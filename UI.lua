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
--   name      optional global name (checkbox, slider, edit box, dropdown)
--   numeric   edit boxes only: digits only

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
    local cb = CreateFrame("CheckButton", spec.name, parent, "InterfaceOptionsCheckButtonTemplate")
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

    box.buttons = buttons   -- in option order, for badges and the like
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
    if spec.numeric then e:SetNumeric(true) end
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

-- A dropdown: a button showing the current choice; a click opens the
-- choices in Watching Machine's own menu, straight under it (never the
-- game's dropdown list, which opens elsewhere on a scaled UI: see
-- UI:ShowMenu). options = list of { value =, text = } or a function
-- returning one (re-read each time the menu opens, for lists that change).
function UI.Dropdown(parent, spec)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(1, 24)

    local label
    if spec.label then
        label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(spec.label)
    end

    local width = (spec.width or 120) + 24
    local dd = CreateFrame("Button", spec.name or UniqueName("WM_UIDropdown"), box, "BackdropTemplate")
    dd:SetSize(width, 20)
    if label then dd:SetPoint("LEFT", label, "RIGHT", 6, 0) else dd:SetPoint("LEFT", 0, 0) end
    dd.bg = dd:CreateTexture(nil, "BACKGROUND")
    dd.bg:SetAllPoints(dd)
    dd.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
    if dd.SetBackdrop then
        dd:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        dd:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
    local hl = dd:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(dd)
    hl:SetColorTexture(1, 1, 1, 0.08)
    dd.arrow = dd:CreateTexture(nil, "ARTWORK")
    dd.arrow:SetSize(14, 14)
    dd.arrow:SetPoint("RIGHT", -3, 0)
    dd.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    dd.arrow:SetTexCoord(0.2, 0.8, 0.25, 0.75)
    dd.label = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dd.label:SetPoint("LEFT", 6, 0)
    dd.label:SetPoint("RIGHT", dd.arrow, "LEFT", -2, 0)
    dd.label:SetJustifyH("LEFT")
    dd.label:SetWordWrap(false)

    local function Options() return Eval(spec.options) or {} end
    local function TextFor(v)
        for _, o in ipairs(Options()) do
            if o.value == v then return o.text end
        end
        return spec.placeholder or (v ~= nil and tostring(v)) or ""
    end
    local function Show(text)
        dd.shownText = text
        dd.label:SetText(text or "")
    end

    -- The choices, as menu items (the current one ticked)
    function dd:MenuItems()
        local cur = spec.get and spec.get()
        local items = {}
        for _, o in ipairs(Options()) do
            items[#items + 1] = { text = o.text, value = o.value, checked = (o.value == cur),
                func = function()
                    if spec.set then spec.set(o.value) end
                    Show(o.text)
                end }
        end
        return items
    end

    dd:SetScript("OnClick", function(self)
        if self.isDisabled then return end
        if UI:MenuOpenFor(self) then UI:HideMenu() return end
        UI:ShowMenu(self:MenuItems(), nil, nil, { anchor = self, minWidth = width })
    end)
    dd:SetScript("OnHide", function(self) if UI:MenuOpenFor(self) then UI:HideMenu() end end)
    UI.SetTooltip(dd, spec.tooltip)

    box.dropdown = dd
    function box:Refresh()
        Show(TextFor(spec.get and spec.get()))
        if spec.disabled then
            dd.isDisabled = spec.disabled() and true or false
            dd:SetAlpha(dd.isDisabled and 0.4 or 1)
        end
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
    fs.dynamic = type(spec.text) == "function"
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
function RowMethods:Dropdown(spec, x) return TrackOn(self, PlaceLeft(self, UI.Dropdown(self.frame, spec), x)) end
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

