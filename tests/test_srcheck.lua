-- Black Temple shadow resist gear check (Debuff Tracker): gear SR read from
-- item stats and tooltips, so gems and enchants count.
-- Usage: lua5.1 test_srcheck.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/DebuffTracker.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local DT = WM.modules.DebuffTracker
DT:InitDB()
local DB = env.DebuffTrackerDB
check("check on by default", DB.srCheck == true)

-- ---- one tooltip line ----
local Line = DT.ShadowResistFromLine
check("item stat line", Line("+40 Shadow Resistance") == 40)
check("Void Sphere gem line", Line("+4 Resist All") == 4)
check("all resistances enchant", Line("+5 All Resistances") == 5)
check("to all resistances", Line("+10 to All Resistances") == 10)
check("active socket bonus", Line("Socket Bonus: +4 Shadow Resistance", 1, 1, 1) == 4)
check("grey (inactive) socket bonus ignored", Line("Socket Bonus: +4 Shadow Resistance", 0.5, 0.5, 0.5) == 0)
check("other school ignored", Line("+40 Fire Resistance") == 0)
check("nil line", Line(nil) == 0)

-- ---- equipped gear ----
local gear = {}       -- slot -> { link, stats, lines }
env.GetInventoryItemLink = function(_, slot) return gear[slot] and gear[slot].link end
env.GetItemStats = function(link)
    for _, g in pairs(gear) do if g.link == link then return g.stats end end
end
local white = { r = 1, g = 1, b = 1 }
local function Lines(...)
    local out = {}
    for _, t in ipairs({ ... }) do out[#out + 1] = { leftText = t, leftColor = white } end
    return out
end
env.C_TooltipInfo = {
    GetInventoryItem = function(_, slot)
        return gear[slot] and { lines = gear[slot].lines }
    end,
}

-- Base SR plus three Void Spheres: GetItemStats sees only the 40
gear[5] = { link = "[Chest]", stats = { RESISTANCE5_NAME = 40 },
    lines = Lines("Chest", "+40 Shadow Resistance", "+4 Resist All", "+4 Resist All", "+4 Resist All") }
-- Rings whose SR the item stats don't report at all
gear[11] = { link = "[Dark Band of Healing]", stats = {},
    lines = Lines("Dark Band of Healing", "+20 Shadow Resistance") }
gear[12] = { link = "[Dark Band of Power]", stats = {},
    lines = Lines("Dark Band of Power", "+20 Shadow Resistance") }
-- A normal piece
gear[1] = { link = "[Helm]", stats = { ITEM_MOD_STAMINA_SHORT = 30 }, lines = Lines("Helm", "+30 Stamina") }

local total, pieces, detail = DT:GetGearShadowResist()
check("gems counted on top of the item's SR", detail[1] and detail[1].slot == 5 and detail[1].sr == 52)
check("tooltip-only rings counted", total == 92 and pieces == 3)

-- No tooltip API: the item stats still work
env.C_TooltipInfo = false
total, pieces = DT:GetGearShadowResist()
check("falls back to item stats", total == 40 and pieces == 1)

-- Old-style scanning tooltip (no C_TooltipInfo)
local function FS(text, grey)
    local f = W.NewFrame()
    f:SetText(text)
    f.GetTextColor = function() if grey then return 0.5, 0.5, 0.5 end return 1, 1, 1 end
    return f
end
local tipLines = {}
W.Frame.NumLines = function() return #tipLines end
W.Frame.SetInventoryItem = function(self, _, slot)
    local g = gear[slot]
    tipLines = {}
    if slot == 5 then
        tipLines = { FS("Chest"), FS("+40 Shadow Resistance"), FS("+4 Resist All"),
            FS("Socket Bonus: +4 Shadow Resistance", true) }
    end
    for i = 1, 10 do env["WM_SRScanTooltipTextLeft" .. i] = tipLines[i] end
    return self
end
total = DT:GetGearShadowResist()
check("scanning tooltip: gem counted, grey bonus not", total == 44)

-- ---- arming and warning ----
local warned
DT.WarnShadowResist = function(_, t, p) warned = { t, p } end
env.C_TooltipInfo = {
    GetInventoryItem = function(_, slot) return gear[slot] and { lines = gear[slot].lines } end,
}
DT:ResetShadowResistCheck()
DT:CheckShadowResistGear()
check("not armed: no warning", warned == nil)
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Mother Shahraz")
check("Mother's death arms it", DT:IsShadowResistArmed())
DT:CheckShadowResistGear()
check("armed with SR gear on: warns", warned and warned[1] == 92 and warned[2] == 3)

warned = nil
DT:ResetShadowResistCheck()
DT:HandleShadowResistCombatLog("SWING_DAMAGE", "Me", "Illidari Archon")
check("engaging a trigger mob arms and warns", DT:IsShadowResistArmed() and warned ~= nil)

warned = nil
gear[5], gear[11], gear[12] = nil, nil, nil
DT:CheckShadowResistGear()
check("SR gear off: no warning", warned == nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
