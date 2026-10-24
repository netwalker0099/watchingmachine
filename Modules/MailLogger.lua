-- Watching Machine: Mail & Trade Logger Module
-- Long-term logging of items and gold received via mail and trades

local AddonName, WM = ...
local MailLogger = {}
WM:RegisterModule("MailLogger", MailLogger)

MailLogger.version = "2.8"

-- Default settings
local globalDefaults = {
    maxLogEntries = 1000,
    showNotifications = true,
    logGold = true,
    logItems = true,
    logAuctionHouse = true,
    logTrades = true,
    tradeGoldAlerts = true,   -- a chat line whenever gold changes hands in a trade
}

local charDefaults = {
    log = {},
    tradeLog = {},
}

-- State
local isMailboxOpen = false
-- Dedupe guard: fingerprints of takes already logged for the CURRENT inbox
-- state. Wiped on MAIL_INBOX_UPDATE (i.e. whenever the inbox actually
-- changes). Bulk-pull addons retry TakeInboxItem/TakeInboxMoney for the same
-- slot until the server confirms — without this, every retry logged a
-- duplicate entry.
-- (inbox snapshot state lives with the diff logic below)
local currentCharKey = nil
local selectedCharKey = nil
local tradeCache = {}
local isTrading = false
local tradePartner = nil

-- Filter state
local activeFilters = {
    gold = true,
    items = true,
    ah_sale = true,
    ah_purchase = true,
    ah_expired = true,
    ah_cancelled = true,
}

-- ============================================
-- UTILITIES
-- ============================================

local function GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

local function FormatMoney(copper)
    if not copper or copper == 0 then return "0c" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperLeft = copper % 100
    local str = ""
    if gold > 0 then str = str .. gold .. "g " end
    if silver > 0 then str = str .. silver .. "s " end
    if copperLeft > 0 or str == "" then str = str .. copperLeft .. "c" end
    return str:gsub(" $", "")
end

local function GetTimestamp()
    return date("%Y-%m-%d %H:%M:%S")
end

local function GetDateString()
    return date("%Y-%m-%d")
end

function MailLogger:Print(msg)
    WM:ModulePrint("MailLogger", msg)
end

-- ============================================
-- INITIALIZATION
-- ============================================

function MailLogger:Initialize()
    currentCharKey = GetCharacterKey()
    selectedCharKey = currentCharKey
    self:InitDB()
    if WM.RegisterChatLink then
        WM:RegisterChatLink("mltrades", function() MailLogger:ShowTrades() end)
    end
end

function MailLogger:InitDB()
    currentCharKey = currentCharKey or GetCharacterKey()
    selectedCharKey = selectedCharKey or currentCharKey
    if not MailLoggerDB then
        MailLoggerDB = { characters = {} }
    end
    
    for k, v in pairs(globalDefaults) do
        if MailLoggerDB[k] == nil then
            MailLoggerDB[k] = v
        end
    end
    
    if not MailLoggerDB.characters then
        MailLoggerDB.characters = {}
    end
    
    if not MailLoggerDB.characters[currentCharKey] then
        MailLoggerDB.characters[currentCharKey] = {
            log = {},
            tradeLog = {},
        }
    end
end

-- ============================================
-- CHARACTER MANAGEMENT
-- ============================================

function MailLogger:GetCharacterList()
    local chars = {}
    if MailLoggerDB and MailLoggerDB.characters then
        for charKey, _ in pairs(MailLoggerDB.characters) do
            table.insert(chars, charKey)
        end
    end
    table.sort(chars)
    return chars
end

function MailLogger:GetCharacterLog(charKey)
    charKey = charKey or selectedCharKey or currentCharKey
    if MailLoggerDB and MailLoggerDB.characters and MailLoggerDB.characters[charKey] then
        return MailLoggerDB.characters[charKey].log or {}
    end
    return {}
end

function MailLogger:GetCharacterTradeLog(charKey)
    charKey = charKey or selectedCharKey or currentCharKey
    if MailLoggerDB and MailLoggerDB.characters and MailLoggerDB.characters[charKey] then
        return MailLoggerDB.characters[charKey].tradeLog or {}
    end
    return {}
end

-- ============================================
-- STATUS
-- ============================================

function MailLogger:GetQuickStatus()
    local charLog = self:GetCharacterLog(currentCharKey)
    local tradeLog = self:GetCharacterTradeLog(currentCharKey)
    local mailCount = #charLog
    local tradeCount = #tradeLog
    
    return string.format("|cFF00FF00%d|r mail, |cFF00FF00%d|r trades", mailCount, tradeCount)
end

