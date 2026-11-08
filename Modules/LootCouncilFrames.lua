-- Watching Machine: Loot Council's session frames
--   * The response frame: each item the master looter sent, the gear it
--     would replace, a button for each answer (Need, Greed, Minor Upgrade...
--     as the master looter set them) plus Pass, and a note.
--   * The voting frame (council): every candidate's answer, item level,
--     the gear they'd replace, votes, note and roll, as in RCLootCouncil,
--     plus their LAST LOOT from the guild (item and how long ago). Hovering
--     a candidate lists their loot of the last 30 days.

local AddonName, WM = ...
local LC = WM.LootCouncil
local RC = LC.RC

local function On() return WM:IsModuleOn("LootCouncil") end
local function DB() return LC.DB() end

local ROW_H = 20

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and type(c.colorStr) == "string" and c.colorStr or "ffffffff"
end
local function Hex(c) return string.format("|cff%02x%02x%02x", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255) end
local function ItemTip(owner, link)
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

-- ============================================
-- THE RESPONSE FRAME
-- ============================================

local resp
local MAX_ITEMS = 6

local function Unanswered()
    local out = {}
    local s = RC.session
    for ses, item in pairs(s and s.items or {}) do
        if not item.answered and not item.awarded then out[#out + 1] = item end
    end
    table.sort(out, function(a, b) return a.session < b.session end)
    return out
end

local function RespondRow(i)
    local row = resp.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, resp.body)
    row:SetHeight(58)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 62)
    row:SetPoint("RIGHT", resp.body, "RIGHT", 0, 0)
    row.icon = CreateFrame("Button", nil, row)
    row.icon:SetSize(40, 40)
    row.icon:SetPoint("TOPLEFT", 2, -2)
    row.icon.tex = row.icon:CreateTexture(nil, "ARTWORK")
    row.icon.tex:SetAllPoints()
    row.icon:SetScript("OnEnter", function(self) ItemTip(self, row.item and row.item.link) end)
    row.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.info:SetPoint("RIGHT", -8, 0)
    row.info:SetJustifyH("LEFT")
    row.info:SetWordWrap(false)
    row.buttons = {}
    row.note = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.note:SetSize(110, 18)
    row.note:SetAutoFocus(false)
    row.note:SetMaxLetters(100)
    row.note:SetPoint("BOTTOMRIGHT", -6, 2)
    row.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.noteLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.noteLabel:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row.noteLabel:SetText("Note:")
    resp.rows[i] = row
    return row
end

