-- Crit Tracker: recording from the combat log (melee, ranged, spells,
-- abilities, heals), new bests, PvP kept apart, alerts, tooltips, Your
-- Characters, sharing and the window.
-- Usage: lua5.1 test_crits.lua <repo>
local REPO = assert(arg[1], "repo path")
local W = dofile(REPO .. "/tests/wowstub.lua")(REPO)
local env = W.env

local now = 1800000000
env.GetServerTime = function() return now end
local ME = "Player-1-00000001"
env.UnitGUID = function(u) if u == "player" then return ME end end
env.UnitName = function(u) if u == "player" then return "Mage" end end
env.GetRealmName = function() return "Spineshatter" end
env.GetRealZoneText = function() return "Karazhan" end
local played = {}
env.PlaySound = function(id) played[#played + 1] = id end
local sent = {}
env.SendChatMessage = function(m, c) sent[#sent + 1] = { m, c } end
env.IsInRaid = function() return false end
env.GetNumGroupMembers = function() return 3 end
env.GetSpellTexture = function(id) return "icon" .. tostring(id) end

for _, f in ipairs({ "Core.lua", "UI.lua", "Sounds.lua", "Modules/Crits.lua" }) do W.load(f) end
local WM = W.WM
local CR = WM.modules.Crits
env.WatchingMachineDB = { theme = "Default" }
CR:Initialize()

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1 else fail = fail + 1; io.write("FAIL: ", name, "\n") end
end
local MOB, PLAYER = "Creature-0-1-530-1-15550-0000000001", "Player-1-00000002"
local function Spell(sub, id, name, school, amount, crit, dst, dstName)
    return CR:OnCombatEvent(0, sub, false, ME, "Mage", 0, 0, dst or MOB, dstName or "Attumen", 0, 0,
        id, name, school, amount, 0, school, nil, nil, nil, crit)
end
local function Heal(id, name, amount, crit)
    return CR:OnCombatEvent(0, "SPELL_HEAL", false, ME, "Mage", 0, 0, ME, "Mage", 0, 0, id, name, 2, amount, 0, 0, crit)
end
local function Swing(amount, crit)
    return CR:OnCombatEvent(0, "SWING_DAMAGE", false, ME, "Mage", 0, 0, MOB, "Attumen", 0, 0, amount, 0, 1, nil, nil, nil, crit)
end

-- ---- Recording ----
local r, field = Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 2500, false)
check("a spell hit", r.cat == "spell" and r.hit.value == 2500 and field == "hit" and r.hits == 1 and r.crits == 0)
r, field = Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 4000, true)
check("a crit", r.crit.value == 4000 and field == "crit" and r.crits == 1 and r.crit.target == "Attumen" and r.crit.zone == "Karazhan")
r, field = Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 3900, true)
check("a smaller crit isn't a record", field == nil and r.crit.value == 4000 and r.crits == 2)
check("crit rate", CR.Rate(r) == 66.7)
check("physical SPELL_DAMAGE is an ability", Spell("SPELL_DAMAGE", 30335, "Bloodthirst", 1, 2000, true).cat == "ability")
check("dots count as spells", Spell("SPELL_PERIODIC_DAMAGE", 27218, "Curse of Agony", 32, 300, false).cat == "spell")
check("melee", Swing(1200, true).cat == "melee" and CR:List(nil, "melee")[1].crit.value == 1200)
check("ranged", CR:OnCombatEvent(0, "RANGE_DAMAGE", false, ME, "Mage", 0, 0, MOB, "Attumen", 0, 0, 5019, "Shoot", 32, 400,
    0, 32, nil, nil, nil, true).cat == "ranged")
check("heals", Heal(25235, "Flash Heal", 1800, true).cat == "heal" and CR:List(nil, "heal")[1].crit.value == 1800)
check("others' hits don't count", CR:OnCombatEvent(0, "SPELL_DAMAGE", false, "Player-9", "X", 0, 0, MOB, "Attumen", 0, 0,
    27070, "Fireball", 4, 99999, 0, 4, nil, nil, nil, true) == nil)
-- PvP apart
local pr = Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 6000, true, PLAYER, "Rogue")
check("hits on players kept apart", pr.pvp and CR:List(nil, "spell", true)[1].crit.value == 6000
    and CR:List(nil, "spell")[1].crit.value == 4000)
