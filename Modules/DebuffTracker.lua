-- Watching Machine: Debuff Tracker Module
-- Tracks important raid debuffs on target with priority awareness

local AddonName, WM = ...
local DebuffTracker = {}
WM:RegisterModule("DebuffTracker", DebuffTracker)

DebuffTracker.version = "2.0"

-- ============================================
-- DEBUFF DEFINITIONS (TBC)
-- Priority: Higher number = better version of debuff
-- ============================================

local DEBUFF_CATEGORIES = {
    -- Armor Reduction
    {
        name = "Armor",
        shortName = "Armor",
        color = {1, 0.5, 0},  -- Orange
        debuffs = {
            { name = "Improved Expose Armor", spellIDs = {26866}, priority = 100, class = "ROGUE" },
            { name = "Expose Armor", spellIDs = {26866, 11198, 8647, 8646}, priority = 90, class = "ROGUE" },
            { name = "Sunder Armor", spellIDs = {25225, 11597, 11596, 8380, 7405, 7386}, priority = 80, class = "WARRIOR" },
            { name = "Faerie Fire", spellIDs = {26993, 9907, 9749, 778, 770}, priority = 50, class = "DRUID" },
            { name = "Faerie Fire (Feral)", spellIDs = {27011, 17392, 17391, 16857}, priority = 50, class = "DRUID" },
        }
    },
    -- Physical Damage Increase
    {
        name = "Physical Dmg",
        shortName = "Phys%",
        color = {0.8, 0.2, 0.2},  -- Red
        debuffs = {
            { name = "Blood Frenzy", spellIDs = {29859, 29858}, priority = 100, class = "WARRIOR" },
            { name = "Savage Combat", spellIDs = {58413, 58412}, priority = 100, class = "ROGUE" },
        }
    },
    -- Shadow Damage
    {
        name = "Shadow Dmg",
        shortName = "Shadow",
        color = {0.5, 0, 0.8},  -- Purple
        debuffs = {
            { name = "Shadow Weaving", spellIDs = {15334, 15333, 15332, 15331, 15258}, priority = 100, class = "PRIEST" },
            { name = "Curse of Elements", spellIDs = {27228, 11722, 11721, 1490}, priority = 90, class = "WARLOCK" },
        }
    },
    -- Spell Hit
    {
        name = "Spell Hit",
        shortName = "Hit",
        color = {0, 0.7, 1},  -- Cyan
        debuffs = {
            { name = "Misery", spellIDs = {33198, 33197, 33196, 33195, 33191}, priority = 100, class = "PRIEST" },
        }
    },
    -- Fire Damage
    {
        name = "Fire Dmg",
        shortName = "Fire",
        color = {1, 0.4, 0},  -- Fire orange
        debuffs = {
            { name = "Improved Scorch", spellIDs = {12873, 12872, 12871, 12870, 12869}, priority = 100, class = "MAGE" },
            { name = "Curse of Elements", spellIDs = {27228, 11722, 11721, 1490}, priority = 90, class = "WARLOCK" },
        }
    },
    -- Attack Speed Reduction
    {
        name = "Attack Speed",
        shortName = "AtkSpd",
        color = {0.6, 0.6, 0.6},  -- Gray
        debuffs = {
            { name = "Improved Thunder Clap", spellIDs = {25264, 11581, 11580, 8198, 8204, 6343}, priority = 100, class = "WARRIOR" },
            { name = "Thunder Clap", spellIDs = {25264, 11581, 11580, 8198, 8204, 6343}, priority = 80, class = "WARRIOR" },
            { name = "Infected Wounds", spellIDs = {48485, 48484, 48483}, priority = 90, class = "DRUID" },
        }
    },
    -- Attack Power Reduction
    {
        name = "AP Reduction",
        shortName = "AP-",
        color = {0.4, 0.4, 0.8},  -- Blue-gray
        debuffs = {
            { name = "Demoralizing Shout", spellIDs = {25203, 11556, 11555, 6190, 5242, 1160}, priority = 100, class = "WARRIOR" },
            { name = "Demoralizing Roar", spellIDs = {27551, 9898, 9747, 9490, 1735, 99}, priority = 95, class = "DRUID" },
            { name = "Curse of Weakness", spellIDs = {27224, 11708, 11707, 7646, 6205, 702, 1108}, priority = 80, class = "WARLOCK" },
        }
    },
    -- Healing Reduction
    {
        name = "Healing Debuff",
        shortName = "Heal-",
        color = {0, 0.6, 0.3},  -- Green
        debuffs = {
            { name = "Mortal Strike", spellIDs = {30330, 21553, 21552, 21551, 12294}, priority = 100, class = "WARRIOR" },
            { name = "Wound Poison", spellIDs = {27189, 13224, 13223, 13222, 13221, 13220, 13219, 13218}, priority = 80, class = "ROGUE" },
            { name = "Aimed Shot", spellIDs = {27065, 20904, 20903, 20902, 20901, 20900, 19434}, priority = 70, class = "HUNTER" },
        }
    },
    -- Hunter's Mark
    {
        name = "Hunter's Mark",
        shortName = "Mark",
        color = {0.1, 0.8, 0.1},  -- Bright green
        debuffs = {
            { name = "Hunter's Mark", spellIDs = {14325, 14324, 14323, 1130}, priority = 100, class = "HUNTER" },
        }
    },
}

