-- Watching Machine: ArmorySnap's armory
-- One saved armory per character and spec (the talent tree with the most
-- points), in ArmorySnapDB.armory, shared with guildmates running Watching
-- Machine:
--   * Your own gear and talents are saved whenever they change.
--   * A guildmate who doesn't run Watching Machine is saved whenever
--     ArmorySnap inspects them (the game doesn't show an inspected player's
--     talent points, so their spec is the one whose saved gear matches best).
--   * Each new scan goes to the guild; the newest scan of each spec wins on
--     every install. Opening someone's armory asks the guild for anything
--     newer.
-- Roster Manager shows it from its details pane ("Show armory").
--
-- Messages (prefix WMArmory, guild channel):
--   H^version                        I run Watching Machine
--   P^id^part^parts^data             one armory, split in parts
--   Q^Name-Realm^spec=time,...       anything newer than these?

local AddonName, WM = ...
local AS = WM.modules.ArmorySnap
local Arm = {}
AS.Armory = Arm

local PREFIX = "WMArmory"
local PART = 200                 -- bytes of armory data per message
local QUERY_GAP = 60             -- seconds before asking about the same player again
local USER_DAYS = 30             -- a player heard from within this many days runs Watching Machine
local KEEP_DAYS = 365            -- armories not updated for this long are dropped
local MATCH = 0.6                -- share of items in common to call it the same spec
Arm.UNKNOWN = "?"                -- spec of an inspect that matches nothing saved

local function On() return WM:IsModuleOn("ArmorySnap") end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end
local function DB() return AS.InitDB() end
local function Opt(k) return DB().options[k] ~= false end

-- ============================================
-- NAMES
-- ============================================

local function Realm()
    local r = GetRealmName and GetRealmName() or ""
    return (r:gsub("[%s%-]", ""))
end

-- "Name-Realm" with the realm's spaces and hyphens removed, as the guild
-- roster names players
function Arm.Key(name)
    if type(name) ~= "string" or name == "" then return nil end
    local n, r = name:match("^([^%-]+)%-(.+)$")
    if n then return n .. "-" .. r:gsub("[%s%-]", "") end
    return name .. "-" .. Realm()
end

local function Short(key) return key and (key:match("^([^%-]+)") or key) or "?" end
Arm.Short = Short

local function MyKey() return Arm.Key(UnitName("player")) end

-- ============================================
-- SAVED ARMORIES
-- ============================================

function Arm.All() return DB().armory end

-- { [spec] = entry } for a player, or nil
function Arm.Profile(name)
    local key = Arm.Key(name)
    return key and Arm.All()[key]
end

