-- Watching Machine
-- Comprehensive monitoring suite for WoW Classic TBC Anniversary
-- Author: Robert

local AddonName, WM = ...
_G.WatchingMachine = WM

WM.version = "3.49"
WM.modules = {}

-- The heading for our keys in the game's Key Bindings (Bindings.xml)
BINDING_HEADER_WATCHINGMACHINE = "Watching Machine"

-- ============================================
-- ERROR LOGGING (loads before everything else)
-- ============================================

WM._errorLog = {}
local MAX_ERRORS = 200
local WM_ERROR_PATTERNS = {
    "WatchingMachine", "watchingmachine", "WM_",
    "PvPTracker", "DebuffTracker", "AutoLogger",
    "KeywordMonitor", "ChatFilter", "MailLogger", "ServicesParser",
    "Recruiter", "WhisperLogs", "GuildInvite", "BuffCheck", "ArmorySnap", "AuraRange",
    "ClassTools", "ClassGeneral", "ClassWarlock", "ClassMage", "ClassShaman", "SwingTimer", "ClassPaladin", "InstanceTracker", "AltTracker", "PvPLog", "WorldTimers", "LootBrowser", "GearScore", "Attunements", "Hazards", "Crits", "Ogrila", "GearSets", "FrameMover",
}

local origErrorHandler = geterrorhandler()
seterrorhandler(function(msg)
    local msgStr = tostring(msg or "unknown")
    
    -- Only capture WatchingMachine-related errors
    local isWM = false
    for _, pattern in ipairs(WM_ERROR_PATTERNS) do
        if msgStr:find(pattern, 1, true) then
            isWM = true
            break
        end
    end
    
    -- If not found in message, check stack trace
    if not isWM then
        local stack = debugstack(2, 6, 0) or ""
        for _, pattern in ipairs(WM_ERROR_PATTERNS) do
            if stack:find(pattern, 1, true) then
                isWM = true
                break
            end
        end
    end
    
    if isWM then
        local stack = debugstack(2, 8, 0) or ""
        local entry = date("%H:%M:%S") .. " | " .. msgStr
        if stack ~= "" then
            entry = entry .. " || STACK: " .. stack:gsub("\n", " >> ")
        end
        table.insert(WM._errorLog, entry)
        while #WM._errorLog > MAX_ERRORS do
            table.remove(WM._errorLog, 1)
        end
        if WatchingMachineDB then
            WatchingMachineDB.errorLog = WM._errorLog
        end
    end
    
    -- Always pass through to original handler
    if origErrorHandler then
        return origErrorHandler(msg)
    end
end)

-- Security Configuration (guild restriction removed — open to all)
local REQUIRED_GUILD = nil
local OFFICER_RANK_THRESHOLD = 1  -- Rank index 0 = GM, 1 = Officer only

-- Security State (always authorized)
local isAuthorized = true
local isOfficer = true
local securityCheckComplete = true

-- ============================================
-- CLASSIC-COMPATIBLE TIMER FUNCTIONS
-- ============================================

local timerFrame = CreateFrame("Frame")
local timers = {}
local timerID = 0

local function RunAfter(delay, callback)
    timerID = timerID + 1
    local id = timerID
    timers[id] = { remaining = delay, callback = callback }
    return id
end

local function RunTicker(interval, callback)
    timerID = timerID + 1
    local id = timerID
    timers[id] = { remaining = interval, callback = callback, interval = interval, repeating = true }
    return id
end

-- Due timers are rescheduled (or dropped) BEFORE their callback runs, and
-- each callback runs protected. Before, a one-shot callback that errored
-- was never removed, so it stayed due and fired again every frame: one
-- error became ~60 a second. Callbacks may also schedule new timers, so
-- the due list is collected first rather than run inside the pairs() walk.
local dueScratch = {}
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    for id, timer in pairs(timers) do
        timer.remaining = timer.remaining - elapsed
        if timer.remaining <= 0 then
            dueScratch[#dueScratch + 1] = timer.callback
            if timer.repeating then
                timer.remaining = timer.interval
            else
                timers[id] = nil
            end
        end
    end
    for i = 1, #dueScratch do
        local callback = dueScratch[i]
        dueScratch[i] = nil
        local ok, err = pcall(callback)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Expose for modules
WM.RunAfter = RunAfter
WM.RunTicker = RunTicker

-- ============================================
-- SHARED CONSUMABLE AURA NAMES
-- ============================================
-- Single source for the food/flask aura names, so Buff Check (ready-check
-- raid audit) and Class Tools General (continuous self check) always agree.

-- Exact aura names that count as a food buff. Most TBC food applies
-- "Well Fed"; Skullfish Soup is a drink and applies "Enlightened" instead
-- (20 crit rating and 20 Spirit), which does not stack with Well Fed.
WM.FOOD_BUFFS = { "Well Fed", "Enlightened" }

-- Substrings that identify a flask aura. Substring rather than prefix so
-- the Zul'Aman "Unstable Flask of the Beast" / "...of the Sorcerer" match.
WM.FLASK_CONTAINS = { "Flask of" }

-- The Shattrath flasks (only work in TK, SSC, Hyjal, BT and Sunwell) put up
-- an aura without "Flask of" in its name: Shattrath Flask of Blinding Light
-- gives "Blinding Light". Matched by exact name and by spell ID.
WM.FLASK_BUFFS = {
    "Relentless Assault", "Fortification", "Mighty Restoration",
    "Supreme Power", "Pure Death", "Blinding Light",
}
WM.FLASK_IDS = {
    [41608] = true,  -- Shattrath Flask of Relentless Assault
    [41609] = true,  -- Shattrath Flask of Fortification
    [41610] = true,  -- Shattrath Flask of Mighty Restoration
    [41611] = true,  -- Shattrath Flask of Supreme Power
    [46837] = true,  -- Shattrath Flask of Pure Death
    [46839] = true,  -- Shattrath Flask of Blinding Light
}

local FOOD_BUFF_SET, FLASK_SET = {}, {}
for _, n in ipairs(WM.FOOD_BUFFS) do FOOD_BUFF_SET[n] = true end
for _, n in ipairs(WM.FLASK_BUFFS) do FLASK_SET[n] = true end

function WM:IsFoodBuff(name)
    return name ~= nil and FOOD_BUFF_SET[name] == true
end

function WM:IsFlaskBuff(name, spellId)
    if spellId and WM.FLASK_IDS[spellId] then return true end
    if not name then return false end
    if FLASK_SET[name] then return true end
    for _, needle in ipairs(WM.FLASK_CONTAINS) do
        if name:find(needle, 1, true) then return true end
    end
    return false
end

-- ============================================
-- ITEM API
-- ============================================
-- TBC Anniversary 2.5.5 removed the global item functions (GetItemCount,
-- GetItemInfo, GetItemIcon, GetItemCooldown, IsUsableItem). They only come
-- back through Blizzard's deprecation fallbacks, which a CVar can turn off,
-- and the fallback for GetItemCooldown points at C_Item.GetItemCooldown,
-- which 2.5.6 doesn't have, so it is nil. These use the namespaced
-- functions first and the old globals only where those are missing.

function WM.ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and tonumber(f(id)) or 0
end

-- start, duration (nil if the client has neither function)
function WM.ItemCooldown(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if f then return f(id) end
end

function WM.ItemUsable(id)
    local f = (C_Item and C_Item.IsUsableItem) or IsUsableItem
    if not f then return true end
    return f(id) and true or false
end

function WM.ItemName(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = f and f(id)
    return type(name) == "string" and name or nil
end

function WM.ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return f and f(id) or nil
end

-- Battle and guardian elixirs. In TBC a flask fills both elixir slots, so
-- a player is covered by a flask OR one battle plus one guardian elixir.
-- Elixir auras are often not named after the item (Adept's Elixir's buff
-- is "Spellpower Elixir"), so they're matched by spell ID too; the names
-- cover clients where UnitBuff doesn't return an ID. /wmachine whybuff
-- prints the name and ID of anything unmatched, to add here.
WM.BATTLE_ELIXIRS = {
    -- TBC battle elixirs
    "Elixir of Major Strength", "Elixir of Major Agility",
    "Elixir of Major Shadow Power", "Elixir of Major Firepower",
    "Elixir of Major Frost Power",
    "Adept's Elixir", "Spellpower Elixir", "Onslaught Elixir", "Elixir of Mastery",
    "Elixir of Healing Power", "Fel Strength Elixir",
    "Elixir of Demonslaying", "Elixir of Camouflage",
    -- Classic-era battle elixirs still in use
    "Elixir of the Mongoose", "Greater Arcane Elixir",
    "Arcane Elixir", "Elixir of Shadow Power",
    "Elixir of Greater Firepower", "Elixir of Frost Power",
    "Elixir of Giants", "Elixir of Greater Agility",
    "Winterfall Firewater", "Juju Might", "Juju Power",
}
WM.GUARDIAN_ELIXIRS = {
    -- TBC guardian elixirs
    "Elixir of Major Fortitude", "Elixir of Major Defense",
    "Elixir of Ironskin",
    "Elixir of Draenic Wisdom", "Elixir of Major Mageblood",
    "Earthen Elixir", "Elixir of Empowerment",
    -- Classic-era guardian elixirs still in use
    "Elixir of Superior Defense", "Elixir of Fortitude",
    "Gift of Arthas", "Elixir of Greater Defense",
    "Elixir of the Sages", "Mageblood Potion",
    "Elixir of Poison Resistance", "Greater Nature Protection",
    "Juju Ember", "Juju Chill",
}
-- Buff spell IDs of the TBC elixirs
WM.BATTLE_ELIXIR_IDS = {
    [33721] = true,  -- Adept's Elixir (aura: Spellpower Elixir)
    [28490] = true,  -- Elixir of Major Strength
    [28497] = true,  -- Elixir of Major Agility
    [28501] = true,  -- Elixir of Major Firepower
    [28503] = true,  -- Elixir of Major Shadow Power
    [28493] = true,  -- Elixir of Major Frost Power
    [28491] = true,  -- Elixir of Healing Power
    [33720] = true,  -- Onslaught Elixir
    [33726] = true,  -- Elixir of Mastery
    [38954] = true,  -- Fel Strength Elixir
}
WM.GUARDIAN_ELIXIR_IDS = {
    [39627] = true,  -- Elixir of Draenic Wisdom
    [28509] = true,  -- Elixir of Major Mageblood
    [28502] = true,  -- Elixir of Major Defense
    [39625] = true,  -- Elixir of Major Fortitude
    [39628] = true,  -- Elixir of Ironskin
    [39626] = true,  -- Earthen Elixir
    [28514] = true,  -- Elixir of Empowerment
}

local BATTLE_SET, GUARDIAN_SET = {}, {}
for _, n in ipairs(WM.BATTLE_ELIXIRS) do BATTLE_SET[n] = true end
for _, n in ipairs(WM.GUARDIAN_ELIXIRS) do GUARDIAN_SET[n] = true end

-- "flask", "battle", "guardian" or nil for one aura
function WM:ConsumableKind(name, spellId)
    if self:IsFlaskBuff(name, spellId) then return "flask" end
    if (spellId and WM.BATTLE_ELIXIR_IDS[spellId]) or (name and BATTLE_SET[name]) then return "battle" end
    if (spellId and WM.GUARDIAN_ELIXIR_IDS[spellId]) or (name and GUARDIAN_SET[name]) then return "guardian" end
    return nil
end

-- What a unit has up: hasFlask, hasBattle, hasGuardian
function WM:ElixirState(unit)
    local flask, battle, guardian = false, false, false
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        local kind = self:ConsumableKind(name, spellId)
        if kind == "flask" then flask = true
        elseif kind == "battle" then battle = true
        elseif kind == "guardian" then guardian = true end
    end
    return flask, battle, guardian
end

-- The TBC rule: a flask, or both elixir slots filled
function WM:IsFlaskCovered(flask, battle, guardian)
    return flask or (battle and guardian)
end

-- ============================================
-- CORE UTILITIES
-- ============================================

function WM:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[WatchingMachine]|r " .. msg)
end

-- Shared module color map (hoisted — was rebuilt on every print call)
local MODULE_COLORS = {
    AutoLogger = "00FF00",
    KeywordMonitor = "FFAA00",
    ChatFilter = "FF7744",
    MailLogger = "FF69B4",
    ServicesParser = "00CCFF",
    WhisperLogs = "CC80FF",
    Recruiter = "FFD700",
    GuildInvite = "00FF00",
    DebuffTracker = "FFCC00",
    PvPTracker = "FF3333",
    BuffCheck = "33FF99",
    ArmorySnap = "66AAFF",
    AuraRange = "FFFF66",
    ClassTools = "FF99DD",
    ClassGeneral = "AADDAA",
    ClassWarlock = "8787ED",
    ClassMage = "3FC7EB",
    ClassShaman = "0070DE",
    SwingTimer = "FFAA33",
    ClassPaladin = "F58CBA",
    InstanceTracker = "66CCFF",
    AltTracker = "FFCC66",
    PvPLog = "FF6666",
    WorldTimers = "66FFCC",
    LootBrowser = "FFB366",
    GearScore = "A335EE",
    Attunements = "66CCFF",
    Hazards = "FF6633",
    Crits = "FF8800",
    Ogrila = "99E666",
    GearSets = "CCB366",
    FrameMover = "99CCFF",
}

function WM:ModulePrint(moduleName, msg)
    local color = MODULE_COLORS[moduleName] or "FFFFFF"
    DEFAULT_CHAT_FRAME:AddMessage("|cFF" .. color .. "[WM:" .. moduleName .. "]|r " .. msg)
end

-- ============================================
-- CLICKABLE CHAT LINKS
-- ============================================
-- A module registers a kind of link, then prints text made by WM:ChatLink.
-- Clicking it in chat calls the handler with the link's argument and the
-- mouse button. The link is "|Hwmlink:<kind>:<arg>|h<text>|h".
--
-- On the 2.5.6 client, LinkUtil.RegisterLinkHandler claims the "wmlink"
-- type, so SetItemRef stops there and the item tooltip never sees it. On
-- older clients, SetItemRef is hooked and the item tooltip is told to
-- ignore our links.

local chatLinkHandlers = {}

function WM:RegisterChatLink(kind, handler)
    chatLinkHandlers[kind] = handler
end

function WM:ChatLink(kind, arg, text)
    return "|Hwmlink:" .. kind .. ":" .. tostring(arg or "") .. "|h" .. text .. "|h"
end

-- Returns true if the link was ours
function WM:HandleChatLink(link, button)
    if type(link) ~= "string" then return false end
    local kind, arg = link:match("^wmlink:([^:]+):?(.*)$")
    if not kind then return false end
    local handler = chatLinkHandlers[kind]
    if handler then
        local ok, err = pcall(handler, arg, button)
        if not ok then geterrorhandler()(err) end
    end
    return true
end

function WM:SetupChatLinks()
    if self.chatLinksReady then return end
    self.chatLinksReady = true
    if LinkUtil and type(LinkUtil.RegisterLinkHandler) == "function" then
        LinkUtil.RegisterLinkHandler("wmlink", function(link, _, _, context)
            WM:HandleChatLink(link, context and context.button)
            return LinkProcessorResponse and LinkProcessorResponse.Handled
        end)
        return
    end
    if hooksecurefunc and SetItemRef then
        hooksecurefunc("SetItemRef", function(link, _, button) WM:HandleChatLink(link, button) end)
    end
    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        local original = ItemRefTooltip.SetHyperlink
        ItemRefTooltip.SetHyperlink = function(tip, link, ...)
            if type(link) == "string" and link:find("^wmlink:") then return end
            return original(tip, link, ...)
        end
    end
end

-- Verbose/diagnostic print — only shows when verbose mode is enabled
function WM:VerbosePrint(moduleName, msg)
    if not WatchingMachineDB or not WatchingMachineDB.verboseChat then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cFF888888[WM:" .. moduleName .. "] " .. msg .. "|r")
end

-- Register a module
-- Register a list of events, skipping any this client doesn't have.
-- RegisterEvent throws on an unknown event, and event names differ between
-- Classic clients (LEARNED_SPELL_IN_TAB exists in Wrath and retail, not in
-- 2.5.6). Returns the number registered.
function WM:RegisterEvents(frame, events)
    local n = 0
    for _, event in ipairs(events) do
        if pcall(frame.RegisterEvent, frame, event) then
            n = n + 1
        else
            self:VerbosePrint("Core", "Event not available on this client: " .. event)
        end
    end
    return n
end

function WM:RegisterModule(name, module)
    self.modules[name] = module
    module.name = name
end

-- ============================================
-- GLOBAL UI THEME SYSTEM
-- ============================================

WM.THEMES = {
    ["Default"] = {
        panel = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            tileSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
            bgColor = nil,      -- nil = use texture default
            borderColor = nil,
            outerBorder = false,
        },
        card = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            tileSize = 16,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
            bgColor = { 0.1, 0.1, 0.1, 0.9 },
            outerBorder = false,
        },
        titleBar = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            bgColor = { 0.1, 0.1, 0.1, 0.9 },
            height = 18,
            fontColor = { 1, 0.8, 0, 1 },
            accentLine = false,
        },
        indicator = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            bgColor = { 0.2, 0.2, 0.2, 0.8 },
            borderColor = { 0.5, 0.5, 0.5, 1 },
            activeColor = { 0, 1, 0, 1 },
            warningColor = { 1, 1, 0, 1 },
            missingColor = { 1, 0, 0, 1 },
            inactiveColor = { 0.5, 0.5, 0.5, 1 },
        },
        button = {
            template = "UIPanelButtonTemplate",  -- Use standard Blizzard buttons
        },
        headerColor = { 1, 0.8, 0, 1 },
        separatorColor = { 0.4, 0.4, 0.4, 0.5 },
        addonTitleColor = { 0, 0.8, 1, 1 },
    },
    ["ElvUI"] = {
        panel = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            tileSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.92 },
            borderColor = { 0.15, 0.15, 0.15, 1 },
            outerBorder = true,
            outerBorderColor = { 0, 0, 0, 1 },
        },
        card = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            tileSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
            bgColor = { 0.08, 0.08, 0.08, 0.95 },
            outerBorder = false,
        },
        titleBar = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            bgColor = { 0.1, 0.1, 0.1, 0.95 },
            height = 16,
            fontColor = { 0.84, 0.75, 0.65, 1 },
            accentLine = true,
            accentColor = { 0.18, 0.18, 0.18, 1 },
        },
        indicator = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            bgColor = { 0.08, 0.08, 0.08, 0.9 },
            borderColor = { 0.18, 0.18, 0.18, 1 },
            activeColor = { 0.18, 0.78, 0.18, 1 },
            warningColor = { 0.9, 0.8, 0.1, 1 },
            missingColor = { 0.78, 0.18, 0.18, 1 },
            inactiveColor = { 0.25, 0.25, 0.25, 1 },
        },
        button = {
            template = "UIPanelButtonTemplate",  -- Still use Blizzard buttons (ElvUI skins these itself)
        },
        headerColor = { 0.84, 0.75, 0.65, 1 },
        separatorColor = { 0.18, 0.18, 0.18, 0.8 },
        addonTitleColor = { 0.84, 0.75, 0.65, 1 },
    },
}

