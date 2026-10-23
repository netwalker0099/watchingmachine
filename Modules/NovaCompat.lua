-- Watching Machine: Nova addon compatibility (listen only)
-- Reads instance reset notices sent by Nova Instance Tracker (and the one
-- Nova World Buffs sends), so a group leader running a Nova addon tells us
-- about resets too. Nothing is ever sent in Nova's format.
--
-- Their messages, worked out in docs/NOVA-PROTOCOL.md (part 1):
--   prefix "NIT", on PARTY / RAID / INSTANCE_CHAT
--   AceComm framing: \004 escapes a leading control byte; \001 / \002 /
--     \003 mark the first / middle / last part of a long message
--   LibDeflate's addon-channel escape: \001\002 = \000, \001\003 = \001
--   raw DEFLATE (no zlib header)
--   LibSerialize (format 1) of one string: "<command> <version> <data>"
--
-- This file decodes that from scratch: the AceComm reassembly, the escape,
-- an inflater (RFC 1951) and a LibSerialize string reader. No Nova or
-- library code is included.

local AddonName, WM = ...
local Nova = {}
WM.Nova = Nova

local MAX_MESSAGE = 8192    -- reassembled or inflated: anything bigger is junk
local NIT_MIN_VERSION = 1.00

-- ============================================
-- ADDON-CHANNEL ESCAPE
-- ============================================

function Nova.Unescape(s)
    if type(s) ~= "string" then return nil end
    local bad = false
    local out = s:gsub("\001(.?)", function(c)
        if c == "\002" then return "\000" end
        if c == "\003" then return "\001" end
        bad = true
        return ""
    end)
    if bad then return nil end
    return out
end

-- ============================================
-- INFLATE (raw DEFLATE, RFC 1951)
-- ============================================

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
    67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local POW2 = {}
for i = 0, 31 do POW2[i] = 2 ^ i end

-- Canonical Huffman table from code lengths (lengths[0..n-1])
local function Huffman(lengths, n)
    local count, offs, symbol = {}, {}, {}
    for len = 0, 15 do count[len] = 0 end
    for s = 0, n - 1 do
        local len = lengths[s] or 0
        count[len] = count[len] + 1
    end
    offs[1] = 0
    for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
    for s = 0, n - 1 do
        local len = lengths[s] or 0
        if len ~= 0 then
            symbol[offs[len]] = s
            offs[len] = offs[len] + 1
        end
    end
    return { count = count, symbol = symbol }
end

local fixedLit, fixedDist
local function FixedTables()
    if not fixedLit then
        local l = {}
        for s = 0, 143 do l[s] = 8 end
        for s = 144, 255 do l[s] = 9 end
        for s = 256, 279 do l[s] = 7 end
        for s = 280, 287 do l[s] = 8 end
        fixedLit = Huffman(l, 288)
        local d = {}
        for s = 0, 29 do d[s] = 5 end
        fixedDist = Huffman(d, 30)
    end
    return fixedLit, fixedDist
end

