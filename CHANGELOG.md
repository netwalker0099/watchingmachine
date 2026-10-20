# Watching Machine — Changelog

All notable changes to Watching Machine. Versions are listed newest first.

Current release: **3.5** — TBC Classic Anniversary patch 2.5.6 (Interface `20506`)

---

## 3.5

### Class Tools — first class features, and a shared warning frame

3.4 shipped the framework. 3.5 is what plugs into it.

Features no longer each build their own alert window or their own timer. They
call `SetAlert(key, text, icon)` / `ClearAlert(key)`, and Class Tools collects
everything into **one movable *CHECK YOURSELF* frame** (up to six lines),
hidden the moment the last warning clears. Registered monitors share a single
one-second tick, so the cost does not grow with the number of checks.

Frame options are in the panel, under the feature list: sound on a new
warning, lock in place, reset position, and **Show example** — two dummy lines
for six seconds so the frame can be found and positioned without waiting for a
real warning.

### New module — Class: Warlock

- **Armor** — warns when Fel Armor, Demon Armor or Demon Skin has fallen off.
- **Demonic Sacrifice** — warns only when the talent is actually taken *and*
  no demon is out. A warlock standing there with a pet has made a choice, not
  a mistake, so nothing is raised.
- **Soul Link** — warns only when talented, with a living pet, and with no
  sacrifice buff up. The two checks interlock: a sacrificed warlock is never
  nagged about Soul Link, and a warlock with a pet out is never nagged about
  the sacrifice.
- **Soulstone timers** — the group is scanned for the Soulstone Resurrection
  buff, which carries a real expiration time. Reading the buff rather than
  watching for casts means it works for soulstones applied by any warlock,
  including ones cast before you logged in. `/wmachine soulstone` lists who is
  stoned and for how long.

Talents are read by name across all trees (self-inspection is reliable in TBC
Classic) and cached for five seconds. The cache is dropped outright on
`CHARACTER_POINTS_CHANGED` / `PLAYER_TALENT_UPDATE`, so a respec takes effect
immediately rather than at the end of the TTL.

### New module — Class: Mage

- **Armor** — warns when Molten, Mage, Ice or Frost Armor is missing.
- **Portal / teleport button** — a single draggable button that expands on
  hover into every teleport and portal you know, portals first. It is built
  from your spellbook, so it shows exactly what you can cast and nothing else,
  and rebuilds on `LEARNED_SPELL_IN_TAB` / `SPELLS_CHANGED`.

The spellbook scan derives the `Teleport:` / `Portal:` prefixes from
`GetSpellInfo` on two known spell IDs rather than hardcoding English strings,
so it works on localised clients.

The flyout deliberately refuses to expand in combat. Its entries are
`SecureActionButtonTemplate` buttons, which cannot be created or reconfigured
during combat lockdown; since portals aren't castable in combat either,
declining to open is honest behaviour rather than a limitation worth working
around with secure state drivers.

### New module — Class: General

Consumable checks that apply to every class, under a **General** tab that
always sorts first.

- **Flask**, **food buff** (Well Fed) and **weapon oil / stone**.
- Active **only inside a raid instance**, and **25-man only by default**, with
  a tick to include 10-mans. No nagging in town or while questing.
- The wording follows your class: casters are told about wizard oil, melee
  about sharpening stones and weightstones.
- The off hand is checked only when a real weapon is equipped there. Shields
  and held items occupy the same slot and can't take an oil, so they are
  skipped rather than producing a permanent, unfixable warning.
- Flask matching is on substring, so `Unstable Flask of the Beast` and
  `Unstable Flask of the Sorcerer` count alongside the standard flasks.
- `/wmachine consumes` prints what the checks currently see.

Classic exposes only *whether* a temporary weapon enchant is present, not
which one, so the check is presence-based — an oil on a melee weapon will
satisfy it.

### New commands

- `/wmachine class` — open Class Tools (`/wmachine classes`, `classtools`)
- `/wmachine soulstone` — soulstone timers (`soulstones`, `ss`)
- `/wmachine portals` — list known teleports and portals (`teleports`)
- `/wmachine consumes` — what the general checks see (`consumables`)

