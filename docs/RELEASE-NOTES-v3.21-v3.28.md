# Changelog announcement — Watching Machine 3.21 to 3.28

Copy-paste ready text for CurseForge, covering 3.21, 3.22, 3.23, 3.24,
3.25, 3.26, 3.26.1, 3.27 and 3.28. The canonical, full-detail changelog
lives in [`CHANGELOG.md`](../CHANGELOG.md). Earlier releases:
[`RELEASE-NOTES-v3.16-v3.21.md`](RELEASE-NOTES-v3.16-v3.21.md),
[`RELEASE-NOTES-v3.11.3-v3.13.md`](RELEASE-NOTES-v3.11.3-v3.13.md),
[`RELEASE-NOTES-v3.11-v3.11.2.md`](RELEASE-NOTES-v3.11-v3.11.2.md) and
[`RELEASE-NOTES-v2.9-v3.11.md`](RELEASE-NOTES-v2.9-v3.11.md).

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.28

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Covers 3.21 through 3.28. It adds five new modules:
- an **Instance Tracker** with lockouts
- **Your Characters**
- a **Battlegrounds & Arenas** log
- **World Timers** (layers, Terokkar towers, dailies, Darkmoon Faire)
- **gold trade alerts**

There are also **alert sounds** and a **resizable dashboard**. Watching
Machine can now read **Nova Instance Tracker** and **Nova World Buffs**
users' shared data (listen only). Settings and saved data carry over, with
no reset needed.

### At a glance

| Version | Headline |
|---|---|
| **3.28** | New **World Timers**: your layer, Terokkar tower resets, today's dailies, Darkmoon Faire and your Sayge cooldown, world buffs, Songflowers |
| **3.27** | New **Your Characters** window and **Battlegrounds & Arenas** log |
| **3.26 / 3.26.1** | **Alert sounds** for the mana potion and rune warnings, with new Potion and Rune sounds |
| **3.25** | **Gold trade alerts**, and trades record the instance you were in |
| **3.24** | Instance Tracker chat lines are **clickable**, with a red **X** to delete a run |
| **3.23** | Shows **reset notices from Nova Instance Tracker** users |
| **3.22** | New **Instance Tracker**: lockouts and a log of every run |
| **3.21** | The **dashboard is resizable** and opens showing every module |

---

### 3.22 – 3.24 — Instance Tracker

A log of every dungeon and raid you enter, on all your characters, and the
instance limits (`/wmachine instances`, dashboard **Logging** group).

**Lockouts:**
- **The limits:** how many instances you've entered this hour (limit **5**)
  and in the last 24 hours (limit **30**), across all characters, and when
  the next slot frees up.
- **Which lockout:** it says whether you're on an **hourly** or a **daily**
  lockout.
- **Timed from leaving:** runs count from when you **leave**, as the server
  counts them.
- **Ready again:** it tells you when you can enter a new instance.
- **Where it shows:** in the window, on the dashboard card and in the minimap
  tooltip. `/wmachine lockouts` prints them.

**The same instance counts once.** Going back into the same instance (a
corpse run, another wing on the same ID, a disconnect, logging out inside)
adds to your earlier run instead of counting again. After a reset, the next
visit is a new run.

**Each run keeps:**
- the group (name, level, class)
- time in and out, and time inside
- mobs killed by the group
- XP and XP per mob
- gold looted
- your level going in and out (see where you dinged)
- every reputation gain
- gold traded during the run (3.25)

Hover a run in the log to see it all.

**In chat (3.24):**
- **Entering:** "Entered The Deadmines (3/5 this hour, 7/30 today)." with a
  **red X**. Click the X to delete that run if it shouldn't count.
- **Every line is clickable** and opens the log.
- **Leaving:** prints the run's stats to your chat window, to your group, or
  not at all.

**Resets:**
- **Your resets:** as group leader, a reset is announced to your group.
- **Nova Instance Tracker users (3.23):** when your group leader runs Nova
  Instance Tracker and resets, you see "The Deadmines has been reset by the
  group leader". The instance is also marked as reset in your log.
- **Trust:** only the leader of your own group is believed.

### 3.25 — Gold trade alerts

- **The line:** "Trade with Booster: received 500g, gave 2 item(s) (in The
  Deadmines)." It appears whenever gold changes hands in a trade, and
  clicking it opens the trade log.
