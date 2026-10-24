-- Watching Machine: Frame Mover
-- Lets you drag the game's own windows (character, spellbook, bags' bank,
-- mailbox, talents, the world map, ...) wherever you like, and resize them
-- with Ctrl + mouse wheel. Each character remembers its own layout, and a
-- window goes back to your spot every time the game opens or re-places it.
--
--   drag                  move the window (a drag on any of its tabs or
--                         inner panels moves the whole window)
--   Ctrl + mouse wheel    make it bigger or smaller
--   Shift + right-click   put it back where the game had it
--   Ctrl + right-click    put its size back
--
-- Nothing is written into the game's own tables: our state lives in local
-- tables keyed by frame, hooks are secure hooks, and protected windows are
-- left alone in combat (changes wait for it to end). The window list is in
-- Data/FrameMover.lua (compiled with the help of BlizzMove's research); the
-- code is our own.

local AddonName, WM = ...
local FM = {}
WM:RegisterModule("FrameMover", FM)
WM.FrameMover = FM

FM.version = "3.49"

local MIN_SCALE, MAX_SCALE, STEP = 0.5, 2, 0.1
FM.MIN_SCALE, FM.MAX_SCALE = MIN_SCALE, MAX_SCALE

-- Other addons that move the same windows: with one of them loaded we stay
-- out of the way
local OTHERS = { "BlizzMove", "MoveAnything", "BlizzMoveAll" }

local DEFAULTS = {
    shiftDrag = false,      -- only move while Shift is held
    wheelScale = true,      -- Ctrl + mouse wheel resizes
    clamp = true,           -- keep windows on the screen
}

local function DB()
    WMFrameMoverDB = WMFrameMoverDB or {}
    local db = WMFrameMoverDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.pos) ~= "table" then db.pos = {} end         -- [window] = { x = left, y = top } in screen units
    if type(db.scale) ~= "table" then db.scale = {} end     -- [window] = its size
    if type(db.fixed) ~= "table" then db.fixed = {} end     -- [window] = true: don't move this one
    return db
end
FM.DB = DB

local function On() return WM:IsModuleOn("FrameMover") end

-- ============================================
-- FRAMES
-- ============================================

-- Our own state about each frame we handle, keyed by the frame (never
-- written into the frame itself)
local info = setmetatable({}, { __mode = "k" })
FM.info = info
FM.roots = {}               -- [window name] = its frame, once found
FM.pending = {}             -- work held back by combat

local moving                -- the window being dragged
local applying = false      -- true while we set a window's anchor ourselves

local function Loaded(addon)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addon) end
    if IsAddOnLoaded then return IsAddOnLoaded(addon) end
    return false
end

-- Another mover is loaded (its name), or nil
function FM:OtherMover()
    for _, name in ipairs(OTHERS) do
        if Loaded(name) then return name end
    end
end

-- A frame by name; "A.B" is the child key B of frame A
function FM.Resolve(name)
    local obj
    for key in string.gmatch(name, "[^%.]+") do
        if obj == nil then obj = _G[key] else obj = type(obj) == "table" and rawget(obj, key) or nil end
        if obj == nil then return nil end
    end
    -- A frame (textures and text have no scripts to hook)
    if type(obj) == "table" and type(obj.SetPoint) == "function" and type(obj.HookScript) == "function" then return obj end
end

-- Protected and in combat: the game won't let us touch it now
local function Busy(frame)
    return InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() and true or false
end

-- Run fn when combat ends (once per key)
local function Later(key, fn) FM.pending[key] = fn end

local function Points(frame)
    local out = {}
    for i = 1, (frame:GetNumPoints() or 0) do out[i] = { frame:GetPoint(i) } end
    return out
end

local function NameOf(root) return info[root] and info[root].name end

-- Remember where the game has a window (for putting it back), unless it's
-- on one of our own anchors
local function NoteGameSpot(root)
    local i = info[root]
    local p, rel, rp = root:GetPoint(1)
    if not p then return end
    if p == "TOPLEFT" and rel == UIParent and rp == "BOTTOMLEFT" and i.orig then return end
    i.orig = Points(root)
end

local function Clamp(v) return math.max(MIN_SCALE, math.min(MAX_SCALE, v)) end

-- ---- position ----

