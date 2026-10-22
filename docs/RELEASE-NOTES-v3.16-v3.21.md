# Changelog announcement — Watching Machine 3.16 to 3.21

Copy-paste ready text for CurseForge, covering 3.16, 3.16.1, 3.17, 3.18,
3.19, 3.20, 3.20.1 and 3.21. The canonical, full-detail changelog lives in
[`CHANGELOG.md`](../CHANGELOG.md). Earlier releases:
[`RELEASE-NOTES-v3.11.3-v3.13.md`](RELEASE-NOTES-v3.11.3-v3.13.md),
[`RELEASE-NOTES-v3.11-v3.11.2.md`](RELEASE-NOTES-v3.11-v3.11.2.md) and
[`RELEASE-NOTES-v2.9-v3.11.md`](RELEASE-NOTES-v2.9-v3.11.md).

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.21

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Covers 3.16 through 3.21: a shaman totem button, a swing and Auto Shot
timer with enhancement weapon sync, a Righteous Fury check, a game menu
button, and a resizable dashboard. Settings and saved data carry over, with
no reset needed.

### At a glance

| Version | Headline |
|---|---|
| **3.21** | The **dashboard is resizable** and opens showing every module |
| **3.20.1** | Fixed: the game menu button overlapped ElvUI's and ignored its skin |
| **3.20** | The **swing timer is resizable** |
| **3.19** | New **Watching Machine button in the game menu** (Escape) |
| **3.18** | New **Righteous Fury check** for Protection paladins |
| **3.17** | New **swing timer** and **hunter Auto Shot timer**, with **enhancement weapon sync** |
| **3.16.1** | Fixed: Class Tools dropdowns covered their option text |
| **3.16** | New **shaman totem button** with totem sets |

---

### 3.16 — Shaman totem button

One button that drops a whole **totem set**, one totem per click, in the
order **Air, Water, Earth, then Fire**. Fire always goes last.

- **Pick a set:** hover the button to open your sets, and click one to use
  it. The button's icon and label show the set in use, and its tooltip
  lists the four totems.
- **Drop it:** each click casts the next totem. The game allows only one
  spell per click, so the button runs a `/castsequence` built from the set.
- **Starts again from Air** when all your totems are gone (destroyed or
  expired; TBC has no Totemic Recall), when combat ends, or on **Ctrl-click**.
- **Right-click** opens the set editor. **Shift-drag** moves the button, since
  a plain press drops a totem.

**Four sets, premade:**

| Set | Air | Water | Earth | Fire |
|---|---|---|---|---|
| **Melee** | Windfury | Mana Spring | Strength of Earth | Searing |
| **Caster** | Wrath of Air | Mana Spring | Stoneskin | Totem of Wrath |
| **Healer** | Wrath of Air | Healing Stream | Stoneskin | Searing |
| **Tremor** | Windfury | Mana Spring | Tremor | Searing |

Each element uses the best totem you know, so a set keeps working while you
level: Searing until you have Totem of Wrath, Grace of Air until Windfury.

**Totem Sets editor:** open it with `/wmachine totems`, by right-clicking the
button, or from the Class Tools card's **...** menu. Rename a set, and choose
each element's totem, *Auto* (the premade's pick) or *None*. *Restore
premades* puts all four back.

**Options** in Class Tools > Shaman: *Show the totem button*, and *Totem sets
expand* (Up, Right, Down, Left or Hidden). The button docks and locks with
the other flyout buttons.

---

### 3.17 — Swing timer and Auto Shot timer

A movable bar per hand showing the time to your next swing. A white line
moves left to right as the swing comes round.

**Who gets it:**
- warriors and rogues
- **Retribution** paladins and **Enhancement** shamans (your spec is read from
  your talents)
- **hunters**, who get an **Auto Shot** bar instead

An option turns it on for every class and spec.

**Latency:** the last stretch of each bar, as long as your latency, is drawn
in red, and the fill turns red inside it. Every "press now" marker is moved
earlier by your latency.

**How it keeps time (TBC rules):**

| What happens | Effect on the timer |
|---|---|
| A swing lands or misses (dodge, parry, block, miss) | Restarts that hand |
| Heroic Strike, Cleave, Maul, Raptor Strike | Replace the swing: restart the main hand |
| A cast-time spell finishes (Slam, Lightning Bolt, a heal) | Restarts both hands. Instants (Stormstrike, shocks) don't |
| Haste (Flurry, Bloodlust, drums) | The time left speeds up or slows down to match |
| You parry an attack | Your next main-hand swing comes sooner: 40% of the swing taken off, never below 20% left |
| Weapon swap | Restarts every hand |
| Windfury extra attack | Not counted as a new swing |

