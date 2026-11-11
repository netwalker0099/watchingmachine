-- Watching Machine: Loot Council as master looter
-- Runs the session the way an RCLootCouncil master looter does, in its
-- messages, so raiders running RCLootCouncil or Watching Machine answer and
-- the council votes in either:
--   * items: from the loot window (your quality threshold and up), by
--     Alt-clicking any item, or /wmachine council add <item>
--   * the council: group members at your council rank or higher (from the
--     guild roster), plus any names you list, plus you
--   * awarding (voting frame): straight from the loot window when it's open
--     (master loot), otherwise queued to trade Gargul-style: the trade opens
--     with the winner and the item goes in by itself
--   * each award is announced to the raid and logged in RCLootCouncil's
--     history format, so every RCLootCouncil and Watching Machine user
--     records it
--   * test loot: /wmachine council sendtest sends test items to your group
--     for answers and votes (marked as a test, nothing given or logged)

local AddonName, WM = ...
local LC = WM.LootCouncil
local RC = LC.RC
local ML = {}
LC.ML = ML

local function On() return WM:IsModuleOn("LootCouncil") end
local function DB() return LC.DB() end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end
local function MyKey() return LC.Key(UnitName("player")) end
local function Print(msg) WM:ModulePrint("LootCouncil", msg) end

ML.pending = {}        -- items waiting to be sent: { link, string, itemID, slot, boss }
ML.toTrade = {}        -- awards to hand over by trade: { winner, itemID, link, t, done }
ML.test = false        -- the running session is test loot
local historyCounter = 0

-- ============================================
-- AM I THE MASTER LOOTER?
-- ============================================

function ML:IsML()
    if not On() or RC.RCLCRunning() then return false end
    if not (IsInGroup and IsInGroup()) then return false end
    return RC.MasterLooter() == MyKey()
end

-- Group members by name: { [name] = unit }
local function GroupByName()
    local out = {}
    for _, u in ipairs(RC.GroupUnits()) do
        local n, r = UnitName(u)
        if n then
            local key = LC.Key((r and r ~= "") and (n .. "-" .. r) or n)
            out[key] = u
        end
    end
    return out
end
ML.GroupByName = GroupByName

