# Changelog

## 1.3.0-beta1 - 2026-11-15

### New
- **Routes to anywhere** (ForeverNav, a new addon in the download). Set a waypoint across the world and the
  compass takes you there leg by leg: walk to the zeppelin tower, take the zeppelin to Grom'gol, walk on. It
  joins walks over the real terrain with flights (between the flight points you've found: open a flight
  master's map once so it knows them), boats, zeppelins, lifts, the Deeprun Tram, portals and your Hearthstone.
  The step shows under the compass's pointer; the walk to the next leg is drawn on the minimap (lilac dots)
  and the peek map (a lilac line), from where you stand and on the floor you're on, and re-planned if you
  wander off. Rides you take teach it their real schedules. Map & travel › Waypoints: **Plan routes** and
  **Follow roads** (on: keeps to roads, safer while levelling; off: the shortest line). `/deckkit route`.
  ForeverNav's walking maps, travel data and route planner come from **Shortest Path Forever** by Cillian
  Berragan, with thanks. It needs nothing else from DeckKit, and any addon can use it (`ForeverNav.v1`).
- **A compass in the status bar** (DeckHUD): half the horizon centered on your facing, your waypoint with its
  distance, Blizzard's map pin, a guard's directions, the focused quest (pulsing while you're in its area) and
  your group. Screen › Status bar picks its width, view and marks. The mouseover tooltip is a card under it.
- **PackPad**, DeckKit's own bags, on Blizzard's gamepad bag window: bag icons in their own column, the slots
  in one grid, item marks, and a full-screen bag peek on a grip chord with Pawn's upgrade arrows. It replaces
  BagPad.
- **MarketDeck**: auction house prices with nothing to press. A snapshot each time you open the auction house
  (when the last is over an hour old), read a little each frame; auction, vendor and disenchant values on item
  tooltips.
- **A welcome window** for first-time setup: each step and how it's going, with a button to do it (the Steam
  controller layout, **Apply everything suggested**, HealPad's macros). `/deckkit setup` reopens it. INSTALL.md
  walks through setting DeckKit up from zero.
- **Grip chords per character**: slots stay shared, and a character can change any of them for itself
  (Controls › Grips › Slot changes apply to).
- **Dictation**: the chord shows "Starting" the moment you press it, and the game's sound fades out while you
  dictate so the Deck's mic doesn't hear its speakers (Chat › Dictation › Mute the game while dictating).

### Changed
- **License: the GNU General Public License, version 3 or later** (was MIT; releases up to 1.2.0-beta1 stay
  MIT). It matches the projects DeckKit now builds on.
- **Waypoints live in the DeckKit core**, and WayPad is their controller front end: its list and Add windows
  are one screen, the coordinates dialed in. WayPad's floating arrow is gone: the compass shows the way.
- MapDeck: the current waypoint's pin bounces, and the peek follows you into another zone while held.

### Fixed
- DisenchantDeck leaves your bags open when you pick Disenchant (closing them tainted the gamepad bar).
- HealPad's macro names could collide and overwrite other macros.
- The Suggested settings page and the layout undo were missing from the menu.
- An old auction scan's timeout could cancel a newer scan.
- The waypoint editor kept editing the right waypoint after the list changed; a hand-off follows the new active
  waypoint; focus aura settings apply after a reload.

### For addon authors
- `ForeverNav.v1`: `Plan`, `PlanMeasured`, `Walk`, `SurfacesAt`, `Follow` and `PlayerFloor`.
- `WayPad_Add`, `WayPad_Get` and `WayPad_Remove` work without WayPad, with stable ids; `DeckKit.Route.Summary`
  gives a waypoint's trip.
- Layouts from data (`DeckKit.UI.Build`, `UI.ShowLayout`, `DeckKit.Conditions`, `DeckKit.JSON`), welcome-window
  steps (`DeckKit.Setup.AddStep`), and the dictation indicator's `Claim()` and Thinking state.

## 1.2.0-beta1 - 2026-11-13

### New
- **A status bar across the top of the screen** (DeckHUD). A dark bar with a thin metal edge and
  readings you pick for its left, middle and right: clock, FPS, latency, gold, free bag slots,
  durability, XP and coordinates. With **DeckTelemetry** (from the companion suite DeckKitAfterDark)
  it also shows the Steam Deck's own battery, battery draw, APU power, CPU / GPU load, memory, APU
  temperature and fan. An XP line runs along its bottom, so Blizzard's XP bar is hidden. The minimap
  moves under it. Screen › Status bar, where **Buffs under the bar** also moves your buffs down to
  clear it (`/deckkit layout buffs`).
- **Loot rolls, compact until you need them** (DeckHUD). Forever's Need / Greed / Pass window opens in
  the top-left corner, and until you press View it's a small list instead: each item's [name] in its
  quality color with a countdown under it (a thin bar, seconds, or a bar behind the name). View brings
  up the game's window to roll. Screen › Loot rolls; each part can be turned off, and the list has
  its own opacity.

### Changed
- **The grips moved to F1-F8** (held: L4 F1, R4 F2, L5 F3, R5 F4; long press F5-F8), so F9-F12
  are free for other addons. **Rerun `make-chord-layout.py --install`** (README, Grip chords step 3)
  after updating, or the grips stop working. Your slots are kept. README has a new Keys section.
- **Decktation's status hook left DeckKit**, with its four signal bindings (Insert / Home / End /
  Delete) and the old Decktation patches (built into Decktation 0.3.24). The dictation indicator still
  follows the L4 + R4 chord. For Decktation's exact state, install **DeckDictation** from
  DeckKitAfterDark (other addons can report it with `DeckKit.Dictation.SetState`).

## 1.1.1-beta1 - 2026-11-13

### New
- **Chat history survives reloads.** The last 200 lines of each chat tab are kept per character and
  put back when the UI loads, under a gray "earlier chat" line; the chat peek shows them too.
  Chat › "Keep chat across reloads" (on by default) and "Clear saved chat".
- **Range dots that follow your focus.** On crossbar buttons holding a `[@focus]` macro, the range
  dot checks your focus instead of your target: white in range, red out of range. With no focus,
  the game's own dot is back.
- **No target menu in combat.** With no trigger held, Y opens your target's menu, which takes over
  the pad until you press B. During a fight that's now ignored; with a trigger held, Y works as
  usual. Controls › Buttons (on by default).
- **Hide macro names** on the crossbar and action bars, so a macro shows just its icon.
  Screen › Action bars (off by default).

### Changed
- **A Chat tab in the menu** with the chat window look, the chat peek, chat history and dictation.
- **Focus auras sit above the focus frame's name**, each on a dark tile, so they read against the
  world and stay clear of the party frames.
- **Dictation popups** use DeckKit's window look and the game's voice chat icons. A new Indicator
  opacity slider (Chat › Dictation) sets how solid they are.
- **The "LB" prompt under party and raid frames is hidden** (LB still works). Healing › Party, raid
  and focus frames.
- **Map peek:** party and raid members are round dots in their class color, like on Blizzard's
  map, instead of light-blue squares that vanished against quest areas.

## 1.1.0 - 2026-11-13

### New
- **DeckHUD: a focus frame for healers.** Screen › Unit frames › Focus frame offers Blizzard's,
  **No portrait**, or **Name and health**: a big first name (class color; for NPCs, their full name
  in reaction color) over a tall health bar. Under the bar, an aura row: the buffs you pick (your
  class's by default), your Weakened Soul, and debuffs you can dispel. **Center the focus frame**
  places it between your frame and your target's. Works in combat.
- **DeckKit: grip cheat sheet.** A small on-screen list of what your grip chords do. Turn it on in
  Controls › Cheat sheet, pick one of four spots, and tick the slots to show. Also on a grip chord
  slot, or `/deckkit sheet`.

### Changed
- **Keep moving while you peek.** The chat and map peeks no longer take the sticks, so you can keep
  running while one is open. In exchange, chat's right-stick scrolling and the map's zoom out to the
  continent are gone.
- **"Paddles" are now grips**, Valve's name for L4, R4, L5 and R5: the menu section is
  Controls › Grips. Your slots carry over.
- **Reload UI is no longer put on F6 for you.** Bind it under Key Bindings › DeckKit, put it on a
  grip chord, or use MenuReload's button in the game menu. If F6 already reloads for you, it still
  does.
- American spellings in menus and messages ("Center", "color").

### Voice chat
- Works with Decktation 0.3.24's built-in status hook and **Exact binding only**. No more patching
  Decktation. Setup steps are on GitHub.

## 1.0.0 - 2026-11-11

First release. Controller-first addons for WoW: Forever on the Steam Deck, all set up from one menu
(press Menu twice, or /deckkit).

- **DeckKit**: the shared core and menu. Paddle chords: the four back grips, alone or together,
  pressed or held, each a slot for any action, including spells, in combat. Needs DeckKit's Steam
  controller layout (see the project page).
- **HealPad**: a d-pad cursor on party and raid frames that sets your focus; makes heal macros from
  your spellbook (buffs folded into one-button sequences); practice party and raid frames to try it
  solo.
- **QuestPad**: a big button for the quest item you need, found by the quest's real area or by your
  target.
- **MapDeck** / **ChatDeck**: hold a button for the map or chat, full screen.
- **WayPad**: waypoints dialed in with the d-pad, with an arrow to follow.
- **DisenchantDeck**: everything you can disenchant, in a controller list.
- **DeckAngler**: fishing on one button, with a catch tally.
- **DeckHUD**: a square minimap, a tidy chat frame, and one-press Edit Mode layouts (party and raid
  frames lined up).
- **DeckSundries**: wand shoot on a button, and small controller extras.
- **MenuReload**: a Reload UI button in the game menu.