-- Returns the inflated string, or nil, reason
function Nova.Inflate(data, maxOut)
    maxOut = maxOut or MAX_MESSAGE
    local pos, buf, cnt = 1, 0, 0
    local out, n = {}, 0

    local function Bits(need)
        while cnt < need do
            local b = data:byte(pos)
            if not b then error("truncated", 0) end
            pos = pos + 1
            buf = buf + b * POW2[cnt]
            cnt = cnt + 8
        end
        local v = buf % POW2[need]
        buf = (buf - v) / POW2[need]
        cnt = cnt - need
        return v
    end

    local function Decode(h)
        local code, first, index = 0, 0, 0
        for len = 1, 15 do
            code = code + Bits(1)
            local c = h.count[len]
            if code - c < first then return h.symbol[index + (code - first)] end
            index = index + c
            first = (first + c) * 2
            code = code * 2
        end
        error("bad code", 0)
    end

    local function Put(byte)
        n = n + 1
        if n > maxOut then error("too long", 0) end
        out[n] = byte
    end

    local function Codes(lit, dist)
        while true do
            local sym = Decode(lit)
            if sym < 256 then
                Put(sym)
            elseif sym == 256 then
                return
            else
                sym = sym - 256
                if sym > 29 then error("bad length", 0) end
                local len = LEN_BASE[sym] + Bits(LEN_EXTRA[sym])
                local dsym = Decode(dist)
                if dsym > 29 then error("bad distance", 0) end
                local d = DIST_BASE[dsym + 1] + Bits(DIST_EXTRA[dsym + 1])
                if d > n then error("distance too far", 0) end
                for _ = 1, len do Put(out[n - d + 1]) end
            end
        end
    end

    local ok, err = pcall(function()
        repeat
            local final = Bits(1)
            local kind = Bits(2)
            if kind == 0 then
                -- Stored: skip to the byte boundary
                buf, cnt = 0, 0
                local b1, b2, b3, b4 = data:byte(pos, pos + 3)
                if not b4 then error("truncated", 0) end
                local len, nlen = b1 + b2 * 256, b3 + b4 * 256
                if len + nlen ~= 65535 then error("bad stored block", 0) end
                pos = pos + 4
                for i = pos, pos + len - 1 do
                    local b = data:byte(i)
                    if not b then error("truncated", 0) end
                    Put(b)
                end
                pos = pos + len
            elseif kind == 1 then
                Codes(FixedTables())
            elseif kind == 2 then
                local nlen, ndist, ncode = Bits(5) + 257, Bits(5) + 1, Bits(4) + 4
                if nlen > 286 or ndist > 30 then error("bad counts", 0) end
                local lengths = {}
                for i = 1, 19 do lengths[CODE_ORDER[i]] = 0 end
                for i = 1, ncode do lengths[CODE_ORDER[i]] = Bits(3) end
                local codeTable = Huffman(lengths, 19)
                local all, i = {}, 0
                while i < nlen + ndist do
                    local sym = Decode(codeTable)
                    if sym < 16 then
                        all[i] = sym
                        i = i + 1
                    else
                        local value, rep = 0, 0
                        if sym == 16 then
                            if i == 0 then error("repeat with no length", 0) end
                            value, rep = all[i - 1], 3 + Bits(2)
                        elseif sym == 17 then
                            rep = 3 + Bits(3)
                        else
                            rep = 11 + Bits(7)
                        end
                        if i + rep > nlen + ndist then error("too many lengths", 0) end
                        for _ = 1, rep do all[i] = value; i = i + 1 end
                    end
                end
                local lit, dist = {}, {}
                for s = 0, nlen - 1 do lit[s] = all[s] end
                for s = 0, ndist - 1 do dist[s] = all[nlen + s] end
                Codes(Huffman(lit, nlen), Huffman(dist, ndist))
            else
                error("bad block type", 0)
            end
        until final == 1
    end)
    if not ok then return nil, err end

    local parts = {}
    for i = 1, n, 4096 do
        parts[#parts + 1] = string.char(unpack(out, i, math.min(n, i + 4095)))
    end
    return table.concat(parts)
end

-- ============================================
-- LIBSERIALIZE (format 1): one string value
-- ============================================

function Nova.ReadSerializedString(s)
    if type(s) ~= "string" or s:byte(1) ~= 1 then return nil end
    local b = s:byte(2)
    if not b then return nil end
    local len, start
    if b % 16 == 2 then
        len, start = (b - 2) / 16, 3                       -- short: length in the type byte
    elseif b == 112 then
        len, start = s:byte(3), 4                          -- 1-byte length
    elseif b == 120 then
        local h, l = s:byte(3, 4)
        if not l then return nil end
        len, start = h * 256 + l, 5                        -- 2-byte length
    elseif b == 128 then
        local h, m, l = s:byte(3, 5)
        if not l then return nil end
        len, start = (h * 256 + m) * 256 + l, 6            -- 3-byte length
    else
        return nil                                         -- not a single string
    end
    if not len or #s ~= start + len - 1 then return nil end
    return s:sub(start, start + len - 1)
end

-- ============================================
-- LIBSERIALIZE (format 1): any value
-- ============================================
-- The full value format: numbers (embedded, 16 / 24 / 32 / 56-bit, double,
-- decimal string), booleans, nil, strings, tables, arrays, mixed tables,
-- and back-references to strings (over 2 bytes) and tables seen earlier.

local MAX_OBJECTS, MAX_DEPTH = 20000, 32

local function ReadDouble(b1, b2, b3, b4, b5, b6, b7, b8)
    local sign = b1 > 127 and -1 or 1
    local expo = (b1 % 128) * 16 + math.floor(b2 / 16)
    local mant = ((((((b2 % 16) * 256 + b3) * 256 + b4) * 256 + b5) * 256 + b6) * 256 + b7) * 256 + b8
    if expo == 0 and mant == 0 then return sign * 0.0 end
    if expo == 2047 then return mant == 0 and sign * math.huge or 0 / 0 end
    return sign * (1 + mant / 4503599627370496) * 2 ^ (expo - 1023)
end

-- Returns ok, value1, value2, ... (ok false, reason on bad data)
function Nova.Deserialize(s)
    if type(s) ~= "string" or s:byte(1) ~= 1 then return false, "not LibSerialize format 1" end
    local pos, objects = 2, 0
    local strings, tables = {}, {}

    local function Bytes(n)
        local chunk = s:sub(pos, pos + n - 1)
        if #chunk < n then error("truncated", 0) end
        pos = pos + n
        return chunk
    end
    local function Int(n)
        local v = 0
        for i = 1, n do
            local b = s:byte(pos)
            if not b then error("truncated", 0) end
            v = v * 256 + b
            pos = pos + 1
        end
        return v
    end
    local function Str(len)
        local v = Bytes(len)
        if len > 2 then strings[#strings + 1] = v end
        return v
    end

    local Read
    local function Table(count, t, depth)
        if not t then t = {}; tables[#tables + 1] = t end
        for _ = 1, count do
            local k = Read(depth)
            local v = Read(depth)
            if k == nil then error("nil key", 0) end
            t[k] = v
        end
        return t
    end
    local function Array(count, t, depth)
        if not t then t = {}; tables[#tables + 1] = t end
        for i = 1, count do t[i] = Read(depth) end
        return t
    end
    local function Mixed(arrayCount, mapCount, depth)
        local t = {}
        tables[#tables + 1] = t
        Array(arrayCount, t, depth)
        Table(mapCount, t, depth)
        return t
    end

    local TYPED = {
        [0] = function() return nil end,
        [1] = function() return Int(2) end, [2] = function() return -Int(2) end,
        [3] = function() return Int(3) end, [4] = function() return -Int(3) end,
        [5] = function() return Int(4) end, [6] = function() return -Int(4) end,
        [7] = function() return Int(7) end, [8] = function() return -Int(7) end,
        [9] = function() return ReadDouble(Bytes(8):byte(1, 8)) end,
        [10] = function() return tonumber(Bytes(Int(1))) end,
        [11] = function() return -(tonumber(Bytes(Int(1))) or 0) end,
        [12] = function() return true end, [13] = function() return false end,
        [14] = function() return Str(Int(1)) end, [15] = function() return Str(Int(2)) end,
        [16] = function() return Str(Int(3)) end,
        [17] = function(d) return Table(Int(1), nil, d) end, [18] = function(d) return Table(Int(2), nil, d) end,
        [19] = function(d) return Table(Int(3), nil, d) end,
        [20] = function(d) return Array(Int(1), nil, d) end, [21] = function(d) return Array(Int(2), nil, d) end,
        [22] = function(d) return Array(Int(3), nil, d) end,
        [23] = function(d) local a, m = Int(1), Int(1); return Mixed(a, m, d) end,
        [24] = function(d) local a, m = Int(2), Int(2); return Mixed(a, m, d) end,
        [25] = function(d) local a, m = Int(3), Int(3); return Mixed(a, m, d) end,
        [26] = function() return strings[Int(1)] end, [27] = function() return strings[Int(2)] end,
        [28] = function() return strings[Int(3)] end,
        [29] = function() return tables[Int(1)] end, [30] = function() return tables[Int(2)] end,
        [31] = function() return tables[Int(3)] end,
    }

    function Read(depth)
        depth = (depth or 0) + 1
        if depth > MAX_DEPTH then error("too deep", 0) end
        objects = objects + 1
        if objects > MAX_OBJECTS then error("too big", 0) end
        local b = Int(1)
        if b % 2 == 1 then return (b - 1) / 2 end                   -- 7-bit number
        if b % 4 == 2 then                                          -- type with its count
            local typ = (b - 2) / 4
            local count = math.floor(typ / 4)
            typ = typ % 4
            if typ == 0 then return Str(count) end
            if typ == 1 then return Table(count, nil, depth) end
            if typ == 2 then return Array(count, nil, depth) end
            return Mixed(count % 4 + 1, math.floor(count / 4) + 1, depth)
        end
        if b % 8 == 4 then                                          -- 12-bit number
            local packed = Int(1) * 256 + b
            if b % 16 == 12 then return -(packed - 12) / 16 end
            return (packed - 4) / 16
        end
        local reader = TYPED[b / 8]
        if not reader then error("unknown type " .. b, 0) end
        return reader(depth)
    end

    local results, n = {}, 0
    local ok, err = pcall(function()
        while pos <= #s do
            n = n + 1
            results[n] = Read(0)
        end
    end)
    if not ok then return false, err end
    return true, unpack(results, 1, n)
end

-- ============================================
-- LIBDEFLATE CODECS
-- ============================================
-- LibDeflate's codecs replace "reserved" bytes with an escape byte plus a
-- substitute (or, for the first few, with a single "map" byte). The table
-- of substitutes is rebuilt here from the same three lists it's made from.

local function Codec(reserved, escapes, map)
    local taken, decode = {}, {}
    local all = reserved .. escapes .. map
    for i = 1, #all do taken[all:byte(i)] = true end
    local mapped = {}
    for i = 1, #map do
        mapped[map:byte(i)] = reserved:sub(i, i)
    end
    local alreadyMapped = {}
    for i = 1, #map do alreadyMapped[reserved:sub(i, i)] = true end
    local escIndex, r = 1, 0
    local esc = escapes:byte(1)
    decode[esc] = {}
    for i = 1, #all do
        local c = all:sub(i, i)
        if not alreadyMapped[c] then
            while r >= 256 or taken[r] do
                r = r + 1
                if r > 255 then
                    escIndex = escIndex + 1
                    esc = escapes:byte(escIndex)
                    if not esc then return nil end
                    decode[esc] = {}
                    r = 0
                end
            end
            decode[esc][r] = c
            r = r + 1
        end
    end
    local reservedSet = {}
    for i = 1, #reserved do reservedSet[reserved:byte(i)] = true end
    return function(str)
        if type(str) ~= "string" then return nil end
        local out, i, n = {}, 1, #str
        while i <= n do
            local b = str:byte(i)
            if decode[b] then
                local nb = str:byte(i + 1)
                local c = nb and decode[b][nb]
                if not c then return nil end
                out[#out + 1] = c
                i = i + 2
            elseif mapped[b] then
                out[#out + 1] = mapped[b]
                i = i + 1
            elseif reservedSet[b] then
                return nil                     -- a reserved byte can't appear encoded
            else
                out[#out + 1] = string.char(b)
                i = i + 1
            end
        end
        return table.concat(out)
    end
end
Nova.Codec = Codec

local chatHigh = {}
for i = 128, 255 do chatHigh[#chatHigh + 1] = string.char(i) end
Nova.DecodeChat = Codec("sS\000\010\013\124%" .. table.concat(chatHigh), "\029\031", "\015\020")
Nova.DecodeAddon = Codec("\000", "\001", "")

-- Body of a Nova message -> the values it carries. distribution picks the
-- codec: YELL / SAY use the chat-channel one.
function Nova.DecodeBody(body, distribution)
    local decode = (distribution == "YELL" or distribution == "SAY") and Nova.DecodeChat or Nova.DecodeAddon
    local raw = decode(body)
    if not raw then return nil end
    local inflated = Nova.Inflate(raw)
    if not inflated then return nil end
    return Nova.Deserialize(inflated)
end

-- Whole pipeline: one complete message body -> "<cmd> <version> <data>"
function Nova.DecodeNIT(body)
    local raw = Nova.Unescape(body)
    if not raw then return nil end
    local inflated = Nova.Inflate(raw)
    if not inflated then return nil end
    local text = Nova.ReadSerializedString(inflated)
    if not text then return nil end
    local cmd, version, data = text:match("^(%S+) (%S+) ?(.*)$")
    if not cmd then return nil end
    return cmd, tonumber(version), data
end

-- ============================================
-- ACECOMM FRAMING
-- ============================================

local partial = {}   -- prefix .. distribution .. sender -> buffered parts

-- Returns the whole message once complete, else nil
function Nova.Reassemble(prefix, message, distribution, sender)
    local control = message:byte(1)
    if not control or control > 9 or control == 0 then return message end
    local rest = message:sub(2)
    local key = prefix .. "\031" .. (distribution or "") .. "\031" .. (sender or "")
    if control == 4 then return rest end
    if control == 1 then
        partial[key] = { rest }
        return nil
    end
    local buffered = partial[key]
    if not buffered then return nil end
    buffered[#buffered + 1] = rest
    local size = 0
    for _, part in ipairs(buffered) do size = size + #part end
    if size > MAX_MESSAGE then partial[key] = nil return nil end
    if control == 2 then return nil end
    if control == 3 then
        partial[key] = nil
        return table.concat(buffered)
    end
    partial[key] = nil
    return nil
end

-- ============================================
-- RESET NOTICES
-- ============================================

local function ShortName(sender)
    if type(sender) ~= "string" then return "?" end
    if Ambiguate then
        local ok, name = pcall(Ambiguate, sender, "none")
        if ok and name then sender = name end
    end
    return sender
end

-- Ambiguate drops our own realm, so our own messages come back as our name
local function IsMe(sender)
    return ShortName(sender) == UnitName("player")
end

-- Only the leader of the group you're in can reset its instances; Nova
-- itself doesn't check, so we do
local function IsGroupLeader(name)
    if not (IsInGroup and IsInGroup()) then return false end
    local inGroup = (UnitInParty and UnitInParty(name)) or (UnitInRaid and UnitInRaid(name))
    return inGroup and UnitIsGroupLeader and UnitIsGroupLeader(name) and true or false
end

-- Returns what it showed, for tests: "shown" / "quiet" / nil (ignored)
function Nova:OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= "NIT" or type(message) ~= "string" then return nil end
    if distribution ~= "PARTY" and distribution ~= "RAID" and distribution ~= "INSTANCE_CHAT" then return nil end
    if IsMe(sender) then return nil end
    local IT = WM.modules.InstanceTracker
    if not IT or not IT.DB or not IT.DB().novaListen then return nil end

    local body = Nova.Reassemble(prefix, message, distribution, sender)
    if not body then return nil end
    local cmd, version, data = Nova.DecodeNIT(body)
    if not cmd or not data or data == "" then return nil end

    local who = ShortName(sender)
    if not IsGroupLeader(who) then return nil end

    if cmd == "instanceReset" or cmd == "instanceResetNoMsg" then
        if not version or version < NIT_MIN_VERSION then return nil end
        IT:MarkReset(data)
        if cmd == "instanceReset" then
            -- They also posted it to group chat themselves
            return "quiet"
        end
        IT:PrintLink(data .. " has been reset by the group leader (" .. who .. ", Nova Instance Tracker).")
        return "shown"
    elseif cmd == "instanceResetOther" then
        -- From Nova World Buffs. Its sender only fires when the reset fails
        -- (players still inside): see docs/NOVA-PROTOCOL.md, part 1 section 6
        IT:PrintLink("The group leader (" .. who .. ") tried to reset " .. data
            .. ", but players are still inside (Nova World Buffs).")
        return "shown"
    end
    return nil
end

local events = CreateFrame("Frame")
function Nova:Start()
    if self.started then return end
    self.started = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, "NIT")
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, "NIT")
    end
    WM:RegisterEvents(events, { "CHAT_MSG_ADDON" })
end
events:SetScript("OnEvent", function(_, _, prefix, message, distribution, sender)
    local ok, err = pcall(Nova.OnAddonMessage, Nova, prefix, message, distribution, sender)
    if not ok and WM.VerbosePrint then WM:VerbosePrint("Nova", tostring(err)) end
end)
