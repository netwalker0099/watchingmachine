-- Watching Machine: Crit Tracker
-- Your biggest hits, crits and heals for every spell and ability, from
-- the combat log: the best normal hit and the best crit, how often it
-- crits, and who it was on and where. A new best crit says so in chat
-- (and with a sound, if you like). Kept per character; PvP and PvE apart.
-- Spell tooltips show your records for that spell.

local AddonName, WM = ...
local CR = {}
WM:RegisterModule("Crits", CR)
WM.Crits = CR

CR.version = "3.43"

local CATS = {
    { key = "spell", label = "Spells" }, { key = "ability", label = "Abilities" },
    { key = "melee", label = "Melee" }, { key = "ranged", label = "Ranged" }, { key = "heal", label = "Heals" },
}
CR.CATS = CATS
local CAT_LABEL = {}
for _, c in ipairs(CATS) do CAT_LABEL[c.key] = c.label end

local DEFAULTS = {
    enabled = true,
    alertCrits = true,     -- chat line on a new best crit
    alertHits = false,     -- ... and on a new best normal hit
    sound = "kit:891",
    channel = "Master",
    splash = false,        -- big text in the middle of the screen
    announce = false,      -- tell your party / raid
    minimum = 0,           -- records below this don't say anything
    pvp = true,            -- count hits on players (kept apart)
    tooltips = true,       -- records on spell tooltips
}

local function DB()
    WMCritsDB = WMCritsDB or {}
    local db = WMCritsDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    if type(db.chars) ~= "table" then db.chars = {} end
    return db
end
CR.DB = DB

local function Now() return (GetServerTime and tonumber(GetServerTime())) or time() end
local function CharKey() return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?") end
CR.CharKey = CharKey

-- A character's records (made for the character you're on; read-only
-- for others, so looking at an alt doesn't add an empty entry)
local function Records(key)
    local chars = DB().chars
    key = key or CharKey()
    if not chars[key] then
        if key ~= CharKey() then return {} end
        chars[key] = { records = {} }
    end
    chars[key].records = chars[key].records or {}
    return chars[key].records
end
CR.Records = Records

local function Commas(n)
    local s = tostring(math.floor(n or 0))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
CR.Commas = Commas

-- ============================================
-- RECORDING
-- ============================================

-- One hit or heal of yours. Returns the record, and "crit" / "hit" when it
-- was a new best.
function CR:Record(cat, name, spellID, amount, crit, target, pvp)
    if not name or not amount or amount <= 0 then return nil end
    local key = (pvp and "pvp:" or "") .. cat .. ":" .. name
    local recs = Records()
    local r = recs[key]
    if not r then
        r = { cat = cat, name = name, spell = spellID, pvp = pvp or nil, hits = 0, crits = 0 }
        recs[key] = r
    end
    r.spell = spellID or r.spell
    r.hits = r.hits + 1
    if crit then r.crits = r.crits + 1 end
    local field = crit and "crit" or "hit"
    local best = r[field]
    if not best or amount > best.value then
        local old = best and best.value
        r[field] = { value = amount, at = Now(), target = target,
            zone = (GetRealZoneText and GetRealZoneText()) or nil, prev = old }
        return r, field, old
    end
    return r
end

function CR:Announce(r, field, old)
    local db = DB()
    local b = r[field]
    if b.value < (db.minimum or 0) then return false end
    if field == "hit" and not db.alertHits then return false end
    if field == "crit" and not db.alertCrits then return false end
    if not old then
        -- The first of something isn't a record worth a fanfare
        return false
    end
    local what = field == "crit" and "crit" or "hit"
    local msg = string.format("New best %s%s: |cFFFFFFFF%s|r |cFFFF3333%s|r |cFF888888(was %s%s)|r", what,
        r.pvp and " (PvP)" or "", r.name, Commas(b.value), Commas(old), b.target and (", on " .. b.target) or "")
    WM:ModulePrint("Crits", msg)
    if WM.Sounds then WM.Sounds.Play(db.sound, db.channel) end
    if db.splash and RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, r.name .. " " .. Commas(b.value) .. "!", { r = 1, g = 0.5, b = 0 })
    end
    if db.announce and field == "crit" and (not self.lastShout or GetTime() - self.lastShout > 5) then
        local channel = (IsInRaid and IsInRaid()) and "RAID" or ((GetNumGroupMembers and GetNumGroupMembers() or 0) > 0 and "PARTY" or nil)
        if channel then
            self.lastShout = GetTime()
            SendChatMessage(string.format("[WM] New best crit: %s %s (was %s)", r.name, Commas(b.value), Commas(old)), channel)
        end
    end
    return true
