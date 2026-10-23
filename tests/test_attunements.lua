-- Attunements: the data, reading progress (quests, items, level,
-- reputation, other attunements), patch variants, saving per character,
-- the guild survey and the window.
-- Usage: lua5.1 test_attunements.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
local completed, onQuest, items, reps = {}, {}, {}, {}
local level, side, build = 70, "Horde", 20506
env.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return completed[id] == true end,
    IsOnQuest = function(id) return onQuest[id] == true end,
    GetQuestInfo = function(id) if id == 9838 then return "The Master's Touch" end end,
}
env.C_Item = {
    GetItemCount = function(id) return items[id] or 0 end,
    GetItemInfo = function(id) if id == 24490 then return "The Master's Key" end end,
}
env.UnitLevel = function() return level end
env.UnitFactionGroup = function() return side end
env.UnitName = function() return "Tanky" end
env.GetRealmName = function() return "Spineshatter" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.GetFactionInfoByID = function(id) return "Faction" .. id, "", 4, 0, 0, reps[id] end
env.GetBuildInfo = function() return "2.5.6", "1", "Oct 1 2026", build end
env.IsInGuild = function() return true end
local sentMsgs = {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(p, m, c) sentMsgs[#sentMsgs + 1] = { p, m, c } end }
env.Ambiguate = function(n) return (n:gsub("%-Spineshatter$", "")) end
env.math.random = function() return 0.5 end

for _, f in ipairs({ "Core.lua", "UI.lua", "Data/Attunements.lua", "Modules/Attunements.lua" }) do W.load(f) end
local WM = W.WM
local AT = WM.modules.Attunements
env.WatchingMachineDB = { theme = "Default" }
AT:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- The data ----
local D = WM.AttuneData
local good, why = true, ""
local kinds = { quest = true, pickup = true, turnin = true, item = true, kill = true, talk = true, use = true,
    level = true, rep = true, attune = true }
for _, a in ipairs(D.attunements) do
    local ids = {}
    for _, s in ipairs(a.steps) do ids[s.id] = true end
    if #a.steps == 0 or not a.finish or #a.finish == 0 then good, why = false, "empty " .. a.name end
    for _, f in ipairs(a.finish or {}) do if not ids[f] then good, why = false, "finish " .. a.name end end
    for _, s in ipairs(a.steps) do
        if not kinds[s.t] then good, why = false, "kind " .. tostring(s.t) end
        for _, p in ipairs(s.after or {}) do if not ids[p] then good, why = false, a.name .. " after " .. p end end
        if (s.t == "quest" or s.t == "pickup" or s.t == "turnin") and not D.quests[s.ref] then good, why = false, "quest " .. s.ref end
        if (s.t == "kill" or s.t == "talk") and not D.npcs[s.ref] then good, why = false, "npc " .. s.ref end
        if s.t == "attune" and not AT:Get(s.attune) then good, why = false, "attune " .. s.attune end
    end
end
check("data: well formed (" .. why .. ")", good)
check("data: every TBC raid", (function()
    local n = {}
    for _, a in ipairs(D.attunements) do if a.expansion == 1 and a.group == "raid" then n[a.name] = true end end
    return n.Karazhan and n["Serpentshrine Cavern"] and n["The Eye"] and n["Mount Hyjal"] and n["Black Temple"] and n.Nightbane
end)())

-- ---- The list ----
local list = AT:List()
local function Has(l, name, sd)
    for _, a in ipairs(l) do if a.name == name and (not sd or a.side == sd) then return a end end
end
check("list: TBC, your side", Has(list, "Karazhan") and Has(list, "Thrallmar Heroics") and not Has(list, "Honor Hold Heroics")
    and not Has(list, "Molten Core"))
check("list: raids first", list[1].group == "raid" and list[#list].group == "misc")
check("list: Classic when asked", Has(AT:List(true), "Molten Core") ~= nil)
check("one id, your side's version", AT:Get(190).side == "Horde" and AT:Get(140).side == "Horde")
side = "Alliance"
check("Alliance side", AT:Get(160) and Has(AT:List(), "Honor Hold Heroics") and not Has(AT:List(), "Thrallmar Heroics"))
side = "Horde"

-- ---- Progress ----
local kara = AT:Get(115)
local r = AT:Evaluate(kara)
check("start: level done, talk next", r.done[10] and not r.done[20] and r.next[1].id == 20 and not r.complete)
completed[9824] = true
r = AT:Evaluate(kara)
check("a quest done marks what came before", r.done[30] and r.done[20] and not r.done[40])
check("next: the other branch", (function() for _, s in ipairs(r.next) do if s.id == 40 then return true end end end)())
completed[9825] = true
r = AT:Evaluate(kara)
check("both branches: the next quest opens", (function() for _, s in ipairs(r.next) do if s.id == 50 then return true end end end)())
check("progress counted", r.count >= 4 and r.total > 20 and r.pct > 0 and r.pct < 100)
onQuest[9831] = true
check("pick-up: on the quest", AT:Evaluate(kara).done[70])
items[24490] = 1
r = AT:Evaluate(kara)
check("an item in your bags", r.done[180] and r.done[170])
completed[9838] = true
r = AT:Evaluate(kara)
check("finished: attuned", r.complete and r.pct == 100 and r.count == r.total and #r.next == 0)
-- Another attunement as a step
local slab = AT:Get(30)
check("key: not yet", not AT:Evaluate(slab).complete)
items[27991] = 1
check("key: held", AT:Evaluate(slab).complete)
check("attunement as a step", AT:StepCheck({ t = "attune", attune = 30 }))
-- Reputation and patch variants
local hk = AT:Get(104)
reps[947] = 15000
r = AT:Evaluate(hk)
check("heroic key: revered needed on 2.5.6", not r.done[10] and r.total == 3)
reps[947] = 21000
check("heroic key: revered", AT:Evaluate(hk).done[10])
items[30637] = 1
check("heroic key: the key", AT:Evaluate(hk).complete)
build = 20507
items[30637] = nil
reps[947] = 12000
r = AT:Evaluate(hk)
check("from 2.5.7: honored, the new key", r.done[10] and not r.complete and r.total == 2)
items[185686] = 1
check("from 2.5.7: done", AT:Evaluate(hk).complete)
build = 20506
-- "any one of" doesn't vouch for both
local any
for _, a in ipairs(D.attunements) do
    for _, s in ipairs(a.steps) do if s.any and not any then any = { a = a, s = s } end end
end
completed[any.s.ref] = true
r = AT:Evaluate(any.a)
check("any-of: the step is done, its options aren't assumed", r.done[any.s.id] and not (r.done[any.s.after[1]] and r.done[any.s.after[2]]))
completed[any.s.ref] = nil

-- ---- Text ----
check("text: quest from the client", AT:StepText({ t = "quest", ref = 9838 }) == "Quest: The Master's Touch")
check("text: quest from the data", AT:StepText({ t = "turnin", ref = 9837 }) == "Turn in: Return to Khadgar")
check("text: item", AT:StepText({ t = "item", ref = 24490 }) == "Get The Master's Key"
    and AT:StepText({ t = "item", ref = 1, count = 20 }) == "Get Item 1 x20")
check("text: kill and talk", AT:StepText({ t = "kill", ref = 18708 }):find("^Kill ") and AT:StepText({ t = "talk", ref = 15608 }) == "Talk to Medivh")
check("text: level, rep, attune", AT:StepText({ t = "level", value = 68 }) == "Reach level 68"
    and AT:StepText({ t = "rep", faction = 947, value = 21000 }) == "Revered with Faction947"
    and AT:StepText({ t = "attune", attune = 30 }) == "Attuned: Shadow Labyrinth")
check("standings", AT.Standing(42000) == "Exalted" and AT.Standing(12000) == "Honored" and AT.Standing(-1) == "Unfriendly")
local sum = AT:Summary(kara)
check("summary from the steps", sum:find("^Raids, 10 players") and sum:find("Deadwind Pass", 1, true) and sum:find("The Master's Touch", 1, true))

-- ---- Saved per character ----
completed[9838] = nil
local c = AT:Update()
check("saved", c.att[115].pct < 100 and c.level == 70 and env.AttunementsDB.chars["Tanky-Spineshatter"] ~= nil)
W.printed = {}
completed[9838] = true
AT:Update()
check("newly attuned: said in chat", (W.printed[#W.printed] or ""):find("Attuned:", 1, true) and W.printed[#W.printed]:find("Karazhan", 1, true))
W.printed = {}
AT:Update()
check("only once", #W.printed == 0)
check("attuned names", table.concat(AT:AttunedNames(nil, true), ","):find("Karazhan", 1, true) ~= nil)
local tl = AT:TooltipLines("Tanky-Spineshatter")
check("Your Characters tooltip lines", tl and tl[1]:find("Attuned:", 1, true) and tl[1]:find("Karazhan", 1, true))
check("nothing for an unknown character", AT:TooltipLines("Nobody-Nowhere") == nil)
check("status", AT:GetQuickStatus():find("raids", 1, true) ~= nil)

-- ---- Guild ----
local enc = AT:Encode()
local dec = AT.Decode(enc)
check("encode / decode", enc:find("^A 70 ") and dec.level == 70 and dec.att[115] == 100)
check("decode: junk", AT.Decode("hello") == nil)
check("survey asks the guild", AT:Survey() and sentMsgs[#sentMsgs][2] == "Q" and sentMsgs[#sentMsgs][3] == "GUILD")
W.timers = {}
AT:OnAddonMessage("WMAtt", "Q", "GUILD", "Healz-Spineshatter")
W.runTimers()
check("answers a survey", sentMsgs[#sentMsgs][2]:find("^A 70") ~= nil)
local before = #sentMsgs
AT:OnAddonMessage("WMAtt", "Q", "GUILD", "Other-Spineshatter")
W.runTimers()
check("not more than every 30 seconds", #sentMsgs == before)
AT:OnAddonMessage("WMAtt", "A 69 115:45,120:100", "GUILD", "Healz-Spineshatter")
check("stores answers", env.AttunementsDB.guild.Healz.att[115] == 45 and env.AttunementsDB.guild.Healz.level == 69)
AT:OnAddonMessage("WMAtt", "A 70 115:100", "GUILD", "Tanky-Spineshatter")
check("ignores yourself", env.AttunementsDB.guild.Tanky == nil)
AT:OnAddonMessage("Other", "A 70 115:100", "GUILD", "Bob-Spineshatter")
check("ignores other prefixes", env.AttunementsDB.guild.Bob == nil)

-- ---- Window ----
AT:Toggle()
local p = env.WM_AttunementsFrame
check("opens", p:IsShown())
local left = p.left.rows
check("groups and attunements", left[1].text:GetText():find("Raids", 1, true) and left[2].att == 115
    and left[2].right:GetText():find("100%", 1, true))
check("first one selected", p.title:GetText():find("Karazhan", 1, true) and p.title:GetText():find("100%", 1, true))
local steps = p.right.rows
check("steps listed", steps[1]:IsShown() and steps[1].step ~= nil and steps[1].right:GetText():find("done", 1, true))
check("steps show their zone", (function()
    for _, row in ipairs(steps) do if row:IsShown() and row.text:GetText():find("Deadwind Pass", 1, true) then return true end end
end)())
-- Pick another: what's next is marked
local sscRow
for _, row in ipairs(left) do if row.att == 120 then sscRow = row end end
sscRow:_fire("OnClick")
check("select another", p.title:GetText():find("Serpentshrine", 1, true) ~= nil)
check("next step marked", (function()
    for _, row in ipairs(steps) do if row:IsShown() and row.right:GetText():find("next", 1, true) then return true end end
end)())
local tipLines = {}
env.GameTooltip.SetText = function(_, t) tipLines[#tipLines + 1] = t end
env.GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
steps[2]._scripts.OnEnter(steps[2])
check("step tooltip", #tipLines >= 1)
-- Alts and guild views
env.AttunementsDB.chars["Alty-Spineshatter"] = { name = "Alty", class = "MAGE", level = 68, side = "Horde", att = { [120] = { pct = 30 } } }
p.viewBox.buttons[2]:_fire("OnClick")
check("my characters", steps[1].text:GetText():find("Alty", 1, true) or steps[2].text:GetText():find("Alty", 1, true))
p.viewBox.buttons[3]:_fire("OnClick")
check("guild", steps[1].text:GetText():find("Healz", 1, true) and steps[1].right:GetText():find("attuned", 1, true))
env.AttunementsDB.guild = {}
AT:RefreshList()
check("guild: empty hint", steps[1].text:GetText():find("Survey guild", 1, true) ~= nil)
AT:Toggle()
check("closes", not p:IsShown())

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