### Saved variables

`ClassToolsDB`, `GeneralChecksDB` and `MageToolsDB` are declared in the TOC.

---

## 3.4

### Mail Logger — Open All logged by diffing the inbox

The dedupe added in 3.2 could not work during an Open All, for two reasons:

- Its key embedded `mailIndex`, but indices shift as each mail is emptied, so
  the same physical mail produced a different key after a shift and was logged
  again.
- The guard was wiped on every `MAIL_INBOX_UPDATE`, and that event fires
  continuously throughout a bulk pull — erasing the guard before it could
  suppress anything.

It held up when clicking mail slowly, which is what the earlier tests
simulated, because those tests controlled when `MAIL_INBOX_UPDATE` fired.

Replaced with content diffing. Every receivable unit (money, and each
attachment) is fingerprinted by sender / subject / item / count into a
multiset; the inbox is re-read every 0.4s while the mailbox is open, and
whatever disappeared is logged. This is:

- immune to retries — a retry changes nothing in the inbox,
- immune to index shifts — no index appears in the key,
- correct for N identical mails — multiset counts,
- independent of which API the open-all uses, or how fast it runs.

Details:

- The take hooks no longer log. `ReturnInboxItem` and `DeleteInboxItem` are
  hooked only to suppress mail that leaves *without* being received.
- No diff on `MAIL_CLOSED`: the client can report an empty inbox afterwards,
  which would look like everything was collected.
- An empty read is held for one poll before being trusted, so a momentary blip
  can't mass-log, while genuinely emptying the last mail still records.

### New module — Class Tools

Detects the class you're playing and surfaces the tools built for it.

- Class section in the dashboard (`/wmachine class`) with a tab per class.
  A tab appears only once a feature has been registered for that class, so
  there are no empty tabs for work not yet done.
- Your own class is selected on open, and is always offered as a tab even
  before it has tools, so the panel explains itself.
- Per-feature toggles saved per class; the same feature key on two different
  classes keeps independent state.
- Ships as the framework: features call `RegisterFeature(class, def)` and
  appear in the panel automatically, then query `IsEnabled` /
  `IsActiveForPlayer` without touching the UI. Registration before the saved
  variables load is supported.

### Dashboard — card list now scrolls

With 13 modules the card list needed 634px inside a 585px area, so the last
card was cut off, and the panel can't grow past the ~768px screen. The list is
now a scroll frame, which also stops this recurring as more modules land.

## 3.3

### Debuff Tracker — Black Temple shadow resist gear check

Mother Shahraz is the only Black Temple fight that wants shadow resist gear, and
staying in it for the rest of the raid is an easy and costly mistake.

- Arms when Mother Shahraz dies, **and** the moment you engage one of the Grand
  Promenade pulls (Shadowmoon Reaver, Promenade Sentinel, Illidari Archon /
  Assassin / Battle-mage / Blood Lord) — so a `/reload` after Mother is already
  down still works.
- Reads **equipped gear only** via item stats, never `UnitResistance`, so Shadow
  Protection or a Shadow Resistance Aura can't produce a false warning.
  Matches both item-stat key conventions, since they differ between clients.
- Configurable threshold (default 60 gear SR) so a single piece with incidental
  resistance is ignored; a Mother set runs well over 200.
- Warns locally with a raid-warning flash and a sound; optional Say / Party /
  Raid / `/rw` announce. Deliberately **not** gated by the leader-announcer rule
  used elsewhere, because it concerns the individual player's own gear.
- One warning per pull (20s cooldown). Disarms on zone change.
- `/wmachine srcheck` lists every equipped piece carrying shadow resistance, the
  total against the threshold, whether it is armed, and cross-checks the
  character sheet so a broken item API is obvious rather than silent.

### Debuff Tracker — settings panel split (fixes clipped controls)

The settings panel had grown from its original 700px to 948px as features were
added. WoW's UIParent is only about 768px tall at UI scale 1.0, so the lowest
controls were off-screen and unreachable.