-- Default settings
local defaults = {
    enabled = true,
    locked = false,
    showOnlyInRaid = true,
    showOnlyOnBoss = false,
    trackedCategories = {},  -- Will be populated with all categories enabled
    scale = 1.0,
    alpha = 1.0,
    frameX = nil,
    frameY = nil,
    compactMode = false,
    hideWhenNoTarget = true,
}

-- Initialize tracked categories
for _, cat in ipairs(DEBUFF_CATEGORIES) do
    defaults.trackedCategories[cat.name] = true
end

-- State
local mainFrame = nil
local trackerFrame = nil
local categoryFrames = {}
local updateTimer = 0
local UPDATE_INTERVAL = 0.2  -- Update 5 times per second

-- ============================================
-- INITIALIZATION
-- ============================================

function DebuffTracker:Initialize()
    self:InitDB()
    self:CreateTrackerFrame()
end

function DebuffTracker:InitDB()
    if not DebuffTrackerDB then
        DebuffTrackerDB = {}
    end
    for key, value in pairs(defaults) do
        if DebuffTrackerDB[key] == nil then
            if type(value) == "table" then
                DebuffTrackerDB[key] = {}
                for k2, v2 in pairs(value) do
                    DebuffTrackerDB[key][k2] = v2
                end
            else
                DebuffTrackerDB[key] = value
            end
        end
    end
end

-- ============================================
-- UTILITIES
-- ============================================

function DebuffTracker:Print(msg)
    WM:ModulePrint("DebuffTracker", msg)
end

-- Check if unit is a boss
local function IsBossUnit(unit)
    if not unit or not UnitExists(unit) then return false end
    
    -- Check classification
    local classification = UnitClassification(unit)
    if classification == "worldboss" or classification == "raidboss" then
        return true
    end
    
    -- Check level (boss level is -1 or very high)
    local level = UnitLevel(unit)
    if level == -1 or level == "??" then
        return true
    end
    
    -- Check if it's a dungeon/raid boss by checking for skull
    if level and level >= 0 then
        local playerLevel = UnitLevel("player")
        if level >= playerLevel + 3 and classification == "elite" then
            return true
        end
    end
    
    return false
end

