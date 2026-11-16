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
