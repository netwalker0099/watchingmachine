-- Watching Machine
-- Comprehensive monitoring suite for WoW Classic TBC Anniversary
-- Author: Robert

local AddonName, WM = ...
_G.WatchingMachine = WM

WM.version = "3.9"
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
    "Recruiter", "WhisperLogs", "GuildInvite", "BuffCheck", "ArmorySnap", "AuraRange",
    "ClassTools", "ClassGeneral", "ClassWarlock", "ClassMage",
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

-- Security Configuration (guild restriction removed — open to all)
local REQUIRED_GUILD = nil
local OFFICER_RANK_THRESHOLD = 1  -- Rank index 0 = GM, 1 = Officer only

-- Security State (always authorized)
local isAuthorized = true
local isOfficer = true
local securityCheckComplete = true

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
-- SHARED CONSUMABLE AURA NAMES
-- ============================================
-- Single source for the food/flask aura names, so Buff Check (ready-check
-- raid audit) and Class Tools General (continuous self check) always agree.

-- Exact aura names that count as a food buff. Most TBC food applies
-- "Well Fed"; Skullfish Soup is a drink and applies "Enlightened" instead
-- (20 crit rating and 20 Spirit), which does not stack with Well Fed.
WM.FOOD_BUFFS = { "Well Fed", "Enlightened" }

-- Substrings that identify a flask aura. Substring rather than prefix so
-- the Zul'Aman "Unstable Flask of the Beast" / "...of the Sorcerer" match.
WM.FLASK_CONTAINS = { "Flask of" }

local FOOD_BUFF_SET = {}
for _, n in ipairs(WM.FOOD_BUFFS) do FOOD_BUFF_SET[n] = true end

function WM:IsFoodBuff(name)
    return name ~= nil and FOOD_BUFF_SET[name] == true
end

function WM:IsFlaskBuff(name)
    if not name then return false end
    for _, needle in ipairs(WM.FLASK_CONTAINS) do
        if name:find(needle, 1, true) then return true end
    end
    return false
end

-- ============================================
-- CORE UTILITIES
-- ============================================

function WM:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[WatchingMachine]|r " .. msg)
end

-- Shared module color map (hoisted — was rebuilt on every print call)
local MODULE_COLORS = {
    AutoLogger = "00FF00",
    KeywordMonitor = "FFAA00",
    MailLogger = "FF69B4",
    ServicesParser = "00CCFF",
    WhisperLogs = "CC80FF",
    Recruiter = "FFD700",
    GuildInvite = "00FF00",
    DebuffTracker = "FFCC00",
    PvPTracker = "FF3333",
    BuffCheck = "33FF99",
    ArmorySnap = "66AAFF",
    AuraRange = "FFFF66",
    ClassTools = "FF99DD",
    ClassGeneral = "AADDAA",
    ClassWarlock = "8787ED",
    ClassMage = "3FC7EB",
}

function WM:ModulePrint(moduleName, msg)
    local color = MODULE_COLORS[moduleName] or "FFFFFF"
    DEFAULT_CHAT_FRAME:AddMessage("|cFF" .. color .. "[WM:" .. moduleName .. "]|r " .. msg)
end

-- Verbose/diagnostic print — only shows when verbose mode is enabled
function WM:VerbosePrint(moduleName, msg)
    if not WatchingMachineDB or not WatchingMachineDB.verboseChat then return end
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

-- Named panels also close on Escape. UISpecialFrames holds global names,
-- so a panel rebuilt under the same name needs only one entry.
local escRegistered = {}

function WM:RegisterEscClose(frame)
    local name = frame and frame.GetName and frame:GetName()
    if not name or escRegistered[name] then return end
    escRegistered[name] = true
    tinsert(UISpecialFrames, name)
end

function WM:RegisterSkinnedPanel(frame)
    self._skinnedPanels[frame] = true
    self:RegisterEscClose(frame)
end

-- For panels being destroyed and rebuilt, so the stale frame isn't reskinned
function WM:UnregisterSkinnedPanel(frame)
    if frame then self._skinnedPanels[frame] = nil end
end

-- Text and textures coloured from a theme key (headerColor, separatorColor,
-- ...). Registered so a theme change recolours them instead of leaving the
-- colour they were built with. Weak keys: a discarded panel isn't pinned.
WM._themedTexts = setmetatable({}, { __mode = "k" })
WM._themedTextures = setmetatable({}, { __mode = "k" })

function WM:ThemeText(fontString, colorKey)
    self._themedTexts[fontString] = colorKey
    fontString:SetTextColor(unpack(self:GetTheme()[colorKey]))
end

function WM:ThemeTexture(texture, colorKey)
    self._themedTextures[texture] = colorKey
    texture:SetColorTexture(unpack(self:GetTheme()[colorKey]))
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
    local theme = self:GetTheme()
    for fs, key in pairs(self._themedTexts) do
        fs:SetTextColor(unpack(theme[key]))
    end
    for tex, key in pairs(self._themedTextures) do
        tex:SetColorTexture(unpack(theme[key]))
    end
