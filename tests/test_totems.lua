-- Shaman totem button: sets, the cast sequence (Air, Water, Earth, Fire),
-- reset when totems are gone, and the set editor.
-- Usage: lua5.1 test_totems.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

function W.Frame:RegisterForClicks(...) self._clicks = { ... } end
function W.Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function W.Frame:GetAttribute(k) return self._attr and self._attr[k] end
local moving = 0
function W.Frame:StartMoving() moving = moving + 1 end
local allFrames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); allFrames[#allFrames + 1] = f; return f end

local book = {}
env.GetSpellBookItemName = function(i) return book[i] end
env.GetSpellBookItemTexture = function(i) return "Interface\\Icons\\" .. (book[i] or "?"):gsub("%W", "") end
env.GetSpellInfo = function() return nil end
local combat = false
env.InCombatLockdown = function() return combat end
local keyDown = true
env.GetCVarBool = function() return keyDown end
local shift = false
env.IsShiftKeyDown = function() return shift end
local totems = { false, false, false, false }   -- slot 1 fire .. 4 air
env.GetTotemInfo = function(slot)
    if totems[slot] then return true, totems[slot], 0, 120, "icon" end
    return false, "", 0, 0, ""
end
env.UnitClass = function() return "Shaman", "SHAMAN" end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua",
                     "Modules/ClassGeneral.lua", "Modules/ClassWarlock.lua", "Modules/ClassMage.lua",
                     "Modules/ClassShaman.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Shaman, Flyout = WM.modules.ClassTools, WM.modules.ClassShaman, WM.Flyout
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function Seq(prefix)
    local text = env.WM_TotemAnchor:GetAttribute("macrotext") or ""
    local reset, list = text:match("^/castsequence (reset=%S+) (.*)$")
    return list, reset, text
end

-- A level-60ish shaman: no Wrath of Air, no Totem of Wrath, no Windfury yet
book = { "Grace of Air Totem", "Mana Spring Totem", "Healing Stream Totem", "Strength of Earth Totem",
         "Stoneskin Totem", "Tremor Totem", "Searing Totem", "Lightning Bolt" }
Shaman:Initialize()
W.runTimers()
local a = env.WM_TotemAnchor
local fly = Shaman.flyout

-- ---- The button ----
check("totem button created and shown", a ~= nil and a:IsShown())
check("anchor is a secure button", a._template == "SecureActionButtonTemplate")
check("anchor casts a macro", a:GetAttribute("type") == "macro")
check("right-click doesn't cast", a:GetAttribute("type2") == "stop")
check("shift-click doesn't cast (it's for dragging)", a:GetAttribute("shift-type1") == "stop")
check("OnClick left to the secure template", a._scripts.OnClick == nil)
check("clicks: the casting half of left, plus right-up",
    a._clicks[1] == "LeftButtonDown" and a._clicks[2] == "RightButtonUp")
keyDown = false
Shaman:ApplyMacro()
check("cast-on-release client registers left-up", a._clicks[1] == "LeftButtonUp")
keyDown = true
Shaman:ApplyMacro()

-- ---- The sequence ----
local list, reset = Seq()
check("Melee set: Air, Water, Earth, Fire, fire last",
    list == "Grace of Air Totem, Mana Spring Totem, Strength of Earth Totem, Searing Totem")
check("sequence resets after combat and on ctrl", reset and reset:find("^reset=combat/ctrl/%d+$") ~= nil)
check("anchor icon: the set's air totem", a.icon._texture == "Interface\\Icons\\GraceofAirTotem")
check("anchor label names the set", a.label:GetText() == "Melee")

-- Learning Windfury switches the premade to it
book[#book + 1] = "Windfury Totem"
Shaman:Refresh()
check("premade prefers Windfury once known", (Seq()):find("^Windfury Totem, ") ~= nil)

-- Caster: Totem of Wrath falls back to Searing; no Wrath of Air or Tranquil Air -> no air
Shaman:SelectSet(2)
check("caster without Wrath of Air drops no air totem",
    Seq() == "Mana Spring Totem, Stoneskin Totem, Searing Totem")
book[#book + 1] = "Totem of Wrath"
book[#book + 1] = "Wrath of Air Totem"
Shaman:Refresh()
check("caster with the talent ends on Totem of Wrath",
    Seq() == "Wrath of Air Totem, Mana Spring Totem, Stoneskin Totem, Totem of Wrath")
check("caster icon: its fire totem", a.icon._texture == "Interface\\Icons\\TotemofWrath")

-- ---- Picking a set from the flyout ----
W.fire(a, "OnEnter")
check("hover opens the set flyout", fly.open and fly.count == 4)
local b3 = env.WM_TotemSetBtn3
check("set entries don't cast", b3:GetAttribute("type") == nil and b3:GetAttribute("spell") == nil)
check("set entry tooltip lists its totems", b3.tooltipLines[1] == "Healer"
    and b3.tooltipLines[3] == "Water: Healing Stream Totem")
W.fire(b3, "PostClick", "LeftButton")
check("clicking a set selects it", env.ShamanToolsDB.selected == 3)
check("and closes the flyout", not fly.open and not b3:IsShown())
check("healer sequence", Seq() == "Wrath of Air Totem, Healing Stream Totem, Stoneskin Totem, Searing Totem")
check("label follows the set", a.label:GetText() == "Healer")
W.fire(a, "OnLeave")

-- Tooltip still works in combat; flyout doesn't open
combat = true
fly:HideButtons()   -- no-op in combat
W.fire(a, "OnEnter")
check("no flyout in combat", not fly.open)
check("set can't change in combat", (function() Shaman:SelectSet(1); return env.ShamanToolsDB.selected == 3 end)())
combat = false

-- ---- Reset when the totems are gone ----
local _, r0 = Seq()
totems = { "Searing Totem", false, false, false }
Shaman:OnTotemUpdate()
check("dropping totems doesn't reset", select(2, Seq()) == r0)
totems = { "Searing Totem", "Stoneskin Totem", false, false }
Shaman:OnTotemUpdate()
totems = { false, "Stoneskin Totem", false, false }
Shaman:OnTotemUpdate()
check("one totem gone isn't a reset", select(2, Seq()) == r0)
totems = { false, false, false, false }
Shaman:OnTotemUpdate()
local _, r1 = Seq()
check("all totems gone starts the sequence again", r1 ~= r0)
check("same totems after the reset", Seq() == "Wrath of Air Totem, Healing Stream Totem, Stoneskin Totem, Searing Totem")
Shaman:OnTotemUpdate()
check("staying empty doesn't keep resetting", select(2, Seq()) == r1)

-- In combat the macro can't change: it waits for combat to end
totems = { "Searing Totem", false, false, false }
Shaman:OnTotemUpdate()
combat = true
totems = { false, false, false, false }
Shaman:OnTotemUpdate()
check("in combat: reset waits", select(2, Seq()) == r1 and Shaman:IsPendingApply())
combat = false
local shamanEvents
for _, f in ipairs(allFrames) do
    local h = f._scripts.OnEvent
    if h and debug.getinfo(h, "S").source:find("ClassShaman", 1, true) then shamanEvents = f end
end
W.fire(shamanEvents, "OnEvent", "PLAYER_REGEN_ENABLED")
check("applied when combat ends", select(2, Seq()) ~= r1 and not Shaman:IsPendingApply())
W.fire(shamanEvents, "OnEvent", "PLAYER_TOTEM_UPDATE")   -- routed, no error
check("totem event routed", true)

-- ---- Dragging ----
moving = 0
W.fire(a, "OnDragStart")
check("plain drag doesn't move (a press casts)", moving == 0)
shift = true
W.fire(a, "OnDragStart")
W.fire(a, "OnDragStop")
shift = false
check("shift-drag moves it", moving == 1)

-- ---- The editor ----
W.fire(a, "PostClick", "RightButton")
local ed = env.WM_TotemSetsFrame
check("right-click opens the set editor", ed ~= nil and ed:IsShown())
local function InEditor(f)
    while f do if f == ed then return true end; f = f._parent end
end
local dds = {}
for _, f in ipairs(allFrames) do
    if f._template == "UIDropDownMenuTemplate" and InEditor(f) then dds[#dds + 1] = f end
end
check("four element dropdowns per set", #dds == 16)
-- dds[9..12] are set 3 (Healer): Air, Water, Earth, Fire
local items = W.openMenu(dds[12])
check("fire menu: auto, none, then known fire totems", items[1].text == "Auto (Searing Totem)"
    and items[2].text == "None" and items[3].text == "Totem of Wrath" and items[4].text == "Searing Totem")
items[3].func()
check("choosing a totem rebuilds the sequence", (Seq()):find(", Totem of Wrath$") ~= nil)
items = W.openMenu(dds[9])
items[2].func()   -- Air: None
check("None leaves that element out", Seq() == "Healing Stream Totem, Stoneskin Totem, Totem of Wrath")
check("dropdown shows the choice", dds[9]._ddText == "None")
items = W.openMenu(dds[9])
items[1].func()   -- back to Auto
check("Auto goes back to the premade", env.ShamanToolsDB.sets[3].AIR == nil
    and (Seq()):find("^Wrath of Air Totem, ") ~= nil)

-- Renaming
local nameBox
for _, f in ipairs(allFrames) do
    if f._template == "InputBoxTemplate" and InEditor(f) and f:GetText() == "Healer" then nameBox = f end
end
nameBox:SetText("Raid heals")
nameBox:SetFocus()
nameBox:ClearFocus()
check("rename saved and shown on the button", env.ShamanToolsDB.sets[3].name == "Raid heals"
    and a.label:GetText() == "Raid heals")

-- Restore premades
Shaman:RestorePremades()
check("restore puts the premades back", env.ShamanToolsDB.sets[3].name == "Healer"
    and env.ShamanToolsDB.sets[3].FIRE == nil and Seq():find(", Searing Totem$") ~= nil)
check("selected set kept", env.ShamanToolsDB.selected == 3)
Shaman:ToggleEditor()
check("toggle closes the editor", not ed:IsShown())

-- A set with nothing known drops nothing
for _, e in ipairs(Shaman.ELEMENTS) do env.ShamanToolsDB.sets[4][e] = "NONE" end
Shaman:SelectSet(4)
check("empty set: empty macro", select(3, Seq()) == "")
Shaman:RestorePremades()
check("Tremor set", Seq() == "Windfury Totem, Mana Spring Totem, Tremor Totem, Searing Totem")

-- ---- Options ----
env.ShamanToolsDB.setDir = "HIDDEN"
Shaman:Refresh()
check("Hidden: no set flyout", fly.count == 0)
check("button still casts with the flyout hidden", Seq() ~= nil)
env.ShamanToolsDB.setDir = "LEFT"
Shaman:Refresh()
local _, _, _, x = env.WM_TotemSetBtn1:GetPoint(1)
check("direction applies", fly.count == 4 and x < 0)
CT:SetEnabled("SHAMAN", "totemButton", false)
check("feature off hides the button", not a:IsShown())
CT:SetEnabled("SHAMAN", "totemButton", true)
check("feature on shows it", a:IsShown())
local inRegistry = false
for _, f in ipairs(Flyout.registry) do if f == fly then inRegistry = true end end
check("docks with the other flyout buttons", inRegistry)

-- Saved sets survive a reload's InitDB, and bad data is repaired
env.ShamanToolsDB.sets[2] = "junk"
env.ShamanToolsDB.selected = 9
Shaman:InitDB()
check("InitDB repairs sets and selection", type(env.ShamanToolsDB.sets[2]) == "table"
    and env.ShamanToolsDB.sets[2].name == "Caster" and env.ShamanToolsDB.selected == 1)

-- No GetTotemInfo on this client: no reset, no error
env.GetTotemInfo = false
check("no totem API: unknown", Shaman:AnyTotemDown() == nil)
Shaman:OnTotemUpdate()

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
