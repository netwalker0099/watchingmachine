-- BuffCheck + shared consumable names harness. Usage: lua5.1 test_buffcheck.lua <repo>
local REPO = assert(arg[1], "repo path")

-- Universal stub: any field/call returns another stub (frames, fonts, ...)
local stub
local stubmt = {}
stubmt.__index = function() return stub end
stubmt.__call = function() return stub end
stub = setmetatable({}, stubmt)

local auras = {}          -- unit -> { aura names }
local units = {}          -- unit -> { name=, class= }
local inRaid, raidSize = false, 0
local printed = {}

local env = {}
local G = setmetatable(env, { __index = function(_, k)
    local v = _G[k]; if v ~= nil then return v end
    if type(k) == "string" and k:find("DB$") then return nil end  -- SavedVariables start nil
    return stub
end })
env._G = env
env.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end printed[#printed+1] = table.concat(t, " ") end
env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed+1] = m end }
env.CreateFrame = function() return stub end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.date = os.date
env.UnitBuff = function(u, i) local l = auras[u]; return l and l[i] end
env.UnitExists = function(u) return units[u] ~= nil end
env.UnitName = function(u) return units[u] and units[u].name end
env.UnitClass = function(u) local c = units[u] and units[u].class; return c, c end
env.UnitIsConnected = function() return true end
env.UnitIsDeadOrGhost = function() return false end
env.IsInRaid = function() return inRaid end
env.IsInGroup = function() return inRaid end
env.GetNumGroupMembers = function() return raidSize end
env.IsInInstance = function() return true, "raid" end
env.GetInstanceInfo = function() return nil, nil, nil, nil, 25 end
env.GetWeaponEnchantInfo = function() return true, 0, 0, true end
env.GetInventoryItemLink = function() return nil end
env.SendChatMessage = function(m) printed[#printed+1] = "CHAT:" .. m end

local WM = {}
local function load(rel)
    local f = assert(loadfile(REPO .. "/" .. rel))
    setfenv(f, G)
    f("WatchingMachine", WM)
end
load("Core.lua")
load("Modules/BuffCheck.lua")
load("Modules/ClassTools.lua")
load("Modules/ClassGeneral.lua")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function has(pattern)
    for _, l in ipairs(printed) do if l:find(pattern, 1, true) then return true end end
    return false
end

-- ---- shared helpers ----
check("Well Fed is food", WM:IsFoodBuff("Well Fed"))
check("Enlightened (Skullfish Soup) is food", WM:IsFoodBuff("Enlightened"))
check("Food (eating channel) is not a food buff", not WM:IsFoodBuff("Food"))
check("Drink is not a food buff", not WM:IsFoodBuff("Drink"))
check("nil is not food", not WM:IsFoodBuff(nil))
check("Flask of Relentless Assault is a flask", WM:IsFlaskBuff("Flask of Relentless Assault"))
check("Unstable Flask of the Sorcerer is a flask", WM:IsFlaskBuff("Unstable Flask of the Sorcerer"))
check("Enlightened is not a flask", not WM:IsFlaskBuff("Enlightened"))

-- ---- BuffCheck ready-check scan ----
local BC = WM.modules.BuffCheck
_G.BuffCheckDB = nil
env.BuffCheckDB = nil
BC:InitDB()
local DB = env.BuffCheckDB
check("food check on by default", DB.checkedGroups.wellfed == true)

-- Upgrade: settings saved before the default changed hold wellfed=false.
-- They're switched on once; a later choice to turn it off sticks.
env.BuffCheckDB = { enabled = true, checkedGroups = { wellfed = false, fortitude = true } }
BC:InitDB()
check("upgrade turns food check on", env.BuffCheckDB.checkedGroups.wellfed == true)
check("upgrade keeps other choices", env.BuffCheckDB.checkedGroups.fortitude == true)
env.BuffCheckDB.checkedGroups.wellfed = false
BC:InitDB()
check("turning it off afterwards sticks", env.BuffCheckDB.checkedGroups.wellfed == false)
env.BuffCheckDB = nil
BC:InitDB()
DB = env.BuffCheckDB

-- Only consumables on, so class providers don't matter
for k in pairs(DB.checkedGroups) do DB.checkedGroups[k] = false end
DB.checkedGroups.wellfed = true

inRaid, raidSize = true, 4
units = {
    raid1 = { name = "Souper",  class = "PRIEST" },
    raid2 = { name = "Steaker", class = "WARRIOR" },
    raid3 = { name = "Hungry",  class = "MAGE" },
    raid4 = { name = "Eater",   class = "ROGUE" },
}
auras = {
    raid1 = { "Power Word: Fortitude", "Enlightened" },
    raid2 = { "Well Fed" },
    raid3 = { "Arcane Intellect" },
    raid4 = { "Food" },   -- still eating, no buff yet
}
local lines, missing = BC:ScanGroup()
check("two players missing food", missing == 2)
check("one report line", #lines == 1)
local l = lines[1] or ""
check("line names the check", l:find("Missing Food Buff:", 1, true) ~= nil)
check("Enlightened satisfies the check", not l:find("Souper", 1, true))
check("Well Fed satisfies the check", not l:find("Steaker", 1, true))
check("unfed mage reported", l:find("Hungry", 1, true) ~= nil)
check("mid-eating rogue reported", l:find("Eater", 1, true) ~= nil)

-- Check off -> nothing reported
DB.checkedGroups.wellfed = false
lines, missing = BC:ScanGroup()
check("food check off reports nothing", missing == 0 and #lines == 0)

-- Flask groups use the shared substring list
DB.checkedGroups.flask = true
auras.raid1 = { "Unstable Flask of the Sorcerer" }
auras.raid2 = { "Flask of Relentless Assault" }
auras.raid3 = { "Elixir of Major Firepower" }
auras.raid4 = {}
lines, missing = BC:ScanGroup()
check("flask: two missing", missing == 2)
DB.checkedGroups.flask = false
DB.checkedGroups.battleelixir = true
lines, missing = BC:ScanGroup()
check("battle elixir: flask counts, elixir counts, only raid4 missing", missing == 1 and lines[1]:find("Eater", 1, true))
DB.checkedGroups.battleelixir = false

-- Explain labels Enlightened as matched
DB.checkedGroups.wellfed = true
units.player = { name = "Me", class = "MAGE" }
auras.player = { "Enlightened" }
printed = {}
BC:ExplainUnit("player")
check("explain matches Enlightened to Food Buff", has("Enlightened|r -> Food Buff [on, exact]"))

-- ---- ClassGeneral uses the same names ----
local Gen = WM.modules.ClassGeneral
env.GeneralChecksDB = nil
Gen:InitDB()
auras.player = { "Enlightened", "Flask of Supreme Power" }
printed = {}
Gen:Explain()
check("general: Enlightened counts as food", has("food buff: |cFF00FF00yes"))
check("general: flask detected", has("flask: |cFF00FF00yes"))
auras.player = { "Food" }
printed = {}
Gen:Explain()
check("general: eating without buff is no", has("food buff: |cFFFF4444no"))
check("general: no flask", has("flask: |cFFFF4444no"))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
