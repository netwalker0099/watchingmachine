-- Mage utility button: mana gems, armors, food/water/table.
-- Usage: lua5.1 test_mageutility.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

function W.Frame:RegisterForClicks(...) self._clicks = { ... } end
function W.Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function W.Frame:GetAttribute(k) return self._attr and self._attr[k] end
local allFrames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); allFrames[#allFrames + 1] = f; return f end

-- Spellbook in client order: ranks lowest first, groups interleaved
local book = {
    "Frost Armor", "Conjure Food", "Conjure Water", "Conjure Mana Agate",   -- 1-4
    "Frost Armor", "Conjure Water", "Ice Armor", "Conjure Mana Ruby",       -- 5-8 (rank 2s)
    "Arcane Intellect", "Conjure Food", "Conjure Water", "Molten Armor",    -- 9-12
    "Ritual of Refreshment", "Hechizo de Esmeralda", "Portal: Stormwind",   -- 13-15
}
env.GetSpellBookItemName = function(i) return book[i] end
env.GetSpellBookItemTexture = function(i) return "Interface\\Icons\\Slot" .. i end
-- A localized client: the Emerald gem has a non-English name, found by its ID
env.GetSpellInfo = function(id) if id == 27101 then return "Hechizo de Esmeralda" end end
env.InCombatLockdown = function() return false end
env.GetCVarBool = function() return true end
local tipCalls = {}
env.GameTooltip.SetSpellBookItem = function(_, index) tipCalls[#tipCalls + 1] = index end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/ClassTools.lua")
W.load("Modules/ClassFlyout.lua")
W.load("Modules/ClassMage.lua")
local WM = W.WM
local Mage, CT = WM.modules.ClassMage, WM.modules.ClassTools
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
Mage:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Pos(b) local _, _, _, x, y = b:GetPoint(1); return x, y end
local function Btn(i) return rawget(env, "WM_MageUtilityBtn" .. i) end
local step, first = 32 + 4, 36 / 2 + 4 + 32 / 2

-- ---- discovery ----
Mage:ScanSpellbook()
local function Names(group)
    local out = {}
    for _, e in ipairs(Mage:GetUtilitySpells(group)) do out[#out + 1] = e.name end
    return table.concat(out, ", ")
end
check("gems highest level first (localized Emerald found by ID)",
    Names("gems") == "Hechizo de Esmeralda, Conjure Mana Ruby, Conjure Mana Agate")
check("armors once each, highest level first", Names("armor") == "Molten Armor, Ice Armor, Frost Armor")
check("table, then water, then food", Names("food") == "Ritual of Refreshment, Conjure Water, Conjure Food")
local function Entry(group, name)
    for _, e in ipairs(Mage:GetUtilitySpells(group)) do if e.name == name then return e end end
end
check("ranked spells use their highest-rank slot", Entry("armor", "Frost Armor").index == 5
    and Entry("food", "Conjure Water").index == 11 and Entry("food", "Conjure Food").index == 10)
check("portal not picked up as a utility spell", Entry("food", "Portal: Stormwind") == nil)

-- ---- the button ----
local anchor = rawget(env, "WM_MageUtilityAnchor")
check("utility button created for a mage", anchor ~= nil)
check("utility icon is the mage class crest",
    rawget(anchor.icon, "_texture") == "Interface\\TargetingFrame\\UI-Classes-Circles"
    and rawget(anchor.icon, "_texCoord")[1] == 0.25 and rawget(anchor.icon, "_texCoord")[3] == 0)
check("portal button still there too", rawget(env, "WM_MagePortalAnchor") ~= nil)

Mage:UpdateButtons()
check("defaults: gems left, armor up, food right", env.MageToolsDB.gemDir == "LEFT"
    and env.MageToolsDB.armorDir == "UP" and env.MageToolsDB.foodDir == "RIGHT")
check("nine utility icons: 3 gems, 3 armors, 3 food", Btn(9) ~= nil and Btn(10) == nil)
local x, y = Pos(Btn(1))
check("highest gem closest to the button", Btn(1):GetAttribute("spell") == "Hechizo de Esmeralda"
    and x == -first and y == 0)
x = Pos(Btn(3))
check("lowest gem furthest out", Btn(3):GetAttribute("spell") == "Conjure Mana Agate" and x == -(first + 2 * step))
x, y = Pos(Btn(4))
check("armor line starts above the button with Molten", Btn(4):GetAttribute("spell") == "Molten Armor"
    and x == 0 and y == first)
x, y = Pos(Btn(7))
check("table first on the food line", Btn(7):GetAttribute("spell") == "Ritual of Refreshment"
    and x == first and y == 0)
check("every icon casts its spell", Btn(8):GetAttribute("type") == "spell"
    and Btn(8):GetAttribute("spell") == "Conjure Water")
check("icons from the spellbook", rawget(Btn(4).icon, "_texture") == "Interface\\Icons\\Slot12")
check("cast press registered", Btn(1)._clicks[1] == "AnyDown")
W.fire(Btn(8), "OnEnter")
check("water tooltip from its highest rank", tipCalls[#tipCalls] == 11)

-- all three the same way: one line, gems then armor then food
env.MageToolsDB.gemDir, env.MageToolsDB.armorDir, env.MageToolsDB.foodDir = "UP", "UP", "UP"
Mage:BuildUtilityFlyout()
x, y = Pos(Btn(4))
check("armors continue after the gems", Btn(4):GetAttribute("spell") == "Molten Armor"
    and x == 0 and y == first + 3 * step)
x, y = Pos(Btn(9))
check("food last on the shared line", Btn(9):GetAttribute("spell") == "Conjure Food"
    and y == first + 8 * step)
-- two share, one apart
env.MageToolsDB.foodDir = "DOWN"
Mage:BuildUtilityFlyout()
x, y = Pos(Btn(7))
check("food on its own line when it points elsewhere", x == 0 and y == -first)

-- hover expands, leaving closes
for i = 1, 9 do Btn(i):Hide() end
W.fire(anchor, "OnEnter")
check("hover shows every icon", Btn(1):IsShown() and Btn(9):IsShown())
W.fire(anchor, "OnLeave"); W.runTimers()
check("leaving closes it", not Btn(1):IsShown())

-- nothing known: tooltip says so
book = { "Arcane Intellect" }
Mage:BuildUtilityFlyout()
local said
env.GameTooltip.AddLine = function(_, t) said = (said or "") .. t .. "|" end
W.fire(anchor, "OnEnter")
check("empty button explains itself", said and said:find("No mana gem", 1, true) ~= nil)

-- switching it off hides it
CT:SetEnabled("MAGE", "utilityButton", false)
check("utility button can be switched off", not anchor:IsShown())
CT:SetEnabled("MAGE", "utilityButton", true)

-- ---- options ----
local kinds = {}
for _, f in ipairs(CT:GetFeatures("MAGE")) do kinds[f.key] = f.kind or "check" end
check("show option", kinds.utilityButton == "check")
check("direction options", kinds.gemDir == "choice" and kinds.armorDir == "choice" and kinds.foodDir == "choice")
check("no mage-only lock (the lock is shared, in General)", kinds.portalLock == nil)

local rebuilt = 0
local orig = Mage.UpdateUtilityButtonVisibility
Mage.UpdateUtilityButtonVisibility = function() rebuilt = rebuilt + 1 end
local panel = CT:CreateUI()
panel:Show()
local row
for _, f in ipairs(allFrames) do
    if rawget(f, "label") and rawget(f, "cycle") and f.label:GetText() == "Armors expand" then row = f end
end
check("Armors expand in the Mage tab", row ~= nil and row.cycle.dropdown._ddText == "Up")
W.openMenu(row.cycle.dropdown)[2].func()   -- Right
check("cycling it saves and rebuilds", env.MageToolsDB.armorDir == "RIGHT" and rebuilt == 1)
Mage.UpdateUtilityButtonVisibility = orig

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
