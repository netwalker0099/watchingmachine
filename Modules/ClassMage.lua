-- Watching Machine: Mage Class Tools
-- Armor-spell warning, and two hover-expanding buttons: one for every
-- teleport and portal the character knows, one for mana gems, armors and
-- food / water / table.

local AddonName, WM = ...
local Mage = {}
WM:RegisterModule("ClassMage", Mage)

Mage.version = "3.7"

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
-- SPELL DISCOVERY (teleports, portals, utility spells)
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

-- Utility spells, highest level first: that order is the order they fan out
-- from the button, so the best one sits closest. Matched by English name
-- and by the client's own name for the spell ID, so localized clients work.
-- Ranked spells (armors, food, water) show once, casting the highest rank:
-- casting by name picks it, and the tooltip uses the highest-rank slot.
local UTILITY_SPELLS = {
    gems = {
        { "Conjure Mana Emerald", 27101 },
        { "Conjure Mana Ruby",    10054 },
        { "Conjure Mana Citrine", 10053 },
        { "Conjure Mana Jade",    3552 },
        { "Conjure Mana Agate",   759 },
    },
    armor = {
        { "Molten Armor", 30482 },
        { "Mage Armor",   6117 },
        { "Ice Armor",    7302 },
        { "Frost Armor",  168 },
    },
    food = {
        { "Ritual of Refreshment", 43987 },
        { "Conjure Water",         5504 },
        { "Conjure Food",          587 },
    },
}

-- Each entry: { name = "Portal: Stormwind", index = spellbook slot, icon = texture }
local teleportSpells, portalSpells = {}, {}
local utilitySpells = { gems = {}, armor = {}, food = {} }

local utilityByName = nil   -- spell name -> { group, order }

local function UtilityNames()
    if utilityByName then return utilityByName end
    utilityByName = {}
    for group, list in pairs(UTILITY_SPELLS) do
        for order, s in ipairs(list) do
            local slot = { group = group, order = order }
            utilityByName[s[1]] = slot
            if GetSpellInfo then
                local ok, name = pcall(GetSpellInfo, s[2])
                if ok and type(name) == "string" then utilityByName[name] = slot end
            end
        end
    end
    return utilityByName
end

local function SpellIcon(index, name)
    local tex = GetSpellBookItemTexture and GetSpellBookItemTexture(index, BOOKTYPE_SPELL or "spell")
    if not tex and GetSpellTexture then tex = GetSpellTexture(name) end
    return tex or ICON_PORTAL
end

