-- Watching Machine: World Timers
-- Timers for the open world on TBC Anniversary, kept per layer:
--   * Layers: which layer you're on, from the four Shattrath NPCs
--   * Terokkar Forest towers: when the Spirit Towers reset
--   * Today's dungeon, heroic and PvP dailies
--   * Darkmoon Faire: when it's up, where, and your Sayge buff cooldown
--   * Classic world buffs: Rend, Onyxia, Nefarian, Zandalar (rare on TBC)
--   * Felwood Songflowers
-- It also listens to Nova World Buffs users' timer data (guild, group and
-- yells), the way Nova clients share it with each other. Watching Machine
-- never sends in Nova's format. The rules follow Nova World Buffs' own
-- behaviour on the TBC client (worked out from its code; none copied).

local AddonName, WM = ...
local WT = {}
WM:RegisterModule("WorldTimers", WT)
WM.WorldTimers = WT

WT.version = "3.28"

-- ============================================
-- CONSTANTS
-- ============================================

local SHATTRATH, TEROKKAR, FELWOOD = 1955, 1952, 1448
local ORGRIMMAR, STORMWIND, BARRENS, ELWYNN, DUROTAR = 1454, 1453, 1413, 1429, 1411
local LAYER_EXPIRE, MAX_LAYERS = 7200, 20
local SHATTRATH_NPCS = { [18481] = true, [18940] = true, [19046] = true, [19232] = true }
-- Zones a layer can be followed into (Outland, Quel'Danas, the two capitals)
local LAYER_ZONES = { [1453] = true, [1454] = true, [1944] = true, [1946] = true, [1948] = true, [1949] = true,
    [1951] = true, [1952] = true, [1953] = true, [1955] = true, [1957] = true }
local IGNORE_NPCS = { [9662] = true, [187832] = true, [6491] = true, [18483] = true, [18482] = true, [68] = true, [3296] = true }

local TEROK_DRIFT = 2.7507           -- the towers' clock runs this many seconds slow per minute
local TEROK_WIDGETS = { neutral = 3097, alliance = 3118, horde = 3119, cap1 = 3111, cap2 = 3112 }

local BUFFS = {
    rend = { name = "Rend (Warchief's Blessing)", cooldown = 10800, spells = { [16609] = true, [355366] = true } },
    ony  = { name = "Onyxia", cooldown = 21600, spells = { [22888] = true, [355363] = true } },
    nef  = { name = "Nefarian", cooldown = 28800, spells = { [22888] = true, [355363] = true } },
    zan  = { name = "Zandalar", cooldown = nil, spells = { [24425] = true, [355365] = true } },
}
WT.BUFFS = BUFFS
local BUFF_ORDER = { "rend", "ony", "nef" }
local WARN_AT = { 1800, 900, 600, 300, 60, 0 }

-- First and second yells (English; matched as plain substrings)
local YELLS = {
    { buff = "rend", first = true, text = "Rend Blackhand, has fallen" },
    { buff = "rend", text = "Battle for the glory of the Horde" },
    { buff = "ony", first = true, text = "Onyxia, has been slain" },
    { buff = "ony", text = "Be lifted by the rallying cry" },
    { buff = "ony", first = true, text = "history has been made" },
    { buff = "ony", text = "Onyxia, hangs from the arches" },
    { buff = "nef", first = true, text = "NEFARIAN IS SLAIN" },
    { buff = "nef", text = "Revel in his rallying cry" },
    { buff = "nef", first = true, text = "the Lord of Blackrock is slain" },
    { buff = "nef", text = "Revel in the rallying cry" },
    { buff = "zan", first = true, text = "Begin the ritual" },
    { buff = "zan", first = true, text = "The Blood God" },
    { buff = "zan", text = "slayer of Hakkar" },
}
local BUFF_NPCS = {   -- buff source npcs
    rend = { [4949] = true, [10719] = true },
    ony = { [14392] = true, [14394] = true, [173758] = true, [173754] = true },
    nef = { [14720] = true, [14721] = true, [173758] = true, [173754] = true },
    zan = {},
}
local KILL_NPCS = {
    ["Overlord Runthak"] = "ony", ["Major Mattingly"] = "ony",
    ["High Overlord Saurfang"] = "nef", ["Field Marshal Afrasiabi"] = "nef", ["Field Marshal Stonebridge"] = "nef",
}

local SONGFLOWER_SPELL, SONGFLOWER_RESPAWN = 15366, 1500
local SONGFLOWERS = {
    { 63.9, 6.1, "North Felpaw Village" }, { 55.8, 10.4, "West Felpaw Village" },
    { 50.6, 13.9, "North of Irontree Woods" }, { 63.3, 22.6, "Talonbranch Glade" },
    { 40.1, 44.4, "Shatter Scar Vale" }, { 34.3, 52.2, "Bloodvenom Post" },
    { 40.1, 56.5, "East of Jaedenar" }, { 48.3, 75.7, "North of Emerald Sanctuary" },
    { 45.9, 85.2, "West of Emerald Sanctuary" }, { 52.9, 87.8, "South of Emerald Sanctuary" },
}
WT.SONGFLOWERS = SONGFLOWERS

local DMF_SPELLS = { [23768] = true, [23769] = true, [23767] = true, [23766] = true,
    [23738] = true, [23737] = true, [23735] = true, [23736] = true }
local DMF_COOLDOWN = 14400

-- Dailies: questID -> { id, name }
local DUNGEON_DAILIES = {
    [11389] = { 1, "Arcatraz" }, [11371] = { 2, "Steamvault" }, [11376] = { 3, "Shadow Labyrinth" },
    [11383] = { 4, "Black Morass" }, [11364] = { 5, "Shattered Halls" }, [11500] = { 6, "Magisters' Terrace" },
    [11385] = { 7, "Botanica" }, [11387] = { 8, "Mechanar" },
}
local HEROIC_DAILIES = {
    [11369] = { 1, "Underbog" }, [11384] = { 2, "Botanica" }, [11382] = { 3, "Black Morass" },
    [11363] = { 4, "Shattered Halls" }, [11362] = { 5, "Blood Furnace" }, [11375] = { 6, "Shadow Labyrinth" },
    [11354] = { 7, "Hellfire Ramparts" }, [11386] = { 8, "Mechanar" }, [11373] = { 9, "Mana-Tombs" },
    [11378] = { 10, "Old Hillsbrad Foothills" }, [11374] = { 11, "Auchenai Crypts" }, [11372] = { 12, "Sethekk Halls" },
    [11368] = { 13, "Slave Pens" }, [11388] = { 14, "Arcatraz" }, [11370] = { 15, "Steamvault" },
    [11499] = { 16, "Magisters' Terrace" },
}
local PVP_DAILIES = {
    [11342] = { 1, "Warsong Gulch" }, [11339] = { 2, "Arathi Basin" }, [11340] = { 3, "Alterac Valley" },
    [11341] = { 4, "Eye of the Storm" }, [11338] = { 5, "Warsong Gulch" }, [11335] = { 6, "Arathi Basin" },
    [11336] = { 7, "Alterac Valley" }, [11337] = { 8, "Eye of the Storm" },
    [13407] = { 9, "Strand of the Ancients" }, [14164] = { 10, "Isle of Conquest" },
    [13405] = { 11, "Strand of the Ancients" }, [14163] = { 12, "Isle of Conquest" },
}
local function ById(list)
    local out = {}
    for _, d in pairs(list) do out[d[1]] = d[2] end
    return out
end
local DAILY_KINDS = {
    dungeon = { npcs = { [24370] = true }, quests = DUNGEON_DAILIES, names = ById(DUNGEON_DAILIES), label = "Dungeon" },
    heroic = { npcs = { [24369] = true }, quests = HEROIC_DAILIES, names = ById(HEROIC_DAILIES), label = "Heroic" },
    pvp = { npcs = { [15350] = true, [15351] = true }, quests = PVP_DAILIES, names = ById(PVP_DAILIES), label = "PvP" },
}
WT.DAILY_KINDS = DAILY_KINDS
local DAILY_ORDER = { "dungeon", "heroic", "pvp" }
local DAY = 86400

-- Nova World Buffs' short keys -> ours
local NWB_KEYS = {
    n = "rendTimer", o = "rendYell", s = "onyTimer", t = "onyYell", y = "nefTimer", z = "nefYell",
    x = "onyNpcDied", D = "nefNpcDied", E = "lastSeenNPC", af = "spawn",
    L = "terokTowers", U = "terokTowersTime", M = "terokFaction",
    O = "tbcHD", P = "tbcHDT", Q = "tbcDD", R = "tbcDDT", S = "tbcPD", T = "tbcPDT",
}
for i = 1, 10 do NWB_KEYS["f" .. i] = "flower" .. i end
local NWB_MIN_VERSION = 3.26

-- ============================================
-- SAVED DATA (per realm and faction, like the layers themselves)
-- ============================================

local DEFAULTS = {
    terokWarn = true,        -- chat line 10 minutes before the Terokkar towers reset
    buffWarn = true,         -- world buff warnings (30/15/10/5/1 min)
    listenNWB = true,        -- read Nova World Buffs users' timers
    showNWBNotices = true,   -- their yell / NPC-killed notices
}
WT.DEFAULTS = DEFAULTS

local function Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" and t > 0 then return t end
    end
    return time()
end
WT.Now = Now

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end

local function DB()
    if type(WorldTimersDB) ~= "table" then WorldTimersDB = {} end
    local db = WorldTimersDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.realms) ~= "table" then db.realms = {} end
    if type(db.chars) ~= "table" then db.chars = {} end
    return db
