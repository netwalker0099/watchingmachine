-- Start-up robustness: timers, module initialisation, events the client
-- doesn't have. Reproduces the 3.11 mage login error spam
-- ("Attempt to register unknown event LEARNED_SPELL_IN_TAB", ~60/s).
-- Usage: lua5.1 test_startup.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

-- Error handler plumbing, as the client provides it
local errors = {}
local current = function(e) errors[#errors + 1] = tostring(e) end
env.seterrorhandler = function(fn) current = fn end
env.geterrorhandler = function() return current end
env.debugstack = function() return "" end

-- RegisterEvent throws on events this client doesn't have, like the real one
local UNKNOWN = { LEARNED_SPELL_IN_TAB = true, PLAYER_TALENT_UPDATE = true }
function W.Frame:RegisterEvent(ev)
    if UNKNOWN[ev] then
        error('Frame:RegisterEvent(): Attempt to register unknown event "' .. ev .. '"', 2)
    end
    self._events = self._events or {}
    self._events[ev] = true
end

-- Keep every frame, to find the timer frame and the modules' event frames
local frames = {}
local realCreate = env.CreateFrame
env.CreateFrame = function(...) local f = realCreate(...); frames[#frames + 1] = f; return f end

for line in io.lines(REPO .. "/WatchingMachine.toc") do
    if line:match("%.lua$") then W.load(line) end
end
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local timerFrame
for _, f in ipairs(frames) do
    local s = f:GetScript("OnUpdate")
    if s and debug.getinfo(s, "S").source:find("Core.lua", 1, true) then timerFrame = f break end
end
check("found Core's timer frame", timerFrame ~= nil)
local function Tick(dt) W.fire(timerFrame, "OnUpdate", dt or 0.016) end

-- ---- timers ----
local RunAfter = W.realRunAfter
local ran, after = 0, 0
RunAfter(0.1, function() ran = ran + 1; error("boom from a timer") end)
RunAfter(0.1, function() after = after + 1 end)
Tick(0.2)
check("failing one-shot timer ran once", ran == 1)
check("its error was reported", #errors >= 1 and errors[#errors]:find("boom", 1, true) ~= nil)
check("another timer due the same frame still ran", after == 1)
for _ = 1, 30 do Tick(0.2) end
check("failing timer does not fire again every frame", ran == 1)
check("one error, not one per frame", (function()
    local n = 0
    for _, e in ipairs(errors) do if e:find("boom", 1, true) then n = n + 1 end end
    return n == 1
end)())

local chained = 0
RunAfter(0.1, function() RunAfter(0.1, function() chained = chained + 1 end) end)
Tick(0.2); Tick(0.2)
check("a timer scheduled inside a callback still runs", chained == 1)

local ticks = 0
WM.RunTicker(0.5, function() ticks = ticks + 1; error("ticker boom") end)
Tick(0.6); Tick(0.1); Tick(0.5)
check("a failing ticker keeps its interval instead of firing every frame", ticks == 2)

-- ---- start-up: mage login on a client without LEARNED_SPELL_IN_TAB ----
for k in pairs(errors) do errors[k] = nil end
env.UnitClass = function() return "Mage", "MAGE" end
local initCount = {}
for name, m in pairs(WM.modules) do
    local orig = m.Initialize
    if orig then
        m.Initialize = function(self, ...)
            initCount[name] = (initCount[name] or 0) + 1
            return orig(self, ...)
        end
    end
end
-- A module that throws during start-up, to prove it can't take others down
WM.modules.ZZBroken = { Initialize = function() error("broken module") end }

WM:OnSecurityCheckPassed()
local unknownEvent = false
for _, e in ipairs(errors) do
    if e:find("unknown event", 1, true) then unknownEvent = true end
end
check("mage login raises no unknown-event error", not unknownEvent)
check("the broken module's error is reported", (function()
    for _, e in ipairs(errors) do if e:find("ZZBroken:Initialize failed", 1, true) then return true end end
end)())
local everyone = true
for name, m in pairs(WM.modules) do
    if name ~= "ZZBroken" and m.Initialize and initCount[name] ~= 1 then
        everyone = false
        io.write("  not initialised once: ", name, " (", tostring(initCount[name]), ")\n")
    end
end
check("every other module initialised exactly once", everyone)

WM:OnSecurityCheckPassed()
check("start-up runs only once", initCount.ClassMage == 1 and initCount.BuffCheck == 1)

-- The mage module still hooked the events it needs
local mageEvents
for _, f in ipairs(frames) do
    local h = f:GetScript("OnEvent")
    if h and debug.getinfo(h, "S").source:find("ClassMage", 1, true) then mageEvents = rawget(f, "_events") end
end
check("mage listens for SPELLS_CHANGED", mageEvents and mageEvents.SPELLS_CHANGED)
check("mage listens for PLAYER_REGEN_ENABLED", mageEvents and mageEvents.PLAYER_REGEN_ENABLED)
check("mage no longer asks for LEARNED_SPELL_IN_TAB", mageEvents and not mageEvents.LEARNED_SPELL_IN_TAB)
check("portal refresh still scheduled after start-up", #W.timers > 0)

-- Warlock: PLAYER_TALENT_UPDATE missing must not break it either
for k in pairs(errors) do errors[k] = nil end
env.UnitClass = function() return "Warlock", "WARLOCK" end
local ok, err = pcall(WM.modules.ClassWarlock.Initialize, WM.modules.ClassWarlock)
check("warlock start-up survives a missing PLAYER_TALENT_UPDATE", ok)
if not ok then io.write("  ", tostring(err), "\n") end

-- RegisterEvents helper
local f = realCreate(nil, nil, nil)
local n = WM:RegisterEvents(f, { "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_REGEN_ENABLED" })
check("RegisterEvents skips unknown events and registers the rest", n == 2
    and f._events.SPELLS_CHANGED and f._events.PLAYER_REGEN_ENABLED)

-- No module registers LEARNED_SPELL_IN_TAB directly any more
for line in io.lines(REPO .. "/WatchingMachine.toc") do
    if line:match("%.lua$") then
        local h = io.open(REPO .. "/" .. line); local src = h:read("*a"); h:close()
        check(line .. " doesn't RegisterEvent LEARNED_SPELL_IN_TAB",
            not src:find('RegisterEvent%("LEARNED_SPELL_IN_TAB"%)'))
    end
end

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
