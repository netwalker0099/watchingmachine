-- Gear Sets: item matching, the swap engine against a simulated inventory
-- (cursor, swaps in place, locks, two-handers, full bags, combat, casting),
-- missing-item alerts, spec / mount / battleground swaps, the character
-- sheet warning, the quick-swap menu, the window and editor, commands.
-- Usage: lua5.1 test_gearsets.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- ---- A simulated character: worn items, bags, the cursor ----
local LOC, NAMES = {}, {}   -- [item id] = equip location, name
local function Item(id, loc, name, opts)
    LOC[id], NAMES[id] = loc, name
    opts = opts or {}
    return string.format("|cffa335ee|Hitem:%d:%d:%d:0:0:0:%d:%d:70|h[%s]|h|r", id, opts.ench or 0, opts.gem or 0,
        opts.suffix or 0, opts.uniq or 0, name)
end
local function IDOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
local inv, bags = {}, {}
for b = 0, 4 do bags[b] = { n = 4, items = {} } end
local cursor
local locking, locks = false, {}
local function K(loc) return loc.inv and ("i" .. loc.inv) or (loc.bag .. ":" .. loc.slot) end
local function Get(loc) if loc.inv then return inv[loc.inv] end return bags[loc.bag].items[loc.slot] end
local function Put(loc, link) if loc.inv then inv[loc.inv] = link else bags[loc.bag].items[loc.slot] = link end end
local FITS
local function Fits(link, slot)
    if not link then return true end
    for _, s in ipairs(FITS[LOC[IDOf(link)]] or {}) do if s == slot then return true end end
    return false
end
local function TwoHand(link) return link and LOC[IDOf(link)] == "INVTYPE_2HWEAPON" end
local refuse = {}         -- [slot] = times the "server" refuses an equip
local function Place(to)
    local from, link = cursor.from, cursor.link
    if K(from) == K(to) then cursor = nil; return end
    if to.inv and (refuse[to.inv] or 0) > 0 then refuse[to.inv] = refuse[to.inv] - 1; return end
    local old = Get(to)
    if to.inv then
        if not Fits(link, to.inv) then return end
        if to.inv == 16 and TwoHand(link) and inv[17] and not (from.inv == 17) then return end
        if to.inv == 17 and TwoHand(inv[16]) then return end
    end
    if from.inv and old and not Fits(old, from.inv) then return end
    Put(from, old)
    Put(to, link)
    cursor = nil
    if locking then locks[K(from)], locks[K(to)] = true, true end
end
local function Pickup(loc)
    if cursor then return Place(loc) end
    if Get(loc) and not locks[K(loc)] then cursor = { link = Get(loc), from = loc } end
end
local function Server() locks = {} end

env.GetInventoryItemLink = function(_, slot) return inv[slot] end
env.IsInventoryItemLocked = function(slot) return locks["i" .. slot] or false end
env.PickupInventoryItem = function(slot) Pickup({ inv = slot }) end
env.C_Container = {
    GetContainerNumSlots = function(b) return bags[b] and bags[b].n or 0 end,
    GetContainerItemInfo = function(b, s)
        local l = bags[b] and bags[b].items[s]
        if l then return { hyperlink = l, isLocked = locks[b .. ":" .. s] or false, stackCount = 1 } end
    end,
    GetContainerNumFreeSlots = function(b) return 0, bags[b] and bags[b].family or 0 end,
    PickupContainerItem = function(b, s) Pickup({ bag = b, slot = s }) end,
}
env.CursorHasItem = function() return cursor ~= nil end
env.ClearCursor = function() cursor = nil end
env.SpellIsTargeting = function() return false end
local casting = false
env.UnitCastingInfo = function() return casting and "Frostbolt" or nil end
env.UnitChannelInfo = function() return nil end
local combat, dead = false, false
env.InCombatLockdown = function() return combat end
env.UnitAffectingCombat = function() return combat end
env.UnitIsDeadOrGhost = function() return dead end
env.GetItemInfoInstant = function(link) local id = IDOf(link) or tonumber(link); return id, "Armor", "Misc", LOC[id] end
-- The client knows items it has cached: name and a link
env.GetItemInfo = function(l)
    local id = IDOf(l) or tonumber(l)
    if NAMES[id] then return NAMES[id], "|cffa335ee|Hitem:" .. id .. "|h[" .. NAMES[id] .. "]|h|r" end
end
env.GetItemIcon = function(id) return "icon" .. tostring(id) end
env.C_Item = {}
local mounted, zone = false, "none"
env.IsMounted = function() return mounted end
env.IsInInstance = function() return zone ~= "none", zone end
local spec = 1
env.GetActiveTalentGroup = function() return spec end
env.GetNumTalentGroups = function() return 2 end
env.GetTalentTabInfo = function(tab, _, _, group)
    local pts = group == 1 and { 0, 41, 20 } or { 41, 0, 20 }
    return ({ "Holy", "Protection", "Retribution" })[tab], "icon", pts[tab]
