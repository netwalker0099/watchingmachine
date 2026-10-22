# To do

Planned work that hasn't been started. Each item notes what's decided and
what still needs settling before it's built.

1. ~~Mana potion / rune alert~~ (done, 3.14)
2. Audio trigger for alerts
3. ~~Melee swing timer~~ (done, 3.17)
4. ~~Warlock button: armors and demon summons~~ (done, 3.15)
5. ~~Shaman totem bar with quick sets~~ (done, 3.16)
6. ~~Flyout buttons: open on hover or on click~~ (done, 3.15)
7. ~~Flyout directions: add "Hidden", and use dropdowns~~ (done, 3.15)
8. ~~Dock flyout buttons together~~ (done, 3.15)

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

