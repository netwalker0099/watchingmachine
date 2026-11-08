-- ArmorySnap's armory: your own gear saved per spec, guildmates saved from
-- inspects, shared with the guild (newest scan wins), asked for on demand,
-- shown in the browser and from Roster Manager.
-- Usage: lua5.1 test_armory.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
local timers = {}
local function NewTimer(_, fn)
    local t = { fn = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
end
env.C_Timer = { After = NewTimer, NewTimer = NewTimer, NewTicker = function() return { Cancel = function() end } end }
local function RunTimers()
    for _ = 1, 200 do
        local list = timers; timers = {}
        if #list == 0 then return end
        for _, t in ipairs(list) do if not t.cancelled then t.fn() end end
    end
end

local sent = {}
env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, body, channel, target) sent[#sent + 1] = { prefix, body, channel, target } end,
}

-- The player: a fire mage in the guild
local gear = {
    [1] = "|cffa335ee|Hitem:28963:2999:24030:24030:0:0:0:0|h[Voidheart Crown]|h|r",
    [5] = "|cffa335ee|Hitem:28964:0:0:0:0:0:0:0|h[Voidheart Robe]|h|r",
    [13] = "|cffa335ee|Hitem:28783:0:0:0:0:0:0:0|h[Eye of Magtheridon]|h|r",
    [16] = "|cffa335ee|Hitem:29988:2669:0:0:0:0:-5:12345|h[The Nexus Key]|h|r",
}
local trees = { { "Arcane", "a", 10 }, { "Fire", "f", 51 }, { "Frost", "i", 0 } }
local inspected = { gear = {}, trees = { { "Arms", "x", 0 }, { "Fury", "y", 0 }, { "Protection", "z", 0 } } }
local units = { player = "Me", target = "Tankier", party1 = "Stranger" }
env.UnitName = function(u) return units[u] end
env.UnitClass = function(u) if u == "player" then return "Mage", "MAGE" end return "Warrior", "WARRIOR" end
env.UnitRace = function() return "Gnome" end
env.UnitLevel = function() return 70 end
env.UnitSex = function() return 2 end
env.UnitIsUnit = function(a, b) return a == b end
env.UnitIsInMyGuild = function(u) return u == "player" or u == "target" end
env.IsInGuild = function() return true end
env.GetGuildInfo = function() return "Ninjas" end
env.GetInventoryItemLink = function(u, slot) if u == "player" then return gear[slot] end return inspected.gear[slot] end
env.GetInventoryItemTexture = function() return "icon" end
env.GetNumTalentTabs = function() return 3 end
env.GetTalentTabInfo = function(tab, isInspect)
    local t = (isInspect and inspected.trees or trees)[tab]
    return t[1], t[2], t[3]
end
env.GetNumTalents = function() return 0 end
env.GetItemInfo = function() return nil end
env.C_Item = { GetItemInfo = function(id)
    if id == 28963 then return "Voidheart Crown", nil, 4 end
end, GetItemIconByID = function(id) return "icon" .. id end }
env.ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee" } }
env.strsplit = function(sep, s)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return unpack(out)
end
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
env.IsAddOnLoaded = function() return false end
env.C_AddOns = { IsAddOnLoaded = function() return false end }
env.InCombatLockdown = function() return false end

env.WatchingMachineDB = { theme = "Default" }
for _, f in ipairs({ "Core.lua", "UI.lua", "Profiles.lua", "Modules/ArmorySnap.lua", "Modules/ArmorySnapArmory.lua",
                     "Modules/GuildRoster.lua", "Modules/GuildRosterSync.lua", "Modules/GuildRosterUI.lua" }) do
    W.load(f)
