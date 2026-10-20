-- Module panels built with WM.UI: Auto Logger, Aura Range, Guild Invite.
-- Usage: lua5.1 test_panels_social1.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/AutoLogger.lua")
W.load("Modules/AuraRange.lua")
W.load("Modules/GuildInvite.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
env.IsInInstance = function() return true, "raid" end
env.GetInstanceInfo = function() return "Karazhan", "raid", 0, "Normal", 10 end
local cvars = { advancedCombatLogging = "1" }
env.GetCVar = function(k) return cvars[k] end
env.SetCVar = function(k, v) cvars[k] = v end
local chatLog, combatLog
env.LoggingChat = function(v) chatLog = v end
env.LoggingCombat = function(v) combatLog = v end
local roster = { "Alice-Testrealm", "Bob-Testrealm" }
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i) return roster[i] end
env.strsplit = function(sep, s) return (s:match("^([^" .. sep .. "]*)")) end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function Init(mod)
    local ok = pcall(mod.Initialize, mod)
    if not ok then mod:InitDB() end
end

local function FindCheckbox(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then
            return w
        end
    end
end
local function FindSlider(panel, name)
    for _, w in ipairs(panel.layout.widgets) do
        if rawget(w, "slider") and w.slider:GetName() == name then return w end
    end
end
local function FindEditBox(panel)
    for _, w in ipairs(panel.layout.widgets) do
        if rawget(w, "editBox") then return w end
    end
end
local function FindButton(list, text)
    for _, w in ipairs(list) do
        if w.GetText and w:GetText() == text then return w end
    end
end
local function Escapes(name)
    for _, v in ipairs(env.UISpecialFrames) do if v == name then return true end end
    return false
end
local function Fits(panel)
    return panel:GetHeight() <= 700 and panel:GetHeight() <= 768 - 16
end

-- ============ Auto Logger ============
local AL = WM.modules.AutoLogger
Init(AL)
local ap = AL:CreateSettingsUI()
AL:OpenSettings()
check("auto logger panel shown", ap:IsShown())
check("auto logger panel fits", Fits(ap))
check("auto logger panel isn't scrolling", not ap.scrollBar:IsShown())
check("auto logger same frame on reopen", AL:CreateSettingsUI() == ap)
check("auto logger Escape registered", Escapes("WM_AutoLoggerSettings"))

local dungeon = FindCheckbox(ap, "Combat Logging in Dungeons")
check("dungeon checkbox reflects default", dungeon and dungeon:GetChecked() == false)
W.click(dungeon)
check("dungeon checkbox writes", env.AutoLoggerDB.enableInDungeons == true)
local debug = FindCheckbox(ap, "Debug Mode")
W.click(debug)
check("debug checkbox writes", env.AutoLoggerDB.debugMode == true)
check("debug checkbox has a tooltip", debug:GetScript("OnEnter") ~= nil)

local combat = FindCheckbox(ap, "Combat Logging in Raids")
W.click(combat)
check("combat checkbox off writes and stops logging", env.AutoLoggerDB.enableCombatLog == false and combatLog == 0)
W.click(combat)
check("combat checkbox on starts logging in a raid", env.AutoLoggerDB.enableCombatLog == true and combatLog == 1)
check("status shows the instance and logging state",
    ap.statusText:GetText():find("Karazhan", 1, true) and ap.statusText:GetText():find("Logging|r", 1, true))

cvars.advancedCombatLogging = "0"
local adv = FindCheckbox(ap, "Advanced Combat Logging")
W.click(adv)
check("advanced checkbox off writes", env.AutoLoggerDB.enableAdvancedLogging == false)
W.click(adv)
check("advanced checkbox on re-enables the CVar", cvars.advancedCombatLogging == "1")

W.click(FindCheckbox(ap, "Chat Logging"))
check("chat checkbox off writes", env.AutoLoggerDB.enableChatLog == false)

AL:ToggleUI()
check("auto logger toggles closed", not ap:IsShown())

-- ============ Aura Range ============
local AR = WM.modules.AuraRange
Init(AR)
local rp = AR:CreateUI()
AR:Toggle()
check("aura range panel shown", rp:IsShown())
check("aura range panel fits", Fits(rp))
check("aura range same frame on reopen", AR:CreateUI() == rp)
check("aura range Escape registered", Escapes("WM_AuraRangeSettings"))

local enable = FindCheckbox(rp, "Enable out-of-range alerts")
check("enable checkbox matches IsModuleEnabled", enable:GetChecked() == AR:IsModuleEnabled())
W.click(enable)
check("enable checkbox turns the module off", AR:IsModuleEnabled() == false and env.AuraRangeDB.enabled == false)
AR:SetModuleEnabled(true)
check("dashboard switch refreshes the open panel", enable:GetChecked() == true)

local lock = FindCheckbox(rp, "Lock alert frame")
W.click(lock)
check("lock checkbox writes", env.AuraRangeDB.locked == true)
check("lock checkbox has a tooltip", lock:GetScript("OnEnter") ~= nil)
local sound = FindCheckbox(rp, "Play sound")
W.click(sound)
check("sound checkbox writes", env.AuraRangeDB.soundEnabled == false)

local slider = FindSlider(rp, "WM_AuraRangeTimeoutSlider")
check("timeout slider keeps its name", slider ~= nil)
slider.slider:SetValue(21.6)
check("timeout slider writes", env.AuraRangeDB.alertTimeout == 22)
check("timeout slider has a tooltip", slider.slider:GetScript("OnEnter") ~= nil)

local wf = FindCheckbox(rp, "Windfury Totem")
check("windfury row present and off by default", wf and wf:GetChecked() == false)
W.click(wf)
check("aura checkbox writes", env.AuraRangeDB.trackedAuras.windfury == true)

-- Test Alert shows the HUD frame; a second click doesn't add a second line
local testBtn
for _, w in ipairs(rp.layout.widgets) do
    if w.GetText and w:GetText() == "Test Alert" then testBtn = w end
end
W.click(testBtn)
W.click(testBtn)
check("test alert shows the alert frame", env.WM_AuraRangeAlertFrame:IsShown())
check("test alert shows one line", env.WM_AuraRangeAlertFrame.lines[1]:IsShown()
    and not env.WM_AuraRangeAlertFrame.lines[2]:IsShown())

-- ============ Guild Invite ============
local GI = WM.modules.GuildInvite
Init(GI)
local gp = GI:CreateUI()
GI:Toggle()
check("guild invite panel shown", gp:IsShown())
check("guild invite panel fits", Fits(gp) and gp:GetHeight() <= 600)
check("guild invite has a list area", gp.layout.fill ~= nil and gp.scrollChild ~= nil)
check("guild invite same frame on reopen", GI:CreateUI() == gp)
check("guild invite Escape registered", Escapes("WM_GuildInviteFrame"))
check("roster count in the footer", gp.statusText:GetText() == "Roster: 2 members")

local genable = FindCheckbox(gp, "Enable auto-invite")
check("enable checkbox matches IsModuleEnabled", genable:GetChecked() == GI:IsModuleEnabled())
W.click(genable)
check("enable checkbox turns the module off", GI:IsModuleEnabled() == false)
GI:SetModuleEnabled(true)
check("dashboard switch refreshes the open panel", genable:GetChecked() == true)

local trig = FindEditBox(gp)
check("trigger box shows the saved word", trig:GetText() == "inv")
trig.editBox:SetText(" 123 ")
W.fire(trig.editBox, "OnEnterPressed")
check("trigger saved on Enter", env.GuildInviteDB.trigger == "123")
trig.editBox:SetFocus()
trig.editBox:SetText("invme")
trig.editBox:ClearFocus()
check("trigger saved on focus lost", env.GuildInviteDB.trigger == "invme")

local respond = FindCheckbox(gp, "Reply to non-guild")
W.click(respond)
check("respond checkbox writes", env.GuildInviteDB.respondToNonGuild == true)
local announce = FindCheckbox(gp, "Announce invites")
W.click(announce)
check("announce checkbox writes", env.GuildInviteDB.announceInvites == false)

-- Log entries render in the list, and new invites show up while it's open
GI:LogInvite("Alice", "Guild")
GI:LogInvite("Bob", "Whisper")
check("log rows rendered", #gp.logEntries == 2 and gp.logEntries[1]:IsShown())
check("newest invite first", gp.logEntries[1]:GetText():find("Bob", 1, true) ~= nil)
check("scroll child grows", gp.scrollChild:GetHeight() == 28)

local clearBtn
for _, w in ipairs(gp.layout.widgets) do
    if w.GetText and w:GetText() == "Clear" then clearBtn = w end
end
W.click(clearBtn)
check("clear empties the log", #env.GuildInviteDB.inviteLog == 0 and not gp.logEntries[1]:IsShown())

roster[3] = "Carol-Testrealm"
W.click(FindButton(gp.footerButtons, "Refresh Roster"))
check("refresh roster updates the count", gp.statusText:GetText() == "Roster: 3 members")

env.UIParent:SetHeight(400)
gp:Hide(); gp:Show()
check("guild invite shrinks to a short screen", gp:GetHeight() == 400 - 16)
env.UIParent:SetHeight(768)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
