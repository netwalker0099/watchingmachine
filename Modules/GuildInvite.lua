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
    if not WM:IsModuleOn("GuildInvite") or not GuildInviteDB then return end
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
    if not WM:IsModuleOn("GuildInvite") then return end
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

    if mainFrame and mainFrame:IsShown() then self:UpdateLogDisplay() end
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
    if not WM:IsModuleOn("GuildInvite") then return end
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

-- Dashboard on/off switch (see WM:CreateModuleCards). The settings panel's
-- own enable checkbox goes through the same function.
function GuildInvite:IsModuleEnabled()
    return GuildInviteDB and GuildInviteDB.enabled and true or false
end

function GuildInvite:SetModuleEnabled(v)
    if GuildInviteDB == nil or GuildInviteDB.trigger == nil then self:InitDB() end
    GuildInviteDB.enabled = v and true or false
    self:Print(GuildInviteDB.enabled and "Enabled" or "Disabled")
    if mainFrame and mainFrame:IsShown() then mainFrame:Refresh() end
end

-- Turned off on this character: nothing is invited (the event handler
-- checks), so just close the window
function GuildInvite:OnModuleOff()
    if mainFrame then mainFrame:Hide() end
end

-- The module's page in the guided setup
function GuildInvite:SetupPage(L)
    self:InitDB()
    L:Note("When a guildie types the trigger word on its own in guild chat, they get a group invite from you."
        .. " Whispers, party and raid chat work too, but only from names on your guild roster.")
    L:Note("|cFFFFFFFFHow it works:|r you need to be solo, the party leader, or leader or assist in a raid."
        .. " When a party is full, the 6th invite turns it into a raid first. Someone saying \"raid\" or"
        .. " \"raid convert\" in party or guild chat turns your party into a raid. Each invite is listed in the"
        .. " invite log.")
    L:EditBox({
        label = "Trigger word:", width = 80,
        get = function() return GuildInviteDB.trigger or "inv" end,
        set = function(v) if v ~= "" then GuildInviteDB.trigger = v end end,
        tooltip = { "Trigger Word", "The whole message must be this word (any case), so \"inv pls\" doesn't count.",
            "Saved when you press Enter or click away." },
    })
    L:Checkbox({
        label = "Announce invites in chat",
        get = function() return GuildInviteDB.announceInvites end,
        set = function(v) GuildInviteDB.announceInvites = v end,
        tooltip = { "Announce Invites", "Print a line in your chat frame (only you see it) for each invite sent." },
    })
    L:Checkbox({
        label = "Reply to non-guild whispers",
        get = function() return GuildInviteDB.respondToNonGuild end,
        set = function(v) GuildInviteDB.respondToNonGuild = v end,
        tooltip = { "Reply to Non-Guild Whispers", "When someone outside your guild whispers the trigger word,"
            .. " whisper back \"Sorry, raid invites are for guild members only.\"", "Off: they're silently ignored." },
    })
    L:Note("The invite log and a button to re-read the guild roster are in the Guild Invite window:"
        .. " |cFFFFFF00/wmachine ginvite|r.")
end

-- guildRoster holds each member twice (with and without realm)
local function RosterCount()
    local count = 0
    for _ in pairs(guildRoster) do count = count + 1 end
    return math.floor(count / 2)
end

function GuildInvite:CreateUI()
    if mainFrame then return mainFrame end

    -- Settings rows on top, the invite log fills the rest
    local panel = WM.UI:CreatePanel({
        name = "WM_GuildInviteFrame",
        title = "Guild Invite",
        titleColor = "00FF00",
        width = 400,
        height = 450,
        minHeight = 360,
        scroll = false,
        onRefresh = function() GuildInvite:UpdateLogDisplay() end,
    })
    local L = panel.layout

    L:Checkbox({
        label = "Enable auto-invite",
        get = function() return GuildInvite:IsModuleEnabled() end,
        set = function(v) GuildInvite:SetModuleEnabled(v) end,
    })
    L:EditBox({
        label = "Trigger word:", width = 80,
        get = function() return GuildInviteDB.trigger or "inv" end,
        set = function(v)
            if v == GuildInviteDB.trigger then return end
            GuildInviteDB.trigger = v
            GuildInvite:Print("Trigger set to: " .. v)
        end,
        tooltip = { "Trigger Word", "Saying exactly this word (any case) in guild chat gets the sender invited.",
            "Whispers, party and raid chat work too, but only from players on your guild roster.",
            "Saved when you press Enter or click away." },
    })
    L:Checkbox({
        label = "Announce invites in chat",
        get = function() return GuildInviteDB.announceInvites end,
        set = function(v) GuildInviteDB.announceInvites = v end,
        tooltip = { "Announce Invites", "Print a line in your chat frame for each invite sent.",
            "With verbose chat on, also notes requests ignored because you aren't leader or assist." },
    })
    L:Checkbox({
        label = "Reply to non-guild whispers",
        get = function() return GuildInviteDB.respondToNonGuild end,
        set = function(v) GuildInviteDB.respondToNonGuild = v end,
        tooltip = { "Reply to Non-Guild Whispers", "When someone outside your guild whispers the trigger word,"
            .. " whisper back \"Sorry, raid invites are for guild members only.\"",
            "Off: they're silently ignored." },
    })

    L:Space(4)
    L:Note("|cFFFFFF00Triggers:|r |cFF888888Say the trigger word in guild/whisper/party to get invited."
        .. " Say \"raid\" or \"raid convert\" in party/guild to convert to raid."
        .. " Auto-converts to raid when a 6th member is invited.|r")

    -- Invite log header with its Clear button
    local row = L:Row(24)
    local logLabel = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logLabel:SetPoint("LEFT", row.frame, "LEFT", 8, 0)
    logLabel:SetText("Recent Invites:")
    WM:ThemeText(logLabel, "headerColor")
    row:Button({
        text = "Clear", width = 70,
        onClick = function()
            GuildInviteDB.inviteLog = {}
            GuildInvite:UpdateLogDisplay()
        end,
        tooltip = { "Clear Log", "Delete every entry from the invite log." },
    }, 120)

    -- Scrollable log in the remaining space
    local fill = L:Fill(100)
    local scrollFrame = CreateFrame("ScrollFrame", "WM_GuildInviteScrollFrame", fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(400 - 24 - 8 - 23)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild
    panel.logEntries = {}

    panel:AddFooterButton({
        text = "Refresh Roster", width = 120,
        onClick = function()
            GuildInvite:UpdateGuildRoster()
            GuildInvite:VerbosePrint("Guild roster updated (" .. RosterCount() .. " members)")
            GuildInvite:UpdateLogDisplay()
        end,
        tooltip = { "Refresh Roster", "Re-read the guild roster now. Whispers, party and raid requests"
            .. " are only answered for names on it; it also updates on its own when the game sends a roster update." },
    }, "LEFT")
    panel.statusText = panel:AddFooterText({ text = "", font = "GameFontNormalSmall" }, "RIGHT")

    panel:Finish()

    mainFrame = panel
    self.mainFrame = panel

    return panel
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
    mainFrame.statusText:SetText("Roster: " .. RosterCount() .. " members")
end

function GuildInvite:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
