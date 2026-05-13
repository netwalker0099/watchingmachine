-- Watching Machine: Recruiting Tool Module
-- Crawls /who results for unguilded players and generates a per-player
-- click-to-send list. The user manually presses Enter to send each whisper,
-- pacing the sends naturally and avoiding chat throttle / spam flags.

local AddonName, WM = ...
local Recruiter = {}
WM:RegisterModule("Recruiter", Recruiter)

Recruiter.version = "3.0"

-- Default settings
local defaults = {
    guildName = "Your Guild",
    minLevel = 1,
    maxLevel = 70,
    message = "<%GUILD%> is recruiting! Whisper for more info!",
    whispered = {},
    enabled = false,
    currentClass = 1,
    currentLetter = 1,
    scanDelay = 5,
    cooldownDays = 7,
    activityLog = {},
    maxLogEntries = 100,
    hideWhispers = true,
    enabledClasses = {
        Warrior = true, Paladin = true, Hunter = true, Rogue = true,
        Priest = true, Shaman = true, Mage = true, Warlock = true, Druid = true,
    },
}

local classes = {"Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"}
local alphabet = {"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"}

-- State
local isScanning = false
local scanTimer = 0
local harvestedPlayers = {}   -- list of {name, level, class}
local harvestedIndex = {}     -- name -> true, for dedup during scanning
local currentWhoQuery = ""
local waitingForContinue = false
local mainFrame = nil
local messageFrame = nil

-- ============================================
-- INITIALIZATION
-- ============================================

function Recruiter:Initialize()
    self:InitDB()
    self:InstallChatFilter()
end

function Recruiter:InitDB()
    -- Migrate from old DB name if exists
    if SASRecruiterDB and not RecruitingToolDB then
        RecruitingToolDB = SASRecruiterDB
    end

    if not RecruitingToolDB then
        RecruitingToolDB = {}
    end

    -- Clean up deprecated v2.x auto-send keys if present
    RecruitingToolDB.autoInvite = nil
    RecruitingToolDB.whisperDelay = nil

    for k, v in pairs(defaults) do
        if RecruitingToolDB[k] == nil then
            if type(v) == "table" then
                RecruitingToolDB[k] = {}
                for k2, v2 in pairs(v) do
                    RecruitingToolDB[k][k2] = v2
                end
            else
                RecruitingToolDB[k] = v
            end
        end
    end
end

-- ============================================
-- UTILITIES
-- ============================================

function Recruiter:Print(msg)
    WM:ModulePrint("Recruiter", msg)
end

function Recruiter:AddLog(message)
    local timestamp = date("%m/%d %H:%M:%S")
    local entry = timestamp .. " - " .. message
    table.insert(RecruitingToolDB.activityLog, 1, entry)
    while #RecruitingToolDB.activityLog > RecruitingToolDB.maxLogEntries do
        table.remove(RecruitingToolDB.activityLog)
    end
end

function Recruiter:GetFormattedMessage()
    return RecruitingToolDB.message:gsub("%%GUILD%%", RecruitingToolDB.guildName)
end

function Recruiter:IsOnCooldown(playerName)
    if not RecruitingToolDB.whispered[playerName] then
        return false
    end
    local lastWhispered = RecruitingToolDB.whispered[playerName]
    local cooldownSeconds = RecruitingToolDB.cooldownDays * 86400
    return (time() - lastWhispered) < cooldownSeconds
end

function Recruiter:FormatTime(seconds)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh", hours)
    else
        return "< 1h"
    end
end

-- Chat filter to hide our own outgoing recruitment whispers from chat frame
function Recruiter:ChatFilter(self, event, msg, player, ...)
    if not RecruitingToolDB.hideWhispers then return false end
    if msg == Recruiter:GetFormattedMessage() then return true end
    return false
end

function Recruiter:InstallChatFilter()
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg, player, ...)
        return Recruiter:ChatFilter(self, event, msg, player, ...)
    end)
end

-- ============================================
-- HARVEST / SEND HELPERS
-- ============================================

function Recruiter:ClearHarvest()
    wipe(harvestedPlayers)
    wipe(harvestedIndex)
end