end
local alt = false
env.IsAltKeyDown = function() return alt end
env.MouseIsOver = function() return false end
env.StaticPopup_Show = function(_, _, _, fn) fn() end
env.GetRealmName = function() return "Testrealm" end
env.UnitName = function() return "Me" end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/GearSets.lua" }) do W.load(f) end
local WM = W.WM
local GS = WM.modules.GearSets
FITS = GS.FITS
env.WatchingMachineDB = { theme = "Default" }
-- Catch the module's event frame
local evFrame
local origRegister = WM.RegisterEvents
WM.RegisterEvents = function(_, fr) evFrame = fr end
GS:Initialize()
WM.RegisterEvents = origRegister
local function Event(ev, ...) evFrame._scripts.OnEvent(evFrame, ev, ...) end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Run(n)
    for _ = 1, n or 40 do
        if not GS.job then return end
        GS:Tick(0.1)
        Server()
    end
end
local function Said(text)
    for i = #W.printed, 1, -1 do if W.printed[i]:find(text, 1, true) then return W.printed[i] end end
end
local function Count(id)
    local n = 0
    for _, l in pairs(inv) do if IDOf(l) == id then n = n + 1 end end
    for b = 0, 4 do for _, l in pairs(bags[b].items) do if IDOf(l) == id then n = n + 1 end end end
    return n
end

-- The gear
local HELM_T = Item(29011, "INVTYPE_HEAD", "Warbringer Greathelm", { ench = 3003 })
local HELM_D = Item(29021, "INVTYPE_HEAD", "Warbringer Battle-Helm")
local CHEST_T = Item(29012, "INVTYPE_CHEST", "Warbringer Chestguard")
local CHEST_D = Item(29019, "INVTYPE_CHEST", "Warbringer Breastplate")
local TRINK_A1 = Item(28528, "INVTYPE_TRINKET", "Moroes' Lucky Pocket Watch", { uniq = 111 })
local TRINK_A2 = Item(28528, "INVTYPE_TRINKET", "Moroes' Lucky Pocket Watch", { uniq = 222 })
local TRINK_B = Item(29383, "INVTYPE_TRINKET", "Bloodlust Brooch")
local SWORD = Item(28189, "INVTYPE_WEAPON", "Latro's Shifting Sword")
local SHIELD = Item(28825, "INVTYPE_SHIELD", "Aldori Legacy Defender")
local AXE = Item(28773, "INVTYPE_2HWEAPON", "Gorehowl")
local RING_X = Item(29279, "INVTYPE_FINGER", "Violet Signet of the Great Protector")
local RING_Y = Item(28757, "INVTYPE_FINGER", "Ring of a Thousand Marks")

-- ---- Matching ----
check("item string", GS.ItemString(HELM_T) == "29011:3003:0:0:0:0:0:0")
check("same item", GS.Match(GS.ItemString(TRINK_A1), GS.ItemString(TRINK_A1)) == 3)
check("the other copy", GS.Match(GS.ItemString(TRINK_A1), GS.ItemString(TRINK_A2)) == 2)
check("re-enchanted", GS.Match(GS.ItemString(HELM_T), GS.ItemString(Item(29011, "INVTYPE_HEAD", "x", { ench = 1 }))) == 1)
check("random suffix matters", GS.Match("1:0:0:0:0:0:5:0", "1:0:0:0:0:0:6:0") == 0)
check("other item", GS.Match(GS.ItemString(HELM_T), GS.ItemString(HELM_D)) == 0)

-- ---- Saving a set from what you're wearing ----
inv = { [1] = HELM_T, [5] = CHEST_T, [13] = TRINK_A1, [14] = TRINK_B, [16] = SWORD, [17] = SHIELD, [11] = RING_X }
bags[0].items = { HELM_D, CHEST_D, TRINK_A2, AXE }
bags[1].items = { RING_Y }
local ed = GS:OpenEditor(nil)
check("new set: what you wear, current spec", ed.draft.items[1] == GS.ItemString(HELM_T) and ed.draft.items[12] == false
    and ed.draft.items[4] == nil and ed.draft.spec == 1 and ed.draft.specAuto)
ed.draft.name = "Tank"
check("saved", GS:SaveDraft() and GS.Char().sets.Tank and not ed:IsShown() and Said("Saved Tank, equipped when you switch to Spec 1: Protection"))
check("wearing it", GS:IsWearing(GS.Char().sets.Tank))
-- A DPS set by hand
GS:SaveSet("DPS", { [1] = GS.ItemString(HELM_D), [5] = GS.ItemString(CHEST_D), [13] = GS.ItemString(TRINK_A2),
    [14] = GS.ItemString(TRINK_A1), [16] = GS.ItemString(AXE), [12] = GS.ItemString(RING_Y) }, { spec = 2, specAuto = true })
