-- Watching Machine: Damage Meter
-- Reads the combat log and counts, for you and your group, the damage and
-- healing done, damage taken, friendly fire, interrupts, dispels and
-- deaths, fight by fight. Each fight is a segment; the meter keeps the
-- current fight, the last few fights and an overall total. Threat is read
-- live from the game. Any number of bar windows can be open, each showing
-- its own display and segment (DamageMeterUI.lua draws them).
--
-- How a damage meter should count on the TBC combat log (what starts and
-- ends a fight, pets credited to their owners, active time, the death
-- log) was compiled with the help of Details! Damage Meter's research;
-- the code is our own.

local AddonName, WM = ...
local DM = {}
WM:RegisterModule("DamageMeter", DM)
WM.DamageMeter = DM

DM.version = "3.82"

local DEFAULTS = {
    hideOutOfCombat = false,  -- windows show only during a fight
    locked = false,           -- windows can't be moved or resized
    keepSegments = 12,        -- past fights kept
    freshInInstance = true,   -- clear the fights when you enter a new dungeon or raid
    barHeight = 16,
    showRank = true,          -- "1." before each name
    classIcons = true,        -- class icon at the start of each bar
    reportLines = 5,          -- lines sent by Report
    mergePets = true,         -- pets' damage counts for their owner
    onlyGroup = true,         -- count only you and your group
    timeMode = "effective",   -- DPS over the whole fight ("effective") or each player's active time ("activity")
}
DM.DEFAULTS = DEFAULTS

local MAX_WINDOWS = 8
DM.MAX_WINDOWS = MAX_WINDOWS

local function DB()
    WMDamageMeterDB = WMDamageMeterDB or {}
    local db = WMDamageMeterDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.windows) ~= "table" then
        db.windows = { { display = "damage", segment = "current" } }
    end
    if type(db.history) ~= "table" then db.history = {} end
    return db
end
DM.DB = DB

-- ============================================
-- HELPERS
-- ============================================

local function Now() return (GetTime and tonumber(GetTime())) or 0 end
local function Stamp() return (GetServerTime and tonumber(GetServerTime())) or time() end

-- Combat log flags, without the bit library (pure arithmetic)
local function Has(flags, b) return type(flags) == "number" and flags % (b * 2) >= b end
local MINE, PARTY, RAID = 0x1, 0x2, 0x4
local HOSTILE = 0x40
local T_PLAYER, T_PET, T_GUARDIAN = 0x400, 0x1000, 0x2000
local function InGroup(flags) return type(flags) == "number" and flags % 8 >= 1 end
DM.Has, DM.InGroup = Has, InGroup

