-- Watching Machine: GearScore
-- A gear score and average item level for you and every player you mouse
-- over, worked out from their equipped items: on unit tooltips, on item
-- tooltips (with what an item would change for you), on the character and
-- inspect frames, and in a list of your group.
--
-- The score uses the GearScoreLite formula as tuned for TBC by
-- GearScoreTBCClassic, so the numbers match what its users quote:
--
--   GearScoreTBCClassic, Copyright (c) 2024 gk646. MIT License:
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the
--   "Software"), to deal in the Software without restriction, including
--   without limitation the rights to use, copy, modify, merge, publish,
--   distribute, sublicense, and/or sell copies of the Software, and to
--   permit persons to whom the Software is furnished to do so, subject to
--   the following conditions: The above copyright notice and this
--   permission notice shall be included in all copies or substantial
--   portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT
--   WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
--   THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
--   LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
--   OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
--   WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local AddonName, WM = ...
local GS = {}
WM:RegisterModule("GearScore", GS)
WM.GearScore = GS

GS.version = "3.37"

local DEFAULTS = {
    unitTooltip = true,     -- score on player tooltips
    itemTooltip = true,     -- score on item tooltips
    itemDetails = false,    -- base / enchant / gems / upgrade lines on item tooltips
    paperDoll = true,       -- score on the character and inspect frames
    autoInspect = true,     -- inspect players you mouse over (out of combat, in range)
    keepDays = 7,           -- how long others' scores are kept
}
GS.DEFAULTS = DEFAULTS

local function DB()
    WMGearScoreDB = WMGearScoreDB or {}
    local db = WMGearScoreDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if type(db.players) ~= "table" then db.players = {} end
    if type(db.pos) ~= "table" then db.pos = {} end
    return db
end

-- Another GearScore addon already puts scores on tooltips and the
-- character frame: leave those to it (the group list still works)
local OTHER_ADDONS = { "GearScoreTBCClassic", "GearScore", "GearScoreLite", "TacoTip" }
function GS.OtherAddon()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if type(f) ~= "function" then return nil end
    for _, name in ipairs(OTHER_ADDONS) do
        local ok, loaded = pcall(f, name)
        if ok and loaded == true then return name end
    end
end

local function Now() return (GetServerTime and GetServerTime()) or time() end

-- ============================================
-- THE FORMULA
-- ============================================

local BRACKET = 400                  -- TBC bracket size (Classic 200, Wrath 1000)
local MAX_SCORE = BRACKET * 6 - 1
local SCALE = 1.8618
local ENCHANT_BONUS = 1.05           -- an enchanted item counts 5% more
local GEM_BONUS = 5                  -- per socketed gem
local SLOTS = 17                     -- equippable slots for the average item level

-- [equip location] = { weight, can be enchanted }
local SLOT_INFO = {
    INVTYPE_RELIC = { 0.3164, false }, INVTYPE_TRINKET = { 0.5625, false },
    INVTYPE_2HWEAPON = { 2.000, true }, INVTYPE_WEAPONMAINHAND = { 1.0, true },
    INVTYPE_WEAPONOFFHAND = { 1.0, true }, INVTYPE_RANGED = { 0.3164, true },
    INVTYPE_THROWN = { 0.3164, false }, INVTYPE_RANGEDRIGHT = { 0.3164, true },
    INVTYPE_SHIELD = { 1.0, true }, INVTYPE_WEAPON = { 1.0, true },
    INVTYPE_HOLDABLE = { 1.0, false }, INVTYPE_HEAD = { 1.0, true },
    INVTYPE_NECK = { 0.5625, false }, INVTYPE_SHOULDER = { 0.75, true },
    INVTYPE_CHEST = { 1.0, true }, INVTYPE_ROBE = { 1.0, true },
    INVTYPE_WAIST = { 0.75, false }, INVTYPE_LEGS = { 1.0, true },
    INVTYPE_FEET = { 0.75, true }, INVTYPE_WRIST = { 0.5625, true },
    INVTYPE_HAND = { 0.75, true }, INVTYPE_FINGER = { 0.5625, false },
    INVTYPE_CLOAK = { 0.5625, true },
}
GS.SLOT_INFO = SLOT_INFO

