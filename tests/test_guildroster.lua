-- Roster Manager: the roster scan (joins, leaves, kicks, renames, rejoins,
-- promotions), edits (dates, alts, mains, notes, birthdays, bans), the
-- Guild Roster Manager message formats both ways (and their gates), the
-- import, the setup page and the on/off switch.
-- Usage: lua5.1 test_guildroster.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local clock = 1800000000
env.time = function() return clock end
env.date = function(fmt, t) return os.date(fmt, t or clock) end
env.GetRealmName = function() return "Spine Shatter" end
env.UnitName = function() return "Me" end
env.IsInGuild = function() return true end
env.GetGuildInfo = function() return "The Watchers", "Officer", 1 end
env.GuildControlGetNumRanks = function() return 5 end
env.CanViewOfficerNote = function() return true end
env.IsInGroup = function() return false end

-- The live roster: { name, rankName, rankIndex, level, class, guid, note, onote, online }
local roster = {}
local function Member(name, rank, idx, level, class, guid, online)
    return { name = name .. "-SpineShatter", rank = rank, idx = idx, level = level, class = class, guid = guid,
        note = "", onote = "", online = online ~= false }
end
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
    local m = roster[i]
    if not m then return nil end
    return m.name, m.rank, m.idx, m.level, nil, "Shattrath", m.note, m.onote, m.online, 0, m.class, nil, nil, nil, nil, nil, m.guid
end
env.GetGuildRosterLastOnline = function(i) local m = roster[i]; return 0, 0, m.days or 0, 0 end
local guildEvents = {}
env.GetNumGuildEvents = function() return #guildEvents end
env.GetGuildEventInfo = function(i) return unpack(guildEvents[i]) end

local sent = {}
env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, body, channel, target) sent[#sent + 1] = { prefix, body, channel, target } end,
}
local addons = {}
env.C_AddOns = { IsAddOnLoaded = function(n) return addons[n] or false end }

for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/GuildRoster.lua", "Modules/GuildRosterSync.lua",
                     "Modules/GuildRosterUI.lua", "Modules/GuildRosterPurge.lua" }) do
    W.load(f)
