-- The few services the ported transport and planning code calls on (in Shortest Path Forever they live in its
-- Core/Core.lua, among its window's). ForeverNav has no window, so these are only what that code needs: saved settings
-- and per-character data, a startup hook, the server clock, locale strings, dock labels. NowMs and RouteShown are
-- upstream's as written (Shortest Path Forever, by Cillian Berragan, GPL-3.0-or-later).
local ADDON, ns = ...

-- Settings the ported code reads. ForeverNav has no settings page: callers pass what they want per request.
local DEFAULTS = {
    otherFaction = false,      -- plan with the other faction's boats and zeppelins too
    hearthMinimumSavings = 0,  -- seconds a Hearthstone must save over not using it (the planner's floor is 20)
    teleports = true,          -- plan with the hearthstone and the teleports this character knows
    share = false,             -- ride sightings shared with other players on your shard (Share.lua): off until asked
    chat = false,              -- the library's own chat lines (a ride's schedule synced): off, ForeverNav has no window
    debug = false,             -- the ride observer's raw trace (upstream's /path debug)
}
local CHAR_DEFAULTS = function() return { taxi = {}, taxiNames = {} } end

-- Before the saved variables load (and in tests that never load them), answer with the defaults.
ns.db = setmetatable({}, { __index = DEFAULTS })
ns.charDB = CHAR_DEFAULTS()

-- Locale: the ported code's own phrases ("%s (turn in)", "docked"...) read back in English; ForeverNav's API returns
-- its own step text (Steps.lua), and none of these reach a player through it.
ns.L = setmetatable({}, { __index = function(_, key) return key end })

-- Startup: fn runs once the saved variables are loaded (at once, if they are).
local pending, ready = {}, false
function ns.Init(fn)
    if ready then fn() else pending[#pending + 1] = fn end
end

-- Loads the saved variables and runs what waited for them. ADDON_LOADED calls it; tests call it directly.
function ns.LoadSaved()
    if ready then return end
    ForeverNavDB = type(ForeverNavDB) == "table" and ForeverNavDB or {}
    ns.db = setmetatable(ForeverNavDB, { __index = DEFAULTS })
    ForeverNavCharDB = type(ForeverNavCharDB) == "table" and ForeverNavCharDB or CHAR_DEFAULTS()
    ForeverNavCharDB.taxi = ForeverNavCharDB.taxi or {}
    ForeverNavCharDB.taxiNames = ForeverNavCharDB.taxiNames or {}
    ns.charDB = ForeverNavCharDB
    ready = true
    for _, fn in ipairs(pending) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
    pending = {}
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    if frame.RegisterEvent then
        frame:RegisterEvent("ADDON_LOADED")
        frame:SetScript("OnEvent", function(self, _, name)
            if name == ADDON then
                self:UnregisterEvent("ADDON_LOADED")
                ns.LoadSaved()
            end
        end)
    end
end

-- Server time in milliseconds (upstream's): GetTime's precision on the server's clock, which the timetables use.
local offset
function ns.NowMs()
    local lead = GetServerTime() - GetTime()
    if not offset or lead > offset or offset - lead > 2 then
        offset = lead
    end
    return (GetTime() + offset) * 1000
end

-- Where the player stands: x north, y west (yards), z (nil: the client gives no height), and the instance map; nil
-- where the client gives no position (inside an instance). Upstream's PlayerPosition and JourneyPosition, in one.
local readable = canaccessvalue or function() return true end
function ns.JourneyPosition()
    local x, y, _, map = UnitPosition("player")
    if readable(x) and readable(y) and readable(map) and x and y and map then
        return x, y, nil, map
    end
end
ns.PlayerPosition = ns.JourneyPosition

-- The dock nearest the player and its yards (upstream's, as written): Floor.lua lets the floor go within a lift's reach,
-- since a lift changes floor without moving you. A lift's two landings tie on the map; the lower id wins.
local dockX, dockY, dockMap, nearestDock, nearestYards
function ns.NearestDock()
    local x, y, _, map = ns.JourneyPosition()
    if not x then
        return nil
    end
    if x == dockX and y == dockY and map == dockMap then
        return nearestDock, nearestYards
    end
    local nearest, yards
    for dockID, dock in pairs(ns.Docks) do
        if dock.map == map then
            local distance = math.sqrt((dock.x - x) ^ 2 + (dock.y - y) ^ 2)
            if not yards or distance < yards or (distance == yards and dockID < nearest) then
                nearest, yards = dockID, distance
            end
        end
    end
    dockX, dockY, dockMap = x, y, map
    nearestDock, nearestYards = nearest, yards
    return nearest, yards
end

-- The travel clock: listeners (the ride observer, the hearthstone's landing) sampled once a second, as upstream's
-- Core.lua runs it: while you're within 200 yd of a dock, a ride is being observed, you're on a taxi or moving, and
-- for a few seconds after anything wakes it (TRAVEL_AWAKE after a hearth, the minute its landing may take).
local TRAVEL_AWAKE, NEAR_DOCK = 75, 200
local travelListeners, travelTicker, awakeUntil, moving = {}, nil, 0, false
function ns.OnTravelTick(fn)
    travelListeners[#travelListeners + 1] = fn
end

local function TravelTick()
    local dockID, yards = ns.NearestDock()
    for _, fn in ipairs(travelListeners) do
        local ok, err = pcall(fn, dockID, yards)
        if not ok then geterrorhandler()(err) end
    end
    local active = (yards and yards <= NEAR_DOCK) or (ns.IsObservingRide and ns.IsObservingRide())
        or UnitOnTaxi("player") or moving or GetTime() <= awakeUntil
    if not active and travelTicker then
        travelTicker:Cancel()
        travelTicker = nil
    end
end
ns.TravelTick = TravelTick -- for tests: one tick by hand

function ns.WakeTravel(seconds)
    awakeUntil = math.max(awakeUntil, GetTime() + (seconds or TRAVEL_AWAKE))
    if not travelTicker and C_Timer and C_Timer.NewTicker then
        travelTicker = C_Timer.NewTicker(1, TravelTick)
    end
end

-- Moving, changing zone or coming out of a loading screen wakes the clock, which then decides whether to keep going.
if CreateFrame then
    local frame = CreateFrame("Frame")
    if frame.RegisterEvent then
        for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST",
            "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_STARTED_MOVING",
            "PLAYER_STOPPED_MOVING" }) do
            frame:RegisterEvent(event)
        end
        frame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_STARTED_MOVING" then moving = true
            elseif event == "PLAYER_STOPPED_MOVING" then moving = false end
            ns.WakeTravel(2)
        end)
    end
end

-- Upstream's: a route of the other faction is planned only with otherFaction on.
function ns.RouteShown(route)
    return ns.db.otherFaction or not route.faction or route.faction == UnitFactionGroup("player")
end

-- A dock's label for the timetable's own phrases (Steps.lua names places for the API).
function ns.DockLabel(dockID)
    local dock = ns.Docks[dockID]
    return dock and (dock.name and dock.site and (dock.site .. ", " .. dock.name) or dock.site or dock.name) or "?"
end

-- The library's own chat lines (upstream's ride observer announces a synced schedule): only with ForeverNavDB.chat on.
function ns.Print(message)
    if ns.db.chat then print("|cffb87aff" .. "ForeverNav:|r " .. tostring(message)) end
end
