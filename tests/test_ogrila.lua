-- Ogri'la Helper: recording the sequence, stepping on each beam touched,
-- undoing on Reprisal, opening at a relic, hotkeys and combat, the window.
-- Usage: lua5.1 test_ogrila.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local clock = 100
env.GetTime = function() return clock end
local ME = "Player-1-00000001"
local npc
env.UnitGUID = function(u) if u == "player" then return ME elseif u == "npc" then return npc end end
local debuff                       -- { id, expires } or nil
env.UnitDebuff = function(_, i)
    if i == 1 and debuff then return "Introspection", nil, 0, nil, 30, debuff[2], nil, nil, nil, debuff[1] end
end
local bags = { [32569] = 87, [32572] = 2 }
env.GetItemCount = function(id) return bags[id] or 0 end
env.C_Item = {}
local lockdown = false
env.InCombatLockdown = function() return lockdown end
local bindings, cleared = {}, 0
env.SetOverrideBindingClick = function(_, _, key, button) bindings[key] = button end
env.ClearOverrideBindings = function() bindings = {}; cleared = cleared + 1 end
local errs = {}
env.UIErrorsFrame = { AddMessage = function(_, m) errs[#errs + 1] = m end }
local hooks = {}
env.hooksecurefunc = function(t, name, fn) hooks[name] = fn end
env.C_GossipInfo = { SelectOption = function() end, SelectOptionByIndex = function() end }
env.SelectGossipOption = nil
env.PlaySound = function() end

for _, f in ipairs({ "Core.lua", "UI.lua", "Modules/Ogrila.lua" }) do W.load(f) end
local WM = W.WM
local OG = WM.modules.Ogrila
env.WatchingMachineDB = { theme = "Default" }
OG:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local h = env.WM_OgrilaHelper
local function Tick() clock = clock + 0.5; h._scripts.OnUpdate(h) end
local function Touch(expires) debuff = { 40165, expires }; Tick() end
local function Reprisal()
    OG:OnCombatEvent(0, "SPELL_DAMAGE", false, "GameObject-0-1-530-1-185890-1", "Apexis Relic", 0, 0, ME, "Me", 0, 0, 40065)
end

-- ---- Starting a relic ----
check("hooks the gossip choices", hooks.SelectOption and hooks.SelectOptionByIndex)
check("hidden until needed", not h:IsShown())
npc = "Creature-0-1-530-1-23253-0000000001"
hooks.SelectOption()
check("a normal NPC doesn't open it", not h:IsShown())
check("relic GUIDs", OG.RelicFor("GameObject-0-4170-530-12-185944-00002A1B3C") == "Apexis Monument"
    and OG.RelicFor("Creature-0-1-530-1-185890-1") == nil and OG.RelicFor(nil) == nil)
OG.seq[1] = 1
npc = "GameObject-0-4170-530-12-185890-00002A1B3C"
hooks.SelectOption()
check("the relic opens it", h:IsShown() and OG.relic == "Apexis Relic")
check("fresh sequence", #OG.seq == 0 and OG.pos == 0 and env.OgrilaDB.games["Apexis Relic"] == 1)
check("title", h.title:GetText():find("Apexis Relic", 1, true) ~= nil)
check("shards and crystals", h.status:GetText():find("Shards|r 87", 1, true) and h.status:GetText():find("Crystals|r 2", 1, true))
check("asks you to record", h.line:GetText():find("Click the colours", 1, true) ~= nil)

-- ---- Hotkeys ----
check("G/Y/B/R bound to the buttons", bindings.G == "WM_OgrilaColor1" and bindings.Y == "WM_OgrilaColor2"
    and bindings.B == "WM_OgrilaColor3" and bindings.R == "WM_OgrilaColor4")
check("keys shown on the buttons", h.colors[1].key:GetText() == "G")

-- ---- Recording ----
W.click(h.colors[1]); W.click(h.colors[3]); W.click(h.colors[3]); W.click(h.colors[4])
check("recorded in order", table.concat(OG.seq, ",") == "1,3,3,4")
check("slots show it", h.slots[4]:IsShown() and not h.slots[5]:IsShown() and h.slots[2].num:GetText() == 2)
check("next: the first", OG:Next() == 1 and h.slots[1].ring:IsShown() and not h.slots[2].ring:IsShown()
    and h.line:GetText():find("Green", 1, true) and h.line:GetText():find("1 of 4", 1, true))

-- ---- Touching the beams ----
Tick()
check("no debuff yet: nothing moves", OG.pos == 0)
Touch(130)
check("the debuff appearing isn't a touch", OG.pos == 0)
Touch(131)
check("refreshed: one step on", OG.pos == 1 and OG:Next() == 3 and h.slots[1]._alpha < 1 and h.slots[2].ring:IsShown())
Touch(131)
check("same expiry: no step", OG.pos == 1)
Touch(132)
check("second", OG.pos == 2)
Touch(133)
Reprisal()
check("Reprisal puts the step back", OG.pos == 2 and OG:Next() == 3)
OG:OnCombatEvent(0, "SPELL_DAMAGE", false, "x", "x", 0, 0, "Player-1-2", "Other", 0, 0, 40065)
check("someone else's Reprisal doesn't", OG.pos == 2)
Touch(134); Touch(135)
check("done", OG:Done() and h.line:GetText():find("Done", 1, true) and env.OgrilaDB.best["Apexis Relic"] == 4)
check("best on the status line", h.status:GetText():find("Best|r 4", 1, true) ~= nil)
Touch(136)
check("extra touches past the end do nothing", OG.pos == 4)
W.click(h.colors[2])
check("after a finished sequence, a click starts the next one", table.concat(OG.seq, ",") == "2" and OG.pos == 0)
debuff = nil
Tick()
Touch(200)
check("debuff gone and back: not a touch", OG.pos == 0)

-- ---- Editing ----
W.click(h.colors[1]); W.click(h.colors[4]); W.click(h.colors[3])   -- 2,1,4,3
h.slots[2]._scripts.OnClick(h.slots[2], "LeftButton")
check("left click removes one", table.concat(OG.seq, ",") == "2,4,3")
h.slots[2]._scripts.OnClick(h.slots[2], "RightButton")
check("right click removes it and the rest", table.concat(OG.seq, ",") == "2")
Touch(201)
OG:Remove(1)
check("removing a touched one", #OG.seq == 0 and OG.pos == 0)
for _ = 1, 20 do OG:Add(1) end
check("at most 16", #OG.seq == 16 and h.slots[16]:IsShown())
h.clearBtn._scripts.OnClick(h.clearBtn)
check("clear", #OG.seq == 0)
OG:Add(9)
check("unknown colour ignored", #OG.seq == 0)

-- ---- Combat ----
check("bound before combat", bindings.G ~= nil and OG.bound)
-- The event frame isn't named: catch it by initialising again
local evFrame
local origRegister = WM.RegisterEvents
WM.RegisterEvents = function(_, fr) evFrame = fr end
OG:Initialize()
WM.RegisterEvents = origRegister
local function Event(ev) evFrame._scripts.OnEvent(evFrame, ev) end
Event("PLAYER_REGEN_DISABLED")
lockdown = true
check("combat: keys freed", next(bindings) == nil and not OG.bound and h.colors[1].key:GetText() == "")
env.OgrilaDB.hotkeys = true
OG:UpdateBindings()
check("can't rebind in combat", next(bindings) == nil)
lockdown = false
Event("PLAYER_REGEN_ENABLED")
check("back after combat", bindings.G == "WM_OgrilaColor1" and OG.bound)
env.OgrilaDB.unbindCombat = false
Event("PLAYER_REGEN_DISABLED")
check("keep them if asked", bindings.G ~= nil)
lockdown = true
h:Hide()
check("closing in combat waits", bindings.G ~= nil and OG.pendingBind and #errs > 0)
lockdown = false
Event("PLAYER_REGEN_ENABLED")
check("then frees them", next(bindings) == nil and not OG.bound)
env.OgrilaDB.unbindCombat = true

-- ---- Options ----
OG:Toggle()
local p = env.WM_OgrilaFrame
check("options window", p:IsShown())
env.OgrilaDB.keys[1] = "SHIFT-1"
OG:ShowHelper()
check("custom key", bindings["SHIFT-1"] == "WM_OgrilaColor1" and bindings.G == nil)
env.OgrilaDB.hotkeys = false
OG:UpdateBindings()
check("hotkeys off", next(bindings) == nil and h.colors[1].key:GetText() == "")
env.OgrilaDB.hotkeys = true
env.OgrilaDB.autoOpen = false
h:Hide()
hooks.SelectOption()
check("auto-open off", not h:IsShown())
env.OgrilaDB.autoOpen = true
-- Turned off on this character: closes, and relics don't open it
OG:ShowHelper()
WM:SetModuleOn("Ogrila", false)
check("off: the helper closes", not h:IsShown() and next(bindings) == nil)
hooks.SelectOption()
check("off: relics don't open it", not h:IsShown())
WM:SetModuleOn("Ogrila", true)
OG:Command("")
check("command toggles the helper", h:IsShown())
OG:Command("clear")
check("status", OG:GetQuickStatus():find("87 shards", 1, true) and OG:GetQuickStatus():find("best 4", 1, true))
local tipped = {}
env.GameTooltip.SetText = function(_, t) tipped[#tipped + 1] = t end
h.colors[2]._scripts.OnEnter(h.colors[2])
check("button tooltip", tipped[#tipped] == "Add Yellow")
env.OgrilaDB.tooltips = false
local n = #tipped
h.colors[2]._scripts.OnEnter(h.colors[2])
check("tooltips off", #tipped == n)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
