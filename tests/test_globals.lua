-- No addon file assigns a game global. Writing one from addon code "taints"
-- it, and the game's own code that reads it afterwards can be blocked from
-- protected actions: 3.48 and before reassigned StaticPopupDialogs, which
-- the game reads when Escape is pressed, and the Escape menu's Log Out
-- stopped working. Allowed: our saved variables (...DB), WM_ frame names,
-- slash commands (SLASH_...) and key binding names (BINDING_...).
-- Reads the compiled code (luac5.1 -l); skipped if luac5.1 isn't there.
-- Usage: lua5.1 test_globals.lua <repo>
local REPO = assert(arg[1], "repo path")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local probe = io.popen("luac5.1 -v 2>&1")
local version = probe and probe:read("*a") or ""
if probe then probe:close() end
if not version:find("Lua 5.1", 1, true) then
    print("0 passed, 0 failed (luac5.1 not found: skipped)")
    return
end

local function Allowed(name)
    return name:find("^WM_") or name:find("DB$") or name:find("^SLASH_") or name:find("^BINDING_")
end

local files = 0
for line in io.lines(REPO .. "/WatchingMachine.toc") do
    local rel = line:match("^([%w_/%.]+%.lua)%s*$")
    if rel and not rel:find("^Data/") then
        files = files + 1
        local p = io.popen("luac5.1 -l -p '" .. REPO .. "/" .. rel .. "' 2>&1")
        local listing = p:read("*a")
        p:close()
        local bad = {}
        for name in listing:gmatch("SETGLOBAL%s+%S+%s+%S+%s*; ([%w_]+)") do
            if not Allowed(name) then bad[name] = true end
        end
        local names = {}
        for n in pairs(bad) do names[#names + 1] = n end
        table.sort(names)
        check(rel .. " assigns no game globals" .. (#names > 0 and (": " .. table.concat(names, ", ")) or ""), #names == 0)
    end
end
check("files checked", files > 20)
os.remove("luac.out")

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
