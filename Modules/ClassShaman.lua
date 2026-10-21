-- Watching Machine: Shaman Class Tools
-- The totem button: pick a totem set by hovering the button, then click it
-- to drop that set one totem per click, Air, Water, Earth, then Fire (fire
-- always last). Everything here no-ops unless the player is a shaman.
--
-- A secure button can cast only one spell per click, so the drop is a
-- /castsequence macro rebuilt whenever the set changes. The sequence starts
-- again from Air when:
--   * all your totems are gone (destroyed, expired or replaced by nothing);
--     TBC has no Totemic Recall, so "no totems down" is the signal
--   * combat ends (reset=combat)
--   * you Ctrl-click the button (reset=ctrl)
-- Changing the macro is a secure change, so in combat a reset waits until
-- combat ends, which reset=combat covers anyway.

local AddonName, WM = ...
local Shaman = {}
WM:RegisterModule("ClassShaman", Shaman)

Shaman.version = "3.16"

local CLASS = "SHAMAN"
local ICON_TOTEM = "Interface\\Icons\\Spell_Nature_StoneSkinTotem"
local NUM_SETS = 4

-- Drop order: fire is always last
local ELEMENTS = { "AIR", "WATER", "EARTH", "FIRE" }
local ELEMENT_NAMES = { AIR = "Air", WATER = "Water", EARTH = "Earth", FIRE = "Fire" }
Shaman.ELEMENTS = ELEMENTS

-- Every totem, by element, with its rank-1 spell ID (for localized names).
-- Casting by name casts the highest rank.
local TOTEMS = {
    AIR = {
        { "Windfury Totem", 8512 }, { "Grace of Air Totem", 8835 },
        { "Wrath of Air Totem", 3738 }, { "Tranquil Air Totem", 25908 },
        { "Grounding Totem", 8177 }, { "Nature Resistance Totem", 10595 },
        { "Windwall Totem", 15107 }, { "Sentry Totem", 6495 },
    },
    WATER = {
        { "Mana Spring Totem", 5675 }, { "Healing Stream Totem", 5394 },
        { "Mana Tide Totem", 16190 }, { "Poison Cleansing Totem", 8166 },
        { "Disease Cleansing Totem", 8170 }, { "Fire Resistance Totem", 8184 },
    },
    EARTH = {
        { "Strength of Earth Totem", 8075 }, { "Stoneskin Totem", 8071 },
        { "Tremor Totem", 8143 }, { "Earthbind Totem", 2484 },
        { "Stoneclaw Totem", 5730 }, { "Earth Elemental Totem", 2062 },
    },
    FIRE = {
        { "Totem of Wrath", 30706 }, { "Searing Totem", 3599 },
        { "Flametongue Totem", 8227 }, { "Magma Totem", 8190 },
        { "Fire Nova Totem", 1535 }, { "Frost Resistance Totem", 8181 },
        { "Fire Elemental Totem", 2894 },
    },
}
Shaman.TOTEMS = TOTEMS

-- The premade sets. Each element is a preference list: the first totem you
-- know is used, so a set keeps working while you level (Searing until you
-- have Totem of Wrath). icon = the element whose totem is the set's icon.
local PREMADES = {
    { name = "Melee", icon = "AIR",
      AIR = { "Windfury Totem", "Grace of Air Totem" },
      WATER = { "Mana Spring Totem", "Healing Stream Totem" },
      EARTH = { "Strength of Earth Totem", "Stoneskin Totem" },
      FIRE = { "Searing Totem" } },
    { name = "Caster", icon = "FIRE",
      AIR = { "Wrath of Air Totem", "Tranquil Air Totem" },
      WATER = { "Mana Spring Totem", "Healing Stream Totem" },
      EARTH = { "Stoneskin Totem", "Strength of Earth Totem" },
      FIRE = { "Totem of Wrath", "Searing Totem" } },
    { name = "Healer", icon = "WATER",
      AIR = { "Wrath of Air Totem", "Tranquil Air Totem" },
      WATER = { "Healing Stream Totem", "Mana Spring Totem" },
      EARTH = { "Stoneskin Totem", "Strength of Earth Totem" },
      FIRE = { "Searing Totem" } },
    { name = "Tremor", icon = "EARTH",
      AIR = { "Windfury Totem", "Grace of Air Totem" },
      WATER = { "Mana Spring Totem", "Healing Stream Totem" },
      EARTH = { "Tremor Totem" },
      FIRE = { "Searing Totem" } },
}
Shaman.PREMADES = PREMADES

