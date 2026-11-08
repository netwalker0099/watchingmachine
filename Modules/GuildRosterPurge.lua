-- Watching Machine: Roster Manager's purge
-- For players allowed to remove guild members (officers and up): finds
-- everyone whose characters have ALL been offline for at least a number of
-- days, checking each player's main and alts together, so nobody whose alt
-- was on yesterday is removed. You review the list, untick anyone to keep,
-- and remove them one click at a time (the game allows one removal per
-- click). Before each removal the player is checked again.

local AddonName, WM = ...
local GR = WM.GuildRoster
local Purge = {}
GR.Purge = Purge

local function DB() return GR.DB() end
local function On() return WM:IsModuleOn("GuildRoster") end

-- Can this character remove guild members at all?
function GR:CanPurge()
    if not On() or not (IsInGuild and IsInGuild()) then return false end
    local f = rawget(_G, "CanGuildRemove") or (C_GuildInfo and C_GuildInfo.CanGuildRemove)
    if not f then return false end
    local ok, v = pcall(f)
    return ok and v and true or false
end

local function MyRankIndex()
    local _, _, idx = GetGuildInfo and GetGuildInfo("player")
    return tonumber(idx) or 0
end

-- Days since any of these characters was online (0 if one is online now)
local function DaysOff(recs)
    local hours
    for _, r in ipairs(recs) do
        local h = r.online and 0 or (r.offlineHours or 0)
        if not hours or h < hours then hours = h end
    end
    return math.floor((hours or 0) / 24)
end
Purge.DaysOff = DaysOff

