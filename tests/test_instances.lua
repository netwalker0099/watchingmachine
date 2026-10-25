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
env.GetMaxPlayerLevel = function() return 70 end
env.IsXPUserDisabled = function() return false end
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
-- 49,200 XP in 25 minutes; 59,800 still needed at level 41
check("XP still needed recorded on leaving", run.xpToLevel == 60000 - 200)
check("XP per hour", math.floor(IT.XPPerHour(run)) == 118080 and LastPrint():find("118,080 XP/hour", 1, true) ~= nil)
check("runs like it to level", IT.RunsToLevel(run) == 2 and LastPrint():find("2 more runs like this to level 42", 1, true) ~= nil)
local function Fake(t) local r = { name = "Test", entered = 0, left = 0, mobs = 0, xp = 0, gold = 0 }
    for k, v in pairs(t) do r[k] = v end; return r end
check("one run to go: singular", IT:RunSummary(Fake({ left = 600, xp = 5000, xpToLevel = 3000, levelOut = 50 }))
    :find("1 more run like this to level 51", 1, true) ~= nil)
check("under a minute: no hourly rate", IT.XPPerHour(Fake({ left = 45, xp = 900 })) == nil)
check("no XP: no rate, no runs", IT.XPPerHour(Fake({ left = 600 })) == nil and IT.RunsToLevel(Fake({ left = 600, xpToLevel = 100 })) == nil)
check("at the level cap: no runs to level", IT.RunsToLevel(Fake({ left = 600, xp = 500, xpToLevel = nil })) == nil
    and not IT:RunSummary(Fake({ left = 600, xp = 500, levelOut = 70 })):find("more run", 1, true))
IT.DB().xpRate = false
check("option off: no rate or runs", not IT:RunSummary(run):find("XP/hour", 1, true)
    and not IT:RunSummary(run):find("more run", 1, true))
IT.DB().xpRate = true

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
check("stats off: only the entered line", #sent == n and #W.printed == p + 1
    and W.printed[#W.printed]:find("Entered Gnomeregan", 1, true) ~= nil)
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

-- ---- Clickable chat lines and the X ----
local handler
env.LinkUtil = { RegisterLinkHandler = function(kind, fn) if kind == "wmlink" then handler = fn end end }
env.LinkProcessorResponse = { Handled = 2, Unhandled = 1 }
WM.chatLinksReady = nil
WM:SetupChatLinks()
check("link type claimed with LinkUtil", handler ~= nil)
local p0 = #W.printed
Zone("Scholomance", 289)
local scholo = IT:Current()
local line = W.printed[#W.printed]
check("entered line printed with counts", #W.printed == p0 + 1 and line:find("Entered Scholomance (", 1, true) ~= nil
    and line:find("this hour", 1, true) ~= nil)
local logLink = line:match("(wmlink:itlog:[^|]*)|h")
local delLink = line:match("(wmlink:itdel:%d+)|h")
check("the line opens the log", logLink ~= nil)
check("and has a red X for this run", delLink == "wmlink:itdel:" .. scholo.id
    and line:find("UI%-GroupLoot%-Pass%-Up") ~= nil)
check("every run has an id", (function() for _, r in ipairs(runs) do if not r.id then return false end end return true end)())
if f:IsShown() then f:Hide() end
check("clicking the line returns Handled", handler(logLink, "[x]", {}, { button = "LeftButton" }) == 2)
check("and opens the log", f:IsShown())
f:Hide()
local confirmText
WM.Confirm = function(_, text, fn) confirmText = text; fn() end
local before2 = #runs
handler(delLink, "x", {}, { button = "LeftButton" })
check("the X asks, then deletes that run", confirmText:find("Delete Scholomance", 1, true) ~= nil
    and #runs == before2 - 1 and IT:RunById(scholo.id) == nil and IT:Current() == nil)
check("and says so", W.printed[#W.printed]:find("Deleted Scholomance", 1, true) ~= nil)
handler(delLink, "x", {}, { button = "LeftButton" })
check("clicking an old X: already gone", W.printed[#W.printed]:find("no longer in the log", 1, true) ~= nil)
check("other links aren't ours", WM:HandleChatLink("item:1234", "LeftButton") == false)
IT:PrintLockouts()
check("lockout lines are clickable", W.printed[#W.printed]:find("wmlink:itlog:", 1, true) ~= nil)
Zone(nil)
IT.DB().enterMessage = false
local p1 = #W.printed
Zone("Stratholme", 329)
check("entered line can be turned off", #W.printed == p1)
Zone(nil)
-- Older clients: SetItemRef hook and the item tooltip guard
env.LinkUtil = false   -- (nil would read as a stub frame)
local hooked
env.hooksecurefunc = function(name, fn) if name == "SetItemRef" then hooked = fn end end
env.SetItemRef = function() end
local shownLink
env.ItemRefTooltip = { SetHyperlink = function(_, link) shownLink = link end }
WM.chatLinksReady = nil
WM:SetupChatLinks()
f:Hide()
hooked("wmlink:itlog:", "x", "LeftButton")
check("older client: SetItemRef hook opens the log", f:IsShown())
env.ItemRefTooltip:SetHyperlink("wmlink:itlog:")
check("item tooltip ignores our links", shownLink == nil)
env.ItemRefTooltip:SetHyperlink("item:1234")
check("but still shows real ones", shownLink == "item:1234")

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
