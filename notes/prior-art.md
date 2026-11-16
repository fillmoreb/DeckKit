# Prior art: pathfinding in WoW (surveyed 2026-11-15)

Two kinds exist, and nobody has combined them in an addon.

## Over the terrain: always outside the game

Everything that handles impassable ground, height and bridges extracts geometry from the client's
files (terrain tiles, WMOs, M2 doodads), builds a **Recast** navmesh, and queries it with **Detour**
(A* over polygons, then string pulling). No one hand-authors zone data; the world is in the files.

- **Emulators** (MaNGOS → TrinityCore, AzerothCore, cMaNGOS, vMaNGOS): map/vmap extractors, then
  a movemap generator writing `.mmap` per map and `.mmtile` per tile. Takes hours for all maps.
  [TrinityCore generator](https://www.trinitycore.net/d2/d87/tools_2mmaps__generator_2pathgenerator_8cpp_source),
  [getmangos movemaps](https://www.getmangos.eu/forums/topic/6388-11917-movemaps)
- **namigator** (namreeb): standalone StormLib + Recast library for 1.12.1, 2.4.3, 3.3.5a, with Rust
  bindings. Author has stepped back from it; never shipped in an emulator.
  [repo](https://www.github.com/The-Alpha-Project/namigator), [wiki](https://github.imc.re/namreeb/namigator/wiki),
  [Rust crate](https://lib.rs/crates/namigator)
- **PPather** ("Pontus"): the Glider-era bot pather, a 3D graph from terrain read out of the MPQs.
  Mirror archived 2018. [namreeb/PPather](https://www.github.com/namreeb/PPather)
- **Bots**: AmeisenNavigation, BloogBot/WWoW, wow-navmesh run Detour over TrinityCore/AzerothCore
  meshes. [AmeisenNavigation](https://github.com/Jnnshschl/AmeisenNavigation),
  [wow-navmesh](https://pypi.org/project/wow-navmesh/). Commercial bots (Honorbuddy and others) served
  Recast meshes from their own servers (from memory, unverified).
- **Tooling for modern (CASC) clients:** all of the above read MPQs (≤3.3.5). For CASC:
  CascLib (used here), WoWMap (CASC + ADT/WMO/M2 parsing), cascette-rs (Classic 1.13–1.15),
  warcraft-rs and recast-rs (wowemulation-dev). [WoWMap](https://github.com/shmilyzxt/WoWMap),
  [recast-rs](https://recast-rs.readthedocs.io). One 2022 report: the TrinityCore-style extractor
  failed on Classic. No ready Classic → navmesh pipeline found.

## Inside addons: travel graphs only

Addons can't read the ground. They route over a graph of travel connections and point a straight
arrow at the next stop.

- **FarstriderLib + FarstriderLib Data** (GPLv3, Forever dataset "Camelot", 23 KB): nodes like "Board
  the Tram", boats, Wizard's Sanctum entrances, with x/y/z, cost and faction conditions. Fields
  (`locaId`, `uiMapHint`) suggest it's generated from Blizzard's waypoint tables. API
  `FindTrail(...)` / `FindTrailTo(mapId, x, y)`.
  [lib](https://www.curseforge.com/wow/addons/farstriderlib), [data](https://www.curseforge.com/wow/addons/farstriderlib-data)
- **Mapzeroth** (MIT, Forever): travel graph (portals, hearths, flights, boats), Dijkstra.
  [CurseForge](https://www.curseforge.com/wow/addons/mapzeroth)
- **Zygor's LibRover**: closed, in Zygor Guides. **AzerothWaypoint** (GPLv3, Forever) routes through
  Farstrider, Mapzeroth or LibRover. [AzerothWaypoint](https://www.curseforge.com/wow/addons/azerothwaypoint)
- Guides (RestedXP and the like) get around terrain with hand-placed intermediate waypoints.

## Flow fields

No WoW use found. For one fixed goal a flow field is Dijkstra outward from the goal over the same
mesh; it changes the query, not the data.

## The gap this repo explores

Build the navmesh offline, reduce it to a graph small enough for Lua, ship it as addon data, and run
A* in the game. Nothing at runtime outside the client.
