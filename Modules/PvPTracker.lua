-- Watching Machine: PvP Enemy Tracker Module
-- Tracks players who kill you in world PvP, alerts on proximity

local AddonName, WM = ...
local PvPTracker = {}
WM:RegisterModule("PvPTracker", PvPTracker)

PvPTracker.version = "1.0"

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
}

-- State
local mainFrame = nil
local eventFrame = nil
local lastDamageSource = {}     -- Track who last hit us for kill attribution
local alertTimestamps = {}      -- alertTimestamps["Name"] = time of last alert
local detectedEnemies = {}      -- Currently detected nearby enemies
local scanTimer = 0
local SCAN_INTERVAL = 1.0       -- Nameplate scan frequency
local playerName = nil
local playerGUID = nil

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
end

function PvPTracker:Initialize()
    self:InitDB()
    playerName = UnitName("player")
    playerGUID = UnitGUID("player")
    self:RegisterEvents()
    self:Print("Loaded. Tracking " .. self:GetEnemyCount() .. " enemies.")
end

-- ============================================
-- UTILITIES
-- ============================================

function PvPTracker:Print(msg)
    WM:ModulePrint("PvPTracker", msg)
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
    if nearby > 0 then
        return "|cFFFF3333Active|r (" .. count .. " enemies, |cFFFF0000" .. nearby .. " nearby!|r)"
    end
    return "|cFF00FF00Active|r (" .. count .. " enemies tracked)"
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
    
    -- Scan all nameplate units
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsFriend("player", unit) then
            local name = UnitName(unit)
            if name and PvPTrackerDB.enemies[name] then
                detectedEnemies[name] = true
                self:TriggerAlert(name, unit)
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
        local killStr = ""
        if enemy.kills > 0 then
            killStr = " - killed you " .. enemy.kills .. "x"
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
-- COMBAT LOG PROCESSING
-- ============================================

-- Safe flag check - handles nil constants gracefully
local PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x0400
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x0040

local function IsHostilePlayer(flags)
    if not flags or flags == 0 then return false end
    if not bit or not bit.band then return false end
    return bit.band(flags, PLAYER_FLAG) > 0 and bit.band(flags, HOSTILE_FLAG) > 0
end

local function IsPlayerFlag(flags)
    if not flags or flags == 0 then return false end
    if not bit or not bit.band then return false end
    return bit.band(flags, PLAYER_FLAG) > 0
end

function PvPTracker:ProcessCombatLog()
    if not PvPTrackerDB or not PvPTrackerDB.enabled then return end
    if not CombatLogGetCurrentEventInfo then return end
    
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
    
    if not subevent then return end
    if not destGUID and not sourceGUID then return end
    
    -- Track damage sources hitting the player (for kill attribution)
    if destGUID and destGUID == playerGUID and sourceGUID and sourceName then
        if IsHostilePlayer(sourceFlags) then
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
        if sourceName and IsPlayerFlag(sourceFlags) then
            self:RecordKill(sourceName, sourceGUID)
        end
    end
    
    -- Proximity: check if any combat log source is a tracked enemy
    if sourceName and PvPTrackerDB.enemies and PvPTrackerDB.enemies[sourceName] then
        if IsPlayerFlag(sourceFlags) then
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
    frame:SetSize(450, 550)
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
        if a.data.kills ~= b.data.kills then
            return a.data.kills > b.data.kills
        end
        return (a.data.lastKill or 0) > (b.data.lastKill or 0)
    end)
    
    -- Update count text
    if mainFrame.countText then
        mainFrame.countText:SetText("|cFF888888(" .. #sorted .. " enemies)|r")
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
        
        -- Kill count
        local killText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        killText:SetPoint("LEFT", 158, 0)
        killText:SetWidth(38)
        if data.kills > 0 then
            killText:SetText("|cFFFF3333" .. data.kills .. "|r")
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
                GameTooltip:AddLine("First killed you: " .. FormatDate(data.firstKill), 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Last killed you: " .. FormatDate(data.lastKill), 0.6, 0.6, 0.6)
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
