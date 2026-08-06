# Release announcement — Watching Machine 3.1

Copy-paste ready text for Discord and CurseForge. The canonical, full-detail
changelog lives in [`CHANGELOG.md`](../CHANGELOG.md).

---

# ═══════════════  DISCORD  ═══════════════

Discord caps messages at 2000 characters, so this is split into four posts.
Send them in order — each is self-contained and under the limit. Discord
markdown supports `#`/`##`/`###` headers, `**bold**`, `` `code` `` and lists,
but **not** tables.

---

## ▸ Discord post 1 of 4

```
# 🔧 Watching Machine 3.1 is out

Updated for **TBC Anniversary patch 2.5.6** (Interface 20506).
Three new modules, a much faster gear scanner, and a pile of fixes.

## 🆕 New: Buff Check
Full raid buff audit on every ready check.
- **You** run the ready check → missing buffs announced to raid chat
- **Someone else** runs it → same report, but only you see it
- Checks Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings, Divine Spirit, Shadow Protection, Well Fed, Flasks, Battle Elixirs and Guardian Elixirs
- Only nags for buffs your raid can actually provide — no priest, no Fortitude spam
- Rogues aren't flagged for missing Intellect; dead and offline players are skipped
- Flasks correctly satisfy **both** elixir slots

**PallyPower integration**: if paladins have assignments set, each player is checked against their *assigned* blessing and the report names it exactly — "Missing Blessing of Kings: Bobtank". Single-target assignments override that paladin's class blessing, so a feral tank on single Might is never flagged for missing class Salvation.

`/wmachine buffcheck`
```

---

## ▸ Discord post 2 of 4

```
## 🆕 New: Aura Range
Alerts when you walk out of range of party auras and shaman totems.

- Watches Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin auras, and totems (Strength of Earth, Grace of Air, Wrath of Air, Totem of Wrath, Mana Spring, and more)
- Movable pulsing on-screen alert showing exactly what you lost, plus an optional sound
- Clears the instant you step back into range
- Won't false-alarm on death, provider death, zoning, or leaving the group
- Stale alerts auto-expire for totems that simply ran out

`/wmachine range`

## 🆕 New: ArmorySnap (integrated)
The standalone ArmorySnap addon is now built in — passive raid gear, enchant, gem and talent snapshots with a paper-doll browser.

- **Scans ~4.5x faster**: a full 25-man captures in about 15–20 seconds instead of 75+
- Out-of-range players retried every 15s instead of every 2 minutes
- Your existing ArmorySnap archive carries over automatically
- Disables itself if you still have the standalone addon loaded

`/wmachine armory` or `/as`
```

---

## ▸ Discord post 3 of 4

```
## 🎯 Debuff Tracker — false alerts fixed

**Raid trash was triggering boss alerts.** The old check treated any level 72–73 elite as a boss, which is exactly what TBC raid trash is — Magtheridon's Hellfire Warders being the obvious case.

- Mobs are now identified by **npcID**, not display name, so mobs that share a name are told apart properly
- A **health-pool floor** (adjustable) separates trash from real bosses regardless of level

**Multi-boss fights no longer misfire.** On Fathom-Lord Karathress, targeting a guard the raid is ignoring used to set alerts off.

- The addon now tracks which mob is taking the most raid damage and only alerts for **that** one
- It follows your kill order automatically — Tidalvess → Sharkkis → Karathress, or straight to the Fathom-Lord, no config either way

**Escape hatches** if something still slips through:
- `/wmachine exclude` — target a mob, never treat it as a boss again
- `/wmachine whyboss` — prints exactly why the addon does or doesn't consider your target a boss
```

---

## ▸ Discord post 4 of 4

