# guide/: ForeverGuide's tools

ForeverGuide (`addons/ForeverGuide`, with `ForeverGuide_Horde` and `ForeverGuide_Alliance`) plays leveling
guides for WoW: Forever and tells other addons where a character is in them (`ForeverGuide.v1`, see the header
of `addons/ForeverGuide/API.lua`). GuidePad draws it in the quest tracker's place.

## Credit

**The guides are [Polestar](https://github.com/fitzforge/polestar)'s, by Fitz**: every route, step, tip and
coordinate, compiled by Polestar's `forge guide compile` and synced here unchanged. Polestar is a full guide
addon of its own, with far more than we use (its arrow, travel planner, dungeons, professions, the guide
menu); if you play with a mouse, play Polestar. Its guides are GPL-3.0-only, and so is our copy of them.

The rules ForeverGuide follows for when a goal counts as done are Polestar's too (its `docs/ARCHITECTURE.md`,
"Guide data"); the engine is our own, much smaller one, written from them.

The facts in the guides come from the sources Polestar names in `LICENSE-DATA.txt`, shipped beside each guide
file: pfQuest (MIT), CMaNGOS classic-db (GPL-3.0), the WoW: Forever TrinityCore database (GPL-2.0), EG Link
(CC BY 4.0), wago.tools and Blizzard's client tables, and web quest databases including QuestieDB, used as facts.

## Syncing

```sh
python3 -I tools/sync_polestar.py              # the latest Polestar release
python3 -I tools/sync_polestar.py --tag v0.4.1 # a given one
```

It copies `Guides.lua` and `MapFrames.lua` from Polestar's `addon/Polestar_Guides*` folders, adding one header
line (`local Polestar = ForeverGuide.Data`, so the files' `Polestar.RegisterGuide` calls reach ForeverGuide and
no global named Polestar is made), and records the release, commit and file hashes in `UPSTREAM.json`. It refuses
a file that calls a Polestar function the engine doesn't answer. Polestar's race parts (baked walks into each
step) are left out: ForeverNav walks.

Never edit the synced files. After a sync, run the test and look at a new character's first steps in the game.

## Test

```sh
lua5.1 tests/test_engine.lua
```

The real guides against a stand-in game: a Skyborne rogue played through Zephras Isle's first steps, plus the
soft-goal and condition rules on small made-up guides.
