-- Watching Machine: Hazard Alerts
-- A sound the moment you're standing in something that hurts: void zones,
-- fire, poison clouds, cleaves, lava, drowning, fatigue. Four kinds of
-- alert, each with its own sound:
--   high damage   move now
--   low damage    you're taking damage you could avoid
--   fail          you just failed a mechanic
--   friendly fire your own spell is hurting your group
-- Known spells come from Data/Hazards.lua; lava, slime, fire and drowning
-- from the game's environmental damage. Tanks hear the tank version (some
-- hazards are a tank's job to stand in). Small hits (under 2% of your
-- health, by default) and old content stay quiet.

local AddonName, WM = ...
local HZ = {}
WM:RegisterModule("Hazards", HZ)
WM.Hazards = HZ

HZ.version = "3.43"

local KINDS = {
    { key = 1, name = "High damage", default = "kit:8959" },
    { key = 2, name = "Low damage", default = "kit:8960" },
    { key = 3, name = "Fail", default = "kit:12867" },
    { key = 4, name = "Friendly fire", default = "kit:8332" },
}
HZ.KINDS = KINDS

local DEFAULTS = {
    enabled = true,
    channel = "Master",
    trivialPct = 2,        -- quieter than this % of your health: no alert
    oldContent = false,    -- alert in content far below your level too
    screenText = false,    -- a warning in the middle of the screen as well
    drowning = true, fatigue = true, lava = true,
    gap = 0.2,             -- seconds between two alerts
}

local function DB()
    HazardsDB = HazardsDB or {}
    local db = HazardsDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.sounds) ~= "table" then db.sounds = {} end
    for _, k in ipairs(KINDS) do if db.sounds[k.key] == nil then db.sounds[k.key] = k.default end end
    if type(db.muted) ~= "table" then db.muted = {} end      -- [spell ID] = true
    return db
end
HZ.DB = DB

local function Data() return WM.HazardData or { spells = {}, friendly = {} } end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end

-- ============================================
-- WHO YOU ARE: tank? caster?
-- ============================================

local TANK_BUFFS = {
    PALADIN = { 25780 },          -- Righteous Fury
    DRUID = { 5487, 9634 },       -- Bear Form, Dire Bear Form
    WARRIOR = { 71 },             -- Defensive Stance
}
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true }
local MELEE = { WARRIOR = true, ROGUE = true }

local function HasAura(filterFn, ids)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, id = filterFn("player", i)
        if not name then return false end
        for _, want in ipairs(ids) do if id == want then return true end end
    end
    return false
end
local function HasBuff(id) return UnitBuff and HasAura(UnitBuff, { id }) end
local function HasDebuff(id) return UnitDebuff and HasAura(UnitDebuff, { id }) end

function HZ.IsTank()
    local _, class = UnitClass("player")
    if UnitBuff and TANK_BUFFS[class] and HasAura(UnitBuff, TANK_BUFFS[class]) then return true end
    if GetPartyAssignment then
        local ok, mt = pcall(GetPartyAssignment, "MAINTANK", "player")
        if ok and mt then return true end
    end
    if UnitGroupRolesAssigned then
        local ok, role = pcall(UnitGroupRolesAssigned, "player")
        if ok and role == "TANK" then return true end
    end
    return false
end

local function Heroic()
    if not GetInstanceInfo then return false end
    local ok, _, _, difficulty = pcall(GetInstanceInfo)
    return ok and (difficulty == 2 or difficulty == 174)
end

local function MobID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- ============================================
-- PLAYING ALERTS
-- ============================================

local lastAlert = -100
HZ.recent = {}             -- the last alerts, newest first

