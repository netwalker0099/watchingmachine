-- Watching Machine: Debuff Tracker Module
-- Tracks important raid debuffs on target with priority awareness

local AddonName, WM = ...
local DebuffTracker = {}
WM:RegisterModule("DebuffTracker", DebuffTracker)

DebuffTracker.version = "3.3"

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

-- Build per-category lookup tables once at load so the 5x/second target scan
-- does hash lookups instead of nested linear searches over every definition.
for _, cat in ipairs(DEBUFF_CATEGORIES) do
    cat.byName = {}
    cat.bySpellID = {}
    for _, debuff in ipairs(cat.debuffs) do
        cat.byName[debuff.name] = debuff
        for _, id in ipairs(debuff.spellIDs) do
            -- Multiple definitions can share a spellID (e.g. Improved Expose
            -- Armor vs Expose Armor) — keep a list to preserve priority rules
            if not cat.bySpellID[id] then
                cat.bySpellID[id] = {}
            end
            table.insert(cat.bySpellID[id], debuff)
        end
    end
end

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
    -- Encounter callouts
    illidanDoomWarning = true,   -- /rw "CAST DOOM NOW" when Illidan hits 68%
    -- Illidan Shear monitor
    shearMonitor = true,         -- Watch Illidan's Shear on the main tank
    shearChannel = "RAID",       -- LOCAL, SAY, PARTY, RAID, RAID_WARNING
    shearAnnounceAvoided = false,-- Also announce dodged/parried/blocked Shears
    shearPreWarn = false,        -- Local "Shear incoming..." on cast start
    shearThrottle = 0,           -- Min seconds between chat announcements (0 = every one)
    shearSummary = true,         -- Print a per-pull summary when combat ends
    -- Black Temple shadow resist gear check (post-Mother Shahraz)
    srCheck = true,              -- Warn if still wearing SR gear after Mother
    srCheckThreshold = 60,       -- Gear-only shadow resist that counts as "still on"
    srCheckChannel = "LOCAL",    -- LOCAL, SAY, PARTY, RAID, RAID_WARNING
    -- False-positive controls
    bossMinHealth = 150000,   -- Minimum max-HP for a mob to count as a boss (0 = off)
    focusTracking = true,     -- Only alert for the mob taking the most raid damage
    excludedNPCs = {},        -- [tostring(npcID)] = "Name" — never treated as a boss
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

-- Focus-target state (multi-boss encounters: Karathress, Illidari Council, ...)
-- The raid's real kill target is whichever hostile GUID is taking the most
-- group damage in a rolling window. This adapts to any kill order without
-- hardcoding, so alerts follow the raid instead of your current target.
local damageWindow = {}          -- guid -> { amount = n, last = GetTime(), name = str }
local FOCUS_WINDOW = 6           -- seconds of damage history that counts
local focusGUID = nil            -- current best kill-target GUID
local focusName = nil
local lastFocusEval = 0
local FOCUS_EVAL_INTERVAL = 1    -- recompute focus at most once per second

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

