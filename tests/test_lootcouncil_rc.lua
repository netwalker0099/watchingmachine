-- Loot Council, part 2: an RCLootCouncil session as raider and council.
-- A master looter's real messages (packed as RCLootCouncil packs them) go in;
-- our acknowledgement, answers and votes come out the same way; the voting
-- frame shows everyone with their last loot; awards are recorded live.
-- Usage: lua5.1 test_lootcouncil_rc.lua <repo>
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
env.InCombatLockdown = function() return false end
env.GetNumGroupMembers = function() return 3 end
env.IsInRaid = function() return true end
env.IsInGroup = function() return true end
local raid = { { "Me", "PALADIN", "Player-4904-AAAA" }, { "Venhana", "PRIEST", "Player-4904-BBBB" }, { "Taslan", "ROGUE", "Player-4904-CCCC" } }
env.UnitExists = function(u) local i = tonumber(tostring(u):match("^raid(%d+)$")); return i and raid[i] ~= nil end
env.UnitName = function(u)
    if u == "player" then return "Me" end
    local i = tonumber(tostring(u):match("^raid(%d+)$")); return i and raid[i] and raid[i][1]
end
env.UnitClass = function(u)
    if u == "player" then return "Paladin", "PALADIN" end
    local i = tonumber(tostring(u):match("^raid(%d+)$")); return i and raid[i] and raid[i][2], i and raid[i] and raid[i][2]
end
env.UnitGUID = function(u)
    if u == "player" then return raid[1][3] end
    local i = tonumber(tostring(u):match("^raid(%d+)$")); return i and raid[i] and raid[i][3]
end
env.GetLootMethod = function() return "master", nil, 2 end      -- Venhana is the loot master
env.UnitIsGroupLeader = function(u) return u == "raid2" end
env.GetGuildInfo = function() return "Socks and Sandals", "Raider", 3 end
local items = {
    [30242] = { "Helm of the Vanquished Champion", 4, 120, "", "Interface\\Icons\\Helm" },
    [30100] = { "Soul-Strider Boots", 4, 128, "INVTYPE_FEET", "Interface\\Icons\\Boots" },
    [29000] = { "Old Boots", 4, 115, "INVTYPE_FEET", "Interface\\Icons\\OldBoots" },
}
local function Info(x)
    local id = tonumber(tostring(x):match("item:(%d+)") or x)
    local i = items[id]
    if not i then return nil end
    local s = tostring(x):match("item:([%-%d:]+)") or tostring(id)
    return i[1], "|cffa335ee|Hitem:" .. s .. "|h[" .. i[1] .. "]|h|r", i[2], i[3], 0, "", "", 1, i[4], i[5]
end
env.GetItemInfo = Info
env.C_Item = { GetItemInfo = Info }
env.GetInventoryItemLink = function(u, slot) if slot == 8 then return "|cffa335ee|Hitem:29000::::::::70|h[Old Boots]|h|r" end end
env.RAID_CLASS_COLORS = { PALADIN = { colorStr = "fff58cba" }, ROGUE = { colorStr = "fffff569" }, PRIEST = { colorStr = "ffffffff" } }
local timers = {}
env.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTimer = function(_, fn) return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end }
local sent = {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, body, channel, target) sent[#sent + 1] = { prefix, body, channel, target } end }

env.WatchingMachineDB = { theme = "Default" }
for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/ArmorySnap.lua", "Modules/ArmorySnapArmory.lua",
    "Modules/LootCouncil.lua", "Modules/LootCouncilCodec.lua", "Modules/LootCouncilRC.lua", "Modules/LootCouncilML.lua",
    "Modules/LootCouncilUI.lua", "Modules/LootCouncilFrames.lua" }) do
    W.load(f)
end
local WM = W.WM
local LC = WM.modules.LootCouncil
local RC, Codec = LC.RC, WM.LootCodec

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- Messages as an RCLootCouncil player sends them
local function From(sender, command, args, prefix, dist)
    for _, part in ipairs(Codec.Pack(command, args)) do
        RC:OnAddonMessage(prefix or "RCLC", part, dist or "RAID", sender)
    end