check("save needs a name", select(2, GS:SaveSet("  ", { [1] = false })) ~= nil)
check("renaming onto another set refused", select(2, GS:SaveSet("Tank", { [1] = false }, { oldName = "DPS" })) ~= nil)

-- ---- Swapping ----
W.printed = {}
GS:EquipSet("DPS")
Run()
check("DPS on", inv[1] == HELM_D and inv[5] == CHEST_D and inv[16] == AXE and inv[12] == RING_Y and not GS.job)
check("the very same trinket copies, swapped over", inv[13] == TRINK_A2 and inv[14] == TRINK_A1)
check("two-hander: the shield went to your bags first", inv[17] == nil and Count(28825) == 1)
check("nothing lost", Count(29011) == 1 and Count(29012) == 1 and Count(28189) == 1 and Count(29383) == 1)
check("said so", Said("Equipped DPS.") ~= nil)
check("current set", GS.Char().current == "DPS")
-- Back to the tank set: off hand back on after the main hand
GS:EquipSet("Tank")
Run()
check("Tank back on", inv[1] == HELM_T and inv[16] == SWORD and inv[17] == SHIELD and inv[13] == TRINK_A1 and inv[14] == TRINK_B
    and inv[12] == nil and Count(28757) == 1)
GS:EquipSet("Tank")
Run()
check("already wearing it", Said("already wearing Tank") ~= nil)

-- No free bag space needed for a straight swap
bags[0].items = { HELM_D, CHEST_D, TRINK_A2, AXE }
bags[1].items = { RING_Y, Item(1, "INVTYPE_HEAD", "Junk"), Item(2, "", "Junk"), Item(3, "", "Junk") }
for b = 2, 4 do bags[b].items = { Item(4, "", "J"), Item(5, "", "J"), Item(6, "", "J"), Item(7, "", "J") } end
GS:Equip({ [1] = GS.ItemString(HELM_D), [5] = GS.ItemString(CHEST_D) }, "Swap")
Run()
check("bags full: swaps in place still work", inv[1] == HELM_D and inv[5] == CHEST_D)
-- But taking a shield off for the two-hander needs room
W.printed = {}
GS:Equip({ [16] = GS.ItemString(AXE) }, "Axe")
Run()
check("bags full: the two-hander can't go on", inv[16] == SWORD and inv[17] == SHIELD and Said("Couldn't finish Axe")
    and Said("no room in your bags for the off hand"))
for b = 1, 4 do bags[b].items = {} end
bags[1].items = { RING_Y }

-- A soul bag or quiver can't take gear
bags[2].family, bags[2].items = 1, {}
bags[0].items, bags[3].items, bags[4].items = { HELM_T, CHEST_T, TRINK_A2, AXE }, {}, {}
for b = 3, 4 do bags[b].n = 0 end
bags[1].items = { RING_Y, Item(8, "", "J"), Item(9, "", "J"), Item(10, "", "J") }
GS:Equip({ [17] = false }, "Off")
Run()
check("special bags aren't used for gear", inv[17] == SHIELD and Said("bags are full"))
bags[2].family = nil
for b = 3, 4 do bags[b].n = 4 end
for b = 1, 4 do bags[b].items = {} end
bags[1].items = { RING_Y }
GS:Equip({ [17] = false }, "Off")
Run()
check("take a slot off", inv[17] == nil and Count(28825) == 1)
GS:Equip({ [17] = GS.ItemString(SHIELD) }, "Shield", true)
Run()

-- Refused once (the server not caught up yet): tried again
refuse[5] = 1
GS:Equip({ [5] = GS.ItemString(CHEST_T) }, "Retry", true)
Run()
check("a refusal is retried", inv[5] == CHEST_T)
refuse[5] = 10
W.printed = {}
GS:Equip({ [5] = GS.ItemString(CHEST_D) }, "Never")
Run()
check("refused every time: reported", inv[5] == CHEST_T and Said("Couldn't finish Never") and Said("wouldn't equip it"))
refuse[5] = nil

-- Re-gemmed: still found
local HELM_T2 = Item(29011, "INVTYPE_HEAD", "Warbringer Greathelm", { ench = 2999 })
inv[1] = HELM_D
bags[0].items[1] = HELM_T2
GS:Equip({ [1] = GS.ItemString(HELM_T) }, "Regem")
Run()
check("an item with a new enchant still counts", inv[1] == HELM_T2)

