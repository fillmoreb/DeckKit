# Can an addon know the player's height? (tested 2026-11-15, build 1.60.1.70938)

No. Everything tried gives a flat (2D) position or distance.

| Source | Result |
|---|---|
| `UnitPosition("player")` outdoors | y, x, **z = 0**, instance id. Works outdoors (it's untainted-only per the API docs), but height is stripped. |
| `C_Map.GetPlayerMapPosition` / `GetWorldPosFromMapPos` | 2D by design. |
| `UiMapPoint.CreateFromCoordinates(map, x, y, z)` → `C_Map.SetUserWaypoint` | The z is dropped: `GetUserWaypoint().position.z` is nil. |
| `C_Navigation.GetDistance()` to a super-tracked pin at the player's own spot | 0.00006 yd for 900 frames while Ben jumped in place repeatedly. **Flat distance.** |
| `C_QuestLog.GetDistanceSqToQuest` | Matches the flat distance to the quest's map point (99.70 vs 99.71 yd). |
| Minimap API (`MinimapDocumentation.lua`) | Nothing about elevation. |

**The minimap's above/below arrows** (on party members and tracked targets) are drawn by the engine:
it chooses the up/down blip variant itself, comparing heights in C++. Nothing reaches Lua.

Not tested: `UnitDistanceSquared(partyUnit)` (needs a party member; if it's 3D, it gives height
relative to party members only, with no help solo).

## What this means for the plan

The in-game side can't measure height, so where walkable surfaces stack (a bridge over a road,
a building's upper floor, a cave under a hill) it has to infer which layer the player is on:

- **Continuity:** walkable layers connect only at specific portals (a ramp's top and bottom), so
  tracking the player's polygon from frame to frame tells which layer they're on, as long as the
  first fix is right.
- **First fix:** prefer the ground layer, unless a hint says otherwise.
- **Hints the client does give:** `IsIndoors()` (inside a WMO marked interior, e.g. a building or
  cave), `IsSwimming()` (in water, so under a bridge rather than on it), `IsFlying()`/`IsFalling()`,
  and the subzone name (`GetSubZoneText`), which often differs between levels.
- The data should mark stacked areas, so the in-game side knows where it's guessing and can
  fall back to a plain direction there.
