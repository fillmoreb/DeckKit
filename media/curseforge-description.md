# DeckKit

DeckKit is a suite of addons for playing **WoW: Forever** with a controller, built on and for the **Steam Deck**. Everything works from the gamepad alone, and every setting lives in one controller-driven menu.

**Requires:** WoW: Forever. Made for the Steam Deck with the game's Gamepad UI. Other controllers should work too, but the Deck is what it's tested on.

## The DeckKit menu

Press the **Menu (☰) button twice quickly**, or type `/deckkit`, to open one settings window covering every module. D-pad up/down picks a setting, left/right changes it, A toggles or runs it, LB/RB switches modules, and B closes it. Button prompts use the game's own controller icons.

## What's included

**WayPad** – Waypoints without a keyboard. Dial in coordinates digit by digit with the d-pad, then follow a floating arrow to the active waypoint. Waypoints show on the world map and minimap. A list window lets you make one active, edit it or remove it. Supports TomTom-style `/way 45.2 62.8` too.

**MapDeck** – Hold a button to see the map full-screen, even in combat. While it's held, the right stick zooms out from the zone to the continent and back in. Shows you, your party, quest markers and WayPad waypoints.

**ChatDeck** – Hold a button to read chat full-screen in a large font. While it's held, the right stick scrolls back through the history. New messages appear live.

**DeckAngler** – Controller fishing. With a fishing pole equipped, **X casts Fishing** (out of combat); once the line is out, X goes back to interacting, so it clicks the bobber. Includes a per-session catch tally panel, an optional chime when a cast times out with no bite, and an optional reminder if you've had the pole out a while without casting.

**DisenchantDeck** – A controller list of everything in your bags you can disenchant. A disenchants the selected item, Y hides items you want to keep, and LB/RB shows the hidden ones.

**DeckHUD** – Interface tweaks for a handheld screen. Each is on by default and can be switched off in the menu:
- a **square minimap** in the top-right corner, as wide as the quest tracker, without the buttons around its edge (zoom and size are in the menu instead), optionally leaving room for the Steam performance overlay's battery readout
- a **thin chat frame** tucked into the bottom-left corner, without the Combat Log tab
- Edit Mode layout tools (`/deckkit layout`), which back up your layout before changing it

**DeckSundries** – Small extras. **Wand shoot:** with a wand equipped and a living enemy targeted, X fires your wand instead of a melee swing; anything else still interacts normally.

**MenuReload** – Adds a Reload UI button to the game menu.

**DeckKit** (the core) – Shared controller input and windows for the modules above, the settings menu, and a **DeckKit section in Key Bindings**. It sets **Reload UI to F6** once, only if F6 is unbound; you can rebind or clear it.

## Setup

Install, then assign the hold-to-peek buttons (map, chat) and WayPad's buttons under **Key Bindings › DeckKit**. The Steam Deck's back grips work well for the peeks. Most modules need the DeckKit core, which is included.

## Active development

DeckKit grows out of actually playing on the Deck. Features get added and polished whenever I run into something I need, so expect regular updates. Suggestions and bug reports are welcome on GitHub.

## Built with AI

DeckKit is largely written with an AI coding assistant (Claude Code) from my descriptions, then reviewed and tested in game on a Steam Deck.

## Credits and license

MIT License. Controller input is adapted from **BagPad** (MIT, © 2026 Chris); the shared button overrides, wand shoot and the controller icon list are adapted from **Improved Forever** (MIT, © 2026 markg).

---

Source, issues and changelog: https://github.com/fillmoreb/DeckKit