function Layout:Dropdown(spec)
    local row = self:Row(28)
    return row:Dropdown(spec, 12 + (spec.indent or 0)), row
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
    local state, opts = frame:GetState(), frame.opts
    -- A position saved by the window this panel replaced is adopted once
    if not state.pos and opts.legacyPosition and #opts.legacyPosition >= 4 then
        local p = opts.legacyPosition
        state.pos = { p[1], p[2], p[3], p[4] }
    end
    local pos = state.pos
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif opts.defaultPoint then
        local d = opts.defaultPoint
        frame:SetPoint(d[1] or "CENTER", UIParent, d[1] or "CENTER", d[2] or 0, d[3] or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- Size to content, capped at maxHeight and the screen
function Panel:Fit()
    local opts = self.opts
    local footer = (#self.footerButtons > 0 or self.hasFooter) and FOOTER_H or BOTTOM_PAD
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", SIDE_PAD, -TOP_PAD)
    self.body:SetPoint("BOTTOMRIGHT", -(opts.scroll and SCROLLBAR_PAD or SIDE_PAD), footer)

    local wanted
    local size = opts.resizable and self:GetState().size
    if size then
        wanted = size[2]
    elseif opts.height then
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
    for _, t in ipairs(self.footerTexts or {}) do
        if t.Refresh and t.dynamic then t:Refresh() end
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

-- Status text in the footer band (between any footer buttons). text may be
-- a function; it's re-read on Refresh, or set directly with :SetText.
function Panel:AddFooterText(spec, side)
    local fs = UI.Text(self, spec)
    if side == "RIGHT" then
        fs:SetPoint("BOTTOMRIGHT", -20, 20)
        fs:SetJustifyH("RIGHT")
    elseif side == "CENTER" then
        fs:SetPoint("BOTTOM", 0, 20)
    else
        fs:SetPoint("BOTTOMLEFT", 20, 20)
    end
    self.footerTexts = self.footerTexts or {}
    self.footerTexts[#self.footerTexts + 1] = fs
    self.hasFooter = true
    return fs
end

-- Pages: more than one set of content in one scrolling panel (a wizard).
-- Each page has its own layout; ShowPage swaps it in.
function Panel:NewPage()
    assert(self.opts.scroll, "pages need a scrolling panel")
    local content = CreateFrame("Frame", nil, self.body)
    content:SetWidth(self.layout.width)
    content:SetHeight(1)
    content:Hide()
    return { content = content, layout = NewLayout(self, content, self.layout.width) }
end

function Panel:ShowPage(page)
    if self.page and self.page ~= page then self.page.content:Hide() end
    if not self.firstPage then self.firstPage = { content = self.content, layout = self.layout } end
    if self.content ~= page.content then self.content:Hide() end
    self.page = page
    self.content, self.layout = page.content, page.layout
    self.body:SetScrollChild(page.content)
    page.content:Show()
    self.body:SetVerticalScroll(0)
    self:Refresh()
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
--   resizable  { minWidth, minHeight, maxWidth, maxHeight }: adds a size
--              grabber and remembers the size; for scroll = false panels,
--              whose rows stretch to the width (maxHeight is still capped
--              at the screen). onResize(panel) runs after a resize.
--   defaultPoint   { point, x, y } for the first open, before the player
--              has moved it (e.g. beside a related window)
--   legacyPosition { point, relPoint, x, y } saved by an older version of
--              the window; adopted once if the panel has no position yet
--              (the caller then clears its old key)
--   onShow     extra OnShow handler (after Refresh)
--   onHide     OnHide handler
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

    if opts.resizable then
        local r = opts.resizable
        local saved = frame:GetState().size
        if saved then frame:SetWidth(math.max(r[1], math.min(saved[1], r[3]))) end
        width = frame:GetWidth() > 0 and frame:GetWidth() or width
        frame:SetResizable(true)
        local function Bounds()
            local maxH = math.min(r[4], (UIParent:GetHeight() or r[4]) - SCREEN_MARGIN)
            if frame.SetResizeBounds then
                frame:SetResizeBounds(r[1], r[2], r[3], maxH)
            elseif frame.SetMinResize then
                frame:SetMinResize(r[1], r[2])
                frame:SetMaxResize(r[3], maxH)
            end
        end
        Bounds()
        local grip = CreateFrame("Button", nil, frame)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", -4, 4)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function() Bounds(); frame:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function()
            frame:StopMovingOrSizing()
            frame:GetState().size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
            SavePosition(frame)
            frame:Reflow()
            if opts.onResize then opts.onResize(frame) end
        end)
        frame.sizeGrip = grip
    end

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
    if opts.onHide then frame:SetScript("OnHide", opts.onHide) end

    return frame
end

-- ============================================
-- A WINDOW OF TEXT TO COPY (exports)
-- ============================================
-- UI:ShowCopyText(title, text, note): the text selected in a scrolling box,
-- ready for Ctrl+C. One window, reused.

local copyPanel

function UI:ShowCopyText(title, text, note)
    if not copyPanel then
        copyPanel = self:CreatePanel({ name = "WM_CopyTextFrame", title = "Copy", width = 620, height = 420,
            minHeight = 220, scroll = false, resizable = { 400, 220, 1400, 1200 } })
        local L = copyPanel.layout
        copyPanel.noteRow = L:Row(18)
        copyPanel.note = copyPanel.noteRow:Text({ text = function() return copyPanel.noteText or "" end }, 0)
        local fill = L:Fill(160)
        local sf = CreateFrame("ScrollFrame", "WM_CopyTextScroll", fill, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, 0)
        sf:SetPoint("BOTTOMRIGHT", -24, 0)
        local box = CreateFrame("EditBox", "WM_CopyTextBox", sf)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        box:SetWidth(560)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnTextChanged", function(self, user)
            -- Read-only: typing puts the text back
            if user and copyPanel.text then self:SetText(copyPanel.text); self:HighlightText() end
        end)
        sf:SetScrollChild(box)
        sf:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then box:SetWidth(w) end end)
        copyPanel.box = box
        copyPanel:AddFooterButton({ text = "Select all", width = 90, onClick = function()
            copyPanel.box:SetFocus(); copyPanel.box:HighlightText() end }, "RIGHT")
        copyPanel:Finish()
    end
    copyPanel.text = text or ""
    copyPanel.noteText = note or "Press Ctrl+C to copy, then paste it into a spreadsheet or text file."
    if copyPanel.titleText then copyPanel.titleText:SetText(title or "Copy") end
    copyPanel.note:SetText(copyPanel.noteText)
    copyPanel.box:SetText(copyPanel.text)
    if not copyPanel:IsShown() then copyPanel:Show() end
    copyPanel.box:SetFocus()
    copyPanel.box:HighlightText()
    return copyPanel
