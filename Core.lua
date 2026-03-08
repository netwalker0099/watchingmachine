-- Watching Machine
-- Comprehensive monitoring suite for WoW Classic TBC Anniversary
-- Author: Robert

local AddonName, WM = ...
_G.WatchingMachine = WM

WM.version = "2.5"
WM.modules = {}

-- ============================================
-- ERROR LOGGING (loads before everything else)
-- ============================================

WM._errorLog = {}
local MAX_ERRORS = 200
local WM_ERROR_PATTERNS = {
    "WatchingMachine", "watchingmachine", "WM_",
    "PvPTracker", "DebuffTracker", "AutoLogger",
    "KeywordMonitor", "MailLogger", "ServicesParser",
    "Recruiter", "WhisperLogs", "GuildInvite",
}

local origErrorHandler = geterrorhandler()
seterrorhandler(function(msg)
    local msgStr = tostring(msg or "unknown")
    
    -- Only capture WatchingMachine-related errors
    local isWM = false
    for _, pattern in ipairs(WM_ERROR_PATTERNS) do
        if msgStr:find(pattern, 1, true) then
            isWM = true
            break
        end
    end
    
    -- If not found in message, check stack trace
    if not isWM then
        local stack = debugstack(2, 6, 0) or ""
        for _, pattern in ipairs(WM_ERROR_PATTERNS) do
            if stack:find(pattern, 1, true) then
                isWM = true
                break
            end
        end
    end
    
    if isWM then
        local stack = debugstack(2, 8, 0) or ""
        local entry = date("%H:%M:%S") .. " | " .. msgStr
        if stack ~= "" then
            entry = entry .. " || STACK: " .. stack:gsub("\n", " >> ")
        end
        table.insert(WM._errorLog, entry)
        while #WM._errorLog > MAX_ERRORS do
            table.remove(WM._errorLog, 1)
        end
        if WatchingMachineDB then
            WatchingMachineDB.errorLog = WM._errorLog
        end
    end
    
    -- Always pass through to original handler
    if origErrorHandler then
        return origErrorHandler(msg)
    end
end)

-- Security Configuration
local REQUIRED_GUILD = "Socks and Sandals"
local OFFICER_RANK_THRESHOLD = 1  -- Rank index 0 = GM, 1 = Officer only

-- Security State
local isAuthorized = false
local isOfficer = false
local securityCheckComplete = false

-- ============================================
-- CLASSIC-COMPATIBLE TIMER FUNCTIONS
-- ============================================

local timerFrame = CreateFrame("Frame")
local timers = {}
local timerID = 0

local function RunAfter(delay, callback)
    timerID = timerID + 1
    local id = timerID
    timers[id] = { remaining = delay, callback = callback }
    return id
end

local function RunTicker(interval, callback)
    timerID = timerID + 1
    local id = timerID
    timers[id] = { remaining = interval, callback = callback, interval = interval, repeating = true }
    return id
end

timerFrame:SetScript("OnUpdate", function(self, elapsed)
    for id, timer in pairs(timers) do
        timer.remaining = timer.remaining - elapsed
        if timer.remaining <= 0 then
            timer.callback()
            if timer.repeating then
                timer.remaining = timer.interval
            else
                timers[id] = nil
            end
        end
    end
end)

-- Expose for modules
WM.RunAfter = RunAfter
WM.RunTicker = RunTicker

-- ============================================
-- CORE UTILITIES
-- ============================================

function WM:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[WatchingMachine]|r " .. msg)
end

function WM:ModulePrint(moduleName, msg)
    local colors = {
        AutoLogger = "00FF00",
        KeywordMonitor = "FFAA00",
        MailLogger = "FF69B4",
        ServicesParser = "00CCFF",
        WhisperLogs = "CC80FF",
        Recruiter = "FFD700",
        GuildInvite = "00FF00",
        DebuffTracker = "FFCC00",
        PvPTracker = "FF3333",
    }
    local color = colors[moduleName] or "FFFFFF"
    DEFAULT_CHAT_FRAME:AddMessage("|cFF" .. color .. "[WM:" .. moduleName .. "]|r " .. msg)
end

-- Verbose/diagnostic print — only shows when verbose mode is enabled
function WM:VerbosePrint(moduleName, msg)
    if not WatchingMachineDB or not WatchingMachineDB.verboseChat then return end
    local colors = {
        AutoLogger = "00FF00",
        KeywordMonitor = "FFAA00",
        MailLogger = "FF69B4",
        ServicesParser = "00CCFF",
        WhisperLogs = "CC80FF",
        Recruiter = "FFD700",
        GuildInvite = "00FF00",
        DebuffTracker = "FFCC00",
        PvPTracker = "FF3333",
    }
    local color = colors[moduleName] or "FFFFFF"
    DEFAULT_CHAT_FRAME:AddMessage("|cFF888888[WM:" .. moduleName .. "] " .. msg .. "|r")
end

-- Register a module
function WM:RegisterModule(name, module)
    self.modules[name] = module
    module.name = name
end

-- ============================================
-- GLOBAL UI THEME SYSTEM
-- ============================================

