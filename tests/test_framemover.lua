-- Frame Mover: dragging the game's windows (and their parts), Ctrl + wheel
-- sizes, Shift / Ctrl + right-click resets, the game re-placing a window,
-- load-on-demand windows, combat with protected windows, the per-window
-- "don't move" switch, turning the module off and on, its setup page, and
-- standing aside for BlizzMove. Never writes into the game's frames.
-- Usage: lua5.1 test_framemover.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Frames that know where they are, their scale and their mouse settings
local F = W.Frame
function F:GetScale() return self._scale or 1 end
function F:GetEffectiveScale()
    local s, f = 1, self
    while f do s = s * (f._scale or 1); f = f._parent end
    return s
end
function F:SetScale(s) self._scale = s end
function F:GetLeft() return self._left end
function F:GetTop() return self._top end
function F:EnableMouse(v) self._mouse = v and true or false end
function F:IsMouseEnabled() return self._mouse or false end
function F:EnableMouseWheel(v) self._wheel = v and true or false end
function F:IsMouseWheelEnabled() return self._wheel or false end
function F:SetClampedToScreen(v) self._clamped = v and true or false end
function F:IsClampedToScreen() return self._clamped or false end
function F:SetMovable(v) self._movable = v and true or false end
function F:IsMovable() return self._movable or false end
function F:SetUserPlaced(v) self._userPlaced = v and true or false end
function F:IsUserPlaced() return self._userPlaced or false end
function F:IsProtected() return self._protected or false end
function F:StartMoving() self._moving = true end
function F:StopMovingOrSizing() self._moving = false end

local combat, keys, loaded = false, {}, {}
env.InCombatLockdown = function() return combat end
env.IsShiftKeyDown = function() return keys.shift or false end
env.IsControlKeyDown = function() return keys.ctrl or false end
env.IsAltKeyDown = function() return keys.alt or false end
env.C_AddOns = { IsAddOnLoaded = function(a) return loaded[a] or false end }
env.SlashCmdList = {}
env.StaticPopup_Show = false     -- no dialog: WM:Confirm runs at once
env.unpack = unpack
-- Secure hooks: run after the original, like the client's
env.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then
        local orig = a[b]
        a[b] = function(...) local r = { orig(...) }; c(...); return unpack(r) end
    else
        local orig = env[a]
        env[a] = function(...) orig(...); b(...) end
    end
end

-- The game's windows: Character (with a tab panel), Mailbox, a protected
-- one, and the menu that must never be touched
local function Window(name, l, t)
    local f = W.NewFrame(name, env.UIParent)
    env[name] = f
    f:SetSize(380, 420)
    f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 16, -116)
    f._left, f._top = l or 16, t or 652
    return f
end
local CharacterFrame = Window("CharacterFrame")
local PaperDollFrame = W.NewFrame("PaperDollFrame", CharacterFrame)
env.PaperDollFrame = PaperDollFrame
local MailFrame = Window("MailFrame")
local OpenMailFrame = W.NewFrame("OpenMailFrame", MailFrame)
env.OpenMailFrame = OpenMailFrame
OpenMailFrame._wheel = true       -- scrolls by itself
local WorldMapFrame = Window("WorldMapFrame")
WorldMapFrame._protected = true
local GameMenuFrame = Window("GameMenuFrame")
env.UpdateScaleForFit = function() end

