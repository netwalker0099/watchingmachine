-- Watching Machine: shared panel and widget builder
--
-- Every settings window used to be laid out by hand: a running yOffset,
-- per-module checkbox and slider boilerplate, and a frame height measured
-- by eye. That is how panels kept ending up taller than the screen. This
-- builds them from a vertical list of rows instead:
--
--   local panel = WM.UI:CreatePanel({ name = "WM_FooFrame", title = "Foo", width = 360 })
--   local L = panel.layout
--   L:Checkbox({ label = "Enable", get = function() return FooDB.enabled end,
--                set = function(v) FooDB.enabled = v end, tooltip = { "Enable", "Explains it." } })
--   L:Section({ key = "alerts", title = "Alerts" })
--   L:Slider({ label = "Delay", min = 2, max = 15, step = 1, get = ..., set = ... })
--   panel:AddFooterButton({ text = "Test", onClick = ... }, "RIGHT")
--   panel:Finish()
--
-- What every panel gets:
--   * title, close button, Escape to close, theme skin (via RegisterSkinnedPanel)
--   * position remembered in WatchingMachineDB.panels[name]
--   * height fitted to its content and capped at the screen; the body
--     scrolls when the content is taller (or, with scroll = false, a Fill
--     area such as a list absorbs the difference)
--   * collapsible sections, remembered per panel
--   * panel:Refresh() re-reads every control from its get(), so a panel
--     never needs to be destroyed and rebuilt to show new state
--
-- Widget specs share these fields:
--   label     string or function returning one (re-read on Refresh)
--   tooltip   { "Title", "Wrapped line", { "Coloured line", r, g, b }, " " }
--   get/set   read and write the saved value
--   disabled  optional function; true greys the control out
--   indent    extra left offset in a vertical layout

local AddonName, WM = ...
local UI = {}
WM.UI = UI

local TOP_PAD = 40          -- title band
local SIDE_PAD = 12
local SCROLLBAR_PAD = 30    -- room for the scroll bar on the right
local FOOTER_H = 44
local BOTTOM_PAD = 14
local SCREEN_MARGIN = 16

local ROW_H = {
    header = 22, checkbox = 24, slider = 44, cycle = 24, button = 26,
    editbox = 26, separator = 9, section = 24,
}

local nameCounter = 0
local function UniqueName(prefix)
    nameCounter = nameCounter + 1
    return (prefix or "WM_UI") .. nameCounter
end

local function Eval(v)
    if type(v) == "function" then return v() end
    return v
end

-- ============================================
-- TOOLTIPS
-- ============================================

function UI.ShowTooltip(owner, tip)
    if not tip or #tip == 0 then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(tip) do
        if i == 1 then
            GameTooltip:AddLine(line, 1, 0.8, 0)
        elseif type(line) == "table" then
            GameTooltip:AddLine(line[1], line[2] or 0.6, line[3] or 0.8, line[4] or 1, true)
        else
            GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

