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

-- ============================================
-- UI THEMES
-- ============================================

local THEMES = {
    ["Default"] = {
        -- Tracker frame
        tracker = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
            bgColor = { 0, 0, 0, 0.7 },
            borderColor = { 0.3, 0.3, 0.3, 1 },
        },
        -- Title bar
        titleBar = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            bgColor = { 0.1, 0.1, 0.1, 0.9 },
            height = 18,
            fontObject = "GameFontNormalSmall",
            fontColor = { 1, 0.8, 0, 1 },
        },
        -- Category indicators
        indicator = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            bgColor = { 0.2, 0.2, 0.2, 0.8 },
            borderColor = { 0.5, 0.5, 0.5, 1 },
            activeColor = { 0, 1, 0, 1 },      -- Green = debuff present
            warningColor = { 1, 1, 0, 1 },     -- Yellow = suboptimal
            missingColor = { 1, 0, 0, 1 },     -- Red = missing
            inactiveColor = { 0.5, 0.5, 0.5, 1 },
        },
        -- Settings panel
        settings = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            tileSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
            headerColor = { 1, 0.8, 0, 1 },
            separatorColor = { 0.4, 0.4, 0.4, 0.5 },
        },
    },
    ["ElvUI"] = {
        -- Tracker frame - Tukui pixel-perfect style
        tracker = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.92 },
            borderColor = { 0.15, 0.15, 0.15, 1 },
            -- Outer glow border (Tukui signature double-border)
            outerBorder = true,
            outerBorderColor = { 0, 0, 0, 1 },
            outerBorderSize = 1,
        },
        -- Title bar - very minimal
        titleBar = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            bgColor = { 0.1, 0.1, 0.1, 0.95 },
            height = 16,
            fontObject = "GameFontNormalSmall",
            fontColor = { 0.84, 0.75, 0.65, 1 },  -- Tukui's warm gold
            -- Bottom accent line
            accentLine = true,
            accentColor = { 0.18, 0.18, 0.18, 1 },
        },
        -- Category indicators - flat dark style
        indicator = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            bgColor = { 0.08, 0.08, 0.08, 0.9 },
            borderColor = { 0.18, 0.18, 0.18, 1 },
            activeColor = { 0.18, 0.78, 0.18, 1 },   -- Muted green
            warningColor = { 0.9, 0.8, 0.1, 1 },     -- Muted gold
            missingColor = { 0.78, 0.18, 0.18, 1 },   -- Muted red
            inactiveColor = { 0.25, 0.25, 0.25, 1 },
            -- Tukui inner shadow effect
            innerShadow = true,
        },
        -- Settings panel - dark flat panel
        settings = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            tileSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.95 },
            borderColor = { 0.15, 0.15, 0.15, 1 },
            headerColor = { 0.84, 0.75, 0.65, 1 },
            separatorColor = { 0.18, 0.18, 0.18, 0.8 },
            -- Outer border for the double-border look
            outerBorder = true,
            outerBorderColor = { 0, 0, 0, 1 },
        },
    },
}

local THEME_LIST = { "Default", "ElvUI" }

-- Helper: Get current theme table
local function GetTheme()
    local themeName = DebuffTrackerDB and DebuffTrackerDB.theme or "Default"
    return THEMES[themeName] or THEMES["Default"]
end

-- Helper: Create the Tukui-style outer border frame (pixel border effect)
local function CreateOuterBorder(parent, color)
    if parent._outerBorder then
        parent._outerBorder:Show()
        return parent._outerBorder
    end
    
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(math.max(parent:GetFrameLevel() - 1, 0))
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    local c = color or { 0, 0, 0, 1 }
    border:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    
    parent._outerBorder = border
    return border
end

-- Helper: Remove/hide outer border
local function RemoveOuterBorder(parent)
    if parent._outerBorder then
        parent._outerBorder:Hide()
    end
end

