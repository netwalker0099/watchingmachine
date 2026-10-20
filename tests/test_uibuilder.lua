-- Shared panel builder (UI.lua) harness. Usage: lua5.1 test_uibuilder.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env
W.load("Core.lua")
W.load("UI.lua")
local WM = W.WM
local UI = WM.UI
env.WatchingMachineDB = { theme = "Default" }

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local function count(list, v) local n = 0 for _, x in ipairs(list) do if x == v then n = n + 1 end end return n end

-- ---- a small panel that fits its content ----
local DB = { a = true, b = false, mode = "RAID", level = 6, note = "hi" }
local p = UI:CreatePanel({ name = "WM_TestPanel", title = "Test", width = 360 })
local L = p.layout
local cbA = L:Checkbox({ label = "A", get = function() return DB.a end, set = function(v) DB.a = v end })
local cbB = L:Checkbox({ label = function() return "B is " .. tostring(DB.b) end,
    get = function() return DB.b end, set = function(v) DB.b = v end,
    disabled = function() return not DB.a end })
local cyc = L:Cycle({ label = "To:", get = function() return DB.mode end, set = function(v) DB.mode = v end,
    options = { { value = "LOCAL", text = "Me only" }, { value = "RAID", text = "Raid" }, { value = "RAID_WARNING", text = "/rw" } } })
local sl = L:Slider({ label = "Level", min = 2, max = 15, step = 1, get = function() return DB.level end,
    set = function(v) DB.level = v end, format = function(v) return v .. "s" end })
