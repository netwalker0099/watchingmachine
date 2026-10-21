-- Mage portal flyout: the secure buttons must be able to cast.
-- Usage: lua5.1 test_classmage.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local templates, clicks = {}, {}
local realCreate = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = realCreate(kind, name, parent, template)
    if name then templates[name] = template end
    return f
end
function W.Frame:RegisterForClicks(...) clicks[self:GetName() or "?"] = { ... } end
function W.Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function W.Frame:GetAttribute(k) return self._attr and self._attr[k] end

local book = { "Arcane Intellect", "Teleport: Stormwind", "Portal: Ironforge", "Teleport: Ironforge",
               "Portal: Stormwind", "Frostbolt" }
env.GetSpellBookItemName = function(i) return book[i] end
env.GetSpellInfo = function() return nil end   -- use the English prefixes
env.InCombatLockdown = function() return false end
local keyDown = true
env.GetCVarBool = function(cvar) if cvar == "ActionButtonUseKeyDown" then return keyDown end end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/ClassTools.lua")
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

-- Template order: later templates override earlier ones, so the secure
-- one (whose click handler casts) must come last
local t = templates.WM_MagePortalBtn1 or ""
local secureAt = t:find("SecureActionButtonTemplate", 1, true)
local panelAt = t:find("UIPanelButtonTemplate", 1, true)
check("uses SecureActionButtonTemplate", secureAt ~= nil)
check("secure template listed after the visual one", panelAt and secureAt and secureAt > panelAt)

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
check("label drops the prefix", b1:GetText():find("Ironforge", 1, true) and not b1:GetText():find("Portal:", 1, true))
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

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
