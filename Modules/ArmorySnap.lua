-- Watching Machine: ArmorySnap Module
-- Passively snapshots gear, enchants, gems, and talents for your entire raid
-- and keeps a browsable archive. Ported from the standalone ArmorySnap addon
-- (v1.2.0) with its event-chained inspect queue: the next inspect fires the
-- moment the previous one resolves, so a full 25-man captures in ~15-20s
-- instead of 75+.
--
-- Uses the ArmorySnapDB saved variable, so archives from the standalone
-- addon carry over. If the standalone addon is still enabled, this module
-- stands down to avoid double-inspecting.

local AddonName, WM = ...
local AS = {}
WM:RegisterModule("ArmorySnap", AS)

AS.version = "2.9"

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
AS.SLOT_INFO = {
    [1]  = { name = "HeadSlot",          label = "Head" },
    [2]  = { name = "NeckSlot",          label = "Neck" },
    [3]  = { name = "ShoulderSlot",      label = "Shoulder" },
    [4]  = { name = "ShirtSlot",         label = "Shirt" },
    [5]  = { name = "ChestSlot",         label = "Chest" },
    [6]  = { name = "WaistSlot",         label = "Waist" },
    [7]  = { name = "LegsSlot",          label = "Legs" },
    [8]  = { name = "FeetSlot",          label = "Feet" },
    [9]  = { name = "WristSlot",         label = "Wrist" },
    [10] = { name = "HandsSlot",         label = "Hands" },
    [11] = { name = "Finger0Slot",       label = "Finger 1" },
    [12] = { name = "Finger1Slot",       label = "Finger 2" },
    [13] = { name = "Trinket0Slot",      label = "Trinket 1" },
    [14] = { name = "Trinket1Slot",      label = "Trinket 2" },
    [15] = { name = "BackSlot",          label = "Back" },
    [16] = { name = "MainHandSlot",      label = "Main Hand" },
    [17] = { name = "SecondaryHandSlot", label = "Off Hand" },
    [18] = { name = "RangedSlot",        label = "Ranged / Relic" },
    [19] = { name = "TabardSlot",        label = "Tabard" },
}

AS.EMPTY_SLOT_TEXTURES = {}

----------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------
local SCAN_TICK        = 3     -- watchdog tick (session/zone/roster upkeep)
local CHAIN_DELAY      = 0.15  -- delay before the next inspect after one resolves
local RETRY_COOLDOWN   = 15    -- retry delay for out-of-range members
local ROSTER_CHECK     = 10
local INSPECT_TIMEOUT  = 3

-- Forward declaration: OnInspectReady chains straight into the next queue
-- pump instead of waiting for the watchdog tick.
local ScannerTick

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
AS.db = nil
AS.standaloneConflict = false

