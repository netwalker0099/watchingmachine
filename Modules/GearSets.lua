-- Watching Machine: Gear Sets
-- Save what you're wearing as a named set and put it back on in one click,
-- from a macro (/wmachine gear equip <name>), or automatically: when you
-- switch talent spec, while mounted, or in battlegrounds and arenas.
--
-- Built to be reliable rather than clever:
--   * Items are matched exactly (enchant, gems, random suffix, and which
--     copy it is), so two identical trinkets or a re-gemmed piece still
--     find the right item.
--   * Every step re-reads your bags and slots first and only touches items
--     that aren't locked, so a slow server, a busy cursor or another addon
--     moving things can't send it off on stale positions.
--   * Swaps happen in place (the old piece goes where the new one was), so
--     most sets need no free bag space at all.
--   * In combat the weapons change at once and the rest waits for combat
--     to end; it also waits out casts and death.
--   * When it's done it checks the result and tells you what's missing
--     (and whether it's in your bank) or what couldn't be equipped.
-- Opening the character sheet warns you if a set's item is missing.

local AddonName, WM = ...
local GS = {}
WM:RegisterModule("GearSets", GS)
WM.GearSets = GS

GS.version = "3.45"

local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Finger 1", "Finger 2", "Trinket 1", "Trinket 2", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }
local SLOT_FRAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard" }
GS.SLOT_NAMES = SLOT_NAMES
local WEAPON = { [16] = true, [17] = true, [18] = true }
-- Weapons first (a two-hander before the off hand), then the rest
local ORDER = { 16, 17, 18, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 4, 19 }
-- Where each kind of item can go
local FITS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
GS.FITS = FITS

local TIMEOUT = 8            -- seconds of trying before giving up on a slot
local MAX_TRIES = 4          -- moves sent for one slot before calling it failed
local TICK = 0.1

local DEFAULTS = {
    auto = true,             -- automatic swaps (spec, mount, battlegrounds)
    reportDone = true,       -- "Equipped Tank." in chat
    reportMissing = true,    -- chat alert when a set's item is missing
    dollWarning = true,      -- warning on the character sheet
    quickMenu = true,        -- Alt over a character sheet slot: what fits it
}

local function DB()
    WMGearSetsDB = WMGearSetsDB or {}
    local db = WMGearSetsDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.chars) ~= "table" then db.chars = {} end
    return db
end
GS.DB = DB

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- This character's sets and state
local function Char()
    local db = DB()
    local key = CharKey()
    local c = db.chars[key]
    if type(c) ~= "table" then c = {}; db.chars[key] = c end
    if type(c.sets) ~= "table" then c.sets = {} end
    if type(c.revert) ~= "table" then c.revert = {} end
    return c
end
GS.Char = Char

local function Say(msg) WM:ModulePrint("GearSets", msg) end
local function On() return WM:IsModuleOn("GearSets") end

-- ============================================
-- ITEMS
-- ============================================