end

local PHYSICAL = 1
function CR:OnCombatEvent(...)
    local _, sub, _, srcGUID, _, _, _, dstGUID, dstName, _, _, a12, a13, a14, a15, _, _, a18, _, _, a21 = ...
    if srcGUID ~= UnitGUID("player") then return end
    -- Damage to another player counts as PvP; heals (on anyone) never do
    local pvp = type(dstGUID) == "string" and dstGUID:find("^Player") ~= nil and dstGUID ~= srcGUID
    local cat, name, spellID, amount, crit
    if sub == "SWING_DAMAGE" then
        cat, name, amount, crit = "melee", "Melee", a12, a18
    elseif sub == "RANGE_DAMAGE" then
        cat, name, spellID, amount, crit = "ranged", a13 or "Ranged", a12, a15, a21
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" then
        cat = (sub == "SPELL_DAMAGE" and a14 == PHYSICAL) and "ability" or "spell"
        name, spellID, amount, crit = a13, a12, a15, a21
    elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        cat, name, spellID, amount, crit = "heal", a13, a12, a15, a18
        pvp = false
    else
        return
    end
    if pvp and not DB().pvp then return end
    local r, field, old = self:Record(cat, name, tonumber(spellID), tonumber(amount), crit and true or false,
        cat ~= "heal" and dstName or nil, pvp)
    if field then
        self:Announce(r, field, old)
        self:RefreshUI()
    end
    return r, field
end

-- ============================================
-- LISTS, TOOLTIPS, YOUR CHARACTERS
-- ============================================

-- Records, best crit first: filter cat (nil = all), pvp (true / false)
function CR:List(charKey, cat, pvp)
    local out = {}
    for _, r in pairs(Records(charKey)) do
        if (not cat or r.cat == cat) and ((r.pvp and true or false) == (pvp and true or false)) then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        local va, vb = a.crit and a.crit.value or 0, b.crit and b.crit.value or 0
        if va ~= vb then return va > vb end
        return (a.hit and a.hit.value or 0) > (b.hit and b.hit.value or 0)
    end)
    return out
end

function CR.Rate(r) return r.hits > 0 and math.floor(r.crits / r.hits * 1000 + 0.5) / 10 or 0 end

local function Ago(t)
    local s = math.max(0, Now() - (t or 0))
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end
CR.Ago = Ago

