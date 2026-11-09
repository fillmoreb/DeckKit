-- Hand-off: one waypoint system at a time. WayPad's own (arrow, map and minimap pins, arrival),
-- or another waypoint addon that speaks the common waypoint interface (TomTom's AddWaypoint /
-- RemoveWaypoint / SetCrazyArrow, which other waypoint addons also provide). In hand-off mode
-- WayPad is the controller front end: its d-pad editor and Manage window drive the other addon,
-- and WayPad's own arrow, pins and arrival handling stay off.
--
-- WayPad's list stays the record of what you added (Manage and MapDeck read it). The other addon
-- only ever gets WayPad's own waypoints added and removed; whatever else it has is left alone.
-- Asking it to add a waypoint that already exists hands back the existing one, so WayPad needs
-- no ids of its own and nothing breaks across reloads.
--
-- "Waypoints go to" (DeckKit menu, WayPad page): Auto (the other addon if one is installed),
-- WayPad, or the other addon.
local _, ns = ...

local HandOff = {}
ns.HandOff = HandOff

local MODES = { auto = true, waypad = true, other = true }

-- The other waypoint addon, if one that speaks the interface is installed.
local function Other()
    local t = _G.TomTom
    if type(t) == "table" and type(t.AddWaypoint) == "function" and type(t.RemoveWaypoint) == "function" then
        return t
    end
end
HandOff.Available = function() return Other() ~= nil end

function HandOff.Mode()
    local mode = ns.db and ns.db.waypoints
    return MODES[mode] and mode or "auto"
end

-- The addon waypoints go to right now, or nil for WayPad's own.
function HandOff.Active()
    if HandOff.Mode() == "waypad" then return nil end
    return Other()
end

local function Title(p) return p.label or ns.Coords(p.x, p.y) end

local function Ref(t, p, pointArrow)
    return t:AddWaypoint(p.mapID, p.x, p.y, { title = Title(p), from = "WayPad", silent = true, crazy = pointArrow or false })
end

local function Point(t, p)
    local uid = Ref(t, p)
    if uid and type(t.SetCrazyArrow) == "function" then t:SetCrazyArrow(uid, ns.ARRIVE_YARDS, Title(p)) end
end

local function Drop(t, p)
    local uid = Ref(t, p)
    if uid then t:RemoveWaypoint(uid) end
end

-- Called by Core.lua as waypoints change (each a no-op in WayPad mode).
function HandOff.Added(p)
    local t = HandOff.Active()
    if t then Ref(t, p, true) end -- the new one becomes the target, as in WayPad
end

function HandOff.Edited(old, p, isActive)
    local t = HandOff.Active()
    if not t then return end
    Drop(t, old)
    Ref(t, p)
    if isActive then Point(t, p) end
end

function HandOff.Activated(p)
    local t = HandOff.Active()
    if t then Point(t, p) end
end

function HandOff.Removed(p)
    local t = HandOff.Active()
    if t then Drop(t, p) end
end

-- Switching modes moves WayPad's waypoints over (or takes them back).
function HandOff.SetMode(mode)
    local before = HandOff.Active()
    ns.db.waypoints = mode
    local after = HandOff.Active()
    if before ~= after then
        if before then for _, p in ipairs(ns.points) do Drop(before, p) end end
        if after then
            for _, p in ipairs(ns.points) do Ref(after, p) end
            if ns.Active() then Point(after, ns.Active()) end
        end
    end
    ns.Changed()
end

-- What WayPad itself draws: nothing while another addon has the waypoints.
function ns.DrawnPoints()
    if HandOff.Active() then return {} end
    return ns.points
end

-- At login, hand over the waypoints WayPad already has (after the other addon has set itself up).
-- Ones it saved itself are found, not duplicated.
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(2, function()
        local t = HandOff.Active()
        if not t then return end
        for _, p in ipairs(ns.points) do Ref(t, p) end
        if ns.Active() then Point(t, ns.Active()) end
        ns.Changed()
    end)
end)