local sec = L:Section({ key = "more", title = "More" })
local inSec = L:Checkbox({ label = "Inside", get = function() return true end })
L:Note("A note that is long enough to wrap onto a second line in a narrow panel like this one.")
L:EndSection()
local eb = L:EditBox({ label = "Note:", get = function() return DB.note end, set = function(v) DB.note = v end })
local added = {}
local act = L:EditBox({ label = "Add:", onEnter = function(t) added[#added + 1] = t end, clearOnEnter = true })
local fired = 0
local btn = p:AddFooterButton({ text = "Go", onClick = function() fired = fired + 1 end }, "LEFT")
local danger = p:AddFooterButton({ text = "Reset", confirm = true, onClick = function() fired = fired + 10 end }, "RIGHT")
p:Finish()

check("Escape registered", count(env.UISpecialFrames, "WM_TestPanel") == 1)
check("skinned and registered", WM._skinnedPanels[p])
local h1 = p:GetHeight()
check("height fits content", h1 > 150 and h1 < 400)
check("height = chrome + content", h1 == 40 + L.height + 44 + 4)
check("scroll bar hidden when content fits", not p.scrollBar:IsShown())

-- checkboxes read and write
check("checkbox reads get()", cbA:GetChecked() == true)
W.click(cbA)
check("click writes set()", DB.a == false)
p:Refresh()
check("dependent control greyed when disabled()", cbB:IsEnabled() == false and cbB:GetAlpha() < 1)
check("label function re-read on Refresh", cbB.Text:GetText() == "B is false")
DB.b = true
p:Refresh()
check("Refresh re-reads values", cbB:GetChecked() == true)
DB.a = true; p:Refresh()
check("re-enabled when disabled() turns false", cbB:IsEnabled() and cbB:GetAlpha() == 1)

-- cycle and slider
check("cycle shows current text", cyc.button:GetText() == "Raid")
W.click(cyc.button)
check("cycle advances", DB.mode == "RAID_WARNING" and cyc.button:GetText() == "/rw")
W.click(cyc.button)
check("cycle wraps", DB.mode == "LOCAL")
sl.slider:SetValue(9.4)
check("slider snaps to step and writes", DB.level == 9)
DB.level = 12; p:Refresh()
check("slider Refresh doesn't write back", DB.level == 12 and sl.slider:GetValue() == 12)

-- sections collapse and remember
local before = p:GetHeight()
sec:SetCollapsed(true)
check("collapsing hides its rows", not inSec:GetParent():IsShown())
check("collapsing shrinks the panel", p:GetHeight() < before)
check("collapsed state saved", env.WatchingMachineDB.panels.WM_TestPanel.collapsed.more == true)
W.fire(sec.row.frame, "OnMouseUp")
check("header click expands", not sec:IsCollapsed() and inSec:GetParent():IsShown())

-- edit boxes
eb.editBox:SetText("changed")
W.fire(eb.editBox, "OnEnterPressed")
check("edit box saves on Enter", DB.note == "changed")
eb.editBox:SetText("typed"); eb.editBox:SetFocus(); eb.editBox:ClearFocus()
check("edit box saves on focus lost", DB.note == "typed")
eb.editBox:SetText("oops")
W.fire(eb.editBox, "OnEscapePressed")
check("Escape restores saved value", eb.editBox:GetText() == "typed")
act.editBox:SetText("  Gankalot ")
W.fire(act.editBox, "OnEnterPressed")
check("action edit box runs onEnter trimmed", added[1] == "Gankalot")
check("action edit box clears", act.editBox:GetText() == "")

-- footer buttons
W.click(btn)
check("footer button fires", fired == 1)
W.click(danger)
check("confirm button needs a second click", fired == 1 and danger:GetText():find("Sure"))
W.click(danger)
check("second click fires", fired == 11 and danger:GetText() == "Reset")
W.click(danger); W.runTimers()
check("confirm times out", danger:GetText() == "Reset")

-- ---- screen cap and scrolling ----
env.UIParent:SetHeight(300)
p:Refresh()
check("capped at screen height", p:GetHeight() == 300 - 16)
check("scroll bar shown when content overflows", p.scrollBar:IsShown())
env.UIParent:SetHeight(768)
p:Hide(); p:Show()
check("re-fits on show", p:GetHeight() == h1)

-- ---- ShowSection scrolls to a section ----
local tall = UI:CreatePanel({ name = "WM_TallPanel", title = "Tall", maxHeight = 300 })
for i = 1, 30 do tall.layout:Checkbox({ label = "row " .. i }) end
local far = tall.layout:Section({ key = "far", title = "Far", collapsed = true })
tall.layout:Checkbox({ label = "far row" })
tall:Finish()
check("maxHeight caps a fitted panel", tall:GetHeight() == 300)
check("section default collapsed honoured", far:IsCollapsed())
tall:ShowSection("far")
check("ShowSection expands", not far:IsCollapsed())
check("ShowSection scrolls to it", tall.body:GetVerticalScroll() > 0)

-- ---- position is remembered ----
p:SetScript("OnDragStop", p:GetScript("OnDragStop"))
p:ClearAllPoints(); p:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 100.4, -50.6)
W.fire(p, "OnDragStop")
check("drag stop saves position", env.WatchingMachineDB.panels.WM_TestPanel.pos[3] == 100)
local p2 = UI:CreatePanel({ name = "WM_TestPanel", title = "Test again" })
local pt, rel, relPt, x, y = p2:GetPoint(1)
check("new panel restores saved position", pt == "TOPLEFT" and x == 100 and y == -51)
check("rebuilt panel not registered twice for Escape", count(env.UISpecialFrames, "WM_TestPanel") == 1)

-- ---- non-scrolling panel with a Fill area ----
local list = UI:CreatePanel({ name = "WM_ListPanel", title = "List", scroll = false, height = 700, minHeight = 300 })
list.layout:Checkbox({ label = "setting" })
local fill = list.layout:Fill(80)
list:Finish()
check("fixed-height panel keeps its height", list:GetHeight() == 700)
check("fill anchored below the rows", select(5, fill:GetPoint(1)) == -24)
env.UIParent:SetHeight(500)
list:Hide(); list:Show()
check("fixed-height panel still capped at screen", list:GetHeight() == 484)
env.UIParent:SetHeight(768)

-- ---- tooltips ----
local shown
env.GameTooltip.AddLine = function(_, text) shown = shown or {}; shown[#shown + 1] = text end
local tipped = UI.Button(env.UIParent, { text = "T", tooltip = { "Title", "Body", { "Hint", 0.6, 0.8, 1 } } })
W.fire(tipped, "OnEnter")
check("tooltip lines added in order", shown and shown[1] == "Title" and shown[2] == "Body" and shown[3] == "Hint")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
