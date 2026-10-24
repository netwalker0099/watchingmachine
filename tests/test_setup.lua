-- Per-character settings, module switches and the setup: profiles over
-- saved variables, shared data, old settings carried over, a new character
-- starting with everything off, an old one keeping its modules, starting
-- and stopping modules, the welcome window, quick and guided setup, copying
-- another character.
-- Usage: lua5.1 test_setup.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local errors = {}
env.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
local name = "Newbie"
env.UnitName = function() return name end
env.GetRealmName = function() return "Spineshatter" end
env.StaticPopup_Show = function(_, _, _, fn) fn() end
env.SlashCmdList = {}

for line in io.lines(REPO .. "/WatchingMachine.toc") do
    if line:match("%.lua$") then W.load(line) end
end
local WM = W.WM
local P = WM.Profiles

local pass, fail = 0, 0
local function check(label, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", label, "\n") end
end
local function Said(text)
    for i = #W.printed, 1, -1 do if tostring(W.printed[i]):find(text, 1, true) then return true end end
end

-- ---- Saved data from before profiles ----
env.WatchingMachineDB = { theme = "Default", chars = nil }
env.HazardsDB = { enabled = true, trivialPct = 5, sounds = { "kit:1" } }
env.AltTrackerDB = { chars = { ["Veteran-Spineshatter"] = { name = "Veteran" } }, showAll = true }
env.PvPTrackerDB = { enemies = { Bob = { kills = 3 } }, alertSound = false }

-- First login after the update, on a brand-new character
P:Load()
local raw = rawget(env, "HazardsDB")
check("profiles: the saved table only holds the store", rawget(raw, "trivialPct") == nil and rawget(raw, "__wm") ~= nil)
check("profiles: old settings carried over", env.HazardsDB.trivialPct == 5 and env.HazardsDB.sounds[1] == "kit:1")
env.HazardsDB.trivialPct = 9
env.HazardsDB.newKey = "x"
check("profiles: writes go to this character", raw.__wm.profiles["Newbie-Spineshatter"].trivialPct == 9
    and raw.__wm.legacy.trivialPct == 5 and rawget(raw, "newKey") == nil)
env.HazardsDB.newKey = nil
check("profiles: setting nil clears it", env.HazardsDB.newKey == nil)
check("profiles: shared data stays shared", env.AltTrackerDB.chars["Veteran-Spineshatter"] ~= nil
    and rawget(env.AltTrackerDB, "__wm").shared.chars ~= nil)
env.PvPTrackerDB.enemies.Alice = { kills = 1 }
env.PvPTrackerDB.alertSound = true
check("profiles: mixed tables split", rawget(env.PvPTrackerDB, "__wm").shared.enemies.Alice
    and rawget(env.PvPTrackerDB, "__wm").profiles["Newbie-Spineshatter"].alertSound == true)
check("profiles: never-saved tables work too", env.OgrilaDB ~= nil and (function() env.OgrilaDB.scale = 2; return env.OgrilaDB.scale == 2 end)())
check("ArmorySnap is left alone (the standalone addon reads it)", getmetatable(env.ArmorySnapDB or {}) == nil)

-- Simulate logging in on another character: the game saves the raw tables
local function Relog(who)
    local saved = {}
    for sv in pairs(P.SCOPE) do
        local t = rawget(env, sv)
        if t then setmetatable(t, nil); saved[sv] = t end
    end
    name = who
    for sv, t in pairs(saved) do env[sv] = t end
    P.profiles, P.stores, P.fresh = {}, {}, {}
    P:Load()
end
Relog("Veteran")
check("second character: starts from the old settings", env.HazardsDB.trivialPct == 5)
check("second character: sees the shared data", env.PvPTrackerDB.enemies.Alice ~= nil)
env.HazardsDB.trivialPct = 3
Relog("Newbie")
check("first character keeps its own", env.HazardsDB.trivialPct == 9)
Relog("Veteran")
check("and the second its own", env.HazardsDB.trivialPct == 3)

-- ---- Which modules are on ----
name = "Veteran"
local c = WM:InitCharacter()
check("a character that used it before: everything stays on, setup offered", c.setup == "offer" and c.defaultOn
    and WM:IsModuleOn("Hazards") and WM:IsModuleOn("LootBrowser"))
Relog("Newbie")
c = WM:InitCharacter()
check("a new character: everything off, asked to set up", c.setup == "new" and not c.defaultOn
    and not WM:IsModuleOn("Hazards") and not WM:IsModuleOn("ClassTools"))
check("InitCharacter only once", WM:InitCharacter() == c)

-- Startup starts only what's on
local started = {}
for n, m in pairs(WM.modules) do
    local real = m.Initialize
    m.Initialize = function(self) started[n] = (started[n] or 0) + 1; if real then return real(self) end end
    m._realInit = real
end
c.modules.Hazards = true
WM:OnSecurityCheckPassed()
check("startup: only modules that are on start", started.Hazards == 1 and started.LootBrowser == nil and started.ClassTools == nil)

-- Turning on and off now
WM:SetModuleOn("LootBrowser", true)
check("turning a module on starts it", started.LootBrowser == 1 and WM:IsModuleOn("LootBrowser"))
WM:SetModuleOn("LootBrowser", false)
WM:SetModuleOn("LootBrowser", true)
check("and only once", started.LootBrowser == 1)
local offCalls = 0
WM.modules.GearScore.OnModuleOff = function() offCalls = offCalls + 1 end
WM:SetModuleOn("GearScore", true)
WM:SetModuleOn("GearScore", false)
check("turning off calls OnModuleOff", offCalls == 1 and not WM:IsModuleOn("GearScore"))
-- Modules with a switch of their own follow
WM:SetModuleOn("Hazards", false)
check("a module's own switch follows", env.HazardsDB.enabled == false)
WM:SetModuleOn("Hazards", true)
check("... back on", env.HazardsDB.enabled == true)
-- Parts follow their parent
check("class parts are off while Class Tools is", not WM:IsModuleOn("ClassWarlock") and not WM:IsModuleOn("SwingTimer"))
WM:SetModuleOn("ClassTools", true)
check("Class Tools on: its parts start (a new character too)", WM:IsModuleOn("ClassWarlock") and WM:IsModuleOn("SwingTimer")
    and WM:IsModuleOn("ClassGeneral") and started.ClassTools == 1 and started.ClassWarlock == 1 and started.SwingTimer == 1)
c.modules.ClassWarlock = false
check("a part can still be off on its own", not WM:IsModuleOn("ClassWarlock") and WM:IsModuleOn("ClassGeneral"))
c.modules.ClassWarlock = nil
-- Commands for a module that's off
W.printed = {}
check("a module that's off can't be used", WM:UsableModule("GearScore") == nil and Said("is off on this character"))
check("one that's on can", WM:UsableModule("Hazards") == WM.modules.Hazards)
W.printed = {}
env.SlashCmdList.WATCHINGMACHINE("crits")
check("its slash command says how to turn it on", Said("Crit Tracker is off on this character"))
W.printed = {}
env.SlashCmdList.WATCHINGMACHINE("gear")
check("/wmachine gear is Gear Sets (not ArmorySnap)", Said("Gear Sets is off on this character") and not Said("ArmorySnap"))

-- ---- The welcome window ----
W.printed = {}
WM.Setup:OnLogin()
local wel = env.WM_SetupWelcome
check("welcome shown for a new character", wel and wel:IsShown())
local noteText
for _, w in ipairs(wel.layout.widgets) do
    local t = w.GetText and w:GetText()
    if type(t) == "string" and t:find("Everything is off", 1, true) then noteText = t end
end
check("explains everything is off", noteText ~= nil)
WM.Setup:Later()
check("Later: not asked again, told how", c.setup == "later" and not wel:IsShown() and Said("/wmachine setup"))
W.printed = {}
WM.Setup:OnLogin()
check("not shown after Later", not wel:IsShown())

-- ---- Quick setup ----
local q = WM.Setup:OpenQuick()
check("quick: a box per module", q:IsShown() and q.draft.Hazards == true and q.draft.LootBrowser == true)
WM.Setup:ApplyPreset("raid")
check("preset: raiding", q.draft.BuffCheck and q.draft.ClassTools and not q.draft.Recruiter)
WM.Setup:ApplyPreset("none")
q.draft.ChatFilter, q.draft.KeywordMonitor = true, true
local on = WM.Setup:ApplyQuick()
check("quick: applied", WM:IsModuleOn("ChatFilter") and WM:IsModuleOn("KeywordMonitor") and not WM:IsModuleOn("Hazards")
    and not WM:IsModuleOn("ClassTools") and #on == 2 and c.setup == "done")
check("quick: started what's on", started.ChatFilter == 1 and started.KeywordMonitor == 1)
check("links shown", WM.Setup.LinksText("KeywordMonitor"):find("Chat Filter", 1, true) ~= nil)

-- ---- Guided setup ----
local pageCalls = 0
WM.modules.Hazards.SetupPage = function(_, L)
    pageCalls = pageCalls + 1
    L:Checkbox({ label = "Drowning", get = function() return env.HazardsDB.drowning end, set = function(v) env.HazardsDB.drowning = v end })
end
local g = WM.Setup:OpenGuided()
check("guided: opens on the introduction", g:IsShown() and g.index == 1 and #g.pages == #WM.Setup:Modules() + 2)
check("guided: back is off on the first page", g.backBtn:GetAlpha() < 1)
local hzIndex
for i, p in ipairs(g.pages) do if p.name == "Hazards" then hzIndex = i end end
WM.Setup:ShowStep(hzIndex)
check("guided: the module's page", g.index == hzIndex and pageCalls == 1)
local box, drown
for _, w in ipairs(g.layout.widgets) do
    local t = rawget(w, "Text") and w.Text:GetText()
    if t and t:find("Turn on Hazard Alerts", 1, true) then box = w end
    if t == "Drowning" then drown = w end
end
check("guided: a switch to turn it on", box and not box:GetChecked())
W.click(box)
check("guided: ticking turns it on now", WM:IsModuleOn("Hazards"))
check("guided: the module's own settings", drown ~= nil)
W.click(drown)
check("guided: settings saved for this character", env.HazardsDB.drowning == (drown:GetChecked() and true or false))
WM.Setup:Go(-1)
WM.Setup:Go(1)
check("guided: pages are built once", pageCalls == 1)
WM.Setup:ShowStep(#g.pages)
check("guided: the last page says Finish", g.nextBtn:GetText() == "Finish")
WM.Setup:Go(1)
check("guided: finish", not g:IsShown() and c.setup == "done" and c.setupHow == "guided")
-- Every real module's page builds without errors
errors = {}
for i = 2, #g.pages - 1 do WM.Setup:ShowStep(i) end
check("every page builds", #errors == 0)
for _, e in ipairs(errors) do print("  " .. e) end

-- ---- Copy another character ----
local vetProfile = rawget(env.HazardsDB, "__wm").profiles["Veteran-Spineshatter"]
check("characters to copy from", (function()
    for _, k in ipairs(P:Characters()) do if k == "Veteran-Spineshatter" then return true end end
end)())
local reloaded = false
env.ReloadUI = function() reloaded = true end
WM.Setup:CopyFrom("Veteran-Spineshatter")
check("copy with modules running: reloads", reloaded)
check("copy: settings", env.HazardsDB.trivialPct == vetProfile.trivialPct and env.HazardsDB.trivialPct == 3)
check("copy: modules", WM:IsModuleOn("LootBrowser") and WM:IsModuleOn("Hazards"))

-- ---- Dashboard ----
WM:CreateDashboard()
WM:CreateModuleCards()
WM.dashboard:Show()
WM:SetModuleOn("Recruiter", false)
WM:UpdateDashboard()
local card = WM.dashboard.moduleCards.Recruiter
check("dashboard: off on this character", card.statusText:GetText():find("Off on this character", 1, true)
    and not card.switch:GetChecked())
W.click(card.switch)
check("dashboard: the switch turns it on", WM:IsModuleOn("Recruiter"))

-- ---- Hide inactive ----
local hb = WM.dashboard.hideInactiveBtn
check("hide inactive: a button at the top", hb and hb:GetText() == "Hide inactive")
WM:SetModuleOn("Recruiter", false)
WM:SetModuleOn("GuildInvite", true)
W.click(hb)
local cards2 = WM.dashboard.moduleCards
check("hide inactive: off modules' cards hidden", not cards2.Recruiter:IsShown() and cards2.GuildInvite:IsShown()
    and hb:GetText() == "Show all")
check("hide inactive: saved for this character", c.hideInactive == true)
local function HeaderFor(title)
    for gi, g in ipairs(WM.MODULE_GROUPS) do if g.title == title then return WM.dashboard.groupHeaders[gi] end end
end
local savedMods = {}
for k, v in pairs(c.modules) do savedMods[k] = v end
for _, n in ipairs(WM.MODULE_GROUPS[3].modules) do WM:SetModuleOn(n, false) end
check("hide inactive: a group with nothing on goes", not HeaderFor(WM.MODULE_GROUPS[3].title):IsShown())
WM:SetModuleOn("GuildInvite", false)
check("hide inactive: turning a switch off hides its card", not cards2.GuildInvite:IsShown())
for _, m in ipairs(WM.Setup:Modules()) do WM:SetModuleOn(m.name, false) end
check("hide inactive: nothing on says so", WM.dashboard.noneOnText:IsShown())
local w, h = WM:DashboardFitSize()
check("hide inactive: Fit sizes to what's shown", h < 400)
W.click(hb)
check("show all: every card back", cards2.Recruiter:IsShown() and cards2.GuildInvite:IsShown()
    and not WM.dashboard.noneOnText:IsShown() and hb:GetText() == "Hide inactive" and c.hideInactive == false)
for k, v in pairs(savedMods) do WM:SetModuleOn(k, v) end

-- ---- Running the setup again ----
local function Snapshot()
    local out = {}
    for _, m in ipairs(WM.Setup:Modules()) do out[m.name] = WM:IsModuleOn(m.name) end
    return out
end
local function Same(a, b, except)
    for k, v in pairs(a) do if k ~= except and b[k] ~= v then return false end end
    return true
end
c.setup = "done"
local dashSetup
for _, btn in ipairs(WM.dashboard.footerButtons) do if btn:GetText() == "Setup" then dashSetup = btn end end
W.click(dashSetup)
check("re-run: the dashboard's Setup button", wel:IsShown())
local found
for _, w in ipairs(wel.layout.widgets) do
    local t = w.GetText and w:GetText()
    if type(t) == "string" and t:find("current setup is kept", 1, true) then found = true end
end
check("re-run: says your setup is kept", found)
wel:Hide()
env.SlashCmdList.WATCHINGMACHINE("resetup")
check("re-run: /wmachine resetup", wel:IsShown())
wel:Hide()
-- Quick: what's on is ticked; applying without changes changes nothing
local before = Snapshot()
q = WM.Setup:OpenQuick()
check("re-run quick: ticks what's on now", Same(before, q.draft))
WM.Setup:ApplyQuick()
check("re-run quick: nothing changed", Same(before, Snapshot()))
-- ... and one change changes only that
q = WM.Setup:OpenQuick()
local flip = before.Attunements and false or true
q.draft.Attunements = flip
WM.Setup:ApplyQuick()
local after = Snapshot()
check("re-run quick: only the change", after.Attunements == flip and Same(before, after, "Attunements"))
-- Guided: each page shows what you have now
env.HazardsDB.drowning = false
local hzOn = WM:IsModuleOn("Hazards")
before = Snapshot()
g = WM.Setup:OpenGuided()
WM.Setup:ShowStep(hzIndex)
local turnOn, drownBox
for _, w in ipairs(g.layout.widgets) do
    local t = rawget(w, "Text") and w.Text:GetText()
    if t and t:find("Turn on Hazard Alerts", 1, true) then turnOn = w end
    if t == "Drowning" then drownBox = w end
end
check("re-run guided: the switch shows what's on", turnOn:GetChecked() == hzOn)
check("re-run guided: settings show their values", drownBox:GetChecked() == false)
env.HazardsDB.drowning = true
WM.Setup:Go(1); WM.Setup:Go(-1)
check("re-run guided: values re-read each time", drownBox:GetChecked() == true)
for i = WM.Setup.guided and 1 or g.index, #g.pages - 1 do WM.Setup:Go(1) end
WM.Setup:Go(1)
check("re-run guided: paging through changes nothing", not g:IsShown() and Same(before, Snapshot()) and env.HazardsDB.drowning == true)

-- ---- What's new: a module added since this character last looked ----
local c = WM:CharState()
check("finishing the setup marks every module as seen", type(c.known) == "table" and c.known.FrameMover
    and #WM.Setup:NewModules() == 0)
c.known.FrameMover = nil            -- as if this version had just added it
check("a module it hasn't seen is new", table.concat(WM.Setup:NewModules(), ",") == "FrameMover")
WM.Setup:OnLogin()
local wn = env.WM_SetupWhatsNew
check("login shows what's new", wn ~= nil and wn:IsShown())
local fmSwitch
for _, w in ipairs(wn.layout.widgets) do
    local t = rawget(w, "Text") and w.Text:GetText()
    if t and t:find("Turn on Frame Mover", 1, true) then fmSwitch = w end
end
check("what's new: the module's page, with its switch", fmSwitch ~= nil and fmSwitch:GetChecked() == WM:IsModuleOn("FrameMover"))
W.click(fmSwitch)
check("what's new: the switch works", WM:IsModuleOn("FrameMover") == fmSwitch:GetChecked())
W.click(wn.doneBtn)
check("Done: seen, closed", not wn:IsShown() and #WM.Setup:NewModules() == 0)
wn:Hide()
WM.Setup:OnLogin()
check("not shown again once seen", not wn:IsShown())
c.known = nil
WM.Setup:OnLogin()
check("a character from before: everything it has counts as seen", not wn:IsShown() and c.known and c.known.Hazards)
W.printed = {}
env.SlashCmdList.WATCHINGMACHINE("setup new")
check("setup new: the last new modules again", wn:IsShown())
wn:Hide()
c.lastNew = nil
env.SlashCmdList.WATCHINGMACHINE("whatsnew")
check("whatsnew with nothing new says so", Said("Nothing new") and not wn:IsShown())

-- ---- Forget a character ----
local me = P.key
local hz = rawget(env.HazardsDB, "__wm")
check("another character has settings", hz.profiles["Veteran-Spineshatter"] ~= nil
    and env.WatchingMachineDB.chars["Veteran-Spineshatter"] ~= nil)
check("can't forget the character you're on", P:DeleteCharacter(me) == false and hz.profiles[me] ~= nil)
local welcomeP = WM.Setup:ShowWelcome()
welcomeP.forget = "Veteran-Spineshatter"
local forgetBtn
for _, w in ipairs(welcomeP.layout.widgets) do
    if w.GetText and w:GetText() == "Forget its settings" then forgetBtn = w end
end
check("welcome window: forget a character", forgetBtn ~= nil)
W.click(forgetBtn)
check("forgotten: its settings and switches", hz.profiles["Veteran-Spineshatter"] == nil
    and env.WatchingMachineDB.chars["Veteran-Spineshatter"] == nil and Said("Forgot Veteran-Spineshatter"))
check("records about all characters kept", env.AltTrackerDB.chars["Veteran-Spineshatter"] ~= nil)
local listed = false
for _, k in ipairs(P:Characters()) do if k == "Veteran-Spineshatter" then listed = true end end
check("no longer listed", not listed)
check("forgetting again finds nothing", WM.Setup:Forget("Veteran-Spineshatter") == false)
welcomeP:Hide()
local sp = WM:CreateSettingsPanel()
local inSettings = false
for _, w in ipairs(sp.layout.widgets) do
    if w.GetText and w:GetText() == "Forget its settings" then inSettings = true end
end
check("settings window: forget a character too", inSettings)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