-- Put a window where you left it
function FM:Apply(root)
    local i = info[root]
    if not i or not On() then return end
    local p = DB().pos[i.name]
    if not p or DB().fixed[i.name] then return end
    if Busy(root) then Later(root, function() FM:Apply(root) end) return end
    local s = root:GetScale() or 1
    if s <= 0 then s = 1 end
    NoteGameSpot(root)
    applying = true
    -- Held by two corners: keep its size before anchoring one
    if (root:GetNumPoints() or 0) > 1 and root.GetWidth then
        local w, h = root:GetWidth(), root:GetHeight()
        if w and w > 0 and h and h > 0 then root:SetSize(w, h) end
    end
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x / s, p.y / s)
    applying = false
end

-- Remember where a window is now
function FM:Save(root)
    local i = info[root]
    if not i then return end
    local l, t = root:GetLeft(), root:GetTop()
    if not l or not t then return end
    local s = root:GetScale() or 1
    DB().pos[i.name] = { x = l * s, y = t * s }
end

-- Back to where the game put it
function FM:ResetPosition(name)
    DB().pos[name] = nil
    local root = self.roots[name]
    local i = root and info[root]
    if not i or not i.orig or #i.orig == 0 then return end
    if Busy(root) then Later(root, function() FM:ResetPosition(name) end) return end
    applying = true
    root:ClearAllPoints()
    for _, p in ipairs(i.orig) do root:SetPoint(unpack(p)) end
    applying = false
end

-- ---- size ----

function FM:ApplyScale(root)
    local i = info[root]
    if not i or not On() then return end
    local sc = DB().scale[i.name]
    if not sc or DB().fixed[i.name] then return end
    if Busy(root) then Later(root, function() FM:ApplyScale(root) end) return end
    if i.origScale == nil then i.origScale = root:GetScale() end
    if root:GetScale() ~= sc then
        root:SetScale(sc)
        self:Apply(root)
    end
end

-- Resize by one step (delta +1 / -1)
function FM:StepScale(root, delta)
    local i = info[root]
    if not i or Busy(root) or DB().fixed[i.name] then return end
    if i.origScale == nil then i.origScale = root:GetScale() end
    local cur = root:GetScale() or 1
    local new = Clamp(math.floor((cur + STEP * delta) * 10 + 0.5) / 10)
    if new == cur then return end
    -- Keep its top-left corner where it is
    if not DB().pos[i.name] then
        NoteGameSpot(root)
        self:Save(root)
    end
    DB().scale[i.name] = new
    root:SetScale(new)
    self:Apply(root)
end

function FM:ResetScale(name)
    DB().scale[name] = nil
    local root = self.roots[name]
    local i = root and info[root]
    if not i or i.origScale == nil then return end
    if Busy(root) then Later(root, function() FM:ResetScale(name) end) return end
    root:SetScale(i.origScale)
    self:Apply(root)
end

function FM:ResetAll()
    local db = DB()
    local names = {}
    for name in pairs(db.pos) do names[name] = true end
    for name in pairs(db.scale) do names[name] = true end
    for name in pairs(names) do
        self:ResetPosition(name)
        self:ResetScale(name)
    end
    if self.panel and self.panel:IsShown() then self.panel:Refresh() end
end

-- ============================================
-- MOUSE
-- ============================================

local function RootOf(frame) local i = info[frame]; return i and i.root end

local function OnMouseDown(frame, button)
    if not On() or button ~= "LeftButton" then return end
    local root = RootOf(frame)
    local i = root and info[root]
    if not i or DB().fixed[i.name] or Busy(root) then return end
    if DB().shiftDrag and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    NoteGameSpot(root)
    i.userPlaced = root.IsUserPlaced and root:IsUserPlaced() or false
    i.movable = root.IsMovable and root:IsMovable() or false
    root:SetMovable(true)
    root:StartMoving()
    moving = root
end

-- The drag ended: remember the spot, and anchor it our way
function FM:StopMoving(root)
    if moving ~= root then return end
    moving = nil
    local i = info[root]
    root:StopMovingOrSizing()
    -- Not "user placed": the game's own layout cache stays out of it
    if root.SetUserPlaced then root:SetUserPlaced(i and i.userPlaced or false) end
    if i and not i.movable and root.SetMovable then root:SetMovable(false) end
    self:Save(root)
    self:Apply(root)
    if self.panel and self.panel:IsShown() then self.panel:Refresh() end