-- Find active debuff from a category on unit
local function GetActiveDebuff(unit, category)
    if not UnitExists(unit) then return nil end
    
    local bestDebuff = nil
    local bestPriority = 0
    
    for i = 1, 40 do
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, 
              nameplateShowPersonal, spellId = UnitDebuff(unit, i)
        
        if not name then break end
        
        -- Check against category debuffs
        for _, debuff in ipairs(category.debuffs) do
            -- Check by name (more reliable in Classic)
            if name == debuff.name then
                if debuff.priority > bestPriority then
                    bestDebuff = {
                        name = name,
                        icon = icon,
                        count = count,
                        duration = duration,
                        expirationTime = expirationTime,
                        priority = debuff.priority,
                        definition = debuff,
                    }
                    bestPriority = debuff.priority
                end
            end
            
            -- Also check by spellID if available
            if spellId then
                for _, id in ipairs(debuff.spellIDs) do
                    if spellId == id then
                        if debuff.priority > bestPriority then
                            bestDebuff = {
                                name = name,
                                icon = icon,
                                count = count,
                                duration = duration,
                                expirationTime = expirationTime,
                                priority = debuff.priority,
                                definition = debuff,
                            }
                            bestPriority = debuff.priority
                        end
                    end
                end
            end
        end
    end
    
    return bestDebuff
end

-- Get the best possible debuff in a category
local function GetBestDebuff(category)
    local best = nil
    local bestPriority = 0
    for _, debuff in ipairs(category.debuffs) do
        if debuff.priority > bestPriority then
            best = debuff
            bestPriority = debuff.priority
        end
    end
    return best
end

-- ============================================
-- TRACKER FRAME
-- ============================================

function DebuffTracker:CreateTrackerFrame()
    if trackerFrame then return trackerFrame end
    
    local frame = CreateFrame("Frame", "WM_DebuffTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(200, 30)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetFrameStrata("HIGH")
    
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(18)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    titleBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    frame.titleBar = titleBar
    
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 5, 0)
    title:SetText("|cFFFFCC00Debuffs|r")
    frame.title = title
    
    -- Lock button
    local lockBtn = CreateFrame("Button", nil, titleBar)
    lockBtn:SetSize(14, 14)
    lockBtn:SetPoint("RIGHT", -2, 0)
    lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
    lockBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
    lockBtn:SetScript("OnClick", function()
        DebuffTrackerDB.locked = not DebuffTrackerDB.locked
        DebuffTracker:UpdateLockState()
    end)
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(DebuffTrackerDB.locked and "Click to unlock" or "Click to lock")
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.lockBtn = lockBtn
    
    -- Drag handling
    frame:SetScript("OnDragStart", function(self)
        if not DebuffTrackerDB.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        DebuffTrackerDB.frameX = x
        DebuffTrackerDB.frameY = y
    end)
    
    -- Container for category indicators
    local container = CreateFrame("Frame", nil, frame)
    container:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 5, -5)
    container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    frame.container = container
    
    -- Create category indicators
    self:CreateCategoryIndicators(container)
    
    -- Update frame size based on tracked categories
    self:UpdateFrameSize()
    
    -- Restore position
    if DebuffTrackerDB.frameX and DebuffTrackerDB.frameY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DebuffTrackerDB.frameX, DebuffTrackerDB.frameY)
    end
    
    -- Update handler
    frame:SetScript("OnUpdate", function(self, elapsed)
        updateTimer = updateTimer + elapsed
        if updateTimer >= UPDATE_INTERVAL then
            updateTimer = 0
            DebuffTracker:UpdateDebuffs()
        end
    end)
    
    -- Register events
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function(self, event)
        DebuffTracker:UpdateVisibility()
        DebuffTracker:UpdateDebuffs()
    end)
    
    trackerFrame = frame
    self.trackerFrame = frame
    
    self:UpdateLockState()
    self:UpdateVisibility()
    
    return frame
end

