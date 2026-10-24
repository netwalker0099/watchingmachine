-- ArmorySnap's gear browser on the WM.UI panel builder.
-- Usage: lua5.1 test_panels_armorysnap.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
W.load("Core.lua")
W.load("UI.lua")
W.load("Modules/ArmorySnap.lua")
local WM = W.WM
env.WatchingMachineDB = { theme = "Default" }
env.UnitExists = function() return false end
env.GetNumGroupMembers = function() return 0 end
env.GetItemInfo = function() return nil end
-- strsplit that honours the separator and limit (item links split on ":")
env.strsplit = function(sep, s, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then out[#out + 1] = s:sub(start) break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
    return unpack(out)
end

-- Record every frame so the browser's private pieces can be found
local created = {}
local baseCreate = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    local f = baseCreate(kind, name, parent, template)
    f._kind = kind
    created[#created + 1] = f
    return f
end

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

local function FindCheckbox(panel, pattern)
    for _, w in ipairs(panel.layout.widgets) do
        local t = rawget(w, "Text")
        if t and t:GetText() and t:GetText():find(pattern, 1, true) then return w end
    end
end
local function FindDropdown(panel, name)
    for _, w in ipairs(panel.layout.widgets) do
        local dd = rawget(w, "dropdown")
        if dd and dd:GetName() == name then return w, dd end
    end
end
local function SlotButton(slotId)
    for _, f in ipairs(created) do
        if rawget(f, "elvBg") and f.slotId == slotId then return f end
    end
end
local function ShownMembers()
    local names = {}
    for _, f in ipairs(created) do
        if rawget(f, "memberName") and f:IsShown() then names[#names + 1] = f.memberName end
    end
    table.sort(names)
    return names
end
local function BordersShown(f)
    local b = rawget(f, "_pxBorders")
    return b ~= nil and b[1]:IsShown()
end

-- Saved variables as AS:Initialize leaves them, plus a stale theme flag
-- from before the global theme took over
local AS = WM.modules.ArmorySnap
local HELM = "|cffa335ee|Hitem:28963:2999:0:0|h[Voidheart Crown]|h|r"
env.ArmorySnapDB = {
    options = { enabled = true, scanGroup = false, verbose = false, retentionDays = 30, elvuiTheme = true },
    snapshots = {
        ["2026-10-18 20:00 - Karazhan"] = { timestamp = "2026-10-18 20:00", zone = "Karazhan", members = {
            Alice = { name = "Alice", class = "WARLOCK", race = "Gnome", level = 70, guild = "", gear = {
                [1] = { link = HELM, icon = "Interface\\Icons\\Helm" } } },
            Bob = { name = "Bob", class = "WARRIOR", race = "Orc", level = 70, guild = "Ninjas", gear = {} },
        } },
        ["2026-10-19 20:00 - Gruul's Lair"] = { timestamp = "2026-10-19 20:00", zone = "Gruul's Lair", members = {
            Carol = { name = "Carol", class = "MAGE", race = "Human", level = 70, guild = "", gear = {},
                talents = { trees = { { name = "Arcane", icon = "a", points = 40 },
                    { name = "Fire", icon = "f", points = 0 }, { name = "Frost", icon = "i", points = 21 } },
                    spec = "Arcane", points = "40/0/21" } },
        } },
    },
}
AS.db = env.ArmorySnapDB

-- ============ Shell ============
AS.ToggleBrowseFrame()
local p = env.WM_ArmorySnapFrame
check("browse frame is a builder panel", p ~= nil and p.layout ~= nil and p.layout.fill ~= nil)
check("no Blizzard frame template any more", p._template == "BackdropTemplate")
check("browse frame shown", p:IsShown())
check("browse frame skinned by the global theme", WM._skinnedPanels[p] == true)
AS.ToggleBrowseFrame()
check("toggle hides it", not p:IsShown())
AS.ToggleBrowseFrame()
local esc = 0
for _, n in ipairs(env.UISpecialFrames) do if n == "WM_ArmorySnapFrame" then esc = esc + 1 end end
check("Escape registered exactly once", esc == 1)
check("one frame across toggles", env.WM_ArmorySnapFrame == p)
check("no more than 700 tall", p:GetHeight() <= 700)
check("about the old 632", math.abs(p:GetHeight() - 632) <= 8)

-- Fill must hold the right column: name 18 + detail 12 + guild 12 with
-- gaps (4+2+1+8), doll 8*39+36+16, talents 6+52, summary 6+12
local need = 4 + 18 + 2 + 12 + 1 + 12 + 8 + (8 * 39 + 36 + 16) + 6 + 52 + 6 + 12
local fillTop = select(5, p.layout.fill.frame:GetPoint(1))
local fillH = p:GetHeight() - 40 - 14 + fillTop
check("fill gives the paper doll its room", fillH >= need)
check("rows stack above the fill without overlap", -fillTop == 22 + 24 + 28)
check("width fits list + gap + doll inside the body", p:GetWidth() - 24 >= 180 + 10 + 330)

-- ============ Checkboxes ============
local o = env.ArmorySnapDB.options
local group, chat, auto = FindCheckbox(p, "Scan in group"), FindCheckbox(p, "Chat Log"), FindCheckbox(p, "Auto-scan")
check("three option checkboxes", group and chat and auto)
check("no ElvUI Theme checkbox", FindCheckbox(p, "ElvUI") == nil and rawget(env, "WM_ASThemeCB") == nil)
for _, cb in ipairs({ group, chat, auto }) do
    check("checkbox has a tooltip: " .. cb.Text:GetText(), cb:GetScript("OnEnter") ~= nil)
end
W.click(group)
check("Scan in group writes scanGroup", o.scanGroup == true)
W.click(chat)
check("Chat Log writes verbose", o.verbose == true)
check("Auto-scan starts on", auto:GetChecked() == true)
W.click(auto)
check("Auto-scan writes enabled", o.enabled == false and not AS.IsAutoScan())
AS.SetAutoScan(true)
check("SetAutoScan re-syncs the open checkbox", auto:GetChecked() == true and AS.IsAutoScan())
AS.SetAutoScan(false)
check("and back off", auto:GetChecked() == false)
AS.SetAutoScan(true)
AS.HandleSlash("group")
check("/as group updates the open checkbox", o.scanGroup == false and group:GetChecked() == false)
o.verbose = false
p:Hide(); p:Show()
check("reopen re-reads the options", chat:GetChecked() == false)

-- ============ Retention ============
local retBox, retDD = FindDropdown(p, "WM_ASRetentionDD")
check("retention dropdown present", retBox ~= nil)
check("retention dropdown has a tooltip", retDD:GetScript("OnEnter") ~= nil)
check("retention shows the saved value", env.UIDropDownMenu_GetText(retDD) == "30 days")
local items = W.openMenu(retDD)
check("retention lists four choices", #items == 4 and items[1].text == "1 day" and items[4].checked)
items[2].func()
check("retention writes retentionDays", o.retentionDays == 7)
check("retention label follows", env.UIDropDownMenu_GetText(retDD) == "7 days")

-- ============ Snapshots and members ============
local snapBox, snapDD = FindDropdown(p, "WM_ASSnapDD")
check("snapshot dropdown keeps its name", snapBox ~= nil)
check("newest snapshot selected on open", env.UIDropDownMenu_GetText(snapDD) == "2026-10-19 20:00 - Gruul's Lair")
local shown = ShownMembers()
check("member list shows the newest snapshot", #shown == 1 and shown[1] == "Carol")
items = W.openMenu(snapDD)
check("snapshot dropdown lists stored snapshots, newest first", #items == 2
    and items[1].text == "2026-10-19 20:00 - Gruul's Lair" and items[1].checked
    and items[2].text == "2026-10-18 20:00 - Karazhan")
items[2].func()
shown = ShownMembers()
check("selecting a snapshot updates the member list", #shown == 2 and shown[1] == "Alice" and shown[2] == "Bob")
check("dropdown shows the selection", env.UIDropDownMenu_GetText(snapDD) == "2026-10-18 20:00 - Karazhan")

local aliceBtn
for _, f in ipairs(created) do if rawget(f, "memberName") == "Alice" and f:IsShown() then aliceBtn = f end end
W.click(aliceBtn)
local head = SlotButton(1)
check("clicking a member fills the paper doll", head.itemLink == HELM and head.iconTex:IsShown())
check("selected member highlighted", aliceBtn.selTex:IsShown())
local linked
env.IsShiftKeyDown = function() return true end
env.ChatEdit_GetActiveWindow = function() return true end
env.ChatEdit_InsertLink = function(l) linked = l end
W.click(head)
check("shift-click links the item", linked == HELM)
env.GameTooltip.SetHyperlink = function(_, l) linked = "tip:" .. l end
W.fire(head, "OnEnter")
check("slot tooltip shows the item", linked == "tip:" .. HELM)

-- Snapshot list stays current after a delete
AS.DeleteSnapshot("2026-10-19 20:00 - Gruul's Lair")
check("deleted snapshot gone from the menu", #W.openMenu(snapDD) == 1)
env.ArmorySnapDB.snapshots = {}
AS.RefreshSnapshotList()
check("empty archive greys the snapshot dropdown", snapDD._ddEnabled == false)

-- ============ Theme ============
check("no private theme handler", AS.OnGlobalThemeChanged == nil)
local before = {}
for k, v in pairs(o) do before[k] = v end
W.printed = {}
AS.HandleSlash("theme")
AS.HandleSlash("elvui")
local same = true
for k, v in pairs(before) do if o[k] ~= v then same = false end end
for k in pairs(o) do if before[k] == nil then same = false end end
check("/as theme toggles nothing", same and env.WatchingMachineDB.theme == "Default")
local said = table.concat(W.printed, "\n")
check("/as theme points at /wmachine settings", said:find("global", 1, true) and said:find("/wmachine settings", 1, true))
check("stale elvuiTheme flag left untouched", o.elvuiTheme == true)

-- Default theme: Blizzard slot art even though the old flag says ElvUI
local empty = SlotButton(2)
check("default theme: Blizzard slot art", not empty.elvBg:IsShown() and empty.bgTex:IsShown()
    and not BordersShown(empty))
local statusBar
for _, f in ipairs(created) do if f._kind == "StatusBar" then statusBar = f end end
check("default theme: no status bar border", not BordersShown(statusBar))

env.WatchingMachineDB.theme = "ElvUI"
WM:OnThemeChanged()
check("ElvUI theme: flat slots with pixel borders", empty.elvBg:IsShown() and not empty.bgTex:IsShown()
    and BordersShown(empty))
check("ElvUI theme: status bar bordered", BordersShown(statusBar))
check("ElvUI theme: frame reskinned, still registered", WM._skinnedPanels[p] == true)

env.WatchingMachineDB.theme = "Default"
WM:OnThemeChanged()
check("back to default: borders hidden", not BordersShown(empty) and empty.bgTex:IsShown()
    and not BordersShown(statusBar))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
