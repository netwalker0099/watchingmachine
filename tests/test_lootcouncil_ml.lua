-- Loot Council, part 3: running the session as master looter, and passing
-- on items you can't use. Items from the loot window go out for votes in
-- RCLootCouncil's messages; awards are given from the loot window or traded
-- (Gargul-style), announced and logged; test loot isn't given or logged.
-- Usage: lua5.1 test_lootcouncil_ml.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1793000000
env.GetServerTime = function() return now end
env.C_DateAndTime = false
env.GetRealmName = function() return "Nightslayer" end
local loaded = {}
env.IsAddOnLoaded = function(n) return loaded[n] or false end
env.C_AddOns = { IsAddOnLoaded = function(n) return loaded[n] or false end }
local inCombat = false
env.InCombatLockdown = function() return inCombat end
env.IsInRaid = function() return true end
env.IsInGroup = function() return true end
local raid = { { "Me", "PALADIN", "Player-4904-AAAA" }, { "Venhana", "PRIEST", "Player-4904-BBBB" },
    { "Taslan", "ROGUE", "Player-4904-CCCC" }, { "Pug", "MAGE", "Player-4904-DDDD" } }
local function Idx(u) return tonumber(tostring(u):match("^raid(%d+)$")) end
env.UnitExists = function(u) return u == "player" or u == "target" or (Idx(u) and raid[Idx(u)] ~= nil) or false end
env.UnitName = function(u)
    if u == "player" then return "Me" end
    if u == "NPC" then return env._tradePartner end
    if u == "target" then return "Lady Vashj" end
    return Idx(u) and raid[Idx(u)] and raid[Idx(u)][1]
end
env.UnitClass = function(u)
    if u == "player" then return "Paladin", "PALADIN" end
    local r = Idx(u) and raid[Idx(u)]; return r and r[2], r and r[2]
end
env.UnitGUID = function(u)
    if u == "player" then return raid[1][3] end
    local r = Idx(u) and raid[Idx(u)]; return r and r[3]
end
env.GetLootMethod = function() return "master", nil, 1 end          -- we're the loot master
env.UnitIsGroupLeader = function(u) return u == "raid1" or u == "player" end
env.GetGuildInfo = function() return "Socks and Sandals", "Officer", 1 end
env.GetNumGuildMembers = function() return 3 end
local guild = { { "Me-Nightslayer", "Officer", 1 }, { "Venhana-Nightslayer", "Officer", 1 }, { "Taslan-Nightslayer", "Raider", 3 } }
env.GetGuildRosterInfo = function(i) local g = guild[i]; return g[1], g[2], g[3] end
env.GetInstanceInfo = function() return "Serpentshrine Cavern", "raid", 4, "25 Player", 25, 0, false, 548, 25 end

-- Items: id -> { name, quality, ilvl, equipLoc, texture, classID, subclassID }
local items = {
    [30242] = { "Helm of the Vanquished Champion", 4, 120, "", "tex", 15, 0, "Paladin, Rogue, Shaman" },
    [30100] = { "Soul-Strider Boots", 4, 128, "INVTYPE_FEET", "tex", 4, 1 },        -- cloth
    [30020] = { "Fire-Cord of the Magus", 4, 128, "INVTYPE_WAIST", "tex", 4, 1 },
    [30106] = { "Belt of One-Hundred Deaths", 4, 128, "INVTYPE_WAIST", "tex", 4, 2 }, -- leather
    [29988] = { "The Nexus Key", 4, 141, "INVTYPE_2HWEAPON", "tex", 2, 10 },         -- staff
    [30247] = { "Leggings of the Vanquished Hero", 4, 120, "", "tex", 15, 0, "Hunter, Mage, Warlock" },
    [30027] = { "Boots of Courage Unending", 4, 128, "INVTYPE_FEET", "tex", 4, 4 },   -- plate
    [30236] = { "Chestguard of the Vanquished Champion", 4, 120, "", "tex", 15, 0, "Paladin, Rogue, Shaman" },
}
local function Id(x) return tonumber(tostring(x):match("item:(%d+)") or x) end
local function Info(x)
    local i = items[Id(x)]
    if not i then return nil end
    local s = tostring(x):match("item:([%-%d:]+)") or tostring(Id(x))
    return i[1], "|cffa335ee|Hitem:" .. s .. "|h[" .. i[1] .. "]|h|r", i[2], i[3], 0, "", "", 1, i[4], i[5]
