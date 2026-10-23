# To do

Planned work that hasn't been started. Each item notes what's decided and
what still needs settling before it's built.

1. ~~Mana potion / rune alert~~ (done, 3.14)
2. ~~Audio trigger for alerts~~ (done, 3.26 and 3.32)
3. ~~Melee swing timer~~ (done, 3.17)
4. ~~Warlock button: armors and demon summons~~ (done, 3.15)
5. ~~Shaman totem bar with quick sets~~ (done, 3.16)
6. ~~Flyout buttons: open on hover or on click~~ (done, 3.15)
7. ~~Flyout directions: add "Hidden", and use dropdowns~~ (done, 3.15)
8. ~~Dock flyout buttons together~~ (done, 3.15)
9. Instance tracker: lockouts, instance log and run stats (core done, 3.22)
10. ~~Gold trade alerts and trade log by instance~~ (done, 3.25)
11. ~~Alt tracking: "Your Characters"~~ (done, 3.27)
12. ~~PvP instance log: battleground and arena stats~~ (done, 3.27)
13. ~~World buff timers, Songflowers and Darkmoon Faire~~ (done, 3.28)

---

## 1. Mana potion / rune alert — DONE in 3.14

Built in Class Tools > General. The open questions were settled as:

- **Cooldowns:** runes have their own cooldown, separate from potions
  (confirmed in game).
- **When it runs:** in combat, inside raid instances, following the General
  25-man toggle.
- **Thresholds:** click-to-cycle choices (potion 2000–5000, rune 1000–3000),
  defaulting to 3000 / 1500.
- **Flicker:** a warning clears only once mana is 500 back under its
  threshold.
- **Rune and health:** no rune warning below 35% health.
- **When the rune applies:** when no potion is *ready*, whether on cooldown
  or none carried.
- **Still to confirm in game:** the item IDs, especially Cenarion Mana Salve
  `32903`, Bottled Nethergon Energy `32902`, Fel Mana Potion `31677`, Mad
  Alchemist's Potion `34440` and Unstable Mana Potion `28101`.

---

## 2. Audio trigger for alerts

**Built in 3.26:**
- `WM.Sounds` (`Sounds.lua`) and a sound argument on `CT:SetAlert`
- per-warning sound dropdowns for the mana potion and rune warnings,
  defaulting to the addon's own `potion.ogg` / `rune.ogg`
- picking a sound plays it (the test)
- a channel option (Master / Sound effects / Dialog)
- each sound plays once per appearance, throttled

**Built in 3.32:** the rest of it.
- [x] Sound choices for every other Class Tools warning (the Warning sounds
      section, `CT:RegisterAlertSound`, `CT:SetAlertSound`).
- [x] The swing timer's SYNC NOW sound.

(The original notes follow.)

A sound that plays when an alert fires. It should cover the mana potion /
rune alerts first, and be built so any Class Tools alert can use it.

**What exists today:** the *CHECK YOURSELF* frame has one global option,
*sound on a new warning*, which plays the same sound for any new line.

**Idea:**
- **Per-alert sounds:** an optional sound per alert (`SetAlert(key, text,
  icon, sound)`), so "Use a mana potion" and "Use a rune" can sound
  different from each other and from the other warnings.
- **Choosing a sound:** a dropdown (`WM.UI.Dropdown`) of built-in sounds
  (`PlaySound` kit IDs). Maybe also a few `PlaySoundFile` media files
  shipped with the addon. The choice saves per alert.
- **Volume:** play on a chosen sound channel (Master / SFX / Dialog), so it
  can be heard with game sound turned down.
- **Repeats:** throttle, so a repeating alert sounds once per appearance,
  not every tick.
- **Testing a sound:** a "Test sound" button next to each choice.

**To settle:**
- [ ] **Scope:** per-alert sounds for all Class Tools alerts, or just the
      mana / rune ones first?
- [ ] **Custom files:** ship custom sound files, or built-in sounds only?
      Shipped files add to the addon's size and need a licence check.
- [ ] **Repeat:** should a sound repeat while the condition persists, for
      example every 10s if you still haven't drunk the potion, or sound once?

