-- Fixed trips with known answers, across the kinds of travel the planner joins: the safety net for a data sync or a
-- ported fix (PLAN.md step 6). Each says which legs the trip must take; times are left to the data.
--   Undercity:     from the ruins of Lordaeron down to the lower ring takes a lift down.
--   Thunder Bluff: from Mulgore's plain up to the flight master on the mesa takes a lift up.
--   Deeprun Tram:  Alliance, Ironforge to Stormwind with no flight point found, rides the tram.
--   Flights:       Horde, the Crossroads to Orgrimmar, walks with no flight point found and flies with them all.
ns.LoadSaved()
local api = ForeverNav.v1

local frames = {}
ns.Path.after = function(fn) frames[#frames + 1] = fn end
-- The measured plan, with the frame-sliced walking searches run here by hand.
local function measured(label, from, to, opts)
    local got
    local handle = api.PlanMeasured(from, to, opts, function(p, why) got = p or why end)
    check(handle, label .. ": a measured plan starts")
    local spins = 0
    while got == nil and #frames > 0 and spins < 400000 do
        table.remove(frames, 1)()
        spins = spins + 1
    end
    check(type(got) == "table", label .. ": a plan (" .. tostring(got) .. ")")
    return got
end

local function modes(plan)
    local out = {}
    for i, leg in ipairs(plan.legs) do out[i] = leg.mode end
    return table.concat(out, ",")
end

local function report(label, plan)
    local steps = {}
    for i, leg in ipairs(plan.legs) do steps[i] = leg.text end
    print(("routes: %s: %.0f s, %s"):format(label, plan.seconds, table.concat(steps, " / ")))
end

local function has(plan, mode)
    for _, leg in ipairs(plan.legs) do if leg.mode == mode then return leg end end
end

-- Undercity: the west lift's top landing (in the ruins) to beside the east lift's bottom (the lower ring).
do
    local top, bottom = ns.Docks[1009], ns.Docks[1012]
    check(top.site:find("Undercity") and top.name == "Top" and bottom.name == "Bottom", "Undercity's lifts")
    local plan = measured("Undercity", { map = 0, x = top.x + 12, y = top.y, z = top.z },
        { map = 0, x = bottom.x - 14, y = bottom.y, z = bottom.z }, { faction = "Horde", teleports = false })
    local lift = has(plan, "lift")
    check(lift, "Undercity: down from the ruins takes a lift: " .. modes(plan))
    check(lift.text == "Take the lift down", "Undercity: the lift goes down: " .. lift.text)
    report("Undercity, ruins to the lower ring", plan)
end

-- Thunder Bluff: beside the west lift's bottom landing (Mulgore's plain) to the flight master on the mesa.
do
    local bottom = ns.Docks[1006]
    check(bottom.site:find("Thunder Bluff") and bottom.name == "Bottom", "Thunder Bluff's west lift")
    local plan = measured("Thunder Bluff", { map = 1, x = bottom.x, y = bottom.y + 20, z = bottom.z },
        { map = 1, x = -1197.21, y = 29.71, z = 176.95 }, { faction = "Horde", teleports = false })
    local lift = has(plan, "lift")
    check(lift, "Thunder Bluff: up onto the mesa takes a lift: " .. modes(plan))
    check(lift.text == "Take the lift up", "Thunder Bluff: the lift goes up: " .. lift.text)
    report("Thunder Bluff, Mulgore to the flight master", plan)
end

-- Deeprun Tram: Ironforge's flight master to Stormwind's, Alliance, no flight point found.
do
    local plan = assert(api.Plan({ map = 0, x = -4821.78, y = -1155.44, z = 502.21 },
        { map = 0, x = -8832.77, y = 478.623, z = 109.616 }, { faction = "Alliance", teleports = false }))
    check(has(plan, "tram"), "Ironforge to Stormwind rides the Deeprun Tram: " .. modes(plan))
    check(not has(plan, "flight"), "and flies nowhere: no flight point found: " .. modes(plan))
    report("Ironforge to Stormwind, Alliance", plan)
end

-- Flights: the Crossroads to Orgrimmar, Horde. With no flight point found it walks; with every one found it flies.
do
    local from, to = { map = 1, x = -441.8, y = -2596.08, z = 96.06 }, { map = 1, x = 1677.59, y = -4315.71, z = 61.17 }
    local walked = assert(api.Plan(from, to, { faction = "Horde", teleports = false }))
    check(not has(walked, "flight"), "no flight point found: no flight: " .. modes(walked))
    local flown = assert(api.Plan(from, to, { faction = "Horde", teleports = false, assumeFlights = true }))
    local flight = has(flown, "flight")
    check(flight, "every flight point found: it flies: " .. modes(flown))
    check(flight.text == "Fly to Orgrimmar", "and says where: " .. flight.text)
    check(flown.seconds < walked.seconds, ("flying is quicker: %.0f s against %.0f s"):format(flown.seconds, walked.seconds))
    report("the Crossroads to Orgrimmar, walking", walked)
    report("the Crossroads to Orgrimmar, flying", flown)
end
