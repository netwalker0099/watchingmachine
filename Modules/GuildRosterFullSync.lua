-- Watching Machine: Roster Manager's full catch-up sync
-- Live edits reach only who's online. This catches up on the rest:
--
--   * With Guild Roster Manager users online: their elected leader syncs
--     with each user in turn. We take part as a FOLLOWER in Guild Roster
--     Manager's own messages: we ask its leader, compare its lists of who
--     changed what and when with ours, send our newer join and promotion
--     dates, alt groups, custom notes, bans and birthdays, and take its
--     newer ones, with its sequence numbers and resends. We never stand for
--     leader (we don't answer its election), so a Guild Roster Manager user
--     always leads.
--   * Between Watching Machine users (no Guild Roster Manager online, or as
--     well): at login we ask for every record changed since we were last
--     online; guildmates send them one at a time, skipping any someone else
--     already sent (prefix WMRosterS).
--
-- Guild Roster Manager's full-sync format compiled with the help of its
-- research (Arkaan); the code is our own.

local AddonName, WM = ...
local GR = WM.GuildRoster
local Sync = GR.Sync
local Full = {}
Sync.Full = Full

local PREFIX_SYNC = "GRM_SYNC"
local MAX_BODY = 246
local TIMEOUT = 15            -- seconds of silence before we give up on a sync

local function DB() return GR.DB() end
local function On() return WM:IsModuleOn("GuildRoster") end
local function Now() return time() end
local function Me() return GR.MyName() end

-- ============================================
-- SENDING, WITH SEQUENCE NUMBERS
-- ============================================

local function Whisper(target, body)
    if #body > MAX_BODY then return false end
    return WM:QueueAddonMessage(PREFIX_SYNC, body, "WHISPER", target, true)
end

-- A packed message: "TAG?R?" then items until the next one wouldn't fit,
-- each message ending "?seq" (or "~|~seq"). Returns the messages sent.
function Full:Pack(tag, R, items, sep, store, counter)
    sep = sep or "?"
    local head = tag .. "?" .. R .. "?"
    local cur, out = {}, {}
    local function Flush()
        if #cur == 0 then return end
        self.seq[counter] = (self.seq[counter] or 0) + 1
        local body = head .. table.concat(cur, "?") .. sep .. self.seq[counter]
        store[counter] = store[counter] or {}
        store[counter][self.seq[counter]] = body
        Whisper(self.partner, body)
        out[#out + 1] = body
        cur = {}
    end
    for _, item in ipairs(items) do
        local trial = head .. table.concat(cur, "?") .. (#cur > 0 and "?" or "") .. item .. sep .. "99999"
        if #trial > MAX_BODY and #cur > 0 then Flush() end
        cur[#cur + 1] = item
    end
    Flush()
    return out
end

-- One record per message ("TAG?R?record~|~seq")
function Full:One(tag, R, record, sep, store, counter)
    self.seq[counter] = (self.seq[counter] or 0) + 1
    local body = tag .. "?" .. R .. "?" .. record .. (sep or "?") .. self.seq[counter]
    store[counter] = store[counter] or {}
    store[counter][self.seq[counter]] = body
    Whisper(self.partner, body)
    return body
end

-- ============================================
-- OUR LISTS (Guild Roster Manager's pre-check lists)
-- ============================================

local function Clean(s) return (tostring(s or ""):gsub("[%?~|]", "")) end

-- [name] = epoch, per category, for the categories we may share
function Full:OurLists()
    local g = GR:Guild()
    local L = { jd = {}, pd = {}, alt = {}, cust = {}, ban = {}, bday = {} }
    if not g then return L end
    for name, rec in pairs(g.members) do
        if rec.join and rec.join.verified and (rec.join.date or "") ~= "" and (rec.join.epoch or 0) > 0 then L.jd[name] = rec.join.epoch end
        if rec.promo and rec.promo.verified and (rec.promo.date or "") ~= "" and (rec.promo.epoch or 0) > 0 then L.pd[name] = rec.promo.epoch end
        local grp = rec.group and g.groups[rec.group]
        if grp then L.alt[name] = grp.modified or 0
        elseif (rec.groupLeft or 0) > 0 then L.alt[name] = rec.groupLeft end
        if DB().syncCustom and rec.custom and rec.custom.sync ~= false and (rec.custom.epoch or 0) > 0 then L.cust[name] = rec.custom.epoch end
        local b = (grp and grp.bday) or rec.bday
        if b and (b.epoch or 0) > 0 then L.bday[name] = b.epoch end
    end
    if DB().syncBans then
        for _, src in ipairs({ g.members, g.former }) do
            for name, rec in pairs(src) do
                if rec.ban and (rec.ban.on or rec.ban.unbanned) and (rec.ban.epoch or 0) > 0 then L.ban[name] = rec.ban.epoch end
            end
        end
    end
    return L
end

-- Markers: leader's list vs ours. 1 = the leader's is newer, 2 = ours is
function Full.Markers(theirs, ours)
    local need, give = {}, {}
    for name, e in pairs(theirs) do
        local mine = ours[name]
        if not mine or e > mine then need[#need + 1] = name
        elseif mine > e then give[#give + 1] = name end
    end
    for name in pairs(ours) do if theirs[name] == nil then give[#give + 1] = name end end
    table.sort(need)
    table.sort(give)
    return need, give
end

-- ============================================
-- THE FOLLOWER
-- ============================================
-- Full.partner: the leader we're syncing with. Full.phase: "pre", "data",
-- "final", "bday", "bdayfinal". Full.got[cat] = { [seq] = body }.

Full.leader = nil       -- the designated leader (from NEWLEADER / IAMLEADER)
Full.restrict = {}      -- the leader's last restriction values

function Full:Reset()
    self.partner, self.phase, self.lastActive = nil, nil, nil
    self.theirs = { jd = {}, pd = {}, alt = {}, cust = {}, ban = {}, bday = {} }
    self.seq, self.sent, self.got, self.counts = {}, {}, {}, {}
    self.altGroups, self.pendingSplit = {}, {}
end
Full:Reset()

function Full:Active() return self.partner ~= nil end

local function Touch() Full.lastActive = Now() end

function Full:Start(leader)
    self:Reset()
    self.partner = leader
    self.phase = "pre"
    Touch()
end

function Full:Finish(ok, why)
    local who = self.partner
    self:Reset()
    self.lastSync = Now()
    if ok then
        DB().lastFullSync = Now()
        GR:Log("info", "Caught up with " .. GR.Short(who or "?") .. " (Guild Roster Manager full sync).")
    elseif why then
        WM:VerbosePrint("GuildRoster", "Full sync stopped: " .. why)
    end
end

-- Silence for too long: give up
function Full:CheckTimeout()
    if self.partner and self.lastActive and Now() - self.lastActive > TIMEOUT then
        self:Finish(false, "no answer from " .. GR.Short(self.partner))
    end
end

local function Fields(payload) local t = {} for f in payload:gmatch("[^?]+") do t[#t + 1] = f end return t end
local function TFields(payload) local t = {} for f in payload:gmatch("[^~|]+") do t[#t + 1] = f end return t end

-- The sequence number at the end of a body
local function SeqOf(payload)
    local n = payload:match("[%?|](%d+)$")
    return tonumber(n)
end

-- Which category a received SYNCUP tag's messages are counted under
local UP_CAT = { GRM_JDSYNCUP = "jd", GRM_PDSYNCUP = "pd",
    GRM_ALTSYNCUP1 = "alt", GRM_ALTSYNCUP2 = "alt", GRM_ALTSYNCUP3 = "alt", GRM_ALTSYNCUP4 = "alt",
    GRM_CUSTSYNCUP1 = "cust", GRM_CUSTSYNCUP2 = "cust", GRM_CUSTSYNCUP3 = "cust",
    GRM_BANSYNCUP1 = "ban", GRM_BANSYNCUP2 = "ban", GRM_BANSYNCUP3 = "ban",
    GRM_BANSYNCUP4 = "ban", GRM_BANSYNCUP5 = "ban", GRM_BANSYNCUP6 = "ban", GRM_BDSYNCUP = "bday" }
local PRE_CAT = { GRM_RECJDPRE = "jd", GRM_RECPDPRE = "pd", GRM_RECALTPRE = "alt", GRM_RECCUSTPRE = "cust",
    GRM_RECBANPRE = "ban", GRM_RECBDAYPRE = "bday" }
-- Our data counters by category: F series (names) and data series
local F_COUNTER = { jd = "JDF", pd = "PDF", alt = "ALTF", cust = "CUSTF", ban = "BANF", bday = "BDAYF" }
local D_COUNTER = { jd = "JD", pd = "PD", alt = "ALT", cust = "CUST", ban = "BAN", bday = "BDAY" }
-- Their resend requests: tag -> our counter
local REQ_MIS = { GRM_REQMISJDF = "JDF", GRM_REQMISJD = "JD", GRM_REQMISPDF = "PDF", GRM_REQMISPD = "PD",
    GRM_REQMISALTF = "ALTF", GRM_REQMISALT = "ALT", GRM_REQMISCUSTF = "CUSTF", GRM_REQMISCUST = "CUST",
    GRM_REQMISBANF = "BANF", GRM_REQMISBAN = "BAN", GRM_REQMISBDAYF = "BDAYF", GRM_REQMISBDAY = "BDAY" }
local MISFIN_REPLY = { GRM_MISFIN = "GRM_MISSENT", GRM_MISFIN3 = "GRM_MISSENT3" }

local FULL_TAGS = { GRM_IAMLEADER = true, GRM_NEWLEADER = true, GRM_ELECTINFO = true, GRM_WHOISLEADER = true,
    GRM_ELECT = true, GRM_BUSY = true, GRM_REQJDDATA = true, GRM_PREHASHALL = true, GRM_FINALPRE = true,
    GRM_FINALPRE2 = true, GRM_FINALSTOP = true, GRM_FINALSTOP2 = true, GRM_MISSENT2 = true, GRM_MISSENT4 = true,
    GRM_COMPLETE = true, GRM_ENDSYNC = true, GRM_MISFIN = true, GRM_MISFIN3 = true }
for t in pairs(UP_CAT) do FULL_TAGS[t] = true end
for t in pairs(PRE_CAT) do FULL_TAGS[t] = true end
for t in pairs(REQ_MIS) do FULL_TAGS[t] = true end
function Full.Handles(tag) return FULL_TAGS[tag] or false end

local function NumRanks() return Sync.NumRanks() end

-- Guild Roster Manager's class numbers
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local CLASS_FILES = {}
for k, v in pairs(CLASS_IDS) do CLASS_FILES[v] = k end
function Sync.ClassID(class) return CLASS_IDS[class or ""] or 0 end
function Sync.ClassFile(id) return CLASS_FILES[id or 0] end

-- May we share with / take from this leader? (its rank against our limits)
local function LeaderRank() local rec = GR:Find(Full.partner or Full.leader or "") return rec and rec.rankIndex end
local function MayTake(cat)
    local r = LeaderRank()
    if not r then return false end
    if cat == "cust" then return DB().syncCustom and r <= Sync.CustomRank() end
    if cat == "ban" then return DB().syncBans and r <= Sync.BanRank() end
    return r <= Sync.SyncRank()
end
Full.MayTake = MayTake

-- ============================================
-- WHAT WE SEND IN THE DATA PHASE
-- ============================================

local function JoinYMD(rec) return (rec.join and rec.join.date ~= "" and rec.join.date) or "0" end

function Full:SendData()
    local g = GR:Guild()
    if not g or not self.partner then return end
    local ours = self:OurLists()
    local R = NumRanks()
    local RB = Sync.BanRank()
    local store = self.sent
    self.flags = self.flags or { jd = true, pd = true, alt = true, cust = true, bday = true, ban = true }
    for _, cat in ipairs({ "jd", "pd", "alt", "cust", "ban" }) do
        local need, give = Full.Markers(self.theirs[cat], ours[cat])
        if not self.flags[cat] then need, give = {}, {} end
        if not MayTake(cat) then need = {} end
        local r = (cat == "ban") and RB or R
        local names = {}
        for _, n in ipairs(need) do names[#names + 1] = Clean(n) end
        local fTag = ({ jd = "GRM_JDSYNCF", pd = "GRM_PDSYNCF", alt = "GRM_ALTSYNCF", cust = "GRM_CUSTSYNCF", ban = "GRM_BANSYNCF" })[cat]
        self:Pack(fTag, r, names, "?", store, F_COUNTER[cat])
        if cat == "jd" or cat == "pd" then
            local items = {}
            for _, n in ipairs(give) do
                local rec = g.members[n]
                local d = rec and (cat == "jd" and rec.join or rec.promo)
                if d and d.date ~= "" then items[#items + 1] = Clean(n) .. "?" .. d.date .. "?" .. (d.epoch or 0) end
            end
            self:Pack(cat == "jd" and "GRM_JDSYNC" or "GRM_PDSYNC", r, items, "?", store, D_COUNTER[cat])
        elseif cat == "alt" then
            local ungrouped, single, headers, done = {}, {}, {}, {}
            for _, n in ipairs(give) do
                local rec = g.members[n]
                local grp = rec and rec.group and g.groups[rec.group]
                if rec and not grp then
                    ungrouped[#ungrouped + 1] = Clean(n) .. "?" .. (rec.groupLeft or 0)
                elseif grp and not done[rec.group] then
                    done[rec.group] = true
                    local members = {}
                    for _, m in ipairs(grp.members) do members[#members + 1] = m end
                    table.sort(members)
                    if #members == 1 and grp.main == members[1] then
                        single[#single + 1] = Clean(members[1]) .. "?" .. (grp.modified or 0)
                    elseif #members >= 1 then
                        headers[#headers + 1] = { members = members, main = grp.main, modified = grp.modified or 0 }
                    end
                end
            end
            self:Pack("GRM_ALTSYNC1", r, ungrouped, "?", store, "ALT")
            self:Pack("GRM_ALTSYNC2", r, single, "?", store, "ALT")
            for _, h in ipairs(headers) do
                local lead = h.members[1]
                self:One("GRM_ALTSYNC3", r, Clean(lead) .. "?" .. ((h.main ~= "" and Clean(h.main)) or "#") .. "?" .. h.modified, "?", store, "ALT")
                local rest = {}
                for i = 2, #h.members do rest[#rest + 1] = Clean(h.members[i]) end
                -- Members: "lead?m2?m3..." in as many messages as needed
                local cur = {}
                local function FlushMembers()
                    if #cur == 0 then return end
                    self:One("GRM_ALTSYNC4", r, Clean(lead) .. "?" .. table.concat(cur, "?"), "?", store, "ALT")
                    cur = {}
                end
                for _, m in ipairs(rest) do
                    if #("GRM_ALTSYNC4?" .. r .. "?" .. lead .. "?" .. table.concat(cur, "?") .. "?" .. m .. "?99999") > MAX_BODY then FlushMembers() end
                    cur[#cur + 1] = m
                end
                FlushMembers()
            end
        elseif cat == "cust" then
            for _, n in ipairs(give) do
                local rec = g.members[n]
                local c = rec and rec.custom
                if c then
                    local text = Clean(c.text)
                    if text == "" then text = "#" end
                    local head = Clean(n) .. "~|~" .. (c.epoch or 0) .. "~|~" .. ((c.editor and Clean(c.editor) ~= "" and Clean(c.editor)) or "#") .. "~|~"
                    if #("GRM_CUSTSYNC1?" .. r .. "?" .. head .. text .. "~|~99999") <= MAX_BODY then
                        self:One("GRM_CUSTSYNC1", r, head .. text, "~|~", store, "CUST")
                    else
                        self:One("GRM_CUSTSYNC2", r, head .. text:sub(1, 99), "~|~", store, "CUST")
                        self:One("GRM_CUSTSYNC3", r, Clean(n) .. "~|~" .. text:sub(100), "~|~", store, "CUST")
                    end
                end
            end
        elseif cat == "ban" then
            for _, n in ipairs(give) do
                local rec, former = g.members[n], false
                if not rec then rec, former = g.former[n], true end
                local b = rec and rec.ban
                if b then
                    local kind = b.on and 1 or 2
                    local by = (b.by and Clean(b.by) ~= "" and Clean(b.by)) or "#"
                    local reason = Clean(b.reason)
                    if reason == "" then reason = "###" end
                    local function Build(rs)
                        if former then
                            return Clean(n) .. "~|~" .. (Sync.ClassID and Sync.ClassID(rec.class) or 0) .. "~|~" .. ((rec.rankName and rec.rankName ~= "" and Clean(rec.rankName)) or "##")
                                .. "~|~" .. (rec.rankIndex or 99) .. "~|~" .. (rec.level or 1) .. "~|~" .. JoinYMD(rec) .. "~|~"
                                .. ((rec.join and rec.join.epoch) or 0) .. "~|~" .. ((rec.guid and rec.guid:gsub("^Player%-", "")) or "#")
                                .. "~|~" .. kind .. "~|~" .. (b.epoch or 0) .. "~|~" .. by .. "~|~" .. rs
                        end
                        return Clean(n) .. "~|~" .. kind .. "~|~" .. (b.epoch or 0) .. "~|~" .. by .. "~|~" .. rs
                    end
                    -- Never split a ban record: shorten the reason to fit
                    local tag = former and "GRM_BANSYNC1" or "GRM_BANSYNC4"
                    local rec2 = Build(reason)
                    while #(tag .. "?" .. r .. "?" .. rec2 .. "~|~99999") > MAX_BODY and #reason > 3 do
                        reason = reason:sub(1, #reason - 10)
                        rec2 = Build(reason)
                    end
                    self:One(tag, r, rec2, "~|~", store, "BAN")
                end
            end
        end
    end
    Whisper(self.partner, table.concat({ "GRM_STOP", R, self.seq.JDF or 0, self.seq.JD or 0, self.seq.PDF or 0, self.seq.PD or 0,
        self.seq.ALTF or 0, self.seq.ALT or 0, self.seq.CUSTF or 0, self.seq.CUST or 0, self.seq.BANF or 0, self.seq.BAN or 0 }, "?"))
    self.phase = "final"
    Touch()
end

function Full:SendBirthdays()
    local g = GR:Guild()
    if not g or not self.partner then return end
    local ours = self:OurLists()
    local need, give = Full.Markers(self.theirs.bday, ours.bday)
    if not MayTake("bday") then need = {} end
    local R = NumRanks()
    local names = {}
    for _, n in ipairs(need) do names[#names + 1] = Clean(n) end
    self:Pack("GRM_BDAYSYNCF", R, names, "?", self.sent, "BDAYF")
    local items = {}
    for _, n in ipairs(give) do
        local rec = g.members[n]
        local grp = rec and rec.group and g.groups[rec.group]
        local b = (grp and grp.bday) or (rec and rec.bday)
        if b and (b.epoch or 0) > 0 then items[#items + 1] = Clean(n) .. "?" .. b.epoch .. "?" .. (b.d or 0) .. "?" .. (b.m or 0) end
    end
    self:Pack("GRM_BDSYNC", R, items, "?", self.sent, "BDAY")
    Whisper(self.partner, table.concat({ "GRM_STOP2", R, self.seq.BDAYF or 0, self.seq.BDAY or 0 }, "?"))
    self.phase = "bdayfinal"
    Touch()
end

-- ============================================
-- WHAT WE TAKE (the leader's SYNCUP records)
-- ============================================

local function Remote(fn, ...)
    GR.applyingRemote = true
    local ok, a = pcall(fn, ...)
    GR.applyingRemote = false
    return ok and a
end

function Full:ApplyUp(tag, payload)
    local g = GR:Guild()
    if not g then return end
    local cat = UP_CAT[tag]
    if not MayTake(cat) then return end
    if tag == "GRM_JDSYNCUP" or tag == "GRM_PDSYNCUP" then
        local f = Fields(payload)
        local name, stamp, epoch = GR.FullName(f[1]), f[2], tonumber(f[3])
        if name and stamp and epoch and g.members[name] then
            Remote(tag == "GRM_JDSYNCUP" and GR.SetJoinDate or GR.SetPromoDate, GR, name, stamp, epoch, true)
        end
    elseif tag == "GRM_ALTSYNCUP1" then
        local f = Fields(payload)
        local name, epoch = GR.FullName(f[1]), tonumber(f[2])
        if name and epoch then
            if not Remote(GR.RemoveAlt, GR, name, epoch, true) then
                local rec = GR:Find(name)
                if rec and not rec.group then rec.groupLeft = math.max(rec.groupLeft or 0, epoch) end
            end
        end
    elseif tag == "GRM_ALTSYNCUP2" then
        local f = Fields(payload)
        local name, epoch = GR.FullName(f[1]), tonumber(f[2])
        if name and epoch then
            Remote(GR.RemoveAlt, GR, name, epoch, true)
            Remote(GR.SetMain, GR, name, epoch, true)
        end
    elseif tag == "GRM_ALTSYNCUP3" then
        local f = Fields(payload)
        local lead = GR.FullName(f[1])
        if lead then
            self.altGroups[lead] = { main = (f[2] ~= "#") and GR.FullName(f[2]) or "", modified = tonumber(f[3]) or 0,
                count = tonumber(f[4]) or 0, members = { lead } }
        end
    elseif tag == "GRM_ALTSYNCUP4" then
        local f = Fields(payload)
        local lead = GR.FullName(f[1])
        local grp = lead and self.altGroups[lead]
        if grp then
            for i = 2, #f do grp.members[#grp.members + 1] = GR.FullName(f[i]) end
        end
    elseif tag == "GRM_CUSTSYNCUP1" or tag == "GRM_CUSTSYNCUP2" then
        local f = TFields(payload)
        local name, epoch, editor, text = GR.FullName(f[1]), tonumber(f[2]), f[3], f[4]
        if not (name and epoch) then return end
        if text == "#" then text = "" end
        if tag == "GRM_CUSTSYNCUP2" then
            self.pendingSplit["c:" .. name] = { epoch = epoch, editor = editor, text = text or "" }
        else
            Remote(GR.SetCustomNote, GR, name, text or "", epoch, editor ~= "#" and editor or nil, true)
        end
    elseif tag == "GRM_CUSTSYNCUP3" then
        local f = TFields(payload)
        local name = GR.FullName(f[1])
        local first = name and self.pendingSplit["c:" .. name]
        if first then
            self.pendingSplit["c:" .. name] = nil
            Remote(GR.SetCustomNote, GR, name, first.text .. (f[2] or ""), first.epoch, first.editor ~= "#" and first.editor or nil, true)
        end
    elseif tag == "GRM_BANSYNCUP1" or tag == "GRM_BANSYNCUP2" or tag == "GRM_BANSYNCUP4" or tag == "GRM_BANSYNCUP5" then
        local f = TFields(payload)
        local name, epoch, kind, by = GR.FullName(f[1]), tonumber(f[2]), tonumber(f[3]), f[4]
        if not (name and epoch and kind) then return end
        local reason, class, guid
        if tag == "GRM_BANSYNCUP1" then
            class = Sync.ClassFile and Sync.ClassFile(tonumber(f[8])) or nil
            guid = (f[11] and f[11] ~= "#") and ("Player-" .. f[11]) or nil
            reason = f[12]
        elseif tag == "GRM_BANSYNCUP4" then
            reason = f[5]
        end
        if tag == "GRM_BANSYNCUP2" or tag == "GRM_BANSYNCUP5" then
            self.pendingSplit["b:" .. name] = { epoch = epoch, kind = kind, by = by }
            return
        end
        self:ApplyBan(name, epoch, kind, by, reason, class, guid)
    elseif tag == "GRM_BANSYNCUP3" or tag == "GRM_BANSYNCUP6" then
        local f = TFields(payload)
        local name = GR.FullName(f[1])
        local first = name and self.pendingSplit["b:" .. name]
        if first then
            self.pendingSplit["b:" .. name] = nil
            self:ApplyBan(name, first.epoch, first.kind, first.by, f[2])
        end
    elseif tag == "GRM_BDSYNCUP" then
        local f = Fields(payload)
        local name, epoch, d, m = GR.FullName(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
        if name and epoch and g.members[name] then
            Remote(GR.SetBirthday, GR, name, (d or 0) > 0 and d or 0, (m or 0) > 0 and m or 0, epoch, true)
        end
    end
end

function Full:ApplyBan(name, epoch, kind, by, reason, class, guid)
    local rec = GR:Find(name)
    if rec and rec.ban and (rec.ban.epoch or 0) > epoch then return end
    if reason == "###" then reason = "" end
    if by == "#" or by == "X" then by = nil end
    Remote(GR.SetBan, GR, name, kind == 1, reason, epoch, by and GR.FullName(by) or nil, true, class, guid)
end

-- Alt groups: only complete ones are rebuilt; then each group shares one birthday
function Full:ApplyAltGroups()
    for _, grp in pairs(self.altGroups) do
        if #grp.members >= math.max(1, grp.count) then
            local cur = GR:Find(grp.members[1])
            local g = GR:Guild()
            local have = cur and cur.group and g.groups[cur.group]
            if not have or (have.modified or 0) <= grp.modified then
                Remote(GR.ApplyGroup, GR, grp.members, grp.main, grp.modified)
            end
        end
    end
    self.altGroups = {}
end

-- What we're missing from the leader's numbered messages
function Full:Missing(cat, count)
    local got = self.got[cat] or {}
    local out = {}
    for n = 1, count or 0 do if not got[n] then out[#out + 1] = tostring(n) end end
    return out
end

-- ============================================
-- RECEIVING
-- ============================================

function Full:OnMessage(tag, rest, sender, R)
    if not On() then return end
    local payload = rest or ""
    -- Election: learn who leads; we never stand for leader
    if tag == "GRM_IAMLEADER" or tag == "GRM_NEWLEADER" then
        local f = Fields(payload)
        local leader = tag == "GRM_IAMLEADER" and sender or GR.FullName(f[1])
        if leader then
            self.leader = leader
            local base = tag == "GRM_NEWLEADER" and 1 or 0
            self.restrict = { ban = tonumber(f[base + 1]), max = tonumber(f[base + 2]), sync = tonumber(f[base + 3]), custom = tonumber(f[base + 4]) }
            if self.wantSync and leader ~= Me() and not self:Active() then
                self.wantSync = nil
                WM.RunAfter(tag == "GRM_NEWLEADER" and 0.5 or 2.5, function() Full:Request() end)
            end
        end
        return
    elseif tag == "GRM_ELECTINFO" then
        if self.electing then
            local f = Fields(payload)
            local name, at, rank = GR.FullName(f[1]), tonumber(f[2]), tonumber(f[3])
            if name then self.candidates[#self.candidates + 1] = { name = name, at = at or 0, rank = rank or 99, f = f } end
        end
        return
    elseif tag == "GRM_WHOISLEADER" or tag == "GRM_ELECT" or tag == "GRM_BUSY" then
        return
    end
    -- Everything else is a sync with our leader
    if tag == "GRM_REQJDDATA" then
        local f = Fields(payload)
        if GR.FullName(f[1]) == Me() and not self:Active() then
            self:Start(sender)
        end
        return
    end
    if not self.partner or sender ~= self.partner then return end
    Touch()
    if tag == "GRM_ENDSYNC" then
        self:Finish(false, "the leader stopped")
    elseif tag == "GRM_PREHASHALL" then
        -- We compare everything (the hashes only save a round trip)
        local flags = { "1", "1", "1", DB().syncCustom and "1" or "0", "1", DB().syncBans and "1" or "0" }
        self.flags = { jd = true, pd = true, alt = true, cust = flags[4] == "1", bday = true, ban = flags[6] == "1" }
        Whisper(self.partner, "GRM_PREALLRESULT?" .. NumRanks() .. "?" .. table.concat(flags))
    elseif PRE_CAT[tag] then
        local cat = PRE_CAT[tag]
        local f = Fields(payload)
        for i = 1, #f - 1, 2 do
            local name, epoch = GR.FullName(f[i]), tonumber(f[i + 1])
            if name and epoch then self.theirs[cat][name] = epoch end
        end
    elseif tag == "GRM_FINALPRE" then
        self.phase = "data"
        WM.RunAfter(1.25, function() if Full.partner then Full:SendData() end end)
    elseif REQ_MIS[tag] then
        self.resend = self.resend or {}
        for n in payload:gmatch("%d+") do
            local body = self.sent[REQ_MIS[tag]] and self.sent[REQ_MIS[tag]][tonumber(n)]
            if body then self.resend[#self.resend + 1] = body end
        end
    elseif MISFIN_REPLY[tag] then
        for _, body in ipairs(self.resend or {}) do Whisper(self.partner, body) end
        self.resend = nil
        Whisper(self.partner, MISFIN_REPLY[tag] .. "?" .. NumRanks() .. "?")
    elseif UP_CAT[tag] then
        local cat = UP_CAT[tag]
        local seq = SeqOf(payload)
        self.got[cat] = self.got[cat] or {}
        if seq and self.got[cat][seq] then return end      -- a resend we already have
        if seq then self.got[cat][seq] = true end
        local body = payload:gsub("[%?|~]+%d+$", "")
        self:ApplyUp(tag, body)
    elseif tag == "GRM_FINALSTOP" or tag == "GRM_FINALSTOP2" then
        local f = Fields(payload)
        local counts = tag == "GRM_FINALSTOP"
            and { jd = tonumber(f[1]), pd = tonumber(f[2]), alt = tonumber(f[3]), cust = tonumber(f[4]), ban = tonumber(f[5]) }
            or { bday = tonumber(f[1]) }
        local reqTags = tag == "GRM_FINALSTOP"
            and { { "jd", "GRM_REQJDFIN" }, { "pd", "GRM_REQPDFIN" }, { "alt", "GRM_REQALTFIN" }, { "cust", "GRM_REQCUSTFIN" }, { "ban", "GRM_REQBANFIN" } }
            or { { "bday", "GRM_REQBDAYFIN" } }
        local any = false
        for _, rt in ipairs(reqTags) do
            local miss = self:Missing(rt[1], counts[rt[1]])
            if #miss > 0 then
                any = true
                local cur = {}
                for _, n in ipairs(miss) do
                    if #(rt[2] .. "?" .. NumRanks() .. "?" .. table.concat(cur, "?") .. "?" .. n) > MAX_BODY then
                        Whisper(self.partner, rt[2] .. "?" .. NumRanks() .. "?" .. table.concat(cur, "?"))
                        cur = {}
                    end
                    cur[#cur + 1] = n
                end
                Whisper(self.partner, rt[2] .. "?" .. NumRanks() .. "?" .. table.concat(cur, "?"))
            end
        end
        if any then
            self.waitingFor = tag == "GRM_FINALSTOP" and "GRM_MISSENT2" or "GRM_MISSENT4"
            Whisper(self.partner, (tag == "GRM_FINALSTOP" and "GRM_MISFIN2" or "GRM_MISFIN4") .. "?" .. NumRanks() .. "?")
        else
            self:AfterFinal(tag)
        end
    elseif tag == "GRM_MISSENT2" or tag == "GRM_MISSENT4" then
        if self.waitingFor == tag then
            self.waitingFor = nil
            self:AfterFinal(tag == "GRM_MISSENT2" and "GRM_FINALSTOP" or "GRM_FINALSTOP2")
        end
    elseif tag == "GRM_FINALPRE2" then
        self.phase = "bday"
        WM.RunAfter(1.25, function() if Full.partner then Full:SendBirthdays() end end)
    elseif tag == "GRM_COMPLETE" then
        local f = Fields(payload)
        if GR.FullName(f[1]) == Me() then self:Finish(true) end
    end
end

function Full:AfterFinal(tag)
    if tag == "GRM_FINALSTOP" then
        self:ApplyAltGroups()
        Whisper(self.partner, "GRM_ALTPROCESSED?" .. NumRanks() .. "?")
    else
        Whisper(self.partner, "GRM_FINALSTOP3?" .. NumRanks() .. "?")
    end
    Touch()
end

-- ============================================
-- ASKING FOR A SYNC
-- ============================================

-- Ask the designated leader to sync with us
function Full:Request()
    if not On() or not Sync:Enabled() or self:Active() then return false end
    if not self.leader or self.leader == Me() then return false end
    Sync.Send(PREFIX_SYNC, "GRM_REQUESTSYNC?" .. NumRanks() .. "?", "WHISPER", self.leader)
    return true
end

-- Who leads? Ask; if nobody says, hold an election among Guild Roster
-- Manager users (we don't stand) and ask the winner
function Full:Begin()
    if not On() or not Sync:Enabled() or self:Active() then return false end
    if IsInGroup and IsInGroup() then return false end
    if not DB().fullSync then return false end
    if self.wantSync or self.electing then return false end      -- already asking
    local r = Sync.SyncRank()
    local restr = table.concat({ Sync.SyncRank(), Sync.BanRank(), Sync.SyncRank(), Sync.SyncRank(), Sync.CustomRank() }, "?")
    self.wantSync = true
    Sync.Send(PREFIX_SYNC, "GRM_WHOISLEADER?" .. restr, "GUILD")
    WM.RunAfter(2.5, function()
        if not Full.wantSync then return end          -- a leader answered
        Full.electing, Full.candidates = true, {}
        Sync.Send(PREFIX_SYNC, "GRM_ELECT?" .. r .. "?", "GUILD")
        WM.RunAfter(2.5, function() Full:Elect() end)
    end)
    return true
end

function Full:Elect()
    self.electing = false
    local best
    for _, c in ipairs(self.candidates or {}) do
        if not best or c.rank < best.rank or (c.rank == best.rank and c.at < best.at) then best = c end
    end
    self.candidates = {}
    if not best then self.wantSync = nil return false end       -- no Guild Roster Manager user online
    local f = best.f
    Sync.Send(PREFIX_SYNC, table.concat({ "GRM_NEWLEADER", Sync.SyncRank(), best.name, f[4] or Sync.BanRank(), f[5] or Sync.SyncRank(),
        f[6] or Sync.SyncRank(), f[7] or Sync.CustomRank() }, "?"), "GUILD")
    self.leader = best.name
    self.wantSync = nil
    WM.RunAfter(0.5, function() Full:Request() end)
    return true
end

-- ============================================
-- WATCHING MACHINE USERS: CATCH-UP AT LOGIN
-- ============================================
-- "C", since: send me every record changed since then. "E", record.

-- (the codec file loads after this one: looked up when used)
local function Codec() return WM.LootCodec end
local PREFIX_WM = "WMRosterS"
local DRIP, MARGIN = 0.6, 3600
local heard, seqNo = {}, 0
local drip, dripSet, dripTimer = {}, {}, nil

local function ChangedAt(rec, g)
    local t = 0
    for _, v in ipairs({ rec.join and rec.join.epoch, rec.promo and rec.promo.epoch, rec.custom and rec.custom.epoch,
        rec.bday and rec.bday.epoch, rec.ban and rec.ban.epoch, rec.groupLeft }) do
        if tonumber(v) and v > t then t = v end
    end
    local grp = rec.group and g.groups[rec.group]
    if grp and (grp.modified or 0) > t then t = grp.modified end
    return t
end
Full.ChangedAt = ChangedAt

function Full.PackRecord(rec, g)
    local w = { n = rec.name, t = ChangedAt(rec, g) }
    if rec.join and rec.join.verified and rec.join.date ~= "" then w.j = { rec.join.date, rec.join.epoch or 0 } end
    if rec.promo and rec.promo.verified and rec.promo.date ~= "" then w.p = { rec.promo.date, rec.promo.epoch or 0 } end
    if DB().syncCustom and rec.custom and rec.custom.sync ~= false and (rec.custom.epoch or 0) > 0 then
        w.c = { rec.custom.text or "", rec.custom.epoch, rec.custom.editor or "" }
    end
    local grp = rec.group and g.groups[rec.group]
    local b = (grp and grp.bday) or rec.bday
    if b and (b.epoch or 0) > 0 then w.b = { b.d or 0, b.m or 0, b.epoch } end
    if DB().syncBans and rec.ban and (rec.ban.on or rec.ban.unbanned) and (rec.ban.epoch or 0) > 0 then
        w.x = { rec.ban.on and 1 or 0, rec.ban.epoch, rec.ban.by or "", rec.ban.reason or "" }
    end
    if grp then w.g = { grp.members, grp.main or "", grp.modified or 0 }
    elseif (rec.groupLeft or 0) > 0 then w.l = rec.groupLeft end
    return w
end

function Full.ApplyRecord(w, sender)
    local g = GR:Guild()
    local name = type(w) == "table" and GR.FullName(w.n)
    if not g or not name then return false end
    local rec = g.members[name] or g.former[name]
    if not rec then return false end
    local r = Sync.users[sender]
    local senderRank = GR:Find(sender) and GR:Find(sender).rankIndex
    local okRank = senderRank and senderRank <= Sync.SyncRank()
    if okRank and type(w.j) == "table" then Remote(GR.SetJoinDate, GR, name, w.j[1], tonumber(w.j[2]), true) end
    if okRank and type(w.p) == "table" then Remote(GR.SetPromoDate, GR, name, w.p[1], tonumber(w.p[2]), true) end
    if type(w.c) == "table" and DB().syncCustom and senderRank and senderRank <= Sync.CustomRank() then
        Remote(GR.SetCustomNote, GR, name, w.c[1], tonumber(w.c[2]), w.c[3] ~= "" and w.c[3] or nil, true)
    end
    if okRank and type(w.b) == "table" then Remote(GR.SetBirthday, GR, name, tonumber(w.b[1]), tonumber(w.b[2]), tonumber(w.b[3]), true) end
    if type(w.x) == "table" and DB().syncBans and senderRank and senderRank <= Sync.BanRank() then
        local epoch = tonumber(w.x[2]) or 0
        if not rec.ban or (rec.ban.epoch or 0) < epoch then
            Remote(GR.SetBan, GR, name, w.x[1] == 1, w.x[4], epoch, w.x[3] ~= "" and w.x[3] or nil, true)
        end
    end
    if okRank and type(w.g) == "table" and type(w.g[1]) == "table" then
        local have = rec.group and g.groups[rec.group]
        if not have or (have.modified or 0) < (tonumber(w.g[3]) or 0) then
            Remote(GR.ApplyGroup, GR, w.g[1], w.g[2] or "", tonumber(w.g[3]) or 0)
        end
    elseif okRank and tonumber(w.l) and not rec.group then
        rec.groupLeft = math.max(rec.groupLeft or 0, tonumber(w.l))
    end
    return true
end

local function WMEnabled() return On() and DB().sync and IsInGuild and IsInGuild() end

local function SendWM(kind, payload)
    for _, part in ipairs(Codec().Frame(Codec().Serialize(kind, payload))) do
        WM:QueueAddonMessage(PREFIX_WM, part, "GUILD")
    end
end

local function Heard(name, t)
    seqNo = seqNo + 1
    local h = heard[name]
    if not h or h.t < t then heard[name] = { t = t, seq = seqNo } elseif h.t == t then h.seq = seqNo end
end

local function DripNext()
    dripTimer = nil
    if not WMEnabled() then return end
    local g = GR:Guild()
    while #drip > 0 do
        local item = table.remove(drip, 1)
        dripSet[item.name] = nil
        local rec = g and (g.members[item.name] or g.former[item.name])
        local h = heard[item.name]
        if rec and not (h and h.t >= ChangedAt(rec, g) and h.seq > item.seq) then
            local w = Full.PackRecord(rec, g)
            SendWM("E", w)
            Heard(item.name, w.t)
            Full.wmSent = (Full.wmSent or 0) + 1
            if #drip > 0 and C_Timer then dripTimer = C_Timer.NewTimer(DRIP, DripNext) end
            return
        end
    end
end

function Full:OnCatchUp(since)
    if not WMEnabled() then return end
    local g = GR:Guild()
    if not g then return end
    local new = {}
    for _, src in ipairs({ g.members, g.former }) do
        for name, rec in pairs(src) do
            local t = ChangedAt(rec, g)
            if t > since then
                if dripSet[name] then dripSet[name].seq = seqNo
                else
                    dripSet[name] = { name = name, t = t, seq = seqNo }
                    new[#new + 1] = dripSet[name]
                end
            end
        end
    end
    if #new == 0 then return end
    table.sort(new, function(a, b) return a.t > b.t end)
    for _, it in ipairs(new) do drip[#drip + 1] = it end
    if not dripTimer and C_Timer then dripTimer = C_Timer.NewTimer(2 + math.random() * 6, DripNext) end
end
function Full.CatchUpLength() return #drip end

local unframe
function Full:OnWMMessage(prefix, msg, dist, sender)
    if prefix ~= PREFIX_WM or dist ~= "GUILD" or not WMEnabled() then return end
    sender = GR.FullName(sender)
    if not sender or sender == Me() then return end
    unframe = unframe or Codec().NewUnframer()
    local whole = unframe(sender, msg)
    if not whole then return end
    local ok, kind, payload = Codec().Deserialize(whole)
    if not ok then return end
    if kind == "C" then
        self:OnCatchUp(tonumber(payload) or 0)
    elseif kind == "E" and type(payload) == "table" then
        Heard(GR.FullName(payload.n) or "?", tonumber(payload.t) or 0)
        if Full.ApplyRecord(payload, sender) then Full.wmReceived = (Full.wmReceived or 0) + 1 end
    end
end

function Full:HelloWM()
    if self.greeted or not WMEnabled() then return end
    self.greeted = true
    local last = tonumber(DB().rosterLastOnline) or 0
    SendWM("C", math.max(0, last > 0 and (last - MARGIN) or 0))
    DB().rosterLastOnline = Now()
end

function Full:StopWM()
    if dripTimer then dripTimer:Cancel(); dripTimer = nil end
    wipe(drip); wipe(dripSet)
    WM:ClearAddonQueue({ [PREFIX_WM] = true })
end

function Full:ResetForTests()
    wipe(heard); wipe(drip); wipe(dripSet)
    if dripTimer then dripTimer:Cancel(); dripTimer = nil end
    self.greeted = nil
    self:Reset()
end

local wmEvents = CreateFrame("Frame")
wmEvents:SetScript("OnEvent", function(_, event, ...)
    if not On() then return end
    if event == "CHAT_MSG_ADDON" then Full:OnWMMessage(...)
    elseif event == "PLAYER_LOGOUT" then DB().rosterLastOnline = Now() end
end)

-- Every few seconds: time-outs
local ticker
function Full:Init()
    if self.started then return end
    self.started = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX_WM) end
    WM:RegisterEvents(wmEvents, { "CHAT_MSG_ADDON", "PLAYER_LOGOUT" })
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(5, function() Full:CheckTimeout() end) end
    -- After login: Watching Machine users first, then Guild Roster Manager's leader
    WM.RunAfter(40, function() Full:HelloWM() end)
    WM.RunAfter(60, function() Full:Begin() end)
end

function Full:Stop()
    if self.partner then Whisper(self.partner, "GRM_ENDSYNC?") end
    self:Reset()
    self:StopWM()
end
