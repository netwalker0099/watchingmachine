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

function AutoLogger:CreateSettingsUI()
    if settingsPanel then return settingsPanel end
    
    local frame = CreateFrame("Frame", "WM_AutoLoggerSettings", UIParent, "BackdropTemplate")
    frame:SetSize(350, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF00FF00Auto Logger|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local yOffset = -50
    local checkboxes = {}
    
    -- Helper function
    local function CreateCheckBox(name, label, tooltip, yPos, onClick)
        local check = CreateFrame("CheckButton", "WM_AL_" .. name, frame, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", 20, yPos)
        check.Text:SetText(label)
        check.tooltipText = tooltip
        check:SetScript("OnClick", onClick)
        checkboxes[name] = check
        return check
    end
    
    -- Chat Logging
    CreateCheckBox("ChatLog", "Enable Chat Logging on Login",
        "Automatically enable chat logging every time you log in", yOffset,
        function(self)
            AutoLoggerDB.enableChatLog = self:GetChecked()
            if AutoLoggerDB.enableChatLog then
                LoggingChat(1)
                AutoLogger:Print("Chat logging enabled")
            else
                AutoLogger:Print("Chat logging will be disabled on next login")
            end
        end)
    
    -- Combat Logging
    yOffset = yOffset - 30
    CreateCheckBox("CombatLog", "Enable Combat Logging in Raids",
        "Automatically enable combat logging when entering raid instances", yOffset,
        function(self)
            AutoLoggerDB.enableCombatLog = self:GetChecked()
            if AutoLoggerDB.enableCombatLog then
                AutoLogger:Print("Combat logging enabled for raids")
                AutoLogger:UpdateCombatLog()
            else
                AutoLogger:Print("Combat logging disabled")
                LoggingCombat(0)
                currentlyLogging = false
            end
        end)
    
    -- Dungeon Logging
    yOffset = yOffset - 30
    CreateCheckBox("DungeonLog", "Enable Combat Logging in Dungeons",
        "Also enable combat logging in 5-man dungeons", yOffset,
        function(self)
            AutoLoggerDB.enableInDungeons = self:GetChecked()
            AutoLogger:UpdateCombatLog()
        end)

    -- Advanced Combat Logging
    yOffset = yOffset - 30
    CreateCheckBox("AdvancedLog", "Keep Advanced Combat Logging On",
        "Checks the advancedCombatLogging setting on login and when entering raids, and re-enables it if it was turned off. Required for complete Warcraft Logs uploads.", yOffset,
        function(self)
            AutoLoggerDB.enableAdvancedLogging = self:GetChecked()
            if AutoLoggerDB.enableAdvancedLogging then
                AutoLogger:EnsureAdvancedLogging("settings toggle")
            else
                AutoLogger:Print("Advanced logging check disabled (CVar left as-is)")
            end
        end)
    
    -- Debug Mode
    yOffset = yOffset - 30
    CreateCheckBox("Debug", "Enable Debug Mode",
        "Show detailed messages when logging is enabled/disabled", yOffset,
        function(self)
            AutoLoggerDB.debugMode = self:GetChecked()
        end)
    
    -- Status section
    yOffset = yOffset - 50
    local statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", 20, yOffset)
    statusLabel:SetText("|cFFFFFF00Current Status:|r")
    
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -8)
    statusText:SetJustifyH("LEFT")
    frame.statusText = statusText
    
    -- Info text
    yOffset = yOffset - 95
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", 20, yOffset)
    infoText:SetWidth(310)
    infoText:SetJustifyH("LEFT")
    infoText:SetText(
        "|cFFFFAA00Log Files:|r World of Warcraft\\_classic_anniversary_\\Logs\\\n\n" ..
        "Combat logs (with Advanced enabled) are required for Warcraft Logs uploads."
    )
    
    -- Refresh function
    frame.Refresh = function()
        checkboxes.ChatLog:SetChecked(AutoLoggerDB.enableChatLog)
        checkboxes.CombatLog:SetChecked(AutoLoggerDB.enableCombatLog)
        checkboxes.DungeonLog:SetChecked(AutoLoggerDB.enableInDungeons)
        checkboxes.AdvancedLog:SetChecked(AutoLoggerDB.enableAdvancedLogging)
        checkboxes.Debug:SetChecked(AutoLoggerDB.debugMode)

        local inInstance, instanceType = IsInInstance()
        local name = GetInstanceInfo()

        local status = "Outside Instances"
        if inInstance then
            status = "In: " .. (name or "Unknown") .. " (" .. (instanceType or "?") .. ")"
        end

        local combatStatus = currentlyLogging and "|cFF00FF00Logging|r" or "|cFFFF0000Not Logging|r"
        local advStatus = AutoLogger:IsAdvancedLoggingEnabled() and "|cFF00FF00On|r" or "|cFFFF0000Off|r"
        statusText:SetText(status .. "\nCombat Log: " .. combatStatus .. "\nAdvanced Logging: " .. advStatus)
    end
    
    frame:SetScript("OnShow", frame.Refresh)
    
    settingsPanel = frame
    return frame
end

function AutoLogger:OpenSettings()
    local panel = self:CreateSettingsUI()
    panel:Show()
    panel.Refresh()
end

function AutoLogger:ToggleUI()
    local panel = self:CreateSettingsUI()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        panel.Refresh()
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
            settingsPanel.Refresh()
        end
    end
end)