-- Helper: Create accent line under title bar (Tukui style)
local function CreateAccentLine(parent, color)
    if parent._accentLine then
        parent._accentLine:Show()
        local c = color or { 0.18, 0.18, 0.18, 1 }
        parent._accentLine:SetColorTexture(c[1], c[2], c[3], c[4])
        return parent._accentLine
    end
    
    local line = parent:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local c = color or { 0.18, 0.18, 0.18, 1 }
    line:SetColorTexture(c[1], c[2], c[3], c[4])
    
    parent._accentLine = line
    return line
end

-- Helper: Remove/hide accent line
local function RemoveAccentLine(parent)
    if parent._accentLine then
        parent._accentLine:Hide()
    end
end

-- Default settings
local defaults = {
    enabled = true,
    locked = false,
    showOnlyInRaid = true,
    showOnlyOnBoss = false,
    trackedCategories = {},  -- Will be populated with all categories enabled
    trackedDebuffs = {},     -- Per-debuff enable/disable: trackedDebuffs["Armor"]["Sunder Armor"] = true/false
    theme = "Default",
    scale = 1.0,
    alpha = 1.0,
    frameX = nil,
    frameY = nil,
    compactMode = false,
    hideWhenNoTarget = true,
}

-- Initialize tracked categories and per-debuff defaults (all enabled)
for _, cat in ipairs(DEBUFF_CATEGORIES) do
    defaults.trackedCategories[cat.name] = true
    defaults.trackedDebuffs[cat.name] = {}
    for _, debuff in ipairs(cat.debuffs) do
        defaults.trackedDebuffs[cat.name][debuff.name] = true
    end
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
                    if type(v2) == "table" then
                        DebuffTrackerDB[key][k2] = {}
                        for k3, v3 in pairs(v2) do
                            DebuffTrackerDB[key][k2][k3] = v3
                        end
                    else
                        DebuffTrackerDB[key][k2] = v2
                    end
                end
            else
                DebuffTrackerDB[key] = value
            end
        end
    end
    -- Ensure all categories and debuffs exist in trackedDebuffs (handles addon updates adding new debuffs)
    if not DebuffTrackerDB.trackedDebuffs then
        DebuffTrackerDB.trackedDebuffs = {}
    end
    for _, cat in ipairs(DEBUFF_CATEGORIES) do
        if not DebuffTrackerDB.trackedDebuffs[cat.name] then
            DebuffTrackerDB.trackedDebuffs[cat.name] = {}
        end
        for _, debuff in ipairs(cat.debuffs) do
            if DebuffTrackerDB.trackedDebuffs[cat.name][debuff.name] == nil then
                DebuffTrackerDB.trackedDebuffs[cat.name][debuff.name] = true
            end
        end
    end
    
    -- Auto-detect ElvUI / Tukui on first run (only if theme hasn't been explicitly set yet)
    if not DebuffTrackerDB._themeInitialized then
        if IsAddOnLoaded and (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
            DebuffTrackerDB.theme = "ElvUI"
            self:Print("ElvUI/Tukui detected - auto-selected ElvUI theme")
        elseif C_AddOns and C_AddOns.IsAddOnLoaded and (C_AddOns.IsAddOnLoaded("ElvUI") or C_AddOns.IsAddOnLoaded("Tukui")) then
            DebuffTrackerDB.theme = "ElvUI"
            self:Print("ElvUI/Tukui detected - auto-selected ElvUI theme")
        end
        DebuffTrackerDB._themeInitialized = true
    end
    
    -- Validate saved theme still exists
    if not THEMES[DebuffTrackerDB.theme] then
        DebuffTrackerDB.theme = "Default"
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
    
    -- Get the per-debuff enable/disable table for this category
    local debuffToggles = DebuffTrackerDB and DebuffTrackerDB.trackedDebuffs and DebuffTrackerDB.trackedDebuffs[category.name]
    
    for i = 1, 40 do
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, 
              nameplateShowPersonal, spellId = UnitDebuff(unit, i)
        
        if not name then break end
        
        -- Check against category debuffs
        for _, debuff in ipairs(category.debuffs) do
            -- Skip if this specific debuff is disabled in options
            if not debuffToggles or debuffToggles[debuff.name] ~= false then
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
    end
    
    return bestDebuff
end

-- Get the best possible debuff in a category (only among enabled debuffs)
local function GetBestDebuff(category)
    local best = nil
    local bestPriority = 0
    local debuffToggles = DebuffTrackerDB and DebuffTrackerDB.trackedDebuffs and DebuffTrackerDB.trackedDebuffs[category.name]
    
    for _, debuff in ipairs(category.debuffs) do
        -- Skip if this specific debuff is disabled in options
        if not debuffToggles or debuffToggles[debuff.name] ~= false then
            if debuff.priority > bestPriority then
                best = debuff
                bestPriority = debuff.priority
            end
        end
    end
    return best
end

-- ============================================
-- THEME APPLICATION
-- ============================================

function DebuffTracker:ApplyTrackerTheme()
    if not trackerFrame then return end
    local theme = GetTheme()
    local t = theme.tracker
    local tt = theme.titleBar
    
    -- Main tracker frame
    trackerFrame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = 16, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    trackerFrame:SetBackdropColor(unpack(t.bgColor))
    trackerFrame:SetBackdropBorderColor(unpack(t.borderColor))
    
    -- Outer border (Tukui double-border)
    if t.outerBorder then
        CreateOuterBorder(trackerFrame, t.outerBorderColor)
    else
        RemoveOuterBorder(trackerFrame)
    end
    
    -- Title bar
    trackerFrame.titleBar:SetBackdrop({
        bgFile = tt.bgFile,
    })
    trackerFrame.titleBar:SetBackdropColor(unpack(tt.bgColor))
    trackerFrame.titleBar:SetHeight(tt.height)
    trackerFrame.title:SetFontObject(tt.fontObject)
    trackerFrame.title:SetTextColor(unpack(tt.fontColor))
    
    -- Accent line
    if tt.accentLine then
        CreateAccentLine(trackerFrame.titleBar, tt.accentColor)
    else
        RemoveAccentLine(trackerFrame.titleBar)
    end
    
    -- Apply to category indicators
    self:ApplyCategoryTheme()
end

function DebuffTracker:ApplyCategoryTheme()
    local theme = GetTheme()
    local ti = theme.indicator
    
    for _, catFrame in ipairs(categoryFrames) do
        catFrame:SetBackdrop({
            bgFile = ti.bgFile,
            edgeFile = ti.edgeFile,
            edgeSize = ti.edgeSize,
        })
        catFrame:SetBackdropColor(unpack(ti.bgColor))
        -- Border color will be set by UpdateDebuffs based on state
        catFrame:SetBackdropBorderColor(unpack(ti.inactiveColor))
    end
end

function DebuffTracker:ApplySettingsTheme()
    if not mainFrame then return end
    local theme = GetTheme()
    local ts = theme.settings
    
    mainFrame:SetBackdrop({
        bgFile = ts.bgFile,
        edgeFile = ts.edgeFile,
        tile = true, tileSize = ts.tileSize, edgeSize = ts.edgeSize,
        insets = ts.insets,
    })
    
    if ts.bgColor then
        mainFrame:SetBackdropColor(unpack(ts.bgColor))
    end
    if ts.borderColor then
        mainFrame:SetBackdropBorderColor(unpack(ts.borderColor))
    end
    
    -- Outer border for settings
    if ts.outerBorder then
        CreateOuterBorder(mainFrame, ts.outerBorderColor)
    else
        RemoveOuterBorder(mainFrame)
    end
end

function DebuffTracker:ApplyTheme()
    self:ApplyTrackerTheme()
    self:ApplySettingsTheme()
    self:UpdateDebuffs()  -- Re-apply state colors with new theme
end

-- ============================================
-- TRACKER FRAME
-- ============================================

function DebuffTracker:CreateTrackerFrame()
    if trackerFrame then return trackerFrame end
    
    local theme = GetTheme()
    local t = theme.tracker
    local tt = theme.titleBar
    
    local frame = CreateFrame("Frame", "WM_DebuffTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(200, 30)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetFrameStrata("HIGH")
    
    frame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = 16, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    frame:SetBackdropColor(unpack(t.bgColor))
    frame:SetBackdropBorderColor(unpack(t.borderColor))
    
    -- Outer border (Tukui double-border effect)
    if t.outerBorder then
        CreateOuterBorder(frame, t.outerBorderColor)
    end
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(tt.height)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({
        bgFile = tt.bgFile,
    })
    titleBar:SetBackdropColor(unpack(tt.bgColor))
    frame.titleBar = titleBar
    
    local title = titleBar:CreateFontString(nil, "OVERLAY", tt.fontObject)
    title:SetPoint("LEFT", 5, 0)
    title:SetText("Debuffs")
    title:SetTextColor(unpack(tt.fontColor))
    frame.title = title
    
    -- Accent line (Tukui style)
    if tt.accentLine then
        CreateAccentLine(titleBar, tt.accentColor)
    end
    
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
    
    local theme = GetTheme()
    local ti = theme.indicator
    
    local xOffset = 0
    local yOffset = 0
    local indicatorSize = 24
    local spacing = 3
    local maxWidth = 180
    
    for i, category in ipairs(DEBUFF_CATEGORIES) do
        local catFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
        catFrame:SetSize(indicatorSize, indicatorSize)
        catFrame:SetBackdrop({
            bgFile = ti.bgFile,
            edgeFile = ti.edgeFile,
            edgeSize = ti.edgeSize,
        })
        catFrame:SetBackdropColor(unpack(ti.bgColor))
        catFrame:SetBackdropBorderColor(unpack(ti.inactiveColor))
        
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
            
            -- List possible debuffs with enabled/disabled status
            GameTooltip:AddLine("Debuffs (priority order):", 1, 1, 1)
            local sorted = {}
            for _, d in ipairs(category.debuffs) do
                table.insert(sorted, d)
            end
            table.sort(sorted, function(a, b) return a.priority > b.priority end)
            local debuffToggles = DebuffTrackerDB and DebuffTrackerDB.trackedDebuffs and DebuffTrackerDB.trackedDebuffs[category.name]
            for _, d in ipairs(sorted) do
                local isEnabled = not debuffToggles or debuffToggles[d.name] ~= false
                local classColor = RAID_CLASS_COLORS[d.class] or {r=1, g=1, b=1}
                local prefix = isEnabled and "|cFF00FF00[ON]|r " or "|cFF666666[OFF]|r "
                if isEnabled then
                    GameTooltip:AddLine(prefix .. d.name .. " (" .. d.class .. ")", classColor.r, classColor.g, classColor.b)
                else
                    GameTooltip:AddLine(prefix .. d.name .. " (" .. d.class .. ")", 0.4, 0.4, 0.4)
                end
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
    
    local theme = GetTheme()
    local ti = theme.indicator
    
    local unit = "target"
    if not UnitExists(unit) or not UnitCanAttack("player", unit) then
        -- Clear all indicators
        for _, catFrame in ipairs(categoryFrames) do
            catFrame:SetBackdropBorderColor(unpack(ti.inactiveColor))
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
                catFrame:SetBackdropBorderColor(unpack(ti.activeColor))
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
                    -- Not optimal
                    catFrame:SetBackdropBorderColor(unpack(ti.warningColor))
                end
            else
                -- Debuff missing
                local best = GetBestDebuff(category)
                if best then
                    -- Show what should be there (greyed out)
                    catFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                catFrame:SetBackdropBorderColor(unpack(ti.missingColor))
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
        local catCount = 0
        local debuffCount = 0
        local totalDebuffs = 0
        for _, cat in ipairs(DEBUFF_CATEGORIES) do
            if DebuffTrackerDB.trackedCategories[cat.name] then
                catCount = catCount + 1
                for _, debuff in ipairs(cat.debuffs) do
                    totalDebuffs = totalDebuffs + 1
                    if DebuffTrackerDB.trackedDebuffs[cat.name] and 
                       DebuffTrackerDB.trackedDebuffs[cat.name][debuff.name] ~= false then
                        debuffCount = debuffCount + 1
                    end
                end
            end
        end
        return "|cFF00FF00Active|r (" .. catCount .. " categories, " .. debuffCount .. "/" .. totalDebuffs .. " debuffs)"
    else
        return "|cFFFF0000Disabled|r"
    end
end

-- ============================================
-- SETTINGS UI
-- ============================================

function DebuffTracker:CreateUI()
    if mainFrame then return mainFrame end
    
    local theme = GetTheme()
    local ts = theme.settings
    
    local frame = CreateFrame("Frame", "WM_DebuffTrackerSettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(380, 560)
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
        bgFile = ts.bgFile,
        edgeFile = ts.edgeFile,
        tile = true, tileSize = ts.tileSize, edgeSize = ts.edgeSize,
        insets = ts.insets,
    })
    if ts.bgColor then frame:SetBackdropColor(unpack(ts.bgColor)) end
    if ts.borderColor then frame:SetBackdropBorderColor(unpack(ts.borderColor)) end
    if ts.outerBorder then CreateOuterBorder(frame, ts.outerBorderColor) end
    
    -- Title
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -15)
    titleText:SetText("Debuff Tracker Settings")
    titleText:SetTextColor(unpack(ts.headerColor))
    
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
    
    yOffset = yOffset - 30
    
    -- Theme selector
    local themeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", 20, yOffset)
    themeLabel:SetText("UI Theme:")
    themeLabel:SetTextColor(unpack(ts.headerColor))
    
    -- Dropdown button (manual implementation - no UIDropDownMenu dependency)
    local themeDropdown = CreateFrame("Frame", "WM_DebuffTrackerThemeDropdown", frame, "BackdropTemplate")
    themeDropdown:SetSize(150, 22)
    themeDropdown:SetPoint("LEFT", themeLabel, "RIGHT", 10, 0)
    themeDropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    themeDropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    themeDropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local themeText = themeDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    themeText:SetPoint("LEFT", 8, 0)
    themeText:SetText(DebuffTrackerDB.theme or "Default")
    
    local themeArrow = themeDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    themeArrow:SetPoint("RIGHT", -6, 0)
    themeArrow:SetText("v")
    
    -- Dropdown menu frame
    local themeMenu = CreateFrame("Frame", "WM_DebuffTrackerThemeMenu", themeDropdown, "BackdropTemplate")
    themeMenu:SetPoint("TOPLEFT", themeDropdown, "BOTTOMLEFT", 0, -2)
    themeMenu:SetSize(150, (#THEME_LIST * 20) + 6)
    themeMenu:SetFrameStrata("TOOLTIP")
    themeMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    themeMenu:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    themeMenu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    themeMenu:Hide()
    
    for idx, themeName in ipairs(THEME_LIST) do
        local item = CreateFrame("Button", nil, themeMenu)
        item:SetSize(146, 18)
        item:SetPoint("TOPLEFT", 2, -((idx - 1) * 20) - 3)
        
        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", 6, 0)
        itemText:SetText(themeName)
        
        local itemHighlight = item:CreateTexture(nil, "HIGHLIGHT")
        itemHighlight:SetAllPoints()
        itemHighlight:SetColorTexture(0.3, 0.3, 0.5, 0.3)
        
        item:SetScript("OnClick", function()
            DebuffTrackerDB.theme = themeName
            themeText:SetText(themeName)
            themeMenu:Hide()
            -- Destroy and recreate the settings frame with new theme
            -- (simpler than trying to re-skin every child element)
            mainFrame:Hide()
            mainFrame = nil
            DebuffTracker.mainFrame = nil
            DebuffTracker:ApplyTrackerTheme()
            DebuffTracker:UpdateDebuffs()
            DebuffTracker:Print("Theme changed to: " .. themeName .. ". Reopen settings to see themed panel.")
        end)
    end
    
    themeDropdown:EnableMouse(true)
    themeDropdown:SetScript("OnMouseDown", function()
        if themeMenu:IsShown() then
            themeMenu:Hide()
        else
            themeMenu:Show()
        end
    end)
    
    -- Close menu when clicking elsewhere
    themeMenu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
    frame:HookScript("OnHide", function()
        themeMenu:Hide()
    end)
    
    yOffset = yOffset - 32
    
    -- Category & Debuff Selection header
    local catHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", 20, yOffset)
    catHeader:SetText("Debuff Selection by Class:")
    catHeader:SetTextColor(unpack(ts.headerColor))
    
    yOffset = yOffset - 5
    
    -- Scroll frame for categories + debuffs
    local scrollFrame = CreateFrame("ScrollFrame", "WM_DebuffTrackerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, yOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)  -- Will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Build the category + debuff checkbox tree
    local scrollY = 0
    local debuffCheckboxes = {}  -- Store references so we can enable/disable them
    
    for _, category in ipairs(DEBUFF_CATEGORIES) do
        -- Category header checkbox
        local catCB = CreateFrame("CheckButton", nil, scrollChild, "InterfaceOptionsCheckButtonTemplate")
        catCB:SetPoint("TOPLEFT", 5, -scrollY)
        
        local colorHex = string.format("%02x%02x%02x", 
            category.color[1]*255, category.color[2]*255, category.color[3]*255)
        catCB.Text:SetText("|cFF" .. colorHex .. category.name .. "|r")
        catCB.Text:SetFontObject("GameFontNormal")
        catCB:SetChecked(DebuffTrackerDB.trackedCategories[category.name])
        
        -- Store debuff CBs for this category so we can grey them out
        debuffCheckboxes[category.name] = {}
        
        scrollY = scrollY + 24
        
        -- Group debuffs by class for display
        local classesSeen = {}
        local classOrder = {}
        for _, debuff in ipairs(category.debuffs) do
            if not classesSeen[debuff.class] then
                classesSeen[debuff.class] = {}
                table.insert(classOrder, debuff.class)
            end
            table.insert(classesSeen[debuff.class], debuff)
        end
        
        -- Create per-class debuff checkboxes
        for _, className in ipairs(classOrder) do
            local classDebuffs = classesSeen[className]
            local classColor = RAID_CLASS_COLORS[className] or {r=1, g=1, b=1}
            
            -- Class label
            local classLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            classLabel:SetPoint("TOPLEFT", 35, -scrollY)
            classLabel:SetText("|cFF" .. string.format("%02x%02x%02x", 
                classColor.r*255, classColor.g*255, classColor.b*255) .. className .. ":|r")
            
            scrollY = scrollY + 15
            
            for _, debuff in ipairs(classDebuffs) do
                local debuffCB = CreateFrame("CheckButton", nil, scrollChild, "InterfaceOptionsCheckButtonTemplate")
                debuffCB:SetPoint("TOPLEFT", 45, -scrollY)
                debuffCB:SetScale(0.85)
                debuffCB.Text:SetText(debuff.name .. " |cFF888888(P:" .. debuff.priority .. ")|r")
                debuffCB:SetChecked(DebuffTrackerDB.trackedDebuffs[category.name][debuff.name])
                
                -- Store reference
                table.insert(debuffCheckboxes[category.name], {
                    checkbox = debuffCB,
                    label = classLabel,
                    debuffName = debuff.name,
                })
                
                debuffCB:SetScript("OnClick", function(self)
                    DebuffTrackerDB.trackedDebuffs[category.name][debuff.name] = self:GetChecked()
                    DebuffTracker:UpdateDebuffs()
                end)
                
                -- Disable if category is unchecked
                if not DebuffTrackerDB.trackedCategories[category.name] then
                    debuffCB:Disable()
                    debuffCB:SetAlpha(0.4)
                end
                
                scrollY = scrollY + 20
            end
        end
        
        -- Enable All / Disable All buttons for this category
        local enableAllBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        enableAllBtn:SetSize(65, 16)
        enableAllBtn:SetPoint("TOPLEFT", 45, -scrollY)
        enableAllBtn:SetText("All On")
        enableAllBtn:GetFontString():SetFont(GameFontNormalSmall:GetFont())
        enableAllBtn:SetScript("OnClick", function()
            for _, entry in ipairs(debuffCheckboxes[category.name]) do
                entry.checkbox:SetChecked(true)
                DebuffTrackerDB.trackedDebuffs[category.name][entry.debuffName] = true
            end
            DebuffTracker:UpdateDebuffs()
        end)
        
        local disableAllBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        disableAllBtn:SetSize(65, 16)
        disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 5, 0)
        disableAllBtn:SetText("All Off")
        disableAllBtn:GetFontString():SetFont(GameFontNormalSmall:GetFont())
        disableAllBtn:SetScript("OnClick", function()
            for _, entry in ipairs(debuffCheckboxes[category.name]) do
                entry.checkbox:SetChecked(false)
                DebuffTrackerDB.trackedDebuffs[category.name][entry.debuffName] = false
            end
            DebuffTracker:UpdateDebuffs()
        end)
        
        -- Disable the enable/disable buttons if category is off
        if not DebuffTrackerDB.trackedCategories[category.name] then
            enableAllBtn:Disable()
            enableAllBtn:SetAlpha(0.4)
            disableAllBtn:Disable()
            disableAllBtn:SetAlpha(0.4)
        end
        
        -- Store button references for the category toggle
        debuffCheckboxes[category.name].enableAllBtn = enableAllBtn
        debuffCheckboxes[category.name].disableAllBtn = disableAllBtn
        
        scrollY = scrollY + 22
        
        -- Category checkbox OnClick - enable/disable all child checkboxes
        catCB:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            DebuffTrackerDB.trackedCategories[category.name] = checked
            for _, entry in ipairs(debuffCheckboxes[category.name]) do
                if checked then
                    entry.checkbox:Enable()
                    entry.checkbox:SetAlpha(1.0)
                else
                    entry.checkbox:Disable()
                    entry.checkbox:SetAlpha(0.4)
                end
            end
            if checked then
                debuffCheckboxes[category.name].enableAllBtn:Enable()
                debuffCheckboxes[category.name].enableAllBtn:SetAlpha(1.0)
                debuffCheckboxes[category.name].disableAllBtn:Enable()
                debuffCheckboxes[category.name].disableAllBtn:SetAlpha(1.0)
            else
                debuffCheckboxes[category.name].enableAllBtn:Disable()
                debuffCheckboxes[category.name].enableAllBtn:SetAlpha(0.4)
                debuffCheckboxes[category.name].disableAllBtn:Disable()
                debuffCheckboxes[category.name].disableAllBtn:SetAlpha(0.4)
            end
            DebuffTracker:UpdateFrameSize()
            DebuffTracker:UpdateDebuffs()
        end)
        
        -- Separator line
        local sep = scrollChild:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", 5, -scrollY)
        sep:SetPoint("TOPRIGHT", -5, -scrollY)
        sep:SetColorTexture(unpack(ts.separatorColor))
        
        scrollY = scrollY + 8
    end
    
    -- Set scroll child height
    scrollChild:SetHeight(scrollY + 10)
    
    -- Bottom buttons
    
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