end
-- What we sent, unpacked
local function Out()
    WM:FlushAddonQueue()
    local un = Codec.NewUnframer()
    local out = {}
    for _, m in ipairs(sent) do
        local whole = un(m[1] .. m[3], m[2])
        if whole then
            local c, a = Codec.Unpack(whole)
            out[#out + 1] = { command = c, args = a, channel = m[3], prefix = m[1], target = m[4] }
        end
    end
    sent = {}
    return out
end
local function Find(list, cmd) for _, m in ipairs(list) do if m.command == cmd then return m end end end

LC:Initialize()
for _, fn in ipairs(timers) do fn() end
timers = {}
-- Some loot history: Taslan's last loot
LC.Add({ link = "|cffa335ee|Hitem:30242|h[Helm of the Vanquished Champion]|h|r", to = "Taslan", t = now - 5 * 86400,
    how = "Mainspec/Need", class = "ROGUE", src = { wm = 1 }, srcKind = "wm" })

check("master looter: the loot master", RC.MasterLooter() == "Venhana-Nightslayer")

-- ============ A session from an RCLootCouncil master looter ============
From("Venhana", "StartHandleLoot", {})
check("asks for the master looter's settings", Find(Out(), "MLdb_request") ~= nil)
From("Venhana", "mldb", { { ["|8"] = { ["|14"] = { ["|5"] = 2, [1] = { ["|15"] = "BiS" }, [2] = { ["|15"] = "Upgrade" } } },
    ["|12"] = 90, ["|2"] = true } })
check("settings read, short keys restored", RC.mldb and RC.mldb.timeout == 90 and RC.mldb.multiVote == true
    and RC:Buttons()[1].text == "BiS" and #RC:Buttons() == 2)
From("Venhana", "council", { { ["4904-AAAA"] = true, ["4904-BBBB"] = true } })
check("council by GUID", RC.council["Me-Nightslayer"] and RC.council["Venhana-Nightslayer"] and RC:IsCouncil())
From("Taslan", "lootTable", { { { string = "30242", session = 1 } } })
check("a loot table from someone else is ignored", RC.session == nil)
From("Venhana", "lootTable", { { { string = "30242", session = 1, boss = "Lady Vashj" }, { string = "30100", session = 2, boss = "Lady Vashj" } } })
check("session started", RC.session and RC.session.items[1].itemID == 30242 and RC.session.items[2].equipLoc == "INVTYPE_FEET")
check("items read from the item string", RC.session.items[2].link:find("Soul%-Strider Boots") and RC.session.items[2].ilvl == 128)
check("everyone in the raid a candidate", RC.session.candidates[1]["Taslan-Nightslayer"].response == "ANNOUNCED")
local out = Out()
local ack = Find(out, "lootAck")
check("acknowledged to the raid", ack and ack.channel == "RAID" and ack.prefix == "RCLC")
check("ack: the boots we'd replace and the difference", ack and ack.args[3].gear1[2] == "29000::::::::70" and ack.args[3].diff[2] == 13)
check("response frame shown", env.WM_LootResponseFrame:IsShown())
check("voting frame opened for the council", env.WM_LootVotingFrame and env.WM_LootVotingFrame:IsShown())

-- Answering
RC:Respond(2, 1, "bis")
local r = Find(Out(), "response")
check("answer sent", r and r.args[1] == 2 and r.args[2].response == 1 and r.args[2].note == "bis"
    and r.args[2].gear1 == "item:29000::::::::70")
check("answered item leaves the response frame", RC.session.items[2].answered == 1)
-- Our own message comes back from the raid
From("Me", "response", { 2, { response = 1, note = "bis" } })
check("our answer shows for us", RC.session.candidates[2]["Me-Nightslayer"].response == 1)
From("Taslan", "lootAck", { 0, 131.5, { gear1 = { [2] = "28000" }, diff = { [2] = 4 }, response = { [1] = true } } })
check("their ack: gear, diff, autopass", RC.session.candidates[2]["Taslan-Nightslayer"].gear1 == "item:28000"
    and RC.session.candidates[2]["Taslan-Nightslayer"].diff == 4 and RC.session.candidates[1]["Taslan-Nightslayer"].response == "AUTOPASS"
    and RC.session.candidates[2]["Taslan-Nightslayer"].response == "WAIT")
From("Taslan", "response", { 2, { response = 2, note = "offspec please" } })
check("their answer", RC.session.candidates[2]["Taslan-Nightslayer"].response == 2)

-- Votes
RC:Vote(2, "Taslan-Nightslayer", 1)
local v = Find(Out(), "vote")
check("vote sent", v and v.args[1] == 2 and v.args[2] == "Taslan-Nightslayer" and v.args[3] == 1)
From("Me", "vote", { 2, "Taslan-Nightslayer", 1 })
From("Venhana", "vote", { 2, "Taslan-Nightslayer", 1 })
From("Taslan", "vote", { 2, "Taslan-Nightslayer", 1 })
check("council votes counted, others ignored", RC.session.candidates[2]["Taslan-Nightslayer"].votes == 2)
check("can't vote twice", RC:Vote(2, "Taslan-Nightslayer", 1) == false)
RC:Vote(2, "Taslan-Nightslayer", -1)
check("unvote sent", Find(Out(), "vote").args[3] == -1)

-- The voting frame
LC.voteSession = 2
env.WM_LootVotingFrame.list:SetHeight(200)
LC:RefreshVoting()
local rows = LC:VoteRows(2)
check("rows sorted by answer", rows[1].name == "Me-Nightslayer" and rows[2].name == "Taslan-Nightslayer")
check("answer text from the master looter's responses", RC:Response("default", 2).text == "Offspec/Greed")
local shown
for _, row in ipairs(env.WM_LootVotingFrame.list.rows) do
    if row.cand and row.cand.name == "Taslan-Nightslayer" then shown = row.cells.last:GetText() end
end
check("last loot column", shown and shown:find("Helm of the Vanquished", 1, true) and shown:find("5 days ago", 1, true))
local lines = {}
local tt = { AddLine = function(_, t) lines[#lines + 1] = tostring(t) end,
    AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " | " .. tostring(b) end }
LC:AddLootTooltip(tt, "Taslan-Nightslayer", 30)
check("hover: their last 30 days", table.concat(lines, "\n"):find("Last 30 days: 1 item", 1, true))

-- Award and history, live
From("Venhana", "awarded", { 2, "Taslan-Nightslayer", nil })
check("awarded shown", RC.session.items[2].awarded == "Taslan-Nightslayer"
    and RC.session.candidates[2]["Taslan-Nightslayer"].response == "AWARDED")
From("Venhana", "history", { "Taslan-Nightslayer", { lootWon = "|cffa335ee|Hitem:30100|h[Soul-Strider Boots]|h|r",
    date = "2026/11/08", time = "21:00:00", response = "Offspec/Greed", responseID = 2, color = { 1, 0.5, 0, 1 },
    boss = "Lady Vashj", class = "ROGUE", id = "1793000000-1", owner = "Venhana-Nightslayer" } })
local last = LC.LastLoot("Taslan")
check("the award recorded in the loot history", last.itemID == 30100 and last.how == "Offspec/Greed" and last.boss == "Lady Vashj")
From("Taslan", "history", { "Taslan-Nightslayer", { lootWon = "|cffa335ee|Hitem:29000|h[x]|h|r", date = "2026/11/08",
    time = "21:01:00", response = "x", id = "fake" } })
check("history from someone else isn't recorded", LC.LastLoot("Taslan").itemID == 30100)
From("Venhana", "delete_history", { "1793000000-1" })
check("a deleted award is gone", LC.LastLoot("Taslan").itemID == 30242)
From("Venhana", "session_end", {})
check("session ended", RC.session == nil and not env.WM_LootResponseFrame:IsShown())

-- ============ Version checks ============
From("Venhana", "fr", {}, "RCLCv", "RAID")
local f = Find(Out(), "f")
check("version check answered as RCLootCouncil " .. RC.VERSION, f and f.prefix == "RCLCv" and f.args[3] == "1.5.1"
    and f.args[5][1]:find("Watching Machine", 1, true))

-- ============ RCLootCouncil on this character ============
loaded["RCLootCouncil_Classic"] = true
From("Venhana", "lootTable", { { { string = "30242", session = 1 } } })
check("RCLootCouncil here: no session of our own", RC.session == nil and #Out() == 0)
From("Venhana", "history", { "Taslan-Nightslayer", { lootWon = "|cffa335ee|Hitem:29000|h[x]|h|r", date = "2026/11/08",
    time = "21:05:00", response = "Mainspec/Need", id = "1793000300-2" } })
check("but its awards are still recorded", LC.LastLoot("Taslan").itemID == 29000)
loaded["RCLootCouncil_Classic"] = nil

-- ============ Local test session ============
LC:Command("test 2")
check("test session: two items, nothing sent", RC.session and RC.session.items[2] and #Out() == 0)
check("test: candidates answered", RC.session.candidates[1]["Venhana-Nightslayer"].response ~= "ANNOUNCED")
check("test: our ack loops back locally", RC.session.candidates[1]["Me-Nightslayer"].response == "WAIT")
RC:Respond(1, 2)
check("test: our answer shows", RC.session.candidates[1]["Me-Nightslayer"].response == 2 and #Out() == 0)
RC:Vote(1, "Venhana-Nightslayer", 1)
check("test: our vote counted", RC.session.candidates[1]["Venhana-Nightslayer"].votes == 1 and #Out() == 0)
LC:Command("endtest")
check("test ended", RC.session == nil and RC.local_ == nil)

-- ============ Off ============
LC:Command("test")
WM:SetModuleOn("LootCouncil", false)
check("off: session dropped, frames hidden", RC.session == nil and not env.WM_LootVotingFrame:IsShown()
    and not env.WM_LootResponseFrame:IsShown())
From("Venhana", "lootTable", { { { string = "30242", session = 1 } } })
check("off: nothing heard", RC.session == nil and #Out() == 0)
WM:SetModuleOn("LootCouncil", true)

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
