-- Watching Machine: alert sounds
-- One list of sounds any alert can offer in a dropdown: the addon's own
-- (Media/Sounds: ours, and CC0 sounds by Robin Lamb and Kenney, see
-- Media/Sounds/CREDITS.txt) and the game's. A choice is saved as a string:
--   "wm:<name>"   a file in Media/Sounds (<name>.ogg)
--   "kit:<id>"    a game sound kit, played with PlaySound
--   "none"        silent
-- WoW only finds new sound files after a full game restart, not a /reload.

local AddonName, WM = ...
local Sounds = {}
WM.Sounds = Sounds

local MEDIA = "Interface\\AddOns\\" .. (AddonName or "WatchingMachine") .. "\\Media\\Sounds\\"

Sounds.OPTIONS = {
    { value = "wm:potion", text = "Potion (Watching Machine)" },
    { value = "wm:rune", text = "Rune (Watching Machine)" },
    -- The sound pack (Media/Sounds/CREDITS.txt)
    { value = "wm:alarm", text = "Alarm, short" },
    { value = "wm:alarm_long", text = "Alarm, long" },
    { value = "wm:chimes", text = "Chimes" },
    { value = "wm:ding", text = "Ding" },
    { value = "wm:ding_deep", text = "Deep ding" },
    { value = "wm:uh_oh", text = "Uh-oh" },
    { value = "wm:confirm", text = "Confirm" },
    { value = "wm:error", text = "Error" },
    { value = "wm:error_low", text = "Error, low" },
    { value = "wm:glass", text = "Glass" },
    { value = "wm:question", text = "Question" },
    -- The game's
    { value = "kit:8959", text = "Raid warning" },
    { value = "kit:8960", text = "Ready check" },
    { value = "kit:12867", text = "Alarm clock" },
    { value = "kit:8332", text = "PvP flag captured" },
    { value = "kit:891", text = "Coins" },
    { value = "kit:888", text = "Level up" },
}

-- More of the game's sounds, by their name in the game's SOUNDKIT list:
-- only those this client has are offered
Sounds.GAME_SOUNDS = {
    { "RAID_BOSS_EMOTE_WARNING", "Boss emote warning" },
    { "UI_RAID_BOSS_WHISPER_WARNING", "Boss whisper warning" },
    { "PVP_THROUGH_QUEUE", "Queue pop" },
    { "LFG_ROLE_CHECK", "Role check" },
    { "IG_PLAYER_INVITE", "Group invite" },
    { "TELL_MESSAGE", "Whisper" },
    { "MAP_PING", "Map ping" },
    { "IG_QUEST_FAILED", "Quest failed" },
    { "TUTORIAL_POPUP", "Tutorial pop-up" },
    { "ALARM_CLOCK_WARNING_1", "Alarm clock 2" },
    { "ALARM_CLOCK_WARNING_3", "Alarm clock 3" },
}

do
    local kits = rawget(_G, "SOUNDKIT")
    local have = {}
    for _, o in ipairs(Sounds.OPTIONS) do have[o.value] = true end
    for _, s in ipairs(Sounds.GAME_SOUNDS) do
        local id = type(kits) == "table" and tonumber(kits[s[1]])
        if id and not have["kit:" .. id] then
            have["kit:" .. id] = true
            Sounds.OPTIONS[#Sounds.OPTIONS + 1] = { value = "kit:" .. id, text = s[2] }
        end
    end
    Sounds.OPTIONS[#Sounds.OPTIONS + 1] = { value = "none", text = "None" }
end

Sounds.CHANNELS = {
    { value = "Master", text = "Master" },
    { value = "SFX", text = "Sound effects" },
    { value = "Dialog", text = "Dialog" },
}

function Sounds.Path(name) return MEDIA .. name .. ".ogg" end

-- Plays a saved choice; true if something was played
function Sounds.Play(choice, channel)
    if type(choice) ~= "string" or choice == "none" then return false end
    channel = channel or "Master"
    local file = choice:match("^wm:([%w_%-]+)$")
    if file and PlaySoundFile then
        return pcall(PlaySoundFile, Sounds.Path(file), channel) and true or false
    end
    local kit = tonumber(choice:match("^kit:(%d+)$"))
    if kit and PlaySound then
        return pcall(PlaySound, kit, channel) and true or false
    end
    return false
end

function Sounds.Label(choice)
    for _, o in ipairs(Sounds.OPTIONS) do
        if o.value == choice then return o.text end
    end
    return tostring(choice)
end