-- Where each equip location goes, for "what would this change"
local SLOTS_FOR = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON = { 16, 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Per quality: score = (item level - A) / B
local FORMULA = {
    [4] = { 26.0, 1.2 },
    [3] = { 0.75, 1.8 },
    [2] = { 8.0, 2.0 },
    [1] = { 0.0, 2.25 },
}

local SOCKET_STATS = { "EMPTY_SOCKET_META", "EMPTY_SOCKET_RED", "EMPTY_SOCKET_YELLOW", "EMPTY_SOCKET_BLUE", "EMPTY_SOCKET_PRISMATIC" }
local SCOPE_SUBCLASSES = { [2] = true, [3] = true, [18] = true }   -- bows, guns, crossbows
local HUNTER_MELEE = { INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_WEAPON = true, INVTYPE_HOLDABLE = true }
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }

local function ItemInfo(link)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, name, _, quality, ilvl, _, _, _, _, equipLoc = pcall(f, link)
    if ok and type(name) == "string" then return name, tonumber(quality), tonumber(ilvl), equipLoc end
end

local function ItemClass(link)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, classID, subclassID = pcall(f, link)
    if ok then return classID, subclassID end
end

local function SocketCount(link)
    local f = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not f then return 0 end
    local ok, stats = pcall(f, link)
    if not ok or type(stats) ~= "table" then return 0 end
    local n = 0
    for _, k in ipairs(SOCKET_STATS) do n = n + (tonumber(stats[k]) or 0) end
    return n
end

local function EnchantID(link) return tonumber(link:match("item:%d+:(%d+)")) end

local function GemCount(link)
    local n = 0
    local a, b, c = link:match("item:%d+:%d*:(%d*):(%d*):(%d*)")
    for _, g in ipairs({ a, b, c }) do
        if tonumber(g) and tonumber(g) > 0 then n = n + 1 end
    end
    return n
end

-- Can it be enchanted, and should a missing enchant be pointed out?
-- (Ring enchants are enchanter-only: counted, never flagged as missing.)
local function EnchantRule(link, equipLoc, default)
    if equipLoc == "INVTYPE_FINGER" then return true, false end
    if RANGED[equipLoc] then
        local classID, subclassID = ItemClass(link)
        local scope = classID == 2 and SCOPE_SUBCLASSES[subclassID] == true
        return scope, scope
    end
    return default, default
end

-- One item's score. Returns nil while the client has no data for it yet,
-- else a table: score, ilvl, base, enchantBonus, gems, sockets, enchanted,
-- missingEnchant, equipLoc
function GS.ItemScore(link, class)
    if type(link) ~= "string" then return nil end
    local name, quality, ilvl, equipLoc = ItemInfo(link)
    if not name or not quality or not ilvl or not equipLoc then return nil end
    local slot = SLOT_INFO[equipLoc]
    local r = { score = 0, ilvl = ilvl, base = 0, enchantBonus = 0, gems = 0, sockets = 0, equipLoc = equipLoc }
    if not slot then return r end
    local scale = 1
    if quality == 5 then scale, quality = 1.3, 4
    elseif quality == 1 or quality == 0 then scale, quality = 0.005, 2
    elseif quality == 7 then quality, ilvl, r.heirloom = 3, 187.05, true end
    local f = FORMULA[quality]
    if not f or quality < 2 or quality > 4 then return r end
    local score = math.floor(((ilvl - f[1]) / f[2]) * slot[1] * SCALE * scale)
    if r.heirloom then r.ilvl = 0 end
    if score < 0 then score = 0 end
    if class == "HUNTER" then
        if HUNTER_MELEE[equipLoc] then score = math.floor(score * 0.3164)
        elseif RANGED[equipLoc] then score = math.floor(score * 5.3224) end
    end
    r.base = score
    local canEnchant, flagMissing = EnchantRule(link, equipLoc, slot[2])
    local ench = canEnchant and EnchantID(link)
    r.enchanted = ench ~= nil and ench ~= false and ench > 0
    if r.enchanted then score = math.floor(score * ENCHANT_BONUS) end
    r.enchantBonus = score - r.base
    r.missingEnchant = flagMissing and not r.enchanted
    r.gems = GemCount(link)
    score = score + r.gems * GEM_BONUS
    r.sockets = math.max(SocketCount(link), r.gems)
    r.score = score
    return r
end

local function UnitClassToken(unit)
    local _, class = UnitClass(unit)
    return class
end

