-- Watching Machine: Ogri'la Helper
-- The Apexis Relic and Apexis Monument in Ogri'la show you a sequence of
-- coloured beams that you then have to touch in the same order. This
-- remembers the sequence for you: click the colours (or press G, Y, B, R)
-- as the relic shows them, then touch the beams. The next colour is
-- highlighted, each correct touch moves it on, and a wrong one (the
-- relic's Reprisal hitting you) puts the step back.
--
-- The window opens by itself when you start a relic or the monument, and
-- shows your Apexis Shards and Crystals and your longest sequence so far.
-- Game facts (object, debuff and spell IDs) compiled with the help of
-- Ogri'Lazy's research; the code is our own.

local AddonName, WM = ...
local OG = {}
WM:RegisterModule("Ogrila", OG)
WM.Ogrila = OG

OG.version = "3.44"

-- ============================================
-- GAME FACTS
-- ============================================

local RELICS = { [185890] = "Apexis Relic", [185944] = "Apexis Monument" }
-- The debuff you carry while playing; it's refreshed each time you touch
-- a beam
local INTROSPECTION = { [40055] = true, [40165] = true, [40166] = true, [40167] = true }
local REPRISAL = 40065          -- the relic hitting you for a wrong beam
local SHARD, CRYSTAL = 32569, 32572
OG.RELICS, OG.INTROSPECTION, OG.REPRISAL = RELICS, INTROSPECTION, REPRISAL

local COLORS = {
    { name = "Green", rgb = { 0.2, 0.9, 0.3 }, hex = "33E64D", key = "G" },
    { name = "Yellow", rgb = { 1, 0.85, 0.1 }, hex = "FFD91A", key = "Y" },
    { name = "Blue", rgb = { 0.25, 0.55, 1 }, hex = "408CFF", key = "B" },
    { name = "Red", rgb = { 1, 0.25, 0.2 }, hex = "FF4033", key = "R" },
}
OG.COLORS = COLORS

local MAX_SLOTS = 16

local DEFAULTS = {
    autoOpen = true,        -- open when you start a relic
    tooltips = true,        -- help on the buttons
    hotkeys = true,         -- G/Y/B/R while the window is up
    showKeys = true,        -- the key on each colour button
    unbindCombat = true,    -- give the keys back in combat
    scale = 1,
}

local function DB()
    OgrilaDB = OgrilaDB or {}
    local db = OgrilaDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.keys) ~= "table" then db.keys = {} end
    for i, c in ipairs(COLORS) do if db.keys[i] == nil then db.keys[i] = c.key end end
    if type(db.best) ~= "table" then db.best = {} end       -- [relic name] = longest sequence done
    if type(db.games) ~= "table" then db.games = {} end     -- [relic name] = times started
    return db
end
OG.DB = DB

-- ============================================
-- THE SEQUENCE
-- ============================================

-- seq: the colours recorded (1-4); pos: how many you've already touched
OG.seq, OG.pos = {}, 0
OG.relic = nil              -- which relic you're at, if known

function OG:Clear()
    wipe(self.seq)
    self.pos = 0
    self:RefreshHelper()
end

function OG:Done() return #self.seq > 0 and self.pos >= #self.seq end

-- The colour to touch next (nil: nothing left)
function OG:Next()
    if self.pos < #self.seq then return self.seq[self.pos + 1] end
end

