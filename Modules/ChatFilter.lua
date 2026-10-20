-- Watching Machine: Chat Filter Module
-- Hides chat messages containing phrases you choose ("Guild Loot Run",
-- "WTS boost", ...). Filtered messages are removed from your chat frames
-- AND skipped by Keyword Monitor, which asks this module first: filters are
-- applied before keyword monitoring.

local AddonName, WM = ...
local ChatFilter = {}
WM:RegisterModule("ChatFilter", ChatFilter)

ChatFilter.version = "1.0"

-- Where filters apply. Every event is hooked once; the toggle is read per
-- message, so switching a type on or off needs no re-registration.
local CHAT_TYPES = {
    { key = "channels", label = "Public channels (Trade, General, LFG ...)",
      events = { "CHAT_MSG_CHANNEL" }, default = true },
    { key = "say", label = "Say and yell",
      events = { "CHAT_MSG_SAY", "CHAT_MSG_YELL" }, default = false },
    { key = "whisper", label = "Whispers",
      events = { "CHAT_MSG_WHISPER" }, default = false },
}

local EVENT_TYPE = {}   -- event -> chat type key
for _, t in ipairs(CHAT_TYPES) do
    for _, ev in ipairs(t.events) do EVENT_TYPE[ev] = t.key end
end

-- Ready-made filters for common advert spam, switched on with one click.
-- Kept apart from the player's own phrases so they can be turned off again
-- without hunting through the list. Off by default: hiding adverts nobody
-- asked to hide would be a surprise.
local PREMADES = {
    { key = "gdkp", label = "GDKP", phrases = { "GDKP" },
      desc = "Gold-bid raid adverts (any message mentioning GDKP)." },
    { key = "glr", label = "Guild Loot Run", phrases = { "Guild Loot Run" },
      desc = "Guild loot run adverts." },
    { key = "gearcarry", label = "Gear Carry", phrases = { "Gear Carry", "Gear Carries" },
      desc = "Paid gear carry adverts (\"gear carry\" or \"gear carries\")." },
}
ChatFilter.PREMADES = PREMADES

local defaults = {
    enabled = true,
    phrases = {},   -- as typed, in the order added
    premades = {},  -- premade key -> bool, all off until ticked
    types = {},     -- chat type key -> bool, filled from CHAT_TYPES
}
for _, t in ipairs(CHAT_TYPES) do defaults.types[t.key] = t.default end

-- Session counts of hidden messages, keyed by normalised phrase
local hidden = {}
local hiddenTotal = 0

local mainFrame = nil

function ChatFilter:Print(msg)
    WM:ModulePrint("ChatFilter", msg)
end

-- ============================================
-- MATCHING
-- ============================================

