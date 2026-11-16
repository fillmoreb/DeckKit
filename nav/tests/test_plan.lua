-- The planner joins walks with rides: a level 3 orc in the Valley of Trials who has found no flight point, headed
-- for Sentinel Hill in Westfall, takes the zeppelin from Orgrimmar to Grom'gol and walks the rest (the route
-- MapzerothLib gave, which ForeverNav replaces).
ns.LoadSaved()
local api = ForeverNav.v1

local VALLEY = { map = 1, x = -598.3, y = -4410.5 }
local SENTINEL_HILL = { map = 0, x = -10628.89, y = 1036.68 }   -- ns.TaxiNodes: "Sentinel Hill, Westfall"

local function describe(plan)
    local lines = {}
    for i, leg in ipairs(plan.legs) do
        lines[i] = ("  %d. [%s] %s  (%.0f s%s)"):format(i, leg.mode, leg.text, leg.seconds,
            leg.wait > 0 and (", wait %.0f s"):format(leg.wait) or "")
    end
    return table.concat(lines, "\n")
end

local t0 = os.clock()
local plan, why = api.Plan(VALLEY, SENTINEL_HILL, { name = "Sentinel Hill", faction = "Horde" })
local took = os.clock() - t0
check(plan, "a plan: " .. tostring(why))
local modes = {}
for _, leg in ipairs(plan.legs) do modes[#modes + 1] = leg.mode end
local list = table.concat(modes, ",")
check(list:find("zeppelin", 1, true), "Durotar to Westfall rides a zeppelin: " .. list)
check(not list:find("flight", 1, true), "and flies nowhere: no flight point is found: " .. list)
check(plan.legs[1].mode == "walk" and plan.legs[#plan.legs].mode == "walk", "it starts and ends on foot")
check(plan.legs[#plan.legs].text:find("Sentinel Hill", 1, true), "the last step names where it goes")
local zeppelin
for _, leg in ipairs(plan.legs) do if leg.mode == "zeppelin" then zeppelin = leg end end
check(zeppelin.text:find("Grom'gol", 1, true), "the zeppelin goes to Grom'gol: " .. zeppelin.text)
check(zeppelin.from.map == 1 and zeppelin.to.map == 0, "from Kalimdor to the Eastern Kingdoms")
print(("plan: Valley of Trials -> Sentinel Hill as a Horde character with no flights: %.0f s (%.1f min), planned in %.0f ms\n%s"):format(
    plan.seconds, plan.seconds / 60, took * 1000, describe(plan)))

-- Every flight point counted as found: the same trip flies where that's quicker.
local flying = assert(api.Plan(VALLEY, SENTINEL_HILL, { name = "Sentinel Hill", faction = "Horde", assumeFlights = true }))
check(flying.seconds <= plan.seconds, ("with every flight point found it's no slower: %.0f s against %.0f s"):format(
    flying.seconds, plan.seconds))
print(("plan: the same with every flight point found: %.0f s\n%s"):format(flying.seconds, describe(flying)))

-- Nonsense in, a reason out.
check(select(2, api.Plan({ map = 1 }, SENTINEL_HILL)) == "invalid", "a point without coordinates: invalid")

-- The Hearthstone: bound in Orgrimmar (where the hearth last set you down: Teleports.lua keeps it), from Grom'gol to
-- Orgrimmar's flight master it hearths instead of riding the zeppelin back.
canaccessvalue = function() return true end
GetBindLocation = function() return "Orgrimmar" end
C_Item = { GetItemCount = function(item) return item == 6948 and 1 or 0 end, GetItemCooldown = function() return 0, 0 end }
C_SpellBook = { IsSpellKnown = function() return false end }
C_Spell = { GetSpellInfo = function() return { castTime = 10000 } end, GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
ns.charDB.bind = { name = "Orgrimmar", map = 1, x = 1630, y = -4440 }
local GROMGOL = { map = 0, x = -12464.0, y = 231.6 }                        -- the zeppelin's dock at Grom'gol
local ORGRIMMAR_FLIGHTS = { map = 1, x = 1677.59, y = -4315.71 }
local home = assert(api.Plan(GROMGOL, ORGRIMMAR_FLIGHTS, { name = "Orgrimmar's flight master", faction = "Horde" }))
check(home.legs[1].mode == "teleport", "Grom'gol to Orgrimmar starts with the Hearthstone: " .. describe(home))
check(home.legs[1].text == "Hearth to Orgrimmar", "and says so: " .. home.legs[1].text)
local rode = assert(api.Plan(GROMGOL, ORGRIMMAR_FLIGHTS, { name = "Orgrimmar's flight master", faction = "Horde", teleports = false }))
check(rode.seconds > home.seconds, ("without it the trip is longer: %.0f s against %.0f s"):format(rode.seconds, home.seconds))
print(("plan: Grom'gol -> Orgrimmar, bound in Orgrimmar: %.0f s (without the hearth %.0f s)\n%s"):format(home.seconds, rode.seconds, describe(home)))

-- On cooldown it isn't used.
C_Item.GetItemCooldown = function() return GetTime() - 10, 3600 end
local cooling = assert(api.Plan(GROMGOL, ORGRIMMAR_FLIGHTS, { faction = "Horde" }))
check(cooling.legs[1].mode ~= "teleport", "a Hearthstone on cooldown isn't used: " .. describe(cooling))

-- Measured walks: the same trip with its walks searched on the walking maps (following roads). Straight-line
-- estimates only ever undersell a walk, so the measured trip is no shorter, and the plan ends with nothing estimated.
-- The frame-sliced searches run here by hand: Path.after is the next-frame hook PathJobs schedules through.
local frames = {}
ns.Path.after = function(fn) frames[#frames + 1] = fn end
local function measured(from, to, opts)
    local got
    local handle = assert(api.PlanMeasured(from, to, opts, function(p, why) got = p or why end))
    local spins = 0
    while got == nil and #frames > 0 and spins < 200000 do
        table.remove(frames, 1)()
        spins = spins + 1
    end
    check(type(got) == "table", "a measured plan: " .. tostring(got))
    return got, spins
end
local estimate = assert(api.Plan(VALLEY, SENTINEL_HILL, { name = "Sentinel Hill", faction = "Horde", teleports = false }))
local real, spins = measured(VALLEY, SENTINEL_HILL, { name = "Sentinel Hill", faction = "Horde", teleports = false })
check(real.measured, "every walk the plan uses is measured")
check(real.seconds >= estimate.seconds - 1, ("measured is no shorter than the estimate: %.0f s against %.0f s"):format(
    real.seconds, estimate.seconds))
local lastEstimate, lastReal = estimate.legs[#estimate.legs], real.legs[#real.legs]
check(lastReal.seconds >= lastEstimate.seconds, ("the walk from Grom'gol, measured: %.0f s against %.0f s estimated"):format(
    lastReal.seconds, lastEstimate.seconds))
print(("plan: measured: %.0f s (%.1f min) against %.0f s estimated, %d frames of searching\n%s"):format(
    real.seconds, real.seconds / 60, estimate.seconds, spins, describe(real)))