-- Record a colour as the relic shows it. A finished sequence starts over:
-- the relic shows the whole of the next one again.
function OG:Add(color)
    if not COLORS[color] then return end
    if self:Done() then wipe(self.seq); self.pos = 0 end
    if #self.seq >= MAX_SLOTS then return end
    self.seq[#self.seq + 1] = color
    self:RefreshHelper()
end

-- Left click on a slot: drop that one. Right click: drop it and the rest.
function OG:Remove(i, andAfter)
    if not self.seq[i] then return end
    if andAfter then
        for j = #self.seq, i, -1 do self.seq[j] = nil end
    else
        table.remove(self.seq, i)
    end
    if self.pos > #self.seq then self.pos = #self.seq end
    if i <= self.pos then self.pos = math.max(0, i - 1) end
    self:RefreshHelper()
end

-- You touched a beam
function OG:Step()
    if self.pos >= #self.seq then return end
    self.pos = self.pos + 1
    if self:Done() then
        local db, name = DB(), self.relic or "Apexis Relic"
        if #self.seq > (db.best[name] or 0) then db.best[name] = #self.seq end
    end
    self:RefreshHelper()
end

-- The relic punished a wrong beam: that step didn't count
function OG:Undo()
    if self.pos > 0 then self.pos = self.pos - 1 end
    self:RefreshHelper()
end

-- ============================================
-- WATCHING THE GAME
-- ============================================

-- Expiry time of your Introspection debuff (nil: not playing)
function OG.IntrospectionExpiry()
    if not UnitDebuff then return nil end
    for i = 1, 40 do
        local name, _, _, _, _, expires, _, _, _, id = UnitDebuff("player", i)
        if not name then return nil end
        if INTROSPECTION[id] then return expires end
    end
end

-- Polled while the window is up: a new expiry means a beam was touched
local lastExpiry, nextPoll = nil, 0
function OG:Poll(now)
    now = now or GetTime()
    if now < nextPoll then return end
    nextPoll = now + 0.1
    local e = OG.IntrospectionExpiry()
    if e and e ~= lastExpiry then
        if lastExpiry then self:Step() end
        lastExpiry = e
    elseif not e then
        lastExpiry = nil
    end
end
function OG:ResetPoll() lastExpiry, nextPoll = OG.IntrospectionExpiry(), 0 end

function OG:OnCombatEvent(...)
    local _, sub, _, _, _, _, _, dstGUID, _, _, _, spellID = ...
    if sub == "SPELL_DAMAGE" and tonumber(spellID) == REPRISAL and dstGUID == UnitGUID("player") then
        self:Undo()
    end
end

-- Which relic an object GUID is (nil: not one)
function OG.RelicFor(guid)
    if type(guid) ~= "string" then return nil end
    local id = guid:match("^GameObject%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
    return id and RELICS[tonumber(id)]
end

-- A gossip option was picked: starting a relic?
function OG:OnGossipSelect()
    if not WM:IsModuleOn("Ogrila") or not DB().autoOpen then return end
    local relic = OG.RelicFor(UnitGUID("npc"))
    if not relic then return end
    local db = DB()
    db.games[relic] = (db.games[relic] or 0) + 1
    self.relic = relic
    wipe(self.seq)
    self.pos = 0
    self:ShowHelper()
end

-- ============================================
-- HOTKEYS
-- ============================================

local helper
OG.bound = false

local function KeyFor(i)
    local k = DB().keys[i]
    if type(k) == "string" and k ~= "" then return k:upper() end
end

-- Bind (or free) G/Y/B/R to the colour buttons. Bindings can't change in
-- combat: wait for it to end.
function OG:UpdateBindings()
    if not helper then return end
    local want = helper:IsShown() and DB().hotkeys and not (self.inCombat and DB().unbindCombat)
    if InCombatLockdown and InCombatLockdown() then
        if want ~= self.bound then
            self.pendingBind = true
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("Ogri'la Helper: hotkeys change when combat ends.", 1, 0.4, 0)
            end
        end
        return
    end
    self.pendingBind = nil
    if ClearOverrideBindings then ClearOverrideBindings(helper) end
    self.bound = false
    if want and SetOverrideBindingClick then
        for i = 1, #COLORS do
            local k = KeyFor(i)
            if k then SetOverrideBindingClick(helper, true, k, helper.colors[i]:GetName()) end
        end
        self.bound = true
    end
    self:RefreshHelper()
end

-- ============================================
-- THE HELPER WINDOW
-- ============================================

local function Color(i) return COLORS[i] and COLORS[i].rgb or { 0.5, 0.5, 0.5 } end

local function Tip(owner, title, text)
    if not DB().tooltips then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if text then GameTooltip:AddLine(text, 1, 0.82, 0, true) end
    GameTooltip:Show()
end
local function Untip() GameTooltip:Hide() end

local function Count(item)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and tonumber(f(item)) or 0
end

function OG:StatusText()
    local db = DB()
    local name = self.relic or "Apexis Relic"
    local nxt = self:Next()
    local line
    if #self.seq == 0 then
        line = "Click the colours as the relic shows them."
    elseif nxt then
        line = string.format("Next: |cFF%s%s|r  (%d of %d)", COLORS[nxt].hex, COLORS[nxt].name, self.pos + 1, #self.seq)
    else
        line = "|cFF33FF33Done!|r Record the next sequence."
    end
    local shards = string.format("|cFFAAAAAAShards|r %d  |cFFAAAAAACrystals|r %d", Count(SHARD), Count(CRYSTAL))
    if db.best[name] then shards = shards .. string.format("  |cFFAAAAAABest|r %d", db.best[name]) end
    return line, shards
end

function OG:CreateHelper()
    if helper then return helper end
    local db = DB()
    local f = CreateFrame("Frame", "WM_OgrilaHelper", UIParent, "BackdropTemplate")
    helper = f
    f:SetSize(246, 136)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        DB().point = { p, rp, x, y }
    end)
    local pt = db.point
    if type(pt) == "table" and pt[1] then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else f:SetPoint("CENTER", 0, 120) end
    local color = { 0.6, 0.9, 0.4 }
    if WM.SkinCard then WM:SkinCard(f, color); WM:RegisterSkinnedCard(f, color) end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeBtn = close
    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(48, 18)
    clear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() OG:Clear() end)
    clear:SetScript("OnEnter", function(b) Tip(b, "Clear", "Start the sequence again.") end)
    clear:SetScript("OnLeave", Untip)
    f.clearBtn = clear

    -- The recorded sequence: two rows of eight
    f.slots = {}
    for i = 1, MAX_SLOTS do
        local s = CreateFrame("Button", nil, f)
        s:SetSize(24, 24)
        local row, col = math.floor((i - 1) / 8), (i - 1) % 8
        s:SetPoint("TOPLEFT", 10 + col * 28, -30 - row * 28)
        s.ring = s:CreateTexture(nil, "BACKGROUND")
        s.ring:SetPoint("TOPLEFT", -3, 3)
        s.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        s.ring:SetColorTexture(1, 1, 1, 0.9)
        s.fill = s:CreateTexture(nil, "ARTWORK")
        s.fill:SetAllPoints()
        s.num = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.num:SetPoint("CENTER")
        if s.RegisterForClicks then s:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        s:SetScript("OnClick", function(_, button) OG:Remove(i, button == "RightButton") end)
        s:SetScript("OnEnter", function(b)
            local c = COLORS[OG.seq[i]]
            Tip(b, c and (i .. ". " .. c.name) or "", "Left click: remove this one.\nRight click: remove it and everything after.")
        end)
        s:SetScript("OnLeave", Untip)
        f.slots[i] = s
    end

    -- The four colours
    f.colors = {}
    for i, c in ipairs(COLORS) do
        local b = CreateFrame("Button", "WM_OgrilaColor" .. i, f)
        b:SetSize(48, 28)
        b:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 57, 26)
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetAllPoints()
        b.fill:SetColorTexture(c.rgb[1], c.rgb[2], c.rgb[3], 0.85)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        b.key = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.key:SetPoint("CENTER")
        b:SetScript("OnClick", function()
            OG:Add(i)
            if PlaySound then pcall(PlaySound, 1115) end
        end)
        b:SetScript("OnEnter", function(btn)
            local k = OG.bound and KeyFor(i)
            Tip(btn, "Add " .. c.name, "Click as the relic lights " .. c.name:lower() .. "." .. (k and (" Or press " .. k .. ".") or ""))
        end)
        b:SetScript("OnLeave", Untip)
        f.colors[i] = b
    end

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 10, 10)
    f.status:SetPoint("BOTTOMRIGHT", -10, 10)
    f.status:SetJustifyH("LEFT")
    f.line = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.line:SetPoint("BOTTOMLEFT", f.colors[1], "TOPLEFT", 0, 6)

    f:SetScript("OnShow", function(self)
        self:SetScale(math.max(0.8, math.min(2.5, tonumber(DB().scale) or 1)))
        OG:ResetPoll()
        OG:UpdateBindings()
    end)
    f:SetScript("OnHide", function() OG:UpdateBindings() end)
    f:SetScript("OnUpdate", function() OG:Poll() end)
    f:Hide()
    return f
