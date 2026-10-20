-- UI fixes harness (Esc, theming, screen-fit heights, settings controls). Usage: lua5.1 test_ui.lua <repo>
local REPO = assert(arg[1], "repo path")

-- Fake frames: track parent, name, shown state and colours; any other
-- method is a no-op (Get* -> 0, Is* -> false, else returns self).
local Frame = {}
local NewFrame
local frameMT = { __call = function() return NewFrame() end, __index = function(t, k)
    if Frame[k] then return Frame[k] end
    if type(k) == "string" and k:find("^Get") then return function() return 0 end end
    if type(k) == "string" and k:find("^Is") then return function() return false end end
    if type(k) == "string" and k:find("^_") then return nil end
    return NewFrame()   -- callable: works as a method or as a child (.Text)
end }
function NewFrame(name, parent)
    local f = setmetatable({ _name = name, _parent = parent, _shown = true }, frameMT)
    return f
end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p) self._parent = p end
function Frame:GetName() return self._name end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsShown() return self._shown end
function Frame:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
function Frame:SetColorTexture(r, g, b, a) self._tex = { r, g, b, a } end
function Frame:CreateFontString(name) return NewFrame(name, self) end
function Frame:CreateTexture(name) return NewFrame(name, self) end
function Frame:GetText() return "" end
function Frame:SetHeight(h) self._h = h end
function Frame:GetHeight() return self._h or 0 end
function Frame:HookScript(ev, fn) self._hooks = self._hooks or {}; self._hooks[ev] = fn end
function Frame:Fire(ev) if self._hooks and self._hooks[ev] then self._hooks[ev](self) end end
function Frame:GetStringWidth() return 10 end

local env = {}
local G = setmetatable(env, { __index = function(_, k)
    local v = _G[k]; if v ~= nil then return v end
    if type(k) == "string" and k:find("DB$") then return nil end
    return NewFrame()
end })
env._G = env
env.print = function() end
env.DEFAULT_CHAT_FRAME = NewFrame()
env.UISpecialFrames = {}
env.CreateFrame = function(_, name, parent)
    local f = NewFrame(name, parent)
    if name then env[name] = f end
    return f
end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.tinsert = table.insert
env.date = os.date
env.GetTime = function() return 0 end
env.C_Timer = { After = function() end, NewTicker = function() return NewFrame() end }

local WM = {}
local function load(rel)
    local f = assert(loadfile(REPO .. "/" .. rel))
    setfenv(f, G)
    f("WatchingMachine", WM)
end
load("Core.lua")
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function count(list, v) local n = 0 for _, x in ipairs(list) do if x == v then n = n + 1 end end return n end
local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