function Mage:ScanSpellbook()
    wipe(teleportSpells)
    wipe(portalSpells)
    for _, list in pairs(utilitySpells) do wipe(list) end
    if not IsPlayerMage() then return end
    if not GetSpellBookItemName then return end

    local telePrefix = LocalizedPrefix(3561, "Teleport:")   -- Teleport: Stormwind
    local portPrefix = LocalizedPrefix(10059, "Portal:")    -- Portal: Stormwind
    local utility = UtilityNames()
    local found = { gems = {}, armor = {}, food = {} }      -- group -> order -> entry

    local i = 1
    while true do
        local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end
        local entry = { name = name, index = i }
        if name:sub(1, #telePrefix) == telePrefix then
            entry.icon = SpellIcon(i, name)
            teleportSpells[#teleportSpells + 1] = entry
        elseif name:sub(1, #portPrefix) == portPrefix then
            entry.icon = SpellIcon(i, name)
            portalSpells[#portalSpells + 1] = entry
        elseif utility[name] then
            -- Ranks are listed lowest first, so a later slot is a higher rank
            local slot = utility[name]
            entry.icon = SpellIcon(i, name)
            found[slot.group][slot.order] = entry
        end
        i = i + 1
        if i > 1024 then break end   -- guard against a malformed spellbook
    end

    local function byName(a, b) return a.name < b.name end
    table.sort(teleportSpells, byName)
    table.sort(portalSpells, byName)
    for group, list in pairs(UTILITY_SPELLS) do
        for order = 1, #list do
            if found[group][order] then table.insert(utilitySpells[group], found[group][order]) end
        end
    end
    return #teleportSpells, #portalSpells
end

function Mage:GetUtilitySpells(group)
    return utilitySpells[group]
end

-- ============================================
-- FLYOUT BUTTONS
-- ============================================
-- An icon button that, on hover, expands into one icon per spell. Each
-- group of spells (portals, teleports, mana gems, ...) fans out in its own
-- direction (Class Tools > Mage); groups sharing a direction form one line,
-- in group order.
--
-- Casting requires SecureActionButtonTemplate, and secure frames cannot be
-- shown, hidden or moved while in combat. None of these spells are worth
-- casting in combat from here (portals and conjures can't be), so the
-- flyouts simply refuse to expand in combat rather than pulling in a
-- secure-handler state driver to work around a restriction that costs
-- nothing here.

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

-- Saved direction keys and their defaults
local DIR_DEFAULTS = {
    portalDir = "LEFT", teleportDir = "UP",
    gemDir = "LEFT", armorDir = "UP", foodDir = "RIGHT",
}

local function Dir(key)
    local d = MageToolsDB and MageToolsDB[key]
    return DIRECTIONS[d] and d or DIR_DEFAULTS[key]
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

-- Offset of the n-th icon (1-based) along a direction from the anchor centre
local function Offset(dir, n)
    local d = DIRECTIONS[dir]
    local dist = ANCHOR_SIZE / 2 + GAP + ICON_SIZE / 2 + (n - 1) * (ICON_SIZE + GAP)
    return d[1] * dist, d[2] * dist
end
Mage.FlyoutOffset = Offset   -- for tests

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

local Flyout = {}
Flyout.__index = Flyout

-- cfg:
--   anchorName, buttonPrefix   global frame names
--   title, emptyText           anchor tooltip when there's nothing to show
--   feature                    Class Tools feature key that shows it
--   posX, posY, defaultX       saved centre in MageToolsDB, first-run offset
--   groups()                   { { entries = list, dirKey = "portalDir" }, ... }
--   setIcon(texture, flyout)   paint the anchor icon after a build
local function NewFlyout(cfg)
    return setmetatable({ cfg = cfg, buttons = {}, count = 0, closePending = false }, Flyout)
end

function Flyout:HideButtons()
    if InCombatLockdown() then return end
    for _, b in ipairs(self.buttons) do b:Hide() end
end

function Flyout:CancelClose()
    self.closePending = false
    if InCombatLockdown() then return end
    for i = 1, self.count do
        if self.buttons[i] then self.buttons[i]:Show() end
    end
end

function Flyout:ScheduleClose()
    self.closePending = true
    WM.RunAfter(0.35, function()
        if self.closePending then self:HideButtons() end
    end)
end

function Flyout:NewButton(i)
    -- Secure template only: its click handler is the one that casts
    local b = CreateFrame("Button", self.cfg.buttonPrefix .. i, self.anchor, "SecureActionButtonTemplate")
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    -- Keep the flyout open while moving between its buttons
    b:SetScript("OnEnter", function(btn)
        self:CancelClose()
        ShowSpellTooltip(btn)
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        self:ScheduleClose()
    end)
    return b
end

function Flyout:Build()
    if InCombatLockdown() then return end
    if not self.anchor then return end

    Mage:ScanSpellbook()

    -- Each group continues the line of any earlier group sharing its direction
    local placed, lineLength = {}, {}
    for _, group in ipairs(self.cfg.groups()) do
        local dir = Dir(group.dirKey)
        for _, e in ipairs(group.entries) do
            lineLength[dir] = (lineLength[dir] or 0) + 1
            placed[#placed + 1] = { entry = e, dir = dir, n = lineLength[dir] }
        end
    end

    local clicks = CastClicks()
    for i, p in ipairs(placed) do
        local b = self.buttons[i] or self:NewButton(i)
        self.buttons[i] = b
        b:ClearAllPoints()
        local x, y = Offset(p.dir, p.n)
        b:SetPoint("CENTER", self.anchor, "CENTER", x, y)
        b:RegisterForClicks(clicks)
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", p.entry.name)
        b.spellName, b.bookIndex = p.entry.name, p.entry.index
        b.icon:SetTexture(p.entry.icon)
        b:Hide()
    end

    -- Retire any buttons left over from a previous, longer list
    for i = #placed + 1, #self.buttons do
        local b = self.buttons[i]
        b:Hide()
        b:SetAttribute("spell", nil)
        b.spellName, b.bookIndex = nil, nil
    end

    self.count = #placed
    self.anchor.count = #placed
    if self.cfg.setIcon then self.cfg.setIcon(self.anchor.icon, self) end
end

function Flyout:CreateAnchor()
    if self.anchor then return self.anchor end
    local cfg = self.cfg

    local a = CreateFrame("Button", cfg.anchorName, UIParent)
    a:SetSize(ANCHOR_SIZE, ANCHOR_SIZE)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetAllPoints()
    a:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    a:Hide()
    self.anchor = a
    if cfg.setIcon then cfg.setIcon(a.icon, self) end

    if MageToolsDB and MageToolsDB[cfg.posX] and MageToolsDB[cfg.posY] then
        a:SetPoint("CENTER", UIParent, "BOTTOMLEFT", MageToolsDB[cfg.posX], MageToolsDB[cfg.posY])
    else
        a:SetPoint("CENTER", UIParent, "CENTER", cfg.defaultX, 0)
    end

    a:SetScript("OnDragStart", function(btn)
        if MageToolsDB and MageToolsDB.portalLocked then return end
        if InCombatLockdown() then return end
        btn:StartMoving()
    end)
    a:SetScript("OnDragStop", function(btn)
        btn:StopMovingOrSizing()
        local x, y = btn:GetCenter()
        if MageToolsDB then MageToolsDB[cfg.posX], MageToolsDB[cfg.posY] = x, y end
    end)

    a:SetScript("OnEnter", function(btn)
        if InCombatLockdown() then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cfg.title, 1, 0.8, 0)
            GameTooltip:AddLine("Unavailable in combat.", 0.8, 0.4, 0.4)
            GameTooltip:Show()
            return
        end
        self:CancelClose()
        if self.count == 0 then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cfg.title, 1, 0.8, 0)
            GameTooltip:AddLine(cfg.emptyText, 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    a:SetScript("OnLeave", function()
        GameTooltip:Hide()
        self:ScheduleClose()
    end)
    return a
end

function Flyout:UpdateVisibility()
    local CT = WM.modules.ClassTools
    if not self.anchor then return end
    if InCombatLockdown() then return end   -- anchor holds secure children
    if IsPlayerMage() and CT and CT:IsEnabled(CLASS, self.cfg.feature) then
        self:Build()
        self.anchor:Show()
    else
        self:HideButtons()
        self.anchor:Hide()
    end
end

-- ---------- the two buttons ----------

local portalFlyout = NewFlyout({
    anchorName = "WM_MagePortalAnchor", buttonPrefix = "WM_MagePortalBtn",
    title = "Portals", emptyText = "No teleport or portal spells known yet.",
    feature = "portalButton", posX = "portalX", posY = "portalY", defaultX = 240,
    groups = function()
        return {
            { entries = portalSpells,   dirKey = "portalDir" },
            { entries = teleportSpells, dirKey = "teleportDir" },
        }
    end,
    -- Your first portal (or teleport) as the button's own icon
    setIcon = function(icon)
        local first = portalSpells[1] or teleportSpells[1]
        icon:SetTexture(first and first.icon or ICON_PORTAL)
    end,
})

local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"

local utilityFlyout = NewFlyout({
    anchorName = "WM_MageUtilityAnchor", buttonPrefix = "WM_MageUtilityBtn",
    title = "Mage utility", emptyText = "No mana gem, armor or conjure spells known yet.",
    feature = "utilityButton", posX = "utilityX", posY = "utilityY", defaultX = 196,
    groups = function()
        return {
            { entries = utilitySpells.gems,  dirKey = "gemDir" },
            { entries = utilitySpells.armor, dirKey = "armorDir" },
            { entries = utilitySpells.food,  dirKey = "foodDir" },
        }
    end,
    -- The mage class crest, from the class-circles sheet every client ships
    setIcon = function(icon)
        local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS.MAGE
        if type(coords) == "table" then
            icon:SetTexture(CLASS_CIRCLES)
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            icon:SetTexture(ICON_ARMOR)
        end
    end,
})

Mage.portalFlyout, Mage.utilityFlyout = portalFlyout, utilityFlyout

-- Portal button entry points (kept by name; tests and older code use them)
function Mage:CreateAnchor()
    local a = portalFlyout:CreateAnchor()
    self.anchor = a
    return a
end
function Mage:BuildFlyout() portalFlyout:Build() end
function Mage:CancelFlyoutClose() portalFlyout:CancelClose() end
function Mage:ScheduleFlyoutClose() portalFlyout:ScheduleClose() end
function Mage:UpdatePortalButtonVisibility() portalFlyout:UpdateVisibility() end

function Mage:CreateUtilityAnchor() return utilityFlyout:CreateAnchor() end
function Mage:BuildUtilityFlyout() utilityFlyout:Build() end
function Mage:UpdateUtilityButtonVisibility() utilityFlyout:UpdateVisibility() end

function Mage:UpdateButtons()
    portalFlyout:UpdateVisibility()
    utilityFlyout:UpdateVisibility()
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
    for key, default in pairs(DIR_DEFAULTS) do
        if MageToolsDB[key] == nil then MageToolsDB[key] = default end
    end
end

-- A direction option for one group of a flyout
local function DirectionFeature(tools, key, name, what, rebuild)
    tools:RegisterFeature(CLASS, {
        key = key, kind = "choice", name = name,
        options = Mage.DIRECTION_OPTIONS, default = DIR_DEFAULTS[key],
        desc = "Which way the " .. what .. " icons open from the button.",
        get = function() return MageToolsDB[key] end,
        set = function(v) MageToolsDB[key] = v end,
        onChange = rebuild,
        tooltip = { name, "Click to cycle: Up > Right > Down > Left.",
            "Groups on the same button that expand the same way share one line, in the order listed here." },
    })
end

function Mage:Initialize()
    self:InitDB()
    local tools = Tools()
    if not tools then return end

    local rebuildPortals = function() Mage:UpdatePortalButtonVisibility() end
    local rebuildUtility = function() Mage:UpdateUtilityButtonVisibility() end

    tools:RegisterFeature(CLASS, {
        key = "armor", name = "Warn if armor spell is missing",
        desc = "Molten, Mage, Ice or Frost Armor.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "portalButton", name = "Show the portal / teleport button",
        desc = "A draggable portal icon that expands on hover into an icon for every portal and teleport you know. Hover an icon for the spell; click to cast. Not available in combat.",
        default = true,
        onToggle = rebuildPortals,
    })
    DirectionFeature(tools, "portalDir", "Portals expand", "portal", rebuildPortals)
    DirectionFeature(tools, "teleportDir", "Teleports expand", "teleport", rebuildPortals)
    tools:RegisterFeature(CLASS, {
        key = "utilityButton", name = "Show the mage utility button",
        desc = "A draggable mage-crest icon that expands into your mana gems, armors, and food, water and table spells, highest level nearest the button. Click to cast. Not available in combat.",
        default = true,
        onToggle = rebuildUtility,
    })
    DirectionFeature(tools, "gemDir", "Mana gems expand", "mana gem", rebuildUtility)
    DirectionFeature(tools, "armorDir", "Armors expand", "armor", rebuildUtility)
    DirectionFeature(tools, "foodDir", "Food & water expand", "food, water and table", rebuildUtility)
    tools:RegisterFeature(CLASS, {
        key = "portalLock", name = "Lock the mage buttons",
        desc = "Stops the portal and utility buttons being dragged by accident.",
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
        self:CreateUtilityAnchor()
        -- SPELLS_CHANGED also fires when a spell is learned, which is what
        -- picks up a new spell; LEARNED_SPELL_IN_TAB doesn't exist on 2.5.6
        WM:RegisterEvents(eventFrame, { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" })
        -- Spellbook isn't reliably populated the instant we initialise
        WM.RunAfter(2, function() Mage:UpdateButtons() end)
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if not IsPlayerMage() then return end
    -- Secure children can't be touched mid-combat; rebuild once it drops
    if InCombatLockdown() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        Mage:UpdateButtons()
    else
        WM.RunAfter(1, function() Mage:UpdateButtons() end)
    end
end)

function Mage:ReportSpells()
    local t, p = self:ScanSpellbook()
    self:Print("Known teleports: " .. (t or 0) .. ", portals: " .. (p or 0))
    for _, e in ipairs(portalSpells)   do print("  |cFF66CCFF" .. e.name .. "|r") end
    for _, e in ipairs(teleportSpells) do print("  |cFFCCCCCC" .. e.name .. "|r") end
    for _, group in ipairs({ "gems", "armor", "food" }) do
        for _, e in ipairs(utilitySpells[group]) do print("  |cFFFFCC66" .. e.name .. "|r") end
    end
end
