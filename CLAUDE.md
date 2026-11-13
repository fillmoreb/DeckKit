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
- Lua errors: `deckctl errors` (DeckDev catches them as they happen). The game also writes them to
  `_forever_/Logs/General.log` (grep for `Lua Error`), late. Check its
  timestamp: a wedged client can stop writing it while still running, and then APIs misbehave too
  (`C_DeathInfo.GetCorpseMapPosition` returned nil until a restart).
- Forever's own UI source (FrameXML) is mirrored at github.com/Ketho/wow-ui-source-forever
  (`gh api repos/Ketho/wow-ui-source-forever/contents/<path> -H "Accept: application/vnd.github.raw"`,
  `gh search code ... --repo Ketho/wow-ui-source-forever`). Read it before guessing at Blizzard
  behavior.
- Don't hook or hide the chat edit box or anything in its path (HookScript on `ChatFrame1EditBox`,
  hooked Show/Hide on its gamepad legend): it taints the box, Enter stops running slash commands, and
  the game blames a random addon ("DeckHUD has been blocked..."). To hide something there, set its
  alpha only (see `DeckHUD/Chat.lua` NoLegend). With Gamepad UI on, Forever shows a button legend
  under the chat box whenever it has focus (`ChatFrameN.FloatingChatFrameinputLegend`, lowercase i).
- Old texture paths may be missing (e.g. `Interface\WorldMap\WorldMapCorpse`) and draw as nothing,
  with no error. Check with `tex:GetTextureFileID()` (nil = missing) or prefer atlases checked
  via `C_Texture.GetAtlasInfo`.

## Rules

- **Say "grip buttons" or "grips" for L4/R4/L5/R5, never "paddles"** (Valve's terms: "grip buttons", and
  "back grips" in Steam's controller settings). Combinations are "grip chords"; the menu section is
  Controls › Grips.
- **Peeks never take the sticks.** Full character control while a peek (ChatDeck, MapDeck, any
  hold-to-see view) is up matters more than features inside the peek. Ben decided this on
  2026-11-13: ChatDeck's right-stick scrollback and MapDeck's right-stick zoom to the continent were
  removed for it. `DeckKit.TakeSticks` takes *both* sticks (the client can't take one), so it's only
  for windows you navigate, like the menu. Reading the right stick by polling without taking it
  means the camera turns too: the camera speed CVars can't go below 0.1, so there's no way to hold
  it still. Don't bring either back without asking.
- **Never rename a SavedVariables table or a binding name.** Players' data and keybinds are stored
  under those names. This also holds while moving code into the DeckKit core.
- Use `/deckkit` (and `/dkit`) for suite commands. `/deck` is taken by other Forever addons.
- Each feature stays a separate addon on top of the **DeckKit core** (`addons/DeckKit`), which holds
  the shared controller input (`Input.lua`), the window look (`Window.lua`), and in `Core.lua` the
  `DeckKit` global, per-module event buses, `DeckKit.TakeSticks` and `/deckkit`; `Override.lua` is
  `DeckKit.Override`, which shares pad buttons between modules. A module lists
  `## Dependencies: DeckKit` and starts its first file with
  `DeckKit.NewModule(ns, ADDON, "<colored title>")`, which sets `ns.Print`, `ns.On`, `ns.Input`,
  `ns.Window`, `ns.Override`, `ns.AddCommand` and `ns.TITLE`. Shared behavior gets fixed once, in the core. Never copy core code into
  a module.
- Never bind a pad button directly from a module. Claim it with
  `ns.Override.Set(key, id, { when = "[macro conditions]", priority = n, macro = "..." })`; the core
  picks the winner per press, in secure code. X (PAD3) today: wand shoot (20, `[harm,nodead]`), fishing
  (10, `[nocombat,nochanneling]`).
- **The back grips are DeckKit's grip chords** (`DeckKit/Chords.lua`). Steam sends 8 plain keys
  and nothing else (`deck-setup/make-chord-layout.py` writes the layout; never hand-edit it): each
  grip's own key while held (L4 F8, R4 F9, L5 F10, R5 F11) and a second key 400 ms in, Steam's long
  press (F1 F2 F3 F4). Secure code turns those into 15 chords x press / hold = 30 slots, set in
  Controls > Grips (`DeckKit/CheatSheet.lua` shows the picked slots on screen; it follows slot changes
  through `ns.Chords.OnChange`). A chord's press fires on the first release (or on press if nothing bigger or
  held could follow); its hold fires when the last-pressed grip's long key arrives. Restricted code
  has no clock, so there's no double-tap. Don't bind the 8 keys from a module: offer the action with
  `ns.Chords.Offer(BINDING_NAME, { label, run = fn(down) })` (insecure, fine in combat for DeckKit's
  own windows and peeks), `ns.Chords.OfferPress(id, fn, label)`, or `{ mirror = "SecureButtonName" }`
  for a secure action (the grip button copies that button's attributes as it fires; QuestPad does
  this). Addons can't call `RunBinding`, so a binding with no offer can't go in a slot. Spells
  (`SPELL:<id>`) and action bar buttons work without offers. Module code that sets its own override
  on a key skips keys where `DeckKit.Chords.Owns(key)`. Glyphs: `ns.Chords.Glyph(chord, gesture)`,
  from `media/chords.tga` (`deck-setup/make-chord-glyphs.py`). Decktation (push-to-talk on
  L4+R4) needs "Exact binding only" (`exactBindingMs`, 150) so bigger chords containing L4+R4 don't
  start dictation: `patches/decktation/exact-binding.patch` until it's released upstream.
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
  Screen, Map & travel, Healing, Tools); actions a player triggers with a button are offered to
  the grip chord slots (`ns.Chords.Offer`, below), not given their own binding rows. Everything a player can change should be
  reachable there with the controller alone. Use `{A}`, `{MENU}`, `{LB}`, `{DPAD_LR}`... tokens for
  button icons.
