# Release announcement — Watching Machine 3.9

Copy-paste ready text for Discord and CurseForge. The canonical, full-detail
changelog lives in [`CHANGELOG.md`](../CHANGELOG.md).

> 3.5.1 through 3.8 shipped without a release post. Their highlights are
> included below, since they are new to anyone upgrading from 3.5.

---

# ═══════════════  DISCORD  ═══════════════

Discord caps messages at 2000 characters, so this is split into three posts.
Send them in order — each is self-contained and under the limit. Discord
markdown supports `#`/`##`/`###` headers, `**bold**`, `` `code` `` and lists,
but **not** tables.

---

## ▸ Discord post 1 of 3

```
# 🧭 Watching Machine 3.9 is out

Every window in the addon has been rebuilt on one shared layout. Same settings, same features — but they all behave the same way now.

## 🪟 Every window now…
- **Closes on Escape.** Before, only ArmorySnap did
- **Remembers where you put it.** Windows that already saved their spot keep it
- **Fits your screen.** Nothing runs off the bottom at bigger UI scales any more — long windows scroll, list windows give the list whatever room is left
- **Explains itself.** Hover any setting whose effect isn't obvious for a tooltip. Mail & Trade, Guild Invite and Recruiter had none at all before
- **Follows your theme**, ArmorySnap included

## ✨ Things you'll notice
- **Mail & Trade** and **Services Parser** finally show which tab you're on
- **Services Parser** settings are a section of its window now, not a separate pop-up
- **Debuff Tracker** is one window again: Encounter Callouts (Illidan Doom & Shear, the Black Temple SR check) are a section of it. `/wmachine encounters` jumps straight there
- **Keyword Monitor**, **PvP Tracker** and **Debuff Tracker** have collapsible sections
- **Class Tools** scrolls when your class has a lot of checks
- Text boxes save when you click away, not just on Enter. Escape puts the old value back
```

---

## ▸ Discord post 2 of 3

```
## 🎛️ The dashboard got smarter (3.8)
`/wmachine` is now the one place to find everything:
- Cards are grouped: **Raid**, **Guild & Social**, **Logging**
- **Hover a card** to see what the module does, its full status and its command
- **On/off switch** right on the card for Buff Check, Debuff Tracker, Aura Range, ArmorySnap auto-scan, Guild Invite, PvP Tracker and Keyword Monitor. Off modules go grey
- **`...` or right-click a card** for its tools — the stuff that used to be slash-command only: *why is my target a boss*, exclusions, Shear tallies, SR gear check, explain buffs, run a buff check, take a snapshot, soulstone timers, portal list…

Other ways in:
- **Minimap right-click** now opens Settings (left-click is still the dashboard)
- **Options → AddOns → Watching Machine** has a page with an Open Dashboard button

## 🍲 Food check fixes (3.5.1 / 3.6)
- **Skullfish Soup counts as food.** It gives *Enlightened*, not Well Fed, so anyone on soup was being called unfed. Fixed in both the ready-check audit and the in-raid warning
- Buff Check's food check is now called **Food Buff** and is **on by default**. It was switched on once for everyone — turn it off on its card if you don't want it
```

---

## ▸ Discord post 3 of 3

```
## 🧹 Smaller fixes along the way
- **PvP Tracker** window no longer runs off the bottom of the screen
- **Mail & Trade** stopped leaking memory every time its list refreshed
- **PvP leaderboard** points column no longer cut off
- **Guild Invite** log updates while the window is open
- **Aura Range** Test Alert no longer stacks duplicate lines
- Switching theme recolours headers in already-open windows
- **ArmorySnap**: new **Auto-scan** checkbox (and `/as auto`) to stop automatic raid scanning without disabling the module. Manual `/as snap` still works
- **Mages**: new **Lock the portal button** option in Class Tools

## ⬆️ Upgrading
- Settings carry over, no reset needed
- **ArmorySnap now follows the global theme.** Its own ElvUI checkbox is gone — change the look in `/wmachine settings` (right-click the minimap button)
- **Minimap right-click** opens Settings now, not the dashboard
- The **Food Buff** ready-check is on — switch it off on the Buff Check card if your raid doesn't want it
- Windows that never remembered their position open centred the first time, then stay where you put them

⬇️ CurseForge or GitHub. Full changelog in the repo.
```

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.9

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Every window in the addon is now built on one shared panel layout, so they
all close on Escape, remember their position, fit the screen and explain
their settings. This post also covers 3.5.1 through 3.8, which shipped
without one.

### At a glance

| | |
|---|---|
| **Every window** | Escape to close, remembered position, never taller than the screen, tooltips throughout |
| **Debuff Tracker** | Settings and Encounter Callouts in one window again, with collapsible sections |
| **Dashboard** | Grouped cards, on/off switches, a tools menu per module, hover descriptions |
| **Food check** | Skullfish Soup (*Enlightened*) counts; Food Buff check on by default |
| **ArmorySnap** | Follows the global theme; new Auto-scan switch |
| **Other ways in** | Minimap right-click for Settings; Options → AddOns page |

### Every window rebuilt on one layout (3.7 – 3.9)

