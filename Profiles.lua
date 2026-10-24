-- Watching Machine: per-character settings and module switches
--
-- Settings: each module keeps its settings in its own saved variable
-- (HazardsDB, ClassToolsDB, ...). Those are account-wide in the game, so
-- here each one is given a profile per character: the saved table holds
--   __wm = { profiles = { ["Name-Realm"] = {...} }, shared = {...}, legacy = {...} }
-- and a metatable sends every read and write to this character's profile,
-- except a module's cross-character data (every character's log, the enemy
-- list, ...), which stays shared. Modules keep using HazardsDB.sounds and
-- so on as before. The game saves the raw table, so every profile is kept.
-- Settings saved before this existed become the starting point for each
-- character the first time it logs in.
--
-- Not given profiles: WatchingMachineDB (the addon's own: theme, minimap,
-- window positions, and the per-character switches below) and ArmorySnapDB
-- (the standalone ArmorySnap addon reads it directly).
--
-- Switches: which modules are on, per character, in
--   WatchingMachineDB.chars["Name-Realm"].modules[name] = true / false
-- A module that's off isn't started at login. Turning one on starts it;
-- turning one off calls its OnModuleOff (and SetModuleEnabled(false) for
-- modules with a switch of their own).

local AddonName, WM = ...
local P = {}
WM.Profiles = P

-- Saved variable -> the keys that hold data shared by all your characters
P.SCOPE = {
    AutoLoggerDB = {},
    KeywordMonitorDB = {},
    ChatFilterDB = {},
    MailLoggerDB = { shared = { "characters" } },
    ServicesParserDB = {},
    RecruitingToolDB = { shared = { "activityLog", "whispered" } },
    WhisperLogsDB = { shared = { "whispers" } },
    GuildInviteDB = { shared = { "inviteLog" } },
    DebuffTrackerDB = { shared = { "excludedNPCs" } },
    PvPTrackerDB = { shared = { "enemies", "leaderboard", "myKOSKills" } },
    BuffCheckDB = {},
    AuraRangeDB = {},
    ClassToolsDB = {},
    GeneralChecksDB = {},
    MageToolsDB = {},
    WarlockToolsDB = {},
    ShamanToolsDB = {},
    SwingTimerDB = {},
    InstanceTrackerDB = { shared = { "runs", "nextId" } },
    AltTrackerDB = { shared = { "chars" } },
    PvPLogDB = { shared = { "matches", "nextId" } },
    WorldTimersDB = { shared = { "realms", "chars" } },
    LootBrowserDB = { shared = { "lists", "bis", "listOrder", "chars", "names" } },
    WMGearScoreDB = { shared = { "players" } },
    AttunementsDB = { shared = { "chars", "guild" } },
    HazardsDB = {},
    WMCritsDB = { shared = { "chars" } },
    OgrilaDB = {},
    WMGearSetsDB = { shared = { "chars" } },
    WMFrameMoverDB = {},
}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end
P.DeepCopy = DeepCopy

function P.CharKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    return (type(name) == "string" and name or "?") .. "-" .. (type(realm) == "string" and realm or "?")
end

P.profiles = {}      -- [saved variable] = this character's live profile table
P.stores = {}        -- [saved variable] = its __wm store
P.fresh = {}         -- [saved variable] = true: this character's profile was just made

-- Give one saved variable its per-character routing
function P:Wrap(name, key)
    local spec = self.SCOPE[name]
    if not spec then return end
    local shared = {}
    for _, k in ipairs(spec.shared or {}) do shared[k] = true end
    local raw = rawget(_G, name)
    if type(raw) ~= "table" then raw = {} end
    if getmetatable(raw) then return raw end
    local store = rawget(raw, "__wm")
    if type(store) ~= "table" then
        -- Saved before profiles: shared data stays shared, the rest is the
        -- starting point for every character
        store = { profiles = {}, shared = {} }
        local legacy = {}
        for k, v in pairs(raw) do
            if shared[k] then store.shared[k] = v else legacy[k] = v end
        end
        if next(legacy) then store.legacy = legacy end
        raw = { __wm = store }
    else
        if type(store.profiles) ~= "table" then store.profiles = {} end
        if type(store.shared) ~= "table" then store.shared = {} end
    end
    local profile = store.profiles[key]
    if type(profile) ~= "table" then
        profile = store.legacy and DeepCopy(store.legacy) or {}
        store.profiles[key] = profile
        self.fresh[name] = true
    end
    -- Anything written past the routing goes where it belongs
    for k, v in pairs(raw) do
        if k ~= "__wm" then
            raw[k] = nil
            if shared[k] then store.shared[k] = v else profile[k] = v end
        end
    end
    setmetatable(raw, {
        __index = function(_, k)
            if shared[k] then return store.shared[k] end
            return profile[k]
        end,
        __newindex = function(_, k, v)
            if shared[k] then store.shared[k] = v else profile[k] = v end
        end,
    })
    _G[name] = raw
    self.profiles[name], self.stores[name] = profile, store
    return raw