end

-- ============================================
-- WATCHING MACHINE'S OWN MENU
-- ============================================
-- Every menu and dropdown list in the addon is this one frame. The game's
-- own dropdown menus (UIDropDownMenuTemplate, ToggleDropDownMenu, EasyMenu)
-- are not used anywhere: they place their list from the cursor or the
-- anchor divided by a UI scale, so with ElvUI and other UI packs the list
-- opens on another part of the screen. tests/test_menus.lua fails if one
-- comes back.
--
-- UI:ShowMenu(items, rebuild, stay, opts)
--   items: { text, func, checked (true / false / nil for no tick), isTitle,
--            disabled, keepOpen, tooltip = { title, line, ... } }
--   rebuild: for keepOpen items, a function giving the items again (ticks
--            that change with each click); the menu is redrawn in place
--   opts.anchor: a frame to hang the menu under (a dropdown or a button);
--            without it the menu opens at the cursor
--   opts.minWidth: at least this wide (a dropdown's own width)
-- Closes on a choice, a click elsewhere, or Escape. Long lists scroll with
-- the mouse wheel.

local menu
local MENU_ROW, MENU_MAX = 16, 22

function UI:HideMenu() if menu then menu:Hide() end end

-- Is the menu open under this frame? (a dropdown's second click closes it)
function UI:MenuOpenFor(anchor)
    return menu ~= nil and menu:IsShown() and menu.anchor == anchor
end

local function DrawMenu()
    local items = menu.items
    local visible = math.min(#items, MENU_MAX)
    menu.offset = math.max(0, math.min(menu.offset or 0, #items - visible))
    local width = math.max(140, menu.minWidth or 0)
    for i = 1, visible do
        local it = items[i + menu.offset]
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(MENU_ROW)
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
            row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints(row)
            row.hl:SetColorTexture(1, 1, 1, 0.15)
            row.check = row:CreateTexture(nil, "ARTWORK")
            row.check:SetSize(12, 12)
            row.check:SetPoint("LEFT", 2, 0)
            row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 18, 0)
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(self)
                local fn = self.func
                if self.keepOpen and menu.rebuild then
                    if fn then fn() end
                    UI:ShowMenu(menu.rebuild(), menu.rebuild, true, menu.opts)
                    return
                end
                menu:Hide()
                if fn then fn() end
            end)
            row:SetScript("OnEnter", function(self) if self.tip then UI.ShowTooltip(self, self.tip) end end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            menu.rows[i] = row
        end
        row.func = (not it.isTitle and not it.disabled) and it.func or nil
        row.keepOpen = it.keepOpen
        row.tip = it.tooltip
        row.text:SetText(it.text or "")
        if it.isTitle then row.text:SetTextColor(1, 0.82, 0)
        elseif it.disabled then row.text:SetTextColor(0.5, 0.5, 0.5)
        else row.text:SetTextColor(1, 1, 1) end
        row.check:SetShown(it.checked == true)
        if it.isTitle or it.disabled then row:Disable(); row.hl:Hide() else row:Enable(); row.hl:Show() end
        row:Show()
        local w = (row.text.GetStringWidth and tonumber(row.text:GetStringWidth()) or 0) + 30
        if w > width then width = w end
    end
    for i = visible + 1, #menu.rows do menu.rows[i]:Hide() end
    -- More above or below: a small mark at the edge
    menu.more:SetShown(#items > visible)
    if #items > visible then
        menu.more:SetText((menu.offset > 0 and "^ " or "") .. (menu.offset + visible) .. " / " .. #items
            .. (menu.offset + visible < #items and " v" or ""))
    end
    -- Never narrower than it has been since it opened (it would jump about while scrolling)
    width = math.max(math.min(width, 360), menu.widest or 0)
    menu.widest = width
    menu:SetSize(width, 8 + visible * MENU_ROW + (#items > visible and 12 or 0))
end

function UI:ShowMenu(items, rebuild, stay, opts)
    opts = opts or {}
    if not menu then
        menu = CreateFrame("Frame", "WM_PopupMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        -- A solid dark background (always drawn, with or without backdrops)
        -- so the menu doesn't blend into what's behind it
        menu.bg = menu:CreateTexture(nil, "BACKGROUND")
        menu.bg:SetAllPoints(menu)
        menu.bg:SetColorTexture(0.02, 0.02, 0.03, 1)
        if menu.SetBackdrop then
            menu:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            menu:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
        end
        menu.more = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        menu.more:SetPoint("BOTTOMRIGHT", -6, 3)
        menu.rows = {}
        WM:RegisterEscClose(menu)
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(self, delta)
            self.offset = (self.offset or 0) - delta * 3
            DrawMenu()
        end)
        -- A click anywhere else closes it. (Not a click on the control it
        -- hangs under: that control's own click closes it, see MenuOpenFor.)
        menu:SetScript("OnEvent", function(self)
            if not self:IsShown() then return end
            if self.IsMouseOver and self:IsMouseOver() then return end
            local a = self.anchor
            if a and a.IsMouseOver and a:IsMouseOver() then return end
            self:Hide()
        end)
        menu:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
        menu:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    end
    local redraw = stay and menu:IsShown()
    menu.items, menu.rebuild, menu.opts = items, rebuild, opts
    menu.anchor, menu.minWidth = opts.anchor, opts.minWidth
    if not redraw then
        menu.offset, menu.widest = 0, nil
        -- Open with the ticked choice in view
        for i, it in ipairs(items) do
            if it.checked == true then menu.offset = math.max(0, i - math.floor(MENU_MAX / 2)) break end
        end
    end
    DrawMenu()
    if redraw then return menu end
    menu:ClearAllPoints()
    if opts.anchor then
        -- Straight under the control, whatever the UI scale
        menu:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, -2)
    else
        local x, y = 0, 0
        if GetCursorPosition then
            local cx, cy = GetCursorPosition()
            local scale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            x, y = (tonumber(cx) or 0) / scale, (tonumber(cy) or 0) / scale
        end
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
    menu:Show()
    return menu
end
