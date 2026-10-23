-- Your Characters: gear and GearScore, bags, keyring, bank, raid lockouts,
-- the item search across characters, and the flyout.
-- Usage: lua5.1 test_alts_gear.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
local name, class = "Tanky", "WARRIOR"
env.UnitName = function(u) if u == "player" then return name end end
env.GetRealmName = function() return "Spineshatter" end
env.UnitClass = function(u) return class, class end
env.UnitLevel = function() return 70 end
env.UnitFactionGroup = function() return "Horde" end
env.UnitXP = function() return 0 end
env.UnitXPMax = function() return 0 end
env.GetMoney = function() return 100 end
env.UnitExists = function() return false end
env.GetItemInfo = function() return nil end

local function L(id, name_) return "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[" .. name_ .. "]|h|r" end
local HELM, SWORD, POTION, KEY, ORE = L(28963, "Voidheart Crown"), L(29988, "The Nexus Key"), L(22829, "Super Healing Potion"),
    L(24490, "The Master's Key"), L(23424, "Fel Iron Ore")
local gear = { [1] = HELM, [16] = SWORD }
env.GetInventoryItemLink = function(_, slot) return gear[slot] end
local bags = { [0] = { POTION, ORE }, [1] = { ORE }, [-2] = { KEY }, [-1] = { ORE, POTION }, [5] = { HELM } }
local counts = { [POTION] = 5, [ORE] = 20 }
env.C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerNumFreeSlots = function() return 2, 0 end,
    GetContainerItemInfo = function(bag, slot)
        local link = bags[bag] and bags[bag][slot]
        if link then return { hyperlink = link, stackCount = counts[link] or 1, iconFileID = 1 } end
    end,
}
local saved = { { "Karazhan", 1, 3600 * 30, 3, true, false, 0, true, 10, "10 Player", 11, 4 },
    { "Old Raid", 2, 0, 3, false, false, 0, true, 25, "25 Player", 6, 6 } }
env.GetNumSavedInstances = function() return #saved end
env.GetSavedInstanceInfo = function(i) return unpack(saved[i]) end
local raidInfo = 0
env.RequestRaidInfo = function() raidInfo = raidInfo + 1 end
local items = { [28963] = { "Voidheart Crown", 4, 120, "INVTYPE_HEAD" }, [29988] = { "The Nexus Key", 4, 141, "INVTYPE_2HWEAPON" } }
env.C_Item = {
    GetItemInfo = function(link)
        local id = tonumber(tostring(link):match("item:(%d+)") or link)
        local i = items[id]
        if i then return i[1], link, i[2], i[3], 0, "", "", 1, i[4] end
    end,
    GetItemInfoInstant = function(link) return nil end,
    GetItemStats = function() return {} end,
    GetItemIconByID = function(id) return "icon" .. id end,
}

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/GearScore.lua", "Modules/AltTracker.lua",
    "Data/Attunements.lua", "Modules/Attunements.lua" }) do W.load(f) end
local WM = W.WM
local Alts = WM.modules.AltTracker
env.WatchingMachineDB = { theme = "Default" }
Alts:Initialize()

local pass, fail = 0, 0
local function check(name_, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name_, "\n") end
end

