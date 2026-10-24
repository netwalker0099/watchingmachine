-- Watching Machine: PvP Enemy Tracker Module
-- Tracks players who kill you in world PvP, alerts on proximity

local AddonName, WM = ...
local PvPTracker = {}
WM:RegisterModule("PvPTracker", PvPTracker)

PvPTracker.version = "2.8"

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

-- Off on this character: no alerts, nothing tracked, nothing sent to the guild
local function On() return WM:IsModuleOn("PvPTracker") end

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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if prefix ~= SYNC_PREFIX or not On() then return end
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
            if not On() then return end
            if event == "CHAT_MSG_ADDON" then
                pcall(PvPTracker.OnAddonMessage, PvPTracker, prefix, message, distribution, sender)
            end
        end)
        
        -- Queue processor on OnUpdate
        syncFrame:SetScript("OnUpdate", function(self, elapsed)
            if not On() then return end
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

-- Check GUID to confirm it's an actual player (not NPC/creature/pet)
local function IsPlayerGUID(guid)
    if not guid then return false end
    return guid:match("^Player%-") ~= nil
end

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
    if not On() or not PvPTrackerDB.enabled then return end
    
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.guildSync then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.leaderboardEnabled then return end
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
    if not On() or not PvPTrackerDB or not PvPTrackerDB.leaderboardEnabled then return end
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

-- Safe to call again after UnregisterEvents (the panel's switch turns
-- the module off and on again): the handlers are made once and re-attached
local onEvent, onUpdate

function PvPTracker:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        self:MakeHandlers()
    end
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:SetScript("OnUpdate", onUpdate)
end

function PvPTracker:MakeHandlers()
    -- Error throttle: if we get 5 errors in 10 seconds, disable the handler
    local errorCount = 0
    local errorResetTime = 0
    local handlerDisabled = false
    
    onEvent = function(self, event, ...)
        if handlerDisabled or not On() then return end
        
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
    end
    
    -- Periodic nameplate scan (also pcall-protected)
    onUpdate = function(self, elapsed)
        if handlerDisabled or not On() then return end
        scanTimer = scanTimer + elapsed
        if scanTimer >= SCAN_INTERVAL then
            scanTimer = 0
            local ok, err = pcall(PvPTracker.ScanNameplates, PvPTracker)
            if not ok then
                PvPTracker:Print("|cFFFF0000Scan error:|r " .. tostring(err))
            end
        end
    end
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

    -- Settings rows on top, the KOS list fills whatever height is left.
    -- Collapsing Guild Sync or Leaderboard gives the list more room.
    local panel = WM.UI:CreatePanel({
        name = "WM_PvPTrackerFrame",
        title = "PvP Enemy Tracker",
        titleColor = "E63333",
        width = 450,
        height = 700,
        minHeight = 460,
        scroll = false,
    })
    local L = panel.layout
    local function opt(key)
        return function() return PvPTrackerDB[key] end, function(v) PvPTrackerDB[key] = v end
    end
    local get, set

    L:Checkbox({
        label = "Enable PvP Enemy Tracker",
        get = function() return PvPTracker:IsModuleEnabled() end,
        set = function(v) PvPTracker:SetModuleEnabled(v) end,
    })
    local row = L:Row(24)
    get, set = opt("alertSound")
    row:Checkbox({ label = "Sound alerts", get = get, set = set,
        tooltip = { "Sound Alerts", "Play a sound when a KOS enemy is spotted." } }, 8)
    get, set = opt("alertChat")
    row:Checkbox({ label = "Chat alerts", get = get, set = set,
        tooltip = { "Chat Alerts", "Print a line in your chat frame when a KOS enemy is spotted." } }, 153)
    get, set = opt("alertScreen")
    row:Checkbox({ label = "Screen alerts", get = get, set = set,
        tooltip = { "Screen Alerts", "Flash a warning in the middle of the screen when a KOS enemy is spotted." } }, 283)
    get, set = opt("trackManualOnly")
    L:Checkbox({ label = "Manual tracking only (don't auto-add killers)", get = get, set = set,
        tooltip = { "Manual Tracking Only", "Players who kill you are no longer added to the list"
            .. " automatically; only names you add below are tracked." } })

    -- ---------- Guild sync ----------
    L:Section({ key = "sync", title = "Guild Sync" })
    L:Checkbox({
        label = "Enable guild KOS sync",
        get = function() return PvPTrackerDB.guildSync end,
        set = function(v)
            PvPTrackerDB.guildSync = v
            if v then PvPTracker:SendHello() end
            PvPTracker:RefreshList()
        end,
        tooltip = { "Guild KOS Sync", "Share kills and the KOS list with guildies running Watching Machine." },
    })
    row = L:Row(32)
    row:Button({
        text = "Request Sync", width = 100,
        onClick = function() PvPTracker:RequestSync() end,
        tooltip = { "Request Sync", "Ask online guildies running WatchingMachine to send their KOS data."
            .. " Cooldown: 5 minutes." },
    }, 8)
    row:Button({
        text = "Send List", width = 90,
        onClick = function() PvPTracker:SendFullSync() end,
        tooltip = { "Send List", "Push your personal kill data to all online guildies running WatchingMachine." },
    }, 113)
    row:Text({ width = 200,
        text = "|cFF888888Kills broadcast to guild in real-time.\nFull list syncs on login and request.|r" }, 215)
    row = L:Row(24)
    row:Checkbox({
        label = "Auto-request sync on login",
        get = function() return PvPTrackerDB.syncOnLogin ~= false end,  -- default true when sync enabled
        set = function(v) PvPTrackerDB.syncOnLogin = v end,
    }, 8)
    row:Checkbox({
        label = "Announce revenge kills",
        get = function() return PvPTrackerDB.announceRevenge ~= false end,
        set = function(v) PvPTrackerDB.announceRevenge = v end,
        tooltip = { "Announce Revenge Kills", "When you kill someone on the KOS list who was reported by"
            .. " a guildie, announce the kill to guild chat as a revenge message." },
    }, 213)

    -- ---------- Leaderboard ----------
    L:Section({ key = "leaderboard", title = "KOS Leaderboard" })
    row = L:Row(24)
    get, set = opt("leaderboardEnabled")
    row:Checkbox({ label = "Enable point tracking", get = get, set = set,
        tooltip = { "KOS Leaderboard", "Earn 1 point for each KOS-listed enemy you kill. Points are"
            .. " synced with guild members running WatchingMachine." } }, 8)
    row:Choice({
        label = "Announce:", default = "off",
        get = function() return PvPTrackerDB.leaderboardAnnounce end,
        set = function(v)
            PvPTrackerDB.leaderboardAnnounce = v
            if v == "hourly" then lastAnnounceTime = GetTime() end  -- reset timer from now
        end,
        options = {
            { value = "off", text = "Off", width = 32,
              tooltip = { "Announce Off", "Never post the leaderboard to guild chat." } },
            { value = "hourly", text = "Hourly", width = 48,
              tooltip = { "Hourly Announce", "Posts the top 3 to guild chat once per hour." } },
            { value = "onchange", text = "On Lead", width = 60,
              tooltip = { "On Lead Change", "Posts to guild chat when a new player takes the #1 spot on the leaderboard." } },
        },
    }, 213)
    row = L:Row(26)
    row:Button({
        text = "Show Leaderboard", width = 110,
        onClick = function() PvPTracker:ToggleLeaderboard() end,
        tooltip = { "Show Leaderboard", "Open the guild KOS points table." },
    }, 8)
    local myPointsText = row.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    myPointsText:SetPoint("LEFT", row.frame, "LEFT", 128, 0)
    myPointsText:SetText("|cFFFFCC00Your Points: " .. (PvPTrackerDB.myKOSKills or 0) .. "|r")
    panel.myPointsText = myPointsText
    row:RightButton({
        text = "Reset", width = 50, confirm = true,
        onClick = function()
            PvPTrackerDB.myKOSKills = 0
            PvPTrackerDB.leaderboard = {}
            lastLeader = nil
            myPointsText:SetText("|cFFFFCC00Your Points: 0|r")
            if leaderboardFrame and leaderboardFrame:IsShown() then
                PvPTracker:RefreshLeaderboard()
            end
            PvPTracker:Print("Leaderboard reset.")
        end,
        tooltip = { "Reset Leaderboard", "Clears all leaderboard data including your own points and"
            .. " all synced guild data. Click twice to confirm." },
    }, 3)
    L:EndSection()

    -- ---------- Add + list ----------
    L:Space(4)
    row = L:Row(26)
    local function AddName(name)
        if name and name ~= "" then
            PvPTracker:AddManualEnemy(strtrim(name))
            PvPTracker:RefreshList()
        end
    end
    local addBox = row:EditBox({
        name = "WM_PvPTrackerAddBox", label = "Add to KOS:", labelColorKey = "headerColor",
        width = 150, maxLetters = 24, onEnter = AddName, clearOnEnter = true,
        tooltip = { "Add to KOS", "Type a player name and press Enter, or click Add." },
    }, 8)
    row:Button({
        text = "Add", width = 50,
        onClick = function()
            AddName(addBox:GetText())
            addBox:SetText("")
        end,
    }, 243)
    row:Button({
        text = "Add Target", width = 80,
        onClick = function()
            if UnitExists("target") and UnitIsPlayer("target") and not UnitIsFriend("player", "target") then
                PvPTracker:AddManualEnemy(UnitName("target"))
                PvPTracker:RefreshList()
            else
                PvPTracker:Print("No hostile player target selected.")
            end
        end,
        tooltip = { "Add Target", "Add your current target, if it's a hostile player." },
    }, 298)

    row = L:Row(22)
    local listHeader = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("LEFT", row.frame, "LEFT", 8, 0)
    listHeader:SetText("Kill-on-Sight List")
    WM:ThemeText(listHeader, "headerColor")
    local countText = row.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", listHeader, "RIGHT", 10, 0)
    panel.countText = countText
    local syncStatus = row.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncStatus:SetPoint("RIGHT", row.frame, "RIGHT", -68, 0)
    syncStatus:SetText(PvPTrackerDB.guildSync and "|cFF00CC00[Sync ON]|r" or "|cFF888888[Sync OFF]|r")
    panel.syncStatus = syncStatus
    row:RightButton({
        text = "Clear All", width = 60, height = 18, confirm = true, confirmText = "Confirm",
        onClick = function()
            PvPTrackerDB.enemies = {}
            PvPTracker:Print("Enemy list cleared.")
            PvPTracker:RefreshList()
        end,
        tooltip = { "Clear All", "Remove every name from the KOS list. Click twice to confirm." },
    }, 3)

    row = L:Row(16)
    for _, col in ipairs({ { "Name", 3 }, { "Kills", 155 }, { "Last Zone", 195 }, { "Last Kill", 345 } }) do
        local fs = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", row.frame, "LEFT", col[2], 0)
        fs:SetText(col[1])
        fs:SetTextColor(0.7, 0.7, 0.7)
    end

    -- Scrollable enemy list in the remaining space
    local fill = L:Fill(120)
    local scrollFrame = CreateFrame("ScrollFrame", "WM_PvPTrackerScrollFrame", fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(450 - 24 - 23)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    panel.scrollChild = scrollChild
    panel.scrollFrame = scrollFrame
    panel.rows = {}

    panel:Finish()

    mainFrame = panel
    self:RefreshList()
    return panel
end

-- Dashboard on/off switch (see WM:CreateModuleCards). The settings panel's
-- own enable checkbox goes through the same function.
function PvPTracker:IsModuleEnabled()
    return PvPTrackerDB and PvPTrackerDB.enabled and true or false
end

function PvPTracker:SetModuleEnabled(v)
    if PvPTrackerDB == nil or PvPTrackerDB.enemies == nil then self:InitDB() end
    PvPTrackerDB.enabled = v and true or false
    if PvPTrackerDB.enabled then self:RegisterEvents() else self:UnregisterEvents() end
    if mainFrame and mainFrame:IsShown() then mainFrame:Refresh() end
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

local LB_W = 280
local LB_ROW_H = 24
local LB_BAR_W = 70

-- Your points and rank, above the list
local function LeaderboardSubtitle()
    local myPts = PvPTrackerDB and PvPTrackerDB.myKOSKills or 0
    if myPts <= 0 then
        return "|cFF888888No points yet — kill KOS enemies!|r"
    end
    local myRank = "-"
    for i, entry in ipairs(PvPTracker:GetSortedLeaderboard()) do
        if entry.name == playerName then
            myRank = "#" .. i
            break
        end
    end
    return "|cFFCCCCCCYou: " .. myPts .. " pts (" .. myRank .. ")|r"
end

local function NewLeaderboardRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LB_ROW_H)

    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rankText:SetPoint("LEFT", 2, 0)
    row.rankText:SetWidth(22)
    row.rankText:SetJustifyH("RIGHT")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 30, 0)
    row.nameText:SetWidth(96)
    row.nameText:SetJustifyH("LEFT")

    row.barBg = row:CreateTexture(nil, "ARTWORK")
    row.barBg:SetPoint("LEFT", 130, 0)
    row.barBg:SetSize(LB_BAR_W, 12)
    row.barBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    row.barFill:SetPoint("LEFT", 130, 0)

    row.ptsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ptsText:SetPoint("LEFT", 202, 0)
    row.ptsText:SetWidth(30)
    row.ptsText:SetJustifyH("RIGHT")
    return row
