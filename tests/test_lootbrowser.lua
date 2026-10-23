-- Loot Browser: the data files, expansion gating, pages (normal / heroic,
-- faction items, set pages by class), item sources, the window.
-- Usage: lua5.1 test_lootbrowser.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local faction, class = "Horde", "MAGE"
env.UnitFactionGroup = function() return faction end
env.UnitClass = function() return "Mage", class end
env.LE_EXPANSION_LEVEL_CURRENT = 1
local names = { [28477] = { "Harbinger Bands", 4 }, [24024] = { "Pauldrons of Arcane Rage", 3 } }
local asked = {}
env.C_Item = {
    GetItemInfo = function(id)
        asked[id] = true
        local n = names[id]
        if n then return n[1], "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. n[1] .. "]|h|r", n[2] end
    end,
    GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "INVTYPE_WRIST", "Interface\\Icons\\INV_Bracer_07" end,
    GetItemSetInfo = function(id) return "Set" .. id end,
}
env.INVTYPE_WRIST = "Wrist"
env.C_Map = { GetAreaInfo = function(id) if id == 3457 then return "Karazhan" end end }
local inInstance, instanceID = false, 0
env.IsInInstance = function() return inInstance end
env.GetInstanceInfo = function() return "x", "raid", 0, "", 10, 0, false, instanceID end

for _, f in ipairs({ "Core.lua", "UI.lua", "Data/LootClassic.lua", "Data/LootTBC.lua", "Data/LootWrath.lua",
    "Data/LootSets.lua", "Modules/LootBrowser.lua" }) do W.load(f) end
local WM = W.WM
local LB = WM.modules.LootBrowser
env.WatchingMachineDB = { theme = "Default" }
LB:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- The data ----
local good, why = true, ""
local ids, items = {}, 0
for _, tag in ipairs({ "classic", "tbc" }) do
    for _, inst in ipairs(WM.LootData[tag].build()) do
        if ids[inst.id] then good, why = false, "duplicate " .. inst.id end
        ids[inst.id] = true
        if type(inst.name) ~= "string" or not inst.bosses or #inst.bosses == 0 then good, why = false, "empty " .. inst.id end
        for _, b in ipairs(inst.bosses) do
            if type(b[1]) ~= "string" then good, why = false, "boss name in " .. inst.id end
            for _, k in ipairs({ "n", "h", "horde", "alliance", "sets", "sets_h" }) do
                for _, e in ipairs(b[k] or {}) do
                    for _, id in ipairs(type(e) == "table" and e or { e }) do
                        items = items + 1
                        if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then good, why = false, "bad id in " .. inst.id end
                        if k:find("^sets") and not WM.LootData.sets()[id] then good, why = false, "missing set " .. id end
                    end
                end
            end
        end
    end
end
check("data: well formed (" .. why .. ")", good)
check("data: thousands of drops", items > 5000)
check("data: no custom-server content", not ids.TheHallOfThanes and not ids.OnyxiasLairNew)

