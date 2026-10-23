-- Dashboard cards: switches, tools menus, tooltips, options entry.
-- Usage: lua5.1 test_dashboard.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Load the whole addon in .toc order
for line in io.lines(REPO .. "/WatchingMachine.toc") do
    if line:match("%.lua$") then W.load(line) end
end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
-- Every module's saved variables, as at login
for name, m in pairs(WM.modules) do
    local ok = m.Initialize and pcall(m.Initialize, m)
    if not ok and m.InitDB then pcall(m.InitDB, m) end
end
WM.modules.ArmorySnap.db = env.ArmorySnapDB

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- grouping covers every module exactly once ----
local seen, total = {}, 0
for _, g in ipairs(WM.MODULE_GROUPS) do
    for _, name in ipairs(g.modules) do
        seen[name] = (seen[name] or 0) + 1
        total = total + 1
    end
end
for _, name in ipairs({ "AutoLogger", "KeywordMonitor", "MailLogger", "ServicesParser", "WhisperLogs",
                        "GuildInvite", "DebuffTracker", "PvPTracker", "Recruiter", "BuffCheck", "ChatFilter",
                        "ArmorySnap", "AuraRange", "ClassTools", "InstanceTracker", "PvPLog", "AltTracker", "WorldTimers", "LootBrowser", "GearScore", "Attunements", "Hazards", "Crits", "Ogrila" }) do
    check(name .. " has exactly one card", seen[name] == 1)
    local info = WM.MODULE_INFO[name]
    check(name .. " card explains itself", info and info.about and #info.about > 20 and info.command)
end
check("no stray cards", total == 24)

-- ---- build the dashboard ----
WM:CreateDashboard()
local dash = WM.dashboard
WM:CreateModuleCards()     -- normally deferred by a timer
dash:Show()
WM:UpdateDashboard()
local cards = dash.moduleCards

local switched = { BuffCheck = true, DebuffTracker = true, PvPTracker = true, GuildInvite = true, ChatFilter = true,
                   AuraRange = true, ArmorySnap = true, KeywordMonitor = true, Hazards = true, Crits = true, Ogrila = true }
for name, card in pairs(cards) do
    check(name .. (switched[name] and " has" or " has no") .. " an on/off switch",
        (card.switch ~= nil) == (switched[name] == true))
    check(name .. " status text stops before the buttons",
        card.statusText:GetWidth() > 100 and card.statusText:GetWidth() <= 370 - 50 - 63)
    check(name .. " card has a hover tooltip", card:GetScript("OnEnter") ~= nil)
end

-- ---- Class Tools card shows the player's class crest ----
local ctIcon = cards.ClassTools.icon
check("class tools icon is the class-circles sheet",
    rawget(ctIcon, "_texture") == "Interface\\TargetingFrame\\UI-Classes-Circles")
check("cropped to the player's class (mage)", rawget(ctIcon, "_texCoord")[1] == 0.25
    and rawget(ctIcon, "_texCoord")[2] == 0.49609375)
local saved = env.CLASS_ICON_TCOORDS
env.CLASS_ICON_TCOORDS = false
WM:SetCardIcon(ctIcon, WM.MODULE_INFO.ClassTools)
check("falls back to the gear icon without the coords table",
    rawget(ctIcon, "_texture") == "Interface\\Icons\\INV_Misc_Gear_01" and rawget(ctIcon, "_texCoord")[2] == 1)
env.CLASS_ICON_TCOORDS = saved
for name, info in pairs(WM.MODULE_INFO) do
    check(name .. " icon isn't a Wrath achievement icon", not info.icon:find("Achievement_", 1, true))
end

-- ---- switches ----
local function Toggle(name) W.click(cards[name].switch); WM:UpdateDashboard() end
check("buff check starts on", cards.BuffCheck.switch:GetChecked() == true)
Toggle("BuffCheck")
check("switch off writes the module's own flag", env.BuffCheckDB.enabled == false)
check("off card's icon is greyed", rawget(cards.BuffCheck.icon, "_desaturated") == true)
Toggle("BuffCheck")
check("switch back on", env.BuffCheckDB.enabled == true)
check("on card's icon in colour", rawget(cards.BuffCheck.icon, "_desaturated") == false)

local registered = 0
local PT = WM.modules.PvPTracker
local origReg, origUnreg = PT.RegisterEvents, PT.UnregisterEvents
PT.RegisterEvents = function() registered = registered + 1 end
PT.UnregisterEvents = function() registered = registered - 1 end
env.PvPTrackerDB.enabled = true; WM:UpdateDashboard()
Toggle("PvPTracker")
check("pvp switch unregisters events", registered == -1 and env.PvPTrackerDB.enabled == false)
Toggle("PvPTracker")
check("pvp switch registers events", registered == 0 and env.PvPTrackerDB.enabled == true)
PT.RegisterEvents, PT.UnregisterEvents = origReg, origUnreg

Toggle("KeywordMonitor")
check("keyword switch pauses monitoring", WM.modules.KeywordMonitor:IsPaused() == true)
Toggle("KeywordMonitor")
check("keyword switch resumes", WM.modules.KeywordMonitor:IsPaused() == false)

Toggle("ArmorySnap")
check("armorysnap switch turns auto-scan off", env.ArmorySnapDB.options.enabled == false)
Toggle("ArmorySnap")

-- change made elsewhere shows up on the card
env.DebuffTrackerDB.enabled = false
WM:UpdateDashboard()
check("card follows a setting changed in the module", cards.DebuffTracker.switch:GetChecked() == false)
env.DebuffTrackerDB.enabled = true

-- the module's own enable checkbox goes through the same path
local bp = WM.modules.BuffCheck:CreateUI()
bp:Show()
local enableCB
for _, w in ipairs(bp.layout.widgets) do
    local t = rawget(w, "Text")
    if t and t:GetText() == "Enable buff check on ready check" then enableCB = w end
end
W.click(enableCB)
WM:UpdateDashboard()
check("panel checkbox and card switch agree", cards.BuffCheck.switch:GetChecked() == env.BuffCheckDB.enabled)
W.click(enableCB)

-- ---- tools menus reach real methods ----
local calls = {}
local real = {}
for name, m in pairs(WM.modules) do
    real[name] = m
    WM.modules[name] = setmetatable({}, { __index = function(_, method)
        return function() calls[#calls + 1] = { name, method } end
    end })
end
env.StaticPopup_Show = function(_, _, _, fn) fn() end   -- accept every confirm
env.UnitClass = function() return "Warlock", "WARLOCK" end
for name, info in pairs(WM.MODULE_INFO) do
    for _, t in ipairs(info.tools or {}) do t.func() end
end
env.UnitClass = function() return "Mage", "MAGE" end
for name, m in pairs(real) do WM.modules[name] = m end
check("tools made calls", #calls >= 18)
for _, c in ipairs(calls) do
    local m = real[c[1]]
    check("tool calls " .. c[1] .. ":" .. c[2], m and m[c[2]] ~= nil)
end

-- class-only tools are hidden for other classes
local function VisibleCount(info)
    local n = 0
    for _, t in ipairs(info.tools) do if not t.visible or t.visible() then n = n + 1 end end
    return n
end
env.UnitClass = function() return "Mage", "MAGE" end
check("mage sees consumables + portals", VisibleCount(WM.MODULE_INFO.ClassTools) == 2)
env.UnitClass = function() return "Warrior", "WARRIOR" end
check("warrior sees consumables + swing timer", VisibleCount(WM.MODULE_INFO.ClassTools) == 2)

-- ---- right-click opens the tools menu ----
local added, toggled = {}, 0
env.UIDropDownMenu_CreateInfo = function() return {} end
env.UIDropDownMenu_AddButton = function(item) added[#added + 1] = item end
env.UIDropDownMenu_Initialize = function(frame, fn) fn(frame, 1) end
local lastAnchor
env.ToggleDropDownMenu = function(level, value, frame, anchor) toggled = toggled + 1; lastAnchor = anchor end
W.fire(cards.DebuffTracker, "OnMouseUp", "RightButton")
check("right-click opens a menu", toggled == 1)
check("right-click menu hangs off the card's ... button, not the cursor",
    lastAnchor == cards.DebuffTracker.toolsBtn)
check("menu has title, every tool and cancel", #added == #WM.MODULE_INFO.DebuffTracker.tools + 2
    and added[1].isTitle and added[#added].text)
added = {}
W.click(cards.BuffCheck.toolsBtn)
check("... button opens the same menu", toggled == 2 and #added == #WM.MODULE_INFO.BuffCheck.tools + 2)
check("menu opens under the ... button that was clicked", lastAnchor == cards.BuffCheck.toolsBtn)
added = {}
W.fire(cards.AutoLogger, "OnMouseUp", "RightButton")
check("no menu for a module without tools", toggled == 2 and #added == 0)
check("no ... button without tools", cards.AutoLogger.toolsBtn == nil)

-- ---- card tooltip ----
local lines = {}
env.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
W.fire(cards.DebuffTracker, "OnEnter")
local joined = table.concat(lines, "\n")
check("tooltip has the long description", joined:find("encounter callouts", 1, true) ~= nil)
check("tooltip shows switch state", joined:find("Switch:", 1, true) ~= nil)
check("tooltip mentions tools", joined:find("right-click", 1, true) ~= nil)
check("tooltip shows the command", joined:find("/wmachine debuff", 1, true) ~= nil)

-- ---- options entry ----
local registeredCat
env.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
    RegisterAddOnCategory = function(cat) registeredCat = cat end,
}
WM:RegisterOptionsCategory()
check("registered under Options > AddOns", registeredCat and registeredCat.name == "Watching Machine")
WM.optionsCategory = nil
env.Settings = false   -- the stub would otherwise answer for a missing global
local legacy
env.InterfaceOptions_AddCategory = function(f) legacy = f end
WM:RegisterOptionsCategory()
check("falls back to InterfaceOptions", legacy and legacy.name == "Watching Machine")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