end
local WM = W.WM
local AS = WM.modules.ArmorySnap
local Arm = AS.Armory
local GR = WM.modules.GuildRoster

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Sent() WM:FlushAddonQueue(); local s = sent; sent = {}; return s end
local function Bodies(prefix)
    local out = {}
    for _, m in ipairs(Sent()) do if m[1] == prefix then out[#out + 1] = m[2] end end
    return out
end

AS:Initialize()
local db = AS.db
check("armory saved variables made", type(db.armory) == "table" and type(db.armoryUsers) == "table")
check("armory options default on", db.options.armorySelf and db.options.armoryInspect and db.options.armoryShare)
check("names keyed with the realm", Arm.Key("Me") == "Me-Testrealm" and Arm.Key("Bob-Some Realm") == "Bob-SomeRealm")

-- ============ Your own gear ============
check("own scan saved", Arm:RecordSelf() == true)
local mine = db.armory["Me-Testrealm"]
check("saved under the spec with the most points", mine and mine.Fire ~= nil)
check("own scan marked", mine.Fire.own == true and mine.Fire.by == "Me-Testrealm" and mine.Fire.time == now)
check("gear kept", mine.Fire.gear[1].link == gear[1] and mine.Fire.talents.points == "10/51/0")
local parts = Bodies("WMArmory")
check("own scan sent to the guild", #parts >= 1 and parts[1]:find("^P%^") ~= nil)
for _, b in ipairs(parts) do check("each message fits", #b + #"WMArmory" <= 254) end
check("nothing new: not saved again", Arm:RecordSelf() == false and #Sent() == 0)
now = now + 100
gear[5] = "|cffa335ee|Hitem:30000:0:0:0:0:0:0:0|h[New Robe]|h|r"
check("gear change saved", Arm:RecordSelf() == true and mine.Fire.time == now)
Sent()
-- Respec to frost: a second armory, the fire one kept
trees[2][3], trees[3][3] = 0, 51
now = now + 100
Arm:RecordSelf()
check("second spec saved separately", mine.Frost ~= nil and mine.Fire ~= nil)
check("specs newest first", Arm.Specs("Me")[1].spec == "Frost" and Arm.Specs("Me")[2].spec == "Fire")
Sent()

-- ============ Wire format ============
local key, e = Arm.Deserialize(Arm.Serialize("Me-Testrealm", mine.Fire))
check("round trip: key, spec, time", key == "Me-Testrealm" and e.spec == "Fire" and e.time == mine.Fire.time)
check("round trip: own, class, level", e.own == true and e.class == "MAGE" and e.level == 70)
check("round trip: talents", e.talents.points == "10/51/0" and e.talents.spec == "Fire" and e.talents.trees[2].name == "Fire")
check("round trip: enchant and gems kept, known item named",
    e.gear[1].link == "|cffa335ee|Hitem:28963:2999:24030:24030|h[Voidheart Crown]|h|r" and not e.gear[1].pending)
check("round trip: random suffix kept", e.gear[16].link:find("item:29988:2669:0:0:0:0:%-5:12345|h") ~= nil)
check("round trip: unknown item waits for its name", e.gear[13].pending == true and e.gear[13].link:find("%[Item 28783%]") ~= nil)
check("icon from the item id", e.gear[13].icon == "icon28783")
check("a broken message is ignored", Arm.Deserialize("2^x") == nil and Arm.Deserialize("garbage") == nil)

-- ============ From the guild ============
local function Deliver(sender, k, entry)
    local data = Arm.Serialize(k, entry)
    local n = math.ceil(#data / 200)
    for i = 1, n do
        Arm:OnMessage("WMArmory", "P^ab1^" .. i .. "^" .. n .. "^" .. data:sub((i - 1) * 200 + 1, i * 200), "GUILD", sender)
    end
end
local healer = { name = "Holy", class = "PALADIN", race = "Human", level = 70, sex = 3, guild = "Ninjas",
    spec = "Holy", time = now - 50, by = "Holy-Testrealm", own = true,
    talents = { trees = { { name = "Holy", points = 41, icon = "h" }, { name = "Protection", points = 20, icon = "p" },
        { name = "Retribution", points = 0, icon = "r" } }, spec = "Holy", points = "41/20/0" },
    gear = { [1] = { link = gear[1] } } }
Deliver("Holy", "Holy-Testrealm", healer)
check("armory from a guildmate saved", db.armory["Holy-Testrealm"] and db.armory["Holy-Testrealm"].Holy.time == now - 50)
check("their own scan: they run Watching Machine", Arm.RunsAddon("Holy-Testrealm"))
-- A full set with gems splits over several messages and comes back whole
local full = {}
for k, v in pairs(healer) do full[k] = v end
full.gear, full.time = {}, now - 40
for slot = 1, 18 do full.gear[slot] = { link = "|cffa335ee|Hitem:" .. (30000 + slot) .. ":2999:24030:24031:24032|h[X]|h|r" } end
local data = Arm.Serialize("Holy-Testrealm", full)
check("a full set needs several messages", math.ceil(#data / 200) >= 2)
Deliver("Holy", "Holy-Testrealm", full)
local got = db.armory["Holy-Testrealm"].Holy
local n = 0
for _ in pairs(got.gear) do n = n + 1 end
check("a split armory arrives whole", got.time == now - 40 and n == 18 and got.gear[18].link:find("item:30018:2999:24030:24031:24032|h") ~= nil)
healer.time = now - 40
local older = {}
for k, v in pairs(healer) do older[k] = v end
older.time = now - 500
Deliver("Someone", "Holy-Testrealm", older)
check("an older scan doesn't replace a newer one", db.armory["Holy-Testrealm"].Holy.time == now - 40)
Arm:OnMessage("WMArmory", "P^zz^1^1^" .. Arm.Serialize("Bad-Testrealm", healer), "WHISPER", "Holy")
check("only the guild channel is heard", db.armory["Bad-Testrealm"] == nil)
local future = {}
for k, v in pairs(healer) do future[k] = v end
future.time = now + 100000
Deliver("Liar", "Holy-Testrealm", future)
check("a scan from the future is ignored", db.armory["Holy-Testrealm"].Holy.time == now - 40)

-- ============ Inspects ============
local function Inspect(unit)
    local ci = AS.CaptureCharInfo(unit)
    ci.gear = AS.CaptureGear(unit)
    ci.talents = AS.CaptureTalents(true)
    return Arm:FromInspect(ci, unit)
end
inspected.gear = {
    [1] = "|cffa335ee|Hitem:100:0|h[A]|h|r", [5] = "|cffa335ee|Hitem:101:0|h[B]|h|r",
    [7] = "|cffa335ee|Hitem:102:0|h[C]|h|r", [10] = "|cffa335ee|Hitem:103:0|h[D]|h|r",
}
check("guildmate inspect saved", Inspect("target") == true)
local tank = db.armory["Tankier-Testrealm"]
check("no talent points: spec unknown", tank and tank["?"] ~= nil and tank["?"].by == "Me-Testrealm" and not tank["?"].own)
check("inspect shared", #Bodies("WMArmory") >= 1)
check("not a guildmate: not saved", Inspect("party1") == false and db.armory["Stranger-Testrealm"] == nil)
-- Their own Protection scan arrives; a later inspect in the same gear goes under it
local prot = { name = "Tankier", class = "WARRIOR", race = "Orc", level = 70, sex = 2, guild = "Ninjas",
    spec = "Protection", time = now + 10, by = "Tankier-Testrealm",
    talents = { trees = { { name = "Arms", points = 0 }, { name = "Fury", points = 20 }, { name = "Protection", points = 41 } },
        spec = "Protection", points = "0/20/41" },
    gear = {} }
for s, l in pairs(inspected.gear) do prot.gear[s] = { link = l } end
Arm.Store("Tankier-Testrealm", prot)
check("a spec found by talents replaces the matching unknown one", tank.Protection ~= nil and tank["?"] == nil)
now = now + 200
inspected.gear[10] = "|cffa335ee|Hitem:999:0|h[E]|h|r"
check("inspect matched to the spec with the same gear", Inspect("target") == true and tank.Protection.time == now)
check("its talent points kept from that spec", tank.Protection.talents.points == "0/20/41")
Sent()
db.armoryUsers["Tankier-Testrealm"] = now
check("a Watching Machine user keeps their own", Inspect("target") == false)
db.armoryUsers["Tankier-Testrealm"] = now - 40 * 86400
now = now + 1
check("not heard from for a month: inspected again", Inspect("target") == true)
Sent()

-- ============ Asking ============
RunTimers()   -- the start-up scan and greeting
Sent()
Arm:ResetForTests()
check("query sent", Arm:Query("Holy") == true)
local q = Bodies("WMArmory")
check("query lists what we have", q[1] and q[1]:find("^Q%^Holy%-Testrealm%^") and q[1]:find("Holy=" .. (now - 241)))
check("not asked again within a minute", Arm:Query("Holy") == false)
-- Someone asks about Holy with an older copy: we answer after a moment
Arm:OnMessage("WMArmory", "Q^Holy-Testrealm^Holy=1", "GUILD", "Asker")
check("answer waits", #Bodies("WMArmory") == 0)
RunTimers()
local answer = Bodies("WMArmory")
check("answered with our newer armory", #answer >= 1 and answer[1]:find("^P%^") ~= nil)
-- Someone else answers first: we stay quiet
Arm:OnMessage("WMArmory", "Q^Holy-Testrealm^Holy=1", "GUILD", "Asker2")
Deliver("Other", "Holy-Testrealm", healer)
RunTimers()
check("someone else answered: we don't repeat it", #Bodies("WMArmory") == 0)
Arm:OnMessage("WMArmory", "Q^Holy-Testrealm^Holy=" .. (now + 1), "GUILD", "Asker3")
RunTimers()
check("they have it already: no answer", #Bodies("WMArmory") == 0)
-- Asked about ourselves: answered quickly
Arm:OnMessage("WMArmory", "Q^Me-Testrealm^", "GUILD", "Asker4")
RunTimers()
check("asked about us: both specs sent", #Bodies("WMArmory") == 2)

-- Something we shared ourselves earlier is still sent to someone asking later
Arm:ResetForTests()
now = now + 50
gear[13] = "|cffa335ee|Hitem:28784:0:0:0:0:0:0:0|h[Other Trinket]|h|r"
Arm:RecordSelf()
Sent()
Arm:OnMessage("WMArmory", "Q^Me-Testrealm^Frost=1,Fire=1", "GUILD", "LateComer")
RunTimers()
check("our own earlier share doesn't stop a later answer", #Bodies("WMArmory") == 2)

-- ============ Catching up ============
Arm:ResetForTests()
db.armoryLastOnline = nil
Arm:Greet()
local greet = Bodies("WMArmory")
check("greeting says hello", greet[1] and greet[1]:find("^H%^") ~= nil)
check("first time: catch up on everything", greet[2] == "C^0")
check("last online noted", db.armoryLastOnline == now)
Arm:ResetForTests()
now = now + 7200
Arm:Greet()
greet = Bodies("WMArmory")
check("next time: since an hour before last online", greet[2] == "C^" .. (now - 7200 - 3600))
RunTimers(); Sent()

-- Someone asks to catch up: our guild's armories go out one at a time, newest first
local otherGuild = {}
for k, v in pairs(healer) do otherGuild[k] = v end
otherGuild.guild, otherGuild.time = "Other Guild", now - 30
Arm.Store("Outsider-Testrealm", otherGuild)
Arm:ResetForTests()
local since = db.armory["Holy-Testrealm"].Holy.time - 1
Arm:OnMessage("WMArmory", "C^" .. since, "GUILD", "Returner")
local queued = Arm.CatchUpLength()
local expect = 0
for key, specs in pairs(db.armory) do for _, e in pairs(specs) do
    if e.time > since and e.guild == "Ninjas" then expect = expect + 1 end
end end
check("catch-up: our guild's armories since then queued", queued == expect and queued >= 3)
check("catch-up: waits a moment before starting", #Bodies("WMArmory") == 0)
-- Someone else sends the Holy armory first: we skip it
Deliver("Faster", "Holy-Testrealm", db.armory["Holy-Testrealm"].Holy)
RunTimers()
local out, holy, outsider = Bodies("WMArmory"), false, false
for _, b in ipairs(out) do
    if b:find("Holy%-Testrealm") then holy = true end
    if b:find("Outsider") then outsider = true end
end
check("catch-up: sent the rest", #out >= expect - 1 and #out > 0)
check("catch-up: skipped what someone else sent", not holy)
check("catch-up: other guilds' armories not sent", not outsider)
check("catch-up: nothing left", Arm.CatchUpLength() == 0)
Arm:OnMessage("WMArmory", "C^" .. (now + 10), "GUILD", "UpToDate")
check("catch-up: nothing newer, nothing queued", Arm.CatchUpLength() == 0)
Arm:OnMessage("WMArmory", "C^0", "GUILD", "Returner")
Arm:Stop()
RunTimers()
check("stopped: the catch-up is dropped", Arm.CatchUpLength() == 0 and #Bodies("WMArmory") == 0)
db.armory["Outsider-Testrealm"] = nil

-- An inspect that brings talent points goes under that spec
Arm:ResetForTests()
units.target = "Swapper"
inspected.trees = { { "Arms", "x", 41 }, { "Fury", "y", 20 }, { "Protection", "z", 0 } }
now = now + 10
check("inspected talents saved", Inspect("target") == true)
check("filed under the spec their talents show", db.armory["Swapper-Testrealm"].Arms ~= nil
    and db.armory["Swapper-Testrealm"].Arms.talents.points == "41/20/0")
units.target = "Tankier"
inspected.trees = { { "Arms", "x", 0 }, { "Fury", "y", 0 }, { "Protection", "z", 0 } }
Sent()

-- ============ The browser ============
local view = Arm.View()
check("view: a row per character and spec", view.members["Me · Fire"] and view.members["Me · Frost"] and view.members["Tankier · Protection"])
check("view row shows who scanned", view.members["Holy · Holy"].armoryNote:find("their own scan") ~= nil)
check("view row reads the saved armory", view.members["Me · Fire"].class == "MAGE")
check("one player's rows", next(Arm.View("Holy-Testrealm").members) == "Holy · Holy")
check("their newest row", Arm.ViewKey("Me") == "Me · Frost")
AS.ShowArmory("Me", Arm.ViewKey("Me"))
check("browser opened at the armory", env.WM_ArmorySnapFrame and env.WM_ArmorySnapFrame:IsShown() and AS.armoryFilter == "Me-Testrealm")
check("armory listed with snapshots", AS.GetMemberNames(AS.ARMORY_KEY)[1] == "Me · Fire")

-- ============ Roster Manager ============
check("roster sees the armory with ArmorySnap on", GR.Armory() == Arm)
local rec = { name = "Holy-Testrealm", class = "PALADIN", level = 70, join = { date = "" }, promo = { date = "" },
    bday = {}, custom = { text = "" }, ban = {} }
local found
for _, l in ipairs(GR:DetailLines(rec)) do if l[1] == "Armory" and l[2]:find("^Holy") then found = true end end
check("details list their armory", found)
WM:SetModuleOn("ArmorySnap", false)
check("ArmorySnap off: no armory in the roster", GR.Armory() == nil)
found = false
for _, l in ipairs(GR:DetailLines(rec)) do if l[1] == "Armory" then found = true end end
check("ArmorySnap off: no armory lines", not found)

-- ============ Off means off ============
Sent()
now = now + 100
gear[1] = "|cffa335ee|Hitem:31000:0:0:0:0:0:0:0|h[Other Hat]|h|r"
check("off: own gear not saved", Arm:RecordSelf() == false)
check("off: inspects not saved", Inspect("target") == false)
Arm:OnMessage("WMArmory", "P^q^1^1^" .. Arm.Serialize("New-Testrealm", healer), "GUILD", "New")
check("off: messages ignored", db.armory["New-Testrealm"] == nil)
check("off: no queries", Arm:Query("Holy", true) == false)
check("off: nothing sent", #Sent() == 0)
WM:SetModuleOn("ArmorySnap", true)
RunTimers()
check("on again: changed gear saved", db.armory["Me-Testrealm"].Frost.gear[1].link:find("31000") ~= nil)

-- Settings
db.options.armorySelf = false
now = now + 100
gear[1] = gear[5]
check("save my gear off: not saved", Arm:RecordSelf() == false)
db.options.armorySelf = true
db.options.armoryShare = false
Sent()
check("share off: saved but not sent", Arm:RecordSelf() == true and #Sent() == 0)

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