-- ============================================
-- LOGGING
-- ============================================

function MailLogger:AddLogEntry(entryType, data)
    if not MailLoggerDB or not currentCharKey then return end
    if not MailLoggerDB.characters or not MailLoggerDB.characters[currentCharKey] then return end
    
    local entry = {
        type = entryType,
        timestamp = GetTimestamp(),
        date = GetDateString(),
        time_t = time(),
        data = data
    }
    
    local charLog = MailLoggerDB.characters[currentCharKey].log
    if not charLog then return end
    table.insert(charLog, 1, entry)
    
    while #charLog > MailLoggerDB.maxLogEntries do
        table.remove(charLog)
    end
    
    if MailLoggerDB.showNotifications then
        if entryType == "gold" then
            self:Print("Logged: " .. FormatMoney(data.amount) .. " from " .. (data.sender or "Unknown"))
        elseif entryType == "item" then
            local itemStr = data.itemLink or data.itemName or "Unknown Item"
            if data.count and data.count > 1 then
                itemStr = itemStr .. " x" .. data.count
            end
            self:Print("Logged: " .. itemStr .. " from " .. (data.sender or "Unknown"))
        elseif entryType == "ah_sale" then
            self:Print("Logged AH Sale: " .. (data.itemName or "Unknown") .. " for " .. FormatMoney(data.amount))
        end
    end
end

-- Where you are when a trade happens: the instance (and the Instance
-- Tracker run, so a run can show the gold traded during it) or the zone
local function TradePlace()
    local IT = WM:IsModuleOn("InstanceTracker") and WM.modules.InstanceTracker
    local run = IT and IT.Current and IT:Current()
    if run then return run.name, run.id end
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    if inside and (kind == "party" or kind == "raid") and GetInstanceInfo then
        return (GetInstanceInfo()), nil
    end
    return nil, nil
end

