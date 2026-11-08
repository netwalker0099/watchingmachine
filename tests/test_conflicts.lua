-- Other addons doing a module's job: found only for modules that are on and
-- addons that are loaded, shown at login (unless kept or switched off), and
-- each button does what it says.
-- Usage: lua5.1 test_conflicts.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local loaded = { GTFO = true, RCLootCouncil_Classic = true, Questie = true }
local disabled = {}
env.C_AddOns = {
    IsAddOnLoaded = function(n) return loaded[n] or false end,
    GetAddOnInfo = function(n) return n, (n == "GTFO" and "|cff00ff00GTFO|r" or n) end,
    DisableAddOn = function(n, who) disabled[#disabled + 1] = { n, who } end,
}
local printed = {}
env.WatchingMachineDB = { theme = "Default" }
for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Conflicts.lua" }) do W.load(f) end
local WM = W.WM
WM.Print = function(_, msg) printed[#printed + 1] = msg end
local C = WM.Conflicts
-- Two modules standing in for the real ones
WM:RegisterModule("Hazards", {})
WM:RegisterModule("LootCouncil", {})
WM:RegisterModule("GearSets", {})
WM.MODULE_INFO = WM.MODULE_INFO or {}

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local list = C:Find(false)
check("both clashes found", #list == 2 and list[1].module == "Hazards" and list[1].addon == "GTFO"
    and list[2].module == "LootCouncil" and list[2].addon == "RCLootCouncil_Classic")
check("an addon that isn't loaded isn't one", (function() for _, c in ipairs(list) do if c.addon == "ItemRack" then return false end end return true end)())
check("the addon's title without colours", C.Title("GTFO") == "GTFO")

-- At login: the window
check("shown at login", C:CheckAtLogin() == 2 and env.WM_ConflictsFrame and env.WM_ConflictsFrame:IsShown())
local row = env.WM_ConflictsFrame.list.rows[1]
check("the row says what clashes", row.text:GetText():find("do the same job", 1, true) and row.text:GetText():find("alarm", 1, true))

-- Keep both: not asked again
C:Keep(list[1])
check("kept: not at login", #C:Find(false) == 1)
check("kept: still listed by the command", #C:Find(true) == 2 and C:Find(true)[1].kept)

-- Turn the module off
C:TurnOffModule(list[2])
check("module turned off", not WM:IsModuleOn("LootCouncil") and #C:Find(true) == 1)
WM:SetModuleOn("LootCouncil", true)

-- Disable the other addon (for this character)
C:DisableAddon(list[2])
check("addon disabled for this character", disabled[1] and disabled[1][1] == "RCLootCouncil_Classic" and disabled[1][2] == env.UnitName("player"))
check("reload offered", env.WM_ConflictsFrame.reloadBtn:IsShown())

-- A module that's off isn't one
WM:SetModuleOn("Hazards", false)
check("module off: no clash", (function() for _, c in ipairs(C:Find(true)) do if c.module == "Hazards" then return false end end return true end)())
WM:SetModuleOn("Hazards", true)

-- The warning switched off
env.WatchingMachineDB.conflictWarn = false
env.WM_ConflictsFrame:Hide()
check("warning off: nothing at login", C:CheckAtLogin() == 0 and not env.WM_ConflictsFrame:IsShown())
env.WatchingMachineDB.conflictWarn = nil

-- Nothing loaded: the command says so
loaded = {}
C:Command()
check("nothing to warn about", printed[#printed]:find("No other addon", 1, true) and not env.WM_ConflictsFrame:IsShown())

-- Every module named in the list exists in Watching Machine
local names = {}
for line in io.lines(REPO .. "/WatchingMachine.toc") do names[#names + 1] = line end
local text = table.concat(names, "\n")
for module in pairs(C.LIST) do
    local file = ({ GuildRoster = "GuildRoster", LootCouncil = "LootCouncil", Ogrila = "Ogrila" })[module] or module
    check("module " .. module .. " is in the toc", text:find("Modules/" .. file .. ".lua", 1, true) ~= nil)
end

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
