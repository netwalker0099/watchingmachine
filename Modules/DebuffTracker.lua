-- Watching Machine: Debuff Tracker Module
-- Tracks important raid debuffs on target with priority awareness

local AddonName, WM = ...
local DebuffTracker = {}
WM:RegisterModule("DebuffTracker", DebuffTracker)

DebuffTracker.version = "2.6"

-- ============================================
-- DEBUFF DEFINITIONS (TBC)
-- Priority: Higher number = better version of debuff
-- spec: Required talent spec (nil = any spec of that class)
-- ============================================

local DEBUFF_CATEGORIES = {
    -- Armor Reduction
    {
        name = "Armor",
        shortName = "Armor",
        color = {1, 0.5, 0},  -- Orange
        debuffs = {
            { name = "Improved Expose Armor", spellIDs = {26866}, priority = 100, class = "ROGUE", spec = "Combat" },
            { name = "Expose Armor", spellIDs = {26866, 11198, 8647, 8646}, priority = 90, class = "ROGUE" },
            { name = "Sunder Armor", spellIDs = {25225, 11597, 11596, 8380, 7405, 7386}, priority = 80, class = "WARRIOR" },
            { name = "Faerie Fire", spellIDs = {26993, 9907, 9749, 778, 770}, priority = 50, class = "DRUID", spec = "Balance" },
            { name = "Faerie Fire (Feral)", spellIDs = {27011, 17392, 17391, 16857}, priority = 50, class = "DRUID", spec = "Feral" },
        }
    },
    -- Physical Damage Increase
    {
        name = "Physical Dmg",
        shortName = "Phys%",
        color = {0.8, 0.2, 0.2},  -- Red
        debuffs = {
            { name = "Blood Frenzy", spellIDs = {29859, 29858}, priority = 100, class = "WARRIOR", spec = "Arms" },
        }
    },
    -- Shadow Damage
    {
        name = "Shadow Dmg",
        shortName = "Shadow",
        color = {0.5, 0, 0.8},  -- Purple
        debuffs = {
            { name = "Shadow Weaving", spellIDs = {15334, 15333, 15332, 15331, 15258}, priority = 100, class = "PRIEST", spec = "Shadow" },
            { name = "Curse of Elements", spellIDs = {27228, 11722, 11721, 1490}, priority = 90, class = "WARLOCK" },
        }
    },
    -- Spell Hit
    {
        name = "Spell Hit",
        shortName = "Hit",
        color = {0, 0.7, 1},  -- Cyan
        debuffs = {
            { name = "Misery", spellIDs = {33198, 33197, 33196, 33195, 33191}, priority = 100, class = "PRIEST", spec = "Shadow" },
        }
    },
    -- Fire Damage
    {
        name = "Fire Dmg",
        shortName = "Fire",
        color = {1, 0.4, 0},  -- Fire orange
        debuffs = {
            { name = "Improved Scorch", spellIDs = {12873, 12872, 12871, 12870, 12869}, priority = 100, class = "MAGE", spec = "Fire" },
            { name = "Curse of Elements", spellIDs = {27228, 11722, 11721, 1490}, priority = 90, class = "WARLOCK" },
        }
    },
    -- Attack Speed Reduction
    {
        name = "Attack Speed",
        shortName = "AtkSpd",
        color = {0.6, 0.6, 0.6},  -- Gray
        debuffs = {
            { name = "Improved Thunder Clap", spellIDs = {25264, 11581, 11580, 8198, 8204, 6343}, priority = 100, class = "WARRIOR", spec = "Arms" },
            { name = "Thunder Clap", spellIDs = {25264, 11581, 11580, 8198, 8204, 6343}, priority = 80, class = "WARRIOR" },
        }
    },
    -- Attack Power Reduction
    {
        name = "AP Reduction",
        shortName = "AP-",
        color = {0.4, 0.4, 0.8},  -- Blue-gray
        debuffs = {
            { name = "Demoralizing Shout", spellIDs = {25203, 11556, 11555, 6190, 5242, 1160}, priority = 100, class = "WARRIOR" },
            { name = "Demoralizing Roar", spellIDs = {27551, 9898, 9747, 9490, 1735, 99}, priority = 95, class = "DRUID", spec = "Feral" },
            { name = "Curse of Weakness", spellIDs = {27224, 11708, 11707, 7646, 6205, 702, 1108}, priority = 80, class = "WARLOCK" },
        }
    },
    -- Healing Reduction (optional — not auto-enabled, enable manually if needed)
    {
        name = "Healing Debuff",
        shortName = "Heal-",
        color = {0, 0.6, 0.3},  -- Green
        optional = true,         -- Auto-detect won't enable this; user must opt in
        debuffs = {
            { name = "Mortal Strike", spellIDs = {30330, 21553, 21552, 21551, 12294}, priority = 100, class = "WARRIOR", spec = "Arms" },
            { name = "Wound Poison", spellIDs = {27189, 13224, 13223, 13222, 13221, 13220, 13219, 13218}, priority = 80, class = "ROGUE" },
            { name = "Aimed Shot", spellIDs = {27065, 20904, 20903, 20902, 20901, 20900, 19434}, priority = 70, class = "HUNTER", spec = "Marksmanship" },
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
-- SPEC DETECTION via Raid Member Buffs (TBC)
-- ============================================
-- Map class -> list of { buffName, spec } that identify a talent spec.
-- We scan all raid members for these buffs to determine who is what spec.
-- If a spec can't be confirmed via buff, we mark it "unconfirmed" but
-- still allow it (conservative: don't hide debuffs we might actually have).

local SPEC_IDENTIFYING_BUFFS = {
    PRIEST = {
        { buff = "Shadowform", spec = "Shadow" },
        -- Holy/Disc have no persistent identifiable buff in TBC
    },
    DRUID = {
        { buff = "Moonkin Form", spec = "Balance" },
        { buff = "Moonkin Aura", spec = "Balance" },
        { buff = "Tree of Life", spec = "Restoration" },
        { buff = "Tree of Life Aura", spec = "Restoration" },
        { buff = "Leader of the Pack", spec = "Feral" },
    },
    HUNTER = {
        { buff = "Trueshot Aura", spec = "Marksmanship" },
        -- BM/Survival don't have persistent auras
    },
    -- Warrior, Mage, Rogue, Warlock: no reliable persistent buffs to detect spec
    -- For these, we assume "unconfirmed" and still allow the debuff
}

-- Specs that CAN be detected via buffs (if the class is present but spec not confirmed,
-- and the spec IS in this list, we know they're a different spec)
local DETECTABLE_SPECS = {
    PRIEST = { Shadow = true },              -- If priest has no Shadowform, they're NOT Shadow
    DRUID = { Balance = true, Feral = true, Restoration = true },  -- All druid specs detectable
    HUNTER = { Marksmanship = true },        -- If hunter has no Trueshot, they're NOT MM
}

-- ============================================
-- THEME HELPERS (uses global WM theme system)
-- ============================================

-- Local convenience wrapper
local function GetTheme()
    return WM:GetTheme()
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
    scale = 1.0,
    alpha = 1.0,
    frameX = nil,
    frameY = nil,
    compactMode = false,
    hideWhenNoTarget = true,
    autoDetect = true,       -- Auto-configure based on raid composition
    -- Raid alert settings
    raidAlerts = false,      -- Send raid messages for missing debuffs on boss
    alertDelay = 5,          -- Seconds a debuff must be missing before alerting
    alertCooldown = 30,      -- Seconds between repeat alerts for same category
    alertOnlyOnBoss = true,  -- Only alert for boss targets
    assistCanAnnounce = false, -- Allow raid assistants to announce (off to prevent duplicates)
    -- Pull announce settings
    pullAnnounce = false,        -- Announce who pulled the boss
    pullAnnounceChannel = "SAY", -- Channel: SAY, PARTY, RAID, RAID_WARNING
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
local raidClasses = {}       -- Set of classes currently in raid: raidClasses["WARRIOR"] = count
local raidSpecs = {}         -- Confirmed specs: raidSpecs["PRIEST"] = { ["Shadow"] = 1 }
local raidScanDirty = true   -- Flag to trigger rescan
local specScanTimer = 0      -- Throttle spec scanning (heavier than class scan)
local SPEC_SCAN_INTERVAL = 5 -- Scan specs every 5 seconds

-- Alert state
local missingTimers = {}     -- missingTimers["Armor"] = GetTime() when first noticed missing
local alertCooldowns = {}    -- alertCooldowns["Armor"] = GetTime() of last alert sent
local alertedThisPull = {}   -- alertedThisPull["Armor"] = true if already alerted this encounter
local deadCasterCache = {}   -- deadCasterCache["Armor"] = { alive=bool, time=GetTime() }
local DEAD_CASTER_CHECK_INTERVAL = 2  -- Re-check alive status every 2 seconds
local inCombat = false       -- Tracked via PLAYER_REGEN events
local bossEngaged = false    -- True when target boss is in combat (not just player)
local bossDeadGUID = nil     -- GUID of boss that died (suppress alerts until combat drop)

-- Pull detection state
local pullAnnounced = false      -- Already announced this pull
local trackedBossGUIDs = {}      -- GUIDs of bosses we've seen: trackedBossGUIDs[guid] = name
local pullDetectFrame = nil      -- Separate frame for combat log events

-- ============================================
-- RAID COMPOSITION + SPEC SCANNING
-- ============================================

-- Scan a single unit for spec-identifying buffs
local function DetectUnitSpec(unit, class)
    local specEntries = SPEC_IDENTIFYING_BUFFS[class]
    if not specEntries then return nil end
    
    for i = 1, 40 do
        local buffName = UnitBuff(unit, i)
        if not buffName then break end
        for _, entry in ipairs(specEntries) do
            if buffName == entry.buff then
                return entry.spec
            end
        end
    end
    return nil  -- Could not determine spec
end

-- Scan raid/party for all unique classes and detect specs
function DebuffTracker:ScanRaidComposition()
    local newClasses = {}
    local newSpecs = {}
    
    -- Helper to process a unit
    local function ProcessUnit(unit)
        if not UnitExists(unit) then return end
        local _, class = UnitClass(unit)
        if not class then return end
        
        newClasses[class] = (newClasses[class] or 0) + 1
        
        -- Detect spec via buffs
        local spec = DetectUnitSpec(unit, class)
        if spec then
            if not newSpecs[class] then newSpecs[class] = {} end
            newSpecs[class][spec] = (newSpecs[class][spec] or 0) + 1
        end
    end
    
    -- Always include player
    ProcessUnit("player")
    
    if IsInRaid() then
        for i = 1, 40 do
            ProcessUnit("raid" .. i)
        end
    elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
        for i = 1, 4 do
            ProcessUnit("party" .. i)
        end
    end
    
    -- Check if composition actually changed
    local changed = false
    for class, count in pairs(newClasses) do
        if raidClasses[class] ~= count then changed = true break end
    end
    if not changed then
        for class in pairs(raidClasses) do
            if not newClasses[class] then changed = true break end
        end
    end
    
    -- Check if specs changed
    if not changed then
        for class, specs in pairs(newSpecs) do
            if not raidSpecs[class] then changed = true break end
            for spec, count in pairs(specs) do
                if raidSpecs[class][spec] ~= count then changed = true break end
            end
            if changed then break end
        end
    end
    if not changed then
        for class, specs in pairs(raidSpecs) do
            if not newSpecs[class] then changed = true break end
            for spec in pairs(specs) do
                if not newSpecs[class][spec] then changed = true break end
            end
            if changed then break end
        end
    end
    
    if changed then
        raidClasses = newClasses
        raidSpecs = newSpecs
        if DebuffTrackerDB and DebuffTrackerDB.autoDetect then
            self:ApplyAutoDetect()
        end
    end
    
    raidScanDirty = false
end

-- Check if a specific class is in the raid
function DebuffTracker:IsClassInRaid(className)
    return raidClasses[className] and raidClasses[className] > 0
end

-- Check if a specific spec of a class is available in the raid
-- Returns: "confirmed", "unconfirmed", or "absent"
function DebuffTracker:GetSpecStatus(className, specName)
    if not specName then
        -- No spec required, just need the class
        return self:IsClassInRaid(className) and "confirmed" or "absent"
    end
    
    if not self:IsClassInRaid(className) then
        return "absent"
    end
    
    -- Check if we've confirmed this spec via buff scanning
    if raidSpecs[className] and raidSpecs[className][specName] and raidSpecs[className][specName] > 0 then
        return "confirmed"
    end
    
    -- Can we definitively say this spec is NOT present?
    -- Only if this class's specs are detectable and we scanned everyone
    local detectable = DETECTABLE_SPECS[className]
    if detectable and detectable[specName] then
        -- We CAN detect this spec via buffs. If we haven't seen it, it's absent.
        return "absent"
    end
    
    -- Spec is not detectable via buffs (warrior, mage, rogue, warlock specs)
    -- Class is present but we can't confirm the spec
    return "unconfirmed"
end

-- Check if a debuff is potentially available given raid comp + specs
-- Returns: "confirmed", "unconfirmed", or "absent"
function DebuffTracker:GetDebuffAvailability(debuff)
    return self:GetSpecStatus(debuff.class, debuff.spec)
end

-- Check if any debuff in a category can be provided by the current raid (spec-aware)
function DebuffTracker:IsCategoryCoverable(category)
    for _, debuff in ipairs(category.debuffs) do
        local status = self:GetDebuffAvailability(debuff)
        if status == "confirmed" or status == "unconfirmed" then
            return true
        end
    end
    return false
end

-- Check if at least one ALIVE raid member can cast a debuff in this category
-- Used mid-combat to suppress alerts when all casters are dead
function DebuffTracker:HasAliveCaster(category)
    if not category or not category.debuffs then return false end
    
    -- Build set of class+spec combos that can provide this debuff
    local neededClasses = {}  -- neededClasses["WARRIOR"] = { [nil]=true } or { ["Arms"]=true }
    local debuffToggles = DebuffTrackerDB and DebuffTrackerDB.trackedDebuffs[category.name]
    
    for _, debuff in ipairs(category.debuffs) do
        -- Only consider debuffs that are enabled in settings
        if not debuffToggles or debuffToggles[debuff.name] ~= false then
            if debuff.class then
                if not neededClasses[debuff.class] then
                    neededClasses[debuff.class] = {}
                end
                -- nil spec means any spec of that class can do it
                neededClasses[debuff.class][debuff.spec or "ANY"] = true
            end
        end
    end
    
    -- No classes needed (shouldn't happen, but guard)
    if not next(neededClasses) then return false end
    
    -- Scan raid for alive members matching those classes
    local function CheckUnit(unit)
        if not UnitExists(unit) then return false end
        if UnitIsDead(unit) or UnitIsGhost(unit) then return false end
        
        local _, class = UnitClass(unit)
        if not class then return false end
        
        local specs = neededClasses[class]
        if not specs then return false end
        
        -- If any entry allows ANY spec, this alive member qualifies
        if specs["ANY"] then return true end
        
        -- Need a specific spec — check if this unit has it
        local unitSpec = DetectUnitSpec(unit, class)
        if unitSpec and specs[unitSpec] then
            return true
        end
        
        -- Can't confirm spec but class matches — if spec detection isn't
        -- possible for this class, give benefit of the doubt
        if not unitSpec then
            local detectable = DETECTABLE_SPECS[class]
            for specName in pairs(specs) do
                if specName ~= "ANY" and (not detectable or not detectable[specName]) then
                    -- Can't detect this spec via buffs, class is alive, assume possible
                    return true
                end
            end
        end
        
        return false
    end
    
    -- Check player
    if CheckUnit("player") then return true end
    
    -- Check group
    if IsInRaid() then
        for i = 1, 40 do
            if CheckUnit("raid" .. i) then return true end
        end
    elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
        for i = 1, 4 do
            if CheckUnit("party" .. i) then return true end
        end
    end
    
    return false
end

-- Apply auto-detection: enable categories/debuffs based on raid composition + specs
function DebuffTracker:ApplyAutoDetect()
    if not DebuffTrackerDB or not DebuffTrackerDB.autoDetect then return end
    
    local changed = false
    
    for _, category in ipairs(DEBUFF_CATEGORIES) do
        local hasCoverage = self:IsCategoryCoverable(category)
        local skipDebuffs = false
        
        -- Optional categories (e.g. Healing Debuff) are never auto-enabled.
        -- If the user manually enabled one, still auto-configure its individual debuffs.
        if category.optional then
            if not DebuffTrackerDB.trackedCategories[category.name] then
                -- User hasn't enabled it — skip entirely
                skipDebuffs = true
            end
            -- Don't touch the category toggle — leave it as the user set it
        else
            -- Auto-enable/disable the category
            if DebuffTrackerDB.trackedCategories[category.name] ~= hasCoverage then
                DebuffTrackerDB.trackedCategories[category.name] = hasCoverage
                changed = true
            end
        end
        
        -- Within category, enable debuffs whose class+spec is available, disable others
        if not skipDebuffs then
        if not DebuffTrackerDB.trackedDebuffs[category.name] then
            DebuffTrackerDB.trackedDebuffs[category.name] = {}
        end
        for _, debuff in ipairs(category.debuffs) do
            local status = self:GetDebuffAvailability(debuff)
            local shouldEnable = (status == "confirmed" or status == "unconfirmed")
            if DebuffTrackerDB.trackedDebuffs[category.name][debuff.name] ~= shouldEnable then
                DebuffTrackerDB.trackedDebuffs[category.name][debuff.name] = shouldEnable
                changed = true
            end
        end
        end -- if not skipDebuffs
    end
    
    if changed then
        self:UpdateFrameSize()
        self:UpdateDebuffs()
        -- Refresh settings UI if open
        if mainFrame and mainFrame:IsShown() then
            self:RefreshSettingsUI()
        end
    end
end

-- Get a summary string of detected classes + specs
function DebuffTracker:GetRaidCompositionString()
    local parts = {}
    for class, count in pairs(raidClasses) do
        local color = RAID_CLASS_COLORS[class]
        local hex = color and string.format("%02x%02x%02x", color.r*255, color.g*255, color.b*255) or "ffffff"
        
        -- Append detected specs
        local specStr = ""
        if raidSpecs[class] then
            local specParts = {}
            for spec, scount in pairs(raidSpecs[class]) do
                table.insert(specParts, spec .. ":" .. scount)
            end
            if #specParts > 0 then
                specStr = " [" .. table.concat(specParts, ",") .. "]"
            end
        end
        
        table.insert(parts, "|cFF" .. hex .. class .. "|r(" .. count .. ")" .. specStr)
    end
    table.sort(parts)
    if #parts == 0 then return "None detected" end
    return table.concat(parts, ", ")
end


-- ============================================
-- MISSING DEBUFF RAID ALERTS
-- ============================================

-- Determine if this player should be the one announcing alerts to chat
-- Only ONE person should announce to avoid spam from multiple addon users.
-- Rule: Raid leader announces. If not in a raid, party leader announces.
-- Raid assistants can be given announce rights via a setting.
local function ShouldAnnounce()
    if not IsInRaid() then
        -- Party or solo: leader (or solo player) announces
        if not IsInGroup() then return true end
        return UnitIsGroupLeader("player")
    end
    
    -- In raid: leader always announces
    if UnitIsGroupLeader("player") then return true end
    
    -- Assistants: only announce if the setting allows it
    -- Default off to prevent duplicate alerts from multiple addon users
    if UnitIsGroupAssistant("player") then
        return DebuffTrackerDB and DebuffTrackerDB.assistCanAnnounce
    end
    
    -- Regular raid member: never announce to chat
    return false
end

function DebuffTracker:SendAlert(categoryName, debuffNames)
    local channel = nil
    local chatAnnounce = ShouldAnnounce()
    
    -- Build the alert message
    local msg = "[WM] Missing: " .. categoryName
    if debuffNames and debuffNames ~= "" then
        msg = msg .. " (" .. debuffNames .. ")"
    end
    
    -- Always show locally regardless of role
    self:Print("|cFFFF6600" .. msg .. "|r")
    
    -- Only send to chat if we're the designated announcer
    if not chatAnnounce then return end
    
    -- Determine best channel
    if IsInRaid() then
        -- Use RAID_WARNING if we have assist, otherwise RAID
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            channel = "RAID_WARNING"
        else
            channel = "RAID"
        end
    elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
        channel = "PARTY"
    end
    
    if not channel then return end
    
    pcall(SendChatMessage, msg, channel)
    alertCooldowns[categoryName] = GetTime()
end

-- Check if unit is a boss (TBC-compatible, no global IsBossUnit in Classic)
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

-- ============================================
-- BOSS PULL DETECTION
-- ============================================

-- Track a boss GUID from a unit (called when targeting a boss)
function DebuffTracker:TrackBossGUID(unit)
    if not unit or not UnitExists(unit) then return end
    if not IsBossUnit(unit) then return end
    if UnitIsDead(unit) then return end
    
    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    if guid and name then
        trackedBossGUIDs[guid] = name
    end
end

-- Check if a GUID belongs to a tracked boss
local function IsBossGUID(guid)
    return guid and trackedBossGUIDs[guid] ~= nil
end

-- Check if a GUID belongs to someone in our raid/party
local function IsInOurGroup(guid)
    if not guid then return false end
    -- Check player
    if guid == UnitGUID("player") then return true end
    -- Check raid
    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return true
            end
        end
    elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return true
            end
        end
    end
    return false
end

-- Subevents that indicate a player attacked/engaged a mob
local PULL_SUBEVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_CAST_SUCCESS = true,
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_APPLIED_DOSE = true,
    SPELL_INSTAKILL = true,
}

function DebuffTracker:ProcessPullDetection()
    if not DebuffTrackerDB or not DebuffTrackerDB.pullAnnounce then return end
    if pullAnnounced then return end
    if not inCombat then return end
    if not CombatLogGetCurrentEventInfo then return end
    
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
    
    if not subevent or not PULL_SUBEVENTS[subevent] then return end
    if not sourceGUID or not destGUID then return end
    
    -- Dest must be a tracked boss
    if not IsBossGUID(destGUID) then return end
    
    -- Source must be a player in our group
    if not sourceName then return end
    if not IsInOurGroup(sourceGUID) then return end
    
    -- This is the puller!
    pullAnnounced = true
    self:AnnouncePull(sourceName, trackedBossGUIDs[destGUID])
end

function DebuffTracker:AnnouncePull(pullerName, bossName)
    if not pullerName then return end
    
    local msg = "First hit: " .. pullerName
    if bossName then
        msg = msg .. " on " .. bossName
    end
    
    -- Local alert always
    self:Print("|cFFFF8800" .. msg .. "|r")
    
    -- Only the announcer sends to chat
    if not ShouldAnnounce() then return end
    
    local channel = DebuffTrackerDB.pullAnnounceChannel or "SAY"
    
    -- Validate channel
    if channel == "RAID_WARNING" then
        if not IsInRaid() then channel = "SAY"
        elseif not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
            channel = "RAID"
        end
    elseif channel == "RAID" then
        if not IsInRaid() then channel = "PARTY" end
    elseif channel == "PARTY" then
        if not IsInGroup() then channel = "SAY" end
    end
    
    pcall(SendChatMessage, msg, channel)
end

function DebuffTracker:RegisterPullDetection()
    if pullDetectFrame then return end
    
    pullDetectFrame = CreateFrame("Frame")
    pullDetectFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    pullDetectFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    pullDetectFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    pullDetectFrame:SetScript("OnEvent", function(self, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            pcall(DebuffTracker.ProcessPullDetection, DebuffTracker)
        elseif event == "PLAYER_TARGET_CHANGED" then
            pcall(DebuffTracker.TrackBossGUID, DebuffTracker, "target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            pcall(DebuffTracker.TrackBossGUID, DebuffTracker, "mouseover")
        end
    end)
end
function DebuffTracker:CheckAlerts(unit)
    if not DebuffTrackerDB or not DebuffTrackerDB.raidAlerts then return end
    if not IsInRaid() and not (GetNumGroupMembers and GetNumGroupMembers() > 0) then return end
    
    -- Gate 1: Player must be in combat
    if not inCombat then return end
    
    -- Gate 2: Boss must be dead-checked (suppress after kill)
    if bossDeadGUID then return end
    
    -- Gate 3: Target must exist and not be dead
    if not unit or not UnitExists(unit) then return end
    if UnitIsDead(unit) then
        -- Boss just died — mark as dead so we stop alerting for this encounter
        if IsBossUnit(unit) then
            bossDeadGUID = UnitGUID(unit)
        end
        return
    end
    
    -- Gate 4: Only alert on boss if setting is on
    if DebuffTrackerDB.alertOnlyOnBoss and not IsBossUnit(unit) then
        return
    end
    
    -- Gate 5: The TARGET must be in combat too (not just the player)
    -- This prevents alerts when you're fighting trash but targeting an unengaged boss
    if not UnitAffectingCombat(unit) then
        -- Boss not engaged yet — clear any started timers so they don't
        -- fire the instant the pull happens
        missingTimers = {}
        return
    end
    
    -- Mark boss as engaged (used to track encounter state)
    bossEngaged = true
    
    local now = GetTime()
    local delay = DebuffTrackerDB.alertDelay or 5
    local cooldown = DebuffTrackerDB.alertCooldown or 30
    
    for _, catFrame in ipairs(categoryFrames) do
        local category = catFrame.category
        if DebuffTrackerDB.trackedCategories[category.name] then
            if catFrame.currentDebuff then
                -- Debuff present - reset timer
                missingTimers[category.name] = nil
            else
                -- Debuff missing — check if anyone alive can even cast it
                local cached = deadCasterCache[category.name]
                local hasAlive
                if cached and (now - cached.time) < DEAD_CASTER_CHECK_INTERVAL then
                    hasAlive = cached.alive
                else
                    hasAlive = self:HasAliveCaster(category)
                    deadCasterCache[category.name] = { alive = hasAlive, time = now }
                end
                
                if not hasAlive then
                    -- All casters for this category are dead — suppress silently
                    missingTimers[category.name] = nil
                elseif alertedThisPull[category.name] then
                    -- Already sent an alert for this category this encounter
                    -- Don't re-alert; just keep the timer ticking silently
                elseif not missingTimers[category.name] then
                    -- Start timer
                    missingTimers[category.name] = now
                elseif (now - missingTimers[category.name]) >= delay then
                    -- Been missing long enough - check cooldown
                    if not alertCooldowns[category.name] or (now - alertCooldowns[category.name]) >= cooldown then
                        -- Build list of expected debuff names for the alert
                        local names = {}
                        local debuffToggles = DebuffTrackerDB.trackedDebuffs[category.name]
                        for _, debuff in ipairs(category.debuffs) do
                            if not debuffToggles or debuffToggles[debuff.name] ~= false then
                                table.insert(names, debuff.name)
                            end
                        end
                        self:SendAlert(category.name, table.concat(names, "/"))
                        -- Mark as alerted for this encounter — won't re-fire until combat drops
                        alertedThisPull[category.name] = true
                        missingTimers[category.name] = now
                    end
                end
            end
        end
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

function DebuffTracker:Initialize()
    self:InitDB()
    self:CreateTrackerFrame()
    self:RegisterPullDetection()
    -- Sync combat state (handles /reload mid-fight)
    inCombat = UnitAffectingCombat("player") or false
    -- Initial raid scan after a short delay (roster may not be ready yet)
    WM.RunAfter(2, function()
        DebuffTracker:ScanRaidComposition()
    end)
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
    -- Ensure autoDetect exists for existing installs
    if DebuffTrackerDB.autoDetect == nil then
        DebuffTrackerDB.autoDetect = true
    end
    -- Ensure alert settings exist for existing installs
    if DebuffTrackerDB.raidAlerts == nil then
        DebuffTrackerDB.raidAlerts = false
    end
    if DebuffTrackerDB.alertDelay == nil then
        DebuffTrackerDB.alertDelay = 5
    end
    if DebuffTrackerDB.alertCooldown == nil then
        DebuffTrackerDB.alertCooldown = 30
    end
    if DebuffTrackerDB.alertOnlyOnBoss == nil then
        DebuffTrackerDB.alertOnlyOnBoss = true
    end
    if DebuffTrackerDB.assistCanAnnounce == nil then
        DebuffTrackerDB.assistCanAnnounce = false
    end
    if DebuffTrackerDB.pullAnnounce == nil then
        DebuffTrackerDB.pullAnnounce = false
    end
    if DebuffTrackerDB.pullAnnounceChannel == nil then
        DebuffTrackerDB.pullAnnounceChannel = "SAY"
    end
    
    -- v2.3.1 migration: force-disable raid alerts once on upgrade.
    -- The alert system was overhauled (encounter-aware, dead caster suppression,
    -- leader-only coordination). Reset so users consciously re-enable it.
    if not DebuffTrackerDB.alertResetV26 then
        DebuffTrackerDB.raidAlerts = false
        DebuffTrackerDB.alertResetV26 = true
    end
end

-- ============================================
-- UTILITIES
-- ============================================

function DebuffTracker:Print(msg)
    WM:ModulePrint("DebuffTracker", msg)
end

function DebuffTracker:VerbosePrint(msg)
    WM:VerbosePrint("DebuffTracker", msg)
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
    local t = theme.panel  -- Use panel style for tracker frame
    local tt = theme.titleBar
    
    -- Main tracker frame
    trackerFrame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = t.tileSize or 16, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    if t.bgColor then trackerFrame:SetBackdropColor(unpack(t.bgColor)) end
    if t.borderColor then trackerFrame:SetBackdropBorderColor(unpack(t.borderColor)) end
    
    -- Outer border (Tukui double-border)
    if t.outerBorder then
        WM:CreateOuterBorder(trackerFrame, t.outerBorderColor)
    else
        WM:RemoveOuterBorder(trackerFrame)
    end
    
    -- Title bar
    trackerFrame.titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    trackerFrame.titleBar:SetBackdropColor(unpack(tt.bgColor))
    trackerFrame.titleBar:SetHeight(tt.height)
    trackerFrame.title:SetFontObject("GameFontNormalSmall")
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
        catFrame:SetBackdropBorderColor(unpack(ti.inactiveColor))
    end
end

function DebuffTracker:ApplySettingsTheme()
    if not mainFrame then return end
    WM:SkinPanel(mainFrame)
end

function DebuffTracker:ApplyTheme()
    self:ApplyTrackerTheme()
    self:ApplySettingsTheme()
    self:UpdateDebuffs()
end

-- ============================================
-- TRACKER FRAME
-- ============================================

function DebuffTracker:CreateTrackerFrame()
    if trackerFrame then return trackerFrame end
    
    local theme = GetTheme()
    local t = theme.panel
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
        tile = true, tileSize = t.tileSize or 16, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    if t.bgColor then frame:SetBackdropColor(unpack(t.bgColor)) end
    if t.borderColor then frame:SetBackdropBorderColor(unpack(t.borderColor)) end
    
    -- Outer border (Tukui double-border effect)
    if t.outerBorder then
        WM:CreateOuterBorder(frame, t.outerBorderColor)
    end
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetHeight(tt.height)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    titleBar:SetBackdropColor(unpack(tt.bgColor))
    frame.titleBar = titleBar
    
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
        specScanTimer = specScanTimer + elapsed
        
        if updateTimer >= UPDATE_INTERVAL then
            updateTimer = 0
            -- Process pending raid scan (class-level, fast)
            if raidScanDirty then
                DebuffTracker:ScanRaidComposition()
            end
            DebuffTracker:UpdateDebuffs()
        end
        
        -- Periodic spec scan (buff-based, slower interval)
        if specScanTimer >= SPEC_SCAN_INTERVAL then
            specScanTimer = 0
            DebuffTracker:ScanRaidComposition()  -- Also re-scans specs
        end
    end)
    
    -- Register events
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Enter combat
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leave combat
    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            -- Fresh encounter: reset all alert state
            missingTimers = {}
            alertCooldowns = {}
            alertedThisPull = {}
            deadCasterCache = {}
            bossEngaged = false
            bossDeadGUID = nil
            pullAnnounced = false
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            -- Clean slate for next pull
            missingTimers = {}
            alertCooldowns = {}
            alertedThisPull = {}
            deadCasterCache = {}
            bossEngaged = false
            bossDeadGUID = nil
            pullAnnounced = false
            trackedBossGUIDs = {}
            return
        end
        if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            raidScanDirty = true
        end
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
            
            -- List possible debuffs with enabled/disabled status and raid availability
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
                local availability = DebuffTracker:GetDebuffAvailability(d)
                
                local prefix
                if not isEnabled then
                    prefix = "|cFF666666[OFF]|r "
                elseif availability == "confirmed" then
                    prefix = "|cFF00FF00[OK]|r "
                elseif availability == "unconfirmed" then
                    prefix = "|cFFFFFF00[?]|r "
                else
                    prefix = "|cFFFF4444[NO]|r "
                end
                
                -- Build spec label
                local specLabel = d.spec and (" |cFFAAAAAA(" .. d.spec .. " " .. d.class .. ")|r") or (" |cFFAAAAAA(" .. d.class .. ")|r")
                
                if isEnabled and availability == "confirmed" then
                    GameTooltip:AddLine(prefix .. d.name .. specLabel, classColor.r, classColor.g, classColor.b)
                elseif isEnabled and availability == "unconfirmed" then
                    GameTooltip:AddLine(prefix .. d.name .. specLabel, 0.8, 0.8, 0.3)
                elseif isEnabled then
                    GameTooltip:AddLine(prefix .. d.name .. specLabel, 0.6, 0.3, 0.1)
                else
                    GameTooltip:AddLine(prefix .. d.name .. specLabel, 0.4, 0.4, 0.4)
                end
            end
            
            -- Show current status
            if self.currentDebuff then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Active: " .. self.currentDebuff.name, 0, 1, 0)
            elseif DebuffTracker:IsCategoryCoverable(category) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("MISSING!", 1, 0, 0)
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("No class in raid for this category", 0.5, 0.5, 0.5)
            end
            
            if DebuffTrackerDB.autoDetect then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Auto-detect: ON", 0.4, 0.8, 0.4)
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
        -- missingTimers persist across target switches so delay doesn't restart.
        -- alertedThisPull prevents re-firing for the entire encounter.
        return
    end
    
    -- Track boss GUIDs for pull detection
    self:TrackBossGUID(unit)
    
    -- Dead target: clear indicators, suppress alerts
    if UnitIsDead(unit) then
        for _, catFrame in ipairs(categoryFrames) do
            catFrame:SetBackdropBorderColor(unpack(ti.inactiveColor))
            catFrame.icon:SetTexture(nil)
            catFrame.status:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
            catFrame.stackText:SetText("")
            catFrame.currentDebuff = nil
        end
        -- Mark boss as dead so alerts don't fire even if retargeted
        if IsBossUnit(unit) then
            bossDeadGUID = UnitGUID(unit)
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
    
    -- Check for missing debuff alerts
    self:CheckAlerts(unit)
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
        local autoTag = DebuffTrackerDB.autoDetect and " |cFF88CCFF[Auto]|r" or ""
        local alertTag = DebuffTrackerDB.raidAlerts and " |cFFFFCC00[Alerts:" .. DebuffTrackerDB.alertDelay .. "s]|r" or ""
        return "|cFF00FF00Active|r (" .. catCount .. " categories, " .. debuffCount .. "/" .. totalDebuffs .. " debuffs)" .. autoTag .. alertTag
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
    
    local frame = CreateFrame("Frame", "WM_DebuffTrackerSettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 700)
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
    
    -- Title
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -15)
    titleText:SetText("Debuff Tracker Settings")
    titleText:SetTextColor(unpack(theme.headerColor))
    
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
    
    -- ========================================
    -- AUTO-DETECT SECTION
    -- ========================================
    
    local autoHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoHeader:SetPoint("TOPLEFT", 20, yOffset)
    autoHeader:SetText("Raid Auto-Detection:")
    autoHeader:SetTextColor(unpack(theme.headerColor))
    
    yOffset = yOffset - 22
    
    -- Auto-detect checkbox
    local autoCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    autoCB:SetPoint("TOPLEFT", 20, yOffset)
    autoCB.Text:SetText("Auto-configure from raid composition")
    autoCB:SetChecked(DebuffTrackerDB.autoDetect)
    frame.autoCB = autoCB
    
    yOffset = yOffset - 20
    
    -- Auto-detect description
    local autoDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoDesc:SetPoint("TOPLEFT", 40, yOffset)
    autoDesc:SetWidth(320)
    autoDesc:SetJustifyH("LEFT")
    autoDesc:SetText("|cFF888888Scans raid roster for classes. Only shows debuff categories that your raid can actually provide. Re-scans when roster changes.|r")
    frame.autoDesc = autoDesc
    
    yOffset = yOffset - 30
    
    -- Raid composition display
    local compLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compLabel:SetPoint("TOPLEFT", 25, yOffset)
    compLabel:SetText("Detected classes:")
    compLabel:SetTextColor(0.7, 0.7, 0.7)
    
    local compText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compText:SetPoint("TOPLEFT", 25, yOffset - 14)
    compText:SetWidth(280)
    compText:SetJustifyH("LEFT")
    compText:SetText(DebuffTracker:GetRaidCompositionString())
    frame.compText = compText
    
    -- Scan Now button
    local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanBtn:SetSize(70, 18)
    scanBtn:SetPoint("TOPRIGHT", -20, yOffset)
    scanBtn:SetText("Scan Now")
    scanBtn:SetScript("OnClick", function()
        DebuffTracker:ScanRaidComposition()
        if frame.compText then
            frame.compText:SetText(DebuffTracker:GetRaidCompositionString())
        end
        DebuffTracker:VerbosePrint("Raid scanned: " .. DebuffTracker:GetRaidCompositionString())
    end)
    frame.scanBtn = scanBtn
    
    yOffset = yOffset - 36
    
    -- Separator
    local autoSep = frame:CreateTexture(nil, "ARTWORK")
    autoSep:SetHeight(1)
    autoSep:SetPoint("TOPLEFT", 15, yOffset)
    autoSep:SetPoint("TOPRIGHT", -15, yOffset)
    autoSep:SetColorTexture(unpack(theme.separatorColor))
    
    yOffset = yOffset - 8
    
    -- ========================================
    -- RAID ALERT SECTION
    -- ========================================
    
    local alertHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alertHeader:SetPoint("TOPLEFT", 20, yOffset)
    alertHeader:SetText("Missing Debuff Alerts:")
    alertHeader:SetTextColor(unpack(theme.headerColor))
    
    yOffset = yOffset - 22
    
    -- Enable raid alerts checkbox
    local alertCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    alertCB:SetPoint("TOPLEFT", 20, yOffset)
    alertCB.Text:SetText("Send raid message when debuff missing")
    alertCB:SetChecked(DebuffTrackerDB.raidAlerts)
    alertCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.raidAlerts = self:GetChecked()
    end)
    
    yOffset = yOffset - 22
    
    -- Boss only checkbox
    local alertBossCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    alertBossCB:SetPoint("TOPLEFT", 35, yOffset)
    alertBossCB.Text:SetText("Only on boss targets")
    alertBossCB:SetChecked(DebuffTrackerDB.alertOnlyOnBoss)
    alertBossCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.alertOnlyOnBoss = self:GetChecked()
    end)
    
    -- Assist can announce checkbox (same row, right side)
    local assistCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    assistCB:SetPoint("TOPLEFT", 220, yOffset)
    assistCB.Text:SetText("Assistants can announce")
    assistCB:SetChecked(DebuffTrackerDB.assistCanAnnounce)
    assistCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.assistCanAnnounce = self:GetChecked()
    end)
    assistCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Assistant Announcements", 1, 0.8, 0)
        GameTooltip:AddLine("By default only the raid leader sends", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("missing debuff alerts to chat. Enable this", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("if the raid leader doesn't have the addon", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("and you want assistants to announce.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    assistCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 24
    
    -- Alert delay slider
    local delayLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delayLabel:SetPoint("TOPLEFT", 25, yOffset)
    delayLabel:SetText("Delay before alert:")
    
    local delayValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    delayValue:SetPoint("LEFT", delayLabel, "RIGHT", 5, 0)
    delayValue:SetText(DebuffTrackerDB.alertDelay .. "s")
    
    local delaySlider = CreateFrame("Slider", "WM_DebuffAlertDelaySlider", frame, "OptionsSliderTemplate")
    delaySlider:SetPoint("TOPLEFT", 25, yOffset - 18)
    delaySlider:SetSize(160, 16)
    delaySlider:SetMinMaxValues(2, 15)
    delaySlider:SetValueStep(1)
    delaySlider:SetObeyStepOnDrag(true)
    delaySlider:SetValue(DebuffTrackerDB.alertDelay)
    delaySlider.Low:SetText("2s")
    delaySlider.High:SetText("15s")
    delaySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        DebuffTrackerDB.alertDelay = value
        delayValue:SetText(value .. "s")
    end)
    
    -- Alert cooldown slider
    local cdLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdLabel:SetPoint("TOPLEFT", 200, yOffset)
    cdLabel:SetText("Cooldown between alerts:")
    
    local cdValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdValue:SetPoint("LEFT", cdLabel, "RIGHT", 5, 0)
    cdValue:SetText(DebuffTrackerDB.alertCooldown .. "s")
    
    local cdSlider = CreateFrame("Slider", "WM_DebuffAlertCDSlider", frame, "OptionsSliderTemplate")
    cdSlider:SetPoint("TOPLEFT", 200, yOffset - 18)
    cdSlider:SetSize(140, 16)
    cdSlider:SetMinMaxValues(10, 120)
    cdSlider:SetValueStep(5)
    cdSlider:SetObeyStepOnDrag(true)
    cdSlider:SetValue(DebuffTrackerDB.alertCooldown)
    cdSlider.Low:SetText("10s")
    cdSlider.High:SetText("120s")
    cdSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 5 + 0.5) * 5
        DebuffTrackerDB.alertCooldown = value
        cdValue:SetText(value .. "s")
    end)
    
    yOffset = yOffset - 40
    
    -- Alert description
    local alertDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alertDesc:SetPoint("TOPLEFT", 25, yOffset)
    alertDesc:SetWidth(340)
    alertDesc:SetJustifyH("LEFT")
    alertDesc:SetText("|cFF888888Uses /rw if you have assist, otherwise /raid. Only alerts for enabled categories.|r")
    
    yOffset = yOffset - 22
    
    -- ========================================
    -- PULL ANNOUNCE SECTION
    -- ========================================
    
    local pullCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    pullCB:SetPoint("TOPLEFT", 20, yOffset)
    pullCB.Text:SetText("Announce who pulled the boss")
    pullCB:SetChecked(DebuffTrackerDB.pullAnnounce)
    pullCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.pullAnnounce = self:GetChecked()
    end)
    pullCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pull Announce", 1, 0.8, 0)
        GameTooltip:AddLine("Detects the first player in your group to", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("hit a boss and announces it to chat.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Example: First hit: Playername on Gruul", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    pullCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Channel selector
    local chanLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chanLabel:SetPoint("TOPLEFT", 220, yOffset - 2)
    chanLabel:SetText("|cFF888888Channel:|r")
    
    local channels = { "SAY", "PARTY", "RAID", "RAID_WARNING" }
    local channelLabels = { SAY = "Say", PARTY = "Party", RAID = "Raid", RAID_WARNING = "/rw" }
    
    local currentChannel = DebuffTrackerDB.pullAnnounceChannel or "SAY"
    
    local chanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chanBtn:SetSize(55, 18)
    chanBtn:SetPoint("LEFT", chanLabel, "RIGHT", 5, 0)
    chanBtn:SetText(channelLabels[currentChannel] or currentChannel)
    chanBtn:SetScript("OnClick", function(self)
        -- Cycle through channels
        local cur = DebuffTrackerDB.pullAnnounceChannel or "SAY"
        local nextIdx = 1
        for i, ch in ipairs(channels) do
            if ch == cur then
                nextIdx = (i % #channels) + 1
                break
            end
        end
        DebuffTrackerDB.pullAnnounceChannel = channels[nextIdx]
        self:SetText(channelLabels[channels[nextIdx]] or channels[nextIdx])
    end)
    chanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Announce Channel", 1, 0.8, 0)
        GameTooltip:AddLine("Click to cycle: Say > Party > Raid > /rw", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("/rw falls back to Raid if no assist.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    chanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 22
    
    -- Separator
    local alertSep = frame:CreateTexture(nil, "ARTWORK")
    alertSep:SetHeight(1)
    alertSep:SetPoint("TOPLEFT", 15, yOffset)
    alertSep:SetPoint("TOPRIGHT", -15, yOffset)
    alertSep:SetColorTexture(unpack(theme.separatorColor))
    
    yOffset = yOffset - 8
    
    -- ========================================
    -- DEBUFF SELECTION SECTION
    -- ========================================
    
    -- Category & Debuff Selection header
    local catHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHeader:SetPoint("TOPLEFT", 20, yOffset)
    catHeader:SetText("Debuff Selection by Class:")
    catHeader:SetTextColor(unpack(theme.headerColor))
    
    local manualNote = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manualNote:SetPoint("LEFT", catHeader, "RIGHT", 8, 0)
    manualNote:SetText("")
    frame.manualNote = manualNote
    
    yOffset = yOffset - 5
    
    -- Scroll frame for categories + debuffs
    local scrollFrame = CreateFrame("ScrollFrame", "WM_DebuffTrackerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, yOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Build the category + debuff checkbox tree
    local scrollY = 0
    local debuffCheckboxes = {}
    
    for _, category in ipairs(DEBUFF_CATEGORIES) do
        local catCoverable = DebuffTracker:IsCategoryCoverable(category)
        
        -- Category header checkbox
        local catCB = CreateFrame("CheckButton", nil, scrollChild, "InterfaceOptionsCheckButtonTemplate")
        catCB:SetPoint("TOPLEFT", 5, -scrollY)
        
        local colorHex = string.format("%02x%02x%02x", 
            category.color[1]*255, category.color[2]*255, category.color[3]*255)
        
        -- Show coverage indicator in category name
        local coverageTag = ""
        if category.optional then
            coverageTag = " |cFFAAAA00(optional)|r"
        elseif DebuffTrackerDB.autoDetect then
            if catCoverable then
                coverageTag = " |cFF00FF00(available)|r"
            else
                coverageTag = " |cFF666666(no class in raid)|r"
            end
        end
        catCB.Text:SetText("|cFF" .. colorHex .. category.name .. "|r" .. coverageTag)
        catCB.Text:SetFontObject("GameFontNormal")
        catCB:SetChecked(DebuffTrackerDB.trackedCategories[category.name])
        
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
            local classInRaid = DebuffTracker:IsClassInRaid(className)
            
            -- Class label with raid presence and spec indicator
            local classLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            classLabel:SetPoint("TOPLEFT", 35, -scrollY)
            
            local raidTag = ""
            if DebuffTrackerDB.autoDetect then
                if classInRaid then
                    local specStr = ""
                    if raidSpecs[className] then
                        local specParts = {}
                        for spec, count in pairs(raidSpecs[className]) do
                            table.insert(specParts, spec)
                        end
                        if #specParts > 0 then
                            specStr = " - " .. table.concat(specParts, ", ")
                        end
                    end
                    raidTag = " |cFF00FF00(" .. (raidClasses[className] or 0) .. " in raid" .. specStr .. ")|r"
                else
                    raidTag = " |cFFFF4444(not in raid)|r"
                end
            end
            classLabel:SetText("|cFF" .. string.format("%02x%02x%02x", 
                classColor.r*255, classColor.g*255, classColor.b*255) .. className .. ":|r" .. raidTag)
            
            scrollY = scrollY + 18
            
            for _, debuff in ipairs(classDebuffs) do
                local wrapper = CreateFrame("Frame", nil, scrollChild)
                wrapper:SetSize(280, 22)
                wrapper:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 40, -scrollY)
                
                local debuffCB = CreateFrame("CheckButton", nil, wrapper, "InterfaceOptionsCheckButtonTemplate")
                debuffCB:SetPoint("LEFT", wrapper, "LEFT", 0, 0)
                debuffCB.Text:SetText(debuff.name .. (debuff.spec and " |cFFAAAACC[" .. debuff.spec .. "]|r" or "") .. " |cFF888888(P:" .. debuff.priority .. ")|r")
                debuffCB:SetChecked(DebuffTrackerDB.trackedDebuffs[category.name][debuff.name])
                
                table.insert(debuffCheckboxes[category.name], {
                    checkbox = debuffCB,
                    wrapper = wrapper,
                    label = classLabel,
                    debuffName = debuff.name,
                    className = className,
                })
                
                debuffCB:SetScript("OnClick", function(self)
                    DebuffTrackerDB.trackedDebuffs[category.name][debuff.name] = self:GetChecked()
                    DebuffTracker:UpdateDebuffs()
                end)
                
                -- Disable if category is unchecked OR auto-detect is on
                local catEnabled = DebuffTrackerDB.trackedCategories[category.name]
                if not catEnabled or DebuffTrackerDB.autoDetect then
                    debuffCB:Disable()
                    debuffCB:SetAlpha(0.4)
                end
                
                scrollY = scrollY + 24
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
        
        -- Disable buttons if category is off or auto-detect is on
        if not DebuffTrackerDB.trackedCategories[category.name] or DebuffTrackerDB.autoDetect then
            enableAllBtn:Disable()
            enableAllBtn:SetAlpha(0.4)
            disableAllBtn:Disable()
            disableAllBtn:SetAlpha(0.4)
        end
        
        debuffCheckboxes[category.name].enableAllBtn = enableAllBtn
        debuffCheckboxes[category.name].disableAllBtn = disableAllBtn
        
        scrollY = scrollY + 22
        
        -- Category checkbox OnClick
        catCB:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            DebuffTrackerDB.trackedCategories[category.name] = checked
            local canEdit = checked and not DebuffTrackerDB.autoDetect
            for _, entry in ipairs(debuffCheckboxes[category.name]) do
                if canEdit then
                    entry.checkbox:Enable()
                    entry.checkbox:SetAlpha(1.0)
                else
                    entry.checkbox:Disable()
                    entry.checkbox:SetAlpha(0.4)
                end
            end
            if canEdit then
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
        
        -- Disable category CB when auto-detect is on (except optional categories)
        if DebuffTrackerDB.autoDetect and not category.optional then
            catCB:Disable()
            catCB:SetAlpha(0.6)
        end
        
        -- Separator line
        local sep = scrollChild:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", 5, -scrollY)
        sep:SetPoint("TOPRIGHT", -5, -scrollY)
        sep:SetColorTexture(unpack(theme.separatorColor))
        
        scrollY = scrollY + 8
    end
    
    scrollChild:SetHeight(scrollY + 10)
    
    -- Store references for auto-detect toggle
    frame.debuffCheckboxes = debuffCheckboxes
    frame.scrollChild = scrollChild
    
    -- Auto-detect checkbox OnClick (defined after debuffCheckboxes exist)
    autoCB:SetScript("OnClick", function(self)
        DebuffTrackerDB.autoDetect = self:GetChecked()
        if DebuffTrackerDB.autoDetect then
            DebuffTracker:ScanRaidComposition()
            frame.manualNote:SetText("|cFF888888(auto-managed)|r")
        else
            frame.manualNote:SetText("")
        end
        -- Rebuild UI to reflect enable/disable state
        DebuffTracker:RefreshSettingsUI()
    end)
    
    -- Set initial manual note
    if DebuffTrackerDB.autoDetect then
        frame.manualNote:SetText("|cFF888888(auto-managed)|r")
    end
    
    -- Bottom buttons
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
    
    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(100, 22)
    testBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    testBtn:SetText("Test Display")
    testBtn:SetScript("OnClick", function()
        if trackerFrame then
            trackerFrame:Show()
            DebuffTracker:Print("Showing tracker for testing. Target a mob to see debuffs.")
        end
    end)
    
    mainFrame = frame
    self.mainFrame = frame
    
    return frame
end

-- Refresh the settings UI by destroying and recreating it
function DebuffTracker:RefreshSettingsUI()
    if mainFrame then
        local wasShown = mainFrame:IsShown()
        mainFrame:Hide()
        mainFrame:SetParent(nil)
        mainFrame = nil
        self.mainFrame = nil
        if wasShown then
            self:CreateUI()
            mainFrame:Show()
        end
    end
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
