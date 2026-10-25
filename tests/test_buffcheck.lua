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
-- An aura is a name, or { name, spellId } to return the ID like the client
env.UnitBuff = function(u, i)
    local a = auras[u] and auras[u][i]
    if type(a) == "table" then return a[1], nil, nil, nil, nil, nil, nil, nil, nil, a[2] end
    return a
end
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
load("Profiles.lua")   -- the module switches (WM:IsModuleOn), loaded with Core in the addon
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
check("Shattrath Blinding Light is a flask (by name)", WM:IsFlaskBuff("Blinding Light"))
check("Shattrath Pure Death is a flask (by ID)", WM:IsFlaskBuff("Something Else", 46837))
check("Shattrath flask is a consumable flask", WM:ConsumableKind("Blinding Light", 46839) == "flask")

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

-- The group list: each member with what they're missing (and GearScore)
local rows = BC:GroupRows()
local byN = {}
for _, r in ipairs(rows) do byN[r.name] = r end
check("group list: everyone", #rows == 4)
check("group list: what each is missing", byN.Hungry.missing[1] == "Food Buff" and #byN.Hungry.missing == 1
    and #byN.Souper.missing == 0)
check("group list: most missing first, then by name", rows[1].name == "Eater" and rows[2].name == "Hungry")
check("group list: no GearScore without the module", byN.Souper.score == nil)
WM.modules.GearScore = { GroupList = function()
    return { { name = "Souper", score = 1800 }, { name = "Hungry", score = 1500 }, { name = "Eater" } }
end }
DB.groupSort = "gs"
rows = BC:GroupRows()
check("group list: GearScore column", rows[1].name == "Souper" and rows[1].score == 1800 and rows[2].score == 1500)
check("group list: unknown scores last", rows[3].score == nil and rows[4].score == nil)
DB.groupSort = "gslow"
check("group list: lowest GearScore first", BC:GroupRows()[1].name == "Hungry")
DB.groupSort = nil
WM.modules.GearScore = nil
env.UnitIsConnected = function(u) return u ~= "raid4" end
BC:ScanGroup()
for _, r in ipairs(BC:GroupRows()) do byN[r.name] = r end
check("group list: offline at the check", byN.Eater.missing == false)
env.UnitIsConnected = function() return true end
BC:ScanGroup()

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
-- Shattrath flasks: aura "Blinding Light", no "Flask of" in the name
DB.checkedGroups.flask = true
auras.raid3 = { "Blinding Light" }
auras.raid4 = { { "Pure Death", 46837 } }
lines, missing = BC:ScanGroup()
check("flask: Shattrath flasks count", missing == 0)
DB.checkedGroups.flask = false

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

-- ---- flask OR battle + guardian elixir (TBC rule) ----
-- Adept's Elixir's aura is "Spellpower Elixir" (33721); Draenic Wisdom is 39627
local ADEPT, DRAENIC = { "Spellpower Elixir", 33721 }, { "Elixir of Draenic Wisdom", 39627 }
check("Adept's Elixir is a battle elixir (by ID)", WM:ConsumableKind("Spellpower Elixir", 33721) == "battle")
check("Draenic Wisdom is a guardian elixir (by ID)", WM:ConsumableKind("Something Else", 39627) == "guardian")
check("names still work without an ID", WM:ConsumableKind("Adept's Elixir") == "battle"
    and WM:ConsumableKind("Elixir of Draenic Wisdom") == "guardian")

for k in pairs(DB.checkedGroups) do DB.checkedGroups[k] = false end
DB.checkedGroups.flask = true
auras.raid1 = { ADEPT, DRAENIC }                          -- both elixirs
auras.raid2 = { "Flask of Supreme Power" }                -- flask
auras.raid3 = { ADEPT }                                   -- battle only
auras.raid4 = { DRAENIC }                                 -- guardian only
lines, missing = BC:ScanGroup()
check("raid flask check: elixir pair counts as covered", not (lines[1] or ""):find("Souper", 1, true))
check("raid flask check: flask covered", not (lines[1] or ""):find("Steaker", 1, true))
check("raid flask check: one elixir isn't enough", missing == 2
    and lines[1]:find("Hungry", 1, true) and lines[1]:find("Eater", 1, true))
check("raid check renamed", lines[1]:find("Missing Flask or Elixirs:", 1, true) ~= nil)
DB.checkedGroups.flask = false
DB.checkedGroups.battleelixir = true
DB.checkedGroups.guardianelixir = true
lines, missing = BC:ScanGroup()
check("battle/guardian checks by spell ID: only the gaps reported", missing == 2)
DB.checkedGroups.battleelixir, DB.checkedGroups.guardianelixir = false, false

-- personal (Class Tools General) check: run the real monitor and read the alert
local alerts, monitor = {}, nil
local tools = WM.modules.ClassTools
tools.SetAlert = function(_, key, text) alerts[key] = text end
tools.ClearAlert = function(_, key) alerts[key] = nil end
tools.IsEnabled = function(_, class, key) return key == "flask" end
tools.RegisterMonitor = function(_, fn) monitor = fn end
env.UnitIsDeadOrGhost = function() return false end
Gen:Initialize()
check("general monitor registered", monitor ~= nil)
local function Warn(list) auras.player = list; monitor(); return alerts.gen_flask end
check("personal: Adept's + Draenic, no warning", Warn({ ADEPT, DRAENIC }) == nil)
check("personal: flask alone, no warning", Warn({ "Flask of Pure Death" }) == nil)
check("personal: battle only asks for a guardian", Warn({ ADEPT }) == "No guardian elixir (or flask)")
check("personal: guardian only asks for a battle", Warn({ DRAENIC }) == "No battle elixir (or flask)")
check("personal: nothing up", Warn({ "Arcane Intellect" }) == "No flask or elixirs")
check("personal: by name too (no spell ID)", Warn({ "Adept's Elixir", "Elixir of Draenic Wisdom" }) == nil)

-- whybuff prints the spell ID of anything unmatched, to add it
auras.player = { { "Mystery Elixir", 99999 } }
printed = {}
BC:ExplainUnit("player")
check("whybuff shows spell IDs of unmatched auras", has("Mystery Elixir (spell id 99999)"))
auras.player = { ADEPT, DRAENIC }
printed = {}
BC:ExplainUnit("player")
check("whybuff summarises flask-or-elixirs", has("Flask or elixirs: |cFF00FF00covered"))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
