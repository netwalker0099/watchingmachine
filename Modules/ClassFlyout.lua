-- Watching Machine: Class flyout buttons
-- The shared engine behind every class's flyout buttons (mage portals and
-- utility, warlock armors / demons / stones, ...). A flyout is an icon
-- button that expands into one icon per spell, in groups; each group fans
-- out in its own direction, or is Hidden.
--
-- Shared behaviour, set once in Class Tools > General, for every flyout:
--   * open on hover or on click
--   * dock: line the buttons up together (row or column) so they move as one
--   * lock: stop them being dragged
--
-- Casting requires SecureActionButtonTemplate, and secure frames cannot be
-- shown, hidden or moved while in combat. None of these spells are worth
-- casting from here in combat (portals and conjures can't be), so flyouts
-- refuse to open in combat, and layout / docking changes made in combat
-- apply when it ends.
--
-- Using it from a class module:
--
--   local fly = WM.Flyout.New({
--       class = "WARLOCK", feature = "warlockButton",    -- Class Tools toggle
--       anchorName = "WM_WarlockAnchor", buttonPrefix = "WM_WarlockBtn",
--       title = "Warlock", emptyText = "...",
--       store = function() return WarlockToolsDB end,  -- position + directions
--       posX = "buttonX", posY = "buttonY", defaultX = 196,
--       groups = function() return { { entries = list, dirKey = "demonDir" }, ... } end,
--       setIcon = function(texture, fly) ... end,
--   })
--
-- Entries are { name, index (spellbook slot), icon, badge = function or nil }.
-- An entry with select = function picks something instead of casting (the
-- shaman's totem sets); tooltip = { lines } gives it a tooltip of its own.
--
-- cfg.secureAnchor: the anchor is itself a SecureActionButton that does
-- something on click (the totem button casts its set), so the flyout only
-- opens on hover; cfg.setupAnchor(anchor) sets its attributes and clicks,
-- and cfg.anchorTooltip(tooltip, inCombat) fills the anchor's tooltip (it
-- still works in combat, unlike the flyout). cfg.dragNeedsShift: only a
-- Shift-drag moves it, so a plain press can't both cast and start a drag.
-- A def with prefix = true matches every spell whose name starts with it,
-- for spells whose ranks are separate names ("Create Healthstone (Major)").

local AddonName, WM = ...
local Flyout = {}
WM.Flyout = Flyout

local ANCHOR_SIZE, ICON_SIZE, GAP, DOCK_GAP = 36, 32, 4, 2
Flyout.ANCHOR_SIZE, Flyout.ICON_SIZE, Flyout.GAP, Flyout.DOCK_GAP = ANCHOR_SIZE, ICON_SIZE, GAP, DOCK_GAP

local DIRECTIONS = {
    UP    = { 0, 1 },
    DOWN  = { 0, -1 },
    LEFT  = { -1, 0 },
    RIGHT = { 1, 0 },
}
Flyout.DIRECTIONS = DIRECTIONS
Flyout.DIRECTION_OPTIONS = {
    { value = "UP", text = "Up" }, { value = "RIGHT", text = "Right" },
    { value = "DOWN", text = "Down" }, { value = "LEFT", text = "Left" },
    { value = "HIDDEN", text = "Hidden" },
}
Flyout.DOCK_OPTIONS = {
    { value = "RIGHT", text = "Row, left to right" },
    { value = "LEFT",  text = "Row, right to left" },
    { value = "DOWN",  text = "Column, downwards" },
    { value = "UP",    text = "Column, upwards" },
}
Flyout.OPEN_OPTIONS = {
    { value = "hover", text = "On hover" },
    { value = "click", text = "On click" },
}

local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- ============================================
-- SHARED SETTINGS (ClassToolsDB.flyout)
-- ============================================

local function Settings()
    if not ClassToolsDB then return {} end
    local s = ClassToolsDB.flyout
    if type(s) ~= "table" then s = {}; ClassToolsDB.flyout = s end
    if s.openMode == nil then s.openMode = "hover" end
    if s.docked == nil then s.docked = false end
    if s.dockDir == nil then s.dockDir = "RIGHT" end
    if s.locked == nil then
        -- Mage-only lock before 3.15: carry it over once
        s.locked = (MageToolsDB and MageToolsDB.portalLocked) and true or false
    end
    return s
end
Flyout.Settings = Settings

-- Click-to-open applies unless the anchor's own click does something else
local function ClickMode(fly)
    if fly and fly.cfg.secureAnchor then return false end
    return Settings().openMode == "click"
end

-- ============================================
-- HELPERS
-- ============================================

-- Which half of a click casts. On current client builds a secure action
-- button only acts on the press that matches the ActionButtonUseKeyDown
-- setting (on by default: the mouse-DOWN). Registering for "AnyUp" alone
-- meant the button never saw the press it acts on, so nothing was cast.
-- Registering both would cast twice on builds without that check, so
-- register exactly the one that casts. Re-read on every rebuild.
function Flyout.CastClicks()
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return keyDown and "AnyDown" or "AnyUp"
end

-- Offset of the n-th icon (1-based) along a direction from the anchor centre
function Flyout.Offset(dir, n)
    local d = DIRECTIONS[dir]
    local dist = ANCHOR_SIZE / 2 + GAP + ICON_SIZE / 2 + (n - 1) * (ICON_SIZE + GAP)
    return d[1] * dist, d[2] * dist
end

-- Paint a texture with a class's crest from the class-circles sheet every
-- client ships; fallback texture if the coordinates aren't available
function Flyout.ClassCrest(icon, class, fallback)
    local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[class]
    if type(coords) == "table" then
        icon:SetTexture(CLASS_CIRCLES)
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        icon:SetTexture(fallback)
        icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function PlayerClass()
    local _, c = UnitClass("player")
    return c
end

function Flyout.SpellIcon(index, name, fallback)
    local tex = GetSpellBookItemTexture and GetSpellBookItemTexture(index, BOOKTYPE_SPELL or "spell")
    if not tex and GetSpellTexture then tex = GetSpellTexture(name) end
    return tex or fallback
end

-- Scan the spellbook for named spells.
-- defs = { group = { { "English Name", spellID, extra fields... }, ... } }, each
-- group listed in display order (nearest the button first). Returns
-- { group = { entry, ... } } with only known spells, one entry per name: the
-- highest rank, since ranks are listed lowest first and casting by name
-- picks the highest anyway. Matched by English name and by the client's
-- own name for the ID, so localized clients work. Extra fields on a def
-- (badge = ...) are copied onto its entry; key is the def's English name.
function Flyout.ScanSpells(defs, fallbackIcon)
    local byName, byPrefix = {}, {}
    for group, list in pairs(defs) do
        for order, d in ipairs(list) do
            local slot = { group = group, order = order, def = d }
            local names = { d[1] }
            if GetSpellInfo and d[2] then
                local ok, name = pcall(GetSpellInfo, d[2])
                if ok and type(name) == "string" then
                    -- A localized "Create Healthstone (Minor)" prefixes as
                    -- "Create Healthstone"
                    names[#names + 1] = d.prefix and (name:gsub("%s*%b()$", "")) or name
                end
            end
            for _, n in ipairs(names) do
                if d.prefix then byPrefix[#byPrefix + 1] = { prefix = n, slot = slot }
                else byName[n] = slot end
            end
        end
    end
    local function Lookup(name)
        if byName[name] then return byName[name] end
        for _, p in ipairs(byPrefix) do
            if name:sub(1, #p.prefix) == p.prefix then return p.slot end
        end
    end

    local found = {}
    for group in pairs(defs) do found[group] = {} end
    if GetSpellBookItemName then
        local i = 1
        while true do
            local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
            if not name then break end
            local slot = Lookup(name)
            if slot then
                found[slot.group][slot.order] = {
                    name = name, index = i, key = slot.def[1],
                    icon = Flyout.SpellIcon(i, name, fallbackIcon),
                    badge = slot.def.badge,
                }
            end
            i = i + 1
            if i > 1024 then break end   -- guard against a malformed spellbook
        end
    end

    local out = {}
    for group, list in pairs(defs) do
        out[group] = {}
        for order = 1, #list do
            if found[group][order] then table.insert(out[group], found[group][order]) end
        end
    end
    return out
end

local function ShowSpellTooltip(b)
    if b.tooltipLines then
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        for i, line in ipairs(b.tooltipLines) do
            if i == 1 then GameTooltip:AddLine(line, 1, 0.8, 0) else GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
        end
        GameTooltip:Show()
        return
    end
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

-- ============================================
-- FLYOUT
-- ============================================

local FlyoutMT = {}
FlyoutMT.__index = FlyoutMT

local registry = {}   -- every flyout, in creation order (= dock order)
Flyout.registry = registry

function Flyout.New(cfg)
    local fly = setmetatable({ cfg = cfg, buttons = {}, count = 0, closePending = false, open = false }, FlyoutMT)
    registry[#registry + 1] = fly
    return fly
end

function FlyoutMT:Store()
    return (self.cfg.store and self.cfg.store()) or {}
end

-- A group's direction, or "HIDDEN"; unknown saved values use the default
function FlyoutMT:Direction(dirKey)
    local d = self:Store()[dirKey]
    if d == "HIDDEN" or DIRECTIONS[d] then return d end
    return (self.cfg.defaults and self.cfg.defaults[dirKey]) or "UP"
end

function FlyoutMT:HideButtons()
    if InCombatLockdown() then return end
    self.open = false
    for _, b in ipairs(self.buttons) do b:Hide() end
end

function FlyoutMT:ShowButtons()
    self.closePending = false
    if InCombatLockdown() then return end
    self.open = true
    for i = 1, self.count do
        if self.buttons[i] then self.buttons[i]:Show() end
    end
end

-- Hover mode closes a moment after the mouse leaves; click mode stays open
function FlyoutMT:ScheduleClose()
    if ClickMode(self) then return end
    self.closePending = true
    WM.RunAfter(0.35, function()
        if self.closePending then self:HideButtons() end
    end)
end

-- Kept under the hover names other code uses
FlyoutMT.CancelClose = FlyoutMT.ShowButtons

function FlyoutMT:UpdateBadges()
    for i = 1, self.count do
        local b = self.buttons[i]
        if b and b.countText then
            local text = b.badge and b.badge() or nil
            b.countText:SetText(text or "")
        end
    end
end

function FlyoutMT:NewButton(i)
    -- Secure template only: its click handler is the one that casts
    local b = CreateFrame("Button", self.cfg.buttonPrefix .. i, self.anchor, "SecureActionButtonTemplate")
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.countText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.countText:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    -- Keep the flyout open while moving between its buttons
    b:SetScript("OnEnter", function(btn)
        self:ShowButtons()
        ShowSpellTooltip(btn)
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        self:ScheduleClose()
    end)
    -- A picker entry runs its choice; click mode closes after a pick or cast
    b:SetScript("PostClick", function(btn)
        if btn.select then btn.select() end
        if ClickMode(self) or btn.select then self:HideButtons() end
    end)
    return b
end

function FlyoutMT:Build()
    if InCombatLockdown() then return end
    if not self.anchor then return end
    if self.cfg.scan then self.cfg.scan() end

    -- Each group continues the line of any earlier group sharing its
    -- direction; Hidden groups aren't placed at all
    local placed, lineLength = {}, {}
    for _, group in ipairs(self.cfg.groups()) do
        local dir = self:Direction(group.dirKey)
        if dir ~= "HIDDEN" then
            for _, e in ipairs(group.entries) do
                lineLength[dir] = (lineLength[dir] or 0) + 1
                placed[#placed + 1] = { entry = e, dir = dir, n = lineLength[dir] }
            end
        end
    end

    local clicks = Flyout.CastClicks()
    for i, p in ipairs(placed) do
        local b = self.buttons[i] or self:NewButton(i)
        self.buttons[i] = b
        b:ClearAllPoints()
        local x, y = Flyout.Offset(p.dir, p.n)
        b:SetPoint("CENTER", self.anchor, "CENTER", x, y)
        b:RegisterForClicks(clicks)
        if p.entry.select then
            -- Picks something; no secure action
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        else
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", p.entry.name)
        end
        b.spellName, b.bookIndex, b.badge = p.entry.name, p.entry.index, p.entry.badge
        b.select, b.tooltipLines = p.entry.select, p.entry.tooltip
        b.icon:SetTexture(p.entry.icon)
        if self.open then b:Show() else b:Hide() end
    end

    -- Retire any buttons left over from a previous, longer list
    for i = #placed + 1, #self.buttons do
        local b = self.buttons[i]
        b:Hide()
        b:SetAttribute("spell", nil)
        b.spellName, b.bookIndex, b.badge = nil, nil, nil
        b.select, b.tooltipLines = nil, nil
    end

    self.count = #placed
    self.anchor.count = #placed
    self:UpdateBadges()
    if self.cfg.setIcon then self.cfg.setIcon(self.anchor.icon, self) end
end

function FlyoutMT:SavePosition()
    local store = self:Store()
    local x, y = self.anchor:GetCenter()
    if x then store[self.cfg.posX], store[self.cfg.posY] = x, y end
end

function FlyoutMT:RestorePosition()
    local store, a = self:Store(), self.anchor
    a:ClearAllPoints()
    if store[self.cfg.posX] and store[self.cfg.posY] then
        a:SetPoint("CENTER", UIParent, "BOTTOMLEFT", store[self.cfg.posX], store[self.cfg.posY])
    else
        a:SetPoint("CENTER", UIParent, "CENTER", self.cfg.defaultX or 0, self.cfg.defaultY or 0)
    end
end

function FlyoutMT:CreateAnchor()
    if self.anchor then return self.anchor end
    local cfg = self.cfg

    local a = CreateFrame("Button", cfg.anchorName, UIParent,
        cfg.secureAnchor and "SecureActionButtonTemplate" or nil)
    a:SetSize(ANCHOR_SIZE, ANCHOR_SIZE)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")   -- a secure anchor's setupAnchor may change this
    if not cfg.secureAnchor then a:RegisterForClicks("LeftButtonUp") end
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetAllPoints()
    a:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    a:Hide()
    self.anchor = a
    if cfg.setIcon then cfg.setIcon(a.icon, self) end
    self:RestorePosition()

    -- Docked buttons move as one: dragging any of them drags the lead
    a:SetScript("OnDragStart", function()
        if Settings().locked or InCombatLockdown() then return end
        if cfg.dragNeedsShift and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        local mover = Flyout.DragTarget(self)
        mover.anchor:StartMoving()
        self.dragging = mover
    end)
    a:SetScript("OnDragStop", function()
        local mover = self.dragging or self
        self.dragging = nil
        mover.anchor:StopMovingOrSizing()
        mover:SavePosition()
        Flyout.ApplyDock()
    end)

    if cfg.secureAnchor then
        -- Never replace a secure button's OnClick: it's what performs the action
        if cfg.setupAnchor then cfg.setupAnchor(a, self) end
    else
        a:SetScript("OnClick", function()
            if not ClickMode() or InCombatLockdown() then return end
            if self.open then self:HideButtons() else self:ShowButtons() end
        end)
    end

    a:SetScript("OnEnter", function(btn)
        if cfg.anchorTooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            cfg.anchorTooltip(GameTooltip, InCombatLockdown())
            GameTooltip:Show()
            if not InCombatLockdown() then self:ShowButtons() end
            return
        end
        if InCombatLockdown() then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cfg.title, 1, 0.8, 0)
            GameTooltip:AddLine("Unavailable in combat.", 0.8, 0.4, 0.4)
            GameTooltip:Show()
            return
        end
        if not ClickMode(self) then self:ShowButtons() else self.closePending = false end
        if self.count == 0 then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cfg.title, 1, 0.8, 0)
            GameTooltip:AddLine(cfg.emptyText, 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Or every group is set to Hidden in Class Tools.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        elseif ClickMode(self) and not self.open then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cfg.title, 1, 0.8, 0)
            GameTooltip:AddLine("Click to open.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    a:SetScript("OnLeave", function()
        GameTooltip:Hide()
        self:ScheduleClose()
    end)
    return a
end

function FlyoutMT:IsWanted()
    local CT = WM.modules.ClassTools
    return PlayerClass() == self.cfg.class and CT and CT:IsEnabled(self.cfg.class, self.cfg.feature)
end

function FlyoutMT:UpdateVisibility()
    if not self.anchor then return end
    if InCombatLockdown() then return end   -- anchor holds secure children
    if self:IsWanted() then
        self:Build()
        self.anchor:Show()
    else
        self:HideButtons()
        self.anchor:Hide()
    end
    Flyout.ApplyDock()
end

-- ============================================
-- DOCKING
-- ============================================
-- With docking on, the visible flyout buttons line up in creation order:
-- the first (the lead) keeps its own saved position and the others attach
-- to the one before, in the chosen orientation. With it off, each sits at
-- its own saved position.

local function Visible()
    local out = {}
    for _, fly in ipairs(registry) do
        if fly.anchor and fly.anchor:IsShown() then out[#out + 1] = fly end
    end
    return out
end

-- The flyout whose anchor a drag should move
function Flyout.DragTarget(fly)
    if not Settings().docked then return fly end
    return Visible()[1] or fly
end

function Flyout.ApplyDock()
    if InCombatLockdown() then Flyout.dockPending = true return end
    Flyout.dockPending = false
    local s = Settings()
    local shown = Visible()
    local step = ANCHOR_SIZE + DOCK_GAP
    local d = DIRECTIONS[s.dockDir] or DIRECTIONS.RIGHT
    for i, fly in ipairs(shown) do
        if s.docked and i > 1 then
            fly.anchor:ClearAllPoints()
            fly.anchor:SetPoint("CENTER", shown[i - 1].anchor, "CENTER", d[1] * step, d[2] * step)
        else
            fly:RestorePosition()
        end
    end
end

-- Rebuild every flyout (directions, open mode, spellbook changes)
function Flyout.UpdateAll()
    for _, fly in ipairs(registry) do fly:UpdateVisibility() end
    Flyout.ApplyDock()
end

function Flyout.UpdateAllBadges()
    for _, fly in ipairs(registry) do fly:UpdateBadges() end
end

-- ============================================
-- OPTIONS
-- ============================================

-- A direction option for one group of a flyout, in its class's tab.
-- store() returns the table the direction is saved in.
function Flyout.DirectionFeature(tools, class, key, name, what, store, default, rebuild)
    tools:RegisterFeature(class, {
        key = key, kind = "choice", name = name,
        options = Flyout.DIRECTION_OPTIONS, default = default,
        desc = "Which way the " .. what .. " icons open from the button, or Hidden to leave them out.",
        get = function() return store()[key] end,
        set = function(v) store()[key] = v end,
        onChange = rebuild,
        tooltip = { name, "Up, Right, Down or Left from the button, or Hidden to leave this group out.",
            "Groups on the same button that expand the same way share one line, in the order listed here." },
    })
end

-- Class Tools > General: shared by every flyout.
-- Registered by ClassGeneral after its own checks, so they list in order.

function Flyout.RegisterOptions(tools)
    local function rebuild() Flyout.UpdateAll() end
    tools:RegisterFeature("GENERAL", {
        key = "flyoutOpen", kind = "choice", name = "Flyout buttons open",
        options = Flyout.OPEN_OPTIONS, default = "hover",
        desc = "For every class's flyout buttons (mage portals, warlock demons, ...).",
        get = function() return Settings().openMode end,
        set = function(v)
            Settings().openMode = v
            for _, fly in ipairs(registry) do fly:HideButtons() end
        end,
        tooltip = { "Flyout buttons open", "On hover: open when the mouse is over the button, close when it leaves.",
            "On click: click the button to open or close it; picking a spell closes it." },
    })
    tools:RegisterFeature("GENERAL", {
        key = "flyoutDock", name = "Dock flyout buttons together",
        desc = "Line your class's flyout buttons up in one group that moves together. Drag any of them to move the group.",
        default = false,
        onToggle = function(v) Settings().docked = v and true or false; Flyout.ApplyDock() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "flyoutDockDir", kind = "choice", name = "Docked layout",
        options = Flyout.DOCK_OPTIONS, default = "RIGHT",
        desc = "Which way docked buttons are joined, starting from the first one.",
        get = function() return Settings().dockDir end,
        set = function(v) Settings().dockDir = v end,
        onChange = rebuild,
    })
    tools:RegisterFeature("GENERAL", {
        key = "flyoutLock", name = "Lock flyout buttons",
        desc = "Stops every flyout button (or the docked group) being dragged by accident.",
        default = Settings().locked,
        onToggle = function(v) Settings().locked = v and true or false end,
    })

    -- Keep the saved flags and the feature toggles in step on load
    local tdb = ClassToolsDB and ClassToolsDB.enabled and ClassToolsDB.enabled.GENERAL
    local s = Settings()
    if tdb then
        if tdb.flyoutDock ~= nil then s.docked = tdb.flyoutDock and true or false end
        if tdb.flyoutLock ~= nil then s.locked = tdb.flyoutLock and true or false end
    end
end

-- ============================================
-- EVENTS
-- ============================================

local eventFrame = CreateFrame("Frame")
WM:RegisterEvents(eventFrame, { "BAG_UPDATE", "PLAYER_REGEN_ENABLED" })
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE" then
        Flyout.UpdateAllBadges()   -- shard counts; text is safe in combat
    elseif event == "PLAYER_REGEN_ENABLED" and Flyout.dockPending then
        Flyout.ApplyDock()
    end
end)
