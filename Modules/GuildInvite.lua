-- Watching Machine: Guild Invite Module
-- Auto-invites guild members to raid when they say 'inv' in guild chat or whisper

local AddonName, WM = ...
local GuildInvite = {}
WM:RegisterModule("GuildInvite", GuildInvite)

GuildInvite.version = "2.2"

-- ============================================
-- TBC API COMPATIBILITY
-- ============================================
-- TBC Classic uses global functions, retail uses C_PartyInfo namespace
-- Wrap both with pcall for safety (e.g. post-arena state transitions)

local function SafeInviteUnit(name)
    local fn = InviteUnit or (C_PartyInfo and C_PartyInfo.InviteUnit)
    if fn then
        local ok, err = pcall(fn, name)
        return ok
    end
    return false
end

local function SafeConvertToRaid()
    local fn = ConvertToRaid or (C_PartyInfo and C_PartyInfo.ConvertToRaid)
    if fn then
        local ok, err = pcall(fn)
        return ok
    end
    return false
end

-- Default settings
local defaults = {
    enabled = true,
    trigger = "inv",
    announceInvites = true,
    respondToNonGuild = false,
    inviteLog = {},
    maxLogEntries = 100,
}

-- State
local guildRoster = {}
local mainFrame = nil

-- ============================================
-- INITIALIZATION
-- ============================================

function GuildInvite:Initialize()
    self:InitDB()
    self:UpdateGuildRoster()
    self:RegisterEvents()
end

function GuildInvite:InitDB()
    if not GuildInviteDB then
        GuildInviteDB = {}
    end
    for key, value in pairs(defaults) do
        if GuildInviteDB[key] == nil then
            if type(value) == "table" then
                GuildInviteDB[key] = {}
                for k2, v2 in pairs(value) do
                    GuildInviteDB[key][k2] = v2
                end
            else
                GuildInviteDB[key] = value
            end
        end
    end
end

-- ============================================
-- UTILITIES
-- ============================================

function GuildInvite:Print(msg)
    WM:ModulePrint("GuildInvite", msg)
end

function GuildInvite:VerbosePrint(msg)
    WM:VerbosePrint("GuildInvite", msg)
end

local function GetTimestamp()
    return date("%H:%M:%S")
end

-- ============================================
-- GUILD ROSTER
-- ============================================

function GuildInvite:UpdateGuildRoster()
    wipe(guildRoster)
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            -- Store both with and without realm for compatibility
            local shortName = strsplit("-", name)
            guildRoster[name:lower()] = true
            guildRoster[shortName:lower()] = true
        end
    end
end

function GuildInvite:IsInGuild(playerName)
    if not playerName then return false end
    local checkName = playerName:lower()
    local shortName = strsplit("-", checkName)
    return guildRoster[checkName] or guildRoster[shortName]
end

-- ============================================
-- INVITE FUNCTIONALITY
-- ============================================

-- Check if we have permission to invite (leader, assist, or solo/party leader)
local function CanInvite()
    if IsInRaid() then
        -- In raid: need leader or assist
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    elseif IsInGroup() then
        -- In party: need leader
        return UnitIsGroupLeader("player")
    end
    -- Solo: can always invite (creates a new group)
    return true
end

-- Check if the player has permission to invite
-- Solo: can always invite (forms a new party)
-- Party: must be leader
-- Raid: must be leader or assistant
local function HasInvitePermission()
    if not IsInGroup() then
        -- Solo — can always invite to form a new group
        return true
    end
    if IsInRaid() then
        -- Raid — need leader or assist
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    -- Party — need leader
    return UnitIsGroupLeader("player")
end

function GuildInvite:InviteToRaid(playerName, source)
    if not playerName or playerName == "" then return end
    if not GuildInviteDB then return end
    if not GuildInviteDB.enabled then return end
    
    -- Must have invite permissions (leader/assist or solo)
    if not HasInvitePermission() then
        if GuildInviteDB.announceInvites then
            self:VerbosePrint("Ignoring invite request from " .. playerName .. " (not leader/assist)")
        end
        return
    end
    
    -- Convert to raid only when party is full and we're trying to invite a 6th
    if IsInGroup() and not IsInRaid() then
        if UnitIsGroupLeader("player") then
            local numGroupMembers = GetNumGroupMembers()
            if numGroupMembers >= 5 then
                if SafeConvertToRaid() then
                    self:Print("Auto-converted to raid (6th member incoming)")
                end
            end
        end
    end
    
    -- Invite the player
    SafeInviteUnit(playerName)
    
    -- Log the invite
    self:LogInvite(playerName, source)
    
    if GuildInviteDB.announceInvites then
        self:Print("Invited " .. playerName .. " (" .. source .. ")")
    end
end

function GuildInvite:ConvertToRaid()
    if not IsInGroup() then
        self:Print("You are not in a group.")
        return
    end
    
    if IsInRaid() then
        self:Print("Already in a raid.")
        return
    end
    
    if not UnitIsGroupLeader("player") then
        self:Print("You must be party leader to convert.")
        return
    end
    
    if SafeConvertToRaid() then
        self:Print("Converted to raid.")
    else
        self:Print("Failed to convert to raid.")
    end
