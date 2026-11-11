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
--
-- The button has a key binding (Bindings.xml: a click on the secure button,
-- so it works in combat), and timers above it for the totems you have down.

local AddonName, WM = ...
local Shaman = {}
WM:RegisterModule("ClassShaman", Shaman)

-- The key binding's name in the game's Key Bindings
local BINDING = "CLICK WM_TotemAnchor:LeftButton"
Shaman.BINDING = BINDING
_G["BINDING_NAME_" .. BINDING] = "Drop the next totem (totem button)"

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

-- ============================================
-- TOTEM TIMERS: the totems you have down, above the button
-- ============================================

local TOTEM_SLOTS = { FIRE = 1, EARTH = 2, WATER = 3, AIR = 4 }
Shaman.TOTEM_SLOTS = TOTEM_SLOTS
local TIMER_SIZE, TIMER_GAP = 20, 3

-- What's down in a totem slot: name, seconds left, icon (nil: nothing)
function Shaman:TotemLeft(slot, now)
    if type(GetTotemInfo) ~= "function" then return nil end
    local ok, have, name, start, duration, icon = pcall(GetTotemInfo, slot)
    if not ok or not have or type(name) ~= "string" or name == "" then return nil end
    local left = (tonumber(start) or 0) + (tonumber(duration) or 0) - (now or GetTime())
    if left <= 0 then return nil end
    return name, left, icon
end

function Shaman.TimeText(left)
    if left >= 60 then return string.format("%dm", math.floor(left / 60 + 0.5)) end
    return string.format("%d", math.floor(left + 0.5))
end