function UI.SetTooltip(widget, tip)
    if not tip then return end
    widget:SetScript("OnEnter", function(self) UI.ShowTooltip(self, Eval(tip)) end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Grey a control out (or back) without destroying it
local function ApplyDisabled(widget, spec)
    if not spec.disabled then return end
    local off = spec.disabled() and true or false
    if off then
        if widget.Disable then widget:Disable() end
        widget:SetAlpha(0.4)
    else
        if widget.Enable then widget:Enable() end
        widget:SetAlpha(1)
    end
end

-- ============================================
-- WIDGETS
-- ============================================
-- Each takes a parent frame and a spec and returns the widget, with a
-- Refresh method that re-reads its value. Placement is the caller's job.

function UI.Checkbox(parent, spec)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    if spec.font then cb.Text:SetFontObject(spec.font) end
    cb:SetScript("OnClick", function(self)
        if spec.set then spec.set(self:GetChecked() and true or false) end
        if spec.onChange then spec.onChange(self:GetChecked() and true or false) end
    end)
    UI.SetTooltip(cb, spec.tooltip)
    function cb:Refresh()
        self.Text:SetText(Eval(spec.label) or "")
        if spec.get then self:SetChecked(spec.get() and true or false) end
        ApplyDisabled(self, spec)
    end
    cb:Refresh()
    return cb
end

-- Slider with "Label: value" above it and low/high captions below
function UI.Slider(parent, spec)
    local width = spec.width or 160
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width + 6, 40)

    local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 0, 0)

    local value = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", label, "RIGHT", 5, 0)

    local step = spec.step or 1
    local fmt = spec.format or function(v) return tostring(v) end

    local s = CreateFrame("Slider", spec.name or UniqueName("WM_UISlider"), box, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 3, -18)
    s:SetSize(width, 16)
    s:SetMinMaxValues(spec.min, spec.max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low = s.Low or _G[s:GetName() .. "Low"]
    local high = s.High or _G[s:GetName() .. "High"]
    local text = s.Text or _G[s:GetName() .. "Text"]
    if low then low:SetText(spec.lowText or fmt(spec.min)) end
    if high then high:SetText(spec.highText or fmt(spec.max)) end
    if text then text:SetText("") end

    local refreshing = false
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor((v - spec.min) / step + 0.5) * step + spec.min
        value:SetText(fmt(v))
        if not refreshing and spec.set then spec.set(v) end
    end)
    UI.SetTooltip(s, spec.tooltip)

    box.slider = s
    function box:Refresh()
        label:SetText((Eval(spec.label) or "") .. ":")
        local v = spec.get and spec.get() or spec.min
        refreshing = true
        s:SetValue(v)
        refreshing = false
        value:SetText(fmt(v))
        ApplyDisabled(s, spec)
    end
    box:Refresh()
    return box
end

-- Button that steps through a fixed list of options, with an optional
-- grey prefix label ("To:"). options = { { value = "RAID", text = "Raid" }, ... }
function UI.Cycle(parent, spec)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(1, 20)

    local prefix
    if spec.label then
        prefix = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        prefix:SetPoint("LEFT", 0, 0)
    end

    local btn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    btn:SetSize(spec.width or 66, 18)
    if prefix then
        btn:SetPoint("LEFT", prefix, "RIGHT", 4, 0)
    else
        btn:SetPoint("LEFT", 0, 0)
    end

    local function Current()
        local v = spec.get and spec.get()
        if v == nil then v = spec.default end
        return v
    end

    btn:SetScript("OnClick", function()
        local cur, opts = Current(), spec.options
        local nextIdx = 1
        for i, o in ipairs(opts) do
            if o.value == cur then nextIdx = (i % #opts) + 1 break end
        end
        if spec.set then spec.set(opts[nextIdx].value) end
        box:Refresh()
    end)
    UI.SetTooltip(btn, spec.tooltip)

    box.button = btn
    function box:Refresh()
        if prefix then prefix:SetText("|cFF888888" .. (Eval(spec.label) or "") .. "|r") end
        local cur = Current()
        local shown = tostring(cur)
        for _, o in ipairs(spec.options) do
            if o.value == cur then shown = o.text break end
        end
        btn:SetText(shown)
        ApplyDisabled(btn, spec)
    end
    box:Refresh()
    return box
end

-- A row of buttons where exactly one is current (shown green)
function UI.Choice(parent, spec)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(1, 20)

    local prev
    if spec.label then
        prev = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        prev:SetPoint("LEFT", 0, 0)
        prev:SetText("|cFF888888" .. spec.label .. "|r")
    end

    local buttons = {}
    for i, o in ipairs(spec.options) do
        local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        b:SetSize(o.width or 50, 18)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 5 or 2, 0)
        else
            b:SetPoint("LEFT", 0, 0)
        end
        b:SetScript("OnClick", function()
            if spec.set then spec.set(o.value) end
            box:Refresh()
        end)
        UI.SetTooltip(b, o.tooltip)
        buttons[i] = b
        prev = b
    end

    function box:Refresh()
        local cur = spec.get and spec.get()
        if cur == nil then cur = spec.default end
        for i, o in ipairs(spec.options) do
            buttons[i]:SetText(o.value == cur and ("|cFF00FF00" .. o.text .. "|r") or o.text)
        end
    end
    box:Refresh()
    return box
end