-- A unit's total: score, average item level, complete (false while some
-- item data hasn't arrived)
function GS.UnitScore(unit)
    local class = UnitClassToken(unit)
    local total, levels, complete = 0, 0, true
    local mainLink, mainLevel
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = GetInventoryItemLink(unit, slot)
            if link then
                local r = GS.ItemScore(link, class)
                if r then
                    total = total + r.score
                    if r.ilvl and r.ilvl > 0 then levels = levels + r.ilvl end
                    if slot == 16 then mainLink, mainLevel = link, r.ilvl end
                else
                    complete = false
                end
            elseif GetInventoryItemID and GetInventoryItemID(unit, slot) then
                complete = false   -- something is there, its link just isn't ready
            end
        end
    end
    -- A two-hander counts for both weapon slots in the average
    if mainLink and not GetInventoryItemLink(unit, 17) and (mainLevel or 0) > 0 then
        local _, _, _, loc = ItemInfo(mainLink)
        if loc == "INVTYPE_2HWEAPON" then levels = levels + mainLevel end
    end
    return total, levels / SLOTS, complete
end

-- ============================================
-- COLOURS (GearScoreLite's brackets)
-- ============================================

local QUALITY = {
    [BRACKET * 6] = { { 0.94, BRACKET * 5, 0.00006, 1 }, { 0, 0, 0, 0 }, { 0.47, BRACKET * 5, 0.00047, -1 }, "Legendary" },
    [BRACKET * 5] = { { 0.69, BRACKET * 4, 0.00025, 1 }, { 0.97, BRACKET * 4, 0.00096, -1 }, { 0.28, BRACKET * 4, 0.00019, 1 }, "Epic" },
    [BRACKET * 4] = { { 0.0, BRACKET * 3, 0.00069, 1 }, { 1, BRACKET * 3, 0.00003, -1 }, { 0.5, BRACKET * 3, 0.00022, -1 }, "Superior" },
    [BRACKET * 3] = { { 0.12, BRACKET * 2, 0.00012, -1 }, { 0, BRACKET * 2, 0.001, 1 }, { 1, BRACKET * 2, 0.00050, -1 }, "Uncommon" },
    [BRACKET * 2] = { { 1, BRACKET, 0.00088, -1 }, { 1, BRACKET, 0.001, -1 }, { 1, 0, 0, 0 }, "Common" },
    [BRACKET] = { { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 }, "Trash" },
}

local function Channel(c, score) return c[1] + ((score - c[2]) * c[3]) * c[4] end
local function Clamp(v) return math.max(0, math.min(1, v)) end

-- r, g, b, tier name. (GearScoreLite's green / blue swap is kept, so the
-- colours match.)
function GS.Color(score)
    score = tonumber(score) or 0
    if score <= 0 then return 0.55, 0.55, 0.55, "Trash" end
    if score > MAX_SCORE then score = MAX_SCORE end
    for i = 0, 5 do
        if score > i * BRACKET and score <= (i + 1) * BRACKET then
            local q = QUALITY[(i + 1) * BRACKET]
            return Clamp(Channel(q[1], score)), Clamp(Channel(q[3], score)), Clamp(Channel(q[2], score)), q[4]
        end
    end
    return 0.55, 0.55, 0.55, "Trash"
end

function GS.ColorText(score, text)
    local r, g, b = GS.Color(score)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255),
        text or tostring(math.floor((score or 0) + 0.5)))
end

-- ============================================
-- SCORES WE KNOW
-- ============================================
-- By GUID for this session, and by name for a week (the group list)

local byGUID = {}

