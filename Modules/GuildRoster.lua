-- Watching Machine: Roster Manager
-- Keeps a record of every guild member and of everyone who has left:
-- join and promotion dates (with rank history), alts and their main, a
-- custom note, birthday and the ban list. The roster is scanned every
-- little while; joins, rejoins, leaves and kicks, promotions, demotions,
-- level-ups, note changes, name changes and players back from a long
-- absence go into the guild log (and, if you like, your chat). The
-- guild's event log says who invited, kicked, promoted or demoted.
--
-- It shares those edits with guildmates running Guild Roster Manager and
-- with other Watching Machine users, over Guild Roster Manager's own
-- addon messages (GuildRosterSync.lua). The window and the guild roster's
-- hover details are in GuildRosterUI.lua.
--
-- Data model and sync formats compiled with the help of Guild Roster
-- Manager's research (Arkaan); the code is our own.

local AddonName, WM = ...
local GR = {}
WM:RegisterModule("GuildRoster", GR)
WM.GuildRoster = GR

-- ============================================
-- SETTINGS AND SAVED DATA
-- ============================================
-- WMGuildRosterDB.guilds["Guild-Realm"] is shared by every character (it's
-- about the guild, not you); everything else is this character's settings.

local DEFAULTS = {
    scanEvery = 30,         -- seconds between roster scans
    inactiveDays = 14,      -- offline this long counts as inactive
    reportReturn = true,    -- log players back after being inactive
    levelMin = 10,          -- don't report level-ups below this
    showOnLogin = true,     -- open the log at login when something changed
    hoverDetails = true,    -- details when you hover the guild roster
    promoDays = {},         -- [rank index] = days at that rank before suggesting the next
    stampNote = "officer",  -- join dates go into the "officer" or "public" note
    autoStamp = false,      -- stamp a new member's join date by itself
    anniversaries = true,   -- guild anniversaries and birthdays in the log on the day
    anniversaryGuild = false, -- ...and in guild chat
    groupAlts = true,       -- roster tab: alts listed under their main (+ / -)
    nameMain = true,        -- log lines about an alt end with "-- Main's alt"
    purgeDays = 30,         -- purge: every character offline at least this many days
    purgeProtectRank = 1,   -- purge: never ranks at or above this index (0 = guild master)
    purgeShowIgnored = false, -- purge: also list players tagged never to purge
    sync = true,            -- share edits with guildmates (GRM and WM)
    syncBans = true,
    syncCustom = true,
    syncRank = nil,         -- nil: every rank
    banRank = 1,            -- ban data with this rank index and above
    customRank = nil,       -- nil: every rank
}

-- Log kinds: title, colour, on in the log, on in chat
local KINDS = {
    join     = { "Joined",            { 0.5, 1, 0 } },
    rejoin   = { "Rejoined",          { 0.5, 1, 0 } },
    left     = { "Left",              { 0.6, 0.6, 0.6 } },
    kick     = { "Kicked",            { 0.6, 0.6, 0.6 } },
    promote  = { "Promoted",          { 1, 0.914, 0 } },
    demote   = { "Demoted",           { 0.91, 0.39, 0.05 } },
    level    = { "Level up",          { 0.2, 0.6, 1 } },
    note     = { "Public note",       { 1, 0.6, 1 } },
    onote    = { "Officer note",      { 1, 0.3, 0.93 } },
    custom   = { "Custom note",       { 0.24, 0.69, 0.49 } },
    rename   = { "Name change",       { 0.9, 0.82, 0.62 } },
    rankname = { "Rank renamed",      { 1, 1, 1 } },
    back     = { "Back from inactive", { 0, 1, 0.87 } },
    ban      = { "Ban list",          { 1, 0.2, 0.2 } },
    alts     = { "Alts",              { 0.7, 0.8, 1 } },
    dates    = { "Dates",             { 0.6, 0.85, 1 } },
    info     = { "Info",              { 1, 1, 1 } },
    suggest  = { "Ready to promote",  { 1, 0.82, 0 } },
    anniversary = { "Anniversaries and birthdays", { 1, 0.5, 0.8 } },
}
GR.KINDS = KINDS
GR.KIND_ORDER = { "join", "rejoin", "left", "kick", "promote", "demote", "level", "note", "onote", "custom",
    "rename", "rankname", "back", "ban", "alts", "dates", "info", "suggest", "anniversary" }
local LOG_MAX = 3000

local function DB()
    WMGuildRosterDB = WMGuildRosterDB or {}
    local db = WMGuildRosterDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.guilds) ~= "table" then db.guilds = {} end
    if type(db.toLog) ~= "table" then db.toLog = {} end
    if type(db.toChat) ~= "table" then db.toChat = {} end
    for k in pairs(KINDS) do
        if db.toLog[k] == nil then db.toLog[k] = true end
        if db.toChat[k] == nil then db.toChat[k] = (k ~= "level" and k ~= "info") end
    end
    return db
end
GR.DB = DB

-- ============================================
-- NAMES, DATES
-- ============================================

local function Realm()
    local r = GetRealmName and GetRealmName() or ""
    return (r:gsub("[%s%-]", ""))