end

local RANK_COLORS = { "FFD700", "C0C0C0", "CD7F32" }   -- gold, silver, bronze

-- Fill the list from the sorted board, reusing rows between refreshes
local function RenderLeaderboard(lbf)
    local scrollChild = lbf.scrollChild
    local board = PvPTracker:GetSortedLeaderboard()
    local maxPoints = (board[1] and board[1].points) or 1

    for _, row in ipairs(lbf.rows) do row:Hide() end

    local scrollY = 0
    for i, entry in ipairs(board) do
        local row = lbf.rows[i]
        if not row then
            row = NewLeaderboardRow(scrollChild)
            lbf.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -scrollY)
        row:SetPoint("TOPRIGHT", 0, -scrollY)

        local rankColor = RANK_COLORS[i] or "888888"
        row.rankText:SetText("|cFF" .. rankColor .. "#" .. i .. "|r")
        local nameColor = (entry.name == playerName) and "00FF00" or "FFFFFF"
        row.nameText:SetText("|cFF" .. nameColor .. entry.name .. "|r")

        row.barFill:SetSize(math.max(2, (entry.points / maxPoints) * LB_BAR_W), 12)
        if i == 1 then
            row.barFill:SetColorTexture(1, 0.84, 0, 0.8)  -- Gold
        elseif entry.name == playerName then
            row.barFill:SetColorTexture(0, 0.8, 0, 0.7)    -- Green for you
        else
            row.barFill:SetColorTexture(0.8, 0.3, 0.3, 0.7) -- Red
        end
        row.ptsText:SetText("|cFF" .. rankColor .. entry.points .. "|r")

        row:Show()
        scrollY = scrollY + LB_ROW_H
    end

    -- Empty state
    if #board == 0 then
        lbf.emptyText:Show()
        scrollY = 120
    else
        lbf.emptyText:Hide()
    end

    scrollChild:SetHeight(scrollY + 10)
