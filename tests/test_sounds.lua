-- Warning sounds: every addon sound in the list has its file in
-- Media/Sounds (and every file there is offered and credited), the game's
-- extra sounds appear only when the client has them, None stays last, and
-- playing a choice reaches the right game call.
-- Usage: lua5.1 test_sounds.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local played = {}
env.PlaySoundFile = function(path, channel) played[#played + 1] = { "file", path, channel } return true end
env.PlaySound = function(id, channel) played[#played + 1] = { "kit", id, channel } return true end
-- The client's sound kit list: one known, one the addon already offers by number
env.SOUNDKIT = { RAID_BOSS_EMOTE_WARNING = 12197, RAID_WARNING = 8959, ALARM_CLOCK_WARNING_2 = 12867 }
W.load("Sounds.lua")
local S = W.WM.Sounds

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function Exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
end
local credits = io.open(REPO .. "/Media/Sounds/CREDITS.txt"):read("*a")

-- ---- The addon's own sounds ----
local files, offered = 0, {}
for _, o in ipairs(S.OPTIONS) do
    local name = o.value:match("^wm:(.+)$")
    if name then
        files = files + 1
        offered[name] = true
        if not Exists(REPO .. "/Media/Sounds/" .. name .. ".ogg") then io.write("no file: ", name, "\n"); files = -999 end
        if not credits:find(name .. ".ogg", 1, true) then io.write("not credited: ", name, "\n"); files = -999 end
    end
end
check("every addon sound has its file and a credit", files == 13)
-- Every file in Media/Sounds is offered
local dir = REPO .. "/Media/Sounds"
local WINDOWS = package.config:sub(1, 1) == "\\"
local p = io.popen(WINDOWS and ('dir /b "' .. dir:gsub("/", "\\") .. '"') or ('ls "' .. dir .. '"'))
local listed = p and p:read("*a") or ""
if p then p:close() end
local stray, found = {}, 0
for name in listed:gmatch("([%w_%-]+)%.ogg") do
    found = found + 1
    if not offered[name] then stray[#stray + 1] = name end
end
check("every sound file is offered", found == 13 and #stray == 0)
check("the sound pack is credited with its licence", credits:find("Robin Lamb", 1, true) and credits:find("Kenney", 1, true)
    and select(2, credits:gsub("CC0 1.0", "")) == 2)

-- ---- The game's sounds ----
local labels = {}
for _, o in ipairs(S.OPTIONS) do labels[o.text] = o.value end
check("a game sound the client has is offered", labels["Boss emote warning"] == "kit:12197")
check("one it doesn't have isn't", labels["Queue pop"] == nil and labels["Role check"] == nil)
check("a sound already offered by number isn't offered twice", labels["Alarm clock 3"] == nil
    and select(2, (function() local n = 0; for _, o in ipairs(S.OPTIONS) do if o.value == "kit:12867" then n = n + 1 end end; return nil, n end)()) == 1)
check("None is last", S.OPTIONS[#S.OPTIONS].value == "none")
local seen, dup = {}, false
for _, o in ipairs(S.OPTIONS) do if seen[o.value] then dup = true end; seen[o.value] = true end
check("no choice twice", not dup)

-- ---- Playing ----
check("a pack sound plays its file", S.Play("wm:chimes", "SFX") and played[#played][1] == "file"
    and played[#played][2]:find("Media\\Sounds\\chimes.ogg", 1, true) and played[#played][3] == "SFX")
check("a game sound plays its kit", S.Play("kit:12197") and played[#played][1] == "kit" and played[#played][2] == 12197
    and played[#played][3] == "Master")
check("labels", S.Label("wm:uh_oh") == "Uh-oh" and S.Label("kit:12197") == "Boss emote warning")
check("bad choices play nothing", not S.Play("wm:../x") and not S.Play("none") and not S.Play(nil))

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
