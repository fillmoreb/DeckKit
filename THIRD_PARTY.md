# Third-party inputs

ForeverNav is GPL-3.0-or-later ([LICENSE](LICENSE)). Everything it ships that it did not write:

| Input | What ForeverNav takes | Pin | Licence |
|---|---|---|---|
| [Shortest Path Forever](https://github.com/cjber/shortest-path-forever), by Cillian Berragan (cjber) | `addon/ForeverNav/Nav/*` (the walking maps) and `addon/ForeverNav/Data/*` (taxi, transports, docks, portals, teleports, zones, town areas, walks, roads, spawn heights), unchanged except the walking maps' global name and a header on each file | `release` and `commit` in [UPSTREAM.json](UPSTREAM.json) | GPL-3.0-or-later |

That data in turn carries Shortest Path Forever's inputs, credited in its own
[THIRD_PARTY.md](https://github.com/cjber/shortest-path-forever/blob/main/THIRD_PARTY.md):

| Its input | In which data | Licence |
|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | taxi paths, transports, lifts, portals, teleports | Blizzard Entertainment's game data |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | portal and teleport destinations, transport spawns and periods, spawn heights | GPL-3.0 |
| [CMaNGOS mangos-classic](https://github.com/cmangos/mangos-classic) | the transport timetable model and flight speed (reimplemented in its tools) | GPL-2.0-or-later |
| [InFlight](https://github.com/LudiusMaximus/InFlight) | recorded flight durations | MIT |
| The Forever client's terrain, baked with [TrinityCore](https://github.com/TrinityCore/TrinityCore)'s tools (Recast/Detour) and the player's collision limits from [benilla-re](https://github.com/samwhosung/benilla-re) | the walking maps | derived data, GPL-3.0-or-later; Blizzard's EULA applies to the client files |

Read for ideas, not copied: [Polestar](https://github.com/fitzforge/polestar) (GPL-3.0)'s routing documentation.
Anything later ported from Polestar's or Shortest Path Forever's code is credited in the file it lands in and here.

Build and research only: [CascLib](https://github.com/ladislav-zezula/CascLib) (MIT), in `vendor/`, for
`tools/casc.py`.