env.WMCritsDB.pvp = false
check("PvP off: not counted", Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 9000, true, PLAYER, "Rogue") == nil)
env.WMCritsDB.pvp = true

-- ---- Alerts ----
W.printed = {}
played = {}
Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 4500, true)
check("new best crit: said in chat", (W.printed[#W.printed] or ""):find("New best crit", 1, true)
    and W.printed[#W.printed]:find("4,500", 1, true) and W.printed[#W.printed]:find("was 4,000", 1, true))
check("with a sound", played[1] == 891)
W.printed = {}
Spell("SPELL_DAMAGE", 27071, "Frostbolt", 16, 3000, true)
check("the first crit of a spell isn't announced", #W.printed == 0)
W.printed = {}
Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 2600, false)
check("normal hits quiet by default", #W.printed == 0)
env.WMCritsDB.alertHits = true
Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 2700, false)
check("unless asked", (W.printed[#W.printed] or ""):find("New best hit", 1, true) ~= nil)
env.WMCritsDB.alertHits = false
W.printed = {}
env.WMCritsDB.minimum = 10000
Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 4600, true)
check("quiet below the minimum", #W.printed == 0)
env.WMCritsDB.minimum = 0
env.WMCritsDB.announce = true
Spell("SPELL_DAMAGE", 27070, "Fireball", 4, 4700, true)
check("tells the party", sent[#sent] and sent[#sent][2] == "PARTY" and sent[#sent][1]:find("Fireball 4,700", 1, true))
env.WMCritsDB.announce = false

-- ---- Tooltips and Your Characters ----
local tl = CR:TooltipLines("Fireball")
check("spell tooltip lines", tl and #tl == 2 and table.concat(tl, " "):find("4,700", 1, true) and table.concat(tl, " "):find("PvP", 1, true))
check("no lines for unknown spells", CR:TooltipLines("Arcane Missiles") == nil)
local tip = W.NewFrame("Tip")
tip.lines = {}
tip.AddLine = function(self, l) self.lines[#self.lines + 1] = l end
tip.GetSpell = function() return "Fireball", "Rank 13" end
tip.HasScript = function() return true end
env.GameTooltip = tip
CR:HookTooltips()
tip:_fire("OnTooltipSetSpell")
check("tooltip hook", #tip.lines == 2)
tip:_fire("OnTooltipSetSpell")
check("once per showing", #tip.lines == 2)
check("best crit for Your Characters", CR:BestLine("Mage-Spineshatter"):find("Fireball", 1, true)
    and CR:BestLine("Mage-Spineshatter"):find("4,700", 1, true))
check("looking at an unknown alt adds nothing", CR:BestLine("Alt-Spineshatter") == nil and env.WMCritsDB.chars["Alt-Spineshatter"] == nil)

-- ---- Sharing ----
local fb = CR:List(nil, "spell")[1]
CR:Share(fb, "GUILD")
check("share", sent[#sent][2] == "GUILD" and sent[#sent][1]:find("My best crit Fireball: 4,700 on Attumen", 1, true))
local menu = CR:OpenShareMenu(fb)
local items = W.openMenu(menu)
check("share menu", #items == 4 and items[4].text == "Share in Guild")

-- ---- Window ----
CR:Toggle()
local p = env.WM_CritsFrame
check("window", p:IsShown() and p.rows[1].rec.name == "Fireball" and p.rows[1].crit:GetText():find("4,700", 1, true))
p.catBox.buttons[6]:_fire("OnClick")
check("filter: heals", p.rows[1].rec.cat == "heal" and not p.rows[2]:IsShown())
p.pvpBox.buttons[2]:_fire("OnClick")
check("against players", (function()
    p.catBox.buttons[1]:_fire("OnClick")
    return p.rows[1].rec.pvp == true
end)())
local tipText = {}
env.GameTooltip.SetText = function(_, t) tipText[#tipText + 1] = t end
env.GameTooltip.AddLine = function(_, t) tipText[#tipText + 1] = t end
p.rows[1]._scripts.OnEnter(p.rows[1])
check("row tooltip", table.concat(tipText, "\n"):find("Best crit", 1, true) ~= nil)
check("status", CR:GetQuickStatus():find("Fireball", 1, true) ~= nil)
CR:Reset()
check("reset", #CR:List() == 0)

print(pass .. " passed, " .. fail .. " failed")
if fail > 0 then os.exit(1) end
