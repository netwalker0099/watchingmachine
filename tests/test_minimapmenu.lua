-- The minimap button's right-click menu: every module, favorites first,
-- and the favorites list in the settings panel.
-- Usage: lua5.1 test_minimapmenu.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

for line in io.lines(REPO .. "/WatchingMachine.toc") do
    if line:match("%.lua$") then W.load(line) end
end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
for _, m in pairs(WM.modules) do
    local ok = m.Initialize and pcall(m.Initialize, m)
    if not ok and m.InitDB then pcall(m.InitDB, m) end
end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local anchored
env.ToggleDropDownMenu = function(_, _, dd, anchor) anchored = { dd, anchor } end
local function Menu()
    WM:ShowModuleMenu("button")
    return W.openMenu(env.WM_MinimapModuleMenu)
end
local function Find(items, name)
    for i, it in ipairs(items) do if it.moduleName == name then return it, i end end
end
local function TitleIndex(items, text)
    for i, it in ipairs(items) do if it.isTitle and it.text and it.text:find(text, 1, true) then return i end end
end

-- ---- no favorites: every module, under its group ----
local items = Menu()
check("opens at the minimap button", anchored and anchored[1] == env.WM_MinimapModuleMenu and anchored[2] == "button")
local count = 0
for _, it in ipairs(items) do if it.moduleName then count = count + 1 end end
local total = 0
for _, g in ipairs(WM.MODULE_GROUPS) do total = total + #g.modules end
check("every module listed once", count == total)
check("no Favorites heading without favorites", TitleIndex(items, "Favorites") == nil)
local _, iBuff = Find(items, "BuffCheck")
local _, iLog = Find(items, "AutoLogger")
check("grouped as on the dashboard", TitleIndex(items, "Raid") < iBuff and iBuff < TitleIndex(items, "Logging")
    and TitleIndex(items, "Logging") < iLog)
check("module lines have the module's icon and description",
    Find(items, "LootBrowser").icon == WM.MODULE_INFO.LootBrowser.icon
    and Find(items, "LootBrowser").tooltipText:find(WM.MODULE_INFO.LootBrowser.desc, 1, true))
check("settings and favorites at the bottom", items[#items - 2].text == "Edit favorites..."
    and items[#items - 1].text == "Settings")

-- ---- clicking opens the module ----
local opened
WM.modules.LootBrowser.ToggleUI = function() opened = "LootBrowser" end
WM:SetModuleOn("LootBrowser", true)
Find(items, "LootBrowser").func()
check("click opens its window", opened == "LootBrowser")
opened = nil
WM:SetModuleOn("LootBrowser", false)
items = Menu()
check("an off module is greyed and says so", Find(items, "LootBrowser").text:find("(off)", 1, true))
local asked
env.StaticPopup_Show = function(_, _, _, fn) asked = fn end
Find(items, "LootBrowser").func()
check("an off module asks to be turned on first", opened == nil and asked ~= nil)
asked()
check("yes: turned on and opened", WM:IsModuleOn("LootBrowser") and opened == "LootBrowser")

-- ---- favorites ----
WM:SetMenuFavorite("GearSets", true)
WM:SetMenuFavorite("AutoLogger", true)
check("saved account-wide", env.WatchingMachineDB.menuFavorites.GearSets == true)
items = Menu()
local fav = TitleIndex(items, "Favorites")
local _, iGear = Find(items, "GearSets")
local _, iAuto = Find(items, "AutoLogger")
check("Favorites heading first", fav == 1)
check("favorites at the top, in dashboard order", iGear == 2 and iAuto == 3)
check("the rest follow", TitleIndex(items, "Raid") > iAuto)
local n = 0
for _, it in ipairs(items) do if it.moduleName == "GearSets" then n = n + 1 end end
check("a favorite isn't listed twice", n == 1)
WM:SetMenuFavorite("GearSets", false)
check("unticked: gone from favorites", #WM:MenuFavorites() == 1 and WM:MenuFavorites()[1] == "AutoLogger")

-- ---- the settings panel's favorites list ----
local panel = WM:CreateSettingsPanel()
check("settings has a favorites section, collapsed", panel.layout.sections.menuFavorites ~= nil
    and panel.layout.sections.menuFavorites:IsCollapsed())
local box
for _, w in ipairs(panel.layout.widgets) do
    if type(w.Text) == "table" and w.Text:GetText() == WM.MODULE_INFO.Crits.title then box = w end
end
check("a tick box per module", box ~= nil)
box:SetChecked(true)
W.fire(box, "OnClick")
check("ticking makes it a favorite", WM:IsMenuFavorite("Crits"))
WM:EditMenuFavorites()
check("Edit favorites opens settings at the list", panel:IsShown()
    and not panel.layout.sections.menuFavorites:IsCollapsed())

-- ---- the minimap button: right-click is the menu, left-click the dashboard ----
local src = io.open(REPO .. "/Core.lua"):read("*a")
check("right-click opens the module menu", src:find('btn == "RightButton" then%s+GameTooltip:Hide%(%)%s+WM:ShowModuleMenu%(self%)') ~= nil)
check("left-click still opens the dashboard", src:find('elseif btn == "LeftButton" then%s+WM:ToggleDashboard%(%)') ~= nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