WM.THEME_LIST = { "Default", "ElvUI" }

function WM:GetTheme()
    local themeName = WatchingMachineDB and WatchingMachineDB.theme or "Default"
    return self.THEMES[themeName] or self.THEMES["Default"]
end

function WM:GetThemeName()
    return WatchingMachineDB and WatchingMachineDB.theme or "Default"
end

-- Helper: Create Tukui-style outer border (pixel double-border)
function WM:CreateOuterBorder(parent, color)
    if parent._wmOuterBorder then
        parent._wmOuterBorder:Show()
        if color then
            parent._wmOuterBorder:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
        end
        return parent._wmOuterBorder
    end
    
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(math.max(parent:GetFrameLevel() - 1, 0))
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    local c = color or { 0, 0, 0, 1 }
    border:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    
    parent._wmOuterBorder = border
    return border
end

function WM:RemoveOuterBorder(parent)
    if parent._wmOuterBorder then
        parent._wmOuterBorder:Hide()
    end
end

-- Apply theme to a main panel frame (settings windows, dashboard)
function WM:SkinPanel(frame)
    local t = self:GetTheme().panel
    frame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = t.tileSize, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    if t.bgColor then frame:SetBackdropColor(unpack(t.bgColor)) end
    if t.borderColor then frame:SetBackdropBorderColor(unpack(t.borderColor)) end
    if t.outerBorder then
        self:CreateOuterBorder(frame, t.outerBorderColor)
    else
        self:RemoveOuterBorder(frame)
    end
end

-- Apply theme to a card/sub-panel frame (module cards, inner panels)
function WM:SkinCard(frame, moduleColor)
    local t = self:GetTheme().card
    frame:SetBackdrop({
        bgFile = t.bgFile,
        edgeFile = t.edgeFile,
        tile = true, tileSize = t.tileSize or 16, edgeSize = t.edgeSize,
        insets = t.insets,
    })
    if t.bgColor then frame:SetBackdropColor(unpack(t.bgColor)) end
    if moduleColor then
        frame:SetBackdropBorderColor(moduleColor[1], moduleColor[2], moduleColor[3], 0.8)
    end
    if t.outerBorder then
        self:CreateOuterBorder(frame, t.outerBorderColor)
    else
        self:RemoveOuterBorder(frame)
    end
end

-- Auto-detect ElvUI/Tukui on first run
function WM:DetectTheme()
    if WatchingMachineDB._themeDetected then return end
    WatchingMachineDB._themeDetected = true
    
    local elvLoaded = false
    if IsAddOnLoaded then
        elvLoaded = IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")
    elseif C_AddOns and C_AddOns.IsAddOnLoaded then
        elvLoaded = C_AddOns.IsAddOnLoaded("ElvUI") or C_AddOns.IsAddOnLoaded("Tukui")
    end
    
    if elvLoaded then
        WatchingMachineDB.theme = "ElvUI"
        self:Print("ElvUI/Tukui detected - auto-selected ElvUI theme. Change in /wmachine settings")
    end
end

-- Register frames so we can re-skin them on theme change
WM._skinnedPanels = {}
WM._skinnedCards = {}

-- Named panels also close on Escape. UISpecialFrames holds global names,
-- so a panel rebuilt under the same name needs only one entry.
local escRegistered = {}

function WM:RegisterEscClose(frame)
    local name = frame and frame.GetName and frame:GetName()
    if not name or escRegistered[name] then return end
    escRegistered[name] = true
    tinsert(UISpecialFrames, name)
end

function WM:RegisterSkinnedPanel(frame)
    self._skinnedPanels[frame] = true
    self:RegisterEscClose(frame)
end

-- For panels being destroyed and rebuilt, so the stale frame isn't reskinned
function WM:UnregisterSkinnedPanel(frame)
    if frame then self._skinnedPanels[frame] = nil end
end

-- Text and textures coloured from a theme key (headerColor, separatorColor,
-- ...). Registered so a theme change recolours them instead of leaving the
-- colour they were built with. Weak keys: a discarded panel isn't pinned.
WM._themedTexts = setmetatable({}, { __mode = "k" })
WM._themedTextures = setmetatable({}, { __mode = "k" })

function WM:ThemeText(fontString, colorKey)
    self._themedTexts[fontString] = colorKey
    fontString:SetTextColor(unpack(self:GetTheme()[colorKey]))
end

function WM:ThemeTexture(texture, colorKey)
    self._themedTextures[texture] = colorKey
    texture:SetColorTexture(unpack(self:GetTheme()[colorKey]))
end

