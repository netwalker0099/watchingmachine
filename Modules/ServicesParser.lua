-- Watching Machine: Services Parser Module
-- Parse services channel for boost advertisements by dungeon

local AddonName, WM = ...
local ServicesParser = {}
WM:RegisterModule("ServicesParser", ServicesParser)

ServicesParser.version = "2.0"

-- Dungeon categories (Classic + TBC)
local DUNGEONS = {
    -- Classic Dungeons
    { key = "RFC", name = "Ragefire Chasm", patterns = {"rfc", "ragefire"}, levelRange = "13-18" },
    { key = "SFK", name = "Shadowfang Keep", patterns = {"sfk", "shadowfang"}, levelRange = "22-30" },
    { key = "SM", name = "Scarlet Monastery", patterns = {"sm", "scarlet", "monastery", "cath", "armory", "library", "graveyard"}, levelRange = "26-45" },
    { key = "MARA", name = "Maraudon", patterns = {"mara", "maraudon"}, levelRange = "40-52" },
    { key = "LBRS", name = "Lower Blackrock Spire", patterns = {"lbrs", "lower blackrock", "lower brs"}, levelRange = "55-60" },
    { key = "ZG", name = "Zul'Gurub", patterns = {"zg", "zul'gurub", "zulgurub", "zul gurub"}, levelRange = "58-60" },
    { key = "STRAT", name = "Stratholme", patterns = {"strat", "stratholme", "ud", "live"}, levelRange = "58-60" },
    -- TBC Dungeons
    { key = "RAMP", name = "Hellfire Ramparts", patterns = {"ramp", "ramparts", "hellfire rampart"}, levelRange = "60-62" },
    { key = "BF", name = "Blood Furnace", patterns = {"bf", "blood furnace", "furnace"}, levelRange = "61-63" },
    { key = "SP", name = "Slave Pens", patterns = {"sp", "slave pens", "slavepens", "pens"}, levelRange = "62-64" },
    { key = "UB", name = "Underbog", patterns = {"ub", "underbog", "bog"}, levelRange = "63-65" },
    { key = "MT", name = "Mana Tombs", patterns = {"mt", "mana tombs", "manatombs", "tombs"}, levelRange = "64-66" },
    { key = "SH", name = "Shattered Halls", patterns = {"sh", "shattered halls", "shatt halls", "shat hall"}, levelRange = "70" },
    { key = "SL", name = "Shadow Labyrinth", patterns = {"sl", "shadow lab", "slabs", "slab", "labyrinth"}, levelRange = "70" },
    { key = "BOTA", name = "Botanica", patterns = {"bota", "botanica", "bot"}, levelRange = "70" },
    { key = "MECH", name = "Mechanar", patterns = {"mech", "mechanar"}, levelRange = "70" },
    { key = "ARCA", name = "Arcatraz", patterns = {"arca", "arcatraz", "arc"}, levelRange = "70" },
}

local SUMMON_PATTERNS = {"summon", "summons", "summoning", "port", "portal", "sum ", " sum", "sums"}

-- Default settings
local defaults = {
    messageDuration = 60,
    channelName = "services",
    playSound = false,
}

-- State
local messages = {}
local mainFrame = nil
local tabChoices = {}    -- the two rows of tab buttons
local tabCounts = {}     -- listing count on each tab, by key
local currentTab = "SM"
local updateTimer = 0

-- Initialize message tables immediately
for _, dungeon in ipairs(DUNGEONS) do
    messages[dungeon.key] = {}
end
messages["SUMMONS"] = {}

-- ============================================
-- INITIALIZATION
-- ============================================

function ServicesParser:Initialize()
    self:InitDB()
    self:InitMessageTables()
end

function ServicesParser:InitDB()
    if not ServicesParserDB then
        ServicesParserDB = {}
    end
    for k, v in pairs(defaults) do
        if ServicesParserDB[k] == nil then
            ServicesParserDB[k] = v
        end
    end
end

function ServicesParser:InitMessageTables()
    -- Clear all message tables
    for key, _ in pairs(messages) do
        messages[key] = {}
    end
end

-- ============================================
-- UTILITIES
-- ============================================

function ServicesParser:Print(msg)
    WM:ModulePrint("ServicesParser", msg)
end

local function GetTime()
    return time()
end

local function MatchDungeon(text)
    local lowerText = text:lower()
    for _, dungeon in ipairs(DUNGEONS) do
        for _, pattern in ipairs(dungeon.patterns) do
            if lowerText:find(pattern, 1, true) then
                return dungeon.key
            end
        end
    end
    return nil
end

