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
}

-- Fallbacks if RAID_CLASS_COLORS is unavailable for any reason
local CLASS_RGB = {
    WARRIOR = {0.78,0.61,0.43}, PALADIN = {0.96,0.55,0.73}, HUNTER  = {0.67,0.83,0.45},
    ROGUE   = {1.00,0.96,0.41}, PRIEST  = {1.00,1.00,1.00}, SHAMAN  = {0.00,0.44,0.87},
    MAGE    = {0.25,0.78,0.92}, WARLOCK = {0.53,0.53,0.93}, DRUID   = {1.00,0.49,0.04},
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
    enabled = {},        -- enabled["SHAMAN"]["totemReminder"] = true/false
    showAllClasses = false,  -- show tabs for classes you aren't playing
}

function ClassTools:Initialize()
    self:InitDB()
    self:DetectClass()
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
    mainFrame.content:SetPoint("BOTTOMRIGHT", -20, 46)
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
    frame:SetSize(420, 420)
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
    title:SetTextColor(unpack(theme.headerColor))

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local classHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classHeader:SetPoint("TOPLEFT", 20, -100)
    frame.classHeader = classHeader

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 20, -124)
    content:SetPoint("BOTTOMRIGHT", -20, 46)
    frame.content = content

    local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", 4, -4)
    emptyText:SetWidth(360)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    frame.emptyText = emptyText

    local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", 20, 18)
    foot:SetWidth(380)
    foot:SetJustifyH("LEFT")
    foot:SetText("|cFF888888Tabs appear for each class that has tools built for it. "
        .. "Your own class is selected when the panel opens.|r")

    frame:SetScript("OnShow", function()
        selectedClass = selectedClass or ClassTools:GetPlayerClass()
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
