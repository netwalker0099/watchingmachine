-- Watching Machine: Your Characters
-- Every character you log in, on every realm: level, XP and rested XP,
-- gold, bag space, durability, professions, the reagents your class uses,
-- and a hunter's ammo and pet; their gear (and GearScore), bags, keyring,
-- bank (as of the last visit) and raid lockouts. Saved as you play and on
-- logout, so the window shows all your alts at once, and one search finds
-- an item on any of them.
--
-- Rested XP keeps growing while you're logged out: 5% of a level every 8
-- hours in an inn or city (a quarter of that elsewhere), up to 1.5 levels.
-- The window shows the estimate for now, from the last value saved.

local AddonName, WM = ...
local Alts = {}
WM:RegisterModule("AltTracker", Alts)
WM.AltTracker = Alts

Alts.version = "3.42"

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

-- One container's items: { { link, count }, ... } (count left out when 1)
local function ContainerItems(bag, out)
    local nslots
    if C_Container and C_Container.GetContainerNumSlots then nslots = C_Container.GetContainerNumSlots(bag)
    elseif GetContainerNumSlots then nslots = GetContainerNumSlots(bag) end
    for slot = 1, tonumber(nslots) or 0 do
        local link, count
        if C_Container and C_Container.GetContainerItemInfo then
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" then link, count = info.hyperlink, info.stackCount end
        elseif GetContainerItemInfo then
            local ok, _, n, _, _, _, _, l = pcall(GetContainerItemInfo, bag, slot)
            if ok then link, count = l, n end
        end
        if not link and GetContainerItemLink then link = GetContainerItemLink(bag, slot) end
        if type(link) == "string" then
            count = tonumber(count) or 1
            out[#out + 1] = count > 1 and { link, count } or { link }
        end
    end
    return out
end
Alts.ContainerItems = ContainerItems

local BANK = rawget(_G, "BANK_CONTAINER") or -1
local KEYRING = rawget(_G, "KEYRING_CONTAINER") or -2
local function BankBags()
    local first = (rawget(_G, "NUM_BAG_SLOTS") or 4) + 1
    local n = rawget(_G, "NUM_BANKBAGSLOTS") or 7
    local out = { BANK }
    for b = first, first + n - 1 do out[#out + 1] = b end
    return out
end

local function Gear()
    local gear = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if type(link) == "string" then gear[slot] = link end
    end
    return gear
end

-- Raid lockouts from the game: { name, size, difficulty, bosses, killed, reset (time) }
local function SavedInstances(now)
    local out = {}
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return out end
    for i = 1, tonumber(GetNumSavedInstances()) or 0 do
        local ok, name, id, reset, _, locked, extended, _, isRaid, maxPlayers, diffName, bosses, killed = pcall(GetSavedInstanceInfo, i)
        if ok and type(name) == "string" and (locked or extended) and (tonumber(reset) or 0) > 0 then
            out[#out + 1] = { name = name, id = id, size = maxPlayers, difficulty = diffName, raid = isRaid and true or false,
                bosses = tonumber(bosses), killed = tonumber(killed), reset = now + tonumber(reset) }
        end
    end
    return out
end

function Alts:UpdateBank()
    local c = DB().chars[CharKey()]
    if not c then return end
    local items = {}
    for _, bag in ipairs(BankBags()) do ContainerItems(bag, items) end
    c.bank, c.bankAt = items, Now()
    return c
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
    -- What they wear, carry and are saved to
    c.gear = Gear()
    local GS = WM.GearScore
    if GS and GS.GearScoreFor and next(c.gear) then
        local score, ilvl, complete = GS.GearScoreFor(c.gear, class)
        if complete then c.gearScore, c.avgIlvl = score, math.floor(ilvl * 10 + 0.5) / 10 end
    end
    local bags = {}
    for bag = 0, 4 do ContainerItems(bag, bags) end
    c.bags = bags
    c.keys = ContainerItems(KEYRING, {})
    if self.bankOpen then self:UpdateBank() end
    if self.savedFresh then c.saved = SavedInstances(c.seen) end
    return c
end

-- Raid lockouts still running for a character
function Alts:Lockouts(c, now)
    now = now or Now()
    local out = {}
    for _, l in ipairs(c and c.saved or {}) do
        if (l.reset or 0) > now then out[#out + 1] = l end
    end
    table.sort(out, function(a, b) return a.reset < b.reset end)
    return out
end

-- ============================================
-- SEARCH (every character's gear, bags, keyring and bank)
-- ============================================

local function LinkID(link) return tonumber(tostring(link):match("item:(%d+)")) end
local function LinkName(link) return tostring(link):match("%[(.-)%]") end
Alts.LinkID, Alts.LinkName = LinkID, LinkName

local PLACES = { { "gear", "worn" }, { "bags", "bags" }, { "keys", "keyring" }, { "bank", "bank" } }

-- Items whose name has the text in it: { id, name, link, total,
-- where = { { char, count, place } } }, most held first
function Alts:Search(text)
    local q = type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if #q < 2 then return {} end
    local byID = {}
    for _, c in ipairs(self:Characters()) do
        for _, place in ipairs(PLACES) do
            local list = c[place[1]]
            if type(list) == "table" then
                for k, e in pairs(list) do
                    local link, count = e, 1
                    if type(e) == "table" then link, count = e[1], e[2] or 1 end
                    local name = LinkName(link)
                    if name and name:lower():find(q, 1, true) then
                        local id = LinkID(link) or name
                        local hit = byID[id]
                        if not hit then
                            hit = { id = id, name = name, link = link, total = 0, where = {}, at = {} }
                            byID[id] = hit
                        end
                        hit.total = hit.total + count
                        local key = c.key .. "/" .. place[2]
                        local w = hit.at[key]
                        if not w then
                            w = { char = c, count = 0, place = place[2] }
                            hit.at[key] = w
                            hit.where[#hit.where + 1] = w
                        end
                        w.count = w.count + count
                    end
                end
            end
        end
    end
    local out = {}
    for _, h in pairs(byID) do h.at = nil; out[#out + 1] = h end
    table.sort(out, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return out
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
    local att = WM.Attunements and WM.Attunements.TooltipLines and WM.Attunements:TooltipLines(c.key)
    if att then
        GameTooltip:AddLine(" ")
        for _, l in ipairs(att) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    end
    if c.key ~= CharKey() then GameTooltip:AddLine("Right-click to remove (a deleted character).", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- ============================================
-- WINDOW
-- ============================================
-- One row per character: name, level, rested, GearScore, then buttons for
-- their bags, bank, attunements and lockouts, gold and last seen. Click a
-- character for their gear. The details open in a flyout on the right.

local panel, flyout
local ROW_H = 20
local ICONS = {
    bags = "Interface\\Icons\\INV_Misc_Bag_08", bank = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    attune = "Interface\\Icons\\INV_Misc_Key_07", lockouts = "Interface\\Icons\\Spell_Holy_BorrowedTime",
}
local VIEW_ORDER = { "bags", "bank", "attune", "lockouts" }
local VIEW_TIPS = { bags = "Bags and keyring", bank = "Bank (as of the last visit)", attune = "Attunements", lockouts = "Raid lockouts" }

local function ScoreText(score)
    local GS = WM.GearScore
    if not score then return "" end
    return GS and GS.ColorText and GS.ColorText(score) or tostring(score)
end

local function Icon(link)
    local id = LinkID(link)
    return id and WM.ItemIcon and WM.ItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function LinkTooltip(owner, link)
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

local function LinkClick(link)
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.3, 0.6, 1, 0.25)
    row.sel:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:Hide()
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
    row.gs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.gs:SetPoint("LEFT", 290, 0)
    row.gs:SetWidth(48)
    row.gs:SetJustifyH("LEFT")
    row.views = {}
    for i, v in ipairs(VIEW_ORDER) do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(16, 16)
        b:SetPoint("LEFT", 342 + (i - 1) * 19, 0)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexture(ICONS[v])
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.view = v
        b:SetScript("OnClick", function(self) if row.char then Alts:ShowDetail(row.char, self.view) end end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(VIEW_TIPS[self.view])
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.views[v] = b
    end
    row.gold = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.gold:SetPoint("RIGHT", -90, 0)
    row.gold:SetJustifyH("RIGHT")
    row.seen = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.seen:SetPoint("RIGHT", -6, 0)
    row.seen:SetWidth(80)
    row.seen:SetJustifyH("RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        if self.hit then
            Alts:ShowHitTooltip(self, self.hit)
        elseif self.char then
            Alts:ShowTooltip(self, self.char)
        elseif self.realm then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.realm, 1, 0.8, 0)
            GameTooltip:AddDoubleLine("Gold on this realm", Money(Alts:RealmGold(self.realm)), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        if self.hit then LinkClick(self.hit.link); return end
        local c = self.char
        if not c then return end
        if button == "RightButton" then
            if c.key == CharKey() then return end
            WM:Confirm("Remove " .. (c.name or "?") .. " (" .. (c.realm or "") .. ") from Your Characters?"
                .. " It comes back if you log in on it again.", function() Alts:Delete(c.key) end)
        else
            Alts:ShowDetail(c, "gear")
        end
    end)
    return row
end

-- A search result: the item, then who has it and where
function Alts:ShowHitTooltip(owner, hit)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if hit.link then GameTooltip:SetHyperlink(hit.link) else GameTooltip:SetText(hit.name) end
    GameTooltip:AddLine(" ")
    for _, w in ipairs(hit.where) do
        GameTooltip:AddDoubleLine("|cFF" .. ClassHex(w.char.class) .. (w.char.name or "?") .. "|r |cFF888888" .. (w.char.realm or "") .. "|r",
            w.count .. " (" .. w.place .. ")", 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function ShowColumns(row, show)
    row.level:SetShown(show); row.rested:SetShown(show); row.gs:SetShown(show)
    for _, b in pairs(row.views) do b:SetShown(show) end
end

function Alts:RefreshList()
    if not panel or not panel.listChild then return end
    self:Update()
    local child, rows = panel.listChild, panel.rows
    local width = math.max(520, (panel:GetWidth() or 680) - 50)
    child:SetWidth(width)
    local n, realm, total = 0, nil, 0
    local function Row()
        n = n + 1
        local row = rows[n] or NewRow(child)
        rows[n] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(n - 1) * ROW_H)
        row:SetWidth(width)
        row.hit, row.char, row.realm = nil, nil, nil
        row.icon:Hide()
        row.sel:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(150)
        row:Show()
        return row
    end
    local search = self.searchText
    if search and #search >= 2 then
        -- Search results instead of the characters
        local hits = self:Search(search)
        for i, h in ipairs(hits) do
            if i > 100 then break end
            local row = Row()
            row.hit = h
            row.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.05 or 0.02)
            ShowColumns(row, false)
            row.icon:SetTexture(Icon(h.link))
            row.icon:Show()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetWidth(width - 260)
            row.name:SetText(h.link or h.name)
            local who = {}
            for _, w in ipairs(h.where) do who[#who + 1] = (w.char.name or "?") .. " " .. w.count end
            row.gold:SetText("|cFFFFFFFF" .. h.total .. "|r")
            row.seen:SetText("|cFF999999" .. table.concat(who, ", "):sub(1, 40) .. "|r")
        end
        if #hits == 0 then
            local row = Row()
            ShowColumns(row, false)
            row.bg:SetColorTexture(0, 0, 0, 0)
            row.name:SetWidth(width - 20)
            row.name:SetText("|cFF888888No character has an item called \"" .. search .. "\". (Banks count from each one's last visit.)|r")
            row.gold:SetText(""); row.seen:SetText("")
        end
        child:SetHeight(math.max(1, n * ROW_H))
        for i = n + 1, #rows do rows[i]:Hide(); rows[i].char, rows[i].realm, rows[i].hit = nil, nil, nil end
        if panel.totalText then panel.totalText:SetText(#hits .. " item" .. (#hits == 1 and "" or "s") .. " found") end
        return
    end
    for _, c in ipairs(self:Characters()) do
        if c.realm ~= realm then
            realm = c.realm
            local row = Row()
            row.realm = realm
            row.bg:SetColorTexture(1, 0.8, 0, 0.12)
            ShowColumns(row, false)
            row.name:SetText("|cFFFFCC00" .. (realm or "?") .. "|r")
            row.seen:SetText("")
            row.gold:SetText("|cFFFFCC00" .. Money(self:RealmGold(realm)) .. "|r")
        end
        local row = Row()
        row.char = c
        row.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.05 or 0.02)
        ShowColumns(row, true)
        row.sel:SetShown(flyout and flyout:IsShown() and flyout.char and flyout.char.key == c.key or false)
        row.name:SetText("|cFF" .. ClassHex(c.class) .. (c.name or "?") .. "|r"
            .. (c.key == CharKey() and " |cFF33FF33(you)|r" or ""))
        row.level:SetText(c.level or "?")
        if (c.level or 0) < 70 and c.xpMax and c.xpMax > 0 then
            row.rested:SetText("|cFF7FB2FF" .. RestedPct(self, c) .. "% rested|r")
        else
            row.rested:SetText("")
        end
        row.gs:SetText(ScoreText(c.gearScore))
        row.views.bank:SetAlpha(c.bank and 1 or 0.35)
        row.views.lockouts:SetAlpha(#self:Lockouts(c) > 0 and 1 or 0.35)
        row.gold:SetText(Money(c.gold))
        row.seen:SetText("|cFF999999" .. (c.key == CharKey() and "now" or Ago(c.seen)) .. "|r")
        total = total + (c.gold or 0)
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].char, rows[i].realm, rows[i].hit = nil, nil, nil end
    child:SetHeight(math.max(1, n * ROW_H))
    if panel.totalText then panel.totalText:SetText("All characters: |cFFFFFFFF" .. Money(total) .. "|r") end
    if flyout and flyout:IsShown() and flyout.char then self:ShowDetail(DB().chars[flyout.char.key] or flyout.char, flyout.view, true) end
end

-- ============================================
-- THE FLYOUT: gear, bags, bank, attunements, lockouts
-- ============================================

local SLOT = 36
-- Paper-doll order: left column, right column, then the weapons
local DOLL_LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
local DOLL_RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local DOLL_BOTTOM = { 16, 17, 18 }
local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Finger", "Finger", "Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }
local GRID_COLS, GRID_SLOT = 8, 32

local function ItemSlot(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        if self.link then LinkTooltip(self, self.link)
        elseif self.slotName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.slotName .. ": empty", 0.6, 0.6, 0.6); GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) LinkClick(self.link) end)
    return b
end

local function SetSlot(b, link, count)
    b.link = link
    b.icon:SetTexture(link and Icon(link) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    b.icon:SetDesaturated(not link)
    b.count:SetText(count and count > 1 and count or "")
    b:Show()
end

local function CreateFlyout()
    if flyout then return flyout end
    local f = CreateFrame("Frame", "WM_AltTrackerDetail", panel, "BackdropTemplate")
    f:SetSize(330, 440)
    f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
    f:EnableMouse(true)
    if WM.SkinPanel then WM:SkinPanel(f) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -14)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.sub:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide(); Alts:RefreshList() end)
    -- Tabs for the five views
    f.tabs = {}
    local tabs = { { "gear", "Gear" }, { "bags", "Bags" }, { "bank", "Bank" }, { "attune", "Attune" }, { "lockouts", "Lockouts" } }
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(58, 18)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 61, -48)
        b:SetText(t[2])
        b.view = t[1]
        b:SetScript("OnClick", function(self) if f.char then Alts:ShowDetail(f.char, self.view) end end)
        f.tabs[i] = b
    end
    -- Gear: a paper doll
    f.doll = CreateFrame("Frame", nil, f)
    f.doll:SetPoint("TOPLEFT", 12, -74)
    f.doll:SetPoint("BOTTOMRIGHT", -12, 12)
    f.slots = {}
    for i, slot in ipairs(DOLL_LEFT) do
        local b = ItemSlot(f.doll, SLOT)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * (SLOT + 4))
        f.slots[slot] = b
    end
    for i, slot in ipairs(DOLL_RIGHT) do
        local b = ItemSlot(f.doll, SLOT)
        b:SetPoint("TOPRIGHT", 0, -(i - 1) * (SLOT + 4))
        f.slots[slot] = b
    end
    for i, slot in ipairs(DOLL_BOTTOM) do
        local b = ItemSlot(f.doll, SLOT)
        b:SetPoint("BOTTOM", (i - 2) * (SLOT + 6), 0)
        f.slots[slot] = b
    end
    for slot, b in pairs(f.slots) do b.slotName = SLOT_NAMES[slot] end
    f.dollText = f.doll:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.dollText:SetPoint("CENTER", 0, 20)
    f.dollText:SetWidth(180)
    -- Bags / bank: a scrolling grid
    f.grid = CreateFrame("ScrollFrame", "WM_AltTrackerGrid", f, "UIPanelScrollFrameTemplate")
    f.grid:SetPoint("TOPLEFT", 12, -74)
    f.grid:SetPoint("BOTTOMRIGHT", -32, 12)
    f.gridChild = CreateFrame("Frame", nil, f.grid)
    f.gridChild:SetSize(GRID_COLS * (GRID_SLOT + 2), 1)
    f.grid:SetScrollChild(f.gridChild)
    f.cells = {}
    -- Attunements / lockouts: lines of text
    f.lines = {}
    f.text = CreateFrame("Frame", nil, f)
    f.text:SetPoint("TOPLEFT", 12, -74)
    f.text:SetPoint("BOTTOMRIGHT", -12, 36)
    f.openBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.openBtn:SetSize(140, 20)
    f.openBtn:SetPoint("BOTTOMLEFT", 12, 10)
    flyout = f
    f:Hide()
    return f
end

local function Line(f, i, text)
    local fs = f.lines[i]
    if not fs then
        fs = f.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        fs:SetPoint("RIGHT", f.text, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        f.lines[i] = fs
    end
    fs:SetText(text)
    fs:Show()
end

local function ResetIn(s)
    s = math.max(0, s)
    if s >= 86400 then return math.floor(s / 86400) .. "d " .. math.floor(s % 86400 / 3600) .. "h" end
    return math.floor(s / 3600) .. "h " .. math.floor(s % 3600 / 60) .. "m"
end

-- Open the flyout on a character's gear / bags / bank / attune / lockouts
function Alts:ShowDetail(c, view, keepOpen)
    if not panel or not c then return end
    local f = CreateFlyout()
    if not keepOpen and f:IsShown() and f.char and f.char.key == c.key and f.view == view then
        f:Hide()
        self:RefreshList()
        return
    end
    f.char, f.view = c, view
    f.title:SetText("|cFF" .. ClassHex(c.class) .. (c.name or "?") .. "|r  |cFF888888" .. (c.realm or "") .. "|r")
    for _, t in ipairs(f.tabs) do t:SetText((t.view == view and "|cFF00FF00" or "") .. ({ gear = "Gear", bags = "Bags", bank = "Bank", attune = "Attune", lockouts = "Lockouts" })[t.view]) end
    f.doll:SetShown(view == "gear")
    f.grid:SetShown(view == "bags" or view == "bank")
    f.text:SetShown(view == "attune" or view == "lockouts")
    f.openBtn:Hide()
    for _, fs in ipairs(f.lines) do fs:Hide() end
    local sub = "Level " .. (c.level or "?")
    if view == "gear" then
        local gear = c.gear or {}
        for slot, b in pairs(f.slots) do SetSlot(b, gear[slot]) end
        if c.gearScore then
            sub = sub .. "   |cFFFFD100GearScore|r " .. ScoreText(c.gearScore) .. "   |cFFFFD100iLvl|r " .. math.floor((c.avgIlvl or 0) + 0.5)
        end
        f.dollText:SetText(next(gear) and "" or "|cFF888888Log in on this character once to see its gear.|r")
    elseif view == "bags" or view == "bank" then
        local items = {}
        for _, e in ipairs(view == "bags" and (c.bags or {}) or (c.bank or {})) do items[#items + 1] = e end
        if view == "bags" then for _, e in ipairs(c.keys or {}) do items[#items + 1] = e end end
        for i, e in ipairs(items) do
            local cell = f.cells[i]
            if not cell then cell = ItemSlot(f.gridChild, GRID_SLOT); f.cells[i] = cell end
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", ((i - 1) % GRID_COLS) * (GRID_SLOT + 2), -math.floor((i - 1) / GRID_COLS) * (GRID_SLOT + 2))
            cell.slotName = nil
            SetSlot(cell, e[1], e[2])
        end
        for i = #items + 1, #f.cells do f.cells[i]:Hide(); f.cells[i].link = nil end
        f.gridChild:SetHeight(math.max(1, math.ceil(#items / GRID_COLS) * (GRID_SLOT + 2)))
        if view == "bags" then
            sub = #items .. " items" .. (c.bagTotal and ("   " .. (c.bagFree or 0) .. " of " .. c.bagTotal .. " slots free") or "")
        elseif c.bankAt then
            sub = #items .. " items, as of " .. Ago(c.bankAt)
        else
            sub = "|cFF888888Open the bank once on this character to see what's in it.|r"
        end
    elseif view == "attune" then
        local AT = WM.Attunements
        local i = 0
        local saved = AT and AttunementsDB and AttunementsDB.chars and AttunementsDB.chars[c.key]
        if AT and saved and saved.att then
            for _, a in ipairs(AT:List(false)) do
                local r = saved.att[a.id]
                local pct = r and r.pct or 0
                local color = pct >= 100 and "|cFF00FF00" or pct > 0 and "|cFFFFD100" or "|cFF888888"
                i = i + 1
                Line(f, i, color .. a.name .. "|r  " .. color .. (pct >= 100 and "attuned" or (pct .. "%")) .. "|r")
            end
            sub = sub .. "   " .. #AT:AttunedNames(c.key, true) .. " raids attuned"
        else
            Line(f, 1, "|cFF888888Log in on this character once to see its attunements.|r")
        end
        if AT then
            f.openBtn:SetText("Open Attunements")
            f.openBtn:SetScript("OnClick", function() AT:Toggle() end)
            f.openBtn:Show()
        end
    elseif view == "lockouts" then
        local locks = self:Lockouts(c)
        local now = Now()
        for i, l in ipairs(locks) do
            local progress = (l.bosses and l.bosses > 0) and (" " .. (l.killed or 0) .. "/" .. l.bosses) or ""
            Line(f, i, "|cFFFFFFFF" .. l.name .. "|r |cFF888888" .. (l.difficulty or (l.size and (l.size .. "-player")) or "") .. "|r"
                .. progress .. "  |cFF66CCFFresets in " .. ResetIn(l.reset - now) .. "|r")
        end
        if #locks == 0 then Line(f, 1, "|cFF888888No raid lockouts" .. (c.saved and "." or " seen yet (log in on this character).") .. "|r") end
        local IT = WM.modules.InstanceTracker
        if IT and IT.LockoutText then
            Line(f, #locks + 2, "|cFFFFD100Instances entered (all characters):|r " .. (IT:LockoutText() or ""))
            f.openBtn:SetText("Open Instance Tracker")
            f.openBtn:SetScript("OnClick", function() IT:Toggle() end)
            f.openBtn:Show()
        end
    end
    f.sub:SetText(sub)
    f:Show()
    if not keepOpen then self:RefreshList() end
end

function Alts:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_AltTrackerFrame", title = "Your Characters", titleColor = "FFCC66",
        width = 680, height = 460, minHeight = 300, scroll = false,
        resizable = { 600, 300, 1200, 1200 },
        onResize = function() Alts:RefreshList() end,
        onRefresh = function() Alts:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(24)
    local box = top:EditBox({ label = "Find an item:", width = 180, maxLetters = 40,
        tooltip = { "Item search", "Finds an item on any of your characters: worn, in their bags or keyring, or in"
            .. " their bank (as of their last visit). Hover a result for who has how many." },
        onEnter = function(t) Alts.searchText = t; Alts:RefreshList() end }, 8)
    local e = box.editBox
    e:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local t = strtrim(self:GetText() or "")
        Alts.searchText = #t >= 2 and t or nil
        Alts:RefreshList()
    end)
    e:SetScript("OnEscapePressed", function(self) self:SetText(""); Alts.searchText = nil; Alts:RefreshList(); self:ClearFocus() end)
    panel.searchBox = box
    local head = L:Row(16)
    head:Text({ text = "|cFF888888Character|r" }, 6)
    head:Text({ text = "|cFF888888Level|r" }, 160)
    head:Text({ text = "|cFF888888GearScore|r" }, 290)
    head:Text({ text = "|cFF888888Bags, bank, attunes, lockouts|r" }, 342)
    L:Row(16):Text({ text = "|cFF888888Click a character for their gear. Right-click to remove a deleted character.|r" }, 8)
    local fill = L:Fill(160)
    local scroll = CreateFrame("ScrollFrame", "WM_AltTrackerScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    scroll:SetScrollChild(child)
    panel.listChild, panel.rows = child, {}
    panel.totalText = panel:AddFooterText({ text = "" }, "LEFT")
    panel:HookScript("OnHide", function() if flyout then flyout:Hide() end end)
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
        "UNIT_PET", "UNIT_HAPPINESS", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA", "PLAYER_EQUIPMENT_CHANGED",
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "UPDATE_INSTANCE_INFO",
    })
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    self:Update()
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "BANKFRAME_OPENED" then
        Alts.bankOpen = true
        Alts:UpdateBank()
        Alts:RefreshUI()
    elseif event == "BANKFRAME_CLOSED" then
        if Alts.bankOpen then pcall(Alts.UpdateBank, Alts) end
        Alts.bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if Alts.bankOpen then Soon() end
    elseif event == "UPDATE_INSTANCE_INFO" then
        Alts.savedFresh = true
        Soon()
    elseif event == "PLAYER_LOGOUT" then
        pcall(Alts.Update, Alts)
    elseif (event == "UNIT_PET" or event == "UNIT_HAPPINESS") and unit ~= "player" and unit ~= "pet" then
        return
    else
        Soon()
    end
end)