end

-- "Name-Realm", as the guild roster and addon messages name players
local function FullName(n)
    if type(n) ~= "string" or n == "" then return nil end
    if n:find("-", 1, true) then return n end
    return n .. "-" .. Realm()
end
GR.FullName = FullName

local function Short(n) return n and (n:match("^([^-]+)") or n) or "?" end
GR.Short = Short

function GR.MyName() return FullName(UnitName("player")) end

local function Now() return time() end

-- "YYYYMMDD" for a time (default now)
local function Stamp(t) return date("%Y%m%d", t or Now()) end
GR.Stamp = Stamp

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
GR.MONTHS = MONTHS

-- "YYYYMMDD" -> day, month, year (nil if it isn't one)
local function SplitStamp(s)
    s = tostring(s or "")
    local y, m, d = s:match("^(%d%d%d%d)(%d%d)(%d%d)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return d, m, y
end
GR.SplitStamp = SplitStamp

-- "15 Jan 2026"
function GR.PrettyDate(s)
    local d, m, y = SplitStamp(s)
    if not d then return "unknown" end
    return string.format("%d %s %d", d, MONTHS[m], y)
end

-- Day, month, year typed by hand ("15/1/2026", "2026-01-15", "15 Jan 2026")
function GR.ParseDate(text)
    text = strtrim(tostring(text or ""))
    local y, m, d = text:match("^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)$")
    if not y then d, m, y = text:match("^(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)$") end
    if not y then
        local dd, mon, yy = text:match("^(%d%d?)%s+(%a+)%s+(%d%d%d%d)$")
        if dd then
            for i, name in ipairs(MONTHS) do
                if mon:sub(1, 3):lower() == name:lower() then d, m, y = dd, i, yy end
            end
        end
    end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return string.format("%04d%02d%02d", y, m, d)
end

-- ============================================
-- THE GUILD'S RECORDS
-- ============================================
-- g.members[fullName] / g.former[fullName] = {
--   name, guid, class, rankIndex, rankName, level, note, onote, online,
--   offlineHours, zone,
--   join  = { date "YYYYMMDD", epoch (edit time), verified },
--   promo = { date, epoch, verified },
--   joins = { { date, left } ... } newest first, ranks = { { rank, date } ... },
--   custom = { text, epoch, editor, sync },
--   bday = { d, m, epoch },
--   ban = { on, epoch, unbanned, by, reason },
--   group (alt group id), groupLeft (epoch),
--   altsAtLeaving, mainAtLeaving, timesInGuild }
-- g.groups[id] = { members = { names sorted }, main = name or "", modified, bday = { d, m, epoch } }

function GR.GuildKey()
    if not IsInGuild or not IsInGuild() then return nil end
    local name = GetGuildInfo and GetGuildInfo("player")
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. Realm()
end

function GR:Guild(key)
    key = key or GR.GuildKey()
    if not key then return nil end
    local db = DB()
    local g = db.guilds[key]
    if not g then
        g = { members = {}, former = {}, groups = {}, nextGroup = 1, log = {}, ranks = {} }
        db.guilds[key] = g
    end
    return g
end

local function NewRecord(name)
    return {
        name = name, level = 1, rankIndex = 99, rankName = "",
        join = { date = "", epoch = 0, verified = false },
        promo = { date = "", epoch = 0, verified = false },
        joins = {}, ranks = {},
        custom = { text = "", epoch = 0, editor = "", sync = true },
        bday = { d = 0, m = 0, epoch = 0 },
        ban = { on = false, epoch = 0, unbanned = false, by = "", reason = "" },
        groupLeft = 0, timesInGuild = 1,
    }
end
GR.NewRecord = NewRecord

-- A member or former member record by name: rec, isFormer
function GR:Find(name, g)
    g = g or self:Guild()
    name = FullName(name)
    if not g or not name then return nil end
    if g.members[name] then return g.members[name], false end
    if g.former[name] then return g.former[name], true end
    -- Typed without a realm, or a different case
    local lower = name:lower()
    for n, r in pairs(g.members) do if n:lower() == lower then return r, false end end
    for n, r in pairs(g.former) do if n:lower() == lower then return r, true end end
end

-- ============================================
-- THE LOG
-- ============================================

-- " -- Venitra's alt" for a character with a main (other than itself), so
-- log lines about alts say whose they are
function GR:AltSuffix(name, g)
    g = g or self:Guild()
    if not g or not DB().nameMain then return "" end
    local rec = g.members[name] or g.former[name]
    local grp = rec and rec.group and g.groups[rec.group]
    if not grp or grp.main == "" or grp.main == name then return "" end
    return " -- " .. Short(grp.main) .. "'s alt"
end

function GR:Log(kind, text, g)
    g = g or self:Guild()
    if not g then return end
    local db = DB()
    if db.toLog[kind] ~= false then
        table.insert(g.log, 1, { t = Now(), kind = kind, text = text })
        while #g.log > LOG_MAX do table.remove(g.log) end
        self.changedSinceView = true
    end
    if db.toChat[kind] and not self.silent then
        local c = KINDS[kind] and KINDS[kind][2] or { 1, 1, 1 }
        WM:Print(string.format("|cFF%02X%02X%02X%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text))
    end
    if self.OnLogChanged then self:OnLogChanged() end
end

-- ============================================
-- THE GUILD EVENT LOG (who invited, kicked, promoted, demoted)
-- ============================================

GR.events = {}   -- { type, actor, target, rank, when (epoch) }, newest first

function GR:ReadEventLog()
    if not GetNumGuildEvents or not GetGuildEventInfo then return end
    local list, now = {}, Now()
    local n = GetNumGuildEvents() or 0
    for i = n, 1, -1 do   -- the game lists them oldest first
        local kind, p1, p2, rank, y, mo, d, h = GetGuildEventInfo(i)
        if kind then
            local ago = (((tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0)) * 24
                + (tonumber(h) or 0)) * 3600
            list[#list + 1] = { type = kind, actor = p1, target = p2, rank = rank, when = now - ago }
        end
    end
    self.events = list
end

-- Who did it: the newest event of that type about that player
-- (types: invite, join, promote, demote, remove, quit)
function GR:WhoDid(kind, name)
    local short = Short(name):lower()
    for _, e in ipairs(self.events) do
        if e.type == kind then
            local subject = (kind == "join" or kind == "quit") and e.actor or e.target
            if subject and Short(subject):lower() == short then return e.actor, e.when end
        end
    end
end

-- ============================================
-- SCANNING THE ROSTER
-- ============================================

local function RosterRows()
    local rows, n = {}, GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, rankIndex, level, _, zone, note, onote, online, _, class, _, _, _, _, _, guid =
            GetGuildRosterInfo(i)
        name = FullName(name)
        if name then
            local y, m, d, h = 0, 0, 0, 0
            if not online and GetGuildRosterLastOnline then y, m, d, h = GetGuildRosterLastOnline(i) end
            rows[#rows + 1] = {
                index = i, name = name, rankName = rankName or "", rankIndex = tonumber(rankIndex) or 99,
                level = tonumber(level) or 1, zone = zone, note = note or "", onote = onote or "",
                online = online and true or false, class = class, guid = guid,
                offlineHours = online and 0 or (((tonumber(y) or 0) * 365 + (tonumber(m) or 0) * 30
                    + (tonumber(d) or 0)) * 24 + (tonumber(h) or 0)),
            }
        end
    end
    return rows
end
GR.RosterRows = RosterRows

local function CanSeeOfficerNotes()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then
        local ok, v = pcall(C_GuildInfo.CanViewOfficerNote); if ok then return v and true or false end
    end
    if CanViewOfficerNote then return CanViewOfficerNote() and true or false end
    return false
end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end
GR.Copy = Copy

local function Fill(rec, row)
    rec.guid = row.guid or rec.guid
    rec.class = row.class or rec.class
    rec.level, rec.rankIndex, rec.rankName = row.level, row.rankIndex, row.rankName
    rec.note, rec.zone, rec.online, rec.offlineHours = row.note, row.zone, row.online, row.offlineHours
    if row.onote ~= nil and CanSeeOfficerNotes() then rec.onote = row.onote end
end

-- The rank names, by index
local function SaveRanks(g, rows)
    g.ranks = g.ranks or {}
    for _, r in ipairs(rows) do g.ranks[r.rankIndex] = r.rankName end
end

local function Quote(s) return (s and s ~= "") and ("\"" .. s .. "\"") or "(empty)" end

-- Compare the live roster with what we have. first = the guild's first
-- scan: everyone is recorded quietly.
function GR:Scan()
    if not WM:IsModuleOn("GuildRoster") then return end
    local g = self:Guild()
    if not g then return end
    local rows = RosterRows()
    if #rows == 0 then return end
    local stored = 0
    for _ in pairs(g.members) do stored = stored + 1 end
    -- Half the guild gone at once: the server sent a partial roster
    if stored >= 10 and #rows < stored * 0.5 then return end

    local db, now, today = DB(), Now(), Stamp()
    local first = stored == 0
    local byGuid, seen = {}, {}
    for name, rec in pairs(g.members) do if rec.guid then byGuid[rec.guid] = name end end
    local formerByGuid = {}
    for name, rec in pairs(g.former) do if rec.guid then formerByGuid[rec.guid] = name end end
    local joined = {}

    for _, row in ipairs(rows) do
        local oldName = (row.guid and byGuid[row.guid]) or (g.members[row.name] and row.name)
        local rec = oldName and g.members[oldName]
        if rec and oldName ~= row.name then
            -- Same character, new name
            g.members[oldName] = nil
            g.members[row.name] = rec
            rec.name = row.name
            self:RenameInGroups(g, oldName, row.name)
            self:Log("rename", Short(oldName) .. " is now " .. Short(row.name) .. "." .. self:AltSuffix(row.name, g), g)
        end
        if not rec then
            local fname = (row.guid and formerByGuid[row.guid]) or (g.former[row.name] and row.name)
            local old = fname and g.former[fname]
            if old then
                g.former[fname] = nil
                rec = old
                rec.name = row.name
                rec.timesInGuild = (rec.timesInGuild or 1) + 1
                table.insert(rec.joins, 1, { date = today })
                rec.join = { date = today, epoch = now, verified = true }
                rec.promo = { date = today, epoch = now, verified = true }
                rec.altsAtLeaving, rec.mainAtLeaving = nil, nil
                local who = self:WhoDid("invite", row.name)
                local text = Short(row.name) .. " rejoined the guild" .. (who and (" (invited by " .. Short(who) .. ")") or "")
                    .. (fname ~= row.name and (", previously " .. Short(fname)) or "") .. "."
                self:Log("rejoin", text, g)
                if rec.ban and rec.ban.on then
                    self:Log("ban", "|cFFFF3333Warning:|r " .. Short(row.name) .. " is on the ban list"
                        .. (rec.ban.reason ~= "" and (": " .. rec.ban.reason) or "") .. ".", g)
                end
            else
                rec = NewRecord(row.name)
                if first then
                    rec.join.date, rec.promo.date = "", ""
                else
                    rec.join = { date = today, epoch = now, verified = true }
                    rec.promo = { date = today, epoch = now, verified = true }
                    rec.joins = { { date = today } }
                    local who = self:WhoDid("invite", row.name)
                    self:Log("join", Short(row.name) .. " joined the guild"
                        .. (who and (" (invited by " .. Short(who) .. ")") or "") .. ".", g)
                end
            end
            g.members[row.name] = rec
            if not first then joined[#joined + 1] = rec end
            rec.rankIndex = row.rankIndex
            rec.ranks = rec.ranks or {}
            table.insert(rec.ranks, 1, { rank = row.rankName, date = first and "" or today })
            Fill(rec, row)
        else
            -- Changes
            if row.rankIndex ~= rec.rankIndex and rec.rankIndex ~= 99 then
                local up = row.rankIndex < rec.rankIndex
                local who = self:WhoDid(up and "promote" or "demote", row.name)
                self:Log(up and "promote" or "demote", Short(row.name) .. (up and " was promoted" or " was demoted")
                    .. " from " .. (rec.rankName ~= "" and rec.rankName or "?") .. " to " .. row.rankName
                    .. (who and (" by " .. Short(who)) or "") .. "." .. self:AltSuffix(row.name, g), g)
                rec.promo = { date = today, epoch = now, verified = true }
                table.insert(rec.ranks, 1, { rank = row.rankName, date = today })
                while #rec.ranks > 30 do table.remove(rec.ranks) end
            end
            if row.level > (rec.level or 1) and row.level >= db.levelMin then
                self:Log("level", Short(row.name) .. " reached level " .. row.level .. "." .. self:AltSuffix(row.name, g), g)
            end
            if (rec.note or "") ~= row.note and rec.note ~= nil then
                self:Log("note", Short(row.name) .. "'s public note: " .. Quote(row.note) .. " (was " .. Quote(rec.note) .. ")." .. self:AltSuffix(row.name, g), g)
            end
            if rec.onote ~= nil and CanSeeOfficerNotes() and rec.onote ~= row.onote then
                self:Log("onote", Short(row.name) .. "'s officer note: " .. Quote(row.onote) .. " (was " .. Quote(rec.onote) .. ")." .. self:AltSuffix(row.name, g), g)
            end
            local inactive = db.inactiveDays * 24
            if db.reportReturn and row.online and (rec.offlineHours or 0) >= inactive then
                self:Log("back", Short(row.name) .. " is back after " .. math.floor(rec.offlineHours / 24) .. " days away." .. self:AltSuffix(row.name, g), g)
            end
            Fill(rec, row)
        end
        seen[row.name] = true
    end

    -- Gone: left or kicked
    for name, rec in pairs(g.members) do
        if not seen[name] then
            local kicker = self:WhoDid("remove", name)
            local whose = self:AltSuffix(name, g)
            g.members[name] = nil
            self:MoveToFormer(g, rec, kicker)
            local alts = rec.altsAtLeaving and #rec.altsAtLeaving > 0
                and (" Alts still here: " .. table.concat(rec.altsAtLeaving, ", ") .. ".") or ""
            if kicker then
                self:Log("kick", Short(name) .. " was removed from the guild by " .. Short(kicker) .. "." .. alts .. whose, g)
            else
                self:Log("left", Short(name) .. " left the guild." .. alts .. whose, g)
            end
        end
    end

    -- Ranks renamed
    local oldRanks = g.ranks or {}
    for _, row in ipairs(rows) do
        local was = oldRanks[row.rankIndex]
        if was and was ~= "" and was ~= row.rankName and not (g._rankLogged or {})[row.rankIndex] then
            g._rankLogged = g._rankLogged or {}
            g._rankLogged[row.rankIndex] = true
            self:Log("rankname", "Rank " .. row.rankIndex .. " renamed: " .. was .. " is now " .. row.rankName .. ".", g)
        end
    end
    g._rankLogged = nil
    SaveRanks(g, rows)
    if first then
        self:Log("info", "Started keeping the roster: " .. #rows .. " members.", g)
    end
    g.lastScan = now
    self.lastScan = now
    -- Once per guild: alts and mains the guild notes already name
    if not g.notesRead then
        g.notesRead = true
        self:AltsFromNotes()
    end
    if self.Tools then self.Tools:AfterScan(joined) end
    if self.OnScanned then self:OnScanned() end
end

function GR:MoveToFormer(g, rec, kicker)
    local today = Stamp()
    -- Alts and main as they were
    local grp = rec.group and g.groups[rec.group]
    if grp then
        local alts = {}
        for _, n in ipairs(grp.members) do if n ~= rec.name then alts[#alts + 1] = n end end
        rec.altsAtLeaving = alts
        rec.mainAtLeaving = grp.main ~= "" and grp.main ~= rec.name and grp.main or nil
        self:LeaveGroup(g, rec.name, Now(), true)
    end
    rec.group = nil
    table.insert(rec.joins, 1, { date = today, left = true, kicked = kicker and true or nil })
    rec.leftAt = Now()
    rec.online = false
    g.former[rec.name] = rec
end

-- ============================================
-- ALT GROUPS
-- ============================================

local function SortNames(t) table.sort(t, function(a, b) return a < b end) end

local function Has(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end
GR.Has = Has

local function GroupOf(g, name)
    local rec = g.members[name] or g.former[name]
    local id = rec and rec.group
    return id and g.groups[id], id, rec
end
GR.GroupOf = GroupOf

function GR:NewGroup(g, members, main, modified)
    local id = tostring(g.nextGroup or 1)
    g.nextGroup = (g.nextGroup or 1) + 1
    local grp = { members = {}, main = main or "", modified = modified or Now(), bday = { d = 0, m = 0, epoch = 0 } }
    g.groups[id] = grp
    for _, n in ipairs(members) do
        local rec = g.members[n] or g.former[n]
        if rec then
            if rec.group and rec.group ~= id then self:LeaveGroup(g, n, modified, true) end
            rec.group = id
            grp.members[#grp.members + 1] = n
        end
    end
    SortNames(grp.members)
    if grp.main ~= "" and not Has(grp.members, grp.main) then grp.main = "" end
    return grp, id
end

-- Take someone out of their group. A group left with one player and no
-- main (or nobody) goes away.
function GR:LeaveGroup(g, name, epoch, keepModified)
    local grp, id, rec = GroupOf(g, name)
    if not grp then return end
    for i = #grp.members, 1, -1 do if grp.members[i] == name then table.remove(grp.members, i) end end
    if grp.main == name then grp.main = "" end
    rec.group = nil
    rec.groupLeft = epoch or Now()
    if not keepModified then grp.modified = epoch or Now() end
    if #grp.members == 0 then
        g.groups[id] = nil
    elseif #grp.members == 1 and grp.main == "" then
        local last = g.members[grp.members[1]] or g.former[grp.members[1]]
        if last then last.group = nil; last.groupLeft = epoch or Now() end
        g.groups[id] = nil
    end
end

function GR:RenameInGroups(g, old, new)
    for _, grp in pairs(g.groups) do
        for i, n in ipairs(grp.members) do if n == old then grp.members[i] = new end end
        if grp.main == old then grp.main = new end
        SortNames(grp.members)
    end
end

-- ============================================
-- EDITS (made here, or arriving from a guildmate)
-- ============================================
-- Each takes the edit's own time (epoch). Local edits use now and are
-- shared through GR.Sync; arriving ones keep the sender's time, and only
-- replace older data (the newest edit wins, as Guild Roster Manager does).

local function Changed(what) if GR.OnDataChanged then GR:OnDataChanged(what) end end
local function Share(fn, ...) if GR.Sync and GR.Sync[fn] and not GR.applyingRemote then GR.Sync[fn](GR.Sync, ...) end end

function GR:SetJoinDate(name, stamp, epoch, remote)
    local g = self:Guild(); local rec = self:Find(name, g)
    if not rec or not SplitStamp(stamp) then return false end
    epoch = epoch or Now()
    if remote and rec.join.verified and (rec.join.epoch or 0) > epoch then return false end
    rec.join = { date = stamp, epoch = epoch, verified = true }
    if not remote then
        self:Log("dates", Short(rec.name) .. "'s join date set to " .. GR.PrettyDate(stamp) .. ".", g)
        Share("SendJoinDate", rec.name, stamp, epoch)
    end
    Changed("dates")
    return true
end

function GR:SetPromoDate(name, stamp, epoch, remote)
    local g = self:Guild(); local rec = self:Find(name, g)
    if not rec or not SplitStamp(stamp) then return false end
    epoch = epoch or Now()
    if remote and rec.promo.verified and (rec.promo.epoch or 0) > epoch then return false end
    rec.promo = { date = stamp, epoch = epoch, verified = true }
    if not remote then
        self:Log("dates", Short(rec.name) .. "'s promotion date set to " .. GR.PrettyDate(stamp) .. ".", g)
        Share("SendPromoDate", rec.name, stamp, epoch)
    end
    Changed("dates")
    return true
end

-- Custom note: up to 150 characters. Characters that would break the
-- shared format (? ~ |) are left out.
GR.CUSTOM_MAX = 150
function GR.CleanNote(text)
    text = tostring(text or ""):gsub("[%?~|\r\n]", " ")
    if #text > GR.CUSTOM_MAX then text = text:sub(1, GR.CUSTOM_MAX) end
    return strtrim(text)
end

function GR:SetCustomNote(name, text, epoch, editor, remote)
    local g = self:Guild(); local rec = self:Find(name, g)
    if not rec then return false end
    epoch = epoch or Now()
    if remote and ((rec.custom.sync == false) or (rec.custom.epoch or 0) > epoch) then return false end
    text = GR.CleanNote(text)
    local old = rec.custom.text or ""
    rec.custom.text, rec.custom.epoch, rec.custom.editor = text, epoch, editor or GR.MyName()
    if old ~= text then
        self:Log("custom", Short(rec.name) .. "'s custom note: " .. Quote(text)
            .. (remote and (" (by " .. Short(editor) .. ")") or "") .. ".", g)
    end
    if not remote then Share("SendCustomNote", rec.name, text, epoch) end
    Changed("custom")
    return true
end

-- The birthday belongs to the whole alt group
function GR:SetBirthday(name, d, m, epoch, remote)
    local g = self:Guild(); local rec = self:Find(name, g)
    if not rec then return false end
    d, m, epoch = tonumber(d) or 0, tonumber(m) or 0, epoch or Now()
    local grp = rec.group and g.groups[rec.group]
    local cur = grp and grp.bday or rec.bday
    if remote and (cur.epoch or 0) > epoch then return false end
    local b = { d = d, m = m, epoch = epoch }
    rec.bday = Copy(b)
    if grp then
        grp.bday = Copy(b)
        for _, n in ipairs(grp.members) do local r = g.members[n] or g.former[n]; if r then r.bday = Copy(b) end end
    end
    if not remote then
        if d > 0 and m > 0 then Share("SendBirthday", rec.name, d, m, epoch) else Share("SendBirthdayRemoved", rec.name, epoch) end
    end
    Changed("bday")
    return true
end

-- Ban (on = true) or unban a member, former member, or someone never in the guild
function GR:SetBan(name, on, reason, epoch, by, remote, class, guid, banAlts)
    local g = self:Guild()
    if not g then return false end
    name = FullName(name)
    local rec = self:Find(name, g)
    if not rec then
        if not on then return false end
        rec = NewRecord(name)
        rec.class, rec.guid, rec.leftAt = class, guid, Now()
        rec.joins = { { date = Stamp(), left = true } }
        g.former[name] = rec
    end
    epoch = epoch or Now()
    by = by or GR.MyName()
    reason = GR.CleanNote(reason)
    rec.ban = { on = on and true or false, epoch = epoch, unbanned = not on, by = by, reason = on and reason or "" }
    if on then
        self:Log("ban", Short(rec.name) .. " was banned by " .. Short(by) .. (reason ~= "" and (": " .. reason) or "") .. ".", g)
    else
        self:Log("ban", Short(rec.name) .. " was unbanned by " .. Short(by) .. ".", g)
    end
    if banAlts and on then
        local grp = rec.group and g.groups[rec.group]
        local alts = grp and grp.members or rec.altsAtLeaving or {}
        for _, n in ipairs(alts) do
            local r = g.members[n] or g.former[n]
            if n ~= rec.name and n ~= GR.MyName() and r then
                r.ban = { on = true, epoch = epoch, unbanned = false, by = by, reason = reason }
            end
        end
    end
    if not remote then
        if on then Share("SendBan", rec.name, epoch, reason, rec.class, rec.guid, banAlts)
        else Share("SendUnban", rec.name, epoch) end
    end
    Changed("ban")
    return true
end

-- Put alt into target's group (both must be current members)
function GR:AddAlt(target, alt, epoch, remote)
    local g = self:Guild()
    if not g then return false end
    target, alt = FullName(target), FullName(alt)
    if target == alt or not g.members[target] or not g.members[alt] then return false end
    epoch = epoch or Now()
    local grp, id = GroupOf(g, target)
    local altGrp = GroupOf(g, alt)
    if grp and grp == altGrp then return false end
    if #((grp and grp.members) or {}) >= 75 then return false end
    -- Two groups with mains: the one being added in gives up its main
    if altGrp then self:LeaveGroup(g, alt, epoch, true) end
    if not grp then
        grp, id = self:NewGroup(g, { target, alt }, "", epoch)
    else
        g.members[alt].group = id
        grp.members[#grp.members + 1] = alt
        SortNames(grp.members)
        grp.modified = epoch
    end
    -- One birthday for the group: the newest
    local best = grp.bday or { d = 0, m = 0, epoch = 0 }
    for _, n in ipairs(grp.members) do
        local r = g.members[n]
        if r and (r.bday.epoch or 0) > (best.epoch or 0) then best = r.bday end
    end
    grp.bday = Copy(best)
    for _, n in ipairs(grp.members) do local r = g.members[n]; if r then r.bday = Copy(best) end end
    if not remote then
        self:Log("alts", Short(alt) .. " is now an alt of " .. Short(target) .. ".", g)
        Share("SendAddAlt", grp, alt, target)
    end
    Changed("alts")
    return true
end

function GR:RemoveAlt(alt, epoch, remote)
    local g = self:Guild()
    alt = FullName(alt)
    local grp = g and GroupOf(g, alt)
    if not grp then return false end
    epoch = epoch or Now()
    if remote and (grp.modified or 0) > epoch then return false end
    local owner = grp.main ~= "" and grp.main ~= alt and grp.main or grp.members[1]
    self:LeaveGroup(g, alt, epoch, remote)
    if not remote then
        self:Log("alts", Short(alt) .. " is no longer in an alt group.", g)
        Share("SendRemoveAlt", alt, epoch, owner)
    end
    Changed("alts")
    return true
end

function GR:SetMain(name, epoch, remote)
    local g = self:Guild()
    name = FullName(name)
    local rec = g and (g.members[name] or g.former[name])
    if not rec then return false end
    epoch = epoch or Now()
    local grp = rec.group and g.groups[rec.group]
    if grp then
        if remote and (grp.modified or 0) >= epoch and grp.main ~= name then return false end
        grp.main = name
        grp.modified = math.max(grp.modified or 0, epoch)
    else
        if remote and (rec.groupLeft or 0) >= epoch then return false end
        self:NewGroup(g, { name }, name, epoch)
    end
    if not remote then
        self:Log("alts", Short(name) .. " is now a main.", g)
        Share("SendMain", name, epoch)
    end
    Changed("alts")
    return true
end

function GR:UnsetMain(name, epoch, remote)
    local g = self:Guild()
    name = FullName(name)
    local grp, id, rec
    if g then grp, id, rec = GroupOf(g, name) end
    if not grp or grp.main ~= name then return false end
    epoch = epoch or Now()
    if #grp.members == 1 then
        rec.group = nil
        rec.groupLeft = epoch
        g.groups[id] = nil
    else
        grp.main = ""
        grp.modified = epoch
    end
    if not remote then
        self:Log("alts", Short(name) .. " is no longer a main.", g)
        Share("SendUnsetMain", name, epoch)
    end
    Changed("alts")
    return true
end

-- ============================================
-- ALTS FROM GUILD NOTES
-- ============================================
-- Public and officer notes often say whose alt a character is: "Venhana
-- alt", "Venitra's Alt [BS]375", "alt of Chojii", "Main: Chojii". When the
-- name is a guild member, they become that character's main: in the alt
-- group they already share, or with the alt added to theirs. Nothing is
-- changed where it would move someone out of a group that has another
-- main, or join two groups.

local NOTE_PATTERNS = {
    "^%s*([^%s%p%d]+)'?s?%s+alt",        -- "Name alt", "Name's alt"
    "alt%s+of%s+([^%s%p%d]+)",           -- "alt of Name"
    "alt%s+to%s+([^%s%p%d]+)",           -- "alt to Name"
    "alt%s*[:%-]%s*([^%s%p%d]+)",        -- "alt: Name", "alt - Name"
    "main%s*[:%-]%s*([^%s%p%d]+)",       -- "main: Name"
    "main%s+is%s+([^%s%p%d]+)",          -- "main is Name"
}

-- The guild member a note names as this character's main
function GR:MainFromNote(note, byShort, self_name)
    if type(note) ~= "string" or note == "" then return nil end
    local low = note:lower()
    for _, pat in ipairs(NOTE_PATTERNS) do
        local who = low:match(pat)
        local name = who and byShort[who]
        if name and name ~= self_name then return name end
    end
    return nil
end

-- Reads every member's notes; returns how many characters were linked
function GR:AltsFromNotes()
    local g = self:Guild()
    if not g then return 0 end
    local byShort = {}
    for name in pairs(g.members) do byShort[Short(name):lower()] = name end
    local found = {}
    for name, rec in pairs(g.members) do
        local main = self:MainFromNote(rec.note, byShort, name) or self:MainFromNote(rec.onote, byShort, name)
        if main then found[#found + 1] = { name, main } end
    end
    table.sort(found, function(a, b) return a[1] < b[1] end)
    local linked = 0
    for _, f in ipairs(found) do
        local alt, main = f[1], f[2]
        local ag, mg = GroupOf(g, alt), GroupOf(g, main)
        local done = false
        if ag and ag == mg then
            if ag.main == "" then done = self:SetMain(main) end
        elseif not ag and not mg then
            done = self:AddAlt(main, alt) and self:SetMain(main)
        elseif not ag and mg then
            if mg.main == "" or mg.main == main then
                done = self:AddAlt(main, alt)
                if done and mg.main == "" then self:SetMain(main) end
            end
        elseif ag and not mg then
            if ag.main == "" then done = self:AddAlt(alt, main) and self:SetMain(main) end
        end
        if done then linked = linked + 1 end
    end
    if linked > 0 then
        self:Log("info", string.format("Guild notes named the main of %d character%s.", linked, linked == 1 and "" or "s"), g)
    end
    return linked
end

-- The character an alt group is listed under: its main while they're in the
-- guild, otherwise the highest rank, then highest level, then the name.
-- Second return: true when that's the group's main.
function GR:GroupLead(g, grp)
    if not grp then return nil end
    if grp.main ~= "" and g.members[grp.main] then return g.members[grp.main], true end
    local best
    for _, n in ipairs(grp.members) do
        local r = g.members[n]
        if r and (not best
            or (r.rankIndex or 99) < (best.rankIndex or 99)
            or ((r.rankIndex or 99) == (best.rankIndex or 99) and ((r.level or 0) > (best.level or 0)
                or ((r.level or 0) == (best.level or 0) and r.name < best.name)))) then
            best = r
        end
    end
    return best, false
end

-- A whole group as a guildmate sent it: exactly these members, this main
function GR:ApplyGroup(members, main, epoch)
    local g = self:Guild()
    if not g then return end
    local known = {}
    for _, n in ipairs(members) do if g.members[n] or g.former[n] then known[#known + 1] = n end end
    if #known < 2 and not (main ~= "" and #known == 1) then return end
    for _, n in ipairs(known) do self:LeaveGroup(g, n, epoch, true) end
    self:NewGroup(g, known, main, epoch)
    Changed("alts")
end

-- Alts of a player (not counting them), and the group's main
function GR:AltsOf(name)
    local g = self:Guild()
    local grp = g and GroupOf(g, FullName(name))
    if not grp then return {}, nil end
    local out = {}
    for _, n in ipairs(grp.members) do if n ~= FullName(name) then out[#out + 1] = n end end
    return out, grp.main ~= "" and grp.main or nil
end

-- Banned players who are in the guild right now
function GR:BannedInGuild()
    local g, out = self:Guild(), {}
    if not g then return out end
    for name, rec in pairs(g.members) do if rec.ban and rec.ban.on then out[#out + 1] = name end end
    table.sort(out)
    return out
end

-- ============================================
-- QUERIES FOR THE WINDOW
-- ============================================

function GR:Members(includeFormer)
    local g, out = self:Guild(), {}
    if not g then return out end
    for _, rec in pairs(g.members) do out[#out + 1] = rec end
    if includeFormer then for _, rec in pairs(g.former) do out[#out + 1] = rec end end
    return out
end

function GR:Counts()
    local g = self:Guild()
    if not g then return 0, 0, 0 end
    local m, online, f = 0, 0, 0
    for _, rec in pairs(g.members) do m = m + 1; if rec.online then online = online + 1 end end
    for _ in pairs(g.former) do f = f + 1 end
    return m, online, f
end

function GR:GetQuickStatus()
    if not GR.GuildKey() then return "Not in a guild" end
    local m, online = self:Counts()
    local sync = GR.Sync and GR.Sync:StatusText() or ""
    return string.format("%d members, %d online%s", m, online, sync ~= "" and (", " .. sync) or "")
end

-- ============================================
-- START-UP AND TIMERS
-- ============================================

local events = CreateFrame("Frame")
local scanPending, sinceAsk = false, 0

local function AskRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
    if QueryGuildEventLog then pcall(QueryGuildEventLog) end
end
GR.AskRoster = AskRoster

local function ScanSoon()
    if scanPending then return end
    scanPending = true
    WM.RunAfter(1, function()
        scanPending = false
        if not WM:IsModuleOn("GuildRoster") then return end
        local ok, err = pcall(GR.Scan, GR)
        if not ok then geterrorhandler()(err) end
    end)
end
GR.ScanSoon = ScanSoon

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    sinceAsk = sinceAsk + (elapsed or 0)
    if sinceAsk < (DB().scanEvery or 30) then return end
    sinceAsk = 0
    if WM:IsModuleOn("GuildRoster") and IsInGuild and IsInGuild() then AskRoster() end
end)

function GR:Initialize()
    DB()
    WM:RegisterEvents(events, { "GUILD_ROSTER_UPDATE", "GUILD_EVENT_LOG_UPDATE", "PLAYER_GUILD_UPDATE" })
    if self.Sync and self.Sync.Initialize then self.Sync:Initialize() end
    if self.InitUI then self:InitUI() end
    WM.RunAfter(3, function() if WM:IsModuleOn("GuildRoster") then AskRoster() end end)
end

events:SetScript("OnEvent", function(_, event)
    if not WM:IsModuleOn("GuildRoster") then return end
    if event == "GUILD_EVENT_LOG_UPDATE" then
        pcall(GR.ReadEventLog, GR)
    elseif event == "GUILD_ROSTER_UPDATE" then
        ScanSoon()
    elseif event == "PLAYER_GUILD_UPDATE" then
        AskRoster()
    end
end)

function GR:OnModuleOff()
    if self.HideUI then self:HideUI() end
    if self.Sync and self.Sync.OnModuleOff then self.Sync:OnModuleOff() end
end

function GR:OnModuleOn()
    DB()
    AskRoster()
    if self.Sync and self.Sync.OnModuleOn then self.Sync:OnModuleOn() end
end
