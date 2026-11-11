-- Watching Machine: Roster Manager's officer tools
--   * Promote / Demote a member (one click each; the game needs the click)
--   * Promotion suggestions: after N days at a rank (a setting per rank),
--     the log says they're ready for the next one, and "Ready to promote"
--     on the roster's Show filter lists them
--   * Export the roster (or former members) as CSV
--   * Join dates stamped into a note ("Joined 15 Jan 26"), by hand for
--     everyone or by itself when someone joins
--   * Guild anniversaries and birthdays: said at login on the day (and to
--     guild chat if you like)

local AddonName, WM = ...
local GR = WM.GuildRoster
local Tools = {}
GR.Tools = Tools

local function DB() return GR.DB() end
local function On() return WM:IsModuleOn("GuildRoster") end
local function Now() return time() end
local function Short(n) return GR.Short(n) end

-- "YYYYMMDD" -> time at noon, or nil
local function StampTime(s)
    local y, m, d = tostring(s or ""):match("^(%d%d%d%d)(%d%d)(%d%d)$")
    if not y then return nil end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end
Tools.StampTime = StampTime

local function MyRank()
    local idx
    if GetGuildInfo then idx = select(3, GetGuildInfo("player")) end
    return tonumber(idx) or 0
end

local function NumRanks() return tonumber(GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0 end

local function RankName(g, index)
    local n = g and g.ranks and g.ranks[index]
    if n and n ~= "" then return n end
    local f = GuildControlGetRankName and GuildControlGetRankName(index + 1)
    return type(f) == "string" and f or ("Rank " .. index)
end
Tools.RankName = RankName

-- ============================================
-- PROMOTE / DEMOTE
-- ============================================

local function Can(fn)
    local f = rawget(_G, fn)
    if not f then return false end
    local ok, v = pcall(f)
    return ok and v and true or false
end

-- Can we promote / demote this member? (the game's permission, and ranks below ours)
function GR:CanPromote(rec)
    if not On() or not rec or rec.rankIndex == nil or rec.rankIndex == 99 then return false end
    if not Can("CanGuildPromote") then return false end
    return rec.rankIndex - 1 > MyRank()
end

function GR:CanDemote(rec)
    if not On() or not rec or rec.rankIndex == nil or rec.rankIndex == 99 then return false end
    if not Can("CanGuildDemote") then return false end
    return rec.rankIndex > MyRank() and rec.rankIndex < NumRanks() - 1
end

local function Target(rec)
    local short = Short(rec.name)
    return GR.FullName(short) == rec.name and short or rec.name
end

function GR:Promote(name)
    local rec = self:Find(name)
    if not self:CanPromote(rec) then return false end
    local f = rawget(_G, "GuildPromote") or (C_GuildInfo and C_GuildInfo.Promote)
    if not f then return false end
    f(Target(rec))
    if GR.AskRoster then C_Timer.After(1, GR.AskRoster) end
    return true
end

function GR:Demote(name)
    local rec = self:Find(name)
    if not self:CanDemote(rec) then return false end
    local f = rawget(_G, "GuildDemote") or (C_GuildInfo and C_GuildInfo.Demote)
    if not f then return false end
    f(Target(rec))
    if GR.AskRoster then C_Timer.After(1, GR.AskRoster) end
    return true
end

-- ============================================
-- PROMOTION SUGGESTIONS
-- ============================================
-- DB().promoDays[rankIndex] = days at that rank before the next one

-- Days at their current rank (from the promotion date, else the join date)
function Tools.DaysAtRank(rec)
    local t = StampTime(rec.promo and rec.promo.date) or StampTime(rec.join and rec.join.date)
    if not t then return nil end
    return math.floor((Now() - t) / 86400)
end

-- The rank they're ready for, or nil
function GR:ReadyFor(rec)
    local days = DB().promoDays and tonumber(DB().promoDays[rec.rankIndex])
    if not days or days <= 0 or not rec.rankIndex or rec.rankIndex <= 0 then return nil end
    local at = Tools.DaysAtRank(rec)
    if not at or at < days then return nil end
    return rec.rankIndex - 1, at
end

-- After a scan: a log line for each member newly ready (once per rank)
function Tools:CheckSuggestions()
    local g = GR:Guild()
    if not g then return 0 end
    local n = 0
    for _, rec in pairs(g.members) do
        local next, at = GR:ReadyFor(rec)
        if next and rec.suggestedFor ~= rec.rankIndex then
            rec.suggestedFor = rec.rankIndex
            GR:Log("suggest", Short(rec.name) .. " has been " .. RankName(g, rec.rankIndex) .. " for " .. at
                .. " days: ready for " .. RankName(g, next) .. "." .. GR:AltSuffix(rec.name, g), g)
            n = n + 1
        elseif not next and rec.suggestedFor and rec.suggestedFor ~= rec.rankIndex then
            rec.suggestedFor = nil
        end
    end
    return n
end

-- ============================================
-- EXPORT
-- ============================================

local CsvField = WM.CsvField

-- The roster (former = former members) as CSV
function GR:ExportCSV(former)
    local g = self:Guild()
    if not g then return "", 0 end
    local src = former and g.former or g.members
    local list = {}
    for _, rec in pairs(src) do list[#list + 1] = rec end
    table.sort(list, GR.RosterOrder or function(a, b) return a.name < b.name end)
    local head = { "Name", "Main", "Rank", "Level", "Class", "Joined", "Promoted", "DaysOffline", "Note", "OfficerNote",
        "CustomNote", "Birthday", "Banned", "BanReason" }
    if former then head[#head + 1] = "Left" end
    local lines = { table.concat(head, ",") }
    for _, rec in ipairs(list) do
        local grp = rec.group and g.groups[rec.group]
        local row = {
            Short(rec.name), grp and grp.main ~= "" and Short(grp.main) or "", rec.rankName or "", rec.level or "",
            rec.class or "", GR.PrettyDate(rec.join and rec.join.date or ""), GR.PrettyDate(rec.promo and rec.promo.date or ""),
            rec.online and 0 or math.floor((rec.offlineHours or 0) / 24), rec.note or "", rec.onote or "",
            rec.custom and rec.custom.text or "",
            (rec.bday and (rec.bday.d or 0) > 0) and (rec.bday.d .. "/" .. rec.bday.m) or "",
            rec.ban and rec.ban.on and "yes" or "", rec.ban and rec.ban.reason or "",
        }
        if former then row[#row + 1] = rec.leftAt and date("%Y-%m-%d", rec.leftAt) or "" end
        for i, v in ipairs(row) do row[i] = CsvField(v) end
        lines[#lines + 1] = table.concat(row, ",")
    end
    return table.concat(lines, "\n"), #list
end

-- ============================================
-- JOIN DATES IN NOTES
-- ============================================

local NOTE_MAX = 31

function Tools.StampText(rec)
    local t = StampTime(rec.join and rec.join.date)
    if not t then return nil end
    return "Joined " .. date("%d %b %y", t)
end

-- The guild roster index of a member (for writing their note)
local function RosterIndex(name)
    local n = tonumber(GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, n do
        local rn = GetGuildRosterInfo(i)
        if rn and GR.FullName(rn) == name then return i end
    end
end

-- The note text to write, or nil (already stamped, no date, or too long)
function Tools.Stamped(rec, officer)
    local stamp = Tools.StampText(rec)
    if not stamp then return nil end
    local note = (officer and rec.onote or rec.note) or ""
    if note:find("Joined", 1, true) then return nil end
    local text = (note == "") and stamp or (note .. " " .. stamp)
    if #text > NOTE_MAX then return nil end
    return text
end

function Tools.CanWriteNotes(officer)
    if officer then
        local f = rawget(_G, "CanEditOfficerNote") or (C_GuildInfo and C_GuildInfo.CanEditOfficerNote)
        if not f then return false end
        local ok, v = pcall(f)
        return ok and v and true or false
    end
    return Can("CanEditPublicNote")
end

local function WriteNote(index, text, officer)
    local f = officer and (rawget(_G, "GuildRosterSetOfficerNote")) or rawget(_G, "GuildRosterSetPublicNote")
    if not f or not index then return false end
    f(index, text)
    return true
end

-- Stamp one member now (a new join, with auto-stamp on)
function Tools:StampOne(rec)
    local officer = DB().stampNote ~= "public"
    if not Tools.CanWriteNotes(officer) then return false end
    local text = Tools.Stamped(rec, officer)
    if not text then return false end
    return WriteNote(RosterIndex(rec.name), text, officer)
end

-- Everyone with a join date and no stamp yet, a few a second
function Tools:StampAll()
    local officer = DB().stampNote ~= "public"
    if not Tools.CanWriteNotes(officer) then
        WM:Print("Roster Manager: you can't edit " .. (officer and "officer" or "public") .. " notes.")
        return 0
    end
    local g = GR:Guild()
    local todo = {}
    for _, rec in pairs(g and g.members or {}) do
        if Tools.Stamped(rec, officer) then todo[#todo + 1] = rec end
    end
    table.sort(todo, function(a, b) return a.name < b.name end)
    local i = 0
    local function NextOne()
        i = i + 1
        local rec = todo[i]
        if not rec or not On() then
            if rec == nil and i > 1 then WM:Print("Roster Manager: stamped " .. (i - 1) .. " join dates.") end
            if GR.AskRoster then GR.AskRoster() end
            return
        end
        local text = Tools.Stamped(rec, officer)
        if text then WriteNote(RosterIndex(rec.name), text, officer) end
        if C_Timer then C_Timer.After(0.3, NextOne) else NextOne() end
    end
    if #todo > 0 then NextOne() end
    return #todo
end

-- ============================================
-- ANNIVERSARIES AND BIRTHDAYS
-- ============================================

-- Today's guild anniversaries and birthdays: { text } once a year each
function Tools:Celebrations(today)
    local g = GR:Guild()
    if not g then return {} end
    today = today or Now()
    local d, m, y = tonumber(date("%d", today)), tonumber(date("%m", today)), tonumber(date("%Y", today))
    local out, doneGroups = {}, {}
    for _, rec in pairs(g.members) do
        local jt = StampTime(rec.join and rec.join.date)
        if jt and rec.join.verified ~= false then
            local jd, jm, jy = tonumber(date("%d", jt)), tonumber(date("%m", jt)), tonumber(date("%Y", jt))
            if jd == d and jm == m and y > jy and rec.annivYear ~= y then
                rec.annivYear = y
                local years = y - jy
                out[#out + 1] = { kind = "anniversary", text = "Today is " .. Short(rec.name) .. "'s " .. years
                    .. "-year" .. " anniversary in the guild!" }
            end
        end
        local b = rec.bday
        local key = rec.group or rec.name
        if b and (b.d or 0) == d and (b.m or 0) == m and not doneGroups[key] then
            doneGroups[key] = true
            local grp = rec.group and g.groups[rec.group]
            local who = (grp and grp.main ~= "" and grp.main) or rec.name
            local whoRec = g.members[who] or rec
            if whoRec.bdayYear ~= y then
                whoRec.bdayYear = y
                out[#out + 1] = { kind = "anniversary", text = "Happy birthday, " .. Short(who) .. "!" }
            end
        end
    end
    return out
end

function Tools:CheckCelebrations()
    if not DB().anniversaries then return 0 end
    local list = self:Celebrations()
    local g = GR:Guild()
    for _, c in ipairs(list) do
        GR:Log(c.kind, c.text, g)
        if DB().anniversaryGuild and SendChatMessage and IsInGuild and IsInGuild() then SendChatMessage(c.text, "GUILD") end
    end
    return #list
end

-- After each scan: suggestions, and (once a day) anniversaries
function Tools:AfterScan(newJoins)
    if not On() then return end
    self:CheckSuggestions()
    local today = date("%Y%m%d")
    if self.celebrated ~= today then
        self.celebrated = today
        self:CheckCelebrations()
    end
    if DB().autoStamp then
        for _, rec in ipairs(newJoins or {}) do self:StampOne(rec) end
    end
end
