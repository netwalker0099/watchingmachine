-- Watching Machine: Auto Logger Module
-- Automatic chat and combat logging

local AddonName, WM = ...
local AutoLogger = {}
WM:RegisterModule("AutoLogger", AutoLogger)

-- Default settings
local defaults = {
    enableChatLog = true,
    enableCombatLog = true,
    enableInDungeons = false,
    enableAdvancedLogging = true,  -- keep advancedCombatLogging CVar on (required for WCL uploads)
    debugMode = false,
}

-- State tracking
local currentlyLogging = false
local chatLogEnabled = false

-- ============================================
-- INITIALIZATION
-- ============================================

function AutoLogger:Initialize()
    self:InitDB()
    self:EnableChatLog()
    -- Verify advanced combat logging on login, not just when entering a raid
    self:EnsureAdvancedLogging("login check")
    self:UpdateCombatLog()
end

function AutoLogger:InitDB()
    if not AutoLoggerDB then
        AutoLoggerDB = {}
    end
    for key, value in pairs(defaults) do
        if AutoLoggerDB[key] == nil then
            AutoLoggerDB[key] = value
        end
    end
end

-- ============================================
-- CORE FUNCTIONALITY
-- ============================================

function AutoLogger:Print(msg)
    WM:ModulePrint("AutoLogger", msg)
end

function AutoLogger:DebugPrint(msg)
    if AutoLoggerDB.debugMode then
        self:Print(msg)
    end
end

function AutoLogger:EnableChatLog()
    if not chatLogEnabled and AutoLoggerDB.enableChatLog then
        LoggingChat(1)
        chatLogEnabled = true
        self:DebugPrint("Chat logging enabled")
    end
end

-- Check the advancedCombatLogging CVar and turn it on if it got disabled.
-- WCL uploads are incomplete without it (no gear, no per-target resource data).
function AutoLogger:IsAdvancedLoggingEnabled()
    local value = GetCVar and GetCVar("advancedCombatLogging")
    return value == "1"
end

function AutoLogger:EnsureAdvancedLogging(context)
    if not AutoLoggerDB or not AutoLoggerDB.enableCombatLog or not AutoLoggerDB.enableAdvancedLogging then
        return
    end
    if not SetCVar then return end

    if not self:IsAdvancedLoggingEnabled() then
        SetCVar("advancedCombatLogging", "1")
        self:Print("Advanced combat logging was OFF - re-enabled it (" .. (context or "check") .. ")")
    else
        self:DebugPrint("Advanced combat logging verified on (" .. (context or "check") .. ")")
    end
end

function AutoLogger:ShouldEnableCombatLog()
    local inInstance, instanceType = IsInInstance()
    
    if not inInstance then
        return false
    end
    
    local name, _, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()

    self:DebugPrint(string.format("Instance: %s, Type: %s, Difficulty: %s, MaxPlayers: %d",
        tostring(name), tostring(instanceType), tostring(difficultyName), tostring(maxPlayers)))
    
    -- Enable for raids
    if instanceType == "raid" then
        if maxPlayers == 10 or maxPlayers == 25 or maxPlayers == 40 then
            return true
        end
    end
    
    -- Optionally enable for 5-man dungeons
    if AutoLoggerDB.enableInDungeons and instanceType == "party" then
        return true
    end
    
    return false
end

function AutoLogger:UpdateCombatLog()
    if not AutoLoggerDB or not AutoLoggerDB.enableCombatLog then
        return
    end
    
    local shouldLog = self:ShouldEnableCombatLog()

    if shouldLog and not currentlyLogging then
        -- Make sure advanced logging is on before combat logging starts
        self:EnsureAdvancedLogging("entering instance")
        LoggingCombat(1)
        currentlyLogging = true
        self:Print("Combat logging enabled - Raid instance detected")
    elseif not shouldLog and currentlyLogging then
        LoggingCombat(0)
        currentlyLogging = false
        self:Print("Combat logging disabled - Left raid instance")
    end
end

function AutoLogger:IsCurrentlyLogging()
    return currentlyLogging
end

-- ============================================
-- STATUS
-- ============================================

function AutoLogger:GetQuickStatus()
    if not AutoLoggerDB then return "|cFF888888Not initialized|r" end
    
    local parts = {}
    
    if AutoLoggerDB.enableChatLog then
        table.insert(parts, "|cFF00FF00Chat|r")
    end
    
    if AutoLoggerDB.enableCombatLog then
        if currentlyLogging then
            table.insert(parts, "|cFF00FF00Combat (Active)|r")
        else
            table.insert(parts, "|cFFFFFF00Combat (Ready)|r")
        end
    end
    
    if #parts == 0 then
        return "|cFF888888Disabled|r"
    end
    
    return table.concat(parts, ", ")
