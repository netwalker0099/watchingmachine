-- Shared flyout engine: Hidden groups, open on hover / click, docking,
-- lock, and the warlock button. Usage: lua5.1 test_flyout.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

function W.Frame:RegisterForClicks(...) self._clicks = { ... } end
function W.Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function W.Frame:GetAttribute(k) return self._attr and self._attr[k] end
local moving = {}
function W.Frame:StartMoving() moving[#moving + 1] = self end
local centers = {}
function W.Frame:GetCenter() local c = centers[self]; if c then return c[1], c[2] end end
local allFrames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); allFrames[#allFrames + 1] = f; return f end

local book = {}
env.GetSpellBookItemName = function(i) return book[i] end
env.GetSpellBookItemTexture = function(i) return "Interface\\Icons\\Slot" .. i end
env.GetSpellInfo = function() return nil end
local combat = false
env.InCombatLockdown = function() return combat end
env.GetCVarBool = function() return true end
local shards = 7
env.C_Item = { GetItemCount = function(id) if id == 6265 then return shards end; return 0 end }

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua",
                     "Modules/ClassGeneral.lua", "Modules/ClassWarlock.lua", "Modules/ClassMage.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Mage, Lock, Gen = WM.modules.ClassTools, WM.modules.ClassMage, WM.modules.ClassWarlock, WM.modules.ClassGeneral
local Flyout = WM.Flyout
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Pos(b) local _, rel, _, x, y = b:GetPoint(1); return x, y, rel end
local first, step = 36 / 2 + 4 + 32 / 2, 32 + 4

-- ================= MAGE (Hidden, open modes, docking) =================
env.UnitClass = function() return "Mage", "MAGE" end
book = { "Portal: Ironforge", "Portal: Stormwind", "Teleport: Ironforge", "Conjure Water", "Molten Armor" }
Gen:Initialize()
Mage:Initialize()
Mage:UpdateButtons()
local portal, utility = Mage.portalFlyout, Mage.utilityFlyout
local function PBtn(i) return rawget(env, "WM_MagePortalBtn" .. i) end

-- ---- Hidden ----
check("both portals and the teleport shown by default", portal.count == 3)
env.MageToolsDB.portalDir = "HIDDEN"
Mage:BuildFlyout()
check("portals hidden: only the teleport", portal.count == 1 and PBtn(1):GetAttribute("spell") == "Teleport: Ironforge")
local x, y = Pos(PBtn(1))
check("teleport starts right next to the button", x == 0 and y == first)
check("hidden group's buttons retired", PBtn(2):GetAttribute("spell") == nil)
env.MageToolsDB.teleportDir = "HIDDEN"
Mage:BuildFlyout()
check("all hidden: nothing shown", portal.count == 0)
local said = ""
env.GameTooltip.AddLine = function(_, t) said = said .. t .. "|" end
W.fire(portal.anchor, "OnEnter")
check("empty button mentions Hidden", said:find("Hidden", 1, true) ~= nil)
env.MageToolsDB.portalDir, env.MageToolsDB.teleportDir = "LEFT", "UP"
Mage:BuildFlyout()

-- ---- hover mode (default) ----
check("opens on hover by default", Flyout.Settings().openMode == "hover")
W.fire(portal.anchor, "OnEnter")
check("hover opens", PBtn(1):IsShown())
W.fire(portal.anchor, "OnLeave"); W.runTimers()
check("leaving closes", not PBtn(1):IsShown())

-- ---- click mode ----
Flyout.Settings().openMode = "click"
W.fire(portal.anchor, "OnEnter")
check("click mode: hovering doesn't open", not PBtn(1):IsShown())
W.click(portal.anchor)
check("click opens", PBtn(1):IsShown() and portal.open)
W.fire(portal.anchor, "OnLeave"); W.runTimers()
check("click mode: leaving doesn't close", PBtn(1):IsShown())
W.fire(PBtn(1), "PostClick")
check("picking a spell closes it", not PBtn(1):IsShown())
W.click(portal.anchor); W.click(portal.anchor)
check("a second click closes it", not PBtn(1):IsShown())
combat = true; W.click(portal.anchor); combat = false
check("never opens in combat", not PBtn(1):IsShown())
Flyout.Settings().openMode = "hover"

-- ---- docking ----
check("not docked by default", Flyout.Settings().docked == false)
local _, _, prel = Pos(portal.anchor)
local _, _, urel = Pos(utility.anchor)
check("undocked: each button at its own spot", prel == env.UIParent and urel == env.UIParent)
CT:SetEnabled("GENERAL", "flyoutDock", true)
check("dock switch saves", Flyout.Settings().docked == true)
local lead, other = Flyout.registry[1], nil
local shown = {}
for _, f in ipairs(Flyout.registry) do if f.anchor and f.anchor:IsShown() then shown[#shown + 1] = f end end
lead, other = shown[1], shown[2]
check("two mage buttons to dock", lead == portal and other == utility)
x, y, urel = Pos(utility.anchor)
check("docked: utility attached to the portal button's right", urel == portal.anchor and x == 38 and y == 0)
Flyout.Settings().dockDir = "DOWN"; Flyout.ApplyDock()
x, y, urel = Pos(utility.anchor)
check("column downwards", urel == portal.anchor and x == 0 and y == -38)
Flyout.Settings().dockDir = "LEFT"; Flyout.ApplyDock()
x = Pos(utility.anchor)
check("row right to left", x == -38)
Flyout.Settings().dockDir = "RIGHT"; Flyout.ApplyDock()

-- dragging any docked button moves the group (the lead)
moving = {}
W.fire(utility.anchor, "OnDragStart")
check("dragging the second button moves the lead", moving[1] == portal.anchor)
centers[portal.anchor] = { 500, 400 }
W.fire(utility.anchor, "OnDragStop")
check("the lead's new spot is saved", env.MageToolsDB.portalX == 500 and env.MageToolsDB.portalY == 400)
check("the other button keeps its own saved spot for undocking", env.MageToolsDB.utilityX == nil)

-- lock
CT:SetEnabled("GENERAL", "flyoutLock", true)
moving = {}
W.fire(portal.anchor, "OnDragStart")
check("locked: can't drag", #moving == 0)
CT:SetEnabled("GENERAL", "flyoutLock", false)

-- docking in combat waits
combat = true
CT:SetEnabled("GENERAL", "flyoutDock", false)
check("undock in combat is deferred", Flyout.dockPending == true)
x, y, urel = Pos(utility.anchor)
check("...buttons not moved mid-combat", urel == portal.anchor)
combat = false
local flyEvents
for _, f in ipairs(allFrames) do
    local h = f:GetScript("OnEvent")
    if h and debug.getinfo(h, "S").source:find("ClassFlyout", 1, true) then flyEvents = f end
end
W.fire(flyEvents, "OnEvent", "PLAYER_REGEN_ENABLED")
_, _, urel = Pos(utility.anchor)
check("applied when combat ends", urel == env.UIParent and not Flyout.dockPending)

-- options live in General and are dropdowns where they're choices
local kinds = {}
for _, f in ipairs(CT:GetFeatures("GENERAL")) do kinds[f.key] = f.kind or "check" end
check("General has open mode, dock, dock layout, lock", kinds.flyoutOpen == "choice" and kinds.flyoutDock == "check"
    and kinds.flyoutDockDir == "choice" and kinds.flyoutLock == "check")

-- hide the mage buttons for the warlock part
CT:SetEnabled("MAGE", "portalButton", false)
CT:SetEnabled("MAGE", "utilityButton", false)

-- ================= WARLOCK =================
env.UnitClass = function() return "Warlock", "WARLOCK" end
book = {
    "Summon Imp", "Demon Skin", "Summon Voidwalker", "Create Healthstone (Minor)",   -- 1-4
    "Summon Succubus", "Demon Skin", "Create Soulstone (Minor)", "Summon Felhunter", -- 5-8
    "Ritual of Summoning", "Demon Armor", "Create Healthstone (Major)",             -- 9-11
    "Create Soulstone (Major)", "Fel Armor", "Ritual of Souls", "Fel Domination",   -- 12-15
}
Lock:Initialize()
local wl = Lock.flyout
check("warlock button created", wl.anchor ~= nil)
Lock:UpdateButton()
local function WBtn(i) return rawget(env, "WM_WarlockBtn" .. i) end
local function Names(group)
    local t = {}
    for _, e in ipairs(Lock:GetFlyoutSpells(group)) do t[#t + 1] = e.name end
    return table.concat(t, ", ")
end
check("demons nearest first, no Felguard without the talent",
    Names("demons") == "Summon Succubus, Summon Imp, Summon Felhunter, Summon Voidwalker")
check("armors once each, best first", Names("armor") == "Fel Armor, Demon Armor, Demon Skin")
check("stones & rituals, highest stone ranks", Names("stones")
    == "Ritual of Souls, Ritual of Summoning, Create Healthstone (Major), Create Soulstone (Major)")
check("no Fel Domination", not (Names("demons") .. Names("stones")):find("Fel Domination", 1, true))
check("warlock crest icon", rawget(wl.anchor.icon, "_texture") == "Interface\\TargetingFrame\\UI-Classes-Circles"
    and rawget(wl.anchor.icon, "_texCoord")[1] == 0.7421875)
check("defaults: demons left, armor up, stones right", env.WarlockToolsDB.demonDir == "LEFT"
    and env.WarlockToolsDB.armorDir == "UP" and env.WarlockToolsDB.stoneDir == "RIGHT")
x, y = Pos(WBtn(1))
check("Succubus nearest on the demon line", WBtn(1):GetAttribute("spell") == "Summon Succubus" and x == -first)

-- shard counts on the spells that use a shard
local function BadgeFor(spell)
    for i = 1, wl.count do
        if WBtn(i):GetAttribute("spell") == spell then return WBtn(i).countText:GetText() end
    end
end
check("Succubus shows the shard count", BadgeFor("Summon Succubus") == "7")
check("Imp doesn't (no shard)", BadgeFor("Summon Imp") == "")
check("armor doesn't", BadgeFor("Fel Armor") == "")
check("Healthstone, Soulstone, Soulwell, summoning do",
    BadgeFor("Create Healthstone (Major)") == "7" and BadgeFor("Create Soulstone (Major)") == "7"
    and BadgeFor("Ritual of Souls") == "7" and BadgeFor("Ritual of Summoning") == "7")
shards = 3
W.fire(flyEvents, "OnEvent", "BAG_UPDATE")
check("shard count updates with your bags", BadgeFor("Summon Voidwalker") == "3")
combat = true; shards = 2
W.fire(flyEvents, "OnEvent", "BAG_UPDATE")
check("...even in combat", BadgeFor("Summon Felhunter") == "2")
combat = false

-- Felguard appears once talented, nearest the button
table.insert(book, "Summon Felguard")
Lock:UpdateButton()
check("Felguard first when known", Names("demons"):find("^Summon Felguard") ~= nil
    and WBtn(1):GetAttribute("spell") == "Summon Felguard")

-- Hidden works for the warlock too
env.WarlockToolsDB.demonDir = "HIDDEN"
Lock:UpdateButton()
check("demons hidden", BadgeFor("Summon Succubus") == nil and wl.count == 7)
env.WarlockToolsDB.demonDir = "LEFT"

-- options in the Warlock tab
kinds = {}
for _, f in ipairs(CT:GetFeatures("WARLOCK")) do kinds[f.key] = f.kind or "check" end
check("warlock button and its directions", kinds.warlockButton == "check" and kinds.demonDir == "choice"
    and kinds.armorDir == "choice" and kinds.stoneDir == "choice")

-- the Mage tab's dropdown and General's numeric dropdowns work through the panel
local panel = CT:CreateUI()
panel:Show()
local function DropRow(label)
    for _, f in ipairs(allFrames) do
        if rawget(f, "label") and rawget(f, "cycle") and f.label:GetText() == label and f:IsShown() then return f end
    end
end
local row = DropRow("Demons expand")
check("Demons expand is a dropdown in the Warlock tab", row and row.cycle.dropdown._ddText == "Left")
local items = W.openMenu(row.cycle.dropdown)
items[5].func()
check("choosing Hidden from the dropdown", env.WarlockToolsDB.demonDir == "HIDDEN" and wl.count == 7)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
