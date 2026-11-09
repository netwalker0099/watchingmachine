-- Roster Manager's full catch-up sync: as a follower of Guild Roster
-- Manager's elected leader (its lists, our newer records with sequence
-- numbers and resends, its newer records applied, alt groups and
-- birthdays), the election (we never stand), and the catch-up between
-- Watching Machine users.
-- Usage: lua5.1 test_guildroster_fullsync.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local clock = 1800000000
env.time = function(t) if t then return os.time(t) end return clock end
env.date = function(fmt, t) return os.date(fmt, t or clock) end
env.GetRealmName = function() return "Spine Shatter" end
env.UnitName = function() return "Me" end
env.IsInGuild = function() return true end
env.GetGuildInfo = function() return "The Watchers", "Officer", 1 end
env.GuildControlGetNumRanks = function() return 5 end
env.CanViewOfficerNote = function() return true end
env.IsInGroup = function() return false end

local roster = {}
local function Member(name, rank, idx, level, class, guid)
    return { name = name .. "-SpineShatter", rank = rank, idx = idx, level = level, class = class, guid = guid, note = "", onote = "", online = true }
end
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
    local m = roster[i]
    if not m then return nil end
    return m.name, m.rank, m.idx, m.level, nil, "Shattrath", m.note, m.onote, m.online, 0, m.class, nil, nil, nil, nil, nil, m.guid
end
env.GetGuildRosterLastOnline = function() return 0, 0, 0, 0 end
env.GetNumGuildEvents = function() return 0 end

local sent = {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, body, channel, target) sent[#sent + 1] = { prefix, body, channel, target } end }
env.C_AddOns = { IsAddOnLoaded = function() return false end }
local afters = {}
env.C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
    NewTimer = function(_, fn) local t = { fn = fn, Cancel = function(self) self.cancelled = true end }; afters[#afters + 1] = function() if not t.cancelled then fn() end end; return t end,
    NewTicker = function() return { Cancel = function() end } end }

for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/LootCouncilCodec.lua", "Modules/GuildRoster.lua",
    "Modules/GuildRosterSync.lua", "Modules/GuildRosterUI.lua", "Modules/GuildRosterPurge.lua",
    "Modules/GuildRosterTools.lua", "Modules/GuildRosterFullSync.lua" }) do
    W.load(f)
