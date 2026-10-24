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
local historyFrame = nil

-- Off on this character: nothing scans, prefills a whisper or filters chat
local function On() return WM:IsModuleOn("Recruiter") end

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
    if not On() or not RecruitingToolDB or not RecruitingToolDB.hideWhispers then return false end
    if not RecruitingToolDB.message or not RecruitingToolDB.guildName then return false end
    if msg == Recruiter:GetFormattedMessage() then return true end
    return false
end

function Recruiter:InstallChatFilter()
    if self.filterInstalled or not ChatFrame_AddMessageEventFilter then return end
    self.filterInstalled = true
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
-- send mechanism that replaces the auto-send queue. Returns true if the
-- chat box was filled (never while the module is off).
function Recruiter:OpenWhisperPrompt(name)
    if not On() or not name then return false end
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
    return true
end

-- ============================================
-- STATUS
-- ============================================

function Recruiter:GetQuickStatus()
    if not RecruitingToolDB or type(RecruitingToolDB.whispered) ~= "table" then return "|cFF888888Not started|r" end
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
    if not On() then return end
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
    if not On() or not isScanning or not waitingForContinue then return end
    waitingForContinue = false
    self:PerformWhoQuery()
end

function Recruiter:PerformWhoQuery()
    if not isScanning or not On() then return end

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

-- Status lines, shared by the panel's Refresh and UpdateUI
local function StatusLine()
    if isScanning then
        local className = classes[RecruitingToolDB.currentClass] or "?"
        local letter = alphabet[RecruitingToolDB.currentLetter] or "?"
        if waitingForContinue then
            return "|cFFFFFF00Waiting...|r " .. className .. " [" .. string.upper(letter) .. "]"
        end
        return "|cFF00FF00Scanning|r " .. className .. " [" .. string.upper(letter) .. "]"
    end
    return "|cFF888888Idle|r"
end

local function HarvestLine()
    local sent = Recruiter:CountSentInHarvest()
    local remaining = #harvestedPlayers - sent
    return "Harvested: |cFFFFFF00" .. #harvestedPlayers .. "|r (|cFF00FF00" .. remaining .. "|r ready)"
end

local function WhisperedLine()
    local count = 0
    for _ in pairs(RecruitingToolDB.whispered) do count = count + 1 end
    return "Total: |cFFFFFF00" .. count .. "|r messaged"
end

-- Edit box writers, also used to take what's typed when a button is clicked
local function SetGuildName(text) RecruitingToolDB.guildName = text end
local function SetMinLevel(text) RecruitingToolDB.minLevel = tonumber(text) or 1 end
local function SetMaxLevel(text) RecruitingToolDB.maxLevel = tonumber(text) or 70 end
local function SetCooldown(text) RecruitingToolDB.cooldownDays = math.min(14, tonumber(text) or 7) end
local function SetMessage(text) RecruitingToolDB.message = text end

