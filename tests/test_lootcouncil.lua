-- Loot Council, part 1: the loot history. Gargul's and RCLootCouncil's saved
-- awards imported once each (the same award from both merged), how each was
-- won, a player's loot and last loot, the history window, the loot pane
-- beside an armory, the roster's "Last loot" line, the setup page, and off.
-- Usage: lua5.1 test_lootcouncil.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1793000000
env.GetServerTime = function() return now end
env.C_DateAndTime = false        -- realm clock = this machine's clock in the test
env.GetRealmName = function() return "Nightslayer" end
env.IsAddOnLoaded = function() return false end
env.C_AddOns = { IsAddOnLoaded = function() return false end }
env.InCombatLockdown = function() return false end
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
env.GetItemInfo = function() return nil end
env.C_Item = { GetItemInfo = function() return nil end }
local afters = {}
env.C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end, NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end }
env.RAID_CLASS_COLORS = { PALADIN = { colorStr = "fff58cba" }, ROGUE = { colorStr = "fffff569" } }

local function T(y, m, d, H, M) return os.time({ year = y, month = m, day = d, hour = H, min = M, sec = 0 }) end
local HELM = "|cffa335ee|Hitem:30242::::::::70::::::::::|h[Helm of the Vanquished Champion]|h|r"
local BOOTS = "|cffa335ee|Hitem:30100::::::::70::::::::::|h[Soul-Strider Boots]|h|r"
local GLOVES = "|cffa335ee|Hitem:28506::::::::70::::::::::|h[Gloves of Dexterous Manipulation]|h|r"

-- RCLootCouncil: Taslan won the helm on Need, a disenchant award, an old date form
env.RCLootCouncilLootDB = { factionrealm = { ["Horde - Nightslayer"] = {
    ["Taslan-Nightslayer"] = {
        { lootWon = HELM, date = "2026/07/16", time = "20:58:00", response = "Mainspec/Need", responseID = 1,
          color = { 0, 1, 0, 1 }, boss = "Lady Vashj", instance = "Serpentshrine Cavern-25 Player", votes = 5,
          note = "bis phase 2", class = "ROGUE", owner = "Venhana-Nightslayer", id = "1784257127-2",
          itemReplaced1 = GLOVES, isAwardReason = false },
        { lootWon = BOOTS, date = "17/07/26", time = "21:00:00", response = "Disenchant", responseID = 1,
          isAwardReason = true, class = "ROGUE", id = "1784340000-1" },
    },
} } }
-- Gargul: the same helm (2 minutes off) with rolls, gloves won on OS, a disenchanted item
env.GargulDB = { AwardHistory = {
    ["aaaa"] = { checksum = "aaaa", itemLink = HELM, itemID = 30242, awardedTo = "Taslan-Nightslayer",
        awardedBy = "Venhana-Nightslayer", timestamp = T(2026, 7, 16, 21, 0), winnerClass = 4, OS = false, SR = false,
        Rolls = { { player = "Taslan", amount = 88, classification = "MS", max = 100 } } },
    ["bbbb"] = { checksum = "bbbb", itemLink = GLOVES, itemID = 28506, awardedTo = "Hydarnes-Nightslayer",
        awardedBy = "Stoutn-Nightslayer", timestamp = T(2026, 6, 15, 20, 40), winnerClass = 2, OS = true, SR = false },
    ["cccc"] = { checksum = "cccc", itemLink = BOOTS, itemID = 30100, awardedTo = "||de||",
        awardedBy = "Stoutn-Nightslayer", timestamp = T(2026, 6, 15, 21, 0), winnerClass = 5 },
    ["dddd"] = { checksum = "dddd", itemID = 30100, awardedTo = "Hydarnes-Nightslayer", awardedBy = "Stoutn-Nightslayer",
        timestamp = now - 2 * 86400, winnerClass = 2, SR = true },
} }
-- Gargul History's copy of the gloves award
env.GargulHistoryDB = { history = { { date = "2026-06-15 20:40:00", awardedTo = "Hydarnes",
    item = { name = "Gloves of Dexterous Manipulation", id = "28506" }, itemLink = GLOVES, timestamp = T(2026, 6, 15, 20, 40) } } }