WM.THEMES = {
    ["Default"] = {
        panel = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            tileSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
            bgColor = nil,      -- nil = use texture default
            borderColor = nil,
            outerBorder = false,
        },
        card = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            tileSize = 16,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
            bgColor = { 0.1, 0.1, 0.1, 0.9 },
            outerBorder = false,
        },
        titleBar = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            bgColor = { 0.1, 0.1, 0.1, 0.9 },
            height = 18,
            fontColor = { 1, 0.8, 0, 1 },
            accentLine = false,
        },
        indicator = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            bgColor = { 0.2, 0.2, 0.2, 0.8 },
            borderColor = { 0.5, 0.5, 0.5, 1 },
            activeColor = { 0, 1, 0, 1 },
            warningColor = { 1, 1, 0, 1 },
            missingColor = { 1, 0, 0, 1 },
            inactiveColor = { 0.5, 0.5, 0.5, 1 },
        },
        button = {
            template = "UIPanelButtonTemplate",  -- Use standard Blizzard buttons
        },
        headerColor = { 1, 0.8, 0, 1 },
        separatorColor = { 0.4, 0.4, 0.4, 0.5 },
        addonTitleColor = { 0, 0.8, 1, 1 },
    },
    ["ElvUI"] = {
        panel = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            tileSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.92 },
            borderColor = { 0.15, 0.15, 0.15, 1 },
            outerBorder = true,
            outerBorderColor = { 0, 0, 0, 1 },
        },
        card = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            tileSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
            bgColor = { 0.08, 0.08, 0.08, 0.95 },
            outerBorder = false,
        },
        titleBar = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            bgColor = { 0.1, 0.1, 0.1, 0.95 },
            height = 16,
            fontColor = { 0.84, 0.75, 0.65, 1 },
            accentLine = true,
            accentColor = { 0.18, 0.18, 0.18, 1 },
        },
        indicator = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            bgColor = { 0.08, 0.08, 0.08, 0.9 },
            borderColor = { 0.18, 0.18, 0.18, 1 },
            activeColor = { 0.18, 0.78, 0.18, 1 },
            warningColor = { 0.9, 0.8, 0.1, 1 },
            missingColor = { 0.78, 0.18, 0.18, 1 },
            inactiveColor = { 0.25, 0.25, 0.25, 1 },
        },
        button = {
            template = "UIPanelButtonTemplate",  -- Still use Blizzard buttons (ElvUI skins these itself)
        },
        headerColor = { 0.84, 0.75, 0.65, 1 },
        separatorColor = { 0.18, 0.18, 0.18, 0.8 },
        addonTitleColor = { 0.84, 0.75, 0.65, 1 },
    },
}

WM.THEME_LIST = { "Default", "ElvUI" }

function WM:GetTheme()
    local themeName = WatchingMachineDB and WatchingMachineDB.theme or "Default"
    return self.THEMES[themeName] or self.THEMES["Default"]
end

function WM:GetThemeName()
    return WatchingMachineDB and WatchingMachineDB.theme or "Default"
end

-- Helper: Create Tukui-style outer border (pixel double-border)
function WM:CreateOuterBorder(parent, color)
    if parent._wmOuterBorder then
        parent._wmOuterBorder:Show()
        if color then
            parent._wmOuterBorder:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
        end
        return parent._wmOuterBorder
    end
    
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(math.max(parent:GetFrameLevel() - 1, 0))
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    local c = color or { 0, 0, 0, 1 }
    border:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    
    parent._wmOuterBorder = border
    return border
end

function WM:RemoveOuterBorder(parent)
    if parent._wmOuterBorder then
        parent._wmOuterBorder:Hide()
    end
end

-- Apply theme to a main panel frame (settings windows, dashboard)
function WM:SkinPanel(frame)
    local t = self:GetTheme().panel
    frame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = t.tileSize, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    if t.bgColor then frame:SetBackdropColor(unpack(t.bgColor)) end
    if t.borderColor then frame:SetBackdropBorderColor(unpack(t.borderColor)) end
    if t.outerBorder then
        self:CreateOuterBorder(frame, t.outerBorderColor)
    else
        self:RemoveOuterBorder(frame)
    end
end

-- Apply theme to a card/sub-panel frame (module cards, inner panels)
function WM:SkinCard(frame, moduleColor)
    local t = self:GetTheme().card
    frame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = t.tileSize or 16, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    if t.bgColor then frame:SetBackdropColor(unpack(t.bgColor)) end
    if moduleColor then
        frame:SetBackdropBorderColor(moduleColor[1], moduleColor[2], moduleColor[3], 0.8)
    end
    if t.outerBorder then
        self:CreateOuterBorder(frame, t.outerBorderColor)
    else
        self:RemoveOuterBorder(frame)
    end
end

-- Auto-detect ElvUI/Tukui on first run
function WM:DetectTheme()
    if WatchingMachineDB._themeDetected then return end
    WatchingMachineDB._themeDetected = true
    
    local elvLoaded = false
    if IsAddOnLoaded then
        elvLoaded = IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")
    elseif C_AddOns and C_AddOns.IsAddOnLoaded then
        elvLoaded = C_AddOns.IsAddOnLoaded("ElvUI") or C_AddOns.IsAddOnLoaded("Tukui")
    end
    
    if elvLoaded then
        WatchingMachineDB.theme = "ElvUI"
        self:Print("ElvUI/Tukui detected - auto-selected ElvUI theme. Change in /wmachine settings")
    end
end

-- Register frames so we can re-skin them on theme change
WM._skinnedPanels = {}
WM._skinnedCards = {}

