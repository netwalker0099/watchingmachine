-- Watching Machine: Attunements
-- How far each of your characters is through every raid attunement, key
-- and heroic key chain (Classic and The Burning Crusade): which steps are
-- done, what to do next and where, kept per character so your alts show
-- too, and shared with guild members running Watching Machine.
--
-- Progress is read from the game: finished quests, quests in your log,
-- items in your bags and bank, your level and reputation. Steps the game
-- can't report (kills, talking to someone) count as done once anything
-- after them is.

local AddonName, WM = ...
local AT = {}
WM:RegisterModule("Attunements", AT)
WM.Attunements = AT

AT.version = "3.41"

local PREFIX = "WMAtt"
local DEFAULTS = {
    showClassic = false,   -- Classic attunements in the list
    announce = true,       -- chat line when a step or attunement is done
}

local function DB()
    AttunementsDB = AttunementsDB or {}
    local db = AttunementsDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.guild) ~= "table" then db.guild = {} end
    return db
end

local function Now() return (GetServerTime and GetServerTime()) or time() end
local function CharKey() return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?") end
local function Side() return (UnitFactionGroup and UnitFactionGroup("player")) == "Alliance" and "Alliance" or "Horde" end
AT.CharKey = CharKey

local function Data() return WM.AttuneData or { attunements = {}, quests = {}, npcs = {} } end

-- The client build (20506 on patch 2.5.6), for steps that changed with a patch
local function Build()
    if GetBuildInfo then
        local ok, _, _, _, toc = pcall(GetBuildInfo)
        if ok and tonumber(toc) then return tonumber(toc) end
    end
    return 20506
end

local function StepValid(s, build)
    if s.from and build < s.from then return false end
    if s.to and build >= s.to then return false end
    return true
end

-- ============================================
-- THE LIST
-- ============================================

local byID
function AT:Get(id)
    if not byID then
        byID = {}
        for _, a in ipairs(Data().attunements) do byID[a.id] = byID[a.id] or {}; table.insert(byID[a.id], a) end
    end
    local list = byID[id]
    if not list then return nil end
    for _, a in ipairs(list) do if not a.side or a.side == Side() then return a end end
    return list[1]
end

-- Your side's attunements, TBC first (raids, keys, heroics, other), then
-- Classic when it's switched on
local GROUP_ORDER = { raid = 1, key = 2, heroic = 3, misc = 4 }
AT.GROUP_LABELS = { raid = "Raids", key = "Dungeon keys", heroic = "Heroic keys", misc = "Other" }
function AT:List(includeClassic)
    if includeClassic == nil then includeClassic = DB().showClassic end
    local side, out = Side(), {}
    for i, a in ipairs(Data().attunements) do
        if (not a.side or a.side == side) and (a.expansion >= 1 or includeClassic) then
            a._i = i
            out[#out + 1] = a
        end
    end
    table.sort(out, function(x, y)
        if x.expansion ~= y.expansion then return x.expansion > y.expansion end
        local gx, gy = GROUP_ORDER[x.group] or 9, GROUP_ORDER[y.group] or 9
        if gx ~= gy then return gx < gy end
        return x._i < y._i
    end)
    return out
end

-- ============================================
-- READING PROGRESS FROM THE GAME
-- ============================================

local function QuestDone(id)
    local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or rawget(_G, "IsQuestFlaggedCompleted")
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f, id)
    return ok and v and true or false
end

local function OnQuest(id)
    local f = C_QuestLog and C_QuestLog.IsOnQuest
    if type(f) == "function" then
        local ok, v = pcall(f, id)
        if ok and v then return true end
    end
    local g = rawget(_G, "GetQuestLogIndexByID")
    if type(g) == "function" then
        local ok, i = pcall(g, id)
        return ok and (tonumber(i) or 0) > 0
    end
    return false
end

local function ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id, true)   -- bags and bank
    return ok and tonumber(n) or 0
end

local function RepValue(faction)
    local f = rawget(_G, "GetFactionInfoByID")
    if type(f) ~= "function" then return nil end
    local ok, name, _, _, _, _, earned = pcall(f, faction)
    if ok then return tonumber(earned), name end
end

