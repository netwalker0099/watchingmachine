-- No addon file assigns a game global. Writing one from addon code "taints"
-- it, and the game's own code that reads it afterwards can be blocked from
-- protected actions: 3.48 and before reassigned StaticPopupDialogs, which
-- the game reads when Escape is pressed, and the Escape menu's Log Out
-- stopped working. Allowed: our saved variables (...DB), WM_ frame names,
-- slash commands (SLASH_...) and key binding names (BINDING_...).
-- Reads the compiled code (luac -l): $LUAC if set, else luac5.1, else luac
-- (Windows installs name it luac.exe); skipped if none is Lua 5.1.
-- Usage: lua5.1 test_globals.lua <repo>
local REPO = assert(arg[1], "repo path")

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- cmd.exe drops the first and last quote of a line with more than two, so
-- Windows needs the whole line wrapped once more.
local WINDOWS = package.config:sub(1, 1) == "\\"
local function popen(line)
    return io.popen(WINDOWS and ('"' .. line .. '"') or line)
end

local LUAC
local candidates = { "luac5.1", "luac" }
if os.getenv("LUAC") then table.insert(candidates, 1, os.getenv("LUAC")) end
for _, cmd in ipairs(candidates) do
    local probe = popen('"' .. cmd .. '" -v 2>&1')
    local version = probe and probe:read("*a") or ""
    if probe then probe:close() end
    if version:find("Lua 5.1", 1, true) then LUAC = cmd; break end
end
if not LUAC then
    print("0 passed, 0 failed (luac for Lua 5.1 not found: skipped)")
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
        local p = popen('"' .. LUAC .. '" -l -p "' .. REPO .. "/" .. rel .. '" 2>&1')
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
