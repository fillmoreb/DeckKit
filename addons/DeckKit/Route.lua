-- DeckKit.Route: the active waypoint as a route, when ForeverNav is installed. A waypoint across the world is reached
-- by legs: walk to the zeppelin tower, take the zeppelin, walk to the border, take a flight. Waypoints.lua asks Leg()
-- every tick, and then guides to the current leg's end instead of the waypoint (the compass shows the step's words);
-- arrival is still the waypoint's own. Without ForeverNav, or with routing off in the menu, or with nothing better
-- than walking straight there, Leg() is nil and the waypoint is guided to as before. Walk() is the path on foot to
-- where the guidance points, for the minimap and the peek map.
--
-- ForeverNav (our GPL routing library, ForeverNav.v1: Shortest Path Forever's walking maps, timetables and planner)
-- is a game-data library DeckKit may use (CLAUDE.md). A plan takes a few ms (16 in game for Durotar to Westfall), so
-- it's planned when the waypoint changes and again when you've clearly left the route (at most every
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
    local nav = ForeverNav
    return type(nav) == "table" and type(nav.v1) == "table" and nav.v1.Plan and nav.v1 or nil
end

-- True when ForeverNav is installed.
function R.Available()
    return Api() ~= nil
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

-- A plan's place ({ map, x, y }: continent and world yards) as a point the waypoint guidance can use: its world
-- position is set already (Waypoints.Guide reads it), and its map is the one it's best shown on.
local function Point(pt, label, fallbackMap)
    if not pt then return nil end
    local mapID, x, y = Map.FromWorld(pt.map, pt.x, pt.y)
    return { mapID = mapID or fallbackMap, x = x or 0.5, y = y or 0.5, label = label,
        continent = pt.map, north = pt.x, west = pt.y }
end

local function Plan(p, key)
    lastPlan = GetTime()
    route = { key = key, at = 1, none = true }
    local me = ns.Waypoints.player
    local continent, north, west = Map.WorldPosition(p.mapID, p.x, p.y)
    if not (me.continent and continent) then return end
    local planned = Api().Plan({ map = me.continent, x = me.north, y = me.west }, { map = continent, x = north, y = west },
        { name = p.label })
    -- No route, or nothing better than walking straight there: guide to the waypoint itself.
    if not planned or #planned.legs <= 1 then return end
    route.none = nil
    route.steps = {}
    for i, leg in ipairs(planned.legs) do
        local ride = not OWN_FEET[leg.mode]
        route.steps[i] = {
            text = leg.text, method = leg.mode, ride = ride, seconds = leg.seconds + leg.wait,
            to = Point(leg.to, leg.text, p.mapID),                       -- where it ends
            board = ride and Point(leg.from, leg.text, p.mapID) or nil,  -- where a ride starts: the dock, the portal
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

------------------------------------------------------------------------
-- The walk: the path on foot to where the guidance points now (the current leg's end, or the waypoint itself), from
-- ForeverNav (ForeverNav.v1.Walk: walking routes over the real terrain, Shortest Path Forever's maps). MapDeck draws it
-- on the peek map. A walk is asked for when the target changes, and again when you've strayed OFF_PATH_YARDS from it
-- (at most every WALK_AGAIN_SECONDS); never in combat. The search itself runs a little each frame inside ForeverNav.
------------------------------------------------------------------------

R.OFF_PATH_YARDS = 40
R.WALK_AGAIN_SECONDS = 5

local walk          -- { key, continent, points = { { x = north, y = west }, ... }, next, yards, at } once found
local walking       -- the search under way: { key, handle }

local function NavApi()
    local nav = ForeverNav
    return type(nav) == "table" and type(nav.v1) == "table" and nav.v1.Walk and nav.v1 or nil
end

-- Follow roads (Map & travel > Waypoints, on by default): the walk keeps to roads where that costs less than half
-- again, which is safer while levelling; off, the shortest line, cliffs and all.
function R.FollowRoads()
    return not (ns.db and ns.db.walkRoads == false)
end

local function DropWalk()
    if walking and walking.handle then walking.handle.Cancel() end
    walk, walking = nil, nil
end

-- Yards from the player to the path, and the corner after the nearest stretch of it (the next one to walk to).
local function OnPath(points, me)
    local best, after = math.huge, 2
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local abN, abW = b.x - a.x, b.y - a.y
        local len2 = abN * abN + abW * abW
        local t = len2 > 0 and (((me.north - a.x) * abN + (me.west - a.y) * abW) / len2) or 0
        t = t < 0 and 0 or t > 1 and 1 or t
        local dN, dW = a.x + abN * t - me.north, a.y + abW * t - me.west
        local d = math.sqrt(dN * dN + dW * dW)
        if d < best then best, after = d, i + 1 end
    end
    return best, after
end

-- Called with the guidance every tick (Waypoints.lua): keeps the walk to its target current.
function R.UpdateWalk(g)
    local api = NavApi()
    local target = R.Enabled() and api and g and g.state == "ok" and g.point
    local me = ns.Waypoints.player
    if not (target and target.continent and me.continent == target.continent) then
        DropWalk()
        return
    end
    local roads = R.FollowRoads()
    local key = string.format("%d:%.0f:%.0f:%s", target.continent, target.north, target.west, roads and "r" or "")
    local again = false
    if walk and walk.key == key then
        local off, after = OnPath(walk.points, me)
        walk.next = after
        again = off > R.OFF_PATH_YARDS and GetTime() - walk.at >= R.WALK_AGAIN_SECONDS
        if not again then return end
    end
    -- A search for this target is under way (a walk takes a few seconds of frame-sliced work): let it finish.
    -- Restarting it every tick while you're off the path meant none ever did.
    if walking and walking.key == key then return end
    if InCombatLockdown() then return end
    if walking and walking.handle then walking.handle.Cancel() end
    local asked = { key = key }
    walking = asked
    asked.handle = api.Walk(me.continent, { x = me.north, y = me.west }, { x = target.north, y = target.west },
        function(route)
            if walking ~= asked then return end                             -- a newer ask replaced this one
            walking = nil
            if not route or #route.points < 2 then
                walk = nil
                return
            end
            walk = { key = key, continent = me.continent, points = route.points, next = 2, yards = route.yards,
                at = GetTime() }
        end, { roads = roads })
    if not asked.handle then walking = nil end
end

function R.SetFollowRoads(on)
    if ns.db then ns.db.walkRoads = on and true or false end
    DropWalk() -- walked again on the next tick, the new way
end

-- The walk for drawing, or nil: { continent, points = { { x = north, y = west }, ... } start to goal, next (the index
-- of the corner after where you are: the ones before it are behind you) }.
function R.Walk()
    return walk
end

-- Waypoint `p`'s route, for other addons (DeckAgent tells the player how the trip goes): { seconds, steps =
-- { { text, method, seconds }, ... }, at (the step they're on) }, or nil when it has none (no ForeverNav, routing
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
    if not R.Available() then return "ForeverNav isn't loaded: waypoints are guided to directly." end
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
end, "the active waypoint's route (ForeverNav)")