end

-- At ADDON_LOADED, before any module reads its settings
function P:Load()
    local key = P.CharKey()
    self.key = key
    for name in pairs(self.SCOPE) do self:Wrap(name, key) end
end

-- Characters with settings of their own (for "copy from"), sorted
function P:Characters()
    local seen, out = {}, {}
    for _, store in pairs(self.stores) do
        for k in pairs(store.profiles) do
            if k ~= self.key and not seen[k] then seen[k] = true; out[#out + 1] = k end
        end
    end
    for k in pairs((WatchingMachineDB and WatchingMachineDB.chars) or {}) do
        if k ~= self.key and not seen[k] then seen[k] = true; out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

-- Forget another character's settings and module switches (a character
-- you deleted or renamed). Records modules keep about all your characters
-- (Your Characters' list, the instance log, ...) are left to those modules.
function P:DeleteCharacter(other)
    if not other or other == self.key then return false end
    local found = false
    for _, store in pairs(self.stores) do
        if store.profiles[other] ~= nil then store.profiles[other] = nil; found = true end
    end
    local chars = WatchingMachineDB and WatchingMachineDB.chars
    if type(chars) == "table" and chars[other] then chars[other] = nil; found = true end
    return found
end

-- Copy another character's settings and module switches onto this one.
-- Modules already running pick up some changes only after /reload.
function P:CopyFrom(other)
    if not other or other == self.key then return false end
    for name, store in pairs(self.stores) do
        local from = store.profiles[other]
        local mine = self.profiles[name]
        if type(from) == "table" and mine then
            for k in pairs(mine) do mine[k] = nil end
            for k, v in pairs(DeepCopy(from)) do mine[k] = v end
        end
    end
    local chars = WatchingMachineDB and WatchingMachineDB.chars
    if chars and chars[other] then
        local c = WM:CharState()
        c.modules = DeepCopy(chars[other].modules or {})
        c.defaultOn = chars[other].defaultOn
    end
    return true
end

-- ============================================
-- WHICH MODULES ARE ON (per character)
-- ============================================

-- Parts of another module: on only while it is, and set up with it
WM.MODULE_PARENT = {
    ClassGeneral = "ClassTools", ClassWarlock = "ClassTools", ClassMage = "ClassTools",
    ClassShaman = "ClassTools", ClassPaladin = "ClassTools", SwingTimer = "ClassTools",
}

-- Optional links: module -> { other module = what you get with both on }
WM.MODULE_LINKS = {
    AltTracker = {
        GearScore = "a GearScore for each of your characters",
        Attunements = "attunement progress on each character's tooltip",
        Crits = "each character's best crit on its tooltip",
        InstanceTracker = "the instances each character entered, in the lockouts view",
    },
    GearSets = { AltTracker = "missing set items say when they're in your bank" },
    KeywordMonitor = { ChatFilter = "filtered spam never reaches your keywords" },
    ArmorySnap = { GearScore = "a GearScore for every raid member in a snapshot" },
    DebuffTracker = { ArmorySnap = "the spell-reflect check waits while ArmorySnap inspects" },
    InstanceTracker = { MailLogger = "gold traded during a run, on the run's tooltip",
        AltTracker = "a button to Your Characters from the instance list" },
    MailLogger = { InstanceTracker = "trades tagged with the instance run they happened in" },
}

function WM:CharKey() return P.CharKey() end

-- This character's setup record
function WM:CharState()
    WatchingMachineDB = WatchingMachineDB or {}
    local db = WatchingMachineDB
    if type(db.chars) ~= "table" then db.chars = {} end
    local key = P.CharKey()
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = { modules = {}, defaultOn = true }
        db.chars[key] = c
    end
    if type(c.modules) ~= "table" then c.modules = {} end
    return c
end

-- First time on this character (with this version): a character that used
-- Watching Machine before keeps everything on and is offered the setup; a
-- new one starts with everything off and is asked to set up.
function WM:InitCharacter()
    WatchingMachineDB = WatchingMachineDB or {}
    if type(WatchingMachineDB.chars) ~= "table" then WatchingMachineDB.chars = {} end
    local key = P.CharKey()
    if WatchingMachineDB.chars[key] then return WatchingMachineDB.chars[key] end
    local known = false
    local alts = AltTrackerDB and AltTrackerDB.chars
    if type(alts) == "table" and alts[key] then known = true end
    local c = { modules = {}, created = time and time() or 0 }
    if known then
        c.defaultOn, c.setup = true, "offer"
    else
        c.defaultOn, c.setup = false, "new"
    end
    WatchingMachineDB.chars[key] = c
    return c
end

-- Is a module on for this character?
function WM:IsModuleOn(name)
    local parent = WM.MODULE_PARENT[name]
    if parent and not self:IsModuleOn(parent) then return false end
    local db = WatchingMachineDB
    local c = db and type(db.chars) == "table" and db.chars[P.CharKey()]
    if not c or type(c.modules) ~= "table" then return true end
    local v = c.modules[name]
    -- A part with no switch of its own follows its parent
    if parent and v == nil then return true end
    if v == nil then return c.defaultOn ~= false end
    return v and true or false
end

-- On for any of your characters. Modules that keep records about all your
-- characters (Your Characters) record every one you log in on while this is
-- true, so their view is complete even from a character where they're off.
function WM:IsModuleOnAnywhere(name)
    if self:IsModuleOn(name) then return true end
    local chars = WatchingMachineDB and WatchingMachineDB.chars
    if type(chars) ~= "table" then return false end
    for _, c in pairs(chars) do
        if type(c) == "table" then
            local v = type(c.modules) == "table" and c.modules[name]
            if v == true or (v == nil and c.defaultOn ~= false) then return true end
        end
    end
    return false
end

-- Should this module run on this character? On here, or (for a module
-- that records every character) on for any of them
function WM:ShouldRun(name)
    if self:IsModuleOn(name) then return true end
    local m = self.modules[name]
    return m and m.recordsEveryCharacter and self:IsModuleOnAnywhere(name) or false
end

-- Start a module that hasn't been started yet
function WM:StartModule(name)
    local m = self.modules[name]
    if not m or m._wmStarted then return end
    m._wmStarted = true
    if m.Initialize then
        local ok, err = pcall(m.Initialize, m)
        if not ok then geterrorhandler()(name .. ":Initialize failed: " .. tostring(err)) end
    end
end

-- Modules that are part of this one
local function Children(name)
    local out = {}
    for child, parent in pairs(WM.MODULE_PARENT) do
        if parent == name then out[#out + 1] = child end
    end
    table.sort(out)
    return out
end
WM.ModuleChildren = Children

-- Turn a module on or off for this character, starting or stopping it now
function WM:SetModuleOn(name, on)
    on = on and true or false
    local c = self:CharState()
    c.modules[name] = on
    local function Apply(n)
        local m = self.modules[n]
        if not m then return end
        if on then
            if self.modulesInitialized then self:StartModule(n) end
            if m.SetModuleEnabled then pcall(m.SetModuleEnabled, m, true) end
            if m.OnModuleOn then pcall(m.OnModuleOn, m) end
        else
            if m.SetModuleEnabled then pcall(m.SetModuleEnabled, m, false) end
            if m.OnModuleOff then pcall(m.OnModuleOff, m) end
        end
    end
    if on then
        Apply(name)
        for _, child in ipairs(Children(name)) do if self:IsModuleOn(child) then Apply(child) end end
    else
        for _, child in ipairs(Children(name)) do Apply(child) end
        Apply(name)
    end
    if self.UpdateDashboard then self:UpdateDashboard() end
end

-- The module, if it's on; otherwise says how to turn it on
function WM:UsableModule(name)
    local m = self.modules[name]
    if not m then self:Print(name .. " isn't available."); return nil end
    if not self:IsModuleOn(name) then
        local info = self.MODULE_INFO and self.MODULE_INFO[WM.MODULE_PARENT[name] or name]
        self:Print((info and info.title or name) .. " is off on this character. Turn it on from the dashboard, or run /wmachine setup.")
        return nil
    end
    if not m._wmStarted and self.modulesInitialized then self:StartModule(name) end
    return m
end