```
## 🐛 Fixes & performance

**Mail Logger — duplicate entries on bulk mail pulls.** Two bugs: entries were logged per take *attempt* (bulk-pull addons retry until the server answers), and mail data came from a cache that went stale as inbox indices shifted. Hooks now read live with per-slot dedupe. The "Open All Mail" button is also hooked now — those pulls were previously never logged at all.

**Auto Logger — Advanced Combat Logging guard.** Checks the CVar on login *and* when entering a raid, re-enabling it if something turned it off. Warcraft Logs uploads are incomplete without it.

**Whisper Logs — correct WCL links.** URLs pointed at the old 2021 progression partition; Anniversary realms live on `fresh.warcraftlogs.com`. Saved entries migrate automatically.

**Performance.** Fixed permanent frame leaks in Keyword Monitor and Whisper Logs (rows were recreated every refresh — WoW never frees frames), debounced Mail Logger's inbox caching, and replaced the Debuff Tracker's nested scans with lookup tables (that path runs 5x/second).

⬇️ Grab it on CurseForge or GitHub. Full changelog in the repo.
```

---

# ═══════════════  CURSEFORGE  ═══════════════

CurseForge's changelog field accepts markdown, including tables. Paste the
block below as-is.

---

## Watching Machine 3.1

**Updated for TBC Classic Anniversary patch 2.5.6** (Interface `20506`, Classic Era `11508`).

This release adds three modules, makes raid gear scanning roughly 4.5× faster, and fixes several classes of false alerts and duplicate log entries.

### At a glance

| | |
|---|---|
| **New modules** | Buff Check, Aura Range, ArmorySnap (integrated) |
| **Major fixes** | Debuff Tracker false boss alerts, Mail Logger duplicates, WCL link partition |
| **Performance** | ~4.5× faster gear scans, two permanent frame leaks fixed |
| **Client** | TBC Anniversary 2.5.6 |

---

### New module: Buff Check

Runs a full raid buff audit on every ready check.

- **When you start the ready check**, missing buffs are announced to raid/party chat.
- **When someone else starts it**, the identical report prints locally where only you can see it.
- Tracks Fortitude, Mark of the Wild, Arcane Intellect, Paladin Blessings, Divine Spirit, Shadow Protection, Well Fed, Flasks, Battle Elixirs and Guardian Elixirs — each individually toggleable.
- Class buffs are only checked when the providing class is actually in the group, and only against classes the buff applies to (rogues are never flagged for Intellect).
- Dead and offline players are skipped and listed separately.
- Flasks satisfy both the Battle and Guardian elixir slots, per TBC's consumable rules.
- Long reports are split to respect the chat length cap. Includes a "Run Check Now" button for manual local checks.

**PallyPower integration** — when PallyPower is running with assignments configured, each player is checked against their *assigned* blessings and the report names the exact missing blessing. Greater and normal versions both count. Single-target assignments correctly override that paladin's class-wide blessing, so a feral tank assigned single Might is not flagged for missing the class Salvation. Falls back to a generic "any blessing" check when PallyPower is absent or unconfigured.

Command: `/wmachine buffcheck`

---

### New module: Aura Range

Visual and audio alerts when you drift out of range of party auras and shaman totems. These buffs drop the instant you leave their radius, so the module watches your own auras event-driven — no polling, and it fires the same frame you step out.

- Tracks Moonkin Aura, Leader of the Pack, Trueshot Aura, Tree of Life, Paladin auras, and totem buffs including Strength of Earth, Grace of Air, Wrath of Air, Totem of Wrath, Mana Spring, Healing Stream, Stoneskin and Windfury.
- Movable, pulsing on-screen alert listing exactly which auras you lost, with icons. Clears the moment you walk back into range.
- Optional raid-warning sound, throttled so losing several totems at once doesn't spam you.
- Suppresses false alarms from death, provider death, zone transitions, and leaving the group. Stale alerts auto-expire (5–30s) for totems that simply expired.

Command: `/wmachine range`

---

### New module: ArmorySnap (integrated)

The standalone ArmorySnap addon is now a built-in module, including its v1.2 scanner overhaul.

- **Roughly 4.5× faster scanning.** Inspects now chain event-driven — the next request fires the moment the previous one resolves — instead of waiting on a fixed 3-second ticker. A full 25-man with everyone in range captures in about 15–20 seconds; previously 75+ seconds.
- Out-of-range members are retried every 15 seconds instead of every 2 minutes.
- Passive gear snapshots including enchants and gems, browsable in a paper-doll view with native tooltips.
- Talent tree capture, enchant/gem summaries, and snapshot retention of 1/7/14/30 days.
- **Uses the same `ArmorySnapDB` saved variable**, so archives from the standalone addon carry over automatically.
- Detects the standalone addon and stands down if both are loaded, preventing inspect conflicts.

