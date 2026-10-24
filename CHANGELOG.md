# Watching Machine — Changelog

All notable changes to Watching Machine. Versions are listed newest first.

Current release: **3.47.1** — TBC Classic Anniversary patch 2.5.6 (Interface `20506`)

---

## 3.47.1

- **Fixed: Your Characters stopped updating your alts.** Since 3.46 each
  character has its own module switches and a new character starts with
  everything off, so Your Characters stopped saving any character where it
  wasn't switched on: their gold, bags and gear stayed as they were. Now,
  while Your Characters is on for any of your characters, it saves every
  character you log in on (switching it off on a character only hides the
  window there). Its card on such a character says "Off here, still saving
  this character for your others".

---

## 3.47

### Loot Browser

- **Collections**, a new category: the Badge of Justice vendor (with its
  Phase 4 and 5 stock), the Sunmote vendor on the Isle of Quel'Danas,
  world epics, mounts, companions, tabards, legendaries, the Classic item
  sets (tier, dungeon, Zul'Gurub, Ahn'Qiraj and others) and world events
  (Darkmoon Faire, the holidays, Brewfest, Gurubashi Arena, invasions),
  for Classic and The Burning Crusade. Compiled with the help of AtlasLoot
  Classic's research; only the item IDs are kept. Tooltips say "Also in:"
  for collection items, and the search covers them.
- **Search no longer stalls the game.** It used to ask the game for every
  item in the browser (about ten thousand) on each search, which made the
  client request every item it hadn't seen from the server, and it redid
  that every second while names came in. Now:
  - item names are remembered between sessions, for all your characters,
    so a search reads only that list (milliseconds, no calls into the
    game);
  - names the game hasn't shown you yet are learnt in the background, 20
    every quarter of a second, and never asked for again once known (or
    once the game says the item doesn't exist);
  - the results refresh only when a newly learnt name matches your search,
    at most once a second.

---

## 3.46.2

- **Hide inactive** button at the top of the dashboard, next to Fit: shows
  only the modules that are on for this character. Groups with nothing on
  disappear, a card goes as soon as you switch its module off, and with
  nothing on the dashboard says so and points to Show all and Setup.
  **Show all** brings every card back. Remembered per character; Fit sizes
  the dashboard to the cards showing.
- The character key no longer errors if the client hasn't given the
  player's name yet.

---

## 3.46.1

- **Run the setup again** any time: `/wmachine setup`, `/wmachine resetup`
  or the new **Setup** button on the dashboard. Your current setup is kept:
  modules that are on stay ticked in the quick setup and on the guided
  pages, and every setting keeps its value, unless you change it during the
  setup. The welcome window, quick setup and guided introduction say so.
- Fixed: a guided page could error if that module's settings had been reset
  since the page was first shown; each page now fills in its module's
  defaults before showing.

---

## 3.46

### New — Setup, and modules per character

- **First login on a character:** every module starts off, and a welcome
  window offers a **guided setup** (a page per module: what it does, how it
  works, a switch to turn it on, and its main settings explained), a
  **quick setup** (a checklist with presets: Raiding, Guild officer,
  Everything, Nothing), or **copying another character's** modules and
  settings. `/wmachine setup` brings it back any time.
- **Characters that already used the addon** keep every module they had on
  and are offered the setup once.
- **Per character:** which modules are on, and every module's settings.
  Your settings from before become each character's starting point. Data
  about all your characters (Your Characters, logs, enemy list, world
  timers, loot lists, crit records, gear sets, mail log) stays shared;
  ArmorySnap's data stays as the standalone addon uses it.
- **Every dashboard card has an on/off switch** for this character. A
  module that's off isn't started, and its card, the minimap tooltip and
  `/wmachine status` say so. Opening an off module offers to turn it on;
  its commands say how.
- **Turning a module off works straight away:** its events, timers, hooks,
  tooltip lines and chat filters stop and its windows and buttons hide.
- **Parts and links:** the class tools and swing timer follow Class Tools;
  modules that add to each other say so in the setup.

---

## 3.45

### New — Gear Sets

Save and swap gear sets, like ItemRack (`/wmachine gear`, or the dashboard
card in the Raid group). Written from the ground up: the idea is
ItemRack's, the code is our own and built to be reliable.

- **Sets** from what you're wearing, with the slots you tick. Equip from the
  window, a macro (`/wmachine gear equip <name>`), or undo the last swap.
- **Spec swaps:** assign a set to Spec 1 or Spec 2 and tick *Equip it when I
  switch to that spec*. Switching spec puts it on. Automatic swaps can be
  turned off on the dashboard; each set's spec swap has its own tick box.
- **Mounted / battlegrounds:** a set can go on while mounted or in
  battlegrounds and arenas; your previous gear goes back on after.
- **Reliability:**
  - Exact item matching (enchant, gems, random suffix, which copy), so
    identical trinkets and re-enchanted pieces are found.
  - Each step re-reads your bags and slots and skips items the server is
    still moving; a refused equip is retried, and the off hand waits for
    the main hand.
  - Swaps in place (no free bag space needed for most sets); two-handers
    take the off hand off first; quivers and soul bags are never used.
  - In combat the weapons change at once and the rest waits for combat to
    end; casts and death are waited out; a stuck item times out.
  - The result is checked at the end and anything that didn't go on is
    named with the reason.
- **Missing items:** a chat alert after a swap names any set item you don't
  have on you (and says if it's in your bank). The character sheet shows a
  warning listing them and marks the current set's missing slots in red.
- **Quick swap:** Alt over a character sheet slot shows what in your bags
  fits it; click to equip.

---

## 3.44

### New — Ogri'la Helper

Remembers the Apexis Relic sequence in Ogri'la (`/wmachine ogri`, or the
dashboard card in the Raid group). Game facts compiled with the help of
Ogri'Lazy's research; the code is our own.

- **Opens by itself** when you start an Apexis Relic or the Apexis Monument.
- **Record** the colours as the relic lights them: click the green, yellow,
  blue and red buttons, or press G, Y, B and R while the helper is up.
- **Follow along:** the next colour is ringed and moves on each time you
  touch a beam (the Introspection debuff refreshing). A wrong beam (the
  relic's Reprisal hitting you) puts the step back.
- **Edit:** left-click a recorded colour to drop it, right-click to drop it
  and the rest, *Clear* to start again.
- **Shows** your Apexis Shards and Crystals and your longest sequence per
  relic.
- **Hotkeys** are only bound while the helper is showing, can be changed,
  and are freed in combat (optional). Bindings can't change during combat,
  so a change then waits for combat to end.
- **Options:** open at relics (the dashboard switch), help tooltips, keys on
  the buttons, helper size; drag the helper to move it.

---

## 3.43

### New — Hazard Alerts

A sound the moment you're standing in something that hurts
(`/wmachine gtfo`, or the dashboard card in the Raid group).

| Alert | Means | Default sound |
|---|---|---|
| High damage | Move now | Raid warning |
| Low damage | You're taking damage you could avoid | Ready check |
| Fail | You failed a mechanic | Alarm clock |
| Friendly fire | Your own spell is hurting your group | PvP flag captured |

- **What it knows:**
  - about 265 hazards in TBC raids and dungeons (void zones, fire, poison
    clouds, cleaves, and the like), and some Classic ones
  - lava, slime and fire on the ground, drowning and fatigue
- **Only when it matters:**
  - Tanks hear the tank version, or nothing for hazards a tank is meant to
    stand in. You count as a tank in Righteous Fury, Bear Form or Defensive
    Stance, or if you're the main tank.
  - Heroics can sound different.
  - Some hazards only count from the creature that casts them, others
    only when the debuff lands, or only when it hurts.
  - Hits under 2% of your health, misses, and old content far below your
    level stay quiet. *Alert in low-level content too* turns that off.
  - Alerts are at least 0.2 seconds apart.
- **Options:** a sound per alert (any addon or game sound, or None), the
  channel, *Test* buttons, an optional on-screen warning, and switches for
  drowning, fatigue and lava.
- **Recent alerts** in the window.
- **Mute one:** `/wmachine gtfo mute <spell ID>` (and `unmute`).
- **Written for Watching Machine:** new code, and the hazard list was
  compiled with the help of the GTFO addon's research. Only the facts are
  kept (spell IDs and how bad each is), in our own format.

### New — Crit Tracker

Your biggest hits, crits and heals (`/wmachine crits`, or the dashboard
card in the Logging group).

- **Per spell, ability, melee and ranged attack, and heal:**
  - the best normal hit and best crit
  - the crit rate
  - who, where and when
- **PvP kept apart** (or not counted: *Count hits on players*).
- **New best crit:**
  - a chat line ("New best crit: Fireball 4,700 (was 4,500, on Attumen)")
    with a sound
  - optional big text on screen
  - optionally, a line to your party or raid
  - The first crit of a spell doesn't count as a record. *Quiet below*
    keeps small (levelling) records quiet.
- **Spell tooltips** show your records for that spell.
- **The window:**
  - records, best crit first, by kind, creatures or players, and character
  - hover for details; right-click to share in say, party, raid or guild
  - *Reset* clears a character's records
- **Your Characters** tooltips show each character's best crit.
- Written for Watching Machine, inspired by CritTrackerTBC.

### Also

- Two more alert sounds for every sound dropdown: *Coins* and *Level up*.

---

## 3.42

### New — gear, bags, bank, lockouts and item search in Your Characters

- **GearScore column:** each character's score from what they had on last
  time you played them.
- **Click a character** for a paper doll flyout beside the window:
  - their gear, slot by slot, with the GearScore and average item level
  - hover a slot for the item's tooltip; shift-click to link it
- **Four buttons on each row** open the same flyout (or the tabs along its
  top):
  - **Bags:** everything in their bags and keyring, with stack counts.
  - **Bank:** what's in their bank and bank bags, as of their last visit.
    Open the bank once on each character to fill it in.
  - **Attunements:** that character's progress on every attunement, and a
    button to open the Attunements window.
  - **Lockouts:** their raid saves (raid, size, bosses killed, when it
    resets), read when you log in on them, and the account's
    instances-per-hour from the Instance Tracker.
- **Find an item:** a search box at the top looks through every character's
  gear, bags, keyring and bank.
  - Each result shows the total held.
  - Hover it for who has how many, and where (worn, bags, keyring, bank).
  - Shift-click links it. Escape goes back to the list.
- **Saved:** gear, bags and keyring as you play; the bank when you open
  and close it; lockouts when the game sends them.

---

## 3.41

### New — Attunements

Where each of your characters is on every attunement (`/wmachine attune`,
or the dashboard card in the Raid group).

| Group | Attunements |
|---|---|
| Raids | Karazhan, Nightbane, Serpentshrine Cavern, The Eye, Mount Hyjal, Black Temple |
| Dungeon keys | Shattered Halls, Shadow Labyrinth, The Arcatraz, The Black Morass |
| Heroic keys | Thrallmar / Honor Hold, Cenarion Expedition, Lower City, Sha'tar, Keepers of Time |
| Other | Ogri'la, Ally of the Netherwing |
| Classic (*Classic too*) | Molten Core, Onyxia, Blackwing Lair, Naxxramas, Aqual Quintessence, the Scepter, BRD and Scholomance keys |

- **Progress is read from the game:**
  - finished quests, quests in your log
  - items in your bags and bank
  - your level and reputation
  - attunements a chain needs (Karazhan needs the Shadow Labyrinth,
    Arcatraz and Black Morass keys)
  - Steps the game can't report, like a kill or a conversation, count as
    done once anything after them is.
- **Each step:**
  - **green** done, **yellow** what to do next, **grey** later, with its
    zone
  - hover for the quest's level and group size, the creature, the item, or
    your reputation so far
  - the heading says "12 / 26 steps (46%)", with a short summary
- **Patch-aware:** the heroic keys follow the client's patch (Revered on
  2.5.6; Honored and the new keys from 2.5.7).
- **Your characters:**
  - *My characters* shows every alt's progress for the selected attunement.
  - Your Characters tooltips now say *Attuned:* and *In progress:* for raids.
- **Guild:** *Survey guild* asks guild members running Watching Machine for
  their progress, and the *Guild* view lists them.
  - It uses its own addon message.
  - Each member answers at most every 30 seconds, a moment apart.
- **"Attuned: Karazhan!"** in chat when you finish one (*Say when done*).
- **Written for Watching Machine:** the code is new. The attunement chains
  were compiled with the help of the Attune addon's research. Only the
  facts are kept (which quests, items, creatures, levels and reputation),
  in our own format.

---

## 3.40

### New — search in the Loot Browser

A *Search:* box under the expansion and category picker.

- **What it searches:** item names on every page this client has: dungeon
  and raid drops, faction and PvP rewards, set pieces, and crafted items
  (or the recipe's name, for enchants). Instance and boss names too.
- **When:** as you type, from three letters (Enter searches from two).
  Escape or *Clear* takes you back.
- **Results:**
  - up to 300 items, best quality first
  - split into *Drops*, *Reputation*, *PvP* and *Crafted*
  - each with where it's from ("Attumen the Huntsman (Karazhan)")
  - Alt-click and right-click work as everywhere else
- **Places:** matching instances and bosses are listed under the results;
  click one to open that page.
- **Names the game doesn't have yet:** item names only exist for items the
  client has seen. The first search asks for the rest, 25 at a time, five
  times a second. The status shows how many are left, and results fill in
  as they arrive.

---

## 3.39

### New — favourites and best-in-slot lists in the Loot Browser

A new **My Lists** page in the Loot Browser (*Show: My Lists*).

- **Favourite lists:** start with *Favourites*. Make more (Karazhan gear,
  alts, crafting mats...) from the bar above the page: type a name, then
  *New list*, *Rename* or *Delete* (click twice).
- **BiS lists:** one per spec of your class (*BiS: Arcane*, *BiS: Fire*,
  *BiS: Frost*). These are your own marks, not a ready-made list.
- **Adding:**
  - **Alt-click** an item anywhere in the browser (set pieces and recipes
    too) to add it to your list, or take it out. It goes to the list you
    last opened under My Lists.
  - **Right-click** for a menu that ticks it in or out of any list, and
    marks it BiS for any of your specs.
- **Badges:** a star on items in a list, an orange "BiS" on items marked BiS
  for your class.
- **The pages:** *All items* plus one section per slot (Head, Neck, ...).
  Each item says whether you have it (**Equipped**, or **Have** in your bags
  or bank) and where it's from. The heading counts "16 items, 5 you have".
- **Tooltips:** item tooltips now start with "Your BiS: Fire" and "In your
  lists: Favourites" before where it's from.
- **Shared across characters:** lists and BiS marks are account-wide. Which
  list Alt-click fills is per character.

---

## 3.38

### New — GearScore in ArmorySnap

Every member of every ArmorySnap snapshot now has a GearScore, worked out
from the gear saved in the snapshot with the GearScore module's formula
(same numbers as the tooltips).

- **Member list:** "GS 1650" in the score's colour (where the talent points
  or item count were; talents are still on the paper doll).
- **Paper doll:** "GearScore 1650  iLvl 112" ahead of the enchant / gem
  summary.
- **Raid average:** next to *Raid Members*, for the snapshot shown.
- **Old snapshots too:** members captured before 3.38 are scored when you
  open the snapshot. Items the client hasn't loaded yet show "..." /
  "(loading)" and fill in as they arrive.
- **Saved:** once every item is known, the score and average item level
  are saved on the member, so they're instant next time.

---

## 3.37

### New — GearScore

A gear score and average item level for you and every player you mouse over
(`/wmachine gs`, `/gs`, or the dashboard card in the Raid group).

- **The numbers:** the same as GearScoreTBCClassic's. It uses the
  GearScoreLite formula tuned for TBC:
  - each item's level, quality and slot weight (a two-hander counts double,
    trinkets and rings about half)
  - **enchants +5%**, **gems +5** each
  - hunters' ranged weapons count more and their melee weapons less
  - colours by tier, grey through orange
