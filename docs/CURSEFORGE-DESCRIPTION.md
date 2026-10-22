Post Issues here - https://github.com/netwalker0099/watchingmachine/issues
Please include your full LUA error output.

# Watching Machine

**Comprehensive Monitoring Suite for WoW TBC Classic Anniversary**

Version 3.21 | Author: Robert | Interface 20506 (TBC Anniversary patch 2.5.6)

## Overview

Watching Machine combines fourteen monitoring and automation tools into a single unified addon with a central dashboard. Updated for The Burning Crusade Classic Anniversary Edition patch 2.5.6.

- **Raid:** Buff Check, Debuff Tracker, Class Tools, Aura Range, ArmorySnap
- **Guild & Social:** Guild Invite, Recruiting Tool, PvP Enemy Tracker, Chat Filter, Keyword Monitor, Services Parser, Whisper Logs
- **Logging:** Auto Logger, Mail & Trade Logger

**Class Tools** adds per-class helpers. It has a swing timer, an Auto Shot timer and raid consumable checks for everyone. It also has flyout spell buttons for mages and warlocks, a totem button for shamans, and missing-buff warnings for every supported class.

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
- **Chat Filter runs first**: messages hidden by Chat Filter are never checked for keywords, and the window says so

### 3. Mail & Trade Logger

Long-term logging of items and gold received via mail and trades.

- Logs gold, items, and auction house transactions
- Multi-character support with character selector
- Filter by Gold, Items, AH Sales, AH Buys, Expired
- Duplicate-proof bulk mail pulling (Postal-style addons and retry-spam handled)
- "Open All Mail" button pulls are logged too

### 4. Services Parser

Parse services channel for boost advertisements by dungeon.

- Classic dungeons: RFC, SFK, SM, Mara, LBRS, ZG, Strat
- TBC dungeons: Ramparts, Blood Furnace, Slave Pens, Underbog, Mana Tombs, Shattered Halls, Shadow Lab, Botanica, Mechanar, Arcatraz
- Separate tab for summons/portals

### 5. Whisper Logs (WCL Lookup)

Track whispers and quickly look up players on Warcraft Logs.

- **Auto-detects your server** via GetRealmName() and injects it into WCL URLs
- **Per-player realm tracking**: cross-server whispers and group members get their correct server in the URL, not yours
- Parses full "Player-Realm" format from whisper events and group roster
- Generates correct fresh.warcraftlogs.com URLs per region (US/EU/KR/TW/CN), the Warcraft Logs partition for Anniversary realms; saved entries from older versions are migrated automatically
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

Visual raid debuff monitoring with auto-detection, raid alerts and encounter callouts.

- Tracks important debuffs on your target with priority awareness
- Shows visual indicators (green=present, red=missing, yellow=suboptimal)
- Per-debuff selection: choose exactly which debuffs to track per category
- **Raid Auto-Detection**: scans the raid roster for classes and talent specs
  - Detects specs via persistent buffs (Shadowform, Moonkin Form, Leader of the Pack, Tree of Life, Trueshot Aura)
  - Three-state availability: confirmed (green), unconfirmed (yellow, class present but spec unknown), absent (red)
  - Auto-enables only debuff categories your raid can actually provide
  - Auto-disables individual debuffs when their required class/spec is missing
  - Re-scans on roster changes and every 5 seconds for spec buffs
  - Manual override available (toggle auto-detect off for full manual control)