-- ---- Waiting ----
-- Locks: nothing moves while the server hasn't answered
inv[1] = HELM_T2
bags[0].items[1] = HELM_D
locks["0:1"] = true
GS:Equip({ [1] = GS.ItemString(HELM_D) }, "Locked")
check("a locked item isn't touched", inv[1] == HELM_T2 and GS.job)
locks = {}
GS:Tick(0.1)
check("goes once it's free", inv[1] == HELM_D)
Run()
-- A lock that never clears: gives up and says so
locks["0:1"] = true
W.printed = {}
GS:Equip({ [1] = GS.ItemString(HELM_T2) }, "Stuck")
for _ = 1, 100 do if GS.job then GS:Tick(0.1) end end
check("stuck: gives up after a while", not GS.job and Said("Couldn't finish Stuck") and Said("timed out"))
locks = {}
-- Cursor in use
cursor = { link = RING_Y, from = { bag = 1, slot = 1 } }
GS:Equip({ [1] = GS.ItemString(HELM_T2) }, "Cursor")
GS:Tick(0.1)
check("cursor busy: waits", GS.job and GS.job.waiting == "cursor" and inv[1] == HELM_D)
cursor = nil
Run()
check("then carries on", inv[1] == HELM_T2)
-- Casting
casting = true
GS:Equip({ [1] = GS.ItemString(HELM_D) }, "Cast")
for _ = 1, 200 do GS:Tick(0.1) end
check("waits out a cast without timing out", GS.job and GS.job.waiting == "casting" and inv[1] == HELM_T2)
casting = false
Run()
check("after the cast", inv[1] == HELM_D)
-- Dead
dead = true
GS:Equip({ [1] = GS.ItemString(HELM_T2) }, "Dead")
check("dead: waits", GS.job and GS.job.waiting == "dead")
dead = false
Event("PLAYER_UNGHOST")
Run()
check("alive again: on", inv[1] == HELM_T2)

-- Combat: weapons now, armour after
combat = true
W.printed = {}
GS:EquipSet("DPS")
Run(5)
check("combat: the weapon swaps", inv[16] == AXE and inv[17] == nil)
check("combat: armour waits", inv[1] == HELM_T2 and GS.job and GS.job.waiting == "combat" and Said("will go on when combat ends"))
combat = false
Event("PLAYER_REGEN_ENABLED")
Run()
check("combat over: the rest goes on", inv[1] == HELM_D and inv[5] == CHEST_D and not GS.job)

