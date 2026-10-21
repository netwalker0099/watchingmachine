-- Watching Machine: Mage Class Tools
-- Armor-spell warning, and a hover-expanding flyout for every teleport and
-- portal the character actually knows.

local AddonName, WM = ...
local Mage = {}
WM:RegisterModule("ClassMage", Mage)

Mage.version = "3.6"

local CLASS = "MAGE"

local ARMOR_BUFFS = { "Molten Armor", "Mage Armor", "Ice Armor", "Frost Armor" }
local ICON_ARMOR  = "Interface\\Icons\\Spell_MageArmor"
local ICON_PORTAL = "Interface\\Icons\\Spell_Arcane_PortalStormwind"

local function IsPlayerMage()
    local _, c = UnitClass("player")
    return c == CLASS
end

local function PlayerHasAnyBuff(list)
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return nil end
        for _, want in ipairs(list) do
            if n == want then return n end
        end
    end
    return nil
end

function Mage:Print(msg)
    WM:ModulePrint("ClassMage", msg)
end

-- ============================================
-- TELEPORT / PORTAL DISCOVERY
-- ============================================
-- Read the spellbook rather than hardcoding a faction's spell list: the
-- character can only ever cast what it actually knows, and this stays correct
-- for either faction and for whatever the player has learned so far.
--
-- The "Teleport:" / "Portal:" prefixes are localized, so they are derived
-- from a known spell's own name where possible instead of assumed English.

local function LocalizedPrefix(spellID, fallback)
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" then
            local prefix = name:match("^([^:]+:)")
            if prefix then return prefix end
        end
    end
    return fallback
end

-- Each entry: { name = "Portal: Stormwind", index = spellbook slot, icon = texture }
local teleportSpells, portalSpells = {}, {}

local function SpellIcon(index, name)
    local tex = GetSpellBookItemTexture and GetSpellBookItemTexture(index, BOOKTYPE_SPELL or "spell")
    if not tex and GetSpellTexture then tex = GetSpellTexture(name) end
    return tex or ICON_PORTAL
end

