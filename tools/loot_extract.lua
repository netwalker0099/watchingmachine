-- Reads AtlasLoot's data files in a sandbox and keeps the facts only:
-- what is in each instance / profession / faction / PvP page, by item,
-- craft spell or set ID. Usage: lua5.1 loot_extract2.lua <atlas dir> <out dir>
local dir, out = assert(arg[1]), assert(arg[2])
local CURRENT = 2

local function Sandboxed(path, env, ...)
    local f = assert(loadfile(path))
    setfenv(f, env)
    return f(...)
end

local captured
local diffOrder = 0
local function NewData()
    local data = {}
    captured = data
    function data:AddDifficulty(name, short)
        diffOrder = diffOrder + 1
        return { diff = short or name, name = name }
    end
    function data:AddItemTableType(a) return "tt:" .. a end
    function data:AddExtraItemTableType(a) return "ett:" .. a end
    function data:AddContentType(n) return { content = n } end
    return setmetatable(data, { __newindex = function(t, k, v) rawset(t, k, v); local o = rawget(t, "_order") or {}; rawset(t, "_order", o); table.insert(o, k) end })
end

local AtlasLoot = {
    CLASSIC_VERSION_NUM = 1, BC_VERSION_NUM = 2, WRATH_VERSION_NUM = 3, RETAIL_VERSION_NUM = 99,
    ItemDB = { Add = function() return NewData() end },
    Locales = setmetatable({}, { __index = function(_, k) return k end }),
    IngameLocales = setmetatable({}, { __index = function(_, k) return k end }),
    Data = { ContentPhase = { GetActivePhase = function() return 6 end },
        Profession = { GetColorSkillRankNoSpell = function() return "" end },
        Requirements = { GetPvPRankName = function(r) return "Rank " .. tostring(r) end, GetPvPRankIcon = function() return "" end } },
}
function AtlasLoot:GetRetByFaction(h, a) return h end
function AtlasLoot.ReturnForGameVersion(c, b, w) if CURRENT >= 3 then return w or b or c end return b or c end
function AtlasLoot:GameVersion_GE(v, ret, f)
    if v > CURRENT then if ret ~= nil then return { __min = v, value = ret } end return f or false end
    if ret == nil then return true end return ret
end
function AtlasLoot:GameVersion_LT(v, ret, f)
    if CURRENT < v then if ret == nil then return true end return ret end
    return f or false
end
function AtlasLoot:GameVersion_EQ(v, ret, f)
    if CURRENT == v then if ret == nil then return true end return ret end
    return f or false
end
local env
env = setmetatable({
    AtlasLoot = AtlasLoot, string = string, math = math, table = table, pairs = pairs, ipairs = ipairs,
    type = type, select = select, tostring = tostring, tonumber = tonumber, unpack = unpack, format = string.format,
    setmetatable = setmetatable, next = next, getfenv = function() return env end,
    UnitFactionGroup = function() return "Horde" end, FACTION_HORDE = "Horde", FACTION_ALLIANCE = "Alliance",
    ATLASLOOT_IT_HORDE = "horde", ATLASLOOT_IT_ALLIANCE = "alliance", GENERAL = "General",
    RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff", r = 1, g = 1, b = 1 } end }),
    C_Map = { GetAreaInfo = function(id) return "@area:" .. id end },
    CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end,
    print = function() end,
}, { __index = function(_, k) if type(k) == "string" and k:find("^ATLASLOOT_") then return k end end })
env._G = env
local private = setmetatable({}, { __index = function() return nil end })

local function strip(s)
    if type(s) ~= "string" then return nil end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function q(s) return string.format("%q", s) end

local DIFF_KEY = { NORMAL = "n", HEROIC = "h", Normal = "n", n = "n" }
local function DiffKey(d) return DIFF_KEY[d.diff] or d.diff end

