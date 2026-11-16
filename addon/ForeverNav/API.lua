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

ForeverNav.v1 = setmetatable({}, { __index = v1, __newindex = function() error("ForeverNav.v1 is read-only", 2) end })
