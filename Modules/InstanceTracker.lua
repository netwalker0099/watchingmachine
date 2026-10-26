-- Watching Machine: Instance Tracker
-- Logs every dungeon and raid you enter, on every character, and keeps the
-- instance limits: 5 instances an hour and 30 in 24 hours, per account.
--
-- A run is timed from when you LEAVE (the server's own rule), so the run
-- you're in now counts from when you entered until you come out.
--
-- Telling runs apart: the server gives each instance a number of its own
-- (the zone UID, the 5th field of every creature GUID inside it). The first
-- creature the addon sees sets the run's number; coming back into the same
-- number (a corpse run, another Scarlet Monastery wing on the same ID, a
-- disconnect) merges into the earlier run instead of logging a new one, so
-- it isn't counted twice. A reset makes the next visit a new run.
--
-- Each run keeps: the group (name, level, class), time in and out, mobs
-- killed by the group, XP gained, gold looted, your level in and out, and
-- reputation gained.
--
-- The way runs and lockouts are worked out follows Nova Instance Tracker's
-- approach (docs/NOVA-PROTOCOL.md, part 1, section 8); no code is shared.

local AddonName, WM = ...
local IT = {}
WM:RegisterModule("InstanceTracker", IT)
WM.InstanceTracker = IT

IT.version = "3.22"

local HOURLY_LIMIT, HOUR = 5, 3600
local DAILY_LIMIT, DAY = 30, 86400
local MAX_RUNS = 500

local DEFAULTS = {
    enabled = true,
    statsOnLeave = "self",      -- "off" / "self" / "group"
    announceReset = true,       -- tell your group when you reset
    mergeSame = true,           -- same instance number: merge, don't log again
    lockoutReady = true,        -- say when you can enter a new instance again
    enterMessage = true,        -- "Entered X (n/5 this hour) [X]" in chat
    novaListen = true,          -- show Nova Instance Tracker users' reset notices
    xpRate = true,              -- run stats: XP per hour and runs like it to level
}
IT.DEFAULTS = DEFAULTS

-- ============================================
-- SAVED DATA
-- ============================================

local function DB()
    if type(InstanceTrackerDB) ~= "table" then InstanceTrackerDB = {} end
    local db = InstanceTrackerDB
    if type(db.runs) ~= "table" then db.runs = {} end
    if type(db.nextId) ~= "number" then db.nextId = 1 end
    -- Every run has an id, for chat links (runs from before ids get one)
    for _, run in ipairs(db.runs) do
        if not run.id then run.id = db.nextId; db.nextId = db.nextId + 1 end
    end
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end
IT.DB = DB

local function Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" and t > 0 then return t end
    end
    return time()
end
IT.Now = Now

local function CharKey()
    local name = UnitName("player") or "?"
    local realm = (GetRealmName and GetRealmName()) or "?"
    return name .. "-" .. realm
end

function IT:Print(msg) WM:ModulePrint("InstanceTracker", msg) end

-- ============================================
-- CHAT LINKS
-- ============================================
-- Any line the tracker prints can be clicked to open the log. The red X on
-- the "Entered ..." line deletes that run (for an instance it got wrong).

local X_ICON = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:-1|t"

local function LogLink(text)
    if not WM.ChatLink then return text end
    return WM:ChatLink("itlog", "", text)
end
IT.LogLink = LogLink

local function DeleteLink(run)
    if not (WM.ChatLink and run.id) then return "" end
    return " " .. WM:ChatLink("itdel", run.id, X_ICON)
end

-- A printed line: the module prefix, then clickable text
function IT:PrintLink(msg, run)
    self:Print(LogLink(msg) .. (run and DeleteLink(run) or ""))
end

-- A client string, or the English one if it's missing
local function Text(value, english)
    return type(value) == "string" and value or english
end

-- ============================================
-- FORMATTING
-- ============================================

local function Duration(s)
    s = math.max(0, math.floor(s or 0))
    if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
    return s .. "s"
end
IT.Duration = Duration

local function Money(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return c .. "c"
end
IT.Money = Money

local function Commas(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- ============================================
-- RUNS
-- ============================================

local current          -- the run you're in, or nil

function IT:Runs() return DB().runs end
function IT:Current() return current end

-- The kind of place you're in: "party" / "raid", or nil outside instances
local function InstanceKind()
    local inside, kind = IsInInstance()
    if inside and (kind == "party" or kind == "raid") then return kind end
    return nil
end

local function InstanceDetails()
    local name, _, difficulty, _, _, _, _, mapID = GetInstanceInfo()
    return name, tonumber(mapID), difficulty
end

local function AddMember(run, unit)
    if not UnitExists(unit) then return end
    local name, realm = UnitName(unit)
    if not name or name == "" or name == Text(UNKNOWNOBJECT, "Unknown") then return end
    if realm and realm ~= "" then name = name .. "-" .. realm end
    for _, m in ipairs(run.group) do
        if m.name == name then
            m.level = UnitLevel(unit) or m.level
            return
        end
    end
    local _, class = UnitClass(unit)
    run.group[#run.group + 1] = { name = name, level = UnitLevel(unit), class = class }
end

function IT:UpdateGroup()
    if not current then return end
    AddMember(current, "player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do AddMember(current, "raid" .. i) end
    else
        for i = 1, 4 do AddMember(current, "party" .. i) end
    end
end

-- XP: tracked from UnitXP so rested, quest and kill XP all count
local lastXP, lastXPMax, lastLevel
local function SnapshotXP()
    lastXP, lastXPMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end

function IT:Enter()
    local kind = InstanceKind()
    if not kind then return end
    local name, mapID, difficulty = InstanceDetails()
    if not name then return end
    local now, char = Now(), CharKey()

    if current then
        if current.name == name then return end   -- a /reload or loading screen inside
        self:Leave()                              -- straight from one instance into another
    end

    -- Logged out or reloaded inside: carry on with that run
    local last = DB().runs[1]
    if last and last.char == char and last.name == name and not last.reset
        and (last.left == 0 or (last.loggedOut and now - last.left < HOUR)) then
        last.left, last.loggedOut = 0, nil
        current = last
    else
        current = {
            name = name, mapID = mapID, difficulty = difficulty, kind = kind,
            char = char, class = select(2, UnitClass("player")),
            entered = now, left = 0,
            levelIn = UnitLevel("player"), levelOut = nil,
            mobs = 0, xp = 0, gold = 0, rep = {}, group = {},
        }
        local db = DB()
        current.id = db.nextId
        db.nextId = db.nextId + 1
        table.insert(db.runs, 1, current)
        while #db.runs > MAX_RUNS do table.remove(db.runs) end
        if db.enterMessage then
            local l = self:Lockouts(now)
            self:PrintLink(string.format("Entered %s (%d/%d this hour, %d/%d today).",
                name, l.hour, l.hourLimit, l.day, l.dayLimit), current)
        end
    end
    SnapshotXP()
    self:UpdateGroup()
    self:RefreshUI()
end

function IT:Leave(loggingOut)
    local run = current
    if not run then return end
    current = nil
    run.left = Now()
    run.levelOut = UnitLevel("player")
    -- XP still needed for the next level (nil at the level cap)
    local max = tonumber(UnitXPMax("player")) or 0
    local cap = GetMaxPlayerLevel and tonumber(GetMaxPlayerLevel())
    local capped = (IsXPUserDisabled and IsXPUserDisabled() == true) or (cap and run.levelOut >= cap)
    run.xpToLevel = (not capped and max > 0) and math.max(0, max - (tonumber(UnitXP("player")) or 0)) or nil
    -- A whole level's XP at the level you leave on (for "% of a level")
    run.levelXP = (not capped and max > 0) and max or nil
    run.loggedOut = loggingOut or nil
    if not loggingOut then self:ReportRun(run) end
    self:RefreshUI()
end

-- A run's instance number, from a creature GUID seen inside it. Same number
-- as an earlier run of yours that wasn't reset: it's that run again.
function IT:SeeGUID(guid)
    if not current or current.zoneUID or type(guid) ~= "string" then return end
    local unitType, _, _, map, zoneUID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return end
    zoneUID = tonumber(zoneUID)
    if not zoneUID or zoneUID == 0 then return end
    if current.mapID and tonumber(map) ~= current.mapID then return end
    current.zoneUID = zoneUID

    if not DB().mergeSame then return end
    local runs = DB().runs
    for i = 2, #runs do
        local old = runs[i]
        if old.char == current.char and old.zoneUID == zoneUID and old.name == current.name and not old.reset then
            -- Fold this visit into the earlier run
            old.mobs, old.xp, old.gold = old.mobs + current.mobs, old.xp + current.xp, old.gold + current.gold
            for faction, n in pairs(current.rep) do old.rep[faction] = (old.rep[faction] or 0) + n end
            for _, m in ipairs(current.group) do
                local have = false
                for _, o in ipairs(old.group) do if o.name == m.name then have = true break end end
                if not have then old.group[#old.group + 1] = m end
            end
            old.left = 0
            table.remove(runs, 1)
            table.remove(runs, i - 1)
            table.insert(runs, 1, old)
            current = old
            self:PrintLink("Back in the same " .. old.name .. " (same instance), so it isn't counted again.")
            self:RefreshUI()
            return
        end
        if old.char == current.char and old.name == current.name then break end
    end
end

-- XP per hour over a run (nil: no XP, or too short to say)
function IT.XPPerHour(run)
    local secs = (run.left > 0 and run.left or Now()) - run.entered
    if (run.xp or 0) <= 0 or secs < 60 then return nil end
    return run.xp * 3600 / secs
end

-- The run's XP as a share of a level, in percent (nil: at the cap, or no XP)
function IT.LevelPercent(run)
    if not run.levelXP or run.levelXP <= 0 or (run.xp or 0) <= 0 then return nil end
    return run.xp * 100 / run.levelXP
end

function IT.PercentText(pct)
    if pct < 10 then return string.format("%.1f%%", pct) end
    return string.format("%d%%", math.floor(pct + 0.5))
end

-- How many more runs like this one to the next level (nil: at the cap, or
-- no XP from it)
function IT.RunsToLevel(run)
    if not run.xpToLevel or (run.xp or 0) <= 0 then return nil end
    return math.max(1, math.ceil(run.xpToLevel / run.xp))
end

-- Stats print when you leave
function IT:RunSummary(run)
    local secs = (run.left > 0 and run.left or Now()) - run.entered
    local parts = { run.name .. ": " .. Duration(secs) }
    if run.mobs > 0 then parts[#parts + 1] = run.mobs .. " mobs" end
    if run.xp > 0 then
        local notes = {}
        if run.mobs > 0 then notes[#notes + 1] = Commas(run.xp / run.mobs) .. "/mob" end
        local pct = DB().xpRate and IT.LevelPercent(run)
        if pct then notes[#notes + 1] = IT.PercentText(pct) .. " of a level" end
        parts[#parts + 1] = Commas(run.xp) .. " XP" .. (#notes > 0 and (" (" .. table.concat(notes, ", ") .. ")") or "")
        if DB().xpRate then
            local rate = IT.XPPerHour(run)
            if rate then parts[#parts + 1] = Commas(rate) .. " XP/hour" end
            local runs = IT.RunsToLevel(run)
            if runs then
                parts[#parts + 1] = runs .. " more run" .. (runs == 1 and "" or "s") .. " like this to level "
                    .. ((run.levelOut or UnitLevel("player")) + 1)
            end
        end
    end
    if run.gold > 0 then parts[#parts + 1] = Money(run.gold) .. " looted" end
    return table.concat(parts, ", ")
end

function IT:ReportRun(run)
    local mode = DB().statsOnLeave
    if mode == "off" then return end
    local text = self:RunSummary(run)
    if mode == "group" and IsInGroup() then
        SendChatMessage("[WM] " .. text, IsInRaid() and "RAID" or "PARTY")
    else
        self:PrintLink(text)
    end
end

-- ============================================
-- LOCKOUTS
-- ============================================
-- Counted over every character (the limits are per account). A run counts
-- from when you left it, or from when you entered if you're still inside.

function IT:Lockouts(now)
    now = now or Now()
    local hour, day, oldestHour, oldestDay = 0, 0, nil, nil
    for _, run in ipairs(DB().runs) do
        local t = (run.left and run.left > 0) and run.left or run.entered
        if t and now - t < DAY then
            day = day + 1
            if not oldestDay or t < oldestDay then oldestDay = t end
            if now - t < HOUR then
                hour = hour + 1
                if not oldestHour or t < oldestHour then oldestHour = t end
            end
        end
    end
    local info = {
        hour = hour, hourLimit = HOURLY_LIMIT,
        day = day, dayLimit = DAILY_LIMIT,
        -- When the oldest run in the window drops out, a slot frees up
        hourFree = oldestHour and math.max(0, HOUR - (now - oldestHour)) or 0,
        dayFree = oldestDay and math.max(0, DAY - (now - oldestDay)) or 0,
    }
    if day >= DAILY_LIMIT then
        info.locked, info.wait = "daily", math.max(info.dayFree, hour >= HOURLY_LIMIT and info.hourFree or 0)
    elseif hour >= HOURLY_LIMIT then
        info.locked, info.wait = "hourly", info.hourFree
    end
    return info
end

function IT:LockoutText(now)
    local l = self:Lockouts(now)
    local hourColor = (l.hour >= l.hourLimit) and "FF4444" or (l.hour >= l.hourLimit - 1) and "FFCC33" or "33FF33"
    local dayColor = (l.day >= l.dayLimit) and "FF4444" or (l.day >= l.dayLimit - 5) and "FFCC33" or "33FF33"
    local text = string.format("This hour: |cFF%s%d/%d|r", hourColor, l.hour, l.hourLimit)
    if l.hour > 0 and l.hour < l.hourLimit then text = text .. " (one frees in " .. Duration(l.hourFree) .. ")" end
    text = text .. string.format("   24 hours: |cFF%s%d/%d|r", dayColor, l.day, l.dayLimit)
    if l.locked == "hourly" then
        text = text .. "\n|cFFFF4444Hourly lockout:|r you can enter a new instance in " .. Duration(l.wait)
    elseif l.locked == "daily" then
        text = text .. "\n|cFFFF4444Daily lockout (30 in 24 hours):|r you can enter a new instance in " .. Duration(l.wait)
    end
    return text, l
end

function IT:PrintLockouts()
    local text = self:LockoutText()
    for line in text:gmatch("[^\n]+") do self:PrintLink(line) end
end

-- Say once when a full limit has room again
local wasLocked
function IT:CheckLockoutReady()
    local l = self:Lockouts()
    if wasLocked and not l.locked and DB().lockoutReady then
        self:PrintLink("|cFF33FF33You can enter a new instance now.|r")
    end
    wasLocked = l.locked
end

-- ============================================
-- RESETS
-- ============================================

-- "%s has been reset." etc. as Lua patterns capturing the instance name
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end
IT.Pattern = Pattern

local resetPattern, resetFailPattern, tooManyText

local function Patterns()
    if not resetPattern then
        resetPattern = Pattern(Text(INSTANCE_RESET_SUCCESS, "%s has been reset."))
        resetFailPattern = Pattern(Text(INSTANCE_RESET_FAILED, "Cannot reset %s.  There are players still inside the instance."))
        tooManyText = Text(TRANSFER_ABORT_TOO_MANY_INSTANCES, "You have entered too many instances recently.")
    end
end

-- Your resets: later visits are new instances (only this character's
-- instances are reset)
function IT:MarkReset(name)
    local char = CharKey()
    for _, run in ipairs(DB().runs) do
        if run.name == name and run.char == char and run ~= current then run.reset = true end
    end
end

function IT:OnSystemMessage(msg)
    Patterns()
    local name = msg:match(resetPattern)
    if name then
        self:MarkReset(name)
        if DB().announceReset and IsInGroup() and UnitIsGroupLeader("player") then
            SendChatMessage("[WM] " .. name .. " has been reset.", IsInRaid() and "RAID" or "PARTY")
        end
        if self.SendResetNotice then self:SendResetNotice(name) end
        return
    end
    if msg == tooManyText or msg:find(tooManyText, 1, true) then
        self:PrintLockouts()
    end
end

-- ============================================
-- RUN STATS
-- ============================================

local repPattern, moneyPatterns

local function MoneyFromText(msg)
    if not moneyPatterns then
        moneyPatterns = {
            { Pattern(Text(GOLD_AMOUNT, "%d Gold")), 10000 },
            { Pattern(Text(SILVER_AMOUNT, "%d Silver")), 100 },
            { Pattern(Text(COPPER_AMOUNT, "%d Copper")), 1 },
        }
        for _, p in ipairs(moneyPatterns) do p[1] = p[1]:gsub("^%^", ""):gsub("%$$", "") end
    end
    local total = 0
    for _, p in ipairs(moneyPatterns) do
        local n = msg:match(p[1])
        if n then total = total + tonumber(n) * p[2] end
    end
    return total
end
IT.MoneyFromText = MoneyFromText

function IT:OnMoney(msg)
    if current then current.gold = current.gold + MoneyFromText(msg) end
end

function IT:OnReputation(msg)
    if not current then return end
    repPattern = repPattern or Pattern(Text(FACTION_STANDING_INCREASED, "Your %s reputation has increased by %d."))
    local faction, amount = msg:match(repPattern)
    if faction and tonumber(amount) then
        current.rep[faction] = (current.rep[faction] or 0) + tonumber(amount)
    end
end

function IT:OnXP()
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if current and lastXP then
        local gained
        if level > lastLevel then gained = (lastXPMax - lastXP) + xp
        else gained = xp - lastXP end
        if gained > 0 then current.xp = current.xp + gained end
    end
    lastXP, lastXPMax, lastLevel = xp, xpMax, level
end

local GROUP_MASK = 0x00000007   -- mine, party or raid

function IT:OnCombatEvent(_, sub, _, srcGUID, _, srcFlags, _, dstGUID)
    if not current then return end
    if not current.zoneUID then
        self:SeeGUID(dstGUID)
        self:SeeGUID(srcGUID)
    end
    if sub == "PARTY_KILL" and type(dstGUID) == "string" and dstGUID:find("^Creature")
        and bit.band(srcFlags or 0, GROUP_MASK) ~= 0 then
        current.mobs = current.mobs + 1
    end
end

-- ============================================
-- WINDOW
-- ============================================

local panel

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "ffffff"
end

local function When(t)
    return date("%d %b %H:%M", t)
end

function IT:ShowRunTooltip(owner, run)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(run.name .. (run.kind == "raid" and " (raid)" or ""), 1, 0.8, 0)
    local name = run.char:match("^[^-]+") or run.char
    GameTooltip:AddLine("|cFF" .. ClassColor(run.class) .. name .. "|r  " .. (run.char:match("%-(.+)$") or ""), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Entered", When(run.entered), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Left", run.left > 0 and When(run.left) or "still inside", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Time inside", Duration((run.left > 0 and run.left or Now()) - run.entered), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Mobs killed", run.mobs, 0.8, 0.8, 0.8, 1, 1, 1)
    if run.xp > 0 then
        GameTooltip:AddDoubleLine("XP", Commas(run.xp), 0.8, 0.8, 0.8, 1, 1, 1)
        if run.mobs > 0 then GameTooltip:AddDoubleLine("XP per mob", Commas(run.xp / run.mobs), 0.8, 0.8, 0.8, 1, 1, 1) end
        local pct = IT.LevelPercent(run)
        if pct then GameTooltip:AddDoubleLine("Share of a level", IT.PercentText(pct), 0.8, 0.8, 0.8, 1, 1, 1) end
        local rate = IT.XPPerHour(run)
        if rate then GameTooltip:AddDoubleLine("XP per hour", Commas(rate), 0.8, 0.8, 0.8, 1, 1, 1) end
        local runs = IT.RunsToLevel(run)
        if runs then
            GameTooltip:AddDoubleLine("Runs like it to level " .. ((run.levelOut or 0) + 1), runs, 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    GameTooltip:AddDoubleLine("Gold looted", Money(run.gold), 0.8, 0.8, 0.8, 1, 1, 1)
    -- Trades are logged by Mail & Trade Logger, tagged with the run
    local ML = WM:IsModuleOn("MailLogger") and WM.modules.MailLogger
    if ML and ML.GoldTradedInRun then
        local received, given, count = ML:GoldTradedInRun(run.id, run.char)
        if count > 0 then
            GameTooltip:AddDoubleLine("Gold traded (" .. count .. (count == 1 and " trade)" or " trades)"),
                "|cFF33FF33+" .. Money(received) .. "|r  |cFFFF6633-" .. Money(given) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    local levels = "Level " .. (run.levelIn or "?")
    if run.levelOut and run.levelOut ~= run.levelIn then levels = levels .. " → " .. run.levelOut .. " (ding!)" end
    GameTooltip:AddDoubleLine("Your level", levels, 0.8, 0.8, 0.8, 1, 1, 1)
    if next(run.rep) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Reputation", 1, 0.8, 0)
        for faction, n in pairs(run.rep) do GameTooltip:AddDoubleLine(faction, "+" .. Commas(n), 0.8, 0.8, 0.8, 0.3, 1, 0.3) end
    end
    if #run.group > 0 then
        GameTooltip:AddLine(" ")
        local total = 0
        for _, m in ipairs(run.group) do total = total + (m.level or 0) end
        GameTooltip:AddLine(string.format("Group (average level %.1f)", total / #run.group), 1, 0.8, 0)
        for _, m in ipairs(run.group) do
            GameTooltip:AddDoubleLine("|cFF" .. ClassColor(m.class) .. m.name .. "|r", m.level and ("Level " .. m.level) or "", 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    if run.reset then GameTooltip:AddLine(" "); GameTooltip:AddLine("Reset since.", 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to delete this entry.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function IT:RunById(id)
    id = tonumber(id)
    for _, run in ipairs(DB().runs) do
        if run.id == id then return run end
    end
end

-- From the chat X: ask, then delete
function IT:ConfirmDelete(run)
    if not run then
        self:Print("That run is no longer in the log.")
        return
    end
    WM:Confirm("Delete " .. run.name .. " (" .. date("%d %b %H:%M", run.entered) .. ") from the instance log?"
        .. " It stops counting toward your lockouts.", function()
        IT:DeleteRun(run)
        IT:Print("Deleted " .. run.name .. " from the instance log.")
    end)
end

function IT:DeleteRun(run)
    local runs = DB().runs
    for i, r in ipairs(runs) do
        if r == run then
            table.remove(runs, i)
            if run == current then current = nil end
            break
        end
    end
    self:RefreshUI()
end

local ROW_H = 20

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetWidth(170)
    row.name:SetJustifyH("LEFT")
    row.char = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.char:SetPoint("LEFT", 180, 0)
    row.char:SetWidth(100)
    row.char:SetJustifyH("LEFT")
    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.when:SetPoint("LEFT", 285, 0)
    row.when:SetWidth(90)
    row.when:SetJustifyH("LEFT")
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("RIGHT", -6, 0)
    row.info:SetJustifyH("RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self) if self.run then IT:ShowRunTooltip(self, self.run) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.run then
            IT:ConfirmDelete(self.run)
        end
    end)
    return row
end

function IT:RefreshList()
    if not panel or not panel.listChild then return end
    local child, rows = panel.listChild, panel.rows
    local width = math.max(300, (panel:GetWidth() or 520) - 50)
    child:SetWidth(width)
    local filter = panel.showAll and nil or CharKey()
    local n = 0
    for _, run in ipairs(DB().runs) do
        if not filter or run.char == filter then
            n = n + 1
            local row = rows[n] or NewRow(child)
            rows[n] = row
            row.run = run
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(n - 1) * ROW_H)
            row:SetWidth(width)
            row.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.05 or 0.02)
            local name = run.name
            if run == current then name = "|cFF33FF33" .. name .. " (now)|r" end
            if run.reset then name = "|cFF999999" .. name .. "|r" end
            row.name:SetText(name)
            row.char:SetText("|cFF" .. ClassColor(run.class) .. (run.char:match("^[^-]+") or run.char) .. "|r")
            row.when:SetText(When(run.entered))
            local secs = (run.left > 0 and run.left or Now()) - run.entered
            row.info:SetText(Duration(secs) .. "  |cFF999999" .. run.mobs .. " mobs|r")
            row:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].run = nil end
    child:SetHeight(math.max(1, n * ROW_H))
    if panel.emptyText then panel.emptyText:SetShown(n == 0) end
end

IT.STATS_OPTIONS = {
    { value = "off", text = "Off" },
    { value = "self", text = "My chat window" },
    { value = "group", text = "My group" },
}

function IT:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_InstanceTrackerFrame", title = "Instance Tracker", titleColor = "66CCFF",
        width = 560, height = 520, minHeight = 360, scroll = false,
        resizable = { 460, 360, 1000, 1200 },
        onResize = function() IT:RefreshList() end,
        onRefresh = function() IT:RefreshList() end,
    })
    local L = panel.layout

    local row = L:Row(34)
    panel.lockoutText = row:Text({ text = function() return (IT:LockoutText()) end, width = 500 }, 8)

    L:Section({ key = "options", title = "Options" })
    L:Checkbox({
        label = "Merge going back into the same instance",
        get = function() return DB().mergeSame end, set = function(v) DB().mergeSame = v end,
        tooltip = { "Same instance", "Coming back into the same instance (a corpse run, another wing on the"
            .. " same ID, a disconnect) adds to the earlier run instead of logging, and counting, a new one." },
    })
    L:Checkbox({
        label = "Tell my group when I reset instances",
        get = function() return DB().announceReset end, set = function(v) DB().announceReset = v end,
        tooltip = { "Reset announcement", "As group leader, a reset posts \"[WM] <instance> has been reset.\""
            .. " in party or raid chat." },
    })
    L:Checkbox({
        label = "Show resets from leaders using Nova Instance Tracker",
        get = function() return DB().novaListen end, set = function(v) DB().novaListen = v end,
        tooltip = { "Nova Instance Tracker", "When your group leader runs Nova Instance Tracker (or Nova World"
            .. " Buffs) and resets, their addon tells the group; this shows it and marks the instance as reset."
            .. " Only the leader of your own group is believed. Watching Machine only listens: it never sends in"
            .. " Nova's format." },
    })
    L:Checkbox({
        label = "Say when I can enter a new instance again",
        get = function() return DB().lockoutReady end, set = function(v) DB().lockoutReady = v end,
    })
    L:Checkbox({
        label = "Say when I enter an instance",
        get = function() return DB().enterMessage end, set = function(v) DB().enterMessage = v end,
        tooltip = { "Entering an instance", "\"Entered <instance> (3/5 this hour, 7/30 today).\" Click the line"
            .. " to open the log; click the red X to delete that run if it shouldn't count." },
    })
    L:Dropdown({
        label = "Run stats when leaving:", width = 130, options = IT.STATS_OPTIONS,
        get = function() return DB().statsOnLeave end, set = function(v) DB().statsOnLeave = v end,
        tooltip = { "Run stats", "Time, mobs, XP and gold for the run you've just left, in your chat window or"
            .. " your group's chat." },
    })
    L:Checkbox({
        label = "Add % of a level, XP per hour and runs to level",
        get = function() return DB().xpRate end, set = function(v) DB().xpRate = v end,
        tooltip = { "XP per hour", "Run stats also give the run's XP as a share of a level, its XP per hour, and how"
            .. " many more runs like it take you to the next level (from the XP you still need when you leave). Not at"
            .. " the level cap." },
    })
    L:EndSection()

    row = L:Row(22)
    row:Checkbox({
        label = "All characters",
        get = function() return panel.showAll end,
        set = function(v) panel.showAll = v; IT:RefreshList() end,
    }, 8)
    row:Text({ text = "|cFF888888Hover a run for its stats, right-click to delete it.|r" }, 140)

    local fill = L:Fill(160)
    local scroll = CreateFrame("ScrollFrame", "WM_InstanceTrackerScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    scroll:SetScrollChild(child)
    panel.listChild, panel.rows = child, {}
    panel.emptyText = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.emptyText:SetPoint("TOP", 0, -20)
    panel.emptyText:SetText("|cFF888888No instances logged yet.|r")
    panel.showAll = true

    panel:AddFooterButton({ text = "Print lockouts", width = 110, onClick = function() IT:PrintLockouts() end }, "LEFT")
    panel:AddFooterButton({ text = "Your Characters", width = 120,
        onClick = function()
            local AT = WM:UsableModule("AltTracker")
            if AT then AT:Toggle() end
        end }, "RIGHT")
    panel:Finish()
    -- Lockout countdowns tick while open
    local since = 0
    panel:HookScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since >= 1 then
            since = 0
            panel.lockoutText:Refresh()
            if current then IT:RefreshList() end
        end
    end)
    return panel
end

function IT:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function IT:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
IT.ToggleUI = IT.Toggle

-- Dashboard / minimap status
function IT:GetQuickStatus()
    local l = self:Lockouts()
    if l.locked == "hourly" then return "|cFFFF4444Hourly lockout|r, " .. Duration(l.wait) end
    if l.locked == "daily" then return "|cFFFF4444Daily lockout|r, " .. Duration(l.wait) end
    local s = string.format("%d/%d this hour, %d/%d today", l.hour, l.hourLimit, l.day, l.dayLimit)
    if current then s = "|cFF33FF33In " .. current.name .. "|r, " .. s end
    return s
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

function IT:OnEvent(event, ...)
    if not WM:IsModuleOn("InstanceTracker") then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if InstanceKind() then self:Enter() elseif current then self:Leave() end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if current and CombatLogGetCurrentEventInfo then self:OnCombatEvent(CombatLogGetCurrentEventInfo()) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if current then self:SeeGUID(UnitGUID("target")) end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if current then self:SeeGUID(UnitGUID("mouseover")) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if current then self:SeeGUID(UnitGUID((...))) end
    elseif event == "CHAT_MSG_SYSTEM" then
        self:OnSystemMessage((...) or "")
    elseif event == "CHAT_MSG_MONEY" then
        self:OnMoney((...) or "")
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        self:OnReputation((...) or "")
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        self:OnXP()
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:UpdateGroup()
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_CAMPING" then
        if current then self:Leave(true) end
    end
end

function IT:Initialize()
    DB()
    SnapshotXP()
    WM:RegisterEvents(events, {
        "PLAYER_ENTERING_WORLD", "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_TARGET_CHANGED",
        "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "CHAT_MSG_SYSTEM", "CHAT_MSG_MONEY",
        "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
        "GROUP_ROSTER_UPDATE", "PLAYER_LOGOUT", "PLAYER_CAMPING",
    })
    if WM.Nova then WM.Nova:Start() end
    if WM.RegisterChatLink then
        WM:RegisterChatLink("itlog", function()
            if not WM:UsableModule("InstanceTracker") then return end
            local p = IT:CreateUI()
            if not p:IsShown() then p:Show() end
        end)
        WM:RegisterChatLink("itdel", function(id)
            if WM:UsableModule("InstanceTracker") then IT:ConfirmDelete(IT:RunById(id)) end
        end)
    end
    -- Already inside when the addon starts (login or /reload in an instance)
    if InstanceKind() then self:Enter() end
    wasLocked = self:Lockouts().locked
    WM.RunTicker(30, function()
        if WM:IsModuleOn("InstanceTracker") then IT:CheckLockoutReady() end
    end)
end

-- Turned off: close the window, and end the run you're in quietly (kept as
-- if you'd logged out, so turning it back on inside carries the run on)
function IT:OnModuleOff()
    if panel then panel:Hide() end
    if current then self:Leave(true) end
end

-- Turned back on: pick up the instance you're in
function IT:OnModuleOn()
    DB()
    SnapshotXP()
    if InstanceKind() then self:Enter() end
    wasLocked = self:Lockouts().locked
end

-- The module's page in the guided setup
function IT:SetupPage(L)
    DB()
    L:Note("The game lets each account enter only 5 instances an hour and 30 a day. This logs every dungeon and raid"
        .. " you enter, on all your characters, so you can see how many you have left and when the next one frees up.")
    L:Note("|cFFFFFFFFHow it works:|r entering an instance prints \"Entered <instance> (2/5 this hour, 4/30 today)\"."
        .. " A run counts from when you leave, as the server counts it. Going back into the same instance (a"
        .. " corpse run, another wing) isn't counted twice; a reset makes the next visit a new run. Each run keeps"
        .. " the group, time inside, mobs killed, XP, gold looted and reputation: hover it in the list.")
    L:Checkbox({ label = "Say when I enter an instance", get = function() return DB().enterMessage end,
        set = function(v) DB().enterMessage = v end,
        tooltip = { "Entering an instance", "A chat line with your counts for the hour and the day. Click it to open"
            .. " the log; the red X deletes that run if it shouldn't count." } })
    L:Checkbox({ label = "Say when I can enter a new instance again", get = function() return DB().lockoutReady end,
        set = function(v) DB().lockoutReady = v end,
        tooltip = { "Lockout over", "When you've hit the 5 an hour or 30 a day, a chat line tells you once a slot is free." } })
    L:Checkbox({ label = "Merge going back into the same instance", get = function() return DB().mergeSame end,
        set = function(v) DB().mergeSame = v end,
        tooltip = { "Same instance", "Coming back into the same instance adds to the earlier run instead of logging,"
            .. " and counting, a new one." } })
    L:Checkbox({ label = "Tell my group when I reset instances", get = function() return DB().announceReset end,
        set = function(v) DB().announceReset = v end,
        tooltip = { "Reset announcement", "As group leader, a reset posts \"[WM] <instance> has been reset.\" in"
            .. " party or raid chat." } })
    L:Checkbox({ label = "Show resets from leaders using Nova Instance Tracker", get = function() return DB().novaListen end,
        set = function(v) DB().novaListen = v end,
        tooltip = { "Nova Instance Tracker", "When your group leader resets with Nova Instance Tracker (or Nova World"
            .. " Buffs), their addon tells the group; this shows it and marks the instance as reset. It only listens." } })
    L:Dropdown({ label = "Run stats when leaving:", width = 130, options = IT.STATS_OPTIONS,
        get = function() return DB().statsOnLeave end, set = function(v) DB().statsOnLeave = v end,
        tooltip = { "Run stats", "Time, mobs, XP and gold for the run you've just left, in your chat window or your"
            .. " group's chat, or not at all." } })
    L:Checkbox({ label = "Add % of a level, XP per hour and runs to level", get = function() return DB().xpRate end,
        set = function(v) DB().xpRate = v end,
        tooltip = { "XP per hour", "\"18,300 XP (300/mob, 23% of a level), 45,750 XP/hour, 4 more runs like this to"
            .. " level 62\": the run's XP as a share of a level, its XP per hour, and how many more runs like it you"
            .. " need for the next level. Not at the level cap." } })
    L:Note("The log, your counts and every run's details are in its window: |cFFFFFF00/wmachine instances|r.")
end

events:SetScript("OnEvent", function(_, event, ...) IT:OnEvent(event, ...) end)
