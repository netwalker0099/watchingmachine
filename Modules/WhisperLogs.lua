-- Watching Machine: Whisper Logs Module
-- Tracks whispers and provides Warcraft Logs lookup links

local AddonName, WM = ...
local WhisperLogs = {}
WM:RegisterModule("WhisperLogs", WhisperLogs)

WhisperLogs.version = "2.0"

-- Configuration
-- TBC Anniversary uses classic.warcraftlogs.com (follows progression)
local WCL_BASE_URL = "https://classic.warcraftlogs.com/character"
local DEFAULT_REGION = "us"

-- State
local mainFrame = nil
local whisperList = {}
local maxWhispers = 50

-- ============================================
-- UTILITIES
-- ============================================

function WhisperLogs:Print(msg)
    WM:ModulePrint("WhisperLogs", msg)
end

local function GetServerSlug(realmName)
    if not realmName then return "unknown" end
    -- Convert realm name to URL slug (lowercase, no spaces/special chars)
    local slug = realmName:lower():gsub("%s+", "-"):gsub("'", "")
    return slug
end

local function GetWarcraftLogsURL(playerName, realmName, region)
    region = region or DEFAULT_REGION
    local serverSlug = GetServerSlug(realmName)
    local charName = playerName:lower():gsub("%-.*", "") -- Remove realm suffix if present
    return WCL_BASE_URL .. "/" .. region .. "/" .. serverSlug .. "/" .. charName
end

local function GetTimestamp()
    return date("%H:%M:%S")
end

local function GetDateTimestamp()
    return date("%Y-%m-%d %H:%M:%S")
end

-- ============================================
-- INITIALIZATION
-- ============================================

function WhisperLogs:Initialize()
    self:InitDB()
end

function WhisperLogs:InitDB()
    if not WhisperLogsDB then
        WhisperLogsDB = {
            region = DEFAULT_REGION,
            whispers = {},
            position = nil,
        }
    end
    
    -- Ensure fields exist
    if not WhisperLogsDB.region then WhisperLogsDB.region = DEFAULT_REGION end
    if not WhisperLogsDB.whispers then WhisperLogsDB.whispers = {} end
    
    -- Load saved whispers into memory
    whisperList = WhisperLogsDB.whispers
end

-- ============================================
-- WHISPER TRACKING
-- ============================================

function WhisperLogs:AddWhisper(sender, message)
    -- Skip if DB not initialized yet
    if not WhisperLogsDB then return end
    
    local realm = GetRealmName()
    
    -- Check if this person is already in the list
    for i, entry in ipairs(whisperList) do
        if entry.name:lower() == sender:lower() then
            -- Update existing entry
            entry.lastWhisper = GetDateTimestamp()
            entry.lastMessage = message
            entry.count = (entry.count or 1) + 1
            -- Move to top of list
            table.remove(whisperList, i)
            table.insert(whisperList, 1, entry)
            self:RefreshDisplay()
            return
        end
    end
    
    -- Add new entry at top
    local entry = {
        name = sender,
        realm = realm,
        firstWhisper = GetDateTimestamp(),
        lastWhisper = GetDateTimestamp(),
        lastMessage = message,
        count = 1,
        url = GetWarcraftLogsURL(sender, realm, WhisperLogsDB.region),
    }
    
    table.insert(whisperList, 1, entry)
    
    -- Trim list if too long
    while #whisperList > maxWhispers do
        table.remove(whisperList)
    end
    
    -- Save to DB
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
    local realm = GetRealmName()
    local region = WhisperLogsDB.region or DEFAULT_REGION
    local added = 0
    
    if IsInRaid() then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                -- Strip realm from name if present
                local cleanName = name:match("([^%-]+)") or name
                self:AddGroupMember(cleanName, realm, region)
                added = added + 1
            end
        end
        self:Print("Scanned " .. added .. " raid members")
    elseif IsInGroup() then
        -- Add player first
        local playerName = UnitName("player")
        self:AddGroupMember(playerName, realm, region)
        added = 1
        
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                if name then
                    self:AddGroupMember(name, realm, region)
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

