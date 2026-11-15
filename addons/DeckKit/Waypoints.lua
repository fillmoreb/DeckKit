-- DeckKit.Waypoints: the suite's waypoints. The list (kept per character), which one is active,
-- where each is relative to you, arriving at one, and the ticker that keeps all that current. The
-- controller front end is WayPad (the d-pad editor, the list window, map pins, /way); the compass in
-- DeckHUD's status bar shows the active one; DeckAgent and MapDeck read and change the list through
-- the WayPad_* functions at the bottom, which work whether or not WayPad is installed.
--
-- Waypoints are tables { id, mapID, x, y, label } with x, y in 0..1. Ids (1-65535) stay put while the
-- list shifts, and aren't reused while the waypoint they named is still there.
--
-- Hand-off: a front end can hand the waypoints to another waypoint addon (WayPad's HandOff.lua). It
-- registers with SetHandOff; while its Active() returns something, DeckKit leaves arrival to that
-- addon and draws nothing (DrawnPoints is empty), and every change is passed to it.
--
-- Saved in DeckKitCharDB.waypoints. Waypoints from before they moved here (WayPadDB.points) are
-- brought over once, when WayPad loads (Import); WayPadDB itself is left as it was.
local _, ns = ...

local W = {}
ns.Waypoints = W

W.ARRIVE_YARDS = 10
W.ARRIVED_SHOWN = 2.5 -- seconds "Arrived" shows
W.points = {}         -- the list (this table is kept: cleared in place, never replaced)
W.active = nil        -- index of the active one
W.arrival = nil       -- { label, untilTime } just after arriving
W.guide = nil         -- the active one's guidance, refreshed each tick (see W.Guide)
W.debug = false

local db -- DeckKitCharDB

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function Readable(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end
W.Readable = Readable

function W.MapInfo(mapID)
    if not (mapID and C_Map and C_Map.GetMapInfo) then return end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" then return info end
end

function W.MapName(mapID)
    local info = W.MapInfo(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

function W.Coords(x, y)
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

function W.Describe(p)
    local s = W.Coords(p.x, p.y) .. " in " .. W.MapName(p.mapID)
    if p.label then s = p.label .. " (" .. s .. ")" end
    return s
end

-- The player's map and position (0..1), the same ones Blizzard's coordinates use.
function W.PlayerPosition()
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
function W.WorldPosition(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not Readable(continent) or not pos then return end
    local north, west = pos:GetXY()
    if not Readable(north) or not Readable(west) then return end
    return continent, north, west
end

-- A point of one map on another map: a parent (zone -> continent) or a child (zone -> city).
function W.TranslateToMap(fromMap, x, y, toMap)
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

-- Which way you face: radians counter-clockwise from north, or nil where the game won't say.
function W.Facing()
    if not GetPlayerFacing then return end
    local ok, f = pcall(GetPlayerFacing)
    if ok and Readable(f) then return f end
end

local function WorldOf(p)
    if not p.continent then
        p.continent, p.north, p.west = W.WorldPosition(p.mapID, p.x, p.y)
    end
    return p.continent, p.north, p.west
end

------------------------------------------------------------------------
-- Guidance: where a point is, relative to the player
--   state: "ok", "far" (another continent), "nopos" (can't read position here)
--   yards, bearing (radians counter-clockwise from north), angle (counter-clockwise from facing)
------------------------------------------------------------------------

local player = {} -- refreshed once per tick
W.player = player

local function ReadPlayer()
    player.mapID, player.x, player.y = W.PlayerPosition()
    player.continent, player.north, player.west = nil, nil, nil
    if player.mapID then
        player.continent, player.north, player.west = W.WorldPosition(player.mapID, player.x, player.y)
    end
    player.facing = W.Facing()
end

function W.Guide(p)
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

------------------------------------------------------------------------
-- Listeners: OnChange(fn()) after the list changes; OnTick(fn(guide)) every tick
------------------------------------------------------------------------

local changeFns, tickFns = {}, {}
function W.OnChange(fn) changeFns[#changeFns + 1] = fn end
function W.OnTick(fn) tickFns[#tickFns + 1] = fn end

local function Each(fns, ...)
    for _, fn in ipairs(fns) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

------------------------------------------------------------------------
-- Hand-off (see the header)
------------------------------------------------------------------------

local handOff
function W.SetHandOff(h) handOff = h end
local function HandedOff() return handOff and handOff.Active() end
W.HandedOff = HandedOff
local function Tell(event, ...)
    if handOff and handOff[event] then handOff[event](...) end
end

-- What DeckKit and its front ends draw: nothing while another addon has the waypoints.
function W.DrawnPoints()
    if HandedOff() then return {} end
    return W.points
end

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------

local function InUse(id)
    for _, p in ipairs(W.points) do if p.id == id then return true end end
end

local function NewId()
    local id = db and db.nextWaypointId or 1
    for _ = 1, 65535 do
        if not InUse(id) then break end
        id = id % 65535 + 1
    end
    if db then db.nextWaypointId = id % 65535 + 1 end
    return id
end

function W.Find(id)
    for i, p in ipairs(W.points) do if p.id == id then return i, p end end
end

local function Save()
    if not db then return end
    local out = {}
    for i, p in ipairs(W.points) do
        out[i] = { id = p.id, mapID = p.mapID, x = p.x, y = p.y, label = p.label }
    end
    db.waypoints = out
    db.activeWaypoint = W.active
end

function W.Active()
    return W.active and W.points[W.active]
end

local StartTicker

function W.Changed()
    Save()
    Each(changeFns)
    StartTicker()
end

function W.Add(mapID, x, y, label)
    table.insert(W.points, { id = NewId(), mapID = mapID, x = x, y = y, label = label })
    W.active = #W.points
    W.arrival = nil
    Tell("Added", W.points[W.active])
    W.Changed()
    return W.points[W.active]
end

function W.Edit(i, x, y)
    local p = W.points[i]
    if not p then return end
    local old = { mapID = p.mapID, x = p.x, y = p.y, label = p.label }
    p.x, p.y, p.continent = x, y, nil
    Tell("Edited", old, p, W.active == i)
    W.Changed()
end

function W.SetActive(i)
    if W.points[i] then
        W.active = i
        Tell("Activated", W.points[i])
        W.Changed()
    end
end

function W.Remove(i)
    if not W.points[i] then return end
    Tell("Removed", W.points[i])
    table.remove(W.points, i)
    if W.active == i then
        W.active = #W.points > 0 and #W.points or nil -- the newest left
    elseif W.active and W.active > i then
        W.active = W.active - 1
    end
    W.Changed()
end

function W.ClearAll()
    for _, p in ipairs(W.points) do Tell("Removed", p) end
    wipe(W.points)
    W.active = nil
    W.Changed()
end

-- Loads saved waypoints into the (empty) list: ones without a usable id get a fresh one.
local function Load(saved, active)
    for _, p in ipairs(saved or {}) do
        if type(p.mapID) == "number" and type(p.x) == "number" and type(p.y) == "number" then
            local id = type(p.id) == "number" and not InUse(p.id) and p.id or nil
            table.insert(W.points, { id = id or NewId(), mapID = p.mapID, x = p.x, y = p.y, label = p.label })
        end
    end
    W.active = W.points[active or 0] and active or (#W.points > 0 and #W.points or nil)
end

-- Waypoints kept by WayPad before they moved here: brought over once (nothing saved here yet).
function W.Import(saved, active, nextId)
    if not db or db.waypoints ~= nil then return end
    if type(nextId) == "number" then db.nextWaypointId = nextId end
    Load(saved, active)
    Save()
    W.Changed()
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
    ns.Print(string.format("waypoints: me map=%s pos=%s,%s world=%s/%s,%s facing=%s | target %s | yd=%s bearing=%s angle=%s",
        tostring(player.mapID), f(player.x), f(player.y), tostring(player.continent), f(player.north), f(player.west),
        f(player.facing), g and g.point and W.Describe(g.point) or "none", f(g and g.yards), f(g and g.bearing),
        f(g and g.angle)))
end

local inTick

local function TickBody()
    ReadPlayer()
    -- Another waypoint addon has the waypoints: it does the guiding and arriving.
    local handedOff = HandedOff()
    local p = not handedOff and W.Active()
    local g = p and W.Guide(p)
    if g and g.state == "ok" and g.yards <= W.ARRIVE_YARDS then
        PlayArrival()
        W.arrival = { label = p.label or W.Coords(p.x, p.y), untilTime = GetTime() + W.ARRIVED_SHOWN }
        W.Remove(W.active)
        p = W.Active()
        g = p and W.Guide(p)
    end
    if W.arrival and GetTime() > W.arrival.untilTime then W.arrival = nil end
    W.guide = g
    Each(tickFns, g)
    if W.debug and GetTime() >= debugNext then
        debugNext = GetTime() + 1
        DebugLine(g)
    end
    if (#W.points == 0 or handedOff) and not W.arrival and not W.debug and ticker then
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

StartTicker = function()
    if not ticker and (#W.points > 0 or W.arrival or W.debug) then
        ticker = C_Timer.NewTicker(0.05, Tick)
    end
    Tick()
end
W.StartTicker = StartTicker

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
    if name ~= "DeckKit" then return end
    DeckKitCharDB = DeckKitCharDB or {}
    db = DeckKitCharDB
    Load(db.waypoints, db.activeWaypoint)
    if db.waypoints ~= nil then Save() end -- ids given just now are kept (nothing saved yet: left for Import)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    StartTicker()
    Each(changeFns)
end)

------------------------------------------------------------------------
-- For other addons (names from when this lived in WayPad; kept so callers don't break)
------------------------------------------------------------------------

-- The live list and the active index.
function WayPad_GetPoints() return W.points, W.active end

-- Adds a waypoint and makes it the active one. Returns the new waypoint, or nil and why not.
function WayPad_Add(mapID, x, y, label)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil, "bad arguments" end
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, "coordinates are 0-1" end
    if not W.MapInfo(mapID) then return nil, "unknown map " .. mapID end
    if label ~= nil and type(label) ~= "string" then label = tostring(label) end
    return W.Add(mapID, x, y, label)
end

-- The waypoint with that id, or nil (removed, or never there).
function WayPad_Get(id)
    local _, p = W.Find(id)
    return p
end

-- Removes it; true if it was there.
function WayPad_Remove(id)
    local i = W.Find(id)
    if not i then return false end
    W.Remove(i)
    return true
end
