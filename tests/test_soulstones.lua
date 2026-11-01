-- Warlock: the Soulstones frame (every warlock in the group: who their
-- soulstone is on, its cooldown, or ready).
-- Usage: lua5.1 test_soulstones.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now, server = 100, 50000
env.GetTime = function() return now end
env.GetServerTime = function() return server end
local function Advance(s) now = now + s; server = server + s end

-- player = Me (warlock), raid2 = Otherlock (warlock), raid3 = Tank (warrior)
local roster = {
    player = { "Me", "WARLOCK" }, raid1 = { "Me", "WARLOCK" },
    raid2 = { "Otherlock", "WARLOCK" }, raid3 = { "Tank", "WARRIOR" },
}
local raid, group = true, true
env.IsInGroup = function() return group end
env.IsInRaid = function() return raid end
env.GetNumGroupMembers = function() return group and 3 or 0 end
env.UnitExists = function(u) return roster[u] ~= nil and (u == "player" or group) end
env.UnitName = function(u) return roster[u] and roster[u][1] end
env.UnitClass = function(u) local r = roster[u]; if r then return r[2], r[2] end end
env.UnitIsUnit = function(a, b) return env.UnitName(a) == env.UnitName(b) end
env.UnitIsConnected = function() return true end
env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
env.RAID_CLASS_COLORS = { WARLOCK = { r = 0.58, g = 0.51, b = 0.79 } }
local buffs = {}
env.UnitBuff = function(u, i)
    local b = buffs[u] and buffs[u][i]
    if b then return unpack(b) end
end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/ClassTools.lua", "Modules/ClassFlyout.lua", "Modules/ClassWarlock.lua" }) do
    W.load(f)
end
local WM = W.WM
local CT, Lock = WM.modules.ClassTools, WM.modules.ClassWarlock
env.WatchingMachineDB = { theme = "Default" }
CT:InitDB()
Lock:RegisterFeatures()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Rows() return Lock:StoneRows() end
local function Row(name)
    for _, r in ipairs(Rows()) do if r.text == name then return (r.right or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end end
end

check("on by default, not raid-only", CT:IsEnabled("WARLOCK", "soulstoneFrame") and not CT:IsEnabled("WARLOCK", "stoneRaidOnly"))
check("one row per warlock, sorted", #Rows() == 2 and Rows()[1].text == "Me" and Rows()[2].text == "Otherlock")
check("nothing seen yet: ready?", Row("Me") == "ready?" and Row("Otherlock") == "ready?")
check("class coloured", Rows()[1].r == 0.58)

-- Otherlock stones the tank: the combat log and the buff
Lock:OnCombatLog("SPELL_AURA_APPLIED", "Otherlock-Spineshatter", "Tank", "Soulstone Resurrection")
buffs.raid3 = { { "Soulstone Resurrection", "icon", 0, nil, 1800, now + 1800, "raid2" } }
check("on the tank, with its time left", Row("Otherlock") == "on Tank  30:00")
Advance(600)
check("time runs down", Row("Otherlock") == "on Tank  20:00")

-- The tank dies and takes the stone: the cooldown is what's left
buffs.raid3 = {}
check("used: cooldown", Row("Otherlock") == "cooldown 20:00")
Advance(1201)
check("cooldown over: ready", Row("Otherlock") == "ready")

-- Another warlock's stone isn't yours
Lock:OnCombatLog("SPELL_CAST_SUCCESS", "Me", "Tank", "Soulstone Resurrection")
check("only the aura counts, not the cast", Row("Me") == "ready?")
Lock:OnCombatLog("SPELL_AURA_APPLIED", "Me", "Tank", "Shadow Bolt")
check("other spells ignored", Row("Me") == "ready?")

-- After a /reload: learned from the buff (its caster and time left)
env.WarlockToolsDB.stones = {}
buffs.raid2 = { { "Soulstone Resurrection", "icon", 0, nil, 1800, now + 900, "player" } }
check("found from the buff: on Otherlock", Row("Me") == "on Otherlock  15:00")
buffs.raid2 = {}
check("its cast time worked out from the buff: cooldown", Row("Me") == "cooldown 15:00")
check("saved by server time", env.WarlockToolsDB.stones.Me and env.WarlockToolsDB.stones.Me.at == server - 900)

-- Raid-only, solo, option off
raid = false
CT:SetEnabled("WARLOCK", "stoneRaidOnly", true)
check("raid-only in a party: nothing", #Rows() == 0)
CT:SetEnabled("WARLOCK", "stoneRaidOnly", false)
raid = true
group = false
check("not in a group: nothing", #Rows() == 0)
group = true
CT:SetEnabled("WARLOCK", "soulstoneFrame", false)
check("option off: nothing", #Rows() == 0)
CT:SetEnabled("WARLOCK", "soulstoneFrame", true)

-- The frame
local f = Lock:CreateStoneFrame()
Lock:UpdateStones()
check("frame shows a row per warlock", f:IsShown() and f.rows[1]:IsShown() and f.rows[2]:IsShown()
    and not f.rows[3]:IsShown() and f.rows[2].text:GetText() == "Otherlock")
WM:SetModuleOn("ClassWarlock", false)
check("module off: hidden, and nothing to show", not f:IsShown() and #Rows() == 0)
WM:SetModuleOn("ClassWarlock", true)
check("module on: back", f:IsShown())

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
