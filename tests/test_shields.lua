-- Shaman: the Shields frame (your Water / Lightning Shield) and the Earth
-- Shield unit frame (who has it, their health, its charges).
-- Usage: lua5.1 test_shields.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 100
env.GetTime = function() return now end
env.UnitClass = function(u)
    if u == "player" then return "Shaman", "SHAMAN" end
    return "Warrior", "WARRIOR"
end
local NAMES = { [24398] = "Water Shield", [324] = "Lightning Shield", [974] = "Earth Shield" }
env.GetSpellInfo = function(id) return NAMES[id] end
local known = { [324] = true, [24398] = true }
env.IsPlayerSpell = function(id) return known[id] or false end
env.IsSpellKnown = false
-- buffs[unit] = { { name, icon, count, type, duration, expires, source }, ... }
local buffs = { player = {} }
env.UnitBuff = function(u, i)
    local b = buffs[u] and buffs[u][i]
    if b then return unpack(b) end
end
local group, inCombat = false, false
env.IsInGroup = function() return group end
env.IsInRaid = function() return false end
env.InCombatLockdown = function() return inCombat end
env.GetNumGroupMembers = function() return group and 2 or 0 end
local party = { party1 = { name = "Tankguy", guid = "G-Tank", hp = 6000, max = 12000 } }
env.UnitExists = function(u) return u == "player" or (group and party[u] ~= nil) end
env.UnitName = function(u) if u == "player" then return "Me" end return party[u] and party[u].name end
env.UnitGUID = function(u) if u == "player" then return "G-Me" end return party[u] and party[u].guid end
env.UnitHealth = function(u) return party[u] and party[u].hp or 0 end
env.UnitHealthMax = function(u) return party[u] and party[u].max or 0 end
env.UnitIsDeadOrGhost = function() return false end
env.UnitIsConnected = function() return true end
env.UnitIsVisible = function() return true end
env.UnitPowerType = function() return 1, "RAGE" end
env.UnitPower = function() return 50 end
env.UnitPowerMax = function() return 100 end
env.UnitIsUnit = function(a, b) return a == b end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua", "Modules/ClassShaman.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Sham = WM.modules.ClassTools, WM.modules.ClassShaman
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
Sham:RegisterFeatures()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Rows() return Sham:ShieldRows(now) end
local function Texts()
    local t = {}
    for _, r in ipairs(Rows()) do t[#t + 1] = (r.text or "") .. " | " .. (r.right or "") end
    return table.concat(t, "\n")
end

check("both options on by default", CT:IsEnabled("SHAMAN", "shieldTimer") and CT:IsEnabled("SHAMAN", "earthShield"))

-- ---- your own shield ----
check("solo, out of combat, no shield: nothing shown", #Rows() == 0)
inCombat = true
check("in combat without a shield: red line", Texts() == "No Water or Lightning Shield | "
    and Rows()[1].r == 1 and Rows()[1].g < 0.5)
buffs.player = { { "Water Shield", "wsicon", 3, nil, 600, now + 545 } }
check("Water Shield: charges and time left", Texts() == "Water Shield | 3  9:05" and Rows()[1].icon == "wsicon")
buffs.player = { { "Lightning Shield", "lsicon", 2, nil, 600, now + 42 } }
check("Lightning Shield: charges and seconds", Texts() == "Lightning Shield | 2  42s")
CT:SetEnabled("SHAMAN", "shieldTimer", false)
check("option off: no row", #Rows() == 0)
CT:SetEnabled("SHAMAN", "shieldTimer", true)
known[324], known[24398] = nil, nil
buffs.player = {}
check("no shield learned yet: no nagging", #Rows() == 0)
known[324] = true
inCombat = false

-- ---- Earth Shield: its own unit frame ----
local function ES() return Sham:EarthShieldState(now) end
check("Earth Shield not known: no frame", ES() == nil)
known[974] = true
check("known, solo: no frame", ES() == nil)
group = true
check("in a group, on nobody: says so", ES() and ES().none and ES().name == "No Earth Shield")
check("the Shields frame keeps to your own shield", Texts() == "No Water or Lightning Shield | ")
buffs.player = { { "Water Shield", "wsicon", 3, nil, 600, now + 600 } }

Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Me", "G-Tank", "Tankguy", "Earth Shield")
buffs.party1 = { { "Earth Shield", "esicon", 6, nil, 600, now + 600, "player" } }
local es = ES()
check("on the tank: unit, name, health and charges", es and es.unit == "party1" and es.token == "party1"
    and es.name == "Tankguy" and es.hp == 6000 and es.max == 12000 and es.charges == 6 and es.left == 600
    and es.class == "WARRIOR")
buffs.party1[1][3] = 4
party.party1.hp = 3000
es = ES()
check("charges and health follow the buff", es.charges == 4 and es.hp == 3000)
buffs.party1[1][7] = "party2"
check("someone else's Earth Shield on them: yours is gone", ES().none and Sham:EarthShieldTarget() == nil)
buffs.party1[1][7] = "player"
Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Me", "G-Tank", "Tankguy", "Earth Shield")
check("cast again: back on the tank", ES().name == "Tankguy" and not ES().none)

-- Out of range: faded
env.UnitInRange = function() return false, true end
check("out of range: far", ES().far)
env.UnitInRange = function() return true, true end
check("in range: not far", not ES().far)

-- Out of sight: the combat log's last word
group = false
Sham:OnCombatLog("SPELL_AURA_REMOVED_DOSE", "G-Me", "G-Tank", "Tankguy", "Earth Shield", 3)
es = ES()
check("out of sight: name, charges and time from the combat log", es and es.name == "Tankguy" and es.charges == 3
    and es.left == 600 and es.far and not es.unit)
group = true
Sham:OnCombatLog("SPELL_AURA_REMOVED", "G-Me", "G-Tank", "Tankguy", "Earth Shield")
buffs.party1 = {}
check("removed: on nobody again", ES().none)
Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Other", "G-Tank", "Tankguy", "Earth Shield")
check("another shaman's Earth Shield is ignored", Sham:EarthShieldTarget() == nil)

-- After a /reload: found by looking through the group
buffs.party1 = { { "Earth Shield", "esicon", 5, nil, 600, now + 300, "player" } }
now = now + 3
es = ES()
check("after a reload: found on the group", es and es.name == "Tankguy" and es.charges == 5 and es.left == 297)

-- ---- the frames ----
local f = Sham:CreateShieldFrame()
local u = Sham:CreateEarthShieldFrame()
check("the unit frame is a secure unit button that targets on click",
    u._template:find("SecureUnitButtonTemplate", 1, true) ~= nil)
local attrs = {}
u.SetAttribute = function(_, k, v) attrs[k] = v end
Sham:UpdateShields(now)
check("Shields frame: your own shield only", f:IsShown() and f.rows[1]:IsShown() and f.rows[1].text:GetText() == "Water Shield")
check("unit frame shown, on the tank", u:IsShown() and u:GetAlpha() == 1 and attrs.unit == "party1")
check("name and health on the bar", u.name:GetText() == "Tankguy" and u.hp:GetText() == "3.0k | 25%" and u.frac == 0.25)
check("charges and time on the aura", u.aura.count:GetText() == "5" and u.aura.time:GetText() == "4:57")
-- In combat it moves to someone else: drawn at once, clickable after combat
party.party2 = { name = "Offtank", guid = "G-Off", hp = 9000, max = 9000 }
inCombat = true
buffs.party1 = {}
buffs.party2 = { { "Earth Shield", "esicon", 6, nil, 600, now + 600, "player" } }
Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Me", "G-Off", "Offtank", "Earth Shield")
Sham:UpdateShields(now)
check("new target in combat: drawn, the click waits", u.name:GetText() == "Offtank" and attrs.unit == "party1")
inCombat = false
Sham:UpdateShields(now)
check("after combat: the click follows", attrs.unit == "party2")
-- Dead
env.UnitIsDeadOrGhost = function(un) return un == "party2" end
Sham:UpdateShields(now)
check("dead: says so, bar empty", u.hp:GetText() == "Dead" and u.frac == 0)
env.UnitIsDeadOrGhost = function() return false end
env.UnitIsConnected = function() return true end
env.UnitIsVisible = function() return true end
env.UnitPowerType = function() return 1, "RAGE" end
env.UnitPower = function() return 50 end
env.UnitPowerMax = function() return 100 end

WM:SetModuleOn("ClassShaman", false)
check("module off: both hidden", not f:IsShown() and not u:IsShown() and #Rows() == 0 and ES() == nil)
WM:SetModuleOn("ClassShaman", true)
check("module on: back", f:IsShown() and u:IsShown())
CT:SetEnabled("SHAMAN", "earthShield", false)
check("Earth Shield option off: unit frame hidden", not u:IsShown() and f:IsShown())
CT:SetEnabled("SHAMAN", "shieldTimer", false)
check("both options off: both hidden", not f:IsShown() and not u:IsShown())

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
