-- Loot Council, part 5: the loot history shared between Watching Machine
-- users. Awards made or recorded live, and edits and deletes, go to the
-- guild; a guildmate's arrive and merge with what we have (the latest change
-- wins); at login we catch up on what we missed, one award at a time.
-- Usage: lua5.1 test_lootcouncil_sync.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1793000000
env.GetServerTime = function() return now end
env.C_DateAndTime = false
env.GetRealmName = function() return "Nightslayer" end
env.IsAddOnLoaded = function() return false end
env.C_AddOns = { IsAddOnLoaded = function() return false end }
env.InCombatLockdown = function() return false end
env.IsInGuild = function() return true end
env.IsInGroup = function() return false end
env.IsInRaid = function() return false end
env.UnitExists = function(u) return u == "player" end
env.GetNumGroupMembers = function() return 0 end
env.GetItemInfo = function() return nil end
env.C_Item = { GetItemInfo = function() return nil end }
local timers = {}
local function NewTimer(_, fn)
    local t = { fn = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
end
env.C_Timer = { After = NewTimer, NewTimer = NewTimer, NewTicker = function() return { Cancel = function() end } end }
local function RunTimers()
    for _ = 1, 100 do
        local list = timers; timers = {}
        if #list == 0 then return end
        for _, t in ipairs(list) do if not t.cancelled then t.fn() end end
    end
end
local sent = {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, body, channel, target) sent[#sent + 1] = { prefix, body, channel, target } end }

env.WatchingMachineDB = { theme = "Default" }
for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/LootCouncil.lua", "Modules/LootCouncilCodec.lua",
    "Modules/LootCouncilRC.lua", "Modules/LootCouncilML.lua", "Modules/LootCouncilRoll.lua", "Modules/LootCouncilSync.lua",
    "Modules/LootCouncilUI.lua", "Modules/LootCouncilFrames.lua" }) do
    W.load(f)