function Mage:ScanSpellbook()
    wipe(teleportSpells)
    wipe(portalSpells)
    if not IsPlayerMage() then return end
    if not GetSpellBookItemName then return end

    local telePrefix = LocalizedPrefix(3561, "Teleport:")   -- Teleport: Stormwind
    local portPrefix = LocalizedPrefix(10059, "Portal:")    -- Portal: Stormwind

    local i = 1
    while true do
        local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end
        local list
        if name:sub(1, #telePrefix) == telePrefix then
            list = teleportSpells
        elseif name:sub(1, #portPrefix) == portPrefix then
            list = portalSpells
        end
        if list then list[#list + 1] = { name = name, index = i, icon = SpellIcon(i, name) } end
        i = i + 1
        if i > 1024 then break end   -- guard against a malformed spellbook
    end

    local function byName(a, b) return a.name < b.name end
    table.sort(teleportSpells, byName)
    table.sort(portalSpells, byName)
    return #teleportSpells, #portalSpells
end

-- ============================================
-- FLYOUT BUTTON
-- ============================================
-- An icon button that, on hover, expands into one icon per teleport and
-- portal you know. Portals and teleports each fan out in their own
-- direction (Class Tools > Mage); when both point the same way the
-- teleports continue the line after the portals.
--
-- Casting requires SecureActionButtonTemplate, and secure frames cannot be
-- shown, hidden or moved while in combat. Teleports and portals are not
-- castable in combat anyway, so the flyout simply refuses to expand in
-- combat rather than pulling in a secure-handler state driver to work around
-- a restriction that costs nothing here.

local anchor = nil
local flyoutButtons = {}
local ANCHOR_SIZE, ICON_SIZE, GAP = 36, 32, 4

local DIRECTIONS = {
    UP    = { 0, 1 },
    DOWN  = { 0, -1 },
    LEFT  = { -1, 0 },
    RIGHT = { 1, 0 },
}
Mage.DIRECTION_OPTIONS = {
    { value = "UP", text = "Up" }, { value = "RIGHT", text = "Right" },
    { value = "DOWN", text = "Down" }, { value = "LEFT", text = "Left" },
}
local DEFAULT_PORTAL_DIR, DEFAULT_TELEPORT_DIR = "LEFT", "UP"

local function PortalDir()
    local d = MageToolsDB and MageToolsDB.portalDir
    return DIRECTIONS[d] and d or DEFAULT_PORTAL_DIR
end

local function TeleportDir()
    local d = MageToolsDB and MageToolsDB.teleportDir
    return DIRECTIONS[d] and d or DEFAULT_TELEPORT_DIR
end

-- Which half of a click casts. On current client builds a secure action
-- button only acts on the press that matches the ActionButtonUseKeyDown
-- setting (on by default: the mouse-DOWN). Registering for "AnyUp" alone
-- meant the button never saw the press it acts on, so nothing was cast.
-- Registering both would cast twice on builds without that check, so
-- register exactly the one that casts. Re-read on every rebuild, in case
-- the setting changed.
local function CastClicks()
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return keyDown and "AnyDown" or "AnyUp"
end
Mage.CastClicks = CastClicks   -- for tests

local function HideFlyout()
    if InCombatLockdown() then return end
    for _, b in ipairs(flyoutButtons) do b:Hide() end
end

local function ShowSpellTooltip(b)
    if not b.spellName then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    -- The full spell tooltip (name, cast time, reagent) where the client
    -- can show a spellbook slot; just the name otherwise
    local ok = b.bookIndex and GameTooltip.SetSpellBookItem
        and pcall(GameTooltip.SetSpellBookItem, GameTooltip, b.bookIndex, BOOKTYPE_SPELL or "spell")
    if not ok then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(b.spellName, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function NewFlyoutButton(i)
    -- Secure template only: its click handler is the one that casts
    local b = CreateFrame("Button", "WM_MagePortalBtn" .. i, anchor, "SecureActionButtonTemplate")
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    -- Keep the flyout open while moving between its buttons
    b:SetScript("OnEnter", function(self)
        Mage:CancelFlyoutClose()
        ShowSpellTooltip(self)
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Mage:ScheduleFlyoutClose()
    end)
    return b
end

-- Offset of the n-th icon (1-based) along a direction from the anchor centre
local function Offset(dir, n)
    local d = DIRECTIONS[dir]
    local dist = ANCHOR_SIZE / 2 + GAP + ICON_SIZE / 2 + (n - 1) * (ICON_SIZE + GAP)
    return d[1] * dist, d[2] * dist
end
Mage.FlyoutOffset = Offset   -- for tests

function Mage:BuildFlyout()
    if InCombatLockdown() then return end
    if not anchor then return end

    self:ScanSpellbook()

    -- Lay out each group along its direction; a shared direction means one
    -- line, portals first
    local portalDir, teleportDir = PortalDir(), TeleportDir()
    local placed = {}
    for n, e in ipairs(portalSpells) do
        placed[#placed + 1] = { entry = e, dir = portalDir, n = n }
    end
    local start = (teleportDir == portalDir) and #portalSpells or 0
    for n, e in ipairs(teleportSpells) do
        placed[#placed + 1] = { entry = e, dir = teleportDir, n = start + n }
    end

    local clicks = CastClicks()
    for i, p in ipairs(placed) do
        local b = flyoutButtons[i] or NewFlyoutButton(i)
        flyoutButtons[i] = b
        b:ClearAllPoints()
        local x, y = Offset(p.dir, p.n)
        b:SetPoint("CENTER", anchor, "CENTER", x, y)
        b:RegisterForClicks(clicks)
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", p.entry.name)
        b.spellName, b.bookIndex = p.entry.name, p.entry.index
        b.icon:SetTexture(p.entry.icon)
        b:Hide()
    end

    -- Retire any buttons left over from a previous, longer list
    for i = #placed + 1, #flyoutButtons do
        local b = flyoutButtons[i]
        b:Hide()
        b:SetAttribute("spell", nil)
        b.spellName, b.bookIndex = nil, nil
    end

    anchor.count = #placed
    -- The anchor shows your first portal (or teleport) as its own icon
    local first = portalSpells[1] or teleportSpells[1]
    anchor.icon:SetTexture(first and first.icon or ICON_PORTAL)
end

local closePending = false

function Mage:CancelFlyoutClose()
    closePending = false
    if InCombatLockdown() then return end
    for i = 1, (anchor and anchor.count or 0) do
        if flyoutButtons[i] then flyoutButtons[i]:Show() end
    end
end

function Mage:ScheduleFlyoutClose()
    closePending = true
    WM.RunAfter(0.35, function()
        if closePending then HideFlyout() end
    end)
end

function Mage:CreateAnchor()
    if anchor then return anchor end

    local a = CreateFrame("Button", "WM_MagePortalAnchor", UIParent)
    a:SetSize(ANCHOR_SIZE, ANCHOR_SIZE)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetAllPoints()
    a.icon:SetTexture(ICON_PORTAL)
    a:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    a:Hide()

    if MageToolsDB and MageToolsDB.portalX and MageToolsDB.portalY then
        a:SetPoint("CENTER", UIParent, "BOTTOMLEFT", MageToolsDB.portalX, MageToolsDB.portalY)
    else
        a:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
    end

    a:SetScript("OnDragStart", function(self)
        if MageToolsDB and MageToolsDB.portalLocked then return end
        if InCombatLockdown() then return end
        self:StartMoving()
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if MageToolsDB then MageToolsDB.portalX, MageToolsDB.portalY = x, y end
    end)

    a:SetScript("OnEnter", function(self)
        if InCombatLockdown() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Portals", 1, 0.8, 0)
            GameTooltip:AddLine("Unavailable in combat.", 0.8, 0.4, 0.4)
            GameTooltip:Show()
            return
        end
        Mage:CancelFlyoutClose()
        if (self.count or 0) == 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Portals", 1, 0.8, 0)
            GameTooltip:AddLine("No teleport or portal spells known yet.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    a:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Mage:ScheduleFlyoutClose()
    end)

    anchor = a
    self.anchor = a
    return a
end

function Mage:UpdatePortalButtonVisibility()
    local CT = WM.modules.ClassTools
    if not anchor then return end
    local want = IsPlayerMage() and CT and CT:IsEnabled(CLASS, "portalButton")
    if InCombatLockdown() then return end   -- anchor holds secure children
    if want then
        self:BuildFlyout()
        anchor:Show()
    else
        HideFlyout()
        anchor:Hide()
    end
end

-- ============================================
-- MONITOR
-- ============================================

local CT

local function Tools()
    CT = CT or WM.modules.ClassTools
    return CT
end

local function Monitor()
    local tools = Tools()
    if not tools then return end
    if not IsPlayerMage() then return end

    if UnitIsDeadOrGhost("player") then
        tools:ClearAlert("mage_armor")
        return
    end

    if tools:IsEnabled(CLASS, "armor") then
        if PlayerHasAnyBuff(ARMOR_BUFFS) then
            tools:ClearAlert("mage_armor")
        else
            tools:SetAlert("mage_armor", "No Mage Armor spell active", ICON_ARMOR)
        end
    else
        tools:ClearAlert("mage_armor")
    end
end

-- ============================================
-- REGISTRATION
-- ============================================

local eventFrame = CreateFrame("Frame")

function Mage:InitDB()
    if not MageToolsDB then MageToolsDB = {} end
    if MageToolsDB.portalLocked == nil then MageToolsDB.portalLocked = false end
    if MageToolsDB.portalDir == nil then MageToolsDB.portalDir = DEFAULT_PORTAL_DIR end
    if MageToolsDB.teleportDir == nil then MageToolsDB.teleportDir = DEFAULT_TELEPORT_DIR end
end

function Mage:Initialize()
    self:InitDB()
    local tools = Tools()
    if not tools then return end

    tools:RegisterFeature(CLASS, {
        key = "armor", name = "Warn if armor spell is missing",
        desc = "Molten, Mage, Ice or Frost Armor.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "portalButton", name = "Show the portal / teleport button",
        desc = "A draggable portal icon that expands on hover into an icon for every portal and teleport you know. Hover an icon for the spell; click to cast. Not available in combat.",
        default = true,
        onToggle = function() Mage:UpdatePortalButtonVisibility() end,
    })
    tools:RegisterFeature(CLASS, {
        key = "portalDir", kind = "choice", name = "Portals expand",
        options = Mage.DIRECTION_OPTIONS, default = DEFAULT_PORTAL_DIR,
        desc = "Which way the portal icons open from the button.",
        get = function() return MageToolsDB.portalDir end,
        set = function(v) MageToolsDB.portalDir = v end,
        onChange = function() Mage:UpdatePortalButtonVisibility() end,
        tooltip = { "Portals expand", "Click to cycle: Up > Right > Down > Left.",
            "If teleports expand the same way, they continue the line after the portals." },
    })
    tools:RegisterFeature(CLASS, {
        key = "teleportDir", kind = "choice", name = "Teleports expand",
        options = Mage.DIRECTION_OPTIONS, default = DEFAULT_TELEPORT_DIR,
        desc = "Which way the teleport icons open from the button.",
        get = function() return MageToolsDB.teleportDir end,
        set = function(v) MageToolsDB.teleportDir = v end,
        onChange = function() Mage:UpdatePortalButtonVisibility() end,
        tooltip = { "Teleports expand", "Click to cycle: Up > Right > Down > Left.",
            "If portals expand the same way, teleports go on the end of the line after them." },
    })
    tools:RegisterFeature(CLASS, {
        key = "portalLock", name = "Lock the portal button",
        desc = "Stops it being dragged by accident.",
        default = false,
        onToggle = function(v) MageToolsDB.portalLocked = v and true or false end,
    })

    -- Keep the saved flag and the feature toggle in step on load
    local tdb = ClassToolsDB and ClassToolsDB.enabled and ClassToolsDB.enabled[CLASS]
    if tdb and tdb.portalLock ~= nil then
        MageToolsDB.portalLocked = tdb.portalLock and true or false
    end

    tools:RegisterMonitor(Monitor)

    if IsPlayerMage() then
        self:CreateAnchor()
        -- SPELLS_CHANGED also fires when a spell is learned, which is what
        -- picks up a new portal; LEARNED_SPELL_IN_TAB doesn't exist on 2.5.6
        WM:RegisterEvents(eventFrame, { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" })
        -- Spellbook isn't reliably populated the instant we initialise
        WM.RunAfter(2, function() Mage:UpdatePortalButtonVisibility() end)
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if not IsPlayerMage() then return end
    -- Secure children can't be touched mid-combat; rebuild once it drops
    if InCombatLockdown() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Mage:UpdatePortalButtonVisibility()
    else
        WM.RunAfter(1, function() Mage:UpdatePortalButtonVisibility() end)
    end
end)

function Mage:ReportSpells()
    local t, p = self:ScanSpellbook()
    self:Print("Known teleports: " .. (t or 0) .. ", portals: " .. (p or 0))
    for _, e in ipairs(portalSpells)   do print("  |cFF66CCFF" .. e.name .. "|r") end
    for _, e in ipairs(teleportSpells) do print("  |cFFCCCCCC" .. e.name .. "|r") end
end
