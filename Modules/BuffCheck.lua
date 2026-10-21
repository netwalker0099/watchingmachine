-- Watching Machine: Buff Check Module
-- Scans the raid for missing buffs when a ready check runs.
-- If YOU started the ready check: announces missing buffs to raid chat.
-- If someone else started it: prints the report locally so only you see it.

local AddonName, WM = ...
local BuffCheck = {}
WM:RegisterModule("BuffCheck", BuffCheck)

BuffCheck.version = "3.1"

-- ============================================
-- BUFF DEFINITIONS (TBC)
-- ============================================
-- providerClass: buff only checked if that class is in the group (nil = always, e.g. consumables)
-- appliesTo: which classes are expected to have the buff
-- buffs: any one of these aura names counts as "has it"
-- prefix: alternative match — aura name starting with this counts (used for flasks)

local ALL_CLASSES = {
    WARRIOR = true, ROGUE = true, HUNTER = true, MAGE = true, WARLOCK = true,
    PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true,
}
-- Everyone except warriors and rogues uses mana in TBC (hunters included)
local MANA_CLASSES = {
    HUNTER = true, MAGE = true, WARLOCK = true, PRIEST = true,
    PALADIN = true, SHAMAN = true, DRUID = true,
}

local BUFF_GROUPS = {
    {
        key = "fortitude",
        name = "Fortitude",
        providerClass = "PRIEST",
        buffs = { "Power Word: Fortitude", "Prayer of Fortitude" },
        appliesTo = ALL_CLASSES,
        default = true,
    },
    {
        key = "motw",
        name = "Mark of the Wild",
        providerClass = "DRUID",
        buffs = { "Mark of the Wild", "Gift of the Wild" },
        appliesTo = ALL_CLASSES,
        default = true,
    },
    {
        key = "intellect",
        name = "Arcane Intellect",
        providerClass = "MAGE",
        buffs = { "Arcane Intellect", "Arcane Brilliance" },
        appliesTo = MANA_CLASSES,
        default = true,
    },
    {
        key = "blessing",
        name = "Paladin Blessing",
        providerClass = "PALADIN",
        buffs = {
            "Blessing of Might", "Greater Blessing of Might",
            "Blessing of Wisdom", "Greater Blessing of Wisdom",
            "Blessing of Kings", "Greater Blessing of Kings",
            "Blessing of Salvation", "Greater Blessing of Salvation",
            "Blessing of Sanctuary", "Greater Blessing of Sanctuary",
            "Blessing of Light", "Greater Blessing of Light",
        },
        appliesTo = ALL_CLASSES,
        default = true,
    },
    {
        key = "spirit",
        name = "Divine Spirit",
        providerClass = "PRIEST",
        buffs = { "Divine Spirit", "Prayer of Spirit" },
        appliesTo = MANA_CLASSES,
        default = false,  -- Disc talent in TBC; enable only if your raid runs one
        note = "Disc priest talent",
    },
    {
        key = "shadowprot",
        name = "Shadow Protection",
        providerClass = "PRIEST",
        buffs = { "Shadow Protection", "Prayer of Shadow Protection" },
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Enable for shadow-heavy fights",
    },
    {
        key = "wellfed",
        name = "Food Buff",
        providerClass = nil,  -- consumable
        buffs = WM.FOOD_BUFFS,  -- shared with ClassGeneral (Core.lua)
        appliesTo = ALL_CLASSES,
        default = true,
        note = "Well Fed or Enlightened",
    },
    {
        key = "flask",
        name = "Flask or Elixirs",
        providerClass = nil,  -- consumable
        buffs = {},
        -- Substring (not prefix) match: TBC's Zul'Aman-era flasks are named
        -- "Unstable Flask of the Beast" / "...of the Sorcerer", so anchoring
        -- to the start of the name would miss them.
        contains = WM.FLASK_CONTAINS,
        -- A battle plus a guardian elixir is as good as a flask in TBC
        orElixirPair = true,
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Flask, or battle + guardian elixir",
    },
    {
        key = "battleelixir",
        name = "Battle Elixir",
        providerClass = nil,  -- consumable
        buffs = WM.BATTLE_ELIXIRS,       -- shared with ClassGeneral (Core.lua)
        ids = WM.BATTLE_ELIXIR_IDS,
        -- Flasks occupy both elixir slots in TBC
        contains = WM.FLASK_CONTAINS,
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Flask counts too",
    },
    {
        key = "guardianelixir",
        name = "Guardian Elixir",
        providerClass = nil,  -- consumable
        buffs = WM.GUARDIAN_ELIXIRS,
        ids = WM.GUARDIAN_ELIXIR_IDS,
        contains = WM.FLASK_CONTAINS,
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Flask counts too",
    },
}