local function CreateLogList(fill, width)
    local scrollFrame = CreateFrame("ScrollFrame", nil, fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    return scrollFrame, scrollChild
end

function Recruiter:CreateUI()
    if mainFrame then return mainFrame end

    -- Settings and scan controls on top, the activity log fills the rest
    local panel = WM.UI:CreatePanel({
        name = "WM_RecruiterFrame",
        title = "Recruiting Tool",
        titleColor = "FFD700",
        width = 450,
        height = 560,
        minHeight = 460,
        scroll = false,
        onShow = function() Recruiter:UpdateUI() end,
    })
    panel.titleText:SetText("|cFFFFD700Recruiting Tool|r |cFF888888v" .. Recruiter.version .. "|r")
    local L = panel.layout

    panel.guildInput = L:EditBox({
        label = "Guild Name:", width = 200,
        get = function() return RecruitingToolDB.guildName end,
        set = SetGuildName,
        tooltip = { "Guild Name", "Replaces %GUILD% in the whisper message." },
    })

    local row = L:Row(26)
    panel.minLvlInput = row:EditBox({
        label = "Level Range:", width = 40,
        numeric = true,
        get = function() return tostring(RecruitingToolDB.minLevel) end,
        set = SetMinLevel,
        tooltip = { "Level Range", "Only players in this level range are searched for with /who." },
    }, 12)
    panel.maxLvlInput = row:EditBox({
        label = "to", width = 40,
        numeric = true,
        get = function() return tostring(RecruitingToolDB.maxLevel) end,
        set = SetMaxLevel,
        tooltip = { "Level Range", "Only players in this level range are searched for with /who." },
    }, 142)
    panel.cooldownInput = row:EditBox({
        label = "Cooldown (days):", width = 40,
        numeric = true,
        get = function() return tostring(RecruitingToolDB.cooldownDays) end,
        set = SetCooldown,
        tooltip = { "Cooldown", "A player you've messaged is left out of new scans, and listed as sent, until this many days have passed. At most 14." },
    }, 230)

    row = L:Row(18)
    row:Text({ text = "Message (use %GUILD% for guild name):", font = "GameFontNormal" }, 12)
    panel.msgInput = L:EditBox({
        width = 400,
        get = function() return RecruitingToolDB.message end,
        set = SetMessage,
        tooltip = { "Message", "The whisper sent to each player. %GUILD% is replaced with the guild name." },
    })

    L:Checkbox({
        label = "Hide outgoing recruitment whispers from chat",
        get = function() return RecruitingToolDB.hideWhispers end,
        set = function(v) RecruitingToolDB.hideWhispers = v end,
        tooltip = { "Hide Outgoing Whispers", "Keeps your own whispers out of the chat window when their text is exactly the recruitment message." },
    })

    -- Class grid: five per row
    L:Header("Classes to scan:")
    panel.classCheckboxes = {}
    for i, className in ipairs(classes) do
        if (i - 1) % 5 == 0 then row = L:Row(24) end
        panel.classCheckboxes[className] = row:Checkbox({
            label = className,
            get = function() return RecruitingToolDB.enabledClasses[className] end,
            set = function(v) RecruitingToolDB.enabledClasses[className] = v end,
            tooltip = { className, "Include " .. className .. "s in the scan. Unticked classes are skipped." },
        }, 8 + ((i - 1) % 5) * 84)
    end

    L:Space(6)
    row = L:Row(20)
    row:Text({ text = "Status:", font = "GameFontNormal" }, 12)
    panel.statusText = row:Text({ text = StatusLine, font = "GameFontHighlight" }, 70)
    row = L:Row(20)
    panel.harvestText = row:Text({ text = HarvestLine }, 12)
    panel.whisperedText = row:Text({ text = WhisperedLine }, 220)

    local buttons = L:Buttons({
        { text = "Start Scan", width = 80,
          onClick = function()
              SetGuildName(panel.guildInput:GetText())
              SetMinLevel(panel.minLvlInput:GetText())
              SetMaxLevel(panel.maxLvlInput:GetText())
              SetCooldown(panel.cooldownInput:GetText())
              SetMessage(panel.msgInput:GetText())
              Recruiter:StartScan()
          end,
          tooltip = { "Start Scan", "Runs one /who per ticked class and letter (a to z) in the level range, collecting unguilded players who aren't on cooldown. The scan pauses after each result for Continue." } },
        { text = "Stop", width = 80,
          onClick = function() Recruiter:StopScan() end,
          tooltip = { "Stop", "Ends the scan. Players found so far stay in the list." } },
        { text = "Continue", width = 80,
          onClick = function() Recruiter:ContinueScan() end,
          disabled = function() return not (isScanning and waitingForContinue) end,
          tooltip = { "Continue", "Runs the next /who query of the scan." } },
        { text = "Clear Results", width = 100,
          onClick = function()
              Recruiter:ClearHarvest()
              Recruiter:Print("Harvest cleared")
              Recruiter:UpdateUI()
              if messageFrame and messageFrame:IsShown() then
                  Recruiter:UpdateMessageList()
              end
          end,
          tooltip = { "Clear Results", "Empties the list of harvested players. Whisper history and cooldowns are kept." } },
    }, -4)
    panel.startBtn, panel.stopBtn, panel.continueBtn, panel.clearHarvestBtn = buttons[1], buttons[2], buttons[3], buttons[4]

    buttons = L:Buttons({
        { text = "|cFFFFD700Show Messages|r", width = 140,
          onClick = function() Recruiter:ShowMessageList() end,
          tooltip = { "Show Messages", "Opens the list of harvested players, each with a button that puts the whisper in your chat box." } },
        { text = "Test Message", width = 100,
          onClick = function()
              SetGuildName(panel.guildInput:GetText())
              SetMessage(panel.msgInput:GetText())
              local playerName = UnitName("player")
              Recruiter:OpenWhisperPrompt(playerName)
              Recruiter:Print("Chat prefilled with test whisper to yourself - press Enter to send")
          end,
          tooltip = { "Test Message", "Puts the whisper, addressed to yourself, in the chat box. Press Enter to send it and see how it reads." } },
    }, -4)
    panel.showMsgBtn, panel.testBtn = buttons[1], buttons[2]

    row = L:Row(24)
    row:Text({ text = "Activity Log:", font = "GameFontNormal" }, 12)
    panel.viewHistoryBtn = row:Button({
        text = "View History", width = 90,
        onClick = function() Recruiter:ShowHistoryWindow() end,
        tooltip = { "View History", "Lists every player you've messaged, newest first." },
    }, 105)
    row:Button({
        text = "Clear Log", width = 80,
        onClick = function()
            RecruitingToolDB.activityLog = {}
            Recruiter:UpdateLogDisplay()
        end,
        tooltip = { "Clear Log", "Empties the activity log below." },
    }, 200)

    local fill = L:Fill(80)
    panel.logFrame, panel.logChild = CreateLogList(fill, 370)

    panel:AddFooterButton({
        text = "Clear History", width = 100,
        onClick = function() StaticPopup_Show("WM_RECRUITER_CLEAR_HISTORY") end,
        tooltip = { "Clear History", "Forgets every player you've messaged, so their cooldowns end, and empties the harvest list. Asks first." },
    })

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

    panel:Finish()

    mainFrame = panel
    self.mainFrame = panel

    return panel
end

function Recruiter:UpdateUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    mainFrame.statusText:SetText(StatusLine())
    mainFrame.harvestText:SetText(HarvestLine())
    mainFrame.whisperedText:SetText(WhisperedLine())
    mainFrame.continueBtn:Refresh()

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

local function CountLine()
    local sent = Recruiter:CountSentInHarvest()
    local total = #harvestedPlayers
    return string.format(
        "|cFFFFFFFF%d|r harvested  -  |cFF00FF00%d|r ready  -  |cFF888888%d|r marked sent",
        total, total - sent, sent
    )
end

function Recruiter:ShowMessageList()
    if not messageFrame then
        self:CreateMessageFrame()
    end

    if messageFrame:IsShown() then
        messageFrame:Hide()
    else
        messageFrame:Show()   -- OnShow fills the list
    end
end

function Recruiter:CreateMessageFrame()
    local panel = WM.UI:CreatePanel({
        name = "WM_RecruiterMessageFrame",
        title = "Whisper Messages",
        titleColor = "FFD700",
        width = 480,
        height = 520,
        minHeight = 300,
        scroll = false,
        onShow = function() Recruiter:UpdateMessageList() end,
        defaultPoint = { "CENTER", 280, 0 },   -- beside the main window, not on top of it
    })
    local L = panel.layout

    L:Note("Click |cFF00FF00Send|r to prefill chat with the whisper. Press Enter in chat to actually send.\nThe row marks itself sent on click; use |cFFFFAA00Unmark|r if you didn't actually send it.")

    local row = L:Row(28)
    panel.countText = row:Text({ text = CountLine, font = "GameFontNormal" }, 8)
    row:RightButton({
        text = "Clear List", width = 100, height = 22,
        onClick = function()
            Recruiter:ClearHarvest()
            Recruiter:UpdateMessageList()
            Recruiter:UpdateUI()
        end,
        tooltip = { "Clear List", "Empties the list of harvested players. Whisper history and cooldowns are kept." },
    }, 0)
    row:RightButton({
        text = "Mark All Sent", width = 110, height = 22,
        onClick = function() StaticPopup_Show("WM_RECRUITER_MARK_ALL_SENT") end,
        tooltip = { "Mark All Sent", "Marks every ready player in the list as messaged, starting their cooldown, without whispering them. Asks first." },
    }, 105)

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

    -- Scroll list of player rows in the remaining space
    local fill = L:Fill(120)
    panel.scrollFrame, panel.scrollChild = CreateLogList(fill, 480 - 24 - 8 - 23)
    panel.rows = {}

    panel:Finish()
    messageFrame = panel
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

    messageFrame.countText:SetText(CountLine())

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
                if not Recruiter:OpenWhisperPrompt(name) then return end
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

function Recruiter:ShowHistoryWindow()
    if not historyFrame then
        local panel = WM.UI:CreatePanel({
            name = "WM_RecruiterHistoryFrame",
            title = "Whisper History",
            titleColor = "FFD700",
            width = 400,
            height = 450,
            minHeight = 250,
            scroll = false,
            onShow = function() Recruiter:UpdateHistoryDisplay() end,
            defaultPoint = { "CENTER", 250, 0 },
        })
        local L = panel.layout

        -- Filled by UpdateHistoryDisplay, so not a tracked (Refresh-reset) text
        local row = L:Row(22)
        panel.countText = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.countText:SetPoint("LEFT", 8, 0)

        local fill = L:Fill(100)
        panel.scrollFrame, panel.scrollChild = CreateLogList(fill, 340)
        panel.historyEntries = {}

        panel:Finish()
        historyFrame = panel
    end

    if historyFrame:IsShown() then
        historyFrame:Hide()
    else
        historyFrame:Show()   -- OnShow fills the list
    end
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
        frame:Show()   -- OnShow runs UpdateUI
    end
end

function Recruiter:Toggle()
    self:ToggleUI()
end

-- Turned off on this character: stop a scan in progress and close the
-- windows. The harvested list is kept for when it's turned back on.
function Recruiter:OnModuleOff()
    isScanning, waitingForContinue, scanTimer = false, false, 0
    if StaticPopup_Hide then
        StaticPopup_Hide("WM_RECRUITER_CLEAR_HISTORY")
        StaticPopup_Hide("WM_RECRUITER_MARK_ALL_SENT")
    end
    if mainFrame then mainFrame:Hide() end
    if messageFrame then messageFrame:Hide() end
    if historyFrame then historyFrame:Hide() end
end

-- The module's page in the guided setup
function Recruiter:SetupPage(L)
    self:InitDB()
    L:Note("Finds players with no guild and helps you send each of them your recruiting message. It never"
        .. " whispers anyone by itself: every message is sent by you, one at a time.")
    L:Note("|cFFFFFFFFScanning:|r Start Scan in the window runs a /who for each ticked class and letter in your"
        .. " level range, and waits for you to click Continue before the next one. Players with no guild are"
        .. " collected into a list.")
    L:Note("|cFFFFFFFFSending:|r in Show Messages, each Send button puts the whisper in your chat box. Nothing"
        .. " is sent until you press Enter. The player is then marked as messaged, and left out of new scans"
        .. " until the cooldown below has passed, so nobody is messaged twice in that time.")
    L:Note("|cFFFFCC00Please recruit kindly:|r unasked-for whispers annoy people, and many reports of spam can"
        .. " get your account silenced. Keep the message short, don't send dozens in a row, and leave people"
        .. " alone if they say no.")
    L:EditBox({
        label = "Guild name:", width = 180,
        get = function() return RecruitingToolDB.guildName end,
        set = function(v) if v ~= "" then SetGuildName(v) end end,
        tooltip = { "Guild Name", "Replaces %GUILD% in the message." },
    })
    L:Note("Message (%GUILD% becomes your guild's name):")
    L:EditBox({
        width = math.max(200, (L.width or 400) - 40),
        get = function() return RecruitingToolDB.message end,
        set = function(v) if v ~= "" then SetMessage(v) end end,
        tooltip = { "Message", "The whisper each player gets. You can see it in your chat box before you"
            .. " send it, and Test Message in the window sends it to yourself first." },
    })
    L:EditBox({
        label = "Lowest level:", width = 40, numeric = true,
        get = function() return tostring(RecruitingToolDB.minLevel) end,
        set = SetMinLevel,
        tooltip = { "Level Range", "Only players from this level up are searched for." },
    })
    L:EditBox({
        label = "Highest level:", width = 40, numeric = true,
        get = function() return tostring(RecruitingToolDB.maxLevel) end,
        set = SetMaxLevel,
        tooltip = { "Level Range", "Only players up to this level are searched for." },
    })
    L:EditBox({
        label = "Cooldown (days):", width = 40, numeric = true,
        get = function() return tostring(RecruitingToolDB.cooldownDays) end,
        set = SetCooldown,
        tooltip = { "Cooldown", "How long a player you've messaged is left out of new scans and shown as sent."
            .. " At most 14 days. The list of who you've messaged is shared by all your characters." },
    })
    L:Checkbox({
        label = "Hide my recruitment whispers from chat",
        get = function() return RecruitingToolDB.hideWhispers end,
        set = function(v) RecruitingToolDB.hideWhispers = v end,
        tooltip = { "Hide Outgoing Whispers", "Keeps your own whispers out of the chat window when their text is"
            .. " exactly the recruitment message, so a run of them doesn't fill your chat." },
    })
    L:Note("Which classes to scan, your whisper history and the activity log are in the Recruiting Tool"
        .. " window: |cFFFFFF00/wmachine recruit|r.")
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local whoEventFrame = CreateFrame("Frame")
whoEventFrame:RegisterEvent("WHO_LIST_UPDATE")
whoEventFrame:SetScript("OnEvent", function()
    if isScanning and On() then
        Recruiter:ProcessWhoResults()
    end
end)

-- OnUpdate for scan timer only (auto-send is gone)
local updateFrame = CreateFrame("Frame")
local uiUpdateTimer = 0
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not On() then return end
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
