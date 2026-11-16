-- The synced data loads in Lua 5.1 as the game loads it: Data/*.lua in Data.xml's order onto one addon table, the
-- walking maps onto ForeverNavPathData, and every map holds the packed blocks its counts promise.
--     lua5.1 tests/test_data_loads.lua        (from the repo root)

local ADDON = "addon/ForeverNav/"

local function xmlScripts(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    local out = {}
    for file in text:gmatch('<Script file="([^"]+)"/>') do out[#out + 1] = file end
    return out
end

local function load(path, ns)
    local chunk = assert(loadfile(path))
    chunk("ForeverNav", ns)
end

local failures = 0
local function check(ok, msg)
    if not ok then
        failures = failures + 1
        print("FAIL " .. msg)
    end
end

-- Data
local ns = {}
local dataFiles = xmlScripts(ADDON .. "Data/Data.xml")
check(#dataFiles >= 11, "Data.xml lists the routing data: " .. #dataFiles)
for _, file in ipairs(dataFiles) do load(ADDON .. "Data/" .. file, ns) end
local tables = { "Docks", "Routes", "Landmasses", "TaxiNodes", "TaxiPaths", "Entrances", "Portals", "Teleports",
    "Zones", "TownAreas", "WalkPlaces", "Walks", "RoadCells", "RoadEdges", "SpawnHeights" }
for _, name in ipairs(tables) do check(type(ns[name]) == "table", "ns." .. name .. " is a table") end
local lifts = 0
for id in pairs(ns.Docks or {}) do if id >= 1001 then lifts = lifts + 1 end end
check(lifts >= 10, "Transports.lua added the lift and tram landings to Docks: " .. lifts)

-- Walking maps
ForeverNavPathData = nil
for _, file in ipairs(xmlScripts(ADDON .. "Nav/Nav.xml")) do load(ADDON .. "Nav/" .. file, {}) end
check(type(ForeverNavPathData) == "table", "the walking maps are on ForeverNavPathData")
check(rawget(_G, "ShortestPathForeverPathData") == nil, "and not on Shortest Path Forever's global")
local maps = 0
for id, map in pairs(ForeverNavPathData or {}) do
    maps = maps + 1
    check(map.format == 3, "map " .. id .. " is format 3")
    for kind, want in pairs(map.counts) do
        local got = 0
        for _ in pairs(map.packed[kind]) do got = got + 1 end
        check(got == want, ("map %d: %d packed %s blocks of %d"):format(id, got, kind, want))
    end
end
check(maps == 3, "three walking maps (Eastern Kingdoms, Kalimdor, Zephras Isle): " .. maps)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print(("ok: %d data files, %d walking maps, %d lift and tram landings"):format(#dataFiles, maps, lifts))
