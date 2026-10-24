-- Reads Attune's data and English names in a sandbox and writes the facts
-- (attunement chains: step kinds, quest / item / NPC IDs and names,
-- levels, reputation, order) in Watching Machine's own format.
-- Usage: lua5.1 attune_extract.lua <Attune dir> > out.lua
local dir = assert(arg[1])
local L = {}
local LibStub = setmetatable({}, { __call = function()
    return { NewLocale = function() return L end, GetLocale = function() return L end }
end })
local function Sandboxed(path, env)
    local f = assert(loadfile(path))
    setfenv(f, env)
    return f()
end
local env = { LibStub = LibStub, pairs = pairs, ipairs = ipairs, string = string, table = table, tostring = tostring, tonumber = tonumber }
env._G = env
Sandboxed(dir .. "/Locales/enUS.lua", env)
local names = setmetatable({}, { __index = function(_, k) return L[k] or k end })
env.AttuneLang = names
env.Attune = {}
env.Attune_Data = {}
Sandboxed(dir .. "/AttuneData.lua", env)
local D = env.Attune_Data

local function q(s) return string.format("%q", s) end

-- Which steps finish each attunement
local finish = {}
for line in io.lines(dir .. "/Attune.lua") do
    local cond, att = line:match('^%s*if (.-) and att%.attuned%["(%d+)"%] ~= 100')
    if cond and not line:match("^%s*%-%-") then
        finish[att] = finish[att] or {}
        for a, s in cond:gmatch('att%.done%["(%d+)%-(%d+)"%]') do
            if a == att then table.insert(finish[att], tonumber(s)) end
        end
    end
end

local GROUP = { RAIDS = "raid", KEYS = "key", HEROICS = "heroic", MISC = "misc" }
local KIND = { Quest = "quest", ["Pick Up"] = "pickup", ["Turn In"] = "turnin", Item = "item", Level = "level",
    Rep = "rep", Kill = "kill", Interact = "talk", Click = "use", Attune = "attune" }

local out = {}
local function w(s) out[#out + 1] = s end
w("    attunements = {")
for _, a in ipairs(D.attunes) do
    local exp = a.EXPAC == "The Burning Crusade" and 1 or 0
    local group = GROUP[(a.GROUP or ""):upper()] or "misc"
    local icon = a.ICON and a.ICON:find("^Interface\\Icons\\") and a.ICON:gsub("^Interface\\Icons\\", "") or nil
    local head = string.format("        { id = %s, name = %s, expansion = %d, group = %q", a.ID, q(a.NAME), exp, group)
    if a.FACTION ~= "Both" then head = head .. ", side = " .. q(a.FACTION) end
    if icon then head = head .. ", icon = " .. q(icon) end
    if a.GROUPSIZE then head = head .. ", size = " .. a.GROUPSIZE end
    local fin = finish[a.ID] or {}
    head = head .. ", finish = { " .. table.concat(fin, ", ") .. " }, steps = {"
    w(head)
    for _, s in ipairs(D.steps) do
        if s.ID_ATTUNE == a.ID and KIND[s.TYPE] then
            local k = KIND[s.TYPE]
            local parts = { "id = " .. s.ID, "t = " .. q(k) }
            local val = tonumber(s.ID_WOWHEAD)
            if k == "rep" then
                parts[#parts + 1] = "faction = " .. s.LOCATION
                parts[#parts + 1] = "value = " .. (val or 0)
            elseif k == "level" then
                parts[#parts + 1] = "value = " .. (val or 0)
            elseif k == "use" then
                parts[#parts + 1] = "name = " .. q(s.STEP)
            elseif k == "attune" then
                parts[#parts + 1] = "attune = " .. (val or 0)
            else
                parts[#parts + 1] = "ref = " .. (val or 0)
            end
            if s.COUNT then parts[#parts + 1] = "count = " .. s.COUNT end
            if k ~= "rep" and s.LOCATION and s.LOCATION ~= "" then parts[#parts + 1] = "zone = " .. q(s.LOCATION) end
            local f = s.FOLLOWS or "0"
            if f ~= "0" and f ~= "" then
                local any = f:find("|", 1, true) ~= nil
                local ids = {}
                for x in f:gmatch("%d+") do ids[#ids + 1] = x end
                parts[#parts + 1] = "after = { " .. table.concat(ids, ", ") .. " }"
                if any then parts[#parts + 1] = "any = true" end
            end
            if s.VALIDFROM then parts[#parts + 1] = "from = " .. s.VALIDFROM end
            if s.VALIDTO then parts[#parts + 1] = "to = " .. s.VALIDTO end
            w("            { " .. table.concat(parts, ", ") .. " },")
        end
    end
    w("        } },")
end
w("    },")
-- Quest titles (English; the client's own title is used when it has one),
-- level and group size
w("    quests = {")
local qids = {}
for id in pairs(D.quests) do qids[#qids + 1] = id end
table.sort(qids)
for _, id in ipairs(qids) do
    local t = L["Q1_" .. id]
    local d = D.quests[id]
    w(string.format("        [%d] = { %s, %d, %d },", id, q(t or ("Quest " .. id)), d[1] or 0, d[2] or 1))
end
w("    },")
-- NPC names (English), level and kind (elite / boss)
w("    npcs = {")
local nids = {}
for id in pairs(D.npcs) do nids[#nids + 1] = id end
table.sort(nids)
for _, id in ipairs(nids) do
    local n = D.npcs[id]
    local name = L["N1_" .. id] or n[3]
    local rank = n[2] or ""
    w(string.format("        [%d] = { %s, %s%s },", id, q(name), q(tostring(n[1])), rank ~= "" and (", " .. q(rank)) or ""))
end
w("    },")
print(table.concat(out, "\n"))
