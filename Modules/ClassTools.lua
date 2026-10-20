-- Watching Machine: Class Tools Module
-- Detects the class you are playing and surfaces the tools built for it.
--
-- This file is the FRAMEWORK, not the tools themselves. Per-class features
-- register into it, and the panel builds itself from whatever is registered:
-- a tab appears for a class only once something has been registered for that
-- class, so the UI never shows empty tabs for work that hasn't been done yet.
--
-- Registering a feature, from anywhere in the addon:
--
--   local CT = WM.modules.ClassTools
--   CT:RegisterFeature("SHAMAN", {
--       key   = "totemReminder",           -- unique within the class
--       name  = "Totem reminder",
--       desc  = "Warn when a totem drops off.",
--       default = false,                   -- enabled state for new installs
--       onToggle = function(enabled) ... end,   -- optional
--   })
--
-- Enabled state is saved per character in ClassToolsDB, so a feature can ask
--   CT:IsEnabled("SHAMAN", "totemReminder")
-- without caring about the UI at all.

local AddonName, WM = ...
local ClassTools = {}
WM:RegisterModule("ClassTools", ClassTools)

ClassTools.version = "3.4"

-- ============================================
-- CLASS LIST (TBC)
-- ============================================

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local CLASS_LABEL = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER  = "Hunter",
    ROGUE   = "Rogue",   PRIEST  = "Priest",  SHAMAN  = "Shaman",
    MAGE    = "Mage",    WARLOCK = "Warlock", DRUID   = "Druid",
    -- Pseudo-class for checks that apply to everyone
    GENERAL = "General",
}

-- Fallbacks if RAID_CLASS_COLORS is unavailable for any reason
local CLASS_RGB = {
    WARRIOR = {0.78,0.61,0.43}, PALADIN = {0.96,0.55,0.73}, HUNTER  = {0.67,0.83,0.45},
    ROGUE   = {1.00,0.96,0.41}, PRIEST  = {1.00,1.00,1.00}, SHAMAN  = {0.00,0.44,0.87},
    MAGE    = {0.25,0.78,0.92}, WARLOCK = {0.53,0.53,0.93}, DRUID   = {1.00,0.49,0.04},
    GENERAL = {0.70,0.90,0.70},
}

local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.r then return c.r, c.g, c.b end
    local f = CLASS_RGB[class] or {1,1,1}
    return f[1], f[2], f[3]
end

local function ClassHex(class)
    local r, g, b = ClassColor(class)
    return string.format("%02x%02x%02x", r*255, g*255, b*255)
end

-- ============================================
-- FEATURE REGISTRY
-- ============================================
-- registry[CLASS] = { ordered list of feature definitions }

local registry = {}
local playerClass = nil

local defaults = {
    enabled = {},            -- enabled["SHAMAN"]["totemReminder"] = true/false
    showAllClasses = false,  -- show tabs for classes you aren't playing
    alertSound = true,       -- play a sound when a warning first appears
    alertLocked = false,     -- lock the warning frame in place
    alertX = nil,
    alertY = nil,
}

function ClassTools:Initialize()
    self:InitDB()
    self:DetectClass()
    self:CreateAlertFrame()
    self:StartMonitorTick()
end

function ClassTools:InitDB()
    if not ClassToolsDB then ClassToolsDB = {} end
    for k, v in pairs(defaults) do
        if ClassToolsDB[k] == nil then
            ClassToolsDB[k] = (type(v) == "table") and {} or v
        end
    end
    if type(ClassToolsDB.enabled) ~= "table" then ClassToolsDB.enabled = {} end
    -- Apply defaults for anything registered before the DB existed
    for class, features in pairs(registry) do
        for _, f in ipairs(features) do
            self:EnsureDefault(class, f)
        end
    end
end

function ClassTools:EnsureDefault(class, feature)
    if not ClassToolsDB then return end
    ClassToolsDB.enabled[class] = ClassToolsDB.enabled[class] or {}
    if ClassToolsDB.enabled[class][feature.key] == nil then
        ClassToolsDB.enabled[class][feature.key] = feature.default and true or false
    end