end
WT.DB = DB

-- This realm and faction's timers
function WT:Data()
    local key = ((GetRealmName and GetRealmName()) or "?") .. "-" .. ((UnitFactionGroup and UnitFactionGroup("player")) or "?")
    local realms = DB().realms
    local d = realms[key]
    if type(d) ~= "table" then d = {}; realms[key] = d end
    if type(d.layers) ~= "table" then d.layers = {} end
    if type(d.dailies) ~= "table" then d.dailies = {} end
    if type(d.flowers) ~= "table" then d.flowers = {} end   -- no layer known
    if type(d.buffs) ~= "table" then d.buffs = {} end       -- no layer known
    return d
end

function WT:Print(msg)
    if WM.ChatLink then msg = WM:ChatLink("wtimers", "", msg) end
    WM:ModulePrint("WorldTimers", msg)
end

-- ============================================
-- FORMATTING
-- ============================================

local function Short(s)
    s = math.max(0, math.floor(s or 0))
    if s >= 86400 then return string.format("%dd %dh", math.floor(s / 86400), math.floor(s % 86400 / 3600)) end
    if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
    return s .. "s"
end
WT.Short = Short

-- ============================================
-- LAYERS
-- ============================================

local currentLayer          -- Shattrath zoneUID of the layer you're on
local confirmedLayer        -- set by a Shattrath NPC this session (needed to map other zones)
local lastGroupJoin = 0     -- GetTime() of the last group join
local joinedGroup = false   -- any group joined this session: zones are no longer mapped
local phase = {}            -- mapID -> first zoneUID seen there since the layer was known

local function ParseGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, zoneUID, npcID, spawnUID = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    return tonumber(zoneUID), tonumber(npcID), spawnUID
end
WT.ParseGUID = ParseGUID

local function MapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then return tonumber(id) end
    end
end

local function SortedLayerKeys(layers)
    local keys = {}
    for k in pairs(layers) do if type(k) == "number" then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
end

function WT:LayerNumber(zoneUID)
    if not zoneUID then return nil end
    for i, k in ipairs(SortedLayerKeys(self:Data().layers)) do
        if k == zoneUID then return i end
    end
end

function WT:LayerCount()
    return #SortedLayerKeys(self:Data().layers)
end

function WT:CurrentLayer() return currentLayer end

local function LayerCount(layers)
    local n = 0
    for k in pairs(layers) do if type(k) == "number" then n = n + 1 end end
    return n
end