function LC:RefreshResponse()
    if not resp then return end
    local items = Unanswered()
    if #items == 0 or not DB().showResponse then resp:Hide() return end
    if not resp:IsShown() then resp:Show() end
    for i = 1, math.max(#items, #resp.rows) do
        local item = i <= MAX_ITEMS and items[i]
        local row = item and RespondRow(i) or resp.rows[i]
        if item then
            row.item = item
            row.icon.tex:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(item.link or "?")
            local g1, g2, diff = RC:GearFor(item)
            local gear = g1 and ("  replaces " .. g1 .. (g2 and (" / " .. g2) or "")) or ""
            row.info:SetText((item.ilvl and ("ilvl " .. item.ilvl) or "") .. (diff and (" (" .. (diff >= 0 and "+" or "") .. diff .. ")") or "")
                .. (item.boss and ("  |cff888888" .. item.boss .. "|r") or "") .. gear)
            local specs = RC:Buttons(item.typeCode)
            specs[#specs + 1] = { text = PASS or "Pass", pass = true }
            for b, spec in ipairs(specs) do
                local btn = row.buttons[b]
                if not btn then
                    btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    btn:SetHeight(20)
                    row.buttons[b] = btn
                end
                btn:SetWidth(math.max(60, math.min(110, #spec.text * 7 + 16)))
                btn:ClearAllPoints()
                if b == 1 then btn:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -16)
                else btn:SetPoint("LEFT", row.buttons[b - 1], "RIGHT", 4, 0) end
                btn:SetText(spec.text)
                btn:SetScript("OnClick", function()
                    local note = strtrim(row.note:GetText() or "")
                    if spec.requireNotes and note == "" then
                        WM:ModulePrint("LootCouncil", "This answer needs a note.")
                        row.note:SetFocus()
                        return
                    end
                    RC:Respond(item.session, spec.pass and "PASS" or b, note)
                    row.note:SetText("")
                end)
                btn:Show()
            end
            for b = #specs + 1, #row.buttons do row.buttons[b]:Hide() end
            row:Show()
        elseif row then
            row.item = nil
            row:Hide()
        end
    end
    resp:SetHeight(70 + math.min(#items, MAX_ITEMS) * 62)
end

-- The master looter's time limit
local function TimerTick(self, elapsed)
    local s = RC.session
    local limit = RC.mldb and RC.mldb.timeout
    if limit == nil then limit = 60 end
    if not s or not limit or limit == false then self.bar:Hide() return end
    self.bar:Show()
    local left = limit - (time() - (s.started or time()))
    self.bar:SetMinMaxValues(0, limit)
    self.bar:SetValue(math.max(0, left))
    self.bar.text:SetText(left > 0 and ("Time left: " .. math.ceil(left) .. "s") or "Time's up")
    if left <= 0 then
        for _, item in ipairs(Unanswered()) do RC:Respond(item.session, "TIMEOUT") end
    end
end

function LC:CreateResponseFrame()
    if resp then return resp end
    resp = CreateFrame("Frame", "WM_LootResponseFrame", UIParent, "BackdropTemplate")
    resp:SetSize(560, 140)
    resp:SetPoint("TOP", 0, -140)
    resp:SetFrameStrata("DIALOG")
    resp:SetMovable(true)
    resp:EnableMouse(true)
    resp:RegisterForDrag("LeftButton")
    resp:SetScript("OnDragStart", resp.StartMoving)
    resp:SetScript("OnDragStop", resp.StopMovingOrSizing)
    if WM.SkinCard then WM:SkinCard(resp, { 1, 0.7, 0.28 }); WM:RegisterSkinnedCard(resp, { 1, 0.7, 0.28 }) end
    local title = resp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Loot Council: what do you want?")
    resp.bar = CreateFrame("StatusBar", nil, resp)
    resp.bar:SetSize(180, 12)
    resp.bar:SetPoint("TOPRIGHT", -12, -10)
    resp.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    resp.bar:SetStatusBarColor(1, 0.7, 0.28)
    resp.bar.text = resp.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resp.bar.text:SetPoint("CENTER")
    resp.body = CreateFrame("Frame", nil, resp)
    resp.body:SetPoint("TOPLEFT", 10, -32)
    resp.body:SetPoint("BOTTOMRIGHT", -10, 10)
    resp.rows = {}
    resp:SetScript("OnUpdate", TimerTick)
    resp:Hide()
    return resp
end

-- ============================================
-- THE VOTING FRAME
-- ============================================

local vote
LC.voteSession = 1

local COLS = {
    { key = "name", title = "Name", w = 110 }, { key = "rank", title = "Rank", w = 80 },
    { key = "response", title = "Response", w = 130 }, { key = "ilvl", title = "ilvl", w = 40 },
    { key = "diff", title = "Diff", w = 38 }, { key = "gear", title = "Gear", w = 44 },
    { key = "votes", title = "Votes", w = 40 }, { key = "vote", title = "", w = 62 },
    { key = "note", title = "Note", w = 34 }, { key = "roll", title = "Roll", w = 34 },
    { key = "last", title = "Last loot", w = 0 },
}

-- The candidates for an item, sorted as RCLootCouncil does: by answer, then votes
function LC:VoteRows(ses)
    local s = RC.session
    local item = s and s.items[ses]
    local list = {}
    for _, c in pairs(s and s.candidates[ses] or {}) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        local ra = RC:Response(item and item.typeCode, a.response).sort or 999
        local rb = RC:Response(item and item.typeCode, b.response).sort or 999
        if ra ~= rb then return ra < rb end
        if (a.votes or 0) ~= (b.votes or 0) then return (a.votes or 0) > (b.votes or 0) end
        return a.name < b.name
    end)
    return list
end

local function GearButton(row, i)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(18, 18)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b:SetScript("OnEnter", function(self) ItemTip(self, self.link) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function CandidateTip(owner, c)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|c" .. ClassHex(c.class) .. LC.Short(c.name) .. "|r")
    if c.note and c.note ~= "" then GameTooltip:AddLine("Note: " .. c.note, 1, 1, 1, true) end
    local voters = {}
    for v in pairs(c.voters or {}) do voters[#voters + 1] = LC.Short(v) end
    if #voters > 0 then GameTooltip:AddLine("Voted for by: " .. table.concat(voters, ", "), 0.8, 0.8, 0.8, true) end
    LC:AddLootTooltip(GameTooltip, c.name, DB().recentDays)
    GameTooltip:Show()
end

local function VoteRow(i)
    local row = vote.list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, vote.list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", vote.list, "RIGHT", 0, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.cells = {}
    local x = 4
    for _, col in ipairs(COLS) do
        if col.key == "gear" then
            row.g1 = GearButton(row); row.g1:SetPoint("LEFT", x, 0)
            row.g2 = GearButton(row); row.g2:SetPoint("LEFT", x + 20, 0)
        elseif col.key == "vote" then
            row.voteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.voteBtn:SetSize(col.w - 4, 18)
            row.voteBtn:SetPoint("LEFT", x, 0)
            row.voteBtn:SetScript("OnClick", function()
                local c = row.cand
                if not c then return end
                if c.voters[LC.Key(UnitName("player"))] then RC:Vote(LC.voteSession, c.name, -1)
                else RC:Vote(LC.voteSession, c.name, 1) end
            end)
        else
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x, 0)
            if col.w > 0 then fs:SetWidth(col.w - 4) else fs:SetPoint("RIGHT", -4, 0) end
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[col.key] = fs
        end
        x = x + col.w
    end
    row:SetScript("OnEnter", function(self) if self.cand then CandidateTip(self, self.cand) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    vote.list.rows[i] = row
    return row
end

local function SessionButton(i)
    local b = vote.sessions[i]
    if b then return b end
    b = CreateFrame("Button", nil, vote.side)
    b:SetSize(36, 36)
    b:SetPoint("TOPLEFT", 2, -(i - 1) * 40)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(18, 18)
    b.check:SetPoint("BOTTOMRIGHT", 2, -2)
    b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetAllPoints()
    b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.sel:SetBlendMode("ADD")
    b:SetScript("OnClick", function(self) LC.voteSession = self.session; LC:RefreshVoting() end)
    b:SetScript("OnEnter", function(self) ItemTip(self, self.link) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    vote.sessions[i] = b
    return b
end

function LC:RefreshVoting()
    if not vote or not vote:IsShown() then return end
    local s = RC.session
    if not s then
        vote.head:SetText("|cff888888No loot session.|r")
        vote.sub:SetText("")
        for _, r in ipairs(vote.list.rows) do r:Hide() end
        for _, b in ipairs(vote.sessions) do b:Hide() end
        return
    end
    local sesList = {}
    for ses in pairs(s.items) do sesList[#sesList + 1] = ses end
    table.sort(sesList)
    if not s.items[LC.voteSession] then LC.voteSession = sesList[1] end
    for i, ses in ipairs(sesList) do
        local b = SessionButton(i)
        local item = s.items[ses]
        b.session, b.link = ses, item.link
        b.tex:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.check:SetShown(item.awarded ~= nil)
        b.sel:SetShown(ses == LC.voteSession)
        b:Show()
    end
    for i = #sesList + 1, #vote.sessions do vote.sessions[i]:Hide() end
    local item = s.items[LC.voteSession]
    vote.head:SetText((item.link or "?") .. (item.ilvl and ("  |cffffffffilvl " .. item.ilvl .. "|r") or ""))
    vote.sub:SetText((item.boss and (item.boss .. "   ") or "") .. "Master looter: " .. LC.Short(s.ml)
        .. (item.awarded and ("   |cff33ff33Awarded to " .. LC.Short(item.awarded) .. "|r") or ""))
    local rows = self:VoteRows(LC.voteSession)
    local visible = math.max(1, math.floor((vote.list:GetHeight() or 0) / ROW_H))
    vote.list.offset = math.max(0, math.min(vote.list.offset or 0, math.max(0, #rows - visible)))
    local me = LC.Key(UnitName("player"))
    local council = RC:IsCouncil()
    for i = 1, math.max(visible, #vote.list.rows) do
        local c = i <= visible and rows[i + vote.list.offset]
        local row = c and VoteRow(i) or vote.list.rows[i]
        if c then
            row.cand = c
            local r = RC:Response(item.typeCode, c.response)
            row.cells.name:SetText("|c" .. ClassHex(c.class) .. LC.Short(c.name) .. "|r")
            row.cells.rank:SetText(c.rank or RC.ranks[c.name] or "")
            row.cells.response:SetText(Hex(r.color or { 1, 1, 1 }) .. (r.text or tostring(c.response)) .. "|r")
            row.cells.ilvl:SetText(c.ilvl and tostring(math.floor(c.ilvl + 0.5)) or "")
            local d = tonumber(c.diff)
            row.cells.diff:SetText(d and ((d > 0 and "|cff33ff33+" or d < 0 and "|cffff3333" or "|cff888888") .. d .. "|r") or "")
            for gi, g in ipairs({ row.g1, row.g2 }) do
                local link = gi == 1 and c.gear1 or c.gear2
                g.link = link
                local tex = link and select(10, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link))
                g.tex:SetTexture(tex or (link and "Interface\\Icons\\INV_Misc_QuestionMark") or nil)
                g:SetShown(link ~= nil)
            end
            row.cells.votes:SetText(tostring(c.votes or 0))
            row.voteBtn:SetText(c.voters[me] and "Unvote" or "Vote")
            row.voteBtn:SetShown(council)
            row.cells.note:SetText((c.note and c.note ~= "") and "|cffffd100note|r" or "")
            row.cells.roll:SetText(c.roll and tostring(c.roll) or "")
            local last = LC.LastLoot(c.name)
            row.cells.last:SetText(last and (LC.ItemText(last) .. " |cff888888" .. LC.Ago(last.t) .. "|r") or "|cff888888none|r")
            row:Show()
        elseif row then
            row.cand = nil
            row:Hide()
        end
    end
    -- How many of the council have voted on this item
    local voted, total = {}, 0
    for _, c in ipairs(rows) do for v in pairs(c.voters) do voted[v] = true end end
    local nv = 0
    for _ in pairs(voted) do nv = nv + 1 end
    for _ in pairs(RC.council) do total = total + 1 end
    LC.voteStatus = nv .. " of " .. math.max(total, nv) .. " council have voted" .. (RC.local_ and "   |cffffd100(local test)|r" or "")
    if vote.status then vote.status:SetText(LC.voteStatus) end
end

function LC:CreateVotingFrame()
    if vote then return vote end
    vote = WM.UI:CreatePanel({
        name = "WM_LootVotingFrame", title = "Loot Council: voting", titleColor = "FFB347",
        width = 840, height = 420, minHeight = 260, scroll = false,
        resizable = { 700, 260, 1400, 1200 },
        onResize = function() LC:RefreshVoting() end,
        onRefresh = function() LC:RefreshVoting() end,
    })
    local L = vote.layout
    local row = L:Row(22)
    vote.head = row:Text({ text = "", font = "GameFontNormal" }, 44)
    row = L:Row(16)
    vote.sub = row:Text({ text = "" }, 44)
    row = L:Row(16)
    local x = 48
    for _, col in ipairs(COLS) do
        if col.title ~= "" then row:Text({ text = "|cffffd100" .. col.title .. "|r" }, x) end
        x = x + col.w
    end
    local fill = L:Fill(140)
    vote.side = CreateFrame("Frame", nil, fill)
    vote.side:SetPoint("TOPLEFT", 0, 0)
    vote.side:SetPoint("BOTTOMLEFT", 0, 0)
    vote.side:SetWidth(42)
    vote.sessions = {}
    vote.list = CreateFrame("Frame", nil, fill)
    vote.list:SetPoint("TOPLEFT", 44, 0)
    vote.list:SetPoint("BOTTOMRIGHT", 0, 0)
    vote.list:EnableMouseWheel(true)
    vote.list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta * 3
        LC:RefreshVoting()
    end)
    vote.list.rows = {}
    vote.status = vote:AddFooterText({ text = function() return LC.voteStatus or "" end }, "LEFT")
    vote:AddFooterButton({ text = "End test", width = 90, onClick = function() RC:EndTest() end,
        tooltip = { "End test", "Ends a local test session (nothing was sent to anyone)." } }, "RIGHT")
    vote:Finish()
    return vote
end

function LC:ShowVoting()
    local f = self:CreateVotingFrame()
    if not f:IsShown() then f:Show() end
    self:RefreshVoting()
end

-- ============================================
-- WIRING
-- ============================================

function LC:InitFrames()
    self:CreateResponseFrame()
    RC.OnChange(function(what)
        if what == "session" and RC.session then
            if DB().showResponse then LC:RefreshResponse() end
            if RC:IsCouncil() and DB().openVoting then LC:ShowVoting() end
        elseif what == "end" then
            if resp then resp:Hide() end
            if vote then LC:RefreshVoting() end
        else
            LC:RefreshResponse()
            LC:RefreshVoting()
        end
    end)
    LC.OnChange(function() LC:RefreshVoting() end)
end

function LC:HideFrames()
    if resp then resp:Hide() end
    if vote then vote:Hide() end
end
