-- The shard you're on. Forever moves players between shards of a zone; a creature's GUID
-- (Creature-0-server-instance-zone-npc-spawn) carries the zone part, the same for every creature on one shard. The
-- first reading counts at once; once a second kind of creature agrees it's settled, and replacing a settled shard
-- takes two kinds of creature agreeing on the new one (one odd creature never moves it). Nameplates are re-read every
-- minute, since the shard can change while you stand still.
-- Adapted from Mapzeroth's LeyShare.lua (its "phase"), by tr0tsky0, MIT License (see nav/THIRD_PARTY.md).
local _, ns = ...

local Shard = {}
ns.Shard = Shard

local CONFIRMATIONS = 2
local SCAN_SECONDS = 60

local shard        -- the current shard (the zone part, as a string), nil until read
local tentative    -- the creature id it was read from while only one kind has agreed
local candidates = {}
local history = {}  -- { { at = server s, shard }, ... }: the shards you've been on lately, oldest first
local HISTORY = 20

local function Set(s, npc)
    if s ~= shard then
        history[#history + 1] = { at = GetServerTime(), shard = s }
        if #history > HISTORY then table.remove(history, 1) end
    end
    shard, tentative = s, npc
end

local readable = canaccessvalue or function() return true end

local function clean(v)
    if v ~= nil and not readable(v) then return nil end
    return v
end

-- A GUID seen on a unit (exposed for tests).
function Shard.Read(guid)
    guid = clean(guid)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, zone, npc = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    zone, npc = tonumber(zone), tonumber(npc)
    if not zone or zone <= 0 or not npc then return end
    local s = tostring(zone)
    if s == shard then
        if tentative and npc ~= tentative then tentative = nil end -- another kind agrees
        wipe(candidates)
    elseif not shard or tentative then
        Set(s, npc)
        wipe(candidates)
    else
        local c = candidates[s] or { n = 0 }
        candidates[s] = c
        if not c[npc] then c[npc], c.n = true, c.n + 1 end
        if c.n >= CONFIRMATIONS then
            Set(s, nil)
            wipe(candidates)
        end
    end
end

-- The shard id, and whether it's only tentative (one kind of creature so far); nil before any reading.
function Shard.Current()
    return shard, tentative ~= nil
end

-- Every shard you've been on since server time `since` (the one you were on then included), oldest first. Shard ids
-- are per zone: a ride from Durotar to Stranglethorn is on one in each.
function Shard.Since(since)
    local out, seen = {}, {}
    for i = #history, 1, -1 do
        local h = history[i]
        if not seen[h.shard] then
            seen[h.shard] = true
            table.insert(out, 1, h.shard)
        end
        if h.at <= since then break end
    end
    return out
end

-- For tests: forget it.
function Shard.Reset()
    shard, tentative = nil, nil
    wipe(history)
    wipe(candidates)
end

local function ReadUnit(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok then Shard.Read(guid) end
end

local function ScanNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if clean(UnitExists(unit)) then ReadUnit(unit) end
    end
end

ns.Init(function()
    if not CreateFrame then return end
    local frame = CreateFrame("Frame")
    if not frame.RegisterEvent then return end
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then ReadUnit(unit)
        elseif event == "PLAYER_TARGET_CHANGED" then ReadUnit("target")
        else ReadUnit("mouseover") end
    end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(SCAN_SECONDS, ScanNameplates) end
end)
