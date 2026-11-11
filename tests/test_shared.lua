-- Core's shared helpers: the catch-up engine (WM.NewCatchUp, used by the
-- armory, Roster Manager and Loot Council), the worn-gear reader, the
-- character key and CSV fields.
-- Usage: lua5.1 test_shared.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local timers = {}
env.C_Timer = { NewTimer = function(delay, fn)
    local t = { delay = delay, fn = fn, Cancel = function(self) self.cancelled = true end }
    timers[#timers + 1] = t
    return t
end, After = function() end }
local function Fire()      -- run the newest timer, if it wasn't cancelled
    local t = table.remove(timers)
    if t and not t.cancelled then t.fn() end
    return t
end
local links = { [1] = "|Hitem:1|h[Helm]|h", [5] = "|Hitem:5|h[Chest]|h", [19] = "|Hitem:19|h[Tabard]|h" }
env.GetInventoryItemLink = function(unit, slot) if unit == "player" then return links[slot] end end
env.UnitName = function() return "Me" end
env.GetRealmName = function() return "Realm" end
W.load("Core.lua")
local WM = W.WM

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- The catch-up engine ----
local records = { a = 10, b = 30, c = 20 }       -- id -> stamp
local sent, on = {}, true
local C
C = WM.NewCatchUp({
    gap = 0.6,
    enabled = function() return on end,
    current = function(id) return records[id] end,
    send = function(id) sent[#sent + 1] = id; C:Heard(id, records[id]) end,
})
for id, stamp in pairs(records) do C:Offer(id, stamp, id) end
C:Start()
check("three waiting, one timer with a random first wait", C:Length() == 3 and #timers == 1
    and timers[1].delay >= 2 and timers[1].delay <= 8)
Fire()
check("newest first", sent[1] == "b" and C:Length() == 2)
check("then one every gap", #timers == 1 and timers[1].delay == 0.6)
-- Someone else sends c before our turn
C:Heard("c", 20)
Fire()
check("a record someone else sent meanwhile is skipped", sent[2] == "a" and #sent == 2 and C:Length() == 0)
check("nothing left: no more timers", #timers == 0)

-- Asked again: what went out before the new request doesn't count
sent = {}
C:Offer("b", 30, "b")
C:Start()
Fire()
check("asked again: sent again", sent[1] == "b")
-- A record that's gone, and one asked for twice while waiting
sent = {}
records.gone = 50
C:Offer("gone", 50, "gone")
C:Offer("a", 10, "a")
C:Offer("a", 10, "a")
C:Start()
check("the same record isn't queued twice", C:Length() == 2)
records.gone = nil
Fire()
check("a record that no longer exists is skipped", sent[1] == "a" and #sent == 1)
-- Off: nothing goes out; Stop empties the queue
sent = {}
C:Offer("b", 30, "b")
C:Start()
on = false
Fire()
check("sharing off: nothing is sent", #sent == 0)
on = true
C:Offer("c", 20, "c")
C:Start()
C:Stop()
check("stopped: nothing waiting, timer cancelled", C:Length() == 0 and (#timers == 0 or timers[#timers].cancelled))
check("heard is kept by a plain stop", C:SentSince("b", 30, 0))
C:Stop(true)
check("and dropped when asked to forget", not C:SentSince("b", 30, 0))

-- ---- Worn gear ----
local worn = WM.EquippedLinks("player")
check("worn gear by slot", worn[1] == links[1] and worn[5] == links[5] and worn[19] == links[19] and worn[2] == nil)
check("up to a last slot", WM.EquippedLinks("player", 18)[19] == nil)
check("nobody: nothing", next(WM.EquippedLinks("target")) == nil)

-- ---- Character key, CSV ----
check("character key", WM.PlayerKey() == "Me-Realm" and WM:CharKey() == "Me-Realm")
env.UnitName = function() return "Alt" end
check("the key follows the character", WM.PlayerKey() == "Alt-Realm")
check("csv: plain, quoted, colour codes out", WM.CsvField("abc") == "abc" and WM.CsvField('a,"b"') == '"a,""b"""'
    and WM.CsvField("|cffff0000Red|r") == "Red" and WM.CsvField(nil) == "")

io.write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