local function IsSummonMessage(text)
    local lowerText = text:lower()
    for _, pattern in ipairs(SUMMON_PATTERNS) do
        if lowerText:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

local function GetMessageKey(sender, text)
    return sender .. ":" .. text:lower():gsub("%s+", " "):sub(1, 100)
end

-- ============================================
-- STATUS
-- ============================================

function ServicesParser:GetQuickStatus()
    local total = 0
    for _, msgList in pairs(messages) do
        total = total + #msgList
    end
    
    if total > 0 then
        return "|cFF00FF00" .. total .. "|r listings tracked"
    else
        return "|cFF888888No listings|r"
    end
end

-- ============================================
-- MESSAGE HANDLING
-- ============================================

function ServicesParser:AddMessage(sender, text, channel)
    if not sender or not text or text == "" then return end
    
    local dungeonKey = MatchDungeon(text)
    local isSummon = IsSummonMessage(text)
    
    if not dungeonKey and not isSummon then return end
    
    local msgKey = GetMessageKey(sender, text)
    local timestamp = GetTime()
    
    local entry = {
        sender = sender,
        text = text,
        timestamp = timestamp,
        expireTime = timestamp + (ServicesParserDB and ServicesParserDB.messageDuration or 60),
        key = msgKey,
    }
    
    -- Add to summons if matches
    if isSummon then
        -- Ensure table exists
        if not messages["SUMMONS"] then messages["SUMMONS"] = {} end
        
        local isDupe = false
        for i, msg in ipairs(messages["SUMMONS"]) do
            if msg.key == msgKey then
                messages["SUMMONS"][i] = entry
                isDupe = true
                break
            end
        end
        if not isDupe then
            table.insert(messages["SUMMONS"], 1, entry)
        end
    end
    
    -- Add to dungeon category
    if dungeonKey then
        -- Ensure table exists
        if not messages[dungeonKey] then messages[dungeonKey] = {} end
        
        local isDupe = false
        for i, msg in ipairs(messages[dungeonKey]) do
            if msg.key == msgKey then
                messages[dungeonKey][i] = entry
                isDupe = true
                break
            end
        end
        if not isDupe then
            table.insert(messages[dungeonKey], 1, entry)
        end
    end
    
    if ServicesParserDB and ServicesParserDB.playSound then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end
    
    if mainFrame and mainFrame:IsShown() then
        self:RefreshDisplay()
    end
end

local function CleanExpiredMessages()
    local now = GetTime()
    for category, msgList in pairs(messages) do
        local i = 1
        while i <= #msgList do
            if msgList[i].expireTime <= now then
                table.remove(msgList, i)
            else
                i = i + 1
            end
        end
    end
end