function Recruiter:CountSentInHarvest()
    local sent = 0
    for _, p in ipairs(harvestedPlayers) do
        if self:IsOnCooldown(p.name) then
            sent = sent + 1
        end
    end
    return sent
end

function Recruiter:MarkAsSent(name)
    RecruitingToolDB.whispered[name] = time()
end

function Recruiter:UnmarkAsSent(name)
    RecruitingToolDB.whispered[name] = nil
end

function Recruiter:MarkAllHarvestedAsSent()
    local marked = 0
    for _, p in ipairs(harvestedPlayers) do
        if not self:IsOnCooldown(p.name) then
            RecruitingToolDB.whispered[p.name] = time()
            marked = marked + 1
        end
    end
    self:AddLog("Bulk-marked " .. marked .. " players as sent")
    self:Print("Marked " .. marked .. " players as sent")
    return marked
end

-- Open the chat editbox pre-filled with a whisper command.
-- The user presses Enter to actually send. This is the human-paced
-- send mechanism that replaces the auto-send queue.
function Recruiter:OpenWhisperPrompt(name)
    local msg = self:GetFormattedMessage()
    local text = "/w " .. name .. " " .. msg
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(text, DEFAULT_CHAT_FRAME)
    else
        -- Fallback for clients without ChatFrame_OpenChat
        local editBox = DEFAULT_CHAT_FRAME.editBox
        editBox:SetText(text)
        editBox:Show()
        editBox:SetFocus()
    end
end

-- ============================================
-- STATUS
-- ============================================

function Recruiter:GetQuickStatus()
    local harvestCount = #harvestedPlayers
    local whisperedCount = 0
    for _ in pairs(RecruitingToolDB.whispered) do whisperedCount = whisperedCount + 1 end

    if isScanning then
        return "|cFF00FF00Scanning|r (" .. harvestCount .. " found)"
    elseif harvestCount > 0 then
        return "|cFFFFFF00" .. harvestCount .. " ready|r"
    else
        return "|cFF888888Idle|r (" .. whisperedCount .. " total)"
    end
end

-- ============================================
-- SCANNING
-- ============================================

function Recruiter:StartScan()
    if isScanning then
        self:Print("Already scanning!")
        return
    end

    isScanning = true
    waitingForContinue = false
    RecruitingToolDB.currentClass = 1
    RecruitingToolDB.currentLetter = 1
    scanTimer = 0
    self:Print("Starting scan: Level " .. RecruitingToolDB.minLevel .. "-" .. RecruitingToolDB.maxLevel)
    self:AddLog("Started scan")
    self:PerformWhoQuery()
end

function Recruiter:StopScan()
    isScanning = false
    waitingForContinue = false
    self:Print("Scanning stopped")
    self:AddLog("Scanning stopped")
    self:UpdateUI()
end

function Recruiter:ContinueScan()
    if not isScanning or not waitingForContinue then return end
    waitingForContinue = false
    self:PerformWhoQuery()
end

