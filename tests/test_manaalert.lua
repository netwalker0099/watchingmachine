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
-- 2.5.6 has only the namespaced item functions; the old globals are gone
-- (their fallback for GetItemCooldown is nil), so don't provide them
local NAMES = { [22832] = "Super Mana Potion", [13444] = "Major Mana Potion", [12662] = "Demonic Rune",
    [20520] = "Dark Rune", [32902] = "Bottled Nethergon Energy" }
env.C_Item = {
    GetItemCount = function(id) return bags[id] or 0 end,
    IsUsableItem = function(id) if usable[id] == false then return false, false end; return true, false end,
    GetItemInfo = function(id) return NAMES[id] end,
    GetItemIconByID = function(id) return "icon" .. id end,
}
env.C_Container = {
    GetItemCooldown = function(id) local c = cooldowns[id]; if c then return 100, c, 1 end; return 0, 0, 1 end,
}
for _, n in ipairs({ "GetItemCount", "GetItemCooldown", "IsUsableItem", "GetItemInfo", "GetItemIcon" }) do
    env[n] = false
end

W.load("Core.lua")
W.load("UI.lua")
W.load("Sounds.lua")
W.load("Modules/ClassTools.lua")
W.load("Modules/ClassGeneral.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local CT, Gen = WM.modules.ClassTools, WM.modules.ClassGeneral

local alerts, icons, sounds, monitor = {}, {}, {}, nil
local realSetAlert, realClearAlert = CT.SetAlert, CT.ClearAlert
CT.SetAlert = function(_, key, text, icon, sound, channel) alerts[key] = text; icons[key] = icon; sounds[key] = { sound, channel } end
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

-- ---- a missed warning says why, once per reason ----
local said = {}
local realPrint = Gen.Print
Gen.Print = function(_, msg) said[#said + 1] = msg end
Gen.ResetSkipNotes()
Reset()
mana = maxMana - 3500; Tick()
check("no potions: says so", #said == 1 and said[1]:find("no mana potion found", 1, true))
Tick(); Tick()
check("only once", #said == 1)
bags[22832] = 5; cooldowns[22832] = 120; Tick()
check("pre-pull potion cooldown: says so", #said == 2 and said[2]:find("on cooldown", 1, true))
cooldowns[22832] = nil
mana = maxMana - 1000; Tick()
check("under the threshold: nothing said", #said == 2)
mana = maxMana - 3500
env.GeneralChecksDB.only25 = true
env.GetInstanceInfo = function() return nil, nil, nil, nil, 10 end; Tick()
check("25-man only in a 10-man: says so", #said == 3 and said[3]:find("reports 10 players", 1, true))
env.GetInstanceInfo = function() return nil, nil, nil, nil, 25 end
Gen.Print = realPrint

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

-- ---- sounds ----
local played = {}
env.PlaySoundFile = function(path, channel) played[#played + 1] = { "file", path, channel } end
env.PlaySound = function(id, channel) played[#played + 1] = { "kit", id, channel } end
check("default sounds: potion and rune", env.GeneralChecksDB.potionSound == "wm:potion"
    and env.GeneralChecksDB.runeSound == "wm:rune" and env.GeneralChecksDB.soundChannel == "Master")
Reset()
bags[22832] = 5; bags[12662] = 2
mana = maxMana - 4500; Tick()
check("potion warning carries its sound", sounds.gen_mana_potion[1] == "wm:potion" and sounds.gen_mana_potion[2] == "Master")
cooldowns[22832] = 120; Tick()
mana = maxMana - 2000; Tick()
check("rune warning carries its sound", sounds.gen_mana_rune and sounds.gen_mana_rune[1] == "wm:rune")
check("sound options are dropdowns", kinds.potionSound == "choice" and kinds.runeSound == "choice"
    and kinds.soundChannel == "choice")
local feature = {}
for _, f in ipairs(CT:GetFeatures("GENERAL")) do feature[f.key] = f end
check("sound list offers both sounds and game sounds", (function()
    local have = {}
    for _, o in ipairs(feature.potionSound.options) do have[o.value] = true end
    return have["wm:potion"] and have["wm:rune"] and have["kit:8959"] and have.none
end)())
played = {}
feature.potionSound.set("kit:8959"); feature.potionSound.onChange("kit:8959")
check("picking a sound plays it (the test button)", played[1] and played[1][1] == "kit" and played[1][2] == 8959)
check("and saves it", env.GeneralChecksDB.potionSound == "kit:8959")
feature.potionSound.set("wm:potion")
-- The real warning frame plays the chosen sound once, when the warning first appears
CT.SetAlert, CT.ClearAlert = realSetAlert, realClearAlert
local now = 1000
env.GetTime = function() return now end
played = {}
CT:SetAlert("gen_mana_potion", "Use a mana potion", "icon", "wm:potion", "Master")
check("plays the addon's file", played[1] and played[1][1] == "file"
    and played[1][2] == "Interface\\AddOns\\WatchingMachine\\Media\\Sounds\\potion.ogg" and played[1][3] == "Master")
CT:SetAlert("gen_mana_potion", "Use a mana potion", "icon", "wm:potion", "Master")
check("not again while the warning stays up", #played == 1)
CT:ClearAlert("gen_mana_potion")
now = now + 1
CT:SetAlert("gen_mana_potion", "Use a mana potion", "icon", "wm:potion", "Master")
check("not again within a few seconds", #played == 1)
CT:ClearAlert("gen_mana_potion")
now = now + 10
CT:SetAlert("gen_mana_potion", "Use a mana potion", "icon", "wm:potion", "SFX")
check("again when it comes back later, on the chosen channel", #played == 2 and played[2][3] == "SFX")
CT:ClearAlert("gen_mana_potion")
env.ClassToolsDB.alertSound = true
now = now + 10
CT:SetAlert("gen_mana_rune", "Use a rune", "icon", "wm:rune", "Master")
check("its own sound replaces the shared warning sound", #played == 3 and played[3][2]:find("rune.ogg", 1, true))
CT:ClearAlert("gen_mana_rune")
now = now + 10
CT:SetAlert("gen_mana_rune", "Use a rune", "icon", "none", "Master")
check("None: silent, even with the shared sound on", #played == 3)
CT:ClearAlert("gen_mana_rune")

-- ---- Per-warning sounds (Warning sounds section) ----
now = now + 10
CT:SetAlert("gen_flask", "No flask", "icon")
check("no choice: the shared warning sound", #played == 4 and played[4][1] == "kit" and played[4][2] == 8959)
CT:ClearAlert("gen_flask")
CT:SetAlertSound("gen_flask", "wm:rune")
now = now + 10
CT:SetAlert("gen_flask", "No flask", "icon")
check("a chosen sound for that warning", #played == 5 and played[5][2]:find("rune.ogg", 1, true)
    and played[5][3] == env.GeneralChecksDB.soundChannel)
CT:ClearAlert("gen_flask")
CT:SetAlertSound("gen_flask", "none")
now = now + 10
CT:SetAlert("gen_flask", "No flask", "icon")
check("None for that warning: silent", #played == 5)
CT:ClearAlert("gen_flask")
CT:SetAlertSound("gen_flask", "shared")
check("back to shared clears the choice", CT:AlertSound("gen_flask") == nil and env.ClassToolsDB.alertSounds.gen_flask == nil)
local keys = {}
for _, d in ipairs(CT:GetAlertSoundDefs()) do keys[d.key] = d.class end
check("General warnings offer a sound", keys.gen_flask == "GENERAL" and keys.gen_food == "GENERAL" and keys.gen_oil == "GENERAL")
-- The Class Tools window lists them
local panel = CT:CreateUI()
check("Warning sounds section built", panel.layout.sections and panel.layout.sections.sounds ~= nil)
check("bad choices play nothing", not WM.Sounds.Play("wm:../x") and not WM.Sounds.Play(nil) and not WM.Sounds.Play("none"))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
