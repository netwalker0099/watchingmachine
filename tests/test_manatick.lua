-- Mana tick spark: finding the 2 second tick rhythm from mana gains (and
-- ignoring potions until the rhythm really moves), the five-second rule
-- after spending mana on a spell, the spark's place on the health bar,
-- mana bar or its own bar (Blizzard's or ElvUI's player frame), hiding at
-- full mana, its Class Tools options, and turning it off and on.
-- Usage: lua5.1 test_manatick.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1000
env.GetTime = function() return now end
local mana, maxMana = 5000, 10000
env.UnitPower = function(_, kind) return kind == 0 and mana or 0 end
env.UnitPowerMax = function(_, kind) return kind == 0 and maxMana or 0 end
local combat = false
env.UnitAffectingCombat = function() return combat end
env.UnitClass = function() return "Mage", "MAGE" end
local shift = false
env.IsShiftKeyDown = function() return shift end
function W.Frame:IsVisible() return self._shown end
function W.Frame:GetFrameStrata() return self._strata or "MEDIUM" end
function W.Frame:SetFrameStrata(s) self._strata = s end
function W.Frame:GetFrameLevel() return self._level or 1 end
function W.Frame:SetFrameLevel(l) self._level = l end
function W.Frame:SetAllPoints(f) self._allPoints = f end
-- Blizzard's player frame bars
local health = W.NewFrame("PlayerFrameHealthBar")
health:SetSize(120, 12)
env.PlayerFrameHealthBar = health
local manaBar = W.NewFrame("PlayerFrameManaBar")
manaBar:SetSize(120, 12)
env.PlayerFrameManaBar = manaBar

