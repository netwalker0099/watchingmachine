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

local anchor = W.NewFrame("WatchingMachineMinimapButton")
local function Menu()
    local m = env.WM_MinimapModuleMenu
    if m and m:IsShown() then m:Hide() end
    WM:ShowModuleMenu(anchor)
    return env.WM_MinimapModuleMenu.entries
end
local function Row(name)
    for i, r in ipairs(env.WM_MinimapModuleMenu.rows) do
        if r.entry and r.entry.module == name then return r, i end
    end
end
local function Find(items, name)
    for i, it in ipairs(items) do if it.module == name then return it, i end end
end
local function TitleIndex(items, text)
    for i, it in ipairs(items) do if it.title and it.title:find(text, 1, true) then return i end end
end

-- ---- no favorites: every module, under its group ----
local items = Menu()
local menu = env.WM_MinimapModuleMenu
check("our own frame, shown", menu:IsShown() and menu._template:find("BackdropTemplate", 1, true))
local count = 0
for _, it in ipairs(items) do if it.module then count = count + 1 end end
local total = 0
for _, g in ipairs(WM.MODULE_GROUPS) do total = total + #g.modules end
check("every module listed once", count == total)
check("no Favorites heading without favorites", TitleIndex(items, "Favorites") == nil)
local _, iBuff = Find(items, "BuffCheck")
local _, iLog = Find(items, "AutoLogger")
check("grouped as on the dashboard", TitleIndex(items, "Raid") < iBuff and iBuff < TitleIndex(items, "Logging")
    and TitleIndex(items, "Logging") < iLog)
check("module rows have the module's icon and title", Row("LootBrowser").icon._texture == WM.MODULE_INFO.LootBrowser.icon
    and Row("LootBrowser").text:GetText() == WM.MODULE_INFO.LootBrowser.title)
check("settings and favorites at the bottom", items[#items - 1].action == "Edit favorites..."
    and items[#items].action == "Settings")
WM:ShowModuleMenu(anchor)
check("a second right-click closes it", not menu:IsShown())
-- A short screen: columns
local h = env.UIParent:GetHeight()
env.UIParent:SetHeight(300)
Menu()
check("too tall for the screen: split into columns", menu:GetWidth() > 2 * 190)
env.UIParent:SetHeight(h)

-- ---- clicking opens the module ----
local opened
WM.modules.LootBrowser.ToggleUI = function() opened = "LootBrowser" end
WM:SetModuleOn("LootBrowser", true)
Menu()
W.click(Row("LootBrowser"), "LeftButton")
check("click opens its window and closes the menu", opened == "LootBrowser" and not menu:IsShown())
opened = nil
WM:SetModuleOn("LootBrowser", false)
Menu()
check("an off module is greyed and says so", Row("LootBrowser").text:GetText():find("(off)", 1, true))
local asked
env.StaticPopup_Show = function(_, _, _, fn) asked = fn end
W.click(Row("LootBrowser"), "LeftButton")
check("an off module asks to be turned on first", opened == nil and asked ~= nil)
asked()
check("yes: turned on and opened", WM:IsModuleOn("LootBrowser") and opened == "LootBrowser")

-- ---- favorites ----
WM:SetMenuFavorite("GearSets", true)
Menu()
W.click(Row("AutoLogger"), "RightButton")
check("right-click a module: a favorite, menu stays open", WM:IsMenuFavorite("AutoLogger") and menu:IsShown())
check("saved account-wide", env.WatchingMachineDB.menuFavorites.GearSets == true)
items = menu.entries
local fav = TitleIndex(items, "Favorites")
local _, iGear = Find(items, "GearSets")
local _, iAuto = Find(items, "AutoLogger")
check("Favorites heading first", fav == 1)
check("favorites at the top, in dashboard order", iGear == 2 and iAuto == 3)
check("the rest follow", TitleIndex(items, "Raid") > iAuto)
local n = 0
for _, it in ipairs(items) do if it.module == "GearSets" then n = n + 1 end end
check("a favorite isn't listed twice", n == 1)
W.click(Row("GearSets"), "RightButton")
check("right-click again: off the favorites", not WM:IsMenuFavorite("GearSets")
    and #WM:MenuFavorites() == 1 and WM:MenuFavorites()[1] == "AutoLogger")
menu:Hide()

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
check("right-click opens the module menu", src:find('btn == "RightButton" then%s+GameTooltip:Hide%(%)%s+local ok, err = pcall%(WM.ShowModuleMenu, WM, self%)') ~= nil)
check("left-click still opens the dashboard", src:find('elseif btn == "LeftButton" then%s+WM:ToggleDashboard%(%)') ~= nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