-- ---- Expansions ----
local ex = LB:Expansions()
check("TBC client: Classic and TBC", #ex == 2 and ex[1].tag == "classic" and ex[2].tag == "tbc")
check("Wrath is left out while it has no tables", (function()
    env.LE_EXPANSION_LEVEL_CURRENT = 2
    local n = #LB:Expansions()
    env.LE_EXPANSION_LEVEL_CURRENT = 1
    return n == 2
end)())
env.LE_EXPANSION_LEVEL_CURRENT = 0
check("Classic client: Classic only", #LB:Expansions() == 1)
env.LE_EXPANSION_LEVEL_CURRENT = nil
env.GetExpansionLevel = function() return 1 end
check("expansion from GetExpansionLevel", WM.Expansion() == 1)
env.LE_EXPANSION_LEVEL_CURRENT = 1

local tbc = LB:Instances("tbc")
check("TBC: every dungeon and raid", #tbc == 27)
check("dungeons first, then raids, then extras", tbc[1].kind == "dungeon" and tbc[#tbc].kind == "extra"
    and tbc[#tbc - 1].kind == "raid")
check("Classic instances", #LB:Instances("classic") >= 34)

-- ---- Pages ----
local ramps = LB:Instance("tbc", "HellfireRamparts")
local garg = LB:Bosses(ramps)[1]
check("boss list", garg[1] == "Watchkeeper Gargolmar")
local d = LB:Diffs(garg)
check("normal and heroic", #d == 2 and d[1] == "n" and d[2] == "h")
local n = LB:Entries(garg, "n")
local h = LB:Entries(garg, "h")
check("normal loot", n[1].item == 24024 and #n == 6)
check("heroic loot", h[1].item == 29434 and #h == 10)
check("no heroic: falls back to normal", #LB:Entries(LB:Bosses(LB:Instance("tbc", "Karazhan"))[1], "h") > 0)

local ony = LB:Bosses(LB:Instance("classic", "Onyxia"))[1]
local function HasItem(list, id) for _, e in ipairs(list) do if e.item == id then return true end end end
check("Horde gets the Horde head", HasItem(LB:Entries(ony, "n"), 18422) and not HasItem(LB:Entries(ony, "n"), 18423))
faction = "Alliance"
check("Alliance gets theirs", HasItem(LB:Entries(ony, "n"), 18423))
faction = "Horde"

-- Holiday bosses are Wrath-only
local pens = LB:Instance("tbc", "TheSlavePens")
local function HasBoss(inst, name) for _, b in ipairs(LB:Bosses(inst)) do if b[1]:find(name, 1, true) then return true end end end
check("Ahune: not on TBC", not HasBoss(pens, "Ahune"))
env.LE_EXPANSION_LEVEL_CURRENT = 2
check("Ahune: on Wrath", HasBoss(pens, "Ahune"))
env.LE_EXPANSION_LEVEL_CURRENT = 1

-- Set pages
local shared = LB:Instance("tbc", "tbcShared")
local t4
for _, b in ipairs(LB:Bosses(shared)) do if b[1] == "Tier 4 Sets" then t4 = b end end
local mine = LB:Entries(t4, "n", true)
local all = LB:Entries(t4, "n", false)
check("tier sets: your class only", mine[1] and mine[1].header == "Set648" and #mine == 6)
check("tier sets: every class", #all > 60)
class = "WARRIOR"
local war = LB:Entries(t4, "n", true)
check("tier sets: warrior's two", war[1].header == "Set654" and war[7].header == "Set655")
class = "MAGE"

-- Lookups
local tag, id = LB:FindByInstanceID(532)
check("instance ID lookup", tag == "tbc" and id == "Karazhan")
local src = LB:Sources(28477)
check("where an item drops", #src == 1 and src[1].instance.id == "Karazhan" and src[1].boss[1] == "Attumen the Huntsman")
local badge = LB:Sources(29434)
check("an item from many bosses", #badge > 20 and badge[1].diff == "h")
check("instance names from the client", LB:InstanceName(LB:Instance("tbc", "Karazhan")) == "Karazhan"
    and LB:InstanceName(ramps) == "Hellfire Ramparts")
check("item text", LB.ItemText(24024) == "|cFF0070DDPauldrons of Arcane Rage|r" and LB.ItemText(1):find("Item 1", 1, true))
check("item kind", LB.ItemKind(24024) == "Wrist, Cloth")

-- ---- Window ----
inInstance, instanceID = true, 543
LB:Toggle()
local p = env.WM_LootBrowserFrame
check("opens", p:IsShown())
check("opens on the instance you're in", p.status:GetText():find("Hellfire Ramparts", 1, true)
    and p.status:GetText():find("Watchkeeper Gargolmar", 1, true))
check("instance list", p.instList.rows[1]:IsShown() and p.instList.rows[1].text:GetText():find("Hellfire Ramparts", 1, true))
check("first instance selected", p.instList.rows[1].hl:IsShown() and not p.instList.rows[2].hl:IsShown())
check("boss list", p.bossList.rows[3]:IsShown() and p.bossList.rows[3].text:GetText() == "Nazan & Vazruden")
local shown = 0
for _, b in ipairs(p.itemButtons) do if b:IsShown() then shown = shown + 1 end end
check("item buttons", shown == 6 and p.itemButtons[1].itemID == 24024)
check("unknown item names: waits for them", p.waitingForItems == true)
check("heroic switch shown", p.diffBox:IsShown())
p.bossList.rows[2]:_fire("OnClick")
check("pick a boss", p.status:GetText():find("Omor", 1, true) ~= nil)
LootBrowserDB = env.LootBrowserDB
env.LootBrowserDB.diff = "h"
LB:RefreshList()
check("heroic page", p.status:GetText():find("Heroic", 1, true) and p.itemButtons[1].itemID == 29434)
-- Karazhan has no heroic
local karaRow
for i, r in ipairs(p.instList.rows) do if r.value == "Karazhan" then karaRow = r end end
karaRow:_fire("OnClick")
check("pick an instance", p.status:GetText():find("Karazhan", 1, true) and p.status:GetText():find("Attumen", 1, true))
check("no heroic: switch hidden", not p.diffBox:IsShown())
check("remembered per expansion", env.LootBrowserDB.instance.tbc == "Karazhan")
-- Item info arriving refreshes, once
names[28507] = { "Handwraps of Flowing Thought", 4 }
W.timers = {}
LB:OnItemInfo(); LB:OnItemInfo()
check("item info: one refresh queued", #W.timers == 1)
W.runTimers()
local found
for _, b in ipairs(p.itemButtons) do if b.itemID == 28507 and b.name:GetText():find("Handwraps", 1, true) then found = true end end
check("item info: names filled in", found)
-- Tooltip and links
local tipItem
env.GameTooltip.SetItemByID = function(_, id) tipItem = id end
p.itemButtons[1]._scripts.OnEnter(p.itemButtons[1])
check("tooltip", tipItem == 28477)
local linked
env.HandleModifiedItemClick = function(link) linked = link end
p.itemButtons[1]._scripts.OnClick(p.itemButtons[1])
check("shift-click / ctrl-click handled", linked and linked:find("Hitem:28477", 1, true))
-- Expansion switch
LB:Show("classic", "MoltenCore")
check("show an instance", p.status:GetText():find("Molten Core", 1, true) ~= nil)
check("toggle closes", (function() LB:Toggle(); return not p:IsShown() end)())
check("status", LB:GetQuickStatus():find("instances", 1, true) ~= nil)

-- ---- Item tooltips ----
local kara = LB:SourceLines(28477)
check("tooltip: header and the boss", kara[1]:find("Drops from:", 1, true)
    and kara[2]:find("Attumen the Huntsman", 1, true) and kara[2]:find("(Karazhan)", 1, true) and #kara == 2)
local heroicOnly = LB:SourceLines(27448)   -- Cloak of the Everliving, heroic Gargolmar
check("tooltip: heroic-only drops say so", heroicOnly[2]:find("Hellfire Ramparts, Heroic", 1, true))
local both = LB:SourceLines(23881)          -- Gargolmar's Hand, normal and heroic
check("tooltip: normal and heroic merged", #both == 2 and not both[2]:find("Heroic", 1, true))
local many = LB:SourceLines(29434)          -- Badge of Justice
check("tooltip: many bosses capped", #many == 5 and many[5]:find("^   |cFFAAAAAAand %d+ more"))
check("tooltip: nothing for other items", LB:SourceLines(6948) == nil)

-- A tooltip as the client fills it
local function Tip()
    local tip = W.NewFrame("Tip")
    tip.lines = {}
    tip.AddLine = function(self, l) self.lines[#self.lines + 1] = l end
    return tip
end
local tip = Tip()
check("added once", LB:AddTooltipSource(tip, 28477) and #tip.lines == 2)
check("not twice for the same showing", not LB:AddTooltipSource(tip, 28477) and #tip.lines == 2)
tip.wmLootSource = nil
env.LootBrowserDB.tooltips = false
check("switched off", not LB:AddTooltipSource(tip, 28477))
env.LootBrowserDB.tooltips = true

-- Hooks: OnTooltipSetItem on the game's tooltips, and TooltipDataProcessor
local gt = Tip()
local link = "|cffa335ee|Hitem:28477::::::::70:::::|h[Harbinger Bands]|h|r"
gt.GetItem = function() return "Harbinger Bands", link end
gt.HasScript = function(_, name) return name == "OnTooltipSetItem" end
env.GameTooltip, env.ItemRefTooltip = gt, Tip()
local post
env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 0 then post = fn end end }
env.Enum = { TooltipDataType = { Item = 0 } }
LB.tooltipsHooked = nil
LB:HookTooltips()
check("hooks the tooltips", gt._hooks.OnTooltipSetItem ~= nil and gt._hooks.OnTooltipCleared ~= nil and post ~= nil)
gt:_fire("OnTooltipCleared")
gt:_fire("OnTooltipSetItem")
check("item tooltip gets the lines", #gt.lines == 2 and gt.lines[2]:find("Attumen", 1, true))
post(gt, { id = 28477 })
check("both hooks: still once", #gt.lines == 2)
gt:_fire("OnTooltipCleared")
gt.lines = {}
post(gt, { id = 24024 })
check("data processor hook", #gt.lines == 2 and gt.lines[2]:find("Watchkeeper Gargolmar", 1, true))
check("hooked once", (function() LB.tooltipsHooked = nil; local n = 0
    env.TooltipDataProcessor.AddTooltipPostCall = function() n = n + 1 end
    LB:HookTooltips(); return n == 1 and #gt._hooks.OnTooltipSetItem == 1 end)())

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
