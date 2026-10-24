-- Turning modules off and on, and their guided-setup pages: GearScore,
-- Attunements, Hazard Alerts, Gear Sets and Crit Tracker. Each page builds
-- on a module that has never started; turned off, each one's events, hooks
-- and timers do nothing and its frames hide; turned on, it works again.
-- Usage: lua5.1 test_onoff_raid3.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now, clock = 1800000000, 1000
env.GetServerTime = function() return now end
env.GetTime = function() return clock end
local ME = "Player-1-00000001"
env.UnitName = function(u) if u == "player" then return "Me" elseif u == "mouseover" then return "Magey" end end
env.GetRealmName = function() return "Testrealm" end
env.UnitGUID = function(u) if u == "player" then return ME elseif u == "mouseover" then return "Player-1-00000002" end end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitExists = function(u) return u == "player" or u == "mouseover" end
env.UnitIsPlayer = function(u) return u == "player" or u == "mouseover" end
env.UnitIsUnit = function(a, b) return a == b end
env.UnitLevel = function() return 70 end
env.UnitFactionGroup = function() return "Horde" end
env.UnitHealthMax = function() return 10000 end
env.UnitBuff = function() return nil end
env.UnitDebuff = function() return nil end
env.UnitIsCharmed = function() return false end
env.UnitIsDeadOrGhost = function() return false end
env.UnitCastingInfo = function() return nil end
env.UnitChannelInfo = function() return nil end
env.UnitAffectingCombat = function() return false end
env.InCombatLockdown = function() return false end
env.CursorHasItem = function() return false end
env.SpellIsTargeting = function() return false end
env.CheckInteractDistance = function() return true end
env.CanInspect = function() return true end
local notified = {}
env.NotifyInspect = function(u) notified[#notified + 1] = u end
env.ClearInspectPlayer = function() end
env.GetNumGroupMembers = function() return 0 end
env.SlashCmdList = {}
env.PlaySound = function() end
local sent = {}
env.SendChatMessage = function(m, c) sent[#sent + 1] = { m, c } end
env.IsInGuild = function() return true end
local addonMsgs = {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(p, m, c) addonMsgs[#addonMsgs + 1] = { p, m, c } end }
env.Ambiguate = function(n) return (n:gsub("%-Testrealm$", "")) end
env.math.random = function() return 0.5 end
env.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
env.GetBuildInfo = function() return "2.5.6", "1", "Oct 1 2026", 20506 end
env.GetFactionInfoByID = function(id) return "Faction" .. id, "", 4, 0, 0, 0 end
-- An epic helm, the only thing anyone wears
local HELM = "|cffa335ee|Hitem:1:0:0:0:0:0:0:0|h[Helm]|h|r"
env.C_Item = {
    GetItemInfo = function(l) if tostring(l):find("item:1:") then return "Helm", HELM, 4, 115, 0, "", "", 1, "INVTYPE_HEAD" end end,
    GetItemInfoInstant = function(l) if tostring(l):find("item:1:") then return 1, "Armor", "Plate", "INVTYPE_HEAD" end end,
    GetItemStats = function() return {} end,
    IsEquippableItem = function() return true end,
    GetItemCount = function() return 0 end,
}
env.GetInventoryItemLink = function(_, slot) if slot == 1 then return HELM end end
env.C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() return nil end,
    GetContainerNumFreeSlots = function() return 0, 0 end,
    PickupContainerItem = function() end,
}
env.PickupInventoryItem = function() end
env.IsInventoryItemLocked = function() return false end
local spec = 1
env.GetActiveTalentGroup = function() return spec end
env.GetNumTalentGroups = function() return 2 end
env.IsMounted = function() return false end
env.PaperDollFrame = W.NewFrame("PaperDollFrame")
env.CharacterFrame = W.NewFrame("CharacterFrame")
for _, n in ipairs({ "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Finger0",
    "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard" }) do
    env["Character" .. n .. "Slot"] = W.NewFrame("Character" .. n .. "Slot", env.PaperDollFrame)
end

for _, f in ipairs({ "Core.lua", "UI.lua", "Sounds.lua", "Data/Hazards.lua", "Data/Attunements.lua",
    "Modules/GearScore.lua", "Modules/Attunements.lua", "Modules/Hazards.lua", "Modules/GearSets.lua",
    "Modules/Crits.lua" }) do W.load(f) end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Said(text)
    for i = #W.printed, 1, -1 do if tostring(W.printed[i]):find(text, 1, true) then return W.printed[i] end end
end

-- A setup page, built on its own panel. Returns its controls' specs by
-- label (nil if it failed).
local n = 0
local function Page(M)
    n = n + 1
    local p = WM.UI:CreatePanel({ name = "WM_TestSetup" .. n, title = "t" })
    local page = p:NewPage()
    local L, specs = page.layout, {}
    for _, kind in ipairs({ "Checkbox", "Dropdown", "Slider", "EditBox" }) do
        local orig = L[kind]
        L[kind] = function(self, spec, ...)
            if type(spec.label) == "string" then specs[spec.label] = spec end
            return orig(self, spec, ...)
        end
    end
    local ok, err = pcall(M.SetupPage, M, L)
    if not ok then io.write("SetupPage error: ", tostring(err), "\n") end
    L:Reflow()
    return ok and specs
end

-- Catch each module's event frame as it registers
local evFrames = {}
local origRegister = WM.RegisterEvents
local function Start(name)
    WM.RegisterEvents = function(_, fr) evFrames[name] = fr end
    WM.modules[name]:Initialize()
    WM.RegisterEvents = origRegister
end
local function Event(name, ev, ...) evFrames[name]._scripts.OnEvent(evFrames[name], ev, ...) end
-- A tooltip that records its lines
local function Tip()
    local t = W.NewFrame("Tip")
    t.lines = {}
    t.AddLine = function(self, l) self.lines[#self.lines + 1] = l end
    t.HasScript = function() return true end
    return t
end

-- ============================================
-- SETUP PAGES ON MODULES THAT HAVE NEVER STARTED
-- ============================================

for _, name in ipairs({ "GearScore", "Attunements", "Hazards", "GearSets", "Crits" }) do
    check(name .. ": setup page builds before it has started", Page(WM.modules[name]))
end
-- Settings written from the pages land in the modules' own settings
check("GearScore page: defaults filled", env.WMGearScoreDB.unitTooltip == true and env.WMGearScoreDB.keepDays == 7)
check("Hazards page: defaults filled", env.HazardsDB.drowning == true and env.HazardsDB.sounds[1] ~= nil)
check("Gear Sets page: automatic swaps on by default", env.WMGearSetsDB.auto == true)
check("Crits page: defaults filled", env.WMCritsDB.alertCrits == true)
check("Attunements page: defaults filled", env.AttunementsDB.announce == true)

-- Round trips through the pages' own controls
local function RoundTrip(M, label, value, read)
    local spec = (Page(M) or {})[label]
    if not spec then return false end
    spec.set(value)
    return read() == value and spec.get() == value
end
local HZ = WM.modules.Hazards
check("Hazards page: screen warning", RoundTrip(HZ, "Also show a warning on screen", true, function() return env.HazardsDB.screenText end))
env.HazardsDB.screenText = false
check("GearScore page: keep days", RoundTrip(WM.modules.GearScore, "Remember other players' scores for", 3,
    function() return env.WMGearScoreDB.keepDays end))
env.WMGearScoreDB.keepDays = 7
check("Crits page: quiet below", RoundTrip(WM.modules.Crits, "Quiet below:", "500", function() return tostring(env.WMCritsDB.minimum) end))
env.WMCritsDB.minimum = 0
check("Attunements page: Classic", RoundTrip(WM.modules.Attunements, "Show Classic attunements too", true,
    function() return env.AttunementsDB.showClassic end))
env.AttunementsDB.showClassic = false
local GE = WM.modules.GearSets
check("Gear Sets page: automatic swaps", RoundTrip(GE, "Automatic swaps (spec, mounted, battlegrounds)", false,
    function() return env.WMGearSetsDB.auto end))
GE.DB().auto = false
check("Gear Sets: auto is an ordinary setting now", GE.IsModuleEnabled == nil and GE.SetModuleEnabled == nil
    and WM:IsModuleOn("GearSets"))
GE.DB().auto = true

-- ============================================
-- HAZARD ALERTS
-- ============================================

Start("Hazards")
local played = 0
WM.Sounds = WM.Sounds or {}
local realPlay = WM.Sounds.Play
WM.Sounds.Play = function() played = played + 1 end
env.CombatLogGetCurrentEventInfo = function()
    return 0, "ENVIRONMENTAL_DAMAGE", false, "", "", 0, 0, ME, "Me", 0, 0, "LAVA", 3000
end
Event("Hazards", "COMBAT_LOG_EVENT_UNFILTERED")
check("Hazards: lava alerts", played == 1)
HZ:Toggle()
WM:SetModuleOn("Hazards", false)
clock = clock + 5
Event("Hazards", "COMBAT_LOG_EVENT_UNFILTERED")
Event("Hazards", "MIRROR_TIMER_START", "EXHAUSTION", 0, 0, -1)
check("Hazards off: no alerts", played == 1 and not HZ:Alert(1, "Test"))
check("Hazards off: window hidden", not env.WM_HazardsFrame:IsShown())
WM:SetModuleOn("Hazards", true)
clock = clock + 5
Event("Hazards", "COMBAT_LOG_EVENT_UNFILTERED")
check("Hazards on again: alerts", played == 2)

-- ============================================
-- CRIT TRACKER
-- ============================================

local CR = WM.modules.Crits
Start("Crits")
env.CombatLogGetCurrentEventInfo = function()
    return 0, "SPELL_DAMAGE", false, ME, "Me", 0, 0, "Creature-0-1-530-1-1-1", "Mob", 0, 0, 133, "Fireball", 4, 2000,
        0, 4, nil, nil, nil, true
end
Event("Crits", "COMBAT_LOG_EVENT_UNFILTERED")
local recs = CR.Records()
check("Crits: records a crit", recs["spell:Fireball"] and recs["spell:Fireball"].crits == 1)
local tip = Tip()
tip.GetSpell = function() return "Fireball" end
env.GameTooltip = tip
CR:HookTooltips()
tip:_fire("OnTooltipSetSpell")
check("Crits: tooltip line", #tip.lines == 1)
CR:Toggle()
WM:SetModuleOn("Crits", false)
Event("Crits", "COMBAT_LOG_EVENT_UNFILTERED")
check("Crits off: nothing recorded", recs["spell:Fireball"].crits == 1)
tip:_fire("OnTooltipCleared")
tip:_fire("OnTooltipSetSpell")
check("Crits off: no tooltip lines", #tip.lines == 1 and CR:TooltipLines("Fireball") == nil)
check("Crits off: window hidden", not env.WM_CritsFrame:IsShown())
WM:SetModuleOn("Crits", true)
Event("Crits", "COMBAT_LOG_EVENT_UNFILTERED")
tip:_fire("OnTooltipCleared")
tip:_fire("OnTooltipSetSpell")
check("Crits on again: records and tooltips", recs["spell:Fireball"].crits == 2 and #tip.lines == 2)

-- ============================================
-- GEARSCORE
-- ============================================

local GS = WM.modules.GearScore
Start("GearScore")
check("GearScore: /gs added", env.SlashCmdList.WM_GEARSCORE ~= nil)
local gt = Tip()
gt.GetUnit = function() return "Me", "player" end
gt.GetItem = function() return "Helm", HELM end
env.GameTooltip = gt
GS.tooltipsHooked = nil
GS:HookTooltips()
gt:_fire("OnTooltipSetItem")
gt:_fire("OnTooltipSetUnit")
check("GearScore: item and unit tooltip lines", #gt.lines == 2)
GS:UpdatePlayer()
local doll = GS.frames.paperDoll
check("GearScore: character sheet line", doll and doll:IsShown())
check("GearScore: mouseover queues an inspect", GS:QueueInspect("mouseover") and #notified == 1)
GS:Toggle()
WM:SetModuleOn("GearScore", false)
gt:_fire("OnTooltipCleared")
gt:_fire("OnTooltipSetItem")
gt:_fire("OnTooltipSetUnit")
check("GearScore off: no tooltip lines", #gt.lines == 2)
check("GearScore off: character sheet line hidden", not doll:IsShown())
env.CharacterFrame:_fire("OnShow")
GS:RefreshFrames()
check("GearScore off: stays hidden", not doll:IsShown())
check("GearScore off: no inspecting", not GS:QueueInspect("mouseover") and GS:NextInspect() == nil and #notified == 1)
check("GearScore off: window hidden", not env.WM_GearScoreFrame:IsShown())
Event("GearScore", "INSPECT_READY", "Player-1-00000002")
W.printed = {}
env.SlashCmdList.WM_GEARSCORE("")
check("GearScore off: /gs says it's off", Said("off on this character") and not env.WM_GearScoreFrame:IsShown())
WM:SetModuleOn("GearScore", true)
check("GearScore on again: character sheet line back", doll:IsShown())
gt:_fire("OnTooltipCleared")
gt:_fire("OnTooltipSetItem")
check("GearScore on again: tooltips", #gt.lines == 3)
clock = clock + 10
check("GearScore on again: inspects", GS:QueueInspect("mouseover") and #notified == 2)

-- ============================================
-- ATTUNEMENTS
-- ============================================

local AT = WM.modules.Attunements
Start("Attunements")
AT:OnEvent("CHAT_MSG_ADDON", "WMAtt", "Q", "GUILD", "Guildie-Testrealm")
W.runTimers()
check("Attunements: answers a survey", #addonMsgs == 1 and addonMsgs[1][2]:find("^A "))
AT:Toggle()
WM:SetModuleOn("Attunements", false)
clock = clock + 60
Event("Attunements", "CHAT_MSG_ADDON", "WMAtt", "Q", "GUILD", "Guildie-Testrealm")
Event("Attunements", "CHAT_MSG_ADDON", "WMAtt", "A 70 1:100", "GUILD", "Other-Testrealm")
W.runTimers()
check("Attunements off: doesn't answer or store", #addonMsgs == 1 and env.AttunementsDB.guild.Other == nil)
check("Attunements off: no survey", not AT:Survey() and #addonMsgs == 1)
check("Attunements off: window hidden", not env.WM_AttunementsFrame:IsShown())
WM:SetModuleOn("Attunements", true)
Event("Attunements", "CHAT_MSG_ADDON", "WMAtt", "A 70 1:100", "GUILD", "Other-Testrealm")
check("Attunements on again: stores answers", env.AttunementsDB.guild.Other ~= nil)
check("Attunements on again: survey", AT:Survey() and addonMsgs[#addonMsgs][2] == "Q")

-- ============================================
-- GEAR SETS
-- ============================================

Start("GearSets")
W.runTimers()   -- already in the world: ready for spec swaps without a loading screen
check("Gear Sets: ready when started after the loading screen", GE.ready and GE.Char().lastSpec == 1)
GE:SaveSet("DPS", { [1] = false }, { spec = 2, specAuto = true })
W.printed = {}
spec = 2
Event("GearSets", "ACTIVE_TALENT_GROUP_CHANGED")
check("Gear Sets: switching spec equips its set", Said("Switched to Spec 2"))
spec = 1
Event("GearSets", "ACTIVE_TALENT_GROUP_CHANGED")
-- Character sheet warning: a set wants an item you don't have
GE:SaveSet("Missing", { [5] = "999:0:0:0:0:0:0:0" }, {})
env.PaperDollFrame:Hide()
env.PaperDollFrame:Show()
local badge = env.WM_GearSetsWarning
check("Gear Sets: character sheet warning", badge and badge:IsShown())
GE:Toggle()
GE.job = { items = {}, name = "x", tries = {}, failed = {}, why = {}, spent = 0 }
WM:SetModuleOn("GearSets", false)
check("Gear Sets off: swap stopped, warning and window hidden", GE.job == nil and not badge:IsShown()
    and not env.WM_GearSetsFrame:IsShown())
W.printed = {}
spec = 2
Event("GearSets", "ACTIVE_TALENT_GROUP_CHANGED")
check("Gear Sets off: no spec swap", not Said("Switched to") and not GE.job)
env.PaperDollFrame:Hide()
env.PaperDollFrame:Show()
check("Gear Sets off: no warning on the character sheet", not badge:IsShown())
env.IsAltKeyDown = function() return true end
check("Gear Sets off: no quick-swap menu", GE:ShowQuickMenu(5, env.CharacterChestSlot) == nil)
WM:SetModuleOn("GearSets", true)
check("Gear Sets on again: the spec changed while off doesn't swap", not Said("Switched to")
    and GE.Char().lastSpec == 2)
check("Gear Sets on again: warning back", badge:IsShown())
spec = 1
GE:SaveSet("Tank", { [1] = false }, { spec = 1, specAuto = true })
Event("GearSets", "ACTIVE_TALENT_GROUP_CHANGED")
check("Gear Sets on again: spec swaps", Said("Switched to Spec 1"))
-- The bank note needs Your Characters
env.WatchingMachineDB.chars = env.WatchingMachineDB.chars or {}
WM.modules.AltTracker = { DB = function() return { chars = { ["Me-Testrealm"] = { bank = { { "item:999:0" } } } } } end }
check("Gear Sets: bank from Your Characters", GE.InBank("999:0:0:0:0:0:0:0"))
WM:CharState().modules.AltTracker = false
check("Gear Sets: Your Characters off, no bank", not GE.InBank("999:0:0:0:0:0:0:0"))
WM.modules.AltTracker = nil

WM.Sounds.Play = realPlay
print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