-- Play alert kind 1-4 (throttled). Returns true if it sounded.
function HZ:Alert(kind, label, spellID, damage)
    local db = DB()
    if not db.enabled or not kind or kind < 1 or kind > 4 then return false end
    local t = GetTime()
    if t - lastAlert < (db.gap or 0.2) then return false end
    lastAlert = t
    if WM.Sounds then WM.Sounds.Play(db.sounds[kind], db.channel) end
    if db.screenText and RaidNotice_AddMessage and RaidWarningFrame then
        local colors = { { r = 1, g = 0.2, b = 0.2 }, { r = 1, g = 0.7, b = 0.2 }, { r = 1, g = 0.2, b = 1 }, { r = 0.3, g = 0.8, b = 1 } }
        pcall(RaidNotice_AddMessage, RaidWarningFrame, (label or KINDS[kind].name), colors[kind])
    end
    table.insert(self.recent, 1, { kind = kind, label = label, spell = spellID, damage = damage, at = Now() })
    while #self.recent > 20 do table.remove(self.recent) end
    self:RefreshUI()
    return true
end

-- The alert an entry gives you now (nil: none)
function HZ.AlertFor(e)
    local heroic = Heroic()
    local tank = HZ.IsTank()
    local kind = e.s
    if heroic and e.heroic then kind = e.heroic end
    if tank then
        if heroic and e.tankHeroic then kind = e.tankHeroic
        elseif e.tank then kind = e.tank end
    end
    if kind == 0 then return nil end
    return kind
end

local function Trivial(e, damage)
    local db = DB()
    if not db.oldContent and e.level and e.level <= (UnitLevel("player") or 0) then return true end
    if damage and not e.always and not db.oldContent then
        local max = UnitHealthMax and tonumber(UnitHealthMax("player")) or 0
        if max > 0 then
            local need = (e.pct and e.pct > 0) and e.pct or db.trivialPct
            if damage * 100 / max < need then return true end
        end
    end
    return false
end
HZ.Trivial = Trivial

local AURA_EVENTS = { SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REFRESH = true }
local DAMAGE_EVENTS = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true }
local MISS_EVENTS = { SPELL_MISSED = true, SPELL_PERIODIC_MISSED = true }

-- Should this combat log line about a known spell hitting you sound?
function HZ:SpellAlert(e, sub, srcGUID, damage, auraType, stacks)
    local _, class = UnitClass("player")
    if e.caster and not CASTERS[class] then return nil end
    if e.melee and not MELEE[class] then return nil end
    local isAura = AURA_EVENTS[sub]
    if isAura and auraType ~= "DEBUFF" then return nil end
    if e.noPeriodic and (sub == "SPELL_PERIODIC_DAMAGE" or sub == "SPELL_PERIODIC_MISSED") then return nil end
    if e.unlessBuff and HasBuff(e.unlessBuff) then return nil end
    if e.unlessDebuff and HasDebuff(e.unlessDebuff) then return nil end
    if e.onlyDebuff and not HasDebuff(e.onlyDebuff) then return nil end
    if Trivial(e, DAMAGE_EVENTS[sub] and damage or nil) then return nil end
    if e.mobs then
        local id, found = MobID(srcGUID), false
        for _, m in ipairs(e.mobs) do if m == id then found = true end end
        if not found then return nil end
    end
    if MISS_EVENTS[sub] and not e.always then return nil end
    if e.aura then
        if not isAura then return nil end
        if e.stacks and (sub ~= "SPELL_AURA_APPLIED_DOSE" or (stacks or 0) <= e.stacks) then return nil end
    end
    if e.noAura and isAura then return nil end
    if e.notSelf and srcGUID == UnitGUID("player") then return nil end
    if e.min and (damage or 0) < e.min then return nil end
    return HZ.AlertFor(e)
end

local ENVIRONMENT = { DROWNING = "drowning", FATIGUE = "fatigue", LAVA = "lava", FIRE = "lava", SLIME = "lava" }

