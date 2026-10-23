-- Hazard Alerts: the data, which combat log lines sound and which don't,
-- tanks, heroics, environmental damage, friendly fire, the throttle,
-- options and the window.
-- Usage: lua5.1 test_hazards.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local clock = 1000
env.GetTime = function() return clock end
local ME = "Player-1-00000001"
env.UnitGUID = function(u) if u == "player" then return ME end end
local class, level, hpMax = "MAGE", 70, 10000
env.UnitClass = function() return class, class end
env.UnitLevel = function() return level end
env.UnitHealthMax = function() return hpMax end
env.UnitIsCharmed = function() return false end
local buffs, debuffs = {}, {}
env.UnitBuff = function(_, i) local id = buffs[i]; if id then return "b", nil, 0, nil, 0, 0, nil, nil, nil, id end end
env.UnitDebuff = function(_, i) local id = debuffs[i]; if id then return "d", nil, 0, nil, 0, 0, nil, nil, nil, id end end
env.GetPartyAssignment = function() return false end
env.UnitGroupRolesAssigned = function() return "NONE" end
local difficulty = 1
env.GetInstanceInfo = function() return "x", "party", difficulty end
env.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return unpack(out)
end
local played = {}
env.PlaySound = function(id, ch) played[#played + 1] = { id, ch } end
env.bit = { band = function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end }

for _, f in ipairs({ "Core.lua", "UI.lua", "Sounds.lua", "Data/Hazards.lua", "Modules/Hazards.lua" }) do W.load(f) end
local WM = W.WM
local HZ = WM.modules.Hazards
env.WatchingMachineDB = { theme = "Default" }
HZ:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local MOB = "Creature-0-1-530-1-17225-0000000001"
-- One combat log line hitting you
local function Hit(sub, spell, amount, src, extra1, extra2)
    clock = clock + 1
    local before = #played
    if sub == "ENVIRONMENTAL_DAMAGE" then
        HZ:OnCombatEvent(0, sub, false, "", "", 0, 0, ME, "Me", 0x511, 0, spell, amount)
    elseif sub:find("AURA") then
        HZ:OnCombatEvent(0, sub, false, src or MOB, "Mob", 0, 0, ME, "Me", 0x511, 0, spell, "Spell", 1, extra1 or "DEBUFF", extra2)
    else
        HZ:OnCombatEvent(0, sub, false, src or MOB, "Mob", 0, 0, ME, "Me", 0x511, 0, spell, "Spell", 1, amount)
    end
    return #played > before and played[#played][1] or nil
end

-- ---- The data ----
local D = WM.HazardData
local n, good = 0, true
for id, e in pairs(D.spells) do
    n = n + 1
    if type(id) ~= "number" or not (e.s >= 0 and e.s <= 4) then good = false end
end
check("data: hundreds of hazards, well formed", n > 200 and good)
check("data: TBC raids", D.spells[30533] and D.spells[30533].d:find("Netherspite", 1, true) and D.spells[28865])
check("data: friendly fire list", next(D.friendly) ~= nil)

-- ---- High and low damage ----
-- Void Zone (Netherspite): high damage, any hit
check("void zone: high damage sound", Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000) == 8959)
check("throttled: not twice at once", (function()
    local before = #played
    HZ:OnCombatEvent(0, "SPELL_PERIODIC_DAMAGE", false, MOB, "Mob", 0, 0, ME, "Me", 0, 0, 30533, "Void Zone", 32, 2000)
    return #played == before
end)())
check("a small tick (under 2%) stays quiet", Hit("SPELL_PERIODIC_DAMAGE", 30533, 100) == nil)
check("misses stay quiet", Hit("SPELL_MISSED", 30533, 0) == nil)
check("someone else's hit isn't yours", (function()
    clock = clock + 1
    local before = #played
    HZ:OnCombatEvent(0, "SPELL_DAMAGE", false, MOB, "Mob", 0, 0, "Player-1-2", "Other", 0, 0, 30533, "Void Zone", 32, 5000)
    return #played == before
end)())
check("unknown spells stay quiet", Hit("SPELL_DAMAGE", 1, 5000) == nil)
-- Charred Earth: damage only, not the debuff landing
check("damage-only: the hit sounds", Hit("SPELL_DAMAGE", 30129, 3000) == 8959)
check("damage-only: the debuff landing doesn't", Hit("SPELL_AURA_APPLIED", 30129) == nil)
-- An aura-only one
local auraID
for id, e in pairs(D.spells) do if e.aura and not e.stacks and not e.level and not e.mobs and not e.caster and not e.melee and not e.onlyDebuff then auraID = id; break end end
check("aura-only: the debuff landing sounds", Hit("SPELL_AURA_APPLIED", auraID) ~= nil)
check("aura-only: its damage doesn't", Hit("SPELL_DAMAGE", auraID, 5000) == nil)
check("buffs aren't hazards", Hit("SPELL_AURA_APPLIED", auraID, nil, nil, "BUFF") == nil)
-- Old content: trivial at your level
local oldID
for id, e in pairs(D.spells) do if e.level and e.level <= 70 and not e.aura and not e.mobs and not e.caster and not e.melee and not e.onlyDebuff and not e.unlessBuff and not e.unlessDebuff then oldID = id; break end end
check("old content stays quiet", Hit("SPELL_DAMAGE", oldID, 5000) == nil)
env.HazardsDB.oldContent = true
check("unless you ask for it", Hit("SPELL_DAMAGE", oldID, 5000) ~= nil)
env.HazardsDB.oldContent = false

