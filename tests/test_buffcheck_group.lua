-- Buff Check's Group list in its window: a row per member with their
-- GearScore (with GearScore on) and what they were missing at the last
-- check, sorting, the inspect button, and refreshing after a check.
-- Usage: lua5.1 test_buffcheck_group.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local units = {
    raid1 = { name = "Tanky", class = "WARRIOR", auras = { "Well Fed" } },
    raid2 = { name = "Healy", class = "PRIEST", auras = {} },
    raid3 = { name = "Zappy", class = "MAGE", auras = { "Enlightened" } },
}
env.IsInRaid = function() return true end
env.IsInGroup = function() return true end
env.GetNumGroupMembers = function() return 3 end
env.UnitExists = function(u) return units[u] ~= nil end
env.UnitName = function(u) return units[u] and units[u].name end
env.UnitClass = function(u) local c = units[u] and units[u].class; return c, c end
env.UnitIsConnected = function() return true end
env.UnitIsDeadOrGhost = function() return false end
env.UnitBuff = function(u, i) return units[u] and units[u].auras[i] end
env.SendChatMessage = function() end
env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/BuffCheck.lua" }) do W.load(f) end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
local BC = WM.modules.BuffCheck
BC:InitDB()
for k in pairs(env.BuffCheckDB.checkedGroups) do env.BuffCheckDB.checkedGroups[k] = false end
env.BuffCheckDB.checkedGroups.wellfed = true

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Said(text)
    for i = #W.printed, 1, -1 do if tostring(W.printed[i]):find(text, 1, true) then return true end end
end

local p = BC:CreateUI()
p:Show()
p:Refresh()
local function Row(name)
    for _, row in ipairs(p.groupRows) do
        if not row.hidden and (row.frame.nameText:GetText() or ""):find(name, 1, true) then return row.frame end
    end
end
check("a row per member", Row("Tanky") and Row("Healy") and Row("Zappy") and p.groupRows[4].hidden)
check("before a check: not checked yet", Row("Healy").missText:GetText():find("not checked yet", 1, true))
check("GearScore off: a dash", Row("Tanky").gsText:GetText():find("-", 1, true) ~= nil)
check("note says how to get the column", (function()
    for _, w in ipairs(p.layout.widgets) do
        local t = w.GetText and w:GetText()
        if t and t:find("Turn on GearScore for a GearScore column", 1, true) then return true end
    end
end)())

BC:RunLocalCheck()
check("after a check: the list refreshes", Row("Healy").missText:GetText():find("Food Buff", 1, true)
    and Row("Tanky").missText:GetText():find("all buffs up", 1, true))

-- GearScore on: the column fills in
local inspected = 0
WM.modules.GearScore = {
    GroupList = function() return { { name = "Tanky", score = 2100 }, { name = "Zappy", score = 1700 }, { name = "Healy" } } end,
    ColorText = function(score, text) return "<" .. text .. ">" end,
    ScanGroup = function() inspected = inspected + 1; return 1 end,
}
p:Refresh()
check("GearScore column", Row("Tanky").gsText:GetText() == "<2100>" and Row("Healy").gsText:GetText():find("?", 1, true))
env.BuffCheckDB.groupSort = "gs"
p:Refresh()
check("sorted by GearScore", p.groupRows[1].frame.nameText:GetText():find("Tanky", 1, true)
    and p.groupRows[2].frame.nameText:GetText():find("Zappy", 1, true))
local inspectBtn
for _, w in ipairs(p.layout.widgets) do if w.GetText and w:GetText() == "Inspect for GearScores" then inspectBtn = w end end
W.click(inspectBtn)
check("inspect button asks GearScore", inspected == 1 and Said("Inspecting 1 players"))
WM.modules.GearScore = nil
W.printed = {}
W.click(inspectBtn)
check("inspect without GearScore says so", Said("Turn on GearScore"))

-- Fewer members: rows hide
units.raid3 = nil
env.GetNumGroupMembers = function() return 2 end
p:Refresh()
check("rows follow the group", Row("Zappy") == nil and not p.groupRows[2].hidden and p.groupRows[3].hidden)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
