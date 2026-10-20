-- Chat Filter, and Keyword Monitor honouring it. Usage: lua5.1 test_chatfilter.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Record chat frame filters and every frame the modules create
local chatFilters = {}
env.ChatFrame_AddMessageEventFilter = function(event, fn) chatFilters[event] = fn end
env.PlaySound = function() end
local frames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); frames[#frames + 1] = f; return f end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/KeywordMonitor.lua")
W.load("Modules/ChatFilter.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local CF, KM = WM.modules.ChatFilter, WM.modules.KeywordMonitor
CF:Initialize()
KM:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- normalising and matching ----
local N = CF.Normalise
check("lower case, single spaces", N("  Guild   LOOT run ") == "guild loot run")
check("colour codes stripped", N("|cffff0000Guild|r Loot Run") == "guild loot run")
check("item link reads as its name",
    N("WTS |cffa335ee|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r cheap") == "wts [warglaive of azzinoth] cheap")

check("starts enabled, filtering channels only", env.ChatFilterDB.enabled and env.ChatFilterDB.types.channels
    and not env.ChatFilterDB.types.say and not env.ChatFilterDB.types.whisper)
check("hooks channel, say, yell and whisper", chatFilters.CHAT_MSG_CHANNEL and chatFilters.CHAT_MSG_SAY
    and chatFilters.CHAT_MSG_YELL and chatFilters.CHAT_MSG_WHISPER)

check("add phrase", CF:AddPhrase("Guild Loot Run") == true)
check("duplicate (any case) refused", CF:AddPhrase("guild loot RUN") == false and #CF:GetPhrases() == 1)
check("empty phrase refused", CF:AddPhrase("   ") == false)
check("phrase kept as typed", CF:GetPhrases()[1] == "Guild Loot Run")

check("match anywhere, any case", CF:Match("LF2M <Guild Loot Run> BT, whisper me") == "guild loot run")
check("no match for a different phrase", CF:Match("guild run loot tonight") == nil)
check("plain text, not a pattern", (CF:AddPhrase("50% off") and CF:Match("everything 50% off!")) ~= nil)
check("pattern chars don't act as wildcards", CF:Match("everything 50x off") == nil)

-- ---- the chat frame filter ----
local filter = chatFilters.CHAT_MSG_CHANNEL
local function Chat(event, msg, sender, lineID)
    -- args after sender: language, channelName, target, flags, zoneID, index, baseName, langID, lineID
    return chatFilters[event](nil, event, msg, sender, "", "2. Trade - City", "", "", 0, 2, "Trade", 0, lineID)
end
check("matching channel message hidden", Chat("CHAT_MSG_CHANNEL", "Guild Loot Run BT 25", "Spammer", 1) == true)
-- Every chat tab runs the filter for a message before the next one arrives
check("same line in another chat tab: same answer", Chat("CHAT_MSG_CHANNEL", "Guild Loot Run BT 25", "Spammer", 1) == true)
check("other channel message shown", Chat("CHAT_MSG_CHANNEL", "LFM Karazhan", "Raider", 2) == false)
check("counted once per message, not per tab", CF:HiddenCount("Guild Loot Run") == 1 and CF:HiddenTotal() == 1)
check("own messages never hidden", Chat("CHAT_MSG_CHANNEL", "Guild Loot Run? who runs it", "Me-Testrealm", 3) == false)
check("say not filtered by default", Chat("CHAT_MSG_SAY", "Guild Loot Run", "Spammer", 4) == false)
env.ChatFilterDB.types.say = true
check("say filtered when ticked", Chat("CHAT_MSG_SAY", "Guild Loot Run", "Spammer", 5) == true)
check("yell follows the say toggle", Chat("CHAT_MSG_YELL", "GUILD LOOT RUN!!", "Spammer", 6) == true)
env.ChatFilterDB.types.say = false
CF:SetModuleEnabled(false)
check("nothing hidden while off", Chat("CHAT_MSG_CHANNEL", "Guild Loot Run", "Spammer", 7) == false)
CF:SetModuleEnabled(true)

-- ---- Keyword Monitor sees only what the filter lets through ----
local kmFrame
for _, f in ipairs(frames) do
    local h = f:GetScript("OnEvent")
    if h and debug.getinfo(h, "S").source:find("KeywordMonitor", 1, true) then kmFrame = f end
end
check("found Keyword Monitor's chat handler", kmFrame ~= nil)
env.KeywordMonitorDB.keywords = { ["bt"] = true }
env.KeywordMonitorDB.results = {}
local function KMChat(msg, sender)
    W.fire(kmFrame, "OnEvent", "CHAT_MSG_CHANNEL", msg, sender, "", "2. Trade - City", "", "", 0, 2, "Trade", 0, 99)
end
KMChat("LF healer for BT tonight", "Raider")
local afterClean = #env.KeywordMonitorDB.results
check("unfiltered message reaches Keyword Monitor", afterClean == 1)
KMChat("Guild Loot Run BT, all welcome", "Spammer")
check("filtered message never reaches Keyword Monitor", #env.KeywordMonitorDB.results == afterClean)
CF:SetModuleEnabled(false)
KMChat("Guild Loot Run BT again", "Spammer2")
check("with the filter off, Keyword Monitor sees it", #env.KeywordMonitorDB.results == afterClean + 1)
CF:SetModuleEnabled(true)

-- ---- panels ----
local p = CF:CreateUI()
p:Show()
check("filter panel fits the screen", p:GetHeight() <= 700)
check("filter panel closes on Escape", (function()
    for _, n in ipairs(env.UISpecialFrames) do if n == "WM_ChatFilterFrame" then return true end end
end)())
local function NoteTexts(panel)
    local out = {}
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "_text")
        if type(t) == "string" then out[#out + 1] = t end
    end
    return table.concat(out, "\n")
end
check("filter panel warns it runs before Keyword Monitor",
    NoteTexts(p):find("applied before Keyword Monitor", 1, true) ~= nil)
check("one list row per phrase", p.rows[1] and p.rows[1].text:GetText() == "Guild Loot Run"
    and p.rows[2] and p.rows[2].text:GetText() == "50% off" and not p.emptyText:IsShown())
-- channel, say and yell lines above: three hidden by this phrase
check("row shows its hidden count", CF:HiddenCount("Guild Loot Run") == 3
    and p.rows[1].count:GetText():find("3 hidden", 1, true) ~= nil)
W.click(p.rows[2].remove)
check("Remove deletes that phrase", #CF:GetPhrases() == 1 and not p.rows[2]:IsShown())

local addBox
for _, w in ipairs(p.layout.widgets) do if rawget(w, "editBox") then addBox = w end end
addBox.editBox:SetText("  WTS Boost ")
W.fire(addBox.editBox, "OnEnterPressed")
check("add box adds a trimmed phrase", CF:GetPhrases()[2] == "WTS Boost" and addBox.editBox:GetText() == "")
check("panel list updated", p.rows[2]:IsShown() and p.rows[2].text:GetText() == "WTS Boost")

local channelsCB
for _, w in ipairs(p.layout.widgets) do
    local t = rawget(w, "Text")
    if t and t:GetText() and t:GetText():find("Public channels", 1, true) then channelsCB = w end
end
W.click(channelsCB)
check("chat type checkbox writes", env.ChatFilterDB.types.channels == false)
W.click(channelsCB)

local kp = KM:CreateMainFrame()
kp:Show()
check("Keyword Monitor warns filters run first",
    NoteTexts(kp):find("Chat Filter is applied before Keyword Monitor", 1, true) ~= nil)
check("Keyword Monitor note shows filter state", NoteTexts(kp):find("on with 2 phrase", 1, true) ~= nil)

CF:ClearPhrases()
check("clear removes every phrase", #CF:GetPhrases() == 0 and CF:Match("Guild Loot Run") == nil)
check("status reflects no phrases", CF:GetQuickStatus():find("No phrases", 1, true) ~= nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
