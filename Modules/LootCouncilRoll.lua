-- Watching Machine: Loot Council roll-offs (Gargul-style)
-- The master looter (or group leader) puts an item up for rolls:
--   * announced to the raid ("You have 20 seconds to roll on [item] -
--     /roll for MS, /roll 99 for OS"), with a countdown and "Stop your
--     rolls!" at the end
--   * every /roll in the group is read: 1-100 is main spec, 1-99 off spec
--     (the ranges are settings); a second roll of the same kind doesn't count
--   * the roll window lists them, main spec first then highest, each with the
--     player's last loot (hover for their last 30 days)
--   * Award gives it from the loot window or by trade, announces it and logs
--     it with the rolls; Disenchant sends it to the disenchanter
--   * raiders running Watching Machine get Roll MS / Roll OS / Pass buttons
-- Facts about roll-offs compiled with the help of Gargul's research; the
-- code is our own.

local AddonName, WM = ...
local LC = WM.LootCouncil
local Roll = {}
LC.Roll = Roll

local PREFIX = "WMLoot"
local LEEWAY = 1            -- seconds after the end a roll still counts

local function On() return WM:IsModuleOn("LootCouncil") end
local function DB() return LC.DB() end
local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end
local function MyKey() return LC.Key(UnitName("player")) end
local function Print(msg) WM:ModulePrint("LootCouncil", msg) end

Roll.cur = nil      -- { link, string, itemID, ends, note, rolls = { { name, class, roll, min, max, kind, prio, repeat_ } }, open }

-- The kinds of roll: label, low, high, priority (lower wins first)
function Roll.Kinds()
    local db = DB()
    return {
        { label = "MS", low = 1, high = db.rollMS or 100, prio = 1, how = "Mainspec roll" },
        { label = "OS", low = 1, high = db.rollOS or 99, prio = 2, how = "Offspec roll" },
    }
end

local function ItemString(link)
    local s = link and link:match("item:([%-%d:]+)")
    return s and (s:gsub(":+$", "")) or nil
end

local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

-- Raid warning when we may, else the group; alone, our own chat
local function Say(text, warning)
    local channel = GroupChannel()
    if not channel or not SendChatMessage then Print(text) return end
    if warning and channel == "RAID" and DB().rollWarning then
        local lead = (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        if lead then channel = "RAID_WARNING" end
    end
    SendChatMessage(text, channel)
end

function Roll.CanRun()
    if not On() then return false end
    if not (IsInGroup and IsInGroup()) then return true end      -- alone: to try it
    if LC.ML and LC.ML:IsML() then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false
end

-- ============================================
-- RUNNING A ROLL-OFF
-- ============================================

local ticker

function Roll:Start(link, seconds, note)
    if not Roll.CanRun() then Print("Only the master looter, group leader or an assistant can start a roll-off.") return false end
    local s = ItemString(link)
    if not s then Print("That isn't an item link.") return false end
    if self.cur and self.cur.open then self:Stop(true) end
    seconds = math.max(5, tonumber(seconds) or DB().rollSeconds or 20)
    note = note or DB().rollNote or ""
    self.cur = { link = link, string = s, itemID = tonumber(s:match("^(%d+)")), ends = time() + seconds,
        seconds = seconds, note = note, rolls = {}, open = true, by = MyKey() }
    Say("You have " .. seconds .. " seconds to roll on " .. link .. (note ~= "" and (" - " .. note) or ""), true)
    -- Raiders running Watching Machine get roll buttons
    local channel = GroupChannel()
    if channel then WM:QueueAddonMessage(PREFIX, "R^" .. s .. "^" .. seconds .. "^" .. note:gsub("%^", " "), channel, nil, true) end
    if ticker then ticker:Cancel() end
    local said = {}
    if C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(1, function() Roll:Tick(said) end)
    end
    if LC.ShowRolls then LC:ShowRolls() end
    return true
end

-- Every second: the countdown, then the end
function Roll:Tick(said)
    local cur = self.cur
    if not cur or not cur.open then if ticker then ticker:Cancel(); ticker = nil end return end
    local left = cur.ends - time()
    local count = DB().rollCountdown or 5
    if left > 0 and left <= count and not said[left] then
        said[left] = true
        Say(tostring(left))
    end
    if left <= 0 then self:Stop() end
    if LC.RefreshRolls then LC:RefreshRolls() end
end

function Roll:Stop(quiet)
    local cur = self.cur
    if not cur or not cur.open then return end
    cur.open = false
    cur.closed = time()
    if ticker then ticker:Cancel(); ticker = nil end
    if not quiet then Say("Stop your rolls!", true) end
    local channel = GroupChannel()
    if channel then WM:QueueAddonMessage(PREFIX, "S^" .. cur.string, channel, nil, true) end
    if LC.RefreshRolls then LC:RefreshRolls() end
end

-- ============================================
-- READING /ROLL
-- ============================================

local rollPattern
local function RollPattern()
    if rollPattern then return rollPattern end
    local fmt = type(RANDOM_ROLL_RESULT) == "string" and RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    p = p:gsub("%%d", "(%%d+)")
    rollPattern = "^" .. p .. "$"
    return rollPattern
end
Roll.Pattern = RollPattern

-- A system message: a roll, if it's one we're watching
function Roll:OnSystem(msg)
    local cur = self.cur
    if not cur or type(msg) ~= "string" then return false end
    if not cur.open and (not cur.closed or time() - cur.closed > LEEWAY) then return false end
    local who, amount, low, high = msg:match(RollPattern())
    amount, low, high = tonumber(amount), tonumber(low), tonumber(high)
    if not who or not amount then return false end
    local name = LC.Key(who)
    -- Only the group (or us, alone)
    local unit = LC.ML and LC.ML.GroupByName()[name]
    if not unit and IsInGroup and IsInGroup() then return false end
    local kind
    for _, k in ipairs(Roll.Kinds()) do if k.low == low and k.high == high then kind = k end end
    if not kind then return false end
    local repeat_ = false
    for _, r in ipairs(cur.rolls) do if r.name == name and r.kind == kind.label then repeat_ = true end end
    local _, class
    if unit then _, class = UnitClass(unit) else _, class = UnitClass("player") end
    cur.rolls[#cur.rolls + 1] = { name = name, class = class, roll = amount, min = low, max = high,
        kind = kind.label, how = kind.how, prio = kind.prio, repeat_ = repeat_ or nil }
    if LC.RefreshRolls then LC:RefreshRolls() end
    return true
end

-- The rolls in award order: main spec first, then highest; repeats last
function Roll:Sorted()
    local out = {}
    for _, r in ipairs(self.cur and self.cur.rolls or {}) do out[#out + 1] = r end
    table.sort(out, function(a, b)
        if (a.repeat_ and 1 or 0) ~= (b.repeat_ and 1 or 0) then return not a.repeat_ end
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.name < b.name
    end)
    return out
end

-- ============================================
-- AWARDING THE ROLL-OFF
-- ============================================

local counter = 0

-- Award to a player who rolled (their best roll says how), or for a reason
-- ("Disenchant"). Gives it, announces it and logs it with the rolls.
function Roll:Award(name, reason)
    local cur = self.cur
    if not cur or not name then return false end
    if cur.open then self:Stop(true) end
    local best
    for _, r in ipairs(self:Sorted()) do if r.name == name and not best then best = r end end
    local how = reason or (best and best.how) or "Awarded"
    local where = LC.ML and LC.ML:HandOver(cur.link, name) or "kept"
    Say(cur.link .. " was awarded to " .. LC.Short(name) .. " for " .. (reason or ((best and (best.kind .. " roll (" .. best.roll .. ")")) or "the roll")) .. "!")
    local rolls = {}
    for _, r in ipairs(self:Sorted()) do rolls[#rolls + 1] = { name = r.name, roll = r.roll, type = r.kind, max = r.max } end
    counter = counter + 1
    local _, isNew = LC.Add({ link = cur.link, to = name, by = MyKey(), t = Now(), how = how, howFirm = true,
        color = LC.HOW_COLORS[reason and "de" or LC.Kind(how)], reason = reason and true or nil, rolls = rolls,
        class = best and best.class, boss = cur.boss, src = { wm = "roll:" .. Now() .. ":" .. counter }, srcKind = "wm" })
    -- RCLootCouncil users record it too, in its history format
    if LC.RC and LC.RC.Send and GroupChannel() and LC.ML and LC.ML.HistoryEntry then
        local fake = { link = cur.link, boss = cur.boss, typeCode = "default" }
        local entry = LC.ML:HistoryEntry(fake, name, { votes = 0, class = best and best.class }, reason)
        entry.response = how
        entry.color = LC.HOW_COLORS[reason and "de" or LC.Kind(how)]
        LC.RC:Send("history", { name, entry })
    end
    cur.awarded, cur.where = name, where
    if LC.RefreshRolls then LC:RefreshRolls() end
    return true, where
end

-- ============================================
-- RAIDERS: ROLL BUTTONS
-- ============================================

Roll.prompt = nil      -- { link, ends } shown to a raider

function Roll:OnAddonMessage(prefix, body, dist, sender)
    if prefix ~= PREFIX or not On() or type(body) ~= "string" then return end
    sender = LC.Key(sender)
    if sender == MyKey() then return end
    -- Only from the master looter or a group leader
    local fromLead = false
    local unit = LC.ML and LC.ML.GroupByName()[sender]
    if unit then
        fromLead = (UnitIsGroupLeader and UnitIsGroupLeader(unit)) or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit))
            or (LC.RC and LC.RC.MasterLooter() == sender)
    end
    if not fromLead then return end
    local kind, s, seconds, note = body:match("^(%a)%^([%-%d:]+)%^?(%d*)%^?(.*)$")
    if kind == "R" and DB().rollButtons then
        local _, link = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)("item:" .. s)
        self.prompt = { link = link or ("item:" .. s), string = s, ends = time() + (tonumber(seconds) or 20), note = note }
        if LC.ShowRollPrompt then LC:ShowRollPrompt() end
    elseif kind == "S" then
        self.prompt = nil
        if LC.HideRollPrompt then LC:HideRollPrompt() end
    end
end

-- A raider's button: roll for a kind ("MS" / "OS"), or pass
function Roll:RollFor(label)
    if label then
        for _, k in ipairs(Roll.Kinds()) do
            if k.label == label and RandomRoll then RandomRoll(k.low, k.high) end
        end
    end
    self.prompt = nil
    if LC.HideRollPrompt then LC:HideRollPrompt() end
end

-- ============================================
-- EVENTS
-- ============================================

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if not On() then return end
    if event == "CHAT_MSG_SYSTEM" then Roll:OnSystem(a1)
    elseif event == "CHAT_MSG_ADDON" then Roll:OnAddonMessage(a1, a2, a3, a4) end
end)

function Roll:Init()
    if self.started then return end
    self.started = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    WM:RegisterEvents(events, { "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON" })
end

function Roll:Stop_All()
    if ticker then ticker:Cancel(); ticker = nil end
    self.cur, self.prompt = nil, nil
    WM:ClearAddonQueue({ [PREFIX] = true })
end
