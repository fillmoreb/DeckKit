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
--       route.wet the yards over water. Roads are followed: a yard off the road counts 1.5 while the walk is chosen
--       (Shortest Path Forever's "Follow roads"), so a walk takes the road when that adds less than half again to it,
--       and doesn't hug the foot of every cliff the way the shortest line does. opts.roads = false: the shortest line. Reasons: "nodata", "outside", "offmesh" (a point off every surface),
--       "unreachable", "error". Searches wait out combat. handle:Cancel() drops it.
--
--   ForeverNav.v1.Plan(from, to[, opts]) -> plan | nil, reason
--       The quickest way from one point to another anywhere in the world, as this character: walks joined with
--       flights (between the flight points it has found), boats, zeppelins, lifts, the tram and portals, with each
--       ride's wait from the timetables. from and to are { map, x, y[, z] } (z picks the floor, as for v1.Walk). opts: name (the destination's name in the
--       steps), faction ("Horde"/"Alliance", default the player's), walkSpeed (yards a second, default the player's),
--       assumeFlights (true: every flight point counts as found), otherFaction (the other side's boats too),
--       teleports (false: leave out the Hearthstone and teleport spells; they count only when `from` is where the
--       player stands, so pass false for a plan from anywhere else).
--       plan.seconds is the whole trip; plan.legs[i] = { mode ("walk", "flight", "boat", "zeppelin", "lift",
--       "tram", "portal", "passage", "teleport"), text ("Take the zeppelin to Grom'gol", "Hearth to Orgrimmar"),
--       from and to { map, x, y },
--       seconds (the leg itself), wait (seconds waiting for a ride before it) }. A walk's time is estimated from the
--       baked walks or the straight line: v1.Walk measures one. Plans in the caller's frame (a few ms).
--       Reasons: "invalid", "no route".
--
--   ForeverNav.v1.PlanMeasured(from, to, opts, callback) -> handle | nil, reason
--       The same plan with its walks measured: v1.Plan's walk legs from `from` and to `to` are estimates (the
--       straight line, never longer than the real walk), so this plans, measures the walks that plan uses with the
--       walking search (following roads unless opts.roads is false), plans again with them, and repeats until the
--       plan it picks uses only measured walks (at most 4 rounds; plan.measured says whether it got there). A measured
--       walk that's longer can make another way the quickest, which is then measured in turn. Calls
--       callback(plan) or callback(nil, reason) with plan as v1.Plan's; takes a few seconds of frame-sliced work.
--       handle:Cancel() drops it.
--
--   ForeverNav.v1.Follow(owner, on)
--       Follow the player's floor while you need walks from where they stand (owner: your addon's name; on false to
--       stop). The client gives no height, and where surfaces stack (a city under ruins, a bridge over a road) a walk
--       from a bare x, y starts on the cheapest surface near it: a roof, a ledge, the wrong level. Followed, ForeverNav
--       keeps the surfaces the player can be on as they move (the walking map's connections rule the others out) and
--       decodes the map around them ahead of time. Shortest Path Forever's Routing/Floor.lua does the work.
--
--   ForeverNav.v1.PlayerFloor() -> z | nil
--       The height of the floor the player stands on, while followed and once it's known (nil until then, or while
--       the surfaces they may be on are on different floors). Pass it as `from.z` to v1.Walk and v1.Plan.
--
--   ForeverNav.v1.Drift() -> { count, entries, sameShard, otherShard, otherSession }
--       Whether ride sightings hold (Drift.lua): each time a ride replaced an earlier sighting of the same route, how
--       far off the old one was (entries[i].drift, seconds, against the loop's period), the time between the rides
--       (gap), and the shard and session on each side. The groups give how many and the worst drift: rides on the
--       same shard, on different shards, and in different sessions.
--
--   ForeverNav.v1.SetSharing(on), ForeverNav.v1.Sharing() -> { on, joined, shard, sightings }
--       Share ride sightings with other ForeverNav players (Share.lua; off until turned on): a ride you take tells
--       everyone on your shard where that boat is in its loop, and theirs tell you, through a hidden addon channel for
--       your faction. Plans use the shared sightings of the shard you're on. Sharing() says whether it's on, whether
--       the channel is joined, the shard you're on (nil until a creature has been seen) and how many sightings are held.
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

-- The search's hazard profile (upstream: Journey/Hazards.lua, which also steers round hostile towns and zones far
-- above your level), with nothing charged and only its Follow roads switch on.
local ROADS = {
    key = "foreverNav:roads",
    roads = true,
    Point = function() return 1 end,
    Charged = function() return false end,
    Near = function() return false end,
    Chord = function() return 1 end,
}

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
    end, opts and opts.waterWalking or false, not (opts and opts.roads == false) and ROADS or nil)
    return { Cancel = function() Path.Cancel(job) end }
end

local function place(p)
    return type(p) == "table" and type(p.map) == "number" and type(p.x) == "number" and type(p.y) == "number"
        and { map = p.map, x = p.x, y = p.y, z = type(p.z) == "number" and p.z or nil } or nil