function DebuffTracker:CreateCategoryIndicators(container)
    categoryFrames = {}
    
    local xOffset = 0
    local yOffset = 0
    local indicatorSize = 24
    local spacing = 3
    local maxWidth = 180
    
    for i, category in ipairs(DEBUFF_CATEGORIES) do
        local catFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
        catFrame:SetSize(indicatorSize, indicatorSize)
        catFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        catFrame:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        catFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        
        -- Icon
        local icon = catFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        catFrame.icon = icon
        
        -- Status overlay
        local status = catFrame:CreateTexture(nil, "OVERLAY")
        status:SetSize(8, 8)
        status:SetPoint("BOTTOMRIGHT", 2, -2)
        status:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
        catFrame.status = status
        
        -- Stack text
        local stackText = catFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        stackText:SetPoint("BOTTOMRIGHT", -1, 1)
        stackText:SetText("")
        catFrame.stackText = stackText
        
        -- Short name below (for compact mode identification)
        local nameText = catFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("TOP", catFrame, "BOTTOM", 0, -1)
        nameText:SetText(category.shortName)
        nameText:SetTextColor(category.color[1], category.color[2], category.color[3])
        nameText:Hide()  -- Only show in expanded mode
        catFrame.nameText = nameText
        
        -- Tooltip
        catFrame:EnableMouse(true)
        catFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(category.name, category.color[1], category.color[2], category.color[3])
            GameTooltip:AddLine(" ")
            
            -- List possible debuffs
            GameTooltip:AddLine("Debuffs (priority order):", 1, 1, 1)
            local sorted = {}
            for _, d in ipairs(category.debuffs) do
                table.insert(sorted, d)
            end
            table.sort(sorted, function(a, b) return a.priority > b.priority end)
            for _, d in ipairs(sorted) do
                local classColor = RAID_CLASS_COLORS[d.class] or {r=1, g=1, b=1}
                GameTooltip:AddLine("  " .. d.name .. " (" .. d.class .. ")", classColor.r, classColor.g, classColor.b)
            end
            
            -- Show current status
            if self.currentDebuff then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Active: " .. self.currentDebuff.name, 0, 1, 0)
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("MISSING!", 1, 0, 0)
            end
            
            GameTooltip:Show()
        end)
        catFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Position
        catFrame:SetPoint("TOPLEFT", container, "TOPLEFT", xOffset, -yOffset)
        
        xOffset = xOffset + indicatorSize + spacing
        if xOffset + indicatorSize > maxWidth then
            xOffset = 0
            yOffset = yOffset + indicatorSize + spacing + 2
        end
        
        catFrame.category = category
        categoryFrames[i] = catFrame
    end
end

function DebuffTracker:UpdateFrameSize()
    if not trackerFrame then return end
    
    local enabledCount = 0
    for _, category in ipairs(DEBUFF_CATEGORIES) do
        if DebuffTrackerDB.trackedCategories[category.name] then
            enabledCount = enabledCount + 1
        end
    end
    
    local indicatorSize = 24
    local spacing = 3
    local maxPerRow = 6
    local rows = math.ceil(enabledCount / maxPerRow)
    local cols = math.min(enabledCount, maxPerRow)
    
    local width = math.max(100, cols * (indicatorSize + spacing) + 10)
    local height = 18 + rows * (indicatorSize + spacing) + 10
    
    trackerFrame:SetSize(width, height)
    
    -- Reposition indicators
    local xOffset = 0
    local yOffset = 0
    local index = 0
    
    for i, catFrame in ipairs(categoryFrames) do
        local category = catFrame.category
        if DebuffTrackerDB.trackedCategories[category.name] then
            catFrame:Show()
            catFrame:ClearAllPoints()
            catFrame:SetPoint("TOPLEFT", trackerFrame.container, "TOPLEFT", xOffset, -yOffset)
            
            xOffset = xOffset + indicatorSize + spacing
            index = index + 1
            if index % maxPerRow == 0 then
                xOffset = 0
                yOffset = yOffset + indicatorSize + spacing
            end
        else
            catFrame:Hide()
        end
    end
end

