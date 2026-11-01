-- Class Tools > General: Righteous Fury watch on the tanking paladins in
-- your group. Usage: lua5.1 test_rfwatch.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 100
env.GetTime = function() return now end
-- player = Me (mage), party1 = Tankadin, party2 = Holyadin
local roster = { player = { "Me", "MAGE" }, party1 = { "Tankadin", "PALADIN" }, party2 = { "Holyadin", "PALADIN" } }
local group, raid, instance = true, false, true
env.IsInGroup = function() return group end
env.IsInRaid = function() return raid end
env.IsInInstance = function() return instance, instance and "party" or "none" end
env.GetNumGroupMembers = function() return 3 end
env.UnitExists = function(u) return roster[u] ~= nil end
env.UnitName = function(u) return roster[u] and roster[u][1] end
env.UnitClass = function(u) local r = roster[u]; if r then return r[2], r[2] end end
env.UnitIsUnit = function(a, b) return a == b end
local dead, visible, online = {}, { party1 = true, party2 = true }, {}
env.UnitIsDeadOrGhost = function(u) return dead[u] or false end
env.UnitIsConnected = function(u) return not online[u] end
env.UnitIsVisible = function(u) return visible[u] or false end
env.GetSpellInfo = function(id) if id == 25780 then return "Righteous Fury" end end
local buffs = {}
env.UnitBuff = function(u, i) return buffs[u] and buffs[u][i] end
local sent = {}
env.SendChatMessage = function(m, c) sent[#sent + 1] = { m, c } end
-- Nothing else in General should warn here
env.UnitPowerType = function() return 0 end
env.UnitPower = function() return 100 end
env.UnitPowerMax = function() return 100 end
env.GetInstanceInfo = function() return nil, "party", nil, nil, 5 end

for _, f in ipairs({ "Core.lua", "UI.lua", "Sounds.lua", "Modules/ClassTools.lua", "Modules/ClassGeneral.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Gen = WM.modules.ClassTools, WM.modules.ClassGeneral
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
local alerts = {}
CT.SetAlert = function(_, key, text) alerts[key] = text end
CT.ClearAlert = function(_, key) alerts[key] = nil end
local printed = {}
Gen.Print = function(_, msg) printed[#printed + 1] = msg end
Gen:RegisterFeatures()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Tick(s) now = now + (s or 1); Gen.FuryMonitor() end
local TANK = "gen_rf_Tankadin"

check("on by default, telling only you", CT:IsEnabled("GENERAL", "rfWatch") and env.GeneralChecksDB.rfChannel == "LOCAL")

-- Holyadin never has Righteous Fury: never warned about
Tick()
check("no Righteous Fury seen yet: not a tank, no warning", next(alerts) == nil)
buffs.party1 = { "Blessing of Kings", "Righteous Fury" }
Tick()
check("Righteous Fury seen: a tank, nothing wrong", next(alerts) == nil and #printed == 0)

-- It falls off
buffs.party1 = { "Blessing of Kings" }
Tick()
check("falls off: warning line", alerts[TANK] == "Tankadin: Righteous Fury is off")
check("me only: told in my chat, nothing sent", printed[1] and printed[1]:find("Righteous Fury dropped off Tankadin!", 1, true)
    and #sent == 0)
Tick()
check("told once, the warning stays", #printed == 1 and alerts[TANK])
check("the healer paladin is never warned about", alerts.gen_rf_Holyadin == nil)
buffs.party1 = { "Righteous Fury" }
Tick(31)
check("back on: warning gone", alerts[TANK] == nil)

-- Announce to the group, once per 30 seconds
env.GeneralChecksDB.rfChannel = "PARTY"
buffs.party1 = {}
Tick()
check("party: announced", sent[1] and sent[1][1] == "Righteous Fury dropped off Tankadin!" and sent[1][2] == "PARTY")
buffs.party1 = { "Righteous Fury" }; Tick()
buffs.party1 = {}; Tick()
check("not again within 30 seconds", #sent == 1 and alerts[TANK])
buffs.party1 = { "Righteous Fury" }; Tick(30)
buffs.party1 = {}; Tick()
check("again after 30 seconds", #sent == 2)

env.GeneralChecksDB.rfChannel = "RAID"
buffs.party1 = { "Righteous Fury" }; Tick(31)
buffs.party1 = {}; Tick()
check("raid in a party goes to party", sent[3] and sent[3][2] == "PARTY")

env.GeneralChecksDB.rfChannel = "SAY"
instance = false
buffs.party1 = { "Righteous Fury" }; Tick(31)
buffs.party1 = {}; Tick()
check("say outside an instance: only me", #sent == 3 and printed[#printed]:find("Tankadin", 1, true))
instance = true
buffs.party1 = { "Righteous Fury" }; Tick(31)
buffs.party1 = {}; Tick()
check("say inside an instance", sent[4] and sent[4][2] == "SAY")

-- Death: it drops, nobody's fault; after a rez the warning shows (no announce)
buffs.party1 = { "Righteous Fury" }; Tick(31)
dead.party1 = true
buffs.party1 = {}
Tick()
check("dies: no warning, no announce", alerts[TANK] == nil and #sent == 4)
dead.party1 = nil
Tick()
check("resurrected without it: warning, no announce", alerts[TANK] and #sent == 4)

-- Out of sight: not judged
buffs.party1 = { "Righteous Fury" }; Tick(31)
visible.party1 = nil
buffs.party1 = {}
Tick()
check("out of sight: not judged", alerts[TANK] == nil and #sent == 4)
visible.party1 = true

-- Left the group, option off, module off
buffs.party1 = {}; Tick(31)
check("warning up again", alerts[TANK])
roster.party1 = nil
Tick()
check("left the group: warning gone", alerts[TANK] == nil)
roster.party1 = { "Tankadin", "PALADIN" }
buffs.party1 = { "Righteous Fury" }; Tick()
buffs.party1 = {}; Tick(31)
CT:SetEnabled("GENERAL", "rfWatch", false)
Tick()
check("option off: warning gone", alerts[TANK] == nil)
CT:SetEnabled("GENERAL", "rfWatch", true)
buffs.party1 = { "Righteous Fury" }; Tick()
buffs.party1 = {}; Tick(31)
check("option on: watching again", alerts[TANK])
local before = #sent
WM:SetModuleOn("ClassGeneral", false)
check("module off: warning gone", alerts[TANK] == nil)
buffs.party1 = { "Righteous Fury" }; Tick()
buffs.party1 = {}; Tick(31)
check("module off: nothing", alerts[TANK] == nil and #sent == before)

-- You as the paladin: your own warning is the Paladin tab's, not this one
WM:SetModuleOn("ClassGeneral", true)
roster.player = { "Me", "PALADIN" }
buffs.player = { "Righteous Fury" }; Tick()
buffs.player = {}; Tick(31)
check("yourself: not watched here", alerts.gen_rf_Me == nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
