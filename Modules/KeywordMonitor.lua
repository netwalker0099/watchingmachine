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
            position = {},
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

function KeywordMonitor:UpdateStopButton()
    if not self.stopButton or not self.statusText then return end
    
    if isMonitoringPaused then
        self.stopButton:SetText("Resume")
        self.statusText:SetText("|cffff0000PAUSED|r")
    else
        self.stopButton:SetText("Stop")
        self.statusText:SetText("|cff00ff00ACTIVE|r")
    end
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

function KeywordMonitor:UpdateKeywordList()
    if not self.keywordDisplay then return end
    
    local keywords = {}
    for kw, _ in pairs(KeywordMonitorDB.keywords) do
        table.insert(keywords, kw)
    end
    
    if #keywords == 0 then
        self.keywordDisplay:SetText("Active: |cFF888888(none)|r")
    else
        self.keywordDisplay:SetText("Active: |cFF00FF00" .. table.concat(keywords, ", ") .. "|r")
    end
end

function KeywordMonitor:UpdateHistoryDisplay()
    if not self.historyContainer then return end
    
    -- Clear existing buttons
    if self.historyButtons then
        for _, btn in ipairs(self.historyButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
    end
    self.historyButtons = {}
    
    local xOffset = 0
    for i, keyword in ipairs(KeywordMonitorDB.keywordHistory) do
        local btn = CreateFrame("Button", nil, self.historyContainer, "UIPanelButtonTemplate")
        btn:SetHeight(18)
        btn:SetText(keyword)
        btn:SetWidth(btn:GetFontString():GetStringWidth() + 20)
        btn:SetPoint("LEFT", xOffset, 0)
        btn:SetScript("OnClick", function()
            KeywordMonitorDB.keywords[keyword] = true
            self:UpdateKeywordList()
        end)
        
        table.insert(self.historyButtons, btn)
        xOffset = xOffset + btn:GetWidth() + 3
        
        if xOffset > 350 then break end
    end
end

function KeywordMonitor:UpdateResultsDisplay()
    if not self.resultsScrollChild then return end
    
    CleanupOldResults()
    
    -- Clear existing frames
    if self.resultFrames then
        for _, frame in ipairs(self.resultFrames) do
            frame:Hide()
            frame:SetParent(nil)
        end
    end
    self.resultFrames = {}
    
    local yOffset = 0
    local frameHeight = 45
    local spacing = 3
    
    for i, result in ipairs(KeywordMonitorDB.results) do
        local frame = self:CreateResultFrame(result)
        frame:SetParent(self.resultsScrollChild)
        frame:SetPoint("TOPLEFT", 0, -yOffset)
        frame:SetPoint("RIGHT", 0, 0)
        frame:Show()
        
        table.insert(self.resultFrames, frame)
        yOffset = yOffset + frameHeight + spacing
    end
    
    self.resultsScrollChild:SetHeight(math.max(yOffset, 1))
end

function KeywordMonitor:CreateResultFrame(result)
    local frame = CreateFrame("Button", nil, nil, "BackdropTemplate")
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
        self:SetBackdropColor(0.25, 0.25, 0.25, 0.95)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Left-click: Whisper " .. result.sender, 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Copy message", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        GameTooltip:Hide()
    end)
    
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            ChatFrame_OpenChat("/w " .. result.sender .. " ", DEFAULT_CHAT_FRAME)
        elseif button == "RightButton" then
            ChatFrame_OpenChat(result.message, DEFAULT_CHAT_FRAME)
        end
    end)
    
    -- Header
    local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerText:SetPoint("TOPLEFT", 5, -5)
    headerText:SetPoint("RIGHT", -5, 0)
    headerText:SetJustifyH("LEFT")
    
    local timeAgo = FormatTimeAgo(result.timestamp)
    headerText:SetText("|cff888888" .. timeAgo .. "|r  |cff4488ff[" .. result.channel .. "]|r  |cffffff00" .. result.sender .. "|r  |cff00ff00<" .. result.keyword .. ">|r")
    
    -- Message
    local messageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    messageText:SetPoint("TOPLEFT", 5, -20)
    messageText:SetPoint("BOTTOMRIGHT", -5, 5)
    messageText:SetJustifyH("LEFT")
    messageText:SetJustifyV("TOP")
    messageText:SetWordWrap(true)
    messageText:SetMaxLines(2)
    messageText:SetText(result.message)
    
    return frame
end