end

function GuildInvite:CheckConvertTrigger(message)
    if not message then return false end
    local lower = message:lower():gsub("^%s*(.-)%s*$", "%1")
    -- Match "raid convert", "convert raid", "convert to raid", "make raid"
    return lower == "raid convert" or lower == "convert raid" or 
           lower == "convert to raid" or lower == "make raid" or
           lower == "raid"
end

function GuildInvite:LogInvite(playerName, source)
    if not GuildInviteDB or not GuildInviteDB.inviteLog then return end
    
    local entry = {
        name = playerName,
        source = source,
        time = GetTimestamp(),
        timestamp = time(),
    }
    
    table.insert(GuildInviteDB.inviteLog, 1, entry)
    
    -- Trim log
    while #GuildInviteDB.inviteLog > GuildInviteDB.maxLogEntries do
        table.remove(GuildInviteDB.inviteLog)
    end
end

function GuildInvite:CheckTrigger(message)
    if not message or not GuildInviteDB then return false end
    local trigger = GuildInviteDB.trigger or "inv"
    local lower = message:lower():gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
    return lower == trigger:lower()
end

-- ============================================
-- EVENT HANDLING
-- ============================================

local eventFrame = CreateFrame("Frame")

function GuildInvite:RegisterEvents()
    eventFrame:RegisterEvent("CHAT_MSG_GUILD")
    eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
    eventFrame:RegisterEvent("CHAT_MSG_PARTY")
    eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    eventFrame:RegisterEvent("CHAT_MSG_RAID")
    eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not GuildInviteDB or not GuildInviteDB.enabled then return end
    
    -- Helper: check if sender is the player (ignore our own messages)
    local function IsSelf(sender)
        if not sender then return false end
        local playerName = UnitName("player")
        if not playerName then return false end
        -- sender may be "Name" or "Name-Realm"
        local senderName = sender:match("^([^%-]+)") or sender
        return senderName == playerName
    end
    
    if event == "CHAT_MSG_GUILD" then
        local message, sender = ...
        if IsSelf(sender) then return end
        if GuildInvite:CheckTrigger(message) then
            -- Guild chat - they're definitely in guild, invite directly
            GuildInvite:InviteToRaid(sender, "Guild")
        elseif GuildInvite:CheckConvertTrigger(message) then
            -- Convert to raid request from guild chat
            GuildInvite:ConvertToRaid()
        end
        
    elseif event == "CHAT_MSG_WHISPER" then
        local message, sender = ...
        if IsSelf(sender) then return end
        if GuildInvite:CheckTrigger(message) then
            -- Whisper - verify they're in guild first
            if GuildInvite:IsInGuild(sender) then
                GuildInvite:InviteToRaid(sender, "Whisper")
            elseif GuildInviteDB.respondToNonGuild then
                SendChatMessage("Sorry, raid invites are for guild members only.", "WHISPER", nil, sender)
            end
        elseif GuildInvite:CheckConvertTrigger(message) then
            -- Convert to raid request from whisper (guild only)
            if GuildInvite:IsInGuild(sender) then
                GuildInvite:ConvertToRaid()
            end
        end
        
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        local message, sender = ...
        if IsSelf(sender) then return end
        -- Check for convert trigger in party chat
        if GuildInvite:CheckConvertTrigger(message) then
            GuildInvite:ConvertToRaid()
        -- Also allow inv trigger from party members who are in guild
        elseif GuildInvite:CheckTrigger(message) and GuildInvite:IsInGuild(sender) then
            GuildInvite:InviteToRaid(sender, "Party")
        end
        
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        local message, sender = ...
        if IsSelf(sender) then return end
        -- Allow inv trigger from raid members who are in guild
        if GuildInvite:CheckTrigger(message) and GuildInvite:IsInGuild(sender) then
            GuildInvite:InviteToRaid(sender, "Raid")
        end
        
    elseif event == "GUILD_ROSTER_UPDATE" then
        GuildInvite:UpdateGuildRoster()
        
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- No auto-convert here; only convert when a 6th invite triggers it in InviteToRaid
    end
end)

-- ============================================
-- STATUS
-- ============================================

function GuildInvite:GetQuickStatus()
    if not GuildInviteDB then return "|cFF888888Not initialized|r" end
    
    if GuildInviteDB.enabled then
        local logCount = GuildInviteDB.inviteLog and #GuildInviteDB.inviteLog or 0
        return "|cFF00FF00Active|r (trigger: \"" .. (GuildInviteDB.trigger or "inv") .. "\", " .. logCount .. " invites)"
    else
        return "|cFFFF0000Disabled|r"
    end
end

-- ============================================
-- UI
-- ============================================

