-- Watching Machine: Your Characters
-- Every character you log in, on every realm: level, XP and rested XP,
-- gold, bag space, durability, professions, the reagents your class uses,
-- and a hunter's ammo and pet. Saved as you play and on logout, so the
-- window shows all your alts at once.
--
-- Rested XP keeps growing while you're logged out: 5% of a level every 8
-- hours in an inn or city (a quarter of that elsewhere), up to 1.5 levels.
-- The window shows the estimate for now, from the last value saved.

local AddonName, WM = ...
local Alts = {}
WM:RegisterModule("AltTracker", Alts)
WM.AltTracker = Alts

Alts.version = "3.27"

local REST_PER_8H, EIGHT_HOURS, REST_CAP = 0.05, 8 * 3600, 1.5

-- Reagents worth carrying, per class (item IDs; names come from the client)
local REAGENTS = {
    PRIEST  = { 17029, 17028 },               -- Sacred Candle, Holy Candle
    MAGE    = { 17020, 17031, 17032, 17056 },  -- Arcane Powder, Runes of Teleportation / Portals, Light Feather
    DRUID   = { 22148, 17026, 17021, 22147 },  -- Wild Quillvine, Wild Thornroot, Wild Berries, Flintweed Seed
    PALADIN = { 21177, 17033 },               -- Symbol of Kings, Symbol of Divinity
    SHAMAN  = { 17030 },                      -- Ankh
    WARLOCK = { 6265, 5565, 16583 },          -- Soul Shard, Infernal Stone, Demonic Figurine
    ROGUE   = { 5140, 5530 },                 -- Flash Powder, Blinding Powder
    HUNTER  = {},
    WARRIOR = {},
}
local REAGENT_NAMES = {
    [17029] = "Sacred Candle", [17028] = "Holy Candle", [17020] = "Arcane Powder",
    [17031] = "Rune of Teleportation", [17032] = "Rune of Portals", [17056] = "Light Feather",
    [22148] = "Wild Quillvine", [17026] = "Wild Thornroot", [17021] = "Wild Berries", [22147] = "Flintweed Seed",
    [21177] = "Symbol of Kings", [17033] = "Symbol of Divinity", [17030] = "Ankh", [6265] = "Soul Shard",
    [5565] = "Infernal Stone", [16583] = "Demonic Figurine", [5140] = "Flash Powder", [5530] = "Blinding Powder",
}
Alts.REAGENTS = REAGENTS

-- Professions by name (English, plus the skill-window headers on other clients)
local PROFESSIONS = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Jewelcrafting = true, Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
    Cooking = true, ["First Aid"] = true, Fishing = true,
}

-- ============================================
-- SAVED DATA
-- ============================================

local function DB()
    if type(AltTrackerDB) ~= "table" then AltTrackerDB = {} end
    if type(AltTrackerDB.chars) ~= "table" then AltTrackerDB.chars = {} end
    return AltTrackerDB
end
Alts.DB = DB

local function Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" and t > 0 then return t end
    end
    return time()
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end
Alts.CharKey = CharKey

local function Text(value, english)
    return type(value) == "string" and value or english
end

-- ============================================
-- READING THE CHARACTER
-- ============================================

