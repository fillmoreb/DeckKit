-- ForeverNav.v1.SurfacesAt reads the walking maps the way the bake wrote them. Ground truth from the data itself:
-- every lift (Data/Transports.lua's docks from 1001) stands where both its landings are, one above the other, so the
-- cell there must hold a surface at the top landing's height and one at the bottom's.
local api = ForeverNav.v1
check(api.GetVersion() == 1, "v1")

local function near(surfaces, z, tol)
    for _, s in ipairs(surfaces) do
        if math.abs(s.z - z) <= tol then return s end
    end
end

local TOL = 4   -- the map stores heights in 2-yard steps, and a landing stands a little above its floor
local lifts, checked = {}, 0
for id, dock in pairs(ns.Docks) do
    if id >= 1001 and id < 1100 then lifts[#lifts + 1] = dock end   -- lifts; 1101+ are the tram's stations
end
check(#lifts >= 12, "the lift landings: " .. #lifts)
-- A landing's x, y is the middle of the shaft, and where the shaft is open (the platform is a moving object, not
-- terrain) the floor you step onto is beside it: off a cliff (the Great Lift), round a ring (the Undercity). As
-- Shortest Path Forever's snap does for any endpoint, a surface at the landing's height within SNAP cells counts.
local CELL, SNAP = 1600 / 3 / 67, 6
local exact, far = 0, 0
for _, dock in ipairs(lifts) do
    local surfaces, why = api.SurfacesAt(dock.map, dock.x, dock.y)
    check(surfaces, ("%s %s: %s"):format(dock.site, dock.name, tostring(why)))
    local best
    for dx = -SNAP, SNAP do
        for dy = -SNAP, SNAP do
            local d = math.sqrt(dx * dx + dy * dy)
            if (not best or d < best) and near(api.SurfacesAt(dock.map, dock.x + dx * CELL, dock.y + dy * CELL) or {}, dock.z, TOL) then
                best = d
            end
        end
    end
    local heights = {}
    for i, s in ipairs(surfaces) do heights[i] = ("%.0f"):format(s.z) end
    check(best, ("%s %s at z %.1f: no surface at that height within %d cells (its own cell has %s)"):format(
        dock.site, dock.name, dock.z, SNAP, table.concat(heights, ", ")))
    if best == 0 then exact = exact + 1 end
    if best > far then far = best end
    checked = checked + 1
end

-- Lowest first, and a lift's cell has at least its two landings.
local uc = api.SurfacesAt(0, 1596.15, 291.8)                     -- Undercity, west lift
check(#uc >= 2, "the Undercity's west lift has a top and a bottom: " .. #uc)
for i = 2, #uc do check(uc[i - 1].z <= uc[i].z, "surfaces come lowest first") end

-- Where Rektagho stood (UnitPosition: Valley of Trials, Kalimdor): open ground.
local vot = api.SurfacesAt(1, -598.3, -4410.5)
check(vot and #vot >= 1, "the Valley of Trials has ground")

-- Off the data, and nonsense.
local none, why = api.SurfacesAt(1, 99999, 99999)
check(none == nil and why == "outside", "far off the map: outside, " .. tostring(why))
check(select(2, api.SurfacesAt(9999, 0, 0)) == "nodata", "a map without data: nodata")
check(select(2, api.SurfacesAt("x", 0, 0)) == "invalid", "bad arguments: invalid")

print(("surfaces: %d lift landings on their floors (%d in their own cell, the furthest %.0f yd off); Undercity west lift %s; Valley of Trials %s"):format(checked, exact, far * CELL,
    (function() local t = {} for i, s in ipairs(uc) do t[i] = ("%.0f"):format(s.z) end return table.concat(t, "/") end)(),
    (function() local t = {} for i, s in ipairs(vot) do t[i] = ("%.0f %s"):format(s.z, s.kind) end return table.concat(t, "/") end)()))
