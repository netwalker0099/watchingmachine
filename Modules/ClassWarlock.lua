-- Watching Machine: Warlock Class Tools
-- Registers warlock features into ClassTools. Everything here no-ops unless
-- the player is a warlock and the individual feature is switched on.

local AddonName, WM = ...
local Warlock = {}
WM:RegisterModule("ClassWarlock", Warlock)

Warlock.version = "3.6"

local CLASS = "WARLOCK"

-- ============================================
-- SPELL / BUFF NAMES (TBC)
-- ============================================
-- Matched by NAME rather than spell ID: ranks each have their own ID, and a
-- name read back from GetSpellInfo is already localized.

-- Demonic Sacrifice grants a different 30-minute buff per demon sacrificed.
local SACRIFICE_BUFFS = {
    ["Burning Wish"]    = "Imp",         -- +15% Fire damage
    ["Fel Stamina"]     = "Voidwalker",  -- periodic health
    ["Touch of Shadow"] = "Succubus",    -- +15% Shadow damage
    ["Fel Energy"]      = "Felhunter",   -- periodic mana
}

local ARMOR_BUFFS = { "Fel Armor", "Demon Armor", "Demon Skin" }
local SOUL_LINK_BUFF = "Soul Link"
local SOULSTONE_BUFF = "Soulstone Resurrection"

-- Talent names, used to decide whether a check is even relevant to this spec
local TALENT_DEMONIC_SACRIFICE = "Demonic Sacrifice"
local TALENT_SOUL_LINK = "Soul Link"

local ICON_SAC   = "Interface\\Icons\\Spell_Shadow_PsychicScream"
local ICON_LINK  = "Interface\\Icons\\Spell_Shadow_GatherShadows"
local ICON_ARMOR = "Interface\\Icons\\Spell_Shadow_FelArmour"
local ICON_STONE = "Interface\\Icons\\Spell_Shadow_SoulGem"

-- ============================================
-- HELPERS
-- ============================================

local function IsPlayerWarlock()
    local _, c = UnitClass("player")
    return c == CLASS
end

-- Does the player have this buff? Returns name, expirationTime
local function PlayerBuff(name)
    for i = 1, 40 do
        local n, _, _, _, _, expires = UnitBuff("player", i)
        if not n then return nil end
        if n == name then return n, expires end
    end
    return nil
end

local function PlayerHasAnyBuff(list)
    for _, n in ipairs(list) do
        if PlayerBuff(n) then return n end
    end
    return nil
end

-- Points spent in a talent, found by name across all trees. Self-inspection
-- works reliably in TBC Classic (unlike inspecting other players).
local talentCache, talentCacheTime = {}, 0
local TALENT_CACHE_TTL = 5

local function TalentRank(wanted)
    local now = GetTime()
    if (now - talentCacheTime) < TALENT_CACHE_TTL and talentCache[wanted] ~= nil then
        return talentCache[wanted]
    end
    if (now - talentCacheTime) >= TALENT_CACHE_TTL then
        wipe(talentCache)
        talentCacheTime = now
    end

    local rank = 0
    local numTabs = 3
    local ok, n = pcall(GetNumTalentTabs)
    if ok and tonumber(n) then numTabs = tonumber(n) end

    for tab = 1, numTabs do
        local okN, count = pcall(GetNumTalents, tab)
        count = tonumber(count) or 0
        for i = 1, count do
            local okT, tname, _, _, _, currRank = pcall(GetTalentInfo, tab, i)
            if okT and tname == wanted then
                rank = tonumber(currRank) or 0
                break
            end
        end
        if rank > 0 then break end
    end

    talentCache[wanted] = rank
    return rank
end

-- A respec rewrites every rank at once, so the TTL alone would leave the
-- checks acting on the old build for up to five seconds. Drop the cache the
-- moment the client tells us talents moved.
function Warlock:InvalidateTalentCache()
    wipe(talentCache)
    talentCacheTime = 0