Commands: `/wmachine armory`, or the original `/as` set.

---

### Debuff Tracker: false boss alerts eliminated

**Raid trash was being treated as bosses.** The detection accepted any mob at `level >= playerLevel + 3` with elite classification — which describes TBC raid trash exactly as well as it describes real bosses. Magtheridon's Hellfire Warders were the clearest case, and display names couldn't separate them since some trash shares names with encounter mobs.

- Mobs are now identified by the **npcID** embedded in their creature GUID, which is unique per creature type even when display names collide.
- A **health-pool floor** (default 150,000; adjustable 0–400k) separates trash from bosses independently of level and classification.

**Multi-boss encounters no longer misfire.** On Fathom-Lord Karathress, targeting a Fathom-Guard the raid was ignoring would start the alerts.

- Group damage is now accumulated per hostile mob over a rolling 6-second window. The mob absorbing the most raid damage is the real kill target, and alerts fire only for it.
- The focus follows your raid automatically as the kill order progresses, and adapts to any strategy — a standard Tidalvess → Sharkkis → Karathress order and a straight Fathom-Lord burn both work with no configuration.
- Fails open: a stale focus never suppresses alerts permanently.

**Escape hatches** for anything the heuristics still get wrong:

- `/wmachine exclude` — with a mob targeted, permanently stops that creature type triggering boss alerts. Keyed on npcID, so same-named mobs elsewhere are unaffected. Also `/wmachine unexclude` and `/wmachine exclusions`.
- `/wmachine whyboss` — prints exactly how the tracker sees your target: npcID, classification, level, health vs. the floor, exclusion state, current raid focus, and whether an alert would fire.

---

### Fixes

**Mail & Trade Logger — duplicate entries when bulk-pulling mail.** Two compounding bugs: the take hooks logged on every *attempt* (bulk-pull addons retry the same slot until the server responds, producing one entry per retry), and mail data came from a snapshot cache that went stale as mail deletion shifted inbox indices, causing takes to log the wrong mail's data. Hooks now read the inbox live at take time with a per-slot dedupe fingerprint that resets when the inbox actually changes — so genuinely identical mails still log individually, but retries are suppressed. `AutoLootMailItem` is now hooked as well, so the client's "Open All Mail" button pulls are logged; previously they were silently missing.

**Auto Logger — Advanced Combat Logging guard.** Verifies the `advancedCombatLogging` CVar on login *and* before combat logging starts in a raid, re-enabling it with a chat notice if it was turned off. Warcraft Logs uploads are incomplete without it. Includes a settings toggle and live CVar status display.

**Whisper Logs — correct Warcraft Logs partition.** URLs pointed at `classic.warcraftlogs.com`, the old 2021 TBC progression era; Anniversary realms live on `fresh.warcraftlogs.com`. Previously saved entries are migrated automatically on login.

---

### Performance

- **Keyword Monitor**: result rows are pooled and reused. Previously every row was recreated once per second while the window was open — WoW never garbage-collects frames, so this leaked memory permanently.
- **Whisper Logs**: entry rows pooled instead of recreated on every whisper or refresh.
- **Mail Logger**: inbox re-caching uses one debounced timer instead of creating a new frame per `MAIL_INBOX_UPDATE`.
- **Debuff Tracker**: target scanning uses precomputed name/spellID lookup tables instead of nested linear searches — that path runs 5× per second. Group membership lookups during combat log processing are now a cached hash set instead of a 40-unit scan per event.
- **Core**: the module color table is hoisted out of the print functions instead of being rebuilt on every chat message.

---

### Upgrade notes

- Existing settings and saved data carry over; no reset needed.
- If you run the **standalone ArmorySnap addon**, disable it — the integrated module stands down while it's loaded, and running both would fight over the game's single inspect slot.
- Battle and Guardian Elixir checks in Buff Check are **off by default**; enable them in `/wmachine buffcheck` if your raid requires them.
- The Debuff Tracker's boss health floor defaults to 150k, tuned for T4/T5. If a boss ever reads as "not a boss", lower it with the slider — `/wmachine whyboss` will tell you what it's seeing.