function DebuffTracker:UpdateLockState()
    if not trackerFrame then return end
    
    if DebuffTrackerDB.locked then
        trackerFrame.lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        trackerFrame.lockBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
        trackerFrame:EnableMouse(false)
        trackerFrame.titleBar:EnableMouse(true)
        trackerFrame:RegisterForDrag()
    else
        trackerFrame.lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        trackerFrame.lockBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
        trackerFrame:EnableMouse(true)
        trackerFrame:RegisterForDrag("LeftButton")
    end
end

function DebuffTracker:UpdateVisibility()
    if not trackerFrame then return end
    if not DebuffTrackerDB or not DebuffTrackerDB.enabled then
        trackerFrame:Hide()
        return
    end
    
    -- Check if should show
    local shouldShow = true
    
    -- Check raid requirement
    if DebuffTrackerDB.showOnlyInRaid then
        if not IsInRaid() then
            shouldShow = false
        end
    end
    
    -- Check target requirement
    if DebuffTrackerDB.hideWhenNoTarget then
        if not UnitExists("target") or not UnitCanAttack("player", "target") then
            shouldShow = false
        end
    end
    
    -- Check boss requirement
    if shouldShow and DebuffTrackerDB.showOnlyOnBoss then
        if not IsBossUnit("target") then
            shouldShow = false
        end
    end
    
    if shouldShow then
        trackerFrame:Show()
    else
        trackerFrame:Hide()
    end
end

function DebuffTracker:UpdateDebuffs()
    if not trackerFrame or not trackerFrame:IsShown() then return end
    
    local unit = "target"
    if not UnitExists(unit) or not UnitCanAttack("player", unit) then
        -- Clear all indicators
        for _, catFrame in ipairs(categoryFrames) do
            catFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            catFrame.icon:SetTexture(nil)
            catFrame.status:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
            catFrame.stackText:SetText("")
            catFrame.currentDebuff = nil
        end
        return
    end
    
    for _, catFrame in ipairs(categoryFrames) do
        local category = catFrame.category
        
        if not DebuffTrackerDB.trackedCategories[category.name] then
            catFrame:Hide()
        else
            catFrame:Show()
            
            local activeDebuff = GetActiveDebuff(unit, category)
            catFrame.currentDebuff = activeDebuff
            
            if activeDebuff then
                -- Debuff present
                catFrame.icon:SetTexture(activeDebuff.icon)
                catFrame:SetBackdropBorderColor(0, 1, 0, 1)  -- Green border
                catFrame.status:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                
                -- Show stack count if applicable
                if activeDebuff.count and activeDebuff.count > 1 then
                    catFrame.stackText:SetText(activeDebuff.count)
                else
                    catFrame.stackText:SetText("")
                end
                
                -- Check if it's the best version
                local best = GetBestDebuff(category)
                if best and activeDebuff.priority < best.priority then
                    -- Not optimal - yellow border
                    catFrame:SetBackdropBorderColor(1, 1, 0, 1)
                end
            else
                -- Debuff missing
                local best = GetBestDebuff(category)
                if best then
                    -- Show what should be there (greyed out)
                    catFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                catFrame:SetBackdropBorderColor(1, 0, 0, 1)  -- Red border
                catFrame.status:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
                catFrame.stackText:SetText("")
            end
        end
    end
end

-- ============================================
-- STATUS
-- ============================================

function DebuffTracker:GetQuickStatus()
    if not DebuffTrackerDB then return "|cFF888888Not initialized|r" end
    
    if DebuffTrackerDB.enabled then
        local count = 0
        for _, enabled in pairs(DebuffTrackerDB.trackedCategories) do
            if enabled then count = count + 1 end
        end
        return "|cFF00FF00Active|r (" .. count .. " categories)"
    else
        return "|cFFFF0000Disabled|r"
    end
end

-- ============================================
-- SETTINGS UI
-- ============================================

