-- Watching Machine: Paladin Class Tools
-- Registers paladin features into ClassTools. Everything here no-ops unless
-- the player is a paladin and the individual feature is switched on.

local AddonName, WM = ...
local Paladin = {}
WM:RegisterModule("ClassPaladin", Paladin)

Paladin.version = "3.18"

local CLASS = "PALADIN"

local RIGHTEOUS_FURY = 25780
local ICON_FURY = "Interface\\Icons\\Spell_Holy_SealOfFury"

-- Talent-learned spells that mark a Protection paladin
local AVENGERS_SHIELD, HOLY_SHIELD = 31935, 20925
local PROT_TAB = 2

-- ============================================
-- HELPERS
-- ============================================

local function IsPlayerPaladin()
    local _, c = UnitClass("player")
    return c == CLASS
end

local function Knows(id)
    for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown }) do
        if type(fn) == "function" then
            local ok, v = pcall(fn, id)
            if ok and v then return true end
        end
    end
    return false
end

-- Matched by name (every rank) and by the client's name for the ID
local furyNames
local function FuryNames()
    if not furyNames then
        furyNames = { ["Righteous Fury"] = true }
        if GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, RIGHTEOUS_FURY)
            if ok and type(n) == "string" then furyNames[n] = true end
        end
    end
    return furyNames
end

local function HasFury()
    local names = FuryNames()
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if names[n] then return true end
    end
    return false
end

-- Points spent in a tree (sum of ranks; GetTalentInfo's 5th return)
local function TreePoints(tab)
    local okN, count = pcall(GetNumTalents, tab)
    count = okN and tonumber(count) or 0
    local points = 0
    for i = 1, count do
        local ok, _, _, _, _, rank = pcall(GetTalentInfo, tab, i)
        if ok then points = points + (tonumber(rank) or 0) end
    end
    return points
end

-- Cached: the monitor ticks often, and talents rarely change. Dropped on a
-- respec or a new spell.
local protCache, protCacheTime = nil, -100
local CACHE_TTL = 5

function Paladin:IsProtection()
    local now = GetTime()
    if protCache ~= nil and now - protCacheTime < CACHE_TTL then return protCache end
    local prot = Knows(AVENGERS_SHIELD) or Knows(HOLY_SHIELD)
    if not prot then
        local mine = TreePoints(PROT_TAB)
        prot = mine > 0 and mine > TreePoints(1) and mine > TreePoints(3)
    end
    protCache, protCacheTime = prot and true or false, now
    return protCache
end

function Paladin:InvalidateSpec()
    protCache, protCacheTime = nil, -100
end

-- ============================================
-- MONITOR
-- ============================================

local function Tools() return WM.modules.ClassTools end

local function Monitor()
    local tools = Tools()
    if not tools or not WM:IsModuleOn("ClassPaladin") then return end
    if not IsPlayerPaladin() then return end

    if UnitIsDeadOrGhost("player") or not tools:IsEnabled(CLASS, "fury")
        or not Knows(RIGHTEOUS_FURY) or not Paladin:IsProtection() then
        tools:ClearAlert("pal_fury")
        return
    end
    if HasFury() then
        tools:ClearAlert("pal_fury")
    else
        tools:SetAlert("pal_fury", "Righteous Fury is missing", ICON_FURY)
    end
end

-- ============================================
-- REGISTRATION
-- ============================================

-- The paladin tab's feature, warning sound and monitor. Only registers (no
-- frames, no events), so the guided setup can list them before this has
-- started; runs once.
function Paladin:RegisterFeatures()
    local tools = Tools()
    if not tools or self.featuresRegistered then return end
    self.featuresRegistered = true

    tools:RegisterFeature(CLASS, {
        key = "fury", name = "Warn if Righteous Fury is missing",
        desc = "Protection paladins only (most points in Protection, or Holy Shield / Avenger's Shield).",
        default = true,
    })
    tools:RegisterAlertSound(CLASS, "pal_fury", "Righteous Fury missing")
    tools:RegisterMonitor(Monitor)
end

function Paladin:Initialize()
    self:RegisterFeatures()
    if not Tools() then return end

    local watcher = CreateFrame("Frame")
    WM:RegisterEvents(watcher, { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED" })
    watcher:SetScript("OnEvent", function()
        if WM:IsModuleOn("ClassPaladin") then Paladin:InvalidateSpec() end
    end)
end

-- Turned off on this character: its warning goes
function Paladin:OnModuleOff()
    local tools = Tools()
    if tools then tools:ClearAlert("pal_fury") end
end
