-- Watching Machine: Battleground & Arena log
-- Every battleground and arena match you play, on every character: the
-- result, how long it took, your scoreboard line (killing blows, honorable
-- kills, deaths, honor, damage, healing) and, for arenas, the bracket, both
-- teams and your rating change. Totals and win rates per battleground and
-- per arena bracket.
--
-- The scoreboard is read when the game declares a winner
-- (GetBattlefieldWinner, on UPDATE_BATTLEFIELD_SCORE). Leaving before then
-- logs the match as "left".
--
-- World PvP kills stay in the PvP Enemy Tracker; this is its battleground
-- and arena counterpart.

local AddonName, WM = ...
local Log = {}
WM:RegisterModule("PvPLog", Log)
WM.PvPLog = Log

Log.version = "3.27"

local MAX_MATCHES = 1000

local function DB()
    if type(PvPLogDB) ~= "table" then PvPLogDB = {} end
    local db = PvPLogDB
    if type(db.matches) ~= "table" then db.matches = {} end
    if type(db.nextId) ~= "number" then db.nextId = 1 end
    if db.announce == nil then db.announce = true end
    return db
end
Log.DB = DB

local function Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" and t > 0 then return t end
    end
    return time()
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end

function Log:Print(msg) WM:ModulePrint("PvPLog", msg) end

local function Duration(s)
    s = math.max(0, math.floor(s or 0))
    if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    return string.format("%dm %02ds", math.floor(s / 60), s % 60)
end

local function Commas(n)
    local s = tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (s:gsub("^,", ""))
end

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "ffffff"
end

-- ============================================
-- THE MATCH YOU'RE IN
-- ============================================

local current

function Log:Current() return current end
function Log:Matches() return DB().matches end

local function PvPKind()
    local inside, kind = IsInInstance()
    if inside and (kind == "pvp" or kind == "arena") then return kind end
    return nil
end

-- The arena bracket (2 / 3 / 5) and whether it's rated
local function ArenaInfo()
    local size, rated
    if GetMaxBattlefieldID and GetBattlefieldStatus then
        for i = 1, GetMaxBattlefieldID() do
            local status, _, teamSize, registered = GetBattlefieldStatus(i)
            if status == "active" then
                size = tonumber(teamSize)
                if registered and registered ~= 0 then rated = true end
            end
        end
    end
    if IsActiveBattlefieldArena then
        local _, isRanked = IsActiveBattlefieldArena()
        if isRanked then rated = true end
    end
    return size, rated and true or false
end

function Log:Start()
    local kind = PvPKind()
    if not kind then return end
    local name = GetInstanceInfo and GetInstanceInfo() or GetRealZoneText and GetRealZoneText() or "?"
    if current and current.name == name and not current.done then return end   -- reload inside
    if current then self:Finish(nil) end
    local db = DB()
    current = {
        id = db.nextId, kind = kind == "arena" and "arena" or "bg", name = name,
        char = CharKey(), class = select(2, UnitClass("player")), level = UnitLevel("player"),
        started = Now(), ended = 0,
    }
    db.nextId = db.nextId + 1
    if current.kind == "arena" then current.bracket, current.rated = ArenaInfo() end
    table.insert(db.matches, 1, current)
    while #db.matches > MAX_MATCHES do table.remove(db.matches) end
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
    self:RefreshUI()
end

