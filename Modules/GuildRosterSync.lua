-- Watching Machine: Roster Manager sync
-- Shares Roster Manager's edits (join and promotion dates, alts and mains,
-- custom notes, birthdays, bans) with guildmates, in Guild Roster Manager's
-- own addon-message format, so players running Guild Roster Manager and
-- players running Watching Machine see each other's edits.
--
--   GRMUSER  REG / REQ: who's there, with which settings. Guild Roster
--            Manager only listens to a sender whose REG carries exactly its
--            own release number ("patch day"), so we use the one the
--            guild's Guild Roster Manager users announce.
--   GRM_SYNC TAG?R?fields: one edit, to the guild (bans by whisper to
--            those allowed ban data). R is the lowest rank (highest index)
--            that may use it.
-- Each edit carries the time it was made; the newest edit wins.
--
-- Also: importing what Guild Roster Manager already knows, when it's
-- installed. Formats compiled with the help of Guild Roster Manager's
-- research (Arkaan); the code is our own.

local AddonName, WM = ...
local GR = WM.GuildRoster
local Sync = {}
GR.Sync = Sync

local PREFIX_USER, PREFIX_SYNC, PREFIX_VER = "GRMUSER", "GRM_SYNC", "GRMVER"
Sync.DEFAULT_PATCHDAY = 1792119571     -- Guild Roster Manager R1.99423
local MAX_BODY = 246                   -- 255 minus the prefix
local NOTE_SPLIT = 99

Sync.users = {}       -- [Name-Realm] = { patchDay, syncRank, banRank, inGroup, enabled, exportAll, ver, ok }
local seenPatchDay = {}   -- [sender] = patch day they announced
local pendingNote = {}    -- [name] = { epoch, text } until a long note's second part
local pendingAlts = {}    -- [sender .. lead] = { main, epoch, added, names }

local function DB() return GR.DB() end

-- ============================================
-- WHO WE ARE
-- ============================================

-- Guild Roster Manager running on this character does its own syncing
-- (and would see our messages as its own): we stay quiet then.
function Sync.GRMRunning()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not f then return false end
    local ok, loaded = pcall(f, "Guild_Roster_Manager")
    return ok and loaded and true or false
end

function Sync:Enabled()
    return WM:IsModuleOn("GuildRoster") and DB().sync and not Sync.GRMRunning() and GR.GuildKey() ~= nil
end

function Sync:PatchDay() return tonumber(DB().patchDay) or Sync.DEFAULT_PATCHDAY end

local function NumRanks()
    local n = tonumber(GuildControlGetNumRanks and GuildControlGetNumRanks()) or 10
    return math.max(0, n - 1)
end
Sync.NumRanks = NumRanks

-- Our rank index (0 = guild master)
local function MyRank()
    local rec = GR:Find(GR.MyName())
    if rec and rec.rankIndex and rec.rankIndex ~= 99 then return rec.rankIndex end
    local _, _, idx = GetGuildInfo and GetGuildInfo("player")
    return tonumber(idx) or NumRanks()
end
Sync.MyRank = MyRank

-- The rank limits we use: share with and accept from ranks at or above these
local function SyncRank() return tonumber(DB().syncRank) or NumRanks() end
local function BanRank() return tonumber(DB().banRank) or 1 end
local function CustomRank() return tonumber(DB().customRank) or SyncRank() end
Sync.SyncRank, Sync.BanRank, Sync.CustomRank = SyncRank, BanRank, CustomRank

-- Sender's rank index, from the roster (nil: not a member we know)
local function RankOf(name)
    local g = GR:Guild()
    local rec = g and g.members[name]
    return rec and rec.rankIndex
end

-- ============================================
-- SENDING (paced)
-- ============================================

-- Through Watching Machine's shared, paced queue (Core)
local OUR_PREFIXES = { [PREFIX_USER] = true, [PREFIX_SYNC] = true, [PREFIX_VER] = true }

