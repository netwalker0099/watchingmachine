# Watching Machine — Changelog

All notable changes to Watching Machine. Versions are listed newest first.

Current release: **3.1** — TBC Classic Anniversary patch 2.5.6 (Interface `20506`)

---

## 3.1

### Debuff Tracker — boss detection false positives eliminated

The tracker treated any mob at `level >= playerLevel + 3` with elite classification
as a boss. TBC raid trash is level 72–73 elite exactly like real bosses, so trash
triggered boss alerts — Magtheridon's Hellfire Warders being the clearest case.
Display names couldn't separate them either, since some trash shares names with
encounter mobs.

**Added — NPC-ID identity**
- Mobs are identified by the `npcID` embedded in their creature GUID, which is
  unique per creature type even when two mobs share a display name.

**Added — Health-pool floor**
- Mobs below a configurable max-health threshold are never treated as bosses
  (default 150,000; slider 0–400k, 0 = off). Separates trash from bosses
  independently of level and classification.

**Added — Focus target tracking**
- On multi-boss encounters (Fathom-Lord Karathress, Illidari Council, …) group
  damage is accumulated per hostile GUID over a rolling 6-second window from the
  combat log. The mob absorbing the most raid damage is the raid's real kill
  target, and alerts fire only for it.
- Targeting an add the raid is ignoring — a Fathom-Guard that isn't next in the
  kill order — no longer sets alerts off.
- The focus follows the raid automatically when kill order or strategy changes.
  No hardcoded kill orders; switching to "burn the Fathom-Lord first" needs no
  configuration.
- Fails open: an expired or stale focus never suppresses alerts permanently.

**Added — Manual exclusions and diagnostics**
- `/wmachine exclude` — with a mob targeted, permanently stops that creature type
  triggering boss alerts. Keyed on npcID, so same-named mobs elsewhere are
  unaffected.
- `/wmachine unexclude`, `/wmachine exclusions` — manage the list.
- `/wmachine whyboss` — prints exactly how the tracker sees your target: npcID,
  classification, level, health vs. the floor, exclusion state, current raid
  focus, and whether an alert would fire.
- "Exclude Target" button and both new settings added to the Debuff Tracker panel.

**Performance**
- Combat log handling merged into a single parse feeding both damage tracking and
  pull detection.
- Group membership lookups are now a cached GUID hash set instead of a 40-unit
  scan on every combat log event.

---

## 3.0

### New module — Aura Range

Visual and audio alerts when you drift out of range of party auras and shaman
totems. These buffs drop off the instant you leave their radius, so the module
watches your own auras via `UNIT_AURA` — event-driven, no polling, and it fires
the same frame you step out.

- Tracks Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin
  auras, and totem buffs (Strength of Earth, Grace of Air, Wrath of Air, Totem of
  Wrath, Mana Spring, Healing Stream, Stoneskin, Windfury). Each individually
  toggleable.
- Movable, pulsing on-screen alert listing exactly which auras you lost, with
  icons; clears the moment you walk back into range.
- Optional raid-warning sound, throttled so losing several totems at once doesn't
  triple-blast you.
- False-alarm guards: no alerts while dead (death wipes all buffs), when the
  providing class has no living member in the group, on zone transitions, or after
  leaving the group.
- Stale alerts auto-expire (5–30s, default 15s) to cover totems that simply
  expired or were destroyed.
- Lockable alert frame, test button, `/wmachine range`.

### Buff Check — Battle and Guardian Elixir detection

- Two new buff groups with TBC-accurate elixir lists for both categories,
  including classic-era holdovers still in use.
- Flasks correctly satisfy **both** elixir slots, matching TBC's consumable rules —
  a flasked player is never nagged about elixirs.
- Off by default; toggle in settings alongside the other consumable checks.

### Buff Check — PallyPower single-target override fix

- Expected blessings were computed as the union of class-wide **plus**
  single-target assignments, so a player with a single-target override (e.g. a
  feral tank assigned single Might) was falsely flagged for missing that same
  paladin's class-wide blessing (Salvation on druids).
- Expectations are now computed **per paladin**: a single-target assignment
  replaces that paladin's class blessing for that player, while class blessings
  from other paladins still apply.

---

## 2.9

### ArmorySnap integrated as a module

The standalone ArmorySnap addon is now a Watching Machine module, including its
v1.2 scanner overhaul.

- Passive raid gear snapshots — enchants and gems included, since TBC item links
  embed both.
- **Event-chained scanning**: the next inspect fires the moment the previous one
  resolves (success, timeout, or self-capture) instead of waiting on a fixed
  ticker. A full 25-man with everyone in range captures in roughly 15–20 seconds;
  the old fixed-tick scanner took 75+ seconds.