env.WatchingMachineDB = { theme = "Default" }
for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/ArmorySnap.lua", "Modules/ArmorySnapArmory.lua",
    "Modules/LootCouncil.lua", "Modules/LootCouncilUI.lua",
    "Modules/GuildRoster.lua", "Modules/GuildRosterSync.lua", "Modules/GuildRosterUI.lua", "Modules/GuildRosterPurge.lua" }) do
    W.load(f)
end
local WM = W.WM
local LC = WM.modules.LootCouncil

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ============ Setup page before the module starts ============
local p = WM.UI:CreatePanel({ name = "WM_TestSetupLC", title = "t" })
local page = p:NewPage()
local ok, err = pcall(LC.SetupPage, LC, page.layout)
if not ok then io.write(tostring(err), "\n") end
check("setup page builds before the module starts", ok and pcall(page.layout.Reflow, page.layout))
check("setup page: defaults saved", env.WMLootDB and env.WMLootDB.autoImport == true and env.WMLootDB.recentDays == 30)
check("setup page: nothing imported by the page", next(env.WMLootDB.history) == nil)

-- ============ Importing ============
LC:Initialize()
check("import waits for login", next(env.WMLootDB.history) == nil and #afters >= 1)
for _, fn in ipairs(afters) do fn() end
afters = {}
local db = env.WMLootDB
local n = 0
for _ in pairs(db.history) do n = n + 1 end
check("RCLootCouncil and Gargul awards imported, the shared helm once", n == 5)
local taslan = LC.ForPlayer("Taslan")
check("a player's loot, newest first", #taslan == 2 and taslan[1].itemID == 30100 and taslan[2].itemID == 30242)
local helm = taslan[2]
check("RCLootCouncil says how it was won", helm.how == "Mainspec/Need" and helm.color[2] == 1)
check("merged: RCLootCouncil's details and Gargul's rolls", helm.boss == "Lady Vashj" and helm.votes == 5
    and helm.note == "bis phase 2" and helm.rolls and helm.rolls[1].roll == 88 and helm.src.rc and helm.src.gl)
check("old d/m/y dates read", taslan[1].t == T(2026, 7, 17, 21, 0))
check("an award reason doesn't count as last loot", LC.LastLoot("Taslan").itemID == 30242)
local hyd = LC.ForPlayer("Hydarnes-Nightslayer")
check("Gargul: off-spec and soft reserve", #hyd == 2 and hyd[1].how == "Soft reserve" and hyd[2].how == "Offspec")
check("Gargul History's copy merged into Gargul's", #hyd == 2 and hyd[2].src.gh ~= nil)
check("Gargul: class from its number", hyd[1].class == "PALADIN")
check("Gargul: a missing link falls back to the item id", hyd[1].link == nil and LC.ItemText(hyd[1]):find("Item 30100", 1, true))
local de = LC.All(function(e) return e.de end)
check("disenchanted items kept in all loot, under nobody", #de == 1 and de[1].to == nil and de[1].how == "Disenchant")
check("importing again adds nothing", LC:ImportRCLC() + LC:ImportGargul() == 0)
check("recent loot: the last 30 days", #LC.Recent("Hydarnes", 30) == 1 and #LC.Recent("Taslan", 30) == 0)
check("time since", LC.Ago(now - 3 * 86400) == "3 days ago" and LC.Ago(now - 7200) == "2 h ago")
check("kinds of win", LC.Kind("Mainspec/Need") == "need" and LC.Kind("Offspec/Greed") == "greed"
    and LC.Kind("Minor Upgrade") == "minor" and LC.Kind("Disenchant") == "de" and LC.Kind("Banking") == "other")
check("names in any case", #LC.ForPlayer("taslan-nightslayer") == 2 and LC.Resolve("taslan") == "Taslan-Nightslayer")
local players = LC.Players()
check("players: most recent loot first", players[1].key == "Hydarnes-Nightslayer" and players[1].count == 2)

-- ============ The window ============
LC:Command("history")
local f = env.WM_LootCouncilFrame
check("window opens on all loot", f and f:IsShown() and LC.tab == "all")
local rows = LC:Rows()
check("all loot: every award", #rows == 5 and rows[1].entry.itemID == 30100)
LC.search = "helm"
check("search by item", #LC:Rows() == 1)
LC.search = "hydarnes"
check("search by player", #LC:Rows() == 2)
LC.search = ""
LC:ShowPlayer("taslan")
check("one player's loot", #LC:Rows() == 2 and LC.headingText:find("Taslan's loot", 1, true))
LC.tab = "players"
check("players tab", #LC:Rows() == 2)
LC:Command("Taslan")
check("command with a name opens their loot", LC.player == "Taslan-Nightslayer")

-- Tooltip
local lines = {}
local tt = { AddLine = function(_, t) lines[#lines + 1] = tostring(t) end,
    AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " | " .. tostring(b) end }
LC:AddLootTooltip(tt, "Hydarnes", 30)
local text = table.concat(lines, "\n")
check("tooltip: last loot and the last 30 days", text:find("Last loot | 2 days ago", 1, true) and text:find("Last 30 days: 1 item", 1, true))

-- ============ Export ============
local csv, count = LC.ExportCSV()
local lines = {}
for l in csv:gmatch("[^\n]+") do lines[#lines + 1] = l end
check("export: header and one line per award", lines[1]:find("^Date,Time,Player,Class,Item,ItemID,How") and #lines == count + 1 and count == 5)
check("export: a note with a comma is quoted", csv:find('"bis phase 2"', 1, true) == nil and csv:find("bis phase 2", 1, true) ~= nil)
check("export: item names without link codes", csv:find("Helm of the Vanquished Champion", 1, true) and not csv:find("|H", 1, true))
LC.Add({ link = HELM, to = "Comma", t = now, how = "Need", note = 'one, "two"', src = { wm = "x" }, srcKind = "wm" })
csv = LC.ExportCSV()
check("export: commas and quotes escaped", csv:find('"one, ""two"""', 1, true) ~= nil)
LC:ShowPlayer("Taslan")
LC:Command("export")
check("export: the window shows what's listed", env.WM_CopyTextFrame and env.WM_CopyTextFrame:IsShown()
    and env.WM_CopyTextBox:GetText():find("Taslan", 1, true) and not env.WM_CopyTextBox:GetText():find("Hydarnes", 1, true))
LC.DeleteEntry(LC.LastLoot("Comma"))

-- ============ The loot pane beside an armory ============
local AS = WM.modules.ArmorySnap
local frame = env.CreateFrame("Frame")
for _, fn in ipairs(AS.memberListeners) do fn("Taslan-Nightslayer", frame) end
local pane = env.WM_LootCouncilPane
check("pane shows beside the armory", pane and pane:IsShown() and pane.key == "Taslan-Nightslayer")
check("pane: count and last loot", pane.title:GetText():find(": 2", 1, true) and pane.last:GetText():find("Last loot", 1, true))
for _, fn in ipairs(AS.memberListeners) do fn(nil, frame) end
check("no player: pane hidden", not pane:IsShown())
env.WMLootDB.showInArmory = false
for _, fn in ipairs(AS.memberListeners) do fn("Taslan-Nightslayer", frame) end
check("option off: no pane", not pane:IsShown())
env.WMLootDB.showInArmory = true

-- ============ Roster Manager ============
local GR = WM.modules.GuildRoster
local rec = { name = "Taslan-Nightslayer", class = "ROGUE", level = 70, join = { date = "" }, promo = { date = "" },
    bday = {}, custom = { text = "" }, ban = {} }
local found
for _, l in ipairs(GR:DetailLines(rec)) do if l[1] == "Last loot" then found = l[2] end end
check("roster details: last loot", found and found:find("Helm of the Vanquished", 1, true))

-- ============ Off ============
LC:Command("history")
WM:SetModuleOn("LootCouncil", false)
check("off: window hidden", not f:IsShown())
for _, fn in ipairs(AS.memberListeners) do fn("Taslan-Nightslayer", frame) end
check("off: no pane", not pane:IsShown())
check("off: no import", LC:ImportAll() == 0)
found = nil
for _, l in ipairs(GR:DetailLines(rec)) do if l[1] == "Last loot" then found = true end end
check("off: no roster line", not found)
WM:SetModuleOn("LootCouncil", true)

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
