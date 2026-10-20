# Changelog announcement — Watching Machine 2.9 to 3.11

Copy-paste ready text for Discord and CurseForge, covering every release
from 2.9 to 3.11 in one go. The canonical, full-detail changelog lives in
[`CHANGELOG.md`](../CHANGELOG.md).

---

# ═══════════════  DISCORD  ═══════════════

Discord caps a message at 2000 characters, so this is split into seven
posts, newest first. Paste the text *inside* each code block as its own
message, in order. Every post is under 1900 characters (counted the way
Discord counts, where an emoji takes two), so there is headroom for small
edits. Discord markdown supports `#`/`##`/`###` headers, `**bold**`,
`` `code` `` and lists, but **not** tables.

---

## ▸ Discord post 1 of 7

```
# 📜 Watching Machine — everything from 2.9 to 3.11

Sixteen releases' worth in one place, newest first. Settings carry over through all of them, no reset needed.

## 3.11 — Premade chat filters
Chat Filter now has one-tick filters for the usual spam:
- **GDKP**
- **Guild Loot Run**
- **Gear Carry** (also catches "gear carries")
They're off until you tick them, kept apart from your own phrase list, and each shows how many messages it has hidden this session.

## 3.10 — New: Chat Filter 🔇
`/wmachine filter` hides chat messages containing phrases you choose.
- A phrase matches anywhere in a message, ignoring caps, colours, item-link brackets and extra spaces. Plain text, no wildcards
- Public channels by default; say/yell and whispers optional
- Your own messages are never hidden
- **Applied before Keyword Monitor.** Spam you filter is never checked for keywords, so it can't trigger a match. Both windows say so
- Dashboard card with an on/off switch

Also: the **Class Tools** card now shows **your class crest**. The old icon was a Wrath achievement icon that doesn't exist in TBC.
```

---

## ▸ Discord post 2 of 7

```
## 3.9 — Every window rebuilt
All windows now share one layout, so they all:
- **close on Escape** (before, only ArmorySnap did)
- **remember where you put them**
- **fit your screen**: long windows scroll, list windows give the list the leftover room
- **have tooltips** on every setting that isn't obvious. Mail & Trade, Guild Invite and Recruiter had none
- **follow your theme**, ArmorySnap included. Its own ElvUI checkbox is gone

Also: Mail & Trade and Services Parser **mark the current tab**. Services Parser's settings moved into its window. Text boxes save when you click away. Mail & Trade stopped leaking memory.

## 3.8 — A smarter dashboard 🎛️
- Cards grouped into **Raid**, **Guild & Social** and **Logging**
- **Hover a card** for what it does, its status and its command
- **On/off switch** on the card for modules that have one; off modules go grey
- **`...` or right-click** a card for its tools. These are the things that used to be slash-only: why-is-this-a-boss, exclusions, Shear tallies, SR gear check, explain buffs, take a snapshot, soulstones, portals…
- **Minimap right-click** opens Settings
- New page under **Options → AddOns**
```

---

## ▸ Discord post 3 of 7

```
## 3.7 — Debuff Tracker is one window again
- Settings and **Encounter Callouts** are back in one scrolling window, with sections you can collapse
- The debuff list isn't squeezed into a tiny box any more
- `/wmachine encounters` jumps straight to the callouts
- PvP Tracker's Guild Sync and Leaderboard sections collapse to give the KOS list room

## 3.6 — Food check on, and fixes
- Buff Check's **Food Buff** check is now **on by default**. It was switched on once for everyone; turn it off on its card if your raid doesn't want it
- Windows can't grow taller than the screen at big UI scales
- **ArmorySnap:** new **Auto-scan** checkbox and `/as auto`, to stop automatic raid scanning without turning the module off
- **Mages:** "Lock the portal button" option

## 3.5.2 — Window fixes
- Escape closes every window
- PvP Tracker no longer runs off the bottom of the screen
- Theme changes recolour headers in open windows
- `/wmachine help` lists the commands it was missing

## 3.5.1 — Skullfish Soup 🍲
Skullfish Soup gives **Enlightened**, not Well Fed, so people on it were called unfed. Both food checks now accept either, from one shared list.
```

---

## ▸ Discord post 4 of 7