- Out-of-range retry cooldown reduced from 120s to 15s — stragglers who walk into
  range are captured in seconds instead of minutes.
- Paper-doll browser: pick a snapshot, pick a member, see their gear laid out like
  the character frame with native tooltips. Shift-click to link items.
- Talent tree capture (full detail for yourself; tree names and icons for
  inspected players — the Anniversary API doesn't expose inspected point counts to
  any addon).
- Enchant/gem count summary per character; snapshot retention 1/7/14/30 days.
- Reuses the `ArmorySnapDB` saved variable, so archives from the standalone addon
  carry over automatically.
- Detects the standalone addon and stands down if both are loaded, preventing
  inspect conflicts.
- Keeps the standalone `/as` commands; adds `/wmachine armory`.

---

## 2.8

### Patch 2.5.6 support

- Interface bumped to `20506` (TBC Anniversary patch 2.5.6); Classic Era to `11508`.
- Removed stale `Interface-Wrath` / `Interface-Cata` declarations for clients that
  no longer exist.

### New module — Buff Check

Full raid buff audit that runs automatically on every ready check.

- **You start the ready check** → missing buffs are announced to raid/party chat.
- **Someone else starts it** → the same report prints locally, where only you see it.
- Tracks Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings, Divine
  Spirit, Shadow Protection, Well Fed, and Flasks. Each individually toggleable.
- Class buffs are only checked when the providing class is actually in the group —
  no priest means no Fortitude nagging.
- Only classes a buff applies to are checked; rogues aren't flagged for missing
  Intellect.
- Offline and dead players are skipped and listed separately in the local report.
- Long reports are split to respect the chat message length cap.
- "Run Check Now" button for manual local checks; optional "all buffs up!"
  confirmation.

### Buff Check — PallyPower integration

- When PallyPower is running and paladins in the group have assignments, each
  player is checked against their **assigned** blessings and the report names the
  exact missing blessing ("Missing Blessing of Kings: Player1").
- Greater and normal blessing versions both satisfy an assignment.
- Only assignments from paladins actually in the group are honored, so stale
  assignments from an absent paladin can't generate false nags.
- Reads PallyPower's own runtime tables (`ClassID` / `Spells` / `GSpells`), so the
  mapping stays correct across PallyPower versions and localized clients.
- Graceful fallback to the generic "any blessing" check when PallyPower is absent,
  unconfigured, or the toggle is off.

### Auto Logger — Advanced Combat Logging guard

- Verifies the `advancedCombatLogging` CVar **on login** and again **before combat
  logging starts in a raid**, re-enabling it with a chat notice if something turned
  it off. Warcraft Logs uploads are incomplete without it.
- New settings checkbox and live CVar status display in the panel.
- Fixed a local variable shadowing the global `type` function in instance
  detection.

### Mail & Trade Logger — duplicate entries on bulk mail pulls

- **Root cause 1**: the take hooks logged on every *attempt*. Bulk-pull addons
  retry the same slot until the server responds, producing one log entry per retry.
- **Root cause 2**: mail data came from a snapshot cache refreshed 0.1s after
  `MAIL_INBOX_UPDATE`. Mail deletion shifts inbox indices, so takes during bulk
  pulls read stale cache entries and logged the wrong mail's data.
- Hooks now read the inbox **live** at take time, with a per-slot dedupe
  fingerprint that resets whenever the inbox actually changes — so twelve
  identical mails from your bank alt still log as twelve entries, but retries of
  the same take are suppressed.
- `AutoLootMailItem` is now hooked, so the client's "Open All Mail" button pulls
  are logged. Previously they were silently missing.

### Whisper Logs — correct Warcraft Logs partition

- URLs pointed at `classic.warcraftlogs.com`, the old 2021 TBC progression era.
  Anniversary realms live on `fresh.warcraftlogs.com`.
- Entries already saved from older versions are migrated automatically on login.

### Performance pass

- **Keyword Monitor**: result rows are pooled and reused. Previously every row was
  recreated once per second while the window was open — WoW never garbage-collects
  frames, so this leaked memory permanently.
- **Whisper Logs**: entry rows pooled and reused instead of recreated on every
  whisper or refresh.
- **Mail Logger**: inbox re-caching uses a single debounced timer instead of
  creating a new frame on every `MAIL_INBOX_UPDATE` event.
- **Debuff Tracker**: target debuff scanning uses precomputed name/spellID lookup
  tables instead of nested linear searches. This runs 5× per second.
- **Core**: the module color table is hoisted out of the print functions; it was
  being rebuilt on every chat message.

### Housekeeping

- Fixed the unknown-command hint pointing at `/wm`, which was never registered.
- Corrected module version markers and the theme coverage module count.

---

## 2.7 and earlier

See the version history in `README.md` for releases prior to 2.8.