end

function ClassTools:Print(msg)
    WM:ModulePrint("ClassTools", msg)
end

function ClassTools:DetectClass()
    local _, class = UnitClass("player")
    playerClass = class
    return class
end

function ClassTools:GetPlayerClass()
    if not playerClass then self:DetectClass() end
    return playerClass
end

function ClassTools:GetPlayerClassLabel()
    local c = self:GetPlayerClass()
    return CLASS_LABEL[c] or c or "Unknown"
end

-- Register one feature for a class. Safe to call at file-load time, before
-- the saved variables exist.
function ClassTools:RegisterFeature(class, feature)
    if not class or not feature or not feature.key then return end
    if not CLASS_LABEL[class] then
        self:Print("Ignoring feature for unknown class: " .. tostring(class))
        return
    end
    registry[class] = registry[class] or {}
    for _, existing in ipairs(registry[class]) do
        if existing.key == feature.key then return end  -- already registered
    end
    table.insert(registry[class], feature)
    if ClassToolsDB then self:EnsureDefault(class, feature) end
    -- A newly registered feature may add a tab
    if self.RefreshUI then self:RefreshUI() end
end

function ClassTools:GetFeatures(class)
    return registry[class] or {}
end

function ClassTools:HasFeatures(class)
    local f = registry[class]
    return f ~= nil and #f > 0
end

-- Classes that have something to show
function ClassTools:GetPopulatedClasses()
    local out = {}
    -- General first: it applies to every character
    if self:HasFeatures("GENERAL") then out[#out + 1] = "GENERAL" end
    for _, class in ipairs(CLASS_ORDER) do
        if self:HasFeatures(class) then out[#out + 1] = class end
    end
    return out
end

-- The question a feature actually asks
function ClassTools:IsEnabled(class, key)
    if not ClassToolsDB or not ClassToolsDB.enabled[class] then return false end
    return ClassToolsDB.enabled[class][key] and true or false
end

function ClassTools:SetEnabled(class, key, value)
    if not ClassToolsDB then return end
    ClassToolsDB.enabled[class] = ClassToolsDB.enabled[class] or {}
    ClassToolsDB.enabled[class][key] = value and true or false

    for _, f in ipairs(self:GetFeatures(class)) do
        if f.key == key and f.onToggle then
            pcall(f.onToggle, value and true or false)
        end
    end
end

-- Convenience for features that only ever apply to the player's own class
function ClassTools:IsActiveForPlayer(key)
    local c = self:GetPlayerClass()
    if not c then return false end
    return self:IsEnabled(c, key)
end

-- ============================================
-- SHARED MONITOR + ALERT DISPLAY
-- ============================================
-- Class features need the same two things: a periodic "check yourself" tick,
-- and somewhere to put a warning. Both live here so each class file stays
-- just its own rules, and so every warning lands in one frame the player can
-- move once rather than one frame per class.

local monitors = {}          -- list of functions run on the tick
local activeAlerts = {}      -- key -> { text = , icon = }
local alertOrder = {}        -- stable display order
local monitorFrame = nil
local alertFrame = nil
local monitorAccum = 0
local MONITOR_INTERVAL = 1.0
local lastAlertSound = 0
local ALERT_SOUND_THROTTLE = 4

-- Register a function called about once a second. It should call SetAlert /
-- ClearAlert for its own keys and nothing else.
function ClassTools:RegisterMonitor(fn)
    if type(fn) ~= "function" then return end
    monitors[#monitors + 1] = fn
end

function ClassTools:SetAlert(key, text, icon)
    if not key then return end
    if not activeAlerts[key] then
        alertOrder[#alertOrder + 1] = key
        -- Only make noise when a warning first appears
        local now = GetTime()
        if ClassToolsDB and ClassToolsDB.alertSound
            and (now - lastAlertSound) > ALERT_SOUND_THROTTLE then
            lastAlertSound = now
            pcall(PlaySound, 8959, "Master")
        end
    end
    activeAlerts[key] = { text = text, icon = icon }
    self:UpdateAlertFrame()
end

function ClassTools:ClearAlert(key)
    if not key or not activeAlerts[key] then return end
    activeAlerts[key] = nil
    for i = #alertOrder, 1, -1 do
        if alertOrder[i] == key then table.remove(alertOrder, i) end
    end
    self:UpdateAlertFrame()
end

function ClassTools:ClearAllAlerts()
    wipe(activeAlerts)
    wipe(alertOrder)
    self:UpdateAlertFrame()
end

function ClassTools:GetActiveAlertCount()
    return #alertOrder
end

local MAX_ALERT_LINES = 6

function ClassTools:CreateAlertFrame()
    if alertFrame then return alertFrame end

    local f = CreateFrame("Frame", "WM_ClassToolsAlertFrame", UIParent, "BackdropTemplate")
    f:SetSize(250, 40)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.25, 0.12, 0.02, 0.85)
    f:SetBackdropBorderColor(1, 0.6, 0.1, 1)
    f:Hide()

    if ClassToolsDB and ClassToolsDB.alertX and ClassToolsDB.alertY then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ClassToolsDB.alertX, ClassToolsDB.alertY)
    end

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not (ClassToolsDB and ClassToolsDB.alertLocked) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if ClassToolsDB then ClassToolsDB.alertX, ClassToolsDB.alertY = x, y end
    end)
    f:EnableMouse(not (ClassToolsDB and ClassToolsDB.alertLocked))

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -5)
    header:SetText("|cFFFFAA00CHECK YOURSELF|r")

    f.lines = {}
    for i = 1, MAX_ALERT_LINES do
        local line = CreateFrame("Frame", nil, f)
        line:SetSize(230, 18)
        line:SetPoint("TOP", 0, -22 - (i - 1) * 19)
        local icon = line:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        line.icon = icon
        local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        line.text = text
        line:Hide()
        f.lines[i] = line
    end

    alertFrame = f
    self.alertFrame = f
    return f