- DeckKit windows are built from `DeckKit/UI.lua` (screen with tabs and footer prompts, panels,
  checkbox, switch, selector, stepper, action, key binding, icon grid, scrolling list; the game's
  own pointer as the cursor). `DeckKit/Sample.lua` (`/deckkit sample`) shows every element; keep it
  in step when adding one. `/deckkit sample <PADKEY ...>` replays presses for testing.
- Edit Mode positions and settings: change them through `DeckHUD/Layout.lua` (`C_EditMode`,
  backup first, then a /reload), never by fighting Edit Mode at runtime.
- `DeckHUD/masks/*.tga` are generated by `deck-setup/make-minimap-masks.py`; `DeckKit/media/chords.tga` by
  `deck-setup/make-chord-glyphs.py`. `python3 deck-setup/test_make_chord_layout.py` tests the layout generator.

## Checking and deploying

The dev tooling lives in **~/Projects/AddonTools** (read its README): the **DeckDev** dev addon
(log on a screen strip, Lua error and blocked-call capture, `DeckDev.Dump` / `DeckDev.Inspect`) and
**`deck/deckctl`**, which drives the game from the Mac. Changes to the tooling go there, with tests.

- `./deploy.sh <Addon...>` (no arguments for all) runs `deckctl deploy`: Lua 5.1 syntax check,
  apicheck, whole-folder swap on the Deck, reload, verify. A good deploy ends **"addons loaded N/N,
  0 Lua errors, 0 blocked"**; anything else exits 1 and is a failure to look at (`deckctl errors`,
  `deckctl blocked`). DeckDev itself is deployed from AddonTools (`./deploy.sh` there).
- `~/Projects/AddonTools/tools/apicheck.py addons/*`: globals Forever doesn't have. Keep it at 0
  findings; optional or load-on-demand globals go in the addon's `apicheck.globals`.
- In the game, with `deck/deckctl` (in AddonTools):
  - `deckctl run 'return ...'` runs Lua and prints the results (tables through `DeckDev.Dump`);
    `deckctl run --slash "/mapdeck"` runs a slash command. Nothing is typed into chat.
  - `deckctl state`: the control record (session, last deploy, addons loaded, error and blocked
    counts). `deckctl read`: the log. `deckctl errors` / `deckctl blocked`: this session's Lua
    errors with stacks / blocked calls. `deckctl inspect NAME`: a frame's layout and state.
  - `deckctl shot FILE.png`: a screenshot, when you need to see the screen.
  - Log from addon code with `ns.Debug(...)` (lines prefixed with the module name, sent to DeckDev
    when it's installed); turn the log on with `DeckDev.SetOn(true)` or `/deckdev on`.
  - Raw xdotool only for a real key press into secure code. Never movement keys.
- **Don't roll your own game-driving or debugging tools in DeckKit.** If deckctl / DeckDev can't do
  what you need, read `~/Projects/AddonTools/ROADMAP.md` first: it's probably a planned item
  (scenario runner, input testing, event trace, log follow, sv/taint/crop helpers). Then stop and
  tell Ben what you were trying to do and which item it matches, instead of improvising: no xdotool
  loops, no one-off scripts in `deck-setup/`, no prints typed into chat. Tooling changes get built
  in ~/Projects/AddonTools with tests, not here. The one exception is the real key press for secure
  code above.
- DeckKit must work without DeckDev: it's an optional dependency (`## OptionalDeps: DeckDev`).
- There is no automated test harness for DeckKit itself yet. Behavior has to be verified in the
  game; say plainly when a change hasn't been tested in-game yet.

## Layout

- `addons/<Name>/`: one folder per addon (`.toc`, Lua, optional `Bindings.xml`).
- `deck-setup/`: Battle.net launcher script and Steam shortcut tooling for the Deck.
- `patches/`: local patches to other people's addons and Decky plugins. Re-apply them after those
  projects update.