function KeywordMonitor:CreateMainFrame()
    if self.mainFrame then return end
    
    local frame = CreateFrame("Frame", "WM_KeywordMonitorFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 580)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        KeywordMonitorDB.position = {point, relPoint, x, y}
    end)
    frame:Hide()
    
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    
    -- Restore position
    if KeywordMonitorDB.position and #KeywordMonitorDB.position >= 4 then
        frame:ClearAllPoints()
        frame:SetPoint(KeywordMonitorDB.position[1], UIParent, KeywordMonitorDB.position[2], 
                      KeywordMonitorDB.position[3], KeywordMonitorDB.position[4])
    end
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFFAA00Keyword Monitor|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    frame:SetResizeBounds(400, 480, 800, 800)
    
    -- ========== Keywords Section ==========
    local keywordSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    keywordSection:SetPoint("TOPLEFT", 15, -40)
    keywordSection:SetPoint("TOPRIGHT", -15, -40)
    keywordSection:SetHeight(70)
    keywordSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    keywordSection:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    local keywordLabel = keywordSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keywordLabel:SetPoint("TOPLEFT", 8, -8)
    keywordLabel:SetText("Keywords:")
    
    local keywordInput = CreateFrame("EditBox", nil, keywordSection, "InputBoxTemplate")
    keywordInput:SetSize(120, 20)
    keywordInput:SetPoint("TOPLEFT", 8, -25)
    keywordInput:SetAutoFocus(false)
    keywordInput:SetScript("OnEnterPressed", function(self)
        local text = strtrim(self:GetText() or "")
        if text ~= "" then
            KeywordMonitorDB.keywords[text] = true
            AddToHistory(text)
            KeywordMonitor:UpdateKeywordList()
            KeywordMonitor:UpdateHistoryDisplay()
            self:SetText("")
        end
        self:ClearFocus()
    end)
    
    local addBtn = CreateFrame("Button", nil, keywordSection, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("LEFT", keywordInput, "RIGHT", 5, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local text = strtrim(keywordInput:GetText() or "")
        if text ~= "" then
            KeywordMonitorDB.keywords[text] = true
            AddToHistory(text)
            KeywordMonitor:UpdateKeywordList()
            KeywordMonitor:UpdateHistoryDisplay()
            keywordInput:SetText("")
        end
    end)
    
    local clearAllBtn = CreateFrame("Button", nil, keywordSection, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(60, 22)
    clearAllBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
    clearAllBtn:SetText("Clear All")
    clearAllBtn:SetScript("OnClick", function()
        KeywordMonitorDB.keywords = {}
        KeywordMonitor:UpdateKeywordList()
    end)
    
    local keywordDisplay = keywordSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keywordDisplay:SetPoint("TOPLEFT", 8, -50)
    keywordDisplay:SetPoint("RIGHT", -8, 0)
    keywordDisplay:SetJustifyH("LEFT")
    keywordDisplay:SetWordWrap(true)
    self.keywordDisplay = keywordDisplay
    
    -- ========== History Section ==========
    local historySection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    historySection:SetPoint("TOPLEFT", keywordSection, "BOTTOMLEFT", 0, -5)
    historySection:SetPoint("TOPRIGHT", keywordSection, "BOTTOMRIGHT", 0, -5)
    historySection:SetHeight(50)
    historySection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    historySection:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    local historyLabel = historySection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyLabel:SetPoint("TOPLEFT", 8, -8)
    historyLabel:SetText("Recent Keywords (click to add):")
    
    local historyContainer = CreateFrame("Frame", nil, historySection)
    historyContainer:SetPoint("TOPLEFT", 8, -25)
    historyContainer:SetPoint("BOTTOMRIGHT", -8, 5)
    self.historyContainer = historyContainer
    self.historyButtons = {}
    
    -- ========== Channels Section ==========
    local channelSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    channelSection:SetPoint("TOPLEFT", historySection, "BOTTOMLEFT", 0, -5)
    channelSection:SetPoint("TOPRIGHT", historySection, "BOTTOMRIGHT", 0, -5)
    channelSection:SetHeight(72)
    channelSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    channelSection:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    local channelLabel = channelSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("TOPLEFT", 8, -8)
    channelLabel:SetText("Channels:")
    
    -- Stop/Resume button
    local stopBtn = CreateFrame("Button", nil, channelSection, "UIPanelButtonTemplate")
    stopBtn:SetSize(70, 22)
    stopBtn:SetPoint("TOPRIGHT", -8, -6)
    self.stopButton = stopBtn
    
    local statusText = channelSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("RIGHT", stopBtn, "LEFT", -8, 0)
    self.statusText = statusText
    
    stopBtn:SetScript("OnClick", function()
        isMonitoringPaused = not isMonitoringPaused
        KeywordMonitor:UpdateStopButton()
    end)
    self:UpdateStopButton()
    
    -- Channel checkboxes
    local channels = {"Trade", "General", "LookingForGroup", "LocalDefense", "WorldDefense", "GuildRecruitment", "Services"}
    local xPos, yPos = 8, -25
    self.channelCheckboxes = {}
    
    for _, channel in ipairs(channels) do
        local cb = CreateFrame("CheckButton", nil, channelSection, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", xPos, yPos)
        cb:SetChecked(KeywordMonitorDB.channels[channel] or false)
        cb:SetScript("OnClick", function(self)
            KeywordMonitorDB.channels[channel] = self:GetChecked()
        end)
        
        local cbLabel = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        
        local shortName = channel
        if channel == "LookingForGroup" then shortName = "LFG"
        elseif channel == "LocalDefense" then shortName = "LocalDef"
        elseif channel == "WorldDefense" then shortName = "WorldDef"
        elseif channel == "GuildRecruitment" then shortName = "GuildRecruit"
        end
        cbLabel:SetText(shortName)
        
        self.channelCheckboxes[channel] = cb
        xPos = xPos + 75
        if xPos > 400 then
            xPos = 8
            yPos = yPos - 22
        end
    end
    
    -- ========== Alert Section ==========
    local alertSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    alertSection:SetPoint("TOPLEFT", channelSection, "BOTTOMLEFT", 0, -5)
    alertSection:SetPoint("TOPRIGHT", channelSection, "BOTTOMRIGHT", 0, -5)
    alertSection:SetHeight(45)
    alertSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    alertSection:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    local alertLabel = alertSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alertLabel:SetPoint("TOPLEFT", 8, -8)
    alertLabel:SetText("Alerts:")
    
    local chatAlertCB = CreateFrame("CheckButton", nil, alertSection, "UICheckButtonTemplate")
    chatAlertCB:SetSize(24, 24)
    chatAlertCB:SetPoint("TOPLEFT", 8, -24)
    chatAlertCB:SetChecked(KeywordMonitorDB.alertsEnabled)
    chatAlertCB:SetScript("OnClick", function(self)
        KeywordMonitorDB.alertsEnabled = self:GetChecked()
    end)
    
    local chatAlertLabel = chatAlertCB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chatAlertLabel:SetPoint("LEFT", chatAlertCB, "RIGHT", 0, 0)
    chatAlertLabel:SetText("Chat")
    
    local soundAlertCB = CreateFrame("CheckButton", nil, alertSection, "UICheckButtonTemplate")
    soundAlertCB:SetSize(24, 24)
    soundAlertCB:SetPoint("LEFT", chatAlertCB, "RIGHT", 50, 0)
    soundAlertCB:SetChecked(KeywordMonitorDB.soundEnabled)
    soundAlertCB:SetScript("OnClick", function(self)
        KeywordMonitorDB.soundEnabled = self:GetChecked()
    end)
    
    local soundAlertLabel = soundAlertCB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soundAlertLabel:SetPoint("LEFT", soundAlertCB, "RIGHT", 0, 0)
    soundAlertLabel:SetText("Sound")
    
    -- ========== Results Section ==========
    local resultsSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    resultsSection:SetPoint("TOPLEFT", alertSection, "BOTTOMLEFT", 0, -5)
    resultsSection:SetPoint("BOTTOMRIGHT", -15, 15)
    resultsSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    resultsSection:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    local resultsLabel = resultsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultsLabel:SetPoint("TOPLEFT", 8, -8)
    resultsLabel:SetText("Recent Matches (click to whisper):")
    
    local clearResultsBtn = CreateFrame("Button", nil, resultsSection, "UIPanelButtonTemplate")
    clearResultsBtn:SetSize(80, 18)
    clearResultsBtn:SetPoint("TOPRIGHT", -8, -5)
    clearResultsBtn:SetText("Clear Results")
    clearResultsBtn:SetScript("OnClick", function()
        KeywordMonitorDB.results = {}
        KeywordMonitor:UpdateResultsDisplay()
    end)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, resultsSection, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 8)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    self.resultsScrollChild = scrollChild
    self.resultsScrollFrame = scrollFrame
    
    frame:SetScript("OnSizeChanged", function()
        local width = scrollFrame:GetWidth()
        scrollChild:SetWidth(width)
        KeywordMonitor:UpdateResultsDisplay()
    end)
    
    self.mainFrame = frame
    
    -- Initial update
    self:UpdateKeywordList()
    self:UpdateHistoryDisplay()
    self:UpdateResultsDisplay()
end

function KeywordMonitor:ToggleUI()
    if not self.mainFrame then
        self:CreateMainFrame()
    end
    
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
        self:UpdateStopButton()
        self:UpdateResultsDisplay()
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
