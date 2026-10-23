-- Core windows built with WM.UI: Settings, the dashboard shell, Class Tools
-- and the PvP leaderboard. Usage: lua5.1 test_panels_core.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Record every frame so tab buttons inside Choice widgets can be found
local created = {}
local rawCreateFrame = env.CreateFrame
env.CreateFrame = function(...)
    local f = rawCreateFrame(...)
    created[#created + 1] = f
    return f
end

-- Load the whole addon in .toc order
for line in io.lines(REPO .. "/WatchingMachine.toc") do
    if line:match("%.lua$") then W.load(line) end
end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default", dashboardPos = { "TOPLEFT", "TOPLEFT", 100, -50 } }
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
for name, m in pairs(WM.modules) do
    local ok = m.Initialize and pcall(m.Initialize, m)
    if not ok and m.InitDB then pcall(m.InitDB, m) end
end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function FindCheckbox(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then return w end
    end
end
local function FindButton(list, text)
    for _, b in ipairs(list) do
        if b._template == "UIPanelButtonTemplate" and b:GetText() and b:GetText():find(text, 1, true) then
            return b
        end
    end
end
local function FindText(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        if rawget(w, "_text") and w._text:find(pattern, 1, true) then return w end
    end
end
local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

-- ============ Settings ============
local sp = WM:CreateSettingsPanel()
sp:Show()
check("settings panel built by the builder", sp.layout ~= nil and sp:GetName() == "WM_SettingsFrame")
check("settings panel same frame on reopen", WM:CreateSettingsPanel() == sp)
check("settings panel fits", sp:GetHeight() <= 700 and sp:GetHeight() >= 120)
local dd = env.WM_SettingsThemeDropdown
check("theme dropdown keeps its global name", dd ~= nil and dd._ddInit ~= nil)
check("theme dropdown shows the current theme", dd._ddText == "Default")
local items = W.openMenu(dd)
check("theme dropdown lists Default and ElvUI", #items == 2 and items[1].text == "Default" and items[2].text == "ElvUI")
check("current theme ticked", items[1].checked == true and not items[2].checked)
check("active theme line", FindText(sp, "Active:") and FindText(sp, "Active:")._text:find("Default", 1, true))

-- ============ Dashboard ============
WM:CreateDashboard()
local dash = WM.dashboard
dash:Show()
check("dashboard built by the builder", dash.layout ~= nil and dash:GetName() == "WatchingMachineDashboard")
check("dashboard is a fill panel", dash.opts.scroll == false and dash.layout.fill ~= nil)
-- 18 cards don't fit one column on a 768-high screen: two columns
check("dashboard opens at a size that shows every card", dash:GetWidth() == 50 + 2 * 370 + 6
    and dash:GetHeight() == 3 * 20 + 10 * 49 + 12 + 104)
check("dashboard is resizable", dash.sizeGrip ~= nil)
check("card scroll keeps its name", env.WM_DashboardCardScroll == dash.cardsScroll)
check("card scroll sits in the fill area", dash.cardsScroll:GetParent() == dash.layout.fill.frame)
check("cards container in the scroll frame", dash.cardsContainer:GetParent() == dash.cardsScroll)

-- Position migrated once into the builder's panel state
local state = env.WatchingMachineDB.panels and env.WatchingMachineDB.panels.WatchingMachineDashboard
check("old dashboardPos cleared", env.WatchingMachineDB.dashboardPos == nil)
check("position moved to panels state", state and state.pos and state.pos[1] == "TOPLEFT" and state.pos[4] == -50)
local point, _, relPoint, x, y = dash:GetPoint(1)
check("dashboard opens where it was left", point == "TOPLEFT" and relPoint == "TOPLEFT" and x == 100 and y == -50)

WM:CreateModuleCards()     -- normally deferred by a timer
local n, inside = 0, true
for _, card in pairs(dash.moduleCards) do
    n = n + 1
    if card:GetParent() ~= dash.cardsContainer then inside = false end
end
check("every module card created", n == 18)
check("cards live in cardsContainer", inside)
check("container sized to the cards", dash.cardsContainer:GetHeight() == 3 * 20 + 10 * 49 + 12)
check("two columns of cards", dash.cardColumns == 2)
local function CardAt(name) local _, _, _, x, y = dash.moduleCards[name]:GetPoint(1); return x, y end
local bx, by = CardAt("BuffCheck")
local dx, dy = CardAt("DebuffTracker")
local cx, cy = CardAt("ClassTools")
check("cards fill a row before the next", bx == 0 and dx == 376 and dy == by and cx == 0 and cy == by - 49)
check("card width split between columns", dash.moduleCards.BuffCheck:GetWidth() == 370)
-- Narrower: one column, every card stacked
dash:SetWidth(400)
WM:LayoutCards()
check("narrow: one column", dash.cardColumns == 1 and select(4, dash.moduleCards.DebuffTracker:GetPoint(1)) == 0
    and dash.cardsContainer:GetHeight() == 3 * 20 + 18 * 49 + 12)
check("card text narrows with the card", dash.moduleCards.BuffCheck.titleText:GetWidth()
    == 350 - dash.moduleCards.BuffCheck.textReserve)
-- Wide: three columns
dash:SetWidth(50 + 3 * 340 + 12)
WM:LayoutCards()
check("wide: three columns", dash.cardColumns == 3)
-- Fit puts the every-card size back and saves it
WM:FitDashboard()
check("Fit: back to the size that shows every card", dash:GetWidth() == 796 and dash.cardColumns == 2
    and dash:GetHeight() == 666)
local saved = env.WatchingMachineDB.panels.WatchingMachineDashboard.size
check("Fit saves the size", saved and saved[1] == 796 and saved[2] == 666)
W.click(dash.fitBtn)
check("Fit button", dash:GetWidth() == 796)

-- Footer
check("minimap button says hide", dash.minimapBtn:GetText() == "Hide Minimap")
check("minimap status visible", dash.minimapStatus:GetText():find("Visible", 1, true) ~= nil)
W.click(dash.minimapBtn)
check("minimap toggle hides", env.WatchingMachineDB.minimapHidden == true)
check("minimap button text follows", dash.minimapBtn:GetText() == "Show Minimap")
check("minimap status follows", dash.minimapStatus:GetText():find("Hidden", 1, true) ~= nil)
W.click(dash.minimapBtn)
check("minimap toggle shows again", env.WatchingMachineDB.minimapHidden == false
    and dash.minimapBtn:GetText() == "Hide Minimap")
check("minimap status beside its button", select(2, dash.minimapStatus:GetPoint(1)) == dash.minimapBtn)
sp:Hide()
W.click(FindButton(dash.footerButtons, "Settings"))
check("Settings button opens settings", sp:IsShown())
W.printed = {}
W.click(FindButton(dash.footerButtons, "Help"))
check("Help button prints the commands", table.concat(W.printed, "\n"):find("/wmachine", 1, true) ~= nil)

-- ============ Theme change ============
local themeChanges = 0
local realOnThemeChanged = WM.OnThemeChanged
WM.OnThemeChanged = function(self, ...) themeChanges = themeChanges + 1; return realOnThemeChanged(self, ...) end
local aCard = dash.moduleCards.BuffCheck
items = W.openMenu(dd)
items[2].func()
check("selecting ElvUI saves the theme", env.WatchingMachineDB.theme == "ElvUI")
check("selecting ElvUI calls OnThemeChanged", themeChanges == 1)
check("dropdown shows ElvUI", dd._ddText == "ElvUI")
check("active line follows the theme", FindText(sp, "Active:")._text:find("ElvUI", 1, true) ~= nil)
check("settings panel refreshed in place", WM:CreateSettingsPanel() == sp and sp:IsShown())
check("dashboard kept, not rebuilt", WM.dashboard == dash and dash:IsShown())
check("dashboard cards still reskinned", WM._skinnedCards[aCard] ~= nil)
check("dashboard title recoloured", same(dash.titleText._color, WM.THEMES.ElvUI.addonTitleColor))
items = W.openMenu(dd)
items[1].func()
check("back to Default", env.WatchingMachineDB.theme == "Default" and themeChanges == 2
    and same(dash.titleText._color, WM.THEMES.Default.addonTitleColor))
WM.OnThemeChanged = realOnThemeChanged

local verbose = FindCheckbox(sp, "Verbose chat")
check("verbose checkbox has its tooltip", verbose and verbose:GetScript("OnEnter") ~= nil)
W.click(verbose)
check("verbose checkbox writes", env.WatchingMachineDB.verboseChat == true)
W.click(verbose)
check("verbose checkbox clears", env.WatchingMachineDB.verboseChat == false)

-- dashboard fits a short screen
env.UIParent:SetHeight(500)
dash:Hide(); dash:Show()
check("dashboard shrinks to a short screen", dash:GetHeight() == 500 - 16)
env.UIParent:SetHeight(768)

-- ============ Class Tools ============
local CT = WM.modules.ClassTools
local cp = CT:CreateUI()
cp:Show()
local rows = cp.layout.rows
check("class tools built by the builder", cp:GetName() == "WM_ClassToolsFrame" and cp.layout ~= nil)
check("class tools within 486", cp:GetHeight() <= 486)

-- Tab buttons: buttons in a shown Choice box inside one of the two tab rows
local function Tabs()
    local out = {}
    for i = 1, 2 do
        for _, f in ipairs(created) do
            local box = f:GetParent()
            if f._template == "UIPanelButtonTemplate" and box and box._shown and box:GetParent() == rows[i].frame then
                out[#out + 1] = f
            end
        end
    end
    return out
end
local function Tab(label)
    for _, b in ipairs(Tabs()) do
        if b:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == label then return b end
    end
end
local function Header()
    for _, w in ipairs(cp.layout.widgets) do
        if w:GetParent() == rows[3].frame then return w:GetText() end
    end
end
local function ShownFeatures()
    local out = {}
    for _, f in ipairs(created) do
        local row = f:GetParent()
        if f._template == "InterfaceOptionsCheckButtonTemplate" and row and row._shown
            and row:GetParent() == rows[4].frame then
            out[#out + 1] = f
        end
    end
    return out
end
local function HasFeature(label)
    for _, cb in ipairs(ShownFeatures()) do if cb.Text:GetText() == label then return cb end end
end

local tabs = Tabs()
check("a tab per populated class", #tabs == 5 and Tab("General") and Tab("Mage") and Tab("Warlock") and Tab("Shaman") and Tab("Paladin"))
check("General tab first", tabs[1] == Tab("General"))
check("current class marked", Tab("Mage"):GetText() == "|cFF00FF00Mage|r"
    and Tab("Warlock"):GetText() == "Warlock")
check("header names your class", Header():find("Mage", 1, true) and Header():find("your class", 1, true))
check("mage features shown", #ShownFeatures() == 3 and HasFeature("Warn if armor spell is missing")
    and HasFeature("Show the mage utility button"))

W.click(Tab("Warlock"))
check("switching tab marks it", Tab("Warlock"):GetText() == "|cFF00FF00Warlock|r"
    and Tab("Mage"):GetText() == "Mage")
check("header follows the tab", Header():find("Warlock", 1, true) and not Header():find("your class", 1, true))
check("warlock features shown", #ShownFeatures() == 5 and HasFeature("Track soulstone timers")
    and HasFeature("Show the warlock button"))

local calls = {}
local realSetEnabled = CT.SetEnabled
CT.SetEnabled = function(self, class, key, v) calls[#calls + 1] = { class, key, v }; return realSetEnabled(self, class, key, v) end
local ss = HasFeature("Track soulstone timers")
local was = ss:GetChecked()
W.click(ss)
check("feature checkbox calls SetEnabled", #calls == 1 and calls[1][1] == "WARLOCK" and calls[1][2] == "soulstones"
    and calls[1][3] == not was)
check("feature checkbox saved", CT:IsEnabled("WARLOCK", "soulstones") == not was)
W.click(ss)
CT.SetEnabled = realSetEnabled
check("feature checkbox has description", ss:GetParent().desc:GetText():find("Soulstones", 1, true) ~= nil)

-- A feature registered after the panel exists adds its tab
CT:RegisterFeature("DRUID", { key = "motw", name = "Warn if Mark of the Wild is missing", desc = "Test.", default = true })
check("late registration adds a tab", Tab("Druid") ~= nil and #Tabs() == 6)
check("selected tab kept", Tab("Warlock"):GetText() == "|cFF00FF00Warlock|r")
W.click(Tab("Druid"))
check("late feature shows", #ShownFeatures() == 1 and HasFeature("Warn if Mark of the Wild is missing"))
CT:RegisterFeature("DRUID", { key = "thorns", name = "Thorns", default = false })
check("late feature on the open tab shows", #ShownFeatures() == 2 and HasFeature("Thorns")
    and not HasFeature("Thorns"):GetChecked())

-- Many features scroll instead of overflowing
for i = 1, 30 do
    CT:RegisterFeature("SHAMAN", { key = "f" .. i, name = "Feature " .. i, desc = "Something to check, number " .. i .. "." })
end
CT:RegisterFeature("ROGUE", { key = "poison", name = "Warn if no poison", default = true })
check("tabs wrap onto a second row", #Tabs() == 7 and not rows[2].hidden)
W.click(Tab("Shaman"))
check("thirty features listed, plus the totem button", #ShownFeatures() == 31)
check("long list stays within 486", cp:GetHeight() <= 486)
check("long list scrolls", cp.scrollBar:IsShown() and cp.layout.height > cp:GetHeight())
W.click(Tab("General"))
check("General lists its checkbox options (mana warnings, flyout dock and lock, swing timer included)",
    #ShownFeatures() == 12 and HasFeature("Dock flyout buttons together") and HasFeature("Lock flyout buttons")
    and HasFeature("Swing timer") and HasFeature("Shaman weapon sync mark"))
W.click(Tab("Rogue"))
check("short list stops scrolling", not cp.scrollBar:IsShown() and #ShownFeatures() == 1)

-- Player's own class gets a tab even with nothing built for it
env.UnitClass = function() return "Hunter", "HUNTER" end
CT:DetectClass()
CT:RefreshUI()
W.click(Tab("Hunter"))
check("own empty class has a tab", Tab("Hunter") ~= nil and #ShownFeatures() == 0)
check("empty class explains itself", cp.emptyText:IsShown()
    and cp.emptyText:GetText():find("No tools built for your class", 1, true))
env.UnitClass = function() return "Mage", "MAGE" end
CT:DetectClass()
CT:RefreshUI()
check("empty text hidden again", Tab("Hunter") == nil and not cp.emptyText:IsShown())

-- Shared warning-frame options
local sound = FindCheckbox(cp, "Play a sound")
check("sound option has a tooltip", sound and sound:GetScript("OnEnter") ~= nil)
local soundWas = env.ClassToolsDB.alertSound
W.click(sound)
check("sound option writes", env.ClassToolsDB.alertSound == not soundWas)
W.click(sound)
local locks = 0
local realLock = CT.ApplyAlertLock
CT.ApplyAlertLock = function(self) locks = locks + 1; return realLock(self) end
W.click(FindCheckbox(cp, "Lock the warning frame"))
check("lock option writes and applies", env.ClassToolsDB.alertLocked == true and locks == 1)
W.click(FindCheckbox(cp, "Lock the warning frame"))
CT.ApplyAlertLock = realLock
env.ClassToolsDB.alertX, env.ClassToolsDB.alertY = 10, 20
W.click(FindButton(cp.layout.widgets, "Reset position"))
check("reset position clears the saved spot", env.ClassToolsDB.alertX == nil and env.ClassToolsDB.alertY == nil)
CT:ClearAllAlerts()
W.click(FindButton(cp.layout.widgets, "Show example"))
check("show example puts up two warnings", CT:GetActiveAlertCount() == 2)
CT:ClearAllAlerts()
check("same panel on reopen", CT:CreateUI() == cp)
cp:Hide()
CT:Toggle()
check("toggle reopens it", cp:IsShown())

-- ============ PvP leaderboard ============
local PT = WM.modules.PvPTracker
env.PvPTrackerDB.leaderboard = {
    Alpha = { points = 5, lastUpdate = 1 },
    Bravo = { points = 1, lastUpdate = 2 },
}
env.PvPTrackerDB.myKOSKills = 3
local lb = PT:CreateLeaderboard()
check("leaderboard built by the builder", lb:GetName() == "WM_PvPLeaderboardFrame" and lb.layout ~= nil)
check("leaderboard opens beside the tracker", lb:GetPoint(1) == "CENTER" and select(4, lb:GetPoint(1)) == 250)
PT:ToggleLeaderboard()
check("leaderboard shown", lb:IsShown())
check("leaderboard at most 700 tall", lb:GetHeight() <= 700 and lb:GetHeight() == 340)
local shown = {}
for _, row in ipairs(lb.rows) do if row._shown then shown[#shown + 1] = row end end
check("a row per player", #shown == 3)
check("ranked by points", shown[1].nameText:GetText():find("Alpha", 1, true)
    and shown[2].nameText:GetText():find("Me", 1, true) and shown[3].nameText:GetText():find("Bravo", 1, true))
check("leader gets gold", shown[1].rankText:GetText():find("FFD700", 1, true) ~= nil)
check("you are green", shown[2].nameText:GetText():find("00FF00", 1, true) ~= nil)
check("subtitle shows your rank", lb.subtitle:GetText():find("3 pts (#2)", 1, true) ~= nil)
check("empty text hidden with entries", not lb.emptyText:IsShown())
check("rows fit the list width", lb.scrollChild:GetWidth() >= 232)

env.PvPTrackerDB.leaderboard = {}
env.PvPTrackerDB.myKOSKills = 0
PT:RefreshLeaderboard()
local left = 0
for _, row in ipairs(lb.rows) do if row._shown then left = left + 1 end end
check("cleared board hides the rows", left == 0)
check("cleared board shows the empty text", lb.emptyText:IsShown())
check("subtitle prompts for points", lb.subtitle:GetText():find("No points yet", 1, true) ~= nil)
check("rows reused, not recreated", #lb.rows == 3)
PT:ToggleLeaderboard()
check("leaderboard toggles closed", not lb:IsShown())

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
