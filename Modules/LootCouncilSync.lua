-- Watching Machine: Loot Council history shared between Watching Machine users
-- Guildmates running Watching Machine keep the same loot history:
--   * an award made or recorded live (a council or roll-off award, one an
--     RCLootCouncil master looter logged) and every edit or delete goes to
--     the guild as it happens
--   * at login you ask for everything changed since you were last online
--     (all of it, the first time); guildmates send it one award at a time,
--     skipping any someone else has already sent, so each goes out about once
--   * the same award is matched everywhere by RCLootCouncil's id, Gargul's
--     checksum, or who awarded it and when; the latest change wins
-- Awards imported from Gargul's or RCLootCouncil's saved data aren't sent
-- one by one; guildmates catch up on them at login.
--
-- Messages (prefix WMLootH, guild channel): our serializer's text, split
-- like AceComm's messages:  "E", award   /   "C", since

local AddonName, WM = ...
local LC = WM.LootCouncil
local Codec = WM.LootCodec
local Sync = {}
LC.Sync = Sync

local PREFIX = "WMLootH"
local DRIP = 0.6                -- seconds between awards sent for a catch-up
local MARGIN = 3600             -- a catch-up starts this long before you were last online

local function On() return WM:IsModuleOn("LootCouncil") end
local function DB() return LC.DB() end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end
local function MyKey() return LC.Key(UnitName("player")) end

function Sync.Enabled()
    return On() and DB().syncHistory ~= false and IsInGuild and IsInGuild() and true or false
end

-- ============================================
-- AN AWARD ON THE WIRE
-- ============================================

local FIELDS = { link = "l", itemID = "i", to = "o", by = "b", t = "t", how = "h", rid = "r", reason = "x",
    boss = "s", zone = "z", votes = "v", note = "n", class = "k", deleted = "d", mod = "m", de = "e", os = "f", sr = "w" }

function Sync.Pack(e)
    local w = { g = LC.GlobalId(e) }
    for k, short in pairs(FIELDS) do
        local v = e[k]
        if v ~= nil and v ~= false then w[short] = v end
    end
    if not w.m then w.m = e.t end
    if e.color then w.c = { e.color[1], e.color[2], e.color[3] } end
    if e.src then w.a = { rc = e.src.rc, gl = e.src.gl } end
    return w
end

function Sync.Unpack(w)
    if type(w) ~= "table" or type(w.g) ~= "string" then return nil end
    local e = { gid = w.g }
    for k, short in pairs(FIELDS) do e[k] = w[short] end
    if type(w.c) == "table" then e.color = { w.c[1], w.c[2], w.c[3] } end
    e.src = {}
    if type(w.a) == "table" then e.src.rc, e.src.gl = w.a.rc, w.a.gl end
    e.itemID = tonumber(e.itemID)
    e.t, e.mod = tonumber(e.t), tonumber(e.mod) or tonumber(e.t)
    if not e.itemID or not e.t then return nil end
    return e
end

-- The award we already have for this one, if any
function Sync.Find(e)
    local db = DB()
    local id = db.sources["g:" .. e.gid] or db.sources[e.gid]
    if not id and e.src then
        if e.src.rc then id = db.sources["rc:" .. tostring(e.src.rc)] end
        if not id and e.src.gl then id = db.sources["gl:" .. tostring(e.src.gl)] end
    end
    return id and db.history[id]
end

-- ============================================
-- SENDING
-- ============================================

local heard = {}      -- [gid] = { mod, seq }: newest change sent or heard
local seq = 0
local function Heard(gid, mod)
    seq = seq + 1
    local h = heard[gid]
    if not h or h.mod < mod then heard[gid] = { mod = mod, seq = seq }
    elseif h.mod == mod then h.seq = seq end
end
local function SentSince(gid, mod, since)
    local h = heard[gid]
    return h ~= nil and h.mod >= mod and h.seq > since
end

local function Send(kind, payload, urgent)
    local text = Codec.Serialize(kind, payload)
    for _, part in ipairs(Codec.Frame(text)) do
        WM:QueueAddonMessage(PREFIX, part, "GUILD", nil, urgent)
    end
end

function Sync:ShareRaid(r, key)
    if not Sync.Enabled() or not r then return false end
    Send("A", { t = r.t, z = r.zone, b = r.boss, m = r.members })
    Heard("raid:" .. key, r.t or 0)
    return true
end

function Sync:Share(e)
    if not Sync.Enabled() or not e then return false end
    local w = Sync.Pack(e)
    Send("E", w)
    Heard(w.g, w.m or 0)
    Sync.sent = (Sync.sent or 0) + 1
    return true
end

-- ============================================
-- RECEIVING
-- ============================================

