-- Gold trade alerts and the trade log's instance tag (Mail & Trade Logger,
-- with Instance Tracker). Usage: lua5.1 test_trades.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local allFrames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); allFrames[#allFrames + 1] = f; return f end

local now = 1800000000
env.GetServerTime = function() return now end
env.time = function() return now end
env.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
env.UnitName = function(u) if u == "player" then return "Tanky" end; if u == "NPC" then return "Booster" end end
env.GetRealmName = function() return "Spineshatter" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitLevel = function() return 40 end
env.UnitXP = function() return 0 end
env.UnitXPMax = function() return 1000 end
env.UnitExists = function(u) return u == "player" end
env.IsInGroup = function() return false end
env.IsInRaid = function() return false end
local inside, instName = false, nil
env.IsInInstance = function() return inside, inside and "party" or "none" end
env.GetInstanceInfo = function() return instName, "party", 1, "Normal", 5, 0, false, 36 end
env.ERR_TRADE_COMPLETE = "Trade complete."
local playerMoney, targetMoney = 0, 0
env.GetPlayerTradeMoney = function() return playerMoney end
env.GetTargetTradeMoney = function() return targetMoney end
local playerItems, targetItems = {}, {}
env.GetTradePlayerItemInfo = function(i) local it = playerItems[i]; if it then return it, "tex", 1 end end
env.GetTradeTargetItemInfo = function(i) local it = targetItems[i]; if it then return it, "tex", 1 end end
env.GetTradePlayerItemLink = function(i) return playerItems[i] and ("[" .. playerItems[i] .. "]") end
env.GetTradeTargetItemLink = function(i) return targetItems[i] and ("[" .. targetItems[i] .. "]") end
local handler
env.LinkUtil = { RegisterLinkHandler = function(kind, fn) if kind == "wmlink" then handler = fn end end }
env.LinkProcessorResponse = { Handled = 2 }

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/MailLogger.lua", "Modules/NovaCompat.lua", "Modules/InstanceTracker.lua" }) do
    W.load(f)
end
local WM = W.WM
local ML, IT = WM.modules.MailLogger, WM.modules.InstanceTracker
env.WatchingMachineDB = { theme = "Default" }
ML:Initialize()
IT:Initialize()
WM:SetupChatLinks()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local mlEvents
for _, f in ipairs(allFrames) do
    local h = f._scripts.OnEvent
    if h and debug.getinfo(h, "S").source:find("MailLogger", 1, true) then mlEvents = f end
end
local function Trade(give, get, gItems, tItems, complete)
    playerMoney, targetMoney = give or 0, get or 0
    playerItems, targetItems = gItems or {}, tItems or {}
    W.fire(mlEvents, "OnEvent", "TRADE_SHOW")
    W.fire(mlEvents, "OnEvent", "TRADE_ACCEPT_UPDATE")
    if complete ~= false then W.fire(mlEvents, "OnEvent", "UI_INFO_MESSAGE", 0, "Trade complete.") end
    W.fire(mlEvents, "OnEvent", "TRADE_CLOSED")
end
local function Log() return ML:GetCharacterTradeLog() end
local function Last() return W.printed[#W.printed] or "" end

-- ---- Outside an instance ----
env.MailLoggerDB.showNotifications = false   -- only the gold alert
local n = #W.printed
Trade(0, 5000000)   -- received 500g
check("trade logged", #Log() == 1 and Log()[1].partner == "Booster" and Log()[1].received.money == 5000000)
check("gold received: chat line", #W.printed == n + 1 and Last():find("Trade with", 1, true) ~= nil
    and Last():find("Booster", 1, true) ~= nil and Last():find("received", 1, true) ~= nil
    and Last():find("500g", 1, true) ~= nil)
check("no instance outside", Log()[1].instance == nil and not Last():find("(in ", 1, true))
Trade(200000, 0)    -- gave 20g
check("gold given: chat line", Last():find("gave", 1, true) ~= nil and Last():find("20g", 1, true) ~= nil)
Trade(150000, 2000000, { "Linen Cloth" }, { "Runecloth", "Silk" })
check("both ways, with items", Last():find("received", 1, true) ~= nil and Last():find("gave", 1, true) ~= nil
    and Last():find("2 item(s)", 1, true) ~= nil)
n = #W.printed
Trade(0, 0, { "Linen Cloth" }, {})
check("items only: no gold line (notifications off)", #W.printed == n and #Log() == 4)
env.MailLoggerDB.showNotifications = true
Trade(0, 0, {}, { "Silk" })
check("items only, notifications on: a line", #W.printed == n + 1)
n = #W.printed
Trade(0, 9999, nil, nil, false)
check("cancelled trade: nothing", #W.printed == n and #Log() == 5)
-- Localised "trade complete" text
env.ERR_TRADE_COMPLETE = "Handel abgeschlossen."
playerMoney, targetMoney = 0, 10000
W.fire(mlEvents, "OnEvent", "TRADE_SHOW")
W.fire(mlEvents, "OnEvent", "UI_INFO_MESSAGE", 0, "Handel abgeschlossen.")
W.fire(mlEvents, "OnEvent", "TRADE_CLOSED")
check("other client languages: detected from ERR_TRADE_COMPLETE", #Log() == 6)
env.ERR_TRADE_COMPLETE = "Trade complete."

-- ---- Inside an instance ----
inside, instName = true, "The Deadmines"
IT:OnEvent("PLAYER_ENTERING_WORLD")
local run = IT:Current()
check("run started", run and run.id)
Trade(0, 1000000)   -- 100g in the Deadmines
check("trade tagged with the instance and run", Log()[1].instance == "The Deadmines" and Log()[1].runId == run.id)
check("chat line says where", Last():find("(in The Deadmines)", 1, true) ~= nil)
Trade(300000, 0)
local received, given, count = ML:GoldTradedInRun(run.id)
check("run totals: received, given, count", received == 1000000 and given == 300000 and count == 2)
check("other runs: none", select(3, ML:GoldTradedInRun(9999)) == 0)
inside = false
IT:OnEvent("PLAYER_ENTERING_WORLD")
-- An instance the tracker doesn't know about (e.g. tracker off): still tagged by name
inside, instName = true, "Wailing Caverns"
local current = IT.Current
IT.Current = function() return nil end
Trade(0, 50000)
check("instance name without a run", Log()[1].instance == "Wailing Caverns" and Log()[1].runId == nil)
IT.Current = current
inside = false

-- ---- The link ----
local link = Last():match("(wmlink:mltrades:[^|]*)|h")
check("chat line is a link", link ~= nil)
handler(link, "x", {}, {})
local frame = ML.mainFrame
check("clicking it opens the trade log", frame and frame:IsShown() and ML.currentTab == "trades")
ML:RefreshTradesLog()
check("trade list shows the instance", ML.tradeRows[1] and (ML.tradeRows[1].header:GetText() or ""):find("in Wailing Caverns", 1, true) ~= nil)

-- ---- Options ----
env.MailLoggerDB.showNotifications = false
env.MailLoggerDB.tradeGoldAlerts = false
n = #W.printed
Trade(0, 70000)
check("gold alert off: no line, still logged", #W.printed == n and Log()[1].received.money == 70000)
env.MailLoggerDB.tradeGoldAlerts = true
env.MailLoggerDB.logTrades = false
local size = #Log()
Trade(0, 80000)
check("logging off: alert still shows, nothing logged", #W.printed == n + 1 and #Log() == size)
env.MailLoggerDB.logTrades = true

local summary = ML.TradeSummary({ money = 10000, items = {} }, { money = 0, items = { 1 } })
check("summary helper", summary:find("received|r 1g", 1, true) ~= nil and summary:find("gave|r 1 item(s)", 1, true) ~= nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
