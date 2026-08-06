-- Watching Machine: Buff Check Module
-- Scans the raid for missing buffs when a ready check runs.
-- If YOU started the ready check: announces missing buffs to raid chat.
-- If someone else started it: prints the report locally so only you see it.

local AddonName, WM = ...
local BuffCheck = {}
WM:RegisterModule("BuffCheck", BuffCheck)

BuffCheck.version = "2.8"

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
        name = "Well Fed",
        providerClass = nil,  -- consumable
        buffs = { "Well Fed" },
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Food buff",
    },
    {
        key = "flask",
        name = "Flask",
        providerClass = nil,  -- consumable
        buffs = {},
        prefixes = { "Flask of", "Shattrath Flask of" },
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Any flask aura",
    },
    {
        key = "battleelixir",
        name = "Battle Elixir",
        providerClass = nil,  -- consumable
        buffs = {
            -- TBC battle elixirs
            "Elixir of Major Strength", "Elixir of Major Agility",
            "Elixir of Major Shadow Power", "Elixir of Major Firepower",
            "Elixir of Major Frost Power", "Adept's Elixir",
            "Onslaught Elixir", "Elixir of Mastery",
            "Elixir of Healing Power", "Fel Strength Elixir",
            "Elixir of Empowerment", "Elixir of Demonslaying",
            -- Classic-era battle elixirs still in use
            "Elixir of the Mongoose", "Greater Arcane Elixir",
            "Elixir of Shadow Power", "Elixir of Greater Firepower",
        },
        -- Flasks occupy both elixir slots in TBC
        prefixes = { "Flask of", "Shattrath Flask of" },
        appliesTo = ALL_CLASSES,
        default = false,
        note = "Flask counts too",
    },
    {
        key = "guardianelixir",
        name = "Guardian Elixir",
        providerClass = nil,  -- consumable
        buffs = {
            -- TBC guardian elixirs
            "Elixir of Major Fortitude", "Elixir of Major Defense",
            "Elixir of Ironskin", "Elixir of Draenic Wisdom",
            "Elixir of Major Mageblood", "Earthen Elixir",
            -- Classic-era guardian elixirs still in use
            "Elixir of Superior Defense", "Elixir of Fortitude",
            "Gift of Arthas", "Elixir of Greater Defense",
        },
        prefixes = { "Flask of", "Shattrath Flask of" },
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
local function GetUnitBuffSet(unit)
    wipe(buffScratch)
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        buffScratch[name] = true
    end
    return buffScratch
end

local function UnitHasGroupBuff(buffSet, group)
    for buffName in pairs(buffSet) do
        if group.buffSet[buffName] then
            return true
        end
        if group.prefixes then
            for _, prefix in ipairs(group.prefixes) do
                if buffName:sub(1, #prefix) == prefix then
                    return true
                end
            end
        end
    end
    return false
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

    local theme = WM:GetTheme()

    local frame = CreateFrame("Frame", "WM_BuffCheckFrame", UIParent, "BackdropTemplate")
    frame:SetSize(360, 585)
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
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF33FF99Buff Check|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local yOffset = -45

    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 20, yOffset)
    enableCB.Text:SetText("Enable buff check on ready check")
    enableCB:SetChecked(BuffCheckDB.enabled)
    enableCB:SetScript("OnClick", function(self)
        BuffCheckDB.enabled = self:GetChecked()
    end)

    yOffset = yOffset - 26

    -- Announce checkbox
    local announceCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    announceCB:SetPoint("TOPLEFT", 20, yOffset)
    announceCB.Text:SetText("Announce to raid when I start the ready check")
    announceCB:SetChecked(BuffCheckDB.announceToRaid)
    announceCB:SetScript("OnClick", function(self)
        BuffCheckDB.announceToRaid = self:GetChecked()
    end)
    announceCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Announce Mode", 1, 0.8, 0)
        GameTooltip:AddLine("When YOU run the ready check, missing buffs", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("are announced to raid/party chat.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("When someone ELSE runs it, the report is", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("always shown only to you.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    announceCB:SetScript("OnLeave", function() GameTooltip:Hide() end)

    yOffset = yOffset - 26

    -- Report all-buffed checkbox
    local allBuffedCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    allBuffedCB:SetPoint("TOPLEFT", 20, yOffset)
    allBuffedCB.Text:SetText("Also report when everyone is fully buffed")
    allBuffedCB:SetChecked(BuffCheckDB.reportAllBuffed)
    allBuffedCB:SetScript("OnClick", function(self)
        BuffCheckDB.reportAllBuffed = self:GetChecked()
    end)

    yOffset = yOffset - 26

    -- PallyPower integration checkbox
    local ppCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    ppCB:SetPoint("TOPLEFT", 20, yOffset)
    ppCB.Text:SetText("Use PallyPower blessing assignments")
    ppCB:SetChecked(BuffCheckDB.usePallyPower)
    ppCB:SetScript("OnClick", function(self)
        BuffCheckDB.usePallyPower = self:GetChecked()
    end)
    ppCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("PallyPower Integration", 1, 0.8, 0)
        GameTooltip:AddLine("When PallyPower is running and paladins in your", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("group have blessing assignments, each player is", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("checked against their ASSIGNED blessings, and the", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("report names the exact missing blessing.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Single-target assignments override that paladin's", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("class blessing for that player (a tank assigned", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("single Might isn't expected to have class Salv).", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Greater and normal versions both count.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Falls back to 'any blessing' when PallyPower is", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("missing or has no assignments configured.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    ppCB:SetScript("OnLeave", function() GameTooltip:Hide() end)

    yOffset = yOffset - 22

    -- PallyPower detection status (refreshed every time the panel opens)
    local ppStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ppStatus:SetPoint("TOPLEFT", 45, yOffset)
    frame.ppStatus = ppStatus
    frame:SetScript("OnShow", function(self)
        if BuffCheck:IsPallyPowerAvailable() then
            self.ppStatus:SetText("|cFF00FF00PallyPower detected|r")
        else
            self.ppStatus:SetText("|cFF888888PallyPower not detected — using generic blessing check|r")
        end
    end)

    yOffset = yOffset - 26

    -- Buff selection header
    local buffHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buffHeader:SetPoint("TOPLEFT", 20, yOffset)
    buffHeader:SetText("Buffs to check:")
    buffHeader:SetTextColor(unpack(theme.headerColor))

    yOffset = yOffset - 22

    -- Per-buff-group checkboxes
    for _, group in ipairs(BUFF_GROUPS) do
        local cb = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 25, yOffset)
        local label = group.name
        if group.providerClass then
            local classColor = RAID_CLASS_COLORS[group.providerClass]
            local hex = classColor and string.format("%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255) or "ffffff"
            label = label .. " |cFF" .. hex .. "(" .. group.providerClass:sub(1, 1) .. group.providerClass:sub(2):lower() .. ")|r"
        end
        if group.note then
            label = label .. " |cFF888888- " .. group.note .. "|r"
        end
        cb.Text:SetText(label)
        cb:SetChecked(BuffCheckDB.checkedGroups[group.key])
        cb:SetScript("OnClick", function(self)
            BuffCheckDB.checkedGroups[group.key] = self:GetChecked()
        end)
        yOffset = yOffset - 24
    end

    yOffset = yOffset - 8

    -- Info text
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", 20, yOffset)
    infoText:SetWidth(320)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("|cFF888888Class buffs are only checked when the providing class is in the group. Offline and dead players are skipped.|r")

    -- Run Check Now button
    local runBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    runBtn:SetSize(130, 24)
    runBtn:SetPoint("BOTTOMLEFT", 20, 15)
    runBtn:SetText("Run Check Now")
    runBtn:SetScript("OnClick", function()
        -- Manual runs are always local-only
        local lines, missingCount, skipped = BuffCheck:ScanGroup()
        lastReport = lines
        lastReportTime = date("%H:%M:%S")
        BuffCheck:Report(lines, missingCount, skipped, false)
    end)

    mainFrame = frame
    self.mainFrame = frame

    return frame
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
