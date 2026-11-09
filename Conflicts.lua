-- Watching Machine: other addons that do a module's job
-- At login, if a module that's on for this character has another addon
-- doing the same job enabled too, a window says so and offers, for each:
--   * turn the module off in Watching Machine (for this character)
--   * disable the other addon (for this character; takes a reload)
--   * keep both (not asked again for that pair on this character)
-- /wmachine conflicts shows the list any time, kept pairs included.

local AddonName, WM = ...
local Conflicts = {}
WM.Conflicts = Conflicts

-- module -> addons doing the same job, and what clashes
Conflicts.LIST = {
    ArmorySnap = { { "ArmorySnap", "Both inspect your raid; Watching Machine's ArmorySnap stands aside while the addon runs." } },
    GuildRoster = { { "Guild_Roster_Manager", "Both keep the guild's records; Roster Manager leaves the syncing to it, and both log the roster." } },
    LootCouncil = {
        { "RCLootCouncil_Classic", "Both run loot council sessions; Loot Council only records awards while it runs." },
        { "RCLootCouncil", "Both run loot council sessions; Loot Council only records awards while it runs." },
        { "Gargul", "Both run roll-offs and award loot by trade; Loot Council already reads Gargul's saved history." },
    },
    GearScore = {
        { "GearScoreTBCClassic", "Both put a GearScore on tooltips and the character sheet." },
        { "GearScore", "Both put a GearScore on tooltips and the character sheet." },
        { "TacoTip", "Both put a GearScore on tooltips." },
    },
    GearSets = {
        { "ItemRack", "Both save and swap gear sets, and both can swap on a spec change or mounting." },
        { "Outfitter", "Both save and swap gear sets." },
    },
    FrameMover = {
        { "BlizzMove", "Both move and resize the game's windows, and fight over where they go." },
        { "MoveAnything", "Both move the game's windows." },
    },
    Hazards = { { "GTFO", "Both sound an alarm when you stand in something harmful (two alarms at once)." } },
    Attunements = { { "Attune", "Both track attunements and both talk to the guild about them." } },
    WorldTimers = { { "NovaWorldBuffs", "Both time world buffs, Songflowers and the Darkmoon Faire and announce them." } },
    InstanceTracker = { { "NovaInstanceTracker", "Both count your instances per hour and per day and log your runs." } },
    Ogrila = { { "Ogri'Lazy", "Both track the Ogri'la relic and Apexis tools." } },
    DamageMeter = {
        { "Details", "Both count damage, healing and threat from the combat log: two meters do the same work in every fight." },
        { "Recount", "Both count damage and healing from the combat log: two meters do the same work in every fight." },
        { "Skada", "Both count damage and healing from the combat log: two meters do the same work in every fight." },
    },
    Crits = { { "CritMatic", "Both record your biggest hits and heals and announce new ones." } },
    GuildInvite = { { "GuildRaidInvite", "Both invite guildmates to the group when they ask." } },
    LootBrowser = { { "AtlasLootClassic", "Both browse boss loot, and both add where an item drops to tooltips." } },
    AutoLogger = {
        { "LoggerHead", "Both switch the combat log on in raids." },
        { "AutoCombatLogger", "Both switch the combat log on in raids." },
    },
}

local function Loaded(name)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not f then return false end
    local ok, loaded = pcall(f, name)
    return ok and loaded and true or false
end
Conflicts.Loaded = Loaded

