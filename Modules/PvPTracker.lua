-- Watching Machine: PvP Enemy Tracker Module
-- Tracks players who kill you in world PvP, alerts on proximity

local AddonName, WM = ...
local PvPTracker = {}
WM:RegisterModule("PvPTracker", PvPTracker)

PvPTracker.version = "2.7"

-- ============================================
-- DEFAULT SETTINGS
-- ============================================

local defaults = {
    enabled = true,
    enemies = {},           -- enemies["Playername"] = { kills=N, firstKill=time, lastKill=time, lastZone="", class="", level=0, guild="", notes="" }
    alertSound = true,
    alertChat = true,
    alertScreen = true,
    alertSoundFile = "Interface\\AddOns\\WatchingMachine\\alert.ogg",  -- fallback to default
    alertCooldown = 30,     -- seconds between repeated alerts for same player
    trackManualOnly = false, -- if true, only track manually added names
    -- Guild sync settings
    guildSync = true,        -- Enable guild sync
    syncAnnounce = true,     -- Show sync messages in chat
    syncOnLogin = true,      -- Auto-request sync from guild on login
    announceRevenge = true,  -- Announce revenge kills to guild chat
    -- Leaderboard settings
    leaderboard = {},        -- leaderboard["PlayerName"] = { points=N, lastUpdate=time }
    myKOSKills = 0,          -- Local player's KOS kill count (= points)
    leaderboardEnabled = true,  -- Enable leaderboard tracking
    leaderboardAnnounce = "off", -- "off", "hourly", "onchange"
}

-- State
local mainFrame = nil
local eventFrame = nil
local lastDamageSource = {}     -- Track who last hit us for kill attribution
local lastDamageDealt = {}      -- Track who we last hit for revenge detection: lastDamageDealt["Name"] = { guid, time }
local alertTimestamps = {}      -- alertTimestamps["Name"] = time of last alert
local detectedEnemies = {}      -- Currently detected nearby enemies
local scanTimer = 0
local SCAN_INTERVAL = 1.0       -- Nameplate scan frequency
local playerName = nil
local playerGUID = nil

-- ============================================
-- GUILD SYNC: COMMS LAYER
-- ============================================

local SYNC_PREFIX = "WMPvP"         -- Addon message prefix (max 16 chars)
local SYNC_VERSION = 1              -- Protocol version
local FIELD_SEP = ":"               -- Field separator within messages

-- Sync state
local syncFrame = nil               -- Frame for CHAT_MSG_ADDON events
local sendQueue = {}                -- Outbound message queue
local sendTimer = 0
local SEND_INTERVAL = 0.35          -- Seconds between queued messages (respect throttle)
local lastSyncRequest = 0           -- Timestamp of last full sync request we sent
local SYNC_REQUEST_COOLDOWN = 300   -- 5 minutes between full sync requests
local lastHelloTime = 0
local HELLO_COOLDOWN = 60           -- Don't send hello more than once per minute
local peerSyncTimestamps = {}       -- peerSyncTimestamps["Player"] = time of last full sync from them

-- Leaderboard state
local lastLeader = nil              -- Name of the current top player
local lastAnnounceTime = 0          -- Timestamp of last hourly announcement
local ANNOUNCE_INTERVAL = 3600      -- 1 hour between periodic announcements
local leaderboardFrame = nil        -- Leaderboard UI frame

-- Compat: TBC uses C_ChatInfo, older Classic uses globals
local function SafeSendAddonMessage(prefix, message, chatType, target)
    local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if fn then
        local ok = pcall(fn, prefix, message, chatType, target)
        return ok
    end
    return false
end

local function SafeRegisterPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, prefix)
    end
end

-- ============================================
-- GUILD SYNC: MESSAGE QUEUE (throttled)
-- ============================================

local function QueueMessage(msg)
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not IsInGuild() then return end
    table.insert(sendQueue, msg)
end

local function ProcessQueue(elapsed)
    if #sendQueue == 0 then return end
    sendTimer = sendTimer + elapsed
    if sendTimer < SEND_INTERVAL then return end
    sendTimer = 0
    
    local msg = table.remove(sendQueue, 1)
    if msg then
        SafeSendAddonMessage(SYNC_PREFIX, msg, "GUILD")
    end
end

-- ============================================
-- GUILD SYNC: PROTOCOL
-- ============================================

-- Escape colons in field values (zone names, guild names can have special chars)
local function EscapeField(str)
    if not str then return "" end
    return str:gsub(":", ";")  -- Simple escape: replace : with ;
end

local function UnescapeField(str)
    if not str then return "" end
    return str:gsub(";", ":")
end

-- Send a real-time kill broadcast: "I just got killed by this person"
function PvPTracker:BroadcastKill(enemyName, enemyData)
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not IsInGuild() then return end
    
    local msg = "K" .. FIELD_SEP 
        .. EscapeField(enemyName) .. FIELD_SEP
        .. (enemyData.class or "UNKNOWN") .. FIELD_SEP
        .. (enemyData.level or 0) .. FIELD_SEP
        .. EscapeField(enemyData.guild or "") .. FIELD_SEP
        .. EscapeField(enemyData.lastZone or "")
    
    -- Kill broadcasts go immediately (high priority, single message)
    SafeSendAddonMessage(SYNC_PREFIX, msg, "GUILD")
end

-- Announce a revenge kill to guild chat
function PvPTracker:AnnounceRevenge(enemyName)
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not PvPTrackerDB.announceRevenge then return end
    if not IsInGuild() then return end
    
    local enemy = PvPTrackerDB.enemies and PvPTrackerDB.enemies[enemyName]
    if not enemy then return end
    if not enemy.guildKills or not next(enemy.guildKills) then return end
    
    -- Build list of guildies who reported this enemy
    local reporters = {}
    for reporter, rdata in pairs(enemy.guildKills) do
        if rdata.kills and rdata.kills > 0 then
            table.insert(reporters, reporter)
        end
    end
    
    if #reporters == 0 then return end
    
    -- Build the avenge message
    local avenged
    if #reporters == 1 then
        avenged = reporters[1] .. " has been avenged!"
    elseif #reporters == 2 then
        avenged = reporters[1] .. " and " .. reporters[2] .. " have been avenged!"
    else
        -- 3+: "A, B, and C have been avenged!"
        local last = table.remove(reporters)
        avenged = table.concat(reporters, ", ") .. ", and " .. last .. " have been avenged!"
    end
    
    local chatMsg = playerName .. " has slain " .. enemyName .. "! " .. avenged
    
    -- Send as visible guild chat message
    pcall(SendChatMessage, chatMsg, "GUILD")
    
    -- Also broadcast via addon message so other WM users see a formatted local alert
    local addonMsg = "V" .. FIELD_SEP .. EscapeField(enemyName) .. FIELD_SEP .. EscapeField(avenged)
    SafeSendAddonMessage(SYNC_PREFIX, addonMsg, "GUILD")
    
    -- Local feedback
    local colorCode = CLASS_COLORS[enemy.class] or "FF3333"
    self:Print("|cFF00FF00REVENGE!|r You slew |cFF" .. colorCode .. enemyName .. "|r! " .. avenged)
end

-- Send a single enemy record for bulk sync
function PvPTracker:QueueSyncEntry(enemyName, enemyData)
    local msg = "S" .. FIELD_SEP
        .. EscapeField(enemyName) .. FIELD_SEP
        .. (enemyData.class or "UNKNOWN") .. FIELD_SEP
        .. (enemyData.kills or 0) .. FIELD_SEP
        .. (enemyData.lastKill or 0) .. FIELD_SEP
        .. (enemyData.level or 0) .. FIELD_SEP
        .. EscapeField(enemyData.guild or "") .. FIELD_SEP
        .. EscapeField(enemyData.lastZone or "")
    
    QueueMessage(msg)
end

-- Send hello (announce presence)
function PvPTracker:SendHello()
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not IsInGuild() then return end
    
    local now = GetTime()
    if now - lastHelloTime < HELLO_COOLDOWN then return end
    lastHelloTime = now
    
    local count = self:GetEnemyCount()
    local points = PvPTrackerDB.myKOSKills or 0
    local msg = "H" .. FIELD_SEP .. count .. FIELD_SEP .. SYNC_VERSION .. FIELD_SEP .. points
    SafeSendAddonMessage(SYNC_PREFIX, msg, "GUILD")
end

-- Request full sync from online guildies
function PvPTracker:RequestSync()
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not IsInGuild() then return end
    
    local now = GetTime()
    if now - lastSyncRequest < SYNC_REQUEST_COOLDOWN then
        self:VerbosePrint("Sync request on cooldown. Try again in " .. math.ceil(SYNC_REQUEST_COOLDOWN - (now - lastSyncRequest)) .. "s.")
        return
    end
    lastSyncRequest = now
    
    SafeSendAddonMessage(SYNC_PREFIX, "R", "GUILD")
    self:VerbosePrint("Requested sync from online guild members.")
end