local c = Alts.DB().chars["Tanky-Spineshatter"]
-- ---- What's saved ----
check("raid info asked for at login", raidInfo == 1)
check("gear saved by slot", c.gear[1] == HELM and c.gear[16] == SWORD and c.gear[2] == nil)
check("GearScore saved", c.gearScore == select(1, WM.GearScore.GearScoreFor(gear, "WARRIOR")) and c.gearScore > 0 and c.avgIlvl > 0)
check("bags: links and counts", #c.bags == 3 and c.bags[1][1] == POTION and c.bags[1][2] == 5 and c.bags[3][1] == ORE)
check("keyring", #c.keys == 1 and c.keys[1][1] == KEY and c.keys[1][2] == nil)
check("no bank until you visit", c.bank == nil)
check("no lockouts until the game says", c.saved == nil)
-- The bank opens
Alts.bankOpen = true
Alts:UpdateBank()
check("bank: the main slots and bank bags", #c.bank == 3 and c.bank[1][2] == 20 and c.bank[3][1] == HELM and c.bankAt == now)
Alts.bankOpen = false
-- Lockouts from the game
Alts.savedFresh = true
Alts:Update()
check("lockouts: only the ones still running", #c.saved == 1 and c.saved[1].name == "Karazhan" and c.saved[1].killed == 4
    and c.saved[1].bosses == 11 and c.saved[1].reset == now + 3600 * 30)
check("lockouts: running", #Alts:Lockouts(c) == 1 and #Alts:Lockouts(c, now + 3600 * 31) == 0)

-- A second character
name, class = "Alty", "MAGE"
gear = { [1] = HELM }
bags = { [0] = { ORE } }
counts[ORE] = 7
Alts:Update()

-- ---- Search ----
local hits = Alts:Search("ore")
check("search: by name across characters", #hits == 1 and hits[1].name == "Fel Iron Ore" and hits[1].total == 20 + 20 + 20 + 7)
local where = {}
for _, w in ipairs(hits[1].where) do where[w.char.name .. "/" .. w.place] = w.count end
check("search: who and where", where["Tanky/bags"] == 40 and where["Tanky/bank"] == 20 and where["Alty/bags"] == 7)
local crown = Alts:Search("voidheart")[1]
check("search: worn and banked count", crown.total == 3)
check("search: keyring", Alts:Search("master's")[1].where[1].place == "keyring")
check("search: too short", #Alts:Search("o") == 0)
check("search: case-insensitive", #Alts:Search("FEL IRON") == 1)

-- ---- The window ----
Alts:Toggle()
local p = env.WM_AltTrackerFrame
local function CharRow(n)
    for _, r in ipairs(p.rows) do if r:IsShown() and r.char and r.char.name == n then return r end end
end
local tank = CharRow("Tanky")
check("GearScore column", tank.gs:GetText():find(tostring(c.gearScore), 1, true) ~= nil)
check("four buttons per character", tank.views.bags:IsShown() and tank.views.bank:IsShown() and tank.views.attune:IsShown()
    and tank.views.lockouts:IsShown())
check("bank button dim without a visit", CharRow("Alty").views.bank._alpha < 1 and tank.views.bank._alpha == 1)
-- Gear flyout
W.fire(tank, "OnClick", "LeftButton")
local fl = env.WM_AltTrackerDetail
check("click: gear flyout", fl:IsShown() and fl.view == "gear" and fl.slots[1].link == HELM and fl.slots[16].link == SWORD
    and fl.slots[2].link == nil)
check("flyout header: GearScore", fl.sub:GetText():find("GearScore", 1, true) ~= nil)
check("selected row highlighted", CharRow("Tanky").sel:IsShown())
local tipped
env.GameTooltip.SetHyperlink = function(_, l) tipped = l end
fl.slots[1]._scripts.OnEnter(fl.slots[1])
check("slot tooltip", tipped == HELM)
local linked
env.HandleModifiedItemClick = function(l) linked = l end
fl.slots[16]._scripts.OnClick(fl.slots[16])
check("shift-click links", linked == SWORD)
-- Bags, bank, attunements, lockouts
tank = CharRow("Tanky")
tank.views.bags._scripts.OnClick(tank.views.bags)
check("bags view", fl.view == "bags" and fl.cells[1].link == POTION and fl.cells[1].count:GetText() == 5
    and fl.cells[4].link == KEY and fl.sub:GetText():find("4 items", 1, true))
tank.views.bank._scripts.OnClick(tank.views.bank)
check("bank view", fl.view == "bank" and fl.cells[3].link == HELM and not fl.cells[4]:IsShown() and fl.sub:GetText():find("as of", 1, true))
CharRow("Alty").views.bank._scripts.OnClick(CharRow("Alty").views.bank)
check("bank never visited: a hint", fl.sub:GetText():find("Open the bank once", 1, true) ~= nil)
tank = CharRow("Tanky")
tank.views.lockouts._scripts.OnClick(tank.views.lockouts)
check("lockouts view", fl.lines[1]:GetText():find("Karazhan", 1, true) and fl.lines[1]:GetText():find("4/11", 1, true)
    and fl.lines[1]:GetText():find("resets in 1d 6h", 1, true))
WM.Attunements:Update()
tank = CharRow("Tanky")
tank.views.attune._scripts.OnClick(tank.views.attune)
check("attunements view", fl.view == "attune" and fl.lines[1]:IsShown() and fl.openBtn:IsShown())
check("same button again closes it", (function()
    tank = CharRow("Tanky")
    tank.views.attune._scripts.OnClick(tank.views.attune)
    return not fl:IsShown()
end)())
-- Search in the window
local e = p.searchBox.editBox
e:SetText("ore")
e._scripts.OnTextChanged(e, true)
local hitRow
for _, r in ipairs(p.rows) do if r:IsShown() and r.hit then hitRow = r end end
check("search results in the list", hitRow and hitRow.hit.name == "Fel Iron Ore" and hitRow.gold:GetText():find("67", 1, true)
    and p.totalText:GetText():find("1 item found", 1, true))
local hitTip = {}
env.GameTooltip.AddDoubleLine = function(_, a, b) hitTip[#hitTip + 1] = a .. " " .. b end
hitRow._scripts.OnEnter(hitRow)
check("result tooltip: who has it", table.concat(hitTip, "\n"):find("Tanky", 1, true) and table.concat(hitTip, "\n"):find("(bank)", 1, true))
e:SetText("zzz")
e._scripts.OnTextChanged(e, true)
check("no results: says so", p.rows[1].name:GetText():find("No character has", 1, true) ~= nil)
e._scripts.OnEscapePressed(e)
check("Escape: back to the characters", CharRow("Tanky") ~= nil and Alts.searchText == nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
