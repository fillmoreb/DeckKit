-- WayPad: controller-first waypoints for WoW: Forever.
--
--   Core.lua     waypoint store, position math, arrival, the update ticker
--   Arrow.lua    the floating arrow (no panel)
--   Pins.lua     world map and minimap pins
--   Editor.lua   "Add waypoint": six digit slots dialed with the d-pad
--   Manager.lua  the waypoint list: make active, edit, remove, clear all
--   Slash.lua    /waypad and /way
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff4fc3f7WayPad|r") -- Print, On, Input, Window
ns.ARRIVE_YARDS = 10
ns.ARRIVED_SHOWN = 2.5

local db
ns.points = {} -- { mapID, x, y, label } with x, y in 0..1

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function Readable(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end
ns.Readable = Readable

function ns.MapInfo(mapID)
    if not (mapID and C_Map and C_Map.GetMapInfo) then return end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" then return info end
end

function ns.MapName(mapID)
    local info = ns.MapInfo(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

function ns.Coords(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

function ns.Describe(p)
    local s = ns.Coords(p.x, p.y) .. " in " .. ns.MapName(p.mapID)
    if p.label then s = p.label .. " (" .. s .. ")" end
    return s
end

-- The player's map and position (0..1), the same ones Blizzard's coordinates use.
function ns.PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not Readable(mapID) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if not Readable(x) or not Readable(y) or (x == 0 and y == 0) then return end
    return mapID, x, y
end

-- World position in yards: world X runs north, world Y runs west.
function ns.WorldPosition(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not Readable(continent) or not pos then return end
    local north, west = pos:GetXY()
    if not Readable(north) or not Readable(west) then return end
    return continent, north, west
end

-- A point of one map on another map: a parent (zone -> continent) or a child (zone -> city).
function ns.TranslateToMap(fromMap, x, y, toMap)
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

function ns.Facing()
    if not GetPlayerFacing then return end
    local ok, f = pcall(GetPlayerFacing)
    if ok and Readable(f) then return f end
end

local function WorldOf(p)
    if not p.continent then
        p.continent, p.north, p.west = ns.WorldPosition(p.mapID, p.x, p.y)
    end
    return p.continent, p.north, p.west
end

------------------------------------------------------------------------
-- Guidance: where a point is, relative to the player
--   state: "ok", "far" (another continent), "nopos" (can't read position here)
--   yards, bearing (radians counter-clockwise from north), angle (counter-clockwise from facing)
------------------------------------------------------------------------

local player = {} -- refreshed once per tick

local function ReadPlayer()
    player.mapID, player.x, player.y = ns.PlayerPosition()
    player.continent, player.north, player.west = nil, nil, nil
    if player.mapID then
        player.continent, player.north, player.west = ns.WorldPosition(player.mapID, player.x, player.y)
    end
    player.facing = ns.Facing()
end

function ns.Guide(p)
    local g = { point = p }
    if not player.continent then
        g.state = "nopos"
        return g
    end
    local continent, north, west = WorldOf(p)
    if not continent or continent ~= player.continent then
        g.state = "far"
        return g
    end
    local dN, dW = north - player.north, west - player.west
    g.dN, g.dW = dN, dW
    g.yards = math.sqrt(dN * dN + dW * dW)
    g.bearing = math.atan2(dW, dN)
    if player.facing then g.angle = g.bearing - player.facing end
    g.state = "ok"
    return g
end

ns.player = player

------------------------------------------------------------------------
-- The store
------------------------------------------------------------------------

local function Save()
    local out = {}
    for i, p in ipairs(ns.points) do
        out[i] = { mapID = p.mapID, x = p.x, y = p.y, label = p.label }
    end
    db.points = out
    db.active = ns.active
end

function ns.Active()
    return ns.active and ns.points[ns.active]
end

function ns.Changed()
    Save()
    if ns.Pins then ns.Pins.Refresh() end
    if ns.Manager then ns.Manager.Refresh() end
    ns.StartTicker()
end

function ns.Add(mapID, x, y, label)
    table.insert(ns.points, { mapID = mapID, x = x, y = y, label = label })
    ns.active = #ns.points
    ns.arrival = nil
    if ns.HandOff then ns.HandOff.Added(ns.points[ns.active]) end
    ns.Changed()
    return ns.points[ns.active]
end

function ns.Edit(i, x, y)
    local p = ns.points[i]
    if not p then return end
    local old = { mapID = p.mapID, x = p.x, y = p.y, label = p.label }
    p.x, p.y, p.continent = x, y, nil
    if ns.HandOff then ns.HandOff.Edited(old, p, ns.active == i) end
    ns.Changed()
end

function ns.SetActive(i)
    if ns.points[i] then
        ns.active = i
        if ns.HandOff then ns.HandOff.Activated(ns.points[i]) end
        ns.Changed()
    end
end

function ns.Remove(i)
    if not ns.points[i] then return end
    if ns.HandOff then ns.HandOff.Removed(ns.points[i]) end
    table.remove(ns.points, i)
    if ns.active == i then
        ns.active = #ns.points > 0 and #ns.points or nil -- the newest left
    elseif ns.active and ns.active > i then
        ns.active = ns.active - 1
    end
    ns.Changed()
end

function ns.ClearAll()
    if ns.HandOff then for _, p in ipairs(ns.points) do ns.HandOff.Removed(p) end end
    wipe(ns.points)
    ns.active = nil
    ns.Changed()
end

------------------------------------------------------------------------
-- The ticker: 20 times a second while there's something to show
------------------------------------------------------------------------

local ticker
local debugNext = 0

local function PlayArrival()
    local kit = SOUNDKIT and (SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON or SOUNDKIT.MAP_PING) or 3175
    PlaySound(kit, "Master", false)
end

local function DebugLine(g)
    local function f(v) return Readable(v) and string.format("%.3f", v) or tostring(v) end
    local view = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    ns.Print(string.format("me map=%s pos=%s,%s world=%s/%s,%s facing=%s | target %s | yd=%s bearing=%s angle=%s | view=%s mm=%s rotate=%s zoom=%s",
        tostring(player.mapID), f(player.x), f(player.y), tostring(player.continent), f(player.north), f(player.west),
        f(player.facing), g and g.point and ns.Describe(g.point) or "none", f(g and g.yards), f(g and g.bearing),
        f(g and g.angle), f(view), f(Minimap and Minimap:GetWidth()), tostring(GetCVar("rotateMinimap")),
        tostring(Minimap and Minimap:GetZoom())))
end

local inTick

local function TickBody()
    ReadPlayer()
    -- Another waypoint addon has the waypoints: it does the arrow and arrival, not WayPad.
    local handedOff = ns.HandOff and ns.HandOff.Active()
    local p = not handedOff and ns.Active()
    local g = p and ns.Guide(p)
    if g and g.state == "ok" and g.yards <= ns.ARRIVE_YARDS then
        PlayArrival()
        ns.arrival = { label = p.label or ns.Coords(p.x, p.y), untilTime = GetTime() + ns.ARRIVED_SHOWN }
        ns.Remove(ns.active)
        p = ns.Active()
        g = p and ns.Guide(p)
    end
    if ns.arrival and GetTime() > ns.arrival.untilTime then ns.arrival = nil end
    if ns.Arrow then ns.Arrow.Update(g) end
    if ns.Pins then ns.Pins.UpdateMinimap() end
    if ns.debug and GetTime() >= debugNext then
        debugNext = GetTime() + 1
        DebugLine(g)
    end
    if (#ns.points == 0 or handedOff) and not ns.arrival and not ns.debug and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Tick()
    if inTick then return end
    inTick = true
    local ok, err = pcall(TickBody)
    inTick = false
    if not ok then geterrorhandler()(err) end
end

function ns.StartTicker()
    if not ticker and (#ns.points > 0 or ns.arrival or ns.debug) then
        ticker = C_Timer.NewTicker(0.05, Tick)
    end
    Tick()
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    WayPadDB = WayPadDB or {}
    db = WayPadDB
    ns.db = db
    for _, p in ipairs(db.points or {}) do
        if type(p.mapID) == "number" and type(p.x) == "number" and type(p.y) == "number" then
            table.insert(ns.points, { mapID = p.mapID, x = p.x, y = p.y, label = p.label })
        end
    end
    ns.active = ns.points[db.active or 0] and db.active or (#ns.points > 0 and #ns.points or nil)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    ns.StartTicker()
    if ns.Pins then ns.Pins.Refresh() end
end)

BINDING_HEADER_WAYPAD = "WayPad"
BINDING_NAME_WAYPAD_ADD = "Add Waypoint"
BINDING_NAME_WAYPAD_MANAGE = "Manage Waypoints"