-- Lines for a spell's tooltip (by name; ranks share one record)
function CR:TooltipLines(name)
    if not WM:IsModuleOn("Crits") or not DB().tooltips or not name then return nil end
    local lines = {}
    for _, r in pairs(Records()) do
        if r.name == name then
            local tag = (CAT_LABEL[r.cat] or r.cat) .. (r.pvp and ", PvP" or "")
            local s = "|cFFFF8800Best|r |cFF888888(" .. tag .. ")|r "
            if r.crit then s = s .. "crit |cFFFF3333" .. Commas(r.crit.value) .. "|r " end
            if r.hit then s = s .. "hit |cFFFFFFFF" .. Commas(r.hit.value) .. "|r " end
            s = s .. "|cFF888888" .. CR.Rate(r) .. "% crits|r"
            lines[#lines + 1] = s
        end
    end
    return #lines > 0 and lines or nil
end

-- "Best crit: Fireball 4,512" for Your Characters
function CR:BestLine(charKey)
    local best
    for _, r in pairs(Records(charKey)) do
        if r.crit and not r.pvp and (not best or r.crit.value > best.crit.value) then best = r end
    end
    if not best then return nil end
    return "|cFFFF8800Best crit:|r " .. best.name .. " |cFFFF3333" .. Commas(best.crit.value) .. "|r"
end

local hookedTips = {}
function CR:HookTooltips()
    local function Add(tip)
        if not tip or not tip.GetSpell then return end
        local ok, name = pcall(tip.GetSpell, tip)
        if not ok or tip.wmCrits == name then return end
        local lines = CR:TooltipLines(name)
        if not lines then return end
        tip.wmCrits = name
        for _, l in ipairs(lines) do tip:AddLine(l) end
        if tip.Show then tip:Show() end
    end
    local proc, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    if type(proc) == "table" and type(proc.AddTooltipPostCall) == "function" and type(enum) == "table"
        and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Spell then
        proc.AddTooltipPostCall(enum.TooltipDataType.Spell, function(tip) pcall(Add, tip) end)
    end
    local tip = rawget(_G, "GameTooltip")
    if type(tip) == "table" and tip.HookScript and not hookedTips[tip] then
        hookedTips[tip] = true
        tip:HookScript("OnTooltipCleared", function(t) t.wmCrits = nil end)
        -- (Add checks the module is on, through TooltipLines)
        if not tip.HasScript or tip:HasScript("OnTooltipSetSpell") then
            tip:HookScript("OnTooltipSetSpell", function(t) pcall(Add, t) end)
        end
    end
end

function CR:Reset(charKey)
    DB().chars[charKey or CharKey()] = { records = {} }
    self:RefreshUI()
end

function CR:Share(r, channel)
    local b = r.crit or r.hit
    if not b then return false end
    local msg = string.format("[WM] My best %s %s: %s%s", r.crit and "crit" or "hit", r.name, Commas(b.value),
        b.target and (" on " .. b.target) or "")
    SendChatMessage(msg, channel)
    return true
end

-- ============================================
-- WINDOW
-- ============================================

local panel
local ROW_H = 18
local view = { cat = nil, pvp = false, char = nil }

local function Row(child, rows, i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 2, ROW_H - 2)
    r.icon:SetPoint("LEFT", 2, 0)
    local function Col(x, w, justify)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end
    r.name = Col(22, 150)
    r.cat = Col(176, 64)
    r.crit = Col(244, 64, "RIGHT")
    r.hit = Col(312, 64, "RIGHT")
    r.rate = Col(380, 44, "RIGHT")
    r.target = Col(432, 160)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", function(self)
        local rec = self.rec
        if not rec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(rec.name .. (rec.pvp and " (PvP)" or ""))
        for _, f in ipairs({ "crit", "hit" }) do
            local b = rec[f]
            if b then
                GameTooltip:AddLine((f == "crit" and "Best crit " or "Best hit ") .. Commas(b.value)
                    .. (b.target and (" on " .. b.target) or "") .. (b.zone and (", " .. b.zone) or "") .. ", " .. Ago(b.at), 1, 1, 1)
            end
        end
        GameTooltip:AddLine(rec.crits .. " crits in " .. rec.hits .. " (" .. CR.Rate(rec) .. "%)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click to share.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.rec then CR:OpenShareMenu(self.rec) end
    end)
    rows[i] = r
    return r
end

function CR:OpenShareMenu(rec)
    if not self.menu then self.menu = CreateFrame("Frame", "WM_CritsShareMenu", UIParent, "UIDropDownMenuTemplate") end
    UIDropDownMenu_Initialize(self.menu, function(_, level)
        for _, ch in ipairs({ { "SAY", "Say" }, { "PARTY", "Party" }, { "RAID", "Raid" }, { "GUILD", "Guild" } }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable = "Share in " .. ch[2], true
            info.func = function() CR:Share(rec, ch[1]) end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    if ToggleDropDownMenu then ToggleDropDownMenu(1, nil, self.menu, "cursor", 0, 0) end
    return self.menu
end

local function SpellIcon(id)
    if not id then return "Interface\\Icons\\INV_Sword_04" end
    local f = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if f then
        local ok, tex = pcall(f, id)
        if ok and tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function CR:RefreshList()
    if not panel or not panel.listChild then return end
    local list = self:List(view.char, view.cat, view.pvp)
    local child, rows = panel.listChild, panel.rows
    child:SetWidth(math.max(500, (panel:GetWidth() or 640) - 50))
    for i, rec in ipairs(list) do
        local r = Row(child, rows, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.05 or 0.02)
        r.rec = rec
        r.icon:SetTexture(rec.cat == "melee" and "Interface\\Icons\\INV_Sword_04" or SpellIcon(rec.spell))
        r.name:SetText(rec.name)
        r.cat:SetText("|cFF888888" .. (CAT_LABEL[rec.cat] or rec.cat) .. "|r")
        r.crit:SetText(rec.crit and ("|cFFFF3333" .. Commas(rec.crit.value) .. "|r") or "|cFF555555-|r")
        r.hit:SetText(rec.hit and Commas(rec.hit.value) or "|cFF555555-|r")
        r.rate:SetText("|cFF888888" .. CR.Rate(rec) .. "%|r")
        local b = rec.crit or rec.hit
        r.target:SetText("|cFF888888" .. ((b and b.target) or "") .. "|r")
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide(); rows[i].rec = nil end
    child:SetHeight(math.max(1, #list * ROW_H))
    if panel.summary then
        panel.summary:SetText(#list == 0 and "|cFF888888Nothing yet: go hit something.|r" or (#list .. " records"))
    end
end

function CR:CreateUI()
    if panel then return panel end
    panel = WM.UI:CreatePanel({
        name = "WM_CritsFrame", title = "Crit Tracker", titleColor = "FF8800",
        width = 640, height = 480, scroll = false,
        resizable = { 560, 300, 1200, 1400 },
        onResize = function() CR:RefreshList() end,
        onRefresh = function() CR:RefreshList() end,
    })
    local L = panel.layout
    local top = L:Row(24)
    local opts = { { value = "all", text = "All", width = 40 } }
    for _, c in ipairs(CATS) do opts[#opts + 1] = { value = c.key, text = c.label, width = #c.label * 7 + 14 } end
    panel.catBox = top:Choice({ label = "Show:", options = opts,
        get = function() return view.cat or "all" end,
        set = function(v) view.cat = v ~= "all" and v or nil; CR:RefreshList() end }, 4)
    local second = L:Row(24)
    panel.pvpBox = second:Choice({ label = "Against:", options = { { value = "pve", text = "Creatures", width = 70 }, { value = "pvp", text = "Players", width = 60 } },
        get = function() return view.pvp and "pvp" or "pve" end,
        set = function(v) view.pvp = v == "pvp"; CR:RefreshList() end }, 4)
    panel.charBox = second:Dropdown({ label = "Character:", width = 140,
        options = function()
            local o = {}
            for key in pairs(DB().chars) do o[#o + 1] = { value = key, text = key } end
            table.sort(o, function(a, b) return a.text < b.text end)
            return o
        end,
        get = function() return view.char or CharKey() end,
        set = function(v) view.char = v ~= CharKey() and v or nil; CR:RefreshList() end }, 200)
    local head = L:Row(16)
    for _, h in ipairs({ { "Spell", 22 }, { "Kind", 176 }, { "Best crit", 252 }, { "Best hit", 324 }, { "Crits", 388 }, { "On", 432 } }) do
        head:Text({ text = "|cFFFFD100" .. h[1] .. "|r" }, h[2])
    end
    local fill = L:Fill(140)
    local scroll = CreateFrame("ScrollFrame", "WM_CritsScroll", fill, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(560, 1)
    scroll:SetScrollChild(child)
    panel.listChild, panel.rows = child, {}
    L:Section({ key = "options", title = "Options" })
    L:Checkbox({ label = "Say when you beat your best crit", get = function() return DB().alertCrits end, set = function(v) DB().alertCrits = v end })
    L:Checkbox({ label = "... and your best normal hit", get = function() return DB().alertHits end, set = function(v) DB().alertHits = v end })
    L:Dropdown({ label = "Sound:", width = 150, options = function() return WM.Sounds and WM.Sounds.OPTIONS or {} end,
        get = function() return DB().sound end,
        set = function(v) DB().sound = v; if WM.Sounds then WM.Sounds.Play(v, DB().channel) end end })
    L:Checkbox({ label = "Big text on screen too", get = function() return DB().splash end, set = function(v) DB().splash = v end })
    L:Checkbox({ label = "Tell your party / raid about a new best crit", get = function() return DB().announce end, set = function(v) DB().announce = v end })
    L:Checkbox({ label = "Count hits on players (kept apart)", get = function() return DB().pvp end, set = function(v) DB().pvp = v end })
    L:Checkbox({ label = "Records on spell tooltips", get = function() return DB().tooltips end, set = function(v) DB().tooltips = v end })
    L:EditBox({ label = "Quiet below:", width = 70, numeric = true,
        get = function() return tostring(DB().minimum or 0) end,
        set = function(v) DB().minimum = tonumber(v) or 0 end,
        tooltip = { "Quiet below", "New records smaller than this don't say anything (useful while levelling)." } })
    L:EndSection()
    panel.summary = panel:AddFooterText({ text = "" }, "LEFT")
    panel:AddFooterButton({ text = "Reset", width = 70, confirm = true, onClick = function() CR:Reset(view.char) end }, "RIGHT")
    panel:Finish()
    return panel
end

function CR:RefreshUI()
    if panel and panel:IsShown() then panel:Refresh() end
end

function CR:Toggle()
    local p = self:CreateUI()
    if p:IsShown() then p:Hide() else p:Show() end
end
CR.ToggleUI = CR.Toggle

function CR:IsModuleEnabled() return DB().enabled end
function CR:SetModuleEnabled(v) DB().enabled = v and true or false end

function CR:OnModuleOff()
    if panel then panel:Hide() end
    if self.menu and CloseDropDownMenus then CloseDropDownMenus() end
end

-- The module's page in the guided setup
function CR:SetupPage(L)
    DB()
    L:Note("Crit Tracker reads the combat log and keeps, for every spell, ability, melee swing, shot and heal you"
        .. " use, your biggest normal hit and your biggest crit, how often it crits, and who and where it was.")
    L:Note("|cFFFFFFFFWhen you beat a record:|r a line in chat says so, with the old number to compare. The very first"
        .. " hit with something isn't announced, so a new character doesn't fill your chat. Hits on players are kept"
        .. " apart from hits on creatures.")
    L:Note("Hover over a spell in your spellbook or on your bars to see your records for it.")
    L:Checkbox({ label = "Say when you beat your best crit", get = function() return DB().alertCrits end,
        set = function(v) DB().alertCrits = v end,
        tooltip = { "New best crit", "A line in chat (and the sound below) when a crit beats your last best one." } })
    L:Checkbox({ label = "... and your best normal hit", get = function() return DB().alertHits end,
        set = function(v) DB().alertHits = v end,
        tooltip = { "New best hit", "The same for normal hits. These come often while you're levelling." } })
    L:Dropdown({ label = "Sound:", width = 150, options = function() return WM.Sounds and WM.Sounds.OPTIONS or {} end,
        get = function() return DB().sound end,
        set = function(v) DB().sound = v; if WM.Sounds then WM.Sounds.Play(v, DB().channel) end end,
        tooltip = { "Sound", "Played with the chat line. Picking one plays it." } })
    L:Checkbox({ label = "Big text on screen too", get = function() return DB().splash end,
        set = function(v) DB().splash = v end,
        tooltip = { "Big text", "The spell and the number in the middle of the screen." } })
    L:Checkbox({ label = "Tell your party / raid about a new best crit", get = function() return DB().announce end,
        set = function(v) DB().announce = v end,
        tooltip = { "Announce", "A line in party or raid chat, at most once every 5 seconds." } })
    L:Checkbox({ label = "Count hits on players (kept apart)", get = function() return DB().pvp end,
        set = function(v) DB().pvp = v end,
        tooltip = { "PvP", "Off: hits on other players aren't recorded at all." } })
    L:Checkbox({ label = "Records on spell tooltips", get = function() return DB().tooltips end,
        set = function(v) DB().tooltips = v end,
        tooltip = { "Tooltips", "Your best crit, best hit and crit rate under the spell's own tooltip." } })
    L:EditBox({ label = "Quiet below:", width = 70, numeric = true,
        get = function() return tostring(DB().minimum or 0) end,
        set = function(v) DB().minimum = tonumber(v) or 0 end,
        tooltip = { "Quiet below", "New records smaller than this don't say anything (useful while levelling)." } })
    L:Note("Your records, your other characters' and sharing one in chat are in its window: |cFFFFFF00/wmachine crits|r.")
end

function CR:GetQuickStatus()
    local best
    for _, r in pairs(Records()) do
        if r.crit and not r.pvp and (not best or r.crit.value > best.crit.value) then best = r end
    end
    return best and (best.name .. " " .. Commas(best.crit.value)) or "No crits yet"
end

-- ============================================
-- START-UP
-- ============================================

local events = CreateFrame("Frame")

function CR:Initialize()
    DB()
    WM:RegisterEvents(events, { "COMBAT_LOG_EVENT_UNFILTERED" })
    self:HookTooltips()
end

events:SetScript("OnEvent", function()
    if not WM:IsModuleOn("Crits") or not DB().enabled or not CombatLogGetCurrentEventInfo then return end
    local ok, err = pcall(CR.OnCombatEvent, CR, CombatLogGetCurrentEventInfo())
    if not ok then geterrorhandler()(err) end
end)
