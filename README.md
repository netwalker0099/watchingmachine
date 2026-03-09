# Watching Machine

**Comprehensive Monitoring Suite for WoW TBC Classic Anniversary**

Version 2.6 | Author: Robert

## Overview

Watching Machine combines nine powerful monitoring and automation tools into a single unified addon with a central dashboard. Updated for The Burning Crusade Classic Anniversary Edition.

## Security

This addon is restricted to **<Socks and Sandals>** guild members only.

- **Non-members**: Addon will not load, minimap button hidden, slash commands disabled
- **Guild Members**: Full access to all monitoring modules
- **Officers/GM Only**: Recruiting Tool is restricted to guild officers and the guild master

## Modules

### 1. Auto Logger
Automatically manages chat and combat logging.
- Enables chat logging on login
- Automatically enables combat logging in raid instances (10/25-man for TBC)
- Optional logging in 5-man dungeons

### 2. Keyword Monitor
Monitor public channels for specific keywords with duplicate detection.
- Monitor Trade, General, LFG, and other channels
- 5-minute result retention with deduplication
- Sound and chat alerts

### 3. Mail & Trade Logger
Long-term logging of items and gold received via mail and trades.
- Logs gold, items, and auction house transactions
- Multi-character support with character selector
- Filter by Gold, Items, AH Sales, AH Buys, Expired

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
- Generates correct classic.warcraftlogs.com URLs per region (US/EU/KR/TW/CN)
- "Scan Raid/Party" button to add all group members with correct realms
- Shows detected server in UI header, cross-server players tagged with realm name
- Click to copy URL, right-click to remove

### 6. Guild Invite
Auto-invite guild members to raid when they say the trigger word.
- Responds to trigger word (default: "inv") in guild chat or whispers
- Verifies guild membership before inviting
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

### 9. Recruiting Tool *(Officers Only)*
Automated guild recruiting system.
- Scan unguilded players by class and level range (1-70 for TBC)
- Customizable message with %GUILD% placeholder

## Global Theme System

Addon-wide theme support accessible via `/wmachine settings` or the Settings button on the dashboard.

### Available Themes
- **Default**: Standard WoW dialog box styling with gold headers and bright status colors
- **ElvUI**: Pixel-perfect dark theme with 1px borders, double-border effect, warm gold text, and muted colors. Auto-detected if ElvUI or Tukui is installed.

### Theme Coverage
- Dashboard and all module cards
- All module settings panels (8 modules)
- Debuff Tracker overlay and indicators
- Live re-skinning: theme changes apply immediately without /reload

## Error Logging

Built-in error capture system for debugging.
- Captures all WatchingMachine-related errors with timestamps and stack traces
- Stored in SavedVariables (persists across sessions, max 200 entries)
- `/wmachine errors` - show last 20 errors in chat (works even if not authorized)
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
- `/wmachine mail` - Open Mail & Trade Logger
- `/wmachine services` - Open Services Parser
- `/wmachine wcl` - Open Whisper Logs (WCL Lookup)
- `/wmachine ginvite` - Open Guild Invite
- `/wmachine debuff` - Open Debuff Tracker settings
- `/wmachine pvp` - Open PvP Enemy Tracker
- `/wmachine recruit` - Open Recruiting Tool (Officers only)
- `/wmachine minimap` - Toggle minimap button visibility
- `/wmachine resetminimap` - Reset minimap button position
- `/wmachine status` - Show status of all modules
- `/wmachine errors` - Show captured error log
- `/wmachine clearerrors` - Clear error log
- `/wmachine help` - Show command help

### Minimap Button
- **Left-click**: Toggle dashboard
- **Drag**: Move button anywhere on screen

## Saved Variables

- `WatchingMachineDB` - Core settings, theme, error log
- `AutoLoggerDB` - Auto Logger settings
- `KeywordMonitorDB` - Keyword Monitor data
- `MailLoggerDB` - Mail & Trade logs
- `ServicesParserDB` - Services Parser settings
- `WhisperLogsDB` - Whisper Logs data
- `GuildInviteDB` - Guild Invite settings and log
- `DebuffTrackerDB` - Debuff Tracker settings
- `PvPTrackerDB` - PvP Enemy Tracker data and enemy list
- `RecruitingToolDB` - Recruiting Tool data

## Changelog

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
