-- The few services the ported transport and planning code calls on (in Shortest Path Forever they live in its
-- Core/Core.lua, among its window's). ForeverNav has no window, so these are only what that code needs: saved settings
-- and per-character data, a startup hook, the server clock, locale strings, dock labels. NowMs and RouteShown are
-- upstream's as written (Shortest Path Forever, by Cillian Berragan, GPL-3.0-or-later).
local ADDON, ns = ...

-- Settings the ported code reads. ForeverNav has no settings page: callers pass what they want per request.
local DEFAULTS = {
    otherFaction = false,      -- plan with the other faction's boats and zeppelins too
    hearthMinimumSavings = 0,  -- seconds a Hearthstone must save over not using it (the planner's floor is 20)
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

-- Upstream's: a route of the other faction is planned only with otherFaction on.
function ns.RouteShown(route)
    return ns.db.otherFaction or not route.faction or route.faction == UnitFactionGroup("player")
end

-- A dock's label for the timetable's own phrases (Steps.lua names places for the API).
function ns.DockLabel(dockID)
    local dock = ns.Docks[dockID]
    return dock and (dock.name and dock.site and (dock.site .. ", " .. dock.name) or dock.site or dock.name) or "?"
end

function ns.Print(message)
    print("|cffb87aff" .. "ForeverNav:|r " .. tostring(message))
end
