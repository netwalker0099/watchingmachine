-- Watching Machine: Loot Council's message format, compatible with
-- RCLootCouncil (our own code, written from the formats' specifications):
--   * Serialize / Deserialize: AceSerializer-3.0's text form ("^1 ... ^^")
--   * Deflate / Inflate: raw DEFLATE (RFC 1951). We write stored blocks
--     (any reader accepts them); we read all three block types.
--   * EncodeChannel / DecodeChannel: \000 -> \001\002, \001 -> \001\003
--   * Frame / Unframe: AceComm's split of long messages into 254-byte parts
-- RCLootCouncil's messages are Frame(EncodeChannel(Deflate(Serialize(command, args)))).

local AddonName, WM = ...
local Codec = {}
WM.LootCodec = Codec

-- ============================================
-- ACESERIALIZER TEXT FORM
-- ============================================

local function EscapeChar(c)
    local n = c:byte()
    if n == 30 then return "~z" end
    if n <= 32 then return "~" .. string.char(n + 64) end
    if n == 94 then return "~}" end
    if n == 126 then return "~|" end
    if n == 127 then return "~{" end
end

local function SerializeValue(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "^S"
        out[#out + 1] = (v:gsub("[%c \94\126\127]", EscapeChar))
    elseif t == "number" then
        local s = tostring(v)
        if v ~= v then
            out[#out + 1] = "^N"; out[#out + 1] = "nan"
        elseif tonumber(s) == v then
            out[#out + 1] = "^N"; out[#out + 1] = s
        elseif v == math.huge then
            out[#out + 1] = "^N"; out[#out + 1] = "1.#INF"
        elseif v == -math.huge then
            out[#out + 1] = "^N"; out[#out + 1] = "-1.#INF"
        else
            local m, e = math.frexp(v)
            out[#out + 1] = "^F"; out[#out + 1] = string.format("%.0f", m * 2 ^ 53)
            out[#out + 1] = "^f"; out[#out + 1] = tostring(e - 53)
        end
    elseif t == "table" then
        out[#out + 1] = "^T"
        for k, val in pairs(v) do
            SerializeValue(k, out)
            SerializeValue(val, out)
        end
        out[#out + 1] = "^t"
    elseif t == "boolean" then
        out[#out + 1] = v and "^B" or "^b"
    elseif t == "nil" then
        out[#out + 1] = "^Z"
    else
        error("can't serialize a " .. t)
    end
end

function Codec.Serialize(...)
    local out = { "^1" }
    for i = 1, select("#", ...) do SerializeValue((select(i, ...)), out) end
    out[#out + 1] = "^^"
    return table.concat(out)
end

local function UnescapeChar(e)
    if e == "~z" then return "\030" end
    if e == "~{" then return "\127" end
    if e == "~|" then return "~" end
    if e == "~}" then return "^" end
    return string.char(e:byte(2) - 64)
end

-- The values, or nil and an error
function Codec.Deserialize(s)
    if type(s) ~= "string" then return nil, "not a string" end
    s = s:gsub("[%c ]", "")
    local tokens = {}
    for tag, data in s:gmatch("(^.)([^^]*)") do tokens[#tokens + 1] = { tag, data } end
    if not tokens[1] or tokens[1][1] ~= "^1" then return nil, "not AceSerializer data" end
    local i = 2
    local ReadValue
    local function ReadNumber(data)
        if data == "1.#INF" or data == "inf" then return math.huge end
        if data == "-1.#INF" or data == "-inf" then return -math.huge end
        if data == "nan" or data == "-1.#IND" or data == "1.#QNAN" then return 0 / 0 end
        return tonumber(data)
    end
    function ReadValue()
        local tok = tokens[i]
        if not tok then error("ran out of data") end
        i = i + 1
        local tag, data = tok[1], tok[2]
        if tag == "^S" then
            return (data:gsub("~.", UnescapeChar))
        elseif tag == "^N" then
            local n = ReadNumber(data)
            if not n then error("bad number") end
            return n
        elseif tag == "^F" then
            local e = tokens[i]
            if not e or e[1] ~= "^f" then error("bad float") end
            i = i + 1
            return tonumber(data) * 2 ^ tonumber(e[2])
        elseif tag == "^B" then return true
        elseif tag == "^b" then return false
        elseif tag == "^Z" then return nil
        elseif tag == "^T" then
            local t = {}
            while true do
                local nx = tokens[i]
                if not nx then error("unfinished table") end
                if nx[1] == "^t" then i = i + 1; return t end
                local k = ReadValue()
                local v = ReadValue()
                if k ~= nil then t[k] = v end
            end
        end
        error("unknown tag " .. tag)
    end
    local results, n = {}, 0
    local ok, err = pcall(function()
        while tokens[i] and tokens[i][1] ~= "^^" do
            n = n + 1
            results[n] = ReadValue()
        end
        if not tokens[i] then error("no end marker") end
    end)
    if not ok then return nil, err end
    return true, unpack(results, 1, n)
end

-- ============================================
-- RAW DEFLATE
-- ============================================

-- Stored blocks only: valid DEFLATE that every reader accepts
function Codec.Deflate(s)
    local out = {}
    local len, pos = #s, 1
    repeat
        local n = math.min(65535, len - pos + 1)
        local final = (pos + n > len) and 1 or 0
        out[#out + 1] = string.char(final, n % 256, math.floor(n / 256), (65535 - n) % 256, math.floor((65535 - n) / 256))
        out[#out + 1] = s:sub(pos, pos + n - 1)
        pos = pos + n
    until pos > len
    return table.concat(out)
end

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
    3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- A canonical Huffman code from code lengths (lengths[sym], sym from 0):
-- counts per length and the symbols in code order
local function BuildCode(lengths, n)
    local counts, offs, symbols = {}, {}, {}
    for l = 0, 15 do counts[l] = 0 end
    for s = 0, n - 1 do counts[lengths[s] or 0] = counts[lengths[s] or 0] + 1 end
    offs[1] = 0
    for l = 1, 14 do offs[l + 1] = offs[l] + counts[l] end
    for s = 0, n - 1 do
        local l = lengths[s] or 0
        if l > 0 then
            symbols[offs[l]] = s
            offs[l] = offs[l] + 1
        end
    end
    return { counts = counts, symbols = symbols }
end

local FIXED_LIT, FIXED_DIST
do
    local l = {}
    for s = 0, 143 do l[s] = 8 end
    for s = 144, 255 do l[s] = 9 end
    for s = 256, 279 do l[s] = 7 end
    for s = 280, 287 do l[s] = 8 end
    FIXED_LIT = BuildCode(l, 288)
    local d = {}
    for s = 0, 29 do d[s] = 5 end
    FIXED_DIST = BuildCode(d, 30)
end

-- The decompressed string, or nil and an error
function Codec.Inflate(data)
    if type(data) ~= "string" then return nil, "not a string" end
    local pos, buf, cnt = 1, 0, 0
    local out, outLen = {}, 0
    local function Bits(n)
        while cnt < n do
            local b = data:byte(pos)
            if not b then error("ran out of data") end
            pos = pos + 1
            buf = buf + b * 2 ^ cnt
            cnt = cnt + 8
        end
        local p = 2 ^ n
        local v = buf % p
        buf = (buf - v) / p
        cnt = cnt - n
        return v
    end
    local function Decode(code)
        local c, first, index = 0, 0, 0
        for len = 1, 15 do
            c = c + Bits(1)
            local count = code.counts[len]
            if c - first < count then return code.symbols[index + c - first] end
            index = index + count
            first = (first + count) * 2
            c = c * 2
        end
        error("bad code")
    end
    local function Blocks(lit, dist)
        while true do
            local sym = Decode(lit)
            if sym < 256 then
                outLen = outLen + 1
                out[outLen] = sym
            elseif sym == 256 then
                return
            else
                sym = sym - 257
                if sym >= 29 then error("bad length") end
                local len = LEN_BASE[sym + 1] + Bits(LEN_EXTRA[sym + 1])
                local ds = Decode(dist)
                if ds >= 30 then error("bad distance") end
                local d = DIST_BASE[ds + 1] + Bits(DIST_EXTRA[ds + 1])
                if d > outLen then error("distance too far") end
                for _ = 1, len do
                    outLen = outLen + 1
                    out[outLen] = out[outLen - d]
                end
            end
        end
    end
    local ok, err = pcall(function()
        local final
        repeat
            final = Bits(1)
            local kind = Bits(2)
            if kind == 0 then
                buf, cnt = 0, 0                               -- to the next byte
                local a, b, c, d = data:byte(pos, pos + 3)
                if not d then error("ran out of data") end
                local n = a + b * 256
                if n ~= 65535 - (c + d * 256) then error("bad stored length") end
                pos = pos + 4
                if pos + n - 1 > #data then error("ran out of data") end
                for k = 0, n - 1 do
                    outLen = outLen + 1
                    out[outLen] = data:byte(pos + k)
                end
                pos = pos + n
            elseif kind == 1 then
                Blocks(FIXED_LIT, FIXED_DIST)
            elseif kind == 2 then
                local nlen, ndist, ncode = Bits(5) + 257, Bits(5) + 1, Bits(4) + 4
                local cl = {}
                for k = 1, ncode do cl[CL_ORDER[k]] = Bits(3) end
                local clCode = BuildCode(cl, 19)
                local lengths, k = {}, 0
                while k < nlen + ndist do
                    local sym = Decode(clCode)
                    if sym < 16 then
                        lengths[k] = sym; k = k + 1
                    else
                        local rep, val = 0, 0
                        if sym == 16 then
                            if k == 0 then error("repeat with nothing before") end
                            val, rep = lengths[k - 1], 3 + Bits(2)
                        elseif sym == 17 then rep = 3 + Bits(3)
                        else rep = 11 + Bits(7) end
                        for _ = 1, rep do lengths[k] = val; k = k + 1 end
                    end
                end
                local litLens, distLens = {}, {}
                for s = 0, nlen - 1 do litLens[s] = lengths[s] end
                for s = 0, ndist - 1 do distLens[s] = lengths[nlen + s] end
                Blocks(BuildCode(litLens, nlen), BuildCode(distLens, ndist))
            else
                error("bad block type")
            end
        until final == 1
    end)
    if not ok then return nil, err end
    local parts = {}
    for k = 1, outLen, 4096 do parts[#parts + 1] = string.char(unpack(out, k, math.min(k + 4095, outLen))) end
    return table.concat(parts)
end

-- ============================================
-- THE ADDON CHANNEL (no \000 in a message)
-- ============================================

function Codec.EncodeChannel(s)
    return (s:gsub("[%z\001]", function(c) return c == "\000" and "\001\002" or "\001\003" end))
end

function Codec.DecodeChannel(s)
    if type(s) ~= "string" or s:find("%z") then return nil end
    local bad = false
    local r = s:gsub("\001(.?)", function(c)
        if c == "\002" then return "\000" elseif c == "\003" then return "\001" end
        bad = true
        return ""
    end)
    if bad then return nil end
    return r
end

-- ============================================
-- ACECOMM FRAMING
-- ============================================

local PART = 254

-- The messages to send for one long string
function Codec.Frame(s)
    local first = s:byte(1) or 0
    if #s <= 255 and not (first >= 1 and first <= 9) then return { s } end
    if #s < 255 and first >= 1 and first <= 9 then return { "\004" .. s } end
    local parts = {}
    local pos = 1
    while pos <= #s do
        local chunk = s:sub(pos, pos + PART - 1)
        pos = pos + PART
        local mark = (#parts == 0) and "\001" or (pos > #s and "\003" or "\002")
        parts[#parts + 1] = mark .. chunk
    end
    return parts
end

-- A reassembler: Unframe(key, message) returns the whole string when it's complete
function Codec.NewUnframer()
    local spool = {}
    return function(key, msg)
        local c = msg:byte(1)
        if c == 1 then
            spool[key] = { msg:sub(2) }
        elseif c == 2 then
            if spool[key] then table.insert(spool[key], msg:sub(2)) end
        elseif c == 3 then
            local parts = spool[key]
            spool[key] = nil
            if parts then
                parts[#parts + 1] = msg:sub(2)
                return table.concat(parts)
            end
        elseif c == 4 then
            return msg:sub(2)
        elseif c and c >= 5 and c <= 9 then
            return nil
        else
            return msg
        end
    end
end

-- ============================================
-- WHOLE MESSAGES
-- ============================================

-- The framed messages for an RCLootCouncil command
function Codec.Pack(command, args)
    return Codec.Frame(Codec.EncodeChannel(Codec.Deflate(Codec.Serialize(command, args or {}))))
end

-- command, args from a whole (unframed) message, or nil
function Codec.Unpack(s)
    local decoded = Codec.DecodeChannel(s)
    if not decoded then return nil end
    local inflated = Codec.Inflate(decoded)
    if not inflated then return nil end
    local ok, command, args = Codec.Deserialize(inflated)
    if not ok or type(command) ~= "string" then return nil end
    return command, type(args) == "table" and args or {}
end