AS.session = {
    active       = false,
    snapshotKey  = nil,
    captured     = {},
    pending      = {},
    failed       = {},
    inspecting   = false,
    currentUnit  = nil,
    passComplete = false,
    retryClock   = 0,
    rosterClock  = 0,
    totalInRaid  = 0,
    totalCaptured= 0,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function Print(msg)
    WM:ModulePrint("ArmorySnap", msg)
end
AS.Print = Print

local function Verbose(msg)
    if AS.db and AS.db.options and AS.db.options.verbose then
        Print(msg)
    end
end

local function GetTimestamp()
    return date("%Y-%m-%d %H:%M")
end

local function GetGroupSize()
    if GetNumRaidMembers then
        local n = GetNumRaidMembers()
        if n > 0 then return n, "raid" end
    elseif IsInRaid and IsInRaid() then
        return GetNumGroupMembers(), "raid"
    end
    local n = GetNumPartyMembers and GetNumPartyMembers()
             or (GetNumGroupMembers and GetNumGroupMembers() or 0)
    if n > 0 then return n, "party" end
    return 0, "none"
end

----------------------------------------------------------------------
-- Instance / zone detection
----------------------------------------------------------------------
function AS.ShouldAutoScan()
    if not AS.db or AS.standaloneConflict then return false end
    if AS.db.options and AS.db.options.enabled == false then return false end
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "raid" then return true end
    if AS.db.options and AS.db.options.scanGroup then
        local size = GetGroupSize()
        if size > 0 then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Session key
----------------------------------------------------------------------
local function MakeSessionKey()
    local zone = GetRealZoneText() or "Unknown"
    return GetTimestamp() .. " - " .. zone
end

----------------------------------------------------------------------
-- Cache empty-slot textures
----------------------------------------------------------------------
local function CacheEmptyTextures()
    for slotId, info in pairs(AS.SLOT_INFO) do
        local _, tex = GetInventorySlotInfo(info.name)
        AS.EMPTY_SLOT_TEXTURES[slotId] = tex
    end
end

----------------------------------------------------------------------
-- Capture gear for a unit
----------------------------------------------------------------------
local function CaptureGear(unit)
    local gear = {}
    for slotId in pairs(AS.SLOT_INFO) do
        local link = GetInventoryItemLink(unit, slotId)
        local tex  = GetInventoryItemTexture(unit, slotId)
        if link then
            gear[slotId] = { link = link, icon = tex or "" }
        end
    end
    return gear
end

----------------------------------------------------------------------
-- Capture talents — tries every known API variant
----------------------------------------------------------------------
local function SumTalentPoints(tab, isInspect)
    local total = 0
    local rankIdx = nil

    local numTalents = 0
    for _, fn in ipairs({
        function() return GetNumTalents(tab, isInspect) end,
        function() return GetNumTalents(tab, isInspect, false) end,
        function() return GetNumTalents(tab) end,
    }) do
        local ok, n = pcall(fn)
        if ok and n and tonumber(n) and tonumber(n) > 0 then
            numTalents = tonumber(n); break
        end
    end
    if numTalents == 0 then numTalents = 30 end

    for i = 1, numTalents do
        local results
        for _, fn in ipairs({
            function() return { GetTalentInfo(tab, i, isInspect, false, nil) } end,
            function() return { GetTalentInfo(tab, i, isInspect, false) } end,
            function() return { GetTalentInfo(tab, i, isInspect) } end,
        }) do
            local ok, r = pcall(fn)
            if ok and r and #r >= 4 and r[1] ~= nil then
                results = r; break
            end
        end
        if not results then break end

        if rankIdx == nil then
            rankIdx = type(results[1]) == "number" and 6 or 5
        end
        total = total + (tonumber(results[rankIdx]) or 0)
    end
    return total
end

local function CaptureTalents(isInspect)
    local talents = { trees = {}, spec = "", points = "" }
    local maxPts, maxTree = 0, ""
    local ptsStrParts = {}

    local numTabs = 3
    local ok, n = pcall(function() return GetNumTalentTabs(isInspect) end)
    if ok and n and tonumber(n) and tonumber(n) > 0 then numTabs = tonumber(n) end

    for tab = 1, numTabs do
        local tName, tIcon, tPts = "Tree " .. tab, "", 0

        for _, fn in ipairs({
            function() return { GetTalentTabInfo(tab, isInspect) } end,
            function() return { GetTalentTabInfo(tab, isInspect, false) } end,
            function() return { GetTalentTabInfo(tab, isInspect, false, nil) } end,
        }) do
            local fOk, r = pcall(fn)
            if fOk and r and #r >= 3 then
                if type(r[1]) == "number" then
                    tName = tostring(r[2] or tName)
                    tIcon = r[4] or ""
                    tPts  = tonumber(r[5]) or 0
                else
                    tName = tostring(r[1] or tName)
                    tIcon = r[2] or ""
                    tPts  = tonumber(r[3]) or 0
                end
                if tPts > 0 then break end
            end
        end

        if tPts == 0 then
            local summed = SumTalentPoints(tab, isInspect)
            if summed > 0 then tPts = summed end
        end

        table.insert(talents.trees, { name = tName, icon = tIcon, points = tPts })
        table.insert(ptsStrParts, tostring(tPts))
        if tPts > maxPts then maxPts = tPts; maxTree = tName end
    end

    talents.spec   = maxTree
    talents.points = table.concat(ptsStrParts, "/")
    return talents
end

----------------------------------------------------------------------
-- Capture character metadata
----------------------------------------------------------------------
local function CaptureCharInfo(unit)
    local name, realm = UnitName(unit)
    if realm and realm ~= "" then name = name .. "-" .. realm end
    local _, classFile = UnitClass(unit)
    return {
        name    = name or "Unknown",
        class   = classFile or "WARRIOR",
        race    = UnitRace(unit) or "",
        level   = UnitLevel(unit) or 0,
        guild   = GetGuildInfo(unit) or "",
        sex     = UnitSex(unit) or 1,
        gear    = {},
        talents = nil,
    }
end

----------------------------------------------------------------------
-- Parse enchant / gem IDs from item link
----------------------------------------------------------------------
function AS.ParseItemLink(link)
    if not link then return nil end
    local _, _, color, itemStr, name =
        string.find(link, "|c(%x+)|Hitem:(.+)|h%[(.+)%]|h|r")
    if not itemStr then return nil end
    local parts = { strsplit(":", itemStr) }
    return {
        itemId    = tonumber(parts[1]) or 0,
        enchantId = tonumber(parts[2]) or 0,
        gem1      = tonumber(parts[3]) or 0,
        gem2      = tonumber(parts[4]) or 0,
        gem3      = tonumber(parts[5]) or 0,
        name      = name or "",
        color     = color or "ffffffff",
        fullLink  = link,
    }
end

----------------------------------------------------------------------
-- SESSION MANAGEMENT
----------------------------------------------------------------------
local function EnsureSessionSnapshot()
    local s = AS.session
    if s.snapshotKey and AS.db.snapshots[s.snapshotKey] then
        return s.snapshotKey
    end
    local key = MakeSessionKey()
    if not AS.db.snapshots[key] then
        AS.db.snapshots[key] = {
            timestamp = GetTimestamp(),
            zone      = GetRealZoneText() or "Unknown",
            members   = {},
        }
    end
    s.snapshotKey = key
    return key
end

local function BuildPendingQueue()
    local s = AS.session
    s.pending = {}
    s.failed  = {}
    local size, groupType = GetGroupSize()
    s.totalInRaid = size
    local added = {}

    for i = 1, size do
        local unit
        if groupType == "raid" then
            unit = "raid" .. i
        elseif i < size then
            unit = "party" .. i
        else
            unit = "player"
        end
        if unit and UnitExists(unit) then
            local uName = UnitName(unit)
            local realm = select(2, UnitName(unit))
            if realm and realm ~= "" then uName = uName .. "-" .. realm end
            if uName and not s.captured[uName] and not added[uName] then
                table.insert(s.pending, unit)
                added[uName] = true
            end
        end
    end
    if groupType == "party" then
        local pName = UnitName("player")
        if pName and not s.captured[pName] and not added[pName] then
            table.insert(s.pending, "player")
        end
    end
end

local function UpdateCounts()
    local s = AS.session
    local c = 0
    for _ in pairs(s.captured) do c = c + 1 end
    s.totalCaptured = c
end

function AS.ResetSession()
    local s = AS.session
    s.active        = false
    s.snapshotKey   = nil
    s.captured      = {}
    s.pending       = {}
    s.failed        = {}
    s.inspecting    = false
    s.currentUnit   = nil
    s.passComplete  = false
    s.retryClock    = 0
    s.rosterClock   = 0
    s.totalInRaid   = 0
    s.totalCaptured = 0
end

----------------------------------------------------------------------
-- INSPECT HANDLING
----------------------------------------------------------------------
local inspectTimer = nil

local function FinishInspect()
    local s = AS.session
    if inspectTimer then inspectTimer:Cancel(); inspectTimer = nil end
    ClearInspectPlayer()
    s.inspecting  = false
    s.currentUnit = nil
end

local function OnInspectReady(guid)
    local s = AS.session
    if not s.inspecting or not s.currentUnit then return end
    if not s.snapshotKey then FinishInspect(); return end

    local unit = s.currentUnit
    if guid and UnitGUID(unit) ~= guid then return end

    local snap = AS.db.snapshots[s.snapshotKey]
    if not snap then FinishInspect(); return end

    local charInfo    = CaptureCharInfo(unit)
    charInfo.gear     = CaptureGear(unit)
    charInfo.talents  = CaptureTalents(true)

    local totalPts = 0
    if charInfo.talents and charInfo.talents.trees then
        for _, tree in ipairs(charInfo.talents.trees) do
            totalPts = totalPts + (tree.points or 0)
        end
    end

    -- Note: TBC Anniversary API does not return talent point allocations
    -- for inspected targets (confirmed limitation, affects all addons).
    -- Tree names and icons are available; pointsSpent is always 0.
    -- Self-inspection works correctly.

    local charName = charInfo.name
    snap.members[charName] = charInfo
    s.captured[charName]   = true
    UpdateCounts()

    local gc = 0
    for _ in pairs(charInfo.gear) do gc = gc + 1 end
    local specStr = ""
    if totalPts > 0 and charInfo.talents and charInfo.talents.spec ~= "" then
        specStr = "  " .. charInfo.talents.points .. " " .. charInfo.talents.spec
    end
    Verbose("  Scanned |cffffffff" .. charName .. "|r (" .. gc
          .. " items" .. specStr .. ")  [" .. s.totalCaptured .. "/" .. s.totalInRaid .. "]")

    FinishInspect()
    if AS.OnMemberCaptured then AS.OnMemberCaptured() end

    -- Chain: pump the queue as soon as this inspect resolved instead of
    -- waiting up to SCAN_TICK seconds — this is what makes a full 25-man
    -- scan take seconds instead of minutes.
    C_Timer.After(CHAIN_DELAY, function()
        if ScannerTick then ScannerTick() end
    end)
end

local function TryInspectUnit(unit)
    local s = AS.session
    if not UnitExists(unit) or not UnitIsConnected(unit) then return false end

    -- Self
    if UnitIsUnit(unit, "player") then
        EnsureSessionSnapshot()
        local snap = AS.db.snapshots[s.snapshotKey]
        if snap then
            local ci = CaptureCharInfo(unit)
            ci.gear    = CaptureGear(unit)
            ci.talents = CaptureTalents(false)
            snap.members[ci.name] = ci
            s.captured[ci.name]   = true
            UpdateCounts()
            local specStr = ""
            if ci.talents and ci.talents.spec ~= "" then
                specStr = "  " .. ci.talents.points .. " " .. ci.talents.spec
            end
            Verbose("  Scanned |cffffffff" .. ci.name .. "|r (self" .. specStr .. ")  ["
                  .. s.totalCaptured .. "/" .. s.totalInRaid .. "]")
            if AS.OnMemberCaptured then AS.OnMemberCaptured() end
        end
        -- Self-capture needs no inspect — continue the queue immediately
        C_Timer.After(CHAIN_DELAY, function()
            if ScannerTick then ScannerTick() end
        end)
        return true
    end

    if not CheckInteractDistance(unit, 1) then return false end
    if CanInspect and not CanInspect(unit) then return false end

    s.inspecting  = true
    s.currentUnit = unit
    NotifyInspect(unit)

    inspectTimer = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
        if s.inspecting then
            FinishInspect()
            -- Chain after a timeout too — don't let a dead inspect stall
            -- the queue until the next watchdog tick
            C_Timer.After(CHAIN_DELAY, function()
                if ScannerTick then ScannerTick() end
            end)
        end
    end)
    return true