-- Escape closes skinned panels, once per name
local p1 = env.CreateFrame("Frame", "WM_TestPanel", nil)
WM:RegisterSkinnedPanel(p1)
local p1b = env.CreateFrame("Frame", "WM_TestPanel", nil)   -- rebuilt under same name
WM:RegisterSkinnedPanel(p1b)
check("named panel registered for Esc", count(env.UISpecialFrames, "WM_TestPanel") == 1)
local anon = env.CreateFrame("Frame", nil, nil)
local before = #env.UISpecialFrames
WM:RegisterSkinnedPanel(anon)
check("unnamed panel not added to UISpecialFrames", #env.UISpecialFrames == before)
if #env.UISpecialFrames ~= before then for i, v in ipairs(env.UISpecialFrames) do print(i, tostring(v)) end end
WM:UnregisterSkinnedPanel(p1)
check("unregister drops stale panel", WM._skinnedPanels[p1] == nil and WM._skinnedPanels[p1b])

-- Theme-keyed text and textures follow a theme change
local fs = p1b:CreateFontString()
local tex = p1b:CreateTexture()
WM:ThemeText(fs, "headerColor")
WM:ThemeTexture(tex, "separatorColor")
check("header built in Default colour", same(fs._color, WM.THEMES.Default.headerColor))
env.WatchingMachineDB.theme = "ElvUI"
WM:ReskinAll()
check("header recoloured to ElvUI", same(fs._color, WM.THEMES.ElvUI.headerColor))
check("separator recoloured to ElvUI", same(tex._tex, WM.THEMES.ElvUI.separatorColor))
env.WatchingMachineDB.theme = "Default"

-- Dashboard cards are unregistered on theme change, at any nesting depth
WM:CreateDashboard()
local dash = WM.dashboard
check("dashboard created", dash ~= nil)
local scroll = env.CreateFrame("ScrollFrame", nil, dash)
local container = env.CreateFrame("Frame", nil, scroll)
local card = env.CreateFrame("Frame", nil, container)
WM:RegisterSkinnedCard(card, { 1, 1, 1 })
local outsider = env.CreateFrame("Frame", nil, env.CreateFrame("Frame", nil, nil))
WM:RegisterSkinnedCard(outsider, { 1, 1, 1 })
dash:Hide()
WM:OnThemeChanged()
check("nested dashboard card unregistered", WM._skinnedCards[card] == nil)
check("unrelated card kept", WM._skinnedCards[outsider] ~= nil)

-- OnSecurityCheckFailed hides the real dashboard and doesn't touch a nil global
WM:CreateDashboard()
WM.dashboard:Show()
local ok = pcall(WM.OnSecurityCheckFailed, WM)
check("security-failed handler runs", ok)
check("security-failed hides dashboard", not WM.dashboard:IsShown())

-- Modules with their own theme flag get the global theme first
local seen = {}
WM.modules.FakeAS = {
    OnGlobalThemeChanged = function(_, name) seen[#seen + 1] = "global:" .. name end,
    ApplyTheme = function() seen[#seen + 1] = "apply" end,
}
env.WatchingMachineDB.theme = "ElvUI"
WM:OnThemeChanged()
check("global theme passed before ApplyTheme", seen[1] == "global:ElvUI" and seen[2] == "apply")
WM.modules.FakeAS = nil

-- ArmorySnap's handler syncs its flag
load("Modules/ArmorySnap.lua")
local AS = WM.modules.ArmorySnap
AS.db = { options = { elvuiTheme = false } }
AS:OnGlobalThemeChanged("ElvUI")
check("ArmorySnap follows ElvUI", AS.db.options.elvuiTheme == true)
AS:OnGlobalThemeChanged("Default")
check("ArmorySnap follows Default", AS.db.options.elvuiTheme == false)
AS.db.options.enabled = true
env.strsplit = function(sep, s, n) local a, b = s:match("^(%S*)%s*(.*)$"); return a, b end
env.strlower, env.strtrim = string.lower, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
AS.HandleSlash("auto")
check("/as auto turns auto-scan off", AS.db.options.enabled == false)
AS.HandleSlash("auto")
check("/as auto turns it back on", AS.db.options.enabled == true)

-- Mage portal lock is a Class Tools feature kept in step with MageToolsDB
load("Modules/ClassTools.lua")
load("Modules/ClassMage.lua")
local CT, Mage = WM.modules.ClassTools, WM.modules.ClassMage
env.ClassToolsDB = nil
env.MageToolsDB = nil
CT:InitDB()
Mage:InitDB()
local lockFeature
for _, f in ipairs(CT:GetFeatures("MAGE")) do if f.key == "portalLock" then lockFeature = f end end
if not lockFeature then Mage:Initialize() end
for _, f in ipairs(CT:GetFeatures("MAGE")) do if f.key == "portalLock" then lockFeature = f end end
check("portal lock registered", lockFeature ~= nil and lockFeature.default == false)
CT:SetEnabled("MAGE", "portalLock", true)
check("ticking lock sets portalLocked", env.MageToolsDB.portalLocked == true)
CT:SetEnabled("MAGE", "portalLock", false)
check("unticking clears it", env.MageToolsDB.portalLocked == false)

-- Panels fit the screen height
env.UIParent = NewFrame("UIParent"); env.UIParent:SetHeight(768)
local tall = env.CreateFrame("Frame", "WM_TallPanel", nil)
WM:FitHeight(tall, 742, 640)
check("742 panel fits at 768 unchanged", tall:GetHeight() == 742)
env.UIParent:SetHeight(700)                 -- larger UI scale
tall:Fire("OnShow")
check("re-fits on show at a shorter screen", tall:GetHeight() == 700 - 16)
env.UIParent:SetHeight(500)
tall:Fire("OnShow")
check("never below its minimum", tall:GetHeight() == 640)
env.UIParent:SetHeight(768)
check("ScreenFitHeight caps resize bound", WM:ScreenFitHeight(800, 480) == 752)

local function src(rel) local h = assert(io.open(REPO .. "/" .. rel)); local s = h:read("*a"); h:close(); return s end
for _, rel in ipairs({ "Core.lua", "Modules/PvPTracker.lua", "Modules/DebuffTracker.lua", "Modules/KeywordMonitor.lua" }) do
    local s = src(rel)
    for w, h in s:gmatch('SetSize%((%d+), (%d+)%)') do
        check(rel .. " fixed size " .. w .. "x" .. h .. " under 700", tonumber(h) <= 700)
    end
    check(rel .. " no 800px resize bound", not s:find("SetResizeBounds%([^)]*, 800%)"))
end
check("ToggleTracker dead code removed", not src("Modules/DebuffTracker.lua"):find("ToggleTracker"))
local sp = src("Modules/ServicesParser.lua")
check("ServicesParser settings named", sp:find('CreateFrame%("Frame", "WM_ServicesParserSettings"') ~= nil)
check("ServicesParser settings clamped",
    sp:find('"WM_ServicesParserSettings".-SetClampedToScreen%(true%)') ~= nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
