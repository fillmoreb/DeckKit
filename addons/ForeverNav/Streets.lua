-- ForeverNav's streets: roads recorded by walking them. Shortest Path Forever's walking maps mark the outdoor roads but
-- hardly any city streets (37 road cells in all of Orgrimmar's map), and their 8-yard cells link straight through
-- the thin shells of Orgrimmar's rock formations. So a player walks the streets once; every 8-yard cell they pass
-- through is kept and counts as road from then on (PathGrid's road lookup asks ns.ExtraRoads), and in a capital a walk
-- keeps to the roads (API.lua's city weight). Every recorded cell is walkable for certain: someone walked it.
--
-- Saved in ForeverNavDB.streets[map] = { [gx * 65536 + gy] = true } (global cell coordinates of that map's walking
-- grid). Cells shipped with the addon can be added to STREETS below (exported from a recording).
--
--   v1.Streets.Record(on)       start or stop recording (stopping applies them to routes at once)
--   v1.Streets.Recording()      true while recording
--   v1.Streets.Cells(map)       the recorded cells' centres: { { x, y }, ... } in world yards (north, west)
--   v1.Streets.Count(map)       how many
--   v1.Streets.Clear(map)       forget the recorded cells (nil: every map)
--   v1.Streets.OnChange(fn)     fn() when cells are added (while recording, at most once a second) or cleared
--   v1.Streets.Export(map)      the recorded cells as a Lua table's text, for shipping them in STREETS
local _, ns = ...
if ns.broken then return end

local Grid = ns.PathGrid
local Streets = {}
ns.Streets = Streets -- published as ForeverNav.v1.Streets (API.lua)

local SAMPLE_SECONDS = 0.25
local STREETS = {} -- shipped cells: [map] = { key, key, ... } (none yet)

local recording, ticker, last = false, nil, nil
local listeners, dirty, notified = {}, false, 0

function Streets.OnChange(fn) listeners[#listeners + 1] = fn end
local function Notify(force)
    local now = GetTime()
    if not force and now - notified < 1 then dirty = true return end
    notified, dirty = now, false
    for _, fn in ipairs(listeners) do pcall(fn) end
end

local function Store(map)
    ForeverNavDB = type(ForeverNavDB) == "table" and ForeverNavDB or {}
    ForeverNavDB.streets = ForeverNavDB.streets or {}
    local s = ForeverNavDB.streets[map]
    if not s then s = {}; ForeverNavDB.streets[map] = s end
    return s
end

local function Key(gx, gy) return gx * 65536 + gy end

-- The routes' road sets learn the recorded cells: PathGrid calls this as it decodes a cluster's roads.
function ns.ExtraRoads(st, k, set)
    local C, ny = st.C, st.ny
    local cx, cy = math.floor(k / ny) * C, (k % ny) * C
    local added
    local function Add(key)
        local gx, gy = math.floor(key / 65536), key % 65536
        if gx >= cx and gx < cx + C and gy >= cy and gy < cy + C then
            added = added or (set or {})
            added[(gx - cx) * C + (gy - cy)] = true
        end
    end
    local saved = type(ForeverNavDB) == "table" and ForeverNavDB.streets and ForeverNavDB.streets[st.map]
    if saved then for key in pairs(saved) do Add(key) end end
    for _, key in ipairs(STREETS[st.map] or {}) do Add(key) end
    return added or set
end

-- Every cell on the line between two global cells (so a fast mount doesn't leave gaps).
local function Line(ax, ay, bx, by, fn)
    local dx, dy = math.abs(bx - ax), math.abs(by - ay)
    local sx, sy = ax < bx and 1 or -1, ay < by and 1 or -1
    local err = dx - dy
    for _ = 1, dx + dy + 1 do
        fn(ax, ay)
        if ax == bx and ay == by then return end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; ax = ax + sx end
        if e2 < dx then err = err + dx; ay = ay + sy end
    end
end

local function Sample()
    if UnitOnTaxi and UnitOnTaxi("player") then last = nil return end
    if IsFlying and IsFlying() then last = nil return end
    local x, y, _, map = UnitPosition("player")
    if not (x and y and map) or (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then return end
    local st = Grid.State(map)
    if not st then return end
    local gx, gy = math.floor((x - st.x0) / st.cs), math.floor((y - st.y0) / st.cs)
    if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then return end
    local store, new = Store(map), false
    local function Mark(cx, cy)
        local key = Key(cx, cy)
        if not store[key] then store[key] = true; new = true end
    end
    -- A jump of more than a few cells (a portal, a loading screen, a hearth) isn't walked: start afresh there.
    if last and last.map == map and math.abs(last.gx - gx) <= 4 and math.abs(last.gy - gy) <= 4 then
        Line(last.gx, last.gy, gx, gy, Mark)
    else
        Mark(gx, gy)
    end
    last = { map = map, gx = gx, gy = gy }
    if new then Notify() elseif dirty then Notify() end
end

-- Routes pick the new roads up: the grid's decoded roads and baked edges are dropped and rebuilt as needed.
local function Apply()
    if ns.Path and ns.Path.ClearCaches then ns.Path.ClearCaches() end
end

function Streets.Record(on)
    on = on and true or false
    if on == recording then return recording end
    recording = on
    if on then
        last = nil
        ticker = C_Timer.NewTicker(SAMPLE_SECONDS, Sample)
        Sample()
    else
        if ticker then ticker:Cancel(); ticker = nil end
        Apply()
        Notify(true)
    end
    return recording
end

function Streets.Recording() return recording end

function Streets.Cells(map)
    local st = Grid.State(map)
    local out = {}
    if not st then return out end
    local saved = type(ForeverNavDB) == "table" and ForeverNavDB.streets and ForeverNavDB.streets[map] or {}
    for key in pairs(saved) do
        local gx, gy = math.floor(key / 65536), key % 65536
        out[#out + 1] = { x = st.x0 + (gx + 0.5) * st.cs, y = st.y0 + (gy + 0.5) * st.cs }
    end
    return out
end

function Streets.Count(map)
    local n = 0
    local saved = type(ForeverNavDB) == "table" and ForeverNavDB.streets and ForeverNavDB.streets[map]
    for _ in pairs(saved or {}) do n = n + 1 end
    return n
end

function Streets.Clear(map)
    if type(ForeverNavDB) ~= "table" or not ForeverNavDB.streets then return end
    if map then ForeverNavDB.streets[map] = nil else ForeverNavDB.streets = {} end
    Apply()
    Notify(true)
end

function Streets.Export(map)
    local keys = {}
    for key in pairs(type(ForeverNavDB) == "table" and ForeverNavDB.streets and ForeverNavDB.streets[map] or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys, 12 do
        local row = {}
        for j = i, math.min(i + 11, #keys) do row[#row + 1] = tostring(keys[j]) end
        parts[#parts + 1] = "        " .. table.concat(row, ", ") .. ","
    end
    return ("    [%d] = {\n%s\n    },"):format(map, table.concat(parts, "\n"))
end
