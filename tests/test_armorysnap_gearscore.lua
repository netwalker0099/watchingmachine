-- GearScore in ArmorySnap: members scored on capture and from saved
-- snapshots, the member list, the paper doll line, the snapshot average.
-- Usage: lua5.1 test_armorysnap_gearscore.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Items: id -> { name, quality, ilvl, equipLoc }; known[id] = the client has it
local items = {
    [28963] = { "Voidheart Crown", 4, 120, "INVTYPE_HEAD" },
    [28964] = { "Voidheart Robe", 4, 120, "INVTYPE_CHEST" },
    [28783] = { "Eye of Magtheridon", 4, 125, "INVTYPE_TRINKET" },
    [29988] = { "The Nexus Key", 4, 141, "INVTYPE_2HWEAPON" },
}
local known = { [28963] = true, [28964] = true, [28783] = true, [29988] = true }
local function Id(link) return tonumber(tostring(link):match("item:(%d+)")) end
env.C_Item = {
    GetItemInfo = function(link)
        local id = Id(link)
        local i = known[id] and items[id]
        if i then return i[1], link, i[2], i[3], 0, "", "", 1, i[4] end
    end,
    GetItemInfoInstant = function(link) local i = items[Id(link)]; if i then return Id(link), "", "", i[4], "", 4, 0 end end,
    GetItemStats = function() return {} end,
}
env.GetItemInfo = env.C_Item.GetItemInfo
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
env.strsplit = function(sep, s, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then out[#out + 1] = s:sub(start) break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return unpack(out)
end
local afters = {}
env.C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end, NewTimer = function() return { Cancel = function() end } end }

-- Record frames and font strings so the browser's pieces can be found
local created, strings = {}, {}
local baseCreate = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = baseCreate(kind, name, parent, template)
    created[#created + 1] = f
    return f
end
local baseFS = W.Frame.CreateFontString
W.Frame.CreateFontString = function(self, ...)
    local fs = baseFS(self, ...)
    strings[#strings + 1] = fs
    return fs
end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/GearScore.lua", "Modules/ArmorySnap.lua" }) do W.load(f) end
local WM = W.WM
local GS, AS = WM.modules.GearScore, WM.modules.ArmorySnap
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function L(id, ench) return "|cffa335ee|Hitem:" .. id .. ":" .. (ench or 0) .. ":0:0:0|h[" .. items[id][1] .. "]|h|r" end
local function G(...)
    local gear = {}
    for i = 1, select("#", ...), 2 do gear[select(i, ...)] = { link = select(i + 1, ...), icon = "" } end
    return gear
end

local KEY = "2026-10-20 20:00 - Karazhan"
env.ArmorySnapDB = {
    options = { enabled = true, scanGroup = false, verbose = false, retentionDays = 30 },
    snapshots = {
        [KEY] = { timestamp = "2026-10-20 20:00", zone = "Karazhan", members = {
            Alice = { name = "Alice", class = "WARLOCK", race = "Gnome", level = 70, guild = "",
                gear = G(1, L(28963, 2999), 5, L(28964), 13, L(28783)) },
            Bob = { name = "Bob", class = "MAGE", race = "Human", level = 70, guild = "", gear = G(16, L(29988)) },
            Carol = { name = "Carol", class = "MAGE", race = "Human", level = 70, guild = "", gear = {} },
        } },
    },
}
AS.db = env.ArmorySnapDB
local members = env.ArmorySnapDB.snapshots[KEY].members

-- ---- Scoring a member ----
local expectAlice = select(1, GS.GearScoreFor({ [1] = L(28963, 2999), [5] = L(28964), [13] = L(28783) }, "WARLOCK"))
local score, ilvl, complete = AS.ScoreMember(members.Alice)
check("member scored from the saved links", score == expectAlice and complete and score > 0)
check("saved on the member", members.Alice.gearScore == expectAlice and members.Alice.avgIlvl == math.floor((120 + 120 + 125) / 17 * 10 + 0.5) / 10)
check("enchant counted", members.Alice.gearScore > select(1, GS.GearScoreFor({ [1] = L(28963), [5] = L(28964), [13] = L(28783) }, "WARLOCK")))
check("two-hander's level counts twice", math.abs(select(2, AS.ScoreMember(members.Bob)) - 141 * 2 / 17) < 0.1)
check("no gear: no score", AS.ScoreMember(members.Carol) == nil)
known[28964] = nil
members.Alice.gearScore = nil
score, ilvl, complete = AS.ScoreMember(members.Alice)
check("item not known yet: partial, not saved", not complete and members.Alice.gearScore == nil and score < expectAlice)
known[28964] = true
check("later: complete and saved", select(3, AS.ScoreMember(members.Alice)) and members.Alice.gearScore == expectAlice)
members.Alice.gear = {}
check("saved score kept without looking again", AS.ScoreMember(members.Alice) == expectAlice)
members.Alice.gear = G(1, L(28963, 2999), 5, L(28964), 13, L(28783))

-- Snapshot average
local avg, n = AS.SnapshotScore(KEY)
check("snapshot average", n == 2 and avg == math.floor((members.Alice.gearScore + members.Bob.gearScore) / 2 + 0.5))
check("no such snapshot", AS.SnapshotScore("nope") == nil)
local saved = WM.GearScore
WM.GearScore = nil
members.Bob.gearScore = nil
check("without the GearScore module: nothing", AS.ScoreMember(members.Bob) == nil)
WM.GearScore = saved

-- ---- The browser ----
known[29988] = nil   -- Bob's weapon still loading
AS.ToggleBrowseFrame()
local function MemberButton(name)
    for _, f in ipairs(created) do if rawget(f, "memberName") == name and f:IsShown() then return f end end
end
local alice = MemberButton("Alice")
check("member list: score in the row", alice and alice.rightText:GetText():find(tostring(expectAlice), 1, true))
check("member list: no score without gear", not MemberButton("Carol").rightText:GetText():find("|cff", 1, true))
local function FindString(pattern)
    for _, fs in ipairs(strings) do
        local t = fs:GetText()
        if t and t:find(pattern, 1, true) then return fs end
    end
end
check("members label: snapshot average", FindString("avg GS") ~= nil)
W.click(alice)
local line = FindString("GearScore")
check("paper doll: GearScore and iLvl", line and line:GetText():find("iLvl", 1, true) and line:GetText():find(tostring(expectAlice), 1, true))
W.click(MemberButton("Bob"))
check("paper doll: still loading", FindString("(loading)") ~= nil)
-- The item arrives: the browser redraws
known[29988] = true
afters = {}
local watch
for _, f in ipairs(created) do
    local h = rawget(f, "_scripts") and f._scripts.OnEvent
    if h then
        h(f, "GET_ITEM_INFO_RECEIVED")
        if #afters > 0 then watch = f; break end
    end
end
check("item info: a redraw is queued", watch ~= nil and #afters == 1)
afters[1]()
check("then the score is complete", members.Bob.gearScore ~= nil and not FindString("(loading)"))

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
