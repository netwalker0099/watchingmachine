# Release announcement — Watching Machine 3.5

Copy-paste ready text for Discord and CurseForge. The canonical, full-detail
changelog lives in [`CHANGELOG.md`](../CHANGELOG.md).

> 3.4 shipped the Class Tools framework and the mailbox fix without a release
> post. Both are included below, since they are new to anyone upgrading from
> 3.3.

---

# ═══════════════  DISCORD  ═══════════════

Discord caps messages at 2000 characters, so this is split into three posts.
Send them in order — each is self-contained and under the limit. Discord
markdown supports `#`/`##`/`###` headers, `**bold**`, `` `code` `` and lists,
but **not** tables.

---

## ▸ Discord post 1 of 3

```
# 🧙 Watching Machine 3.5 is out

The addon now knows what class you're playing, and shows you only the tools that apply to it.

## 🗂️ New: Class Tools
`/wmachine class` opens a panel with a **tab per class**. Your own class is selected when it opens. A tab only appears once something has actually been built for that class, so there are no empty tabs promising work that doesn't exist.

Everything funnels into **one movable warning frame** — not a new window per check. Up to six lines at a time, and it hides itself the second the last warning clears.

Frame options are right under the feature list: sound on a new warning, lock in place, reset position, and **Show example** — which puts two dummy lines up for six seconds so you can find and drag the frame without waiting for a real warning to fire.

Every check has its own on/off switch, saved per class.
```

---

## ▸ Discord post 2 of 3

```
## 🟣 Warlock
- **Armor** — warns when Fel Armor / Demon Armor / Demon Skin falls off
- **Demonic Sacrifice** — only nags if you actually took the talent *and* have no demon out. Pet summoned? That's a choice, not a mistake, and it says nothing
- **Soul Link** — only when talented, pet alive, and not sacrificed. The two checks interlock, so a sacrificed lock is never nagged about Soul Link
- **Soulstone timers** — `/wmachine soulstone` shows who's stoned and for how long. It reads the buff itself, so it works for stones cast by any warlock, including ones applied before you logged in

Talents re-read instantly on a respec instead of waiting out a cache.

## 🔵 Mage
- **Armor** — warns when Molten / Mage / Ice / Frost Armor is missing
- **Portal button** — one draggable button that expands on hover into **every teleport and portal you know**, portals first. Built from your spellbook, so it shows exactly what you can cast and nothing else

It won't expand in combat — those are secure buttons the client refuses to rebuild mid-fight, and portals aren't castable in combat anyway.

`/wmachine portals` lists what it found.
```

---

## ▸ Discord post 3 of 3

```
## ⚗️ New: General consumable checks
A **General** tab that applies to everyone, and always sorts first:

- **Flask**, **food buff** and **weapon oil / stone**
- Runs **only inside a raid instance**, and **25-man only by default** (tick to include 10s). Nothing nags you in Shattrath
- Wording follows your class: casters get told about wizard oil, melee about sharpening stones and weightstones
- Off hand is checked only when a real weapon is in it — shields and held items share the slot but can't take an oil
- Unstable Flasks count

`/wmachine consumes` shows exactly what it sees.

## 📬 Also in 3.4, if you skipped it
- **Open All duplicates in the mail log are fixed.** The log now works out what you collected by diffing the inbox instead of logging on each click, so retries and shifting mail indices can't double up
- Dashboard card list scrolls, so no module is cut off the bottom

## ⬆️ Upgrading
- Settings carry over, no reset needed
- Class checks are **on by default but entirely private** — nothing is sent to raid chat
- Mages: the portal button starts in the centre of your screen. Drag it where you want it
- Worth doing once: open `/wmachine class` and hit **Show example** to place the warning frame

⬇️ CurseForge or GitHub. Full changelog in the repo.
```

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.5

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

The addon now detects the class you are playing and surfaces only the tools
built for it, under a new **Class Tools** panel.

### At a glance