function DebuffTracker:CreateUI()
    if mainFrame then return mainFrame end
    
    local frame = CreateFrame("Frame", "WM_DebuffTrackerSettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(350, 450)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFFFFCC00Debuff Tracker Settings|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local yOffset = -45
    
    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 20, yOffset)
    enableCB.Text:SetText("Enable Debuff Tracker")
    enableCB:SetChecked(DebuffTrackerDB.enabled)
    enableCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.enabled = self:GetChecked()
        DebuffTracker:UpdateVisibility()
    end)
    
    yOffset = yOffset - 25
    
    -- Show only in raid
    local raidCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    raidCB:SetPoint("TOPLEFT", 20, yOffset)
    raidCB.Text:SetText("Show only in raid")
    raidCB:SetChecked(DebuffTrackerDB.showOnlyInRaid)
    raidCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.showOnlyInRaid = self:GetChecked()
        DebuffTracker:UpdateVisibility()
    end)
    
    yOffset = yOffset - 25
    
    -- Show only on boss
    local bossCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    bossCB:SetPoint("TOPLEFT", 20, yOffset)
    bossCB.Text:SetText("Show only on boss targets")
    bossCB:SetChecked(DebuffTrackerDB.showOnlyOnBoss)
    bossCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.showOnlyOnBoss = self:GetChecked()
        DebuffTracker:UpdateVisibility()
    end)
    
    yOffset = yOffset - 25
    
    -- Hide when no target
    local noTargetCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    noTargetCB:SetPoint("TOPLEFT", 20, yOffset)
    noTargetCB.Text:SetText("Hide when no hostile target")
    noTargetCB:SetChecked(DebuffTrackerDB.hideWhenNoTarget)
    noTargetCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.hideWhenNoTarget = self:GetChecked()
        DebuffTracker:UpdateVisibility()
    end)
    
    yOffset = yOffset - 35
    
    -- Category header
    local catHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", 20, yOffset)
    catHeader:SetText("Tracked Debuff Categories:")
    
    yOffset = yOffset - 20
    
    -- Category checkboxes
    for _, category in ipairs(DEBUFF_CATEGORIES) do
        local cb = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 30, yOffset)
        cb.Text:SetText("|cFF" .. string.format("%02x%02x%02x", 
            category.color[1]*255, category.color[2]*255, category.color[3]*255) .. 
            category.name .. "|r")
        cb:SetChecked(DebuffTrackerDB.trackedCategories[category.name])
        cb:SetScript("OnClick", function(self)
            DebuffTrackerDB.trackedCategories[category.name] = self:GetChecked()
            DebuffTracker:UpdateFrameSize()
            DebuffTracker:UpdateDebuffs()
        end)
        
        yOffset = yOffset - 22
    end
    
    yOffset = yOffset - 15
    
    -- Reset position button
    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 22)
    resetBtn:SetPoint("BOTTOMLEFT", 20, 15)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        DebuffTrackerDB.frameX = nil
        DebuffTrackerDB.frameY = nil
        if trackerFrame then
            trackerFrame:ClearAllPoints()
            trackerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end
        DebuffTracker:Print("Tracker position reset")
    end)
    
    -- Test mode button
    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 22)
    testBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    testBtn:SetText("Test Display")
    testBtn:SetScript("OnClick", function()
        -- Temporarily show the tracker regardless of settings
        if trackerFrame then
            trackerFrame:Show()
            DebuffTracker:Print("Showing tracker for testing. Target a mob to see debuffs.")
        end
    end)
    
    mainFrame = frame
    self.mainFrame = frame
    
    return frame
end

function DebuffTracker:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function DebuffTracker:ToggleTracker()
    if not trackerFrame then
        self:CreateTrackerFrame()
    end
    
    DebuffTrackerDB.enabled = not DebuffTrackerDB.enabled
    self:UpdateVisibility()
    self:Print(DebuffTrackerDB.enabled and "Tracker enabled" or "Tracker disabled")
end