- **Player tooltips:** "GearScore: 1650  iLvl: 112".
  - **Auto-inspect:** players you mouse over are inspected one at a time,
    out of combat and within inspect range (about 28 yards), never while
    your own inspect window is open.
  - **Late tooltips:** the line appears as soon as the inspect comes back,
    even with the tooltip already open.
  - **Kept:** scores are saved by name for a week.
- **Item tooltips:** the item's score. *Item tooltip details* (off by
  default) adds:
  - its base score, enchant and gem bonuses, or a missing enchant or empty
    sockets
  - what equipping it would change: against your weaker ring or trinket,
    and both hands for a two-hander
- **Character and inspect frames:** "GearScore: 1650  iLvl: 112".
  `/wmachine gs unlock` to move it, `lock` to save, `reset` to put it back.
- **Group list:** your party or raid, highest score first, with when each
  was last inspected.
  - *Scan group* inspects whoever's missing.
  - *Send to group* posts the scores.
  - `/wmachine gs report` prints them.
- **Another GearScore addon?** With GearScoreTBCClassic, GearScoreLite or
  TacoTip loaded, Watching Machine leaves the tooltips and character frame
  to it (no double lines). The group list still works.
- **Credit:** formula and colour brackets from GearScoreTBCClassic (gk646,
  MIT licence, notice in `Modules/GearScore.lua`).

---

## 3.36

### New — crafting, factions and PvP in the Loot Browser

A *Show:* switch at the top: **Dungeons & Raids**, **Crafting**,
**Factions**, **PvP**, for Classic and The Burning Crusade. A Wrath client
also gets Wrath's crafting (with Inscription), factions and PvP.

| Page | What's in it |
|---|---|
| Crafting | Every profession by section (Flasks, Transmutes, Armor - Head...), with Plate / Mail / Leather lists where a section has them. Each recipe shows what it makes and the skill needed; hover for the reagents and the recipe item that teaches it |
| Factions | What each faction sells at Friendly, Honored, Revered and Exalted. Your side's factions only (Thrallmar or Honor Hold); faction-only rewards (the Wintersaber mount) show only to that faction |
| PvP | Battleground rewards, Honor and Arena Season 1–4 sets and weapons, world PvP vendors (Halaa, Hellfire, Terokkar, Zangarmarsh), mounts and insignia |

- **Lists:** the *Loot:* buttons now show whatever lists a page has: Normal /
  Heroic, Plate / Mail / Leather, Major / Minor Glyphs.
- **Tooltips:** item tooltips now also say *Reputation reward* (faction,
  standing), *PvP reward* (season or vendor) and *Made by* (profession,
  skill).

### Changed — shorter set pages

- **One line per set:** each set is now a single line, its name then an
  icon per piece. Hover a piece for its tooltip; shift-click to link it.
- **By class:** with *Sets: my class only* off, the sets are grouped under
  each class's name, in class colour. Tier 4 for every class is now 26
  lines instead of over 100.

---

## 3.35

### New — "Drops from" on item tooltips

Every item tooltip (bags, chat links, the auction house, the Loot Browser)
now says which bosses drop it, from the Loot Browser's data:

```
Drops from:
   Attumen the Huntsman (Karazhan)
```

- **Heroic:** "(Hellfire Ramparts, Heroic)" when only the heroic version
  drops it; an item from both shows the boss once.
- **Many bosses:** up to three, then "and N more" (Badge of Justice).
- **Your faction:** both versions of faction items are known.
- **Switch:** *Item tooltips* at the top of the Loot Browser (on by default).
- Works with both ways the client builds item tooltips
  (`TooltipDataProcessor` and `OnTooltipSetItem`), adding the lines once.
- The drop index is built the first time an item tooltip shows.

---

## 3.34

### New — Loot Browser

What every dungeon and raid boss drops (`/wmachine loot`, or the new
dashboard card in the Raid group).

- **Content:** every Classic and Burning Crusade dungeon and raid, boss by
  boss. Also trash, quest and event pages, keys, and Tier 1–6 sets.
- **The window:** instances on the left (dungeons, then raids in orange,
  with the TBC phase), bosses in the middle, loot on the right.
  - **Normal / Heroic** switch when a boss has both.
  - **Your faction's** version of items that differ.
  - *Sets: my class only* (on by default) on the tier set pages.
  - **Resizable**; two columns of loot when it's wide.
- **Items:** icon, name in its quality colour, slot and armour type.
  - **Hover** for the full tooltip.
  - **Shift-click** links it, **Ctrl-click** tries it on.
- **Opens on the instance you're in**, and remembers your last instance per
  expansion.
- **Wrath of the Lich King:** the browser checks the client's expansion.
  - Wrath holiday bosses (Ahune, Headless Horseman, Coren Direbrew,
    Apothecary Hummel) already show on a Wrath client.
  - The Wrath dungeon and raid tables slot into `Data/LootWrath.lua` when
    they're added. Until then Wrath stays out of the list.
- **Light:** only item IDs are stored (about 80 KB of data), built the
  first time the window opens. Names, icons and stats come from the game.

---

## 3.33

### New — World Timers on the world map

Pins with live timers on the map they belong to (World Timers options:
*Show the timers on the world map*, on by default).

| Map | Pins |
|---|---|
| The Faire's zone and continent | Darkmoon Faire: "opens in" or "ends in" |
| Terokkar Forest, Shattrath | Terokkar towers: your layer's reset (or the soonest) |
| Shattrath | Today's dungeon and heroic dailies |
| Felwood | All ten Songflowers: time until each is back, or "ready?" |

- **Hover a pin** for details: every layer's tower reset and who holds the
  towers, when a Songflower was picked and on which layer.
- **Ticks** once a second while the map is open; pins keep their size when
  you zoom.
- **Safe:** pins are drawn on the map's canvas and only post-hook it
  (`OnMapChanged`, `OnCanvasScaleChanged`, `OnShow`). Nothing of Blizzard's
  is replaced. It also works when the map loads after Watching Machine.

### New — guild layer list

Nova World Buffs users tell their guild which layer they're on. World
Timers now lists them under the timers ("Layer 1: Anna, Bob"), in Nova's
numbering, for 30 minutes after each last said. Only guild messages count.

### New — NPC walking alert (Horde)

After the Onyxia or Nefarian head is handed in, Runthak or Saurfang walks
to the gate and the buff drops when they get there. Stand by the throne
with their window open: when they walk off, it closes by itself, and you
get "Onyxia buff NPC has started walking!" and a sound.

- **What doesn't count** (checked half a second after the close, as Nova
  World Buffs does):
  - closing it yourself: the X, Goodbye, Escape, or a trade window opening
  - moving, or having stopped in the last second
  - targeting the NPC while they stand still
  - being away from the throne
- **Repeats:** once a minute per buff.
- **Options:** *Say when the Onyxia / Nefarian NPC starts walking (Horde)*
  (on), and *Walking alert sound* (raid warning by default; any addon or game
  sound, or None).
- **Guild members' Nova walking notices** show too ("... started walking
  (seen by Anna)"), with the same sound. Like Nova, only from the guild.

---

## 3.32

### New — a sound for every warning

The Class Tools window has a new **Warning sounds** section (collapsible,
below the warning frame options). It has a dropdown for each warning of the
General tab and your class:

| Tab | Warnings |
|---|---|
| General | No flask or elixirs, No food buff, No weapon oil / stone |
| Mage | Mage armor missing |
| Warlock | Fel / Demon Armor missing, Demonic Sacrifice missing, Soul Link not cast |
| Paladin | Righteous Fury missing |

- **The choices:**
  - *Shared warning sound*, the default: the warning frame's "Play a sound
    when a new warning appears", if it's on.
  - Any addon or game sound.
  - **None** for silent.
- **Picking a sound plays it.**
- **Channel:** sounds use the *Warning sounds play on* channel from the
  General tab.
- **When:** each plays once when its warning appears, at most every few
  seconds.
- The mana potion and rune sounds stay where they were, in the General tab.

### New — SYNC NOW sound

*SYNC NOW sound* (Class Tools > General, off by default) plays a sound when
the Enhancement weapon sync prompt comes up, once per prompt. That way you
can press the sync macro without watching the bar.

### Changed — None is silent

For the mana potion and rune warnings, **None** used to fall back to the
shared warning sound. It's now silent everywhere. Choosing *Shared warning
sound* in the new section gives the old behaviour.

---

## 3.31

### Changed — raid SR check runs on every robot pull

The raid-wide shadow resist check ran once, 45 seconds after Mother died.
It now runs each time you pull a trigger mob after her (the Promenade
Sentinel robots, Shadowmoon Reavers and the Illidari packs), once per
pull, for the raid leader and assistants. Mother's death only arms it.
Each scan takes a few seconds per raider who isn't running the addon, so
it finishes well inside a robot pull.

### Fixed — mana potion cooldowns not seen on 2.5.6

TBC Anniversary 2.5.5 removed the global item functions. Blizzard's
deprecation fallback sets `GetItemCooldown` to `C_Item.GetItemCooldown`,
which 2.5.6 doesn't have, so it was nil: a potion on cooldown counted as
ready, the potion warning stayed up and the rune warning never showed.

- New `WM.ItemCount`, `WM.ItemCooldown`, `WM.ItemUsable`, `WM.ItemName` and
  `WM.ItemIcon` in `Core.lua` use `C_Item` / `C_Container` first and the old
  globals only where those are missing.
- The mana potion and rune warnings, Your Characters' reagent counts and
  the warlock soul shard count use them.

### New — a missed mana potion warning says why

When you're down by the potion threshold in combat but no potion warning
can show, chat says why, once per reason per session:

- no mana potion in your bags
- your potion is on cooldown (a pre-pull potion shares it)
- the potion you carry can't be used here
- "Only in 25-man raids" is on and the instance reports another size

### Checked — 2.5.6 build 70006

Build 70006 (October 12) changed nothing in Blizzard's UI code beyond the
version number; the build before it (69795) only touched the group finder.
Interface `20506` is still correct. Checked every global function the
addon calls against the 2.5.6 API list: besides the item functions above,
`UnitBuff`, `UnitDebuff`, `CombatLogGetCurrentEventInfo`, `SendChatMessage`
and `GetTalentInfo` also exist only as deprecation fallbacks. They work
today but Blizzard says they'll be removed.

---

## 3.30

### New — raid-wide shadow resist gear check

The SR gear check only ever looked at your own gear, so a raid leader had
no way to see who was still in SR gear after Mother Shahraz. Now they can.

- **When:** 45 seconds after Mother dies, to give people time to swap.
  If you `/reload` after Mother, it runs instead the moment you engage a
  Grand Promenade pull. It runs automatically only for the raid leader and
  assistants, once per kill. `/wmachine srraid`, the **Check Raid** button
  (Debuff Tracker settings, Black Temple section) or the dashboard tools
  menu runs it any time, for anyone.
- **How:** raiders running Watching Machine 3.30 report their own gear
  total over a `WMSR` addon message (the same reading as
  `/wmachine srcheck`). Everyone who doesn't answer within 3 seconds is
  inspected, one every 1.5 seconds. Inspecting needs them within about
  28 yards. It waits for Armory Snap's inspects and leaves an open inspect
  window alone.
- **Result:** "Still in SR gear (N): Name (SR), ...", highest first, against
  the same threshold as the personal check, plus who couldn't be checked
  (out of range, offline, no inspect reply). It shows on screen, and can
  go to Say / Party / Raid / `/rw` (new **To:** setting, default Me only).
