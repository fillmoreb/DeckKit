-- What a plan starts from: the planner's options (adapted from Shortest Path Forever's Core/PlanContext.lua Options, by
-- Cillian Berragan, GPL-3.0-or-later), and the flight points this character knows, learned from the flight master's
-- map the way its Transport/Taxi.lua scans it (slots CURRENT or REACHABLE are known; a map's nodes not listed on it
-- are forgotten). The hearthstone and teleports come from Transport/Teleports.lua (upstream's, ported). A party mage's
-- portals and the ride you're on are not read yet: plans don't use them.
local _, ns = ...

local Context = {}
ns.Context = Context

local readable = canaccessvalue or function() return true end

local lastSpeed = 7
-- Run speed, kept while standing still or when the client hides it (upstream's RunSpeed).
function Context.RunSpeed()
    local _, speed = GetUnitSpeed("player")
    if readable(speed) and type(speed) == "number" and speed > 0 and speed < math.huge then
        lastSpeed = speed
    end
    return lastSpeed
end

-- The planner's options from `from` to `to` ({ map, x, y }: instance map and UnitPosition's x north, y west).
-- opts (optional): faction ("Horde"/"Alliance", default the player's), walkSpeed (yards a second, default the
-- player's), assumeFlights (true: every flight point counts as known), otherFaction, teleports (false: no hearthstone
-- or teleport spells; they're used from where you stand only, as upstream does: from anywhere else, pass false).
-- Your own sightings, with any shared on the shard you're on (Share.lua) where they're newer.
function Context.Anchors()
    local own = ns.Timetable.Anchors()
    local shared = ns.Share and ns.db.share and ns.Share.For((ns.Shard.Current()))
    if not shared then return own end
    local out = {}
    for route, a in pairs(own) do out[route] = a end
    for route, a in pairs(shared) do
        if ns.Model.Newer(a, out[route]) then out[route] = a end
    end
    return out
end

function Context.Options(from, to, opts)
    opts = opts or {}
    local now = ns.NowMs()
    local teleports, ready
    if opts.teleports ~= false then teleports, ready = ns.UsableTeleports(now) end
    return {
        from = from,
        to = to,
        now = now,
        teleports = teleports,
        teleportReady = ready,
        walkSpeed = opts.walkSpeed or Context.RunSpeed(),
        faction = opts.faction or UnitFactionGroup("player"),
        otherFaction = opts.otherFaction or ns.db.otherFaction or false,
        taxiKnown = not opts.assumeFlights and ns.charDB.taxi or nil,
        anchors = Context.Anchors(),
        docks = ns.Docks,
        routes = ns.Routes,
        taxiNodes = ns.TaxiNodes,
        taxiPaths = ns.TaxiPaths,
        portals = ns.Portals,
        hearthMinimumSavings = ns.db.hearthMinimumSavings or 0,
        landmasses = ns.Landmasses,
        baked = ns.Walks,
    }
end

------------------------------------------------------------------------
-- Known flight points
------------------------------------------------------------------------

local function SlotKnown(slot)
    local kind = TaxiNodeGetType(slot)
    return kind == "CURRENT" or kind == "REACHABLE"
end

local function ScanFlightMaster()
    local uiMap = GetTaxiMapID and GetTaxiMapID()
    local nodes = uiMap and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes(uiMap) or {}
    local bySlot = {}
    for _, node in ipairs(nodes) do
        if node.slotIndex and ns.TaxiNodes[node.nodeID] then bySlot[node.slotIndex] = node end
    end
    local listed, continent = {}, nil
    for slot = 1, NumTaxiNodes() do
        local node = bySlot[slot]
        if node and SlotKnown(slot) then
            ns.charDB.taxi[node.nodeID] = true
            listed[node.nodeID] = true
            continent = continent or ns.TaxiNodes[node.nodeID].map
            local name = TaxiNodeName(slot)
            ns.charDB.taxiNames[node.nodeID] = (name and name ~= "") and name or node.name
        end
    end
    if continent ~= nil then
        for nodeID in pairs(ns.charDB.taxi) do
            local node = ns.TaxiNodes[nodeID]
            if node and node.map == continent and not listed[nodeID] then
                ns.charDB.taxi[nodeID], ns.charDB.taxiNames[nodeID] = nil, nil
            end
        end
    end
end

-- How many flight points this character is known to have found (for callers that hint "open a flight master's map").
function Context.KnownFlightCount()
    local n = 0
    for _ in pairs(ns.charDB.taxi) do n = n + 1 end
    return n
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    if frame.RegisterEvent then
        local open = false
        frame:RegisterEvent("TAXIMAP_OPENED")
        frame:RegisterEvent("TAXIMAP_CLOSED")
        frame:RegisterEvent("TAXI_NODE_STATUS_CHANGED") -- learning a node, while the flight master's map is open
        frame:SetScript("OnEvent", function(_, event)
            if event == "TAXIMAP_CLOSED" then
                open = false
                return
            end
            if event == "TAXIMAP_OPENED" then open = true end
            if open then
                local ok, err = pcall(ScanFlightMaster)
                if not ok then geterrorhandler()(err) end
            end
        end)
    end
end
