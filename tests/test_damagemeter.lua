-- Damage Meter: reading the combat log (damage, absorbs, overkill, heals,
-- shields, friendly fire, pets, interrupts, dispels, deaths), fights and
-- segments, displays, threat, reports, the bar windows, menus, the
-- breakdown, turning it off and on, and its setup page.
-- Usage: lua5.1 test_damagemeter.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local clock = 100
env.GetTime = function() return clock end
env.GetServerTime = function() return 1800000000 + clock end
local ME, PARTY1, PET = "Player-1-00000001", "Player-1-00000002", "Pet-0-1-1-1-416-0000000001"
local MOB, MOB2 = "Creature-0-1-530-1-15550-0000000001", "Creature-0-1-530-1-17257-0000000002"
local guids = { player = ME, party1 = PARTY1, pet = PET }
local names = { player = "Mage", party1 = "Healer", pet = "Imp", target = "Attumen" }
local classes = { player = "MAGE", party1 = "PRIEST" }
env.UnitGUID = function(u) return guids[u] end
env.UnitName = function(u) return names[u] end
env.UnitClass = function(u) local c = classes[u]; if c then return c, c end end
env.GetPlayerInfoByGUID = function(g)
    if g == ME then return "Mage", "MAGE" elseif g == PARTY1 then return "Priest", "PRIEST" end
