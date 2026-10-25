-- Swing timer: swing detection, next-melee, cast resets, haste, parry haste,
-- extra attacks, weapon swaps, shaman sync, hunter Auto Shot zones, spec
-- detection and the bars. Usage: lua5.1 test_swing.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 100
env.GetTime = function() return now end
local mhSpeed, ohSpeed = 2.6, 2.6
env.UnitAttackSpeed = function() return mhSpeed, ohSpeed end
local rangedSpeed = 3.0
env.UnitRangedDamage = function() return rangedSpeed end
env.UnitGUID = function(u) return u == "player" and "Player-1" or "Mob-1" end
env.UnitAffectingCombat = function() return true end
local worldMs = 100
env.GetNetStats = function() return 0, 0, 80, worldMs end
local spellNames = { [78] = "Heroic Strike", [845] = "Cleave", [6807] = "Maul", [2973] = "Raptor Strike",
    [34120] = "Steady Shot", [19434] = "Aimed Shot", [403] = "Lightning Bolt", [1464] = "Slam", [75] = "Auto Shot" }
env.GetSpellInfo = function(id)
    if id == 34120 then return "Steady Shot", nil, "icon", 1500 end
    return spellNames[id]
end
local known = {}
env.IsPlayerSpell = function(id) return known[id] or false end
env.IsSpellKnown = function(id) return known[id] or false end
local talents = { 0, 0, 0 }
env.GetNumTalents = function(tab) return 1 end
env.GetTalentInfo = function(tab) return "T", "i", 1, 1, talents[tab] end
env.UnitClass = function() return "Shaman", "SHAMAN" end
local cleu
env.CombatLogGetCurrentEventInfo = function() return unpack(cleu, 1, 24) end