function GuildInvite:CreateUI()
    if mainFrame then return mainFrame end
    
    local frame = CreateFrame("Frame", "WM_GuildInviteFrame", UIParent, "BackdropTemplate")
    frame:SetSize(400, 450)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    
    WM:SkinPanel(frame)
    WM:RegisterSkinnedPanel(frame)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF00FF00Guild Invite|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local yOffset = -45
    
    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 20, yOffset)
    enableCB.Text:SetText("Enable auto-invite")
    enableCB:SetChecked(GuildInviteDB.enabled)
    enableCB:SetScript("OnClick", function(self)
        GuildInviteDB.enabled = self:GetChecked()
        GuildInvite:Print(GuildInviteDB.enabled and "Enabled" or "Disabled")
    end)
    
    yOffset = yOffset - 30
    
    -- Trigger word
    local triggerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    triggerLabel:SetPoint("TOPLEFT", 20, yOffset)
    triggerLabel:SetText("Trigger word:")
    
    local triggerInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    triggerInput:SetSize(80, 20)
    triggerInput:SetPoint("LEFT", triggerLabel, "RIGHT", 10, 0)
    triggerInput:SetText(GuildInviteDB.trigger or "inv")
    triggerInput:SetAutoFocus(false)
    triggerInput:SetScript("OnEnterPressed", function(self)
        GuildInviteDB.trigger = self:GetText()
        self:ClearFocus()
        GuildInvite:Print("Trigger set to: " .. GuildInviteDB.trigger)
    end)
    triggerInput:SetScript("OnEditFocusLost", function(self)
        GuildInviteDB.trigger = self:GetText()
    end)
    
    yOffset = yOffset - 30
    
    -- Announce invites checkbox
    local announceCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    announceCB:SetPoint("TOPLEFT", 20, yOffset)
    announceCB.Text:SetText("Announce invites in chat")
    announceCB:SetChecked(GuildInviteDB.announceInvites)
    announceCB:SetScript("OnClick", function(self)
        GuildInviteDB.announceInvites = self:GetChecked()
    end)
    
    yOffset = yOffset - 25
    
    -- Respond to non-guild checkbox
    local respondCB = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
    respondCB:SetPoint("TOPLEFT", 20, yOffset)
    respondCB.Text:SetText("Reply to non-guild whispers")
    respondCB:SetChecked(GuildInviteDB.respondToNonGuild)
    respondCB:SetScript("OnClick", function(self)
        GuildInviteDB.respondToNonGuild = self:GetChecked()
    end)
    
    yOffset = yOffset - 35
    
    -- Info text about triggers
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", 20, yOffset)
    infoText:SetWidth(360)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("|cFFFFFF00Triggers:|r Say trigger word in guild/whisper/party to get invited.\nSay \"raid\" or \"raid convert\" in party/guild to convert to raid.\nAuto-converts to raid when a 6th member is invited.")
    
    yOffset = yOffset - 45
    
    -- Invite log header
    local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logLabel:SetPoint("TOPLEFT", 20, yOffset)
    logLabel:SetText("Recent Invites:")
    
    -- Clear log button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 20)
    clearBtn:SetPoint("LEFT", logLabel, "RIGHT", 10, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        GuildInviteDB.inviteLog = {}
        GuildInvite:UpdateLogDisplay()
    end)
    
    yOffset = yOffset - 20
    
    -- Log scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, yOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.logEntries = {}
    
    -- Refresh roster button
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(120, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", 20, 15)
    refreshBtn:SetText("Refresh Roster")
    refreshBtn:SetScript("OnClick", function()
        GuildInvite:UpdateGuildRoster()
        local count = 0
        for _ in pairs(guildRoster) do count = count + 1 end
        GuildInvite:VerbosePrint("Guild roster updated (" .. math.floor(count/2) .. " members)")
    end)
    
    -- Status text
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMRIGHT", -20, 20)
    frame.statusText = statusText
    
    mainFrame = frame
    self.mainFrame = frame
    
    return frame
end

function GuildInvite:UpdateLogDisplay()
    if not mainFrame or not mainFrame.scrollChild then return end
    
    -- Hide existing entries
    if mainFrame.logEntries then
        for _, entry in ipairs(mainFrame.logEntries) do
            entry:Hide()
        end
    else
        mainFrame.logEntries = {}
    end
    
    if not GuildInviteDB or not GuildInviteDB.inviteLog then return end
    
    local yOffset = 0
    local numEntries = math.min(#GuildInviteDB.inviteLog, 50)
    
    for i = 1, numEntries do
        local entry = GuildInviteDB.inviteLog[i]
        local text = mainFrame.logEntries[i]
        
        if not text then
            text = mainFrame.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetWidth(320)
            text:SetJustifyH("LEFT")
            mainFrame.logEntries[i] = text
        end
        
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", 0, -yOffset)
        
        local sourceColor = entry.source == "Guild" and "|cFF00FF00" or "|cFFFFFF00"
        text:SetText("|cFFFFFFFF" .. entry.time .. "|r " .. sourceColor .. "[" .. entry.source .. "]|r " .. entry.name)
        text:Show()
        
        yOffset = yOffset + 14
    end
    
    mainFrame.scrollChild:SetHeight(math.max(yOffset, 1))
    
    -- Update status
    local rosterCount = 0
    for _ in pairs(guildRoster) do rosterCount = rosterCount + 1 end
    mainFrame.statusText:SetText("Roster: " .. math.floor(rosterCount/2) .. " members")
end

function GuildInvite:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:UpdateLogDisplay()
    end
end
