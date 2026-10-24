Post Issues here - https://github.com/netwalker0099/watchingmachine/issues
Please include your full LUA error output.

# Watching Machine

**Comprehensive Monitoring Suite for WoW TBC Classic Anniversary**

Version 3.48 | Author: Robert | Interface 20506 (TBC Anniversary patch 2.5.6)

## Overview

Watching Machine is one addon made of 25 modules for raiding, guilds and
logging, built for The Burning Crusade Classic Anniversary Edition (patch
2.5.6). Everything is reached from one dashboard (`/wmachine`). Each module
switches on and off **per character**, keeps its own settings for each
character, and is explained in a **guided setup** the first time you log
in.

**Raid**
- **Buff Check** and **Debuff Tracker**: ready-check buff audits, boss
  debuff tracking with alerts and encounter callouts.
- **Class Tools**: per-class warnings and buttons (consumables, mana
  potions and runes, warlock stones and demons, mage portals, shaman
  totem sets, paladin auras) and a **swing timer**.
- **Aura Range**: an alert when you leave a raid aura or totem's range.
- **ArmorySnap** and **GearScore**: raid gear and talent snapshots, and
  gear scores on tooltips, the character sheet and for your group.
- **Loot Browser**: every boss's loot, crafting, reputation and PvP
  rewards, and **collections** (badge vendors, mounts, companions, world
  epics, events), with your own lists and best-in-slot, fast search and
  "drops from" tooltips (Classic and TBC; Wrath ready).
- **Attunements**: every raid attunement and key, per character, with a
  guild survey.
- **World Timers**: layers, Terokkar towers, dailies, world buffs and the
  Darkmoon Faire, with map pins.
- **Hazard Alerts** (GTFO-style): a sound when you stand in the bad.
- **Gear Sets** (ItemRack-style): save and swap sets, a **dressing room**,
  a slot menu on the character sheet, automatic swaps on **spec change**,
  mount or battleground, and missing-item alerts.
- **Ogri'la Helper**: remembers the Apexis Relic sequence.

**Guild & Social**
- **Guild Invite**, **Recruiting Tool**, **PvP Enemy Tracker** (with guild
  sync), **Chat Filter**, **Keyword Monitor**, **Services Parser** and
  **WarcraftLogs Lookup**.

**Logging**
- **Auto Logger** (chat and combat logs), **Mail & Trade Logger**,
  **Instance Tracker** (lockouts and a log of every run), **Battlegrounds
  & Arenas**, **Your Characters** (every alt's gold, gear, bags, bank and
  lockouts, with a search across them) and **Crit Tracker**.

## Getting started: setup and characters

### First login on a character
Every module starts **off** on a new character, and a welcome window asks how
you'd like to set up:

- **Guided setup**: a page per module. Each page explains what the module
  does and how it works, has a switch to turn it on for this character, and
  its main settings with an explanation of each (for Class Tools: your own
  class's tools one by one, e.g. a warlock's potion and rune warnings and the
  armour and minion buttons). Back and Next move through the pages; nothing
  is final.
- **Quick setup**: one checklist of every module with presets (*Raiding*,
  *Guild officer*, *Everything*, *Nothing*).
- **Copy another character**: its modules and settings.
- **Later**: everything stays off until you run `/wmachine setup`.

A character that used Watching Machine before this version keeps every
module it had on, and is offered the setup once.

### Per character
- **Which modules are on** is per character: the switch on each dashboard
  card turns a module on or off for the character you're playing. A module
  that's off isn't started at all.
- **Settings are per character too.** The first time a character logs in
  after updating, it starts from the settings you had before.
- **Shared between your characters:** data that's about all of them, such as
  Your Characters, the instance and battleground logs, the PvP enemy list,
  world timers, Loot Browser lists, crit records, gear sets (each character's
  own) and the mail and trade log. ArmorySnap's saved data stays exactly as
  the standalone ArmorySnap addon uses it.
- **Parts of a module** follow it: the class tools (general, warlock, mage,
  shaman, paladin) and the swing timer are on only while Class Tools is.
- **Working together:** some modules add to each other when both are on, and
  the setup says so (e.g. Gear Sets says a missing item is in your bank when
  Your Characters is on).

`/wmachine setup` (or `/wmachine resetup`, or the dashboard's **Setup**
button) runs the setup again: everything you have on stays ticked and every
setting keeps its value unless you change it during the setup. `setup quick`
and `setup guided` go straight to one.

## Raid