for _, f in ipairs({ "Core.lua", "UI.lua", "Sounds.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua",
                     "Modules/SwingTimer.lua", "Modules/ClassGeneral.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Swing, Gen = WM.modules.ClassTools, WM.modules.SwingTimer, WM.modules.ClassGeneral
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
Gen:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end

local ME, MOB = "Player-1", "Mob-1"
local function Log(sub, src, dst, ...)
    cleu = { now, sub, false, src, "x", 0, 0, dst, "y", 0, 0, ... }
    Swing:OnEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
local function MeleeHit(offHand)   -- SWING_DAMAGE: isOffHand is the 21st value
    Log("SWING_DAMAGE", ME, MOB, 500, 0, 1, 0, 0, 0, nil, nil, nil, offHand)
end
local function MeleeMiss(offHand, missType) Log("SWING_MISSED", ME, MOB, missType or "MISS", offHand) end
local H = Swing.hands

-- ---- Who gets a timer ----
check("shaman with no talents or Stormstrike: no timer", Swing:Kind() == nil)
talents = { 5, 21, 0 }
check("most points in Enhancement: melee", Swing:Kind() == "melee")
talents = { 30, 31, 0 }
check("Enhancement just ahead of Elemental: melee", Swing:Kind() == "melee")
talents = { 40, 21, 0 }
check("Elemental: no timer", Swing:Kind() == nil)
known[17364] = true
check("knowing Stormstrike counts as Enhancement", Swing:Kind() == "melee")
known[17364] = nil
env.UnitClass = function() return "Paladin", "PALADIN" end
talents = { 0, 10, 41 }
check("Retribution paladin: melee", Swing:Kind() == "melee")
talents = { 41, 10, 0 }
check("Holy paladin: none", Swing:Kind() == nil)
CT:SetEnabled("GENERAL", "swingAnyClass", true)
check("every-class option covers a holy paladin", Swing:Kind() == "melee")
CT:SetEnabled("GENERAL", "swingAnyClass", false)
for class, kind in pairs({ WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = false }) do
    env.UnitClass = function() return class, class end
    check(class .. " timer kind", (Swing:Kind() or false) == kind)
end

-- ---- Melee swings (an Enhancement shaman) ----
env.UnitClass = function() return "Shaman", "SHAMAN" end
talents = { 0, 40, 21 }
Swing:Initialize()
check("enhancement detected on load", Swing.kind == "melee")
Swing:OnEvent("PLAYER_ENTER_COMBAT")
check("starting to attack puts the off hand at half its swing", near(H.oh.expires, now + 1.3))
MeleeHit(nil)
check("a main-hand hit restarts the main hand", near(H.mh.expires, now + 2.6))
now = now + 1.3
MeleeHit(true)
check("an off-hand hit restarts the off hand only", near(H.oh.expires, now + 2.6) and near(H.mh.expires, now + 1.3))
now = now + 1.0
MeleeMiss(nil, "DODGE")
check("a dodge restarts the swing too", near(H.mh.expires, now + 2.6))
MeleeMiss(true, "PARRY")
check("a parried off hand restarts the off hand", near(H.oh.expires, now + 2.6))
-- Someone else's swing is ignored
local before = H.mh.expires
Log("SWING_DAMAGE", MOB, ME, 500)
check("others' swings ignored", H.mh.expires == before)

-- ---- Extra attacks (Windfury) don't restart a second time ----
now = now + 2.6
MeleeHit(nil)
local exp = H.mh.expires
Log("SPELL_EXTRA_ATTACKS", ME, MOB, 25504, "Windfury Attack", 1, 1)
now = now + 0.01
MeleeHit(nil)
check("the extra attack's swing doesn't restart the main hand", H.mh.expires == exp)
now = now + 0.5
MeleeHit(nil)
check("the next real swing does", near(H.mh.expires, now + 2.6))
Log("SPELL_DAMAGE", ME, MOB, 25504, "Windfury Attack", 1, 300)
check("Windfury Attack damage isn't a swing", near(H.mh.expires, now + 2.6))

-- ---- Next-melee abilities ----
now = now + 1
Log("SPELL_DAMAGE", ME, MOB, 30324, "Heroic Strike", 1, 900)
check("Heroic Strike restarts the main hand", near(H.mh.expires, now + 2.6))
now = now + 1
Log("SPELL_MISSED", ME, MOB, 25231, "Cleave", 1, "DODGE")
check("a dodged Cleave restarts it too", near(H.mh.expires, now + 2.6))
now = now + 1
Log("SPELL_DAMAGE", ME, MOB, 17364, "Stormstrike", 8, 900)
check("Stormstrike doesn't touch the swing", near(H.mh.expires, now + 1.6))

-- ---- Cast-time spells ----
Swing:OnEvent("UNIT_SPELLCAST_START", "player", "g1", 403)
now = now + 0.5
Swing:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g1", 403)
check("finishing Lightning Bolt restarts both hands", near(H.mh.expires, now + 2.6) and near(H.oh.expires, now + 2.6))
now = now + 0.5
Swing:OnEvent("UNIT_SPELLCAST_START", "player", "g2", 403)
Swing:OnEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "g2", 403)
Swing:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g3", 8042)   -- an instant (Earth Shock)
check("an interrupted cast and an instant don't reset", near(H.mh.expires, now + 2.1))

-- ---- Haste ----
mhSpeed, ohSpeed = 2.0, 2.0      -- Flurry (2.6 -> 2.0)
Swing:OnEvent("UNIT_ATTACK_SPEED", "player")
check("haste rescales the time left", near(H.mh.expires, now + 2.1 * 2.0 / 2.6) and H.mh.speed == 2.0)
mhSpeed, ohSpeed = 2.6, 2.6
Swing:OnEvent("UNIT_ATTACK_SPEED", "player")
check("and back again", near(H.mh.expires, now + 2.1))

-- ---- Parry haste ----
MeleeHit(nil)                     -- 2.6 left
Log("SWING_MISSED", MOB, ME, "PARRY")
check("parrying takes 40% of the swing off", near(H.mh.expires, now + 2.6 - 1.04))
H.mh.expires = now + 0.7          -- 0.7 left: only down to 20% (0.52)
Log("SWING_MISSED", MOB, ME, "PARRY")
check("but never below 20% left", near(H.mh.expires, now + 0.52))
Log("SWING_MISSED", MOB, ME, "PARRY")
check("already at 20%: no change", near(H.mh.expires, now + 0.52))
Log("SPELL_MISSED", MOB, ME, 1, "Hit", 1, "PARRY")
check("a parried special also counts (at 20%: no change)", near(H.mh.expires, now + 0.52))
MeleeHit(nil)
Log("SWING_MISSED", MOB, ME, "DODGE")
check("dodging doesn't haste", near(H.mh.expires, now + 2.6))

-- ---- Weapon swap ----
now = now + 1
Swing:OnEvent("PLAYER_EQUIPMENT_CHANGED", 1)
check("non-weapon slots ignored", near(H.mh.expires, now + 1.6))
Swing:OnEvent("PLAYER_EQUIPMENT_CHANGED", 17)
check("an off-hand swap restarts the hands", near(H.mh.expires, now + 2.6) and near(H.oh.expires, now + 2.6))

-- ---- Latency ----
check("world latency in seconds", near(Swing:Latency(now + 10), 0.1))

-- ---- Weapon sync ----
local db = Swing.DB()
db.syncLag = 0.15
MeleeHit(nil)                     -- MH lands at now+2.6
H.oh.expires = now + 2.6 + 0.2
check("off hand 0.2s after: in sync", (Swing:SyncState()) == "good")
H.oh.expires = now + 2.6 - 0.2
check("off hand 0.2s first: early", (Swing:SyncState()) == "early")
H.oh.expires = now + 2.6 + 1.0
local state, gap = Swing:SyncState()
check("1s apart: out of sync", state == "off" and near(gap, 1.0))
H.oh.expires = now + 2.6 + 2.0    -- 2.0 after = 0.6 before the next main hand
state, gap = Swing:SyncState()
check("the gap wraps to the nearest main hand", near(gap, -0.6) and state == "off")
-- The mark: MH left = 2.6/2 - 0.15 - 0.1 = 1.05
check("sync mark: off-hand half speed - lag - latency", near(Swing:SyncMark(now), 1.05))
now = now + (2.6 - 1.05)          -- MH has 1.05 left: at the mark
H.oh.expires = now + 0.9          -- OH 0.9 left (past halfway) and landing first
check("at the mark with a bad gap: SYNC NOW", Swing:ShouldSync(now))
check("not well away from the mark", not Swing:ShouldSync(now - 0.3))
H.oh.expires = now + 1.5          -- OH not past halfway: pressing wouldn't move it
check("off hand not past halfway: pressing does nothing, no prompt", not Swing:ShouldSync(now))
H.oh.expires = H.mh.expires + 0.15
check("in sync: no prompt", not Swing:ShouldSync(now))
-- What pressing does, through the engine: OH goes to now + 1.3 = MH + 0.25
H.oh.expires = now + 0.9
Swing:OnEvent("PLAYER_LEAVE_COMBAT")
Swing:OnEvent("PLAYER_ENTER_COMBAT")
state, gap = Swing:SyncState()
check("pressing the macro at the mark syncs the hands", state == "good" and near(gap, 0.25))

-- ---- SYNC NOW sound ----
local played = {}
env.PlaySound = function(id, chan) played[#played + 1] = { id, chan } end
env.PlaySoundFile = function(path, chan) played[#played + 1] = { path, chan } end
check("SYNC NOW sound off by default", Swing.DB().syncSound == "none")
Swing.DB().syncSound = "kit:8959"
local savedOH = H.oh.expires
H.oh.expires = now + 0.9
Swing:Draw(now)
check("plays as SYNC NOW comes up", #played == 1 and played[1][1] == 8959)
Swing:Draw(now + 0.02)
check("once per prompt", #played == 1)
H.oh.expires = H.mh.expires + 0.15
Swing:Draw(now)
H.oh.expires = now + 0.9
Swing:Draw(now)
check("again on the next prompt", #played == 2)
Swing.DB().syncSound = "none"
H.oh.expires = H.mh.expires + 0.15
Swing:Draw(now)
H.oh.expires = now + 0.9
Swing:Draw(now)
check("None: silent", #played == 2)
H.oh.expires = savedOH

-- ---- The bars ----
Swing:Draw(now)
local f = env.WM_SwingTimerFrame
check("frame shown while attacking", f:IsShown())
check("both hand bars shown", f.mh:IsShown() and f.oh:IsShown() and not f.ranged:IsShown())
check("spark moves right with the swing", select(4, f.mh.spark:GetPoint(1)) > 0)
local fillBefore = f.mh.fill:GetWidth()
now = now + 0.5
Swing:Draw(now)
check("fill grows", f.mh.fill:GetWidth() > fillBefore)
check("latency zone at the end of the bar", near(f.mh.latency:GetWidth(), 0.1 / 2.6 * 220))
check("sync status shown", (f.status:GetText() or ""):find("In sync", 1, true) ~= nil)
check("sync mark on the main-hand bar", f.mh.mark:IsShown())
now = H.mh.expires - 0.05
Swing:Draw(now)
check("inside the latency zone the fill changes colour", f.mh.fill._tex[1] == 1.00 and f.mh.fill._tex[2] == 0.30)
ohSpeed = 2.7
Swing:OnEvent("UNIT_ATTACK_SPEED", "player")
Swing:Draw(now)
check("unequal speeds are pointed out", (f.status:GetText() or ""):find("speeds differ", 1, true) ~= nil)
ohSpeed = 2.6
CT:SetEnabled("GENERAL", "swingSync", false)
Swing:Draw(now)
check("sync mark off: no mark or status", not f.mh.mark:IsShown() and (f.status:GetText() or "") == "")
CT:SetEnabled("GENERAL", "swingSync", true)
Swing:OnEvent("PLAYER_LEAVE_COMBAT")
env.UnitAffectingCombat = function() return false end
Swing:Draw(now)
check("hidden after you stop attacking and leave combat", not f:IsShown())
env.UnitAffectingCombat = function() return true end
CT:SetEnabled("GENERAL", "swingTimer", false)
Swing:OnEvent("PLAYER_ENTER_COMBAT")
Swing:Draw(now)
check("option off: hidden", not f:IsShown())
CT:SetEnabled("GENERAL", "swingTimer", true)
Swing:Draw(now)
check("option on: back", f:IsShown())

-- Lock
CT:SetEnabled("GENERAL", "swingLock", true)
check("lock saved", Swing.DB().locked == true)
CT:SetEnabled("GENERAL", "swingLock", false)

-- ---- Hunter Auto Shot ----
env.UnitClass = function() return "Hunter", "HUNTER" end
Swing:Refresh()
Swing:OnEvent("PLAYER_LEAVE_COMBAT")
Swing:OnEvent("START_AUTOREPEAT_SPELL")
Swing:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "a1", 75)
check("Auto Shot restarts the ranged timer", near(H.ranged.expires, now + 3.0))
local clipAt, windupAt = Swing:RangedZones(now)
check("wind-up is the last 0.5s", near(windupAt, 2.5))
check("clip zone starts a Steady Shot cast + latency before the wind-up", near(clipAt, 2.5 - 1.5 - 0.1))
Swing:Draw(now + 0.2)
check("ranged bar shown, melee bars hidden", f.ranged:IsShown() and not f.mh:IsShown() and not f.oh:IsShown())
check("right after a shot: safe (green)", f.ranged.fill._tex[2] == 0.80)
Swing:Draw(now + 1.5)
check("inside the clip zone: red", f.ranged.fill._tex[1] == 0.90 and f.ranged.fill._tex[2] == 0.20)
Swing:Draw(now + 2.7)
check("in the wind-up: yellow", f.ranged.fill._tex[1] == 1.00 and f.ranged.fill._tex[2] == 0.85)
check("clip and wind-up zones drawn", f.ranged.zone1:IsShown() and f.ranged.zone2:IsShown())
Swing:OnEvent("UNIT_SPELLCAST_START", "player", "s1", 34120)
now = now + 1.5
Swing:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "s1", 34120)
check("Steady Shot doesn't reset the Auto Shot timer", near(H.ranged.expires, now + 1.5))
Swing:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "a2", 19434)
check("Aimed Shot restarts it", near(H.ranged.expires, now + 3.0))
Swing:OnEvent("STOP_AUTOREPEAT_SPELL")
env.UnitAffectingCombat = function() return false end
Swing:Draw(now + 5)
check("hidden when you stop shooting", not f:IsShown())

-- ---- Test mode ----
Swing:Test()
check("test mode shows it", f:IsShown() and W.printed[#W.printed]:find("10 seconds", 1, true))
Swing:EndTest()
Swing:Draw(now)
check("and ends", not f:IsShown())

-- No combat-log function on this client: no error
env.CombatLogGetCurrentEventInfo = false
Swing:OnEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- ---- Resizing ----
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.CombatLogGetCurrentEventInfo = function() return unpack(cleu, 1, 24) end
Swing:Refresh()
local sdb = Swing.DB()
check("default size", sdb.width == 220 and sdb.barHeight == 14 and f.mh:GetWidth() == 220 and f.mh:GetHeight() == 14)
check("grip shown while unlocked", f.grip:IsShown())
local cx, cy = 500, 400
env.GetCursorPosition = function() return cx, cy end
f.GetEffectiveScale = function() return 1 end
W.fire(f.grip, "OnMouseDown")
check("resizing keeps the timer on screen", Swing:IsResizing() and Swing:IsActive(now))
cx, cy = 580, 390                 -- 80 right, 10 down
Swing:UpdateResize()
check("drag right: wider", sdb.width == 300 and f.mh:GetWidth() == 300 and f:GetWidth() == 300)
check("drag down: taller bars", sdb.barHeight == 24 and f.mh:GetHeight() == 24)
check("spark and mark follow the bar height", f.mh.spark:GetHeight() == 28 and f.mh.mark:GetHeight() == 30)
cx, cy = 2000, 2000
W.fire(f.grip, "OnMouseUp")
check("size clamped to its limits", sdb.width == 600 and sdb.barHeight == 8 and not Swing:IsResizing())
check("labels hidden when the bars are too thin", not f.mh.label:IsShown() and not f.mh.time:IsShown())
-- Drawing uses the new width
H.mh.speed, H.mh.expires = 2.0, now + 1.0
Swing:OnEvent("PLAYER_ENTER_COMBAT")
Swing:Draw(now)
check("spark placed on the resized bar", near(select(4, f.mh.spark:GetPoint(1)), 300))
-- Class Tools dropdowns
Swing:SetSize(260, 18)
check("width and height options apply", sdb.width == 260 and f.mh:GetWidth() == 260 and f.mh:GetHeight() == 18
    and f.mh.label:IsShown())
check("stack height follows the bar height", f:GetHeight() == 18 + 3 + 18 or f:GetHeight() == 18)
-- Locked: no grip, no resizing
CT:SetEnabled("GENERAL", "swingLock", true)
check("locked: grip hidden", not f.grip:IsShown())
W.fire(f.grip, "OnMouseDown")
check("locked: can't resize", not Swing:IsResizing())
CT:SetEnabled("GENERAL", "swingLock", false)
check("unlocked: grip back", f.grip:IsShown())
-- Bad saved values are repaired
sdb.width, sdb.barHeight = "wide", 99
Swing.DB()
check("bad saved size repaired", sdb.width == 220 and sdb.barHeight == 40)
Swing:ResetPosition()
check("reset puts the default size back", sdb.width == 220 and sdb.barHeight == 14 and f.mh:GetWidth() == 220)

-- ---- Windfury cooldown bar ----
env.UnitClass = function() return "Shaman", "SHAMAN" end
talents = { 5, 41, 15 }
Swing.kind = Swing:Kind()
Swing:EndTest()
Swing:OnEvent("PLAYER_ENTER_COMBAT")
MeleeHit(false); MeleeHit(true)
local WF = Swing.wfCooldown
WF.speed, WF.expires, Swing.wfSeen = nil, nil, false
Swing:Draw(now)
check("Windfury bar: hidden before any proc", not f.wf:IsShown())
Log("SPELL_EXTRA_ATTACKS", ME, MOB, 15600, "Hand of Justice", 1, 1)
check("another extra attack doesn't start it", WF.expires == nil and not Swing.wfSeen)
Log("SPELL_EXTRA_ATTACKS", ME, MOB, 25504, "Windfury Attack", 1, 1)
check("a Windfury proc starts its 3s cooldown", near(WF.expires, now + 3) and Swing.wfSeen)
Swing:Draw(now)
check("Windfury bar shown under the weapons", f.wf:IsShown() and f.wf.time:GetText() == "3.0")
now = now + 1
Swing:Draw(now)
check("cooling down", f.wf.time:GetText() == "2.0")
now = now + 2.5
Swing:Draw(now)
check("ready again", f.wf:IsShown() and f.wf.time:GetText() == "ready")
CT:SetEnabled("GENERAL", "swingWindfury", false)
Swing:Draw(now)
check("option off: no Windfury bar", not f.wf:IsShown())
CT:SetEnabled("GENERAL", "swingWindfury", true)
env.UnitClass = function() return "Warrior", "WARRIOR" end
Swing.kind = Swing:Kind()
Swing:Draw(now)
check("not a shaman: no Windfury bar", not f.wf:IsShown())

-- ---- Flurry charges ----
local flurryStacks = 0
env.UnitBuff = function(u, i)
    if u == "player" and i == 1 and flurryStacks > 0 then return "Flurry", "icon", flurryStacks end
end
flurryStacks = 3
Swing:OnEvent("UNIT_AURA", "player")
Swing:Draw(now)
check("Flurry charges read", Swing.flurry == 3)
check("shown on the main-hand bar", f.mh.label:GetText():find("Flurry 3", 1, true) ~= nil)
flurryStacks = 1
Swing:OnEvent("UNIT_AURA", "target")
check("other units' auras ignored", Swing.flurry == 3)
Swing:OnEvent("UNIT_AURA", "player")
Swing:Draw(now)
check("a charge used", f.mh.label:GetText():find("Flurry 1", 1, true) ~= nil)
CT:SetEnabled("GENERAL", "swingFlurry", false)
Swing:Draw(now)
check("option off: plain label", f.mh.label:GetText() == "Main")
CT:SetEnabled("GENERAL", "swingFlurry", true)
flurryStacks = 0
Swing:OnEvent("UNIT_AURA", "player")
Swing:Draw(now)
check("Flurry gone: plain label", Swing.flurry == 0 and f.mh.label:GetText() == "Main")
flurryStacks = 2
Swing:OnEvent("UNIT_AURA", "player")
Swing:OnModuleOff()
check("off: Windfury and Flurry cleared", Swing.flurry == 0 and not Swing.wfSeen and WF.expires == nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
