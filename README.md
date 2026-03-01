# Watching Machine

**Comprehensive Monitoring Suite for WoW TBC Classic Anniversary**

Version 2.0 | Author: Robert

## Overview

Watching Machine combines eight powerful monitoring and automation tools into a single unified addon with a central dashboard. Updated for The Burning Crusade Classic Anniversary Edition.

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
- Generates Warcraft Logs URLs for each player
- "Scan Raid/Party" button to add all group members

### 6. Guild Invite
Auto-invite guild members to raid when they say the trigger word.
- Responds to trigger word (default: "inv") in guild chat or whispers
- Verifies guild membership before inviting
- Auto-converts party to raid when party reaches 5 members
- Say "raid" or "raid convert" in party/guild to manually convert
- Invite logging with timestamps

### 7. Debuff Tracker
Visual raid debuff monitoring for raid leaders.
- Tracks important debuffs on your target with priority awareness
- Shows visual indicators (green=present, red=missing, yellow=suboptimal)
- **Armor Reduction**: Improved Expose Armor > Expose Armor > Sunder Armor > Faerie Fire
- **Physical Damage**: Blood Frenzy, Savage Combat
- **Shadow Damage**: Shadow Weaving, Curse of Elements
- **Spell Hit**: Misery
- **Fire Damage**: Improved Scorch, Curse of Elements
- **Attack Speed**: Thunder Clap (Improved)
- **AP Reduction**: Demoralizing Shout/Roar
- **Healing Debuff**: Mortal Strike, Wound Poison
- **Hunter's Mark**
- Configurable: show only in raid, show only on boss, categories to track
- Draggable frame, lockable position

### 8. Recruiting Tool *(Officers Only)*
Automated guild recruiting system.
- Scan unguilded players by class and level range (1-70 for TBC)
- Customizable message with %GUILD% placeholder

## Installation

1. Extract the `WatchingMachine` folder to your WoW addons directory:
   - `World of Warcraft\_classic_anniversary_\Interface\AddOns\`
2. Restart WoW or reload UI (`/reload`)

## Usage

### Slash Commands
- `/wmachine` - Toggle the main dashboard
- `/wmachine logger` - Open Auto Logger settings
- `/wmachine keyword` - Open Keyword Monitor
- `/wmachine mail` - Open Mail & Trade Logger
- `/wmachine services` - Open Services Parser
- `/wmachine wcl` - Open Whisper Logs (WCL Lookup)
- `/wmachine ginvite` - Open Guild Invite
- `/wmachine debuff` - Open Debuff Tracker settings
- `/wmachine recruit` - Open Recruiting Tool (Officers only)
- `/wmachine minimap` - Toggle minimap button visibility
- `/wmachine resetminimap` - Reset minimap button position
- `/wmachine status` - Show status of all modules
- `/wmachine help` - Show command help

### Minimap Button
- **Left-click**: Toggle dashboard
- **Drag**: Move button anywhere on screen

## Saved Variables

- `WatchingMachineDB` - Core settings
- `AutoLoggerDB` - Auto Logger settings
- `KeywordMonitorDB` - Keyword Monitor data
- `MailLoggerDB` - Mail & Trade logs
- `ServicesParserDB` - Services Parser settings
- `WhisperLogsDB` - Whisper Logs data
- `GuildInviteDB` - Guild Invite settings and log
- `DebuffTrackerDB` - Debuff Tracker settings
- `RecruitingToolDB` - Recruiting Tool data

## Changelog

### Version 2.0
- Updated for TBC Classic Anniversary Edition
- Added Guild Invite module (auto-invite on "inv" trigger)
- Added Debuff Tracker module (raid debuff monitoring with priority)
- Added TBC dungeons to Services Parser
- Minimap button now freely movable anywhere on screen
- Fixed GetInboxItem API for TBC (itemID return value)
- Added Test Message button to Recruiting Tool
- Added nil safety checks throughout all modules