local function BagSpace()
    local free, total = 0, 0
    for bag = 0, 4 do
        local slots, freeSlots, family
        if C_Container and C_Container.GetContainerNumSlots then
            slots = C_Container.GetContainerNumSlots(bag)
            freeSlots, family = C_Container.GetContainerNumFreeSlots(bag)
        elseif GetContainerNumSlots then
            slots = GetContainerNumSlots(bag)
            freeSlots, family = GetContainerNumFreeSlots(bag)
        end
        -- Only ordinary bags (quivers, soul and herb bags don't hold anything)
        if (tonumber(family) or 0) == 0 then
            total = total + (tonumber(slots) or 0)
            free = free + (tonumber(freeSlots) or 0)
        end
    end
    return free, total
end

-- Average durability of worn gear, and the lowest piece, as percentages
local function Durability()
    if not GetInventoryItemDurability then return nil end
    local sum, n, lowest = 0, 0, nil
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if tonumber(cur) and tonumber(max) and tonumber(max) > 0 then
            local pct = (tonumber(cur) or 0) / tonumber(max) * 100
            sum, n = sum + pct, n + 1
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    if n == 0 then return nil end
    return math.floor(sum / n + 0.5), math.floor(lowest + 0.5)
end

local function Professions()
    local out = {}
    if not (GetNumSkillLines and GetSkillLineInfo) then return out end
    local headerProfessions = Text(TRADE_SKILLS, "Professions")
    local headerSecondary = Text(SECONDARY_SKILLS, "Secondary Skills")
    local section
    for i = 1, tonumber(GetNumSkillLines()) or 0 do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if type(name) ~= "string" then
            -- skip
        elseif isHeader then
            section = name
        elseif (PROFESSIONS[name] or section == headerProfessions or section == headerSecondary) then
            out[#out + 1] = { name = name, rank = tonumber(rank) or 0, max = tonumber(maxRank) or 0 }
        end
    end
    return out
end

local function Pet()
    if not UnitExists("pet") then return nil end
    local pet = { name = UnitName("pet"), level = UnitLevel("pet"), family = UnitCreatureFamily and UnitCreatureFamily("pet") }
    if GetPetHappiness then pet.happiness = GetPetHappiness() end
    return pet
end

-- Save everything about the character you're playing
function Alts:Update()
    local key = CharKey()
    local c = DB().chars[key] or {}
    DB().chars[key] = c
    c.key = key
    local _, class = UnitClass("player")
    c.name, c.realm, c.class = UnitName("player"), GetRealmName and GetRealmName() or "?", class
    c.faction = UnitFactionGroup and UnitFactionGroup("player") or c.faction
    c.level = tonumber(UnitLevel("player")) or c.level
    c.xp, c.xpMax = tonumber(UnitXP("player")) or 0, tonumber(UnitXPMax("player")) or 0
    c.rested = (GetXPExhaustion and tonumber(GetXPExhaustion())) or 0
    local resting = IsResting and IsResting()
    c.resting = (resting == true or resting == 1)
    c.gold = (GetMoney and tonumber(GetMoney())) or c.gold or 0
    c.bagFree, c.bagTotal = BagSpace()
    c.durability, c.durabilityLow = Durability()
    c.professions = Professions()
    c.reagents = {}
    for _, id in ipairs(REAGENTS[class] or {}) do
        c.reagents[id] = WM.ItemCount(id)
    end
    if class == "HUNTER" then
        local slot = GetInventorySlotInfo and GetInventorySlotInfo("AmmoSlot")
        c.ammo = slot and GetInventoryItemCount and tonumber(GetInventoryItemCount("player", slot)) or c.ammo
        c.pet = Pet() or c.pet
    end
    local zone = GetZoneText and GetZoneText()
    if type(zone) == "string" then c.zone = zone end
    c.seen = Now()
    return c
end

-- Rested XP now: what was saved, plus what's built up since
function Alts:RestedNow(c, now)
    if not c or not c.xpMax or c.xpMax <= 0 then return 0 end
    local rested = c.rested or 0
    if c.key ~= CharKey() and c.seen then
        local hours8 = math.max(0, (now or Now()) - c.seen) / EIGHT_HOURS
        rested = rested + c.xpMax * REST_PER_8H * hours8 * (c.resting and 1 or 0.25)
    end
    return math.min(rested, c.xpMax * REST_CAP)
end

function Alts:Characters()
    local list = {}
    for key, c in pairs(DB().chars) do
        c.key = key
        list[#list + 1] = c
    end
    table.sort(list, function(a, b)
        if a.realm ~= b.realm then return (a.realm or "") < (b.realm or "") end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

function Alts:RealmGold(realm)
    local total = 0
    for _, c in pairs(DB().chars) do
        if c.realm == realm then total = total + (c.gold or 0) end
    end
    return total
end

function Alts:Delete(key)
    if key == CharKey() then return false end
    DB().chars[key] = nil
    self:RefreshUI()
    return true
end

-- ============================================
-- FORMATTING
-- ============================================

local function Money(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s, c = math.floor(copper % 10000 / 100), copper % 100
    local gs = tostring(g):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if g > 0 then return string.format("%sg %ds", gs, s) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return c .. "c"
end
Alts.Money = Money

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "ffffff"
end

local function Ago(t, now)
    if not t then return "never" end
    local s = math.max(0, (now or Now()) - t)
    if s < 120 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end

local function RestedPct(self, c)
    if not c.xpMax or c.xpMax <= 0 then return 0 end
    return math.floor(self:RestedNow(c) / c.xpMax * 100 + 0.5)
end

local function ReagentName(id)
    local name = GetItemInfo and GetItemInfo(id)
    return type(name) == "string" and name or REAGENT_NAMES[id] or ("item " .. id)
end

local HAPPINESS = { [1] = "|cFFFF4444Unhappy|r", [2] = "|cFFFFCC33Content|r", [3] = "|cFF33FF33Happy|r" }

function Alts:ShowTooltip(owner, c)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|cFF" .. ClassHex(c.class) .. (c.name or "?") .. "|r  " .. (c.realm or ""), 1, 1, 1)
    local lvl = "Level " .. (c.level or "?")
    if c.xpMax and c.xpMax > 0 and (c.level or 0) < 70 then
        lvl = lvl .. string.format("  (%d%% through)", math.floor((c.xp or 0) / c.xpMax * 100))
    end
    GameTooltip:AddLine(lvl, 0.9, 0.9, 0.9)
    if c.xpMax and c.xpMax > 0 and (c.level or 0) < 70 then
        local rested = self:RestedNow(c)
        GameTooltip:AddDoubleLine("Rested XP", string.format("%d (%d%% of a level)%s", rested,
            RestedPct(self, c), c.key ~= CharKey() and " est." or ""), 0.8, 0.8, 0.8, 0.5, 0.7, 1)
    end
    GameTooltip:AddDoubleLine("Gold", Money(c.gold), 0.8, 0.8, 0.8, 1, 1, 1)
    if c.bagTotal and c.bagTotal > 0 then
        GameTooltip:AddDoubleLine("Bags", c.bagFree .. " of " .. c.bagTotal .. " free", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if c.durability then
        local low = c.durabilityLow < 25
        GameTooltip:AddDoubleLine("Durability", c.durability .. "% (lowest " .. c.durabilityLow .. "%)",
            0.8, 0.8, 0.8, 1, low and 0.3 or 1, low and 0.3 or 1)
    end
    if c.professions and #c.professions > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Professions", 1, 0.8, 0)
        for _, p in ipairs(c.professions) do
            GameTooltip:AddDoubleLine(p.name, p.rank .. " / " .. p.max, 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    local ids = REAGENTS[c.class] or {}
    if #ids > 0 and c.reagents then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Reagents", 1, 0.8, 0)
        for _, id in ipairs(ids) do
            local n = c.reagents[id] or 0
            GameTooltip:AddDoubleLine(ReagentName(id), n, 0.8, 0.8, 0.8, 1, n == 0 and 0.4 or 1, n == 0 and 0.4 or 1)
        end
    end
    if c.class == "HUNTER" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Ammo", c.ammo or "?", 0.8, 0.8, 0.8, 1, 1, 1)
        if c.pet then
            GameTooltip:AddDoubleLine("Pet", (c.pet.name or "?") .. "  level " .. (c.pet.level or "?")
                .. (c.pet.family and (" " .. c.pet.family) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
            if HAPPINESS[c.pet.happiness] then GameTooltip:AddDoubleLine(" ", HAPPINESS[c.pet.happiness]) end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Last seen " .. Ago(c.seen) .. (c.zone and (" in " .. c.zone) or ""), 0.6, 0.6, 0.6)
    if c.key ~= CharKey() then GameTooltip:AddLine("Right-click to remove (a deleted character).", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- ============================================
-- WINDOW
-- ============================================

local panel
local ROW_H = 20

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", 160, 0)
    row.level:SetWidth(40)
    row.level:SetJustifyH("LEFT")
    row.rested = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rested:SetPoint("LEFT", 205, 0)
    row.rested:SetWidth(80)
    row.rested:SetJustifyH("LEFT")
    row.gold = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.gold:SetPoint("RIGHT", -90, 0)
    row.gold:SetJustifyH("RIGHT")
    row.seen = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.seen:SetPoint("RIGHT", -6, 0)
    row.seen:SetWidth(80)
    row.seen:SetJustifyH("RIGHT")
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnEnter", function(self)
        if self.char then
            Alts:ShowTooltip(self, self.char)
        elseif self.realm then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.realm, 1, 0.8, 0)
            GameTooltip:AddDoubleLine("Gold on this realm", Money(Alts:RealmGold(self.realm)), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local c = self.char
        if not c or c.key == CharKey() then return end
        WM:Confirm("Remove " .. (c.name or "?") .. " (" .. (c.realm or "") .. ") from Your Characters?"
            .. " It comes back if you log in on it again.", function() Alts:Delete(c.key) end)
    end)
    return row
end

function Alts:RefreshList()
    if not panel or not panel.listChild then return end
    self:Update()
    local child, rows = panel.listChild, panel.rows
    local width = math.max(360, (panel:GetWidth() or 520) - 50)
    child:SetWidth(width)
    local n, realm, total = 0, nil, 0
    local function Row()
        n = n + 1
        local row = rows[n] or NewRow(child)
        rows[n] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(n - 1) * ROW_H)
        row:SetWidth(width)
        row:Show()
        return row
    end
    for _, c in ipairs(self:Characters()) do
        if c.realm ~= realm then
            realm = c.realm
            local row = Row()
            row.char, row.realm = nil, realm
            row.bg:SetColorTexture(1, 0.8, 0, 0.12)
            row.name:SetText("|cFFFFCC00" .. (realm or "?") .. "|r")
            row.level:SetText(""); row.rested:SetText(""); row.seen:SetText("")
            row.gold:SetText("|cFFFFCC00" .. Money(self:RealmGold(realm)) .. "|r")
        end
        local row = Row()
        row.char, row.realm = c, nil
        row.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.05 or 0.02)
        row.name:SetText("|cFF" .. ClassHex(c.class) .. (c.name or "?") .. "|r"
            .. (c.key == CharKey() and " |cFF33FF33(you)|r" or ""))
        row.level:SetText(c.level or "?")
        if (c.level or 0) < 70 and c.xpMax and c.xpMax > 0 then
            row.rested:SetText("|cFF7FB2FF" .. RestedPct(self, c) .. "% rested|r")
        else
            row.rested:SetText("")
        end
        row.gold:SetText(Money(c.gold))
        row.seen:SetText("|cFF999999" .. (c.key == CharKey() and "now" or Ago(c.seen)) .. "|r")
        total = total + (c.gold or 0)
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].char, rows[i].realm = nil, nil end
    child:SetHeight(math.max(1, n * ROW_H))
    if panel.totalText then panel.totalText:SetText("All characters: |cFFFFFFFF" .. Money(total) .. "|r") end
end

function Alts:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_AltTrackerFrame", title = "Your Characters", titleColor = "FFCC66",
        width = 560, height = 440, minHeight = 300, scroll = false,
        resizable = { 440, 300, 1000, 1200 },
        onResize = function() Alts:RefreshList() end,
        onRefresh = function() Alts:RefreshList() end,
    })
    local L = panel.layout
    L:Row(18):Text({ text = "|cFF888888Hover a character for details, a realm for its gold. Right-click to remove a deleted character.|r" }, 8)
    local fill = L:Fill(160)
    local scroll = CreateFrame("ScrollFrame", "WM_AltTrackerScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    scroll:SetScrollChild(child)
    panel.listChild, panel.rows = child, {}
    panel.totalText = panel:AddFooterText({ text = "" }, "LEFT")
    panel:Finish()
    return panel
end

function Alts:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function Alts:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
Alts.ToggleUI = Alts.Toggle

function Alts:GetQuickStatus()
    local n, total = 0, 0
    for _, c in pairs(DB().chars) do n = n + 1; total = total + (c.gold or 0) end
    return string.format("%d character%s, %s", n, n == 1 and "" or "s", Money(total))
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local pending = false

-- Many events come in bursts (bags, money): save at most once a second
local function Soon()
    if pending then return end
    pending = true
    WM.RunAfter(1, function()
        pending = false
        Alts:Update()
        Alts:RefreshUI()
    end)
end

function Alts:Initialize()
    DB()
    WM:RegisterEvents(events, {
        "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
        "PLAYER_UPDATE_RESTING", "BAG_UPDATE", "UPDATE_INVENTORY_DURABILITY", "SKILL_LINES_CHANGED",
        "UNIT_PET", "UNIT_HAPPINESS", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA",
    })
    self:Update()
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGOUT" then
        pcall(Alts.Update, Alts)
    elseif (event == "UNIT_PET" or event == "UNIT_HAPPINESS") and unit ~= "player" and unit ~= "pet" then
        return
    else
        Soon()
    end
end)