for _, f in ipairs({ "Core.lua", "UI.lua", "Data/FrameMover.lua", "Modules/FrameMover.lua" }) do W.load(f) end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local FM = WM.modules.FrameMover
local function DB() return env.WMFrameMoverDB end
local function Anchor(f) return f._points[#f._points] end

-- ============================================
-- DATA AND WIRING
-- ============================================

check("module registered", FM ~= nil and WM.FrameMover == FM)
local listed = {}
for _, e in ipairs(WM.FrameMoverData) do listed[e.frame] = true end
check("window list has the base windows", listed.CharacterFrame and listed.MailFrame and listed.WorldMapFrame
    and listed.SpellBookFrame and listed.BankFrame)
check("window list has load-on-demand windows", listed.PlayerTalentFrame and listed.AuctionFrame)
check("Escape menu is never moved", not listed.GameMenuFrame)
local named = true
for name in pairs(listed) do if not WM.FrameMoverNames[name] then named = false; io.write("unnamed: ", name, "\n") end end
check("every window has a name in the list", named)
check("layout per character, plus one shared layout", WM.Profiles.SCOPE.WMFrameMoverDB ~= nil
    and table.concat(WM.Profiles.SCOPE.WMFrameMoverDB.shared or {}, ",") == "layout")
local popouts = 0
for _, e in ipairs(WM.FrameMoverData) do
    local isPart = {}
    for _, p in ipairs(e.parts or {}) do isPart[p] = true end
    for _, p in ipairs(e.popouts or {}) do
        popouts = popouts + 1
        if not isPart[p] then io.write("pop-out not a part: ", p, "\n"); popouts = -999 end
        if not WM.FrameMoverNames[p] then io.write("pop-out unnamed: ", p, "\n"); popouts = -999 end
    end
end
check("pop-outs are parts of their window, each named", popouts >= 10)
check("card in the Interface group", (function()
    for _, g in ipairs(WM.MODULE_GROUPS) do
        for _, m in ipairs(g.modules) do if m == "FrameMover" then return g.title == "Interface" end end
    end
end)())
check("card explains itself", WM.MODULE_INFO.FrameMover.command == "move" and #WM.MODULE_INFO.FrameMover.about > 50)

-- ============================================
-- SETUP PAGE BEFORE IT HAS STARTED
-- ============================================

local function Page()
    local p = WM.UI:CreatePanel({ name = "WM_TestSetupFM", title = "t" })
    local page = p:NewPage()
    local L, specs = page.layout, {}
    local orig = L.Checkbox
    L.Checkbox = function(self, spec, ...)
        if type(spec.label) == "string" then specs[spec.label] = spec end
        return orig(self, spec, ...)
    end
    local ok, err = pcall(FM.SetupPage, FM, L)
    if not ok then io.write("SetupPage error: ", tostring(err), "\n") end
    L:Reflow()
    return ok and specs
end
local specs = Page()
check("setup page builds before it has started", specs ~= nil)
check("setup page: Shift option with a tooltip", specs and specs["Only move windows while Shift is held"]
    and specs["Only move windows while Shift is held"].tooltip)
check("setup page: resizing on by default", specs and specs["Ctrl + mouse wheel resizes a window"].get() == true)
check("setup page: on-screen on by default", specs and specs["Keep windows on the screen"].get() == true)
check("setup page touched no window", CharacterFrame._hooks.OnMouseDown == nil)

-- ============================================
-- START: TAKING THE WINDOWS ON
-- ============================================

local evFrame
local origRegister = WM.RegisterEvents
WM.RegisterEvents = function(_, fr) evFrame = fr end
FM:Initialize()
WM.RegisterEvents = origRegister
local function Event(ev, ...) evFrame._scripts.OnEvent(evFrame, ev, ...) end

check("Character window taken on", FM.roots.CharacterFrame == CharacterFrame and FM.info[CharacterFrame] ~= nil)
check("its tab panel moves it too", FM.info[PaperDollFrame] and FM.info[PaperDollFrame].root == CharacterFrame)
check("mouse on for the window and its parts", CharacterFrame._mouse and PaperDollFrame._mouse)
check("wheel on where nothing scrolls", CharacterFrame._wheel == true)
check("a scrolling part keeps its own wheel", FM.info[OpenMailFrame] and FM.info[OpenMailFrame].ownWheel == true)
check("kept on the screen", CharacterFrame._clamped == true)
check("Escape menu not touched", GameMenuFrame._hooks.OnMouseDown == nil and GameMenuFrame._mouse == nil)
check("talents not there yet", FM.roots.PlayerTalentFrame == nil)

-- ============================================
-- DRAGGING
-- ============================================

-- Drag the Character window by its tab panel
W.fire(PaperDollFrame, "OnMouseDown", "LeftButton")
check("drag on a part moves the whole window", CharacterFrame._moving == true and PaperDollFrame._moving == nil)
CharacterFrame._left, CharacterFrame._top = 500, 600
W.fire(PaperDollFrame, "OnMouseUp", "LeftButton")
check("drag stopped", CharacterFrame._moving == false)
check("position saved", DB().pos.CharacterFrame and DB().pos.CharacterFrame.x == 500 and DB().pos.CharacterFrame.y == 600)
local a = Anchor(CharacterFrame)
check("anchored by its top-left to the screen", #CharacterFrame._points == 1 and a[1] == "TOPLEFT"
    and a[2] == env.UIParent and a[3] == "BOTTOMLEFT" and a[4] == 500 and a[5] == 600)
check("not left 'user placed' (the game's layout cache stays out of it)", CharacterFrame._userPlaced == false)
check("moved window listed", FM:MovedText():find("Character", 1, true) ~= nil)
check("status counts it", FM:GetQuickStatus() == "1 window moved")

-- The game re-places it (opening it, or making room for another window)
CharacterFrame:ClearAllPoints()
CharacterFrame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 16, -116)
a = Anchor(CharacterFrame)
check("game re-placing it puts it back on your spot", #CharacterFrame._points == 1 and a[4] == 500 and a[5] == 600)
check("the game's spot remembered for a reset", FM.info[CharacterFrame].orig[1][4] == 16)

-- Shown again: on your spot
CharacterFrame:Hide()
CharacterFrame._points = { { "TOPLEFT", env.UIParent, "TOPLEFT", 16, -116 } }   -- where the game left it
CharacterFrame:Show()
check("shown again: on your spot", Anchor(CharacterFrame)[4] == 500)

-- Shift only
DB().shiftDrag = true
W.fire(MailFrame, "OnMouseDown", "LeftButton")
check("Shift-only: no move without Shift", not MailFrame._moving)
keys.shift = true
W.fire(MailFrame, "OnMouseDown", "LeftButton")
check("Shift-only: moves with Shift", MailFrame._moving == true)
MailFrame._left, MailFrame._top = 300, 500
W.fire(MailFrame, "OnMouseUp", "LeftButton")
keys.shift = false
DB().shiftDrag = false
check("second window saved", DB().pos.MailFrame and DB().pos.MailFrame.x == 300)

-- Right-click without a modifier does nothing
W.fire(MailFrame, "OnMouseUp", "RightButton")
check("plain right-click keeps the spot", DB().pos.MailFrame ~= nil)

-- ============================================
-- SIZE
-- ============================================

W.fire(CharacterFrame, "OnMouseWheel", 1)
check("wheel without Ctrl: no size change", CharacterFrame:GetScale() == 1 and DB().scale.CharacterFrame == nil)
keys.ctrl = true
W.fire(CharacterFrame, "OnMouseWheel", 1)
check("Ctrl + wheel up: bigger", CharacterFrame:GetScale() == 1.1 and DB().scale.CharacterFrame == 1.1)
a = Anchor(CharacterFrame)
check("top-left corner stays put", a[4] == 500 / 1.1 and a[5] == 600 / 1.1)
for _ = 1, 20 do W.fire(PaperDollFrame, "OnMouseWheel", 1) end
check("size stops at the most", CharacterFrame:GetScale() == FM.MAX_SCALE)
for _ = 1, 40 do W.fire(CharacterFrame, "OnMouseWheel", -1) end
check("size stops at the least", CharacterFrame:GetScale() == FM.MIN_SCALE)
W.fire(CharacterFrame, "OnMouseWheel", 1)
check("size steps of a tenth", CharacterFrame:GetScale() == 0.6)
-- The game fitting it to the screen again: back to your size
CharacterFrame._scale = 1
env.UpdateScaleForFit(CharacterFrame)
check("game's fit-to-screen: your size again", CharacterFrame:GetScale() == 0.6)
-- Ctrl + right-click: size back
W.fire(CharacterFrame, "OnMouseUp", "RightButton")
keys.ctrl = false
check("Ctrl + right-click: size back", CharacterFrame:GetScale() == 1 and DB().scale.CharacterFrame == nil)
check("position kept after a size reset", DB().pos.CharacterFrame ~= nil)

-- A size on a window you never dragged keeps its place too
keys.ctrl = true
W.fire(MailFrame, "OnMouseWheel", -1)
keys.ctrl = false
check("size on its own saved", DB().scale.MailFrame == 0.9)

-- ============================================
-- RESETS
-- ============================================

keys.shift = true
W.fire(PaperDollFrame, "OnMouseUp", "RightButton")
keys.shift = false
a = Anchor(CharacterFrame)
check("Shift + right-click: back where the game had it", DB().pos.CharacterFrame == nil and a[1] == "TOPLEFT"
    and a[2] == env.UIParent and a[3] == "TOPLEFT" and a[4] == 16 and a[5] == -116)
CharacterFrame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 30, -100)
check("reset window: the game places it again", Anchor(CharacterFrame)[4] == 30)

-- ============================================
-- DON'T MOVE THIS WINDOW
-- ============================================

FM:CreateUI()
FM.selected = "MailFrame"
DB().fixed.MailFrame = true
FM:ResetPosition("MailFrame"); FM:ResetScale("MailFrame")
W.fire(MailFrame, "OnMouseDown", "LeftButton")
check("'don't move' window can't be dragged", not MailFrame._moving)
check("'don't move' window back to normal", DB().pos.MailFrame == nil and MailFrame:GetScale() == 1)
keys.ctrl = true
W.fire(MailFrame, "OnMouseWheel", 1)
keys.ctrl = false
check("'don't move' window can't be resized", MailFrame:GetScale() == 1)
DB().fixed.MailFrame = nil

-- ============================================
-- LOAD-ON-DEMAND WINDOWS
-- ============================================

local Talents = Window("PlayerTalentFrame")
loaded.Blizzard_TalentUI = true
Event("ADDON_LOADED", "Blizzard_TalentUI")
check("talents taken on when their addon loads", FM.roots.PlayerTalentFrame == Talents and Talents._mouse == true)
Event("ADDON_LOADED", "SomeOtherAddon")
check("other addons ignored", true)

-- ============================================
-- COMBAT AND PROTECTED WINDOWS
-- ============================================

combat = true
W.fire(WorldMapFrame, "OnMouseDown", "LeftButton")
check("protected window can't be dragged in combat", not WorldMapFrame._moving)
-- A saved spot for it waits for combat to end
DB().pos.WorldMapFrame = { x = 100, y = 700 }
WorldMapFrame:SetPoint("CENTER", 0, 0)
check("protected window not re-placed in combat", Anchor(WorldMapFrame)[1] == "CENTER")
W.fire(CharacterFrame, "OnMouseDown", "LeftButton")
check("unprotected windows still move in combat", CharacterFrame._moving == true)
CharacterFrame._left, CharacterFrame._top = 200, 650
W.fire(CharacterFrame, "OnMouseUp", "LeftButton")
combat = false
Event("PLAYER_REGEN_ENABLED")
a = Anchor(WorldMapFrame)
check("after combat: protected window on its spot", a[1] == "TOPLEFT" and a[4] == 100 and a[5] == 700)

-- ============================================
-- NOTHING WRITTEN INTO THE GAME'S FRAMES
-- ============================================

local clean = true
for _, f in ipairs({ CharacterFrame, PaperDollFrame, MailFrame, OpenMailFrame, WorldMapFrame, Talents }) do
    for k in pairs(f) do
        if type(k) == "string" and not k:find("^_") and k ~= "SetPoint" then clean = false; io.write("wrote: ", k, "\n") end
    end
end
check("no fields written into the game's frames (only the secure SetPoint hook)", clean)

-- ============================================
-- OFF AND ON
-- ============================================

check("Character on your spot before turning off", Anchor(CharacterFrame)[4] == 200)
WM:SetModuleOn("FrameMover", false)
a = Anchor(CharacterFrame)
check("off: open window back where the game had it", a[3] == "TOPLEFT" and a[4] == 30)
check("off: mouse back as the game had it", Talents._mouse == false and CharacterFrame._wheel == false)
check("off: clamping back", CharacterFrame._clamped == false)
check("off: layout still saved for later", DB().pos.CharacterFrame ~= nil)
check("off: window closed", not env.WM_FrameMoverFrame:IsShown())
W.fire(CharacterFrame, "OnMouseDown", "LeftButton")
check("off: no dragging", not CharacterFrame._moving)
CharacterFrame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 40, -90)
check("off: the game places windows itself", Anchor(CharacterFrame)[4] == 40)
keys.ctrl = true
W.fire(CharacterFrame, "OnMouseWheel", 1)
keys.ctrl = false
check("off: no resizing", CharacterFrame:GetScale() == 1)
local Inspect = Window("InspectFrame")
loaded.Blizzard_InspectUI = true
Event("ADDON_LOADED", "Blizzard_InspectUI")
check("off: new windows left alone", FM.roots.InspectFrame == nil)

