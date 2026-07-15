-- Watching Machine: Mail & Trade Logger Module
-- Long-term logging of items and gold received via mail and trades

local AddonName, WM = ...
local MailLogger = {}
WM:RegisterModule("MailLogger", MailLogger)

MailLogger.version = "2.0"

-- Default settings
local globalDefaults = {
    maxLogEntries = 1000,
    showNotifications = true,
    logGold = true,
    logItems = true,
    logAuctionHouse = true,
    logTrades = true,
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
local loggedTakes = {}
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
end

function MailLogger:InitDB()
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

function MailLogger:AddTradeLogEntry(data)
    if not MailLoggerDB or not currentCharKey then return end
    if not MailLoggerDB.logTrades then return end
    if not MailLoggerDB.characters or not MailLoggerDB.characters[currentCharKey] then return end
    
    local entry = {
        timestamp = GetTimestamp(),
        date = GetDateString(),
        time_t = time(),
        partner = data.partner,
        received = data.received,
        given = data.given,
    }
    
    local tradeLog = MailLoggerDB.characters[currentCharKey].tradeLog
    if not tradeLog then return end
    table.insert(tradeLog, 1, entry)
    
    while #tradeLog > MailLoggerDB.maxLogEntries do
        table.remove(tradeLog)
    end
    
    if MailLoggerDB.showNotifications then
        local msg = "Trade with " .. (data.partner or "Unknown")
        if data.received.money > 0 then
            msg = msg .. " | Received: " .. FormatMoney(data.received.money)
        end
        if #data.received.items > 0 then
            msg = msg .. " + " .. #data.received.items .. " item(s)"
        end
        self:Print(msg)
    end
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

-- Clear the dedupe guard whenever the inbox state changes
function MailLogger:ResetTakeGuard()
    wipe(loggedTakes)
end

-- Log the gold attached to a mail (called from the take hooks)
function MailLogger:LogMoneyTake(index)
    if not MailLoggerDB or not MailLoggerDB.logGold then return end

    local _, _, sender, subject, money = GetInboxHeaderInfo(index)
    if not money or money <= 0 then return end

    -- Dedupe: same slot + same content = a retry of the same take
    local key = "money:" .. index .. ":" .. (sender or "?") .. ":" .. (subject or "?") .. ":" .. money
    if loggedTakes[key] then return end
    loggedTakes[key] = true

    local invoiceType, invoiceItemName, invoicePlayerName = GetInboxInvoiceInfo(index)

    if invoiceType == "seller" or invoiceType == "seller_temp_invoice" then
        if MailLoggerDB.logAuctionHouse then
            self:AddLogEntry("ah_sale", {
                sender = sender,
                subject = subject,
                amount = money,
                itemName = invoiceItemName,
                buyer = invoicePlayerName,
            })
        end
    else
        self:AddLogEntry("gold", {
            sender = sender,
            subject = subject,
            amount = money
        })
    end
end

-- Log one attachment slot of a mail (called from the take hooks)
function MailLogger:LogItemTake(mailIndex, itemIndex)
    if not MailLoggerDB or not MailLoggerDB.logItems then return end

    -- TBC Anniversary API: name, itemID, texture, count, quality, canUse
    local name, _, _, count, quality = GetInboxItem(mailIndex, itemIndex)
    if not name then return end
    count = count or 1

    local _, _, sender, subject = GetInboxHeaderInfo(mailIndex)

    local key = "item:" .. mailIndex .. ":" .. itemIndex .. ":" .. (sender or "?") .. ":" .. (subject or "?") .. ":" .. name .. ":" .. count
    if loggedTakes[key] then return end
    loggedTakes[key] = true

    local itemLink = GetInboxItemLink(mailIndex, itemIndex)
    local invoiceType = GetInboxInvoiceInfo(mailIndex)

    if invoiceType == "buyer" then
        if MailLoggerDB.logAuctionHouse then
            self:AddLogEntry("ah_purchase", {
                sender = sender,
                itemName = name,
                itemLink = itemLink,
                count = count,
            })
        end
    elseif subject and subject:find("Auction expired") then
        if MailLoggerDB.logAuctionHouse then
            self:AddLogEntry("ah_expired", {
                itemName = name,
                itemLink = itemLink,
                count = count
            })
        end
    else
        self:AddLogEntry("item", {
            sender = sender,
            subject = subject,
            itemName = name,
            itemLink = itemLink,
            count = count,
            quality = quality
        })
    end
end

-- Hook TakeInboxMoney
local originalTakeInboxMoney = TakeInboxMoney
function TakeInboxMoney(index, ...)
    pcall(MailLogger.LogMoneyTake, MailLogger, index)
    return originalTakeInboxMoney(index, ...)
end

-- Hook TakeInboxItem
local originalTakeInboxItem = TakeInboxItem
function TakeInboxItem(mailIndex, itemIndex, ...)
    pcall(MailLogger.LogItemTake, MailLogger, mailIndex, itemIndex)
    return originalTakeInboxItem(mailIndex, itemIndex, ...)
end

-- Hook AutoLootMailItem — the Anniversary client's "Open All Mail" button
-- loots through this function, not TakeInboxItem, so those pulls were
-- previously never logged.
if AutoLootMailItem then
    local originalAutoLootMailItem = AutoLootMailItem
    function AutoLootMailItem(index, ...)
        pcall(function()
            MailLogger:LogMoneyTake(index)
            local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(index)
            if hasItem then
                for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                    MailLogger:LogItemTake(index, j)
                end
            end
        end)
        return originalAutoLootMailItem(index, ...)
    end
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

function MailLogger:CreateUI()
    if mainFrame then return mainFrame end
    
    local frame = CreateFrame("Frame", "WM_MailLoggerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(700, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    frame:SetFrameStrata("HIGH")
    
    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFF69B4Mail & Trade Logger|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    -- Tab buttons
    local tabs = {"Mail", "Trades", "Summary", "Settings"}
    local tabButtons = {}
    
    for i, tabName in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
        btn:SetSize(80, 25)
        if i == 1 then
            btn:SetPoint("TOPLEFT", 20, -40)
        else
            btn:SetPoint("LEFT", tabButtons[i-1], "RIGHT", 5, 0)
        end
        btn:SetText(tabName)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetScript("OnClick", function()
            MailLogger:ShowTab(tabName:lower())
        end)
        tabButtons[i] = btn
    end
    
    self.tabButtons = tabButtons
    
    -- Character selector
    local charLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charLabel:SetPoint("TOPLEFT", 20, -75)
    charLabel:SetText("Character:")
    
    local charDropdown = CreateFrame("Frame", "WM_MailLoggerCharDropdown", frame, "UIDropDownMenuTemplate")
    charDropdown:SetPoint("LEFT", charLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(charDropdown, 150)
    
    local function CharDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local chars = MailLogger:GetCharacterList()
        
        for _, charKey in ipairs(chars) do
            info.text = charKey
            info.value = charKey
            info.checked = (charKey == selectedCharKey)
            info.func = function(self)
                selectedCharKey = self.value
                UIDropDownMenu_SetText(charDropdown, selectedCharKey)
                MailLogger:RefreshCurrentTab()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    
    UIDropDownMenu_Initialize(charDropdown, CharDropdown_Initialize)
    UIDropDownMenu_SetText(charDropdown, selectedCharKey or currentCharKey or "Select")
    self.charDropdown = charDropdown
    
    -- Content area
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", 15, -100)
    contentFrame:SetPoint("BOTTOMRIGHT", -15, 15)
    self.contentFrame = contentFrame
    
    -- Create tab frames
    self:CreateMailTab()
    self:CreateTradesTab()
    self:CreateSummaryTab()
    self:CreateSettingsTab()
    
    mainFrame = frame
    self.mainFrame = frame
    
    self:ShowTab("mail")
    
    return frame
end

function MailLogger:CreateMailTab()
    local tab = CreateFrame("Frame", nil, self.contentFrame)
    tab:SetAllPoints()
    tab:Hide()
    self.mailTab = tab
    
    -- Filter buttons at top
    local filterFrame = CreateFrame("Frame", nil, tab)
    filterFrame:SetPoint("TOPLEFT", 5, -5)
    filterFrame:SetPoint("TOPRIGHT", -25, -5)
    filterFrame:SetHeight(25)
    
    local filterLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("LEFT", 0, 0)
    filterLabel:SetText("Filters:")
    
    local filters = {
        {key = "gold", label = "Gold", color = {1, 0.84, 0}},
        {key = "items", label = "Items", color = {0.4, 0.78, 1}},
        {key = "ah_sale", label = "AH Sales", color = {0, 1, 0}},
        {key = "ah_purchase", label = "AH Buys", color = {1, 0.5, 0}},
        {key = "ah_expired", label = "Expired", color = {0.7, 0.7, 0.7}},
    }
    
    local xOffset = 45
    self.filterButtons = {}
    
    for _, filter in ipairs(filters) do
        local btn = CreateFrame("Button", nil, filterFrame)
        btn:SetSize(65, 20)
        btn:SetPoint("LEFT", xOffset, 0)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(filter.color[1] * 0.3, filter.color[2] * 0.3, filter.color[3] * 0.3, 0.8)
        btn.bg = bg
        btn.activeColor = filter.color
        
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(filter.label)
        btn.label = label
        
        btn.filterKey = filter.key
        btn.isActive = true
        
        btn:SetScript("OnClick", function(self)
            self.isActive = not self.isActive
            activeFilters[self.filterKey] = self.isActive
            
            -- Also toggle related ah_ filters for simplified "AH" concept
            if self.filterKey == "ah_sale" or self.filterKey == "ah_purchase" or self.filterKey == "ah_expired" then
                -- Individual AH filter toggled
            end
            
            if self.isActive then
                self.bg:SetColorTexture(self.activeColor[1] * 0.3, self.activeColor[2] * 0.3, self.activeColor[3] * 0.3, 0.8)
                self.label:SetTextColor(1, 1, 1)
            else
                self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
                self.label:SetTextColor(0.5, 0.5, 0.5)
            end
            
            MailLogger:RefreshMailDisplay()
        end)
        
        btn:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(self.activeColor[1] * 0.5, self.activeColor[2] * 0.5, self.activeColor[3] * 0.5, 0.9)
        end)
        btn:SetScript("OnLeave", function(self)
            if self.isActive then
                self.bg:SetColorTexture(self.activeColor[1] * 0.3, self.activeColor[2] * 0.3, self.activeColor[3] * 0.3, 0.8)
            else
                self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
            end
        end)
        
        self.filterButtons[filter.key] = btn
        xOffset = xOffset + 68
    end
    
    -- Scroll frame (moved down to account for filter bar)
    local scrollFrame = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() - 10)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    
    self.mailScrollChild = scrollChild
end

function MailLogger:CreateTradesTab()
    local tab = CreateFrame("Frame", nil, self.contentFrame)
    tab:SetAllPoints()
    tab:Hide()
    self.tradesTab = tab
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() - 10)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    
    self.tradesScrollChild = scrollChild
