-- Mage portal flyout: the secure buttons must be able to cast.
-- Usage: lua5.1 test_classmage.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local templates, clicks = {}, {}
local allFrames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = realCreate(kind, name, parent, template)
    if name then templates[name] = template end
    allFrames[#allFrames + 1] = f
    return f
end
function W.Frame:RegisterForClicks(...) clicks[self:GetName() or "?"] = { ... } end
function W.Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function W.Frame:GetAttribute(k) return self._attr and self._attr[k] end

local book = { "Arcane Intellect", "Teleport: Stormwind", "Portal: Ironforge", "Teleport: Ironforge",
               "Portal: Stormwind", "Frostbolt" }
env.GetSpellBookItemName = function(i) return book[i] end
env.GetSpellInfo = function() return nil end   -- use the English prefixes
env.GetSpellBookItemTexture = function(i) return "Interface\\Icons\\Book" .. i end
local tipCalls = {}
env.GameTooltip.SetSpellBookItem = function(_, index, book) tipCalls[#tipCalls + 1] = { index, book } end
env.InCombatLockdown = function() return false end
local keyDown = true
env.GetCVarBool = function(cvar) if cvar == "ActionButtonUseKeyDown" then return keyDown end end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/ClassTools.lua")
W.load("Modules/ClassFlyout.lua")
W.load("Modules/ClassMage.lua")
local Mage = W.WM.modules.ClassMage
env.WatchingMachineDB = { theme = "Default" }
Mage:InitDB()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

Mage:CreateAnchor()
Mage:BuildFlyout()

local b1 = env.WM_MagePortalBtn1
check("flyout button created", b1 ~= nil)
check("four portal/teleport buttons", env.WM_MagePortalBtn4 ~= nil and rawget(env, "WM_MagePortalBtn5") == nil)

-- Only the secure template: nothing can override the click handler that casts
check("icon buttons are plain secure action buttons", templates.WM_MagePortalBtn1 == "SecureActionButtonTemplate")

-- Click registration follows ActionButtonUseKeyDown
check("cast-on-key-down client: registered for the down press",
    clicks.WM_MagePortalBtn1 and clicks.WM_MagePortalBtn1[1] == "AnyDown" and #clicks.WM_MagePortalBtn1 == 1)
keyDown = false
Mage:BuildFlyout()
check("cast-on-key-up setting: registered for the release",
    clicks.WM_MagePortalBtn1[1] == "AnyUp" and #clicks.WM_MagePortalBtn1 == 1)
env.GetCVarBool = false   -- the stub would otherwise answer for a missing global
check("client without the setting: release", Mage.CastClicks() == "AnyUp")

-- Each button casts its spell
check("button casts a spell", b1:GetAttribute("type") == "spell")
check("portals first, sorted", b1:GetAttribute("spell") == "Portal: Ironforge"
    and env.WM_MagePortalBtn2:GetAttribute("spell") == "Portal: Stormwind")
check("then teleports", env.WM_MagePortalBtn3:GetAttribute("spell") == "Teleport: Ironforge")
-- Spell icons from the spellbook ("Portal: Ironforge" is slot 3)
check("button shows its spell's icon", rawget(b1.icon, "_texture") == "Interface\\Icons\\Book3")
check("anchor shows the first portal's icon", rawget(env.WM_MagePortalAnchor.icon, "_texture") == "Interface\\Icons\\Book3")
W.fire(b1, "OnEnter")
check("hover shows that spell's tooltip", tipCalls[#tipCalls] and tipCalls[#tipCalls][1] == 3)
env.GameTooltip.SetSpellBookItem = function() error("not on this client") end
local named
env.GameTooltip.AddLine = function(_, text) named = text end
W.fire(env.WM_MagePortalBtn3, "OnEnter")
check("falls back to the spell name", named == "Teleport: Ironforge")

-- ---- expansion directions ----
local function Pos(b) local _, _, _, x, y = b:GetPoint(1); return x, y end
local step, first = 32 + 4, 36 / 2 + 4 + 32 / 2
check("defaults: portals left, teleports up",
    env.MageToolsDB.portalDir == "LEFT" and env.MageToolsDB.teleportDir == "UP")
local x1, y1 = Pos(env.WM_MagePortalBtn1)
local x2, y2 = Pos(env.WM_MagePortalBtn2)
local x3, y3 = Pos(env.WM_MagePortalBtn3)
check("first portal just left of the button", x1 == -first and y1 == 0)
check("second portal further left", x2 == -(first + step) and y2 == 0)
check("first teleport starts its own line upward", x3 == 0 and y3 == first)
env.MageToolsDB.portalDir, env.MageToolsDB.teleportDir = "UP", "UP"
keyDown = true
Mage:BuildFlyout()
x3, y3 = Pos(env.WM_MagePortalBtn3)
local x4, y4 = Pos(env.WM_MagePortalBtn4)
check("same direction: teleports continue after the portals", x3 == 0 and y3 == first + 2 * step
    and x4 == 0 and y4 == first + 3 * step)
check("same direction: order is portals then teleports",
    env.WM_MagePortalBtn2:GetAttribute("spell") == "Portal: Stormwind"
    and env.WM_MagePortalBtn3:GetAttribute("spell") == "Teleport: Ironforge")
env.MageToolsDB.portalDir, env.MageToolsDB.teleportDir = "RIGHT", "DOWN"
Mage:BuildFlyout()
x1, y1 = Pos(env.WM_MagePortalBtn1)
x3, y3 = Pos(env.WM_MagePortalBtn3)
check("right and down", x1 == first and y1 == 0 and x3 == 0 and y3 == -first)
env.MageToolsDB.portalDir = "SIDEWAYS"
Mage:BuildFlyout()
x1 = Pos(env.WM_MagePortalBtn1)
check("unknown saved direction falls back to the default", x1 == -first)
env.MageToolsDB.portalDir, env.MageToolsDB.teleportDir = "LEFT", "UP"
Mage:BuildFlyout()
check("no OnClick script replaces the secure handler", b1:GetScript("OnClick") == nil)

-- Forgetting a spell retires its button
book = { "Teleport: Stormwind" }
Mage:BuildFlyout()
check("leftover buttons cleared", env.WM_MagePortalBtn2:GetAttribute("spell") == nil)

-- Never rebuilt in combat
env.InCombatLockdown = function() return true end
book = { "Portal: Ironforge", "Portal: Stormwind", "Teleport: Stormwind" }
Mage:BuildFlyout()
check("no rebuild in combat", env.WM_MagePortalBtn1:GetAttribute("spell") == "Teleport: Stormwind")

-- ---- options in Class Tools ----
env.InCombatLockdown = function() return false end
local CT = W.WM.modules.ClassTools
CT:InitDB()
Mage:Initialize()
local kinds = {}
for _, f in ipairs(CT:GetFeatures("MAGE")) do kinds[f.key] = f.kind or "check" end
check("Portals expand is a choice option", kinds.portalDir == "choice")
check("Teleports expand is a choice option", kinds.teleportDir == "choice")
check("choice options aren't stored as on/off", env.ClassToolsDB.enabled.MAGE.portalDir == nil)

local rebuilt = 0
local origUpdate = Mage.UpdatePortalButtonVisibility
Mage.UpdatePortalButtonVisibility = function(...) rebuilt = rebuilt + 1 end
local panel = CT:CreateUI()
panel:Show()
local function FindCycle(labelText)
    -- pooled choice rows: label font string + cycle box
    local found
    local function walk(f)
        if type(f) ~= "table" then return end
        if rawget(f, "label") and rawget(f, "cycle") and f.label:GetText() == labelText then found = f end
    end
    for _, fr in ipairs(allFrames) do walk(fr) end
    return found
end
local row = FindCycle("Portals expand")
check("panel shows the Portals expand option", row ~= nil)
check("it's a dropdown showing the current direction", row and row.cycle.dropdown._ddText == "Left")
local items = W.openMenu(row.cycle.dropdown)
local labels = {}
for _, it in ipairs(items) do labels[#labels + 1] = it.text end
check("dropdown lists Up, Right, Down, Left, Hidden", table.concat(labels, ",") == "Up,Right,Down,Left,Hidden")
items[1].func()
check("choosing Up saves it and updates the text", env.MageToolsDB.portalDir == "UP" and row.cycle.dropdown._ddText == "Up")
check("changing it rebuilds the flyout", rebuilt >= 1)
local trow = FindCycle("Teleports expand")
check("panel shows the Teleports expand option", trow and trow.cycle.dropdown._ddText == "Up")
Mage.UpdatePortalButtonVisibility = origUpdate

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
