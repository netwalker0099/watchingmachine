import sys
S, OUT = sys.argv[1], sys.argv[2]
HDR='''-- Watching Machine: Loot Browser data — {what}
-- {desc}
-- Only IDs are stored; names, icons and stats come from the game client at
-- run time. Compiled with the help of community loot data (AtlasLoot
-- Classic); only the facts are kept, in Watching Machine's own format, and
-- each table is built the first time the Loot Browser shows it.
--
-- Page: id, name (English; the client's own name is used when it has one),
--   kind, side (Horde / Alliance only), instance / area / faction IDs,
--   levels, phase (TBC phase), bosses = rows.
-- Row: [1] name, npc, special, extra (trash / quest / event pages),
--   expansion (needs that expansion: 2 = Wrath), phase, set (the lists are
--   item set IDs), craft (the lists are craft spell IDs), and its lists:
--   n (normal), h (heroic), horde / alliance, or others (plate, mail,
--   leather, vendor...). A list entry is an ID, or {{ horde ID, alliance ID }}
--   (0 = not for that faction).

local _, WM = ...
WM.LootData = WM.LootData or {{}}
'''
LABEL={0:"Classic",1:"Burning Crusade",2:"Wrath of the Lich King"}
def ds(key,cat,exp,src):
    body=open(f"{S}/{src}").read()
    return f'''
WM.LootData.{key} = {{
    expansion = {exp}, category = "{cat}", label = "{LABEL[exp]}", order = {exp + 1},
    build = function() return {{
'''+body+'''    } end,
}
'''
def write(path, what, desc, parts):
    open(f"{OUT}/{path}",'w').write(HDR.format(what=what, desc=desc)+''.join(parts))
write("LootClassic.lua","Classic dungeons and raids","Which items drop where: instance, boss, difficulty and item IDs.",[ds("classic","dungeons",0,"classic_dungeons.lua")])
write("LootTBC.lua","Burning Crusade dungeons and raids","Which items drop where: instance, boss, difficulty and item IDs.",[ds("tbc","dungeons",1,"tbc_dungeons.lua")])
write("LootCrafting.lua","professions","What each profession makes, by craft spell ID (see LootCrafts.lua).",
  [ds("classicCrafting","crafting",0,"classic_crafting.lua"),ds("tbcCrafting","crafting",1,"tbc_crafting.lua"),ds("wrathCrafting","crafting",2,"wrath_crafting.lua")])
write("LootFactions.lua","reputation rewards","What each faction sells or gives at each standing.",
  [ds("classicFactions","factions",0,"classic_factions.lua"),ds("tbcFactions","factions",1,"tbc_factions.lua"),ds("wrathFactions","factions",2,"wrath_factions.lua")])
write("LootPvP.lua","PvP rewards","Battleground, arena, honor and world PvP rewards.",
  [ds("classicPvP","pvp",0,"classic_pvp.lua"),ds("tbcPvP","pvp",1,"tbc_pvp.lua"),ds("wrathPvP","pvp",2,"wrath_pvp.lua")])
write("LootCollections.lua","collections","Badge and Sunmote vendors, world epics, mounts, companions, tabards,\n-- legendaries, Classic item sets and world events.",
  [ds("classicCollections","collections",0,"classic_collections.lua"),ds("tbcCollections","collections",1,"tbc_collections.lua")])
open(f"{OUT}/LootSets.lua","w").write('''-- Watching Machine: Loot Browser data — item sets
-- The pieces of each set the pages show: [set ID] = { item IDs,
-- classes = class mask (1 warrior, 2 paladin, 4 hunter, 8 rogue, 16 priest,
-- 32 death knight, 64 shaman, 128 mage, 256 warlock, 1024 druid),
-- prefix / base for sets named after another ("Brutal" + set 685) }.
-- base: as on a TBC client; wrath: what a Wrath client changes or adds.
-- Set names come from the game client (GetItemSetInfo).

local _, WM = ...
WM.LootData = WM.LootData or {}
WM.LootData.sets = function() return {
'''+open(f"{S}/sets.lua").read()+'''} end
''')
open(f"{OUT}/LootCrafts.lua","w").write('''-- Watching Machine: Loot Browser data — craft spells
-- [craft spell ID] = { made item ID (0: none, e.g. an enchant), profession,
-- skill needed, turns green at, turns grey at, r = { reagent ID, count, ... },
-- t = the recipe item that teaches it }.
-- Professions: 1 First Aid, 2 Blacksmithing, 3 Leatherworking, 4 Alchemy,
-- 5 Herbalism, 6 Cooking, 7 Mining, 8 Tailoring, 9 Engineering,
-- 10 Enchanting, 11 Fishing, 12 Skinning, 13 Poisons, 14 Jewelcrafting,
-- 15 Inscription.
-- base: as on a TBC client; wrath: what a Wrath client changes or adds.

local _, WM = ...
WM.LootData = WM.LootData or {}
WM.LootData.crafts = function() return {
'''+open(f"{S}/crafts.lua").read()+'''} end
''')
