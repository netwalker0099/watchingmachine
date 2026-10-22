-- Game menu (Escape) button: the 2.5.6 list-built menu and the older
-- fixed-button menu. Usage: lua5.1 test_gamemenu.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

env.LOG_OUT = "Log Out"
env.hooksecurefunc = function(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local r = orig(...); fn(...); return r end
end
-- Like the client: setting an anchor point that's already set replaces it
function W.Frame:SetPoint(point, ...)
    for i, p in ipairs(self._points) do
        if p[1] == point then self._points[i] = { point, ... } return end
    end
    self._points[#self._points + 1] = { point, ... }
end
local hidden
env.HideUIPanel = function(f) hidden = f; f:Hide() end

W.load("Core.lua")
W.load("UI.lua")
W.load("GameMenu.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local toggled = 0
WM.ToggleDashboard = function() toggled = toggled + 1 end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- The 2.5.6 menu: InitButtons rebuilds a pooled list, Layout stacks it ----
env.MACROS = "Macros"
local menu = W.NewFrame("GameMenuFrame")
env.GameMenuFrame = menu
local pool = {}
menu.buttonPool = { EnumerateActive = function() local i = 0
    return function() i = i + 1; return pool[i] end end }
function menu:AddButton(text, cb)
    local b = W.NewFrame(nil, self)
    b:SetText(text); b:SetScript("OnClick", cb)
    b:SetHeight(21)
    b.layoutIndex = self.nextLayoutIndex
    self.nextLayoutIndex = self.nextLayoutIndex + 1
    pool[#pool + 1] = b
    return b
end
local LABELS = { "Options", "AddOns", "Support", "Macros", "Log Out", "Exit Game", "Return to Game" }
function menu:InitButtons()
    pool = {}
    self.nextLayoutIndex = 1
    for _, t in ipairs(LABELS) do self:AddButton(t) end
end
-- Stand-in for the vertical layout: each button under the previous one
-- (20 gap before Log Out), height to fit
function menu:Layout()
    local y = -32
    for i, b in ipairs(pool) do
        if b.layoutIndex then
            if b:GetText() == "Log Out" or b:GetText() == "Return to Game" then y = y - 20 end
            b:ClearAllPoints()
            b:SetPoint("TOP", self, "TOP", 0, y)
            y = y - 21
        end
    end
    self:SetHeight(-y + 28)
end
local function Open() menu:InitButtons(); menu:Layout() end
local function Y(b) return select(5, b:GetPoint(1)) end
local function ByText(t) for _, b in ipairs(pool) do if b:GetText() == t then return b end end end

WM:SetupGameMenuButton()
WM:SetupGameMenuButton()   -- hooks once
Open()
local b = env.WM_GameMenuButton
check("button created on the menu", b ~= nil and b:GetParent() == menu)
check("its own button, not one from the menu's pool", (function()
    for _, p in ipairs(pool) do if p == b then return false end end
    return true end)())
check("not part of the layout", b.layoutIndex == nil)
local _, rel, relPoint = b:GetPoint(1)
check("sits under Macros", rel == ByText("Macros") and relPoint == "BOTTOMLEFT")
-- Log Out was 20 + 21*4 + 32 down; now pushed one button lower
check("Log Out and below pushed down by its height", Y(ByText("Log Out")) == -(32 + 4 * 21 + 20) - 21
    and Y(ByText("Return to Game")) == -(32 + 6 * 21 + 40) - 21)
check("buttons above it stay put", Y(ByText("Macros")) == -(32 + 3 * 21))
check("menu taller by one button", menu:GetHeight() == (32 + 7 * 21 + 40 + 28) + 21)
check("shown, with the addon's name", b:IsShown() and b:GetText():find("Watching Machine", 1, true))
W.click(b)
check("click closes the menu and opens the dashboard", hidden == menu and toggled == 1)

-- Reopening: rebuilt from scratch, ours pushed in once (no creeping)
Open()
check("reopened: same button, shifted once", env.WM_GameMenuButton == b
    and Y(ByText("Log Out")) == -(32 + 4 * 21 + 20) - 21)

-- ---- ElvUI present: its button sits under Macros; ours goes under it ----
local skinned = {}
local S = { HandleButton = function(_, btn) skinned[btn] = true; btn.backdrop = W.NewFrame() end }
env.ElvUI = { { GetModule = function(_, name) return name == "Skins" and S or nil end,
    private = { skins = { blizzard = { enable = true, misc = true } } } } }
local elvBtn = W.NewFrame("ElvUI_GameMenuButton", menu)
elvBtn:SetHeight(21)
menu.ElvUI = elvBtn
-- ElvUI's own Layout hook: anchor under Macros, push the rest down 20
local layout = menu.Layout
menu.Layout = function(self)
    layout(self)
    elvBtn:ClearAllPoints()
    elvBtn:SetPoint("TOPLEFT", ByText("Macros"), "BOTTOMLEFT")
    for _, x in ipairs(pool) do
        local t = x:GetText()
        if t == "Log Out" or t == "Exit Game" or t == "Return to Game" then
            local p, r, rp, px, py = x:GetPoint(1); x:SetPoint(p, r, rp, px, py - 20)
        end
    end
end
b.wmSkinned = nil
Open()
_, rel = b:GetPoint(1)
check("with ElvUI: ours sits under ElvUI's button, not on top of it", rel == elvBtn)
check("with ElvUI: Log Out below both buttons", Y(ByText("Log Out")) == -(32 + 4 * 21 + 20) - 20 - 21)
check("with ElvUI: ElvUI's button skin applied", skinned[b] == true and b.wmSkinned)
-- ElvUI's Blizzard skins turned off: default look
env.ElvUI[1].private.skins.blizzard.misc = false
b.wmSkinned = nil
skinned[b] = nil
Open()
check("ElvUI skins off: left in the default look", not skinned[b])
env.ElvUI[1].private.skins.blizzard.misc = true
elvBtn:Hide()
Open()
_, rel = b:GetPoint(1)
check("ElvUI's button hidden: back under Macros", rel == ByText("Macros"))
elvBtn:Show()
env.ElvUI = nil
menu.ElvUI = nil
elvBtn:Hide()
menu.Layout = layout

-- No Log Out (renamed): above the last button
LABELS = { "Options", "Leave", "Return to Game" }
WM.gameMenuHooked = false
WM:SetupGameMenuButton()
Open()
_, rel = b:GetPoint(1)
check("no Log Out or Macros: under the button before the last", rel == ByText("Leave"))
check("and the last button pushed down", Y(ByText("Return to Game")) < -(32 + 2 * 21 + 20))
LABELS = { "Options", "AddOns", "Support", "Macros", "Log Out", "Exit Game", "Return to Game" }

-- Turned off in Settings
env.WatchingMachineDB.gameMenuButton = false
Open()
check("option off: hidden, nothing pushed down", not b:IsShown()
    and Y(ByText("Log Out")) == -(32 + 4 * 21 + 20))
env.WatchingMachineDB.gameMenuButton = true

-- ---- An older fixed-button menu ----
local W2 = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env2 = W2.env
env2.hooksecurefunc = env.hooksecurefunc
W2.load("Core.lua"); W2.load("UI.lua"); W2.load("GameMenu.lua")
env2.WatchingMachineDB = { theme = "Default" }
local old = W2.NewFrame("GameMenuFrame")
old:SetHeight(300)
old.InitButtons = false   -- the old menu has no list builder
env2.GameMenuFrame = old
local macros = W2.NewFrame("GameMenuButtonMacros", old)
local logout = W2.NewFrame("GameMenuButtonLogout", old)
logout:SetHeight(21)
logout:SetPoint("TOP", macros, "BOTTOM", 0, -16)
env2.GameMenuButtonLogout = logout
W2.WM:SetupGameMenuButton()
local lb = env2.WM_GameMenuButton
lb:SetHeight(21)
local _, rel = lb:GetPoint(1)
local _, lrel = logout:GetPoint(1)
check("old menu: our button under Macros", rel == macros)
check("old menu: Log Out moved under ours", lrel == lb)
check("old menu: taller by one button", old:GetHeight() > 300)
local h = old:GetHeight()
W2.fire(old, "OnShow")
check("old menu: reopening doesn't grow it again", old:GetHeight() == h)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
