-- The walking search finds real walking routes over the synced maps: from the Valley of Trials (where Rektagho
-- stood) up into Orgrimmar to its flight master, and across the Southfury River to the Crossroads by the bridge.
local Path = ns.Path
local api = ForeverNav.v1

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function walk(label, map, from, to)
    local t0 = os.clock()
    local points, cost, expansions = Path.FindSync(map, from, to, false)
    local took = os.clock() - t0
    check(points, label .. ": a route (" .. tostring(cost) .. ")")
    local straight = dist(from, to)
    check(dist(points[1], from) < 20, label .. ": starts where asked")
    check(dist(points[#points], to) < 20, label .. ": ends where asked")
    check(cost >= straight * 0.98, ("%s: no shorter than a straight line (%.0f against %.0f)"):format(label, cost, straight))
    check(cost <= straight * 1.8, ("%s: not a wild detour (%.0f against %.0f straight)"):format(label, cost, straight))
    -- Every corner stands on a walkable surface near its height.
    for i, p in ipairs(points) do
        local surfaces = api.SurfacesAt(map, p.x, p.y) or {}
        local on = false
        for _, s in ipairs(surfaces) do
            if not p.z or math.abs(s.z - p.z) <= 6 then on = true end
        end
        check(on, ("%s: corner %d (%.0f, %.0f, z %s) is on a surface"):format(label, i, p.x, p.y, tostring(p.z)))
    end
    print(("walk: %s: %.0f yd running (%.0f straight, x%.2f), %d corners, %.0f yd over water, %d expansions, %.2f s"):format(
        label, cost, straight, cost / straight, #points, points.wet or 0, expansions, took))
    return points, cost
end

local VALLEY = { x = -598.3, y = -4410.5 }                       -- Rektagho's spot, Valley of Trials
local ORGRIMMAR_FLIGHTS = { x = 1677.59, y = -4315.71, z = 61.17 } -- ns.TaxiNodes[23]
local CROSSROADS_FLIGHTS = { x = -441.8, y = -2596.08, z = 96.06 } -- ns.TaxiNodes[25]
check(ns.TaxiNodes[23].name:find("Orgrimmar"), "taxi node 23 is Orgrimmar's")

local _, org = walk("Valley of Trials -> Orgrimmar flight master", 1, VALLEY, ORGRIMMAR_FLIGHTS)
local cross = select(1, walk("Valley of Trials -> Crossroads (over the Southfury)", 1, VALLEY, CROSSROADS_FLIGHTS))
check((cross.wet or 0) < 40, "the Crossroads walk takes the bridge, not a swim: " .. (cross.wet or 0) .. " yd wet")

-- Off the map, and between continents (a walk is one map).
local none, why = Path.FindSync(1, VALLEY, { x = 99999, y = 99999 }, false)
check(none == nil and why == "outside", "a goal off the map: outside, " .. tostring(why))

-- The public call answers through the frame-sliced jobs.
check(select(2, api.Walk(9999, VALLEY, VALLEY, function() end)) == "nodata", "v1.Walk on a map without data: nodata")
check(select(2, api.Walk(1, VALLEY, VALLEY)) == "invalid", "v1.Walk without a callback: invalid")
