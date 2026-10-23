-- Watching Machine: alert sounds
-- One list of sounds any alert can offer in a dropdown: the addon's own
-- (Media/Sounds) and a few of the game's. A choice is saved as a string:
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
    { value = "kit:8959", text = "Raid warning" },
    { value = "kit:8960", text = "Ready check" },
    { value = "kit:12867", text = "Alarm clock" },
    { value = "kit:8332", text = "PvP flag captured" },
    { value = "kit:891", text = "Coins" },
    { value = "kit:888", text = "Level up" },
    { value = "none", text = "None" },
}

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