end

-- ============================================
-- SECURITY CHECKS
-- ============================================

function WM:CheckGuildSecurity()
    -- Guild restriction removed — always authorized
    isAuthorized = true
    isOfficer = true
    securityCheckComplete = true
    return true
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
    -- Hide dashboard if open (but keep minimap button visible for user preference).
    -- WM.dashboard, not the file-local: that local is declared further down.
    if self.dashboard then
        self.dashboard:Hide()
    end
    
    -- Silently fail - don't announce to non-guild members
end

function WM:OnSecurityCheckPassed()
    -- Minimap button visibility is managed by CreateMinimapButton based on minimapHidden setting
    
    -- Auto-detect ElvUI/Tukui theme on first run
    self:DetectTheme()
    
    self:Print("Loaded v" .. self.version .. ". Type /wmachine to open dashboard.")
    
    -- Initialize modules
    for name, module in pairs(self.modules) do
        if module.Initialize then
            module:Initialize()
        end
    end
    
    -- Start dashboard update timer
    RunTicker(2, function()
        self:UpdateDashboard()
    end)
end

-- ============================================
-- SAVED VARIABLES INITIALIZATION
-- ============================================

local coreDefaults = {
    minimapPos = 220,
    minimapHidden = false,
    theme = "Default",
    verboseChat = false,    -- Show diagnostic/sync messages in chat
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
            -- Merge missing keys into existing tables
            for k2, v2 in pairs(v) do
                if WatchingMachineDB[k][k2] == nil then
                    WatchingMachineDB[k][k2] = v2
                end
            end
        end
    end
    -- moduleStates was saved but never read; each module keeps its own
    -- on/off flag, switched from its dashboard card
    WatchingMachineDB.moduleStates = nil

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
        if btn == "RightButton" then
            WM:ToggleSettings()
        elseif btn == "LeftButton" then
            WM:ToggleDashboard()
        end
    end)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if isDragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Watching Machine", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Dashboard", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Settings (theme, minimap)", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: Move button anywhere", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")

        -- Same order and names as the dashboard
        for _, group in ipairs(WM.MODULE_GROUPS or {}) do
            for _, name in ipairs(group.modules) do
                local module = WM.modules[name]
                if module and module.GetQuickStatus then
                    local info = WM.MODULE_INFO[name]
                    GameTooltip:AddDoubleLine(info and info.title or name, module:GetQuickStatus(),
                        0.8, 0.8, 0.8, 1, 1, 1)
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

    -- The card list scrolls inside the fill area; the panel is 700 tall
    -- but never taller than the screen.
    local frame = self.UI:CreatePanel({
        name = "WatchingMachineDashboard",
        title = "Watching Machine",
        width = 420,
        height = 700,
        minHeight = 400,
        scroll = false,
        strata = "MEDIUM",
        -- Saved as WatchingMachineDB.dashboardPos before the builder
        legacyPosition = WatchingMachineDB and WatchingMachineDB.dashboardPos,
    })
    if WatchingMachineDB then WatchingMachineDB.dashboardPos = nil end
    WM:ThemeText(frame.titleText, "addonTitleColor")
    local L = frame.layout

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", frame.titleText, "BOTTOM", 0, -2)
    subtitle:SetText("v" .. WM.version .. "  |cFF888888-  hover a card for details, ... for tools|r")
    L:Space(12)   -- room for the subtitle below the title band

    -- Module cards, in a scroll frame: the list grows with every module and
    -- the panel itself can't exceed the ~768px screen height.
    local fill = L:Fill(200)
    local cardsScroll = CreateFrame("ScrollFrame", "WM_DashboardCardScroll", fill, "UIPanelScrollFrameTemplate")
    cardsScroll:SetPoint("TOPLEFT", 3, 0)
    cardsScroll:SetPoint("BOTTOMRIGHT", -20, 0)

    local cardsContainer = CreateFrame("Frame", nil, cardsScroll)
    cardsContainer:SetSize(370, 1)
    cardsScroll:SetScrollChild(cardsContainer)

    frame.cardsScroll = cardsScroll
    frame.cardsContainer = cardsContainer
    frame.moduleCards = {}

    -- Footer: minimap toggle with its status beside it, Settings and Help
    frame.minimapBtn = frame:AddFooterButton({
        text = function()
            return WatchingMachineDB and WatchingMachineDB.minimapHidden and "Show Minimap" or "Hide Minimap"
        end,
        width = 120, height = 24,
        onClick = function() WM:ToggleMinimapButton() end,
        tooltip = { "Minimap Button", "Show or hide the Watching Machine button on the minimap."
            .. " With it hidden, /wmachine still opens the dashboard." },
    }, "LEFT")
    local minimapStatus = frame:AddFooterText({
        font = "GameFontNormalSmall",
        text = function()
            return WatchingMachineDB and WatchingMachineDB.minimapHidden
                and "|cFFFF0000[Hidden]|r" or "|cFF00FF00[Visible]|r"
        end,
    })
    -- Footer text anchors to the panel edge; sit it beside the button instead
    minimapStatus:ClearAllPoints()
    minimapStatus:SetPoint("LEFT", frame.minimapBtn, "RIGHT", 10, 0)
    frame.minimapStatus = minimapStatus

    frame:AddFooterButton({
        text = "Help", width = 80, height = 24,
        onClick = function() WM:ShowHelp() end,
        tooltip = { "Help", "Print every /wmachine command to chat." },
    }, "RIGHT")
    frame:AddFooterButton({
        text = "Settings", width = 80, height = 24,
        onClick = function() WM:ToggleSettings() end,
        tooltip = { "Settings", "UI theme and verbose chat." },
    }, "RIGHT")

    frame:Finish()
    dashboard = frame
    WM.dashboard = frame

    -- Create module cards after a short delay to ensure modules are registered
    RunAfter(0.1, function()
        WM:CreateModuleCards()
    end)