-- ---- Missing items ----
local TABARD = Item(31404, "INVTYPE_TABARD", "Green Trophy Tabard of the Illidari")
GS.Char().sets.DPS.items[19] = GS.ItemString(TABARD)
W.printed = {}
GS:EquipSet("DPS")
Run()
local msg = Said("Missing from DPS")
check("chat alert for a missing item", msg and msg:find("Green Trophy Tabard", 1, true) and not msg:find("bank", 1, true))
WM.modules.AltTracker = { DB = function() return { chars = { ["Me-Testrealm"] = { bank = { { TABARD } } } } } end }
W.printed = {}
GS:EquipSet("DPS")
Run()
check("says when it's in your bank", (Said("Missing from DPS") or ""):find("in your bank", 1, true) ~= nil)
check("missing list", #GS:MissingItems() == 1 and GS:MissingItems()[1].bank)
GS.DB().reportMissing = false
W.printed = {}
GS:EquipSet("DPS")
Run()
check("alert can be turned off", Said("Missing from") == nil)
GS.DB().reportMissing = true
WM.modules.AltTracker = nil

-- ---- Undo ----
GS:EquipSet("Tank")
Run()
GS:Undo()
Run()
check("undo puts back what you wore", inv[16] == AXE and inv[1] == HELM_D)
GS:EquipSet("Tank")
Run()

-- ---- Talent spec ----
check("spec names", GS.SpecName(1) == "Spec 1: Protection (0/41/20)" and GS.SpecName(2):find("Holy", 1, true))
check("set for a spec", GS:SetForSpec(2).name == "DPS")
Event("ACTIVE_TALENT_GROUP_CHANGED")
check("before you're in the world: no swap", not GS.job)
Event("PLAYER_ENTERING_WORLD")
W.printed = {}
spec = 2
Event("ACTIVE_TALENT_GROUP_CHANGED")
check("switching spec equips its set", GS.job and GS.job.name == "DPS" and Said("Switched to Spec 2"))
Run()
check("spec 2 gear on", inv[16] == AXE)
Event("PLAYER_TALENT_UPDATE")
check("same spec again: nothing", not GS.job)
spec = 1
Event("PLAYER_TALENT_UPDATE")
Run()
check("back to spec 1: tank gear", inv[16] == SWORD and inv[17] == SHIELD)
GS.Char().sets.DPS.specAuto = false
spec = 2
Event("ACTIVE_TALENT_GROUP_CHANGED")
check("per-set switch off: no swap", not GS.job and inv[16] == SWORD)
GS.Char().sets.DPS.specAuto = true
spec = 1
Event("ACTIVE_TALENT_GROUP_CHANGED")
Run()
GS.DB().auto = false
spec = 2
Event("ACTIVE_TALENT_GROUP_CHANGED")
check("automatic swaps off: no swap", not GS.job and GS.IsModuleEnabled == nil)
GS.DB().auto = true
spec = 1
Event("ACTIVE_TALENT_GROUP_CHANGED")
Run()

-- ---- Mounted and battlegrounds ----
local CROP = Item(25653, "INVTYPE_TRINKET", "Riding Crop")
bags[2].items = { CROP }
GS:SaveSet("Riding", { [14] = GS.ItemString(CROP) }, { mount = true })
mounted = true
Event("UNIT_AURA", "target")
check("someone else's auras: ignored", not GS.job)
Event("UNIT_AURA", "player")
Run()
check("mounted: the crop goes on", inv[14] == CROP)
mounted = false
Event("UNIT_AURA", "player")
Run()
check("dismounted: your trinket's back", inv[14] == TRINK_B)
GS:SaveSet("PvP", { [13] = GS.ItemString(TRINK_A2) }, { pvp = true })
zone = "pvp"
Event("ZONE_CHANGED_NEW_AREA")
Run()
check("battleground: PvP set", inv[13] == TRINK_A2)
zone = "none"
Event("ZONE_CHANGED_NEW_AREA")
Run()
check("left: back", inv[13] == TRINK_A1)

-- ---- Character sheet ----
local doll = W.NewFrame("PaperDollFrame")
env.PaperDollFrame = doll
for _, n in ipairs({ "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Finger0",
    "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard" }) do
    env["Character" .. n .. "Slot"] = W.NewFrame("Character" .. n .. "Slot", doll)
end
doll:Hide()
GS:HookDoll()
GS.Char().current = "DPS"
doll:Show()
local badge = env.WM_GearSetsWarning
check("character sheet: warning", badge and badge:IsShown() and badge.text:GetText():find("1 set item missing", 1, true))
check("the set's slot marked", GS.dollMissing[1].slot == 19)
local tip = {}
env.GameTooltip.AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. " " .. b end
badge._scripts.OnEnter(badge)
check("warning tooltip lists it", (tip[1] or ""):find("^DPS: ") and tip[1]:find("Green Trophy Tabard", 1, true) and tip[1]:find("missing", 1, true))
GS.Char().sets.DPS.items[19] = nil
GS:UpdateDoll()
check("nothing missing: no warning", not badge:IsShown())
GS.Char().sets.DPS.items[19] = GS.ItemString(TABARD)
GS.DB().dollWarning = false
GS:UpdateDoll()
check("warning can be turned off", not badge:IsShown())
GS.DB().dollWarning = true
GS.Char().sets.DPS.items[19] = nil

-- Slot menu: hover a character sheet slot for what else fits
local slotFrame = env.CharacterTrinket1Slot
alt = false
slotFrame:_fire("OnEnter")
local q = env.WM_GearSetsQuick
check("hover a trinket slot: the trinkets in your bags", q and q:IsShown() and q.buttons[1]:IsShown()
    and type(q.buttons[1].choice) == "table")
local inMenu = {}
for _, b in ipairs(q.buttons) do if b:IsShown() then inMenu[b.choice.str] = true end end
check("... only ones you're not wearing", inMenu[GS.ItemString(CROP)] and not inMenu[GS.ItemString(inv[13])]
    and not inMenu[GS.ItemString(inv[14])])
check("... no set-editor buttons here", not inMenu["off"] and not inMenu["none"])
local pick
for _, b in ipairs(q.buttons) do if b:IsShown() and b.choice.str == GS.ItemString(CROP) then pick = b end end
pick._scripts.OnClick(pick)
Run()
check("click one: it goes on", inv[14] == CROP and not q:IsShown())
GS:Equip({ [14] = GS.ItemString(TRINK_B) }, "x", true)
Run()
-- Leaving the slot and the menu closes it
slotFrame:_fire("OnEnter")
env.MouseIsOver = function() return false end
q._scripts.OnUpdate(q, 0.3)
check("mouse gone: the menu closes", not q:IsShown())
-- Alt only, or never
GS.DB().slotMenu = "alt"
slotFrame:_fire("OnEnter")
check("Alt mode: plain hover does nothing", not q:IsShown())
alt = true
slotFrame:_fire("OnEnter")
check("Alt mode: Alt-hover shows it", q:IsShown())
q:Hide()
GS.DB().slotMenu = "off"
slotFrame:_fire("OnEnter")
check("off: never", not q:IsShown())
alt = false
GS.DB().slotMenu = "hover"
check("an old 'quick menu off' setting carries over", (function()
    local saved = env.WMGearSetsDB.slotMenu
    env.WMGearSetsDB.slotMenu, env.WMGearSetsDB.quickMenu = nil, false
    local mode = GS.DB().slotMenu
    env.WMGearSetsDB.slotMenu, env.WMGearSetsDB.quickMenu = saved, nil
    return mode == "off"
end)())

-- ---- Window ----
GS:Toggle()
local p = env.WM_GearSetsFrame
local function RowFor(name) for _, r in ipairs(p.setRows) do if not r.hidden and r.frame.set and r.frame.set.name == name then return r end end end
check("window lists the sets", p:IsShown() and RowFor("Tank") and RowFor("DPS") and RowFor("Riding") and p.emptyRow.hidden)
check("sorted", p.setRows[1].frame.set.name == "DPS" and p.setRows[4].frame.set.name == "Tank")
check("status: wearing", RowFor("Tank").frame.status:GetText():find("wearing", 1, true) ~= nil)
check("badges", RowFor("DPS").frame.status:GetText():find("spec 2", 1, true) and RowFor("Riding").frame.status:GetText():find("mounted", 1, true))
RowFor("DPS").frame.equip._scripts.OnClick(RowFor("DPS").frame.equip)
Run()
check("Equip button", inv[16] == AXE)
RowFor("DPS").frame.edit._scripts.OnClick(RowFor("DPS").frame.edit)
local e = env.WM_GearSetEditor
check("Edit opens the editor on it", e:IsShown() and e.draft.oldName == "DPS" and e.draft.spec == 2)
e.draft.name = "Fury"
GS:SaveDraft()
check("rename", GS.Char().sets.Fury and not GS.Char().sets.DPS and GS.Char().current == "Fury")
RowFor("PvP").frame.del._scripts.OnClick(RowFor("PvP").frame.del)
check("delete", GS.Char().sets.PvP == nil and not RowFor("PvP"))
-- Editor slot boxes
GS:OpenEditor(GS.Char().sets.Riding)
local box = e.slotBoxes[13]
W.click(box)
check("tick a slot: takes what you wear there", e.draft.items[13] == GS.ItemString(inv[13]))
W.click(box)
check("untick: not part of the set", e.draft.items[13] == nil)
local spinfo = e.slotBoxes[14].Text:GetText()
check("slot label", spinfo:find("Trinket 2", 1, true) and spinfo:find("Riding Crop", 1, true))
-- The dressing room
local room = env.WM_GearSetDressingRoom
local model = env.WM_GearSetModel
local tried, undressed, unitSet = {}, {}, 0
model.SetUnit = function() unitSet = unitSet + 1; tried, undressed = {}, {} end
model.TryOn = function(_, link) tried[#tried + 1] = link end
model.UndressSlot = function(_, slot) undressed[slot] = true end
e.draft.items[17] = false
e:Refresh()
check("dressing room: a button for every slot", (function()
    for slot = 1, 19 do if not room.slots[slot] then return false end end
    return true
end)())
check("dressing room: the set's item in its slot", room.slots[14].state == "item")
check("dressing room: take-it-off slot", room.slots[17].state == "off" and room.slots[17].mark:GetText():find("off", 1, true))
check("dressing room: slots not in the set are faded", room.slots[1].state == "none" and room.slots[1]._alpha < 1)
check("dressing room: the model wears the set", unitSet > 0 and tried[1] == "item:" .. GS.ItemString(CROP) and undressed[17])
-- Click a slot: the picker, with what you wear, your bags, take-off and not-in-set
local sb = room.slots[13]
sb._scripts.OnClick(sb, "LeftButton")
local pq = env.WM_GearSetsQuick
local kinds, worn, bagged = {}, false, false
for _, b in ipairs(pq.buttons) do
    if b:IsShown() then
        if type(b.choice) == "table" then
            if b.choice.inv then worn = true else bagged = true end
        else kinds[b.choice] = true end
    end
end
check("dressing room picker: worn and bag items that fit, and the two extras", worn and bagged and kinds.off and kinds.none)
local bagPick
for _, b in ipairs(pq.buttons) do
    if b:IsShown() and type(b.choice) == "table" and not b.choice.inv then bagPick = b end
end
bagPick._scripts.OnClick(bagPick)
check("dressing room: picking puts it in the set", e.draft.items[13] == bagPick.choice.str and room.slots[13].state == "item")
check("... without equipping anything", inv[13] ~= nil and GS.ItemString(inv[13]) ~= bagPick.choice.str)
sb._scripts.OnClick(sb, "LeftButton")
for _, b in ipairs(pq.buttons) do if b:IsShown() and b.choice == "off" then b._scripts.OnClick(b) break end end
check("dressing room: take it off", e.draft.items[13] == false)
sb._scripts.OnClick(sb, "RightButton")
check("dressing room: right-click leaves it out", e.draft.items[13] == nil and room.slots[13].state == "none")
e:Hide()

-- ---- Commands and status ----
GS:Command("equip tank")
Run()
check("macro: equip by name, any case", inv[16] == SWORD)
W.printed = {}
GS:Command("equip nope")
check("unknown set", Said("No set called") ~= nil)
GS:Command("list")
check("list", Said("Your sets: Fury, Riding, Tank") ~= nil)
check("status", GS:GetQuickStatus():find("3 sets", 1, true) and GS:GetQuickStatus():find("Tank", 1, true))

-- Save a set again with extra options, keeping the rest
local function Resave(name, extra)
    local s = GS.Char().sets[name]
    local opts = { spec = s.spec, specAuto = s.specAuto, mount = s.mount, pvp = s.pvp, form = s.form, key = s.key, bis = s.bis }
    for k, v in pairs(extra) do opts[k] = v end
    if extra.form == false then opts.form = nil end
    return GS:SaveSet(name, s.items, opts)
end

-- ---- Key bindings ----
local xml = io.open(REPO .. "/Bindings.xml"):read("*a")
local allNamed = true
for name in xml:gmatch('<Binding name="([^"]+)"') do
    if name:find("^WM_GEARSET") and not env["BINDING_NAME_" .. name] then allNamed = false end
end
check("Bindings.xml: ten set keys, undo and the totem button", xml:find('"WM_GEARSET_10"', 1, true)
    and xml:find('"WM_GEARSET_UNDO"', 1, true) and xml:find('"CLICK WM_TotemAnchor:LeftButton"', 1, true)
    and xml:find('header="WATCHINGMACHINE"', 1, true))
check("key binding heading named", env.BINDING_HEADER_WATCHINGMACHINE == "Watching Machine")
check("every set key has a name", allNamed and env.BINDING_NAME_WM_GEARSET_UNDO ~= nil)
check("unused key named by number", env.BINDING_NAME_WM_GEARSET_1 == "Gear set 1")
Resave("Tank", { key = 1 })
check("set takes a key number; key named after it", GS.Char().sets.Tank.key == 1
    and env.BINDING_NAME_WM_GEARSET_1 == "Gear set 1: Tank" and GS:SetForKey(1).name == "Tank")
Resave("Fury", { key = 1 })
check("a key number belongs to one set", GS.Char().sets.Tank.key == nil and GS:SetForKey(1).name == "Fury"
    and env.BINDING_NAME_WM_GEARSET_1 == "Gear set 1: Fury")
Resave("Tank", { key = 2 })
env.GetBindingKey = function(b) if b == "WM_GEARSET_2" then return "F5" end end
check("badge shows the bound key", GS.Badges(GS.Char().sets.Tank):find("key F5", 1, true) ~= nil)
check("badge shows the number when no key is bound", GS.Badges(GS.Char().sets.Fury):find("key 1", 1, true) ~= nil)
GS.job = nil
GS.Char().undo = nil
env.WM_GearSetKey(2)
check("pressing the key equips its set", GS.Char().undo and GS.Char().undo.name == "what you wore before Tank")
Run()
W.printed = {}
env.WM_GearSetKey(7)
check("an unused key says so", Said("No set uses Gear set 7") ~= nil)
env.WM_GearSetKey("undo")
check("the undo key undoes", GS.Char().undo == nil)
Run()
local dd = GS:OpenEditor(GS.Char().sets.Tank)
check("editor keeps the key", dd.draft.key == 2)
dd:Hide()
GS:DeleteSet("Fury")
check("deleting a set frees its key name", env.BINDING_NAME_WM_GEARSET_1 == "Gear set 1")

-- ---- Forms and stances ----
local formIndex = 0
local FORM_SPELLS = { 9634, 768, 783 }
local FORM_NAMES = { [9634] = "Dire Bear Form", [768] = "Cat Form", [783] = "Travel Form" }
env.GetNumShapeshiftForms = function() return 3 end
env.GetShapeshiftFormInfo = function(i) return "icon", i == formIndex, true, FORM_SPELLS[i] end
env.GetSpellInfo = function(id) return FORM_NAMES[id] end
env.GetShapeshiftForm = function() return formIndex end
check("forms read from the stance bar", table.concat(GS.Forms(), ",") == "Dire Bear Form,Cat Form,Travel Form")
check("caster form is no form", GS.CurrentForm() == nil)
-- Older clients give the name second
env.GetShapeshiftFormInfo = function(i) return "icon", FORM_NAMES[FORM_SPELLS[i]], i == formIndex, true end
check("forms on older clients too", GS.Forms()[2] == "Cat Form")
GS:EquipSet("Tank"); Run()
local casterHelm = inv[1]
GS:SaveSet("Bear", { [1] = GS.ItemString(HELM_D) }, { form = "Dire Bear Form" })
check("form saved on the set; badge", GS.Char().sets.Bear.form == "Dire Bear Form"
    and GS.Badges(GS.Char().sets.Bear):find("Dire Bear Form", 1, true) ~= nil)
GS.ready = true
GS.state.form = nil
formIndex = 1
GS.job = nil
Event("UPDATE_SHAPESHIFT_FORM")
check("bear form: its set goes on", GS.job and GS.job.setName == "Bear")
Run()
check("... and is on", GS.ItemString(inv[1]) == GS.ItemString(HELM_D))
GS.job = nil
Event("UPDATE_SHAPESHIFT_FORM")
check("the same form again: nothing", GS.job == nil)
formIndex = 2
Event("UPDATE_SHAPESHIFT_FORM")
check("a form with no set: what you wore before goes back", GS.job ~= nil)
Run()
check("... your caster helm", inv[1] == casterHelm and GS.Char().revert.form == nil)
formIndex = 0
GS.job = nil
Event("UPDATE_SHAPESHIFT_FORM")
check("back to caster with nothing to put back: nothing", GS.job == nil)
GS.DB().auto = false
formIndex = 1
Event("UPDATE_SHAPESHIFT_FORM")
check("automatic swaps off: no form swap", GS.job == nil)
GS.DB().auto = true
formIndex = 0
Event("UPDATE_SHAPESHIFT_FORM")
GS.ready = false
formIndex = 1
Event("UPDATE_SHAPESHIFT_FORM")
check("at login (not ready): the form is noted, no swap", GS.job == nil and GS.state.form == "Dire Bear Form")
GS.ready = true
formIndex = 0
Event("UPDATE_SHAPESHIFT_FORM")
GS.job = nil
local fe = GS:OpenEditor(GS.Char().sets.Bear)
check("editor keeps the form", fe.draft.form == "Dire Bear Form")
fe:Hide()

-- ---- A set's GearScore and missing BiS ----
check("no GearScore without the module", GS:SetScore(GS.Char().sets.Tank) == nil and GS.Extras(GS.Char().sets.Tank) == "")
local scored
WM.modules.GearScore = {
    GearScoreFor = function(links) scored = links; local n = 0; for _ in pairs(links) do n = n + 1 end; return n * 100, 115.5, true end,
    ColorText = function(_, t) return "<" .. t .. ">" end,
}
local tank = GS.Char().sets.Tank
local score = GS:SetScore(tank)
check("set's GearScore from its items", score ~= nil and scored[1] and scored[1]:find("29011", 1, true)
    and scored[16] ~= nil)
check("GearScore text coloured by the module", GS:ScoreText(tank) == "<GS " .. score .. ">")
check("no BiS compare without a BiS spec", GS:MissingBiS(tank) == nil)
local BIS = { Protection = { [29011] = 1, [29021] = 1, [29279] = 1, [28757] = 1, [28825] = 1 } }
WM.modules.LootBrowser = {
    MySpecs = function() return { "Arms", "Fury", "Protection" } end,
    BiSItems = function(_, spec) return BIS[spec] or {} end,
}
check("BiS specs from the Loot Browser", table.concat(GS.BiSSpecs(), ",") == "Arms,Fury,Protection")
Resave("Tank", { bis = "Protection" })
tank = GS.Char().sets.Tank
local missing, short = GS:MissingBiS(tank)
local missIds = {}
for _, m in ipairs(missing or {}) do missIds[m.id] = m.slot end
-- Tank has the BiS helm (another BiS helm doesn't count), one BiS ring of two, the BiS shield
check("missing BiS: the second ring only", short == 1 and missIds[28757] == 11 and missIds[29021] == nil
    and missIds[29279] == nil and missIds[28825] == nil)
check("list shows score and BiS", GS.Extras(tank):find("<GS", 1, true) and GS.Extras(tank):find("1 BiS missing", 1, true))
BIS.Protection[28757] = nil
check("all BiS: nothing missing", select(2, GS:MissingBiS(tank)) == 0 and not GS.Extras(tank):find("BiS", 1, true))
BIS.Protection[99999] = 1
LOC[99999] = "INVTYPE_BODY"   -- a shirt: the set leaves that slot alone
check("BiS for a slot the set doesn't cover: not counted", select(2, GS:MissingBiS(tank)) == 0)
local be = GS:OpenEditor(tank)
check("editor keeps the BiS spec", be.draft.bis == "Protection")
be:Hide()
WM.modules.GearScore, WM.modules.LootBrowser = nil, nil
check("modules gone: nothing shown", GS.Extras(tank) == "" and GS:MissingBiS(tank) == nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