end
local WM = W.WM
local GR, Sync = WM.modules.GuildRoster, WM.GuildRoster.Sync
env.WatchingMachineDB = { theme = "Default" }
local printed = {}
WM.Print = function(_, m) printed[#printed + 1] = m end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- the setup page works before the module has started ----
do
    local rows = 0
    local L = setmetatable({}, { __index = function() return function() rows = rows + 1; return { editBox = W.NewFrame() } end end })
    local ok, err = pcall(GR.SetupPage, GR, L)
    check("setup page builds before start (" .. tostring(err) .. ")", ok and rows > 5)
end

GR:Initialize()
-- ---- first scan: everyone recorded quietly ----
roster = {
    Member("Me", "Officer", 1, 70, "MAGE", "Player-1-ME"),
    Member("Tank", "Raider", 2, 70, "WARRIOR", "Player-1-TANK"),
    Member("Healer", "Raider", 2, 70, "PRIEST", "Player-1-HEAL"),
    Member("Alty", "Member", 3, 60, "ROGUE", "Player-1-ALTY", false),
}
GR:Scan()
local g = GR:Guild()
check("first scan: members recorded", g.members["Tank-SpineShatter"] and g.members["Alty-SpineShatter"])
check("first scan: just one info line", #g.log == 1 and g.log[1].kind == "info")
check("first scan: join dates unknown", g.members["Tank-SpineShatter"].join.date == "")

-- ---- changes ----
clock = clock + 3600
guildEvents = {
    { "invite", "Me", "Newbie", nil, 0, 0, 0, 1 },
    { "promote", "Me", "Healer", "Officer", 0, 0, 0, 1 },
    { "remove", "Me", "Alty", nil, 0, 0, 0, 1 },
}
GR:ReadEventLog()
roster[3].idx, roster[3].rank = 1, "Officer"
roster[2].level = 70
roster[2].note = "MT"
table.remove(roster, 4)                                 -- Alty kicked
roster[#roster + 1] = Member("Newbie", "Member", 3, 12, "HUNTER", "Player-1-NEW")
GR:Scan()
local kinds = {}
for _, e in ipairs(g.log) do kinds[e.kind] = e.text end
check("join, with the inviter", kinds.join and kinds.join:find("Newbie joined the guild %(invited by Me%)"))
check("join date today, verified", g.members["Newbie-SpineShatter"].join.verified
    and g.members["Newbie-SpineShatter"].join.date == os.date("%Y%m%d", clock))
check("promotion, with who did it", kinds.promote and kinds.promote:find("Healer was promoted from Raider to Officer by Me", 1, true))
check("promotion date set", g.members["Healer-SpineShatter"].promo.date == os.date("%Y%m%d", clock))
check("kick, with who kicked", kinds.kick and kinds.kick:find("Alty was removed from the guild by Me", 1, true))
check("kicked player kept as a former member", g.former["Alty-SpineShatter"] and not g.members["Alty-SpineShatter"])
check("public note change logged", kinds.note and kinds.note:find("Tank's public note", 1, true))

-- Rename: same GUID
clock = clock + 60
roster[2].name = "Tankier-SpineShatter"
GR:Scan()
check("rename follows the GUID", g.members["Tankier-SpineShatter"] and not g.members["Tank-SpineShatter"]
    and g.log[1].kind == "rename")

-- A partial roster from the server is ignored
local saved = roster
roster = { saved[1] }
for i = 1, 20 do g.members["Filler" .. i .. "-SpineShatter"] = GR.NewRecord("Filler" .. i .. "-SpineShatter") end
local n = #g.log
GR:Scan()
check("half the guild gone at once: scan skipped", #g.log == n and g.members["Healer-SpineShatter"])
for i = 1, 20 do g.members["Filler" .. i .. "-SpineShatter"] = nil end
roster = saved

-- ---- local edits, and what they send ----
GR:Scan()
Sync.users = {}
Sync:ClearQueue()
sent = {}
local function Sent() Sync:FlushForTests(); local s = sent; sent = {}; return s end

GR:SetJoinDate("Healer", "20250307")
local s = Sent()
check("join date edit sent as GRM_JD", s[1] and s[1][1] == "GRM_SYNC" and s[1][3] == "GUILD"
    and s[1][2] == "GRM_JD?4?Healer-SpineShatter?20250307?" .. clock)
GR:SetCustomNote("Healer", "Holy priest | raid lead?")
s = Sent()
check("custom note: GRM_CNOTE1, separators taken out", s[1] and s[1][2] == "GRM_CNOTE1?4?Healer-SpineShatter~|~" .. clock .. "~|~Holy priest   raid lead")
local long = string.rep("a", 120)
local bodies = Sync:CustomNoteBodies("Healer-SpineShatter", long, clock)
check("long note: two parts at 99", #bodies == 2 and bodies[1]:find("^GRM_CNOTE2") and bodies[2]:find("^GRM_CNOTE3")
    and bodies[2] == "GRM_CNOTE3?4?Healer-SpineShatter~|~" .. string.rep("a", 21))
GR:AddAlt("Healer", "Newbie")
s = Sent()
check("add alt: GRM_ADDALT with the whole group, ending in X",
    s[1] and s[1][2] == "GRM_ADDALT?4?S?Healer-SpineShatter?#?" .. clock .. "?1?Newbie-SpineShatter?Healer-SpineShatter?Newbie-SpineShatter?X")
GR:SetMain("Healer")
s = Sent()
check("set main: GRM_MAIN", s[1] and s[1][2] == "GRM_MAIN?4?Healer-SpineShatter?" .. clock)
GR:SetBirthday("Newbie", 14, 2)
s = Sent()
check("birthday: day, month, then time", s[1] and s[1][2] == "GRM_BDAY?4?Newbie-SpineShatter?14?2?" .. clock)
check("birthday shared with the alt group", g.members["Healer-SpineShatter"].bday.d == 14)
local alts, main = GR:AltsOf("Newbie")
check("alts and main", alts[1] == "Healer-SpineShatter" and main == "Healer-SpineShatter")

-- Bans: whispered to those allowed ban data
Sync.users["Tankier-SpineShatter"] = { ok = true, enabled = true, banRank = 2, patchDay = Sync:PatchDay() }
roster[2].idx, roster[2].rank = 1, "Officer"
GR:Scan()
GR:SetBan("Badguy", true, "ninja~looted")
s = Sent()
check("ban someone outside the guild: a former-member record", g.former["Badguy-SpineShatter"] and g.former["Badguy-SpineShatter"].ban.on)
check("ban whispered, ~|~ fields, placeholders", s[1] and s[1][3] == "WHISPER" and s[1][4] == "Tankier-SpineShatter"
    and s[1][2] == "GRM_BAN?1?Badguy-SpineShatter~|~" .. clock .. "~|~ninja looted~|~WARRIOR~|~#~|~false")

-- A banned player rejoining: warned
roster[#roster + 1] = Member("Badguy", "Member", 3, 70, "ROGUE", "Player-1-BAD")
g.former["Badguy-SpineShatter"].guid = "Player-1-BAD"
GR:Scan()
check("banned player rejoins: red warning", g.log[1].kind == "ban" and g.log[1].text:find("is on the ban list"))
check("banned and in the guild", GR:BannedInGuild()[1] == "Badguy-SpineShatter")

-- ---- receiving ----
Sync.users = {}
local function User(body, sender)
    W.fire(Sync.eventFrame, "OnEvent", "CHAT_MSG_ADDON", "GRMUSER", body, "GUILD", sender)
end
local function Msg(body, sender, channel)
    W.fire(Sync.eventFrame, "OnEvent", "CHAT_MSG_ADDON", "GRM_SYNC", body, channel or "GUILD", sender)
end
-- Not announced: ignored
Msg("GRM_JD?4?Tankier-SpineShatter?20240101?" .. (clock + 10), "Tankier-SpineShatter")
check("no REG yet: edits ignored", g.members["Tankier-SpineShatter"].join.date ~= "20240101")
-- Announced with another release: we switch to theirs, then listen
User("REG?R1.99500?1800000500?4?1?false?true?true", "Tankier-SpineShatter")
check("learned the guild's Guild Roster Manager release", Sync:PatchDay() == 1800000500 and Sync.users["Tankier-SpineShatter"].ok)
check("and announced ourselves with it", (function()
    Sync:FlushForTests()
    for _, m in ipairs(sent) do if m[1] == "GRMUSER" and m[2]:find("^REG%?WM") and m[2]:find("%?1800000500%?") then return true end end
end)())
sent = {}
Msg("GRM_JD?4?Tankier-SpineShatter?20240101?" .. (clock + 10), "Tankier-SpineShatter")
check("join date from a guildmate", g.members["Tankier-SpineShatter"].join.date == "20240101"
    and g.members["Tankier-SpineShatter"].join.epoch == clock + 10)
Msg("GRM_JD?4?Tankier-SpineShatter?20230101?" .. (clock + 5), "Tankier-SpineShatter")
check("an older edit doesn't replace a newer one", g.members["Tankier-SpineShatter"].join.date == "20240101")
Msg("GRM_JD?0?Tankier-SpineShatter?20220101?" .. (clock + 50), "Tankier-SpineShatter")
check("R below our rank: ignored", g.members["Tankier-SpineShatter"].join.date == "20240101")
Msg("GRM_CNOTE2?4?Tankier-SpineShatter~|~" .. (clock + 20) .. "~|~" .. string.rep("b", 99), "Tankier-SpineShatter")
Msg("GRM_CNOTE3?4?Tankier-SpineShatter~|~cc", "Tankier-SpineShatter")
check("a long note in two parts", g.members["Tankier-SpineShatter"].custom.text == string.rep("b", 99) .. "cc"
    and g.members["Tankier-SpineShatter"].custom.editor == "Tankier-SpineShatter")
Msg("GRM_CNOTE1?4?Tankier-SpineShatter~|~" .. (clock + 30) .. "~|~#", "Tankier-SpineShatter")
check("# clears a note", g.members["Tankier-SpineShatter"].custom.text == "")
Msg("GRM_ADDALT?4?S?Me-SpineShatter?Me-SpineShatter?" .. (clock + 40) .. "?1?Tankier-SpineShatter?Me-SpineShatter?Tankier-SpineShatter?X",
    "Tankier-SpineShatter")
local ma, mm = GR:AltsOf("Me")
check("alt group from a guildmate", ma[1] == "Tankier-SpineShatter" and mm == "Me-SpineShatter")
Msg("GRM_RMVALT?4?Tankier-SpineShatter?" .. (clock + 41) .. "?Me-SpineShatter", "Tankier-SpineShatter")
check("alt removed by a guildmate; a main alone keeps their group", #GR:AltsOf("Me") == 0 and select(2, GR:AltsOf("Me")) == "Me-SpineShatter")
Msg("GRM_BDAY?4?Me-SpineShatter?3?9?" .. (clock + 42), "Tankier-SpineShatter")
check("birthday from a guildmate", g.members["Me-SpineShatter"].bday.d == 3 and g.members["Me-SpineShatter"].bday.m == 9)
Msg("GRM_BAN?1?Villain-SpineShatter~|~" .. (clock + 43) .. "~|~###~|~ROGUE~|~#~|~false", "Tankier-SpineShatter", "WHISPER")
check("ban from an officer, ### is no reason", g.former["Villain-SpineShatter"] and g.former["Villain-SpineShatter"].ban.on
    and g.former["Villain-SpineShatter"].ban.reason == "" and g.former["Villain-SpineShatter"].class == "ROGUE")
Msg("GRM_UNBAN?1?Villain-SpineShatter?" .. (clock + 44), "Tankier-SpineShatter", "WHISPER")
check("unban", not g.former["Villain-SpineShatter"].ban.on and g.former["Villain-SpineShatter"].ban.unbanned)
-- A raider can't ban
g.members["Newbie-SpineShatter"].rankIndex = 3
User("REG?R1.99500?1800000500?4?1?false?true?true", "Newbie-SpineShatter")
Msg("GRM_BAN?4?Tankier-SpineShatter~|~" .. (clock + 45) .. "~|~griefer~|~WARRIOR~|~#~|~false", "Newbie-SpineShatter", "WHISPER")
check("ban from below the ban rank: ignored", not g.members["Tankier-SpineShatter"].ban.on)
-- Full-sync messages are left alone
Msg("GRM_WHOISLEADER?4?4?1?4?4?4", "Tankier-SpineShatter")
check("full-sync messages ignored (no reply)", (function() Sync:FlushForTests(); for _, m in ipairs(sent) do if m[2]:find("IAMLEADER") then return false end end return true end)())
-- REQ: we answer with REG
sent = {}
User("REQ?", "Healer-SpineShatter")
Sync:FlushForTests()
check("REQ answered with REG", sent[1] and sent[1][1] == "GRMUSER" and sent[1][2]:find("^REG%?WM"))

-- ---- Guild Roster Manager running here: we stay quiet ----
addons.Guild_Roster_Manager = true
sent = {}
GR:SetJoinDate("Healer", "20250308")
Sync:FlushForTests()
check("GRM loaded on this character: nothing sent", #sent == 0)
addons.Guild_Roster_Manager = false

-- ---- import from Guild Roster Manager's saved data ----
env.GRM_GuildMemberHistory_Save = { ["The Watchers"] = {
    ["Healer-SpineShatter"] = {
        joinDateHist = { { 1, 2, 2020, "20200201", clock + 1000, true, 1 } },
        rankHist = { { "Officer", 5, 6, 2021, "20210605", clock + 1000, true } },
        customNote = { true, clock + 1000, "Someone-SpineShatter", "imported note" },
        birthdayInfo = { date = { 7, 8 }, timeUpdated = clock + 1000 },
    },
} }
env.GRM_PlayersThatLeftHistory_Save = { ["The Watchers"] = {
    ["Oldie-SpineShatter"] = { level = 70, rankName = "Raider", bannedInfo = { true, clock, false, "GM-SpineShatter" }, reasonBanned = "drama" },
} }
env.GRM_Alts = { ["The Watchers"] = {} }
check("GRM data seen", Sync.GRMDataAvailable())
local im, imf = Sync:ImportFromGRM()
local h = g.members["Healer-SpineShatter"]
check("import: dates, note, birthday", im == 1 and h.join.date == "20200201" and h.promo.date == "20210605"
    and h.custom.text == "imported note" and h.bday.d == 7)
check("import: former member with their ban", imf == 1 and g.former["Oldie-SpineShatter"].ban.on
    and g.former["Oldie-SpineShatter"].ban.reason == "drama")

-- ---- the window ----
GR:ShowTab("roster")
local lines = GR:TabLines()
check("roster tab lists members", #lines >= 4 and lines[1].rec)
-- Alts under their main
if not (g.members["Newbie-SpineShatter"].group and g.members["Newbie-SpineShatter"].group == g.members["Healer-SpineShatter"].group) then
    GR:AddAlt("Healer", "Newbie")
end
GR:SetMain("Healer")
Sync:ClearQueue()
local function Find(ls, name) for i, l in ipairs(ls) do if l.rec and l.rec.name == name then return i, l end end end
lines = GR:TabLines()
local hi, hl = Find(lines, "Healer-SpineShatter")
check("main listed with a +", hl and hl.toggle == "+" and hl.main == "Healer-SpineShatter" and hl.text:find("1 alt", 1, true))
check("closed: the alt isn't listed on its own", Find(lines, "Newbie-SpineShatter") == nil)
GR:ToggleAlts("Healer-SpineShatter")
lines = GR:TabLines()
hi, hl = Find(lines, "Healer-SpineShatter")
local ni, nl = Find(lines, "Newbie-SpineShatter")
check("opened: a - and the alt right under its main, indented", hl.toggle == "-" and ni == hi + 1 and nl.indent == 1)
GR:ToggleAlts("Healer-SpineShatter")
check("closed again", Find(GR:TabLines(), "Newbie-SpineShatter") == nil)
GR.searchText = "newb"
lines = GR:TabLines()
hi, hl = Find(lines, "Healer-SpineShatter")
ni = Find(lines, "Newbie-SpineShatter")
check("searching for an alt shows its main, opened", hl and hl.toggle == "-" and ni == hi + 1)
GR.searchText = nil
GR.DB().groupAlts = false
lines = GR:TabLines()
ni, nl = Find(lines, "Newbie-SpineShatter")
check("grouping off: alts listed on their own", nl and nl.indent == 0 and not (select(2, Find(lines, "Healer-SpineShatter")) or {}).toggle)
GR.DB().groupAlts = true

-- Names finish as you type in the add-alt box
local matches = GR:NameMatches("ne", "members")
check("name matches by start of name", #matches == 1 and matches[1].name == "Newbie-SpineShatter")
check("no text, no matches", #GR:NameMatches("", "members") == 0)
check("former members only when asked", #GR:NameMatches("old", "members") == 0 and #GR:NameMatches("old", "all") == 1)
local popup = env.CreateFrame("Frame")
popup.which = "WM_GUILDROSTER_INPUT"
popup.data = { complete = function(t) return GR:NameMatches(t, "members") end }
local box = env.CreateFrame("EditBox", nil, popup)
GR.HookCompletion(box)
box:SetText("Ne")
GR.CompleteName(box, true)
check("typing fills in the rest of the name", box:GetText() == "Newbie")
check("matches listed under the box", env.WM_GuildRosterSuggest and env.WM_GuildRosterSuggest:IsShown()
    and env.WM_GuildRosterSuggest.rows[1].value == "Newbie")
box:SetText("Ne")
GR.CompleteName(box, true)
check("deleting doesn't fill it back in", box:GetText() == "Ne")
box:SetText("Zz")
GR.CompleteName(box, true)
check("nothing matches: list hidden", not env.WM_GuildRosterSuggest:IsShown())
popup.data = { }
box:SetText("Ne")
GR.CompleteName(box, true)
check("a box without completion is left alone", box:GetText() == "Ne")

-- Alts and mains from guild notes
local function Add(name, note, onote, rank, level)
    local r = GR.NewRecord(name .. "-SpineShatter")
    r.note, r.onote, r.rankIndex, r.level = note or "", onote or "", rank or 3, level or 70
    g.members[r.name] = r
    return r
end
Add("Mainy"); Add("Alta", "Mainy alt"); Add("Altb", "", "alt of MAINY")
Add("Solo", "Raid alt"); Add("Paira", "Pairb's Alt [BS]375"); Add("Pairb")
Add("Grpa"); Add("Grpb", "Main: Grpa")
GR:AddAlt("Grpa", "Grpb"); GR:UnsetMain("Grpa")
Add("Taken", "Mainy alt")
Add("Other"); Add("Otheralt"); GR:AddAlt("Other", "Otheralt"); GR:SetMain("Other")
g.members["Taken-SpineShatter"].group = nil
GR:AddAlt("Other", "Taken")
local linked = GR:AltsFromNotes()
local function MainOfName(n) local r = g.members[n .. "-SpineShatter"]; local gr = r.group and g.groups[r.group]; return gr and gr.main end
check("notes: \"Name alt\" makes Name the main", MainOfName("Alta") == "Mainy-SpineShatter" and MainOfName("Mainy") == "Mainy-SpineShatter")
check("notes: \"alt of NAME\" in the officer note, any case", MainOfName("Altb") == "Mainy-SpineShatter")
check("notes: \"Name's Alt [..]\"", MainOfName("Paira") == "Pairb-SpineShatter")
check("notes: a group with no main gets the one its note names", MainOfName("Grpb") == "Grpa-SpineShatter")
check("notes: names that aren't members are ignored", g.members["Solo-SpineShatter"].group == nil)
check("notes: nobody moved out of a group with another main", MainOfName("Taken") == "Other-SpineShatter")
check("notes: count of characters linked", linked == 4)
check("notes: nothing new the second time", GR:AltsFromNotes() == 0)
Sync:ClearQueue()

-- A group with no main is listed under its highest-ranked character
Add("Lowrank", "", "", 4, 70); Add("Highrank", "", "", 2, 60)
GR:AddAlt("Lowrank", "Highrank")
GR:UnsetMain("Lowrank")
lines = GR:TabLines()
local _, hr = Find(lines, "Highrank-SpineShatter")
check("no main: listed under the highest rank, marked", hr and hr.toggle == "+" and hr.text:find("no main set", 1, true))
check("no main: the other character is under it", Find(lines, "Lowrank-SpineShatter") == nil)
check("lead is the main when there is one", GR:GroupLead(g, g.groups[g.members["Alta-SpineShatter"].group]).name == "Mainy-SpineShatter")
Sync:ClearQueue()
-- Purge: whole players offline long enough, one removal per click
local canRemove, uninvited = true, {}
env.CanGuildRemove = function() return canRemove end
env.GuildUninvite = function(n) uninvited[#uninvited + 1] = n end
env.InCombatLockdown = function() return false end
for _, r in pairs(g.members) do r.offlineHours = 0 end
local function Off(n, days) g.members[n .. "-SpineShatter"].offlineHours = days * 24; g.members[n .. "-SpineShatter"].online = false end
-- Mainy's group: all away 40+ days; Other's group: an alt on 2 days ago
Off("Mainy", 45); Off("Alta", 60); Off("Altb", 41)
Off("Other", 90); Off("Otheralt", 2); Off("Taken", 90)
Off("Solo", 31)
Off("Highrank", 100); Off("Lowrank", 100)
g.members["Highrank-SpineShatter"].rankIndex = 1
Off("Paira", 10); Off("Pairb", 50)
local cands = GR:PurgeCandidates(30, 1)
local byLead = {}
for _, c in ipairs(cands) do byLead[c.lead.name] = c end
check("purge: a player whose main and alts are all away is listed", byLead["Mainy-SpineShatter"] and #byLead["Mainy-SpineShatter"].recs == 3
    and byLead["Mainy-SpineShatter"].days == 41)
check("purge: an alt on recently keeps the whole player", byLead["Other-SpineShatter"] == nil)
check("purge: an alt on within the days keeps the main", byLead["Pairb-SpineShatter"] == nil)
check("purge: a single character away long enough", byLead["Solo-SpineShatter"] ~= nil)
check("purge: a protected rank on any character keeps the player", byLead["Highrank-SpineShatter"] == nil)
check("purge: ranks at or above yours aren't listed", (function()
    for _, c in ipairs(cands) do for _, r in ipairs(c.recs) do if (r.rankIndex or 99) <= 1 then return false end end end
    return true end)())
check("purge: you're never listed", (function()
    for _, c in ipairs(cands) do for _, r in ipairs(c.recs) do if r.name == GR.MyName() then return false end end end
    return true end)())
check("purge: the main is first", byLead["Mainy-SpineShatter"].recs[1].name == "Mainy-SpineShatter")
check("purge: longest away first", cands[1].days >= cands[#cands].days)
local P = GR.Purge
P:Find(30, 1)
for _, e in ipairs(P.list) do if e.lead.name ~= "Mainy-SpineShatter" then e.keep = true end end
check("purge: counts what's ticked", select(2, P:Counts()) == 3)
check("purge: one removal per click", P:RemoveNext() == true and #uninvited == 1 and uninvited[1] == "Mainy")
P:RemoveNext(); P:RemoveNext()
check("purge: the whole player removed over three clicks", #uninvited == 3 and P:Counts() == 0)
check("purge: nothing more to remove", P:RemoveNext() == false and #uninvited == 3)
-- Someone comes back between Find and the click
P:Find(30, 1)
for _, e in ipairs(P.list) do e.keep = e.lead.name ~= "Solo-SpineShatter" end
g.members["Solo-SpineShatter"].online = true
check("purge: a player who came back is kept", P:RemoveNext() == false and #uninvited == 3 and P.list[1].skipped ~= nil or (function()
    for _, e in ipairs(P.list) do if e.lead.name == "Solo-SpineShatter" then return e.skipped end end end)())
g.members["Solo-SpineShatter"].online = false
canRemove = false
P:Find(30, 1)
check("purge: not allowed to remove: nothing removed", P:RemoveNext() == false and #uninvited == 3)
check("purge: not allowed: Can say no", GR:CanPurge() == false)
canRemove = true
GR:TogglePurge()
check("purge window opens", env.WM_GuildRosterPurge and env.WM_GuildRosterPurge:IsShown())
GR:HidePurge()
check("purge window closes", not env.WM_GuildRosterPurge:IsShown())

-- Leave the roster as the scans expect it
for _, n in ipairs({ "Mainy", "Alta", "Altb", "Solo", "Paira", "Pairb", "Grpa", "Grpb", "Taken", "Other", "Otheralt", "Lowrank", "Highrank" }) do
    local r = g.members[n .. "-SpineShatter"]
    if r and r.group then g.groups[r.group] = nil end
    g.members[n .. "-SpineShatter"] = nil
end
GR.tab = "log"
check("log tab lists entries", #GR:TabLines() == #g.log)
GR.tab = "sync"
local syncText = {}
for _, l in ipairs(GR:TabLines()) do syncText[#syncText + 1] = l.text end
check("sync tab lists guildmates", table.concat(syncText, "\n"):find("Tankier") ~= nil)
GR.selected = "Healer-SpineShatter"
GR:RefreshList()
check("details pane shows the selected member", env.WM_GuildRosterFrame.details.body:GetText():find("Joined", 1, true))

-- ---- off means off ----
WM:SetModuleOn("GuildRoster", false)
check("off: window hidden", not env.WM_GuildRosterFrame:IsShown())
n = #g.log
roster[#roster + 1] = Member("Ghost", "Member", 3, 70, "MAGE", "Player-1-GHOST")
GR:Scan()
check("off: no scanning", #g.log == n and not g.members["Ghost-SpineShatter"])
Msg("GRM_JD?4?Healer-SpineShatter?20190101?" .. (clock + 5000), "Tankier-SpineShatter")
check("off: edits from guildmates ignored", g.members["Healer-SpineShatter"].join.date ~= "20190101")
sent = {}
Sync:Announce()
Sync:FlushForTests()
check("off: nothing sent", #sent == 0)
WM:SetModuleOn("GuildRoster", true)
GR:Scan()
check("on again: scanning", g.members["Ghost-SpineShatter"] ~= nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