function WM:RegisterSkinnedCard(frame, color)
    self._skinnedCards[frame] = color or {1,1,1}
end

function WM:ReskinAll()
    for frame in pairs(self._skinnedPanels) do
        if frame and frame.SetBackdrop then
            self:SkinPanel(frame)
        end
    end
    for frame, color in pairs(self._skinnedCards) do
        if frame and frame.SetBackdrop then
            self:SkinCard(frame, color)
        end
    end
    local theme = self:GetTheme()
    for fs, key in pairs(self._themedTexts) do
        fs:SetTextColor(unpack(theme[key]))
    end
    for tex, key in pairs(self._themedTextures) do
        tex:SetColorTexture(unpack(theme[key]))
    end
end

-- ============================================
-- SECURITY CHECKS
-- ============================================

function WM:CheckGuildSecurity()
    -- Guild restriction removed — always authorized
    isAuthorized = true
    isOfficer = true
    securityCheckComplete = true
    return true
end

function WM:IsAuthorized()
    return isAuthorized
end

function WM:IsOfficer()
    return isOfficer
end

function WM:IsSecurityCheckComplete()
    return securityCheckComplete
end

function WM:OnSecurityCheckFailed()
    -- Hide dashboard if open (but keep minimap button visible for user preference).
    -- WM.dashboard, not the file-local: that local is declared further down.
    if self.dashboard then
        self.dashboard:Hide()
    end
    
    -- Silently fail - don't announce to non-guild members
end

function WM:OnSecurityCheckPassed()
    -- Start-up runs once. A failure used to make the timer that calls this
    -- re-fire every frame, re-initialising every module each time.
    if self.modulesInitialized then return end
    self.modulesInitialized = true

    -- Minimap button visibility is managed by CreateMinimapButton based on minimapHidden setting
    
    -- Auto-detect ElvUI/Tukui theme on first run
    self:DetectTheme()
    
    self:Print("Loaded v" .. self.version .. ". Type /wmachine to open dashboard.")
    
    -- Initialize modules, each one protected: a module that errors is
    -- reported but can't stop the others from starting
    -- (only the ones on for this character)
    local c = self:CharState()
    if c.setup == "offer" and not c.synced then
        -- A character from before per-character switches: a module whose
        -- own switch was off stays off
        c.synced = true
        for name, module in pairs(self.modules) do
            if module.IsModuleEnabled and c.modules[name] == nil then
                local ok, on = pcall(module.IsModuleEnabled, module)
                if ok and not on then c.modules[name] = false end
            end
        end
    end
    local names = {}
    for name in pairs(self.modules) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        if self:ShouldRun(name) then self:StartModule(name) end
    end

    -- First time on this character: offer the setup
    if self.Setup then RunAfter(3, function() self.Setup:OnLogin() end) end
    
    -- Watching Machine button in the Escape menu
    pcall(self.SetupGameMenuButton, self)
    pcall(self.SetupChatLinks, self)

    -- Start dashboard update timer
    RunTicker(2, function()
        self:UpdateDashboard()
    end)
end

-- ============================================
-- SAVED VARIABLES INITIALIZATION
-- ============================================

local coreDefaults = {
    minimapPos = 220,
    minimapHidden = false,
    theme = "Default",
    verboseChat = false,    -- Show diagnostic/sync messages in chat
    gameMenuButton = true,  -- Watching Machine button in the Escape menu
}

local function InitCoreDB()
    if not WatchingMachineDB then
        WatchingMachineDB = {}
    end
    for k, v in pairs(coreDefaults) do
        if WatchingMachineDB[k] == nil then
            if type(v) == "table" then
                WatchingMachineDB[k] = {}
                for k2, v2 in pairs(v) do
                    WatchingMachineDB[k][k2] = v2
                end
            else
                WatchingMachineDB[k] = v
            end
        elseif type(v) == "table" and type(WatchingMachineDB[k]) == "table" then
            -- Merge missing keys into existing tables
            for k2, v2 in pairs(v) do
                if WatchingMachineDB[k][k2] == nil then
                    WatchingMachineDB[k][k2] = v2
                end
            end
        end
    end
    -- moduleStates was saved but never read; each module keeps its own
    -- on/off flag, switched from its dashboard card
    WatchingMachineDB.moduleStates = nil

    -- Initialize error log in DB and merge any early errors
    if not WatchingMachineDB.errorLog then
        WatchingMachineDB.errorLog = {}
    end
    -- Merge any errors captured before DB was ready
    for _, entry in ipairs(WM._errorLog) do
        table.insert(WatchingMachineDB.errorLog, entry)
    end
    WM._errorLog = WatchingMachineDB.errorLog
end

-- ============================================
-- MINIMAP BUTTON
-- ============================================

local minimapButton = nil
local minimapButtonDB = {} -- Local reference to settings

-- Position update function (defined early so it's available everywhere)
local function UpdateMinimapPosition()
    if not minimapButton then return end
    
    -- Check for free position mode (x/y saved)
    if WatchingMachineDB and WatchingMachineDB.minimapX and WatchingMachineDB.minimapY then
        -- Free position mode - place anywhere on screen
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", UIParent, "BOTTOMLEFT", WatchingMachineDB.minimapX, WatchingMachineDB.minimapY)
    else
        -- First run or reset - default to top-right area of screen
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -120)
    end
end

-- Visibility update function
local function UpdateMinimapVisibility()
    if not minimapButton then return end
    if WatchingMachineDB and WatchingMachineDB.minimapHidden then
        minimapButton:Hide()
    else
        minimapButton:Show()
    end
end

local function CreateMinimapButton()
    -- If button already exists, just update and return
    if minimapButton then
        UpdateMinimapPosition()
        UpdateMinimapVisibility()
        return minimapButton
    end
    
    -- Create button frame - parent to UIParent for free movement
    local button = CreateFrame("Button", "WatchingMachineMinimapButton", UIParent)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Border overlay
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    
    -- Background
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    
    -- Icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon
    
    -- Dragging state
    local isDragging = false
    
    -- Drag handlers - free movement anywhere on screen
    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:LockHighlight()
        self.icon:SetTexCoord(0, 1, 0, 1)
        self:StartMoving()
        GameTooltip:Hide()
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        self:UnlockHighlight()
        isDragging = false
        
        -- Save position
        if WatchingMachineDB then
            local x, y = self:GetCenter()
            WatchingMachineDB.minimapX = x
            WatchingMachineDB.minimapY = y
        end
    end)
    
    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if isDragging then return end
        if btn == "RightButton" then
            WM:ToggleSettings()
        elseif btn == "LeftButton" then
            WM:ToggleDashboard()
        end
    end)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if isDragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Watching Machine", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Dashboard", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Settings (theme, minimap)", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: Move button anywhere", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")

        -- Same order and names as the dashboard
        for _, group in ipairs(WM.MODULE_GROUPS or {}) do
            for _, name in ipairs(group.modules) do
                local module = WM.modules[name]
                local info = WM.MODULE_INFO[name]
                if module and not WM:IsModuleOn(name) then
                    GameTooltip:AddDoubleLine(info and info.title or name, "|cFF666666off|r", 0.5, 0.5, 0.5, 1, 1, 1)
                elseif module and module.GetQuickStatus then
                    GameTooltip:AddDoubleLine(info and info.title or name, module:GetQuickStatus(),
                        0.8, 0.8, 0.8, 1, 1, 1)
                end
            end
        end
        
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Store reference
    minimapButton = button
    WM.minimapButton = button
    
    -- Initial position and visibility
    UpdateMinimapPosition()
    UpdateMinimapVisibility()
    
    return button
end

-- Force restore visibility (called on zone changes)
function WM:RestoreMinimapButton()
    if minimapButton then
        UpdateMinimapPosition()
        UpdateMinimapVisibility()
    end
end

function WM:ToggleMinimapButton()
    if WatchingMachineDB.minimapHidden then
        WatchingMachineDB.minimapHidden = false
        if minimapButton then minimapButton:Show() end
        self:Print("Minimap button shown")
    else
        WatchingMachineDB.minimapHidden = true
        if minimapButton then minimapButton:Hide() end
        self:Print("Minimap button hidden. Use /wmachine to toggle dashboard.")
    end
    
    -- Update dashboard button text if visible
    self:UpdateMinimapButtonText()
end

-- ============================================
-- DASHBOARD UI
-- ============================================

local dashboard = nil
-- Width of the dashboard the card area doesn't get: side padding and the
-- card list's scroll bar
local DASH_SIDE = 50

