-- Watching Machine: button in the game menu (Escape), the way ElvUI adds one.
--
-- The 2.5.6 client builds its game menu from a list: every time the menu
-- opens, GameMenuFrame:InitButtons() releases its buttons and adds them
-- again with :AddButton(), and a vertical layout (GameMenuFrame:Layout)
-- stacks them by layoutIndex.
--
-- The button works the way ElvUI's does, so the two sit together instead of
-- on top of each other: it isn't part of that layout. After each Layout it
-- is anchored under Macros, or under ElvUI's (or another addon's) button
-- if one is already there, and Log Out, Exit Game and Return to Game are
-- pushed down by its height. ElvUI pushes them down for its own button the
-- same way, so the two shifts add up whichever hook runs first.
--
-- With ElvUI loaded (and its Blizzard skins on) the button takes ElvUI's
-- button skin, like the menu's own buttons.
--
-- Older clients had fixed buttons (GameMenuButtonLogout, ...) anchored one
-- under another; there the button is anchored above Log Out instead.

local AddonName, WM = ...

local TEXT = "|cFF33CCFFWatching Machine|r"

local function Wanted()
    return not (WatchingMachineDB and WatchingMachineDB.gameMenuButton == false)
end

local function OpenFromMenu()
    if WM.Diagnostics then WM.Diagnostics:Note("menuclick", "Watching Machine menu button clicked") end
    if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION) end
    if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
    WM:ToggleDashboard()
end

-- The menu's Log Out button, found by its text
local function IsLogout(button)
    local t = button.GetText and button:GetText()
    return t and (t == LOG_OUT or t == LOGOUT)
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

-- Buttons other addons put on the menu outside its layout (ElvUI's first)
local function AddonButtons(menu, ours, pooled)
    local out = {}
    -- rawget: plain fields, not methods (ElvUI sets GameMenuFrame.ElvUI)
    local elv = rawget(menu, "ElvUI") or rawget(_G, "ElvUI_GameMenuButton")
    if type(elv) == "table" and elv ~= ours and elv.IsShown and elv:IsShown() then out[#out + 1] = elv end
    if menu.GetChildren then
        for _, child in ipairs({ menu:GetChildren() }) do
            if type(child) == "table" and child ~= ours and child ~= elv and not pooled[child] and not child.layoutIndex
                and child.IsObjectType and child:IsObjectType("Button") and child:IsShown()
                and child.GetText and child:GetText() then
                out[#out + 1] = child
            end
        end
    end
    return out
end

local function Nudge(button, dy)
    local point, rel, relPoint, x, y = button:GetPoint(1)
    if point then button:SetPoint(point, rel, relPoint, x or 0, (y or 0) + dy) end
end

local menuButton

-- After the menu lays itself out: place ours and make room for it
function WM:PositionGameMenuButton(menu)
    local ours = menuButton
    if not ours or not ours:IsShown() or not menu.buttonPool then return end
    local pooled, macros, logoutAt, lastBefore = {}, nil, nil, nil
    for b in menu.buttonPool:EnumerateActive() do
        pooled[b] = true
        if IsLogout(b) and b.layoutIndex then logoutAt = b.layoutIndex end
        if MACROS and b.GetText and b:GetText() == MACROS then macros = b end
    end
    if not logoutAt then
        -- No Log Out: go above the last button (Return to Game)
        for b in menu.buttonPool:EnumerateActive() do
            if b.layoutIndex and (not logoutAt or b.layoutIndex > logoutAt) then logoutAt = b.layoutIndex end
        end
    end
    if not logoutAt then return end
    if not macros then
        for b in menu.buttonPool:EnumerateActive() do
            if b.layoutIndex and b.layoutIndex < logoutAt
                and (not lastBefore or b.layoutIndex > lastBefore.layoutIndex) then lastBefore = b end
        end
    end
    local above = macros or lastBefore
    if not above then return end

    -- Under any addon buttons already sitting there (ElvUI's), in a column
    local others = AddonButtons(menu, ours, pooled)
    if #others > 0 then above = others[#others] end
    ours:ClearAllPoints()
    ours:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)

    local h = ours:GetHeight()
    if not h or h <= 0 then h = 21 end
    for b in menu.buttonPool:EnumerateActive() do
        if b.layoutIndex and b.layoutIndex >= logoutAt then Nudge(b, -h) end
    end
    menu:SetHeight((menu:GetHeight() or 0) + h)
    self.gameMenuAnchor = above
end

-- Each time the menu is rebuilt: make sure ours exists, shown or not
function WM:AddGameMenuButton(menu)
    if not menuButton then
        menuButton = CreateFrame("Button", "WM_GameMenuButton", menu, "MainMenuFrameButtonTemplate")
        menuButton:SetSize(144, 21)
        menuButton:SetText(TEXT)
        menuButton:SetScript("OnClick", OpenFromMenu)
        self.gameMenuButton = menuButton
    end
    menuButton.layoutIndex = nil   -- placed after Layout, not by it
    if Wanted() then
        ElvSkin(menuButton)
        menuButton:Show()
    else
        menuButton:Hide()
    end
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
    ElvSkin(legacyButton)
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
    -- Off: don't touch the menu at all (so it can be ruled out when logging
    -- out misbehaves); turning it back on takes a /reload
    if not Wanted() then return end
    self.gameMenuHooked = true
    if type(GameMenuFrame.InitButtons) == "function" then
        hooksecurefunc(GameMenuFrame, "InitButtons", function(menu) WM:AddGameMenuButton(menu) end)
        if type(GameMenuFrame.Layout) == "function" then
            hooksecurefunc(GameMenuFrame, "Layout", function(menu) WM:PositionGameMenuButton(menu) end)
        end
    else
        WM:AddLegacyGameMenuButton()
        GameMenuFrame:HookScript("OnShow", function() WM:AddLegacyGameMenuButton() end)
    end
end
