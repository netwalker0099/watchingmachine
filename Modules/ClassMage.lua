-- Watching Machine: Mage Class Tools
-- Armor-spell warning, and two hover-expanding buttons: one for every
-- teleport and portal the character knows, one for mana gems, armors and
-- food / water / table.

local AddonName, WM = ...
local Mage = {}
WM:RegisterModule("ClassMage", Mage)

Mage.version = "3.8"

local CLASS = "MAGE"

local ARMOR_BUFFS = { "Molten Armor", "Mage Armor", "Ice Armor", "Frost Armor" }
local ICON_ARMOR  = "Interface\\Icons\\Spell_MageArmor"
local ICON_PORTAL = "Interface\\Icons\\Spell_Arcane_PortalStormwind"

local function IsPlayerMage()
    local _, c = UnitClass("player")
    return c == CLASS
end

local function PlayerHasAnyBuff(list)
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return nil end
        for _, want in ipairs(list) do
            if n == want then return n end
        end
    end
    return nil
end

function Mage:Print(msg)
    WM:ModulePrint("ClassMage", msg)
end

-- ============================================
-- SPELL DISCOVERY (teleports, portals, utility spells)
-- ============================================
-- Read the spellbook rather than hardcoding a faction's spell list: the
-- character can only ever cast what it actually knows, and this stays correct
-- for either faction and for whatever the player has learned so far.
--
-- The "Teleport:" / "Portal:" prefixes are localized, so they are derived
-- from a known spell's own name where possible instead of assumed English.

local function LocalizedPrefix(spellID, fallback)
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" then
            local prefix = name:match("^([^:]+:)")
            if prefix then return prefix end
        end
    end
    return fallback
end

-- Utility spells, highest level first: that order is the order they fan out
-- from the button, so the best one sits closest. Matched by English name
-- and by the client's own name for the spell ID, so localized clients work.
-- Ranked spells (armors, food, water) show once, casting the highest rank.
local UTILITY_SPELLS = {
    gems = {
        { "Conjure Mana Emerald", 27101 },
        { "Conjure Mana Ruby",    10054 },
        { "Conjure Mana Citrine", 10053 },
        { "Conjure Mana Jade",    3552 },
        { "Conjure Mana Agate",   759 },
    },
    armor = {
        { "Molten Armor", 30482 },
        { "Mage Armor",   6117 },
        { "Ice Armor",    7302 },
        { "Frost Armor",  168 },
    },
    food = {
        { "Ritual of Refreshment", 43987 },
        { "Conjure Water",         5504 },
        { "Conjure Food",          587 },
    },
}

-- Each entry: { name = "Portal: Stormwind", index = spellbook slot, icon = texture }
local teleportSpells, portalSpells = {}, {}
local utilitySpells = { gems = {}, armor = {}, food = {} }

