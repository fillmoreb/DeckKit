-- The ride observer (Transport/Observer.lua, upstream's): riding the Orgrimmar - Grom'gol zeppelin, sampled once a
-- second by the travel clock, it works out where in its loop the zeppelin was and records that as the route's
-- sighting. A plan afterwards has that zeppelin's real departure, not the half-period average.
ns.LoadSaved()
local api, Timetable = ForeverNav.v1, ns.Timetable

local ROUTE = 285
local route = ns.Routes[ROUTE]
check(route and route.kind == "zeppelin", "route 285 is a zeppelin")
check(Timetable.Anchor(ROUTE) == nil, "no sighting yet")

-- Where the zeppelin is at a phase of its loop (ms), from its own frames { arrive, depart, map, x, y, crossing, z }.
local function At(phase)
    local frames = route.frames
    for i = 1, #frames - 1 do
        local a, b = frames[i], frames[i + 1]
        if phase >= a[1] and phase <= a[2] then return a[3], a[4], a[5] end
        if phase > a[2] and phase < b[1] and a[3] == b[3] and not a[6] then
            local t = (phase - a[2]) / (b[1] - a[2])
            return a[3], a[4] + (b[4] - a[4]) * t, a[5] + (b[5] - a[5]) * t
        end
    end
end

-- An invented schedule: the zeppelin's loop was at 0 ms at server time EPOCH.
local EPOCH = 1794700000000 + 123456
local clock = EPOCH
ns.NowMs = function() return clock end
GetServerTime = function() return math.floor(clock / 1000) end

-- Board in Orgrimmar (the stop on Kalimdor) and ride to Grom'gol, a sample a second.
local board, alight
for _, stop in ipairs(route.stops) do
    if ns.Docks[stop.dock].map == 1 then board = stop else alight = stop end
end
check(board and alight, "the route stops on both continents")
local samples = 0
-- The ride may run past the end of the loop (Orgrimmar's departure later in it than Grom'gol's arrival).
local arrive = alight.arrive < board.depart and alight.arrive + route.period or alight.arrive
for phase = board.depart, arrive, 1000 do
    clock = EPOCH + phase
    local map, x, y = At(phase % route.period)
    if map then
        PLAYER = { map = map, x = x, y = y }
        ns.TravelTick()
        samples = samples + 1
    end
end
-- Off at Grom'gol and standing there: the ride ends after RIDE_GAP (30 s) without moving, and is recorded.
for _ = 1, 40 do
    clock = clock + 1000
    ns.TravelTick()
end
check(samples > 30, "a ride's worth of samples: " .. samples)

local anchor = Timetable.Anchor(ROUTE)
check(anchor, "the ride was recorded as the zeppelin's sighting")
local off = (anchor.epoch - EPOCH) % route.period
off = math.min(off, route.period - off)
check(off <= 3000, ("its loop is placed within 3 s of the truth: %.1f s off"):format(off / 1000))
print(("ride: %d samples on the Orgrimmar - Grom'gol zeppelin, sighting %.1f s off the true schedule"):format(samples,
    off / 1000))

-- Planning now: the zeppelin's wait is its real next departure, no longer half its period.
local VALLEY, SENTINEL_HILL = { map = 1, x = -598.3, y = -4410.5 }, { map = 0, x = -10628.89, y = 1036.68 }
local plan = assert(api.Plan(VALLEY, SENTINEL_HILL, { faction = "Horde", teleports = false }))
local zeppelin
for _, leg in ipairs(plan.legs) do if leg.mode == "zeppelin" then zeppelin = leg end end
check(zeppelin, "the plan still rides the zeppelin")
check(math.abs(zeppelin.wait - route.period / 2000) > 1, ("its wait is the schedule's, not half the period: %.0f s"):format(
    zeppelin.wait))
-- And it's the true one: the walk there ends at some phase; the wait runs to the next departure from Orgrimmar.
local reach = (clock + plan.legs[1].seconds * 1000 - EPOCH) % route.period
local toDepart = (board.depart - reach) % route.period
check(math.abs(zeppelin.wait * 1000 - toDepart) <= 3000, ("the wait matches the schedule: %.0f s against %.0f s"):format(
    zeppelin.wait, toDepart / 1000))
print(("ride: after the sighting, the zeppelin's wait is %.0f s (half its period would be %.0f s)"):format(zeppelin.wait,
    route.period / 2000))