-- Fast lookup: buff name -> group, built once at load
for _, group in ipairs(BUFF_GROUPS) do
    group.buffSet = {}
    for _, buffName in ipairs(group.buffs) do
        group.buffSet[buffName] = true
    end
end

-- Default settings
local defaults = {
    enabled = true,
    announceToRaid = true,     -- announce when the player initiated the ready check
    reportAllBuffed = true,    -- also report when nothing is missing
    usePallyPower = true,      -- check assigned blessings from PallyPower when available
    checkedGroups = {},        -- per-group enable, filled below
}

for _, group in ipairs(BUFF_GROUPS) do
    defaults.checkedGroups[group.key] = group.default
end

-- State
local mainFrame = nil
local lastReport = nil        -- Cached lines from the most recent check
local lastReportTime = nil

-- ============================================
-- INITIALIZATION
-- ============================================

function BuffCheck:Initialize()
    self:InitDB()
    self:RegisterEvents()
end

function BuffCheck:InitDB()
    if not BuffCheckDB then
        BuffCheckDB = {}
    end
    for key, value in pairs(defaults) do
        if BuffCheckDB[key] == nil then
            if type(value) == "table" then
                BuffCheckDB[key] = {}
                for k2, v2 in pairs(value) do
                    BuffCheckDB[key][k2] = v2
                end
            else
                BuffCheckDB[key] = value
            end
        end
    end
    -- Merge new buff groups added by addon updates
    for _, group in ipairs(BUFF_GROUPS) do
        if BuffCheckDB.checkedGroups[group.key] == nil then
            BuffCheckDB.checkedGroups[group.key] = group.default
        end
    end
    -- 3.6: the food check became on by default. Saved settings from before
    -- hold the old default (off), so turn it on once; after that the
    -- player's own choice sticks.
    if not BuffCheckDB.foodDefaultOn then
        BuffCheckDB.foodDefaultOn = true
        BuffCheckDB.checkedGroups.wellfed = true
    end
end

function BuffCheck:Print(msg)
    WM:ModulePrint("BuffCheck", msg)
end

-- ============================================
-- SCANNING
-- ============================================

