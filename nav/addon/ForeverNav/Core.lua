-- ForeverNav: the fastest way anywhere in WoW: Forever, as a library (no window of its own). GPL-3.0-or-later.
--
-- The walking maps (Nav/) and routing data (Data/) are Shortest Path Forever's, by Cillian Berragan (cjber,
-- https://github.com/cjber/shortest-path-forever), synced unchanged by tools/sync_spf.py. The router in Routing/ is
-- ported from Shortest Path Forever's, credited in each file. See README.md and THIRD_PARTY.md.
--
-- Files, in load order (ForeverNav.toc):
--   Core.lua             the shared table (`ns`) and the global ForeverNav
--   Data/, Nav/          synced data: Data/*.lua write onto `ns`, Nav/*.lua onto ForeverNavPathData
--   Routing/PathGrid.lua the walking maps' decoder and grid helpers   } ported from Shortest Path Forever as upstream
--   Routing/Path.lua     the walking search (HPA* over tiles, A* inside) } wrote them (credited in each file)
--   Routing/PathJobs.lua the searches as frame-budgeted jobs           }
--   Routing/Floor.lua    the player's floor, followed as they move     }
--   API.lua              ForeverNav.v1, the public API
local ADDON, ns = ...

ns.ADDON = ADDON

-- The public global. `v1` is the API (API.lua); `internal` is this addon's own table, for development tools: anything
-- in it can change in any release.
ForeverNav = ForeverNav or {}
ForeverNav.internal = ns
