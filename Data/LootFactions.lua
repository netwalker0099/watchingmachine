-- Watching Machine: Loot Browser data — reputation rewards
-- What each faction sells or gives at each standing.
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

WM.LootData.classicFactions = {
    expansion = 0, category = "factions", label = "Classic", order = 1,
    build = function() return {
    { id = "ArgentDawn", name = "Argent Dawn", kind = "faction", faction = 529, bosses = {
        { "Exalted", n = { 18182, 22523, 22523 } },
        { "Revered", n = { 13810, 13813, 19217, 19329, 19205, 19447, 18171, 18169, 18170, 18172, 18173, 22523, 22523 } },
        { "Honored", n = { 19216, 19328, 19203, 19442, 19446, 13482, 22523, 22523 } },
        { "Friendly", n = { 13724, 22523, 22523 } },
    } },
    { id = "Timbermaw", name = "Timbermaw", kind = "faction", faction = 576, bosses = {
        { "Exalted", n = { 21326 } },
        { "Revered", n = { 19218, 19327, 19204 } },
        { "Honored", n = { 16768, 16769, 19202, 19326, 19215, 19445 } },
        { "Friendly", n = { 13484, 15754, 15742, 22392 } },
    } },
    { id = "ThoriumBrotherhood", name = "Thorium Brotherhood", kind = "faction", faction = 59, bosses = {
        { "Exalted", n = { 20040, 19210, 19211, 19212 } },
        { "Revered", n = { 19220, 19333, 19332, 17053, 19331, 19207, 17052, 19208, 19209, 19449 } },
        { "Honored", n = { 17017, 19219, 19330, 17049, 17025, 19206, 17059, 17060, 19448 } },
        { "Friendly", n = { 17018, 17023, 17022, 17051, 20761, 19444 } },
    } },
    { id = "CenarionCircle", name = "Cenarion Circle", kind = "faction", faction = 609, bosses = {
        { "Exalted", n = { 20382, 21188, 21180, 21190 } },
        { "Revered", n = { 22683, 22312, 22774, 22771, 20508, 20511, 22766, 22219, 21184, 21186, 21185, 21189 } },
        { "Honored", n = { 22773, 22770, 20507, 20510, 22767, 22214, 20733, 21181, 21183, 21182 } },
        { "Friendly", n = { 22772, 22310, 22769, 20506, 20509, 22768, 22209, 20732, 21178, 21187, 21179 } },
    } },
    { id = "ZandalarTribe", name = "Zandalar Tribe", kind = "faction", faction = 270, bosses = {
        { "Exalted", n = { 20013, 20077, 20076, 20078 } },
        { "Revered", n = { 19764, 19769, 19772, 19776, 19779, 20011, 20080, 20079, 20081 } },
        { "Honored", n = { 19765, 20000, 19770, 19773, 19777, 19780, 20014, 20756, 20031 } },
        { "Friendly", n = { 19766, 19771, 20001, 19778, 19781, 20012, 20757 } },
    } },
    { id = "BroodOfNozdormu", name = "Brood of Nozdormu", kind = "faction", faction = 910, bosses = {
        { "Exalted", n = { 21210, 21205, 21200 } },
        { "Revered", n = { 21209, 21204, 21199 } },
        { "Honored", n = { 21208, 21203, 21198 } },
        { "Friendly", n = { 21207, 21202, 21197 } },
        { "Neutral", n = { 21206, 21201, 21196 } },
    } },
    { id = "HydraxianWaterlords", name = "Hydraxian Waterlords", kind = "faction", faction = 749, bosses = {
        { "Revered", n = { 22687, 22698, 22705, 22695, 22754 } },
        { "Honored", n = { 17333 } },
    } },
    { id = "BloodsailBuccaneers", name = "Bloodsail Buccaneers", kind = "minor", faction = 87, bosses = {
        { "Friendly", n = { 12185, 22742, 22743, 22745 } },
    } },
    { id = "WintersaberTrainers", name = "Wintersaber Trainers", kind = "minor", faction = 589, bosses = {
        { "Exalted", alliance = { {0,13086} } },
    } },
    } end,
}

