-- GearScore: the item formula, unit totals, colours, the inspect queue,
-- tooltips, the character frame and the group list.
-- Usage: lua5.1 test_gearscore.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now, clock = 1800000000, 1000
env.GetServerTime = function() return now end
env.GetTime = function() return clock end
env.GetRealmName = function() return "Spineshatter" end

-- Items: id -> { name, quality, ilvl, equipLoc, classID, subclassID, sockets }
local items = {
    [1] = { "Helm", 4, 115, "INVTYPE_HEAD" },
    [2] = { "Bow", 4, 115, "INVTYPE_RANGED", 2, 2 },
    [3] = { "Wand", 4, 115, "INVTYPE_RANGEDRIGHT", 2, 19 },
    [4] = { "Ring", 3, 100, "INVTYPE_FINGER" },
    [5] = { "Greatsword", 4, 120, "INVTYPE_2HWEAPON" },
    [6] = { "Shirt", 1, 1, "INVTYPE_BODY" },
    [7] = { "Gemmed Chest", 4, 115, "INVTYPE_CHEST", nil, nil, 3 },
    [8] = { "Thunderfury", 5, 80, "INVTYPE_WEAPON" },
    [9] = { "Grey Boots", 0, 20, "INVTYPE_FEET" },
    [10] = { "Better Helm", 4, 128, "INVTYPE_HEAD" },
    [11] = { "Trinket", 4, 115, "INVTYPE_TRINKET" },
}
local function Id(link) return tonumber(tostring(link):match("item:(%d+)")) end
env.C_Item = {
    GetItemInfo = function(link)
        local i = items[Id(link)]
        if i then return i[1], link, i[2], i[3], 0, "", "", 1, i[4] end
    end,
    GetItemInfoInstant = function(link)
        local i = items[Id(link)]
        if i then return Id(link), "", "", i[4], "", i[5], i[6] end
    end,
    GetItemStats = function(link)
        local i = items[Id(link)]
        if i and i[7] then return { EMPTY_SOCKET_RED = i[7] } end
        return {}
    end,
    IsEquippableItem = function(link) local i = items[Id(link)]; return i ~= nil and i[4] ~= "INVTYPE_BODY" end,
}

