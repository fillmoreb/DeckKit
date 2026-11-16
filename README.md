# ForeverNav

The fastest way anywhere in WoW: Forever, as a library: walking routes over the real terrain, plus flights, boats,
zeppelins, lifts, the tram and portals, with an API and no window of its own. Built for the DeckKit suite (its
waypoints, compass and assistant drive it), usable by any addon. GPL-3.0-or-later.

Local only for now.

## Credits

ForeverNav stands on other people's work, and says so everywhere it can.

- **[Shortest Path Forever](https://github.com/cjber/shortest-path-forever) by Cillian Berragan (cjber).**
  The walking maps and every piece of travel data ForeverNav routes on are Shortest Path Forever's, synced from its
  releases unchanged. Its router is the model for ForeverNav's. ForeverNav exists because Shortest Path Forever
  solved the hard parts: walking maps baked from the client, routing with no height from the client, lifts, the
  tram, boat timetables. If you want a complete journey planner with its own arrow, tracker and map, install
  Shortest Path Forever itself.
- **[Polestar](https://github.com/fitzforge/polestar) by the Polestar team (0xFitz).** Polestar's routing
  write-ups (its `docs/ARCHITECTURE.md`) are a reference for ForeverNav's router.
- Shortest Path Forever's own sources, which its data carries: WoW: Forever's client tables (via
  [wago.tools](https://wago.tools)), [CMaNGOS classic-db](https://github.com/cmangos/classic-db) and
  [mangos-classic](https://github.com/cmangos/mangos-classic), [InFlight](https://github.com/LudiusMaximus/InFlight),
  and terrain baked with [TrinityCore](https://github.com/TrinityCore/TrinityCore)'s tools and Recast/Detour.

[THIRD_PARTY.md](THIRD_PARTY.md) lists each input, where it is pinned and its licence.

## Status

- **Data sync: done.** `tools/sync_spf.py` takes Shortest Path Forever's walking maps and routing data from a
  release, checks them, and records the release in [UPSTREAM.json](UPSTREAM.json).
- **Reader: done.** `ForeverNav.v1.SurfacesAt(map, x, y)`: the walkable surfaces at a point.
- Router, floor tracking, the rest of the API: next ([PLAN.md](PLAN.md)).

## Layout

- `addon/ForeverNav/`: the addon. `Nav/` and `Data/` are synced (never edited by hand); the code goes beside them.
- `tools/sync_spf.py`: the data sync. `tools/casc.py`: reads Forever's own files from Blizzard's CDN (from the first
  research pass; for baking our own maps one day, if ever needed).
- `tests/`: run from the repo root: `lua5.1 tests/test_data_loads.lua` (the data loads), and
  `python3 tests/harness.py` (the addon loaded headless in Lua 5.1 through lupa: `pip install lupa`).
- `notes/`: research. `cache/`, `vendor/` (ignored): downloads.

## Syncing the data

```sh
python3 -I tools/sync_spf.py                 # the latest release (needs gh)
python3 -I tools/sync_spf.py --tag v1.37.1   # a given release
lua5.1 tests/test_data_loads.lua             # then: it all loads, every map whole
```

The sync refuses a release whose walking maps are in a format the reader doesn't know, whose maps arrived short,
or whose data files changed shape, and changes nothing. `UPSTREAM.json` says which release, commit and client
build the data is from.
