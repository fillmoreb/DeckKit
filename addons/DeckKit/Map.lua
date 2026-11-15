-- DeckKit.Map: where things are, for the modules that place things on maps or point at them (the
-- waypoints, MapDeck, the compass, WayPad). Every call is guarded: an API this client lacks, a map
-- that isn't there, or a value the game won't let addons read (a "secret" value, in combat or
-- instances) gives nil, never an error.
--
-- Map positions are 0..1 on a map (the numbers Blizzard's coordinates show, times 100). World
-- positions are yards on a continent: north and west, as C_Map.GetWorldPosFromMapPos gives them.
local _, ns = ...

local Map = {}
ns.Map = Map

local Readable = ns.Readable

function Map.Info(mapID)
    if not (mapID and C_Map and C_Map.GetMapInfo) then return end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" then return info end
end

function Map.Name(mapID)
    local info = Map.Info(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

-- "45.2, 62.8": a map position as Blizzard's coordinates show it.
function Map.Coords(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- A group member's (or your own) position on mapID, or nil (not on it, or not readable here).
function Map.UnitPosition(unit, mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
    if not (ok and pos) then return end
    local x, y = pos:GetXY()
    if Readable(x) and Readable(y) and (x ~= 0 or y ~= 0) then return x, y end
end

-- The map you're standing in and your position on it.
function Map.PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not Readable(mapID) then return end
    local x, y = Map.UnitPosition("player", mapID)
    if x then return mapID, x, y end
end

-- A map position in the world: its continent, and yards north and west.
function Map.WorldPosition(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not Readable(continent) or not pos then return end
    local north, west = pos:GetXY()
    if not Readable(north) or not Readable(west) then return end
    return continent, north, west
end

-- A point of one map on another map: a parent (zone -> continent) or a child (zone -> city). nil when
-- it's off that map.
function Map.Translate(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    if not (C_Map and C_Map.GetMapRectOnMap) then return end
    local tx, ty
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, fromMap, toMap)
    if ok and Readable(minX) and Readable(maxY) and maxX > minX and maxY > minY then
        tx, ty = minX + x * (maxX - minX), minY + y * (maxY - minY)
    else
        ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, toMap, fromMap)
        if ok and Readable(minX) and Readable(maxY) and maxX > minX and maxY > minY then
            tx, ty = (x - minX) / (maxX - minX), (y - minY) / (maxY - minY)
        end
    end
    if not tx or tx < 0 or tx > 1 or ty < 0 or ty > 1 then return end
    return tx, ty
end

-- The way from one map position to another, in radians counter-clockwise from north, or nil (on
-- different continents, unreadable, or the same spot).
function Map.Bearing(fromMap, fx, fy, toMap, tx, ty)
    local fc, fn, fw = Map.WorldPosition(fromMap, fx, fy)
    local tc, tn, tw = Map.WorldPosition(toMap, tx, ty)
    if not (fc and tc) or fc ~= tc then return end
    local dN, dW = tn - fn, tw - fw
    if dN == 0 and dW == 0 then return end
    return math.atan2(dW, dN)
end

-- Which way you face: radians counter-clockwise from north, or nil where the game won't say.
function Map.Facing()
    if not GetPlayerFacing then return end
    local ok, f = pcall(GetPlayerFacing)
    if ok and Readable(f) then return f end
end
