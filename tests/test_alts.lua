-- Your Characters (AltTracker): saving the character, rested XP while
-- logged out, realm gold, the window. Usage: lua5.1 test_alts.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
local name, realm, class, level = "Tanky", "Spineshatter", "WARRIOR", 45
env.UnitName = function(u) if u == "player" then return name end; if u == "pet" then return "Fang" end end
env.GetRealmName = function() return realm end
env.UnitClass = function(u) if u == "player" then return class, class end end
env.UnitLevel = function(u) if u == "pet" then return 44 end; return level end
env.UnitFactionGroup = function() return "Alliance" end
local xp, xpMax, rested, resting = 20000, 80000, 40000, true
env.UnitXP = function() return xp end
env.UnitXPMax = function() return xpMax end
env.GetXPExhaustion = function() return rested end
env.IsResting = function() return resting end
local money = 1234567
env.GetMoney = function() return money end
env.C_Container = {
    GetContainerNumSlots = function(bag) return bag <= 4 and 16 or 0 end,
    GetContainerNumFreeSlots = function(bag) if bag == 4 then return 10, 1 end; return 3, 0 end,   -- bag 4: a quiver
}
local dura = { [1] = { 50, 100 }, [5] = { 10, 100 }, [16] = { 90, 100 } }
env.GetInventoryItemDurability = function(slot) local d = dura[slot]; if d then return d[1], d[2] end end
local skills = {
    { "Professions", true }, { "Mining", false, 300, 300 }, { "Blacksmithing", false, 275, 300 },
    { "Secondary Skills", true }, { "First Aid", false, 150, 225 },
    { "Weapon Skills", true }, { "Swords", false, 220, 225 },
}
env.GetNumSkillLines = function() return #skills end
env.GetSkillLineInfo = function(i) local s = skills[i]; return s[1], s[2], true, s[3], 0, 0, s[4] end
local items = {}
env.C_Item = { GetItemCount = function(id) return items[id] or 0 end }
env.GetItemInfo = function() return nil end
local petOut = false
env.UnitExists = function(u) return u == "player" or (u == "pet" and petOut) end
env.UnitCreatureFamily = function() return "Wolf" end
env.GetPetHappiness = function() return 3 end
env.GetInventorySlotInfo = function(s) if s == "AmmoSlot" then return 0 end end
env.GetInventoryItemCount = function(_, slot) if slot == 0 then return 1800 end end
env.GetZoneText = function() return "Ironforge" end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/AltTracker.lua")
local WM = W.WM
local Alts = WM.modules.AltTracker
env.WatchingMachineDB = { theme = "Default" }
Alts:Initialize()

local pass, fail = 0, 0
local function check(name_, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name_, "\n") end
end

local c = Alts.DB().chars["Tanky-Spineshatter"]
check("character saved on login", c and c.name == "Tanky" and c.realm == "Spineshatter" and c.class == "WARRIOR")
check("level, XP, rested", c.level == 45 and c.xp == 20000 and c.xpMax == 80000 and c.rested == 40000 and c.resting == true)
check("gold", c.gold == 1234567)
check("bag space counts ordinary bags only", c.bagFree == 12 and c.bagTotal == 64)
check("durability: average and lowest", c.durability == 50 and c.durabilityLow == 10)
check("professions only, with ranks", #c.professions == 3 and c.professions[1].name == "Mining"
    and c.professions[2].rank == 275 and c.professions[3].name == "First Aid" and c.professions[3].max == 225)
check("faction and zone", c.faction == "Alliance" and c.zone == "Ironforge")
check("seen now", c.seen == now)

-- ---- A second character: a hunter with a pet ----
name, class, level = "Shooty", "HUNTER", 60
petOut = true
money = 50000
Alts:Update()
local h = Alts.DB().chars["Shooty-Spineshatter"]
check("hunter ammo", h.ammo == 1800)
check("hunter pet", h.pet and h.pet.name == "Fang" and h.pet.level == 44 and h.pet.family == "Wolf" and h.pet.happiness == 3)
-- A warlock alt on another realm, with shards
name, realm, class, level = "Locky", "Thunderstrike", "WARLOCK", 70
petOut = false
items[6265] = 12
money = 99990000
Alts:Update()
local w = Alts.DB().chars["Locky-Thunderstrike"]
check("class reagents counted", w.reagents[6265] == 12 and w.reagents[5565] == 0)
check("no ammo or pet for non-hunters", w.ammo == nil and w.pet == nil)

-- ---- Realm gold, order ----
check("gold per realm", Alts:RealmGold("Spineshatter") == 1234567 + 50000 and Alts:RealmGold("Thunderstrike") == 99990000)
local list = Alts:Characters()
check("sorted by realm, then level", list[1].name == "Shooty" and list[2].name == "Tanky" and list[3].name == "Locky")

-- ---- Rested XP while logged out ----
local t = Alts.DB().chars["Tanky-Spineshatter"]
now = now + 8 * 3600   -- 8 hours later, in an inn
check("rested grows 5% of a level per 8 hours in an inn", math.floor(Alts:RestedNow(t)) == 40000 + 4000)
t.resting = false
check("a quarter of that outside", math.floor(Alts:RestedNow(t)) == 40000 + 1000)
t.resting = true
now = now + 30 * 24 * 3600
check("capped at 1.5 levels", Alts:RestedNow(t) == 80000 * 1.5)
check("the character you're on uses the live value", Alts:RestedNow(Alts.DB().chars["Locky-Thunderstrike"]) == 40000)

-- ---- The window ----
Alts:Toggle()
local f = env.WM_AltTrackerFrame
check("window opens", f and f:IsShown())
local shown, realmRows, charRows = 0, 0, 0
for _, r in ipairs(f.rows) do
    if r:IsShown() then
        shown = shown + 1
        if r.realm then realmRows = realmRows + 1 end
        if r.char then charRows = charRows + 1 end
    end
end
check("a row per realm and per character", realmRows == 2 and charRows == 3)
check("realm row shows its gold", f.rows[1].realm == "Spineshatter" and f.rows[1].gold:GetText():find("128g", 1, true) ~= nil)
check("total gold in the footer", (f.totalText:GetText() or ""):find("10,127g", 1, true) ~= nil)
local tanky
for _, r in ipairs(f.rows) do if r.char and r.char.name == "Tanky" then tanky = r end end
check("rested shown for an alt below 70", tanky.rested:GetText():find("% rested", 1, true) ~= nil)
W.fire(tanky, "OnEnter")
check("hover works", true)
local confirmed
WM.Confirm = function(_, text, fn) confirmed = text; fn() end
W.fire(tanky, "OnClick", "RightButton")
check("right-click removes an alt (asks first)", confirmed:find("Remove Tanky", 1, true) and Alts.DB().chars["Tanky-Spineshatter"] == nil)
check("can't remove the character you're on", Alts:Delete("Locky-Thunderstrike") == false)
check("dashboard status", Alts:GetQuickStatus():find("2 characters", 1, true) ~= nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
