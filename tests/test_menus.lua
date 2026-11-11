-- Menus and dropdowns: every one is Watching Machine's own menu frame
-- (UI:ShowMenu). The game's dropdown menus place their list from the cursor
-- or the anchor divided by a UI scale, so with ElvUI and other UI packs the
-- list opened on another part of the screen; they aren't used anywhere.
-- Usage: lua5.1 test_menus.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

env.GetCursorPosition = function() return 400, 300 end
W.load("Core.lua")
W.load("UI.lua")
local WM = W.WM
local UI = WM.UI

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end

-- ---- No file uses the game's dropdown menus ----
local BANNED = { "UIDropDownMenu", "ToggleDropDownMenu", "EasyMenu", "CloseDropDownMenus", "MenuUtil%." }
local used = {}
for line in io.lines(REPO .. "/WatchingMachine.toc") do
    local rel = line:match("^([%w_/%.]+%.lua)%s*$")
    if rel then
        local n = 0
        for src in io.lines(REPO .. "/" .. rel) do
            n = n + 1
            local code = src:gsub("%-%-.*$", "")
            for _, word in ipairs(BANNED) do
                if code:find(word) then used[#used + 1] = rel .. ":" .. n end
            end
        end
    end
end
check("no file uses the game's dropdown menus (" .. table.concat(used, ", ") .. ")", #used == 0)

-- ---- A menu at the cursor ----
local chosen
local items = { { text = "Title", isTitle = true }, { text = "One", func = function() chosen = 1 end },
    { text = "Two", func = function() chosen = 2 end, checked = true }, { text = "Off", disabled = true, func = function() chosen = 3 end } }
UI:ShowMenu(items)
local menu = env.WM_PopupMenu
check("the menu opens", menu and menu:IsShown() and menu.rows[2].text:GetText() == "One")
check("at the cursor: anchored to the screen, not a frame", menu.anchor == nil)
check("the ticked item shows its tick", menu.rows[3].check:IsShown() and not menu.rows[2].check:IsShown())
menu.rows[4]._scripts.OnClick(menu.rows[4])
check("a disabled item does nothing", chosen == nil)
UI:ShowMenu(items)
menu.rows[2]._scripts.OnClick(menu.rows[2])
check("a choice runs and closes the menu", chosen == 1 and not menu:IsShown())

-- ---- Under a control ----
local button = env.CreateFrame("Button", nil, env.UIParent)
UI:ShowMenu(items, nil, nil, { anchor = button, minWidth = 200 })
check("hung under its control", menu:IsShown() and menu.anchor == button and UI:MenuOpenFor(button))
check("at least as wide as the control", (menu:GetWidth() or 0) >= 200)
check("not open for another control", not UI:MenuOpenFor(env.UIParent))
UI:HideMenu()
check("hidden: open for nothing", not UI:MenuOpenFor(button))

-- ---- A long list scrolls ----
local long = {}
for i = 1, 60 do long[i] = { text = "Item " .. i, checked = (i == 40) } end
UI:ShowMenu(long)
local shown = 0
for _, row in ipairs(menu.rows) do if row:IsShown() then shown = shown + 1 end end
check("a long list shows a screenful", shown == 22)
local function Visible(text)
    for _, row in ipairs(menu.rows) do if row:IsShown() and row.text:GetText() == text then return true end end
    return false
end
check("opens with the ticked choice in view", Visible("Item 40"))
menu._scripts.OnMouseWheel(menu, -1)
menu._scripts.OnMouseWheel(menu, -1)
menu._scripts.OnMouseWheel(menu, -1)
menu._scripts.OnMouseWheel(menu, -1)
menu._scripts.OnMouseWheel(menu, -1)
menu._scripts.OnMouseWheel(menu, -1)
check("the wheel scrolls down to the end", Visible("Item 60") and not Visible("Item 30"))
for _ = 1, 30 do menu._scripts.OnMouseWheel(menu, 1) end
check("and back up to the start", Visible("Item 1"))
UI:HideMenu()

-- ---- A dropdown is a button that opens that menu under itself ----
local saved = "b"
local box = UI.Dropdown(env.UIParent, { label = "Pick:", width = 100,
    options = { { value = "a", text = "Alpha" }, { value = "b", text = "Beta" }, { value = "c", text = "Gamma" } },
    get = function() return saved end, set = function(v) saved = v end })
local dd = box.dropdown
check("the dropdown shows the current choice", dd.shownText == "Beta" and dd.label:GetText() == "Beta")
dd._scripts.OnClick(dd)
check("a click opens the menu under the dropdown", menu:IsShown() and menu.anchor == dd and #menu.items == 3)
check("the current choice is ticked", menu.items[2].checked == true and menu.items[1].checked == false)
dd._scripts.OnClick(dd)
check("a second click closes it", not menu:IsShown())
dd._scripts.OnClick(dd)
menu.rows[3]._scripts.OnClick(menu.rows[3])
check("choosing sets the value and the text", saved == "c" and dd.shownText == "Gamma" and not menu:IsShown())
local off = true
local box2 = UI.Dropdown(env.UIParent, { options = { { value = 1, text = "One" } }, get = function() return 1 end,
    disabled = function() return off end })
box2.dropdown._scripts.OnClick(box2.dropdown)
check("a disabled dropdown doesn't open", not menu:IsShown() and box2.dropdown.isDisabled == true)
off = false
box2:Refresh()
box2.dropdown._scripts.OnClick(box2.dropdown)
check("enabled again: it opens", menu:IsShown())
UI:HideMenu()

io.write(string.format("%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
