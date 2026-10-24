-- Class Tools and its parts (General checks, warlock, mage, shaman, paladin,
-- the flyout buttons, the swing timer): the guided setup page on a module
-- that has never started, for a warlock, a mage, a shaman and a priest;
-- turning Class Tools off silences the warnings, hides the buttons and the
-- swing timer and idles the shared events; turning it on brings them back.
-- Usage: lua5.1 test_onoff_class.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

function W.Frame:RegisterForClicks(...) self._clicks = { ... } end
function W.Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function W.Frame:GetAttribute(k) return self._attr and self._attr[k] end
function W.Frame:RegisterEvent(e) self._events = self._events or {}; self._events[e] = true end
function W.Frame:UnregisterAllEvents() self._events = {} end
local allFrames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); allFrames[#allFrames + 1] = f; return f end
local function FrameFor(event)
    for _, f in ipairs(allFrames) do
        if f._events and f._events[event] and f._scripts.OnEvent then return f end
    end
end
local function Frames() return #allFrames end

local book = {}
env.GetSpellBookItemName = function(i) return book[i] end
env.GetSpellBookItemTexture = function(i) return "Interface\\Icons\\Slot" .. i end
env.GetSpellInfo = function() return nil end
env.InCombatLockdown = function() return false end
env.GetCVarBool = function() return true end
env.C_Item = { GetItemCount = function() return 0 end }
env.UnitBuff = function() return nil end
env.UnitIsDeadOrGhost = function() return false end
env.UnitIsDead = function() return false end
env.UnitExists = function() return false end
env.UnitAffectingCombat = function() return false end
env.UnitPowerType = function() return 0 end
env.GetNumTalentTabs = function() return 3 end
env.GetNumTalents = function() return 0 end
env.GetTalentInfo = function() return nil end
env.IsPlayerSpell = function() return false end
env.IsSpellKnown = function() return false end
env.UnitGUID = function() return "Player-1-1" end
env.UnitAttackSpeed = function() return 2.6, nil end
env.PlaySound = function() end
local myClass = { "Warlock", "WARLOCK" }
env.UnitClass = function() return myClass[1], myClass[2] end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua", "Modules/SwingTimer.lua",
                     "Modules/ClassGeneral.lua", "Modules/ClassWarlock.lua", "Modules/ClassMage.lua",
                     "Modules/ClassShaman.lua", "Modules/ClassPaladin.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Gen, Lock, Mage = WM.modules.ClassTools, WM.modules.ClassGeneral, WM.modules.ClassWarlock, WM.modules.ClassMage
local Sham, Pal, Swing = WM.modules.ClassShaman, WM.modules.ClassPaladin, WM.modules.SwingTimer
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local pageN = 0
local function Page()
    pageN = pageN + 1
    local p = WM.UI:CreatePanel({ name = "WM_TestSetupClass" .. pageN, title = "t" })
    local page = p:NewPage()
    local ok, err = pcall(CT.SetupPage, CT, page.layout)
    if not ok then io.write("SetupPage error: ", tostring(err), "\n") end
    page.layout:Reflow()
    return page, ok
end
local function Box(page, label)
    for _, w in ipairs(page.layout.widgets) do
        local t = rawget(w, "Text") and w.Text:GetText()
        if t == label then return w end
    end
end
local function Texts(page)
    local out = {}
    for _, w in ipairs(page.layout.widgets) do
        local t = w.GetText and w:GetText()
        if type(t) == "string" then out[#out + 1] = t end
        t = rawget(w, "Text") and w.Text:GetText()
        if type(t) == "string" then out[#out + 1] = t end
    end
    return table.concat(out, "\n")
end
-- The dropdown whose options include this text
local function Dropdown(page, optionText)
    for _, w in ipairs(page.layout.widgets) do
        local dd = rawget(w, "dropdown")
        if dd then
            for _, item in ipairs(W.openMenu(dd)) do
                if item.text == optionText then return w, dd end
            end
        end
    end
end
local function Pick(dd, text)
    for _, item in ipairs(W.openMenu(dd)) do
        if item.text == text then item.func(); return true end
    end
end

-- ================= SETUP PAGE: WARLOCK, NEVER STARTED =================
check("nothing initialised yet", env.ClassToolsDB == nil and env.GeneralChecksDB == nil and env.WarlockToolsDB == nil)
local before = Frames()
local page, ok = Page()
check("warlock: page builds before Class Tools has started", ok)
check("warlock: no alert frame, buttons or swing bars made",
    rawget(env, "WM_ClassToolsAlertFrame") == nil and rawget(env, "WM_WarlockAnchor") == nil
    and rawget(env, "WM_SwingTimerFrame") == nil)
check("warlock: defaults filled in", env.ClassToolsDB and env.GeneralChecksDB and env.GeneralChecksDB.potionAt == 3000
    and env.WarlockToolsDB and env.WarlockToolsDB.demonDir == "LEFT")
check("warlock: features registered without starting", #CT:GetFeatures("WARLOCK") > 0 and #CT:GetFeatures("GENERAL") > 0)
local text = Texts(page)
check("warlock: own class's tools", text:find("Warlock", 1, true) and text:find("soulstone", 1, true)
    and Box(page, "Warn if armor spell is missing") and Box(page, "Show the warlock button"))
check("warlock: no other class's tools", not Box(page, "Show the portal / teleport button")
    and not Box(page, "Show the totem button") and not Box(page, "Warn if Righteous Fury is missing"))
check("warlock: general checks too", Box(page, "Warn if no flask or elixirs") and Box(page, "Warn to drink a mana potion")
    and Box(page, "Warn to use a Dark / Demonic Rune"))
check("warlock: feature descriptions explained", text:find("Demonic Sacrifice", 1, true) and text:find("CHECK YOURSELF", 1, true))
check("warlock: other characters mentioned", text:find("other characters", 1, true))
check("warlock: swing timer only by choice", Box(page, "Swing timer for every class and spec")
    and not Box(page, "Shaman weapon sync mark") and not Box(page, "Lock the swing timer"))
check("warlock: flyout options for a class with buttons", Box(page, "Lock flyout buttons"))

-- The user's example: potion alert on, rune alert off, armour icons on the
-- warlock button but not the demons
local potion, rune = Box(page, "Warn to drink a mana potion"), Box(page, "Warn to use a Dark / Demonic Rune")
check("potion and rune on by default", potion:GetChecked() and rune:GetChecked())
W.click(rune)
check("rune alert off", not CT:IsEnabled("GENERAL", "manarune") and CT:IsEnabled("GENERAL", "manapotion"))
local demons, armors = Box(page, "Show the demon summon icons"), Box(page, "Show the armor icons")
check("direction switches", demons and armors and demons:GetChecked() and armors:GetChecked())
W.click(demons)
check("demons left off the button, armours kept", env.WarlockToolsDB.demonDir == "HIDDEN" and env.WarlockToolsDB.armorDir == "UP")
W.click(demons)
check("demons back where they were", env.WarlockToolsDB.demonDir == "LEFT")
W.click(demons)
local _, potionDD = Dropdown(page, "4000")
check("potion threshold dropdown", potionDD and Pick(potionDD, "4000") and env.GeneralChecksDB.potionAt == 4000)
local lockBox = Box(page, "Lock the warning frame in place")
W.click(lockBox)
check("warning frame lock", env.ClassToolsDB.alertLocked == true)
W.click(lockBox)
check("still nothing started", rawget(env, "WM_ClassToolsAlertFrame") == nil and rawget(env, "WM_WarlockAnchor") == nil
    and rawget(env, "WM_SwingTimerFrame") == nil)

-- ================= SETUP PAGE: MAGE, SHAMAN, PRIEST =================
myClass = { "Mage", "MAGE" }
page, ok = Page()
text = Texts(page)
check("mage: page builds", ok and Box(page, "Show the portal / teleport button") and Box(page, "Show the portal icons")
    and not Box(page, "Show the warlock button"))
local portals = Box(page, "Show the portal icons")
W.click(portals)
check("mage: portals left off", env.MageToolsDB.portalDir == "HIDDEN")
W.click(portals)
check("mage: portals back", env.MageToolsDB.portalDir == "LEFT")
local mageArmor = Box(page, "Warn if armor spell is missing")
W.click(mageArmor)
check("mage: armour warning off", not CT:IsEnabled("MAGE", "armor") and CT:IsEnabled("WARLOCK", "armor"))
W.click(mageArmor)

myClass = { "Shaman", "SHAMAN" }
page, ok = Page()
check("shaman: page builds with the totem button and sync", ok and Box(page, "Show the totem button")
    and Box(page, "Shaman weapon sync mark") and Box(page, "Lock the swing timer"))
local _, setDD = Dropdown(page, "Tremor")
check("shaman: set in use", setDD and Pick(setDD, "Tremor") and env.ShamanToolsDB.selected == 4)

myClass = { "Priest", "PRIEST" }
page, ok = Page()
text = Texts(page)
check("priest: page builds, says nothing class-specific yet", ok and text:find("Nothing just for Priests", 1, true)
    and Box(page, "Warn if no flask or elixirs") and not Box(page, "Lock flyout buttons"))

myClass = { "Warrior", "WARRIOR" }
page, ok = Page()
check("warrior: no mana section", ok and not Box(page, "Warn to drink a mana potion") and Box(page, "Swing timer"))
check("setup pages made no module frames", rawget(env, "WM_ClassToolsAlertFrame") == nil
    and rawget(env, "WM_MageUtilityAnchor") == nil and rawget(env, "WM_TotemAnchor") == nil
    and rawget(env, "WM_SwingTimerFrame") == nil)

-- ================= ON / OFF (warlock) =================
myClass = { "Warlock", "WARLOCK" }
CT:DetectClass()
book = { "Fel Armor", "Summon Imp" }
for _, m in ipairs({ CT, Gen, Swing, Lock, Mage, Sham, Pal }) do m:Initialize() end
Lock:UpdateButton()
local alertFrame, anchor, swingFrame = env.WM_ClassToolsAlertFrame, env.WM_WarlockAnchor, env.WM_SwingTimerFrame
check("started: frames made", alertFrame and anchor and swingFrame)
check("started: the warlock button shows", anchor:IsShown())
CT:RunMonitors()
check("started: the armour warning shows", CT:GetActiveAlertCount() == 1 and alertFrame:IsShown())
-- The monitor tick: the frame whose OnUpdate runs the monitors
local tick, runs = nil, 0
local realRun = CT.RunMonitors
CT.RunMonitors = function(self) runs = runs + 1; return realRun(self) end
for _, f in ipairs(allFrames) do
    if not tick and f._scripts.OnUpdate and f ~= swingFrame then
        local was = runs
        pcall(f._scripts.OnUpdate, f, 1)
        if runs > was then tick = f end
    end
end
local swingEvents = FrameFor("PLAYER_ENTER_COMBAT")
local flyEvents = FrameFor("BAG_UPDATE")
check("event frames found", swingEvents and flyEvents and tick)
local badges = 0
local realBadges = WM.Flyout.UpdateAllBadges
WM.Flyout.UpdateAllBadges = function() badges = badges + 1 end
flyEvents._scripts.OnEvent(flyEvents, "BAG_UPDATE")
check("on: bag changes update the shard counts", badges == 1)
Swing:Test()
check("on: swing timer test shows", swingFrame:IsShown())
Swing:EndTest()

WM:SetModuleOn("ClassTools", false)
check("off: parts off with it", not WM:IsModuleOn("ClassWarlock") and not WM:IsModuleOn("SwingTimer")
    and not WM:IsModuleOn("ClassGeneral"))
check("off: warnings cleared and the frame hidden", CT:GetActiveAlertCount() == 0 and not alertFrame:IsShown())
check("off: the warlock button hidden", not anchor:IsShown())
check("off: swing bars hidden", not swingFrame:IsShown())
CT:RunMonitors()
CT:SetAlert("x", "should not show")
check("off: monitors and alerts do nothing", CT:GetActiveAlertCount() == 0 and not alertFrame:IsShown())
local runsBefore = runs
for _ = 1, 3 do tick._scripts.OnUpdate(tick, 1) end
check("off: the monitor tick idles", runs == runsBefore and CT:GetActiveAlertCount() == 0)
flyEvents._scripts.OnEvent(flyEvents, "BAG_UPDATE")
check("off: bag changes ignored", badges == 1)
swingEvents._scripts.OnEvent(swingEvents, "PLAYER_ENTER_COMBAT")
check("off: swing events ignored", not Swing:IsAttacking())
check("off: swing timer stops reading events", not (swingEvents._events and swingEvents._events.COMBAT_LOG_EVENT_UNFILTERED))
Lock:UpdateButton()
check("off: the button stays hidden", not anchor:IsShown())
CT:Toggle()
check("off: the window doesn't open", rawget(env, "WM_ClassToolsFrame") == nil or not env.WM_ClassToolsFrame:IsShown())

WM:SetModuleOn("ClassTools", true)
check("on again: parts back on", WM:IsModuleOn("ClassWarlock") and WM:IsModuleOn("SwingTimer"))
check("on again: the warlock button back", anchor:IsShown())
tick._scripts.OnUpdate(tick, 1)
check("on again: the tick runs the monitors", runs == runsBefore + 1)
check("on again: the armour warning back", CT:GetActiveAlertCount() == 1 and alertFrame:IsShown())
flyEvents._scripts.OnEvent(flyEvents, "BAG_UPDATE")
check("on again: shard counts update", badges == 2)
check("on again: swing timer reads events", swingEvents._events and swingEvents._events.COMBAT_LOG_EVENT_UNFILTERED)
swingEvents._scripts.OnEvent(swingEvents, "PLAYER_ENTER_COMBAT")
check("on again: swing events handled", Swing:IsAttacking())
WM.Flyout.UpdateAllBadges = realBadges

-- Just the warlock part off: its warning and button go, General stays
WM:SetModuleOn("ClassWarlock", false)
CT:RunMonitors()
check("warlock part off: its warning and button go", CT:GetActiveAlertCount() == 0 and not anchor:IsShown()
    and WM:IsModuleOn("ClassGeneral"))
WM:SetModuleOn("ClassWarlock", true)
check("warlock part on: button back", anchor:IsShown())

-- Turned off in combat: the button can't be hidden until combat ends
env.InCombatLockdown = function() return true end
WM:SetModuleOn("ClassTools", false)
check("off in combat: waits", anchor:IsShown())
env.InCombatLockdown = function() return false end
flyEvents._scripts.OnEvent(flyEvents, "PLAYER_REGEN_ENABLED")
check("off in combat: hidden once combat ends", not anchor:IsShown())
WM:SetModuleOn("ClassTools", true)

-- ================= ON / OFF (mage buttons, shaman editor) =================
myClass = { "Mage", "MAGE" }
book = { "Portal: Ironforge", "Molten Armor" }
Mage:Initialize()
Mage:UpdateButtons()
local portal = env.WM_MagePortalAnchor
check("mage: portal button shows", portal and portal:IsShown())
WM:SetModuleOn("ClassTools", false)
check("mage: off hides it", not portal:IsShown())
WM:SetModuleOn("ClassTools", true)
check("mage: on shows it", portal:IsShown())

myClass = { "Shaman", "SHAMAN" }
book = { "Searing Totem" }
Sham:Initialize()
Sham:ToggleEditor()
check("shaman: editor opens", env.WM_TotemSetsFrame and env.WM_TotemSetsFrame:IsShown())
WM:SetModuleOn("ClassTools", false)
check("shaman: off closes the editor and the button", not env.WM_TotemSetsFrame:IsShown()
    and not env.WM_TotemAnchor:IsShown())
Sham:ToggleEditor()
check("shaman: editor won't open while off", not env.WM_TotemSetsFrame:IsShown())
WM:SetModuleOn("ClassTools", true)
check("shaman: button back", env.WM_TotemAnchor:IsShown())

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
