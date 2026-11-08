-- Loot Council's RCLootCouncil-compatible message format: AceSerializer's
-- text form, raw DEFLATE (checked against zlib's own streams), the addon
-- channel's encoding and AceComm's framing.
-- Usage: lua5.1 test_lootcodec.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
W.load("Core.lua")
W.load("Modules/LootCouncilCodec.lua")
local C = W.WM.LootCodec

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b or (a ~= a and b ~= b) end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- ============ AceSerializer ============
check("RCLootCouncil's council example", C.Serialize("council", { { ["4904-0A1B2C3D"] = true } })
    == "^1^Scouncil^T^N1^T^S4904-0A1B2C3D^B^t^t^^")
local s = C.Serialize("x", "a b^c~d\030e\127f\001")
check("strings escaped", s == "^1^Sx^Sa~`b~}c~|d~ze~{f~A^^")
local ok, cmd, v = C.Deserialize(s)
check("escapes read back", ok and cmd == "x" and v == "a b^c~d\030e\127f\001")
local data = { 1, 2.5, -7, 0.1, 1e300, true, false, "s", { nested = { deep = "yes" }, [3] = 4 },
    gear1 = "item:30242::::::::70", note = "bis phase 2" }
ok, cmd, v = C.Deserialize(C.Serialize("response", data))
check("tables, numbers, booleans round trip", ok and cmd == "response" and Same(v, data))
check("0.1 exactly", v[4] == 0.1)
ok, cmd, v = C.Deserialize("^1^Sa^N" .. "1.#INF" .. "^^")
check("infinity", ok and v == math.huge)
check("spaces and line breaks in the text are ignored", select(3, C.Deserialize("^1^Sa ^N1\n2^^")) == 12)
check("not serializer text", C.Deserialize("hello") == nil and C.Deserialize("^1^Sa") == nil)
ok, cmd, v = C.Deserialize("^1^Sx^T^N1^Z^N2^N5^t^^")
check("nil values make holes", ok and v[1] == nil and v[2] == 5)

-- ============ DEFLATE ============
local fixtures = dofile(REPO .. "/tests/deflate_fixtures.lua")
for i, f in ipairs(fixtures) do
    local out, err = C.Inflate(f.packed)
    check("zlib stream " .. i .. " (level " .. f.level .. ") inflates" .. (err and (": " .. err) or ""), out == f.plain)
end
for _, str in ipairs({ "", "a", string.rep("xyz", 30000), fixtures[3].plain }) do
    check("stored blocks round trip (" .. #str .. " bytes)", C.Inflate(C.Deflate(str)) == str)
end
check("broken data refused", C.Inflate("\255\255\255") == nil and C.Inflate(fixtures[1].packed:sub(1, 5)) == nil)

-- ============ The addon channel ============
local raw = "a\000b\001c\002"
local enc = C.EncodeChannel(raw)
check("channel encoding has no zero byte", not enc:find("%z") and enc == "a\001\002b\001\003c\002")
check("channel decoding", C.DecodeChannel(enc) == raw)
check("a zero byte is refused", C.DecodeChannel("a\000") == nil)

-- ============ AceComm framing ============
check("short message as is", #C.Frame("hello") == 1 and C.Frame("hello")[1] == "hello")
check("leading control byte escaped", C.Frame("\002abc")[1] == "\004\002abc")
local long = string.rep("0123456789", 60)
local parts = C.Frame(long)
check("long message in 254-byte parts", #parts == 3 and parts[1]:byte(1) == 1 and parts[2]:byte(1) == 2
    and parts[3]:byte(1) == 3 and #parts[1] == 255)
local un = C.NewUnframer()
local got
for _, p in ipairs(parts) do got = un("RCLC\tRAID\tBob", p) or got end
check("parts put back together", got == long)
check("escaped single message", un("k", "\004\002abc") == "\002abc")
check("a middle part with no start is dropped", un("k2", "\002x") == nil and un("k2", "\003y") == nil)

-- ============ Whole messages ============
local packed = C.Pack("vote", { 1, "Taslan-Nightslayer", 1 })
local un2 = C.NewUnframer()
local whole
for _, p in ipairs(packed) do whole = un2("k", p) or whole end
local command, args = C.Unpack(whole)
check("pack and unpack", command == "vote" and args[1] == 1 and args[2] == "Taslan-Nightslayer" and args[3] == 1)
local big = {}
for i = 1, 40 do big[i] = { string = "30242", session = i, boss = "Lady Vashj", owner = "Venhana-Nightslayer" } end
packed = C.Pack("lootTable", { big })
check("a big loot table splits", #packed > 1)
whole = nil
for _, p in ipairs(packed) do
    check("each part fits a message", #p <= 255)
    whole = un2("big", p) or whole
end
command, args = C.Unpack(whole)
check("a big loot table comes back whole", command == "lootTable" and #args[1] == 40 and args[1][40].session == 40)
-- A message as RCLootCouncil would send it: zlib-compressed serializer text
local zl = fixtures[3]
command, args = C.Unpack(C.EncodeChannel(zl.packed))
check("an RCLootCouncil-style compressed message", command == "response" and args[1] == 1
    and args[2].response == 1 and args[2].note == "bis phase 2")

io.write(pass, " passed, ", fail, " failed\n")
os.exit(fail == 0 and 0 or 1)