end

function OG:RefreshHelper()
    local f = helper
    if not f then return end
    f.title:SetText("|cFF99E666" .. (self.relic or "Apexis Relic") .. "|r")
    local nxt = self.pos + 1
    for i, s in ipairs(f.slots) do
        local c = self.seq[i]
        if c then
            local rgb = Color(c)
            s.fill:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            s.num:SetText(i)
            s:SetAlpha(i <= self.pos and 0.3 or 1)
            if i == nxt then s.ring:Show() else s.ring:Hide() end
            s:Show()
        else
            s:Hide()
        end
    end
    local db = DB()
    for i, b in ipairs(f.colors) do
        local k = KeyFor(i)
        b.key:SetText((db.showKeys and self.bound and k) or "")
    end
    local line, status = self:StatusText()
    f.line:SetText(line)
    f.status:SetText(status)
end

function OG:ShowHelper()
    local f = self:CreateHelper()
    f:Show()
    self:RefreshHelper()
end

function OG:ToggleHelper()
    local f = self:CreateHelper()
    if f:IsShown() then f:Hide() else self:ShowHelper() end
end

-- ============================================
-- OPTIONS
-- ============================================

local panel

function OG:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({ name = "WM_OgrilaFrame", title = "Ogri'la Helper", titleColor = "99E666", width = 420 })
    local L = panel.layout
    L:Note("Remembers the Apexis Relic and Monument sequence for you. Click the colours (or press their keys) as the relic"
        .. " shows them, then touch the beams: the next one is highlighted and moves on by itself.")
    L:Buttons({ { text = "Show the helper", width = 130, onClick = function() OG:ShowHelper() end },
        { text = "Reset its position", width = 130, onClick = function()
            DB().point = nil
            if helper then helper:ClearAllPoints(); helper:SetPoint("CENTER", 0, 120) end
        end } })
    L:Checkbox({ label = "Open when you start a relic", get = function() return DB().autoOpen end, set = function(v) DB().autoOpen = v end })
    L:Checkbox({ label = "Help tooltips", get = function() return DB().tooltips end, set = function(v) DB().tooltips = v end })
    L:Checkbox({ label = "Hotkeys while the helper is up", get = function() return DB().hotkeys end,
        set = function(v) DB().hotkeys = v; OG:UpdateBindings() end,
        tooltip = { "Hotkeys", "The keys below add a colour while the helper is showing; they go back to normal when it closes." } })
    L:Checkbox({ label = "Show the keys on the buttons", get = function() return DB().showKeys end,
        set = function(v) DB().showKeys = v; OG:RefreshHelper() end })
    L:Checkbox({ label = "Free the keys in combat", get = function() return DB().unbindCombat end,
        set = function(v) DB().unbindCombat = v; OG:UpdateBindings() end })
    L:Slider({ label = "Helper size", min = 0.8, max = 2.5, step = 0.1, width = 200,
        format = function(v) return string.format("%.1f", v) end,
        get = function() return DB().scale end,
        set = function(v) DB().scale = v; if helper then helper:SetScale(v) end end })
    for i, c in ipairs(COLORS) do
        L:EditBox({ label = "|cFF" .. c.hex .. c.name .. "|r key:", width = 90, maxLetters = 24,
            get = function() return DB().keys[i] or "" end,
            set = function(v)
                DB().keys[i] = (v ~= "" and v:upper()) or c.key
                OG:UpdateBindings()
            end,
            tooltip = { c.name .. " key", "Any key, e.g. G, 1 or SHIFT-G. Empty puts back " .. c.key .. "." } })
    end
    L:Note(function()
        local db, parts = DB(), {}
        for _, name in ipairs({ "Apexis Relic", "Apexis Monument" }) do
            if db.games[name] or db.best[name] then
                parts[#parts + 1] = string.format("%s: played %d, longest %d", name, db.games[name] or 0, db.best[name] or 0)
            end
        end
        return #parts > 0 and table.concat(parts, "\n") or "|cFF888888No relics played yet.|r"
    end)
    panel:Finish()
    return panel
end

function OG:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
OG.ToggleUI = OG.Toggle

-- Turned off on this character: close everything and free the keys (the
-- gossip hook stays, but does nothing while the module is off)
function OG:OnModuleOff()
    if helper then helper:Hide() end
    if panel then panel:Hide() end
end

-- The module's page in the guided setup
function OG:SetupPage(L)
    L:Note("In Ogri'la (Blade's Edge Mountains) the Apexis Relics and the Apexis Monument play a memory game: they"
        .. " light a sequence of coloured beams and you touch the beams in the same order. Each round is longer.")
    L:Note("|cFFFFFFFFHow it works:|r when you start a relic the helper opens. As the relic lights each colour, click"
        .. " that colour in the helper (or press G, Y, B or R). Then touch the beams: the next one is ringed and moves"
        .. " on by itself each time you touch one, and steps back if the relic punishes a wrong one. It also shows"
        .. " your Apexis Shards and Crystals.")
    L:Checkbox({ label = "Open the helper when you start a relic", get = function() return DB().autoOpen end,
        set = function(v) DB().autoOpen = v end })
    L:Checkbox({ label = "Hotkeys (G, Y, B, R) while the helper is up", get = function() return DB().hotkeys end,
        set = function(v) DB().hotkeys = v end,
        tooltip = { "Hotkeys", "Only while the helper is showing; your keys go back to normal when it closes." } })
    L:Checkbox({ label = "Give the keys back in combat", get = function() return DB().unbindCombat end,
        set = function(v) DB().unbindCombat = v end })
    L:Checkbox({ label = "Help tooltips on the helper's buttons", get = function() return DB().tooltips end,
        set = function(v) DB().tooltips = v end })
    L:Note("Different keys and the helper's size are in its options: |cFFFFFF00/wmachine ogri options|r.")
end

function OG:GetQuickStatus()
    local db = DB()
    return string.format("%s, %d shards, best %d", db.autoOpen and "Opens at relics" or "Manual",
        Count(SHARD), math.max(db.best["Apexis Relic"] or 0, db.best["Apexis Monument"] or 0))
end

-- /wmachine ogri [options|clear]
function OG:Command(arg)
    arg = (arg or ""):lower()
    if arg == "options" or arg == "config" or arg == "opt" then
        self:Toggle()
    elseif arg == "clear" then
        self:Clear()
    else
        self:ToggleHelper()
    end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

local function Hook(tbl, name)
    if tbl and type(tbl[name]) == "function" and hooksecurefunc then
        hooksecurefunc(tbl, name, function() OG:OnGossipSelect() end)
    end
end

function OG:Initialize()
    DB()
    self:CreateHelper()
    Hook(C_GossipInfo, "SelectOption")
    Hook(C_GossipInfo, "SelectOptionByIndex")
    Hook(_G, "SelectGossipOption")
    WM:RegisterEvents(events, { "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE" })
end

events:SetScript("OnEvent", function(_, event)
    if not WM:IsModuleOn("Ogrila") then return end
    local ok, err = true
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not (helper and helper:IsShown() and CombatLogGetCurrentEventInfo) then return end
        ok, err = pcall(OG.OnCombatEvent, OG, CombatLogGetCurrentEventInfo())
    elseif event == "PLAYER_REGEN_DISABLED" then
        OG.inCombat = true
        -- Still allowed the instant combat starts
        if OG.bound and DB().unbindCombat and helper then
            if ClearOverrideBindings then ClearOverrideBindings(helper) end
            OG.bound = false
            OG:RefreshHelper()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        OG.inCombat = false
        if helper and (helper:IsShown() or OG.bound or OG.pendingBind) then ok, err = pcall(OG.UpdateBindings, OG) end
    elseif event == "BAG_UPDATE" then
        if helper and helper:IsShown() then OG:RefreshHelper() end
    end
    if not ok then geterrorhandler()(err) end
end)