end

-- A planner's plan as the API returns it.
local function Public(plan, options, goalName)
    local out = { seconds = (plan.arrive - options.now) / 1000, legs = {} }
    for i, leg in ipairs(plan.legs) do
        leg.next = plan.legs[i + 1]
        out.legs[i] = {
            mode = leg.mode,
            text = ns.Steps.Text(leg, goalName),
            from = { map = leg.from.map, x = leg.from.x, y = leg.from.y },
            to = { map = leg.to.map, x = leg.to.x, y = leg.to.y },
            seconds = (leg.arrive - leg.depart) / 1000,
            wait = (leg.wait or 0) / 1000,
        }
    end
    return out
end

function v1.Plan(from, to, opts)
    local a, b = place(from), place(to)
    if not a or not b then return nil, "invalid" end
    local options = ns.Context.Options(a, b, opts)
    local plan = ns.Planner.Plan(options)
    if not plan or not plan.legs or #plan.legs == 0 then return nil, "no route" end
    return Public(plan, options, opts and opts.name)
end

local MEASURE_ROUNDS = 4

local function spot(p)
    return { x = p.x, y = p.y, z = p.z }
end

function v1.PlanMeasured(from, to, opts, callback)
    local a, b = place(from), place(to)
    if not a or not b or type(callback) ~= "function" then return nil, "invalid" end
    local hazards = not (opts and opts.roads == false) and ROADS or nil
    local water = opts and opts.waterWalking or false
    local walks, rounds, jobs, cancelled = {}, 0, {}, false
    local function round()
        rounds = rounds + 1
        local options = ns.Context.Options(a, b, opts)
        options.walks = walks
        local plan = ns.Planner.Plan(options)
        if not plan or not plan.legs or #plan.legs == 0 then
            callback(nil, "no route")
            return
        end
        local pending = {}
        for _, leg in ipairs(plan.pendingWalks or {}) do
            if leg.from.map == leg.to.map then pending[#pending + 1] = leg end
        end
        if #pending == 0 or rounds >= MEASURE_ROUNDS then
            local out = Public(plan, options, opts and opts.name)
            out.measured = #pending == 0
            callback(out)
            return
        end
        local left = #pending
        jobs = {}
        for _, leg in ipairs(pending) do
            jobs[#jobs + 1] = Path.FindCost(leg.from.map, spot(leg.from), spot(leg.to), function(cost)
                if cancelled then return end
                -- Measured: its running yards, or false when there's no walk at all (the planner drops the edge).
                walks[#walks + 1] = { from = leg.from, to = leg.to, cost = type(cost) == "number" and cost or false }
                left = left - 1
                if left == 0 then round() end
            end, water, hazards)
        end
    end
    round()
    return {
        Cancel = function()
            cancelled = true
            for _, job in ipairs(jobs) do Path.Cancel(job) end
        end,
    }
end

-- Following the player's floor: sampled every FOLLOW_SECONDS after moving at least a yard, while anyone follows.
local FOLLOW_SECONDS = 0.25
local followers, followFrame = {}, nil
local lastX, lastY, lastMap, since = nil, nil, nil, 0

local function FollowTick(_, elapsed)
    since = since + elapsed
    if since < FOLLOW_SECONDS then return end
    since = 0
    local x, y, _, map = ns.JourneyPosition()
    if not (x and y and map) then
        ns.Floor.Forget()
        lastMap = nil
        return
    end
    -- Standing still with the floor known: nothing to do. Unknown (the first sample waited for its tiles to decode),
    -- sample again even without moving.
    if map == lastMap and (x - lastX) ^ 2 + (y - lastY) ^ 2 < 1 and ns.Floor.Height(map, x, y) then return end
    lastX, lastY, lastMap = x, y, map
    ns.Floor.Sample(map, x, y)
end

function v1.Follow(owner, on)
    if type(owner) ~= "string" or owner == "" then return false end
    followers[owner] = on and true or nil
    if next(followers) then
        if not followFrame and CreateFrame then
            followFrame = CreateFrame("Frame")
            followFrame:SetScript("OnUpdate", FollowTick)
        end
        if followFrame and followFrame.Show then followFrame:Show() end
    else
        if followFrame and followFrame.Hide then followFrame:Hide() end
        lastMap = nil
        ns.Floor.Forget()
    end
    return true
end

function v1.PlayerFloor()
    local x, y, _, map = ns.JourneyPosition()
    if not (x and y and map) then return nil end
    return ns.Floor.Height(map, x, y)
end

function v1.Drift()
    return ns.Drift.Summary()
end

function v1.SetSharing(on)
    ns.Share.SetOn(on)
end

function v1.Sharing()
    return ns.Share.State()
end

ForeverNav.v1 = setmetatable({}, { __index = v1, __newindex = function() error("ForeverNav.v1 is read-only", 2) end })
