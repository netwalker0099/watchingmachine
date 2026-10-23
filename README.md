# Watching Machine

**Comprehensive Monitoring Suite for WoW TBC Classic Anniversary**

Version 3.31 | Author: Robert | Interface 20506 (TBC Anniversary patch 2.5.6)

## Overview

Watching Machine combines eighteen monitoring and automation tools into a single unified addon with a central dashboard. Updated for The Burning Crusade Classic Anniversary Edition patch 2.5.6.

## Modules

### 1. Auto Logger
Automatically manages chat and combat logging.
- Enables chat logging on login
- Automatically enables combat logging in raid instances (10/25-man for TBC)
- Optional logging in 5-man dungeons
- **Advanced Combat Logging guard**: verifies the `advancedCombatLogging` CVar on login and when entering a raid, and re-enables it if it was turned off (required for complete Warcraft Logs uploads); toggleable in settings

### 2. Keyword Monitor
Monitor public channels for specific keywords with duplicate detection.
- Monitor Trade, General, LFG, and other channels
- 5-minute result retention with deduplication
- Sound and chat alerts
- **Chat Filter runs first**: messages hidden by Chat Filter (module 17) are never checked for keywords; the window says so at the top

### 3. Mail & Trade Logger
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

### 4. Services Parser
Parse services channel for boost advertisements by dungeon.
- Classic dungeons: RFC, SFK, SM, Mara, LBRS, ZG, Strat
- TBC dungeons: Ramparts, Blood Furnace, Slave Pens, Underbog, Mana Tombs, Shattered Halls, Shadow Lab, Botanica, Mechanar, Arcatraz
- Separate tab for summons/portals

### 5. Whisper Logs (WCL Lookup)
Track whispers and quickly look up players on Warcraft Logs.
- **Auto-detects your server** via GetRealmName() and injects it into WCL URLs
- **Per-player realm tracking**: Cross-server whispers and group members get their correct server in the URL, not yours
- Parses full "Player-Realm" format from whisper events and group roster
- Generates correct fresh.warcraftlogs.com URLs per region (US/EU/KR/TW/CN) — the Warcraft Logs partition for Anniversary realms; saved entries from older versions are migrated automatically
- "Scan Raid/Party" button to add all group members with correct realms
- Shows detected server in UI header, cross-server players tagged with realm name
- Click to copy URL, right-click to remove

