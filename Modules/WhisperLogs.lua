-- Watching Machine: Whisper Logs Module
-- Tracks whispers and provides Warcraft Logs lookup links

local AddonName, WM = ...
local WhisperLogs = {}
WM:RegisterModule("WhisperLogs", WhisperLogs)

WhisperLogs.version = "2.2"

-- Configuration
-- TBC Anniversary uses classic.warcraftlogs.com
local WCL_BASE_URL = "https://classic.warcraftlogs.com/character"
local DEFAULT_REGION = "us"

-- State
local mainFrame = nil
local whisperList = {}
local maxWhispers = 50
local playerRealm = nil    -- Cached: player's own realm (slug form)
local playerRealmRaw = nil -- Cached: player's own realm (display form)

-- ============================================
-- UTILITIES
-- ============================================

function WhisperLogs:Print(msg)
    WM:ModulePrint("WhisperLogs", msg)
end

-- Convert realm name to URL-safe slug
-- "Grobbulus" -> "grobbulus"
-- "Old Blanchy" -> "old-blanchy"
local function RealmToSlug(realmName)
    if not realmName or realmName == "" then return nil end
    local slug = realmName:lower()
    slug = slug:gsub("'", "")
    slug = slug:gsub("%s+", "-")
    slug = slug:gsub("[^%a%d%-]", "")
    return slug
end

-- Build a WCL URL for a player
local function BuildWCLUrl(charName, realmSlug, region)
    region = region or DEFAULT_REGION
    if not realmSlug or realmSlug == "" then
        realmSlug = playerRealm or "unknown"
    end
    -- Strip realm suffix from name if present
    local cleanName = charName:lower():gsub("%-.*", "")
    return WCL_BASE_URL .. "/" .. region .. "/" .. realmSlug .. "/" .. cleanName
end

-- Extract name and realm from a full "Player-Realm" string
-- Returns: cleanName, realmSlug, realmRaw
local function ParseNameRealm(fullName)
    local name, realm = fullName:match("^([^%-]+)%-(.+)$")
    if name and realm then
        return name, RealmToSlug(realm), realm
    end
    return fullName, nil, nil
end

local function GetDateTimestamp()
    return date("%Y-%m-%d %H:%M:%S")
end

-- ============================================
-- INITIALIZATION
-- ============================================

function WhisperLogs:Initialize()
    self:InitDB()
    self:DetectServer()
end

function WhisperLogs:DetectServer()
    playerRealmRaw = GetRealmName()
    playerRealm = RealmToSlug(playerRealmRaw)

    if playerRealm then
        WhisperLogsDB.detectedServer = playerRealm
        WhisperLogsDB.detectedServerRaw = playerRealmRaw
    end
end

function WhisperLogs:InitDB()
    if not WhisperLogsDB then
        WhisperLogsDB = {
            region = DEFAULT_REGION,
            whispers = {},
            position = nil,
            detectedServer = nil,
            detectedServerRaw = nil,
        }
    end

    if not WhisperLogsDB.region then WhisperLogsDB.region = DEFAULT_REGION end
    if not WhisperLogsDB.whispers then WhisperLogsDB.whispers = {} end

    whisperList = WhisperLogsDB.whispers
end

-- Rebuild all URLs (called after region change)
function WhisperLogs:RebuildAllURLs()
    local region = WhisperLogsDB.region or DEFAULT_REGION
    for _, entry in ipairs(whisperList) do
        entry.url = BuildWCLUrl(entry.name, entry.realmSlug, region)
    end
    WhisperLogsDB.whispers = whisperList
    self:RefreshDisplay()
end

-- ============================================
-- WHISPER TRACKING
-- ============================================