end

function Warlock:Print(msg)
    WM:ModulePrint("ClassWarlock", msg)
end

-- ============================================
-- SOULSTONE TRACKING
-- ============================================
-- Scans the raid for the Soulstone Resurrection buff, which is the only
-- reliable source: it carries a real expiration time and works regardless of
-- which warlock applied it or whether we saw the cast.

local soulstones = {}   -- name -> { expires = , class = }

local function GroupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, 4 do
            if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end
        end
    end
    return units
end

function Warlock:ScanSoulstones()
    wipe(soulstones)
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) then
            for i = 1, 40 do
                local n, _, _, _, _, expires = UnitBuff(unit, i)
                if not n then break end
                if n == SOULSTONE_BUFF then
                    local name = UnitName(unit)
                    local _, class = UnitClass(unit)
                    if name then
                        soulstones[name] = { expires = expires, class = class }
                    end
                    break
                end
            end
        end
    end
    return soulstones
end

local function FormatRemaining(expires)
    if not expires or expires <= 0 then return "unknown" end
    local left = expires - GetTime()
    if left <= 0 then return "expired" end
    return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
end

-- /wmachine soulstone
function Warlock:ReportSoulstones()
    self:ScanSoulstones()
    local any = false
    self:Print("=== Soulstones in group ===")
    for name, info in pairs(soulstones) do
        any = true
        local hex = "ffffff"
        local c = info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
        if c then hex = string.format("%02x%02x%02x", c.r*255, c.g*255, c.b*255) end
        print("  |cFF" .. hex .. name .. "|r  " .. FormatRemaining(info.expires) .. " remaining")
    end
    if not any then
        print("  none found (only soulstones on people in range are visible)")
    end
end

-- ============================================
-- MONITOR
-- ============================================

local CT  -- resolved lazily: module load order isn't guaranteed

local function Tools()
    CT = CT or WM.modules.ClassTools
    return CT
end

local function Monitor()
    local tools = Tools()
    if not tools or not WM:IsModuleOn("ClassWarlock") then return end
    if not IsPlayerWarlock() then return end

    -- Nothing to check while dead
    if UnitIsDeadOrGhost("player") then
        tools:ClearAlert("wl_sac")
        tools:ClearAlert("wl_soullink")
        tools:ClearAlert("wl_armor")
        return
    end

    -- --- Armor spell ---
    if tools:IsEnabled(CLASS, "armor") then
        if PlayerHasAnyBuff(ARMOR_BUFFS) then
            tools:ClearAlert("wl_armor")
        else
            tools:SetAlert("wl_armor", "No Fel/Demon Armor", ICON_ARMOR)
        end
    else
        tools:ClearAlert("wl_armor")
    end

    -- --- Demonic Sacrifice ---
    -- Only meaningful if the talent is actually taken. If a demon is out,
    -- the player has chosen to keep the pet, so don't nag.
    local sacBuff = PlayerHasAnyBuff({ "Burning Wish", "Fel Stamina", "Touch of Shadow", "Fel Energy" })
    if tools:IsEnabled(CLASS, "sacrifice") and TalentRank(TALENT_DEMONIC_SACRIFICE) > 0 then
        if sacBuff or UnitExists("pet") then
            tools:ClearAlert("wl_sac")
        else
            tools:SetAlert("wl_sac", "Demonic Sacrifice buff missing", ICON_SAC)
        end
    else
        tools:ClearAlert("wl_sac")
    end

    -- --- Soul Link ---
    -- Needs a living pet, and is impossible while a sacrifice buff is up.
    if tools:IsEnabled(CLASS, "soullink") and TalentRank(TALENT_SOUL_LINK) > 0 then
        if sacBuff then
            tools:ClearAlert("wl_soullink")          -- sacrificed: no pet by design
        elseif not UnitExists("pet") or UnitIsDead("pet") then
            tools:ClearAlert("wl_soullink")          -- no pet to link to
        elseif PlayerBuff(SOUL_LINK_BUFF) then
            tools:ClearAlert("wl_soullink")
        else
            tools:SetAlert("wl_soullink", "Soul Link not active", ICON_LINK)
        end
    else
        tools:ClearAlert("wl_soullink")
    end
