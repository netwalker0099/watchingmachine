-- Paladin: Righteous Fury warning for Protection paladins.
-- Usage: lua5.1 test_paladin.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 100
env.GetTime = function() return now end
env.UnitClass = function() return "Paladin", "PALADIN" end
local buffs = {}
env.UnitBuff = function(_, i) return buffs[i] end
local dead = false
env.UnitIsDeadOrGhost = function() return dead end
local known = { [25780] = true }
env.IsPlayerSpell = function(id) return known[id] or false end
env.IsSpellKnown = false
env.GetSpellInfo = function(id) if id == 25780 then return "Righteous Fury" end end
local talents = { 0, 0, 0 }
env.GetNumTalents = function() return 1 end
env.GetTalentInfo = function(tab) return "T", "i", 1, 1, talents[tab] end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/ClassTools.lua", "Modules/ClassPaladin.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Pal = WM.modules.ClassTools, WM.modules.ClassPaladin
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
Pal:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Alert()
    CT:CreateAlertFrame()
    CT:RunMonitors()
    return CT:GetActiveAlertCount() == 1
end
local function Respec(t) talents = t; Pal:InvalidateSpec() end

check("feature registered, on by default", CT:IsEnabled("PALADIN", "fury"))
local line = CT:CreateAlertFrame().lines[1]

Respec({ 0, 0, 0 })
check("no talents: not Protection, no warning", not Alert())
Respec({ 5, 30, 26 })
check("most points in Protection: warns without Righteous Fury", Alert())
check("warning text and icon", line.text:GetText() == "Righteous Fury is missing"
    and line.icon._texture == "Interface\\Icons\\Spell_Holy_SealOfFury")
buffs = { "Blessing of Kings", "Righteous Fury" }
check("Righteous Fury up: cleared", not Alert())
buffs = {}
check("falls off: warns again", Alert())

Respec({ 0, 10, 41 })
check("Retribution: no warning", not Alert())
Respec({ 41, 20, 0 })
check("Holy: no warning", not Alert())
known[20925] = true
Pal:InvalidateSpec()
check("knowing Holy Shield counts as Protection", Alert())
known[20925] = nil
Respec({ 0, 30, 20 })

dead = true
check("no warning while dead", not Alert())
dead = false

known[25780] = nil
check("Righteous Fury not learned yet: no warning", not Alert())
known[25780] = true

CT:SetEnabled("PALADIN", "fury", false)
check("option off: no warning", not Alert())
CT:SetEnabled("PALADIN", "fury", true)
check("option on: back", Alert())

-- Cached for a few seconds, refreshed after
talents = { 0, 0, 41 }
check("spec is cached between ticks", Alert())
now = now + 6
check("and re-read after the cache expires", not Alert())

env.UnitClass = function() return "Warrior", "WARRIOR" end
CT:ClearAlert("pal_fury")
check("other classes: nothing", not Alert())

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