function WhisperLogs:AddWhisper(senderFull, message)
    if not WhisperLogsDB then return end

    -- Parse "Player-Realm" format from CHAT_MSG_WHISPER
    local name, senderRealmSlug, senderRealmRaw = ParseNameRealm(senderFull)
    -- If no realm in sender string, use player's own realm
    local realmSlug = senderRealmSlug or playerRealm
    local realmRaw = senderRealmRaw or playerRealmRaw
    local region = WhisperLogsDB.region or DEFAULT_REGION

    -- Check if this person is already in the list
    for i, entry in ipairs(whisperList) do
        if entry.name:lower() == name:lower() then
            entry.lastWhisper = GetDateTimestamp()
            entry.lastMessage = message
            entry.count = (entry.count or 1) + 1
            -- Update realm if we now have a better one
            if senderRealmSlug and entry.realmSlug ~= senderRealmSlug then
                entry.realmSlug = senderRealmSlug
                entry.realmRaw = senderRealmRaw
                entry.url = BuildWCLUrl(name, senderRealmSlug, region)
            end
            -- Move to top
            table.remove(whisperList, i)
            table.insert(whisperList, 1, entry)
            self:RefreshDisplay()
            return
        end
    end

    -- Add new entry
    local entry = {
        name = name,
        realmSlug = realmSlug,
        realmRaw = realmRaw,
        firstWhisper = GetDateTimestamp(),
        lastWhisper = GetDateTimestamp(),
        lastMessage = message,
        count = 1,
        url = BuildWCLUrl(name, realmSlug, region),
    }

    table.insert(whisperList, 1, entry)

    while #whisperList > maxWhispers do
        table.remove(whisperList)
    end

    WhisperLogsDB.whispers = whisperList
    self:RefreshDisplay()
end

function WhisperLogs:ClearWhispers()
    whisperList = {}
    WhisperLogsDB.whispers = {}
    self:RefreshDisplay()
    self:Print("Whisper list cleared")
end

function WhisperLogs:RemoveWhisper(index)
    if whisperList[index] then
        local name = whisperList[index].name
        table.remove(whisperList, index)
        WhisperLogsDB.whispers = whisperList
        self:RefreshDisplay()
        self:Print("Removed " .. name .. " from list")
    end
end

-- ============================================
-- RAID/PARTY LOOKUP
-- ============================================

function WhisperLogs:ScanGroup()
    local region = WhisperLogsDB.region or DEFAULT_REGION
    local added = 0

    if IsInRaid() then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                -- GetRaidRosterInfo returns "Name-Realm" for cross-server, "Name" for same
                local cleanName, realmSlug, realmRaw = ParseNameRealm(name)
                if not realmSlug then
                    realmSlug = playerRealm
                    realmRaw = playerRealmRaw
                end
                self:AddGroupMember(cleanName, realmSlug, realmRaw, region)
                added = added + 1
            end
        end
        self:Print("Scanned " .. added .. " raid members")
    elseif IsInGroup() then
        -- Add player first
        local playerName = UnitName("player")
        self:AddGroupMember(playerName, playerRealm, playerRealmRaw, region)
        added = 1

        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                -- UnitName returns name, realm as separate values
                local name, realm = UnitName(unit)
                if name then
                    local realmSlug, realmRaw
                    if realm and realm ~= "" then
                        realmSlug = RealmToSlug(realm)
                        realmRaw = realm
                    else
                        realmSlug = playerRealm
                        realmRaw = playerRealmRaw
                    end
                    self:AddGroupMember(name, realmSlug, realmRaw, region)
                    added = added + 1
                end
            end
        end
        self:Print("Scanned " .. added .. " party members")
    else
        self:Print("Not in a group or raid")
    end

    self:RefreshDisplay()
end

