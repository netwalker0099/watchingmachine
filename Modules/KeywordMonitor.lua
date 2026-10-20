-- Watching Machine: Keyword Monitor Module
-- Monitor public channels for keywords with duplicate detection

local AddonName, WM = ...
local KeywordMonitor = {}
WM:RegisterModule("KeywordMonitor", KeywordMonitor)

local RETENTION_TIME = 300 -- 5 minutes
local isMonitoringPaused = false

-- ============================================
-- INITIALIZATION
-- ============================================

function KeywordMonitor:Initialize()
    self:InitDB()
    -- Reset monitoring state on login
    isMonitoringPaused = false
    -- Clear any stale results from previous session
    KeywordMonitorDB.results = {}
    -- Re-enable chat monitoring (may have been disabled on logout)
    self:EnableChatMonitoring()
end

function KeywordMonitor:InitDB()
    if not KeywordMonitorDB then
        KeywordMonitorDB = {
            keywords = {},
            channels = {
                ["Trade"] = true,
                ["General"] = true,
                ["LookingForGroup"] = true,
            },
            results = {},
            keywordHistory = {},
            alertsEnabled = true,
            soundEnabled = true,
        }
    end
    
    -- Ensure all fields exist
    if not KeywordMonitorDB.channels then
        KeywordMonitorDB.channels = { Trade = true, General = true, LookingForGroup = true }
    end
    if not KeywordMonitorDB.keywordHistory then KeywordMonitorDB.keywordHistory = {} end
    if KeywordMonitorDB.alertsEnabled == nil then KeywordMonitorDB.alertsEnabled = true end
    if KeywordMonitorDB.soundEnabled == nil then KeywordMonitorDB.soundEnabled = true end
end

-- ============================================
-- UTILITIES
-- ============================================

function KeywordMonitor:Print(msg)
    WM:ModulePrint("KeywordMonitor", msg)
end

-- Dashboard on/off switch: off = paused, the same as the Stop button.
-- Like Stop, it lasts for this session only.
function KeywordMonitor:IsModuleEnabled()
    return not isMonitoringPaused
end

function KeywordMonitor:SetModuleEnabled(v)
    isMonitoringPaused = not v
    self:UpdateStopButton()
end

function KeywordMonitor:UpdateStopButton()
    if not self.stopButton or not self.statusText then return end
    -- Both read isMonitoringPaused
    self.stopButton:Refresh()
    self.statusText:Refresh()
end

local function GetCurrentTime()
    return time()
end

local function FormatTimeAgo(timestamp)
    local diff = GetCurrentTime() - timestamp
    if diff < 60 then
        return string.format("%ds ago", diff)
    else
        return string.format("%dm %ds ago", math.floor(diff / 60), diff % 60)
    end
end

-- Add keyword to history
local function AddToHistory(keyword)
    local history = KeywordMonitorDB.keywordHistory
    for i = #history, 1, -1 do
        if string.lower(history[i]) == string.lower(keyword) then
            table.remove(history, i)
        end
    end
    table.insert(history, 1, keyword)
    while #history > 10 do
        table.remove(history)
    end
end

-- Clean old results
local function CleanupOldResults()
    if not KeywordMonitorDB or not KeywordMonitorDB.results then return end
    local currentTime = GetCurrentTime()
    local newResults = {}
    for _, result in ipairs(KeywordMonitorDB.results) do
        if (currentTime - result.timestamp) < RETENTION_TIME then
            table.insert(newResults, result)
        end
    end
    KeywordMonitorDB.results = newResults
end

-- Check for duplicate
local function IsDuplicate(sender, message, keyword)
    if not KeywordMonitorDB or not KeywordMonitorDB.results then return false end
    local currentTime = GetCurrentTime()
    local messageLower = string.lower(message)
    for _, result in ipairs(KeywordMonitorDB.results) do
        if result.sender == sender and 
           string.lower(result.message) == messageLower and 
           result.keyword == keyword and
           (currentTime - result.timestamp) < RETENTION_TIME then
            return true
        end
    end
    return false
end

