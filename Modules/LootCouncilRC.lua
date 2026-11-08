-- Watching Machine: Loot Council talking with RCLootCouncil
-- The raider and council side of an RCLootCouncil session, in its own
-- message format (LootCouncilCodec.lua), so a master looter running
-- RCLootCouncil (or Watching Machine) can send us loot:
--   * the session: which items, from which master looter, with its buttons
--     (Need, Greed, Minor Upgrade...) and its council
--   * as a raider: we acknowledge each item with the gear we'd replace, and
--     answer from the response frame
--   * as council: everyone's answers and votes, and our own votes, for the
--     voting frame
--   * every award the master looter logs goes into our loot history
-- When RCLootCouncil itself runs on this character it does all of this;
-- we only record its awards then. Protocol facts compiled with the help of
-- RCLootCouncil's research (Potdisc); the code is our own.

local AddonName, WM = ...
local LC = WM.LootCouncil
local Codec = WM.LootCodec
local RC = {}
LC.RC = RC

local PREFIX, PREFIX_VER = "RCLC", "RCLCv"
RC.VERSION = "1.5.1"            -- the RCLootCouncil Classic release we speak

local function On() return WM:IsModuleOn("LootCouncil") end
local function DB() return LC.DB() end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end

-- ============================================
-- WHO'S WHO
-- ============================================

local function Realm()
    local r = GetRealmName and GetRealmName() or ""
    return (r:gsub("[%s%-]", ""))
end
local function Key(name) return LC.Key(name) end
local function MyKey() return Key(UnitName("player")) end

function RC.RCLCRunning()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not f then return false end
    local ok, loaded = pcall(f, "RCLootCouncil_Classic")
    if ok and loaded then return true end
    ok, loaded = pcall(f, "RCLootCouncil")
    return ok and loaded and true or false
end

-- We take part (answer, vote) only when RCLootCouncil isn't doing it here
function RC.Active() return On() and DB().rcTalk ~= false and not RC.RCLCRunning() end

