-- Watching Machine: Swing Timer
-- A bar per hand showing time to your next melee swing (warriors, rogues,
-- Retribution paladins, Enhancement shamans), or to your next Auto Shot
-- (hunters). A spark line moves left to right; the fill changes colour as
-- the swing nears, and the end of each bar shows your latency.
--
-- How the timer is kept (TBC rules, the same as the established swing
-- timer addons):
--   * a swing (SWING_DAMAGE / SWING_MISSED, any miss type) restarts its hand
--   * Heroic Strike, Cleave, Maul and Raptor Strike replace the main-hand
--     swing, so they restart it
--   * finishing a spell with a cast time (Slam, Lightning Bolt, a heal)
--     restarts both hands; instants (Stormstrike, shocks) don't
--   * haste (Flurry, Bloodlust, drums) rescales the time left
--   * parrying an attack hastens your main hand: the time left drops by 40%
--     of your swing, but never below 20% of it
--   * a weapon swap restarts every hand
--   * starting to attack puts the off hand halfway through its swing if it
--     was past halfway. That is what the shaman sync macro uses
--   * extra attacks (Windfury) land with the swing that gave them, so they
--     don't restart the hand a second time
--
-- Shamans get a Windfury bar: Windfury Weapon's 3 second cooldown from its
-- last proc (the first proc in the combat log shows it). Shamans and
-- warriors see their Flurry charges on the main-hand bar.
--
-- Retribution paladins twisting seals get, on the main-hand bar, the point
-- of no return (a GCD before the swing), the twist window at its end, and
-- the seal they have up.
--
-- Weapon sync (Enhancement shamans): the off hand should land just after
-- the main hand. Windfury Weapon has a 3 second cooldown shared by both
-- hands, so the main hand should be the one that gets it, and two hits
-- close together share one Flurry charge. The usual sync macro is
--     /cleartarget
--     /targetlasttarget
--     /startattack
-- It stops and restarts your attack, which can only delay the off hand: to
-- half its swing from the press, if it was past halfway. So pressing it when
-- the main hand has (off-hand speed / 2 - lag) left lands the off hand
-- "lag" seconds after the main hand. The main-hand bar marks that moment,
-- moved earlier by your latency, and says "SYNC NOW" when it's time.
-- Sync only holds with equal weapon speeds.
--
-- Hunters: the Auto Shot bar is split into the time a Steady Shot is safe to
-- start, the part where a Steady Shot would delay (clip) the next shot, and
-- the final half-second wind-up where moving delays it.

local AddonName, WM = ...
local Swing = {}
WM:RegisterModule("SwingTimer", Swing)
WM.SwingTimer = Swing

Swing.version = "3.17"

local BAR_GAP = 3
-- Size: saved, set by dragging the corner grip (unlocked) or in Class Tools
local DEFAULT_W, DEFAULT_H = 220, 14
local MIN_W, MAX_W, MIN_H, MAX_H = 100, 600, 8, 40
Swing.SIZE_LIMITS = { MIN_W, MAX_W, MIN_H, MAX_H }
local WINDUP = 0.5          -- Auto Shot wind-up
local EXTRA_WINDOW = 0.04   -- an extra attack lands within this of its proc
local SYNC_WINDOW = 0.1     -- "SYNC NOW" this close to the mark
local GOOD_LAG = 0.4        -- off hand landing up to this after the main hand
local ICON = "Interface\\Icons\\INV_Sword_04"

-- ============================================
-- SPELLS
-- ============================================
-- Matched by English name and the client's name for the spell ID, so every
-- rank and localized clients work

local function NameSet(defs)
    local set = {}
    for _, d in ipairs(defs) do
        set[d[1]] = true
        if GetSpellInfo and d[2] then
            local ok, n = pcall(GetSpellInfo, d[2])
            if ok and type(n) == "string" then set[n] = true end
        end
    end
    return set
end

local NEXT_MELEE_DEFS = {
    { "Heroic Strike", 78 }, { "Cleave", 845 }, { "Maul", 6807 }, { "Raptor Strike", 2973 },
}
-- Cast-time spells that don't reset the swing
local NO_RESET_DEFS = {
    { "Steady Shot", 34120 }, { "Volley", 1510 }, { "Hurricane", 16914 },
    { "Drums of Battle", 35476 }, { "Drums of War", 35475 }, { "Drums of Restoration", 35478 },
    { "Drums of Speed", 35477 }, { "Drums of Panic", 35474 },
}
local NO_RESET_IDS = { [34120] = true, [35474] = true, [35475] = true, [35476] = true,
    [35477] = true, [35478] = true }
local AUTO_SHOT = 75
local AIMED_SHOT_DEFS = { { "Aimed Shot", 19434 } }
local STEADY_SHOT = 34120
-- Windfury Weapon's extra attacks, and the Flurry buff (shaman and warrior)
local WINDFURY_DEFS = { { "Windfury Attack", 25504 }, { "Windfury Weapon", 25505 } }
local FLURRY_DEFS = { { "Flurry", 16280 }, { "Flurry", 12970 } }
local WF_COOLDOWN = 3       -- Windfury Weapon, shared by both hands
-- Paladin seals (rank 1 IDs, for the name on localized clients); any rank
-- is matched by name or by the aura's spell ID
local SEAL_DEFS = {
    { "Seal of Command", 20375 }, { "Seal of Blood", 31892 }, { "Seal of the Martyr", 348700 },
    { "Seal of Righteousness", 21084 }, { "Seal of the Crusader", 21082 }, { "Seal of Wisdom", 20166 },
    { "Seal of Light", 20165 }, { "Seal of Justice", 20164 }, { "Seal of Vengeance", 31801 },
}
local SEAL_IDS = {}
for _, d in ipairs(SEAL_DEFS) do SEAL_IDS[d[2]] = true end
local GCD_BASE, GCD_MIN = 1.5, 1.0
local TWIST_DEFAULT = 0.4   -- the twist window: Seal of Command still lands this close to the swing