### Buff Check
Full raid buff audit that runs automatically on every ready check.
- **You start the ready check** → missing buffs are announced to raid/party chat ("Missing Fortitude: Player1, Player2")
- **Someone else starts it** → the same report prints locally where only you can see it
- Tracked buffs (TBC): Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings (any), Divine Spirit, Shadow Protection, Food Buff (Well Fed or Enlightened — on by default), Flasks, Battle Elixirs, Guardian Elixirs — each individually toggleable
- Elixir checks know the TBC rules: a flask satisfies both the Battle and Guardian elixir slots
- **PallyPower integration**: when PallyPower is running and paladins in your group have assignments, each player is checked against their *assigned* blessings and the report names the exact missing blessing ("Missing Blessing of Kings: Player1"); greater and normal versions both count; falls back to the generic "any blessing" check when PallyPower is absent or unconfigured
- **Single-target assignments override correctly**: a player with a single-target assignment (e.g. a feral tank assigned single Might) is *not* expected to have that paladin's class-wide blessing (Salvation) — but still owes class blessings from the *other* paladins
- Class buffs are only checked when the providing class is actually in the group (no priest = no Fortitude nag)
- Only classes a buff applies to are checked (rogues aren't flagged for missing Intellect)
- Offline and dead players are skipped (listed separately in the local report)
- Long reports are split to respect the chat message length cap
- "Run Check Now" button for manual local checks any time
- Optional "all buffs up!" confirmation message

### Debuff Tracker
Visual raid debuff monitoring with auto-detection and raid alerts.
- Tracks important debuffs on your target with priority awareness
- Shows visual indicators (green=present, red=missing, yellow=suboptimal)
- Per-debuff selection: choose exactly which debuffs to track per category
- **Raid Auto-Detection**: Scans raid roster for classes and talent specs
  - Detects specs via persistent buffs (Shadowform, Moonkin Form, Leader of the Pack, Tree of Life, Trueshot Aura)
  - Three-state availability: confirmed (green), unconfirmed (yellow, class present but spec unknown), absent (red)
  - Auto-enables only debuff categories your raid can actually provide
  - Auto-disables individual debuffs when their required class/spec is missing
  - Re-scans on roster changes and every 5 seconds for spec buffs
  - Manual override available (toggle auto-detect off for full manual control)
- **Missing Debuff Raid Alerts**: Sends raid chat/warning when a tracked debuff is missing from a boss
  - Configurable delay before alerting (2-15 seconds, default 5s)
  - Configurable cooldown between repeat alerts (10-120 seconds, default 30s)
  - Uses /rw with assist, /raid without
  - Boss-only mode (on by default), alerts include expected debuff names
  - Off by default, enable in settings
- **Tracked Categories** (TBC-accurate, no WotLK abilities):
  - **Armor Reduction**: Improved Expose Armor > Expose Armor > Sunder Armor > Faerie Fire
  - **Physical Damage**: Blood Frenzy (Arms Warrior)
  - **Shadow Damage**: Shadow Weaving (Shadow Priest), Curse of Elements
  - **Spell Hit**: Misery (Shadow Priest)
  - **Fire Damage**: Improved Scorch (Fire Mage), Curse of Elements
  - **Attack Speed**: Improved Thunder Clap, Thunder Clap
  - **AP Reduction**: Demoralizing Shout/Roar, Curse of Weakness
  - **Healing Debuff**: Mortal Strike, Wound Poison, Aimed Shot (MM Hunter)
  - **Hunter's Mark**
- **False-positive filtering** (v3.1):
  - **NPC-ID identity**: mobs are identified by the npcID embedded in their GUID, not their display name — so same-named mobs in different places are distinguishable
  - **Health-pool floor** (default 150k, slider): raid trash is level 72–73 elite exactly like real bosses, so level alone can't separate them; health pool can. Stops Magtheridon's Hellfire Warders and similar trash from registering as bosses
  - **Focus target tracking**: on multi-boss fights (Fathom-Lord Karathress, Illidari Council) the addon watches which mob is absorbing the most raid damage in a rolling 6-second window and only alerts for that one. Target an add the raid is ignoring (a Fathom-Guard that isn't next in the kill order) and it stays silent. Adapts automatically to any kill order — swap to burning Karathress directly and alerts follow, no configuration
  - **Manual exclusions**: `/wmachine exclude` with a mob targeted permanently stops that creature type triggering boss alerts (keyed on npcID, so same-named mobs elsewhere are unaffected)
  - **`/wmachine whyboss`** diagnostic prints exactly how the tracker sees your target: npcID, classification, level, health vs. the floor, exclusion state, current raid focus, and whether it would alert
- **Illidan Doom warning** (v3.2): raid-warns **CAST DOOM NOW** when Illidan Stormrage hits 68%, so warlocks land Curse of Doom before he lifts off at 65%
  - Toggle in Debuff Tracker settings (on by default); fires once per pull
  - Sent by the raid leader (or assistants if "Assistants can announce" is on) so multiple addon users don't duplicate it
- **Illidan Shear monitor**: calls out Shear on the main tank during Illidan's ground phases
  - Shear cuts the tank's max health by ~60% and can be dodged/parried/blocked, so damage meters miss it: the hit is a max-health debuff, and an avoided Shear deals no damage at all
  - Watches every subevent a Shear can produce (cast start, damage, aura applied/refreshed, and all avoidance results), plus a raid-aura sweep as a backup if a combat-log event is dropped
  - Matches by spell ID *and* localized spell name, so an unexpected ID still registers
  - One call per cast — the cast/aura/damage events a single Shear generates are deduped
  - Announces hits to raid chat by default; avoided Shears are counted but not announced (toggleable), with a channel picker and optional throttle
  - Optional local cast warning (~1.5s window to use Shield Block / Holy Shield)
  - Per-pull summary on combat end: total, hit vs avoided, per-tank breakdown, and avoidance types
  - `/wmachine shear` for status and tallies, `/wmachine shear on|off` to toggle
- **Black Temple shadow resist gear check**: warns if you're still in SR gear after Mother Shahraz
  - Arms when Mother Shahraz dies, and also the moment you engage a Grand Promenade pull (Shadowmoon Reaver, Promenade Sentinel, Illidari Archon/Assassin/Battle-mage/Blood Lord), so a mid-raid `/reload` still works
  - Reads **equipped gear only**, so Shadow Protection and Shadow Resistance Aura can't cause a false warning
  - Configurable threshold (default 60 gear SR) so an odd piece with incidental resistance is ignored
  - Warns you locally with a screen flash and sound by default; optional Say/Party/Raid/`/rw` announce. Unlike the other callouts this is **not** limited to the raid leader, since it's about your own gear
  - One warning per pull (20s cooldown), `/wmachine srcheck` to see exactly what it detects per slot
  - Counts the item's own resistance plus socketed gems (Void Sphere's +4 Resist All), enchants and active socket bonuses
  - **Raid-wide check** for the raid leader and assistants: on every pull of a Promenade robot or Illidari pack after Mother it lists every raider still in SR gear, on screen and optionally to Say/Party/Raid/`/rw`. Raiders running Watching Machine report their own gear; everyone else is inspected, which needs them within inspect range (anyone out of range is listed as not checked). `/wmachine srraid` or the **Check Raid** button runs it any time
- **Encounter callouts** (Doom warning, Shear monitor, SR check) are the *Encounter Callouts* section of Debuff Tracker settings; `/wmachine encounters` opens the panel scrolled to it
- Configurable: show only in raid, show only on boss, categories to track
- Draggable frame, lockable position

### Class Tools
Detects the class you're playing and surfaces the tools built for it.

- **Class section in the dashboard** (`/wmachine class`) with a **tab per class**. A tab appears only once something has been built for that class, so there are no empty tabs for work that hasn't been done.
- **Your own class is selected when the panel opens**, and is always offered as a tab even before it has tools — so the panel explains itself rather than looking broken.
- Per-feature on/off switches, **saved per class**, so the same feature key on two classes stays independent.
- This ships as the framework. Class features register into it and appear automatically:

```lua
local CT = WM.modules.ClassTools
CT:RegisterFeature("SHAMAN", {
    key     = "totemReminder",
    name    = "Totem reminder",
    desc    = "Warn when a totem drops off.",
    default = false,
    onToggle = function(enabled) --[[ ... ]] end,
})
```

  A feature then just asks `CT:IsEnabled("SHAMAN", "totemReminder")`, or
  `CT:IsActiveForPlayer("totemReminder")` for the class being played.

- **Shared warning frame.** Features don't each build their own alert. They
  call `CT:SetAlert(key, text, icon)` and `CT:ClearAlert(key)`; Class Tools
  collects everything into one movable *CHECK YOURSELF* frame (up to six lines
  at once) that hides itself the moment the last warning clears. Registered
  monitors run on a shared one-second tick, so twenty checks cost one timer.
- Warning frame options live at the bottom of the panel: sound on a new
  warning, lock in place, reset position, and **Show example** — which puts
  two dummy lines up for six seconds so you can find and position the frame
  without waiting for a real warning.
- **Warning sounds** (a section below): a sound for each warning of General
  and your class:
  - **General:** no flask or elixirs, no food buff, no weapon oil / stone
  - **Mage:** armor missing
  - **Warlock:** Fel / Demon Armor, Demonic Sacrifice, Soul Link
  - **Paladin:** Righteous Fury

  Each one is *Shared warning sound* (the default: the sound above, if it's
  on), one of the addon or game sounds, or **None** (silent). Picking a
  sound plays it. They use the *Warning sounds play on* channel from the
  General tab.

#### Flyout buttons (all classes)
The mage, warlock and shaman buttons share one flyout engine (`Modules/ClassFlyout.lua`)
and a set of options in Class Tools > **General**:

- **Flyout buttons open**: *On hover* (default) or *On click*. In click mode
  a click opens or closes the flyout, and picking a spell closes it
- **Dock flyout buttons together**: your class's buttons line up in one
  group that moves together. Drag any of them to move the group
- **Docked layout**: row left-to-right / right-to-left, or column down / up
- **Lock flyout buttons**: no dragging (the whole group when docked)
- Every group's direction includes **Hidden** to leave it out, and the
  direction options are **dropdowns**
- Nothing opens, moves or re-docks in combat; changes made in combat apply
  when it ends

#### General
Consumable checks that apply to everyone, shown under a **General** tab that
always sits first.

- **Flask or elixirs** (a flask, or a battle plus a guardian elixir), **food buff** (Well Fed, or Enlightened from Skullfish Soup) and **weapon enchant** checks, running
  only while you're inside a raid instance — no nagging in town or while
  questing
- **25-man only by default**, with a tick to extend it to 10-mans
- Wording follows your class: casters are told about **wizard oil**, melee
  about **sharpening stones / weightstones**
- The off hand is checked only when a real **weapon** is equipped there —
  shields and held items share the slot but can't take an oil
- **Mana potion / rune warnings** (mana users, in combat):
  - **Use a mana potion** once your mana is 3000 below max and a potion is
    ready. It names the potion and prefers the free raid-zone ones where
    they work.
  - **Use a Dark / Demonic Rune** once you're 1500 below and no potion is
    ready, either on cooldown or none left. Not below 35% health.
  - Both thresholds are adjustable. A warning stays up until you're 500 back
    under its threshold, so it doesn't flicker as mana regenerates.
  - **Sounds:** each warning plays its own sound once when it appears: the
    addon's **potion** and **rune** sounds by default. Pick another from a
    dropdown (the other addon sound, raid warning, ready check, alarm clock,
    PvP flag, or None for silent); picking one plays it, so you can hear it.
    *Warning sounds play on* Master (default, heard with game sound turned
    down), Sound effects or Dialog
- `/wmachine consumes` prints exactly what the checks currently see
- **Swing timer**: a bar per hand showing the time to your next swing, for
  warriors, rogues, Retribution paladins and Enhancement shamans (spec read
  from your talents), and an **Auto Shot** bar for hunters
  - A white line moves left to right as the swing comes round; the fill
    turns red in the last stretch, which is your **latency** (drawn in red at
    the end of the bar)
  - Follows TBC's rules: Heroic Strike / Cleave replace the swing; finishing
    a cast (Slam, Lightning Bolt, a heal) restarts it; instants (Stormstrike,
    shocks) don't; haste such as Flurry rescales it; **parrying** takes 40%
    of your swing off (never below 20% left); a weapon swap restarts it;
    Windfury extra attacks don't count as a new swing
  - **Hunters**: the Auto Shot bar is green while a Steady Shot is safe to
    start, red where starting one would delay (clip) the next shot (cast time
    plus latency before the wind-up), and yellow for the final half-second
    wind-up, when moving delays the shot
  - **Enhancement weapon sync**: you want the off hand to land just after
    the main hand (Windfury Weapon's 3s cooldown is shared, so the main hand
    should get the proc, and close hits share one Flurry charge). A blue mark
    on the main-hand bar shows when to press the sync macro
    (`/cleartarget`, `/targetlasttarget`, `/startattack`). It stops and
    restarts your attack, which puts an off hand that's past halfway back to
    halfway. The mark sits at *off-hand speed ÷ 2 − lag − latency* before
    the main-hand swing, turns green with **SYNC NOW** when it's time, and a
    line under the bars says *In sync*, *Off hand first* or *Out of sync*.
    *Off hand lands after by* sets the lag (0.15s default). Sync only holds
    with equal weapon speeds; the timer says so when they differ.
    *SYNC NOW sound* (off by default) plays a sound as the prompt comes up
  - **Resizable**: drag the grip in its bottom-right corner while it's
    unlocked (right for wider, down for taller bars), or pick *Swing timer
    width* (100–600) and *bar height* (8–40) in Class Tools > General
  - Options: *Swing timer*, *for every class and spec*, *Shaman weapon sync
    mark*, *Off hand lands after by*, width, bar height, *Lock the swing
    timer* (no moving or resizing). `/wmachine swing` shows it for 10 seconds
    so you can move and resize it; `/wmachine swing reset` puts back the
    default place and size

Flask detection matches on substring, so `Unstable Flask of the Beast` and
`Unstable Flask of the Sorcerer` count alongside the standard flasks.

#### Warlock
- **Armor check** — warns when Fel Armor, Demon Armor or Demon Skin has
  fallen off
- **Demonic Sacrifice** — only nags when you've actually taken the talent and
  have no demon out. A warlock with a pet summoned is making a choice, not
  making a mistake, so no warning is raised
- **Soul Link** — warns only when talented, with a living pet, and with no
  sacrifice buff up. A sacrificed warlock is never nagged about Soul Link
- **Soulstone timers** — scans the group for Soulstone Resurrection and reads
  the real expiry from the buff itself, so it works regardless of which
  warlock cast it or whether you saw the cast. `/wmachine soulstone` lists
  who's stoned and for how long
- Talents are cached for five seconds for speed, and the cache is dropped
  immediately on a respec (`CHARACTER_POINTS_CHANGED` / `PLAYER_TALENT_UPDATE`)
  so the checks never act on an old build
- **Warlock button**: a flyout button showing the warlock class crest, with
  three groups (nearest first), each with its own direction or Hidden:
  - **Demons**: Felguard (only if talented), Succubus, Imp, Felhunter,
    Voidwalker
  - **Armors**: Fel Armor, Demon Armor, Demon Skin (highest rank)
  - **Stones & rituals**: Soulwell (Ritual of Souls), Ritual of Summoning,
    Healthstone, Soulstone (highest rank)

  Icons for spells that use a Soul Shard show your **shard count**, updated
  as your bags change. Defaults: demons left, armors up, stones right

#### Mage
- **Armor check** — warns when Molten, Mage, Ice or Frost Armor is missing
- **Portal / teleport button**: a draggable portal icon that expands on
  hover into an **icon for every portal and teleport you know**, each with
  its own spell icon. Hover an icon for the spell's tooltip; click to cast.
  Built from your spellbook, so it only ever shows what you can actually
  cast, and refreshes when you learn a new one
- **Expansion direction**: *Portals expand* and *Teleports expand* in the
  Mage tab, each Up / Right / Down / Left / **Hidden** (defaults: portals
  left, teleports up). If both point the same way, they form one line,
  portals first with the teleports continuing on the end
- The spellbook scan derives the `Teleport:` / `Portal:` prefixes from the
  client's own spell names, so it works on non-English clients
- The flyout deliberately **won't expand in combat**: its buttons are secure
  frames that can't be reconfigured mid-fight, and portals aren't castable in
  combat anyway
- **Mage utility button**: a second draggable button showing the mage class
  crest. On hover it expands into three groups, each ordered highest level
  first so the best is nearest the button:
  - **Mana gems**: Emerald, Ruby, Citrine, Jade, Agate (those you know)
  - **Armors**: Molten, Mage, Ice, Frost, one icon each
  - **Food & water**: Ritual of Refreshment (table), Conjure Water, Conjure
    Food

  Ranked spells show once and cast your highest rank. Each group has its own
  direction (*Mana gems / Armors / Food & water expand*; defaults left, up,
  right). Groups sharing a direction form one line in that order.
- Opening on hover or click, docking and locking are shared by every
  class's flyout buttons: see **Flyout buttons** under Class Tools
- `/wmachine portals` lists what the scan found

#### Shaman
- **Totem button**: one button that drops a whole **totem set**, one totem
  per click, in the order **Air, Water, Earth, then Fire** (fire is always
  last)
  - **Hover** the button to open your sets and click one to use it. Its
    icon and label show the set in use, and the tooltip lists its totems
  - **Click** to drop the next totem. Underneath it's a `/castsequence`
    macro, since the game allows one cast per click
  - The sequence **starts again from Air** when all your totems are gone
    (destroyed or expired; TBC has no Totemic Recall), when combat ends, or
    on **Ctrl-click**
  - **Shift-drag** moves it (a plain press casts). **Right-click** opens the
    set editor
- **Four sets**, premade as **Melee** (Windfury / Mana Spring / Strength of
  Earth / Searing), **Caster** (Wrath of Air / Mana Spring / Stoneskin /
  Totem of Wrath), **Healer** (Wrath of Air / Healing Stream / Stoneskin /
  Searing) and **Tremor** (Windfury / Mana Spring / Tremor / Searing)
  - Each premade element is **Auto**: the first totem in its list that you
    know, so a set keeps working as you level (Searing until you have Totem
    of Wrath, Grace of Air until Windfury)
- **Totem Sets editor** (`/wmachine totems`, right-click the button, or the
  Class Tools card's tools menu): rename a set and choose each element's
  totem, Auto, or None to skip that element. *Restore premades* puts all
  four back
- *Totem sets expand* sets the flyout's direction (or Hidden). Changes made
  in combat apply when it ends; dropping a set works in combat

#### Paladin
- **Righteous Fury check** — warns when Righteous Fury is missing, the same
  way the mage and warlock armor checks do. Only for **Protection**
  paladins: most talent points in Protection, or Holy Shield / Avenger's
  Shield learned. Holy and Retribution paladins are never nagged, and
  nothing shows before you've learned the spell or while you're dead

### Aura Range
Visual and audio alerts when you drift out of range of party auras and shaman totems.
- **Watches your own buffs**: party auras (Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin auras) and totem buffs (Strength of Earth, Grace of Air, Wrath of Air, Totem of Wrath, Mana Spring, and more) drop off the moment you leave their radius — the module catches the drop instantly via UNIT_AURA, no polling
- **Movable on-screen alert** with pulsing red border listing exactly which auras you've walked away from, plus an optional raid-warning sound
- Alert clears the moment you step back into range
- **False-alarm guards**: no alerts while dead (death wipes buffs), when the provider (moonkin/shaman/etc.) is dead or gone, on zone transitions, or after leaving a group; stale alerts auto-expire (configurable 5–30s) to cover totems that simply expired or were destroyed
- Per-aura toggles, sound toggle, lockable alert frame, test button

### ArmorySnap
Passive raid gear & talent archive (integrated from the standalone ArmorySnap addon, keeping its fast v1.2 scanner).
- **Passively snapshots every raid member's gear** while you're in a raid instance — enchants and gems included (TBC item links embed both)
- **Fast event-chained scanning**: the next inspect fires the moment the previous one resolves; a full 25-man with everyone in range captures in roughly 15–20 seconds
- Out-of-range members retried every 15 seconds; new joiners picked up within 10 seconds
- **Paper-doll browser**: pick a snapshot, pick a member, see their gear laid out like the character frame with native tooltips; Shift-click to link items
- Talent tree capture (full detail for yourself; tree names/icons for inspected players — the Anniversary API doesn't expose inspected point counts to any addon)
- Enchant/gem count summary per character
- **GearScore** (3.38): every captured member's score, from the GearScore module's formula. It shows in the member list ("GS 1650"), with average item level on the paper doll, and the snapshot's raid average next to *Raid Members*. Scores are saved with the snapshot once every item is known, and older snapshots are scored when you open them
- Zone-aware sessions labeled timestamp + zone; snapshots retained 1/7/14/30 days (dropdown)
- Manual snapshots via `/as snap [label]`; optional scanning in 5-man/world groups
- **Auto-scan** checkbox (or `/as auto`) turns automatic raid scanning off without disabling the module; manual snapshots still work
- **Migrates your existing archive**: uses the same `ArmorySnapDB` saved variable as the standalone addon; if the standalone addon is still enabled, the module stands down and tells you (disable one or the other)
- Keeps the standalone `/as` slash commands; also `/wmachine armory`

### World Timers
Open-world timers for TBC, kept per layer (Raid group; `/wmachine timers`).

- **Layers:** which layer you're on, found by targeting or mousing over
  A'dal, Nutral, Minalei or Innkeeper Haelthol in Shattrath, and numbered the
  way Nova World Buffs numbers them. Other Outland zones (and the two capitals) are
  then tied to that layer as you target things there, until you join a group
  (which can move you) or a zone shows signs of a different layer
- **Terokkar Forest towers:** when the Spirit Towers reset, per layer and
  with the controlling faction, read from the zone's timer (corrected for
  its slow clock). A chat warning 10 minutes before
- **Dailies:** today's dungeon (Nether-Stalker Mah'duun), heroic (Wind
  Trader Zhareem) and PvP (Call to Arms) dailies, from accepting them, or
  from Nova World Buffs users
- **Darkmoon Faire:** whether it's up, where (Terokkar / Elwynn / Mulgore by
  month), when it opens or closes and where it goes next; plus **your Sayge
  fortune cooldown** (4 hours of play) per character