end

local function OnMouseUp(frame, button)
    local root = RootOf(frame)
    if not root then return end
    if button == "LeftButton" then
        if moving == root then FM:StopMoving(root) end
        return
    end
    if not On() or button ~= "RightButton" then return end
    local name = NameOf(root)
    if IsShiftKeyDown and IsShiftKeyDown() then FM:ResetPosition(name) end
    if IsControlKeyDown and IsControlKeyDown() then FM:ResetScale(name) end
end

local function OnMouseWheel(frame, delta)
    if not On() or not DB().wheelScale or not (IsControlKeyDown and IsControlKeyDown()) then return end
    local root = RootOf(frame)
    if root then FM:StepScale(root, delta > 0 and 1 or -1) end
end

-- ============================================
-- TAKING A WINDOW ON
-- ============================================

-- Mouse, wheel and clamping as the settings want them (remembering how the
-- game had them, for when the module is turned off)
function FM:Prepare(frame)
    local i = info[frame]
    if not i or Busy(frame) then return end
    local db = DB()
    if i.mouse == nil then i.mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false end
    if not i.mouse then frame:EnableMouse(true) end
    -- The wheel only on frames that don't scroll by themselves
    if i.wheel == nil then
        i.wheel = frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() or false
        i.ownWheel = i.wheel or (frame.GetScript and frame:GetScript("OnMouseWheel") ~= nil) or false
    end
    if not i.ownWheel and frame.EnableMouseWheel then frame:EnableMouseWheel(db.wheelScale and true or false) end
    if i.isRoot and frame.SetClampedToScreen then
        if i.clamped == nil then i.clamped = frame.IsClampedToScreen and frame:IsClampedToScreen() or false end
        frame:SetClampedToScreen(db.clamp or i.clamped)
    end
end

-- Back to how the game had it
function FM:Unprepare(frame)
    local i = info[frame]
    if not i or Busy(frame) then return end
    if i.mouse == false then frame:EnableMouse(false) end
    if not i.ownWheel and i.wheel ~= nil and frame.EnableMouseWheel then frame:EnableMouseWheel(i.wheel) end
    if i.isRoot and i.clamped ~= nil and frame.SetClampedToScreen then frame:SetClampedToScreen(i.clamped) end
end

local function OnShow(root)
    if not On() then return end
    FM:ApplyScale(root)
    FM:Apply(root)
end

local function OnHide(root)
    if moving == root then FM:StopMoving(root) end
end

-- The game re-placed a window (opening it, or making room for another):
-- put it back on your spot
local function OnSetPoint(root)
    if applying or moving == root or not On() then return end
    local i = info[root]
    if not i or not DB().pos[i.name] or DB().fixed[i.name] then return end
    FM:Apply(root)
end

local function OnScaleForFit(frame)
    if On() and info[frame] and info[frame].isRoot then FM:ApplyScale(frame) end
end

local function Hook(frame, root, name)
    if info[frame] then return end
    info[frame] = { root = root, name = name, isRoot = frame == root }
    frame:HookScript("OnMouseDown", OnMouseDown)
    frame:HookScript("OnMouseUp", OnMouseUp)
    frame:HookScript("OnMouseWheel", OnMouseWheel)
    if frame == root then
        frame:HookScript("OnShow", OnShow)
        frame:HookScript("OnHide", OnHide)
        if hooksecurefunc then hooksecurefunc(frame, "SetPoint", OnSetPoint) end
    end
end

-- Take on one window and its parts, if this client has it
function FM:TakeOn(entry)
    local root = self.Resolve(entry.frame)
    if not root then return false end
    if Busy(root) then Later(entry, function() FM:TakeOn(entry) end) return false end
    self.roots[entry.frame] = root
    Hook(root, root, entry.frame)
    self:Prepare(root)
    for _, partName in ipairs(entry.parts or {}) do
        local part = self.Resolve(partName)
        if part and part ~= root and not info[part] then
            Hook(part, root, entry.frame)
            self:Prepare(part)
        end
    end
    if root:IsShown() then OnShow(root) end
    return true
end