end
local WM = W.WM
local LC = WM.modules.LootCouncil
local Sync, Codec = LC.Sync, WM.LootCodec

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
-- What we sent to the guild, unpacked
local function Out()
    WM:FlushAddonQueue()
    local un = Codec.NewUnframer()
    local out = {}
    for _, m in ipairs(sent) do
        if m[1] == "WMLootH" then
            local whole = un("me", m[2])
            if whole then
                local _, kind, payload = Codec.Deserialize(whole)
                out[#out + 1] = { kind = kind, payload = payload, channel = m[3] }
            end
        end
    end
    sent = {}
    return out
end
-- A guildmate's message
local function From(sender, kind, payload)
    for _, part in ipairs(Codec.Frame(Codec.Serialize(kind, payload))) do Sync:OnMessage("WMLootH", part, "GUILD", sender) end
end

LC:Initialize()
RunTimers()
Out()
Sync:ResetForTests()

local HELM = "|cffa335ee|Hitem:30242|h[Helm of the Vanquished Champion]|h|r"

-- ============ Imports aren't sent one by one ============
LC.Add({ link = HELM, to = "Taslan", t = now - 86400, how = "Mainspec/Need", src = { gl = "chk1" }, srcKind = "gl" })
check("an import isn't sent", #Out() == 0)

-- ============ Awards made live are ============
LC.AddRCLC("Pug-Nightslayer", { lootWon = "|cffa335ee|Hitem:30100|h[Soul-Strider Boots]|h|r", date = "2026/11/08",
    time = "21:00:00", response = "Offspec/Greed", responseID = 2, id = "1793000000-1", boss = "Lady Vashj" }, nil, true)
local out = Out()
check("a live award goes to the guild", out[1] and out[1].kind == "E" and out[1].channel == "GUILD"
    and out[1].payload.g == "rc:1793000000-1" and out[1].payload.o == "Pug-Nightslayer" and out[1].payload.h == "Offspec/Greed")
local pug = LC.LastLoot("Pug")
LC.DeleteEntry(pug)
out = Out()
check("a delete goes too, newer", out[1] and out[1].payload.d == true and out[1].payload.g == "rc:1793000000-1"
    and out[1].payload.m == now)

-- ============ A guildmate's awards ============
From("Venhana", "E", { g = "wm:Venhana-Nightslayer:1793000100:7", l = "|cffa335ee|Hitem:30020|h[Fire-Cord]|h|r", i = 30020,
    o = "Taslan-Nightslayer", b = "Venhana-Nightslayer", t = now + 100, m = now + 100, h = "Mainspec roll", s = "Kael'thas" })
local cord
for _, e in ipairs(LC.ForPlayer("Taslan")) do if e.itemID == 30020 then cord = e end end
check("a guildmate's award added", cord and cord.how == "Mainspec roll" and cord.boss == "Kael'thas" and cord.by == "Venhana-Nightslayer")
check("not sent on again", #Out() == 0)
From("Venhana", "E", { g = "wm:Venhana-Nightslayer:1793000100:7", i = 30020, o = "Taslan-Nightslayer", t = now + 100, m = now + 100 })
check("the same award again: once", #LC.ForPlayer("Taslan") == 2)
-- Their copy of an award we imported from Gargul: matched by the checksum, not doubled
From("Venhana", "E", { g = "gl:chk1", a = { gl = "chk1" }, l = HELM, i = 30242, o = "Taslan-Nightslayer", t = now - 86400,
    m = now - 86400, h = "Mainspec" })
check("matched by Gargul's checksum", #LC.ForPlayer("Taslan") == 2)
-- A newer change wins, an older one doesn't
From("Venhana", "E", { g = "gl:chk1", a = { gl = "chk1" }, i = 30242, o = "Pug-Nightslayer", t = now - 86400, m = now + 500, h = "Offspec" })
check("a newer change (new winner) wins", LC.LastLoot("Pug") and LC.LastLoot("Pug").itemID == 30242 and LC.LastLoot("Pug").how == "Offspec"
    and #LC.ForPlayer("Taslan") == 1)
From("Venhana", "E", { g = "gl:chk1", a = { gl = "chk1" }, i = 30242, o = "Taslan-Nightslayer", t = now - 86400, m = now + 200, h = "Mainspec" })
check("an older change doesn't", LC.LastLoot("Pug").itemID == 30242)
From("Venhana", "E", { g = "wm:Venhana-Nightslayer:1793000100:7", i = 30020, o = "Taslan-Nightslayer", t = now + 100, m = now + 600, d = true })
check("a delete from a guildmate", #LC.ForPlayer("Taslan") == 0)
-- Deleted before we had it: remembered, so an import doesn't bring it back
From("Venhana", "E", { g = "rc:old-1", a = { rc = "old-1" }, i = 30027, o = "Hydarnes-Nightslayer", t = now - 9000, m = now, d = true })
check("a deleted award stays deleted", LC.AddRCLC("Hydarnes-Nightslayer", { lootWon = "|cffa335ee|Hitem:30027|h[x]|h|r",
    date = "2026/11/08", time = "18:00:00", response = "x", id = "old-1" }) ~= nil and #LC.ForPlayer("Hydarnes") == 0)
-- Not the guild channel, or ourselves: ignored
for _, part in ipairs(Codec.Frame(Codec.Serialize("E", { g = "wm:x:1:1", i = 1, o = "Bad-Nightslayer", t = now, m = now }))) do
    Sync:OnMessage("WMLootH", part, "WHISPER", "Bad")
end
check("only the guild channel", #LC.ForPlayer("Bad") == 0)

-- ============ Attendance ============
env.IsInRaid = function() return true end
env.GetRaidRosterInfo = function(i) return ({ "Me", "Taslan" })[i] end
env.GetRealZoneText = function() return "Karazhan" end
LC:RecordKill("Prince Malchezaar")
out = Out()
check("a boss kill goes to the guild", out[1] and out[1].kind == "A" and out[1].payload.b == "Prince Malchezaar" and #out[1].payload.m == 2)
From("Venhana", "A", { t = now, z = "Karazhan", b = "Prince Malchezaar", m = { "Venhana-Nightslayer", "Taslan-Nightslayer" } })
local kara = LC.DB().raids[LC.RaidKey(now, "Karazhan", "Prince Malchezaar")]
check("a guildmate's view of the same kill adds who we missed", kara and #kara.members == 3)
From("Venhana", "A", { t = now - 86400, z = "Karazhan", b = "Nightbane", m = { "Venhana-Nightslayer" } })
check("a kill we weren't at", LC.DB().raids[LC.RaidKey(now - 86400, "Karazhan", "Nightbane")] ~= nil)
check("not sent on again", #Out() == 0)
env.IsInRaid = function() return false end

-- ============ Catching up ============
Sync:ResetForTests()
WM.LootCouncil.DB().syncLastOnline = nil
Sync:Hello()
out = Out()
check("first login: ask for everything", out[1] and out[1].kind == "C" and out[1].payload == 0)
check("last online noted", LC.DB().syncLastOnline == now)
Sync:ResetForTests()
now = now + 7200
Sync:Hello()
out = Out()
check("next login: since an hour before", out[1] and out[1].payload == now - 7200 - 3600)
-- A guildmate asks: we send what changed since, one at a time
Sync:ResetForTests()
From("Returner", "C", now - 7200 - 3600)
local queued = Sync.CatchUpLength()
check("catch-up queued (awards and raids)", queued >= 3)
check("catch-up waits a moment", #Out() == 0)
-- Someone else sends one first: we skip it
local skipGid = "gl:chk1"
From("Faster", "E", { g = skipGid, a = { gl = "chk1" }, i = 30242, o = "Pug-Nightslayer", t = now - 86400 - 7200, m = now - 7200 + 500, h = "Offspec" })
RunTimers()
out = Out()
local gids = {}
for _, m in ipairs(out) do if m.payload.g then gids[m.payload.g] = true end end
check("catch-up sent the rest", #out >= 1 and #out == queued - 1)
check("skipped what someone else sent", not gids[skipGid])
check("nothing left", Sync.CatchUpLength() == 0)
From("UpToDate", "C", now + 10)
check("nothing newer: nothing queued", Sync.CatchUpLength() == 0)
From("Returner", "C", 0)
Sync:Stop()
RunTimers()
check("stopped: the catch-up is dropped", Sync.CatchUpLength() == 0 and #Out() == 0)

-- ============ Turned off ============
LC.DB().syncHistory = false
LC.AddRCLC("Pug-Nightslayer", { lootWon = "|cffa335ee|Hitem:30106|h[Belt]|h|r", date = "2026/11/08", time = "22:00:00",
    response = "Mainspec/Need", id = "1793009999-1" }, nil, true)
check("sharing off: nothing sent", #Out() == 0)
From("Venhana", "E", { g = "wm:v:2:2", i = 30106, o = "Taslan-Nightslayer", t = now, m = now })
check("sharing off: nothing taken", #LC.ForPlayer("Taslan") == 0)
LC.DB().syncHistory = true
WM:SetModuleOn("LootCouncil", false)
From("Venhana", "E", { g = "wm:v:3:3", i = 30106, o = "Taslan-Nightslayer", t = now, m = now })
check("module off: nothing taken", #LC.ForPlayer("Taslan") == 0)
WM:SetModuleOn("LootCouncil", true)

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
