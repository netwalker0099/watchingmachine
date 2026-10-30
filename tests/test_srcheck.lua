-- Black Temple shadow resist gear check (Debuff Tracker): gear SR read from
-- item stats and tooltips, so gems and enchants count.
-- Usage: lua5.1 test_srcheck.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/DebuffTracker.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local DT = WM.modules.DebuffTracker
DT:InitDB()
local DB = env.DebuffTrackerDB
check("check on by default", DB.srCheck == true)

-- ---- one tooltip line ----
local Line = DT.ShadowResistFromLine
check("item stat line", Line("+40 Shadow Resistance") == 40)
check("Void Sphere gem line", Line("+4 Resist All") == 4)
check("all resistances enchant", Line("+5 All Resistances") == 5)
check("to all resistances", Line("+10 to All Resistances") == 10)
check("active socket bonus", Line("Socket Bonus: +4 Shadow Resistance", 1, 1, 1) == 4)
check("grey (inactive) socket bonus ignored", Line("Socket Bonus: +4 Shadow Resistance", 0.5, 0.5, 0.5) == 0)
check("other school ignored", Line("+40 Fire Resistance") == 0)
check("nil line", Line(nil) == 0)

-- ---- equipped gear ----
local gear = {}       -- slot -> { link, stats, lines }
env.GetInventoryItemLink = function(_, slot) return gear[slot] and gear[slot].link end
env.GetItemStats = function(link)
    for _, g in pairs(gear) do if g.link == link then return g.stats end end