**Hunters:** the Auto Shot bar is **green** while a Steady Shot is safe to
start, **red** where starting one would delay (clip) your next shot, and
**yellow** for the final half-second wind-up, when moving delays the shot.

**Enhancement weapon sync.** With two weapons of the same speed, you want the
off hand to land just after the main hand:
- **Why:** Windfury Weapon has a 3-second cooldown shared by both hands, so
  the main hand should be the one that gets the proc. Two hits close
  together also share one Flurry charge.
- **The macro:** the usual sync macro is:

  ```
  /cleartarget
  /targetlasttarget
  /startattack
  ```

  It stops and restarts your attack, which can only *delay* the off hand: an
  off hand that's past halfway is put back to halfway.
- **The mark:** a blue line on the main-hand bar shows when to press. It turns
  green and the timer says **SYNC NOW** when it's time and pressing would
  actually help.
- **The readout:** a line under the bars says *In sync*, *Off hand first* or
  *Out of sync*, with the gap. It also warns when your weapon speeds differ,
  since sync can't hold then.
- **Off hand lands after by** sets the gap you're aiming for (0.15s by
  default).

**Options** in Class Tools > General. `/wmachine swing` shows the timer for 10
seconds so you can place it.

---

### 3.18 — Righteous Fury check

**Protection paladins** are warned in the CHECK YOURSELF frame when
**Righteous Fury** is missing, the same way the mage and warlock armor checks
work.

- **Who counts as Protection:** most talent points in Protection, or Holy
  Shield / Avenger's Shield learned. Holy and Retribution paladins are never
  warned.
- **No warning** before you've learned Righteous Fury, or while you're dead.
- A respec is picked up straight away.
- Paladins now have their own tab in Class Tools.

---

### 3.19 and 3.20.1 — Game menu button

A **Watching Machine** button in the menu that Escape opens, just above
**Log Out** (like ElvUI's). Click it to open the dashboard.

- **With ElvUI (3.20.1):** the button sits under ElvUI's button instead of on
  top of it, and takes ElvUI's button skin. If ElvUI's Blizzard skins are
  off, it keeps the default look like the rest of the menu. It also makes
  room for any other addon's menu button.
- **Safe to use:** Blizzard's own menu buttons are left alone, so *Log Out*
  and *Exit Game* keep working without "blocked by an AddOn" errors.
- **Turn it off:** Settings > *Watching Machine button in the game menu
  (Esc)*.

---

### 3.20 — Resizable swing timer

- **Drag to resize:** while the timer is unlocked, drag the grip in its
  bottom-right corner. Right makes the bars wider, down makes them taller.
- **Or pick a size:** *Swing timer width* and *Swing timer bar height* in
  Class Tools > General.
- **Everything scales:** the line, the sync mark, the latency and the hunter
  zones resize with the bars. The labels hide on very thin bars.
- **Lock the swing timer** now also stops resizing.
- `/wmachine swing reset` puts back the default place and size.

---

### 3.21 — Resizable dashboard

- **Opens showing every module:** the dashboard used to be a fixed
  single-column window that needed scrolling. It now opens at a size worked
  out from your screen, with two (or more) columns of cards when one column
  wouldn't fit.
- **Resizable:** drag the bottom-right corner. The cards rearrange into as many
  columns as fit while you drag, and the size is remembered.
- **Fit**, at the top left, snaps back to the size that shows every card.

---

### Fixes

- **3.16.1:** in Class Tools, option dropdowns (the mage, warlock and shaman
  *expand* directions, the flyout and mana options) drew over the first line
  of their own description. The description now sits under the dropdown, and
  the dropdowns line up in one column.

### New commands

| Command | What it does |
|---|---|
| `/wmachine totems` | Edit your totem sets (shaman) |
| `/wmachine swing` | Show the swing timer for 10s to move or resize it |
| `/wmachine swing reset` | Swing timer back to its default place and size |

### Upgrade notes

- **New saved data:** `ShamanToolsDB` (totem sets) and `SwingTimerDB` (swing
  timer place, size and sync setting).
- **New options:** the swing timer and Righteous Fury check are on by
  default; the swing timer only appears for the classes and specs above.
- **Dashboard size:** on its first open the dashboard picks its new size. Drag
  it or press **Fit** to change it.
- **Still to confirm in game:** how the client logs Windfury Weapon's extra
  attack, and whether the Auto Shot wind-up shortens with haste (the timer
  uses a fixed 0.5s).
