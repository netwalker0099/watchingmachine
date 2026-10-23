-- Watching Machine: Loot Browser
-- What every dungeon and raid boss drops, what each profession makes, what
-- each faction sells at each standing, and the PvP rewards: Classic and The
-- Burning Crusade, with Wrath of the Lich King switching on by itself on a
-- Wrath client. Hover an item for its tooltip; shift-click links it,
-- ctrl-click tries it on. Item tooltips everywhere say where the item
-- comes from (boss, faction, PvP, profession).
--
-- The data (Data/Loot*.lua) is only IDs; names, icons and stats come from
-- the client, and each table is built the first time it's shown.

local AddonName, WM = ...
local LB = {}
WM:RegisterModule("LootBrowser", LB)
WM.LootBrowser = LB

LB.version = "3.36"

local DEFAULTS = {
    expansion = nil,       -- expansion shown (0 / 1 / 2; nil: the client's own)
    category = "dungeons", -- dungeons, crafting, factions, pvp
    instance = nil,        -- page shown per data set: { [tag] = id }
    diff = "n",            -- the list shown: n (normal), h (heroic), plate...
    myClassSets = true,    -- set pages: only your class's sets
    followInstance = true, -- open on the instance you're in
    tooltips = true,       -- "Drops from" lines on item tooltips
}
LB.DEFAULTS = DEFAULTS

local function DB()
    LootBrowserDB = LootBrowserDB or {}
    for k, v in pairs(DEFAULTS) do
        if LootBrowserDB[k] == nil then LootBrowserDB[k] = v end
    end
    if type(LootBrowserDB.instance) ~= "table" then LootBrowserDB.instance = {} end
    if type(LootBrowserDB.expansion) ~= "number" then LootBrowserDB.expansion = nil end   -- 3.34 kept a tag
    return LootBrowserDB
end

-- ============================================
-- EXPANSIONS AND DATA
-- ============================================

-- 0 Classic, 1 The Burning Crusade, 2 Wrath of the Lich King
function WM.Expansion()
    local lvl = rawget(_G, "LE_EXPANSION_LEVEL_CURRENT")
    if type(lvl) ~= "number" and type(GetExpansionLevel) == "function" then
        local ok, v = pcall(GetExpansionLevel)
        if ok then lvl = v end
    end
    return tonumber(lvl) or 1
end

local EXPANSION_LABELS = { [0] = "Classic", [1] = "Burning Crusade", [2] = "Wrath of the Lich King" }
local CATEGORIES = {
    { key = "dungeons", label = "Dungeons & Raids", width = 112 },
    { key = "crafting", label = "Crafting", width = 70 },
    { key = "factions", label = "Factions", width = 70 },
    { key = "pvp", label = "PvP", width = 46 },
}
LB.CATEGORIES = CATEGORIES

local built = {}      -- tag -> page list (built on first use)
local lookups = {}    -- sets / crafts tables, built on first use

local function Data() return WM.LootData or {} end

local function Build(tag)
    if built[tag] == nil then
        local d = Data()[tag]
        local ok, list = false, nil
        if type(d) == "table" and type(d.build) == "function" then ok, list = pcall(d.build) end
        built[tag] = (ok and type(list) == "table") and list or false
        if not ok and list then geterrorhandler()(list) end
    end
    return built[tag] or nil
end

-- A base table with Wrath's changes on top (on a Wrath client)
local function Lookup(name, id)
    local t = lookups[name]
    if t == nil then
        local ok, v = false, nil
        if type(Data()[name]) == "function" then ok, v = pcall(Data()[name]) end
        t = (ok and type(v) == "table") and v or {}
        lookups[name] = t
    end
    if WM.Expansion() >= 2 and t.wrath and t.wrath[id] then return t.wrath[id] end
    return t.base and t.base[id] or nil
end
function LB.SetInfo(id) return Lookup("sets", id) end
function LB.CraftInfo(id) return Lookup("crafts", id) end

local function DataSets()
    local out, mine = {}, WM.Expansion()
    for tag, d in pairs(Data()) do
        if type(d) == "table" and type(d.expansion) == "number" and d.expansion <= mine then
            local list = Build(tag)
            if list and #list > 0 then out[#out + 1] = { tag = tag, d = d } end
        end
    end
    return out
end

-- The expansions this client has data for, oldest first:
-- { expansion, label, tags = { [category] = tag } }
function LB:Expansions()
    local by = {}
    for _, x in ipairs(DataSets()) do
        local e = x.d.expansion
        by[e] = by[e] or { expansion = e, label = EXPANSION_LABELS[e] or x.d.label or tostring(e), tags = {} }
        by[e].tags[x.d.category or "dungeons"] = x.tag
    end
    local out = {}
    for _, v in pairs(by) do out[#out + 1] = v end
    table.sort(out, function(a, b) return a.expansion < b.expansion end)
    return out
end

-- The data set for an expansion and category, or nil
function LB:Tag(expansion, category)
    for _, x in ipairs(self:Expansions()) do
        if x.expansion == expansion then return x.tags[category] end
    end
end

local function Available(entry)
    return not entry.expansion or entry.expansion <= WM.Expansion()
end

local function PlayerSide()
    return (UnitFactionGroup and UnitFactionGroup("player")) == "Alliance" and "Alliance" or "Horde"
end

-- The pages of a data set: grouped by kind in the order the kinds first
-- appear (dungeons before raids, ...), extras last; the other side's
-- faction pages left out
function LB:Instances(tag)
    local list = Build(tag)
    if not list then return {} end
    if not list.sorted then
        local first = {}
        for i, inst in ipairs(list) do
            inst.index = i
            if not first[inst.kind] then first[inst.kind] = inst.kind == "extra" and 10000 or i end
        end
        table.sort(list, function(a, b)
            local ka, kb = first[a.kind] or 0, first[b.kind] or 0
            if ka ~= kb then return ka < kb end
            return a.index < b.index
        end)
        list.sorted = true
    end
    local side, out = PlayerSide(), {}
    for _, inst in ipairs(list) do
        if not inst.side or inst.side == side then out[#out + 1] = inst end
    end
    return out
end

function LB:Instance(tag, id)
    for _, inst in ipairs(Build(tag) or {}) do
        if inst.id == id then return inst end
    end
end

local SHARED_NAMES = { dungeons = "Keys and Tier Sets", pvp = "Insignia and Gems" }

-- The client's name for a page where it has one
function LB:InstanceName(inst)
    if inst.faction then
        local f = rawget(_G, "GetFactionInfoByID")
        if type(f) == "function" then
            local ok, n = pcall(f, inst.faction)
            if ok and type(n) == "string" and n ~= "" then return n end
        end
    end
    if inst.area and C_Map and C_Map.GetAreaInfo and inst.kind ~= "world" then
        local ok, n = pcall(C_Map.GetAreaInfo, inst.area)
        if ok and type(n) == "string" and n ~= "" and not inst.id:find("^ScarletMonastery") and not inst.id:find("^DireMaul")
            and inst.id ~= "UpperBlackrockSpire" and inst.id ~= "LowerBlackrockSpire" then
            return n
        end
    end
    if inst.kind == "extra" then
        for _, c in ipairs(CATEGORIES) do
            if inst.id:find(c.key .. "Shared$") and SHARED_NAMES[c.key] then return SHARED_NAMES[c.key] end
        end
    end
    return inst.name
end

function LB:Bosses(inst)
    local out = {}
    for _, b in ipairs(inst and inst.bosses or {}) do
        if Available(b) then out[#out + 1] = b end
    end
    return out
end

-- ============================================
-- LISTS (normal / heroic / plate ...)
-- ============================================

local DIFF_ORDER = { "n", "h", "plate", "mail", "leather", "vendor", "T10_1", "T10_2",
    "majorglyphs", "minorglyphs", "set1", "set2", "set3" }
local DIFF_LABELS = { n = "Normal", h = "Heroic", plate = "Plate", mail = "Mail", leather = "Leather",
    vendor = "Vendor", T10_1 = "25 Raid", T10_2 = "25 Raid Heroic", majorglyphs = "Major Glyphs",
    minorglyphs = "Minor Glyphs", set1 = "Savage", set2 = "Hateful", set3 = "Deadly" }
LB.DIFF_LABELS = DIFF_LABELS
local FACTION_KEYS = { horde = true, alliance = true }

local function FactionKey() return PlayerSide() == "Alliance" and "alliance" or "horde" end

local function ListFor(boss, diff)
    if diff == "n" then return boss.n or boss[FactionKey()] end
    return boss[diff]
end

-- The lists a boss has, in order; your faction's list counts as Normal
function LB:Diffs(boss)
    local out, seen = {}, {}
    for _, d in ipairs(DIFF_ORDER) do
        if ListFor(boss, d) then out[#out + 1] = d; seen[d] = true end
    end
    local extra = {}
    for k, v in pairs(boss) do
        if type(k) == "string" and type(v) == "table" and not seen[k] and not FACTION_KEYS[k] then extra[#extra + 1] = k end
    end
    table.sort(extra)
    for _, k in ipairs(extra) do out[#out + 1] = k end
    return out
end

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function ItemID(e)
    if type(e) == "table" then e = FactionKey() == "alliance" and e[2] or e[1] end
    if e and e > 0 then return e end
end

local function SetName(id)
    local s = LB.SetInfo(id)
    local base = s and s.base or id
    local f = (C_Item and C_Item.GetItemSetInfo) or GetItemSetInfo
    local name
    if f then
        local ok, n = pcall(f, base)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    name = name or ("Set " .. base)
    if s and s.prefix then name = s.prefix .. " " .. name end
    return name
end
LB.SetName = SetName

-- The one class a set is for, or "ALL"
local function SetClass(s)
    local mask = s.classes or 0
    local found
    for token, bit in pairs(CLASS_BITS) do
        if math.floor(mask / bit) % 2 == 1 then
            if found then return "ALL" end
            found = token
        end
    end
    return found or "ALL"
end
LB.SetClass = SetClass

-- What a page shows, in order:
--   { item = id } | { craft = spell ID } | { header = text }
--   { classHeader = class token or "ALL" } then { set = id, name, items }
function LB:Entries(boss, diff, myClassOnly)
    local out = {}
    if not boss then return out end
    local list = ListFor(boss, diff) or ListFor(boss, "n")
    if not list then
        local d = self:Diffs(boss)[1]
        list = d and ListFor(boss, d)
    end
    if boss.set then
        local _, class = UnitClass("player")
        local groups = {}
        for _, e in ipairs(list or {}) do
            local id = ItemID(e)
            local s = id and LB.SetInfo(id)
            if s then
                local c = SetClass(s)
                if not myClassOnly or c == class or c == "ALL" then
                    groups[c] = groups[c] or {}
                    table.insert(groups[c], { set = id, name = SetName(id), items = s })
                end
            end
        end
        local order = {}
        for _, c in ipairs(CLASS_ORDER) do order[#order + 1] = c end
        order[#order + 1] = "ALL"
        for _, c in ipairs(order) do
            if groups[c] then
                out[#out + 1] = { classHeader = c }
                for _, s in ipairs(groups[c]) do out[#out + 1] = s end
            end
        end
        return out
    end
    for _, e in ipairs(list or {}) do
        local id = ItemID(e)
        if id then out[#out + 1] = boss.craft and { craft = id } or { item = id } end
    end
    return out
end

-- The dungeon page (tag, id) for an instance map ID, e.g. the one you're in
function LB:FindByInstanceID(instanceID)
    if not instanceID then return nil end
    for _, x in ipairs(self:Expansions()) do
        local tag = x.tags.dungeons
        for _, inst in ipairs(tag and self:Instances(tag) or {}) do
            if inst.instance == instanceID then return tag, inst.id end
        end
    end
end

-- ============================================
-- PROFESSIONS
-- ============================================

local PROF_NAMES = { "First Aid", "Blacksmithing", "Leatherworking", "Alchemy", "Herbalism", "Cooking", "Mining",
    "Tailoring", "Engineering", "Enchanting", "Fishing", "Skinning", "Poisons", "Jewelcrafting", "Inscription" }
LB.PROF_NAMES = PROF_NAMES

local function SpellInfo(id)
    local f = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    if not f then return nil end
    local ok, a, _, icon = pcall(f, id)
    if not ok then return nil end
    if type(a) == "table" then return a.name, a.iconID end
    return a, icon
end

-- "Alchemy 375"
function LB.CraftSkill(id)
    local c = LB.CraftInfo(id)
    if not c then return "" end
    return (PROF_NAMES[c[2]] or "") .. " " .. (c[3] or "")
end

-- ============================================
-- WHERE ITEMS COME FROM
-- ============================================
-- { cat, tag, instance, boss, diff, craft } per source, for tooltips

local sourceIndex
local function AddSource(id, src)
    if not id or id <= 0 then return end
    local list = sourceIndex[id]
    if not list then list = {}; sourceIndex[id] = list end
    list[#list + 1] = src
end

function LB:Sources(itemID)
    if not sourceIndex then
        sourceIndex = {}
        for _, x in ipairs(self:Expansions()) do
            for cat, tag in pairs(x.tags) do
                for _, inst in ipairs(self:Instances(tag)) do
                    if inst.kind ~= "extra" then
                        for _, b in ipairs(self:Bosses(inst)) do
                            for k, list in pairs(b) do
                                if type(k) == "string" and type(list) == "table" then
                                    local diff = k == "h" and "h" or "n"
                                    for _, e in ipairs(list) do
                                        for _, id in ipairs(type(e) == "table" and e or { e }) do
                                            local src = { cat = cat, tag = tag, instance = inst, boss = b, diff = diff }
                                            if b.craft then
                                                local c = LB.CraftInfo(id)
                                                if c then src.craft = id; AddSource(c[1], src) end
                                            elseif b.set then
                                                if cat ~= "dungeons" then
                                                    for _, piece in ipairs(LB.SetInfo(id) or {}) do AddSource(piece, src) end
                                                end
                                            else
                                                AddSource(id, src)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return sourceIndex[itemID] or {}
end

-- ============================================
-- ITEM TOOLTIPS
-- ============================================
-- One block per kind of source, up to MAX_SOURCES lines each:
--   Drops from:          Attumen the Huntsman (Karazhan)
--   Reputation reward:   The Aldor (Exalted)
--   PvP reward:          Arena Season 1 (Sets)
--   Made by:             Alchemy (375)

local MAX_SOURCES = 3
local SOURCE_COLOR, PLACE_COLOR = "FFB366", "AAAAAA"
local SOURCE_HEADS = { dungeons = "Drops from:", factions = "Reputation reward:", pvp = "PvP reward:", crafting = "Made by:" }
local SOURCE_ORDER = { "dungeons", "factions", "pvp", "crafting" }

local function SourceLine(g)
    local s = g.first
    if s.cat == "dungeons" then
        local where = LB:InstanceName(s.instance)
        if g.diffs.h and not g.diffs.n then where = where .. ", Heroic" end
        return "|cFFFFFFFF" .. s.boss[1] .. "|r |cFF" .. PLACE_COLOR .. "(" .. where .. ")|r"
    elseif s.cat == "crafting" then
        local c = LB.CraftInfo(s.craft)
        return "|cFFFFFFFF" .. (PROF_NAMES[c and c[2]] or LB:InstanceName(s.instance)) .. "|r |cFF" .. PLACE_COLOR
            .. "(" .. (c and c[3] or "?") .. ")|r"
    end
    return "|cFFFFFFFF" .. LB:InstanceName(s.instance) .. "|r |cFF" .. PLACE_COLOR .. "(" .. s.boss[1] .. ")|r"
end

function LB:SourceLines(itemID)
    local list = self:Sources(itemID)
    if #list == 0 then return nil end
    local by = {}
    for _, s in ipairs(list) do
        local cat = by[s.cat]
        if not cat then cat = { groups = {}, order = {} }; by[s.cat] = cat end
        local key = s.craft or s.boss
        local g = cat.groups[key]
        if not g then
            g = { first = s, diffs = {} }
            cat.groups[key] = g
            cat.order[#cat.order + 1] = g
        end
        g.diffs[s.diff] = true
    end
    local lines = {}
    for _, c in ipairs(SOURCE_ORDER) do
        local cat = by[c]
        if cat then
            lines[#lines + 1] = "|cFF" .. SOURCE_COLOR .. SOURCE_HEADS[c] .. "|r"
            for i, g in ipairs(cat.order) do
                if i > MAX_SOURCES then
                    lines[#lines + 1] = "   |cFF" .. PLACE_COLOR .. "and " .. (#cat.order - MAX_SOURCES) .. " more|r"
                    break
                end
                lines[#lines + 1] = "   " .. SourceLine(g)
            end
        end
    end
    return lines
end

local function ItemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Add the lines once per tooltip showing (both hooks below may fire)
function LB:AddTooltipSource(tooltip, itemID)
    if not DB().tooltips or not tooltip or not itemID then return false end
    if tooltip.wmLootSource == itemID then return false end
    tooltip.wmLootSource = itemID
    local lines = self:SourceLines(itemID)
    if not lines then return false end
    for _, l in ipairs(lines) do tooltip:AddLine(l) end
    if tooltip.Show then tooltip:Show() end   -- resize to the new lines
    return true
end

local hookedTips = {}
local function HookTooltip(tip)
    if type(tip) ~= "table" or hookedTips[tip] or not tip.HookScript then return end
    hookedTips[tip] = true
    tip:HookScript("OnTooltipCleared", function(t) t.wmLootSource = nil end)
    if not tip.HasScript or tip:HasScript("OnTooltipSetItem") then
        tip:HookScript("OnTooltipSetItem", function(t)
            if not t.GetItem then return end
            local ok, _, link = pcall(t.GetItem, t)
            if ok then LB:AddTooltipSource(t, ItemIDFromLink(link)) end
        end)
    end
end

function LB:HookTooltips()
    if self.tooltipsHooked then return end
    self.tooltipsHooked = true
    -- Newer clients route item tooltips through TooltipDataProcessor
    local proc = rawget(_G, "TooltipDataProcessor")
    local enum = rawget(_G, "Enum")
    if type(proc) == "table" and type(proc.AddTooltipPostCall) == "function" and type(enum) == "table"
        and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item then
        proc.AddTooltipPostCall(enum.TooltipDataType.Item, function(tip, data)
            if tip and type(data) == "table" then
                local ok, err = pcall(LB.AddTooltipSource, LB, tip, tonumber(data.id))
                if not ok then geterrorhandler()(err) end
            end
        end)
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        HookTooltip(rawget(_G, name))
    end
end

-- ============================================
-- ITEMS
-- ============================================

local QUALITY_HEX = { [0] = "9D9D9D", [1] = "FFFFFF", [2] = "1EFF00", [3] = "0070DD", [4] = "A335EE", [5] = "FF8000", [6] = "E6CC80", [7] = "00CCFF" }

local function ItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, name, link, quality = pcall(f, id)
    if ok and type(name) == "string" then return name, link, tonumber(quality) end
end

local function ItemInstant(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, itemType, subType, equipLoc, icon = pcall(f, id)
    if ok then return itemType, subType, equipLoc, icon end
end

-- "Head, Plate" / "Trinket" / "Recipe"
function LB.ItemKind(id)
    local itemType, subType, equipLoc = ItemInstant(id)
    local slot = type(equipLoc) == "string" and equipLoc ~= "" and rawget(_G, equipLoc)
    if type(slot) == "string" then
        if type(subType) == "string" and subType ~= "" and subType ~= "Miscellaneous" and equipLoc ~= "INVTYPE_CLOAK"
            and equipLoc ~= "INVTYPE_FINGER" and equipLoc ~= "INVTYPE_NECK" and equipLoc ~= "INVTYPE_TRINKET" then
            return slot .. ", " .. subType
        end
        return slot
    end
    return type(subType) == "string" and subType ~= "" and subType or (type(itemType) == "string" and itemType or "")
end

function LB.ItemText(id)
    local name, _, quality = ItemInfo(id)
    if not name then return "|cFF888888Item " .. id .. "|r", false end
    return "|cFF" .. (QUALITY_HEX[quality or 1] or "FFFFFF") .. name .. "|r", true
end

local function ItemLink(id)
    local _, link = ItemInfo(id)
    return link or ("item:" .. id)
end

local function ClassLabel(token)
    if token == "ALL" then return "|cFFFFD100Every class|r" end
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    local name = type(names) == "table" and names[token] or (token:sub(1, 1) .. token:sub(2):lower())
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    local c = type(colors) == "table" and colors[token]
    if c and c.r then
        return string.format("|cFF%02X%02X%02X%s|r", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
    end
    return name
end
LB.ClassLabel = ClassLabel

-- ============================================
-- WINDOW
-- ============================================

local panel
local ROW_H, ITEM_H, SET_H, PIECE = 18, 30, 30, 26
local MAX_PIECES = 10
local state = { exp = nil, cat = nil, inst = nil, boss = 1 }

local function CurrentExpansion()
    local list = LB:Expansions()
    if #list == 0 then return nil end
    local want = state.exp or DB().expansion
    for _, x in ipairs(list) do if x.expansion == want then return x end end
    local mine, best = WM.Expansion(), list[1]
    for _, x in ipairs(list) do if x.expansion <= mine and x.tags.dungeons then best = x end end
    return best
end

-- The data set shown (and its expansion and category)
local function CurrentTag()
    local x = CurrentExpansion()
    if not x then return nil end
    local cat = state.cat or DB().category or "dungeons"
    if not x.tags[cat] then
        for _, c in ipairs(CATEGORIES) do if x.tags[c.key] then cat = c.key; break end end
    end
    state.exp, state.cat = x.expansion, cat
    return x.tags[cat], x, cat
end

local function CurrentInstance(tag)
    local list = LB:Instances(tag)
    local id = state.inst or DB().instance[tag]
    for _, inst in ipairs(list) do if inst.id == id then return inst end end
    return list[1]
end

-- A clickable list (pages, bosses) of plain text rows
local function NewList(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(150, 1)
    scroll:SetScrollChild(child)
    scroll.child, scroll.rows = child, {}
    function scroll:Row(i)
        local r = self.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, child)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(0.3, 0.6, 1, 0.25)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 4, 0)
        r.text:SetPoint("RIGHT", -2, 0)
        r.text:SetJustifyH("LEFT")
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        self.rows[i] = r
        return r
    end
    function scroll:Fill(items, selected, onClick)
        local w = (self:GetWidth() or 150)
        child:SetWidth(math.max(50, w))
        for i, it in ipairs(items) do
            local r = self:Row(i)
            r.text:SetText(it.text)
            r.hl:SetShown(i == selected)
            r.value = it.value
            r:SetScript("OnClick", function() onClick(it.value, i) end)
            if it.tooltip then
                r:SetScript("OnEnter", function(b) WM.UI.ShowTooltip(b, it.tooltip) end)
                r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                r:SetScript("OnEnter", nil)
                r:SetScript("OnLeave", nil)
            end
            r:Show()
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide() end
        child:SetHeight(math.max(1, #items * ROW_H))
    end
    return scroll
end

-- Tooltip for an item, or for a craft (what it makes, then the skill,
-- reagents and the recipe that teaches it)
local function ItemEnter(b)
    if not (b.itemID or b.craftID) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local c = b.craftID and LB.CraftInfo(b.craftID)
    local made = b.itemID or (c and c[1] and c[1] > 0 and c[1])
    if made then
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(made) else GameTooltip:SetHyperlink("item:" .. made) end
    elseif b.craftID then
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(b.craftID) else GameTooltip:SetHyperlink("enchant:" .. b.craftID) end
    end
    if c then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFD100Requires " .. (PROF_NAMES[c[2]] or "?") .. " (" .. (c[3] or "?") .. ")|r")
        local r = c.r or {}
        for i = 1, #r, 2 do
            local name = ItemInfo(r[i]) or ("Item " .. r[i])
            GameTooltip:AddLine("   " .. (r[i + 1] or 1) .. " x " .. name, 1, 1, 1)
        end
        if c.t then
            local name = ItemInfo(c.t) or ("Item " .. c.t)
            GameTooltip:AddLine("|cFF888888Taught by " .. name .. "|r")
        end
    end
    GameTooltip:Show()
end

local function ItemClick(b)
    local c = b.craftID and LB.CraftInfo(b.craftID)
    local id = b.itemID or (c and c[1] and c[1] > 0 and c[1])
    if id then
        local link = ItemLink(id)
        if HandleModifiedItemClick and link:find("|H") then HandleModifiedItemClick(link) end
    elseif b.craftID and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
        local f = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
        local link = f and f(b.craftID)
        if link then ChatEdit_InsertLink(link) end
    end
end

local function ItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ITEM_H)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ITEM_H - 4, ITEM_H - 4)
    b.icon:SetPoint("LEFT", 2, 0)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -1)
    b.name:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.name:SetJustifyH("LEFT")
    b.kind = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.kind:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 1)
    b.kind:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.kind:SetJustifyH("LEFT")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnEnter", ItemEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", ItemClick)
    return b
end

-- One set on one line: its name, then an icon per piece
local function SetRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(SET_H)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("LEFT", 4, 0)
    r.name:SetJustifyH("LEFT")
    r.pieces = {}
    for i = 1, MAX_PIECES do
        local p = CreateFrame("Button", nil, r)
        p:SetSize(PIECE, PIECE)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        p:SetScript("OnEnter", ItemEnter)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:SetScript("OnClick", ItemClick)
        r.pieces[i] = p
    end
    return r
end

-- Lay the page's entries out: items and crafts in one or two columns,
-- headers and sets across the width
function LB:FillItems(entries)
    local area = panel.itemChild
    local width = math.max(200, panel.itemScroll:GetWidth() or 400)
    local cols = width >= 520 and 2 or 1
    local colW = math.floor(width / cols)
    area:SetWidth(width)
    panel.itemButtons = panel.itemButtons or {}
    panel.setRows = panel.setRows or {}
    local y, col, pending = 0, 0, false
    local used, usedSets = 0, 0
    local nameW = math.min(260, math.max(120, width - MAX_PIECES * (PIECE + 2) - 8))
    local function NewLine() if col > 0 then y = y + ITEM_H; col = 0 end end
    for _, e in ipairs(entries) do
        if e.set then
            NewLine()
            usedSets = usedSets + 1
            local r = panel.setRows[usedSets]
            if not r then r = SetRow(area); panel.setRows[usedSets] = r end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
            r:SetWidth(width)
            r.setID = e.set
            r.name:SetWidth(nameW)
            r.name:SetText("|cFFFFFFFF" .. e.name .. "|r")
            for i, p in ipairs(r.pieces) do
                local id = e.items[i]
                p:ClearAllPoints()
                if id then
                    p:SetPoint("LEFT", r, "LEFT", 8 + nameW + (i - 1) * (PIECE + 2), 0)
                    local _, _, _, icon = ItemInstant(id)
                    p.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    p.itemID = id
                    p:Show()
                else
                    p.itemID = nil
                    p:Hide()
                end
            end
            r:Show()
            y = y + SET_H
        else
            used = used + 1
            local b = panel.itemButtons[used]
            if not b then b = ItemButton(area); panel.itemButtons[used] = b end
            b:ClearAllPoints()
            b.itemID, b.craftID = nil, nil
            if e.header or e.classHeader then
                NewLine()
                b:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
                b:SetWidth(width)
                b:SetHeight(e.classHeader and 22 or ITEM_H)
                b.icon:Hide()
                b.name:SetText(e.classHeader and ClassLabel(e.classHeader) or ("|cFFFFD100" .. e.header .. "|r"))
                b.kind:SetText("")
                y = y + (e.classHeader and 22 or ITEM_H)
            else
                b:SetPoint("TOPLEFT", area, "TOPLEFT", col * colW, -y)
                b:SetWidth(colW - 4)
                b:SetHeight(ITEM_H)
                b.icon:Show()
                local text, known, icon, kind
                if e.craft then
                    b.craftID = e.craft
                    local c = LB.CraftInfo(e.craft)
                    local made = c and c[1] and c[1] > 0 and c[1]
                    if made then
                        text, known = LB.ItemText(made)
                        icon = select(4, ItemInstant(made))
                    else
                        local name, sIcon = SpellInfo(e.craft)
                        text, known, icon = name and ("|cFFFFFFFF" .. name .. "|r") or ("|cFF888888Spell " .. e.craft .. "|r"), true, sIcon
                    end
                    kind = LB.CraftSkill(e.craft)
                else
                    b.itemID = e.item
                    text, known = LB.ItemText(e.item)
                    icon = select(4, ItemInstant(e.item))
                    kind = LB.ItemKind(e.item)
                end
                if not known then pending = true end
                b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                b.name:SetText(text)
                b.kind:SetText(kind)
                col = col + 1
                if col >= cols then col = 0; y = y + ITEM_H end
            end
            b:Show()
        end
    end
    if col > 0 then y = y + ITEM_H end
    for i = used + 1, #panel.itemButtons do
        local b = panel.itemButtons[i]
        b:Hide(); b.itemID, b.craftID = nil, nil
    end
    for i = usedSets + 1, #panel.setRows do panel.setRows[i]:Hide(); panel.setRows[i].setID = nil end
    area:SetHeight(math.max(1, y))
    panel.waitingForItems = pending
    return used + usedSets
end

local KIND_COLORS = { raid = "FF9933", extra = "AAAAAA", minor = "AAAAAA", arena = "FF6666", world = "66CC66",
    gathering = "AAAAAA", secondary = "AAAAAA", class = "AAAAAA" }

function LB:RefreshDiffButtons(diffs, cur)
    local bar = panel.diffBar
    local x = bar.label:GetStringWidth() and (bar.label:GetStringWidth() + 6) or 40
    for i, btn in ipairs(bar.buttons) do
        local d = diffs[i]
        if d and #diffs > 1 then
            local label = DIFF_LABELS[d] or d
            btn:SetText(d == cur and ("|cFF00FF00" .. label .. "|r") or label)
            btn:SetWidth(math.max(54, #label * 7 + 16))
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", bar, "LEFT", x, 0)
            x = x + btn:GetWidth() + 2
            btn.diff = d
            btn:Show()
        else
            btn.diff = nil
            btn:Hide()
        end
    end
    bar:SetShown(#diffs > 1)
end

function LB:RefreshList()
    if not panel then return end
    local tag, x, cat = CurrentTag()
    if not tag then
        panel.status:SetText("|cFF888888No loot data for this client.|r")
        return
    end
    for i, c in ipairs(CATEGORIES) do
        local btn = panel.catBox.buttons[i]
        if btn then btn:SetShown(x.tags[c.key] ~= nil) end
    end
    if panel.catBox.Refresh then panel.catBox:Refresh() end
    local inst = CurrentInstance(tag)
    state.inst = inst and inst.id
    -- pages
    local items, sel = {}, nil
    for _, i in ipairs(self:Instances(tag)) do
        local label = self:InstanceName(i)
        if KIND_COLORS[i.kind] then label = "|cFF" .. KIND_COLORS[i.kind] .. label .. "|r" end
        if i.phase then label = label .. " |cFF888888(P" .. i.phase .. ")|r" end
        local tip
        if i.levels then tip = { self:InstanceName(i), "Levels " .. (i.levels[2] or i.levels[1]) .. "-" .. (i.levels[3] or i.levels[2] or "") } end
        items[#items + 1] = { text = label, value = i.id, tooltip = tip }
        if i == inst then sel = #items end
    end
    panel.instList:Fill(items, sel, function(id)
        state.inst, state.boss = id, 1
        DB().instance[tag] = id
        LB:RefreshList()
    end)
    -- bosses / sections
    local bosses = self:Bosses(inst)
    if state.boss > #bosses then state.boss = 1 end
    local bitems = {}
    for _, b in ipairs(bosses) do
        local label = b[1]
        if b.extra then label = "|cFFAAAAAA" .. label .. "|r"
        elseif b.special == "rare" then label = label .. " |cFF888888(rare)|r"
        elseif b.special == "quest" then label = label .. " |cFF888888(quest)|r" end
        if b.phase then label = label .. " |cFF888888(P" .. b.phase .. ")|r" end
        bitems[#bitems + 1] = { text = label, value = b }
    end
    panel.bossList:Fill(bitems, state.boss, function(_, i)
        state.boss = i
        LB:RefreshList()
    end)
    -- loot
    local boss = bosses[state.boss]
    local diffs = boss and self:Diffs(boss) or {}
    local diff = DB().diff
    local has = {}
    for _, d in ipairs(diffs) do has[d] = true end
    if not has[diff] then diff = diffs[1] or "n" end
    state.diff = diff
    self:RefreshDiffButtons(diffs, diff)
    local n = self:FillItems(self:Entries(boss, diff, DB().myClassSets))
    local title = boss and boss[1] or ""
    panel.status:SetText((inst and ("|cFFFFFFFF" .. self:InstanceName(inst) .. "|r") or "")
        .. (boss and ("  -  " .. title) or "") .. (#diffs > 1 and ("  |cFF66FF66(" .. (DIFF_LABELS[diff] or diff) .. ")|r") or ""))
    return n
end

function LB:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_LootBrowserFrame", title = "Loot Browser", titleColor = "FFB366",
        width = 860, height = 540, scroll = false,
        resizable = { 680, 380, 1600, 1400 },
        onResize = function() LB:RefreshList() end,
        onRefresh = function() LB:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(26)
    top:Dropdown({
        label = "Expansion:", width = 150,
        options = function()
            local o = {}
            for _, x in ipairs(LB:Expansions()) do o[#o + 1] = { value = x.expansion, text = x.label } end
            return o
        end,
        get = function() local x = CurrentExpansion(); return x and x.expansion end,
        set = function(v)
            state.exp, state.inst, state.boss = v, nil, 1
            DB().expansion = v
            LB:RefreshList()
        end,
    }, 4)
    local opts = {}
    for _, c in ipairs(CATEGORIES) do opts[#opts + 1] = { value = c.key, text = c.label, width = c.width } end
    panel.catBox = top:Choice({
        label = "Show:", options = opts,
        get = function() return state.cat or DB().category end,
        set = function(v)
            state.cat, state.inst, state.boss = v, nil, 1
            DB().category = v
            LB:RefreshList()
        end,
    }, 262)

    local second = L:Row(24)
    local bar = CreateFrame("Frame", nil, second.frame)
    bar:SetPoint("LEFT", 8, 0)
    bar:SetSize(420, 20)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", 0, 0)
    bar.label:SetText("|cFF888888Loot:|r")
    bar.buttons = {}
    for i = 1, 6 do
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetSize(60, 18)
        btn:SetScript("OnClick", function(self)
            if not self.diff then return end
            DB().diff = self.diff
            LB:RefreshList()
        end)
        bar.buttons[i] = btn
    end
    panel.diffBar = bar
    second:Checkbox({
        label = "Sets: my class only",
        get = function() return DB().myClassSets end,
        set = function(v) DB().myClassSets = v; LB:RefreshList() end,
        tooltip = { "Set pages", "Show only the sets your class can wear. Off: every class's sets, grouped by class." },
    }, 430)
    second:Checkbox({
        label = "Item tooltips",
        get = function() return DB().tooltips end,
        set = function(v) DB().tooltips = v end,
        tooltip = { "Item tooltips", "Add where an item comes from to item tooltips everywhere (bags, chat links,"
            .. " the auction house): the bosses that drop it, the faction or PvP vendor, or the profession that makes it." },
    }, 600)
    local st = L:Row(18)
    panel.status = st:Text({ text = "" }, 8)

    local fill = L:Fill(200)
    panel.instList = NewList(fill, "WM_LootBrowserInstances")
    panel.instList:SetPoint("TOPLEFT", 0, -2)
    panel.instList:SetPoint("BOTTOMLEFT", 0, 0)
    panel.instList:SetWidth(190)
    panel.bossList = NewList(fill, "WM_LootBrowserBosses")
    panel.bossList:SetPoint("TOPLEFT", panel.instList, "TOPRIGHT", 26, 0)
    panel.bossList:SetPoint("BOTTOMLEFT", panel.instList, "BOTTOMRIGHT", 26, 0)
    panel.bossList:SetWidth(190)
    local items = CreateFrame("ScrollFrame", "WM_LootBrowserItems", fill, "UIPanelScrollFrameTemplate")
    items:SetPoint("TOPLEFT", panel.bossList, "TOPRIGHT", 26, 0)
    items:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, items)
    child:SetSize(400, 1)
    items:SetScrollChild(child)
    panel.itemScroll, panel.itemChild = items, child

    panel:AddFooterText({ text = "|cFF888888Shift-click to link, Ctrl-click to try on.|r" }, "LEFT")
    panel:Finish()
    return panel
end

function LB:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

-- Open on a page of a data set
function LB:Show(tag, instID)
    local p = self:CreateUI()
    local d = tag and Data()[tag]
    if d then state.exp, state.cat, state.inst, state.boss = d.expansion, d.category or "dungeons", instID, 1 end
    if not p:IsShown() then p:Show() else self:RefreshList() end
end

function LB:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide(); return end
    if DB().followInstance and IsInInstance then
        local inInstance = IsInInstance()
        if inInstance and GetInstanceInfo then
            local instanceID = select(8, GetInstanceInfo())
            local tag, id = self:FindByInstanceID(tonumber(instanceID))
            local d = tag and Data()[tag]
            if d then state.exp, state.cat, state.inst, state.boss = d.expansion, "dungeons", id, 1 end
        end
    end
    p:Show()
end
LB.ToggleUI = LB.Toggle

function LB:GetQuickStatus()
    local n = 0
    for _, x in ipairs(self:Expansions()) do
        if x.tags.dungeons then n = n + #self:Instances(x.tags.dungeons) end
    end
    return n .. " instances"
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local refreshQueued = false

function LB:OnItemInfo()
    if not (panel and panel:IsShown() and panel.waitingForItems) or refreshQueued then return end
    refreshQueued = true
    WM.RunAfter(0.3, function()
        refreshQueued = false
        LB:RefreshList()
    end)
end

function LB:Initialize()
    DB()
    WM:RegisterEvents(events, { "GET_ITEM_INFO_RECEIVED" })
    self:HookTooltips()
end

events:SetScript("OnEvent", function()
    local ok, err = pcall(LB.OnItemInfo, LB)
    if not ok then geterrorhandler()(err) end
end)