-- ---- Tanks and heroics ----
local tankID
for id, e in pairs(D.spells) do if e.tank == 0 and not e.aura and not e.level and not e.mobs and not e.caster and not e.melee and not e.onlyDebuff and not e.unlessBuff then tankID = id; break end end
check("tank-only-silent hazard: sounds for others", Hit("SPELL_DAMAGE", tankID, 5000) ~= nil)
class = "PALADIN"
buffs = { 25780 }
check("Righteous Fury makes you a tank", WM.Hazards.IsTank())
check("tanks don't hear it", Hit("SPELL_DAMAGE", tankID, 5000) == nil)
buffs = {}
class = "WARRIOR"
buffs = { 71 }
check("Defensive Stance too", WM.Hazards.IsTank())
buffs = {}
class = "MAGE"
check("AlertFor: heroic version", (function()
    difficulty = 2
    local k = HZ.AlertFor({ s = 2, heroic = 1 })
    difficulty = 1
    return k == 1 and HZ.AlertFor({ s = 2, heroic = 1 }) == 2
end)())
-- Creature-specific
local mobID
for id, e in pairs(D.spells) do if e.mobs and #e.mobs == 1 and not e.aura and not e.level and not e.caster and not e.melee then mobID = id; break end end
local rightMob = "Creature-0-1-530-1-" .. D.spells[mobID].mobs[1] .. "-0000000001"
check("only from its creature", Hit("SPELL_DAMAGE", mobID, 5000) == nil and Hit("SPELL_DAMAGE", mobID, 5000, rightMob) ~= nil)

-- ---- Environment ----
check("lava: low damage", Hit("ENVIRONMENTAL_DAMAGE", "Lava", 1500) == 8960)
check("slime too", Hit("ENVIRONMENTAL_DAMAGE", "Slime", 1500) == 8960)
check("drowning: high", Hit("ENVIRONMENTAL_DAMAGE", "Drowning", 300) == 8959)
check("falling: nothing", Hit("ENVIRONMENTAL_DAMAGE", "Falling", 3000) == nil)
env.HazardsDB.lava = false
check("lava off", Hit("ENVIRONMENTAL_DAMAGE", "Lava", 1500) == nil)
env.HazardsDB.lava = true
clock = clock + 1
local before = #played
HZ:Alert(1, "Fatigue")
check("fatigue alert", #played == before + 1)

-- ---- Friendly fire ----
local ffID = next(D.friendly)
local ffE = D.friendly[ffID]
ffE.level = nil
clock = clock + 1
before = #played
HZ:OnCombatEvent(0, "SPELL_DAMAGE", false, ME, "Me", 0, 0, "Player-1-00000009", "Healz", 0x514, 0, ffID, "Spell", 1, 3000)
check("your spell hitting your group", #played == before + 1 and HZ.recent[1].label:find("on Healz", 1, true))
clock = clock + 1
before = #played
HZ:OnCombatEvent(0, "SPELL_DAMAGE", false, ME, "Me", 0, 0, "Player-1-00000010", "Stranger", 0x548, 0, ffID, "Spell", 1, 3000)
check("not someone outside your group", #played == before)

-- ---- Options ----
env.HazardsDB.sounds[1] = "kit:12867"
check("pick a sound per kind", Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000) == 12867)
env.HazardsDB.sounds[1] = "none"
check("none: silent", Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000) == nil and HZ.recent[1].spell == 30533)
env.HazardsDB.sounds[1] = "kit:8959"
HZ:Command("mute 30533")
check("mute a spell", env.HazardsDB.muted[30533] and Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000) == nil)
HZ:Command("unmute 30533")
check("unmute", Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000) == 8959)
HZ:SetModuleEnabled(false)
check("switched off", Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000) == nil and not HZ:IsModuleEnabled())
HZ:SetModuleEnabled(true)
check("channel", played[#played][2] == "Master")
local splash
env.RaidWarningFrame = {}
env.RaidNotice_AddMessage = function(_, text) splash = text end
env.HazardsDB.screenText = true
Hit("SPELL_PERIODIC_DAMAGE", 30533, 2000)
check("screen text", splash ~= nil)
env.HazardsDB.screenText = false

-- ---- Window ----
HZ:Toggle()
local p = env.WM_HazardsFrame
check("window", p:IsShown())
check("recent alerts", HZ:RecentLines()[1]:find("High damage", 1, true) ~= nil)
check("status", HZ:GetQuickStatus():find("alerts this session", 1, true) ~= nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
