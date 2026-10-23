-- World Timers: layers, Terokkar towers, dailies, Darkmoon Faire, world
-- buffs, Songflowers, and Nova World Buffs data (wt_fixtures.lua was made
-- by the real LibSerialize / LibDeflate, sandboxed).
-- Usage: lua5.1 test_worldtimers.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
local F = dofile(REPO .. "/tests/wt_fixtures.lua")

local now = 1792004000                  -- 2026-10-14 18:53 UTC
local clock = 1000
env.GetServerTime = function() return now end
env.GetTime = function() return clock end
env.time = function() return now end
env.date = function(fmt, t) if fmt == "*t" then return { isdst = false } end return os.date("!" .. fmt, t) end
env.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
env.UnitName = function() return "Tanky" end
env.GetRealmName = function() return "Spineshatter" end
env.UnitFactionGroup = function() return "Horde" end
env.GetCurrentRegion = function() return 1 end
local mapID = 1955
env.C_Map = {
    GetBestMapForUnit = function() return mapID end,
    GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end,
}
px, py = 0.5, 0.5
local guids = {}
env.UnitGUID = function(u) return guids[u] end
env.IsInInstance = function() return false, "none" end
local buffs = {}
env.UnitBuff = function(_, i) local b = buffs[i]; if b then return b.name, nil, 0, nil, 7200, b.expires, nil, nil, nil, b.id end end
local widgets = {}
env.C_UIWidgetManager = { GetIconAndTextWidgetVisualizationInfo = function(id) return widgets[id] end }
local cleu
env.CombatLogGetCurrentEventInfo = function() return unpack(cleu, 1, 12) end
env.Ambiguate = function(n) return (n:gsub("%-Spineshatter$", "")) end
local sent = {}
env.SendChatMessage = function(m, c) sent[#sent + 1] = { m, c } end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/NovaCompat.lua", "Modules/WorldTimers.lua" }) do W.load(f) end
local WM = W.WM
local WT = WM.modules.WorldTimers
env.WatchingMachineDB = { theme = "Default" }
WT:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Last() return W.printed[#W.printed] or "" end
local function Creature(zoneUID, npc, spawn) return "Creature-0-4395-530-" .. zoneUID .. "-" .. npc .. "-" .. (spawn or "0000ABCDEF") end
local function Target(guid) guids.target = guid; WT:OnEvent("PLAYER_TARGET_CHANGED") end
local function CLEU(sub, src, dst, dstName, spell) cleu = { now, sub, false, src, "x", 0, 0, dst, dstName, 0, 0, spell }; WT:OnEvent("COMBAT_LOG_EVENT_UNFILTERED") end
local data = function() return WT:Data() end

-- ---- Layers ----
check("no layer before seeing an NPC", WT:CurrentLayer() == nil and WT:LayerCount() == 0)
Target(Creature(11890, 18481))            -- A'dal
check("A'dal in Shattrath makes a layer", WT:LayerCount() == 1 and WT:CurrentLayer() == 11890)
Target(Creature(11872, 19232))            -- Innkeeper Haelthol on another layer
check("second layer, numbered by zone ID", WT:LayerCount() == 2 and WT:LayerNumber(11872) == 1 and WT:LayerNumber(11890) == 2)
check("you're on the one you last saw", WT:CurrentLayer() == 11872)
Target(Creature(11950, 12345))            -- some other NPC in Shattrath
check("other Shattrath NPCs don't make layers", WT:LayerCount() == 2)
check("layer age from the spawn ID", data().layers[11872].spawn and data().layers[11872].spawn <= now)
-- Following the layer into Terokkar
mapID = 1952
Target(Creature(12001, 22000))
check("a new zone is tied to the confirmed layer", data().layers[11872].layerMap[12001] == 1952 and WT:CurrentLayer() == 11872)
Target(Creature(12002, 22001))            -- a second instance of Terokkar: layer may have changed
check("two instances of one zone: layer unknown", WT:CurrentLayer() == nil)
Target(Creature(12001, 22000))
check("a mapped zone brings the layer back", WT:CurrentLayer() == 11872)
WT:OnEvent("GROUP_JOINED")
check("joining a group: layer unknown", WT:CurrentLayer() == nil)
Target(Creature(12555, 22000))
check("after a group join, zones aren't mapped", data().layers[11872].layerMap[12555] == nil)
Target(Creature(12001, 22000))
check("but known zones still show the layer", WT:CurrentLayer() == 11872)
clock = clock + 700
mapID = 1955
Target(Creature(11872, 18940))
check("Shattrath NPC again (10 min after the join): confirmed", WT:CurrentLayer() == 11872)

-- ---- Terokkar towers ----
mapID = 1952
WT:OnEvent("ZONE_CHANGED_NEW_AREA")
widgets = { [3097] = { state = 0 }, [3118] = { state = 0 }, [3119] = { state = 1, text = "Towers reset in 3:15" } }
WT:ReadTowers()
check("needs a creature targeted in Terokkar first", data().layers[11872].terokTowers == nil)
Target(Creature(12001, 22000))
WT:ReadTowers()
local layer = data().layers[11872]
check("tower reset read from the widget", layer.terokTowers == now + 3 * 3600 + 15 * 60 and layer.terokFaction == 3)
check("drift correction", WT.TerokEnd(now + 3600, now) == now + 3600 + math.floor(60 * 2.7507))
widgets[3111], widgets[3112] = { state = 1 }, { state = 1 }
WT:ReadTowers()
check("being captured: timer cleared", layer.terokTowers == nil)
widgets[3111], widgets[3112] = nil, nil
widgets[3119].text = "0:09"
WT:ReadTowers()
check("parses the short form too", layer.terokTowers == now + 540)
layer.terokWarned = nil
layer.terokTowers, layer.terokTowersTime = now + 570, now   -- drift makes that about 596 s
local n = #W.printed
WT:CheckTerokWarning(now)
check("10-minute warning", #W.printed == n + 1 and Last():find("Terokkar Forest towers reset in 10 minutes (Layer 1)", 1, true) ~= nil)
WT:CheckTerokWarning(now + 5)
check("only once", #W.printed == n + 1)
check("parser", WT.ParseTowerTime("2:05") == 7500 and WT.ParseTowerTime("nothing") == nil)
mapID = 1955

-- ---- Dailies ----
guids.npc = Creature(11872, 24369)       -- Wind Trader Zhareem
WT:OnEvent("GOSSIP_SHOW")
WT:OnEvent("QUEST_FINISHED")
check("heroic daily from Zhareem", WT:OnQuestAccepted(5, 11354) == "heroic" and WT:Daily("heroic") == "Hellfire Ramparts")
check("a one-argument QUEST_ACCEPTED works too", (function()
    guids.npc = Creature(11872, 24370); WT:OnEvent("GOSSIP_SHOW"); WT:OnEvent("QUEST_FINISHED")
    return WT:OnQuestAccepted(11376) == "dungeon" and WT:Daily("dungeon") == "Shadow Labyrinth" end)())
clock = clock + 500
check("a shared quest (no NPC) doesn't count", WT:OnQuestAccepted(5, 11342) == nil and WT:Daily("pvp") == nil)
check("gone after 24 hours", WT:Daily("heroic", now + 86400) == nil)

-- ---- Darkmoon Faire ----
local s, e = WT.DmfDates(2026, 11, 1, false)
check("Faire opens the Monday after the first Friday, 08:00 UTC (US)", s == 1794211200 and e == s + 7 * 86400)
check("EU opens at 02:00 UTC", (WT.DmfDates(2026, 11, 3, false)) == 1794211200 - 6 * 3600)
check("one hour earlier in summer time", (WT.DmfDates(2026, 11, 1, true)) == 1794211200 - 3600)
check("a month starting on a Friday", (WT.DmfDates(2027, 1, 1, false)) == 1799049600)
check("rotation", WT.DmfPlace(1):find("Terokkar") and WT.DmfPlace(3) == "Elwynn Forest" and WT.DmfPlace(11) == "Mulgore")
local d = WT:Dmf(now)            -- 14 Oct: October's Faire (5-12 Oct) is over
check("between Faires: the next one", d and not d.up and d.start == 1794211200 and d.place == "Mulgore")
d = WT:Dmf(1794211200 + 3600)
check("during the Faire: up, with the next place", d.up and d.ends == 1794211200 + 7 * 86400 and d.next.place == "Elwynn Forest")
-- Sayge's fortune
buffs = { { name = "Sayge's Dark Fortune of Agility", id = 23736, expires = clock + 7200 } }
CLEU("SPELL_AURA_APPLIED", "Creature-0-1-1-1-14822-1", nil, nil, 23736)
check("ignored when not on you", WT:DmfCooldown() == 0)
guids.player = "Player-1-0001"
CLEU("SPELL_AURA_APPLIED", "Creature-0-1-1-1-14822-1", "Player-1-0001", "Tanky", 23736)
check("fresh Sayge buff starts the 4-hour cooldown", WT:DmfCooldown() == 14400)
WT:TickDmf(3600)
check("counts down while you play", WT:DmfCooldown() == 10800)
buffs[1].expires = clock + 3000
WT:TickDmf(10800)
CLEU("SPELL_AURA_APPLIED", "x", "Player-1-0001", "Tanky", 23736)
check("an old buff (re-applied at login) doesn't restart it", WT:DmfCooldown() == 0)
buffs = {}

-- ---- World buffs ----
mapID = 1454
WT:OnYell("Be lifted by the rallying cry of your dragonslayers!", "Overlord Runthak")
CLEU("SPELL_AURA_APPLIED", Creature(11873, 14392), "Player-1-0001", "Tanky", 22888)
-- 11873 isn't mapped anywhere: goes to the current layer
check("Onyxia buff after the yell: timer on the layer", data().layers[11872].onyTimer == now)
now = now + 100
CLEU("SPELL_AURA_APPLIED", Creature(11873, 14720), "Player-1-0001", "Tanky", 22888)
check("no yell: no timer", data().layers[11872].nefTimer == nil)
local ony = data().layers[11872].onyTimer
n = #W.printed
WT:CheckBuffWarnings(ony + 21600 - 1800)
check("warning 30 minutes before", #W.printed == n + 1 and Last():find("Onyxia resets in 30m", 1, true) ~= nil)
WT:CheckBuffWarnings(ony + 21600 - 1795)
check("not twice", #W.printed == n + 1)
WT:CheckBuffWarnings(ony + 21600 + 5)
check("and when it can drop again", Last():find("A new Onyxia buff can be dropped now", 1, true) ~= nil)
CLEU("UNIT_DIED", nil, Creature(11873, 14392), "Overlord Runthak")
check("buff NPC killed", Last():find("Overlord Runthak has just been killed", 1, true) ~= nil)

-- ---- Songflowers ----
mapID = 1448
px, py = 0.401, 0.444                    -- Shatter Scar Vale
buffs = { { name = "Songflower Serenade", id = 15366, expires = clock + 3600 } }
CLEU("SPELL_AURA_APPLIED", "Player-1-0001", "Player-1-0001", "Tanky", 15366)
check("your own pick at a flower", data().layers[11872].flowers[5] == now and Last():find("Shatter Scar Vale", 1, true) ~= nil)
check("nearest flower", WT.NearestFlower(63.9, 6.0) == 1 and WT.NearestFlower(10, 10) == nil)
px, py = 0.639, 0.061
CLEU("SPELL_AURA_APPLIED", "Player-1-0002", "Player-1-0002", "Picker", 15366)
check("someone just logged in with it: not a pick", data().layers[11872].flowers[1] == nil)
clock = clock + 5
CLEU("SPELL_AURA_APPLIED", "Player-1-0002", "Player-1-0002", "Picker", 15366)
check("someone seen before picking: a pick", data().layers[11872].flowers[1] == now)
buffs = {}
mapID = 1955

-- ---- Nova World Buffs data ----
now = 1792004000
-- Fresh state for these
env.WorldTimersDB.realms = {}
local function NWB(body, dist, sender) return WT:OnNWBMessage(body, dist, sender or "Novauser-Spineshatter") end
check("Terokkar data from a yell", NWB(F.terokYell, "YELL") >= 1)
layer = data().layers[11872]
check("their tower timer, time and faction", layer.terokTowers == 1792014600 and layer.terokTowersTime == 1792003020 and layer.terokFaction == 3)
check("their zone map (string keys skipped)", layer.layerMap[11873] == 1952 and layer.layerMap[11879] == 1944 and layer.layerMap.created == nil)
check("their last-seen time", layer.lastSeenNPC == 1792002911)
check("same message again changes nothing", NWB(F.terokYell, "YELL") == 0)
local taken = NWB(F.dailiesGuild, "GUILD")
check("dailies from guild", taken >= 3 and WT:Daily("heroic") == "Hellfire Ramparts" and WT:Daily("dungeon") == "Shadow Labyrinth"
    and WT:Daily("pvp") == "Warsong Gulch")
check("their second layer", data().layers[11890] and data().layers[11890].lastSeenNPC == 1792001777)
NWB(F.buffsGuild, "GUILD")
check("world buff timers with a matching yell", data().layers[11872].rendTimer == 1792000000 and data().layers[11872].onyTimer == 1791990000)
check("their Songflower", data().layers[11872].flowers[3] == 1792003500)
check("a layer not seen for hours is ignored", NWB(F.staleYell, "YELL") == 0 and data().layers[11999] == nil)
env.WorldTimersDB.realms = {}
NWB(F.badBuffGuild, "GUILD")
check("a buff timer without a matching yell is ignored", data().layers[11872].rendTimer == nil)
check("low-level senders are ignored", NWB(F.lowLevel, "YELL") == nil)
check("old Nova versions are ignored", NWB(F.oldVersion, "GUILD") == nil)
check("wrong codec: ignored", NWB(F.terokYell, "GUILD") == nil)
n = #W.printed
local _, cmd = NWB(F.yellOny, "GUILD")
check("their 'buff about to drop' notice", cmd == "yell" and Last():find("Onyxia is about to drop (seen by Novauser)", 1, true) ~= nil)
NWB(F.npcKilled, "GUILD")
check("their NPC-killed notice", Last():find("Nefarian buff NPC has just been killed", 1, true) ~= nil)
check("layer roster messages are read and ignored", select(2, NWB(F.layerL, "GUILD")) == "l")
env.WorldTimersDB.listenNWB = false
check("listening off: ignored", NWB(F.terokYell, "YELL") == nil)
env.WorldTimersDB.listenNWB = true
-- Through the event, with AceComm framing (the long yell arrives in parts)
local body = F.terokYell
local parts = { body:sub(1, 254), body:sub(255) }
env.WorldTimersDB.realms = {}
if #body > 255 then
    WT:OnEvent("CHAT_MSG_ADDON", "NWB", "\001" .. parts[1], "YELL", "Novauser-Spineshatter")
    WT:OnEvent("CHAT_MSG_ADDON", "NWB", "\003" .. parts[2], "YELL", "Novauser-Spineshatter")
else
    WT:OnEvent("CHAT_MSG_ADDON", "NWB", (body:byte(1) <= 9 and "\004" or "") .. body, "YELL", "Novauser-Spineshatter")
end
check("through CHAT_MSG_ADDON", data().layers[11872] and data().layers[11872].terokTowers == 1792014600)
env.WorldTimersDB.realms = {}
WT:OnEvent("CHAT_MSG_ADDON", "NWB", (body:byte(1) <= 9 and "\004" or "") .. body, "YELL", "Tanky")
check("our own messages ignored", data().layers[11872] == nil)

-- ---- Expiry ----
env.WorldTimersDB.realms = {}
NWB(F.terokYell, "YELL")
WT:ExpireLayers(now + 9000)   -- not seen for 2.5 hours, towers still to reset
check("a layer with a live tower timer is kept", data().layers[11872] ~= nil)
WT:ExpireLayers(now + 8 * 3600)
check("an old layer with nothing running is dropped", data().layers[11872] == nil)

-- ---- Output ----
env.WorldTimersDB.realms = {}
NWB(F.terokYell, "YELL")
NWB(F.dailiesGuild, "GUILD")
local text = WT:AllText(now)
check("window text: layers, towers, dailies, Faire", text:find("Layer 1", 1, true) and text:find("Terokkar towers", 1, true)
    and text:find("Heroic daily: |cFFFFFFFFHellfire Ramparts", 1, true) and text:find("Darkmoon Faire opens in", 1, true))
check("short timers", WT:ShortTimers(now):find("(Terokkar L1:", 1, true) ~= nil)
WT:Report("guild")
check("sent to a channel", sent[#sent][2] == "GUILD" and sent[#sent][1]:find("^%[WM%]") ~= nil)
WT:Toggle()
check("window opens", env.WM_WorldTimersFrame:IsShown() and (env.WM_WorldTimersFrame.text:GetText() or ""):find("Layer", 1, true))
check("status", WT:GetQuickStatus():find("DMF", 1, true) ~= nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