```
## 3.5 — Class Tools gets real features 🧙
Everything feeds **one movable CHECK YOURSELF frame**, not a window per check.
**Warlock**
- Armor missing (Fel / Demon Armor / Demon Skin)
- Demonic Sacrifice: only when talented *and* no demon is out
- Soul Link: only when talented, with a living pet
- `/wmachine soulstone` lists who's stoned and for how long

**Mage**
- Armor missing (Molten / Mage / Ice / Frost)
- **Portal button**: one draggable button that expands into every teleport and portal you know (not in combat)

**General** (every class, in raid instances, 25-man only by default)
- Flask, food buff and weapon oil / stone
- `/wmachine consumes` shows what it sees

## 3.4 — Class Tools framework + mailbox fix 📬
- `/wmachine class` opens a tab per class, with yours selected
- **Open All no longer logs duplicate mail.** The log works out what you collected by comparing the inbox before and after
- The dashboard card list scrolls, so no module is cut off
```

---

## ▸ Discord post 5 of 7

```
## 3.3 — Black Temple shadow resist check 🛡️
After Mother Shahraz, it warns you if you pull the Grand Promenade still wearing shadow resist gear.
- Reads **equipped gear only**, so Shadow Protection or an SR aura can't cause a false warning
- Default threshold is 60 SR from gear, so one odd piece is ignored
- Local flash and sound; optional say / party / raid / `/rw`
- Still works after a `/reload` past Mother
- `/wmachine srcheck` shows exactly what it detects

Debuff Tracker settings had grown taller than the screen, so callouts got their own window (merged back in 3.7). The Shear throttle and pull summary got their missing controls.

## 3.2 — Illidan helpers 👹
- **Shear monitor**: calls out Shear on the main tank, hit or avoided, which damage meters miss. It deduplicates each cast, has an optional cast warning, a per-pull summary and a choice of channel. `/wmachine shear` shows the tallies
- **Doom warning**: raid-warns **CAST DOOM NOW** at 68% so warlocks land Curse of Doom before 65%
- Only the raid leader sends either to chat (or assists, if allowed)

**Buff Check:** elixir lists fixed (Empowerment and Major Defense are Guardian), Unstable Flasks detected, and new `/wmachine whybuff`.
```

---

## ▸ Discord post 6 of 7

```
## 3.1 — No more boss alerts on trash 🎯
TBC raid trash is the same level and elite status as bosses, so trash such as Magtheridon's Hellfire Warders was triggering boss alerts.
- Mobs are now identified by their creature ID, not by name
- **Health floor**: mobs under 150k max health (adjustable) are never treated as bosses
- **Focus tracking**: on council fights, alerts only fire for the mob your raid is actually killing, and follow the raid if the kill order changes
- `/wmachine exclude` / `unexclude` / `exclusions` let you fix a false boss by hand
- `/wmachine whyboss` explains how the tracker sees your target

## 3.0 — New: Aura Range 📡
Warns the moment you walk out of range of a party aura or shaman totem you were getting (Moonkin, Leader of the Pack, Trueshot, paladin auras, Windfury, Strength of Earth, Mana Spring…).
- A movable alert lists exactly which auras you lost, and clears when you step back in
- No false alarms while dead, when the provider is dead, or on zoning
- `/wmachine range`

**Buff Check:** new **Battle and Guardian Elixir** checks (a flask counts for both), and a PallyPower fix for players with a single-target blessing assigned.
```

---

## ▸ Discord post 7 of 7

```
## 2.9 — ArmorySnap joins Watching Machine 🛡️
The standalone ArmorySnap addon is now built in.
- Quietly snapshots every raid member's gear, enchants and gems
- **Fast scanning**: a full 25-man in range is captured in about 15–20 seconds (it used to take over 75)
- Players who were out of range are retried after 15s instead of 2 minutes
- Paper-doll browser with real tooltips; Shift-click links items
- Talent trees, enchant/gem summary, snapshots kept for 1–30 days
- Your old ArmorySnap archive carries over. If the standalone addon is still enabled, the built-in one steps aside to avoid inspect fights
- `/as` or `/wmachine armory`

## ⬆️ Upgrading from anything since 2.9
- Settings and saved data carry over. Windows that already saved their spot keep it
- **ArmorySnap follows the global theme** now. Set it in `/wmachine settings`
- **Minimap right-click** opens Settings; left-click is still the dashboard
- The **Food Buff** ready-check is on. Switch it off on the Buff Check card if you don't want it
- Chat Filter's premades are **off** until you tick them

⬇️ CurseForge or GitHub. Full changelog in the repo.
```

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 2.9 – 3.11

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Every release from 2.9 to 3.11, newest first. Settings and saved data
carry over through all of them.

