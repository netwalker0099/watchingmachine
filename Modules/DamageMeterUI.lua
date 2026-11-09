-- Watching Machine: Damage Meter windows
-- Bar windows in the style of the well-known damage meters: a title bar
-- (click it for the display, right-click for the fight), one class-coloured
-- bar per player sized against the top one, a tooltip with their spells,
-- and a click for the full breakdown. Any number of windows (up to
-- DM.MAX_WINDOWS), each with its own display and fight; their places,
-- sizes and choices are kept per character.

local AddonName, WM = ...
local DM = WM.DamageMeter
local DB = DM.DB
local Short, Commas, Clock = DM.Short, DM.Commas, DM.Clock

local TITLE_H = 18
local GAP = 1
local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local DEFAULT_W, DEFAULT_BARS = 230, 8

local frames = {}          -- [i] = window frame for DB().windows[i]
DM.frames = frames

local function ClassColor(class)
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    local c = type(class) == "string" and type(colors) == "table" and colors[class]
    if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    return 0.55, 0.55, 0.6
end
DM.ClassColor = ClassColor

local function SpellIcon(id)
    if not id then return nil end
    local f = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if type(f) ~= "function" then return nil end
    local ok, tex = pcall(f, id)
    if ok and (type(tex) == "string" or type(tex) == "number") then return tex end
end

local function Tip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 0.82, 0)
    for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
end

-- ============================================
-- ONE WINDOW
-- ============================================

local function Cfg(f) return DB().windows[f.index] end

local function SavePlace(f)
    local cfg = Cfg(f)
    if not cfg then return end
    local l, t = f:GetLeft(), f:GetTop()
    if type(l) == "number" and type(t) == "number" then cfg.x, cfg.y = l, t end
    local w, h = f:GetWidth(), f:GetHeight()
    if type(w) == "number" and w > 0 then cfg.w, cfg.h = w, h end
end

local function Place(f)
    local cfg = Cfg(f)
    local db = DB()
    f:ClearAllPoints()
    f:SetSize(cfg.w or DEFAULT_W, cfg.h or (TITLE_H + 4 + DEFAULT_BARS * (db.barHeight + GAP)))
    if cfg.x and cfg.y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg.x, cfg.y)
    else
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40 - (f.index - 1) * (DEFAULT_W + 10), 200)
    end
end

local function SmallButton(f, tex, tip, onClick)
    local b = CreateFrame("Button", nil, f.title)
    b:SetSize(14, 14)
    b:SetNormalTexture(tex)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) Tip(self, tip[1], { tip[2] }) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Bar(f, i)
    local bar = f.bars[i]
    if bar then return bar end
    bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetMinMaxValues(0, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
    bar.icon = bar:CreateTexture(nil, "OVERLAY")
    bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.left:SetJustifyH("LEFT")
    bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.right:SetJustifyH("RIGHT")
    bar.right:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self) DM:BarTooltip(self) end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            DM:OpenMenu("display", f.index)
        elseif self.row then
            local cfg = Cfg(f)
            if IsShiftKeyDown and IsShiftKeyDown() == true then
                DM:Report(cfg.display, cfg.segment)
            else
                DM:OpenBreakdown(cfg.display, cfg.segment, self.row)
            end
        end
    end)
    f.bars[i] = bar
    return bar
end

