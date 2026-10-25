# Tools (not part of the addon)

Scripts used to build Watching Machine's data files and docs. The game never
loads this folder (nothing here is in the `.toc`). Third-party addons are
only read for facts (IDs, numbers), which are written in our own format with
a "compiled with the help of X's research" credit; their code is never
copied. Unpack each addon into its own empty folder and pass the path in.

- `loot_extract.lua` + `loot_write_data.py`: AtlasLoot Classic data to
  `Data/Loot*.lua` (dungeons, crafting, factions, PvP, collections, item
  sets, craft spells). Wrath dungeons and raids still need the AtlasLoot
  Classic **WotLK** data files (`AtlasLootClassic_DungeonsAndRaids/data-wrath.lua`):
  add a `{ "dungeons", "wrath", "DungeonsAndRaids", "data-wrath.lua", 3 }` run
  and write `Data/LootWrath.lua`.
  ```
  lua5.1 tools/loot_extract.lua <atlasloot dir> <out dir>
  python3 -I tools/loot_write_data.py <out dir> <data out dir>
  ```
  Compare the results with `Data/` (`cmp`) before copying them over.
- `attune_extract.lua`: the Attune addon to `Data/Attunements.lua`.
- `gtfo_extract.lua`: GTFO's spell lists to `Data/Hazards.lua`.
- `curseforge_description.py`: rebuilds `docs/CURSEFORGE-DESCRIPTION.md`
  from `README.md` (run from the repo root after changing the README):
  `python3 -I tools/curseforge_description.py`
- `release_notes.py`: one version's CHANGELOG section, for a release's
  notes (the release workflow posts it to CurseForge):
  `python3 -I tools/release_notes.py 3.56`
- `make_release.py`: a zip for testers with only what the game loads (the
  toc, the files it lists, `Bindings.xml`, `Media`), from the committed
  files: `python3 -I tools/make_release.py .` writes
  `release/WatchingMachine-<version>.zip` (`release/` is ignored by git).
