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

-- ---- The 2.5.6 menu: InitButtons rebuilds a pooled, layout-ordered list ----
local menu = W.NewFrame("GameMenuFrame")
env.GameMenuFrame = menu
local pool = {}
menu.buttonPool = { EnumerateActive = function() local i = 0
    return function() i = i + 1; return pool[i] end end }
function menu:AddButton(text, cb)
    local b = W.NewFrame(nil, self)
    b:SetText(text); b:SetScript("OnClick", cb)
    b.layoutIndex = self.nextLayoutIndex
    self.nextLayoutIndex = self.nextLayoutIndex + 1
    pool[#pool + 1] = b
    return b
end
function menu:InitButtons()
    pool = {}
    self.nextLayoutIndex = 1
    for _, t in ipairs({ "Options", "AddOns", "Support", "Macros", "Log Out", "Exit Game", "Return to Game" }) do
        self:AddButton(t)
    end
end

WM:SetupGameMenuButton()
WM:SetupGameMenuButton()   -- hooks once
menu:InitButtons()
local b = env.WM_GameMenuButton
check("button created on the menu", b ~= nil and b:GetParent() == menu)
check("its own button, not one from the menu's pool", (function()
    for _, p in ipairs(pool) do if p == b then return false end end
    return true end)())
check("Blizzard's buttons keep their places", pool[5]:GetText() == "Log Out" and pool[5].layoutIndex == 5
    and pool[4].layoutIndex == 4)
check("ordered just above Log Out, below Macros", b.layoutIndex > 4 and b.layoutIndex < 5)
check("shown, with the addon's name", b:IsShown() and b:GetText():find("Watching Machine", 1, true))
W.click(b)
check("click closes the menu and opens the dashboard", hidden == menu and toggled == 1)

-- Reopening rebuilds the list; the button keeps its place and isn't duplicated
menu:InitButtons()
check("reopened: same button, same place", env.WM_GameMenuButton == b and b.layoutIndex == 4.5)

-- No Log Out (renamed): above the last button
pool = {}
function menu:InitButtons()
    pool = {}
    self.nextLayoutIndex = 1
    for _, t in ipairs({ "Options", "Leave", "Return to Game" }) do self:AddButton(t) end
end
WM.gameMenuHooked = false
WM:SetupGameMenuButton()
menu:InitButtons()
check("no Log Out found: just above Return to Game", b.layoutIndex == 2.5)

-- Turned off in Settings
env.WatchingMachineDB.gameMenuButton = false
menu:InitButtons()
check("option off: hidden and out of the layout", not b:IsShown() and b.layoutIndex == nil)
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
