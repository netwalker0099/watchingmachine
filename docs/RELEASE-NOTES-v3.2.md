# Release announcement — Watching Machine 3.2

Copy-paste ready text for CurseForge. The canonical, full-detail changelog
lives in [`CHANGELOG.md`](../CHANGELOG.md).

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.2

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

This release adds an automated Curse of Doom callout for Illidan and fixes several Buff Check elixir and flask detection errors.

### At a glance

| | |
|---|---|
| **New** | Illidan Doom warning (Debuff Tracker), `/wmachine whybuff` diagnostic |
| **Fixes** | Buff Check elixir classification, Unstable Flask detection |
| **Client** | TBC Anniversary 2.5.6 |

---

### New: Illidan Doom warning

When **Illidan Stormrage** drops to **68%**, Watching Machine sends **CAST DOOM NOW** as a raid warning. Curse of Doom takes 60 seconds to land, so this gives warlocks time to get it on before he lifts off for Phase 2 at 65%.

- **Toggle:** *Illidan 68%: raid warn "CAST DOOM NOW"* in Debuff Tracker settings (`/wmachine debuff`). On by default.
- **Fires once per pull** and resets after a wipe.
- **No targeting needed:** Illidan is picked up from boss frames, your target or focus, other raid members' targets, or nameplates.
- **No duplicate warnings:** only the raid leader sends it (assistants too if *Assistants can announce* is on). Everyone else running the addon gets a local chat line. Without assist it falls back to `/raid`.
- **Reload-safe:** if you `/reload` and Illidan is already below 60%, it stays quiet.

---

### Buff Check fixes

- **Elixir of Empowerment** and **Elixir of Major Defense** are now correctly treated as **Guardian** elixirs. Players using them were wrongly flagged as missing a guardian elixir.
- **Unstable Flasks** (*Unstable Flask of the Beast*, *of the Sorcerer*, …) are now recognised. They count for the flask check and both elixir slots, like any other flask.
- **More elixirs recognised:** expanded Battle and Guardian lists with missing TBC and classic-era consumables still in use, including Elixir of Camouflage, Frost Power, Giants, Greater Agility, Elixir of the Sages, Mageblood Potion, Winterfall Firewater, and Juju buffs.

### New: `/wmachine whybuff`

Lists every aura on your target (or on you, if nothing is targeted), which Buff Check category each one satisfies, which auras match nothing, and which checks are enabled. Consumable aura names often differ from their item names, so use this when something isn't being detected. Alias: `/wmachine buffdebug`.

---

### Upgrade notes

- Existing settings and saved data carry over; no reset needed.
- The Doom warning is **on by default**. If someone else in your raid already calls Doom, untick it in `/wmachine debuff`.
- Only the raid leader sends the warning by default. If an assistant should send it instead, have them tick *Assistants can announce* in Debuff Tracker settings.