function WhisperLogs:AddGroupMember(name, realm, region)
    -- Check if already in list
    for _, entry in ipairs(whisperList) do
        if entry.name:lower() == name:lower() then
            return -- Already exists
        end
    end
    
    -- Add new entry
    local entry = {
        name = name,
        realm = realm,
        firstWhisper = GetDateTimestamp(),
        lastWhisper = GetDateTimestamp(),
        lastMessage = "(Group member)",
        count = 0,
        isGroupMember = true,
        url = GetWarcraftLogsURL(name, realm, region),
    }
    
    table.insert(whisperList, 1, entry)
    
    -- Trim list if too long
    while #whisperList > maxWhispers do
        table.remove(whisperList)
    end
    
    -- Save to DB
    WhisperLogsDB.whispers = whisperList
end

-- ============================================
-- UI
-- ============================================

function WhisperLogs:CreateMainFrame()
    if mainFrame then return mainFrame end
    
    local frame = CreateFrame("Frame", "WM_WhisperLogsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 400)
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
    
    -- Region selector (right side)
    local regionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    regionLabel:SetPoint("TOPRIGHT", -120, -45)
    regionLabel:SetText("Region:")
    
    local regionDropdown = CreateFrame("Frame", "WM_WhisperLogsRegionDropdown", frame, "UIDropDownMenuTemplate")
    regionDropdown:SetPoint("TOPRIGHT", -15, -40)
    
    local regions = {"us", "eu", "kr", "tw", "cn"}
    UIDropDownMenu_SetWidth(regionDropdown, 50)
    UIDropDownMenu_SetText(regionDropdown, WhisperLogsDB.region or DEFAULT_REGION)
    
    UIDropDownMenu_Initialize(regionDropdown, function(self, level)
        for _, region in ipairs(regions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = region:upper()
            info.value = region
            info.func = function(self)
                WhisperLogsDB.region = self.value
                UIDropDownMenu_SetText(regionDropdown, self.value)
                -- Update all URLs
                local realm = GetRealmName()
                for _, entry in ipairs(whisperList) do
                    entry.url = GetWarcraftLogsURL(entry.name, realm, self.value)
                end
                WhisperLogs:RefreshDisplay()
                CloseDropDownMenus()
            end
            info.checked = (WhisperLogsDB.region == region)
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Instructions (left side, below title)
    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", 20, -45)
    helpText:SetText("|cFF888888Click name to copy URL | Right-click to remove|r")
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -65)
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
    
    -- Confirmation dialog
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
    local entryHeight = 45
    
    for i, data in ipairs(whisperList) do
        local entryFrame = CreateFrame("Button", nil, scrollChild)
        entryFrame:SetSize(390, entryHeight - 5)
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
        
        -- Player name with source indicator
        local nameText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", 5, -5)
        if data.isGroupMember then
            nameText:SetText("|cFFFFFFFF" .. data.name .. "|r |cFF00FF00[Group]|r")
        else
            nameText:SetText("|cFFFFFFFF" .. data.name .. "|r |cFF888888(" .. (data.count or 1) .. " whispers)|r")
        end
        
        -- URL (truncated for display)
        local urlText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        urlText:SetPoint("TOPLEFT", 5, -20)
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
                -- Copy URL to clipboard via edit box
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
    if count == 0 then
        return "|cFF888888No whispers tracked|r"
    else
        return "|cFF00FF00" .. count .. " players|r tracked"
    end
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")

eventFrame:SetScript("OnEvent", function(self, event, message, sender, ...)
    if event == "CHAT_MSG_WHISPER" then
        -- Strip realm name for display but keep for lookup
        local name = sender:match("([^%-]+)") or sender
        WhisperLogs:AddWhisper(name, message)
    end
end)