| | |
|---|---|
| **Class Tools** | `/wmachine class` — a tab per class, yours selected on open |
| **Warlock** | Armor, Demonic Sacrifice, Soul Link, soulstone timers |
| **Mage** | Armor check, expanding portal / teleport button |
| **General** | Flask, food buff and weapon oil / stone in raid instances |
| **Shared warning frame** | One movable *CHECK YOURSELF* window for every check |
| **From 3.4** | Mailbox Open All duplicates fixed; scrollable dashboard |

### New: Class Tools

A class section in the dashboard with a **tab per class**. A tab appears only
once a feature has been registered for that class, so there are no empty tabs
for work that has not been done. Your own class is selected when the panel
opens, and is always offered even before it has tools.

Features do not each build their own alert window or their own timer. They all
feed **one movable *CHECK YOURSELF* frame** holding up to six lines, which
hides itself the moment the last warning clears, and they share a single
one-second tick — so the cost does not grow as more checks are added.

Frame options sit under the feature list: sound on a new warning, lock in
place, reset position, and **Show example**, which puts two dummy lines up for
six seconds so the frame can be found and positioned without waiting for a
real warning.

Every feature has its own switch, saved per class.

### New: Warlock tools

- **Armor** — warns when Fel Armor, Demon Armor or Demon Skin has fallen off.
- **Demonic Sacrifice** — warns only when the talent is actually taken *and*
  no demon is out. A warlock with a pet summoned has made a choice, not a
  mistake, and nothing is raised.
- **Soul Link** — warns only when talented, with a living pet, and with no
  sacrifice buff up. The two checks interlock in both directions.
- **Soulstone timers** — `/wmachine soulstone` lists who is stoned and for how
  long. It reads the Soulstone Resurrection buff rather than watching for
  casts, so it covers stones applied by any warlock, including before you
  logged in.

Talents are read by name across all trees and cached briefly for speed; the
cache is dropped outright on a respec, so the checks never act on an old build.

### New: Mage tools

- **Armor** — warns when Molten, Mage, Ice or Frost Armor is missing.
- **Portal / teleport button** — a single draggable button that expands on
  hover into every teleport and portal you know, portals first. It is built
  from your spellbook, so it shows exactly what you can cast, and rebuilds when
  you learn a new one.

The scan derives the `Teleport:` / `Portal:` prefixes from the client's own
spell names rather than hardcoding English, so it works on localised clients.
The flyout does not expand in combat: its entries are secure buttons the client
will not let an addon reconfigure during a fight, and portals are not castable
in combat regardless.

### New: General consumable checks

A **General** tab that applies to every class and always sorts first.

- **Flask**, **food buff** (Well Fed) and **weapon oil / stone**.
- Active only inside a raid instance, and **25-man only by default**, with a
  tick to include 10-mans.
- Wording follows your class — wizard oil for casters, sharpening stones and
  weightstones for melee.
- The off hand is checked only when a real weapon is equipped there; shields
  and held items share the slot but cannot take an oil.
- Flask matching is on substring, so Unstable Flasks are recognised.
- `/wmachine consumes` prints what the checks currently see.

Classic exposes only *whether* a temporary weapon enchant is present, not which
one, so this check is presence-based.

### Included from 3.4

- **Mailbox Open All no longer produces duplicate log entries.** What you
  collected is now worked out by diffing the inbox rather than logging on each
  take attempt, which is immune to retries, shifting mail indices and however
  fast the open-all runs.
- **The dashboard card list scrolls**, so no module card is cut off.

### New commands

| Command | Does |
|---|---|
| `/wmachine class` | Open Class Tools |
| `/wmachine soulstone` | Soulstone timers in your group (warlock) |
| `/wmachine portals` | List known teleports and portals (mage) |
| `/wmachine consumes` | Show what the general consumable checks see |

### Upgrade notes

- Existing settings and saved data carry over; no reset needed.
- Class checks are **on by default but entirely private** — none of them send
  anything to raid chat.
- Mages: the portal button starts in the centre of the screen. Drag it where
  you want it, and lock it from the panel.
- Worth doing once: open `/wmachine class` and press **Show example** to place
  the warning frame before you need it.
