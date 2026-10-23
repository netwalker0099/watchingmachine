-- Watching Machine: setup
-- The first time you log in on a character everything is off, and this
-- asks how you'd like to set it up:
--   Guided setup  a page per module: what it does and how it works, a
--                 switch to turn it on, and its main settings, explained
--   Quick setup   one checklist of every module, with a few presets
--   Copy          another character's modules and settings
-- A character that used Watching Machine before this keeps what it had and
-- is offered the same choices once. /wmachine setup brings it back.
--
-- A module adds its settings to its guided page with
--   function Module:SetupPage(L) ... end
-- where L is a panel layout (L:Note, L:Header, L:Checkbox, L:Dropdown,
-- L:Slider, L:EditBox, L:Buttons, ...). It's called once, when the page is
-- first shown, and must work before the module has started (the module may
-- be off): read and write settings through the module's own DB function.

local AddonName, WM = ...
local S = {}
WM.Setup = S

local function Info(name) return WM.MODULE_INFO and WM.MODULE_INFO[name] end
local function Hex(c) return string.format("%02x%02x%02x", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255) end
local function Title(name)
    local info = Info(name)
    if not info then return name end
    return "|cFF" .. Hex(info.color or { 1, 1, 1 }) .. info.title .. "|r"
end

-- Every module the setup shows, in dashboard order
function S:Modules()
    local out = {}
    for _, g in ipairs(WM.MODULE_GROUPS or {}) do
        for _, name in ipairs(g.modules) do
            if WM.modules[name] and Info(name) then out[#out + 1] = { name = name, group = g.title } end
        end
    end
    return out
end

local PRESETS = {
    { key = "raid", text = "Raiding", tip = "Raid and dungeon tools, class tools, logging and your characters.",
        modules = { "BuffCheck", "DebuffTracker", "ClassTools", "AuraRange", "ArmorySnap", "WorldTimers", "LootBrowser",
            "GearScore", "Attunements", "Hazards", "GearSets", "AutoLogger", "InstanceTracker", "AltTracker", "Crits" } },
    { key = "guild", text = "Guild officer", tip = "Recruiting, invites, chat tools and logs.",
        modules = { "GuildInvite", "Recruiter", "PvPTracker", "ChatFilter", "KeywordMonitor", "ServicesParser",
            "WhisperLogs", "MailLogger", "AltTracker", "ArmorySnap" } },
    { key = "all", text = "Everything", tip = "Every module on." },
    { key = "none", text = "Nothing", tip = "Every module off." },
}
S.PRESETS = PRESETS

local function Done(how)
    local c = WM:CharState()
    c.setup = "done"
    c.setupHow = how
    c.defaultOn = c.defaultOn and true or false
end

function S:OnCount()
    local n = 0
    for _, m in ipairs(self:Modules()) do if WM:IsModuleOn(m.name) then n = n + 1 end end
    return n
end

-- ============================================
-- WELCOME
-- ============================================

local welcome

function S:OnLogin()
    local c = WM:CharState()
    if c.setup == "new" or c.setup == "offer" then self:ShowWelcome() end
end

function S:ShowWelcome()
    if not welcome then
        welcome = WM.UI:CreatePanel({ name = "WM_SetupWelcome", title = "Welcome to Watching Machine", width = 460,
            strata = "DIALOG" })
        local L = welcome.layout
        L:Note(function()
            local c = WM:CharState()
            if c.setup == "offer" then
                return "|cFFFFFFFFNew: modules are switched on and off per character, and each character has its own settings.|r"
                    .. " Everything you were using is still on. Would you like to go through the setup?"
            elseif c.setup == "done" then
                return "|cFFFFFFFF" .. S:OnCount() .. " modules are on for this character.|r Run the setup again?"
            end
            return "|cFFFFFFFFEverything is off on this character.|r Watching Machine is a toolbox of " .. #S:Modules()
                .. " modules for raiding, guilds and logging. Pick how you'd like to choose the ones you want."
        end)
        L:Space(6)
        L:Buttons({ { text = "Guided setup", width = 140, onClick = function() welcome:Hide(); S:OpenGuided() end,
            tooltip = { "Guided setup", "A page for each module: what it does, how it works, a switch to turn it on and"
                .. " its main settings. The best way to learn what's here." } } })
        L:Note("A page per module: what it does, turn it on, and its main settings explained.")
        L:Buttons({ { text = "Quick setup", width = 140, onClick = function() welcome:Hide(); S:OpenQuick() end,
            tooltip = { "Quick setup", "One checklist of every module, with presets. Settings stay at their defaults." } } })
        L:Note("One checklist of every module, with presets (Raiding, Guild officer, ...).")
        L:Header("Copy another character")
        welcome.copyFrom = nil
        L:Dropdown({ label = "From:", width = 200,
            options = function()
                local o = {}
                for _, k in ipairs(WM.Profiles:Characters()) do o[#o + 1] = { value = k, text = k } end
                if #o == 0 then o[1] = { value = "", text = "(no other characters yet)" } end
                return o
            end,
            get = function() return welcome.copyFrom end,
            set = function(v) welcome.copyFrom = v ~= "" and v or nil end })
        L:Buttons({ { text = "Copy modules and settings", width = 200, onClick = function()
            if not welcome.copyFrom then WM:Print("Pick a character to copy from first."); return end
            S:CopyFrom(welcome.copyFrom)
            welcome:Hide()
        end } })
        welcome:AddFooterButton({ text = "Later", width = 90, onClick = function() S:Later() end }, "RIGHT")
        welcome:Finish()
    end
    welcome:Show()
    welcome:Refresh()
    return welcome
end

function S:Later()
    if welcome then welcome:Hide() end
    local c = WM:CharState()
    if c.setup == "new" then
        c.setup = "later"
        WM:Print("Everything is off on this character for now. Type |cFFFFFF00/wmachine setup|r when you're ready.")
    elseif c.setup == "offer" then
        c.setup = "done"
        WM:Print("No problem. |cFFFFFF00/wmachine setup|r brings the setup back any time.")
    end
end

-- Copy another character's modules and settings. With modules already
-- running, their settings can't be swapped under them: copy and reload.
function S:CopyFrom(other)
    local running = false
    for _, m in pairs(WM.modules) do if m._wmStarted then running = true end end
    local function Copy()
        if not WM.Profiles:CopyFrom(other) then return false end
        Done("copy")
        return true
    end
    if running then
        WM:Confirm("Copying " .. other .. "'s setup reloads your interface. Copy and reload now?", function()
            if Copy() and ReloadUI then ReloadUI() end
        end)
        return true
    end
    if not Copy() then return false end
    for _, m in ipairs(self:Modules()) do
        if WM:IsModuleOn(m.name) then WM:SetModuleOn(m.name, true) end
    end
    WM:Print("Copied " .. other .. "'s modules and settings.")
    return true
end

-- ============================================
-- QUICK SETUP
-- ============================================

local quick

function S:ApplyPreset(key)
    local draft = quick and quick.draft
    if not draft then return end
    local set
    for _, p in ipairs(PRESETS) do if p.key == key then set = p end end
    if not set then return end
    local want = {}
    for _, n in ipairs(set.modules or {}) do want[n] = true end
    for _, m in ipairs(self:Modules()) do
        draft[m.name] = (key == "all") or (key ~= "none" and want[m.name] == true)
    end
    quick:Refresh()
end

local function LinksText(name)
    local parts = {}
    for other, what in pairs(WM.MODULE_LINKS[name] or {}) do
        local info = Info(other)
        parts[#parts + 1] = "With " .. (info and info.title or other) .. ": " .. what .. "."
    end
    for owner, links in pairs(WM.MODULE_LINKS) do
        if links[name] and owner ~= name then
            local info = Info(owner)
            parts[#parts + 1] = "With " .. (info and info.title or owner) .. ": " .. links[name] .. "."
        end
    end
    table.sort(parts)
    return table.concat(parts, " ")
end
S.LinksText = LinksText

function S:OpenQuick()
    if not quick then
        quick = WM.UI:CreatePanel({ name = "WM_SetupQuick", title = "Quick setup", width = 520, maxHeight = 640 })
        quick.draft = {}
        local L = quick.layout
        L:Note("Tick the modules you want on this character. You can change this any time with the switch on each"
            .. " dashboard card, or run the guided setup to learn what each one does.")
        local btns = {}
        for _, p in ipairs(PRESETS) do
            btns[#btns + 1] = { text = p.text, width = 100, tooltip = { p.text, p.tip },
                onClick = function() S:ApplyPreset(p.key) end }
        end
        L:Buttons(btns)
        local group
        for _, m in ipairs(self:Modules()) do
            if m.group ~= group then
                group = m.group
                L:Header(group)
            end
            local name, info = m.name, Info(m.name)
            L:Checkbox({
                label = function()
                    local extra = ""
                    if name == "ClassTools" and WM.modules.ClassTools and WM.modules.ClassTools.GetPlayerClassLabel then
                        extra = " |cFF888888(" .. WM.modules.ClassTools:GetPlayerClassLabel() .. " and general)|r"
                    end
                    return Title(name) .. extra .. "  |cFFAAAAAA" .. (info.desc or "") .. "|r"
                end,
                get = function() return quick.draft[name] end,
                set = function(v) quick.draft[name] = v end,
                tooltip = function()
                    local links = LinksText(name)
                    return { info.title, (info.about or info.desc or "") .. (links ~= "" and ("\n\n" .. links) or "") }
                end,
            })
        end
        quick:AddFooterButton({ text = "Turn on", width = 100, onClick = function() S:ApplyQuick() end }, "RIGHT")
        quick:AddFooterButton({ text = "Guided instead", width = 120, onClick = function() quick:Hide(); S:OpenGuided() end }, "LEFT")
        quick:Finish()
    end
    quick.draft = {}
    for _, m in ipairs(self:Modules()) do quick.draft[m.name] = WM:IsModuleOn(m.name) end
    quick:Show()
    quick:Refresh()
    return quick
end

function S:ApplyQuick()
    if not quick then return end
    local on = {}
    for _, m in ipairs(self:Modules()) do
        local want = quick.draft[m.name] and true or false
        if want ~= WM:IsModuleOn(m.name) then WM:SetModuleOn(m.name, want)
        else WM:CharState().modules[m.name] = want end
        if want then on[#on + 1] = (Info(m.name) or {}).title or m.name end
    end
    Done("quick")
    quick:Hide()
    if #on == 0 then
        WM:Print("Everything is off on this character. |cFFFFFF00/wmachine setup|r any time.")
    else
        WM:Print("On for this character: " .. table.concat(on, ", ") .. ". Their settings are in /wmachine (the dashboard).")
    end
    return on
end

-- ============================================
-- GUIDED SETUP
-- ============================================

local guided

-- The pages, in order: introduction, one per module, the end
function S:Pages()
    local pages = { { kind = "intro" } }
    for _, m in ipairs(self:Modules()) do pages[#pages + 1] = { kind = "module", name = m.name, group = m.group } end
    pages[#pages + 1] = { kind = "finish" }
    return pages
end

local function BuildIntro(L)
    L:Header("How Watching Machine works")
    L:Note("Watching Machine is one addon made of modules. Each one does one job: checking raid buffs, tracking"
        .. " debuffs on the boss, logging your mail and trades, swapping gear sets, and so on. Over the next pages"
        .. " you'll meet each module: what it does, how it works, and its main settings. Turn on the ones you want;"
        .. " skip the rest. Nothing you choose here is final.")
    L:Header("Per character")
    L:Note("Which modules are on, and every module's settings, belong to this character. Your other characters"
        .. " keep their own (you can copy one character's setup to another from the welcome window). Things that are"
        .. " about all your characters, like Your Characters' gold totals or the instance log, are shared.")
    L:Header("The dashboard")
    L:Note("|cFFFFFFFF/wmachine|r (or left-click the minimap button) opens the dashboard: a card per module, in"
        .. " three groups. Each card has an on/off switch (for this character), an Open button for the module's"
        .. " window with all its settings, and a |cFFFFFFFF...|r menu (or right-click) with its tools. Hover a card"
        .. " to read what it does and how it's doing.")
    L:Header("Commands")
    L:Note("|cFFFFFF00/wmachine help|r lists every command. Most modules have their own, e.g. |cFFFFFF00/wmachine"
        .. " loot|r for the Loot Browser; each page here tells you its command. |cFFFFFF00/wmachine setup|r brings this"
        .. " setup back.")
    L:Header("Errors")
    L:Note("If a module ever misbehaves, |cFFFFFF00/wmachine errors|r shows what went wrong (handy to send to the"
        .. " author).")
end

local function BuildModule(L, name)
    local info = Info(name) or { title = name }
    local m = WM.modules[name]
    L:Header(Title(name) .. "  |cFF888888" .. (info.desc or "") .. "|r")
    L:Note(info.about or info.desc or "")
    L:Checkbox({
        label = function() return "Turn on " .. info.title .. " for this character" end,
        get = function() return WM:IsModuleOn(name) end,
        set = function(v) WM:SetModuleOn(name, v); if guided then guided:Refresh() end end,
        font = "GameFontNormal",
    })
    local links = LinksText(name)
    if links ~= "" then L:Note("|cFFCCCC99Works with other modules:|r " .. links) end
    if m and m.SetupPage then
        L:Header("Settings")
        local ok, err = pcall(m.SetupPage, m, L)
        if not ok then
            geterrorhandler()(name .. ":SetupPage failed: " .. tostring(err))
            L:Note("|cFFFF6666This page couldn't be shown (see /wmachine errors).|r")
        end
    end
    L:Separator()
    L:Note("Later: " .. (info.command and ("|cFFFFFF00/wmachine " .. info.command .. "|r, or ") or "")
        .. "the " .. info.title .. " card on the dashboard has every setting.")
end

local function BuildFinish(L)
    L:Header("All set")
    L:Note(function()
        local on, off = {}, {}
        for _, m in ipairs(S:Modules()) do
            local t = (Info(m.name) or {}).title or m.name
            if WM:IsModuleOn(m.name) then on[#on + 1] = t else off[#off + 1] = t end
        end
        return "|cFF33FF33On:|r " .. (#on > 0 and table.concat(on, ", ") or "nothing") .. "\n\n|cFF888888Off:|r "
            .. (#off > 0 and table.concat(off, ", ") or "nothing")
    end)
    L:Note("Change any of this from the dashboard (|cFFFFFF00/wmachine|r): each card's switch turns a module on or"
        .. " off for this character, and Open has all its settings. |cFFFFFF00/wmachine setup|r brings this back.")
end

function S:OpenGuided(startAt)
    if not guided then
        guided = WM.UI:CreatePanel({ name = "WM_SetupGuided", title = "Watching Machine setup", width = 560,
            height = 600 })
        guided.pages = self:Pages()
        guided.built = {}
        guided.stepText = guided:AddFooterText({ text = function()
            local p = guided.pages[guided.index or 1]
            local where = p.group and (p.group .. ", ") or ""
            return string.format("|cFF888888%sstep %d of %d|r", where, guided.index or 1, #guided.pages)
        end }, "CENTER")
        guided.backBtn = guided:AddFooterButton({ text = "Back", width = 80, onClick = function() S:Go(-1) end,
            disabled = function() return (guided.index or 1) <= 1 end }, "LEFT")
        guided.nextBtn = guided:AddFooterButton({ text = function()
            return (guided.index or 1) >= #guided.pages and "Finish" or "Next"
        end, width = 90, onClick = function() S:Go(1) end }, "RIGHT")
        guided:Finish()
    end
    guided:Show()
    self:ShowStep(startAt or 1)
    return guided
end

function S:ShowStep(i)
    local g = guided
    i = math.max(1, math.min(#g.pages, i))
    g.index = i
    local spec = g.pages[i]
    local page = g.built[i]
    if not page then
        page = g:NewPage()
        g.built[i] = page
        local L = page.layout
        if spec.kind == "intro" then BuildIntro(L)
        elseif spec.kind == "finish" then BuildFinish(L)
        else BuildModule(L, spec.name) end
        L:Reflow()
    end
    g:ShowPage(page)
    return page
end

function S:Go(step)
    local g = guided
    if not g then return end
    local i = (g.index or 1) + step
    if i > #g.pages then
        Done("guided")
        g:Hide()
        WM:Print("Setup done: " .. self:OnCount() .. " modules on for this character. /wmachine opens the dashboard.")
        return
    end
    self:ShowStep(i)
end

-- Jump to a module's page
function S:OpenModulePage(name)
    local pages = self:Pages()
    for i, p in ipairs(pages) do if p.name == name then return self:OpenGuided(i) end end
end