- New settings: **Check the whole raid after Mother** (on) and its channel.

---

## 3.29.1

### Fixed — shadow resist gear not detected after Mother Shahraz

The check read gear shadow resistance from `GetItemStats`, which gives only
an item's own stats: socketed gems and enchants never showed, and "Resist
All" wasn't counted. A set gemmed with Void Spheres could stay under the
threshold and never warn.

- Each equipped item's tooltip is now read as well (`C_TooltipInfo` where
  the client has it, otherwise a hidden scanning tooltip). It counts "+N
  Shadow Resistance", "+N Resist All", "+N All Resistances" and active
  socket and set bonuses; grey (inactive) bonuses are skipped.
- Each slot takes the larger of the item stats and the tooltip, so a client
  where one of them comes back empty still works.
- New test file `tests/test_srcheck.lua`.

---

## 3.29

### Fixed — Shattrath flasks not detected

The Shattrath flasks, which only work in Tempest Keep, Serpentshrine
Cavern, Hyjal, Black Temple and Sunwell, put up an aura without "Flask of"
in its name (Shattrath Flask of Blinding Light gives "Blinding Light"), so
the flask checks missed them.

- They now count as a flask by aura name and by spell ID: Relentless
  Assault, Fortification, Mighty Restoration, Supreme Power, Pure Death and
  Blinding Light.
- Covers the raid Buff Check (Flask or Elixirs, and the battle and guardian
  elixir checks) and the Class Tools General flask warning.
- `/wmachine whybuff` labels them "Shattrath flask".

---

## 3.28

### New — World Timers

Open-world timers for TBC Anniversary, per layer (dashboard **Raid** group,
`/wmachine timers`). It follows how Nova World Buffs works on the TBC
client, worked out from its code (`docs/NOVA-PROTOCOL.md`, part 3); none of
its code is used.

- **Layers:**
  - **Finding yours:** target or mouse over A'dal, Nutral, Minalei or
    Innkeeper Haelthol in Shattrath and the window shows "Layer N of M",
    numbered as Nova World Buffs numbers them.
  - **Other zones:** Outland zones and the two capitals are then tied to your
    layer as you target things there. This stops once you join a group,
    since joining can move you, and resets when a zone shows a second
    instance.
  - **Old layers:** a layer nobody has seen for 2 hours is dropped, unless a
    timer is still running on it.
- **Terokkar Forest towers:**
  - **The timer:** when the Spirit Towers reset, read from the zone's timer
    (whose clock runs slow, so it's corrected), per layer, with the
    controlling faction.
  - **Warning:** a line 10 minutes before (option).
  - **Captures:** cleared while the towers are being captured.
- **Dailies:**
  - **Which ones:** today's dungeon daily (Nether-Stalker Mah'duun), heroic
    daily (Wind Trader Zhareem) and PvP daily (Call to Arms).
  - **How they're found:** from accepting the quest from the NPC (not a
    shared quest), or from Nova World Buffs users.
  - **Validity:** each counts for 24 hours.
- **Darkmoon Faire:**
  - **When:** whether it's up, when it opens or closes, and where it goes
    next. It opens the Monday after the first Friday of the month at the
    region's reset hour, for 7 days.
  - **Where:** January, April, July and October in Terokkar Forest; March,
    June, September and December in Elwynn Forest; the other months in
    Mulgore.
  - **Your Sayge cooldown:** a fresh fortune buff starts a 4-hour (played
    time) cooldown per character, with a line when it resets.
- **Classic world buffs:** Rend, Onyxia and Nefarian timers.
  - **How a timer is set:** from the NPC's yell and the buff landing on you
    within 30 seconds, tied to the layer.
  - **Warnings:** at 30, 15, 10, 5 and 1 minutes, and when a new one can be
    dropped (option).
  - **Also:** "about to drop" and buff-NPC-killed notices. These are rare on
    TBC.
- **Songflowers:**
  - **Picks:** a pick at one of Felwood's ten flowers starts that flower's
    25-minute timer. Your own picks count, and so do picks by a player you'd
    already seen nearby, so players logging in with the buff aren't counted.
- **Nova World Buffs users:**
  - **What's read:** their shared data (guild, group and the yells their
    addon sends to nearby players): layers, zone mappings, tower timers,
    dailies, world buffs and Songflowers.
  - **Checks:** Nova's own receive rules. Layers must have been seen in the
    last 2 hours, buff timers need a matching yell, tower timers must be in
    range, and senders must be level 6 or higher on version 3.26 or later.
  - **Notices:** their "about to drop" and NPC-killed notices are shown
    (option).
  - **Listen only:** nothing is ever sent in Nova's format. The decoder
    gained a full reader for Nova's packed data and the codec for yelled
    messages, tested against messages made by the real libraries.
- **Commands:** `/wmachine wb` prints the short timers, and `/wmachine wb
  guild` (or party / raid) sends them to that channel. The dashboard card's
  tools menu prints them too.
