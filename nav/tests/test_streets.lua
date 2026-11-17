-- Recorded streets (Streets.lua): cells a player walks become roads, and in a capital a walk keeps to them. Here a
-- "street" is recorded the long way round, through a point well off the shortest line, and the city walk must take
-- it; outside a city the same street changes nothing much.
local Path, Grid, Streets = ns.Path, ns.PathGrid, ForeverNav.v1.Streets
local st = Grid.State(1)
local FROM, TO = { x = 1661.1, y = -4420.9 }, { x = 1849.2, y = -4569.8 } -- Ben's Orgrimmar trip

local function near(points, p, yards)
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        for d = 0, len, 2 do
            local f = len > 0 and d / len or 0
            local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
            if (x - p.x) ^ 2 + (y - p.y) ^ 2 <= yards * yards then return true end
        end
    end
    return false
end

-- Walk the cells of a route into the recording, as Streets' sampler would.
local function record(points)
    ForeverNavDB = ForeverNavDB or {}
    ForeverNavDB.streets = ForeverNavDB.streets or {}
    ForeverNavDB.streets[1] = ForeverNavDB.streets[1] or {}
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        for d = 0, len, 2 do
            local f = len > 0 and d / len or 0
            local gx = math.floor((a.x + (b.x - a.x) * f - st.x0) / st.cs)
            local gy = math.floor((a.y + (b.y - a.y) * f - st.y0) / st.cs)
            ForeverNavDB.streets[1][gx * 65536 + gy] = true
        end
    end
end

-- A point off the shortest line that a walk can pass through: the street's bend.
local direct = Path.FindSync(1, FROM, TO, false, ns.RoadsProfile)
check(direct, "a walk before any streets")
local bend
for _, c in ipairs({ { 1700, -4380 }, { 1740, -4420 }, { 1620, -4500 }, { 1780, -4470 }, { 1720, -4560 } }) do
    local p = { x = c[1], y = c[2] }
    if not near(direct, p, 30) and Path.FindSync(1, FROM, p, false) and Path.FindSync(1, p, TO, false) then
        bend = p
        break
    end
end
check(bend, "a walkable bend well off the shortest walk")
local leg1 = Path.FindSync(1, FROM, bend, false)
local leg2 = Path.FindSync(1, bend, TO, false)
record(leg1)
record(leg2)
check(Streets.Count(1) > 10, "the street's cells are recorded: " .. Streets.Count(1))
Path.ClearCaches()

local walk, cost = Path.FindSync(1, FROM, TO, false, ns.RoadsProfile)
check(walk, "a walk with the street")
check(near(walk, bend, 12), ("the city walk takes the recorded street round by %.0f, %.0f"):format(bend.x, bend.y))
print(("streets: %d cells; the walk follows them round the bend (%.0f yd)"):format(Streets.Count(1), cost))

check(Streets.Export(1):find("%[1%] = {"), "exports as a table for shipping")
Streets.Clear(1)
eq = eq or function(a, b, m) check(a == b, m) end
check(Streets.Count(1) == 0, "cleared")
local after = Path.FindSync(1, FROM, TO, false, ns.RoadsProfile)
check(not near(after, bend, 12), "once cleared, the walk is back to its own way")

-- The city weight reads each cell's road status itself: a recorded cell is road (1), the cell beside it isn't (4).
-- (A bug kept every city cell at 4, so no weight changed anything: Ben, 2026-11-17, "not weighted heavy enough".)
ForeverNavDB.streets[1] = {}
local onCell = { x = 1700, y = -4380 }
local gx, gy = math.floor((onCell.x - st.x0) / st.cs), math.floor((onCell.y - st.y0) / st.cs)
ForeverNavDB.streets[1][gx * 65536 + gy] = true
Path.ClearCaches()
check(ns.RoadsProfile.Point(1, st.x0 + (gx + 0.5) * st.cs, st.y0 + (gy + 0.5) * st.cs) == 1, "a recorded street cell weighs 1")
check(ns.RoadsProfile.Point(1, st.x0 + (gx + 3.5) * st.cs, st.y0 + (gy + 0.5) * st.cs) > 1, "a cell off it in the city weighs more")

-- Ben's own recording of Orgrimmar's road from the Valley of Strength toward the Drag (76 cells, 2026-11-17), and his
-- trip to 63.4, 45.4: the walk keeps to the street, leaving it only for the waypoint, which stands off its end.
local BEN = {
    117441095, 117506631, 117506632, 117572168, 117637704, 117703240, 117768776, 117834312, 117899848, 117965383,
    117965384, 118030919, 118096455, 118161990, 118161991, 118227526, 118293062, 118358597, 118358598, 118424133,
    118489669, 118555205, 118620741, 118620742, 118686278, 118751814, 118751815, 118817351, 118882888, 118948424,
    118948425, 119013961, 119079497, 119079498, 119145034, 119210571, 119210572, 119276108, 119276109, 119341645,
    119407180, 119407181, 119472715, 119472716, 119538250, 119538251, 119603775, 119603776, 119603777, 119603778,
    119603785, 119603786, 119669309, 119669310, 119669315, 119669316, 119669317, 119669318, 119669319, 119669320,
    119734844, 119734845, 119800379, 119800380, 119865914, 119865915, 119931450, 119996986, 120062521, 120062522,
    120128057, 120193593, 120259129, 120259130, 120324666, 120390202,
}
ForeverNavDB.streets[1] = {}
for _, k in ipairs(BEN) do ForeverNavDB.streets[1][k] = true end
Path.ClearCaches()
local centres = {}
for _, k in ipairs(BEN) do
    centres[#centres + 1] = { st.x0 + (math.floor(k / 65536) + 0.5) * st.cs, st.y0 + (k % 65536 + 0.5) * st.cs }
end
local trip = Path.FindSync(1, { x = 1545, y = -4427 }, TO, false, ns.RoadsProfile)
check(trip, "Ben's trip has a walk")
for i = 1, #trip - 1 do
    local a, b = trip[i], trip[i + 1]
    local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    for d = 0, len, 2 do
        local f = len > 0 and d / len or 0
        local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
        local off = math.huge
        for _, c in ipairs(centres) do off = math.min(off, math.sqrt((c[1] - x) ^ 2 + (c[2] - y) ^ 2)) end
        local toGoal = math.sqrt((TO.x - x) ^ 2 + (TO.y - y) ^ 2)
        check(off <= 12 or toGoal <= 60, ("Ben's trip stays on his street: %.0f yd off it at %.0f, %.0f"):format(off, x, y))
    end
end
Streets.Clear(1)