### 6. Guild Invite
Auto-invite guild members to raid when they say the trigger word.
- Responds to trigger word (default: "inv") in guild chat or whispers
- Verifies guild membership before inviting whisper requests
- Requires party/raid leader or raid assist to process invites
- Auto-converts party to raid only when a 6th member is invited (won't convert legitimate 5-man parties)
- Say "raid" or "raid convert" in party/guild to manually convert
- TBC-compatible API calls with pcall protection (safe during arena/BG transitions)
- Invite logging with timestamps

### 7. Debuff Tracker
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

### 8. PvP Enemy Tracker
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

### 9. Recruiting Tool
Automated guild recruiting system.
- Scan unguilded players by class and level range (1-70 for TBC)
- Customizable message with %GUILD% placeholder

### 10. Buff Check
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

### 11. ArmorySnap
Passive raid gear & talent archive (integrated from the standalone ArmorySnap addon, keeping its fast v1.2 scanner).
- **Passively snapshots every raid member's gear** while you're in a raid instance — enchants and gems included (TBC item links embed both)
- **Fast event-chained scanning**: the next inspect fires the moment the previous one resolves; a full 25-man with everyone in range captures in roughly 15–20 seconds
- Out-of-range members retried every 15 seconds; new joiners picked up within 10 seconds
- **Paper-doll browser**: pick a snapshot, pick a member, see their gear laid out like the character frame with native tooltips; Shift-click to link items
- Talent tree capture (full detail for yourself; tree names/icons for inspected players — the Anniversary API doesn't expose inspected point counts to any addon)
- Enchant/gem count summary per character
- Zone-aware sessions labeled timestamp + zone; snapshots retained 1/7/14/30 days (dropdown)
- Manual snapshots via `/as snap [label]`; optional scanning in 5-man/world groups
- **Auto-scan** checkbox (or `/as auto`) turns automatic raid scanning off without disabling the module; manual snapshots still work
- **Migrates your existing archive**: uses the same `ArmorySnapDB` saved variable as the standalone addon; if the standalone addon is still enabled, the module stands down and tells you (disable one or the other)
- Keeps the standalone `/as` slash commands; also `/wmachine armory`

### 12. Aura Range
Visual and audio alerts when you drift out of range of party auras and shaman totems.
- **Watches your own buffs**: party auras (Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin auras) and totem buffs (Strength of Earth, Grace of Air, Wrath of Air, Totem of Wrath, Mana Spring, and more) drop off the moment you leave their radius — the module catches the drop instantly via UNIT_AURA, no polling
- **Movable on-screen alert** with pulsing red border listing exactly which auras you've walked away from, plus an optional raid-warning sound
- Alert clears the moment you step back into range
- **False-alarm guards**: no alerts while dead (death wipes buffs), when the provider (moonkin/shaman/etc.) is dead or gone, on zone transitions, or after leaving a group; stale alerts auto-expire (configurable 5–30s) to cover totems that simply expired or were destroyed
- Per-aura toggles, sound toggle, lockable alert frame, test button

### 13. Class Tools
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

### Flyout buttons (all classes)
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

### 14. Class — General
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
    PvP flag, or None); picking one plays it, so you can hear it. *Warning
    sounds play on* Master (default, heard with game sound turned down),
    Sound effects or Dialog
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
    with equal weapon speeds; the timer says so when they differ
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

### 15. Class — Warlock
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

### 16. Class — Mage
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

### 17. Class — Shaman
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

### 18. Class — Paladin
- **Righteous Fury check** — warns when Righteous Fury is missing, the same
  way the mage and warlock armor checks do. Only for **Protection**
  paladins: most talent points in Protection, or Holy Shield / Avenger's
  Shield learned. Holy and Retribution paladins are never nagged, and
  nothing shows before you've learned the spell or while you're dead

### 19. Instance Tracker
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

### 20. Your Characters
Every character you log in, on every realm, in one window (Logging group;
`/wmachine alts`, or **Your Characters** in the Instance Tracker window).

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
- Saved as you play and when you log out
- **Right-click** a character to remove one you've deleted

### 21. Battlegrounds & Arenas
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

### 22. World Timers
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
- `/wmachine wb` prints the short timers; `/wmachine wb guild` (or party /
  raid) sends them to that channel

### 23. Chat Filter
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

## Panel Builder

`UI.lua` is the shared builder for every window (`WM.UI:CreatePanel`).
A panel is a vertical list of rows (checkbox, slider, cycle, choice, edit
box, buttons, note, header, separator, collapsible section) instead of
hand-placed controls. Every panel built with it gets:

- title, close button, **Escape to close**, theme skin
- a height fitted to its content and **never taller than the screen**; the
  body scrolls when needed
- **collapsible sections**, and a **remembered position**, both saved in
  `WatchingMachineDB.panels`
- in-place refresh: controls re-read their settings, so a panel is never
  torn down and rebuilt to show new state

Every window uses it: the dashboard, Settings, and all module windows. The
only frames still built by hand are the on-screen warnings (Aura Range,
Class Tools, the Debuff Tracker display), which are overlays rather than
windows. List windows put their list in a `Layout:Fill` area below the
settings rows.

## Tests

`tests/` holds Lua 5.1 harnesses that stub the WoW API and load the real
addon files. Run them all with `LUA=/path/to/lua5.1 tests/run.sh`. The game
never loads them, because they aren't listed in the `.toc`.

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
- **Hover a card** to see what the module does, its full status, and its
  slash command.
- The **on/off switch** on a card turns the module on or off. Only modules
  with a single on/off flag have one: Buff Check, Debuff Tracker, Aura
  Range, ArmorySnap auto-scan, Guild Invite, PvP Tracker, Chat Filter, and
  Keyword Monitor (which pauses for the session). An off module's icon is greyed
  out.
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
- `ShamanToolsDB` - Totem sets, the set in use, and the totem button's position and direction

## Planned work

Ideas that are planned but not started, with open questions, are in
[`docs/TODO.md`](docs/TODO.md).

## Changelog

Full detail for 2.8 onward lives in [`CHANGELOG.md`](CHANGELOG.md).
Copy-paste release announcements for Discord and CurseForge are in
[`docs/`](docs/) — the latest is
[`docs/RELEASE-NOTES-v3.21-v3.28.md`](docs/RELEASE-NOTES-v3.21-v3.28.md)
(3.21 to 3.28). Earlier: 3.16 to 3.21 in
[`docs/RELEASE-NOTES-v3.16-v3.21.md`](docs/RELEASE-NOTES-v3.16-v3.21.md),
3.11.3 to 3.13 in
[`docs/RELEASE-NOTES-v3.11.3-v3.13.md`](docs/RELEASE-NOTES-v3.11.3-v3.13.md),
3.11 to 3.11.2 in
[`docs/RELEASE-NOTES-v3.11-v3.11.2.md`](docs/RELEASE-NOTES-v3.11-v3.11.2.md),
and 2.9 to 3.11 in
[`docs/RELEASE-NOTES-v2.9-v3.11.md`](docs/RELEASE-NOTES-v2.9-v3.11.md).

### Version 3.31
- The raid-wide SR check now runs on **every robot pull** after Mother instead of once, 45 seconds after the kill
- Fix: the mana potion warning now sees potion cooldowns on 2.5.6, so the rune warning shows when your potion is on cooldown
- When the mana potion warning can't show (no potion, on cooldown, unusable here, or the 25-man-only setting), it says why in chat once
- Item checks use the current `C_Item` / `C_Container` API instead of Blizzard's deprecation fallbacks

### Version 3.30
- New **raid-wide shadow resist check**: the raid leader sees who is still in SR gear after Mother Shahraz (`/wmachine srraid`, or automatically 45 seconds after the kill)

### Version 3.29.1
- Fix: the Black Temple **shadow resist gear check** now counts socketed gems (Void Sphere's +4 Resist All), enchants and socket bonuses, and pieces whose resistance the item stats don't report

### Version 3.29
- Fix: the **Shattrath flasks** (Blinding Light, Pure Death, Relentless Assault, Supreme Power, Fortification, Mighty Restoration) now count as flasks in Buff Check and the personal flask warning

### Version 3.28
- New **World Timers**: your layer, Terokkar Forest tower resets per layer, today's dungeon / heroic / PvP dailies, the Darkmoon Faire (where, when, your Sayge cooldown), Classic world buff timers and Songflowers, with Nova World Buffs users' shared timers read in (listen only)

### Version 3.27
- New **Your Characters** window: every alt by realm with gold, rested XP (estimated while offline), bags, durability, professions, reagents, and hunter ammo and pet
- New **Battlegrounds & Arenas** log: results, scoreboard stats, arena brackets, teams and rating changes, with win rates

### Version 3.26.1
- New **Potion** warning sound

### Version 3.26
- **Alert sounds**: the mana potion and rune warnings play their own sounds (new potion and rune sounds by default), each chosen from a dropdown, on the sound channel you pick

### Version 3.25
- **Gold trade alerts** in chat (who, how much each way, and where), and the trade log records the instance you were in; Instance Tracker runs show the gold traded during them

### Version 3.24
- Instance Tracker chat lines are **clickable** (open the log), and entering an instance prints a line with a **red X** to delete that run

### Version 3.23
- Instance Tracker shows **reset notices from group leaders running Nova Instance Tracker** (or Nova World Buffs), and marks the instance as reset; listen only

### Version 3.22
- New **Instance Tracker**: instance lockouts (5 an hour, 30 a day, timed from leaving, hourly or daily), a log of every run on every character with group, time, mobs, XP, gold, levels and reputation, the same instance counted once, and reset announcements

### Version 3.21
- The **dashboard is resizable** and opens at a size that shows every module; cards flow into columns as it gets wider, and **Fit** snaps back to the show-everything size

### Version 3.20.1
- Fixed: the game menu button sat on top of ElvUI's and kept the default look. It now goes under ElvUI's button (or any other addon's) and takes ElvUI's skin

### Version 3.20
- The **swing timer is resizable**: drag its corner while unlocked, or choose a width and bar height in Class Tools > General

### Version 3.19
- **Watching Machine button in the game menu** (Escape), above Log Out, opening the dashboard; can be turned off in Settings

### Version 3.18
- New **Paladin** tab in Class Tools: Protection paladins are warned when **Righteous Fury** is missing

### Version 3.17
- **Swing timer** for warriors, rogues, Retribution paladins and Enhancement shamans, and an **Auto Shot timer** for hunters, with your latency shown at the end of each bar
- Hunters: the bar shows when a Steady Shot is safe, when it would clip the next shot, and the wind-up
- Enhancement shamans: a **weapon sync** mark for your sync macro, with *SYNC NOW* and an in-sync / out-of-sync readout

### Version 3.16.1
- Fixed: in Class Tools, option dropdowns (e.g. the mage *expand* directions) covered the first line of their description. The description now sits below the dropdown, and the dropdowns line up in one column
- The Totem Sets editor is a little wider, so its two dropdown columns can't touch

### Version 3.16
- **Shaman totem button**: hover to pick a totem set, click to drop it one totem per click (Air, Water, Earth, then Fire); starts again from Air when your totems are gone, after combat, or on Ctrl-click
- Four editable sets, premade as Melee, Caster, Healer and Tremor, each picking the best totem you know; `/wmachine totems` opens the editor

### Version 3.15
- **Warlock button**: demons (Felguard only if talented), armors, and Soulwell / Ritual of Summoning / Healthstone / Soulstone, with Soul Shard counts on the spells that use one
- Every flyout button can open **on hover or on click**, be **docked** together in a row or column, and has a shared **lock** (Class Tools > General)
- **Hidden** added to every flyout direction; direction and other choice options are now **dropdowns**

### Version 3.14
- New mana warnings in Class Tools > General: **drink a mana potion** at 3000 mana below max, or **use a Dark / Demonic Rune** at 1500 below when no potion is ready; both thresholds adjustable

### Version 3.13.1
- Fixed: a battle plus a guardian elixir (e.g. Adept's Elixir + Elixir of Draenic Wisdom) still gave a "No flask" warning. The raid check (now **Flask or Elixirs**) and the personal check accept a flask or both elixirs, from one shared list
- Elixirs are matched by spell ID as well as name; `/wmachine whybuff` shows the spell ID of anything it can't match

### Version 3.13
- New **mage utility button** (class crest): mana gems, armors and food / water / table, each group highest level nearest the button, with spell tooltips
- Each group's expansion direction is set in Class Tools > Mage; groups sharing a direction line up in order
- The lock option now covers both mage buttons

### Version 3.12
- Mage portal button is now a portal icon that expands into spell icons, one per portal and teleport, with spell tooltips on hover
- New Mage options: *Portals expand* and *Teleports expand* (Up / Right / Down / Left); the same direction puts portals first, then teleports
- Class Tools options can now be choices as well as checkboxes

### Version 3.11.3
- Fixed: clicking a portal or teleport in the mage portal button didn't cast it

### Version 3.11.2
- Fixed: the dashboard tools menu (**...** / right-click) opened near the bottom of the screen with ElvUI or a non-default UI scale; it now opens under the card's **...** button

### Version 3.11.1
- Fixed: error spam on login on mages ("Attempt to register unknown event LEARNED_SPELL_IN_TAB"), which also stopped other modules from starting
- A module that errors at start-up no longer blocks the others, and a failing timer no longer repeats every frame

### Version 3.11
- Chat Filter: premade filters for **GDKP**, **Guild Loot Run** and **Gear Carry** (incl. "gear carries"), one tick each in the Chat Filter window; off until switched on

### Version 3.10
- **New module: Chat Filter** — hide chat messages containing phrases you choose (e.g. *Guild Loot Run*); applied before Keyword Monitor, so filtered spam is never checked for keywords. Both windows carry a warning saying so
- Class Tools dashboard card shows your class crest (the old Wrath-era achievement icon doesn't exist in the TBC client)

### Version 3.9
- Every remaining window moved to the panel builder: Auto Logger, Aura Range, Guild Invite, Keyword Monitor, WarcraftLogs Lookup, Services Parser, Mail & Trade, Recruiter (all three windows), Class Tools, PvP leaderboard, ArmorySnap, Settings and the dashboard
- Every window closes on Escape, remembers where you put it, fits the screen, and has tooltips (Mail & Trade, Guild Invite and Recruiter had none)
- Services Parser settings are a section of its window instead of a separate one; Mail & Trade and Services Parser mark the current tab
- ArmorySnap follows the global theme; its private ElvUI toggle is retired
- Theme changes restyle windows in place instead of rebuilding the dashboard and Settings
- Builder: dropdowns, resizable panels, footer text, first-open placement, adoption of old saved positions, numeric edit boxes

### Version 3.8
- Dashboard: cards grouped into Raid, Guild & Social and Logging; hover a card for a description, its full status and its command
- On/off switch on the cards of modules with an enable flag; off modules are greyed out
- Tools menu on cards (**...** or right-click) for the diagnostics that were slash-command only
- Card text truncates instead of running under the buttons
- Minimap right-click opens Settings; its tooltip lists modules in dashboard order
- Watching Machine page under the game's Options > AddOns
- Removed the unused `moduleStates` saved setting

### Version 3.7
- New shared panel builder (`UI.lua`): panels fit their content, never exceed the screen, scroll when needed, remember their position and have collapsible sections
- **Debuff Tracker**: settings and encounter callouts are one scrolling panel again, in collapsible sections; the debuff list is no longer squeezed into a 141px box; `/wmachine encounters` opens it at the callouts
- **PvP Tracker**: Guild Sync and Leaderboard sections collapse to give the KOS list more room; tooltips on every alert option
- **Buff Check** rebuilt on the builder
- Debuff Tracker settings refresh in place on roster changes instead of being rebuilt

### Version 3.6
- Buff Check's **Food Buff** check (Well Fed or Enlightened) is now **on by default**, including for existing installs (once — turning it off afterwards sticks)
- Debuff Tracker settings, PvP Tracker and the dashboard never grow taller than the screen; at larger UI scales their lists shrink instead of the bottom going off screen
- Keyword Monitor can no longer be resized taller than the screen
- ArmorySnap: new **Auto-scan** checkbox and `/as auto` for the previously hidden enabled setting
- Mage: new **Lock the portal button** option
- Lua test harnesses committed under `tests/`

### Version 3.5.2
- Escape now closes every Watching Machine window, not just ArmorySnap
- PvP Enemy Tracker window is 700px tall instead of 780, so its list no longer runs off the bottom of the screen
- Theme changes now recolour section headers and separators in open windows, and ArmorySnap follows the global theme
- Services Parser settings window can no longer be dragged off screen
- `/wmachine help` lists `status`, `clearexclusions` and the `/as` sub-commands

### Version 3.5.1
- Buff Check and the General food check now accept **Enlightened** (Skullfish Soup) as a food buff, not just Well Fed
- Food and flask aura names are shared between Buff Check and Class Tools General, so the two can't disagree
- Buff Check's "Well Fed" check is renamed **Food Buff**; it is still off by default

### Version 3.5
- Class Tools: first class features — Warlock (armor, Demonic Sacrifice, Soul Link, soulstone timers), Mage (armor check, expanding portal/teleport button)
- New **General** tab: flask, food buff and weapon oil/stone checks inside raid instances, 25-man only by default
- Shared one-second monitor tick and a single movable *CHECK YOURSELF* warning frame for all class features
- Warning frame options in the panel: sound, lock, reset position, show example
- Warlock talent cache is dropped on respec instead of waiting out its 5s TTL
- New commands: `/wmachine class`, `/wmachine soulstone`, `/wmachine portals`, `/wmachine consumes`

### Version 3.4
- Class Tools framework: per-class tabs in the dashboard, features register themselves, toggles saved per class
- Mail Logger: Open All is logged by diffing the inbox rather than on take attempts, fixing duplicates during bulk pulls
- Dashboard card list made scrollable so all modules stay reachable

### Version 3.3
- DebuffTracker: Illidan Shear monitor with raid announcements, throttle and pull summary
- DebuffTracker: shadow resist gear check after Mother Shahraz

### Version 3.2
- DebuffTracker: Illidan Doom warning — `/rw CAST DOOM NOW` at 68% (toggle in settings, on by default)
- Buff Check: Elixir of Empowerment and Elixir of Major Defense classed as Guardian; Unstable Flasks now detected; expanded elixir lists
- New `/wmachine whybuff` diagnostic for Buff Check

### Version 3.1
- DebuffTracker: eliminated boss-detection false positives
  - Root cause: the old check treated any mob at `level >= playerLevel + 3` with elite classification as a boss. TBC raid trash is level 72–73 elite, identical to real bosses, so trash like Magtheridon's Hellfire Warders was flagged. Display names couldn't separate them either, since some trash shares names with encounter mobs
  - Mobs are now identified by **npcID** extracted from their GUID (unique per creature type even when names collide), gated behind a **health-pool floor** (default 150k, adjustable) that separates trash from bosses regardless of level
  - **Focus target tracking**: on multi-boss encounters, alerts only fire for the mob taking the most raid damage in a rolling 6s window. Targeting an add the raid is ignoring no longer triggers alerts, and the focus follows the raid automatically when the kill order or strategy changes. Fails open — a stale focus never silences alerts permanently
  - Manual npcID exclusion list with `/wmachine exclude` / `unexclude` / `exclusions`
  - New `/wmachine whyboss` diagnostic explaining the tracker's view of your target
  - Group-membership lookups for combat log processing are now a cached hash set instead of a 40-unit scan per event

### Version 3.0
- **New module: Aura Range** — out-of-range alerts for party auras and shaman totems
  - Detects the instant Moonkin Aura, Trueshot Aura, Leader of the Pack, Tree of Life, paladin auras, or totem buffs drop off you while their provider is alive in your group
  - Movable pulsing alert frame + optional sound; clears when you walk back in range
  - Suppresses false alarms from death, provider death, zoning, leaving group; stale alerts auto-expire
- Buff Check: Battle Elixir and Guardian Elixir detection (off by default, toggle in settings)
  - TBC-accurate elixir lists for both categories, including classic-era holdovers
  - Flasks correctly satisfy both elixir slots
- Buff Check: PallyPower single-target assignments now override that paladin's class blessing per player
  - Previously the expectation was the union of both, so a feral tank with a single Might assignment was falsely flagged for missing the class-wide Salvation
  - Expectations are now computed per paladin: the single-target assignment replaces that paladin's class blessing for that player, while other paladins' class blessings still apply

### Version 2.9
- **New module: ArmorySnap** — the standalone ArmorySnap addon is now integrated as a Watching Machine module
  - Passive raid gear/talent snapshots with a paper-doll browser, snapshot retention dropdown, and manual snapshots
  - Includes the v1.2 scan-speed overhaul: event-chained inspects capture a full 25-man in ~15–20s (the old fixed-tick scanner took 75+ seconds); out-of-range retry 120s → 15s
  - Reuses `ArmorySnapDB`, so archives from the standalone addon appear automatically
  - Detects the standalone addon and disables itself if both are running (prevents inspect conflicts)
  - Standalone `/as` commands kept; minimap button dropped in favor of the WM dashboard

### Version 2.8
- Updated for TBC Classic Anniversary patch 2.5.6 (Interface 20506, Classic Era 11508)
- Removed stale Wrath/Cata interface declarations from the TOC (those clients no longer exist)
- WhisperLogs: WCL URLs now point at fresh.warcraftlogs.com — the partition for Anniversary realms (classic.warcraftlogs.com is the old 2021 progression era); previously saved entries are migrated on login
- MailLogger: fixed duplicate log entries when bulk-pulling mail
  - Take hooks logged on every ATTEMPT — bulk-pull addons retry the same slot until the server responds, creating one entry per retry
  - Mail data was read from a snapshot cache that went stale when mail deletion shifted inbox indices, logging the wrong (already-logged) mail's data
  - Hooks now read the inbox live at take time, with a per-slot dedupe fingerprint that resets whenever the inbox actually changes — identical mails from the same sender still all log correctly
  - "Open All Mail" button (AutoLootMailItem) is now hooked too; those pulls were previously never logged
- **New module: Buff Check** — full raid buff audit on every ready check
  - Announces missing buffs to raid chat when YOU start the ready check
  - Reports locally (only you see it) when someone else starts it
  - Checks Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings, and optional Divine Spirit, Shadow Protection, Well Fed, and Flask auras
  - Skips buffs whose providing class isn't in the group; skips offline/dead players
  - PallyPower integration: checks each player against their assigned blessings (class + single-target) when PallyPower is configured, reading PallyPower's own runtime tables so it tracks that addon's versions and localization; graceful fallback to the generic check otherwise
- AutoLogger: Advanced Combat Logging guard
  - Verifies the advancedCombatLogging CVar on login and when entering raids
  - Re-enables it automatically if it got turned off (WCL uploads need it)
  - New settings checkbox + live CVar status in the panel
- Performance pass across the addon:
  - KeywordMonitor: result rows are now pooled and reused — previously every row was recreated once per second while the window was open, permanently leaking frames
  - WhisperLogs: entry rows pooled and reused instead of recreated on every whisper/refresh
  - MailLogger: inbox re-cache now uses a single debounced timer instead of creating a new frame on every MAIL_INBOX_UPDATE event
  - DebuffTracker: target debuff scanning now uses precomputed name/spellID lookup tables instead of nested linear searches (runs 5x/second)
  - Core: module color table hoisted out of the print functions (was rebuilt on every chat message)
- AutoLogger: fixed local variable shadowing the global `type` in instance detection

### Version 2.7
- DebuffTracker: Boss pull announce — "First hit: Playername on Gruul"
  - Detects first player in group to hit a boss via combat log
  - Configurable channel: Say, Party, Raid, /rw (cycles on click)
  - Follows leader-only announcement rules (no duplicate spam)
  - Resets per encounter
- DebuffTracker: Healing Debuff category marked optional in auto-detect
  - Auto-detect won't enable it; user must opt in manually
  - Shows "(optional)" tag in settings, checkbox stays interactive
- PvP Tracker: GUID-based player validation + faction checks
  - Fixed boss abilities (e.g. Shade of Aran Flame Wreath) being logged as PvP kills
  - Player GUIDs validated via "Player-" prefix (NPCs start with "Creature-")
  - NPC-controlled entities rejected via COMBATLOG_OBJECT_CONTROL_NPC flag
  - UnitFactionGroup check on unit detection and nameplate scanning

### Version 2.6
- Removed guild restriction — addon is now open to all players
  - No longer requires "Socks and Sandals" guild membership
  - Officer rank gating removed — all modules including Recruiter available to everyone
  - Removed security check retry loop, /wmachine recheck command
  - Simplified login flow: modules initialize immediately (no guild info wait)
  - 160 lines of security scaffolding removed

### Version 2.5
- Global verbose chat mode: low-priority messages hidden by default, toggle in WM Settings
  - Sync status, roster updates, leaderboard ticks, and diagnostics moved to VerbosePrint
  - High-priority alerts (revenge kills, enemy detected, kill notifications, errors) always visible
  - Verbose messages render in gray to distinguish from important alerts
- DebuffTracker: alert coordination — only raid leader announces missing debuffs to chat
  - "Assistants can announce" checkbox for raids where leader doesn't have addon
  - All players still see alerts locally regardless of role
- DebuffTracker: encounter-aware alerts — fixed pre-pull, post-kill, and retarget re-fire bugs
- DebuffTracker: dead caster suppression — silences alerts when all casters for a debuff are dead
- DebuffTracker: raid alerts force-disabled on upgrade (re-enable in settings after updating)
- DebuffTracker: fixed IsBossUnit crash when targeting bosses in TBC Classic
- GuildInvite: explicit leader/assist permission check before processing invite requests
- PvP Tracker: guild sync and leaderboard now default to on for new installs
- PvP Tracker: removed per-module "Show sync messages" checkbox (replaced by global verbose mode)
- Full addon audit: verified no forward-reference or retail-only API issues across all 10 files

### Version 2.4
- DebuffTracker: alert coordination — only raid leader announces to chat (prevents duplicate spam)
  - "Assistants can announce" checkbox for raids where leader doesn't have the addon
  - All players still see alerts locally regardless of role
- DebuffTracker: encounter-aware alerts — fixed pre-pull, post-kill, and retarget re-fire issues
  - Checks UnitAffectingCombat(target) so unengaged bosses don't trigger alerts
  - Tracks bossDeadGUID to suppress alerts after boss dies
  - alertedThisPull prevents same category from re-firing during an encounter
- DebuffTracker: dead caster suppression — silences alerts when all casters for a debuff are dead
  - Scans raid for alive members matching class+spec needed for each debuff category
  - 2-second cache to avoid scanning 40 members every tick
  - Battle rez resumes alerts within 2 seconds
- DebuffTracker: raid alerts force-disabled on upgrade (re-enable in settings)
- DebuffTracker: fixed IsBossUnit crash when targeting bosses in TBC Classic
  - IsBossUnit() is a retail-only global; local function was defined after first call site
- GuildInvite: explicit leader/assist permission check before processing invite requests
  - Solo: can invite; Party: must be leader; Raid: must be leader or assistant
- PvP Tracker: guild sync and leaderboard now default to on for new installs
- Full addon audit: verified no forward-reference or retail-only API issues across all 10 files

### Version 2.3
- PvP Tracker: Guild Sync UI controls (enable, show messages, auto-request, send/request buttons)
- PvP Tracker: revenge kill announcements ("X has slain Y! Z has been avenged!")
- PvP Tracker: KOS Leaderboard with point system (1pt per KOS kill, synced across guild)
- PvP Tracker: leaderboard window with ranked list, bar graph, gold/silver/bronze medals
- PvP Tracker: three announcement modes (Off, Hourly top 3, On Lead Change)
- PvP Tracker: outgoing kill detection via PARTY_KILL and damage attribution
- PvP Tracker: leaderboard points included in Hello handshake on login
- Guild Invite: ignore player's own messages (won't self-invite when typing trigger words)

### Version 2.2
- Debuff Tracker: raid composition auto-detection with talent spec awareness
- Debuff Tracker: missing debuff raid alerts with configurable delay and cooldown
- Debuff Tracker: removed WotLK abilities (Savage Combat, Infected Wounds)
- Debuff Tracker: added spec requirements to debuff definitions (Shadow Priest, Arms Warrior, etc.)
- Whisper Logs: auto-detects server, per-player realm tracking for correct WCL URLs
- Whisper Logs: proper cross-server player support via "Player-Realm" parsing
- Guild Invite: fixed C_PartyInfo retail API calls for TBC Classic (uses global ConvertToRaid/InviteUnit)
- Guild Invite: auto-convert to raid now only triggers on 6th invite (won't break 5-man parties)
- Guild Invite: pcall-protected group API calls (safe during arena/BG transitions)

### Version 2.1
- Added PvP Enemy Tracker module (world PvP kill logging and proximity alerts)
- Added global theme system (ElvUI/Tukui skin for entire addon)
- Added Settings panel accessible via dashboard button and `/wmachine settings`
- Added built-in error logging with stack traces (`/wmachine errors`)
- Added per-debuff selection to Debuff Tracker
- Moved theme system from DebuffTracker to Core.lua (all modules now themed)
- Auto-detects ElvUI/Tukui on first load and selects matching theme
- Fixed module initialization for existing installs (new modules merge into saved moduleStates)

### Version 2.0
- Updated for TBC Classic Anniversary Edition
- Added Guild Invite module (auto-invite on "inv" trigger)
- Added Debuff Tracker module (raid debuff monitoring with priority)
- Added TBC dungeons to Services Parser
- Minimap button now freely movable anywhere on screen
- Fixed GetInboxItem API for TBC (itemID return value)
- Added Test Message button to Recruiting Tool
- Added nil safety checks throughout all modules