-- Send our full enemy list (queued/throttled)
function PvPTracker:SendFullSync()
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not IsInGuild() then return end
    
    local count = 0
    for enemyName, enemyData in pairs(PvPTrackerDB.enemies) do
        -- Only sync enemies we have personal kills on (don't echo guild data back)
        if enemyData.kills and enemyData.kills > 0 then
            self:QueueSyncEntry(enemyName, enemyData)
            count = count + 1
        end
    end
    
    if count > 0 then
        self:VerbosePrint("Queued " .. count .. " enemies for guild sync.")
    end
end

-- ============================================
-- GUILD SYNC: RECEIVE + MERGE
-- ============================================

-- Get total kills including guild reports for an enemy
function PvPTracker:GetTotalKills(enemyName)
    local enemy = PvPTrackerDB.enemies[enemyName]
    if not enemy then return 0 end
    
    local total = enemy.kills or 0
    if enemy.guildKills then
        for reporter, rdata in pairs(enemy.guildKills) do
            total = total + (rdata.kills or 0)
        end
    end
    return total
end

-- Get a summary of guild reporters for an enemy
function PvPTracker:GetGuildReporters(enemyName)
    local enemy = PvPTrackerDB.enemies[enemyName]
    if not enemy or not enemy.guildKills then return "" end
    
    local parts = {}
    for reporter, rdata in pairs(enemy.guildKills) do
        table.insert(parts, reporter .. "(" .. (rdata.kills or 0) .. ")")
    end
    if #parts == 0 then return "" end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- Merge a received enemy record from a guild member
function PvPTracker:MergeGuildData(sender, enemyName, class, kills, lastKill, level, guild, zone)
    -- Ignore our own data echoed back
    if sender == playerName then return end
    
    kills = tonumber(kills) or 0
    lastKill = tonumber(lastKill) or 0
    level = tonumber(level) or 0
    
    -- Create enemy entry if it doesn't exist
    if not PvPTrackerDB.enemies[enemyName] then
        PvPTrackerDB.enemies[enemyName] = {
            kills = 0,
            firstKill = 0,
            lastKill = 0,
            lastZone = zone or "",
            class = class or "UNKNOWN",
            level = level,
            guild = guild or "",
            notes = "",
            guildKills = {},
        }
    end
    
    local enemy = PvPTrackerDB.enemies[enemyName]
    
    -- Ensure guildKills table exists
    if not enemy.guildKills then
        enemy.guildKills = {}
    end
    
    -- Update guild kill data for this reporter
    if not enemy.guildKills[sender] then
        enemy.guildKills[sender] = { kills = 0, lastReport = 0, lastZone = "" }
    end
    
    local gk = enemy.guildKills[sender]
    
    -- For SYNC messages: sender's total kill count (take if higher)
    if kills > (gk.kills or 0) then
        gk.kills = kills
    end
    gk.lastReport = time()
    if zone and zone ~= "" then
        gk.lastZone = zone
    end
    
    -- Update enemy metadata to most recent info
    if class and class ~= "" and class ~= "UNKNOWN" then
        enemy.class = class
    end
    if level and level > (enemy.level or 0) then
        enemy.level = level
    end
    if guild and guild ~= "" then
        enemy.guild = guild
    end
    if zone and zone ~= "" and lastKill > (enemy.lastKill or 0) then
        enemy.lastZone = zone
    end
end

-- Handle a real-time kill broadcast from a guild member
function PvPTracker:HandleKillBroadcast(sender, enemyName, class, level, guild, zone)
    if sender == playerName then return end
    
    level = tonumber(level) or 0
    
    -- Create enemy if needed
    if not PvPTrackerDB.enemies[enemyName] then
        PvPTrackerDB.enemies[enemyName] = {
            kills = 0,
            firstKill = 0,
            lastKill = 0,
            lastZone = zone or "",
            class = class or "UNKNOWN",
            level = level,
            guild = guild or "",
            notes = "",
            guildKills = {},
        }
    end
    
    local enemy = PvPTrackerDB.enemies[enemyName]
    if not enemy.guildKills then enemy.guildKills = {} end
    
    if not enemy.guildKills[sender] then
        enemy.guildKills[sender] = { kills = 0, lastReport = 0, lastZone = "" }
    end
    
    -- Increment their kill count by 1 (real-time kill)
    enemy.guildKills[sender].kills = (enemy.guildKills[sender].kills or 0) + 1
    enemy.guildKills[sender].lastReport = time()
    enemy.guildKills[sender].lastZone = zone or ""
    
    -- Update metadata
    if class and class ~= "" and class ~= "UNKNOWN" then enemy.class = class end
    if level > (enemy.level or 0) then enemy.level = level end
    if guild and guild ~= "" then enemy.guild = guild end
    if zone and zone ~= "" then enemy.lastZone = zone end
    
    -- Verbose alert
    local colorCode = CLASS_COLORS[enemy.class] or "FF3333"
    self:VerbosePrint("[Guild Sync] " .. sender .. " killed by " .. enemyName .. " in " .. (zone or "?"))
    
    -- Refresh UI if open
    if mainFrame and mainFrame:IsShown() then
        self:RefreshList()
    end
end

-- Master message handler
function PvPTracker:OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= SYNC_PREFIX then return end
    if distribution ~= "GUILD" then return end
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    
    -- Strip realm from sender if present
    local senderName = sender:match("^([^%-]+)") or sender
    if senderName == playerName then return end  -- Ignore own messages
    
    local parts = { strsplit(FIELD_SEP, message) }
    local msgType = parts[1]
    
    if msgType == "K" and #parts >= 6 then
        -- Kill broadcast: K:Name:Class:Level:Guild:Zone
        local enemyName = UnescapeField(parts[2])
        local class = parts[3]
        local level = parts[4]
        local guild = UnescapeField(parts[5])
        local zone = UnescapeField(parts[6])
        self:HandleKillBroadcast(senderName, enemyName, class, level, guild, zone)
        
    elseif msgType == "S" and #parts >= 8 then
        -- Sync record: S:Name:Class:Kills:LastKill:Level:Guild:Zone
        local enemyName = UnescapeField(parts[2])
        local class = parts[3]
        local kills = parts[4]
        local lastKill = parts[5]
        local level = parts[6]
        local guild = UnescapeField(parts[7])
        local zone = UnescapeField(parts[8])
        self:MergeGuildData(senderName, enemyName, class, kills, lastKill, level, guild, zone)
        
    elseif msgType == "R" then
        -- Sync request: someone wants our data
        -- Throttle: don't send to same person within cooldown
        local now = GetTime()
        if peerSyncTimestamps[senderName] and (now - peerSyncTimestamps[senderName]) < SYNC_REQUEST_COOLDOWN then
            return
        end
        peerSyncTimestamps[senderName] = now
        
        self:VerbosePrint("[Guild Sync] " .. senderName .. " requested sync. Sending data...")
        self:SendFullSync()
        
    elseif msgType == "H" and #parts >= 2 then
        -- Hello: peer logged in with N enemies (optionally with points)
        local peerCount = tonumber(parts[2]) or 0
        local peerPoints = tonumber(parts[4]) or 0  -- H:count:version:points
        local pointStr = ""
        if peerPoints > 0 and PvPTrackerDB.leaderboardEnabled then
            pointStr = ", " .. peerPoints .. " KOS pts"
        end
        self:VerbosePrint("[Guild Sync] " .. senderName .. " online (" .. peerCount .. " enemies" .. pointStr .. ")")
        -- Update leaderboard from hello
        if peerPoints > 0 and PvPTrackerDB.leaderboardEnabled then
            if not PvPTrackerDB.leaderboard then PvPTrackerDB.leaderboard = {} end
            local prev = PvPTrackerDB.leaderboard[senderName]
            if not prev or peerPoints > (prev.points or 0) then
                PvPTrackerDB.leaderboard[senderName] = { points = peerPoints, lastUpdate = time() }
            end
        end
        
    elseif msgType == "V" and #parts >= 3 then
        -- Vengeance: V:EnemyName:AvengeText
        local enemyName = UnescapeField(parts[2])
        local avengeText = UnescapeField(parts[3])
        -- Show formatted revenge alert locally (the guild chat message is already visible)
        local enemy = PvPTrackerDB.enemies and PvPTrackerDB.enemies[enemyName]
        local colorCode = (enemy and CLASS_COLORS[enemy.class]) or "FF3333"
        self:Print("|cFF00FF00REVENGE!|r " .. senderName .. " slew |cFF" .. colorCode .. enemyName .. "|r! " .. avengeText)
        
    elseif msgType == "L" and #parts >= 2 then
        -- Leaderboard: L:Points:EnemyName
        local points = parts[2]
        local enemyName = (#parts >= 3) and UnescapeField(parts[3]) or ""
        self:HandlePointsBroadcast(senderName, points, enemyName)
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

function PvPTracker:InitDB()
    if not PvPTrackerDB then
        PvPTrackerDB = {}
    end
    for key, value in pairs(defaults) do
        if PvPTrackerDB[key] == nil then
            if type(value) == "table" then
                PvPTrackerDB[key] = {}
                for k2, v2 in pairs(value) do
                    if type(v2) == "table" then
                        PvPTrackerDB[key][k2] = {}
                        for k3, v3 in pairs(v2) do
                            PvPTrackerDB[key][k2][k3] = v3
                        end
                    else
                        PvPTrackerDB[key][k2] = v2
                    end
                end
            else
                PvPTrackerDB[key] = value
            end
        end
    end
    -- Ensure sync fields exist for existing installs
    if PvPTrackerDB.guildSync == nil then PvPTrackerDB.guildSync = true end
    if PvPTrackerDB.syncAnnounce == nil then PvPTrackerDB.syncAnnounce = true end
    if PvPTrackerDB.syncOnLogin == nil then PvPTrackerDB.syncOnLogin = true end
    if PvPTrackerDB.announceRevenge == nil then PvPTrackerDB.announceRevenge = true end
    if PvPTrackerDB.leaderboard == nil then PvPTrackerDB.leaderboard = {} end
    if PvPTrackerDB.myKOSKills == nil then PvPTrackerDB.myKOSKills = 0 end
    if PvPTrackerDB.leaderboardEnabled == nil then PvPTrackerDB.leaderboardEnabled = true end
    if PvPTrackerDB.leaderboardAnnounce == nil then PvPTrackerDB.leaderboardAnnounce = "off" end
end

-- Register addon message prefix and sync event handler
function PvPTracker:RegisterSync()
    SafeRegisterPrefix(SYNC_PREFIX)
    
    if not syncFrame then
        syncFrame = CreateFrame("Frame")
        syncFrame:RegisterEvent("CHAT_MSG_ADDON")
        syncFrame:SetScript("OnEvent", function(self, event, prefix, message, distribution, sender)
            if event == "CHAT_MSG_ADDON" then
                pcall(PvPTracker.OnAddonMessage, PvPTracker, prefix, message, distribution, sender)
            end
        end)
        
        -- Queue processor on OnUpdate
        syncFrame:SetScript("OnUpdate", function(self, elapsed)
            ProcessQueue(elapsed)
            -- Periodic leaderboard announce
            if PvPTrackerDB and PvPTrackerDB.leaderboardEnabled then
                local now = GetTime()
                if now - lastAnnounceTime >= ANNOUNCE_INTERVAL then
                    pcall(PvPTracker.CheckPeriodicAnnounce, PvPTracker)
                end
            end
        end)
    end
    
    -- Send hello after a delay (let guild roster load)
    if PvPTrackerDB.guildSync then
        WM.RunAfter(8, function()
            PvPTracker:SendHello()
            -- Auto-request sync from guild on login
            if PvPTrackerDB.syncOnLogin ~= false then
                WM.RunAfter(3, function()
                    PvPTracker:RequestSync()
                end)
            end
        end)
    end
end

function PvPTracker:Initialize()
    self:InitDB()
    playerName = UnitName("player")
    playerGUID = UnitGUID("player")
    self:RegisterEvents()
    self:RegisterSync()
    -- Init leaderboard state
    lastLeader = self:GetLeader()
    lastAnnounceTime = GetTime()  -- Don't announce immediately on login
    self:VerbosePrint("Loaded. Tracking " .. self:GetEnemyCount() .. " enemies.")
end

-- ============================================
-- UTILITIES
-- ============================================

function PvPTracker:Print(msg)
    WM:ModulePrint("PvPTracker", msg)
end

function PvPTracker:VerbosePrint(msg)
    WM:VerbosePrint("PvPTracker", msg)
end

function PvPTracker:GetEnemyCount()
    local count = 0
    for _ in pairs(PvPTrackerDB.enemies) do
        count = count + 1
    end
    return count
end

function PvPTracker:GetQuickStatus()
    if not PvPTrackerDB or not PvPTrackerDB.enabled then
        return "|cFFFF0000Disabled|r"
    end
    local count = self:GetEnemyCount()
    local nearby = 0
    for _ in pairs(detectedEnemies) do nearby = nearby + 1 end
    local base
    if nearby > 0 then
        base = "|cFFFF3333Active|r (" .. count .. " enemies, |cFFFF0000" .. nearby .. " nearby!|r)"
    else
        base = "|cFF00FF00Active|r (" .. count .. " enemies tracked)"
    end
    -- Append leaderboard info if enabled
    if PvPTrackerDB.leaderboardEnabled and PvPTrackerDB.guildSync then
        local pts = PvPTrackerDB.myKOSKills or 0
        if pts > 0 then
            base = base .. " |cFFFFCC00[" .. pts .. " pts]|r"
        end
    end
    return base
end

-- Check if player is in a battleground or arena
local function IsInBattleground()
    -- Check instance type first (most reliable)
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" or instanceType == "arena" then
        return true
    end
    -- Check battlefield status as backup
    local maxBG = 3
    if GetMaxBattlefieldID then maxBG = GetMaxBattlefieldID() or 3 end
    for i = 1, maxBG do
        local status = GetBattlefieldStatus(i)
        if status == "active" then
            return true
        end
    end
    return false
end

-- Get current zone name
local function GetCurrentZone()
    local zone = GetSubZoneText()
    if zone and zone ~= "" then
        return GetZoneText() .. " - " .. zone
    end
    return GetZoneText() or "Unknown"
end

-- Format timestamp to readable date
local function FormatDate(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    return date("%m/%d/%y %H:%M", timestamp)
end

-- Format relative time
local function FormatTimeAgo(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    local diff = time() - timestamp
    if diff < 60 then return diff .. "s ago" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

-- Class colors for display
local CLASS_COLORS = {
    WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473",
    ROGUE = "FFF569", PRIEST = "FFFFFF", DEATHKNIGHT = "C41E3A",
    SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9",
    DRUID = "FF7D0A",
}

-- ============================================
-- KILL TRACKING
-- ============================================

function PvPTracker:RecordKill(killerName, killerGUID)
    if not PvPTrackerDB.enabled then return end
    if not killerName or killerName == "" then return end
    if IsInBattleground() then return end
    if PvPTrackerDB.trackManualOnly then return end
    
    -- Must be an actual player (GUID starts with "Player-"), not an NPC/creature
    if killerGUID and not IsPlayerGUID(killerGUID) then return end
    
    -- Determine class from GUID if possible
    local killerClass = nil
    local killerLevel = nil
    if killerGUID then
        local _, class = GetPlayerInfoByGUID(killerGUID)
        killerClass = class
    end
    
    -- Get guild if target is the killer
    local killerGuild = nil
    if UnitExists("target") and UnitName("target") == killerName then
        killerGuild = GetGuildInfo("target")
        if not killerClass then
            _, killerClass = UnitClass("target")
        end
        killerLevel = UnitLevel("target")
    end
    
    local zone = GetCurrentZone()
    local now = time()
    
    if not PvPTrackerDB.enemies[killerName] then
        PvPTrackerDB.enemies[killerName] = {
            kills = 0,
            firstKill = now,
            lastKill = now,
            lastZone = zone,
            class = killerClass or "UNKNOWN",
            level = killerLevel or 0,
            guild = killerGuild or "",
            notes = "",
        }
    end
    
    local enemy = PvPTrackerDB.enemies[killerName]
    enemy.kills = enemy.kills + 1
    enemy.lastKill = now
    enemy.lastZone = zone
    if killerClass and killerClass ~= "UNKNOWN" then enemy.class = killerClass end
    if killerLevel and killerLevel > 0 then enemy.level = killerLevel end
    if killerGuild and killerGuild ~= "" then enemy.guild = killerGuild end
    
    local colorCode = CLASS_COLORS[enemy.class] or "FF3333"
    self:Print("|cFF" .. colorCode .. killerName .. "|r killed you in " .. zone .. "! (Kill #" .. enemy.kills .. ")")
    
    -- Broadcast to guild
    self:BroadcastKill(killerName, enemy)
end

function PvPTracker:AddManualEnemy(name, notes)
    if not name or name == "" then return end
    
    -- Capitalize first letter
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    
    if not PvPTrackerDB.enemies[name] then
        PvPTrackerDB.enemies[name] = {
            kills = 0,
            firstKill = 0,
            lastKill = 0,
            lastZone = "Manually added",
            class = "UNKNOWN",
            level = 0,
            guild = "",
            notes = notes or "Manually added",
        }
        self:Print("Added |cFFFF3333" .. name .. "|r to kill-on-sight list.")
    else
        if notes and notes ~= "" then
            PvPTrackerDB.enemies[name].notes = notes
        end
        self:Print("|cFFFF3333" .. name .. "|r is already on the list.")
    end
end

function PvPTracker:RemoveEnemy(name)
    if PvPTrackerDB.enemies[name] then
        PvPTrackerDB.enemies[name] = nil
        self:Print("Removed |cFFFFFF00" .. name .. "|r from enemy list.")
        return true
    end
    return false
end

-- ============================================
-- PROXIMITY DETECTION
-- ============================================

function PvPTracker:CheckUnit(unit)
    if not PvPTrackerDB.enabled then return end
    if not unit or not UnitExists(unit) then return end
    if not UnitIsPlayer(unit) then return end
    if UnitIsFriend("player", unit) then return end
    -- Faction check: must be opposite faction (not just hostile NPC)
    if UnitFactionGroup then
        local myFaction = UnitFactionGroup("player")
        local theirFaction = UnitFactionGroup(unit)
        if myFaction and theirFaction and myFaction == theirFaction then return end
    end
    
    local name = UnitName(unit)
    if not name then return end
    
    if PvPTrackerDB.enemies[name] then
        self:TriggerAlert(name, unit)
    end
end

function PvPTracker:ScanNameplates()
    if not PvPTrackerDB.enabled then return end
    if IsInBattleground() then return end
    
    -- Clear old detections
    detectedEnemies = {}
    
    local myFaction = UnitFactionGroup and UnitFactionGroup("player")
    
    -- Scan all nameplate units
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsFriend("player", unit) then
            -- Faction check: skip same-faction players
            local theirFaction = UnitFactionGroup and UnitFactionGroup(unit)
            if not myFaction or not theirFaction or myFaction ~= theirFaction then
                local name = UnitName(unit)
                if name and PvPTrackerDB.enemies[name] then
                    detectedEnemies[name] = true
                    self:TriggerAlert(name, unit)
                end
            end
        end
    end
end

function PvPTracker:TriggerAlert(name, unit)
    if not PvPTrackerDB.enabled then return end
    
    local now = GetTime()
    local cooldown = PvPTrackerDB.alertCooldown or 30
    
    if alertTimestamps[name] and (now - alertTimestamps[name]) < cooldown then
        return -- Still on cooldown
    end
    alertTimestamps[name] = now
    detectedEnemies[name] = true
    
    local enemy = PvPTrackerDB.enemies[name]
    if not enemy then return end
    
    local colorCode = CLASS_COLORS[enemy.class] or "FF3333"
    local nameStr = "|cFF" .. colorCode .. name .. "|r"
    
    -- Update class/level/guild if we have a unit
    if unit and UnitExists(unit) then
        local _, class = UnitClass(unit)
        if class then enemy.class = class end
        local level = UnitLevel(unit)
        if level and level > 0 then enemy.level = level end
        local guild = GetGuildInfo(unit)
        if guild then enemy.guild = guild end
    end
    
    -- Chat alert
    if PvPTrackerDB.alertChat then
        local totalKills = self:GetTotalKills(name)
        local killStr = ""
        if totalKills > 0 then
            if enemy.guildKills and next(enemy.guildKills) then
                killStr = " - " .. totalKills .. " total kills (" .. enemy.kills .. " yours)"
            else
                killStr = " - killed you " .. enemy.kills .. "x"
            end
        end
        local guildStr = ""
        if enemy.guild and enemy.guild ~= "" then
            guildStr = " <" .. enemy.guild .. ">"
        end
        self:Print("|cFFFF0000>> ENEMY DETECTED:|r " .. nameStr .. guildStr .. killStr)
    end
    
    -- Sound alert
    if PvPTrackerDB.alertSound then
        if PlaySound then
            PlaySound(8332, "Master")  -- PVP flag captured
        end
    end
    
    -- Screen alert (raid warning frame)
    if PvPTrackerDB.alertScreen then
        if RaidWarningFrame and RaidWarningFrame.AddMessage then
            RaidWarningFrame:AddMessage("ENEMY: " .. name, 1, 0.2, 0.2, 1, 3)
        end
    end
end

-- ============================================
-- REVENGE KILL DETECTION
-- ============================================

local revengeThrottle = {}  -- Prevent double-fire from PARTY_KILL + UNIT_DIED

function PvPTracker:CheckKOSKill(enemyName)
    if not PvPTrackerDB then return end
    if not enemyName then return end
    
    -- Throttle: don't process same enemy twice within 5 seconds
    local now = GetTime()
    if revengeThrottle[enemyName] and (now - revengeThrottle[enemyName]) < 5 then return end
    revengeThrottle[enemyName] = now
    
    -- Must be on the KOS list
    local enemy = PvPTrackerDB.enemies and PvPTrackerDB.enemies[enemyName]
    if not enemy then return end
    
    -- Award leaderboard point (always, if leaderboard enabled)
    if PvPTrackerDB.leaderboardEnabled and PvPTrackerDB.guildSync then
        self:AwardKOSPoint(enemyName)
    end
    
    -- Check revenge (only if guild reporters exist)
    if PvPTrackerDB.guildSync and PvPTrackerDB.announceRevenge then
        if enemy.guildKills and next(enemy.guildKills) then
            self:AnnounceRevenge(enemyName)
        end
    end
end

-- ============================================
-- LEADERBOARD SYSTEM
-- ============================================

-- Get sorted leaderboard: { {name, points, lastUpdate}, ... }
function PvPTracker:GetSortedLeaderboard()
    if not PvPTrackerDB or not PvPTrackerDB.leaderboard then return {} end
    
    local board = {}
    
    -- Include ourselves
    local myPoints = PvPTrackerDB.myKOSKills or 0
    if myPoints > 0 and playerName then
        board[playerName] = { points = myPoints, lastUpdate = time() }
    end
    
    -- Merge guild data (take higher of local vs synced for ourselves, use synced for others)
    for name, data in pairs(PvPTrackerDB.leaderboard) do
        if name == playerName then
            -- For ourselves, use the higher value
            if data.points and data.points > (myPoints or 0) then
                board[name] = { points = data.points, lastUpdate = data.lastUpdate or 0 }
            end
        else
            if data.points and data.points > 0 then
                board[name] = { points = data.points, lastUpdate = data.lastUpdate or 0 }
            end
        end
    end
    
    -- Convert to sorted array
    local sorted = {}
    for name, data in pairs(board) do
        table.insert(sorted, { name = name, points = data.points, lastUpdate = data.lastUpdate })
    end
    table.sort(sorted, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return (a.lastUpdate or 0) < (b.lastUpdate or 0)  -- Tie: whoever got there first
    end)
    
    return sorted
end

-- Get the current leader name and points
function PvPTracker:GetLeader()
    local board = self:GetSortedLeaderboard()
    if #board > 0 then
        return board[1].name, board[1].points
    end
    return nil, 0
end

-- Award a point for killing a KOS enemy
function PvPTracker:AwardKOSPoint(enemyName)
    PvPTrackerDB.myKOSKills = (PvPTrackerDB.myKOSKills or 0) + 1
    local points = PvPTrackerDB.myKOSKills
    
    -- Update ourselves in leaderboard
    if not PvPTrackerDB.leaderboard then PvPTrackerDB.leaderboard = {} end
    PvPTrackerDB.leaderboard[playerName] = {
        points = points,
        lastUpdate = time(),
    }
    
    -- Local feedback
    self:Print("|cFFFFCC00+1 KOS Point!|r (" .. points .. " total) — killed " .. enemyName)
    
    -- Broadcast to guild
    self:BroadcastPoints(points, enemyName)
    
    -- Check if leadership changed
    self:CheckLeaderChange()
    
    -- Refresh leaderboard UI if open
    if leaderboardFrame and leaderboardFrame:IsShown() then
        self:RefreshLeaderboard()
    end
end

-- Broadcast our points to guild
function PvPTracker:BroadcastPoints(points, enemyName)
    if not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
    if not IsInGuild() then return end
    
    local msg = "L" .. FIELD_SEP .. (points or 0) .. FIELD_SEP .. EscapeField(enemyName or "")
    SafeSendAddonMessage(SYNC_PREFIX, msg, "GUILD")
end

-- Handle received leaderboard broadcast
function PvPTracker:HandlePointsBroadcast(senderName, points, enemyName)
    if senderName == playerName then return end
    if not PvPTrackerDB.leaderboardEnabled then return end
    
    points = tonumber(points) or 0
    if points <= 0 then return end
    
    if not PvPTrackerDB.leaderboard then PvPTrackerDB.leaderboard = {} end
    
    local prev = PvPTrackerDB.leaderboard[senderName]
    local prevPoints = prev and prev.points or 0
    
    -- Only update if higher (monotonically increasing)
    if points > prevPoints then
        PvPTrackerDB.leaderboard[senderName] = {
            points = points,
            lastUpdate = time(),
        }
        
        if enemyName and enemyName ~= "" then
            self:VerbosePrint("[Leaderboard] " .. senderName .. " scored a KOS kill (" .. enemyName .. ") — " .. points .. " pts")
        end
        
        -- Check if this changed the leader
        self:CheckLeaderChange()
        
        -- Refresh leaderboard UI if open
        if leaderboardFrame and leaderboardFrame:IsShown() then
            self:RefreshLeaderboard()
        end
    end
end

-- Check if the top leader changed and announce if configured
function PvPTracker:CheckLeaderChange()
    if not PvPTrackerDB or not PvPTrackerDB.leaderboardEnabled then return end
    if not PvPTrackerDB.guildSync then return end
    
    local newLeader, newPoints = self:GetLeader()
    if not newLeader or newPoints <= 0 then return end
    
    if PvPTrackerDB.leaderboardAnnounce == "onchange" then
        if lastLeader and newLeader ~= lastLeader and newPoints > 0 then
            -- Leadership changed hands
            local chatMsg = "[WM] New KOS Leaderboard Leader: " .. newLeader .. " with " .. newPoints .. " points!"
            if IsInGuild() then
                pcall(SendChatMessage, chatMsg, "GUILD")
            end
            self:Print("|cFFFFCC00[Leaderboard]|r " .. newLeader .. " takes the lead with " .. newPoints .. " points!")
        end
    end
    
    lastLeader = newLeader
end

-- Periodic announcement (called from timer)
function PvPTracker:CheckPeriodicAnnounce()
    if not PvPTrackerDB or not PvPTrackerDB.leaderboardEnabled then return end
    if not PvPTrackerDB.guildSync then return end
    if PvPTrackerDB.leaderboardAnnounce ~= "hourly" then return end
    
    local now = GetTime()
    if now - lastAnnounceTime < ANNOUNCE_INTERVAL then return end
    lastAnnounceTime = now
    
    local leader, points = self:GetLeader()
    if not leader or points <= 0 then return end
    
    -- Build top 3
    local board = self:GetSortedLeaderboard()
    local top = {}
    for i = 1, math.min(3, #board) do
        table.insert(top, board[i].name .. "(" .. board[i].points .. ")")
    end
    
    if #top == 0 then return end
    
    local chatMsg = "[WM] KOS Leaderboard — " .. table.concat(top, ", ")
    if IsInGuild() then
        pcall(SendChatMessage, chatMsg, "GUILD")
    end
end

-- ============================================
-- COMBAT LOG PROCESSING
-- ============================================

-- Safe flag check - handles nil constants gracefully
local PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x0400
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x0040
local NPC_CONTROL = COMBATLOG_OBJECT_CONTROL_NPC or 0x0200

-- Check GUID to confirm it's an actual player (not NPC/creature/pet)
local function IsPlayerGUID(guid)
    if not guid then return false end
    return guid:match("^Player%-") ~= nil
end

local function IsHostilePlayer(flags, guid)
    if not flags or flags == 0 then return false end
    if not bit or not bit.band then return false end
    -- Must have player type flag AND hostile reaction
    if bit.band(flags, PLAYER_FLAG) == 0 then return false end
    if bit.band(flags, HOSTILE_FLAG) == 0 then return false end
    -- Reject NPC-controlled entities (boss pets, mind controlled units)
    if bit.band(flags, NPC_CONTROL) > 0 then return false end
    -- GUID check: definitive — player GUIDs always start with "Player-"
    if guid and not IsPlayerGUID(guid) then return false end
    return true
end

local function IsPlayerFlag(flags, guid)
    if not flags or flags == 0 then return false end
    if not bit or not bit.band then return false end
    if bit.band(flags, PLAYER_FLAG) == 0 then return false end
    -- GUID check if available
    if guid and not IsPlayerGUID(guid) then return false end
    return true
end

function PvPTracker:ProcessCombatLog()
    if not PvPTrackerDB or not PvPTrackerDB.enabled then return end
    if not CombatLogGetCurrentEventInfo then return end
    
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
    
    if not subevent then return end
    if not destGUID and not sourceGUID then return end
    
    -- Track damage sources hitting the player (for kill attribution)
    if destGUID and destGUID == playerGUID and sourceGUID and sourceName then
        if IsHostilePlayer(sourceFlags, sourceGUID) then
            if subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" or
               subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or
               subevent == "SPELL_INSTAKILL" then
                lastDamageSource = {
                    name = sourceName,
                    guid = sourceGUID,
                    time = GetTime(),
                }
            end
        end
    end
    
    -- Detect player death
    if subevent == "UNIT_DIED" and destGUID == playerGUID then
        if lastDamageSource.name and lastDamageSource.time and (GetTime() - lastDamageSource.time) < 5 then
            self:RecordKill(lastDamageSource.name, lastDamageSource.guid)
            lastDamageSource = {}
        end
    end
    
    -- Also catch PARTY_KILL where we are the victim
    if subevent == "PARTY_KILL" and destGUID == playerGUID then
        if sourceName and IsPlayerFlag(sourceFlags, sourceGUID) then
            self:RecordKill(sourceName, sourceGUID)
        end
    end
    
    -- Track outgoing damage from us to hostile players (for revenge detection)
    if sourceGUID and sourceGUID == playerGUID and destGUID and destName then
        if IsHostilePlayer(destFlags, destGUID) then
            if subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" or
               subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or
               subevent == "SPELL_INSTAKILL" then
                lastDamageDealt[destName] = {
                    guid = destGUID,
                    time = GetTime(),
                }
            end
        end
    end
    
    -- Detect PARTY_KILL where we are the killer (works in groups)
    if subevent == "PARTY_KILL" and sourceGUID == playerGUID then
        if destName and IsHostilePlayer(destFlags, destGUID) then
            self:CheckKOSKill(destName)
        end
    end
    
    -- Detect UNIT_DIED for hostile players we recently damaged (works solo)
    if subevent == "UNIT_DIED" and destName and destGUID ~= playerGUID then
        if lastDamageDealt[destName] and (GetTime() - lastDamageDealt[destName].time) < 5 then
            self:CheckKOSKill(destName)
            lastDamageDealt[destName] = nil
        end
    end
    
    -- Proximity: check if any combat log source is a tracked enemy
    if sourceName and PvPTrackerDB.enemies and PvPTrackerDB.enemies[sourceName] then
        if IsPlayerFlag(sourceFlags, sourceGUID) then
            self:TriggerAlert(sourceName, nil)
        end
    end
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

function PvPTracker:RegisterEvents()
    if eventFrame then return end
    
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    
    -- Error throttle: if we get 5 errors in 10 seconds, disable the handler
    local errorCount = 0
    local errorResetTime = 0
    local handlerDisabled = false
    
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if handlerDisabled then return end
        
        local ok, err
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            ok, err = pcall(PvPTracker.ProcessCombatLog, PvPTracker)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            ok, err = pcall(PvPTracker.CheckUnit, PvPTracker, "mouseover")
        elseif event == "PLAYER_TARGET_CHANGED" then
            ok, err = pcall(PvPTracker.CheckUnit, PvPTracker, "target")
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            local unit = ...
            ok, err = pcall(PvPTracker.CheckUnit, PvPTracker, unit)
        else
            ok = true
        end
        
        if not ok then
            local now = GetTime()
            if now - errorResetTime > 10 then
                errorCount = 0
                errorResetTime = now
            end
            errorCount = errorCount + 1
            if errorCount <= 3 then
                PvPTracker:Print("|cFFFF0000Error:|r " .. tostring(err))
            end
            if errorCount >= 5 then
                handlerDisabled = true
                PvPTracker:Print("|cFFFF0000Too many errors - PvP event handler paused. Use /reload to retry.|r")
            end
        end
    end)
    
    -- Periodic nameplate scan (also pcall-protected)
    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        if handlerDisabled then return end
        scanTimer = scanTimer + elapsed
        if scanTimer >= SCAN_INTERVAL then
            scanTimer = 0
            local ok, err = pcall(PvPTracker.ScanNameplates, PvPTracker)
            if not ok then
                PvPTracker:Print("|cFFFF0000Scan error:|r " .. tostring(err))
            end
        end
    end)
end

function PvPTracker:UnregisterEvents()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnUpdate", nil)
        eventFrame:SetScript("OnEvent", nil)
    end
end

-- ============================================
-- SETTINGS UI
-- ============================================

function PvPTracker:CreateUI()
    if mainFrame then return mainFrame end
    
    local frame = CreateFrame("Frame", "WM_PvPTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 780)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    
    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)
    
    local theme = WM:GetTheme()
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("PvP Enemy Tracker")
    title:SetTextColor(0.9, 0.2, 0.2, 1)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local yOffset = -42
    
    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 15, yOffset)
    enableCB.Text:SetText("Enable PvP Enemy Tracker")
    enableCB:SetChecked(PvPTrackerDB.enabled)
    enableCB:SetScript("OnClick", function(self)
        PvPTrackerDB.enabled = self:GetChecked()
        if PvPTrackerDB.enabled then
            PvPTracker:RegisterEvents()
        else
            PvPTracker:UnregisterEvents()
        end
    end)
    
    yOffset = yOffset - 22
    
    -- Alert checkboxes
    local soundCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    soundCB:SetPoint("TOPLEFT", 15, yOffset)
    soundCB.Text:SetText("Sound alerts")
    soundCB:SetChecked(PvPTrackerDB.alertSound)
    soundCB:SetScript("OnClick", function(self) PvPTrackerDB.alertSound = self:GetChecked() end)
    
    local chatCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    chatCB:SetPoint("TOPLEFT", 160, yOffset)
    chatCB.Text:SetText("Chat alerts")
    chatCB:SetChecked(PvPTrackerDB.alertChat)
    chatCB:SetScript("OnClick", function(self) PvPTrackerDB.alertChat = self:GetChecked() end)
    
    local screenCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    screenCB:SetPoint("TOPLEFT", 290, yOffset)
    screenCB.Text:SetText("Screen alerts")
    screenCB:SetChecked(PvPTrackerDB.alertScreen)
    screenCB:SetScript("OnClick", function(self) PvPTrackerDB.alertScreen = self:GetChecked() end)
    
    yOffset = yOffset - 24
    
    -- Manual only toggle
    local manualCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    manualCB:SetPoint("TOPLEFT", 15, yOffset)
    manualCB.Text:SetText("Manual tracking only (don't auto-add killers)")
    manualCB:SetChecked(PvPTrackerDB.trackManualOnly)
    manualCB:SetScript("OnClick", function(self) PvPTrackerDB.trackManualOnly = self:GetChecked() end)
    
    yOffset = yOffset - 28
    
    -- ==========================================
    -- GUILD SYNC SECTION
    -- ==========================================
    local syncLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncLabel:SetPoint("TOPLEFT", 15, yOffset)
    syncLabel:SetText("Guild Sync")
    syncLabel:SetTextColor(unpack(theme.headerColor))
    
    yOffset = yOffset - 20
    
    local syncCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    syncCB:SetPoint("TOPLEFT", 15, yOffset)
    syncCB.Text:SetText("Enable guild KOS sync")
    syncCB:SetChecked(PvPTrackerDB.guildSync)
    syncCB:SetScript("OnClick", function(self)
        PvPTrackerDB.guildSync = self:GetChecked()
        if PvPTrackerDB.guildSync then
            PvPTracker:SendHello()
        end
    end)
    
    yOffset = yOffset - 24
    
    local requestSyncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    requestSyncBtn:SetSize(100, 20)
    requestSyncBtn:SetPoint("TOPLEFT", 15, yOffset)
    requestSyncBtn:SetText("Request Sync")
    requestSyncBtn:SetScript("OnClick", function()
        PvPTracker:RequestSync()
    end)
    requestSyncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Request Sync", 1, 0.8, 0)
        GameTooltip:AddLine("Ask online guildies running WatchingMachine to", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("send their KOS data. Cooldown: 5 minutes.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    requestSyncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local sendSyncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendSyncBtn:SetSize(90, 20)
    sendSyncBtn:SetPoint("LEFT", requestSyncBtn, "RIGHT", 5, 0)
    sendSyncBtn:SetText("Send List")
    sendSyncBtn:SetScript("OnClick", function()
        PvPTracker:SendFullSync()
    end)
    sendSyncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Send List", 1, 0.8, 0)
        GameTooltip:AddLine("Push your personal kill data to all online", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("guildies running WatchingMachine.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sendSyncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local syncDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncDesc:SetPoint("TOPLEFT", 230, yOffset)
    syncDesc:SetWidth(200)
    syncDesc:SetJustifyH("LEFT")
    syncDesc:SetText("|cFF888888Kills broadcast to guild in real-time.\nFull list syncs on login and request.|r")
    
    yOffset = yOffset - 32
    
    -- Auto-request on login toggle
    local autoSyncCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    autoSyncCB:SetPoint("TOPLEFT", 15, yOffset)
    autoSyncCB.Text:SetText("Auto-request sync on login")
    autoSyncCB:SetChecked(PvPTrackerDB.syncOnLogin ~= false) -- default true when sync enabled
    autoSyncCB:SetScript("OnClick", function(self)
        PvPTrackerDB.syncOnLogin = self:GetChecked()
    end)
    
    local revengeCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    revengeCB:SetPoint("TOPLEFT", 220, yOffset)
    revengeCB.Text:SetText("Announce revenge kills")
    revengeCB:SetChecked(PvPTrackerDB.announceRevenge ~= false)
    revengeCB:SetScript("OnClick", function(self)
        PvPTrackerDB.announceRevenge = self:GetChecked()
    end)
    revengeCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Announce Revenge Kills", 1, 0.8, 0)
        GameTooltip:AddLine("When you kill someone on the KOS list who", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("was reported by a guildie, announce the", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("kill to guild chat as a revenge message.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    revengeCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 28
    
    -- ==========================================
    -- LEADERBOARD SECTION
    -- ==========================================
    local lbLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbLabel:SetPoint("TOPLEFT", 15, yOffset)
    lbLabel:SetText("KOS Leaderboard")
    lbLabel:SetTextColor(unpack(theme.headerColor))
    
    yOffset = yOffset - 20
    
    local lbEnableCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    lbEnableCB:SetPoint("TOPLEFT", 15, yOffset)
    lbEnableCB.Text:SetText("Enable point tracking")
    lbEnableCB:SetChecked(PvPTrackerDB.leaderboardEnabled)
    lbEnableCB:SetScript("OnClick", function(self)
        PvPTrackerDB.leaderboardEnabled = self:GetChecked()
    end)
    lbEnableCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("KOS Leaderboard", 1, 0.8, 0)
        GameTooltip:AddLine("Earn 1 point for each KOS-listed enemy you", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("kill. Points are synced with guild members", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("running WatchingMachine.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    lbEnableCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Announce mode dropdown-like buttons
    local announceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    announceLabel:SetPoint("TOPLEFT", 220, yOffset - 2)
    announceLabel:SetText("|cFF888888Announce:|r")
    
    local currentMode = PvPTrackerDB.leaderboardAnnounce or "off"
    
    local modeOffBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    modeOffBtn:SetSize(32, 18)
    modeOffBtn:SetPoint("LEFT", announceLabel, "RIGHT", 5, 0)
    modeOffBtn:SetText("Off")
    
    local modeHourlyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    modeHourlyBtn:SetSize(48, 18)
    modeHourlyBtn:SetPoint("LEFT", modeOffBtn, "RIGHT", 2, 0)
    modeHourlyBtn:SetText("Hourly")
    
    local modeChangeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    modeChangeBtn:SetSize(60, 18)
    modeChangeBtn:SetPoint("LEFT", modeHourlyBtn, "RIGHT", 2, 0)
    modeChangeBtn:SetText("On Lead")
    
    -- Highlight active mode
    local function UpdateModeButtons()
        local mode = PvPTrackerDB.leaderboardAnnounce or "off"
        modeOffBtn:SetText(mode == "off" and "|cFF00FF00Off|r" or "Off")
        modeHourlyBtn:SetText(mode == "hourly" and "|cFF00FF00Hourly|r" or "Hourly")
        modeChangeBtn:SetText(mode == "onchange" and "|cFF00FF00On Lead|r" or "On Lead")
    end
    
    modeOffBtn:SetScript("OnClick", function()
        PvPTrackerDB.leaderboardAnnounce = "off"
        UpdateModeButtons()
    end)
    modeHourlyBtn:SetScript("OnClick", function()
        PvPTrackerDB.leaderboardAnnounce = "hourly"
        lastAnnounceTime = GetTime()  -- Reset timer from now
        UpdateModeButtons()
    end)
    modeHourlyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Hourly Announce", 1, 0.8, 0)
        GameTooltip:AddLine("Posts the top 3 to guild chat once per hour.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    modeHourlyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    modeChangeBtn:SetScript("OnClick", function()
        PvPTrackerDB.leaderboardAnnounce = "onchange"
        UpdateModeButtons()
    end)
    modeChangeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("On Lead Change", 1, 0.8, 0)
        GameTooltip:AddLine("Posts to guild chat when a new player takes", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("the #1 spot on the leaderboard.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    modeChangeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UpdateModeButtons()
    
    yOffset = yOffset - 24
    
    -- Open leaderboard button
    local lbOpenBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    lbOpenBtn:SetSize(110, 20)
    lbOpenBtn:SetPoint("TOPLEFT", 15, yOffset)
    lbOpenBtn:SetText("Show Leaderboard")
    lbOpenBtn:SetScript("OnClick", function()
        PvPTracker:ToggleLeaderboard()
    end)
    
    -- My points display
    local myPointsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    myPointsText:SetPoint("LEFT", lbOpenBtn, "RIGHT", 10, 0)
    local pts = PvPTrackerDB.myKOSKills or 0
    myPointsText:SetText("|cFFFFCC00Your Points: " .. pts .. "|r")
    frame.myPointsText = myPointsText
    
    -- Reset points button
    local lbResetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    lbResetBtn:SetSize(50, 20)
    lbResetBtn:SetPoint("RIGHT", frame, "TOPRIGHT", -15, yOffset)
    lbResetBtn:SetText("Reset")
    lbResetBtn:SetScript("OnClick", function()
        if lbResetBtn._confirm then
            PvPTrackerDB.myKOSKills = 0
            PvPTrackerDB.leaderboard = {}
            lastLeader = nil
            if frame.myPointsText then
                frame.myPointsText:SetText("|cFFFFCC00Your Points: 0|r")
            end
            if leaderboardFrame and leaderboardFrame:IsShown() then
                PvPTracker:RefreshLeaderboard()
            end
            PvPTracker:Print("Leaderboard reset.")
            lbResetBtn:SetText("Reset")
            lbResetBtn._confirm = false
        else
            lbResetBtn:SetText("|cFFFF0000Sure?|r")
            lbResetBtn._confirm = true
            WM.RunAfter(3, function()
                if lbResetBtn._confirm then
                    lbResetBtn:SetText("Reset")
                    lbResetBtn._confirm = false
                end
            end)
        end
    end)
    lbResetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset Leaderboard", 1, 0.3, 0.3)
        GameTooltip:AddLine("Clears all leaderboard data including your", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("own points and all synced guild data.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    lbResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 28
    
    -- Add enemy manually
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 15, yOffset)
    addLabel:SetText("Add to KOS:")
    addLabel:SetTextColor(unpack(theme.headerColor))
    
    local addBox = CreateFrame("EditBox", "WM_PvPTrackerAddBox", frame, "InputBoxTemplate")
    addBox:SetSize(150, 20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(24)
    
    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 20)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 5, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = addBox:GetText()
        if name and name ~= "" then
            PvPTracker:AddManualEnemy(strtrim(name))
            addBox:SetText("")
            PvPTracker:RefreshList()
        end
    end)
    addBox:SetScript("OnEnterPressed", function(self)
        local name = self:GetText()
        if name and name ~= "" then
            PvPTracker:AddManualEnemy(strtrim(name))
            self:SetText("")
            PvPTracker:RefreshList()
        end
        self:ClearFocus()
    end)
    
    -- Add target button
    local addTargetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addTargetBtn:SetSize(80, 20)
    addTargetBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
    addTargetBtn:SetText("Add Target")
    addTargetBtn:SetScript("OnClick", function()
        if UnitExists("target") and UnitIsPlayer("target") and not UnitIsFriend("player", "target") then
            local targetName = UnitName("target")
            PvPTracker:AddManualEnemy(targetName)
            PvPTracker:RefreshList()
        else
            PvPTracker:Print("No hostile player target selected.")
        end
    end)
    
    yOffset = yOffset - 30
    
    -- Enemy list header
    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", 15, yOffset)
    listHeader:SetText("Kill-on-Sight List")
    listHeader:SetTextColor(unpack(theme.headerColor))
    
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", listHeader, "RIGHT", 10, 0)
    frame.countText = countText
    
    -- Sync status tag
    local syncStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncStatus:SetPoint("RIGHT", frame, "TOPRIGHT", -80, yOffset)
    if PvPTrackerDB.guildSync then
        syncStatus:SetText("|cFF00CC00[Sync ON]|r")
    else
        syncStatus:SetText("|cFF888888[Sync OFF]|r")
    end
    frame.syncStatus = syncStatus
    
    -- Clear all button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 18)
    clearBtn:SetPoint("RIGHT", frame, "TOPRIGHT", -15, yOffset)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        -- Confirmation via second click
        if clearBtn._confirm then
            PvPTrackerDB.enemies = {}
            PvPTracker:Print("Enemy list cleared.")
            PvPTracker:RefreshList()
            clearBtn:SetText("Clear All")
            clearBtn._confirm = false
        else
            clearBtn:SetText("|cFFFF0000Confirm|r")
            clearBtn._confirm = true
            WM.RunAfter(3, function()
                if clearBtn._confirm then
                    clearBtn:SetText("Clear All")
                    clearBtn._confirm = false
                end
            end)
        end
    end)
    
    yOffset = yOffset - 8
    
    -- Column headers
    local colY = yOffset
    local headerFont = "GameFontNormalSmall"
    
    local colName = frame:CreateFontString(nil, "OVERLAY", headerFont)
    colName:SetPoint("TOPLEFT", 18, colY)
    colName:SetText("Name")
    colName:SetTextColor(0.7, 0.7, 0.7)
    
    local colKills = frame:CreateFontString(nil, "OVERLAY", headerFont)
    colKills:SetPoint("TOPLEFT", 170, colY)
    colKills:SetText("Kills")
    colKills:SetTextColor(0.7, 0.7, 0.7)
    
    local colZone = frame:CreateFontString(nil, "OVERLAY", headerFont)
    colZone:SetPoint("TOPLEFT", 210, colY)
    colZone:SetText("Last Zone")
    colZone:SetTextColor(0.7, 0.7, 0.7)
    
    local colSeen = frame:CreateFontString(nil, "OVERLAY", headerFont)
    colSeen:SetPoint("TOPLEFT", 360, colY)
    colSeen:SetText("Last Kill")
    colSeen:SetTextColor(0.7, 0.7, 0.7)
    
    yOffset = yOffset - 14
    
    -- Scrollable enemy list
    local scrollFrame = CreateFrame("ScrollFrame", "WM_PvPTrackerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, yOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(scrollChild)
    
    frame.scrollChild = scrollChild
    frame.scrollFrame = scrollFrame
    frame.rows = {}
    
    mainFrame = frame
    self:RefreshList()
    return frame
end

function PvPTracker:RefreshList()
    if not mainFrame then return end
    
    local scrollChild = mainFrame.scrollChild
    
    -- Clear existing rows
    for _, row in ipairs(mainFrame.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    mainFrame.rows = {}
    
    -- Sort enemies: by kill count descending, then by last kill time
    local sorted = {}
    for name, data in pairs(PvPTrackerDB.enemies) do
        table.insert(sorted, { name = name, data = data })
    end
    table.sort(sorted, function(a, b)
        local aTotal = PvPTracker:GetTotalKills(a.name)
        local bTotal = PvPTracker:GetTotalKills(b.name)
        if aTotal ~= bTotal then
            return aTotal > bTotal
        end
        return (a.data.lastKill or 0) > (b.data.lastKill or 0)
    end)
    
    -- Update count text
    if mainFrame.countText then
        -- Count how many have guild data
        local guildCount = 0
        for _, entry in ipairs(sorted) do
            if entry.data.guildKills and next(entry.data.guildKills) then
                guildCount = guildCount + 1
            end
        end
        if guildCount > 0 then
            mainFrame.countText:SetText("|cFF888888(" .. #sorted .. " enemies, |cFFFFCC00" .. guildCount .. " from guild|cFF888888)|r")
        else
            mainFrame.countText:SetText("|cFF888888(" .. #sorted .. " enemies)|r")
        end
    end
    
    -- Update sync status if visible
    if mainFrame.syncStatus then
        if PvPTrackerDB.guildSync then
            mainFrame.syncStatus:SetText("|cFF00CC00[Sync ON]|r")
        else
            mainFrame.syncStatus:SetText("|cFF888888[Sync OFF]|r")
        end
    end
    
    -- Update points display
    if mainFrame.myPointsText then
        local pts = PvPTrackerDB.myKOSKills or 0
        mainFrame.myPointsText:SetText("|cFFFFCC00Your Points: " .. pts .. "|r")
    end
    
    local rowHeight = 22
    local scrollY = 0
    
    for i, entry in ipairs(sorted) do
        local name = entry.name
        local data = entry.data
        
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetSize(scrollChild:GetWidth(), rowHeight)
        row:SetPoint("TOPLEFT", 0, -scrollY)
        
        -- Alternating row background
        if i % 2 == 0 then
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
        end
        
        -- Name (class colored)
        local colorCode = CLASS_COLORS[data.class] or "AAAAAA"
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(148)
        nameText:SetJustifyH("LEFT")
        nameText:SetText("|cFF" .. colorCode .. name .. "|r")
        
        -- Kill count (total = yours + guild)
        local totalKills = PvPTracker:GetTotalKills(name)
        local killText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        killText:SetPoint("LEFT", 158, 0)
        killText:SetWidth(38)
        if totalKills > 0 then
            if data.guildKills and next(data.guildKills) then
                killText:SetText("|cFFFF3333" .. totalKills .. "|r|cFFFFCC00*|r")
            else
                killText:SetText("|cFFFF3333" .. totalKills .. "|r")
            end
        else
            killText:SetText("|cFF888888-|r")
        end
        
        -- Zone (truncated)
        local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        zoneText:SetPoint("LEFT", 198, 0)
        zoneText:SetWidth(148)
        zoneText:SetJustifyH("LEFT")
        local zoneStr = data.lastZone or ""
        if #zoneStr > 25 then zoneStr = zoneStr:sub(1, 24) .. ".." end
        zoneText:SetText("|cFFCCCCCC" .. zoneStr .. "|r")
        
        -- Last kill time
        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetPoint("LEFT", 348, 0)
        timeText:SetWidth(60)
        timeText:SetJustifyH("LEFT")
        timeText:SetText("|cFF888888" .. FormatTimeAgo(data.lastKill) .. "|r")
        
        -- Remove button (X)
        local removeBtn = CreateFrame("Button", nil, row)
        removeBtn:SetSize(14, 14)
        removeBtn:SetPoint("RIGHT", -2, 0)
        
        local removeText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        removeText:SetAllPoints()
        removeText:SetText("|cFFFF4444x|r")
        
        local removeHighlight = removeBtn:CreateTexture(nil, "HIGHLIGHT")
        removeHighlight:SetAllPoints()
        removeHighlight:SetColorTexture(1, 0, 0, 0.15)
        
        removeBtn:SetScript("OnClick", function()
            PvPTracker:RemoveEnemy(name)
            PvPTracker:RefreshList()
        end)
        
        removeBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Remove " .. name, 1, 0.3, 0.3)
            if data.notes and data.notes ~= "" then
                GameTooltip:AddLine("Notes: " .. data.notes, 0.8, 0.8, 0.8, true)
            end
            if data.guild and data.guild ~= "" then
                GameTooltip:AddLine("Guild: <" .. data.guild .. ">", 0.6, 0.6, 0.6)
            end
            if data.kills > 0 then
                GameTooltip:AddLine("Your kills: " .. data.kills, 0.9, 0.3, 0.3)
                GameTooltip:AddLine("First killed you: " .. FormatDate(data.firstKill), 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Last killed you: " .. FormatDate(data.lastKill), 0.6, 0.6, 0.6)
            end
            -- Guild sync kill data
            if data.guildKills and next(data.guildKills) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Guild reports:", 1, 0.8, 0)
                for reporter, rdata in pairs(data.guildKills) do
                    local rKills = rdata.kills or 0
                    local rZone = rdata.lastZone or ""
                    if rZone ~= "" then
                        GameTooltip:AddLine("  " .. reporter .. ": " .. rKills .. "x (last: " .. rZone .. ")", 0.7, 0.7, 0.5)
                    else
                        GameTooltip:AddLine("  " .. reporter .. ": " .. rKills .. "x", 0.7, 0.7, 0.5)
                    end
                end
                local totalKills2 = PvPTracker:GetTotalKills(name)
                GameTooltip:AddLine("Total: " .. totalKills2, 1, 0.4, 0.4)
            end
            GameTooltip:Show()
        end)
        removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        table.insert(mainFrame.rows, row)
        scrollY = scrollY + rowHeight
    end
    
    -- Empty state
    if #sorted == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        emptyText:SetPoint("CENTER", scrollChild, "TOP", 0, -40)
        emptyText:SetText("|cFF888888No enemies tracked yet.\nGet killed in world PvP or add names manually.|r")
        emptyText:SetJustifyH("CENTER")
        
        local emptyRow = CreateFrame("Frame", nil, scrollChild)
        emptyRow:SetSize(1, 80)
        emptyRow._emptyText = emptyText
        table.insert(mainFrame.rows, emptyRow)
        scrollY = 80
    end
    
    scrollChild:SetHeight(scrollY + 10)
end

-- ============================================
-- LEADERBOARD WINDOW
-- ============================================

function PvPTracker:CreateLeaderboard()
    if leaderboardFrame then return leaderboardFrame end
    
    local lbf = CreateFrame("Frame", "WM_PvPLeaderboardFrame", UIParent, "BackdropTemplate")
    lbf:SetSize(280, 340)
    lbf:SetPoint("CENTER", 250, 0)
    lbf:SetMovable(true)
    lbf:EnableMouse(true)
    lbf:SetClampedToScreen(true)
    lbf:RegisterForDrag("LeftButton")
    lbf:SetScript("OnDragStart", lbf.StartMoving)
    lbf:SetScript("OnDragStop", lbf.StopMovingOrSizing)
    lbf:SetFrameStrata("DIALOG")
    lbf:Hide()
    
    WM:SkinPanel(lbf)
    WM:RegisterSkinnedPanel(lbf)
    
    local theme = WM:GetTheme()
    
    -- Title
    local title = lbf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("KOS Leaderboard")
    title:SetTextColor(1, 0.8, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, lbf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    
    -- Subtitle: your rank
    local subtitle = lbf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", 0, -34)
    lbf.subtitle = subtitle
    
    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", "WM_PvPLeaderboardScroll", lbf, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -52)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    lbf.scrollChild = scrollChild
    lbf.scrollFrame = scrollFrame
    lbf.rows = {}
    
    leaderboardFrame = lbf
    return lbf
end

function PvPTracker:RefreshLeaderboard()
    if not leaderboardFrame then return end
    
    local scrollChild = leaderboardFrame.scrollChild
    
    -- Clean old rows
    if leaderboardFrame.rows then
        for _, row in ipairs(leaderboardFrame.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    leaderboardFrame.rows = {}
    
    local board = self:GetSortedLeaderboard()
    local maxPoints = (board[1] and board[1].points) or 1
    
    -- Update subtitle
    if leaderboardFrame.subtitle then
        local myRank = "-"
        local myPts = PvPTrackerDB.myKOSKills or 0
        for i, entry in ipairs(board) do
            if entry.name == playerName then
                myRank = "#" .. i
                break
            end
        end
        if myPts > 0 then
            leaderboardFrame.subtitle:SetText("|cFFCCCCCCYou: " .. myPts .. " pts (" .. myRank .. ")|r")
        else
            leaderboardFrame.subtitle:SetText("|cFF888888No points yet — kill KOS enemies!|r")
        end
    end
    
    local rowHeight = 24
    local scrollY = 0
    
    for i, entry in ipairs(board) do
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetSize(scrollChild:GetWidth(), rowHeight)
        row:SetPoint("TOPLEFT", 0, -scrollY)
        
        -- Rank medal coloring
        local rankColor
        if i == 1 then rankColor = "FFD700"      -- Gold
        elseif i == 2 then rankColor = "C0C0C0"  -- Silver
        elseif i == 3 then rankColor = "CD7F32"   -- Bronze
        else rankColor = "888888"
        end
        
        -- Rank number
        local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rankText:SetPoint("LEFT", 5, 0)
        rankText:SetWidth(22)
        rankText:SetJustifyH("RIGHT")
        rankText:SetText("|cFF" .. rankColor .. "#" .. i .. "|r")
        
        -- Player name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", 32, 0)
        nameText:SetWidth(100)
        nameText:SetJustifyH("LEFT")
        local nameColor = (entry.name == playerName) and "00FF00" or "FFFFFF"
        nameText:SetText("|cFF" .. nameColor .. entry.name .. "|r")
        
        -- Points bar background
        local barBg = row:CreateTexture(nil, "ARTWORK")
        barBg:SetPoint("LEFT", 138, 0)
        barBg:SetSize(90, 12)
        barBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        
        -- Points bar fill
        local barWidth = math.max(2, (entry.points / maxPoints) * 90)
        local barFill = row:CreateTexture(nil, "OVERLAY")
        barFill:SetPoint("LEFT", 138, 0)
        barFill:SetSize(barWidth, 12)
        if i == 1 then
            barFill:SetColorTexture(1, 0.84, 0, 0.8)  -- Gold
        elseif entry.name == playerName then
            barFill:SetColorTexture(0, 0.8, 0, 0.7)    -- Green for you
        else
            barFill:SetColorTexture(0.8, 0.3, 0.3, 0.7) -- Red
        end
        
        -- Points number
        local ptsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ptsText:SetPoint("LEFT", 232, 0)
        ptsText:SetWidth(30)
        ptsText:SetJustifyH("RIGHT")
        ptsText:SetText("|cFF" .. rankColor .. entry.points .. "|r")
        
        table.insert(leaderboardFrame.rows, row)
        scrollY = scrollY + rowHeight
    end
    
    -- Empty state
    if #board == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        emptyText:SetPoint("CENTER", scrollChild, "TOP", 0, -60)
        emptyText:SetText("|cFF888888No points scored yet.\nKill enemies on the KOS list to earn points.\nEnable guild sync to see others.|r")
        emptyText:SetJustifyH("CENTER")
        
        local emptyRow = CreateFrame("Frame", nil, scrollChild)
        emptyRow:SetSize(1, 120)
        emptyRow._emptyText = emptyText
        table.insert(leaderboardFrame.rows, emptyRow)
        scrollY = 120
    end
    
    scrollChild:SetHeight(scrollY + 10)
end

function PvPTracker:ToggleLeaderboard()
    if not leaderboardFrame then
        self:CreateLeaderboard()
    end
    if leaderboardFrame:IsShown() then
        leaderboardFrame:Hide()
    else
        self:RefreshLeaderboard()
        leaderboardFrame:Show()
    end
end

-- ============================================
-- TOGGLE / PUBLIC API
-- ============================================

function PvPTracker:Toggle()
    if not mainFrame then
        self:CreateUI()
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:RefreshList()
        mainFrame:Show()
    end
end

PvPTracker.ToggleUI = PvPTracker.Toggle

function PvPTracker:OpenSettings()
    self:Toggle()
end
