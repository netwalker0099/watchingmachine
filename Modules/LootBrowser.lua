-- Watching Machine: Loot Browser
-- What every dungeon and raid boss drops, for Classic and The Burning
-- Crusade, with Wrath of the Lich King switching on by itself on a Wrath
-- client. Pick an instance and a boss to see its loot (normal or heroic),
-- tier and dungeon sets, keys and trash. Hover an item for its tooltip;
-- shift-click links it, ctrl-click tries it on.
--
-- The data (Data/Loot*.lua) is only item IDs per boss; names, icons and
-- stats come from the client, and each expansion's tables are built the
-- first time they're shown.

local AddonName, WM = ...
local LB = {}
WM:RegisterModule("LootBrowser", LB)
WM.LootBrowser = LB

LB.version = "3.34"

local DEFAULTS = {
    expansion = nil,       -- tag of the expansion shown (nil: the client's own)
    instance = nil,        -- instance id shown, per expansion: { [tag] = id }
    diff = "n",            -- n (normal) or h (heroic)
    myClassSets = true,    -- set pages: only your class's sets
    followInstance = true, -- open on the instance you're in
}
LB.DEFAULTS = DEFAULTS

local function DB()
    LootBrowserDB = LootBrowserDB or {}
    for k, v in pairs(DEFAULTS) do
        if LootBrowserDB[k] == nil then LootBrowserDB[k] = v end
    end
    if type(LootBrowserDB.instance) ~= "table" then LootBrowserDB.instance = {} end
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

local built = {}      -- tag -> instance list (built on first use)
local setData

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

local function Sets()
    if setData == nil then
        local ok, t = false, nil
        if type(Data().sets) == "function" then ok, t = pcall(Data().sets) end
        setData = (ok and type(t) == "table") and t or {}
    end
    return setData
end

-- Expansions this client has, with data: { tag, label, expansion }, oldest first
function LB:Expansions()
    local out, mine = {}, WM.Expansion()
    for tag, d in pairs(Data()) do
        if type(d) == "table" and type(d.expansion) == "number" and d.expansion <= mine then
            local list = Build(tag)
            if list and #list > 0 then out[#out + 1] = { tag = tag, label = d.label or tag, expansion = d.expansion, order = d.order or 0 } end
        end
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

local function Available(entry)
    return not entry.expansion or entry.expansion <= WM.Expansion()
end

-- The instances of one expansion: dungeons, raids, then extras (each in level order)
local KIND_ORDER = { dungeon = 1, raid = 2, extra = 3 }
function LB:Instances(tag)
    local list = Build(tag)
    if not list then return {} end
    if not list.sorted then
        for i, inst in ipairs(list) do inst.index = i end
        table.sort(list, function(a, b)
            local ka, kb = KIND_ORDER[a.kind] or 9, KIND_ORDER[b.kind] or 9
            if ka ~= kb then return ka < kb end
            return a.index < b.index
        end)
        list.sorted = true
    end
    return list
end

function LB:Instance(tag, id)
    for _, inst in ipairs(self:Instances(tag)) do
        if inst.id == id then return inst end
    end
end

-- The client's name for an instance where it has one
function LB:InstanceName(inst)
    if inst.area and C_Map and C_Map.GetAreaInfo then
        local ok, n = pcall(C_Map.GetAreaInfo, inst.area)
        if ok and type(n) == "string" and n ~= "" and not inst.id:find("^ScarletMonastery") and not inst.id:find("^DireMaul")
            and inst.id ~= "UpperBlackrockSpire" and inst.id ~= "LowerBlackrockSpire" then
            return n
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

-- The loot lists a boss has, in order: { "n", "h" } (faction lists count as n)
local DIFF_KEYS = { "n", "h" }
local function FactionKey()
    return (UnitFactionGroup and UnitFactionGroup("player")) == "Alliance" and "alliance" or "horde"
end
local function ListFor(boss, diff)
    if diff == "h" then return boss.h, boss.sets_h end
    return boss.n or boss[FactionKey()] or boss.horde or boss.alliance, boss.sets
end
function LB:Diffs(boss)
    local out = {}
    for _, d in ipairs(DIFF_KEYS) do
        local items, sets = ListFor(boss, d)
        if items or sets then out[#out + 1] = d end
    end
    return out
end

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }

local function ItemID(e)
    if type(e) == "table" then return FactionKey() == "alliance" and e[2] or e[1] end
    return e
end

local function SetName(id)
    local f = (C_Item and C_Item.GetItemSetInfo) or GetItemSetInfo
    if f then
        local ok, n = pcall(f, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return "Set " .. id
end

-- What a page shows: { { item = id } | { header = text } }
function LB:Entries(boss, diff, myClassOnly)
    local out = {}
    if not boss then return out end
    local items, sets = ListFor(boss, diff)
    if not items and not sets then items, sets = ListFor(boss, "n") end
    for _, e in ipairs(items or {}) do
        local id = ItemID(e)
        if id then out[#out + 1] = { item = id } end
    end
    if sets then
        local _, class = UnitClass("player")
        local bit = CLASS_BITS[class or ""]
        local data = Sets()
        for _, setID in ipairs(sets) do
            local s = data[setID]
            if s then
                local mask = s.classes or 0
                local mine = not bit or mask == 0 or math.floor(mask / bit) % 2 == 1
                if mine or not myClassOnly then
                    out[#out + 1] = { header = SetName(setID), set = setID }
                    for _, id in ipairs(s) do out[#out + 1] = { item = id } end
                end
            end
        end
    end
    return out
end

-- The instance (tag, id) for an instance map ID, e.g. the one you're in
function LB:FindByInstanceID(instanceID)
    if not instanceID then return nil end
    for _, x in ipairs(self:Expansions()) do
        for _, inst in ipairs(self:Instances(x.tag)) do
            if inst.instance == instanceID then return x.tag, inst.id end
        end
    end
end

-- Where an item drops: { { tag, instance, boss, diff } }, for tooltips and search
local sourceIndex
function LB:Sources(itemID)
    if not sourceIndex then
        sourceIndex = {}
        for _, x in ipairs(self:Expansions()) do
            for _, inst in ipairs(self:Instances(x.tag)) do
                if inst.kind ~= "extra" then
                    for _, b in ipairs(self:Bosses(inst)) do
                        for _, d in ipairs({ "n", "h", "horde", "alliance" }) do
                            for _, e in ipairs(b[d] or {}) do
                                for _, id in ipairs(type(e) == "table" and e or { e }) do
                                    local list = sourceIndex[id]
                                    if not list then list = {}; sourceIndex[id] = list end
                                    list[#list + 1] = { tag = x.tag, instance = inst, boss = b, diff = d == "h" and "h" or "n" }
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

-- ============================================
-- WINDOW
-- ============================================

local panel
local ROW_H, ITEM_H = 18, 30
local state = { tag = nil, inst = nil, boss = 1 }

local function CurrentTag()
    local list = LB:Expansions()
    if #list == 0 then return nil end
    local want = state.tag or DB().expansion
    for _, x in ipairs(list) do if x.tag == want then return want end end
    local mine = WM.Expansion()
    local best = list[1].tag
    for _, x in ipairs(list) do if x.expansion <= mine then best = x.tag end end
    return best
end

local function CurrentInstance(tag)
    local list = LB:Instances(tag)
    local id = state.inst or DB().instance[tag]
    return LB:Instance(tag, id) or list[1]
end

-- A clickable list (instances, bosses) of plain text rows
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

local function ItemEnter(b)
    if not b.itemID then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(b.itemID)
    else
        GameTooltip:SetHyperlink("item:" .. b.itemID)
    end
    GameTooltip:Show()
end

local function ItemClick(b)
    if not b.itemID then return end
    local link = ItemLink(b.itemID)
    if HandleModifiedItemClick and link:find("|H") then HandleModifiedItemClick(link) end
end

local function ItemButton(parent, i)
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

-- Lay the page's entries out in one or two columns
function LB:FillItems(entries)
    local area = panel.itemChild
    local width = math.max(200, panel.itemScroll:GetWidth() or 400)
    local cols = width >= 520 and 2 or 1
    local colW = math.floor(width / cols)
    area:SetWidth(width)
    panel.itemButtons = panel.itemButtons or {}
    local y, col, pending, rowTop = 0, 0, false, 0
    local used = 0
    for _, e in ipairs(entries) do
        used = used + 1
        local b = panel.itemButtons[used]
        if not b then b = ItemButton(area, used); panel.itemButtons[used] = b end
        b:ClearAllPoints()
        if e.header then
            if col > 0 then y = y + ITEM_H; col = 0 end
            b:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -y)
            b:SetWidth(width)
            b.icon:Hide()
            b.itemID = nil
            b.name:SetText("|cFFFFD100" .. e.header .. "|r")
            b.kind:SetText("")
            y = y + ITEM_H
        else
            b:SetPoint("TOPLEFT", area, "TOPLEFT", col * colW, -y)
            b:SetWidth(colW - 4)
            b.icon:Show()
            b.itemID = e.item
            local _, _, _, icon = ItemInstant(e.item)
            b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local text, known = LB.ItemText(e.item)
            if not known then pending = true end
            b.name:SetText(text)
            b.kind:SetText(LB.ItemKind(e.item))
            col = col + 1
            if col >= cols then col = 0; y = y + ITEM_H end
        end
        b:Show()
    end
    if col > 0 then y = y + ITEM_H end
    for i = used + 1, #panel.itemButtons do panel.itemButtons[i]:Hide(); panel.itemButtons[i].itemID = nil end
    area:SetHeight(math.max(1, y))
    panel.waitingForItems = pending
    return used
end

function LB:RefreshList()
    if not panel then return end
    local tag = CurrentTag()
    if not tag then
        panel.status:SetText("|cFF888888No loot data for this client.|r")
        return
    end
    state.tag = tag
    local inst = CurrentInstance(tag)
    state.inst = inst and inst.id
    -- instances
    local items, sel = {}, nil
    for _, i in ipairs(self:Instances(tag)) do
        local label = self:InstanceName(i)
        if i.kind == "raid" then label = "|cFFFF9933" .. label .. "|r"
        elseif i.kind == "extra" then label = "|cFFAAAAAA" .. label .. "|r" end
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
    -- bosses
    local bosses = self:Bosses(inst)
    if state.boss > #bosses then state.boss = 1 end
    local bitems = {}
    for _, b in ipairs(bosses) do
        local label = b[1]
        if b.extra then label = "|cFFAAAAAA" .. label .. "|r"
        elseif b.special == "rare" then label = label .. " |cFF888888(rare)|r"
        elseif b.special == "quest" then label = label .. " |cFF888888(quest)|r" end
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
    panel.diffBox:SetShown(has.h and true or false)
    if panel.diffBox.Refresh then panel.diffBox:Refresh() end
    local n = self:FillItems(self:Entries(boss, diff, DB().myClassSets))
    local title = boss and boss[1] or ""
    panel.status:SetText((inst and ("|cFFFFFFFF" .. self:InstanceName(inst) .. "|r") or "")
        .. (boss and ("  -  " .. title) or "") .. (has.h and (diff == "h" and "  |cFFFF6666(Heroic)|r" or "  |cFF66FF66(Normal)|r") or ""))
    return n
end

function LB:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_LootBrowserFrame", title = "Loot Browser", titleColor = "FFB366",
        width = 860, height = 520, scroll = false,
        resizable = { 640, 360, 1600, 1400 },
        onResize = function() LB:RefreshList() end,
        onRefresh = function() LB:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(26)
    top:Dropdown({
        label = "Expansion:", width = 150,
        options = function()
            local o = {}
            for _, x in ipairs(LB:Expansions()) do o[#o + 1] = { value = x.tag, text = x.label } end
            return o
        end,
        get = function() return CurrentTag() end,
        set = function(v)
            state.tag, state.inst, state.boss = v, nil, 1
            DB().expansion = v
            LB:RefreshList()
        end,
    }, 4)
    panel.diffBox = top:Choice({
        label = "Loot:",
        options = { { value = "n", text = "Normal", width = 60 }, { value = "h", text = "Heroic", width = 60 } },
        get = function() return state.diff or DB().diff end,
        set = function(v) DB().diff = v; LB:RefreshList() end,
    }, 260)
    top:Checkbox({
        label = "Sets: my class only",
        get = function() return DB().myClassSets end,
        set = function(v) DB().myClassSets = v; LB:RefreshList() end,
        tooltip = { "Set pages", "Show only the tier and dungeon sets your class can wear." },
    }, 430)
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

-- Open on an instance (or the one you're in)
function LB:Show(tag, instID)
    local p = self:CreateUI()
    if tag then state.tag, state.inst, state.boss = tag, instID, 1 end
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
            if tag then state.tag, state.inst, state.boss = tag, id, 1 end
        end
    end
    p:Show()
end
LB.ToggleUI = LB.Toggle

function LB:GetQuickStatus()
    local n = 0
    for _, x in ipairs(self:Expansions()) do n = n + #self:Instances(x.tag) end
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
end

events:SetScript("OnEvent", function()
    local ok, err = pcall(LB.OnItemInfo, LB)
    if not ok then geterrorhandler()(err) end
end)