-- 1234 -> "1.2K", 123456 -> "123K", 1234567 -> "1.23M"
local function Short(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if a >= 1e5 then return string.format("%dK", math.floor(n / 1e3)) end
    if a >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end
DM.Short = Short

local function Commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(%-?),", "%1"))
end
DM.Commas = Commas

-- 75 -> "1:15"
local function Clock(s)
    s = math.max(0, math.floor((tonumber(s) or 0) + 0.5))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
DM.Clock = Clock

local function ShortName(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^([^%-]+)") or name
end
DM.ShortName = ShortName

-- ============================================
-- YOUR GROUP: units, pets and their owners
-- ============================================

local unitOf = {}     -- [guid] = unit token, for you and your group
local owners = {}     -- [pet or guardian guid] = { ownerGUID, ownerName }
DM.unitOf, DM.owners = unitOf, owners

local function Guid(unit)
    local g = UnitGUID and UnitGUID(unit)
    return type(g) == "string" and g or nil
end

local function GroupUnits()
    local out = { { "player", "pet" } }
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do out[#out + 1] = { "raid" .. i, "raidpet" .. i } end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do out[#out + 1] = { "party" .. i, "partypet" .. i } end
    end
    return out
end
DM.GroupUnits = GroupUnits

function DM:ScanGroup()
    for k in pairs(unitOf) do unitOf[k] = nil end
    for _, u in ipairs(GroupUnits()) do
        local g = Guid(u[1])
        if g then
            unitOf[g] = unitOf[g] or u[1]
            local pg = Guid(u[2])
            if pg then
                local name = UnitName and UnitName(u[1])
                owners[pg] = { g, type(name) == "string" and name or nil }
            end
        end
    end
end

-- The player a group pet or guardian belongs to, if we know
local function OwnerOf(guid, flags)
    local o = owners[guid]
    if o then return o[1], o[2] end
    if Has(flags, MINE) then
        local me = Guid("player")
        if me then return me, UnitName and UnitName("player") end
    end
end
DM.OwnerOf = OwnerOf

local function ClassOf(guid)
    if not guid then return nil end
    if GetPlayerInfoByGUID then
        local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
        if ok and type(class) == "string" then return class end
    end
    local unit = unitOf[guid]
    if unit and UnitClass then
        local _, class = UnitClass(unit)
        if type(class) == "string" then return class end
    end
end

-- ============================================
-- SEGMENTS
-- ============================================
-- A segment: { name, boss, zone, date, start, last, stop, time,
--   actors = { [guid] = actor }, enemies = { [name] = damage taken },
--   deaths = { death, ... } }
-- An actor: { n = name, c = class, dmg, heal, oh, tk, ff, int, disp, dth,
--   at = active seconds, sp = damage spells, hp = heal spells,
--   tf = damage taken from, is = spells interrupted, ds = auras dispelled }
-- A spell: { a = amount, h = hits, c = crits, m = biggest, o = overheal, id }

local fight              -- the segment being recorded (nil between fights)
local lastAct = {}       -- [segment][guid] = time of their last action (not saved)
DM.ACTIVE_GAP = 10       -- a pause longer than this isn't active time
DM.MIN_ACTIVE = 10       -- activity time is never counted as less than this
DM.SHORT_FIGHT = 5       -- fights shorter than this in a dungeon or raid aren't kept

local function NewSegment(name)
    return { name = name, date = Stamp(), start = Now(), last = Now(), actors = {}, enemies = {}, deaths = {},
        zone = (GetRealZoneText and type(GetRealZoneText()) == "string" and GetRealZoneText()) or nil }
end

function DM:Overall()
    local db = DB()
    if type(db.overall) ~= "table" then
        db.overall = NewSegment("Overall")
        db.overall.overall, db.overall.time = true, 0
    end
    return db.overall
end

function DM:History() return DB().history end
function DM:InFight() return fight ~= nil end
function DM:Fight() return fight end

-- Seconds a segment covers
function DM:Duration(seg)
    if not seg then return 0 end
    if seg.overall then return (seg.time or 0) + ((fight and fight.start) and (Now() - fight.start) or 0) end
    if seg.time then return seg.time end
    if seg == fight then return math.max(0, Now() - (seg.start or Now())) end
    return math.max(0, (seg.last or 0) - (seg.start or 0))
end

-- "current", "overall" or n (n fights ago, 1 = the latest)
function DM:Segment(which)
    if which == "overall" then return self:Overall() end
    local h = DB().history
    if which == "current" or which == nil then return h[1] end
    return h[tonumber(which) or 1]
end

-- A fight's name; one still going is named after the enemy hurt most so far
function DM:FightName(seg)
    if not seg then return nil end
    if seg == fight and not seg.boss then
        local best, most
        for name, amt in pairs(seg.enemies) do
            if not most or amt > most then best, most = name, amt end
        end
        return best or seg.name or "Fight"
    end
    return seg.name or "Fight"
end

function DM:SegmentName(which)
    if which == "overall" then return "Overall" end
    local seg = self:Segment(which)
    if not seg then return "No fights yet" end
    local n = self:FightName(seg)
    if which == "current" then return n end
    return "#" .. tostring(which) .. " " .. n
end

local function Actor(seg, guid, name)
    local a = seg.actors[guid]
    if a then return a end
    a = { n = ShortName(name), c = ClassOf(guid), dmg = 0, heal = 0, oh = 0, tk = 0, ff = 0, int = 0, disp = 0, dth = 0, at = 0 }
    seg.actors[guid] = a
    return a
end
DM.Actor = Actor

-- Active time: the time between an actor's actions, leaving out pauses
-- longer than ACTIVE_GAP
local function Touch(seg, guid, a, t)
    local la = lastAct[seg]
    if not la then la = {}; lastAct[seg] = la end
    local prev = la[guid]
    if prev and t - prev <= DM.ACTIVE_GAP then
        a.at = a.at + (t - prev)
    end
    la[guid] = t
end

local function Spell(list, key, id)
    local s = list[key]
    if not s then
        s = { a = 0, h = 0, c = 0, m = 0, id = id }
        list[key] = s
    end
    return s
end

local function Targets()
    if not fight then return nil end
    return fight, DM:Overall()
end

function DM:StartFight(name)
    if fight then return fight end
    local db = DB()
    fight = NewSegment(name or "Fight")
    table.insert(db.history, 1, fight)
    while #db.history > math.max(1, tonumber(db.keepSegments) or 12) do
        local old = table.remove(db.history)
        lastAct[old] = nil
    end
    lastAct[self:Overall()] = nil
    self.checkTimer = 0
    -- Windows looking at an older fight go back to the current one
    for _, w in ipairs(db.windows) do
        if type(w.segment) == "number" then w.segment = "current" end
    end
    self:Changed()
    if self.OnFightStart then self:OnFightStart() end
    return fight
end

-- The name a fight gets: the boss, or the enemy that took the most damage
local function NameFight(seg)
    if seg.boss then return end
    local best, most
    for name, amt in pairs(seg.enemies) do
        if not most or amt > most then best, most = name, amt end
    end
    seg.name = best or seg.name or "Fight"
end

local function HasData(seg)
    for _, a in pairs(seg.actors) do
        if a.dmg > 0 or a.heal > 0 or a.tk > 0 or a.dth > 0 or a.int > 0 or a.disp > 0 then return true end
    end
    return false
end

function DM:EndFight()
    if not fight then return end
    local seg = fight
    fight = nil
    seg.stop = Now()
    seg.time = math.max(0, (seg.last or seg.stop) - (seg.start or seg.stop))
    local tiny = seg.time < DM.SHORT_FIGHT and not seg.boss and IsInInstance and IsInInstance() == true
    if seg.time < 1 then seg.time = 1 end
    NameFight(seg)
    lastAct[seg] = nil
    local overall = self:Overall()
    lastAct[overall] = nil
    local db = DB()
    if tiny or not HasData(seg) then
        for i, s in ipairs(db.history) do
            if s == seg then table.remove(db.history, i) break end
        end
    else
        overall.time = (overall.time or 0) + seg.time
    end
    self:Changed()
    if self.OnFightEnd then self:OnFightEnd(seg) end
    return seg
end

-- Is anyone in your group still fighting?
function DM:GroupInCombat()
    if not UnitAffectingCombat then return false end
    for _, u in ipairs(GroupUnits()) do
        if UnitAffectingCombat(u[1]) == true or UnitAffectingCombat(u[2]) == true then return true end
    end
    return false
end

function DM:Reset()
    local db = DB()
    fight = nil
    db.history = {}
    db.overall = nil
    for k in pairs(lastAct) do lastAct[k] = nil end
    for _, w in ipairs(db.windows) do
        if type(w.segment) == "number" then w.segment = "current" end
    end
    self:Changed()
end

-- ============================================
-- DEATH LOG
-- ============================================
-- The last events on each group member, so a death can show what killed
-- them: DEATH_EVENTS at most, from the last DEATH_SECONDS.

local DEATH_EVENTS, DEATH_SECONDS = 32, 10
DM.DEATH_EVENTS, DM.DEATH_SECONDS = DEATH_EVENTS, DEATH_SECONDS
local recent = {}         -- [guid] = { event, ... } oldest first

local function HealthPct(guid)
    local unit = unitOf[guid]
    if not unit or not UnitHealth or not UnitHealthMax then return nil end
    local hp, max = UnitHealth(unit), UnitHealthMax(unit)
    if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    return math.floor(hp / max * 100 + 0.5)
end

local function Remember(guid, e)
    local list = recent[guid]
    if not list then list = {}; recent[guid] = list end
    e.t = Now()
    e.hp = HealthPct(guid)
    list[#list + 1] = e
    if #list > DEATH_EVENTS then table.remove(list, 1) end
end
DM.recent = recent

function DM:Died(guid, name)
    local seg, overall = Targets()
    if not seg then return end
    if UnitIsFeignDeath and unitOf[guid] and UnitIsFeignDeath(unitOf[guid]) == true then return end
    local t = Now()
    local log = {}
    for _, e in ipairs(recent[guid] or {}) do
        if t - e.t <= DEATH_SECONDS then
            log[#log + 1] = { ago = math.floor((t - e.t) * 10 + 0.5) / 10, spell = e.spell, src = e.src,
                amount = e.amount, heal = e.heal, crit = e.crit, hp = e.hp }
        end
    end
    recent[guid] = nil
    local killer
    for i = #log, 1, -1 do
        if not log[i].heal then killer = log[i] break end
    end
    local death = { n = ShortName(name), c = ClassOf(guid), at = math.max(0, t - (seg.start or t)), date = Stamp(),
        log = log, killer = killer and ((killer.spell or "?") .. (killer.src and (" (" .. killer.src .. ")") or "")) or nil }
    for _, s in ipairs({ seg, overall }) do
        local a = Actor(s, guid, name)
        a.dth = a.dth + 1
        s.deaths[#s.deaths + 1] = death
        while #s.deaths > 100 do table.remove(s.deaths, 1) end
    end
    seg.last = t
    self:Changed()
    return death
end

-- ============================================
-- READING THE COMBAT LOG
-- ============================================

-- Who gets the credit for a group unit's action: a player, or a pet's owner
-- (pet spells then show as "Spell (Pet)"). Nil for anyone outside the group.
local FRIENDLY = 0x10
local function Credit(guid, name, flags)
    if type(guid) ~= "string" or guid == "" then return nil end
    if Has(flags, T_PLAYER) then
        if unitOf[guid] or InGroup(flags) then return guid, name end
        -- Friendly players outside your group, if you asked for them
        if not DB().onlyGroup and Has(flags, FRIENDLY) then return guid, name end
        return nil
    end
    if owners[guid] or ((Has(flags, T_PET) or Has(flags, T_GUARDIAN)) and InGroup(flags)) then
        local og, on = OwnerOf(guid, flags)
        -- An unknown group pet isn't counted (we can't say whose it is)
        if not og then return nil end
        if not DB().mergePets then return guid, name end
        return og, on, ShortName(name)
    end
end
DM.Credit = Credit

local function InInstance()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    return inside == true or inside == 1
end
DM.InInstance = InInstance

-- Heals the game credits to the wrong player: Earth Shield's heal (379)
-- and Prayer of Mending's (33110) belong to whoever cast the buff
local HEAL_FROM_BUFF = { [379] = "es", [33110] = "pom" }
local BUFF_KIND = { [974] = "es", [32593] = "es", [32594] = "es", [41635] = "pom" }
local IGNORED_SHIELDS = { [20711] = true }       -- Spirit of Redemption
DM.HEAL_FROM_BUFF, DM.BUFF_KIND = HEAL_FROM_BUFF, BUFF_KIND
local buffCaster = {}     -- [target guid .. kind] = { guid, name, flags }

local function IsGroupTarget(guid, flags)
    if unitOf[guid] then return true end
    return InGroup(flags) and Has(flags, T_PLAYER)
end

-- Damage counts what a shield soaked up too; overkill is left out in
-- dungeons and raids
local function Damage(srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spell, id, amount, overkill, crit, absorbed)
    amount = (tonumber(amount) or 0) + (tonumber(absorbed) or 0)
    overkill = tonumber(overkill) or 0
    if overkill > 0 and InInstance() then amount = amount - overkill end
    if amount <= 0 then return end
    local t = Now()
    local cg, cn, pet = Credit(srcGUID, srcName, srcFlags)
    local friendly = cg and (IsGroupTarget(dstGUID, dstFlags) or (Has(dstFlags, T_PET) and InGroup(dstFlags)))
    local victim = IsGroupTarget(dstGUID, dstFlags)
    -- A fight starts when your group hits, or is hit by, something hostile
    if not fight then
        if (cg and not friendly) or (victim and not cg and srcGUID ~= nil and srcGUID ~= "") then
            DM:StartFight()
        else
            return
        end
    end
    local seg, overall = Targets()
    local key = pet and ((spell or "Melee") .. " (" .. pet .. ")") or (spell or "Melee")
    for _, s in ipairs({ seg, overall }) do
        if cg then
            local a = Actor(s, cg, cn)
            if friendly then
                a.ff = a.ff + amount
            else
                a.dmg = a.dmg + amount
                a.sp = a.sp or {}
                local sp = Spell(a.sp, key, id)
                sp.a, sp.h = sp.a + amount, sp.h + 1
                if crit then sp.c = sp.c + 1 end
                if amount > sp.m then sp.m = amount end
                if type(dstName) == "string" then s.enemies[dstName] = (s.enemies[dstName] or 0) + amount end
            end
            Touch(s, cg, a, t)
        end
        if victim then
            local v = Actor(s, dstGUID, dstName)
            v.tk = v.tk + amount
            v.tf = v.tf or {}
            local from = (type(srcName) == "string" and ShortName(srcName)) or "Environment"
            local sp = Spell(v.tf, spell and (spell .. " (" .. from .. ")") or from, id)
            sp.a, sp.h = sp.a + amount, sp.h + 1
            if crit then sp.c = sp.c + 1 end
            if amount > sp.m then sp.m = amount end
        end
    end
    if victim then
        Remember(dstGUID, { spell = spell or "Melee", src = type(srcName) == "string" and ShortName(srcName) or nil,
            amount = amount, crit = crit and true or nil })
    end
    seg.last = t
    DM:Changed()
end
DM.Damage = Damage

-- Effective healing: the amount less overhealing, plus any part a heal
-- absorb soaked up. Heals never start a fight.
local function Heal(srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spell, id, amount, over, crit, absorbed)
    amount = tonumber(amount) or 0
    over = tonumber(over) or 0
    if not fight or amount <= 0 then return end
    local kind = HEAL_FROM_BUFF[tonumber(id) or 0]
    local by = kind and type(dstGUID) == "string" and buffCaster[dstGUID .. kind]
    if by then srcGUID, srcName, srcFlags = by[1], by[2], by[3] end
    local eff = math.max(0, amount - over + (tonumber(absorbed) or 0))
    local t = Now()
    local cg, cn, pet = Credit(srcGUID, srcName, srcFlags)
    local seg, overall = Targets()
    if cg then
        local key = pet and ((spell or "?") .. " (" .. pet .. ")") or (spell or "?")
        for _, s in ipairs({ seg, overall }) do
            local a = Actor(s, cg, cn)
            a.heal, a.oh = a.heal + eff, a.oh + over
            a.hp = a.hp or {}
            local sp = Spell(a.hp, key, id)
            sp.a, sp.h = sp.a + eff, sp.h + 1
            sp.o = (sp.o or 0) + over
            if crit then sp.c = sp.c + 1 end
            if eff > sp.m then sp.m = eff end
            Touch(s, cg, a, t)
        end
    end
    if IsGroupTarget(dstGUID, dstFlags) and eff > 0 then
        Remember(dstGUID, { spell = spell, src = type(srcName) == "string" and ShortName(srcName) or nil,
            amount = eff, heal = true, crit = crit and true or nil })
    end
    seg.last = t
    DM:Changed()
end
DM.Heal = Heal

local function Count(field, listField, srcGUID, srcName, srcFlags, what)
    if not fight then return end
    local cg, cn = Credit(srcGUID, srcName, srcFlags)
    if not cg then return end
    local seg, overall = Targets()
    for _, s in ipairs({ seg, overall }) do
        local a = Actor(s, cg, cn)
        a[field] = a[field] + 1
        if what then
            a[listField] = a[listField] or {}
            a[listField][what] = (a[listField][what] or 0) + 1
        end
    end
    seg.last = Now()
    DM:Changed()
end

-- A shield (Power Word: Shield, Ice Barrier, ...) soaking up damage counts
-- as healing by whoever cast it
local function Absorbed(casterGUID, casterName, casterFlags, dstGUID, dstName, dstFlags, spell, id, amount)
    if IGNORED_SHIELDS[tonumber(id) or 0] then return end
    return Heal(casterGUID, casterName, casterFlags, dstGUID, dstName, dstFlags, spell, id, amount, 0, false)
end

-- One combat log event (CombatLogGetCurrentEventInfo's values)
function DM:OnCombatEvent(...)
    local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _,
        a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22 = ...
    if type(sub) ~= "string" then return end
    if sub == "SWING_DAMAGE" then
        return Damage(srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, "Melee", 6603, a12, a13, a18, a17)
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE"
        or sub == "DAMAGE_SHIELD" or sub == "DAMAGE_SPLIT" or sub == "SPELL_BUILDING_DAMAGE" then
        return Damage(srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, a13, a12, a15, a16, a21, a20)
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        local kind = type(a12) == "string" and (a12:sub(1, 1) .. a12:sub(2):lower()) or "Environment"
        return Damage(nil, nil, 0, dstGUID, dstName, dstFlags, kind, nil, a13, a14, a19, a18)
    elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        return Heal(srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, a13, a12, a15, a16, a18, a17)
    elseif sub == "SPELL_ABSORBED" then
        -- After a spell: its id, name, school, then the shield's caster;
        -- after a melee swing the caster comes first
        if type(a12) == "string" then
            return Absorbed(a12, a13, a14, dstGUID, dstName, dstFlags, a17, a16, a19)
        end
        return Absorbed(a15, a16, a17, dstGUID, dstName, dstFlags, a20, a19, a22)
    elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
        local kind = BUFF_KIND[tonumber(a12) or 0]
        if kind and type(dstGUID) == "string" then buffCaster[dstGUID .. kind] = { srcGUID, srcName, srcFlags } end
    elseif sub == "SPELL_INTERRUPT" then
        return Count("int", "is", srcGUID, srcName, srcFlags, type(a16) == "string" and a16 or nil)
    elseif sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
        return Count("disp", "ds", srcGUID, srcName, srcFlags, type(a16) == "string" and a16 or nil)
    elseif sub == "UNIT_DIED" then
        if fight and Has(dstFlags, T_PLAYER) and IsGroupTarget(dstGUID, dstFlags) then
            return self:Died(dstGUID, dstName)
        end
    elseif sub == "SPELL_SUMMON" then
        -- A summon by a group player, or by their totem or pet (Fire
        -- Elemental Totem's elemental) belongs to that player
        if type(dstGUID) ~= "string" then return end
        local og, on = OwnerOf(srcGUID, srcFlags)
        if owners[srcGUID] then
            owners[dstGUID] = { og, on }
        elseif Has(srcFlags, T_PLAYER) and (unitOf[srcGUID] or InGroup(srcFlags)) then
            owners[dstGUID] = { srcGUID, srcName }
        end
    end
end

-- ============================================
-- DISPLAYS
-- ============================================
-- Each display turns a segment into sorted rows:
--   { key, name, value, text (right side), class, actor, guid }
-- Threat isn't kept in segments; it's read live from the game.

local function Pct(part, whole) return whole > 0 and (part / whole * 100) or 0 end

local function ActorRows(seg, field, rate)
    local rows, total = {}, 0
    if not seg then return rows, 0 end
    local dur = math.max(1, DM:Duration(seg))
    for guid, a in pairs(seg.actors) do
        local v = a[field] or 0
        if v > 0 then
            total = total + v
            rows[#rows + 1] = { name = a.n, class = a.c, actor = a, guid = guid, amount = v }
        end
    end
    local activity = DB().timeMode == "activity"
    for _, r in ipairs(rows) do
        local active = math.min(dur, math.max(DM.MIN_ACTIVE, r.actor.at or 0))
        r.rate = r.amount / (activity and active or dur)
        r.pct = Pct(r.amount, total)
        r.value = rate and r.rate or r.amount
    end
    table.sort(rows, function(x, y)
        if x.value ~= y.value then return x.value > y.value end
        return x.name < y.name
    end)
    return rows, total
end

local DISPLAYS = {
    { key = "damage", name = "Damage Done", short = "Damage", field = "dmg", spells = "sp",
        text = function(r) return Short(r.amount) .. " (" .. Short(r.rate) .. ", " .. string.format("%.1f%%", r.pct) .. ")" end },
    { key = "dps", name = "DPS", short = "DPS", field = "dmg", rate = true, spells = "sp",
        text = function(r) return Short(r.rate) .. " (" .. Short(r.amount) .. ")" end },
    { key = "heal", name = "Healing Done", short = "Healing", field = "heal", spells = "hp",
        text = function(r) return Short(r.amount) .. " (" .. Short(r.rate) .. ", " .. string.format("%.1f%%", r.pct) .. ")" end },
    { key = "hps", name = "HPS", short = "HPS", field = "heal", rate = true, spells = "hp",
        text = function(r) return Short(r.rate) .. " (" .. Short(r.amount) .. ")" end },
    { key = "overheal", name = "Overhealing", short = "Overheal", field = "oh", spells = "hp",
        text = function(r)
            local a = r.actor
            return Short(r.amount) .. " (" .. string.format("%.0f%%", Pct(a.oh, a.oh + a.heal)) .. ")"
        end },
    { key = "taken", name = "Damage Taken", short = "Taken", field = "tk", spells = "tf",
        text = function(r) return Short(r.amount) .. " (" .. string.format("%.1f%%", r.pct) .. ")" end },
    { key = "enemies", name = "Enemy Damage Taken", short = "Enemies",
        text = function(r) return Short(r.amount) .. " (" .. string.format("%.1f%%", r.pct) .. ")" end },
    { key = "ff", name = "Friendly Fire", short = "Friendly fire", field = "ff",
        text = function(r) return Short(r.amount) .. " (" .. string.format("%.1f%%", r.pct) .. ")" end },
    { key = "interrupts", name = "Interrupts", short = "Interrupts", field = "int", counts = "is",
        text = function(r) return tostring(r.amount) end },
    { key = "dispels", name = "Dispels", short = "Dispels", field = "disp", counts = "ds",
        text = function(r) return tostring(r.amount) end },
    { key = "deaths", name = "Deaths", short = "Deaths",
        text = function(r) return r.death and Clock(r.death.at) or "" end },
    { key = "threat", name = "Threat", short = "Threat", live = true,
        text = function(r) return Short(r.amount) .. " (" .. string.format("%.1f%%", r.pct) .. ")" end },
}
DM.DISPLAYS = DISPLAYS
local BY_KEY = {}
for _, d in ipairs(DISPLAYS) do BY_KEY[d.key] = d end
DM.BY_KEY = BY_KEY

function DM:Display(key) return BY_KEY[key] or BY_KEY.damage end

-- The rows for a display on a segment ("current", "overall" or n)
function DM:Rows(key, which)
    local d = self:Display(key)
    if d.key == "threat" then return self:ThreatRows() end
    local seg = self:Segment(which)
    if not seg then return {}, 0 end
    if d.key == "enemies" then
        local rows, total = {}, 0
        for name, amt in pairs(seg.enemies or {}) do
            total = total + amt
            rows[#rows + 1] = { name = name, amount = amt, value = amt }
        end
        for _, r in ipairs(rows) do r.pct = Pct(r.amount, total) end
        table.sort(rows, function(x, y) if x.value ~= y.value then return x.value > y.value end return x.name < y.name end)
        return rows, total
    elseif d.key == "deaths" then
        local rows = {}
        for i = #(seg.deaths or {}), 1, -1 do
            local e = seg.deaths[i]
            rows[#rows + 1] = { name = e.n, class = e.c, death = e, value = 1, amount = 1, pct = 100 }
        end
        return rows, #rows
    end
    return ActorRows(seg, d.field, d.rate)
end

-- The spells (or sources, or interrupted spells) behind one row, biggest first
function DM:Breakdown(key, row)
    local d = self:Display(key)
    local out, total = {}, 0
    local a = row and row.actor
    if not a then return out, 0 end
    if d.spells and a[d.spells] then
        for name, s in pairs(a[d.spells]) do
            local v = d.key == "overheal" and (s.o or 0) or s.a
            if v > 0 then
                total = total + v
                out[#out + 1] = { name = name, amount = v, hits = s.h, crits = s.c, max = s.m, over = s.o, id = s.id,
                    effective = s.a }
            end
        end
    elseif d.counts and a[d.counts] then
        for name, n in pairs(a[d.counts]) do
            total = total + n
            out[#out + 1] = { name = name, amount = n }
        end
    end
    for _, s in ipairs(out) do s.pct = Pct(s.amount, total) end
    table.sort(out, function(x, y) if x.amount ~= y.amount then return x.amount > y.amount end return x.name < y.name end)
    return out, total
end

-- ============================================
-- THREAT (live, from the game)
-- ============================================

-- The enemy threat is read against: your target, or your focus
function DM:ThreatUnit()
    for _, u in ipairs({ "target", "focus" }) do
        if UnitExists and UnitExists(u) == true and UnitCanAttack and UnitCanAttack("player", u) == true
            and not (UnitIsDead and UnitIsDead(u) == true) then
            return u
        end
    end
end

function DM:ThreatRows()
    local rows = {}
    local mob = self:ThreatUnit()
    if not mob or not UnitDetailedThreatSituation then return rows, 0 end
    local top = 0
    local seen = {}
    for _, u in ipairs(GroupUnits()) do
        for _, unit in ipairs(u) do
            local g = Guid(unit)
            if g and not seen[g] then
                seen[g] = true
                local tanking, _, scaled, _, value = UnitDetailedThreatSituation(unit, mob)
                value = tonumber(value)
                if value and value > 0 then
                    local name = UnitName and UnitName(unit)
                    local _, class = UnitClass(unit)
                    local r = { name = ShortName(name), class = type(class) == "string" and class or nil,
                        amount = value / 100, value = value, tanking = tanking and true or false,
                        scaled = tonumber(scaled) or 0, unit = unit, guid = g }
                    rows[#rows + 1] = r
                    if value > top then top = value end
                end
            end
        end
    end
    -- Percent of what pulls aggro (the game's scaled percent): the tank
    -- shows 100%, and anyone reaching 100% takes it
    for _, r in ipairs(rows) do r.pct = r.tanking and 100 or math.min(100, r.scaled) end
    table.sort(rows, function(x, y) if x.value ~= y.value then return x.value > y.value end return x.name < y.name end)
    return rows, top / 100
end

-- Threat bars run green to red as they near pulling aggro
function DM.ThreatColor(pct)
    local p = math.max(0, math.min(100, tonumber(pct) or 0)) / 100
    if p < 0.5 then return p * 2, 1, 0 end
    return 1, 1 - (p - 0.5) * 2, 0
end

-- ============================================
-- REPORT TO CHAT
-- ============================================

function DM:ReportLines(key, which, n)
    local d = self:Display(key)
    local rows = self:Rows(key, which)
    n = math.max(1, math.min(25, tonumber(n) or DB().reportLines or 5))
    local seg = d.live and nil or self:Segment(which)
    local head = "Damage Meter - " .. d.name
    if d.live then
        local mob = self:ThreatUnit()
        local mobName = mob and UnitName and UnitName(mob)
        head = head .. (type(mobName) == "string" and (" on " .. mobName) or "")
    else
        head = head .. ": " .. self:SegmentName(which) .. (seg and (" [" .. Clock(self:Duration(seg)) .. "]") or "")
    end
    local lines = { head }
    for i = 1, math.min(n, #rows) do
        local r = rows[i]
        lines[#lines + 1] = i .. ". " .. r.name .. "  " .. d.text(r):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    if #rows == 0 then lines[#lines + 1] = "(nothing yet)" end
    return lines
end

-- channel: SAY, PARTY, RAID, GUILD, OFFICER, or WHISPER with a target
function DM:Report(key, which, channel, target, n)
    if not WM:IsModuleOn("DamageMeter") then return false end
    channel = (channel or ""):upper()
    if channel == "" then
        channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or "SAY")
    end
    local lines = self:ReportLines(key, which, n)
    for _, l in ipairs(lines) do
        if channel == "SELF" then
            WM:ModulePrint("DamageMeter", l)
        else
            SendChatMessage(l, channel, nil, target)
        end
    end
    return true
end

-- ============================================
-- EVENTS
-- ============================================

local changed = false
function DM:Changed() changed = true end
function DM:TakeChanged() local c = changed; changed = false; return c end

-- Every second during a fight: has the whole group left combat?
DM.checkTimer = 0
function DM:CheckFightEnd(elapsed)
    if not fight then return end
    self.checkTimer = (self.checkTimer or 0) + (elapsed or 0)
    if self.checkTimer < 1 then return end
    self.checkTimer = 0
    if fight.boss then return end          -- a boss fight ends with the encounter
    if not self:GroupInCombat() then self:EndFight() end
end

function DM:OnEvent(event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if CombatLogGetCurrentEventInfo then return self:OnCombatEvent(CombatLogGetCurrentEventInfo()) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if fight and not fight.boss and not self:GroupInCombat() then self:EndFight() end
    elseif event == "ENCOUNTER_START" then
        local _, name = ...
        if fight and not fight.boss then self:EndFight() end
        local seg = self:StartFight(type(name) == "string" and name or nil)
        seg.boss = true
        if type(name) == "string" then seg.name = name end
    elseif event == "ENCOUNTER_END" then
        local _, name, _, _, success = ...
        if fight and fight.boss then
            fight.killed = success == 1 or success == true
            if type(name) == "string" then fight.name = name end
            self:EndFight()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
        self:ScanGroup()
        if event == "PLAYER_ENTERING_WORLD" then self:CheckInstance() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        self:CheckInstance()
    end
    if self.OnStateEvent then self:OnStateEvent(event) end
end

-- Entering a different dungeon or raid starts the fights afresh
function DM:CheckInstance()
    if not IsInInstance or not GetInstanceInfo then return end
    local inside, kind = IsInInstance()
    if inside ~= true or (kind ~= "party" and kind ~= "raid") then return end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    local key = tostring(id or name or "?")
    local db = DB()
    if db.lastInstance == key then return end
    local first = db.lastInstance == nil
    db.lastInstance = key
    if db.freshInInstance and not first and not fight and (#db.history > 0 or db.overall) then
        self:Reset()
        WM:ModulePrint("DamageMeter", "New instance (" .. tostring(name or "?") .. "): the fights start afresh.")
    end
end

-- ============================================
-- MODULE
-- ============================================

-- The settings, shared by the options window and the guided setup
function DM:SettingsControls(L)
    local function Redraw()
        if DM.ShowWindows and DM._wmStarted then DM:ShowWindows() end
    end
    L:Checkbox({ label = "Show the windows only during a fight", get = function() return DB().hideOutOfCombat end,
        set = function(v) DB().hideOutOfCombat = v; Redraw() end,
        tooltip = { "Only in combat", "The windows hide between fights and come back on the next pull." } })
    L:Checkbox({ label = "Lock the windows", get = function() return DB().locked end,
        set = function(v) DB().locked = v; if DM.ApplyLock and DM._wmStarted then DM:ApplyLock() end end,
        tooltip = { "Lock", "Locked windows can't be dragged or resized by accident. Their menus still work." } })
    L:Checkbox({ label = "Count pets and totems for their owner", get = function() return DB().mergePets end,
        set = function(v) DB().mergePets = v end,
        tooltip = { "Pets", "A hunter's pet, a warlock's demon, a shaman's totems and elementals add to their owner's"
            .. " bar; their spells show as \"Spell (Pet)\". Off: pets get bars of their own." } })
    L:Checkbox({ label = "Count only you and your group", get = function() return DB().onlyGroup end,
        set = function(v) DB().onlyGroup = v end,
        tooltip = { "Group only", "Off: other friendly players fighting near you are counted too." } })
    L:Checkbox({ label = "DPS over each player's active time", get = function() return DB().timeMode == "activity" end,
        set = function(v) DB().timeMode = v and "activity" or "effective" end,
        tooltip = { "Active time", "Off (the usual): DPS and HPS are over the whole fight, so a player who was dead"
            .. " or idle shows lower.", "On: over the time each player was actually acting (pauses of more than 10"
            .. " seconds left out)." } })
    L:Checkbox({ label = "Start afresh in a new dungeon or raid", get = function() return DB().freshInInstance end,
        set = function(v) DB().freshInInstance = v end,
        tooltip = { "New instance", "Entering a different dungeon or raid clears the old fights and the overall total." } })
    L:Checkbox({ label = "Rank numbers before the names", get = function() return DB().showRank end,
        set = function(v) DB().showRank = v; Redraw() end })
    L:Checkbox({ label = "Class icons on the bars", get = function() return DB().classIcons end,
        set = function(v) DB().classIcons = v; Redraw() end })
    L:Slider({ label = "Bar height", min = 12, max = 28, step = 1, get = function() return DB().barHeight end,
        set = function(v) DB().barHeight = v; Redraw() end,
        tooltip = { "Bar height", "How tall each player's bar is. A taller window shows more bars." } })
    L:Slider({ label = "Fights kept", min = 3, max = 30, step = 1, get = function() return DB().keepSegments end,
        set = function(v) DB().keepSegments = v end,
        tooltip = { "Fights kept", "How many past fights the fight menu offers. The overall total covers every fight." } })
    L:Slider({ label = "Lines in a report", min = 3, max = 15, step = 1, get = function() return DB().reportLines end,
        set = function(v) DB().reportLines = v end,
        tooltip = { "Report", "How many players a report to chat lists." } })
end

-- The module's page in the guided setup
function DM:SetupPage(L)
    DB()
    L:Note("Damage Meter reads the combat log and counts, for you and your group, the damage and healing done,"
        .. " damage taken, interrupts, dispels and deaths, fight by fight. Threat is read live from the game.")
    L:Note("|cFFFFFFFFWindows:|r each window is a list of bars, one per player, longest first. Click a window's"
        .. " title to choose what it shows: Damage Done, DPS, Healing Done, HPS, Overhealing, Damage Taken, Enemy"
        .. " Damage Taken, Friendly Fire, Interrupts, Dispels, Deaths or Threat. The + button opens another window,"
        .. " so you can watch damage and healing side by side.")
    L:Note("|cFFFFFFFFFights:|r a fight starts when your group hits something (or a boss pull starts) and ends when"
        .. " everyone is out of combat. Right-click the title for the current fight, the overall total, or an earlier"
        .. " fight. Boss fights are named after the boss.")
    L:Note("|cFFFFFFFFBars:|r hover over one for that player's top spells (a death shows its last 10 seconds)."
        .. " Click for the full breakdown, Shift-click to report the window to chat, right-click to change the display.")
    self:SettingsControls(L)
    L:Note("Show or hide the windows with |cFFFFFF00/wmachine meter|r; |cFFFFFF00/wmachine meter options|r for these"
        .. " settings later.")
end

function DM:GetQuickStatus()
    local seg = self:Segment("current")
    if not seg then return "No fights yet" end
    local rows = self:Rows("damage", "current")
    local me = UnitName and UnitName("player")
    for i, r in ipairs(rows) do
        if r.name == me then
            return string.format("%s: you #%d, %s DPS", self:FightName(seg), i, Short(r.rate))
        end
    end
    return self:FightName(seg) .. ", " .. #rows .. " in the meter"
end

-- /wmachine meter [new|reset|report [channel]|lock|unlock|options]
function DM:Command(arg)
    arg = strtrim(arg or "")
    local word, rest = arg:match("^(%S*)%s*(.-)$")
    word = (word or ""):lower()
    if word == "" or word == "show" or word == "toggle" then
        self:ToggleUI()
    elseif word == "new" or word == "window" then
        self:NewWindow()
    elseif word == "reset" then
        WM:Confirm("Clear every fight in the damage meter?", function() DM:Reset() end)
    elseif word == "report" then
        local w = DB().windows[1]
        self:Report(w and w.display or "damage", w and w.segment or "current", rest ~= "" and rest or nil)
    elseif word == "lock" or word == "unlock" then
        DB().locked = word == "lock"
        self:ApplyLock()
        WM:ModulePrint("DamageMeter", word == "lock" and "Windows locked." or "Windows unlocked: drag the title to move, the corner to resize.")
    elseif word == "options" or word == "config" or word == "opt" then
        self:ToggleOptions()
    else
        WM:ModulePrint("DamageMeter", "/wmachine meter: show or hide the windows. Also: meter new, reset, report [say|party|raid|guild], lock, unlock, options.")
    end
end

local events = CreateFrame("Frame")
DM.eventFrame = events

function DM:Initialize()
    DB()
    -- A fight cut short by a reload or log-out is closed where it stopped
    for _, seg in ipairs(DB().history) do
        if not seg.time then seg.time = math.max(1, (seg.last or 0) - (seg.start or 0)) end
    end
    WM:RegisterEvents(events, { "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_ENABLED",
        "ENCOUNTER_START", "ENCOUNTER_END", "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED" })
    self:ScanGroup()
    if self.CreateWindows then self:CreateWindows() end
    self:StartDriver()
end

events:SetScript("OnEvent", function(_, event, ...)
    if not WM:IsModuleOn("DamageMeter") then return end
    local ok, err = pcall(DM.OnEvent, DM, event, ...)
    if not ok then geterrorhandler()(err) end
end)

-- The driver: ends fights, and redraws the windows a few times a second
local driver = CreateFrame("Frame")
DM.driver = driver
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if not WM:IsModuleOn("DamageMeter") then return end
    DM:CheckFightEnd(elapsed)
    since = since + (elapsed or 0)
    if since < 0.3 then return end
    since = 0
    if DM.Tick then DM:Tick() end
end)
driver:Hide()

function DM:StartDriver() driver:Show() end

function DM:OnModuleOff()
    driver:Hide()
    if fight then self:EndFight() end
    if self.HideAllFrames then self:HideAllFrames() end
end

function DM:OnModuleOn()
    if not self._wmStarted then return end
    self:ScanGroup()
    driver:Show()
    if self.ShowWindows then self:ShowWindows() end
end