-- Plain button. confirm = true needs a second click within 3s, with the
-- label switched to confirmText meanwhile ("Sure?").
function UI.Button(parent, spec)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(spec.width or 100, spec.height or 20)
    if spec.small and b.GetFontString and b:GetFontString() then
        b:GetFontString():SetFont(GameFontNormalSmall:GetFont())
    end
    local armed = false
    b:SetScript("OnClick", function(self)
        if spec.confirm and not armed then
            armed = true
            self:SetText("|cFFFF0000" .. (spec.confirmText or "Sure?") .. "|r")
            WM.RunAfter(3, function()
                if armed then armed = false; self:SetText(Eval(spec.text)) end
            end)
            return
        end
        armed = false
        self:SetText(Eval(spec.text))
        if spec.onClick then spec.onClick(self) end
    end)
    UI.SetTooltip(b, spec.tooltip)
    function b:Refresh()
        if not armed then self:SetText(Eval(spec.text) or "") end
        ApplyDisabled(self, spec)
    end
    b:Refresh()
    return b
end

-- Text box with an optional label in front. With set(), the value is saved
-- on Enter and when focus leaves; Escape puts the saved value back. With
-- onEnter(text), Enter runs an action instead (and clears if clearOnEnter).
function UI.EditBox(parent, spec)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(1, 20)

    local label
    if spec.label then
        label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(spec.label)
        if spec.labelColorKey then WM:ThemeText(label, spec.labelColorKey) end
    end

    local e = CreateFrame("EditBox", spec.name or UniqueName("WM_UIEdit"), box, "InputBoxTemplate")
    e:SetSize(spec.width or 150, 20)
    e:SetAutoFocus(false)
    if spec.maxLetters then e:SetMaxLetters(spec.maxLetters) end
    if label then
        e:SetPoint("LEFT", label, "RIGHT", 10, 0)
    else
        e:SetPoint("LEFT", 6, 0)
    end

    local function Save(self)
        if spec.set then spec.set(strtrim(self:GetText() or "")) end
    end
    e:SetScript("OnEnterPressed", function(self)
        if spec.onEnter then
            local t = strtrim(self:GetText() or "")
            if t ~= "" then spec.onEnter(t) end
            if spec.clearOnEnter then self:SetText("") end
        else
            Save(self)
        end
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        if not spec.onEnter then Save(self) end
    end)
    e:SetScript("OnEscapePressed", function(self)
        if spec.get then self:SetText(spec.get() or "") end
        self:ClearFocus()
    end)
    UI.SetTooltip(e, spec.tooltip)

    box.editBox = e
    function box:GetText() return e:GetText() end
    function box:SetText(t) e:SetText(t) end
    function box:Refresh()
        if spec.get and not e:HasFocus() then e:SetText(spec.get() or "") end
        ApplyDisabled(e, spec)
    end
    box:Refresh()
    return box
end

-- Font string whose text can come from a function (re-read on Refresh)
function UI.Text(parent, spec)
    local fs = parent:CreateFontString(nil, "OVERLAY", spec.font or "GameFontHighlightSmall")
    if spec.width then fs:SetWidth(spec.width) end
    fs:SetJustifyH(spec.justify or "LEFT")
    if spec.colorKey then WM:ThemeText(fs, spec.colorKey) end
    function fs:Refresh() self:SetText(Eval(spec.text) or "") end
    fs:Refresh()
    return fs
end

-- ============================================
-- ROWS
-- ============================================
-- A row is a frame of fixed height in a layout. Its widget methods place a
-- widget at x (left edge, vertically centred) and track it for Refresh.

local function TrackOn(row, widget)
    row.layout:Track(widget)
    return widget
end

local function PlaceLeft(row, widget, x)
    widget:ClearAllPoints()
    widget:SetPoint("LEFT", row.frame, "LEFT", x or 0, 0)
    return widget
end