end

function PvPTracker:CreateLeaderboard()
    if leaderboardFrame then return leaderboardFrame end

    local lbf = WM.UI:CreatePanel({
        name = "WM_PvPLeaderboardFrame",
        title = "KOS Leaderboard",
        titleColor = "FFCC00",
        width = LB_W,
        height = 340,
        scroll = false,
        strata = "DIALOG",
        onRefresh = RenderLeaderboard,
        defaultPoint = { "CENTER", 250, 0 },   -- beside the tracker window until moved
    })
    local L = lbf.layout

    local row = L:Row(18)
    local subtitle = WM.UI.Text(row.frame, { text = LeaderboardSubtitle })
    subtitle:SetPoint("CENTER", row.frame, "CENTER", 0, 0)
    L:Track(subtitle)
    lbf.subtitle = subtitle

    -- Ranked list in the remaining space
    local fill = L:Fill(120)
    local scrollFrame = CreateFrame("ScrollFrame", "WM_PvPLeaderboardScroll", fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(L.width - 22, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", scrollChild, "TOP", 0, -60)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText("|cFF888888No points scored yet.\nKill enemies on the KOS list to earn points.\nEnable guild sync to see others.|r")

    lbf.scrollChild = scrollChild
    lbf.scrollFrame = scrollFrame
    lbf.emptyText = emptyText
    lbf.rows = {}

    leaderboardFrame = lbf:Finish()
    return lbf
end

function PvPTracker:RefreshLeaderboard()
    if not leaderboardFrame then return end
    leaderboardFrame:Refresh()
end

function PvPTracker:ToggleLeaderboard()
    if not leaderboardFrame then
        self:CreateLeaderboard()
    end
    if leaderboardFrame:IsShown() then
        leaderboardFrame:Hide()
    else
        leaderboardFrame:Show()   -- refreshes on show
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

-- Turned off on this character. SetModuleEnabled(false) has already
-- unregistered the tracking events; drop anything still queued for the
-- guild and close the windows.
function PvPTracker:OnModuleOff()
    wipe(sendQueue)
    wipe(detectedEnemies)
    if mainFrame then mainFrame:Hide() end
    if leaderboardFrame then leaderboardFrame:Hide() end
end

-- The module's page in the guided setup
function PvPTracker:SetupPage(L)
    self:InitDB()
    local function opt(key)
        return function() return PvPTrackerDB[key] end, function(v) PvPTrackerDB[key] = v end
    end
    L:Note("Keeps a kill-on-sight (KOS) list. When another player kills you in world PvP (not in battlegrounds"
        .. " or arenas), they're added to it, with how often they've killed you and where.")
    L:Note("|cFFFFFFFFAlerts:|r when someone on the list shows up on a nameplate, as your target or under your"
        .. " mouse, you get a warning: a sound, a line in chat and a message in the middle of the screen. The"
        .. " same player alerts again only after the cooldown.")
    L:Note("|cFFFFFFFFGuild sync:|r guildies running Watching Machine share their kills, so you're warned about"
        .. " players who killed them too. Killing someone who killed a guildie can post a revenge message in"
        .. " guild chat, and each KOS kill earns a point on the guild leaderboard.")
    local get, set = opt("alertSound")
    L:Checkbox({ label = "Sound alert", get = get, set = set,
        tooltip = { "Sound Alert", "Play a sound when a KOS enemy is spotted." } })
    get, set = opt("alertChat")
    L:Checkbox({ label = "Chat alert", get = get, set = set,
        tooltip = { "Chat Alert", "A line in your chat frame (only you see it) with their guild and kills." } })
    get, set = opt("alertScreen")
    L:Checkbox({ label = "Screen alert", get = get, set = set,
        tooltip = { "Screen Alert", "Flash \"ENEMY: name\" in the middle of the screen." } })
    L:Slider({ label = "Alert again after", min = 10, max = 120, step = 5,
        format = function(v) return v .. " sec" end,
        get = function() return PvPTrackerDB.alertCooldown or 30 end,
        set = function(v) PvPTrackerDB.alertCooldown = v end })
    get, set = opt("trackManualOnly")
    L:Checkbox({ label = "Only track names I add myself", get = get, set = set,
        tooltip = { "Manual Tracking Only", "Players who kill you aren't added automatically; only names you"
            .. " add in the window are tracked." } })
    get, set = opt("guildSync")
    L:Checkbox({ label = "Share the KOS list with my guild", get = get, set = set,
        tooltip = { "Guild KOS Sync", "Send your kills to guildies running Watching Machine and receive theirs."
            .. " These are hidden addon messages, not chat." } })
    L:Checkbox({ label = "Ask the guild for their lists when I log in",
        get = function() return PvPTrackerDB.syncOnLogin ~= false end,
        set = function(v) PvPTrackerDB.syncOnLogin = v end,
        disabled = function() return not PvPTrackerDB.guildSync end,
        tooltip = { "Sync on Login", "A few seconds after you log in, ask online guildies for their KOS data"
            .. " (at most once every 5 minutes)." } })
    L:Checkbox({ label = "Announce revenge kills in guild chat",
        get = function() return PvPTrackerDB.announceRevenge ~= false end,
        set = function(v) PvPTrackerDB.announceRevenge = v end,
        disabled = function() return not PvPTrackerDB.guildSync end,
        tooltip = { "Announce Revenge Kills", "When you kill someone who killed a guildie, post"
            .. " \"<you> has slain <them>! <guildie> has been avenged!\" in guild chat, which everyone sees." } })
    get, set = opt("leaderboardEnabled")
    L:Checkbox({ label = "KOS leaderboard points", get = get, set = set,
        tooltip = { "KOS Leaderboard", "1 point for each KOS enemy you kill, shared with your guild." } })
    L:Dropdown({ label = "Post the leaderboard:", width = 120,
        options = { { value = "off", text = "Never" }, { value = "hourly", text = "Hourly" },
            { value = "onchange", text = "On a new leader" } },
        get = function() return PvPTrackerDB.leaderboardAnnounce or "off" end,
        set = function(v)
            PvPTrackerDB.leaderboardAnnounce = v
            if v == "hourly" then lastAnnounceTime = GetTime() end
        end,
        tooltip = { "Post the Leaderboard", "Posts to guild chat: the top 3 once an hour, or when someone new"
            .. " takes first place. Needs guild sync." } })
    L:Note("The KOS list itself, adding names and the leaderboard are in the PvP Enemy Tracker window:"
        .. " |cFFFFFF00/wmachine pvp|r.")
end

function PvPTracker:OpenSettings()
    self:Toggle()
end