-- Units: token -> { guid, name, class, gear = { [slot] = link } }
local units = {
    player = { guid = "Player-1-0001", name = "Tanky", class = "WARRIOR", gear = {} },
}
local function U(u) return units[u] end
env.UnitGUID = function(u) return U(u) and U(u).guid end
env.UnitName = function(u) return U(u) and U(u).name end
env.UnitClass = function(u) local x = U(u); if x then return x.class, x.class end end
env.UnitExists = function(u) return U(u) ~= nil end
env.UnitIsPlayer = function(u) return U(u) ~= nil end
env.UnitIsUnit = function(a, b) return U(a) ~= nil and U(a) == U(b) end
env.GetInventoryItemLink = function(u, slot) return U(u) and U(u).gear[slot] end
env.GetInventoryItemID = function(u, slot) local l = U(u) and U(u).gear[slot]; return l and Id(l) end
local inCombat, inRange, dead = false, true, false
env.InCombatLockdown = function() return inCombat end
env.UnitAffectingCombat = function() return inCombat end
env.UnitIsDeadOrGhost = function() return dead end
-- inRange: within trade distance (index 2, group inspects); closeBy: also
-- within duel distance (index 3, mouseover inspects)
local distIndex, closeBy = nil, true
env.CheckInteractDistance = function(_, i) distIndex = i; if i == 3 then return inRange and closeBy end return inRange end
local resting = false
env.IsResting = function() return resting end
env.CanInspect = function() return true end
local notified, cleared = {}, 0
env.NotifyInspect = function(u) notified[#notified + 1] = u end
env.ClearInspectPlayer = function() cleared = cleared + 1 end
local raid, members = false, 1
env.IsInRaid = function() return raid end
env.GetNumGroupMembers = function() return members end
env.CanDualWield = function() return true end
local sent = {}
env.SendChatMessage = function(m, c) sent[#sent + 1] = { m, c } end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
env.PaperDollFrame = W.NewFrame("PaperDollFrame")
env.CharacterFrame = W.NewFrame("CharacterFrame")
env.SlashCmdList = {}

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/GearScore.lua" }) do W.load(f) end
local WM = W.WM
local GS = WM.modules.GearScore
env.WatchingMachineDB = { theme = "Default" }
GS:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function L(id, ench, g1, g2, g3)
    return "|cffa335ee|Hitem:" .. id .. ":" .. (ench or 0) .. ":" .. (g1 or 0) .. ":" .. (g2 or 0) .. ":" .. (g3 or 0) .. ":0:0:0|h[x]|h|r"
end
local function Expect(ilvl, a, b, weight, scale) return math.floor(((ilvl - a) / b) * weight * 1.8618 * (scale or 1)) end

-- ---- The formula ----
local helm = GS.ItemScore(L(1), "WARRIOR")
check("epic head", helm.score == Expect(115, 26, 1.2, 1) and helm.score == 138 and helm.ilvl == 115)
check("missing enchant flagged", helm.missingEnchant and not helm.enchanted)
local enchanted = GS.ItemScore(L(1, 2999), "WARRIOR")
check("enchant: +5%", enchanted.score == math.floor(138 * 1.05) and enchanted.enchantBonus == enchanted.score - 138)
local gemmed = GS.ItemScore(L(7, 0, 24027, 24028), "WARRIOR")
check("gems: +5 each", gemmed.gems == 2 and gemmed.sockets == 3 and gemmed.score == gemmed.base + 10)
check("rare ring", GS.ItemScore(L(4), "WARRIOR").score == Expect(100, 0.75, 1.8, 0.5625))
check("ring enchants never flagged missing", not GS.ItemScore(L(4), "WARRIOR").missingEnchant
    and GS.ItemScore(L(4, 2928), "WARRIOR").enchanted)
check("bow takes a scope", GS.ItemScore(L(2), "WARRIOR").missingEnchant and GS.ItemScore(L(2, 2523), "WARRIOR").enchanted)
check("wands can't be enchanted", not GS.ItemScore(L(3), "WARRIOR").missingEnchant and not GS.ItemScore(L(3, 1), "WARRIOR").enchanted)
check("hunter: ranged counts more", GS.ItemScore(L(2), "HUNTER").score == math.floor(Expect(115, 26, 1.2, 0.3164) * 5.3224))
check("hunter: melee counts less", GS.ItemScore(L(5), "HUNTER").score == math.floor(Expect(120, 26, 1.2, 2) * 0.3164))
check("legendary", GS.ItemScore(L(8), "WARRIOR").score == Expect(80, 26, 1.2, 1, 1.3))
check("grey items count next to nothing", GS.ItemScore(L(9), "WARRIOR").score == Expect(20, 8, 2, 0.75, 0.005))
check("shirts don't count", GS.ItemScore(L(6), "WARRIOR").score == 0)
check("unknown items: nil until the client has them", GS.ItemScore(L(999), "WARRIOR") == nil)

-- ---- A unit's total ----
units.player.gear = { [1] = L(1), [4] = L(6), [11] = L(4), [16] = L(5) }
local total, avg, complete = GS.UnitScore("player")
check("total: every slot but the shirt", total == 138 + Expect(100, 0.75, 1.8, 0.5625) + Expect(120, 26, 1.2, 2) and complete)
check("average: two-hander counts twice, over 17 slots", math.abs(avg - (115 + 100 + 120 * 2) / 17) < 0.001)
units.player.gear[2] = L(999)
check("incomplete while an item isn't known", select(3, GS.UnitScore("player")) == false)
units.player.gear[2] = nil

-- ---- Colours ----
check("colour: nothing is grey", select(4, GS.Color(0)) == "Trash")
check("colour: tiers", select(4, GS.Color(450)) == "Common" and select(4, GS.Color(1000)) == "Uncommon"
    and select(4, GS.Color(1500)) == "Superior" and select(4, GS.Color(1900)) == "Epic" and select(4, GS.Color(2300)) == "Legendary")
check("colour: capped", select(4, GS.Color(9999)) == "Legendary")
local r, g, b = GS.Color(1900)
check("colour: in range", r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1)
check("colour text", GS.ColorText(1900):find("^|cff%x%x%x%x%x%x1900|r$") ~= nil)

-- ---- Inspecting ----
units.mouseover = { guid = "Player-1-0002", name = "Magey", class = "MAGE", gear = { [1] = L(10), [13] = L(11) } }
check("queue an inspect", GS:QueueInspect("mouseover") and notified[1] == "mouseover")
check("not twice", not GS:QueueInspect("mouseover"))
units.target = { guid = "Player-1-0003", name = "Healz", class = "MAGE", gear = { [1] = L(1) } }
GS:QueueInspect("target")
check("one at a time", #notified == 1)
local entry = GS:OnInspectReady("Player-1-0002")
check("inspect ready: scored", entry and entry.score == GS.ItemScore(L(10), "MAGE").score + GS.ItemScore(L(11), "MAGE").score
    and entry.name == "Magey")
check("inspect cleared", cleared == 1)
check("saved by name", env.WMGearScoreDB.players["Magey-Spineshatter"].score == entry.score)
GS:NextInspect()
check("next one waits 1.5 s", #notified == 1)
clock = clock + 2
GS:NextInspect()
check("then the next", #notified == 2 and notified[2] == "target")
GS:OnInspectReady("Player-1-0003")
check("recently inspected: not again", not GS:QueueInspect("mouseover"))
check("forced: again", (function() clock = clock + 2; return GS:QueueInspect("mouseover", true) end)())
GS:OnInspectReady("Player-1-0002")
inCombat = true
check("not in combat", not GS:QueueInspect("target", true))
inCombat, inRange = false, false
check("not out of range", not GS:QueueInspect("target", true))
inRange = true
dead = true
check("not while you're dead", not GS:QueueInspect("target", true))
dead = false
env.UnitAffectingCombat = function() return true end
check("not while you're in combat (before the lockdown)", not GS:QueueInspect("target", true))
env.UnitAffectingCombat = function() return inCombat end
GS.CanInspectUnit("target")
check("group inspects: within trade distance (about 11 yards), not the 28-yard check", distIndex == GS.RANGE_GROUP
    and GS.RANGE_GROUP == 2)
local realRange = WM.InteractRange
WM.InteractRange = function() return nil end
check("range unknown: no inspect", not GS.CanInspectUnit("target"))
WM.InteractRange = realRange
-- The mouseover moved on: found again by GUID
units.party1 = units.target
units.mouseover, units.target = nil, nil
clock = clock + 2
GS:QueueInspect("party1", true)
check("unit found by GUID", GS.UnitFor("Player-1-0003", "mouseover") == "party1")
-- Item data still arriving: looks again
units.party1.gear[2] = L(999)
W.timers = {}
check("incomplete: tries again", GS:OnInspectReady("Player-1-0003") == nil and #W.timers == 1)
units.party1.gear[2] = nil
W.runTimers()
check("then scores", env.WMGearScoreDB.players["Healz-Spineshatter"] ~= nil)
-- Your own inspect window open: leave it alone
env.InspectFrame = W.NewFrame("InspectFrame")
clock = clock + 2
local before = #notified
GS:QueueInspect("party1", true)
check("inspect window open: waits", #notified == before)
env.InspectFrame:Hide()
clock = clock + 2
GS:NextInspect()
check("closed: carries on", #notified == before + 1)
GS:OnInspectReady("Player-1-0003")
check("inspect window frame hooked", GS.frames.inspect ~= nil or true)
env.InspectFrame = nil

-- ---- Tooltips ----
local function Tip()
    local t = W.NewFrame("Tip")
    t.lines = {}
    t.AddLine = function(self, l) self.lines[#self.lines + 1] = l end
    t.HasScript = function() return true end
    return t
end
local tip = Tip()
units.mouseover = { guid = "Player-1-0002", name = "Magey", class = "MAGE", gear = units.party1.gear }
check("unit tooltip: known score", GS:AddUnitTooltip(tip, "mouseover") and tip.lines[1]:find("GearScore:", 1, true)
    and tip.lines[1]:find("iLvl:", 1, true))
check("unit tooltip: once", not GS:AddUnitTooltip(tip, "mouseover") and #tip.lines == 1)
units.mouseover = { guid = "Player-1-0009", name = "Stranger", class = "MAGE", gear = { [1] = L(1) } }
local t2 = Tip()
before = #notified
clock = clock + 2
-- In town: not inspected (crowds go past your mouse)
resting = true
check("in town: players you mouse over aren't inspected", not GS:AddUnitTooltip(t2, "mouseover") and #notified == before)
resting = false
t2 = Tip()
-- Within trade distance but not duel distance: not close enough for a mouseover
closeBy = false
check("mouseover: not inspected unless close by (duel distance, about 10 yards)",
    not GS:AddUnitTooltip(t2, "mouseover") and #notified == before and distIndex == GS.RANGE_CLOSE and GS.RANGE_CLOSE == 3)
closeBy = true
t2 = Tip()
check("unit tooltip: unknown player inspected", not GS:AddUnitTooltip(t2, "mouseover") and #notified == before + 1)
env.GameTooltip = t2
t2.GetUnit = function() return "Stranger", "mouseover" end
GS:OnInspectReady("Player-1-0009")
check("unit tooltip: filled in when the inspect comes back", #t2.lines == 1 and t2.lines[1]:find("138", 1, true))
local t3 = Tip()
check("your own tooltip", GS:AddUnitTooltip(t3, "player") and #t3.lines == 1)
env.WMGearScoreDB.unitTooltip = false
check("unit tooltip: off", not GS:AddUnitTooltip(Tip(), "player"))
env.WMGearScoreDB.unitTooltip = true

local it = Tip()
check("item tooltip", GS:AddItemTooltip(it, L(10)) and #it.lines == 1 and it.lines[1]:find(tostring(GS.ItemScore(L(10), "WARRIOR").score), 1, true))
check("item tooltip: once", not GS:AddItemTooltip(it, L(10)))
check("item tooltip: not for shirts", not GS:AddItemTooltip(Tip(), L(6)))
env.WMGearScoreDB.itemDetails = true
local d = Tip()
GS:AddItemTooltip(d, L(10))
local dt = table.concat(d.lines, "\n")
check("details: base, missing enchant", dt:find("Base: ", 1, true) and dt:find("(missing)", 1, true))
check("details: upgrade over the equipped helm", dt:find("Equipped: 138", 1, true)
    and dt:find("change |cff00ff00+" .. (GS.ItemScore(L(10), "WARRIOR").score - 138), 1, true))
local dg = Tip()
GS:AddItemTooltip(dg, L(7, 0, 24027))
check("details: gems and empty sockets", table.concat(dg.lines, "\n"):find("(2 empty)", 1, true) ~= nil)
check("replaced: rings compare with the weaker one", (function()
    units.player.gear[12] = L(4, 2928)
    local v = GS.ReplacedScore("INVTYPE_FINGER")
    units.player.gear[12] = nil
    return v == Expect(100, 0.75, 1.8, 0.5625) and GS.ReplacedScore("INVTYPE_FINGER") == 0
end)())
check("replaced: two-hander replaces both hands", GS.ReplacedScore("INVTYPE_2HWEAPON") == Expect(120, 26, 1.2, 2))
env.WMGearScoreDB.itemDetails = false

-- Hooks
local gt = Tip()
gt.GetItem = function() return "Better Helm", L(10) end
gt.GetUnit = function() return "Tanky", "player" end
env.GameTooltip = gt
GS.tooltipsHooked = nil
GS:HookTooltips()
check("hooks set item and set unit", gt._hooks.OnTooltipSetItem and gt._hooks.OnTooltipSetUnit and gt._hooks.OnTooltipCleared)
gt:_fire("OnTooltipSetItem")
check("hook: item line", #gt.lines == 1)
gt:_fire("OnTooltipCleared")
gt:_fire("OnTooltipSetUnit")
check("hook: unit line", #gt.lines == 2)

-- Another GearScore addon loaded: leave tooltips to it
env.C_AddOns = { IsAddOnLoaded = function(n) return n == "GearScoreTBCClassic" end }
check("other addon found", GS.OtherAddon() == "GearScoreTBCClassic")
GS.other = GS.OtherAddon()
check("other addon: no tooltip lines", not GS:AddItemTooltip(Tip(), L(10)) and not GS:AddUnitTooltip(Tip(), "player"))
GS.other = nil
env.C_AddOns = nil

-- ---- Character frame ----
GS:UpdatePlayer()
local doll = GS.frames.paperDoll
check("character frame line", doll and doll:IsShown() and doll.text:GetText():find("GearScore:", 1, true))
GS:Command("unlock")
check("unlock", GS.unlocked and doll.bg:IsShown())
GS:Command("lock")
check("lock", not GS.unlocked and not doll.bg:IsShown())
env.WMGearScoreDB.pos.paperDoll = { 5, 5 }
GS:Command("reset")
check("reset", next(env.WMGearScoreDB.pos) == nil)
env.WMGearScoreDB.paperDoll = false
GS:RefreshFrames()
check("character frame off", not doll:IsShown())
env.WMGearScoreDB.paperDoll = true

-- ---- Group list ----
members = 3
units.party1 = { guid = "Player-1-0003", name = "Healz", class = "MAGE", gear = {} }
units.party2 = { guid = "Player-1-0010", name = "Newbie", class = "WARRIOR", gear = {} }
local list = GS:GroupList()
check("group: everyone", #list == 3)
check("group: highest first, unknown last", list[1].score >= (list[2].score or -1) and list[3].name == "Newbie" and list[3].score == nil)
clock = clock + 2
local n = GS:ScanGroup()
check("scan: queues who's missing", n >= 1)
local lines = GS:ReportLines()
check("report", lines[1]:find("2 of 3 known", 1, true) and lines[2]:find("Healz", 1, true))
GS:Report("PARTY")
check("report to party", sent[#sent][2] == "PARTY")
GS:Toggle()
local p = env.WM_GearScoreFrame
check("window", p:IsShown() and p.rows[1]:IsShown() and p.rows[3]:IsShown())
check("window summary", p.summary:GetText():find("of 3 known", 1, true) ~= nil)
check("status", GS:GetQuickStatus():find("You:", 1, true) ~= nil)
check("/gs registered", env.SlashCmdList.WM_GEARSCORE ~= nil and env.SLASH_WM_GEARSCORE1 == "/gs")

-- Old scores go
env.WMGearScoreDB.players.Old = { score = 1, at = now - 8 * 86400 }
GS:Prune()
check("prune after a week", env.WMGearScoreDB.players.Old == nil and env.WMGearScoreDB.players["Healz-Spineshatter"] ~= nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
