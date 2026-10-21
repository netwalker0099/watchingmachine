-- Watching Machine: General Raid Checks
-- Consumable checks that apply to every character, surfaced under the
-- "General" tab of Class Tools. Distinct from Buff Check, which audits the
-- whole raid once on a ready check: this watches YOU, continuously, while
-- you're in a raid instance.

local AddonName, WM = ...
local General = {}
WM:RegisterModule("ClassGeneral", General)

General.version = "3.5.1"

local CLASS = "GENERAL"

local ICON_FLASK = "Interface\\Icons\\INV_Potion_97"
local ICON_FOOD  = "Interface\\Icons\\INV_Misc_Food_15"
local ICON_OIL   = "Interface\\Icons\\INV_Potion_98"

-- Weapon types that take a sharpening stone / weightstone rather than oil.
-- Used only to word the warning usefully; the check itself is the same.
local MELEE_CLASSES = {
    WARRIOR = true, ROGUE = true, PALADIN = true,
    HUNTER = true, SHAMAN = true, DRUID = true,
}

-- Food and flask names come from Core.lua, shared with Buff Check
local function PlayerHasAura(test)
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if test(WM, n) then return true end
    end
    return false
end

local function PlayerHasFood()  return PlayerHasAura(WM.IsFoodBuff) end

-- The flask warning, worded for what's actually missing. A flask, or one
-- battle plus one guardian elixir, is a full set in TBC. nil = covered.
local function FlaskWarning()
    local flask, battle, guardian = WM:ElixirState("player")
    if WM:IsFlaskCovered(flask, battle, guardian) then return nil end
    if battle then return "No guardian elixir (or flask)" end
    if guardian then return "No battle elixir (or flask)" end
    return "No flask or elixirs"
end

function General:Print(msg)
    WM:ModulePrint("ClassGeneral", msg)
end

-- ============================================
-- RAID CONTEXT
-- ============================================

-- Returns inRaidInstance, maxPlayers
local function RaidContext()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then return false, 0 end
    local _, _, _, _, maxPlayers = GetInstanceInfo()
    return true, tonumber(maxPlayers) or 0
end

local function ShouldCheckHere()
    if not GeneralChecksDB then return false end
    local inRaid, maxPlayers = RaidContext()
    if not inRaid then return false end
    if GeneralChecksDB.only25 and maxPlayers ~= 25 then return false end
    return true
end

-- ============================================
-- WEAPON ENCHANT
-- ============================================
-- GetWeaponEnchantInfo reports only that an enchant EXISTS, never which one,
-- so this detects a missing oil/stone but can't tell oil from stone. That is
-- the useful alert anyway: "you have nothing on your weapon".

local function WeaponEnchantState()
    if not GetWeaponEnchantInfo then return true, true end
    local ok, hasMain, _, _, hasOff = pcall(GetWeaponEnchantInfo)
    if not ok then return true, true end   -- unavailable: don't invent warnings
    return hasMain and true or false, hasOff and true or false
end

-- Only a real weapon in the off hand can take an oil or a stone. Shields and
-- held items (tomes, orbs) occupy the same slot and would otherwise produce a
-- permanent, unfixable warning.
local OFFHAND_ENCHANTABLE = {
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_WEAPON        = true,
    INVTYPE_2HWEAPON      = true,
}

local function HasOffHandWeapon()
    if not GetInventoryItemLink then return false end
    local link = GetInventoryItemLink("player", 17)
    if not link then return false end
    if not GetItemInfo then return false end
    local ok, _, _, _, _, _, _, _, _, equipSlot = pcall(GetItemInfo, link)
    -- Uncached item: say no rather than warn about something we can't classify
    if not ok or not equipSlot then return false end
    return OFFHAND_ENCHANTABLE[equipSlot] or false
end

-- ============================================
-- MONITOR
-- ============================================

local CT

local function Tools()
    CT = CT or WM.modules.ClassTools
    return CT
end

local function ClearAll(tools)
    tools:ClearAlert("gen_flask")
    tools:ClearAlert("gen_food")
    tools:ClearAlert("gen_oil")
end

