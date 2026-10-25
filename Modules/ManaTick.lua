-- Watching Machine: Mana Tick
-- A white spark that slides left to right across your health bar (or mana
-- bar, or a small bar of its own), reaching the right edge as your next
-- mana tick lands. TBC regenerates mana in ticks every 2 seconds, so you
-- can time a cast to finish just after a tick, or stop casting just long
-- enough to catch one.
--
-- How the ticks are found: the server ticks every 2 seconds on its own
-- clock, so the spark locks onto the mana gains you get. A gain that fits
-- the 2 second rhythm keeps it in step; one that doesn't (a potion,
-- Innervate, a judgement) is ignored, unless another gain comes exactly
-- 2 seconds after it, which means the rhythm itself moved.
--
-- The five-second rule: spending mana on a spell stops spirit regeneration
-- for 5 seconds. An orange spark crosses the bar over those 5 seconds.
--
-- The spark sits on a frame of our own laid over the bar: nothing is
-- written into the game's unit frames.

local AddonName, WM = ...
local MT = {}
WM:RegisterModule("ManaTick", MT)
WM.ManaTick = MT

MT.version = "3.51"

local TICK = 2              -- seconds between mana ticks
local SLACK = 0.25          -- how far off the rhythm a tick may land (server and frame timing)
local FSR = 5               -- the five-second rule
local CAST_WINDOW = 0.5     -- a mana drop this close to your cast was spent on it
local OWN_W, OWN_H = 160, 10
MT.TICK, MT.FSR = TICK, FSR

-- Where the spark goes: the first of these frames that exists ("A.B": the
-- child key B of frame A). Blizzard's player frame, then ElvUI's.
local HOSTS = {
    health = { "PlayerFrameHealthBar", "ElvUF_Player.Health" },
    mana = { "PlayerFrameManaBar", "ElvUF_Player.Power" },
}
MT.HOSTS = HOSTS

MT.WHERE_OPTIONS = {
    { value = "health", text = "Health bar" },
    { value = "mana", text = "Mana bar" },
    { value = "own", text = "Its own bar" },
}

local function DB()
    if type(ManaTickDB) ~= "table" then ManaTickDB = {} end
    local db = ManaTickDB
    if db.where ~= "health" and db.where ~= "mana" and db.where ~= "own" then db.where = "health" end
    return db
end
MT.DB = DB

local function Tools() return WM.modules.ClassTools end
local function Enabled(key)
    local CT = Tools()
    return CT and CT:IsEnabled("GENERAL", key) and true or false
end
local function On() return WM:IsModuleOn("ManaTick") end

-- ============================================
-- THE TICKS
-- ============================================
-- lastTick: GetTime() of the last tick seen (nil: not found yet)
-- candidate: an off-rhythm gain that may be the start of a new rhythm
-- fsrStart: when the five-second rule last started (nil: not in it)

MT.lastTick, MT.candidate, MT.fsrStart = nil, nil, nil
local lastMana, lastDropAt, lastCastAt

local function Mana()
    if not UnitPower then return nil end
    return tonumber(UnitPower("player", 0))
end
local function MaxMana()
    if not UnitPowerMax then return 0 end
    return tonumber(UnitPowerMax("player", 0)) or 0
end

-- Does a gain at `now` fit the rhythm that started at `at`?
local function OnRhythm(at, now)
    local d = now - at
    if d < TICK - SLACK then return false end
    local k = math.floor(d / TICK + 0.5)
    return math.abs(d - k * TICK) <= SLACK
end

-- Mana went up at `now`
function MT:OnGain(now)
    if not self.lastTick then
        self.lastTick = now
    elseif OnRhythm(self.lastTick, now) then
        self.lastTick = now
        self.candidate = nil
    elseif self.candidate and OnRhythm(self.candidate, now) then
        -- Two off-rhythm gains 2 seconds apart: the rhythm moved
        self.lastTick, self.candidate = now, nil
    else
        -- Off the rhythm: a potion or the like, or the start of a new rhythm
        self.candidate = now
    end
end