end

-- ============================================
-- SETTINGS UI
-- ============================================

local settingsPanel = nil

-- Current instance, combat log and Advanced Logging state, for the panel
local function StatusText()
    local inInstance, instanceType = IsInInstance()
    local name = GetInstanceInfo()

    local status = "Outside Instances"
    if inInstance then
        status = "In: " .. (name or "Unknown") .. " (" .. (instanceType or "?") .. ")"
    end

    local combatStatus = currentlyLogging and "|cFF00FF00Logging|r" or "|cFFFF0000Not Logging|r"
    local advStatus = AutoLogger:IsAdvancedLoggingEnabled() and "|cFF00FF00On|r" or "|cFFFF0000Off|r"
    return status .. "\nCombat Log: " .. combatStatus .. "\nAdvanced Logging: " .. advStatus
end

function AutoLogger:CreateSettingsUI()
    if settingsPanel then return settingsPanel end

    local panel = WM.UI:CreatePanel({
        name = "WM_AutoLoggerSettings",
        title = "Auto Logger",
        titleColor = "00FF00",
        width = 350,
        maxHeight = 700,
    })
    local L = panel.layout

    L:Checkbox({
        label = "Enable Chat Logging on Login",
        get = function() return AutoLoggerDB.enableChatLog end,
        set = function(v)
            AutoLoggerDB.enableChatLog = v
            if v then
                LoggingChat(1)
                AutoLogger:Print("Chat logging enabled")
            else
                AutoLogger:Print("Chat logging will be disabled on next login")
            end
        end,
        tooltip = { "Chat Logging", "Automatically enable chat logging every time you log in." },
    })
    L:Checkbox({
        label = "Enable Combat Logging in Raids",
        get = function() return AutoLoggerDB.enableCombatLog end,
        set = function(v)
            AutoLoggerDB.enableCombatLog = v
            if v then
                AutoLogger:Print("Combat logging enabled for raids")
                AutoLogger:UpdateCombatLog()
            else
                AutoLogger:Print("Combat logging disabled")
                LoggingCombat(0)
                currentlyLogging = false
            end
            panel:Refresh()
        end,
        tooltip = { "Combat Logging", "Automatically enable combat logging when entering raid instances,"
            .. " and turn it off again when you leave." },
    })
    L:Checkbox({
        label = "Enable Combat Logging in Dungeons",
        get = function() return AutoLoggerDB.enableInDungeons end,
        set = function(v)
            AutoLoggerDB.enableInDungeons = v
            AutoLogger:UpdateCombatLog()
            panel:Refresh()
        end,
        tooltip = { "Dungeon Logging", "Also enable combat logging in 5-man dungeons."
            .. " Only applies while combat logging in raids is on." },
    })
    L:Checkbox({
        label = "Keep Advanced Combat Logging On",
        get = function() return AutoLoggerDB.enableAdvancedLogging end,
        set = function(v)
            AutoLoggerDB.enableAdvancedLogging = v
            if v then
                AutoLogger:EnsureAdvancedLogging("settings toggle")
            else
                AutoLogger:Print("Advanced logging check disabled (CVar left as-is)")
            end
            panel:Refresh()
        end,
        tooltip = { "Advanced Combat Logging", "Checks the advancedCombatLogging setting on login and when"
            .. " entering raids, and re-enables it if it was turned off. Required for complete Warcraft Logs uploads.",
            "Only applies while combat logging in raids is on." },
    })
    L:Checkbox({
        label = "Enable Debug Mode",
        get = function() return AutoLoggerDB.debugMode end,
        set = function(v) AutoLoggerDB.debugMode = v end,
        tooltip = { "Debug Mode", "Show detailed messages when logging is enabled/disabled." },
    })

    -- Status, re-read on every Refresh (panel open, zone change)
    L:Space(8)
    L:Header("Current Status")
    local row = L:Row(46)
    panel.statusText = row:Text({ text = StatusText, font = "GameFontHighlight" }, 12)

    L:Space(8)
    L:Note("|cFFFFAA00Log Files:|r |cFF888888World of Warcraft\\_classic_anniversary_\\Logs\\|r")
    L:Note("Combat logs (with Advanced enabled) are required for Warcraft Logs uploads.")

    panel:Finish()

    settingsPanel = panel
    return panel
end

function AutoLogger:OpenSettings()
    local panel = self:CreateSettingsUI()
    if panel:IsShown() then panel:Refresh() else panel:Show() end
end

function AutoLogger:ToggleUI()
    local panel = self:CreateSettingsUI()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end

function AutoLogger:Toggle()
    self:ToggleUI()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        AutoLogger:UpdateCombatLog()
        if settingsPanel and settingsPanel:IsShown() then
            settingsPanel:Refresh()
        end
    end
end)