-- A set's element is AUTO (the premade's preference), NONE, or a totem's
-- English name
local AUTO, NONE = "AUTO", "NONE"
Shaman.AUTO, Shaman.NONE = AUTO, NONE

-- ============================================
-- HELPERS
-- ============================================

local function IsPlayerShaman()
    local _, c = UnitClass("player")
    return c == CLASS
end

local CT
local function Tools()
    CT = CT or WM.modules.ClassTools
    return CT
end

function Shaman:Print(msg)
    WM:ModulePrint("ClassShaman", msg)
end

local function Store() return ShamanToolsDB or {} end

local DIR_DEFAULTS = { setDir = "UP" }

function Shaman:InitDB()
    if type(ShamanToolsDB) ~= "table" then ShamanToolsDB = {} end
    local db = ShamanToolsDB
    for key, default in pairs(DIR_DEFAULTS) do
        if db[key] == nil then db[key] = default end
    end
    if type(db.sets) ~= "table" then db.sets = {} end
    for i = 1, NUM_SETS do
        if type(db.sets[i]) ~= "table" then db.sets[i] = { name = PREMADES[i].name } end
    end
    if type(db.selected) ~= "number" or not db.sets[db.selected] then db.selected = 1 end
end

-- Put every set back to its premade
function Shaman:RestorePremades()
    for i = 1, NUM_SETS do ShamanToolsDB.sets[i] = { name = PREMADES[i].name } end
    self:Refresh()
end

-- ============================================
-- KNOWN TOTEMS
-- ============================================

local known = {}                                  -- English name -> entry
local knownByElement = { AIR = {}, WATER = {}, EARTH = {}, FIRE = {} }

function Shaman:ScanSpellbook()
    wipe(known)
    for _, list in pairs(knownByElement) do wipe(list) end
    if not IsPlayerShaman() then return end
    local found = WM.Flyout.ScanSpells(TOTEMS, ICON_TOTEM)
    for element, list in pairs(found) do
        for _, e in ipairs(list) do
            known[e.key] = e
            table.insert(knownByElement[element], e)
        end
    end
end

function Shaman:KnownTotems(element) return knownByElement[element] end

-- The totem a set drops for an element: an entry, or nil for none
function Shaman:ResolveTotem(i, element)
    local set = Store().sets and Store().sets[i]
    local choice = set and set[element] or AUTO
    if choice == NONE then return nil end
    if choice ~= AUTO then return known[choice] end
    for _, name in ipairs(PREMADES[i] and PREMADES[i][element] or {}) do
        if known[name] then return known[name] end
    end
end

function Shaman:SetName(i)
    local set = Store().sets and Store().sets[i]
    local name = set and set.name
    if not name or name == "" then name = "Set " .. i end
    return name
end

function Shaman:SetIcon(i)
    local prefer = PREMADES[i] and PREMADES[i].icon or "FIRE"
    local e = self:ResolveTotem(i, prefer)
    if e then return e.icon end
    for _, element in ipairs(ELEMENTS) do
        e = self:ResolveTotem(i, element)
        if e then return e.icon end
    end
    return ICON_TOTEM
end

-- ============================================
-- THE CAST SEQUENCE
-- ============================================

-- Bumped on every reset. The game keeps a sequence's progress keyed by its
-- text, so a new timeout (an hour plus n seconds: never reached) makes a
-- new sequence that starts from the top.
local resetCount = 0

