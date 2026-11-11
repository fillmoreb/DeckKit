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
- Lua errors are written to `_forever_/Logs/General.log` (grep for `Lua Error`). Check its
  timestamp: a wedged client can stop writing it while still running, and then APIs misbehave too
  (`C_DeathInfo.GetCorpseMapPosition` returned nil until a restart).
- Forever's own UI source (FrameXML) is mirrored at github.com/Ketho/wow-ui-source-forever
  (`gh api repos/Ketho/wow-ui-source-forever/contents/<path> -H "Accept: application/vnd.github.raw"`,
  `gh search code ... --repo Ketho/wow-ui-source-forever`). Read it before guessing at Blizzard
  behaviour.
- Don't hook or hide the chat edit box or anything in its path (HookScript on `ChatFrame1EditBox`,
  hooked Show/Hide on its gamepad legend): it taints the box, Enter stops running slash commands, and
  the game blames a random addon ("DeckHUD has been blocked..."). To hide something there, set its
  alpha only (see `DeckHUD/Chat.lua` NoLegend). With Gamepad UI on, Forever shows a button legend
  under the chat box whenever it has focus (`ChatFrameN.FloatingChatFrameinputLegend`, lowercase i).
- Old texture paths may be missing (e.g. `Interface\WorldMap\WorldMapCorpse`) and draw as nothing,
  with no error. Check with `tex:GetTextureFileID()` (nil = missing) or prefer atlases checked
  via `C_Texture.GetAtlasInfo`.

## Rules

- **Never rename a SavedVariables table or a binding name.** Players' data and keybinds are stored
  under those names. This also holds while moving code into the DeckKit core.
- Use `/deckkit` (and `/dkit`) for suite commands. `/deck` is taken by other Forever addons.
- Each feature stays a separate addon on top of the **DeckKit core** (`addons/DeckKit`), which holds
  the shared controller input (`Input.lua`), the window look (`Window.lua`), and in `Core.lua` the
  `DeckKit` global, per-module event buses, `DeckKit.TakeSticks` and `/deckkit`; `Override.lua` is
  `DeckKit.Override`, which shares pad buttons between modules. A module lists
  `## Dependencies: DeckKit` and starts its first file with
  `DeckKit.NewModule(ns, ADDON, "<colored title>")`, which sets `ns.Print`, `ns.On`, `ns.Input`,
  `ns.Window`, `ns.Override`, `ns.AddCommand` and `ns.TITLE`. Shared behaviour gets fixed once, in the core. Never copy core code into
  a module.
- Never bind a pad button directly from a module. Claim it with
  `ns.Override.Set(key, id, { when = "[macro conditions]", priority = n, macro = "..." })`; the core
  picks the winner per press, in secure code. X (PAD3) today: wand shoot (20, `[harm,nodead]`), fishing
  (10, `[nocombat,nochanneling]`).
- Module bindings go in the DeckKit section of Key Bindings: `category="BINDING_HEADER_DECKKIT"` in
  `Bindings.xml`, with the module's own `header`.
- Gamepad input: secure actions (casting, using items) need SecureActionButtons and override
  bindings. You can't trigger them from insecure Lua. See `DisenchantDeck/List.lua` for the pattern.
- Restricted snippets (`WrapScript`, `SecureHandler*`): an error inside one drops the click with
  nothing on screen. It is logged ("Call failed: [string ...]:<line>"), but `General.log` reaches the
  disk late (often only at a reload or exit), so an empty log right after a test proves nothing.
  Frame handles have `GetRect`, not `GetCenter`. A key
  bound to a button clicks it twice (down, then up). Clicks from insecure Lua (`button:Click()`)
  skip the wraps, so test with a real key press (an override binding plus xdotool) and bisect with
  `owner:SetAttribute("dbg", ...)` markers read back from insecure code. `HealPad` is the example.
- Stay agnostic of other addons: no code paths that know about a specific third-party addon
  (RestedXP, Questie, TomTom...). Use Blizzard APIs, generic mechanisms (e.g. hiding whatever sits
  along a screen edge) and common conventions (`GetMinimapShape`, LibDBIcon button names).
- Credit borrowed code, in the file header and in `LICENSE`. `DeckKit/Input.lua` is adapted from
  BagPad's MIT-licensed `Input/Controller.lua`; `DeckKit/Override.lua` and
  `DeckSundries/WandShoot.lua` from Improved Forever's (MIT) `Override.lua` and `WandShoot.lua`.
- Module commands go under `/deckkit <name>` (`ns.AddCommand`), not new slash commands.
- Module settings go in the DeckKit menu (`ns.AddSettings`, see `DeckKit/Settings.lua`): toggles,
  choices, ranges, actions, key bindings, status and info rows. The menu is grouped by topic, not by
  addon: start each call with a `{ type = "section", tab = ..., label = ... }` row (tabs: Controls,
  Screen, Map & travel, Healing, Tools); key bindings go in Controls > Bindings as
  `{ type = "binding", action = "MYADDON_THING" }`. Everything a player can change should be
  reachable there with the controller alone. Use `{A}`, `{MENU}`, `{LB}`, `{DPAD_LR}`... tokens for
  button icons.
- DeckKit windows are built from `DeckKit/UI.lua` (screen with tabs and footer prompts, panels,
  checkbox, switch, selector, stepper, action, key binding, icon grid, scrolling list; the game's
  own pointer as the cursor). `DeckKit/Sample.lua` (`/deckkit sample`) shows every element; keep it
  in step when adding one. `/deckkit sample <PADKEY ...>` replays presses for testing.
- Edit Mode positions and settings: change them through `DeckHUD/Layout.lua` (`C_EditMode`,
  backup first, then a /reload), never by fighting Edit Mode at runtime.
- `DeckHUD/masks/*.tga` are generated by `deck-setup/make-minimap-masks.py`.

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
