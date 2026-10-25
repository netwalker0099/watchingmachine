-- Watching Machine: Frame Mover
-- Lets you drag the game's own windows (character, spellbook, bank,
-- mailbox, talents, the world map, ...) wherever you like, and resize them
-- with Ctrl + mouse wheel. Each character remembers its own layout (or
-- uses one shared by all your characters), and a window goes back to your
-- spot every time the game opens or re-places it.
--
--   drag                  move the window (a drag on any of its tabs or
--                         inner panels moves the whole window)
--   Alt + drag            pull a pop-out (reputation details, raid info, an
--                         opened mail, ...) off its window and place it on
--                         its own; after that a plain drag moves it
--   Ctrl + mouse wheel    make the window bigger or smaller
--   Shift + right-click   put it back where the game had it (a pop-out:
--                         back on its window)
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

FM.version = "3.50"

local MIN_SCALE, MAX_SCALE, STEP = 0.5, 2, 0.1
FM.MIN_SCALE, FM.MAX_SCALE = MIN_SCALE, MAX_SCALE

-- Other addons that move the same windows: with one of them loaded we stay
-- out of the way
local OTHERS = { "BlizzMove", "MoveAnything", "BlizzMoveAll" }

local DEFAULTS = {
    shiftDrag = false,      -- only move while Shift is held
    wheelScale = true,      -- Ctrl + mouse wheel resizes
    clamp = true,           -- keep windows on the screen
    useShared = false,      -- this character uses the layout shared by all
}