function WM:RegisterSkinnedPanel(frame)
    self._skinnedPanels[frame] = true
end

function WM:RegisterSkinnedCard(frame, color)
    self._skinnedCards[frame] = color or {1,1,1}
end

function WM:ReskinAll()
    for frame in pairs(self._skinnedPanels) do
        if frame and frame.SetBackdrop then
            self:SkinPanel(frame)
        end
    end
    for frame, color in pairs(self._skinnedCards) do
        if frame and frame.SetBackdrop then
            self:SkinCard(frame, color)
        end
    end
end

-- ============================================
-- SECURITY CHECKS
-- ============================================

function WM:CheckGuildSecurity()
    if not IsInGuild() then
        isAuthorized = false
        isOfficer = false
        securityCheckComplete = true
        return false
    end
    
    local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")
    
    if not guildName then
        -- Guild info not loaded yet, try again later
        return nil
    end
    
    securityCheckComplete = true
    
    -- Check guild name (case-insensitive)
    if guildName:lower() == REQUIRED_GUILD:lower() then
        isAuthorized = true
        
        -- Check officer status (GM = 0, Officer = 1)
        if guildRankIndex and guildRankIndex <= OFFICER_RANK_THRESHOLD then
            isOfficer = true
        else
            isOfficer = false
        end
        
        return true
    else
        isAuthorized = false
        isOfficer = false
        return false
    end
end

function WM:IsAuthorized()
    return isAuthorized
end

function WM:IsOfficer()
    return isOfficer
end

function WM:IsSecurityCheckComplete()
    return securityCheckComplete
end

function WM:OnSecurityCheckFailed()
    -- Hide dashboard if open (but keep minimap button visible for user preference)
    if dashboard then
        dashboard:Hide()
    end
    
    -- Silently fail - don't announce to non-guild members
end

function WM:OnSecurityCheckPassed()
    -- Minimap button visibility is managed by CreateMinimapButton based on minimapHidden setting
    
    -- Auto-detect ElvUI/Tukui theme on first run
    self:DetectTheme()
    
    self:Print("Loaded v" .. self.version .. ". Type /wmachine to open dashboard.")
    
    -- Initialize authorized modules
    for name, module in pairs(self.modules) do
        -- Skip Recruiter for non-officers
        if name == "Recruiter" and not isOfficer then
            -- Don't initialize
        elseif module.Initialize then
            module:Initialize()
        end
    end
    
    -- Start dashboard update timer
    RunTicker(2, function()
        if isAuthorized then
            self:UpdateDashboard()
        end
    end)
end

-- ============================================
-- SAVED VARIABLES INITIALIZATION
-- ============================================

local coreDefaults = {
    minimapPos = 220,
    minimapHidden = false,
    dashboardPos = nil,
    theme = "Default",
    verboseChat = false,    -- Show diagnostic/sync messages in chat
    moduleStates = {
        AutoLogger = true,
        KeywordMonitor = true,
        MailLogger = true,
        ServicesParser = true,
        WhisperLogs = true,
        GuildInvite = true,
        DebuffTracker = true,
        PvPTracker = true,
        Recruiter = true,
    },
}

local function InitCoreDB()
    if not WatchingMachineDB then
        WatchingMachineDB = {}
    end
    for k, v in pairs(coreDefaults) do
        if WatchingMachineDB[k] == nil then
            if type(v) == "table" then
                WatchingMachineDB[k] = {}
                for k2, v2 in pairs(v) do
                    WatchingMachineDB[k][k2] = v2
                end
            else
                WatchingMachineDB[k] = v
            end
        elseif type(v) == "table" and type(WatchingMachineDB[k]) == "table" then
            -- Merge missing keys into existing tables (e.g. new modules into moduleStates)
            for k2, v2 in pairs(v) do
                if WatchingMachineDB[k][k2] == nil then
                    WatchingMachineDB[k][k2] = v2
                end
            end
        end
    end
    -- Initialize error log in DB and merge any early errors
    if not WatchingMachineDB.errorLog then
        WatchingMachineDB.errorLog = {}
    end
    -- Merge any errors captured before DB was ready
    for _, entry in ipairs(WM._errorLog) do
        table.insert(WatchingMachineDB.errorLog, entry)
    end
    WM._errorLog = WatchingMachineDB.errorLog
end

-- ============================================
-- MINIMAP BUTTON
-- ============================================

local minimapButton = nil
local minimapButtonDB = {} -- Local reference to settings

-- Position update function (defined early so it's available everywhere)
local function UpdateMinimapPosition()
    if not minimapButton then return end
    
    -- Check for free position mode (x/y saved)
    if WatchingMachineDB and WatchingMachineDB.minimapX and WatchingMachineDB.minimapY then
        -- Free position mode - place anywhere on screen
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", UIParent, "BOTTOMLEFT", WatchingMachineDB.minimapX, WatchingMachineDB.minimapY)
    else
        -- First run or reset - default to top-right area of screen
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -120)
    end
end

-- Visibility update function
local function UpdateMinimapVisibility()
    if not minimapButton then return end
    if WatchingMachineDB and WatchingMachineDB.minimapHidden then
        minimapButton:Hide()
    else
        minimapButton:Show()
    end
end