-- Is this step done, from what the game says? (nil: the game can't tell)
function AT:StepCheck(s, depth)
    local t = s.t
    if t == "quest" or t == "turnin" then return QuestDone(s.ref)
    elseif t == "pickup" then return OnQuest(s.ref) or QuestDone(s.ref)
    elseif t == "item" then return ItemCount(s.ref) >= (s.count or 1)
    elseif t == "level" then return (UnitLevel("player") or 0) >= (s.value or 0)
    elseif t == "rep" then
        local v = RepValue(s.faction)
        return v ~= nil and v >= (s.value or 0)
    elseif t == "attune" then
        local other = self:Get(s.attune)
        return other ~= nil and (depth or 0) < 4 and self:Evaluate(other, depth).complete
    end
    return nil
end

-- Work out one attunement: { done = { [step id] = true }, next = { step },
-- count, total, complete, pct }
function AT:Evaluate(a, depth)
    depth = (depth or 0) + 1
    local build = Build()
    local steps, children = {}, {}
    for _, s in ipairs(a.steps) do
        if StepValid(s, build) then steps[#steps + 1] = s end
    end
    local done = {}
    for _, s in ipairs(steps) do
        local ok = self:StepCheck(s, depth)
        if ok then done[s.id] = true end
        for _, p in ipairs(s.after or {}) do
            children[p] = children[p] or {}
            table.insert(children[p], s)
        end
    end
    -- Something later is done, so what it needed must be (only through
    -- "all of these" links: an "any one of" doesn't say which)
    local changed = true
    while changed do
        changed = false
        for _, s in ipairs(steps) do
            if done[s.id] and not s.any then
                for _, p in ipairs(s.after or {}) do
                    if not done[p] then done[p] = true; changed = true end
                end
            end
        end
    end
    local complete = false
    for _, id in ipairs(a.finish or {}) do if done[id] then complete = true end end
    if complete then for _, s in ipairs(steps) do done[s.id] = true end end
    -- Next: not done, and everything before it is
    local nextSteps, seen = {}, {}
    if not complete then
        for _, s in ipairs(steps) do
            if not done[s.id] and not seen[s.id] then
                local ready
                if s.after and #s.after > 0 then
                    ready = not s.any
                    for _, p in ipairs(s.after) do
                        if s.any then ready = ready or done[p] else ready = ready and done[p] end
                    end
                else
                    ready = true
                end
                if ready then nextSteps[#nextSteps + 1] = s; seen[s.id] = true end
            end
        end
    end
    local count, total, counted = 0, 0, {}
    for _, s in ipairs(steps) do
        if not counted[s.id] then
            counted[s.id] = true
            total = total + 1
            if done[s.id] then count = count + 1 end
        end
    end
    return { done = done, next = nextSteps, count = count, total = total, complete = complete,
        pct = complete and 100 or (total > 0 and math.floor(count / total * 100) or 0) }
end

-- ============================================
-- STEP TEXT
-- ============================================

local STANDINGS = { { 42000, "Exalted" }, { 21000, "Revered" }, { 9000, "Honored" }, { 3000, "Friendly" }, { 0, "Neutral" } }
local function Standing(value)
    for _, s in ipairs(STANDINGS) do if value >= s[1] then return s[2] end end
    return "Unfriendly"
end
AT.Standing = Standing

function AT.QuestTitle(id)
    local f = C_QuestLog and C_QuestLog.GetQuestInfo
    if type(f) == "function" then
        local ok, t = pcall(f, id)
        if ok and type(t) == "string" and t ~= "" then return t end
    end
    local q = Data().quests[id]
    return q and q[1] or ("Quest " .. id)
end

local function ItemName(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then
        local ok, n = pcall(f, id)
        if ok and type(n) == "string" then return n end
    end
    return "Item " .. id
end

function AT.NpcName(id)
    local n = Data().npcs[id]
    return n and n[1] or ("NPC " .. id)
end

-- "Turn in: Return to Khadgar"
function AT:StepText(s)
    local t = s.t
    if t == "quest" then return "Quest: " .. AT.QuestTitle(s.ref)
    elseif t == "pickup" then return "Pick up: " .. AT.QuestTitle(s.ref)
    elseif t == "turnin" then return "Turn in: " .. AT.QuestTitle(s.ref)
    elseif t == "item" then return "Get " .. ItemName(s.ref) .. ((s.count or 1) > 1 and (" x" .. s.count) or "")
    elseif t == "kill" then return "Kill " .. AT.NpcName(s.ref)
    elseif t == "talk" then return "Talk to " .. AT.NpcName(s.ref)
    elseif t == "use" then return s.name or "Use the object"
    elseif t == "level" then return "Reach level " .. (s.value or 0)
    elseif t == "rep" then
        local _, name = RepValue(s.faction)
        return Standing(s.value or 0) .. " with " .. (name or ("faction " .. s.faction))
    elseif t == "attune" then
        local other = self:Get(s.attune)
        return "Attuned: " .. (other and other.name or "?")
    end
    return t
end

-- What the attunement asks, from its own steps
function AT:Summary(a)
    local zones, seen, quests = {}, {}, 0
    local last
    for _, s in ipairs(a.steps) do
        if s.zone and not seen[s.zone] then seen[s.zone] = true; zones[#zones + 1] = s.zone end
        if s.t == "quest" or s.t == "turnin" then quests = quests + 1; last = s end
    end
    local parts = {}
    parts[#parts + 1] = (AT.GROUP_LABELS[a.group] or "Attunement") .. (a.size and (", " .. a.size .. " players") or "")
    parts[#parts + 1] = #a.steps .. " steps, " .. quests .. " quests"
    if #zones > 0 then
        local z = {}
        for i = 1, math.min(5, #zones) do z[i] = zones[i] end
        parts[#parts + 1] = "in " .. table.concat(z, ", ") .. (#zones > 5 and (" and " .. (#zones - 5) .. " more") or "")
    end
    if last then parts[#parts + 1] = "ending with " .. AT.QuestTitle(last.ref) end
    return table.concat(parts, "; ") .. "."
end

-- ============================================
-- SAVED PER CHARACTER
-- ============================================

function AT:Update()
    local char = DB().chars[CharKey()] or {}
    local _, class = UnitClass("player")
    char.name, char.class, char.level, char.side, char.at = UnitName("player"), class, UnitLevel("player"), Side(), Now()
    char.att = char.att or {}
    local newly = {}
    for _, a in ipairs(self:List(true)) do
        local r = self:Evaluate(a)
        local old = char.att[a.id]
        if r.complete and old and old.pct and old.pct < 100 then newly[#newly + 1] = a end
        char.att[a.id] = { pct = r.pct, count = r.count, total = r.total }
    end
    DB().chars[CharKey()] = char
    if DB().announce then
        for _, a in ipairs(newly) do
            WM:ModulePrint("Attunements", "|cff00ff00Attuned:|r " .. a.name .. "!")
        end
    end
    self:RefreshUI()
    return char
end

-- "Karazhan, Serpentshrine Cavern" for a saved character
function AT:AttunedNames(charKey, raidsOnly)
    local c = DB().chars[charKey or CharKey()]
    if not c or not c.att then return {} end
    local out = {}
    for _, a in ipairs(self:List(true)) do
        local r = c.att[a.id]
        if r and r.pct == 100 and (not raidsOnly or a.group == "raid") then out[#out + 1] = a.name end
    end
    return out
end

-- Lines for the Your Characters tooltip
function AT:TooltipLines(charKey)
    local c = DB().chars[charKey]
    if not c or not c.att then return nil end
    local done, going = {}, {}
    for _, a in ipairs(self:List(false)) do
        local r = c.att[a.id]
        if r and a.group == "raid" then
            if r.pct == 100 then done[#done + 1] = a.name elseif r.pct > 0 then going[#going + 1] = a.name .. " " .. r.pct .. "%" end
        end
    end
    if #done == 0 and #going == 0 then return nil end
    local lines = {}
    if #done > 0 then lines[#lines + 1] = "|cff00ff00Attuned:|r " .. table.concat(done, ", ") end
    if #going > 0 then lines[#lines + 1] = "|cffffd100In progress:|r " .. table.concat(going, ", ") end
    return lines
end

-- ============================================
-- GUILD (Watching Machine users)
-- ============================================
-- "Q" asks the guild; each member answers "A <id>:<pct>,..." once, a
-- moment later (spread out so a big guild doesn't answer all at once)

local lastAnswer = -100
function AT:Encode()
    local char = DB().chars[CharKey()]
    local parts = {}
    for id, r in pairs(char and char.att or {}) do
        if r.pct and r.pct > 0 then parts[#parts + 1] = id .. ":" .. r.pct end
    end
    table.sort(parts)
    return "A " .. ((char and char.level) or 0) .. " " .. table.concat(parts, ",")
end

function AT.Decode(msg)
    local level, rest = msg:match("^A (%d+) ?(.*)$")
    if not level then return nil end
    local att = {}
    for id, pct in rest:gmatch("(%d+):(%d+)") do att[tonumber(id)] = math.min(100, tonumber(pct)) end
    return { level = tonumber(level), att = att }
end

local function Send(msg, channel)
    local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or rawget(_G, "SendAddonMessage")
    if type(f) == "function" then pcall(f, PREFIX, msg, channel or "GUILD") end
end

function AT:Survey()
    if not (IsInGuild and IsInGuild()) then
        WM:ModulePrint("Attunements", "You're not in a guild.")
        return false
    end
    self:Update()
    Send("Q", "GUILD")
    self.surveyAt = GetTime()
    return true
end

function AT:OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    local short = sender and (Ambiguate and Ambiguate(sender, "none") or sender:match("^([^-]+)")) or "?"
    if short == UnitName("player") then return end
    if msg == "Q" then
        if GetTime() - lastAnswer < 30 then return end
        lastAnswer = GetTime()
        WM.RunAfter(math.random() * 3, function() Send(AT:Encode(), "GUILD") end)
    else
        local r = AT.Decode(msg)
        if r then
            r.at = Now()
            DB().guild[short] = r
            self:RefreshUI()
        end
    end
end

-- ============================================
-- WINDOW
-- ============================================

local panel
local ROW_H = 20
local state = { sel = nil, view = "me" }

local function Color(pct)
    if pct >= 100 then return "|cff00ff00" end
    if pct > 0 then return "|cffffd100" end
    return "|cff888888"
end

local function NewScroll(parent, name)
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(200, 1)
    sf:SetScrollChild(child)
    sf.child, sf.rows = child, {}
    return sf
end

local function Row(sf, i, height)
    local r = sf.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, sf.child)
    r:SetHeight(height or ROW_H)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(0.3, 0.6, 1, 0.25)
    r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize((height or ROW_H) - 4, (height or ROW_H) - 4)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", -40, 0)
    r.text:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -4, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    sf.rows[i] = r
    return r
end

local function Place(sf, i, r, y)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", sf.child, "TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", sf.child, "RIGHT", 0, 0)
end

local function StepTooltip(r)
    local s = r.step
    if not s then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if s.t == "item" and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(s.ref)
    else
        GameTooltip:SetText(AT:StepText(s), 1, 1, 1)
        if s.t == "quest" or s.t == "pickup" or s.t == "turnin" then
            local q = Data().quests[s.ref]
            if q then
                GameTooltip:AddLine("Level " .. q[2] .. (q[3] > 1 and (", group of " .. q[3]) or ", solo"), 0.8, 0.8, 0.8)
            end
        elseif s.t == "kill" or s.t == "talk" then
            local n = Data().npcs[s.ref]
            if n then GameTooltip:AddLine("Level " .. n[2] .. (n[3] and (" " .. n[3]) or ""), 0.8, 0.8, 0.8) end
        elseif s.t == "rep" then
            local v = RepValue(s.faction)
            if v then GameTooltip:AddLine(string.format("You: %d of %d", v, s.value or 0), 0.8, 0.8, 0.8) end
        end
    end
    if s.zone then GameTooltip:AddLine(s.zone, 0.6, 0.8, 1) end
    GameTooltip:Show()
end

local STEP_ICONS = { quest = "INV_Scroll_03", pickup = "INV_Scroll_03", turnin = "INV_Scroll_03", item = "INV_Misc_Bag_10",
    kill = "Ability_DualWield", talk = "Spell_Holy_PrayerOfHealing", use = "INV_Misc_Orb_05", level = "Spell_Holy_InnerFire",
    rep = "INV_Misc_Note_01", attune = "INV_Misc_Key_14" }

function AT:RefreshList()
    if not panel then return end
    local list = self:List()
    if not state.sel or not self:Get(state.sel) then state.sel = list[1] and list[1].id end
    -- attunements
    local left, y, i, lastGroup = panel.left, 0, 0, nil
    for _, a in ipairs(list) do
        local group = (a.expansion == 0 and "Classic " or "") .. (AT.GROUP_LABELS[a.group] or "")
        if group ~= lastGroup then
            i = i + 1
            local h = Row(left, i, 18)
            Place(left, i, h, y)
            h.icon:SetTexture(nil)
            h.text:SetText("|cffffd100" .. group .. "|r")
            h.right:SetText("")
            h.hl:Hide()
            h.att = nil
            h:SetScript("OnClick", nil)
            h:Show()
            y = y + 18
            lastGroup = group
        end
        i = i + 1
        local r = Row(left, i)
        Place(left, i, r, y)
        local pct = self:Evaluate(a).pct
        r.icon:SetTexture("Interface\\Icons\\" .. (a.icon or "INV_Misc_QuestionMark"))
        r.text:SetText(a.name)
        r.right:SetText(Color(pct) .. pct .. "%|r")
        r.hl:SetShown(a.id == state.sel)
        r.att = a.id
        r:SetScript("OnClick", function() state.sel = a.id; AT:RefreshList() end)
        r:Show()
        y = y + ROW_H
    end
    for j = i + 1, #left.rows do left.rows[j]:Hide() end
    left.child:SetHeight(math.max(1, y))
    left.child:SetWidth(math.max(50, left:GetWidth() or 200))

    -- the selected one
    local a = self:Get(state.sel)
    if not a then return end
    local r = self:Evaluate(a)
    panel.title:SetText(a.name .. "  " .. Color(r.pct) .. r.count .. " / " .. r.total .. " steps (" .. r.pct .. "%)|r")
    panel.summary:SetText("|cff888888" .. self:Summary(a) .. "|r")
    local right = panel.right
    right.child:SetWidth(math.max(50, right:GetWidth() or 300))
    y, i = 0, 0
    if state.view == "me" then
        local nextOf = {}
        for _, s in ipairs(r.next) do nextOf[s.id] = true end
        local build, shown = Build(), {}
        for _, s in ipairs(a.steps) do
            if StepValid(s, build) and not shown[s.id .. s.t .. (s.ref or s.value or 0)] then
                shown[s.id .. s.t .. (s.ref or s.value or 0)] = true
                i = i + 1
                local row = Row(right, i)
                Place(right, i, row, y)
                row.icon:SetTexture("Interface\\Icons\\" .. (STEP_ICONS[s.t] or "INV_Misc_QuestionMark"))
                local text = self:StepText(s)
                if r.done[s.id] then
                    row.text:SetText("|cff00ff00" .. text .. "|r")
                    row.right:SetText("|cff00ff00done|r")
                elseif nextOf[s.id] then
                    row.text:SetText("|cffffd100" .. text .. "|r")
                    row.right:SetText("|cffffd100next|r")
                else
                    row.text:SetText("|cff888888" .. text .. "|r")
                    row.right:SetText("")
                end
                if s.zone then row.text:SetText(row.text:GetText() .. "  |cff6699cc" .. s.zone .. "|r") end
                row.step = s
                row.hl:Hide()
                row:SetScript("OnClick", nil)
                row:SetScript("OnEnter", StepTooltip)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row:Show()
                y = y + ROW_H
            end
        end
    else
        -- alts or guild: one line per character
        local people = {}
        if state.view == "alts" then
            for key, c in pairs(DB().chars) do
                if c.side == nil or c.side == Side() or not a.side then
                    people[#people + 1] = { name = key, class = c.class, level = c.level, r = c.att and c.att[a.id] }
                end
            end
        else
            for name, g in pairs(DB().guild) do
                people[#people + 1] = { name = name, level = g.level, r = { pct = g.att[a.id] or 0 } }
            end
        end
        table.sort(people, function(x, y2)
            local px, py = x.r and x.r.pct or -1, y2.r and y2.r.pct or -1
            if px ~= py then return px > py end
            return x.name < y2.name
        end)
        for _, p in ipairs(people) do
            i = i + 1
            local row = Row(right, i)
            Place(right, i, row, y)
            row.icon:SetTexture(nil)
            local pct = p.r and p.r.pct or 0
            row.text:SetText(p.name .. "  |cff888888" .. (p.level and ("level " .. p.level) or "") .. "|r")
            row.right:SetText(Color(pct) .. (pct >= 100 and "attuned" or (pct .. "%")) .. "|r")
            row.step = nil
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row.hl:Hide()
            row:Show()
            y = y + ROW_H
        end
        if #people == 0 then
            i = i + 1
            local row = Row(right, i)
            Place(right, i, row, y)
            row.icon:SetTexture(nil)
            row.text:SetText("|cff888888" .. (state.view == "guild" and "No answers yet. Press Survey guild (members with Watching Machine answer)."
                or "Log in your other characters once to see them here.") .. "|r")
            row.right:SetText("")
            row.step = nil
            row:Show()
            y = y + ROW_H
        end
    end
    for j = i + 1, #right.rows do right.rows[j]:Hide(); right.rows[j].step = nil end
    right.child:SetHeight(math.max(1, y))
    if panel.viewBox and panel.viewBox.Refresh then panel.viewBox:Refresh() end
end

function AT:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_AttunementsFrame", title = "Attunements", titleColor = "66CCFF",
        width = 760, height = 520, scroll = false,
        resizable = { 600, 360, 1400, 1400 },
        onResize = function() AT:RefreshList() end,
        onRefresh = function() AT:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(24)
    panel.viewBox = top:Choice({
        label = "Show:",
        options = { { value = "me", text = "Steps", width = 60 }, { value = "alts", text = "My characters", width = 100 },
            { value = "guild", text = "Guild", width = 60 } },
        get = function() return state.view end,
        set = function(v) state.view = v; AT:RefreshList() end,
    }, 4)
    top:Checkbox({ label = "Classic too", get = function() return DB().showClassic end,
        set = function(v) DB().showClassic = v; AT:RefreshList() end,
        tooltip = { "Classic attunements", "Molten Core, Onyxia, Blackwing Lair, Naxxramas and the Classic dungeon keys." } }, 290)
    top:Checkbox({ label = "Say when done", get = function() return DB().announce end,
        set = function(v) DB().announce = v end }, 410)
    local head = L:Row(36)
    panel.title = head.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 238, -2)
    panel.summary = head.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -2)
    panel.summary:SetPoint("RIGHT", head.frame, "RIGHT", -8, 0)
    panel.summary:SetJustifyH("LEFT")
    local fill = L:Fill(200)
    panel.left = NewScroll(fill, "WM_AttunementsList")
    panel.left:SetPoint("TOPLEFT", 0, 34)
    panel.left:SetPoint("BOTTOMLEFT", 0, 0)
    panel.left:SetWidth(210)
    panel.right = NewScroll(fill, "WM_AttunementsSteps")
    panel.right:SetPoint("TOPLEFT", panel.left, "TOPRIGHT", 28, -34)
    panel.right:SetPoint("BOTTOMRIGHT", -23, 0)
    panel:AddFooterButton({ text = "Survey guild", width = 100, onClick = function()
        if AT:Survey() then
            state.view = "guild"
            WM:ModulePrint("Attunements", "Asked the guild; members with Watching Machine will answer.")
            AT:RefreshList()
        end
    end }, "RIGHT")
    panel:AddFooterText({ text = "|cff888888Green: done.  Yellow: what to do next.  Hover a step for details.|r" }, "LEFT")
    panel:Finish()
    return panel
end

function AT:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function AT:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else self:Update(); p:Show() end
end
AT.ToggleUI = AT.Toggle

function AT:GetQuickStatus()
    local names = self:AttunedNames(nil, true)
    local total = 0
    for _, a in ipairs(self:List(false)) do if a.group == "raid" then total = total + 1 end end
    return #names .. " / " .. total .. " raids"
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")
local queued = false

local function Soon()
    if queued then return end
    queued = true
    WM.RunAfter(2, function()
        queued = false
        AT:Update()
    end)
end

function AT:OnEvent(event, ...)
    if event == "CHAT_MSG_ADDON" then
        self:OnAddonMessage(...)
    else
        Soon()
    end
end

function AT:Initialize()
    DB()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    WM:RegisterEvents(events, {
        "PLAYER_ENTERING_WORLD", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "BAG_UPDATE",
        "PLAYER_LEVEL_UP", "UPDATE_FACTION", "CHAT_MSG_ADDON",
    })
end

events:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(AT.OnEvent, AT, event, ...)
    if not ok then geterrorhandler()(err) end
end)
