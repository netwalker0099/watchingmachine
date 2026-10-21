-- Watching Machine: Mage Class Tools
-- Armor-spell warning, and a hover-expanding flyout for every teleport and
-- portal the character actually knows.

local AddonName, WM = ...
local Mage = {}
WM:RegisterModule("ClassMage", Mage)

Mage.version = "3.5"

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

local teleportSpells, portalSpells = {}, {}

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
        if name:sub(1, #telePrefix) == telePrefix then
            teleportSpells[#teleportSpells + 1] = name
        elseif name:sub(1, #portPrefix) == portPrefix then
            portalSpells[#portalSpells + 1] = name
        end
        i = i + 1
        if i > 1024 then break end   -- guard against a malformed spellbook
    end

    table.sort(teleportSpells)
    table.sort(portalSpells)
    return #teleportSpells, #portalSpells
end

-- ============================================
-- FLYOUT BUTTON
-- ============================================
-- Casting requires SecureActionButtonTemplate, and secure frames cannot be
-- shown, hidden or reconfigured while in combat. Teleports and portals are
-- not castable in combat anyway, so the flyout simply refuses to expand in
-- combat rather than pulling in a secure-handler state driver to work around
-- a restriction that costs nothing here.

local anchor = nil
local flyoutButtons = {}
local BTN_W, BTN_H = 150, 20

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

function Mage:BuildFlyout()
    if InCombatLockdown() then return end
    if not anchor then return end

    self:ScanSpellbook()

    local list = {}
    for _, n in ipairs(portalSpells)   do list[#list + 1] = { name = n, kind = "portal" } end
    for _, n in ipairs(teleportSpells) do list[#list + 1] = { name = n, kind = "tele" } end

    for i, entry in ipairs(list) do
        local b = flyoutButtons[i]
        if not b then
            -- Secure template LAST: later templates override earlier ones,
            -- and its click handler is the one that casts
            b = CreateFrame("Button", "WM_MagePortalBtn" .. i, anchor,
                            "UIPanelButtonTemplate, SecureActionButtonTemplate")
            b:SetSize(BTN_W, BTN_H)
            -- Keep the flyout open while moving between its buttons
            b:SetScript("OnEnter", function() Mage:CancelFlyoutClose() end)
            b:SetScript("OnLeave", function() Mage:ScheduleFlyoutClose() end)
            flyoutButtons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -((i - 1) * (BTN_H + 2)) - 2)
        b:RegisterForClicks(CastClicks())
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", entry.name)
        -- Strip the "Portal: " / "Teleport: " prefix for a readable label
        local short = entry.name:match("^[^:]+:%s*(.+)$") or entry.name
        b:SetText((entry.kind == "portal" and "|cFF66CCFF" or "|cFFCCCCCC") .. short .. "|r")
        b:Hide()
    end

    -- Retire any buttons left over from a previous, longer list
    for i = #list + 1, #flyoutButtons do
        flyoutButtons[i]:Hide()
        flyoutButtons[i]:SetAttribute("spell", nil)
    end

    anchor.count = #list
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

    local a = CreateFrame("Button", "WM_MagePortalAnchor", UIParent, "UIPanelButtonTemplate")
    a:SetSize(BTN_W, 24)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")
    a:SetText("Portals")
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
        desc = "A draggable button that expands on hover with every teleport and portal you know. Not available in combat.",
        default = true,
        onToggle = function() Mage:UpdatePortalButtonVisibility() end,
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
    for _, n in ipairs(portalSpells)   do print("  |cFF66CCFF" .. n .. "|r") end
    for _, n in ipairs(teleportSpells) do print("  |cFFCCCCCC" .. n .. "|r") end
end
