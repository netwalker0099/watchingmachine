-- Nova compatibility (listen only): the decoder (escape, inflate,
-- LibSerialize string, AceComm parts) and reset notices from Nova Instance
-- Tracker / Nova World Buffs users. Test messages in nova_fixtures.lua were
-- made with zlib's raw DEFLATE, as Nova's own LibDeflate makes them.
-- Usage: lua5.1 test_nova.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
local F = dofile(REPO .. "/tests/nova_fixtures.lua")

local now = 1800000000
env.GetServerTime = function() return now end
env.strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end
env.UnitName = function(u) if u == "player" then return "Tanky" end end
env.GetRealmName = function() return "Spineshatter" end
env.Ambiguate = function(name) return (name:gsub("%-Spineshatter$", "")) end
local grouped, leaderName = true, "Lead"
env.IsInGroup = function() return grouped end
env.IsInRaid = function() return false end
env.UnitInParty = function(n) return grouped and (n == "Lead" or n == "Member") end
env.UnitInRaid = function() return nil end
env.UnitIsGroupLeader = function(n) return n == leaderName end
local registered = {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function(p) registered[p] = true end }
env.IsInInstance = function() return false, "none" end

W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/NovaCompat.lua")
W.load("Modules/InstanceTracker.lua")
local WM = W.WM
local Nova, IT = WM.Nova, WM.modules.InstanceTracker
env.WatchingMachineDB = { theme = "Default" }
IT:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function LastPrint() return W.printed[#W.printed] or "" end

-- ---- The decoder ----
check("NIT prefix registered", registered.NIT == true)
for _, key in ipairs({ "reset", "resetChat", "old", "nwb", "version", "stored", "fixed", "mid", "long" }) do
    local cmd, version, data = Nova.DecodeNIT(F[key].body)
    local text = cmd and (cmd .. " " .. (F[key].text:match("^%S+ (%S+)")) .. (data ~= "" and (" " .. data) or ""))
    check("decodes " .. key, text == F[key].text)
end
check("long message used the dynamic Huffman path and round-trips", (select(3, Nova.DecodeNIT(F.long.body))):len() > 1000)
check("version is a number", select(2, Nova.DecodeNIT(F.reset.body)) == 2.31)
check("escape undone", Nova.Unescape("a\001\002b\001\003c") == "a\000b\001c")
check("bad escape rejected", Nova.Unescape("a\001\009") == nil)
check("serialized string read", Nova.ReadSerializedString(F.longSerialized):find("^instanceResetNoMsg 2%.31") ~= nil)
check("short serialized string", Nova.ReadSerializedString("\001\050ab") == nil   -- says 3 bytes, has 2
    and Nova.ReadSerializedString("\001" .. string.char(3 * 16 + 2) .. "abc") == "abc")
check("not a string: rejected", Nova.ReadSerializedString("\001\005") == nil)
check("garbage doesn't inflate", Nova.Inflate("\255\255\255") == nil)
check("truncated data doesn't inflate", Nova.Inflate(F.reset.body:sub(1, 5)) == nil)
check("inflate size cap", Nova.Inflate(Nova.Unescape(F.long.body), 100) == nil)

-- AceComm framing
check("single part passes through", Nova.Reassemble("NIT", "abc", "PARTY", "Lead") == "abc")
check("escaped control byte", Nova.Reassemble("NIT", "\004\001xyz", "PARTY", "Lead") == "\001xyz")
local body = F.long.body
local p1, p2, p3 = body:sub(1, 254), body:sub(255, 508), body:sub(509)
check("first part buffered", Nova.Reassemble("NIT", "\001" .. p1, "PARTY", "Lead") == nil)
check("middle part buffered", Nova.Reassemble("NIT", "\002" .. p2, "PARTY", "Lead") == nil)
check("last part completes it", Nova.Reassemble("NIT", "\003" .. p3, "PARTY", "Lead") == body)
check("a last part with no first is dropped", Nova.Reassemble("NIT", "\003" .. p3, "PARTY", "Lead") == nil)
check("parts kept apart per sender", Nova.Reassemble("NIT", "\001" .. p1, "PARTY", "Other") == nil
    and Nova.Reassemble("NIT", "\003" .. p3, "PARTY", "Lead") == nil)

-- ---- Reset notices ----
local function Send(fixture, distribution, sender, framed)
    local msg = F[fixture].body
    if msg:byte(1) and msg:byte(1) <= 9 then msg = "\004" .. msg end
    return Nova:OnAddonMessage("NIT", framed or msg, distribution or "PARTY", sender or "Lead-Spineshatter")
end
-- A run of ours in that instance, so the reset can be marked
table.insert(IT:Runs(), 1, { name = "The Deadmines", char = "Tanky-Spineshatter", entered = now - 900, left = now - 100,
    mobs = 0, xp = 0, gold = 0, rep = {}, group = {} })
local n = #W.printed
check("leader's NoMsg reset is shown", Send("reset") == "shown" and #W.printed == n + 1
    and LastPrint():find("The Deadmines has been reset by the group leader (Lead", 1, true) ~= nil)
check("and marks our run as reset", IT:Runs()[1].reset == true)
n = #W.printed
check("leader's reset with its own chat line: marked, not repeated", Send("resetChat") == "quiet" and #W.printed == n)
check("Nova World Buffs notice: shown as a failed reset", Send("nwb") == "shown"
    and LastPrint():find("tried to reset Razorfen Kraul", 1, true) ~= nil)
check("long multipart notice", (function()
    Nova:OnAddonMessage("NIT", "\001" .. p1, "PARTY", "Lead")
    Nova:OnAddonMessage("NIT", "\002" .. p2, "PARTY", "Lead")
    return Nova:OnAddonMessage("NIT", "\003" .. p3, "PARTY", "Lead") == "shown"
end)())
n = #W.printed
check("not the leader: ignored", Send("reset", "PARTY", "Member") == nil and #W.printed == n)
check("not in our group: ignored", Send("reset", "PARTY", "Stranger") == nil)
check("old NIT version: ignored", Send("old") == nil)
check("version messages: ignored", Send("version") == nil)
check("guild channel: ignored", Send("reset", "GUILD") == nil)
check("our own message: ignored", Send("reset", "PARTY", "Tanky") == nil)
check("other prefixes: ignored", Nova:OnAddonMessage("NWB", F.reset.body, "PARTY", "Lead") == nil)
check("junk: ignored", Nova:OnAddonMessage("NIT", "not nova data", "PARTY", "Lead") == nil)
grouped = false
check("not in a group: ignored", Send("reset") == nil)
grouped = true
IT.DB().novaListen = false
check("option off: ignored", Send("reset") == nil)
IT.DB().novaListen = true
check("raid and instance chat accepted", Send("reset", "RAID") == "shown" and Send("reset", "INSTANCE_CHAT") == "shown")

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
