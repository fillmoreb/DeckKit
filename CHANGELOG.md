# Changelog

## Unreleased

### Changed
- **The grips moved to F1-F8** (held: L4 F1, R4 F2, L5 F3, R5 F4; long press F5-F8), so F9-F12
  are free for other addons. **Rerun `make-chord-layout.py --install`** (README, Grip chords step 3)
  after updating, or the grips stop working. Your slots are kept. README has a new Keys section.
- **Decktation's status hook left DeckKit**, with its four signal bindings (Insert / Home / End /
  Delete) and the old Decktation patches (built into Decktation 0.3.24). The dictation indicator still
  follows the L4 + R4 chord; other addons can report the exact state with `DeckKit.Dictation.SetState`.

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