-- Add result
local function AddResult(sender, message, channel, keyword)
    if not KeywordMonitorDB or not KeywordMonitorDB.results then return false end
    if IsDuplicate(sender, message, keyword) then
        return false
    end
    table.insert(KeywordMonitorDB.results, 1, {
        sender = sender,
        message = message,
        channel = channel,
        keyword = keyword,
        timestamp = GetCurrentTime(),
    })
    return true
end

-- Get channel base name
local function GetChannelName(channelName)
    local channelMap = {"Trade", "General", "LookingForGroup", "LocalDefense", "WorldDefense", "GuildRecruitment", "Services"}
    for _, name in ipairs(channelMap) do
        if string.find(channelName, name) then
            return name
        end
    end
    return nil
end

-- Check if channel monitored
local function IsChannelMonitored(channelName)
    if not KeywordMonitorDB or not KeywordMonitorDB.channels then return false, nil end
    local baseName = GetChannelName(channelName)
    if baseName and KeywordMonitorDB.channels[baseName] then
        return true, baseName
    end
    return false, nil
end

-- Check message for keywords
local function CheckMessageForKeywords(message)
    if not KeywordMonitorDB or not KeywordMonitorDB.keywords then return false, nil end
    local messageLower = string.lower(message)
    for keyword, _ in pairs(KeywordMonitorDB.keywords) do
        if string.find(messageLower, string.lower(keyword), 1, true) then
            return true, keyword
        end
    end
    return false, nil
end

-- ============================================
-- STATUS
-- ============================================

function KeywordMonitor:GetQuickStatus()
    if not KeywordMonitorDB then return "|cFF888888Not initialized|r" end
    
    local keywordCount = 0
    if KeywordMonitorDB.keywords then
        for _ in pairs(KeywordMonitorDB.keywords) do keywordCount = keywordCount + 1 end
    end
    
    if isMonitoringPaused then
        return "|cFFFF0000Paused|r (" .. keywordCount .. " keywords)"
    elseif keywordCount > 0 then
        local resultCount = KeywordMonitorDB.results and #KeywordMonitorDB.results or 0
        return "|cFF00FF00Active|r (" .. keywordCount .. " keywords, " .. resultCount .. " matches)"
    else
        return "|cFFFFFF00No keywords set|r"
    end
end

function KeywordMonitor:IsPaused()
    return isMonitoringPaused
end

function KeywordMonitor:SetPaused(paused)
    isMonitoringPaused = paused
end

-- ============================================
-- CHAT HANDLER
-- ============================================

local function OnChatMessage(self, event, message, sender, _, _, _, _, _, _, channelName)
    if isMonitoringPaused then return end
    if not KeywordMonitorDB then return end
    
    local isMonitored, baseName = IsChannelMonitored(channelName)
    if not isMonitored then return end
    
    local hasKeyword, keyword = CheckMessageForKeywords(message)
    if hasKeyword then
        local cleanSender = string.match(sender, "([^%-]+)") or sender
        
        if AddResult(cleanSender, message, baseName, keyword) then
            if KeywordMonitorDB.soundEnabled then
                PlaySound(8959, "Master")
            end
            
            if KeywordMonitorDB.alertsEnabled then
                print(string.format("|cFFFFAA00[WM:Keyword]|r |cffff0000%s|r in |cff4488ff[%s]|r from |cffffff00%s|r: %s", 
                    keyword, baseName, cleanSender, string.sub(message, 1, 80)))
            end
            
            if KeywordMonitor.mainFrame and KeywordMonitor.mainFrame:IsVisible() then
                KeywordMonitor:UpdateResultsDisplay()
            end
        end
    end
end

-- ============================================
-- UI
-- ============================================

local CHANNELS = {
    { key = "Trade", label = "Trade" },
    { key = "General", label = "General" },
    { key = "LookingForGroup", label = "LFG" },
    { key = "LocalDefense", label = "LocalDef" },
    { key = "WorldDefense", label = "WorldDef" },
    { key = "GuildRecruitment", label = "GuildRecruit" },
    { key = "Services", label = "Services" },
}