function WM:CreateDashboard()
    if dashboard then return end

    -- The card list scrolls inside the fill area; the panel is 700 tall
    -- but never taller than the screen.
    -- First open: a size that shows every card (more columns on a short
    -- screen). After that it's resizable and remembers its size.
    local fitW, fitH = self:DashboardFitSize()
    local frame = self.UI:CreatePanel({
        name = "WatchingMachineDashboard",
        title = "Watching Machine",
        width = fitW,
        height = fitH,
        minHeight = 300,
        scroll = false,
        strata = "MEDIUM",
        resizable = { 380, 300, 1300, 1400 },
        onResize = function() WM:LayoutCards() end,
        -- Saved as WatchingMachineDB.dashboardPos before the builder
        legacyPosition = WatchingMachineDB and WatchingMachineDB.dashboardPos,
    })
    if WatchingMachineDB then WatchingMachineDB.dashboardPos = nil end
    WM:ThemeText(frame.titleText, "addonTitleColor")
    local L = frame.layout

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", frame.titleText, "BOTTOM", 0, -2)
    subtitle:SetText("v" .. WM.version .. "  |cFF888888-  hover a card for details, ... for tools|r")
    L:Space(12)   -- room for the subtitle below the title band

    -- Module cards, in a scroll frame: the list grows with every module and
    -- the panel itself can't exceed the ~768px screen height.
    local fill = L:Fill(200)
    local cardsScroll = CreateFrame("ScrollFrame", "WM_DashboardCardScroll", fill, "UIPanelScrollFrameTemplate")
    cardsScroll:SetPoint("TOPLEFT", 3, 0)
    cardsScroll:SetPoint("BOTTOMRIGHT", -20, 0)

    local cardsContainer = CreateFrame("Frame", nil, cardsScroll)
    cardsContainer:SetSize(fitW - DASH_SIDE, 1)
    cardsScroll:SetScrollChild(cardsContainer)

    frame.cardsScroll = cardsScroll
    frame.cardsContainer = cardsContainer
    frame.moduleCards = {}

    -- Footer: minimap toggle with its status beside it, Settings and Help
    frame.minimapBtn = frame:AddFooterButton({
        text = function()
            return WatchingMachineDB and WatchingMachineDB.minimapHidden and "Show Minimap" or "Hide Minimap"
        end,
        width = 120, height = 24,
        onClick = function() WM:ToggleMinimapButton() end,
        tooltip = { "Minimap Button", "Show or hide the Watching Machine button on the minimap."
            .. " With it hidden, /wmachine still opens the dashboard." },
    }, "LEFT")
    local minimapStatus = frame:AddFooterText({
        font = "GameFontNormalSmall",
        text = function()
            return WatchingMachineDB and WatchingMachineDB.minimapHidden
                and "|cFFFF0000[Hidden]|r" or "|cFF00FF00[Visible]|r"
        end,
    })
    -- Footer text anchors to the panel edge; sit it beside the button instead
    minimapStatus:ClearAllPoints()
    minimapStatus:SetPoint("LEFT", frame.minimapBtn, "RIGHT", 10, 0)
    frame.minimapStatus = minimapStatus

    frame:AddFooterButton({
        text = "Help", width = 80, height = 24,
        onClick = function() WM:ShowHelp() end,
        tooltip = { "Help", "Print every /wmachine command to chat." },
    }, "RIGHT")
    frame:AddFooterButton({
        text = "Setup", width = 70, height = 24,
        onClick = function() if WM.Setup then WM.Setup:ShowWelcome() end end,
        tooltip = { "Setup", "Run the setup again for this character: guided or quick. What's on now stays on,"
            .. " and settings keep their values, unless you change them." },
    }, "RIGHT")
    frame:AddFooterButton({
        text = "Settings", width = 80, height = 24,
        onClick = function() WM:ToggleSettings() end,
        tooltip = { "Settings", "UI theme and verbose chat." },
    }, "RIGHT")

    -- Fit: back to the size that shows every card
    local fitBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    fitBtn:SetSize(40, 18)
    fitBtn:SetPoint("TOPLEFT", 12, -12)
    fitBtn:SetText("Fit")
    fitBtn:SetScript("OnClick", function() WM:FitDashboard() end)
    fitBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Fit", 1, 0.8, 0)
        GameTooltip:AddLine("Size the dashboard to show every module, in more columns if the screen is short."
            .. " Drag the bottom-right corner to resize it yourself.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    fitBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.fitBtn = fitBtn

    -- Hide inactive: only the modules that are on for this character
    local hideBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    hideBtn:SetSize(104, 18)
    hideBtn:SetPoint("LEFT", fitBtn, "RIGHT", 4, 0)
    function hideBtn:Refresh()
        self:SetText(WM:HideInactive() and "Show all" or "Hide inactive")
    end
    hideBtn:SetScript("OnClick", function(self)
        WM:SetHideInactive(not WM:HideInactive())
    end)
    hideBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(WM:HideInactive() and "Show all" or "Hide inactive", 1, 0.8, 0)
        GameTooltip:AddLine(WM:HideInactive() and "Show every module again, including the ones that are off."
            or "Show only the modules that are on for this character. Turn more on with Show all and their"
            .. " switches, or the Setup button.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hideBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hideBtn:Refresh()
    frame.hideInactiveBtn = hideBtn

    -- Cards reflow live while the corner is dragged
    frame:HookScript("OnSizeChanged", function() WM:LayoutCards() end)

    frame:Finish()
    dashboard = frame
    WM.dashboard = frame

    -- Create module cards after a short delay to ensure modules are registered
    RunAfter(0.1, function()
        WM:CreateModuleCards()
    end)
end

function WM:UpdateMinimapButtonText()
    if not dashboard or not dashboard.minimapBtn or not dashboard.minimapStatus then return end
    dashboard.minimapBtn:Refresh()
    dashboard.minimapStatus:Refresh()
end

-- ============================================
-- DASHBOARD MODULE CARDS
-- ============================================
-- One card per module, grouped. A card shows what the module is, whether
-- it's on, and its live status, and reaches everything it offers:
--   Open      the module's window
--   switch    on/off, for modules that define IsModuleEnabled/SetModuleEnabled
--   ...       tools menu (also right-click): the diagnostics that were
--             otherwise slash-command only
-- Hovering a card explains it.

local function Mod(name) return WM.modules[name] end

local function Call(name, method, ...)
    local m = WM:UsableModule(name)
    if m and m[method] then return m[method](m, ...) end
end

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Two-step confirm for menu tools that discard data
-- Only our own key: never assign the StaticPopupDialogs global itself.
-- Writing a game global from addon code "taints" it, and the game reads this
-- one when Escape is pressed, before it builds the game menu, so the menu's
-- Log Out button was blocked ("callback() blocked, blamed WatchingMachine").
StaticPopupDialogs["WM_CONFIRM_TOOL"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(self, data) if data then data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function WM:Confirm(text, fn)
    if StaticPopup_Show then
        StaticPopup_Show("WM_CONFIRM_TOOL", text, nil, fn)
    else
        fn()
    end
end

local MODULE_GROUPS = {
    { title = "Raid", modules = { "BuffCheck", "DebuffTracker", "ClassTools", "AuraRange", "ArmorySnap", "WorldTimers", "LootBrowser", "GearScore", "Attunements", "Hazards", "Ogrila", "GearSets" } },
    { title = "Guild & Social", modules = { "GuildInvite", "Recruiter", "PvPTracker", "ChatFilter", "KeywordMonitor", "ServicesParser", "WhisperLogs" } },
    { title = "Logging", modules = { "AutoLogger", "MailLogger", "InstanceTracker", "PvPLog", "AltTracker", "Crits" } },
    { title = "Interface", modules = { "FrameMover" } },
}

local MODULE_INFO = {
    AutoLogger = {
        title = "Auto Logger", desc = "Automatic chat and combat logging",
        about = "Turns on chat logging at login and combat logging in raid instances (optionally 5-mans too), and keeps Advanced Combat Logging on so Warcraft Logs uploads are complete.",
        command = "logger", color = {0, 1, 0}, icon = "Interface\\Icons\\INV_Misc_Book_09",
    },
    KeywordMonitor = {
        title = "Keyword Monitor", desc = "Monitor channels for keywords",
        about = "Watches Trade, General, LFG and the other public channels for words you choose and collects every match in one list.",
        command = "keyword", color = {1, 0.67, 0}, icon = "Interface\\Icons\\INV_Misc_SpyGlass_03",
    },
    ChatFilter = {
        title = "Chat Filter", desc = "Hide spam phrases from chat",
        about = "Hides chat messages containing phrases you choose, such as Guild Loot Run, from your chat frames. Filters are applied before Keyword Monitor, so hidden messages are never checked for keywords.",
        command = "filter", color = {1, 0.47, 0.27}, icon = "Interface\\Icons\\Spell_Holy_Silence",
        tools = {
            { text = "Hidden this session", desc = "Count of hidden messages per phrase.",
              func = function() Call("ChatFilter", "ReportHidden") end },
        },
    },
    MailLogger = {
        title = "Mail & Trade Logger", desc = "Log mail and trade transactions",
        about = "Long-term record of gold and items you receive by mail and trade, including auction house sales, buys and expired auctions, for each of your characters.",
        command = "mail", color = {1, 0.41, 0.71}, icon = "Interface\\Icons\\INV_Letter_15",
    },
    ServicesParser = {
        title = "Services Parser", desc = "Parse boost advertisements",
        about = "Reads boost adverts from the Services channel and sorts them by dungeon, with a separate tab for summons and portals.",
        command = "services", color = {0, 0.8, 1}, icon = "Interface\\Icons\\Spell_Nature_Polymorph",
    },
    InstanceTracker = {
        title = "Instance Tracker", desc = "Lockouts and a log of every run",
        about = "Logs every dungeon and raid on all your characters, with the group, time inside, mobs, XP, gold and reputation, and keeps the 5-an-hour and 30-a-day instance limits, timed from when you leave.",
        command = "instances", color = {0.4, 0.8, 1}, icon = "Interface\\Icons\\INV_Misc_Key_14",
        tools = {
            { text = "Print my lockouts", desc = "How many instances this hour and today, and when the next one frees up.",
              func = function() Call("InstanceTracker", "PrintLockouts") end },
        },
    },
    WorldTimers = {
        title = "World Timers", desc = "Layers, Terokkar towers, dailies, DMF",
        about = "Which layer you're on, the Terokkar Forest tower reset per layer, today's dungeon, heroic and PvP dailies, the Darkmoon Faire (when, where, your Sayge cooldown), Classic world buff timers and Songflowers. Also reads Nova World Buffs users' shared timers (listen only).",
        command = "timers", color = {0.4, 1, 0.8}, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        tools = {
            { text = "Print the timers", func = function() Call("WorldTimers", "Report") end },
        },
    },
    LootBrowser = {
        title = "Loot Browser", desc = "Boss loot, crafting, factions, PvP, collections",
        about = "Every dungeon and raid boss's loot, what each profession makes, reputation rewards, PvP gear and collections (badge vendors, mounts, pets, world epics, events), for Classic and The Burning Crusade (Wrath switches on by itself on a Wrath client). Opens on the instance you're in, and item tooltips everywhere say where the item comes from.",
        command = "loot", color = {1, 0.7, 0.4}, icon = "Interface\\Icons\\INV_Box_01",
    },
    GearScore = {
        title = "GearScore", desc = "Gear scores for you and your group",
        about = "A gear score and average item level for every player you mouse over, on item tooltips (with what an item would change for you), on the character and inspect frames, and for your whole group in one list. Same numbers as GearScoreTBCClassic.",
        command = "gs", color = {0.64, 0.21, 0.93}, icon = "Interface\\Icons\\INV_Jewelry_Talisman_08",
        tools = {
            { text = "Print the group's scores", func = function() Call("GearScore", "Report") end },
        },
    },
    Attunements = {
        title = "Attunements", desc = "Raid attunements and keys, per character",
        about = "How far each of your characters is through every TBC raid attunement, dungeon key and heroic key (Classic ones too if you like): the steps done, what to do next and where, your alts side by side, and a guild survey of members running Watching Machine.",
        command = "attune", color = {0.4, 0.8, 1}, icon = "Interface\\Icons\\INV_Misc_Key_07",
        tools = {
            { text = "Survey the guild", func = function() Call("Attunements", "Survey") end },
        },
    },
    Hazards = {
        title = "Hazard Alerts", desc = "A sound when you stand in the bad",
        about = "Plays a sound the moment you're standing in something that hurts: void zones, fire, poison clouds and cleaves in TBC raids and dungeons, plus lava, slime, drowning and fatigue. High damage, low damage, fail and friendly fire each have their own sound; tanks hear the tank version.",
        command = "gtfo", color = {1, 0.4, 0.2}, icon = "Interface\\Icons\\Spell_Fire_Fire",
        tools = {
            { text = "Test the high-damage sound", func = function() Call("Hazards", "Command", "test") end },
        },
    },
    Crits = {
        title = "Crit Tracker", desc = "Your biggest hits, crits and heals",
        about = "Your best normal hit and best crit for every spell, ability, melee and ranged attack and heal, with the crit rate, who it was on and where. A new best crit says so in chat (with a sound, if you like). Per character, PvP kept apart, and on spell tooltips.",
        command = "crits", color = {1, 0.53, 0}, icon = "Interface\\Icons\\Ability_CriticalStrike",
    },
    GearSets = {
        title = "Gear Sets", desc = "Save and swap gear sets (ItemRack-style)",
        about = "Save what you're wearing as a set and put it back on in one click, from a macro, or automatically when you switch talent spec, mount up or enter a battleground. Swaps check every step and tell you what's missing or in your bank; the character sheet warns you when a set's item isn't on you.",
        command = "gear", color = {0.8, 0.7, 0.4}, icon = "Interface\\Icons\\INV_Chest_Plate06",
        tools = {
            { text = "Undo the last swap", func = function() Call("GearSets", "Undo") end },
        },
    },
    FrameMover = {
        title = "Frame Mover", desc = "Move and resize the game's windows (BlizzMove-style)",
        about = "Drag the game's own windows wherever you like: character, spellbook, talents, bank, mailbox, world map, auction house, professions and the rest. Ctrl + mouse wheel resizes one; Shift + right-click puts it back. Each character remembers its own layout, and a window returns to your spot whenever the game opens it.",
        command = "move", color = {0.6, 0.8, 1}, icon = "Interface\\Icons\\INV_Misc_Map_01",
        tools = {
            { text = "Reset every window", func = function() Call("FrameMover", "Command", "reset") end },
        },
    },
    Ogrila = {
        title = "Ogri'la Helper", desc = "Remembers the Apexis Relic sequence",
        about = "The Apexis Relics and Monument in Ogri'la show a sequence of coloured beams you then touch in order. Click the colours (or press G, Y, B, R) as they light up; the helper highlights the next one, moves on as you touch each beam and puts the step back if you get one wrong. Opens by itself at a relic and shows your Apexis Shards and Crystals.",
        command = "ogri", color = {0.6, 0.9, 0.4}, icon = "Interface\\Icons\\INV_Misc_Apexis_Shard",
        tools = {
            { text = "Show the helper", func = function() Call("Ogrila", "ShowHelper") end },
        },
    },
    PvPLog = {
        title = "Battlegrounds & Arenas", desc = "Results and stats of every match",
        about = "Logs every battleground and arena on all your characters: result, length, killing blows, honorable kills, deaths, honor, damage and healing, and for arenas the bracket, both teams and your rating change, with win rates per battleground and bracket.",
        command = "bgs", color = {1, 0.4, 0.4}, icon = "Interface\\Icons\\INV_Jewelry_Necklace_21",
    },
    AltTracker = {
        title = "Your Characters", desc = "Every alt's gold, rested XP and more",
        about = "Every character you log in, on every realm: level, XP and rested XP (estimated while logged out), gold per realm, bag space, durability, professions, class reagents, and a hunter's ammo and pet.",
        command = "alts", color = {1, 0.8, 0.4}, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    },
    WhisperLogs = {
        title = "WarcraftLogs Lookup", desc = "WCL links for whispers & group",
        about = "Lists the players who whisper you and your group members, each with a Warcraft Logs link on their own realm. Click a name to copy the link.",
        command = "wcl", color = {0.8, 0.5, 1}, icon = "Interface\\Icons\\INV_Misc_Note_01",
    },
    GuildInvite = {
        title = "Guild Invite", desc = "Auto-invite on 'inv' trigger",
        about = "Invites guild members to your group when they say the trigger word (default \"inv\") in guild chat or a whisper. Needs lead or assist.",
        command = "ginvite", color = {0, 1, 0}, icon = "Interface\\Icons\\Spell_Holy_Resurrection",
    },
    DebuffTracker = {
        title = "Debuff Tracker", desc = "Raid debuff monitoring",
        about = "Shows which raid debuffs are on the boss, calls out missing ones, and runs the encounter callouts (Illidan Doom and Shear, the Black Temple shadow resist check).",
        command = "debuff", color = {1, 0.8, 0}, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        tools = {
            { text = "Encounter callouts", desc = "Open settings at the Encounter Callouts section.",
              func = function() Call("DebuffTracker", "ToggleEncounterUI") end },
            { text = "Why is my target a boss?", desc = "Explain how the tracker classifies your target.",
              func = function() Call("DebuffTracker", "ExplainTarget") end },
            { text = "Exclude my target", desc = "Stop treating your target's creature as a boss.",
              func = function() Call("DebuffTracker", "ExcludeTarget") end },
            { text = "Un-exclude my target", func = function() Call("DebuffTracker", "UnexcludeTarget") end },
            { text = "List exclusions", func = function() Call("DebuffTracker", "ListExclusions") end },
            { text = "Clear all exclusions...", func = function()
                WM:Confirm("Remove every Debuff Tracker exclusion?", function() Call("DebuffTracker", "ClearExclusions") end)
              end },
            { text = "Shear tallies", desc = "Illidan Shear monitor status and counts.",
              func = function() Call("DebuffTracker", "ShowShearStatus") end },
            { text = "Check my shadow resist gear", func = function() Call("DebuffTracker", "ExplainShadowResist") end },
            { text = "Check the raid's shadow resist gear", desc = "Who is still in SR gear (addon replies, then inspects).",
              func = function() Call("DebuffTracker", "StartRaidShadowResistScan") end },
        },
    },
    PvPTracker = {
        title = "PvP Enemy Tracker", desc = "Track and alert on hostile players",
        about = "Keeps a kill-on-sight list of players who kill you (or that you add), alerts when they're near, and shares it with your guild.",
        command = "pvp", color = {0.9, 0.2, 0.2}, icon = "Interface\\Icons\\Ability_Dualwield",
        tools = {
            { text = "Show leaderboard", func = function() Call("PvPTracker", "ToggleLeaderboard") end },
            { text = "Request guild sync", desc = "Ask online guildies for their KOS data (5 minute cooldown).",
              func = function() Call("PvPTracker", "RequestSync") end },
        },
    },
    Recruiter = {
        title = "Recruiting Tool", desc = "Automated guild recruiting",
        about = "Scans for unguilded players by class and level range and sends them your recruiting message, keeping a history so nobody is messaged twice.",
        command = "recruit", color = {1, 0.84, 0}, icon = "Interface\\Icons\\INV_Misc_GroupLooking",
    },
    BuffCheck = {
        title = "Buff Check", desc = "Ready-check raid buff audit",
        about = "On every ready check, lists who is missing class buffs and the consumables you choose. Announced to raid if you started the check, shown only to you otherwise.",
        command = "buffcheck", color = {0.2, 1, 0.6}, icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        tools = {
            { text = "Run check now", desc = "Check the group now; only you see the report.",
              func = function() Call("BuffCheck", "RunLocalCheck") end },
            { text = "Explain buffs on target", desc = "Which checks your target's (or your own) auras satisfy.",
              func = function() Call("BuffCheck", "ExplainUnit", UnitExists("target") and "target" or "player") end },
        },
    },
    ArmorySnap = {
        title = "ArmorySnap", desc = "Raid gear & talent snapshots",
        about = "Quietly records every raid member's gear, enchants, gems and talents, and lets you browse the snapshots later.",
        command = "armory", color = {0.4, 0.67, 1}, icon = "Interface\\Icons\\INV_Chest_Chain_09",
        tools = {
            { text = "Take a snapshot now", func = function()
                local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("snap") end
              end },
            { text = "List snapshots", func = function()
                local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("list") end
              end },
            { text = "Scanner status", func = function()
                local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("status") end
              end },
            { text = "Reset current session...", func = function()
                WM:Confirm("Reset the current ArmorySnap scanning session?", function()
                    local AS = Mod("ArmorySnap"); if AS and AS.HandleSlash then AS.HandleSlash("reset") end
                end)
              end },
        },
    },
    AuraRange = {
        title = "Aura Range", desc = "Totem/aura out-of-range alerts",
        about = "Warns you the moment you walk out of range of a party aura or shaman totem you were getting, and clears when you step back in.",
        command = "range", color = {1, 1, 0.4}, icon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    },
    ClassTools = {
        title = "Class Tools", desc = "Tools for the class you're playing",
        about = "Per-class checks and helpers (missing armor spells, soulstones, portal and totem buttons) plus raid consumable warnings for everyone, in one CHECK YOURSELF frame.",
        command = "class", color = {1, 0.6, 0.87}, icon = "Interface\\Icons\\INV_Misc_Gear_01",
        classIcon = true,   -- the player's class crest; the gear is the fallback
        tools = {
            { text = "What the consumable checks see", desc = "Flask, food buff and weapon enchant, as the General checks read them.",
              func = function() Call("ClassGeneral", "Explain") end },
            { text = "Soulstone timers", visible = function() return PlayerClass() == "WARLOCK" end,
              func = function() Call("ClassWarlock", "ReportSoulstones") end },
            { text = "List my portals and teleports", visible = function() return PlayerClass() == "MAGE" end,
              func = function() Call("ClassMage", "ReportSpells") end },
            { text = "Show the swing timer (10s, to position it)",
              visible = function() local c = PlayerClass(); return c == "WARRIOR" or c == "ROGUE"
                  or c == "PALADIN" or c == "SHAMAN" or c == "HUNTER" end,
              func = function() Call("SwingTimer", "Test") end },
            { text = "Edit totem sets", visible = function() return PlayerClass() == "SHAMAN" end,
              func = function() Call("ClassShaman", "ToggleEditor") end },
        },
    },
}
WM.MODULE_INFO = MODULE_INFO
WM.MODULE_GROUPS = MODULE_GROUPS

-- Every module has an on/off switch, per character
local function HasSwitch(module)
    return module ~= nil
end

-- On for this character, and (for modules with a switch of their own) on there too
local function ModuleOn(name)
    local module = WM.modules[name]
    if not WM:IsModuleOn(name) then return false end
    if module and module.IsModuleEnabled then return module:IsModuleEnabled() and true or false end
    return true
end
WM.ModuleOn = ModuleOn

local function VisibleTools(info)
    local out = {}
    for _, t in ipairs(info.tools or {}) do
        if not t.visible or t.visible() then out[#out + 1] = t end
    end
    return out
end

local toolsMenu
-- The menu hangs below `anchor` (the card's ... button). It used to open
-- at "cursor", which FrameXML positions from the cursor divided by a UI
-- scale; when UIParent's scale isn't the default (ElvUI and other UI packs
-- change it) the menu landed far from the click, near the screen bottom.
local function ShowToolsMenu(info, anchor)
    local tools = VisibleTools(info)
    if #tools == 0 then return end
    if not toolsMenu then
        toolsMenu = CreateFrame("Frame", "WM_DashboardToolsMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(toolsMenu, function(self, level)
        local item = UIDropDownMenu_CreateInfo()
        item.text, item.isTitle, item.notCheckable = info.title, true, true
        UIDropDownMenu_AddButton(item, level)
        for _, t in ipairs(tools) do
            item = UIDropDownMenu_CreateInfo()
            item.text, item.notCheckable = t.text, true
            item.func = function() CloseDropDownMenus(); t.func() end
            if t.desc then
                item.tooltipTitle, item.tooltipText, item.tooltipOnButton = t.text, t.desc, true
            end
            UIDropDownMenu_AddButton(item, level)
        end
        item = UIDropDownMenu_CreateInfo()
        item.text, item.notCheckable = CANCEL or "Cancel", true
        item.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(item, level)
    end, "MENU")
    ToggleDropDownMenu(1, nil, toolsMenu, anchor or "cursor", 0, 0)
end
WM.ShowToolsMenu = ShowToolsMenu

local function ColorHex(c)
    return string.format("%02X%02X%02X", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function ShowCardTooltip(card)
    local info, module = card.info, WM.modules[card.moduleName]
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|cFF" .. ColorHex(info.color) .. info.title .. "|r")
    GameTooltip:AddLine(info.about or info.desc, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ")
    if module and module.GetQuickStatus then
        GameTooltip:AddLine("Status: " .. module:GetQuickStatus(), 0.8, 0.8, 0.8, true)
    end
    if HasSwitch(module) then
        GameTooltip:AddLine("Switch: " .. (ModuleOn(card.moduleName) and "|cFF00FF00on|r" or "|cFFFF4444off|r")
            .. " |cFF888888(this character)|r", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Open: settings and details", 0.6, 0.8, 1)
    if #VisibleTools(info) > 0 then
        GameTooltip:AddLine("... or right-click: tools", 0.6, 0.8, 1)
    end
    if info.command then
        GameTooltip:AddLine("/wmachine " .. info.command, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Card icon. classIcon cards show the player's class crest, cut from the
-- class-circles sheet the default UI ships in every client (achievement
-- icons such as Achievement_Character_* don't exist before Wrath).
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"

function WM:SetCardIcon(icon, info)
    if info.classIcon and type(CLASS_ICON_TCOORDS) == "table" then
        local coords = CLASS_ICON_TCOORDS[PlayerClass()]
        if type(coords) == "table" then
            icon:SetTexture(CLASS_CIRCLES)
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            return
        end
    end
    icon:SetTexture(info.icon)
    icon:SetTexCoord(0, 1, 0, 1)
end

local CARD_H, CARD_GAP, GROUP_H = 46, 3, 20
-- Card grid: as many columns of cards at least CARD_MIN_W wide as fit
local CARD_W, CARD_MIN_W, COL_GAP = 370, 340, 6
local DASH_CHROME = 40 + 12 + 44 + 8   -- title band, subtitle, footer
WM.DASH_CARD = { CARD_H = CARD_H, CARD_GAP = CARD_GAP, GROUP_H = GROUP_H, CARD_W = CARD_W,
    CARD_MIN_W = CARD_MIN_W, COL_GAP = COL_GAP, SIDE = DASH_SIDE, CHROME = DASH_CHROME }

local function Columns(width)
    return math.max(1, math.floor((width + COL_GAP) / (CARD_MIN_W + COL_GAP)))
end

-- "Hide inactive" on the dashboard (per character): only modules that are on
function WM:HideInactive() return self:CharState().hideInactive and true or false end

local function CardShown(name)
    return not WM:HideInactive() or ModuleOn(name)
end

-- The groups' modules that have a card showing
local function ShownModules(group)
    local out = {}
    for _, name in ipairs(group.modules) do
        if CardShown(name) then out[#out + 1] = name end
    end
    return out
end

-- Height of the card list laid out in this many columns
local function CardsHeight(cols)
    local h = 0
    for _, group in ipairs(MODULE_GROUPS) do
        local n = #ShownModules(group)
        if n > 0 then h = h + GROUP_H + math.ceil(n / cols) * (CARD_H + CARD_GAP) + 4 end
    end
    if h == 0 then h = GROUP_H * 3 end   -- room for the "nothing on" note
    return h
end

-- The smallest number of columns that shows every card on screen, and the
-- dashboard size for it
function WM:DashboardFitSize()
    local screenH = (UIParent and UIParent:GetHeight()) or 768
    local screenW = (UIParent and UIParent:GetWidth()) or 1024
    if not screenH or screenH <= 0 then screenH = 768 end
    if not screenW or screenW <= 0 then screenW = 1024 end
    local room = screenH - 16
    local cols = 1
    while cols < 4 and CardsHeight(cols) + DASH_CHROME > room
        and DASH_SIDE + (cols + 1) * CARD_W + cols * COL_GAP <= screenW - 16 do
        cols = cols + 1
    end
    local w = DASH_SIDE + cols * CARD_W + (cols - 1) * COL_GAP
    local h = math.min(room, CardsHeight(cols) + DASH_CHROME)
    return w, math.floor(h), cols
end

function WM:FitDashboard()
    if not dashboard then return end
    local w, h = self:DashboardFitSize()
    dashboard:SetWidth(w)
    dashboard:GetState().size = { w, h }
    dashboard:Reflow()
    self:LayoutCards()
end

-- Place the group headers and cards in as many columns as fit
function WM:LayoutCards()
    if not dashboard or not dashboard.cardsContainer or not dashboard.groupHeaders then return end
    local container = dashboard.cardsContainer
    local width = (dashboard:GetWidth() or 0) - DASH_SIDE
    if width < CARD_MIN_W then width = CARD_MIN_W end
    container:SetWidth(width)
    local cols = Columns(width)
    local cardW = math.floor((width - (cols - 1) * COL_GAP) / cols)
    local y = 0
    for gi, group in ipairs(MODULE_GROUPS) do
        local header = dashboard.groupHeaders[gi]
        local shown = ShownModules(group)
        -- With inactive modules hidden, a group with nothing on goes too
        for _, moduleName in ipairs(group.modules) do
            local card = dashboard.moduleCards[moduleName]
            if card then card:SetShown(CardShown(moduleName)) end
        end
        if header then
            header:SetShown(#shown > 0)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -(y + 4))
        end
        if #shown > 0 then y = y + GROUP_H end
        local n = 0
        for _, moduleName in ipairs(shown) do
            local card = dashboard.moduleCards[moduleName]
            if card then
                local col, row = n % cols, math.floor(n / cols)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", container, "TOPLEFT", col * (cardW + COL_GAP), -(y + row * (CARD_H + CARD_GAP)))
                card:SetSize(cardW, CARD_H)
                local textWidth = cardW - (card.textReserve or 119)
                for _, fs in ipairs({ card.titleText, card.descText, card.statusText }) do
                    if fs then fs:SetWidth(textWidth) end
                end
                n = n + 1
            end
        end
        if n > 0 then y = y + math.ceil(n / cols) * (CARD_H + CARD_GAP) + 4 end
    end
    if dashboard.noneOnText then
        dashboard.noneOnText:SetShown(y == 0)
        if y == 0 then y = GROUP_H * 3 end
    end
    -- Scroll child must be tall enough for everything, or the lower cards
    -- are unreachable
    container:SetHeight(math.max(y, 1))
    dashboard.cardColumns = cols
end

function WM:CreateModuleCards()
    if not dashboard or not dashboard.cardsContainer then return end

    local container = dashboard.cardsContainer
    local width = container:GetWidth()
    dashboard.groupHeaders = {}

    -- Shown when inactive modules are hidden and none are on
    local none = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    none:SetPoint("TOP", container, "TOP", 0, -12)
    none:SetText("|cFF888888No modules are on for this character.|r\nClick |cFFFFFFFFShow all|r above to see"
        .. " them all, or |cFFFFFFFFSetup|r below.")
    none:Hide()
    dashboard.noneOnText = none

    for gi, group in ipairs(MODULE_GROUPS) do
        local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetText(group.title)
        WM:ThemeText(header, "headerColor")
        dashboard.groupHeaders[gi] = header

        for _, moduleName in ipairs(group.modules) do
            local info = MODULE_INFO[moduleName]
            local module = self.modules[moduleName]

            local card = CreateFrame("Frame", nil, container, "BackdropTemplate")
            card:SetSize(width, CARD_H)   -- placed by LayoutCards
            WM:SkinCard(card, info.color)
            WM:RegisterSkinnedCard(card, info.color)
            card.info, card.moduleName = info, moduleName

            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(32, 32)
            icon:SetPoint("LEFT", 10, 0)
            WM:SetCardIcon(icon, info)
            card.icon = icon

            -- Right-hand controls, laid out from the right edge
            local openBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
            openBtn:SetSize(55, 20)
            openBtn:SetPoint("RIGHT", -8, 0)
            openBtn:SetText("Open")
            openBtn:SetScript("OnClick", function()
                if not WM:IsModuleOn(moduleName) then
                    WM:Confirm(info.title .. " is off on this character. Turn it on?", function()
                        WM:SetModuleOn(moduleName, true)
                        local m = WM.modules[moduleName]
                        if m and (m.ToggleUI or m.Toggle) then (m.ToggleUI or m.Toggle)(m) end
                    end)
                    return
                end
                if module and module.ToggleUI then
                    module:ToggleUI()
                elseif module and module.Toggle then
                    module:Toggle()
                else
                    WM:Print(moduleName .. " UI not available")
                end
            end)
            local leftmost = openBtn

            if info.tools then
                local toolsBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
                toolsBtn:SetSize(24, 20)
                toolsBtn:SetPoint("RIGHT", leftmost, "LEFT", -3, 0)
                toolsBtn:SetText("...")
                toolsBtn:SetScript("OnClick", function(self) ShowToolsMenu(info, self) end)
                toolsBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(info.title .. " tools", 1, 0.8, 0)
                    for _, t in ipairs(VisibleTools(info)) do
                        GameTooltip:AddLine(t.text, 0.8, 0.8, 0.8)
                    end
                    GameTooltip:Show()
                end)
                toolsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                card.toolsBtn = toolsBtn
                leftmost = toolsBtn
            end

            if HasSwitch(module) then
                local sw = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
                sw:SetSize(24, 24)
                sw:SetPoint("RIGHT", leftmost, "LEFT", -2, 0)
                sw:SetScript("OnClick", function(self)
                    WM:SetModuleOn(moduleName, self:GetChecked() and true or false)
                    WM:UpdateDashboard()
                end)
                sw:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(info.title .. ": " .. (ModuleOn(moduleName) and "on" or "off") .. " on this character", 1, 0.8, 0)
                    GameTooltip:AddLine("Click to turn it " .. (ModuleOn(moduleName) and "off." or "on."), 0.8, 0.8, 0.8)
                    if info.toggleNote then GameTooltip:AddLine(info.toggleNote, 0.8, 0.8, 0.8, true) end
                    GameTooltip:Show()
                end)
                sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
                card.switch = sw
                leftmost = sw
            end

            -- Text column stops short of the controls; long text truncates
            -- rather than running underneath them
            card.textReserve = 50 + (8 + 55) + 6
                + (card.toolsBtn and 27 or 0) + (card.switch and 26 or 0)
            local textWidth = width - card.textReserve

            local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleText:SetPoint("TOPLEFT", 50, -6)
            titleText:SetWidth(textWidth)
            titleText:SetJustifyH("LEFT")
            titleText:SetWordWrap(false)
            titleText:SetText("|cFF" .. ColorHex(info.color) .. info.title .. "|r")

            local descText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            descText:SetPoint("TOPLEFT", 50, -20)
            descText:SetWidth(textWidth)
            descText:SetJustifyH("LEFT")
            descText:SetWordWrap(false)
            descText:SetText(info.desc)

            local statusText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            statusText:SetPoint("TOPLEFT", 50, -34)
            statusText:SetWidth(textWidth)
            statusText:SetJustifyH("LEFT")
            statusText:SetWordWrap(false)
            statusText:SetText("|cFF888888Loading...|r")
            card.statusText = statusText

            -- Hover explains the card; right-click opens its tools
            card:EnableMouse(true)
            card:SetScript("OnEnter", ShowCardTooltip)
            card:SetScript("OnLeave", function() GameTooltip:Hide() end)
            card:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" then ShowToolsMenu(info, self.toolsBtn or self) end
            end)

            dashboard.moduleCards[moduleName] = card
            card.titleText, card.descText = titleText, descText
        end
    end

    self:LayoutCards()
    self:UpdateDashboard()
end

-- Hide (or show again) the cards of modules that are off on this character
function WM:SetHideInactive(v)
    self:CharState().hideInactive = v and true or false
    if dashboard then
        if dashboard.hideInactiveBtn then dashboard.hideInactiveBtn:Refresh() end
        self:LayoutCards()
        self:UpdateDashboard()
    end
end

function WM:UpdateDashboard()
    if not dashboard or not dashboard:IsShown() then return end
    -- A switch turned off with inactive modules hidden: its card goes
    if self:HideInactive() then self:LayoutCards() end

    for moduleName, card in pairs(dashboard.moduleCards) do
        local module = self.modules[moduleName]
        if module and not WM:IsModuleOn(moduleName) then
            card.statusText:SetText(WM:ShouldRun(moduleName)
                and "|cFF888888Off here, still saving this character for your others|r"
                or "|cFF888888Off on this character|r")
        elseif module and module.GetQuickStatus then
            local ok, status = pcall(module.GetQuickStatus, module)
            card.statusText:SetText(ok and status or "|cFFFF6666Status unavailable|r")
        else
            card.statusText:SetText("|cFF888888Module not loaded|r")
        end
        if card.switch then
            local on = ModuleOn(moduleName)
            card.switch:SetChecked(on)
            card.icon:SetDesaturated(not on)
        end
    end
end

-- A small page under the game's Options > AddOns, so the addon can be found
-- without knowing its slash command. Uses the Settings API where the client
-- has it, the older InterfaceOptions call otherwise.
function WM:RegisterOptionsCategory()
    if self.optionsCategory then return end
    local f = CreateFrame("Frame")
    f.name = "Watching Machine"

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Watching Machine  |cFF888888v" .. self.version .. "|r")

    local desc = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Every module is on the dashboard: switch modules on and off, open their"
        .. " settings, and hover a card to see what it does. Also: /wmachine, or the minimap button.")

    local function CloseOptions()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    end

    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    open:SetText("Open Dashboard")
    open:SetScript("OnClick", function()
        CloseOptions()
        if not (dashboard and dashboard:IsShown()) then WM:ToggleDashboard() end
    end)

    local settings = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    settings:SetSize(160, 24)
    settings:SetPoint("LEFT", open, "RIGHT", 8, 0)
    settings:SetText("Theme & Minimap")
    settings:SetScript("OnClick", function()
        CloseOptions()
        WM:ToggleSettings()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(f)
        self.optionsCategory = f
    end
end

function WM:ToggleDashboard()
    if not dashboard then
        self:CreateDashboard()
    end
    
    if not dashboard then
        return
    end
    
    if dashboard:IsShown() then
        dashboard:Hide()
    else
        dashboard:Show()
        self:UpdateDashboard()
        self:UpdateMinimapButtonText()
    end
end

-- ============================================
-- SETTINGS PANEL
-- ============================================

local settingsFrame = nil

function WM:CreateSettingsPanel()
    if settingsFrame then return settingsFrame end

    local panel = self.UI:CreatePanel({
        name = "WM_SettingsFrame",
        title = "Watching Machine Settings",
        width = 320,
        strata = "DIALOG",
    })
    local L = panel.layout

    local themes = {}
    for _, themeName in ipairs(self.THEME_LIST) do
        themes[#themes + 1] = { value = themeName, text = themeName }
    end
    L:Dropdown({
        name = "WM_SettingsThemeDropdown",
        label = "UI Theme:",
        width = 140,
        options = themes,
        get = function() return WM:GetThemeName() end,
        set = function(v)
            WatchingMachineDB.theme = v
            WM:OnThemeChanged()
        end,
        tooltip = { "UI Theme", "Default: Blizzard dialog borders. ElvUI: flat dark panels with pixel"
            .. " borders, to sit with ElvUI or Tukui. Applied straight away." },
    })
    L:Note("Applies to the dashboard, every module window, ArmorySnap and the debuff tracker."
        .. " On-screen warning frames keep their own colours.")
    L:Checkbox({
        label = "Verbose chat (show sync/diagnostic messages)",
        get = function() return WatchingMachineDB and WatchingMachineDB.verboseChat end,
        set = function(v)
            if WatchingMachineDB then WatchingMachineDB.verboseChat = v end
        end,
        tooltip = { "Verbose Chat Mode", "Shows low-priority messages like guild sync status, leaderboard"
            .. " updates, roster refreshes, and other backend activity. Useful for diagnostics."
            .. " Off by default to reduce chat noise." },
    })
    L:Checkbox({
        label = "Watching Machine button in the game menu (Esc)",
        get = function() return not (WatchingMachineDB and WatchingMachineDB.gameMenuButton == false) end,
        set = function(v)
            if WatchingMachineDB then WatchingMachineDB.gameMenuButton = v and true or false end
        end,
        tooltip = { "Game Menu Button", "Adds a Watching Machine button above Log Out in the menu"
            .. " Escape opens, like ElvUI's. Click it to open the dashboard. Takes effect the next"
            .. " time the menu opens; turned off, the addon doesn't touch the menu (after a /reload)." },
    })
    L:Row(20):Text({
        font = "GameFontNormalSmall",
        text = function() return "Active: |cFF00FF00" .. WM:GetThemeName() .. "|r" end,
    }, 12)
    if self.Setup and self.Setup.ForgetControls then self.Setup:ForgetControls(L, panel) end

    settingsFrame = panel:Finish()
    return settingsFrame
end

function WM:OnThemeChanged()
    local themeName = self:GetThemeName()
    self:Print("Theme changed to: |cFFFFCC00" .. themeName .. "|r")

    -- Re-skin all registered frames: panel backdrops (dashboard and settings
    -- included), dashboard cards and theme-keyed text. Nothing needs
    -- rebuilding; the settings panel just re-reads its controls.
    self:ReskinAll()
    if settingsFrame and settingsFrame:IsShown() then settingsFrame:Refresh() end

    -- Modules with their own theme-dependent styling (Debuff Tracker's
    -- display, ArmorySnap's paper doll) restyle themselves
    for name, module in pairs(self.modules) do
        if module.ApplyTheme then
            module:ApplyTheme()
        end
    end
end

function WM:ToggleSettings()
    local frame = self:CreateSettingsPanel()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function WM:ShowHelp()
    self:Print("=== Watching Machine Commands ===")
    print("|cFFFFFF00/wmachine|r - Toggle dashboard")
    print("|cFFFFFF00/wmachine setup|r - Run the setup (again) for this character, keeping what's on (setup quick / setup guided / setup new for what's new; also /wmachine resetup)")
    print("|cFFFFFF00/wmachine logger|r - Open Auto Logger")
    print("|cFFFFFF00/wmachine keyword|r - Open Keyword Monitor")
    print("|cFFFFFF00/wmachine filter|r - Open Chat Filter (hide spam phrases; applied before Keyword Monitor)")
    print("|cFFFFFF00/wmachine mail|r - Open Mail & Trade Logger")
    print("|cFFFFFF00/wmachine services|r - Open Services Parser")
    print("|cFFFFFF00/wmachine wcl|r - Open Whisper Logs (WCL Lookup)")
    print("|cFFFFFF00/wmachine ginvite|r - Open Guild Invite")
    print("|cFFFFFF00/wmachine debuff|r - Open Debuff Tracker settings")
    print("|cFFFFFF00/wmachine pvp|r - Open PvP Enemy Tracker")
    print("|cFFFFFF00/wmachine recruit|r - Open Recruiting Tool")
    print("|cFFFFFF00/wmachine buffcheck|r - Open Buff Check settings")
    print("|cFFFFFF00/wmachine armory|r - Open ArmorySnap gear browser (also /as)")
    print("|cFFFFFF00/as snap [label]|r, |cFFFFFF00list|r, |cFFFFFF00delete <name>|r, |cFFFFFF00group|r, |cFFFFFF00auto|r, |cFFFFFF00status|r, |cFFFFFF00reset|r - ArmorySnap snapshots and scanner")
    print("|cFFFFFF00/wmachine range|r - Open Aura Range alert settings")
    print("|cFFFFFF00/wmachine exclude|r - Stop the debuff tracker treating your target as a boss")
    print("|cFFFFFF00/wmachine unexclude|r - Undo an exclusion for your target")
    print("|cFFFFFF00/wmachine exclusions|r - List excluded NPCs")
    print("|cFFFFFF00/wmachine clearexclusions|r - Remove every exclusion")
    print("|cFFFFFF00/wmachine whyboss|r - Explain how the tracker sees your target")
    print("|cFFFFFF00/wmachine shear|r - Illidan Shear monitor status and tallies")
    print("|cFFFFFF00/wmachine shear on|off|r - Toggle the Shear monitor")
    print("|cFFFFFF00/wmachine encounters|r - Debuff Tracker settings, opened at Encounter Callouts")
    print("|cFFFFFF00/wmachine srcheck|r - Show your equipped shadow resist gear")
    print("|cFFFFFF00/wmachine srraid|r - List raiders still in shadow resist gear")
    print("|cFFFFFF00/wmachine class|r - Open Class Tools for your class")
    print("|cFFFFFF00/wmachine soulstone|r - Soulstone timers in your group (warlock)")
    print("|cFFFFFF00/wmachine consumes|r - What the general raid checks see")
    print("|cFFFFFF00/wmachine portals|r - List your teleport/portal spells (mage)")
    print("|cFFFFFF00/wmachine totems|r - Edit your totem sets (shaman)")
    print("|cFFFFFF00/wmachine instances|r - Instance log and lockouts")
    print("|cFFFFFF00/wmachine lockouts|r - Print your instance lockouts")
    print("|cFFFFFF00/wmachine bgs|r - Battleground and arena log")
    print("|cFFFFFF00/wmachine timers|r - World Timers (layers, Terokkar, dailies, DMF)")
    print("|cFFFFFF00/wmachine loot|r - Loot Browser (what every dungeon and raid boss drops)")
    print("|cFFFFFF00/wmachine gtfo|r - Hazard Alerts (gtfo test / mute <spell ID> / unmute <spell ID>)")
    print("|cFFFFFF00/wmachine gear|r - Gear Sets (gear equip <name> / undo / list)")
    print("|cFFFFFF00/wmachine ogri|r - Ogri'la Helper: remembers the Apexis Relic sequence (ogri options / clear)")
    print("|cFFFFFF00/wmachine move|r - Frame Mover: move and resize the game's windows (move reset puts them all back)")
    print("|cFFFFFF00/wmachine crits|r - Crit Tracker: your best hits, crits and heals")
    print("|cFFFFFF00/wmachine attune|r - Attunements: raid attunements and keys for each character")
    print("|cFFFFFF00/wmachine gs|r - GearScore for your group (gs unlock / lock / reset / report)")
    print("|cFFFFFF00/wmachine wb [guild|party|raid]|r - Print the world timers, or send them to a channel")
    print("|cFFFFFF00/wmachine alts|r - Your Characters (gold, rested XP, ...)")
    print("|cFFFFFF00/wmachine swing|r - Show the swing timer for 10s to move or resize it")
    print("|cFFFFFF00/wmachine swing reset|r - Swing timer back to the default place and size")
    print("|cFFFFFF00/wmachine whybuff|r - Show which buff checks your target's auras match")
    print("|cFFFFFF00/wmachine settings|r - Open addon settings (theme)")
    print("|cFFFFFF00/wmachine status|r - One-line status for every module")
    print("|cFFFFFF00/wmachine minimap|r - Toggle minimap button")
    print("|cFFFFFF00/wmachine resetminimap|r - Reset button position")
    print("|cFFFFFF00/wmachine debug|r - Show debug info")
    print("|cFFFFFF00/wmachine errors|r - Show captured error log")
    print("|cFFFFFF00/wmachine clearerrors|r - Clear error log")
    print("|cFFFFFF00/wmachine logoutcheck|r - Can't log out? Shows what the game blocked and what to try")
    print("|cFFFFFF00/wmachine menubutton on|off|r - The Watching Machine button in the Escape menu")
    print("|cFFFFFF00/wmachine help|r - Show this help")
end

-- ============================================
-- SLASH COMMANDS
-- ============================================

SLASH_WATCHINGMACHINE1 = "/wmachine"
SLASH_WATCHINGMACHINE2 = "/watchingmachine"

SlashCmdList["WATCHINGMACHINE"] = function(msg)
    msg = msg or ""
    local cmd = strtrim(msg:lower())
    
    -- Debug command
    if cmd == "debug" then
        WM:Print("=== Debug Info ===")
        WM:Print("Version: " .. WM.version)
        WM:Print("IsInGuild: " .. tostring(IsInGuild()))
        local guildName, rankName, rankIndex = GetGuildInfo("player")
        WM:Print("GuildInfo: name='" .. tostring(guildName) .. "' rank='" .. tostring(rankName) .. "' index=" .. tostring(rankIndex))
        WM:Print("Verbose: " .. tostring(WatchingMachineDB and WatchingMachineDB.verboseChat))
        return
    end
    
    -- Error log commands
    if cmd == "errors" or cmd == "errorlog" or cmd == "err" then
        local log = WatchingMachineDB and WatchingMachineDB.errorLog or WM._errorLog
        if not log or #log == 0 then
            WM:Print("No errors captured. If you're seeing errors, do /reload then run this again.")
        else
            WM:Print("=== Error Log (" .. #log .. " entries) ===")
            local start = math.max(1, #log - 19)
            for i = start, #log do
                print("|cFFFF6666[" .. i .. "]|r " .. log[i]:gsub("\n", " | "))
            end
            if #log > 20 then
                WM:Print("Showing last 20 of " .. #log .. ". Full log in SavedVariables.")
            end
            WM:Print("Full log: WTF/Account/YOUR_ACCOUNT/SavedVariables/WatchingMachine.lua -> errorLog table")
        end
        return
    end
    
    if cmd == "clearerrors" or cmd == "clearerr" then
        if WatchingMachineDB then
            WatchingMachineDB.errorLog = {}
            WM._errorLog = WatchingMachineDB.errorLog
        end
        WM:Print("Error log cleared.")
        return
    end
    
    if cmd == "" then
        WM:ToggleDashboard()
        
    elseif cmd == "logger" or cmd == "autolog" or cmd == "log" then
        local module = WM:UsableModule("AutoLogger")
        if module and module.OpenSettings then
            module:OpenSettings()
        end
        
    elseif cmd == "keyword" or cmd == "km" or cmd == "keywords" then
        local module = WM:UsableModule("KeywordMonitor")
        if module and module.ToggleUI then
            module:ToggleUI()
        end
        
    elseif cmd == "filter" or cmd == "chatfilter" or cmd == "cf" then
        local module = WM:UsableModule("ChatFilter")
        if module and module.ToggleUI then
            module:ToggleUI()
        end

    elseif cmd == "mail" or cmd == "ml" or cmd == "trade" then
        local module = WM:UsableModule("MailLogger")
        if module and module.ToggleUI then
            module:ToggleUI()
        end
        
    elseif cmd == "services" or cmd == "sp" or cmd == "boost" or cmd == "boosts" then
        local module = WM:UsableModule("ServicesParser")
        if module and module.ToggleUI then
            module:ToggleUI()
        end
        
    elseif cmd == "recruit" or cmd == "recruiter" or cmd == "guild" then
        local module = WM:UsableModule("Recruiter")
        if module and module.ToggleUI then
            module:ToggleUI()
        end
        
    elseif cmd == "whisper" or cmd == "whispers" or cmd == "wcl" or cmd == "logs" then
        local module = WM:UsableModule("WhisperLogs")
        if module and module.Toggle then
            module:Toggle()
        end
        
    elseif cmd == "ginvite" or cmd == "guildinvite" or cmd == "autoinv" then
        local module = WM:UsableModule("GuildInvite")
        if module and module.Toggle then
            module:Toggle()
        end
        
    elseif cmd == "debuff" or cmd == "debuffs" or cmd == "debufftracker" then
        local module = WM:UsableModule("DebuffTracker")
        if module and module.Toggle then
            module:Toggle()
        end
        
    elseif cmd == "pvp" or cmd == "enemies" or cmd == "pvptracker" or cmd == "kos" then
        local module = WM:UsableModule("PvPTracker")
        if module and module.Toggle then
            module:Toggle()
        end

    elseif cmd == "buffcheck" or cmd == "buffs" or cmd == "bc" then
        local module = WM:UsableModule("BuffCheck")
        if module and module.Toggle then
            module:Toggle()
        end

    elseif cmd == "armory" or cmd == "armorysnap" or cmd == "snap" then
        local module = WM:UsableModule("ArmorySnap")
        if module and module.Toggle then
            module:Toggle()
        end

    elseif cmd == "soulstone" or cmd == "soulstones" or cmd == "ss" then
        local module = WM:UsableModule("ClassWarlock")
        if module and module.ReportSoulstones then
            module:ReportSoulstones()
        end

    elseif cmd == "consumes" or cmd == "consumables" then
        local module = WM:UsableModule("ClassGeneral")
        if module and module.Explain then
            module:Explain()
        end

    elseif cmd == "portals" or cmd == "teleports" then
        local module = WM:UsableModule("ClassMage")
        if module and module.ReportSpells then
            module:ReportSpells()
        end

    elseif cmd == "instances" or cmd == "instance" or cmd == "it" then
        local module = WM:UsableModule("InstanceTracker")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "timers" or cmd == "worldtimers" or cmd == "dmf" or cmd == "layer" then
        local module = WM:UsableModule("WorldTimers")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "wb" or cmd:match("^wb ") then
        local module = WM:UsableModule("WorldTimers")
        if module and module.Report then module:Report(cmd:match("^wb (%a+)")) end

    elseif cmd == "gs" or cmd == "gearscore" or cmd:match("^gs ") then
        local module = WM:UsableModule("GearScore")
        if module and module.Command then module:Command(cmd:match("^gs (.+)$")) end

    elseif cmd == "attune" or cmd == "attunements" or cmd == "att" then
        local module = WM:UsableModule("Attunements")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "gtfo" or cmd == "hazards" or cmd:match("^gtfo ") then
        local module = WM:UsableModule("Hazards")
        if module and module.Command then module:Command(cmd:match("^gtfo (.+)$")) end

    elseif cmd == "gear" or cmd == "sets" or cmd == "itemrack" or cmd:match("^gear ") then
        local module = WM:UsableModule("GearSets")
        if module and module.Command then module:Command(strtrim(msg):match("^%S+%s+(.+)$")) end

    elseif cmd == "ogri" or cmd == "relic" or cmd == "ogrila" or cmd:match("^ogri ") then
        local module = WM:UsableModule("Ogrila")
        if module and module.Command then module:Command(cmd:match("^ogri (.+)$")) end

    elseif cmd == "move" or cmd == "mover" or cmd == "frames" or cmd:match("^move ") then
        local module = WM:UsableModule("FrameMover")
        if module and module.Command then module:Command(cmd:match("^move (.+)$")) end

    elseif cmd == "crits" or cmd == "crit" or cmd == "ct" then
        local module = WM:UsableModule("Crits")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "loot" or cmd == "atlas" or cmd == "al" then
        local module = WM:UsableModule("LootBrowser")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "bgs" or cmd == "arenas" or cmd == "pvplog" then
        local module = WM:UsableModule("PvPLog")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "alts" or cmd == "characters" or cmd == "chars" then
        local module = WM:UsableModule("AltTracker")
        if module and module.Toggle then module:Toggle() end

    elseif cmd == "lockouts" or cmd == "lockout" then
        local module = WM:UsableModule("InstanceTracker")
        if module and module.PrintLockouts then module:PrintLockouts() end

    elseif cmd == "swing reset" then
        local module = WM:UsableModule("SwingTimer")
        if module and module.ResetPosition then
            module:ResetPosition()
            WM:Print("Swing timer moved back to the centre at its default size.")
        end

    elseif cmd == "swing" or cmd == "swingtimer" then
        local module = WM:UsableModule("SwingTimer")
        if module and module.Test then
            module:Test()
        end

    elseif cmd == "totems" or cmd == "totem" then
        local module = WM:UsableModule("ClassShaman")
        if module and module.ToggleEditor then
            module:ToggleEditor()
        end

    elseif cmd == "class" or cmd == "classes" or cmd == "classtools" then
        local module = WM:UsableModule("ClassTools")
        if module and module.Toggle then
            module:Toggle()
        end

    elseif cmd == "encounters" or cmd == "callouts" then
        local module = WM:UsableModule("DebuffTracker")
        if module and module.ToggleEncounterUI then
            module:ToggleEncounterUI()
        end

    elseif cmd == "srcheck" or cmd == "sr" or cmd == "resist" then
        local module = WM:UsableModule("DebuffTracker")
        if module and module.ExplainShadowResist then
            module:ExplainShadowResist()
        end

    elseif cmd == "srraid" or cmd == "srcheck raid" or cmd == "sr raid" then
        local module = WM:UsableModule("DebuffTracker")
        if module and module.StartRaidShadowResistScan then
            module:StartRaidShadowResistScan()
        end

    elseif cmd == "shear" or cmd == "shear on" or cmd == "shear off"
        or cmd == "shearstats" then
        local module = WM:UsableModule("DebuffTracker")
        if not module then return end
        if cmd == "shear on" or cmd == "shear off" then
            local want = (cmd == "shear on")
            if DebuffTrackerDB and DebuffTrackerDB.shearMonitor ~= want then
                module:ToggleShearMonitor()
            else
                WM:Print("Shear monitor already " .. (want and "on" or "off"))
            end
        else
            module:ShowShearStatus()
        end

    elseif cmd == "whybuff" or cmd == "buffdebug" then
        local module = WM:UsableModule("BuffCheck")
        if module and module.ExplainUnit then
            -- Inspect your target if you have one, otherwise yourself
            module:ExplainUnit(UnitExists("target") and "target" or "player")
        end

    elseif cmd == "exclude" or cmd == "unexclude" or cmd == "exclusions"
        or cmd == "excludelist" or cmd == "clearexclusions" or cmd == "whyboss" then
        local module = WM:UsableModule("DebuffTracker")
        if not module then return end
        if cmd == "exclude" then
            module:ExcludeTarget()
        elseif cmd == "unexclude" then
            module:UnexcludeTarget()
        elseif cmd == "clearexclusions" then
            module:ClearExclusions()
        elseif cmd == "whyboss" then
            module:ExplainTarget()
        else
            module:ListExclusions()
        end

    elseif cmd == "range" or cmd == "aurarange" or cmd == "aura" then
        local module = WM:UsableModule("AuraRange")
        if module and module.Toggle then
            module:Toggle()
        end

    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        WM:ToggleSettings()
        
    elseif cmd == "minimap" then
        WM:ToggleMinimapButton()
        
    elseif cmd == "resetminimap" or cmd == "resetbutton" then
        -- Clear saved position to reset to default
        if WatchingMachineDB then
            WatchingMachineDB.minimapX = nil
            WatchingMachineDB.minimapY = nil
            WatchingMachineDB.minimapPos = nil
        end
        if minimapButton then
            minimapButton:ClearAllPoints()
            minimapButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -120)
        end
        WM:Print("Minimap button position reset. Drag to reposition.")
        
    elseif cmd == "setup" or cmd == "setup quick" or cmd == "setup guided" or cmd == "wizard"
        or cmd == "resetup" or cmd == "rerun" or cmd == "setup again" or cmd == "setup new" or cmd == "whatsnew" then
        if WM.Setup then
            if cmd == "setup new" or cmd == "whatsnew" then
                local new = WM.Setup:NewModules()
                WM.Setup:ShowWhatsNew(#new > 0 and new or WM:CharState().lastNew)
            elseif cmd == "setup quick" then WM.Setup:OpenQuick()
            elseif cmd == "setup guided" then WM.Setup:OpenGuided()
            else WM.Setup:ShowWelcome() end
        end

    elseif cmd == "logoutcheck" or cmd == "logout check" or cmd == "diag" then
        if WM.Diagnostics then WM.Diagnostics:Report() end

    elseif cmd == "menubutton on" or cmd == "menubutton off" then
        if WM.Diagnostics then WM.Diagnostics:SetMenuButton(cmd == "menubutton on") end

    elseif cmd == "help" then
        WM:ShowHelp()
    elseif cmd == "status" then
        WM:Print("=== Module Status ===")
        for name, module in pairs(WM.modules) do
            if not WM:IsModuleOn(name) then
                print("  " .. name .. ": |cFF888888off on this character|r")
            elseif module.GetQuickStatus then
                print("  " .. name .. ": " .. module:GetQuickStatus())
            else
                print("  " .. name .. ": |cFF888888Loaded|r")
            end
        end
        
    else
        WM:Print("Unknown command. Type /wmachine help for available commands.")
    end
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

local function PerformSecurityCheck()
    local result = WM:CheckGuildSecurity()
    
    if result == nil then
        -- Guild info not loaded yet, will retry
        return false
    end
    
    if result then
        WM:OnSecurityCheckPassed()
    else
        WM:OnSecurityCheckFailed()
    end
    return true
end

local retryCount = 0
local maxRetries = 5

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AddonName then
        InitCoreDB()
        -- Per-character settings, then this character's module switches
        if WM.Profiles then WM.Profiles:Load() end
        if WM.InitCharacter then WM:InitCharacter() end
        
    elseif event == "PLAYER_LOGIN" then
        -- Hide dashboard if it exists from previous session
        if dashboard then
            dashboard:Hide()
        end
        
        -- Create or reuse minimap button
        CreateMinimapButton()

        -- Entry in the game's own AddOns options list
        WM:RegisterOptionsCategory()
        
        -- Hook Minimap OnShow to restore our button when minimap becomes visible
        if Minimap and not Minimap.wmHooked then
            Minimap:HookScript("OnShow", function()
                RunAfter(0.1, function()
                    WM:RestoreMinimapButton()
                end)
            end)
            Minimap.wmHooked = true
        end
        
        -- Request guild roster for modules that need it
        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
        end
        
        -- Initialize immediately (no guild check needed)
        RunAfter(1, function()
            PerformSecurityCheck()
        end)
        
    elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        -- Guild roster updated (modules may need this data)
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Restore minimap button after zone change with a small delay
        RunAfter(0.5, function()
            WM:RestoreMinimapButton()
        end)
        WM:RestoreMinimapButton()
        
    elseif event == "PLAYER_LEAVING_WORLD" then
        -- Hide dashboard on logout/character switch
        if dashboard then
            dashboard:Hide()
        end
    end
end)