function DM:CreateWindowFrame(i)
    local f = frames[i]
    if f then return f end
    f = CreateFrame("Frame", "WM_DamageMeterWindow" .. i, UIParent, "BackdropTemplate")
    f.index = i
    f.bars = {}
    f.offset = 0
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(120, TITLE_H + 24, 900, 900) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
        f:SetBackdropBorderColor(0, 0, 0, 0.8)
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, (self.offset or 0) - (delta or 0))
        DM:RefreshWindow(self.index)
    end)
    f:SetScript("OnSizeChanged", function(self) if self:IsShown() then DM:RefreshWindow(self.index) end end)

    -- Title bar: drag to move, click for the display, right-click for the fight
    local title = CreateFrame("Button", "WM_DamageMeterTitle" .. i, f)
    f.title = title
    title:SetHeight(TITLE_H)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    title.bg = title:CreateTexture(nil, "BACKGROUND")
    title.bg:SetAllPoints()
    title.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title.text:SetPoint("LEFT", title, "LEFT", 4, 0)
    title.text:SetJustifyH("LEFT")
    title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() if not DB().locked then f:StartMoving() end end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePlace(f) end)
    title:SetScript("OnClick", function(_, button)
        DM:OpenMenu(button == "RightButton" and "segment" or "display", f.index)
    end)
    title:SetScript("OnEnter", function(self)
        Tip(self, "Damage Meter", { "Click: choose what this window shows.", "Right-click: choose the fight.",
            DB().locked and "Windows are locked (/wmachine meter unlock)." or "Drag to move; the corner resizes." })
    end)
    title:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Buttons, right to left
    local btns = {}
    btns[1] = SmallButton(f, "Interface\\Buttons\\UI-StopButton", { "Close", "Hide this window (/wmachine meter brings it back)." },
        function() DM:CloseWindow(f.index) end)
    btns[2] = SmallButton(f, "Interface\\Buttons\\UI-PlusButton-Up", { "New window", "Open another window with its own display." },
        function() DM:NewWindow() end)
    btns[3] = SmallButton(f, "Interface\\Buttons\\UI-GuildButton-MOTD-Up", { "Report", "Send this window's top lines to chat." },
        function() DM:OpenMenu("report", f.index) end)
    btns[4] = SmallButton(f, "Interface\\Buttons\\UI-RotationLeft-Button-Up", { "Reset", "Clear every fight (asks first)." },
        function() WM:Confirm("Clear every fight in the damage meter?", function() DM:Reset() end) end)
    btns[5] = SmallButton(f, "Interface\\Icons\\INV_Misc_PocketWatch_01", { "Fight", "Current fight, overall, or an earlier fight." },
        function() DM:OpenMenu("segment", f.index) end)
    for k, b in ipairs(btns) do
        b:SetPoint("RIGHT", title, "RIGHT", -2 - (k - 1) * 15, 0)
    end
    f.buttons = btns
    title.text:SetPoint("RIGHT", title, "RIGHT", -2 - #btns * 15, 0)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOP", f, "TOP", 0, -TITLE_H - 8)

    -- Resize grip
    local grip = CreateFrame("Button", nil, f)
    f.grip = grip
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel((tonumber(f:GetFrameLevel()) or 1) + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() if not DB().locked then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); SavePlace(f); DM:RefreshWindow(f.index) end)

    frames[i] = f
    return f
end

function DM:ApplyLock()
    local locked = DB().locked
    for _, f in pairs(frames) do
        f.grip:SetShown(not locked)
    end
end

-- Should window i be on screen now?
function DM:WindowWanted(i)
    local db = DB()
    local cfg = db.windows[i]
    if not cfg or cfg.hidden then return false end
    if not WM:IsModuleOn("DamageMeter") then return false end
    if db.hideOutOfCombat and not self:InFight() then return false end
    return true
end

function DM:CreateWindows()
    local db = DB()
    for i = 1, #db.windows do
        local f = self:CreateWindowFrame(i)
        f.index = i
        Place(f)
    end
    self:ApplyLock()
    self:ShowWindows()
end

function DM:ShowWindows()
    local db = DB()
    for i = 1, #db.windows do
        local f = self:CreateWindowFrame(i)
        if self:WindowWanted(i) then
            if not f:IsShown() then Place(f) end
            f:Show()
            self:RefreshWindow(i)
        else
            f:Hide()
        end
    end
    for i = #db.windows + 1, #frames do frames[i]:Hide() end
end

function DM:AnyWindowShown()
    for _, f in pairs(frames) do if f:IsShown() then return true end end
    return false
end