end
local WM = W.WM
local GR, Sync = WM.modules.GuildRoster, WM.GuildRoster.Sync
local Full = Sync.Full
local Codec = WM.LootCodec
env.WatchingMachineDB = { theme = "Default" }
WM.RunAfter = function(_, fn) afters[#afters + 1] = fn end
local function RunAfters() for _ = 1, 20 do local a = afters; afters = {}; if #a == 0 then return end; for _, fn in ipairs(a) do fn() end end end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

GR:Initialize()
roster = {
    Member("Me", "Officer", 1, 70, "MAGE", "Player-1-ME"),
    Member("Leader", "Officer", 1, 70, "PALADIN", "Player-1-LEAD"),
    Member("Tank", "Raider", 2, 70, "WARRIOR", "Player-1-TANK"),
    Member("Healer", "Raider", 2, 70, "PRIEST", "Player-1-HEAL"),
    Member("Alty", "Member", 3, 60, "ROGUE", "Player-1-ALTY"),
}
GR:Scan()
local g = GR:Guild()
Sync:ClearQueue()
sent = {}

-- The leader runs Guild Roster Manager on our release
Sync:OnUserMessage("REG?R1.99423?" .. Sync:PatchDay() .. "?4?1?false?true?true", "Leader-SpineShatter")
check("leader known", Sync.users["Leader-SpineShatter"] and Sync.users["Leader-SpineShatter"].ok)

local function Out()
    WM:FlushAddonQueue()
    local out = {}
    for _, m in ipairs(sent) do out[#out + 1] = { prefix = m[1], body = m[2], channel = m[3], target = m[4] } end
    sent = {}
    return out
end
local function Bodies(out, pat)
    local r = {}
    for _, m in ipairs(out) do if m.body:find(pat) then r[#r + 1] = m.body end end
    return r
end
local function FromLeader(body) Sync:OnSyncMessage(body, "Leader-SpineShatter") end

-- Our data: Tank's join date (newer than the leader's), a custom note, an alt group
GR:SetJoinDate("Tank", "20250101", clock - 100)
GR:SetCustomNote("Healer", "heals well", clock - 50)
GR:AddAlt("Tank", "Alty"); GR:SetMain("Tank")
Sync:ClearQueue()
Out()

-- ============ The election: we never stand ============
GR.DB().fullSync = true
check("asks who leads", Full:Begin() == true)
local out = Out()
check("WHOISLEADER to the guild", #Bodies(out, "^GRM_WHOISLEADER%?") == 1)
RunAfters()
out = Out()
check("no answer: an election", #Bodies(out, "^GRM_ELECT%?") == 1)
-- (the afters ran the election end too with no candidates; run it again with one)
Full.electing, Full.candidates = true, {}
FromLeader("GRM_ELECTINFO?4?Leader-SpineShatter?1799990000?1?1?4?4?4")
Full:Elect()
out = Out()
check("the Guild Roster Manager user is announced as leader", #Bodies(out, "^GRM_NEWLEADER%?%d+%?Leader%-SpineShatter") == 1)
RunAfters()
out = Out()
local req = Bodies(out, "^GRM_REQUESTSYNC")
check("we ask the leader to sync with us, by whisper", #req == 1 and out[#out].target == "Leader-SpineShatter")
check("we never answer an election", (function() Sync:OnSyncMessage("GRM_ELECT?4?", "Tank-SpineShatter"); return #Bodies(Out(), "ELECTINFO") == 0 end)())

-- ============ The sync, as follower ============
FromLeader("GRM_REQJDDATA?4?Me-SpineShatter")
check("sync started with the leader", Full.partner == "Leader-SpineShatter")
FromLeader("GRM_PREHASHALL?4?1?2?3?4?5?6?21")
out = Out()
check("we compare everything", Bodies(out, "^GRM_PREALLRESULT%?4%?111")[1] ~= nil)
-- The leader's lists: Healer's join date (we have none), Tank's older one; its note for Healer older
FromLeader("GRM_RECJDPRE?4?Healer-SpineShatter?" .. (clock - 500) .. "?Tank-SpineShatter?" .. (clock - 9000))
FromLeader("GRM_RECCUSTPRE?4?Healer-SpineShatter?" .. (clock - 9000))
FromLeader("GRM_RECALTPRE?4?Alty-SpineShatter?" .. (clock - 99999))
FromLeader("GRM_FINALPRE?4?")
RunAfters()
out = Out()
check("names we need from the leader", Bodies(out, "^GRM_JDSYNCF%?4%?Healer%-SpineShatter%?1$")[1] ~= nil)
check("our newer join date sent with a sequence number", Bodies(out, "^GRM_JDSYNC%?4%?Tank%-SpineShatter%?20250101%?" .. (clock - 100) .. "%?1$")[1] ~= nil)
check("our newer note", Bodies(out, "^GRM_CUSTSYNC1%?4%?Healer%-SpineShatter~|~" .. (clock - 50) .. "~|~Me%-SpineShatter~|~heals well~|~1$")[1] ~= nil)
check("our alt group: header and members", Bodies(out, "^GRM_ALTSYNC3%?4%?Alty%-SpineShatter%?Tank%-SpineShatter%?")[1] ~= nil
    and Bodies(out, "^GRM_ALTSYNC4%?4%?Alty%-SpineShatter%?Tank%-SpineShatter%?%d+$")[1] ~= nil)
local stop = Bodies(out, "^GRM_STOP%?")[1]
check("STOP with the counts sent", stop ~= nil and stop:find("^GRM_STOP%?4%?1%?1%?0%?0%?") ~= nil)
-- The leader lost our JD message 1: we resend it exactly
FromLeader("GRM_REQMISJD?4?1")
FromLeader("GRM_MISFIN?4?")
out = Out()
check("resend byte for byte, then MISSENT", out[1] and out[1].body:find("^GRM_JDSYNC%?4%?Tank") and Bodies(out, "^GRM_MISSENT%?4%?")[1] ~= nil)
-- The leader's newer records
FromLeader("GRM_JDSYNCUP?4?Healer-SpineShatter?20240305?" .. (clock - 500) .. "?1")
FromLeader("GRM_CUSTSYNCUP1?4?Tank-SpineShatter~|~" .. (clock - 10) .. "~|~Leader-SpineShatter~|~shield wall~|~1")
FromLeader("GRM_BANSYNCUP4?4?Healer-SpineShatter~|~" .. (clock - 5) .. "~|~1~|~Leader-SpineShatter~|~ninja looted~|~1")
FromLeader("GRM_ALTSYNCUP3?4?Healer-SpineShatter?Healer-SpineShatter?" .. (clock - 1) .. "?1?1")
FromLeader("GRM_ALTSYNCUP4?4?Healer-SpineShatter?Leader-SpineShatter?2")
check("their newer join date applied", g.members["Healer-SpineShatter"].join.date == "20240305")
check("their newer note applied", g.members["Tank-SpineShatter"].custom.text == "shield wall")
check("their ban applied", g.members["Healer-SpineShatter"].ban.on and g.members["Healer-SpineShatter"].ban.reason == "ninja looted")
-- FINALSTOP says 2 JD messages: we ask for number 2
FromLeader("GRM_FINALSTOP?4?2?0?2?1?1")
out = Out()
check("missing number asked for", Bodies(out, "^GRM_REQJDFIN%?4%?2$")[1] ~= nil and Bodies(out, "^GRM_MISFIN2%?4%?")[1] ~= nil)
FromLeader("GRM_JDSYNCUP?4?Leader-SpineShatter?20230101?" .. (clock - 400) .. "?2")
FromLeader("GRM_JDSYNCUP?4?Leader-SpineShatter?20230101?" .. (clock - 400) .. "?2")
FromLeader("GRM_MISSENT2?4?")
out = Out()
check("resent record applied", g.members["Leader-SpineShatter"].join.date == "20230101")
check("alt groups applied after the data", g.members["Healer-SpineShatter"].group ~= nil
    and g.groups[g.members["Healer-SpineShatter"].group].main == "Healer-SpineShatter"
    and g.members["Leader-SpineShatter"].group == g.members["Healer-SpineShatter"].group)
check("ALTPROCESSED", Bodies(out, "^GRM_ALTPROCESSED%?4%?")[1] ~= nil)
-- Birthdays
FromLeader("GRM_RECBDAYPRE?4?Tank-SpineShatter?" .. (clock - 20))
FromLeader("GRM_FINALPRE2?4?")
RunAfters()
out = Out()
check("birthday names asked for, STOP2", Bodies(out, "^GRM_BDAYSYNCF%?4%?Tank%-SpineShatter%?1$")[1] ~= nil and Bodies(out, "^GRM_STOP2%?4%?1%?0$")[1] ~= nil)
FromLeader("GRM_BDSYNCUP?4?Tank-SpineShatter?" .. (clock - 20) .. "?14?2?1")
FromLeader("GRM_FINALSTOP2?4?1")
out = Out()
check("their birthday applied", g.members["Tank-SpineShatter"].bday.d == 14 and g.members["Tank-SpineShatter"].bday.m == 2)
check("FINALSTOP3", Bodies(out, "^GRM_FINALSTOP3%?4%?")[1] ~= nil)
FromLeader("GRM_COMPLETE?4?Me-SpineShatter")
check("finished", not Full:Active() and GR.DB().lastFullSync == clock)

-- Someone who isn't our leader can't drive a sync
FromLeader("GRM_REQJDDATA?4?Me-SpineShatter")
Sync:OnSyncMessage("GRM_JDSYNCUP?4?Tank-SpineShatter?19990101?" .. (clock + 99) .. "?1", "Healer-SpineShatter")
check("records from someone else ignored", g.members["Tank-SpineShatter"].join.date == "20250101")
FromLeader("GRM_ENDSYNC?")
check("the leader can stop it", not Full:Active())
-- Silence: we give up
FromLeader("GRM_REQJDDATA?4?Me-SpineShatter")
clock = clock + 20
Full:CheckTimeout()
check("timed out", not Full:Active())

-- ============ Between Watching Machine users ============
Full:ResetForTests()
GR.DB().rosterLastOnline = nil
Full:HelloWM()
local function WMOut()
    WM:FlushAddonQueue()
    local un = Codec.NewUnframer()
    local r = {}
    for _, m in ipairs(sent) do
        if m[1] == "WMRosterS" then
            local whole = un("me", m[2])
            if whole then local _, k, p = Codec.Deserialize(whole); r[#r + 1] = { kind = k, payload = p } end
        end
    end
    sent = {}
    return r
end
local w = WMOut()
check("first time: ask for everything", w[1] and w[1].kind == "C" and w[1].payload == 0)
-- A guildmate asks: we send records changed since then
Full:ResetForTests()
local function FromWM(sender, kind, payload)
    for _, part in ipairs(Codec.Frame(Codec.Serialize(kind, payload))) do Full:OnWMMessage("WMRosterS", part, "GUILD", sender) end
end
FromWM("Tank-SpineShatter", "C", clock - 100000)
check("catch-up queued", Full.CatchUpLength() >= 3)
RunAfters()
w = WMOut()
check("records sent one at a time", #w >= 3 and w[1].kind == "E" and w[1].payload.n ~= nil)
-- A guildmate's newer record
FromWM("Leader-SpineShatter", "E", { n = "Alty-SpineShatter", t = clock + 50, j = { "20220202", clock + 50 },
    c = { "best rogue", clock + 50, "Leader-SpineShatter" } })
check("their newer join date and note", g.members["Alty-SpineShatter"].join.date == "20220202"
    and g.members["Alty-SpineShatter"].custom.text == "best rogue")
FromWM("Leader-SpineShatter", "E", { n = "Alty-SpineShatter", t = clock - 9e5, j = { "19990101", clock - 9e5 } })
check("an older one doesn't win", g.members["Alty-SpineShatter"].join.date == "20220202")

-- ============ Off ============
WM:SetModuleOn("GuildRoster", false)
FromLeader("GRM_REQJDDATA?4?Me-SpineShatter")
check("off: no sync", not Full:Active())
check("off: no catch-up", (function() FromWM("Tank-SpineShatter", "C", 0); return Full.CatchUpLength() == 0 end)())
WM:SetModuleOn("GuildRoster", true)

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