local function NameKey(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() or "" end
    return name .. "-" .. realm
end

function GS:Store(unit, score, ilvl)
    local guid = UnitGUID(unit)
    if not guid then return end
    local entry = { score = score, ilvl = ilvl, at = Now(), name = UnitName(unit), class = UnitClassToken(unit) }
    byGUID[guid] = entry
    local key = NameKey(unit)
    if key then DB().players[key] = entry end
    self:RefreshUI()
    return entry
end

function GS:Known(unit)
    local guid = UnitGUID(unit)
    local e = guid and byGUID[guid]
    if e then return e end
    local key = NameKey(unit)
    e = key and DB().players[key]
    if e and Now() - (e.at or 0) < (DB().keepDays or 7) * 86400 then return e end
end

function GS:Prune(now)
    now = now or Now()
    local limit = (DB().keepDays or 7) * 86400
    for k, e in pairs(DB().players) do
        if type(e) ~= "table" or now - (e.at or 0) > limit then DB().players[k] = nil end
    end
end

-- Your own, kept up to date
function GS:UpdatePlayer()
    local score, ilvl, complete = GS.UnitScore("player")
    self.playerScore, self.playerIlvl = score, ilvl
    if complete then self:Store("player", score, ilvl) end
    self:RefreshFrames()
    return score, ilvl, complete
end

-- ============================================
-- INSPECTING
-- ============================================
-- One player at a time, in range, out of combat, never while you have the
-- inspect window open on someone (that would switch it)

local queue, queued = {}, {}
local MAX_QUEUE = 10
local current, currentAt
local lastNotify = -100
local INSPECT_GAP, INSPECT_TIMEOUT, RETRIES = 1.5, 4, 3
local FRESH = 600   -- don't inspect again for 10 minutes

local function InspectWindowOpen()
    local f = rawget(_G, "InspectFrame")
    return type(f) == "table" and f.IsShown and f:IsShown()
end

local function CanInspectUnit(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if CanInspect and not CanInspect(unit) then return false end
    if CheckInteractDistance then
        local ok, near = pcall(CheckInteractDistance, unit, 1)
        if ok and not near then return false end
    end
    return true
end
GS.CanInspectUnit = CanInspectUnit

-- Ask to inspect a unit (soon). force: even if we know a recent score.
function GS:QueueInspect(unit, force)
    if not CanInspectUnit(unit) then return false end
    local guid = UnitGUID(unit)
    if not guid or queued[guid] then return false end
    local e = byGUID[guid]
    if e and not force and Now() - (e.at or 0) < FRESH then return false end
    queued[guid] = true
    queue[#queue + 1] = { unit = unit, guid = guid, tries = 0 }
    while #queue > MAX_QUEUE do queued[table.remove(queue, 1).guid] = nil end
    self:NextInspect()
    return true
end

function GS:NextInspect()
    local t = GetTime()
    if current then
        if t - currentAt < INSPECT_TIMEOUT then return end
        queued[current.guid] = nil   -- gave up on it
        current = nil
    end
    if InspectWindowOpen() or t - lastNotify < INSPECT_GAP then return end
    while #queue > 0 do
        local job = table.remove(queue, 1)
        if UnitGUID(job.unit) == job.guid and CanInspectUnit(job.unit) then
            current, currentAt, lastNotify = job, t, t
            NotifyInspect(job.unit)
            return job
        end
        queued[job.guid] = nil
    end
end

-- A unit token that is this player right now (the mouseover may have moved on)
local function UnitFor(guid, hint)
    if hint and UnitGUID(hint) == guid then return hint end
    local tokens = { "mouseover", "target", "focus" }
    local raid = IsInRaid and IsInRaid()
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        tokens[#tokens + 1] = (raid and "raid" or "party") .. i
    end
    for _, u in ipairs(tokens) do
        if UnitGUID(u) == guid then return u end
    end
end
GS.UnitFor = UnitFor

function GS:OnInspectReady(guid)
    if not current or current.guid ~= guid then return end
    local job = current
    local unit = UnitFor(guid, job.unit)
    if not unit then
        current, queued[guid] = nil, nil
        return
    end
    job.unit = unit
    local score, ilvl, complete = GS.UnitScore(job.unit)
    if not complete and job.tries < RETRIES then
        -- Some items aren't known to the client yet: look again shortly
        job.tries = job.tries + 1
        WM.RunAfter(0.3, function()
            if current == job then GS:OnInspectReady(guid) end
        end)
        return
    end
    current, queued[guid] = nil, nil
    local entry = self:Store(job.unit, score, ilvl)
    if not InspectWindowOpen() and ClearInspectPlayer then ClearInspectPlayer() end
    self:RefreshTooltip(job.unit)
    self:RefreshFrames()
    return entry
end

-- ============================================
-- TOOLTIPS
-- ============================================

function GS:UnitLine(entry)
    return "|cFFFFD100GearScore:|r " .. GS.ColorText(entry.score) .. "  |cFFFFD100iLvl:|r |cFFFFFFFF"
        .. math.floor((entry.ilvl or 0) + 0.5) .. "|r"
end

function GS:AddUnitTooltip(tip, unit)
    if self.other or not DB().unitTooltip or not tip or not unit or not UnitIsPlayer(unit) then return false end
    local guid = UnitGUID(unit)
    if not guid or tip.wmGearScore == guid then return false end
    local entry
    if UnitIsUnit(unit, "player") then
        local score, ilvl = GS.UnitScore("player")
        entry = { score = score, ilvl = ilvl }
    else
        entry = self:Known(unit)
        if DB().autoInspect and not (entry and byGUID[guid] and Now() - (entry.at or 0) < FRESH) then
            self:QueueInspect(unit)
        end
    end
    if not entry or (entry.score or 0) <= 0 then return false end
    tip.wmGearScore = guid
    tip:AddLine(self:UnitLine(entry))
    if tip.Show then tip:Show() end
    return true
end

-- An inspect finished while its tooltip is still up: add the line now
function GS:RefreshTooltip(unit)
    local tip = rawget(_G, "GameTooltip")
    if not tip or not tip.GetUnit then return end
    local ok, _, tipUnit = pcall(tip.GetUnit, tip)
    if ok and tipUnit and UnitGUID(tipUnit) == UnitGUID(unit) then self:AddUnitTooltip(tip, tipUnit) end
end

local function Equippable(link)
    local f = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
    if not f then return true end
    local ok, v = pcall(f, link)
    return ok and v and true or false
end

-- What equipping an item instead would change: the equipped score it replaces
function GS.ReplacedScore(equipLoc)
    local slots = SLOTS_FOR[equipLoc]
    if not slots then return nil end
    local class = UnitClassToken("player")
    local function At(slot)
        local r = GS.ItemScore(GetInventoryItemLink("player", slot), class)
        return r and r.score or 0
    end
    local mainLink = GetInventoryItemLink("player", 16)
    local mainLoc = mainLink and select(4, ItemInfo(mainLink))
    local both = equipLoc == "INVTYPE_2HWEAPON" or (mainLoc == "INVTYPE_2HWEAPON" and (equipLoc == "INVTYPE_WEAPON"
        or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE"))
    if both then return At(16) + At(17) end
    if equipLoc == "INVTYPE_WEAPON" and (not CanDualWield or not CanDualWield()) then return At(16) end
    local worst = At(slots[1])
    for i = 2, #slots do worst = math.min(worst, At(slots[i])) end
    return worst
end

local IND = "   "
function GS:ItemLines(link)
    if not Equippable(link) then return nil end
    local r = GS.ItemScore(link, UnitClassToken("player"))
    if not r or not SLOT_INFO[r.equipLoc] then return nil end
    local lines = { "|cFFFFD100GearScore:|r |cFFFFFFFF" .. r.score .. "|r" }
    if DB().itemDetails then
        lines[#lines + 1] = IND .. "Base: " .. r.base
        if r.enchanted then
            lines[#lines + 1] = IND .. "Enchant: |cff00ff00+" .. r.enchantBonus .. "|r"
        elseif r.missingEnchant then
            lines[#lines + 1] = IND .. "Enchant: |cffff4040-" .. (math.floor(r.base * ENCHANT_BONUS) - r.base) .. " (missing)|r"
        end
        if r.sockets > 0 then
            local missing = r.sockets - r.gems
            local s = IND .. "Gems: "
            if r.gems > 0 then s = s .. "|cff00ff00+" .. (r.gems * GEM_BONUS) .. "|r" end
            if missing > 0 then s = s .. (r.gems > 0 and ", " or "") .. "|cffff4040-" .. (missing * GEM_BONUS) .. " (" .. missing .. " empty)|r" end
            lines[#lines + 1] = s
        end
        local replaced = GS.ReplacedScore(r.equipLoc)
        if replaced then
            local diff = r.score - replaced
            local total = (GS.UnitScore("player")) + diff
            local change = diff > 0 and ("|cff00ff00+" .. diff .. "|r") or diff < 0 and ("|cffff4040" .. diff .. "|r") or "|cff9d9d9d0|r"
            lines[#lines + 1] = IND .. "Equipped: " .. replaced .. ", change " .. change .. ", new total " .. GS.ColorText(total)
        end
    end
    return lines
end

function GS:AddItemTooltip(tip, link)
    if self.other or not DB().itemTooltip or not tip or type(link) ~= "string" then return false end
    if tip.wmGearScoreItem == link then return false end
    local lines = self:ItemLines(link)
    if not lines then return false end
    tip.wmGearScoreItem = link
    for _, l in ipairs(lines) do tip:AddLine(l) end
    if tip.Show then tip:Show() end
    return true
end

local hooked = {}
local function HookTip(tip, units)
    if type(tip) ~= "table" or hooked[tip] or not tip.HookScript then return end
    hooked[tip] = true
    tip:HookScript("OnTooltipCleared", function(t) t.wmGearScore, t.wmGearScoreItem = nil, nil end)
    if not tip.HasScript or tip:HasScript("OnTooltipSetItem") then
        tip:HookScript("OnTooltipSetItem", function(t)
            if not t.GetItem then return end
            local ok, _, link = pcall(t.GetItem, t)
            if ok then GS:AddItemTooltip(t, link) end
        end)
    end
    if units and (not tip.HasScript or tip:HasScript("OnTooltipSetUnit")) then
        tip:HookScript("OnTooltipSetUnit", function(t)
            if not t.GetUnit then return end
            local ok, _, unit = pcall(t.GetUnit, t)
            if ok then GS:AddUnitTooltip(t, unit) end
        end)
    end
end

function GS:HookTooltips()
    if self.tooltipsHooked then return end
    self.tooltipsHooked = true
    local proc, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    if type(proc) == "table" and type(proc.AddTooltipPostCall) == "function" and type(enum) == "table"
        and type(enum.TooltipDataType) == "table" then
        local T = enum.TooltipDataType
        if T.Item then
            proc.AddTooltipPostCall(T.Item, function(tip)
                if not tip or not tip.GetItem then return end
                local ok, _, link = pcall(tip.GetItem, tip)
                if ok then GS:AddItemTooltip(tip, link) end
            end)
        end
        if T.Unit then
            proc.AddTooltipPostCall(T.Unit, function(tip)
                if not tip or not tip.GetUnit then return end
                local ok, _, unit = pcall(tip.GetUnit, tip)
                if ok then GS:AddUnitTooltip(tip, unit) end
            end)
        end
    end
    HookTip(rawget(_G, "GameTooltip"), true)
    for _, name in ipairs({ "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do HookTip(rawget(_G, name), false) end
end

-- ============================================
-- CHARACTER AND INSPECT FRAMES
-- ============================================

local DEFAULT_POS = { paperDoll = { 73, 240 }, inspect = { 73, 145 } }
local frames = {}

local function ScoreFrame(key, parent)
    if frames[key] then return frames[key] end
    if type(parent) ~= "table" then return nil end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(220, 24)
    local pos = DB().pos[key] or DEFAULT_POS[key]
    f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", pos[1], pos[2])
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(1, 0.82, 0, 0.14)
    f.bg:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = self:GetParent()
        if p and p.GetLeft and p:GetLeft() and self:GetLeft() then
            local x, y = math.floor(self:GetLeft() - p:GetLeft() + 0.5), math.floor(self:GetBottom() - p:GetBottom() + 0.5)
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", x, y)
            DB().pos[key] = { x, y }
        end
    end)
    frames[key] = f
    return f
end
GS.frames = frames

local function SetFrameText(f, score, ilvl)
    if not f then return end
    if not DB().paperDoll or GS.other then f:Hide(); return end
    f.text:SetText("|cFFFFD100GearScore:|r " .. GS.ColorText(score) .. "    |cFFFFD100iLvl:|r |cFFFFFFFF"
        .. math.floor((ilvl or 0) + 0.5) .. "|r")
    f:Show()
end

function GS:RefreshFrames()
    if frames.paperDoll then
        SetFrameText(frames.paperDoll, self.playerScore or 0, self.playerIlvl or 0)
    end
    local inspect = rawget(_G, "InspectFrame")
    if frames.inspect and type(inspect) == "table" and inspect.unit and UnitExists(inspect.unit) then
        local score, ilvl = GS.UnitScore(inspect.unit)
        SetFrameText(frames.inspect, score, ilvl)
    end
end

function GS:Unlock(on)
    for _, f in pairs(frames) do
        f:EnableMouse(on and true or false)
        f.bg:SetShown(on and true or false)
        f:SetFrameStrata(on and "DIALOG" or "MEDIUM")
    end
    self.unlocked = on and true or false
end

function GS:ResetPositions()
    DB().pos = {}
    for key, f in pairs(frames) do
        local pos = DEFAULT_POS[key]
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", f:GetParent(), "BOTTOMLEFT", pos[1], pos[2])
    end
end

function GS:HookFrames()
    local doll = rawget(_G, "PaperDollFrame")
    if not frames.paperDoll and type(doll) == "table" then
        ScoreFrame("paperDoll", doll)
        local cf = rawget(_G, "CharacterFrame")
        if type(cf) == "table" and cf.HookScript then cf:HookScript("OnShow", function() GS:UpdatePlayer() end) end
    end
    local inspect = rawget(_G, "InspectFrame")
    if not frames.inspect and type(inspect) == "table" then
        ScoreFrame("inspect", inspect)
        if inspect.HookScript then inspect:HookScript("OnShow", function() GS:RefreshFrames() end) end
    end
end

-- ============================================
-- GROUP LIST
-- ============================================

local panel

local function GroupUnits()
    local out = { "player" }
    local raid = IsInRaid and IsInRaid()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if raid then
        out = {}
        for i = 1, n do out[#out + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, n - 1) do out[#out + 1] = "party" .. i end
    end
    return out
end

-- { name, class, score, ilvl, age (seconds, nil = never), unit } for each
-- group member, highest score first
function GS:GroupList()
    local list = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local e
            if UnitIsUnit(unit, "player") then
                local score, ilvl = GS.UnitScore("player")
                e = { score = score, ilvl = ilvl, at = Now() }
            else
                e = self:Known(unit)
            end
            list[#list + 1] = { unit = unit, name = UnitName(unit), class = UnitClassToken(unit),
                score = e and e.score, ilvl = e and e.ilvl, age = e and (Now() - (e.at or 0)) }
        end
    end
    table.sort(list, function(a, b)
        if (a.score or -1) ~= (b.score or -1) then return (a.score or -1) > (b.score or -1) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- Queue everyone in the group we don't have a recent score for
function GS:ScanGroup()
    local n = 0
    for _, unit in ipairs(GroupUnits()) do
        if self:QueueInspect(unit) then n = n + 1 end
    end
    return n
end

function GS:ReportLines()
    local list = self:GroupList()
    local scored, sum = 0, 0
    for _, e in ipairs(list) do if e.score then scored = scored + 1; sum = sum + e.score end end
    local lines = { string.format("[WM] GearScore: %d of %d known, average %d", scored, #list, scored > 0 and math.floor(sum / scored + 0.5) or 0) }
    local line = ""
    for _, e in ipairs(list) do
        if e.score then
            local part = e.name .. " " .. e.score
            if #line + #part > 230 then lines[#lines + 1] = line; line = "" end
            line = line .. (line == "" and "" or ", ") .. part
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

function GS:Report(channel)
    for _, l in ipairs(self:ReportLines()) do
        if channel then SendChatMessage(l, channel) else WM:ModulePrint("GearScore", l) end
    end
end

local function ClassColored(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.r then return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name) end
    return name
end

local function Ago(s)
    if not s then return "|cFF888888not yet|r" end
    if s < 60 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    return math.floor(s / 3600) .. "h ago"
end

local ROW_H = 18
function GS:RefreshList()
    if not panel or not panel.listChild then return end
    local rows, child = panel.rows, panel.listChild
    local list = self:GroupList()
    for i, e in ipairs(list) do
        local r = rows[i]
        if not r then
            r = CreateFrame("Frame", nil, child)
            r:SetHeight(ROW_H)
            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.name:SetPoint("LEFT", 4, 0)
            r.name:SetWidth(150)
            r.name:SetJustifyH("LEFT")
            r.score = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.score:SetPoint("LEFT", 160, 0)
            r.ilvl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.ilvl:SetPoint("LEFT", 230, 0)
            r.age = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.age:SetPoint("LEFT", 290, 0)
            rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r.name:SetText(ClassColored(e.name or "?", e.class))
        r.score:SetText(e.score and GS.ColorText(e.score) or "|cFF888888-|r")
        r.ilvl:SetText(e.ilvl and ("|cFFFFFFFF" .. math.floor(e.ilvl + 0.5) .. "|r") or "")
        r.age:SetText(UnitIsUnit(e.unit, "player") and "|cFF888888you|r" or ("|cFF888888" .. Ago(e.age) .. "|r"))
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    child:SetHeight(math.max(1, #list * ROW_H))
    if panel.summary then
        local known, sum = 0, 0
        for _, e in ipairs(list) do if e.score then known = known + 1; sum = sum + e.score end end
        panel.summary:SetText(string.format("|cFFFFD100%d|r of %d known, average %s", known, #list,
            known > 0 and GS.ColorText(sum / known) or "-"))
    end
    return #list
end

function GS:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_GearScoreFrame", title = "GearScore", titleColor = "A335EE",
        width = 420, height = 440, scroll = false,
        resizable = { 380, 300, 800, 1200 },
        onResize = function() GS:RefreshList() end,
        onRefresh = function() GS:RefreshList() end,
    })
    local L = panel.layout
    L:Row(18):Text({ text = function()
        if GS.other then return "|cFFFF9933" .. GS.other .. " is loaded: tooltips and the character frame are left to it.|r" end
        return "|cFF888888Your group's scores. Players are inspected when in range (about 28 yards) and out of combat.|r"
    end, width = 380 }, 8)
    local head = L:Row(16)
    head:Text({ text = "|cFFFFD100Name|r" }, 4)
    head:Text({ text = "|cFFFFD100GearScore|r" }, 160)
    head:Text({ text = "|cFFFFD100iLvl|r" }, 230)
    head:Text({ text = "|cFFFFD100Seen|r" }, 290)
    local fill = L:Fill(140)
    local scroll = CreateFrame("ScrollFrame", "WM_GearScoreScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(360, 1)
    scroll:SetScrollChild(child)
    panel.listChild, panel.rows = child, {}
    L:Section({ key = "options", title = "Options" })
    L:Checkbox({ label = "GearScore on player tooltips", get = function() return DB().unitTooltip end, set = function(v) DB().unitTooltip = v end })
    L:Checkbox({ label = "Inspect players you mouse over", get = function() return DB().autoInspect end, set = function(v) DB().autoInspect = v end,
        tooltip = { "Inspecting", "Out of combat and within inspect range, one player at a time. Never while your own inspect window is open." } })
    L:Checkbox({ label = "GearScore on item tooltips", get = function() return DB().itemTooltip end, set = function(v) DB().itemTooltip = v end })
    L:Checkbox({ label = "Item tooltip details (enchant, gems, upgrade)", get = function() return DB().itemDetails end, set = function(v) DB().itemDetails = v end,
        tooltip = { "Details", "The item's base score, its enchant and gem bonuses (or what's missing), and what equipping it would change for you." } })
    L:Checkbox({ label = "On the character and inspect frames", get = function() return DB().paperDoll end,
        set = function(v) DB().paperDoll = v; GS:RefreshFrames() end,
        tooltip = { "Frames", "/wmachine gs unlock to drag it, /wmachine gs lock to save, /wmachine gs reset to put it back." } })
    L:EndSection()
    panel.summary = panel:AddFooterText({ text = "" }, "LEFT")
    panel:AddFooterButton({ text = "Scan group", width = 90, onClick = function()
        local n = GS:ScanGroup()
        WM:ModulePrint("GearScore", n > 0 and ("Inspecting " .. n .. " player" .. (n == 1 and "" or "s") .. "...")
            or "Nobody new in range to inspect.")
    end }, "RIGHT")
    panel:AddFooterButton({ text = "Send to group", width = 100, onClick = function()
        local ch = (IsInRaid and IsInRaid()) and "RAID" or ((GetNumGroupMembers and GetNumGroupMembers() or 0) > 0 and "PARTY" or nil)
        GS:Report(ch)
    end }, "RIGHT")
    panel:Finish()
    return panel
end

function GS:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function GS:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show(); self:ScanGroup() end
end
GS.ToggleUI = GS.Toggle

function GS:GetQuickStatus()
    local score = self.playerScore or GS.UnitScore("player")
    return "You: " .. GS.ColorText(score)
end

-- /wmachine gs [unlock | lock | reset | report]
function GS:Command(arg)
    arg = (arg or ""):lower()
    if arg == "unlock" or arg == "move" then
        self:HookFrames()
        self:Unlock(true)
        WM:ModulePrint("GearScore", "Drag the GearScore line on your character frame, then /wmachine gs lock.")
    elseif arg == "lock" then
        self:Unlock(false)
        WM:ModulePrint("GearScore", "Position saved.")
    elseif arg == "reset" then
        self:ResetPositions()
        WM:ModulePrint("GearScore", "Position reset.")
    elseif arg == "report" then
        self:Report()
    else
        self:Toggle()
    end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local pendingPlayer = false

function GS:OnEvent(event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "GET_ITEM_INFO_RECEIVED" then
        if pendingPlayer then return end
        pendingPlayer = true
        WM.RunAfter(0.5, function()
            pendingPlayer = false
            GS:UpdatePlayer()
        end)
    elseif event == "INSPECT_READY" then
        self:HookFrames()
        self:OnInspectReady(arg1)
        self:RefreshFrames()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then self:HookFrames() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:RefreshUI()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:NextInspect()
    end
end

function GS:Initialize()
    DB()
    self:Prune()
    self.other = GS.OtherAddon()
    if self.other then
        WM:ModulePrint("GearScore", self.other .. " is loaded, so its tooltips and character frame score are used;"
            .. " Watching Machine's group list (/wmachine gs) still works.")
    end
    WM:RegisterEvents(events, {
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED", "INSPECT_READY",
        "ADDON_LOADED", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
    })
    self:HookTooltips()
    self:HookFrames()
    WM.RunTicker(1, function() GS:NextInspect() end)
    -- /gs as a shortcut, unless another GearScore addon has it
    if type(SlashCmdList) == "table" and not SlashCmdList.GEARSCORE and not SlashCmdList.WM_GEARSCORE then
        SLASH_WM_GEARSCORE1 = "/gs"
        SlashCmdList.WM_GEARSCORE = function(msg) GS:Command(msg) end
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(GS.OnEvent, GS, event, ...)
    if not ok then geterrorhandler()(err) end
end)
