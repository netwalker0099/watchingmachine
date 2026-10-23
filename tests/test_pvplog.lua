-- Battleground & Arena log (PvPLog). Usage: lua5.1 test_pvplog.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
env.date = function(fmt, t) return os.date("!" .. fmt, t) end
env.UnitName = function() return "Tanky" end
env.GetRealmName = function() return "Spineshatter" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitLevel = function() return 70 end
local inside, kind, zone = false, "none", nil
env.IsInInstance = function() return inside, kind end
env.GetInstanceInfo = function() return zone end
local scores, winner = {}, nil
env.GetNumBattlefieldScores = function() return #scores end
env.GetBattlefieldScore = function(i) return unpack(scores[i]) end
env.GetBattlefieldWinner = function() return winner end
env.RequestBattlefieldScoreData = function() end
local arenaTeam, teams, bracket, rated = 0, {}, nil, false
env.GetBattlefieldArenaFaction = function() return arenaTeam end
env.GetBattlefieldTeamInfo = function(t) local x = teams[t]; if x then return x[1], x[2], x[3] end end
env.GetMaxBattlefieldID = function() return 2 end
env.GetBattlefieldStatus = function(i) if i == 1 and kind == "arena" then return "active", zone, bracket, rated and 1 or 0 end; return "none" end
env.IsActiveBattlefieldArena = function() return kind == "arena", rated end
local handler
env.LinkUtil = { RegisterLinkHandler = function(k, fn) if k == "wmlink" then handler = fn end end }
env.LinkProcessorResponse = { Handled = 2 }

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/PvPLog.lua")
local WM = W.WM
local Log = WM.modules.PvPLog
env.WatchingMachineDB = { theme = "Default" }
Log:Initialize()
WM:SetupChatLinks()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Zone(z, k)
    if z then inside, kind, zone = true, k, z else inside, kind, zone = false, "none", nil end
    Log:OnEvent("PLAYER_ENTERING_WORLD")