- **Saved data:** new SavedVariable `WorldTimersDB` (per realm and faction,
  plus each character's Sayge cooldown).

**Still to confirm in game:**
- the Darkmoon Faire hours on OCE realms (Nova uses US times there)
- whether the Classic world buffs still drop on Anniversary realms
- whether `QUEST_ACCEPTED` passes one argument or two on 2.5.6 (both are
  handled)

---

## 3.27

### New — Your Characters

A window listing every character you log in, on every realm (dashboard
**Logging** group, `/wmachine alts`, or the **Your Characters** button in the
Instance Tracker window).

- **Grouped by realm,** with each realm's total gold (hover the realm row) and
  the gold across all characters in the footer.
- **Each row:** name (class colour), level, rested XP as a % of a level,
  gold, and when you last played it.
- **Rested XP while offline:** it's estimated from the last saved value: 5%
  of a level per 8 hours resting (a quarter of that elsewhere), up to 1.5
  levels.
- **Hover a character** for its details:
  - XP through the level, and rested XP
  - gold, and free bag slots (ordinary bags only: quivers, soul and herb
    bags are left out)
  - armor durability, average and lowest piece
  - professions with skill
  - the reagents your class carries: Sacred / Holy Candles, Arcane Powder
    and the teleport / portal runes, Druid seeds and Quillvine, Symbols,
    Ankhs, Soul Shards / Infernal Stones / Demonic Figurines, Flash /
    Blinding Powder
  - for hunters, ammo and the pet (name, level, family, happiness)
- **When it saves:** as you play (bag, money, XP and durability changes,
  grouped) and when you log out.
- **Right-click** removes a character you've deleted. It comes back if you
  log in on it again.
- **Saved data:** new SavedVariable `AltTrackerDB`.

### New — Battlegrounds & Arenas

A log of every battleground and arena match, on every character (dashboard
**Logging** group, `/wmachine bgs`).

- **The result:** win, loss, draw, or left early. It's read when the game
  declares a winner.
- **Your scoreboard line:** killing blows, honorable kills, deaths, honor,
  damage and healing.
- **Arenas also record:**
  - the bracket (2v2 / 3v3 / 5v5, rated or skirmish)
  - your partners and opponents, with classes
  - both team names
  - your new rating and its change
- **Totals:** played, won and win rate per battleground and per arena
  bracket, for all characters or just the one you're on.
- **A result line in chat** after each match, for example "Warsong Gulch: Win
  (24m 10s) — 4 KB, 31 HK, 2 deaths, +412 honor". Click it to open the log,
  or turn it off.
- **In the log:** hover a match for everything; right-click to delete one.
- **Saved data:** new SavedVariable `PvPLogDB`.

---

## 3.26.1

- **New Potion sound:** `Media/Sounds/potion.ogg` is replaced with a new
  recording, the default for the mana potion warning. The file name is
  unchanged, so your sound choices carry over. Restart the game, not just
  `/reload`, to hear the new file.

---

## 3.26

### New — Alert sounds (mana potion and rune warnings)

- **Their own sounds:** the mana potion and rune warnings in Class Tools >
  General each play a sound once when they appear. By default these are the
  two new addon sounds, **Potion** and **Rune** (`Media/Sounds/potion.ogg`,
  `rune.ogg`).
- **Choose a sound:** *Potion warning sound* and *Rune warning sound* are
  dropdowns offering:
  - the two addon sounds
  - the game's raid warning, ready check, alarm clock and PvP flag sounds
  - **None**

  Picking a sound plays it, so the dropdown doubles as a test button.
- **Channel:** *Warning sounds play on* chooses Master (the default, heard
  even with game sound effects turned down), Sound effects or Dialog.
- **Repeats:** a sound plays once per appearance, at most once every few
  seconds, and never while the warning simply stays up.
- **The shared sound:** a warning with its own sound plays that instead of
  the warning frame's shared "sound on a new warning". With *None* it falls
  back to the shared sound, if that's on.
- **For other alerts:** `Sounds.lua` (`WM.Sounds`) holds the sound list and
  plays a choice, and `CT:SetAlert(key, text, icon, sound, channel)` takes
  one. Other alerts can use it later.
- **Note:** WoW only finds new sound files after a full restart of the game,
  not a `/reload`.

---

## 3.25

### New — Gold trade alerts (Mail & Trade Logger)

Trades stay in the existing Mail & Trade log; this adds to it.

- **Chat line** whenever gold changes hands in a trade, with who, what each
  side gave, and where. For example: "Trade with Booster: received 500g,
  gave 2 item(s) (in The Deadmines)." Click it to open the trade log.
  - It shows even with the general chat notifications off.
  - It has its own option, *Chat line when gold is traded* (on).
  - Trades of items only still get a line when notifications are on.
- **Trades record the instance** you were in. The Trades tab shows it ("in The
  Deadmines"), and older trades just show no instance.
- **With the Instance Tracker:** each trade is tied to the run you were in,
  and the run's tooltip in the instance log shows **gold traded**, received
  and given, with the number of trades.
- **Fixed:** completed trades were only detected on English clients (the
  "Trade complete" text was hard-coded). They now use the client's own text.
- **Fixed:** the old chat line only mentioned gold received; it now shows both
  directions.

---

## 3.24

### Instance Tracker: clickable chat lines and the X

- **Entering an instance** now prints a line with your counts: "Entered The
  Deadmines (3/5 this hour, 7/30 today)."
  - **The red X** at its end deletes that run, after asking. Use it when an
    instance shouldn't count, for example one the tracker logged by mistake.
  - Turn the line off with *Say when I enter an instance*.
- **Every line the tracker prints opens the log** when clicked: entering,
  leaving (run stats), the same-instance merge, lockouts, "you can enter a
  new instance now", and Nova reset notices.
- **Shared chat links:** links are built by a small helper in Core
  (`WM:RegisterChatLink`, `WM:ChatLink`) that any module can use.
  - **On the 2.5.6 client** it claims its own link type with Blizzard's
    `LinkUtil.RegisterLinkHandler`, so clicking never opens the item
    tooltip.
  - **On older clients** it hooks `SetItemRef` and tells the item tooltip to
    ignore its links.
- **Run IDs:** every run now has an ID (older runs get one on login), which
  the X uses.

---

## 3.23

### New — Reset notices from Nova Instance Tracker users

When your group leader runs **Nova Instance Tracker** and resets instances,
their addon tells the group in a hidden addon message. Watching Machine now
reads it.

- **Leader resets with Nova's chat announcement off:** you see "The
  Deadmines has been reset by the group leader (Name, Nova Instance
  Tracker)."
- **Leader resets with it on:** Nova has already posted to party chat, so
  nothing is repeated.
- **Either way,** that instance is marked as reset in your log, so going back
  in starts a new run.
- **Nova World Buffs** sends a similar notice, but only when a reset *fails*
  (players still inside). That's a bug in Nova World Buffs, worked out from
  its code. It's shown as "tried to reset ..., but players are still
  inside".
- **Trust:** only the leader of your own group is believed (Nova itself
  doesn't check), and only group channels are read.
- **Listen only:** Watching Machine never sends in Nova's format.
- **Option:** *Show resets from leaders using Nova Instance Tracker* in the
  Instance Tracker window (on by default).
- **How it's read:** Nova's messages are packed and compressed, so
  `Modules/NovaCompat.lua` unpacks them with its own decoder (message
  reassembly, decompression and unpacking), written from the format
  described in `docs/NOVA-PROTOCOL.md`. No Nova or library code is
  included. The tests decode messages compressed by zlib in the same format
  Nova produces.

---

## 3.22

### New — Instance Tracker

A new module (dashboard **Logging** group, `/wmachine instances`) that logs
every dungeon and raid on every character and keeps the instance limits.

**Lockouts:**
- **The limits:** instances entered this hour (limit 5) and in the last 24
  hours (limit 30), across all your characters, with when the next one frees
  up.
- **Which lockout:** whether you're on an **hourly** or a **daily** lockout,
  and for how long.
- **Timed from leaving:** a run counts from when you leave it, or from when
  you entered while you're still inside.
- **Where it shows:** in the window, on the dashboard card and in the minimap
  tooltip. `/wmachine lockouts` prints them, and so does the game's "too many
  instances" message. When a full limit frees up, it tells you.

**The same instance is counted once:**
- **How it's recognised:** the server gives every instance its own number,
  carried in the GUID of every creature inside.
- **Merging:** going back into the same number adds to the earlier run
  instead of logging and counting a new one. That covers a corpse run,
  another Scarlet Monastery wing on the same ID, a disconnect, or logging
  out inside.
- **Resets:** after one, the next visit is a new run.

**Each run keeps:**
- the group: name, level and class
- time in and out, and time inside
- mobs killed by you and your group
- XP, and XP per mob
- gold looted
- your level going in and coming out
- every reputation gain

Hover a run in the log for all of it, and right-click to delete one.

**Leaving an instance** prints the run's stats to your chat window (the
default), to your group, or not at all.

**Resets:** as group leader, resetting posts "[WM] <instance> has been
reset." in party or raid chat.

**Options:** merge the same instance, reset announcements, the "you can
enter again" message, and where run stats go.

**Saved data:** new SavedVariable `InstanceTrackerDB` (one log for all
characters).

**Still to come:**
- reset notices to and from Nova Instance Tracker users
  (docs/NOVA-PROTOCOL.md)
- clickable chat lines
- gold trade alerts (TODO 10)
- the alts window (TODO 11)

---

## 3.21

### Dashboard: sized to fit, and resizable

- **Opens showing every card:** the dashboard used to be a fixed 420 × 700
  window with one column, so the 14 cards needed scrolling on most screens.
  Its first size is now worked out from your screen. If one column would be
  taller than the screen, it uses two columns (up to four), wide enough for
  every card to show.
- **Resizable:** drag the size grip in the bottom-right corner, between 380
  and 1300 wide and up to your screen's height. The cards reflow as you drag
  into as many columns as fit, at least 340 wide each, and their text
  narrows or widens with them. The size is remembered.
- **Fit:** a button at the top left puts back the size that shows every
  card.
- Anything that still doesn't fit (a short window, or a very small screen)
  scrolls as before.

---

## 3.20.1

### Fixed — game menu button with ElvUI

- **Overlap:** the Watching Machine button sat on top of ElvUI's.
  - **Cause:** ElvUI's button isn't part of the menu's layout. After each
    layout, ElvUI anchors it under Macros and pushes Log Out, Exit Game and
    Return to Game down. Ours was laid out into that same slot.
  - **Fix:** ours now works the same way. After each layout it goes under
    Macros, or under ElvUI's button (or another addon's menu button) if one
    is there, and pushes the buttons below down by its own height. The two
    shifts add up, so both buttons fit whichever addon runs first.
- **Look:** with ElvUI loaded, the button now takes ElvUI's button skin, the
  same one ElvUI gives the menu's own buttons. If ElvUI's Blizzard skins
  (or its *Misc* skins) are turned off, it keeps the default look like the
  rest of the menu.

---

## 3.20

### Swing timer: resizable

- **Grip:** while the swing timer is unlocked, a size grip sits in its
  bottom-right corner. Drag right for wider bars, down for taller ones.
  `/wmachine swing` shows the timer for 10 seconds, and it stays up while
  you're resizing.
- **Options** in Class Tools > General: *Swing timer width* (140–420 in the
  list) and *Swing timer bar height* (10–28). The grip allows 100–600 wide
  and 8–40 tall.
- Everything scales with the size: the spark, the sync mark, the latency
  and hunter zones. The labels hide when the bars are too thin for them.
- **Lock the swing timer** now also stops resizing and hides the grip.
- `/wmachine swing reset` puts the timer back in the centre at its default
  size (220 × 14).
- Saved in `SwingTimerDB` (`width`, `barHeight`).

---

## 3.19

### New — Game menu button

A **Watching Machine** button in the menu that Escape opens, the way ElvUI
adds its own. It sits at the end of the AddOns / Macros group, just above
**Log Out**, and opens the dashboard.

- **Turning it off:** Settings > *Watching Machine button in the game menu
  (Esc)*. It takes effect the next time the menu opens.
- **How it's added:** the 2.5.6 client rebuilds its game menu each time it
  opens. The addon adds its own button to the menu's layout after every
  rebuild, without taking a button from Blizzard's pool or changing
  Blizzard's buttons. Changing them could get *Log Out* and *Exit Game*
  blocked as "an AddOn". Older menus with fixed buttons are handled too.

---

## 3.18

### New — Righteous Fury check (Class Tools > Paladin)

*Warn if Righteous Fury is missing* (on by default) puts **Righteous Fury
is missing** in the CHECK YOURSELF frame, the same way the mage and warlock
armor checks work.

- **Protection paladins only:** most talent points in Protection, or Holy
  Shield / Avenger's Shield learned. Holy and Retribution paladins are
  never warned.
- **No warning** before you've learned Righteous Fury, or while you're
  dead.
- **Spec changes** are picked up at once: the spec is cached for a few
  seconds and dropped on a respec.
- Paladins now have their own tab in Class Tools.

---

## 3.17

### New — Swing timer (Class Tools > General)

A movable bar per hand showing the time to your next melee swing, or to your
next Auto Shot for hunters. A white spark moves left to right as the swing
comes round.

**Who gets it:** warriors and rogues; paladins with most points in
Retribution (or Crusader Strike); shamans with most points in Enhancement
(or Stormstrike / Dual Wield); hunters (Auto Shot). *Swing timer for every
class and spec* shows it for anyone. It appears while you're attacking or
shooting, and goes once you stop and leave combat.

**How it keeps time (TBC rules):**

| What happens | Effect |
|---|---|
| A swing lands or misses (dodge, parry, block, miss) | Restarts that hand |
| Heroic Strike, Cleave, Maul, Raptor Strike | Replace the swing: restart the main hand |
| A cast-time spell finishes (Slam, Lightning Bolt, a heal) | Restarts both hands. Interrupted casts and instants (Stormstrike, shocks) don't |
| Haste changes (Flurry, Bloodlust, drums) | The time left is rescaled |
| You parry an attack | Main hand: time left drops by 40% of your swing, but never below 20% |
| Weapon swap | Restarts every hand |
| You start attacking | An off hand past halfway goes back to halfway |
| Windfury extra attack | Not counted as a new swing |

**Latency:** the bars aren't shifted (every swing is reported equally late);
instead the last part of each bar, as long as your world latency, is drawn
in red and the fill turns red inside it. Anything that tells you *when to
press* (the sync mark, the hunter clip zone) is moved earlier by your
latency.

**Hunters:** the Auto Shot bar is split into three parts:
- **green** while a Steady Shot is safe to start;
- **red** where starting one would delay (clip) the next shot: from a
  Steady Shot's cast time plus latency before the wind-up;
- **yellow** for the final 0.5s wind-up, when moving delays the shot.

Auto Shot restarts the bar, Aimed Shot resets it, Steady Shot doesn't.

**Enhancement weapon sync:** with two weapons of the same speed, you want
the off hand to land just after the main hand. Windfury Weapon has a 3
second cooldown shared by both hands, so the main hand should be the hand
that gets the proc, and two hits close together share one Flurry charge.
The usual sync macro is:

```
/cleartarget
/targetlasttarget
/startattack
```

It stops and restarts your attack. That can only *delay* the off hand: if it
was past halfway, it lands half a swing after the press. So pressing when
the main hand has *off-hand speed ÷ 2 − lag* left lands the off hand *lag*
seconds after the main hand.

- **The mark:** a blue line on the main-hand bar at that point, moved earlier
  by your latency. It's faint while you're in sync.
- **SYNC NOW:** shown, and the mark turns green, when you're out of sync, the
  mark is reached and the off hand is past halfway (otherwise pressing
  wouldn't move it).
- **Readout** under the bars: *In sync* (off hand 0–0.4s after the main
  hand), *Off hand first*, or *Out of sync*, with the gap. It notes when your
  weapon speeds differ, since sync then drifts every swing.
- **Off hand lands after by:** 0.10, 0.15 (default), 0.20 or 0.30s.

**Options:** *Swing timer* (on by default), *Swing timer for every class and
spec*, *Shaman weapon sync mark*, *Off hand lands after by*, *Lock the swing
timer*. `/wmachine swing` (or the Class Tools card's tools menu) shows it for
10 seconds to drag it into place.

**Saved data:** new SavedVariable `SwingTimerDB`.

**Still to confirm in game:** how the client logs Windfury Weapon's extra
attack, and whether the Auto Shot wind-up shortens with haste (the timer
uses a fixed 0.5s).

---

## 3.16.1

### Fixed — dropdowns covering option text in Class Tools

- **The bug:** every dropdown option in Class Tools (the mage *Portals /
  Teleports / Mana gems / Armors / Food & water expand*, the warlock and
  shaman directions, and the General flyout and mana options) drew over the
  first line of its own description. The dropdown is taller than a
  checkbox, but its description started at the same height as a
  checkbox's.
- **The fix:** dropdown rows now put the description below the dropdown
  and are sized to fit it. Labels sit in a fixed-width column, so the
  dropdowns line up and a long label can't push one into the next.
- **Checked elsewhere:** the other dropdowns (Mail & Trade, Whisper Logs,
  ArmorySnap) have room. The Totem Sets editor's two columns came within a
  few pixels of each other and of the panel edge; the panel is now wider
  and the columns spaced further apart.

---

## 3.16

### New — Shaman totem button

One button that drops a **totem set**, one totem per click, in the order
**Air, Water, Earth, then Fire**. Fire always goes last.

- **Picking a set:** hover the button to open your sets, and click one to
  use it. The button's icon and label show the set in use; its tooltip
  lists the four totems.
- **Dropping:** each click casts the next totem. A secure button can only
  cast one spell per click, so the button runs a `/castsequence` macro
  built from the set.
- **Starting again from Air:** when all your totems are gone (destroyed or
  expired; TBC has no Totemic Recall, so "no totems down" is the signal,
  read from `PLAYER_TOTEM_UPDATE`), when combat ends, or on **Ctrl-click**.
  A reset that happens in combat applies when combat ends, which is when
  the sequence resets anyway.
- **Moving:** Shift-drag, since a plain press casts. The shared flyout lock
  and docking apply.
- **Right-click** opens the set editor.

**Sets:** four, premade as:

| Set | Air | Water | Earth | Fire |
|---|---|---|---|---|
| **Melee** | Windfury (Grace of Air) | Mana Spring (Healing Stream) | Strength of Earth (Stoneskin) | Searing |
| **Caster** | Wrath of Air (Tranquil Air) | Mana Spring (Healing Stream) | Stoneskin (Strength of Earth) | Totem of Wrath (Searing) |
| **Healer** | Wrath of Air (Tranquil Air) | Healing Stream (Mana Spring) | Stoneskin (Strength of Earth) | Searing |
| **Tremor** | Windfury (Grace of Air) | Mana Spring (Healing Stream) | Tremor | Searing |

A premade element is **Auto**: it uses the first totem in its list that you
know (fallbacks in brackets). Elements with nothing known are skipped.

**Totem Sets editor:** `/wmachine totems`, right-click the button, or
*Edit totem sets* in the Class Tools card's tools menu. Rename a set, and
choose each element's totem, *Auto*, or *None*. *Restore premades* puts all
four back.

**Options** (Class Tools > Shaman): *Show the totem button* (on by
default) and *Totem sets expand* (Up by default, or Hidden).

**Saved data:** new SavedVariable `ShamanToolsDB`.

### Flyout engine

- A flyout's anchor can now be a secure button with an action of its own
  (the totem button), and flyout entries can pick something instead of
  casting a spell.

---

## 3.15

### New — Warlock button

A flyout button showing the **warlock class crest**. It opens into three
groups, nearest the button first, and each group has its own direction (or
Hidden) in Class Tools > Warlock:

| Group | Spells | Default |
|---|---|---|
| **Demons** | Summon Felguard (only if talented), Succubus, Imp, Felhunter, Voidwalker | Left |
| **Armors** | Fel Armor, Demon Armor, Demon Skin | Up |
| **Stones & rituals** | Ritual of Souls (Soulwell), Ritual of Summoning, Create Healthstone, Create Soulstone | Right |

- **Only what you know:** spells you haven't learned don't appear, so
  Felguard is hidden without the talent.
- **Highest rank:** armors cast their highest rank. Stone ranks are
  separate spell names ("Create Healthstone (Major)"), so those match by
  prefix and keep the highest.
- **Soul Shard count:** every icon whose spell uses a shard shows your
  current count: all demons except Imp, plus all four stones and rituals.
  It updates whenever your bags change, in combat too.
- **Saved data:** new SavedVariable `WarlockToolsDB` (position and
  directions). The *Show the warlock button* option is on by default.

### Flyout buttons, for every class

The flyout engine moved out of the Mage module into
`Modules/ClassFlyout.lua` (`WM.Flyout`). The mage portal button, the mage
utility button and the warlock button all use it. New shared options in
Class Tools > **General**:

- **Flyout buttons open:** *On hover* (as before) or *On click*. In click
  mode, clicking the button opens or closes the flyout, moving away doesn't
  close it, and casting a spell from it does.
- **Dock flyout buttons together:**
  - Your class's visible flyout buttons line up into one group.
  - The first button keeps its own saved position and the rest attach to it.
  - Dragging any of them moves the group.
  - Undocking puts each one back where you left it.
- **Docked layout:** row left to right (default), row right to left, column
  downwards, or column upwards.
- **Lock flyout buttons:** replaces the mage-only *Lock the mage buttons*
  and carries that setting over once.

**Hidden** is now an option for every flyout group's direction. A hidden
group isn't shown and the other groups start next to the button. For
example, *Portals expand: Hidden* shows only the teleports.

**Combat:** nothing opens, rebuilds or re-docks in combat. Changes made
then apply when combat ends.

### Class Tools — choice options are dropdowns

Choice options are now dropdowns instead of click-to-cycle buttons. That
covers every flyout direction, the mana potion and rune thresholds, the
flyout open mode and the docked layout.

### Tests

- **New `tests/test_flyout.lua` (49 checks):**
  - Hidden groups, including all of them hidden
  - hover and click opening, and no opening in combat
  - docking in all four layouts, dragging the group from any button, the
    shared lock, and dock changes deferred until combat ends
  - the warlock spell discovery: order, Felguard only when known, highest
    stone ranks, no Fel Domination
  - the warlock crest, directions, shard badges and their updates
  - choosing Hidden from the dropdown in the Warlock tab
- **Updated for the shared lock and dropdowns:** `test_ui`, `test_classmage`,
  `test_mageutility` and `test_panels_core`.
- **Total:** 943 checks across 16 suites.

### To do

Items 4, 6, 7 and 8 are done (`docs/TODO.md`).

---

## 3.14

### Class Tools — mana potion and rune warnings

Two new warnings in the **General** tab, for anyone whose power is mana,
in combat, on the *CHECK YOURSELF* frame:

| Warning | When |
|---|---|
| **Use a mana potion (Super Mana Potion)** | Mana is **3000** or more below max and a mana potion is ready |
| **Potion on cooldown: use Demonic Rune** | Mana is **1500** or more below max and no potion is ready |

- **Ready** means the item is in your bags, usable where you are, and off
  cooldown (the global cooldown is ignored).
- **Which potion:**
  - Best first: Cenarion Mana Salve, then Bottled Nethergon Energy (both
    free, and only usable in their own raid), Super, Fel, Mad Alchemist's,
    Unstable, Major and Superior Mana Potion.
  - The warning names the potion and uses its icon.
- **Which rune:** Demonic Rune, then Dark Rune. Runes have their own
  cooldown, separate from potions.
- **When the rune is suggested:** when no potion is ready, whether it's on
  cooldown or you have none left. The warning says which ("Potion on
  cooldown" / "No mana potion").
- **Health:** no rune warning below **35% health**, since runes cost health.
- **No flicker:** once a warning is up it stays until mana is **500 back
  under its threshold**, so it doesn't flick on and off as mana regenerates.
- **Options:**
  - *Warn to drink a mana potion* and *Warn to use a Dark / Demonic Rune*
    (both on).
  - *Potion when mana is down by* (2000–5000, default 3000) and *Rune when
    mana is down by* (1000–3000, default 1500), each a click-to-cycle
    choice.
- **Where it runs:** like the other General checks, only inside raid
  instances (25-man unless *Only in 25-man raids* is unticked). Druids in
  bear or cat form and other non-mana users are skipped.
- **`/wmachine consumes`:** shows your mana deficit, the thresholds, and
  which potion and rune are ready or on cooldown.
- **Saved data:** new `GeneralChecksDB` keys `potionAt` and `runeAt`.

Confirmed in game: runes and potions have separate cooldowns. Still to
confirm: the item IDs, especially the zone potions. A wrong ID just never
shows up in your bags.

### Tests

`tests/test_manaalert.lua` (32 checks) covers:
- the thresholds, including one short of each
- hysteresis
- a potion on cooldown, with fallback to the rune
- the rune on cooldown, with fallback to the other rune
- the global cooldown not counting as a cooldown
- no potions carried
- the health cutoff
- best-potion order, and zone potions only where usable
- combat, mana users and raid-instance gating
- the switches and adjustable thresholds
- the `consumes` output

`test_panels_core` is updated for the longer General tab.

---

## 3.13.1

### Fixed — elixirs didn't count against the flask warnings

In TBC a flask fills both elixir slots, so **a flask, or one battle elixir
plus one guardian elixir**, is a full set. Neither check knew that:

- **Personal check (Class Tools General):** it looked only for a flask, so
  Adept's Elixir plus Elixir of Draenic Wisdom still warned **"No flask"**.
- **Raid check (Buff Check):** the *Flask* check accepted only a flask. The
  separate Battle and Guardian elixir checks accepted elixirs, but nothing
  joined the two.

Both now use one rule from `Core.lua` (`WM:ElixirState`,
`WM:IsFlaskCovered`):

- **Personal warning:** it now says what's actually missing:
  - **No flask or elixirs**
  - **No guardian elixir (or flask)**
  - **No battle elixir (or flask)**

  The feature is renamed *Warn if no flask or elixirs*.
- **Raid check:** renamed **Flask or Elixirs**, with the note *Flask, or
  battle + guardian elixir*. The saved setting key (`flask`) is unchanged.

### Elixir matching

- **Shared lists:** the battle and guardian elixir lists moved from Buff
  Check into `Core.lua` (`WM.BATTLE_ELIXIRS` / `WM.GUARDIAN_ELIXIRS`), so the
  raid and personal checks share them, as the food and flask lists already
  do.
- **Spell IDs:** elixir auras aren't always named after the item. Adept's
  Elixir's buff is *Spellpower Elixir*, which is now also on the list. So
  elixirs are matched by **buff spell ID** as well (`WM.BATTLE_ELIXIR_IDS` /
  `WM.GUARDIAN_ELIXIR_IDS`, all the TBC elixirs). Names still work where the
  client doesn't return an ID.
- **`/wmachine whybuff`:**
  - prints the **spell ID** beside any aura it can't match, so a missing
    elixir can be added straight from that line;
  - matches by spell ID;
  - adds a *Flask or elixirs: covered / missing* summary line.

### Tests

`tests/test_buffcheck.lua` now has 44 checks, using real elixir buff IDs:
- the elixir pair, a flask, and one elixir only, in the raid check
- the battle and guardian checks matched by ID
- the personal monitor's exact warning text for each case
- matching by name when there's no ID
- `whybuff` showing IDs and the summary line

### To do

Added: dock the mage buttons together (`docs/TODO.md`, item 8).

---

## 3.13

### Mage — utility button

A second flyout button beside the portal button, showing the **mage class
crest**, cut from the default UI's class-circles texture. On hover it
expands into one icon per spell, in three groups. Each group is ordered
highest level first, so the best spell sits closest to the button.

| Group | Spells, nearest first |
|---|---|
| **Mana gems** | Conjure Mana Emerald, Ruby, Citrine, Jade, Agate |
| **Armors** | Molten Armor, Mage Armor, Ice Armor, Frost Armor |
| **Food & water** | Ritual of Refreshment (table), Conjure Water, Conjure Food |

- **Only what you know:** a spell appears only if it's in your spellbook.
  It is matched by its English name and by the client's own name for its
  spell ID, so localized clients work.
- **Ranks:** ranked spells (the armors, Conjure Food and Conjure Water)
  appear once. Clicking casts by name, which casts your highest rank, and the
  tooltip shows the highest-rank slot.
- **Icons and tooltips:** each icon is the spell's own spellbook icon, so
  each gem shows its gem. Hovering shows the spell's tooltip.
- **Directions:** each group has its own option in Class Tools > Mage:
  *Mana gems expand*, *Armors expand* and *Food & water expand*. Defaults are
  **left**, **up** and **right**. Groups on the same button that share a
  direction form one line, in the order above.
- **Mage tab:** *Show the mage utility button* (on by default). *Lock the
  portal button* becomes **Lock the mage buttons** and covers both.
- **Combat:** like the portal button, it doesn't open in combat. Changes made
  in combat apply when combat ends.
- **Saved data:** new `MageToolsDB` keys `utilityX`/`utilityY`, `gemDir`,
  `armorDir` and `foodDir`.

### Internals

- **Shared flyout:** the portal flyout is now a reusable flyout object
  (`NewFlyout`) that both buttons use. A flyout takes any number of groups,
  each with a direction key. The same-direction rule generalises: each group
  continues the line of any earlier group sharing its direction.
- **Portal button unchanged:** the `Mage:BuildFlyout` /
  `UpdatePortalButtonVisibility` entry points are kept. New counterparts:
  `Mage:BuildUtilityFlyout`, `UpdateUtilityButtonVisibility`, and
  `UpdateButtons` for both.

### Tests

`tests/test_mageutility.lua` (30 checks) uses a spellbook with
interleaved ranks and a localized Emerald. It covers:
- discovery order, and ranks collapsed to the highest slot
- the class-crest icon
- layout for the default, all-same and mixed directions
- the cast attributes, icons, and highest-rank tooltips
- hover open and close
- the empty-button explanation
- switching the button off
- the options, and cycling one in the Mage tab

All existing portal-button tests still pass on the shared flyout.

---

## 3.12

### Mage — portal button with icons and expansion directions

- **Button:** the portal button is now a 36px icon showing your first
  portal's spell icon (Stormwind's portal icon until you know one). Drag to
  move; *Lock the portal button* still applies.
- **Flyout:** hovering opens a 32px **icon for each portal and teleport you
  know**, using each spell's own icon from your spellbook.
- **Tooltips:** hovering an icon shows that spell's full tooltip, or just
  its name on a client that can't show a spellbook tooltip.
- **Casting:** click an icon to cast. The buttons are plain
  `SecureActionButtonTemplate` buttons, registered for the press that casts
  (see 3.11.3).
- **Two new options in Class Tools > Mage:** *Portals expand* and
  *Teleports expand*. Each cycles Up > Right > Down > Left. The defaults are
  portals **left** and teleports **up**.
  - **Different directions:** each group fans out from the button in its own
    line.
  - **Same direction:** one line, portals first, with the teleports
    continuing on the end.
  - **Saved** in `MageToolsDB.portalDir` and `MageToolsDB.teleportDir`. A
    change made in combat applies when combat ends, since secure buttons
    can't be moved mid-fight.
- **Combat:** the flyout still doesn't open in combat.

### Class Tools — choice options

Features can now be `kind = "choice"` with `options`, `get`, `set` and
`onChange`. They're drawn as a label with a button that cycles through the
options, and they keep their own value rather than an on/off flag in
`ClassToolsDB`. Feature rows are pooled per kind, so switching class tabs
reuses them correctly.

### Tests

`tests/test_classmage.lua` is extended to 32 checks:
- icon buttons, with only the secure template
- spell icons taken from the spellbook
- the anchor's icon
- spell tooltips, and the name fallback
- the layout for the default, shared, opposite and invalid directions
- portals-then-teleports order
- the choice options registered in Class Tools and not stored as on/off
- cycling the option in the Class Tools window, which rebuilds the flyout

---

## 3.11.3

### Fixed — mage portal button didn't cast

The flyout listed your portals and teleports, but clicking one did
nothing. Two causes, both in how the secure buttons were built:

- **Click registration.** The buttons were registered for `"AnyUp"` only.
  On current client builds a secure action button acts only on the press
  that matches the `ActionButtonUseKeyDown` setting. That setting is on by
  default, so the mouse-down casts, and the buttons never received it. They
  now register for exactly the press that casts on this client: `AnyDown`
  with the setting on, `AnyUp` with it off or on builds without it. They
  don't register both, because builds without the check would then cast
  twice. This is re-read every time the flyout is rebuilt.
- **Template order.** The buttons inherited `"SecureActionButtonTemplate,
  UIPanelButtonTemplate"`. Later templates override earlier ones, so the
  visual template came after the secure one, whose click handler is what
  casts. The order is now reversed, with the secure template last.

### Tests

`tests/test_classmage.lua` (14 checks) builds the flyout from a fake
spellbook. It checks:
- the template order
- the click registration under both settings, and on a client without the
  setting
- each button's `type`/`spell` attributes
- portals listed first
- nothing replaces the secure click handler
- leftover buttons are cleared
- no rebuild happens in combat

---

## 3.11.2

### Fixed — dashboard tools menu opened at the bottom of the screen

The **...** button and right-clicking a card opened the tools menu with
`ToggleDropDownMenu(..., "cursor")`. FrameXML places a cursor-anchored
menu from the cursor position divided by a UI scale. When UIParent's scale
isn't the default, as with ElvUI and other UI packs, that calculation puts
the menu far from the click, near the bottom of the screen. The menu is now
anchored to the card's **...** button and opens directly below it at any UI
scale, from either the button or a right-click. The dashboard tests now
check where it is anchored.

---

## 3.11.1

### Fixed — error spam on login (mages)

Logging in on a mage filled the error log with about 60 errors a second:

> `Frame:RegisterEvent(): Attempt to register unknown event "LEARNED_SPELL_IN_TAB"`

Three problems stacked:

1. **The trigger.** The Mage module (3.5) registered `LEARNED_SPELL_IN_TAB`.
   That event exists in Wrath and retail but not in the 2.5.6 client, so
   `RegisterEvent` threw. It's gone: `SPELLS_CHANGED` already fires when a
   spell is learned, and that's what picks up a new portal.
2. **Why it repeated.** Core's timer ran a one-shot callback *before*
   removing it. The start-up callback threw, was never removed, stayed due,
   and fired again on every frame. Timers are now rescheduled or dropped
   before their callback runs, and each callback runs protected: a failing
   timer reports its error once and is done. A failing repeating timer keeps
   its interval. Callbacks that schedule new timers are handled safely.
3. **What else it broke.** Modules were started one after another, unguarded.
   The error aborted the loop, so on every attempt each module after Class
   Mage never finished starting, and the ones before it started again.
   Start-up now runs once, and each module's `Initialize` runs protected: a
   failure is logged as `<Module>:Initialize failed: ...` and the remaining
   modules still start.

Also:

- New `WM:RegisterEvents(frame, { ... })` registers a list of events and
  skips any the client doesn't have (noted in verbose chat). Class Mage and
  Class Warlock use it. Warlock's `PLAYER_TALENT_UPDATE` is registered this
  way in case it's missing too; `CHARACTER_POINTS_CHANGED` is the TBC talent
  event and is what matters.
- The mage portal button was also affected, since its events and first
  refresh came after the failing call. It now sets itself up normally.

The 200 old entries stay in the saved error log until cleared:
`/wmachine clearerrors`.

### Tests

`tests/test_startup.lua` (37 checks) replays the login with a
`RegisterEvent` that rejects unknown events the way the client does. It
covers:
- a failing timer runs once and reports once
- other timers due in the same frame still run
- timers scheduled from inside a callback
- a failing ticker keeps its interval
- a mage login raises no unknown-event error
- a broken module can't stop the others
- every module initialises exactly once, even if start-up is called again
- the mage module still listens for the events it needs
- warlock start-up survives a missing `PLAYER_TALENT_UPDATE`

The timer checks fail against the 3.11 code.

---

## 3.11

### Chat Filter — premade filters

Common advert spam can be filtered with one tick in a new **Premade
filters** section of the Chat Filter window.

| Premade | Matches |
|---|---|
| **GDKP** | `GDKP` |
| **Guild Loot Run** | `Guild Loot Run` |
| **Gear Carry** | `Gear Carry`, `Gear Carries` |

- **Same matching as your own phrases:** anywhere in a message, ignoring
  case, colours and link brackets.
- **Applied before Keyword Monitor**, like every Chat Filter phrase.
- **Off by default**, so updating doesn't start hiding adverts nobody
  asked to hide.
- **Kept apart from your own phrase list.** Switching one on doesn't add to
  the list, and switching it off brings those messages straight back.
- **Hidden counts:** each premade's checkbox shows how many messages it has
  hidden this session, and the dashboard's "Hidden this session" tool
  lists them.
- **Saved** in `ChatFilterDB.premades`.
- **Counting:** the dashboard status and the Keyword Monitor note now count
  *filters* (ticked premades plus your own phrases) rather than only your
  own phrases.

---

## 3.10

### New module — Chat Filter

Hides chat spam by phrase. Add *Guild Loot Run* and every message
containing it disappears from your chat frames.

- **Phrases:** you add plain-text phrases. A message is hidden when it
  contains one anywhere. Case, colour codes, item-link brackets (`[Item]`
  is read as the text you see) and runs of spaces are ignored. There are no
  wildcards: `50% off` means exactly that.
- **Applied before Keyword Monitor.** Keyword Monitor reads channel chat
  through its own event handler, so hiding a line from the chat frame alone
  wouldn't stop it parsing that line. It now asks Chat Filter first and
  skips anything Chat Filter hides, so filtered spam can't produce keyword
  matches. The warning appears at the top of the Chat Filter window and of
  the Keyword Monitor window. The Keyword Monitor note also says whether
  Chat Filter is on and how many phrases it has.
- **Where it applies:** public channels by default. Say/yell and whispers
  can be switched on. Your own messages are never hidden.
- **Hidden counts:** kept per phrase and in total for the session, in the
  window and in the dashboard card's tools menu. A message shown in several
  chat tabs is counted once.
- **Window:** `/wmachine filter` (also `chatfilter`, `cf`), built on the
  panel builder. It has an enable switch, the chat types, an "Add phrase"
  box (Enter or Add), and the phrase list with per-phrase counts, Remove,
  and a two-click Clear All.
- **Dashboard:** a Guild & Social card with an on/off switch. Off, nothing
  is hidden and Keyword Monitor sees every message again.
- **Saved data:** new SavedVariable `ChatFilterDB`.
- **Not filtered:** Services Parser still reads every advert in the
  Services channel; the filter doesn't apply to it.

### Class Tools card icon

The card used `Achievement_Character_Human_Male`. Achievement icons were
added in Wrath, so the icon doesn't exist in the TBC client. The card now
shows your class crest, cut from the default UI's class-circles texture
with `CLASS_ICON_TCOORDS`. If that table is missing, it falls back to
`INV_Misc_Gear_01`. The dashboard test now rejects any `Achievement_` icon
on a card.

### Tests

- `tests/test_chatfilter.lua` (39 checks) covers:
  - normalising
  - phrase matching, including plain text that looks like a pattern
  - duplicate and empty phrases
  - chat types, own messages, the on/off switch
  - counting once per message across tabs
  - Keyword Monitor skipping filtered messages, and seeing them again with
    the filter off
  - both windows' warnings
  - the list, the add box and Remove
- The dashboard suite covers the class crest and its fallback.
- 716 checks in total.

---

## 3.9

### Every window on the panel builder

3.7 built the panel builder and moved three windows onto it. 3.9 moves the
rest. The only frames still built by hand are the on-screen warnings (Aura
Range, the Class Tools *CHECK YOURSELF* frame, the Debuff Tracker display)
and the dashboard's tools dropdown. Those are overlays, not windows.

Every window now:
- closes on **Escape**
- **remembers where you put it**
- uses the global theme
- fits the screen, scrolling or giving a list the leftover room

Saved settings are unchanged. Where a window used to save its own position
(`dashboardPos`, `KeywordMonitorDB.position`, `WhisperLogsDB.position`),
that position is adopted once, so nothing jumps back to the centre.

| Window | Notable changes |
|---|---|
| **Dashboard** | Builder shell; card list in a Fill area; minimap toggle, Settings and Help in the footer |
| **Settings** | Real dropdown for the theme; fits its content |
| **Auto Logger** | Fits its content; the status line updates as soon as a box is ticked |
| **Aura Range** | Fits its content; Test Alert resets its sample instead of adding a second line |
| **Guild Invite** | The log updates live while open; the trigger word also saves when you click away, and only reports a change when there is one; roster count in the footer |
| **Keyword Monitor** | Builder resizing (capped at the screen); Keywords / Channels / Alerts as collapsible sections; recent-keyword buttons reused |
| **WarcraftLogs Lookup** | Builder region dropdown; the list refreshes on open |
| **Services Parser** | Tab rows mark the current dungeon, with listing counts; the separate settings window is now a collapsed *Settings* section; edit boxes also save on focus loss, and an empty channel name is refused |
| **Mail & Trade** | The current tab is marked; builder character dropdown; filters and settings shown on their own tab; list rows reused instead of recreated (and leaked) on every refresh |
| **Recruiter** (main, messages, history) | Builder edit boxes that save on Enter and focus loss, with Escape to restore; full class names in the class grid; messages and history open beside the main window |
| **Class Tools** | Scrolls when a class has many features; tabs show the current class |
| **PvP leaderboard** | Rows reused; the empty-state text no longer stacks; columns fit the window; position saved |
| **ArmorySnap** | Builder shell around the unchanged paper doll; builder dropdowns; position saved |

**Tooltips:** Mail & Trade, Guild Invite and Recruiter had none, and most
other windows only had some. Every control whose effect isn't obvious from
its label now has one, written from what the code actually does.

### ArmorySnap follows the global theme

ArmorySnap's own "ElvUI Theme" checkbox is gone, along with the code that
synced it to the global theme. The browser now uses the Watching Machine
theme like every other window. The ElvUI-specific inner styling (pixel
borders on gear slots, the status bar and the talent panel) switches live
with the global theme. `/as theme` now says where the theme is set.
`ArmorySnapDB.options.elvuiTheme` is left in place but unused, because
the standalone ArmorySnap addon shares that saved variable and still reads
it.

### Theme changes restyle in place

`WM:OnThemeChanged` no longer destroys and rebuilds the dashboard and the
Settings panel. Every window, card and theme-coloured text is registered
with the reskin, so it just re-skins them and refreshes Settings. The
dashboard title is theme-coloured too now.

### Builder additions

- `Dropdown` widget (Blizzard dropdown; options can be a function, re-read
  on open).
- `resizable = { minW, minH, maxW, maxH }`: size grabber, saved size,
  maximum capped at the screen, `onResize`.
- `AddFooterText`, `onHide`.
- `defaultPoint` for a window's first open (Recruiter messages and history,
  PvP leaderboard).
- `legacyPosition` adopts a position saved by an older version of the
  window, once.
- `numeric` edit boxes, `name` on checkboxes, and `Choice.buttons` for
  per-option badges.

### Removed

- `WM:FitHeight` / `WM:ScreenFitHeight`, superseded by the builder.
- The module theme hook `OnGlobalThemeChanged`.
- `WM_ServicesParserSettings`, `WM_SettingsThemeMenu`, and the hand-made
  Keyword Monitor size grabber.

### Tests

- New suites:
  - `test_panels_core` (90): dashboard, Settings, Class Tools, leaderboard
  - `test_panels_social1` (53): Auto Logger, Aura Range, Guild Invite
  - `test_panels_social2` (93): Keyword Monitor, WarcraftLogs Lookup,
    Services Parser
  - `test_panels_mailrecruit` (95)
  - `test_panels_armorysnap` (53)
- `test_uibuilder` extended to 62 checks.
- 654 checks across ten suites in total.

---

## 3.8

### Dashboard: see what's on, reach everything

The dashboard was a list of thirteen identical cards. Each had one Open
button and a one-line description, and nothing showed whether a module was
on. Tools such as `whyboss`, `whybuff`, `soulstone`, Shear tallies and
ArmorySnap's snapshot commands had no button anywhere.

- **Groups:** cards sit under **Raid** (Buff Check, Debuff Tracker, Class
  Tools, Aura Range, ArmorySnap), **Guild & Social** (Guild Invite,
  Recruiter, PvP Tracker, Keyword Monitor, Services Parser, WhisperLogs)
  and **Logging** (Auto Logger, Mail & Trade).
- **Card tooltip:** hovering a card shows what the module does in a
  sentence or two, its full status (which the card may truncate), whether
  it's on, and its `/wmachine` command.
- **On/off switch:** the card's checkbox switches the module's *own* flag,
  through a new `IsModuleEnabled` / `SetModuleEnabled` pair. The module's
  settings checkbox uses the same function, so the two always agree. An off
  module's icon is greyed out. Modules with a switch:
  - Buff Check (the ready-check trigger)
  - Debuff Tracker (hides the display)
  - PvP Tracker (stops its event handlers)
  - Guild Invite
  - Aura Range (clears active alerts)
  - ArmorySnap (automatic scanning)
  - Keyword Monitor (pause; for the session only, like its Stop button)

  Mail & Trade, Services Parser, WhisperLogs, Recruiter and Class Tools
  have no single on/off setting, so their cards have no switch. Auto Logger
  has two separate settings (chat log and combat log), so it has none
  either.
- **Tools menu:** opened with the **...** button or a right-click on the
  card. A confirmation dialog guards the actions that discard data (clear
  exclusions, reset ArmorySnap session). Class-specific tools appear only
  on that class.
  - **Debuff Tracker:** encounter callouts, why is my target a boss,
    exclude / un-exclude target, list exclusions, clear exclusions, Shear
    tallies, shadow resist gear check.
  - **Buff Check:** run check now, explain buffs on target.
  - **ArmorySnap:** snapshot now, list snapshots, scanner status, reset
    session.
  - **PvP Tracker:** show leaderboard, request guild sync.
  - **Class Tools:** consumable check, soulstone timers (warlock), portals
    (mage).
- **Card text** (title, description, status) is width-limited and
  truncates, so long status lines no longer run under the buttons.
- Buff Check's manual run is now `BuffCheck:RunLocalCheck()`. It works even
  with the ready-check trigger off; Run Check Now and the tools menu both
  use it.

### Other ways in

- **Minimap button:** right-click opens Settings (it used to do the same as
  left-click). The tooltip says so and lists every module's status in
  dashboard order with proper names.
- **Options > AddOns > Watching Machine:** a page in the game's own options,
  with Open Dashboard and Theme & Minimap buttons. It uses the Settings API
  where the client has it and falls back to `InterfaceOptions_AddCategory`.

### Cleanup

- `WatchingMachineDB.moduleStates` was created and merged on every load but
  never read. It is removed, and cleared from existing saved variables.
- ArmorySnap's `/as auto` used to update the Auto-scan checkbox through a
  variable declared later in the file, which Lua reads as an unset global,
  so the checkbox didn't follow the command until the window was reopened.
  It now goes through `AS:SetModuleEnabled`.

### Tests

`tests/test_dashboard.lua` (111 checks) loads the whole addon in `.toc`
order and covers:
- the card groups
- switches against each module's own flag, in both directions
- every tools-menu entry resolving to a real module method
- class-only tools
- right-click and **...** menus
- card tooltips
- the Options > AddOns registration, on both API paths

---

## 3.7

### Shared panel builder

Every settings window used to be laid out by hand: a running `yOffset`,
per-module checkbox and slider boilerplate, and a frame height measured by
eye. Three times that produced a panel taller than the screen: Debuff
Tracker settings at 948px, the dashboard card list, and PvP Tracker at
780px. The new `UI.lua` (`WM.UI`) builds a panel from a vertical list of
rows instead.

- **Panel** (`WM.UI:CreatePanel`):
  - title, close button, Escape to close, theme skin
  - height fitted to its content, capped at `maxHeight` and at the screen;
    the body scrolls when the content is taller
  - fixed-height panels (`scroll = false`) can give the remaining space to
    a list with `Layout:Fill`
  - optional footer button row
  - position saved in `WatchingMachineDB.panels[name]`
- **Rows:**
  - `Checkbox`, `Slider`, `Cycle` (replaces the hand-rolled channel cycle
    buttons), `Choice` (one-of-N buttons), `EditBox` (always saves on Enter
    and when focus leaves; Escape restores), `Buttons`, `Note` (wrapped grey
    text sized to fit), `Header`, `Separator`, `Space`
  - `Section`: collapsible, with state remembered per panel
  - `Row(height)` with the same widgets at an x offset, for two-column rows
- **Specs:** every control takes a `get`/`set` pair, an optional
  `disabled()` and an optional `tooltip` (`{ "Title", "wrapped text", ... }`;
  no more hand-broken lines). `panel:Refresh()` re-reads all of them, so a
  panel never has to be destroyed and rebuilt to show new state.
- **Two-click confirm:** `Button{ confirm = true }` replaces the copies in
  PvP Tracker.

### Moved to the builder

- **Debuff Tracker settings.** The settings window and the separate
  Encounter Callouts window are one panel again. It is 700px tall at most
  and scrolls, with these sections: Raid Auto-Detection, Missing Debuff
  Alerts, Target Filtering, Encounter Callouts, Debuff Selection by Class.
  - The debuff list used to sit in a 141px inner scroll box. It is now part
    of the panel's own scroll, and collapsing the sections above it gives it
    the whole window.
  - `/wmachine encounters` opens the panel scrolled to Encounter Callouts.
    `WM_DebuffEncounterFrame` no longer exists.
  - Roster scans and the auto-detect toggle refresh the panel in place.
    Before, they destroyed and recreated it, which lost the scroll position
    and leaked the old frame.
  - The delay and cooldown sliders, the Scan Now button and the footer
    buttons have tooltips now.
- **PvP Enemy Tracker.**
  - Guild Sync and KOS Leaderboard are collapsible sections; collapsing
    them gives the KOS list more room.
  - The window is still 700px and the list still fills what's left.
  - Every alert option has a tooltip.
  - The Reset and Clear All confirmations use the shared two-click button.
- **Buff Check.** The panel is now built from rows and fits its content.
  The PallyPower detection line is a note that's re-read on open, and Run
  Check Now is a footer button.

Saved settings are unchanged. The only new saved data is panel position
and section state in `WatchingMachineDB.panels`.

### Tests

- `tests/wowstub.lua`: a reusable fake WoW client (frames, scripts, check
  buttons, sliders, scroll frames, edit boxes).
- `tests/test_uibuilder.lua` (43 checks):
  - fitting, screen cap and scrolling
  - sections, edit boxes, cycles, sliders
  - confirm buttons, saved position, Escape registration
- `tests/test_panels.lua` (30 checks): the three converted panels, driven
  through their controls.

---

## 3.6

### Food check on by default

Buff Check's **Food Buff** check (Well Fed, or Enlightened from Skullfish
Soup) is now on by default. Saved settings from earlier versions still hold
the old default, so 3.6 turns the check on **once** for existing installs
(tracked by `BuffCheckDB.foodDefaultOn`). After that the player's own choice
sticks. The Class Tools General food warning was already on by default and
uses the same aura list.

### Panels never taller than the screen

New `WM:FitHeight(frame, desired, min)` / `WM:ScreenFitHeight(desired, min)`
in `Core.lua`. A panel gets its normal height, capped at the screen height
minus 16px, and re-fits each time it opens in case the UI scale has changed.
Each panel's scroll list is anchored to the bottom and absorbs the
difference.

- **Debuff Tracker settings** (742px): unchanged at 768. At larger UI scales
  the debuff tree shrinks instead of Reset Position and Test Display going
  off screen. Minimum height 640.
- **PvP Enemy Tracker** (700px) and the **dashboard** (700px) get the same
  treatment.
- **Keyword Monitor** could be resized up to 800px tall. Its maximum, and
  its 580px opening height, are now capped at the screen.

This is the first piece of the shared panel builder proposed in the UI
review. It doesn't replace that work: Debuff Tracker settings still needs
real scrolling to stop squeezing its debuff tree.

### Settings that had no control

- **ArmorySnap Auto-scan:** `ArmorySnapDB.options.enabled` gated automatic
  scanning but had no checkbox and no command. It now has an **Auto-scan**
  checkbox in the browser's checkbox row (with a tooltip) and `/as auto`.
  Manual `/as snap` works either way.
- **Mage portal lock:** `MageToolsDB.portalLocked` was saved and honoured,
  but nothing could set it. The Mage tab now has **Lock the portal button**,
  kept in step with the saved flag the same way General's "Only in 25-man
  raids" is.
- **Debuff Tracker:** `DebuffTracker:ToggleTracker()` had no caller and has
  been removed. The Enable checkbox in the settings window is the real
  toggle.

### Tests in the repo

The Lua harnesses now live in `tests/` (`test_buffcheck.lua`,
`test_ui.lua`, and `run.sh`, which exits non-zero on any failure). They used
to live only in session scratch space. The `.toc` doesn't list them, so the
game never loads them.

---

## 3.5.2

### UI fixes

These come from the first batch of the UI review: things that were broken.
Layouts aren't redesigned, and saved settings are untouched.

- **Escape closes every window.** Previously only ArmorySnap was registered
  to close on Escape. Every panel that goes through `WM:RegisterSkinnedPanel`
  is now registered too. On-screen warning frames (Aura Range, Class Tools,
  the debuff overlay) are not panels and are left alone.
- **PvP Enemy Tracker fits on screen.** The window was 780px tall. At UI
  scale 1.0 the screen is about 768px, so the bottom of the KOS list and its
  scroll-down arrow were off screen. It is now 700px tall; the controls
  don't move and the list is 80px shorter.
- **Theme changes reach every window.**
  - Section headers and separators were coloured once, when the window was
    built, so switching theme left the old colours behind. This affected
    PvP, Buff Check, Aura Range, Class Tools and both Debuff Tracker
    windows. They now register through `WM:ThemeText` / `WM:ThemeTexture`
    and are recoloured on every theme change.
  - ArmorySnap read only its own ElvUI flag after first run, so it never
    followed the global theme. A global theme change now resets it to
    match; its own toggle still works as an override until the next change.
  - Stale dashboard cards are now dropped from the reskin list when the
    dashboard is rebuilt. The old check looked one parent level too shallow
    and never matched. A rebuilt Debuff Tracker settings panel is
    unregistered the same way.
- **Services Parser settings** can no longer be dragged off screen. It now
  has a global name (`WM_ServicesParserSettings`) and is clamped to the
  screen.
- **Hiding the dashboard on a failed security check** now uses
  `WM.dashboard`. The old code read a file-local that is declared further
  down, so it always saw nil.
- **Help** now lists `/wmachine status`, `/wmachine clearexclusions` and
  ArmorySnap's `/as` sub-commands. The theme description in Settings no
  longer claims to cover every frame.

---

## 3.5.1

### Skullfish Soup counts as food

Skullfish Soup is a drink, and its buff is called **Enlightened** (20 crit
rating and 20 Spirit for 30 minutes), not **Well Fed**. Both food checks
matched only "Well Fed", so anyone on Skullfish Soup was reported as unfed.
Enlightened doesn't stack with Well Fed, so either one now counts as the
player's food buff.

- **Buff Check:** the ready-check food check is renamed from *Well Fed* to
  **Food Buff** and accepts either aura. It is still **off by default**;
  turn it on in the Buff Check panel. The saved setting key (`wellfed`)
  hasn't changed, so existing settings carry over.
- **Class Tools — General:** the in-raid "no food buff" warning accepts
  either aura too.
- **Shared names:** food and flask aura names now live in one place in
  `Core.lua` (`WM.FOOD_BUFFS`, `WM.FLASK_CONTAINS`, `WM:IsFoodBuff`,
  `WM:IsFlaskBuff`). Buff Check and Class Tools General both use it, so the
  ready-check audit and the self check can no longer disagree.

---

## 3.5

### Class Tools — first class features, and a shared warning frame

3.4 shipped the framework. 3.5 is what plugs into it.

Features no longer each build their own alert window or their own timer. They
call `SetAlert(key, text, icon)` / `ClearAlert(key)`, and Class Tools collects
everything into **one movable *CHECK YOURSELF* frame** (up to six lines),
hidden the moment the last warning clears. Registered monitors share a single
one-second tick, so the cost does not grow with the number of checks.

Frame options are in the panel, under the feature list: sound on a new
warning, lock in place, reset position, and **Show example** — two dummy lines
for six seconds so the frame can be found and positioned without waiting for a
real warning.

### New module — Class: Warlock

- **Armor** — warns when Fel Armor, Demon Armor or Demon Skin has fallen off.
- **Demonic Sacrifice** — warns only when the talent is actually taken *and*
  no demon is out. A warlock standing there with a pet has made a choice, not
  a mistake, so nothing is raised.
- **Soul Link** — warns only when talented, with a living pet, and with no
  sacrifice buff up. The two checks interlock: a sacrificed warlock is never
  nagged about Soul Link, and a warlock with a pet out is never nagged about
  the sacrifice.
- **Soulstone timers** — the group is scanned for the Soulstone Resurrection
  buff, which carries a real expiration time. Reading the buff rather than
  watching for casts means it works for soulstones applied by any warlock,
  including ones cast before you logged in. `/wmachine soulstone` lists who is
  stoned and for how long.

Talents are read by name across all trees (self-inspection is reliable in TBC
Classic) and cached for five seconds. The cache is dropped outright on
`CHARACTER_POINTS_CHANGED` / `PLAYER_TALENT_UPDATE`, so a respec takes effect
immediately rather than at the end of the TTL.

### New module — Class: Mage

- **Armor** — warns when Molten, Mage, Ice or Frost Armor is missing.
- **Portal / teleport button** — a single draggable button that expands on
  hover into every teleport and portal you know, portals first. It is built
  from your spellbook, so it shows exactly what you can cast and nothing else,
  and rebuilds on `LEARNED_SPELL_IN_TAB` / `SPELLS_CHANGED`.

The spellbook scan derives the `Teleport:` / `Portal:` prefixes from
`GetSpellInfo` on two known spell IDs rather than hardcoding English strings,
so it works on localised clients.

The flyout deliberately refuses to expand in combat. Its entries are
`SecureActionButtonTemplate` buttons, which cannot be created or reconfigured
during combat lockdown; since portals aren't castable in combat either,
declining to open is honest behaviour rather than a limitation worth working
around with secure state drivers.

### New module — Class: General

Consumable checks that apply to every class, under a **General** tab that
always sorts first.

- **Flask**, **food buff** (Well Fed) and **weapon oil / stone**.
- Active **only inside a raid instance**, and **25-man only by default**, with
  a tick to include 10-mans. No nagging in town or while questing.
- The wording follows your class: casters are told about wizard oil, melee
  about sharpening stones and weightstones.
- The off hand is checked only when a real weapon is equipped there. Shields
  and held items occupy the same slot and can't take an oil, so they are
  skipped rather than producing a permanent, unfixable warning.
- Flask matching is on substring, so `Unstable Flask of the Beast` and
  `Unstable Flask of the Sorcerer` count alongside the standard flasks.
- `/wmachine consumes` prints what the checks currently see.

Classic exposes only *whether* a temporary weapon enchant is present, not
which one, so the check is presence-based — an oil on a melee weapon will
satisfy it.

### New commands

- `/wmachine class` — open Class Tools (`/wmachine classes`, `classtools`)
- `/wmachine soulstone` — soulstone timers (`soulstones`, `ss`)
- `/wmachine portals` — list known teleports and portals (`teleports`)
- `/wmachine consumes` — what the general checks see (`consumables`)

### Saved variables

`ClassToolsDB`, `GeneralChecksDB` and `MageToolsDB` are declared in the TOC.

---

## 3.4

### Mail Logger — Open All logged by diffing the inbox

The dedupe added in 3.2 could not work during an Open All, for two reasons:

- Its key embedded `mailIndex`, but indices shift as each mail is emptied, so
  the same physical mail produced a different key after a shift and was logged
  again.
- The guard was wiped on every `MAIL_INBOX_UPDATE`, and that event fires
  continuously throughout a bulk pull — erasing the guard before it could
  suppress anything.

It held up when clicking mail slowly, which is what the earlier tests
simulated, because those tests controlled when `MAIL_INBOX_UPDATE` fired.

Replaced with content diffing. Every receivable unit (money, and each
attachment) is fingerprinted by sender / subject / item / count into a
multiset; the inbox is re-read every 0.4s while the mailbox is open, and
whatever disappeared is logged. This is:

- immune to retries — a retry changes nothing in the inbox,
- immune to index shifts — no index appears in the key,
- correct for N identical mails — multiset counts,
- independent of which API the open-all uses, or how fast it runs.

Details:

- The take hooks no longer log. `ReturnInboxItem` and `DeleteInboxItem` are
  hooked only to suppress mail that leaves *without* being received.
- No diff on `MAIL_CLOSED`: the client can report an empty inbox afterwards,
  which would look like everything was collected.
- An empty read is held for one poll before being trusted, so a momentary blip
  can't mass-log, while genuinely emptying the last mail still records.

### New module — Class Tools

Detects the class you're playing and surfaces the tools built for it.

- Class section in the dashboard (`/wmachine class`) with a tab per class.
  A tab appears only once a feature has been registered for that class, so
  there are no empty tabs for work not yet done.
- Your own class is selected on open, and is always offered as a tab even
  before it has tools, so the panel explains itself.
- Per-feature toggles saved per class; the same feature key on two different
  classes keeps independent state.
- Ships as the framework: features call `RegisterFeature(class, def)` and
  appear in the panel automatically, then query `IsEnabled` /
  `IsActiveForPlayer` without touching the UI. Registration before the saved
  variables load is supported.

### Dashboard — card list now scrolls

With 13 modules the card list needed 634px inside a 585px area, so the last
card was cut off, and the panel can't grow past the ~768px screen. The list is
now a scroll frame, which also stops this recurring as more modules land.

## 3.3

### Debuff Tracker — Black Temple shadow resist gear check

Mother Shahraz is the only Black Temple fight that wants shadow resist gear, and
staying in it for the rest of the raid is an easy and costly mistake.

- Arms when Mother Shahraz dies, **and** the moment you engage one of the Grand
  Promenade pulls (Shadowmoon Reaver, Promenade Sentinel, Illidari Archon /
  Assassin / Battle-mage / Blood Lord) — so a `/reload` after Mother is already
  down still works.
- Reads **equipped gear only** via item stats, never `UnitResistance`, so Shadow
  Protection or a Shadow Resistance Aura can't produce a false warning.
  Matches both item-stat key conventions, since they differ between clients.
- Configurable threshold (default 60 gear SR) so a single piece with incidental
  resistance is ignored; a Mother set runs well over 200.
- Warns locally with a raid-warning flash and a sound; optional Say / Party /
  Raid / `/rw` announce. Deliberately **not** gated by the leader-announcer rule
  used elsewhere, because it concerns the individual player's own gear.
- One warning per pull (20s cooldown). Disarms on zone change.
- `/wmachine srcheck` lists every equipped piece carrying shadow resistance, the
  total against the threshold, whether it is armed, and cross-checks the
  character sheet so a broken item API is obvious rather than silent.

### Debuff Tracker — settings panel split (fixes clipped controls)

The settings panel had grown from its original 700px to 948px as features were
added. WoW's UIParent is only about 768px tall at UI scale 1.0, so the lowest
controls were off-screen and unreachable.

- Encounter callouts (Illidan Doom warning, Illidan Shear monitor, shadow resist
  check) moved into their own window, opened with `/wmachine encounters` or the
  **Encounter Callouts...** button in Debuff Tracker settings.
- The main panel is back to 742px and fits on screen again.

### Debuff Tracker — Shear settings completed

- Added the missing **chat throttle** slider (0–30s; throttled Shears are still
  counted and still shown locally, only the chat line is skipped).
- Added the missing **pull summary** checkbox.
- Removed the redundant `shearAnnounce` flag — the *Me only* channel option
  already does the same thing.

## 3.2

### Debuff Tracker — Illidan Shear monitor

Tracks Shear on Illidan's main tank and calls it out, with a toggle in the
Debuff Tracker settings (on by default).

Shear cuts the main tank's maximum health by roughly 60% for a few seconds,
cannot miss, but can be dodged, parried or blocked. Damage meters under-report
it for two reasons: the damaging part is a max-health debuff rather than a
normal hit, and an avoided Shear produces only a miss event with no damage at
all. So the monitor is deliberately aggressive:

- Watches every subevent a Shear can produce — `SPELL_CAST_START`,
  `SPELL_DAMAGE`, `SPELL_AURA_APPLIED`, `SPELL_AURA_REFRESH` and
  `SPELL_MISSED` (dodge / parry / block / immune / absorb).
- Matches on spell ID **and** localized spell name, so an unexpected or
  unlisted ID still registers, and non-English clients work.
- Sweeps raid auras on `UNIT_AURA` as a backup, catching a landed Shear even
  if its combat-log event is dropped. Only active once Illidan or a Shear has
  been seen in the pull, so it costs nothing elsewhere.
- Deduplicates per cast: the several events one Shear generates produce a
  single call, not three.
- Ignores anything sourced from your own group, so nothing else can spoof it.

Reporting:

- Hits are announced to raid chat by default; avoided Shears are counted but
  not announced (Shear repeats every ~10s, so calling both outcomes doubles the
  chat). Both are always shown locally.
- Channel picker: Me only / Say / Party / Raid / `/rw`, plus an optional
  throttle for the minimum gap between chat calls.
- Optional local cast warning on `SPELL_CAST_START` — the ~1.5s window to use
  Shield Block or Holy Shield. Never sent to chat.
- Per-pull summary when combat ends: total, hit vs avoided, a per-tank
  breakdown (so tank swaps are visible), and which avoidance types occurred.
- Uses the existing announcer rule, so only the raid leader (or assistants, if
  allowed) sends to chat and multiple addon users don't duplicate it.
- `/wmachine shear` shows status and tallies; `/wmachine shear on|off` toggles.

### Debuff Tracker — Illidan Doom warning

**Added**
- Sends **CAST DOOM NOW** as a raid warning when Illidan Stormrage (npcID 22917)
  drops to 68%, so warlocks land Curse of Doom before he lifts off at 65%.
- New checkbox in Debuff Tracker settings: *Illidan 68%: raid warn "CAST DOOM NOW"*
  (on by default).
- Fires once per pull. Illidan is found through any unit pointing at him (boss
  frames, target, focus, raid targets, nameplates), so you don't have to be
  targeting him.
- Follows the existing announcer rule: the raid leader sends it (assistants only when
  "Assistants can announce" is on); everyone else gets a local chat line. Falls
  back to /raid if the sender has no assist.
- Skipped if Illidan is already below 60% when first seen (for example after a
  /reload mid-fight).

### Buff Check — elixir and flask fixes

**Fixed**
- Elixir of Empowerment is now classed as a Guardian elixir (was Battle).
- Elixir of Major Defense is classed as a Guardian elixir (it had been put in the
  Battle list, so tanks pairing it with a battle elixir were flagged).
- Flask matching is substring-based, so "Unstable Flask of the Beast/Sorcerer"
  now counts for the flask and both elixir slots.
- Expanded the Battle/Guardian elixir lists with missing TBC and classic-era entries.

**Added**
- `/wmachine whybuff` (alias `buffdebug`): lists every aura on your target or
  yourself and which check each one satisfies.

---

## 3.1

### Debuff Tracker — boss detection false positives eliminated

The tracker treated any mob at `level >= playerLevel + 3` with elite classification
as a boss. TBC raid trash is level 72–73 elite exactly like real bosses, so trash
triggered boss alerts — Magtheridon's Hellfire Warders being the clearest case.
Display names couldn't separate them either, since some trash shares names with
encounter mobs.

**Added — NPC-ID identity**
- Mobs are identified by the `npcID` embedded in their creature GUID, which is
  unique per creature type even when two mobs share a display name.

**Added — Health-pool floor**
- Mobs below a configurable max-health threshold are never treated as bosses
  (default 150,000; slider 0–400k, 0 = off). Separates trash from bosses
  independently of level and classification.

**Added — Focus target tracking**
- On multi-boss encounters (Fathom-Lord Karathress, Illidari Council, …) group
  damage is accumulated per hostile GUID over a rolling 6-second window from the
  combat log. The mob absorbing the most raid damage is the raid's real kill
  target, and alerts fire only for it.
- Targeting an add the raid is ignoring — a Fathom-Guard that isn't next in the
  kill order — no longer sets alerts off.
- The focus follows the raid automatically when kill order or strategy changes.
  No hardcoded kill orders; switching to "burn the Fathom-Lord first" needs no
  configuration.
- Fails open: an expired or stale focus never suppresses alerts permanently.

**Added — Manual exclusions and diagnostics**
- `/wmachine exclude` — with a mob targeted, permanently stops that creature type
  triggering boss alerts. Keyed on npcID, so same-named mobs elsewhere are
  unaffected.
- `/wmachine unexclude`, `/wmachine exclusions` — manage the list.
- `/wmachine whyboss` — prints exactly how the tracker sees your target: npcID,
  classification, level, health vs. the floor, exclusion state, current raid
  focus, and whether an alert would fire.
- "Exclude Target" button and both new settings added to the Debuff Tracker panel.

**Performance**
- Combat log handling merged into a single parse feeding both damage tracking and
  pull detection.
- Group membership lookups are now a cached GUID hash set instead of a 40-unit
  scan on every combat log event.

---

## 3.0

### New module — Aura Range

Visual and audio alerts when you drift out of range of party auras and shaman
totems. These buffs drop off the instant you leave their radius, so the module
watches your own auras via `UNIT_AURA` — event-driven, no polling, and it fires
the same frame you step out.

- Tracks Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin
  auras, and totem buffs (Strength of Earth, Grace of Air, Wrath of Air, Totem of
  Wrath, Mana Spring, Healing Stream, Stoneskin, Windfury). Each individually
  toggleable.
- Movable, pulsing on-screen alert listing exactly which auras you lost, with
  icons; clears the moment you walk back into range.
- Optional raid-warning sound, throttled so losing several totems at once doesn't
  triple-blast you.
- False-alarm guards: no alerts while dead (death wipes all buffs), when the
  providing class has no living member in the group, on zone transitions, or after
  leaving the group.
- Stale alerts auto-expire (5–30s, default 15s) to cover totems that simply
  expired or were destroyed.
- Lockable alert frame, test button, `/wmachine range`.

### Buff Check — Battle and Guardian Elixir detection

- Two new buff groups with TBC-accurate elixir lists for both categories,
  including classic-era holdovers still in use.
- Flasks correctly satisfy **both** elixir slots, matching TBC's consumable rules —
  a flasked player is never nagged about elixirs.
- Off by default; toggle in settings alongside the other consumable checks.

### Buff Check — PallyPower single-target override fix

- Expected blessings were computed as the union of class-wide **plus**
  single-target assignments, so a player with a single-target override (e.g. a
  feral tank assigned single Might) was falsely flagged for missing that same
  paladin's class-wide blessing (Salvation on druids).
- Expectations are now computed **per paladin**: a single-target assignment
  replaces that paladin's class blessing for that player, while class blessings
  from other paladins still apply.

---

## 2.9

### ArmorySnap integrated as a module

The standalone ArmorySnap addon is now a Watching Machine module, including its
v1.2 scanner overhaul.

- Passive raid gear snapshots — enchants and gems included, since TBC item links
  embed both.
- **Event-chained scanning**: the next inspect fires the moment the previous one
  resolves (success, timeout, or self-capture) instead of waiting on a fixed
  ticker. A full 25-man with everyone in range captures in roughly 15–20 seconds;
  the old fixed-tick scanner took 75+ seconds.
- Out-of-range retry cooldown reduced from 120s to 15s — stragglers who walk into
  range are captured in seconds instead of minutes.
- Paper-doll browser: pick a snapshot, pick a member, see their gear laid out like
  the character frame with native tooltips. Shift-click to link items.
- Talent tree capture (full detail for yourself; tree names and icons for
  inspected players — the Anniversary API doesn't expose inspected point counts to
  any addon).
- Enchant/gem count summary per character; snapshot retention 1/7/14/30 days.
- Reuses the `ArmorySnapDB` saved variable, so archives from the standalone addon
  carry over automatically.
- Detects the standalone addon and stands down if both are loaded, preventing
  inspect conflicts.
- Keeps the standalone `/as` commands; adds `/wmachine armory`.

---

## 2.8

### Patch 2.5.6 support

- Interface bumped to `20506` (TBC Anniversary patch 2.5.6); Classic Era to `11508`.
- Removed stale `Interface-Wrath` / `Interface-Cata` declarations for clients that
  no longer exist.

### New module — Buff Check

Full raid buff audit that runs automatically on every ready check.

- **You start the ready check** → missing buffs are announced to raid/party chat.
- **Someone else starts it** → the same report prints locally, where only you see it.
- Tracks Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings, Divine
  Spirit, Shadow Protection, Well Fed, and Flasks. Each individually toggleable.
- Class buffs are only checked when the providing class is actually in the group —
  no priest means no Fortitude nagging.
- Only classes a buff applies to are checked; rogues aren't flagged for missing
  Intellect.
- Offline and dead players are skipped and listed separately in the local report.
- Long reports are split to respect the chat message length cap.
- "Run Check Now" button for manual local checks; optional "all buffs up!"
  confirmation.

### Buff Check — PallyPower integration

- When PallyPower is running and paladins in the group have assignments, each
  player is checked against their **assigned** blessings and the report names the
  exact missing blessing ("Missing Blessing of Kings: Player1").
- Greater and normal blessing versions both satisfy an assignment.
- Only assignments from paladins actually in the group are honored, so stale
  assignments from an absent paladin can't generate false nags.
- Reads PallyPower's own runtime tables (`ClassID` / `Spells` / `GSpells`), so the
  mapping stays correct across PallyPower versions and localized clients.
- Graceful fallback to the generic "any blessing" check when PallyPower is absent,
  unconfigured, or the toggle is off.

### Auto Logger — Advanced Combat Logging guard

- Verifies the `advancedCombatLogging` CVar **on login** and again **before combat
  logging starts in a raid**, re-enabling it with a chat notice if something turned
  it off. Warcraft Logs uploads are incomplete without it.
- New settings checkbox and live CVar status display in the panel.
- Fixed a local variable shadowing the global `type` function in instance
  detection.

### Mail & Trade Logger — duplicate entries on bulk mail pulls

- **Root cause 1**: the take hooks logged on every *attempt*. Bulk-pull addons
  retry the same slot until the server responds, producing one log entry per retry.
- **Root cause 2**: mail data came from a snapshot cache refreshed 0.1s after
  `MAIL_INBOX_UPDATE`. Mail deletion shifts inbox indices, so takes during bulk
  pulls read stale cache entries and logged the wrong mail's data.
- Hooks now read the inbox **live** at take time, with a per-slot dedupe
  fingerprint that resets whenever the inbox actually changes — so twelve
  identical mails from your bank alt still log as twelve entries, but retries of
  the same take are suppressed.
- `AutoLootMailItem` is now hooked, so the client's "Open All Mail" button pulls
  are logged. Previously they were silently missing.

### Whisper Logs — correct Warcraft Logs partition

- URLs pointed at `classic.warcraftlogs.com`, the old 2021 TBC progression era.
  Anniversary realms live on `fresh.warcraftlogs.com`.
- Entries already saved from older versions are migrated automatically on login.

### Performance pass

- **Keyword Monitor**: result rows are pooled and reused. Previously every row was
  recreated once per second while the window was open — WoW never garbage-collects
  frames, so this leaked memory permanently.
- **Whisper Logs**: entry rows pooled and reused instead of recreated on every
  whisper or refresh.
- **Mail Logger**: inbox re-caching uses a single debounced timer instead of
  creating a new frame on every `MAIL_INBOX_UPDATE` event.
- **Debuff Tracker**: target debuff scanning uses precomputed name/spellID lookup
  tables instead of nested linear searches. This runs 5× per second.
- **Core**: the module color table is hoisted out of the print functions; it was
  being rebuilt on every chat message.

### Housekeeping

- Fixed the unknown-command hint pointing at `/wm`, which was never registered.
- Corrected module version markers and the theme coverage module count.

---

## 2.7 and earlier

See the version history in `README.md` for releases prior to 2.8.