local function Send(prefix, body, channel, target)
    if #body > MAX_BODY then return false end
    return WM:QueueAddonMessage(prefix, body, channel or "GUILD", target)
end
Sync.Send = Send
function Sync:QueueLength() return WM:AddonQueueLength(OUR_PREFIXES) end
-- Send everything queued at once (tests)
function Sync:FlushForTests() WM:FlushAddonQueue() end
function Sync:ClearQueue() WM:ClearAddonQueue(OUR_PREFIXES) end

-- ============================================
-- PRESENCE (GRMUSER)
-- ============================================

function Sync:RegBody()
    local db = DB()
    return table.concat({ "REG", "WM" .. (WM.version or "?"), tostring(self:PatchDay()), tostring(SyncRank()),
        tostring(BanRank()), tostring(IsInGroup and IsInGroup() and true or false),
        tostring(db.sync and true or false), "true" }, "?")
end

function Sync:Announce()
    if not self:Enabled() then return end
    Send(PREFIX_USER, self:RegBody(), "GUILD")
end

-- Which patch day most announcers use; switch to it (and say so again)
function Sync:LearnPatchDay(sender, pd)
    pd = tonumber(pd)
    if not pd then return end
    seenPatchDay[sender] = pd
    local votes, best, bestN = {}, nil, 0
    for _, p in pairs(seenPatchDay) do votes[p] = (votes[p] or 0) + 1 end
    for p, n in pairs(votes) do
        if n > bestN or (n == bestN and p > (best or 0)) then best, bestN = p, n end
    end
    if best and best ~= self:PatchDay() then
        DB().patchDay = best
        for name, u in pairs(self.users) do u.ok = (u.patchDay == best) end
        self:Announce()
    end
end