The dashboard, Settings and every module window — Auto Logger, Keyword
Monitor, Mail & Trade, Services Parser, WarcraftLogs Lookup, Guild Invite,
Debuff Tracker, PvP Tracker and its leaderboard, Recruiter, Buff Check,
ArmorySnap, Aura Range and Class Tools — now share one panel layout instead
of each being laid out by hand. Every window:

- **closes on Escape** (previously only ArmorySnap did);
- **remembers where you put it** — windows that already saved a position
  keep it;
- **never grows taller than the screen** — long windows scroll, and list
  windows give the list whatever room is left;
- **has tooltips** on every control whose effect isn't obvious from its
  label. Mail & Trade, Guild Invite and Recruiter had none before;
- **follows the global theme**, ArmorySnap included, and restyles in place
  when you switch.

Text boxes now save when you click away as well as on Enter, and Escape
restores the saved value.

Window by window:

| Window | What changed |
|---|---|
| **Debuff Tracker** | Settings and Encounter Callouts are one scrolling window with collapsible sections; the debuff list is no longer squeezed into a small box; `/wmachine encounters` opens it at the callouts |
| **PvP Tracker** | Fits the screen; Guild Sync and Leaderboard collapse to give the KOS list more room |
| **Keyword Monitor** | Collapsible Keywords / Channels / Alerts sections; can't be resized taller than the screen |
| **Services Parser** | The current dungeon tab is marked, with listing counts; settings are a section of the window instead of a pop-up |
| **Mail & Trade** | The current tab is marked; no longer leaks frames on every refresh |
| **Recruiter** | All three windows rebuilt; messages and history open beside the main window |
| **Class Tools** | Scrolls when a class has many checks |
| **PvP leaderboard** | Points column no longer cut off; position saved |
| **Guild Invite** | The log updates while the window is open; roster count in the footer |
| **Aura Range** | Test Alert no longer stacks duplicate lines |

### Dashboard (3.8)

- Cards grouped into **Raid**, **Guild & Social** and **Logging**.
- **Hover a card** for a description of the module, its full status and
  its slash command.
- **On/off switch** on the card for Buff Check, Debuff Tracker, Aura Range,
  ArmorySnap (auto-scan), Guild Invite, PvP Tracker and Keyword Monitor
  (pause, for the session). It's the same switch as the one in the module's
  own window. Switched-off modules are greyed out.
- **Tools menu** (the `...` button, or right-click the card) for the
  diagnostics that used to be slash-command only. Destructive ones ask
  first, and class-specific ones only appear on that class.

| Module | Tools |
|---|---|
| Debuff Tracker | Encounter callouts, why is my target a boss, exclude / un-exclude target, list / clear exclusions, Shear tallies, shadow resist gear check |
| Buff Check | Run a check now (only you see it), explain buffs on target |
| ArmorySnap | Snapshot now, list snapshots, scanner status, reset session |
| PvP Tracker | Leaderboard, request guild sync |
| Class Tools | Consumable check; soulstone timers (warlock); portal list (mage) |

- **Minimap button:** right-click opens Settings, and the tooltip lists every
  module's status.
- **Options → AddOns → Watching Machine:** a page in the game's own options
  with Open Dashboard and Theme & Minimap buttons.

### Food check (3.5.1, 3.6)

- **Skullfish Soup now counts as a food buff.** It is a drink that applies
  *Enlightened* (20 crit rating and 20 Spirit) rather than *Well Fed*, so
  players on it were reported as unfed. Both the ready-check audit and the
  Class Tools in-raid warning accept either buff, from one shared list.
- Buff Check's *Well Fed* check is renamed **Food Buff** and is now **on by
  default**. Existing installs were switched on once; if you turn it off, it
  stays off.

### ArmorySnap

- Follows the global Watching Machine theme. Its own *ElvUI Theme* checkbox
  is retired; `/as theme` now points to `/wmachine settings`.
- New **Auto-scan** checkbox and `/as auto` stop automatic raid scanning
  without disabling the module. Manual `/as snap` works either way.

### Other fixes

- The PvP Tracker window no longer runs off the bottom of the screen.
- Theme changes recolour section headers in windows that are already open.
- Mages: **Lock the portal button** option in Class Tools.
- `/wmachine help` now lists `status`, `clearexclusions` and ArmorySnap's
  `/as` sub-commands, which were missing.

### New and changed commands

| Command | |
|---|---|
| `/as auto` | **New** — toggle ArmorySnap's automatic scanning |
| `/wmachine encounters` | Now opens Debuff Tracker settings at the Encounter Callouts section |
| `/as theme` | Now says ArmorySnap follows the global theme |

### Upgrade notes

- Existing settings and saved data carry over; no reset needed.
- **ArmorySnap now follows the global theme.** If you used its own ElvUI
  checkbox, set the theme in `/wmachine settings` instead.
- **Minimap right-click** now opens Settings rather than the dashboard.
- The **Food Buff** ready-check is on. Switch it off on the Buff Check card
  if your raid doesn't want it.
- Windows that never remembered their position before open centred the
  first time, then stay where you leave them.