---

## 3. Melee swing timer — DONE in 3.17

Built as `Modules/SwingTimer.lua`, with its options in Class Tools >
General. Settled as:

- **Reference:** the rules come from the established TBC timers
  (LibClassicSwingTimerAPI, WeakAuras, WeaponSwingTimer, Quartz) and
  enhancement guides, not from Leatrix Plus. No code was copied.
- **Which classes:** warriors, rogues, Retribution paladins and Enhancement
  shamans (spec read from talents), plus hunters with an Auto Shot bar. An
  option covers every class.
- **Off hand:** shown whenever you dual wield.
- **Latency:** shown as a zone at the end of each bar; press-now marks are
  moved earlier by it.
- **Shaman sync:** a mark for the sync macro, plus an in-sync readout.
- **Tests:** `tests/test_swing.lua` drives a fake combat log.
- **Still to confirm in game:** how Windfury Weapon's extra attack is
  logged, and whether the Auto Shot wind-up scales with haste.
- **Not built:** a Windfury cooldown bar and Flurry charges.

---

## 4. Warlock button — DONE in 3.15

One warlock button (warlock crest) with three groups, each with its own
direction or Hidden:

- **Demons,** nearest first: Felguard (appears only if talented), Succubus,
  Imp, Felhunter, Voidwalker. No Fel Domination.
- **Armors:** Fel Armor, Demon Armor, Demon Skin, each casting its highest
  rank.
