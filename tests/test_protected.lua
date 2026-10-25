-- Calls the game restricts in combat: CheckInteractDistance is asked only
-- through WM:InteractRange, which never calls it in combat (on 2.5.x the
-- game blocks it there and blames the addon, even inside a pcall).
-- Usage: lua5.1 test_protected.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local combat, calls = false, 0
env.InCombatLockdown = function() return combat end
env.CheckInteractDistance = function(unit, i) calls = calls + 1; return unit == "party1" end
W.load("Core.lua")
local WM = W.WM

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- Nothing but Core asks the game directly ----
local direct = {}
for line in io.lines(REPO .. "/WatchingMachine.toc") do
    local rel = line:match("^([%w_/%.]+%.lua)%s*$")
    if rel and rel ~= "Core.lua" then
        local n = 0
        for src in io.lines(REPO .. "/" .. rel) do
            n = n + 1
            local code = src:gsub("%-%-.*$", "")
            if code:find("CheckInteractDistance", 1, true) then direct[#direct + 1] = rel .. ":" .. n end
        end
    end
end
if #direct > 0 then io.write("direct calls: ", table.concat(direct, ", "), "\n") end
check("only Core calls CheckInteractDistance (through WM:InteractRange)", #direct == 0)

-- ---- The helper ----
check("out of combat: in range", WM:InteractRange("party1", 1) == true and calls == 1)
check("out of combat: out of range", WM:InteractRange("party2", 1) == false and calls == 2)
combat = true
check("in combat: unknown, and the game isn't asked", WM:InteractRange("party1", 1) == nil and calls == 2)
combat = false
env.CheckInteractDistance = function() error("blocked") end
check("an error: unknown", WM:InteractRange("party1", 1) == nil)
env.CheckInteractDistance = false
check("no such function: unknown", WM:InteractRange("party1", 1) == nil)
check("no unit: unknown", WM:InteractRange(nil, 1) == nil)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