end

function MailLogger:CreateSummaryTab()
    local tab = CreateFrame("Frame", nil, self.contentFrame)
    tab:SetAllPoints()
    tab:Hide()
    self.summaryTab = tab
    
    local summaryText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryText:SetPoint("TOPLEFT", 10, -10)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWidth(650)
    self.summaryText = summaryText
end

function MailLogger:CreateSettingsTab()
    local tab = CreateFrame("Frame", nil, self.contentFrame)
    tab:SetAllPoints()
    tab:Hide()
    self.settingsTab = tab
    
    local yOffset = -10
    local checkboxes = {}
    
    local function CreateSettingCheckbox(name, label, dbKey)
        local cb = CreateFrame("CheckButton", nil, tab, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 10, yOffset)
        cb.Text:SetText(label)
        cb:SetChecked(MailLoggerDB[dbKey])
        cb:SetScript("OnClick", function(self)
            MailLoggerDB[dbKey] = self:GetChecked()
        end)
        checkboxes[name] = cb
        yOffset = yOffset - 30
    end
    
    CreateSettingCheckbox("notifications", "Show chat notifications", "showNotifications")
    CreateSettingCheckbox("gold", "Log gold received", "logGold")
    CreateSettingCheckbox("items", "Log items received", "logItems")
    CreateSettingCheckbox("ah", "Log auction house transactions", "logAuctionHouse")
    CreateSettingCheckbox("trades", "Log trades", "logTrades")
    
    self.settingsCheckboxes = checkboxes