- **Classic world buffs:** Rend, Onyxia, Nefarian (from the NPC's yell and
  the buff landing on you), with warnings at 30, 15, 10, 5 and 1 minutes and
  when one can drop again, and NPC-killed notices. Rare on TBC
- **Songflowers:** a pick at one of Felwood's ten flowers (yours, or a player
  you'd already seen) starts its 25-minute respawn timer
- **Nova World Buffs users:** their shared layers, tower timers, dailies, world
  buffs and Songflowers (guild, group and nearby yells) are merged in, checked
  the way Nova checks them. Watching Machine only listens
- **World map pins:** the Faire on its zone and continent maps, the
  Terokkar towers (Terokkar and Shattrath), today's dungeon and heroic
  dailies in Shattrath, and all ten Songflowers in Felwood, each with its
  timer. Hover a pin for details (every layer's tower reset, which layer a
  Songflower pick was on). The timers tick while the map is open
- **Guild layers:** which layer each guild member running Nova World Buffs
  is on (in their numbering), shown under the timers for 30 minutes after
  they last said
- **NPC walking (Horde):** stand by the throne in Orgrimmar with Runthak's
  or Saurfang's window open after the head is handed in. When they walk off
  to the gate, the window closes by itself and you get a chat line and a
  sound (pick it, or None). Closes you make (the X, Goodbye, Escape, a trade)
  and moving don't count. Guild members' Nova walking notices show too