local nextMelee, noReset, aimedShot, windfury, flurry, seals

local function Names()
    if not nextMelee then
        nextMelee, noReset, aimedShot = NameSet(NEXT_MELEE_DEFS), NameSet(NO_RESET_DEFS), NameSet(AIMED_SHOT_DEFS)
        windfury, flurry, seals = NameSet(WINDFURY_DEFS), NameSet(FLURRY_DEFS), NameSet(SEAL_DEFS)
    end
end

local function SpellName(id)
    if not (GetSpellInfo and id) then return nil end
    local ok, n = pcall(GetSpellInfo, id)
    return ok and n or nil
end

-- ============================================
-- SETTINGS
-- ============================================

local function DB()
    if type(SwingTimerDB) ~= "table" then SwingTimerDB = {} end
    local db = SwingTimerDB
    if db.locked == nil then db.locked = false end
    if db.syncLag == nil then db.syncLag = 0.15 end
    if db.syncSound == nil then db.syncSound = "none" end
    if type(db.twistWindow) ~= "number" then db.twistWindow = TWIST_DEFAULT end
    if type(db.width) ~= "number" then db.width = DEFAULT_W end
    if type(db.barHeight) ~= "number" then db.barHeight = DEFAULT_H end
    db.width = math.max(MIN_W, math.min(MAX_W, math.floor(db.width + 0.5)))
    db.barHeight = math.max(MIN_H, math.min(MAX_H, math.floor(db.barHeight + 0.5)))
    return db
end
Swing.DB = DB

local BAR_W, BAR_H = DEFAULT_W, DEFAULT_H   -- the current size, from DB

local function Tools() return WM.modules.ClassTools end

local function Enabled(key)
    local CT = Tools()
    return CT and CT:IsEnabled("GENERAL", key)
end

-- A Shaman tab option (the weapon sync and Windfury options live there)
local function ShamanEnabled(key)
    local CT = Tools()
    return CT and CT:IsEnabled("SHAMAN", key) and true or false
end

local function PlayerClass()
    local _, c = UnitClass("player")
    return c
end

-- ============================================
-- WHO GETS A TIMER
-- ============================================

local function Knows(id)
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and v then return true end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, id)
        if ok and v then return true end
    end
    return false
end

