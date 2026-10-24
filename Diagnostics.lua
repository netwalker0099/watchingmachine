-- Watching Machine: logout diagnostics
-- For "I can't log out with the addon loaded". Records, across sessions:
--   * actions the game blocked and the addon it blamed (ADDON_ACTION_BLOCKED
--     / _FORBIDDEN: an addon's code ran in the path of a protected action
--     such as Logout), with a chat warning when it's logging out or quitting
--   * logout attempts: the countdown starting (PLAYER_CAMPING / QUITTING)
--     and being cancelled (LOGOUT_CANCEL), and whether you were in combat
--   * clicks on our Escape-menu button (if it ever sat on top of Log Out,
--     the click would land on it instead)
-- /wmachine logoutcheck prints all of that, checks whether our menu button
-- overlaps Log Out, and says what to try. /wmachine menubutton off removes
-- the button entirely, to rule it out.

local AddonName, WM = ...
local D = {}
WM.Diagnostics = D

local MAX = 60
local WATCHED = { Logout = true, Quit = true, ForceQuit = true, CancelLogout = true }

local function Log()
    WatchingMachineDB = WatchingMachineDB or {}
    if type(WatchingMachineDB.diag) ~= "table" then WatchingMachineDB.diag = {} end
    return WatchingMachineDB.diag
end

local function InCombat() return (InCombatLockdown and InCombatLockdown()) and true or false end

function D:Note(kind, text)
    local log = Log()
    log[#log + 1] = { at = time and time() or 0, when = date and date("%m-%d %H:%M:%S") or "?", kind = kind, text = text,
        combat = InCombat() }
    while #log > MAX do table.remove(log, 1) end
    return log[#log]
end

-- An action the game blocked: which addon, which function
function D:OnBlocked(event, addon, func)
    addon, func = tostring(addon or "?"), tostring(func or "?")
    local name = func:match("([%w_]+)%(?%)?$") or func
    self:Note("blocked", string.format("%s blocked %s() (blamed: %s)", event == "ADDON_ACTION_FORBIDDEN" and "Forbidden:"
        or "The game", name, addon))
    local fname = func:match("([%w_]+)%(?%)?$") or func
    if WATCHED[fname] or addon == AddonName then
        WM:Print(string.format("|cFFFF6666The game blocked %s() and blamed %s.|r Type |cFFFFFF00/wmachine logoutcheck|r"
            .. " for what to try.", fname, addon == AddonName and "Watching Machine" or addon))
    end
end

-- ============================================
-- THE MENU BUTTON vs LOG OUT
-- ============================================

local function Rect(f)
    if not (f and f.GetLeft) then return nil end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return nil end
    return l, r, t, b
end

-- The menu's Log Out button (pooled buttons on 2.5.6, the old fixed one otherwise)
function D.LogoutButton()
    local menu = rawget(_G, "GameMenuFrame")
    if type(menu) == "table" and menu.buttonPool and menu.buttonPool.EnumerateActive then
        for b in menu.buttonPool:EnumerateActive() do
            local t = b.GetText and b:GetText()
            if t and (t == rawget(_G, "LOG_OUT") or t == rawget(_G, "LOGOUT")) then return b end
        end
    end
    return rawget(_G, "GameMenuButtonLogout")
end

-- Does our button cover any part of Log Out? (only meaningful while the
-- menu is open). Returns true / false, or nil if it can't tell.
function D.MenuOverlap()
    local ours, logout = WM.gameMenuButton, D.LogoutButton()
    if not (ours and logout and ours.IsVisible and ours:IsVisible() and logout:IsVisible()) then return nil end
    local l1, r1, t1, b1 = Rect(ours)
    local l2, r2, t2, b2 = Rect(logout)
    if not (l1 and l2) then return nil end
    return l1 < r2 and l2 < r1 and b1 < t2 and b2 < t1
end

-- ============================================
-- REPORT
-- ============================================

function D:Report()
    local p = function(s) print("  " .. s) end
    WM:Print("=== Logout check ===")
    local log = Log()
    local blocked, camping, cancelled, clicks = {}, 0, 0, 0
    for _, e in ipairs(log) do
        if e.kind == "blocked" then blocked[#blocked + 1] = e
        elseif e.kind == "camping" then camping = camping + 1
        elseif e.kind == "cancel" then cancelled = cancelled + 1
        elseif e.kind == "menuclick" then clicks = clicks + 1 end
    end
    local menuOn = not (WatchingMachineDB and WatchingMachineDB.gameMenuButton == false)
    p("Escape-menu button: " .. (menuOn and "|cFF33FF33on|r" or "|cFF888888off|r"))
    local overlap = D.MenuOverlap()
    if overlap == true then
        p("|cFFFF6666Our menu button is covering Log Out right now.|r Clicks there open the dashboard instead. Turn it off:"
            .. " |cFFFFFF00/wmachine menubutton off|r")
    elseif overlap == false then
        p("Our menu button doesn't cover Log Out.")
    else
        p("Open the Escape menu and run this again to check our button doesn't cover Log Out.")
    end
    p(string.format("Logouts started: %d, cancelled: %d. Menu button clicks: %d.", camping, cancelled, clicks))
    if #blocked == 0 then
        p("No actions blocked by the game have been recorded.")
    else
        p("|cFFFF6666Blocked actions (newest last):|r")
        for i = math.max(1, #blocked - 5), #blocked do p(blocked[i].when .. "  " .. blocked[i].text) end
    end
    local errs = (WatchingMachineDB and WatchingMachineDB.errorLog) or WM._errorLog or {}
    p("Watching Machine errors recorded: " .. #errs .. (#errs > 0 and " (/wmachine errors)" or ""))
    p("|cFFFFFFFFRecent events:|r")
    for i = math.max(1, #log - 8), #log do
        local e = log[i]
        p(e.when .. "  " .. e.text .. (e.combat and " |cFFFF8800(in combat)|r" or ""))
    end
    WM:Print("What to try:")
    p("1. Type |cFFFFFF00/logout|r (or /camp). If that works but the menu's Log Out doesn't, it's the menu:"
        .. " |cFFFFFF00/wmachine menubutton off|r, /reload, and try again.")
    p("2. If a logout starts and is cancelled, something is moving you or you're in combat (see the events above).")
    p("3. If the game blocked Logout(), the addon it blamed is listed above. For a full trace: /console taintLog 1,"
        .. " /reload, try to log out, then send Logs\\taint.log from the WoW folder.")
end

-- /wmachine menubutton on|off
function D:SetMenuButton(on)
    WatchingMachineDB = WatchingMachineDB or {}
    WatchingMachineDB.gameMenuButton = on and true or false
    if WM.gameMenuButton then WM.gameMenuButton:SetShown(on and true or false) end
    WM:Print("Escape-menu button " .. (on and "on." or "off. Do /reload so the menu is rebuilt without it, then try"
        .. " logging out again."))
end

-- ============================================
-- EVENTS
-- ============================================

local events = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_CAMPING", "PLAYER_QUITING",
    "LOGOUT_CANCEL", "PLAYER_LOGIN" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
    local ok, err = pcall(function()
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            D:OnBlocked(event, a1, a2)
        elseif event == "PLAYER_CAMPING" then
            D:Note("camping", "Logout countdown started")
        elseif event == "PLAYER_QUITING" then
            D:Note("camping", "Quit countdown started")
        elseif event == "LOGOUT_CANCEL" then
            D:Note("cancel", "Logout cancelled (moving, combat, or Cancel)")
        elseif event == "PLAYER_LOGIN" then
            D:Note("login", "Logged in (v" .. tostring(WM.version) .. ")")
        end
    end)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end)