end

function WM:UpdateMinimapButtonText()
    if not dashboard or not dashboard.minimapBtn or not dashboard.minimapStatus then return end
    dashboard.minimapBtn:Refresh()
    dashboard.minimapStatus:Refresh()
end

-- ============================================
-- DASHBOARD MODULE CARDS
-- ============================================
-- One card per module, grouped. A card shows what the module is, whether
-- it's on, and its live status, and reaches everything it offers:
--   Open      the module's window
--   switch    on/off, for modules that define IsModuleEnabled/SetModuleEnabled
--   ...       tools menu (also right-click): the diagnostics that were
--             otherwise slash-command only
-- Hovering a card explains it.

local function Mod(name) return WM.modules[name] end

local function Call(name, method, ...)
    local m = Mod(name)
    if m and m[method] then return m[method](m, ...) end
    WM:Print(name .. " not available")
end

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Two-step confirm for menu tools that discard data
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["WM_CONFIRM_TOOL"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(self, data) if data then data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function WM:Confirm(text, fn)
    if StaticPopup_Show then
        StaticPopup_Show("WM_CONFIRM_TOOL", text, nil, fn)
    else
        fn()
    end
end

local MODULE_GROUPS = {
    { title = "Raid", modules = { "BuffCheck", "DebuffTracker", "ClassTools", "AuraRange", "ArmorySnap" } },
    { title = "Guild & Social", modules = { "GuildInvite", "Recruiter", "PvPTracker", "KeywordMonitor", "ServicesParser", "WhisperLogs" } },
    { title = "Logging", modules = { "AutoLogger", "MailLogger" } },
}

local MODULE_INFO = {
    AutoLogger = {
        title = "Auto Logger", desc = "Automatic chat and combat logging",
        about = "Turns on chat logging at login and combat logging in raid instances (optionally 5-mans too), and keeps Advanced Combat Logging on so Warcraft Logs uploads are complete.",
        command = "logger", color = {0, 1, 0}, icon = "Interface\\Icons\\INV_Misc_Book_09",
    },
    KeywordMonitor = {
        title = "Keyword Monitor", desc = "Monitor channels for keywords",
        about = "Watches Trade, General, LFG and the other public channels for words you choose and collects every match in one list.",
        toggleNote = "Off pauses monitoring for this session, like the Stop button.",
        command = "keyword", color = {1, 0.67, 0}, icon = "Interface\\Icons\\INV_Misc_SpyGlass_03",
    },
    MailLogger = {
        title = "Mail & Trade Logger", desc = "Log mail and trade transactions",
        about = "Long-term record of gold and items you receive by mail and trade, including auction house sales, buys and expired auctions, for each of your characters.",
        command = "mail", color = {1, 0.41, 0.71}, icon = "Interface\\Icons\\INV_Letter_15",
    },
    ServicesParser = {
        title = "Services Parser", desc = "Parse boost advertisements",
        about = "Reads boost adverts from the Services channel and sorts them by dungeon, with a separate tab for summons and portals.",
        command = "services", color = {0, 0.8, 1}, icon = "Interface\\Icons\\Spell_Nature_Polymorph",
    },
    WhisperLogs = {
        title = "WarcraftLogs Lookup", desc = "WCL links for whispers & group",
        about = "Lists the players who whisper you and your group members, each with a Warcraft Logs link on their own realm. Click a name to copy the link.",
        command = "wcl", color = {0.8, 0.5, 1}, icon = "Interface\\Icons\\INV_Misc_Note_01",
    },
    GuildInvite = {
        title = "Guild Invite", desc = "Auto-invite on 'inv' trigger",
        about = "Invites guild members to your group when they say the trigger word (default \"inv\") in guild chat or a whisper. Needs lead or assist.",
        command = "ginvite", color = {0, 1, 0}, icon = "Interface\\Icons\\Spell_Holy_Resurrection",
    },
    DebuffTracker = {
        title = "Debuff Tracker", desc = "Raid debuff monitoring",
        about = "Shows which raid debuffs are on the boss, calls out missing ones, and runs the encounter callouts (Illidan Doom and Shear, the Black Temple shadow resist check).",
        command = "debuff", color = {1, 0.8, 0}, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        tools = {
            { text = "Encounter callouts", desc = "Open settings at the Encounter Callouts section.",
              func = function() Call("DebuffTracker", "ToggleEncounterUI") end },
            { text = "Why is my target a boss?", desc = "Explain how the tracker classifies your target.",
              func = function() Call("DebuffTracker", "ExplainTarget") end },
            { text = "Exclude my target", desc = "Stop treating your target's creature as a boss.",
              func = function() Call("DebuffTracker", "ExcludeTarget") end },
            { text = "Un-exclude my target", func = function() Call("DebuffTracker", "UnexcludeTarget") end },
            { text = "List exclusions", func = function() Call("DebuffTracker", "ListExclusions") end },
            { text = "Clear all exclusions...", func = function()
                WM:Confirm("Remove every Debuff Tracker exclusion?", function() Call("DebuffTracker", "ClearExclusions") end)
              end },
            { text = "Shear tallies", desc = "Illidan Shear monitor status and counts.",
              func = function() Call("DebuffTracker", "ShowShearStatus") end },
            { text = "Check my shadow resist gear", func = function() Call("DebuffTracker", "ExplainShadowResist") end },
        },
    },
    PvPTracker = {
        title = "PvP Enemy Tracker", desc = "Track and alert on hostile players",
        about = "Keeps a kill-on-sight list of players who kill you (or that you add), alerts when they're near, and shares it with your guild.",
        command = "pvp", color = {0.9, 0.2, 0.2}, icon = "Interface\\Icons\\Ability_Dualwield",
        tools = {
            { text = "Show leaderboard", func = function() Call("PvPTracker", "ToggleLeaderboard") end },
            { text = "Request guild sync", desc = "Ask online guildies for their KOS data (5 minute cooldown).",
              func = function() Call("PvPTracker", "RequestSync") end },
        },
    },
    Recruiter = {
        title = "Recruiting Tool", desc = "Automated guild recruiting",
        about = "Scans for unguilded players by class and level range and sends them your recruiting message, keeping a history so nobody is messaged twice.",
        command = "recruit", color = {1, 0.84, 0}, icon = "Interface\\Icons\\INV_Misc_GroupLooking",
    },
    BuffCheck = {
        title = "Buff Check", desc = "Ready-check raid buff audit",
        about = "On every ready check, lists who is missing class buffs and the consumables you choose. Announced to raid if you started the check, shown only to you otherwise.",
        command = "buffcheck", color = {0.2, 1, 0.6}, icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        tools = {
            { text = "Run check now", desc = "Check the group now; only you see the report.",
              func = function() Call("BuffCheck", "RunLocalCheck") end },
            { text = "Explain buffs on target", desc = "Which checks your target's (or your own) auras satisfy.",
              func = function() Call("BuffCheck", "ExplainUnit", UnitExists("target") and "target" or "player") end },
        },
    },
    ArmorySnap = {
        title = "ArmorySnap", desc = "Raid gear & talent snapshots",
        about = "Quietly records every raid member's gear, enchants, gems and talents, and lets you browse the snapshots later.",
        toggleNote = "Automatic scanning in raids. Manual snapshots work either way.",
        command = "armory", color = {0.4, 0.67, 1}, icon = "Interface\\Icons\\INV_Chest_Chain_09",
        tools = {
            { text = "Take a snapshot now", func = function()
                local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("snap") end
              end },
            { text = "List snapshots", func = function()
                local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("list") end
              end },
            { text = "Scanner status", func = function()
                local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("status") end
              end },
            { text = "Reset current session...", func = function()
                WM:Confirm("Reset the current ArmorySnap scanning session?", function()
                    local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("reset") end
                end)
              end },
        },
    },
    AuraRange = {
        title = "Aura Range", desc = "Totem/aura out-of-range alerts",
        about = "Warns you the moment you walk out of range of a party aura or shaman totem you were getting, and clears when you step back in.",
        command = "range", color = {1, 1, 0.4}, icon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    },
    ClassTools = {
        title = "Class Tools", desc = "Tools for the class you're playing",
        about = "Per-class checks and helpers (missing armor spells, soulstones, portal button) plus raid consumable warnings for everyone, in one CHECK YOURSELF frame.",
        command = "class", color = {1, 0.6, 0.87}, icon = "Interface\\Icons\\Achievement_Character_Human_Male",
        tools = {
            { text = "What the consumable checks see", desc = "Flask, food buff and weapon enchant, as the General checks read them.",
              func = function() Call("ClassGeneral", "Explain") end },
            { text = "Soulstone timers", visible = function() return PlayerClass() == "WARLOCK" end,
              func = function() Call("ClassWarlock", "ReportSoulstones") end },
            { text = "List my portals and teleports", visible = function() return PlayerClass() == "MAGE" end,
              func = function() Call("ClassMage", "ReportSpells") end },
        },
    },
}
WM.MODULE_INFO = MODULE_INFO
WM.MODULE_GROUPS = MODULE_GROUPS

local function HasSwitch(module)
    return module and module.IsModuleEnabled and module.SetModuleEnabled and true or false
end

local function VisibleTools(info)
    local out = {}
    for _, t in ipairs(info.tools or {}) do
        if not t.visible or t.visible() then out[#out + 1] = t end
    end
    return out
end

local toolsMenu
local function ShowToolsMenu(info)
    local tools = VisibleTools(info)
    if #tools == 0 then return end
    if not toolsMenu then
        toolsMenu = CreateFrame("Frame", "WM_DashboardToolsMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(toolsMenu, function(self, level)
        local item = UIDropDownMenu_CreateInfo()
        item.text, item.isTitle, item.notCheckable = info.title, true, true
        UIDropDownMenu_AddButton(item, level)
        for _, t in ipairs(tools) do
            item = UIDropDownMenu_CreateInfo()
            item.text, item.notCheckable = t.text, true
            item.func = function() CloseDropDownMenus(); t.func() end
            if t.desc then
                item.tooltipTitle, item.tooltipText, item.tooltipOnButton = t.text, t.desc, true
            end
            UIDropDownMenu_AddButton(item, level)
        end
        item = UIDropDownMenu_CreateInfo()
        item.text, item.notCheckable = CANCEL or "Cancel", true
        item.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(item, level)
    end, "MENU")
    ToggleDropDownMenu(1, nil, toolsMenu, "cursor", 0, 0)
end
WM.ShowToolsMenu = ShowToolsMenu

local function ColorHex(c)
    return string.format("%02X%02X%02X", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function ShowCardTooltip(card)
    local info, module = card.info, WM.modules[card.moduleName]
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|cFF" .. ColorHex(info.color) .. info.title .. "|r")
    GameTooltip:AddLine(info.about or info.desc, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ")
    if module and module.GetQuickStatus then
        GameTooltip:AddLine("Status: " .. module:GetQuickStatus(), 0.8, 0.8, 0.8, true)
    end
    if HasSwitch(module) then
        GameTooltip:AddLine("Switch: " .. (module:IsModuleEnabled() and "|cFF00FF00on|r" or "|cFFFF4444off|r"),
            0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Open: settings and details", 0.6, 0.8, 1)
    if #VisibleTools(info) > 0 then
        GameTooltip:AddLine("... or right-click: tools", 0.6, 0.8, 1)
    end
    if info.command then
        GameTooltip:AddLine("/wmachine " .. info.command, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local CARD_H, CARD_GAP, GROUP_H = 46, 3, 20

function WM:CreateModuleCards()
    if not dashboard or not dashboard.cardsContainer then return end

    local container = dashboard.cardsContainer
    local width = container:GetWidth()
    local yOffset = 0

    for _, group in ipairs(MODULE_GROUPS) do
        local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 4, -(yOffset + 4))
        header:SetText(group.title)
        WM:ThemeText(header, "headerColor")
        yOffset = yOffset + GROUP_H

        for _, moduleName in ipairs(group.modules) do
            local info = MODULE_INFO[moduleName]
            local module = self.modules[moduleName]

            local card = CreateFrame("Frame", nil, container, "BackdropTemplate")
            card:SetSize(width, CARD_H)
            card:SetPoint("TOPLEFT", 0, -yOffset)
            card:SetPoint("TOPRIGHT", 0, -yOffset)
            WM:SkinCard(card, info.color)
            WM:RegisterSkinnedCard(card, info.color)
            card.info, card.moduleName = info, moduleName

            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(32, 32)
            icon:SetPoint("LEFT", 10, 0)
            icon:SetTexture(info.icon)
            card.icon = icon

            -- Right-hand controls, laid out from the right edge
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
            local leftmost = openBtn

            if info.tools then
                local toolsBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
                toolsBtn:SetSize(24, 20)
                toolsBtn:SetPoint("RIGHT", leftmost, "LEFT", -3, 0)
                toolsBtn:SetText("...")
                toolsBtn:SetScript("OnClick", function() ShowToolsMenu(info) end)
                toolsBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(info.title .. " tools", 1, 0.8, 0)
                    for _, t in ipairs(VisibleTools(info)) do
                        GameTooltip:AddLine(t.text, 0.8, 0.8, 0.8)
                    end
                    GameTooltip:Show()
                end)
                toolsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                card.toolsBtn = toolsBtn
                leftmost = toolsBtn
            end

            if HasSwitch(module) then
                local sw = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
                sw:SetSize(24, 24)
                sw:SetPoint("RIGHT", leftmost, "LEFT", -2, 0)
                sw:SetScript("OnClick", function(self)
                    module:SetModuleEnabled(self:GetChecked() and true or false)
                    WM:UpdateDashboard()
                end)
                sw:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(info.title .. ": " .. (module:IsModuleEnabled() and "on" or "off"), 1, 0.8, 0)
                    GameTooltip:AddLine("Click to turn it " .. (module:IsModuleEnabled() and "off." or "on."), 0.8, 0.8, 0.8)
                    if info.toggleNote then GameTooltip:AddLine(info.toggleNote, 0.8, 0.8, 0.8, true) end
                    GameTooltip:Show()
                end)
                sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
                card.switch = sw
                leftmost = sw
            end

            -- Text column stops short of the controls; long text truncates
            -- rather than running underneath them
            local textWidth = width - 50 - (8 + 55) - 6
                - (card.toolsBtn and 27 or 0) - (card.switch and 26 or 0)

            local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleText:SetPoint("TOPLEFT", 50, -6)
            titleText:SetWidth(textWidth)
            titleText:SetJustifyH("LEFT")
            titleText:SetWordWrap(false)
            titleText:SetText("|cFF" .. ColorHex(info.color) .. info.title .. "|r")

            local descText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            descText:SetPoint("TOPLEFT", 50, -20)
            descText:SetWidth(textWidth)
            descText:SetJustifyH("LEFT")
            descText:SetWordWrap(false)
            descText:SetText(info.desc)

            local statusText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            statusText:SetPoint("TOPLEFT", 50, -34)
            statusText:SetWidth(textWidth)
            statusText:SetJustifyH("LEFT")
            statusText:SetWordWrap(false)
            statusText:SetText("|cFF888888Loading...|r")
            card.statusText = statusText

            -- Hover explains the card; right-click opens its tools
            card:EnableMouse(true)
            card:SetScript("OnEnter", ShowCardTooltip)
            card:SetScript("OnLeave", function() GameTooltip:Hide() end)
            card:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" then ShowToolsMenu(info) end
            end)

            dashboard.moduleCards[moduleName] = card
            yOffset = yOffset + CARD_H + CARD_GAP
        end
        yOffset = yOffset + 4
    end

    -- Scroll child must be tall enough for everything, or the lower cards
    -- are unreachable
    container:SetHeight(math.max(yOffset, 1))
    self:UpdateDashboard()
end

function WM:UpdateDashboard()
    if not dashboard or not dashboard:IsShown() then return end

    for moduleName, card in pairs(dashboard.moduleCards) do
        local module = self.modules[moduleName]
        if module and module.GetQuickStatus then
            card.statusText:SetText(module:GetQuickStatus())
        else
            card.statusText:SetText("|cFF888888Module not loaded|r")
        end
        if card.switch then
            local on = module:IsModuleEnabled()
            card.switch:SetChecked(on)
            card.icon:SetDesaturated(not on)
        end
    end
end

-- A small page under the game's Options > AddOns, so the addon can be found
-- without knowing its slash command. Uses the Settings API where the client
-- has it, the older InterfaceOptions call otherwise.
function WM:RegisterOptionsCategory()
    if self.optionsCategory then return end
    local f = CreateFrame("Frame")
    f.name = "Watching Machine"

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Watching Machine  |cFF888888v" .. self.version .. "|r")

    local desc = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Every module is on the dashboard: switch modules on and off, open their"
        .. " settings, and hover a card to see what it does. Also: /wmachine, or the minimap button.")

    local function CloseOptions()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    end

    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    open:SetText("Open Dashboard")
    open:SetScript("OnClick", function()
        CloseOptions()
        if not (dashboard and dashboard:IsShown()) then WM:ToggleDashboard() end
    end)

    local settings = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    settings:SetSize(160, 24)
    settings:SetPoint("LEFT", open, "RIGHT", 8, 0)
    settings:SetText("Theme & Minimap")
    settings:SetScript("OnClick", function()
        CloseOptions()
        WM:ToggleSettings()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(f)
        self.optionsCategory = f
    end
end

function WM:ToggleDashboard()
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

    local panel = self.UI:CreatePanel({
        name = "WM_SettingsFrame",
        title = "Watching Machine Settings",
        width = 320,
        strata = "DIALOG",
    })
    local L = panel.layout

    local themes = {}
    for _, themeName in ipairs(self.THEME_LIST) do
        themes[#themes + 1] = { value = themeName, text = themeName }
    end
    L:Dropdown({
        name = "WM_SettingsThemeDropdown",
        label = "UI Theme:",
        width = 140,
        options = themes,
        get = function() return WM:GetThemeName() end,
        set = function(v)
            WatchingMachineDB.theme = v
            WM:OnThemeChanged()
        end,
        tooltip = { "UI Theme", "Default: Blizzard dialog borders. ElvUI: flat dark panels with pixel"
            .. " borders, to sit with ElvUI or Tukui. Applied straight away." },
    })
    L:Note("Applies to the dashboard, every module window, ArmorySnap and the debuff tracker."
        .. " On-screen warning frames keep their own colours.")
    L:Checkbox({
        label = "Verbose chat (show sync/diagnostic messages)",
        get = function() return WatchingMachineDB and WatchingMachineDB.verboseChat end,
        set = function(v)
            if WatchingMachineDB then WatchingMachineDB.verboseChat = v end
        end,
        tooltip = { "Verbose Chat Mode", "Shows low-priority messages like guild sync status, leaderboard"
            .. " updates, roster refreshes, and other backend activity. Useful for diagnostics."
            .. " Off by default to reduce chat noise." },
    })
    L:Row(20):Text({
        font = "GameFontNormalSmall",
        text = function() return "Active: |cFF00FF00" .. WM:GetThemeName() .. "|r" end,
    }, 12)

    settingsFrame = panel:Finish()
    return settingsFrame
end

function WM:OnThemeChanged()
    local themeName = self:GetThemeName()
    self:Print("Theme changed to: |cFFFFCC00" .. themeName .. "|r")

    -- Re-skin all registered frames: panel backdrops (dashboard and settings
    -- included), dashboard cards and theme-keyed text. Nothing needs
    -- rebuilding; the settings panel just re-reads its controls.
    self:ReskinAll()
    if settingsFrame and settingsFrame:IsShown() then settingsFrame:Refresh() end

    -- Modules with their own theme-dependent styling (Debuff Tracker's
    -- display, ArmorySnap's paper doll) restyle themselves
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
    print("|cFFFFFF00/wmachine recruit|r - Open Recruiting Tool")
    print("|cFFFFFF00/wmachine buffcheck|r - Open Buff Check settings")
    print("|cFFFFFF00/wmachine armory|r - Open ArmorySnap gear browser (also /as)")
    print("|cFFFFFF00/as snap [label]|r, |cFFFFFF00list|r, |cFFFFFF00delete <name>|r, |cFFFFFF00group|r, |cFFFFFF00auto|r, |cFFFFFF00status|r, |cFFFFFF00reset|r - ArmorySnap snapshots and scanner")
    print("|cFFFFFF00/wmachine range|r - Open Aura Range alert settings")
    print("|cFFFFFF00/wmachine exclude|r - Stop the debuff tracker treating your target as a boss")
    print("|cFFFFFF00/wmachine unexclude|r - Undo an exclusion for your target")
    print("|cFFFFFF00/wmachine exclusions|r - List excluded NPCs")
    print("|cFFFFFF00/wmachine clearexclusions|r - Remove every exclusion")
    print("|cFFFFFF00/wmachine whyboss|r - Explain how the tracker sees your target")
    print("|cFFFFFF00/wmachine shear|r - Illidan Shear monitor status and tallies")
    print("|cFFFFFF00/wmachine shear on|off|r - Toggle the Shear monitor")
    print("|cFFFFFF00/wmachine encounters|r - Debuff Tracker settings, opened at Encounter Callouts")
    print("|cFFFFFF00/wmachine srcheck|r - Show your equipped shadow resist gear")
    print("|cFFFFFF00/wmachine class|r - Open Class Tools for your class")
    print("|cFFFFFF00/wmachine soulstone|r - Soulstone timers in your group (warlock)")
    print("|cFFFFFF00/wmachine consumes|r - What the general raid checks see")
    print("|cFFFFFF00/wmachine portals|r - List your teleport/portal spells (mage)")
    print("|cFFFFFF00/wmachine whybuff|r - Show which buff checks your target's auras match")
    print("|cFFFFFF00/wmachine settings|r - Open addon settings (theme)")
    print("|cFFFFFF00/wmachine status|r - One-line status for every module")
    print("|cFFFFFF00/wmachine minimap|r - Toggle minimap button")
    print("|cFFFFFF00/wmachine resetminimap|r - Reset button position")
    print("|cFFFFFF00/wmachine debug|r - Show debug info")
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
    
    -- Debug command
    if cmd == "debug" then
        WM:Print("=== Debug Info ===")
        WM:Print("Version: " .. WM.version)
        WM:Print("IsInGuild: " .. tostring(IsInGuild()))
        local guildName, rankName, rankIndex = GetGuildInfo("player")
        WM:Print("GuildInfo: name='" .. tostring(guildName) .. "' rank='" .. tostring(rankName) .. "' index=" .. tostring(rankIndex))
        WM:Print("Verbose: " .. tostring(WatchingMachineDB and WatchingMachineDB.verboseChat))
        return
    end
    
    -- Error log commands
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

    elseif cmd == "buffcheck" or cmd == "buffs" or cmd == "bc" then
        local module = WM.modules.BuffCheck
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("BuffCheck module not available")
        end

    elseif cmd == "armory" or cmd == "armorysnap" or cmd == "gear" or cmd == "snap" then
        local module = WM.modules.ArmorySnap
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("ArmorySnap module not available")
        end

    elseif cmd == "soulstone" or cmd == "soulstones" or cmd == "ss" then
        local module = WM.modules.ClassWarlock
        if module and module.ReportSoulstones then
            module:ReportSoulstones()
        else
            WM:Print("ClassWarlock module not available")
        end

    elseif cmd == "consumes" or cmd == "consumables" then
        local module = WM.modules.ClassGeneral
        if module and module.Explain then
            module:Explain()
        else
            WM:Print("ClassGeneral module not available")
        end

    elseif cmd == "portals" or cmd == "teleports" then
        local module = WM.modules.ClassMage
        if module and module.ReportSpells then
            module:ReportSpells()
        else
            WM:Print("ClassMage module not available")
        end

    elseif cmd == "class" or cmd == "classes" or cmd == "classtools" then
        local module = WM.modules.ClassTools
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("ClassTools module not available")
        end

    elseif cmd == "encounters" or cmd == "callouts" then
        local module = WM.modules.DebuffTracker
        if module and module.ToggleEncounterUI then
            module:ToggleEncounterUI()
        else
            WM:Print("DebuffTracker module not available")
        end

    elseif cmd == "srcheck" or cmd == "sr" or cmd == "resist" then
        local module = WM.modules.DebuffTracker
        if module and module.ExplainShadowResist then
            module:ExplainShadowResist()
        else
            WM:Print("DebuffTracker module not available")
        end

    elseif cmd == "shear" or cmd == "shear on" or cmd == "shear off"
        or cmd == "shearstats" then
        local module = WM.modules.DebuffTracker
        if not module then
            WM:Print("DebuffTracker module not available")
            return
        end
        if cmd == "shear on" or cmd == "shear off" then
            local want = (cmd == "shear on")
            if DebuffTrackerDB and DebuffTrackerDB.shearMonitor ~= want then
                module:ToggleShearMonitor()
            else
                WM:Print("Shear monitor already " .. (want and "on" or "off"))
            end
        else
            module:ShowShearStatus()
        end

    elseif cmd == "whybuff" or cmd == "buffdebug" then
        local module = WM.modules.BuffCheck
        if module and module.ExplainUnit then
            -- Inspect your target if you have one, otherwise yourself
            module:ExplainUnit(UnitExists("target") and "target" or "player")
        else
            WM:Print("BuffCheck module not available")
        end

    elseif cmd == "exclude" or cmd == "unexclude" or cmd == "exclusions"
        or cmd == "excludelist" or cmd == "clearexclusions" or cmd == "whyboss" then
        local module = WM.modules.DebuffTracker
        if not module then
            WM:Print("DebuffTracker module not available")
            return
        end
        if cmd == "exclude" then
            module:ExcludeTarget()
        elseif cmd == "unexclude" then
            module:UnexcludeTarget()
        elseif cmd == "clearexclusions" then
            module:ClearExclusions()
        elseif cmd == "whyboss" then
            module:ExplainTarget()
        else
            module:ListExclusions()
        end

    elseif cmd == "range" or cmd == "aurarange" or cmd == "totem" or cmd == "aura" then
        local module = WM.modules.AuraRange
        if module and module.Toggle then
            module:Toggle()
        else
            WM:Print("AuraRange module not available")
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
            if module.GetQuickStatus then
                print("  " .. name .. ": " .. module:GetQuickStatus())
            else
                print("  " .. name .. ": |cFF888888Loaded|r")
            end
        end
        
    else
        WM:Print("Unknown command. Type /wmachine help for available commands.")
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
        -- Hide dashboard if it exists from previous session
        if dashboard then
            dashboard:Hide()
        end
        
        -- Create or reuse minimap button
        CreateMinimapButton()

        -- Entry in the game's own AddOns options list
        WM:RegisterOptionsCategory()
        
        -- Hook Minimap OnShow to restore our button when minimap becomes visible
        if Minimap and not Minimap.wmHooked then
            Minimap:HookScript("OnShow", function()
                RunAfter(0.1, function()
                    WM:RestoreMinimapButton()
                end)
            end)
            Minimap.wmHooked = true
        end
        
        -- Request guild roster for modules that need it
        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
        end
        
        -- Initialize immediately (no guild check needed)
        RunAfter(1, function()
            PerformSecurityCheck()
        end)
        
    elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        -- Guild roster updated (modules may need this data)
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Restore minimap button after zone change with a small delay
        RunAfter(0.5, function()
            WM:RestoreMinimapButton()
        end)
        WM:RestoreMinimapButton()
        
    elseif event == "PLAYER_LEAVING_WORLD" then
        -- Hide dashboard on logout/character switch
        if dashboard then
            dashboard:Hide()
        end
    end
end)