function Recruiter:PerformWhoQuery()
    if not isScanning then return end

    local classIndex = RecruitingToolDB.currentClass
    local letterIndex = RecruitingToolDB.currentLetter

    -- Skip disabled classes
    while classIndex <= #classes do
        if RecruitingToolDB.enabledClasses[classes[classIndex]] then
            break
        end
        classIndex = classIndex + 1
        RecruitingToolDB.currentClass = classIndex
        letterIndex = 1
        RecruitingToolDB.currentLetter = 1
    end

    if classIndex > #classes then
        self:Print("Scan complete! " .. #harvestedPlayers .. " players harvested")
        self:AddLog("Scan complete (" .. #harvestedPlayers .. " harvested)")
        isScanning = false
        self:UpdateUI()
        return
    end

    if letterIndex > #alphabet then
        RecruitingToolDB.currentClass = classIndex + 1
        RecruitingToolDB.currentLetter = 1
        self:PerformWhoQuery()
        return
    end

    local className = classes[classIndex]
    local letter = alphabet[letterIndex]
    local minLvl = RecruitingToolDB.minLevel
    local maxLvl = RecruitingToolDB.maxLevel

    currentWhoQuery = string.format("%d-%d %s %s", minLvl, maxLvl, className, letter)

    self:Print("Scanning " .. className .. " [" .. string.upper(letter) .. "]")

    DEFAULT_CHAT_FRAME.editBox:SetText("/who " .. currentWhoQuery)
    ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)

    scanTimer = 3
    self:UpdateUI()
end

function Recruiter:ProcessWhoResults()
    local numResults
    if C_FriendList and C_FriendList.GetNumWhoResults then
        numResults = C_FriendList.GetNumWhoResults()
    else
        numResults = GetNumWhoResults()
    end
    local className = classes[RecruitingToolDB.currentClass]
    local letter = alphabet[RecruitingToolDB.currentLetter]

    if numResults > 0 then
        local added = 0
        for i = 1, numResults do
            local name, guild, level, race, class

            if C_FriendList and C_FriendList.GetWhoInfo then
                local info = C_FriendList.GetWhoInfo(i)
                if info then
                    name = info.fullName
                    guild = info.fullGuildName
                    level = info.level
                    class = info.filename
                end
            else
                -- Classic API returns multiple values
                local charName, guildName, charLevel, charRace, charClass, charZone, charClassFile = GetWhoInfo(i)
                name = charName
                guild = guildName
                level = charLevel
                class = charClassFile or charClass
            end

            if name then
                if (guild == nil or guild == "") then
                    if not self:IsOnCooldown(name) and not harvestedIndex[name] then
                        table.insert(harvestedPlayers, {name = name, level = level, class = class})
                        harvestedIndex[name] = true
                        added = added + 1
                    end
                end
            end
        end

        if added > 0 then
            self:Print("Found " .. added .. " unguilded in " .. className .. " [" .. string.upper(letter) .. "]")
            self:AddLog("Found " .. added .. " " .. className .. " [" .. string.upper(letter) .. "]")
        end
    end

    RecruitingToolDB.currentLetter = RecruitingToolDB.currentLetter + 1
    waitingForContinue = true
    self:Print("|cFFFFFF00Click 'Continue' for next query|r")
    self:UpdateUI()
    if messageFrame and messageFrame:IsShown() then
        self:UpdateMessageList()
    end
end

-- ============================================
-- MAIN UI
-- ============================================

function Recruiter:CreateUI()
    if mainFrame then return mainFrame end

    local frame = CreateFrame("Frame", "WM_RecruiterFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 560)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFFD700Recruiting Tool|r |cFF888888v" .. Recruiter.version .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local yOffset = -45

    -- Guild Name
    local guildLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildLabel:SetPoint("TOPLEFT", 20, yOffset)
    guildLabel:SetText("Guild Name:")

    local guildInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    guildInput:SetSize(200, 20)
    guildInput:SetPoint("LEFT", guildLabel, "RIGHT", 10, 0)
    guildInput:SetText(RecruitingToolDB.guildName)
    guildInput:SetAutoFocus(false)
    guildInput:SetScript("OnEnterPressed", function(self)
        RecruitingToolDB.guildName = self:GetText()
        self:ClearFocus()
    end)
    guildInput:SetScript("OnEditFocusLost", function(self)
        RecruitingToolDB.guildName = self:GetText()
    end)
    frame.guildInput = guildInput

    yOffset = yOffset - 30

    -- Level range
    local levelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelLabel:SetPoint("TOPLEFT", 20, yOffset)
    levelLabel:SetText("Level Range:")

    local minLvlInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    minLvlInput:SetSize(40, 20)
    minLvlInput:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
    minLvlInput:SetText(RecruitingToolDB.minLevel)
    minLvlInput:SetNumeric(true)
    minLvlInput:SetAutoFocus(false)
    minLvlInput:SetScript("OnEnterPressed", function(self)
        RecruitingToolDB.minLevel = tonumber(self:GetText()) or 1
        self:ClearFocus()
    end)
    minLvlInput:SetScript("OnEditFocusLost", function(self)
        RecruitingToolDB.minLevel = tonumber(self:GetText()) or 1
    end)
    frame.minLvlInput = minLvlInput

    local toLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toLabel:SetPoint("LEFT", minLvlInput, "RIGHT", 5, 0)
    toLabel:SetText("to")

    local maxLvlInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    maxLvlInput:SetSize(40, 20)
    maxLvlInput:SetPoint("LEFT", toLabel, "RIGHT", 5, 0)
    maxLvlInput:SetText(RecruitingToolDB.maxLevel)
    maxLvlInput:SetNumeric(true)
    maxLvlInput:SetAutoFocus(false)
    maxLvlInput:SetScript("OnEnterPressed", function(self)
        RecruitingToolDB.maxLevel = tonumber(self:GetText()) or 70
        self:ClearFocus()
    end)
    maxLvlInput:SetScript("OnEditFocusLost", function(self)
        RecruitingToolDB.maxLevel = tonumber(self:GetText()) or 70
    end)
    frame.maxLvlInput = maxLvlInput

    yOffset = yOffset - 30

    -- Cooldown
    local cooldownLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cooldownLabel:SetPoint("TOPLEFT", 20, yOffset)
    cooldownLabel:SetText("Cooldown (days):")

    local cooldownInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    cooldownInput:SetSize(40, 20)
    cooldownInput:SetPoint("LEFT", cooldownLabel, "RIGHT", 10, 0)
    cooldownInput:SetText(RecruitingToolDB.cooldownDays)
    cooldownInput:SetNumeric(true)
    cooldownInput:SetAutoFocus(false)
    cooldownInput:SetScript("OnEnterPressed", function(self)
        RecruitingToolDB.cooldownDays = math.min(14, tonumber(self:GetText()) or 7)
        self:ClearFocus()
    end)
    cooldownInput:SetScript("OnEditFocusLost", function(self)
        RecruitingToolDB.cooldownDays = math.min(14, tonumber(self:GetText()) or 7)
    end)
    frame.cooldownInput = cooldownInput

    yOffset = yOffset - 35

    -- Message
    local msgLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgLabel:SetPoint("TOPLEFT", 20, yOffset)
    msgLabel:SetText("Message (use %GUILD% for guild name):")

    yOffset = yOffset - 20

    local msgInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    msgInput:SetSize(400, 20)
    msgInput:SetPoint("TOPLEFT", 20, yOffset)
    msgInput:SetText(RecruitingToolDB.message)
    msgInput:SetAutoFocus(false)
    msgInput:SetScript("OnEnterPressed", function(self)
        RecruitingToolDB.message = self:GetText()
        self:ClearFocus()
    end)
    msgInput:SetScript("OnEditFocusLost", function(self)
        RecruitingToolDB.message = self:GetText()
    end)
    frame.msgInput = msgInput

    yOffset = yOffset - 30

    -- Hide whispers checkbox
    local hideWhisperCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    hideWhisperCB:SetPoint("TOPLEFT", 15, yOffset)
    hideWhisperCB.Text:SetText("Hide outgoing recruitment whispers from chat")
    hideWhisperCB:SetChecked(RecruitingToolDB.hideWhispers)
    hideWhisperCB:SetScript("OnClick", function(self)
        RecruitingToolDB.hideWhispers = self:GetChecked()
    end)

    yOffset = yOffset - 35

    -- Classes section
    local classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", 20, yOffset)
    classLabel:SetText("Classes to scan:")

    yOffset = yOffset - 22
    local xPos = 20
    frame.classCheckboxes = {}

    for i, className in ipairs(classes) do
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", xPos, yOffset)
        cb:SetChecked(RecruitingToolDB.enabledClasses[className])
        cb:SetScript("OnClick", function(self)
            RecruitingToolDB.enabledClasses[className] = self:GetChecked()
        end)

        local cbLabel = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        cbLabel:SetText(className:sub(1, 4))

        frame.classCheckboxes[className] = cb
        xPos = xPos + 48
        if xPos > 400 then
            xPos = 20
            yOffset = yOffset - 22
        end
    end

    yOffset = yOffset - 35

    -- Status
    local statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", 20, yOffset)
    statusLabel:SetText("Status:")

    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("LEFT", statusLabel, "RIGHT", 10, 0)
    statusText:SetText("|cFF888888Idle|r")
    frame.statusText = statusText

    yOffset = yOffset - 20

    local harvestText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    harvestText:SetPoint("TOPLEFT", 20, yOffset)
    harvestText:SetText("Harvested: 0 players")
    frame.harvestText = harvestText

    local whisperedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whisperedText:SetPoint("LEFT", harvestText, "RIGHT", 30, 0)
    whisperedText:SetText("Total: 0 messaged")
    frame.whisperedText = whisperedText

    yOffset = yOffset - 30

    -- Control buttons row 1
    local startBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startBtn:SetSize(80, 25)
    startBtn:SetPoint("TOPLEFT", 20, yOffset)
    startBtn:SetText("Start Scan")
    startBtn:SetScript("OnClick", function()
        RecruitingToolDB.guildName = frame.guildInput:GetText()
        RecruitingToolDB.minLevel = tonumber(frame.minLvlInput:GetText()) or 1
        RecruitingToolDB.maxLevel = tonumber(frame.maxLvlInput:GetText()) or 70
        RecruitingToolDB.cooldownDays = math.min(14, tonumber(frame.cooldownInput:GetText()) or 7)
        RecruitingToolDB.message = frame.msgInput:GetText()
        Recruiter:StartScan()
    end)
    frame.startBtn = startBtn

    local stopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopBtn:SetSize(80, 25)
    stopBtn:SetPoint("LEFT", startBtn, "RIGHT", 10, 0)
    stopBtn:SetText("Stop")
    stopBtn:SetScript("OnClick", function()
        Recruiter:StopScan()
    end)
    frame.stopBtn = stopBtn

    local continueBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    continueBtn:SetSize(80, 25)
    continueBtn:SetPoint("LEFT", stopBtn, "RIGHT", 10, 0)
    continueBtn:SetText("Continue")
    continueBtn:SetScript("OnClick", function()
        Recruiter:ContinueScan()
    end)
    continueBtn:Disable()
    frame.continueBtn = continueBtn

    local clearHarvestBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearHarvestBtn:SetSize(100, 25)
    clearHarvestBtn:SetPoint("LEFT", continueBtn, "RIGHT", 10, 0)
    clearHarvestBtn:SetText("Clear Results")
    clearHarvestBtn:SetScript("OnClick", function()
        Recruiter:ClearHarvest()
        Recruiter:Print("Harvest cleared")
        Recruiter:UpdateUI()
        if messageFrame and messageFrame:IsShown() then
            Recruiter:UpdateMessageList()
        end
    end)
    frame.clearHarvestBtn = clearHarvestBtn

    yOffset = yOffset - 30

    -- Control buttons row 2 - the new "Show Messages" button is the star here
    local showMsgBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    showMsgBtn:SetSize(140, 25)
    showMsgBtn:SetPoint("TOPLEFT", 20, yOffset)
    showMsgBtn:SetText("|cFFFFD700Show Messages|r")
    showMsgBtn:SetScript("OnClick", function()
        Recruiter:ShowMessageList()
    end)
    frame.showMsgBtn = showMsgBtn

    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 25)
    testBtn:SetPoint("LEFT", showMsgBtn, "RIGHT", 10, 0)
    testBtn:SetText("Test Message")
    testBtn:SetScript("OnClick", function()
        RecruitingToolDB.guildName = frame.guildInput:GetText()
        RecruitingToolDB.message = frame.msgInput:GetText()
        local playerName = UnitName("player")
        Recruiter:OpenWhisperPrompt(playerName)
        Recruiter:Print("Chat prefilled with test whisper to yourself - press Enter to send")
    end)
    frame.testBtn = testBtn

    yOffset = yOffset - 35

    -- Activity log header with buttons
    local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logLabel:SetPoint("TOPLEFT", 20, yOffset)
    logLabel:SetText("Activity Log:")

    local viewHistoryBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewHistoryBtn:SetSize(90, 20)
    viewHistoryBtn:SetPoint("LEFT", logLabel, "RIGHT", 10, 0)
    viewHistoryBtn:SetText("View History")
    viewHistoryBtn:SetScript("OnClick", function()
        Recruiter:ShowHistoryWindow()
    end)
    frame.viewHistoryBtn = viewHistoryBtn

    local clearLogBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearLogBtn:SetSize(80, 20)
    clearLogBtn:SetPoint("LEFT", viewHistoryBtn, "RIGHT", 5, 0)
    clearLogBtn:SetText("Clear Log")
    clearLogBtn:SetScript("OnClick", function()
        RecruitingToolDB.activityLog = {}
        Recruiter:UpdateLogDisplay()
    end)

    yOffset = yOffset - 20

    -- Activity log scroll frame
    local logFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    logFrame:SetPoint("TOPLEFT", 20, yOffset)
    logFrame:SetPoint("BOTTOMRIGHT", -35, 55)
    frame.logFrame = logFrame

    local logChild = CreateFrame("Frame", nil, logFrame)
    logChild:SetWidth(logFrame:GetWidth())
    logChild:SetHeight(1)
    logFrame:SetScrollChild(logChild)
    frame.logChild = logChild

    -- Clear history button (at bottom)
    local clearHistoryBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearHistoryBtn:SetSize(100, 22)
    clearHistoryBtn:SetPoint("BOTTOMLEFT", 20, 18)
    clearHistoryBtn:SetText("Clear History")
    clearHistoryBtn:SetScript("OnClick", function()
        StaticPopup_Show("WM_RECRUITER_CLEAR_HISTORY")
    end)

    StaticPopupDialogs["WM_RECRUITER_CLEAR_HISTORY"] = {
        text = "Clear all whisper history and cooldowns?",
        button1 = "Yes",
        button2 = "Cancel",
        OnAccept = function()
            RecruitingToolDB.whispered = {}
            Recruiter:ClearHarvest()
            Recruiter:Print("History cleared")
            Recruiter:UpdateUI()
            if messageFrame and messageFrame:IsShown() then
                Recruiter:UpdateMessageList()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    mainFrame = frame
    self.mainFrame = frame

    return frame
end

function Recruiter:UpdateUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    -- Status
    if isScanning then
        local className = classes[RecruitingToolDB.currentClass] or "?"
        local letter = alphabet[RecruitingToolDB.currentLetter] or "?"
        if waitingForContinue then
            mainFrame.statusText:SetText("|cFFFFFF00Waiting...|r " .. className .. " [" .. string.upper(letter) .. "]")
        else
            mainFrame.statusText:SetText("|cFF00FF00Scanning|r " .. className .. " [" .. string.upper(letter) .. "]")
        end
    else
        mainFrame.statusText:SetText("|cFF888888Idle|r")
    end

    -- Harvest count
    local sent = self:CountSentInHarvest()
    local remaining = #harvestedPlayers - sent
    mainFrame.harvestText:SetText("Harvested: |cFFFFFF00" .. #harvestedPlayers .. "|r (|cFF00FF00" .. remaining .. "|r ready)")

    -- Whispered count
    local count = 0
    for _ in pairs(RecruitingToolDB.whispered) do count = count + 1 end
    mainFrame.whisperedText:SetText("Total: |cFFFFFF00" .. count .. "|r messaged")

    -- Continue button state
    if isScanning and waitingForContinue then
        mainFrame.continueBtn:Enable()
    else
        mainFrame.continueBtn:Disable()
    end

    -- Update log
    self:UpdateLogDisplay()
end

function Recruiter:UpdateLogDisplay()
    if not mainFrame or not mainFrame.logChild then return end

    if not mainFrame.logEntries then
        mainFrame.logEntries = {}
    end

    for _, entry in ipairs(mainFrame.logEntries) do
        entry:Hide()
    end

    local yOffset = 0
    local numEntries = math.min(#RecruitingToolDB.activityLog, 50)

    for i = 1, numEntries do
        local entry = RecruitingToolDB.activityLog[i]
        local text = mainFrame.logEntries[i]

        if not text then
            text = mainFrame.logChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetWidth(370)
            text:SetJustifyH("LEFT")
            mainFrame.logEntries[i] = text
        end

        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", 0, -yOffset)
        text:SetText(entry)
        text:Show()

        yOffset = yOffset + 14
    end

    mainFrame.logChild:SetHeight(math.max(yOffset, 1))
end

-- ============================================
-- MESSAGES WINDOW (the new per-player click-to-send list)
-- ============================================

function Recruiter:ShowMessageList()
    if not messageFrame then
        self:CreateMessageFrame()
    end

    if messageFrame:IsShown() then
        messageFrame:Hide()
        return
    end

    messageFrame:Show()
    self:UpdateMessageList()
end

function Recruiter:CreateMessageFrame()
    local frame = CreateFrame("Frame", "WM_RecruiterMessageFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 520)
    frame:SetPoint("CENTER", 280, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")

    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFFD700Whisper Messages|r")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Instruction text
    local instruction = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instruction:SetPoint("TOPLEFT", 20, -45)
    instruction:SetPoint("TOPRIGHT", -20, -45)
    instruction:SetJustifyH("LEFT")
    instruction:SetText("Click |cFF00FF00Send|r to prefill chat with the whisper. Press Enter in chat to actually send.\nThe row marks itself sent on click; use |cFFFFAA00Unmark|r if you didn't actually send it.")

    -- Count display
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("TOPLEFT", 20, -82)
    frame.countText = countText

    -- Bulk action buttons
    local markAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    markAllBtn:SetSize(110, 22)
    markAllBtn:SetPoint("TOPRIGHT", -125, -78)
    markAllBtn:SetText("Mark All Sent")
    markAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("WM_RECRUITER_MARK_ALL_SENT")
    end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(100, 22)
    clearBtn:SetPoint("TOPRIGHT", -20, -78)
    clearBtn:SetText("Clear List")
    clearBtn:SetScript("OnClick", function()
        Recruiter:ClearHarvest()
        Recruiter:UpdateMessageList()
        Recruiter:UpdateUI()
    end)

    StaticPopupDialogs["WM_RECRUITER_MARK_ALL_SENT"] = {
        text = "Mark all harvested players as sent? They will be added to the cooldown table.",
        button1 = "Yes",
        button2 = "Cancel",
        OnAccept = function()
            Recruiter:MarkAllHarvestedAsSent()
            Recruiter:UpdateMessageList()
            Recruiter:UpdateUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    -- Scroll frame for player rows
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -110)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 20)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.rows = {}

    messageFrame = frame
end

-- Create or recycle a row at index i for the given player data
function Recruiter:GetOrCreateRow(i, player)
    local frame = messageFrame
    local row = frame.rows[i]

    if not row then
        row = CreateFrame("Frame", nil, frame.scrollChild)
        row:SetHeight(22)
        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)

        row.sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.sendBtn:SetSize(70, 20)
        row.sendBtn:SetPoint("LEFT", 0, 0)

        row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.infoText:SetPoint("LEFT", row.sendBtn, "RIGHT", 8, 0)
        row.infoText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.infoText:SetJustifyH("LEFT")

        frame.rows[i] = row
    end

    return row
end

function Recruiter:UpdateMessageList()
    if not messageFrame or not messageFrame:IsShown() then return end

    local sent = self:CountSentInHarvest()
    local total = #harvestedPlayers
    local remaining = total - sent
    messageFrame.countText:SetText(string.format(
        "|cFFFFFFFF%d|r harvested  -  |cFF00FF00%d|r ready  -  |cFF888888%d|r marked sent",
        total, remaining, sent
    ))

    -- Hide all existing rows first
    for _, row in ipairs(messageFrame.rows) do
        row:Hide()
    end

    local yOffset = 0
    for i, player in ipairs(harvestedPlayers) do
        local row = self:GetOrCreateRow(i, player)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", 0, -yOffset)

        local onCooldown = self:IsOnCooldown(player.name)
        local name = player.name
        local level = player.level or "?"
        local class = player.class or "?"

        if onCooldown then
            row.sendBtn:SetText("Unmark")
            row.sendBtn:SetScript("OnClick", function()
                Recruiter:UnmarkAsSent(name)
                Recruiter:AddLog("Unmarked " .. name)
                Recruiter:UpdateMessageList()
                Recruiter:UpdateUI()
            end)
            row.infoText:SetText("|cFF666666" .. name .. " (L" .. tostring(level) .. " " .. tostring(class) .. ") - sent|r")
        else
            row.sendBtn:SetText("|cFF00FF00Send|r")
            row.sendBtn:SetScript("OnClick", function()
                Recruiter:OpenWhisperPrompt(name)
                Recruiter:MarkAsSent(name)
                Recruiter:AddLog("Sent to " .. name .. " (L" .. tostring(level) .. ")")
                Recruiter:UpdateMessageList()
                Recruiter:UpdateUI()
            end)
            row.infoText:SetText("|cFFFFFFFF" .. name .. "|r |cFFAAAAAA(L" .. tostring(level) .. " " .. tostring(class) .. ")|r")
        end

        row:Show()
        yOffset = yOffset + 24
    end

    messageFrame.scrollChild:SetHeight(math.max(yOffset, 1))
end

-- ============================================
-- HISTORY WINDOW
-- ============================================

local historyFrame = nil

function Recruiter:ShowHistoryWindow()
    if historyFrame then
        if historyFrame:IsShown() then
            historyFrame:Hide()
            return
        end
        historyFrame:Show()
        self:UpdateHistoryDisplay()
        return
    end

    local frame = CreateFrame("Frame", "WM_RecruiterHistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(400, 450)
    frame:SetPoint("CENTER", 250, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")

    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFFD700Whisper History|r")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("TOPLEFT", 20, -45)
    frame.countText = countText

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 20)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.historyEntries = {}

    historyFrame = frame
    self:UpdateHistoryDisplay()
end

function Recruiter:UpdateHistoryDisplay()
    if not historyFrame or not historyFrame:IsShown() then return end

    if historyFrame.historyEntries then
        for _, entry in ipairs(historyFrame.historyEntries) do
            entry:Hide()
        end
    else
        historyFrame.historyEntries = {}
    end

    local sorted = {}
    for name, timestamp in pairs(RecruitingToolDB.whispered) do
        table.insert(sorted, {name = name, time = timestamp})
    end
    table.sort(sorted, function(a, b) return a.time > b.time end)

    historyFrame.countText:SetText("Total whispered: |cFFFFFF00" .. #sorted .. "|r players")

    local yOffset = 0
    for i, data in ipairs(sorted) do
        if i > 200 then break end

        local text = historyFrame.historyEntries[i]
        if not text then
            text = historyFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetWidth(340)
            text:SetJustifyH("LEFT")
            historyFrame.historyEntries[i] = text
        end

        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", 0, -yOffset)

        local timeStr = date("%m/%d %H:%M", data.time)
        text:SetText("|cFFFFFFFF" .. data.name .. "|r - |cFF888888" .. timeStr .. "|r")
        text:Show()

        yOffset = yOffset + 14
    end

    historyFrame.scrollChild:SetHeight(math.max(yOffset, 1))
end

function Recruiter:ToggleUI()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:UpdateUI()
    end
end

function Recruiter:Toggle()
    self:ToggleUI()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local whoEventFrame = CreateFrame("Frame")
whoEventFrame:RegisterEvent("WHO_LIST_UPDATE")
whoEventFrame:SetScript("OnEvent", function()
    if isScanning then
        Recruiter:ProcessWhoResults()
    end
end)

-- OnUpdate for scan timer only (auto-send is gone)
local updateFrame = CreateFrame("Frame")
local uiUpdateTimer = 0
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not isScanning then
        -- Still tick UI updates if main frame is open
        if mainFrame and mainFrame:IsShown() then
            uiUpdateTimer = uiUpdateTimer + elapsed
            if uiUpdateTimer >= 1.0 then
                Recruiter:UpdateUI()
                uiUpdateTimer = 0
            end
        end
        return
    end

    if scanTimer > 0 and not waitingForContinue then
        scanTimer = scanTimer - elapsed
        if scanTimer <= 0 then
            Recruiter:PerformWhoQuery()
        end
    end

    uiUpdateTimer = uiUpdateTimer + elapsed
    if uiUpdateTimer >= 0.5 then
        Recruiter:UpdateUI()
        uiUpdateTimer = 0
    end
end)
