# CLAUDE.md

Notes for Claude (or any AI coding assistant) working in this repo. Most of DeckKit is written with
Claude, so this file is part of how the project gets made. Keep it current when you learn something
non-obvious.

## What this is

Controller-first addons for **WoW: Forever** played on a Steam Deck, plus the Deck-side launch setup.
Every feature has to work with a gamepad alone. A mouse or keyboard is never assumed.

## Target game

- WoW: Forever, game version 1.60.x, **`## Interface: 16001`** in every `.toc`. For multi-flavor
  addons Forever also loads `_Camelot.toc` (Camelot is Forever's internal codename).
- The client runs **Lua 5.1**. Don't use 5.2+ features (`goto`, integer division `//`, bitwise
  operators, `table.unpack`, `utf8`).
- APIs differ from retail and Classic. Known gaps: there is no global `GetItemInfo`, so use
  `C_Item.GetItemInfo`. Check an API exists before relying on it, and guard with `C_X and C_X.Fn or Fn`
  if unsure.
- Replaying the same sound kit within about 0.3 s is dropped silently, even with
  `PlaySound(kit, channel, false)`.
- Lua errors are written to `_forever_/Logs/General.log` (grep for `Lua Error`).

## Rules

- **Never rename a SavedVariables table or a binding name.** Players' data and keybinds are stored
  under those names. This also holds while moving code into the DeckKit core.
- Use `/deckkit` (and `/dkit`) for suite commands. `/deck` is taken by other Forever addons.
- Each addon stays a separate addon. The planned **DeckKit core** addon will hold the shared
  controller input, windows, printing/events and settings, and the feature addons will depend on it.
  Until then `WayPad/Input.lua` and `DisenchantDeck/Input.lua` (and `Window.lua`) are copies that have
  drifted apart. WayPad's copy is the newer one (it has the "draining" fix: the press that closes a
  window stays consumed until released). Fix input bugs in both copies, or better, in the core.
- Gamepad input: secure actions (casting, using items) need SecureActionButtons and override
  bindings. You can't trigger them from insecure Lua. See `DisenchantDeck/List.lua` for the pattern.
- Credit borrowed code. `WayPad/Input.lua` is adapted from BagPad's MIT-licensed
  `Input/Controller.lua`.

## Checking and deploying

- Syntax check: `luac -p file.lua`. The Mac's `luac` is newer than 5.1, so this catches syntax errors
  only, not 5.2+ features.
- `./deploy.sh <Addon...>` (no arguments for all) syntax-checks and copies addons onto the
  maintainer's Deck over SSH. It's specific to that machine. Then `/reload` in game.
- There is no automated test harness. Behaviour has to be verified in the game; say plainly when a
  change hasn't been tested in-game yet.

## Layout

- `addons/<Name>/`: one folder per addon (`.toc`, Lua, optional `Bindings.xml`).
- `deck-setup/`: Battle.net launcher script and Steam shortcut tooling for the Deck.
- `patches/`: local patches to other people's addons and Decky plugins. Re-apply them after those
  projects update.
