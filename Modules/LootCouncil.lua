-- Watching Machine: Loot Council
-- One loot history for the guild: every item awarded, to whom, by whom and
-- how it was won (Need, Greed, Minor Upgrade, Disenchant, off-spec, soft
-- reserve, roll). It starts from what Gargul and RCLootCouncil have already
-- recorded on this account, and is shown two ways: all loot ever awarded,
-- and each player's loot (in their armory and their Roster Manager
-- details), with the time since their last award.
--
-- Later parts (voting with RCLootCouncil users, awarding as master looter,
-- roll-offs) build on this history. Formats of Gargul's and RCLootCouncil's
-- saved data compiled with the help of their authors' research; the code is
-- our own.

local AddonName, WM = ...
local LC = {}
WM:RegisterModule("LootCouncil", LC)
WM.LootCouncil = LC

local function On() return WM:IsModuleOn("LootCouncil") end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end

-- ============================================
-- SAVED DATA
-- ============================================

local DEFAULTS = {
    autoImport = true,       -- read Gargul and RCLootCouncil history at login (new awards only)
    showInArmory = true,     -- the loot pane beside a player's armory
    recentDays = 30,         -- "recent loot" in tooltips
    rcTalk = true,           -- take part in RCLootCouncil sessions (answer, vote)
    showResponse = true,     -- the response frame when loot is sent for answers
    autopass = true,         -- pass on items this character can't use (not shown)
    openVoting = true,       -- the voting frame opens for council members
    -- As master looter
    mlLootWindow = true,     -- items from the loot window go on the list to send
    mlQuality = 4,           -- ...from this quality up (4 = epic)
    mlAltClick = true,       -- Alt-click an item to add it
    mlCouncilRank = 1,       -- the council: this guild rank index and above (0 = guild master)
    mlCouncilNames = "",     -- ...plus these names
    mlTimeout = 60,          -- seconds raiders have to answer
    mlAnnounce = true,       -- awards announced to the raid
    mlAutoTrade = true,      -- open the trade with a winner when the item can't be given from the loot window
}

function LC.InitDB()
    if type(WMLootDB) ~= "table" then WMLootDB = {} end
    local db = WMLootDB
    db.history = db.history or {}     -- [id] = entry (all characters' shared)
    db.sources = db.sources or {}     -- ["rc:<id>" / "gl:<checksum>"] = entry id, so imports run once each
    db.nextId = db.nextId or 1
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    return db
end
local function DB() return LC.InitDB() end
LC.DB = DB

-- ============================================
-- NAMES, CLASSES, HOW IT WAS WON
-- ============================================

local function Realm()
    local r = GetRealmName and GetRealmName() or ""
    return (r:gsub("[%s%-]", ""))
end

-- "Name-Realm" with the realm's spaces and hyphens removed
function LC.Key(name)
    if type(name) ~= "string" or name == "" then return nil end
    local n, r = name:match("^([^%-]+)%-(.+)$")
    if n then return n .. "-" .. r:gsub("[%s%-]", "") end
    return name .. "-" .. Realm()
end
local function Short(key) return key and (key:match("^([^%-]+)") or key) or "?" end
LC.Short = Short

-- Gargul's class numbers
local GARGUL_CLASS = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }

-- Colours for how an item was won, when the source didn't say
LC.HOW_COLORS = {
    need = { 0, 1, 0 }, greed = { 1, 0.5, 0 }, minor = { 0, 0.7, 0.7 }, de = { 0.6, 0.6, 0.6 },
    sr = { 0.8, 0.5, 1 }, roll = { 1, 1, 1 }, other = { 1, 0.82, 0 },
}

-- The kind of win, from a response's text: need / greed / minor / de / other
function LC.Kind(how)
    local h = tostring(how or ""):lower()
    if h:find("disenchant") or h == "de" then return "de" end
    if h:find("need") or h:find("main") or h == "ms" or h:find("bis") then return "need" end
    if h:find("greed") or h:find("off") or h == "os" then return "greed" end
    if h:find("minor") then return "minor" end
    if h:find("soft") then return "sr" end
    if h:find("roll") then return "roll" end
    return "other"
end

local function ItemId(link) return tonumber(tostring(link or ""):match("item:(%-?%d+)")) end

-- ============================================
-- THE HISTORY
-- ============================================

local byPlayer          -- [key] = { entries newest first }, rebuilt when it changes

