-- Per-character on/off and the guided setup pages for ArmorySnap, World
-- Timers and the Loot Browser: each page builds on a module that never
-- started, its controls read and write the real settings, and turning a
-- module off makes its events, hooks and tickers do nothing.
-- Usage: lua5.1 test_onoff_raid2.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local inInstance = false
env.IsInInstance = function() if inInstance then return true, "raid" end return false, "none" end
env.GetRealZoneText = function() return "Karazhan" end
env.GetNumRaidMembers = function() return 0 end
env.GetNumPartyMembers = function() return 0 end
env.GetNumGroupMembers = function() return 0 end
env.UnitExists = function() return false end
env.IsAddOnLoaded = function() return false end
env.GetInventorySlotInfo = function() return 0, "tex" end
env.UnitFactionGroup = function() return "Horde" end
env.GetServerTime = function() return 1792004000 end
env.GetItemInfo = function() return nil end
env.C_Item = { GetItemInfo = function() return nil end,
    GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "INVTYPE_WRIST", "Interface\\Icons\\INV_Bracer_07" end }
env.C_Map = { GetBestMapForUnit = function() return 1955 end, GetAreaInfo = function() return nil end }
env.LE_EXPANSION_LEVEL_CURRENT = 1
env.strsplit = function(sep, s, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then out[#out + 1] = s:sub(start) break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return unpack(out)
end
-- C_Timer: tickers and one-shots collected so the test can run them
local tickers, afters = {}, {}
env.C_Timer = {
    After = function(_, fn) afters[#afters + 1] = fn end,
    NewTimer = function(_, fn) return { Cancel = function() end } end,
    NewTicker = function(_, fn) tickers[#tickers + 1] = fn; return { Cancel = function() end } end,
}
-- Hooks on Blizzard functions and the world map
local secure = {}
env.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then secure[b] = c else secure[a] = b end
end

-- Frames each file creates while loading (their event frames)
local created
local baseCreate = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = baseCreate(kind, name, parent, template)
    if created then created[#created + 1] = f end
    return f
end
local function LoadWatched(rel)
    created = {}
    W.load(rel)
    local out = created
    created = nil
    for _, f in ipairs(out) do if f._scripts.OnEvent then return f end end
end

W.load("Core.lua")
W.load("UI.lua")
for _, f in ipairs({ "Data/LootClassic.lua", "Data/LootTBC.lua", "Data/LootWrath.lua", "Data/LootCrafting.lua",
    "Data/LootFactions.lua", "Data/LootPvP.lua", "Data/LootSets.lua", "Data/LootCrafts.lua",
    "Modules/GearScore.lua", "Modules/NovaCompat.lua" }) do W.load(f) end
local asEvents = LoadWatched("Modules/ArmorySnap.lua")
local wtEvents = LoadWatched("Modules/WorldTimers.lua")
local lbEvents = LoadWatched("Modules/LootBrowser.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local AS, WT, LB = WM.modules.ArmorySnap, WM.modules.WorldTimers, WM.modules.LootBrowser

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function Page(name, m)
    local p = WM.UI:CreatePanel({ name = "WM_TestSetup" .. name, title = "t" })
    local page = p:NewPage()
    local ok, err = pcall(m.SetupPage, m, page.layout)
    if not ok then io.write(tostring(err), "\n") end
    check(name .. ": page builds before the module starts", ok)
    ok = pcall(page.layout.Reflow, page.layout)
    check(name .. ": page reflows", ok)
    return page.layout
end
local function Box(L, pattern)
    for _, w in ipairs(L.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then return w end
    end
end
local function Count(L)
    local n = 0
    for _, w in ipairs(L.widgets) do if rawget(w, "Text") or rawget(w, "dropdown") then n = n + 1 end end
    return n
end

-- ============ Setup pages, on fresh never-started modules ============
check("nothing started yet", env.ArmorySnapDB == nil and rawget(env, "WorldTimersDB") == nil
    and rawget(env, "LootBrowserDB") == nil)

local L = Page("ArmorySnap", AS)
check("ArmorySnap: defaults filled", env.ArmorySnapDB.options.enabled == true and env.ArmorySnapDB.options.retentionDays == 30)
check("ArmorySnap: no frames or events from the page", rawget(env, "WM_ArmorySnapFrame") == nil and #tickers == 0)
local auto = Box(L, "Scan automatically")
check("ArmorySnap: auto-scan box shows the setting", auto and auto:GetChecked() == true)
W.click(auto)
check("ArmorySnap: auto-scan box writes it", env.ArmorySnapDB.options.enabled == false and not AS.IsAutoScan())
W.click(auto)
local verbose = Box(L, "progress in chat")
W.click(verbose)
check("ArmorySnap: chat box writes verbose", env.ArmorySnapDB.options.verbose == true)
env.ArmorySnapDB.options.verbose = false
check("ArmorySnap: no module switch of its own", AS.SetModuleEnabled == nil and AS.IsModuleEnabled == nil)

L = Page("WorldTimers", WT)
check("WorldTimers: defaults filled", env.WorldTimersDB.terokWarn == true and env.WorldTimersDB.mapPins == true)
local terok = Box(L, "Terokkar towers reset")
check("WorldTimers: tower box shows the setting", terok and terok:GetChecked() == true)
W.click(terok)
check("WorldTimers: tower box writes it", env.WorldTimersDB.terokWarn == false)
W.click(terok)
local pins = Box(L, "world map")
W.click(pins)
check("WorldTimers: map box writes it (not started: no error)", env.WorldTimersDB.mapPins == false)
W.click(pins)
check("WorldTimers: a handful of controls", Count(L) >= 6)

L = Page("LootBrowser", LB)
check("LootBrowser: defaults filled", env.LootBrowserDB.tooltips == true and env.LootBrowserDB.followInstance == true)
local tips = Box(L, "tooltips")
check("LootBrowser: tooltip box shows the setting", tips and tips:GetChecked() == true)
W.click(tips)
check("LootBrowser: tooltip box writes it", env.LootBrowserDB.tooltips == false)
W.click(tips)
local dd
for _, w in ipairs(L.widgets) do if rawget(w, "dropdown") then dd = w.dropdown end end
local items = dd and W.openMenu(dd) or {}
check("LootBrowser: expansion choices", #items >= 2)
for _, it in ipairs(items) do if it.value == 0 or it.arg1 == 0 then if it.func then it.func(it, it.arg1, it.arg2) end end end
check("LootBrowser: expansion dropdown writes it", env.LootBrowserDB.expansion == 0)
env.LootBrowserDB.expansion = nil

-- ============ ArmorySnap on and off ============
AS:Initialize()
check("ArmorySnap: tickers started", #tickers == 2)
local scan = tickers[1]
inInstance = true
scan()
check("on: scanning in a raid", AS.session.active == true)
AS.ToggleBrowseFrame()
local browser = env.WM_ArmorySnapFrame
check("on: browser opens", browser and browser:IsShown())
AS.session.passComplete, AS.session.rosterClock = true, 5
asEvents:_fire("OnEvent", "GROUP_ROSTER_UPDATE")
check("on: roster change noticed", AS.session.rosterClock == 0)

WM:SetModuleOn("ArmorySnap", false)
check("off: browser hidden, session dropped", not browser:IsShown() and AS.session.active == false)
check("off: auto-scan setting left alone (shared by every character)", env.ArmorySnapDB.options.enabled == true)
scan()
check("off: the watchdog tick does nothing", AS.session.active == false and AS.session.snapshotKey == nil)
AS.session.passComplete, AS.session.rosterClock = true, 5
asEvents:_fire("OnEvent", "GROUP_ROSTER_UPDATE")
check("off: events do nothing", AS.session.rosterClock == 5)
local printed = #W.printed
AS.HandleSlash("")
check("off: /as says it's off", not browser:IsShown() and #W.printed > printed
    and W.printed[#W.printed]:find("off on this character", 1, true))

WM:SetModuleOn("ArmorySnap", true)
scan()
check("on again: scanning", AS.session.active == true)
asEvents:_fire("OnEvent", "GROUP_ROSTER_UPDATE")
check("on again: events", AS.session.rosterClock == 0)
inInstance = false

-- GearScore off: no new scores for members
local member = { class = "MAGE", gear = { [1] = { link = "|cffa335ee|Hitem:28963::::::::70:::::|h[x]|h|r" } } }
WM:SetModuleOn("GearScore", false)
check("GearScore off: members aren't scored", AS.ScoreMember(member) == nil)
member.gearScore, member.avgIlvl = 500, 120
check("GearScore off: a saved score still shows", AS.ScoreMember(member) == 500)
WM:SetModuleOn("GearScore", true)

-- ============ World Timers on and off ============
local wtTickers = {}
local baseTicker = WM.RunTicker
WM.RunTicker = function(_, fn) wtTickers[#wtTickers + 1] = fn end
WT:Initialize()
WM.RunTicker = baseTicker
check("WorldTimers: two tickers", #wtTickers == 2)
local guids = {}
env.UnitGUID = function(u) return guids[u] end
guids.target = "Creature-0-4395-530-101-18481-0000ABCDEF"
wtEvents:_fire("OnEvent", "PLAYER_TARGET_CHANGED")
check("on: layer seen from A'dal", WT:CurrentLayer() == 101)
WT:Toggle()
local wtPanel = env.WM_WorldTimersFrame
check("on: window opens", wtPanel and wtPanel:IsShown())

WM:SetModuleOn("WorldTimers", false)
check("off: window hidden", not wtPanel:IsShown())
guids.target = "Creature-0-4395-530-202-18481-0000ABCDEF"
wtEvents:_fire("OnEvent", "PLAYER_TARGET_CHANGED")
check("off: events do nothing", WT:CurrentLayer() == 101 and not WT:Data().layers[202])
-- The gossip close hook (set up when a buff NPC's window opens)
WM:SetModuleOn("WorldTimers", true)
guids.npc = "Creature-0-4395-1-1-14392-0000ABCDEF"
WT:OnGossipShow()
local closeHook = secure.CloseGossip or secure.CloseAllWindows
check("gossip close hooked", closeHook ~= nil)
local closes = 0
local origClose = WT.NoteSelfClose
WT.NoteSelfClose = function() closes = closes + 1 end
WM:SetModuleOn("WorldTimers", false)
if closeHook then closeHook() end
check("off: gossip hook does nothing", closes == 0)
WM:SetModuleOn("WorldTimers", true)
if closeHook then closeHook() end
check("on: gossip hook notes the close", closes == 1)
WT.NoteSelfClose = origClose
WM:SetModuleOn("WorldTimers", false)
-- The tickers do nothing either
local warned = 0
local origWarn = WT.CheckTerokWarning
WT.CheckTerokWarning = function() warned = warned + 1 end
wtTickers[1]()
check("off: the 5-second ticker does nothing", warned == 0)
WM:SetModuleOn("WorldTimers", true)
wtTickers[1]()
check("on again: the ticker runs", warned == 1)
WT.CheckTerokWarning = origWarn
wtEvents:_fire("OnEvent", "PLAYER_TARGET_CHANGED")
check("on again: events", WT:CurrentLayer() == 202)
-- World map pins: the map's refresh idles while off
local map, canvas = W.NewFrame("WorldMapFrame"), W.NewFrame("Canvas")
map.GetCanvas = function() return canvas end
map.GetMapID = function() return 1955 end
env.WorldMapFrame = map
check("map hooked", WT:SetupMapPins() and WT.mapTicker:IsShown())
local drawn = 0
local origPins = WT.RefreshMapPins
WT.RefreshMapPins = function() drawn = drawn + 1; return 0 end
map:_fire("OnShow")
check("on: map shown draws the pins", drawn == 1)
WM:SetModuleOn("WorldTimers", false)
check("off: map refresh idled", not WT.mapTicker:IsShown())
map:_fire("OnShow")
WT.mapTicker:_fire("OnUpdate", 2)
check("off: map hooks draw nothing", drawn == 0 + 1)
WM:SetModuleOn("WorldTimers", true)
check("on again: map refresh back", WT.mapTicker:IsShown() and drawn == 2)
WT.RefreshMapPins = origPins

-- ============ Loot Browser on and off ============
LB:Initialize()
local function Tip()
    local tip = W.NewFrame("Tip")
    tip.lines = {}
    tip.AddLine = function(self, l) self.lines[#self.lines + 1] = l end
    return tip
end
local gt = Tip()
gt.GetItem = function() return "Harbinger Bands", "|cffa335ee|Hitem:28477::::::::70:::::|h[Harbinger Bands]|h|r" end
gt.HasScript = function(_, name) return name == "OnTooltipSetItem" end
env.GameTooltip = gt
LB.tooltipsHooked = nil
LB:HookTooltips()
gt:_fire("OnTooltipSetItem")
check("on: item tooltip gets the source", #gt.lines >= 1)
LB:Toggle()
local lbPanel = env.WM_LootBrowserFrame
check("on: window opens", lbPanel and lbPanel:IsShown())

WM:SetModuleOn("LootBrowser", false)
check("off: window hidden", not lbPanel:IsShown())
gt:_fire("OnTooltipCleared")
gt.lines = {}
gt:_fire("OnTooltipSetItem")
check("off: tooltip hook adds nothing", #gt.lines == 0)
local queued = #W.timers
lbEvents:_fire("OnEvent", "GET_ITEM_INFO_RECEIVED")
check("off: item info events do nothing", #W.timers == queued)

WM:SetModuleOn("LootBrowser", true)
gt:_fire("OnTooltipCleared")
gt:_fire("OnTooltipSetItem")
check("on again: tooltip gets the source", #gt.lines >= 1)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