end

-- Lock state is read on drag, but the mouse flag has to be flipped on the
-- live frame or a locked frame still swallows clicks.
function ClassTools:ApplyAlertLock()
    if not alertFrame then return end
    alertFrame:EnableMouse(not (ClassToolsDB and ClassToolsDB.alertLocked))
end

function ClassTools:ResetAlertPosition()
    if ClassToolsDB then
        ClassToolsDB.alertX, ClassToolsDB.alertY = nil, nil
    end
    if alertFrame then
        alertFrame:ClearAllPoints()
        alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
    self:Print("Warning frame moved back to the centre of the screen.")
end

-- Puts two dummy lines up for a few seconds so the frame can be found and
-- dragged without waiting for a real warning.
function ClassTools:ShowExampleAlert()
    self:SetAlert("example1", "This is where warnings appear",
        "Interface\\Icons\\INV_Misc_QuestionMark")
    self:SetAlert("example2", "Drag the frame to move it",
        "Interface\\Icons\\INV_Misc_QuestionMark")
    if WM.RunAfter then
        WM.RunAfter(6, function()
            ClassTools:ClearAlert("example1")
            ClassTools:ClearAlert("example2")
        end)
    end
end

function ClassTools:UpdateAlertFrame()
    local f = alertFrame
    if not f then return end

    local n = #alertOrder
    if n == 0 then f:Hide() return end

    local shown = math.min(n, MAX_ALERT_LINES)
    for i = 1, MAX_ALERT_LINES do
        local line = f.lines[i]
        local key = alertOrder[i]
        local a = key and activeAlerts[key]
        if i <= shown and a then
            line.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            line.text:SetText(a.text or key)
            line:Show()
        else
            line:Hide()
        end
    end
    f:SetHeight(28 + shown * 19)
    f:Show()
end

function ClassTools:RunMonitors()
    -- A feature only runs for the class it was registered under, and only
    -- when its own toggle is on; each monitor checks that for itself.
    for _, fn in ipairs(monitors) do
        pcall(fn)
    end
end