-- Mana went down at `now`: spent on a spell starts the five-second rule
function MT:OnDrop(now)
    lastDropAt = now
    if lastCastAt and now - lastCastAt <= CAST_WINDOW then self.fsrStart = now end
end

function MT:OnCast(now)
    lastCastAt = now
    if lastDropAt and now - lastDropAt <= CAST_WINDOW then self.fsrStart = lastDropAt end
end

function MT:OnPower(now)
    local cur = Mana()
    if not cur then return end
    if lastMana then
        if cur > lastMana then self:OnGain(now)
        elseif cur < lastMana then self:OnDrop(now) end
    end
    lastMana = cur
end

-- How far through the current 2 seconds we are, 0 to 1 (nil: not known)
function MT:TickFraction(now)
    if not self.lastTick then return nil end
    local d = (now - self.lastTick) % TICK
    return d / TICK
end

-- How far through the five-second rule, 0 to 1 (nil: not in it)
function MT:FSRFraction(now)
    if not self.fsrStart then return nil end
    local d = now - self.fsrStart
    if d < 0 or d >= FSR then return nil end
    return d / FSR
end

function MT:Reset()
    self.lastTick, self.candidate, self.fsrStart = nil, nil, nil
    lastMana, lastDropAt, lastCastAt = nil, nil, nil
end

-- ============================================
-- DISPLAY
-- ============================================

local overlay, ownBar, ticker
local testUntil = 0

local function Resolve(name)
    local obj
    for key in string.gmatch(name, "[^%.]+") do
        if obj == nil then obj = _G[key] else obj = type(obj) == "table" and rawget(obj, key) or nil end
        if obj == nil then return nil end
    end
    if type(obj) == "table" and type(obj.GetWidth) == "function" then return obj end
end

-- The bar the spark goes on now (and whether it's our own)
function MT:Host()
    local where = DB().where
    if where ~= "own" then
        for _, name in ipairs(HOSTS[where] or {}) do
            local f = Resolve(name)
            if f then return f, false end
        end
    end
    return self:OwnBar(), true
end

local function Spark(parent, r, g, b)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(r, g, b, 0.95)
    t:SetWidth(2)
    t:Hide()
    return t
end

function MT:CreateOverlay()
    if overlay then return overlay end
    local f = CreateFrame("Frame", "WM_ManaTickOverlay", UIParent)
    f.tick = Spark(f, 1, 1, 1)
    f.fsr = Spark(f, 1, 0.55, 0.1)
    f:Hide()
    overlay = f
    self.overlay = f
    return f
end

-- The small bar of its own: Shift-drag to move it
function MT:OwnBar()
    if ownBar then return ownBar end
    local db = DB()
    local f = CreateFrame("Frame", "WM_ManaTickBar", UIParent)
    f:SetSize(OWN_W, OWN_H)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    if db.x and db.y then f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, -220) end
    f:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown and IsShiftKeyDown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if x then DB().x, DB().y = x, y end
    end)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.1, 0.3, 0.7)
    f:Hide()
    ownBar = f
    self.ownBar = f
    return f
end

function MT:ResetPosition()
    local db = DB()
    db.x, db.y = nil, nil
    if ownBar then
        ownBar:ClearAllPoints()
        ownBar:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
end