-- Points spent in a talent tree (sum of ranks; GetTalentInfo's 5th return)
local function TreePoints(tab)
    local okN, count = pcall(GetNumTalents, tab)
    count = okN and tonumber(count) or 0
    local points = 0
    for i = 1, count do
        local ok, _, _, _, _, rank = pcall(GetTalentInfo, tab, i)
        if ok then points = points + (tonumber(rank) or 0) end
    end
    return points
end

-- True when this tree has more points than any other
local function MainTree(tab)
    local mine = TreePoints(tab)
    if mine == 0 then return false end
    for t = 1, 3 do
        if t ~= tab and TreePoints(t) >= mine then return false end
    end
    return true
end

-- "melee", "ranged", or nil
function Swing:Kind()
    local class = PlayerClass()
    if class == "HUNTER" then return "ranged" end
    if class == "WARRIOR" or class == "ROGUE" then return "melee" end
    if class == "PALADIN" then
        -- Crusader Strike is the 41-point talent; otherwise most points in Retribution
        if Knows(35395) or MainTree(3) then return "melee" end
    elseif class == "SHAMAN" then
        -- Stormstrike / Dual Wield, or most points in Enhancement
        if Knows(17364) or Knows(30798) or MainTree(2) then return "melee" end
    end
    if Enabled("swingAnyClass") then return "melee" end
    return nil
end

function Swing:IsShaman() return PlayerClass() == "SHAMAN" end

-- ============================================
-- TIMER STATE
-- ============================================
-- Each hand: speed (current, hasted) and expires (GetTime of the next swing)

local hands = { mh = {}, oh = {}, ranged = {} }
Swing.hands = hands
-- Windfury Weapon's cooldown: speed (3s) and expires, from its last proc
local wfCooldown = {}
Swing.wfCooldown = wfCooldown
Swing.flurry = 0            -- Flurry charges on you
local attacking, shooting = false, false
local casting           -- spell ID being cast
local extraPending, extraTs = 0, 0
local playerGUID
local testUntil = 0

local function MeleeSpeeds()
    if not UnitAttackSpeed then return nil end
    local mh, oh = UnitAttackSpeed("player")
    return tonumber(mh), tonumber(oh)
end

local function RangedSpeed()
    if not UnitRangedDamage then return nil end
    local s = UnitRangedDamage("player")
    s = tonumber(s)
    if s and s > 0 then return s end
end

local function Restart(key, now)
    local h = hands[key]
    local speed
    if key == "ranged" then speed = RangedSpeed()
    else
        local mh, oh = MeleeSpeeds()
        speed = (key == "mh") and mh or oh
    end
    if not speed or speed <= 0 then h.speed, h.expires = nil, nil return end
    h.speed, h.expires = speed, now + speed
end
Swing.Restart = Restart

-- Time left scales with the speed change
local function Rescale(h, newSpeed, now)
    if not newSpeed or newSpeed <= 0 then h.speed, h.expires = nil, nil return end
    if h.speed and h.expires and h.expires > now then
        h.expires = now + (h.expires - now) * newSpeed / h.speed
    end
    h.speed = newSpeed
end

function Swing:UpdateSpeeds(now)
    local mh, oh = MeleeSpeeds()
    Rescale(hands.mh, mh, now)
    Rescale(hands.oh, oh, now)
end

-- Parrying an attack: main hand time left -40% of speed, not below 20%
local function ParryHaste(h, now)
    if not (h.speed and h.expires) then return end
    local left, s = h.expires - now, h.speed
    if left > 0.2 * s then
        local offset = 0.4 * s
        if left - offset < 0.2 * s then offset = left - 0.2 * s end
        h.expires = h.expires - offset
    end
end
Swing.ParryHaste = ParryHaste

-- ============================================
-- EVENTS
-- ============================================

-- Combat log, as CombatLogGetCurrentEventInfo returns it
function Swing:OnCombatEvent(ts, sub, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
    local now = GetTime()
    playerGUID = playerGUID or (UnitGUID and UnitGUID("player"))
    if not playerGUID then return end
    Names()

    if srcGUID == playerGUID then
        if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
            local isOffHand
            if sub == "SWING_DAMAGE" then isOffHand = select(10, ...) else isOffHand = select(2, ...) end
            if not isOffHand and extraPending > 0 and math.abs((ts or 0) - extraTs) <= EXTRA_WINDOW then
                extraPending = extraPending - 1     -- the extra attack, not a new swing
                return
            end
            Restart(isOffHand and "oh" or "mh", now)
        elseif sub == "SPELL_EXTRA_ATTACKS" then
            extraPending = tonumber(select(4, ...)) or 1
            extraTs = ts or 0
            -- A Windfury proc starts its cooldown
            local spellId, spellName = ...
            if (spellName and (windfury[spellName] or spellName:find("Windfury", 1, true)))
                or (spellId and windfury[SpellName(spellId) or ""]) then
                wfCooldown.speed, wfCooldown.expires = WF_COOLDOWN, now + WF_COOLDOWN
                self.wfSeen = true
            end
        elseif sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED" then
            local spellId, spellName = ...
            if nextMelee[spellName] or (spellId and nextMelee[SpellName(spellId) or ""]) then
                Restart("mh", now)
            end
        end
    elseif dstGUID == playerGUID then
        -- You parried: your next main-hand swing comes sooner
        if (sub == "SWING_MISSED" and (...) == "PARRY")
            or (sub == "SPELL_MISSED" and select(4, ...) == "PARRY") then
            ParryHaste(hands.mh, now)
        end
    end
end

function Swing:OnEvent(event, ...)
    local now = GetTime()
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if CombatLogGetCurrentEventInfo then self:OnCombatEvent(CombatLogGetCurrentEventInfo()) end
    elseif event == "UNIT_ATTACK_SPEED" then
        if (...) == "player" then self:UpdateSpeeds(now) end
    elseif event == "UNIT_SPELLCAST_START" then
        local unit, _, spellID = ...
        if unit == "player" then casting = spellID end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        Names()
        local name = SpellName(spellID)
        if spellID == AUTO_SHOT then
            Restart("ranged", now)
        elseif name and aimedShot[name] then
            Restart("ranged", now)
        end
        -- A completed cast-time spell restarts the melee swing
        if casting and casting == spellID then
            casting = nil
            if not NO_RESET_IDS[spellID] and not (name and noReset[name]) then
                if hands.mh.expires then Restart("mh", now) end
                if hands.oh.expires then Restart("oh", now) end
            end
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        local unit, _, spellID = ...
        if unit == "player" and casting == spellID then casting = nil end
    elseif event == "PLAYER_ENTER_COMBAT" then
        attacking = true
        -- Starting to attack: an off hand past halfway goes back to halfway
        local oh = hands.oh
        local _, ohSpeed = MeleeSpeeds()
        if ohSpeed then
            if not oh.expires or now > oh.expires - ohSpeed / 2 then
                oh.speed, oh.expires = ohSpeed, now + ohSpeed / 2
            end
        end
    elseif event == "PLAYER_LEAVE_COMBAT" then
        attacking = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        shooting = true
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        shooting = false
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == 16 or slot == 17 or slot == 18 then
            if hands.mh.expires then Restart("mh", now) end
            if hands.oh.expires then Restart("oh", now) end
            if hands.ranged.expires then Restart("ranged", now) end
        end
    elseif event == "UNIT_AURA" then
        if (...) == "player" then self:ReadFlurry() end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED"
        or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        self.kind = self:Kind()
        playerGUID = UnitGUID and UnitGUID("player")
        if event == "PLAYER_ENTERING_WORLD" then self:ReadFlurry() end
    end
end

-- Flurry charges on you (0: none), read when your buffs change
function Swing:ReadFlurry()
    Names()
    local n = 0
    local seal
    if UnitBuff then
        for i = 1, 40 do
            local name, icon, count, _, _, _, _, _, _, spellId = UnitBuff("player", i)
            if not name then break end
            if flurry[name] and n == 0 then n = math.max(1, tonumber(count) or 1) end
            -- The seal you have up (paladins)
            if not seal and (seals[name] or SEAL_IDS[tonumber(spellId) or 0] or name:find("^Seal of ")) then
                seal = { name = name, icon = icon, id = tonumber(spellId) }
            end
        end
    end
    self.flurry = n
    self.seal = seal
    return n
end

-- ============================================
-- PALADIN SEAL TWISTING
-- ============================================
-- Seal of Command lingers about 0.4s after it's replaced, so casting Seal of
-- Blood (or the Martyr) in the last 0.4s before a swing lands both. Casting
-- a seal needs the GCD free: once the swing has less than a GCD left,
-- anything on the GCD (Crusader Strike, a judgement) means no twist before
-- this swing. That's the point of no return.

-- Spell haste, in percent (rating, plus buffs where the client says)
local function SpellHaste()
    if UnitSpellHaste then
        local ok, h = pcall(UnitSpellHaste, "player")
        if ok and tonumber(h) then return tonumber(h) end
    end
    if GetCombatRatingBonus then
        local ok, h = pcall(GetCombatRatingBonus, CR_HASTE_SPELL or 20)
        if ok and tonumber(h) then return tonumber(h) end
    end
    return 0
end

-- Your global cooldown: 1.5s cut by spell haste, never under 1s
function Swing:GCD()
    return math.max(GCD_MIN, GCD_BASE / (1 + SpellHaste() / 100))
end

-- Swing time left at which the point of no return comes: a GCD, moved
-- earlier by your latency like the other marks
function Swing:PointOfNoReturn(now)
    return self:GCD() + self:Latency(now)
end

function Swing:IsTwisting()
    local CT = Tools()
    return PlayerClass() == "PALADIN" and CT and CT:IsEnabled("PALADIN", "swingTwist") and true or false
end

function Swing:IsAttacking() return attacking end
function Swing:IsShooting() return shooting end

-- ============================================
-- LATENCY
-- ============================================

local latency, latencyAt = 0, -100

-- World latency in seconds, refreshed every few seconds (the client only
-- updates it about every 30s anyway)
function Swing:Latency(now)
    now = now or GetTime()
    if now - latencyAt >= 5 then
        latencyAt = now
        if GetNetStats then
            local ok, _, _, home, world = pcall(GetNetStats)
            local ms = ok and (tonumber(world) or tonumber(home)) or 0
            if not ms or ms <= 0 then ms = ok and tonumber(home) or 0 end
            latency = math.max(0, math.min(1, (ms or 0) / 1000))
        end
    end
    return latency
end

-- ============================================
-- WEAPON SYNC
-- ============================================

-- How long after the main hand the off hand lands, in (-mh/2, mh/2]
function Swing:SyncGap()
    local mh, oh = hands.mh, hands.oh
    if not (mh.expires and oh.expires and mh.speed) then return nil end
    local gap = oh.expires - mh.expires
    local s = mh.speed
    while gap > s / 2 do gap = gap - s end
    while gap <= -s / 2 do gap = gap + s end
    return gap
end

-- "good" (off hand just after main hand), "early" (off hand first, close),
-- "off" (apart), or nil without two weapons
function Swing:SyncState()
    local gap = self:SyncGap()
    if not gap then return nil end
    if gap >= -0.02 and gap <= GOOD_LAG then return "good", gap end
    if gap < 0 and gap > -0.5 then return "early", gap end
    return "off", gap
end

-- Main-hand time left at which pressing the sync macro lands the off hand
-- syncLag after the main hand, moved earlier by latency
function Swing:SyncMark(now)
    local oh = hands.oh
    if not oh.speed then return nil end
    return oh.speed / 2 - DB().syncLag - self:Latency(now)
end

-- Is now the moment to press the sync macro?
function Swing:ShouldSync(now)
    now = now or GetTime()
    local state = self:SyncState()
    if not state or state == "good" then return false end
    local mh, oh = hands.mh, hands.oh
    local mark = self:SyncMark(now)
    if not (mark and mh.expires and oh.expires) then return false end
    local mhLeft = mh.expires - now
    -- Pressing only moves an off hand that's past halfway
    if (oh.expires - now) >= oh.speed / 2 then return false end
    return math.abs(mhLeft - mark) <= SYNC_WINDOW
end

-- ============================================
-- HUNTER ZONES
-- ============================================

local function SteadyCastTime()
    if GetSpellInfo then
        local ok, _, _, _, castMs = pcall(GetSpellInfo, STEADY_SHOT)
        castMs = ok and tonumber(castMs)
        if castMs and castMs > 0 and castMs < 10000 then return castMs / 1000 end
    end
    return 1.5
end

-- Seconds since the last shot at which the clip zone and wind-up start
function Swing:RangedZones(now)
    local h = hands.ranged
    if not h.speed then return nil end
    local windupAt = math.max(0, h.speed - WINDUP)
    local clipAt = math.max(0, windupAt - SteadyCastTime() - self:Latency(now))
    return clipAt, windupAt
end

-- ============================================
-- DISPLAY
-- ============================================

local COLORS = {
    swing   = { 0.85, 0.65, 0.15 },
    near    = { 1.00, 0.30, 0.20 },   -- inside the latency zone
    safe    = { 0.20, 0.80, 0.30 },   -- hunter: safe to Steady Shot
    clip    = { 0.90, 0.20, 0.20 },   -- hunter: a Steady Shot would clip
    windup  = { 1.00, 0.85, 0.20 },   -- hunter: wind-up, don't move
    latency = { 1.00, 0.10, 0.10, 0.45 },
    mark    = { 0.30, 0.70, 1.00 },
    markNow = { 0.20, 1.00, 0.20 },
    twist   = { 0.75, 0.30, 1.00 },   -- paladin: the twist window
    wf      = { 0.45, 0.60, 0.95 },   -- Windfury cooling down
    wfReady = { 0.20, 0.85, 0.30 },   -- Windfury can proc again
}

local frame, ticker

local function NewBar(parent, label)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(BAR_W, BAR_H)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    bar.fill = bar:CreateTexture(nil, "BORDER")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetColorTexture(unpack(COLORS.swing))
    -- Zones drawn over the bar (latency, hunter clip / wind-up)
    bar.zone1 = bar:CreateTexture(nil, "ARTWORK")
    bar.zone2 = bar:CreateTexture(nil, "ARTWORK")
    bar.latency = bar:CreateTexture(nil, "ARTWORK")
    bar.latency:SetPoint("TOPRIGHT")
    bar.latency:SetPoint("BOTTOMRIGHT")
    bar.latency:SetColorTexture(unpack(COLORS.latency))
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:Hide()
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetColorTexture(1, 1, 1, 1)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", 4, 0)
    bar.label:SetText(label)
    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.time:SetPoint("RIGHT", -4, 0)
    return bar
end

local function Zone(tex, bar, from, to, color)
    if not from or not to or to <= from then tex:Hide() return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", bar, "TOPLEFT", from * BAR_W, 0)
    tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", from * BAR_W, 0)
    tex:SetWidth(math.max(1, (to - from) * BAR_W))
    tex:SetColorTexture(color[1], color[2], color[3], 0.35)
    tex:Show()
end

function Swing:CreateFrame()
    if frame then return frame end
    local db = DB()
    local f = CreateFrame("Frame", "WM_SwingTimerFrame", UIParent)
    f:SetSize(BAR_W, BAR_H)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    if db.x and db.y then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not DB().locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if x then DB().x, DB().y = x, y end
    end)
    f:EnableMouse(not db.locked)

    f.mh = NewBar(f, "Main")
    f.oh = NewBar(f, "Off")
    f.ranged = NewBar(f, "Auto Shot")
    f.wf = NewBar(f, "Windfury")
    f.wf.latency:Hide()
    -- Paladin twisting, on the main-hand bar: the point of no return, the
    -- twist window (zone1), and the seal you have up past the bar's end
    f.mh.ponr = f.mh:CreateTexture(nil, "OVERLAY")
    f.mh.ponr:SetColorTexture(1, 0.82, 0, 1)
    f.mh.ponr:Hide()
    f.seal = CreateFrame("Frame", "WM_SwingTimerSeal", f)
    f.seal:SetPoint("LEFT", f.mh, "RIGHT", 4, 0)
    f.seal.icon = f.seal:CreateTexture(nil, "ARTWORK")
    f.seal.icon:SetAllPoints()
    f.seal.text = f.seal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.seal.text:SetPoint("LEFT", f.seal, "LEFT", 0, 0)
    f.seal:EnableMouse(true)
    f.seal:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local s = Swing.seal
        if s and s.id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(s.id)
        else GameTooltip:AddLine(s and s.name or "No seal", 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    f.seal:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.seal:Hide()
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    -- Resize grip, bottom-right, while unlocked: drag right for wider,
    -- down for taller bars
    local grip = CreateFrame("Button", "WM_SwingTimerGrip", f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 7, -7)
    grip:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() Swing:StartResize() end)
    grip:SetScript("OnMouseUp", function() Swing:StopResize() end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize", 1, 0.8, 0)
        GameTooltip:AddLine("Drag right for wider bars, down for taller ones.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.grip = grip

    f:Hide()
    frame = f
    self.frame = f
    self:ApplySize()
    self:ApplyLock()
    return f
end

-- Size every bar from the saved width / bar height
function Swing:ApplySize()
    local db = DB()
    BAR_W, BAR_H = db.width, db.barHeight
    if not frame then return end
    frame:SetWidth(BAR_W)
    for _, key in ipairs({ "mh", "oh", "ranged", "wf" }) do
        local bar = frame[key]
        bar:SetSize(BAR_W, BAR_H)
        bar.mark:SetSize(3, BAR_H + 6)
        bar.spark:SetSize(2, BAR_H + 4)
        -- Labels only where they fit
        local fits = BAR_H >= 10
        bar.label:SetShown(fits and BAR_W >= 140)
        bar.time:SetShown(fits)
    end
    frame.mh.ponr:SetSize(3, BAR_H + 6)
    frame.seal:SetSize(BAR_H + 6, BAR_H + 6)
end

function Swing:SetSize(width, barHeight)
    local db = DB()
    if width then db.width = width end
    if barHeight then db.barHeight = barHeight end
    DB()   -- clamps
    self:ApplySize()
    if frame then self:Draw() end   -- not before it has started
end

-- Manual sizing: the frame's height follows its bars, so the grip changes
-- the width and the bar height rather than sizing the frame directly
local resizing
local function Cursor()
    local x, y = GetCursorPosition()
    local scale = (frame and frame:GetEffectiveScale()) or 1
    if not scale or scale == 0 then scale = 1 end
    return (x or 0) / scale, (y or 0) / scale
end

function Swing:StartResize()
    if DB().locked or not frame then return end
    local x, y = Cursor()
    resizing = { x = x, y = y, w = BAR_W, h = BAR_H }
    -- Keep it on screen while resizing, in or out of a fight
    testUntil = math.max(testUntil, GetTime() + 10)
end

function Swing:UpdateResize()
    if not resizing then return end
    local x, y = Cursor()
    -- Cursor down (y falls) makes the bars taller
    self:SetSize(resizing.w + (x - resizing.x), resizing.h + (resizing.y - y))
    testUntil = math.max(testUntil, GetTime() + 3)
end

function Swing:StopResize()
    if not resizing then return end
    self:UpdateResize()
    resizing = nil
end

function Swing:IsResizing() return resizing ~= nil end

function Swing:ApplyLock()
    if not frame then return end
    local locked = DB().locked
    frame:EnableMouse(not locked)
    if frame.grip then frame.grip:SetShown(not locked) end
end

function Swing:ResetPosition()
    local db = DB()
    db.x, db.y = nil, nil
    db.width, db.barHeight = DEFAULT_W, DEFAULT_H
    self:ApplySize()
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

-- Draw one bar. Returns false if it has nothing to show.
local function DrawBar(bar, h, now, color)
    if not (h.speed and h.expires) then bar:Hide() return false end
    local left = math.max(0, h.expires - now)
    local frac = 1 - math.min(1, left / h.speed)
    bar.fill:SetWidth(math.max(1, frac * BAR_W))
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar, "LEFT", frac * BAR_W, 0)
    local lat = Swing:Latency(now)
    bar.latency:SetWidth(math.max(1, math.min(1, lat / h.speed) * BAR_W))
    if left <= lat and left > 0 then color = COLORS.near end
    bar.fill:SetColorTexture(color[1], color[2], color[3], 0.9)
    bar.time:SetText(left > 0 and string.format("%.1f", left) or "")
    bar:Show()
    return true
end

-- The Windfury bar: its cooldown filling up, then "ready". Returns false
-- if it has nothing to show (not a shaman, off, or no proc yet).
function Swing:DrawWindfury(bar, now)
    if not (self:IsShaman() and ShamanEnabled("swingWindfury") and self.wfSeen and wfCooldown.speed) then
        bar:Hide()
        return false
    end
    local left = math.max(0, (wfCooldown.expires or 0) - now)
    local frac = 1 - math.min(1, left / wfCooldown.speed)
    local c = left > 0 and COLORS.wf or COLORS.wfReady
    bar.fill:SetWidth(math.max(1, frac * BAR_W))
    bar.fill:SetColorTexture(c[1], c[2], c[3], 0.9)
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar, "LEFT", frac * BAR_W, 0)
    bar.spark:SetShown(left > 0)
    bar.time:SetText(left > 0 and string.format("%.1f", left) or "ready")
    bar:Show()
    return true
end

-- Paladin twisting on the main-hand bar: the point of no return (a gold
-- line, red once passed), the twist window at the end of the bar, and the
-- seal you have up just past it
function Swing:DrawTwist(now)
    local f = frame
    local mh = hands.mh
    if not (self:IsTwisting() and mh.speed and mh.expires and f.mh:IsShown()) then
        f.mh.ponr:Hide()
        f.seal:Hide()
        return
    end
    local left = mh.expires - now
    -- The point of no return
    local ponr = self:PointOfNoReturn(now)
    if ponr > 0 and ponr < mh.speed then
        local x = (1 - ponr / mh.speed) * BAR_W
        f.mh.ponr:ClearAllPoints()
        f.mh.ponr:SetPoint("CENTER", f.mh, "LEFT", x, 0)
        if left > 0 and left < ponr then f.mh.ponr:SetColorTexture(1, 0.2, 0.2, 1)
        else f.mh.ponr:SetColorTexture(1, 0.82, 0, 1) end
        f.mh.ponr:Show()
    else
        f.mh.ponr:Hide()
    end
    self.pastPONR = left > 0 and left < ponr
    -- The twist window: the last 0.4s (an option) of the swing
    local w = math.min(DB().twistWindow, mh.speed)
    Zone(f.mh.zone1, f.mh, 1 - w / mh.speed, 1, COLORS.twist)
    -- The seal you have up
    local s = self.seal
    if s then
        f.seal.icon:SetTexture(s.icon or "Interface\\Icons\\Spell_Holy_SealOfMight")
        f.seal.icon:Show()
        f.seal.text:SetText("")
    else
        f.seal.icon:Hide()
        f.seal.text:SetText("|cFFFF4444no seal|r")
    end
    f.seal:Show()
end

-- The main-hand label, with your Flurry charges
function Swing:MainLabel()
    if Enabled("swingFlurry") and (self.flurry or 0) > 0 then
        return "Main  |cFFFFCC00Flurry " .. self.flurry .. "|r"
    end
    return "Main"
end

-- Where each bar sits; returns the stack's height
local function Stack(bars)
    local y = 0
    for _, bar in ipairs(bars) do
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        y = y + BAR_H + BAR_GAP
    end
    return math.max(BAR_H, y - BAR_GAP)
end

function Swing:IsActive(now)
    if testUntil > now then return true end
    if not Enabled("swingTimer") or not self.kind then return false end
    if self.kind == "ranged" then
        return shooting or (hands.ranged.expires and hands.ranged.expires > now and UnitAffectingCombat("player")) and true or false
    end
    return attacking or ((hands.mh.expires and hands.mh.expires > now and UnitAffectingCombat("player")) and true or false)
end

function Swing:Draw(now)
    now = now or GetTime()
    local f = self:CreateFrame()
    if not self:IsActive(now) then
        if f:IsShown() then f:Hide() end
        return
    end
    if testUntil > now then
        -- Keep the test bars cycling
        for _, key in ipairs({ "mh", "oh", "ranged" }) do
            local h = hands[key]
            if h.speed and (not h.expires or h.expires <= now) then h.expires = now + h.speed end
        end
    end

    local shown = {}
    if self.kind == "ranged" or (testUntil > now and PlayerClass() == "HUNTER") then
        f.mh:Hide(); f.oh:Hide(); f.mh.mark:Hide(); f.wf:Hide(); f.seal:Hide()
        local h = hands.ranged
        if DrawBar(f.ranged, h, now, COLORS.swing) then
            local clipAt, windupAt = self:RangedZones(now)
            local elapsed = h.speed - math.max(0, h.expires - now)
            Zone(f.ranged.zone1, f.ranged, clipAt / h.speed, windupAt / h.speed, COLORS.clip)
            Zone(f.ranged.zone2, f.ranged, windupAt / h.speed, 1, COLORS.windup)
            local c = (elapsed < clipAt) and COLORS.safe or (elapsed < windupAt) and COLORS.clip or COLORS.windup
            if h.expires > now then f.ranged.fill:SetColorTexture(c[1], c[2], c[3], 0.9) end
            shown[#shown + 1] = f.ranged
        end
        f.status:SetText("")
    else
        f.ranged:Hide()
        f.mh.label:SetText(self:MainLabel())
        if DrawBar(f.mh, hands.mh, now, COLORS.swing) then shown[#shown + 1] = f.mh end
        if DrawBar(f.oh, hands.oh, now, COLORS.swing) then shown[#shown + 1] = f.oh end
        if #shown > 0 and self:DrawWindfury(f.wf, now) then shown[#shown + 1] = f.wf end
        f.mh.zone1:Hide(); f.mh.zone2:Hide(); f.oh.zone1:Hide(); f.oh.zone2:Hide()
        self:DrawSync(now)
        self:DrawTwist(now)
    end
    local h = Stack(shown)
    f:SetHeight(h)
    f.status:ClearAllPoints()
    f.status:SetPoint("TOP", f, "BOTTOM", 0, -2)
    if #shown > 0 then f:Show() else f:Hide() end
end

-- The shaman sync mark on the main-hand bar, and the sync status line
function Swing:DrawSync(now)
    local f = frame
    local mh, oh = hands.mh, hands.oh
    if not (self:IsShaman() and ShamanEnabled("swingSync") and mh.speed and oh.speed and mh.expires and oh.expires) then
        f.mh.mark:Hide()
        f.status:SetText("")
        return
    end
    local state, gap = self:SyncState()
    local mark = self:SyncMark(now)
    local now_ = self:ShouldSync(now)
    -- A sound as SYNC NOW comes up (once per prompt)
    if now_ and not self.syncPrompting then
        local choice = DB().syncSound
        if choice and choice ~= "none" and WM.Sounds then
            local chan = (GeneralChecksDB and GeneralChecksDB.soundChannel) or "Master"
            WM.Sounds.Play(choice, chan)
        end
    end
    self.syncPrompting = now_ and true or false
    if mark and mark > 0 and mark < mh.speed then
        local x = (1 - mark / mh.speed) * BAR_W
        f.mh.mark:ClearAllPoints()
        f.mh.mark:SetPoint("CENTER", f.mh, "LEFT", x, 0)
        local c = now_ and COLORS.markNow or COLORS.mark
        f.mh.mark:SetColorTexture(c[1], c[2], c[3], state == "good" and 0.35 or 1)
        f.mh.mark:Show()
    else
        f.mh.mark:Hide()
    end
    local text
    if now_ then
        text = "|cFF33FF33SYNC NOW|r"
    elseif state == "good" then
        text = string.format("|cFF33FF33In sync|r  off hand +%.2fs", gap)
    elseif state == "early" then
        text = string.format("|cFFFFFF33Off hand first|r  %.2fs", gap)
    else
        text = string.format("|cFFFF4444Out of sync|r  %+.2fs", gap)
    end
    if math.abs(mh.speed - oh.speed) > 0.01 then
        text = text .. "  |cFF999999(speeds differ: sync drifts)|r"
    end
    f.status:SetText(text)
end

-- /wmachine swing: show sample bars for 10 seconds to position the timer
function Swing:Test()
    local now = GetTime()
    testUntil = now + 10
    if PlayerClass() == "HUNTER" then
        hands.ranged.speed = RangedSpeed() or 3.0
        hands.ranged.expires = now + hands.ranged.speed
    else
        local mh, oh = MeleeSpeeds()
        hands.mh.speed = mh or 2.6
        hands.mh.expires = now + hands.mh.speed
        if oh then hands.oh.speed, hands.oh.expires = oh, now + oh * 0.6 end
    end
    self:CreateFrame()
    self:Draw(now)
    WM:ModulePrint("SwingTimer", "Showing the swing timer for 10 seconds."
        .. (DB().locked and " It's locked: unlock it in Class Tools > General to move it." or " Drag it to move it, or its corner to resize it."))
end

function Swing:EndTest() testUntil = 0 end

-- ============================================
-- OPTIONS (Class Tools > General; registered by ClassGeneral)
-- ============================================

Swing.WIDTH_OPTIONS = {
    { value = 140, text = "140" }, { value = 180, text = "180" }, { value = 220, text = "220 (default)" },
    { value = 260, text = "260" }, { value = 300, text = "300" }, { value = 360, text = "360" },
    { value = 420, text = "420" },
}
Swing.HEIGHT_OPTIONS = {
    { value = 10, text = "10" }, { value = 14, text = "14 (default)" }, { value = 18, text = "18" },
    { value = 22, text = "22" }, { value = 28, text = "28" },
}

Swing.TWIST_OPTIONS = {
    { value = 0.3, text = "0.30 s" }, { value = 0.35, text = "0.35 s" }, { value = 0.4, text = "0.40 s (default)" },
    { value = 0.45, text = "0.45 s" }, { value = 0.5, text = "0.50 s" },
}

Swing.LAG_OPTIONS = {
    { value = 0.1, text = "0.10 s" }, { value = 0.15, text = "0.15 s" },
    { value = 0.2, text = "0.20 s" }, { value = 0.3, text = "0.30 s" },
}

function Swing.RegisterOptions(tools)
    tools:RegisterFeature("GENERAL", {
        key = "swingTimer", name = "Swing timer",
        desc = "Time to your next swing for warriors, rogues, Retribution paladins and Enhancement shamans, and to your next Auto Shot for hunters. The red end of each bar is your latency. /wmachine swing shows it to position.",
        default = true,
        onToggle = function() Swing:Refresh() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "swingAnyClass", name = "Swing timer for every class and spec",
        desc = "Show it for melee you do on any class or spec, not just those above.",
        default = false,
        onToggle = function() Swing:Refresh() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "swingFlurry", name = "Flurry charges on the swing timer",
        desc = "Shamans and warriors: the main-hand bar shows how many Flurry charges you have left.",
        default = true,
        onToggle = function() Swing:Refresh() end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "swingWidth", kind = "choice", name = "Swing timer width",
        options = Swing.WIDTH_OPTIONS, default = DEFAULT_W,
        desc = "Or drag the swing timer's corner while it's unlocked.",
        get = function() return DB().width end,
        set = function(v) Swing:SetSize(v, nil) end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "swingHeight", kind = "choice", name = "Swing timer bar height",
        options = Swing.HEIGHT_OPTIONS, default = DEFAULT_H,
        desc = "Height of each bar.",
        get = function() return DB().barHeight end,
        set = function(v) Swing:SetSize(nil, v) end,
    })
    tools:RegisterFeature("GENERAL", {
        key = "swingLock", name = "Lock the swing timer",
        desc = "Stops it being dragged or resized, and lets clicks pass through it.",
        default = false,
        onToggle = function(v) DB().locked = v and true or false; Swing:ApplyLock() end,
    })
    local tdb = ClassToolsDB and ClassToolsDB.enabled and ClassToolsDB.enabled.GENERAL
    if tdb and tdb.swingLock ~= nil then DB().locked = tdb.swingLock and true or false end
end

-- The weapon sync and Windfury options, on the Shaman tab (registered by
-- ClassShaman)
function Swing.RegisterShamanOptions(tools)
    -- 3.55 and before had them under General: keep the choices made there
    local en = ClassToolsDB and ClassToolsDB.enabled
    if en and en.GENERAL then
        for _, key in ipairs({ "swingSync", "swingWindfury" }) do
            if en.GENERAL[key] ~= nil then
                en.SHAMAN = en.SHAMAN or {}
                if en.SHAMAN[key] == nil then en.SHAMAN[key] = en.GENERAL[key] end
                en.GENERAL[key] = nil
            end
        end
    end
    tools:RegisterFeature("SHAMAN", {
        key = "swingSync", name = "Weapon sync mark on the swing timer",
        desc = "Enhancement: marks when to press your sync macro (/cleartarget, /targetlasttarget, /startattack) so the off hand lands just after the main hand, and says whether you're in sync.",
        default = true,
    })
    tools:RegisterFeature("SHAMAN", {
        key = "swingWindfury", name = "Windfury cooldown bar on the swing timer",
        desc = "Enhancement: a bar under your weapons showing Windfury Weapon's 3 second cooldown (shared by both hands) from its last proc, green when it can proc again.",
        default = true,
        onToggle = function() Swing:Refresh() end,
    })
    tools:RegisterFeature("SHAMAN", {
        key = "swingSyncSound", kind = "choice", name = "SYNC NOW sound",
        options = WM.Sounds and WM.Sounds.OPTIONS or {}, default = "none",
        desc = "Played as SYNC NOW comes up, so you can press the macro without watching the bar.",
        get = function() return DB().syncSound end,
        set = function(v) DB().syncSound = v end,
        onChange = function(v)
            if WM.Sounds then WM.Sounds.Play(v, (GeneralChecksDB and GeneralChecksDB.soundChannel) or "Master") end
        end,
    })
    tools:RegisterFeature("SHAMAN", {
        key = "swingSyncLag", kind = "choice", name = "Off hand lands after by",
        options = Swing.LAG_OPTIONS, default = 0.15,
        desc = "How long after the main hand the sync macro aims to land the off hand.",
        get = function() return DB().syncLag end,
        set = function(v) DB().syncLag = v end,
    })
end

-- The seal twisting options, on the Paladin tab (registered by ClassPaladin)
function Swing.RegisterPaladinOptions(tools)
    -- 3.53 had them under General: keep the choice made there
    local en = ClassToolsDB and ClassToolsDB.enabled
    if en and en.GENERAL and en.GENERAL.swingTwist ~= nil then
        en.PALADIN = en.PALADIN or {}
        if en.PALADIN.swingTwist == nil then en.PALADIN.swingTwist = en.GENERAL.swingTwist end
        en.GENERAL.swingTwist = nil
    end
    tools:RegisterFeature("PALADIN", {
        key = "swingTwist", name = "Seal twisting marks on the swing timer",
        desc = "Retribution: on the main-hand bar, a gold line at the point of no return (a GCD before the swing, with spell haste and your latency; red once passed), the twist window shaded at the end of the bar, and the seal you have up just past it.",
        default = true,
        onToggle = function() Swing:Refresh() end,
    })
    tools:RegisterFeature("PALADIN", {
        key = "swingTwistWindow", kind = "choice", name = "Twist window",
        options = Swing.TWIST_OPTIONS, default = TWIST_DEFAULT,
        desc = "How long before the swing the twist window starts: the time Seal of Command still lands after you change seal.",
        get = function() return DB().twistWindow end,
        set = function(v) DB().twistWindow = v; Swing:Refresh() end,
    })
end

function Swing:Refresh()
    self.kind = self:Kind()
    -- Options can change before it has started (the guided setup)
    if frame and WM:IsModuleOn("SwingTimer") then self:Draw() end
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local EVENTS = {
    "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_ATTACK_SPEED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
    "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_AURA",
}

function Swing:Initialize()
    DB()
    self.kind = self:Kind()
    playerGUID = UnitGUID and UnitGUID("player")
    self:CreateFrame()
    WM:RegisterEvents(events, EVENTS)
    -- Draw every frame while shown; check ranged haste a few times a second
    ticker = CreateFrame("Frame")
    local sinceRanged = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        if not WM:IsModuleOn("SwingTimer") then return end
        local now = GetTime()
        sinceRanged = sinceRanged + (elapsed or 0)
        if sinceRanged > 0.2 then
            sinceRanged = 0
            local s = RangedSpeed()
            if s and hands.ranged.speed and math.abs(s - hands.ranged.speed) > 0.001 then
                Rescale(hands.ranged, s, now)
            end
        end
        if resizing then Swing:UpdateResize() end
        Swing:Draw(now)
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    if not WM:IsModuleOn("SwingTimer") then return end
    Swing:OnEvent(event, ...)
end)

-- Turned off on this character (or Class Tools is): the bars go, the
-- per-frame ticker stops and the combat log is no longer read
function Swing:OnModuleOff()
    testUntil, resizing = 0, nil
    attacking, shooting, casting = false, false, nil
    for _, h in pairs(hands) do h.speed, h.expires = nil, nil end
    wfCooldown.speed, wfCooldown.expires = nil, nil
    self.wfSeen, self.flurry, self.seal, self.pastPONR = false, 0, nil, false
    self.syncPrompting = false
    if frame then frame:Hide() end
    if ticker then ticker:Hide() end
    events:UnregisterAllEvents()
end

-- Back on after being turned off (not at login: Initialize does that)
function Swing:OnModuleOn()
    if not ticker then return end   -- not started yet
    WM:RegisterEvents(events, EVENTS)
    ticker:Show()
    self.kind = self:Kind()
    playerGUID = UnitGUID and UnitGUID("player")
end
