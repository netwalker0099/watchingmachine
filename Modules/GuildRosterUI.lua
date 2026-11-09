-- Watching Machine: Roster Manager window
-- Four tabs: Roster (every member; click one for their details), Log (the
-- guild log), Former (who left, and the ban list) and Sync (who you share
-- edits with, and the import from Guild Roster Manager). The details pane
-- edits join and promotion dates, birthday, custom note, alts and bans.
-- Hovering a name in the game's guild roster shows the same details.

local AddonName, WM = ...
local GR = WM.GuildRoster
local DB = GR.DB

local panel, options
local ROW_H = 16
local DETAILS_W = 290
GR.tab = "roster"

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "FFFFFF" end
    return string.format("%02X%02X%02X", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
end
local function Colored(rec) return "|cFF" .. ClassHex(rec.class) .. GR.Short(rec.name) .. "|r" end

local function LastOnline(rec)
    if rec.online then return "|cFF33FF33online|r" end
    local h = rec.offlineHours or 0
    if rec.leftAt then return "left " .. date("%d %b %Y", rec.leftAt) end
    if h < 24 then return h .. "h" end
    return math.floor(h / 24) .. "d"
end

-- ============================================
-- POPUPS (text entry)
-- ============================================

StaticPopupDialogs["WM_GUILDROSTER_INPUT"] = {
    text = "%s",
    button1 = OKAY or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 150,
    OnShow = function(self, data)
        local e = self.editBox or self.EditBox
        if e and data then e:SetText(data.value or ""); e:HighlightText() end
        if e and GR.HookCompletion then GR.HookCompletion(e) end
    end,
    OnHide = function() if GR.HideSuggestions then GR.HideSuggestions() end end,
    OnAccept = function(self, data)
        local e = self.editBox or self.EditBox
        if e and data and data.fn then data.fn(strtrim(e:GetText() or "")) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local data = p and p.data
        if data and data.fn then data.fn(strtrim(self:GetText() or "")) end
        if p then p:Hide() end
    end,
    EditBoxOnEscapePressed = function(self) local p = self:GetParent(); if p then p:Hide() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- complete (optional): text -> matching records, to finish names as you type
local function Ask(text, value, fn, complete)
    if StaticPopup_Show then
        StaticPopup_Show("WM_GUILDROSTER_INPUT", text, nil, { value = value, fn = fn, complete = complete })
    end
end
GR.Ask = Ask

-- ============================================
-- NAMES AS YOU TYPE
-- ============================================
-- In a name box, typing finishes the name of a matching guild member (the
-- rest highlighted, so typing on replaces it), and up to 8 matches are
-- listed under the box to click. Tab moves to the next match.

local MAX_SUGGEST = 8

-- Records whose name starts with the text (online first, then by name).
-- from: "members", or "all" for members and former members; skip: names to leave out
function GR:NameMatches(text, from, skip)
    local g = self:Guild()
    text = strtrim(text or ""):lower()
    if not g or text == "" then return {} end
    local out = {}
    local function Scan(src)
        for name, rec in pairs(src) do
            if not (skip and skip[name]) and (GR.Short(name):lower():sub(1, #text) == text or name:lower():sub(1, #text) == text) then
                out[#out + 1] = rec
            end
        end
    end
    Scan(g.members)
    if from == "all" then Scan(g.former) end
    table.sort(out, function(a, b)
        if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
        return a.name < b.name
    end)
    return out
end

local suggest
local function Suggestions()
    if suggest then return suggest end
    suggest = CreateFrame("Frame", "WM_GuildRosterSuggest", UIParent, "BackdropTemplate")
    suggest:SetFrameStrata("FULLSCREEN_DIALOG")
    suggest:SetWidth(200)
    if suggest.SetBackdrop then
        suggest:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        suggest:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        suggest:SetBackdropBorderColor(0.4, 0.8, 1, 0.8)
    end
    suggest.rows = {}
    for i = 1, MAX_SUGGEST do
        local b = CreateFrame("Button", nil, suggest)
        b:SetHeight(16)
        b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 16)
        b:SetPoint("RIGHT", suggest, "RIGHT", -4, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetColorTexture(1, 1, 1, 0.12)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0)
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self)
            if suggest.editBox and self.value then
                suggest.editBox:SetText(self.value)
                suggest.editBox:SetCursorPosition(#self.value)
                suggest.editBox:SetFocus()
            end
            suggest:Hide()
        end)
        suggest.rows[i] = b
    end
    suggest:Hide()
    return suggest
end

function GR.HideSuggestions() if suggest then suggest:Hide() end end

-- The name to put in the box for a record: just the name on your realm
local function BoxName(rec)
    local short = GR.Short(rec.name)
    return GR.FullName(short) == rec.name and short or rec.name
end

local function ShowSuggestions(e, matches)
    local s = Suggestions()
    s.editBox = e
    local n = math.min(#matches, MAX_SUGGEST)
    if n == 0 then s:Hide() return end
    for i, b in ipairs(s.rows) do
        local rec = matches[i]
        if i <= n then
            b.value = BoxName(rec)
            local hex = rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
            hex = hex and type(hex.colorStr) == "string" and hex.colorStr or "ffffffff"
            b.text:SetText("|c" .. hex .. b.value .. "|r  |cFF888888" .. (rec.level or "") .. " "
                .. (rec.rankName or "") .. (rec.online and "  |cFF33FF33online|r" or "") .. "|r")
            b:Show()
        else
            b.value = nil
            b:Hide()
        end
    end
    s:SetHeight(8 + n * 16)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", e, "BOTTOMLEFT", -6, -4)
    s:Show()
end

-- Finish the name being typed, and list the matches
function GR.CompleteName(e, userInput)
    local p = e:GetParent()
    local data = p and p.which == "WM_GUILDROSTER_INPUT" and p.data
    if not (data and data.complete) then GR.HideSuggestions() return end
    local text = e:GetText() or ""
    local grew = #text > (e.wmLastLen or 0)
    e.wmLastLen = #text
    if not userInput then return end
    local matches = data.complete(text)
    e.wmMatches, e.wmMatchIndex = matches, 1
    ShowSuggestions(e, matches)
    -- Typing forwards (not deleting): fill in the rest of the first match
    if grew and matches[1] then
        local full = BoxName(matches[1])
        if #full > #text and full:lower():sub(1, #text) == text:lower() then
            e:SetText(text .. full:sub(#text + 1))
            e:HighlightText(#text, #full)
            e:SetCursorPosition(#text)
            e.wmLastLen = #text
        end
    end
end

-- Tab: the next match
function GR.NextMatch(e)
    local m = e.wmMatches
    if not m or #m == 0 then return end
    e.wmMatchIndex = (e.wmMatchIndex or 1) % #m + 1
    local name = BoxName(m[e.wmMatchIndex])
    e:SetText(name)
    e:SetCursorPosition(#name)
    e.wmLastLen = #name
end

function GR.HookCompletion(e)
    e.wmLastLen = #(e:GetText() or "")
    e.wmMatches = nil
    if e.wmCompletionHooked then return end
    e.wmCompletionHooked = true
    e:HookScript("OnTextChanged", function(self, userInput) GR.CompleteName(self, userInput) end)
    e:HookScript("OnTabPressed", function(self)
        local p = self:GetParent()
        if p and p.which == "WM_GUILDROSTER_INPUT" and p.data and p.data.complete then GR.NextMatch(self) end
    end)
end

local function Refresh() if GR.RefreshUI then GR:RefreshUI() end end

-- ============================================
-- EDIT ACTIONS (the details pane's buttons)
-- ============================================

function GR:EditJoinDate(name)
    local rec = self:Find(name)
    if not rec then return end
    Ask("Join date for " .. GR.Short(rec.name) .. " (day/month/year, e.g. 15/1/2026):", GR.PrettyDate(rec.join.date), function(t)
        local s = GR.ParseDate(t)
        if s then GR:SetJoinDate(rec.name, s) else WM:Print("Not a date: " .. t) end
        Refresh()
    end)
end

function GR:EditPromoDate(name)
    local rec = self:Find(name)
    if not rec then return end
    Ask("Promotion date for " .. GR.Short(rec.name) .. " (day/month/year):", GR.PrettyDate(rec.promo.date), function(t)
        local s = GR.ParseDate(t)
        if s then GR:SetPromoDate(rec.name, s) else WM:Print("Not a date: " .. t) end
        Refresh()
    end)
end

function GR:EditBirthday(name)
    local rec = self:Find(name)
    if not rec then return end
    local cur = (rec.bday.d or 0) > 0 and (rec.bday.d .. "/" .. rec.bday.m) or ""
    Ask("Birthday for " .. GR.Short(rec.name) .. " and their alts (day/month; empty to clear):", cur, function(t)
        if t == "" then GR:SetBirthday(rec.name, 0, 0); Refresh() return end
        local d, m = t:match("^(%d%d?)[/.%-](%d%d?)$")
        d, m = tonumber(d), tonumber(m)
        if d and m and d >= 1 and d <= 31 and m >= 1 and m <= 12 then GR:SetBirthday(rec.name, d, m)
        else WM:Print("Not a day/month: " .. t) end
        Refresh()
    end)
end

function GR:EditCustomNote(name)
    local rec = self:Find(name)
    if not rec then return end
    Ask("Custom note for " .. GR.Short(rec.name) .. " (up to 150 characters, shared with your guild's officers' tools):",
        rec.custom.text or "", function(t) GR:SetCustomNote(rec.name, t); Refresh() end)
end

function GR:AskAddAlt(name)
    local rec = self:Find(name)
    if not rec then return end
    -- Names finish as you type, from guild members not already in this alt group
    local function Complete(text)
        local g, skip = self:Guild(), { [rec.name] = true }
        local grp = g and rec.group and g.groups[rec.group]
        for _, n in ipairs(grp and grp.members or {}) do skip[n] = true end
        return self:NameMatches(text, "members", skip)
    end
    Ask("Add an alt to " .. GR.Short(rec.name) .. " (their name; both must be in the guild). Names finish as you type; Tab for the next match:", "", function(t)
        local alt = self:Find(t)
        if not alt or not GR:AddAlt(rec.name, alt.name) then WM:Print("Couldn't add " .. t .. " (not a guild member?).") end
        Refresh()
    end, Complete)
end

function GR:AskBan(name)
    local rec = self:Find(name)
    if not rec then return end
    Ask("Ban " .. GR.Short(rec.name) .. "? Reason (optional):", "", function(t)
        GR:SetBan(rec.name, true, t)
        Refresh()
    end)
end

function GR:AskBanByName()
    Ask("Ban someone by name (Name or Name-Realm), e.g. a player who isn't in the guild. Members and former members finish as you type:", "", function(t)
        if t == "" then return end
        Ask("Reason for banning " .. t .. " (optional):", "", function(reason)
            GR:SetBan(t, true, reason)
            Refresh()
        end)
    end, function(text) return self:NameMatches(text, "all") end)
end

-- ============================================
-- DETAILS (lines shared by the pane and the roster tooltip)
-- ============================================

function GR:DetailLines(rec)
    local out = {}
    local function Add(l, r) out[#out + 1] = { l, r or "" } end
    local g = self:Guild()
    local className = rec.class and type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[rec.class]
    if type(className) ~= "string" then className = rec.class or "" end
    Add("Level " .. (rec.level or "?") .. " " .. className, rec.rankName or "")
    Add("Last online", LastOnline(rec))
    Add("Joined", (rec.join.date ~= "" and GR.PrettyDate(rec.join.date) or "unknown") .. (rec.join.verified and "" or " |cFF888888(unverified)|r"))
    Add("Promoted", (rec.promo.date ~= "" and GR.PrettyDate(rec.promo.date) or "unknown") .. (rec.promo.verified and "" or " |cFF888888(unverified)|r"))
    if (rec.bday.d or 0) > 0 then Add("Birthday", rec.bday.d .. " " .. (GR.MONTHS[rec.bday.m] or "?")) end
    local grp = g and rec.group and g.groups[rec.group]
    if grp then
        local alts = {}
        for _, n in ipairs(grp.members) do if n ~= rec.name then alts[#alts + 1] = GR.Short(n) end end
        if grp.main == rec.name then Add("Main", "|cFFFFD100yes|r")
        elseif grp.main ~= "" then Add("Main", GR.Short(grp.main)) end
        if #alts > 0 then Add("Alts", table.concat(alts, ", ")) end
    end
    if (rec.timesInGuild or 1) > 1 then Add("Times in guild", tostring(rec.timesInGuild)) end
    if self.ReadyFor then
        local nextRank, days = self:ReadyFor(rec)
        if nextRank then Add("|cFFFFD100Ready to promote|r", days .. " days at rank: " .. GR.Tools.RankName(g, nextRank)) end
    end
    if self.IsPurgeIgnored and self:IsPurgeIgnored(rec.name) then Add("Purge", "|cFF888888never (ignored)|r") end
    if rec.custom.text ~= "" then Add("Custom note", rec.custom.text) end
    if rec.ban.on then
        Add("|cFFFF3333Banned|r", GR.Short(rec.ban.by) .. (rec.ban.reason ~= "" and (": " .. rec.ban.reason) or ""))
    end
    -- Their last loot, with Loot Council on
    local LC = WM:IsModuleOn("LootCouncil") and WM.LootCouncil
    if LC and LC.LastLoot then
        local last = LC.LastLoot(rec.name)
        if last then Add("Last loot", LC.Ago(last.t) .. ": " .. LC.ItemText(last) .. " " .. LC.HowText(last)) end
    end
    -- Their armory, with ArmorySnap on: each spec, its GearScore and age
    local Arm = GR.Armory()
    if Arm then
        for _, e in ipairs(Arm.Specs(rec.name)) do
            local AS = WM.modules.ArmorySnap
            local score = AS and AS.ScoreMember and AS.ScoreMember(e)
            Add("Armory", Arm.SpecLabel(e.spec) .. (score and score > 0 and (" GS " .. score) or "")
                .. " |cFF888888(" .. Arm.Age(e.time) .. ")|r")
        end
    end
    return out
end

-- ArmorySnap's armory, while ArmorySnap is on
function GR.Armory()
    local AS = WM:IsModuleOn("ArmorySnap") and WM.modules.ArmorySnap
    return AS and not AS.standaloneConflict and AS.Armory or nil
end

-- Open a player's armory, asking the guild for a newer one
function GR:ShowArmory(name)
    local Arm = GR.Armory()
    if not Arm then
        WM:ModulePrint("GuildRoster", "The armory is part of ArmorySnap: turn ArmorySnap on to see it.")
        return
    end
    Arm:Query(name)
    if not Arm.Specs(name)[1] then
        WM:ModulePrint("GuildRoster", "No armory for " .. GR.Short(name) .. " yet. Asked guildmates for one;"
            .. " it's also saved when ArmorySnap inspects them, or when they run Watching Machine.")
        return
    end
    WM.modules.ArmorySnap.ShowArmory(name, Arm.ViewKey(name))
end

-- ============================================
-- THE GAME'S GUILD ROSTER: details on hover
-- ============================================

local function HoverRoster(button)
    if not WM:IsModuleOn("GuildRoster") or not DB().hoverDetails then return end
    local index = button.guildIndex
    if not index then return end
    local name = GetGuildRosterInfo(index)
    local rec = name and GR:Find(name)
    if not rec then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Colored(rec))
    for _, l in ipairs(GR:DetailLines(rec)) do GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:AddLine("Roster Manager: /wmachine roster", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local hooked = {}
function GR:HookGuildRoster()
    for _, base in ipairs({ "GuildFrameButton", "GuildStatusButton" }) do
        for i = 1, 30 do
            local b = rawget(_G, base .. i)
            if not b then break end
            if not hooked[b] and b.HookScript then
                hooked[b] = true
                b:HookScript("OnEnter", HoverRoster)
                b:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
    end
end

-- ============================================
-- THE WINDOW
-- ============================================

local function Matches(rec, q)
    if not q or q == "" then return true end
    q = q:lower()
    return (rec.name or ""):lower():find(q, 1, true) or (rec.note or ""):lower():find(q, 1, true)
        or (rec.custom.text or ""):lower():find(q, 1, true) or (rec.rankName or ""):lower():find(q, 1, true)
end

-- How the roster tab sorts and what it shows (Sort / Show above the list)
GR.SORTS = {
    { value = "rank", text = "Online, then rank" }, { value = "name", text = "Name" },
    { value = "class", text = "Class" }, { value = "level", text = "Level" },
    { value = "lastonline", text = "Last online" }, { value = "joined", text = "Join date" },
}
GR.FILTERS = {
    { value = "all", text = "Everyone" }, { value = "online", text = "Online" },
    { value = "inactive", text = "Inactive" }, { value = "nonote", text = "No public note" },
    { value = "mains", text = "Mains" }, { value = "noalts", text = "Not in an alt group" },
    { value = "ready", text = "Ready to promote" },
}

local function SortBy() return DB().rosterSort or "rank" end
local function Hours(r) return r.online and 0 or (r.offlineHours or 0) end

local function RosterOrder(a, b)
    local by = SortBy()
    if by == "name" then return a.name < b.name end
    if by == "class" then
        if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
    elseif by == "level" then
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    elseif by == "lastonline" then
        if Hours(a) ~= Hours(b) then return Hours(a) < Hours(b) end
    elseif by == "joined" then
        local ja, jb = a.join and a.join.date or "", b.join and b.join.date or ""
        if ja ~= jb then
            if ja == "" then return false end
            if jb == "" then return true end
            return ja < jb
        end
    else
        if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
    end
    if a.rankIndex ~= b.rankIndex then return (a.rankIndex or 99) < (b.rankIndex or 99) end
    return a.name < b.name
end
GR.RosterOrder = RosterOrder

-- Does a member pass the Show filter?
function GR:PassesFilter(rec, g)
    local f = DB().rosterFilter or "all"
    if f == "online" then return rec.online and true or false end
    if f == "inactive" then return Hours(rec) >= (DB().inactiveDays or 14) * 24 end
    if f == "nonote" then return (rec.note or "") == "" end
    local grp = rec.group and g and g.groups[rec.group]
    if f == "mains" then return grp ~= nil and grp.main == rec.name end
    if f == "noalts" then return grp == nil end
    if f == "ready" then return self.ReadyFor and self:ReadyFor(rec) ~= nil end
    return true
end

local function RosterLine(rec, g, indent)
    local grp = rec.group and g.groups[rec.group]
    local tag = grp and (grp.main == rec.name and " |cFFFFD100(main)|r" or (grp.main ~= "" and " |cFF888888(alt)|r" or "")) or ""
    local ban = rec.ban.on and " |cFFFF3333(banned)|r" or ""
    return { rec = rec, indent = indent,
        text = Colored(rec) .. tag .. ban .. "  |cFF888888" .. (rec.level or "") .. " " .. (rec.rankName or "") .. "|r",
        right = LastOnline(rec) }
end

-- Which mains have their alts shown (this session)
GR.expanded = GR.expanded or {}

-- The roster with each main's alts under it: a main in the guild lists its
-- alts in the guild beneath it when expanded (+ / -). Searching for an alt
-- shows its main, opened at the alts that match.
function GR:GroupedLines(matched, q)
    local g, out = self:Guild(), {}
    local searching = q and q ~= ""
    -- Each group is listed under its main, or (no main in the guild) under
    -- its highest-ranked character
    local function MainOf(rec)
        local grp = rec.group and g.groups[rec.group]
        local lead = grp and self:GroupLead(g, grp)
        return lead and lead.name ~= rec.name and lead or nil
    end
    local isMatch, top, childMatches = {}, {}, {}
    for _, rec in ipairs(matched) do isMatch[rec.name] = true end
    for _, rec in ipairs(matched) do
        local main = MainOf(rec)
        if main then
            childMatches[main.name] = true
            if not isMatch[main.name] and not top[main.name] then top[main.name] = main end
        else
            top[rec.name] = rec
        end
    end
    -- A main counts as online when any of its characters is
    local function AltsOf(main)
        local grp = g.groups[main.group]
        local alts = {}
        for _, n in ipairs(grp and grp.members or {}) do
            local r = g.members[n]
            if r and n ~= main.name then alts[#alts + 1] = r end
        end
        table.sort(alts, RosterOrder)
        return alts
    end
    local list, altsOf, onAlt = {}, {}, {}
    for _, rec in pairs(top) do
        list[#list + 1] = rec
        local grp = rec.group and g.groups[rec.group]
        local lead, isMain = self:GroupLead(g, grp)
        if lead and lead.name == rec.name then
            altsOf[rec.name] = AltsOf(rec)
            if not isMain then altsOf[rec.name].noMain = true end
            for _, a in ipairs(altsOf[rec.name]) do if a.online and not onAlt[rec.name] then onAlt[rec.name] = a end end
        end
    end
    table.sort(list, function(a, b)
        if SortBy() == "rank" then
            local ao, bo = (a.online or onAlt[a.name]) and true or false, (b.online or onAlt[b.name]) and true or false
            if ao ~= bo then return ao end
        end
        return RosterOrder(a, b)
    end)
    for _, rec in ipairs(list) do
        local line = RosterLine(rec, g, 0)
        local alts = altsOf[rec.name]
        if alts and #alts > 0 then
            local open = self.expanded[rec.name] or (searching and childMatches[rec.name])
            line.toggle = open and "-" or "+"
            line.main = rec.name
            line.text = line.text .. " |cFF888888[" .. #alts .. (#alts == 1 and " alt" or " alts") .. "]|r"
                .. (alts.noMain and " |cFFFF8844(no main set)|r" or "")
            if not rec.online and onAlt[rec.name] then
                line.right = "|cFF33FF33on " .. GR.Short(onAlt[rec.name].name) .. "|r"
            end
            out[#out + 1] = line
            if open then
                for _, a in ipairs(alts) do
                    if not searching or isMatch[a.name] or isMatch[rec.name] then out[#out + 1] = RosterLine(a, g, 1) end
                end
            end
        else
            out[#out + 1] = line
        end
    end
    if #out == 0 then out[1] = { text = "|cFF888888Nobody here" .. (searching and " matching that" or "") .. ".|r" } end
    return out
end

-- Show or hide a main's alts
function GR:ToggleAlts(main)
    self.expanded[main] = not self.expanded[main] or nil
    self:RefreshList()
end

-- The lines the current tab lists: { text, right, rec?, color? }
function GR:TabLines()
    local g, out, q = self:Guild(), {}, self.searchText
    if not g then return { { text = "|cFF888888You're not in a guild.|r" } } end
    if self.tab == "roster" or self.tab == "former" then
        local list = {}
        local src = self.tab == "roster" and g.members or g.former
        for _, rec in pairs(src) do
            if Matches(rec, q) and (not self.bannedOnly or self.tab == "roster" or rec.ban.on)
               and (self.tab ~= "roster" or self:PassesFilter(rec, g)) then
                list[#list + 1] = rec
            end
        end
        if self.tab == "roster" and DB().groupAlts then
            return self:GroupedLines(list, q)
        elseif self.tab == "roster" then
            table.sort(list, RosterOrder)
        else
            table.sort(list, function(a, b) return (a.leftAt or 0) > (b.leftAt or 0) end)
        end
        for _, rec in ipairs(list) do out[#out + 1] = RosterLine(rec, g, 0) end
        if #out == 0 then out[1] = { text = "|cFF888888Nobody here" .. (q and q ~= "" and " matching that" or "") .. ".|r" } end
    elseif self.tab == "log" then
        for _, e in ipairs(g.log) do
            if not q or q == "" or e.text:lower():find(q:lower(), 1, true) then
                local c = GR.KINDS[e.kind] and GR.KINDS[e.kind][2] or { 1, 1, 1 }
                out[#out + 1] = { text = "|cFF888888" .. date("%d %b %H:%M", e.t) .. "|r  " .. e.text, color = c, wrap = true }
            end
        end
        if #out == 0 then out[1] = { text = "|cFF888888Nothing logged yet.|r" } end
    elseif self.tab == "sync" then
        local S = self.Sync
        local function Line(t) out[#out + 1] = { text = t } end
        if S.GRMRunning() then
            Line("|cFFFFAA00Guild Roster Manager is running on this character, so it does the syncing here;"
                .. " Roster Manager only listens to the roster.|r")
        end
        Line("Sync: " .. (DB().sync and "|cFF33FF33on|r" or "|cFFFF4444off|r") .. "   Ban list: "
            .. (DB().syncBans and "on" or "off") .. "   Custom notes: " .. (DB().syncCustom and "on" or "off"))
        Line("Guild Roster Manager release (patch day) in use: " .. S:PatchDay())
        Line("Edits sent: " .. (S.sent or 0) .. ", received: " .. (S.received or 0))
        Line(" ")
        Line("|cFFFFD100Guildmates sharing roster edits|r")
        local peers = S:Peers()
        if #peers == 0 then Line("|cFF888888Nobody yet. They announce themselves when they log in.|r") end
        for _, p in ipairs(peers) do
            local what = p.isWM and ("Watching Machine " .. tostring(p.ver):sub(3)) or ("Guild Roster Manager " .. tostring(p.ver))
            Line("  " .. GR.Short(p.name) .. "  |cFF888888" .. what .. "|r  "
                .. (p.ok and "|cFF33FF33syncing|r" or ("|cFFFF8844different release (" .. tostring(p.patchDay) .. ")|r")))
        end
    end
    return out
end

local function MakeRow(list, i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints(row)
    row.sel:SetColorTexture(1, 0.82, 0, 0.15)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -70, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    -- + / - beside a main: show or hide their alts
    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(14, 14)
    row.toggle:SetPoint("LEFT", 2, 0)
    row.toggle.label = row.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.toggle.label:SetPoint("CENTER", 0, 0)
    row.toggle:SetScript("OnClick", function(self)
        local r = self:GetParent()
        if r.main then GR:ToggleAlts(r.main) end
    end)
    row.toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Alts", 1, 1, 1)
        GameTooltip:AddLine("Show or hide this main's alts underneath them.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row.toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.toggle:Hide()
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self)
        if self.rec then GR.selected = self.rec.name; Refresh() end
    end)
    row:SetScript("OnEnter", function(self)
        if self.rec then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Colored(self.rec))
            for _, l in ipairs(GR:DetailLines(self.rec)) do GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1) end
            GameTooltip:Show()
        elseif self.full then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.full, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    list.rows[i] = row
    return row
end

function GR:RefreshList()
    if not panel or not panel:IsShown() then return end
    local list = panel.list
    local lines = self:TabLines()
    local h = list:GetHeight() or 0
    local visible = math.max(1, math.floor(h / ROW_H))
    local maxOffset = math.max(0, #lines - visible)
    list.offset = math.max(0, math.min(list.offset or 0, maxOffset))
    for i = 1, math.max(visible, #list.rows) do
        local row = MakeRow(list, i)
        local e = i <= visible and lines[i + list.offset]
        if e then
            row.rec, row.full = e.rec, e.wrap and e.text or nil
            row.main = e.main
            row.text:ClearAllPoints()
            if e.toggle then
                row.toggle.label:SetText(e.toggle)
                row.toggle:Show()
                row.text:SetPoint("LEFT", 18, 0)
            else
                row.toggle:Hide()
                row.text:SetPoint("LEFT", 4 + (e.indent or 0) * 18, 0)
            end
            row.text:SetPoint("RIGHT", -70, 0)
            row.text:SetText(e.text)
            local c = e.color
            if c then row.text:SetTextColor(c[1], c[2], c[3]) else row.text:SetTextColor(1, 1, 1) end
            row.right:SetText(e.right or "")
            if e.rec and e.rec.name == GR.selected then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.rec, row.full, row.main = nil, nil, nil
            row:Hide()
        end
    end
    for _, t in ipairs(panel.tabs) do
        if t.key == self.tab then t:LockHighlight() else t:UnlockHighlight() end
    end
    self:RefreshDetails()
    if panel.purgeButton then
        if self.CanPurge and self:CanPurge() then panel.purgeButton:Enable() else panel.purgeButton:Disable() end
    end
    local m, online, f = self:Counts()
    if panel.totalText then
        panel.totalText:SetText(string.format("%d members, %d online, %d former", m, online, f))
    end
end

-- The details pane
local DETAIL_BUTTONS = {
    { "Join date", function(r) GR:EditJoinDate(r.name) end },
    { "Promotion date", function(r) GR:EditPromoDate(r.name) end },
    { "Birthday", function(r) GR:EditBirthday(r.name) end },
    { "Custom note", function(r) GR:EditCustomNote(r.name) end },
    { "Add alt", function(r) GR:AskAddAlt(r.name) end },
    { "Remove from alts", function(r) GR:RemoveAlt(r.name); Refresh() end },
    { "Set as main", function(r)
        local g = GR:Guild()
        local grp = g and r.group and g.groups[r.group]
        if grp and grp.main == r.name then GR:UnsetMain(r.name) else GR:SetMain(r.name) end
        Refresh()
    end },
    { "Ban", function(r) if r.ban.on then GR:SetBan(r.name, false); Refresh() else GR:AskBan(r.name) end end },
    { "Promote", function(r) if GR:Promote(r.name) then Refresh() end end,
      tip = { "Promote", "Up one rank (needs the game's permission to promote, and a rank below yours)." } },
    { "Demote", function(r) if GR:Demote(r.name) then Refresh() end end,
      tip = { "Demote", "Down one rank (needs the game's permission to demote)." } },
    { "Show armory", function(r) GR:ShowArmory(r.name) end,
      tip = { "Show armory", "Their saved gear and talents for each spec, in ArmorySnap's browser. Also asks the guild for a"
          .. " newer scan. Needs ArmorySnap on." } },
}

function GR:RefreshDetails()
    local d = panel and panel.details
    if not d then return end
    local rec = self.selected and self:Find(self.selected)
    if not rec then
        d.title:SetText("|cFF888888Click a player for their details.|r")
        d.body:SetText("")
        for _, b in ipairs(d.buttons) do b:Hide() end
        return
    end
    d.title:SetText(Colored(rec) .. (self.Find and select(2, self:Find(rec.name)) and " |cFF888888(former member)|r" or ""))
    local lines = {}
    for _, l in ipairs(self:DetailLines(rec)) do lines[#lines + 1] = "|cFFAAAAAA" .. l[1] .. ":|r " .. l[2] end
    if rec.note and rec.note ~= "" then lines[#lines + 1] = "|cFFAAAAAANote:|r " .. rec.note end
    if rec.onote and rec.onote ~= "" then lines[#lines + 1] = "|cFFAAAAAAOfficer note:|r " .. rec.onote end
    d.body:SetText(table.concat(lines, "\n"))
    local g = self:Guild()
    local grp = g and rec.group and g.groups[rec.group]
    for i, b in ipairs(d.buttons) do
        local label = DETAIL_BUTTONS[i][1]
        if label == "Set as main" then label = (grp and grp.main == rec.name) and "Not a main" or "Set as main" end
        if label == "Ban" then label = rec.ban.on and "Unban" or "Ban" end
        b:SetText(label)
        local former = select(2, self:Find(rec.name))
        local usable = true
        if former and (i == 5 or i == 6 or i == 7) then usable = false end
        if i == 6 and not grp then usable = false end
        if label == "Show armory" then usable = GR.Armory() ~= nil end
        if label == "Promote" then usable = not former and GR.CanPromote and GR:CanPromote(rec) or false end
        if label == "Demote" then usable = not former and GR.CanDemote and GR:CanDemote(rec) or false end
        if usable then b:Enable() else b:Disable() end
        b:Show()
    end
end

local TABS = { { "roster", "Roster" }, { "log", "Log" }, { "former", "Former & bans" }, { "sync", "Sync" } }

function GR:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_GuildRosterFrame", title = "Roster Manager", titleColor = "66CCFF",
        width = 760, height = 500, minHeight = 340, scroll = false,
        resizable = { 640, 340, 1400, 1400 },
        onResize = function() GR:RefreshList() end,
        onRefresh = function() GR:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(24)
    panel.tabs = {}
    local x = 8
    for _, t in ipairs(TABS) do
        local b = top:Button({ text = t[2], width = t[1] == "former" and 110 or 80, onClick = function()
            GR.tab = t[1]; if panel.list then panel.list.offset = 0 end; GR:RefreshList()
        end }, x)
        b.key = t[1]
        panel.tabs[#panel.tabs + 1] = b
        x = x + (t[1] == "former" and 110 or 80) + 4
    end
    local search = top:EditBox({ label = "Search:", width = 130, maxLetters = 40,
        tooltip = { "Search", "Names, ranks, public and custom notes on the roster tabs; any text in the log." } }, x + 8)
    search.editBox:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        GR.searchText = strtrim(self:GetText() or "")
        if panel.list then panel.list.offset = 0 end
        GR:RefreshList()
    end)
    local view = L:Row(26)
    view:Dropdown({ label = "Sort:", width = 130, options = GR.SORTS,
        get = function() return DB().rosterSort or "rank" end,
        set = function(v) DB().rosterSort = v; if panel.list then panel.list.offset = 0 end; GR:RefreshList() end,
        tooltip = { "Sort the roster", "Online first then by rank, or by name, class, level, last online (most recent first) or join date (longest in the guild first)." } }, 8)
    view:Dropdown({ label = "Show:", width = 140, options = GR.FILTERS,
        get = function() return DB().rosterFilter or "all" end,
        set = function(v) DB().rosterFilter = v; if panel.list then panel.list.offset = 0 end; GR:RefreshList() end,
        tooltip = { "Show", "Everyone; only who's online; inactive (offline longer than Options' inactive days); no public note; mains; or characters in no alt group." } }, 250)
    local fill = L:Fill(200)
    local list = CreateFrame("Frame", nil, fill)
    list:SetPoint("TOPLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", -(DETAILS_W + 10), 0)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta * 3
        GR:RefreshList()
    end)
    list.rows = {}
    panel.list = list

    local d = CreateFrame("Frame", nil, fill, "BackdropTemplate")
    d:SetPoint("TOPRIGHT", 0, -2)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    d:SetWidth(DETAILS_W)
    if WM.SkinCard then WM:SkinCard(d, { 0.4, 0.8, 1 }); WM:RegisterSkinnedCard(d, { 0.4, 0.8, 1 }) end
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 10, -10)
    d.title:SetPoint("RIGHT", -10, 0)
    d.title:SetJustifyH("LEFT")
    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.body:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8)
    d.body:SetPoint("RIGHT", -10, 0)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    d.buttons = {}
    for i, spec in ipairs(DETAIL_BUTTONS) do
        local b = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        b:SetSize((DETAILS_W - 26) / 2, 20)
        local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
        if i == 9 or i == 10 then
            -- Promote / Demote: a row above the edit buttons
            col, rowN = i - 9, -1
        elseif i > 10 then
            -- Show armory: a full-width row above those
            b:SetWidth(DETAILS_W - 18)
            col, rowN = 0, -2
        end
        b:SetPoint("BOTTOMLEFT", 9 + col * ((DETAILS_W - 26) / 2 + 8), 10 + (3 - rowN) * 22)
        b:SetText(spec[1])
        if spec.tip then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(spec.tip[1], 1, 1, 1)
                GameTooltip:AddLine(spec.tip[2], nil, nil, nil, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        b:SetScript("OnClick", function()
            local rec = GR.selected and GR:Find(GR.selected)
            if rec then spec[2](rec) end
        end)
        d.buttons[i] = b
    end
    panel.details = d

    panel.totalText = panel:AddFooterText({ text = "" }, "LEFT")
    panel:AddFooterButton({ text = "Options", width = 80, onClick = function() GR:ToggleOptions() end }, "RIGHT")
    panel.purgeButton = panel:AddFooterButton({ text = "Purge", width = 70, onClick = function() GR:TogglePurge() end,
        tooltip = { "Purge inactive players", "Officers and up: list everyone whose main and alts have all been offline for a number of days, and remove them one click at a time." } }, "RIGHT")
    panel:AddFooterButton({ text = "Export", width = 64, onClick = function() GR:Command("export") end,
        tooltip = { "Export", "The roster (or, on Former & bans, former members) as CSV, to copy into a spreadsheet." } }, "RIGHT")
    panel:AddFooterButton({ text = "Ban by name", width = 100, onClick = function() GR:AskBanByName() end,
        tooltip = { "Ban by name", "Add someone to the ban list who isn't in the guild (or has left). You're warned if they join." } }, "RIGHT")
    panel:AddFooterButton({ text = "Scan now", width = 80, onClick = function() GR.AskRoster() end,
        tooltip = { "Scan now", "Asks the server for the roster now instead of waiting for the next scan." } }, "RIGHT")
    panel:HookScript("OnShow", function() GR.changedSinceView = false; GR.AskRoster() end)
    panel:Finish()
    return panel
end

function GR:RefreshUI()
    if panel and panel:IsShown() then self:RefreshList() end
    if options and options:IsShown() then options:Refresh() end
end
function GR:OnLogChanged() if panel and panel:IsShown() and self.tab == "log" then self:RefreshList() end end
function GR:OnScanned() self:RefreshUI() end
function GR:OnDataChanged() self:RefreshUI() end

function GR:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show(); self:RefreshList() end
end
GR.ToggleUI = GR.Toggle

function GR:ShowTab(tab)
    self.tab = tab
    local p = self:CreateUI()
    p:Show()
    self:RefreshList()
end

function GR:HideUI()
    if panel then panel:Hide() end
    if options then options:Hide() end
    if GR.HidePurge then GR:HidePurge() end
end

-- ============================================
-- OPTIONS (the window's Options button) AND THE GUIDED SETUP PAGE
-- ============================================

local function RankOptions(withEvery)
    local out = {}
    if withEvery then out[#out + 1] = { value = -1, text = "Every rank" } end
    local n = tonumber(GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    for i = 1, n do
        local name = GuildControlGetRankName and GuildControlGetRankName(i)
        if type(name) ~= "string" then name = "Rank " .. i end
        out[#out + 1] = { value = i - 1, text = name .. " and above" }
    end
    if #out == (withEvery and 1 or 0) then
        for i = 0, 9 do out[#out + 1] = { value = i, text = "Rank " .. i .. " and above" } end
    end
    return out
end

GR.RankOptions = RankOptions

local function Settings(L, inSetup)
    L:Checkbox({ label = "Show the log at login when something changed", get = function() return DB().showOnLogin end,
        set = function(v) DB().showOnLogin = v end,
        tooltip = { "Log at login", "Opens the window on the Log tab after you log in, if the first scan found joins, leaves, promotions or other changes since last time." } })
    L:Checkbox({ label = "Details when you hover the guild roster", get = function() return DB().hoverDetails end,
        set = function(v) DB().hoverDetails = v end,
        tooltip = { "Roster hover", "In the game's Guild window (O, Guild tab), hovering a member shows their join and promotion dates, alts, birthday, custom note and ban." } })
    L:Checkbox({ label = "List alts under their main on the roster", get = function() return DB().groupAlts end,
        set = function(v) DB().groupAlts = v; GR:RefreshList() end,
        tooltip = { "Alts under their main", "On the Roster tab, a main shows a + beside their name: click it to list their alts underneath them. Off lists everyone on their own, alts tagged (alt)." } })
    L:Checkbox({ label = "Say whose alt it is in log lines", get = function() return DB().nameMain end,
        set = function(v) DB().nameMain = v end,
        tooltip = { "Whose alt", "Log and chat lines about an alt end with their main, e.g. \"Myalt reached level 12. -- Venitra's alt\"." } })
    L:Checkbox({ label = "Report players back from a long absence", get = function() return DB().reportReturn end,
        set = function(v) DB().reportReturn = v end,
        tooltip = { "Back from inactive", "Logs a line when someone who'd been offline longer than the days below comes back online." } })
    L:Slider({ label = "Away this long counts as inactive (days)", min = 3, max = 60, step = 1, width = 220,
        get = function() return DB().inactiveDays end, set = function(v) DB().inactiveDays = v end })
    L:Slider({ label = "Report level-ups from level", min = 1, max = 70, step = 1, width = 220,
        get = function() return DB().levelMin end, set = function(v) DB().levelMin = v end,
        tooltip = { "Level-ups", "Level-ups below this level aren't logged." } })
    L:Header("Promotions")
    L:Note("Days at a rank before the log (and the roster's |cFFFFFF00Ready to promote|r filter) suggests the next rank up."
        .. " 0 or empty: never. Counted from their last promotion, or when they joined.")
    local nRanks = tonumber(GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    for idx = math.max(nRanks - 1, 1), 2, -1 do
        local rankIndex = idx
        L:EditBox({ label = function() return (GR.Tools and GR.Tools.RankName(GR:Guild(), rankIndex) or ("Rank " .. rankIndex)) .. ":" end,
            width = 50, numeric = true, maxLetters = 4, indent = 16,
            get = function() return tostring(DB().promoDays[rankIndex] or "") end,
            set = function(v) DB().promoDays[rankIndex] = tonumber(v) and tonumber(v) > 0 and tonumber(v) or nil end,
            tooltip = { "Days before a promotion", "After this many days at this rank, they're suggested for the next rank up." } })
    end
    L:Header("Join dates in notes")
    L:Dropdown({ label = "Stamp join dates into:", width = 140,
        options = { { value = "officer", text = "Officer notes" }, { value = "public", text = "Public notes" } },
        get = function() return DB().stampNote or "officer" end, set = function(v) DB().stampNote = v end,
        tooltip = { "Join date stamps", "\"Joined 15 Jan 26\" is added to the end of the note (when it fits in 31 characters and isn't there yet)." } })
    L:Checkbox({ label = "Stamp a new member's join date by itself", get = function() return DB().autoStamp end,
        set = function(v) DB().autoStamp = v end,
        tooltip = { "Stamp on join", "When someone joins, their join date goes into the note above (needs permission to edit those notes)." } })
    if not inSetup then
        L:Buttons({ { text = "Stamp everyone's join date now", width = 230, onClick = function() GR:Command("stamp") end,
            tooltip = { "Stamp now", "Every member with a known join date and no stamp yet gets one, a few a second." } } })
    end
    L:Header("Anniversaries and birthdays")
    L:Checkbox({ label = "Say guild anniversaries and birthdays on the day", get = function() return DB().anniversaries end,
        set = function(v) DB().anniversaries = v end,
        tooltip = { "Anniversaries", "\"Today is Bob's 2-year anniversary in the guild!\" and \"Happy birthday, Bob!\" in the log and your chat, once on the day (birthdays come from the member's details)." } })
    L:Checkbox({ label = "Also say them in guild chat", indent = 16, get = function() return DB().anniversaryGuild end,
        set = function(v) DB().anniversaryGuild = v end })
    L:Header("Sharing with your guild")
    L:Checkbox({ label = "Share edits with guildmates (Guild Roster Manager and Watching Machine)",
        get = function() return DB().sync end,
        set = function(v) DB().sync = v; if v and GR.Sync then GR.Sync:Hello() end end,
        tooltip = { "Sync", "Join and promotion dates, alts and mains, custom notes, birthdays and bans you edit are sent to guildmates running Guild Roster Manager or Watching Machine, and theirs come to you. The newest edit wins." } })
    L:Checkbox({ label = "Share the ban list", indent = 16, get = function() return DB().syncBans end,
        set = function(v) DB().syncBans = v end,
        tooltip = { "Ban list sync", "Bans are only sent to, and taken from, the ranks below." } })
    L:Checkbox({ label = "Share custom notes", indent = 16, get = function() return DB().syncCustom end,
        set = function(v) DB().syncCustom = v end })
    L:Dropdown({ label = "Take edits from:", width = 170, indent = 16, options = function() return RankOptions(true) end,
        get = function() return DB().syncRank or -1 end,
        set = function(v) DB().syncRank = (v ~= -1) and v or nil; if GR.Sync then GR.Sync:Announce() end end,
        tooltip = { "Take edits from", "Only edits made by players of this rank or higher are applied to your records." } })
    L:Dropdown({ label = "Ban list with:", width = 170, indent = 16, options = function() return RankOptions(false) end,
        get = function() return DB().banRank end,
        set = function(v) DB().banRank = v; if GR.Sync then GR.Sync:Announce() end end,
        tooltip = { "Ban list ranks", "Bans are shared only with, and taken only from, players of this rank or higher (usually officers)." } })
    if not inSetup then
        L:Buttons({ { text = "Import from Guild Roster Manager", width = 230,
            disabled = function() return not (GR.Sync and GR.Sync.GRMDataAvailable()) end,
            onClick = function()
                local m, f, g = GR.Sync:ImportFromGRM()
                if m then WM:Print(string.format("Imported %d members, %d former members and %d alt groups from Guild Roster Manager.", m, f, g)) end
                GR:RefreshUI()
            end,
            tooltip = { "Import", "Reads what Guild Roster Manager has saved for this guild (it must be installed and loaded): join and promotion dates, custom notes, birthdays, bans, alt groups and former members. Only newer data replaces what Roster Manager has." } } })
        L:Buttons({ { text = "Read alts from guild notes", width = 230,
            onClick = function() GR:Command("notes") end,
            tooltip = { "Alts from notes", "Reads every public and officer note for whose alt a character is (\"Venhana alt\", \"Venitra's Alt\", \"alt of Chojii\", \"Main: Chojii\") and makes that guild member their main, in the alt group they share or with the alt added to it. Never moves anyone out of a group with another main. Runs once by itself; use this after notes change." } } })
        L:Header("The log")
        L:Note("Which changes go into the log, and which are also printed in your chat:")
        for _, k in ipairs(GR.KIND_ORDER) do
            local row = L:Row(22)
            row:Text({ text = GR.KINDS[k][1] }, 16)
            row:Checkbox({ label = "Log", get = function() return DB().toLog[k] end, set = function(v) DB().toLog[k] = v end }, 160)
            row:Checkbox({ label = "Chat", get = function() return DB().toChat[k] end, set = function(v) DB().toChat[k] = v end }, 230)
        end
    end
end

function GR:ToggleOptions()
    if not options then
        options = WM.UI:CreatePanel({ name = "WM_GuildRosterOptions", title = "Roster Manager Options", titleColor = "66CCFF", width = 420 })
        Settings(options.layout)
        options:Finish()
    end
    if options:IsShown() then options:Hide() else options:Show(); options:Refresh() end
end

function GR:SetupPage(L)
    DB()
    L:Note("Keeps a record of everyone in your guild and everyone who has left, and logs every change to the roster.")
    L:Note("|cFFFFFFFFWhat it watches:|r every 30 seconds it compares the roster with what it saw last. Joins, rejoins"
        .. " (even under a new name), leaves and kicks (with who kicked), promotions and demotions (with who did it),"
        .. " level-ups, public and officer note changes and players back from a long absence go into the guild log.")
    L:Note("|cFFFFFFFFWhat it keeps for each member:|r join and promotion dates, their alts and main, a birthday,"
        .. " a custom note of up to 150 characters, and whether they're banned. A banned player who rejoins gets a red"
        .. " warning. Hover a name in the game's Guild window to see all of it.")
    L:Note("|cFFFFFFFFSharing:|r edits you make are shared with guildmates running Guild Roster Manager or Watching"
        .. " Machine, and theirs come to you, so officers see the same dates, alts and bans. If you already use Guild"
        .. " Roster Manager, Roster Manager can import what it knows.")
    L:Note("|cFFFFFFFFArmory:|r with ArmorySnap on, a member's details list their saved armory for each spec, and"
        .. " |cFFFFFF00Show armory|r opens their gear and talents. Your own gear is saved automatically, guildmates"
        .. " are saved when ArmorySnap inspects them, and guildmates running Watching Machine share theirs.")
    L:Note("|cFFFFFFFFPurge (officers and up):|r the |cFFFFFF00Purge|r button lists every player whose main and alts"
        .. " have all been offline at least the days below, never anyone at the protected ranks, you or your alts."
        .. " You untick anyone to keep and remove the rest one click at a time; each is checked again just before."
        .. " |cFFFFFF00Ignore|r on a player tags them and all their characters so purges never list them again.")
    L:Slider({ label = "Purge: offline at least (days)", min = 7, max = 365, step = 1, width = 220,
        get = function() return DB().purgeDays end, set = function(v) DB().purgeDays = v end,
        tooltip = { "Days offline", "Only players whose main and every alt have been offline at least this long are listed." } })
    L:Dropdown({ label = "Purge never removes:", width = 170, options = function() return RankOptions(false) end,
        get = function() return DB().purgeProtectRank end, set = function(v) DB().purgeProtectRank = v end,
        tooltip = { "Protected ranks", "Players with any character at this rank or higher are never listed." } })
    L:Note("|cFFFFFFFFOfficer tools:|r |cFFFFFF00Promote|r and |cFFFFFF00Demote|r in a member's details (one click each),"
        .. " promotion suggestions after the days you set per rank (the roster's |cFFFFFF00Ready to promote|r filter lists"
        .. " them), |cFFFFFF00Export|r of the roster as CSV, join dates stamped into notes, and anniversaries and birthdays"
        .. " said on the day. The roster sorts by rank, name, class, level, last online or join date, and filters to who's"
        .. " online, inactive, without a note, mains, or ready to promote.")
    L:Note("|cFFFFFFFFAlts from notes:|r the first scan reads public and officer notes like \"Venhana alt\" or"
        .. " \"Main: Chojii\" and sets those mains, so the Roster tab lists their alts under them. An alt group with"
        .. " no main yet is listed under its highest-ranked character, marked |cFFFF8844(no main set)|r.")
    Settings(L, true)
    L:Note("Everything else is in its window: |cFFFFFF00/wmachine roster|r.")
end

-- /wmachine roster [log|former|sync|scan|import|notes|purge|export|stamp|options]
function GR:Command(arg)
    arg = strtrim((arg or ""):lower())
    if arg == "log" or arg == "former" or arg == "sync" then self:ShowTab(arg)
    elseif arg == "bans" then self.bannedOnly = true; self:ShowTab("former")
    elseif arg == "scan" then GR.AskRoster(); WM:Print("Roster Manager: scanning.")
    elseif arg == "import" then
        local m, f, g = self.Sync:ImportFromGRM()
        if m then WM:Print(string.format("Imported %d members, %d former members and %d alt groups.", m, f, g))
        else WM:Print("Guild Roster Manager's data isn't loaded (it must be installed and enabled).") end
    elseif arg == "notes" or arg == "alts" then
        local n = self:AltsFromNotes()
        WM:Print(n > 0 and string.format("Roster Manager: guild notes named the main of %d character%s.", n, n == 1 and "" or "s")
            or "Roster Manager: no new alts or mains in the guild notes.")
        self:RefreshUI()
    elseif arg == "export" then
        local former = self.tab == "former"
        local csv, n = self:ExportCSV(former)
        WM.UI:ShowCopyText((former and "Former members: " or "Roster: ") .. n, csv)
    elseif arg == "stamp" then
        local n = self.Tools:StampAll()
        WM:Print("Roster Manager: stamping " .. n .. " join dates into " .. (DB().stampNote == "public" and "public" or "officer") .. " notes.")
    elseif arg == "purge" then
        if self:CanPurge() then self:TogglePurge()
        else WM:Print("Roster Manager: this character can't remove guild members.") end
    elseif arg == "options" or arg == "config" then self:ToggleOptions()
    else self:Toggle() end
end

-- After the first scan of a session: the log, if something changed
function GR:InitUI()
    self:HookGuildRoster()
    if hooksecurefunc and rawget(_G, "GuildFrame_Update") then
        hooksecurefunc("GuildFrame_Update", function() GR:HookGuildRoster() end)
    end
    WM.RunAfter(20, function()
        if WM:IsModuleOn("GuildRoster") and DB().showOnLogin and GR.changedSinceView then
            GR:ShowTab("log")
        end
    end)
end
