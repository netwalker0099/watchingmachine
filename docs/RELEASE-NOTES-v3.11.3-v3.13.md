# Changelog announcement — Watching Machine 3.11.3 to 3.13

Copy-paste ready text for Discord and CurseForge, covering 3.11.3, 3.12
and 3.13. The canonical, full-detail changelog lives in
[`CHANGELOG.md`](../CHANGELOG.md). Earlier releases:
[`RELEASE-NOTES-v3.11-v3.11.2.md`](RELEASE-NOTES-v3.11-v3.11.2.md) and
[`RELEASE-NOTES-v2.9-v3.11.md`](RELEASE-NOTES-v2.9-v3.11.md).

---

# ═══════════════  DISCORD  ═══════════════

One post. Paste the text *inside* the code block as a single message. It
is under Discord's 2000-character limit (counted the way Discord counts,
where an emoji takes two).

---

## ▸ Discord post 1 of 1

```
# 🧙 Watching Machine 3.13 — mage buttons

Everything here is for mages: the portal button got a rebuild, and it has a new partner.

## 3.13 — New: mage utility button
A second button with the **mage crest**. Hover it for:
- **Mana gems**: Emerald, Ruby, Citrine, Jade, Agate
- **Armors**: Molten, Mage, Ice, Frost
- **Food & water**: Ritual of Refreshment (table), Conjure Water, Conjure Food
Each group starts with the **highest level nearest the button**. Ranked spells show once and cast your highest rank. Only spells you know appear, each with its own icon and tooltip.

## 3.12 — Portal button with icons 🌀
- The button is now a **portal icon**. Hovering opens an **icon for every portal and teleport you know**, each with its spell tooltip
- Click an icon to cast

## 🧭 Choose which way they open
In **Class Tools → Mage**, every group has its own direction: Up, Right, Down or Left.
- Portals left, teleports up, gems left, armor up, food right by default
- Groups on the same button that point the same way form one line (e.g. portals, then teleports on the end)
- **Lock the mage buttons** stops both being dragged

## 3.11.3 — Portals cast again
Clicking a portal or teleport did nothing. Fixed.

Neither button opens in combat, since portals and conjures can't be cast there anyway.

⬇️ CurseForge or GitHub. Full changelog in the repo.
```

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.13

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Covers 3.11.3 through 3.13. All three are mage changes. Settings and saved
data carry over, with no reset needed.

### At a glance

| Version | Headline |
|---|---|
| **3.13** | New **mage utility button**: mana gems, armors, food / water / table |
| **3.12** | Portal button rebuilt as icons, with a direction option for portals and teleports |
| **3.11.3** | Fixed: clicking a portal or teleport didn't cast it |

### 3.13 — Mage utility button

A second draggable button, showing the **mage class crest**, that expands
on hover into one icon per spell:

| Group | Nearest the button first |
|---|---|
| **Mana gems** | Conjure Mana Emerald, Ruby, Citrine, Jade, Agate |
| **Armors** | Molten Armor, Mage Armor, Ice Armor, Frost Armor |
| **Food & water** | Ritual of Refreshment (table), Conjure Water, Conjure Food |

- **Ordering:** each group is ordered highest level first, so the best
  spell sits closest to the button.
- **Only what you know:** a spell appears only if it's in your spellbook.
  Non-English clients are supported.
- **Ranks:** ranked spells (the armors, Conjure Food, Conjure Water) appear
  once, cast your highest rank, and show its tooltip.
- **Icons:** each icon is the spell's own, so every gem shows its gem.
- **Tooltips:** hovering an icon shows the spell's tooltip.
- **Options:** *Show the mage utility button* (on by default), and
  direction options for each group (see below).

### 3.12 — Portal button with icons

- **Icon button:** the portal button is now an icon showing your first
  portal's spell icon.
- **Flyout:** hovering opens an **icon for every portal and teleport you
  know**, each using that spell's icon.
- **Tooltips and casting:** hovering an icon shows the spell's tooltip, and
  clicking it casts.

### Expansion directions (3.12, 3.13)

Each group has its own direction in **Class Tools → Mage**: Up, Right,
Down or Left.

| Option | Default |
|---|---|
| Portals expand | Left |
| Teleports expand | Up |
| Mana gems expand | Left |
| Armors expand | Up |
| Food & water expand | Right |

- **Shared lines:** groups on the same button that point the same way form
  one line, in order. Portals are followed by teleports; gems by armors,
  then food.
- **Lock the mage buttons** (previously *Lock the portal button*) stops both
  buttons being dragged.
- **Combat:** a direction changed in combat applies when combat ends.

### 3.11.3 — Portals cast again

Clicking a portal or teleport did nothing on current client builds. The
buttons were listening for the wrong half of the click: they waited for the
release, but the client's default "cast on key down" setting acts on the
press. They now use whichever half casts on your client.

### Upgrade notes

- **Settings carry over:** settings and saved data are kept, and the portal
  button keeps its position.
- **Placement:** the new utility button first appears just left of the
  portal button. Drag it where you want it.
- **Combat:** neither button opens in combat, because portals and conjure
  spells can't be cast there anyway.