function HZ:OnCombatEvent(...)
    local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, dstFlags, _, a12, a13, a14, a15, a16 = ...
    local me = UnitGUID("player")
    if not me then return end
    if UnitIsCharmed and UnitIsCharmed("player") then return end
    if dstGUID == me then
        if sub == "ENVIRONMENTAL_DAMAGE" then
            local env, damage = tostring(a12 or ""):upper(), tonumber(a13) or 0
            local opt = ENVIRONMENT[env]
            if not opt or not DB()[opt] then return end
            local kind = (env == "DROWNING" or env == "FATIGUE") and 1 or 2
            if kind == 2 and Trivial({}, damage) then return end
            return self:Alert(kind, env:sub(1, 1) .. env:sub(2):lower(), nil, damage)
        end
        local spellID = tonumber(a12)
        local e = spellID and Data().spells[spellID]
        if not e or DB().muted[spellID] then return end
        if not (AURA_EVENTS[sub] or DAMAGE_EVENTS[sub] or MISS_EVENTS[sub] or sub == "SPELL_INSTAKILL") then return end
        local damage = DAMAGE_EVENTS[sub] and tonumber(a15) or nil
        local kind = self:SpellAlert(e, sub, srcGUID, damage, a15, a16)
        if kind then return self:Alert(kind, a13 or e.d, spellID, damage) end
    elseif srcGUID == me and sub == "SPELL_DAMAGE" then
        -- Your spell hit someone in your group
        local spellID = tonumber(a12)
        local e = spellID and Data().friendly[spellID]
        if not e or DB().muted[spellID] then return end
        local group = type(dstFlags) == "number" and bit and bit.band(dstFlags, 0x6) ~= 0
        if not group or not tostring(dstGUID):find("^Player") then return end
        if Trivial(e, nil) then return end
        local kind = HZ.AlertFor(e)
        if kind then return self:Alert(kind, (a13 or e.d) .. " on " .. tostring(dstName), spellID, tonumber(a15)) end
    end
end

-- ============================================
-- WINDOW
-- ============================================

local panel

function HZ:Count()
    local n = 0
    for _ in pairs(Data().spells) do n = n + 1 end
    return n
end

local function Ago(t)
    local s = math.max(0, Now() - (t or 0))
    if s < 60 then return s .. "s ago" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    return math.floor(s / 3600) .. "h ago"
end

function HZ:RecentLines()
    local lines = {}
    for _, r in ipairs(self.recent) do
        lines[#lines + 1] = string.format("%s  |cFFFFFFFF%s|r%s  |cFF888888%s|r", KINDS[r.kind].name, r.label or "?",
            r.damage and ("  " .. r.damage) or "", Ago(r.at))
    end
    return lines
end