-- "received 500g + 2 items, gave 20g"
local function TradeSummary(received, given)
    local parts = {}
    local function Side(label, side)
        if not side then return end
        local bits = {}
        if side.money and side.money > 0 then bits[#bits + 1] = FormatMoney(side.money) end
        if side.items and #side.items > 0 then bits[#bits + 1] = #side.items .. " item(s)" end
        if #bits > 0 then parts[#parts + 1] = label .. " " .. table.concat(bits, " + ") end
    end
    Side("|cFF00FF00received|r", received)
    Side("|cFFFF6600gave|r", given)
    return table.concat(parts, ", ")
end
MailLogger.TradeSummary = TradeSummary

function MailLogger:AddTradeLogEntry(data)
    if not MailLoggerDB or not currentCharKey then return end
    local instance, runId = TradePlace()
    local goldMoved = (data.received.money or 0) > 0 or (data.given.money or 0) > 0

    -- The chat line: always when gold changed hands (unless turned off),
    -- otherwise only with the general notifications on
    if (goldMoved and MailLoggerDB.tradeGoldAlerts) or MailLoggerDB.showNotifications then
        local msg = "Trade with |cFFFFFF00" .. (data.partner or "Unknown") .. "|r: "
            .. TradeSummary(data.received, data.given)
            .. (instance and (" |cFF888888(in " .. instance .. ")|r") or "")
        if WM.ChatLink then msg = WM:ChatLink("mltrades", "", msg) end
        self:Print(msg)
    end

    if not MailLoggerDB.logTrades then return end
    if not MailLoggerDB.characters or not MailLoggerDB.characters[currentCharKey] then return end

    local entry = {
        timestamp = GetTimestamp(),
        date = GetDateString(),
        time_t = time(),
        partner = data.partner,
        received = data.received,
        given = data.given,
        instance = instance,
        runId = runId,
    }

    local tradeLog = MailLoggerDB.characters[currentCharKey].tradeLog
    if not tradeLog then return end
    table.insert(tradeLog, 1, entry)

    while #tradeLog > MailLoggerDB.maxLogEntries do
        table.remove(tradeLog)
    end
    if self.mainFrame and self.mainFrame:IsShown() and self.currentTab == "trades" then self:RefreshTradesLog() end
end

-- Gold traded during an Instance Tracker run: received, given, trade count
function MailLogger:GoldTradedInRun(runId, charKey)
    local received, given, count = 0, 0, 0
    if not runId or not MailLoggerDB or not MailLoggerDB.characters then return 0, 0, 0 end
    local char = MailLoggerDB.characters[charKey or currentCharKey]
    for _, entry in ipairs(char and char.tradeLog or {}) do
        if entry.runId == runId then
            count = count + 1
            received = received + ((entry.received and entry.received.money) or 0)
            given = given + ((entry.given and entry.given.money) or 0)
        end
    end
    return received, given, count
end

-- Open the window on the Trades tab (the trade chat line's link)
function MailLogger:ShowTrades()
    if not WM:UsableModule("MailLogger") then return end
    local frame = self:CreateUI()
    if not frame:IsShown() then frame:Show() end
    self:ShowTab("trades")
end

-- ============================================
-- MAIL HOOKS
-- ============================================
-- Mail data is read LIVE at hook time (the hook runs before the take request
-- goes to the server, so the inbox APIs still return the mail's contents).
-- The old approach used a snapshot cache refreshed 0.1s after
-- MAIL_INBOX_UPDATE — during bulk pulls, mail deletion shifts every index,
-- so takes landed on stale cache entries and logged the wrong (duplicate)
-- mail's data.

-- Capture strategy: DIFF THE INBOX, don't log on take attempts.
--
-- Logging when a take is *requested* cannot be made correct during an
-- "open all": bulk-pull addons retry the same slot until the server answers,
-- and every emptied mail shifts the indices of everything below it. Any key
-- built from an index is therefore unstable, and any guard cleared on
-- MAIL_INBOX_UPDATE is wiped constantly, because that event fires throughout
-- the pull.
--
-- Instead we fingerprint the inbox by CONTENT into a multiset and re-read it
-- periodically while the mailbox is open. Whatever disappeared since the last
-- read was actually collected. That is immune to retries (a retry changes
-- nothing), immune to index shifts (no index in the key), counts N identical
-- mails correctly (multiset counts), and works no matter which API the
-- open-all uses or how fast it runs.

local inboxUnits = {}      -- fingerprint -> count currently in the inbox
local inboxMeta = {}       -- fingerprint -> details needed to write the log line
local snapshotValid = false
local suppressUnits = {}   -- fingerprint -> count to NOT log (returned/deleted)
local diffAccum = 0
local pendingEmpty = false -- an empty read is held one poll before it is trusted
local DIFF_INTERVAL = 0.4  -- seconds between inbox re-reads while open

local function MoneyKey(sender, subject, money)
    return "m|" .. sender .. "|" .. subject .. "|" .. money
end

local function ItemKey(sender, subject, name, count)
    return "i|" .. sender .. "|" .. subject .. "|" .. name .. "|" .. count
end

-- Fingerprint every receivable unit currently in the inbox
local function BuildInboxUnits()
    local units, meta = {}, {}
    local n = GetInboxNumItems() or 0

    for i = 1, n do
        local _, _, sender, subject, money, _, _, hasItem = GetInboxHeaderInfo(i)
        sender  = sender or "?"
        subject = subject or "?"

        local invoiceType, invoiceItemName, invoicePlayerName = GetInboxInvoiceInfo(i)

        if money and money > 0 then
            local key = MoneyKey(sender, subject, money)
            units[key] = (units[key] or 0) + 1
            if not meta[key] then
                meta[key] = {
                    kind = "money", sender = sender, subject = subject, money = money,
                    invoiceType = invoiceType,
                    invoiceItemName = invoiceItemName,
                    invoicePlayerName = invoicePlayerName,
                }
            end
        end

        if hasItem then
            for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local name, _, _, count, quality = GetInboxItem(i, j)
                if name then
                    count = count or 1
                    local key = ItemKey(sender, subject, name, count)
                    units[key] = (units[key] or 0) + 1
                    if not meta[key] then
                        meta[key] = {
                            kind = "item", sender = sender, subject = subject,
                            itemName = name, count = count, quality = quality,
                            itemLink = GetInboxItemLink(i, j),
                            invoiceType = invoiceType,
                        }
                    end
                end
            end
        end
    end

    return units, meta, n
end

function MailLogger:ResetInboxSnapshot()
    wipe(inboxUnits)
    wipe(inboxMeta)
    wipe(suppressUnits)
    snapshotValid = false
    diffAccum = 0
    pendingEmpty = false
end

-- Back-compat: older code/tests called this
function MailLogger:ResetTakeGuard()
    self:ResetInboxSnapshot()
end

-- Write one log line for a unit that left the inbox
function MailLogger:LogReceivedUnit(m)
    if not m or not MailLoggerDB then return end

    if m.kind == "money" then
        if not MailLoggerDB.logGold then return end
        if m.invoiceType == "seller" or m.invoiceType == "seller_temp_invoice" then
            if MailLoggerDB.logAuctionHouse then
                self:AddLogEntry("ah_sale", {
                    sender = m.sender, subject = m.subject, amount = m.money,
                    itemName = m.invoiceItemName, buyer = m.invoicePlayerName,
                })
            end
        else
            self:AddLogEntry("gold", {
                sender = m.sender, subject = m.subject, amount = m.money,
            })
        end
        return
    end

    if not MailLoggerDB.logItems then return end

    if m.invoiceType == "buyer" then
        if MailLoggerDB.logAuctionHouse then
            self:AddLogEntry("ah_purchase", {
                sender = m.sender, itemName = m.itemName,
                itemLink = m.itemLink, count = m.count,
            })
        end
    elseif m.subject and m.subject:find("Auction expired") then
        if MailLoggerDB.logAuctionHouse then
            self:AddLogEntry("ah_expired", {
                itemName = m.itemName, itemLink = m.itemLink, count = m.count,
            })
        end
    else
        self:AddLogEntry("item", {
            sender = m.sender, subject = m.subject, itemName = m.itemName,
            itemLink = m.itemLink, count = m.count, quality = m.quality,
        })
    end
end

-- Re-read the inbox and log whatever vanished since the previous read
function MailLogger:DiffInbox()
    if not isMailboxOpen then return end

    local newUnits, newMeta, n = BuildInboxUnits()

    -- First read after opening: establish the baseline, log nothing
    if not snapshotValid then
        inboxUnits, inboxMeta = newUnits, newMeta
        snapshotValid = true
        return
    end

    -- Emptying the last mail is the normal end of an open-all, so an empty
    -- read usually IS real and must be logged. But a momentary empty read
    -- while the client is catching up would look like "collected everything"
    -- and write a pile of false entries. Hold one poll to tell them apart:
    -- a blip resolves on the next read, a real collection stays empty.
    if n == 0 and next(inboxUnits) ~= nil then
        if not pendingEmpty then
            pendingEmpty = true
            return              -- keep the snapshot, decide next poll
        end
    end
    pendingEmpty = false

    for key, oldCount in pairs(inboxUnits) do
        local gone = oldCount - (newUnits[key] or 0)
        if gone > 0 then
            -- Mail returned to sender or deleted was not "received"
            local suppressed = suppressUnits[key] or 0
            local skip = math.min(suppressed, gone)
            if skip > 0 then
                suppressUnits[key] = suppressed - skip
            end
            for _ = 1, (gone - skip) do
                self:LogReceivedUnit(inboxMeta[key])
            end
        end
    end

    inboxUnits, inboxMeta = newUnits, newMeta
end

-- ============================================
-- MAIL HOOKS
-- ============================================
-- The take functions are no longer hooked for logging — the inbox diff above
-- does that. These hooks only mark mail that is leaving WITHOUT being
-- received, so the diff doesn't record it as income.

function MailLogger:SuppressMail(index)
    if not index or not WM:IsModuleOn("MailLogger") then return end
    local _, _, sender, subject, money, _, _, hasItem = GetInboxHeaderInfo(index)
    sender  = sender or "?"
    subject = subject or "?"

    if money and money > 0 then
        local key = MoneyKey(sender, subject, money)
        suppressUnits[key] = (suppressUnits[key] or 0) + 1
    end
    if hasItem then
        for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local name, _, _, count = GetInboxItem(index, j)
            if name then
                local key = ItemKey(sender, subject, name, count or 1)
                suppressUnits[key] = (suppressUnits[key] or 0) + 1
            end
        end
    end
end

-- Returned or deleted mail isn't logged. Secure hooks (they run after the
-- call; the mail is still readable until the inbox refreshes) rather than
-- replacing the game's functions, which would taint the mailbox.
if hooksecurefunc and ReturnInboxItem then
    hooksecurefunc("ReturnInboxItem", function(index) pcall(MailLogger.SuppressMail, MailLogger, index) end)
end
if hooksecurefunc and DeleteInboxItem then
    hooksecurefunc("DeleteInboxItem", function(index) pcall(MailLogger.SuppressMail, MailLogger, index) end)
end

-- ============================================
-- TRADE TRACKING
-- ============================================

function MailLogger:CacheTrade()
    tradeCache = {
        player = { items = {}, money = GetPlayerTradeMoney() or 0 },
        target = { items = {}, money = GetTargetTradeMoney() or 0 }
    }
    
    for i = 1, 6 do
        local name, texture, quantity = GetTradePlayerItemInfo(i)
        if name then
            local itemLink = GetTradePlayerItemLink(i)
            tradeCache.player.items[i] = { name = name, count = quantity or 1, itemLink = itemLink }
        end
    end
    
    for i = 1, 6 do
        local name, texture, quantity = GetTradeTargetItemInfo(i)
        if name then
            local itemLink = GetTradeTargetItemLink(i)
            tradeCache.target.items[i] = { name = name, count = quantity or 1, itemLink = itemLink }
        end
    end
end

function MailLogger:OnTradeComplete()
    if not isTrading or not tradeCache then return end
    
    local received = { items = {}, money = tradeCache.target.money or 0 }
    local given = { items = {}, money = tradeCache.player.money or 0 }
    
    for i, item in pairs(tradeCache.target.items) do
        table.insert(received.items, { name = item.name, count = item.count, itemLink = item.itemLink })
    end
    
    for i, item in pairs(tradeCache.player.items) do
        table.insert(given.items, { name = item.name, count = item.count, itemLink = item.itemLink })
    end
    
    if received.money > 0 or given.money > 0 or #received.items > 0 or #given.items > 0 then
        self:AddTradeLogEntry({
            partner = tradePartner,
            received = received,
            given = given
        })
    end
end

-- ============================================
-- UI
-- ============================================

local mainFrame = nil

local TABS = {
    { value = "mail", text = "Mail", width = 80 },
    { value = "trades", text = "Trades", width = 80 },
    { value = "summary", text = "Summary", width = 80 },
    { value = "settings", text = "Settings", width = 80 },
}

local LIST_WIDTH = 640

-- Filters only change what the Mail tab lists; they reset on reload
local FILTERS = {
    { key = "gold", label = "Gold", color = "FFD700",
      tip = "Show gold received by mail (auction sale payments have their own filter)." },
    { key = "items", label = "Items", color = "66C7FF",
      tip = "Show items received by mail." },
    { key = "ah_sale", label = "AH Sales", color = "00FF00",
      tip = "Show auction house sale payments." },
    { key = "ah_purchase", label = "AH Buys", color = "FF8000",
      tip = "Show items won at auction." },
    { key = "ah_expired", label = "Expired", color = "B3B3B3",
      tip = "Show expired and cancelled auctions returned by mail." },
}

local SETTINGS = {
    { key = "showNotifications", label = "Show chat notifications",
      tip = "Print a chat line each time gold, an item, an auction sale or a trade is logged." },
    { key = "logGold", label = "Log gold received",
      tip = "Record gold taken from mail. Off also stops auction sale payments being logged." },
    { key = "logItems", label = "Log items received",
      tip = "Record items taken from mail. Off also stops auction purchases and expired auctions being logged." },
    { key = "logAuctionHouse", label = "Log auction house transactions",
      tip = "Record auction sales, purchases and expired auctions. Off: auction house mail isn't logged at all, not even as plain gold or items." },
    { key = "logTrades", label = "Log trades",
      tip = "Record completed trades: who with, the gold and items each side gave, and the instance you were in." },
    { key = "tradeGoldAlerts", label = "Chat line when gold is traded",
      tip = "A line in your chat window whenever you give or receive gold in a trade, with who and where. Click it to open the trade log." },
}

-- A scroll list inside a tab frame; rows are pooled and reused
local function CreateList(parent, top)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, top or 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LIST_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    return scrollChild
end

local function GetListRow(scrollChild, pool, i, height, detailFont)
    local row = pool[i]
    if not row then
        row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

        row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.header:SetPoint("TOPLEFT", 5, -5)

        row.detail = row:CreateFontString(nil, "OVERLAY", detailFont)
        row.detail:SetPoint("TOPLEFT", 5, -20)
        row.detail:SetWidth(LIST_WIDTH - 10)
        row.detail:SetJustifyH("LEFT")
        pool[i] = row
    end
    row:SetSize(LIST_WIDTH, height - 5)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -(i - 1) * height)
    row:SetBackdropColor(0.1, 0.1, 0.1, (i % 2 == 0) and 0.5 or 0)
    row:Show()
    return row
end

local function HideRows(pool, from)
    for i = from, #pool do pool[i]:Hide() end
end

function MailLogger:CreateUI()
    if mainFrame then return mainFrame end

    -- Tab bar and character picker on top; the Mail tab's filters and the
    -- Settings tab's checkboxes are rows shown only on their tab. The lists
    -- and the summary share the Fill area below them.
    local panel = WM.UI:CreatePanel({
        name = "WM_MailLoggerFrame",
        title = "Mail & Trade Logger",
        titleColor = "FF69B4",
        width = 700,
        height = 500,
        minHeight = 300,
        scroll = false,
        onShow = function() MailLogger:RefreshCurrentTab() end,
    })
    local L = panel.layout

    local row = L:Row(30)
    self.tabChoice = row:Choice({
        options = TABS,
        get = function() return MailLogger.currentTab end,
        set = function(v) MailLogger:ShowTab(v) end,
    }, 8)
    self.charDropdown = row:Dropdown({
        name = "WM_MailLoggerCharDropdown",
        label = "Character:",
        width = 150,
        placeholder = "Select",
        options = function()
            local opts = {}
            for _, charKey in ipairs(MailLogger:GetCharacterList()) do
                opts[#opts + 1] = { value = charKey, text = charKey }
            end
            return opts
        end,
        get = function() return selectedCharKey or currentCharKey end,
        set = function(v)
            selectedCharKey = v
            MailLogger:RefreshCurrentTab()
        end,
        tooltip = { "Character", "Show the logs of another of your characters. Each character's mail and trades are recorded while you play it." },
    }, 380)

    -- Mail tab: filter toggles
    row = L:Row(26)
    row:Text({ text = "Filters:", font = "GameFontNormalSmall" }, 8)
    self.filterRow = row
    self.filterCheckboxes = {}
    for i, filter in ipairs(FILTERS) do
        self.filterCheckboxes[filter.key] = row:Checkbox({
            label = "|cFF" .. filter.color .. filter.label .. "|r",
            get = function() return activeFilters[filter.key] end,
            set = function(v)
                activeFilters[filter.key] = v
                MailLogger:RefreshMailLog()
            end,
            tooltip = { filter.label, filter.tip, { "Filters only change this list and reset when you reload." } },
        }, 60 + (i - 1) * 105)
    end

    -- Settings tab
    self.settingsRows = {}
    self.settingsCheckboxes = {}
    for _, s in ipairs(SETTINGS) do
        local cb, srow = L:Checkbox({
            label = s.label,
            get = function() return MailLoggerDB[s.key] end,
            set = function(v) MailLoggerDB[s.key] = v end,
            tooltip = { s.label, s.tip },
        })
        self.settingsCheckboxes[s.key] = cb
        self.settingsRows[#self.settingsRows + 1] = srow
    end

    -- One frame per tab in the remaining space
    local fill = L:Fill(150)

    local mailTab = CreateFrame("Frame", nil, fill)
    mailTab:SetAllPoints()
    self.mailTab = mailTab
    self.mailScrollChild = CreateList(mailTab)
    self.mailRows = {}

    local tradesTab = CreateFrame("Frame", nil, fill)
    tradesTab:SetAllPoints()
    self.tradesTab = tradesTab
    self.tradesScrollChild = CreateList(tradesTab)
    self.tradeRows = {}

    local summaryTab = CreateFrame("Frame", nil, fill)
    summaryTab:SetAllPoints()
    self.summaryTab = summaryTab
    local summaryText = summaryTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryText:SetPoint("TOPLEFT", 10, -10)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWidth(650)
    self.summaryText = summaryText

    -- The settings live in rows above the Fill; this frame keeps ShowTab uniform
    local settingsTab = CreateFrame("Frame", nil, fill)
    settingsTab:SetAllPoints()
    self.settingsTab = settingsTab

    mainFrame = panel
    self.mainFrame = panel

    self:ShowTab("mail")
    panel:Finish()
    return panel
end

function MailLogger:ShowTab(tabName)
    self.mailTab:Hide()
    self.tradesTab:Hide()
    self.summaryTab:Hide()
    self.settingsTab:Hide()
    self.currentTab = tabName

    self.filterRow.hidden = tabName ~= "mail"
    for _, row in ipairs(self.settingsRows) do
        row.hidden = tabName ~= "settings"
    end

    if tabName == "mail" then
        self.mailTab:Show()
        self:RefreshMailLog()
    elseif tabName == "trades" then
        self.tradesTab:Show()
        self:RefreshTradesLog()
    elseif tabName == "summary" then
        self.summaryTab:Show()
        self:RefreshSummary()
    elseif tabName == "settings" then
        self.settingsTab:Show()
    end

    self.tabChoice:Refresh()
    mainFrame:Reflow()
end

function MailLogger:RefreshCurrentTab()
    if self.currentTab then
        self:ShowTab(self.currentTab)
    end
end

function MailLogger:RefreshMailLog()
    if not self.mailScrollChild then return end

    local entryHeight = 50
    local charLog = self:GetCharacterLog()
    local displayCount = 0

    for i, entry in ipairs(charLog) do
        if displayCount > 100 then break end

        -- Check filters
        local showEntry = false
        if entry.type == "gold" and activeFilters.gold then
            showEntry = true
        elseif entry.type == "item" and activeFilters.items then
            showEntry = true
        elseif entry.type == "ah_sale" and activeFilters.ah_sale then
            showEntry = true
        elseif entry.type == "ah_purchase" and activeFilters.ah_purchase then
            showEntry = true
        elseif entry.type == "ah_expired" and activeFilters.ah_expired then
            showEntry = true
        elseif entry.type == "ah_cancelled" and activeFilters.ah_expired then
            showEntry = true
        end

        if showEntry then
            displayCount = displayCount + 1
            local row = GetListRow(self.mailScrollChild, self.mailRows, displayCount, entryHeight, "GameFontHighlight")
            row.header:SetText("|cFF888888" .. (entry.timestamp or "") .. "|r")

            local text = ""
            if entry.type == "gold" then
                text = "|cFFFFD700[Gold]|r " .. FormatMoney(entry.data.amount) .. " from " .. (entry.data.sender or "Unknown")
            elseif entry.type == "item" then
                local itemStr = entry.data.itemLink or entry.data.itemName or "Item"
                if entry.data.count and entry.data.count > 1 then
                    itemStr = itemStr .. " x" .. entry.data.count
                end
                text = "|cFF00FF00[Item]|r " .. itemStr .. " from " .. (entry.data.sender or "Unknown")
            elseif entry.type == "ah_sale" then
                text = "|cFF00FF00[AH Sale]|r " .. (entry.data.itemName or "Item") .. " for " .. FormatMoney(entry.data.amount)
            elseif entry.type == "ah_purchase" then
                text = "|cFF00BFFF[AH Buy]|r " .. (entry.data.itemName or "Item")
            elseif entry.type == "ah_expired" or entry.type == "ah_cancelled" then
                text = "|cFFFF6600[AH Expired]|r " .. (entry.data.itemName or "Item")
            end
            row.detail:SetText(text)
        end
    end

    HideRows(self.mailRows, displayCount + 1)
    self.mailScrollChild:SetHeight(math.max(displayCount * entryHeight, 1))
end

function MailLogger:RefreshTradesLog()
    if not self.tradesScrollChild then return end

    local entryHeight = 60
    local tradeLog = self:GetCharacterTradeLog()
    local shown = 0

    for i, entry in ipairs(tradeLog) do
        if i > 100 then break end
        shown = i

        local row = GetListRow(self.tradesScrollChild, self.tradeRows, i, entryHeight, "GameFontHighlightSmall")
        row.header:SetText("|cFF888888" .. (entry.timestamp or "") .. "|r Trade with |cFFFFFF00" .. (entry.partner or "Unknown") .. "|r"
            .. (entry.instance and ("  |cFF66CCFFin " .. entry.instance .. "|r") or ""))

        local receivedStr = ""
        if entry.received then
            if entry.received.money > 0 then
                receivedStr = FormatMoney(entry.received.money)
            end
            if entry.received.items and #entry.received.items > 0 then
                if receivedStr ~= "" then receivedStr = receivedStr .. ", " end
                receivedStr = receivedStr .. #entry.received.items .. " item(s)"
            end
        end

        local givenStr = ""
        if entry.given then
            if entry.given.money > 0 then
                givenStr = FormatMoney(entry.given.money)
            end
            if entry.given.items and #entry.given.items > 0 then
                if givenStr ~= "" then givenStr = givenStr .. ", " end
                givenStr = givenStr .. #entry.given.items .. " item(s)"
            end
        end

        local text = ""
        if receivedStr ~= "" then text = text .. "|cFF00FF00Received:|r " .. receivedStr end
        if givenStr ~= "" then
            if text ~= "" then text = text .. "  " end
            text = text .. "|cFFFF6600Gave:|r " .. givenStr
        end
        row.detail:SetText(text)
    end

    HideRows(self.tradeRows, shown + 1)
    self.tradesScrollChild:SetHeight(math.max(shown * entryHeight, 1))
end

function MailLogger:RefreshSummary()
    if not self.summaryText then return end
    
    local charLog = self:GetCharacterLog()
    local tradeLog = self:GetCharacterTradeLog()
    
    local totalGold = 0
    local itemCount = 0
    local ahSales = 0
    local ahPurchases = 0
    
    for _, entry in ipairs(charLog) do
        if entry.type == "gold" then
            totalGold = totalGold + (entry.data.amount or 0)
        elseif entry.type == "item" then
            itemCount = itemCount + (entry.data.count or 1)
        elseif entry.type == "ah_sale" then
            ahSales = ahSales + (entry.data.amount or 0)
        end
    end
    
    local text = string.format([[
|cFFFFFF00Summary for %s|r

|cFFFFD700Mail Log:|r
  Total entries: %d
  Gold received: %s
  Items received: %d
  AH Sales total: %s

|cFF00FF00Trade Log:|r
  Total trades: %d
]], selectedCharKey or currentCharKey, #charLog, FormatMoney(totalGold), itemCount, FormatMoney(ahSales), #tradeLog)
    
    self.summaryText:SetText(text)
end

function MailLogger:ToggleUI()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()   -- OnShow refreshes the picker and the current tab
    end
end

function MailLogger:Toggle()
    self:ToggleUI()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_CLOSED")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_CLOSED")
eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
eventFrame:RegisterEvent("UI_INFO_MESSAGE")

local tradeSuccessful = false

-- Poll the inbox while the mailbox is open. An open-all fires MAIL_INBOX_UPDATE
-- far too often to diff on, and may finish a burst between any two events, so a
-- steady re-read is both cheaper and more reliable.
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if not isMailboxOpen or not WM:IsModuleOn("MailLogger") then return end
    diffAccum = diffAccum + elapsed
    if diffAccum < DIFF_INTERVAL then return end
    diffAccum = 0
    pcall(MailLogger.DiffInbox, MailLogger)
end)

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    -- Registered at load: does nothing while it's off on this character
    if not WM:IsModuleOn("MailLogger") then return end
    if event == "MAIL_SHOW" then
        isMailboxOpen = true
        MailLogger:ResetInboxSnapshot()

    elseif event == "MAIL_INBOX_UPDATE" then
        -- Nothing to do here: the periodic diff below picks the change up.
        -- Acting on this event directly is what broke before, because it
        -- fires continuously throughout an open-all.

    elseif event == "MAIL_CLOSED" then
        -- Deliberately no final diff. Once the mailbox closes the client may
        -- report an empty inbox, which would look like "everything was
        -- collected" and write a pile of false entries.
        isMailboxOpen = false
        MailLogger:ResetInboxSnapshot()

    elseif event == "TRADE_SHOW" then
        isTrading = true
        tradeSuccessful = false
        tradePartner = UnitName("NPC") or "Unknown"
        MailLogger:CacheTrade()
        
    elseif event == "TRADE_ACCEPT_UPDATE" then
        MailLogger:CacheTrade()
        
    elseif event == "UI_INFO_MESSAGE" then
        -- ERR_TRADE_COMPLETE is the client's own "Trade complete." text
        local complete = type(ERR_TRADE_COMPLETE) == "string" and ERR_TRADE_COMPLETE or "Trade complete"
        if type(arg2) == "string" and (arg2 == complete or arg2:find("Trade complete", 1, true)) then
            tradeSuccessful = true
        end
        
    elseif event == "TRADE_CLOSED" then
        if isTrading and tradeSuccessful then
            MailLogger:OnTradeComplete()
        end
        isTrading = false
        tradeCache = {}
        tradePartner = nil
        tradeSuccessful = false
    end
end)

-- Turned off: close the window and forget the mailbox or trade in progress
-- (turned on again with the mailbox open, it starts with the next visit)
function MailLogger:OnModuleOff()
    if mainFrame then mainFrame:Hide() end
    isMailboxOpen = false
    self:ResetInboxSnapshot()
    isTrading = false
    tradeCache = {}
    tradePartner = nil
    tradeSuccessful = false
end

-- The module's page in the guided setup
function MailLogger:SetupPage(L)
    self:InitDB()
    L:Note("Keeps a record, on each of your characters, of the gold and items you take from the mailbox and of"
        .. " every trade, so you can look back at who sent or traded you what, and when.")
    L:Note("|cFFFFFFFFHow it works:|r while the mailbox is open it watches the inbox; whatever you take out is"
        .. " logged (mail you return or delete isn't). Auction house mail is sorted into sales, purchases and"
        .. " expired auctions. A finished trade logs who with, the gold and items each side gave, and the"
        .. " instance you were in.")
    for _, s in ipairs(SETTINGS) do
        L:Checkbox({ label = s.label, get = function() return MailLoggerDB[s.key] end,
            set = function(v) MailLoggerDB[s.key] = v end, tooltip = { s.label, s.tip } })
    end
    L:Note(function()
        if WM:IsModuleOn("InstanceTracker") then
            return "With Instance Tracker on, a trade made during a dungeon or raid run shows on that run's tooltip."
        end
        return "|cFF888888With Instance Tracker on too, trades are tagged with the dungeon or raid run they happened in.|r"
    end)
    L:Note("The logs, a summary and another character's records are in its window: |cFFFFFF00/wmachine mail|r.")
end
