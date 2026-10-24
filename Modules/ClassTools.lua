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
--
-- A feature can instead be a choice between options, shown as a dropdown.
-- It keeps its own value (get/set), so nothing is stored in ClassToolsDB
-- for it:
--
--   CT:RegisterFeature("MAGE", {
--       key = "portalDir", kind = "choice", name = "Portals expand",
--       options = { { value = "UP", text = "Up" }, ... },
--       get = function() return MageToolsDB.portalDir end,
--       set = function(v) MageToolsDB.portalDir = v end,
--   })

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
    if feature.kind == "choice" then return end   -- keeps its own value
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

-- Warnings that can have a sound of their own, for the Warning sounds
-- section: { class, key, label } in registration order
local alertSoundDefs = {}

function ClassTools:RegisterAlertSound(class, key, label)
    for _, d in ipairs(alertSoundDefs) do if d.key == key then return end end
    alertSoundDefs[#alertSoundDefs + 1] = { class = class, key = key, label = label }
end

function ClassTools:GetAlertSoundDefs() return alertSoundDefs end

-- The sound chosen for a warning, or nil for the shared warning sound
function ClassTools:AlertSound(key)
    local s = ClassToolsDB and type(ClassToolsDB.alertSounds) == "table" and ClassToolsDB.alertSounds[key]
    if s == "shared" then return nil end
    return s
end

function ClassTools:SetAlertSound(key, choice)
    if not ClassToolsDB then return end
    if type(ClassToolsDB.alertSounds) ~= "table" then ClassToolsDB.alertSounds = {} end
    ClassToolsDB.alertSounds[key] = (choice ~= "shared") and choice or nil
end

local function SoundChannel()
    return (GeneralChecksDB and GeneralChecksDB.soundChannel) or "Master"
end
ClassTools.SoundChannel = SoundChannel

-- sound (optional): a WM.Sounds choice ("wm:potion", "kit:8959", "none")
-- played when this warning first appears. Without one, the warning's choice
-- in the Warning sounds section is used, else the shared warning sound.
-- "none" is silent.
local lastSoundFor = {}
function ClassTools:SetAlert(key, text, icon, sound, channel)
    if not key or not WM:IsModuleOn("ClassTools") then return end
    if not activeAlerts[key] then
        alertOrder[#alertOrder + 1] = key
        -- Only make noise when a warning first appears
        local now = GetTime()
        sound = sound or self:AlertSound(key)
        channel = channel or SoundChannel()
        if sound == "none" then
            -- silent
        elseif sound and WM.Sounds then
            if (now - (lastSoundFor[key] or -100)) > ALERT_SOUND_THROTTLE then
                lastSoundFor[key] = now
                WM.Sounds.Play(sound, channel)
            end
        elseif ClassToolsDB and ClassToolsDB.alertSound
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
    if n == 0 or not WM:IsModuleOn("ClassTools") then f:Hide() return end

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
        if not WM:IsModuleOn("ClassTools") then return end
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
-- Class tabs, the selected class's features, then the warning-frame
-- options. The feature list is a single layout row whose contents are
-- rebuilt for the selected class and whose height is measured on reflow,
-- so a tab change or a late RegisterFeature only refreshes the panel, and
-- a long list makes the panel body scroll.

local mainFrame = nil
local selectedClass = nil

local TAB_W = 72
local tabsPerRow = 5
local tabRows = {}        -- layout rows holding the tab buttons
local tabChoices = {}     -- tabChoices[i] = the Choice widget in tabRows[i]
local tabSignature = nil  -- the class list the tabs were built for
local featureArea = nil   -- layout row the feature rows sit in
local featureRows = {}    -- pooled rows by kind: featureRows.check / .choice

local function CurrentClass()
    return selectedClass or ClassTools:GetPlayerClass()
end

-- Every class with features, plus the player's own even with nothing
-- registered yet, so the panel explains itself instead of looking broken.
local function TabClasses()
    local classes = ClassTools:GetPopulatedClasses()
    local mine = ClassTools:GetPlayerClass()
    if mine then
        local found = false
        for _, c in ipairs(classes) do if c == mine then found = true break end end
        if not found then table.insert(classes, 1, mine) end
    end
    return classes
end

-- Tabs only change when a feature registers for a new class, so the Choice
-- widgets are rebuilt then and just re-marked otherwise.
function ClassTools:RefreshTabs()
    if not mainFrame then return end

    local classes = TabClasses()
    local signature = table.concat(classes, ",")
    -- A selected class that lost its tab falls back to the player's own
    local stillThere = false
    for _, c in ipairs(classes) do if c == selectedClass then stillThere = true break end end
    if not stillThere then selectedClass = nil end
    if signature ~= tabSignature then
        tabSignature = signature
        for i, row in ipairs(tabRows) do
            if tabChoices[i] then tabChoices[i]:Hide() end
            tabChoices[i] = nil
            local options = {}
            for j = (i - 1) * tabsPerRow + 1, math.min(i * tabsPerRow, #classes) do
                local class = classes[j]
                options[#options + 1] = { value = class, text = CLASS_LABEL[class] or class, width = TAB_W }
            end
            row.hidden = (#options == 0)
            if #options > 0 then
                local choice = WM.UI.Choice(row.frame, {
                    options = options,
                    get = CurrentClass,
                    set = function(class)
                        selectedClass = class
                        ClassTools:RefreshUI()
                    end,
                })
                choice:SetPoint("LEFT", row.frame, "LEFT", 6, 0)
                tabChoices[i] = choice
            end
        end
    end
    for _, choice in pairs(tabChoices) do choice:Refresh() end
end

-- Choice rows: label column width, and where the description starts (the
-- dropdown's art is ~26px tall, centred on the label)
local CHOICE_LABEL_W, CHOICE_DESC_TOP = 185, 34

-- Rows are pooled per kind and re-pointed at a feature when the tab
-- changes, so every spec reads row.feature at call time
local function NewFeatureRow(parent, class, feature)
    local row = CreateFrame("Frame", nil, parent)
    row.class, row.feature = class, feature
    if feature.kind == "choice" then
        -- Label in a fixed-width column so every dropdown lines up, and
        -- level with the dropdown (which is taller than a checkbox)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("TOPLEFT", 14, -9)
        row.label:SetWidth(CHOICE_LABEL_W)
        row.label:SetJustifyH("LEFT")
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        row.cycle = WM.UI.Dropdown(row, setmetatable({ width = 130 }, { __index = function(_, k)
            local f = row.feature
            if k == "options" then return function() return row.feature.options end end
            if k == "get" then return function() return row.feature.get and row.feature.get() end end
            if k == "set" then
                return function(v)
                    local cur = row.feature
                    if cur.set then cur.set(v) end
                    if cur.onChange then pcall(cur.onChange, v) end
                end
            end
            -- read when hovered, so a re-pointed row shows its own tooltip
            if k == "tooltip" then return function() return row.feature.tooltip end end
        end }))
        row.cycle:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        row.check = row.cycle   -- what the list refreshes
    else
        row.check = WM.UI.Checkbox(row, {
            label = function() return row.feature.name or row.feature.key end,
            get = function() return ClassTools:IsEnabled(row.class, row.feature.key) end,
            set = function(v) ClassTools:SetEnabled(row.class, row.feature.key, v) end,
        })
        row.check:SetPoint("TOPLEFT", 8, 0)
    end
    row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Below the dropdown on choice rows: beside it, the dropdown covered
    -- the first line of the description
    row.descTop = (feature.kind == "choice") and CHOICE_DESC_TOP or 18
    row.desc:SetPoint("TOPLEFT", 36, -row.descTop)
    row.desc:SetWidth(330)
    row.desc:SetJustifyH("LEFT")
    return row
end

function ClassTools:BuildFeatureList()
    if not mainFrame then return end
    for _, pool in pairs(featureRows) do
        for _, row in ipairs(pool) do row:Hide() end
    end

    local class = CurrentClass()
    local features = self:GetFeatures(class)
    local parent = featureArea.frame
    local emptyText = mainFrame.emptyText

    if #features == 0 then
        emptyText:SetText((class == self:GetPlayerClass())
            and "No tools built for your class yet.\n\nWhen they are added they will appear here automatically."
            or  "Nothing built for this class yet.")
        emptyText:Show()
        featureArea.listHeight = math.floor(emptyText:GetStringHeight() + 12)
        return
    end
    emptyText:Hide()

    local y = 0
    local used = {}
    for _, f in ipairs(features) do
        local kind = (f.kind == "choice") and "choice" or "check"
        featureRows[kind] = featureRows[kind] or {}
        used[kind] = (used[kind] or 0) + 1
        local row = featureRows[kind][used[kind]]
        if row then
            row.class, row.feature = class, f
        else
            row = NewFeatureRow(parent, class, f)
            featureRows[kind][used[kind]] = row
        end
        if row.label then row.label:SetText(f.name or f.key) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
        row.check:Refresh()
        row.desc:SetText(f.desc and ("|cFF888888" .. f.desc .. "|r") or "")
        -- Room for a description that wraps onto more lines
        local h = f.desc and math.max(row.descTop + 22, math.floor(row.descTop + row.desc:GetStringHeight() + 6))
            or (row.descTop + 8)
        row:SetHeight(h)
        row:Show()
        y = y + h
    end
    featureArea.listHeight = y
end

function ClassTools:RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end
    mainFrame:Refresh()
end

function ClassTools:CreateUI()
    if mainFrame then return mainFrame end

    local panel = WM.UI:CreatePanel({
        name = "WM_ClassToolsFrame",
        title = "Class Tools",
        width = 420,
        maxHeight = 486,
        onRefresh = function()
            ClassTools:RefreshTabs()
            ClassTools:BuildFeatureList()
        end,
    })
    local L = panel.layout

    -- Enough tab rows for General plus every class
    tabsPerRow = math.max(1, math.floor((L.width - 6 + 2) / (TAB_W + 2)))
    for i = 1, math.ceil((#CLASS_ORDER + 1) / tabsPerRow) do
        tabRows[i] = L:Row(22)
    end

    -- Header naming the class being shown
    L:Row(24):Text({
        font = "GameFontNormal",
        text = function()
            local class = CurrentClass()
            local hex = class and ClassHex(class) or "ffffff"
            return "|cFF" .. hex .. (CLASS_LABEL[class] or "Unknown") .. "|r"
                .. ((class and class == ClassTools:GetPlayerClass()) and "  |cFF00FF00(your class)|r" or "")
        end,
    }, 8)

    featureArea = L:Row(26)
    featureArea.measure = function() return math.max(featureArea.listHeight or 0, 26) end

    local emptyText = featureArea.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", 12, -4)
    emptyText:SetWidth(350)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    panel.emptyText = emptyText

    -- ---------- Shared warning frame ----------
    L:Separator()
    L:Header("Warning frame")
    local row = L:Row(24)
    row:Checkbox({
        label = "Play a sound when a new warning appears",
        get = function() return ClassToolsDB and ClassToolsDB.alertSound end,
        set = function(v) if ClassToolsDB then ClassToolsDB.alertSound = v end end,
        tooltip = { "Warning Sound", "Plays the raid warning sound when a warning first appears,"
            .. " at most once every " .. ALERT_SOUND_THROTTLE .. " seconds." },
    }, 8)
    row:RightButton({
        text = "Reset position", width = 100,
        onClick = function() ClassTools:ResetAlertPosition() end,
        tooltip = { "Reset Position", "Move the warning frame back to its default spot, just above"
            .. " the centre of the screen." },
    }, 6)
    row = L:Row(24)
    row:Checkbox({
        label = "Lock the warning frame in place",
        get = function() return ClassToolsDB and ClassToolsDB.alertLocked end,
        set = function(v)
            if ClassToolsDB then ClassToolsDB.alertLocked = v end
            ClassTools:ApplyAlertLock()
        end,
        tooltip = { "Lock Warning Frame", "Stops the warning frame being dragged, and lets mouse"
            .. " clicks pass through it." },
    }, 8)
    row:RightButton({
        text = "Show example", width = 100,
        onClick = function() ClassTools:ShowExampleAlert() end,
        tooltip = { "Show Example", "Puts two example warnings up for a few seconds, so the frame"
            .. " can be found and dragged into place." },
    }, 6)
    L:Note("Tabs appear for each class that has tools built for it. Drag the warning frame to move it.")

    -- One sound choice per warning, for General and your class
    local mine = ClassTools:GetPlayerClass()
    local shown = 0
    for _, d in ipairs(alertSoundDefs) do
        if d.class == "GENERAL" or d.class == mine then
            if shown == 0 then L:Section({ key = "sounds", title = "Warning sounds" }) end
            shown = shown + 1
            L:Dropdown({
                label = d.label .. ":", width = 150,
                options = function()
                    local opts = { { value = "shared", text = "Shared warning sound" } }
                    for _, o in ipairs(WM.Sounds and WM.Sounds.OPTIONS or {}) do opts[#opts + 1] = o end
                    return opts
                end,
                get = function() return (ClassToolsDB and ClassToolsDB.alertSounds and ClassToolsDB.alertSounds[d.key]) or "shared" end,
                set = function(v)
                    ClassTools:SetAlertSound(d.key, v)
                    if v ~= "shared" and WM.Sounds then WM.Sounds.Play(v, SoundChannel()) end
                end,
                tooltip = { d.label, "Played once when this warning appears. Shared: the sound above, if it's on."
                    .. " None: silent. Picking a sound plays it." },
            })
        end
    end
    if shown > 0 then
        L:Note("The mana potion and rune sounds are in the General tab. Sounds play on the channel set there.")
        L:EndSection()
    end

    mainFrame = panel
    self.mainFrame = panel
    return panel:Finish()
end

function ClassTools:Toggle()
    if not WM:IsModuleOn("ClassTools") then return end
    local f = self:CreateUI()
    if f:IsShown() then f:Hide() else f:Show() end
end

function ClassTools:ToggleUI()
    self:Toggle()
end

-- ============================================
-- ON / OFF
-- ============================================

-- Turned off on this character: the warnings go and the monitor tick
-- idles. Core turns the class parts off first; each hides its own buttons
-- and bars.
function ClassTools:OnModuleOff()
    self:ClearAllAlerts()
    if alertFrame then alertFrame:Hide() end
    if mainFrame then mainFrame:Hide() end
end

-- ============================================
-- GUIDED SETUP
-- ============================================
-- One page for Class Tools and all its parts: your own class's tools, then
-- the General ones, grouped. Built from the feature registry, so it shows
-- what the Class Tools window shows. The parts register their features
-- here without starting (no frames, no events), so it works before Class
-- Tools has run on this character.

-- The part that holds a class's tools
local CLASS_PART = { WARLOCK = "ClassWarlock", MAGE = "ClassMage", SHAMAN = "ClassShaman", PALADIN = "ClassPaladin" }

-- What a class's tools are for, in a sentence or two
local CLASS_NOTES = {
    WARLOCK = "Warnings when your armour spell is missing, and when Demonic Sacrifice or Soul Link should be up"
        .. " (only if you have the talent). Soulstone timers for everyone in range: |cFFFFFF00/wmachine soulstone|r."
        .. " The warlock button is a draggable warlock crest that opens into three groups of icons: demons,"
        .. " armours, and stones & rituals. Click an icon to cast it.",
    MAGE = "A warning when no armour spell is up, a portal button with every portal and teleport you know, and a"
        .. " mage button with your mana gems, armours, and food, water and table. Click an icon to cast it."
        .. " |cFFFFFF00/wmachine portals|r lists what you know.",
    SHAMAN = "The totem button: hover it to pick one of four totem sets, then click it to drop that set one totem"
        .. " per click (Air, Water, Earth, then Fire). It starts again from Air when your totems are gone, after"
        .. " combat, or on Ctrl-click. Right-click it to edit the sets; Shift-drag to move it.",
    PALADIN = "A warning when Righteous Fury drops, for Protection paladins only, so you don't lose threat.",
}

-- General features, grouped for the page; anything not listed goes last
local GENERAL_GROUPS = {
    { key = "consumables", title = "Raid consumables",
      note = "Only inside a raid instance (25-man only, unless you untick that). A warning stays in the"
          .. " CHECK YOURSELF frame until you fix it, with the warning sound when it first appears.",
      keys = { "flask", "food", "weaponenchant", "only25" } },
    { key = "mana", title = "Mana potions and runes", mana = true,
      note = "In raid combat, as your mana drops: first a nudge to drink a mana potion, then, while no potion is"
          .. " ready (on cooldown or none left), to use a Dark or Demonic Rune. Each has its own sound.",
      keys = { "manapotion", "potionAt", "potionSound", "manarune", "runeAt", "runeSound" } },
    { key = "swing", title = "Swing timer", swing = true,
      note = "A bar per hand showing the time to your next melee swing, or to your next Auto Shot for hunters. It shows"
          .. " while you attack. |cFFFFFF00/wmachine swing|r shows it for 10 seconds so you can drag it into place.",
      keys = { "swingTimer", "swingAnyClass", "swingSync", "swingSyncSound", "swingSyncLag",
               "swingWidth", "swingHeight", "swingLock" } },
    { key = "flyout", title = "Flyout buttons", flyout = true,
      note = "How every class button opens, and whether they line up together.",
      keys = { "flyoutOpen", "flyoutDock", "flyoutDockDir", "flyoutLock" } },
}

-- Classes that get a swing timer without the "every class" option
local SWING_CLASSES = { WARRIOR = true, ROGUE = true, HUNTER = true, PALADIN = true, SHAMAN = true }
local NO_MANA = { WARRIOR = true, ROGUE = true }
-- Only for classes with a default swing timer, and the sync ones only for shamans
local SWING_FULL = { swingSync = "SHAMAN", swingSyncSound = "SHAMAN", swingSyncLag = "SHAMAN",
    swingWidth = true, swingHeight = true, swingLock = true }

-- A setting that only matters while another (a check) is on
local DEPENDS = {
    potionAt = "manapotion", potionSound = "manapotion", runeAt = "manarune", runeSound = "manarune",
    swingAnyClass = "swingTimer", swingSync = "swingTimer", swingSyncSound = "swingSync", swingSyncLag = "swingSync",
    swingWidth = "swingTimer", swingHeight = "swingTimer", swingLock = "swingTimer",
    flyoutDockDir = "flyoutDock",
}

-- Register every part's features without starting anything
function ClassTools:RegisterPartFeatures()
    self:InitDB()
    for _, name in ipairs(WM.ModuleChildren and WM.ModuleChildren("ClassTools") or {}) do
        local m = WM.modules[name]
        if m and m.RegisterFeatures then m:RegisterFeatures() end
    end
end

function ClassTools:SetupPage(L)
    self:RegisterPartFeatures()
    local class = self:DetectClass()
    local label = CLASS_LABEL[class] or class or "Unknown"
    local function Changed() if L.panel and L.panel.Refresh then L.panel:Refresh() end end
    local lastDir = {}

    local function IsOn(c, key) return self:IsEnabled(c, key) end

    -- One feature: a check (with its description below it), a choice, or a
    -- button group's direction (shown / left off, and which way it opens)
    local function Feature(c, f, parentKey)
        local off = parentKey and function() return not IsOn(c, parentKey) end or nil
        if f.direction then
            local function Hidden() return f.get() == "HIDDEN" end
            L:Checkbox({ label = "Show the " .. (f.what or f.name) .. " icons", indent = 16,
                get = function() return not Hidden() end,
                set = function(v)
                    if v then
                        local d = lastDir[f.key] or f.default
                        if not d or d == "HIDDEN" then d = "UP" end
                        f.set(d)
                    else
                        lastDir[f.key] = f.get()
                        f.set("HIDDEN")
                    end
                    if f.onChange then pcall(f.onChange, f.get()) end
                    Changed()
                end,
                disabled = off,
                tooltip = { f.name, "Untick to leave the " .. (f.what or f.name) .. " icons off the button and keep the rest." } })
            local opts = {}
            for _, o in ipairs(WM.Flyout and WM.Flyout.DIRECTION_OPTIONS or {}) do
                if o.value ~= "HIDDEN" then opts[#opts + 1] = o end
            end
            L:Dropdown({ label = "Opens:", width = 90, indent = 40, options = opts,
                get = function() return f.get() end,
                set = function(v) f.set(v); if f.onChange then pcall(f.onChange, v) end end,
                disabled = function() return Hidden() or (off and off()) end,
                tooltip = { f.name, "Which way these icons fan out from the button. Groups that open the same way share one line." } })
        elseif f.kind == "choice" then
            L:Dropdown({ label = (f.name or f.key) .. ":", width = 150, indent = parentKey and 16 or 0,
                options = f.options or {}, get = function() return f.get and f.get() end,
                set = function(v)
                    if f.set then f.set(v) end
                    if f.onChange then pcall(f.onChange, v) end
                end,
                disabled = off,
                tooltip = f.tooltip or (f.desc and { f.name, f.desc }) })
        else
            L:Checkbox({ label = f.name or f.key, indent = parentKey and 16 or 0,
                get = function() return IsOn(c, f.key) end,
                set = function(v) self:SetEnabled(c, f.key, v); Changed() end,
                disabled = off,
                tooltip = f.desc and { f.name, f.desc } })
            if f.desc then L:Note(f.desc, 24 + (parentKey and 16 or 0)) end
        end
    end

    L:Note("Class Tools watches you, not the raid: about once a second it checks the things you're expected to"
        .. " keep up yourself, and anything missing goes in one small |cFFFFAA00CHECK YOURSELF|r frame near the"
        .. " middle of your screen until you fix it. Each warning can be switched off on its own.")
    L:Note("It knows your class: below are the " .. "|cFF" .. ClassHex(class or "") .. label .. "|r"
        .. " tools, then the general ones every character gets.")

    -- ---------- Your class ----------
    L:Header("|cFF" .. ClassHex(class or "") .. label .. "|r tools")
    local mine = self:GetFeatures(class)
    if #mine == 0 then
        L:Note("Nothing just for " .. label .. "s yet. The general checks below still apply, and new class tools"
            .. " appear here by themselves when they're added.")
    else
        if CLASS_NOTES[class] then L:Note(CLASS_NOTES[class]) end
        local button
        for _, f in ipairs(mine) do
            if f.direction then
                Feature(class, f, button)
            else
                if f.kind ~= "choice" then
                    button = f.key:find("Button$") and f.key or nil
                end
                Feature(class, f, nil)
            end
        end
        local part = WM.modules[CLASS_PART[class] or ""]
        if part and part.SetupExtras then part:SetupExtras(L, Changed) end
    end

    -- ---------- General ----------
    local general = self:GetFeatures("GENERAL")
    local byKey, placed = {}, {}
    for _, f in ipairs(general) do byKey[f.key] = f end
    local hasFlyout = false
    for _, fly in ipairs(WM.Flyout and WM.Flyout.registry or {}) do
        if fly.cfg.class == class then hasFlyout = true end
    end
    for _, g in ipairs(GENERAL_GROUPS) do
        local show = true
        if g.mana and NO_MANA[class] then show = false end
        if g.flyout and not hasFlyout then show = false end
        local any = false
        for _, k in ipairs(g.keys) do if byKey[k] then any = true end end
        if show and any then
            L:Header(g.title)
            if g.note then L:Note(g.note) end
            for _, k in ipairs(g.keys) do
                local f = byKey[k]
                local want = f ~= nil
                local full = SWING_FULL[k]
                if want and g.swing and full then
                    want = SWING_CLASSES[class] and (full == true or full == class) or false
                end
                if want then Feature("GENERAL", f, DEPENDS[k]) end
            end
            if g.swing and not SWING_CLASSES[class] then
                L:Note("It's for melee classes and hunters, so a " .. label .. " only gets one with the second option ticked.")
            end
        end
        for _, k in ipairs(g.keys) do placed[k] = true end
    end
    local others = {}
    for _, f in ipairs(general) do
        if not placed[f.key] and f.key ~= "soundChannel" then others[#others + 1] = f end
    end
    if #others > 0 then
        L:Header("Other checks")
        for _, f in ipairs(others) do Feature("GENERAL", f, DEPENDS[f.key]) end
    end

    -- ---------- The warning frame ----------
    L:Header("The warning frame")
    L:Checkbox({ label = "Play a sound when a new warning appears",
        get = function() return ClassToolsDB and ClassToolsDB.alertSound end,
        set = function(v) if ClassToolsDB then ClassToolsDB.alertSound = v end end,
        tooltip = { "Warning Sound", "The raid warning sound, when a warning first appears, at most once every "
            .. ALERT_SOUND_THROTTLE .. " seconds. The mana potion and rune warnings use their own sounds above." } })
    if byKey.soundChannel then Feature("GENERAL", byKey.soundChannel) end
    L:Checkbox({ label = "Lock the warning frame in place",
        get = function() return ClassToolsDB and ClassToolsDB.alertLocked end,
        set = function(v)
            if ClassToolsDB then ClassToolsDB.alertLocked = v end
            self:ApplyAlertLock()
        end,
        tooltip = { "Lock Warning Frame", "Stops the warning frame being dragged, and lets mouse clicks pass through it." } })
    local function NotRunning() return not (WM:IsModuleOn("ClassTools") and alertFrame) end
    L:Buttons({
        { text = "Show example", width = 110, disabled = NotRunning,
          onClick = function() self:ShowExampleAlert() end,
          tooltip = { "Show Example", "Puts two example warnings up for a few seconds, so you can find the frame"
              .. " and drag it where you want it. Needs Class Tools on." } },
        { text = "Reset position", width = 110, onClick = function() self:ResetAlertPosition() end,
          tooltip = { "Reset Position", "Moves the warning frame back to just above the centre of the screen." } },
    })

    L:Note("On your other characters this page shows their own class's tools: warlock armour and soulstones,"
        .. " mage portals, shaman totems, paladin Righteous Fury. The General ones are the same everywhere,"
        .. " but each character keeps its own choices.")
    L:Note("Everything here, plus a sound for each warning, is in the Class Tools window: |cFFFFFF00/wmachine class|r.")
end