end
local function Last() return W.printed[#W.printed] or "" end
local matches = Log:Matches()

-- ---- A battleground, won ----
Zone("Warsong Gulch", "pvp")
local m = Log:Current()
check("battleground starts a match", m and m.kind == "bg" and m.name == "Warsong Gulch" and m.char == "Tanky-Spineshatter")
Log:OnEvent("PLAYER_ENTERING_WORLD")
check("reload inside: same match", Log:Current() == m and #matches == 1)
-- name, KB, HK, deaths, honor, faction, rank, race, class, classToken, damage, healing
scores = {
    { "Tanky", 4, 31, 2, 412, 1, 0, "Human", "Warrior", "WARRIOR", 120000, 5000 },
    { "Orcy-Hellscream", 1, 20, 5, 200, 0, 0, "Orc", "Rogue", "ROGUE", 50000, 0 },
}
Log:OnEvent("UPDATE_BATTLEFIELD_SCORE")
check("no winner yet: still going", Log:Current() == m and not m.done)
now = now + 1450
winner = 1   -- Alliance
Log:OnEvent("UPDATE_BATTLEFIELD_SCORE")
check("winner declared: match finished", m.done and Log:Current() == nil and m.ended == now)
check("our faction won: win", m.result == "win" and m.team == 1)
check("scoreboard line saved", m.killingBlows == 4 and m.honorableKills == 31 and m.deaths == 2 and m.honor == 412
    and m.damage == 120000 and m.healing == 5000 and m.players == 2)
check("result in chat", Last():find("Warsong Gulch", 1, true) and Last():find("Win", 1, true)
    and Last():find("24m 10s", 1, true) and Last():find("4 KB, 31 HK, 2 deaths, +412 honor", 1, true))
local link = Last():match("(wmlink:pvplog:[^|]*)|h")
check("chat line opens the log", link ~= nil)
Zone(nil)
check("leaving after the end: nothing extra", #matches == 1 and m.result == "win")

-- ---- A battleground, lost ----
winner = nil
Zone("Arathi Basin", "pvp")
scores = { { "Tanky", 0, 10, 8, 150, 1, 0, "Human", "Warrior", "WARRIOR", 30000, 0 } }
winner = 0
Log:OnEvent("UPDATE_BATTLEFIELD_STATUS")
check("other faction won: loss", matches[1].result == "loss")
Zone(nil)

-- ---- Leaving early ----
winner = nil
Zone("Warsong Gulch", "pvp")
now = now + 300
Zone(nil)
check("left before the end: left", matches[1].result == "left" and matches[1].done)

-- ---- A rated 2v2, lost ----
rated, bracket, arenaTeam = true, 2, 1
Zone("Nagrand Arena", "arena")
local a = Log:Current()
check("arena: bracket and rated", a.kind == "arena" and a.bracket == 2 and a.rated == true)
scores = {
    { "Tanky", 1, 0, 1, 0, 1, 0, "Human", "Warrior", "WARRIOR", 40000, 0 },
    { "Healz", 0, 0, 0, 0, 1, 0, "Dwarf", "Priest", "PRIEST", 2000, 30000 },
    { "Stabby", 2, 0, 0, 0, 0, 0, "Orc", "Rogue", "ROGUE", 50000, 0 },
    { "Zappy", 0, 0, 0, 0, 0, 0, "Troll", "Mage", "MAGE", 45000, 0 },
}
teams = { [0] = { "Gank Squad", 1600, 1615 }, [1] = { "Our Team", 1520, 1505 } }
now = now + 180
winner = 0
Log:OnEvent("UPDATE_BATTLEFIELD_SCORE")
check("arena result", a.result == "loss" and a.team == 1)
check("rating change", a.rating == 1505 and a.ratingChange == -15)
check("partners and opponents", #a.partners == 1 and a.partners[1].name == "Healz"
    and #a.opponents == 2 and a.opponents[1].name == "Stabby" and a.opponents[2].class == "MAGE")
check("arena summary", Last():find("2v2 rated arena", 1, true) and Last():find("rating 1505 (-15)", 1, true)
    and Last():find("Stabby", 1, true))
Zone(nil)
-- A skirmish win
rated, bracket, arenaTeam = false, 3, 0
teams = {}
Zone("Ruins of Lordaeron", "arena")
winner = 0
Log:OnEvent("UPDATE_BATTLEFIELD_SCORE")
check("skirmish: win, no rating", matches[1].result == "win" and matches[1].rated == false and matches[1].ratingChange == nil)
Zone(nil)
winner = nil

-- ---- Totals ----
local totals = {}
for _, t in ipairs(Log:Totals()) do totals[t.key] = t end
check("per battleground", totals["bg:Warsong Gulch"].games == 2 and totals["bg:Warsong Gulch"].wins == 1
    and totals["bg:Arathi Basin"].games == 1 and totals["bg:Arathi Basin"].wins == 0)
check("per arena bracket", totals["arena:2:rated"].games == 1 and totals["arena:3:skirmish"].wins == 1)
check("totals text", Log:TotalsText():find("Warsong Gulch: |cFFFFFFFF2|r played", 1, true) ~= nil)
check("status", Log:GetQuickStatus():find("5 played, 2 won (40%)", 1, true) ~= nil)

-- ---- The window ----
handler(link, "x", {}, {})
local f = env.WM_PvPLogFrame
check("chat link opens the window", f and f:IsShown())
local shown = 0
for _, r in ipairs(f.rows) do if r:IsShown() then shown = shown + 1 end end
check("a row per match", shown == 5)
W.fire(f.rows[1], "OnEnter")
WM.Confirm = function(_, _, fn) fn() end
W.fire(f.rows[1], "OnClick", "RightButton")
check("right-click deletes", #matches == 4)
Log.DB().announce = false
local p = #W.printed
Zone("Eye of the Storm", "pvp")
winner = 1
scores = { { "Tanky", 0, 0, 0, 0, 1 } }
Log:OnEvent("UPDATE_BATTLEFIELD_SCORE")
check("chat result can be turned off", #W.printed == p and matches[1].result == "win")

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