-- Read the scoreboard and the result. winner = 0 / 1 (Horde / Alliance in a
-- battleground, team 0 / 1 in an arena), nil when you left first. quiet:
-- no chat line
function Log:Finish(winner, quiet)
    local m = current
    if not m or m.done then return end
    m.done = true
    m.ended = Now()
    current = nil

    local me = UnitName("player")
    local myTeam
    local players = {}
    local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    for i = 1, n do
        local name, kb, hk, deaths, honor, faction, _, _, _, classToken, damage, healing = GetBattlefieldScore(i)
        if name then
            local p = { name = name, class = classToken, team = faction }
            players[#players + 1] = p
            if name == me then   -- your own line never carries a realm
                myTeam = faction
                m.killingBlows, m.honorableKills, m.deaths = kb, hk, deaths
                m.honor, m.damage, m.healing = honor, damage, healing
            end
        end
    end
    if m.kind == "arena" and GetBattlefieldArenaFaction then
        local ok, team = pcall(GetBattlefieldArenaFaction)
        if ok and (team == 0 or team == 1) then myTeam = team end
    end
    m.team = myTeam
    m.players = #players

    if winner == nil then
        m.result = "left"
    elseif winner ~= 0 and winner ~= 1 then
        m.result = "draw"
    elseif myTeam == nil then
        m.result = "unknown"
    else
        m.result = (winner == myTeam) and "win" or "loss"
    end

    if m.kind == "arena" then
        -- Both teams' names and ratings, and who you faced
        m.teams = {}
        if GetBattlefieldTeamInfo then
            for t = 0, 1 do
                local ok, teamName, rating, newRating = pcall(GetBattlefieldTeamInfo, t)
                if ok then m.teams[t] = { name = teamName, rating = rating, newRating = newRating } end
            end
        end
        local mine = myTeam and m.teams[myTeam]
        if mine and m.rated and tonumber(mine.rating) and tonumber(mine.newRating) and mine.rating >= 0 then
            m.rating, m.ratingChange = mine.newRating, mine.newRating - mine.rating
        end
        m.opponents, m.partners = {}, {}
        for _, p in ipairs(players) do
            local list = (p.team == myTeam) and m.partners or m.opponents
            if p.name ~= me then list[#list + 1] = { name = p.name, class = p.class } end
        end
    end
    if DB().announce and not quiet then self:Announce(m) end
    self:RefreshUI()
end

local RESULT_TEXT = {
    win = "|cFF33FF33Win|r", loss = "|cFFFF4444Loss|r", draw = "|cFFFFCC33Draw|r",
    left = "|cFF999999Left early|r", unknown = "|cFF999999Ended|r",
}
Log.RESULT_TEXT = RESULT_TEXT

function Log:Title(m)
    if m.kind == "arena" then
        return (m.bracket and (m.bracket .. "v" .. m.bracket .. " ") or "") .. (m.rated and "rated arena" or "skirmish")
            .. (m.name and (" (" .. m.name .. ")") or "")
    end
    return m.name or "Battleground"
end

function Log:Summary(m)
    local parts = { self:Title(m) .. ": " .. (RESULT_TEXT[m.result] or "?") .. " (" .. Duration(m.ended - m.started) .. ")" }
    if m.kind == "arena" then
        if m.ratingChange then
            parts[#parts + 1] = string.format("rating %d (%s%d)", m.rating, m.ratingChange >= 0 and "+" or "", m.ratingChange)
        end
        if m.opponents and #m.opponents > 0 then
            local names = {}
            for _, o in ipairs(m.opponents) do names[#names + 1] = "|cFF" .. ClassHex(o.class) .. o.name .. "|r" end
            parts[#parts + 1] = "vs " .. table.concat(names, ", ")
        end
    elseif m.killingBlows then
        parts[#parts + 1] = string.format("%d KB, %d HK, %d deaths, +%s honor", m.killingBlows or 0,
            m.honorableKills or 0, m.deaths or 0, Commas(m.honor or 0))
    end
    return table.concat(parts, " — ")
end

function Log:Announce(m)
    local text = self:Summary(m)
    if WM.ChatLink then text = WM:ChatLink("pvplog", "", text) end
    self:Print(text)
end

-- ============================================
-- TOTALS
-- ============================================

-- { key, title, games, wins, losses } sorted by games; char = nil for all
function Log:Totals(char)
    local by, order = {}, {}
    for _, m in ipairs(DB().matches) do
        if m.done and (not char or m.char == char) then
            local key = m.kind == "arena" and ("arena:" .. (m.bracket or "?") .. (m.rated and ":rated" or ":skirmish")) or ("bg:" .. (m.name or "?"))
            local t = by[key]
            if not t then
                t = { key = key, games = 0, wins = 0, losses = 0,
                    title = m.kind == "arena" and ((m.bracket and (m.bracket .. "v" .. m.bracket .. " ") or "") .. (m.rated and "rated" or "skirmish")) or m.name }
                by[key] = t
                order[#order + 1] = t
            end
            t.games = t.games + 1
            if m.result == "win" then t.wins = t.wins + 1 elseif m.result == "loss" or m.result == "left" then t.losses = t.losses + 1 end
        end
    end
    table.sort(order, function(a, b) return a.games > b.games end)
    return order
end

function Log:TotalsText(char)
    local lines = {}
    for _, t in ipairs(self:Totals(char)) do
        local rate = t.games > 0 and math.floor(t.wins / t.games * 100 + 0.5) or 0
        lines[#lines + 1] = string.format("%s: |cFFFFFFFF%d|r played, |cFF33FF33%d|r won (%d%%)", t.title, t.games, t.wins, rate)
    end
    if #lines == 0 then return "|cFF888888No battlegrounds or arenas logged yet.|r" end
    return table.concat(lines, "\n")
end

-- ============================================
-- WINDOW
-- ============================================

local panel
local ROW_H = 20

local function When(t) return date("%d %b %H:%M", t) end

function Log:ShowTooltip(owner, m)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self:Title(m), 1, 0.8, 0)
    GameTooltip:AddLine("|cFF" .. ClassHex(m.class) .. (m.char:match("^[^-]+") or m.char) .. "|r  level " .. (m.level or "?"), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Result", RESULT_TEXT[m.result] or (m.done and "?" or "in progress"), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Started", When(m.started), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Length", Duration((m.ended > 0 and m.ended or Now()) - m.started), 0.8, 0.8, 0.8, 1, 1, 1)
    if m.killingBlows then
        GameTooltip:AddDoubleLine("Killing blows", m.killingBlows, 0.8, 0.8, 0.8, 1, 1, 1)
        if m.kind == "bg" then
            GameTooltip:AddDoubleLine("Honorable kills", m.honorableKills or 0, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Deaths", m.deaths or 0, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Honor", "+" .. Commas(m.honor or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if m.damage then GameTooltip:AddDoubleLine("Damage done", Commas(m.damage), 0.8, 0.8, 0.8, 1, 1, 1) end
        if m.healing then GameTooltip:AddDoubleLine("Healing done", Commas(m.healing), 0.8, 0.8, 0.8, 1, 1, 1) end
    end
    if m.kind == "arena" then
        if m.ratingChange then
            GameTooltip:AddDoubleLine("Rating", string.format("%d (%s%d)", m.rating, m.ratingChange >= 0 and "+" or "", m.ratingChange),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        local function List(title, list)
            if not list or #list == 0 then return end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(title, 1, 0.8, 0)
            for _, p in ipairs(list) do GameTooltip:AddLine("|cFF" .. ClassHex(p.class) .. p.name .. "|r") end
        end
        local mine = m.team and m.teams and m.teams[m.team]
        local theirs = m.team and m.teams and m.teams[1 - m.team]
        List("With" .. (mine and mine.name and (" (" .. mine.name .. ")") or ""), m.partners)
        List("Against" .. (theirs and theirs.name and (" (" .. theirs.name .. ")") or ""), m.opponents)
    elseif m.players then
        GameTooltip:AddDoubleLine("Players", m.players, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to delete this match.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function Log:Delete(m)
    local list = DB().matches
    for i, x in ipairs(list) do
        if x == m then table.remove(list, i) break end
    end
    if m == current then current = nil end
    self:RefreshUI()
end

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.title:SetPoint("LEFT", 6, 0)
    row.title:SetWidth(190)
    row.title:SetJustifyH("LEFT")
    row.result = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.result:SetPoint("LEFT", 200, 0)
    row.result:SetWidth(70)
    row.result:SetJustifyH("LEFT")
    row.char = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.char:SetPoint("LEFT", 275, 0)
    row.char:SetWidth(90)
    row.char:SetJustifyH("LEFT")
    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.when:SetPoint("RIGHT", -6, 0)
    row.when:SetJustifyH("RIGHT")
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnEnter", function(self) if self.match then Log:ShowTooltip(self, self.match) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local m = self.match
        if not m then return end
        WM:Confirm("Delete " .. Log:Title(m) .. " (" .. When(m.started) .. ") from the log?", function() Log:Delete(m) end)
    end)
    return row
end

function Log:RefreshList()
    if not panel or not panel.listChild then return end
    local child, rows = panel.listChild, panel.rows
    local width = math.max(380, (panel:GetWidth() or 540) - 50)
    child:SetWidth(width)
    local filter = not panel.showAll and CharKey() or nil
    local n = 0
    for _, m in ipairs(DB().matches) do
        if not filter or m.char == filter then
            n = n + 1
            local row = rows[n] or NewRow(child)
            rows[n] = row
            row.match = m
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(n - 1) * ROW_H)
            row:SetWidth(width)
            row.bg:SetColorTexture(1, 1, 1, n % 2 == 0 and 0.05 or 0.02)
            row.title:SetText(self:Title(m))
            row.result:SetText(m.done and (RESULT_TEXT[m.result] or "?") or "|cFF33FF33now|r")
            row.char:SetText("|cFF" .. ClassHex(m.class) .. (m.char:match("^[^-]+") or m.char) .. "|r")
            row.when:SetText(When(m.started))
            row:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].match = nil end
    child:SetHeight(math.max(1, n * ROW_H))
end

function Log:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_PvPLogFrame", title = "Battlegrounds & Arenas", titleColor = "FF6666",
        width = 560, height = 480, minHeight = 320, scroll = false,
        resizable = { 460, 320, 1000, 1200 },
        onResize = function() Log:RefreshList() end,
        onRefresh = function() Log:RefreshList() end,
    })
    local L = panel.layout
    L:Note(function() return Log:TotalsText(not panel.showAll and CharKey() or nil) end)
    local row = L:Row(22)
    row:Checkbox({
        label = "All characters",
        get = function() return panel.showAll end,
        set = function(v) panel.showAll = v; panel:Refresh() end,
    }, 8)
    row:Checkbox({
        label = "Result in chat after each match",
        get = function() return DB().announce end, set = function(v) DB().announce = v end,
    }, 150)
    local fill = L:Fill(160)
    local scroll = CreateFrame("ScrollFrame", "WM_PvPLogScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    scroll:SetScrollChild(child)
    panel.listChild, panel.rows = child, {}
    panel.showAll = true
    panel:Finish()
    return panel
end

function Log:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function Log:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
Log.ToggleUI = Log.Toggle

function Log:GetQuickStatus()
    if current then return "|cFF33FF33In " .. self:Title(current) .. "|r" end
    local games, wins = 0, 0
    for _, m in ipairs(DB().matches) do
        if m.done then
            games = games + 1
            if m.result == "win" then wins = wins + 1 end
        end
    end
    if games == 0 then return "|cFF888888No matches yet|r" end
    return string.format("%d played, %d won (%d%%)", games, wins, math.floor(wins / games * 100 + 0.5))
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

function Log:OnEvent(event)
    if not WM:IsModuleOn("PvPLog") then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if PvPKind() then self:Start() elseif current then self:Finish(nil) end
    elseif event == "UPDATE_BATTLEFIELD_SCORE" or event == "UPDATE_BATTLEFIELD_STATUS" then
        if current and GetBattlefieldWinner then
            local winner = GetBattlefieldWinner()
            if winner ~= nil then self:Finish(winner) end
        end
    end
end

function Log:Initialize()
    DB()
    WM:RegisterEvents(events, { "PLAYER_ENTERING_WORLD", "UPDATE_BATTLEFIELD_SCORE", "UPDATE_BATTLEFIELD_STATUS" })
    if WM.RegisterChatLink then
        WM:RegisterChatLink("pvplog", function()
            if not WM:UsableModule("PvPLog") then return end
            local p = Log:CreateUI()
            if not p:IsShown() then p:Show() end
        end)
    end
    if PvPKind() then self:Start() end
end

events:SetScript("OnEvent", function(_, event) Log:OnEvent(event) end)

-- Turned off: close the window; a match you're in is logged as left early,
-- without the chat line
function Log:OnModuleOff()
    if panel then panel:Hide() end
    if current then self:Finish(nil, true) end
end

-- Turned back on inside a battleground or arena: log it from now
function Log:OnModuleOn()
    DB()
    if PvPKind() then self:Start() end
end

-- The module's page in the guided setup
function Log:SetupPage(L)
    DB()
    L:Note("Keeps a record of every battleground and arena you play, on all your characters, with totals and win"
        .. " rates for each battleground and each arena bracket.")
    L:Note("|cFFFFFFFFHow it works:|r a match starts being logged when you zone in. When the game declares a winner"
        .. " it reads the scoreboard: your killing blows, honorable kills, deaths, honor, damage and healing, and in"
        .. " arenas both teams and your rating change. Leave before the end and the match is logged as \"left early\".")
    L:Checkbox({ label = "Result in chat after each match", get = function() return DB().announce end,
        set = function(v) DB().announce = v end,
        tooltip = { "Match result", "A chat line when a match ends: win or loss, how long it took and your score."
            .. " Click it to open the log." } })
    L:Note("World PvP kills are kept by the PvP Enemy Tracker, not here.")
    L:Note("The matches, totals and each match's details (hover one) are in its window: |cFFFFFF00/wmachine bgs|r.")
end
