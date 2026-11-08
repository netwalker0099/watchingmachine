-- Watching Machine: Loot Council windows
--   * The loot history window: every award (search, one player's), and a
--     Players tab (how many items each has had and their last award).
--   * A loot pane beside a player's armory in ArmorySnap's browser: their
--     whole loot history with the guild and how they won each item.
--   * LC:AddLootTooltip(tooltip, name, days): a player's recent loot, for the
--     roster, the voting frame and anything else.

local AddonName, WM = ...
local LC = WM.LootCouncil

local function On() return WM:IsModuleOn("LootCouncil") end
local function DB() return LC.DB() end

local ROW_H = 18

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and type(c.colorStr) == "string" and c.colorStr or "ffffffff"
end
local function Who(e)
    if e.de and not e.to then return "|cff999999Disenchanted|r" end
    return "|c" .. ClassHex(e.class) .. LC.Short(e.to) .. "|r"
end
local function ItemText(e)
    if e.link then return e.link end
    local name = e.itemID and WM.ItemName and WM.ItemName(e.itemID)
    return "|cffa335ee[" .. (name or ("Item " .. tostring(e.itemID))) .. "]|r"
end
LC.ItemText = ItemText

-- The tooltip lines for one award
function LC:AddEntryLines(tt, e)
    tt:AddDoubleLine("Won by", Who(e) .. "  " .. LC.HowText(e), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("When", date("%d %b %Y %H:%M", e.t or 0) .. "  (" .. LC.Ago(e.t) .. ")", 0.8, 0.8, 0.8, 1, 1, 1)
    if e.boss or e.zone then tt:AddDoubleLine("Where", (e.boss or "?") .. (e.zone and (", " .. e.zone) or ""), 0.8, 0.8, 0.8, 1, 1, 1) end
    if e.by then tt:AddDoubleLine("Awarded by", LC.Short(e.by), 0.8, 0.8, 0.8, 1, 1, 1) end
    if e.votes then tt:AddDoubleLine("Votes", tostring(e.votes), 0.8, 0.8, 0.8, 1, 1, 1) end
    if e.note and e.note ~= "" then tt:AddLine("Note: " .. e.note, 1, 1, 1, true) end
    if e.replaced then tt:AddDoubleLine("Replaced", e.replaced, 0.8, 0.8, 0.8) end
    if e.rolls and #e.rolls > 0 then
        local parts = {}
        for i, r in ipairs(e.rolls) do
            if i > 8 then break end
            parts[#parts + 1] = LC.Short(r.name) .. " " .. tostring(r.roll) .. (r.type and (" " .. r.type) or "")
        end
        tt:AddLine("Rolls: " .. table.concat(parts, ", "), 0.8, 0.8, 0.8, true)
    end
end

-- A player's loot in a tooltip: last award, then the last `days` days
function LC:AddLootTooltip(tt, name, days)
    if not On() then return end
    days = days or DB().recentDays
    local last = LC.LastLoot(name)
    tt:AddLine(" ")
    if not last then tt:AddLine("No loot from the guild yet.", 0.6, 0.6, 0.6) return end
    tt:AddDoubleLine("Last loot", LC.Ago(last.t), 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine(ItemText(last), LC.HowText(last))
    local recent = LC.Recent(name, days)
    tt:AddLine("Last " .. days .. " days: " .. #recent .. (#recent == 1 and " item" or " items"), 1, 0.82, 0)
    for i, e in ipairs(recent) do
        if i > 15 then tt:AddLine("...and " .. (#recent - 15) .. " more", 0.6, 0.6, 0.6) break end
        tt:AddDoubleLine(ItemText(e), LC.HowText(e) .. " |cff888888" .. date("%d %b", e.t or 0) .. "|r")
    end
end

-- ============================================
-- THE LOOT HISTORY WINDOW
-- ============================================

local panel
LC.tab = "all"
LC.player = nil         -- one player's loot on the All tab
LC.search = ""

local function Matches(e, q)
    if q == "" then return true end
    local name = e.link and e.link:match("%[(.-)%]") or (e.itemID and WM.ItemName and WM.ItemName(e.itemID)) or ""
    return name:lower():find(q, 1, true) or LC.Short(e.to or ""):lower():find(q, 1, true)
        or (e.how or ""):lower():find(q, 1, true) or (e.boss or ""):lower():find(q, 1, true)
end

-- Rows for the current tab: { cols = { ... }, entry?, player? }
function LC:Rows()
    local q = (self.search or ""):lower()
    local out = {}
    if self.tab == "players" then
        for _, p in ipairs(LC.Players()) do
            if q == "" or LC.Short(p.key):lower():find(q, 1, true) then
                out[#out + 1] = { player = p.key, cols = {
                    "|c" .. ClassHex(p.last.class) .. LC.Short(p.key) .. "|r",
                    p.count .. (p.count == 1 and " item" or " items"),
                    ItemText(p.last), LC.Ago(p.last.t), "" } }
            end
        end
    else
        local only = self.player and LC.Resolve(self.player)
        for _, e in ipairs(LC.All(function(e) return (not only or e.to == only) and Matches(e, q) end)) do
            out[#out + 1] = { entry = e, cols = { date("%d %b %y", e.t or 0), ItemText(e), Who(e), LC.HowText(e), e.boss or "" } }
        end
    end
    return out
end

local COLS = { { 64 }, { 230 }, { 100 }, { 120 }, { 0 } }   -- widths; the last fills

local function MakeRow(list, i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.cols = {}
    local x = 4
    for c, spec in ipairs(COLS) do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        if spec[1] > 0 then fs:SetWidth(spec[1] - 6) else fs:SetPoint("RIGHT", -4, 0) end
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.cols[c] = fs
        x = x + spec[1]
    end
    row:SetScript("OnClick", function(self)
        if self.player then
            LC:ShowPlayer(self.player)
        elseif self.entry and self.entry.to then
            LC:ShowPlayer(self.entry.to)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e then
            if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:AddLine(ItemText(e)) end
            LC:AddEntryLines(GameTooltip, e)
            GameTooltip:AddLine("Click: this player's loot", 0.5, 0.5, 0.5)
        elseif self.player then
            GameTooltip:AddLine(LC.Short(self.player))
            LC:AddLootTooltip(GameTooltip, self.player)
            GameTooltip:AddLine("Click: their loot", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    list.rows[i] = row
    return row
end

function LC:RefreshList()
    if not panel or not panel:IsShown() then return end
    local list = panel.list
    local rows = self:Rows()
    local visible = math.max(1, math.floor((list:GetHeight() or 0) / ROW_H))
    list.offset = math.max(0, math.min(list.offset or 0, math.max(0, #rows - visible)))
    for i = 1, math.max(visible, #list.rows) do
        local row = MakeRow(list, i)
        local r = i <= visible and rows[i + list.offset]
        if r then
            row.entry, row.player = r.entry, r.player
            for c, fs in ipairs(row.cols) do fs:SetText(r.cols[c] or "") end
            row:Show()
        else
            row.entry, row.player = nil, nil
            row:Hide()
        end
    end
    for _, t in ipairs(panel.tabs) do
        if t.key == self.tab then t:LockHighlight() else t:UnlockHighlight() end
    end
    if self.tab == "all" and self.player then
        local last = LC.LastLoot(self.player)
        LC.headingText = LC.Short(LC.Resolve(self.player)) .. "'s loot: " .. #rows .. " items"
            .. (last and ("  |cff888888last loot " .. LC.Ago(last.t) .. "|r") or "") .. "   |cff888888(All loot shows everyone)|r"
    elseif self.tab == "all" then
        LC.headingText = "All loot awarded: " .. #rows .. " items"
    else
        LC.headingText = #rows .. " players have had loot"
    end
    if panel.heading then panel.heading:SetText(LC.headingText) end
end

function LC:ShowPlayer(name)
    self.tab, self.player, self.search = "all", name and LC.Resolve(name) or nil, ""
    local p = self:CreateUI()
    if p.searchBox then p.searchBox.editBox:SetText("") end
    p.list.offset = 0
    if not p:IsShown() then p:Show() end
    self:RefreshList()
end

function LC:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_LootCouncilFrame", title = "Loot Council: loot history", titleColor = "FFB347",
        width = 720, height = 480, minHeight = 300, scroll = false,
        resizable = { 600, 300, 1400, 1400 },
        onResize = function() LC:RefreshList() end,
        onRefresh = function() LC:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(24)
    panel.tabs = {}
    local x = 0
    for _, t in ipairs({ { "all", "All loot" }, { "players", "Players" } }) do
        local b = top:Button({ text = t[2], width = 90, onClick = function()
            LC.tab = t[1]
            if t[1] == "all" then LC.player = nil end
            panel.list.offset = 0
            LC:RefreshList()
        end }, x)
        b.key = t[1]
        panel.tabs[#panel.tabs + 1] = b
        x = x + 94
    end
    panel.searchBox = top:EditBox({ label = "Search:", width = 160, maxLetters = 40,
        tooltip = { "Search", "Item, player, how it was won or boss." } }, x + 10)
    panel.searchBox.editBox:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        LC.search = strtrim(self:GetText() or "")
        panel.list.offset = 0
        LC:RefreshList()
    end)
    local head = L:Row(20)
    panel.heading = head:Text({ text = function() return LC.headingText or "" end }, 0)
    local fill = L:Fill(160)
    local list = CreateFrame("Frame", nil, fill)
    list:SetAllPoints(fill)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta * 3
        LC:RefreshList()
    end)
    list.rows = {}
    panel.list = list
    panel.count = panel:AddFooterText({ text = function()
        local n = 0
        for _, e in pairs(DB().history) do if not e.deleted then n = n + 1 end end
        return n .. " awards" .. (DB().lastImport and ("  |cff888888imported " .. LC.Ago(DB().lastImport) .. "|r") or "")
    end }, "LEFT")
    panel:AddFooterButton({ text = "Import now", width = 100, onClick = function() LC:Command("import") end,
        tooltip = { "Import now", "Adds new awards from Gargul and RCLootCouncil (their saved history, when they're installed). Each award is added once; the same award recorded by both is merged." } }, "RIGHT")
    panel:Finish()
    return panel
end

function LC:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show(); self:RefreshList() end
end
LC.ToggleUI = LC.Toggle

-- ============================================
-- THE LOOT PANE BESIDE A PLAYER'S ARMORY
-- ============================================

local pane

local function PaneRow(i)
    local row = pane.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, pane.list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", pane.list, "RIGHT", 0, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.item:SetPoint("LEFT", 2, 0)
    row.item:SetWidth(150)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)
    row.how = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.how:SetPoint("LEFT", 156, 0)
    row.how:SetPoint("RIGHT", -2, 0)
    row.how:SetJustifyH("LEFT")
    row.how:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.entry.link then GameTooltip:SetHyperlink(self.entry.link) else GameTooltip:AddLine(ItemText(self.entry)) end
        LC:AddEntryLines(GameTooltip, self.entry)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane.rows[i] = row
    return row
end

function LC:RefreshPane()
    if not pane or not pane:IsShown() then return end
    local list = LC.ForPlayer(pane.key)
    local last = LC.LastLoot(pane.key)
    pane.title:SetText("Loot with the guild: " .. #list)
    pane.last:SetText(last and ("Last loot " .. LC.Ago(last.t) .. ": " .. ItemText(last)) or "|cff888888No loot from the guild yet.|r")
    local visible = math.max(1, math.floor((pane.list:GetHeight() or 0) / ROW_H))
    pane.offset = math.max(0, math.min(pane.offset or 0, math.max(0, #list - visible)))
    for i = 1, math.max(visible, #pane.rows) do
        local row = PaneRow(i)
        local e = i <= visible and list[i + pane.offset]
        if e then
            row.entry = e
            row.item:SetText(ItemText(e))
            row.how:SetText(LC.HowText(e) .. " |cff888888" .. date("%d %b %y", e.t or 0) .. "|r")
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

-- ArmorySnap shows a player: show their loot beside it
function LC:ShowPane(key, frame)
    if not On() or not DB().showInArmory or not key or not frame then
        if pane then pane:Hide() end
        return
    end
    if not pane then
        pane = CreateFrame("Frame", "WM_LootCouncilPane", frame, "BackdropTemplate")
        pane:SetWidth(300)
        if WM.SkinCard then WM:SkinCard(pane, { 1, 0.7, 0.28 }); WM:RegisterSkinnedCard(pane, { 1, 0.7, 0.28 }) end
        pane.title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pane.title:SetPoint("TOPLEFT", 10, -10)
        pane.last = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pane.last:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 0, -4)
        pane.last:SetPoint("RIGHT", -10, 0)
        pane.last:SetJustifyH("LEFT")
        pane.last:SetWordWrap(false)
        pane.list = CreateFrame("Frame", nil, pane)
        pane.list:SetPoint("TOPLEFT", 8, -46)
        pane.list:SetPoint("BOTTOMRIGHT", -8, 30)
        pane.list:EnableMouseWheel(true)
        pane.list:SetScript("OnMouseWheel", function(_, delta)
            pane.offset = (pane.offset or 0) - delta * 3
            LC:RefreshPane()
        end)
        pane.rows = {}
        local all = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
        all:SetSize(140, 20)
        all:SetPoint("BOTTOM", 0, 6)
        all:SetText("In the loot history")
        all:SetScript("OnClick", function() LC:ShowPlayer(pane.key) end)
        pane:SetScript("OnShow", function() LC:RefreshPane() end)
    end
    pane:ClearAllPoints()
    pane:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
    pane:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 2, 0)
    if pane.key ~= key then pane.offset = 0 end
    pane.key = key
    pane:Show()
    self:RefreshPane()
end

function LC:InitUI()
    local AS = WM.modules.ArmorySnap
    if AS and AS.OnMemberShown and not self.armoryHooked then
        self.armoryHooked = true
        AS.OnMemberShown(function(key, frame) LC:ShowPane(key, frame) end)
    end
    LC.OnChange(function()
        LC:RefreshList()
        LC:RefreshPane()
    end)
end

function LC:HideUI()
    if panel then panel:Hide() end
    if pane then pane:Hide() end
end


-- ============================================
-- COMMANDS, SETUP
-- ============================================

-- /wmachine council [history|players|import|vote|test [n]|endtest|<name>]
function LC:Command(arg)
    arg = strtrim(arg or "")
    local low = arg:lower()
    if low:match("^test") then
        if LC.RC:StartTest(tonumber(low:match("^test%s+(%d+)"))) then
            WM:ModulePrint("LootCouncil", "Local test session: answer in the response frame and vote in the voting frame."
                .. " Nothing is sent to anyone. |cFFFFFF00/wmachine council endtest|r ends it.")
            LC:ShowVoting()
        end
    elseif low == "endtest" then
        LC.RC:EndTest()
    elseif low == "vote" or low == "voting" then
        LC:ShowVoting()
    elseif low == "" or low == "history" then
        self.tab, self.player = "all", nil
        self:Toggle()
    elseif low == "players" then
        self.tab, self.player = "players", nil
        local p = self:CreateUI()
        if not p:IsShown() then p:Show() end
        self:RefreshList()
    elseif low == "import" then
        local n = self:ImportRCLC() + self:ImportGargul()
        DB().lastImport = time()
        WM:ModulePrint("LootCouncil", n > 0 and ("Added " .. n .. " awards to the loot history.")
            or "Nothing new in Gargul's or RCLootCouncil's history (they must be installed and enabled).")
        self:RefreshList()
    else
        self:ShowPlayer(arg)
    end
end

function LC:SetupPage(L)
    local db = DB()
    L:Note("Keeps the guild's loot history: every item awarded, to whom, and how it was won (Need, Greed, Minor"
        .. " Upgrade, off-spec, soft reserve, disenchant).")
    L:Note("|cFFFFFFFFWhere it comes from:|r what Gargul and RCLootCouncil have already saved on this account is added"
        .. " at login (only new awards; an award both recorded becomes one), and every award a master looter running"
        .. " RCLootCouncil logs during a raid is added as it happens.")
    L:Note("|cFFFFFFFFRaiding with RCLootCouncil:|r when the master looter (RCLootCouncil or Watching Machine) sends"
        .. " loot, the response frame shows each item, the gear it would replace and the master looter's buttons"
        .. " (Need, Greed, Minor Upgrade...) plus Pass, with a note. On the council, the voting frame shows everyone's"
        .. " answer, item level, gear, votes and notes, and each candidate's |cFFFFFFFFlast loot|r; hover a candidate"
        .. " for their loot of the last 30 days. |cFFFFFF00/wmachine council test|r runs a local test session"
        .. " (nothing is sent). With RCLootCouncil itself enabled on this character, it does the answering and"
        .. " voting, and we only record its awards.")
    L:Note("|cFFFFFFFFTwo views:|r |cFFFFFF00/wmachine council|r lists all loot ever awarded (search by item, player,"
        .. " how or boss; the Players tab shows each player's count and last loot). Click a player for all of their"
        .. " loot. In ArmorySnap's browser, a player's armory has their loot beside it, with the time since their last"
        .. " award.")
    L:Checkbox({ label = "Add new awards from Gargul and RCLootCouncil at login", get = function() return db.autoImport end,
        set = function(v) db.autoImport = v end,
        tooltip = { "Import at login", "Reads Gargul's and RCLootCouncil's saved loot history when you log in and adds any award not already here." } })
    L:Checkbox({ label = "Show a player's loot beside their armory", get = function() return db.showInArmory end,
        set = function(v) db.showInArmory = v end,
        tooltip = { "Loot beside the armory", "In ArmorySnap's browser, a pane beside the paper doll lists the player's loot with the guild." } })
    L:Checkbox({ label = "Take part in RCLootCouncil loot sessions", get = function() return db.rcTalk ~= false end,
        set = function(v) db.rcTalk = v end,
        tooltip = { "RCLootCouncil sessions", "Answer the master looter's loot and vote on the council, in RCLootCouncil's own messages. Off: only record awards." } })
    L:Checkbox({ label = "Show the response frame for loot sent to the raid", indent = 16, get = function() return db.showResponse end,
        set = function(v) db.showResponse = v end,
        tooltip = { "Response frame", "Each item the master looter sends, with a button for each answer and a note." } })
    L:Checkbox({ label = "Open the voting frame when I'm on the council", indent = 16, get = function() return db.openVoting end,
        set = function(v) db.openVoting = v end,
        tooltip = { "Voting frame", "Opens when a session starts and you're on the master looter's council. /wmachine council vote opens it any time." } })
    L:Slider({ label = "Recent loot covers (days)", min = 7, max = 90, step = 1, width = 220,
        get = function() return db.recentDays end, set = function(v) db.recentDays = v end,
        tooltip = { "Recent loot", "How far back tooltips list a player's loot (the roster, and later the voting frame)." } })
end
