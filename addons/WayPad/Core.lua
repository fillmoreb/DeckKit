-- WayPad: the controller front end for DeckKit's waypoints (DeckKit.Waypoints, in the core: the list,
-- guidance, arrival). The compass in DeckHUD's status bar points the way.
--
--   Core.lua     WayPad's names for the core's waypoint functions, its own settings (WayPadDB)
--   HandOff.lua  handing the waypoints to another waypoint addon instead
--   Pins.lua     world map and minimap pins
--   Editor.lua   "Add waypoint": six digit slots dialed with the d-pad
--   Manager.lua  the waypoint list: make active, edit, remove, clear all
--   Slash.lua    /waypad and /way
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff4fc3f7WayPad|r") -- Print, On, Input, Window

local W = DeckKit.Waypoints
ns.W = W
ns.points = W.points -- the same live table (the core clears it in place, never replaces it)
ns.player = W.player
for _, name in ipairs({ "Readable", "MapInfo", "MapName", "Coords", "Describe", "PlayerPosition",
    "WorldPosition", "TranslateToMap", "Facing", "Guide", "Find", "Active", "Changed", "Add", "Edit",
    "SetActive", "Remove", "ClearAll", "StartTicker", "DrawnPoints" }) do
    ns[name] = W[name]
end
ns.ARRIVE_YARDS = W.ARRIVE_YARDS

-- The changing values (the active index, the arrival, debug) are read from the core as ns.active etc.
setmetatable(ns, {
    __index = function(_, k)
        if k == "active" or k == "arrival" or k == "debug" then return W[k] end
    end,
    __newindex = function(t, k, v)
        if k == "debug" then W.debug = v else rawset(t, k, v) end
    end,
})

W.OnChange(function()
    if ns.Pins then ns.Pins.Refresh() end
    if ns.Manager then ns.Manager.Refresh() end
end)
W.OnTick(function()
    if ns.Pins then ns.Pins.UpdateMinimap() end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    WayPadDB = WayPadDB or {}
    ns.db = WayPadDB
    -- Waypoints saved here before they moved to the core: brought over once (WayPadDB keeps its copy).
    W.Import(WayPadDB.points, WayPadDB.active, WayPadDB.nextId)
end)

BINDING_HEADER_WAYPAD = "WayPad"
BINDING_NAME_WAYPAD_ADD = "Add Waypoint"
BINDING_NAME_WAYPAD_MANAGE = "Manage Waypoints"