local refs = { item = {}, craft = {}, set = {} }
local function ItemsOf(list, kind)
    local rows = {}
    for _, e in ipairs(list or {}) do
        if type(e) == "table" then
            if type(e.horde) == "table" then e.horde = e.horde[1] end
            if type(e.alliance) == "table" then e.alliance = e.alliance[1] end
            -- true: only that faction's; false: hidden from that faction
            if type(e[2]) == "number" and (e.alliance == true or e.horde == false) then e[2], e.horde, e.alliance = 0, nil, e[2]
            elseif type(e[2]) == "number" and (e.horde == true or e.alliance == false) then e.horde, e.alliance = nil, 0 end
            if type(e.horde) == "boolean" then e.horde = nil end
            if type(e.alliance) == "boolean" then e.alliance = nil end
            local id = e[2]
            local v
            if type(id) == "number" then
                v = e.alliance and ("{" .. id .. "," .. e.alliance .. "}") or tostring(id)
                if id > 0 then refs[kind][id] = true end
                if e.alliance and e.alliance > 0 then refs[kind][e.alliance] = true end
            elseif id == nil and (e.horde or e.alliance) then
                v = "{" .. (e.horde or e.alliance) .. "," .. (e.alliance or e.horde) .. "}"
                refs[kind][e.horde or e.alliance] = true; refs[kind][e.alliance or e.horde] = true
            end
            if v then rows[#rows + 1] = { pos = e[1] or 0, v = v } end
        end
    end
    table.sort(rows, function(a, b) return a.pos < b.pos end)
    local o = {}
    for _, r in ipairs(rows) do o[#o + 1] = r.v end
    return o
end

local DIFF_ORDER = { n = 1, h = 2, horde = 3, alliance = 4 }
local function Row(boss, min, instTable)
    local parts = { q(strip(boss.name) or "?") }
    local npc = boss.npcID
    if type(npc) == "table" then npc = npc[1] end
    if type(npc) == "number" then parts[#parts + 1] = "npc = " .. npc end
    if boss.specialType then parts[#parts + 1] = "special = " .. q(boss.specialType) end
    if boss.ExtraList then parts[#parts + 1] = "extra = true" end
    if min then parts[#parts + 1] = "expansion = " .. (min - 1) end
    local ph = boss.ContentPhaseBC
    if ph then parts[#parts + 1] = "phase = " .. ph end
    local tt = boss.TableType or instTable
    local kind = (tt == "tt:Set") and "set" or (tt == "tt:Profession") and "craft" or "item"
    if kind == "set" then parts[#parts + 1] = "set = true" end
    if kind == "craft" then parts[#parts + 1] = "craft = true" end
    local diffs = {}
    for k, v in pairs(boss) do
        if type(k) == "table" and k.diff and type(v) == "table" then
            local items = ItemsOf(v, kind)
            if #items > 0 then diffs[#diffs + 1] = { DiffKey(k), items } end
        end
    end
    if #diffs == 0 then return nil end
    table.sort(diffs, function(a, b) return (DIFF_ORDER[a[1]] or 9) < (DIFF_ORDER[b[1]] or 9) or ((DIFF_ORDER[a[1]] or 9) == (DIFF_ORDER[b[1]] or 9) and a[1] < b[1]) end)
    for _, d in ipairs(diffs) do
        local key = d[1]:match("^[%a_][%w_]*$") and d[1] or ("[" .. q(d[1]) .. "]")
        parts[#parts + 1] = key .. " = { " .. table.concat(d[2], ", ") .. " }"
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function Names(key)
    local n = key:gsub("BCC?$", ""):gsub("Wrath$", ""):gsub("PvP$", "")
    n = n:gsub("(%l)(%u)", "%1 %2"):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
    n = n:gsub(" Of ", " of "):gsub(" The ", " the "):gsub("^Arena S ", "Arena Season ")
    return n
end
local NAME_FIX = {
    Ragefire = "Ragefire Chasm", WorldBosses = "World Bosses", WorldBossesBC = "World Bosses",
    TheRuinsofAhnQiraj = "Ruins of Ahn'Qiraj", TheTempleofAhnQiraj = "Temple of Ahn'Qiraj",
    Onyxia = "Onyxia's Lair", ["TheTempleOfAtal'Hakkar"] = "Sunken Temple",
    ScarletMonasteryGraveyard = "Scarlet Monastery: Graveyard", ScarletMonasteryLibrary = "Scarlet Monastery: Library",
    ScarletMonasteryArmory = "Scarlet Monastery: Armory", ScarletMonasteryCathedral = "Scarlet Monastery: Cathedral",
    DireMaulEast = "Dire Maul: East", DireMaulWest = "Dire Maul: West", DireMaulNorth = "Dire Maul: North",
    MagtheridonsLair = "Magtheridon's Lair", GruulsLair = "Gruul's Lair", TempestKeep = "Tempest Keep: The Eye",
    MagistersTerrace = "Magisters' Terrace", HyjalSummit = "Hyjal Summit", ZulAman = "Zul'Aman",
    AlteracValley = "Alterac Valley", WarsongGulch = "Warsong Gulch", ArathiBasin = "Arathi Basin",
    PvPMounts = "Mounts", PvPMountsBCC = "Mounts", PvPMountsWrath = "Mounts", HonorSetBCC = "Honor",
    ReputationSetBCC = "Reputation", ClassSets = "Class Sets", RoguePoisons = "Poisons", RoguePoisonsBC = "Poisons",
    FirstAid = "First Aid", FirstAidBC = "First Aid", FirstAidWrath = "First Aid",
    HellfirePeninsulaPvP = "Hellfire Peninsula", NagrandPvP = "Nagrand", TerokkarPvP = "Terokkar Forest",
    ZangarmarshPvP = "Zangarmarsh", TheMaghar = "The Mag'har", Ogrila = "Ogri'la", TheShatar = "The Sha'tar",
    ShatariSkyguard = "Sha'tari Skyguard", TheKaluak = "The Kalu'ak",
    KnightsoftheEbonBlade = "Knights of the Ebon Blade", TheSonsofHodir = "The Sons of Hodir",
    ArenaS1PvP = "Arena Season 1", ArenaS2PvP = "Arena Season 2", ArenaS3PvP = "Arena Season 3",
    ArenaS4PvP = "Arena Season 4", ArenaS5PvP = "Arena Season 5", ArenaS6PvP = "Arena Season 6",
    ArenaS7PvP = "Arena Season 7", ArenaS8PvP = "Arena Season 8",
    Darkmoon = "Darkmoon Faire", Legendarys = "Legendaries", LegendarysBC = "Legendaries",
    BadgeofJustice = "Badge of Justice", BadgeofJustice4 = "Badge of Justice (Phase 4)",
    BadgeofJusticeP5 = "Badge of Justice (Phase 5)", BCCSunmote = "Sunmote (Isle of Quel'Danas)",
    ZGSets = "Zul'Gurub Sets", AQSets = "Ahn'Qiraj Sets", MiscSets = "Other Sets",
}
local KINDS = {
    Dungeons = "dungeon", ["10 Raids"] = "raid", ["25 Raids"] = "raid", ["20 Raids"] = "raid", ["40 Raids"] = "raid",
    Professions = "profession", ["Gathering Professions"] = "gathering", ["Secondary Professions"] = "secondary",
    ["Class Professions"] = "class", Factions = "faction", ["Secondary factions"] = "minor",
    Horde = "faction", Alliance = "faction", Battlegrounds = "battleground", Arena = "arena",
    ["Open World"] = "world", General = "general",
    Vendor = "vendor", Collections = "collection", ["World Events"] = "event", Sets = "sets",
}

local function Emit(dataset, tag)
    local lines, shared, seen = {}, {}, {}
    local function w(s) lines[#lines + 1] = s end
    local uses = {}
    for _, key in ipairs(dataset._order or {}) do
        local inst = dataset[key]
        if type(inst) == "table" and inst.items then
            for _, b in ipairs(inst.items) do if type(b) == "table" then uses[b] = (uses[b] or 0) + 1 end end
        end
    end
    local skipped = {}
    for _, key in ipairs(dataset._order or {}) do
        local inst = dataset[key]
        local content = type(inst) == "table" and inst.ContentType and inst.ContentType.content
        local kind = KINDS[content or ""]
        if kind and key ~= "DUMMY" then
            local name = NAME_FIX[key] or strip(inst.name)
            if not name or name:find("^@area") then name = Names(key) end
            local head = string.format("    { id = %q, name = %q, kind = %q", key, name, kind)
            if content == "Horde" or content == "Alliance" then head = head .. ", side = " .. q(content) end
            if inst.InstanceID then head = head .. ", instance = " .. inst.InstanceID end
            if inst.MapID then head = head .. ", area = " .. inst.MapID end
            if inst.FactionID then head = head .. ", faction = " .. inst.FactionID end
            if inst.LevelRange then head = head .. ", levels = { " .. table.concat(inst.LevelRange, ", ") .. " }" end
            if inst.ContentPhaseBC then head = head .. ", phase = " .. inst.ContentPhaseBC end
            w(head .. ", bosses = {")
            for _, boss in ipairs(inst.items or {}) do
                local min
                if type(boss) == "table" and boss.__min then min, boss = boss.__min, boss.value end
                if type(boss) == "table" then
                    if (uses[boss] or 0) > 1 then
                        if not seen[boss] then seen[boss] = true; shared[#shared + 1] = boss end
                    else
                        local r = Row(boss, min, inst.TableType)
                        if r then w("        " .. r .. ",") end
                    end
                end
            end
            w("    } },")
        elseif type(inst) == "table" then
            skipped[#skipped + 1] = key .. "(" .. tostring(content) .. ")"
        end
    end
    if #shared > 0 then
        w(string.format("    { id = %q, name = \"Shared\", kind = \"extra\", bosses = {", tag .. "Shared"))
        for _, b in ipairs(shared) do local r = Row(b); if r then w("        " .. r .. ",") end end
        w("    } },")
    end
    io.stderr:write(tag .. " skipped: " .. table.concat(skipped, " ") .. "\n")
    return lines
end

local RUNS = {
    { "dungeons", "classic", "DungeonsAndRaids", "data.lua", 2 },
    { "dungeons", "tbc", "DungeonsAndRaids", "data-tbc.lua", 2 },
    { "crafting", "classic", "Crafting", "data.lua", 2 },
    { "crafting", "tbc", "Crafting", "data-tbc.lua", 2 },
    { "crafting", "wrath", "Crafting", "data-wrath.lua", 3 },
    { "factions", "classic", "Factions", "data.lua", 2 },
    { "factions", "tbc", "Factions", "data-tbc.lua", 2 },
    { "factions", "wrath", "Factions", "data-wrath.lua", 3 },
    { "pvp", "classic", "PvP", "data.lua", 2 },
    { "pvp", "tbc", "PvP", "data-tbc.lua", 2 },
    { "pvp", "wrath", "PvP", "data-wrath.lua", 3 },
    { "collections", "classic", "Collections", "data.lua", 2 },
    { "collections", "tbc", "Collections", "data-tbc.lua", 2 },
}
for _, r in ipairs(RUNS) do
    CURRENT = r[5]
    captured = nil
    if r[1] == "crafting" then Sandboxed(dir .. "/AtlasLootClassic_Crafting/private.lua", env, "x", private) end
    Sandboxed(dir .. "/AtlasLootClassic_" .. r[3] .. "/" .. r[4], env, "AtlasLootClassic_" .. r[3], private)
    local tag = r[2] .. "_" .. r[1]
    local lines = Emit(captured, tag)
    local fh = assert(io.open(out .. "/" .. tag .. ".lua", "w"))
    fh:write(table.concat(lines, "\n"), "\n")
    fh:close()
    io.stderr:write(tag .. ": " .. #lines .. " lines\n")
end

-- Sections of a game-version data file: SECTION -> { [id] = line rest }
local function Sections(path, marker)
    local secs, cur = {}, nil
    for line in io.lines(path) do
        local sec = line:match(marker .. "%.(%u+) = {")
        if sec then cur = sec; secs[cur] = secs[cur] or {} end
        local id, rest = line:match("^%s*%[(%d+)%] = (.*)")
        if id and cur then secs[cur][tonumber(id)] = rest end
    end
    return secs
end

-- Item sets (base = Classic overlaid by TBC; wrath = Wrath's changes)
local sets = Sections(dir .. "/AtlasLootClassic/Data/ItemSet.lua", "ITEM_SET_DATA_RAW")
local function SetLine(rest)
    local items, nums = rest:match("^{ { ([%d, ]+) }, ([%d, ]+),")
    if not items then return nil end
    local n = {}
    for x in nums:gmatch("%d+") do n[#n + 1] = x end
    -- armor type, quality, item level, classes (a few sets lack the level)
    local mask = n[4] or n[3] or "0"
    local s = "{ " .. items:gsub("%s+$", "")
    if mask ~= "0" then s = s .. ", classes = " .. mask end
    local fmt, base = rest:match('AL%["(.-) %%s"%], (%d+) }')
    if fmt then s = s .. ", prefix = " .. q(fmt) .. ", base = " .. base end
    return s .. " }"
end
local function EmitSets(fh, which, ids)
    local keys = {}
    for id in pairs(ids) do keys[#keys + 1] = id end
    table.sort(keys)
    local n = 0
    for _, id in ipairs(keys) do
        local rest
        for _, sec in ipairs(which) do if sets[sec] and sets[sec][id] then rest = sets[sec][id] end end
        local line = rest and SetLine(rest)
        if line and which[1] == "WRATH" then
            local b = (sets.BCC and sets.BCC[id]) or (sets.CLASSIC and sets.CLASSIC[id])
            if b and SetLine(b) == line then line = nil end
        end
        if line then fh:write("        [" .. id .. "] = " .. line .. ",\n"); n = n + 1 end
    end
    return n
end
local fh = assert(io.open(out .. "/sets.lua", "w"))
fh:write("    base = {\n")
local nb = EmitSets(fh, { "CLASSIC", "BCC" }, refs.set)
fh:write("    },\n    wrath = {\n")
local wrathOnly = {}
for id in pairs(refs.set) do if sets.WRATH and sets.WRATH[id] then wrathOnly[id] = true end end
local nw = EmitSets(fh, { "WRATH" }, wrathOnly)
fh:write("    },\n")
fh:close()
local missing = {}
for id in pairs(refs.set) do
    local any = false
    for _, s in pairs(sets) do if s[id] then any = true end end
    if not any then missing[#missing + 1] = id end
end
io.stderr:write("sets: " .. nb .. " base, " .. nw .. " wrath, missing " .. table.concat(missing, " ") .. "\n")

-- Craft spells: { made item (or 0), profession, skill, yellow, grey, r = { reagent, count, ... }, t = recipe item }
local prof = Sections(dir .. "/AtlasLootClassic/Data/Profession.lua", "PROFESSION_DATA")
local rec = Sections(dir .. "/AtlasLootClassic/Data/Recipe.lua", "RECIPE_DATA")
local teach = {}
for _, secName in ipairs({ "CLASSIC", "BCC", "WRATH" }) do
    teach[secName] = {}
    for item, rest in pairs(rec[secName] or {}) do
        local spell = rest:match("^{ %d+, %d+, (%d+)")
        if spell then teach[secName][tonumber(spell)] = item end
    end
end
local function CraftLine(rest, spell, secs)
    local made, p, a, b, c, reag, cnt = rest:match("^{ (%w+), (%d+), (%d+), (%d+), (%d+), { ([%d, ]*) }, { ([%d, ]*) }")
    if not made then return nil end
    local r = {}
    local ids, ns = {}, {}
    for x in reag:gmatch("%d+") do ids[#ids + 1] = x end
    for x in cnt:gmatch("%d+") do ns[#ns + 1] = x end
    for i, x in ipairs(ids) do r[#r + 1] = x .. "," .. (ns[i] or 1) end
    local s = "{ " .. (made == "nil" and "0" or made) .. ", " .. p .. ", " .. a .. ", " .. b .. ", " .. c
    if #r > 0 then s = s .. ", r = { " .. table.concat(r, ", ") .. " }" end
    local t
    for _, sec in ipairs(secs) do t = teach[sec][spell] or t end
    if t then s = s .. ", t = " .. t end
    return s .. " }"
end
fh = assert(io.open(out .. "/crafts.lua", "w"))
local keys = {}
for id in pairs(refs.craft) do keys[#keys + 1] = id end
table.sort(keys)
local nc, ncw, miss = 0, 0, 0
fh:write("    base = {\n")
for _, id in ipairs(keys) do
    local rest = (prof.BCC and prof.BCC[id]) or (prof.CLASSIC and prof.CLASSIC[id])
    local line = rest and CraftLine(rest, id, { "CLASSIC", "BCC" })
    if line then fh:write("        [" .. id .. "] = " .. line .. ",\n"); nc = nc + 1 end
end
fh:write("    },\n    wrath = {\n")
for _, id in ipairs(keys) do
    local rest = prof.WRATH and prof.WRATH[id]
    local line = rest and CraftLine(rest, id, { "CLASSIC", "BCC", "WRATH" })
    local baseRest = (prof.BCC and prof.BCC[id]) or (prof.CLASSIC and prof.CLASSIC[id])
    if line and baseRest and CraftLine(baseRest, id, { "CLASSIC", "BCC" }) == line then line = nil end
    if line then fh:write("        [" .. id .. "] = " .. line .. ",\n"); ncw = ncw + 1 end
    if not rest and not (prof.BCC and prof.BCC[id]) and not (prof.CLASSIC and prof.CLASSIC[id]) then miss = miss + 1 end
end
fh:write("    },\n")
fh:close()
io.stderr:write("crafts: " .. nc .. " base, " .. ncw .. " wrath, " .. miss .. " missing\n")
