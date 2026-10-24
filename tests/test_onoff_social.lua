-- Guild & Social modules switched off per character, and their guided setup
-- pages: Guild Invite, Recruiter, PvP Tracker, Chat Filter, Keyword Monitor,
-- Services Parser, WarcraftLogs Lookup (WhisperLogs).
-- Usage: lua5.1 test_onoff_social.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Record chat frame filters and every frame the modules create
local chatFilters = {}
env.ChatFrame_AddMessageEventFilter = function(event, fn)
    chatFilters[event] = chatFilters[event] or {}
    table.insert(chatFilters[event], fn)
end
local frames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); frames[#frames + 1] = f; return f end

local clock = 1000
env.GetTime = function() return clock end
env.PlaySound = function() end
env.SOUNDKIT = {}
env.StaticPopupDialogs = {}
env.StaticPopup_Show = function() end
env.StaticPopup_Hide = function() end
local opened = {}
env.ChatFrame_OpenChat = function(text) opened[#opened + 1] = text end
local whoSent = 0
env.DEFAULT_CHAT_FRAME.editBox = W.NewFrame()
env.ChatEdit_SendText = function() whoSent = whoSent + 1 end
local whoResults = 0
env.GetNumWhoResults = function() whoResults = whoResults + 1; return 0 end
local chatSent, addonSent, invited = {}, {}, {}
env.SendChatMessage = function(msg, kind) chatSent[#chatSent + 1] = { msg, kind } end
env.C_ChatInfo = {
    SendAddonMessage = function(prefix, msg) addonSent[#addonSent + 1] = msg end,
    RegisterAddonMessagePrefix = function() end,
}
env.InviteUnit = function(name) invited[#invited + 1] = name end
env.IsInGuild = function() return true end
local roster = { "Alice-Testrealm", "Bob-Testrealm" }
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i) return roster[i] end
env.UnitIsGroupLeader = function() return true end
env.UnitIsGroupAssistant = function() return false end
env.GetNumGroupMembers = function() return 0 end
local mouseover = nil
env.UnitName = function(u) if u == "mouseover" then return mouseover end return "Me" end
env.UnitGUID = function() return "Player-1-00000001" end
env.UnitExists = function(u) return u == "mouseover" and mouseover ~= nil end
env.UnitIsPlayer = function() return true end
env.UnitIsFriend = function() return false end
env.UnitFactionGroup = function(u) return u == "player" and "Alliance" or "Horde" end
env.UnitLevel = function() return 70 end
env.GetGuildInfo = function() return nil end
local warnings = {}
env.RaidWarningFrame = { AddMessage = function(_, m) warnings[#warnings + 1] = m end }

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/GuildInvite.lua", "Modules/Recruiter.lua",
    "Modules/PvPTracker.lua", "Modules/ChatFilter.lua", "Modules/KeywordMonitor.lua",
    "Modules/ServicesParser.lua", "Modules/WhisperLogs.lua" }) do W.load(f) end
local WM = W.WM

-- A new character: everything off, every saved variable an empty profile
env.WatchingMachineDB = { theme = "Default", chars = { ["Me-Testrealm"] = { modules = {}, defaultOn = false } } }
WM.Profiles:Load()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- helpers ----
local pageN = 0
local function BuildPage(m)
    pageN = pageN + 1
    local p = WM.UI:CreatePanel({ name = "WM_TestSetup" .. pageN, title = "t" })
    local page = p:NewPage()
    local ok, err = pcall(m.SetupPage, m, page.layout)
    if ok then ok, err = pcall(page.layout.Reflow, page.layout) end
    if not ok then io.write("  ", tostring(err), "\n") end
    return ok, page.layout
end
local function Checkbox(L, label)
    for _, w in ipairs(L.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(label, 1, true) then return w end
    end
end
local function EditBoxes(L)
    local out = {}
    for _, w in ipairs(L.widgets) do if rawget(w, "editBox") then out[#out + 1] = w end end
    return out
end
local function Typed(box, text)
    box.editBox:SetText(text)
    box.editBox:_fire("OnEnterPressed")
end
local function First(L, field)
    for _, w in ipairs(L.widgets) do if rawget(w, field) then return w end end
end
local function Pick(box, text)
    for _, item in ipairs(W.openMenu(box.dropdown)) do
        if item.text == text then item.func(); return true end
    end
end
local function Tooltips(L)
    for _, w in ipairs(L.widgets) do
        if rawget(w, "Text") and not w:GetScript("OnEnter") then return false end
    end
    return true
end
-- Frames whose script for `ev` was written in `file`
local function Handlers(file, ev)
    local out = {}
    for _, f in ipairs(frames) do
        local h = f:GetScript(ev)
        if h and debug.getinfo(h, "S").source:find(file, 1, true) then out[#out + 1] = f end
    end
    return out
end
local function Fire(f, event, ...) f._scripts.OnEvent(f, event, ...) end

check("a new character starts with these off", not WM:IsModuleOn("GuildInvite") and not WM:IsModuleOn("Recruiter")
    and not WM:IsModuleOn("ChatFilter") and not WM:IsModuleOn("WhisperLogs"))

-- ============ Guild Invite ============
local GI = WM.modules.GuildInvite
local giEvents = Handlers("GuildInvite", "OnEvent")[1]
Fire(giEvents, "CHAT_MSG_GUILD", "inv", "Alice-Testrealm")
check("guild invite: off before it starts, nothing happens", #invited == 0 and env.GuildInviteDB.trigger == nil)
local ok, L = BuildPage(GI)
check("guild invite: setup page builds before it starts", ok)
check("guild invite: setup page has tooltips", Tooltips(L))
Typed(EditBoxes(L)[1], "123")
check("guild invite: trigger word saved", env.GuildInviteDB.trigger == "123")
W.click(Checkbox(L, "Announce invites"))
check("guild invite: announce checkbox writes", env.GuildInviteDB.announceInvites == false)

WM:SetModuleOn("GuildInvite", true)
GI:Initialize()
Fire(giEvents, "CHAT_MSG_GUILD", "123", "Alice-Testrealm")
check("guild invite: on, the trigger invites", invited[1] == "Alice-Testrealm")
GI:Toggle()
check("guild invite: window open", env.WM_GuildInviteFrame:IsShown())
WM:SetModuleOn("GuildInvite", false)
check("guild invite: off closes the window", not env.WM_GuildInviteFrame:IsShown())
env.GuildInviteDB.enabled = true   -- even with its own flag on
Fire(giEvents, "CHAT_MSG_GUILD", "123", "Alice-Testrealm")
GI:InviteToRaid("Bob", "Guild")
check("guild invite: off, nobody is invited", #invited == 1)
WM:SetModuleOn("GuildInvite", true)
Fire(giEvents, "CHAT_MSG_WHISPER", "123", "Bob-Testrealm")
check("guild invite: back on, invites again", invited[2] == "Bob-Testrealm")

-- ============ Recruiter ============
local RC = WM.modules.Recruiter
local rcWho = Handlers("Recruiter", "OnEvent")[1]
local rcUpdate = Handlers("Recruiter", "OnUpdate")[1]
Fire(rcWho, "WHO_LIST_UPDATE")
rcUpdate._scripts.OnUpdate(rcUpdate, 5)
check("recruiter: off before it starts, quiet", whoResults == 0 and whoSent == 0)
check("recruiter: status before it starts", RC:GetQuickStatus():find("Not started", 1, true) ~= nil)
ok, L = BuildPage(RC)
check("recruiter: setup page builds before it starts", ok)
check("recruiter: setup page has tooltips", Tooltips(L))
local boxes = EditBoxes(L)
Typed(boxes[1], "Watchers")
Typed(boxes[#boxes], "30")
check("recruiter: guild name saved", env.RecruitingToolDB.guildName == "Watchers")
check("recruiter: cooldown capped at 14 days", env.RecruitingToolDB.cooldownDays == 14)
W.click(Checkbox(L, "Hide my recruitment"))
check("recruiter: hide checkbox writes", env.RecruitingToolDB.hideWhispers == false)
env.RecruitingToolDB.hideWhispers = true

WM:SetModuleOn("Recruiter", true)
RC:Initialize()
local rcFilter = chatFilters.CHAT_MSG_WHISPER_INFORM and chatFilters.CHAT_MSG_WHISPER_INFORM[1]
local msg = RC:GetFormattedMessage()
check("recruiter: whisper filter installed", rcFilter ~= nil and rcFilter(nil, "CHAT_MSG_WHISPER_INFORM", msg, "Bob") == true)
RC:StartScan()
check("recruiter: on, a scan sends /who", whoSent == 1)
RC:ToggleUI()
RC:ShowMessageList()
RC:ShowHistoryWindow()
check("recruiter: windows open", env.WM_RecruiterFrame:IsShown() and env.WM_RecruiterMessageFrame:IsShown()
    and env.WM_RecruiterHistoryFrame:IsShown())
WM:SetModuleOn("Recruiter", false)
check("recruiter: off closes every window", not env.WM_RecruiterFrame:IsShown()
    and not env.WM_RecruiterMessageFrame:IsShown() and not env.WM_RecruiterHistoryFrame:IsShown())
check("recruiter: off stops the scan", not RC:GetQuickStatus():find("Scanning", 1, true))
Fire(rcWho, "WHO_LIST_UPDATE")
rcUpdate._scripts.OnUpdate(rcUpdate, 10)
RC:StartScan()
RC:ContinueScan()
check("recruiter: off, no /who is sent", whoSent == 1 and whoResults == 0)
check("recruiter: off, no whisper is prefilled", RC:OpenWhisperPrompt("Bob") == false and #opened == 0)
check("recruiter: off, own whispers aren't hidden", rcFilter(nil, "CHAT_MSG_WHISPER_INFORM", msg, "Bob") == false)
WM:SetModuleOn("Recruiter", true)
check("recruiter: back on, prefills the whisper", RC:OpenWhisperPrompt("Bob") == true
    and opened[1] == "/w Bob " .. msg)
RC:StartScan()
check("recruiter: back on, scans", whoSent == 2)
check("recruiter: back on, hides own whispers", rcFilter(nil, "CHAT_MSG_WHISPER_INFORM", msg, "Bob") == true)
RC:StopScan()

-- ============ PvP Tracker ============
local PT = WM.modules.PvPTracker
ok, L = BuildPage(PT)
check("pvp: setup page builds before it starts", ok)
check("pvp: setup page has tooltips", Tooltips(L))
W.click(Checkbox(L, "Sound alert"))
check("pvp: sound checkbox writes", env.PvPTrackerDB.alertSound == false)
check("pvp: post-leaderboard dropdown writes", Pick(First(L, "dropdown"), "Hourly")
    and env.PvPTrackerDB.leaderboardAnnounce == "hourly")
local slider = First(L, "slider")
slider.slider:SetValue(60)
check("pvp: alert cooldown slider writes", env.PvPTrackerDB.alertCooldown == 60)
env.PvPTrackerDB.leaderboardAnnounce = "off"

WM:SetModuleOn("PvPTracker", true)
PT:Initialize()
PT:AddManualEnemy("Gankalot")
local ptFrames = Handlers("PvPTracker", "OnEvent")
local ptEvents, ptSync
for _, f in ipairs(ptFrames) do
    if debug.getinfo(f._scripts.OnEvent, "S").linedefined
        > debug.getinfo(PT.MakeHandlers, "S").linedefined then ptEvents = f else ptSync = f end
end
check("pvp: found its event and sync frames", ptEvents ~= nil and ptSync ~= nil)
mouseover = "Gankalot"
Fire(ptEvents, "UPDATE_MOUSEOVER_UNIT")
check("pvp: on, a KOS name alerts", warnings[#warnings] == "ENEMY: Gankalot")
PT:Toggle()
PT:ToggleLeaderboard()
check("pvp: windows open", env.WM_PvPTrackerFrame:IsShown() and env.WM_PvPLeaderboardFrame:IsShown())
local onEvent = ptEvents._scripts.OnEvent
WM:SetModuleOn("PvPTracker", false)
check("pvp: off closes the windows", not env.WM_PvPTrackerFrame:IsShown() and not env.WM_PvPLeaderboardFrame:IsShown())
check("pvp: off unregisters its events", ptEvents._scripts.OnEvent == nil)
local nWarn, nAddon, nChat = #warnings, #addonSent, #chatSent
clock = clock + 100
onEvent(ptEvents, "UPDATE_MOUSEOVER_UNIT")   -- a late event still arriving
PT:SendHello()
PT:RequestSync()
PT:SendFullSync()
PT:CheckPeriodicAnnounce()
Fire(ptSync, "CHAT_MSG_ADDON", "WMPvP", "K:Stabby:ROGUE:70::Nagrand", "GUILD", "Alice-Testrealm")
ptSync._scripts.OnUpdate(ptSync, 5)
check("pvp: off, no alert", #warnings == nWarn)
check("pvp: off, nothing sent to the guild", #addonSent == nAddon and #chatSent == nChat)
check("pvp: off, guild data ignored", env.PvPTrackerDB.enemies.Stabby == nil)
WM:SetModuleOn("PvPTracker", true)
check("pvp: back on, events re-attached", ptEvents._scripts.OnEvent ~= nil and ptEvents._scripts.OnUpdate ~= nil)
clock = clock + 100
Fire(ptEvents, "UPDATE_MOUSEOVER_UNIT")
check("pvp: back on, alerts again", #warnings == nWarn + 1)
mouseover = nil

-- ============ Chat Filter (and Keyword Monitor honouring it) ============
local CF, KM = WM.modules.ChatFilter, WM.modules.KeywordMonitor
local kmEvents = Handlers("KeywordMonitor", "OnEvent")[1]
local kmUpdate = Handlers("KeywordMonitor", "OnUpdate")[1]
check("chat filter: off before it starts, hides nothing",
    CF.MessageFilter(nil, "CHAT_MSG_CHANNEL", "GDKP tonight", "Spammer", "", "2. Trade - City") == false)
ok, L = BuildPage(CF)
check("chat filter: setup page builds before it starts", ok)
check("chat filter: setup page has tooltips", Tooltips(L))
W.click(Checkbox(L, "Say and yell"))
check("chat filter: chat type checkbox writes", env.ChatFilterDB.types.say == true)
W.click(Checkbox(L, "GDKP"))
check("chat filter: premade checkbox writes", env.ChatFilterDB.premades.gdkp == true)
Typed(EditBoxes(L)[1], "Gear Boost")
check("chat filter: phrase added from the page", env.ChatFilterDB.phrases[1] == "Gear Boost")

ok, L = BuildPage(KM)
check("keyword monitor: setup page builds before it starts", ok)
check("keyword monitor: setup page has tooltips", Tooltips(L))
Typed(EditBoxes(L)[1], "bt")
check("keyword monitor: keyword added from the page", env.KeywordMonitorDB.keywords.bt == true)
W.click(Checkbox(L, "Services"))
check("keyword monitor: channel checkbox writes", env.KeywordMonitorDB.channels.Services == true)
local function Channel(text, sender)
    Fire(kmEvents, "CHAT_MSG_CHANNEL", text, sender or "Spammer", "", "2. Trade - City", "", "", 0, 2, "Trade")
end
Channel("GDKP BT tonight")
Fire(kmEvents, "PLAYER_LOGOUT")
check("keyword monitor: off before it starts, its data untouched", env.KeywordMonitorDB.results == nil)

WM:SetModuleOn("ChatFilter", true)
CF:Initialize()
WM:SetModuleOn("KeywordMonitor", true)
KM:Initialize()
local cfFilter = chatFilters.CHAT_MSG_CHANNEL[1]
local function Hidden(text, line)
    return cfFilter(nil, "CHAT_MSG_CHANNEL", text, "Spammer", "", "2. Trade - City", "", "", 0, 2, "Trade", 0, line)
end
check("chat filter: on, hides a premade", Hidden("GDKP BT tonight", 1) == true)
Channel("GDKP BT tonight")
check("keyword monitor: never sees a filtered message", #env.KeywordMonitorDB.results == 0)
Channel("LFM BT need heals")
check("keyword monitor: on, a keyword matches", #env.KeywordMonitorDB.results == 1)
CF:Toggle()
check("chat filter: window open", env.WM_ChatFilterFrame:IsShown())
WM:SetModuleOn("ChatFilter", false)
check("chat filter: off closes the window", not env.WM_ChatFilterFrame:IsShown())
env.ChatFilterDB.enabled = true    -- even with its own flag on
check("chat filter: off, nothing hidden", Hidden("GDKP BT tonight", 2) == false)
Channel("GDKP BT tonight")
check("keyword monitor: with Chat Filter off, sees everything", #env.KeywordMonitorDB.results == 2)
WM:SetModuleOn("ChatFilter", true)
check("chat filter: back on, hides again", Hidden("GDKP BT tonight", 3) == true)

KM:Toggle()
check("keyword monitor: window open", env.WM_KeywordMonitorFrame:IsShown())
WM:SetModuleOn("KeywordMonitor", false)
check("keyword monitor: off closes the window and drops matches", not env.WM_KeywordMonitorFrame:IsShown()
    and #env.KeywordMonitorDB.results == 0)
Channel("LFM BT tank")
kmUpdate._scripts.OnUpdate(kmUpdate, 2)
local sentinel = env.KeywordMonitorDB.results
Fire(kmEvents, "PLAYER_LOGOUT")
check("keyword monitor: off, no matches", #env.KeywordMonitorDB.results == 0)
check("keyword monitor: off, logout leaves its data alone", env.KeywordMonitorDB.results == sentinel)
WM:SetModuleOn("KeywordMonitor", true)
check("keyword monitor: back on, monitoring", not KM:IsPaused())
Channel("LFM BT dps")
check("keyword monitor: back on, matches again", #env.KeywordMonitorDB.results == 1)

-- ============ Services Parser ============
local SP = WM.modules.ServicesParser
local spFrame = Handlers("ServicesParser", "OnEvent")[1]
local function Advert(text)
    Fire(spFrame, "CHAT_MSG_CHANNEL", text, "Seller-Testrealm", "", "", "", "", 0, 5, "5. Services - City")
end
Advert("WTS SM cath run")
spFrame._scripts.OnUpdate(spFrame, 2)
check("services: off before it starts, nothing read", SP:GetQuickStatus():find("No listings", 1, true) ~= nil
    and env.ServicesParserDB.channelName == nil)
ok, L = BuildPage(SP)
check("services: setup page builds before it starts", ok)
check("services: setup page has tooltips", Tooltips(L))
Typed(EditBoxes(L)[1], "Services")
check("services: channel saved", env.ServicesParserDB.channelName == "Services")
W.click(Checkbox(L, "Play a sound"))
check("services: sound checkbox writes", env.ServicesParserDB.playSound == true)
First(L, "slider").slider:SetValue(120)
check("services: duration slider writes", env.ServicesParserDB.messageDuration == 120)

WM:SetModuleOn("ServicesParser", true)
SP:Initialize()
Advert("WTS SM cath run")
check("services: on, an advert is listed", SP:GetQuickStatus():find("1", 1, true) ~= nil)
SP:Toggle()
check("services: window open", env.WM_ServicesParserFrame:IsShown())
WM:SetModuleOn("ServicesParser", false)
check("services: off closes the window and forgets listings", not env.WM_ServicesParserFrame:IsShown()
    and SP:GetQuickStatus():find("No listings", 1, true) ~= nil)
Advert("WTS Strat run")
check("services: off, adverts ignored", SP:GetQuickStatus():find("No listings", 1, true) ~= nil)
WM:SetModuleOn("ServicesParser", true)
Advert("WTS Strat run")
check("services: back on, listed again", SP:GetQuickStatus():find("No listings", 1, true) == nil)

-- ============ WarcraftLogs Lookup ============
local WL = WM.modules.WhisperLogs
local wlFrame = Handlers("WhisperLogs", "OnEvent")[1]
Fire(wlFrame, "CHAT_MSG_WHISPER", "hi", "Alice-Testrealm")
check("wcl: off before it starts, whispers ignored", env.WhisperLogsDB.whispers == nil
    and WL:GetQuickStatus():find("No whispers", 1, true) ~= nil)
ok, L = BuildPage(WL)
check("wcl: setup page builds before it starts", ok)
check("wcl: region dropdown writes", Pick(First(L, "dropdown"), "EU") and env.WhisperLogsDB.region == "eu")

WM:SetModuleOn("WhisperLogs", true)
WL:Initialize()
Fire(wlFrame, "CHAT_MSG_WHISPER", "hi", "Alice-Testrealm")
check("wcl: on, a whisper is listed with the region", #env.WhisperLogsDB.whispers == 1
    and env.WhisperLogsDB.whispers[1].url:find("/eu/testrealm/alice", 1, true) ~= nil)
WL:Toggle()
check("wcl: window open", env.WM_WhisperLogsFrame:IsShown())
WM:SetModuleOn("WhisperLogs", false)
check("wcl: off closes the window", not env.WM_WhisperLogsFrame:IsShown())
Fire(wlFrame, "CHAT_MSG_WHISPER", "hello", "Bob-Testrealm")
check("wcl: off, whispers ignored", #env.WhisperLogsDB.whispers == 1)
WM:SetModuleOn("WhisperLogs", true)
Fire(wlFrame, "CHAT_MSG_WHISPER", "hello", "Bob-Testrealm")
check("wcl: back on, listed again", #env.WhisperLogsDB.whispers == 2)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