-- "id:enchant:gem1:gem2:gem3:gem4:suffix:unique" from a link
local function ItemString(link)
    if type(link) ~= "string" then return nil end
    local s = link:match("item:([%-%d:]+)")
    if not s then return nil end
    local parts = {}
    for p in (s .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = p end
    for i = 1, 8 do parts[i] = (parts[i] and parts[i] ~= "") and parts[i] or "0" end
    return table.concat(parts, ":", 1, 8)
end
GS.ItemString = ItemString

local function Split(str)
    local t = {}
    for p in (tostring(str) .. ":"):gmatch("([^:]*):") do t[#t + 1] = p end
    return t
end

-- How well an item matches what a set wants: 3 the very same item, 2 same
-- item with the same enchant and gems, 1 same item (enchant or gems
-- changed since), 0 not it
local function Match(want, have)
    if not want or not have then return 0 end
    if want == have then return 3 end
    local a, b = Split(want), Split(have)
    if a[1] ~= b[1] or a[7] ~= b[7] then return 0 end
    for i = 2, 6 do if a[i] ~= b[i] then return 1 end end
    return 2
end
GS.Match = Match

local function ItemID(str) return tonumber(tostring(str):match("^(%-?%d+)")) end

-- Links seen this session, by item string (names show even before the
-- game has the item cached)
local knownLinks = {}

local function LinkFor(str)
    local id = ItemID(str)
    if not id then return "?" end
    if knownLinks[str] then return knownLinks[str] end
    for _, c in pairs(DB().chars) do
        for _, set in pairs(type(c.sets) == "table" and c.sets or {}) do
            for slot, v in pairs(set.items or {}) do
                if v == str and set.links and set.links[slot] then return set.links[slot] end
            end
        end
    end
    local name, link
    if GetItemInfo then name, link = GetItemInfo("item:" .. str) end
    if type(link) == "string" then return link end
    if type(name) == "string" then return "[" .. name .. "]" end
    return "item " .. id
end
GS.LinkFor = LinkFor

local function EquipLoc(link)
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
        if ok and type(loc) == "string" and loc ~= "" then return loc end
    end
    if GetItemInfoInstant then
        local ok, _, _, _, loc = pcall(GetItemInfoInstant, link)
        if ok and type(loc) == "string" and loc ~= "" then return loc end
    end
    if GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, loc = pcall(GetItemInfo, link)
        if ok and type(loc) == "string" then return loc end
    end
end
GS.EquipLoc = EquipLoc

-- ============================================
-- WHERE EVERYTHING IS
-- ============================================

local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return tonumber(C_Container.GetContainerNumSlots(bag)) or 0 end
    return GetContainerNumSlots and tonumber(GetContainerNumSlots(bag)) or 0
end

local function BagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then return info.hyperlink, info.isLocked end
        return nil
    end
    if GetContainerItemInfo then
        local ok, _, _, locked, _, _, _, link = pcall(GetContainerItemInfo, bag, slot)
        if ok then return link, locked end
    end
end

-- Bag family: 0 is an ordinary bag (quivers, soul and herb bags can't take gear)
local function Family(bag)
    if bag == 0 then return 0 end
    local f = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not f then return 0 end
    local ok, _, family = pcall(f, bag)
    return ok and (tonumber(family) or 0) or 0
end

local function Bags()
    local out = {}
    for b = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do out[#out + 1] = b end
    if GS.bankOpen then
        out[#out + 1] = rawget(_G, "BANK_CONTAINER") or -1
        local first = (rawget(_G, "NUM_BAG_SLOTS") or 4) + 1
        for b = first, first + (rawget(_G, "NUM_BANKBAGSLOTS") or 7) - 1 do out[#out + 1] = b end
    end
    return out
end

-- Everything you're wearing and carrying (and the bank, while it's open):
-- { inv = { [slot] = loc }, all = { loc, ... }, free = { { bag, slot }, ... } }
-- loc = { inv = slot } or { bag =, slot = }, plus str, link, locked
function GS.Scan()
    local s = { inv = {}, all = {}, free = {} }
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        local str = ItemString(link)
        if str then
            knownLinks[str] = link
            local loc = { inv = slot, str = str, link = link,
                locked = IsInventoryItemLocked and IsInventoryItemLocked(slot) and true or false }
            s.inv[slot] = loc
            s.all[#s.all + 1] = loc
        end
    end
    local bankBag = rawget(_G, "BANK_CONTAINER") or -1
    for _, bag in ipairs(Bags()) do
        local normal = Family(bag) == 0
        for slot = 1, NumSlots(bag) do
            local link, locked = BagItem(bag, slot)
            local str = ItemString(link)
            if str then
                knownLinks[str] = link
                s.all[#s.all + 1] = { bag = bag, slot = slot, str = str, link = link, locked = locked and true or false,
                    bank = bag == bankBag or bag > (rawget(_G, "NUM_BAG_SLOTS") or 4) }
            elseif normal and not link and bag >= 0 and bag <= (rawget(_G, "NUM_BAG_SLOTS") or 4) then
                s.free[#s.free + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return s
end

-- What it takes to wear a set's items:
-- { moves = { [slot] = loc }, empty = { [slot] = true }, missing = { [slot] = str } }
-- Each item is used once, best matches first; an item already in its
-- slot keeps it.
function GS.Plan(items, scan)
    scan = scan or GS.Scan()
    local cands = {}
    for slot, want in pairs(items) do
        if want then
            for _, loc in ipairs(scan.all) do
                local m = Match(want, loc.str)
                if m > 0 then
                    cands[#cands + 1] = { slot = slot, loc = loc, score = m + (loc.inv == slot and 0.5 or 0) }
                end
            end
        end
    end
    table.sort(cands, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.slot < b.slot
    end)
    local got, used = {}, {}
    for _, c in ipairs(cands) do
        if not got[c.slot] and not used[c.loc] then
            got[c.slot], used[c.loc] = c.loc, true
        end
    end
    local plan = { moves = {}, empty = {}, missing = {}, n = 0 }
    for slot, want in pairs(items) do
        if want == false then
            if scan.inv[slot] then plan.empty[slot] = true; plan.n = plan.n + 1 end
        elseif got[slot] then
            if got[slot].inv ~= slot then plan.moves[slot] = got[slot]; plan.n = plan.n + 1 end
        else
            plan.missing[slot] = want
        end
    end
    return plan
end

-- Is this set on you right now?
function GS:IsWearing(set)
    local plan = GS.Plan(set.items)
    return plan.n == 0 and next(plan.missing) == nil
end

-- Is a missing item in your bank (from Your Characters' last bank visit)?
-- Only known while Your Characters is on.
local function InBank(str)
    if not WM:IsModuleOn("AltTracker") then return false end
    local alts = WM.modules.AltTracker
    local c = alts and alts.DB and alts.DB().chars and alts.DB().chars[CharKey()]
    local id = ItemID(str)
    if not (c and type(c.bank) == "table" and id) then return false end
    for _, e in ipairs(c.bank) do
        if type(e) == "table" and tonumber(tostring(e[1]):match("item:(%d+)")) == id then return true end
    end
    return false
end
GS.InBank = InBank

-- ============================================
-- SWAPPING
-- ============================================

GS.job = nil

local function Busy()
    if CursorHasItem and CursorHasItem() then return "Something is on your cursor." end
    if SpellIsTargeting and SpellIsTargeting() then return "You're targeting a spell." end
    if UnitCastingInfo and UnitCastingInfo("player") then return "casting" end
    if UnitChannelInfo and UnitChannelInfo("player") then return "casting" end
end
local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end
local function Dead() return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false end

local function Pick(loc)
    if loc.inv then PickupInventoryItem(loc.inv) else C_Container.PickupContainerItem(loc.bag, loc.slot) end
end
local function Clear()
    if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
end
local function Key(loc) return loc.inv and ("i" .. loc.inv) or (loc.bag .. ":" .. loc.slot) end

-- Start putting on items ({ [slot] = item string, or false to take it
-- off }). Replaces a swap already running.
function GS:Equip(items, name, quiet)
    local job = { items = {}, name = name or "set", quiet = quiet, tries = {}, failed = {}, why = {}, spent = 0,
        changed = false }
    for slot, v in pairs(items) do job.items[slot] = v end
    self.job = job
    self:Tick(0)
    return job
end

-- One step of the running swap. dt: seconds since the last step.
function GS:Tick(dt)
    local job = self.job
    if not job then return end
    if Dead() then job.waiting = "dead"; return end
    local busy = Busy()
    if busy == "casting" then job.waiting = "casting"; return end
    job.spent = job.spent + (dt or 0)
    if busy then
        if job.spent >= TIMEOUT then return self:Finish(busy) end
        job.waiting = "cursor"
        return
    end
    local combat = InCombat()
    local scan = GS.Scan()
    local plan = GS.Plan(job.items, scan)
    job.plan = plan
    local touched, free, freeAt = {}, scan.free, 1
    local acted, pending, deferred = false, false, 0
    local function Take(slot)
        -- Take a slot off into a free ordinary bag slot
        local spot = free[freeAt]
        if not spot then job.failed[slot] = "your bags are full"; return end
        freeAt = freeAt + 1
        PickupInventoryItem(slot)
        C_Container.PickupContainerItem(spot.bag, spot.slot)
        if CursorHasItem and CursorHasItem() then Clear(); job.why[slot] = "it couldn't go in your bags" end
        touched["i" .. slot] = true
        acted = true
    end
    for _, slot in ipairs(ORDER) do
        local loc = plan.moves[slot]
        local wantsOff = plan.empty[slot]
        if (loc or wantsOff) and not job.failed[slot] then
            pending = true
            if combat and not WEAPON[slot] then
                deferred = deferred + 1
            elseif (job.tries[slot] or 0) >= MAX_TRIES then
                job.failed[slot] = job.why[slot] or "the game wouldn't equip it"
            elseif slot == 17 and touched.i16 then
                -- The off hand waits for the main hand to settle (a two-hander going off)
            elseif not (scan.inv[slot] and scan.inv[slot].locked) and not touched["i" .. slot]
                and not (loc and (loc.locked or touched[Key(loc)])) then
                job.tries[slot] = (job.tries[slot] or 0) + 1
                job.changed = true
                if wantsOff then
                    Take(slot)
                else
                    -- A two-hander can't go on over an off hand: take that off first
                    local blocked = false
                    if slot == 16 and EquipLoc(loc.link) == "INVTYPE_2HWEAPON" and scan.inv[17] and not job.items[17] then
                        if touched.i17 or scan.inv[17].locked then
                            blocked = true
                        else
                            Take(17)
                            if job.failed[17] then
                                job.failed[16], job.failed[17] = "no room in your bags for the off hand", nil
                                blocked = true
                            end
                        end
                    end
                    if not blocked then
                        Pick(loc)
                        PickupInventoryItem(slot)
                        if CursorHasItem and CursorHasItem() then
                            -- Refused (maybe only for now): try again next step
                            Clear()
                            job.why[slot] = "the game wouldn't equip it"
                        end
                        touched[Key(loc)], touched["i" .. slot] = true, true
                        acted = true
                    end
                end
            end
        end
    end
    if deferred > 0 and not acted then
        -- Only armour left, and you're in combat
        if job.waiting ~= "combat" and not job.quiet then
            Say(string.format("%s: %d item%s will go on when combat ends.", job.name, deferred, deferred == 1 and "" or "s"))
        end
        job.waiting = "combat"
        return
    end
    job.waiting = nil
    if not pending then return self:Finish() end
    if job.spent >= TIMEOUT then
        for slot in pairs(plan.moves) do job.failed[slot] = job.failed[slot] or "it timed out" end
        for slot in pairs(plan.empty) do job.failed[slot] = job.failed[slot] or "it timed out" end
        return self:Finish()
    end
end

-- The swap is over: check the result and say how it went
function GS:Finish(reason)
    local job = self.job
    if not job then return end
    self.job = nil
    local plan = GS.Plan(job.items)
    local db = DB()
    local missing, bank = {}, {}
    for _, slot in ipairs(ORDER) do
        local str = plan.missing[slot]
        if str then
            if InBank(str) then bank[#bank + 1] = LinkFor(str) else missing[#missing + 1] = LinkFor(str) end
        end
    end
    local failed = {}
    for _, slot in ipairs(ORDER) do
        if (plan.moves[slot] or plan.empty[slot]) then
            local what = plan.moves[slot] and (plan.moves[slot].link or LinkFor(plan.moves[slot].str)) or SLOT_NAMES[slot]
            failed[#failed + 1] = what .. " (" .. (job.failed[slot] or reason or "it didn't move") .. ")"
        end
    end
    job.result = { missing = missing, bank = bank, failed = failed }
    if job.setName then Char().current = job.setName end
    if db.reportMissing and (#missing > 0 or #bank > 0) then
        local parts = {}
        if #missing > 0 then parts[#parts + 1] = table.concat(missing, ", ") end
        if #bank > 0 then parts[#parts + 1] = table.concat(bank, ", ") .. " |cFFFFCC00(in your bank)|r" end
        Say("|cFFFF4444Missing from " .. job.name .. ":|r " .. table.concat(parts, ", "))
    end
    if #failed > 0 then
        Say("|cFFFF8800Couldn't finish " .. job.name .. ":|r " .. table.concat(failed, "; "))
    elseif db.reportDone and not job.quiet and #missing == 0 and #bank == 0 then
        Say(job.changed and ("Equipped " .. job.name .. ".") or ("You're already wearing " .. job.name .. "."))
    end
    self.lastResult = job.result
    self:RefreshUI()
    self:UpdateDoll()
    if self.onFinish then self.onFinish(job) end
    return job.result
end

-- What you're wearing in these slots now (for putting it back later)
local function Snapshot(slots)
    local out = {}
    for slot in pairs(slots) do
        out[slot] = ItemString(GetInventoryItemLink("player", slot)) or false
    end
    return out
end
GS.Snapshot = Snapshot

-- Put on a saved set by name
function GS:EquipSet(name, why, quiet)
    local set = Char().sets[name]
    if not set then Say("No set called \"" .. tostring(name) .. "\"."); return end
    if why ~= "revert" then Char().undo = { name = "what you wore before " .. name, items = Snapshot(set.items) } end
    local job = self:Equip(set.items, name, quiet)
    job.setName = name
    return job
end

function GS:Undo()
    local u = Char().undo
    if not u then Say("Nothing to undo."); return end
    Char().undo = nil
    return self:Equip(u.items, u.name)
end

-- ============================================
-- SETS
-- ============================================

function GS:SetNames()
    local names = {}
    for name in pairs(Char().sets) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local DEFAULT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
GS.DEFAULT_SLOTS = DEFAULT_SLOTS

-- Save (or replace) a set. items: { [slot] = item string | false }
function GS:SaveSet(name, items, opts)
    name = strtrim(tostring(name or ""))
    if name == "" then return nil, "Give the set a name." end
    if not next(items) then return nil, "Tick at least one slot." end
    local sets = Char().sets
    opts = opts or {}
    if opts.oldName and opts.oldName ~= name and sets[name] then return nil, "There's already a set called " .. name .. "." end
    if opts.oldName and opts.oldName ~= name then
        sets[opts.oldName] = nil
        if Char().current == opts.oldName then Char().current = name end
    end
    local set = { name = name, items = {}, spec = opts.spec, specAuto = opts.specAuto and true or false,
        mount = opts.mount and true or false, pvp = opts.pvp and true or false }
    set.links = {}
    for slot, v in pairs(items) do
        set.items[slot] = v
        if v and knownLinks[v] then set.links[slot] = knownLinks[v] end
    end
    set.icon = opts.icon or GS.IconFor(set)
    sets[name] = set
    self:RefreshUI()
    return set
end

function GS:DeleteSet(name)
    local c = Char()
    c.sets[name] = nil
    if c.current == name then c.current = nil end
    self:RefreshUI()
    self:UpdateDoll()
end

-- The set's icon: its main hand, else chest, else head, else anything
function GS.IconFor(set)
    for _, slot in ipairs({ 16, 5, 1, 18, 3 }) do
        local str = set.items[slot]
        if str then
            local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ItemID(str)))
                or (GetItemIcon and GetItemIcon(ItemID(str)))
            if icon then return icon end
        end
    end
    return "Interface\\Icons\\INV_Chest_Chain_04"
end

-- ============================================
-- TALENT SPECS
-- ============================================

function GS.ActiveSpec()
    if GetActiveTalentGroup then
        local ok, g = pcall(GetActiveTalentGroup)
        if ok and tonumber(g) then return tonumber(g) end
    end
    return 1
end

function GS.NumSpecs()
    if GetNumTalentGroups then
        local ok, n = pcall(GetNumTalentGroups)
        if ok and tonumber(n) and tonumber(n) > 0 then return tonumber(n) end
    end
    return GetActiveTalentGroup and 2 or 1
end

-- "Spec 1: Protection (0/41/20)"
function GS.SpecName(group)
    local pts, best, bestPts = {}, nil, -1
    for tab = 1, 3 do
        local n, p = nil, 0
        if GetTalentTabInfo then
            local ok, a, b, c, _, e = pcall(GetTalentTabInfo, tab, false, false, group)
            if ok then
                -- Classic: name, icon, points; later clients: id, name, description, icon, points
                if type(a) == "string" then n, p = a, tonumber(c) or 0
                elseif type(b) == "string" then n, p = b, tonumber(e) or 0 end
            end
        end
        pts[tab] = p
        if n and p > bestPts then best, bestPts = n, p end
    end
    if best and bestPts > 0 then
        return string.format("Spec %d: %s (%d/%d/%d)", group, best, pts[1], pts[2], pts[3])
    end
    return "Spec " .. group
end

-- The set for a spec (the first, alphabetically, if more than one)
function GS:SetForSpec(group)
    for _, name in ipairs(self:SetNames()) do
        local set = Char().sets[name]
        if set.spec == group and set.specAuto then return set end
    end
end

-- Ready for spec swaps: from now on a change from this spec equips a set
function GS:Arm()
    self.ready = true
    Char().lastSpec = GS.ActiveSpec()
end

function GS:OnSpecChanged()
    if not On() then return end
    local spec = GS.ActiveSpec()
    local c = Char()
    -- Talent info isn't ready until you're in the world: note the spec, don't swap
    if not self.ready then c.lastSpec = spec; return end
    if c.lastSpec == spec then return end
    local was = c.lastSpec
    c.lastSpec = spec
    if was == nil or not DB().auto then return end
    local set = self:SetForSpec(spec)
    if set then
        Say("Switched to " .. GS.SpecName(spec) .. ": equipping " .. set.name .. ".")
        self:EquipSet(set.name, "spec", true)
    end
end

-- ============================================
-- MOUNTED, BATTLEGROUNDS
-- ============================================

local function Mounted() return IsMounted and IsMounted() and true or false end
local function InPvP()
    if not IsInInstance then return false end
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end
GS.TRIGGERS = { mount = { test = Mounted, label = "mounted" }, pvp = { test = InPvP, label = "in battlegrounds and arenas" } }

-- Equip a trigger's set when it starts; put back what you wore when it ends
function GS:CheckTrigger(key)
    local t = GS.TRIGGERS[key]
    local c = Char()
    local on = t.test()
    self.state = self.state or {}
    if self.state[key] == on then return end
    self.state[key] = on
    if not DB().auto then return end
    if on then
        for _, name in ipairs(self:SetNames()) do
            local set = c.sets[name]
            if set[key] then
                c.revert[key] = { items = Snapshot(set.items), name = name }
                self:EquipSet(name, key, true)
                return
            end
        end
    elseif c.revert[key] then
        local r = c.revert[key]
        c.revert[key] = nil
        local job = self:Equip(r.items, "your gear from before " .. r.name, true)
        return job
    end
end

-- ============================================
-- CHARACTER SHEET: missing items, quick swap
-- ============================================

-- Every set item you don't have on you: { { set =, slot =, str =, bank = }, ... }
function GS:MissingItems()
    local out = {}
    local scan = GS.Scan()
    for _, name in ipairs(self:SetNames()) do
        local plan = GS.Plan(Char().sets[name].items, scan)
        for _, slot in ipairs(ORDER) do
            local str = plan.missing[slot]
            if str then out[#out + 1] = { set = name, slot = slot, str = str, bank = InBank(str) } end
        end
    end
    return out
end

local badge
local slotMarks = {}

local function SlotFrame(slot) return rawget(_G, "Character" .. SLOT_FRAMES[slot] .. "Slot") end

function GS:CreateBadge()
    local doll = rawget(_G, "PaperDollFrame")
    if badge or type(doll) ~= "table" then return badge end
    badge = CreateFrame("Button", "WM_GearSetsWarning", doll)
    badge:SetSize(170, 18)
    badge:SetPoint("TOPLEFT", doll, "TOPLEFT", 72, -52)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetSize(16, 16)
    badge.icon:SetPoint("LEFT")
    badge.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge.text:SetPoint("LEFT", badge.icon, "RIGHT", 3, 0)
    badge:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Gear set items not on you")
        for _, m in ipairs(b.missing or {}) do
            GameTooltip:AddDoubleLine(m.set .. ": " .. LinkFor(m.str), m.bank and "|cFFFFCC00in your bank|r" or "|cFFFF4444missing|r")
        end
        GameTooltip:AddLine("Click for Gear Sets.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge:SetScript("OnClick", function() GS:Toggle() end)
    badge:Hide()
    return badge
end

-- Refresh the character sheet warning and the red marks on its slots
function GS:UpdateDoll()
    if not On() then return self:HideDoll() end
    local doll = rawget(_G, "PaperDollFrame")
    if type(doll) ~= "table" or not doll.IsVisible or not doll:IsVisible() then return end
    self:CreateBadge()
    local missing = DB().dollWarning and self:MissingItems() or {}
    local nMiss, nBank = 0, 0
    for _, m in ipairs(missing) do if m.bank then nBank = nBank + 1 else nMiss = nMiss + 1 end end
    if badge then
        badge.missing = missing
        if #missing == 0 then
            badge:Hide()
        else
            local parts = {}
            if nMiss > 0 then parts[#parts + 1] = string.format("|cFFFF4444%d set item%s missing|r", nMiss, nMiss == 1 and "" or "s") end
            if nBank > 0 then parts[#parts + 1] = string.format("|cFFFFCC00%d in your bank|r", nBank) end
            badge.text:SetText(table.concat(parts, ", "))
            badge:Show()
        end
    end
    -- Mark the slots of the set you last equipped
    local current = Char().current
    local marked = {}
    for _, m in ipairs(missing) do if m.set == current then marked[m.slot] = m end end
    for slot = 1, 19 do
        local f = SlotFrame(slot)
        if type(f) == "table" and f.CreateTexture then
            local mark = slotMarks[slot]
            if marked[slot] and not mark then
                mark = f:CreateTexture(nil, "OVERLAY")
                mark:SetAllPoints()
                mark:SetColorTexture(1, 0, 0, 0.35)
                slotMarks[slot] = mark
            end
            if mark then if marked[slot] then mark:Show() else mark:Hide() end end
        end
    end
    self.dollMissing = missing
end

-- Take the warning and the slot marks off the character sheet
function GS:HideDoll()
    if badge then badge:Hide() end
    for _, mark in pairs(slotMarks) do mark:Hide() end
    self.dollMissing = nil
end

-- Alt over a slot on the character sheet: what in your bags fits it
local quick
function GS:ItemsFor(slot)
    local out = {}
    for _, loc in ipairs(GS.Scan().all) do
        if not loc.inv then
            for _, s in ipairs(FITS[EquipLoc(loc.link) or ""] or {}) do
                if s == slot then out[#out + 1] = loc; break end
            end
        end
    end
    return out
end

function GS:ShowQuickMenu(slot, anchor)
    if not On() or not DB().quickMenu then return end
    local items = self:ItemsFor(slot)
    if #items == 0 then if quick then quick:Hide() end return end
    if not quick then
        quick = CreateFrame("Frame", "WM_GearSetsQuick", UIParent, "BackdropTemplate")
        quick:SetFrameStrata("DIALOG")
        if WM.SkinCard then WM:SkinCard(quick, { 0.8, 0.7, 0.4 }) end
        quick.buttons = {}
        quick:SetScript("OnLeave", function(f) if not (MouseIsOver and MouseIsOver(f)) then f:Hide() end end)
    end
    for i, loc in ipairs(items) do
        local b = quick.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, quick)
            b:SetSize(30, 30)
            b:SetPoint("LEFT", 4 + (i - 1) * 32, 0)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(btn.loc.link)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(btn)
                quick:Hide()
                GS:Equip({ [btn.slot] = btn.loc.str }, SLOT_NAMES[btn.slot], true)
            end)
            quick.buttons[i] = b
        end
        b.loc, b.slot = loc, slot
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ItemID(loc.str))) or (GetItemIcon and GetItemIcon(ItemID(loc.str)))
        b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b:Show()
    end
    for i = #items + 1, #quick.buttons do quick.buttons[i]:Hide() end
    quick:SetSize(8 + #items * 32, 38)
    quick:ClearAllPoints()
    quick:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
    quick:Show()
    return quick
end

function GS:HookDoll()
    if self.dollHooked then return end
    local doll = rawget(_G, "PaperDollFrame")
    if type(doll) ~= "table" or not doll.HookScript then return end
    self.dollHooked = true
    doll:HookScript("OnShow", function() GS:UpdateDoll() end)
    for slot = 1, 19 do
        local f = SlotFrame(slot)
        if type(f) == "table" and f.HookScript then
            f:HookScript("OnEnter", function(btn)
                if IsAltKeyDown and IsAltKeyDown() then GS:ShowQuickMenu(slot, btn) end
            end)
            f:HookScript("OnLeave", function()
                WM.RunAfter(0.4, function()
                    if quick and quick:IsShown() and not (MouseIsOver and MouseIsOver(quick)) then quick:Hide() end
                end)
            end)
        end
    end
end

-- ============================================
-- WINDOW
-- ============================================

local panel, editor
local MAX_ROWS = 30

local function Badges(set)
    local b = {}
    if set.spec then b[#b + 1] = (set.specAuto and "|cFF66CCFF" or "|cFF888888") .. "spec " .. set.spec .. "|r" end
    if set.mount then b[#b + 1] = "|cFF99E666mounted|r" end
    if set.pvp then b[#b + 1] = "|cFFFF6666PvP|r" end
    return table.concat(b, " ")
end

function GS:SetStatus(set, scan)
    local plan = GS.Plan(set.items, scan)
    local nMiss = 0
    for _ in pairs(plan.missing) do nMiss = nMiss + 1 end
    if nMiss > 0 then return string.format("|cFFFF4444%d missing|r", nMiss), plan end
    if plan.n == 0 then return "|cFF33FF33wearing|r", plan end
    return string.format("|cFFAAAAAA%d to change|r", plan.n), plan
end

local function NewSetRow(row)
    local f = row.frame
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(22, 22)
    f.icon:SetPoint("LEFT", 8, 0)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.name:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.name:SetWidth(150)
    f.name:SetJustifyH("LEFT")
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetPoint("LEFT", f.name, "RIGHT", 4, 0)
    local function Btn(text, w, x, fn)
        local b = WM.UI.Button(f, { text = text, width = w, onClick = function() fn(f.set) end })
        b:SetPoint("RIGHT", x, 0)
        return b
    end
    f.del = Btn("Delete", 56, -4, function(set)
        WM:Confirm("Delete the gear set " .. set.name .. "?", function() GS:DeleteSet(set.name) end)
    end)
    f.edit = Btn("Edit", 46, -64, function(set) GS:OpenEditor(set) end)
    f.equip = Btn("Equip", 54, -114, function(set) GS:EquipSet(set.name) end)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.set then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.set.name)
        local plan = self.plan
        for _, slot in ipairs(ORDER) do
            local v = self.set.items[slot]
            if v ~= nil then
                local right = v == false and "|cFF888888take off|r" or LinkFor(v)
                if plan and plan.missing[slot] then right = right .. (InBank(v) and " |cFFFFCC00(bank)|r" or " |cFFFF4444(missing)|r") end
                GameTooltip:AddDoubleLine(SLOT_NAMES[slot], right, 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

function GS:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({ name = "WM_GearSetsFrame", title = "Gear Sets", titleColor = "CCB366", width = 480,
        onRefresh = function(p) GS:FillRows(p) end })
    local L = panel.layout
    L:Note("Save what you're wearing as a set and put it back on in one click, from a macro (/wmachine gear equip <name>),"
        .. " or automatically when you switch spec, mount up or enter a battleground.")
    L:Checkbox({ label = "Automatic swaps (spec, mounted, battlegrounds)", get = function() return DB().auto end,
        set = function(v) DB().auto = v end,
        tooltip = { "Automatic swaps", "Off: sets only go on when you equip them yourself." } })
    L:Note(function() return "You're in " .. GS.SpecName(GS.ActiveSpec()) .. "." end)
    L:Buttons({
        { text = "New set", width = 100, onClick = function() GS:OpenEditor(nil) end },
        { text = "Undo last swap", width = 120, onClick = function() GS:Undo() end },
    })
    L:Section({ key = "sets", title = "Your sets" })
    panel.setRows = {}
    for i = 1, MAX_ROWS do
        local row = L:Row(28)
        NewSetRow(row)
        panel.setRows[i] = row
    end
    panel.emptyRow = L:Row(20)
    local empty = WM.UI.Text(panel.emptyRow.frame, { text = "|cFF888888No sets yet: put on your gear and click New set.|r", width = 420 })
    empty:SetPoint("LEFT", 12, 0)
    L:EndSection()
    L:Section({ key = "options", title = "Options", collapsed = true })
    L:Checkbox({ label = "Say in chat when a set is on", get = function() return DB().reportDone end, set = function(v) DB().reportDone = v end })
    L:Checkbox({ label = "Chat alert when a set's item is missing", get = function() return DB().reportMissing end,
        set = function(v) DB().reportMissing = v end })
    L:Checkbox({ label = "Warn on the character sheet about missing items", get = function() return DB().dollWarning end,
        set = function(v) DB().dollWarning = v; GS:UpdateDoll() end })
    L:Checkbox({ label = "Alt over a character sheet slot: what fits it", get = function() return DB().quickMenu end,
        set = function(v) DB().quickMenu = v end,
        tooltip = { "Quick swap", "Hold Alt and point at a slot on the character sheet to see the items in your bags that fit it; click one to put it on." } })
    L:EndSection()
    panel:Finish()
    return panel
end

function GS:FillRows(p)
    local names = self:SetNames()
    local scan = GS.Scan()
    for i, row in ipairs(p.setRows) do
        local set = Char().sets[names[i]]
        local f = row.frame
        row.hidden = set == nil
        f.set = set
        if set then
            f.icon:SetTexture(set.icon or GS.IconFor(set))
            local current = Char().current == set.name and " |cFF33FF33*|r" or ""
            f.name:SetText(set.name .. current)
            local status, plan = self:SetStatus(set, scan)
            f.plan = plan
            local badges = Badges(set)
            f.status:SetText(status .. (badges ~= "" and ("  " .. badges) or ""))
        end
    end
    p.emptyRow.hidden = #names > 0
end

function GS:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
    if editor and editor:IsShown() then editor:Refresh() end
end

function GS:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
GS.ToggleUI = GS.Toggle

-- ---- The set editor ----

function GS:CreateEditor()
    if editor then return editor end
    editor = WM.UI:CreatePanel({ name = "WM_GearSetEditor", title = "Gear Set", titleColor = "CCB366", width = 440 })
    local L = editor.layout
    local function D() return editor.draft end
    L:EditBox({ label = "Name:", width = 200, maxLetters = 40, get = function() return D() and D().name or "" end,
        set = function(v) D().name = v end })
    L:Note("Tick the slots this set changes; the rest are left alone. A ticked empty slot means \"take it off\".")
    L:Buttons({
        { text = "Take what I'm wearing", width = 160, onClick = function()
            for slot in pairs(D().items) do D().items[slot] = ItemString(GetInventoryItemLink("player", slot)) or false end
            editor:Refresh()
        end },
        { text = "All", width = 50, onClick = function()
            for _, slot in ipairs(DEFAULT_SLOTS) do
                if D().items[slot] == nil then D().items[slot] = ItemString(GetInventoryItemLink("player", slot)) or false end
            end
            editor:Refresh()
        end },
        { text = "None", width = 50, onClick = function() wipe(D().items); editor:Refresh() end },
    })
    editor.slotBoxes = {}
    for slot = 1, 19 do
        editor.slotBoxes[slot] = L:Checkbox({
            label = function()
                local v = D() and D().items[slot]
                local what
                if v == nil then what = "|cFF666666not part of the set|r"
                elseif v == false then what = "|cFF888888take it off|r"
                else what = LinkFor(v) end
                return SLOT_NAMES[slot] .. ": " .. what
            end,
            get = function() return D() and D().items[slot] ~= nil end,
            set = function(v)
                if v then D().items[slot] = ItemString(GetInventoryItemLink("player", slot)) or false
                else D().items[slot] = nil end
                editor:Refresh()
            end,
        })
    end
    L:Dropdown({ label = "Talent spec:", width = 220,
        options = function()
            local o = { { value = 0, text = "None" } }
            for g = 1, math.max(2, GS.NumSpecs()) do o[#o + 1] = { value = g, text = GS.SpecName(g) } end
            return o
        end,
        get = function() return D() and D().spec or 0 end,
        set = function(v) D().spec = (v ~= 0) and v or nil; if v ~= 0 and D().specAuto == nil then D().specAuto = true end; editor:Refresh() end })
    L:Checkbox({ label = "Equip it when I switch to that spec", get = function() return D() and D().specAuto end,
        set = function(v) D().specAuto = v end, disabled = function() return not (D() and D().spec) end })
    L:Checkbox({ label = "Equip it while mounted (back after)", get = function() return D() and D().mount end,
        set = function(v) D().mount = v end })
    L:Checkbox({ label = "Equip it in battlegrounds and arenas (back after)", get = function() return D() and D().pvp end,
        set = function(v) D().pvp = v end })
    editor:AddFooterButton({ text = "Save", width = 90, onClick = function() GS:SaveDraft() end }, "RIGHT")
    editor:AddFooterButton({ text = "Cancel", width = 90, onClick = function() editor:Hide() end }, "RIGHT")
    editor:Finish()
    return editor
end

-- Open the editor on a set (nil: a new set from what you're wearing)
function GS:OpenEditor(set)
    local e = self:CreateEditor()
    local d = { items = {} }
    if set then
        d.name, d.oldName, d.spec, d.specAuto, d.mount, d.pvp = set.name, set.name, set.spec, set.specAuto, set.mount, set.pvp
        for slot, v in pairs(set.items) do d.items[slot] = v end
    else
        d.name = ""
        for _, slot in ipairs(DEFAULT_SLOTS) do d.items[slot] = ItemString(GetInventoryItemLink("player", slot)) or false end
        local spec = GS.ActiveSpec()
        if not self:SetForSpec(spec) and GS.NumSpecs() > 1 then d.spec, d.specAuto = spec, true end
    end
    e.draft = d
    e:Show()
    e:Refresh()
    return e
end

function GS:SaveDraft()
    local d = editor and editor.draft
    if not d then return end
    local set, err = self:SaveSet(d.name, d.items, { oldName = d.oldName, spec = d.spec, specAuto = d.specAuto,
        mount = d.mount, pvp = d.pvp })
    if not set then Say(err); return end
    editor:Hide()
    Say("Saved " .. set.name .. (set.spec and set.specAuto and (", equipped when you switch to " .. GS.SpecName(set.spec)) or "") .. ".")
    self:UpdateDoll()
    return set
end

-- ============================================
-- DASHBOARD, COMMANDS
-- ============================================

function GS:OnModuleOff()
    -- Stop a swap part-way (what's already moved stays on)
    self.job = nil
    if panel then panel:Hide() end
    if editor then editor:Hide() end
    if quick then quick:Hide() end
    self:HideDoll()
end

-- Turned back on: start from how things are now, so nothing that changed
-- while it was off (spec, mount, zone) sets off a swap
function GS:OnModuleOn()
    if not self._wmStarted and not self.state then return end
    self.state = { mount = Mounted(), pvp = InPvP() }
    self:Arm()
    self:UpdateDoll()
end

-- The module's page in the guided setup
function GS:SetupPage(L)
    DB()
    L:Note("Gear Sets saves what you're wearing under a name and puts it back on for you: from its window, from a"
        .. " macro (|cFFFFFF00/wmachine gear equip Tank|r), or by itself. Swaps check every step, so a slow server or"
        .. " a full cursor doesn't leave you half-dressed, and in combat only the weapons change; the rest goes on"
        .. " when combat ends.")
    L:Header("Swapping when you change spec")
    L:Note("1. Put on the gear for one spec and click |cFFFFFFFFNew set|r in the Gear Sets window."
        .. "  2. In the set editor, pick that spec under |cFFFFFFFFTalent spec|r."
        .. "  3. Leave |cFFFFFFFFEquip it when I switch to that spec|r ticked. Do the same for your other spec.")
    L:Note("Now whenever you switch spec, chat says \"Switched to Spec 2: equipping ...\" and the set goes on."
        .. " Untick the box on one set to stop just that set swapping, or turn off Automatic swaps below to stop"
        .. " them all. A set can also go on while you're mounted or in battlegrounds, and what you wore before comes"
        .. " back after.")
    L:Note("|cFFFFFFFFIf something's missing:|r when a swap ends it says in chat what it couldn't find, and whether"
        .. " it's in your bank (that needs Your Characters on, which remembers your bank). Opening your character"
        .. " sheet shows a warning when a set's item isn't on you, and marks the slots of your last set in red.")
    L:Checkbox({ label = "Automatic swaps (spec, mounted, battlegrounds)", get = function() return DB().auto end,
        set = function(v) DB().auto = v end,
        tooltip = { "Automatic swaps", "On: a set goes on when you switch to its spec, mount up or enter a"
            .. " battleground (whichever its editor has ticked). Off: sets only go on when you equip them yourself." } })
    L:Checkbox({ label = "Chat alert when a set's item is missing", get = function() return DB().reportMissing end,
        set = function(v) DB().reportMissing = v end,
        tooltip = { "Missing items", "After a swap, a red line in chat lists anything the set wanted that you"
            .. " aren't carrying, and says if it's in your bank." } })
    L:Checkbox({ label = "Warn on the character sheet about missing items", get = function() return DB().dollWarning end,
        set = function(v) DB().dollWarning = v; GS:UpdateDoll() end,
        tooltip = { "Character sheet", "A warning at the top of your character sheet when any set has an item"
            .. " you don't have on you. Hover it for the list; click it for Gear Sets." } })
    L:Checkbox({ label = "Say in chat when a set is on", get = function() return DB().reportDone end,
        set = function(v) DB().reportDone = v end,
        tooltip = { "Done", "\"Equipped Tank.\" when a set you equipped yourself is on." } })
    L:Checkbox({ label = "Alt over a character sheet slot: what fits it", get = function() return DB().quickMenu end,
        set = function(v) DB().quickMenu = v end,
        tooltip = { "Quick swap", "Hold Alt and point at a slot on the character sheet to see the items in your"
            .. " bags that fit it; click one to put it on." } })
    L:Note("Making and editing sets, and undoing the last swap, are in its window: |cFFFFFF00/wmachine gear|r.")
end

function GS:GetQuickStatus()
    local n = #self:SetNames()
    local cur = Char().current
    return string.format("%d set%s%s", n, n == 1 and "" or "s", cur and (", last: " .. cur) or "")
end

-- /wmachine gear [equip <name> | undo | list]
function GS:Command(arg)
    arg = strtrim(arg or "")
    local verb, rest = arg:match("^(%S+)%s*(.*)$")
    verb = verb and verb:lower()
    if verb == "equip" and rest ~= "" then
        -- Names are matched without caring about case
        for _, name in ipairs(self:SetNames()) do
            if name:lower() == rest:lower() then return self:EquipSet(name) end
        end
        Say("No set called \"" .. rest .. "\".")
    elseif verb == "undo" then
        self:Undo()
    elseif verb == "list" then
        local names = self:SetNames()
        Say(#names > 0 and ("Your sets: " .. table.concat(names, ", ")) or "No sets yet.")
    else
        self:Toggle()
    end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if not GS.job or not On() then return end
    since = since + (elapsed or 0)
    if since < TICK then return end
    local dt = since
    since = 0
    local job = GS.job
    if job.waiting == "combat" and InCombat() then return end
    local ok, err = pcall(GS.Tick, GS, dt)
    if not ok then GS.job = nil; geterrorhandler()(err) end
end)

local dollPending = false
local function DollSoon()
    if dollPending then return end
    dollPending = true
    WM.RunAfter(0.3, function() dollPending = false; GS:UpdateDoll() end)
end

function GS:Initialize()
    DB()
    self.state = { mount = Mounted(), pvp = InPvP() }
    self:HookDoll()
    -- Started after you were already in the world (at login the start-up
    -- comes after the first loading screen, or turned on later): get ready
    -- for spec swaps now rather than at the next loading screen
    if IsLoggedIn and IsLoggedIn() then
        WM.RunAfter(1, function() if not GS.ready then GS:Arm() end end)
    end
    WM:RegisterEvents(events, { "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED",
        "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_AURA", "PLAYER_MOUNT_DISPLAY_CHANGED", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_ENTERING_WORLD", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
        "ADDON_LOADED" })
end

events:SetScript("OnEvent", function(_, event, arg1)
    if not On() then return end
    local ok, err = true
    if event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        ok, err = pcall(GS.OnSpecChanged, GS)
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if GS.job then GS.job.waiting = nil; ok, err = pcall(GS.Tick, GS, 0) end
    elseif event == "UNIT_AURA" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or arg1 == "player" then ok, err = pcall(GS.CheckTrigger, GS, "mount") end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" and not GS.ready then GS:Arm() end
        ok, err = pcall(GS.CheckTrigger, GS, "pvp")
    elseif event == "BANKFRAME_OPENED" then
        GS.bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        GS.bankOpen = false
    elseif event == "BAG_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" then
        DollSoon()
        if panel and panel:IsShown() and not GS.job then GS:RefreshUI() end
    elseif event == "ADDON_LOADED" then
        GS:HookDoll()
    end
    if not ok then geterrorhandler()(err) end
end)