local function Rebuild()
    byPlayer = {}
    for _, e in pairs(DB().history) do
        if e.to and not e.deleted then
            local list = byPlayer[e.to]
            if not list then list = {}; byPlayer[e.to] = list end
            list[#list + 1] = e
        end
    end
    for _, list in pairs(byPlayer) do table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end) end
end

local listeners = {}
function LC.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    byPlayer = nil
    for _, fn in ipairs(listeners) do pcall(fn) end
end
LC.Changed = Changed

-- Every entry, newest first (filter(e) -> true to keep)
function LC.All(filter)
    local out = {}
    for _, e in pairs(DB().history) do
        if not e.deleted and (not filter or filter(e)) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b)
        if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
        return (a.id or 0) > (b.id or 0)
    end)
    return out
end

-- A player's loot, newest first
function LC.ForPlayer(name)
    if not byPlayer then Rebuild() end
    local key = LC.Key(name)
    if not key then return {} end
    if byPlayer[key] then return byPlayer[key] end
    -- Typed in another case
    local low = key:lower()
    for k, list in pairs(byPlayer) do if k:lower() == low then return list end end
    return {}
end

-- The saved name for a player typed in any case (or the name as given)
function LC.Resolve(name)
    if not byPlayer then Rebuild() end
    local key = LC.Key(name)
    if not key or byPlayer[key] then return key end
    local low = key:lower()
    for k in pairs(byPlayer) do if k:lower() == low then return k end end
    return key
end

-- Their latest award that counts as loot (not disenchanting or banking for the guild)
function LC.LastLoot(name)
    for _, e in ipairs(LC.ForPlayer(name)) do
        if not e.reason then return e end
    end
end