-- A layout: pos [key] = { x, y } (left and top in screen units), scale
-- [window] = its size, fixed [window] = true (don't move it). Keys are a
-- window's name, or "Window/Pop-out" for a pop-out placed on its own.
local function FillLayout(t)
    if type(t.pos) ~= "table" then t.pos = {} end
    if type(t.scale) ~= "table" then t.scale = {} end
    if type(t.fixed) ~= "table" then t.fixed = {} end
    return t
end

local function DB()
    WMFrameMoverDB = WMFrameMoverDB or {}
    local db = WMFrameMoverDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    FillLayout(db)                                          -- this character's own layout
    if type(db.layout) ~= "table" then db.layout = {} end   -- the shared layout (shared by Profiles)
    FillLayout(db.layout)
    return db
end
FM.DB = DB

-- The layout this character uses
local function Lay()
    local db = DB()
    return db.useShared and db.layout or db
end
FM.Layout = Lay

local function On() return WM:IsModuleOn("FrameMover") end

-- ============================================
-- FRAMES
-- ============================================

-- Our own state about each frame we handle, keyed by the frame (never
-- written into the frame itself): root (its window), name (the window's
-- name), key (for a frame we place: the window, or a pop-out), ...
local info = setmetatable({}, { __mode = "k" })
FM.info = info
FM.roots = {}               -- [window name] = its frame, once found
FM.frames = {}              -- [layout key] = the frame we place for it
FM.pending = {}             -- work held back by combat

local moving                -- the frame being dragged
local applying = false      -- true while we set a frame's anchor ourselves

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
local function IsAlt() return IsAltKeyDown and IsAltKeyDown() and true or false end

-- Remember where the game has a frame (for putting it back), unless it's
-- on one of our own anchors
local function NoteGameSpot(f)
    local i = info[f]
    local p, rel, rp = f:GetPoint(1)
    if not p then return end
    if p == "TOPLEFT" and rel == UIParent and rp == "BOTTOMLEFT" and i.orig then return end
    i.orig = Points(f)
end

-- A frame's size against the screen's (its own size times its window's)
local function Ratio(f)
    local fe = f.GetEffectiveScale and f:GetEffectiveScale()
    local ue = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if type(fe) == "number" and type(ue) == "number" and fe > 0 and ue > 0 then return fe / ue end
    local s = f:GetScale() or 1
    return s > 0 and s or 1
end

local function Clamp(v) return math.max(MIN_SCALE, math.min(MAX_SCALE, v)) end

-- ---- position ----

-- Put a window (or a pop-out placed on its own) where you left it
function FM:Apply(f)
    local i = info[f]
    if not i or not i.key or not On() then return end
    local lay = Lay()
    local p = lay.pos[i.key]
    if not p or lay.fixed[i.name] then return end
    if Busy(f) then Later(f, function() FM:Apply(f) end) return end
    local r = Ratio(f)
    NoteGameSpot(f)
    applying = true
    -- Held by two corners: keep its size before anchoring one
    if (f:GetNumPoints() or 0) > 1 and f.GetWidth then
        local w, h = f:GetWidth(), f:GetHeight()
        if w and w > 0 and h and h > 0 then f:SetSize(w, h) end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x / r, p.y / r)
    applying = false
end

-- Remember where it is now
function FM:Save(f)
    local i = info[f]
    if not i or not i.key then return end
    local l, t = f:GetLeft(), f:GetTop()
    if not l or not t then return end
    local r = Ratio(f)
    Lay().pos[i.key] = { x = l * r, y = t * r }
end

-- Back where the game put it (on the screen, or a pop-out on its window)
local function GameSpot(f)
    local i = info[f]
    if not i or not i.orig or #i.orig == 0 then return end
    if Busy(f) then Later(f, function() GameSpot(f) end) return end
    applying = true
    f:ClearAllPoints()
    for _, p in ipairs(i.orig) do f:SetPoint(unpack(p)) end
    applying = false
end

function FM:ResetPosition(key)
    Lay().pos[key] = nil
    local f = self.frames[key]
    if f then GameSpot(f) end
end

-- A window and the pop-outs you placed on their own
function FM:ResetWindow(name)
    self:ResetPosition(name)
    for key in pairs(Lay().pos) do
        if key:sub(1, #name + 1) == name .. "/" then self:ResetPosition(key) end
    end
end

-- ---- size ----

function FM:ApplyScale(root)
    local i = info[root]
    if not i or not i.isRoot or not On() then return end
    local lay = Lay()
    local sc = lay.scale[i.name]
    if not sc or lay.fixed[i.name] then return end
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
    local lay = Lay()
    if not i or Busy(root) or lay.fixed[i.name] then return end
    if i.origScale == nil then i.origScale = root:GetScale() end
    local cur = root:GetScale() or 1
    local new = Clamp(math.floor((cur + STEP * delta) * 10 + 0.5) / 10)
    if new == cur then return end
    -- Keep its top-left corner where it is
    if not lay.pos[i.key] then
        NoteGameSpot(root)
        self:Save(root)
    end
    lay.scale[i.name] = new
    root:SetScale(new)
    self:Apply(root)
end

function FM:ResetScale(name)
    Lay().scale[name] = nil
    local root = self.roots[name]
    local i = root and info[root]
    if not i or i.origScale == nil then return end
    if Busy(root) then Later(root, function() FM:ResetScale(name) end) return end
    root:SetScale(i.origScale)
    self:Apply(root)
end

function FM:ResetAll()
    local lay = Lay()
    local keys = {}
    for key in pairs(lay.pos) do keys[key] = true end
    for name in pairs(lay.scale) do keys[name] = true end
    for key in pairs(keys) do
        self:ResetPosition(key)
        if not key:find("/", 1, true) then self:ResetScale(key) end
    end
    if self.panel and self.panel:IsShown() then self.panel:Refresh() end
end

-- Every frame as the layout in use wants it (after switching layouts)
function FM:Reapply()
    local lay = Lay()
    for key, f in pairs(self.frames) do
        local i = info[f]
        if i.isRoot then
            if lay.scale[i.name] then self:ApplyScale(f)
            elseif i.origScale ~= nil and not Busy(f) then f:SetScale(i.origScale) end
        end
        if f:IsShown() then
            if lay.pos[key] then self:Apply(f) else GameSpot(f) end
        end
    end
end

-- Use the layout shared by all characters (or this character's own). The
-- first character to share starts the shared layout from its own.
function FM:SetShared(on)
    local db = DB()
    if on and not next(db.layout.pos) and not next(db.layout.scale) then
        db.layout.pos = WM.Profiles and WM.Profiles.DeepCopy(db.pos) or db.pos
        db.layout.scale = WM.Profiles and WM.Profiles.DeepCopy(db.scale) or db.scale
        db.layout.fixed = WM.Profiles and WM.Profiles.DeepCopy(db.fixed) or db.fixed
    end
    db.useShared = on and true or false
    if On() then self:Reapply() end
    if self.panel and self.panel:IsShown() then self.panel:Refresh() end
end

-- ============================================
-- MOUSE
-- ============================================

-- What a drag on this frame moves: a pop-out placed on its own (or being
-- pulled off with Alt) moves itself; anything else moves its window
local function DragTarget(frame)
    local i = info[frame]
    if not i then return nil end
    if i.popout and (Lay().pos[i.key] or IsAlt()) then return frame end
    return i.root
end

local function OnMouseDown(frame, button)
    if not On() or button ~= "LeftButton" then return end
    local f = DragTarget(frame)
    local i = f and info[f]
    if not i or Lay().fixed[i.name] or Busy(f) or Busy(i.root) then return end
    if DB().shiftDrag and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    NoteGameSpot(f)
    i.userPlaced = f.IsUserPlaced and f:IsUserPlaced() or false
    i.movable = f.IsMovable and f:IsMovable() or false
    f:SetMovable(true)
    f:StartMoving()
    moving = f
end

-- The drag ended: remember the spot, and anchor it our way
function FM:StopMoving(f)
    if moving ~= f then return end
    moving = nil
    local i = info[f]
    f:StopMovingOrSizing()
    -- Not "user placed": the game's own layout cache stays out of it
    if f.SetUserPlaced then f:SetUserPlaced(i and i.userPlaced or false) end
    if i and not i.movable and f.SetMovable then f:SetMovable(false) end
    self:Save(f)
    self:Apply(f)
    if self.panel and self.panel:IsShown() then self.panel:Refresh() end
end

local function OnMouseUp(frame, button)
    local i = info[frame]
    if not i then return end
    if button == "LeftButton" then
        if moving then FM:StopMoving(moving) end
        return
    end
    if not On() or button ~= "RightButton" then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        -- A pop-out placed on its own goes back on its window; anything else
        -- puts the window back
        if i.popout and Lay().pos[i.key] then FM:ResetPosition(i.key)
        else FM:ResetPosition(i.name) end
    end
    if IsControlKeyDown and IsControlKeyDown() then FM:ResetScale(i.name) end
end

local function OnMouseWheel(frame, delta)
    if not On() or not DB().wheelScale or not (IsControlKeyDown and IsControlKeyDown()) then return end
    local i = info[frame]
    if i then FM:StepScale(i.root, delta > 0 and 1 or -1) end
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
    if i.key and frame.SetClampedToScreen then
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
    if i.key and i.clamped ~= nil and frame.SetClampedToScreen then frame:SetClampedToScreen(i.clamped) end
end

local function OnShow(f)
    if not On() then return end
    if info[f] and info[f].isRoot then FM:ApplyScale(f) end
    FM:Apply(f)
end

local function OnHide(f)
    if moving and (moving == f or info[moving].root == f) then FM:StopMoving(moving) end
end

-- The game re-placed a frame (opening it, or making room for another):
-- put it back on your spot
local function OnSetPoint(f)
    if applying or moving == f or not On() then return end
    local i = info[f]
    if not i or not Lay().pos[i.key] or Lay().fixed[i.name] then return end
    FM:Apply(f)
end

local function OnScaleForFit(frame)
    if On() and info[frame] and info[frame].isRoot then FM:ApplyScale(frame) end
end

-- key: set for frames we place (windows, and pop-outs)
local function Hook(frame, root, name, key, popout)
    if info[frame] then return end
    info[frame] = { root = root, name = name, isRoot = frame == root, key = key, popout = popout }
    frame:HookScript("OnMouseDown", OnMouseDown)
    frame:HookScript("OnMouseUp", OnMouseUp)
    frame:HookScript("OnMouseWheel", OnMouseWheel)
    if key then
        FM.frames[key] = frame
        frame:HookScript("OnShow", OnShow)
        frame:HookScript("OnHide", OnHide)
        if hooksecurefunc then hooksecurefunc(frame, "SetPoint", OnSetPoint) end
    end
end

-- Take on one window, its parts and its pop-outs, if this client has it
function FM:TakeOn(entry)
    local root = self.Resolve(entry.frame)
    if not root then return false end
    if Busy(root) then Later(entry, function() FM:TakeOn(entry) end) return false end
    self.roots[entry.frame] = root
    Hook(root, root, entry.frame, entry.frame)
    self:Prepare(root)
    local pop = {}
    for _, n in ipairs(entry.popouts or {}) do pop[n] = true end
    for _, partName in ipairs(entry.parts or {}) do
        local part = self.Resolve(partName)
        if part and part ~= root and not info[part] then
            if pop[partName] then Hook(part, root, entry.frame, entry.frame .. "/" .. partName, true)
            else Hook(part, root, entry.frame) end
            self:Prepare(part)
            if pop[partName] and part:IsShown() then OnShow(part) end
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

-- Settings changed: mouse, wheel and clamping again on every frame
function FM:Refresh()
    for frame in pairs(info) do self:Prepare(frame) end
end

-- ============================================
-- OPTIONS
-- ============================================

function FM.Title(name) return (WM.FrameMoverNames and WM.FrameMoverNames[name]) or name end

-- A layout key's title: "Character", or "Reputation details (off Character)"
function FM.KeyTitle(key)
    local window, part = key:match("^(.-)/(.+)$")
    if not part then return FM.Title(key) end
    return FM.Title(part) .. " (off " .. FM.Title(window) .. ")"
end

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

-- How many windows and pop-outs the layout in use has moved or resized
function FM:MovedKeys()
    local lay, seen, out = Lay(), {}, {}
    for key in pairs(lay.pos) do seen[key] = true end
    for name in pairs(lay.scale) do seen[name] = true end
    for key in pairs(seen) do out[#out + 1] = key end
    table.sort(out)
    return out
end

-- "Moved: ..." text for the window
function FM:MovedText()
    local lay, names = Lay(), {}
    for _, key in ipairs(self:MovedKeys()) do
        local t = self.KeyTitle(key)
        if lay.scale[key] then t = t .. string.format(" (size %d%%)", math.floor(lay.scale[key] * 100 + 0.5)) end
        if lay.fixed[key] then t = t .. " (not moving)" end
        names[#names + 1] = t
    end
    table.sort(names)
    local whose = DB().useShared and "the shared layout" or "this character"
    if #names == 0 then return "|cFF888888No windows moved yet in " .. whose .. ".|r" end
    return "Moved in " .. whose .. ": " .. table.concat(names, ", ")
end

local function ControlsNote(L)
    L:Note("|cFFFFFFFFDrag|r a window to move it (its tabs and inner panels too). |cFFFFFFFFCtrl + mouse wheel|r over it"
        .. " makes it bigger or smaller. |cFFFFFFFFShift + right-click|r puts it back where the game had it,"
        .. " |cFFFFFFFFCtrl + right-click|r puts its size back.")
    L:Note("|cFFFFFFFFAlt + drag|r a pop-out (reputation details, raid info, guild info, an opened mail, a calendar"
        .. " event, ...) to pull it off its window and place it on its own; after that a plain drag moves it, and"
        .. " |cFFFFFFFFShift + right-click|r puts it back on its window.")
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
    L:Checkbox({ label = "Use one layout for all my characters", get = function() return DB().useShared end,
        set = function(v) if live then FM:SetShared(v) else DB().useShared = v and true or false end end,
        tooltip = { "Shared layout", "On: this character uses the layout every sharing character uses, so a window"
            .. " moved on one is moved on all of them. Off: this character keeps its own. The first character to"
            .. " share starts the shared layout from its own; your own layout is kept for when you turn this off." } })
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
            if FM.selected then FM:ResetWindow(FM.selected); panel:Refresh() end end,
            tooltip = { "Reset its position", "Back where the game puts it, with its pop-outs back on it." } },
        { text = "Reset its size", width = 105, onClick = function()
            if FM.selected then FM:ResetScale(FM.selected); panel:Refresh() end end },
    })
    L:Checkbox({ label = "Don't move this window", get = function() return FM.selected and Lay().fixed[FM.selected] end,
        set = function(v)
            if not FM.selected then return end
            Lay().fixed[FM.selected] = v or nil
            if v then FM:ResetWindow(FM.selected); FM:ResetScale(FM.selected) end
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
        local f = moving
        moving = nil
        f:StopMovingOrSizing()
    end
    local lay = Lay()
    for key, f in pairs(self.frames) do
        local i = info[f]
        if i and not Busy(f) then
            if lay.pos[key] and f:IsShown() then GameSpot(f) end
            if i.isRoot and i.origScale ~= nil then f:SetScale(i.origScale) end
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
    for _, f in pairs(self.frames) do
        if f:IsShown() then OnShow(f) end
    end
end

-- The module's page in the guided setup
function FM:SetupPage(L)
    L:Note("Moves the game's own windows: character, spellbook, talents, bank, mailbox, the world map, the auction"
        .. " house, professions and the rest. Put them where you like; this character remembers the layout (or"
        .. " shares one with your other characters), and each window goes back to your spot whenever the game"
        .. " opens it.")
    ControlsNote(L)
    L:Note("Every window can be put back on its own, or all at once, from the Frame Mover window"
        .. " (|cFFFFFF00/wmachine move|r). If BlizzMove is installed, Frame Mover leaves the windows to it.")
    SettingBoxes(L, false)
end

function FM:GetQuickStatus()
    local other = self:OtherMover()
    if other then return "Off: " .. other .. " is loaded" end
    local n = #self:MovedKeys()
    local text = n == 0 and "No windows moved" or (n == 1 and "1 window moved" or (n .. " windows moved"))
    return text .. (DB().useShared and " (shared layout)" or "")
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