WM.LootData.tbcFactions = {
    expansion = 1, category = "factions", label = "Burning Crusade", order = 2,
    build = function() return {
    { id = "TheAldor", name = "The Aldor", kind = "faction", faction = 932, bosses = {
        { "Exalted", n = { 29123, 29124, 28886, 28887, 28888, 28889, 31779, 23602, 29702, 29689, 24295, 30844 } },
        { "Revered", n = { 29127, 29128, 29130, 24177, 23604, 29703, 29691, 25721 } },
        { "Honored", n = { 29129, 28881, 28878, 28885, 28882, 23145, 23603, 29704, 29693, 30843, 24293 } },
        { "Friendly", n = { 23149, 23601, 30842 } },
    } },
    { id = "TheScryers", name = "The Scryers", kind = "faction", faction = 934, bosses = {
        { "Exalted", n = { 29126, 29125, 28910, 28911, 28912, 28909, 31780, 23600, 29698, 29677, 24294 } },
        { "Revered", n = { 29131, 29134, 29132, 29133, 24176, 22908, 23599, 29700, 29684, 25722 } },
        { "Honored", n = { 28907, 28908, 28904, 28903, 23143, 23598, 29701, 29682, 24292 } },
        { "Friendly", n = { 23133, 23597 } },
    } },
    { id = "TheShatar", name = "The Sha'tar", kind = "faction", faction = 935, bosses = {
        { "Exalted", n = { 29177, 29175, 29176, 31781, 33153, 31354 } },
        { "Revered", n = { 29180, 29179, 29191, 30634, 24182, 28281, 22537, 22915, 13517, 33159 } },
        { "Honored", n = { 29195, 30826, 33155, 28273, 29717, 35330, 35333, 35341, 35345, 35359, 35362, 35375, 35368, 35380, 35381, 35388, 35395, 35404, 35416, 35407 } },
        { "Friendly", n = { 25904 } },
    } },
    { id = "LowerCity", name = "Lower City", kind = "faction", faction = 1011, bosses = {
        { "Exalted", n = { 30834, 30832, 30830, 31778, 33148, 31357 } },
        { "Revered", n = { 30836, 30835, 30841, 30846, 30633, 24179, 24175, 33157, 22910, 34200 } },
        { "Honored", n = { 29199, 22538, 30833, 35331, 35335, 35340, 35344, 35357, 35361, 35373, 35370, 35378, 35382, 35389, 35391, 35405, 35412, 35411 } },
        { "Friendly", n = { 23138 } },
    } },
    { id = "KeepersOfTime", name = "Keepers of Time", kind = "faction", faction = 989, bosses = {
        { "Exalted", n = { 29183, 29181, 29182, 31777, 33152, 31355 } },
        { "Revered", n = { 29184, 29185, 29186, 30635, 24181, 24174, 33158 } },
        { "Honored", n = { 29198, 28272, 22536, 25910, 33160, 29713, 35328, 35334, 35338, 35346, 35356, 35363, 35372, 35369, 35376, 35384, 35390, 35393, 35402, 35414, 35410 } },
    } },
    { id = "TheVioletEye", name = "The Violet Eye", kind = "faction", faction = 967, bosses = {
        { "Exalted", n = { 29283, 29287, 29290, 29279, 33124, 33165 } },
        { "Revered", n = { 29282, 29286, 34581, 34582, 29291, 29278, 31394, 33205 } },
        { "Honored", n = { 29281, 29285, 31113, 29187, 29289, 29277, 31395, 31393, 31401, 33209 } },
        { "Friendly", n = { 29280, 29284, 29288, 29276 } },
    } },
    { id = "CenarionExpedition", name = "Cenarion Expedition", kind = "faction", faction = 942, bosses = {
        { "Exalted", n = { 33999, 29170, 29172, 29171, 31804, 31390, 31402, 33149, 31356, 22922, 29721 } },
        { "Revered", n = { 29174, 31949, 29173, 29192, 30623, 31392, 31391, 24183, 22918, 28271 } },
        { "Honored", n = { 25838, 25836, 25835, 29194, 25735, 25736, 29720, 25869, 32070, 23618, 28632, 25526, 35329, 35336, 35342, 35347, 35358, 35365, 35374, 35367, 35379, 35385, 35387, 35394, 35403, 35415, 35408 } },
        { "Friendly", n = { 24417, 24429, 25737, 23814 } },
    } },
    { id = "TheConsortium", name = "The Consortium", kind = "faction", faction = 933, bosses = {
        { "Exalted", n = { 29122, 29119, 29121, 31776, 33622 } },
        { "Revered", n = { 29117, 29116, 29115, 24178, 25903, 33156, 33305, 25734, 22535, 23874 } },
        { "Honored", n = { 29457, 29118, 29456, 25733, 24314, 23134, 23155, 23150, 25908, 25902, 22552 } },
        { "Friendly", n = { 25732, 28274, 23146, 23136 } },
    } },
    { id = "AshtongueDeathsworn", name = "Ashtongue Deathsworn", kind = "faction", faction = 1012, phase = 3, bosses = {
        { "Exalted", n = { 32486, 32487, 32488, 32489, 32490, 32492, 32491, 32493, 32485 } },
        { "Honored", n = { 32443, 32441, 32433, 32434, 32431, 32432, 32447, 32439, 32437 } },
        { "Friendly", n = { 32444, 32442, 32436, 32435, 32430, 32429, 32440, 32438 } },
    } },
    { id = "TheScaleOfTheSands", name = "The Scale of the Sands", kind = "faction", faction = 990, phase = 3, bosses = {
        { "Exalted", n = { 29301, 29297, 29305, 29309 } },
        { "Revered", n = { 29300, 29296, 32292, 32308, 32309, 32302, 29304, 29308 } },
        { "Honored", n = { 29299, 29295, 31737, 35763, 32306, 32305, 32304, 35762, 32299, 32301, 29303, 29306, 31735, 32300, 32311, 35765, 32312, 32310, 35764 } },
        { "Friendly", n = { 29298, 29294, 32274, 32283, 32277, 32282, 32284, 32281, 32288, 29302, 29307, 32286, 32287, 32290, 32293, 32291, 32294 } },
    } },
    { id = "ShatteredSunOffensive", name = "Shattered Sun Offensive", kind = "faction", faction = 1077, phase = 5, bosses = {
        { "Exalted", n = { 34676, 34675, 34678, 34679, 34680, 34677, 35221, 35755, 35752, 35754, 35753, 35322, 35323, 35325, 35247, 35257, 35267, 35258, 37504, 35242, 35243, 35265, 35270 } },
        { "Revered", n = { 34667, 34672, 34666, 34671, 34670, 34673, 34674, 34665, 29193, 35695, 35696, 35769, 35768, 35767, 35766, 35252, 35259, 35241, 35271, 35708, 35505, 35502, 35699, 35698, 35697 } },
        { "Honored", n = { 35238, 35251, 35266, 35239, 35240, 35253, 35268, 35269, 35254, 35500, 34872 } },
        { "Friendly", n = { 34780, 35244, 35255, 35246, 35256, 35262, 35248, 35260, 35263, 35264, 35249, 35250, 35261 } },
    } },
    { id = "ShatariSkyguard", name = "Sha'tari Skyguard", kind = "minor", faction = 1031, bosses = {
        { "Exalted", n = { 32770, 32771, 32445, 38628, 32319, 32314, 32317, 32316, 32318 } },
        { "Revered", n = { 32539, 32538 } },
        { "Honored", n = { 32721 } },
        { "Friendly", n = { 32722 } },
    } },
    { id = "Netherwing", name = "Netherwing", kind = "minor", faction = 1015, bosses = {
        { "Exalted", n = { 32858, 32859, 32857, 32860, 32861, 32862 } },
        { "Revered", n = { 32864 } },
        { "Honored", n = { 32695, 32863 } },
        { "Friendly", n = { 32694 } },
    } },
    { id = "Sporeggar", name = "Sporeggar", kind = "minor", faction = 970, bosses = {
        { "Exalted", n = { 34478, 31775, 22906 } },
        { "Revered", n = { 29150, 29149, 22916, 38229 } },
        { "Honored", n = { 25827, 25828, 25550 } },
        { "Friendly", n = { 25548, 24539, 27689, 30156 } },
    } },
    { id = "Ogrila", name = "Ogri'la", kind = "minor", faction = 1038, phase = 2, bosses = {
        { "Exalted", n = { 32647, 32648, 32651, 32645, 32828, 32569 } },
        { "Revered", n = { 32653, 32654, 32652, 32650 } },
        { "Honored", n = { 32784, 32783, 32572 } },
        { "Friendly", n = { 32910, 32909 } },
    } },
    { id = "Tranquillien", name = "Tranquillien", kind = "faction", side = "Horde", faction = 922, bosses = {
        { "Exalted", horde = { 22990 } },
        { "Revered", horde = { 22986, 22987, 22985 } },
        { "Honored", horde = { 28155, 28158, 28162 } },
        { "Friendly", horde = { 22991, 22992, 22993, 28164 } },
    } },
    { id = "Thrallmar", name = "Thrallmar", kind = "faction", side = "Horde", faction = 947, bosses = {
        { "Exalted", horde = { 29155, 29165, 29152, 24004, 33151, 24002, 31362 } },
        { "Revered", horde = { 29168, 29167, 32882, 29190, 30637, 31358, 24003, 34201 } },
        { "Honored", horde = { 25824, 25823, 29197, 25739, 25740, 31361, 29232, 24001, 35332, 35337, 35339, 35343, 35360, 35364, 35371, 35366, 35377, 35383, 35386, 35392, 35406, 35413, 35409 } },
        { "Friendly", horde = { 24006, 24009, 25738, 31359, 24000 } },
    } },
    { id = "TheMaghar", name = "The Mag'har", kind = "faction", side = "Horde", faction = 941, bosses = {
        { "Exalted", horde = { 29139, 29135, 29137, 31773, 29102, 29104, 29105, 29103, 31829, 31831, 31833, 31835 } },
        { "Revered", horde = { 29147, 29141, 29145, 25743, 22917 } },
        { "Honored", horde = { 29143, 25742, 34174, 34172, 29664 } },
        { "Friendly", horde = { 25741 } },
    } },
    { id = "HonorHold", name = "Honor Hold", kind = "faction", side = "Alliance", faction = 946, bosses = {
        { "Exalted", alliance = { 29153, 29156, 29151, 23999, 33150, 23619, 29722 } },
        { "Revered", alliance = { 29169, 29166, 32883, 29189, 30622, 24180, 22547, 34218 } },
        { "Honored", alliance = { 25826, 25825, 29196, 29214, 29215, 29719, 25870, 22905, 35464, 35467, 35466, 35465, 35469, 35470, 35471, 35468, 35475, 35474, 35472, 35473, 35476, 35477, 35478 } },
        { "Friendly", alliance = { 24007, 24008, 29213, 23142, 22531 } },
    } },
    { id = "Kurenai", name = "Kurenai", kind = "faction", side = "Alliance", faction = 978, bosses = {
        { "Exalted", alliance = { 29140, 29136, 29138, 31774, 29227, 29229, 29230, 29231, 31830, 31832, 31834, 31836 } },
        { "Revered", alliance = { 29148, 29142, 29146, 29218, 30443 } },
        { "Honored", alliance = { 29144, 29219, 34175, 34173, 30444 } },
        { "Friendly", alliance = { 29217 } },
    } },
    } end,
}