-- Collect all group unit tokens (including the player)
local function GetGroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                units[#units + 1] = "party" .. i
            end
        end
    else
        units[#units + 1] = "player"
    end
    return units
end

-- Fill a reusable set with every buff name on a unit
local buffScratch = {}
local expectedScratch = {}
-- name -> spell ID (or true where the client gives none)
local function GetUnitBuffSet(unit)
    wipe(buffScratch)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        buffScratch[name] = spellId or true
    end
    return buffScratch
end

-- Does this single aura name satisfy the group? Returns the reason it
-- matched (for diagnostics) or nil.
local function BuffMatchesGroup(buffName, group, spellId)
    if group.buffSet[buffName] then
        return "exact"
    end
    if group.ids and type(spellId) == "number" and group.ids[spellId] then
        return "spell id " .. spellId
    end
    if group.contains then
        for _, needle in ipairs(group.contains) do
            -- plain=true: these are literal strings, not patterns
            if buffName:find(needle, 1, true) then
                return "contains '" .. needle .. "'"
            end
        end
    end
    return nil
end

local function UnitHasGroupBuff(buffSet, group)
    local battle, guardian = false, false
    for buffName, spellId in pairs(buffSet) do
        if BuffMatchesGroup(buffName, group, spellId) then
            return true
        end
        if group.orElixirPair then
            local kind = WM:ConsumableKind(buffName, type(spellId) == "number" and spellId or nil)
            if kind == "battle" then battle = true elseif kind == "guardian" then guardian = true end
        end
    end
    return group.orElixirPair and battle and guardian or false
end

-- ============================================
-- PALLYPOWER INTEGRATION
-- ============================================
-- When PallyPower is running and paladins in the group have blessing
-- assignments, check each player against their ASSIGNED blessings instead of
-- the generic "has any blessing" check. Reads PallyPower's own runtime tables
-- (ClassID / Spells / GSpells) so the mapping stays correct across PallyPower
-- versions and localized clients.
--
-- PallyPower data model:
--   PallyPower_Assignments[pallyName][classIndex] = blessingIndex   (class-wide)
--   PallyPower_NormalAssignments[pallyName][classIndex][playerName] = blessingIndex
--   PallyPower.ClassID[classIndex] = "WARRIOR" etc.
--   PallyPower.Spells[blessingIndex] / PallyPower.GSpells[blessingIndex] = aura names

-- Returns nil when PallyPower isn't usable (not loaded, no assignments from
-- paladins actually in the group) — caller falls back to the generic check.
--
-- Assignments are kept PER PALADIN because PallyPower's single-target
-- (normal) assignments OVERRIDE that same paladin's class-wide blessing for
-- that player: a feral tank with a single Might assigned does NOT also get
-- that paladin's Greater Salvation. A different paladin's class assignment
-- still applies to the tank as usual.
local function GetPallyPowerData(units)
    local pp = _G.PallyPower
    local assignments = _G.PallyPower_Assignments
    if not pp or not assignments or not pp.ClassID or not pp.Spells then
        return nil
    end

    -- Only honor assignments from paladins actually in the group; the
    -- assignments table can carry entries for offline/absent paladins
    local groupPallys = {}
    for _, unit in ipairs(units) do
        local _, class = UnitClass(unit)
        if class == "PALADIN" and UnitIsConnected(unit) then
            local name = UnitName(unit)
            if name then
                groupPallys[name] = true
            end
        end
    end

    -- pallys[pallyName] = {
    --   classes = { classToken -> blessingIndex },   (class-wide greater blessing)
    --   players = { playerName -> blessingIndex },   (single-target override)
    -- }
    local pallys = {}
    local found = false

    for pallyName, classTable in pairs(assignments) do
        if groupPallys[pallyName] and type(classTable) == "table" then
            for classIndex, blessingID in pairs(classTable) do
                local classToken = pp.ClassID[classIndex]
                if classToken and type(blessingID) == "number" and blessingID > 0 then
                    if not pallys[pallyName] then
                        pallys[pallyName] = { classes = {}, players = {} }
                    end
                    pallys[pallyName].classes[classToken] = blessingID
                    found = true
                end
            end
        end
    end

    local normals = _G.PallyPower_NormalAssignments
    if normals then
        for pallyName, classTable in pairs(normals) do
            if groupPallys[pallyName] and type(classTable) == "table" then
                for _, players in pairs(classTable) do
                    if type(players) == "table" then
                        for playerName, blessingID in pairs(players) do
                            if type(blessingID) == "number" and blessingID > 0 then
                                if not pallys[pallyName] then
                                    pallys[pallyName] = { classes = {}, players = {} }
                                end
                                pallys[pallyName].players[playerName] = blessingID
                                found = true
                            end
                        end
                    end
                end
            end
        end
    end

    if not found then return nil end

    return {
        pallys = pallys,
        spells = pp.Spells,
        gspells = pp.GSpells,
    }
end

-- Expected blessing set for one player: for each paladin, the single-target
-- override wins over that paladin's class-wide assignment; contributions
-- from different paladins stack.
local function GetExpectedBlessings(ppData, playerName, classToken, out)
    wipe(out)
    for _, pally in pairs(ppData.pallys) do
        local override = pally.players[playerName]
        if override then
            out[override] = true
        else
            local classBlessing = pally.classes[classToken]
            if classBlessing then
                out[classBlessing] = true
            end
        end
    end
    return out
end

-- Is PallyPower loaded at all? (for UI status display)
function BuffCheck:IsPallyPowerAvailable()
    return (_G.PallyPower and _G.PallyPower_Assignments) and true or false
end

-- Run the full scan.
-- Returns: lines (array of report strings), missingCount, skipped (array of offline/dead names)
function BuffCheck:ScanGroup()
    local units = GetGroupUnits()

    -- First pass: classes present (so we don't demand Fortitude with no priest)
    local classesPresent = {}
    for _, unit in ipairs(units) do
        local _, class = UnitClass(unit)
        if class then
            classesPresent[class] = true
        end
    end

    -- PallyPower assignments (nil = not usable, fall back to generic check)
    local ppData = nil
    if BuffCheckDB.checkedGroups.blessing and BuffCheckDB.usePallyPower then
        ppData = GetPallyPowerData(units)
    end

    -- Which groups are actually checkable right now. When PallyPower data is
    -- available the generic "any blessing" group is replaced by per-assignment
    -- checks below.
    local activeGroups = {}
    for _, group in ipairs(BUFF_GROUPS) do
        if BuffCheckDB.checkedGroups[group.key]
            and (not group.providerClass or classesPresent[group.providerClass])
            and not (group.key == "blessing" and ppData) then
            activeGroups[#activeGroups + 1] = group
        end
    end

    -- Second pass: per-unit buff check
    local missingByGroup = {}     -- group.key -> { playerName, ... }
    local missingBlessings = {}   -- blessingIndex -> { playerName, ... } (PallyPower mode)
    local skipped = {}
    local missingCount = 0

    for _, unit in ipairs(units) do
        if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            if name and class then
                local buffSet = GetUnitBuffSet(unit)
                for _, group in ipairs(activeGroups) do
                    if group.appliesTo[class] and not UnitHasGroupBuff(buffSet, group) then
                        if not missingByGroup[group.key] then
                            missingByGroup[group.key] = {}
                        end
                        local list = missingByGroup[group.key]
                        list[#list + 1] = name
                        missingCount = missingCount + 1
                    end
                end

                -- PallyPower mode: per-paladin expectations — a single-target
                -- assignment replaces that paladin's class blessing for this
                -- player (e.g. feral tank gets single Might, not class Salv)
                if ppData then
                    local expected = GetExpectedBlessings(ppData, name, class, expectedScratch)

                    for blessingID in pairs(expected) do
                        local normalName = ppData.spells and ppData.spells[blessingID]
                        local greaterName = ppData.gspells and ppData.gspells[blessingID]
                        -- Either the normal or greater version satisfies the assignment
                        local has = (normalName and normalName ~= "" and buffSet[normalName])
                            or (greaterName and greaterName ~= "" and buffSet[greaterName])
                        if not has and (normalName or greaterName) then
                            if not missingBlessings[blessingID] then
                                missingBlessings[blessingID] = {}
                            end
                            local list = missingBlessings[blessingID]
                            list[#list + 1] = name
                            missingCount = missingCount + 1
                        end
                    end
                end
            end
        else
            local name = UnitName(unit)
            if name then
                skipped[#skipped + 1] = name
            end
        end
    end

    -- Build report lines (keep BUFF_GROUPS order)
    local lines = {}
    for _, group in ipairs(activeGroups) do
        local list = missingByGroup[group.key]
        if list then
            lines[#lines + 1] = "Missing " .. group.name .. ": " .. table.concat(list, ", ")
        end
    end

    -- PallyPower lines, sorted by blessing index for stable output
    if ppData then
        local ids = {}
        for blessingID in pairs(missingBlessings) do
            ids[#ids + 1] = blessingID
        end
        table.sort(ids)
        for _, blessingID in ipairs(ids) do
            local label = (ppData.spells and ppData.spells[blessingID] ~= "" and ppData.spells[blessingID])
                or (ppData.gspells and ppData.gspells[blessingID])
                or ("Blessing #" .. blessingID)
            lines[#lines + 1] = "Missing " .. label .. ": " .. table.concat(missingBlessings[blessingID], ", ")
        end
    end

    return lines, missingCount, skipped
end

-- ============================================
-- REPORTING
-- ============================================

-- Split a long line into chat-safe chunks (SendChatMessage caps at 255 bytes)
local MAX_CHAT_LEN = 240

local function SendLine(line, channel)
    while #line > MAX_CHAT_LEN do
        -- Break at the last comma before the limit so names stay intact
        local breakAt = nil
        for i = MAX_CHAT_LEN, 1, -1 do
            if line:sub(i, i) == "," then
                breakAt = i
                break
            end
        end
        if not breakAt then breakAt = MAX_CHAT_LEN end
        pcall(SendChatMessage, line:sub(1, breakAt), channel)
        line = "..." .. line:sub(breakAt + 1):gsub("^%s+", " ")
    end
    pcall(SendChatMessage, line, channel)
end

-- announce=true -> raid/party chat; announce=false -> local chat frame only
function BuffCheck:Report(lines, missingCount, skipped, announce)
    local allBuffed = (missingCount == 0)

    if announce then
        local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY")
        if channel then
            if allBuffed then
                if BuffCheckDB.reportAllBuffed then
                    SendLine("[WM] Buff check: all buffs up!", channel)
                end
            else
                SendLine("[WM] Buff check:", channel)
                for _, line in ipairs(lines) do
                    SendLine(line, channel)
                end
            end
            return
        end
        -- Not in a group somehow — fall through to local print
    end

    -- Local-only report
    if allBuffed then
        if BuffCheckDB.reportAllBuffed then
            self:Print("|cFF00FF00Buff check: all buffs up!|r")
        end
    else
        self:Print("|cFFFF6600Buff check — missing buffs:|r")
        for _, line in ipairs(lines) do
            DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFCC00" .. line .. "|r")
        end
    end
    if #skipped > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  |cFF888888Skipped (offline/dead): " .. table.concat(skipped, ", ") .. "|r")
    end
end

-- Entry point: run a check and report it.
-- selfInitiated controls raid announce vs local-only.
function BuffCheck:RunCheck(selfInitiated)
    if not BuffCheckDB or not BuffCheckDB.enabled then return end

    local lines, missingCount, skipped = self:ScanGroup()
    lastReport = lines
    lastReportTime = date("%H:%M:%S")

    local announce = selfInitiated and BuffCheckDB.announceToRaid
    self:Report(lines, missingCount, skipped, announce)
end

-- Manual run: always local-only, and works even with the ready-check
-- trigger switched off (Run Check Now button, dashboard tools menu)
function BuffCheck:RunLocalCheck()
    local lines, missingCount, skipped = self:ScanGroup()
    lastReport = lines
    lastReportTime = date("%H:%M:%S")
    self:Report(lines, missingCount, skipped, false)
end

-- ============================================
-- DIAGNOSTIC
-- ============================================
-- Shows every buff on a unit and which check (if any) it satisfies.
-- Consumable auras are frequently named differently from the item that
-- applies them, and new/unlisted consumables show up as unmatched here —
-- which is exactly the information needed to add them.

function BuffCheck:ExplainUnit(unit)
    unit = unit or "player"
    if not UnitExists(unit) then
        self:Print("No " .. unit .. ".")
        return
    end

    local name = UnitName(unit) or unit
    local _, class = UnitClass(unit)
    self:Print("=== Buffs on " .. name .. " (" .. tostring(class) .. ") ===")

    local matched, unmatched = {}, {}
    local anyBuff = false

    for i = 1, 40 do
        local buffName, _, _, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
        if not buffName then break end
        anyBuff = true

        local hits = {}
        for _, group in ipairs(BUFF_GROUPS) do
            local why = BuffMatchesGroup(buffName, group, spellId)
            if why then
                local state = BuffCheckDB.checkedGroups[group.key] and "on" or "|cFF888888off|r"
                hits[#hits + 1] = group.name .. " [" .. state .. ", " .. why .. "]"
            end
        end

        if #hits > 0 then
            matched[#matched + 1] = "  |cFF00FF00" .. buffName .. "|r -> " .. table.concat(hits, ", ")
        else
            -- The spell ID is what's needed to add a missing elixir
            unmatched[#unmatched + 1] = "  |cFF888888" .. buffName
                .. (spellId and (" (spell id " .. spellId .. ")") or "") .. "|r"
        end
    end

    if not anyBuff then
        print("  (no buffs)")
    end

    for _, line in ipairs(matched) do print(line) end

    local flask, battle, guardian = WM:ElixirState(unit)
    print("  Flask or elixirs: " .. (WM:IsFlaskCovered(flask, battle, guardian) and "|cFF00FF00covered|r" or "|cFFFF4444missing|r")
        .. "  (flask " .. (flask and "yes" or "no") .. ", battle " .. (battle and "yes" or "no")
        .. ", guardian " .. (guardian and "yes" or "no") .. ")")

    if #unmatched > 0 then
        self:Print("Not matched by any check:")
        for _, line in ipairs(unmatched) do print(line) end
        print("|cFF888888If a consumable you expect to be checked is listed here,"
            .. " its aura name differs from the item name — report the exact"
            .. " name above and it can be added.|r")
    end

    -- Which checks are currently enabled at all
    local enabled = {}
    for _, group in ipairs(BUFF_GROUPS) do
        if BuffCheckDB.checkedGroups[group.key] then
            enabled[#enabled + 1] = group.name
        end
    end
    self:Print("Checks enabled: " .. (#enabled > 0
        and table.concat(enabled, ", ")
        or "|cFFFF4444none|r — nothing will ever be reported"))
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")

function BuffCheck:RegisterEvents()
    eventFrame:RegisterEvent("READY_CHECK")
end

eventFrame:SetScript("OnEvent", function(self, event, initiator)
    if event == "READY_CHECK" then
        if not BuffCheckDB or not BuffCheckDB.enabled then return end
        -- initiator is the name of whoever started the ready check.
        -- Names never include the realm for same-realm players; strip it to be safe.
        local playerName = UnitName("player")
        local initiatorName = initiator and (initiator:match("^([^%-]+)") or initiator)
        local selfInitiated = (initiatorName == playerName)
        BuffCheck:RunCheck(selfInitiated)
    end
end)

-- ============================================
-- STATUS
-- ============================================

function BuffCheck:GetQuickStatus()
    if not BuffCheckDB then return "|cFF888888Not initialized|r" end

    if not BuffCheckDB.enabled then
        return "|cFFFF0000Disabled|r"
    end

    local enabledCount = 0
    for _, group in ipairs(BUFF_GROUPS) do
        if BuffCheckDB.checkedGroups[group.key] then
            enabledCount = enabledCount + 1
        end
    end

    local announceTag = BuffCheckDB.announceToRaid and " |cFFFFCC00[Announce]|r" or " |cFF888888[Local only]|r"
    local ppTag = (BuffCheckDB.usePallyPower and self:IsPallyPowerAvailable()) and " |cFFF58CBA[PallyPower]|r" or ""
    local lastTag = lastReportTime and (" last: " .. lastReportTime) or ""
    return "|cFF00FF00Active|r (" .. enabledCount .. " buffs)" .. announceTag .. ppTag .. lastTag
end

-- ============================================
-- SETTINGS UI
-- ============================================

function BuffCheck:CreateUI()
    if mainFrame then return mainFrame end

    local panel = WM.UI:CreatePanel({
        name = "WM_BuffCheckFrame",
        title = "Buff Check",
        titleColor = "33FF99",
        width = 380,
    })
    local L = panel.layout
    local function opt(key)
        return function() return BuffCheckDB[key] end, function(v) BuffCheckDB[key] = v end
    end

    L:Checkbox({
        label = "Enable buff check on ready check",
        get = function() return BuffCheck:IsModuleEnabled() end,
        set = function(v) BuffCheck:SetModuleEnabled(v) end,
    })
    local get, set

    get, set = opt("announceToRaid")
    L:Checkbox({
        label = "Announce to raid when I start the ready check", get = get, set = set,
        tooltip = {
            "Announce Mode",
            "When YOU run the ready check, missing buffs are announced to raid/party chat.",
            "When someone ELSE runs it, the report is always shown only to you.",
        },
    })

    get, set = opt("reportAllBuffed")
    L:Checkbox({ label = "Also report when everyone is fully buffed", get = get, set = set })

    get, set = opt("usePallyPower")
    L:Checkbox({
        label = "Use PallyPower blessing assignments", get = get, set = set,
        tooltip = {
            "PallyPower Integration",
            "When PallyPower is running and paladins in your group have blessing assignments,"
                .. " each player is checked against their ASSIGNED blessings, and the report"
                .. " names the exact missing blessing.",
            "Single-target assignments override that paladin's class blessing for that player"
                .. " (a tank assigned single Might isn't expected to have class Salv).",
            "Greater and normal versions both count.",
            "Falls back to 'any blessing' when PallyPower is missing or has no assignments configured.",
        },
    })
    -- Detection status, re-read every time the panel opens
    L:Note(function()
        if BuffCheck:IsPallyPowerAvailable() then
            return "|cFF00FF00PallyPower detected|r"
        end
        return "PallyPower not detected — using generic blessing check"
    end, 25)

    L:Space(6)
    L:Header("Buffs to check")

    for _, group in ipairs(BUFF_GROUPS) do
        local label = group.name
        if group.providerClass then
            local classColor = RAID_CLASS_COLORS[group.providerClass]
            local hex = classColor and string.format("%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255) or "ffffff"
            label = label .. " |cFF" .. hex .. "(" .. group.providerClass:sub(1, 1) .. group.providerClass:sub(2):lower() .. ")|r"
        end
        if group.note then
            label = label .. " |cFF888888- " .. group.note .. "|r"
        end
        L:Checkbox({
            label = label, indent = 5,
            get = function() return BuffCheckDB.checkedGroups[group.key] end,
            set = function(v) BuffCheckDB.checkedGroups[group.key] = v end,
        })
    end

    L:Space(4)
    L:Note("Class buffs are only checked when the providing class is in the group."
        .. " Offline and dead players are skipped.")

    panel:AddFooterButton({
        text = "Run Check Now", width = 130,
        tooltip = { "Run Check Now", "Checks the group right now and shows the report only to you." },
        onClick = function() BuffCheck:RunLocalCheck() end,
    }, "LEFT")

    panel:Finish()

    mainFrame = panel
    self.mainFrame = panel

    return panel
end

-- Dashboard on/off switch (see WM:CreateModuleCards). The settings panel's
-- own enable checkbox goes through the same function.
function BuffCheck:IsModuleEnabled()
    return BuffCheckDB and BuffCheckDB.enabled and true or false
end

function BuffCheck:SetModuleEnabled(v)
    BuffCheckDB.enabled = v and true or false
    if mainFrame and mainFrame:IsShown() then mainFrame:Refresh() end
end

function BuffCheck:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function BuffCheck:ToggleUI()
    self:Toggle()
end