- **Option:** *Chat line when gold is traded* (on by default).
- **Where it's logged:** still in **Mail & Trade**, which now records the
  instance you were in.
- **Fixed:** completed trades were only detected on English clients.

### 3.26 — Alert sounds

- **The sounds:** the mana potion and rune warnings each play their own
  sound once when they appear, the new **Potion** and **Rune** sounds by
  default.
- **Choosing:** pick another from a dropdown in Class Tools > General: either
  addon sound, raid warning, ready check, alarm clock, PvP flag, or None.
  Picking one plays it, so you can hear it first.
- **Channel:** *Warning sounds play on* Master (heard with game sound turned
  down), Sound effects or Dialog.
- **3.26.1:** a new Potion sound.
- **After updating:** restart WoW (not just `/reload`) to pick up new sound
  files.

### 3.27 — Your Characters

Every character you've logged in, on every realm, in one window
(`/wmachine alts`).

- **The list:** grouped by realm. Hover a realm for its **total gold**; the
  footer shows the total across all characters.
- **Each row:** level, **rested XP** and gold. Rested XP is estimated while
  you're logged out.
- **Hover a character** for:
  - free bag slots
  - armor durability
  - professions
  - your class's **reagents** (candles, powder, symbols, Ankhs, Soul Shards…)
  - for hunters, **ammo** and the **pet**
- **Right-click** a character to remove one you've deleted.

### 3.27 — Battlegrounds & Arenas

A log of every match, on every character (`/wmachine bgs`).

- **Each match:** the result (win, loss, draw or left early), its length,
  and your scoreboard line (killing blows, honorable kills, deaths, honor,
  damage, healing).
- **Arenas:** the bracket, rated or skirmish, who you were with and against,
  both team names, and your **rating change**.
- **Totals:** win rates per battleground and per arena bracket.
- **In chat:** a result line after each match. Click it to open the log.

### 3.28 — World Timers

Open-world timers for TBC, per layer (`/wmachine timers`).

- **Your layer:** target A'dal, Nutral, Minalei or Innkeeper Haelthol in
  Shattrath and it shows "Layer N of M".
- **Terokkar Forest towers:** when the Spirit Towers reset on each layer, and
  who holds them, with a warning 10 minutes before.
- **Dailies:** today's dungeon, heroic and PvP dailies.
- **Darkmoon Faire:**
  - whether it's up, where it is, and when it opens or closes
  - where it goes next: Terokkar / Elwynn / Mulgore by month
  - your **Sayge fortune cooldown** (4 hours of play)
- **Classic world buffs:** Rend, Onyxia and Nefarian timers with warnings, and
  NPC-killed notices. Rare on TBC.
- **Songflowers:** 25-minute timers on Felwood's ten flowers.
- **Nova World Buffs users:**
  - **What's read:** their shared timers from guild, group and nearby
    players.
  - **Checks:** the same rules Nova uses itself.
  - **Listen only:** nothing is ever sent in Nova's format.
- **Sharing:** `/wmachine wb` prints the timers, and `/wmachine wb guild` (or
  party / raid) shares them.

### 3.21 — Resizable dashboard

- **Opens showing every module:** when one column would be taller than your
  screen, it uses two or more.
- **Drag the corner** to resize it. The cards reflow into columns, and the
  size is remembered.
- **Fit** (top left) snaps back to the show-everything size.

---

### New commands

| Command | What it does |
|---|---|
| `/wmachine instances` | Instance log and lockouts |
| `/wmachine lockouts` | Print your instance lockouts |
| `/wmachine alts` | Your Characters |
| `/wmachine bgs` | Battleground and arena log |
| `/wmachine timers` | World Timers |
| `/wmachine wb [guild\|party\|raid]` | Print the world timers, or send them to a channel |

### Upgrade notes

- **New saved data:** `InstanceTrackerDB`, `AltTrackerDB`, `PvPLogDB` and
  `WorldTimersDB`.
- **Sounds:** restart WoW once after updating so the new sound files are
  found.
- **Dashboard:** it picks a new size on first open. Drag it, or press
  **Fit**.
- **Nova compatibility is listen only.** Watching Machine reads Nova Instance
  Tracker reset notices and Nova World Buffs timers, but never sends in
  their format.
- **Still to confirm in game:**
  - Darkmoon Faire hours on OCE realms
  - whether Classic world buffs still drop on Anniversary realms