- **Missing Debuff Raid Alerts**: sends raid chat/warning when a tracked debuff is missing from a boss
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
- **False-positive filtering** (so trash isn't mistaken for a boss):
  - Mobs are identified by their NPC ID, not their name, so same-named mobs elsewhere aren't confused
  - **Health-pool floor** (default 150k, slider): stops elite trash such as Magtheridon's Hellfire Warders registering as bosses
  - **Focus target tracking** on multi-boss fights (Fathom-Lord Karathress, Illidari Council): only the mob the raid is actually damaging triggers alerts, whatever the kill order
  - **Manual exclusions**: `/wmachine exclude` with a mob targeted stops that creature type triggering boss alerts
  - **`/wmachine whyboss`** explains exactly how the tracker sees your target
- **Encounter callouts** (Black Temple), in the *Encounter Callouts* section of the settings (`/wmachine encounters`):
  - **Illidan Doom warning**: raid-warns **CAST DOOM NOW** when Illidan hits 68%, so warlocks land Curse of Doom before he lifts off at 65%. Once per pull, sent by the raid leader (or assistants) so it isn't duplicated
  - **Illidan Shear monitor**: calls out Shear on the main tank during ground phases, including Shears that were dodged, parried or blocked (damage meters miss these). One call per cast, a per-pull summary, an optional local cast warning, `/wmachine shear` for tallies
  - **Shadow resist gear check**: after Mother Shahraz (or on the first Grand Promenade pull), warns if you're still wearing shadow resist gear. Reads equipped gear only, with an adjustable threshold. `/wmachine srcheck` shows what it detects per slot
- Configurable: show only in raid, show only on boss, categories to track
- Draggable frame, lockable position

### 8. PvP Enemy Tracker

Track hostile players who kill you in world PvP and get proximity alerts.

- **Kill Tracking**: automatically logs players who kill you outside battlegrounds/arenas
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
- **Guild Sync**: share KOS lists with guildies running Watching Machine
  - Real-time kill broadcasts to guild channel on every PvP death
  - Full list sync on login and on-demand (Request Sync / Send List buttons)
  - Per-reporter kill tracking with merge logic (won't echo data back)
  - Revenge announcements: guild chat message when you kill a KOS enemy reported by a guildie
  - Configurable: enable/disable, show sync messages, auto-request on login
- **KOS Leaderboard**: compete with guildies for most KOS kills
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

- **You start the ready check**: missing buffs are announced to raid/party chat ("Missing Fortitude: Player1, Player2")
- **Someone else starts it**: the same report prints locally where only you can see it
- Tracked buffs (TBC): Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings (any), Divine Spirit, Shadow Protection, Food Buff (Well Fed or Enlightened, on by default), Flasks, Battle Elixirs, Guardian Elixirs, each individually toggleable
- Elixir checks know the TBC rules: a flask covers both the battle and the guardian elixir
- **PallyPower integration**: when PallyPower is running and paladins in your group have assignments, each player is checked against their *assigned* blessings and the report names the exact missing blessing ("Missing Blessing of Kings: Player1"); greater and normal versions both count; single-target assignments override the class-wide ones correctly; falls back to the generic "any blessing" check when PallyPower is absent or unconfigured
- Class buffs are only checked when the providing class is actually in the group (no priest = no Fortitude nag)
- Only classes a buff applies to are checked (rogues aren't flagged for missing Intellect)
- Offline and dead players are skipped (listed separately in the local report)
- Long reports are split to respect the chat message length cap
- "Run Check Now" button for manual local checks any time
- Optional "all buffs up!" confirmation message

### 11. ArmorySnap

Passive raid gear & talent archive (integrated from the standalone ArmorySnap addon, keeping its fast v1.2 scanner).

- **Passively snapshots every raid member's gear** while you're in a raid instance, enchants and gems included (TBC item links embed both)
- **Fast event-chained scanning**: the next inspect fires the moment the previous one resolves; a full 25-man with everyone in range captures in roughly 15–20 seconds
- Out-of-range members retried every 15 seconds; new joiners picked up within 10 seconds
- **Paper-doll browser**: pick a snapshot, pick a member, see their gear laid out like the character frame with native tooltips; Shift-click to link items
- Talent tree capture (full detail for yourself; tree names/icons for inspected players, since the Anniversary API doesn't expose inspected point counts to any addon)
- Enchant/gem count summary per character
- Zone-aware sessions labeled timestamp + zone; snapshots retained 1/7/14/30 days (dropdown)
- Manual snapshots via `/as snap [label]`; optional scanning in 5-man/world groups
- **Auto-scan** checkbox (or `/as auto`) turns automatic raid scanning off without disabling the module; manual snapshots still work
- **Migrates your existing archive**: uses the same `ArmorySnapDB` saved variable as the standalone addon; if the standalone addon is still enabled, the module stands down and tells you (disable one or the other)
- Keeps the standalone `/as` slash commands; also `/wmachine armory`

### 12. Aura Range

Visual and audio alerts when you drift out of range of party auras and shaman totems.

- **Watches your own buffs**: party auras (Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin auras) and totem buffs (Strength of Earth, Grace of Air, Wrath of Air, Totem of Wrath, Mana Spring, and more) drop off the moment you leave their radius, and the alert appears instantly
- **Movable on-screen alert** with a pulsing red border listing exactly which auras you've walked away from, plus an optional raid-warning sound
- Alert clears the moment you step back into range
- **False-alarm guards**: no alerts while dead, when the provider is dead or gone, on zone transitions, or after leaving a group; stale alerts auto-expire (5–30s) to cover totems that simply expired or were destroyed
- Per-aura toggles, sound toggle, lockable alert frame, test button

### 13. Chat Filter

Hides chat spam by phrase (e.g. **Guild Loot Run**) before you, or Keyword Monitor, ever see it.

- **Premade filters**, one tick each (off until you turn them on): **GDKP**, **Guild Loot Run**, **Gear Carry** (also "Gear Carries")
- Add any number of your own phrases; a message containing one **anywhere** is hidden from every chat frame
- Matching ignores case, colour codes, item-link brackets and extra spaces. Phrases are plain text, no wildcards
- **Applied before Keyword Monitor**: a hidden message is never checked for keywords, so filtered spam can't produce matches
- Filters public channels by default; say/yell and whispers can be ticked on
- Your own messages are never hidden
- Per-phrase and total counts of hidden messages for the session
- `/wmachine filter`, or the dashboard card's on/off switch

### 14. Class Tools

Detects the class you're playing and shows the tools built for it, in a tab per class (`/wmachine class`). Your own class is selected when it opens, and every feature has its own on/off switch, saved per class.

Warnings from every class feature are collected into one movable **CHECK YOURSELF** frame (up to six lines) that hides itself when the last warning clears. It has a sound option, a lock, a reset and a **Show example** button for positioning.

#### General (everyone)

- **Raid consumable checks** inside raid instances (25-man by default, 10-mans optional):
  - **Flask or elixirs** (a flask, or a battle plus a guardian elixir)
  - **Food buff** (Well Fed, or Enlightened from Skullfish Soup)
  - **Weapon enchant**: casters are told about wizard oil, melee about sharpening stones / weightstones. The off hand is only checked when a real weapon is there
  - `/wmachine consumes` shows exactly what the checks see
- **Mana potion / rune warnings** (mana users, in combat):
  - **Use a mana potion** once you're 3000 mana below max and a potion is ready. It names the potion and prefers the free raid-zone ones where they work
  - **Use a Dark / Demonic Rune** once you're 1500 below and no potion is ready (on cooldown or none left). Not below 35% health
  - Both thresholds are adjustable, and the warnings don't flicker as mana regenerates
- **Swing timer**: a bar per hand showing the time to your next swing, for warriors, rogues, **Retribution** paladins and **Enhancement** shamans (spec read from your talents), and an **Auto Shot** bar for hunters. An option turns it on for any class
  - A white line moves left to right as the swing comes round. The last stretch, as long as your **latency**, is drawn in red
  - Follows TBC's rules: Heroic Strike / Cleave replace the swing; finishing a cast (Slam, Lightning Bolt, a heal) restarts it; instants (Stormstrike, shocks) don't; haste such as Flurry speeds it up; **parrying** brings your next swing sooner (40% of the swing off, never below 20% left); a weapon swap restarts it; Windfury extra attacks don't count as a new swing
  - **Hunters**: the Auto Shot bar is **green** while a Steady Shot is safe to start, **red** where one would delay (clip) the next shot, and **yellow** for the final half-second wind-up, when moving delays the shot
  - **Enhancement weapon sync**: a blue mark on the main-hand bar shows when to press your sync macro (`/cleartarget`, `/targetlasttarget`, `/startattack`) so the off hand lands just after the main hand. The main hand then gets the shared Windfury proc, and close hits share one Flurry charge. It turns green with **SYNC NOW** when it's time, and a readout says *In sync*, *Off hand first* or *Out of sync*. The gap is adjustable (0.15s default), and it warns when your weapon speeds differ
  - **Movable and resizable**: drag the corner grip while unlocked, or pick a width and bar height. `/wmachine swing` shows it for 10 seconds to place it; `/wmachine swing reset` puts it back
- **Flyout buttons** (mage, warlock and shaman buttons), shared options:
  - **Open on hover or on click**
  - **Dock** your class's buttons together in a row or column that moves as one
  - **Lock** them in place
  - Every group's direction can be Up, Right, Down, Left or **Hidden**
  - Nothing opens or moves in combat; changes apply when it ends

#### Warlock

- **Armor check**: warns when Fel Armor, Demon Armor or Demon Skin has fallen off
- **Demonic Sacrifice**: only when you've taken the talent and have no demon out
- **Soul Link**: only when talented, with a living pet and no sacrifice buff
- **Soulstone timers**: reads the real expiry from the buff on everyone in your group, whoever cast it. `/wmachine soulstone` lists who's stoned and for how long
- **Warlock button** (warlock crest), three groups each with its own direction:
  - **Demons**: Felguard (only if talented), Succubus, Imp, Felhunter, Voidwalker
  - **Armors**: Fel Armor, Demon Armor, Demon Skin (highest rank)
  - **Stones & rituals**: Soulwell (Ritual of Souls), Ritual of Summoning, Healthstone, Soulstone (highest rank)
  - Spells that use a Soul Shard show your **shard count**

#### Mage

- **Armor check**: warns when Molten, Mage, Ice or Frost Armor is missing
- **Portal / teleport button**: a portal icon that opens into an icon for every portal and teleport you know, with spell tooltips; click to cast. Portals and teleports each have their own direction, and share a line if they point the same way. Works on non-English clients. `/wmachine portals` lists what it found
- **Mage utility button** (mage crest), highest level nearest the button:
  - **Mana gems**: Emerald, Ruby, Citrine, Jade, Agate
  - **Armors**: Molten, Mage, Ice, Frost
  - **Food & water**: Ritual of Refreshment (table), Conjure Water, Conjure Food
  - Ranked spells show once and cast your highest rank

#### Shaman

- **Totem button**: drops a whole **totem set**, one totem per click, in the order **Air, Water, Earth, then Fire** (fire always last)
  - **Hover** the button to pick a set; its icon and label show the set in use
  - **Click** to drop the next totem (a `/castsequence`, since the game allows one cast per click)
  - **Starts again from Air** when all your totems are gone, when combat ends, or on **Ctrl-click**
  - **Shift-drag** to move it; **right-click** to edit sets
- **Four sets**, premade as **Melee** (Windfury / Mana Spring / Strength of Earth / Searing), **Caster** (Wrath of Air / Mana Spring / Stoneskin / Totem of Wrath), **Healer** (Wrath of Air / Healing Stream / Stoneskin / Searing) and **Tremor** (Windfury / Mana Spring / Tremor / Searing). Each picks the best totem you know, so sets keep working as you level
- **Totem Sets editor** (`/wmachine totems`): rename a set and choose each element's totem, Auto, or None. *Restore premades* puts all four back

#### Paladin

- **Righteous Fury check** for **Protection** paladins (most points in Protection, or Holy Shield / Avenger's Shield): warns when Righteous Fury is missing. Holy and Retribution paladins are never warned

## Dashboard

`/wmachine`, the minimap button, the **Watching Machine** button in the Escape menu, or **Options > AddOns > Watching Machine** opens the dashboard. Everything the addon does can be reached from it.

- One card per module, grouped into **Raid**, **Guild & Social** and **Logging**
- **Sized to fit:** it opens at a size that shows every card, in two or more columns on a short screen
- **Resizable:** drag the bottom-right corner and the cards reflow into columns; **Fit** snaps back to the show-everything size
- **Hover a card** to see what the module does, its full status, and its slash command
- **On/off switch** on cards for modules with a single on/off setting; an off module's icon is greyed out
- **Open** opens the module's window
- **...** or **right-click** opens the module's tools:
  - **Debuff Tracker:** why is my target a boss, exclude / un-exclude target, list and clear exclusions, Shear tallies, shadow resist gear check, encounter callouts
  - **Buff Check:** run a check now, explain buffs on target
  - **ArmorySnap:** snapshot now, list snapshots, scanner status, reset session
  - **PvP Tracker:** leaderboard, request guild sync
  - **Class Tools:** consumable check, soulstone timers (warlock), portal list (mage), swing timer placement, totem set editor (shaman)

## Game Menu Button

- A **Watching Machine** button in the menu Escape opens, just above **Log Out**, opening the dashboard
- With **ElvUI** it sits under ElvUI's button and takes ElvUI's button skin
- Can be turned off in Settings

## Global Theme System

Addon-wide theme support accessible via `/wmachine settings` or the Settings button on the dashboard.

### Available Themes

- **Default**: standard WoW dialog box styling with gold headers and bright status colors
- **ElvUI**: pixel-perfect dark theme with 1px borders, double-border effect, warm gold text, and muted colors. Auto-detected if ElvUI or Tukui is installed

### Theme Coverage

- Dashboard and all module cards
- All module windows, including section headers and separators
- ArmorySnap (follows the global theme)
- Debuff Tracker overlay and indicators
- Live re-skinning: theme changes apply immediately without /reload

### Windows

- Every window fits its contents and is **never taller than your screen**; longer ones scroll
- Positions and collapsed sections are remembered; Escape closes them

## Error Logging

Built-in error capture system for debugging.

- Captures all Watching Machine-related errors with timestamps and stack traces
- Stored in SavedVariables (persists across sessions, max 200 entries)
- `/wmachine errors` - show last 20 errors in chat
- `/wmachine clearerrors` - clear the error log

## Installation

1. Extract the `WatchingMachine` folder to your WoW addons directory:
   - `World of Warcraft\_classic_anniversary_\Interface\AddOns\`
2. Restart WoW or reload UI (`/reload`)

## Usage

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
- `/wmachine encounters` - Open Debuff Tracker settings at Encounter Callouts
- `/wmachine pvp` - Open PvP Enemy Tracker
- `/wmachine recruit` - Open Recruiting Tool
- `/wmachine buffcheck` - Open Buff Check settings
- `/wmachine whybuff` - Show which buff checks your target's auras match
- `/wmachine armory` - Open ArmorySnap gear browser (also `/as`, `/as snap`, `/as list`, ...)
- `/wmachine range` - Open Aura Range alert settings
- `/wmachine exclude` - Stop the debuff tracker treating your target as a boss
- `/wmachine unexclude` - Undo an exclusion for your target
- `/wmachine exclusions` - List excluded NPCs
- `/wmachine whyboss` - Explain how the debuff tracker sees your target
- `/wmachine shear` - Illidan Shear monitor status and tallies (`/wmachine shear on|off` to toggle)
- `/wmachine srcheck` - Show your equipped shadow resist gear
- `/wmachine class` - Open Class Tools (tab per class, your own selected)
- `/wmachine consumes` - Show what the raid consumable checks see
- `/wmachine soulstone` - Soulstone timers in your group (warlock)
- `/wmachine portals` - List the teleports and portals you know (mage)
- `/wmachine totems` - Edit your totem sets (shaman)
- `/wmachine swing` - Show the swing timer for 10 seconds to move or resize it
- `/wmachine swing reset` - Swing timer back to its default place and size
- `/wmachine minimap` - Toggle minimap button visibility
- `/wmachine resetminimap` - Reset minimap button position
- `/wmachine status` - Show status of all modules
- `/wmachine errors` - Show captured error log
- `/wmachine clearerrors` - Clear error log
- `/wmachine help` - Show command help

### Minimap Button

- **Left-click**: Toggle dashboard
- **Right-click**: Settings (theme, minimap)
- **Hover**: every module's status, in dashboard order
- **Drag**: Move button anywhere on screen

## Saved Variables

- `WatchingMachineDB` - Core settings, theme, window positions and sizes, error log
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
- `ArmorySnapDB` - ArmorySnap snapshots and options (shared with the standalone addon, so existing archives carry over)
- `AuraRangeDB` - Aura Range settings
- `ClassToolsDB` - Class Tools feature switches, warning frame and flyout options
- `GeneralChecksDB` - Raid consumable check and mana warning settings
- `MageToolsDB` - Mage button positions and directions
- `WarlockToolsDB` - Warlock button position and directions
- `ShamanToolsDB` - Totem sets and the totem button's position and direction
- `SwingTimerDB` - Swing timer position, size, lock and weapon-sync gap