local function KeywordSummary()
    local keywords = {}
    for kw, _ in pairs(KeywordMonitorDB.keywords) do
        table.insert(keywords, kw)
    end
    if #keywords == 0 then return "Active: (none)" end
    table.sort(keywords)
    return "Active: |cFF00FF00" .. table.concat(keywords, ", ") .. "|r"
end

local function AddKeyword(text)
    text = strtrim(text or "")
    if text == "" then return end
    KeywordMonitorDB.keywords[text] = true
    AddToHistory(text)
    KeywordMonitor:UpdateKeywordList()
    KeywordMonitor:UpdateHistoryDisplay()
end

-- The active list is a wrapped note; re-measure so the rows below move
function KeywordMonitor:UpdateKeywordList()
    if not self.keywordDisplay then return end
    self.keywordDisplay:Refresh()
    self.mainFrame:Reflow()
end

-- One button per recent keyword, as many as fit the row (buttons pooled)
function KeywordMonitor:UpdateHistoryDisplay()
    local container = self.historyContainer
    if not container then return end

    local room = container:GetWidth()
    if not room or room <= 0 then room = self.mainFrame.layout.width - 68 end

    local x, full = 0, false
    for i, keyword in ipairs(KeywordMonitorDB.keywordHistory) do
        local btn = self.historyButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
            btn:SetHeight(18)
            btn:SetScript("OnClick", function(b)
                KeywordMonitorDB.keywords[b.keyword] = true
                KeywordMonitor:UpdateKeywordList()
            end)
            WM.UI.SetTooltip(btn, function()
                return { btn.keyword, "Click to make this an active keyword again." }
            end)
            self.historyButtons[i] = btn
        end
        btn.keyword = keyword
        btn:SetText(keyword)
        local w = btn:GetFontString():GetStringWidth() + 20
        btn:SetWidth(w)
        if full or x + w > room then
            full = true
            btn:Hide()
        else
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", container, "LEFT", x, 0)
            btn:Show()
            x = x + w + 3
        end
    end
    for i = #KeywordMonitorDB.keywordHistory + 1, #self.historyButtons do
        self.historyButtons[i]:Hide()
    end
end

function KeywordMonitor:UpdateResultsDisplay()
    if not self.resultsScrollChild then return end

    CleanupOldResults()

    -- Rows stretch to the scroll child, which follows the window width
    local width = self.resultsScrollFrame:GetWidth()
    if not width or width <= 0 then width = self.mainFrame:GetWidth() - 24 - 23 end
    self.resultsScrollChild:SetWidth(width)

    -- Reuse pooled frames — WoW frames are never garbage-collected, so
    -- recreating them every refresh (this runs once per second while the
    -- window is open) leaks memory permanently.
    self.resultFrames = self.resultFrames or {}

    local yOffset = 0
    local frameHeight = 45
    local spacing = 3

    for i, result in ipairs(KeywordMonitorDB.results) do
        local frame = self.resultFrames[i]
        if not frame then
            frame = self:CreateResultFrame()
            self.resultFrames[i] = frame
        end

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", 0, -yOffset)
        frame:SetPoint("RIGHT", 0, 0)
        frame:UpdateResult(result)
        frame:Show()

        yOffset = yOffset + frameHeight + spacing
    end

    -- Hide any leftover pooled frames beyond the current result count
    for i = #KeywordMonitorDB.results + 1, #self.resultFrames do
        self.resultFrames[i]:Hide()
    end

    self.resultsScrollChild:SetHeight(math.max(yOffset, 1))
end

