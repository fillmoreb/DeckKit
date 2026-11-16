-- Ride sightings shared with other ForeverNav players: one ride by anyone on your shard tells everyone there where
-- that boat is in its loop. Off until the player turns it on (ForeverNavDB.share, v1.SetSharing: DeckKit's menu).
--
-- A hidden addon channel per faction (rides are faction business), FNavRidesA / FNavRidesH, prefix FNav, version 1:
--   S:1:<shard>:<route>:<epoch>:<seen>   a sighting: route id, server ms at loop phase 0, server s when seen
--   Q:1:<shard>                          "what do you have for this shard?"
-- Every number is checked: a route ForeverNav knows, a shard of digits, a time within the last two days. Nothing
-- received is run. Sightings are kept by shard (ForeverNavDB.shared) and a plan uses those of the shard you're on
-- when they're newer than your own (Context.lua). Each one heard is also checked against your own (Drift.lua).
--
-- Joining, keeping out of the way and sending are adapted from Mapzeroth's LeyShare.lua, by tr0tsky0, MIT License (see
-- nav/THIRD_PARTY.md): wait for the game's channels at login so ours never takes /1, move ours past every chat channel
-- so General and Trade keep their numbers, hide it from the chat windows, rejoin if dropped, stay out of instances,
-- and send at Forever's channel allowance (about 10 at once, then less than one a second).
local _, ns = ...

local Share = {}
ns.Share = Share

local PREFIX, VERSION = "FNav", "1"
local CHANNEL_BASE = "FNavRides"
local KEEP = 2 * 24 * 3600             -- seconds a sighting is kept and passed on
local FUTURE = 60                      -- a sighting stamped further ahead than this is refused
local SEND_GAP, THROTTLE_PAUSE = 1.25, 5
local OWN_DELAY = 45                   -- a ride is sent this long after it's recorded, so its final refinement goes
local REPLY_MINE, REPLY_OTHERS = { 1, 3 }, { 4, 12 } -- seconds before answering a Q: own sightings first
local MAX_REPLY = 10                   -- sightings in one answer
local REJOIN_SECONDS, SETTLE_SECONDS, SETTLE_MAX = 60, 3, 30
local REORDER_SECONDS, MAX_SWAPS = 60, 10

local queue, sending = {}, false
local me = {}                          -- our own name as senders show it (the server echoes our messages back)
local asked = {}                       -- [shard] = true: a Q for it has gone out (or been heard) this session
local answering = {}                   -- [shard] = token while an answer waits; a heard S for it with nothing new cancels
local lastSent = {}                    -- [route] = seen of the sighting last sent, so a ride goes once
local started, reorderUntil, swapsLeft = false, nil, 0

local readable = canaccessvalue or function() return true end
local function clean(v) if v ~= nil and not readable(v) then return nil end return v end

local function On() return ns.db.share == true end

local function Faction() return UnitFactionGroup("player") == "Horde" and "H" or "A" end
local function ChannelName() return CHANNEL_BASE .. Faction() end

local function ChannelIndex()
    local id = GetChannelName(ChannelName())
    return type(id) == "number" and id > 0 and id or nil
end

------------------------------------------------------------------------
-- The store: ForeverNavDB.shared[shard][route] = { epoch, seen }
------------------------------------------------------------------------

local function Store()
    local s = ns.db.shared
    if type(s) ~= "table" then
        s = {}
        ns.db.shared = s
    end
    return s
end

local function Prune()
    local cutoff = GetServerTime() - KEEP
    for shard, routes in pairs(Store()) do
        for route, a in pairs(routes) do
            if type(a) ~= "table" or not a.seen or a.seen < cutoff then routes[route] = nil end
        end
        if next(routes) == nil then Store()[shard] = nil end
    end
end

-- Keeps a sighting if it's newer than what's held for that shard and route; true when kept.
local function Keep(shard, route, epoch, seen)
    local routes = Store()[shard] or {}
    local held = routes[route]
    if held and held.seen >= seen then return false end
    routes[route] = { epoch = epoch, seen = seen }
    Store()[shard] = routes
    return true
end

-- The sightings shared for a shard ({ [route] = { epoch, seen } }), for Context.lua.
function Share.For(shard)
    return shard and Store()[shard] or nil
end

