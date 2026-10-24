-- Your Characters across characters: on for one character, it still saves
-- the others you log in on (where its switch is off), so their gold, bags
-- and gear carry over; off for every character, nothing is saved.
-- Usage: lua5.1 test_alts_everychar.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local name, gold = "Main", 1000
env.UnitName = function() return name end
env.GetRealmName = function() return "Realm" end
env.GetMoney = function() return gold end
env.UnitLevel = function() return 70 end
env.UnitXP = function() return 0 end
env.UnitXPMax = function() return 1 end
env.SlashCmdList = {}
local bagItem = "|cff1eff00|Hitem:23424::::::::70:::::|h[Fel Iron Ore]|h|r"
env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerNumFreeSlots = function() return 0, 0 end,
    GetContainerItemInfo = function(bag, slot) if bag == 0 and slot == 1 then return { hyperlink = bagItem, stackCount = 5 } end end,
}
for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/AltTracker.lua" }) do W.load(f) end
local WM, P = W.WM, W.WM.Profiles
local Alts = WM.modules.AltTracker

local pass, fail = 0, 0
local function check(label, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", label, "\n") end
end

-- What the game saves and hands back at each login
local saved = { WatchingMachineDB = { theme = "Default" }, AltTrackerDB = {} }
local function Login(who)
    name = who
    for k, v in pairs(saved) do env[k] = v end
    P.profiles, P.stores, P.fresh = {}, {}, {}
    P:Load()
    WM:InitCharacter()
    Alts._wmStarted = nil
    if WM:ShouldRun("AltTracker") then WM:StartModule("AltTracker") end
end
local function Logout()
    for k in pairs(saved) do
        local t = rawget(env, k)
        if t then setmetatable(t, nil); saved[k] = t end
    end
end
local function Char(key) return Alts.DB().chars[key] end

-- A new install: the main turns Your Characters on
Login("Main")
WM:SetModuleOn("AltTracker", true)
Alts:Update()
check("main saved", Char("Main-Realm") and Char("Main-Realm").gold == 1000)
Logout()

-- An alt, new: everything off there, but Your Characters still saves it
gold = 250
Login("Alt")
check("alt: off on this character", not WM:IsModuleOn("AltTracker"))
check("alt: still saved, because it's on for the main", WM:ShouldRun("AltTracker") and Char("Alt-Realm")
    and Char("Alt-Realm").gold == 250 and #Char("Alt-Realm").bags == 1)
gold = 300
Alts:Update()
check("alt: changes saved", Char("Alt-Realm").gold == 300)
check("alt: the window stays off here", WM:UsableModule("AltTracker") == nil)
Logout()

-- Back on the main: the alt's latest gold and bags are there
gold = 1000
Login("Main")
check("main sees the alt's latest gold", Char("Alt-Realm").gold == 300 and Char("Alt-Realm").bags[1][1] == bagItem)
-- Turned off everywhere: nothing more is saved
WM:SetModuleOn("AltTracker", false)
Logout()
gold = 999
Login("Alt")
check("off for every character: the alt isn't saved", not WM:ShouldRun("AltTracker") and Char("Alt-Realm").gold == 300)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