- **Stones & rituals:** Soulwell (Ritual of Souls), Ritual of Summoning,
  Healthstone, Soulstone. Stone ranks are separate names ("Create
  Healthstone (Major)"), so these are matched by prefix and the highest is
  kept.
- **Shard count:** shown on every icon whose spell uses a Soul Shard (all the
  demons except Imp, and all four stones and rituals). It updates on
  `BAG_UPDATE`, in combat too.
- **Groundwork:** the flyout engine moved to `Modules/ClassFlyout.lua`
  (`WM.Flyout`), shared by the mage and warlock buttons.
- **Still to confirm in game:** the spell IDs, used only for localized
  clients. English names already match.

---

## 5. Shaman totem bar — DONE in 3.16

Built as one totem button in Class Tools > Shaman. The open questions were
settled as:

- **Where it lives:** a Shaman tab feature, on the shared flyout engine, so
  it docks and locks with the other buttons.
- **Drop method:** `/castsequence`, Air, Water, Earth, then Fire (fire
  always last). It starts again from Air when no totems are down, after
  combat, or on Ctrl-click.
- **Sets:** four, named and editable, premade as Melee, Caster, Healer and
  Tremor, saved per character (`ShamanToolsDB`). Picked by hovering the
  button.
- **Status:** the reset uses `GetTotemInfo` / `PLAYER_TOTEM_UPDATE`; the
  button skips it if the client lacks them.
- **Still to confirm in game:** that a sequence reset in combat waits for
  combat to end cleanly, and the totem spell IDs (used only for localized
  clients).
- **Not built:** a keybinding (Bindings.xml) for the button, and per-totem
  timers on the bar.

---

## 6. Flyout buttons: open on hover or on click — DONE in 3.15

A single option for every flyout, in Class Tools > General: *Flyout buttons
open: On hover / On click*. In click mode a click toggles the flyout, moving
away doesn't close it, and picking a spell does (`PostClick`).

---

## 7. Flyout directions: "Hidden" and dropdowns — DONE in 3.15

- **Hidden:** every flyout direction option includes it. A hidden group
  isn't placed, and the remaining groups start next to the button. If every
  group is hidden, the button's tooltip says so.
- **Dropdowns:** Class Tools choice options are now dropdowns, for every
  class. That covers the directions, the mana thresholds and the flyout
  settings.

---

## 8. Dock flyout buttons together — DONE in 3.15

Built for every class's flyout buttons, as a setting rather than snapping.

- **Setting:** in Class Tools > General, tick *Dock flyout buttons
  together* and choose a *Docked layout*: row left to right or right to
  left, or column downwards or upwards.
- **Group:** the visible buttons line up from the first one (the lead),
  which keeps its saved position. Dragging any docked button moves the lead,
  and the rest follow.
- **Undocking:** each button goes back to its own saved position.
- **Lock:** one shared *Lock flyout buttons* option replaces the mage-only
  lock, and carries the old setting over once.
- **Combat:** docking changes made in combat apply when it ends.

---

## Items 9–13: guidance from Nova Instance Tracker and Nova World Buffs

Items 9–13 take their feature lists from two addons by Novaspark:

- **Nova Instance Tracker (NIT):**
  <https://github.com/curseforge-mirror/nova-instance-tracker/releases>
- **Nova World Buffs (NWB):**
  <https://github.com/curseforge-mirror/nova-world-buffs/releases>

They're **guidance only**: read them for the approach, events and edge
cases, then build the features on what Watching Machine already has. Their
licences need checking before any code is reused, the same caution as the
Leatrix Plus note in item 3. Copying is out unless a licence allows it.

### Talking to Nova users: their sync protocol comes first

Watching Machine must be able to **listen to and broadcast on Nova's own
addon messages**:
- world buff, Songflower, tuber and Darkmoon Faire timers, with their layer
- buff dropped / NPC killed / NPC walking notices
- instance reset notices (NIT)

That way a Watching Machine user and a Nova user in the same guild or group
share one set of timers. So before items 9 and 13 are built, the protocol is
worked out from Nova's released code and written down in
`docs/NOVA-PROTOCOL.md`.

**What to record**, for NWB and NIT each:
- **Prefixes:** the addon-message prefixes, and which channels each one is
  sent on (GUILD, PARTY / RAID, YELL, WHISPER, a custom channel), and when.
- **Libraries:** whether messages go through AceComm (which splits long
  messages into parts) and are packed with AceSerializer and / or LibDeflate,
  or are plain strings. The exact encode / decode steps, so we can produce
  byte-identical messages.
- **Message types:** every type with its fields in order: timers per buff and
  per layer, Songflower spawns, reset notices, version / handshake messages,
  and requests ("send me your timers").
- **Version checks:** which versions accept which messages, and how old or
  newer senders are handled.
- **Trust rules:** whose data is accepted (guild only? sanity limits on
  timestamps? who is "the one sender" for guild warnings), so ours follows
  the same rules and never feeds bad timers into Nova users' data.
- **Throttling:** how often each message may be sent, so we never get Nova
  users or ourselves disconnected for addon-message spam.
- **Guild-note flags:** how the `#nwb1`–`#nwb8` tags are read, so we honour
  them.

**How we use it:**
- **Separate code:** a `NovaCompat` part kept apart from our own `WM`
  messages. It decodes their messages into our timer data and encodes ours
  into their format.
- **Options:** listening on, broadcasting off by default, each switchable.
- **Tests:** recorded Nova messages decoded in the test harness, and our
  encoded ones decoded back.

**Licence:** implementing a compatible message format for interoperability
doesn't copy their code. Their source is read to learn the format, and our
encoder / decoder is written fresh. If we bundle a library they use
(AceSerializer, LibDeflate), we take it from its own source under its own
licence.

**Blocked for now:** the released addon zips aren't reachable from the
cloud session. The mirror's GitHub releases need API access the session
doesn't have, and CurseForge (`www.curseforge.com`, `edge.forgecdn.net`),
Wago and WoWInterface are blocked by the network policy. Either:
- allow `edge.forgecdn.net` and `www.curseforge.com` in the environment's
  network settings, or
- upload the `NovaWorldBuffs` and `NovaInstanceTracker` folders from
  `Interface\AddOns`.

What all five should share instead of building their own:

| Need | Already in Watching Machine |
|---|---|
| Windows, lists, options | `WM.UI` panel builder (`Layout:Fill` lists, sections, dropdowns, resizable panels) |
| A home | Dashboard cards (with on/off switch and **...** tools menu), slash commands under `/wmachine` |
| Guild / group messages between users | The addon-message code in PvP Tracker (`SafeSendAddonMessage`, prefix registration); move it to Core as a shared helper first |
| Chat output | `WM:ModulePrint`, Chat Filter's message filter (for clickable links) |
| Per-character saved data | Mail & Trade Logger's `characters[charKey]` layout and character selector |
| Minimap hover | The minimap tooltip already lists every module's status |
| Group roster, zone and instance detection | Debuff Tracker, Buff Check, ArmorySnap and Auto Logger already read these; share one helper rather than a sixth copy |

---

## 9. Instance tracker: lockouts, instance log and run stats

**Built in 3.22 (`Modules/InstanceTracker.lua`):**
- lockouts (hourly / daily, timed from leaving)
- the run log with stats
- same-instance merging by zone UID
- reset handling and the leader's announcement
- run stats on leaving

**Still to do:**
- [x] **Nova Instance Tracker compatibility (3.23, listen only):** NIT
      users' reset notices are shown, with our own leader check, and the
      instance is marked reset. Decided: we don't send in Nova's format.
- [x] **Clickable chat (3.24):** chat lines open the log, and the "Entered"
      line has a red **X** to delete that run.
- [x] **Alts window:** opened from the Instance Tracker window's footer and its
      own card (the minimap right-click stays Settings).

Tracks every instance you enter, on every character and realm, and the
limits on entering them.

**Lockouts:**
- **The two limits:** time left on the **5 instances per hour** and **30 per
  24 hours** limits, across all your characters.
- **Which limit you're on:** say whether you're currently blocked by the
  hourly or the daily limit, so you can tell them apart.
- **Timed from when you leave** an instance, not when you enter it.
- **Same instance again:** re-entering the same instance ID (for example
  another Scarlet Monastery wing on the same ID, or a run you zoned out of)
  doesn't add a duplicate or count again.
- **Minimap hover** shows your lockouts.

**Resets:**
- **Telling the group:** when you reset instances, tell your group.
- **When the leader resets:** tell you if your leader resets, when they run
  Watching Machine, or NIT / NWB (that needs NIT's addon-message format).

**Instance log:**
- **Opening it:** open it from `/wmachine instances`, the dashboard card, or by
  clicking the addon's line in chat.
- **Deleting a wrong entry:** a clickable **[X]** in chat deletes an entry
  that wasn't really a new instance.
- **Hovering an entry** shows the run's stats:
  - every group member's name, level and class
  - the time you entered and left, and the time spent inside
  - mobs killed, XP earned, average XP per mob, and the group's average level
  - raw gold looted from mobs
  - your level going in and coming out (to see where you dinged)
  - every reputation gain (useful for raids)
- **Leaving an instance:** optionally print the run's stats to your chat
  window, or to the group.

**Builds on:**
- Auto Logger's instance detection
- ArmorySnap's roster reading
- the panel builder for the log
- Chat Filter's chat hook for the clickable links and [X]

**To settle:**
- [ ] **Limits on 2.5.6:** confirm the 5 per hour and 30 per 24 hours limits
      apply on Anniversary realms, and how the client reports them. Does the
      error text or `GetSavedInstanceInfo` tell hourly from daily?
- [ ] **Instance ID:** how NIT works out the instance ID on this client:
      `GetInstanceInfo`, the GUIDs of mobs inside, or something else.
- [ ] **Leaving vs disconnecting:** a disconnect or `/reload` inside must not
      end the run.
- [ ] **Raids:** do raids count toward these limits, or appear in the log only?
- [ ] **Compatibility:** listen for NIT / NWB reset messages, send our own, or
      both? It needs their message prefix and format.
- [ ] **Storage:** how many runs to keep per character (a size cap, or by age
      as ArmorySnap does).

---

## 10. Gold trade alerts and trade log by instance — DONE in 3.25

Built into Mail & Trade Logger:
- the gold chat line (clickable, opens the trade log), with its own option
- an instance tag on every trade, tied to the Instance Tracker run so the
  run's tooltip shows the gold traded during it

Settled: the line is for gold, plus item-only trades when notifications
are on, and older trades show no instance.

This is mostly an extension of the **Mail & Trade Logger**, which already
logs trades per character.

- **Chat line:** a line in your chat window whenever you give gold to, or
  receive it from, another player, with the amount and the player.
- **Trade log:** the existing trade log gains an **instance** column: where
  you were when the trade happened (useful for boosters and buyers). It
  needs item 9's "current instance".
- **Option:** the chat line can be turned off, in Mail & Trade settings.

**To settle:**
- [ ] **Chat lines:** for gold only, or for item trades too?
- [ ] **Old entries:** trades logged before this have no instance; show them
      as "—".

---

## 11. Alt tracking: "Your Characters" — DONE in 3.27

Built as `Modules/AltTracker.lua`. Settled:
- **Reagents:** per class, as listed in the module.
- **Durability:** read from worn gear (average and lowest piece).
- **Deleted characters:** right-click removes them.
- **Opened from:** its own dashboard card and the Instance Tracker window,
  not the minimap button's right-click, which stays Settings.

A **Your Characters** window listing every character, grouped by realm.

- **Opening it:** from the dashboard tools menu, right-clicking the minimap
  button, or a button in the instance log window.
- **Each character shows** level, XP and **rested XP**.
- **Hover a realm** for your total gold on it.
- **Hover a character** for its details:
  - level, XP and rested XP
  - gold, free bag slots and armor durability
  - profession skills
  - counts of important reagents: buff reagents, Soul Shards and the like
  - for hunters, ammo count and pet details
- **Updates on** logout, and when the values change while you play.

**Builds on:** Mail & Trade Logger already keeps a per-character list and a
character selector; this should share that one character registry instead
of starting another.

**To settle:**
- [ ] **Which reagents:** per class, the reagents that matter (Symbol of
      Kings, Sacred Candle, Arcane Powder, Soul Shards, Ankh, ...).
- [ ] **Durability:** read it from equipped items' durability at logout.
- [ ] **Deleted characters:** a way to remove characters you've deleted.

---

## 12. PvP instance log: battleground and arena stats — DONE in 3.27

Built as `Modules/PvPLog.lua`, with its own dashboard card. The 2.5.6
scoreboard APIs (`GetBattlefieldScore`, `GetBattlefieldWinner`,
`GetBattlefieldTeamInfo`, `GetBattlefieldArenaFaction`) were checked against
Blizzard's TBC scoreboard code.

Logs every battleground and arena you enter, like item 9's log but for PvP.

- **Battlegrounds:** the battleground, its length, the result, and your
  scoreboard line (killing blows, honorable kills, deaths, honor).
- **Arenas:** bracket, team, opponents, result and rating change.
- **Totals:** totals per battleground and per bracket, and a win rate.

**Builds on:** PvP Enemy Tracker already ignores battleground and arena
deaths. This would be its counterpart, in the same module or one beside
it.

**To settle:**
- [ ] **Scoreboard APIs on 2.5.6:** which scoreboard APIs exist
      (`GetBattlefieldScore`, `GetBattlefieldWinner`, the arena team calls).
- [ ] **Where it lives:** inside PvP Tracker, or its own dashboard card?

---

## 13. World buff timers, Songflowers and Darkmoon Faire — DONE in 3.28

Built as `Modules/WorldTimers.lua`, covering the TBC-relevant set:
- layers
- Terokkar towers
- dailies
- Darkmoon Faire with the Sayge cooldown
- Classic world buffs
- Songflowers

It listens to Nova World Buffs users. Decided:
- **Listen only.**
- **No guild posts from the addon.** Nova on TBC makes none except the
  Terokkar warning. `/wmachine wb guild` sends only when you ask.

**Added in 3.33:**
- map pins (Faire, Terokkar towers, Shattrath dailies, Songflowers)
- the guild layer list (from Nova users' guild messages)
- NPC-walking detection (Horde), and guild members' Nova walking notices

**Not built:**
- Whipper Root Tuber / Night Dragon's Breath (local-only on TBC in Nova)

Timers for the Classic world buffs, so nobody misses a drop.

**Buff timers:**
- **The buffs:** Rallying Cry of the Dragonslayer (Onyxia / Nefarian),
  Warchief's Blessing (Rend), Spirit of Zandalar (ZG heart). The timers run
  from the NPC's yell when the buff drops.
- **Warnings:** at 30, 15, 10, 5 and 1 minutes before a buff can drop again.
  They go to the chat window, the middle of the screen and guild chat, and
  each channel and each warning time can be switched on or off.
- **Guild warnings:** only **one** user online sends guild warnings at a
  time, so the guild isn't spammed.
- **NPC killed:** if a buff NPC is killed in front of a member with the addon
  (the mind-control reset), guild chat is told and the timer reset.
- **Showing the timers:**
  - anyone types `!wb` in guild chat
  - `/wmachine wb` to yourself, `/wmachine wb party` (or any channel) to
    others
  - automatically on login
  - on the Orgrimmar / Stormwind world map

**Songflowers:**
- **On the map:** Songflowers appear on the Felwood world map and minimap,
  each with its timer.
- **Commands:** `/sf`-style commands to show the timers to yourself or a
  channel, and to open the Felwood map.
- **Shift-click** a flower's icon to send its timer, location and coordinates
  to guild chat.
- **Seeing a flower picked** tells your guild when it respawns (optional).
- **Shared timers:** a line when you receive a new Songflower timer from
  someone (optional).
- **Also tracked:** Whipper Root Tubers and Night Dragon's Breath.

**Your buffs across alts:** a window showing which world buffs each character
has, opened from a command, the chat prefix, or a map icon.

**Darkmoon Faire:**
- **When and where:** when it arrives and leaves, and where it will be next,
  with a map marker.
- **Your buff cooldown:** how long until you can get the Faire's buff again.

**Layered realms:** timers kept for each layer at once, and which layer you
are on in every zone.

**For guild masters:** let a guild turn off messages from a public-note tag.
NWB uses `#nwb1`–`#nwb8`: off for everything, timers, buff dropped, the
`!wb` command, Songflowers, timers from outside the guild, NPC killed, and
NPC walking. We'd use our own tag (e.g. `#wm1`–`#wm8`), and perhaps honour
NWB's too.

**First run:** after installing, point people at the settings, since the
default warnings can be a lot.

**Localization:** timers come from each NPC's yell, so every client language
needs each NPC's two yell texts.

**To settle:**
- [ ] **Worth it on TBC:** check how these Classic world buffs behave on
      Anniversary realms. Are they removed or suppressed in Outland content?
      If so, the timers matter mostly for levelling, Classic raids and
      Songflower / DMF use. Decide the scope from that, maybe Darkmoon Faire
      and Songflowers first.
- [ ] **Layers:** detecting layers on Anniversary realms (NWB reads the zone
      ID from NPC GUIDs). Check that it still works.
- [ ] **Sharing timers:** guild-only, or also between guilds (NWB shares
      outside the guild unless `#nwb6`)? Who is trusted to send?
- [ ] **NWB compatibility:** should timers from NWB users be read?
- [ ] **Map pins:** map and minimap pins need a world-map and minimap pin
      layer, the first map UI in the addon.
- [ ] **Where it lives:** a module of its own, with its own dashboard card.


## 14. Loot Browser (AtlasLoot-style) — phase 1 DONE in 3.34

Our own loot browser, with AtlasLoot as the inspiration. The code is all
Watching Machine's own. The data keeps only the facts (which item IDs drop
from which boss), in our own format.

- [x] **Dungeons and raids** (3.34): Classic + TBC, normal / heroic, faction
      items, trash / keys / tier sets, opens on your instance.
- [ ] **Wrath tables:** `Data/LootWrath.lua` is in place and gated on the
      client's expansion. It needs the Wrath dungeon and raid lists (the
      AtlasLoot zip we had has no Wrath dungeon or raid tables).
- [x] **Item source tooltips** (3.35): "Drops from: Attumen the Huntsman
      (Karazhan)", Heroic-only marked, capped at three bosses.
- [x] **Crafting, reputation rewards, PvP gear** (3.36), Classic + TBC, and
      Wrath's on a Wrath client. Set pages: one line per set, by class.
- [ ] **Favourites and your own BiS marks** per spec. Not AtlasLoot's
      curated BiS lists.
- [ ] **Search** by item name (cached names only, or ask the client in
      batches).