end

-- ============================================
-- WARLOCK BUTTON (shared engine: Modules/ClassFlyout.lua)
-- ============================================
-- One button, three groups, each nearest-first and with its own direction:
-- demons, armors, and stones & rituals. Icons for spells that use a Soul
-- Shard show your shard count.

local SOUL_SHARD = 6265

local function ShardBadge()
    return tostring(WM.ItemCount(SOUL_SHARD))
end

local WARLOCK_SPELLS = {
    -- Felguard only appears if you have the talent (you won't know it otherwise)
    demons = {
        { "Summon Felguard",   30146, badge = ShardBadge },
        { "Summon Succubus",   712,   badge = ShardBadge },
        { "Summon Imp",        688 },                       -- the one summon without a shard
        { "Summon Felhunter",  691,   badge = ShardBadge },
        { "Summon Voidwalker", 697,   badge = ShardBadge },
    },
    armor = {
        { "Fel Armor",   28176 },
        { "Demon Armor", 706 },
        { "Demon Skin",  687 },
    },
    stones = {
        { "Ritual of Souls",     29893, badge = ShardBadge },   -- the Soulwell
        { "Ritual of Summoning", 698,   badge = ShardBadge },
        -- Ranks are separate names: "Create Healthstone (Major)" etc.
        { "Create Healthstone",  6201,  badge = ShardBadge, prefix = true },
        { "Create Soulstone",    693,   badge = ShardBadge, prefix = true },
    },
}

local warlockSpells = { demons = {}, armor = {}, stones = {} }

function Warlock:ScanSpellbook()
    for _, list in pairs(warlockSpells) do wipe(list) end
    if not IsPlayerWarlock() then return end
    local found = WM.Flyout.ScanSpells(WARLOCK_SPELLS, ICON_ARMOR)
    for group, list in pairs(found) do
        for _, e in ipairs(list) do table.insert(warlockSpells[group], e) end
    end
end

function Warlock:GetFlyoutSpells(group)
    return warlockSpells[group]
end

local DIR_DEFAULTS = { demonDir = "LEFT", armorDir = "UP", stoneDir = "RIGHT" }

local function WarlockStore() return WarlockToolsDB end

local warlockFlyout = WM.Flyout.New({
    class = CLASS, feature = "warlockButton", module = "ClassWarlock",
    anchorName = "WM_WarlockAnchor", buttonPrefix = "WM_WarlockBtn",
    title = "Warlock", emptyText = "No demon, armor, stone or ritual spells known yet.",
    store = WarlockStore, posX = "buttonX", posY = "buttonY", defaultX = 240,
    defaults = DIR_DEFAULTS,
    scan = function() Warlock:ScanSpellbook() end,
    groups = function()
        return {
            { entries = warlockSpells.demons, dirKey = "demonDir" },
            { entries = warlockSpells.armor,  dirKey = "armorDir" },
            { entries = warlockSpells.stones, dirKey = "stoneDir" },
        }
    end,
    setIcon = function(icon) WM.Flyout.ClassCrest(icon, CLASS, ICON_ARMOR) end,
})
Warlock.flyout = warlockFlyout

function Warlock:UpdateButton() warlockFlyout:UpdateVisibility() end

function Warlock:InitDB()
    if not WarlockToolsDB then WarlockToolsDB = {} end
    for key, default in pairs(DIR_DEFAULTS) do
        if WarlockToolsDB[key] == nil then WarlockToolsDB[key] = default end
    end
end

-- ============================================
-- REGISTRATION
-- ============================================

local buttonEvents = CreateFrame("Frame")

-- The warlock tab's features, warning sounds and monitor. Only registers
-- (no frames, no events), so the guided setup can list them before this
-- has started; runs once.
function Warlock:RegisterFeatures()
    self:InitDB()
    local tools = Tools()
    if not tools or self.featuresRegistered then return end
    self.featuresRegistered = true

    tools:RegisterFeature(CLASS, {
        key = "armor", name = "Warn if armor spell is missing",
        desc = "Fel Armor, Demon Armor or Demon Skin.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "sacrifice", name = "Warn if Demonic Sacrifice buff is missing",
        desc = "Only when the talent is taken and no demon is out.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "soullink", name = "Warn if Soul Link is not cast",
        desc = "Only when talented, with a living pet and no sacrifice buff.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "soulstones", name = "Track soulstone timers",
        desc = "Soulstones on you and others in range. /wmachine soulstone",
        default = true,
    })

    local rebuild = function() Warlock:UpdateButton() end
    tools:RegisterFeature(CLASS, {
        key = "warlockButton", name = "Show the warlock button",
        desc = "A draggable warlock-crest icon that opens into your demons, armors, and stones & rituals (Soulwell, Ritual of Summoning, Healthstone, Soulstone), nearest first. Spells that use a Soul Shard show your shard count. Not available in combat.",
        default = true,
        onToggle = rebuild,
    })
    local function Dir(key, name, what)
        WM.Flyout.DirectionFeature(tools, CLASS, key, name, what, WarlockStore, DIR_DEFAULTS[key], rebuild)
    end
    Dir("demonDir", "Demons expand", "demon summon")
    Dir("armorDir", "Armors expand", "armor")
    Dir("stoneDir", "Stones & rituals expand", "Soulwell, summoning, Healthstone and Soulstone")

    tools:RegisterAlertSound(CLASS, "wl_armor", "Fel / Demon Armor missing")
    tools:RegisterAlertSound(CLASS, "wl_sac", "Demonic Sacrifice missing")
    tools:RegisterAlertSound(CLASS, "wl_soullink", "Soul Link not cast")
    tools:RegisterMonitor(Monitor)
end

function Warlock:Initialize()
    self:RegisterFeatures()
    if not Tools() then return end

    local talentWatcher = CreateFrame("Frame")
    -- CHARACTER_POINTS_CHANGED is the TBC talent event; PLAYER_TALENT_UPDATE
    -- may not exist on every Classic client, so register defensively
    WM:RegisterEvents(talentWatcher, { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED" })
    talentWatcher:SetScript("OnEvent", function()
        if WM:IsModuleOn("ClassWarlock") then Warlock:InvalidateTalentCache() end
    end)

    if IsPlayerWarlock() then
        warlockFlyout:CreateAnchor()
        -- SPELLS_CHANGED picks up a new spell or talent (Felguard)
        WM:RegisterEvents(buttonEvents, { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" })
        -- Spellbook isn't reliably populated the instant we initialise
        WM.RunAfter(2, function() Warlock:UpdateButton() end)
    end
end

buttonEvents:SetScript("OnEvent", function(_, event)
    if not IsPlayerWarlock() or not WM:IsModuleOn("ClassWarlock") then return end
    -- Secure children can't be touched mid-combat; rebuild once it drops
    if InCombatLockdown() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Warlock:UpdateButton()
    else
        WM.RunAfter(1, function() Warlock:UpdateButton() end)
    end
end)

-- Turned off on this character: warnings cleared and the button hidden
-- (in combat, once combat ends)
function Warlock:OnModuleOff()
    local tools = Tools()
    if tools then
        tools:ClearAlert("wl_armor")
        tools:ClearAlert("wl_sac")
        tools:ClearAlert("wl_soullink")
    end
    warlockFlyout:UpdateVisibility()
end

-- Back on: the button comes back if it's wanted
function Warlock:OnModuleOn()
    warlockFlyout:UpdateVisibility()
end

function Warlock:GetSoulstones()
    return soulstones
end