-- ============================================
-- UI
-- ============================================
-- One row of tab buttons. Choice shows the current tab in green; the
-- listing count sits in each button's top-right corner.
local function AddTabRow(L, tabs)
    local row = L:Row(22)
    local options = {}
    for i, t in ipairs(tabs) do
        options[i] = { value = t.key, text = t.text, width = 46, tooltip = t.tooltip }
    end
    local choice = row:Choice({
        get = function() return currentTab end,
        set = function(v)
            currentTab = v
            ServicesParser:RefreshDisplay()
        end,
        options = options,
    }, 8)
    local buttons = choice.buttons
    for i, t in ipairs(tabs) do
        local btn = buttons[i]
        if type(btn) == "table" and btn.CreateFontString then
            local count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            count:SetPoint("TOPRIGHT", 2, 2)
            count:SetTextColor(1, 0.8, 0)
            tabCounts[t.key] = count
        end
    end
    tabChoices[#tabChoices + 1] = choice
end

local function DungeonTab(dungeon)
    return { key = dungeon.key, text = dungeon.key,
             tooltip = { dungeon.name, "Levels " .. dungeon.levelRange } }
end

function ServicesParser:CreateMainFrame()
    if mainFrame then return mainFrame end

    -- Tabs and (collapsed) settings on top, the listings fill the rest
    local panel = WM.UI:CreatePanel({
        name = "WM_ServicesParserFrame",
        title = "Services Parser",
        titleColor = "00CCFF",
        width = 520,
        height = 480,
        scroll = false,
        onRefresh = function() ServicesParser:RefreshDisplay() end,
    })
    local L = panel.layout

    -- Header
    local row = L:Row(20)
    local header = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("CENTER", row.frame, "CENTER", 0, 0)
    panel.header = header

    -- Tab buttons - two rows: Classic + Summons, then TBC
    tabChoices, tabCounts = {}, {}
    local classic, tbc = {}, {}
    for i, dungeon in ipairs(DUNGEONS) do
        table.insert(i <= 7 and classic or tbc, DungeonTab(dungeon))
    end
    table.insert(classic, { key = "SUMMONS", text = "SUM",
        tooltip = { "Summons / Portals", "Adverts offering summons or portals." } })
    AddTabRow(L, classic)
    AddTabRow(L, tbc)

    -- ---------- Settings ----------
    L:Section({ key = "settings", title = "Settings", collapsed = true })
    local channelBox
    channelBox = L:EditBox({
        label = "Channel to monitor:", width = 150,
        get = function() return ServicesParserDB.channelName end,
        set = function(v)
            if v ~= "" then
                ServicesParserDB.channelName = v
            else
                channelBox.editBox:SetText(ServicesParserDB.channelName)   -- empty would match every channel
            end
        end,
        tooltip = { "Channel to Monitor", "Adverts are read from any channel whose name contains this"
            .. " text (not case-sensitive)." },
    })
    local durationBox = L:EditBox({
        label = "Message duration (sec):", width = 60,
        numeric = true,
        get = function() return tostring(ServicesParserDB.messageDuration) end,
        set = function(v) ServicesParserDB.messageDuration = tonumber(v) or 60 end,
        tooltip = { "Message Duration", "How long a listing stays in the list. A repeat of the same advert"
            .. " restarts its timer; listings already shown keep their old time." },
    })
    L:Checkbox({
        label = "Play sound on new message",
        get = function() return ServicesParserDB.playSound end,
        set = function(v) ServicesParserDB.playSound = v end,
        tooltip = { "Play Sound", "Play a click whenever a matching advert arrives, repeats included." },
    })
    L:EndSection()

    -- Listings in the remaining space
    local fill = L:Fill(120)
    local scrollFrame = CreateFrame("ScrollFrame", nil, fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 0)
    panel.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(520 - 24 - 23)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild
    panel.entries = {}

    panel:AddFooterButton({
        text = "Clear All", width = 80,
        onClick = function()
            ServicesParser:InitMessageTables()
            ServicesParser:RefreshDisplay()
        end,
        tooltip = { "Clear All", "Remove every listing from all tabs." },
    }, "RIGHT")

    panel:Finish()

    mainFrame = panel
    self.mainFrame = panel

    return panel
end

function ServicesParser:UpdateTabHighlights()
    for _, choice in ipairs(tabChoices) do
        choice:Refresh()
    end
    for key, count in pairs(tabCounts) do
        local msgCount = #(messages[key] or {})
        count:SetText(msgCount > 0 and msgCount or "")
    end
end

function ServicesParser:RefreshDisplay()
    if not mainFrame or not mainFrame:IsShown() then return end
    
    local scrollChild = mainFrame.scrollChild
    
    for _, entry in ipairs(mainFrame.entries or {}) do
        entry:Hide()
    end
    mainFrame.entries = mainFrame.entries or {}
    
    local msgList = messages[currentTab] or {}
    local now = GetTime()
    local yOffset = 0
    local entryWidth = scrollChild:GetWidth() - 10
    
    for i, msg in ipairs(msgList) do
        local entry = mainFrame.entries[i]
        if not entry then
            entry = self:CreateMessageEntry(scrollChild, entryWidth)
            mainFrame.entries[i] = entry
        end
        
        entry:SetWidth(entryWidth)
        entry:SetPoint("TOPLEFT", 5, -yOffset)
        
        entry.senderName = msg.sender
        entry.fullText = msg.text
        entry.sender:SetText(msg.sender)
        
        local displayText = msg.text
        if #displayText > 150 then
            displayText = displayText:sub(1, 147) .. "..."
        end
        entry.message:SetText(displayText)
        
        local remaining = math.max(0, math.ceil(msg.expireTime - now))
        entry.timer:SetText(remaining .. "s")
        if remaining <= 10 then
            entry.timer:SetTextColor(1, 0.3, 0.3)
        elseif remaining <= 30 then
            entry.timer:SetTextColor(1, 0.8, 0.3)
        else
            entry.timer:SetTextColor(0.7, 0.7, 0.7)
        end
        
        entry:Show()
        yOffset = yOffset + 55
    end
    
    scrollChild:SetHeight(math.max(yOffset, mainFrame.scrollFrame:GetHeight()))
    self:UpdateTabHighlights()
    
    -- Update header
    local dungeonName = currentTab
    for _, d in ipairs(DUNGEONS) do
        if d.key == currentTab then
            dungeonName = d.name .. " (" .. d.levelRange .. ")"
            break
        end
    end
    if currentTab == "SUMMONS" then
        dungeonName = "Summons / Portals"
    end
    mainFrame.header:SetText(dungeonName .. " - " .. #msgList .. " listings")
end

function ServicesParser:CreateMessageEntry(parent, width)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetSize(width, 50)
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    frame.bg = bg
    
    local senderText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    senderText:SetPoint("TOPLEFT", 5, -3)
    senderText:SetTextColor(0.4, 0.8, 1.0)
    frame.sender = senderText
    
    local timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("TOPRIGHT", -5, -3)
    timerText:SetTextColor(0.7, 0.7, 0.7)
    frame.timer = timerText
    
    local msgText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgText:SetPoint("TOPLEFT", 5, -16)
    msgText:SetPoint("BOTTOMRIGHT", -5, 3)
    msgText:SetJustifyH("LEFT")
    msgText:SetJustifyV("TOP")
    msgText:SetWordWrap(true)
    msgText:SetTextColor(1, 1, 1)
    frame.message = msgText
    
    frame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and self.senderName then
            ChatFrame_OpenChat("/w " .. self.senderName .. " ")
        end
    end)
    
    frame:SetScript("OnEnter", function(self)
        if self.fullText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.senderName or "Unknown", 0.4, 0.8, 1.0)
            GameTooltip:AddLine(self.fullText, 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click to whisper", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    return frame
end

function ServicesParser:ToggleUI()
    local frame = self:CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()   -- OnShow refreshes the listings
    end
end

function ServicesParser:Toggle()
    self:ToggleUI()
end

-- Turned off on this character: forget the listings and close the window
function ServicesParser:OnModuleOff()
    self:InitMessageTables()
    if mainFrame then mainFrame:Hide() end
end

-- The module's page in the guided setup
function ServicesParser:SetupPage(L)
    self:InitDB()
    L:Note("Reads the adverts people post in the Services channel and sorts them by dungeon, so you can see"
        .. " at a glance who's selling a run through the dungeon you want.")
    L:Note("|cFFFFFFFFHow it works:|r an advert that names a dungeon (by its name or short name, such as SM,"
        .. " Strat or Mech) goes under that dungeon's tab; one offering summons or portals goes under SUM."
        .. " Each tab shows how many listings it has. A listing disappears after the time below, and a repeat"
        .. " of the same advert puts it back at the top. Click one to whisper the seller.")
    L:Note("You need to have joined the Services channel for there to be anything to read.")
    local channelBox
    channelBox = L:EditBox({
        label = "Channel to read:", width = 150,
        get = function() return ServicesParserDB.channelName end,
        set = function(v)
            if v ~= "" then
                ServicesParserDB.channelName = v
            else
                channelBox.editBox:SetText(ServicesParserDB.channelName)   -- empty would match every channel
            end
        end,
        tooltip = { "Channel to Read", "Adverts are read from any channel whose name contains this text"
            .. " (any case)." },
    })
    L:Slider({ label = "Keep each listing for", min = 30, max = 600, step = 30, width = 200,
        format = function(v) return v .. " sec" end,
        get = function() return tonumber(ServicesParserDB.messageDuration) or 60 end,
        set = function(v) ServicesParserDB.messageDuration = v end })
    L:Checkbox({
        label = "Play a sound on each new advert",
        get = function() return ServicesParserDB.playSound end,
        set = function(v) ServicesParserDB.playSound = v end,
        tooltip = { "Play Sound", "A quiet click whenever a matching advert arrives, repeats included." },
    })
    L:Note("The listings themselves are in the Services Parser window: |cFFFFFF00/wmachine services|r.")
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")

-- Registered at load: does nothing while the module is off on this character
eventFrame:SetScript("OnEvent", function(self, event, msg, sender, _, _, _, _, _, _, channelName)
    if not WM:IsModuleOn("ServicesParser") then return end
    if event == "CHAT_MSG_CHANNEL" then
        -- Make sure DB is initialized
        if not ServicesParserDB then return end
        
        local monitorChannel = (ServicesParserDB.channelName or "services"):lower()
        if channelName and channelName:lower():find(monitorChannel, 1, true) then
            local name = sender:match("([^-]+)") or sender
            ServicesParser:AddMessage(name, msg, channelName)
        end
    end
end)

-- Update timer
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if not WM:IsModuleOn("ServicesParser") then return end
    updateTimer = updateTimer + elapsed
    if updateTimer >= 1 then
        updateTimer = 0
        CleanExpiredMessages()
        if mainFrame and mainFrame:IsShown() then
            ServicesParser:RefreshDisplay()
        end
    end
end)
