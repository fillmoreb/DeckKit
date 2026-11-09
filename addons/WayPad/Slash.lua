-- /waypad and /way (TomTom-style).
--
-- /way                          open the Add Waypoint window
-- /way 45.2 62.8 [label]        add a waypoint in the zone you're in (commas are fine: 45.2, 62.8)
-- /way <zone> 45.2 62.8 [label] add one in a named zone
-- /way #<mapID> 45.2 62.8       add one on a map by ID
-- /way list | clear
--
-- /waypad          the waypoint list        /waypad add     the Add Waypoint window
-- /waypad move     unlock the arrow to drag /waypad reset   put the arrow back
-- /waypad debug    print the position math once a second (again to stop)
local _, ns = ...

-- Key bindings (Bindings.xml)
function WayPad_ToggleEditor() ns.Editor.Toggle() end
function WayPad_ToggleManager() ns.Manager.Toggle() end
-- For MapDeck (and later the DeckKit suite): the live waypoint list and which one is active.
function WayPad_GetPoints() return ns.points, ns.active end

------------------------------------------------------------------------
-- Zones by name
------------------------------------------------------------------------

local zones
local RANK = { [3] = 1, [2] = 2, [5] = 3, [6] = 4, [4] = 5 } -- zone, continent, micro, orphan, dungeon

local function ContinentOf(mapID)
    for _ = 1, 10 do
        local info = ns.MapInfo(mapID)
        if not info then return end
        if info.mapType == 2 then return mapID end
        if not info.parentMapID or info.parentMapID == 0 then return end
        mapID = info.parentMapID
    end
end

-- Exact name, then the start of a name, then anywhere in a name. Ties: zones first, then your continent.
local function FindZone(name)
    if not zones then
        zones = {}
        for mapID = 1, 5000 do
            local info = ns.MapInfo(mapID)
            if info and type(info.name) == "string" and info.name ~= "" and RANK[info.mapType] then
                table.insert(zones, { mapID = mapID, lower = info.name:lower(), rank = RANK[info.mapType] })
            end
        end
    end
    name = name:lower()
    local here = C_Map.GetBestMapForUnit("player")
    local myContinent = ns.Readable(here) and ContinentOf(here)
    local best, bestScore
    for _, z in ipairs(zones) do
        local match
        if z.lower == name then match = 0
        elseif z.lower:sub(1, #name) == name then match = 1
        elseif z.lower:find(name, 1, true) then match = 2 end
        if match then
            local score = match * 100 + z.rank * 10
            if myContinent and ContinentOf(z.mapID) ~= myContinent then score = score + 5 end
            if not bestScore or score < bestScore then best, bestScore = z.mapID, score end
        end
    end
    return best
end

------------------------------------------------------------------------
-- /way
------------------------------------------------------------------------

local function List()
    if #ns.points == 0 then
        ns.Print("No waypoints.")
        return
    end
    for i, p in ipairs(ns.points) do
        ns.Print((i == ns.active and "|cffffd100>|r " or "  ") .. i .. ". " .. ns.Describe(p))
    end
end

local function Way(msg)
    msg = strtrim((string.gsub(msg or "", ",", " ")))
    local lower = msg:lower()
    if msg == "" then
        ns.Editor.Open()
        return
    elseif lower == "clear" or lower == "reset" or lower == "clear all" then
        ns.ClearAll()
        ns.Print("All waypoints cleared.")
        return
    elseif lower == "list" then
        List()
        return
    end

    local words = {}
    for w in msg:gmatch("%S+") do table.insert(words, w) end
    local at
    for i = 1, #words - 1 do
        if tonumber(words[i]) and tonumber(words[i + 1]) then
            at = i
            break
        end
    end
    if not at then
        ns.Print("Usage: /way [zone] 45.2 62.8 [label]   ·   /way list   ·   /way clear")
        return
    end

    local x, y = tonumber(words[at]), tonumber(words[at + 1])
    if x < 0 or x > 100 or y < 0 or y > 100 then
        ns.Print("Coordinates go from 0 to 100.")
        return
    end
    local zone = table.concat(words, " ", 1, at - 1)
    local label = at + 2 <= #words and table.concat(words, " ", at + 2) or nil

    local mapID
    if zone == "" then
        mapID = C_Map.GetBestMapForUnit("player")
        if not ns.Readable(mapID) then
            ns.Print("Can't tell what zone you're in here. Try /way <zone> x y.")
            return
        end
    elseif zone:match("^#%d+$") then
        mapID = tonumber(zone:sub(2))
        if not ns.MapInfo(mapID) then
            ns.Print("No map with ID " .. mapID .. ".")
            return
        end
    else
        mapID = FindZone(zone)
        if not mapID then
            ns.Print("No zone called \"" .. zone .. "\".")
            return
        end
    end
    ns.Print("Waypoint added: " .. ns.Describe(ns.Add(mapID, x / 100, y / 100, label)))
end

------------------------------------------------------------------------
-- /waypad
------------------------------------------------------------------------

local function WayPadSlash(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "" then
        ns.Manager.Toggle()
    elseif cmd == "add" then
        ns.Editor.Open()
    elseif cmd == "list" then
        List()
    elseif cmd == "clear" then
        Way("clear")
    elseif cmd == "move" then
        ns.Arrow.SetUnlocked(not ns.Arrow.unlocked)
        ns.Print(ns.Arrow.unlocked and "Arrow unlocked: drag it, then /waypad move again to lock."
            or "Arrow locked.")
        ns.StartTicker()
    elseif cmd == "reset" then
        ns.Arrow.Reset()
        ns.Print("Arrow moved back to the top of the screen.")
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        ns.Print("Debug " .. (ns.debug and "on" or "off") .. ".")
        ns.StartTicker()
    else
        ns.Print("/waypad (list window), add, move, reset, debug  ·  /way [zone] x y [label], list, clear")
    end
end

SLASH_WAYPAD1 = "/waypad"
SlashCmdList.WAYPAD = WayPadSlash

-- /way only if no other addon took it (checked once every addon has loaded).
ns.On("PLAYER_LOGIN", function()
    for key, value in pairs(_G) do
        if type(key) == "string" and key:match("^SLASH_") and type(value) == "string"
            and value:lower() == "/way" and not key:match("^SLASH_WAYPAD") then
            ns.Print("/way is taken by another addon (" .. key .. "); use /waypad add or your bound buttons.")
            return
        end
    end
    SLASH_WAYPADWAY1 = "/way"
    SlashCmdList.WAYPADWAY = Way
end)

ns.AddSettings({
    { type = "action", label = "Add a waypoint", hint = "Dial in the coordinates with the d-pad.",
      run = function() ns.Editor.Open() end },
    { type = "action", label = "Manage waypoints", hint = "Make one active, edit or remove them.",
      run = function() ns.Manager.Toggle() end },
    { type = "action", label = "Reset the arrow position", hint = "Puts the arrow back at the top of the screen.",
      run = function() ns.Arrow.Reset(); ns.Print("Arrow moved back to the top of the screen.") end },
    { type = "info", label = "Bind Add / Manage in Key Bindings > DeckKit." },
})
