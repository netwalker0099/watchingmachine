-- Watching Machine: button in the game menu (Escape), the way ElvUI adds one.
--
-- The 2.5.6 client builds its game menu from a list: every time the menu
-- opens, GameMenuFrame:InitButtons() releases its buttons and adds them
-- again with :AddButton(), and a vertical layout orders them by layoutIndex.
-- So after InitButtons the button is given a place just above Log Out (at
-- the end of the AddOns / Macros group) and the layout puts it there.
--
-- Older clients had fixed buttons (GameMenuButtonLogout, ...) anchored one
-- under another; there the button is anchored above Log Out instead.

local AddonName, WM = ...

local TEXT = "|cFF33CCFFWatching Machine|r"

local function Wanted()
    return not (WatchingMachineDB and WatchingMachineDB.gameMenuButton == false)
end

local function OpenFromMenu()
    if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION) end
    if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
    WM:ToggleDashboard()
end

-- The menu's Log Out button, found by its text
local function IsLogout(button)
    local t = button.GetText and button:GetText()
    return t and (t == LOG_OUT or t == LOGOUT)
end

-- New menu: our own button, a child of the menu, ordered in front of Log
-- Out by a fractional layoutIndex. It isn't taken from the menu's button
-- pool and no Blizzard button is changed: buttons handed out by the pool
-- from addon code can get Log Out / Exit Game blocked as "an AddOn".
local menuButton
function WM:AddGameMenuButton(menu)
    if not menuButton then
        menuButton = CreateFrame("Button", "WM_GameMenuButton", menu, "MainMenuFrameButtonTemplate")
        menuButton:SetText(TEXT)
        menuButton:SetScript("OnClick", OpenFromMenu)
        self.gameMenuButton = menuButton
    end
    if not Wanted() then
        menuButton:Hide()
        menuButton.layoutIndex = nil
        return menuButton
    end
    local at
    if menu.buttonPool then
        for b in menu.buttonPool:EnumerateActive() do
            if IsLogout(b) and b.layoutIndex then at = b.layoutIndex end
        end
    end
    -- No Log Out found: just above the last button (Return to Game)
    at = at or ((menu.nextLayoutIndex or 2) - 1)
    menuButton.layoutIndex = at - 0.5
    menuButton:Show()
    return menuButton
end

-- Old menu: one fixed button above Log Out, the menu made one button taller
local legacyButton
function WM:AddLegacyGameMenuButton()
    local logout = GameMenuButtonLogout
    if not logout then return end
    if not legacyButton then
        legacyButton = CreateFrame("Button", "WM_GameMenuButton", GameMenuFrame, "GameMenuButtonTemplate")
        legacyButton:SetText(TEXT)
        legacyButton:SetScript("OnClick", OpenFromMenu)
        self.gameMenuButton = legacyButton
    end
    local point, relTo, relPoint, x, y = logout:GetPoint(1)
    if relTo ~= legacyButton then
        legacyButton:ClearAllPoints()
        legacyButton:SetPoint(point or "TOP", relTo, relPoint or "BOTTOM", x or 0, y or -1)
        logout:ClearAllPoints()
        logout:SetPoint(point or "TOP", legacyButton, relPoint or "BOTTOM", 0, -16)
        GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + legacyButton:GetHeight() + 16)
    end
    legacyButton:SetShown(Wanted())
end

function WM:SetupGameMenuButton()
    if self.gameMenuHooked or not GameMenuFrame or not hooksecurefunc then return end
    self.gameMenuHooked = true
    if type(GameMenuFrame.InitButtons) == "function" then
        hooksecurefunc(GameMenuFrame, "InitButtons", function(menu) WM:AddGameMenuButton(menu) end)
    else
        WM:AddLegacyGameMenuButton()
        GameMenuFrame:HookScript("OnShow", function() WM:AddLegacyGameMenuButton() end)
    end
end
