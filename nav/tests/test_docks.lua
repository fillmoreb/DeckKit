-- Every dock's boarding point (its `walk`, where the planner's walk to it ends) stands by the dock and on a surface you
-- can walk: a boarding point off on another ledge sends the walk past the tower (Fixes.lua has the one that did).
local api = ForeverNav.v1
local NEAR = 30 -- a boat lies off its pier; 51 yd was the bad one
local checked = 0
for id, d in pairs(ns.Docks) do
    if d.walk then
        local off = math.sqrt((d.walk.x - d.x) ^ 2 + (d.walk.y - d.y) ^ 2)
        check(off <= NEAR, ("dock %d: boarding point %.0f yd from the dock (%.0f, %.0f)"):format(id, off, d.walk.x, d.walk.y))
        checked = checked + 1
    end
end

-- Orgrimmar's Grom'gol zeppelin boards from the tower top (z 54), and a walk there from across the platform stays on it.
local dock = ns.Docks[4]
local on = false
for _, s in ipairs(api.SurfacesAt(1, dock.walk.x, dock.walk.y) or {}) do
    if math.abs(s.z - dock.walk.z) <= 2 then on = true end
end
check(on, "Orgrimmar's Grom'gol boarding point is on the tower top")
local plan = assert(api.Plan({ map = 1, x = 1332.2, y = -4646.5, z = 54 }, { map = 0, x = -12400, y = 200 },
    { faction = "Horde", teleports = false }))
local walk = plan.legs[1]
check(walk.mode == "walk" and math.abs(walk.to.x - dock.x) < 5 and math.abs(walk.to.y - dock.y) < 5,
    ("the walk to the zeppelin ends at the dock: %.0f, %.0f"):format(walk.to.x, walk.to.y))
local points, yards = ns.Path.FindSync(1, { x = 1332.2, y = -4646.5, z = 54 }, dock.walk, false)
check(points and yards < 45, ("across the tower top to it: %.0f yd"):format(yards or -1))
print(("docks: %d boarding points within %d yd of their docks; Orgrimmar's Grom'gol zeppelin from the tower top: %.0f yd")
    :format(checked, NEAR, yards))
