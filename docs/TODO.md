# To do

Planned work that hasn't been started. Each item notes what's decided and
what still needs settling before it's built.

1. Mana potion / rune alert
2. Audio trigger for alerts
3. Melee swing timer
4. Warlock button: armors and demon summons

---

## 1. Mana potion / rune alert

Prompt the player to drink a mana potion, or use a rune when the potion is
on cooldown, as their mana drops.

**Rules (as requested):**

| Condition | Alert |
|---|---|
| Mana is **3000 or more below max**, and a mana potion is ready | "Use a mana potion" |
| Potion is **on cooldown**, mana is **1500 or more below max**, and a rune is ready | "Use a Dark / Demonic Rune" |

**How it fits the existing code:**
- **Where:** a Class Tools feature, using the shared *CHECK YOURSELF* frame
  (`ClassTools:SetAlert` / `ClearAlert`) and the shared one-second monitor
  (`RegisterMonitor`), like the other class checks. It probably belongs in
  the **General** tab, gated to mana users (`UnitPowerType("player") == 0`),
  rather than being mage-only.
- **Mana:** `UnitPower("player", 0)` / `UnitPowerMax("player", 0)`, plus
  `UNIT_POWER_UPDATE` (or the 2.5.6 equivalent; check the event exists, since
  `WM:RegisterEvents` skips missing ones) if the 1s tick feels too slow.
- **Ready means in bags and off cooldown:** `GetItemCount(itemID) > 0` and
  `GetItemCooldown(itemID)` start == 0, checked per item ID.
- **Item IDs to confirm in game:**
  - Super Mana Potion `22832`
  - Major Mana Potion `13444`
  - Dark Rune `20520`
  - Demonic Rune `12662`

  Possibly also: Fel Mana Potion, Mad Alchemist's Potion, Auchenai / Bottled
  Nethergon (battleground and zone potions), and the Cenarion Mana Salve
  pots.

**To settle before building:**
- [ ] **Cooldowns:** confirm in game that runes have their own cooldown,
      separate from potions. The rule above assumes it, which is the usual
      TBC "potion, then rune" pattern.
- [ ] **When it runs:** in combat only, raid instances only (like the other
      General checks, with the 25-man toggle), or anywhere?
- [ ] **Thresholds:** fixed at 3000 / 1500, or sliders? A percentage option
      might suit low-mana characters better.
- [ ] **Flicker:** add hysteresis so the alert doesn't flick on and off
      around the threshold as mana regenerates. For example, clear only once
      the deficit is 500 back under the line, or hold the alert for a few
      seconds.
- [ ] **Rune side effects:** runes cost health, so maybe suppress the rune
      alert below some health %.
- [ ] **Tests:** fake `UnitPower` / `GetItemCount` / `GetItemCooldown` in
      the wowstub. Cover:
      - potion ready
      - potion on cooldown with a rune ready
      - neither available
      - not a mana user
      - out of combat or outside a raid, depending on the rule settled above

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

## 3. Melee swing timer

A movable bar showing time to your next melee swing, main hand and
off hand.

**Reference:** look at how Leatrix Plus does it before building. Either
you provide its code, or we read the released addon. Two cautions: check
that Leatrix Plus actually has a swing timer, and check its licence before
reusing any code. Reading it for the approach is fine; copying code needs a
licence that allows it.

**Likely approach (to check against the reference):**
- **Swing speed:** `UnitAttackSpeed("player")` gives the main- and off-hand
  swing times. They change with haste, so re-read on `UNIT_ATTACK_SPEED`.
- **Swing detection:** watch your own `SWING_DAMAGE` / `SWING_MISSED` in
  `COMBAT_LOG_EVENT_UNFILTERED`. The off-hand flag tells the hands apart.
- **"Next melee" abilities:** Heroic Strike, Cleave, Maul and Raptor Strike
  replace the white swing and arrive as `SPELL_DAMAGE` / `SPELL_MISSED`, so
  they must reset the timer too. Slam resets the swing in TBC.
- **Parry haste:** when *you* parry an incoming attack (a `PARRY` miss with
  you as the target), your own next swing comes sooner. The remaining time is
  cut by 40% of your swing speed, but never to less than 20% of it. Tanks
  will notice if this is missed. Confirm the exact rule against the
  reference.
- **Other resets:** weapon swaps and reaching the target after moving.
- **Display:** a bar per hand, built with the panel builder's styling. It
  should be lockable and movable, with the position saved. Show it only in
  combat or while auto-attack is on.
- **Possible extra:** a hunter Auto Shot timer (`START_AUTOREPEAT_SPELL` /
  `STOP_AUTOREPEAT_SPELL`). It works differently from melee, so treat it as
  optional.

**To settle:**
- [ ] **Where it lives:** a General tab feature in Class Tools, or a module of
      its own? It applies to many classes.
- [ ] **Which classes:** all melee classes, or a per-class toggle?
- [ ] **Off hand:** show the off-hand bar, or main hand only?
- [ ] **Tests:** a fake combat log covering swing resets, next-melee
      abilities and haste changes.

---

## 4. Warlock button: armors and demon summons

A warlock flyout button that works like the mage buttons.

- **Groups:**
  - **Armors:** Fel Armor, Demon Armor, Demon Skin. One icon each; ranked
    spells cast your highest rank, as with the mage armors.
  - **Demons (pet multi-selector):** Summon Imp, Voidwalker, Succubus,
    Felhunter, and Felguard if talented. Only the ones the warlock knows.
- **Directions:** each group has its own expansion direction in Class
  Tools → Warlock. Groups on the same button that share a direction form one
  line, the same rule as portals and teleports.
- **Icon:** the warlock class crest, cut from the same class-circles sheet as
  the mage utility button.

**Groundwork:** the flyout (`NewFlyout`) currently lives inside
`Modules/ClassMage.lua`. It should move to a shared file, for example
`Modules/ClassFlyout.lua` loaded before the class modules, so Warlock (and
later classes) can use it without duplicating it. Spell matching should
follow the mage approach: English name plus the client's own name for a
known spell ID.

**To settle:**
- [ ] **Order:** which group sits nearest the button, and the demon order. By
      level would be Imp, Voidwalker, Succubus, Felhunter, Felguard; or the
      most-used demon first.
- [ ] **Other spells:** include Fel Domination (instant summon) beside the
      demons, and Create Healthstone / Soulstone / Spellstone / Firestone as
      another group?
- [ ] **Soul Shards:** show the shard count on the button, since most summons
      need one?
- [ ] **Spell IDs:** confirm the IDs for each spell in game.