function Shaman:MacroText(i)
    local names = {}
    for _, element in ipairs(ELEMENTS) do
        local e = self:ResolveTotem(i, element)
        if e then names[#names + 1] = e.name end
    end
    if #names == 0 then return "" end
    return "/castsequence reset=combat/ctrl/" .. (3600 + resetCount) .. " " .. table.concat(names, ", ")
end

local pendingApply = false

-- Write the selected set's sequence onto the button (secure: out of combat)
function Shaman:ApplyMacro()
    local a = self.flyout.anchor
    if not a then return end
    if InCombatLockdown() then pendingApply = true return end
    pendingApply = false
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    a:RegisterForClicks(keyDown and "LeftButtonDown" or "LeftButtonUp", "RightButtonUp")
    a:SetAttribute("macrotext", self:MacroText(Store().selected or 1))
end

-- Start the sequence again from Air
function Shaman:ResetSequence()
    resetCount = resetCount + 1
    self:ApplyMacro()
end

-- Are any totems down? nil when the client can't tell. Slots: 1 fire,
-- 2 earth, 3 water, 4 air.
function Shaman:AnyTotemDown()
    if type(GetTotemInfo) ~= "function" then return nil end
    for slot = 1, 4 do
        local ok, have, name = pcall(GetTotemInfo, slot)
        if ok and have and type(name) == "string" and name ~= "" then return true end
    end
    return false
end

local totemsWereDown = false

function Shaman:OnTotemUpdate()
    local down = self:AnyTotemDown()
    if down == nil then return end
    if totemsWereDown and not down then self:ResetSequence() end
    totemsWereDown = down
end

function Shaman:SelectSet(i)
    if InCombatLockdown() or not Store().sets[i] then return end
    Store().selected = i
    resetCount = resetCount + 1   -- a new set starts from Air
    self:Refresh()
end

-- ============================================
-- THE BUTTON (shared engine: Modules/ClassFlyout.lua)
-- ============================================

local setEntries = {}

local function SetTooltip(i)
    local lines = { Shaman:SetName(i) }
    for _, element in ipairs(ELEMENTS) do
        local e = Shaman:ResolveTotem(i, element)
        lines[#lines + 1] = ELEMENT_NAMES[element] .. ": " .. (e and e.name or "none")
    end
    lines[#lines + 1] = i == Store().selected and "In use." or "Click to use this set."
    return lines
end

local function BuildSetEntries()
    wipe(setEntries)
    for i = 1, NUM_SETS do
        setEntries[i] = {
            name = Shaman:SetName(i), icon = Shaman:SetIcon(i),
            select = function() Shaman:SelectSet(i) end,
            tooltip = SetTooltip(i),
        }
    end
end

local function AnchorTooltip(tip, inCombat)
    local i = Store().selected or 1
    tip:AddLine("Totems: " .. Shaman:SetName(i), 1, 0.8, 0)
    for _, element in ipairs(ELEMENTS) do
        local e = Shaman:ResolveTotem(i, element)
        tip:AddDoubleLine(ELEMENT_NAMES[element], e and e.name or "none", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tip:AddLine(" ")
    tip:AddLine("Click: drop the next totem (Air, Water, Earth, then Fire).", 0.9, 0.9, 0.9, true)
    tip:AddLine("Ctrl-click: start again from Air.", 0.9, 0.9, 0.9, true)
    tip:AddLine("Right-click: edit sets. Shift-drag: move.", 0.9, 0.9, 0.9, true)
    if inCombat then
        tip:AddLine("Change set out of combat.", 0.8, 0.4, 0.4)
    end
end

local function SetupAnchor(a)
    a:SetAttribute("type", "macro")
    a:SetAttribute("macrotext", "")
    a:SetAttribute("type2", "stop")          -- right-click opens the editor instead
    a:SetAttribute("shift-type1", "stop")    -- shift is for dragging, not casting
    a.label = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    a.label:SetPoint("TOP", a, "BOTTOM", 0, -2)
    a:SetScript("PostClick", function(_, button)
        if button == "RightButton" then Shaman:ToggleEditor() end
    end)
end

local totemFlyout = WM.Flyout.New({
    class = CLASS, feature = "totemButton",
    anchorName = "WM_TotemAnchor", buttonPrefix = "WM_TotemSetBtn",
    title = "Totems", emptyText = "No totem sets.",
    store = Store, posX = "buttonX", posY = "buttonY", defaultX = 284,
    defaults = DIR_DEFAULTS,
    secureAnchor = true, dragNeedsShift = true,
    setupAnchor = SetupAnchor,
    anchorTooltip = AnchorTooltip,
    scan = function()
        Shaman:ScanSpellbook()
        BuildSetEntries()
        Shaman:ApplyMacro()
    end,
    groups = function() return { { entries = setEntries, dirKey = "setDir" } } end,
    setIcon = function(icon, fly)
        local i = Store().selected or 1
        icon:SetTexture(Shaman:SetIcon(i))
        if fly.anchor and fly.anchor.label then fly.anchor.label:SetText(Shaman:SetName(i)) end
    end,
})
Shaman.flyout = totemFlyout

-- Rebuild the button (out of combat; otherwise once combat ends)
function Shaman:Refresh()
    if InCombatLockdown() then pendingApply = true
    else totemFlyout:UpdateVisibility() end
    if self.editor and self.editor:IsShown() then self.editor:Refresh() end
end

-- ============================================
-- SET EDITOR
-- ============================================

local function ElementOptions(i, element)
    return function()
        local opts = {}
        if PREMADES[i] and PREMADES[i][element] then
            local auto
            for _, name in ipairs(PREMADES[i][element]) do
                if known[name] then auto = known[name].name break end
            end
            opts[#opts + 1] = { value = AUTO, text = "Auto (" .. (auto or "none known") .. ")" }
        end
        opts[#opts + 1] = { value = NONE, text = "None" }
        for _, e in ipairs(knownByElement[element]) do
            opts[#opts + 1] = { value = e.key, text = e.name }
        end
        return opts
    end
end

function Shaman:CreateEditor()
    if self.editor then return self.editor end
    local panel = WM.UI:CreatePanel({ name = "WM_TotemSetsFrame", title = "Totem Sets", titleColor = "0070DE", width = 400 })
    local L = panel.layout
    L:Note("Hover the totem button to pick a set; click it to drop the set one totem per click, Air, Water, Earth, then Fire. Auto picks the premade's best totem you know.")
    for i = 1, NUM_SETS do
        L:Header("Set " .. i)
        local _, row = L:EditBox({
            label = "Name:", width = 140, maxLetters = 24,
            get = function() return Store().sets[i].name end,
            set = function(v) Store().sets[i].name = v; Shaman:Refresh() end,
        })
        row:RightButton({
            text = function() return Store().selected == i and "In use" or "Use this set" end,
            width = 100,
            disabled = function() return Store().selected == i end,
            onClick = function() Shaman:SelectSet(i) end,
        }, 8)
        for pair = 0, 1 do
            local r = L:Row(28)
            for col = 1, 2 do
                local element = ELEMENTS[pair * 2 + col]
                r:Dropdown({
                    label = ELEMENT_NAMES[element] .. ":", width = 115,
                    options = ElementOptions(i, element),
                    get = function() return Store().sets[i][element] or AUTO end,
                    set = function(v)
                        Store().sets[i][element] = (v ~= AUTO) and v or nil
                        Shaman:Refresh()
                    end,
                }, col == 1 and 12 or 192)
            end
        end
    end
    panel:AddFooterButton({ text = "Restore premades", width = 130, confirm = true,
        onClick = function() Shaman:RestorePremades() end,
        tooltip = { "Restore premades", "Puts all four sets back to Melee, Caster, Healer and Tremor." } })
    panel:AddFooterText({ text = function()
        return InCombatLockdown() and "Changes apply after combat." or ""
    end }, "RIGHT")
    panel:Finish()
    self.editor = panel
    return panel
end

function Shaman:ToggleEditor()
    if not IsPlayerShaman() then
        self:Print("Totem sets are for shamans.")
        return
    end
    local p = self:CreateEditor()
    if p:IsShown() then p:Hide() else
        self:ScanSpellbook()
        p:Show()
    end
end

-- ============================================
-- REGISTRATION
-- ============================================

local eventFrame = CreateFrame("Frame")

function Shaman:Initialize()
    self:InitDB()
    local tools = Tools()
    if not tools then return end

    local rebuild = function() Shaman:Refresh() end
    tools:RegisterFeature(CLASS, {
        key = "totemButton", name = "Show the totem button",
        desc = "Hover to pick a totem set; click to drop it one totem per click, Air, Water, Earth, then Fire. Starts again from Air when your totems are gone, after combat, or on Ctrl-click. Right-click to edit the sets.",
        default = true,
        onToggle = rebuild,
    })
    WM.Flyout.DirectionFeature(tools, CLASS, "setDir", "Totem sets expand", "totem set",
        Store, DIR_DEFAULTS.setDir, rebuild)

    if IsPlayerShaman() then
        totemFlyout:CreateAnchor()
        WM:RegisterEvents(eventFrame, { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_TOTEM_UPDATE" })
        totemsWereDown = self:AnyTotemDown() or false
        -- Spellbook isn't reliably populated the instant we initialise
        WM.RunAfter(2, function() Shaman:Refresh() end)
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if not IsPlayerShaman() then return end
    if event == "PLAYER_TOTEM_UPDATE" then
        Shaman:OnTotemUpdate()
    elseif InCombatLockdown() then
        return   -- secure changes wait for combat to end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then totemFlyout:UpdateVisibility() end
    else
        WM.RunAfter(1, function() Shaman:Refresh() end)
    end
end)

function Shaman:IsPendingApply() return pendingApply end