-- Guild rank index of each guild member: { [name] = index }
local function GuildRanks()
    local out = {}
    local n = tonumber(GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then out[LC.Key(name)] = tonumber(rankIndex) end
    end
    return out
end

-- The council in the group: { [name] = unit }
function ML:Council()
    local db = DB()
    local ranks = GuildRanks()
    local extra = {}
    for n in tostring(db.mlCouncilNames or ""):gmatch("[^,%s]+") do extra[LC.Key(n):lower()] = true end
    local out = {}
    for name, unit in pairs(GroupByName()) do
        local r = ranks[name]
        if name == MyKey() or (r and r <= (db.mlCouncilRank or 1)) or extra[name:lower()] then out[name] = unit end
    end
    return out
end

-- ============================================
-- ITEMS TO SEND
-- ============================================

local function ItemString(link)
    local s = link and link:match("item:([%-%d:]+)")
    return s and (s:gsub(":+$", "")) or nil
end

function ML:Add(link, slot, boss)
    local s = ItemString(link)
    if not s then return false end
    for _, p in ipairs(self.pending) do
        if p.slot and slot and p.slot == slot then return false end
    end
    self.pending[#self.pending + 1] = { link = link, string = s, itemID = tonumber(s:match("^(%d+)")), slot = slot, boss = boss }
    if LC.RefreshML then LC:RefreshML() end
    return true
end

function ML:Remove(i)
    table.remove(self.pending, i)
    if LC.RefreshML then LC:RefreshML() end
end

function ML:Clear()
    wipe(self.pending)
    if LC.RefreshML then LC:RefreshML() end
end

-- The loot window opened: the items worth a vote
function ML:ScanLoot()
    if not self:IsML() or not DB().mlLootWindow then return 0 end
    local boss = UnitExists and UnitExists("target") and UnitName("target") or nil
    local n = 0
    for slot = 1, tonumber(GetNumLootItems and GetNumLootItems()) or 0 do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        if link then
            local _, _, quality = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)
            if (tonumber(quality) or 0) >= (DB().mlQuality or 4) and self:Add(link, slot, boss) then n = n + 1 end
        end
    end
    if n > 0 and LC.ShowML then LC:ShowML() end
    return n
end

-- ============================================
-- THE SESSION
-- ============================================

-- RCLootCouncil's master looter settings, in its short keys
function ML:MLDB()
    local db = DB()
    return { ["|8"] = { ["|14"] = { ["|5"] = 3 } }, ["|12"] = db.mlTimeout or 60, ["|1"] = true, ["|2"] = true }
end

-- Send the waiting items for answers and votes. test: test loot
-- The council as RCLootCouncil sends it: { [GUID without "Player-"] = true }
function ML:CouncilForTransmit()
    local council = {}
    for _, unit in pairs(self:Council()) do
        local g = UnitGUID and UnitGUID(unit)
        if g then council[(g:gsub("^Player%-", ""))] = true end
    end
    return council
end

-- Someone asked for the council or our settings (they logged in, reloaded
-- or joined after we sent them). Answered while we run a session; the
-- council at most once every 5 seconds, as many ask at once.
local councilSentAt = -100
function ML:OnRequest(command)
    if not (RC.session and RC.session.ml == MyKey()) or RC.local_ then return false end
    if command == "MLdb_request" then
        return RC:Send("mldb", { self:MLDB() })
    elseif command == "council_request" then
        local now = GetTime and tonumber(GetTime()) or 0
        if now - councilSentAt < 5 then return false end
        councilSentAt = now
        return RC:Send("council", { self:CouncilForTransmit() })
    end
    return false
end

function ML:Start(test)
    if not RC.local_ and not self:IsML() and not (test and IsInGroup and IsInGroup() and UnitIsGroupLeader and UnitIsGroupLeader("player")) then
        Print("Only the master looter (or the group leader, for test loot) can send loot for votes.")
        return false
    end
    if #self.pending == 0 then Print("No items to send. Open the loot window, Alt-click an item, or /wmachine council add <item>.") return false end
    self.test = test and true or false
    RC.testML = test and MyKey() or nil
    local council = self:CouncilForTransmit()
    local lt = {}
    self.sessionItems = {}
    for i, p in ipairs(self.pending) do
        lt[i] = { string = p.string, session = i, boss = p.boss }
        self.sessionItems[i] = p
    end
    wipe(self.pending)
    RC:Send("StartHandleLoot", {})
    RC:Send("mldb", { self:MLDB() })
    RC:Send("council", { council })
    RC:Send("lootTable", { lt })
    if test then self:Announce("(Test) Loot sent for votes: " .. #lt .. (#lt == 1 and " item." or " items.")) end
    if C_Timer then
        C_Timer.After(11 + 0.5 * #lt, function()
            if RC.session and RC.session.ml == MyKey() then RC:Send("offline_timer", {}) end
        end)
    end
    if LC.RefreshML then LC:RefreshML() end
    return true
end

function ML:End()
    if not RC.session then return end
    RC:Send("session_end", {})
    self.test, self.sessionItems = false, nil
    RC.testML = nil
end

function ML:Announce(text)
    if not DB().mlAnnounce or not SendChatMessage then return end
    local channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
    if channel then SendChatMessage(text, channel) end
end

-- ============================================
-- AWARDING
-- ============================================

-- Hand an item over from the open loot window (master loot)
-- Give an item from the open loot window (master loot): the slot holding
-- this item string (the hinted slot first)
function ML:GiveFromLoot(itemString, winner, slotHint)
    if not GiveMasterLoot or not GetMasterLootCandidate or not itemString then return false end
    local slots = {}
    if slotHint then slots[1] = slotHint end
    for s = 1, tonumber(GetNumLootItems and GetNumLootItems()) or 0 do slots[#slots + 1] = s end
    local short = LC.Short(winner)
    for _, slot in ipairs(slots) do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        if link and ItemString(link) == itemString then
            for i = 1, 40 do
                local cand = GetMasterLootCandidate(slot, i)
                if cand and (cand == short or LC.Key(cand) == winner) then
                    GiveMasterLoot(slot, i)
                    return true
                end
            end
            return false
        end
    end
    return false
end

-- Hand an awarded item over: from the loot window when it's there,
-- otherwise queued for a trade (opened now if the winner is close)
function ML:HandOver(link, winner, slotHint)
    local s = ItemString(link)
    if self:GiveFromLoot(s, winner, slotHint) then return "loot" end
    if winner == MyKey() then return "kept" end
    self.toTrade[#self.toTrade + 1] = { winner = winner, itemID = s and tonumber(s:match("^(%d+)")), link = link, t = Now() }
    self:TryTrade(winner)
    if LC.RefreshML then LC:RefreshML() end
    return "trade"
end

-- RCLootCouncil's history entry for an award
function ML:HistoryEntry(item, winner, cand, reason)
    local serverLocal = C_DateAndTime and C_DateAndTime.GetServerTimeLocal and C_DateAndTime.GetServerTimeLocal()
    local stamp = tonumber(serverLocal) or time()
    local dateFmt = serverLocal and "!%Y/%m/%d" or "%Y/%m/%d"
    local timeFmt = serverLocal and "!%H:%M:%S" or "%H:%M:%S"
    local r = reason and { text = reason, color = LC.HOW_COLORS.de } or RC:Response(item.typeCode, cand and (cand.realResponse or cand.response))
    local name, difficultyName, mapID, groupSize
    if GetInstanceInfo then
        local _
        name, _, _, difficultyName, _, _, _, mapID, groupSize = GetInstanceInfo()
    end
    historyCounter = historyCounter + 1
    return {
        lootWon = item.link, date = date(dateFmt, stamp), time = date(timeFmt, stamp),
        instance = name and (name .. "-" .. tostring(difficultyName or "")) or nil, boss = item.boss,
        votes = cand and cand.votes or 0, itemReplaced1 = cand and cand.gear1, itemReplaced2 = cand and cand.gear2,
        response = r.text, responseID = reason and 1 or (cand and (cand.realResponse or cand.response)),
        color = r.color, class = cand and cand.class, isAwardReason = reason and true or false,
        mapID = mapID, groupSize = groupSize, note = cand and cand.note,
        id = Now() .. "-" .. historyCounter, owner = MyKey(), typeCode = item.typeCode,
    }
end

-- Award a session's item. reason: "Disenchant" / "Banking" (award reasons)
function ML:Award(ses, winner, reason)
    local s = RC.session
    local item = s and s.items[ses]
    if not item or not winner then return false end
    if s.ml ~= MyKey() then Print("Only the master looter can award.") return false end
    local cand = s.candidates[ses] and s.candidates[ses][winner]
    local test = self.test or RC.local_
    -- Give it: from the loot window, else by trade
    if not test then
        local p = self.sessionItems and self.sessionItems[ses]
        self:HandOver(item.link, winner, p and p.slot)
    end
    -- Re-awarded: the earlier award's history goes
    if item.historyId and not test then RC:Send("delete_history", { item.historyId }) end
    RC:Send("awarded", { ses, winner, MyKey() })
    item.awarded = winner        -- (our own message also says so when it comes back)
    local r = reason or (cand and RC:Response(item.typeCode, cand.realResponse or cand.response).text) or "the council's choice"
    self:Announce((test and "(Test) " or "") .. (item.link or "?") .. " was awarded to " .. LC.Short(winner) .. " for " .. r .. "!")
    if not test then
        local entry = self:HistoryEntry(item, winner, cand, reason)
        item.historyId = entry.id
        LC.AddRCLC(winner, entry, nil, true)
        RC:Send("history", { winner, entry })
    end
    -- Everything awarded: the session ends
    local all = true
    for _, it in pairs(s.items) do if not it.awarded then all = false end end
    if all and C_Timer then C_Timer.After(1, function() if RC.session == s then ML:End() end end) end
    if LC.RefreshML then LC:RefreshML() end
    return true
end

-- ============================================
-- TRADING AWARDS (Gargul-style)
-- ============================================

-- Open a trade with the winner when they're close enough
function ML:TryTrade(winner)
    if not DB().mlAutoTrade or (InCombatLockdown and InCombatLockdown()) then return false end
    local unit = GroupByName()[winner]
    if not unit or not WM:InteractRange(unit, 2) then return false end
    if InitiateTrade then InitiateTrade(unit) return true end
    return false
end

-- The awards waiting for this player
function ML:WaitingFor(name)
    local out = {}
    for _, t in ipairs(self.toTrade) do if not t.done and t.winner == name then out[#out + 1] = t end end
    return out
end

local function BagFind(itemID, skip)
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local itemIdAt = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    if not numSlots or not itemIdAt then return nil end
    for bag = 0, 4 do
        for slot = 1, tonumber(numSlots(bag)) or 0 do
            if itemIdAt(bag, slot) == itemID and not skip[bag .. ":" .. slot] then return bag, slot end
        end
    end
end

-- The trade opened: put in everything awarded to this player
function ML:OnTradeShow()
    local partner = UnitName and UnitName("NPC")
    if not partner then return 0 end
    local waiting = self:WaitingFor(LC.Key(partner))
    local use = (C_Container and C_Container.UseContainerItem) or UseContainerItem
    local used, n = {}, 0
    for _, t in ipairs(waiting) do
        local bag, slot = BagFind(t.itemID, used)
        if bag and use then
            used[bag .. ":" .. slot] = true
            pcall(use, bag, slot)
            t.offered = true
            n = n + 1
        end
    end
    self.tradePartner = LC.Key(partner)
    return n
end

function ML:OnTradeDone()
    if not self.tradePartner then return end
    for _, t in ipairs(self.toTrade) do
        if t.offered and t.winner == self.tradePartner then t.done = true end
    end
    self.tradePartner = nil
    if LC.RefreshML then LC:RefreshML() end
end

-- ============================================
-- EVENTS
-- ============================================

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a1, a2)
    if not On() then return end
    if event == "LOOT_OPENED" then
        ML:ScanLoot()
    elseif event == "TRADE_SHOW" then
        ML:OnTradeShow()
    elseif event == "UI_INFO_MESSAGE" then
        local msg = a2 or a1
        if msg == ERR_TRADE_COMPLETE then ML:OnTradeDone() end
    elseif event == "TRADE_CLOSED" then
        if C_Timer then C_Timer.After(1, function() ML.tradePartner = nil end) end
    end
end)

function ML:Init()
    if self.started then return end
    self.started = true
    WM:RegisterEvents(events, { "LOOT_OPENED", "TRADE_SHOW", "TRADE_CLOSED", "UI_INFO_MESSAGE" })
    -- Alt-click any item to add it to the items to send (master looter)
    if hooksecurefunc and rawget(_G, "HandleModifiedItemClick") then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not On() or not DB().mlAltClick or not (IsAltKeyDown and IsAltKeyDown()) then return end
            if type(link) ~= "string" or not link:find("item:", 1, true) then return end
            if ML:IsML() or (IsInGroup and IsInGroup() and UnitIsGroupLeader and UnitIsGroupLeader("player")) then
                if ML:Add(link) and LC.ShowML then LC:ShowML() end
            end
        end)
    end
end

function ML:Stop()
    wipe(self.pending)
    self.test, self.sessionItems, self.tradePartner = false, nil, nil
end
