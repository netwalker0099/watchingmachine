# Release announcement — Watching Machine 3.3

Copy-paste ready text for CurseForge. The canonical, full-detail changelog
lives in [`CHANGELOG.md`](../CHANGELOG.md).

> **Note:** the Illidan Shear monitor is listed here as new. It landed after the
> 3.2 notes were written and was never announced, so it is new to anyone
> upgrading. If you published a 3.2 build that already contained it, move that
> section into the 3.2 notes instead.

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.3

**TBC Classic Anniversary patch 2.5.6** (Interface `20506`).

Two Black Temple helpers — a Shear monitor for Illidan's main tank and a shadow resist gear check after Mother Shahraz — plus a fix for settings that were running off the bottom of the screen.

### At a glance

| | |
|---|---|
| **New** | Illidan Shear monitor, Black Temple shadow resist gear check |
| **Fixes** | Settings panel was taller than the screen, hiding its lowest controls |
| **Moved** | Per-boss callouts now live in their own window (`/wmachine encounters`) |
| **Client** | TBC Anniversary 2.5.6 |

---

### New: Illidan Shear monitor

Shear cuts the main tank's maximum health by roughly **60%** for a few seconds. It cannot miss, but it **can** be dodged, parried or blocked — which is why tanks stack avoidance for it.

**Damage meters under-report it, and that is the point of this feature.** The damaging part is a max-health debuff rather than a normal hit, and an avoided Shear produces no damage event at all. Details! has nothing to show in either case. So the monitor watches every event a Shear can produce — the cast, the hit, the debuff application, and every avoidance result — and sweeps raid auras as a backup in case a combat-log event is dropped.

- **Calls out each Shear** on the main tank: `Shear HIT Maintank`.
- **Avoided Shears are counted but not announced** by default. Shear repeats every ~10s across three ground phases, so calling both outcomes doubles the chat. You always see both locally.
- **Channel picker:** Me only / Say / Party / Raid / `/rw`, plus a **throttle** for the minimum gap between chat calls.
- **Optional cast warning:** Shear has a ~1.5s cast — a local heads-up gives the tank the window to use Shield Block or Holy Shield. Never sent to chat.
- **Pull summary** when combat ends: total, hit vs avoided, a per-tank breakdown so swaps are visible, and which avoidance types occurred. This is the record Details can't give you.
- **One call per cast** — the several events a single Shear generates are deduplicated.
- **No duplicate spam:** only the raid leader sends to chat (assistants too if *Assistants can announce* is on). Everyone else gets a local line.
- `/wmachine shear` for status and tallies, `/wmachine shear on|off` to toggle.

---

### New: Black Temple shadow resist gear check

Mother Shahraz is the only Black Temple fight that wants shadow resist gear. Staying in it for the rest of the raid is an easy and expensive mistake.

- **Warns you if the set is still on** when you pull the Grand Promenade constructs after her — Shadowmoon Reaver, Promenade Sentinel, and the Illidari Archon / Assassin / Battle-mage / Blood Lord packs.
- **Arms two ways:** when Mother dies, and the moment you engage one of those mobs. A `/reload` after she is already down still works.
- **Reads equipped gear only.** Shadow Protection and Shadow Resistance Aura cannot cause a false warning.
- **Warns you privately by default** — chat line, screen flash and a sound. Optional Say / Party / Raid / `/rw` if you want it called out.
- **Every player warns themselves.** Unlike the other callouts this is not limited to the raid leader, because it is about your own gear.
- **Threshold** (default 60 gear shadow resist) ignores an odd piece with incidental resistance; a Mother set runs well over 200.
- One warning per pull, and `/wmachine srcheck` lists exactly what it sees on each slot.

---

### Fixed: settings panel controls were off the bottom of the screen

The Debuff Tracker settings panel had grown from 700px to 948px as features were added, but the WoW UI is only about 768px tall at default scale. Its lowest controls — including the newest ones — were off-screen and unreachable.

- **Per-boss callouts** (Illidan Doom warning, Illidan Shear monitor, shadow resist check) now live in their own window: **`/wmachine encounters`**, or the *Encounter Callouts...* button in Debuff Tracker settings.
- The main panel is back to a size that fits on screen.

---

### Upgrade notes

- Existing settings and saved data carry over; no reset needed.
- **The Shear monitor is on and announces hits to raid chat by default.** If you would rather it stay quiet, set its channel to *Me only*, raise the throttle, or untick it in `/wmachine encounters`.
- **The shadow resist check is on but warns you privately**, so it adds nothing to raid chat unless you change its channel.
- **Your encounter settings moved.** They are no longer in the main Debuff Tracker panel — use `/wmachine encounters`.
- Worth doing once: put your Mother set on and run **`/wmachine srcheck`** to confirm it reads your gear correctly before you rely on it.
