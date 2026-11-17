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
- `SetRotation` on an atlas piece turns its coordinates on the whole texture sheet (neighbouring art shows
  through, and it undoes `SetTexCoord`): turn atlas art with 8-argument `SetTexCoord` on `info.file`
  (`DeckHUD/Compass.lua`). Moving 1 px textures flicker from pixel snapping: `SetSnapToPixelGrid(false)`.
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
  the shared controller input (`Input.lua`: one window owns the pad at a time), the window look and the
  suite's colors (`Window.lua`, `DeckKit.COLORS` lilac/plum), the UI kit (`UI.lua`, including
  `UI.MakePointer`/`UI.PlacePointer` for the game's chevron), windows described as data (`Layout.lua`:
  `UI.Build`, `UI.ShowLayout`, the hold-Y map peek and `UI.DrawMapArt`, which MapDeck draws with too), live
  game conditions (`Conditions.lua`, `DeckKit.Conditions`: quest taken, items carried...), map maths (`Map.lua`, `DeckKit.Map`:
  positions, world positions, bearings, facing), the waypoints (`Waypoints.lua`, `DeckKit.Waypoints`:
  list, guidance, arrival; WayPad is only their controller front end, DeckHUD's compass shows them), their
  routes (`Route.lua`, `DeckKit.Route`: with ForeverNav installed, a far waypoint is guided leg by leg,
  the guidance carries the step, and `Route.Summary(p)` gives other addons the trip; DeckAgent's
  `set_waypoint` returns it; with ForeverNav installed, `Route.Walk()` is the path on foot to where the guidance
  points, which MapDeck draws on the peek map), and
  in `Core.lua` the `DeckKit` global, per-module event buses, `DeckKit.Readable` (secret-value check),
  `DeckKit.TakeSticks` and `/deckkit`; `Override.lua` is `DeckKit.Override`, which shares pad buttons
  between modules, and `DeckKit.CrossbarButtons()`. A module lists
  `## Dependencies: DeckKit` and starts its first file with
  `DeckKit.NewModule(ns, ADDON, "<colored title>")`, which sets `ns.Print`, `ns.On`, `ns.Input`,
  `ns.Window`, `ns.Override`, `ns.AddCommand` and `ns.TITLE`. A module with several files gives each
  file one job and lists them in its first file's header (DeckHUD/Core.lua, MarketDeck/Core.lua).
  Shared behavior gets fixed once, in the core. Never copy core code into
  a module.
- Never bind a pad button directly from a module. Claim it with
  `ns.Override.Set(key, id, { when = "[macro conditions]", priority = n, macro = "..." })`; the core
  picks the winner per press, in secure code. X (PAD3) today: wand shoot (20, `[harm,nodead]`), fishing
  (10, `[nocombat,nochanneling]`). Y (PAD4): no target menu (10, `[combat]`, an empty macro). With
  LT/RT held, a claimed key clicks that layer's crossbar button (`CROSSBAR` in `Override.lua`).
  To stop one of Blizzard's crossbar actions, claim its key like this rather than hooking or closing
  what it opens: closing a menu from addon code taints the gamepad bar.
  The one other way: a secure window that opens in combat binds its keys from its own secure header while it's
  shown (restricted `SetBindingClick`, cleared as it closes), because "this window is open" isn't a macro
  condition `Override` can follow. PadTouchGrid does this for F11 and B (`PadTouchGrid/Grids.lua`).
- **The back grips are DeckKit's grip chords** (`DeckKit/Chords.lua`). Steam sends 8 plain keys
  and nothing else (`deck-setup/make-chord-layout.py` writes the layout; never hand-edit it): each
  grip's own key while held (L4 F1, R4 F2, L5 F3, R5 F4) and a second key 400 ms in, Steam's long
  press (F5 F6 F7 F8). They live in `ns.GRIPS` (`DeckKit/Core.lua`) and nowhere else in the addons;
  README "Keys" has every key the setup uses. Secure code turns those into 15 chords x press / hold = 30 slots, set in
  Controls > Grips (`DeckKit/CheatSheet.lua` shows the picked slots on screen; it follows slot changes
  through `ns.Chords.OnChange`). A chord's press fires on the first release (or on press if nothing bigger or
  held could follow); its hold fires when the last-pressed grip's long key arrives. Restricted code
  has no clock, so there's no double-tap. Don't bind the 8 keys from a module: offer the action with
  `ns.Chords.Offer(BINDING_NAME, { label, run = fn(down) })` (insecure, fine in combat for DeckKit's
  own windows and peeks), `ns.Chords.OfferPress(id, fn, label)`, or `{ mirror = "SecureButtonName" }`
  for a secure action (the grip button copies that button's attributes as it fires; QuestPad does
  this). Addons can't call `RunBinding`, so a binding with no offer can't go in a slot. Spells
  (`SPELL:<id>`) and action bar buttons work without offers. Module code that sets its own override
  on a key skips keys where `DeckKit.Chords.Owns(key)`. Glyphs: `ns.Chords.Glyph(chord, gesture)`:
  Ben's 24 px pixel art (`media/chords-24.tga`, 1:1 at 24 on the Deck, where a UI unit is a pixel), built by
  `deck-setup/make-chord-glyphs.py` from his drawings in `deck-setup/glyphs/` (each grip flood-filled, the
  outline recolored): redraw those or change the script's colors, never hand-edit the texture. Decktation (push-to-talk on
  L4+R4) needs "Exact binding only" (`exactBindingMs`, 150) so bigger chords containing L4+R4 don't
  start dictation: built into Decktation 0.3.24+. Decktation's status hook (its real state for the
  dictation indicator) lives in DeckKitAfterDark (it feeds the game from outside); DeckKit only
  offers `DeckKit.Dictation.SetState(state, binding)` and `DeckKit.Dictation.Claim()` (a real-state
  source calls it as it loads, so the grips never show "Listening"; only the tool's own state does; the
  chord then shows "Starting" until it arrives, and `DECKKIT_ASSISTANT` does the same for a voice
  assistant's chord), and must not depend on AfterDark.
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
  (RestedXP, Questie...). Use Blizzard APIs, generic mechanisms (e.g. hiding whatever sits
  along a screen edge) and common conventions (`GetMinimapShape`, LibDBIcon button names). Shared
  interfaces many addons speak count as conventions: WayPad's hand-off talks TomTom's waypoint API
  (`AddWaypoint` / `RemoveWaypoint` / `SetCrazyArrow`, which other waypoint addons provide too).
  Standing down for an addon that does the same job is fine too (PackPad's `CONFLICTS` bag addons):
  a list of names, never code that works with them.
  **Exception: Pawn** (Ben, 2026-11-15: "My addons can know about Pawn. Because I'm not willing to
  duplicate pawn."). Use its public bag-addon API, `PawnShouldItemLinkHaveUpgradeArrow(link, true)`
  (nil = ask again shortly), as an optional dependency (`## OptionalDeps: Pawn`); see `PackPad/Peek.lua`.
  **Exception: game-data libraries** (Ben, 2026-11-15). Addons whose job is supplying game data we'd
  otherwise have to rebuild, like Pawn's stat weights, can be used through their public API as optional
  dependencies. DeckKit is GPL-3.0-or-later (since 2026-11-15; MIT up to 1.2.0-beta1), so
  GPL code and data may come in too, credited in the file and in `LICENSE`; keeping a library a separate addon is
  still the default (ForeverNav, the guide addon) when other addons can use it. For travel routing:
  **ForeverNav** (`addons/ForeverNav`, our routing library on Shortest Path Forever's walking maps, timetables
  and planner; its tools, tests and notes are in `nav/`, see `nav/README.md`): `ForeverNav.v1.Plan(from, to, opts)` for the legs, `v1.Walk` for the path on foot.
  MapzerothLib (Ben's fork of Mapzeroth) and FarstriderLib were used before it and dropped. Settings name what a
  feature does, never the library behind it. Everything else stays agnostic.
- Credit borrowed code, in the file header and in `LICENSE`. `DeckKit/Input.lua` is adapted from
  BagPad's MIT-licensed `Input/Controller.lua`; `DeckKit/Override.lua` and
  `DeckSundries/WandShoot.lua` from Improved Forever's (MIT) `Override.lua` and `WandShoot.lua`.
- Module commands go under `/deckkit <name>` (`ns.AddCommand`), not new slash commands.
- Module settings go in the DeckKit menu (`ns.AddSettings`, see `DeckKit/Settings.lua`): toggles,
  choices, ranges, actions, status and info rows. The menu is grouped by topic, not by
  addon: start each call with a `{ type = "section", tab = ..., label = ... }` row (tabs: Controls,
  Screen, Map & travel, Healing, Tools); actions a player triggers with a button are offered to
  the grip chord slots (`ns.Chords.Offer`, below), not given their own binding rows. Everything a player can change should be
  reachable there with the controller alone. Use `{A}`, `{MENU}`, `{LB}`, `{DPAD_LR}`... tokens for
  button icons.
- DeckKit windows are built from `DeckKit/UI.lua` (screen with tabs and footer prompts, panels,
  checkbox, switch, selector, stepper, dial, action, key binding, icon grid, scrolling list; the game's
  own pointer as the cursor), or described as data with `UI.Build` (`DeckKit/Layout.lua`'s header lists the
  node types). `DeckKit/Sample.lua` (`/deckkit sample`) shows every element; keep it
  in step when adding one. `/deckkit sample <PADKEY ...>` replays presses for testing.
- Edit Mode positions and settings: change them through `DeckHUD/Layout.lua` (`C_EditMode`,
  backup first, then a /reload), never by fighting Edit Mode at runtime.
- `DeckHUD/masks/*.tga` are generated by `deck-setup/make-minimap-masks.py`; `DeckHUD/media/compass-pointer.tga` by
  `deck-setup/make-compass-pointer.py` (from Ben's drawing, `deck-setup/compass/pointer-source.png`); `DeckKit/media/chords-24.tga` by
  `deck-setup/make-chord-glyphs.py` (from `deck-setup/glyphs/`). `python3 deck-setup/test_make_chord_layout.py` tests the layout generator.

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
  - `deckctl chords`: the grip chord slots (list, `set CHORD press|hold ACTION [--char]`, `reset`,
    `actions`, `defaults`). Change slots with it rather than poking `DeckKitDB.chords`; `defaults` prints the
    shared slots as `FirstSlots`' `Add(...)` lines, for changing what a new install starts with.
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
- Offline scenarios: `tests/run.sh` runs `tests/test_*.lua` in AddonTools' harness (the core's real files
  against a stand-in client: geometry, pad presses, keys through override bindings, secure snippets and
  SecureActionButtons recorded in `H.actions`; see AddonTools' README). Add a scenario when changing a window's
  behaviour, the picker, chords or anything secure; run it before deploying. It can't show rendering, taint
  or Steam Input, so behaviour still gets verified in the game: say plainly when a change has only passed
  offline.

## Releasing

Releases go out through the BigWigs packager (`.github/workflows/release.yml`, `.pkgmeta`). Only
when Ben asks for a release; pushing a tag publishes to CurseForge.

1. Add the release's section to `CHANGELOG.md` (newest first; it's uploaded as the changelog).
2. Commit, then tag and push: `git tag 1.2.0-beta1 && git push origin 1.2.0-beta1`. A tag with
   "beta" in it goes up as a Beta, with "alpha" as an Alpha, anything else as a Release. **For now
   every release is a beta** (Ben, 2026-11-13: "We will work through betas"): tag `X.Y.Z-betaN`,
   and only a plain `X.Y.Z` when Ben says a version is ready. Fixes and improvements to
   existing features bump the patch (`1.1.1-beta1`: e.g. chat history for the chat peek, focus-aware
   range dots); something new the minor (`1.2.0-beta1`: a new addon, window or tool). The changelog heading matches the tag.
3. The workflow builds the zip, uploads it to CurseForge (project 1795170, `X-Curse-Project-ID` in
   `addons/DeckKit/DeckKit.toc`, token in the `CF_API_TOKEN` secret) and makes a GitHub Release.
   CurseForge holds new files for moderation before they show.

- `.toc` versions are `@project-version@`: the packager writes the tag in. Don't hard-code versions.
- A new addon folder needs a `move-folders` line in `.pkgmeta`, or it's left out of the zip.
- The CurseForge description isn't uploaded: `media/curseforge-description.md` is pasted by hand.
- To check the zip without releasing: Actions > Release > Run workflow builds it with no upload and
  keeps it as a build artifact.

## Repository layout

- `addons/<Name>/`: one folder per addon (`.toc`, Lua, optional `Bindings.xml`).
- `deck-setup/`: Battle.net launcher script and Steam shortcut tooling for the Deck, and the generators
  for the grip chord layout and glyphs, the minimap masks and the focus aura spell list.
- `nav/`: ForeverNav's tools: the data sync from Shortest Path Forever (`tools/sync_spf.py`, pinned in
  `UPSTREAM.json`), its headless tests (`lua5.1 tests/test_data_loads.lua` and `python3 tests/harness.py`, from
  `nav/`, needs `lupa`) and its plan. `addons/ForeverNav` is the addon: it does **not** depend on the DeckKit core
  (any addon may use it), so it doesn't use `DeckKit.NewModule`; keep it that way. Its `Data/` and `Nav/` are synced,
  never edited (corrections to their data go in `addons/ForeverNav/Fixes.lua`, each guarded on the bad value so a sync
  that fixes it retires it; we don't send fixes upstream); its `Routing/` and `Transport/` files are upstream's as written (credited) so fixes port from a diff.
