-- Module panels built with WM.UI: Keyword Monitor, WarcraftLogs Lookup
-- (WhisperLogs), Services Parser.
-- Usage: lua5.1 test_panels_social2.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- The stub doesn't track child frames; Services Parser asks its tab rows
-- for their buttons, so record them here
local createFrame = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = createFrame(kind, name, parent, template)
    if parent then
        local kids = rawget(parent, "_kids") or {}
        rawset(parent, "_kids", kids)
        kids[#kids + 1] = f
    end
    return f
end
W.Frame.GetChildren = function(self) return unpack(rawget(self, "_kids") or {}) end
local createFontString = W.Frame.CreateFontString
W.Frame.CreateFontString = function(self, ...)
    local fs = createFontString(self, ...)
    local list = rawget(self, "_strings") or {}
    rawset(self, "_strings", list)
    list[#list + 1] = fs
    return fs
end

env.PlaySound = function() end
env.SOUNDKIT = {}
env.StaticPopupDialogs = {}
env.StaticPopup_Show = function(which) W.popup = which end
env.ChatFrame_OpenChat = function() end
env.GetRealmName = function() return "Old Blanchy" end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/KeywordMonitor.lua")
W.load("Modules/WhisperLogs.lua")
W.load("Modules/ServicesParser.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function Init(mod)
    if not pcall(mod.Initialize, mod) then mod:InitDB() end
end

local function FindCheckbox(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then return w end
    end
end
local function EditBoxes(panel)
    local out = {}
    for _, w in ipairs(panel.layout.widgets) do
        if rawget(w, "editBox") then out[#out + 1] = w end
    end
    return out
end
local function Escapable(name)
    for _, n in ipairs(env.UISpecialFrames) do if n == name then return true end end
    return false
end
local function Shown(list)
    local n = 0
    for _, f in ipairs(list or {}) do if f:IsShown() then n = n + 1 end end
    return n
end

-- ============ Keyword Monitor ============
local KM = WM.modules.KeywordMonitor
env.KeywordMonitorDB = nil
Init(KM)
env.KeywordMonitorDB.position = { "TOPLEFT", "TOPLEFT", 40, -50 }
KM:ToggleUI()
local kp = KM.mainFrame
check("keyword panel keeps its global name", env.WM_KeywordMonitorFrame == kp)
check("keyword panel shown", kp:IsShown())
check("keyword panel 580 tall", kp:GetHeight() == 580)
check("keyword panel fits a 768 screen", kp:GetHeight() <= 768 - 16)
check("keyword panel lists in a fill area", kp.layout.fill ~= nil and not kp.opts.scroll)
check("old saved position carried over", kp:GetState().pos and kp:GetState().pos[3] == 40
    and env.KeywordMonitorDB.position == nil)
check("keyword panel closes on Escape", Escapable("WM_KeywordMonitorFrame"))

-- Resizable through the builder; bounds capped at the screen
check("keyword panel has the builder's size grabber", kp.sizeGrip ~= nil)
W.fire(kp.sizeGrip, "OnMouseDown")
local b = rawget(kp, "_bounds")
check("resize bounds 400x480 to 800 wide", b and b[1] == 400 and b[2] == 480 and b[3] == 800)
check("resize max height capped at the screen", b and b[4] == 768 - 16)
kp:SetSize(640, 600)
W.fire(kp.sizeGrip, "OnMouseUp")
check("resize remembered", kp:GetState().size[1] == 640 and kp:GetState().size[2] == 600)
check("list follows the new width", KM.resultsScrollChild:GetWidth() == 640 - 24 - 23)

-- Adding a keyword through the edit box
local addBox = EditBoxes(kp)[1]
addBox.editBox:SetText("  boost  ")
W.fire(addBox.editBox, "OnEnterPressed")
check("keyword added from the edit box", env.KeywordMonitorDB.keywords["boost"] == true)
check("edit box cleared after add", addBox.editBox:GetText() == "")
check("keyword in the history", env.KeywordMonitorDB.keywordHistory[1] == "boost")
check("active keyword shown", KM.keywordDisplay:GetText():find("boost", 1, true) ~= nil)
check("history button shown", KM.historyButtons[1] and KM.historyButtons[1]:IsShown()
    and KM.historyButtons[1]:GetText() == "boost")

-- Clear All keywords, then re-add from history
local clearKw
for _, w in ipairs(kp.layout.widgets) do
    if rawget(w, "_template") == "UIPanelButtonTemplate" and w:GetText() == "Clear All" then clearKw = w end
end
W.click(clearKw)
check("clear all empties keywords", next(env.KeywordMonitorDB.keywords) == nil)
check("active list says none", KM.keywordDisplay:GetText():find("(none)", 1, true) ~= nil)
W.click(KM.historyButtons[1])
check("history button re-adds the keyword", env.KeywordMonitorDB.keywords["boost"] == true)
check("history button has a tooltip", KM.historyButtons[1]:GetScript("OnEnter") ~= nil)

-- Channels and alerts write their saved settings
check("seven channel checkboxes", (function()
    local n = 0 for _ in pairs(KM.channelCheckboxes) do n = n + 1 end return n end)() == 7)
local lfg = KM.channelCheckboxes.LookingForGroup
check("LFG box shows short label, checked", rawget(lfg, "Text"):GetText() == "LFG" and lfg:GetChecked())
W.click(lfg)
check("LFG checkbox writes", env.KeywordMonitorDB.channels.LookingForGroup == false)
W.click(KM.channelCheckboxes.Services)
check("Services checkbox writes", env.KeywordMonitorDB.channels.Services == true)
check("channel checkbox has a tooltip", lfg:GetScript("OnEnter") ~= nil)
local chat = FindCheckbox(kp, "Chat alert")
W.click(chat)
check("chat alert writes", env.KeywordMonitorDB.alertsEnabled == false)
local sound = FindCheckbox(kp, "Sound alert")
W.click(sound)
check("sound alert writes", env.KeywordMonitorDB.soundEnabled == false)
check("alert checkboxes have tooltips", chat:GetScript("OnEnter") ~= nil and sound:GetScript("OnEnter") ~= nil)

-- Stop/Resume and the per-character switch agree
check("starts active", KM.stopButton:GetText() == "Stop" and not KM:IsPaused())
W.click(KM.stopButton)
check("stop pauses", KM:IsPaused() and WM:IsModuleOn("KeywordMonitor"))
check("stop button reads Resume", KM.stopButton:GetText() == "Resume")
check("status reads PAUSED", KM.statusText:GetText():find("PAUSED", 1, true) ~= nil)
W.click(KM.stopButton)
check("resume button resumes", not KM:IsPaused() and KM.stopButton:GetText() == "Stop")
WM:SetModuleOn("KeywordMonitor", false)
check("switch off pauses and relabels to Resume", KM:IsPaused() and KM.stopButton:GetText() == "Resume")
WM:SetModuleOn("KeywordMonitor", true)
check("switch on resumes and relabels", not KM:IsPaused() and KM.stopButton:GetText() == "Stop"
    and KM.statusText:GetText():find("ACTIVE", 1, true) ~= nil)
if not kp:IsShown() then KM:Toggle() end

-- Results list
local now = os.time()
env.KeywordMonitorDB.results = {
    { sender = "Aa", message = "wts boost", channel = "Trade", keyword = "boost", timestamp = now },
    { sender = "Bb", message = "lf boost", channel = "General", keyword = "boost", timestamp = now - 10 },
    { sender = "Cc", message = "old", channel = "Trade", keyword = "boost", timestamp = now - 400 },
}
KM:UpdateResultsDisplay()
check("results produce rows, expired dropped", Shown(KM.resultFrames) == 2)
check("result row text", KM.resultFrames[1].headerText:GetText():find("Aa", 1, true) ~= nil)
local clearRes
for _, w in ipairs(kp.layout.widgets) do
    if rawget(w, "_template") == "UIPanelButtonTemplate" and w:GetText() == "Clear Results" then clearRes = w end
end
W.click(clearRes)
check("clear results empties the list", #env.KeywordMonitorDB.results == 0 and Shown(KM.resultFrames) == 0)
KM:ToggleUI()
check("keyword toggle hides", not kp:IsShown())
KM:ToggleUI()
check("keyword reopen reuses the frame", KM.mainFrame == kp and kp:IsShown())
check("no hand-made grabber left", not io.open(REPO .. "/Modules/KeywordMonitor.lua"):read("*a"):find("SetResizeBounds"))

-- ============ WarcraftLogs Lookup ============
local WL = WM.modules.WhisperLogs
env.WhisperLogsDB = nil
Init(WL)
WL:AddWhisper("Zug-Faerlina", "hi")
WL:AddWhisper("Mok", "yo")
WL:Toggle()
local wp = WL.mainFrame
check("whisper panel keeps its global name", env.WM_WhisperLogsFrame == wp)
check("whisper panel 420 tall", wp:GetHeight() == 420)
check("whisper panel lists in a fill area", wp.layout.fill ~= nil and wp.scrollChild ~= nil)
check("whisper panel closes on Escape", Escapable("WM_WhisperLogsFrame"))
check("whisper list refresh on show produced rows", Shown(wp.entries) == 2)
check("server label shows realm and region", wp.serverLabel:GetText():find("Old Blanchy (US)", 1, true) ~= nil)

local dd
for _, w in ipairs(wp.layout.widgets) do if rawget(w, "dropdown") then dd = w end end
check("region dropdown keeps its global name", env.WM_WhisperLogsRegionDropdown == dd.dropdown)
local items = W.openMenu(dd.dropdown)
check("region dropdown lists five regions", #items == 5 and items[1].text == "US" and items[1].checked)
items[2].func()
check("dropdown writes the region", env.WhisperLogsDB.region == "eu")
check("links rebuilt for the new region", env.WhisperLogsDB.whispers[1].url:find("/eu/", 1, true) ~= nil)
check("server label follows the region", wp.serverLabel:GetText():find("(EU)", 1, true) ~= nil)
check("dropdown text updated", dd.dropdown._ddText == "EU")
check("dropdown has a tooltip", dd.dropdown:GetScript("OnEnter") ~= nil)

local scanBtn, clearBtn = wp.footerButtons[1], wp.footerButtons[2]
check("scan button present", scanBtn:GetText() == "Scan Raid/Party" and scanBtn:GetScript("OnEnter") ~= nil)
env.IsInGroup = function() return true end
env.UnitExists = function(u) return u == "party1" end
env.UnitName = function(u) if u == "party1" then return "Pal", "Kirtonos" end return "Me" end
W.click(scanBtn)
check("scan adds group members", #env.WhisperLogsDB.whispers == 4 and Shown(wp.entries) == 4)
env.IsInGroup = function() return false end
W.click(clearBtn)
check("clear asks first", W.popup == "WM_WHISPERLOGS_CLEAR")
env.StaticPopupDialogs.WM_WHISPERLOGS_CLEAR.OnAccept()
check("clear empties the list", #env.WhisperLogsDB.whispers == 0 and Shown(wp.entries) == 0)
WL:Toggle()
check("whisper toggle hides", not wp:IsShown())

-- ============ Services Parser ============
local SP = WM.modules.ServicesParser
env.ServicesParserDB = nil
Init(SP)
SP:AddMessage("Booster", "WTS SM cath runs cheap")
SP:AddMessage("Porter", "summons to anywhere")
SP:ToggleUI()
local sp = SP.mainFrame
check("services panel keeps its global name", env.WM_ServicesParserFrame == sp)
check("services panel 480 tall", sp:GetHeight() == 480)
check("services panel lists in a fill area", sp.layout.fill ~= nil and sp.scrollChild ~= nil)
check("services panel closes on Escape", Escapable("WM_ServicesParserFrame"))
check("no separate settings window", rawget(env, "WM_ServicesParserSettings") == nil)
check("settings section collapsed by default", sp.layout.sections.settings:IsCollapsed())
check("SM tab lists its advert", Shown(sp.entries) == 1 and sp.entries[1].sender:GetText() == "Booster")
check("header names the dungeon", sp.header:GetText():find("Scarlet Monastery", 1, true) ~= nil)

-- Tabs: two Choice rows, the current one green, with counts
local choices = {}
for _, w in ipairs(sp.layout.widgets) do
    local kids = rawget(w, "_kids")
    if kids and #kids >= 8 and rawget(kids[1], "_template") == "UIPanelButtonTemplate" then
        choices[#choices + 1] = w
    end
end
check("two tab rows", #choices == 2)
local row1, row2 = rawget(choices[1], "_kids"), rawget(choices[2], "_kids")
check("8 + 10 tabs", #row1 == 8 and #row2 == 10)
local function TabText(btn) return btn:GetText() end
check("SM tab marked current", TabText(row1[3]):find("|cFF00FF00SM", 1, true) == 1)
check("other tabs not marked", TabText(row1[1]) == "RFC")
check("tab tooltip names the dungeon", row1[1]:GetScript("OnEnter") ~= nil)
W.click(row1[8])
check("SUM tab switches the list", sp.entries[1]:IsShown() and sp.entries[1].sender:GetText() == "Porter"
    and Shown(sp.entries) == 1)
check("SUM tab now marked, SM not", TabText(row1[8]):find("|cFF00FF00", 1, true) == 1 and TabText(row1[3]) == "SM")
check("header follows the tab", sp.header:GetText():find("Summons", 1, true) ~= nil)
W.click(row2[1])
check("second-row tab marks itself and clears the first row",
    TabText(row2[1]):find("|cFF00FF00RAMP", 1, true) == 1 and TabText(row1[8]) == "SUM")
check("empty tab shows no rows", Shown(sp.entries) == 0)
local function Badge(btn) local fs = rawget(btn, "_strings") return fs and fs[#fs] end
check("SM tab shows its listing count", Badge(row1[3]) and Badge(row1[3]):GetText() == 1)
check("empty tab shows no count", Badge(row2[1]) and Badge(row2[1]):GetText() == "")

-- Settings write the saved values
local boxes = EditBoxes(sp)
local channelBox, durationBox = boxes[1], boxes[2]
check("channel box shows the saved channel", channelBox.editBox:GetText() == "services")
channelBox.editBox:SetFocus()
channelBox.editBox:SetText("trade")
channelBox.editBox:ClearFocus()
check("channel saves on focus lost", env.ServicesParserDB.channelName == "trade")
channelBox.editBox:SetText("")
W.fire(channelBox.editBox, "OnEnterPressed")
check("empty channel ignored", env.ServicesParserDB.channelName == "trade"
    and channelBox.editBox:GetText() == "trade")
durationBox.editBox:SetText("90")
W.fire(durationBox.editBox, "OnEnterPressed")
check("duration saves on Enter", env.ServicesParserDB.messageDuration == 90)
durationBox.editBox:SetFocus()
durationBox.editBox:SetText("45")
durationBox.editBox:ClearFocus()
check("duration saves on focus lost", env.ServicesParserDB.messageDuration == 45)
local soundCB = FindCheckbox(sp, "Play sound")
W.click(soundCB)
check("sound checkbox writes", env.ServicesParserDB.playSound == true)
check("settings have tooltips", channelBox.editBox:GetScript("OnEnter") ~= nil
    and durationBox.editBox:GetScript("OnEnter") ~= nil and soundCB:GetScript("OnEnter") ~= nil)

local fillTop = select(5, sp.layout.fill.frame:GetPoint(1))
sp.layout.sections.settings:SetCollapsed(false)
local fillTop2 = select(5, sp.layout.fill.frame:GetPoint(1))
check("expanding settings moves the list down", fillTop2 < fillTop)
check("list keeps 200px with settings open", 480 - 40 - 44 + fillTop2 >= 200)

local clearAll = sp.footerButtons[1]
check("clear all in the footer", clearAll:GetText() == "Clear All")
W.click(clearAll)
check("clear all empties every tab", SP:GetQuickStatus():find("No listings", 1, true) ~= nil)
SP:ToggleUI()
check("services toggle hides", not sp:IsShown())

-- Short screen: fixed-height panels shrink to fit
env.UIParent:SetHeight(450)
sp:Show()
check("services panel shrinks to a short screen", sp:GetHeight() == 450 - 16)
env.UIParent:SetHeight(768)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
