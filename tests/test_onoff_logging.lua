-- Turning the logging modules off and on (Auto Logger, Mail & Trade
-- Logger, Instance Tracker, Battlegrounds & Arenas, Your Characters, and
-- the Nova listener), and their guided-setup pages.
-- Usage: lua5.1 test_onoff_logging.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
env.time = function() return now end
env.date = function(fmt, t) return os.date("!" .. fmt, t) end
env.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
env.bit = { band = function(a, b)
    local r, bitv = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
        a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
    end
    return r
end }
local inside, kind, instName, maxPlayers = false, "none", nil, 5
env.IsInInstance = function() return inside, kind end
env.GetInstanceInfo = function() return instName, kind, 1, "Normal", maxPlayers, 0, false, 100 end
env.UnitXP = function() return 1000 end
env.UnitXPMax = function() return 50000 end
env.UnitLevel = function() return 60 end
env.UnitName = function() return "Tanky" end
env.GetRealmName = function() return "Spineshatter" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitExists = function(u) return u == "player" end
env.UnitIsGroupLeader = function() return false end
env.GetMoney = function() return 12345 end
-- Logging
local chatLog, combatLog = {}, {}
env.LoggingChat = function(v) chatLog[#chatLog + 1] = v end
env.LoggingCombat = function(v) combatLog[#combatLog + 1] = v end
local cvars = { advancedCombatLogging = "1" }
env.GetCVar = function(k) return cvars[k] end
env.SetCVar = function(k, v) cvars[k] = v end
-- Mailbox: one mail with 5g from Bob
local inbox = {}
env.GetInboxNumItems = function() return #inbox end
env.GetInboxHeaderInfo = function(i) local m = inbox[i]; if m then return nil, nil, m.sender, m.subject, m.money, nil, nil, false end end
env.GetInboxInvoiceInfo = function() return nil end
env.GetInboxItem = function() return nil end
env.GetInboxItemLink = function() return nil end
-- Battlegrounds
local winner
env.GetBattlefieldWinner = function() return winner end
env.GetNumBattlefieldScores = function() return 0 end
env.RequestBattlefieldScoreData = function() end
env.ChatFrame_AddMessageEventFilter = function() end

-- Which frames listen for what (several register at file load)
local listeners = {}
function W.Frame:RegisterEvent(ev)
    listeners[ev] = listeners[ev] or {}
    table.insert(listeners[ev], self)
end
local function Fire(ev, ...)
    for _, f in ipairs(listeners[ev] or {}) do W.fire(f, "OnEvent", ev, ...) end
end
local function Owner(ev, test)
    for _, f in ipairs(listeners[ev] or {}) do if test(f) then return f end end
end

W.load("Core.lua")
W.load("UI.lua")
for _, m in ipairs({ "AutoLogger", "MailLogger", "InstanceTracker", "PvPLog", "AltTracker", "NovaCompat" }) do
    W.load("Modules/" .. m .. ".lua")
end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local tickers = {}
WM.RunTicker = function(_, fn) tickers[#tickers + 1] = fn end

local AL, ML, IT = WM.modules.AutoLogger, WM.modules.MailLogger, WM.modules.InstanceTracker
local Log, Alts, Nova = WM.modules.PvPLog, WM.modules.AltTracker, WM.Nova

local pass, fail = 0, 0
local function check(label, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", label, "\n") end
end
local function Said(text)
    for _, l in ipairs(W.printed) do if tostring(l):find(text, 1, true) then return true end end
end

-- ---- Off before ever starting: events registered at load do nothing ----
WM:SetModuleOn("AutoLogger", false)
WM:SetModuleOn("MailLogger", false)
check("off before starting: no errors", true)
local mailFrame = Owner("MAIL_SHOW", function() return true end)
inside, kind, instName, maxPlayers = true, "raid", "Karazhan", 10
Fire("ZONE_CHANGED_NEW_AREA")
Fire("MAIL_SHOW")
W.fire(mailFrame, "OnUpdate", 1)
check("off: Auto Logger doesn't start the combat log", #combatLog == 0 and env.AutoLoggerDB == nil)
check("off: Mail Logger doesn't touch its saved data", env.MailLoggerDB == nil)
Fire("MAIL_CLOSED")
inside, kind, instName = false, "none", nil

-- ---- Setup pages build on never-started modules ----
local function Page(name, m)
    local p = WM.UI:CreatePanel({ name = "WM_TestSetup" .. name, title = "t" })
    local page = p:NewPage()
    local ok, err = pcall(m.SetupPage, m, page.layout)
    check(name .. ": setup page builds (" .. tostring(err) .. ")", ok)
    pcall(page.layout.Reflow, page.layout)
    return page.layout
end
local function Box(L, label)
    for _, w in ipairs(L.widgets) do
        local t = rawget(w, "Text") and w.Text:GetText()
        if t and t:find(label, 1, true) then return w end
    end
end
local function Notes(L)
    local all = {}
    for _, w in ipairs(L.widgets) do
        local t = w.GetText and w:GetText()
        if type(t) == "string" then all[#all + 1] = t end
    end
    return table.concat(all, "\n")
end

local L = Page("AutoLogger", AL)
local b = Box(L, "Log combat in 5-man")
check("AutoLogger page: defaults filled in", env.AutoLoggerDB.enableCombatLog == true and b and not b:GetChecked())
W.click(b)
check("AutoLogger page: dungeon box writes", env.AutoLoggerDB.enableInDungeons == true)
W.click(b)
check("AutoLogger page: and back", env.AutoLoggerDB.enableInDungeons == false)
check("AutoLogger page: says what turning it off does", Notes(L):find("carries on", 1, true) ~= nil)
check("AutoLogger page: no logging started by the page", #chatLog == 0 and #combatLog == 0)

L = Page("MailLogger", ML)
b = Box(L, "Log trades")
check("MailLogger page: settings read", b and b:GetChecked())
W.click(b)
check("MailLogger page: trades box writes", env.MailLoggerDB.logTrades == false)
W.click(b)
check("MailLogger page: and back", env.MailLoggerDB.logTrades == true)

L = Page("InstanceTracker", IT)
b = Box(L, "Say when I enter")
W.click(b)
check("InstanceTracker page: writes", env.InstanceTrackerDB.enterMessage == false)
W.click(b)
check("InstanceTracker page: and back", env.InstanceTrackerDB.enterMessage == true)

L = Page("PvPLog", Log)
b = Box(L, "Result in chat")
W.click(b)
check("PvPLog page: writes", env.PvPLogDB.announce == false)
W.click(b)
check("PvPLog page: and back", env.PvPLogDB.announce == true)

L = Page("AltTracker", Alts)
check("AltTracker page: explains what it records", Notes(L):find("What it records", 1, true) ~= nil)
check("AltTracker page: doesn't record anything itself", next(env.AltTrackerDB.chars) == nil)

-- ---- Auto Logger ----
WM:SetModuleOn("AutoLogger", true)
AL:Initialize()
check("on: chat log switched on", chatLog[#chatLog] == 1)
inside, kind, instName = true, "raid", "Karazhan"
Fire("ZONE_CHANGED_NEW_AREA")
check("on: combat log starts in a raid", combatLog[#combatLog] == 1 and AL:IsCurrentlyLogging())
AL:Toggle()
WM:SetModuleOn("AutoLogger", false)
check("off: window closes", not env.WM_AutoLoggerSettings:IsShown())
check("off: logging already on is left alone", combatLog[#combatLog] == 1)
local n = #combatLog
inside, kind, instName = false, "none", nil
Fire("ZONE_CHANGED_NEW_AREA")
check("off: leaving the raid doesn't touch logging", #combatLog == n)
inside, kind, instName = true, "raid", "Karazhan"
Fire("PLAYER_ENTERING_WORLD")
check("off: entering a raid doesn't either", #combatLog == n)
inside, kind, instName = false, "none", nil
WM:SetModuleOn("AutoLogger", true)
check("on again: the combat log it started stops outside", combatLog[#combatLog] == 0 and #combatLog == n + 1)
inside, kind, instName = true, "raid", "Karazhan"
Fire("ZONE_CHANGED_NEW_AREA")
check("on again: raids logged", combatLog[#combatLog] == 1)
inside, kind, instName = false, "none", nil
Fire("ZONE_CHANGED_NEW_AREA")

-- ---- Mail & Trade Logger ----
WM:SetModuleOn("MailLogger", true)
ML:Initialize()
local function TakeMail()
    inbox = { { sender = "Bob", subject = "Gold", money = 50000 } }
    Fire("MAIL_SHOW")
    W.fire(mailFrame, "OnUpdate", 1)    -- the baseline
    inbox = {}
    W.fire(mailFrame, "OnUpdate", 1)    -- held once (an empty read)
    W.fire(mailFrame, "OnUpdate", 1)    -- logged
    Fire("MAIL_CLOSED")
end
TakeMail()
local log = env.MailLoggerDB.characters["Tanky-Spineshatter"].log
check("on: mail taken is logged", #log == 1 and log[1].data.amount == 50000)
ML:Toggle()
WM:SetModuleOn("MailLogger", false)
check("off: window closes", not env.WM_MailLoggerFrame:IsShown())
TakeMail()
check("off: mail isn't logged", #log == 1)
-- Trade tagging asks Instance Tracker only while it's on
local asked = 0
local realCurrent = IT.Current
IT.Current = function() asked = asked + 1 end
WM:SetModuleOn("MailLogger", true)
WM:SetModuleOn("InstanceTracker", false)
ML:AddTradeLogEntry({ partner = "Bob", received = { money = 100, items = {} }, given = { money = 0, items = {} } })
check("Instance Tracker off: not asked for the run", asked == 0)
WM:SetModuleOn("InstanceTracker", true)
ML:AddTradeLogEntry({ partner = "Bob", received = { money = 100, items = {} }, given = { money = 0, items = {} } })
check("Instance Tracker on: asked", asked == 1)
IT.Current = realCurrent
TakeMail()
check("on again: mail logged", #log == 2)

-- ---- Instance Tracker ----
IT:Initialize()
inside, kind, instName = true, "party", "The Deadmines"
IT:OnEvent("PLAYER_ENTERING_WORLD")
local runs = IT:Runs()
check("on: entering logs a run", #runs == 1 and IT:Current() == runs[1])
IT:Toggle()
WM:SetModuleOn("InstanceTracker", false)
check("off: window closes", not env.WM_InstanceTrackerFrame:IsShown())
check("off: the run you're in ends quietly", IT:Current() == nil and runs[1].loggedOut and runs[1].left == now)
IT:OnEvent("CHAT_MSG_MONEY", "You loot 5 Gold")
check("off: loot isn't counted", runs[1].gold == 0)
instName = "Wailing Caverns"
IT:OnEvent("PLAYER_ENTERING_WORLD")
check("off: a new instance isn't logged", #runs == 1)
W.printed = {}
for _, fn in ipairs(tickers) do fn() end
check("off: the lockout ticker is quiet", #W.printed == 0)
-- Its tooltip asks Mail Logger only while that's on
local traded = 0
local realGold = ML.GoldTradedInRun
ML.GoldTradedInRun = function() traded = traded + 1; return 0, 0, 0 end
WM:SetModuleOn("MailLogger", false)
IT:ShowRunTooltip(env.UIParent or W.NewFrame(), runs[1])
check("Mail Logger off: not asked for trades", traded == 0)
WM:SetModuleOn("MailLogger", true)
IT:ShowRunTooltip(env.UIParent or W.NewFrame(), runs[1])
check("Mail Logger on: asked", traded == 1)
ML.GoldTradedInRun = realGold
instName = "The Deadmines"
now = now + 60
WM:SetModuleOn("InstanceTracker", true)
check("on again inside: the same run carries on", #runs == 1 and IT:Current() == runs[1] and runs[1].left == 0)
IT:OnEvent("CHAT_MSG_MONEY", "You loot 5 Gold")
check("on again: loot counted", runs[1].gold == 50000)
inside, kind, instName = false, "none", nil
IT:OnEvent("PLAYER_ENTERING_WORLD")

-- ---- Nova listener ----
local heard = 0
local realOn = Nova.OnAddonMessage
Nova.OnAddonMessage = function() heard = heard + 1 end
local novaFrame = Owner("CHAT_MSG_ADDON", function() return true end)
check("Nova: started with Instance Tracker", novaFrame ~= nil)
WM:SetModuleOn("WorldTimers", false)
W.fire(novaFrame, "OnEvent", "CHAT_MSG_ADDON", "NIT", "x", "PARTY", "Lead")
check("Nova: listens with Instance Tracker on", heard == 1 and Nova:IsActive())
WM:SetModuleOn("InstanceTracker", false)
W.fire(novaFrame, "OnEvent", "CHAT_MSG_ADDON", "NIT", "x", "PARTY", "Lead")
check("Nova: quiet with Instance Tracker and World Timers off", heard == 1 and not Nova:IsActive())
WM:SetModuleOn("WorldTimers", true)
W.fire(novaFrame, "OnEvent", "CHAT_MSG_ADDON", "NIT", "x", "PARTY", "Lead")
check("Nova: listens for World Timers too", heard == 2)
Nova.OnAddonMessage = realOn
check("Nova: reset notices are Instance Tracker's (off: ignored)", Nova:OnAddonMessage("NIT", "x", "PARTY", "Lead") == nil)
WM:SetModuleOn("InstanceTracker", true)

-- ---- Battlegrounds & Arenas ----
Log:Initialize()
inside, kind, instName = true, "pvp", "Warsong Gulch"
Log:OnEvent("PLAYER_ENTERING_WORLD")
local matches = Log:Matches()
check("on: a match starts", #matches == 1 and Log:Current() == matches[1])
Log:Toggle()
W.printed = {}
WM:SetModuleOn("PvPLog", false)
check("off: window closes", not env.WM_PvPLogFrame:IsShown())
check("off: the match ends as left, without a chat line", Log:Current() == nil and matches[1].result == "left" and #W.printed == 0)
Log:OnEvent("PLAYER_ENTERING_WORLD")
check("off: a new match isn't logged", #matches == 1)
WM:SetModuleOn("PvPLog", true)
check("on again inside: logged from now", #matches == 2 and Log:Current() == matches[1])
winner = 1
Log:OnEvent("UPDATE_BATTLEFIELD_SCORE")
check("on again: the result is read", Log:Current() == nil and matches[1].done)
inside, kind, instName, winner = false, "none", nil, nil

-- ---- Your Characters ----
Alts:Initialize()
local chars = env.AltTrackerDB.chars
check("on: this character saved", chars["Tanky-Spineshatter"] ~= nil)
Alts:Toggle()
WM:SetModuleOn("AltTracker", false)
check("off: window closes", not env.WM_AltTrackerFrame:IsShown())
chars["Tanky-Spineshatter"] = nil
W.timers = {}
Fire("PLAYER_MONEY")
Fire("PLAYER_LOGOUT")
check("off: nothing saved, nothing scheduled", chars["Tanky-Spineshatter"] == nil and #W.timers == 0)
WM:SetModuleOn("AltTracker", true)
check("on again: saved straight away", chars["Tanky-Spineshatter"] ~= nil)
Fire("PLAYER_MONEY")
check("on again: changes saved", #W.timers == 1)
W.runTimers()
-- The tooltip asks Crits and Attunements only while they're on
local crit, att = 0, 0
WM.Crits = { BestLine = function() crit = crit + 1 end }
WM.Attunements = { TooltipLines = function() att = att + 1 end }
WM:SetModuleOn("Crits", false)
WM:SetModuleOn("Attunements", false)
Alts:ShowTooltip(W.NewFrame(), chars["Tanky-Spineshatter"])
check("Crits and Attunements off: not asked", crit == 0 and att == 0)
WM:SetModuleOn("Crits", true)
WM:SetModuleOn("Attunements", true)
Alts:ShowTooltip(W.NewFrame(), chars["Tanky-Spineshatter"])
check("Crits and Attunements on: asked", crit == 1 and att == 1)
-- GearScore worked out only with GearScore on
local scored = 0
WM.GearScore = { GearScoreFor = function() scored = scored + 1; return 1000, 100, true end }
env.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:1|h[Hat]|h" end end
WM:SetModuleOn("GearScore", false)
Alts:Update()
check("GearScore off: not scored", scored == 0)
WM:SetModuleOn("GearScore", true)
Alts:Update()
check("GearScore on: scored", scored == 1 and chars["Tanky-Spineshatter"].gearScore == 1000)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
