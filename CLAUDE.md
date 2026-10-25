# Watching Machine: notes for working on this addon

A WoW TBC Classic Anniversary addon (client 2.5.6, Interface 20506, Lua 5.1).
Tests: `tests/run.sh` (a stub client in `tests/wowstub.lua`); syntax:
`luac5.1 -p <file>` (then `rm -f luac.out`).

## Never assign a game global

Writing any of the game's globals from addon code (even
`X = X or {}`, a leaked `_`, or replacing an API function) "taints" it and
can get protected actions blocked: 3.48.3 fixed Log Out in the Escape menu
being blocked by `StaticPopupDialogs = StaticPopupDialogs or {}`. Add keys
to game tables (`StaticPopupDialogs["WM_..."] = ...`), use `hooksecurefunc`
instead of replacing functions, and keep everything else `local`.
`tests/test_globals.lua` fails on any other global write.

## Calls the game restricts in combat

`CheckInteractDistance` is blocked in combat on 2.5.x, and the game blames
the addon even inside a `pcall`. Ask through `WM:InteractRange(unit, i)`
(Core), which returns nil in combat without calling it;
`tests/test_protected.lua` fails on any other direct call. Inspecting
(`NotifyInspect`) waits for combat to end too.

## Every new module or feature goes into the setup and the panels

Every module can be switched on and off per character, and has its own
page in the guided setup that teaches it. Don't let a new module or
feature skip that.

### A new module
- [ ] `WM:RegisterModule("Name", M)` in its file; add the file to
      `WatchingMachine.toc` (and any saved variable to `## SavedVariables`).
- [ ] `Core.lua`:
  - `WM_ERROR_PATTERNS`: the module name.
  - `MODULE_COLORS`: its colour.
  - `MODULE_GROUPS`: its dashboard group.
  - `MODULE_INFO`: title, desc, about, command, color, icon, tools.
  - The slash command branch, using `WM:UsableModule("Name")` (so an off
    module says how to turn it on).
  - Its line in `WM:ShowHelp()`.
- [ ] `Profiles.lua`:
  - Its saved variable in `P.SCOPE`, listing in `shared` any key that holds
    data about all characters (logs, lists, per-character records, id
    counters). Everything else is per character.
  - `WM.MODULE_PARENT` if it's part of another module; `WM.MODULE_LINKS` if
    it adds to another module when both are on.
- [ ] Off must mean off: every event handler, OnUpdate, timer, hook,
      tooltip line, chat filter and message send returns early when
      `not WM:IsModuleOn("Name")` (also handlers registered at file load).
      `M:OnModuleOff()` hides its windows and frames and cancels work;
      `M:OnModuleOn()` re-shows anything that should be visible. Check
      `WM:IsModuleOn("Other")` before calling into another module.
      Exception: a module whose job is a record of every character (like
      Your Characters) sets `M.recordsEveryCharacter = true` and gates its
      recording on `WM:ShouldRun("Name")`, so it keeps saving alts where its
      switch is off while it's on for any character; its window still
      follows this character's switch.
- [ ] `M:SetupPage(L)`: the guided setup page. Explain what it does and how
      each main feature works, then its main settings with tooltips. It must
      work before the module has started (call only a defaults-only
      `InitDB`/`DB`). Reference: `Modules/Ogrila.lua`.
- [ ] `Setup.lua` `PRESETS`: add it to the quick setup presets it belongs in.
- [ ] Tests: its own test, plus on/off and setup-page checks (see
      `tests/test_onoff_*.lua`); update the card counts in
      `tests/test_dashboard.lua` and `tests/test_panels_core.lua`.

### A new feature or setting in an existing module
- [ ] Add it to the module's window (`CreateUI`) **and** to its
      `SetupPage`, with a tooltip explaining it.
- [ ] Gate anything new it runs (events, timers, hooks) on
      `WM:IsModuleOn`, and stop it in `OnModuleOff`.
- [ ] New saved data about all characters: add the key to the module's
      `shared` list in `P.SCOPE`.
- [ ] For a Class Tools feature: register it with
      `ClassTools:RegisterFeature` in the part's `RegisterFeatures()` (so the
      setup lists it before the module starts).

## Tools

`tools/` (not loaded by the game) holds the generators for `Data/` (loot from
AtlasLoot, attunements from Attune, hazards from GTFO) and the script that
rebuilds `docs/CURSEFORGE-DESCRIPTION.md` from the README. See
`tools/README.md`.

## Releasing
- Bump `## Version:` in `WatchingMachine.toc`, `WM.version` in `Core.lua`
  and the README header; add a README "### Version" entry, a CHANGELOG
  section (and its "Current release" line), the README module section, and
  update `docs/TODO.md`. Rebuild the CurseForge description
  (`python3 -I tools/curseforge_description.py`).
- Commit to `main`, then push `main` and `main:claude/wow-buff-check-module-q11r9h`.
- Third-party addons used as a guide are rewritten in our own code; only
  facts (IDs, numbers) are kept, in our own format, with a "compiled with
  the help of X's research" credit.
