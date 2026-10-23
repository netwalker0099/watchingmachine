-- Watching Machine: Loot Browser data — Wrath of the Lich King
-- Shown only on a Wrath client (expansion 2). The dungeon and raid tables
-- go in build(), in the same format as LootTBC.lua; until then the
-- Loot Browser shows only Wrath's crafting, factions and PvP. Bosses marked expansion = 2 in
-- the Classic and TBC files (holiday bosses, Wrath-era changes) already
-- switch on by themselves.

local _, WM = ...
WM.LootData = WM.LootData or {}
WM.LootData.wrath = {
    expansion = 2, category = "dungeons", label = "Wrath of the Lich King", order = 3,
    build = function() return {
    } end,
}