end
local grouped = true
env.IsInRaid = function() return false end
env.IsInGroup = function() return grouped end
local inCombat = {}
env.UnitAffectingCombat = function(u) return inCombat[u] == true end
local inside = false
env.IsInInstance = function() return inside, inside and "raid" or "none" end
env.GetInstanceInfo = function() return "Karazhan", "raid", 3, "10 Player", 10, 0, false, 532 end
env.GetRealZoneText = function() return "Karazhan" end
env.UnitHealth = function() return 4000 end
env.UnitHealthMax = function() return 8000 end
env.UnitIsFeignDeath = function() return false end
env.GetSpellTexture = function(id) return "icon" .. tostring(id) end
env.IsShiftKeyDown = function() return false end
env.StaticPopup_Show = false
local sent = {}
env.SendChatMessage = function(m, c, _, t) sent[#sent + 1] = { m, c, t } end
env.ToggleDropDownMenu = function() end
env.SlashCmdList = {}
env.UnitIsPlayer = function(u) return u == "target" and names.target == "Healer" end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/DamageMeter.lua", "Modules/DamageMeterUI.lua" }) do W.load(f) end
local WM = W.WM
local DM = WM.modules.DamageMeter
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- Setup page before the module has started ----
local function Page()
    local p = WM.UI:CreatePanel({ name = "WM_TestDMSetup" .. tostring(clock), title = "t" })
    local L, specs = p:NewPage().layout, {}
    for _, kind in ipairs({ "Checkbox", "Dropdown", "Slider", "EditBox" }) do
        local orig = L[kind]
        L[kind] = function(self, spec, ...)
            if type(spec.label) == "string" then specs[spec.label] = spec end
            return orig(self, spec, ...)
        end
    end
    local ok, err = pcall(DM.SetupPage, DM, L)
    if not ok then io.write("SetupPage error: ", tostring(err), "\n") end
    return ok and specs
end
local specs = Page()
check("setup page builds before the module starts", specs and not DM._wmStarted)
check("setup page: defaults filled", env.WMDamageMeterDB.keepSegments == 12 and #env.WMDamageMeterDB.windows == 1)
check("setup page: every control has a tooltip or is plain",
    specs["Show the windows only during a fight"].tooltip and specs["Bar height"].tooltip)
specs["Show the windows only during a fight"].set(true)
check("setup page: setting saved", env.WMDamageMeterDB.hideOutOfCombat == true
    and specs["Show the windows only during a fight"].get() == true)
specs["Show the windows only during a fight"].set(false)
specs["DPS over each player's active time"].set(true)
check("setup page: time mode", env.WMDamageMeterDB.timeMode == "activity")
specs["DPS over each player's active time"].set(false)

-- ---- Start ----
local evFrame
local origRegister = WM.RegisterEvents
WM.RegisterEvents = function(_, fr) evFrame = fr end
WM:StartModule("DamageMeter")
WM.RegisterEvents = origRegister
check("started", DM._wmStarted and evFrame ~= nil)
check("a window opens", env.WM_DamageMeterWindow1 and env.WM_DamageMeterWindow1:IsShown())

local ev = {}
env.CombatLogGetCurrentEventInfo = function() return unpack(ev, 1, 24) end
local function Log(...)
    ev = { ... }
    evFrame._scripts.OnEvent(evFrame, "COMBAT_LOG_EVENT_UNFILTERED")
end
local P_ME, P_PARTY, P_PET, ENEMY = 0x511, 0x512, 0x1111, 0xa48
local function Spell(src, srcName, flags, dst, dstName, dstFlags, id, name, amount, opts)
    opts = opts or {}
    Log(0, opts.sub or "SPELL_DAMAGE", false, src, srcName, flags, 0, dst, dstName, dstFlags, 0,
        id, name, 4, amount, opts.overkill or -1, 4, 0, 0, opts.absorbed or 0, opts.crit or false)
end
local function Swing(src, srcName, flags, dst, dstName, dstFlags, amount)
    Log(0, "SWING_DAMAGE", false, src, srcName, flags, 0, dst, dstName, dstFlags, 0, amount, -1, 1, 0, 0, 0, false)
end
local function HealEv(src, srcName, flags, dst, dstName, id, name, amount, over)
    Log(0, "SPELL_HEAL", false, src, srcName, flags, 0, dst, dstName, P_PARTY, 0, id, name, 2, amount, over or 0, 0, false)
end

-- ---- Fights ----
check("no fight yet", not DM:InFight() and DM:Segment("current") == nil)
HealEv(PARTY1, "Healer", P_PARTY, ME, "Mage", 25235, "Flash Heal", 1000)
check("a heal doesn't start a fight", not DM:InFight())
inCombat.player = true
Spell(ME, "Mage", P_ME, MOB, "Attumen", ENEMY, 27070, "Fireball", 3000, { crit = true })
check("hitting an enemy starts a fight", DM:InFight())
local seg = DM:Segment("current")
local me = seg.actors[ME]
check("damage counted", me.dmg == 3000 and me.n == "Mage" and me.c == "MAGE")
check("spell recorded", me.sp.Fireball.a == 3000 and me.sp.Fireball.h == 1 and me.sp.Fireball.c == 1 and me.sp.Fireball.id == 27070)
clock = clock + 2
Swing(ME, "Mage", P_ME, MOB, "Attumen", ENEMY, 500)
check("melee", me.dmg == 3500 and me.sp.Melee.a == 500)
Spell(ME, "Mage", P_ME, MOB, "Attumen", ENEMY, 27070, "Fireball", 2000, { absorbed = 400 })
check("absorbed damage counts", me.dmg == 5900)
Spell(ME, "Mage", P_ME, MOB, "Attumen", ENEMY, 27070, "Fireball", 2000, { overkill = 500 })
check("overkill counted outside instances", me.dmg == 7900)
inside = true
Spell(ME, "Mage", P_ME, MOB2, "Midnight", ENEMY, 27070, "Fireball", 2000, { overkill = 500 })
check("overkill left out in an instance", me.dmg == 9400)
inside = false
check("enemy damage taken", seg.enemies.Attumen == 7900 and seg.enemies.Midnight == 1500)
check("overall too", DM:Overall().actors[ME].dmg == 9400)

-- Pets
DM:ScanGroup()
Spell(PET, "Imp", P_PET, MOB, "Attumen", ENEMY, 27267, "Firebolt", 600)
check("pet damage counts for its owner", me.dmg == 10000 and me.sp["Firebolt (Imp)"].a == 600 and not seg.actors[PET])
local TOTEM, ELEM = "Creature-0-1-1-1-15439-1", "Creature-0-1-1-1-15438-1"
Log(0, "SPELL_SUMMON", false, ME, "Mage", P_ME, 0, TOTEM, "Fire Elemental Totem", 0x2111, 0, 2894, "Fire Elemental Totem", 4)
Log(0, "SPELL_SUMMON", false, TOTEM, "Fire Elemental Totem", 0x2111, 0, ELEM, "Greater Fire Elemental", 0x2111, 0, 32982, "x", 4)
Spell(ELEM, "Greater Fire Elemental", 0x2111, MOB, "Attumen", ENEMY, 13376, "Fire Blast", 100)
check("a totem's summon belongs to the totem's owner", me.dmg == 10100 and me.sp["Fire Blast (Greater Fire Elemental)"])
Spell("Creature-0-1-1-1-9-9", "Stray", 0x2148, MOB, "Attumen", ENEMY, 1, "x", 999)
check("someone else's pet isn't counted", me.dmg == 10100 and not seg.actors["Creature-0-1-1-1-9-9"])
Spell("Player-1-99", "Stranger", 0x548, MOB, "Attumen", ENEMY, 1, "x", 999)
check("players outside the group aren't counted", seg.actors["Player-1-99"] == nil)

-- Healing, overheal, shields, Prayer of Mending
HealEv(PARTY1, "Healer", P_PARTY, ME, "Mage", 25235, "Flash Heal", 2000, 500)
local pr = seg.actors[PARTY1]
check("effective healing and overheal", pr.heal == 1500 and pr.oh == 500 and pr.c == "PRIEST")
Log(0, "SPELL_ABSORBED", false, MOB, "Attumen", ENEMY, 0, ME, "Mage", P_ME, 0,
    29711, "Shadow Bolt", 32, PARTY1, "Healer", P_PARTY, 0, 25218, "Power Word: Shield", 2, 800)
check("a shield's absorb is the caster's healing", pr.heal == 2300 and pr.hp["Power Word: Shield"].a == 800)
Log(0, "SPELL_ABSORBED", false, MOB, "Attumen", ENEMY, 0, ME, "Mage", P_ME, 0,
    PARTY1, "Healer", P_PARTY, 0, 25218, "Power Word: Shield", 2, 300)
check("after a melee swing too", pr.heal == 2600)
Log(0, "SPELL_AURA_APPLIED", false, PARTY1, "Healer", P_PARTY, 0, ME, "Mage", P_ME, 0, 41635, "Prayer of Mending", 2, "BUFF")
HealEv(ME, "Mage", P_ME, ME, "Mage", 33110, "Prayer of Mending", 900)
check("Prayer of Mending's heal is the priest's", pr.heal == 3500 and (me.heal or 0) == 0)

-- Damage taken, friendly fire, interrupts, dispels
Swing(MOB, "Attumen", ENEMY, PARTY1, "Healer", P_PARTY, 1200)
check("damage taken", pr.tk == 1200 and pr.tf["Melee (Attumen)"].a == 1200)
Spell(ME, "Mage", P_ME, PARTY1, "Healer", P_PARTY, 27070, "Fireball", 300)
check("friendly fire isn't damage done", me.ff == 300 and me.dmg == 10100 and pr.tk == 1500)
Log(0, "SPELL_INTERRUPT", false, ME, "Mage", P_ME, 0, MOB, "Attumen", ENEMY, 0, 2139, "Counterspell", 64, 29711, "Shadow Bolt", 32)
check("interrupt", me.int == 1 and me.is["Shadow Bolt"] == 1)
Log(0, "SPELL_DISPEL", false, PARTY1, "Healer", P_PARTY, 0, ME, "Mage", P_ME, 0, 988, "Dispel Magic", 2, 30004, "Flame Wreath", 4, "DEBUFF")
check("dispel", pr.disp == 1 and pr.ds["Flame Wreath"] == 1)

-- A death and its log
HealEv(PARTY1, "Healer", P_PARTY, PARTY1, "Healer", 25235, "Flash Heal", 700)
clock = clock + 1
Spell(MOB, "Attumen", ENEMY, PARTY1, "Healer", P_PARTY, 29833, "Shadow Cleave", 5000, { crit = true })
Log(0, "UNIT_DIED", false, "", nil, 0, 0, PARTY1, "Healer", P_PARTY, 0)
check("death counted", pr.dth == 1 and #seg.deaths == 1)
local death = seg.deaths[1]
check("death log", death.n == "Healer" and death.killer == "Shadow Cleave (Attumen)" and #death.log >= 2
    and death.log[#death.log].crit and death.log[#death.log].hp == 50)
check("heals in the death log", (function() for _, e in ipairs(death.log) do if e.heal then return true end end end)())

-- ---- Displays ----
local rows = DM:Rows("damage", "current")
check("damage rows, biggest first", rows[1].name == "Mage" and rows[1].amount == 10100 and rows[1].pct == 100)
local dur = DM:Duration(seg)
check("DPS over the whole fight", math.abs(rows[1].rate - 10100 / dur) < 0.01)
check("damage text", DM.BY_KEY.damage.text(rows[1]):find("10.1K", 1, true) ~= nil)
check("healing rows", DM:Rows("heal", "current")[1].name == "Healer")
check("overheal rows", DM:Rows("overheal", "current")[1].amount == 500)
check("taken rows", DM:Rows("taken", "current")[1].name == "Healer")
check("enemies rows", DM:Rows("enemies", "current")[1].name == "Attumen")
check("friendly fire rows", DM:Rows("ff", "current")[1].amount == 300)
check("interrupt rows", DM:Rows("interrupts", "current")[1].amount == 1)
check("death rows", DM:Rows("deaths", "current")[1].death == death)
local bd = DM:Breakdown("damage", rows[1])
check("breakdown: spells biggest first", bd[1].name == "Fireball" and bd[1].amount == 8900 and bd[1].hits == 4)
check("number format", DM.Short(999) == "999" and DM.Short(1234) == "1.2K" and DM.Short(123456) == "123K"
    and DM.Short(1234567) == "1.23M")

-- ---- Fight end, segments, naming ----
inCombat.player = false
DM:CheckFightEnd(1.5)
check("the fight ends when the group leaves combat", not DM:InFight())
check("named after the enemy hurt most", seg.name == "Attumen" and seg.time > 0)
check("overall time", DM:Overall().time == seg.time)
-- A boss fight
inCombat.player = true
evFrame._scripts.OnEvent(evFrame, "ENCOUNTER_START", 652, "Attumen the Huntsman", 3, 10)
check("a boss pull starts a fight", DM:InFight() and DM:Fight().boss and DM:Fight().name == "Attumen the Huntsman")
clock = clock + 10
Spell(ME, "Mage", P_ME, MOB, "Attumen", ENEMY, 27070, "Fireball", 4000)
inCombat.player = false
DM:CheckFightEnd(1.5)
check("a boss fight waits for the encounter's end", DM:InFight())
evFrame._scripts.OnEvent(evFrame, "ENCOUNTER_END", 652, "Attumen the Huntsman", 3, 10, 1)
check("boss fight ended and kept", not DM:InFight() and DM:Segment("current").name == "Attumen the Huntsman"
    and DM:Segment("current").killed and DM:Segment(2) == seg)
check("segment names", DM:SegmentName(2) == "#2 Attumen" and DM:SegmentName("overall") == "Overall")
check("overall adds both", DM:Overall().actors[ME].dmg == 14100)
-- A short trash fight in an instance isn't kept
inside = true
inCombat.player = true
Spell(ME, "Mage", P_ME, MOB2, "Midnight", ENEMY, 27070, "Fireball", 100)
clock = clock + 2
inCombat.player = false
DM:CheckFightEnd(1.5)
check("a fight under 5 seconds in an instance is dropped", #DM:History() == 2)
inside = false
-- Fights kept
env.WMDamageMeterDB.keepSegments = 3
for _ = 1, 3 do
    inCombat.player = true
    Spell(ME, "Mage", P_ME, MOB2, "Midnight", ENEMY, 27070, "Fireball", 100)
    clock = clock + 6
    inCombat.player = false
    DM:CheckFightEnd(1.5)
end
check("only the newest fights are kept", #DM:History() == 3 and DM:Segment(1).name == "Midnight")

-- ---- Threat ----
local threat = { player = { false, 1, 80, 70, 8000 }, party1 = { true, 3, 100, 100, 10000 } }
env.UnitDetailedThreatSituation = function(u) local t = threat[u]; if t then return unpack(t) end end
env.UnitExists = function(u) return u == "target" end
env.UnitCanAttack = function() return true end
env.UnitIsDead = function() return false end
local trows = DM:Rows("threat")
check("threat rows: tank first", trows[1].name == "Healer" and trows[1].tanking and trows[1].pct == 100
    and trows[2].pct == 80 and trows[2].amount == 80)
check("threat colour runs to red", select(2, DM.ThreatColor(100)) == 0 and select(1, DM.ThreatColor(0)) == 0)
env.UnitExists = function() return false end
check("no target, no threat", #DM:Rows("threat") == 0)
env.UnitExists = function(u) return u == "target" end

-- ---- Reports ----
DM:Report("damage", "overall", "PARTY")
check("report header and lines", sent[1][2] == "PARTY" and sent[1][1]:find("Damage Done: Overall", 1, true)
    and sent[2][1]:find("^1%. Mage"))
sent = {}
env.WMDamageMeterDB.reportLines = 1
DM:Report("heal", "overall", "")
check("report: default channel and line count", #sent == 2 and sent[1][2] == "PARTY")
env.WMDamageMeterDB.reportLines = 5

-- ---- Windows ----
local w1 = env.WM_DamageMeterWindow1
w1:SetSize(230, 18 + 4 + 8 * 17)
DM:SetWindowSegment(1, "overall")
check("window bars", w1.bars[1]:IsShown() and w1.bars[1].left:GetText() == "1. Mage" and w1.bars[1]._value == 1
    and w1.bars[1].right:GetText():find("14.", 1, true))
check("window title", w1.title.text:GetText():find("Damage - Overall", 1, true) ~= nil)
check("one player, one bar", not (w1.bars[2] and w1.bars[2]:IsShown()))
-- Display menu
local items = W.openMenu(DM:OpenMenu("display", 1))
local heal
for _, it in ipairs(items) do if it.text == "Healing Done" then heal = it end end
check("display menu lists the displays", heal ~= nil and #items >= 12)
heal.func()
check("choosing a display", env.WMDamageMeterDB.windows[1].display == "heal" and w1.bars[1].left:GetText() == "1. Healer")
local segItems = W.openMenu(DM:OpenMenu("segment", 1))
check("fight menu", segItems[2].text:find("Current fight", 1, true) and segItems[3].text == "Overall" and #segItems == 5)
segItems[2].func()
check("choosing a fight", env.WMDamageMeterDB.windows[1].segment == "current")
local repItems = W.openMenu(DM:OpenMenu("report", 1))
check("report menu", repItems[2].text == "Say" and #repItems == 8)
-- Bar tooltip and breakdown
DM:SetWindowSegment(1, "overall")
DM:SetWindowDisplay(1, "damage")
local tipLines = {}
env.GameTooltip.SetText = function(_, t) tipLines[#tipLines + 1] = t end
env.GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
w1.bars[1]._scripts.OnEnter(w1.bars[1])
check("bar tooltip lists spells", table.concat(tipLines, "\n"):find("Fireball", 1, true) ~= nil)
w1.bars[1]._scripts.OnMouseUp(w1.bars[1], "LeftButton")
local b = env.WM_DamageMeterBreakdown
check("click opens the breakdown", b and b:IsShown() and b.lines[1][2] == "Fireball")
DM:SetWindowDisplay(1, "deaths")
tipLines = {}
w1.bars[1]._scripts.OnEnter(w1.bars[1])
check("death tooltip", table.concat(tipLines, "\n"):find("killed by Shadow Cleave", 1, true) ~= nil)
w1.bars[1]._scripts.OnMouseUp(w1.bars[1], "LeftButton")
check("death breakdown", b.lines[1][2]:find("Shadow Cleave", 1, true) ~= nil)
-- Shift-click reports
sent = {}
env.IsShiftKeyDown = function() return true end
w1.bars[1]._scripts.OnMouseUp(w1.bars[1], "LeftButton")
check("shift-click reports", #sent > 0)
env.IsShiftKeyDown = function() return false end
-- New windows
local i2 = DM:NewWindow()
check("a new window", i2 == 2 and env.WM_DamageMeterWindow2:IsShown() and env.WMDamageMeterDB.windows[2].display == "damage")
DM:SetWindowDisplay(2, "threat")
check("threat window", env.WM_DamageMeterWindow2.bars[1].left:GetText():find("Healer", 1, true)
    and env.WM_DamageMeterWindow2.title.text:GetText() == "Threat - Attumen")
for _ = 3, DM.MAX_WINDOWS do DM:NewWindow() end
check("windows stop at the limit", DM:NewWindow() == nil and #env.WMDamageMeterDB.windows == DM.MAX_WINDOWS)
for k = DM.MAX_WINDOWS, 3, -1 do DM:DeleteWindow(k) end
check("delete windows", #env.WMDamageMeterDB.windows == 2 and not env.WM_DamageMeterWindow3:IsShown())
DM:CloseWindow(2)
check("close hides a window", not env.WM_DamageMeterWindow2:IsShown() and env.WMDamageMeterDB.windows[2].hidden)
DM:ToggleUI()
check("toggle hides the rest", not w1:IsShown())
DM:ToggleUI()
check("toggle brings them all back", w1:IsShown() and env.WM_DamageMeterWindow2:IsShown())
-- Only in combat
env.WMDamageMeterDB.hideOutOfCombat = true
DM:ShowWindows()
check("hidden out of combat", not w1:IsShown())
inCombat.player = true
Spell(ME, "Mage", P_ME, MOB2, "Midnight", ENEMY, 27070, "Fireball", 100)
check("shown when a fight starts", w1:IsShown())
check("a new fight puts windows back on the current one", env.WMDamageMeterDB.windows[1].segment == "overall")
env.WMDamageMeterDB.hideOutOfCombat = false
-- Lock
DM:Command("lock")
check("lock hides the grips", not w1.grip:IsShown() and env.WMDamageMeterDB.locked)
DM:Command("unlock")
check("unlock", w1.grip:IsShown() and not env.WMDamageMeterDB.locked)
-- Slash command
W.printed = {}
env.SlashCmdList.WATCHINGMACHINE("meter options")
check("/wmachine meter options", env.WM_DamageMeterOptions and env.WM_DamageMeterOptions:IsShown())
check("status line", DM:GetQuickStatus():find("Midnight", 1, true) ~= nil)

-- ---- Off means off ----
local before = DM:Overall().actors[ME].dmg
WM:SetModuleOn("DamageMeter", false)
check("off: every window hidden", not w1:IsShown() and not env.WM_DamageMeterWindow2:IsShown()
    and not env.WM_DamageMeterBreakdown:IsShown() and not env.WM_DamageMeterOptions:IsShown())
check("off: the fight is closed", not DM:InFight())
Spell(ME, "Mage", P_ME, MOB2, "Midnight", ENEMY, 27070, "Fireball", 100)
check("off: nothing counted", DM:Overall().actors[ME].dmg == before and not DM:InFight())
sent = {}
check("off: no reports", DM:Report("damage", "overall", "SAY") == false and #sent == 0)
DM:ToggleUI()
check("off: toggle does nothing", not w1:IsShown())
check("off: the driver is stopped", not DM.driver:IsShown())
WM:SetModuleOn("DamageMeter", true)
check("on again: windows back", w1:IsShown() and DM.driver:IsShown())
Spell(ME, "Mage", P_ME, MOB2, "Midnight", ENEMY, 27070, "Fireball", 100)
check("on again: counting", DM:Overall().actors[ME].dmg == before + 100)

-- ---- Reset ----
DM:Reset()
check("reset clears the fights", #DM:History() == 0 and not DM:InFight() and DM:Overall().actors[ME] == nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
