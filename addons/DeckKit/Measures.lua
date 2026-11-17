-- DeckKit.Measures: numbers a display can follow live ("Light Leather looted since I started", "XP per hour",
-- "what my haul is worth"), read from DeckKit.Ledger and the game. Like DeckKit.Conditions, a measure is a plain
-- table (it can come from JSON) and nothing in it is run as code.
--
--   { measure = "looted", item = 2318 }     items looted (gathering, drops, quest rewards); no item: all of them
--   { measure = "created", item = 2318 }    items crafted
--   { measure = "coin" }                    coin looted (copper)
--   { measure = "money" }                   net change to your money (copper; sales and spending too)
--   { measure = "xp" }                      XP gained
--   { measure = "rep", faction = "Nightclaw Druids" }   reputation gained (no faction: all)
--   { measure = "skill", skill = "Mining" } skill points gained (no skill: all)
--   { measure = "quests" }                  quests turned in
--   { measure = "elapsed" }                 seconds since the start
--   { measure = "carried", item = 2318 }    how many you carry now (bags)
--   { measure = "value", of = <measure> }   what an item measure is worth in copper (auction price where a price
--                                           addon gives one, else vendor); coin and money are their own value
--   { measure = "sum", of = { <measure>, ... } }
-- Shared fields:
--   since = "haul"            from a named mark (DeckKit.Ledger.Mark); since = { minutes = 60 } the last hour;
--                             left out: since this session began
--   scope = "account"         every character's totals (and the account's own marks), not just this one's
--   per = "hour" / "minute"   a rate over the time since the start (nil in its first minute)
--
--   Measures.Value(m)            the number, or nil when it can't be told (an unknown measure, an unset mark)
--   Measures.Format(v, format)   text: "count" (1,234), "rate" (36/h), "money" (3s 78c), "time" (23 min)
--   DeckKit.Prices.Provide(fn)   a price addon registers fn(itemID) -> copper (or nil); MarketDeck does
--   DeckKit.Prices.Of(itemID)    that price, else the vendor price, else nil
local _, ns = ...

local M = {}
ns.Measures = M
local L = ns.Ledger

local Prices = {}
ns.Prices = Prices
local providers = {}
function Prices.Provide(fn) providers[#providers + 1] = fn end
function Prices.Of(id)
    if type(id) ~= "number" then return nil end
    for _, fn in ipairs(providers) do
        local ok, v = pcall(fn, id)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    local sell = C_Item and C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
    return (type(sell) == "number" and sell > 0) and sell or nil
end

-- The start a measure counts from (server time), or nil if its mark isn't set.
local function Since(m)
    local s = m.since
    if s == nil then return L.SessionStart() end
    if type(s) == "string" then return L.MarkTime(s, m.scope) end
    if type(s) == "table" and tonumber(s.minutes) then return GetServerTime() - tonumber(s.minutes) * 60 end
end

local function Sum(t, key)
    if key ~= nil then return t[key] or 0 end
    local n = 0
    for _, v in pairs(t) do n = n + v end
    return n
end

local TOTALS = { looted = { "loot", "item" }, created = { "created", "item" }, coin = { "coin" }, money = { "money" },
                 xp = { "xp" }, rep = { "rep", "faction" }, skill = { "skill", "skill" }, quests = { "quest" } }

local Value

local function Raw(m, since)
    local kind = m.measure
    local t = TOTALS[kind]
    if t then
        return Sum(L.Totals(t[1], since, m.scope), t[2] and m[t[2]] or nil)
    end
    if kind == "elapsed" then return GetServerTime() - since end
    if kind == "carried" then
        local n = C_Item and C_Item.GetItemCount and tonumber(m.item) and C_Item.GetItemCount(tonumber(m.item))
        return type(n) == "number" and n or nil
    end
    if kind == "value" then
        local of = type(m.of) == "table" and m.of
        if not of then return nil end
        if of.measure == "coin" or of.measure == "money" then return Value(of) end
        local ot = TOTALS[of.measure]
        if not (ot and ot[2] == "item") and of.measure ~= "carried" then return nil end
        if of.item then
            local n, price = Value(of), Prices.Of(tonumber(of.item))
            if not n then return nil end
            return price and n * price or 0
        end
        local copper = 0 -- every item looted/created: each at its own price
        local ofSince = Since(of)
        if not ofSince then return nil end
        for id, n in pairs(L.Totals(ot[1], ofSince, of.scope)) do copper = copper + n * (Prices.Of(id) or 0) end
        return copper
    end
    if kind == "sum" then
        if type(m.of) ~= "table" then return nil end
        local n = 0
        for _, part in ipairs(m.of) do n = n + (Value(part) or 0) end
        return n
    end
end

Value = function(m)
    if type(m) ~= "table" then return nil end
    local since = Since(m)
    if not since then return nil end
    local v = Raw(m, since)
    if v == nil or not m.per then return v end
    local seconds = GetServerTime() - since
    if seconds < 60 then return nil end
    return v / seconds * (m.per == "minute" and 60 or 3600)
end
M.Value = Value

local function Thousands(n)
    local s = tostring(math.floor(math.abs(n) + 0.5))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end

local function Money(c)
    local neg, n = c < 0, math.floor(math.abs(c) + 0.5)
    local g, s, cu = math.floor(n / 10000), math.floor(n / 100) % 100, n % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = Thousands(g) .. "g" end
    if s > 0 or g > 0 then parts[#parts + 1] = s .. "s" end
    if g == 0 then parts[#parts + 1] = cu .. "c" end -- copper only matters below a gold
    return (neg and "-" or "") .. table.concat(parts, " ")
end

function M.Format(v, format, per)
    if v == nil then return "…" end
    if format == "money" then return Money(v) .. (per and ("/" .. (per == "minute" and "m" or "h")) or "") end
    if format == "time" then
        local minutes = math.floor(v / 60)
        if minutes < 60 then return minutes .. " min" end
        return ("%d:%02d h"):format(math.floor(minutes / 60), minutes % 60)
    end
    if format == "rate" or per then
        local n = v < 10 and (math.floor(v * 10 + 0.5) / 10) or math.floor(v + 0.5)
        return tostring(n) .. "/" .. (per == "minute" and "m" or "h")
    end
    return Thousands(v)
end