end
local white = { r = 1, g = 1, b = 1 }
local function Lines(...)
    local out = {}
    for _, t in ipairs({ ... }) do out[#out + 1] = { leftText = t, leftColor = white } end
    return out
end
env.C_TooltipInfo = {
    GetInventoryItem = function(_, slot)
        return gear[slot] and { lines = gear[slot].lines }
    end,
}

-- Base SR plus three Void Spheres: GetItemStats sees only the 40
gear[5] = { link = "[Chest]", stats = { RESISTANCE5_NAME = 40 },
    lines = Lines("Chest", "+40 Shadow Resistance", "+4 Resist All", "+4 Resist All", "+4 Resist All") }
-- Rings whose SR the item stats don't report at all
gear[11] = { link = "[Dark Band of Healing]", stats = {},
    lines = Lines("Dark Band of Healing", "+20 Shadow Resistance") }
gear[12] = { link = "[Dark Band of Power]", stats = {},
    lines = Lines("Dark Band of Power", "+20 Shadow Resistance") }
-- A normal piece
gear[1] = { link = "[Helm]", stats = { ITEM_MOD_STAMINA_SHORT = 30 }, lines = Lines("Helm", "+30 Stamina") }

local total, pieces, detail = DT:GetGearShadowResist()
check("gems counted on top of the item's SR", detail[1] and detail[1].slot == 5 and detail[1].sr == 52)
check("tooltip-only rings counted", total == 92 and pieces == 3)

-- No tooltip API: the item stats still work
env.C_TooltipInfo = false
total, pieces = DT:GetGearShadowResist()
check("falls back to item stats", total == 40 and pieces == 1)

-- Old-style scanning tooltip (no C_TooltipInfo)
local function FS(text, grey)
    local f = W.NewFrame()
    f:SetText(text)
    f.GetTextColor = function() if grey then return 0.5, 0.5, 0.5 end return 1, 1, 1 end
    return f
end
local tipLines = {}
W.Frame.NumLines = function() return #tipLines end
W.Frame.SetInventoryItem = function(self, _, slot)
    local g = gear[slot]
    tipLines = {}
    if slot == 5 then
        tipLines = { FS("Chest"), FS("+40 Shadow Resistance"), FS("+4 Resist All"),
            FS("Socket Bonus: +4 Shadow Resistance", true) }
    end
    for i = 1, 10 do env["WM_SRScanTooltipTextLeft" .. i] = tipLines[i] end
    return self
end
total = DT:GetGearShadowResist()
check("scanning tooltip: gem counted, grey bonus not", total == 44)

-- ---- arming and warning ----
local inGroup = false
env.IsInGroup = function() return inGroup end
env.IsInRaid = function() return inGroup end
local timers = {}
WM.RunAfter = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end
local function RunTimers()
    while #timers > 0 do table.remove(timers, 1).fn() end
end
local warned
DT.WarnShadowResist = function(_, t, p) warned = { t, p } end
env.C_TooltipInfo = {
    GetInventoryItem = function(_, slot) return gear[slot] and { lines = gear[slot].lines } end,
}
DT:ResetShadowResistCheck()
DT:CheckShadowResistGear()
check("not armed: no warning", warned == nil)
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Mother Shahraz")
check("Mother's death arms it", DT:IsShadowResistArmed())
DT:CheckShadowResistGear()
check("armed with SR gear on: warns", warned and warned[1] == 92 and warned[2] == 3)

warned = nil
DT:ResetShadowResistCheck()
DT:HandleShadowResistCombatLog("SWING_DAMAGE", "Me", "Illidari Archon")
check("engaging a trigger mob arms and warns", DT:IsShadowResistArmed() and warned ~= nil)

warned = nil
gear[5], gear[11], gear[12] = nil, nil, nil
DT:CheckShadowResistGear()
check("SR gear off: no warning", warned == nil)
check("solo: no raid scan scheduled", #timers == 0)

-- ---- raid-wide check ----
-- Me (leader, clean), Addonuser (replies 180), Inspected (SR gems, in
-- range), Faraway (out of range), Gone (offline)
inGroup = true
local roster = { "Me", "Addonuser", "Inspected", "Faraway", "Gone" }
env.GetNumGroupMembers = function() return #roster end
env.UnitName = function(u)
    if u == "player" then return "Me" end
    local i = tonumber(tostring(u):match("^raid(%d+)$"))
    return i and roster[i]
end
env.UnitGUID = function(u) return "GUID-" .. tostring(env.UnitName(u)) end
env.UnitIsConnected = function(u) return env.UnitName(u) ~= "Gone" end
env.CheckInteractDistance = function(u) return env.UnitName(u) ~= "Faraway" end
env.InCombatLockdown = function() return false end
env.CanInspect = function() return true end
env.UnitIsGroupLeader = function(u) return u == "player" end
env.UnitIsGroupAssistant = function() return false end
env.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
env.GetTime = function() return 1000 end
local inspected, sent, chat = {}, {}, {}
env.NotifyInspect = function(u) inspected[#inspected + 1] = env.UnitName(u) end
env.ClearInspectPlayer = function() end
env.InspectFrame = false                 -- no inspect window open
env.C_ChatInfo = { SendAddonMessage = function(p, m, c) sent[#sent + 1] = { p, m, c } end }
env.SendChatMessage = function(m, c) chat[#chat + 1] = { m, c } end
printed = {}
env.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
local function has(s) for _, l in ipairs(printed) do if l:find(s, 1, true) then return true end end end

-- raid3's gear (read once it's inspected)
local inspectGear = { [5] = { link = "[Robe]", stats = {}, lines = Lines("Robe", "+60 Shadow Resistance", "+4 Resist All") } }
env.GetInventoryItemLink = function(u, slot)
    local g = (u == "player") and gear or (u == "raid3" and inspectGear or {})
    return g[slot] and g[slot].link
end
env.C_TooltipInfo = { GetInventoryItem = function(u, slot)
    local g = (u == "player") and gear or (u == "raid3" and inspectGear or {})
    return g[slot] and { lines = g[slot].lines }
end }
env.GetItemStats = function() return {} end

DT:ResetShadowResistCheck()
DB.srRaidChannel = "RAID"
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Mother Shahraz")
check("Mother's death only arms it", DT:IsShadowResistArmed() and #sent == 0 and #timers == 0)
DT:ResetShadowResistPull()               -- next pull: a Promenade pack
local combat = true
env.InCombatLockdown = function() return combat end
DT:HandleShadowResistCombatLog("SPELL_DAMAGE", "Me", "Promenade Sentinel")
check("engaging a pack: no raid check in combat", #sent == 0 and not DT:IsRaidShadowResistScanning())
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Promenade Sentinel")
check("a pack mob dies in combat: the check waits", #sent == 0 and DT:IsRaidShadowResistQueued())
combat = false
DT:RunQueuedShadowResistScan()           -- combat over
check("combat over: asks addon users first", sent[1] and sent[1][1] == "WMSR" and sent[1][2] == "Q"
    and sent[1][3] == "RAID" and not DT:IsRaidShadowResistQueued())
DT:OnShadowResistMessage("R:180:6", "Addonuser-Spineshatter")
table.remove(timers, 1).fn()             -- reply wait over: inspect starts
check("waits for INSPECT_READY", inspected[1] == "Inspected" and DT:IsRaidShadowResistScanning())
DT:OnShadowResistInspectReady("GUID-Someone-else")
check("ignores another addon's inspect", DT:IsRaidShadowResistScanning() and #timers == 1)
DT:OnShadowResistInspectReady("GUID-Inspected")
RunTimers()
check("addon users aren't inspected", #inspected == 1)
check("scan finished", not DT:IsRaidShadowResistScanning())
check("lists who is still in SR gear, highest first", has("Still in SR gear (2):|r Addonuser (180), Inspected (64)"))
check("lists who couldn't be checked", has("Faraway") and has("Gone (offline)"))
check("leader is clean, not listed", not has("Me ("))
check("announces to the chosen channel", chat[1] and chat[1][2] == "RAID"
    and chat[1][1] == "Still in SR gear: Addonuser, Inspected - swap out!")

-- Once per pull, again on the next pack
sent = {}
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Promenade Sentinel")
DT:RunQueuedShadowResistScan()
check("only once per pull", #sent == 0)
DT:ResetShadowResistPull()
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Illidari Archon")
check("a death out of combat checks at once", #sent == 1 and DT:IsRaidShadowResistScanning())
RunTimers()
check("second scan finishes", not DT:IsRaidShadowResistScanning())
sent = {}
DT:ResetShadowResistPull()
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Some Other Mob")
check("other mobs dying: nothing", #sent == 0 and not DT:IsRaidShadowResistQueued())

-- Not leader or assist: no automatic check, but the manual one still works
sent = {}
DT:ResetShadowResistPull()
env.UnitIsGroupLeader = function() return false end
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Promenade Sentinel")
check("raider: no automatic raid check", #sent == 0)
DB.srRaidCheck = false
DT:ResetShadowResistPull()
env.UnitIsGroupLeader = function(u) return u == "player" end
DT:HandleShadowResistCombatLog("UNIT_DIED", nil, "Promenade Sentinel")
check("setting off: no automatic raid check", #sent == 0 and not DT:IsRaidShadowResistQueued())

-- /wmachine srraid in combat: runs when combat ends, even with the setting off
local told
local realDTPrint = DT.Print
DT.Print = function(_, msg) told = msg end
combat = true
DT:StartRaidShadowResistScan(false)
DT.Print = realDTPrint
check("manual check in combat: says it waits", told and told:find("runs as soon as combat ends", 1, true)
    and #sent == 0 and DT:IsRaidShadowResistQueued())
combat = false
DT:RunQueuedShadowResistScan()
check("manual check runs after combat", #sent == 1 and DT:IsRaidShadowResistScanning())
RunTimers()

-- Answering someone else's check
sent = {}
gear[5] = { link = "[Chest]", stats = { RESISTANCE5_NAME = 40 }, lines = Lines("Chest", "+40 Shadow Resistance") }
DT:OnShadowResistMessage("Q", "Leader-Spineshatter")
check("replies with own gear", sent[1] and sent[1][2] == "R:40:1" and sent[1][3] == "RAID")
DT:OnShadowResistMessage("Q", "Other-Spineshatter")
check("one reply per few seconds", #sent == 1)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
