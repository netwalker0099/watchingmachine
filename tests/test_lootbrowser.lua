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
    "Data/LootCrafting.lua", "Data/LootFactions.lua", "Data/LootPvP.lua", "Data/LootSets.lua", "Data/LootCrafts.lua",
    "Modules/LootBrowser.lua" }) do W.load(f) end
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
local ids, items, perCat = {}, 0, {}
local setsT, craftsT = WM.LootData.sets(), WM.LootData.crafts()
local function HasSet(id) return setsT.base[id] or setsT.wrath[id] end
local function HasCraft(id) return craftsT.base[id] or craftsT.wrath[id] end
for tag, d in pairs(WM.LootData) do
    if type(d) == "table" and d.build then
        if not d.category or type(d.expansion) ~= "number" then good, why = false, "meta " .. tag end
        for _, inst in ipairs(d.build()) do
            if ids[inst.id] then good, why = false, "duplicate " .. inst.id end
            ids[inst.id] = true
            perCat[d.category] = (perCat[d.category] or 0) + 1
            if type(inst.name) ~= "string" or not inst.bosses or #inst.bosses == 0 then good, why = false, "empty " .. inst.id end
            for _, b in ipairs(inst.bosses) do
                if type(b[1]) ~= "string" then good, why = false, "row name in " .. inst.id end
                for k, list in pairs(b) do
                    if type(k) == "string" and type(list) == "table" then
                        for _, e in ipairs(list) do
                            for _, id in ipairs(type(e) == "table" and e or { e }) do
                                items = items + 1
                                if type(id) ~= "number" or id < 0 or id % 1 ~= 0 then good, why = false, "bad id in " .. inst.id end
                                if b.set and id > 0 and not HasSet(id) then good, why = false, "missing set " .. id end
                                if b.craft and id > 0 and not HasCraft(id) then good, why = false, "missing craft " .. id end
                            end
                        end
                    end
                end
            end
        end
    end
end
check("data: well formed (" .. why .. ")", good)
check("data: thousands of entries", items > 10000)
check("data: every category", (perCat.dungeons or 0) > 60 and (perCat.crafting or 0) > 30
    and (perCat.factions or 0) > 30 and (perCat.pvp or 0) > 20)
check("data: no custom-server content", not ids.TheHallOfThanes and not ids.OnyxiasLairNew)

-- ---- Expansions ----
local ex = LB:Expansions()
check("TBC client: Classic and TBC", #ex == 2 and ex[1].expansion == 0 and ex[2].expansion == 1
    and ex[2].label == "Burning Crusade")
check("every category for TBC", ex[2].tags.dungeons == "tbc" and ex[2].tags.crafting == "tbcCrafting"
    and ex[2].tags.factions == "tbcFactions" and ex[2].tags.pvp == "tbcPvP" and LB:Tag(1, "pvp") == "tbcPvP")