local RowMethods = {}
function RowMethods:Checkbox(spec, x) return TrackOn(self, PlaceLeft(self, UI.Checkbox(self.frame, spec), x)) end
function RowMethods:Cycle(spec, x)    return TrackOn(self, PlaceLeft(self, UI.Cycle(self.frame, spec), x)) end
function RowMethods:Choice(spec, x)   return TrackOn(self, PlaceLeft(self, UI.Choice(self.frame, spec), x)) end
function RowMethods:Button(spec, x)   return TrackOn(self, PlaceLeft(self, UI.Button(self.frame, spec), x)) end
function RowMethods:EditBox(spec, x)  return TrackOn(self, PlaceLeft(self, UI.EditBox(self.frame, spec), x)) end
function RowMethods:Text(spec, x)     return TrackOn(self, PlaceLeft(self, UI.Text(self.frame, spec), x)) end
function RowMethods:Slider(spec, x)   return TrackOn(self, PlaceLeft(self, UI.Slider(self.frame, spec), x)) end
-- Anchor relative to the row's right edge instead (x is the gap)
function RowMethods:RightButton(spec, gap)
    local b = UI.Button(self.frame, spec)
    b:SetPoint("RIGHT", self.frame, "RIGHT", -(gap or 0), 0)
    return TrackOn(self, b)
end
function RowMethods:RightText(spec, gap)
    local fs = UI.Text(self.frame, spec)
    fs:SetPoint("RIGHT", self.frame, "RIGHT", -(gap or 0), 0)
    return TrackOn(self, fs)
end

-- ============================================
-- LAYOUT
-- ============================================

local Layout = {}
Layout.__index = Layout

local function NewLayout(panel, content, width)
    return setmetatable({
        panel = panel, content = content, width = width,
        rows = {}, widgets = {}, sections = {}, currentSection = nil,
    }, Layout)
end

function Layout:Track(widget)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

-- Low level: append a row of the given height. Returns a row object with
-- the widget placement methods above, plus .frame for anything custom.
function Layout:Row(height)
    local f = CreateFrame("Frame", nil, self.content)
    f:SetHeight(height)
    local row = { frame = f, height = height, layout = self, section = self.currentSection }
    for k, fn in pairs(RowMethods) do row[k] = fn end
    self.rows[#self.rows + 1] = row
    return row
end

function Layout:Space(height)
    return self:Row(height or 8)
end

function Layout:Header(text)
    local row = self:Row(ROW_H.header)
    local fs = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText(text)
    WM:ThemeText(fs, "headerColor")
    row.text = fs
    return row
end

function Layout:Separator()
    local row = self:Row(ROW_H.separator)
    local tex = row.frame:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    tex:SetPoint("LEFT", 3, 0)
    tex:SetPoint("RIGHT", -3, 0)
    WM:ThemeTexture(tex, "separatorColor")
    return row
end

function Layout:Checkbox(spec)
    local row = self:Row(ROW_H.checkbox)
    return row:Checkbox(spec, 8 + (spec.indent or 0)), row
end

function Layout:Slider(spec)
    local row = self:Row(ROW_H.slider)
    return row:Slider(spec, 12 + (spec.indent or 0)), row
end

function Layout:Cycle(spec)
    local row = self:Row(ROW_H.cycle)
    return row:Cycle(spec, 12 + (spec.indent or 0)), row
end

function Layout:EditBox(spec)
    local row = self:Row(ROW_H.editbox)
    return row:EditBox(spec, 12 + (spec.indent or 0)), row
end

-- Several buttons side by side
function Layout:Buttons(specs, indent)
    local row = self:Row(ROW_H.button)
    local x = 12 + (indent or 0)
    local out = {}
    for i, spec in ipairs(specs) do
        out[i] = row:Button(spec, x)
        x = x + (spec.width or 100) + 5
    end
    return out, row
end

-- Wrapped grey text. Height follows the text, measured on Reflow.
function Layout:Note(text, indent)
    local row = self:Row(16)
    indent = 12 + (indent or 0)
    local fs = UI.Text(row.frame, {
        text = function()
            local t = Eval(text) or ""
            return t ~= "" and ("|cFF888888" .. t .. "|r") or ""
        end,
        width = self.width - indent - 8,
    })
    fs:SetPoint("TOPLEFT", indent, -2)
    self:Track(fs)
    row.measure = function()
        local h = fs.GetStringHeight and fs:GetStringHeight() or 0
        return math.max(16, math.floor((h or 0) + 6))
    end
    row.text = fs
    return row
end

-- Collapsible section. Rows added after it belong to it until the next
-- Section or EndSection. Collapsed state is remembered per panel.
function Layout:Section(spec)
    local state = self.panel:GetState()
    state.collapsed = state.collapsed or {}
    local key = spec.key
    if state.collapsed[key] == nil then state.collapsed[key] = spec.collapsed and true or false end

    self.currentSection = nil
    local row = self:Row(ROW_H.section)
    local f = row.frame
    f:EnableMouse(true)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 6, 0)

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    fs:SetText(spec.title)
    WM:ThemeText(fs, "headerColor")

    local section = { key = key, row = row, title = spec.title }
    self.sections[key] = section
    local panel = self.panel

    function section:IsCollapsed() return state.collapsed[key] and true or false end
    function section:SetCollapsed(v)
        state.collapsed[key] = v and true or false
        panel:Reflow()
    end
    local function UpdateIcon()
        icon:SetTexture(section:IsCollapsed()
            and "Interface\\Buttons\\UI-PlusButton-Up"
            or "Interface\\Buttons\\UI-MinusButton-Up")
    end
    section.UpdateIcon = UpdateIcon
    UpdateIcon()

    f:SetScript("OnMouseUp", function()
        section:SetCollapsed(not section:IsCollapsed())
    end)
    UI.SetTooltip(f, spec.tooltip)

    if spec.rightText then
        local rt = UI.Text(f, { text = spec.rightText })
        rt:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        self:Track(rt)
    end

    self.currentSection = section
    return section