function Shaman:CreateTimers(anchor)
    if self.timers or not anchor then return self.timers end
    local f = CreateFrame("Frame", "WM_TotemTimers", anchor)
    f:SetSize(#ELEMENTS * (TIMER_SIZE + TIMER_GAP) - TIMER_GAP, TIMER_SIZE)
    f:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    f.icons = {}
    for i, element in ipairs(ELEMENTS) do
        local b = CreateFrame("Frame", nil, f)
        b:SetSize(TIMER_SIZE, TIMER_SIZE)
        b:SetPoint("LEFT", (i - 1) * (TIMER_SIZE + TIMER_GAP), 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.text = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.text:SetPoint("CENTER", 0, 0)
        b.element = element
        b:Hide()
        f.icons[i] = b
    end
    local since = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < 0.2 then return end
        since = 0
        Shaman:UpdateTimers()
    end)
    f:Hide()
    self.timers = f
    return f
end

-- Show each element's totem and its time left; hidden with nothing down
function Shaman:UpdateTimers(now)
    local f = self.timers
    if not f then return end
    local tools = Tools()
    local want = WM:IsModuleOn("ClassShaman") and tools and tools:IsEnabled(CLASS, "totemTimers")
    local any = false
    now = now or GetTime()
    for _, b in ipairs(f.icons) do
        local name, left, icon = nil, nil, nil
        if want then name, left, icon = self:TotemLeft(TOTEM_SLOTS[b.element], now) end
        if name then
            b.icon:SetTexture(icon or ICON_TOTEM)
            b.text:SetText(Shaman.TimeText(left))
            b:Show()
            any = true
        else
            b:Hide()
        end
    end
    f:SetShown(any)
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
    local key = GetBindingKey and GetBindingKey(BINDING)
    tip:AddLine("Click" .. (type(key) == "string" and (" or " .. key) or "")
        .. ": drop the next totem (Air, Water, Earth, then Fire).", 0.9, 0.9, 0.9, true)
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
    class = CLASS, feature = "totemButton", module = "ClassShaman",
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
    local panel = WM.UI:CreatePanel({ name = "WM_TotemSetsFrame", title = "Totem Sets", titleColor = "0070DE", width = 420 })
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
            local r = L:Row(30)
            for col = 1, 2 do
                local element = ELEMENTS[pair * 2 + col]
                r:Dropdown({
                    label = ELEMENT_NAMES[element] .. ":", width = 110,
                    options = ElementOptions(i, element),
                    get = function() return Store().sets[i][element] or AUTO end,
                    set = function(v)
                        Store().sets[i][element] = (v ~= AUTO) and v or nil
                        Shaman:Refresh()
                    end,
                }, col == 1 and 12 or 196)
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
    if not WM:IsModuleOn("ClassShaman") then return end
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
-- SHIELDS: your Water / Lightning Shield, and who has your Earth Shield
-- ============================================
-- A small Shields frame with your own shield: charges and time left (in
-- combat or a group, a red line when it's missing). Earth Shield (Restoration
-- talent) gets a unit frame of its own (below): who has it, their health,
-- its charges and time left. Its target comes from
-- the combat log (so it's known outside your group too), and its charges and
-- time are read from the buff whenever that player is a unit we can see.

local WATER_SHIELD, LIGHTNING_SHIELD, EARTH_SHIELD = 24398, 324, 974
local ICON_WATER = "Interface\\Icons\\Ability_Shaman_WaterShield"
local ICON_LIGHTNING = "Interface\\Icons\\Spell_Nature_LightningShield"
local ICON_EARTH = "Interface\\Icons\\Spell_Nature_SkinofEarth"
local ES_DURATION = 600
local SHIELD_TICK = 0.25
local ES_SEARCH_EVERY = 2   -- target unknown (after a /reload): look through the group this often

local spellNames = {}
local function SpellName(id, fallback)
    if spellNames[id] == nil then
        local ok, n = pcall(GetSpellInfo, id)
        spellNames[id] = (ok and type(n) == "string") and n or fallback
    end
    return spellNames[id]
end

local function KnowsBy(fn, id)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, id)
    return ok and v == true
end
local function Knows(id)
    return KnowsBy(IsPlayerSpell, id) or KnowsBy(IsSpellKnown, id)
end

-- A buff on a unit by name, optionally only one you cast:
-- count, seconds left, icon
local function FindBuff(unit, name, mine, now)
    for i = 1, 40 do
        local n, icon, count, _, _, expires, source = UnitBuff(unit, i)
        if not n then return nil end
        if n == name and (not mine or source == "player") then
            local left = (tonumber(expires) or 0) > 0 and (expires - now) or nil
            return tonumber(count) or 0, left, icon
        end
    end
end

-- Your own Water or Lightning Shield: name, charges, seconds left, icon
local OWN_SHIELDS = { { WATER_SHIELD, "Water Shield", ICON_WATER }, { LIGHTNING_SHIELD, "Lightning Shield", ICON_LIGHTNING } }
function Shaman:OwnShield(now)
    now = now or GetTime()
    for _, s in ipairs(OWN_SHIELDS) do
        local name = SpellName(s[1], s[2])
        local count, left, icon = FindBuff("player", name, false, now)
        if count then return name, count, left, icon or s[3] end
    end
end

-- Earth Shield from the combat log: { guid, name, charges, expires }
local esTarget
local esSearchAt = 0

function Shaman:OnCombatLog(sub, srcGUID, destGUID, destName, spellName, amount)
    if not srcGUID or srcGUID ~= UnitGUID("player") then return end
    if spellName ~= SpellName(EARTH_SHIELD, "Earth Shield") then return end
    if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
        esTarget = { guid = destGUID, name = destName, expires = GetTime() + ES_DURATION }
    elseif esTarget and destGUID == esTarget.guid then
        if sub == "SPELL_AURA_REMOVED_DOSE" or sub == "SPELL_AURA_APPLIED_DOSE" then
            esTarget.charges = tonumber(amount) or esTarget.charges
        elseif sub == "SPELL_AURA_REMOVED" then
            esTarget = nil
        end
    end
end

function Shaman:EarthShieldTarget() return esTarget end

local SEEN_TOO = { "target", "focus", "mouseover" }
local function SeeUnits()
    local units = Tools() and Tools().GroupUnits() or { "player" }
    for _, u in ipairs(SEEN_TOO) do units[#units + 1] = u end
    return units
end

-- The unit your Earth Shield is on, if we can see it; after a /reload (no
-- combat log yet), found by looking through the group every few seconds
local function EarthShieldUnit(now)
    local esName = SpellName(EARTH_SHIELD, "Earth Shield")
    if esTarget then
        -- Four times a second: straight through the unit names, no list made
        local guid = esTarget.guid
        if UnitGUID("player") == guid then return "player" end
        local tools = Tools()
        if tools and IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local u = tools.RAID_UNIT[i]
                if u and UnitExists(u) and UnitGUID(u) == guid then return u end
            end
        elseif tools and IsInGroup() then
            for i = 1, 4 do
                local u = tools.PARTY_UNIT[i]
                if UnitExists(u) and UnitGUID(u) == guid then return u end
            end
        end
        for _, u in ipairs(SEEN_TOO) do
            if UnitExists(u) and UnitGUID(u) == guid then return u end
        end
        return nil
    end
    if now < esSearchAt then return nil end
    esSearchAt = now + ES_SEARCH_EVERY
    for _, u in ipairs(SeeUnits()) do
        if UnitExists(u) and FindBuff(u, esName, true, now) then
            esTarget = { guid = UnitGUID(u), name = UnitName(u) }
            return u
        end
    end
end

-- The rows the Shields frame shows now (your own shield)
function Shaman:ShieldRows(now)
    now = now or GetTime()
    local tools = Tools()
    local rows = {}
    if not tools or not WM:IsModuleOn("ClassShaman") or not IsPlayerShaman() then return rows end
    local busy = (InCombatLockdown and InCombatLockdown()) or IsInGroup()

    if tools:IsEnabled(CLASS, "shieldTimer") then
        local name, count, left, icon = self:OwnShield(now)
        if name then
            rows[#rows + 1] = { icon = icon, text = name,
                right = count .. (left and ("  " .. tools.Clock(left)) or ""),
                r = 0.8, g = 0.9, b = 1 }
        elseif busy and (Knows(LIGHTNING_SHIELD) or Knows(WATER_SHIELD)) then
            rows[#rows + 1] = { icon = ICON_LIGHTNING, text = "No Water or Lightning Shield", r = 1, g = 0.3, b = 0.3 }
        end
    end
    return rows
end

-- A unit token a secure button can hold (not target / focus / mouseover)
local function GroupToken(unit)
    return unit and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) and unit or nil
end

-- What the Earth Shield frame shows now, or nil for no frame:
--   { unit (when we can see them), token (for clicks), name, class,
--     charges, left, hp, max, dead, offline, far, none }
function Shaman:EarthShieldState(now)
    now = now or GetTime()
    local tools = Tools()
    if not tools or not WM:IsModuleOn("ClassShaman") or not IsPlayerShaman() then return nil end
    if not tools:IsEnabled(CLASS, "earthShield") or not Knows(EARTH_SHIELD) then return nil end
    local unit = EarthShieldUnit(now)
    if unit then
        local _, class = UnitClass(unit)
        local st = { unit = unit, token = GroupToken(unit), name = UnitName(unit) or (esTarget and esTarget.name) or "?",
            class = class, hp = UnitHealth(unit) or 0, max = UnitHealthMax(unit) or 0 }
        if UnitIsConnected and not UnitIsConnected(unit) then st.offline = true end
        if UnitIsDeadOrGhost(unit) then
            st.dead = true       -- Earth Shield goes when they die
            esTarget = nil
            return st
        end
        local count, left = FindBuff(unit, SpellName(EARTH_SHIELD, "Earth Shield"), true, now)
        if count then
            esTarget.charges = count
            if left then esTarget.expires = now + left end
            st.charges, st.left = count, left
            if UnitIsVisible and not UnitIsVisible(unit) then st.far = true end
            if st.token and st.token ~= "player" and UnitInRange then
                local inRange, checked = UnitInRange(unit)
                if checked and not inRange then st.far = true end
            end
            return st
        elseif esTarget and esTarget.guid == UnitGUID(unit) then
            esTarget = nil   -- seen without it: gone
        end
    elseif esTarget and esTarget.expires and esTarget.expires > now then
        -- Out of sight: what the combat log last said
        return { name = esTarget.name or "?", charges = esTarget.charges, left = esTarget.expires - now, far = true }
    elseif esTarget and esTarget.expires and esTarget.expires <= now then
        esTarget = nil
    end
    if IsInGroup() then return { none = true, name = "No Earth Shield" } end
    return nil
end

-- ---- the Earth Shield unit frame ----
-- Looks and works like a party frame in ElvUI: a flat class-coloured health
-- bar with the name and health on it, a thin power bar under it, a 1px black
-- border (white while they're your target), faded out of range, and the
-- Earth Shield aura beside it (charges, time left and a cooldown swipe).
-- It's a secure unit button: click to target them (or cast on them with a
-- click-casting addon), mouse over for their tooltip. A secure button can't
-- change who it's on, show or hide in combat, so a new Earth Shield target
-- in combat is drawn at once and clickable once combat ends.
local BAR_TEX = "Interface\\Buttons\\WHITE8X8"
local ES_W, ES_HEALTH_H, ES_POWER_H = 170, 30, 5
local POWER_COLORS = { [0] = { 0, 0.55, 1 }, [1] = { 1, 0, 0 }, [2] = { 1, 0.5, 0.25 }, [3] = { 1, 1, 0 } }

local function ShortNumber(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

local function Outline(fs, size)
    local font = GameFontNormalSmall and GameFontNormalSmall:GetFont()
    if type(font) == "string" then fs:SetFont(font, size, "OUTLINE") end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
end

local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BAR_TEX)
    bar:SetMinMaxValues(0, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetTexture(BAR_TEX)
    return bar
end

-- Shown or hidden (in combat a secure frame can't be: faded to nothing,
-- and hidden on the next update after combat)
local function SetFrameVisible(f, want, alpha)
    if not (InCombatLockdown and InCombatLockdown()) then
        f:SetShown(want)
    end
    f:SetAlpha(want and (alpha or 1) or 0)
end

function Shaman:CreateEarthShieldFrame()
    if self.esFrame then return self.esFrame end
    local f = CreateFrame("Button", "WM_EarthShieldFrame", UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f:SetSize(ES_W, ES_HEALTH_H + ES_POWER_H + 3)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")
    f:SetAttribute("type1", "target")
    f:SetBackdrop({ bgFile = BAR_TEX, edgeFile = BAR_TEX, edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    local db = Store()
    if db.esX and db.esY then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.esX, db.esY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -260, -60)
    end
    f:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown and IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if x and ShamanToolsDB then ShamanToolsDB.esX, ShamanToolsDB.esY = x, y end
    end)
    f:SetScript("OnEnter", function(self)
        local st = self.state
        if st and st.unit and UnitExists(st.unit) then
            if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
            else GameTooltip:SetOwner(self, "ANCHOR_TOP") end
            GameTooltip:SetUnit(st.unit)
        else
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Earth Shield", 1, 0.82, 0)
        end
        GameTooltip:AddLine("Who has your Earth Shield, their health and its charges. Click to target them."
            .. " Shift-drag to move.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.health = NewBar(f)
    f.health:SetPoint("TOPLEFT", 1, -1)
    f.health:SetPoint("TOPRIGHT", -1, -1)
    f.health:SetHeight(ES_HEALTH_H)
    f.power = NewBar(f)
    f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
    f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -1)
    f.power:SetHeight(ES_POWER_H)
    f.highlight = f:CreateTexture(nil, "HIGHLIGHT")
    f.highlight:SetAllPoints(f.health)
    f.highlight:SetColorTexture(1, 1, 1, 0.12)
    f.name = f.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetPoint("LEFT", 4, 0)
    f.name:SetJustifyH("LEFT")
    Outline(f.name, 11)
    f.hp = f.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hp:SetPoint("RIGHT", -4, 0)
    f.hp:SetJustifyH("RIGHT")
    Outline(f.hp, 11)

    -- The Earth Shield aura, to the right
    local size = ES_HEALTH_H + ES_POWER_H + 3
    local aura = CreateFrame("Frame", nil, f, "BackdropTemplate")
    aura:SetSize(size, size)
    aura:SetPoint("LEFT", f, "RIGHT", 2, 0)
    aura:SetBackdrop({ bgFile = BAR_TEX, edgeFile = BAR_TEX, edgeSize = 1 })
    aura:SetBackdropColor(0, 0, 0, 0.6)
    aura:SetBackdropBorderColor(0, 0, 0, 1)
    aura.icon = aura:CreateTexture(nil, "ARTWORK")
    aura.icon:SetPoint("TOPLEFT", 1, -1)
    aura.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    aura.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    aura.icon:SetTexture(ICON_EARTH)
    aura.cd = CreateFrame("Cooldown", nil, aura, "CooldownFrameTemplate")
    aura.cd:SetAllPoints(aura.icon)
    aura.cd:SetReverse(true)
    if aura.cd.SetHideCountdownNumbers then aura.cd:SetHideCountdownNumbers(true) end
    local over = CreateFrame("Frame", nil, aura)
    over:SetAllPoints(aura)
    over:SetFrameLevel((aura:GetFrameLevel() or 0) + 3)
    aura.count = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aura.count:SetPoint("BOTTOMRIGHT", -1, 2)
    Outline(aura.count, 14)
    aura.time = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aura.time:SetPoint("TOP", 0, -2)
    Outline(aura.time, 10)
    f.aura = aura

    -- Click-casting addons (Clique) pick up frames listed here
    if type(ClickCastFrames) == "table" then ClickCastFrames[f] = true end
    f:Hide()
    self.esFrame = f
    return f
end

function Shaman:UpdateEarthShield(now)
    local f = self.esFrame
    if not f then return end
    now = now or GetTime()
    local st = self:EarthShieldState(now)
    f.state = st
    -- Who a click goes to: a secure change, so out of combat only
    local token = st and st.token or nil
    if f.secureUnit ~= token and not (InCombatLockdown and InCombatLockdown()) then
        f:SetAttribute("unit", token)
        f.secureUnit = token
    end
    if not st then SetFrameVisible(f, false) return end
    SetFrameVisible(f, true, st.far and 0.45 or 1)

    local cr, cg, cb = 0.5, 0.5, 0.5
    local c = st.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[st.class]
    if c and st.unit then cr, cg, cb = c.r, c.g, c.b end
    local frac = (st.max or 0) > 0 and (st.hp or 0) / st.max or 0
    f.name:SetText(st.name)
    if st.none then
        f.name:SetTextColor(1, 0.3, 0.3)
        f.hp:SetText("")
        frac = 0
    else
        f.name:SetTextColor(1, 1, 1)
        if st.offline then
            f.hp:SetText("Offline"); frac = 0
        elseif st.dead then
            f.hp:SetText("Dead"); frac = 0
        elseif not st.unit then
            f.hp:SetText(""); frac = 0     -- out of sight: health unknown
        else
            f.hp:SetText(ShortNumber(st.hp) .. " | " .. math.floor(frac * 100 + 0.5) .. "%")
        end
    end
    f.health:SetStatusBarColor(cr, cg, cb)
    f.health.bg:SetVertexColor(cr * 0.25, cg * 0.25, cb * 0.25, 1)
    f.health:SetValue(frac)
    f.frac = frac

    local pfrac, pr, pg, pb = 0, 0.3, 0.3, 0.3
    if st.unit and not st.dead and not st.offline then
        local ptype, ptoken = UnitPowerType(st.unit)
        local pmax = UnitPowerMax(st.unit) or 0
        pfrac = pmax > 0 and (UnitPower(st.unit) or 0) / pmax or 0
        local pc = ptoken and PowerBarColor and PowerBarColor[ptoken]
        if type(pc) == "table" and pc.r then pr, pg, pb = pc.r, pc.g, pc.b
        elseif POWER_COLORS[ptype] then pr, pg, pb = unpack(POWER_COLORS[ptype]) end
    end
    f.power:SetStatusBarColor(pr, pg, pb)
    f.power.bg:SetVertexColor(pr * 0.25, pg * 0.25, pb * 0.25, 1)
    f.power:SetValue(pfrac)

    -- White border while they're your target
    local t = (st.unit and UnitIsUnit(st.unit, "target")) and 1 or 0
    f:SetBackdropBorderColor(t, t, t, 1)

    local aura = f.aura
    if st.charges or st.left then
        aura.icon:SetDesaturated(false)
        aura.count:SetText(st.charges and tostring(st.charges) or "")
        aura.time:SetText(st.left and Tools().Clock(st.left) or "")
        local start = st.left and (now + st.left - ES_DURATION) or nil
        if start and math.abs((aura.cdStart or 0) - start) > 0.5 then
            aura.cdStart = start
            aura.cd:SetCooldown(start, ES_DURATION)
        end
    else
        aura.icon:SetDesaturated(true)
        aura.count:SetText("")
        aura.time:SetText("")
        if aura.cdStart then aura.cdStart = nil; aura.cd:SetCooldown(0, 0) end
    end
end

function Shaman:CreateShieldFrame()
    if self.shieldFrame then return self.shieldFrame end
    local tools = Tools()
    if not tools then return nil end
    self.shieldFrame = tools:CreateTrackerFrame({
        name = "WM_ShamanShields", title = "Shields", store = Store, posX = "shieldX", posY = "shieldY",
        x = -260, y = -140, width = 210, rows = 1,
        tip = { "Shields", "Your Water or Lightning Shield: its charges and time left." },
    })
    return self.shieldFrame
end

function Shaman:UpdateShields(now)
    if self.shieldFrame then self.shieldFrame:SetRows(self:ShieldRows(now)) end
    self:UpdateEarthShield(now)
end

local shieldTicker = CreateFrame("Frame")
local shieldSince = 0
shieldTicker:SetScript("OnUpdate", function(_, elapsed)
    shieldSince = shieldSince + (elapsed or 0)
    if shieldSince < SHIELD_TICK then return end
    shieldSince = 0
    if not Shaman.shieldFrame and not Shaman.esFrame then return end
    if not WM:IsModuleOn("ClassShaman") then
        if Shaman.shieldFrame then Shaman.shieldFrame:Hide() end
        if Shaman.esFrame then SetFrameVisible(Shaman.esFrame, false) end
        return
    end
    Shaman:UpdateShields()
end)

-- ============================================
-- REGISTRATION
-- ============================================

local eventFrame = CreateFrame("Frame")
Shaman.eventFrame = eventFrame

-- The shaman tab's features. Only registers (no frames, no events), so the
-- guided setup can list them before this has started; runs once.
function Shaman:RegisterFeatures()
    self:InitDB()
    local tools = Tools()
    if not tools or self.featuresRegistered then return end
    self.featuresRegistered = true

    local rebuild = function() Shaman:Refresh() end
    tools:RegisterFeature(CLASS, {
        key = "totemButton", name = "Show the totem button",
        desc = "Hover to pick a totem set; click to drop it one totem per click, Air, Water, Earth, then Fire. Starts again from Air when your totems are gone, after combat, or on Ctrl-click. Right-click to edit the sets.",
        default = true,
        onToggle = rebuild,
    })
    WM.Flyout.DirectionFeature(tools, CLASS, "setDir", "Totem sets expand", "totem set",
        Store, DIR_DEFAULTS.setDir, rebuild)
    tools:RegisterFeature(CLASS, {
        key = "totemTimers", name = "Totem timers above the button",
        desc = "Each totem you have down, Air, Water, Earth and Fire, with the time it has left. The button also has a key: \"Drop the next totem\" in the game's Key Bindings, under Watching Machine.",
        default = true,
        onToggle = function() Shaman:UpdateTimers() end,
    })
    local shields = function() Shaman:UpdateShields() end
    tools:RegisterFeature(CLASS, {
        key = "shieldTimer", name = "Shield timer: Water / Lightning Shield",
        desc = "A small Shields frame with your Water Shield or Lightning Shield, its charges and the time it has left. In combat or in a group it turns red when you have neither. Shift-drag the frame to move it.",
        default = true,
        onToggle = shields,
    })
    tools:RegisterFeature(CLASS, {
        key = "earthShield", name = "Earth Shield: who has it, their health and charges",
        desc = "Restoration (once you know Earth Shield): a unit frame, like a party frame in ElvUI, for whoever has your Earth Shield: their class-coloured health and power bars, with its charges, time left and a cooldown swipe beside it. Click it to target them (click-casting addons such as Clique work on it), mouse over for their tooltip. It fades when they're out of range, and in a group says \"No Earth Shield\" when it isn't on anyone. Shift-drag to move (out of combat). A new target in combat becomes clickable once combat ends.",
        default = true,
        onToggle = shields,
    })
    -- The swing timer's weapon sync and Windfury options
    if WM.SwingTimer and WM.SwingTimer.RegisterShamanOptions then WM.SwingTimer.RegisterShamanOptions(tools) end
end

function Shaman:Initialize()
    self:RegisterFeatures()
    if not Tools() then return end

    if IsPlayerShaman() then
        self:CreateTimers(totemFlyout:CreateAnchor())
        WM:RegisterEvents(eventFrame, { "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_TOTEM_UPDATE",
            "COMBAT_LOG_EVENT_UNFILTERED" })
        self:CreateShieldFrame()
        self:CreateEarthShieldFrame()
        totemsWereDown = self:AnyTotemDown() or false
        self:UpdateTimers()
        -- Spellbook isn't reliably populated the instant we initialise
        WM.RunAfter(2, function() Shaman:Refresh() end)
    end
end

eventFrame:SetScript("OnEvent", function(_, event)
    if not IsPlayerShaman() then return end
    -- Turned off in combat: the key binding's macro is emptied once it ends
    if event == "PLAYER_REGEN_ENABLED" and Shaman.clearPending then Shaman:ClearMacro() end
    if not WM:IsModuleOn("ClassShaman") then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not CombatLogGetCurrentEventInfo then return end
        local _, sub, _, srcGUID, _, _, _, destGUID, destName, _, _, _, spellName, _, _, amount = CombatLogGetCurrentEventInfo()
        Shaman:OnCombatLog(sub, srcGUID, destGUID, destName, spellName, amount)
    elseif event == "PLAYER_TOTEM_UPDATE" then
        Shaman:OnTotemUpdate()
        Shaman:UpdateTimers()
    elseif InCombatLockdown() then
        return   -- secure changes wait for combat to end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then totemFlyout:UpdateVisibility() end
    else
        WM.RunAfter(1, function() Shaman:Refresh() end)
    end
end)

function Shaman:IsPendingApply() return pendingApply end

-- Turned off on this character: the button and the set editor close (the
-- button in combat once combat ends)
function Shaman:OnModuleOff()
    if self.editor then self.editor:Hide() end
    totemFlyout:UpdateVisibility()
    self:ClearMacro()
    if self.timers then self.timers:Hide() end
    if self.shieldFrame then self.shieldFrame:Hide() end
    if self.esFrame then SetFrameVisible(self.esFrame, false) end
end

-- Empty the button's macro, so its key binding does nothing while off
-- (a secure change: after combat if need be)
function Shaman:ClearMacro()
    local a = totemFlyout.anchor
    if not a then return end
    if InCombatLockdown() then self.clearPending = true return end
    self.clearPending = nil
    if not WM:IsModuleOn("ClassShaman") then a:SetAttribute("macrotext", "") end
end

-- Back on: the button comes back if it's wanted
function Shaman:OnModuleOn()
    self.clearPending = nil
    self:Refresh()
    self:ApplyMacro()
    self:UpdateTimers()
    self:UpdateShields()
end

-- Class Tools' guided setup, after the shaman features: the set in use and
-- the set editor
function Shaman:SetupExtras(L)
    self:InitDB()
    local opts = {}
    for i = 1, NUM_SETS do opts[i] = { value = i, text = self:SetName(i) } end
    L:Dropdown({ label = "Totem set in use:", width = 120, indent = 16, options = opts,
        get = function() return Store().selected end,
        set = function(v)
            if totemFlyout.anchor then self:SelectSet(v)
            elseif Store().sets[v] then Store().selected = v end
        end,
        tooltip = { "Totem set in use", "The set the button drops. You can also pick one by hovering the button.",
            "The four sets start as Melee, Caster, Healer and Tremor; each picks the best totem you know for each element." } })
    L:Buttons({ { text = "Edit totem sets", width = 130,
        disabled = function() return not (WM:IsModuleOn("ClassShaman") and IsPlayerShaman()) end,
        onClick = function() self:ToggleEditor() end,
        tooltip = { "Edit totem sets", "Name each set and choose its Air, Water, Earth and Fire totem, or Auto for"
            .. " the best you know. Also: right-click the totem button, or /wmachine totems." } } }, 16)
    L:Note("|cFFFFFFFFA key for the button:|r give \"Drop the next totem\" a key in the game's Key Bindings, under"
        .. " Watching Machine. It works in combat, like clicking the button.", 16)
end
