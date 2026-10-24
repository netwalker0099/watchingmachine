-- Watching Machine: a button by the game menu (Escape) that opens the
-- dashboard.
--
-- It sits just below the menu, outside it: a frame of our own, parented to
-- UIParent and anchored to the menu's bottom edge, shown and hidden with
-- the menu. Nothing in the menu is touched: no button is added to it, none
-- of its buttons is moved, it isn't resized, and nothing runs when it lays
-- itself out. (Until 3.48 the button was fitted into the menu, which could
-- stop its Log Out button working: the game blocks protected actions like
-- logging out when an addon has been part of building the menu.)
--
-- With ElvUI loaded (and its Blizzard skins on) the button takes ElvUI's
-- button skin. /wmachine menubutton off removes it.

local AddonName, WM = ...

local TEXT = "|cFF33CCFFWatching Machine|r"

local function Wanted()
    return not (WatchingMachineDB and WatchingMachineDB.gameMenuButton == false)
end

local function OpenFromMenu()
    if WM.Diagnostics then WM.Diagnostics:Note("menuclick", "Watching Machine menu button clicked") end
    if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION) end
    if GameMenuFrame and GameMenuFrame:IsShown() then
        if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
    end
    WM:ToggleDashboard()
end

-- ElvUI's skin for a button, if ElvUI is loaded with its Blizzard skins on
local function ElvSkin(button)
    if button.wmSkinned then return end
    local E = type(ElvUI) == "table" and ElvUI[1]
    if type(E) ~= "table" or type(E.GetModule) ~= "function" then return end
    local skins = E.private and E.private.skins and E.private.skins.blizzard
    if skins and (skins.enable == false or skins.misc == false) then return end
    local ok, S = pcall(E.GetModule, E, "Skins", true)
    if not ok or type(S) ~= "table" or type(S.HandleButton) ~= "function" then return end
    if pcall(S.HandleButton, S, button, nil, nil, nil, true) then
        if button.backdrop and button.backdrop.SetInside then
            pcall(button.backdrop.SetInside, button.backdrop, nil, 1, 1)
        end
        button.wmSkinned = true
    end
end
WM.GameMenuElvSkin = ElvSkin

local menuButton

-- Our button, made once: below the menu, never inside it
function WM:CreateGameMenuButton()
    if menuButton then return menuButton end
    local menu = GameMenuFrame
    menuButton = CreateFrame("Button", "WM_GameMenuButton", UIParent, "UIPanelButtonTemplate")
    menuButton:SetSize(160, 24)
    menuButton:SetText(TEXT)
    menuButton:SetFrameStrata(menu.GetFrameStrata and menu:GetFrameStrata() or "DIALOG")
    menuButton:SetPoint("TOP", menu, "BOTTOM", 0, -4)
    menuButton:SetScript("OnClick", OpenFromMenu)
    menuButton:Hide()
    ElvSkin(menuButton)
    self.gameMenuButton = menuButton
    return menuButton
end

-- The menu opened or closed
function WM:UpdateGameMenuButton()
    local menu = GameMenuFrame
    if not menu then return end
    local b = self:CreateGameMenuButton()
    b:SetShown(Wanted() and menu:IsShown() and true or false)
end

function WM:SetupGameMenuButton()
    if self.gameMenuHooked or not GameMenuFrame or not GameMenuFrame.HookScript then return end
    -- Off: don't touch the menu at all; turning it back on takes a /reload
    if not Wanted() then return end
    self.gameMenuHooked = true
    GameMenuFrame:HookScript("OnShow", function() WM:UpdateGameMenuButton() end)
    GameMenuFrame:HookScript("OnHide", function() if menuButton then menuButton:Hide() end end)
    if GameMenuFrame:IsShown() then self:UpdateGameMenuButton() end
end
