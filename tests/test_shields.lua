-- Shaman: the Shields frame (your Water / Lightning Shield, and who has your
-- Earth Shield, their health and its charges).
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

-- ---- Earth Shield ----
check("Earth Shield not known: no Earth Shield row", #Rows() == 0)
known[974] = true
check("known, solo: nothing to say", #Rows() == 0)
group = true
check("in a group, on nobody: red line", Texts() == "No Water or Lightning Shield | \nEarth Shield isn't on anyone | ")
buffs.player = { { "Water Shield", "wsicon", 3, nil, 600, now + 600 } }

Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Me", "G-Tank", "Tankguy", "Earth Shield")
buffs.party1 = { { "Earth Shield", "esicon", 6, nil, 600, now + 600, "player" } }
local es = Rows()[2]
check("on the tank: name, health and charges", es and es.text == "Tankguy  50%" and es.right == "6  10:00")
check("health bar half full, class coloured", es.bar == 0.5 and es.r == 0.78)
buffs.party1[1][3] = 4
party.party1.hp = 3000
es = Rows()[2]
check("charges and health follow the buff", es.text == "Tankguy  25%" and es.right == "4  10:00")
buffs.party1[1][7] = "party2"
check("someone else's Earth Shield on them: yours is gone", Texts():find("Earth Shield isn't on anyone", 1, true) ~= nil
    and Sham:EarthShieldTarget() == nil)
buffs.party1[1][7] = "player"
buffs.party1[1][3] = 4
Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Me", "G-Tank", "Tankguy", "Earth Shield")
check("cast again: back on the tank", Rows()[2].text == "Tankguy  25%")

-- Out of sight: the combat log's last word
group = false
Sham:OnCombatLog("SPELL_AURA_REMOVED_DOSE", "G-Me", "G-Tank", "Tankguy", "Earth Shield", 3)
es = Rows()[2]
check("out of sight: name, charges and time from the combat log", es and es.text == "Tankguy" and es.right == "3  10:00")
group = true
Sham:OnCombatLog("SPELL_AURA_REMOVED", "G-Me", "G-Tank", "Tankguy", "Earth Shield")
buffs.party1 = {}
check("removed: on nobody again", Texts():find("Earth Shield isn't on anyone", 1, true) ~= nil)
Sham:OnCombatLog("SPELL_AURA_APPLIED", "G-Other", "G-Tank", "Tankguy", "Earth Shield")
check("another shaman's Earth Shield is ignored", Sham:EarthShieldTarget() == nil)

-- After a /reload: found by looking through the group
buffs.party1 = { { "Earth Shield", "esicon", 5, nil, 600, now + 300, "player" } }
now = now + 3
es = Rows()[2]
check("after a reload: found on the group", es and es.text == "Tankguy  25%" and es.right == "5  4:57")

-- ---- the frame ----
local f = Sham:CreateShieldFrame()
Sham:UpdateShields(now)
check("frame shows the rows", f:IsShown() and f.rows[1]:IsShown() and f.rows[2]:IsShown()
    and f.rows[2].text:GetText() == "Tankguy  25%")
WM:SetModuleOn("ClassShaman", false)
check("module off: frame hidden", not f:IsShown() and #Rows() == 0)
WM:SetModuleOn("ClassShaman", true)
check("module on: back", f:IsShown())
CT:SetEnabled("SHAMAN", "earthShield", false)
CT:SetEnabled("SHAMAN", "shieldTimer", false)
check("both options off: frame hidden", not f:IsShown())

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