### At a glance

| Version | Headline |
|---|---|
| **3.11** | Premade chat filters: GDKP, Guild Loot Run, Gear Carry |
| **3.10** | New **Chat Filter** module, applied before Keyword Monitor; class crest on the Class Tools card |
| **3.9** | Every window on one layout: Escape to close, remembered position, fits the screen, tooltips throughout |
| **3.8** | Dashboard: grouped cards, on/off switches, tools menus, hover descriptions, Options → AddOns page |
| **3.7** | Debuff Tracker settings and Encounter Callouts in one window again |
| **3.6** | Food Buff check on by default; windows never taller than the screen; ArmorySnap Auto-scan; Mage portal lock |
| **3.5.2** | Escape closes every window; PvP Tracker fits the screen; theme fixes |
| **3.5.1** | Skullfish Soup (*Enlightened*) counts as food |
| **3.5** | Class Tools: Warlock, Mage and General consumable checks |
| **3.4** | Class Tools framework; mailbox Open All duplicates fixed |
| **3.3** | Black Temple shadow resist gear check |
| **3.2** | Illidan Shear monitor and Doom warning; elixir fixes |
| **3.1** | Boss detection rebuilt: no more alerts on raid trash |
| **3.0** | New **Aura Range** module; Battle / Guardian elixir checks |
| **2.9** | **ArmorySnap** integrated as a module |

---

### 3.11 — Premade chat filters

A **Premade filters** section in the Chat Filter window, one tick each:

| Premade | Hides messages containing |
|---|---|
| **GDKP** | `GDKP` |
| **Guild Loot Run** | `Guild Loot Run` |
| **Gear Carry** | `Gear Carry`, `Gear Carries` |

- Off by default.
- Kept apart from your own phrase list, so switching one off brings those
  messages straight back.
- Each shows its hidden count for the session.
- Applied before Keyword Monitor, like every filter.
- Listed in the Chat Filter card's *Hidden this session* tool.

### 3.10 — New module: Chat Filter

`/wmachine filter` (also `/wmachine cf`) hides chat messages containing
phrases you choose.

- **Matching:** a phrase matches anywhere in a message, ignoring case,
  colour codes, item-link brackets and extra spaces. Plain text, no
  wildcards.
- **Where it applies:** public channels by default; say/yell and whispers
  optional. Your own messages are never hidden.
- **Applied before Keyword Monitor.** Keyword Monitor reads chat through its
  own handler, so it now asks Chat Filter first. Filtered spam is never
  checked for keywords. Both windows show this warning.
- Per-phrase and total hidden counts for the session.
- Dashboard card with an on/off switch. Saved in the new `ChatFilterDB`.

The **Class Tools** dashboard card now shows your class crest. The old icon
was a Wrath achievement icon that doesn't exist in the TBC client.

### 3.9 — Every window on one layout

The dashboard, Settings and every module window now share one panel
layout instead of each being laid out by hand. Every window:

- **closes on Escape** (previously only ArmorySnap did);
- **remembers where you put it**, and windows that already saved a position
  keep it;
- **fits the screen**: long windows scroll, list windows give the list the
  leftover room;
- **has tooltips** on every non-obvious control (Mail & Trade, Guild Invite
  and Recruiter had none);
- **follows the global theme**, ArmorySnap included. Its private ElvUI
  checkbox is retired and `/as theme` points to `/wmachine settings`.

| Window | What changed |
|---|---|
| Services Parser | Current dungeon tab marked, with counts; settings moved into a section of the window |
| Mail & Trade | Current tab marked; no longer leaks frames on every refresh |
| Keyword Monitor | Collapsible sections; can't be resized taller than the screen |
| Recruiter | All three windows rebuilt; messages and history open beside the main window |
| Class Tools | Scrolls when a class has many checks |
| PvP leaderboard | Points column no longer cut off; position saved |
| Guild Invite | Log updates while open; roster count in the footer |
| Aura Range | Test Alert no longer stacks duplicate lines |