-- Their loot within the last N days
function LC.Recent(name, days)
    local cutoff = Now() - (days or DB().recentDays) * 86400
    local out = {}
    for _, e in ipairs(LC.ForPlayer(name)) do
        if (e.t or 0) >= cutoff then out[#out + 1] = e end
    end
    return out
end

-- Everyone with loot: { key, count, last = entry }, most recent first
function LC.Players()
    if not byPlayer then Rebuild() end
    local out = {}
    for key, list in pairs(byPlayer) do
        local last
        for _, e in ipairs(list) do if not e.reason then last = e; break end end
        out[#out + 1] = { key = key, count = #list, last = last or list[1] }
    end
    table.sort(out, function(a, b) return (a.last.t or 0) > (b.last.t or 0) end)
    return out
end

-- "3 days ago"
function LC.Ago(t)
    local d = Now() - (t or 0)
    if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local days = math.floor(d / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
end

-- The entry's how-it-was-won text, coloured
function LC.HowText(e)
    local c = e.color or LC.HOW_COLORS[LC.Kind(e.how)] or LC.HOW_COLORS.other
    return string.format("|cff%02x%02x%02x%s|r", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255, e.how or "Awarded")
end

-- ============================================
-- ADDING AWARDS
-- ============================================
-- An award from any source. Awards of the same item to the same player
-- within MERGE seconds are the same award recorded twice (e.g. by both
-- Gargul and RCLootCouncil): the details are combined into one entry.

local MERGE = 3 * 3600

local function FindSame(e)
    local best, bestGap
    for _, o in pairs(DB().history) do
        if not o.deleted and o.itemID == e.itemID and o.to == e.to and not (o.src and e.src and o.src[e.srcKind]) then
            local gap = math.abs((o.t or 0) - (e.t or 0))
            if gap <= MERGE and (not bestGap or gap < bestGap) then best, bestGap = o, gap end
        end
    end
    return best
end

-- Fill what the existing entry lacks; a source that says how it was won
-- (RCLootCouncil's response) wins over a guess
local function Merge(o, e)
    for _, k in ipairs({ "link", "boss", "zone", "votes", "note", "class", "by", "replaced", "rolls", "sr", "os" }) do
        if o[k] == nil and e[k] ~= nil then o[k] = e[k] end
    end
    if e.howFirm and not o.howFirm then o.how, o.color, o.rid, o.reason, o.howFirm = e.how, e.color, e.rid, e.reason, true end
    o.src = o.src or {}
    for k, v in pairs(e.src or {}) do o.src[k] = v end
end

-- e: { link, itemID, to, by, t, how, color, rid, reason, boss, zone, votes, note, class, os, sr, rolls,
--      src = { rc = id } or { gl = checksum } or { wm = n }, srcKind = "rc" / "gl" / "wm", howFirm }
-- Returns the entry id, and whether it was new
function LC.Add(e)
    local db = DB()
    e.to = LC.Key(e.to)
    e.itemID = e.itemID or ItemId(e.link)
    if not e.to or not e.itemID then return nil end
    local srcId = e.srcKind and e.src and e.src[e.srcKind] and (e.srcKind .. ":" .. tostring(e.src[e.srcKind]))
    if srcId and db.sources[srcId] then return db.sources[srcId], false end
    local same = FindSame(e)
    local id
    if same then
        Merge(same, e)
        id = same.id
    else
        id = db.nextId
        db.nextId = id + 1
        e.id = id
        e.srcKind = nil
        db.history[id] = e
    end
    if srcId then db.sources[srcId] = id end
    Changed()
    return id, not same
end

-- ============================================
-- IMPORTING GARGUL AND RCLOOTCOUNCIL
-- ============================================

-- Gargul: GargulDB.AwardHistory[checksum] (account-wide), and the small
-- Gargul History add-on's copy (GargulHistoryDB.history)
function LC:ImportGargul()
    local gdb = rawget(_G, "GargulDB")
    local n = 0
    if type(gdb) == "table" and type(gdb.AwardHistory) == "table" then
        for checksum, a in pairs(gdb.AwardHistory) do
            if type(a) == "table" and a.awardedTo and (a.itemID or a.itemLink) then
                local de = a.awardedTo == "||de||"
                local how
                if de then how = "Disenchant"
                elseif a.winningRollType and a.winningRollType ~= "" then how = tostring(a.winningRollType)
                elseif a.SR then how = "Soft reserve"
                elseif a.OS then how = "Offspec"
                else how = "Mainspec" end
                if how == "MS" then how = "Mainspec" elseif how == "OS" then how = "Offspec" end
                local rolls
                if type(a.Rolls) == "table" and #a.Rolls > 0 then
                    rolls = {}
                    for _, r in ipairs(a.Rolls) do
                        if type(r) == "table" then
                            rolls[#rolls + 1] = { name = r.player, roll = r.amount, type = r.classification, max = r.max }
                        end
                    end
                end
                local winner = a.awardedTo
                if de then winner = nil end
                local _, isNew = LC.Add({
                    link = a.itemLink, itemID = tonumber(a.itemID), to = winner,
                    by = a.awardedBy and LC.Key(a.awardedBy), t = tonumber(a.timestamp) or 0, how = how,
                    color = LC.HOW_COLORS[LC.Kind(how)], reason = de or nil, class = GARGUL_CLASS[tonumber(a.winnerClass) or 0],
                    os = a.OS or nil, sr = a.SR or nil, rolls = rolls, src = { gl = checksum }, srcKind = "gl",
                })
                if de then
                    -- Disenchanted: kept in the all-loot list under nobody
                    local db = DB()
                    local srcId = "gl:" .. tostring(checksum)
                    if not db.sources[srcId] then
                        local id = db.nextId
                        db.nextId = id + 1
                        db.history[id] = { id = id, link = a.itemLink, itemID = tonumber(a.itemID), to = nil, de = true,
                            by = a.awardedBy and LC.Key(a.awardedBy), t = tonumber(a.timestamp) or 0, how = "Disenchant",
                            color = LC.HOW_COLORS.de, reason = true, src = { gl = checksum } }
                        db.sources[srcId] = id
                        n = n + 1
                    end
                elseif isNew then
                    n = n + 1
                end
            end
        end
    end
    local hdb = rawget(_G, "GargulHistoryDB")
    if type(hdb) == "table" and type(hdb.history) == "table" then
        for i, a in ipairs(hdb.history) do
            if type(a) == "table" and a.awardedTo and a.awardedTo ~= "||de||" then
                local _, isNew = LC.Add({ link = a.itemLink, itemID = tonumber(a.item and a.item.id), to = a.awardedTo,
                    t = tonumber(a.timestamp) or 0, how = "Mainspec", color = LC.HOW_COLORS.need,
                    src = { gh = tostring(a.timestamp) .. ":" .. tostring(a.awardedTo) .. ":" .. tostring(a.item and a.item.id) },
                    srcKind = "gh" })
                if isNew then n = n + 1 end
            end
        end
    end
    return n
end

-- RCLootCouncil's date and time are the realm's clock ("2026/07/16",
-- "20:58:00"): the epoch for them
function LC.RealmTime(dateStr, timeStr)
    local a, m, c = tostring(dateStr or ""):match("^(%d+)/(%d+)/(%d+)$")
    if not a then return nil end
    local y, d
    if #a == 4 then y, d = tonumber(a), tonumber(c)      -- "YYYY/MM/DD"
    else d, y = tonumber(a), tonumber(c) end             -- old "d/m/y" form
    m = tonumber(m)
    if y < 100 then y = y + 2000 end
    local H, M, S = tostring(timeStr or ""):match("^(%d+):(%d+):?(%d*)$")
    local fields = { year = y, month = m, day = d, hour = tonumber(H) or 12, min = tonumber(M) or 0, sec = tonumber(S) or 0 }
    local localEpoch = time(fields)
    local getLocal = C_DateAndTime and C_DateAndTime.GetServerTimeLocal
    if getLocal and GetServerTime then
        -- Read the fields as UTC, then take off the realm's offset from UTC
        local now = time()
        local machineOffset = now - time(date("!*t", now))
        local ok, serverLocal = pcall(getLocal)
        if ok and tonumber(serverLocal) then
            return localEpoch + machineOffset - (tonumber(serverLocal) - GetServerTime())
        end
    end
    return localEpoch
end

-- One RCLootCouncil history entry (saved, or sent by a master looter)
function LC.AddRCLC(name, h, index)
    if type(h) ~= "table" or not h.lootWon or type(name) ~= "string" then return nil end
    local c = type(h.color) == "table" and { h.color[1], h.color[2], h.color[3] } or nil
    local how = h.response or "Awarded"
    return LC.Add({
        link = h.lootWon, to = name, t = LC.RealmTime(h.date, h.time) or Now(), how = how,
        color = c or LC.HOW_COLORS[LC.Kind(how)], rid = h.responseID, reason = h.isAwardReason and true or nil, howFirm = true,
        boss = h.boss, zone = h.instance, votes = tonumber(h.votes), note = h.note, class = h.class,
        by = h.owner and LC.Key(h.owner), replaced = h.itemReplaced1,
        src = { rc = h.id or (name .. ":" .. tostring(index)) }, srcKind = "rc",
    })
end

-- An RCLootCouncil history entry was deleted (a re-award)
function LC.DeleteRCLC(id)
    local db = DB()
    local entry = db.sources["rc:" .. tostring(id)]
    entry = entry and db.history[entry]
    if entry then entry.deleted = true; Changed() return true end
    return false
end

function LC:ImportRCLC()
    local rdb = rawget(_G, "RCLootCouncilLootDB")
    if type(rdb) ~= "table" or type(rdb.factionrealm) ~= "table" then return 0 end
    local n = 0
    for _, players in pairs(rdb.factionrealm) do
        if type(players) == "table" then
            for name, list in pairs(players) do
                if type(list) == "table" and type(name) == "string" and name:find("-", 1, true) then
                    for i, h in pairs(list) do
                        local _, isNew = LC.AddRCLC(name, h, i)
                        if isNew then n = n + 1 end
                    end
                end
            end
        end
    end
    return n
end

-- Both, quietly; returns how many new awards
function LC:ImportAll()
    if not On() then return 0 end
    local n = self:ImportRCLC() + self:ImportGargul()
    DB().lastImport = Now()
    return n
end

-- ============================================
-- LIFECYCLE
-- ============================================

function LC:Initialize()
    DB()
    if C_Timer then
        C_Timer.After(15, function()
            if not On() or not DB().autoImport then return end
            local n = LC:ImportAll()
            if n > 0 then WM:ModulePrint("LootCouncil", "Added " .. n .. " awards from Gargul and RCLootCouncil to the loot history.") end
        end)
    end
    if self.InitUI then self:InitUI() end
    if self.RC then self.RC:Init() end
    if self.ML then self.ML:Init() end
    if self.InitFrames then self:InitFrames() end
end

function LC:OnModuleOff()
    if self.HideUI then self:HideUI() end
    if self.HideFrames then self:HideFrames() end
    if self.RC then self.RC:Stop() end
    if self.ML then self.ML:Stop() end
end

function LC:OnModuleOn()
    DB()
end

function LC:GetQuickStatus()
    local n = 0
    for _, e in pairs(DB().history) do if not e.deleted then n = n + 1 end end
    return "|cFF00FF00" .. n .. "|r awards in the loot history"
end