function WT:GetLayer(zoneUID, create)
    local layers = self:Data().layers
    local layer = layers[zoneUID]
    if not layer and create and zoneUID and zoneUID > 0 and LayerCount(layers) < MAX_LAYERS then
        layer = { created = Now(), lastSeenNPC = 0, layerMap = {}, flowers = {} }
        layers[zoneUID] = layer
    end
    if layer then
        if type(layer.layerMap) ~= "table" then layer.layerMap = {} end
        if type(layer.flowers) ~= "table" then layer.flowers = {} end
    end
    return layer
end

-- The layer a zoneUID belongs to (a Shattrath key, or mapped in a layerMap)
function WT:LayerOfZone(zoneUID, mapID)
    if not zoneUID then return nil end
    local layers = self:Data().layers
    if layers[zoneUID] then return zoneUID end
    for key, layer in pairs(layers) do
        local m = type(layer.layerMap) == "table" and layer.layerMap[zoneUID]
        if m and (not mapID or m == mapID) then return key end
    end
end

function WT:OnGroupJoined()
    lastGroupJoin = GetTime()
    joinedGroup = true
    currentLayer, confirmedLayer = nil, nil
    wipe(phase)
end

-- A creature seen by target or mouseover
function WT:SeeUnit(unit)
    local zoneUID, npcID, spawnUID = ParseGUID(UnitGUID(unit))
    if not zoneUID or zoneUID == 0 or IGNORE_NPCS[npcID] then return end
    local mapID = MapID()
    local now = Now()
    if mapID == TEROKKAR then self.terokTargetSeen = true end
    if mapID == SHATTRATH and SHATTRATH_NPCS[npcID] then
        if GetTime() - lastGroupJoin < 600 and lastGroupJoin > 0 then return end
        local layer = self:GetLayer(zoneUID, true)
        if not layer then return end
        layer.lastSeenNPC = now
        -- How long the layer's been up, from the NPC's spawn time
        if type(spawnUID) == "string" and #spawnUID >= 10 then
            local offset = tonumber(spawnUID:sub(5), 16)
            if offset then
                offset = offset % 8388608
                local spawn = now - (now % 8388608) + offset
                if spawn > now then spawn = spawn - 8388607 end
                if not layer.spawn or layer.spawn == 0 or spawn < layer.spawn then layer.spawn = spawn end
            end
        end
        local was = currentLayer
        currentLayer, confirmedLayer = zoneUID, zoneUID
        wipe(phase)
        if was ~= zoneUID then self:RefreshUI() end
        return
    end
    if not (mapID and LAYER_ZONES[mapID]) then return end
    if IsInInstance and IsInInstance() == true then return end
    local known = self:LayerOfZone(zoneUID, mapID)
    if known then
        currentLayer = known
        return
    end
    -- A zone not seen on any layer yet: tie it to the confirmed layer,
    -- unless anything suggests you've changed layer
    if not confirmedLayer or joinedGroup then return end
    if phase[mapID] and phase[mapID] ~= zoneUID then
        -- Two different instances of one zone: the layer may have changed
        currentLayer, confirmedLayer = nil, nil
        return
    end
    phase[mapID] = zoneUID
    local layer = self:GetLayer(confirmedLayer)
    if not layer or layer.layerMap[zoneUID] then return end
    for _, m in pairs(layer.layerMap) do if m == mapID then return end end
    if self:Data().layers[zoneUID] then return end
    layer.layerMap[zoneUID] = mapID
    currentLayer = confirmedLayer
end

-- Drop layers nobody has seen for two hours, unless a timer still runs on them
function WT:ExpireLayers(now)
    now = now or Now()
    local layers = self:Data().layers
    for key, layer in pairs(layers) do
        if type(key) == "number" and now - (layer.lastSeenNPC or 0) > LAYER_EXPIRE then
            local active = (layer.terokTowers and layer.terokTowers > now)
            for _, b in ipairs(BUFF_ORDER) do
                local t = layer[b .. "Timer"]
                if t and t + BUFFS[b].cooldown > now then active = true end
            end
            for _, t in pairs(layer.flowers or {}) do if now - t < SONGFLOWER_RESPAWN then active = true end end
            if not active then
                layers[key] = nil
                if currentLayer == key then currentLayer = nil end
                if confirmedLayer == key then confirmedLayer = nil end
            end
        end
    end
end

-- ============================================
-- TEROKKAR TOWERS
-- ============================================

local function WidgetInfo(id)
    if not (C_UIWidgetManager and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo) then return nil end
    local ok, info = pcall(C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo, id)
    if ok and type(info) == "table" then return info end
end