-- Should the spark show at all right now?
function MT:Wanted(now)
    if testUntil > now then return true end
    if not On() or not Enabled("manaTick") then return false end
    local max = MaxMana()
    if max <= 0 then return false end
    -- Full mana and out of combat: nothing to wait for
    if Enabled("manaTickHideFull") and (Mana() or 0) >= max and not self:FSRFraction(now)
        and not (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end
    return true
end

local function Place(spark, host, frac)
    if not frac then spark:Hide() return end
    local w = host:GetWidth() or 0
    spark:ClearAllPoints()
    spark:SetPoint("TOP", host, "TOPLEFT", frac * w, 0)
    spark:SetPoint("BOTTOM", host, "BOTTOMLEFT", frac * w, 0)
    spark:Show()
end

function MT:Draw(now)
    now = now or GetTime()
    local f = self:CreateOverlay()
    if not self:Wanted(now) then
        f:Hide()
        if ownBar then ownBar:Hide() end
        return
    end
    local host, own = self:Host()
    if own then host:Show() elseif ownBar then ownBar:Hide() end
    if not own and host.IsVisible and not host:IsVisible() then f:Hide() return end
    -- Lay the overlay over the bar, just above it
    if f.host ~= host then
        f:ClearAllPoints()
        f:SetAllPoints(host)
        if host.GetFrameStrata then f:SetFrameStrata(host:GetFrameStrata() or "MEDIUM") end
        if host.GetFrameLevel then f:SetFrameLevel((host:GetFrameLevel() or 1) + 5) end
        f.host = host
    end
    local tickFrac = self:TickFraction(now)
    if testUntil > now and not tickFrac then tickFrac = (now % TICK) / TICK end
    Place(f.tick, f, tickFrac)
    Place(f.fsr, f, Enabled("manaTickFSR") and self:FSRFraction(now) or nil)
    f:Show()
end

-- /wmachine manatick: show it for 10 seconds (to find it, or move its own bar)
function MT:Test()
    testUntil = GetTime() + 10
    self:Draw()
    local own = select(2, self:Host())
    WM:ModulePrint("ManaTick", "Showing the mana tick spark for 10 seconds"
        .. (own and ". Shift-drag its bar to move it." or " on your " .. (DB().where == "mana" and "mana" or "health") .. " bar."))
end

function MT:EndTest() testUntil = 0 end

-- ============================================
-- OPTIONS (Class Tools > General; registered by ClassGeneral)
-- ============================================

function MT.RegisterOptions(tools)
    tools:RegisterFeature("GENERAL", {
        key = "manaTick", name = "Mana tick spark",
        desc = "A white spark slides across your health bar and reaches the end as your next mana tick (every 2 seconds) lands. For any class with mana. /wmachine manatick shows it.",
        default = true,
        onToggle = function() MT:Refresh() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "manaTickWhere", kind = "choice", name = "Mana tick spark on",
        options = MT.WHERE_OPTIONS, default = "health",
        desc = "Your player frame's health bar or mana bar (Blizzard's or ElvUI's), or a small bar of its own (Shift-drag to move it). Without a player frame it uses its own bar.",
        get = function() return DB().where end,
        set = function(v) DB().where = v; MT:Refresh() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "manaTickFSR", name = "Five-second rule spark",
        desc = "After you spend mana on a spell, an orange spark crosses the bar over the 5 seconds your spirit regeneration is stopped.",
        default = true,
        onToggle = function() MT:Refresh() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "manaTickHideFull", name = "Hide the mana tick spark at full mana",
        desc = "Out of combat with full mana there's nothing to wait for.",
        default = true,
        onToggle = function() MT:Refresh() end,
    })
end

function MT:Refresh()
    if overlay and On() then self:Draw() end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local EVENTS = { "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_ENTERING_WORLD",
    "UNIT_MAXPOWER" }

function MT:OnEvent(event, unit, powerType)
    local now = GetTime()
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        if unit == "player" and (powerType == nil or powerType == "MANA") then self:OnPower(now) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" then self:OnCast(now) end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_MAXPOWER" then
        if event == "PLAYER_ENTERING_WORLD" or unit == "player" then lastMana = Mana() end
    end
end

function MT:Initialize()
    DB()
    lastMana = Mana()
    self:CreateOverlay()
    WM:RegisterEvents(events, EVENTS)
    ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function()
        if not On() then return end
        MT:Draw()
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    if not On() then return end
    MT:OnEvent(event, ...)
end)

-- Turned off on this character (or Class Tools is): the spark goes and
-- nothing more is read
function MT:OnModuleOff()
    testUntil = 0
    self:Reset()
    if overlay then overlay:Hide() end
    if ownBar then ownBar:Hide() end
    if ticker then ticker:Hide() end
    events:UnregisterAllEvents()
end

function MT:OnModuleOn()
    if not ticker then return end   -- not started yet
    WM:RegisterEvents(events, EVENTS)
    ticker:Show()
    lastMana = Mana()
end