Text boxes now save when you click away as well as on Enter, and Escape
restores the saved value.

### 3.8 — Dashboard

- **Groups:** cards are grouped into **Raid**, **Guild & Social** and
  **Logging**.
- **Hover a card** for a description, its full status and its slash
  command.
- **On/off switch** on the cards of modules that have one. Switched-off
  modules are greyed out.
- **Tools menu** (`...` or right-click) for the diagnostics that were
  slash-only. Destructive tools ask first.

| Module | Tools |
|---|---|
| Debuff Tracker | Encounter callouts, why is my target a boss, exclude / un-exclude, list / clear exclusions, Shear tallies, SR gear check |
| Buff Check | Run a check now, explain buffs on target |
| ArmorySnap | Snapshot now, list snapshots, scanner status, reset session |
| PvP Tracker | Leaderboard, request guild sync |
| Class Tools | Consumable check; soulstones (warlock); portals (mage) |

- **Minimap button:** right-click opens Settings.
- **Options → AddOns → Watching Machine:** a page in the game's own
  options.

### 3.7 — Debuff Tracker in one window

- **One window again:** settings and Encounter Callouts are back together in
  one scrolling window, with collapsible sections (Auto-Detection, Alerts,
  Target Filtering, Encounter Callouts, Debuff Selection).
- **Debuff list:** no longer squeezed into a small inner box.
- `/wmachine encounters` opens the window at the callouts.
- **PvP Tracker:** Guild Sync and Leaderboard collapse to give the KOS list
  more room.

### 3.6

- **Food Buff on by default.** Buff Check's Food Buff check is now on by
  default, and was switched on once for existing installs. Turning it off
  sticks.
- **Window heights:** windows never grow taller than the screen at larger UI
  scales.
- **ArmorySnap:** new **Auto-scan** checkbox and `/as auto`. Manual
  snapshots work either way.
- **Mage:** **Lock the portal button** option.

### 3.5.2

- **Escape** closes every Watching Machine window.
- **PvP Tracker:** the window no longer runs off the bottom of the screen.
- **Themes:** theme changes recolour section headers in open windows.
- **Services Parser:** its settings window can't be dragged off screen.
- **Help:** `/wmachine help` lists the commands it was missing.

### 3.5.1 — Skullfish Soup

Skullfish Soup is a drink that gives **Enlightened** (crit and Spirit), not
*Well Fed*, so players on it were reported as unfed. The ready-check food
check (renamed **Food Buff**) and the Class Tools in-raid warning now accept
either buff, from one shared list.

### 3.5 — Class Tools features

All checks feed **one movable *CHECK YOURSELF* frame**.

- **Warlock**
  - Armor missing.
  - Demonic Sacrifice: only when talented *and* no demon is out.
  - Soul Link: only when talented, with a living pet.
  - `/wmachine soulstone` lists active soulstones and their timers.
- **Mage**
  - Armor missing.
  - **Portal button:** one draggable button that expands into every
    teleport and portal you know. It doesn't open in combat.
  - `/wmachine portals` lists them.
- **General**, for every class, inside raid instances and 25-man only by
  default
  - Flask, food buff and weapon oil / stone.
  - `/wmachine consumes` shows what the checks see.

### 3.4

- **Class Tools framework:** `/wmachine class` opens a tab per class, with
  yours selected, and per-feature switches saved per class.
- **Mail & Trade:** Open All no longer produces duplicate log entries. What
  you collected is worked out by comparing the inbox, which is immune to
  retries and shifting mail positions.
- **Dashboard:** the card list scrolls, so no module card is cut off.

### 3.3 — Black Temple shadow resist gear check

After Mother Shahraz, it warns you if you pull the Grand Promenade still
wearing shadow resist gear.

- **Gear only:** it reads equipped gear, so buffs and auras can't cause a
  false warning.
- **Threshold:** default 60 SR from gear.
- **Warning:** a local flash and sound, plus an optional say / party / raid
  / `/rw` announce.
- **After a reload:** it still arms if you `/reload` once Mother is dead.
- `/wmachine srcheck` shows exactly what it detects.
- **Settings:** the Shear chat throttle and pull summary got their missing
  controls.