end

----------------------------------------------------------------------
-- PASSIVE SCANNER TICK
----------------------------------------------------------------------
local lastZone = nil

-- Assigns to the forward-declared local above so OnInspectReady's chained
-- calls resolve to this function
function ScannerTick()
    local s = AS.session

    if not AS.ShouldAutoScan() then
        if s.active then
            Verbose("Left scannable area — pausing.")
            s.active = false
        end
        return
    end

    local zone = GetRealZoneText() or ""
    if zone ~= lastZone then
        if lastZone and s.snapshotKey then
            Verbose("Zone changed → starting new scan session.")
        end
        AS.ResetSession()
        lastZone = zone
    end

    if not s.active then
        s.active = true
        EnsureSessionSnapshot()
        BuildPendingQueue()
        if #s.pending > 0 then
            Verbose("Auto-scan started in |cfffff000" .. zone
                  .. "|r  (" .. #s.pending .. " members)")
        end
    end

    if s.inspecting then return end

    if s.passComplete then
        s.rosterClock = s.rosterClock - SCAN_TICK
        if s.rosterClock <= 0 then
            s.rosterClock = ROSTER_CHECK
            BuildPendingQueue()
            if #s.pending > 0 then
                s.passComplete = false
                Verbose("Roster change detected — scanning "
                      .. #s.pending .. " new/remaining members.")
            end
        end
        if #s.failed > 0 then
            s.retryClock = s.retryClock - SCAN_TICK
            if s.retryClock <= 0 then
                s.pending      = s.failed
                s.failed       = {}
                s.passComplete = false
                Verbose("Retrying " .. #s.pending
                      .. " members that were out of range …")
            end
        end
        return
    end

    while #s.pending > 0 do
        local unit = table.remove(s.pending, 1)
        if UnitExists(unit) then
            local uName = UnitName(unit)
            local realm = select(2, UnitName(unit))
            if realm and realm ~= "" then uName = uName .. "-" .. realm end
            if uName and not s.captured[uName] then
                EnsureSessionSnapshot()
                if TryInspectUnit(unit) then return end
                table.insert(s.failed, unit)
            end
        end
    end

    s.passComplete = true
    UpdateCounts()
    if #s.failed > 0 then
        s.retryClock = RETRY_COOLDOWN
        Verbose("Pass done. |cffffffff" .. s.totalCaptured .. "/"
              .. s.totalInRaid .. "|r captured.  Retrying "
              .. #s.failed .. " in " .. RETRY_COOLDOWN .. "s.")
    else
        s.rosterClock = ROSTER_CHECK
        if s.totalCaptured > 0 then
            Verbose("All |cff00ff00" .. s.totalCaptured
                  .. "|r raid members captured!")
        end
    end
end

----------------------------------------------------------------------
-- Manual snapshot
----------------------------------------------------------------------
function AS.TakeManualSnapshot(label)
    local size, groupType = GetGroupSize()
    if size == 0 then Print("You are not in a group."); return end

    local zone = label or GetRealZoneText() or "Unknown"
    local key  = GetTimestamp() .. " - " .. zone
    AS.db.snapshots[key] = {
        timestamp = GetTimestamp(),
        zone      = zone,
        members   = {},
    }
    local snap = AS.db.snapshots[key]

    local queue = {}
    for i = 1, size do
        local unit = (groupType == "raid") and ("raid" .. i)
                     or (i < size and ("party" .. i) or "player")
        if UnitExists(unit) then table.insert(queue, unit) end
    end

    Verbose("Manual snapshot: |cfffff000" .. key .. "|r  (" .. #queue .. " members)")

    local captured, idx = 0, 0
    local function DoNext()
        idx = idx + 1
        if idx > #queue then
            Verbose("Manual snapshot done — " .. captured .. "/" .. #queue .. " captured.")
            if AS.RefreshSnapshotList then AS.RefreshSnapshotList() end
            return
        end
        local unit = queue[idx]
        if UnitIsUnit(unit, "player") then
            local ci = CaptureCharInfo(unit)
            ci.gear    = CaptureGear(unit)
            ci.talents = CaptureTalents(false)
            snap.members[ci.name] = ci; captured = captured + 1
            DoNext()
        elseif UnitExists(unit) and CheckInteractDistance(unit, 1) then
            local waiting, timer = true, nil
            local handler = CreateFrame("Frame")
            handler:RegisterEvent("INSPECT_READY")
            handler:SetScript("OnEvent", function(self, _, guid)
                if not waiting then return end
                if guid and UnitGUID(unit) ~= guid then return end
                waiting = false; self:UnregisterAllEvents()
                if timer then timer:Cancel() end
                local ci = CaptureCharInfo(unit)
                ci.gear    = CaptureGear(unit)
                ci.talents = CaptureTalents(true)
                snap.members[ci.name] = ci; captured = captured + 1
                ClearInspectPlayer()
                C_Timer.After(CHAIN_DELAY, DoNext)
            end)
            NotifyInspect(unit)
            timer = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
                if waiting then
                    waiting = false; handler:UnregisterAllEvents()
                    ClearInspectPlayer(); C_Timer.After(0.2, DoNext)
                end
            end)
        else
            DoNext()
        end
    end
    DoNext()
end

----------------------------------------------------------------------
-- Snapshot helpers
----------------------------------------------------------------------
function AS.GetSnapshotKeys()
    local keys = {}
    for k in pairs(AS.db.snapshots) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return a > b end)
    return keys
end

function AS.GetMemberNames(snapshotKey)
    local snap = AS.db.snapshots[snapshotKey]
    if not snap then return {} end
    local names = {}
    for name in pairs(snap.members) do table.insert(names, name) end
    table.sort(names)
    return names
end

function AS.DeleteSnapshot(key)
    if AS.db.snapshots[key] then
        AS.db.snapshots[key] = nil
        Print("Deleted snapshot: " .. key)
        if AS.RefreshSnapshotList then AS.RefreshSnapshotList() end
    else
        Print("Snapshot not found: " .. key)
    end
end

----------------------------------------------------------------------
-- Snapshot retention — purge snapshots older than configured days
----------------------------------------------------------------------
function AS.PurgeOldSnapshots()
    if not AS.db or not AS.db.snapshots then return end
    local retDays = AS.db.options and AS.db.options.retentionDays or 30
    local now = time()
    local cutoff = now - (retDays * 86400)
    local purged = 0

    for key, snap in pairs(AS.db.snapshots) do
        local y, m, d, H, M = key:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)")
        if y then
            local snapTime = time({
                year = tonumber(y), month = tonumber(m), day = tonumber(d),
                hour = tonumber(H), min = tonumber(M), sec = 0,
            })
            if snapTime < cutoff then
                AS.db.snapshots[key] = nil
                purged = purged + 1
            end
        end
    end

    if purged > 0 then
        Print("Purged " .. purged .. " snapshot"
              .. (purged ~= 1 and "s" or "") .. " older than "
              .. retDays .. " days.")
    end
end

----------------------------------------------------------------------
-- INITIALIZATION + EVENTS (module lifecycle instead of ADDON_LOADED)
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function IsStandaloneLoaded()
    if IsAddOnLoaded then
        return IsAddOnLoaded("ArmorySnap")
    elseif C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("ArmorySnap")
    end
    return false
end

function AS:Initialize()
    -- SavedVariables: reuse the standalone addon's DB so existing archives
    -- carry straight over
    if not ArmorySnapDB then
        ArmorySnapDB = { snapshots = {}, options = {} }
    end
    AS.db = ArmorySnapDB
    if not AS.db.snapshots then AS.db.snapshots = {} end
    if not AS.db.options   then AS.db.options   = {} end
    if AS.db.options.enabled       == nil then AS.db.options.enabled       = true end
    if AS.db.options.scanGroup     == nil then AS.db.options.scanGroup     = false end
    if AS.db.options.verbose       == nil then AS.db.options.verbose       = false end
    if AS.db.options.retentionDays == nil then AS.db.options.retentionDays = 30 end
    -- First run inside Watching Machine: inherit the global theme choice
    if AS.db.options.elvuiTheme == nil then
        AS.db.options.elvuiTheme = (WM:GetThemeName() == "ElvUI")
    end

    -- If the standalone ArmorySnap addon is running, stand down completely:
    -- two scanners would fight over the one-at-a-time inspect slot
    if IsStandaloneLoaded() then
        AS.standaloneConflict = true
        Print("|cFFFF4444Standalone ArmorySnap addon detected|r — module disabled. "
            .. "Disable the standalone addon to use the integrated version.")
        return
    end

    CacheEmptyTextures()
    AS.PurgeOldSnapshots()

    eventFrame:RegisterEvent("INSPECT_READY")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

    C_Timer.NewTicker(SCAN_TICK, ScannerTick)
    C_Timer.NewTicker(2, function()
        if AS.UpdateScanStatus then AS.UpdateScanStatus() end
    end)

    -- Keep the standalone slash commands working
    SLASH_WMARMORYSNAP1 = "/as"
    SLASH_WMARMORYSNAP2 = "/armorysnap"
    SlashCmdList["WMARMORYSNAP"] = AS.HandleSlash
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "INSPECT_READY" then
        OnInspectReady(arg1)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(2, ScannerTick)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if AS.session.passComplete then
            AS.session.rosterClock = 0
        end
    end
end)

----------------------------------------------------------------------
-- STATUS (dashboard card)
----------------------------------------------------------------------
function AS:GetQuickStatus()
    if AS.standaloneConflict then
        return "|cFFFF4444Standalone addon conflict|r"
    end
    if not AS.db then return "|cFF888888Not initialized|r" end
    if AS.db.options.enabled == false then return "|cFFFF0000Disabled|r" end

    local snapCount = 0
    for _ in pairs(AS.db.snapshots) do snapCount = snapCount + 1 end

    local s = AS.session
    if s.active then
        return "|cFF00FF00Scanning|r " .. s.totalCaptured .. "/" .. s.totalInRaid
            .. " (" .. snapCount .. " snapshots)"
    end
    return "|cFF00FF00Active|r (" .. snapCount .. " snapshots stored)"
end

----------------------------------------------------------------------
-- SLASH COMMANDS
----------------------------------------------------------------------
function AS.HandleSlash(msg)
    local cmd, rest = strsplit(" ", msg or "", 2)
    cmd = strlower(strtrim(cmd or ""))

    if cmd == "snap" or cmd == "snapshot" then
        local label = rest and strtrim(rest)
        if label == "" then label = nil end
        AS.TakeManualSnapshot(label)

    elseif cmd == "browse" or cmd == "view" or cmd == "open" or cmd == "" then
        AS.ToggleBrowseFrame()

    elseif cmd == "list" then
        local keys = AS.GetSnapshotKeys()
        if #keys == 0 then
            Print("No snapshots stored.")
        else
            Print("Stored snapshots:")
            for i, k in ipairs(keys) do
                local snap = AS.db.snapshots[k]
                local count = 0
                for _ in pairs(snap.members) do count = count + 1 end
                Print("  " .. i .. ". |cfffff000" .. k
                      .. "|r (" .. count .. " members)")
            end
        end

    elseif cmd == "delete" or cmd == "del" then
        if rest and rest ~= "" then
            AS.DeleteSnapshot(strtrim(rest))
        else Print("Usage: /as delete <snapshot name>") end

    elseif cmd == "group" then
        AS.db.options.scanGroup = not AS.db.options.scanGroup
        Print("Group scanning " .. (AS.db.options.scanGroup
              and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"))
        if AS.UpdateGroupCheckbox then AS.UpdateGroupCheckbox() end

    elseif cmd == "elvui" or cmd == "theme" then
        AS.db.options.elvuiTheme = not AS.db.options.elvuiTheme
        Print("ElvUI theme " .. (AS.db.options.elvuiTheme
              and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"))
        if AS.ApplyTheme then AS.ApplyTheme() end

    elseif cmd == "verbose" or cmd == "chat" then
        AS.db.options.verbose = not AS.db.options.verbose
        Print("Chat output " .. (AS.db.options.verbose
              and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"))
        if AS.UpdateVerboseCheckbox then AS.UpdateVerboseCheckbox() end

    elseif cmd == "status" then
        local s = AS.session
        if s.active then
            Print("Scanning: |cffffffff" .. s.totalCaptured .. "/"
                  .. s.totalInRaid .. "|r captured.")
            Print("Session: |cfffff000" .. (s.snapshotKey or "none") .. "|r")
        else
            Print("Scanner idle.")
        end
        Print("Group scan: " .. (AS.db.options.scanGroup
              and "|cff00ff00ON|r" or "|cffff4444OFF|r"))

    elseif cmd == "reset" then
        AS.ResetSession()
        lastZone = nil
        Print("Session reset.")

    else
        Print("Commands:")
        Print("  |cfffff000/as|r               – Open gear browser")
        Print("  |cfffff000/as snap [label]|r   – Manual snapshot")
        Print("  |cfffff000/as list|r            – List saved snapshots")
        Print("  |cfffff000/as delete <n>|r   – Delete a snapshot")
        Print("  |cfffff000/as group|r           – Toggle group scanning")
        Print("  |cfffff000/as theme|r           – Toggle ElvUI theme")
        Print("  |cfffff000/as verbose|r         – Toggle chat output")
        Print("  |cfffff000/as status|r          – Show scanner status")
        Print("  |cfffff000/as reset|r           – Reset current session")
    end
end

----------------------------------------------------------------------
-- ====================  UI (browse frame)  =========================
----------------------------------------------------------------------
local SLOT_SIZE     = 36
local SLOT_SPACING  = 3
local ICON_BORDER   = 2

local LEFT_SLOTS    = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS   = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOT_SLOTS     = { 16, 17, 18 }

local LIST_WIDTH    = 180
local DOLL_WIDTH    = 330
local FRAME_WIDTH   = LIST_WIDTH + DOLL_WIDTH + 30
local DOLL_COL_H    = #LEFT_SLOTS * (SLOT_SIZE + SLOT_SPACING)
local DOLL_H        = DOLL_COL_H + SLOT_SIZE + 16
local TALENT_H      = 52
local FRAME_HEIGHT  = math.max(590, 28 + 18 + 26 + 24 + 28 + 22 + 30 + DOLL_H + TALENT_H + 40)

local CLASS_COLORS = RAID_CLASS_COLORS or {}

local QUALITY_COLORS = {
    [0] = { r=0.62, g=0.62, b=0.62 },
    [1] = { r=1.00, g=1.00, b=1.00 },
    [2] = { r=0.12, g=1.00, b=0.00 },
    [3] = { r=0.00, g=0.44, b=0.87 },
    [4] = { r=0.64, g=0.21, b=0.93 },
    [5] = { r=1.00, g=0.50, b=0.00 },
}

local ELVUI = {
    bgMain     = { 0.07, 0.07, 0.07, 0.92 },
    bgPanel    = { 0.05, 0.05, 0.05, 0.85 },
    border     = { 0.15, 0.15, 0.15, 1 },
    statusBg   = { 0.08, 0.08, 0.08, 0.8 },
    statusBar  = { 0.00, 0.44, 0.87, 0.85 },
    statusDone = { 0.18, 0.70, 0.18, 0.85 },
    text       = { 0.84, 0.84, 0.84 },
    slotBg     = { 0.10, 0.10, 0.10, 0.7 },
    listHover  = { 1, 1, 1, 0.06 },
    listSelect = { 0.00, 0.44, 0.87, 0.18 },
}

local browseFrame
local memberButtons   = {}
local slotButtons     = {}
local charNameText, charDetailText, charGuildText, summaryLabel
local talentFrame, talentIcons, talentTexts, talentSpecText
local snapshotDropdown
local memberScrollChild
local scanStatusBar, scanStatusText, scanStatusPct, scanStatusBg
local groupCheckbox, themeCheckbox, verboseCheckbox
local dollFrame, dollBg

local selectedSnapshotKey = nil
local selectedMemberName  = nil

local function GetQualityFromLink(link)
    if not link then return 1 end
    local _, _, q = GetItemInfo(link)
    if q then return q end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if hex then
        if hex == "ff9d9d9d" then return 0 end
        if hex == "ffffffff" then return 1 end
        if hex == "ff1eff00" then return 2 end
        if hex == "ff0070dd" then return 3 end
        if hex == "ffa335ee" then return 4 end
        if hex == "ffff8000" then return 5 end
    end
    return 1
end

local function MakePixelBorder(frame, r, g, b, a, size)
    size = size or 1
    if frame._pxBorders then
        for _, t in ipairs(frame._pxBorders) do
            t:SetColorTexture(r, g, b, a)
            t:Show()
        end
        return
    end
    frame._pxBorders = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        if i == 1 then
            t:SetPoint("TOPLEFT", -size, size)
            t:SetPoint("BOTTOMLEFT", -size, -size)
            t:SetWidth(size)
        elseif i == 2 then
            t:SetPoint("TOPRIGHT", size, size)
            t:SetPoint("BOTTOMRIGHT", size, -size)
            t:SetWidth(size)
        elseif i == 3 then
            t:SetPoint("TOPLEFT", -size, size)
            t:SetPoint("TOPRIGHT", size, size)
            t:SetHeight(size)
        else
            t:SetPoint("BOTTOMLEFT", -size, -size)
            t:SetPoint("BOTTOMRIGHT", size, -size)
            t:SetHeight(size)
        end
        table.insert(frame._pxBorders, t)
    end
end

local function CreateSlotButton(parent, slotId)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(AS.EMPTY_SLOT_TEXTURES[slotId]
                  or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest")
    btn.bgTex = bg

    local elvBg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    elvBg:SetAllPoints()
    elvBg:SetColorTexture(unpack(ELVUI.slotBg))
    elvBg:Hide()
    btn.elvBg = elvBg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", ICON_BORDER, -ICON_BORDER)
    icon:SetPoint("BOTTOMRIGHT", -ICON_BORDER, ICON_BORDER)
    icon:Hide()
    btn.iconTex = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAlpha(0.8)
    border:Hide()
    btn.borderTex = border

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    btn.hlTex = hl

    btn.slotId    = slotId
    btn.slotLabel = AS.SLOT_INFO[slotId] and AS.SLOT_INFO[slotId].label or "Slot"
    btn.itemLink  = nil

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
        else
            GameTooltip:AddLine(self.slotLabel, 0.5, 0.5, 0.5)
            GameTooltip:AddLine("Empty", 0.4, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        if IsShiftKeyDown() and self.itemLink and ChatEdit_GetActiveWindow() then
            ChatEdit_InsertLink(self.itemLink)
        end
    end)

    return btn
end

local function SetSlotItem(btn, gearData)
    if gearData and gearData.link then
        btn.itemLink = gearData.link
        btn.iconTex:SetTexture(gearData.icon
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.iconTex:Show()
        btn.bgTex:Hide()
        local q  = GetQualityFromLink(gearData.link)
        local qc = QUALITY_COLORS[q]
        if qc and q >= 2 then
            btn.borderTex:SetVertexColor(qc.r, qc.g, qc.b)
            btn.borderTex:Show()
        else
            btn.borderTex:Hide()
        end
    else
        btn.itemLink = nil
        btn.iconTex:Hide()
        local isElv = AS.db and AS.db.options and AS.db.options.elvuiTheme
        btn.bgTex:SetShown(not isElv)
        btn.borderTex:Hide()
    end
end

function AS.ApplyTheme()
    if not browseFrame then return end
    local elv = AS.db and AS.db.options and AS.db.options.elvuiTheme

    if elv then
        if browseFrame.SetBackdrop then
            browseFrame:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            browseFrame:SetBackdropColor(unpack(ELVUI.bgMain))
            browseFrame:SetBackdropBorderColor(unpack(ELVUI.border))
        end
        if browseFrame.TitleBg        then browseFrame.TitleBg:Hide() end
        if browseFrame.TopTileStreaky then browseFrame.TopTileStreaky:Hide() end
        if browseFrame.Bg             then browseFrame.Bg:Hide() end
        if browseFrame.InsetBg        then browseFrame.InsetBg:Hide() end
        for _, region in pairs({browseFrame:GetRegions()}) do
            if region.GetDrawLayer and region:GetDrawLayer() == "BORDER" then
                region:SetAlpha(0)
            end
        end
        local inset = browseFrame.Inset
        if inset then
            for _, region in pairs({inset:GetRegions()}) do
                region:SetAlpha(0)
            end
        end
        browseFrame.TitleText:SetTextColor(unpack(ELVUI.text))

        if scanStatusBg then scanStatusBg:SetColorTexture(unpack(ELVUI.statusBg)) end
        if scanStatusBar then
            scanStatusBar:SetStatusBarColor(unpack(ELVUI.statusBar))
            MakePixelBorder(scanStatusBar, unpack(ELVUI.border))
        end
        if dollBg then dollBg:SetColorTexture(unpack(ELVUI.bgPanel)) end
        for _, btn in pairs(slotButtons) do
            btn.elvBg:Show()
            btn.bgTex:Hide()
            MakePixelBorder(btn, unpack(ELVUI.border))
            btn.hlTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            btn.hlTex:SetAlpha(0.08)
        end
        if talentFrame then
            talentFrame.bg:SetColorTexture(unpack(ELVUI.bgPanel))
            MakePixelBorder(talentFrame, unpack(ELVUI.border))
        end
    else
        if browseFrame.SetBackdrop then
            browseFrame:SetBackdrop(nil)
        end
        if browseFrame.TitleBg        then browseFrame.TitleBg:Show() end
        if browseFrame.TopTileStreaky then browseFrame.TopTileStreaky:Show() end
        if browseFrame.Bg             then browseFrame.Bg:Show() end
        if browseFrame.InsetBg        then browseFrame.InsetBg:Show() end
        for _, region in pairs({browseFrame:GetRegions()}) do
            if region.GetDrawLayer and region:GetDrawLayer() == "BORDER" then
                region:SetAlpha(1)
            end
        end
        local inset = browseFrame.Inset
        if inset then
            for _, region in pairs({inset:GetRegions()}) do
                region:SetAlpha(1)
            end
        end
        browseFrame.TitleText:SetTextColor(1, 0.82, 0)

        if scanStatusBg then scanStatusBg:SetColorTexture(0.1, 0.1, 0.1, 0.6) end
        if scanStatusBar then
            scanStatusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
            if scanStatusBar._pxBorders then
                for _, t in ipairs(scanStatusBar._pxBorders) do t:Hide() end
            end
        end
        if dollBg then dollBg:SetColorTexture(0, 0, 0, 0.15) end
        for _, btn in pairs(slotButtons) do
            btn.elvBg:Hide()
            if not btn.itemLink then btn.bgTex:Show() end
            if btn._pxBorders then
                for _, t in ipairs(btn._pxBorders) do t:Hide() end
            end
            btn.hlTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            btn.hlTex:SetAlpha(1)
        end
        if talentFrame then
            talentFrame.bg:SetColorTexture(0, 0, 0, 0.2)
            if talentFrame._pxBorders then
                for _, t in ipairs(talentFrame._pxBorders) do t:Hide() end
            end
        end
    end

    if themeCheckbox then
        themeCheckbox:SetChecked(elv and true or false)
    end
end

local function CreateBrowseFrame()
    if browseFrame then return end

    local f = CreateFrame("Frame", "WM_ArmorySnapFrame", UIParent,
                          "BasicFrameTemplateWithInset, BackdropTemplate")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "WM_ArmorySnapFrame")
    f.TitleText:SetText("ArmorySnap")

    -- Scan status bar
    local statusBar = CreateFrame("StatusBar", nil, f)
    statusBar:SetPoint("TOPLEFT", 10, -28)
    statusBar:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    statusBar:SetHeight(18)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:SetStatusBarColor(0.26, 0.8, 0.26, 0.7)
    scanStatusBar = statusBar

    local sBg = statusBar:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints()
    sBg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
    scanStatusBg = sBg

    scanStatusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanStatusText:SetPoint("LEFT", 6, 0)
    scanStatusText:SetText("Scanner idle")

    scanStatusPct = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanStatusPct:SetPoint("RIGHT", -6, 0)

    -- Checkbox row (group + theme + verbose)
    local cbRow = CreateFrame("Frame", nil, f)
    cbRow:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", -2, -1)
    cbRow:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    cbRow:SetHeight(24)

    local gcb = CreateFrame("CheckButton", "WM_ASGroupCB", cbRow, "UICheckButtonTemplate")
    gcb:SetPoint("LEFT", 0, 0)
    gcb:SetSize(22, 22)
    gcb.text = _G[gcb:GetName() .. "Text"] or gcb.Text
    if gcb.text then
        gcb.text:SetText("Scan in group")
        gcb.text:SetFontObject("GameFontNormalSmall")
    end
    gcb:SetChecked(AS.db and AS.db.options and AS.db.options.scanGroup or false)
    gcb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.scanGroup = self:GetChecked() and true or false
        end
    end)
    groupCheckbox = gcb

    local tcb = CreateFrame("CheckButton", "WM_ASThemeCB", cbRow, "UICheckButtonTemplate")
    tcb:SetPoint("LEFT", gcb, "RIGHT", 110, 0)
    tcb:SetSize(22, 22)
    tcb.text = _G[tcb:GetName() .. "Text"] or tcb.Text
    if tcb.text then
        tcb.text:SetText("ElvUI Theme")
        tcb.text:SetFontObject("GameFontNormalSmall")
    end
    tcb:SetChecked(AS.db and AS.db.options and AS.db.options.elvuiTheme or false)
    tcb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.elvuiTheme = self:GetChecked() and true or false
            AS.ApplyTheme()
        end
    end)
    themeCheckbox = tcb

    local vcb = CreateFrame("CheckButton", "WM_ASVerboseCB", cbRow, "UICheckButtonTemplate")
    vcb:SetPoint("LEFT", tcb, "RIGHT", 80, 0)
    vcb:SetSize(22, 22)
    vcb.text = _G[vcb:GetName() .. "Text"] or vcb.Text
    if vcb.text then
        vcb.text:SetText("Chat Log")
        vcb.text:SetFontObject("GameFontNormalSmall")
    end
    vcb:SetChecked(AS.db and AS.db.options and AS.db.options.verbose or false)
    vcb:SetScript("OnClick", function(self)
        if AS.db and AS.db.options then
            AS.db.options.verbose = self:GetChecked() and true or false
        end
    end)
    verboseCheckbox = vcb

    -- Retention row
    local retRow = CreateFrame("Frame", nil, f)
    retRow:SetPoint("TOPLEFT", cbRow, "BOTTOMLEFT", 0, 0)
    retRow:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    retRow:SetHeight(26)

    local retLabel = retRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    retLabel:SetPoint("LEFT", 4, 0)
    retLabel:SetText("Keep snapshots:")

    local retDD = CreateFrame("Frame", "WM_ASRetentionDD", retRow, "UIDropDownMenuTemplate")
    retDD:SetPoint("LEFT", retLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(retDD, 80)

    local retOptions = {
        { text = "1 day",   value = 1 },
        { text = "7 days",  value = 7 },
        { text = "14 days", value = 14 },
        { text = "30 days", value = 30 },
    }

    UIDropDownMenu_Initialize(retDD, function(self, level)
        local current = AS.db and AS.db.options and AS.db.options.retentionDays or 30
        for _, opt in ipairs(retOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = opt.text
            info.value   = opt.value
            info.checked = (opt.value == current)
            info.func = function(self)
                if AS.db and AS.db.options then
                    AS.db.options.retentionDays = self.value
                end
                UIDropDownMenu_SetText(retDD, opt.text)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local initDays = AS.db and AS.db.options and AS.db.options.retentionDays or 30
    for _, opt in ipairs(retOptions) do
        if opt.value == initDays then
            UIDropDownMenu_SetText(retDD, opt.text)
            break
        end
    end

    -- Left panel: snapshot dropdown + member list
    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT", retRow, "BOTTOMLEFT", 2, -2)
    leftPanel:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    leftPanel:SetWidth(LIST_WIDTH)

    local snapLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapLabel:SetPoint("TOPLEFT", 0, 0)
    snapLabel:SetText("Snapshot:")

    local dd = CreateFrame("Frame", "WM_ASSnapDD", leftPanel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", snapLabel, "BOTTOMLEFT", -16, -2)
    snapshotDropdown = dd
    UIDropDownMenu_SetWidth(dd, LIST_WIDTH - 30)

    local function DDInit(self, level)
        local keys = AS.GetSnapshotKeys()
        for _, key in ipairs(keys) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = key
            info.value    = key
            info.checked  = (key == selectedSnapshotKey)
            info.func = function(self)
                selectedSnapshotKey = self.value
                selectedMemberName  = nil
                UIDropDownMenu_SetText(dd, self.value)
                CloseDropDownMenus()
                AS.RefreshMemberList()
                AS.ClearPaperDoll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
        if #keys == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "(No snapshots)"
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(dd, DDInit)
    UIDropDownMenu_SetText(dd, "Select snapshot …")

    local mLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mLabel:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 16, -6)
    mLabel:SetText("Raid Members:")

    local sf = CreateFrame("ScrollFrame", "WM_ASMemberScroll", leftPanel,
                           "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", mLabel, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -22, 4)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(LIST_WIDTH - 28, 1)
    sf:SetScrollChild(child)
    memberScrollChild = child

    -- Right panel: char info + paper doll + talents + summary
    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    rightPanel:SetWidth(DOLL_WIDTH)

    charNameText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    charNameText:SetPoint("TOP", 0, -4)

    charDetailText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charDetailText:SetPoint("TOP", charNameText, "BOTTOM", 0, -2)

    charGuildText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charGuildText:SetPoint("TOP", charDetailText, "BOTTOM", 0, -1)
    charGuildText:SetTextColor(0.25, 1.0, 0.25)

    dollFrame = CreateFrame("Frame", nil, rightPanel)
    dollFrame:SetPoint("TOP", charGuildText, "BOTTOM", 0, -8)
    dollFrame:SetSize(DOLL_WIDTH, DOLL_H)

    dollBg = dollFrame:CreateTexture(nil, "BACKGROUND")
    dollBg:SetAllPoints()
    dollBg:SetColorTexture(0, 0, 0, 0.15)

    for i, sid in ipairs(LEFT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", 6, -((i - 1) * (SLOT_SIZE + SLOT_SPACING) + 4))
        slotButtons[sid] = btn
    end

    local rx = DOLL_WIDTH - SLOT_SIZE - 6
    for i, sid in ipairs(RIGHT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", rx, -((i - 1) * (SLOT_SIZE + SLOT_SPACING) + 4))
        slotButtons[sid] = btn
    end

    local bw = #BOT_SLOTS * SLOT_SIZE + (#BOT_SLOTS - 1) * SLOT_SPACING
    local bx = (DOLL_WIDTH - bw) / 2
    local by = -(DOLL_COL_H + 10)
    for i, sid in ipairs(BOT_SLOTS) do
        local btn = CreateSlotButton(dollFrame, sid)
        btn:SetPoint("TOPLEFT", dollFrame, "TOPLEFT",
                     bx + (i - 1) * (SLOT_SIZE + SLOT_SPACING), by)
        slotButtons[sid] = btn
    end

    local sil = dollFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    sil:SetPoint("CENTER", 0, 10)
    sil:SetText("[ Character ]")
    sil:SetAlpha(0.15)

    -- Talent bar
    talentFrame = CreateFrame("Frame", nil, rightPanel)
    talentFrame:SetPoint("TOP", dollFrame, "BOTTOM", 0, -6)
    talentFrame:SetSize(DOLL_WIDTH, TALENT_H)

    local tBg = talentFrame:CreateTexture(nil, "BACKGROUND")
    tBg:SetAllPoints()
    tBg:SetColorTexture(0, 0, 0, 0.2)
    talentFrame.bg = tBg

    talentSpecText = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    talentSpecText:SetPoint("TOP", 0, -4)

    talentIcons = {}
    talentTexts = {}
    local iconSize = 22
    local colWidth = math.floor(DOLL_WIDTH / 3)

    for t = 1, 3 do
        local colX = (t - 1) * colWidth

        local ic = talentFrame:CreateTexture(nil, "ARTWORK")
        ic:SetSize(iconSize, iconSize)
        ic:SetPoint("TOPLEFT", talentFrame, "TOPLEFT", colX + 8, -22)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic:Hide()
        talentIcons[t] = ic

        local tx = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tx:SetPoint("LEFT", ic, "RIGHT", 4, 0)
        tx:SetWidth(colWidth - iconSize - 16)
        tx:SetJustifyH("LEFT")
        tx:SetText("")
        talentTexts[t] = tx
    end

    summaryLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryLabel:SetPoint("TOP", talentFrame, "BOTTOM", 0, -6)
    summaryLabel:SetWidth(DOLL_WIDTH - 8)
    summaryLabel:SetJustifyH("CENTER")

    browseFrame = f
    f:Hide()
end

function AS.UpdateScanStatus()
    if not browseFrame or not browseFrame:IsShown() then return end
    local s   = AS.session
    local elv = AS.db and AS.db.options and AS.db.options.elvuiTheme
    if s.active then
        local total = math.max(s.totalInRaid, 1)
        local pct   = s.totalCaptured / total
        scanStatusBar:SetValue(pct)
        scanStatusText:SetText("Scanning: " .. (s.snapshotKey or ""))
        scanStatusPct:SetText(s.totalCaptured .. " / " .. s.totalInRaid)
        if pct >= 1 then
            scanStatusBar:SetStatusBarColor(unpack(elv and ELVUI.statusDone
                or { 0.26, 0.8, 0.26, 0.7 }))
        else
            scanStatusBar:SetStatusBarColor(unpack(elv and ELVUI.statusBar
                or { 0.9, 0.7, 0.0, 0.7 }))
        end
    else
        scanStatusBar:SetValue(0)
        scanStatusText:SetText("Scanner idle")
        scanStatusPct:SetText("")
        scanStatusBar:SetStatusBarColor(0.4, 0.4, 0.4, 0.5)
    end
end

function AS.RefreshMemberList()
    for _, btn in ipairs(memberButtons) do btn:Hide() end

    if not selectedSnapshotKey then return end
    local names = AS.GetMemberNames(selectedSnapshotKey)
    local snap  = AS.db.snapshots[selectedSnapshotKey]
    if not snap then return end

    local elv = AS.db and AS.db.options and AS.db.options.elvuiTheme
    local yOff, btnH = 0, 18
    for i, name in ipairs(names) do
        local member = snap.members[name]

        -- Pooled rows (frames are never garbage-collected)
        local btn = memberButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, memberScrollChild)
            btn:SetSize(LIST_WIDTH - 30, btnH)

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            btn.hlTex = hl

            local sel = btn:CreateTexture(nil, "BACKGROUND")
            sel:SetAllPoints()
            sel:Hide()
            btn.selTex = sel

            btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.nameText:SetPoint("LEFT", 4, 0)

            btn.rightText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.rightText:SetPoint("RIGHT", -4, 0)

            btn:SetScript("OnClick", function(self)
                selectedMemberName = self.memberName
                AS.RefreshPaperDoll()
                for _, b in ipairs(memberButtons) do
                    if b.selTex then
                        b.selTex[b.memberName == selectedMemberName
                                 and "Show" or "Hide"](b.selTex)
                    end
                end
            end)

            memberButtons[i] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 0, -yOff)

        if elv then
            btn.hlTex:SetColorTexture(unpack(ELVUI.listHover))
            btn.selTex:SetColorTexture(unpack(ELVUI.listSelect))
        else
            btn.hlTex:SetColorTexture(1, 1, 1, 0.1)
            btn.selTex:SetColorTexture(1, 1, 1, 0.15)
        end

        local cc = CLASS_COLORS[member.class] or { r=1, g=1, b=1 }
        btn.nameText:SetText(name)
        btn.nameText:SetTextColor(cc.r, cc.g, cc.b)

        local rightLabel
        if member.talents and member.talents.points ~= ""
           and member.talents.points ~= "0/0/0" then
            rightLabel = member.talents.points
        else
            local gc = 0
            for _ in pairs(member.gear) do gc = gc + 1 end
            rightLabel = gc .. " items"
        end
        btn.rightText:SetText(rightLabel)

        btn.memberName = name
        btn.selTex:SetShown(name == selectedMemberName)
        btn:Show()

        yOff = yOff + btnH + 1
    end
    memberScrollChild:SetHeight(math.max(1, yOff))
end

function AS.ClearPaperDoll()
    charNameText:SetText("")
    charDetailText:SetText("")
    charGuildText:SetText("")
    if summaryLabel   then summaryLabel:SetText("") end
    if talentSpecText then talentSpecText:SetText("") end
    for t = 1, 3 do
        if talentIcons[t] then talentIcons[t]:Hide() end
        if talentTexts[t] then talentTexts[t]:SetText("") end
    end
    for _, btn in pairs(slotButtons) do SetSlotItem(btn, nil) end
end

function AS.RefreshPaperDoll()
    AS.ClearPaperDoll()
    if not selectedSnapshotKey or not selectedMemberName then return end
    local snap = AS.db.snapshots[selectedSnapshotKey]
    if not snap then return end
    local member = snap.members[selectedMemberName]
    if not member then return end

    local cc = CLASS_COLORS[member.class] or { r=1, g=1, b=1 }
    charNameText:SetText(member.name)
    charNameText:SetTextColor(cc.r, cc.g, cc.b)
    charDetailText:SetText("Level " .. (member.level or "?") .. " "
                           .. (member.race or "") .. " "
                           .. (member.class or ""))
    charGuildText:SetText(member.guild ~= ""
                          and ("<" .. member.guild .. ">") or "")

    local enchants, gems, items = 0, 0, 0
    for sid, btn in pairs(slotButtons) do
        local gd = member.gear[sid]
        SetSlotItem(btn, gd)
        if gd and gd.link then
            items = items + 1
            local p = AS.ParseItemLink(gd.link)
            if p then
                if p.enchantId > 0 then enchants = enchants + 1 end
                if p.gem1      > 0 then gems = gems + 1 end
                if p.gem2      > 0 then gems = gems + 1 end
                if p.gem3      > 0 then gems = gems + 1 end
            end
        end
    end

    local tal = member.talents
    if tal and tal.trees and #tal.trees > 0 then
        local totalPts = 0
        for _, tree in ipairs(tal.trees) do
            totalPts = totalPts + (tree.points or 0)
        end

        local specColor = "|cff" .. string.format("%02x%02x%02x",
            cc.r * 255, cc.g * 255, cc.b * 255)

        if totalPts > 0 then
            talentSpecText:SetText(specColor .. (tal.spec or "") .. "|r  "
                                   .. (tal.points or ""))
            for t = 1, math.min(3, #tal.trees) do
                local tree = tal.trees[t]
                if tree.icon and tree.icon ~= "" then
                    talentIcons[t]:SetTexture(tree.icon)
                    talentIcons[t]:Show()
                end
                talentTexts[t]:SetText(tree.name .. ": " .. tree.points)
            end
        else
            talentSpecText:SetText("|cff888888Talent details unavailable via inspect|r")
            for t = 1, math.min(3, #tal.trees) do
                local tree = tal.trees[t]
                if tree.icon and tree.icon ~= "" then
                    talentIcons[t]:SetTexture(tree.icon)
                    talentIcons[t]:Show()
                end
                talentTexts[t]:SetText(tree.name .. "\n|cff666666N/A|r")
            end
        end
    end

    local s = items .. " items"
    if enchants > 0 or gems > 0 then
        s = s .. "  |  "
        if enchants > 0 then
            s = s .. "|cff00ff00" .. enchants .. " enchant"
                  .. (enchants ~= 1 and "s" or "") .. "|r"
        end
        if enchants > 0 and gems > 0 then s = s .. ", " end
        if gems > 0 then
            s = s .. "|cffff6600" .. gems .. " gem"
                  .. (gems ~= 1 and "s" or "") .. "|r"
        end
    end
    if summaryLabel then summaryLabel:SetText(s) end
end

function AS.RefreshSnapshotList()
    if not browseFrame or not browseFrame:IsShown() then return end
    UIDropDownMenu_Initialize(snapshotDropdown, function(self, level)
        local keys = AS.GetSnapshotKeys()
        for _, key in ipairs(keys) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = key
            info.value   = key
            info.checked = (key == selectedSnapshotKey)
            info.func = function(self)
                selectedSnapshotKey = self.value
                selectedMemberName  = nil
                UIDropDownMenu_SetText(snapshotDropdown, self.value)
                CloseDropDownMenus()
                AS.RefreshMemberList()
                AS.ClearPaperDoll()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if selectedSnapshotKey then
        UIDropDownMenu_SetText(snapshotDropdown, selectedSnapshotKey)
    end
end

function AS.OnMemberCaptured()
    if not browseFrame or not browseFrame:IsShown() then return end
    if AS.session.snapshotKey and selectedSnapshotKey == AS.session.snapshotKey then
        AS.RefreshMemberList()
    end
end

function AS.UpdateGroupCheckbox()
    if groupCheckbox and AS.db and AS.db.options then
        groupCheckbox:SetChecked(AS.db.options.scanGroup)
    end
end

function AS.UpdateVerboseCheckbox()
    if verboseCheckbox and AS.db and AS.db.options then
        verboseCheckbox:SetChecked(AS.db.options.verbose)
    end
end

function AS.ToggleBrowseFrame()
    if AS.standaloneConflict then
        Print("Module disabled — standalone ArmorySnap addon is running.")
        return
    end
    CreateBrowseFrame()
    if browseFrame:IsShown() then
        browseFrame:Hide()
    else
        if groupCheckbox then groupCheckbox:SetChecked(AS.db.options.scanGroup) end
        if themeCheckbox then themeCheckbox:SetChecked(AS.db.options.elvuiTheme) end
        if verboseCheckbox then verboseCheckbox:SetChecked(AS.db.options.verbose) end
        browseFrame:Show()
        AS.ApplyTheme()
        if not selectedSnapshotKey then
            if AS.session.snapshotKey then
                selectedSnapshotKey = AS.session.snapshotKey
            else
                local keys = AS.GetSnapshotKeys()
                if #keys > 0 then selectedSnapshotKey = keys[1] end
            end
            if selectedSnapshotKey then
                UIDropDownMenu_SetText(snapshotDropdown, selectedSnapshotKey)
            end
        end
        AS.RefreshMemberList()
        AS.UpdateScanStatus()
    end
end

function AS:Toggle()
    AS.ToggleBrowseFrame()
end

function AS:ToggleUI()
    AS.ToggleBrowseFrame()
end
