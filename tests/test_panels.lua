-- Module panels built with WM.UI: Buff Check, Debuff Tracker, PvP Tracker.
-- Usage: lua5.1 test_panels.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/BuffCheck.lua")
W.load("Modules/DebuffTracker.lua")
W.load("Modules/PvPTracker.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- Find a tracked checkbox by its (current) label text
local function FindCheckbox(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then
            return w
        end
    end
end
local function CountWidgets(panel)
    local n = 0
    for _ in ipairs(panel.layout.widgets) do n = n + 1 end
    return n
end

-- ============ Buff Check ============
local BC = WM.modules.BuffCheck
BC:InitDB()
local bp = BC:CreateUI()
bp:Show()
check("buff check panel fits the screen", bp:GetHeight() <= 768 - 16)
check("buff check panel isn't scrolling at 768", not bp.scrollBar:IsShown())
local food = FindCheckbox(bp, "Food Buff")
check("food check row present and on", food and food:GetChecked() == true)
W.click(food)
check("food checkbox writes the saved setting", env.BuffCheckDB.checkedGroups.wellfed == false)
local announce = FindCheckbox(bp, "Announce to raid")
check("announce row has a tooltip", announce and announce:GetScript("OnEnter") ~= nil)
check("buff check footer has Run Check Now", bp.footerButtons[1]:GetText() == "Run Check Now")
check("buff check same frame on reopen", BC:CreateUI() == bp)

-- ============ Debuff Tracker ============
local DT = WM.modules.DebuffTracker
DT:InitDB()
local dp = DT:CreateUI()
dp:Show()
check("debuff panel capped at 700", dp:GetHeight() == 700)
check("debuff panel scrolls", dp.scrollBar:IsShown())
check("debuff panel has an encounters section", dp.layout.sections.encounters ~= nil)
check("debuff panel has a debuff selection section", dp.layout.sections.debuffs ~= nil)
check("no separate encounter window", rawget(env, "WM_DebuffEncounterFrame") == nil)

local shear = FindCheckbox(dp, "call out Shear")
check("shear setting lives in the settings panel", shear ~= nil)
W.click(shear)
check("shear checkbox writes", env.DebuffTrackerDB.shearMonitor == shear:GetChecked())

-- /wmachine encounters opens the same panel at the encounters section
dp:Hide()
dp.body:SetVerticalScroll(0)
DT:ToggleEncounterUI()
check("encounters command shows the settings panel", dp:IsShown())
check("encounters command scrolls to the section", dp.body:GetVerticalScroll() > 0)

-- Auto-detect greys out the manual debuff choices, without a rebuild
local before = CountWidgets(dp)
local catName = nil
for name in pairs(env.DebuffTrackerDB.trackedCategories) do catName = name break end
env.DebuffTrackerDB.autoDetect = false
env.DebuffTrackerDB.trackedCategories[catName] = true
dp:Refresh()
local someDebuff
for _, w in ipairs(dp.layout.widgets) do
    local t = rawget(w, "Text")
    if t and t:GetText() and t:GetText():find("(P:", 1, true) then
        someDebuff = w
        if w:IsEnabled() then break end
    end
end
check("a debuff checkbox is editable with auto-detect off", someDebuff and someDebuff:IsEnabled())
local auto = FindCheckbox(dp, "Auto-configure")
W.click(auto)
check("auto-detect on", env.DebuffTrackerDB.autoDetect == true)
check("debuff choices greyed by auto-detect", not someDebuff:IsEnabled())
check("panel refreshed in place, not rebuilt", DT:CreateUI() == dp and CountWidgets(dp) == before)
W.click(auto)
DT:RefreshSettingsUI()
check("RefreshSettingsUI keeps the same frame", DT:CreateUI() == dp)

-- Sliders still write their saved values
local delayBox
for _, w in ipairs(dp.layout.widgets) do
    if rawget(w, "slider") and w.slider:GetName() == "WM_DebuffAlertDelaySlider" then delayBox = w end
end
delayBox.slider:SetValue(7.2)
check("alert delay slider writes", env.DebuffTrackerDB.alertDelay == 7)

-- ============ PvP Tracker ============
local PT = WM.modules.PvPTracker
PT:InitDB()
local pp = PT:CreateUI()
pp:Show()
check("pvp panel 700 tall", pp:GetHeight() == 700)
check("pvp panel has a list area", pp.scrollChild ~= nil and pp.layout.fill ~= nil)
local fillTop = select(5, pp.layout.fill.frame:GetPoint(1))
pp.layout.sections.sync:SetCollapsed(true)
local fillTop2 = select(5, pp.layout.fill.frame:GetPoint(1))
check("collapsing Guild Sync gives the list more room", fillTop2 > fillTop)
pp.layout.sections.sync:SetCollapsed(false)
check("settings rows leave the list at least 250px", 700 - 40 - 14 - (-fillTop) >= 250)

local manual = FindCheckbox(pp, "Manual tracking only")
W.click(manual)
check("pvp checkbox writes", env.PvPTrackerDB.trackManualOnly == manual:GetChecked())

local addBox
for _, w in ipairs(pp.layout.widgets) do if rawget(w, "editBox") then addBox = w end end
addBox.editBox:SetText("Gankalot")
W.fire(addBox.editBox, "OnEnterPressed")
check("Add to KOS adds the name", env.PvPTrackerDB.enemies["Gankalot"] ~= nil)
check("add box cleared", addBox.editBox:GetText() == "")
env.UIParent:SetHeight(600)
pp:Hide(); pp:Show()
check("pvp panel shrinks to a short screen", pp:GetHeight() == 600 - 16)
env.UIParent:SetHeight(768)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
