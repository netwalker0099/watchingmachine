-- Logout diagnostics: blocked actions recorded (and warned about when it's
-- logging out), logout countdowns and cancels, menu button clicks, the
-- overlap check between our menu button and Log Out, the report, and
-- turning the menu button off (which stops it touching the menu at all).
-- Usage: lua5.1 test_diagnostics.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local hooks = 0
env.hooksecurefunc = function() hooks = hooks + 1 end
env.InCombatLockdown = function() return false end
env.LOG_OUT = "Log Out"
local frames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); frames[#frames + 1] = f; return f end
for _, f in ipairs({ "Core.lua", "UI.lua", "GameMenu.lua", "Diagnostics.lua" }) do W.load(f) end
local WM = W.WM
local D = WM.Diagnostics
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Said(text)
    for i = #W.printed, 1, -1 do if tostring(W.printed[i]):find(text, 1, true) then return true end end
end
-- Diagnostics' event frame: the one whose OnEvent comes from Diagnostics.lua
local evFrame
for _, f in ipairs(frames) do
    local s = f:GetScript("OnEvent")
    if s and debug.getinfo(s, "S").source:find("Diagnostics.lua", 1, true) then evFrame = f end
end
check("listens for blocked actions and logouts", evFrame ~= nil)
local function Event(...) evFrame._scripts.OnEvent(evFrame, ...) end

-- ---- Blocked actions ----
W.printed = {}
Event("ADDON_ACTION_BLOCKED", "SomeAddon", "Logout()")
local log = env.WatchingMachineDB.diag
check("blocked action recorded", #log == 1 and log[1].kind == "blocked" and log[1].text:find("Logout", 1, true)
    and log[1].text:find("SomeAddon", 1, true))
check("logging out blocked: says so in chat", Said("The game blocked Logout() and blamed SomeAddon"))
W.printed = {}
Event("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpellByName()")
check("other addons' other blocks: recorded quietly", #log == 2 and not Said("blocked"))
Event("ADDON_ACTION_FORBIDDEN", "WatchingMachine", "UseAction()")
check("anything blamed on us: said", Said("blamed Watching Machine"))

-- ---- Logout countdowns ----
Event("PLAYER_CAMPING")
Event("LOGOUT_CANCEL")
check("logout start and cancel recorded", log[#log - 1].kind == "camping" and log[#log].kind == "cancel")

-- ---- Our menu button vs Log Out ----
local menu = W.NewFrame("GameMenuFrame")
local logout = W.NewFrame()
logout.GetText = function() return "Log Out" end
menu.buttonPool = { EnumerateActive = function() local done; return function() if not done then done = true; return logout end end end }
env.GameMenuFrame = menu
local ours = W.NewFrame("WM_GameMenuButton", menu)
WM.gameMenuButton = ours
local function Place(f, l, r, t, b)
    f.GetLeft, f.GetRight, f.GetTop, f.GetBottom = function() return l end, function() return r end, function() return t end, function() return b end
end
Place(logout, 100, 244, 300, 279)
Place(ours, 100, 244, 279, 258)
check("side by side: no overlap", D.MenuOverlap() == false)
Place(ours, 100, 244, 295, 274)
check("on top of Log Out: overlap", D.MenuOverlap() == true)
W.printed = {}
D:Report()
check("report: says it's covering Log Out", Said("covering Log Out"))
check("report: blocked actions listed", Said("Blocked actions") and Said("SomeAddon"))
check("report: what to try", Said("/logout") and Said("taintLog"))
menu:Hide()
check("menu closed: can't tell", D.MenuOverlap() == nil)

-- ---- The menu button: clicks, and turning it off ----
local n = #log
WM.gameMenuButton = nil
WM:CreateGameMenuButton()
WM.gameMenuButton._scripts.OnClick(WM.gameMenuButton)
check("menu button clicks recorded", log[#log].kind == "menuclick")
W.printed = {}
env.SlashCmdList = env.SlashCmdList or {}
D:SetMenuButton(false)
check("menu button off", env.WatchingMachineDB.gameMenuButton == false and not WM.gameMenuButton:IsShown()
    and Said("/reload"))
WM.gameMenuHooked = nil
hooks = 0
WM:SetupGameMenuButton()
check("off: the menu isn't watched at all", not WM.gameMenuHooked)
D:SetMenuButton(true)
WM:SetupGameMenuButton()
check("on: watched", WM.gameMenuHooked == true and hooks == 0)

for _ = 1, 80 do D:Note("x", "filler") end
check("the record is kept short", #log == 60)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
