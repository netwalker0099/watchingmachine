-- Turning Buff Check, Debuff Tracker and Aura Range off and on for one
-- character: the guided setup page builds before the module has started,
-- and while a module is off its events, polls and frames do nothing.
-- Usage: lua5.1 test_onoff_raid1.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local errors = {}
env.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
-- Remember every frame each module makes (their event frames are local)
local created = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...)
    local f = realCreate(...)
    created[#created + 1] = f
    return f
end

local buffs = {}                  -- unit -> { aura names }
local units = { player = { name = "Me", class = "MAGE" } }
local grouped = false
env.UnitBuff = function(u, i) return buffs[u] and buffs[u][i] end
env.UnitDebuff = function() return nil end
env.UnitExists = function(u) return units[u] ~= nil end
env.UnitName = function(u) return units[u] and units[u].name end
env.UnitClass = function(u) local c = units[u] and units[u].class; return c, c end
env.UnitIsConnected = function(u) return units[u] ~= nil end
env.UnitIsDeadOrGhost = function() return false end
env.UnitIsDead = function() return false end
env.UnitAffectingCombat = function() return false end
env.UnitCanAttack = function() return false end
env.UnitGUID = function() return nil end
env.IsInRaid = function() return false end
env.IsInGroup = function() return grouped end
env.GetNumGroupMembers = function() return grouped and 2 or 0 end
env.IsInInstance = function() return true, "raid" end
env.UnitIsGroupLeader = function() return false end
env.UnitIsGroupAssistant = function() return false end
env.GetSpellInfo = function() return nil end
env.PlaySound = function() end
local clock = 100
env.GetTime = function() return clock end
env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
env.GetInventoryItemLink = function() return nil end
env.GetItemStats = function() return nil end
env.C_TooltipInfo = false
local chat, addonMsgs = {}, {}
env.SendChatMessage = function(m) chat[#chat + 1] = m end
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(_, m) addonMsgs[#addonMsgs + 1] = m end }

W.load("Core.lua")
W.load("UI.lua")
local first = {}
for _, f in ipairs({ "BuffCheck", "DebuffTracker", "AuraRange" }) do
    first[f] = #created + 1
    W.load("Modules/" .. f .. ".lua")
end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Said(text)
    for i = 1, #W.printed do if tostring(W.printed[i]):find(text, 1, true) then return true end end
end
-- Build a module's setup page on a fresh panel; returns its layout
local n = 0
local function Page(M)
    n = n + 1
    local p = WM.UI:CreatePanel({ name = "WM_TestSetup" .. n, title = "t" })
    local page = p:NewPage()
    local ok, err = pcall(M.SetupPage, M, page.layout)
    if not ok then io.write("SetupPage error: ", tostring(err), "\n") end
    page.layout:Reflow()
    return page.layout, ok
end
local function Box(L, label)
    for _, w in ipairs(L.widgets) do
        if type(w.Text) == "table" and w.Text.GetText and tostring(w.Text:GetText() or ""):find(label, 1, true) then return w end
    end
end

-- ================= Buff Check =================
local BC = WM.modules.BuffCheck
check("BuffCheck: never initialised", env.BuffCheckDB == nil)
local L, ok = Page(BC)
check("BuffCheck: setup page builds before start", ok and env.BuffCheckDB ~= nil)
local cb = Box(L, "Announce to raid")
check("BuffCheck: announce box reads the setting", cb and cb:GetChecked() == (env.BuffCheckDB.announceToRaid and true or false))
local was = env.BuffCheckDB.announceToRaid
W.click(cb)
check("BuffCheck: announce box writes the setting", env.BuffCheckDB.announceToRaid == not was)
cb = Box(L, "Flask")
W.click(cb)
check("BuffCheck: consumable box writes the check", env.BuffCheckDB.checkedGroups.flask == true)
env.BuffCheckDB.checkedGroups.flask = false

BC:Initialize()
local bcEvents = created[first.BuffCheck]
W.printed = {}
W.fire(bcEvents, "OnEvent", "READY_CHECK", "Other")
check("BuffCheck: a ready check reports missing food", Said("Missing Food Buff: Me"))
BC:CreateUI():Show()
WM:SetModuleOn("BuffCheck", false)
check("BuffCheck: off closes the window", not BC.mainFrame:IsShown())
W.printed = {}
W.fire(bcEvents, "OnEvent", "READY_CHECK", "Other")
BC:RunCheck(false)
check("BuffCheck: off ignores ready checks", #W.printed == 0)
WM:SetModuleOn("BuffCheck", true)
check("BuffCheck: on again agrees with its own switch", BC:IsModuleEnabled())
W.fire(bcEvents, "OnEvent", "READY_CHECK", "Other")
check("BuffCheck: on again reports", Said("Missing Food Buff: Me"))

-- ================= Debuff Tracker =================
local DT = WM.modules.DebuffTracker
check("DebuffTracker: never initialised", env.DebuffTrackerDB == nil)
L, ok = Page(DT)
check("DebuffTracker: setup page builds before start", ok and env.DebuffTrackerDB ~= nil and DT.trackerFrame == nil)
cb = Box(L, "Show only in raid")
check("DebuffTracker: raid-only box reads the setting", cb and cb:GetChecked() == true)
W.click(cb)
check("DebuffTracker: raid-only box writes the setting", env.DebuffTrackerDB.showOnlyInRaid == false)
cb = Box(L, "Shear")
W.click(cb)
check("DebuffTracker: Shear box writes the setting", env.DebuffTrackerDB.shearMonitor == false)
env.DebuffTrackerDB.shearMonitor = true
env.DebuffTrackerDB.hideWhenNoTarget = false

DT:Initialize()
W.runTimers()
local tf = DT.trackerFrame
local sr = DT.srEventFrame
DT:UpdateVisibility()
check("DebuffTracker: tracker shows", tf:IsShown())
units.party1 = { name = "Friend", class = "PRIEST" }
grouped = true
addonMsgs = {}
W.fire(sr, "OnEvent", "CHAT_MSG_ADDON", "WMSR", "Q", "PARTY", "Friend")
check("DebuffTracker: answers a raid SR check", addonMsgs[1] == "R:0:0")
WM:SetModuleOn("DebuffTracker", false)
check("DebuffTracker: off hides the tracker", not tf:IsShown())
W.fire(tf, "OnEvent", "PLAYER_TARGET_CHANGED")
DT:UpdateVisibility()
check("DebuffTracker: off stays hidden on events", not tf:IsShown())
addonMsgs = {}
clock = clock + 10
W.fire(sr, "OnEvent", "CHAT_MSG_ADDON", "WMSR", "Q", "PARTY", "Friend")
check("DebuffTracker: off ignores addon messages", #addonMsgs == 0)
-- A raid SR check under way is dropped
WM:SetModuleOn("DebuffTracker", true)
check("DebuffTracker: on again shows the tracker", tf:IsShown())
DT:StartRaidShadowResistScan()
check("DebuffTracker: raid SR check running", DT:IsRaidShadowResistScanning())
WM:SetModuleOn("DebuffTracker", false)
check("DebuffTracker: off stops the raid SR check", not DT:IsRaidShadowResistScanning())
W.runTimers()
WM:SetModuleOn("DebuffTracker", true)
check("DebuffTracker: on again agrees with its own switch", DT:IsModuleEnabled())
clock = clock + 10
addonMsgs = {}
W.fire(sr, "OnEvent", "CHAT_MSG_ADDON", "WMSR", "Q", "PARTY", "Friend")
check("DebuffTracker: on again answers", addonMsgs[1] == "R:0:0")

-- ================= Aura Range =================
local AR = WM.modules.AuraRange
check("AuraRange: never initialised", env.AuraRangeDB == nil)
L, ok = Page(AR)
check("AuraRange: setup page builds before start", ok and env.AuraRangeDB ~= nil and AR.alertFrame == nil)
cb = Box(L, "Play sound")
check("AuraRange: sound box reads the setting", cb and cb:GetChecked() == true)
W.click(cb)
check("AuraRange: sound box writes the setting", env.AuraRangeDB.soundEnabled == false)
cb = Box(L, "Paladin auras")
W.click(cb)
check("AuraRange: aura box writes the setting", env.AuraRangeDB.trackedAuras.paladin == true)

units.party1 = { name = "Tree", class = "DRUID" }
grouped = true
buffs.player = { "Moonkin Aura" }
AR:Initialize()
local arEvents = created[first.AuraRange]
W.runTimers()
local af = AR.alertFrame
check("AuraRange: no alert to start with", not af:IsShown())
buffs.player = {}
W.fire(arEvents, "OnEvent", "UNIT_AURA", "player")
check("AuraRange: walking out of range alerts", af:IsShown())
WM:SetModuleOn("AuraRange", false)
check("AuraRange: off hides the alert", not af:IsShown())
buffs.player = { "Moonkin Aura" }
W.fire(arEvents, "OnEvent", "UNIT_AURA", "player")
buffs.player = {}
W.fire(arEvents, "OnEvent", "UNIT_AURA", "player")
W.fire(arEvents, "OnEvent", "PLAYER_ENTERING_WORLD")
W.runTimers()
check("AuraRange: off ignores aura changes", not af:IsShown())
buffs.player = { "Moonkin Aura" }
WM:SetModuleOn("AuraRange", true)
check("AuraRange: on again agrees with its own switch", AR:IsModuleEnabled())
buffs.player = {}
W.fire(arEvents, "OnEvent", "UNIT_AURA", "player")
check("AuraRange: on again alerts", af:IsShown())

check("no errors reported", #errors == 0)
for _, e in ipairs(errors) do io.write("error: ", e, "\n") end

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