-- A player's armories, newest first
function Arm.Specs(name)
    local out = {}
    for _, e in pairs(Arm.Profile(name) or {}) do out[#out + 1] = e end
    table.sort(out, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return out
end

Arm.NO_TALENTS = "-"             -- your own character before level 10

function Arm.SpecLabel(spec)
    if spec == Arm.UNKNOWN then return "spec unknown" end
    if spec == Arm.NO_TALENTS then return "no talents" end
    return spec or "?"
end

-- Players heard from on the armory channel run Watching Machine: their own
-- scans keep their armory, so an inspect doesn't replace it
function Arm.RunsAddon(key)
    local t = DB().armoryUsers[key]
    return t and Now() - t < USER_DAYS * 86400 or false
end

local function Total(talents)
    local n = 0
    for _, t in ipairs(talents and talents.trees or {}) do n = n + (tonumber(t.points) or 0) end
    return n
end
Arm.TotalPoints = Total

local function ItemId(gd) return gd and gd.link and tonumber(gd.link:match("item:(%d+)")) end

-- Share of this gear's items also in that gear
local function Overlap(gear, other)
    local n, same = 0, 0
    for slot, gd in pairs(gear) do
        if slot ~= 4 and slot ~= 19 then
            n = n + 1
            if ItemId(gd) and ItemId(gd) == ItemId(other[slot]) then same = same + 1 end
        end
    end
    return n > 0 and same / n or 0
end

-- The spec a capture belongs to: its main talent tree, or (an inspect, which
-- has no talent points) the saved spec whose gear it matches best
function Arm.SpecFor(key, entry)
    if Total(entry.talents) > 0 and entry.talents.spec ~= "" then return entry.talents.spec end
    local best, bestShare
    for spec, e in pairs(Arm.All()[key] or {}) do
        if spec ~= Arm.UNKNOWN and type(e.gear) == "table" then
            local share = Overlap(entry.gear or {}, e.gear)
            if share >= MATCH and (not bestShare or share > bestShare) then best, bestShare = spec, share end
        end
    end
    return best or Arm.UNKNOWN
end

local listeners = {}
function Arm.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed(key)
    for _, fn in ipairs(listeners) do pcall(fn, key) end
    if AS.RefreshArmoryView then AS.RefreshArmoryView(key) end
end

-- Keep an armory if it's newer than the one saved for that spec
function Arm.Store(key, entry)
    if not key or type(entry) ~= "table" or not entry.spec then return false end
    local all = Arm.All()
    all[key] = all[key] or {}
    local old = all[key][entry.spec]
    if old and (old.time or 0) >= (entry.time or 0) then return false end
    -- An inspect has no talent points: keep the ones this spec was saved with
    if Total(entry.talents) == 0 and old and Total(old.talents) > 0 then entry.talents = old.talents end
    all[key][entry.spec] = entry
    -- A spec found by its talents replaces the unmatched inspect it came from
    local unknown = all[key][Arm.UNKNOWN]
    if entry.spec ~= Arm.UNKNOWN and unknown and (unknown.time or 0) <= entry.time
       and Overlap(unknown.gear or {}, entry.gear or {}) >= MATCH then
        all[key][Arm.UNKNOWN] = nil
    end
    Changed(key)
    return true
end

-- What a capture is, compared to decide whether anything changed
local function Signature(e)
    local parts = { tostring(e.level), e.talents and e.talents.points or "" }
    for slot = 1, 19 do parts[#parts + 1] = e.gear and e.gear[slot] and e.gear[slot].link or "" end
    return table.concat(parts, "|")
end

-- ============================================
-- CAPTURING
-- ============================================

-- Your own gear and talents, saved when they changed (or forced)
function Arm:RecordSelf(force)
    if not On() or AS.standaloneConflict or not Opt("armorySelf") then return false end
    local ci = AS.CaptureCharInfo("player")
    ci.gear = AS.CaptureGear("player")
    ci.talents = AS.CaptureTalents(false)
    if not next(ci.gear) then return false end
    local key = MyKey()
    ci.spec = Total(ci.talents) > 0 and Arm.SpecFor(key, ci) or Arm.NO_TALENTS
    local old = (Arm.All()[key] or {})[ci.spec]
    if old and not force and Signature(old) == Signature(ci) then return false end
    ci.time, ci.by, ci.own = Now(), key, true
    AS.ScoreMember(ci)
    if Arm.Store(key, ci) then
        self:Share(key, ci)
        return true
    end
    return false
end

local function InMyGuild(unit)
    if UnitIsInMyGuild then
        local ok, r = pcall(UnitIsInMyGuild, unit)
        if ok then return r and true or false end
    end
    local mine = GetGuildInfo and GetGuildInfo("player")
    return mine ~= nil and mine == GetGuildInfo(unit)
end
Arm.InMyGuild = InMyGuild

-- ArmorySnap inspected someone: save them if they're a guildmate who doesn't
-- run Watching Machine (who keep their own)
function Arm:FromInspect(ci, unit)
    if not On() or not Opt("armoryInspect") or type(ci) ~= "table" then return false end
    if not unit or UnitIsUnit(unit, "player") or not InMyGuild(unit) then return false end
    local key = Arm.Key(ci.name)
    if not key or Arm.RunsAddon(key) then return false end
    local n = 0
    for _ in pairs(ci.gear or {}) do n = n + 1 end
    if n < 3 then return false end            -- the inspect didn't come through
    local e = {}
    for k, v in pairs(ci) do e[k] = v end
    e.spec = Arm.SpecFor(key, e)
    e.time, e.by, e.own = Now(), MyKey(), nil
    if Arm.Store(key, e) then
        self:Share(key, e)
        return true
    end
    return false
end

-- "3 days ago"
function Arm.Age(t)
    local d = Now() - (t or 0)
    if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local days = math.floor(d / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
end

-- Who saved it and when, under the name on the paper doll
function Arm.Note(e)
    local who = e.own and "their own scan" or ("inspected by " .. Short(e.by))
    if e.own and e.by == MyKey() then who = "your scan" end
    return (e.guild and e.guild ~= "" and ("<" .. e.guild .. ">  ") or "") .. "|cff888888" .. Arm.Age(e.time) .. ", " .. who .. "|r"
end

-- The armory as a snapshot for ArmorySnap's browser: a row per character
-- and spec ("Name · Spec"), all of them or one player's
function Arm.View(filter)
    local members = {}
    for key, specs in pairs(Arm.All()) do
        if not filter or key == filter then
            for spec, e in pairs(specs) do
                Arm.Resolve(e)
                local label = (key:match("%-(.+)$") == Realm() and Short(key) or key) .. " · " .. Arm.SpecLabel(spec)
                members[label] = setmetatable({ name = label, armoryNote = Arm.Note(e) }, { __index = e })
            end
        end
    end
    return { members = members, armory = true }
end

-- The row a player's newest armory has in the view
function Arm.ViewKey(name)
    local key = Arm.Key(name)
    local e = Arm.Specs(name)[1]
    if not e then return nil end
    return (key:match("%-(.+)$") == Realm() and Short(key) or key) .. " · " .. Arm.SpecLabel(e.spec)
end

-- ============================================
-- SHARING
-- ============================================

local function Sharing()
    return On() and not AS.standaloneConflict and Opt("armoryShare") and IsInGuild and IsInGuild()
end

-- "itemId:enchant:gem1:..." from a link, without the trailing zeros
local function ItemString(link)
    local s = link and link:match("|Hitem:([%-%d:]+)|h")
    if not s then return nil end
    return (s:gsub(":[0:]*$", ""))
end

-- A link from an item string: the item's real name and colour when the
-- client knows it, a placeholder until then
local function BuildLink(str)
    local id = tonumber(str:match("^(%d+)"))
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, quality = nil, nil, nil
    if f and id then name, _, quality = f(id) end
    local color = "|cffffffff"
    if type(quality) == "number" and type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality]
       and type(ITEM_QUALITY_COLORS[quality].hex) == "string" then
        color = ITEM_QUALITY_COLORS[quality].hex
    end
    if type(name) ~= "string" then return "|cff9d9d9d|Hitem:" .. str .. "|h[Item " .. (id or "?") .. "]|h|r", true end
    return color .. "|Hitem:" .. str .. "|h[" .. name .. "]|h|r", false
end
Arm.BuildLink = BuildLink

-- Placeholder links get their real names once the client has the items
function Arm.Resolve(entry)
    for _, gd in pairs(entry and entry.gear or {}) do
        if gd.pending then
            local str = gd.link:match("|Hitem:([%-%d:]+)|h")
            if str then
                local link, pending = BuildLink(str)
                if not pending then gd.link, gd.pending = link, nil end
            end
        end
    end
end

local function Clean(s) return (tostring(s or ""):gsub("[%^;,=]", " ")) end

function Arm.Serialize(key, e)
    local trees = {}
    for _, t in ipairs(e.talents and e.talents.trees or {}) do
        trees[#trees + 1] = Clean(t.name) .. "," .. (tonumber(t.points) or 0) .. "," .. Clean(t.icon)
    end
    local gear = {}
    for slot = 1, 19 do
        local s = e.gear and e.gear[slot] and ItemString(e.gear[slot].link)
        if s then gear[#gear + 1] = slot .. "=" .. s end
    end
    return table.concat({ "1", key, Clean(e.spec), tostring(e.time or 0), Clean(e.by), e.own and "1" or "0",
        Clean(e.class), Clean(e.race), tostring(e.level or 0), tostring(e.sex or 1), Clean(e.guild),
        table.concat(trees, ";"), table.concat(gear, ";") }, "^")
end

local function Split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start); return out end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
end

-- key, entry from Serialize's text (nil if it isn't one)
function Arm.Deserialize(data)
    local f = Split(data, "^")
    if f[1] ~= "1" or #f < 13 then return nil end
    local key = Arm.Key(f[2])
    local time = tonumber(f[4])
    if not key or not time or f[3] == "" then return nil end
    local e = { name = Short(key), spec = f[3], time = time, by = f[5], own = f[6] == "1" or nil,
        class = f[7], race = f[8], level = tonumber(f[9]) or 0, sex = tonumber(f[10]) or 1, guild = f[11],
        gear = {}, talents = { trees = {}, spec = "", points = "" } }
    if key:match("%-(.+)$") ~= Realm() then e.name = key end
    local pts, best, bestPts = {}, "", 0
    for _, t in ipairs(f[12] ~= "" and Split(f[12], ";") or {}) do
        local tf = Split(t, ",")
        local p = tonumber(tf[2]) or 0
        e.talents.trees[#e.talents.trees + 1] = { name = tf[1] or "", points = p, icon = tf[3] or "" }
        pts[#pts + 1] = tostring(p)
        if p > bestPts then best, bestPts = tf[1] or "", p end
    end
    e.talents.spec, e.talents.points = best, table.concat(pts, "/")
    for _, g in ipairs(f[13] ~= "" and Split(f[13], ";") or {}) do
        local slot, str = g:match("^(%d+)=([%-%d:]+)$")
        slot = tonumber(slot)
        if slot and slot >= 1 and slot <= 19 then
            local link, pending = BuildLink(str)
            e.gear[slot] = { link = link, icon = WM.ItemIcon(tonumber(str:match("^(%d+)"))) or "", pending = pending or nil }
        end
    end
    return key, e
end

local nextId = 0
local function Send(body) return WM:QueueAddonMessage(PREFIX, body, "GUILD") end

-- Send one armory to the guild
function Arm:Share(key, e)
    if not Sharing() then return false end
    local data = Arm.Serialize(key, e)
    nextId = nextId + 1
    local id = string.format("%x%x", math.random(0, 4095), nextId % 4096)
    local parts = math.ceil(#data / PART)
    for i = 1, parts do
        Send("P^" .. id .. "^" .. i .. "^" .. parts .. "^" .. data:sub((i - 1) * PART + 1, i * PART))
    end
    return true
end

-- Ask the guild for anything newer than what we have of a player
local asked = {}
function Arm:Query(name, force)
    if not Sharing() then return false end
    local key = Arm.Key(name)
    if not key then return false end
    if not force and asked[key] and Now() - asked[key] < QUERY_GAP then return false end
    asked[key] = Now()
    local have = {}
    for spec, e in pairs(Arm.All()[key] or {}) do have[#have + 1] = Clean(spec) .. "=" .. (e.time or 0) end
    return Send("Q^" .. key .. "^" .. table.concat(have, ","))
end

-- ============================================
-- RECEIVING
-- ============================================

local partial = {}        -- [sender .. id] = { parts, got, n, t }
local answers = {}        -- [key .. "^" .. spec] = timer of our pending answer
local heard = {}          -- [key .. "^" .. spec] = newest time heard on the channel

local function Heard(key, spec, t)
    local k = key .. "^" .. spec
    if (heard[k] or 0) < t then heard[k] = t end
end

local function OnArmory(sender, data)
    local key, e = Arm.Deserialize(data)
    if not key then return end
    Heard(key, e.spec, e.time)
    -- An armory the owner sent of themselves: they run Watching Machine
    if e.own and key == sender then DB().armoryUsers[key] = Now() end
    if e.time > Now() + 300 then return end       -- from the future: a wrong clock
    AS.ScoreMember(e)
    Arm.Store(key, e)
end

-- Someone asked: answer with each newer armory we have, after a moment (the
-- owner at once), unless someone else sends it first
local function OnQuery(sender, key, list)
    local theirs = {}
    for _, kv in ipairs(list ~= "" and Split(list, ",") or {}) do
        local spec, t = kv:match("^(.-)=(%d+)$")
        if spec then theirs[spec] = tonumber(t) end
    end
    local me = MyKey()
    for spec, e in pairs(Arm.All()[key] or {}) do
        local id = key .. "^" .. spec
        if (e.time or 0) > (theirs[Clean(spec)] or 0) and not answers[id] then
            local delay = (key == me) and 0.2 or (1 + math.random() * 3)
            answers[id] = C_Timer.NewTimer(delay, function()
                answers[id] = nil
                if not Sharing() then return end
                local current = (Arm.All()[key] or {})[spec]
                if current and (heard[id] or 0) < (current.time or 0) then Arm:Share(key, current) end
            end)
        end
    end
end

function Arm:OnMessage(prefix, body, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not On() or AS.standaloneConflict then return end
    sender = Arm.Key(sender)
    if not sender or sender == MyKey() or type(body) ~= "string" then return end
    DB().armoryUsers[sender] = Now()
    local kind = body:sub(1, 2)
    if kind == "P^" then
        local id, i, n, part = body:match("^P%^([^%^]+)%^(%d+)%^(%d+)%^(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not id or not i or not n or i < 1 or i > n or n > 20 then return end
        local k = sender .. id
        local p = partial[k]
        if not p or Now() - p.t > 60 then p = { parts = {}, got = 0, n = n, t = Now() }; partial[k] = p end
        if not p.parts[i] then p.parts[i], p.got = part, p.got + 1 end
        if p.got >= p.n then
            partial[k] = nil
            OnArmory(sender, table.concat(p.parts))
        end
    elseif kind == "Q^" then
        local key, list = body:match("^Q%^([^%^]+)%^(.*)$")
        if key then OnQuery(sender, Arm.Key(key), list) end
    end
end

-- ============================================
-- WHEN TO SCAN YOURSELF
-- ============================================

local events = CreateFrame("Frame")
local selfTimer, started, greeted

local function ScheduleSelf(delay, force)
    if selfTimer then selfTimer:Cancel() end
    selfTimer = C_Timer.NewTimer(delay or 3, function()
        selfTimer = nil
        if InCombatLockdown and InCombatLockdown() then ScheduleSelf(5, force) return end
        Arm:RecordSelf(force)
    end)
end
Arm.ScheduleSelf = ScheduleSelf

-- Once a session: say we're here and send our own armories
function Arm:Greet()
    if greeted or not Sharing() then return end
    greeted = true
    Send("H^" .. tostring(WM.version or "?"))
    for _, e in pairs(Arm.All()[MyKey()] or {}) do self:Share(MyKey(), e) end
end

events:SetScript("OnEvent", function(_, event, ...)
    if not On() or AS.standaloneConflict then return end
    if event == "CHAT_MSG_ADDON" then
        Arm:OnMessage(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleSelf(8)
        C_Timer.After(20, function() if On() then Arm:Greet() end end)
    else
        -- Gear and talent changes come in bursts (a set swap): save once it settles
        ScheduleSelf(3)
    end
end)

function Arm:Init()
    if started then return end
    started = true
    local db = DB()
    -- Drop armories nobody has updated for a year
    local cutoff = Now() - KEEP_DAYS * 86400
    for key, specs in pairs(db.armory) do
        for spec, e in pairs(specs) do if (e.time or 0) < cutoff then specs[spec] = nil end end
        if not next(specs) then db.armory[key] = nil end
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    WM:RegisterEvents(events, { "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
        "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP" })
    -- In case the module started after you entered the world
    ScheduleSelf(10)
    C_Timer.After(25, function() if On() then Arm:Greet() end end)
end

-- Off: nothing waits to be sent or saved
function Arm:Stop()
    if selfTimer then selfTimer:Cancel(); selfTimer = nil end
    for id, t in pairs(answers) do t:Cancel(); answers[id] = nil end
    wipe(partial)
    WM:ClearAddonQueue({ [PREFIX] = true })
end

-- On again: catch up on anything that changed meanwhile
function Arm:Start()
    if not started then return end
    ScheduleSelf(3)
    C_Timer.After(5, function() if On() then Arm:Greet() end end)
end

-- For tests
function Arm:ResetForTests()
    wipe(partial); wipe(heard); wipe(asked)
    for id, t in pairs(answers) do t:Cancel(); answers[id] = nil end
    greeted = nil
end
Arm.PREFIX = PREFIX
