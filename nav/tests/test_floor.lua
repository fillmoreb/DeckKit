-- The floor rule (Routing/Floor.lua, wired by v1.Follow): following a walk along the Undercity's lower ring, from the
-- west lift's bottom to the east lift's (the ring between the canals below and the ruins of Lordaeron above), the
-- followed floor is always the walk's own: never the ruins, never the canals.
ns.LoadSaved()
local api, Path, Grid, Floor = ForeverNav.v1, ns.Path, ns.PathGrid, ns.Floor

local WEST, EAST = ns.Docks[1010], ns.Docks[1012]                -- Undercity west and east lifts, Bottom
check(WEST.site:find("Undercity") and WEST.name == "Bottom" and EAST.name == "Bottom", "the two lifts' bottoms")
-- Off the lifts themselves (Floor lets the floor go within 10 yd of a lift), on the ring beside them.
local function beside(dock, dx) return { x = dock.x + dx, y = dock.y, z = dock.z } end
local from, to = beside(WEST, -14), beside(EAST, -14)
local points, cost = Path.FindSync(0, from, to, false)
check(points, "a walk round the ring: " .. tostring(cost))

-- Decode every tile the walk crosses up front, as Floor's own decoding job would between frames.
local st = Grid.State(0)
for _, pt in ipairs(points) do
    local k = Grid.locate(st, pt.x, pt.y)
    if k then Grid.Quiet(Grid.grid, st, k) end
end

-- Walk it: a sample every 3 yd along the walk, as v1.Follow samples a moving player.
local samples, known, wrong, worst = 0, 0, 0, 0
for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    for s = 0, math.max(0, math.floor(len / 3) - 1) do
        local f = len > 0 and s * 3 / len or 0
        local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
        local z = (a.z and b.z) and a.z + (b.z - a.z) * f or nil
        PLAYER = { x = x, y = y, map = 0 }
        Floor.Sample(0, x, y)
        samples = samples + 1
        local h = api.PlayerFloor()
        if h and z then
            known = known + 1
            local off = math.abs(h - z)
            if off > worst then worst = off end
            if off > 8 then wrong = wrong + 1 end
        end
    end
end
check(samples > 20, "a walk worth following: " .. samples .. " samples")
check(known >= samples * 0.6, ("the floor is known most of the way: %d of %d samples"):format(known, samples))
check(wrong == 0, ("and always the walk's own floor: %d samples off by more than 8 yd (worst %.0f)"):format(wrong, worst))
print(("floor: Undercity ring, west lift to east lift: %d samples, floor known at %d, worst %.1f yd off the walk's height"):format(
    samples, known, worst))

-- v1.Follow takes an owner and lets go of the floor when the last one stops.
check(api.Follow("Test", true) and api.Follow("Test", false), "Follow on and off")
check(api.PlayerFloor() == nil, "no floor once nobody follows")
check(not api.Follow("", true), "an owner is required")