FM._wmStarted = true
WM:SetModuleOn("FrameMover", true)
check("on: windows loaded meanwhile taken on", FM.roots.InspectFrame == Inspect)
check("on: open window back on your spot", Anchor(CharacterFrame)[4] == 200)
check("on: mouse and wheel again", Talents._mouse == true and CharacterFrame._wheel == true)

-- Settings change at once
DB().wheelScale = false
FM:Refresh()
check("resizing off: wheel freed", CharacterFrame._wheel == false)
DB().wheelScale = true
FM:Refresh()

-- ============================================
-- THE WINDOW AND COMMANDS
-- ============================================

local panel = FM:CreateUI()
check("window built", panel ~= nil and env.WM_FrameMoverFrame == panel)
local opts = FM:WindowOptions()
check("window list sorted by name", #opts > 40 and opts[1].text <= opts[2].text)
FM:Command("reset")
check("move reset: every window back", next(DB().pos) == nil and next(DB().scale) == nil
    and Anchor(CharacterFrame)[4] == 40)
check("status after reset", FM:GetQuickStatus() == "No windows moved")

-- ============================================
-- POP-OUTS: ALT + DRAG PULLS ONE OFF ITS WINDOW
-- ============================================

local POP = "MailFrame/OpenMailFrame"
OpenMailFrame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 0, 0)   -- the game docks it beside the mailbox
OpenMailFrame._left, OpenMailFrame._top = 396, 652
local oi = FM.info[OpenMailFrame]
check("opened mail is a pop-out of the mailbox", oi and oi.popout and oi.key == POP and FM.frames[POP] == OpenMailFrame)
check("a plain part is not", FM.info[PaperDollFrame].popout == nil and FM.info[PaperDollFrame].key == nil)
W.fire(OpenMailFrame, "OnMouseDown", "LeftButton")
check("plain drag on a pop-out still moves its window", MailFrame._moving == true and not OpenMailFrame._moving)
W.fire(OpenMailFrame, "OnMouseUp", "LeftButton")
FM:ResetWindow("MailFrame")
env.IsAltKeyDown = function() return true end
W.fire(OpenMailFrame, "OnMouseDown", "LeftButton")
check("Alt + drag pulls it off", OpenMailFrame._moving == true and not MailFrame._moving)
OpenMailFrame._left, OpenMailFrame._top = 700, 400
W.fire(OpenMailFrame, "OnMouseUp", "LeftButton")
env.IsAltKeyDown = function() return false end
a = Anchor(OpenMailFrame)
check("placed on its own", FM.Layout().pos[POP] and FM.Layout().pos[POP].x == 700
    and a[1] == "TOPLEFT" and a[2] == env.UIParent and a[3] == "BOTTOMLEFT" and a[4] == 700)