-- The addon's title as the AddOns list shows it (colour codes taken out)
function Conflicts.Title(name)
    local f = (C_AddOns and C_AddOns.GetAddOnInfo) or rawget(_G, "GetAddOnInfo")
    local title
    if f then
        local ok, _, t = pcall(f, name)
        if ok and type(t) == "string" and t ~= "" then title = t end
    end
    title = title or name
    return (title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Kept()
    local c = WM:CharState()
    c.conflictsKept = c.conflictsKept or {}
    return c.conflictsKept
end

-- The clashes right now: { module, addon, why, kept }
function Conflicts:Find(includeKept)
    local out = {}
    local kept = Kept()
    for module, addons in pairs(self.LIST) do
        if WM.modules[module] and WM:IsModuleOn(module) then
            for _, a in ipairs(addons) do
                local key = module .. ":" .. a[1]
                if Loaded(a[1]) and (includeKept or not kept[key]) then
                    out[#out + 1] = { module = module, addon = a[1], why = a[2], kept = kept[key] or nil }
                end
            end
        end
    end
    table.sort(out, function(x, y)
        if x.module ~= y.module then return x.module < y.module end
        return x.addon < y.addon
    end)
    return out
end

-- ============================================
-- WHAT THE BUTTONS DO
-- ============================================

function Conflicts:TurnOffModule(c)
    WM:SetModuleOn(c.module, false)
    WM:Print("Turned off " .. self.ModuleTitle(c.module) .. " for this character: " .. self.Title(c.addon) .. " does it.")
    self:Refresh()
end

function Conflicts:DisableAddon(c)
    local f = (C_AddOns and C_AddOns.DisableAddOn) or rawget(_G, "DisableAddOn")
    if not f then return false end
    pcall(f, c.addon, UnitName("player"))
    self.needReload = true
    c.disabled = true
    WM:Print(self.Title(c.addon) .. " is disabled for this character from the next reload (|cFFFFFF00/reload|r).")
    self:Refresh()
    return true
end

function Conflicts:Keep(c)
    Kept()[c.module .. ":" .. c.addon] = true
    c.kept = true
    self:Refresh()
end

function Conflicts.ModuleTitle(module)
    local info = WM.MODULE_INFO and WM.MODULE_INFO[module]
    return (info and info.title) or module
end

-- ============================================
-- THE WINDOW
-- ============================================

local panel
Conflicts.shown = {}

local function Row(i)
    local row = panel.list.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, panel.list)
    row:SetHeight(64)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 68)
    row:SetPoint("RIGHT", panel.list, "RIGHT", 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 2, -2)
    row.text:SetPoint("RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row.buttons = {}
    for b = 1, 3 do
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetHeight(20)
        if b == 1 then btn:SetPoint("BOTTOMLEFT", 2, 2) else btn:SetPoint("LEFT", row.buttons[b - 1], "RIGHT", 6, 0) end
        row.buttons[b] = btn
    end
    panel.list.rows[i] = row
    return row
end

function Conflicts:Refresh()
    if not panel or not panel:IsShown() then return end
    local list = self.shown
    for i = 1, math.max(#list, #panel.list.rows) do
        local c = list[i]
        local row = c and Row(i) or panel.list.rows[i]
        if c then
            local state = ""
            if c.disabled then state = "   |cFF33FF33disabled at the next reload|r"
            elseif not WM:IsModuleOn(c.module) then state = "   |cFF33FF33module turned off|r"
            elseif c.kept then state = "   |cFF888888keeping both|r" end
            row.text:SetText("|cFFFFD100" .. self.ModuleTitle(c.module) .. "|r and |cFFFFD100" .. self.Title(c.addon)
                .. "|r do the same job." .. state .. "\n" .. c.why)
            local done = c.disabled or not WM:IsModuleOn(c.module)
            local specs = {
                { "Turn off " .. self.ModuleTitle(c.module), function() Conflicts:TurnOffModule(c) end },
                { "Disable " .. self.Title(c.addon), function() Conflicts:DisableAddon(c) end },
                { "Keep both", function() Conflicts:Keep(c) end },
            }
            for b, spec in ipairs(specs) do
                local btn = row.buttons[b]
                btn:SetText(spec[1])
                btn:SetWidth(math.min(200, math.max(90, #spec[1] * 6 + 20)))
                btn:SetScript("OnClick", spec[2])
                if done or (b == 3 and c.kept) then btn:Disable() else btn:Enable() end
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    if panel.reloadBtn then panel.reloadBtn:SetShown(self.needReload and true or false) end
end

function Conflicts:Show(list)
    self.shown = list or self:Find(true)
    if not panel then
        panel = WM.UI:CreatePanel({ name = "WM_ConflictsFrame", title = "Addons doing the same job", titleColor = "FFAA33",
            width = 560, height = 360, minHeight = 200, scroll = false, resizable = { 460, 200, 1000, 1000 },
            onRefresh = function() Conflicts:Refresh() end, onResize = function() Conflicts:Refresh() end })
        local L = panel.layout
        L:Note("These Watching Machine modules have another addon doing the same job enabled with them, so you may get"
            .. " two alarms, two announcements or two windows fighting. For each, turn the module off here, disable the"
            .. " other addon, or keep both.")
        local fill = L:Fill(140)
        panel.list = CreateFrame("Frame", nil, fill)
        panel.list:SetAllPoints(fill)
        panel.list.rows = {}
        panel.reloadBtn = panel:AddFooterButton({ text = "Reload now", width = 100, onClick = function() if ReloadUI then ReloadUI() end end,
            tooltip = { "Reload", "Disabled addons stop after a reload." } }, "RIGHT")
        panel:AddFooterButton({ text = "Close", width = 70, onClick = function() panel:Hide() end }, "RIGHT")
        panel:Finish()
    end
    if not panel:IsShown() then panel:Show() end
    self:Refresh()
end

function Conflicts:Hide() if panel then panel:Hide() end end

-- At login: warn about any clash not kept
function Conflicts:CheckAtLogin()
    if WatchingMachineDB and WatchingMachineDB.conflictWarn == false then return 0 end
    local list = self:Find(false)
    if #list > 0 then self:Show(list) end
    return #list
end

-- /wmachine conflicts
function Conflicts:Command()
    local list = self:Find(true)
    if #list == 0 then
        WM:Print("No other addon is doing the job of a module you have on.")
        self:Hide()
        return
    end
    self:Show(list)
end
