-- A plan's legs in words, for the API: "Walk to Orgrimmar's zeppelin tower", "Take the zeppelin to Grom'gol",
-- "Fly to Booty Bay", "Take the lift up". ForeverNav's own (Shortest Path Forever's tracker words its steps in
-- Journey/JourneySteps.lua, tied to its window). English only for now.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

local RIDES = { boat = "boat", zeppelin = "zeppelin", tram = "tram" }
local NEAR_TOWN = 400 -- yards: a dock this close to a flight point is named for its town

-- "Orgrimmar, Durotar" -> "Orgrimmar"
local function Town(name)
    return name and (name:gsub(",.*$", "")) or nil
end

-- The town a world point stands in: the nearest flight point's within NEAR_TOWN, else the zone under it.
local function TownNear(map, x, y)
    local best, bestD
    for id, node in pairs(ns.TaxiNodes) do
        if node.map == map then
            local d = (node.x - x) ^ 2 + (node.y - y) ^ 2
            if not bestD or d < bestD then best, bestD = id, d end
        end
    end
    if best and bestD <= NEAR_TOWN * NEAR_TOWN then
        return Town(ns.charDB.taxiNames[best] or ns.TaxiNodes[best].name)
    end
    if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D and C_Map.GetMapInfoAtPosition then
        local continentUiMap = map == 0 and 1415 or map == 1 and 1414 or nil
        if continentUiMap then
            local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, map, CreateVector2D(x, y), continentUiMap)
            local info = ok and pos and C_Map.GetMapInfoAtPosition(continentUiMap, pos:GetXY())
            if info and info.name then return info.name end
        end
    end
end

-- A place of the plan (Planner.Places: kind dock / taxi / portal / teleport, or start / goal) by name.
function Steps.PlaceName(place, goalName)
    if not place then return nil end
    if place.kind == "goal" then return goalName end
    if place.kind == "taxi" then
        local node = ns.TaxiNodes[place.id]
        return Town(ns.charDB.taxiNames[place.id] or node and node.name)
    end
    if place.kind == "dock" then
        local dock = ns.Docks[place.id]
        if dock and dock.site then return dock.site end
        return TownNear(place.map, place.x, place.y)
    end
    return place.label
end

-- One leg's words. `goalName` names the plan's destination.
function Steps.Text(leg, goalName)
    local to = Steps.PlaceName(leg.to, goalName) or goalName or "your destination"
    local mode = leg.mode
    if mode == "walk" then
        if leg.to and leg.to.kind == "dock" then
            local route = leg.next and ns.Routes[leg.next.route]
            local ride = route and RIDES[route.kind]
            if ride then return ("Walk to the %s at %s"):format(ride, to) end
        end
        return "Walk to " .. to
    elseif mode == "flight" then
        return "Fly to " .. to
    elseif mode == "lift" then
        local fromDock, toDock = ns.Docks[leg.from.id], ns.Docks[leg.to.id]
        local up = fromDock and toDock and toDock.z > fromDock.z
        return up and "Take the lift up" or "Take the lift down"
    elseif RIDES[mode] then
        return ("Take the %s to %s"):format(RIDES[mode], to)
    elseif mode == "portal" or mode == "passage" then
        local name = leg.from and leg.from.label
        return name and ("Take the " .. name) or ("Go through to " .. to)
    elseif mode == "teleport" then
        local t = leg.teleport
        if t and t.item == 6948 then return "Hearth to " .. to end -- the Hearthstone
        local info = t and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(t.spell)
        if info and info.name then return ("Cast %s to %s"):format(info.name, to) end
        return "Teleport to " .. to
    end
    return "Go to " .. to
end