local function ParseTowerTime(text)
    if type(text) ~= "string" then return nil end
    local h, m = text:match("(%d+):%s*(%d+)")
    if not h then
        local nums = {}
        for n in text:gmatch("%d+") do nums[#nums + 1] = n end
        if #nums ~= 2 then return nil end
        h, m = nums[1], nums[2]
    end
    return tonumber(h) * 3600 + tonumber(m) * 60
end
WT.ParseTowerTime = ParseTowerTime

-- The time the towers really reset (their clock runs slow)
function WT.TerokEnd(towers, readAt)
    if not towers then return nil end
    return towers + math.floor(((towers - (readAt or towers)) / 60) * TEROK_DRIFT)
end

-- Read the Terokkar widget (debounced by the caller)
function WT:ReadTowers()
    if MapID() ~= TEROKKAR or not self.terokTargetSeen then return end
    local layerKey = currentLayer
    local layer = layerKey and self:GetLayer(layerKey)
    if not layer then return end
    local c1, c2 = WidgetInfo(TEROK_WIDGETS.cap1), WidgetInfo(TEROK_WIDGETS.cap2)
    if c1 and c2 and c1.state == 1 and c2.state == 1 then
        -- Being captured: no reset timer right now
        layer.terokTowers, layer.terokTowersTime, layer.terokFaction = nil, nil, nil
        return
    end
    local faction, info
    for kind, id in pairs({ [1] = TEROK_WIDGETS.neutral, [2] = TEROK_WIDGETS.alliance, [3] = TEROK_WIDGETS.horde }) do
        local w = WidgetInfo(id)
        if w and w.state == 1 then faction, info = kind, w end
    end
    if not info then return end
    local left = ParseTowerTime(info.text)
    if not left or left <= 0 or left >= 22000 then return end
    local now = Now()
    local towers = now + left
    if layer.terokTowers and towers - layer.terokTowers <= -1800 then return end
    layer.terokTowers, layer.terokTowersTime, layer.terokFaction = towers, now, faction
    layer.terokWarned = (towers - now) <= 900 or nil
    self:RefreshUI()
end

local towerPending
function WT:OnWidgetUpdate(info)
    local id = type(info) == "table" and info.widgetID or info
    if id ~= TEROK_WIDGETS.neutral and id ~= TEROK_WIDGETS.alliance and id ~= TEROK_WIDGETS.horde then return end
    if towerPending then return end
    towerPending = true
    WM.RunAfter(2, function()
        towerPending = false
        WT:ReadTowers()
    end)
end

-- ============================================
-- DAILIES
-- ============================================

local gossipNPC, gossipClosed, gossipShown = nil, -100, -100

function WT:OnGossipShow()
    local _, npcID = ParseGUID(UnitGUID("npc"))
    gossipNPC, gossipShown = npcID, GetTime()
end

function WT:OnQuestFinished()
    if not gossipNPC then return end
    for _, kind in pairs(DAILY_KINDS) do
        if kind.npcs[gossipNPC] then gossipClosed = GetTime() end
    end
end

function WT:OnQuestAccepted(...)
    -- 2.5.6 may pass (questID) or (logIndex, questID): use the last number
    local questID
    for i = 1, select("#", ...) do
        local v = tonumber((select(i, ...)))
        if v then questID = v end
    end
    -- Accepted from the NPC (not shared): their window closed a moment ago,
    -- or is still open from talking to them
    if not questID or (GetTime() - gossipClosed > 2 and GetTime() - gossipShown > 120) then return end
    for kindName, kind in pairs(DAILY_KINDS) do
        local d = kind.quests[questID]
        if d and kind.npcs[gossipNPC or 0] then
            self:Data().dailies[kindName] = { id = d[1], at = Now() }
            self:RefreshUI()
            return kindName
        end
    end
end

-- The daily of each kind seen in the last 24 hours: name or nil
function WT:Daily(kindName, now)
    local d = self:Data().dailies[kindName]
    if not d or not d.id or (now or Now()) - (d.at or 0) >= DAY then return nil end
    return DAILY_KINDS[kindName].names[d.id]
end

-- ============================================
-- DARKMOON FAIRE
-- ============================================

-- Days since 1970-01-01 for a civil date (proleptic Gregorian)
local function DaysFromCivil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
WT.DaysFromCivil = DaysFromCivil

local function UTCParts(t)
    local days = math.floor(t / 86400)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- Region: start hour (UTC) on the Monday after the first Friday
local REGION_HOURS = { [1] = 8, [2] = 1, [3] = 2, [4] = 1, [5] = 20 }

local function Region()
    local r = GetCurrentRegion and tonumber(GetCurrentRegion())
    return r or 1
end

-- When the Faire starts and ends in a given month (UTC epoch seconds)
function WT.DmfDates(year, month, region, dst)
    local hour = REGION_HOURS[region or 1] or 8
    if dst then hour = hour - 1 end
    local first = DaysFromCivil(year, month, 1)
    local weekday = (first + 4) % 7          -- 0 = Sunday; 1970-01-01 was a Thursday
    local firstFriday = 1 + (5 - weekday) % 7
    local start = (DaysFromCivil(year, month, firstFriday + 3)) * 86400 + hour * 3600
    return start, start + 7 * 86400
end

-- Where the Faire is in the month it starts
function WT.DmfPlace(month)
    if month % 3 == 1 then return "Terokkar Forest (Outland)" end
    if month % 3 == 0 then return "Elwynn Forest" end
    return "Mulgore"
end

-- { up = bool, start, ends, place, next = {start, place} }
function WT:Dmf(now)
    now = now or Now()
    local region = Region()
    local dst = false
    local ok, t = pcall(date, "*t", now)
    if ok and type(t) == "table" then dst = t.isdst and true or false end
    local y, m = UTCParts(now)
    for _ = 1, 3 do
        local start, ends = WT.DmfDates(y, m, region, dst)
        if now < ends then
            local nm, ny = m + 1, y
            if nm > 12 then nm, ny = 1, y + 1 end
            local nextStart = WT.DmfDates(ny, nm, region, dst)
            if now < start then
                return { up = false, start = start, ends = ends, place = WT.DmfPlace(m) }
            end
            return { up = true, start = start, ends = ends, place = WT.DmfPlace(m),
                next = { start = nextStart, place = WT.DmfPlace(nm) } }
        end
        m = m + 1
        if m > 12 then m, y = 1, y + 1 end
    end
end

-- Sayge's fortune: 4 hours of time played before another
function WT:DmfCooldown(charKey)
    local c = DB().chars[charKey or CharKey()]
    return c and c.dmfCooldown and c.dmfCooldown > 0 and c.dmfCooldown or 0
end

function WT:StartDmfCooldown()
    local key = CharKey()
    DB().chars[key] = DB().chars[key] or {}
    DB().chars[key].dmfCooldown = DMF_COOLDOWN
    self:Print("Darkmoon Faire buff received: you can get another in 4 hours of play.")
end

function WT:TickDmf(elapsed)
    local c = DB().chars[CharKey()]
    if not c or not c.dmfCooldown or c.dmfCooldown <= 0 then return end
    c.dmfCooldown = c.dmfCooldown - elapsed
    if c.dmfCooldown <= 0 then
        c.dmfCooldown = 0
        local dmf = self:Dmf()
        if dmf and dmf.up then self:Print("|cFF33FF33Your Darkmoon Faire buff cooldown has reset.|r") end
    end
end

-- Remaining duration of a buff on you, by spell ID
local function MyBuffLeft(spellID)
    for i = 1, 40 do
        local name, _, _, _, _, expires, _, _, _, id = UnitBuff("player", i)
        if not name then return nil end
        if id == spellID then
            if not expires or expires == 0 then return math.huge end
            return expires - GetTime()
        end
    end
end

-- ============================================
-- WORLD BUFFS
-- ============================================

local lastYell = {}       -- buff -> { first = t, second = t } (this session)
local lastBuffSet = 0

function WT:BuffLayer(sourceGUID)
    local zoneUID = ParseGUID(sourceGUID)
    local key = self:LayerOfZone(zoneUID)
    if key then return self:GetLayer(key) end
    if currentLayer then return self:GetLayer(currentLayer) end
    return self:Data().buffs
end

function WT:OnYell(msg, npcName)
    if type(msg) ~= "string" then return end
    for _, y in ipairs(YELLS) do
        if msg:find(y.text, 1, true) then
            local rec = lastYell[y.buff] or {}
            lastYell[y.buff] = rec
            local now = Now()
            if y.first then
                rec.first = now
                if y.buff ~= "zan" and DB().buffWarn then
                    self:Print("|cFFFFCC33" .. BUFFS[y.buff].name .. " is about to drop|r (" .. (npcName or "?") .. ").")
                end
            else
                rec.second = now
            end
            return y.buff
        end
    end
end

-- A world buff landing on you sets its timer, if the NPC just yelled
function WT:OnBuffApplied(spellID, sourceGUID)
    local _, npcID = ParseGUID(sourceGUID)
    local now = Now()
    for _, b in ipairs({ "nef", "ony", "rend", "zan" }) do
        local buff = BUFFS[b]
        if buff.spells[spellID] and (not npcID or BUFF_NPCS[b][npcID] or b == "zan") then
            local rec = lastYell[b]
            local recent = rec and ((rec.second and now - rec.second < 30) or (rec.first and now - rec.first < 30))
            if recent and now - lastBuffSet > 20 then
                lastBuffSet = now
                if b == "zan" then return b end
                local layer = self:BuffLayer(sourceGUID)
                layer[b .. "Timer"] = now
                layer[b .. "Yell"] = rec.first or rec.second
                layer[b .. "Warned"] = nil
                self:RefreshUI()
                return b
            end
        end
    end
end

function WT:OnUnitDied(destName)
    local b = KILL_NPCS[destName or ""]
    if not b then return end
    local layer = self:BuffLayer(nil)
    layer[b .. "NpcDied"] = Now()
    self:Print(destName .. " has just been killed (" .. BUFFS[b].name .. " buff NPC).")
end

-- Warnings at 30, 15, 10, 5 and 1 minutes, and when it can drop again
function WT:CheckBuffWarnings(now)
    if not DB().buffWarn then return end
    now = now or Now()
    local function Check(layer, label)
        for _, b in ipairs(BUFF_ORDER) do
            local t = layer[b .. "Timer"]
            if t and t > 0 and not ((layer[b .. "NpcDied"] or 0) > t) then
                local left = t + BUFFS[b].cooldown - now
                local warned = layer[b .. "Warned"] or 99999
                for _, at in ipairs(WARN_AT) do
                    if left <= at and at < warned and left > at - 30 then
                        layer[b .. "Warned"] = at
                        if at == 0 then
                            self:Print("A new " .. BUFFS[b].name .. " buff can be dropped now" .. label .. ".")
                        else
                            self:Print(BUFFS[b].name .. " resets in " .. Short(at) .. label .. ".")
                        end
                        break
                    end
                end
            end
        end
    end
    for key, layer in pairs(self:Data().layers) do
        if type(key) == "number" then Check(layer, " (Layer " .. (self:LayerNumber(key) or "?") .. ")") end
    end
    Check(self:Data().buffs, "")
end

function WT:CheckTerokWarning(now)
    if not DB().terokWarn then return end
    now = now or Now()
    for key, layer in pairs(self:Data().layers) do
        if type(key) == "number" and layer.terokTowers and not layer.terokWarned then
            local left = WT.TerokEnd(layer.terokTowers, layer.terokTowersTime) - now
            if left <= 600 and left >= 570 then
                layer.terokWarned = true
                self:Print("Terokkar Forest towers reset in 10 minutes (Layer " .. (self:LayerNumber(key) or "?") .. ").")
            end
        end
        if type(key) == "number" and layer.terokTowers and WT.TerokEnd(layer.terokTowers, layer.terokTowersTime) < now - 3600 then
            layer.terokTowers, layer.terokTowersTime, layer.terokFaction, layer.terokWarned = nil, nil, nil, nil
        end
    end
end

-- ============================================
-- SONGFLOWERS
-- ============================================

local seenInFelwood = {}   -- GUID -> GetTime() first seen (so login buffs aren't picks)

local function PlayerXY()
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, FELWOOD, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    return x * 100, y * 100
end

function WT.NearestFlower(x, y)
    if not x then return nil end
    for i, f in ipairs(SONGFLOWERS) do
        local dx, dy = x - f[1], y - f[2]
        if math.sqrt(dx * dx + dy * dy) <= 1.5 then return i end
    end
end

function WT:OnSongflower(destGUID, isMe)
    if MapID() ~= FELWOOD then return end
    if not isMe then
        local first = seenInFelwood[destGUID]
        if not first or GetTime() - first < 1 or GetTime() - first > 600 then return end
    elseif (MyBuffLeft(SONGFLOWER_SPELL) or 0) < 3599 then
        return
    end
    local n = WT.NearestFlower(PlayerXY())
    if not n then return end
    local flowers = currentLayer and self:GetLayer(currentLayer) and self:GetLayer(currentLayer).flowers or self:Data().flowers
    local now = Now()
    if flowers[n] and now - flowers[n] < 1440 then return end
    flowers[n] = now
    self:Print("Songflower picked at " .. SONGFLOWERS[n][3] .. ": next one in 25 minutes.")
    self:RefreshUI()
    return n
end

-- ============================================
-- COMBAT LOG
-- ============================================

function WT:OnCombatEvent(_, sub, _, srcGUID, _, _, _, dstGUID, dstName, _, _, spellID)
    local me = UnitGUID("player")
    if sub == "UNIT_DIED" then
        self:OnUnitDied(dstName)
        return
    end
    if MapID() == FELWOOD then
        if dstGUID and not seenInFelwood[dstGUID] and dstGUID:find("^Player") then seenInFelwood[dstGUID] = GetTime() end
        if srcGUID and not seenInFelwood[srcGUID] and srcGUID:find("^Player") then seenInFelwood[srcGUID] = GetTime() end
    end
    if sub ~= "SPELL_AURA_APPLIED" and sub ~= "SPELL_AURA_REFRESH" then return end
    spellID = tonumber(spellID)
    if spellID == SONGFLOWER_SPELL then
        self:OnSongflower(dstGUID, me ~= nil and dstGUID == me)
        return
    end
    if not me or dstGUID ~= me then return end
    if DMF_SPELLS[spellID] then
        if (MyBuffLeft(spellID) or 0) >= 7199 then self:StartDmfCooldown() end
        return
    end
    self:OnBuffApplied(spellID, srcGUID)
end

-- ============================================
-- NOVA WORLD BUFFS DATA (listen only)
-- ============================================

local function Expand(t, depth)
    if type(t) ~= "table" or (depth or 0) > 6 then return t end
    local out = {}
    for k, v in pairs(t) do out[NWB_KEYS[k] or k] = Expand(v, (depth or 0) + 1) end
    return out
end
WT.ExpandKeys = Expand

local function ValidTime(v, now)
    return type(v) == "number" and v > 0 and v <= now + 30000 and v <= 2585912598
end

-- Merge one decoded "data" table. Returns how many values were taken.
function WT:MergeNWB(t, now)
    now = now or Now()
    if type(t) ~= "table" then return 0 end
    t = Expand(t)
    local taken = 0
    local data = self:Data()
    if type(t.layers) == "table" then
        for key in pairs(t.layers) do if type(key) ~= "number" then return 0 end end
        for key, lt in pairs(t.layers) do
            local seen = tonumber(lt.lastSeenNPC)
            if type(lt) == "table" and seen and now - seen <= LAYER_EXPIRE and seen <= now + 30 then
                local layer = self:GetLayer(key, true)
                if layer then
                    if seen > (layer.lastSeenNPC or 0) then layer.lastSeenNPC = seen; taken = taken + 1 end
                    local spawn = tonumber(lt.spawn)
                    if spawn and spawn > 0 and (not layer.spawn or layer.spawn == 0 or spawn < layer.spawn) then layer.spawn = spawn end
                    -- Terokkar
                    local L, U, M = tonumber(lt.terokTowers), tonumber(lt.terokTowersTime), tonumber(lt.terokFaction)
                    if L and U and U > (layer.terokTowersTime or 0) and L > now and L < now + 21700
                        and L > (layer.terokTowers or 0) - 1800 and math.abs(U - now) < 21700 then
                        layer.terokTowers, layer.terokTowersTime, layer.terokFaction = L, U, M
                        layer.terokWarned = (WT.TerokEnd(L, U) - now) <= 900 or nil
                        taken = taken + 1
                    end
                    -- World buffs: need the NPC's yell within 2 minutes of the drop
                    for _, b in ipairs(BUFF_ORDER) do
                        local timer, yell = tonumber(lt[b .. "Timer"]), tonumber(lt[b .. "Yell"])
                        if ValidTime(timer, now) and yell and math.abs(timer - yell) <= 120
                            and now - timer < BUFFS[b].cooldown and timer > (layer[b .. "Timer"] or 0) then
                            layer[b .. "Timer"], layer[b .. "Yell"], layer[b .. "Warned"] = timer, yell, nil
                            taken = taken + 1
                        end
                        local died = tonumber(lt[b .. "NpcDied"])
                        if ValidTime(died, now) and died > (layer[b .. "NpcDied"] or 0) then layer[b .. "NpcDied"] = died end
                    end
                    -- Songflowers
                    for i = 1, #SONGFLOWERS do
                        local f = tonumber(lt["flower" .. i])
                        local mine = layer.flowers[i]
                        if ValidTime(f, now) and now - f < SONGFLOWER_RESPAWN and f > (mine or 0)
                            and not (mine and now - mine < SONGFLOWER_RESPAWN and math.abs(f - mine) > 10) then
                            layer.flowers[i] = f
                            taken = taken + 1
                        end
                    end
                    -- Zones followed to this layer
                    if type(lt.layerMap) == "table" then
                        for zoneUID, mapID in pairs(lt.layerMap) do
                            if type(zoneUID) == "number" and type(mapID) == "number" and LAYER_ZONES[mapID]
                                and not data.layers[zoneUID] and not self:LayerOfZone(zoneUID) then
                                local has = false
                                for _, m in pairs(layer.layerMap) do if m == mapID then has = true end end
                                if not has then layer.layerMap[zoneUID] = mapID; taken = taken + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Dailies
    for kindName, keys in pairs({ heroic = { "tbcHD", "tbcHDT" }, dungeon = { "tbcDD", "tbcDDT" }, pvp = { "tbcPD", "tbcPDT" } }) do
        local id, at = tonumber(t[keys[1]]), tonumber(t[keys[2]])
        local mine = data.dailies[kindName]
        if id and ValidTime(at, now) and now - at < DAY and DAILY_KINDS[kindName].names[id]
            and at > (mine and mine.at or 0) then
            data.dailies[kindName] = { id = id, at = at }
            taken = taken + 1
        end
    end
    if taken > 0 then self:RefreshUI() end
    return taken
end

-- An NWB addon message (already reassembled by AceComm framing)
function WT:OnNWBMessage(body, distribution, sender)
    if not DB().listenNWB or not WM.Nova then return nil end
    local ok, text = WM.Nova.DecodeBody(body, distribution)
    if not ok or type(text) ~= "string" then return nil end
    local cmd, ver, lvl, _, rest = text:match("^(%S+) (%S+) (%S+) (%S+) ?(.*)$")
    if not cmd then
        cmd, ver, lvl = text:match("^(%S+) (%S+) (%S+)")
        rest = ""
    end
    if not cmd then return nil end
    ver = tonumber(ver)
    if not ver or ver < NWB_MIN_VERSION then return nil end
    local level = tonumber((lvl or ""):match("^(%d+)"))
    if not level or level <= 5 then return nil end
    if cmd == "data" then
        local okT, t = WM.Nova.Deserialize(rest)
        if not okT then return nil end
        return self:MergeNWB(t), "data"
    elseif cmd == "yell" or cmd == "npcKilled" then
        local b = rest:match("^(%a+)")
        if b and BUFFS[b] and DB().showNWBNotices then
            local who = (WM.Nova and sender and (sender:match("^([^-]+)"))) or "someone"
            if cmd == "yell" then
                self:Print(BUFFS[b].name .. " is about to drop (seen by " .. who .. ").")
            else
                self:Print(BUFFS[b].name .. " buff NPC has just been killed (seen by " .. who .. ").")
            end
        end
        return 0, cmd
    end
    return 0, cmd
end

-- ============================================
-- TEXT FOR CHAT AND THE WINDOW
-- ============================================

local FACTION_TEXT = { [1] = "|cFFBBBBBBNeutral|r", [2] = "|cFF3399FFAlliance|r", [3] = "|cFFFF4444Horde|r" }

function WT:LayerLines(now)
    now = now or Now()
    local lines = {}
    local keys = SortedLayerKeys(self:Data().layers)
    if #keys == 0 then
        lines[1] = "|cFF888888No layers seen yet. Target A'dal, Nutral, Minalei or Innkeeper Haelthol in Shattrath.|r"
        return lines
    end
    for i, key in ipairs(keys) do
        local layer = self:Data().layers[key]
        local head = "|cFFFFCC00Layer " .. i .. "|r" .. (key == currentLayer and " |cFF33FF33(you are here)|r" or "")
        if layer.spawn and layer.spawn > 0 then head = head .. "  |cFF888888up " .. Short(now - layer.spawn) .. "|r" end
        lines[#lines + 1] = head
        if layer.terokTowers then
            local left = WT.TerokEnd(layer.terokTowers, layer.terokTowersTime) - now
            lines[#lines + 1] = "   Terokkar towers (" .. (FACTION_TEXT[layer.terokFaction] or "?") .. "): "
                .. (left > 0 and ("reset in " .. Short(left)) or "|cFFFF4444reset " .. Short(-left) .. " ago|r")
        end
        for _, b in ipairs(BUFF_ORDER) do
            local t = layer[b .. "Timer"]
            if t and t + BUFFS[b].cooldown > now then
                lines[#lines + 1] = "   " .. BUFFS[b].name .. ": can drop again in " .. Short(t + BUFFS[b].cooldown - now)
            end
        end
        local fl = {}
        for n, t in pairs(layer.flowers or {}) do
            if now - t < SONGFLOWER_RESPAWN then fl[#fl + 1] = SONGFLOWERS[n][3] .. " " .. Short(t + SONGFLOWER_RESPAWN - now) end
        end
        if #fl > 0 then lines[#lines + 1] = "   Songflowers: " .. table.concat(fl, ", ") end
    end
    return lines
end

function WT:DmfLine(now)
    local d = self:Dmf(now)
    if not d then return "Darkmoon Faire: unknown for this region" end
    now = now or Now()
    local line
    if d.up then
        line = "Darkmoon Faire is up in |cFFFFFFFF" .. d.place .. "|r, ends in " .. Short(d.ends - now)
            .. "  |cFF888888(next: " .. d.next.place .. ")|r"
    else
        line = "Darkmoon Faire opens in |cFFFFFFFF" .. d.place .. "|r in " .. Short(d.start - now)
    end
    local cd = self:DmfCooldown()
    if cd > 0 then line = line .. "\n   Your Sayge buff: another in " .. Short(cd) .. " of play"
    elseif d.up then line = line .. "\n   Your Sayge buff: ready" end
    return line
end

function WT:DailyLines(now)
    local lines = {}
    for _, k in ipairs(DAILY_ORDER) do
        local name = self:Daily(k, now)
        lines[#lines + 1] = DAILY_KINDS[k].label .. " daily: " .. (name and ("|cFFFFFFFF" .. name .. "|r") or "|cFF888888unknown|r")
    end
    return lines
end

function WT:AllText(now)
    now = now or Now()
    local parts = {}
    local n = currentLayer and self:LayerNumber(currentLayer)
    parts[#parts + 1] = n and ("You are on |cFF33FF33Layer " .. n .. "|r of " .. self:LayerCount())
        or "|cFF888888Layer unknown: target an NPC (in Shattrath to be sure).|r"
    parts[#parts + 1] = " "
    parts[#parts + 1] = self:DmfLine(now)
    parts[#parts + 1] = " "
    for _, l in ipairs(self:DailyLines(now)) do parts[#parts + 1] = l end
    parts[#parts + 1] = " "
    for _, l in ipairs(self:LayerLines(now)) do parts[#parts + 1] = l end
    local loose = {}
    for _, b in ipairs(BUFF_ORDER) do
        local t = self:Data().buffs[b .. "Timer"]
        if t and t + BUFFS[b].cooldown > now then loose[#loose + 1] = BUFFS[b].name .. " " .. Short(t + BUFFS[b].cooldown - now) end
    end
    if #loose > 0 then parts[#parts + 1] = "World buffs (layer unknown): " .. table.concat(loose, ", ") end
    return table.concat(parts, "\n")
end

-- /wmachine wb [channel]: the short version, to you or a channel
function WT:ShortTimers(now)
    now = now or Now()
    local bits = {}
    for i, key in ipairs(SortedLayerKeys(self:Data().layers)) do
        local layer = self:Data().layers[key]
        if layer.terokTowers then
            local left = WT.TerokEnd(layer.terokTowers, layer.terokTowersTime) - now
            if left > 0 then bits[#bits + 1] = "(Terokkar L" .. i .. ": " .. Short(left) .. ")" end
        end
        for _, b in ipairs(BUFF_ORDER) do
            local t = layer[b .. "Timer"]
            if t and t + BUFFS[b].cooldown > now then bits[#bits + 1] = "(" .. BUFFS[b].name .. " L" .. i .. ": " .. Short(t + BUFFS[b].cooldown - now) .. ")" end
        end
    end
    local d = self:Dmf(now)
    if d then bits[#bits + 1] = d.up and ("(DMF " .. d.place .. ": ends in " .. Short(d.ends - now) .. ")")
        or ("(DMF " .. d.place .. ": opens in " .. Short(d.start - now) .. ")") end
    for _, k in ipairs(DAILY_ORDER) do
        local name = self:Daily(k, now)
        if name then bits[#bits + 1] = "(" .. DAILY_KINDS[k].label .. " daily: " .. name .. ")" end
    end
    if #bits == 0 then return "No timers known yet." end
    return table.concat(bits, " ")
end

function WT:Report(channel)
    local text = self:ShortTimers()
    channel = channel and channel:upper()
    if channel == "GUILD" or channel == "PARTY" or channel == "RAID" or channel == "SAY" then
        SendChatMessage("[WM] " .. text, channel)
    else
        self:Print(text)
    end
end

-- ============================================
-- WINDOW
-- ============================================

local panel

function WT:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_WorldTimersFrame", title = "World Timers", titleColor = "66FFCC", width = 480,
        onRefresh = function() end,
    })
    local L = panel.layout
    local row = L:Row(20)
    local fs = WM.UI.Text(row.frame, { text = function() return WT:AllText() end, width = 440 })
    fs:SetPoint("TOPLEFT", 8, -2)
    L:Track(fs)
    row.measure = function() return math.max(20, math.floor((fs.GetStringHeight and fs:GetStringHeight() or 0) + 8)) end
    panel.text = fs
    L:Section({ key = "options", title = "Options" })
    L:Checkbox({ label = "Warn 10 minutes before the Terokkar towers reset",
        get = function() return DB().terokWarn end, set = function(v) DB().terokWarn = v end })
    L:Checkbox({ label = "World buff warnings (30, 15, 10, 5, 1 minutes)",
        get = function() return DB().buffWarn end, set = function(v) DB().buffWarn = v end,
        tooltip = { "World buffs", "Rend, Onyxia and Nefarian: when the buff can be dropped again. Rare on TBC." } })
    L:Checkbox({ label = "Use timers from Nova World Buffs users",
        get = function() return DB().listenNWB end, set = function(v) DB().listenNWB = v end,
        tooltip = { "Nova World Buffs", "Nova World Buffs users share layers, Terokkar towers, dailies and"
            .. " Songflowers with each other (guild, group and nearby players). Watching Machine reads them,"
            .. " checked the way Nova checks them. It never sends in Nova's format." } })
    L:Checkbox({ label = "Show their \"buff about to drop\" / NPC killed notices",
        get = function() return DB().showNWBNotices end, set = function(v) DB().showNWBNotices = v end })
    L:EndSection()
    panel:AddFooterButton({ text = "Print timers", width = 100, onClick = function() WT:Report() end }, "LEFT")
    panel:Finish()
    local since = 0
    panel:HookScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 1 then since = 0; panel:Refresh() end
    end)
    return panel
end

function WT:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function WT:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
WT.ToggleUI = WT.Toggle

function WT:GetQuickStatus()
    local n = currentLayer and self:LayerNumber(currentLayer)
    local d = self:Dmf()
    local s = n and ("Layer " .. n) or "Layer ?"
    if d then s = s .. ", DMF " .. (d.up and ("up (" .. d.place .. ")") or ("in " .. Short(d.start - Now()))) end
    return s
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

function WT:OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        self:SeeUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        self:SeeUnit("mouseover")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if CombatLogGetCurrentEventInfo then self:OnCombatEvent(CombatLogGetCurrentEventInfo()) end
    elseif event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_SAY" then
        self:OnYell(...)
    elseif event == "UPDATE_UI_WIDGET" then
        self:OnWidgetUpdate(...)
    elseif event == "GOSSIP_SHOW" or event == "QUEST_DETAIL" then
        self:OnGossipShow()
    elseif event == "QUEST_FINISHED" or event == "GOSSIP_CLOSED" then
        self:OnQuestFinished()
    elseif event == "QUEST_ACCEPTED" then
        self:OnQuestAccepted(...)
    elseif event == "GROUP_JOINED" then
        self:OnGroupJoined()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        if MapID() == TEROKKAR then self.terokTargetSeen = false end
        if MapID() ~= FELWOOD then wipe(seenInFelwood) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, distribution, sender = ...
        if prefix ~= "NWB" or type(message) ~= "string" then return end
        if WM.Nova and sender and WM.Nova.Reassemble then
            local short = Ambiguate and Ambiguate(sender, "none") or sender
            if short == UnitName("player") then return end
            local body = WM.Nova.Reassemble(prefix, message, distribution, sender)
            if body then self:OnNWBMessage(body, distribution, sender) end
        end
    end
end

function WT:Initialize()
    DB()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, "NWB") end
    WM:RegisterEvents(events, {
        "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "COMBAT_LOG_EVENT_UNFILTERED",
        "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_SAY", "UPDATE_UI_WIDGET",
        "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_FINISHED", "GOSSIP_CLOSED", "QUEST_ACCEPTED",
        "GROUP_JOINED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON",
    })
    if WM.RegisterChatLink then
        WM:RegisterChatLink("wtimers", function()
            local p = WT:CreateUI()
            if not p:IsShown() then p:Show() end
        end)
    end
    local last = GetTime()
    WM.RunTicker(5, function()
        local t = GetTime()
        WT:TickDmf(t - last)
        last = t
        local now = Now()
        WT:CheckTerokWarning(now)
        WT:CheckBuffWarnings(now)
    end)
    WM.RunTicker(60, function() WT:ExpireLayers() end)
end

events:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(WT.OnEvent, WT, event, ...)
    if not ok then geterrorhandler()(err) end
end)
