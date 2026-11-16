-- DeckKit.Route: the active waypoint as a route, when MapzerothLib is installed. A waypoint across the world is
-- reached by legs: walk to the zeppelin tower, take the zeppelin, walk to the border, take a flight. Waypoints.lua
-- asks Leg() every tick, and then guides to the current leg's end instead of the waypoint (the compass shows the
-- step's words); arrival is still the waypoint's own. Without MapzerothLib, or with routing off in the menu, or with
-- nothing better than walking straight there, Leg() is nil and the waypoint is guided to as before.
--
-- MapzerothLib (Mapzeroth's travel data and route planner, MapzerothLib.v1) is a game-data library, one of the few
-- addons DeckKit may know about (CLAUDE.md). Planning a long route takes about 150 ms, a visible hitch, so it is
-- planned rarely: when the waypoint changes, and again only when you've clearly left the route (at most every
-- REPLAN_SECONDS, never in combat). In between, the legs are followed here: a leg is done when you reach its end.
local _, ns = ...

local R = {}
ns.Route = R

R.WALK_YARDS = 40       -- a walk is done this close to its end (a border crossing is passed at a road's width)
R.RIDE_YARDS = 120      -- a ride (boat, zeppelin, flight, portal, hearthstone...) is done this close to where it lands
R.OFF_YARDS = 200       -- on a walk, this much further from its end than the closest you've been: you left the route
R.REPLAN_SECONDS = 30

local Map = ns.Map

-- Ways of getting somewhere that you walk or fly yourself; every other method is a ride you take.
local OWN_FEET = { walk = true, fly = true }

local route       -- { key, steps = { { text, method, ride, to, board, toWorld... } }, at, best }
local lastPlan = -math.huge

local function Api()
    local lib = MapzerothLib
    return type(lib) == "table" and lib.v1 or nil
end

-- True when MapzerothLib is installed and has built its world.
function R.Available()
    local api = Api()
    return api ~= nil and api.IsReady() == true
end

function R.Enabled()
    return not (ns.db and ns.db.routeWaypoints == false)
end

function R.SetEnabled(on)
    if ns.db then ns.db.routeWaypoints = on and true or false end
    route = nil
end

local function KeyOf(p)
    return string.format("%d:%d:%.5f:%.5f", p.id or 0, p.mapID, p.x, p.y)
end

-- A step's place as a point the waypoint guidance can use (Waypoints.Guide caches its world position on it).
local function Point(pt, label)
    return pt and pt.mapID and { mapID = pt.mapID, x = pt.x, y = pt.y, label = label } or nil
end

local function Plan(p, key)
    lastPlan = GetTime()
    local api = Api()
    local planned = api.RouteTo(p.mapID, p.x, p.y, p.label)
    route = { key = key, at = 1 }
    -- No route, or nothing better than walking straight there: guide to the waypoint itself.
    if not planned or #planned.steps <= 1 then
        route.none = true
        return
    end
    route.steps = {}
    for i, s in ipairs(planned.steps) do
        local ride = not OWN_FEET[s.method]
        route.steps[i] = {
            text = s.text, method = s.method, ride = ride, seconds = s.seconds,
            to = Point(s.to, s.name),                                 -- where it ends
            board = ride and Point(s.path and s.path[1], s.text) or nil, -- where a ride starts: the dock, the portal
        }
    end
    route.seconds = planned.seconds
    if ns.Debug then ns.Debug(string.format("route: %d steps to %s", #route.steps, tostring(p.label or p.mapID))) end
end

-- Yards from the player to a point, or nil when it's on another continent or the player has no position here.
local function YardsTo(pt)
    local me = ns.Waypoints.player
    if not (pt and me.continent) then return nil end
    if not pt.continent then pt.continent, pt.north, pt.west = Map.WorldPosition(pt.mapID, pt.x, pt.y) end
    if pt.continent ~= me.continent then return nil end
    local dN, dW = pt.north - me.north, pt.west - me.west
    return math.sqrt(dN * dN + dW * dW)
end

local function Reached(step)
    local d = step.to and YardsTo(step.to)
    return d ~= nil and d <= (step.ride and R.RIDE_YARDS or R.WALK_YARDS)
end

-- Moves past every leg you've done: the furthest one whose end you're at (a shortcut skips the ones between).
local function Advance()
    for i = #route.steps, route.at, -1 do
        if Reached(route.steps[i]) then
            route.at = i + 1
            route.best = nil
            return
        end
    end
end

-- On a walk, getting much further from its end than you've been, or ending up on another continent: off the route.
local function OffRoute(step)
    if step.ride then return false end
    local d = YardsTo(step.to)
    if not d then return ns.Waypoints.player.continent ~= nil end   -- somewhere else entirely (a hearthstone, a portal)
    if not route.best or d < route.best then route.best = d end
    return d > route.best + R.OFF_YARDS
end

-- The leg to guide to for waypoint `p`, or nil to guide to `p` itself:
--   { point (where to go now, or nil when there's nothing to walk to: a hearthstone), text, method, ride,
--     index, count }
function R.Leg(p)
    if not (p and R.Enabled() and R.Available()) then
        route = nil
        return nil
    end
    local key = KeyOf(p)
    if not route or route.key ~= key then
        if InCombatLockdown() then return nil end   -- planning hitches: wait for the fight to end
        Plan(p, key)
    end
    if route.none then return nil end
    Advance()
    local step = route.steps[route.at]
    if not step then return nil end                 -- past the last leg: the waypoint itself is next
    if route.at == #route.steps and not step.ride then return nil end
    if OffRoute(step) and GetTime() - lastPlan >= R.REPLAN_SECONDS and not InCombatLockdown() then
        Plan(p, key)
        if route.none then return nil end
        step = route.steps[route.at]
        if not step or (route.at == #route.steps and not step.ride) then return nil end
    end
    return {
        point = step.ride and step.board or step.to,
        text = step.text, method = step.method, ride = step.ride,
        index = route.at, count = #route.steps,
    }
end

-- Waypoint `p`'s route, for other addons (DeckAgent tells the player how the trip goes): { seconds, steps =
-- { { text, method, seconds }, ... }, at (the step they're on) }, or nil when it has none (no MapzerothLib, routing
-- off, not planned yet, or walking straight there is the way). A waypoint just added was planned as it was added
-- (Waypoints.Add runs a tick), unless that was in combat.
function R.Summary(p)
    if not (p and route and route.key == KeyOf(p) and not route.none) then return nil end
    local out = { seconds = route.seconds, at = route.at, steps = {} }
    for i, s in ipairs(route.steps) do
        out.steps[i] = { text = s.text, method = s.method, seconds = s.seconds }
    end
    return out
end

-- Plans again on the next tick (the menu's routing toggle, a debug command).
function R.Forget()
    route = nil
end

-- The current route in words, for /deckkit route.
function R.Describe()
    if not R.Available() then return "MapzerothLib isn't loaded: waypoints are guided to directly." end
    if not R.Enabled() then return "Routing is off (Map & travel > Waypoints)." end
    if not route then return "No route (no active waypoint, or not planned yet)." end
    if route.none then return "Walking straight to the waypoint is the way." end
    local lines = { string.format("Route, %d steps:", #route.steps) }
    for i, s in ipairs(route.steps) do
        lines[#lines + 1] = string.format("%s%d. %s", i == route.at and "> " or "  ", i, s.text)
    end
    return table.concat(lines, "\n")
end

ns.AddCommand("route", function()
    for line in R.Describe():gmatch("[^\n]+") do ns.Print(line) end
end, "the active waypoint's route (MapzerothLib)")
