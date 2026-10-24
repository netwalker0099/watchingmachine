-- Game menu (Escape) button: a button of our own just below the menu,
-- shown and hidden with it, that changes nothing in the menu (an addon
-- taking part in building the menu can stop its Log Out button working).
-- Usage: lua5.1 test_gamemenu.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local secureHooks = 0
env.hooksecurefunc = function() secureHooks = secureHooks + 1 end
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

-- A menu with its own buttons, laid out by the game
local menu = W.NewFrame("GameMenuFrame")
env.GameMenuFrame = menu
menu:SetHeight(250)
local logout = W.NewFrame(nil, menu)
logout:SetText("Log Out")
logout:SetPoint("TOP", menu, "TOP", 0, -140)
menu.InitButtons = function() end
menu.Layout = function() end
menu:Hide()

WM:SetupGameMenuButton()
WM:SetupGameMenuButton()   -- once
check("no hooks on how the menu builds or lays itself out", secureHooks == 0)
check("watches the menu opening and closing", #(menu._hooks.OnShow or {}) == 1 and #(menu._hooks.OnHide or {}) == 1)

menu:Show()
local b = env.WM_GameMenuButton
check("a button when the menu opens", b and b:IsShown())
check("not inside the menu", b:GetParent() == env.UIParent)
local point, rel, relPoint = b:GetPoint(1)
check("just below the menu", point == "TOP" and rel == menu and relPoint == "BOTTOM")
check("the menu's own buttons untouched", #logout._points == 1 and select(5, logout:GetPoint(1)) == -140)
check("the menu isn't resized", menu:GetHeight() == 250)

-- Click: the menu closes, the dashboard opens
b._scripts.OnClick(b)
check("click: the menu closes", hidden == menu and not menu:IsShown())
check("... the dashboard opens", toggled == 1)
check("... and the button goes with the menu", not b:IsShown())

-- Off: hidden; and, set up off, the menu isn't watched at all
env.WatchingMachineDB.gameMenuButton = false
menu:Show()
check("off: not shown", not b:IsShown())
menu:Hide()
WM.gameMenuHooked = nil
local menu2 = W.NewFrame("GameMenuFrame")
env.GameMenuFrame = menu2
WM:SetupGameMenuButton()
check("set up while off: the menu isn't touched", not menu2._hooks.OnShow and not WM.gameMenuHooked)
env.WatchingMachineDB.gameMenuButton = true
env.GameMenuFrame = menu
menu:Show()
check("back on: shown with the menu", b:IsShown())

-- ElvUI: takes its button skin
WM.gameMenuHooked = nil
local skinned
env.ElvUI = { { private = { skins = { blizzard = { enable = true, misc = true } } },
    GetModule = function() return { HandleButton = function(_, btn) skinned = btn end } end } }
local plain = W.NewFrame()
WM.GameMenuElvSkin(plain)
check("ElvUI skin applied", skinned == plain and plain.wmSkinned)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
