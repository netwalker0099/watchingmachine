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
local tabButtons = {}
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

function ServicesParser:CreateMainFrame()
    if mainFrame then return mainFrame end
    
    local frame = CreateFrame("Frame", "WM_ServicesParserFrame", UIParent, "BackdropTemplate")
    frame:SetSize(520, 480)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF00CCFFServices Parser|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    -- Header
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -40)
    frame.header = header
    
    -- Tab buttons - Two rows: Classic (row 1), TBC (row 2)
    tabButtons = {}
    local xOffset = 10
    local yOffset = -58
    local tabWidth = 48
    local tabsPerRow = 10
    local tabCount = 0
    
    -- Classic dungeons (first row)
    for i, dungeon in ipairs(DUNGEONS) do
        if i <= 7 then  -- Classic dungeons
            local btn = self:CreateTabButton(frame, dungeon.key, dungeon.key, xOffset, yOffset)
            tabButtons[dungeon.key] = btn
            xOffset = xOffset + tabWidth
            tabCount = tabCount + 1
        end
    end
    
    -- Summons tab at end of first row
    local sumBtn = self:CreateTabButton(frame, "SUM", "SUMMONS", xOffset, yOffset)
    tabButtons["SUMMONS"] = sumBtn
    
    -- TBC dungeons (second row)
    xOffset = 10
    yOffset = yOffset - 24
    for i, dungeon in ipairs(DUNGEONS) do
        if i > 7 then  -- TBC dungeons
            local btn = self:CreateTabButton(frame, dungeon.key, dungeon.key, xOffset, yOffset)
            tabButtons[dungeon.key] = btn
            xOffset = xOffset + tabWidth
        end
    end
    
    -- Scroll frame (adjusted for two rows of tabs)
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -110)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    frame.scrollFrame = scrollFrame
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.entries = {}
    
    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsBtn:SetSize(80, 22)
    settingsBtn:SetPoint("BOTTOMLEFT", 15, 15)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        ServicesParser:ShowSettings()
    end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", -15, 15)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        ServicesParser:InitMessageTables()
        ServicesParser:RefreshDisplay()
    end)
    
    mainFrame = frame
    self.mainFrame = frame
    
    self:UpdateTabHighlights()
    self:RefreshDisplay()
    
    return frame
end

function ServicesParser:CreateTabButton(parent, text, key, xOffset, yOffset)
    yOffset = yOffset or -65
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(46, 22)
    btn:SetPoint("TOPLEFT", xOffset, yOffset)
    
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    btn.bg = bg
    
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    btn.label = label
    
    local count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("TOPRIGHT", 2, 2)
    count:SetTextColor(1, 0.8, 0)
    btn.count = count
    
    btn.key = key
    
    btn:SetScript("OnClick", function()
        currentTab = key
        ServicesParser:UpdateTabHighlights()
        ServicesParser:RefreshDisplay()
    end)
    
    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        if currentTab == self.key then
            self.bg:SetColorTexture(0.3, 0.5, 0.3, 0.9)
        else
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
        end
    end)
    
    return btn
end

function ServicesParser:UpdateTabHighlights()
    for key, btn in pairs(tabButtons) do
        if key == currentTab then
            btn.bg:SetColorTexture(0.3, 0.5, 0.3, 0.9)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end
        
        local msgCount = #(messages[key] or {})
        if msgCount > 0 then
            btn.count:SetText(msgCount)
        else
            btn.count:SetText("")
        end
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

function ServicesParser:ShowSettings()
    if self.settingsFrame then
        self.settingsFrame:Show()
        return
    end
    
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(300, 180)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Services Parser Settings")
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    -- Channel input
    local channelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("TOPLEFT", 20, -50)
    channelLabel:SetText("Channel to monitor:")
    
    local channelInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    channelInput:SetSize(150, 20)
    channelInput:SetPoint("LEFT", channelLabel, "RIGHT", 10, 0)
    channelInput:SetText(ServicesParserDB.channelName)
    channelInput:SetAutoFocus(false)
    channelInput:SetScript("OnEnterPressed", function(self)
        ServicesParserDB.channelName = self:GetText()
        self:ClearFocus()
    end)
    
    -- Duration input
    local durationLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("TOPLEFT", 20, -80)
    durationLabel:SetText("Message duration (sec):")
    
    local durationInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    durationInput:SetSize(60, 20)
    durationInput:SetPoint("LEFT", durationLabel, "RIGHT", 10, 0)
    durationInput:SetText(ServicesParserDB.messageDuration)
    durationInput:SetAutoFocus(false)
    durationInput:SetNumeric(true)
    durationInput:SetScript("OnEnterPressed", function(self)
        ServicesParserDB.messageDuration = tonumber(self:GetText()) or 60
        self:ClearFocus()
    end)
    
    -- Sound checkbox
    local soundCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    soundCB:SetPoint("TOPLEFT", 15, -110)
    soundCB.Text:SetText("Play sound on new message")
    soundCB:SetChecked(ServicesParserDB.playSound)
    soundCB:SetScript("OnClick", function(self)
        ServicesParserDB.playSound = self:GetChecked()
    end)
    
    self.settingsFrame = frame
end

function ServicesParser:ToggleUI()
    local frame = self:CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:RefreshDisplay()
    end
end

function ServicesParser:Toggle()
    self:ToggleUI()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")

eventFrame:SetScript("OnEvent", function(self, event, msg, sender, _, _, _, _, _, _, channelName)
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
    updateTimer = updateTimer + elapsed
    if updateTimer >= 1 then
        updateTimer = 0
        CleanExpiredMessages()
        if mainFrame and mainFrame:IsShown() then
            ServicesParser:RefreshDisplay()
        end
    end
end)
