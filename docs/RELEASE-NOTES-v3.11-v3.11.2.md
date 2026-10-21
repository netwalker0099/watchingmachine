# Changelog announcement — Watching Machine 3.11 to 3.11.2

Copy-paste ready text for Discord and CurseForge, covering 3.11, 3.11.1
and 3.11.2. The canonical, full-detail changelog lives in
[`CHANGELOG.md`](../CHANGELOG.md). Everything before 3.11 is in
[`RELEASE-NOTES-v2.9-v3.11.md`](RELEASE-NOTES-v2.9-v3.11.md).

---

# ═══════════════  DISCORD  ═══════════════

One post. Paste the text *inside* the code block as a single message. It
is well under Discord's 2000-character limit (counted the way Discord
counts, where an emoji takes two).

---

## ▸ Discord post 1 of 1

```
# 🔧 Watching Machine 3.11.2 is out

Premade chat filters, plus two bug fixes. If you play a mage, update.

## 3.11.2 — Tools menu in the right place
The **...** button on dashboard cards (and right-clicking a card) could open its menu down at the bottom of the screen if you use ElvUI or a non-default UI scale. It now opens right under the **...** button.

## 3.11.1 — Mage login error spam fixed 🧙
Logging in on a mage filled your error log with about 60 errors a second (*"unknown event LEARNED_SPELL_IN_TAB"*). That event doesn't exist in TBC, and the failure kept retrying every frame, so some other modules never finished starting up on mages.
- The event is gone; the portal button still picks up new portals
- One broken module can't stop the others starting any more
- A failing timer reports its error once instead of every frame

After updating, run `/wmachine clearerrors` once to clear out the old entries.

## 3.11 — Premade chat filters 🔇
Chat Filter (`/wmachine filter`) has one-tick filters for the usual spam:
- **GDKP**
- **Guild Loot Run**
- **Gear Carry** (also catches "gear carries")
They're off until you tick them, kept apart from your own phrases, and each shows how many messages it has hidden this session. Like all filters, they run **before Keyword Monitor**, so filtered spam never triggers a keyword match.

⬇️ CurseForge or GitHub. Full changelog in the repo.
```

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.11.2

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Covers 3.11 through 3.11.2. Settings and saved data carry over, no reset
needed.

### At a glance

| Version | Headline |
|---|---|
| **3.11.2** | Dashboard tools menu opens under its **...** button, not at the bottom of the screen |
| **3.11.1** | Fixed login error spam on mages; one failing module can no longer stop the others |
| **3.11** | Premade chat filters: GDKP, Guild Loot Run, Gear Carry |

### 3.11.2 — Tools menu position

The **...** button on a dashboard card, and right-clicking a card, opened
the tools menu at the mouse cursor. The game positions a cursor menu using
the UI scale, so with ElvUI or another non-default UI scale it landed far
from the click, near the bottom of the screen. The menu now opens directly
below the card's **...** button at any UI scale.

### 3.11.1 — Mage login error spam

Logging in on a mage filled the error log with roughly 60 errors a second:

> `Attempt to register unknown event "LEARNED_SPELL_IN_TAB"`

- **Cause:** the Mage tools registered an event that exists in later
  expansions but not in the TBC client.
- **Why it repeated:** the failure happened during start-up, inside a timer
  that retried every frame. On every attempt, the modules that start after
  Mage never finished.
- **Fixed:**
  - The event is no longer used. The portal button still updates when you
    learn a new portal.
  - Start-up runs once, and each module starts on its own. A module that
    fails is logged, and the rest still start.
  - A failing timer reports its error once instead of every frame.
  - Class modules skip any event the client doesn't have, rather than
    erroring.
- **After updating,** run `/wmachine clearerrors` once to clear the old
  entries from the saved error log.

### 3.11 — Premade chat filters

A **Premade filters** section in the Chat Filter window (`/wmachine
filter`), one tick each:

| Premade | Hides messages containing |
|---|---|
| **GDKP** | `GDKP` |
| **Guild Loot Run** | `Guild Loot Run` |
| **Gear Carry** | `Gear Carry`, `Gear Carries` |

- Off by default.
- Kept apart from your own phrase list, so switching one off brings those
  messages straight back.
- Each shows how many messages it has hidden this session; the Chat Filter
  card's *Hidden this session* tool lists them too.
- Same matching as your own phrases: anywhere in a message, ignoring case,
  colours and item-link brackets.
- Applied **before Keyword Monitor**, so filtered spam is never checked for
  keywords.

### Upgrade notes

- **Settings carry over:** existing settings and saved data are kept, with
  no reset needed.
- **Mages:** run `/wmachine clearerrors` once to clear the old error spam
  from the log.
- **Chat Filter premades:** these are off until you tick them.