end
env.GetItemInfo = Info
env.C_Item = { GetItemInfo = Info, GetItemInfoInstant = function(x)
    local i = items[Id(x)]; if i then return Id(x), "", "", i[4], i[5], i[6], i[7] end end }
env.ITEM_CLASSES_ALLOWED = "Classes: %s"
env.LOCALIZED_CLASS_NAMES_MALE = { PALADIN = "Paladin", ROGUE = "Rogue" }
-- The hidden tooltip reads the item's "Classes:" line
local tipLines = {}
local baseCreate = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = baseCreate(kind, name, parent, template)
    if kind == "GameTooltip" then
        f.SetOwner = function() end
        f.ClearLines = function() tipLines = {} end
        f.SetHyperlink = function(_, link)
            local i = items[Id(link)]
            tipLines = { i and i[1] or "?" }
            if i and i[8] then tipLines[2] = "Classes: " .. i[8] end
        end
        f.NumLines = function() return #tipLines end
        for n = 1, 4 do env[name .. "TextLeft" .. n] = { GetText = function() return tipLines[n] end } end
    end
    return f
end
env.GetInventoryItemLink = function() return nil end
env.RAID_CLASS_COLORS = {}
local afters = {}
env.C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end, NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end }
local function RunAfters() local a = afters; afters = {}; for _, fn in ipairs(a) do fn() end end
local sent, chat = {}, {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, body, channel, target) sent[#sent + 1] = { prefix, body, channel, target } end }
env.SendChatMessage = function(text, channel) chat[#chat + 1] = { text, channel } end
-- The loot window
local loot = {}
env.GetNumLootItems = function() return #loot end
env.GetLootSlotLink = function(i) return loot[i] end
local given = {}
env.GetMasterLootCandidate = function(slot, i) local r = raid[i]; return r and r[1] end
env.GiveMasterLoot = function(slot, i) given[#given + 1] = { slot, raid[i][1] }; loot[slot] = nil end
-- Trading
local inRange, traded, used = true, {}, {}
env.CheckInteractDistance = function() return inRange end
env.InitiateTrade = function(unit) traded[#traded + 1] = unit end
env.C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
    GetContainerItemID = function(bag, slot) if bag == 0 and slot == 2 then return 30236 end end,
    UseContainerItem = function(bag, slot) used[#used + 1] = bag .. ":" .. slot end }
env.ERR_TRADE_COMPLETE = "Trade complete."

env.WatchingMachineDB = { theme = "Default" }
for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/LootCouncil.lua", "Modules/LootCouncilCodec.lua",
    "Modules/LootCouncilRC.lua", "Modules/LootCouncilML.lua", "Modules/LootCouncilUI.lua", "Modules/LootCouncilFrames.lua" }) do
    W.load(f)
end
local WM = W.WM
local LC = WM.modules.LootCouncil
local RC, ML, Codec = LC.RC, LC.ML, WM.LootCodec

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- Our messages come back to us from the raid, as the game does; returns them unpacked
local un = Codec.NewUnframer()
local function Deliver()
    local out = {}
    for _ = 1, 10 do
        WM:FlushAddonQueue()
        if #sent == 0 then break end
        local batch = sent
        sent = {}
        for _, m in ipairs(batch) do
            local whole = un(m[1] .. m[3], m[2])
            if whole then
                local c, a = Codec.Unpack(whole)
                out[#out + 1] = { command = c, args = a, channel = m[3] }
                RC:OnAddonMessage(m[1], m[2], m[3], "Me")
            end
        end
    end
    return out
end
local function Find(list, cmd) for _, m in ipairs(list) do if m.command == cmd then return m end end end
local function From(sender, command, args)
    for _, part in ipairs(Codec.Pack(command, args)) do RC:OnAddonMessage("RCLC", part, "RAID", sender) end
end

LC:Initialize()
RunAfters()

-- ============ Can I use it? ============
check("a token for my class", RC.CanUse("item:30242") == true)
check("a token for other classes", RC.CanUse("item:30247") == false)
check("cloth: anyone", RC.CanUse("item:30100") == true)
check("a staff: not a paladin", RC.CanUse("item:29988") == false)
check("plate: a paladin can", RC.CanUse("item:30027") == true)
check("plate: a rogue can't", RC.CanUse("item:30027", "ROGUE") == false)
check("leather: a priest can't", RC.CanUse("item:30106", "PRIEST") == false)
check("a staff: a priest can", RC.CanUse("item:29988", "PRIEST") == true)

-- ============ The master looter ============
check("we're the master looter", ML:IsML())
local council = ML:Council()
check("council: officers in the group and us", council["Me-Nightslayer"] and council["Venhana-Nightslayer"]
    and not council["Taslan-Nightslayer"] and not council["Pug-Nightslayer"])
LC.DB().mlCouncilNames = "Taslan"
check("council: plus listed names", ML:Council()["Taslan-Nightslayer"] ~= nil)
LC.DB().mlCouncilNames = ""

loot = { "|cffa335ee|Hitem:30242::::::::70|h[Helm of the Vanquished Champion]|h|r",
    "|cff0070dd|Hitem:1234|h[Blue thing]|h|r", "|cffa335ee|Hitem:30247::::::::70|h[Leggings of the Vanquished Hero]|h|r" }
items[1234] = { "Blue thing", 3, 100, "INVTYPE_NECK", "tex", 4, 0 }
check("loot window: epic items listed", ML:ScanLoot() == 2 and #ML.pending == 2 and ML.pending[1].slot == 1 and ML.pending[1].boss == "Lady Vashj")
check("the master looter panel opens", env.WM_LootMLFrame and env.WM_LootMLFrame:IsShown())
check("loot window again: nothing twice", ML:ScanLoot() == 0)
check("sent for votes", ML:Start(false) == true and #ML.pending == 0)
local out = Deliver()
check("settings, council and loot table sent to the raid", Find(out, "StartHandleLoot") and Find(out, "mldb") and Find(out, "lootTable")
    and Find(out, "lootTable").channel == "RAID")
local c = Find(out, "council")
check("council sent by GUID", c and c.args[1]["4904-AAAA"] and c.args[1]["4904-BBBB"] and not c.args[1]["4904-CCCC"])
check("our own session from our messages", RC.session and RC.session.ml == "Me-Nightslayer" and RC.session.items[2].itemID == 30247)
-- Auto-pass: the leggings are for other classes
check("autopass: the item we can't use isn't asked", RC.session.items[2].answered == "AUTOPASS")
local ack = Find(out, "lootAck")
check("autopass: told the master looter", ack and ack.args[3].response[2] == true)
local ap = nil
for _, m in ipairs(out) do if m.command == "response" and m.args[2].response == "AUTOPASS" then ap = m end end
check("autopass: answered Autopass", ap and ap.args[1] == 2)
check("autopass: shows for us", RC.session.candidates[2]["Me-Nightslayer"].response == "AUTOPASS")
LC:RefreshResponse()
local shownItems = 0
for _, row in ipairs(env.WM_LootResponseFrame.rows or {}) do if row:IsShown() and row.item then shownItems = shownItems + 1 end end
check("autopass: not in the response frame", shownItems == 1)
check("offline timer scheduled", #afters >= 1)

-- Answers from an RCLootCouncil raider and votes
From("Taslan", "response", { 1, { response = 1, note = "bis" } })
From("Pug", "response", { 1, { response = 2 } })
From("Venhana", "vote", { 1, "Taslan-Nightslayer", 1 })
check("answers and votes in", RC.session.candidates[1]["Taslan-Nightslayer"].response == 1
    and RC.session.candidates[1]["Taslan-Nightslayer"].votes == 1)

-- Award from the loot window
LC.voteSession, LC.voteSelected = 1, "Taslan-Nightslayer"
LC:ShowVoting()
check("award buttons for the master looter", env.WM_LootVotingFrame.awardBtn:IsShown())
check("awarded", ML:Award(1, "Taslan-Nightslayer") == true)
check("given from the loot window", #given == 1 and given[1][1] == 1 and given[1][2] == "Taslan")
out = Deliver()
check("awarded sent", Find(out, "awarded") and Find(out, "awarded").args[2] == "Taslan-Nightslayer")
local h = Find(out, "history")
check("history sent in RCLootCouncil's format", h and h.args[1] == "Taslan-Nightslayer" and h.args[2].response == "Mainspec/Need"
    and h.args[2].boss == "Lady Vashj" and h.args[2].votes == 1 and h.args[2].note == "bis" and h.args[2].instance:find("Serpentshrine", 1, true))
check("announced to the raid", chat[#chat][1]:find("was awarded to Taslan for Mainspec/Need!", 1, true) and chat[#chat][2] == "RAID")
local last = LC.LastLoot("Taslan")
check("logged once in our history", last and last.itemID == 30242 and last.how == "Mainspec/Need" and #LC.ForPlayer("Taslan") == 1)
check("the session shows it awarded", RC.session.items[1].awarded == "Taslan-Nightslayer")
-- Re-award: the old history entry is deleted
ML:Award(1, "Pug-Nightslayer")
out = Deliver()
check("re-award deletes the earlier history", Find(out, "delete_history") and #LC.ForPlayer("Taslan") == 0
    and LC.LastLoot("Pug").itemID == 30242)
check("re-award: the earlier winner gets their answer back", RC.session.candidates[1]["Taslan-Nightslayer"].response == 1
    and RC.session.candidates[1]["Pug-Nightslayer"].response == "AWARDED")

-- Award by trade (the loot window has closed)
loot = {}
check("awarded with no loot window", ML:Award(2, "Venhana-Nightslayer", "Disenchant") == true)
-- (the re-award to Pug was queued too: the helm had already left the loot window)
check("queued to trade, trade opened", #ML.toTrade == 2 and ML.toTrade[2].winner == "Venhana-Nightslayer" and traded[#traded] == "raid2")
out = Deliver()
check("an award reason is logged as one", Find(out, "history").args[2].isAwardReason == true
    and Find(out, "history").args[2].response == "Disenchant")
check("the panel lists it to trade", (function()
    for _, l in ipairs(LC:MLLines()) do if l.button == "Trade" then return true end end end)())
items[30247][1] = "Leggings"
env.C_Container.GetContainerItemID = function(bag, slot) if bag == 0 and slot == 3 then return 30247 end end
env._tradePartner = "Venhana"
check("trade opened: the item goes in", ML:OnTradeShow() == 1 and used[1] == "0:3")
ML:OnTradeDone()
check("trade done: no longer waiting", #ML:WaitingFor("Venhana-Nightslayer") == 0)
RunAfters()
Deliver()
check("everything awarded: the session ends", RC.session == nil)

-- In combat or out of range: no trade opened (the award still waits)
inCombat = true
check("no trade in combat", ML:TryTrade("Venhana-Nightslayer") == false)
inCombat = false
inRange = false
check("no trade out of range", ML:TryTrade("Venhana-Nightslayer") == false)
inRange = true

-- ============ Test loot sent to the group ============
chat = {}
local nHist = #LC.All()
LC:Command("sendtest 2")
out = Deliver()
check("test loot sent to the raid", Find(out, "lootTable") and #Find(out, "lootTable").args[1] == 2 and ML.test)
check("announced as a test", chat[1] and chat[1][1]:find("(Test)", 1, true))
given = {}
traded = {}
ML:Award(1, "Taslan-Nightslayer")
out = Deliver()
check("test award: announced, not given, traded or logged", chat[#chat][1]:find("(Test)", 1, true) and #given == 0 and #traded == 0
    and Find(out, "history") == nil and #LC.All() == nHist)
ML:End()
Deliver()
check("ended", RC.session == nil and not ML.test)

-- ============ Not the master looter ============
env.GetLootMethod = function() return "master", nil, 2 end
check("someone else is master looter", not ML:IsML())
ML:Add("|cffa335ee|Hitem:30100|h[Soul-Strider Boots]|h|r")
check("can't send for votes", ML:Start(false) == false)
ML:Clear()
loaded["RCLootCouncil_Classic"] = true
env.GetLootMethod = function() return "master", nil, 1 end
check("RCLootCouncil here: it runs the session, not us", not ML:IsML())
loaded["RCLootCouncil_Classic"] = nil

-- ============ Off ============
WM:SetModuleOn("LootCouncil", false)
check("off: panel hidden, nothing waiting", not env.WM_LootMLFrame:IsShown() and #ML.pending == 0)
loot = { "|cffa335ee|Hitem:30242|h[x]|h|r" }
check("off: loot window ignored", ML:ScanLoot() == 0)
WM:SetModuleOn("LootCouncil", true)

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
