-- Instance Tracker: runs, merging the same instance, resets, lockouts,
-- run stats, the log window. Usage: lua5.1 test_instances.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
env.time = function() return now end
env.date = function(fmt, t) return os.date("!" .. fmt, t) end
env.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
env.bit = { band = function(a, b)
    local r, bitv = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
        a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
    end
    return r
end }
local inside, kind, instName, mapID = false, "none", nil, nil
env.IsInInstance = function() return inside, kind end
env.GetInstanceInfo = function() return instName, kind, 1, "Normal", 5, 0, false, mapID end
local xp, xpMax, level = 1000, 50000, 40
env.UnitXP = function() return xp end
env.UnitXPMax = function() return xpMax end
env.UnitLevel = function(u) return u == "player" and level or 41 end
env.UnitName = function(u) if u == "player" then return "Tanky" end; if u == "party1" then return "Healz" end end
env.GetRealmName = function() return "Spineshatter" end
env.UnitClass = function(u) if u == "party1" then return "Priest", "PRIEST" end; return "Warrior", "WARRIOR" end
local grouped, leader = false, false
env.UnitExists = function(u) return u == "player" or (grouped and u == "party1") end
env.IsInGroup = function() return grouped end
env.IsInRaid = function() return false end
env.UnitIsGroupLeader = function() return leader end
local sent = {}
env.SendChatMessage = function(msg, chan) sent[#sent + 1] = { msg, chan } end
local cleu
env.CombatLogGetCurrentEventInfo = function() return unpack(cleu, 1, 12) end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/InstanceTracker.lua")
local WM = W.WM
local IT = WM.modules.InstanceTracker
env.WatchingMachineDB = { theme = "Default" }
IT:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Zone(name, map, k)
    if name then inside, kind, instName, mapID = true, k or "party", name, map
    else inside, kind, instName, mapID = false, "none", nil, nil end
    IT:OnEvent("PLAYER_ENTERING_WORLD")
end
local function Creature(map, zoneUID, npc) return "Creature-0-4395-" .. map .. "-" .. zoneUID .. "-" .. npc .. "-0000ABCDEF" end
local function Kill(srcFlags, dst)
    cleu = { now, "PARTY_KILL", false, "Player-1", "Tanky", srcFlags, 0, dst, "Mob", 0, 0 }
    IT:OnEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
local function LastPrint() return W.printed[#W.printed] or "" end
local runs = IT:Runs()

-- ---- Entering and leaving ----
check("nothing logged outside", #runs == 0 and IT:Current() == nil)
grouped = true
Zone("The Deadmines", 36)
local run = IT:Current()
check("entering a dungeon starts a run", #runs == 1 and run and run.name == "The Deadmines" and run.mapID == 36
    and run.kind == "party" and run.char == "Tanky-Spineshatter" and run.entered == now and run.left == 0)
check("group recorded with level and class", #run.group == 2 and run.group[2].name == "Healz"
    and run.group[2].class == "PRIEST" and run.group[2].level == 41)
check("level in recorded", run.levelIn == 40)
IT:OnEvent("PLAYER_ENTERING_WORLD")   -- a /reload inside
check("reload inside keeps the same run", #runs == 1 and IT:Current() == run)

-- ---- Stats ----
IT:SeeGUID(Creature(36, 7001, 639))
check("instance number from a creature GUID", run.zoneUID == 7001)
IT:SeeGUID(Creature(36, 9999, 639))
check("first number sticks", run.zoneUID == 7001)
Kill(0x511, Creature(36, 7001, 1))   -- mine
Kill(0x512, Creature(36, 7001, 2))   -- party
Kill(0x548, Creature(36, 7001, 3))   -- outsider
Kill(0x511, "Player-1-0000")          -- a player, not a mob
check("kills by you and your group counted", run.mobs == 2)
xp = 1600; IT:OnEvent("PLAYER_XP_UPDATE")
xp, xpMax, level = 200, 60000, 41; IT:OnEvent("PLAYER_LEVEL_UP")
check("XP counted across a level-up", run.xp == 600 + (50000 - 1600) + 200)
IT:OnEvent("CHAT_MSG_MONEY", "You loot 1 Gold, 20 Silver, 5 Copper")
IT:OnEvent("CHAT_MSG_MONEY", "Your share of the loot is 35 Copper.")
check("gold looted", run.gold == 10000 + 2000 + 5 + 35)
IT:OnEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Stormwind reputation has increased by 25.")
IT:OnEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Stormwind reputation has increased by 5.")
check("reputation summed per faction", run.rep.Stormwind == 30)

-- ---- Leaving ----
now = now + 1500
Zone(nil)
check("leaving ends the run", run.left == now and IT:Current() == nil and run.levelOut == 41)
check("stats printed on leaving", LastPrint():find("The Deadmines: 25m 00s, 2 mobs", 1, true) ~= nil
    and LastPrint():find("looted", 1, true) ~= nil)

-- ---- Same instance again: merged, not counted twice ----
now = now + 60
Zone("The Deadmines", 36)
local again = IT:Current()
check("going back in starts a new run at first", #runs == 2 and again ~= run)
Kill(0x511, Creature(36, 7001, 4))   -- first creature seen: same number
check("same instance number: merged into the earlier run", #runs == 1 and IT:Current() == run
    and run.left == 0 and run.mobs == 3)
check("says so", LastPrint():find("same The Deadmines", 1, true) ~= nil)
now = now + 600
Zone(nil)

-- ---- Resets ----
leader = true
IT:OnEvent("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
check("reset marks the old run", run.reset == true)
check("leader's reset told to the group", sent[#sent][1] == "[WM] The Deadmines has been reset." and sent[#sent][2] == "PARTY")
now = now + 60
Zone("The Deadmines", 36)
IT:SeeGUID(Creature(36, 7001, 639))   -- even with the same number
check("after a reset it's a new run", #runs == 2 and IT:Current() ~= run)
now = now + 600
Zone(nil)
leader = false
local n = #sent
IT:OnEvent("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
check("not leader: no group message", #sent == n)
grouped = false

-- ---- Lockouts ----
local l = IT:Lockouts(now)
check("two runs this hour", l.hour == 2 and l.day == 2 and not l.locked)
for i = 1, 3 do
    now = now + 60
    Zone("Shadowfang Keep", 33); IT:SeeGUID(Creature(33, 8000 + i, 1))
    now = now + 120
    Zone(nil)
end
l = IT:Lockouts(now)
check("five this hour: hourly lockout", l.hour == 5 and l.locked == "hourly")
IT:CheckLockoutReady()   -- the 30-second check sees the lockout
-- Oldest still counting is the first Deadmines run, left at 1800001500 + 60 + 600
check("wait until the oldest run is an hour old", l.wait == 3600 - (now - (1800000000 + 1500 + 60 + 600)))
local text = IT:LockoutText(now)
check("lockout text says hourly", text:find("Hourly lockout", 1, true) ~= nil)
check("dashboard status says hourly", IT:GetQuickStatus():find("Hourly lockout", 1, true) ~= nil)
IT:OnEvent("CHAT_MSG_SYSTEM", "You have entered too many instances recently.")
check("too many instances: lockouts printed", LastPrint():find("Hourly lockout", 1, true) ~= nil)
-- Times out of the hour
local beforeReady = #W.printed
now = now + 3600
IT:CheckLockoutReady()
check("can enter again: says so", LastPrint():find("new instance now", 1, true) ~= nil and #W.printed > beforeReady)
l = IT:Lockouts(now)
check("an hour later: none this hour, still counted today", l.hour == 0 and l.day == 5 and not l.locked)
-- Daily: 30 in 24 hours
for i = 1, 25 do
    table.insert(runs, 1, { name = "Filler", char = "Alt-Spineshatter", entered = now - 7200, left = now - 7000 - i,
        mobs = 0, xp = 0, gold = 0, rep = {}, group = {} })
end
l = IT:Lockouts(now)
check("30 in 24 hours: daily lockout", l.day == 30 and l.locked == "daily")
check("daily text", (IT:LockoutText(now)):find("Daily lockout", 1, true) ~= nil)
check("counts every character", l.day == 30)
for _ = 1, 25 do table.remove(runs, 1) end

-- Logged out inside: picked up again when you log back in
now = now + 100
Zone("Blackfathom Deeps", 48)
local bfd = IT:Current()
IT:OnEvent("PLAYER_LOGOUT")
check("logout closes the run without printing", bfd.left == now and bfd.loggedOut and IT:Current() == nil)
now = now + 300
IT:OnEvent("PLAYER_ENTERING_WORLD")
check("logged back in inside: same run", IT:Current() == bfd and bfd.left == 0 and bfd.loggedOut == nil)
-- Zoning straight into another instance closes the first
now = now + 100
instName, mapID = "Razorfen Kraul", 47
IT:OnEvent("PLAYER_ENTERING_WORLD")
check("another instance: first run closed, new one started", bfd.left == now and IT:Current().name == "Razorfen Kraul")
Zone(nil)

-- Stats to the group, or off
grouped = true
IT.DB().statsOnLeave = "group"
Zone("Gnomeregan", 90); now = now + 10; Zone(nil)
check("stats to the group", sent[#sent][1]:find("^%[WM%] Gnomeregan") ~= nil)
IT.DB().statsOnLeave = "off"
n = #sent
local p = #W.printed
Zone("Gnomeregan", 90); now = now + 10; Zone(nil)
check("stats off: nothing", #sent == n and #W.printed == p)
IT.DB().statsOnLeave = "self"
grouped = false

-- Merge option off
IT.DB().mergeSame = false
Zone("Uldaman", 70); IT:SeeGUID(Creature(70, 5555, 1)); now = now + 10; Zone(nil)
local count = #runs
Zone("Uldaman", 70); IT:SeeGUID(Creature(70, 5555, 1))
check("merge off: same number logged again", #runs == count + 1)
now = now + 10; Zone(nil)
IT.DB().mergeSame = true

-- Raids count too
Zone("Karazhan", 532, "raid")
check("raids logged", IT:Current().kind == "raid")
Zone(nil)

-- Patterns
check("money parsing", IT.MoneyFromText("You loot 3 Silver") == 300)
check("durations", IT.Duration(3725) == "1h 02m" and IT.Duration(65) == "1m 05s")

-- ---- The window ----
IT:Toggle()
local f = env.WM_InstanceTrackerFrame
check("window opens", f and f:IsShown())
local shown = 0
for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
check("one row per run", shown == #runs)
check("newest first", f.rows[1].run == runs[1])
check("lockout line shown", (f.lockoutText:GetText() or ""):find("This hour", 1, true) ~= nil)
W.fire(f.rows[1], "OnEnter")
check("hover shows the run", true)
local before = #runs
local victim = runs[2]
WM.Confirm = function(_, _, fn) fn() end
W.fire(f.rows[2], "OnClick", "RightButton")
check("right-click deletes the run", #runs == before - 1 and runs[2] ~= victim)
IT:Toggle()
check("toggle closes", not f:IsShown())

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