-- /wmachine meter: hide every window, or bring them all back
function DM:ToggleUI()
    if not WM:IsModuleOn("DamageMeter") then return end
    local db = DB()
    if #db.windows == 0 then return self:NewWindow() end
    local anyOpen = false
    for _, w in ipairs(db.windows) do if not w.hidden then anyOpen = true end end
    if anyOpen and self:AnyWindowShown() then
        for _, w in ipairs(db.windows) do w.hidden = true end
    else
        for _, w in ipairs(db.windows) do w.hidden = nil end
        if db.hideOutOfCombat and not self:InFight() then
            WM:ModulePrint("DamageMeter", "The windows show during fights (\"Show only in combat\" is on).")
        end
    end
    self:ShowWindows()
end
DM.Toggle = DM.ToggleUI

-- A display no other window is showing yet
local function NextDisplay()
    local used = {}
    for _, w in ipairs(DB().windows) do used[w.display] = true end
    for _, k in ipairs({ "damage", "heal", "taken", "threat", "dps", "interrupts", "dispels", "deaths" }) do
        if not used[k] then return k end
    end
    return "damage"
end

function DM:NewWindow(display)
    if not WM:IsModuleOn("DamageMeter") then return end
    local db = DB()
    if #db.windows >= DM.MAX_WINDOWS then
        WM:ModulePrint("DamageMeter", "That's " .. DM.MAX_WINDOWS .. " windows already; close one or change what it shows.")
        return nil
    end
    db.windows[#db.windows + 1] = { display = display or NextDisplay(), segment = "current" }
    local i = #db.windows
    local f = self:CreateWindowFrame(i)
    f.index = i
    Place(f)
    self:ApplyLock()
    self:ShowWindows()
    return i
end

-- Hide window i (it comes back with /wmachine meter)
function DM:CloseWindow(i)
    local cfg = DB().windows[i]
    if not cfg then return end
    cfg.hidden = true
    if frames[i] then frames[i]:Hide() end
end

-- Remove window i for good
function DM:DeleteWindow(i)
    local db = DB()
    if not db.windows[i] then return end
    table.remove(db.windows, i)
    for _, f in pairs(frames) do f:Hide() end
    for k = 1, #db.windows do
        local f = self:CreateWindowFrame(k)
        f.index = k
        f.offset = 0
        Place(f)
    end
    self:ShowWindows()
end

function DM:SetWindowDisplay(i, key)
    local cfg = DB().windows[i]
    if not cfg or not DM.BY_KEY[key] then return end
    cfg.display = key
    if frames[i] then frames[i].offset = 0 end
    self:RefreshWindow(i)
end

function DM:SetWindowSegment(i, which)
    local cfg = DB().windows[i]
    if not cfg then return end
    cfg.segment = which
    if frames[i] then frames[i].offset = 0 end
    self:RefreshWindow(i)
end

-- The title: "Damage - Gruul the Dragonkiller [2:41]"
function DM:WindowTitle(i)
    local cfg = DB().windows[i]
    if not cfg then return "" end
    local d = self:Display(cfg.display)
    if d.live then
        local mob = self:ThreatUnit()
        local name = mob and UnitName and UnitName(mob)
        return d.short .. (type(name) == "string" and (" - " .. name) or "")
    end
    local seg = self:Segment(cfg.segment)
    local t = seg and (" [" .. Clock(self:Duration(seg)) .. "]") or ""
    return d.short .. " - " .. self:SegmentName(cfg.segment) .. t
end

function DM:RefreshWindow(i)
    local f = frames[i]
    local cfg = DB().windows[i]
    if not f or not cfg or not f:IsShown() then return end
    local db = DB()
    local d = self:Display(cfg.display)
    f.title.text:SetText(self:WindowTitle(i))
    local rows = self:Rows(cfg.display, cfg.segment)
    local barH = math.max(10, tonumber(db.barHeight) or 16)
    local h = tonumber(f:GetHeight()) or 0
    local w = tonumber(f:GetWidth()) or DEFAULT_W
    local count = math.max(1, math.floor((h - TITLE_H - 2 + GAP) / (barH + GAP)))
    f.offset = math.max(0, math.min(f.offset or 0, #rows - count))
    local top = rows[1] and rows[1].value or 0
    for k = 1, math.max(count, #f.bars) do
        local r = k <= count and rows[k + f.offset]
        if r then
            local bar = Bar(f, k)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -TITLE_H - 1 - (k - 1) * (barH + GAP))
            bar:SetSize(math.max(20, w - 2), barH)
            bar:SetValue(top > 0 and (r.value / top) or 0)
            local cr, cg, cb = ClassColor(r.class)
            if d.key == "enemies" then cr, cg, cb = 0.75, 0.25, 0.25 end
            if d.key == "threat" then cr, cg, cb = DM.ThreatColor(r.pct) end
            bar:SetStatusBarColor(cr, cg, cb, 0.85)
            local x = 3
            local tc = r.class and rawget(_G, "CLASS_ICON_TCOORDS") and CLASS_ICON_TCOORDS[r.class]
            if db.classIcons and type(tc) == "table" then
                bar.icon:SetTexture(CLASS_TEX)
                bar.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                bar.icon:SetSize(barH, barH)
                bar.icon:ClearAllPoints()
                bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
                bar.icon:Show()
                x = barH + 2
            else
                bar.icon:Hide()
            end
            bar.left:ClearAllPoints()
            bar.left:SetPoint("LEFT", bar, "LEFT", x, 0)
            bar.left:SetPoint("RIGHT", bar.right, "LEFT", -4, 0)
            local name = r.name
            if r.tanking then name = name .. " |cFFFF5555(tank)|r" end
            bar.left:SetText((db.showRank and ((k + f.offset) .. ". ") or "") .. name)
            bar.right:SetText(d.text(r))
            bar.row = r
            bar:Show()
        elseif f.bars[k] then
            f.bars[k].row = nil
            f.bars[k]:Hide()
        end
    end
    if #rows == 0 then
        local msg = d.live and "Target an enemy to see threat"
            or (self:Segment(cfg.segment) and "Nothing here yet" or "No fights yet")
        f.empty:SetText(msg)
        f.empty:Show()
    else
        f.empty:Hide()
    end
end

function DM:RefreshWindows()
    for i in ipairs(DB().windows) do self:RefreshWindow(i) end
end

-- A few times a second (from the driver): redraw what changed. Threat
-- windows always redraw, since threat isn't in the combat log.
function DM:Tick()
    local changed = self:TakeChanged()
    for i, cfg in ipairs(DB().windows) do
        local f = frames[i]
        if f and f:IsShown() and (changed or self:Display(cfg.display).live or self:InFight()) then
            self:RefreshWindow(i)
        end
    end
    if changed and self.breakdown and self.breakdown:IsShown() then self:RefreshBreakdown() end
end

function DM:OnFightStart() self:ShowWindows() end
function DM:OnFightEnd() self:ShowWindows() end
function DM:OnStateEvent(event)
    if event == "PLAYER_TARGET_CHANGED" then self:RefreshWindows() end
end

-- ============================================
-- TOOLTIPS
-- ============================================

function DM:TooltipLines(key, which, row)
    local d = self:Display(key)
    local lines = {}
    if not row then return lines end
    if d.key == "deaths" and row.death then
        local e = row.death
        lines[#lines + 1] = "Died at " .. Clock(e.at) .. (e.killer and (", killed by " .. e.killer) or "")
        for k = #e.log, math.max(1, #e.log - 11), -1 do
            lines[#lines + 1] = self:DeathLine(e.log[k])
        end
        return lines
    end
    if d.key == "threat" then
        lines[#lines + 1] = string.format("Threat %s, %.1f%% of what pulls aggro", Commas(row.amount), row.pct)
        if row.tanking then
            lines[#lines + 1] = "Has aggro. Others pull it at 110% of this in melee range, 130% at range."
        end
        return lines
    end
    if row.actor and (d.key == "damage" or d.key == "dps" or d.key == "heal" or d.key == "hps") then
        local seg = self:Segment(which)
        lines[#lines + 1] = string.format("%s in %s active (fight %s)", Commas(row.amount), Clock(row.actor.at),
            Clock(self:Duration(seg)))
    end
    local spells = self:Breakdown(key, row)
    local shown = (IsShiftKeyDown and IsShiftKeyDown() == true) and #spells or 6
    for k = 1, math.min(shown, #spells) do
        local s = spells[k]
        lines[#lines + 1] = string.format("%s  |cFFFFFFFF%s|r |cFFAAAAAA(%.1f%%)|r", s.name,
            (d.counts and tostring(s.amount)) or Short(s.amount), s.pct)
    end
    if #spells > shown then lines[#lines + 1] = "|cFF888888... and " .. (#spells - shown) .. " more (hold Shift)|r" end
    return lines
end

function DM:DeathLine(e)
    if not e then return "" end
    local amt = e.heal and ("|cFF33FF33+" .. Commas(e.amount) .. "|r") or ("|cFFFF4444-" .. Commas(e.amount) .. "|r")
    return string.format("-%.1fs  %s%s  %s%s%s", e.ago or 0, e.spell or "?", e.src and (" (" .. e.src .. ")") or "",
        amt, e.crit and " (crit)" or "", e.hp and ("  |cFFAAAAAA" .. e.hp .. "%|r") or "")
end

function DM:BarTooltip(bar)
    local f = bar:GetParent()
    local cfg = f and f.index and DB().windows[f.index]
    if not cfg or not bar.row then return end
    local d = self:Display(cfg.display)
    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    local r, g, b = ClassColor(bar.row.class)
    GameTooltip:SetText(bar.row.name .. "  |cFFAAAAAA" .. d.name .. "|r", r, g, b)
    for _, l in ipairs(self:TooltipLines(cfg.display, cfg.segment, bar.row)) do GameTooltip:AddLine(l, 1, 1, 1) end
    if not d.live and d.key ~= "enemies" then
        GameTooltip:AddLine("Click: full breakdown. Shift-click: report. Right-click: display.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- ============================================
-- MENUS
-- ============================================

local function Item(text, func, checked, opts)
    local info = { text = text, func = func, checked = checked }
    if opts then for k, v in pairs(opts) do info[k] = v end end
    return info
end

-- kind: "display", "segment" or "report", for window i. Opens Watching
-- Machine's own menu at the cursor (the game's dropdown menu didn't open
-- for some players) and returns its items.
function DM:OpenMenu(kind, i)
    local cfg = DB().windows[i]
    if not cfg then return {} end
    local items = {}
    do
        local add = function(info) items[#items + 1] = info end
        if kind == "display" then
            add(Item("What this window shows", nil, nil, { isTitle = true }))
            for _, d in ipairs(DM.DISPLAYS) do
                add(Item(d.name, function() DM:SetWindowDisplay(i, d.key) end, cfg.display == d.key))
            end
            add(Item("Window", nil, nil, { isTitle = true }))
            add(Item("New window", function() DM:NewWindow() end))
            add(Item("Delete this window", function() DM:DeleteWindow(i) end))
            add(Item(DB().locked and "Unlock windows" or "Lock windows", function()
                DB().locked = not DB().locked; DM:ApplyLock() end))
            add(Item("Options", function() DM:ToggleOptions() end))
        elseif kind == "segment" then
            add(Item("Which fight", nil, nil, { isTitle = true }))
            local h = DM:History()
            add(Item("Current fight" .. (h[1] and (": " .. DM:FightName(h[1])) or ""),
                function() DM:SetWindowSegment(i, "current") end, cfg.segment == "current"))
            add(Item("Overall", function() DM:SetWindowSegment(i, "overall") end, cfg.segment == "overall"))
            for n = 2, #h do
                local s = h[n]
                add(Item(string.format("#%d %s [%s]%s", n, s.name or "Fight", Clock(DM:Duration(s)), s.boss and " (boss)" or ""),
                    function() DM:SetWindowSegment(i, n) end, cfg.segment == n))
            end
        elseif kind == "report" then
            add(Item("Report " .. DB().reportLines .. " lines to", nil, nil, { isTitle = true }))
            for _, ch in ipairs({ { "SAY", "Say" }, { "PARTY", "Party" }, { "RAID", "Raid" }, { "GUILD", "Guild" },
                { "OFFICER", "Officer" }, { "SELF", "Just me (chat frame)" } }) do
                add(Item(ch[2], function() DM:Report(cfg.display, cfg.segment, ch[1]) end))
            end
            add(Item("Whisper your target", function()
                local name = UnitName and UnitName("target")
                if type(name) == "string" and UnitIsPlayer and UnitIsPlayer("target") == true then
                    DM:Report(cfg.display, cfg.segment, "WHISPER", name)
                else
                    WM:ModulePrint("DamageMeter", "Target a player to whisper the report to.")
                end
            end))
        end
    end
    if WM.UI and WM.UI.ShowMenu then WM.UI:ShowMenu(items) end
    return items
end

-- ============================================
-- BREAKDOWN WINDOW
-- ============================================

local B_ROW = 16
local bstate = {}
DM.bstate = bstate

function DM:CreateBreakdown()
    if self.breakdown then return self.breakdown end
    local p = WM.UI:CreatePanel({
        name = "WM_DamageMeterBreakdown", title = "Damage Meter: breakdown", titleColor = "FF5533",
        width = 560, height = 400, scroll = false,
        resizable = { 440, 240, 1100, 1200 },
        onResize = function() DM:RefreshBreakdown() end,
        onRefresh = function() DM:RefreshBreakdown() end,
    })
    local L = p.layout
    local top = L:Row(20)
    p.heading = top:Text({ text = function() return bstate.heading or "" end }, 4)
    local head = L:Row(16)
    p.cols = {}
    for _, h in ipairs({ { "Spell", 22 }, { "Amount", 230 }, { "%", 300 }, { "Hits", 350 }, { "Crit", 400 }, { "Average", 440 }, { "Biggest", 500 } }) do
        local k = #p.cols + 1
        p.cols[k] = head:Text({ text = function() return "|cFFFFD100" .. ((bstate.cols or {})[k] or h[1]) .. "|r" end }, h[2])
    end
    local fill = L:Fill(120)
    local scroll = CreateFrame("ScrollFrame", "WM_DamageMeterBreakdownScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    scroll:SetScrollChild(child)
    p.listChild, p.rows = child, {}
    p:Finish()
    self.breakdown = p
    return p
end

local function BRow(p, i)
    local r = p.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, p.listChild)
    r:SetHeight(B_ROW)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(B_ROW - 2, B_ROW - 2)
    r.icon:SetPoint("LEFT", 2, 0)
    r.cols = {}
    for k, c in ipairs({ { 22, 200, "LEFT" }, { 210, 70, "RIGHT" }, { 284, 46, "RIGHT" }, { 334, 46, "RIGHT" },
        { 384, 46, "RIGHT" }, { 434, 56, "RIGHT" }, { 494, 60, "RIGHT" } }) do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", c[1], 0)
        fs:SetWidth(c[2])
        fs:SetJustifyH(c[3])
        r.cols[k] = fs
    end
    p.rows[i] = r
    return r
end

-- Open the breakdown for one bar's row
function DM:OpenBreakdown(key, which, row)
    if not WM:IsModuleOn("DamageMeter") or not row then return end
    local d = self:Display(key)
    if d.live or d.key == "enemies" then return end
    bstate.key, bstate.which, bstate.guid, bstate.death, bstate.name = key, which, row.guid, row.death, row.name
    local p = self:CreateBreakdown()
    p:Show()
    self:RefreshBreakdown()
    return p
end

function DM:RefreshBreakdown()
    local p = self.breakdown
    if not p or not p:IsShown() or not bstate.key then return end
    local d = self:Display(bstate.key)
    local seg = self:Segment(bstate.which)
    local lines = {}       -- { icon, cols... }
    local headCols
    if bstate.death then
        local e = bstate.death
        bstate.heading = string.format("|cFFFFFFFF%s|r died at %s%s", e.n, Clock(e.at), e.killer and (", killed by " .. e.killer) or "")
        headCols = { "Event", "Amount", "Health", "", "", "", "" }
        for k = #e.log, 1, -1 do
            local ev = e.log[k]
            lines[#lines + 1] = { nil, string.format("-%.1fs %s%s", ev.ago or 0, ev.spell or "?", ev.src and (" (" .. ev.src .. ")") or ""),
                (ev.heal and "|cFF33FF33+" or "|cFFFF4444-") .. Commas(ev.amount) .. "|r" .. (ev.crit and "*" or ""),
                ev.hp and (ev.hp .. "%") or "", "", "", "", "" }
        end
    else
        local actor = seg and bstate.guid and seg.actors[bstate.guid]
        local row = actor and { actor = actor, guid = bstate.guid, name = actor.n }
        local spells = self:Breakdown(bstate.key, row)
        bstate.heading = string.format("|cFFFFFFFF%s|r  %s  |cFFAAAAAA%s|r", bstate.name or "?", d.name, self:SegmentName(bstate.which))
        local healing = d.spells == "hp"
        headCols = { d.spells == "tf" and "From" or (d.counts and "Spell" or "Spell"), "Amount", "%",
            d.counts and "" or "Hits", d.counts and "" or "Crit", d.counts and "" or "Average",
            d.counts and "" or (healing and (d.key == "overheal" and "Healed" or "Overheal") or "Biggest") }
        for _, s in ipairs(spells) do
            if d.counts then
                lines[#lines + 1] = { nil, s.name, tostring(s.amount), string.format("%.1f%%", s.pct), "", "", "", "" }
            else
                local hits = s.hits or 0
                local last = healing and (d.key == "overheal" and Short(s.effective or 0) or Short(s.over or 0)) or Short(s.max or 0)
                lines[#lines + 1] = { SpellIcon(s.id), s.name, Short(s.amount), string.format("%.1f%%", s.pct), tostring(hits),
                    hits > 0 and string.format("%.0f%%", (s.crits or 0) / hits * 100) or "",
                    hits > 0 and Short(s.amount / hits) or "", last }
            end
        end
    end
    bstate.cols = headCols
    p.heading:SetText(bstate.heading)
    for k, c in ipairs(p.cols) do c:SetText("|cFFFFD100" .. (headCols[k] or "") .. "|r") end
    for i, l in ipairs(lines) do
        local r = BRow(p, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * B_ROW)
        r:SetPoint("RIGHT", p.listChild, "RIGHT", 0, 0)
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.05 or 0.02)
        if l[1] then r.icon:SetTexture(l[1]); r.icon:Show() else r.icon:Hide() end
        for k = 1, 7 do r.cols[k]:SetText(l[k + 1] or "") end
        r:Show()
    end
    for i = #lines + 1, #p.rows do p.rows[i]:Hide() end
    p.listChild:SetHeight(math.max(1, #lines * B_ROW))
    p.lines = lines
end

-- ============================================
-- OPTIONS WINDOW
-- ============================================

function DM:CreateOptions()
    if self.options then return self.options end
    local p = WM.UI:CreatePanel({ name = "WM_DamageMeterOptions", title = "Damage Meter options", titleColor = "FF5533", width = 380 })
    self:SettingsControls(p.layout)
    p:AddFooterButton({ text = "New window", width = 100, onClick = function() DM:NewWindow() end }, "LEFT")
    p:AddFooterButton({ text = "Reset fights", width = 100, confirm = true, onClick = function() DM:Reset() end }, "RIGHT")
    p:Finish()
    self.options = p
    return p
end

function DM:ToggleOptions()
    if not WM:IsModuleOn("DamageMeter") then return end
    local p = self:CreateOptions()
    if p:IsShown() then p:Hide() else p:Show(); p:Refresh() end
end

function DM:HideAllFrames()
    for _, f in pairs(frames) do f:Hide() end
    if self.breakdown then self.breakdown:Hide() end
    if self.options then self.options:Hide() end
    if WM.UI and WM.UI.HideMenu then WM.UI:HideMenu() end
end
