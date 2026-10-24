-- Reads GTFO's spell lists (the files a TBC client loads) in a sandbox and
-- writes the facts in Watching Machine's own format.
-- Usage: lua5.1 gtfo_extract.lua <GTFO dir> > out.lua
local dir = assert(arg[1])
local FILES = { "GTFO_Spells_GenericClassic", "GTFO_Spells_Vanilla", "GTFO_Spells_Classic", "GTFO_Spells_BC",
    "GTFO_Spells_Special", "GTFO_Fail_Vanilla", "GTFO_Fail_BC", "GTFO_FF_BC" }
local GTFO = { SpellID = {}, FFSpellID = {}, MobID = {}, BurningCrusadeMode = true, ClassicMode = false,
    IgnoreSpellCategory = {} }
local env = { GTFO = GTFO, pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, string = string, table = table,
    GTFOLocal = setmetatable({}, { __index = function(_, k) return k end }) }
env._G = env
local desc = {}
for _, f in ipairs(FILES) do
    local path = dir .. "/Spells/" .. f .. ".lua"
    local fn = assert(loadfile(path))
    setfenv(fn, env)
    fn()
    local cur
    for line in io.lines(path) do
        local id = line:match('SpellID%["(%d+)"%]')
        if id then cur = id end
        local d = line:match('desc = "(.-)"')
        if d and cur and not desc[cur] then desc[cur] = d end
    end
end
local function q(s) return string.format("%q", s) end
local function Emit(t, name)
    local ids = {}
    for id, e in pairs(t) do if not e.test and tonumber(id) then ids[#ids + 1] = tonumber(id) end end
    table.sort(ids)
    print("    " .. name .. " = {")
    for _, id in ipairs(ids) do
        local e = t[tostring(id)]
        local p = { "s = " .. (e.sound or 1) }
        if e.tankSound then p[#p + 1] = "tank = " .. e.tankSound end
        if e.soundHeroic then p[#p + 1] = "heroic = " .. e.soundHeroic end
        if e.tankSoundHeroic then p[#p + 1] = "tankHeroic = " .. e.tankSoundHeroic end
        if e.applicationOnly then p[#p + 1] = "aura = true" end
        if e.ignoreApplication then p[#p + 1] = "noAura = true" end
        if e.trivialLevel then p[#p + 1] = "level = " .. e.trivialLevel end
        if e.trivialPercent then p[#p + 1] = "pct = " .. e.trivialPercent end
        if e.alwaysAlert then p[#p + 1] = "always = true" end
        if e.damageMinimum then p[#p + 1] = "min = " .. e.damageMinimum end
        if e.minimumStacks then p[#p + 1] = "stacks = " .. e.minimumStacks end
        if e.ignoreSelfInflicted then p[#p + 1] = "notSelf = true" end
        if e.casterOnly then p[#p + 1] = "caster = true" end
        if e.meleeOnly then p[#p + 1] = "melee = true" end
        if e.ignorePeriodic then p[#p + 1] = "noPeriodic = true" end
        if e.negatingBuffSpellID then p[#p + 1] = "unlessBuff = " .. e.negatingBuffSpellID end
        if e.negatingDebuffSpellID then p[#p + 1] = "unlessDebuff = " .. e.negatingDebuffSpellID end
        if e.affirmingDebuffSpellID then p[#p + 1] = "onlyDebuff = " .. e.affirmingDebuffSpellID end
        if e.specificMobs then
            local m = {}
            for _, x in ipairs(e.specificMobs) do m[#m + 1] = tostring(tonumber(x) or x) end
            p[#p + 1] = "mobs = { " .. table.concat(m, ", ") .. " }"
        end
        if desc[tostring(id)] then p[#p + 1] = "d = " .. q(desc[tostring(id)]) end
        print("        [" .. id .. "] = { " .. table.concat(p, ", ") .. " },")
    end
    print("    },")
    io.stderr:write(name .. ": " .. #ids .. "\n")
end
Emit(GTFO.SpellID, "spells")
Emit(GTFO.FFSpellID, "friendly")