end

function MailLogger:ShowTab(tabName)
    self.mailTab:Hide()
    self.tradesTab:Hide()
    self.summaryTab:Hide()
    self.settingsTab:Hide()
    
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
    
    self.currentTab = tabName
end

function MailLogger:RefreshCurrentTab()
    if self.currentTab then
        self:ShowTab(self.currentTab)
    end
end

function MailLogger:RefreshMailLog()
    if not self.mailScrollChild then return end
    
    for _, child in ipairs({self.mailScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = 0
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
            
            local entryFrame = CreateFrame("Frame", nil, self.mailScrollChild, "BackdropTemplate")
            entryFrame:SetSize(640, entryHeight - 5)
            entryFrame:SetPoint("TOPLEFT", 0, -yOffset)
            
            if displayCount % 2 == 0 then
                entryFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                entryFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            end
            
            local timestamp = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timestamp:SetPoint("TOPLEFT", 5, -5)
            timestamp:SetText("|cFF888888" .. (entry.timestamp or "") .. "|r")
            
            local content = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            content:SetPoint("TOPLEFT", 5, -20)
            content:SetWidth(630)
            content:SetJustifyH("LEFT")
            
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
            content:SetText(text)
            
            yOffset = yOffset + entryHeight
        end
    end
    
    self.mailScrollChild:SetHeight(math.max(yOffset, 1))
end

-- Alias for filter button callback
function MailLogger:RefreshMailDisplay()
    self:RefreshMailLog()
end

function MailLogger:RefreshTradesLog()
    if not self.tradesScrollChild then return end
    
    for _, child in ipairs({self.tradesScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = 0
    local entryHeight = 60
    local tradeLog = self:GetCharacterTradeLog()
    
    for i, entry in ipairs(tradeLog) do
        if i > 100 then break end
        
        local entryFrame = CreateFrame("Frame", nil, self.tradesScrollChild, "BackdropTemplate")
        entryFrame:SetSize(640, entryHeight - 5)
        entryFrame:SetPoint("TOPLEFT", 0, -yOffset)
        
        if i % 2 == 0 then
            entryFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            entryFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        end
        
        local timestamp = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timestamp:SetPoint("TOPLEFT", 5, -5)
        timestamp:SetText("|cFF888888" .. (entry.timestamp or "") .. "|r Trade with |cFFFFFF00" .. (entry.partner or "Unknown") .. "|r")
        
        local details = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        details:SetPoint("TOPLEFT", 5, -20)
        details:SetWidth(630)
        details:SetJustifyH("LEFT")
        
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
        details:SetText(text)
        
        yOffset = yOffset + entryHeight
    end
    
    self.tradesScrollChild:SetHeight(math.max(yOffset, 1))
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
        frame:Show()
        UIDropDownMenu_SetText(self.charDropdown, selectedCharKey or currentCharKey)
        self:RefreshCurrentTab()
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

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "MAIL_SHOW" then
        isMailboxOpen = true
        MailLogger:ResetTakeGuard()

    elseif event == "MAIL_INBOX_UPDATE" then
        -- Inbox contents changed (mail looted/deleted, indices shifted) —
        -- previously-seen slot fingerprints no longer describe the same mail
        MailLogger:ResetTakeGuard()

    elseif event == "MAIL_CLOSED" then
        isMailboxOpen = false
        MailLogger:ResetTakeGuard()

    elseif event == "TRADE_SHOW" then
        isTrading = true
        tradeSuccessful = false
        tradePartner = UnitName("NPC") or "Unknown"
        MailLogger:CacheTrade()
        
    elseif event == "TRADE_ACCEPT_UPDATE" then
        MailLogger:CacheTrade()
        
    elseif event == "UI_INFO_MESSAGE" then
        if arg2 and arg2:find("Trade complete") then
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
