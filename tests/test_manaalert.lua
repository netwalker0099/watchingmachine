-- Mana potion / rune alert (Class Tools > General). Usage: lua5.1 test_manaalert.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- The player's state, driven by each test
local mana, maxMana, health, maxHealth = 10000, 10000, 8000, 8000
local powerType, inCombat = 0, true
local bags, cooldowns, usable = {}, {}, {}
env.UnitPower = function() return mana end
env.UnitPowerMax = function() return maxMana end
env.UnitPowerType = function() return powerType end
env.UnitHealth = function() return health end
env.UnitHealthMax = function() return maxHealth end
env.UnitAffectingCombat = function() return inCombat end
env.UnitIsDeadOrGhost = function() return false end
env.UnitBuff = function() return nil end   -- no buffs; only the mana alerts matter here
env.IsInInstance = function() return true, "raid" end
env.GetInstanceInfo = function() return nil, nil, nil, nil, 25 end
env.GetItemCount = function(id) return bags[id] or 0 end
env.GetItemCooldown = function(id) local c = cooldowns[id]; if c then return 100, c, 1 end; return 0, 0, 1 end
env.IsUsableItem = function(id) if usable[id] == false then return false end; return true end
local NAMES = { [22832] = "Super Mana Potion", [13444] = "Major Mana Potion", [12662] = "Demonic Rune",
    [20520] = "Dark Rune", [32902] = "Bottled Nethergon Energy" }
env.GetItemInfo = function(id) return NAMES[id] end
env.GetItemIcon = function(id) return "icon" .. id end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/ClassTools.lua")
W.load("Modules/ClassGeneral.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local CT, Gen = WM.modules.ClassTools, WM.modules.ClassGeneral

local alerts, icons, monitor = {}, {}, nil
CT.SetAlert = function(_, key, text, icon) alerts[key] = text; icons[key] = icon end
CT.ClearAlert = function(_, key) alerts[key] = nil end
CT.RegisterMonitor = function(_, fn) monitor = fn end
CT:InitDB()
Gen:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Tick() monitor() end
local function Potion() return alerts.gen_mana_potion end
local function Rune() return alerts.gen_mana_rune end
local function Reset() bags, cooldowns, usable = {}, {}, {}; mana = maxMana; Tick() end

check("monitor registered", monitor ~= nil)
check("defaults 3000 / 1500", env.GeneralChecksDB.potionAt == 3000 and env.GeneralChecksDB.runeAt == 1500)
check("both warnings on by default", CT:IsEnabled("GENERAL", "manapotion") and CT:IsEnabled("GENERAL", "manarune"))

-- ---- potion ----
bags[22832] = 5; bags[12662] = 2
mana = maxMana - 2999; Tick()
check("2999 down: no potion warning yet", Potion() == nil)
mana = maxMana - 3000; Tick()
check("3000 down: drink a potion", Potion() == "Use a mana potion (Super Mana Potion)")
check("uses the potion's icon", icons.gen_mana_potion == "icon22832")
check("no rune while a potion is ready", Rune() == nil)
mana = maxMana - 2700; Tick()
check("stays up while mana regens a little (hysteresis)", Potion() ~= nil)
mana = maxMana - 2400; Tick()
check("clears once 500 back under the threshold", Potion() == nil)
mana = maxMana - 2900; Tick()
check("doesn't come back until the threshold again", Potion() == nil)

-- ---- rune when the potion is on cooldown ----
cooldowns[22832] = 120
mana = maxMana - 1499; Tick()
check("potion on cooldown, 1499 down: nothing", Potion() == nil and Rune() == nil)
mana = maxMana - 1500; Tick()
check("potion on cooldown, 1500 down: use a rune", Rune() == "Potion on cooldown: use Demonic Rune")
check("rune icon", icons.gen_mana_rune == "icon12662")
mana = maxMana - 5000; Tick()
check("deep deficit with potion on cooldown: still the rune, not the potion", Potion() == nil and Rune() ~= nil)
cooldowns[12662] = 120
Tick()
check("rune on cooldown too: nothing to suggest", Rune() == nil)
bags[20520] = 1; Tick()
check("falls back to a Dark Rune", Rune() == "Potion on cooldown: use Dark Rune")
cooldowns[22832] = 1.0; Tick()
check("the global cooldown isn't a potion cooldown", Potion() ~= nil and Rune() == nil)

-- ---- no potions left ----
Reset()
bags[12662] = 1
mana = maxMana - 1600; Tick()
check("no potions carried: rune suggested", Rune() == "No mana potion: use Demonic Rune")
health = maxHealth * 0.30; Tick()
check("not below 35% health", Rune() == nil)
health = maxHealth; Tick()
check("back above: rune again", Rune() ~= nil)

-- ---- best potion first, zone potions only where usable ----
Reset()
bags[32902] = 3; bags[22832] = 5; bags[13444] = 5
usable[32902] = false     -- Bottled Nethergon outside Tempest Keep
mana = maxMana - 4000; Tick()
check("zone potion skipped where it can't be used", Potion() == "Use a mana potion (Super Mana Potion)")
usable[32902] = nil; Tick()
check("zone potion preferred where it works", Potion() == "Use a mana potion (Bottled Nethergon Energy)")

-- ---- when it runs ----
Reset()
bags[22832] = 5
mana = maxMana - 4000
inCombat = false; Tick()
check("out of combat: silent", Potion() == nil)
inCombat = true; Tick()
check("in combat: warns", Potion() ~= nil)
powerType = 1; Tick()
check("not a mana user (bear form): silent", Potion() == nil)
powerType = 0
CT:SetEnabled("GENERAL", "manapotion", false); Tick()
check("potion warning can be switched off", Potion() == nil)
CT:SetEnabled("GENERAL", "manapotion", true)
env.IsInInstance = function() return false, "none" end; Tick()
check("outside a raid instance: silent, like the other General checks", Potion() == nil)
env.IsInInstance = function() return true, "raid" end

-- ---- thresholds are options ----
env.GeneralChecksDB.potionAt = 4500
mana = maxMana - 4000; Tick()
check("raised threshold respected", Potion() == nil)
mana = maxMana - 4500; Tick()
check("...and reached", Potion() ~= nil)
local kinds = {}
for _, f in ipairs(CT:GetFeatures("GENERAL")) do kinds[f.key] = f.kind or "check" end
check("threshold options are choices", kinds.potionAt == "choice" and kinds.runeAt == "choice")

-- ---- /wmachine consumes explains it ----
W.printed = {}
Gen:Explain()
local out = table.concat(W.printed, "\n")
check("consumes shows the mana deficit", out:find("mana down by: 4500", 1, true) ~= nil)
check("consumes names the ready potion", out:find("Super Mana Potion", 1, true) ~= nil)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