- `/wmachine wb` prints the short timers; `/wmachine wb guild` (or party /
  raid) sends them to that channel

### Loot Browser
What every dungeon and raid boss drops, what each profession makes,
reputation rewards, PvP gear and collections (Raid group; `/wmachine loot`, also
`/wmachine atlas`).

- **Show:** *Dungeons & Raids*, *Crafting*, *Factions*, *PvP*, *Collections*
  or *My Lists*, for the expansion picked at the top
- **Collections** (3.47): the Badge of Justice vendor (and its Phase 4 and 5
  stock), the Sunmote vendor, world epics, mounts, companions, tabards,
  legendaries, the Classic item sets (tier, dungeon, Zul'Gurub, Ahn'Qiraj
  and others) and the world events (Darkmoon Faire, the holidays, Brewfest,
  invasions). Item tooltips say "Also in:" for these
- **Search** (3.40): type three letters (or press Enter) to find items by
  name across every page: drops, faction and PvP rewards, set pieces and
  crafted items. Results come sorted best quality first, split into Drops /
  Reputation / PvP / Crafted / Collections, each saying where it's from.
  Matching instances and bosses are listed too; click one to open it.
  Escape or *Clear* to go back. Fast (3.47): item names are remembered
  between sessions for all your characters, so a search never waits on the
  server; names the game hasn't shown you yet are learnt in the background
  a small batch at a time, and the results grow as matching ones arrive
- **My Lists** (3.39): your own favourite lists and a best-in-slot list for
  each spec of your class.
  - **Alt-click** any item (or set piece, or recipe) to add it to your list
    (the list you last opened under My Lists).
  - **Right-click** for a menu that ticks it in or out of any list, or
    marks it BiS for any of your specs.
  - Items in a list get a star; BiS items get an orange "BiS".
  - Each page is sorted by slot (Head, Neck, ...), and shows whether you
    have the item (equipped, in your bags or bank) and where it's from.
  - Make, rename and delete lists from the bar above. Lists and BiS marks
    are shared across your characters