check("listed as a pop-out", FM:MovedText():find("Opened mail (off Mailbox)", 1, true) ~= nil)
W.fire(OpenMailFrame, "OnMouseDown", "LeftButton")
check("once placed, a plain drag moves it", OpenMailFrame._moving == true and not MailFrame._moving)
OpenMailFrame._left, OpenMailFrame._top = 720, 410
W.fire(OpenMailFrame, "OnMouseUp", "LeftButton")
check("moved again", FM.Layout().pos[POP].x == 720)
-- The game docks it again when a mail opens: back on your spot
OpenMailFrame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 0, 0)
check("the game docking it: back on your spot", Anchor(OpenMailFrame)[4] == 720)
-- In a resized window, its spot stays on the screen where you put it
MailFrame._scale = 0.5
OpenMailFrame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 0, 0)
check("window resized: the pop-out keeps its screen spot", Anchor(OpenMailFrame)[4] == 720 / 0.5)
MailFrame._scale = 1
-- Shift + right-click on the window itself: the window, not the pop-out
keys.shift = true
W.fire(MailFrame, "OnMouseUp", "RightButton")
check("Shift + right-click on the window leaves the pop-out placed", FM.Layout().pos[POP] ~= nil)
W.fire(OpenMailFrame, "OnMouseUp", "RightButton")
keys.shift = false
a = Anchor(OpenMailFrame)
check("Shift + right-click on it: back on its window", FM.Layout().pos[POP] == nil and a[2] == MailFrame and a[3] == "TOPRIGHT")
-- Resetting a window takes its pop-outs back too
env.IsAltKeyDown = function() return true end
W.fire(OpenMailFrame, "OnMouseDown", "LeftButton")
W.fire(OpenMailFrame, "OnMouseUp", "LeftButton")
env.IsAltKeyDown = function() return false end
check("placed again", FM.Layout().pos[POP] ~= nil)
FM:ResetWindow("MailFrame")
check("window reset: its pop-outs go back on it", FM.Layout().pos[POP] == nil and Anchor(OpenMailFrame)[2] == MailFrame)