function ClassTools:StartMonitorTick()
    if monitorFrame then return end
    monitorFrame = CreateFrame("Frame")
    monitorFrame:SetScript("OnUpdate", function(_, elapsed)
        monitorAccum = monitorAccum + elapsed
        if monitorAccum < MONITOR_INTERVAL then return end
        monitorAccum = 0
        ClassTools:RunMonitors()
    end)
end

-- ============================================
-- STATUS
-- ============================================

function ClassTools:GetQuickStatus()
    if not ClassToolsDB then return "|cFF888888Not initialized|r" end

    local class = self:GetPlayerClass()
    local hex = class and ClassHex(class) or "ffffff"
    local label = self:GetPlayerClassLabel()

    local mine = self:GetFeatures(class)
    if #mine == 0 then
        local populated = #self:GetPopulatedClasses()
        if populated == 0 then
            return "|cFF" .. hex .. label .. "|r - |cFF888888no class tools yet|r"
        end
        return "|cFF" .. hex .. label .. "|r - |cFF888888nothing for your class yet|r ("
            .. populated .. " other class" .. (populated == 1 and "" or "es") .. ")"
    end

    local on = 0
    for _, f in ipairs(mine) do
        if self:IsEnabled(class, f.key) then on = on + 1 end
    end
    return "|cFF" .. hex .. label .. "|r - " .. on .. "/" .. #mine .. " enabled"
end

-- ============================================
-- UI
-- ============================================

local mainFrame = nil
local selectedClass = nil
local tabButtons = {}
local featureRows = {}

local TAB_W, TAB_H = 72, 22

local function ClearFeatureRows()
    for _, row in ipairs(featureRows) do
        row:Hide()
    end
end

function ClassTools:BuildFeatureList()
    if not mainFrame then return end
    ClearFeatureRows()

    local class = selectedClass or self:GetPlayerClass()
    local features = self:GetFeatures(class)
    local parent = mainFrame.content

    -- Header naming the class being shown
    local hex = class and ClassHex(class) or "ffffff"
    local label = CLASS_LABEL[class] or "Unknown"
    local isYours = (class == self:GetPlayerClass())
    mainFrame.classHeader:SetText("|cFF" .. hex .. label .. "|r"
        .. (isYours and "  |cFF00FF00(your class)|r" or ""))

    if #features == 0 then
        mainFrame.emptyText:SetText(isYours
            and "No tools built for your class yet.\n\nWhen they are added they will appear here automatically."
            or  "Nothing built for this class yet.")
        mainFrame.emptyText:Show()
        return
    end
    mainFrame.emptyText:Hide()

    local y = 0
    for i, f in ipairs(features) do
        local row = featureRows[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetHeight(40)
            row:SetPoint("LEFT", 0, 0)
            row:SetPoint("RIGHT", 0, 0)

            row.check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
            row.check:SetPoint("TOPLEFT", 0, 0)

            row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.desc:SetPoint("TOPLEFT", 28, -18)
            row.desc:SetWidth(330)
            row.desc:SetJustifyH("LEFT")

            featureRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)

        row.check.Text:SetText(f.name or f.key)
        row.check:SetChecked(self:IsEnabled(class, f.key))
        row.check:SetScript("OnClick", function(cb)
            ClassTools:SetEnabled(class, f.key, cb:GetChecked())
        end)

        row.desc:SetText(f.desc and ("|cFF888888" .. f.desc .. "|r") or "")
        row:Show()

        y = y + (f.desc and 40 or 26)
    end
end