check("Wrath client: Wrath crafting, factions and PvP, no dungeons yet", (function()
    env.LE_EXPANSION_LEVEL_CURRENT = 2
    local list = LB:Expansions()
    env.LE_EXPANSION_LEVEL_CURRENT = 1
    local w = list[3]
    return #list == 3 and w.expansion == 2 and w.tags.crafting and w.tags.factions and w.tags.pvp and not w.tags.dungeons
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
local shared = LB:Instance("tbc", "tbc_dungeonsShared")
check("shared page name", LB:InstanceName(shared) == "Keys and Tier Sets")
local t4
for _, b in ipairs(LB:Bosses(shared)) do if b[1] == "Tier 4 Sets" then t4 = b end end
local mine = LB:Entries(t4, "n", true)
local all = LB:Entries(t4, "n", false)
check("tier sets: your class only", mine[1] and mine[1].classHeader == "MAGE" and mine[2].set == 648
    and mine[2].name == "Set648" and #mine[2].items == 5 and #mine == 2)
local heads, setsN = 0, 0
for _, e in ipairs(all) do if e.classHeader then heads = heads + 1 elseif e.set then setsN = setsN + 1 end end
check("tier sets: every class, grouped by class", heads == 9 and setsN == 17 and #all == 26
    and all[1].classHeader == "WARRIOR" and all[#all - 3].classHeader == "DRUID")
class = "WARRIOR"
local war = LB:Entries(t4, "n", true)
check("tier sets: warrior's two", war[1].classHeader == "WARRIOR" and war[2].set == 654 and war[3].set == 655 and #war == 3)
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

-- ---- Crafting ----
local alch = LB:Instance("tbcCrafting", "AlchemyBC")
local flasks = LB:Bosses(alch)[1]
local fe = LB:Entries(flasks, "n")
check("crafting: craft entries", flasks[1] == "Flasks" and fe[1].craft == 28591 and #fe == 6)
local c = LB.CraftInfo(28591)
check("crafting: what it makes and the skill", c[1] == 22866 and c[2] == 4 and c[3] == 375 and LB.CraftSkill(28591) == "Alchemy 375")
check("crafting: reagents", c.r[1] == 22794 and c.r[2] == 1 and #c.r == 8)
check("crafting: Wrath changes only on Wrath", LB.CraftInfo(2166).r[4] == 2 and (function()
    env.LE_EXPANSION_LEVEL_CURRENT = 2
    local v = LB.CraftInfo(2166).r[4]
    env.LE_EXPANSION_LEVEL_CURRENT = 1
    return v == 6
end)())
local bsHead
for _, b in ipairs(LB:Bosses(LB:Instance("classicCrafting", "Blacksmithing"))) do if b[1] == "Armor - Head" then bsHead = b end end
local bd = LB:Diffs(bsHead)
check("crafting: plate / mail lists", #bd == 2 and bd[1] == "plate" and bd[2] == "mail")
check("crafting: a list picked", LB:Entries(bsHead, "mail")[1].craft == 16728 and LB:Entries(bsHead, "plate")[1].craft == 23636)
check("crafting: unknown list falls back to the first", LB:Entries(bsHead, "n")[1].craft == 23636)

-- ---- Factions ----
local function Has(tag, id) for _, i in ipairs(LB:Instances(tag)) do if i.id == id then return true end end end
check("factions: your side's", Has("tbcFactions", "Thrallmar") and not Has("tbcFactions", "HonorHold") and Has("tbcFactions", "TheAldor"))
faction = "Alliance"
check("factions: the Alliance's", Has("tbcFactions", "HonorHold") and not Has("tbcFactions", "Thrallmar"))
faction = "Horde"
env.GetFactionInfoByID = function(id) if id == 932 then return "The Aldor (client)" end end
check("factions: the client's name", LB:InstanceName(LB:Instance("tbcFactions", "TheAldor")) == "The Aldor (client)")
env.GetFactionInfoByID = nil
local saber = LB:Bosses(LB:Instance("classicFactions", "WintersaberTrainers"))[1]
check("factions: Alliance-only rewards hidden from the Horde", #LB:Entries(saber, "n") == 0)
faction = "Alliance"
check("factions: and shown to the Alliance", LB:Entries(saber, "n")[1].item == 13086)
faction = "Horde"

-- ---- PvP ----
local s1 = LB:Bosses(LB:Instance("tbcPvP", "ArenaS1PvP"))[1]
local s1e = LB:Entries(s1, "n", true)
check("pvp: arena sets, your class", s1e[1].classHeader == "MAGE" and s1e[2].set == 579 and #s1e == 2)
local honor = LB:Bosses(LB:Instance("tbcPvP", "HonorSetBCC"))[1]
check("pvp: your faction's honor sets", LB:Entries(honor, "n", true)[2].set == 600)
env.LE_EXPANSION_LEVEL_CURRENT = 2
local wl = LB.SetInfo(3003780)
check("pvp: Wrath sets named after their base", wl and wl.base == 780 and LB.SetName(3003780) == "Furious Set780")
env.LE_EXPANSION_LEVEL_CURRENT = 1

-- ---- Where items come from ----
local function Joined(id) return table.concat(LB:SourceLines(id) or {}, "\n") end
check("tooltip: reputation reward", Joined(29123):find("Reputation reward:", 1, true) and Joined(29123):find("The Aldor", 1, true)
    and Joined(29123):find("(Exalted)", 1, true))
check("tooltip: made by", Joined(22866):find("Made by:", 1, true) and Joined(22866):find("Alchemy|r |cFFAAAAAA(375)", 1, true))
check("tooltip: PvP set piece", Joined(24553):find("PvP reward:", 1, true) and Joined(24553):find("Arena Season 1", 1, true))
check("tooltip: kinds in order", Joined(29434):find("^|cFFFFB366Drops from:") ~= nil)

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
check("heroic switch shown", p.diffBar:IsShown() and p.diffBar.buttons[2]:IsShown() and p.diffBar.buttons[2].diff == "h")
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
check("no heroic: switch hidden", not p.diffBar:IsShown())
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
-- Categories and set rows in the window
LB:Show("tbc", "tbc_dungeonsShared")
env.LootBrowserDB.myClassSets = false
p.bossList.rows[2]:_fire("OnClick")   -- Tier 4 Sets
local setsShown = 0
for _, r in ipairs(p.setRows or {}) do if r:IsShown() then setsShown = setsShown + 1 end end
check("set rows: one line per set", setsShown == 17)
check("set rows: class headers", p.itemButtons[1].name:GetText():find("Warrior", 1, true) ~= nil)
check("set rows: a piece per icon", p.setRows[1].pieces[1].itemID ~= nil and p.setRows[1].pieces[1]:IsShown()
    and not p.setRows[1].pieces[10]:IsShown())
env.LootBrowserDB.myClassSets = true
p.catBox.buttons[2]:_fire("OnClick")
check("category: crafting", p.status:GetText():find("Alchemy", 1, true) and env.LootBrowserDB.category == "crafting")
check("category: craft rows", p.itemButtons[1].craftID ~= nil)
local craftTip = {}
env.GameTooltip.AddLine = function(_, l) craftTip[#craftTip + 1] = l end
p.itemButtons[1]._scripts.OnEnter(p.itemButtons[1])
check("craft tooltip: skill and reagents", table.concat(craftTip, "\n"):find("Requires Alchemy", 1, true) ~= nil)
p.catBox.buttons[3]:_fire("OnClick")
check("category: factions", env.LootBrowserDB.category == "factions" and p.instList.rows[1]:IsShown())
p.catBox.buttons[1]:_fire("OnClick")
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