function Sync:Apply(e, sender)
    local mine = Sync.Find(e)
    if mine then
        if (mine.mod or mine.t or 0) >= (e.mod or 0) then return false end
        -- A newer change: take its fields
        for _, k in ipairs({ "to", "how", "rid", "reason", "boss", "zone", "votes", "note", "class", "deleted", "de", "link", "color", "by" }) do
            mine[k] = e[k]
        end
        if not e.deleted then mine.deleted = nil end
        mine.mod = e.mod
        LC.Changed()
        return true
    end
    if e.deleted then
        -- Deleted before we ever had it: remember it as deleted (so it isn't imported again)
        local db = DB()
        local id = db.nextId
        db.nextId = id + 1
        e.id = id
        db.history[id] = e
        db.sources["g:" .. e.gid] = id
        if e.src.rc then db.sources["rc:" .. tostring(e.src.rc)] = id end
        if e.src.gl then db.sources["gl:" .. tostring(e.src.gl)] = id end
        return true
    end
    if not e.to and e.de then
        -- Disenchanted, no winner: kept as is
        local db = DB()
        local id = db.nextId
        db.nextId = id + 1
        e.id = id
        db.history[id] = e
        db.sources["g:" .. e.gid] = id
        LC.Changed()
        return true
    end
    e.srcKind = "g"
    e.src.g = e.gid
    local id, isNew = LC.Add(e)
    if id then
        local db = DB()
        db.sources["g:" .. e.gid] = id
        if e.src.rc then db.sources["rc:" .. tostring(e.src.rc)] = id end
        if e.src.gl then db.sources["gl:" .. tostring(e.src.gl)] = id end
    end
    return isNew and true or false
end

local unframe = Codec.NewUnframer()

function Sync:OnMessage(prefix, msg, dist, sender)
    if prefix ~= PREFIX or dist ~= "GUILD" or not Sync.Enabled() then return end
    sender = LC.Key(sender)
    if not sender or sender == MyKey() then return end
    local whole = unframe(sender, msg)
    if not whole then return end
    local ok, kind, payload = Codec.Deserialize(whole)
    if not ok then return end
    if kind == "A" then
        -- A boss kill and who was there
        if type(payload) == "table" and tonumber(payload.t) and payload.z and type(payload.m) == "table" then
            local members = {}
            for _, n in ipairs(payload.m) do if type(n) == "string" then members[#members + 1] = n end end
            local key = LC.RaidKey(tonumber(payload.t), payload.z, payload.b)
            Heard("raid:" .. key, tonumber(payload.t))
            LC.AddRaid({ t = tonumber(payload.t), zone = payload.z, boss = payload.b, members = members }, false)
        end
    elseif kind == "E" then
        local e = Sync.Unpack(payload)
        if e then
            Heard(e.gid, e.mod or 0)
            if self:Apply(e, sender) then Sync.received = (Sync.received or 0) + 1 end
        end
    elseif kind == "C" then
        self:OnCatchUp(tonumber(payload) or 0)
    end
end

-- ============================================
-- CATCHING UP
-- ============================================

local drip, dripSet, dripTimer = {}, {}, nil

local function DripNext()
    dripTimer = nil
    if not Sync.Enabled() then return end
    while #drip > 0 do
        local item = table.remove(drip, 1)
        dripSet[item.gid] = nil
        if item.raid then
            local r = DB().raids[item.raid]
            if r and not SentSince(item.gid, r.t or 0, item.seq) then
                Sync:ShareRaid(r, item.raid)
                if #drip > 0 and C_Timer then dripTimer = C_Timer.NewTimer(DRIP, DripNext) end
                return
            end
        else
            local e = DB().history[item.id]
            if e and not SentSince(item.gid, e.mod or e.t or 0, item.seq) then
                Sync:Share(e)
                if #drip > 0 and C_Timer then dripTimer = C_Timer.NewTimer(DRIP, DripNext) end
                return
            end
        end
    end
end

-- Someone asked for everything changed since then
function Sync:OnCatchUp(since)
    if not Sync.Enabled() then return end
    local new = {}
    for id, e in pairs(DB().history) do
        if (e.mod or e.t or 0) > since then
            local gid = LC.GlobalId(e)
            if dripSet[gid] then
                dripSet[gid].seq = seq
            else
                dripSet[gid] = { id = id, gid = gid, mod = e.mod or e.t or 0, seq = seq }
                new[#new + 1] = dripSet[gid]
            end
        end
    end
    for key, r in pairs(DB().raids or {}) do
        if (r.t or 0) > since then
            local gid = "raid:" .. key
            if dripSet[gid] then
                dripSet[gid].seq = seq
            else
                dripSet[gid] = { raid = key, gid = gid, mod = r.t or 0, seq = seq }
                new[#new + 1] = dripSet[gid]
            end
        end
    end
    if #new == 0 then return end
    table.sort(new, function(a, b) return a.mod > b.mod end)
    for _, item in ipairs(new) do drip[#drip + 1] = item end
    if not dripTimer and C_Timer then dripTimer = C_Timer.NewTimer(2 + math.random() * 6, DripNext) end
end

function Sync.CatchUpLength() return #drip end

-- At login: ask the guild for what we missed
function Sync:Hello()
    if self.greeted or not Sync.Enabled() then return end
    self.greeted = true
    local last = tonumber(DB().syncLastOnline) or 0
    Send("C", math.max(0, last > 0 and (last - MARGIN) or 0))
    DB().syncLastOnline = Now()
end

-- ============================================
-- EVENTS
-- ============================================

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if not On() then return end
    if event == "CHAT_MSG_ADDON" then Sync:OnMessage(...)
    elseif event == "PLAYER_LOGOUT" then DB().syncLastOnline = Now() end
end)

function Sync:Init()
    if self.started then return end
    self.started = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    WM:RegisterEvents(events, { "CHAT_MSG_ADDON", "PLAYER_LOGOUT" })
    LC.OnShare = function(e) Sync:Share(e) end
    LC.OnShareRaid = function(r, key) Sync:ShareRaid(r, key) end
    -- After the imports at login, ask for what we missed
    if C_Timer then C_Timer.After(30, function() if On() then Sync:Hello() end end) end
end

function Sync:Stop()
    if dripTimer then dripTimer:Cancel(); dripTimer = nil end
    wipe(drip); wipe(dripSet)
    WM:ClearAddonQueue({ [PREFIX] = true })
end

function Sync:ResetForTests()
    wipe(heard); wipe(drip); wipe(dripSet)
    if dripTimer then dripTimer:Cancel(); dripTimer = nil end
    self.greeted = nil
end
Sync.PREFIX = PREFIX