-- ============================================
-- MOB IDENTITY (NPC ID)
-- ============================================
-- TBC Classic creature GUIDs look like:
--   Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>
-- Field 6 is the npcID, which is stable and unique per creature type — the
-- only reliable way to tell apart mobs that SHARE A DISPLAY NAME (e.g.
-- Magtheridon's room channelers vs identically-named trash outside).
-- Names and levels can't distinguish those; npcIDs always can.

local function GetNPCID(guid)
    if not guid then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return tonumber(npcID)
end
DebuffTracker.GetNPCID = GetNPCID

-- Resolve a readable name for an npcID from what we've seen this session
local seenNPCNames = {}          -- npcID -> last seen name

function DebuffTracker:IsNPCExcluded(npcID)
    if not npcID or not DebuffTrackerDB then return false end
    local list = DebuffTrackerDB.excludedNPCs
    return list and list[tostring(npcID)] ~= nil
end

-- Check if unit is a boss (TBC-compatible, no global IsBossUnit in Classic)
--
-- Layered so trash can't slip through on the old "high level + elite"
-- heuristic alone, which flagged every level 72/73 elite raid trash mob
-- (Magtheridon's Hellfire Warders, SSC/TK trash) as a boss:
--   1. User exclusion list by npcID  -> never a boss
--   2. Health pool floor             -> trash filtered out regardless of level
--   3. Classification / level        -> original heuristic, now gated by (2)
local function IsBossUnit(unit)
    if not unit or not UnitExists(unit) then return false end
    if not UnitCanAttack("player", unit) then return false end

    -- (1) Explicit user exclusions win over everything
    local guid = UnitGUID(unit)
    local npcID = GetNPCID(guid)
    if npcID then
        seenNPCNames[npcID] = UnitName(unit) or seenNPCNames[npcID]
        if DebuffTracker:IsNPCExcluded(npcID) then
            return false
        end
    end

    local classification = UnitClassification(unit)
    local level = UnitLevel(unit)

    -- (2) Health-pool floor. TBC raid bosses and encounter adds carry
    -- hundreds of thousands of HP; raid trash is an order of magnitude
    -- lower even when it's the same level and elite.
    local minHealth = (DebuffTrackerDB and DebuffTrackerDB.bossMinHealth) or 150000
    if minHealth > 0 then
        local maxHP = UnitHealthMax(unit) or 0
        -- Health can read 0 briefly before the unit is fully known; don't
        -- reject in that case, fall through to the classification checks.
        if maxHP > 0 and maxHP < minHealth then
            return false
        end
    end

    -- (3) Classification / level heuristics
    if classification == "worldboss" or classification == "raidboss" then
        return true
    end

    if level == -1 or level == "??" then
        return true
    end

    if level and level >= 0 then
        local playerLevel = UnitLevel("player")
        if level >= playerLevel + 3 and classification == "elite" then
            return true
        end
    end

    return false
end

-- ============================================
-- FOCUS TARGET (adaptive kill-order detection)
-- ============================================
-- On multi-boss encounters (Fathom-Lord Karathress, Illidari Council, ...)
-- only one mob is actually being killed at a time. Rather than hardcoding a
-- kill order, we watch which hostile GUID is absorbing the most group damage
-- over a rolling window — that's the raid's real target, whatever strat is
-- being run. Alerts fire only for that mob, so targeting an ignored add
-- (Fathom-Guard Caribdis) no longer sets the alerts off.

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    DAMAGE_SHIELD = true,
    DAMAGE_SPLIT = true,
}

-- Record a damage event against a hostile GUID
local function RecordDamage(destGUID, destName, amount)
    if not destGUID or not amount or amount <= 0 then return end
    local now = GetTime()
    local entry = damageWindow[destGUID]
    if not entry or (now - entry.last) > FOCUS_WINDOW then
        -- Stale or new: start a fresh accumulation
        damageWindow[destGUID] = { amount = amount, last = now, name = destName }
    else
        entry.amount = entry.amount + amount
        entry.last = now
        entry.name = destName or entry.name
    end
end

-- Recompute which GUID the raid is actually killing
local function EvaluateFocus()
    local now = GetTime()
    if (now - lastFocusEval) < FOCUS_EVAL_INTERVAL then return end
    lastFocusEval = now

    local bestGUID, bestName, bestAmount = nil, nil, 0
    for guid, entry in pairs(damageWindow) do
        if (now - entry.last) > FOCUS_WINDOW then
            damageWindow[guid] = nil
        elseif entry.amount > bestAmount then
            bestGUID, bestName, bestAmount = guid, entry.name, entry.amount
        end
    end

    focusGUID = bestGUID
    focusName = bestName
end

function DebuffTracker:GetFocusInfo()
    return focusGUID, focusName
end

-- Is this unit the raid's current kill target?
-- Returns true when focus tracking is off, when no focus is established yet,
-- or when the unit IS the focus — i.e. it only ever suppresses alerts when
-- we're confident the raid is killing something else.
local function IsFocusTarget(unit)
    if not DebuffTrackerDB or not DebuffTrackerDB.focusTracking then return true end
    if not focusGUID then return true end

    local guid = UnitGUID(unit)
    if not guid then return true end
    if guid == focusGUID then return true end

    -- Focus exists and it isn't this unit. Only suppress if the focus is
    -- still actually being hit (stale focus shouldn't silence everything).
    local entry = damageWindow[focusGUID]
    if not entry or (GetTime() - entry.last) > FOCUS_WINDOW then
        return true
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

-- Cached set of group member GUIDs. The old implementation walked up to 40
-- raid units on every lookup; damage tracking calls this for every combat log
-- damage event, so it has to be a hash lookup.
local groupGUIDs = {}
local groupGUIDStamp = 0
local GROUP_GUID_TTL = 3

local function RefreshGroupGUIDs()
    wipe(groupGUIDs)
    local pguid = UnitGUID("player")
    if pguid then groupGUIDs[pguid] = true end

    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local g = UnitGUID(unit)
                if g then groupGUIDs[g] = true end
                -- Pets contribute raid damage too
                local pg = UnitGUID("raidpet" .. i)
                if pg then groupGUIDs[pg] = true end
            end
        end
    elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local g = UnitGUID(unit)
                if g then groupGUIDs[g] = true end
                local pg = UnitGUID("partypet" .. i)
                if pg then groupGUIDs[pg] = true end
            end
        end
    end
    local ownPet = UnitGUID("pet")
    if ownPet then groupGUIDs[ownPet] = true end

    groupGUIDStamp = GetTime()
end

-- Check if a GUID belongs to someone in our raid/party (or their pets)
local function IsInOurGroup(guid)
    if not guid then return false end
    if (GetTime() - groupGUIDStamp) > GROUP_GUID_TTL then
        RefreshGroupGUIDs()
    end
    return groupGUIDs[guid] == true
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

-- Single combat-log entry point: parses the event once and feeds both the
-- damage window (focus tracking) and pull detection.
function DebuffTracker:ProcessCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    if not inCombat then return end

    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _,
          p12, p13, p14, p15 = CombatLogGetCurrentEventInfo()

    if not subevent then return end

    -- Shear monitor runs first: cast events can arrive without a destination,
    -- so it must not be gated behind the destGUID guard below.
    if DebuffTrackerDB and DebuffTrackerDB.shearMonitor then
        pcall(self.HandleShearCombatLog, self, subevent, sourceGUID, destGUID, destName, p12, p13, p15)
    end

    -- Shadow resist gear check: arms on Mother's death, fires on engaging the
    -- Grand Promenade pulls. UNIT_DIED has no source, so it runs here too.
    if DebuffTrackerDB and DebuffTrackerDB.srCheck then
        pcall(self.HandleShadowResistCombatLog, self, subevent, sourceName, destName)
    end

    if not sourceGUID or not destGUID then return end

    -- --- Focus tracking: accumulate group damage per hostile GUID ---
    if DebuffTrackerDB and DebuffTrackerDB.focusTracking and DAMAGE_SUBEVENTS[subevent] then
        if IsInOurGroup(sourceGUID) and not IsInOurGroup(destGUID) then
            -- SWING_DAMAGE has no spell payload, so amount sits at 12;
            -- every other damage subevent puts spellId/name/school first.
            local amount = (subevent == "SWING_DAMAGE") and p12 or p15
            if type(amount) == "number" then
                RecordDamage(destGUID, destName, amount)
            end
        end
    end

    -- --- Pull detection ---
    if not DebuffTrackerDB or not DebuffTrackerDB.pullAnnounce then return end
    if pullAnnounced then return end
    if not PULL_SUBEVENTS[subevent] then return end
    if not IsBossGUID(destGUID) then return end
    if not sourceName then return end
    if not IsInOurGroup(sourceGUID) then return end

    pullAnnounced = true
    self:AnnouncePull(sourceName, trackedBossGUIDs[destGUID])
end

-- Back-compat alias (older call sites / user macros)
function DebuffTracker:ProcessPullDetection()
    return self:ProcessCombatLog()
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
    pullDetectFrame:RegisterEvent("UNIT_AURA")
    pullDetectFrame:SetScript("OnEvent", function(self, event, unitArg)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            pcall(DebuffTracker.ProcessCombatLog, DebuffTracker)
        elseif event == "PLAYER_TARGET_CHANGED" then
            pcall(DebuffTracker.TrackBossGUID, DebuffTracker, "target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            pcall(DebuffTracker.TrackBossGUID, DebuffTracker, "mouseover")
        elseif event == "UNIT_AURA" then
            -- Backup Shear detection; no-ops unless Illidan/Shear is live
            pcall(DebuffTracker.SweepShearAura, DebuffTracker, unitArg)
        end
    end)
end

-- ============================================
-- ILLIDAN DOOM WARNING
-- ============================================
-- Raid-warns "CAST DOOM NOW" when Illidan Stormrage drops to 68%. Curse of
-- Doom lands its 60s tick just as he lifts off at 65% for Phase 2. Fires once
-- per pull; only the designated announcer sends it (same rule as alerts).

local ILLIDAN_NPC_ID = 22917
local DOOM_THRESHOLD = 0.68
local DOOM_FLOOR = 0.60          -- below this the window has passed (e.g. /reload mid-fight)
local DOOM_MESSAGE = "CAST DOOM NOW"
local DOOM_POLL_INTERVAL = 0.25

local doomWarned = false
local doomFrame = nil
local doomUnits = { "boss1", "boss2", "boss3", "boss4", "boss5", "target", "focus", "mouseover" }
for i = 1, 40 do doomUnits[#doomUnits + 1] = "raid" .. i .. "target" end
for i = 1, 40 do doomUnits[#doomUnits + 1] = "nameplate" .. i end

-- Health fraction of Illidan from any unit token that currently points at him
local function FindIllidanHealth()
    for _, unit in ipairs(doomUnits) do
        local guid = UnitGUID(unit)
        if guid and GetNPCID(guid) == ILLIDAN_NPC_ID and not UnitIsDead(unit) then
            local maxHP = UnitHealthMax(unit) or 0
            if maxHP > 0 then
                return (UnitHealth(unit) or 0) / maxHP
            end
        end
    end
    return nil
end

function DebuffTracker:ResetDoomWarning()
    doomWarned = false
end

function DebuffTracker:CheckDoomWarning()
    if doomWarned or not inCombat then return end
    if not DebuffTrackerDB or not DebuffTrackerDB.illidanDoomWarning then return end
    if not IsInRaid() then return end

    local pct = FindIllidanHealth()
    if not pct or pct > DOOM_THRESHOLD then return end

    doomWarned = true
    if pct < DOOM_FLOOR then return end

    self:Print("|cFFFF2020" .. DOOM_MESSAGE .. "|r (Illidan at "
        .. math.floor(pct * 100 + 0.5) .. "%)")

    if not ShouldAnnounce() then return end
    local channel = (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
        and "RAID_WARNING" or "RAID"
    pcall(SendChatMessage, DOOM_MESSAGE, channel)
end

function DebuffTracker:RegisterDoomWarning()
    if doomFrame then return end
    doomFrame = CreateFrame("Frame")
    local elapsedSince = 0
    doomFrame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince < DOOM_POLL_INTERVAL then return end
        elapsedSince = 0
        pcall(DebuffTracker.CheckDoomWarning, DebuffTracker)
    end)
end

-- ============================================
-- ILLIDAN SHEAR MONITOR
-- ============================================
-- Shear is Illidan's main-tank ability during the ground phases (1/3/5): a
-- ~1.5s cast, roughly every 10s, that cuts the tank's maximum health by about
-- 60% for a few seconds. It cannot miss, but it CAN be dodged, parried or
-- blocked — which is why tanks stack avoidance for it.
--
-- Why it needs a dedicated monitor: damage meters record damage events. Shear's
-- bite is a max-health debuff, and an avoided Shear produces only a
-- SPELL_MISSED with no damage at all. Neither shows up reliably in Details!.
-- So we watch every subevent a Shear can produce, and additionally sweep raid
-- auras as a backup in case a combat-log event is dropped.

-- 41032 is Shear (confirmed on Wowhead). Only verified IDs belong here: an
-- unverified ID would silently misreport some other ability as a Shear, and
-- the name match below already catches any variant or separate debuff ID.
local SHEAR_SPELL_IDS = { [41032] = true }
local SHEAR_FALLBACK_NAME = "Shear"
local shearName = SHEAR_FALLBACK_NAME  -- replaced with the localized name at init

-- Subevents meaning the Shear connected
local SHEAR_LANDED_EVENTS = {
    SPELL_DAMAGE = true,
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_REFRESH = true,
}

local SHEAR_DEDUPE_WINDOW = 1.0  -- one announcement per cast, not per subevent

local shearArmed = false         -- a Shear or Illidan has been seen this pull
local shearLastResolve = {}      -- destGUID -> GetTime() of the last counted Shear
local shearLastAnnounce = 0
local shearStats, shearLastFight

local function NewShearStats()
    return { total = 0, landed = 0, avoided = 0, byOutcome = {}, byTank = {} }
end
shearStats = NewShearStats()

local function IsShearSpell(spellID, spellNameArg)
    if spellID and SHEAR_SPELL_IDS[spellID] then return true end
    if spellNameArg and (spellNameArg == shearName or spellNameArg == SHEAR_FALLBACK_NAME) then
        return true
    end
    return false
end

local function ShearOutcomeLabel(missType)
    if not missType then return "AVOIDED" end
    local m = tostring(missType):upper()
    if m == "DODGE"  then return "DODGED"   end
    if m == "PARRY"  then return "PARRIED"  end
    if m == "BLOCK"  then return "BLOCKED"  end
    if m == "MISS"   then return "MISSED"   end
    if m == "IMMUNE" then return "IMMUNE"   end
    if m == "ABSORB" then return "ABSORBED" end
    return m
end

function DebuffTracker:ResetShearMonitor(keepSnapshot)
    if keepSnapshot and shearStats and shearStats.total > 0 then
        shearLastFight = shearStats
    end
    shearArmed = false
    wipe(shearLastResolve)
    shearLastAnnounce = 0
    shearStats = NewShearStats()
end

function DebuffTracker:AnnounceShear(destName, outcome, isLanded)
    local who = destName or "the tank"
    local msg = isLanded and ("Shear HIT " .. who)
                          or ("Shear " .. outcome .. " by " .. who)

    -- Local line always, regardless of announce settings or announcer rules
    self:Print((isLanded and "|cFFFF4040" or "|cFF40FF40") .. msg .. "|r")

    if not isLanded and not DebuffTrackerDB.shearAnnounceAvoided then return end

    local channel = DebuffTrackerDB.shearChannel or "RAID"
    if channel == "LOCAL" then return end

    local throttle = DebuffTrackerDB.shearThrottle or 0
    local now = GetTime()
    if throttle > 0 and (now - shearLastAnnounce) < throttle then return end

    if not IsInGroup() and not IsInRaid() then return end
    -- Same announcer rule as the other callouts: only one person talks
    if not ShouldAnnounce() then return end

    if channel == "RAID_WARNING" then
        if not IsInRaid() then
            channel = "PARTY"
        elseif not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            channel = "RAID"
        end
    elseif channel == "RAID" then
        if not IsInRaid() then channel = "PARTY" end
    end

    shearLastAnnounce = now
    pcall(SendChatMessage, msg, channel)
end

-- Count and announce one Shear. Deduped per target so the several subevents a
-- single cast generates (cast success + aura + damage) only report once.
function DebuffTracker:ResolveShear(destGUID, destName, isLanded, outcome)
    local now = GetTime()
    local last = destGUID and shearLastResolve[destGUID]
    if last and (now - last) < SHEAR_DEDUPE_WINDOW then return end
    if destGUID then shearLastResolve[destGUID] = now end

    shearArmed = true
    shearStats.total = shearStats.total + 1
    if isLanded then
        shearStats.landed = shearStats.landed + 1
    else
        shearStats.avoided = shearStats.avoided + 1
    end

    local key = isLanded and "HIT" or outcome
    shearStats.byOutcome[key] = (shearStats.byOutcome[key] or 0) + 1

    if destName then
        local t = shearStats.byTank[destName]
        if not t then
            t = { hit = 0, avoided = 0 }
            shearStats.byTank[destName] = t
        end
        if isLanded then t.hit = t.hit + 1 else t.avoided = t.avoided + 1 end
    end

    self:AnnounceShear(destName, outcome, isLanded)
end

-- Combat-log path. Called for every event before the stricter guards in
-- ProcessCombatLog, because cast events can arrive without a destination.
function DebuffTracker:HandleShearCombatLog(subevent, sourceGUID, destGUID, destName, spellID, spellNameArg, p15)
    if not DebuffTrackerDB or not DebuffTrackerDB.shearMonitor then return end
    if not IsShearSpell(spellID, spellNameArg) then return end
    -- Must come from something hostile, never from one of our own
    if sourceGUID and IsInOurGroup(sourceGUID) then return end

    shearArmed = true

    if subevent == "SPELL_CAST_START" then
        if DebuffTrackerDB.shearPreWarn then
            self:Print("|cFFFFCC00Shear incoming...|r")
        end
        return
    end

    if SHEAR_LANDED_EVENTS[subevent] then
        self:ResolveShear(destGUID, destName, true, "HIT")
    elseif subevent == "SPELL_MISSED" then
        self:ResolveShear(destGUID, destName, false, ShearOutcomeLabel(p15))
    end
    -- SPELL_CAST_SUCCESS is deliberately ignored: the resolution arrives as a
    -- damage, aura or missed event, and counting the cast too would double up.
end

-- Backup detector: if a combat-log event is ever dropped, the debuff itself is
-- still on the tank. Only runs while Illidan/Shear has been seen this pull.
function DebuffTracker:SweepShearAura(unit)
    if not shearArmed then return end
    if not DebuffTrackerDB or not DebuffTrackerDB.shearMonitor then return end
    if not unit or not UnitExists(unit) then return end

    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, i)
        if not name then break end
        if IsShearSpell(spellID, name) then
            self:ResolveShear(UnitGUID(unit), UnitName(unit), true, "HIT")
            return
        end
    end
end

function DebuffTracker:ReportShearSummary()
    if not DebuffTrackerDB or not DebuffTrackerDB.shearSummary then return end
    if not shearStats or shearStats.total == 0 then return end

    self:Print(string.format(
        "Shear summary: %d total - |cFFFF4040%d hit|r, |cFF40FF40%d avoided|r",
        shearStats.total, shearStats.landed, shearStats.avoided))

    for tank, t in pairs(shearStats.byTank) do
        print(string.format("  %s: %d hit, %d avoided", tank, t.hit, t.avoided))
    end

    local parts = {}
    for outcome, n in pairs(shearStats.byOutcome) do
        if outcome ~= "HIT" then
            parts[#parts + 1] = outcome .. " x" .. n
        end
    end
    if #parts > 0 then
        print("  avoided by: " .. table.concat(parts, ", "))
    end
end

-- /wmachine shear
function DebuffTracker:ShowShearStatus()
    local on = DebuffTrackerDB and DebuffTrackerDB.shearMonitor
    self:Print("Shear monitor: " .. (on and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r")
        .. "  (tracking \"" .. tostring(shearName) .. "\")")
    if on then
        print("  announce to: " .. tostring(DebuffTrackerDB.shearChannel)
            .. ", avoided: " .. (DebuffTrackerDB.shearAnnounceAvoided and "yes" or "no")
            .. ", throttle: " .. tostring(DebuffTrackerDB.shearThrottle or 0) .. "s"
            .. ", summary: " .. (DebuffTrackerDB.shearSummary and "yes" or "no"))
    end

    local s = (shearStats and shearStats.total > 0) and shearStats or shearLastFight
    local label = (shearStats and shearStats.total > 0) and "This pull" or "Last pull"
    if not s or s.total == 0 then
        print("  no Shears recorded yet")
        return
    end
    print(string.format("  %s: %d total, %d hit, %d avoided", label, s.total, s.landed, s.avoided))
    for tank, t in pairs(s.byTank) do
        print(string.format("    %s: %d hit, %d avoided", tank, t.hit, t.avoided))
    end
end

function DebuffTracker:ToggleShearMonitor()
    if not DebuffTrackerDB then return end
    DebuffTrackerDB.shearMonitor = not DebuffTrackerDB.shearMonitor
    self:Print("Shear monitor " .. (DebuffTrackerDB.shearMonitor
        and "|cFF00FF00enabled|r" or "|cFFFF4444disabled|r"))
end


-- ============================================
-- SHADOW RESIST GEAR CHECK (post-Mother Shahraz)
-- ============================================
-- Mother Shahraz is the only Black Temple fight that wants shadow resist gear.
-- Staying in it for the Grand Promenade constructs afterwards costs a lot of
-- stats, and it is easy to forget. This arms when Mother dies (or the moment
-- you engage one of the trigger mobs, so a /reload still works) and warns on
-- your next pull if the set is still on.
--
-- Detection reads EQUIPPED GEAR only, never UnitResistance, so Shadow
-- Protection and Shadow Resistance Aura can't trigger a false warning.

-- Mobs that mean "you are past Mother" — the Grand Promenade pulls.
local SR_TRIGGER_MOBS = {}
for _, n in ipairs({
    "Shadowmoon Reaver", "Promenade Sentinel",
    "Illidari Archon", "Illidari Assassin",
    "Illidari Battle-mage", "Illidari Blood Lord",
}) do
    SR_TRIGGER_MOBS[n:lower()] = true
end

local MOTHER_NAME = "Mother Shahraz"
local SR_WARN_COOLDOWN = 20   -- seconds between warnings, so one pull warns once

local srArmed = false
local srLastWarn = 0

-- Total shadow resistance contributed by equipped items.
-- GetItemStats keys differ between clients (ITEM_MOD_SHADOW_RESISTANCE_SHORT
-- vs RESISTANCE5_NAME), so match either shape rather than one literal key.
local function SlotShadowResist(link)
    if not link or not GetItemStats then return 0 end
    local ok, stats = pcall(GetItemStats, link)
    if not ok or type(stats) ~= "table" then return 0 end
    local sr = 0
    for k, v in pairs(stats) do
        if type(v) == "number" and v > 0 then
            local K = tostring(k):upper()
            if K:find("SHADOW_RESISTANCE", 1, true) or K == "RESISTANCE5_NAME" then
                sr = sr + v
            end
        end
    end
    return sr
end

-- Returns total, pieceCount, detail[] = { slot, link, sr }
function DebuffTracker:GetGearShadowResist()
    local total, pieces, detail = 0, 0, {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local sr = SlotShadowResist(link)
            if sr > 0 then
                total = total + sr
                pieces = pieces + 1
                detail[#detail + 1] = { slot = slot, link = link, sr = sr }
            end
        end
    end
    return total, pieces, detail
end

function DebuffTracker:ResetShadowResistCheck()
    srArmed = false
    srLastWarn = 0
end

function DebuffTracker:ArmShadowResistCheck()
    srArmed = true
end

function DebuffTracker:IsShadowResistArmed()
    return srArmed
end

function DebuffTracker:WarnShadowResist(total, pieces)
    local now = GetTime()
    if (now - srLastWarn) < SR_WARN_COOLDOWN then return end
    srLastWarn = now

    local msg = "STILL IN SHADOW RESIST GEAR (" .. total .. " SR across "
        .. pieces .. " piece" .. (pieces == 1 and "" or "s") .. ") - swap out!"

    -- Always tell the player, loudly
    self:Print("|cFFFF2020" .. msg .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    pcall(PlaySound, 8959, "Master")

    local channel = DebuffTrackerDB.srCheckChannel or "LOCAL"
    if channel == "LOCAL" then return end
    if not IsInGroup() and not IsInRaid() then return end

    -- Deliberately NOT gated by ShouldAnnounce: this is about the individual
    -- player's own gear, so everyone needs to warn for themselves.
    if channel == "RAID_WARNING" then
        if not IsInRaid() then
            channel = "PARTY"
        elseif not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            channel = "RAID"
        end
    elseif channel == "RAID" then
        if not IsInRaid() then channel = "PARTY" end
    end

    pcall(SendChatMessage, msg, channel)
end

-- Evaluate now; called on engage and on entering combat while armed
function DebuffTracker:CheckShadowResistGear()
    if not DebuffTrackerDB or not DebuffTrackerDB.srCheck then return end
    if not srArmed then return end

    local total, pieces = self:GetGearShadowResist()
    local threshold = DebuffTrackerDB.srCheckThreshold or 60
    if total >= threshold then
        self:WarnShadowResist(total, pieces)
    end
end

-- Combat-log path: arms on Mother's death, and arms+fires on engaging a
-- Grand Promenade mob (covers reloading after Mother is already dead).
function DebuffTracker:HandleShadowResistCombatLog(subevent, sourceName, destName)
    if not DebuffTrackerDB or not DebuffTrackerDB.srCheck then return end

    if subevent == "UNIT_DIED" then
        if destName and destName == MOTHER_NAME then
            srArmed = true
        end
        return
    end

    if srArmed then return end  -- already armed; combat entry handles the rest

    local a = sourceName and SR_TRIGGER_MOBS[sourceName:lower()]
    local b = destName and SR_TRIGGER_MOBS[destName:lower()]
    if a or b then
        srArmed = true
        self:CheckShadowResistGear()
    end
end

-- /wmachine srcheck
function DebuffTracker:ExplainShadowResist()
    local total, pieces, detail = self:GetGearShadowResist()
    local threshold = DebuffTrackerDB and DebuffTrackerDB.srCheckThreshold or 60

    self:Print("=== Shadow resist gear ===")
    if pieces == 0 then
        print("  no equipped item reports shadow resistance")
    else
        for _, d in ipairs(detail) do
            print(string.format("  slot %d: +%d SR  %s", d.slot, d.sr, d.link))
        end
    end
    print(string.format("  gear total: %d SR across %d piece(s)   threshold: %d",
        total, pieces, threshold))
    print("  would warn: " .. (total >= threshold
        and "|cFFFF4444YES|r" or "|cFF00FF00no|r"))
    print("  check enabled: " .. ((DebuffTrackerDB and DebuffTrackerDB.srCheck)
        and "yes" or "|cFFFF4444no|r")
        .. "   armed (past Mother): " .. (srArmed and "yes" or "no"))

    -- Cross-check so a broken GetItemStats is obvious rather than silent
    if UnitResistance then
        local _, totalRes = UnitResistance("player", 5)
        if totalRes then
            print("  |cFF888888character sheet shadow resist (gear + buffs): "
                .. totalRes .. "|r")
            if pieces == 0 and totalRes > 0 then
                print("  |cFFFFCC00Gear scan found nothing but the character sheet shows"
                    .. " resistance. If you ARE wearing SR gear, report this - the item"
                    .. " API may not expose resistances on this client.|r")
            end
        end
    end
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

    -- Gate 6: On multi-boss encounters, only alert for the mob the raid is
    -- actually killing. Targeting an add the raid is ignoring (e.g. a
    -- Fathom-Guard that isn't next in the kill order) must stay silent.
    EvaluateFocus()
    if not IsFocusTarget(unit) then
        -- Don't accumulate "missing" time against a mob we aren't killing
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
-- NPC EXCLUSION MANAGEMENT (user-facing)
-- ============================================
-- Escape hatch for any mob the heuristics still get wrong: target it, run
-- the command, and that exact creature type is never treated as a boss
-- again. Keyed on npcID so same-named mobs elsewhere are unaffected.

function DebuffTracker:ExcludeTarget()
    if not UnitExists("target") then
        self:Print("No target. Target the mob you want excluded, then run this again.")
        return
    end
    local guid = UnitGUID("target")
    local npcID = GetNPCID(guid)
    if not npcID then
        self:Print("Target isn't a creature (players can't be excluded).")
        return
    end
    local name = UnitName("target") or ("NPC " .. npcID)
    DebuffTrackerDB.excludedNPCs[tostring(npcID)] = name
    self:Print("Excluded |cFFFFCC00" .. name .. "|r (npcID " .. npcID
        .. ") — it will no longer trigger boss alerts.")
    self:UpdateVisibility()
end

function DebuffTracker:UnexcludeTarget()
    if not UnitExists("target") then
        self:Print("No target.")
        return
    end
    local npcID = GetNPCID(UnitGUID("target"))
    if not npcID then return end
    local key = tostring(npcID)
    if DebuffTrackerDB.excludedNPCs[key] then
        local name = DebuffTrackerDB.excludedNPCs[key]
        DebuffTrackerDB.excludedNPCs[key] = nil
        self:Print("Removed |cFFFFCC00" .. name .. "|r from the exclusion list.")
    else
        self:Print((UnitName("target") or "Target") .. " is not excluded.")
    end
end

function DebuffTracker:ListExclusions()
    local list = DebuffTrackerDB and DebuffTrackerDB.excludedNPCs
    if not list or not next(list) then
        self:Print("No excluded NPCs. Target a mob and use /wmachine exclude to add one.")
        return
    end
    self:Print("=== Excluded NPCs (never treated as bosses) ===")
    for npcID, name in pairs(list) do
        print("  |cFFFFCC00" .. tostring(name) .. "|r (npcID " .. npcID .. ")")
    end
    self:Print("Use /wmachine unexclude with the mob targeted to remove one.")
end

function DebuffTracker:ClearExclusions()
    if DebuffTrackerDB then
        DebuffTrackerDB.excludedNPCs = {}
    end
    self:Print("Exclusion list cleared.")
end

-- Diagnostic: what does the tracker think about the current target?
function DebuffTracker:ExplainTarget()
    if not UnitExists("target") then
        self:Print("No target.")
        return
    end
    local guid = UnitGUID("target")
    local npcID = GetNPCID(guid)
    local name = UnitName("target") or "?"
    self:Print("=== Target analysis: " .. name .. " ===")
    print("  npcID: " .. tostring(npcID or "n/a (player?)"))
    print("  classification: " .. tostring(UnitClassification("target"))
        .. "   level: " .. tostring(UnitLevel("target")))
    print("  max health: " .. tostring(UnitHealthMax("target"))
        .. "  (boss floor: " .. tostring(DebuffTrackerDB.bossMinHealth) .. ")")
    print("  excluded: " .. (self:IsNPCExcluded(npcID) and "|cFFFF4444YES|r" or "no"))
    print("  counts as boss: " .. (IsBossUnit("target") and "|cFF00FF00YES|r" or "|cFFFF4444no|r"))
    EvaluateFocus()
    local fGUID, fName = self:GetFocusInfo()
    if DebuffTrackerDB.focusTracking then
        print("  raid focus: " .. tostring(fName or "none yet")
            .. (fGUID == guid and " |cFF00FF00(this target)|r" or ""))
        print("  would alert: " .. (IsFocusTarget("target") and "|cFF00FF00YES|r" or "|cFFFF4444no — raid is killing something else|r"))
    else
        print("  focus tracking: |cFF888888off|r")
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

function DebuffTracker:Initialize()
    self:InitDB()
    self:CreateTrackerFrame()
    self:RegisterPullDetection()
    self:RegisterDoomWarning()
    -- Resolve Shear's localized name so non-English clients match by name too
    if GetSpellInfo then
        local n = GetSpellInfo(41032)
        if n and n ~= "" then shearName = n end
    end
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
    if DebuffTrackerDB.bossMinHealth == nil then
        DebuffTrackerDB.bossMinHealth = 150000
    end
    if DebuffTrackerDB.focusTracking == nil then
        DebuffTrackerDB.focusTracking = true
    end
    if type(DebuffTrackerDB.excludedNPCs) ~= "table" then
        DebuffTrackerDB.excludedNPCs = {}
    end
    if DebuffTrackerDB.shearMonitor == nil then DebuffTrackerDB.shearMonitor = true end
    if DebuffTrackerDB.shearChannel == nil then DebuffTrackerDB.shearChannel = "RAID" end
    if DebuffTrackerDB.shearAnnounceAvoided == nil then DebuffTrackerDB.shearAnnounceAvoided = false end
    if DebuffTrackerDB.shearPreWarn == nil then DebuffTrackerDB.shearPreWarn = false end
    if DebuffTrackerDB.shearThrottle == nil then DebuffTrackerDB.shearThrottle = 0 end
    if DebuffTrackerDB.shearSummary == nil then DebuffTrackerDB.shearSummary = true end
    if DebuffTrackerDB.srCheck == nil then DebuffTrackerDB.srCheck = true end
    if DebuffTrackerDB.srCheckThreshold == nil then DebuffTrackerDB.srCheckThreshold = 60 end
    if DebuffTrackerDB.srCheckChannel == nil then DebuffTrackerDB.srCheckChannel = "LOCAL" end
    
    -- v2.3.1 migration: force-disable raid alerts once on upgrade.
    -- The alert system was overhauled (encounter-aware, dead caster suppression,
    -- leader-only coordination). Reset so users consciously re-enable it.
    if not DebuffTrackerDB.alertResetV27 then
        DebuffTrackerDB.raidAlerts = false
        DebuffTrackerDB.alertResetV27 = true
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

        -- Match by name (more reliable in Classic), then by spellID; pick
        -- the highest-priority enabled definition among the matches
        local candidate = category.byName[name]
        if candidate and debuffToggles and debuffToggles[candidate.name] == false then
            candidate = nil
        end

        local spellMatches = spellId and category.bySpellID[spellId]
        if spellMatches then
            for _, debuff in ipairs(spellMatches) do
                if (not debuffToggles or debuffToggles[debuff.name] ~= false)
                    and (not candidate or debuff.priority > candidate.priority) then
                    candidate = debuff
                end
            end
        end

        if candidate and candidate.priority > bestPriority then
            bestDebuff = {
                name = name,
                icon = icon,
                count = count,
                duration = duration,
                expirationTime = expirationTime,
                priority = candidate.priority,
                definition = candidate,
            }
            bestPriority = candidate.priority
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
            DebuffTracker:ResetDoomWarning()
            DebuffTracker:ResetShearMonitor(false)
            DebuffTracker:CheckShadowResistGear()
            wipe(damageWindow)
            focusGUID, focusName = nil, nil
            RefreshGroupGUIDs()
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
            DebuffTracker:ResetDoomWarning()
            -- Report the pull's Shear tally before clearing it
            DebuffTracker:ReportShearSummary()
            DebuffTracker:ResetShearMonitor(true)
            wipe(damageWindow)
            focusGUID, focusName = nil, nil
            RefreshGroupGUIDs()
            trackedBossGUIDs = {}
            return
        end
        if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            raidScanDirty = true
        end
        if event == "PLAYER_ENTERING_WORLD" then
            -- Left the instance (or reloaded): disarm. Engaging a Grand
            -- Promenade mob re-arms it, so a mid-raid reload still works.
            DebuffTracker:ResetShadowResistCheck()
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
-- SETTINGS PANEL
-- ============================================
-- One scrolling panel built with WM.UI. Encounter callouts used to live in
-- a second window only because the hand-measured panel outgrew the screen;
-- they're a collapsible section here, and /wmachine encounters opens the
-- panel scrolled to it. The panel is refreshed in place (panel:Refresh)
-- when settings or the raid roster change, never rebuilt.

local CHANNEL_OPTIONS = {
    { value = "LOCAL", text = "Me only" }, { value = "SAY", text = "Say" },
    { value = "PARTY", text = "Party" }, { value = "RAID", text = "Raid" },
    { value = "RAID_WARNING", text = "/rw" },
}
local PULL_CHANNEL_OPTIONS = {
    { value = "SAY", text = "Say" }, { value = "PARTY", text = "Party" },
    { value = "RAID", text = "Raid" }, { value = "RAID_WARNING", text = "/rw" },
}

local function DBGetSet(key)
    return function() return DebuffTrackerDB[key] end,
        function(v) DebuffTrackerDB[key] = v end
end

local function ClassHex(className)
    local c = RAID_CLASS_COLORS[className] or { r = 1, g = 1, b = 1 }
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function FormatThrottle(v)
    if v <= 0 then return "every one" end
    return v .. "s"
end

local function FormatHP(v)
    if v <= 0 then return "off" end
    return string.format("%dk", math.floor(v / 1000))
end

function DebuffTracker:CreateUI()
    if mainFrame then return mainFrame end

    local panel = WM.UI:CreatePanel({
        name = "WM_DebuffTrackerSettingsFrame",
        title = "Debuff Tracker Settings",
        width = 420,
        maxHeight = 700,
    })
    local L = panel.layout
    local get, set

    -- ---------- General ----------
    local function Visibility(key, label)
        local g, s = DBGetSet(key)
        L:Checkbox({ label = label, get = g, set = function(v) s(v); DebuffTracker:UpdateVisibility() end })
    end
    Visibility("enabled", "Enable Debuff Tracker")
    Visibility("showOnlyInRaid", "Show only in raid")
    Visibility("showOnlyOnBoss", "Show only on boss targets")
    Visibility("hideWhenNoTarget", "Hide when no hostile target")

    -- ---------- Auto-detection ----------
    L:Section({ key = "autodetect", title = "Raid Auto-Detection" })
    L:Checkbox({
        label = "Auto-configure from raid composition",
        get = function() return DebuffTrackerDB.autoDetect end,
        set = function(v)
            DebuffTrackerDB.autoDetect = v
            if v then DebuffTracker:ScanRaidComposition() end
            panel:Refresh()
        end,
        tooltip = {
            "Auto-Detection",
            "Scans the raid roster for classes and only tracks debuff categories your raid can"
                .. " actually provide. Re-scans when the roster changes.",
            "While on, the debuff selection below is managed for you.",
        },
    })
    local compRow = L:Row(22)
    compRow:Text({ text = "|cFFB3B3B3Detected classes:|r", font = "GameFontNormalSmall" }, 17)
    compRow:RightButton({
        text = "Scan Now", width = 70, height = 18,
        tooltip = { "Scan Now", "Re-read the raid roster immediately." },
        onClick = function()
            DebuffTracker:ScanRaidComposition()
            DebuffTracker:VerbosePrint("Raid scanned: " .. DebuffTracker:GetRaidCompositionString())
            panel:Refresh()
        end,
    }, 8)
    L:Note(function() return DebuffTracker:GetRaidCompositionString() end, 5)

    -- ---------- Alerts ----------
    L:Section({ key = "alerts", title = "Missing Debuff Alerts" })
    get, set = DBGetSet("raidAlerts")
    L:Checkbox({
        label = "Send raid message when debuff missing", get = get, set = set,
        tooltip = { "Missing Debuff Alerts", "Uses /rw if you have assist, otherwise /raid."
            .. " Only alerts for enabled categories." },
    })
    local row = L:Row(24)
    get, set = DBGetSet("alertOnlyOnBoss")
    row:Checkbox({ label = "Only on boss targets", get = get, set = set }, 23)
    get, set = DBGetSet("assistCanAnnounce")
    row:Checkbox({
        label = "Assistants can announce", get = get, set = set,
        tooltip = {
            "Assistant Announcements",
            "By default only the raid leader sends missing debuff alerts to chat. Enable this if"
                .. " the raid leader doesn't have the addon and you want assistants to announce.",
        },
    }, 212)
    row = L:Row(44)
    get, set = DBGetSet("alertDelay")
    row:Slider({
        name = "WM_DebuffAlertDelaySlider", label = "Delay before alert", width = 160,
        min = 2, max = 15, step = 1, get = get, set = set,
        format = function(v) return v .. "s" end,
        tooltip = { "Delay Before Alert", "How long a debuff must be missing from the boss before"
            .. " the alert goes out, so normal refresh gaps don't trigger it." },
    }, 12)
    get, set = DBGetSet("alertCooldown")
    row:Slider({
        name = "WM_DebuffAlertCDSlider", label = "Cooldown between alerts", width = 150,
        min = 10, max = 120, step = 5, get = get, set = set,
        format = function(v) return v .. "s" end,
        tooltip = { "Alert Cooldown", "Minimum time between two alerts, so a debuff that stays"
            .. " missing isn't called out over and over." },
    }, 200)
    row = L:Row(24)
    get, set = DBGetSet("pullAnnounce")
    row:Checkbox({
        label = "Announce who pulled the boss", get = get, set = set,
        tooltip = {
            "Pull Announce",
            "Detects the first player in your group to hit a boss and announces it to chat.",
            "Example: First hit: Playername on Gruul",
        },
    }, 8)
    row:Cycle({
        label = "Channel:", width = 55, options = PULL_CHANNEL_OPTIONS, default = "SAY",
        get = function() return DebuffTrackerDB.pullAnnounceChannel end,
        set = function(v) DebuffTrackerDB.pullAnnounceChannel = v end,
        tooltip = { "Announce Channel", "Click to cycle: Say > Party > Raid > /rw",
            "/rw falls back to Raid if no assist." },
    }, 230)

    -- ---------- Target filtering ----------
    L:Section({ key = "filtering", title = "Target Filtering" })
    get, set = DBGetSet("focusTracking")
    L:Checkbox({
        label = "Only alert for the raid's actual kill target", get = get, set = set,
        tooltip = {
            "Focus Target Tracking",
            "On multi-boss fights (Fathom-Lord Karathress, Illidari Council) the addon watches"
                .. " which mob is taking the most raid damage and only alerts for that one.",
            "Target an add the raid is ignoring and it stays quiet. Adapts to any kill order —"
                .. " no configuration needed if you change strategy.",
        },
    })
    row = L:Row(44)
    row:Slider({
        name = "WM_DebuffBossHPSlider", label = "Min boss health", width = 170,
        min = 0, max = 400000, step = 25000, lowText = "off", highText = "400k",
        get = function() return DebuffTrackerDB.bossMinHealth or 150000 end,
        set = function(v) DebuffTrackerDB.bossMinHealth = v end,
        format = FormatHP,
        tooltip = {
            "Minimum Boss Health",
            "Mobs below this max health are never treated as bosses. Raid trash is level 72-73"
                .. " elite just like real bosses, so level alone can't tell them apart — health pool can.",
            "Lower it if a real boss is being missed; raise it if trash still triggers alerts.",
        },
    }, 12)
    row:RightButton({
        text = "Exclude Target", width = 115,
        onClick = function() DebuffTracker:ExcludeTarget() end,
        tooltip = {
            "Exclude Target",
            "Permanently stop treating your current target's creature type as a boss. Matched by"
                .. " npcID, so mobs that merely share a display name elsewhere are unaffected.",
            " ",
            { "/wmachine exclusions to review the list" },
            { "/wmachine whyboss to diagnose a target" },
        },
    }, 8)

    -- ---------- Encounter callouts ----------
    L:Section({ key = "encounters", title = "Encounter Callouts" })
    get, set = DBGetSet("illidanDoomWarning")
    L:Checkbox({
        label = "Illidan 68%: raid warn \"CAST DOOM NOW\"", get = get, set = set,
        tooltip = {
            "Illidan Doom Warning",
            "When Illidan Stormrage reaches 68% health, sends CAST DOOM NOW as a raid warning so"
                .. " warlocks land Curse of Doom before he lifts off at 65%.",
            " ",
            "Fires once per pull. Sent by the raid leader (or assistants if allowed under Missing"
                .. " Debuff Alerts); others see it locally.",
        },
    })
    row = L:Row(24)
    get, set = DBGetSet("shearMonitor")
    row:Checkbox({
        label = "Illidan: call out Shear on the main tank", get = get, set = set,
        tooltip = {
            "Illidan Shear Monitor",
            "Shear cuts the main tank's maximum health by about 60% and can be dodged, parried or blocked.",
            " ",
            "Damage meters miss it: the hit is a max-health debuff and an avoided Shear deals no"
                .. " damage at all. This watches every cast, hit, aura and avoidance event, and sweeps"
                .. " raid auras as a backup.",
            " ",
            { "A summary prints when the pull ends." },
            { "/wmachine shear - status and tallies" },
        },
    }, 8)
    row:Cycle({
        label = "To:", options = CHANNEL_OPTIONS, default = "RAID",
        get = function() return DebuffTrackerDB.shearChannel end,
        set = function(v) DebuffTrackerDB.shearChannel = v end,
        tooltip = {
            "Shear Announce Channel",
            "Cycles: Me only > Say > Party > Raid > /rw",
            "You always see a local line regardless. Chat is sent by the raid leader (or"
                .. " assistants if allowed) so only one person calls it.",
        },
    }, 268)
    row = L:Row(24)
    get, set = DBGetSet("shearAnnounceAvoided")
    row:Checkbox({
        label = "Also call dodged / parried / blocked", get = get, set = set,
        tooltip = {
            "Avoided Shears",
            "Off by default: Shear repeats every ~10s, so calling both outcomes doubles the chat."
                .. " Avoided Shears are still counted and appear in the pull summary.",
        },
    }, 23)
    get, set = DBGetSet("shearPreWarn")
    row:Checkbox({
        label = "Cast warning", get = get, set = set,
        tooltip = {
            "Shear Cast Warning",
            "Shear has a ~1.5s cast. This prints a local heads-up the moment it starts - the"
                .. " window to use Shield Block or Holy Shield. Never sent to chat.",
        },
    }, 262)
    row = L:Row(44)
    row:Slider({
        name = "WM_DebuffShearThrottleSlider", label = "Min gap between calls", width = 165,
        min = 0, max = 30, step = 1, lowText = "all", highText = "30s",
        get = function() return DebuffTrackerDB.shearThrottle or 0 end,
        set = function(v) DebuffTrackerDB.shearThrottle = v end,
        format = FormatThrottle,
        tooltip = {
            "Shear Chat Throttle",
            "Shear repeats roughly every 10s across three ground phases, so calling every one is a"
                .. " lot of raid chat. This sets the minimum gap between CHAT calls.",
            " ",
            { "Throttled Shears are still counted and still shown to you locally - only the chat line is skipped." },
        },
    }, 27)
    get, set = DBGetSet("shearSummary")
    row:Checkbox({
        label = "Pull summary", get = get, set = set,
        tooltip = {
            "Shear Pull Summary",
            "When combat ends, prints the pull's tally: total, hit vs avoided, a per-tank"
                .. " breakdown so swaps are visible, and which avoidance types occurred.",
            "Local only, never sent to chat.",
        },
    }, 262)

    L:Header("Black Temple: shadow resist gear")
    row = L:Row(24)
    get, set = DBGetSet("srCheck")
    row:Checkbox({
        label = "Warn if still in SR gear after Mother", get = get, set = set,
        tooltip = {
            "Shadow Resist Gear Check",
            "Mother Shahraz is the only fight in Black Temple that wants shadow resist gear. This"
                .. " warns you if you pull the Grand Promenade constructs after her while still wearing it.",
            " ",
            "Arms when Mother dies, or the moment you engage one of the trigger mobs (so a /reload still works).",
            " ",
            { "/wmachine srcheck - see exactly what it detects" },
        },
    }, 8)
    row:Cycle({
        label = "To:", options = CHANNEL_OPTIONS, default = "LOCAL",
        get = function() return DebuffTrackerDB.srCheckChannel end,
        set = function(v) DebuffTrackerDB.srCheckChannel = v end,
        tooltip = {
            "SR Warning Channel",
            "Cycles: Me only > Say > Party > Raid > /rw",
            "This one is about YOUR gear, so unlike the other callouts every player warns"
                .. " themselves - it is not limited to the raid leader.",
        },
    }, 268)
    row = L:Row(44)
    row:Slider({
        name = "WM_DebuffSRThresholdSlider", label = "Warn at gear SR of", width = 165,
        min = 10, max = 250, step = 10,
        get = function() return DebuffTrackerDB.srCheckThreshold or 60 end,
        set = function(v) DebuffTrackerDB.srCheckThreshold = v end,
        tooltip = {
            "Shadow Resist Threshold",
            "Total shadow resistance from EQUIPPED GEAR that counts as still wearing the set."
                .. " Buffs and auras are ignored.",
            " ",
            "A Mother set runs well over 200. Raise this if an odd piece with incidental SR sets it off.",
        },
    }, 27)
    row:RightButton({
        text = "Check My Gear", width = 110,
        onClick = function() DebuffTracker:ExplainShadowResist() end,
        tooltip = {
            "Check My Gear",
            "Lists every equipped piece carrying shadow resistance, the gear total against the"
                .. " threshold, and whether the check is currently armed.",
        },
    }, 8)
    L:Note("Trigger mobs: Shadowmoon Reaver, Promenade Sentinel and the Illidari packs on the"
        .. " Grand Promenade. Use Check My Gear to confirm detection works on your client before relying on it.")

    -- ---------- Debuff selection ----------
    L:Section({
        key = "debuffs", title = "Debuff Selection by Class",
        rightText = function()
            return DebuffTrackerDB.autoDetect and "|cFF888888(auto-managed)|r" or ""
        end,
    })

    for _, category in ipairs(DEBUFF_CATEGORIES) do
        local catName = category.name
        local function CanEdit()
            return DebuffTrackerDB.trackedCategories[catName] and not DebuffTrackerDB.autoDetect
        end
        local colorHex = string.format("%02x%02x%02x",
            category.color[1] * 255, category.color[2] * 255, category.color[3] * 255)

        L:Checkbox({
            font = "GameFontNormal", indent = -3,
            label = function()
                local tag = ""
                if category.optional then
                    tag = " |cFFAAAA00(optional)|r"
                elseif DebuffTrackerDB.autoDetect then
                    tag = DebuffTracker:IsCategoryCoverable(category)
                        and " |cFF00FF00(available)|r" or " |cFF666666(no class in raid)|r"
                end
                return "|cFF" .. colorHex .. catName .. "|r" .. tag
            end,
            get = function() return DebuffTrackerDB.trackedCategories[catName] end,
            set = function(v)
                DebuffTrackerDB.trackedCategories[catName] = v
                DebuffTracker:UpdateFrameSize()
                DebuffTracker:UpdateDebuffs()
                panel:Refresh()
            end,
            -- Auto-detect owns every category except the optional ones
            disabled = function() return DebuffTrackerDB.autoDetect and not category.optional end,
        })

        -- Debuffs grouped by providing class, in first-seen order
        local byClass, classOrder = {}, {}
        for _, debuff in ipairs(category.debuffs) do
            if not byClass[debuff.class] then
                byClass[debuff.class] = {}
                classOrder[#classOrder + 1] = debuff.class
            end
            table.insert(byClass[debuff.class], debuff)
        end

        for _, className in ipairs(classOrder) do
            local classRow = L:Row(18)
            classRow:Text({
                font = "GameFontNormalSmall",
                text = function()
                    local tag = ""
                    if DebuffTrackerDB.autoDetect then
                        if DebuffTracker:IsClassInRaid(className) then
                            local specs = {}
                            for spec in pairs(raidSpecs[className] or {}) do specs[#specs + 1] = spec end
                            local specStr = #specs > 0 and (" - " .. table.concat(specs, ", ")) or ""
                            tag = " |cFF00FF00(" .. (raidClasses[className] or 0) .. " in raid" .. specStr .. ")|r"
                        else
                            tag = " |cFFFF4444(not in raid)|r"
                        end
                    end
                    return "|cFF" .. ClassHex(className) .. className .. ":|r" .. tag
                end,
            }, 35)

            for _, debuff in ipairs(byClass[className]) do
                L:Checkbox({
                    indent = 32,
                    label = debuff.name .. (debuff.spec and " |cFFAAAACC[" .. debuff.spec .. "]|r" or "")
                        .. " |cFF888888(P:" .. debuff.priority .. ")|r",
                    get = function() return DebuffTrackerDB.trackedDebuffs[catName][debuff.name] end,
                    set = function(v)
                        DebuffTrackerDB.trackedDebuffs[catName][debuff.name] = v
                        DebuffTracker:UpdateDebuffs()
                    end,
                    disabled = function() return not CanEdit() end,
                })
            end
        end

        local function SetAll(v)
            for _, debuff in ipairs(category.debuffs) do
                DebuffTrackerDB.trackedDebuffs[catName][debuff.name] = v
            end
            DebuffTracker:UpdateDebuffs()
            panel:Refresh()
        end
        local btnRow = L:Row(22)
        btnRow:Button({ text = "All On", width = 65, height = 16, small = true,
            onClick = function() SetAll(true) end, disabled = function() return not CanEdit() end }, 45)
        btnRow:Button({ text = "All Off", width = 65, height = 16, small = true,
            onClick = function() SetAll(false) end, disabled = function() return not CanEdit() end }, 115)
        L:Separator()
    end

    -- ---------- Footer ----------
    panel:AddFooterButton({
        text = "Reset Position", width = 120,
        tooltip = { "Reset Position", "Move the debuff tracker display back to the middle of the screen." },
        onClick = function()
            DebuffTrackerDB.frameX = nil
            DebuffTrackerDB.frameY = nil
            if trackerFrame then
                trackerFrame:ClearAllPoints()
                trackerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
            end
            DebuffTracker:Print("Tracker position reset")
        end,
    }, "LEFT")
    panel:AddFooterButton({
        text = "Test Display", width = 100,
        tooltip = { "Test Display", "Show the tracker now, outside a raid. Target a mob to see debuffs." },
        onClick = function()
            if trackerFrame then
                trackerFrame:Show()
                DebuffTracker:Print("Showing tracker for testing. Target a mob to see debuffs.")
            end
        end,
    }, "RIGHT")

    panel:Finish()

    mainFrame = panel
    self.mainFrame = panel
    return panel
end

-- Re-read every control (roster scans and auto-detect call this). Kept
-- under its old name: callers predate the panel being refreshable in place.
function DebuffTracker:RefreshSettingsUI()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Refresh()
    end
end

-- /wmachine encounters: the callouts are a section of the settings panel
function DebuffTracker:ToggleEncounterUI()
    local panel = self:CreateUI()
    panel:ShowSection("encounters")
end

function DebuffTracker:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