WM.LootData.wrathFactions = {
    expansion = 2, category = "factions", label = "Wrath of the Lich King", order = 3,
    build = function() return {
    { id = "AllianceVanguard", name = "Alliance Vanguard", kind = "faction", side = "Alliance", faction = 1037, bosses = {
        { "Exalted", n = { 44503, 44937, 50372 } },
        { "Revered", n = { 38459, 38465, 38455, 38463, 38453, 38457, 38464 } },
    } },
    { id = "ArgentCrusade", name = "Argent Crusade", kind = "faction", faction = 1106, bosses = {
        { "Exalted", n = { 44297, 44295, 44296, 44283, 42187 } },
        { "Revered", n = { 44248, 44247, 44244, 44245, 44214, 50369, 41726 } },
        { "Honored", n = { 44216, 44240, 44239, 44139 } },
        { "Friendly", n = { 43154 } },
    } },
    { id = "FrenzyheartTribe", name = "Frenzyheart Tribe", kind = "faction", faction = 1104, bosses = {
        { "Exalted", n = { 44073, 44719, 44718, 39671, 40067, 40087, 44716 } },
        { "Revered", n = { 44116, 44117, 44122, 44120, 44121, 44123, 44717, 41723 } },
        { "Friendly", n = { 44064, 44072, 41561 } },
    } },
    { id = "HordeExpedition", name = "Horde Expedition", kind = "faction", side = "Horde", faction = 1052, bosses = {
        { "Exalted", n = { 44502, 44938, 50373 } },
        { "Revered", n = { 38458, 38461, 38454, 38452, 38462, 38456, 38460 } },
    } },
    { id = "KirinTor", name = "Kirin Tor", kind = "faction", faction = 1090, bosses = {
        { "Exalted", n = { 44180, 44181, 44182, 44183, 41718, 42188 } },
        { "Revered", n = { 44179, 44176, 44173, 44174, 50368 } },
        { "Honored", n = { 44167, 44170, 44171, 44166, 44141 } },
        { "Friendly", n = { 43157 } },
    } },
    { id = "KnightsoftheEbonBlade", name = "Knights of the Ebon Blade", kind = "faction", faction = 1098, bosses = {
        { "Exalted", n = { 44302, 44303, 44305, 44306, 41725 } },
        { "Revered", n = { 44256, 44258, 44257, 44250, 44249, 50367, 41721, 42183 } },
        { "Honored", n = { 44242, 44243, 44241, 44512, 44138 } },
        { "Friendly", n = { 43155, 41562 } },
    } },
    { id = "TheAshenVerdict", name = "The Ashen Verdict", kind = "faction", faction = 1156, bosses = {
        { "Exalted", n = { 50404, 50398, 52572, 50402, 50400 } },
        { "Revered", n = { 50403, 50397, 52571, 50401, 50399, 49971, 49973, 49969, 49959, 49965, 49957, 49962, 49953, 49955 } },
        { "Honored", n = { 50388, 50384, 52570, 50387, 50386, 49974, 49972, 49970, 49958, 49963, 49961, 49966, 49954, 49956, 52022, 52023 } },
        { "Friendly", n = { 50375, 50377, 52569, 50376, 50378 } },
    } },
    { id = "TheKaluak", name = "The Kalu'ak", kind = "faction", faction = 1073, bosses = {
        { "Exalted", n = { 44050, 44723 } },
        { "Revered", n = { 44051, 44052, 44053, 44509, 45774 } },
        { "Honored", n = { 44061, 44062, 44054, 44055, 44059, 44060, 44057, 44058, 44511, 41574 } },
        { "Friendly", n = { 44049, 41568 } },
    } },
    { id = "TheOracles", name = "The Oracles", kind = "faction", faction = 1105, bosses = {
        { "Exalted", n = { 44074, 44707, 39898, 44721, 39896, 39899, 44722, 39883 } },
        { "Revered", n = { 44104, 44106, 44110, 44109, 44112, 44111, 44108, 39878, 41724 } },
        { "Honored", n = { 44071 } },
        { "Friendly", n = { 44065, 41567 } },
    } },
    { id = "TheSilverCovenant", name = "The Silver Covenant", kind = "faction", side = "Alliance", faction = 1094, bosses = {
        { "Exalted", n = { 46813, 46815, 46820, 46817 } },
    } },
    { id = "TheSunreavers", name = "The Sunreavers", kind = "faction", side = "Horde", faction = 1124, bosses = {
        { "Exalted", n = { 46814, 46816, 46821, 46818 } },
    } },
    { id = "TheSonsofHodir", name = "The Sons of Hodir", kind = "faction", faction = 1119, bosses = {
        { "Exalted", n = { {44086,43961}, 44133, 44134, 44136, 44135, 41720, 42184 } },
        { "Revered", n = { {44080,43958}, 44194, 44195, 44193, 44192 } },
        { "Honored", n = { 44190, 44189, 44131, 44130, 44132, 44129, 44510, 44137 } },
    } },
    { id = "TheWyrmrestAccord", name = "The Wyrmrest Accord", kind = "faction", faction = 1091, bosses = {
        { "Exalted", n = { 43955, 44202, 44203, 44204, 44205, 41722 } },
        { "Revered", n = { 44200, 44198, 44201, 44199, 44152 } },
        { "Honored", n = { 44188, 44196, 44197, 44187, 44140 } },
        { "Friendly", n = { 43156 } },
    } },
    } end,
}
