-- Watching Machine: Loot Browser data — collections
-- Badge and Sunmote vendors, world epics, mounts, companions, tabards,
-- legendaries, Classic item sets and world events.
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
--   leather, vendor...). A list entry is an ID, or { horde ID, alliance ID }
--   (0 = not for that faction).

local _, WM = ...
WM.LootData = WM.LootData or {}

WM.LootData.classicCollections = {
    expansion = 0, category = "collections", label = "Classic", order = 1,
    build = function() return {
    { id = "TierSets", name = "Tier Sets", kind = "sets", bosses = {
        { "Tier 1 Sets", set = true, n = { 203, 202, 204, 206, 209, 201, 205, 207, 208 } },
        { "Tier 2 Sets", set = true, n = { 212, 211, 213, 215, 218, 210, 214, 216, 217 } },
        { "Tier 2.5 Sets", set = true, n = { 499, 507, 497, 509, 496, 503, 493, 501, 505 } },
        { "Tier 3 Sets", set = true, n = { 529, 525, 524, 530, 523, 526, 521, 527, 528 } },
    } },
    { id = "DungeonSets", name = "Dungeon Sets", kind = "sets", bosses = {
        { "Dungeon Set 1", set = true, n = { 183, 182, 184, 186, 189, 181, 185, 187, 188 } },
        { "Dungeon Set 2", set = true, n = { 518, 514, 512, 515, 511, 517, 513, 519, 516 } },
    } },
    { id = "ZGSets", name = "Zul'Gurub Sets", kind = "sets", bosses = {
        { "@area:1977 Sets", set = true, horde = { 476 }, alliance = { 481, 480, 478, 477, 474, 482, 479, 475 } },
        { "Misc Sets", set = true, n = { 461, 463, 466, 462, 465, 464 } },
    } },
    { id = "AQSets", name = "Ahn'Qiraj Sets", kind = "sets", bosses = {
        { "@area:3428 20 Sets", set = true, horde = { 502 }, alliance = { 500, 508, 498, 510, 495, 504, 494, 506 } },
        { "@area:3428 40 Sets", set = true, horde = { 501 }, alliance = { 499, 507, 497, 509, 496, 503, 493, 505 } },
    } },
    { id = "MiscSets", name = "Other Sets", kind = "sets", bosses = {
        { "Cloth", set = true, n = { 421, 520, 122, 81, 492, 536 } },
        { "Leather", set = true, n = { 442, 441, 121, 142, 141, 143, 144, 534, 161, 162, 221 } },
        { "Mail", set = true, n = { 443, 123, 489, 491, 1, 490, 163, 535 } },
        { "Plate", set = true, n = { 444, 124, 321, 533 } },
        { "Misc Sets", set = true, n = { 261, 41, 65, 241 } },
    } },
    { id = "WorldEpics", name = "World Epics", kind = "collection", bosses = {
    } },
    { id = "Mounts", name = "Mounts", kind = "collection", bosses = {
        { "Faction Mounts", horde = { 18798, 18797, 18796, 18795, 18794, 18793, 18790, 18789, 18788, 18791, 13334, 5668, 5665, 1132, 15290, 15277, 8592, 8591, 8588, 13333, 13332, 13331 }, alliance = { 18785, 18786, 18787, 18772, 18773, 18774, 18776, 18777, 18778, 5873, 5872, 5864, 13321, 13322, 8563, 8595, 2414, 5656, 5655, 2411, 18902, 18767, 18766, 8632, 8631, 8629 } },
        { "PvP", horde = { 19029, 29469, 29466, 29472, 29470 }, alliance = { 19030, 29467, 29465, 29468, 29471 } },
        { "Drops", n = { 13335, 19872, 19902 } },
        { "Reputation", alliance = { 13086 } },
        { "Special", n = { 21176, 23720 } },
        { "?", n = { 21218, 21323, 21321, 21324 } },
    } },
    { id = "Companions", name = "Companions", kind = "collection", bosses = {
        { "Crafting", n = { 15996, 11826, 4401, 11825, 21277 } },
        { "Drops", n = { 8494, 8492, 8498, 8499, 10822, 8490, 8491, 20769, 11110 } },
        { "Quest", n = { 12264, 11474, 12529, 10398 } },
        { "Vendor", n = { 11023, 10393, 10394, 10392, 8497, 10360, 10361, 8500, 8501, 8485, 8486, 8487, 8490, 8488, 8489, 8496, 8495, 11026, 11027 } },
        { "World Events", n = { 21305, 21301, 21308, 21309, 22235, 23083, 23015, 22781, 23007, 23002 } },
        { "Unobtainable", n = { 13582, 13584, 13583, 22780, 22114, 20651, 20371 } },
    } },
    { id = "Tabards", name = "Tabard", kind = "collection", bosses = {
        { "Tabard", n = { 23192 } },
        { "Capitals", horde = { 45582, 45581, 45584, 45583, 45585 }, alliance = { 45579, 45577, 45578, 45574, 45580, 64882 } },
        { "Factions - Classic", n = { 43154 } },
        { "PvP", horde = { 15197, 15199, 19505, 19031, 20131 }, alliance = { 15196, 15198, 19506, 19032, 20132 } },
        { "Arena", n = { 45983, 49086, 51534 } },
        { "Unobtainable", n = { 19160, 36941, 28788, 38312, 23705, 23709, 38313, 38309, 38310, 38314, 38311 } },
    } },
    { id = "Legendarys", name = "Legendaries", kind = "collection", bosses = {
    } },
    { id = "Darkmoon", name = "Darkmoon Faire", kind = "event", faction = 909, bosses = {
        { "?", n = { 19491, 19426, 19293, 19291, 9249, 19296, 19297, 19292, 19298, 19295 } },
        { "Classic", n = { 19228, 19267, 19257, 19277 } },
    } },
    { id = "GurubashiArena", name = "Gurubashi Arena", kind = "event", bosses = {
        { "Gurubashi Arena", n = { 18709, 18710, 18711, 18712, 18706 } },
    } },
    { id = "FishingExtravaganza", name = "Stranglethorn Fishing Extravaganza", kind = "event", bosses = {
        { "Stranglethorn Fishing Extravaganza", n = { 19970, 19979, 19805, 19803, 19806, 19808, 19972, 19969, 19971 } },
    } },
    { id = "LunarFestival", name = "Lunar Festival", kind = "event", bosses = {
        { "Lunar Festival", n = { 21100, 21157, 21538, 21539, 21541, 21544, 21543 } },
        { "Lunar Festival Fireworks Pack", n = { 21558, 21559, 21557, 21561, 21562, 21537, 21713, 21589, 21590, 21592, 21593, 21595 } },
        { "Lucky Red Envelope", n = { 21540, 21536, 21744, 21745 } },
        { "Plans", n = { 21722, 21738, 21724, 21725, 21726, 21727, 21728, 21729, 21723, 21737, 21730, 21731, 21732, 21733, 21734, 21735 } },
    } },
    { id = "Valentineday", name = "Love is in the Air", kind = "event", bosses = {
        { "Love is in the Air", n = { 22206, 22279, 22235, 22200, 22261, 22218, 21813, 22237, 22238, 22236, 22239, 22276, 22278, 22280, 22277, 22281, 22282 } },
    } },
    { id = "Noblegarden", name = "Noblegarden", kind = "event", bosses = {
        { "Brightly Colored Egg", n = { 19028, 6833, 6835, 7807, 7808, 7806 } },
    } },
    { id = "ChildrensWeek", name = "Childrens Week", kind = "event", bosses = {
        { "Childrens Week", n = { 23007, 23015, 23002, 23022 } },
    } },
    { id = "MidsummerFestival", name = "Midsummer Festival", kind = "event", bosses = {
        { "Midsummer Festival", n = { 23379, 23323, 23324, 23083, 23247, 23246, 23435, 23327, 23326, 23211 } },
    } },
    { id = "HarvestFestival", name = "Harvest Festival", kind = "event", bosses = {
        { "Harvest Festival", n = { 19697, 20009, 20010, 19995, 19996, 19994, 19997 } },
    } },
    { id = "Halloween", name = "Hallow's End", kind = "event", bosses = {
        { "Hallow's End - Misc", n = { 20400, 18633, 18632, 18635, 20557, 20389, 20388, 20390 } },
        { "Hallow's End - Wands", n = { 20410, 20409, 20399, 20398, 20397, 20413, 20411, 20414 } },
        { "Hallow's End - Masks", n = { 20561, 20391, 20566, 20564, 20570, 20572, 20568, 20573, 20562, 20392, 20565, 20563, 20569, 20571, 20567, 20574 } },
    } },
    { id = "WinterVeil", name = "Feast of Winter Veil", kind = "event", bosses = {
        { "Misc", n = { 21525, 21524, 17712, 17202, 21212, 21519 } },
        { "Gaily Wrapped Present", n = { 21301, 21308, 21305, 21309 } },
        { "Festive Gift", n = { 21328 } },
        { "Smokywood Pastures Special Gift", n = { 17706, 17725, 17720, 17722, 17709, 17724, 21325, 21213 } },
        { "Gently Shaken Gift", n = { 21235, 21241 } },
        { "Smokywood Pastures", n = { 17201, 17200, 17344, 17406, 17407, 17408, 17404, 17405, 17196, 17403, 17402, 17194, 17303, 17304, 17307 } },
    } },
    { id = "ElementalInvasions", name = "Elemental Invasions", kind = "event", bosses = {
        { "Elemental Invasions", n = { 18671, 19268, 18672, 18678, 19268, 21548, 18679, 18673, 19268, 18674, 18676, 19268, 21548, 18677 } },
    } },
    { id = "SilithusAbyssal", name = "Silithus Abyssal", kind = "event", bosses = {
        { "Abyssal Dukes", n = { 20665, 20666, 20514, 20664, 20668, 20669, 20514, 20667, 20674, 20675, 20514, 20673, 20671, 20672, 20514, 20670 } },
        { "Abyssal Lords", n = { 20682, 20515, 20681, 20680, 20685, 20515, 20684, 20683, 20691, 20515, 20690, 20689, 20688, 20515, 20686, 20687 } },
        { "Abyssal Templars", n = { 20657, 20655, 20656, 20513, 20654, 20653, 20652, 20513, 20660, 20659, 20658, 20513, 20663, 20661, 20662, 20513 } },
    } },
    { id = "AQOpening", name = "AQ opening", kind = "event", bosses = {
        { "AQ opening", n = { 21138, 21529, 21530, 21139, 21531, 21532, 21137, 21517, 21527, 21526, 21025, 21175, 21176, 21523, 21521, 21522, 21520 } },
    } },
    { id = "ScourgeInvasion", name = "Scourge Invasion", kind = "event", bosses = {
        { "Scourge Invasion", n = { 23123, 23122, 22999, 22484, 23085, 23091, 23084, 23089, 23093, 23081, 23194, 23195, 23196, 23088, 23092, 23082, 23087, 23090, 23078 } },
        { "@area:2017 - Balzaphon", n = { 23126, 23125, 23124 } },
        { "@area:2057 - Lord Blackwood", n = { 23132, 23156, 23139 } },
        { "@area:2557 - Revanchion", n = { 23127, 23129, 23128 } },
        { "Scarlet Monastery - Graveyard - Scorn", n = { 23169, 23170, 23168 } },
        { "@area:209 - Sever", n = { 23173, 23171 } },
        { "@area:722 - Lady Falther'ess", n = { 23178, 23177 } },
    } },
    } end,
}

