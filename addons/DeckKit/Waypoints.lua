-- DeckKit.Waypoints: the suite's waypoints. The list (kept per character), which one is active,
-- where each is relative to you, arriving at one, and the ticker that keeps all that current. The
-- controller front end is WayPad (the d-pad editor, the list window, map pins, /way); the compass in
-- DeckHUD's status bar shows the active one; DeckAgent and MapDeck read and change the list through
-- the WayPad_* functions at the bottom, which work whether or not WayPad is installed.
--
-- Waypoints are tables { id, mapID, x, y, label, behind } with x, y in 0..1 (behind: see W.Add). Ids (1-65535) stay put while the
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

local Map = ns.Map
local Readable = ns.Readable

-- "Name (45.2, 62.8 in Elwynn Forest)": a waypoint in words.
function W.Describe(p)
    local s = Map.Coords(p.x, p.y) .. " in " .. Map.Name(p.mapID)
    if p.label then s = p.label .. " (" .. s .. ")" end
    return s
end

local function WorldOf(p)
    if not p.continent then
        p.continent, p.north, p.west = Map.WorldPosition(p.mapID, p.x, p.y)
    end
    return p.continent, p.north, p.west
end

------------------------------------------------------------------------
-- Guidance: where a point is, relative to the player
--   state: "ok", "far" (another continent), "nopos" (can't read position here)
--   yards, bearing (radians counter-clockwise from north), angle (counter-clockwise from facing)
--   steer ({ yards, bearing }: the next corner of the walk there, when there is one), eta (seconds to the waypoint)
--   and legEta (seconds to this leg's end), see Steer
-- W.guide, what the displays show, is the active waypoint's; or, while it has a route (Route.lua, ForeverNav), the
-- current leg's: its point is where that leg goes, `leg` says what it is ({ text, method, ride, index, count }) and
-- `goal` is the waypoint's own guidance. Arriving is always the waypoint's.
------------------------------------------------------------------------

local player = {} -- refreshed once per tick
W.player = player

local function ReadPlayer()
    player.mapID, player.x, player.y = Map.PlayerPosition()
    player.continent, player.north, player.west = nil, nil, nil
    if player.mapID then
        player.continent, player.north, player.west = Map.WorldPosition(player.mapID, player.x, player.y)
    end
    player.facing = Map.Facing()
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
        out[i] = { id = p.id, mapID = p.mapID, x = p.x, y = p.y, label = p.label, behind = p.behind }
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

-- behind: a waypoint that stays behind the player's own (the leveling guide's): it's only made active when
-- nothing else is, and when the active one goes, the player's own are picked before it.
function W.Add(mapID, x, y, label, behind)
    table.insert(W.points, { id = NewId(), mapID = mapID, x = x, y = y, label = label, behind = behind or nil })
    local p = W.points[#W.points]
    if not (behind and W.active) then
        W.active = #W.points
        W.arrival = nil
    end
    Tell("Added", p)
    W.Changed()
    return p
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
        W.active = #W.points > 0 and #W.points or nil -- the newest left, the player's own before one kept behind
        for j = #W.points, 1, -1 do
            if not W.points[j].behind then W.active = j break end
        end
        if W.active then Tell("Activated", W.points[W.active]) end -- a hand-off target points at it too
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
            table.insert(W.points, { id = id or NewId(), mapID = p.mapID, x = p.x, y = p.y, label = p.label,
                                     behind = p.behind == true or nil })
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
    local function f(v) return type(v) == "number" and Readable(v) and string.format("%.3f", v) or tostring(v) end
    ns.Print(string.format("waypoints: me map=%s pos=%s,%s world=%s/%s,%s facing=%s | target %s | yd=%s bearing=%s angle=%s",
        tostring(player.mapID), f(player.x), f(player.y), tostring(player.continent), f(player.north), f(player.west),
        f(player.facing), g and g.point and W.Describe(g.point) or "none", f(g and g.yards), f(g and g.bearing),
        f(g and g.angle)))
end

local inTick

-- The compass's view of the guidance: `steer` ({ bearing, yards }), the next corner of the walk to it, so the pin
-- follows the path rather than the straight line; and `eta`, seconds to the waypoint at your run speed (mounts
-- included): the walk left along the path, plus the later legs of a route. Without a walk: the straight line.
local function Steer(g)
    if not (g and g.state == "ok") then return end
    local speed = select(2, GetUnitSpeed("player"))
    if not speed or speed <= 0 then speed = 7 end
    local steer, left = nil, g.yards
    if ns.Route and ns.Route.Progress then
        local s, l = ns.Route.Progress(player, g.point)
        if s then
            steer, left = s, l
            local dN, dW = s.north - player.north, s.west - player.west
            g.steer = { yards = math.sqrt(dN * dN + dW * dW), bearing = math.atan2(dW, dN) }
        end
    end
    -- legEta: this leg alone (on foot: the walk left; a ride: its planned wait and trip).
    g.legEta = left / speed
    if g.leg and g.leg.ride then
        g.legEta = ns.Route.CurrentSeconds() or g.legEta
        g.ride = ns.Route.CurrentRide() -- { departIn, arriveIn, guess }
        -- Aboard and matched (ForeverNav's ride observer): the timetable's own arrival, live.
        local aboard = ns.Route.Riding and ns.Route.Riding()
        if g.ride and aboard and aboard.arriveIn then
            g.ride = { departIn = 0, arriveIn = aboard.arriveIn, guess = false, aboard = true }
            g.legEta = aboard.arriveIn
        end
    end
    g.eta = g.legEta + (g.leg and ns.Route.LaterSeconds() or 0)
end

-- Seconds as the compass shows them: "45s", "3:05", "1h 12m".
function W.FormatETA(sec)
    if not sec then return "" end
    sec = math.floor(sec + 0.5)
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then return string.format("%d:%02d", sec / 60, sec % 60) end
    return string.format("%dh %02dm", sec / 3600, (sec % 3600) / 60)
end

local function TickBody()
    ReadPlayer()
    -- Another waypoint addon has the waypoints: it does the guiding and arriving.
    local handedOff = HandedOff()
    local p = not handedOff and W.Active()
    local g = p and W.Guide(p)
    if g and g.state == "ok" and g.yards <= W.ARRIVE_YARDS then
        PlayArrival()
        W.arrival = { label = p.label or Map.Coords(p.x, p.y), untilTime = GetTime() + W.ARRIVED_SHOWN }
        W.Remove(W.active)
        p = W.Active()
        g = p and W.Guide(p)
    end
    if W.arrival and GetTime() > W.arrival.untilTime then W.arrival = nil end
    -- A waypoint across the world: guide to the route's current leg instead (Route.lua).
    local leg = p and ns.Route and ns.Route.Leg(p)
    if leg then
        local lg = leg.point and W.Guide(leg.point) or { state = "none" }
        lg.leg, lg.goal = leg, g
        g = lg
    end
    W.guide = g
    if ns.Route then ns.Route.UpdateWalk(g) end -- the path on foot to it, for the peek map (ForeverNav)
    Steer(g)
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
    if not Map.Info(mapID) then return nil, "unknown map " .. mapID end
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