-- Every window this client has loaded so far (addon: only that addon's)
function FM:TakeOnAll(addon)
    if self:OtherMover() then return 0 end
    local n = 0
    for _, entry in ipairs(WM.FrameMoverData or {}) do
        if (addon and entry.addon == addon) or (not addon and (not entry.addon or Loaded(entry.addon))) then
            if self:TakeOn(entry) then n = n + 1 end
        end
    end
    return n
end

-- Settings changed: mouse, wheel and clamping again on every window
function FM:Refresh()
    for frame in pairs(info) do self:Prepare(frame) end
end

-- ============================================
-- OPTIONS
-- ============================================

function FM.Title(name) return (WM.FrameMoverNames and WM.FrameMoverNames[name]) or name end

-- The windows in the list: { value = frame name, text = its title }
function FM:WindowOptions()
    local out, seen = {}, {}
    for _, entry in ipairs(WM.FrameMoverData or {}) do
        if not seen[entry.frame] then
            seen[entry.frame] = true
            out[#out + 1] = { value = entry.frame, text = self.Title(entry.frame) }
        end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

-- "Moved: ..." text for the window
function FM:MovedText()
    local db, names = DB(), {}
    local seen = {}
    for name in pairs(db.pos) do seen[name] = true end
    for name in pairs(db.scale) do seen[name] = true end
    for name in pairs(seen) do
        local t = self.Title(name)
        if db.scale[name] then t = t .. string.format(" (size %d%%)", math.floor(db.scale[name] * 100 + 0.5)) end
        if db.fixed[name] then t = t .. " (not moving)" end
        names[#names + 1] = t
    end
    table.sort(names)
    if #names == 0 then return "|cFF888888No windows moved yet on this character.|r" end
    return "Moved: " .. table.concat(names, ", ")
end

local function ControlsNote(L)
    L:Note("|cFFFFFFFFDrag|r a window to move it (its tabs and inner panels too). |cFFFFFFFFCtrl + mouse wheel|r over it"
        .. " makes it bigger or smaller. |cFFFFFFFFShift + right-click|r puts it back where the game had it,"
        .. " |cFFFFFFFFCtrl + right-click|r puts its size back.")
end

local function SettingBoxes(L, live)
    L:Checkbox({ label = "Only move windows while Shift is held", get = function() return DB().shiftDrag end,
        set = function(v) DB().shiftDrag = v end,
        tooltip = { "Hold Shift to move", "For when you drag windows by accident: they only move while you hold Shift." } })
    L:Checkbox({ label = "Ctrl + mouse wheel resizes a window", get = function() return DB().wheelScale end,
        set = function(v) DB().wheelScale = v; if live then FM:Refresh() end end,
        tooltip = { "Resizing", "Hold Ctrl and turn the mouse wheel over a window. Lists that scroll still scroll;"
            .. " turn this off if you'd rather the wheel never stops over a window." } })
    L:Checkbox({ label = "Keep windows on the screen", get = function() return DB().clamp end,
        set = function(v) DB().clamp = v; if live then FM:Refresh() end end,
        tooltip = { "On the screen", "Windows can't be dragged past the edge of the screen." } })
end

function FM:CreateUI()
    if self.panel then return self.panel end
    local panel = WM.UI:CreatePanel({ name = "WM_FrameMoverFrame", title = "Frame Mover", titleColor = "99CCFF", width = 440 })
    self.panel = panel
    local L = panel.layout
    L:Note(function()
        local other = FM:OtherMover()
        if other then return "|cFFFF6666" .. other .. " is loaded, so Frame Mover leaves the windows to it.|r" end
        return "Move the game's own windows wherever you like; this character remembers where."
    end)
    ControlsNote(L)
    SettingBoxes(L, true)
    L:Header("One window")
    L:Dropdown({ label = "Window:", width = 180, options = function() return FM:WindowOptions() end,
        get = function() return FM.selected end, set = function(v) FM.selected = v; panel:Refresh() end,
        placeholder = "Choose a window" })
    L:Buttons({
        { text = "Reset its position", width = 125, onClick = function()
            if FM.selected then FM:ResetPosition(FM.selected); panel:Refresh() end end },
        { text = "Reset its size", width = 105, onClick = function()
            if FM.selected then FM:ResetScale(FM.selected); panel:Refresh() end end },
    })
    L:Checkbox({ label = "Don't move this window", get = function() return FM.selected and DB().fixed[FM.selected] end,
        set = function(v)
            if not FM.selected then return end
            DB().fixed[FM.selected] = v or nil
            if v then FM:ResetPosition(FM.selected); FM:ResetScale(FM.selected) end
            panel:Refresh()
        end,
        tooltip = { "Don't move it", "Leaves this window where the game puts it, and puts it back there now." } })
    L:Header("All windows")
    L:Buttons({ { text = "Reset every window", width = 150, onClick = function()
        WM:Confirm("Put every window back where the game had it, at its normal size?", function() FM:ResetAll() end)
    end } })
    L:Note(function() return FM:MovedText() end)
    panel:Finish()
    return panel
end

function FM:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show(); p:Refresh() end
end
FM.ToggleUI = FM.Toggle

-- Turned off on this character: every window goes back to the game's spot
-- and size and its mouse settings (your layout stays saved for next time)
function FM:OnModuleOff()
    if moving then
        local root = moving
        moving = nil
        root:StopMovingOrSizing()
    end
    local db = DB()
    for name, root in pairs(self.roots) do
        local i = info[root]
        if i and not Busy(root) then
            if db.pos[name] and i.orig and #i.orig > 0 and root:IsShown() then
                applying = true
                root:ClearAllPoints()
                for _, p in ipairs(i.orig) do root:SetPoint(unpack(p)) end
                applying = false
            end
            if i.origScale ~= nil then root:SetScale(i.origScale) end
        end
    end
    for frame in pairs(info) do self:Unprepare(frame) end
    wipe(self.pending)
    if self.panel then self.panel:Hide() end
end

-- Turned back on: windows loaded meanwhile, and your layout again
function FM:OnModuleOn()
    if not self._wmStarted then return end
    self:TakeOnAll()
    self:Refresh()
    for _, root in pairs(self.roots) do
        if root:IsShown() then OnShow(root) end
    end
end

-- The module's page in the guided setup
function FM:SetupPage(L)
    L:Note("Moves the game's own windows: character, spellbook, talents, bank, mailbox, the world map, the auction"
        .. " house, professions and the rest. Put them where you like; this character remembers the layout, and"
        .. " each window goes back to your spot whenever the game opens it.")
    ControlsNote(L)
    L:Note("Every window can be put back on its own, or all at once, from the Frame Mover window"
        .. " (|cFFFFFF00/wmachine move|r). If BlizzMove is installed, Frame Mover leaves the windows to it.")
    SettingBoxes(L, false)
end

function FM:GetQuickStatus()
    local other = self:OtherMover()
    if other then return "Off: " .. other .. " is loaded" end
    local db, n = DB(), 0
    local seen = {}
    for name in pairs(db.pos) do seen[name] = true end
    for name in pairs(db.scale) do seen[name] = true end
    for _ in pairs(seen) do n = n + 1 end
    return n == 0 and "No windows moved" or (n == 1 and "1 window moved" or (n .. " windows moved"))
end

-- /wmachine move [reset]
function FM:Command(arg)
    arg = (arg or ""):lower()
    if arg == "reset" then
        WM:Confirm("Put every window back where the game had it, at its normal size?", function() FM:ResetAll() end)
    else
        self:Toggle()
    end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

function FM:Initialize()
    DB()
    local other = self:OtherMover()
    if other then
        WM:ModulePrint("FrameMover", other .. " is loaded, so Frame Mover leaves the game's windows to it.")
        return
    end
    self:TakeOnAll()
    if hooksecurefunc then
        for _, fn in ipairs({ "UpdateScaleForFit", "UIPanelUpdateScaleForFit" }) do
            if type(_G[fn]) == "function" then hooksecurefunc(fn, OnScaleForFit) end
        end
    end
    WM:RegisterEvents(events, { "ADDON_LOADED", "PLAYER_REGEN_ENABLED" })
end

events:SetScript("OnEvent", function(_, event, arg1)
    if not WM:IsModuleOn("FrameMover") then return end
    local ok, err = true
    if event == "ADDON_LOADED" then
        if type(arg1) == "string" and arg1:find("^Blizzard_") then ok, err = pcall(FM.TakeOnAll, FM, arg1) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local work = FM.pending
        FM.pending = {}
        for _, fn in pairs(work) do
            local ok2, err2 = pcall(fn)
            if not ok2 then ok, err = ok2, err2 end
        end
    end
    if not ok then geterrorhandler()(err) end
end)