### 3.2 — Illidan

- **Shear monitor**
  - Calls out Shear on the main tank, whether hit or avoided, which damage
    meters under-report.
  - Each cast is called once.
  - Optional cast warning, per-pull summary, and a choice of channel.
  - `/wmachine shear` shows the tallies.
- **Doom warning**
  - Raid-warns **CAST DOOM NOW** at 68% so warlocks land Curse of Doom
    before the 65% lift-off.
- Only the raid leader (or assistants, if allowed) sends either to chat.
- **Buff Check**
  - Elixir of Empowerment and Elixir of Major Defense are classed as
    Guardian.
  - Unstable Flasks are detected.
  - New `/wmachine whybuff`.

### 3.1 — Boss detection

TBC raid trash is the same level and elite status as bosses, so trash
triggered boss alerts.

- **Creature IDs:** mobs are identified by their creature ID, not their
  name.
- **Health floor:** mobs under 150k max health (adjustable, 0 = off) are
  never bosses.
- **Focus tracking:** on multi-boss fights, alerts only fire for the mob
  the raid is actually damaging, and follow the raid when the kill order
  changes.
- `/wmachine exclude`, `unexclude` and `exclusions` manage false bosses by
  hand; `/wmachine whyboss` explains how the tracker sees your target.

### 3.0 — New module: Aura Range

- **Alerts:** warns when you walk out of range of a party aura or shaman
  totem you were getting, with a movable alert listing what you lost. It
  clears when you step back in.
- **Each aura toggleable:** Moonkin, Leader of the Pack, Trueshot, Tree of
  Life, paladin auras, and the common totems.
- **No false alarms** while dead, when the provider is dead or gone, on
  zoning, or after leaving the group.
- `/wmachine range`.
- **Buff Check:**
  - **Battle and Guardian Elixir** checks, where a flask counts for both.
  - PallyPower fix: a single-target blessing now replaces that paladin's
    class blessing for that player.

### 2.9 — ArmorySnap integrated

The standalone ArmorySnap addon is now a Watching Machine module.

- **Snapshots:** passively records every raid member's gear, enchants and
  gems.
- **Fast scanning:** a full 25-man in range is captured in about 15–20
  seconds instead of 75+. Players who were out of range are retried after
  15s instead of 120s.
- **Browser:** a paper doll with native tooltips; Shift-click links items.
- **More detail:** talent trees, an enchant/gem summary, and snapshot
  retention of 1–30 days.
- **Archive:** your standalone ArmorySnap archive carries over.
- **No conflicts:** if the standalone addon is still enabled, the built-in
  module stands down to avoid inspect conflicts.
- `/as` or `/wmachine armory`.

### New commands since 2.9

| Command | Does | Since |
|---|---|---|
| `/wmachine filter` | Chat Filter | 3.10 |
| `/as auto` | Toggle ArmorySnap automatic scanning | 3.6 |
| `/wmachine class` | Class Tools | 3.4 |
| `/wmachine soulstone` | Soulstone timers (warlock) | 3.5 |
| `/wmachine portals` | Known portals and teleports (mage) | 3.5 |
| `/wmachine consumes` | What the consumable checks see | 3.5 |
| `/wmachine srcheck` | Shadow resist gear check | 3.3 |
| `/wmachine encounters` | Debuff Tracker settings at Encounter Callouts | 3.3 |
| `/wmachine shear` | Shear monitor status and tallies | 3.2 |
| `/wmachine whybuff` | Which buff checks your target's auras satisfy | 3.2 |
| `/wmachine exclude` / `unexclude` / `exclusions` / `whyboss` | Boss detection tools | 3.1 |
| `/wmachine range` | Aura Range | 3.0 |
| `/wmachine armory`, `/as` | ArmorySnap | 2.9 |

### Upgrade notes

- **Settings carry over:** existing settings and saved data are kept, with
  no reset needed.
- **ArmorySnap theme:** ArmorySnap now follows the global theme. If you used
  its own ElvUI checkbox, set the theme in `/wmachine settings`.
- **Minimap button:** right-click now opens Settings rather than the
  dashboard.
- **Food Buff:** the ready-check is on. Switch it off on the Buff Check card
  if your raid doesn't want it.
- **Chat Filter premades:** these are off until ticked.