-- The group's units: "player", "partyN" / "raidN"
local function GroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do if UnitExists("raid" .. i) then units[#units + 1] = "raid" .. i end end
    else
        units[1] = "player"
        for i = 1, 4 do if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end end
    end
    return units
end
RC.GroupUnits = GroupUnits

local function UnitKey(unit)
    local n, r = UnitName(unit)
    if not n then return nil end
    if r and r ~= "" then return n .. "-" .. r:gsub("[%s%-]", "") end
    return n .. "-" .. Realm()
end

-- A player's GUID as RCLootCouncil sends it (without "Player-")
local function TransmitGUID(unit)
    local g = UnitGUID and UnitGUID(unit)
    return g and (g:gsub("^Player%-", "")) or nil
end

-- The master looter: the loot master with master loot, else the group leader
function RC.MasterLooter()
    if RC.testML then return RC.testML end
    if not (IsInGroup and IsInGroup()) then return nil end
    local method, partyID, raidID
    if GetLootMethod then method, partyID, raidID = GetLootMethod() end
    if method == "master" then
        if raidID then return UnitKey("raid" .. raidID) end
        if partyID then return partyID == 0 and MyKey() or UnitKey("party" .. partyID) end
    end
    for _, u in ipairs(GroupUnits()) do
        if UnitIsGroupLeader and UnitIsGroupLeader(u) then return UnitKey(u) end
    end
end

-- Group channel for our messages
local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

-- ============================================
-- SENDING
-- ============================================

RC.sent = {}       -- the last messages sent (tests read them)

-- Send an RCLootCouncil command to the group (or a whisper)
function RC:Send(command, args, channel, target, prefix)
    if self.local_ then
        -- A local test session: our own messages come straight back
        RC.sent[#RC.sent + 1] = { command = command, args = args }
        self:Handle(prefix or PREFIX, command, args, MyKey(), "RAID")
        return true
    end
    if not RC.Active() then return false end
    channel = channel or GroupChannel()
    if not channel then return false end
    RC.sent[#RC.sent + 1] = { command = command, args = args }
    while #RC.sent > 50 do table.remove(RC.sent, 1) end
    for _, part in ipairs(Codec.Pack(command, args)) do
        WM:QueueAddonMessage(prefix or PREFIX, part, channel, target, true)
    end
    return true
end

-- ============================================
-- THE SESSION
-- ============================================
-- RC.session = { ml, items = { [s] = item }, candidates = { [s] = { [name] = c } } }
-- item: { session, string, link, itemID, ilvl, equipLoc, texture, boss, owner, typeCode, awarded, answered }
-- c:    { name, class, rank, response, note, ilvl, diff, gear1, gear2, votes, voters = {}, roll }

RC.mldb = nil
RC.council = {}        -- [name] = true
RC.ranks = {}          -- [name] = guild rank (from pI)

local DEFAULT_BUTTONS = { numButtons = 3, { text = LC.GameText("NEED", "Need") }, { text = LC.GameText("GREED", "Greed") }, { text = "Minor Upgrade" } }
local DEFAULT_RESPONSES = {
    [1] = { text = "Mainspec/Need", color = { 0, 1, 0, 1 }, sort = 1 },
    [2] = { text = "Offspec/Greed", color = { 1, 0.5, 0, 1 }, sort = 2 },
    [3] = { text = "Minor Upgrade", color = { 0, 0.7, 0.7, 1 }, sort = 3 },
}
for i = 4, 10 do DEFAULT_RESPONSES[i] = { text = "Button" .. i, color = { 0.7, 0.7, 0.7, 1 }, sort = i } end
RC.STATUS = {
    AWARDED = { text = "Awarded", color = { 1, 1, 1, 1 }, sort = 0.1 },
    NOTANNOUNCED = { text = "Not announced", color = { 1, 0, 1, 1 }, sort = 501 },
    ANNOUNCED = { text = "Loot announced, waiting for answer", color = { 1, 0, 1, 1 }, sort = 502 },
    WAIT = { text = "Candidate is selecting response, please wait", color = { 1, 1, 0, 1 }, sort = 503 },
    TIMEOUT = { text = "Candidate didn't respond on time", color = { 1, 0, 0, 1 }, sort = 504 },
    REMOVED = { text = "Candidate removed", color = { 0.8, 0.5, 0, 1 }, sort = 505 },
    NOTHING = { text = "Offline or RCLootCouncil not installed", color = { 0.5, 0.5, 0.5, 1 }, sort = 506 },
    NOTELIGIBLE = { text = "Not eligible", color = { 0.8, 0.5, 0, 1 }, sort = 507 },
    PASS = { text = LC.GameText("PASS", "Pass"), color = { 0.7, 0.7, 0.7, 1 }, sort = 800 },
    AUTOPASS = { text = "Autopass", color = { 0.7, 0.7, 0.7, 1 }, sort = 801 },
    DISABLED = { text = "Candidate has disabled RCLootCouncil", color = { 0.3, 0.35, 0.5, 1 }, sort = 802 },
    NOTINRAID = { text = "Candidate is not in the instance", color = { 0.7, 0.6, 0, 1 }, sort = 803 },
    DEFAULT = { text = "Response isn't available", color = { 1, 0, 0, 1 }, sort = 899 },
}

-- mldb keys arrive shortened ("|1" = selfVote ...)
local MLDB_KEYS = { ["|1"] = "selfVote", ["|2"] = "multiVote", ["|3"] = "anonymousVoting", ["|4"] = "sort",
    ["|5"] = "numButtons", ["|6"] = "hideVotes", ["|7"] = "observe", ["|8"] = "buttons", ["|9"] = "rejectTrade",
    ["|10"] = "requireNotes", ["|11"] = "responses", ["|12"] = "timeout", ["|13"] = "outOfRaid", ["|14"] = "default",
    ["|15"] = "text", ["|16"] = "color", ["|17"] = "autoGroupLoot", ["|18"] = "requireNotes" }
local function RestoreKeys(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[MLDB_KEYS[k] or k] = RestoreKeys(v) end
    return out
end
RC.RestoreKeys = RestoreKeys

-- The buttons for an item: { {text, requireNotes}, ... } (Pass is always added)
function RC:Buttons(typeCode)
    local b = self.mldb and self.mldb.buttons
    local set = b and (b[typeCode or "default"] or b.default)
    local n = (set and set.numButtons) or (self.mldb and self.mldb.numButtons) or DEFAULT_BUTTONS.numButtons
    local out = {}
    for i = 1, n do
        local own = set and set[i]
        out[i] = { text = (own and own.text) or (DEFAULT_BUTTONS[i] and DEFAULT_BUTTONS[i].text) or ("Button " .. i),
            requireNotes = own and own.requireNotes or nil }
    end
    return out
end

-- A response's text, colour and sort order
function RC:Response(typeCode, response)
    if RC.STATUS[response] then return RC.STATUS[response] end
    local r = self.mldb and self.mldb.responses
    local set = r and (r[typeCode or "default"] or r.default)
    local own = set and set[response]
    local def = DEFAULT_RESPONSES[tonumber(response) or 0]
    if not own and not def then return RC.STATUS.DEFAULT end
    return { text = (own and own.text) or def.text, color = (own and own.color) or def.color, sort = (own and own.sort) or def.sort }
end

function RC:IsCouncil(name)
    name = name or MyKey()
    if self.session and name == self.session.ml then return true end
    return self.council[name] and true or false
end

-- ============================================
-- ITEMS AND GEAR
-- ============================================

local INV_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
RC.INV_SLOTS = INV_SLOTS

local function ItemInfo(s)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f or not s then return nil end
    local name, link, quality, ilvl, _, _, _, _, equipLoc, texture = f(s)
    return name, link, quality, ilvl, equipLoc, texture
end
local function ItemLevel(link)
    local _, _, _, ilvl = ItemInfo(link)
    return tonumber(ilvl)
end
RC.ItemLevel = ItemLevel

-- Fill an item's details from its item string (when the client has it)
function RC:Resolve(item)
    local _, link, _, ilvl, equipLoc, texture = ItemInfo("item:" .. item.string)
    if link then
        item.link, item.ilvl, item.equipLoc, item.texture = link, ilvl, equipLoc, texture
        item.pending = nil
    else
        item.link = item.link or ("|cffa335ee|Hitem:" .. item.string .. "|h[Item " .. tostring(item.itemID) .. "]|h|r")
        item.pending = true
    end
end

-- The gear we'd replace and how many item levels better the item is
function RC:GearFor(item)
    local slots = INV_SLOTS[item.equipLoc or ""]
    if not slots then return nil end
    local g1 = GetInventoryItemLink and GetInventoryItemLink("player", slots[1])
    local g2 = slots[2] and GetInventoryItemLink and GetInventoryItemLink("player", slots[2])
    local low = ItemLevel(g1)
    if g2 and (ItemLevel(g2) or 0) < (low or 0) then low = ItemLevel(g2) end
    local diff = (item.ilvl and low) and (item.ilvl - low) or nil
    return g1, g2, diff
end

-- Average item level of what we wear (shirt and tabard left out)
function RC.AverageIlvl()
    local sum, n = 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local il = ItemLevel(GetInventoryItemLink and GetInventoryItemLink("player", slot))
            if il then sum, n = sum + il, n + 1 end
        end
    end
    return n > 0 and math.floor(sum / n * 100 + 0.5) / 100 or 0
end

-- ============================================
-- CAN WE USE IT?
-- ============================================
-- What each class can equip in The Burning Crusade (armor and weapon
-- subclasses), plus the "Classes:" line on tier tokens and class items.

local ARMOR = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [6] = "shield",
    [7] = "libram", [8] = "idol", [9] = "totem" }
local CAN_WEAR = {
    WARRIOR = { cloth = 1, leather = 1, mail = 1, plate = 1, shield = 1 },
    PALADIN = { cloth = 1, leather = 1, mail = 1, plate = 1, shield = 1, libram = 1 },
    HUNTER = { cloth = 1, leather = 1, mail = 1 },
    ROGUE = { cloth = 1, leather = 1 },
    PRIEST = { cloth = 1 }, MAGE = { cloth = 1 }, WARLOCK = { cloth = 1 },
    SHAMAN = { cloth = 1, leather = 1, mail = 1, shield = 1, totem = 1 },
    DRUID = { cloth = 1, leather = 1, idol = 1 },
}
-- Weapon subclasses: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm,
-- 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local CAN_WIELD = {
    WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    PALADIN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
    HUNTER = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    ROGUE = { [2] = 1, [3] = 1, [4] = 1, [7] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    PRIEST = { [4] = 1, [10] = 1, [15] = 1, [19] = 1 },
    MAGE = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
    WARLOCK = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
    SHAMAN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
    DRUID = { [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
}
RC.CAN_WEAR, RC.CAN_WIELD = CAN_WEAR, CAN_WIELD

local scanTip
-- The "Classes: ..." line of an item's tooltip, if it has one
local function ClassesLine(link)
    if type(link) ~= "string" then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "WM_LootCouncilScanTip", nil, "GameTooltipTemplate")
    end
    if not scanTip.SetHyperlink then return nil end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip.SetHyperlink, scanTip, link) then return nil end
    local pattern = type(ITEM_CLASSES_ALLOWED) == "string" and ("^" .. ITEM_CLASSES_ALLOWED:gsub("%%s", "(.+)") .. "$") or "^Classes: (.+)$"
    for i = 2, tonumber(scanTip.NumLines and scanTip:NumLines()) or 0 do
        local fs = _G["WM_LootCouncilScanTipTextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        local classes = type(text) == "string" and text:match(pattern)
        if classes then return classes end
    end
end
RC.ClassesLine = ClassesLine

-- Can this class use the item? (class nil: ours)
function RC.CanUse(item, class)
    if not class then class = select(2, UnitClass("player")) end
    if not class or not CAN_WEAR[class] then return true end
    local link = type(item) == "table" and (item.link or (item.string and ("item:" .. item.string))) or item
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if f and link then
        local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(f, link)
        if ok then
            if classID == 4 and ARMOR[subclassID] and equipLoc ~= "INVTYPE_CLOAK" then
                if not CAN_WEAR[class][ARMOR[subclassID]] then return false end
            elseif classID == 2 and subclassID then
                if not CAN_WIELD[class][subclassID] then return false end
            end
        end
    end
    -- Tier tokens and class items: "Classes: Paladin, Rogue, Shaman"
    local classes = RC.ClassesLine(link)
    if classes then
        local male = (type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[class]) or class
        local female = (type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" and LOCALIZED_CLASS_NAMES_FEMALE[class]) or male
        for part in classes:gmatch("[^,]+") do
            part = strtrim(part)
            if part == male or part == female or part:upper() == class then return true end
        end
        return false
    end
    return true
end

local function StripItem(link)
    local s = link and link:match("item:([%-%d:]+)")
    return s and (s:gsub(":+$", "")) or nil
end

-- ============================================
-- RECEIVING
-- ============================================

local unframe = Codec.NewUnframer()

local function NewCandidate(name, class)
    return { name = name, class = class, rank = RC.ranks[name], response = "ANNOUNCED", votes = 0, voters = {} }
end

-- Everyone in the group as a candidate for each item
function RC:SetupCandidates()
    local s = self.session
    if not s then return end
    local roster = {}
    if self.local_ and self.testCandidates then
        for _, c in ipairs(self.testCandidates) do roster[#roster + 1] = c end
    else
        for _, u in ipairs(GroupUnits()) do
            local name = UnitKey(u)
            local _, class = UnitClass(u)
            if name then roster[#roster + 1] = { name = name, class = class } end
        end
    end
    for ses in pairs(s.items) do
        s.candidates[ses] = s.candidates[ses] or {}
        for _, r in ipairs(roster) do
            if not s.candidates[ses][r.name] then s.candidates[ses][r.name] = NewCandidate(r.name, r.class) end
        end
    end
end

local function Candidate(ses, name)
    local s = RC.session
    local list = s and s.candidates[ses]
    if not list then return nil end
    if not list[name] then list[name] = NewCandidate(name) end
    return list[name]
end

local listeners = {}
function RC.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed(what) for _, fn in ipairs(listeners) do pcall(fn, what) end end
RC.Changed = Changed

-- A loot table from the master looter
function RC:StartSession(ml, lt, add)
    if not add or not self.session then
        self.session = { ml = ml, items = {}, candidates = {}, started = Now() }
    end
    for i, e in pairs(lt) do
        if type(e) == "table" and e.string then
            local ses = tonumber(e.session) or tonumber(i)
            local item = { session = ses, string = e.string, itemID = tonumber(e.string:match("^(%d+)")),
                boss = e.boss, owner = e.owner, typeCode = e.typeCode or "default" }
            self:Resolve(item)
            -- Something we can't use: we pass on it without being asked
            if DB().autopass ~= false and not RC.CanUse(item) then item.autopass = true; item.answered = "AUTOPASS" end
            self.session.items[ses] = item
        end
    end
    self:SetupCandidates()
    -- Acknowledge with our gear for each item
    self:SendAck()
    Changed("session")
end

function RC:SendAck()
    local s = self.session
    if not s then return end
    local data = { gear1 = {}, gear2 = {}, diff = {}, response = {} }
    local passed = {}
    for ses, item in pairs(s.items) do
        local g1, g2, diff = self:GearFor(item)
        data.gear1[ses] = StripItem(g1)
        data.gear2[ses] = StripItem(g2)
        data.diff[ses] = diff
        if item.autopass and not item.autopassSent then
            data.response[ses] = true
            item.autopassSent = true
            passed[#passed + 1] = ses
        end
    end
    self:Send("lootAck", { 0, RC.AverageIlvl(), data })
    for _, ses in ipairs(passed) do self:Send("response", { ses, { response = "AUTOPASS" } }) end
end

-- Answer for an item (button index, or "PASS" / "TIMEOUT")
function RC:Respond(ses, response, note)
    local s = self.session
    local item = s and s.items[ses]
    if not item then return false end
    item.answered = response
    local g1, g2, diff = self:GearFor(item)
    self:Send("response", { ses, { response = response, note = (note and note ~= "") and note or nil,
        gear1 = g1 and ("item:" .. StripItem(g1)) or nil, gear2 = g2 and ("item:" .. StripItem(g2)) or nil,
        ilvl = RC.AverageIlvl(), diff = diff } })
    -- The same item in other sessions gets the same answer
    for other, it in pairs(s.items) do
        if other ~= ses and it.string == item.string and not it.answered then
            it.answered = response
            self:Send("response", { other, { response = response, note = (note and note ~= "") and note or nil } })
        end
    end
    Changed("answered")
    return true
end

-- Vote (+1) or take it back (-1)
function RC:Vote(ses, name, n)
    if not self:IsCouncil() then return false end
    local c = Candidate(ses, name)
    if not c then return false end
    if n > 0 and c.voters[MyKey()] then return false end
    if n < 0 and not c.voters[MyKey()] then return false end
    -- The master looter's rules (RCLootCouncil sends a rule only when it's on)
    if n > 0 and self.mldb then
        if not self.mldb.selfVote and name == MyKey() then return false end
        if not self.mldb.multiVote then
            for _, other in pairs(self.session.candidates[ses]) do
                if other.voters[MyKey()] then return false end
            end
        end
    end
    return self:Send("vote", { ses, name, n })
end

-- Messages from the master looter only
local ML_ONLY = { lootTable = true, lt_add = true, mldb = true, council = true, awarded = true, session_end = true,
    change_response = true, offline_timer = true, StartHandleLoot = true, StopHandleLoot = true, ResponseWait = true }

function RC:Handle(prefix, command, args, sender, dist)
    if prefix == PREFIX_VER then return self:HandleVersion(command, args, sender, dist) end
    local fromML = self.local_ or (sender == RC.MasterLooter())
    -- History is recorded from the master looter, or anyone in the guild
    if command == "history" then
        if fromML or dist == "GUILD" then
            local winner, entry = args[1], args[2]
            if type(entry) == "table" then LC.AddRCLC(Key(winner), entry, nil, true) end
        end
        return
    elseif command == "delete_history" then
        if fromML or dist == "GUILD" then LC.DeleteRCLC(args[1]) end
        return
    end
    -- Everything else is the session's, which we take part in only when active
    if not self.local_ and not RC.Active() then return end
    if ML_ONLY[command] and not fromML then return end
    if command == "StartHandleLoot" then
        self.handleLoot = true
        if not self.mldb then self:Send("MLdb_request", {}) end
    elseif command == "StopHandleLoot" then
        self.handleLoot = false
    elseif command == "mldb" then
        if type(args[1]) == "table" then self.mldb = RestoreKeys(args[1]) end
    elseif command == "council" then
        self.council = {}
        local byGuid = {}
        for _, u in ipairs(GroupUnits()) do local g = TransmitGUID(u); if g then byGuid[g] = UnitKey(u) end end
        for g in pairs(type(args[1]) == "table" and args[1] or {}) do
            local name = byGuid[g] or (self.local_ and g)
            if name then self.council[name] = true end
        end
        Changed("council")
    elseif command == "lootTable" then
        if type(args[1]) == "table" then self:StartSession(sender, args[1]) end
    elseif command == "lt_add" then
        if type(args[1]) == "table" then self:StartSession(sender, args[1], true) end
    elseif command == "lootAck" then
        local data = type(args[3]) == "table" and args[3] or {}
        local s = self.session
        if not s then return end
        for ses in pairs(s.items) do
            local c = Candidate(ses, sender)
            c.ilvl = tonumber(args[2]) or c.ilvl
            c.gear1 = data.gear1 and data.gear1[ses] and ("item:" .. data.gear1[ses]) or c.gear1
            c.gear2 = data.gear2 and data.gear2[ses] and ("item:" .. data.gear2[ses]) or c.gear2
            c.diff = data.diff and data.diff[ses] or c.diff
            if c.response == "ANNOUNCED" then
                c.response = (data.response and data.response[ses]) and "AUTOPASS" or "WAIT"
            end
        end
        Changed("candidate")
    elseif command == "response" then
        local ses, data = tonumber(args[1]), args[2]
        local c = ses and type(data) == "table" and Candidate(ses, sender)
        if c then
            for k, v in pairs(data) do c[k] = v end
            Changed("candidate")
        end
    elseif command == "vote" then
        local ses, name, n = tonumber(args[1]), args[2], tonumber(args[3])
        if ses and name and n and self:IsCouncil(sender) then
            local c = Candidate(ses, Key(name))
            if c then
                if n > 0 and not c.voters[sender] then c.voters[sender] = true; c.votes = c.votes + 1
                elseif n < 0 and c.voters[sender] then c.voters[sender] = nil; c.votes = math.max(0, c.votes - 1) end
                Changed("vote")
            end
        end
    elseif command == "awarded" then
        local ses, winner = tonumber(args[1]), args[2] and Key(args[2])
        local s = self.session
        local item = s and ses and s.items[ses]
        if item and winner then
            -- Awarded again: the earlier winner gets their answer back
            local prev = item.shownWinner and item.shownWinner ~= winner and s.candidates[ses][item.shownWinner]
            if prev and prev.response == "AWARDED" then prev.response = prev.realResponse or "NOTHING" end
            item.awarded, item.shownWinner = winner, winner
            local c = Candidate(ses, winner)
            if c.response ~= "AWARDED" then c.realResponse = c.response end
            c.response = "AWARDED"
            Changed("awarded")
        end
    elseif command == "change_response" then
        local c = Candidate(tonumber(args[1]) or 0, Key(args[2] or ""))
        if c then c.response = args[3]; Changed("candidate") end
    elseif command == "offline_timer" then
        local s = self.session
        for _, list in pairs(s and s.candidates or {}) do
            for _, c in pairs(list) do if c.response == "ANNOUNCED" then c.response = "NOTHING" end end
        end
        Changed("candidate")
    elseif command == "ResponseWait" then
        Changed("candidate")
    elseif command == "session_end" then
        self.session = nil
        Changed("end")
    elseif command == "pI" then
        RC.ranks[sender] = args[2]
    elseif command == "playerInfoRequest" then
        self:Send("pI", { nil, RC.MyGuildRank(), nil, nil, RC.AverageIlvl(), nil })
    end
end

function RC.MyGuildRank()
    local rankName
    if GetGuildInfo then rankName = select(2, GetGuildInfo("player")) end
    return rankName or ""
end

-- Version checks: say which RCLootCouncil release we speak, so a master
-- looter's version window lists us
function RC:HandleVersion(command, args, sender, dist)
    if not RC.Active() or sender == MyKey() then return end
    local modules = { "Watching Machine - " .. tostring(WM.version) }
    if command == "v" then
        if dist == "GUILD" then self:Send("r", { RC.VERSION, nil, modules }, "GUILD", nil, PREFIX_VER) end
    elseif command == "fr" then
        local _, class = UnitClass("player")
        local status = 1 + (self.handleLoot and 4 or 0) + (RC.MasterLooter() and 8 or 0) + ((IsInGroup and IsInGroup()) and 32 or 0) + 256
        local channel = (dist == "GUILD") and "GUILD" or (dist == "RAID" or dist == "PARTY") and dist or "WHISPER"
        self:Send("f", { class, RC.MyGuildRank(), RC.VERSION, nil, modules, args[6] or args[1], status },
            channel, channel == "WHISPER" and sender or nil, PREFIX_VER)
    end
end

-- An addon message arrived
function RC:OnAddonMessage(prefix, msg, dist, sender)
    if prefix ~= PREFIX and prefix ~= PREFIX_VER then return end
    if not On() then return end
    sender = Key(sender)
    local whole = unframe(prefix .. "\t" .. tostring(dist) .. "\t" .. tostring(sender), msg)
    if not whole then return end
    local command, args = Codec.Unpack(whole)
    if not command then return end
    -- Cross-realm whispers come through the group addressed to someone
    if command == "xrealm" then
        if Key(args[1]) ~= MyKey() then return end
        command = args[2]
        local rest = {}
        for i = 3, table.maxn(args) do rest[i - 2] = args[i] end
        args = rest
    end
    self:Handle(prefix, command, args, sender, dist)
end

-- ============================================
-- EVENTS
-- ============================================

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if not On() then return end
    if event == "CHAT_MSG_ADDON" then
        RC:OnAddonMessage(...)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local s = RC.session
        local any = false
        for _, item in pairs(s and s.items or {}) do
            if item.pending then RC:Resolve(item); any = any or not item.pending end
        end
        if any then Changed("items") end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if RC.session then RC:SetupCandidates(); Changed("candidate") end
    end
end)

function RC:Init()
    if self.started then return end
    self.started = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX_VER)
    end
    WM:RegisterEvents(events, { "CHAT_MSG_ADDON", "GET_ITEM_INFO_RECEIVED", "GROUP_ROSTER_UPDATE" })
end

function RC:Stop()
    self.session = nil
    self.local_ = nil
    WM:ClearAddonQueue({ [PREFIX] = true, [PREFIX_VER] = true })
    Changed("end")
end

-- ============================================
-- A LOCAL TEST SESSION (nothing is sent)
-- ============================================
-- Items from Serpentshrine Cavern and Tempest Keep; candidates from your
-- group, or from the loot history when you're alone.
RC.TEST_ITEMS = { 30242, 30100, 30020, 30106, 29988, 30247, 30027, 30236 }

function RC:StartTest(n)
    n = math.max(1, math.min(tonumber(n) or 3, #RC.TEST_ITEMS))
    self.local_ = true
    self.testML = MyKey()
    self.mldb = nil
    self.council = { [MyKey()] = true }
    -- Candidates: the group, or recent winners from the loot history
    local cands = {}
    if IsInGroup and IsInGroup() then
        for _, u in ipairs(GroupUnits()) do
            local _, class = UnitClass(u)
            cands[#cands + 1] = { name = UnitKey(u), class = class }
        end
    else
        local _, myClass = UnitClass("player")
        cands[1] = { name = MyKey(), class = myClass }
        for i, p in ipairs(LC.Players()) do
            if i > 9 then break end
            if p.key ~= MyKey() then cands[#cands + 1] = { name = p.key, class = p.last and p.last.class } end
        end
    end
    self.testCandidates = cands
    local lt = {}
    for i = 1, n do lt[i] = { string = tostring(RC.TEST_ITEMS[i]), session = i, boss = "Test boss" } end
    self:Handle(PREFIX, "lootTable", { lt }, MyKey(), "RAID")
    -- Others answer at random (you answer from the response frame)
    local pick = { 1, 1, 1, 2, 2, 3, "PASS" }
    for ses in pairs(self.session.items) do
        for _, c in ipairs(cands) do
            if c.name ~= MyKey() then
                local cand = Candidate(ses, c.name)
                cand.response = pick[math.random(#pick)]
                cand.ilvl = 110 + math.random(0, 30)
                cand.diff = math.random(-10, 25)
                if math.random() < 0.3 then cand.note = "test note" end
            end
        end
    end
    Changed("session")
    return true
end

function RC:EndTest()
    if not self.local_ then return end
    self.local_, self.testML, self.testCandidates = nil, nil, nil
    self.session = nil
    Changed("end")
end