function WhisperLogs:AddGroupMember(name, realmSlug, realmRaw, region)
    for _, entry in ipairs(whisperList) do
        if entry.name:lower() == name:lower() then
            -- Update realm if needed
            if realmSlug and entry.realmSlug ~= realmSlug then
                entry.realmSlug = realmSlug
                entry.realmRaw = realmRaw
                entry.url = BuildWCLUrl(name, realmSlug, region)
            end
            return
        end
    end

    local entry = {
        name = name,
        realmSlug = realmSlug or playerRealm,
        realmRaw = realmRaw or playerRealmRaw,
        firstWhisper = GetDateTimestamp(),
        lastWhisper = GetDateTimestamp(),
        lastMessage = "(Group member)",
        count = 0,
        isGroupMember = true,
        url = BuildWCLUrl(name, realmSlug, region),
    }

    table.insert(whisperList, 1, entry)

    while #whisperList > maxWhispers do
        table.remove(whisperList)
    end

    WhisperLogsDB.whispers = whisperList
end

-- ============================================
-- UI
-- ============================================

function WhisperLogs:CreateMainFrame()
    if mainFrame then return mainFrame end

    local frame = CreateFrame("Frame", "WM_WhisperLogsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 420)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        WhisperLogsDB.position = {point, relPoint, x, y}
    end)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)

    -- Restore position
    if WhisperLogsDB.position then
        frame:ClearAllPoints()
        frame:SetPoint(
            WhisperLogsDB.position[1],
            UIParent,
            WhisperLogsDB.position[2],
            WhisperLogsDB.position[3],
            WhisperLogsDB.position[4]
        )
    end

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF00CCFFWarcraftLogs Lookup|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Server + Region info line
    local serverLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    serverLabel:SetPoint("TOPLEFT", 20, -40)
    local serverDisplay = (playerRealmRaw or "Unknown") .. " (" .. (WhisperLogsDB.region or DEFAULT_REGION):upper() .. ")"
    serverLabel:SetText("Server: |cFF00FF00" .. serverDisplay .. "|r")
    frame.serverLabel = serverLabel

    -- Region selector
    local regionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    regionLabel:SetPoint("TOPRIGHT", -130, -40)
    regionLabel:SetText("Region:")

    local regionDropdown = CreateFrame("Frame", "WM_WhisperLogsRegionDropdown", frame, "UIDropDownMenuTemplate")
    regionDropdown:SetPoint("TOPRIGHT", -15, -34)

    local regions = {"us", "eu", "kr", "tw", "cn"}
    UIDropDownMenu_SetWidth(regionDropdown, 50)
    UIDropDownMenu_SetText(regionDropdown, (WhisperLogsDB.region or DEFAULT_REGION):upper())

    UIDropDownMenu_Initialize(regionDropdown, function(self, level)
        for _, region in ipairs(regions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = region:upper()
            info.value = region
            info.func = function(self)
                WhisperLogsDB.region = self.value
                UIDropDownMenu_SetText(regionDropdown, self.value:upper())
                WhisperLogs:RebuildAllURLs()
                local sd = (playerRealmRaw or "Unknown") .. " (" .. self.value:upper() .. ")"
                frame.serverLabel:SetText("Server: |cFF00FF00" .. sd .. "|r")
                CloseDropDownMenus()
            end
            info.checked = (WhisperLogsDB.region == region)
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Instructions
    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", 20, -55)
    helpText:SetText("|cFF888888Click name to copy URL | Right-click to remove|r")

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 60)
    frame.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.entries = {}

    -- Bottom buttons
    local scanGroupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanGroupBtn:SetSize(140, 24)
    scanGroupBtn:SetPoint("BOTTOMLEFT", 15, 20)
    scanGroupBtn:SetText("Scan Raid/Party")
    scanGroupBtn:SetScript("OnClick", function()
        WhisperLogs:ScanGroup()
    end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 24)
    clearBtn:SetPoint("BOTTOMRIGHT", -15, 20)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("WM_WHISPERLOGS_CLEAR")
    end)

    StaticPopupDialogs["WM_WHISPERLOGS_CLEAR"] = {
        text = "Clear all whisper entries?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            WhisperLogs:ClearWhispers()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    mainFrame = frame
    self.mainFrame = frame

    return frame
end

function WhisperLogs:RefreshDisplay()
    if not mainFrame or not mainFrame:IsVisible() then return end

    local scrollChild = mainFrame.scrollChild

    -- Clear existing entries
    for _, entry in ipairs(mainFrame.entries) do
        entry:Hide()
        entry:SetParent(nil)
    end
    mainFrame.entries = {}

    local yOffset = 0
    local entryHeight = 50

    for i, data in ipairs(whisperList) do
        local entryFrame = CreateFrame("Button", nil, scrollChild)
        entryFrame:SetSize(430, entryHeight - 5)
        entryFrame:SetPoint("TOPLEFT", 0, -yOffset)

        -- Background
        local bg = entryFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        else
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
        end
        entryFrame.bg = bg

        -- Player name with realm tag if cross-server
        local nameText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", 5, -5)

        local realmTag = ""
        if data.realmSlug and data.realmSlug ~= playerRealm then
            realmTag = " |cFFFF8800(" .. (data.realmRaw or data.realmSlug) .. ")|r"
        end

        if data.isGroupMember then
            nameText:SetText("|cFFFFFFFF" .. data.name .. "|r" .. realmTag .. " |cFF00FF00[Group]|r")
        else
            nameText:SetText("|cFFFFFFFF" .. data.name .. "|r" .. realmTag .. " |cFF888888(" .. (data.count or 1) .. " whispers)|r")
        end

        -- URL
        local urlText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        urlText:SetPoint("TOPLEFT", 5, -22)
        urlText:SetText("|cFF00BFFF" .. data.url .. "|r")

        -- Time
        local timeText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("TOPRIGHT", -5, -5)
        timeText:SetText("|cFF888888" .. (data.lastWhisper or "") .. "|r")

        -- Click handlers
        entryFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        entryFrame:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" then
                WhisperLogs:RemoveWhisper(i)
            else
                local editBox = ChatFrame1EditBox or ChatEdit_GetActiveWindow()
                if editBox then
                    editBox:SetText(data.url)
                    editBox:HighlightText()
                    editBox:Show()
                    editBox:SetFocus()
                    WhisperLogs:Print("URL copied to chat box - press Ctrl+C to copy, Escape to cancel")
                end
            end
        end)

        entryFrame:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.2, 0.3, 0.2, 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(data.name, 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Server: " .. (data.realmRaw or data.realmSlug or "Unknown"), 0.4, 0.8, 1)
            if data.isGroupMember then
                GameTooltip:AddLine("Source: Group/Raid scan", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Last whisper:", 0.7, 0.7, 0.7)
                GameTooltip:AddLine(data.lastMessage or "N/A", 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click: Copy URL to chat box", 0, 1, 0)
            GameTooltip:AddLine("Right-click: Remove from list", 1, 0, 0)
            GameTooltip:Show()
        end)

        entryFrame:SetScript("OnLeave", function(self)
            if i % 2 == 0 then
                self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
            else
                self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
            end
            GameTooltip:Hide()
        end)

        table.insert(mainFrame.entries, entryFrame)
        yOffset = yOffset + entryHeight
    end

    scrollChild:SetHeight(math.max(yOffset, 1))
end

function WhisperLogs:Toggle()
    if not mainFrame then
        self:CreateMainFrame()
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        self:RefreshDisplay()
    end
end

-- ============================================
-- STATUS
-- ============================================

function WhisperLogs:GetQuickStatus()
    local count = #whisperList
    local serverStr = playerRealmRaw or "detecting..."
    if count == 0 then
        return "|cFF888888No whispers tracked|r (" .. serverStr .. ")"
    else
        return "|cFF00FF00" .. count .. " players|r tracked (" .. serverStr .. ")"
    end
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")

eventFrame:SetScript("OnEvent", function(self, event, message, sender, ...)
    if event == "CHAT_MSG_WHISPER" then
        -- Pass full sender string including realm ("Player-Realm")
        WhisperLogs:AddWhisper(sender, message)
    end
end)
