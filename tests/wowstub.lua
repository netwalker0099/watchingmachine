-- Minimal WoW client stand-in for the test harnesses.
--
--   local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
--   W.load("Core.lua"); W.load("UI.lua"); ...
--   W.env      the addon's global environment (SavedVariables live here)
--   W.WM       the addon table
--   W.Frame    fake frame methods, extendable per test
--   W.click(f) run a frame's OnClick the way a mouse click would
--
-- Frames record size, anchors, visibility, scripts, text and colours, and
-- answer any other method with a no-op (Get* -> 0, Is*/Has* -> false), so
-- addon UI code can be built and driven without a client.

return function(REPO)
    local W = {}

    local Frame = {}
    W.Frame = Frame
    local NewFrame
    local frameMT = {
        __call = function() return NewFrame() end,
        __index = function(t, k)
            if Frame[k] then return Frame[k] end
            if type(k) ~= "string" then return nil end
            if k:find("^_") or k:find("^[a-z]") then return nil end
            if k:find("^Get") then return function() return 0 end end
            if k:find("^Is") or k:find("^Has") then return function() return false end end
            return function(self) return self end
        end,
    }

    function NewFrame(name, parent, template)
        local f = setmetatable({
            _name = name, _parent = parent, _shown = true, _points = {},
            _scripts = {}, _hooks = {}, _w = 0, _h = 0, _alpha = 1,
            _enabled = true, _template = template,
        }, frameMT)
        if template and (template:find("CheckButton") or template:find("CheckButtonTemplate")) then
            f.Text = NewFrame(nil, f)
        end
        if template and template:find("OptionsSliderTemplate") then
            f.Low, f.High, f.Text = NewFrame(nil, f), NewFrame(nil, f), NewFrame(nil, f)
            f._min, f._max, f._value = 0, 1, 0
        end
        if template and template:find("UIPanelScrollFrameTemplate") then
            f.ScrollBar = NewFrame(nil, f)
            f._scroll = 0
        end
        return f
    end
    W.NewFrame = NewFrame

    function Frame:GetName() return self._name end
    function Frame:GetParent() return self._parent end
    function Frame:SetParent(p) self._parent = p end
    function Frame:Show()
        local was = self._shown
        self._shown = true
        if not was then self:_fire("OnShow") end
    end
    function Frame:Hide()
        local was = self._shown
        self._shown = false
        if was then self:_fire("OnHide") end
    end
    function Frame:IsShown() return self._shown end
    function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
    function Frame:IsVisible()
        local f = self
        while f do
            if not f._shown then return false end
            f = f._parent
        end
        return true
    end
    function Frame:SetSize(w, h) self._w, self._h = w, h end
    function Frame:SetWidth(w) self._w = w end
    function Frame:SetHeight(h) self._h = h end
    function Frame:GetWidth() return self._w end
    function Frame:GetHeight() return self._h end
    function Frame:SetPoint(...) self._points[#self._points + 1] = { ... } end
    function Frame:ClearAllPoints() self._points = {} end
    function Frame:GetPoint(i)
        local p = self._points[i or 1]
        if not p then return nil end
        -- SetPoint(point, rel, relPoint, x, y) or SetPoint(point, x, y)
        if type(p[2]) == "number" then return p[1], nil, p[1], p[2], p[3] end
        return p[1], p[2], p[3], p[4] or 0, p[5] or 0
    end
    function Frame:GetNumPoints() return #self._points end
    function Frame:SetScript(ev, fn) self._scripts[ev] = fn; self._hooks[ev] = nil end
    function Frame:GetScript(ev) return self._scripts[ev] end
    function Frame:HookScript(ev, fn)
        self._hooks[ev] = self._hooks[ev] or {}
        table.insert(self._hooks[ev], fn)
    end
    function Frame:_fire(ev, ...)
        if self._scripts[ev] then self._scripts[ev](self, ...) end
        for _, fn in ipairs(self._hooks[ev] or {}) do fn(self, ...) end
    end
    W.fire = function(f, ev, ...) f:_fire(ev, ...) end
    function Frame:SetText(t) self._text = t end
    function Frame:GetText() return self._text end
    function Frame:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
    function Frame:SetColorTexture(r, g, b, a) self._tex = { r, g, b, a } end
    function Frame:SetTexture(t) self._texture = t end
    function Frame:SetTexCoord(...) self._texCoord = { ... } end
    function Frame:SetDesaturated(v) self._desaturated = v and true or false end
    function Frame:GetStringHeight()
        local t = self._text or ""
        if t == "" then return 0 end
        local w = (self._w and self._w > 0) and self._w or 300
        return 12 * math.max(1, math.ceil(#t * 5 / w))
    end
    function Frame:SetChecked(v) self._checked = v and true or false end
    function Frame:GetChecked() return self._checked end
    function Frame:Enable() self._enabled = true end
    function Frame:Disable() self._enabled = false end
    function Frame:IsEnabled() return self._enabled end
    function Frame:SetAlpha(a) self._alpha = a end
    function Frame:GetAlpha() return self._alpha end
    function Frame:SetMinMaxValues(a, b) self._min, self._max = a, b end
    function Frame:GetMinMaxValues() return self._min, self._max end
    function Frame:SetValue(v)
        self._value = v
        self:_fire("OnValueChanged", v)
    end
    function Frame:GetValue() return self._value end
    function Frame:SetVerticalScroll(v) self._scroll = v end
    function Frame:GetVerticalScroll() return self._scroll or 0 end
    function Frame:SetScrollChild(c) self._child = c end
    function Frame:HasFocus() return self._focus or false end
    function Frame:SetFocus() self._focus = true end
    function Frame:ClearFocus()
        local was = self._focus
        self._focus = false
        if was then self:_fire("OnEditFocusLost") end
    end
    function Frame:CreateFontString(name) return NewFrame(name, self) end
    function Frame:CreateTexture(name) return NewFrame(name, self) end
    function Frame:GetFontString() return self._fs or NewFrame(nil, self) end
    function Frame:StopMovingOrSizing() end
    function Frame:StartMoving() end
    function Frame:StartSizing() end
    function Frame:SetNumeric(v) self._numeric = v end
    function Frame:SetResizeBounds(a, b, c, d) self._bounds = { a, b, c, d } end

    W.click = function(f, ...)
        if f._enabled == false then return end
        if f._template and f._template:find("Check") then f._checked = not f._checked end
        f:_fire("OnClick", ...)
    end

    local env = {}
    W.env = env
    local G = setmetatable(env, { __index = function(_, k)
        local v = _G[k]; if v ~= nil then return v end
        if type(k) == "string" and k:find("DB$") then return nil end
        return NewFrame()
    end })
    env._G = env
    W.printed = {}
    env.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
        W.printed[#W.printed + 1] = table.concat(t, " ")
    end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) W.printed[#W.printed + 1] = m end }
    env.UISpecialFrames = {}
    env.UIParent = NewFrame("UIParent")
    env.UIParent:SetSize(1024, 768)
    env.GameTooltip = NewFrame("GameTooltip")
    env.GameFontNormalSmall = NewFrame()
    -- Same layout as FrameXML's table: left, right, top, bottom per class
    env.CLASS_ICON_TCOORDS = {
        WARRIOR = { 0, 0.25, 0, 0.25 },   MAGE = { 0.25, 0.49609375, 0, 0.25 },
        ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
        HUNTER = { 0, 0.25, 0.25, 0.5 },  SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
        PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
        PALADIN = { 0, 0.25, 0.5, 0.75 },
    }
    env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    env.CreateFrame = function(_, name, parent, template)
        local f = NewFrame(name, parent, template)
        if name then env[name] = f end
        return f
    end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tinsert = table.insert
    env.tremove = table.remove
    env.date = os.date
    env.time = os.time
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strlower = string.lower
    env.strsplit = function(sep, s, n)
        local a, b = s:match("^(%S*)%s*(.*)$")
        return a, b
    end
    env.GetTime = function() return 0 end
    env.UnitName = function() return "Me" end
    env.GetRealmName = function() return "Testrealm" end
    env.UnitClass = function() return "Mage", "MAGE" end
    env.IsInRaid = function() return false end
    env.IsInGroup = function() return false end
    env.IsInInstance = function() return false, "none" end

    -- UIDropDownMenu: Initialize stores the init function; W.openMenu(dd)
    -- runs it and returns the items it added
    env.UIDropDownMenu_SetWidth = function(dd, w) dd._ddWidth = w end
    env.UIDropDownMenu_SetText = function(dd, t) dd._ddText = t end
    env.UIDropDownMenu_GetText = function(dd) return dd._ddText end
    env.UIDropDownMenu_Initialize = function(dd, fn) dd._ddInit = fn end
    env.UIDropDownMenu_CreateInfo = function() return {} end
    env.UIDropDownMenu_EnableDropDown = function(dd) dd._ddEnabled = true end
    env.UIDropDownMenu_DisableDropDown = function(dd) dd._ddEnabled = false end
    env.CloseDropDownMenus = function() end
    local menuItems
    env.UIDropDownMenu_AddButton = function(info) if menuItems then menuItems[#menuItems + 1] = info end end
    W.openMenu = function(dd)
        menuItems = {}
        if dd._ddInit then dd._ddInit(dd, 1) end
        local items = menuItems
        menuItems = nil
        return items
    end

    W.timers = {}
    local WM = {}
    W.WM = WM

    function W.load(rel)
        local f = assert(loadfile(REPO .. "/" .. rel))
        setfenv(f, G)
        f("WatchingMachine", WM)
        -- Timers: collect, run on demand with W.runTimers()
        if WM.RunAfter and not W._timersHooked then
            W._timersHooked = true
            WM.RunAfter = function(_, fn) table.insert(W.timers, fn) end
        end
    end

    function W.runTimers()
        local t = W.timers
        W.timers = {}
        for _, fn in ipairs(t) do fn() end
    end

    return W
end
