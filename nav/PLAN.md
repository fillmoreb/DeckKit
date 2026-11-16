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
2. **The reader** — done. `Routing/PathGrid.lua` ported whole (only the global renamed); `ForeverNav.v1.SurfacesAt`.
   Headless (`tests/harness.py`, lupa): all 14 lift landings found at their recorded heights, within 16 yd of the
   shaft. In game, the same answers through the client's own decoding (Rektagho, Valley of Trials: ground at 44).
   A tile's first decode is 47 ms unsliced: step 4 decodes ahead under the frame budget, as upstream does.
3. **The walking search** — done. `Routing/Path.lua` and `PathJobs.lua` ported whole; `ForeverNav.v1.Walk`.
   Headless: Valley of Trials to Orgrimmar's flight master 2,862 yd (x1.26 the straight line, no water), to the
   Crossroads 2,088 yd over the Southfury bridge (8 yd wet), every corner on a surface. In game through v1.Walk: the
   same route, 148 frames at 2 ms (3.4 s, mostly first decodes of the tiles it crosses).
4. **The floor rule** — done. `Routing/Floor.lua` (ported) wired by `v1.Follow(owner, on)` and `v1.PlayerFloor()`:
   while followed, the player's floor is sampled as they move (4 times a second after a yard), the tiles around them
   decoded ahead under the frame budget; walks and plans from the player start on it. Along the Undercity's lower
   ring the followed floor stays within 1.8 yd of the walk's own height, never the ruins above or the canals below.
   DeckKit follows while it has a walk to draw.
5. **The planner** — done. `Routing/Planner.lua`, `Transport/Model.lua`, `Timetable.lua` and `Teleports.lua` ported
   whole; ForeverNav's own `Services.lua` (what they call on), `Context.lua` (the planner's options, flight points
   learned from the flight master's map) and `Steps.lua` (each leg in words). `v1.Plan` (16 ms in game) and
   `v1.PlanMeasured`: walk legs start as straight-line estimates, so it measures the walks the plan uses, plans again,
   and repeats until nothing is estimated (Durotar to Westfall: 13.4 min estimated, 16.7 measured; it tries the
   Ratchet boat on the way and rejects it). The Hearthstone and teleports count from where you stand; the bind point's
   place is learned where you bind or land. Not yet: the ride observer (without a sighting a ride's wait is half its
   period), party mages' portals.
6. **Route tests**: Durotar to Westfall (zeppelin), the Undercity's rings and lifts, Thunder Bluff's lifts, a
   Stormwind canal walk, the Deeprun Tram, a flight the character hasn't found.
7. **The API** for DeckKit: a route's legs (text, method, seconds), the next turn's position for a compass to aim
   at, change events. Then DeckKit's waypoints use ForeverNav instead of MapzerothLib.
8. **Keeping up**: a scheduled agent check of Shortest Path Forever (and Polestar, for routing ideas): sync new data,
   port routing fixes on a branch, run the route tests, report.

## Licences

ForeverNav is GPL-3.0-or-later. DeckKit stays MIT: it calls ForeverNav's API and never includes its code or data.