- **Classic and The Burning Crusade:** every dungeon and raid, boss by boss,
  plus trash, quest and event pages, keys, and the tier sets. The
  instances come in level order, raids after dungeons, with the TBC phase
  each raid opened in
- **Normal / Heroic:** switch between a boss's normal and heroic loot
- **Your faction's items** where they differ (Onyxia's and Nefarian's heads,
  AQ rewards)
- **Set pages:** one line per set, its name and an icon per piece (hover a
  piece for its tooltip). *Sets: my class only* (on) shows just your
  class's; off, every class's sets are grouped under the class name
- **Crafting:** every profession's recipes by section (Flasks, Transmutes,
  Armor - Head...), with plate / mail / leather lists where a section has
  them. Each shows what it makes and the skill it needs; hover for the
  reagents and the recipe that teaches it
- **Factions:** what each faction sells at each standing (yours, and your
  side's: Thrallmar or Honor Hold). Faction-only rewards show only to
  that faction
- **PvP:** battleground rewards, honor and arena seasons (sets, weapons,
  off-pieces), world PvP vendors, mounts and insignia
- **Items:** icon, name in its quality colour, slot and type. Hover for the
  full tooltip; shift-click links it in chat, ctrl-click tries it on
- **Item tooltips everywhere** (bags, chat links, the auction house, the
  loot window) say where an item comes from: *Drops from* (each boss and
  its instance, "Heroic" when only the heroic version drops it),
  *Reputation reward* (faction and standing), *PvP reward* and *Made by*
  (profession and skill). Up to three of each, then "and N more". Your
  BiS marks and lists come first ("Your BiS: Fire").
  *Item tooltips* in the window turns it off
- **Opens on the instance you're in**, and remembers the last one per
  expansion. The window is resizable; the loot uses two columns when wide
- **Wrath of the Lich King:** switches on by itself on a Wrath client, with
  Wrath's crafting (Inscription included), factions and PvP, and the
  Wrath holiday bosses (Ahune, the Headless Horseman). The Wrath dungeon
  and raid tables are still to come
- Only item IDs are stored; names, icons and stats come from the game, so
  the first look at a page can show "Item 12345" for a moment while the
  client fetches them

### GearScore
A gear score and average item level for you and every player you mouse over
(Raid group; `/wmachine gs`, or `/gs` when no other GearScore addon has it).

- **Same numbers as GearScoreTBCClassic:** the GearScoreLite formula tuned
  for TBC. It uses each item's level, quality and slot weight; enchants add
  5% and gems 5 each; hunters' ranged weapons count more and melee less.
  Colours run grey, white, green, blue, purple, orange
- **Player tooltips:** "GearScore: 1650  iLvl: 112". Players you mouse over
  are inspected automatically: out of combat, within inspect range, one at
  a time, never while your own inspect window is open. Scores are kept by
  name for a week
- **Item tooltips:** the item's score. *Item tooltip details* adds its base
  score, enchant and gem bonuses (or what's missing), and what equipping it
  would change for you (against the weaker ring or trinket, both hands for
  a two-hander)
- **Character and inspect frames:** your score and average item level, and
  the inspected player's. `/wmachine gs unlock` to drag it, `lock` to save,
  `reset` to put it back
- **Group list:** everyone in your party or raid, highest first, with when
  they were last seen. *Scan group* inspects whoever's missing; *Send to
  group* posts the list. `/wmachine gs report` prints it
- **With another GearScore addon** (GearScoreTBCClassic, GearScoreLite,
  TacoTip) loaded, its tooltips and character frame score are left to it;
  the group list still works

### Attunements
Every raid attunement and key, for each of your characters (Raid group;
`/wmachine attune`).

- **What's tracked (TBC):**
  - **Raids:** Karazhan, Nightbane, Serpentshrine Cavern, The Eye, Mount
    Hyjal, Black Temple.
  - **Dungeon keys:** Shattered Halls, Shadow Labyrinth, Arcatraz, Black
    Morass.
  - **Heroic keys:** the five faction keys.
  - **Other:** Ogri'la, Netherwing.
  - **Classic:** MC, Onyxia, BWL, Naxxramas and the Classic keys (*Classic
    too*).
- **Read from the game:** finished quests, quests in your log, items in
  your bags and bank, your level and reputation, and other attunements a
  chain needs. Kills and conversations the game can't report count as done
  once anything after them is
- **The steps:** green done, yellow what to do next, grey later, each with
  its zone; hover for the quest's level and group size, the creature, the
  item, or your reputation so far
- **Patch-aware:** the heroic keys follow the client: Revered on 2.5.6,
  Honored and the new keys from 2.5.7
- **My characters:** every alt's progress for the selected attunement, and
  *Attuned:* / *In progress:* lines on Your Characters tooltips
- **Guild:** *Survey guild* asks guild members running Watching Machine for
  their progress (its own addon message; one answer per 30 seconds each)
- **Chat:** "Attuned: Karazhan!" when you finish one (*Say when done*)

### Hazard Alerts
A sound the moment you're standing in something that hurts (Raid group;
`/wmachine gtfo`).

- **Four alerts, each with its own sound:**
  - **High damage:** move now.
  - **Low damage:** you're taking damage you could avoid.
  - **Fail:** you failed a mechanic.
  - **Friendly fire:** your own spell is hurting your group.
- **What it knows:** about 265 hazards in TBC raids and dungeons (void
  zones, fire, poison clouds, cleaves...) and some Classic ones, plus lava,
  slime and fire on the ground, drowning and fatigue
- **Smart about it:**
  - Tanks hear the tank version, or nothing where standing in it is their
    job. You count as a tank in Righteous Fury, Bear Form or Defensive
    Stance, or if you're marked main tank.
  - Heroics can use a different alert.
  - Some hazards only count from the creature that casts them.
  - Hits under 2% of your health, and old content far below your level,
    stay quiet (unless *Alert in low-level content too*).
- **Sounds:** pick one per alert (any addon or game sound, or None) and the
  channel; *Test* buttons; optional on-screen warning
- **Recent alerts** listed in the window; `/wmachine gtfo mute <spell ID>`
  silences one you don't care about (`unmute` to undo)

### Ogri'la Helper
Remembers the Apexis Relic sequence for you (Raid group; `/wmachine ogri`).
Game facts compiled with the help of Ogri'Lazy's research; the code is our own.

- **Opens by itself** when you start an Apexis Relic or the Apexis Monument
  in Ogri'la
- **Record the sequence:** click the green, yellow, blue and red buttons
  (or press **G**, **Y**, **B**, **R**) as the relic lights them up. Up to
  16 colours, in two rows
- **Then touch the beams:** the next colour is ringed, and each beam you
  touch moves it on by itself. A wrong beam (the relic's Reprisal hitting
  you) puts the step back
- **Fix mistakes:** left-click a colour to remove it, right-click to remove
  it and everything after; *Clear* starts again. A finished sequence
  starts over on the next click, ready for the next round
- **Shows** your Apexis Shards and Crystals and your longest sequence so far
- **Options** (`/wmachine ogri options`): open at relics (the dashboard
  switch), help tooltips, hotkeys on or off, your own keys, the keys on
  the buttons, freeing the keys in combat, and the helper's size. Drag the
  helper to move it

### Gear Sets
Save and swap gear sets, ItemRack-style (Raid group; `/wmachine gear`). Our
own code, written from the ground up for reliability.

- **Sets:** *New set* takes what you're wearing; tick the slots the set
  changes (the rest are left alone, and a ticked empty slot means "take it
  off"). Equip from the window, the macro `/wmachine gear equip <name>`, or
  *Undo last swap* to put back what you wore before
- **Dressing room** (3.48): the set editor shows your character wearing the
  set, with its 19 slots around it like the character sheet. Click a slot to
  choose from everything you own that fits (what you wear, your bags, the
  bank when it's open), or to take it off; right-click to leave it out of
  the set. Faded slots aren't part of the set (the model shows what you wear
  there now). Drag the model to turn it. The slots are also listed as tick
  boxes below
- **Talent spec swaps:** give a set a spec (Spec 1 or Spec 2, shown with
  its talent tree) and tick *Equip it when I switch to that spec*. Switching
  spec then puts it on by itself. *Automatic swaps* in its options turns
  every automatic swap on or off
- **Mounted and battlegrounds:** a set can go on while you're mounted or in
  battlegrounds and arenas, and what you wore before goes back on after
- **Reliable swaps:**
  - items are matched exactly (enchant, gems, random suffix, and which
    copy), so two identical trinkets or a re-enchanted piece are still found
  - every step re-reads your bags and slots, skips anything the server is
    still moving, and retries what the game refuses
  - swaps happen in place, so most sets need no free bag space; a
    two-hander takes the off hand off first (and says so if your bags are
    full); quivers and soul bags are never used for gear
  - in combat the weapons change at once and the rest goes on when combat
    ends; it also waits out casts and death
  - at the end it checks the result and says what didn't go on, and why
- **Missing items:** a chat alert names any set item that isn't on you, and
  says when it's in your bank (from Your Characters). Opening the character
  sheet shows a warning with the list, and the slots of your current set
  that are missing an item are marked red
- **Slot menu** (3.48, like ItemRack's): point at a character sheet slot
  for a row of every item that fits it, from your bags (and the bank while
  it's open); click one to swap it in. It stays while the mouse is on the
  slot or the row. Options: on hover (the default), only with Alt held, or
  off
- **The window:** every set with its icon, *wearing* / *N to change* /
  *N missing*, its spec, mounted and PvP badges; hover for the items, and
  *Equip*, *Edit* and *Delete*

## Guild & Social

### Guild Invite
Auto-invite guild members to raid when they say the trigger word.
- Responds to trigger word (default: "inv") in guild chat or whispers
- Verifies guild membership before inviting whisper requests
- Requires party/raid leader or raid assist to process invites
- Auto-converts party to raid only when a 6th member is invited (won't convert legitimate 5-man parties)
- Say "raid" or "raid convert" in party/guild to manually convert
- TBC-compatible API calls with pcall protection (safe during arena/BG transitions)
- Invite logging with timestamps

### Recruiting Tool
Automated guild recruiting system.
- Scan unguilded players by class and level range (1-70 for TBC)
- Customizable message with %GUILD% placeholder

### PvP Enemy Tracker
Track hostile players who kill you in world PvP and get proximity alerts.
- **Kill Tracking**: Automatically logs players who kill you outside battlegrounds/arenas
  - Records killer name, class, level, guild, zone, timestamp, and kill count
  - Attributes kills via last-damage-source tracking (5-second window)
  - Ignores deaths in battlegrounds and arenas
- **Proximity Detection** (5 layers):
  - Nameplate detection (NAME_PLATE_UNIT_ADDED event)
  - Periodic nameplate scan (every 1 second, 40 nameplates)
  - Mouseover detection
  - Target change detection
  - Combat log source matching
- **Alert System**:
  - Chat alerts with class-colored names, guild, and kill count
  - Sound alerts (PvP flag capture sound)
  - Screen alerts via RaidWarningFrame
  - Per-player cooldown (default 30s) to prevent spam
  - Each alert type independently toggleable
- **Kill-on-Sight List**:
  - Sorted by kill count, scrollable
  - Add manually by name or "Add Target" button
  - Hover tooltip with guild, notes, and exact kill dates
  - Per-entry remove, Clear All with confirmation
  - "Manual tracking only" mode to disable auto-logging
- **Guild Sync**: Share KOS lists with guildies running WatchingMachine
  - Real-time kill broadcasts to guild channel on every PvP death
  - Full list sync on login and on-demand (Request Sync / Send List buttons)
  - Per-reporter kill tracking with merge logic (won't echo data back)
  - Revenge announcements: guild chat message when you kill a KOS enemy reported by a guildie
  - Configurable: enable/disable, show sync messages, auto-request on login
- **KOS Leaderboard**: Compete with guildies for most KOS kills
  - 1 point per KOS-listed enemy killed, synced across guild
  - Separate leaderboard window with ranked list, bar graph, gold/silver/bronze medals
  - Three announcement modes: Off, Hourly (top 3 to guild chat), On Lead Change (new #1 alert)
  - Reset button to wipe leaderboard data
- Error-resilient: pcall-protected event handlers with auto-disable on repeated failures

### Chat Filter
Hides chat spam by phrase — e.g. **Guild Loot Run** — before you, or Keyword Monitor, ever see it.

- **Premade filters**, one tick each (off until you turn them on):
  - **GDKP**: matches `GDKP`
  - **Guild Loot Run**: matches `Guild Loot Run`
  - **Gear Carry**: matches `Gear Carry` and `Gear Carries`
- Add any number of your own phrases; a message containing one **anywhere** is hidden from every chat frame
- Matching ignores case, colour codes, item-link brackets and extra spaces. Phrases are plain text — no wildcards or patterns
- **Applied before Keyword Monitor**: a hidden message is never checked for keywords, so filtered spam can't produce matches. Both windows show this warning
- Filters public channels by default; say/yell and whispers can be ticked on
- Your own messages are never hidden
- Per-phrase and total counts of hidden messages for the session, in the window and the dashboard tools menu
- `/wmachine filter` (also `/wmachine cf`), or the dashboard card's on/off switch

### Keyword Monitor
Monitor public channels for specific keywords with duplicate detection.
- Monitor Trade, General, LFG, and other channels
- 5-minute result retention with deduplication
- Sound and chat alerts
- **Chat Filter runs first**: messages hidden by Chat Filter (module 17) are never checked for keywords; the window says so at the top

### Services Parser
Parse services channel for boost advertisements by dungeon.
- Classic dungeons: RFC, SFK, SM, Mara, LBRS, ZG, Strat
- TBC dungeons: Ramparts, Blood Furnace, Slave Pens, Underbog, Mana Tombs, Shattered Halls, Shadow Lab, Botanica, Mechanar, Arcatraz
- Separate tab for summons/portals

### Whisper Logs (WCL Lookup)
Track whispers and quickly look up players on Warcraft Logs.
- **Auto-detects your server** via GetRealmName() and injects it into WCL URLs
- **Per-player realm tracking**: Cross-server whispers and group members get their correct server in the URL, not yours
- Parses full "Player-Realm" format from whisper events and group roster
- Generates correct fresh.warcraftlogs.com URLs per region (US/EU/KR/TW/CN) — the Warcraft Logs partition for Anniversary realms; saved entries from older versions are migrated automatically
- "Scan Raid/Party" button to add all group members with correct realms
- Shows detected server in UI header, cross-server players tagged with realm name
- Click to copy URL, right-click to remove

## Logging

### Auto Logger
Automatically manages chat and combat logging.
- Enables chat logging on login
- Automatically enables combat logging in raid instances (10/25-man for TBC)
- Optional logging in 5-man dungeons
- **Advanced Combat Logging guard**: verifies the `advancedCombatLogging` CVar on login and when entering a raid, and re-enables it if it was turned off (required for complete Warcraft Logs uploads); toggleable in settings

### Mail & Trade Logger
Long-term logging of items and gold received via mail and trades.
- Logs gold, items, and auction house transactions
- Multi-character support with character selector
- Filter by Gold, Items, AH Sales, AH Buys, Expired
- Duplicate-proof bulk mail pulling (Postal-style addons and retry-spam handled)
- "Open All Mail" button pulls are logged too
- **Gold trade alerts**: a chat line whenever you give or receive gold in a
  trade ("Trade with Booster: received 500g, gave 2 item(s) (in The
  Deadmines)"). Click it to open the trade log. Useful for boosters and
  buyers
- **Trades record where you were**: the trade log shows the instance you were
  in, and an Instance Tracker run's tooltip shows the gold traded during it

### Instance Tracker
Logs every dungeon and raid you enter, on every character, and keeps the
instance limits (Logging group on the dashboard; `/wmachine instances`).

- **Lockouts:** how many instances you've entered this hour (limit **5**) and
  in the last 24 hours (limit **30**), across all your characters, and when
  the next one frees up. It says whether you're on an **hourly** or a
  **daily** lockout. Runs are timed from when you **leave**, as the server
  does. `/wmachine lockouts` prints them, and so does the game's "too many
  instances" message. It tells you when you can enter a new instance again
- **Same instance, counted once:** the server numbers every instance, and
  the addon reads that number from the creatures inside. Going back into the
  same one (a corpse run, another wing on the same ID, a disconnect, logging
  out inside) adds to the earlier run instead of logging and counting a new
  one. A reset makes the next visit a new run
- **Each run keeps:** the group (name, level, class), time in and out and time
  inside, mobs killed by the group, XP (and XP per mob), gold looted, your
  level going in and out, and every reputation gain. Hover a run in the log
  to see it all; right-click to delete one
- **Entering an instance** prints "Entered The Deadmines (3/5 this hour, 7/30
  today)." with a **red X**: click the X to delete that run (when it
  shouldn't count), or click the line to open the log
- **Every line it prints is clickable** and opens the log: entering,
  leaving, the same-instance merge, lockouts, and Nova reset notices
- **Leaving an instance** prints the run's stats to your chat window, to your
  group, or not at all
- **Resets:** as group leader, a reset tells your group in party or raid chat
- **Nova Instance Tracker users:** when your group leader runs Nova Instance
  Tracker (or Nova World Buffs) and resets, their addon's notice is shown
  ("The Deadmines has been reset by the group leader") and the instance is
  marked as reset in your log. Only your own group's leader is believed.
  Watching Machine only listens; it never sends in Nova's format
- Options: merge the same instance, reset announcements, Nova reset notices,
  the "you can enter again" message, the "Entered" message, and where run
  stats go

### Battlegrounds & Arenas
A log of every battleground and arena match, on every character (Logging
group; `/wmachine bgs`).

- **Each match:** the result (win, loss, draw or left early), its length, and
  your scoreboard line: killing blows, honorable kills, deaths, honor,
  damage and healing
- **Arenas:** the bracket (2v2 / 3v3 / 5v5, rated or skirmish), who you were
  with and against, both team names, and your **rating change**
- **Totals:** games played, won and win rate per battleground and per arena
  bracket, for one character or all
- A **result line in chat** after each match (click it to open the log;
  can be turned off). Hover a match for everything; right-click to delete
- World PvP kills stay in the PvP Enemy Tracker

### Your Characters
Every character you log in, on every realm, in one window (Logging group;
`/wmachine alts`, or **Your Characters** in the Instance Tracker window).

- **Every character kept up to date:** while Your Characters is on for any
  of your characters, it saves every character you log in on, even one
  where its switch is off (that only hides the window there), so gold, bags
  and gear are always current

- Grouped by realm, with each realm's **total gold** (hover the realm) and
  your gold on all characters at the bottom
- Each character: level, **rested XP** (as a % of a level), gold and when you
  last played it. Rested XP keeps building while you're logged out (5% of a
  level per 8 hours resting, a quarter of that elsewhere, up to 1.5 levels),
  and the window shows the estimate for now
- **Hover a character** for: XP through the level, rested XP, gold, free bag
  slots (ordinary bags), armor durability (average and lowest piece),
  professions with their skill, your class's **reagents** (candles,
  powder, symbols, Ankhs, Soul Shards, ...), and for hunters **ammo** and
  the **pet** (name, level, family, happiness)
- **GearScore** column (3.42), from what each character last had on
- **Click a character** for their gear: a paper doll beside the window,
  hover a slot for the item, shift-click to link it. GearScore and average
  item level at the top
- **Bags, bank, attunements, lockouts** buttons on each row open the same
  flyout:
  - **Bags:** everything in their bags and keyring, with stack counts.
  - **Bank:** as of their last visit (open the bank once on each character).
  - **Attunements:** their progress on each one, and *Open Attunements*.
  - **Lockouts:** their raid saves (bosses killed, when it resets), plus
    the account's instances-per-hour count.
- **Find an item:** type a name to search every character's gear, bags,
  keyring and bank. Results show the total held; hover one for who has
  how many and where. Escape to go back
- Saved as you play and when you log out
- **Right-click** a character to remove one you've deleted

### Crit Tracker
Your biggest hits, crits and heals (Logging group; `/wmachine crits`).

- **For every spell, ability, melee and ranged attack and heal:** the best
  normal hit and the best crit, the crit rate, who it was on, where and
  when
- **PvP apart:** hits on players are kept as their own records (or not
  counted at all)
- **A new best crit** says so in chat ("New best crit: Fireball 4,700, was
  4,500, on Attumen"), with a sound you pick, optional big text on screen,
  and optionally a line to your party or raid. The first crit of a spell
  doesn't count as a record. *Quiet below* keeps levelling records
  quiet
- **Spell tooltips** show your records for that spell
- **The window:** records best crit first, filtered by kind (spells,
  abilities, melee, ranged, heals), creatures or players, and character.
  Hover a record for the details; right-click to share it in say, party,
  raid or guild. *Reset* clears a character's records
- **Your Characters** tooltips show each character's best crit

## Usage

### Dashboard
`/wmachine`, the minimap button, or **Options > AddOns > Watching Machine**
opens the dashboard. Everything the addon does can be reached from it.

- Cards are grouped into **Raid**, **Guild & Social** and **Logging**.
- **Sized to fit:** the first time it opens, the dashboard picks a size that
  shows every card without scrolling, using two (or more) columns of cards
  when one column would be taller than your screen.
- **Resizable:** drag the bottom-right corner. Cards reflow into as many
  columns as fit the width, and the size is remembered. **Fit** (top left)
  goes back to the size that shows every card.
- **Hide inactive** (top left, next to Fit) shows only the modules that are
  on for this character; groups with nothing on disappear, and a card goes
  as soon as you switch its module off. **Show all** brings every card back.
  It's remembered per character, and Fit sizes the dashboard to what's
  showing.
- **Hover a card** to see what the module does, its full status, and its
  slash command.
- The **on/off switch** on every card turns the module on or off for the
  character you're playing (see *Setup and characters*). An off module's
  icon is greyed out and its card says *Off on this character*.
- **Open** opens the module's window.
- **...** or **right-click** opens the module's tools: the diagnostics that
  used to be slash-command only.
  - **Debuff Tracker:** why is my target a boss, exclude / un-exclude target,
    list and clear exclusions, Shear tallies, shadow resist gear check,
    encounter callouts.
  - **Buff Check:** run a check now, explain buffs on target.
  - **ArmorySnap:** snapshot now, list snapshots, scanner status, reset
    session.
  - **PvP Tracker:** leaderboard, request guild sync.
  - **Class Tools:** consumable check, soulstone timers (warlock), portal
    list (mage), totem set editor (shaman).

### Slash Commands
- `/wmachine` - Toggle the main dashboard
- `/wmachine setup` - Run the setup (again) for this character, keeping what's on (`setup quick`, `setup guided`; also `/wmachine resetup`)
- `/wmachine settings` - Open theme/addon settings
- `/wmachine logger` - Open Auto Logger settings
- `/wmachine keyword` - Open Keyword Monitor
- `/wmachine filter` - Open Chat Filter (hide spam phrases; applied before Keyword Monitor)
- `/wmachine mail` - Open Mail & Trade Logger
- `/wmachine services` - Open Services Parser
- `/wmachine wcl` - Open Whisper Logs (WCL Lookup)
- `/wmachine ginvite` - Open Guild Invite
- `/wmachine debuff` - Open Debuff Tracker settings
- `/wmachine pvp` - Open PvP Enemy Tracker
- `/wmachine recruit` - Open Recruiting Tool
- `/wmachine buffcheck` - Open Buff Check settings
- `/wmachine armory` - Open ArmorySnap gear browser (also `/as`, `/as snap`, `/as list`, ...)
- `/wmachine range` - Open Aura Range alert settings
- `/wmachine exclude` - Stop the debuff tracker treating your target as a boss
- `/wmachine unexclude` - Undo an exclusion for your target
- `/wmachine exclusions` - List excluded NPCs
- `/wmachine whyboss` - Explain how the debuff tracker sees your target
- `/wmachine class` - Open Class Tools (tab per class, your own selected)
- `/wmachine soulstone` - Soulstone timers in your group (warlock)
- `/wmachine portals` - List the teleports and portals you know (mage)
- `/wmachine totems` - Edit your totem sets (shaman)
- `/wmachine instances` - Instance log and lockouts
- `/wmachine lockouts` - Print your instance lockouts
- `/wmachine alts` - Your Characters
- `/wmachine bgs` - Battleground and arena log
- `/wmachine loot` - Loot Browser (also `/wmachine atlas`)
- `/wmachine gtfo` - Hazard Alerts (`gtfo test`, `gtfo mute <spell ID>`, `gtfo unmute <spell ID>`)
- `/wmachine crits` - Crit Tracker
- `/wmachine gear` - Gear Sets (`gear equip <name>`, `gear undo`, `gear list`; also `/wmachine sets`)
- `/wmachine ogri` - Ogri'la Helper for the Apexis Relics (`ogri options`, `ogri clear`; also `/wmachine relic`)
- `/wmachine attune` - Attunements: raids, keys and heroic keys per character
- `/wmachine gs` - GearScore group list (`gs unlock`, `gs lock`, `gs reset`, `gs report`; also `/gs`)
- `/wmachine timers` - World Timers (layers, Terokkar, dailies, Darkmoon Faire)
- `/wmachine wb [guild|party|raid]` - Print the world timers, or send them to a channel
- `/wmachine swing` - Show the swing timer for 10 seconds to move or resize it
- `/wmachine swing reset` - Swing timer back to its default place and size
- `/wmachine consumes` - Show what the general raid consumable checks see
- `/wmachine minimap` - Toggle minimap button visibility
- `/wmachine resetminimap` - Reset minimap button position
- `/wmachine status` - Show status of all modules
- `/wmachine errors` - Show captured error log
- `/wmachine clearerrors` - Clear error log
- `/wmachine help` - Show command help

### Game Menu Button
- A **Watching Machine** button in the menu Escape opens, just above
  **Log Out** (like ElvUI's). Click it to open the dashboard
- With **ElvUI** it sits under ElvUI's button instead of on top of it, and
  takes ElvUI's button skin (unless ElvUI's Blizzard skins are off)
- Turn it off in Settings: *Watching Machine button in the game menu (Esc)*

### Minimap Button
- **Left-click**: Toggle dashboard
- **Right-click**: Settings (theme, minimap)
- **Hover**: every module's status, in dashboard order
- **Drag**: Move button anywhere on screen

## Global Theme System

Addon-wide theme support accessible via `/wmachine settings` or the Settings button on the dashboard.

### Available Themes
- **Default**: Standard WoW dialog box styling with gold headers and bright status colors
- **ElvUI**: Pixel-perfect dark theme with 1px borders, double-border effect, warm gold text, and muted colors. Auto-detected if ElvUI or Tukui is installed.

### Theme Coverage
- Dashboard and all module cards
- All module settings panels, including section headers and separators
- ArmorySnap follows the global theme (its old private ElvUI toggle is retired; `/as theme` points to `/wmachine settings`)
- Debuff Tracker overlay and indicators
- Live re-skinning: theme changes apply immediately without /reload

## Error Logging

Built-in error capture system for debugging.
- Captures all WatchingMachine-related errors with timestamps and stack traces
- Stored in SavedVariables (persists across sessions, max 200 entries)
- `/wmachine errors` - show last 20 errors in chat
- `/wmachine clearerrors` - clear the error log

## Installation

1. Extract the `WatchingMachine` folder to your WoW addons directory:
   - `World of Warcraft\_classic_anniversary_\Interface\AddOns\`
2. Restart WoW or reload UI (`/reload`)

## Saved Variables

- `WatchingMachineDB` - Core settings, theme, error log
- `AutoLoggerDB` - Auto Logger settings
- `KeywordMonitorDB` - Keyword Monitor data
- `ChatFilterDB` - Chat Filter phrases, premade switches and chat types
- `MailLoggerDB` - Mail & Trade logs
- `ServicesParserDB` - Services Parser settings
- `WhisperLogsDB` - Whisper Logs data
- `GuildInviteDB` - Guild Invite settings and log
- `DebuffTrackerDB` - Debuff Tracker settings
- `PvPTrackerDB` - PvP Enemy Tracker data and enemy list
- `RecruitingToolDB` - Recruiting Tool data
- `BuffCheckDB` - Buff Check settings
- `ArmorySnapDB` - ArmorySnap snapshots and options (shared with the standalone addon — existing archives carry over)
- `AuraRangeDB` - Aura Range settings
- `ClassToolsDB` - Per-class feature toggles and warning frame options
- `GeneralChecksDB` - General consumable check settings
- `MageToolsDB` - Mage button positions and expansion directions
- `WarlockToolsDB` - Warlock button position and expansion directions
- `SwingTimerDB` - Swing timer position, size, lock and weapon-sync lag
- `InstanceTrackerDB` - Instance log (every character) and its options
- `AltTrackerDB` - Your Characters: every character's saved details
- `PvPLogDB` - Battleground and arena matches (every character)
- `WorldTimersDB` - World Timers: layers and timers per realm and faction, Sayge cooldowns
- `LootBrowserDB` - Loot Browser: last expansion and instance, Normal / Heroic, set filter
- `WMGearScoreDB` - GearScore options, frame positions, others' scores (kept a week)
- `AttunementsDB` - Attunement progress per character, guild survey answers
- `HazardsDB` - Hazard Alerts options, sounds and muted spells
- `WMCritsDB` - Crit Tracker records per character, and options
- `WMGearSetsDB` - Gear Sets: each character's sets, last set and options
- `OgrilaDB` - Ogri'la Helper options, keys, position, relics played and longest sequences
- `ShamanToolsDB` - Totem sets, the set in use, and the totem button's position and direction
