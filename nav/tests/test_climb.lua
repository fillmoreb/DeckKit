-- No route climbs a rock face. Shortest Path Forever's walking maps (cells about 8 yards across) link some cells
-- whose ground is a wall apart: in Orgrimmar, from the Valley of Strength toward 63.4, 45.4, the route went straight
-- up a 9-yard face onto a rock outcrop and down the other side (Ben, 2026-11-17: "sending me through rock walls").
-- Every stretch of each route is followed along the ground, 2 yards at a time, and no step of it may rise more than
-- a climb a player can walk.
local Path = ns.Path
local api = ForeverNav.v1
local MAX_RISE = 6 -- yards up between ground samples 2 yards apart: a wall, not a slope

local function walk(label, map, from, to, strict)
    local points, cost = Path.FindSync(map, from, to, false)
    check(points, label .. ": a route")
    local worst, where = 0, nil
    local z = points[2] and points[2].z or 0
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        if a.z then z = a.z end
        local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        for d = 0, len, 2 do
            local f = len > 0 and d / len or 0
            local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
            local best
            for _, s in ipairs(api.SurfacesAt(map, x, y) or {}) do
                if not best or math.abs(s.z - z) < math.abs(best - z) then best = s.z end
            end
            if best then
                if best - z > worst then worst, where = best - z, ("%.0f, %.0f"):format(x, y) end
                z = best
            end
        end
    end
    -- Sampled along the exact line, while a route steps through whole 8-yard cells: near a cell edge this can show a
    -- jump the route itself doesn't take, so only the confirmed case is held to it; the rest are reported.
    if strict then
        check(worst <= MAX_RISE, ("%s: climbs %.0f yards at once at %s"):format(label, worst, tostring(where)))
    end
    print(("climb: %s: %.0f yd, steepest rise %.1f yd at %s"):format(label, cost, worst, tostring(where)))
    return cost
end

local org = walk("Orgrimmar, Valley of Strength -> 63.4, 45.4", 1, { x = 1661.1, y = -4420.9 }, { x = 1849.2, y = -4569.8 }, true)
check(org < 300, ("the way round the outcrop isn't a detour: %.0f yd (254 over it)"):format(org))
walk("Valley of Trials -> Orgrimmar flight master", 1, { x = -598.3, y = -4410.5 }, { x = 1677.59, y = -4315.71, z = 61.17 })
walk("Valley of Trials -> Crossroads", 1, { x = -598.3, y = -4410.5 }, { x = -441.8, y = -2596.08, z = 96.06 })