end

function Layout:EndSection()
    self.currentSection = nil
end

-- Non-scrolling panels only: a frame from the current position to the
-- bottom of the body, for a list that should take whatever room is left.
function Layout:Fill(minHeight)
    local f = CreateFrame("Frame", nil, self.content)
    self.fill = { frame = f, minHeight = minHeight or 60, section = self.currentSection }
    return f
end

-- Stack visible rows top to bottom. Returns the content height.
function Layout:Reflow()
    local y = 0
    for _, row in ipairs(self.rows) do
        local hidden = row.hidden or (row.section and row.section:IsCollapsed())
        if hidden then
            row.frame:Hide()
        else
            if row.measure then row.height = row.measure() end
            row.frame:SetHeight(row.height)
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            row.frame:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            row.frame:Show()
            y = y + row.height
        end
    end
    for _, s in pairs(self.sections) do s.UpdateIcon() end
    if self.fill then
        local f = self.fill.frame
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        f:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", 0, 0)
        y = y + self.fill.minHeight
    end
    self.height = y
    return y
end

-- Content offset of a section's header, for scrolling to it
function Layout:SectionOffset(key)
    local section = self.sections[key]
    if not section then return 0 end
    local y = 0
    for _, row in ipairs(self.rows) do
        if row == section.row then return y end
        if not (row.hidden or (row.section and row.section:IsCollapsed())) then
            y = y + row.height
        end
    end
    return 0
end

-- ============================================
-- PANEL
-- ============================================

local Panel = {}

local function PanelStore()
    if not WatchingMachineDB then return {} end
    WatchingMachineDB.panels = WatchingMachineDB.panels or {}
    return WatchingMachineDB.panels
end

function Panel:GetState()
    local store = PanelStore()
    local key = self:GetName()
    store[key] = store[key] or {}
    return store[key]
end

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point then return end
    frame:GetState().pos = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function RestorePosition(frame)
    local pos = frame:GetState().pos
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER")
    end
end