local function Monitor()
    local tools = Tools()
    if not tools then return end

    -- Outside a qualifying raid, or dead, stay silent
    if UnitIsDeadOrGhost("player") or not ShouldCheckHere() then
        ClearAll(tools)
        return
    end

    if tools:IsEnabled(CLASS, "flask") then
        local warning = FlaskWarning()
        if warning then
            tools:SetAlert("gen_flask", warning, ICON_FLASK)
        else
            tools:ClearAlert("gen_flask")
        end
    else
        tools:ClearAlert("gen_flask")
    end

    if tools:IsEnabled(CLASS, "food") then
        if PlayerHasFood() then
            tools:ClearAlert("gen_food")
        else
            tools:SetAlert("gen_food", "No food buff", ICON_FOOD)
        end
    else
        tools:ClearAlert("gen_food")
    end

    if tools:IsEnabled(CLASS, "weaponenchant") then
        local hasMain, hasOff = WeaponEnchantState()
        local _, class = UnitClass("player")
        local label = MELEE_CLASSES[class] and "sharpening stone / weightstone" or "wizard oil"

        local missing = nil
        if not hasMain then
            missing = "Main hand: no " .. label
        elseif GeneralChecksDB.checkOffHand and HasOffHandWeapon() and not hasOff then
            missing = "Off hand: no " .. label
        end

        if missing then
            tools:SetAlert("gen_oil", missing, ICON_OIL)
        else
            tools:ClearAlert("gen_oil")
        end
    else
        tools:ClearAlert("gen_oil")
    end
end

-- ============================================
-- DIAGNOSTIC
-- ============================================

function General:Explain()
    local inRaid, maxPlayers = RaidContext()
    self:Print("=== General raid checks ===")
    print("  in raid instance: " .. tostring(inRaid)
        .. (inRaid and ("  (" .. maxPlayers .. "-man)") or ""))
    print("  25-man only: " .. tostring(GeneralChecksDB and GeneralChecksDB.only25)
        .. "   -> checks active here: " .. tostring(ShouldCheckHere()))
    local flask, battle, guardian = WM:ElixirState("player")
    local yes, no = "|cFF00FF00yes|r", "|cFFFF4444no|r"
    print("  flask: " .. (flask and yes or no) .. "   battle elixir: " .. (battle and yes or no)
        .. "   guardian elixir: " .. (guardian and yes or no)
        .. "   -> " .. (WM:IsFlaskCovered(flask, battle, guardian) and "|cFF00FF00covered|r" or "|cFFFF4444warning|r"))
    print("  food buff: " .. (PlayerHasFood() and "|cFF00FF00yes|r" or "|cFFFF4444no|r"))
    local hasMain, hasOff = WeaponEnchantState()
    print("  main-hand enchant: " .. (hasMain and "|cFF00FF00yes|r" or "|cFFFF4444no|r")
        .. "   off-hand: " .. (hasOff and "|cFF00FF00yes|r"
            or (HasOffHandWeapon() and "|cFFFF4444no|r" or "|cFF888888n/a|r")))
    print("  |cFF888888The weapon API reports only that an enchant exists, not which"
        .. " one, so oil and stones can't be told apart.|r")
end

-- ============================================
-- REGISTRATION
-- ============================================

function General:InitDB()
    if not GeneralChecksDB then GeneralChecksDB = {} end
    if GeneralChecksDB.only25 == nil then GeneralChecksDB.only25 = true end
    if GeneralChecksDB.checkOffHand == nil then GeneralChecksDB.checkOffHand = true end
end

function General:Initialize()
    self:InitDB()
    local tools = Tools()
    if not tools then return end

    tools:RegisterFeature(CLASS, {
        key = "flask", name = "Warn if no flask or elixirs",
        desc = "A flask, or a battle plus a guardian elixir, counts. Checked continuously while you're in a raid instance.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "food", name = "Warn if no food buff",
        desc = "Looks for Well Fed, or Enlightened from Skullfish Soup.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "weaponenchant", name = "Warn if no weapon oil / stone",
        desc = "Wizard oil for casters, sharpening stone or weightstone for melee.",
        default = true,
    })
    tools:RegisterFeature(CLASS, {
        key = "only25", name = "Only in 25-man raids",
        desc = "Untick to check in 10-man raids too.",
        default = true,
        onToggle = function(v) GeneralChecksDB.only25 = v and true or false end,
    })

    -- Keep the saved flag and the feature toggle in step on load
    local tdb = ClassToolsDB and ClassToolsDB.enabled and ClassToolsDB.enabled[CLASS]
    if tdb and tdb.only25 ~= nil then
        GeneralChecksDB.only25 = tdb.only25 and true or false
    end

    tools:RegisterMonitor(Monitor)
end