function HZ:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({ name = "WM_HazardsFrame", title = "Hazard Alerts", titleColor = "FF6633", width = 460 })
    local L = panel.layout
    L:Note("A sound when you stand in something that hurts. " .. self:Count() .. " raid and dungeon hazards known, plus"
        .. " lava, slime, fire, drowning and fatigue.")
    L:Checkbox({ label = "Hazard alerts on", get = function() return DB().enabled end, set = function(v) DB().enabled = v end })
    for _, k in ipairs(KINDS) do
        L:Dropdown({
            label = k.name .. ":", width = 150,
            options = function() return WM.Sounds and WM.Sounds.OPTIONS or {} end,
            get = function() return DB().sounds[k.key] end,
            set = function(v) DB().sounds[k.key] = v; if WM.Sounds then WM.Sounds.Play(v, DB().channel) end end,
            tooltip = { k.name, ({ "You're in something that hits hard: move.", "You're taking damage you could avoid.",
                "You failed a mechanic (picked up a debuff you should have avoided).",
                "Your own spell is hurting someone in your group." })[k.key] .. " Picking a sound plays it." },
        })
    end
    L:Dropdown({ label = "Play on:", width = 150, options = function() return WM.Sounds and WM.Sounds.CHANNELS or {} end,
        get = function() return DB().channel end, set = function(v) DB().channel = v end })
    L:Checkbox({ label = "Also show a warning on screen", get = function() return DB().screenText end, set = function(v) DB().screenText = v end })
    L:Checkbox({ label = "Alert in low-level content too", get = function() return DB().oldContent end, set = function(v) DB().oldContent = v end,
        tooltip = { "Old content", "Off: hazards from content far below your level, and hits under 2% of your health, stay quiet." } })
    L:Checkbox({ label = "Drowning", get = function() return DB().drowning end, set = function(v) DB().drowning = v end })
    L:Checkbox({ label = "Fatigue (swimming too far out)", get = function() return DB().fatigue end, set = function(v) DB().fatigue = v end })
    L:Checkbox({ label = "Lava, slime and fire on the ground", get = function() return DB().lava end, set = function(v) DB().lava = v end })
    L:Buttons({
        { text = "Test high", width = 80, onClick = function() lastAlert = -100; HZ:Alert(1, "Test") end },
        { text = "Test low", width = 80, onClick = function() lastAlert = -100; HZ:Alert(2, "Test") end },
        { text = "Test fail", width = 80, onClick = function() lastAlert = -100; HZ:Alert(3, "Test") end },
        { text = "Test FF", width = 80, onClick = function() lastAlert = -100; HZ:Alert(4, "Test") end },
    })
    L:Section({ key = "recent", title = "Recent alerts" })
    local row = L:Row(20)
    local fs = WM.UI.Text(row.frame, { text = function()
        local lines = HZ:RecentLines()
        return #lines > 0 and table.concat(lines, "\n") or "|cFF888888None yet this session.|r"
    end, width = 420 })
    fs:SetPoint("TOPLEFT", 8, -2)
    L:Track(fs)
    row.measure = function() return math.max(20, math.floor((fs.GetStringHeight and fs:GetStringHeight() or 0) + 8)) end
    L:Note("Mute one that bothers you: /wmachine gtfo mute <spell ID> (the ID is in the spell's tooltip with most tooltip addons).")
    L:EndSection()
    panel:Finish()
    return panel
end

function HZ:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function HZ:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
HZ.ToggleUI = HZ.Toggle

function HZ:IsModuleEnabled() return DB().enabled end
function HZ:SetModuleEnabled(v) DB().enabled = v and true or false end

function HZ:GetQuickStatus()
    return (DB().enabled and "On" or "Off") .. ", " .. #self.recent .. " alerts this session"
end

-- /wmachine gtfo [mute|unmute <id> | test]
function HZ:Command(arg)
    arg = arg or ""
    local verb, id = arg:match("^(%a+)%s*(%d*)$")
    id = tonumber(id)
    if verb == "mute" and id then
        DB().muted[id] = true
        WM:ModulePrint("Hazards", "Muted spell " .. id .. ".")
    elseif verb == "unmute" and id then
        DB().muted[id] = nil
        WM:ModulePrint("Hazards", "Unmuted spell " .. id .. ".")
    elseif verb == "test" then
        lastAlert = -100
        self:Alert(1, "Test")
    else
        self:Toggle()
    end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

function HZ:Initialize()
    DB()
    WM:RegisterEvents(events, { "COMBAT_LOG_EVENT_UNFILTERED", "MIRROR_TIMER_START" })
end

events:SetScript("OnEvent", function(_, event, ...)
    local ok, err
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not DB().enabled or not CombatLogGetCurrentEventInfo then return end
        ok, err = pcall(HZ.OnCombatEvent, HZ, CombatLogGetCurrentEventInfo())
    elseif event == "MIRROR_TIMER_START" then
        -- The fatigue bar draining
        local kind, _, _, scale = ...
        if kind == "EXHAUSTION" and (tonumber(scale) or 0) < 0 and DB().fatigue then
            ok, err = pcall(HZ.Alert, HZ, 1, "Fatigue")
        end
    end
    if ok == false then geterrorhandler()(err) end
end)