function ClassTools:RefreshTabs()
    if not mainFrame then return end

    local classes = self:GetPopulatedClasses()
    -- Always offer the player's own class, even with nothing registered yet,
    -- so the panel explains itself instead of looking broken.
    local mine = self:GetPlayerClass()
    if mine then
        local found = false
        for _, c in ipairs(classes) do if c == mine then found = true break end end
        if not found then table.insert(classes, 1, mine) end
    end

    for _, btn in ipairs(tabButtons) do btn:Hide() end

    local x, row = 0, 0
    for i, class in ipairs(classes) do
        local btn = tabButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
            btn:SetSize(TAB_W, TAB_H)
            tabButtons[i] = btn
        end
        if x + TAB_W > 380 then x, row = 0, row + 1 end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 18 + x, -44 - row * (TAB_H + 3))

        local hex = ClassHex(class)
        local isSel = (class == (selectedClass or mine))
        btn:SetText((isSel and "|cFFFFFFFF>|r " or "") .. "|cFF" .. hex .. (CLASS_LABEL[class] or class) .. "|r")
        btn:SetScript("OnClick", function()
            selectedClass = class
            ClassTools:RefreshTabs()
            ClassTools:BuildFeatureList()
        end)
        btn:Show()
        x = x + TAB_W + 3
    end

    mainFrame.tabRows = row + 1
    mainFrame.content:ClearAllPoints()
    mainFrame.content:SetPoint("TOPLEFT", 20, -44 - (row + 1) * (TAB_H + 3) - 28)
    mainFrame.content:SetPoint("BOTTOMRIGHT", -20, 112)
    mainFrame.classHeader:ClearAllPoints()
    mainFrame.classHeader:SetPoint("TOPLEFT", 20, -44 - (row + 1) * (TAB_H + 3) - 8)
end

function ClassTools:RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end
    self:RefreshTabs()
    self:BuildFeatureList()
end

function ClassTools:CreateUI()
    if mainFrame then return mainFrame end

    local theme = WM:GetTheme()

    local frame = CreateFrame("Frame", "WM_ClassToolsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 486)
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Class Tools")
    WM:ThemeText(title, "headerColor")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local classHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classHeader:SetPoint("TOPLEFT", 20, -100)
    frame.classHeader = classHeader

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 20, -124)
    content:SetPoint("BOTTOMRIGHT", -20, 112)
    frame.content = content

    local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", 4, -4)
    emptyText:SetWidth(360)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    frame.emptyText = emptyText

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT", 18, 104)
    divider:SetPoint("BOTTOMRIGHT", -18, 104)

    local optHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optHeader:SetPoint("BOTTOMLEFT", 20, 86)
    optHeader:SetText("Warning frame")

    local soundCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    soundCB:SetPoint("BOTTOMLEFT", 18, 58)
    soundCB.Text:SetText("Play a sound when a new warning appears")
    soundCB:SetScript("OnClick", function(cb)
        if ClassToolsDB then ClassToolsDB.alertSound = cb:GetChecked() and true or false end
    end)
    frame.soundCB = soundCB

    local lockCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    lockCB:SetPoint("BOTTOMLEFT", 18, 36)
    lockCB.Text:SetText("Lock the warning frame in place")
    lockCB:SetScript("OnClick", function(cb)
        if ClassToolsDB then ClassToolsDB.alertLocked = cb:GetChecked() and true or false end
        ClassTools:ApplyAlertLock()
    end)
    frame.lockCB = lockCB

    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 20)
    resetBtn:SetPoint("BOTTOMRIGHT", -18, 58)
    resetBtn:SetText("Reset position")
    resetBtn:SetScript("OnClick", function() ClassTools:ResetAlertPosition() end)

    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 20)
    testBtn:SetPoint("BOTTOMRIGHT", -18, 36)
    testBtn:SetText("Show example")
    testBtn:SetScript("OnClick", function() ClassTools:ShowExampleAlert() end)

    local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", 20, 14)
    foot:SetWidth(380)
    foot:SetJustifyH("LEFT")
    foot:SetText("|cFF888888Tabs appear for each class that has tools built for it. "
        .. "Drag the warning frame to move it.|r")

    frame:SetScript("OnShow", function()
        selectedClass = selectedClass or ClassTools:GetPlayerClass()
        soundCB:SetChecked(ClassToolsDB and ClassToolsDB.alertSound and true or false)
        lockCB:SetChecked(ClassToolsDB and ClassToolsDB.alertLocked and true or false)
        ClassTools:RefreshTabs()
        ClassTools:BuildFeatureList()
    end)

    mainFrame = frame
    self.mainFrame = frame
    return frame
end

function ClassTools:Toggle()
    local f = self:CreateUI()
    if f:IsShown() then f:Hide() else f:Show() end
end

function ClassTools:ToggleUI()
    self:Toggle()
end