for _, f in ipairs({ "Core.lua", "UI.lua", "Sounds.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua",
                     "Modules/SwingTimer.lua", "Modules/ManaTick.lua", "Modules/ClassGeneral.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, MT, Gen = WM.modules.ClassTools, WM.modules.ManaTick, WM.modules.ClassGeneral
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
Gen:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end
local evFrame
local origRegister = WM.RegisterEvents
WM.RegisterEvents = function(_, fr) evFrame = fr end
MT:Initialize()
WM.RegisterEvents = origRegister
local function Event(ev, ...) evFrame._scripts.OnEvent(evFrame, ev, ...) end
local function Power(new) mana = new; Event("UNIT_POWER_FREQUENT", "player", "MANA") end

-- ---- Wiring ----
check("a part of Class Tools", WM.MODULE_PARENT.ManaTick == "ClassTools")
check("its settings per character", WM.Profiles.SCOPE.ManaTickDB ~= nil and not WM.Profiles.SCOPE.ManaTickDB.shared)
check("options in Class Tools > General", CT:IsEnabled("GENERAL", "manaTick") and CT:IsEnabled("GENERAL", "manaTickFSR")
    and CT:IsEnabled("GENERAL", "manaTickHideFull"))
check("on the health bar by default", env.ManaTickDB.where == "health")

-- ---- Finding the ticks ----
check("no rhythm yet", MT:TickFraction(now) == nil)
Power(5100)
check("the first gain starts the rhythm", MT.lastTick == 1000)
now = 1002.05; Power(5200)
check("a gain 2s later is a tick", near(MT.lastTick, 1002.05))
now = 1003; Power(6000)          -- a potion between ticks
check("a potion between ticks is ignored", near(MT.lastTick, 1002.05) and near(MT.candidate, 1003))
now = 1004.1; Power(6100)
check("the next tick keeps the rhythm and forgets the potion", near(MT.lastTick, 1004.1) and MT.candidate == nil)
now = 1012.1; Power(6200)        -- full a while, then a tick 8s on: still the rhythm
check("ticks after a gap still fit", near(MT.lastTick, 1012.1))
-- The rhythm moved (a new server cycle): two off-rhythm gains 2s apart
now = 1013.1; Power(6300)
check("one off-rhythm gain: noted, not trusted", near(MT.lastTick, 1012.1))
now = 1015.1; Power(6400)
check("a second one 2s later: the new rhythm", near(MT.lastTick, 1015.1) and MT.candidate == nil)
-- Spark position
now = 1016.1
check("half way between ticks", near(MT:TickFraction(now), 0.5))
now = 1017.0
check("nearly at the next tick", near(MT:TickFraction(now), 0.95))
Event("UNIT_POWER_FREQUENT", "target", "MANA")
Event("UNIT_POWER_FREQUENT", "player", "ENERGY")
check("other units and power types ignored", near(MT.lastTick, 1015.1))

-- ---- The five-second rule ----
check("not in the five-second rule", MT:FSRFraction(now) == nil)
Event("UNIT_SPELLCAST_SUCCEEDED", "player")
now = 1017.1; Power(5900)        -- the cost comes off just after the cast
check("spending mana on a spell starts it", near(MT.fsrStart, 1017.1))
now = 1019.6
check("half way through it", near(MT:FSRFraction(now), 0.5))
now = 1022.2
check("over after 5 seconds", MT:FSRFraction(now) == nil)
now = 1030; Power(5000)          -- mana burned, no cast of yours
check("losing mana without casting doesn't start it", near(MT.fsrStart, 1017.1))
now = 1040; Power(4800)
now = 1040.2; Event("UNIT_SPELLCAST_SUCCEEDED", "player")
check("cost first, then the cast event: still counts", near(MT.fsrStart, 1040))

-- ---- The spark on the health bar ----
MT:Reset()
now = 2000; Power(4900)
now = 2002; Power(5000)
now = 2001.5 + 2                 -- 1.5s into the rhythm
MT:Draw(now)
local ov = env.WM_ManaTickOverlay
check("overlay laid over the health bar", ov:IsShown() and ov._allPoints == health and ov:GetFrameLevel() == 6)
local p = ov.tick._points[1]
check("white spark three quarters along", ov.tick:IsShown() and near(p[4], 0.75 * ov:GetWidth()))
check("no five-second spark outside it", not ov.fsr:IsShown())
check("nothing written into the game's bar", rawget(health, "tick") == nil and rawget(health, "fsr") == nil)
Event("UNIT_SPELLCAST_SUCCEEDED", "player"); Power(4000)
MT:Draw(now)
check("orange spark in the five-second rule", ov.fsr:IsShown())
CT:SetEnabled("GENERAL", "manaTickFSR", false)
MT:Draw(now)
check("five-second spark option off", not ov.fsr:IsShown() and ov.tick:IsShown())
CT:SetEnabled("GENERAL", "manaTickFSR", true)

-- ---- Mana bar, own bar, ElvUI ----
env.ManaTickDB.where = "mana"
MT:Draw(now)
check("on the mana bar", ov._allPoints == manaBar)
env.ManaTickDB.where = "own"
MT:Draw(now)
local own = env.WM_ManaTickBar
check("its own bar", own and own:IsShown() and ov._allPoints == own)
shift = false
own._scripts.OnDragStart(own)
check("own bar: plain drag doesn't move it", true)
env.ManaTickDB.where = "health"
MT:Draw(now)
check("back on the health bar: own bar hidden", ov._allPoints == health and not own:IsShown())
env.PlayerFrameHealthBar = false   -- (nil would give the harness's stand-in frame)
local elv = W.NewFrame("ElvHealth")
env.ElvUF_Player = { Health = elv }
elv.GetWidth = function() return 200 end
MT:Draw(now)
check("ElvUI's player health bar when there's no Blizzard one", ov._allPoints == elv)
env.ElvUF_Player = nil
MT:Draw(now)
check("no player frame at all: its own bar", ov._allPoints == own and own:IsShown())
env.PlayerFrameHealthBar = health
MT:Draw(now)
health:Hide()
MT:Draw(now)
check("player frame hidden: spark hidden", not ov:IsShown())
health:Show()

-- ---- When it shows ----
mana = maxMana
MT.fsrStart = nil
MT:Draw(now)
check("full mana out of combat: hidden", not ov:IsShown())
combat = true
MT:Draw(now)
check("full mana in combat: shown", ov:IsShown())
combat = false
CT:SetEnabled("GENERAL", "manaTickHideFull", false)
MT:Draw(now)
check("option: shown at full mana too", ov:IsShown())
CT:SetEnabled("GENERAL", "manaTickHideFull", true)
mana = 3000
maxMana = 0
MT:Draw(now)
check("no mana (warrior, rogue): hidden", not ov:IsShown())
maxMana = 10000
CT:SetEnabled("GENERAL", "manaTick", false)
MT:Draw(now)
check("option off: hidden", not ov:IsShown())
CT:SetEnabled("GENERAL", "manaTick", true)
MT:Test()
mana = maxMana
MT:Draw(now)
check("test shows it even at full mana", ov:IsShown())
MT:EndTest()

-- ---- Off and on ----
WM:SetModuleOn("ClassTools", false)
check("Class Tools off: the part is off", not WM:IsModuleOn("ManaTick"))
check("off: hidden and forgotten", not ov:IsShown() and MT.lastTick == nil)
now = now + 1; mana = 100
Event("UNIT_POWER_FREQUENT", "player", "MANA")
check("off: mana not read", MT.lastTick == nil)
WM:SetModuleOn("ClassTools", true)
check("on again", WM:IsModuleOn("ManaTick"))
Power(200)
now = now + 2; Power(300)
check("on: reading again", MT.lastTick ~= nil)

-- ---- Reset ----
env.ManaTickDB.x, env.ManaTickDB.y = 10, 20
MT:ResetPosition()
check("reset: own bar's spot forgotten", env.ManaTickDB.x == nil and env.ManaTickDB.y == nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