function KeywordMonitor:CreateResultFrame()
    local frame = CreateFrame("Button", nil, self.resultsScrollChild, "BackdropTemplate")
    frame:SetHeight(45)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Hover highlight
    frame:SetScript("OnEnter", function(self)
        if not self.result then return end
        self:SetBackdropColor(0.25, 0.25, 0.25, 0.95)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Left-click: Whisper " .. self.result.sender, 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Copy message", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        GameTooltip:Hide()
    end)

    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if not self.result then return end
        if button == "LeftButton" then
            ChatFrame_OpenChat("/w " .. self.result.sender .. " ", DEFAULT_CHAT_FRAME)
        elseif button == "RightButton" then
            ChatFrame_OpenChat(self.result.message, DEFAULT_CHAT_FRAME)
        end
    end)

    -- Header
    local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerText:SetPoint("TOPLEFT", 5, -5)
    headerText:SetPoint("RIGHT", -5, 0)
    headerText:SetJustifyH("LEFT")
    frame.headerText = headerText

    -- Message
    local messageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    messageText:SetPoint("TOPLEFT", 5, -20)
    messageText:SetPoint("BOTTOMRIGHT", -5, 5)
    messageText:SetJustifyH("LEFT")
    messageText:SetJustifyV("TOP")
    messageText:SetWordWrap(true)
    messageText:SetMaxLines(2)
    frame.messageText = messageText

    -- Fill in data for a specific result (called on every refresh)
    frame.UpdateResult = function(self, result)
        self.result = result
        local timeAgo = FormatTimeAgo(result.timestamp)
        self.headerText:SetText("|cff888888" .. timeAgo .. "|r  |cff4488ff[" .. result.channel .. "]|r  |cffffff00" .. result.sender .. "|r  |cff00ff00<" .. result.keyword .. ">|r")
        self.messageText:SetText(result.message)
    end

    return frame
end