-- Everyone eligible: { lead = record, recs = { every character in the guild },
-- days = days since any of them was on }, longest away first.
-- days: offline at least this long; protect: never ranks at or above this index
function GR:PurgeCandidates(days, protect)
    local g = self:Guild()
    if not g then return {} end
    days = tonumber(days) or DB().purgeDays
    protect = tonumber(protect) or DB().purgeProtectRank
    local mine = g.members[GR.MyName()]
    local myGroup = mine and mine.group
    local myRank = MyRankIndex()
    local done, out = {}, {}
    for name, rec in pairs(g.members) do
        if not done[name] then
            local recs, lead = {}, rec
            local grp = rec.group and g.groups[rec.group]
            if grp then
                for _, n in ipairs(grp.members) do
                    local r = g.members[n]
                    if r then recs[#recs + 1] = r; done[n] = true end
                end
                lead = self:GroupLead(g, grp) or rec
            else
                recs[1] = rec
                done[name] = true
            end
            -- Kept: you and your alts, anyone online or recently on, protected
            -- ranks, and ranks you can't remove (yours and above)
            local keep = (myGroup and rec.group == myGroup) or name == GR.MyName()
            for _, r in ipairs(recs) do
                local ri = r.rankIndex or 99
                if r.name == GR.MyName() or ri <= protect or ri <= myRank then keep = true end
            end
            local off = DaysOff(recs)
            if not keep and off >= days then
                table.sort(recs, function(a, b)
                    if a.name == lead.name then return true end
                    if b.name == lead.name then return false end
                    return a.name < b.name
                end)
                out[#out + 1] = { lead = lead, recs = recs, days = off, keep = false, gone = {} }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.days ~= b.days then return a.days > b.days end
        return a.lead.name < b.lead.name
    end)
    return out
end

-- ============================================
-- REMOVING, ONE CLICK AT A TIME
-- ============================================

Purge.list = {}      -- the candidates found, with keep = true for those unticked
Purge.removed = 0

-- The next character to remove: { rec, entry } or nil
function Purge:Next()
    for _, e in ipairs(self.list) do
        if not e.keep and not e.skipped then
            for _, r in ipairs(e.recs) do
                if not e.gone[r.name] then return r, e end
            end
        end
    end
end

-- Remove the next character (from a click). Each player is checked again
-- first: if any of their characters has been on since, they're skipped.
function Purge:RemoveNext()
    if not GR:CanPurge() then
        WM:ModulePrint("GuildRoster", "You can't remove guild members on this character.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        WM:ModulePrint("GuildRoster", "Not in combat.")
        return false
    end
    local rec, e = self:Next()
    if not rec then return false end
    local g = GR:Guild()
    -- Someone came back, or was promoted out of reach: keep the whole player
    local still = GR:PurgeCandidates(self.days, self.protect)
    local stillIn = false
    for _, c in ipairs(still) do
        for _, r in ipairs(c.recs) do if r.name == rec.name then stillIn = true end end
    end
    if not g or not g.members[rec.name] or not stillIn then
        e.skipped = true
        WM:ModulePrint("GuildRoster", "Kept " .. GR.Short(e.lead.name) .. ": one of their characters has been on, or they're no longer removable.")
        if self.Refresh then self:Refresh() end
        return false
    end
    local short = GR.Short(rec.name)
    local target = GR.FullName(short) == rec.name and short or rec.name
    local f = rawget(_G, "GuildUninvite") or (C_GuildInfo and C_GuildInfo.Uninvite)
    if not f then return false end
    f(target)
    e.gone[rec.name] = true
    self.removed = self.removed + 1
    GR:Log("info", "Purged " .. short .. " (" .. e.days .. " days offline"
        .. (#e.recs > 1 and (", with " .. GR.Short(e.lead.name) .. "'s other characters") or "") .. ").", g)
    if self.Refresh then self:Refresh() end
    return true
end

-- Find who'd be removed
function Purge:Find(days, protect)
    self.days = tonumber(days) or DB().purgeDays
    self.protect = tonumber(protect) or DB().purgeProtectRank
    self.list = GR:PurgeCandidates(self.days, self.protect)
    self.removed = 0
    if self.Refresh then self:Refresh() end
    return self.list
end

function Purge:Counts()
    local players, chars = 0, 0
    for _, e in ipairs(self.list) do
        if not e.keep and not e.skipped then
            local left = 0
            for _, r in ipairs(e.recs) do if not e.gone[r.name] then left = left + 1 end end
            if left > 0 then players, chars = players + 1, chars + left end
        end
    end
    return players, chars
end

-- ============================================
-- THE WINDOW
-- ============================================

local panel
local ROW_H = 18

local function Colored(rec)
    local c = rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
    local hex = c and type(c.colorStr) == "string" and c.colorStr or "ffffffff"
    return "|c" .. hex .. GR.Short(rec.name) .. "|r"
end

local function RowText(e)
    local names = {}
    for i, r in ipairs(e.recs) do
        if i > 1 then names[#names + 1] = (e.gone[r.name] and "|cFF666666" .. GR.Short(r.name) .. " (removed)|r" or Colored(r)) end
    end
    local lead = e.recs[1]
    local t = (e.gone[lead.name] and "|cFF666666" .. GR.Short(lead.name) .. " (removed)|r" or Colored(lead))
        .. "  |cFF888888" .. (lead.rankName or "") .. "|r"
    if #names > 0 then t = t .. "  |cFF888888+|r " .. table.concat(names, ", ") end
    if e.skipped then t = t .. "  |cFF33FF33(kept: came back)|r" end
    return t
end

function Purge:Refresh()
    if not panel or not panel:IsShown() then return end
    local list = panel.list
    local h = list:GetHeight() or 0
    local visible = math.max(1, math.floor(h / ROW_H))
    list.offset = math.max(0, math.min(list.offset or 0, math.max(0, #self.list - visible)))
    for i = 1, math.max(visible, #list.rows) do
        local row = list.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, list)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(18, 18)
            row.check:SetPoint("LEFT", 0, 0)
            row.check:SetScript("OnClick", function(self)
                local e = row.entry
                if e then e.keep = not self:GetChecked() end
                Purge:Refresh()
            end)
            row.check:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Remove this player", 1, 1, 1)
                GameTooltip:AddLine("Ticked: all their characters listed here are removed. Untick to keep them.", nil, nil, nil, true)
                GameTooltip:Show()
            end)
            row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 22, 0)
            row.text:SetPoint("RIGHT", -60, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.days = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.days:SetPoint("RIGHT", -4, 0)
            list.rows[i] = row
        end
        local e = i <= visible and self.list[i + list.offset]
        row.entry = e or nil
        if e then
            row.check:SetChecked(not e.keep)
            row.text:SetText(RowText(e))
            row.days:SetText(e.days .. "d")
            row:Show()
        else
            row:Hide()
        end
    end
    local players, chars = self:Counts()
    local nextRec = self:Next()
    if panel.removeButton then
        panel.removeButton:SetText(nextRec and ("Remove " .. GR.Short(nextRec.name)) or "Nothing to remove")
        if nextRec and GR:CanPurge() then panel.removeButton:Enable() else panel.removeButton:Disable() end
    end
    if panel.status then
        if not GR:CanPurge() then
            panel.status:SetText("|cFFFF8844This character can't remove guild members.|r")
        elseif #self.list == 0 then
            panel.status:SetText("|cFF888888Click Find to list who'd be removed.|r")
        else
            panel.status:SetText(string.format("%d players, %d characters to remove; %d removed", players, chars, self.removed))
        end
    end
end

function GR:TogglePurge()
    if not panel then
        panel = WM.UI:CreatePanel({ name = "WM_GuildRosterPurge", title = "Purge inactive players", titleColor = "66CCFF",
            width = 560, height = 440, scroll = false, onRefresh = function() Purge:Refresh() end })
        local L = panel.layout
        L:Note("Lists players whose characters have |cFFFFFFFFall|r been offline at least this many days. A main and"
            .. " their alts count as one player: if any of them was on more recently, none of them is listed."
            .. " Untick anyone to keep, then click Remove once per character (the game allows one removal per click).")
        local row = L:Row(28)
        row:EditBox({ label = "Offline at least (days):", width = 50, numeric = true, maxLetters = 4,
            get = function() return tostring(DB().purgeDays) end,
            set = function(v) local n = tonumber(v); if n and n >= 1 then DB().purgeDays = math.floor(n) end end,
            tooltip = { "Days offline", "Only players whose main and every alt have been offline at least this long are listed." } }, 0)
        row:Dropdown({ label = "Never remove:", width = 160, options = function() return GR.RankOptions(false) end,
            get = function() return DB().purgeProtectRank end,
            set = function(v) DB().purgeProtectRank = v end,
            tooltip = { "Protected ranks", "Players with any character at this rank or higher are never listed. Ranks at or above yours can't be removed anyway." } }, 230)
        row = L:Row(26)
        row:Button({ text = "Find", width = 90, onClick = function() Purge:Find() end,
            tooltip = { "Find", "Lists who'd be removed, from the last roster scan (every 30 seconds)." } }, 0)
        local fill = L:Fill(160)
        local list = CreateFrame("Frame", nil, fill)
        list:SetAllPoints(fill)
        list:EnableMouseWheel(true)
        list:SetScript("OnMouseWheel", function(self, delta)
            self.offset = (self.offset or 0) - delta * 3
            Purge:Refresh()
        end)
        list.rows = {}
        panel.list = list
        panel.status = panel:AddFooterText({ text = "" }, "LEFT")
        panel.removeButton = panel:AddFooterButton({ text = "Remove", width = 170, onClick = function() Purge:RemoveNext() end,
            tooltip = { "Remove", "Removes the next ticked character from the guild. Click again for the next one." } }, "RIGHT")
        panel:Finish()
    end
    if panel:IsShown() then panel:Hide() else panel:Show(); Purge:Refresh() end
end

function GR:HidePurge() if panel then panel:Hide() end end