WM.LootData.tbcCollections = {
    expansion = 1, category = "collections", label = "Burning Crusade", order = 2,
    build = function() return {
    { id = "BadgeofJustice", name = "Badge of Justice", kind = "vendor", bosses = {
        { "Armor - Cloth", n = { 32089, 32090, 30762, 30764, 30761, 30763 } },
        { "Armor - Leather", n = { 32087, 32088, 30776, 30780, 30778, 30779 } },
        { "Armor - Mail", n = { 32085, 32086, 30773, 30774, 30770, 30772 } },
        { "Armor - Plate", n = { 32083, 32084, 30769, 30767, 30766, 30768 } },
        { "Off Hand", n = { 29266, 29267, 29268, 29269, 29270, 29271, 29272, 29273, 29274, 29275 } },
        { "Neck", n = { 29368, 29374, 29381, 29386 } },
        { "Cloak", n = { 29369, 29375, 29382, 29385 } },
        { "Finger", n = { 29367, 29373, 29379, 29384 } },
        { "Trinket", n = { 29370, 29376, 29383, 29387 } },
        { "Relic", n = { 29388, 29389, 29390 } },
    } },
    { id = "BadgeofJustice4", name = "Badge of Justice (Phase 4)", kind = "vendor", phase = 4, bosses = {
        { "Armor - Cloth", n = { 33588, 33586, 33291, 33584, 33589, 33587, 33585 } },
        { "Armor - Leather", n = { 33972, 33973, 33566, 33578, 33974, 33559, 33577, 33287, 33557, 33552, 33579, 33580, 33583, 33582, 33540, 33539, 33538, 33222 } },
        { "Armor - Mail", n = { 33970, 33965, 33535, 33534, 33536, 33537, 33529, 33528, 33280, 33527, 33532, 33531, 33386, 33530, 33324 } },
        { "Armor - Plate", n = { 33810, 33514, 33513, 33331, 33512, 33501, 33520, 33519, 33518, 33207, 33522, 33516, 33517, 33279, 33524, 33515, 33523 } },
        { "Off Hand", n = { 33334, 33325 } },
        { "Neck", n = { 33296 } },
        { "Back", n = { 33593, 35321, 33304, 35324, 33484, 33333 } },
        { "Trinket", n = { 35326, 34049, 34162, 34163, 33832, 34050 } },
        { "Relic", n = { 33510, 33509, 33508, 33503, 33502, 33504, 33506, 33507, 33505 } },
        { "Wand", n = { 33192 } },
    } },
    { id = "BadgeofJusticeP5", name = "Badge of Justice (Phase 5)", kind = "vendor", phase = 5, bosses = {
        { "Armor - Cloth", n = { 34926, 34924, 34925, 34919, 34917, 34918, 34938, 34936, 34937 } },
        { "Armor - Leather", n = { 34911, 34906, 34910, 34929, 34927, 34928, 34902, 34901, 34900, 34904, 34903, 34905 } },
        { "Armor - Mail", n = { 34932, 34931, 34930, 34916, 34912, 34914, 34935, 34934, 34933 } },
        { "Armor - Plate", n = { 34947, 34945, 34946, 34941, 34939, 34940, 34923, 34921, 34922, 34944, 34942, 34943 } },
        { "Weapon", n = { 34894, 34949, 34952, 34950, 34893, 34951, 34891, 34892, 34898, 34895, 34896 } },
        { "Finger", n = { 34887, 34890, 34889, 34888 } },
        { "Gem", n = { 32228, 32249, 32231, 32230, 32227, 32229 } },
    } },
    { id = "BCCSunmote", name = "Sunmote (Isle of Quel'Danas)", kind = "vendor", phase = 5, bosses = {
        { "Armor - Cloth", n = { 34405, 34393, 34399, 34406, 34386 } },
        { "Armor - Leather", n = { 34403, 34391, 34398, 34407, 34384, 34404, 34397, 34392, 34408, 34385 } },
        { "Armor - Mail", n = { 34402, 34396, 34390, 34409, 34383 } },
        { "Armor - Plate", n = { 34401, 34389, 34395, 34382, 34400, 34388, 34394, 34381 } },
    } },
    { id = "WorldEpicsBC", name = "World Epics", kind = "collection", bosses = {
    } },
    { id = "MountsBC", name = "Mounts", kind = "collection", bosses = {
        { "Faction Mounts", horde = { 29223, 29224, 28936, 25531, 25532, 25533, 25477, 29220, 29221, 29222, 28927, 25474, 25475, 25476 }, alliance = { 29745, 29746, 29747, 25527, 25528, 25529, 25473, 28481, 29743, 29744, 25470, 25471, 25472 } },
        { "PvP", horde = { 34129, 29228, 28915, 30609, 34092, 37676, 43516 }, alliance = { 35906, 29228, 28915, 30609, 34092, 37676, 43516 } },
        { "Drops", n = { 32768, 33809, 30480, 32458 } },
        { "Reputation", horde = { 29102, 29104, 29105, 29103, 31829, 31831, 31833, 31835, 31836, 33999, 32319, 32314, 32317, 32316, 32318, 32858, 32859, 32857, 32860, 32861, 32862 }, alliance = { 29227, 29229, 29230, 29231, 31830, 31832, 31834, 31836, 33999, 32319, 32314, 32317, 32316, 32318, 32858, 32859, 32857, 32860, 32861, 32862 } },
        { "Crafting", n = { 34061, 34060 } },
        { "Special", n = { 33225, 33224, 38576, 35226, 35225 } },
    } },
    { id = "CompanionsBC", name = "Companions", kind = "collection", bosses = {
        { "Drops", n = { 33993, 35504, 34535, 29960 } },
        { "Quest", n = { 31760 } },
        { "Vendor", n = { 34478, 38628, 29363, 29364, 29903, 29904, 29902, 29901, 29957, 29956, 29953, 29958 } },
        { "World Events", n = { 34425, 34955, 32233, 33154, 32617, 32622, 32616 } },
        { "Fishing", n = { 35350, 33818, 35349, 33816, 27445 } },
        { "Unobtainable", n = { 34493, 32588, 38050, 34492, 34519, 34518, 32498, 32465, 31665, 37297, 37298, 39656, 25535, 30360 } },
    } },
    { id = "TabardsBC", name = "Tabard", kind = "collection", bosses = {
        { "Factions", horde = { 24004, 31773 }, alliance = { 31779, 31780, 31804, 31776, 31777, 31778, 32828, 31781, 32445, 31775, 35221, 23999, 31774 } },
        { "Unobtainable Tabards", n = { 36941, 28788 } },
    } },
    { id = "LegendarysBC", name = "Legendaries", kind = "collection", bosses = {
    } },
    { id = "ChildrensWeekBC", name = "Childrens Week", kind = "event", bosses = {
        { "Childrens Week", n = { 23007, 23015, 23002, 23022, 32616, 32617, 32622 } },
    } },
    { id = "MidsummerFestivalBC", name = "Midsummer Festival", kind = "event", bosses = {
        { "Midsummer Festival", n = { 23083, 34686, 23324, 23323, 34683, 34685, 23247, 34599, 34684, 23246, 23215, 23211, 23435, 23327, 23326 } },
        { "@area:3717 - Ahune", n = { 278953, 279240, 278819, 278823, 278774, 35723, 35498, 34955, 35557 }, h = { 29434, 278827, 278833, 278838, 278847, 278953, 279240, 278819, 278823, 278774, 35723, 35498, 34955, 35557 } },
    } },
    { id = "Brewfest", name = "Brewfest", kind = "event", bosses = {
        { "Brewfest", n = { 33968, 33864, 33967, 33969, 33863, 33862, 33966, 33868, 33047, 34008, 33016, 37829, 33976, 33977, 32233, 34028, 37599, 33927, 37750, 39477, 39476, 37816 } },
        { "Food", n = { 33043, 34017, 34018, 34019, 34020, 34021, 34022, 33034, 33035, 33036 } },
        { "@area:1584 - Coren Direbrew", n = { 37128, 37127, 38287, 38290, 38288, 38289, 37597, 33977, 37828, 37863, 38280 } },
    } },
    { id = "HalloweenBC", name = "Hallow's End", kind = "event", bosses = {
        { "Hallow's End - Misc", n = { 20400, 18633, 18632, 18635, 20557, 20389, 20388, 20390 } },
        { "Hallow's End - Wands", n = { 20410, 20409, 20399, 20398, 20397, 20413, 20411, 20414 } },
        { "Hallow's End - Masks", n = { 20561, 20391, 20566, 20564, 20570, 20572, 20568, 20573, 20562, 20392, 20565, 20563, 20569, 20571, 20567, 20574 } },
        { "@area:796 - Headless Horseman", n = { 34075, 34073, 34074, 33808, 38175, 33292, 34068, 33277, 37012, 33182, 33176, 33184, 37011, 33154 } },
    } },
    } end,
}
