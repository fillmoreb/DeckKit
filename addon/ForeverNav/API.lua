-- ForeverNav.v1: ForeverNav's public API, for any addon.
--
-- Coordinates are UnitPosition's frame: `map` the instance map (0 Eastern Kingdoms, 1 Kalimdor, 2991 Zephras Isle),
-- x north and y west in world yards (UnitPosition returns x, y, z, map in that order).
--
--   ForeverNav.v1.SurfacesAt(map, x, y) -> { { z, kind }, ... } | nil, reason
--       The walkable surfaces at a point, lowest first: the walking map's cell there holds its base surface and, where
--       surfaces stack (a bridge over a road, a city under ruins, both ends of a lift), the floors above or below it.
--       z is the surface's height in yards (to the map's 2-yard step), kind "ground", "water" or "steep" (walkable
--       downhill only). Reasons: "nodata" (no walking map for that map), "outside" (off the map's area).
--
--   ForeverNav.v1.Walk(map, from, to, callback[, opts]) -> handle | nil, reason
--       The walking route between two points on one map: from and to are { x, y[, z] } (z picks the floor: without
--       it, the cheapest surface near the point). The search runs a little each frame (2 ms) and calls
--       callback(route) or callback(nil, reason) when done: route.points { { x, y, z }, ... } start to goal (drawn:
--       corners only), route.yards the running cost in yards (a swum yard counts 3 unless opts.waterWalking),
--       route.wet the yards over water. Reasons: "nodata", "outside", "offmesh" (a point off every surface),
--       "unreachable", "error". Searches wait out combat. handle:Cancel() drops it.
--
-- v1 only grows: new functions and fields may appear, nothing is renamed or removed.
local _, ns = ...

local Grid = ns.PathGrid

local KIND = { [1] = "ground", [2] = "water", [3] = "steep" }

local v1 = {}

function v1.GetVersion()
    return 1, 0
end

function v1.SurfacesAt(map, x, y)
    if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil, "invalid" end
    local st = Grid.State(map)
    if not st then return nil, "nodata" end
    local k, lc = Grid.locate(st, x, y)
    if not k then return nil, "outside" end
    -- Decoded whole in this frame (Quiet): a caller outside a search must never be paused by the decoder's slicing.
    local val = Grid.Quiet(Grid.grid, st, k)
    if not val then return nil, "nodata" end
    local z, at = st.z[k], st.at[k]
    local out = {}
    if val[lc + 1] ~= 0 then
        out[#out + 1] = { z = z[lc + 1], kind = KIND[val[lc + 1]] or "ground" }
    end
    local node = at and at[-(lc + 1)]
    while node and at[node + 1] == lc do
        out[#out + 1] = { z = z[node + 1], kind = KIND[val[node + 1]] or "ground" }
        node = node + 1
    end
    table.sort(out, function(a, b) return a.z < b.z end)
    return out
end

local Path = ns.Path

local function point(p)
    return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
        and { x = p.x, y = p.y, z = type(p.z) == "number" and p.z or nil } or nil
end

function v1.Walk(map, from, to, callback, opts)
    local a, b = point(from), point(to)
    if type(map) ~= "number" or not a or not b or type(callback) ~= "function" then return nil, "invalid" end
    if not Grid.State(map) then return nil, "nodata" end
    local job = Path.Find(map, a, b, function(points, cost)
        if not points then
            callback(nil, cost)
            return
        end
        local route = { yards = cost, wet = points.wet or 0, points = {} }
        for i, p in ipairs(points) do route.points[i] = { x = p.x, y = p.y, z = p.z } end
        callback(route)
    end, opts and opts.waterWalking or false)
    return { Cancel = function() Path.Cancel(job) end }
end

ForeverNav.v1 = setmetatable({}, { __index = v1, __newindex = function() error("ForeverNav.v1 is read-only", 2) end })