-- ============================================
-- ONE LAYOUT FOR ALL CHARACTERS
-- ============================================

W.fire(CharacterFrame, "OnMouseDown", "LeftButton")
CharacterFrame._left, CharacterFrame._top = 111, 555
W.fire(CharacterFrame, "OnMouseUp", "LeftButton")
check("own layout has the Character window", DB().pos.CharacterFrame.x == 111 and FM.Layout() == DB())
FM:SetShared(true)
check("sharing: the shared layout starts from this character's", DB().useShared and FM.Layout() == DB().layout
    and DB().layout.pos.CharacterFrame.x == 111 and DB().layout.pos.CharacterFrame ~= DB().pos.CharacterFrame)
check("status says shared", FM:GetQuickStatus():find("(shared layout)", 1, true) ~= nil)
W.fire(CharacterFrame, "OnMouseDown", "LeftButton")
CharacterFrame._left, CharacterFrame._top = 222, 444
W.fire(CharacterFrame, "OnMouseUp", "LeftButton")
check("moves go to the shared layout, not your own", DB().layout.pos.CharacterFrame.x == 222 and DB().pos.CharacterFrame.x == 111)
FM:SetShared(false)
check("back to your own: the window goes to your spot", Anchor(CharacterFrame)[4] == 111 and FM.Layout() == DB())
DB().pos.CharacterFrame = nil
FM:SetShared(true)
check("sharing again keeps the shared layout", DB().layout.pos.CharacterFrame.x == 222 and Anchor(CharacterFrame)[4] == 222)
FM:SetShared(false)
check("own layout with nothing: the game's spot", Anchor(CharacterFrame)[1] ~= "TOPLEFT" or Anchor(CharacterFrame)[3] ~= "BOTTOMLEFT")
local sp = Page()
check("setup page: shared layout option", sp and sp["Use one layout for all my characters"]
    and sp["Use one layout for all my characters"].tooltip)

-- ============================================
-- BLIZZMOVE LOADED: STAND ASIDE
-- ============================================

loaded.BlizzMove = true
check("other mover found", FM:OtherMover() == "BlizzMove")
check("status says why", FM:GetQuickStatus():find("BlizzMove", 1, true) ~= nil)
local Macro = Window("MacroFrame")
loaded.Blizzard_MacroUI = true
Event("ADDON_LOADED", "Blizzard_MacroUI")
check("with BlizzMove: new windows left to it", FM.roots.MacroFrame == nil and Macro._mouse == nil)
loaded.BlizzMove = nil

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