function Mage:ScanSpellbook()
    wipe(teleportSpells)
    wipe(portalSpells)
    for _, list in pairs(utilitySpells) do wipe(list) end
    if not IsPlayerMage() then return end
    if not GetSpellBookItemName then return end

    local telePrefix = LocalizedPrefix(3561, "Teleport:")   -- Teleport: Stormwind
    local portPrefix = LocalizedPrefix(10059, "Portal:")    -- Portal: Stormwind

    local i = 1
    while true do
        local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end
        local list
        if name:sub(1, #telePrefix) == telePrefix then
            list = teleportSpells
        elseif name:sub(1, #portPrefix) == portPrefix then
            list = portalSpells
        end
        if list then
            list[#list + 1] = { name = name, index = i, icon = WM.Flyout.SpellIcon(i, name, ICON_PORTAL) }
        end
        i = i + 1
        if i > 1024 then break end   -- guard against a malformed spellbook
    end

    local function byName(a, b) return a.name < b.name end
    table.sort(teleportSpells, byName)
    table.sort(portalSpells, byName)

    local found = WM.Flyout.ScanSpells(UTILITY_SPELLS, ICON_ARMOR)
    for group, list in pairs(found) do
        for _, e in ipairs(list) do table.insert(utilitySpells[group], e) end
    end
    return #teleportSpells, #portalSpells
end

function Mage:GetUtilitySpells(group)
    return utilitySpells[group]
end

-- ============================================
-- FLYOUT BUTTONS (shared engine: Modules/ClassFlyout.lua)
-- ============================================

-- Saved direction keys and their defaults
local DIR_DEFAULTS = {
    portalDir = "LEFT", teleportDir = "UP",
    gemDir = "LEFT", armorDir = "UP", foodDir = "RIGHT",
}

Mage.DIRECTION_OPTIONS = WM.Flyout.DIRECTION_OPTIONS
Mage.CastClicks = WM.Flyout.CastClicks     -- for tests
Mage.FlyoutOffset = WM.Flyout.Offset       -- for tests

local function MageStore() return MageToolsDB end

local portalFlyout = WM.Flyout.New({
    class = CLASS, feature = "portalButton",
    anchorName = "WM_MagePortalAnchor", buttonPrefix = "WM_MagePortalBtn",
    title = "Portals", emptyText = "No teleport or portal spells known yet.",
    store = MageStore, posX = "portalX", posY = "portalY", defaultX = 240,
    defaults = DIR_DEFAULTS,
    scan = function() Mage:ScanSpellbook() end,
    groups = function()
        return {
            { entries = portalSpells,   dirKey = "portalDir" },
            { entries = teleportSpells, dirKey = "teleportDir" },
        }
    end,
    -- Your first portal (or teleport) as the button's own icon
    setIcon = function(icon)
        local first = portalSpells[1] or teleportSpells[1]
        icon:SetTexture(first and first.icon or ICON_PORTAL)
    end,
})

local utilityFlyout = WM.Flyout.New({
    class = CLASS, feature = "utilityButton",
    anchorName = "WM_MageUtilityAnchor", buttonPrefix = "WM_MageUtilityBtn",
    title = "Mage utility", emptyText = "No mana gem, armor or conjure spells known yet.",
    store = MageStore, posX = "utilityX", posY = "utilityY", defaultX = 196,
    defaults = DIR_DEFAULTS,
    scan = function() Mage:ScanSpellbook() end,
    groups = function()
        return {
            { entries = utilitySpells.gems,  dirKey = "gemDir" },
            { entries = utilitySpells.armor, dirKey = "armorDir" },
            { entries = utilitySpells.food,  dirKey = "foodDir" },
        }
    end,
    setIcon = function(icon) WM.Flyout.ClassCrest(icon, CLASS, ICON_ARMOR) end,
})

Mage.portalFlyout, Mage.utilityFlyout = portalFlyout, utilityFlyout

-- Portal button entry points (kept by name; tests and older code use them)
function Mage:CreateAnchor()
    local a = portalFlyout:CreateAnchor()
    self.anchor = a
    return a
end
function Mage:BuildFlyout() portalFlyout:Build() end
function Mage:CancelFlyoutClose() portalFlyout:ShowButtons() end
function Mage:ScheduleFlyoutClose() portalFlyout:ScheduleClose() end
function Mage:UpdatePortalButtonVisibility() portalFlyout:UpdateVisibility() end

function Mage:CreateUtilityAnchor() return utilityFlyout:CreateAnchor() end
function Mage:BuildUtilityFlyout() utilityFlyout:Build() end
function Mage:UpdateUtilityButtonVisibility() utilityFlyout:UpdateVisibility() end

function Mage:UpdateButtons()
    portalFlyout:UpdateVisibility()
    utilityFlyout:UpdateVisibility()
end

-- ============================================
-- MONITOR
-- ============================================

local CT

local function Tools()
    CT = CT or WM.modules.ClassTools
    return CT
end

local function Monitor()
    local tools = Tools()
    if not tools then return end
    if not IsPlayerMage() then return end

    if UnitIsDeadOrGhost("player") then
        tools:ClearAlert("mage_armor")
        return
    end

    if tools:IsEnabled(CLASS, "armor") then
        if PlayerHasAnyBuff(ARMOR_BUFFS) then
            tools:ClearAlert("mage_armor")
        else
            tools:SetAlert("mage_armor", "No Mage Armor spell active", ICON_ARMOR)
        end
    else
        tools:ClearAlert("mage_armor")
    end
end

-- ============================================
-- REGISTRATION
-- ============================================

local eventFrame = CreateFrame("Frame")

function Mage:InitDB()
    if not MageToolsDB then MageToolsDB = {} end
    for key, default in pairs(DIR_DEFAULTS) do
        if MageToolsDB[key] == nil then MageToolsDB[key] = default end
    end
end

local function DirectionFeature(tools, key, name, what, rebuild)
    WM.Flyout.DirectionFeature(tools, CLASS, key, name, what, MageStore, DIR_DEFAULTS[key], rebuild)
end

function Mage:Initialize()
    self:InitDB()
    local tools = Tools()
    if not tools then return end

    local rebuildPortals = function() Mage:UpdatePortalButtonVisibility() end
    local rebuildUtility = function() Mage:UpdateUtilityButtonVisibility() end

    tools:RegisterFeature(CLASS, {
        key = "armor", name = "Warn if armor spell is missing",
        desc = "Molten, Mage, Ice or Frost Armor.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "portalButton", name = "Show the portal / teleport button",
        desc = "A draggable portal icon that opens into an icon for every portal and teleport you know (on hover or click: see General). Hover an icon for the spell; click to cast. Not available in combat.",
        default = true,
        onToggle = rebuildPortals,
    })
    DirectionFeature(tools, "portalDir", "Portals expand", "portal", rebuildPortals)
    DirectionFeature(tools, "teleportDir", "Teleports expand", "teleport", rebuildPortals)
    tools:RegisterFeature(CLASS, {
        key = "utilityButton", name = "Show the mage utility button",
        desc = "A draggable mage-crest icon that opens into your mana gems, armors, and food, water and table spells, highest level nearest the button. Click to cast. Not available in combat.",
        default = true,
        onToggle = rebuildUtility,
    })
    DirectionFeature(tools, "gemDir", "Mana gems expand", "mana gem", rebuildUtility)
    DirectionFeature(tools, "armorDir", "Armors expand", "armor", rebuildUtility)
    DirectionFeature(tools, "foodDir", "Food & water expand", "food, water and table", rebuildUtility)
    -- Locking, docking and open-on-click are shared by every class's
    -- flyouts: Class Tools > General

    tools:RegisterMonitor(Monitor)

    if IsPlayerMage() then
        self:CreateAnchor()
        self:CreateUtilityAnchor()
        -- SPELLS_CHANGED also fires when a spell is learned, which is what
        -- picks up a new spell; LEARNED_SPELL_IN_TAB doesn't exist on 2.5.6
        WM:RegisterEvents(eventFrame, { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" })
        -- Spellbook isn't reliably populated the instant we initialise
        WM.RunAfter(2, function() Mage:UpdateButtons() end)
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if not IsPlayerMage() then return end
    -- Secure children can't be touched mid-combat; rebuild once it drops
    if InCombatLockdown() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Mage:UpdateButtons()
    else
        WM.RunAfter(1, function() Mage:UpdateButtons() end)
    end
end)

function Mage:ReportSpells()
    local t, p = self:ScanSpellbook()
    self:Print("Known teleports: " .. (t or 0) .. ", portals: " .. (p or 0))
    for _, e in ipairs(portalSpells)   do print("  |cFF66CCFF" .. e.name .. "|r") end
    for _, e in ipairs(teleportSpells) do print("  |cFFCCCCCC" .. e.name .. "|r") end
    for _, group in ipairs({ "gems", "armor", "food" }) do
        for _, e in ipairs(utilitySpells[group]) do print("  |cFFFFCC66" .. e.name .. "|r") end
    end
end
