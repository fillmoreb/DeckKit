# Plan

Revived 2026-11-15. The first plan (bake our own navmesh from the client, notes/height.md) stopped on "addons get no
player height". Shortest Path Forever and Polestar route on terrain without it: the walking map's own connections
tell which floor you are on as you move. So ForeverNav takes Shortest Path Forever's data and builds its own router
and API on it.

## Principles

- **The data is synced, never edited** (`tools/sync_spf.py`, `UPSTREAM.json`). A format change upstream is refused
  until the reader supports it.
- **The router follows upstream's shape.** Ported from Shortest Path Forever's `Routing/` (credited in each file),
  keeping its file split and function names where it can, so an agent can port their later fixes from a diff:
  `UPSTREAM.json`'s commit is where the next port starts.
- **Tests decide.** Fixed routes with expected results, run headless in Lua 5.1 on the synced data. A sync or a
  ported fix lands when they pass, or change for a reason that's understood.
- **API first, no window.** DeckKit (MIT) calls ForeverNav through its API, as a game-data library.

## Steps

1. **Data sync** — done. 11 data files and 3 walking maps (Eastern Kingdoms, Kalimdor, Zephras Isle) from v1.37.1,
   19.7 MB; `tests/test_data_loads.lua`.
2. **The reader.** Decode one cluster (an ADT tile) of a walking map: grid, heights, floors, graph, from the format 3
   description in the Nav files' headers and Shortest Path Forever's `Routing/PathGrid.lua`. Check in game: the
   surfaces under where a character stands, against its real place.
3. **The walking search** (`Routing/Path.lua`, `PathJobs.lua`): A* over the cluster graph, run as frame-budgeted jobs.
4. **The floor rule** (`Routing/Floor.lua`): candidate surfaces kept while the map connects them.
5. **The planner** (`Routing/Planner.lua`): walks joined with flights, boats, zeppelins, lifts, the tram, portals and
   the hearthstone, with the timetables.
6. **Route tests**: Durotar to Westfall (zeppelin), the Undercity's rings and lifts, Thunder Bluff's lifts, a
   Stormwind canal walk, the Deeprun Tram, a flight the character hasn't found.
7. **The API** for DeckKit: a route's legs (text, method, seconds), the next turn's position for a compass to aim
   at, change events. Then DeckKit's waypoints use ForeverNav instead of MapzerothLib.
8. **Keeping up**: a scheduled agent check of Shortest Path Forever (and Polestar, for routing ideas): sync new data,
   port routing fixes on a branch, run the route tests, report.

## Licences

ForeverNav is GPL-3.0-or-later. DeckKit stays MIT: it calls ForeverNav's API and never includes its code or data.