function Sync:OnUserMessage(body, sender)
    local fields = {}
    for f in tostring(body):gmatch("[^?]+") do fields[#fields + 1] = f end
    local kind = fields[1]
    if kind == "REQ" then
        self:Announce()
    elseif kind == "REG" or kind == "INIT" then
        local pd = tonumber(fields[3])
        if not pd then return end
        local u = self.users[sender] or {}
        self.users[sender] = u
        u.ver, u.patchDay = fields[2], pd
        u.syncRank, u.banRank = tonumber(fields[4]) or NumRanks(), tonumber(fields[5]) or 1
        u.inGroup, u.enabled, u.exportAll = fields[6] == "true", fields[7] == "true", fields[8] == "true"
        u.seen = time()
        u.isWM = tostring(u.ver):sub(1, 2) == "WM"
        -- Guild Roster Manager users decide the patch day; Watching Machine
        -- users just follow it
        if not u.isWM then self:LearnPatchDay(sender, pd) end
        u.ok = (pd == self:PatchDay())
        if not u.greeted then u.greeted = true; self:Announce() end
    end
end

-- ============================================
-- RECEIVING EDITS (GRM_SYNC)
-- ============================================

local LIVE = { GRM_JD = true, GRM_PD = true, GRM_ADDALT = true, GRM_RMVALT = true, GRM_MAIN = true,
    GRM_RMVMAIN = true, GRM_BDAY = true, GRM_BDAYREM = true }
local NOTES = { GRM_CNOTE1 = true, GRM_CNOTE2 = true, GRM_CNOTE3 = true }
local BANS = { GRM_BAN = true, GRM_UNBAN = true }

local function Q(payload)
    local t = {}
    for f in payload:gmatch("[^?]+") do t[#t + 1] = f end
    return t
end
local function T(payload)     -- "~|~" records (any ~ or | separates)
    local t = {}
    for f in payload:gmatch("[^~|]+") do t[#t + 1] = f end
    return t
end

local function Remote(fn, ...)
    GR.applyingRemote = true
    local ok, a = pcall(fn, ...)
    GR.applyingRemote = false
    if not ok then geterrorhandler()(a) end
    return ok and a
end

-- Should we take this edit from this sender? (the same gates Guild Roster
-- Manager uses)
function Sync:Accepts(tag, R, sender)
    local S, P = RankOf(sender), MyRank()
    if not S then return false end
    if R < P then return false end
    if NOTES[tag] then return DB().syncCustom and S <= CustomRank() end
    if BANS[tag] then return DB().syncBans and S <= BanRank() end
    return S <= SyncRank()
end

function Sync:OnSyncMessage(body, sender)
    local tag, rest = tostring(body):match("^([^?]+)%?(.*)$")
    if not tag or not (LIVE[tag] or NOTES[tag] or BANS[tag]) then return end
    local R, payload = rest:match("^(%-?%d+)%?(.*)$")
    R = tonumber(R)
    if not R or not self:Accepts(tag, R, sender) then return end
    self.received = (self.received or 0) + 1
    local by = GR.Short(sender)
    if tag == "GRM_JD" or tag == "GRM_PD" then
        local f = Q(payload)
        local name, stamp, epoch = GR.FullName(f[1]), f[2], tonumber(f[3])
        if not (name and stamp and epoch) then return end
        local fn = tag == "GRM_JD" and GR.SetJoinDate or GR.SetPromoDate
        if Remote(fn, GR, name, stamp, epoch, true) then
            GR:Log("dates", by .. " set " .. GR.Short(name) .. "'s " .. (tag == "GRM_JD" and "join" or "promotion")
                .. " date to " .. GR.PrettyDate(stamp) .. ".")
        end
    elseif tag == "GRM_ADDALT" then
        self:OnAddAlt(Q(payload), sender)
    elseif tag == "GRM_RMVALT" then
        local f = Q(payload)
        local alt, epoch = GR.FullName(f[1]), tonumber(f[2])
        if not (alt and epoch) then return end
        if Remote(GR.RemoveAlt, GR, alt, epoch, true) then
            GR:Log("alts", by .. " removed " .. GR.Short(alt) .. " from their alt group.")
        else
            local rec = GR:Find(alt)
            if rec and not rec.group then rec.groupLeft = math.max(rec.groupLeft or 0, epoch) end
        end
    elseif tag == "GRM_MAIN" then
        local f = Q(payload)
        local name, epoch = GR.FullName(f[1]), tonumber(f[2])
        if name and epoch and Remote(GR.SetMain, GR, name, epoch, true) then
            GR:Log("alts", by .. " set " .. GR.Short(name) .. " as a main.")
        end
    elseif tag == "GRM_RMVMAIN" then
        local f = Q(payload)
        local name, epoch = GR.FullName(f[1]), tonumber(f[2])
        if name and epoch and Remote(GR.UnsetMain, GR, name, epoch, true) then
            GR:Log("alts", by .. " made " .. GR.Short(name) .. " no longer a main.")
        end
    elseif tag == "GRM_BDAY" then
        local f = Q(payload)
        local name, d, m, epoch = GR.FullName(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
        if name and d and m and epoch then Remote(GR.SetBirthday, GR, name, d, m, epoch, true) end
    elseif tag == "GRM_BDAYREM" then
        local f = Q(payload)
        local name, epoch = GR.FullName(f[1]), tonumber(f[2])
        if name and epoch then Remote(GR.SetBirthday, GR, name, 0, 0, epoch, true) end
    elseif tag == "GRM_CNOTE1" or tag == "GRM_CNOTE2" then
        local f = T(payload)
        local name, epoch, text = GR.FullName(f[1]), tonumber(f[2]), f[3]
        if not (name and epoch) then return end
        if text == "#" then text = "" end
        if tag == "GRM_CNOTE2" then
            pendingNote[name] = { epoch = epoch, text = text or "" }
        else
            Remote(GR.SetCustomNote, GR, name, text or "", epoch, sender, true)
        end
    elseif tag == "GRM_CNOTE3" then
        local f = T(payload)
        local name = GR.FullName(f[1])
        local first = name and pendingNote[name]
        if not first then return end
        pendingNote[name] = nil
        Remote(GR.SetCustomNote, GR, name, first.text .. (f[2] or ""), first.epoch, sender, true)
    elseif tag == "GRM_BAN" then
        local f = T(payload)
        local name, epoch, reason, class, guid = GR.FullName(f[1]), tonumber(f[2]), f[3], f[4], f[5]
        if not (name and epoch) then return end
        if reason == "###" then reason = "" end
        if guid == "#" then guid = nil end
        Remote(GR.SetBan, GR, name, true, reason, epoch, sender, true, class, guid, f[6] == "true")
    elseif tag == "GRM_UNBAN" then
        local f = Q(payload)
        local name, epoch = GR.FullName(f[1]), tonumber(f[2])
        if name and epoch then Remote(GR.SetBan, GR, name, false, nil, epoch, sender, true) end
    end
end

-- GRM_ADDALT: a header (S) and maybe continuations (##); X ends the list.
-- The list is the whole group, its first (sorted) member given apart.
function Sync:OnAddAlt(f, sender)
    local kind = f[1]
    local key
    if kind == "S" then
        local lead = GR.FullName(f[2])
        if not lead then return end
        key = sender .. "|" .. lead
        local p = { main = f[3] ~= "#" and GR.FullName(f[3]) or "", epoch = tonumber(f[4]) or time(),
            added = GR.FullName(f[6]), target = GR.FullName(f[7]), names = { lead } }
        pendingAlts[key] = p
        for i = 8, #f do
            if f[i] == "X" then return self:FinishAltGroup(key) end
            p.names[#p.names + 1] = GR.FullName(f[i])
        end
    elseif kind == "##" then
        local lead = GR.FullName(f[2])
        key = lead and (sender .. "|" .. lead)
        local p = key and pendingAlts[key]
        if not p then return end
        for i = 3, #f do
            if f[i] == "X" then return self:FinishAltGroup(key) end
            p.names[#p.names + 1] = GR.FullName(f[i])
        end
    end
end

function Sync:FinishAltGroup(key)
    local p = pendingAlts[key]
    pendingAlts[key] = nil
    local g = GR:Guild()
    if not p or not g or not p.added or not g.members[p.added] then return end
    Remote(GR.ApplyGroup, GR, p.names, p.main, p.epoch)
    GR:Log("alts", GR.Short(key:match("^[^|]+")) .. " added " .. GR.Short(p.added) .. " as an alt of "
        .. GR.Short(p.target or p.names[1]) .. ".")
end

-- ============================================
-- SENDING EDITS
-- ============================================

local function R() return NumRanks() end   -- live edits: every rank may use them

local function Clean(s) return (tostring(s or ""):gsub("[%?~|]", "")) end

function Sync:SendLive(tag, ...)
    if not self:Enabled() then return end
    local parts = { tag, tostring(R()) }
    for i = 1, select("#", ...) do parts[#parts + 1] = Clean(select(i, ...)) end
    Send(PREFIX_SYNC, table.concat(parts, "?"), "GUILD")
end

function Sync:SendJoinDate(name, stamp, epoch) self:SendLive("GRM_JD", name, stamp, epoch) end
function Sync:SendPromoDate(name, stamp, epoch) self:SendLive("GRM_PD", name, stamp, epoch) end
function Sync:SendMain(name, epoch) self:SendLive("GRM_MAIN", name, epoch) end
function Sync:SendUnsetMain(name, epoch) self:SendLive("GRM_RMVMAIN", name, epoch) end
function Sync:SendRemoveAlt(alt, epoch, owner) self:SendLive("GRM_RMVALT", alt, epoch, owner or alt) end
function Sync:SendBirthday(name, d, m, epoch) self:SendLive("GRM_BDAY", name, d, m, epoch) end
function Sync:SendBirthdayRemoved(name, epoch) self:SendLive("GRM_BDAYREM", name, epoch) end

-- Long notes go in two parts (the first 99 bytes, then the rest)
function Sync:CustomNoteBodies(name, text, epoch)
    local head = "GRM_CNOTE%d?" .. R() .. "?"
    text = Clean(text)
    if text == "" then text = "#" end
    if #text <= NOTE_SPLIT then
        return { head:format(1) .. name .. "~|~" .. epoch .. "~|~" .. text }
    end
    return { head:format(2) .. name .. "~|~" .. epoch .. "~|~" .. text:sub(1, NOTE_SPLIT),
        head:format(3) .. name .. "~|~" .. text:sub(NOTE_SPLIT + 1) }
end

function Sync:SendCustomNote(name, text, epoch)
    if not self:Enabled() or not DB().syncCustom then return end
    for _, b in ipairs(self:CustomNoteBodies(name, text, epoch)) do Send(PREFIX_SYNC, b, "GUILD") end
end

-- The whole group after adding alt to target's group
function Sync:AddAltBodies(grp, alt, target)
    local members = {}
    for _, n in ipairs(grp.members) do members[#members + 1] = n end
    table.sort(members)
    local lead = members[1]
    local main = (grp.main ~= "" and grp.main) or "#"
    local bodies = {}
    local body = table.concat({ "GRM_ADDALT", tostring(R()), "S", lead, main, tostring(grp.modified or time()),
        tostring(#members - 1), alt, target }, "?")
    for i = 2, #members + 1 do
        local item = members[i] or "X"
        if #body + 1 + #item > MAX_BODY then
            bodies[#bodies + 1] = body
            body = table.concat({ "GRM_ADDALT", tostring(R()), "##", lead }, "?")
        end
        body = body .. "?" .. item
    end
    bodies[#bodies + 1] = body
    return bodies
end

function Sync:SendAddAlt(grp, alt, target)
    if not self:Enabled() then return end
    for _, b in ipairs(self:AddAltBodies(grp, alt, target)) do Send(PREFIX_SYNC, b, "GUILD") end
end

-- Bans go only to those allowed ban data, by whisper
function Sync:BanTargets()
    local out, me, mine = {}, GR.MyName(), MyRank()
    local g = GR:Guild()
    for name, u in pairs(self.users) do
        local rec = g and g.members[name]
        if u.ok and u.enabled and name ~= me and rec and rec.online
            and mine <= (u.banRank or 1) and (rec.rankIndex or 99) <= BanRank() then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

function Sync:SendBan(name, epoch, reason, class, guid, banAlts)
    if not self:Enabled() or not DB().syncBans then return end
    reason = Clean(reason)
    if reason == "" then reason = "###" end
    -- Kept to one message: shorten the reason if need be
    local function Body(r)
        return "GRM_BAN?" .. BanRank() .. "?" .. table.concat({ name, tostring(epoch), r, (class or "WARRIOR"):upper(),
            (guid and guid ~= "") and guid or "#", banAlts and "true" or "false" }, "~|~")
    end
    local body = Body(reason)
    if #body > MAX_BODY then body = Body(reason:sub(1, math.max(1, #reason - (#body - MAX_BODY)))) end
    for _, target in ipairs(self:BanTargets()) do Send(PREFIX_SYNC, body, "WHISPER", target) end
end

function Sync:SendUnban(name, epoch)
    if not self:Enabled() or not DB().syncBans then return end
    local body = "GRM_UNBAN?" .. BanRank() .. "?" .. name .. "?" .. epoch
    for _, target in ipairs(self:BanTargets()) do Send(PREFIX_SYNC, body, "WHISPER", target) end
end

-- ============================================
-- STATUS
-- ============================================

-- Guildmates we sync with: { name, isWM, ver, ok }
function Sync:Peers()
    local out = {}
    for name, u in pairs(self.users) do
        out[#out + 1] = { name = name, isWM = u.isWM, ver = u.ver, ok = u.ok, patchDay = u.patchDay }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Sync:StatusText()
    if not DB().sync then return "sync off" end
    if Sync.GRMRunning() then return "Guild Roster Manager syncs" end
    local n = 0
    for _, u in pairs(self.users) do if u.ok then n = n + 1 end end
    return n > 0 and (n .. " syncing") or ""
end

-- ============================================
-- IMPORT FROM GUILD ROSTER MANAGER
-- ============================================
-- When Guild Roster Manager is installed and loaded, its saved data can be
-- read once: join and promotion dates, custom notes, birthdays, bans, alt
-- groups and former members. Only newer data replaces what we have.

local function GRMTable(name, guildName)
    local t = rawget(_G, name)
    if type(t) ~= "table" then return nil end
    if type(t[guildName]) == "table" then return t[guildName] end
    for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "table" and (k == guildName or k:sub(1, #guildName + 1) == guildName .. "-") then
            return v
        end
    end
end

function Sync.GRMDataAvailable()
    local gname = GetGuildInfo and GetGuildInfo("player")
    return type(gname) == "string" and GRMTable("GRM_GuildMemberHistory_Save", gname) ~= nil
end

local function ImportRecord(rec, src)
    local n = 0
    local jd = type(src.joinDateHist) == "table" and src.joinDateHist[1]
    if type(jd) == "table" and GR.SplitStamp(jd[4]) and (jd[6] or not rec.join.verified)
        and (tonumber(jd[5]) or 0) >= (rec.join.epoch or 0) then
        rec.join = { date = tostring(jd[4]), epoch = tonumber(jd[5]) or 0, verified = jd[6] and true or false }
        n = n + 1
    end
    local pd = type(src.rankHist) == "table" and src.rankHist[1]
    if type(pd) == "table" and GR.SplitStamp(pd[5]) and (pd[7] or not rec.promo.verified)
        and (tonumber(pd[6]) or 0) >= (rec.promo.epoch or 0) then
        rec.promo = { date = tostring(pd[5]), epoch = tonumber(pd[6]) or 0, verified = pd[7] and true or false }
        n = n + 1
    end
    local cn = src.customNote
    if type(cn) == "table" and type(cn[4]) == "string" and cn[4] ~= "" and (tonumber(cn[2]) or 0) >= (rec.custom.epoch or 0) then
        rec.custom = { text = GR.CleanNote(cn[4]), epoch = tonumber(cn[2]) or 0, editor = tostring(cn[3] or ""),
            sync = cn[1] ~= false }
        n = n + 1
    end
    local b = src.birthdayInfo
    if type(b) == "table" and type(b.date) == "table" and (tonumber(b.date[1]) or 0) > 0
        and (tonumber(b.timeUpdated) or 0) >= (rec.bday.epoch or 0) then
        rec.bday = { d = tonumber(b.date[1]), m = tonumber(b.date[2]) or 0, epoch = tonumber(b.timeUpdated) or 0 }
        n = n + 1
    end
    local ban = src.bannedInfo
    if type(ban) == "table" and (ban[1] or ban[3]) and (tonumber(ban[2]) or 0) >= (rec.ban.epoch or 0) then
        rec.ban = { on = ban[1] and true or false, epoch = tonumber(ban[2]) or 0, unbanned = ban[3] and true or false,
            by = tostring(ban[4] or ""), reason = GR.CleanNote(src.reasonBanned) }
        n = n + 1
    end
    rec.guid = rec.guid or src.GUID
    rec.class = rec.class or src.class
    return n
end

-- Returns members, former members and groups brought in (nil: nothing to read)
function Sync:ImportFromGRM()
    local g = GR:Guild()
    local gname = GetGuildInfo and GetGuildInfo("player")
    if not g or type(gname) ~= "string" then return nil end
    local members = GRMTable("GRM_GuildMemberHistory_Save", gname)
    if not members then return nil end
    local former = GRMTable("GRM_PlayersThatLeftHistory_Save", gname) or {}
    local alts = GRMTable("GRM_Alts", gname) or {}
    local nm, nf, ng = 0, 0, 0
    for name, src in pairs(members) do
        if type(name) == "string" and type(src) == "table" and name:find("-", 1, true) then
            local rec = g.members[name]
            if rec and ImportRecord(rec, src) > 0 then nm = nm + 1 end
        end
    end
    for name, src in pairs(former) do
        if type(name) == "string" and type(src) == "table" and name:find("-", 1, true) and not g.members[name] then
            local rec = g.former[name]
            if not rec then
                rec = GR.NewRecord(name)
                rec.level, rec.rankName = tonumber(src.level) or 1, tostring(src.rankName or "")
                rec.joins = { { date = GR.Stamp(), left = true } }
                g.former[name] = rec
            end
            if ImportRecord(rec, src) > 0 or not rec.leftAt then nf = nf + 1 end
            rec.leftAt = rec.leftAt or time()
        end
    end
    for _, grp in pairs(alts) do
        if type(grp) == "table" then
            local names = {}
            for _, e in ipairs(grp) do
                local n = type(e) == "table" and (e.name or e[1]) or e
                if type(n) == "string" and g.members[n] then names[#names + 1] = n end
            end
            local main = type(grp.main) == "string" and grp.main or ""
            if #names >= 2 or (#names == 1 and main == names[1]) then
                local _, existing = GR.GroupOf(g, names[1])
                local cur = existing and g.groups[existing]
                if not cur or (cur.modified or 0) <= (tonumber(grp.timeModified) or 0) then
                    GR.applyingRemote = true
                    pcall(GR.ApplyGroup, GR, names, g.members[main] and main or "", tonumber(grp.timeModified) or time())
                    GR.applyingRemote = false
                    ng = ng + 1
                end
            end
        end
    end
    GR:Log("info", string.format("Imported from Guild Roster Manager: %d members, %d former members, %d alt groups.", nm, nf, ng), g)
    return nm, nf, ng
end

-- ============================================
-- EVENTS
-- ============================================

local events = CreateFrame("Frame")
Sync.eventFrame = events

function Sync:Initialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        for _, p in ipairs({ PREFIX_USER, PREFIX_SYNC, PREFIX_VER }) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end
    end
    WM:RegisterEvents(events, { "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE" })
    WM.RunAfter(5, function() Sync:Hello() end)
end

-- Say who we are and ask who's there
function Sync:Hello()
    if not self:Enabled() then return end
    self:Announce()
    Send(PREFIX_USER, "REQ?", "GUILD")
end

local wasGrouped
events:SetScript("OnEvent", function(_, event, prefix, body, channel, sender)
    if not WM:IsModuleOn("GuildRoster") then return end
    if event == "GROUP_ROSTER_UPDATE" then
        local now = IsInGroup and IsInGroup() and true or false
        if now ~= wasGrouped then wasGrouped = now; Sync:Announce() end
        return
    end
    if prefix ~= PREFIX_USER and prefix ~= PREFIX_SYNC and prefix ~= PREFIX_VER then return end
    if not DB().sync or Sync.GRMRunning() then return end
    sender = GR.FullName(sender)
    if not sender or sender == GR.MyName() then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    local ok, err = true
    if prefix == PREFIX_USER and channel == "GUILD" then
        ok, err = pcall(Sync.OnUserMessage, Sync, body, sender)
    elseif prefix == PREFIX_VER and channel == "GUILD" then
        local pd = tostring(body):match("%?(%d+)")
        if pd then ok, err = pcall(Sync.LearnPatchDay, Sync, sender, pd) end
    elseif prefix == PREFIX_SYNC then
        local u = Sync.users[sender]
        if u and u.ok then ok, err = pcall(Sync.OnSyncMessage, Sync, body, sender) end
    end
    if not ok then geterrorhandler()(err) end
end)

function Sync:OnModuleOff() self:ClearQueue() end
function Sync:OnModuleOn() WM.RunAfter(2, function() Sync:Hello() end) end