-- What the player actually reads: colour codes and link markup stripped
-- (an item link shows as its [Name]), lower case, single spaces. Phrases
-- and messages are both normalised, so "guild  LOOT run" matches.
local function Normalise(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:lower():gsub("%s+", " ")
    return (text:gsub("^ ", ""):gsub(" $", ""))
end
ChatFilter.Normalise = Normalise

local compiled = {}   -- normalised phrases, rebuilt when the list changes

local function Compile()
    wipe(compiled)
    local seen = {}
    local function Add(p)
        local n = Normalise(p)
        if n ~= "" and not seen[n] then
            seen[n] = true
            compiled[#compiled + 1] = n
        end
    end
    if not ChatFilterDB then return end
    for _, pre in ipairs(PREMADES) do
        if ChatFilterDB.premades and ChatFilterDB.premades[pre.key] then
            for _, p in ipairs(pre.phrases) do Add(p) end
        end
    end
    for _, p in ipairs(ChatFilterDB.phrases or {}) do Add(p) end
end

-- The phrase a message contains, or nil. Ignores the on/off switches.
function ChatFilter:Match(message)
    if #compiled == 0 or not message then return nil end
    local text = Normalise(message)
    for _, p in ipairs(compiled) do
        if text:find(p, 1, true) then return p end
    end
    return nil
end

local function IsOwnMessage(sender)
    if not sender then return false end
    local name = sender:match("^([^%-]+)") or sender
    return name == UnitName("player")
end

-- Would this chat event be hidden? Returns the matching phrase or nil.
-- Keyword Monitor calls this before looking at a message.
function ChatFilter:FilteredBy(event, message, sender)
    if not ChatFilterDB or not ChatFilterDB.enabled then return nil end
    local typeKey = EVENT_TYPE[event]
    if not typeKey or not ChatFilterDB.types[typeKey] then return nil end
    if IsOwnMessage(sender) then return nil end   -- never hide what you typed
    return self:Match(message)
end

function ChatFilter:IsFiltered(event, message, sender)
    return self:FilteredBy(event, message, sender) ~= nil
end

-- ============================================
-- CHAT FRAME FILTER
-- ============================================
-- Called once per chat frame showing the message, so a message in three
-- tabs arrives three times. lineID (arg11) is the same for all of them;
-- it's used to count each message once and to skip re-matching.

local lastLineID, lastResult

local function MessageFilter(_, event, message, sender, ...)
    local lineID = select(9, ...)
    if lineID and lineID == lastLineID then return lastResult end

    local phrase = ChatFilter:FilteredBy(event, message, sender)
    lastLineID, lastResult = lineID, phrase ~= nil
    if phrase then
        hidden[phrase] = (hidden[phrase] or 0) + 1
        hiddenTotal = hiddenTotal + 1
        ChatFilter:RefreshPanel()   -- counts and session total
    end
    return phrase ~= nil
end
ChatFilter.MessageFilter = MessageFilter   -- for tests

-- ============================================
-- PHRASE LIST
-- ============================================

function ChatFilter:GetPhrases()
    return ChatFilterDB.phrases
end

-- Returns true if added; false for an empty or duplicate phrase
function ChatFilter:AddPhrase(phrase)
    phrase = strtrim(phrase or "")
    local n = Normalise(phrase)
    if n == "" then return false end
    for _, existing in ipairs(ChatFilterDB.phrases) do
        if Normalise(existing) == n then
            self:Print("Already filtering \"" .. existing .. "\"")
            return false
        end
    end
    table.insert(ChatFilterDB.phrases, phrase)
    Compile()
    self:Print("Filtering \"" .. phrase .. "\"")
    self:RefreshPanel()
    return true
end

function ChatFilter:RemovePhrase(index)
    local phrase = table.remove(ChatFilterDB.phrases, index)
    Compile()
    if phrase then self:Print("No longer filtering \"" .. phrase .. "\"") end
    self:RefreshPanel()
end

function ChatFilter:ClearPhrases()
    wipe(ChatFilterDB.phrases)
    Compile()
    self:Print("All chat filters removed")
    self:RefreshPanel()
end

function ChatFilter:HiddenCount(phrase)
    return hidden[Normalise(phrase)] or 0
end

function ChatFilter:IsPremadeOn(key)
    return ChatFilterDB.premades[key] and true or false
end

function ChatFilter:SetPremade(key, on)
    ChatFilterDB.premades[key] = on and true or false
    Compile()
    self:RefreshPanel()
end

-- Hidden count for a premade: the sum over its phrases
function ChatFilter:PremadeHiddenCount(pre)
    local n = 0
    for _, p in ipairs(pre.phrases) do n = n + self:HiddenCount(p) end
    return n
end

-- Active filters: ticked premades plus your own phrases
function ChatFilter:ActiveCount()
    local n = #ChatFilterDB.phrases
    for _, pre in ipairs(PREMADES) do
        if ChatFilterDB.premades[pre.key] then n = n + 1 end
    end
    return n
end

function ChatFilter:HiddenTotal()
    return hiddenTotal
end

function ChatFilter:ReportHidden()
    self:Print("=== Hidden this session: " .. hiddenTotal .. " ===")
    if self:ActiveCount() == 0 then
        print("  (no filters)")
        return
    end
    for _, pre in ipairs(PREMADES) do
        if ChatFilterDB.premades[pre.key] then
            print(string.format("  %s (premade): %d", pre.label, self:PremadeHiddenCount(pre)))
        end
    end
    for _, p in ipairs(ChatFilterDB.phrases) do
        print(string.format("  %s: %d", p, self:HiddenCount(p)))
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

function ChatFilter:InitDB()
    if not ChatFilterDB then ChatFilterDB = {} end
    if ChatFilterDB.enabled == nil then ChatFilterDB.enabled = defaults.enabled end
    if type(ChatFilterDB.phrases) ~= "table" then ChatFilterDB.phrases = {} end
    if type(ChatFilterDB.premades) ~= "table" then ChatFilterDB.premades = {} end
    if type(ChatFilterDB.types) ~= "table" then ChatFilterDB.types = {} end
    for key, v in pairs(defaults.types) do
        if ChatFilterDB.types[key] == nil then ChatFilterDB.types[key] = v end
    end
    Compile()
end

function ChatFilter:Initialize()
    self:InitDB()
    if self.hooked or not ChatFrame_AddMessageEventFilter then return end
    for event in pairs(EVENT_TYPE) do
        ChatFrame_AddMessageEventFilter(event, MessageFilter)
    end
    self.hooked = true
end

-- Dashboard on/off switch (see WM:CreateModuleCards). The panel's own
-- enable checkbox goes through the same function.
function ChatFilter:IsModuleEnabled()
    return ChatFilterDB and ChatFilterDB.enabled and true or false
end

function ChatFilter:SetModuleEnabled(v)
    ChatFilterDB.enabled = v and true or false
    self:RefreshPanel()
end

function ChatFilter:GetQuickStatus()
    if not ChatFilterDB then return "|cFF888888Not initialized|r" end
    local n = self:ActiveCount()
    if not ChatFilterDB.enabled then
        return "|cFFFF0000Disabled|r (" .. n .. " filters)"
    elseif n == 0 then
        return "|cFFFFFF00No filters set|r"
    end
    return "|cFF00FF00Active|r (" .. n .. " filters, " .. hiddenTotal .. " hidden)"
end

-- ============================================
-- PANEL
-- ============================================

-- Shared with Keyword Monitor's panel, so both say the same thing
function ChatFilter:OrderWarning()
    return "|cFFFFAA00Filters are applied before Keyword Monitor.|r A message hidden here is never"
        .. " checked for keywords, so it can't produce a Keyword Monitor match."
end

local ROW_H = 22

function ChatFilter:RefreshPanel()
    if mainFrame and mainFrame:IsShown() then mainFrame:Refresh() end
end

function ChatFilter:RefreshList()
    if not mainFrame then return end
    local child, rows = mainFrame.listChild, mainFrame.rows
    local phrases = ChatFilterDB.phrases

    for i, phrase in ipairs(phrases) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, child, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.count:SetPoint("RIGHT", -70, 0)
            row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.remove:SetSize(60, 18)
            row.remove:SetPoint("RIGHT", -4, 0)
            row.remove:SetText("Remove")
            WM.UI.SetTooltip(row.remove, { "Remove", "Stop filtering this phrase." })
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row:SetBackdropColor(0.1, 0.1, 0.1, (i % 2 == 0) and 0.5 or 0)
        row.text:SetWidth(mainFrame.listWidth - 150)
        row.text:SetText(phrase)
        local n = ChatFilter:HiddenCount(phrase)
        row.count:SetText(n > 0 and ("|cFFFFCC00" .. n .. " hidden|r") or "|cFF888888none yet|r")
        local index = i
        row.remove:SetScript("OnClick", function() ChatFilter:RemovePhrase(index) end)
        row:Show()
    end
    for i = #phrases + 1, #rows do rows[i]:Hide() end

    mainFrame.emptyText:SetShown(#phrases == 0)
    child:SetHeight(math.max(#phrases * ROW_H, 1))
end

function ChatFilter:CreateUI()
    if mainFrame then return mainFrame end

    local panel = WM.UI:CreatePanel({
        name = "WM_ChatFilterFrame",
        title = "Chat Filter",
        titleColor = "FF7744",
        width = 420,
        height = 620,
        minHeight = 460,
        scroll = false,
        onRefresh = function() ChatFilter:RefreshList() end,
    })
    local L = panel.layout

    L:Note(function() return ChatFilter:OrderWarning() end)

    L:Checkbox({
        label = "Enable chat filter",
        get = function() return ChatFilter:IsModuleEnabled() end,
        set = function(v) ChatFilter:SetModuleEnabled(v) end,
        tooltip = { "Chat Filter", "Hide chat messages containing any phrase below. Off: nothing"
            .. " is hidden, and Keyword Monitor sees every message again." },
    })

    L:Header("Filter in")
    for _, t in ipairs(CHAT_TYPES) do
        L:Checkbox({
            label = t.label, indent = 5,
            get = function() return ChatFilterDB.types[t.key] end,
            set = function(v) ChatFilterDB.types[t.key] = v end,
        })
    end

    L:Header("Premade filters")
    for _, pre in ipairs(PREMADES) do
        L:Checkbox({
            indent = 5,
            label = function()
                local n = ChatFilter:PremadeHiddenCount(pre)
                return pre.label .. (n > 0 and (" |cFFFFCC00(" .. n .. " hidden)|r") or "")
            end,
            get = function() return ChatFilter:IsPremadeOn(pre.key) end,
            set = function(v) ChatFilter:SetPremade(pre.key, v) end,
            tooltip = { pre.label, pre.desc, "Matches: " .. table.concat(pre.phrases, ", ") },
        })
    end

    L:Header("Your phrases")
    local row = L:Row(26)
    local addBox = row:EditBox({
        label = "Add phrase:", width = 190, maxLetters = 100,
        onEnter = function(text) ChatFilter:AddPhrase(text) end, clearOnEnter = true,
        tooltip = {
            "Add a Phrase",
            "Type a phrase and press Enter, e.g. Guild Loot Run. A message containing it anywhere is hidden.",
            "Matching ignores case, colours, item-link brackets and extra spaces. It is plain text: no wildcards.",
        },
    }, 8)
    row:Button({
        text = "Add", width = 50,
        onClick = function()
            if ChatFilter:AddPhrase(addBox:GetText()) then addBox:SetText("") end
        end,
    }, 300)
    L:Note("Your own messages are never hidden. Hidden counts are for this session.")

    row = L:Row(24)
    local header = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("LEFT", row.frame, "LEFT", 8, 0)
    header:SetText("Your phrase list")
    WM:ThemeText(header, "headerColor")
    row:RightButton({
        text = "Clear All", width = 70, confirm = true, confirmText = "Confirm",
        onClick = function() ChatFilter:ClearPhrases() end,
        tooltip = { "Clear All", "Remove every phrase. Click twice to confirm." },
    }, 3)
    row:RightText({
        text = function() return "|cFF888888" .. hiddenTotal .. " hidden this session|r" end,
    }, 82)

    -- Phrase list in the remaining space
    local fill = L:Fill(80)
    local scrollFrame = CreateFrame("ScrollFrame", "WM_ChatFilterScroll", fill, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scrollFrame)
    panel.listWidth = 420 - 24 - 4 - 23
    child:SetWidth(panel.listWidth)
    child:SetHeight(1)
    scrollFrame:SetScrollChild(child)

    local empty = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOP", 0, -10)
    empty:SetText("|cFF888888No phrases yet. Add one above.|r")

    panel.listChild, panel.rows, panel.emptyText = child, {}, empty

    panel:Finish()
    mainFrame = panel
    self.mainFrame = panel
    return panel
end

function ChatFilter:Toggle()
    local frame = self:CreateUI()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function ChatFilter:ToggleUI()
    self:Toggle()
end