- Encounter callouts (Illidan Doom warning, Illidan Shear monitor, shadow resist
  check) moved into their own window, opened with `/wmachine encounters` or the
  **Encounter Callouts...** button in Debuff Tracker settings.
- The main panel is back to 742px and fits on screen again.

### Debuff Tracker — Shear settings completed

- Added the missing **chat throttle** slider (0–30s; throttled Shears are still
  counted and still shown locally, only the chat line is skipped).
- Added the missing **pull summary** checkbox.
- Removed the redundant `shearAnnounce` flag — the *Me only* channel option
  already does the same thing.

## 3.2

### Debuff Tracker — Illidan Shear monitor

Tracks Shear on Illidan's main tank and calls it out, with a toggle in the
Debuff Tracker settings (on by default).

Shear cuts the main tank's maximum health by roughly 60% for a few seconds,
cannot miss, but can be dodged, parried or blocked. Damage meters under-report
it for two reasons: the damaging part is a max-health debuff rather than a
normal hit, and an avoided Shear produces only a miss event with no damage at
all. So the monitor is deliberately aggressive:

- Watches every subevent a Shear can produce — `SPELL_CAST_START`,
  `SPELL_DAMAGE`, `SPELL_AURA_APPLIED`, `SPELL_AURA_REFRESH` and
  `SPELL_MISSED` (dodge / parry / block / immune / absorb).
- Matches on spell ID **and** localized spell name, so an unexpected or
  unlisted ID still registers, and non-English clients work.
- Sweeps raid auras on `UNIT_AURA` as a backup, catching a landed Shear even
  if its combat-log event is dropped. Only active once Illidan or a Shear has
  been seen in the pull, so it costs nothing elsewhere.
- Deduplicates per cast: the several events one Shear generates produce a
  single call, not three.
- Ignores anything sourced from your own group, so nothing else can spoof it.

Reporting:

- Hits are announced to raid chat by default; avoided Shears are counted but
  not announced (Shear repeats every ~10s, so calling both outcomes doubles the
  chat). Both are always shown locally.
- Channel picker: Me only / Say / Party / Raid / `/rw`, plus an optional
  throttle for the minimum gap between chat calls.
- Optional local cast warning on `SPELL_CAST_START` — the ~1.5s window to use
  Shield Block or Holy Shield. Never sent to chat.
- Per-pull summary when combat ends: total, hit vs avoided, a per-tank
  breakdown (so tank swaps are visible), and which avoidance types occurred.
- Uses the existing announcer rule, so only the raid leader (or assistants, if
  allowed) sends to chat and multiple addon users don't duplicate it.
- `/wmachine shear` shows status and tallies; `/wmachine shear on|off` toggles.

### Debuff Tracker — Illidan Doom warning

**Added**
- Sends **CAST DOOM NOW** as a raid warning when Illidan Stormrage (npcID 22917)
  drops to 68%, so warlocks land Curse of Doom before he lifts off at 65%.
- New checkbox in Debuff Tracker settings: *Illidan 68%: raid warn "CAST DOOM NOW"*
  (on by default).
- Fires once per pull. Illidan is found through any unit pointing at him (boss
  frames, target, focus, raid targets, nameplates), so you don't have to be
  targeting him.
- Follows the existing announcer rule: the raid leader sends it (assistants only when
  "Assistants can announce" is on); everyone else gets a local chat line. Falls
  back to /raid if the sender has no assist.
- Skipped if Illidan is already below 60% when first seen (for example after a
  /reload mid-fight).

### Buff Check — elixir and flask fixes

**Fixed**
- Elixir of Empowerment is now classed as a Guardian elixir (was Battle).
- Elixir of Major Defense is classed as a Guardian elixir (it had been put in the
  Battle list, so tanks pairing it with a battle elixir were flagged).
- Flask matching is substring-based, so "Unstable Flask of the Beast/Sorcerer"
  now counts for the flask and both elixir slots.
- Expanded the Battle/Guardian elixir lists with missing TBC and classic-era entries.

**Added**
- `/wmachine whybuff` (alias `buffdebug`): lists every aura on your target or
  yourself and which check each one satisfies.

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