-- Size to content, capped at maxHeight and the screen
function Panel:Fit()
    local opts = self.opts
    local footer = (#self.footerButtons > 0) and FOOTER_H or BOTTOM_PAD
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", SIDE_PAD, -TOP_PAD)
    self.body:SetPoint("BOTTOMRIGHT", -(opts.scroll and SCROLLBAR_PAD or SIDE_PAD), footer)

    local wanted
    if opts.height then
        wanted = opts.height
    else
        wanted = TOP_PAD + (self.layout.height or 0) + footer + 4
    end
    local cap = opts.maxHeight or wanted
    local screen = UIParent and UIParent:GetHeight() or 0
    if screen and screen > 0 then cap = math.min(cap, math.floor(screen) - SCREEN_MARGIN) end
    local h = math.max(math.min(wanted, cap), opts.minHeight or 120)
    self:SetHeight(h)

    if opts.scroll then
        local view = h - TOP_PAD - footer
        self.content:SetHeight(math.max(self.layout.height or 0, 1))
        local maxScroll = math.max(0, (self.layout.height or 0) - view)
        if self.body:GetVerticalScroll() > maxScroll then self.body:SetVerticalScroll(maxScroll) end
        if self.scrollBar then
            if maxScroll > 0 then self.scrollBar:Show() else self.scrollBar:Hide() end
        end
    end
end

function Panel:Reflow()
    self.layout:Reflow()
    self:Fit()
end

function Panel:Refresh()
    for _, w in ipairs(self.layout.widgets) do
        if w.Refresh then w:Refresh() end
    end
    for _, b in ipairs(self.footerButtons) do
        if b.Refresh then b:Refresh() end
    end
    if self.opts.onRefresh then self.opts.onRefresh(self) end
    self:Reflow()
end

-- Open, expand a section and bring it into view
function Panel:ShowSection(key)
    local s = self.layout.sections[key]
    if s and s:IsCollapsed() then s:SetCollapsed(false) end
    self:Show()
    if self.opts.scroll and s then
        self:Reflow()
        local maxScroll = math.max(0, (self.layout.height or 0) - (self:GetHeight() - TOP_PAD - FOOTER_H))
        self.body:SetVerticalScroll(math.min(self.layout:SectionOffset(key), maxScroll))
    end
end

function Panel:AddFooterButton(spec, side)
    local b = UI.Button(self, spec)
    local same = 0
    for _, other in ipairs(self.footerButtons) do
        if other.side == (side or "LEFT") then same = same + (other.width or 100) + 6 end
    end
    if side == "RIGHT" then
        b:SetPoint("BOTTOMRIGHT", -(20 + same), 15)
    else
        b:SetPoint("BOTTOMLEFT", 20 + same, 15)
    end
    b.side, b.width = side or "LEFT", spec.width or 100
    self.footerButtons[#self.footerButtons + 1] = b
    return b
end

-- Call once all rows are added
function Panel:Finish()
    self:Reflow()
    return self
end

-- opts:
--   name       global frame name (required: Escape and saved state use it)
--   title      title text; titleColor = "RRGGBB" for a module colour,
--              otherwise the theme header colour
--   width      default 380
--   height     fixed height (still capped at the screen); omit to fit content
--   maxHeight  cap for fitted panels (default: the screen)
--   minHeight  default 120
--   scroll     default true; false for panels using Layout:Fill
--   strata     default "HIGH"
--   onShow     extra OnShow handler (after Refresh)
--   onRefresh  called at the end of every Refresh
function UI:CreatePanel(opts)
    assert(opts and opts.name, "WM.UI:CreatePanel needs a name")
    if opts.scroll == nil then opts.scroll = true end
    local width = opts.width or 380

    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    for k, fn in pairs(Panel) do frame[k] = fn end
    frame.opts = opts
    frame.footerButtons = {}

    frame:SetWidth(width)
    frame:SetHeight(opts.height or 200)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:SetFrameStrata(opts.strata or "HIGH")
    frame:Hide()
    RestorePosition(frame)

    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    if opts.titleColor then
        title:SetText("|cFF" .. opts.titleColor .. (opts.title or "") .. "|r")
    else
        title:SetText(opts.title or "")
        WM:ThemeText(title, "headerColor")
    end
    frame.titleText = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    local contentWidth
    if opts.scroll then
        local scroll = CreateFrame("ScrollFrame", opts.name .. "Scroll", frame, "UIPanelScrollFrameTemplate")
        contentWidth = width - SIDE_PAD - SCROLLBAR_PAD
        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(contentWidth)
        content:SetHeight(1)
        scroll:SetScrollChild(content)
        scroll.scrollBarHideable = true   -- FrameXML hides the bar when nothing to scroll
        frame.body = scroll
        frame.content = content
        frame.scrollBar = scroll.ScrollBar or _G[opts.name .. "ScrollScrollBar"]
    else
        contentWidth = width - 2 * SIDE_PAD
        local body = CreateFrame("Frame", nil, frame)
        frame.body = body
        frame.content = body
    end

    frame.layout = NewLayout(frame, frame.content, contentWidth)

    frame:SetScript("OnShow", function(self)
        self:Refresh()
        if opts.onShow then opts.onShow(self) end
    end)

    return frame
end