local function CreateMinimapButton()
    -- If button already exists, just update and return
    if minimapButton then
        UpdateMinimapPosition()
        UpdateMinimapVisibility()
        return minimapButton
    end
    
    -- Create button frame - parent to UIParent for free movement
    local button = CreateFrame("Button", "WatchingMachineMinimapButton", UIParent)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Border overlay
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    
    -- Background
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    
    -- Icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon
    
    -- Dragging state
    local isDragging = false
    
    -- Drag handlers - free movement anywhere on screen
    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:LockHighlight()
        self.icon:SetTexCoord(0, 1, 0, 1)
        self:StartMoving()
        GameTooltip:Hide()
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        self:UnlockHighlight()
        isDragging = false
        
        -- Save position
        if WatchingMachineDB then
            local x, y = self:GetCenter()
            WatchingMachineDB.minimapX = x
            WatchingMachineDB.minimapY = y
        end
    end)
    
    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if isDragging then return end
        if btn == "LeftButton" or btn == "RightButton" then
            if not isAuthorized then
                WM:Print("Not authorized. You must be a member of <" .. REQUIRED_GUILD .. ">.")
                return
            end
            WM:ToggleDashboard()
        end
    end)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if isDragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Watching Machine", 1, 1, 1)
        
        if not isAuthorized then
            GameTooltip:AddLine("|cFFFF0000Not Authorized|r", 1, 0, 0)
            GameTooltip:AddLine("Requires <" .. REQUIRED_GUILD .. "> membership", 0.7, 0.7, 0.7)
        else
            if isOfficer then
                GameTooltip:AddLine("|cFFFFD700Officer Access|r", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("|cFF00FF00Authorized|r", 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine("Left-click: Toggle Dashboard", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Drag: Move button anywhere", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            
            for name, module in pairs(WM.modules) do
                if name == "Recruiter" and not isOfficer then
                    -- Skip
                elseif module.GetQuickStatus then
                    local status = module:GetQuickStatus()
                    GameTooltip:AddLine(name .. ": " .. status, 0.8, 0.8, 0.8)
                end
            end
        end
        
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Store reference
    minimapButton = button
    WM.minimapButton = button
    
    -- Initial position and visibility
    UpdateMinimapPosition()
    UpdateMinimapVisibility()
    
    return button
end

-- Force restore visibility (called on zone changes)
function WM:RestoreMinimapButton()
    if minimapButton then
        UpdateMinimapPosition()
        UpdateMinimapVisibility()
    end
end

function WM:ToggleMinimapButton()
    if WatchingMachineDB.minimapHidden then
        WatchingMachineDB.minimapHidden = false
        if minimapButton then minimapButton:Show() end
        self:Print("Minimap button shown")
    else
        WatchingMachineDB.minimapHidden = true
        if minimapButton then minimapButton:Hide() end
        self:Print("Minimap button hidden. Use /wmachine to toggle dashboard.")
    end
    
    -- Update dashboard button text if visible
    self:UpdateMinimapButtonText()
end

-- ============================================
-- DASHBOARD UI
-- ============================================

local dashboard = nil

function WM:CreateDashboard()
    if dashboard then return end
    
    local frame = CreateFrame("Frame", "WatchingMachineDashboard", UIParent, "BackdropTemplate")
    frame:SetSize(420, 640)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        WatchingMachineDB.dashboardPos = {point, relPoint, x, y}
    end)
    frame:Hide()
    
    -- Apply theme
    self:SkinPanel(frame)
    self:RegisterSkinnedPanel(frame)
    
    -- Restore position
    if WatchingMachineDB.dashboardPos then
        frame:ClearAllPoints()
        frame:SetPoint(
            WatchingMachineDB.dashboardPos[1],
            UIParent,
            WatchingMachineDB.dashboardPos[2],
            WatchingMachineDB.dashboardPos[3],
            WatchingMachineDB.dashboardPos[4]
        )
    end
    
    local theme = self:GetTheme()
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Watching Machine")
    title:SetTextColor(unpack(theme.addonTitleColor))
    frame.titleText = title
    
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subtitle:SetText("v" .. WM.version .. " - Comprehensive Monitoring Suite")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    -- Module cards container
    local cardsContainer = CreateFrame("Frame", nil, frame)
    cardsContainer:SetPoint("TOPLEFT", 15, -55)
    cardsContainer:SetPoint("BOTTOMRIGHT", -15, 60)
    
    frame.cardsContainer = cardsContainer
    frame.moduleCards = {}
    
    -- Bottom buttons
    local minimapBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minimapBtn:SetSize(120, 24)
    minimapBtn:SetPoint("BOTTOMLEFT", 20, 20)
    minimapBtn:SetScript("OnClick", function() 
        WM:ToggleMinimapButton() 
        WM:UpdateMinimapButtonText()
    end)
    frame.minimapBtn = minimapBtn
    
    -- Minimap status indicator
    local minimapStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapStatus:SetPoint("LEFT", minimapBtn, "RIGHT", 10, 0)
    frame.minimapStatus = minimapStatus
    
    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsBtn:SetSize(80, 24)
    settingsBtn:SetPoint("BOTTOMRIGHT", -110, 20)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function() WM:ToggleSettings() end)
    
    local helpBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    helpBtn:SetSize(80, 24)
    helpBtn:SetPoint("BOTTOMRIGHT", -20, 20)
    helpBtn:SetText("Help")
    helpBtn:SetScript("OnClick", function() WM:ShowHelp() end)
    
    dashboard = frame
    WM.dashboard = frame
    
    -- Update minimap button text
    WM:UpdateMinimapButtonText()
    
    -- Create module cards after a short delay to ensure modules are registered
    RunAfter(0.1, function()
        WM:CreateModuleCards()
    end)
end

function WM:UpdateMinimapButtonText()
    if not dashboard or not dashboard.minimapBtn or not dashboard.minimapStatus then return end
    
    if WatchingMachineDB and WatchingMachineDB.minimapHidden then
        dashboard.minimapBtn:SetText("Show Minimap")
        dashboard.minimapStatus:SetText("|cFFFF0000[Hidden]|r")
    else
        dashboard.minimapBtn:SetText("Hide Minimap")
        dashboard.minimapStatus:SetText("|cFF00FF00[Visible]|r")
    end
end

function WM:CreateModuleCards()
    if not dashboard or not dashboard.cardsContainer then return end
    
    local container = dashboard.cardsContainer
    local yOffset = 0
    local cardHeight = 55
    local cardSpacing = 6
    
    local moduleOrder = {"AutoLogger", "KeywordMonitor", "MailLogger", "ServicesParser", "WhisperLogs", "GuildInvite", "DebuffTracker", "PvPTracker", "Recruiter"}
    local moduleInfo = {
        AutoLogger = {
            title = "Auto Logger",
            desc = "Automatic chat and combat logging",
            color = {0, 1, 0},
            icon = "Interface\\Icons\\INV_Misc_Book_09",
        },
        KeywordMonitor = {
            title = "Keyword Monitor",
            desc = "Monitor channels for keywords",
            color = {1, 0.67, 0},
            icon = "Interface\\Icons\\INV_Misc_SpyGlass_03",
        },
        MailLogger = {
            title = "Mail & Trade Logger",
            desc = "Log mail and trade transactions",
            color = {1, 0.41, 0.71},
            icon = "Interface\\Icons\\INV_Letter_15",
        },
        ServicesParser = {
            title = "Services Parser",
            desc = "Parse boost advertisements",
            color = {0, 0.8, 1},
            icon = "Interface\\Icons\\Spell_Nature_Polymorph",
        },
        WhisperLogs = {
            title = "WarcraftLogs Lookup",
            desc = "WCL links for whispers & group",
            color = {0.8, 0.5, 1},
            icon = "Interface\\Icons\\INV_Misc_Note_01",
        },
        GuildInvite = {
            title = "Guild Invite",
            desc = "Auto-invite on 'inv' trigger",
            color = {0, 1, 0},
            icon = "Interface\\Icons\\Spell_Holy_Resurrection",
        },
        DebuffTracker = {
            title = "Debuff Tracker",
            desc = "Raid debuff monitoring",
            color = {1, 0.8, 0},
            icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        },
        PvPTracker = {
            title = "PvP Enemy Tracker",
            desc = "Track and alert on hostile players",
            color = {0.9, 0.2, 0.2},
            icon = "Interface\\Icons\\Ability_Dualwield",
        },
        Recruiter = {
            title = "Recruiting Tool",
            desc = "Automated guild recruiting",
            color = {1, 0.84, 0},
            icon = "Interface\\Icons\\INV_Misc_GroupLooking",
        },
    }
    
    for _, moduleName in ipairs(moduleOrder) do
        -- Skip Recruiter for non-officers
        if moduleName == "Recruiter" and not isOfficer then
            -- Don't create card for Recruiter
        else
            local info = moduleInfo[moduleName]
            local module = self.modules[moduleName]
        
        local card = CreateFrame("Frame", nil, container, "BackdropTemplate")
        card:SetSize(container:GetWidth(), cardHeight)
        card:SetPoint("TOPLEFT", 0, -yOffset)
        card:SetPoint("TOPRIGHT", 0, -yOffset)
        WM:SkinCard(card, info.color)
        WM:RegisterSkinnedCard(card, info.color)
        
        -- Icon
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexture(info.icon)
        
        -- Title
        local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOPLEFT", 50, -6)
        titleText:SetText("|cFF" .. string.format("%02X%02X%02X", info.color[1]*255, info.color[2]*255, info.color[3]*255) .. info.title .. "|r")
        
        -- Description
        local descText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        descText:SetPoint("TOPLEFT", 50, -20)
        descText:SetText(info.desc)
        
        -- Status text
        local statusText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusText:SetPoint("TOPLEFT", 50, -34)
        statusText:SetText("|cFF888888Loading...|r")
        card.statusText = statusText
        
        -- Open button
        local openBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        openBtn:SetSize(55, 20)
        openBtn:SetPoint("RIGHT", -8, 0)
        openBtn:SetText("Open")
        openBtn:SetScript("OnClick", function()
            if module and module.ToggleUI then
                module:ToggleUI()
            elseif module and module.Toggle then
                module:Toggle()
            else
                WM:Print(moduleName .. " UI not available")
            end
        end)
        
        card.moduleName = moduleName
        dashboard.moduleCards[moduleName] = card
        
        yOffset = yOffset + cardHeight + cardSpacing
        end -- end of officer check if
    end
end

function WM:UpdateDashboard()
    if not dashboard or not dashboard:IsShown() then return end
    
    for moduleName, card in pairs(dashboard.moduleCards) do
        -- Skip if card shouldn't exist (Recruiter for non-officers)
        if moduleName == "Recruiter" and not isOfficer then
            -- Skip
        else
            local module = self.modules[moduleName]
            if module and module.GetQuickStatus then
                card.statusText:SetText(module:GetQuickStatus())
            else
                card.statusText:SetText("|cFF888888Module not loaded|r")
            end
        end
    end
end

function WM:ToggleDashboard()
    if not isAuthorized then
        return
    end
    
    if not dashboard then
        self:CreateDashboard()
    end
    
    if not dashboard then
        return
    end
    
    if dashboard:IsShown() then
        dashboard:Hide()
    else
        dashboard:Show()
        self:UpdateDashboard()
        self:UpdateMinimapButtonText()
    end
end

-- ============================================
-- SETTINGS PANEL
-- ============================================

local settingsFrame = nil

function WM:CreateSettingsPanel()
    if settingsFrame then return settingsFrame end
    
    local theme = self:GetTheme()
    
    local frame = CreateFrame("Frame", "WM_SettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(320, 230)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    
    self:SkinPanel(frame)
    self:RegisterSkinnedPanel(frame)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Watching Machine Settings")
    title:SetTextColor(unpack(theme.headerColor))
    frame.titleText = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local yOffset = -50
    
    -- Theme label
    local themeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", 25, yOffset)
    themeLabel:SetText("UI Theme:")
    themeLabel:SetTextColor(unpack(theme.headerColor))
    
    -- Theme dropdown
    local dropdown = CreateFrame("Frame", "WM_SettingsThemeDropdown", frame, "BackdropTemplate")
    dropdown:SetSize(160, 24)
    dropdown:SetPoint("LEFT", themeLabel, "RIGHT", 12, 0)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    dropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    dropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local ddText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ddText:SetPoint("LEFT", 8, 0)
    ddText:SetText(self:GetThemeName())
    
    local ddArrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ddArrow:SetPoint("RIGHT", -8, 0)
    ddArrow:SetText("v")
    
    -- Dropdown menu
    local ddMenu = CreateFrame("Frame", "WM_SettingsThemeMenu", dropdown, "BackdropTemplate")
    ddMenu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    ddMenu:SetSize(160, (#self.THEME_LIST * 22) + 6)
    ddMenu:SetFrameStrata("TOOLTIP")
    ddMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    ddMenu:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    ddMenu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    ddMenu:Hide()
    
    for idx, themeName in ipairs(self.THEME_LIST) do
        local item = CreateFrame("Button", nil, ddMenu)
        item:SetSize(156, 20)
        item:SetPoint("TOPLEFT", 2, -((idx - 1) * 22) - 3)
        
        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", 8, 0)
        itemText:SetText(themeName)
        
        local highlight = item:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.3, 0.5, 0.3)
        
        item:SetScript("OnClick", function()
            WatchingMachineDB.theme = themeName
            ddText:SetText(themeName)
            ddMenu:Hide()
            WM:OnThemeChanged()
        end)
    end
    
    dropdown:EnableMouse(true)
    dropdown:SetScript("OnMouseDown", function()
        if ddMenu:IsShown() then ddMenu:Hide() else ddMenu:Show() end
    end)
    frame:HookScript("OnHide", function() ddMenu:Hide() end)
    
    yOffset = yOffset - 35
    
    -- Description
    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", 25, yOffset)
    desc:SetWidth(270)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cFF888888Theme applies to the dashboard, all module panels, and the debuff tracker. ElvUI theme uses pixel-perfect borders matching Tukui/ElvUI style.|r")
    
    yOffset = yOffset - 55
    
    -- Verbose chat toggle
    local verboseCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    verboseCB:SetPoint("TOPLEFT", 20, yOffset)
    verboseCB.Text:SetText("Verbose chat (show sync/diagnostic messages)")
    verboseCB:SetChecked(WatchingMachineDB and WatchingMachineDB.verboseChat)
    verboseCB:SetScript("OnClick", function(self)
        if WatchingMachineDB then
            WatchingMachineDB.verboseChat = self:GetChecked()
        end
    end)
    verboseCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Verbose Chat Mode", 1, 0.8, 0)
        GameTooltip:AddLine("Shows low-priority messages like guild sync", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("status, leaderboard updates, roster refreshes,", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("and other backend activity. Useful for", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("diagnostics. Off by default to reduce chat noise.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    verboseCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 28
    
    -- Current theme indicator
    local currentLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    currentLabel:SetPoint("TOPLEFT", 25, yOffset)
    currentLabel:SetText("Active: |cFF00FF00" .. self:GetThemeName() .. "|r")
    frame.currentLabel = currentLabel
    
    settingsFrame = frame
    return frame
end

function WM:OnThemeChanged()
    local themeName = self:GetThemeName()
    self:Print("Theme changed to: |cFFFFCC00" .. themeName .. "|r")
    
    -- Re-skin all registered frames
    self:ReskinAll()
    
    -- Destroy and recreate dashboard to fully re-theme
    if dashboard then
        local wasShown = dashboard:IsShown()
        dashboard:Hide()
        -- Unregister from skinning
        self._skinnedPanels[dashboard] = nil
        for card in pairs(self._skinnedCards) do
            if card:GetParent() and card:GetParent():GetParent() == dashboard then
                self._skinnedCards[card] = nil
            end
        end
        dashboard = nil
        self.dashboard = nil
        if wasShown then
            self:CreateDashboard()
            dashboard:Show()
            self:UpdateDashboard()
        end
    end
    
    -- Destroy and recreate settings panel with new theme
    if settingsFrame then
        settingsFrame:Hide()
        self._skinnedPanels[settingsFrame] = nil
        settingsFrame = nil
        self:CreateSettingsPanel()
        settingsFrame:Show()
    end
    
    -- Notify modules that have an ApplyTheme method
    for name, module in pairs(self.modules) do
        if module.ApplyTheme then
            module:ApplyTheme()
        end
    end
end

function WM:ToggleSettings()
    local frame = self:CreateSettingsPanel()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function WM:ShowHelp()
    self:Print("=== Watching Machine Commands ===")
    print("|cFFFFFF00/wmachine|r - Toggle dashboard")
    print("|cFFFFFF00/wmachine logger|r - Open Auto Logger")
    print("|cFFFFFF00/wmachine keyword|r - Open Keyword Monitor")
    print("|cFFFFFF00/wmachine mail|r - Open Mail & Trade Logger")
    print("|cFFFFFF00/wmachine services|r - Open Services Parser")
    print("|cFFFFFF00/wmachine wcl|r - Open Whisper Logs (WCL Lookup)")
    print("|cFFFFFF00/wmachine ginvite|r - Open Guild Invite")
    print("|cFFFFFF00/wmachine debuff|r - Open Debuff Tracker settings")
    print("|cFFFFFF00/wmachine pvp|r - Open PvP Enemy Tracker")
    if isOfficer then
        print("|cFFFFFF00/wmachine recruit|r - Open Recruiting Tool |cFFFFD700(Officers)|r")
    end
    print("|cFFFFFF00/wmachine settings|r - Open addon settings (theme)")
    print("|cFFFFFF00/wmachine minimap|r - Toggle minimap button")
    print("|cFFFFFF00/wmachine resetminimap|r - Reset button position")
    print("|cFFFFFF00/wmachine debug|r - Show security debug info")
    print("|cFFFFFF00/wmachine recheck|r - Force security recheck")
    print("|cFFFFFF00/wmachine errors|r - Show captured error log")
    print("|cFFFFFF00/wmachine clearerrors|r - Clear error log")
    print("|cFFFFFF00/wmachine help|r - Show this help")
end

-- ============================================
-- SLASH COMMANDS
-- ============================================

SLASH_WATCHINGMACHINE1 = "/wmachine"
SLASH_WATCHINGMACHINE2 = "/watchingmachine"

SlashCmdList["WATCHINGMACHINE"] = function(msg)
    msg = msg or ""
    local cmd = strtrim(msg:lower())
    
    -- Debug command always available
    if cmd == "debug" then
        WM:Print("=== Debug Info ===")
        WM:Print("securityCheckComplete: " .. tostring(securityCheckComplete))
        WM:Print("isAuthorized: " .. tostring(isAuthorized))
        WM:Print("isOfficer: " .. tostring(isOfficer))
        WM:Print("IsInGuild: " .. tostring(IsInGuild()))
        local guildName, rankName, rankIndex = GetGuildInfo("player")
        WM:Print("GuildInfo: name='" .. tostring(guildName) .. "' rank='" .. tostring(rankName) .. "' index=" .. tostring(rankIndex))
        WM:Print("REQUIRED_GUILD: '" .. REQUIRED_GUILD .. "'")
        return
    end
    
    -- Force recheck command
    if cmd == "recheck" then
        WM:Print("Forcing security recheck...")
        securityCheckComplete = false
        isAuthorized = false
        isOfficer = false
        WM:CheckGuildSecurity()
        if isAuthorized then
            WM:OnSecurityCheckPassed()
        end
        return
    end
    
    -- Error log commands (always available, even if not authorized)
    if cmd == "errors" or cmd == "errorlog" or cmd == "err" then
        local log = WatchingMachineDB and WatchingMachineDB.errorLog or WM._errorLog
        if not log or #log == 0 then
            WM:Print("No errors captured. If you're seeing errors, do /reload then run this again.")
        else
            WM:Print("=== Error Log (" .. #log .. " entries) ===")
            local start = math.max(1, #log - 19)
            for i = start, #log do
                print("|cFFFF6666[" .. i .. "]|r " .. log[i]:gsub("\n", " | "))
            end
            if #log > 20 then
                WM:Print("Showing last 20 of " .. #log .. ". Full log in SavedVariables.")
            end
            WM:Print("Full log: WTF/Account/YOUR_ACCOUNT/SavedVariables/WatchingMachine.lua -> errorLog table")
        end
        return
    end
    
    if cmd == "clearerrors" or cmd == "clearerr" then
        if WatchingMachineDB then
            WatchingMachineDB.errorLog = {}
            WM._errorLog = WatchingMachineDB.errorLog
        end
        WM:Print("Error log cleared.")
        return
    end
    
    -- Security check for all other commands
    if not isAuthorized then
        WM:Print("|cFFFF0000Not authorized. Use /wmachine debug to check status.|r")
        return
    end
    
    if cmd == "" then
        WM:ToggleDashboard()
        
    elseif cmd == "logger" or cmd == "autolog" or cmd == "log" then
        local module = WM.modules.AutoLogger
        if module and module.OpenSettings then
            module:OpenSettings()
        else
            WM:Print("AutoLogger module not available")
        end
        
    elseif cmd == "keyword" or cmd == "km" or cmd == "keywords" then
        local module = WM.modules.KeywordMonitor
        if module and module.ToggleUI then
            module:ToggleUI()
        else
            WM:Print("KeywordMonitor module not available")
        end
        
    elseif cmd == "mail" or cmd == "ml" or cmd == "trade" then
        local module = WM.modules.MailLogger
        if module and module.ToggleUI then
            module:ToggleUI()
        else
            WM:Print("MailLogger module not available")
        end
        
    elseif cmd == "services" or cmd == "sp" or cmd == "boost" or cmd == "boosts" then
        local module = WM.modules.ServicesParser
        if module and module.ToggleUI then
            module:ToggleUI()
        else
            WM:Print("ServicesParser module not available")
        end
        
    elseif cmd == "recruit" or cmd == "recruiter" or cmd == "guild" then
        -- Officer-only command
        if not isOfficer then
            WM:Print("Recruiting Tool is restricted to officers.")
            return
        end
        local module = WM.modules.Recruiter
        if module and module.ToggleUI then
            module:ToggleUI()
        else
            WM:Print("Recruiter module not available")
        end
        
    elseif cmd == "whisper" or cmd == "whispers" or cmd == "wcl" or cmd == "logs" then
        local module = WM.modules.WhisperLogs
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("WhisperLogs module not available")
        end
        
    elseif cmd == "ginvite" or cmd == "guildinvite" or cmd == "autoinv" then
        local module = WM.modules.GuildInvite
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("GuildInvite module not available")
        end
        
    elseif cmd == "debuff" or cmd == "debuffs" or cmd == "debufftracker" then
        local module = WM.modules.DebuffTracker
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("DebuffTracker module not available")
        end
        
    elseif cmd == "pvp" or cmd == "enemies" or cmd == "pvptracker" or cmd == "kos" then
        local module = WM.modules.PvPTracker
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("PvPTracker module not available")
        end
        
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        WM:ToggleSettings()
        
    elseif cmd == "minimap" then
        WM:ToggleMinimapButton()
        
    elseif cmd == "resetminimap" or cmd == "resetbutton" then
        -- Clear saved position to reset to default
        if WatchingMachineDB then
            WatchingMachineDB.minimapX = nil
            WatchingMachineDB.minimapY = nil
            WatchingMachineDB.minimapPos = nil
        end
        if minimapButton then
            minimapButton:ClearAllPoints()
            minimapButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -120)
        end
        WM:Print("Minimap button position reset. Drag to reposition.")
        
    elseif cmd == "help" then
        WM:ShowHelp()
    elseif cmd == "status" then
        WM:Print("=== Module Status ===")
        for name, module in pairs(WM.modules) do
            -- Skip Recruiter for non-officers
            if name == "Recruiter" and not isOfficer then
                -- Don't show
            elseif module.GetQuickStatus then
                print("  " .. name .. ": " .. module:GetQuickStatus())
            else
                print("  " .. name .. ": |cFF888888Loaded|r")
            end
        end
        
    else
        WM:Print("Unknown command. Type /wm help for available commands.")
    end
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

local function PerformSecurityCheck()
    local result = WM:CheckGuildSecurity()
    
    if result == nil then
        -- Guild info not loaded yet, will retry
        return false
    end
    
    if result then
        WM:OnSecurityCheckPassed()
    else
        WM:OnSecurityCheckFailed()
    end
    return true
end

local retryCount = 0
local maxRetries = 5

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AddonName then
        InitCoreDB()
        
    elseif event == "PLAYER_LOGIN" then
        -- Reset security state for new character
        isAuthorized = false
        isOfficer = false
        securityCheckComplete = false
        retryCount = 0
        
        -- Hide dashboard if it exists from previous session
        if dashboard then
            dashboard:Hide()
        end
        
        -- Create or reuse minimap button
        CreateMinimapButton()
        
        -- Hook Minimap OnShow to restore our button when minimap becomes visible
        -- This catches cases where the minimap is hidden/shown during zone transitions
        if Minimap and not Minimap.wmHooked then
            Minimap:HookScript("OnShow", function()
                RunAfter(0.1, function()
                    WM:RestoreMinimapButton()
                end)
            end)
            Minimap.wmHooked = true
        end
        
        -- Request guild roster to ensure we have current data
        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
        end
        
        -- Try initial security check with increasing delays
        local function TrySecurityCheck()
            if securityCheckComplete then return end
            
            retryCount = retryCount + 1
            
            if not PerformSecurityCheck() and retryCount < maxRetries then
                RunAfter(2, TrySecurityCheck)
            end
        end
        
        RunAfter(1, TrySecurityCheck)
        
    elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        -- Re-check security when guild info updates
        if not securityCheckComplete then
            PerformSecurityCheck()
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Restore minimap button after zone change with a small delay
        -- Some addons/UI elements may manipulate minimap during zone transitions
        RunAfter(0.5, function()
            WM:RestoreMinimapButton()
        end)
        -- Also restore immediately in case the delay isn't needed
        WM:RestoreMinimapButton()
        
    elseif event == "PLAYER_LEAVING_WORLD" then
        -- Reset security state when leaving (character switch/logout)
        isAuthorized = false
        isOfficer = false
        securityCheckComplete = false
        retryCount = 0
        
        -- Hide dashboard (minimap button persists based on user preference)
        if dashboard then
            dashboard:Hide()
        end
    end
end)