function KeywordMonitor:CreateMainFrame()
    if self.mainFrame then return self.mainFrame end

    -- Settings rows on top, the match list fills whatever height is left.
    -- Collapsing a section gives the list more room.
    local panel = WM.UI:CreatePanel({
        name = "WM_KeywordMonitorFrame",
        title = "Keyword Monitor",
        titleColor = "FFAA00",
        width = 500,
        height = 580,
        minHeight = 480,
        scroll = false,
        resizable = { 400, 480, 800, 800 },
        onResize = function()
            KeywordMonitor:UpdateHistoryDisplay()
            KeywordMonitor:UpdateResultsDisplay()
        end,
        onRefresh = function()
            KeywordMonitor:UpdateHistoryDisplay()
            KeywordMonitor:UpdateResultsDisplay()
        end,
    })
    self.mainFrame = panel
    local L = panel.layout

    -- Carry over the position saved by the old hand-built window
    local old = KeywordMonitorDB.position
    if old and #old >= 4 and not panel:GetState().pos then
        panel:GetState().pos = { old[1], old[2], old[3], old[4] }
        panel:ClearAllPoints()
        panel:SetPoint(old[1], UIParent, old[2], old[3], old[4])
    end
    KeywordMonitorDB.position = nil

    -- ---------- Monitoring status ----------
    local row = L:Row(26)
    self.statusText = row:Text({
        text = function()
            return "Monitoring: " .. (isMonitoringPaused and "|cffff0000PAUSED|r" or "|cff00ff00ACTIVE|r")
        end,
    }, 12)
    self.stopButton = row:RightButton({
        text = function() return isMonitoringPaused and "Resume" or "Stop" end,
        width = 70,
        onClick = function()
            isMonitoringPaused = not isMonitoringPaused
            KeywordMonitor:UpdateStopButton()
        end,
        tooltip = { "Stop / Resume", "Pause keyword matching. This lasts for this session only:"
            .. " monitoring starts again at your next login or reload." },
    }, 3)

    -- ---------- Keywords ----------
    L:Section({ key = "keywords", title = "Keywords" })
    row = L:Row(26)
    local addBox = row:EditBox({
        label = "Keyword:", width = 120, onEnter = AddKeyword, clearOnEnter = true,
        tooltip = { "Add Keyword", "Type a word or phrase and press Enter, or click Add. A message matches"
            .. " when it contains the keyword anywhere, ignoring case." },
    }, 12)
    row:Button({
        text = "Add", width = 50,
        onClick = function()
            AddKeyword(addBox:GetText())
            addBox:SetText("")
        end,
    }, 215)
    row:Button({
        text = "Clear All", width = 60,
        onClick = function()
            KeywordMonitorDB.keywords = {}
            KeywordMonitor:UpdateKeywordList()
        end,
        tooltip = { "Clear All", "Remove every active keyword. They stay in the Recent list below." },
    }, 270)
    self.keywordDisplay = L:Note(KeywordSummary).text

    row = L:Row(24)
    row:Text({ text = "|cFF888888Recent:|r" }, 12)
    local history = CreateFrame("Frame", nil, row.frame)
    history:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 60, 0)
    history:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", -8, 0)
    self.historyContainer = history
    self.historyButtons = {}

    -- ---------- Channels ----------
    L:Section({ key = "channels", title = "Channels" })
    self.channelCheckboxes = {}
    for i, ch in ipairs(CHANNELS) do
        if (i - 1) % 4 == 0 then row = L:Row(24) end
        self.channelCheckboxes[ch.key] = row:Checkbox({
            label = ch.label,
            get = function() return KeywordMonitorDB.channels[ch.key] end,
            set = function(v) KeywordMonitorDB.channels[ch.key] = v end,
            tooltip = { ch.key, "Check messages in any channel whose name contains \"" .. ch.key .. "\"." },
        }, 8 + ((i - 1) % 4) * 115)
    end

    -- ---------- Alerts ----------
    L:Section({ key = "alerts", title = "Alerts" })
    row = L:Row(24)
    row:Checkbox({
        label = "Chat alert",
        get = function() return KeywordMonitorDB.alertsEnabled end,
        set = function(v) KeywordMonitorDB.alertsEnabled = v end,
        tooltip = { "Chat Alert", "Print each new match in your chat frame. The same message from the same"
            .. " player isn't repeated within 5 minutes." },
    }, 8)
    row:Checkbox({
        label = "Sound alert",
        get = function() return KeywordMonitorDB.soundEnabled end,
        set = function(v) KeywordMonitorDB.soundEnabled = v end,
        tooltip = { "Sound Alert", "Play a sound on each new match (repeats within 5 minutes are silent)." },
    }, 123)
    L:EndSection()

    -- ---------- Results ----------
    row = L:Row(24)
    row:Text({ text = "Recent Matches (click to whisper):", font = "GameFontNormal" }, 8)
    row:RightButton({
        text = "Clear Results", width = 90, height = 18,
        onClick = function()
            KeywordMonitorDB.results = {}
            KeywordMonitor:UpdateResultsDisplay()
        end,
        tooltip = { "Clear Results", "Empty the match list. Matches also drop off on their own after 5 minutes." },
    }, 3)

    local fill = L:Fill(120)
    local scrollFrame = CreateFrame("ScrollFrame", nil, fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(500 - 24 - 23, 1)
    scrollFrame:SetScrollChild(scrollChild)
    self.resultsScrollChild = scrollChild
    self.resultsScrollFrame = scrollFrame

    panel:Finish()
    return panel
end

function KeywordMonitor:ToggleUI()
    local frame = self:CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function KeywordMonitor:Toggle()
    self:ToggleUI()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
-- Don't register CHAT_MSG_CHANNEL here - wait for Initialize() to call EnableChatMonitoring()
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_CHANNEL" then
        -- Extra safety check
        if not KeywordMonitorDB then return end
        OnChatMessage(self, event, ...)
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        -- Stop monitoring immediately
        isMonitoringPaused = true
        
        -- Clear results safely
        if KeywordMonitorDB then
            KeywordMonitorDB.results = {}
        end
        
        -- Hide and reset UI
        if KeywordMonitor.mainFrame then
            KeywordMonitor.mainFrame:Hide()
        end
        
        -- Unregister chat event to stop processing
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
    end
end)

-- Re-register chat event on login (called from Initialize)
function KeywordMonitor:EnableChatMonitoring()
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
end

-- Periodic cleanup
local updateFrame = CreateFrame("Frame")
local timeSinceLastUpdate = 0
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate >= 1 then
        timeSinceLastUpdate = 0
        if KeywordMonitor.mainFrame and KeywordMonitor.mainFrame:IsVisible() then
            KeywordMonitor:UpdateResultsDisplay()
        end
    end
end)
