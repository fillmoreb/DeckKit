-- Do sightings hold? A sighting places a route's boat in its loop, and is trusted until the next ride replaces it,
-- across sessions and characters (upstream's design). Forever moves players between layers and shards, and nothing
-- yet shows whether every one of them runs a route in step. So each time a ride replaces an earlier sighting of the
-- same route, this records how far the new loop position is from where the old sighting said it would be (the drift),
-- with the time between the two rides and the shard and session on each side. Drift near zero across shards and
-- sessions: sightings hold everywhere, and could be shared. Drift all over: they hold only where they were made.
-- ForeverNav's own; Transport/Observer.lua and Timetable.lua (upstream's) are untouched: this listens to the timetable.
--
-- Saved in ForeverNavDB.drift (the newest KEEP), read with ForeverNav.v1.Drift().
local _, ns = ...

local Drift = {}
ns.Drift = Drift

local KEEP = 200
-- A ride is recorded as soon as it proves itself and again as it ends (the observer refines it): a sighting replaced
-- within this many seconds is the same ride, not a second one to compare.
local SAME_RIDE = 600

local held = {}            -- [routeID] = { epoch, seen, shard, session }: the sighting a new ride is compared with
local session              -- this login: server time when ForeverNav loaded

local function CurrentShard()
    return (ns.Shard.Current())
end

local function Signed(ms, period)
    ms = ms % period
    return ms > period / 2 and ms - period or ms
end

local function Remember(routeID, anchor, shardHere)
    held[routeID] = { epoch = anchor.epoch, seen = anchor.seen, shard = shardHere, session = session }
end

local function Log(entry)
    local list = ns.db.drift
    list[#list + 1] = entry
    while #list > KEEP do table.remove(list, 1) end
end

-- Another player's sighting of a route (Share.lua), on their shard: how far it is from yours, when you hold one. That
-- tells as much as a ride of your own would, and every player sharing adds to it.
function Drift.Compare(routeID, anchor, theirShard)
    local mine, route = held[routeID], ns.Routes[routeID]
    if not (mine and route and route.period) then return end
    Log({
        route = routeID, kind = route.kind, source = "shared",
        drift = Signed(anchor.epoch - mine.epoch, route.period) / 1000,
        period = route.period / 1000,
        gap = anchor.seen - mine.seen,
        shard = theirShard, before = mine.shard,
        session = "shared", beforeSession = mine.session,
    })
end

-- A ride was recorded: compare each changed route with what it held.
local function Changed()
    local here = CurrentShard()
    for routeID, anchor in pairs(ns.Timetable.Anchors()) do
        local before = held[routeID]
        if not before or before.epoch ~= anchor.epoch or before.seen ~= anchor.seen then
            local route = ns.Routes[routeID]
            if before and route and route.period and anchor.seen - before.seen >= SAME_RIDE then
                Log({
                    route = routeID,
                    kind = route.kind,
                    drift = Signed(anchor.epoch - before.epoch, route.period) / 1000, -- seconds off the old sighting
                    period = route.period / 1000,
                    gap = anchor.seen - before.seen,                                  -- seconds between the rides
                    shard = here, before = before.shard,
                    session = session, beforeSession = before.session,
                })
            end
            Remember(routeID, anchor, here)
        end
    end
end

ns.Init(function()
    ns.db.drift = type(ns.db.drift) == "table" and ns.db.drift or {}
    session = GetServerTime()
    for routeID, anchor in pairs(ns.Timetable.Anchors()) do Remember(routeID, anchor, nil) end
    ns.Timetable.OnChange(Changed)
end)

-- The record and a summary: { entries = { ... }, count, sameShard = { count, worst }, otherShard, otherSession }, the
-- worst being the largest drift in seconds. "Same shard": both rides' shards known and equal.
function Drift.Summary()
    local list = ns.db.drift or {}
    local out = { entries = {}, count = #list,
        sameShard = { count = 0, worst = 0 }, otherShard = { count = 0, worst = 0 }, otherSession = { count = 0, worst = 0 } }
    for i, e in ipairs(list) do
        out.entries[i] = e
        local size = math.abs(e.drift)
        local function add(group) group.count = group.count + 1; if size > group.worst then group.worst = size end end
        if e.shard and e.before then add(e.shard == e.before and out.sameShard or out.otherShard) end
        if e.session ~= e.beforeSession then add(out.otherSession) end
    end
    return out
end