------------------------------------------------------------------------
-- Sending (Mapzeroth's queue)
------------------------------------------------------------------------

local function Drain()
    local msg, id = queue[1], ChannelIndex()
    if not msg or not id or not On() then
        sending = false
        return
    end
    local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", id)
    -- Older clients return a boolean, newer ones Enum.SendAddonMessageResult (0 = success).
    if ok and (r == nil or r == true or r == 0) then
        table.remove(queue, 1)
        C_Timer.After(SEND_GAP, Drain)
    elseif ok and (r == 3 or r == 8) then -- AddonMessageThrottle, ChannelThrottle: wait it out
        C_Timer.After(THROTTLE_PAUSE, Drain)
    else
        table.remove(queue, 1)
        C_Timer.After(SEND_GAP, Drain)
    end
end

local function Send(msg)
    if not On() then return end
    queue[#queue + 1] = msg
    if not sending and C_Timer then
        sending = true
        Drain()
    end
end
Share.Sent = queue -- for tests: what waits to go

local function SightingMessage(shard, route, a)
    return ("S:%s:%s:%d:%.0f:%d"):format(VERSION, shard, route, a.epoch, a.seen)
end

local function Ask(shard)
    if not shard or asked[shard] then return end
    asked[shard] = true
    Send(("Q:%s:%s"):format(VERSION, shard))
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------

local function Answer(shard)
    local token = {}
    answering[shard] = token
    local own = false
    for route in pairs(Store()[shard] or {}) do
        if lastSent[route] then own = true end
    end
    local wait = own and REPLY_MINE or REPLY_OTHERS
    C_Timer.After(wait[1] + math.random() * (wait[2] - wait[1]), function()
        if answering[shard] ~= token then return end -- someone answered first
        answering[shard] = nil
        local n = 0
        for route, a in pairs(Store()[shard] or {}) do
            if n >= MAX_REPLY then break end
            Send(SightingMessage(shard, route, a))
            n = n + 1
        end
    end)
end

-- One message from the channel (exposed for tests). Returns true when it was taken in.
function Share.OnMessage(text)
    if type(text) ~= "string" or #text > 200 then return false end
    local kind, version, rest = text:match("^(%u):(%d+):(.*)$")
    if version ~= VERSION then return false end
    if kind == "Q" then
        local shard = rest:match("^(%d+)$")
        if not shard then return false end
        asked[shard] = true -- the answers reach us too
        if Store()[shard] and next(Store()[shard]) and not answering[shard] then Answer(shard) end
        return true
    elseif kind == "S" then
        local shard, route, epoch, seen = rest:match("^(%d+):(%d+):(%d+):(%d+)$")
        route, epoch, seen = tonumber(route), tonumber(epoch), tonumber(seen)
        if not (shard and route and epoch and seen and ns.Routes[route]) then return false end
        local now = GetServerTime()
        if seen > now + FUTURE or seen < now - KEEP then return false end
        local new = Keep(shard, route, epoch, seen)
        if not new then answering[shard] = nil end -- what we'd have said has been said
        if new and ns.Drift then ns.Drift.Compare(route, { epoch = epoch, seen = seen }, shard) end
        return new
    end
    return false
end

------------------------------------------------------------------------
-- Your own rides
------------------------------------------------------------------------

-- A ride was recorded: once it's settled (OWN_DELAY), send it for each shard you were on during it. Shard ids are per
-- zone, so a ride from Durotar to Stranglethorn goes out under both: whoever plans at either end can use it.
local MAX_SHARDS = 3

local function OwnRide()
    if not On() then return end
    C_Timer.After(OWN_DELAY, function()
        if not On() then return end
        for route, a in pairs(ns.Timetable.Anchors()) do
            local r = ns.Routes[route]
            if a.seen and a.seen > GetServerTime() - 600 and lastSent[route] ~= a.seen and r and r.period then
                lastSent[route] = a.seen
                local shards = ns.Shard.Since(a.seen - r.period / 1000)
                for i = math.max(1, #shards - MAX_SHARDS + 1), #shards do
                    Keep(shards[i], route, a.epoch, a.seen)
                    Send(SightingMessage(shards[i], route, a))
                end
            end
        end
    end)
end

------------------------------------------------------------------------
-- The channel (Mapzeroth's)
------------------------------------------------------------------------

local function HideFromChat()
    local name = ChannelName()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.RemoveChannel then
            pcall(frame.RemoveChannel, frame, name)
        elseif frame and ChatFrame_RemoveChannel then
            pcall(ChatFrame_RemoveChannel, frame, name)
        end
    end
end

local function ShownChannels()
    local shown = {}
    if not GetChatWindowChannels then return shown end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local list = { GetChatWindowChannels(i) }
        for j = 1, #list, 2 do
            if type(list[j]) == "string" then shown[list[j]:lower()] = true end
        end
    end
    return shown
end

-- The numbers of the channels people chat in (the game's own, and custom ones shown in a chat window), lowest first.
local function ChatChannelNumbers()
    local out = {}
    if not (GetNumDisplayChannels and GetChannelDisplayInfo) then return out end
    local shown = ShownChannels()
    for i = 1, GetNumDisplayChannels() or 0 do
        local name, header, _, number, _, _, category = GetChannelDisplayInfo(i)
        local chat = category == "CHANNEL_CATEGORY_WORLD"
            or (category == "CHANNEL_CATEGORY_CUSTOM" and type(name) == "string" and shown[name:lower()])
        if not header and type(number) == "number" and number > 0 and chat then out[#out + 1] = number end
    end
    table.sort(out)
    return out
end

-- Move ours past every chat channel numbered above it, so General, Trade and the rest keep /1, /2, /3.
local function KeepChannelLast()
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    local ours = ChannelIndex()
    if not swap or not ours then return end
    for _, n in ipairs(ChatChannelNumbers()) do
        if n > ours then
            if swapsLeft <= 0 or not pcall(swap, ours, n) then return end
            swapsLeft = swapsLeft - 1
            ours = n
        end
    end
end

local function Join()
    if not On() or ChannelIndex() or clean(IsInInstance()) then return end
    reorderUntil, swapsLeft = GetTime() + REORDER_SECONDS, MAX_SWAPS
    pcall(JoinTemporaryChannel, ChannelName())
    C_Timer.After(1, HideFromChat)
    C_Timer.After(5, HideFromChat)
    C_Timer.After(3, function() Ask(ns.Shard.Current()) end)
end

local function Start(atLogin)
    if not On() then return end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    if started then
        Join()
        return
    end
    started = true
    local function begin()
        swapsLeft = MAX_SWAPS
        KeepChannelLast()
        Join()
        C_Timer.NewTicker(REJOIN_SECONDS, function()
            Join()
            Ask(ns.Shard.Current()) -- a new shard since: ask about it once
        end)
    end
    if not atLogin then
        begin()
        return
    end
    -- At login the game's own channels come in first: wait until the list has settled.
    local since, changedAt, last = GetTime(), GetTime(), -1
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        local now, count = GetTime(), select("#", GetChannelList())
        if count ~= last then last, changedAt = count, now end
        if (count > 0 and now - changedAt >= SETTLE_SECONDS) or now - since >= SETTLE_MAX then
            ticker:Cancel()
            begin()
        end
    end)
end

function Share.SetOn(on)
    ns.db.share = on and true or false
    if on then
        Start(false)
    else
        wipe(queue)
        local name = ChannelName()
        if ChannelIndex() and LeaveChannelByName then pcall(LeaveChannelByName, name) end
    end
end

function Share.State()
    local count = 0
    for _, routes in pairs(Store()) do for _ in pairs(routes) do count = count + 1 end end
    return { on = On(), joined = ChannelIndex() ~= nil, shard = ns.Shard.Current(), sightings = count }
end

ns.Init(function()
    Prune()
    ns.Timetable.OnChange(OwnRide)
    if not CreateFrame then return end
    local frame = CreateFrame("Frame")
    if not frame.RegisterEvent then return end
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("CHANNEL_UI_UPDATE")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            if not On() then return end
            local prefix, text, _, sender = ...
            prefix, text, sender = clean(prefix), clean(text), clean(sender)
            if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
            if not me[Ambiguate(sender, "none")] then Share.OnMessage(text) end
        elseif event == "CHANNEL_UI_UPDATE" then
            if reorderUntil and GetTime() < reorderUntil then KeepChannelLast() end
        elseif event == "PLAYER_LOGIN" then
            -- On Forever, UnitName gives first name and surname apart; senders show as "First Surname".
            local name, surname = UnitName("player")
            if name then me[name] = true end
            if name and surname and surname ~= "" then me[name .. " " .. surname] = true end
            Start(true)
        elseif event == "PLAYER_LOGOUT" then
            Prune()
        end
    end)
end)
