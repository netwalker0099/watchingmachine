-- Watching Machine: Aura Range Module
-- Alerts you when you drift out of range of party auras (Moonkin Aura,
-- Trueshot Aura, Leader of the Pack, paladin auras) and shaman totem buffs.
--
-- How it works: these buffs drop off you the moment you leave their radius,
-- so the module watches UNIT_AURA on the player and compares the tracked
-- buff set between updates. Buff present -> gone while the providing class
-- is still alive in your group = you walked out of range. A movable on-screen
-- alert (plus optional sound) shows until you walk back in, the aura is
-- re-dropped, or the alert times out (totem expired/destroyed).
--
-- False-alarm guards: alerts are suppressed while you're dead (death wipes
-- all buffs), state resets on zone transitions and when leaving the group,
-- and nothing fires if no alive member of the providing class is present.

local AddonName, WM = ...
local AuraRange = {}
WM:RegisterModule("AuraRange", AuraRange)

AuraRange.version = "3.0"

-- ============================================
-- TRACKED AURAS (TBC)
-- ============================================
-- buffs: aura names that count as this entry (aliases across ranks/variants)
-- providerClass: alerts suppressed when no alive member of this class is in group
-- totem: totem-sourced (expires on its own — shorter default relevance)

local TRACKED = {
    -- Party auras
    { key = "moonkin",       label = "Moonkin Aura",           providerClass = "DRUID",
      buffs = { "Moonkin Aura" }, default = true,
      icon = "Interface\\Icons\\Spell_Nature_ForceOfNature" },
    { key = "lotp",          label = "Leader of the Pack",     providerClass = "DRUID",
      buffs = { "Leader of the Pack", "Improved Leader of the Pack" }, default = true,
      icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina" },
    { key = "trueshot",      label = "Trueshot Aura",          providerClass = "HUNTER",
      buffs = { "Trueshot Aura" }, default = true,
      icon = "Interface\\Icons\\Ability_TrueShot" },
    { key = "tree",          label = "Tree of Life",           providerClass = "DRUID",
      buffs = { "Tree of Life" }, default = true,
      icon = "Interface\\Icons\\Ability_Druid_TreeofLife" },
    { key = "paladin",       label = "Paladin Aura",           providerClass = "PALADIN",
      buffs = { "Devotion Aura", "Retribution Aura", "Concentration Aura",
                "Sanctity Aura", "Shadow Resistance Aura",
                "Frost Resistance Aura", "Fire Resistance Aura" }, default = false,
      icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
    -- Shaman totem buffs
    { key = "strength",      label = "Strength of Earth",      providerClass = "SHAMAN", totem = true,
      buffs = { "Strength of Earth" }, default = true,
      icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem" },
    { key = "grace",         label = "Grace of Air",           providerClass = "SHAMAN", totem = true,
      buffs = { "Grace of Air" }, default = true,
      icon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem" },
    { key = "wrathofair",    label = "Wrath of Air",           providerClass = "SHAMAN", totem = true,
      buffs = { "Wrath of Air Totem", "Wrath of Air" }, default = true,
      icon = "Interface\\Icons\\Spell_Nature_SlowingTotem" },
    { key = "totemofwrath",  label = "Totem of Wrath",         providerClass = "SHAMAN", totem = true,
      buffs = { "Totem of Wrath" }, default = true,
      icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath" },
    { key = "manaspring",    label = "Mana Spring",            providerClass = "SHAMAN", totem = true,
      buffs = { "Mana Spring" }, default = true,
      icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
    { key = "healingstream", label = "Healing Stream",         providerClass = "SHAMAN", totem = true,
      buffs = { "Healing Stream" }, default = false,
      icon = "Interface\\Icons\\INV_Spear_04" },
    { key = "stoneskin",     label = "Stoneskin",              providerClass = "SHAMAN", totem = true,
      buffs = { "Stoneskin" }, default = false,
      icon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem" },
    { key = "windfury",      label = "Windfury Totem",         providerClass = "SHAMAN", totem = true,
      buffs = { "Windfury Totem" }, default = false,
      icon = "Interface\\Icons\\Spell_Nature_Windfury" },
}

-- buffName -> entry lookup (built once)
local BUFF_TO_ENTRY = {}
for _, entry in ipairs(TRACKED) do
    for _, buffName in ipairs(entry.buffs) do
        BUFF_TO_ENTRY[buffName] = entry
    end
end

-- Default settings
local defaults = {
    enabled = true,
    soundEnabled = true,
    alertTimeout = 15,     -- seconds before a lost-aura alert gives up (totem expired etc.)
    locked = false,
    frameX = nil,
    frameY = nil,
    trackedAuras = {},     -- per-entry enable
}
for _, entry in ipairs(TRACKED) do
    defaults.trackedAuras[entry.key] = entry.default
end

-- ============================================
-- STATE
-- ============================================

local prevBuffs = {}        -- tracked buff names present at last UNIT_AURA
local activeAlerts = {}     -- buffName -> { entry = e, lostAt = GetTime() }
local alertOrder = {}       -- stable display order of lost buff names
local providerCache = {}    -- class -> { alive = bool, time = GetTime() }
local PROVIDER_CACHE_TIME = 2
local lastSoundAt = 0
local SOUND_THROTTLE = 3
local suppressed = true     -- true until first clean scan (login/zone/death)
local alertFrame = nil
local settingsFrame = nil

-- ============================================
-- INITIALIZATION
-- ============================================

function AuraRange:Initialize()
    self:InitDB()
    self:CreateAlertFrame()
    self:RegisterEvents()
    -- Baseline scan shortly after login so the first UNIT_AURA diff is clean
    WM.RunAfter(3, function()
        AuraRange:ResetState()
    end)
end

function AuraRange:InitDB()
    if not AuraRangeDB then
        AuraRangeDB = {}
    end
    for key, value in pairs(defaults) do
        if AuraRangeDB[key] == nil then
            if type(value) == "table" then
                AuraRangeDB[key] = {}
                for k2, v2 in pairs(value) do
                    AuraRangeDB[key][k2] = v2
                end
            else
                AuraRangeDB[key] = value
            end
        end
    end
    -- Merge new tracked auras from addon updates
    for _, entry in ipairs(TRACKED) do
        if AuraRangeDB.trackedAuras[entry.key] == nil then
            AuraRangeDB.trackedAuras[entry.key] = entry.default
        end
    end
end

function AuraRange:Print(msg)
    WM:ModulePrint("AuraRange", msg)
end

-- ============================================
-- SCANNING
-- ============================================

-- Rebuild the baseline set with no alerting (login, zone, rez, group change)
function AuraRange:ResetState()
    wipe(prevBuffs)
    wipe(activeAlerts)
    wipe(alertOrder)
    suppressed = false
    self:ScanPlayerBuffs(prevBuffs)
    self:UpdateAlertFrame()
end

-- Fill `out` with tracked buff names currently on the player
function AuraRange:ScanPlayerBuffs(out)
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if BUFF_TO_ENTRY[name] then
            out[name] = true
        end
    end
    return out
end

-- Is at least one alive, connected member of `class` in the group?
local function HasAliveProvider(class)
    local cached = providerCache[class]
    local now = GetTime()
    if cached and (now - cached.time) < PROVIDER_CACHE_TIME then
        return cached.alive
    end

    local alive = false
    local function Check(unit)
        if UnitExists(unit) and UnitIsConnected(unit)
            and not UnitIsDeadOrGhost(unit) then
            local _, c = UnitClass(unit)
            if c == class then return true end
        end
        return false
    end

    if Check("player") then
        alive = true
    elseif IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if Check("raid" .. i) then alive = true break end
        end
    else
        for i = 1, 4 do
            if Check("party" .. i) then alive = true break end
        end
    end

    providerCache[class] = { alive = alive, time = now }
    return alive
end

local scratchBuffs = {}

function AuraRange:OnPlayerAuraChanged()
    if not AuraRangeDB or not AuraRangeDB.enabled then return end
    if suppressed then return end

    -- Death wipes every buff — that's not a range problem
    if UnitIsDeadOrGhost("player") then
        wipe(prevBuffs)
        wipe(activeAlerts)
        wipe(alertOrder)
        self:UpdateAlertFrame()
        return
    end

    -- These buffs only come from group members
    if not IsInGroup() and not IsInRaid() then
        wipe(prevBuffs)
        self:ScanPlayerBuffs(prevBuffs)
        return
    end

    wipe(scratchBuffs)
    self:ScanPlayerBuffs(scratchBuffs)

    -- Regained: clear alerts for anything back on us
    for buffName in pairs(scratchBuffs) do
        if activeAlerts[buffName] then
            activeAlerts[buffName] = nil
            for i = #alertOrder, 1, -1 do
                if alertOrder[i] == buffName then
                    table.remove(alertOrder, i)
                end
            end
        end
    end

    -- Lost: tracked buff present last scan, gone now
    local newLoss = false
    for buffName in pairs(prevBuffs) do
        if not scratchBuffs[buffName] and not activeAlerts[buffName] then
            local entry = BUFF_TO_ENTRY[buffName]
            if entry and AuraRangeDB.trackedAuras[entry.key]
                and HasAliveProvider(entry.providerClass) then
                activeAlerts[buffName] = { entry = entry, lostAt = GetTime() }
                table.insert(alertOrder, buffName)
                newLoss = true
            end
        end
    end

    -- Swap prev <- current
    wipe(prevBuffs)
    for name in pairs(scratchBuffs) do
        prevBuffs[name] = true
    end

    if newLoss then
        if AuraRangeDB.soundEnabled then
            local now = GetTime()
            if now - lastSoundAt > SOUND_THROTTLE then
                lastSoundAt = now
                pcall(PlaySound, 8959, "Master")  -- raid warning sound
            end
        end
    end

    self:UpdateAlertFrame()
end

-- ============================================
-- ALERT FRAME
-- ============================================

local MAX_ALERT_LINES = 5

function AuraRange:CreateAlertFrame()
    if alertFrame then return alertFrame end

    local frame = CreateFrame("Frame", "WM_AuraRangeAlertFrame", UIParent, "BackdropTemplate")
    frame:SetSize(240, 40)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.3, 0.05, 0.05, 0.85)
    frame:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
    frame:Hide()

    -- Restore position
    if AuraRangeDB and AuraRangeDB.frameX and AuraRangeDB.frameY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AuraRangeDB.frameX, AuraRangeDB.frameY)
    end

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not AuraRangeDB.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        AuraRangeDB.frameX = x
        AuraRangeDB.frameY = y
    end)
    frame:EnableMouse(not (AuraRangeDB and AuraRangeDB.locked))

    -- Header
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -5)
    header:SetText("|cFFFF4444OUT OF RANGE|r")
    frame.header = header

    -- Alert lines (icon + label)
    frame.lines = {}
    for i = 1, MAX_ALERT_LINES do
        local line = CreateFrame("Frame", nil, frame)
        line:SetSize(220, 18)
        line:SetPoint("TOP", 0, -22 - (i - 1) * 19)

        local icon = line:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        line.icon = icon

        local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        line.text = text

        line:Hide()
        frame.lines[i] = line
    end

    -- Expiry pump + gentle pulse (only runs while the frame is shown)
    local pulseTimer = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        pulseTimer = pulseTimer + elapsed

        -- Pulse the border for visibility
        local pulse = 0.6 + 0.4 * math.abs(math.sin(pulseTimer * 3))
        self:SetBackdropBorderColor(0.9 * pulse + 0.1, 0.2, 0.2, 1)

        -- Expire stale alerts (totem died/expired, aura dropped for good)
        local timeout = AuraRangeDB.alertTimeout or 15
        local now = GetTime()
        local expired = false
        for buffName, alert in pairs(activeAlerts) do
            if now - alert.lostAt > timeout then
                activeAlerts[buffName] = nil
                for i = #alertOrder, 1, -1 do
                    if alertOrder[i] == buffName then
                        table.remove(alertOrder, i)
                    end
                end
                expired = true
            end
        end
        if expired then
            AuraRange:UpdateAlertFrame()
        end
    end)

    alertFrame = frame
    self.alertFrame = frame
    return frame
end

function AuraRange:UpdateAlertFrame()
    if not alertFrame then return end

    local count = #alertOrder
    if count == 0 then
        alertFrame:Hide()
        return
    end

    local shown = math.min(count, MAX_ALERT_LINES)
    for i = 1, MAX_ALERT_LINES do
        local line = alertFrame.lines[i]
        local buffName = alertOrder[i]
        if i <= shown and buffName and activeAlerts[buffName] then
            local entry = activeAlerts[buffName].entry
            line.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            line.text:SetText(entry.label)
            line:Show()
        else
            line:Hide()
        end
    end

    alertFrame:SetHeight(28 + shown * 19)
    alertFrame:Show()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")

function AuraRange:RegisterEvents()
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "UNIT_AURA" then
        if arg1 == "player" then
            AuraRange:OnPlayerAuraChanged()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone transitions legitimately drop totem buffs — clean restart
        suppressed = true
        WM.RunAfter(2, function()
            AuraRange:ResetState()
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        wipe(providerCache)
        -- Provider may have left: re-baseline without alerting
        if not IsInGroup() and not IsInRaid() then
            AuraRange:ResetState()
        end
    elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        -- Coming back to life: rebuild the baseline quietly
        WM.RunAfter(1, function()
            AuraRange:ResetState()
        end)
    end
end)

-- ============================================
-- STATUS
-- ============================================

function AuraRange:GetQuickStatus()
    if not AuraRangeDB then return "|cFF888888Not initialized|r" end
    if not AuraRangeDB.enabled then return "|cFFFF0000Disabled|r" end

    local enabledCount = 0
    for _, entry in ipairs(TRACKED) do
        if AuraRangeDB.trackedAuras[entry.key] then
            enabledCount = enabledCount + 1
        end
    end

    local lostCount = #alertOrder
    if lostCount > 0 then
        return "|cFFFF4444" .. lostCount .. " aura(s) out of range!|r"
    end
    local soundTag = AuraRangeDB.soundEnabled and " |cFFFFCC00[Sound]|r" or ""
    return "|cFF00FF00Watching|r (" .. enabledCount .. " auras)" .. soundTag
end

-- ============================================
-- SETTINGS UI
-- ============================================

function AuraRange:CreateUI()
    if settingsFrame then return settingsFrame end

    local theme = WM:GetTheme()

    local frame = CreateFrame("Frame", "WM_AuraRangeSettings", UIParent, "BackdropTemplate")
    frame:SetSize(360, 560)
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFFFF66Aura Range|r")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local yOffset = -45

    -- Enable
    local enableCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 20, yOffset)
    enableCB.Text:SetText("Enable out-of-range alerts")
    enableCB:SetChecked(AuraRangeDB.enabled)
    enableCB:SetScript("OnClick", function(self)
        AuraRangeDB.enabled = self:GetChecked()
        if AuraRangeDB.enabled then
            AuraRange:ResetState()
        else
            wipe(activeAlerts)
            wipe(alertOrder)
            AuraRange:UpdateAlertFrame()
        end
    end)

    yOffset = yOffset - 26

    -- Sound
    local soundCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    soundCB:SetPoint("TOPLEFT", 20, yOffset)
    soundCB.Text:SetText("Play sound when an aura is lost")
    soundCB:SetChecked(AuraRangeDB.soundEnabled)
    soundCB:SetScript("OnClick", function(self)
        AuraRangeDB.soundEnabled = self:GetChecked()
    end)

    yOffset = yOffset - 26

    -- Lock alert frame
    local lockCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    lockCB:SetPoint("TOPLEFT", 20, yOffset)
    lockCB.Text:SetText("Lock alert frame position")
    lockCB:SetChecked(AuraRangeDB.locked)
    lockCB:SetScript("OnClick", function(self)
        AuraRangeDB.locked = self:GetChecked()
        if alertFrame then
            alertFrame:EnableMouse(not AuraRangeDB.locked)
        end
    end)

    yOffset = yOffset - 30

    -- Timeout slider
    local toLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toLabel:SetPoint("TOPLEFT", 25, yOffset)
    toLabel:SetText("Alert timeout:")

    local toValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toValue:SetPoint("LEFT", toLabel, "RIGHT", 5, 0)
    toValue:SetText(AuraRangeDB.alertTimeout .. "s")

    local toSlider = CreateFrame("Slider", "WM_AuraRangeTimeoutSlider", frame, "OptionsSliderTemplate")
    toSlider:SetPoint("TOPLEFT", 25, yOffset - 18)
    toSlider:SetSize(180, 16)
    toSlider:SetMinMaxValues(5, 30)
    toSlider:SetValueStep(1)
    toSlider:SetObeyStepOnDrag(true)
    toSlider:SetValue(AuraRangeDB.alertTimeout)
    toSlider.Low:SetText("5s")
    toSlider.High:SetText("30s")
    toSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        AuraRangeDB.alertTimeout = value
        toValue:SetText(value .. "s")
    end)
    toSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Alert Timeout", 1, 0.8, 0)
        GameTooltip:AddLine("How long an out-of-range alert stays up before", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("assuming the totem/aura is simply gone (expired,", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("destroyed, or the provider shifted forms).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    toSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Test button (same row, right)
    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(90, 22)
    testBtn:SetPoint("TOPRIGHT", -20, yOffset - 12)
    testBtn:SetText("Test Alert")
    testBtn:SetScript("OnClick", function()
        local entry = TRACKED[1]
        activeAlerts[entry.buffs[1]] = { entry = entry, lostAt = GetTime() }
        table.insert(alertOrder, entry.buffs[1])
        if AuraRangeDB.soundEnabled then
            pcall(PlaySound, 8959, "Master")
        end
        AuraRange:UpdateAlertFrame()
    end)

    yOffset = yOffset - 48

    -- Tracked aura list
    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", 20, yOffset)
    listHeader:SetText("Auras to watch:")
    listHeader:SetTextColor(unpack(theme.headerColor))

    yOffset = yOffset - 20

    for _, entry in ipairs(TRACKED) do
        local cb = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 25, yOffset)
        local classColor = RAID_CLASS_COLORS[entry.providerClass]
        local hex = classColor and string.format("%02x%02x%02x",
            classColor.r * 255, classColor.g * 255, classColor.b * 255) or "ffffff"
        local tag = entry.totem and " |cFF888888(totem)|r" or ""
        cb.Text:SetText(entry.label .. " |cFF" .. hex .. "("
            .. entry.providerClass:sub(1, 1) .. entry.providerClass:sub(2):lower() .. ")|r" .. tag)
        cb:SetChecked(AuraRangeDB.trackedAuras[entry.key])
        cb:SetScript("OnClick", function(self)
            AuraRangeDB.trackedAuras[entry.key] = self:GetChecked()
        end)
        yOffset = yOffset - 22
    end

    yOffset = yOffset - 6

    -- Info
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", 20, yOffset)
    infoText:SetWidth(320)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("|cFF888888Alerts fire when a buff you had drops off while its provider is alive in your group. Drag the red alert frame to reposition it (unlock first).|r")

    settingsFrame = frame
    self.settingsFrame = frame
    return frame
end

function AuraRange:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function AuraRange:ToggleUI()
    self:Toggle()
end
