# DeckKit

Controller-first addons for **WoW: Forever** on the Steam Deck, plus the Deck-side setup that goes with them.

> **Built with AI.** DeckKit is largely developed with an AI coding assistant
> ([Claude Code](https://claude.com/claude-code)). Most of the Lua here was written by Claude
> from my descriptions, then reviewed and tested in-game by me on a Steam Deck. Expect the kind of
> rough edges that come with that, and please report anything broken. Notes for the assistant
> live in [`CLAUDE.md`](CLAUDE.md), and you're welcome to use them if you work on DeckKit with AI too.

## Addons (`addons/`)

| Addon | What it does |
|---|---|
| **WayPad** | Waypoints dialed in with the d-pad, floating arrow, map + minimap pins, `/way` |
| **DisenchantDeck** | List of disenchantable bag items: A disenchants, Y hides, LB/RB shows hidden (`/dd`) |
| **ChatDeck** | Hold a button to read chat full-screen; right stick scrolls |
| **MapDeck** | Hold a button for a full-screen map (works in combat); right stick zooms to the continent |
| **MenuReload** | Reload UI button in the game menu, under AddOns |
| **FishingTally** | Per-session fishing loot counts (`/fishtally`) |

Planned: a shared **DeckKit core** (controller input, windows, settings) that the addons build on.
Keep SavedVariables and binding names unchanged when refactoring so existing data and binds carry over.

Deploy to the Deck: copy `deploy.local.example` to `deploy.local` and fill in your Deck's SSH target and AddOns path,
then `./deploy.sh WayPad MapDeck` (or no arguments for all) and `/reload` in game.

## Deck setup (`deck-setup/`)

- `wowforever.bat` – lives at `C:\wowforever.bat` in the Lutris Battle.net prefix; starts Battle.net and
  re-sends `launch WoWF` every 10 s until Wow.exe runs.
- `addshortcut.py` + `wowforever-art/` – the "WoW Forever" Steam shortcut and its artwork.

## Patches to other people's addons/plugins (`patches/`)

- `decktation/strip-blank-audio.patch` – stops whisper tags like `[BLANK_AUDIO]` being typed into chat.
  Re-apply after a Decktation update.

## License

MIT, see [`LICENSE`](LICENSE). WayPad's controller input is adapted from BagPad (MIT, © 2026 Chris).
The Steam art in `deck-setup/wowforever-art/` is AI-generated and not covered by the MIT License.
DeckKit is an unofficial fan project, not affiliated with Blizzard Entertainment. World of Warcraft,
Hearthstone and related marks belong to Blizzard.
