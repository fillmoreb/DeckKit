-- MarketDeck: auction house prices, with nothing to press. Opening the auction house takes a snapshot of
-- every auction (C_AuctionHouse.ReplicateItems, Blizzard's whole-house query, allowed every 15 minutes)
-- when the last one is over an hour old, and boils it down to the lowest buyout per item and how many
-- are up. Prices are kept per auction house (realm + Alliance, Horde or the goblins' neutral one),
-- account-wide, with each day's lowest price for two weeks: the market price is the middle of those.
--
-- Core.lua: prices and houses, the settings, /deckkit market. Scan.lua takes the snapshot, Progress.lua
-- shows it going; Disenchant.lua values disenchanting, Tooltip.lua puts it all on item tooltips.
--
-- For other addons:
--   MarketDeck_GetPrice(itemID) -> nil, or { now = copper, quantity = n, market = copper, days = n,
--       scanned = server time, vendor = copper or nil, disenchant = copper or nil } (this house)
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffffd100MarketDeck|r")

ns.RESCAN_AFTER = 3600 -- seconds: an older snapshot is retaken when the auction house opens
ns.KEEP_DAYS = 14

local db -- MarketDeckDB (also ns.db), from login
-- Goblin towns' auction houses are neutral (one house for both factions): their zones' maps.
local NEUTRAL_ZONES = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn, Tanaris, Winterspring

local function Now() return GetServerTime and GetServerTime() or time() end
local function Today() return math.floor(Now() / 86400) end
ns.Now, ns.Today = Now, Today

-- "1,234,567"
function ns.Thousands(n)
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then return s end
    end
end

-- The auction house you're at (or would be): realm plus Alliance, Horde or Neutral (the goblin towns).
function ns.HouseKey()
    local side = UnitFactionGroup("player") or "?"
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if not map or map == 0 then break end
        if NEUTRAL_ZONES[map] then side = "Neutral" break end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    return (GetRealmName() or "?") .. "-" .. side
end

-- ns.houseKey: the house prices are read from: the last one opened, else this character's faction's.

local function House(key)
    key = key or ns.houseKey or ((GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?"))
    db.houses[key] = db.houses[key] or { scanned = 0, now = {}, days = {} }
    return db.houses[key]
end
ns.House = House

------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------

-- days[itemID] is "day:copper day:copper ..." (newest last), one entry per day: that day's lowest.
function ns.Days(h, id)
    local out = {}
    for day, copper in (h.days[id] or ""):gmatch("(%d+):(%d+)") do out[#out + 1] = { tonumber(day), tonumber(copper) } end
    return out
end

local function Median(list)
    if #list == 0 then return nil end
    table.sort(list)
    local m = math.floor((#list + 1) / 2)
    if #list % 2 == 0 then return math.floor((list[m] + list[m + 1]) / 2) end
    return list[m]
end

function ns.Price(id, key)
    local h = House(key)
    local now = h.now[id]
    local lowest, qty
    if now then lowest, qty = now:match("(%d+):(%d+)") end
    local prices, cutoff = {}, Today() - ns.KEEP_DAYS
    for _, d in ipairs(ns.Days(h, id)) do
        if d[1] > cutoff then prices[#prices + 1] = d[2] end
    end
    if not lowest and #prices == 0 then return nil end
    return { now = tonumber(lowest), quantity = tonumber(qty) or 0, market = Median(prices), days = #prices,
        scanned = h.scanned }
end

------------------------------------------------------------------------
-- Setup, settings, commands
------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    MarketDeckDB = MarketDeckDB or {}
    db = MarketDeckDB
    db.houses = db.houses or {}
    ns.db = db
end)

-- DeckKit's live numbers (DeckKit.Measures) value items at the auction price: the market median, else the lowest now.
if DeckKit.Prices then
    DeckKit.Prices.Provide(function(itemID)
        local p = db and ns.Price(itemID)
        return p and (p.market or p.now) or nil
    end)
end

function MarketDeck_GetPrice(itemID)
    if not db or type(itemID) ~= "number" then return nil end
    local p = ns.Price(itemID)
    if p then
        p.vendor = ns.Vendor(itemID)
        p.disenchant = ns.Disenchant and ns.Disenchant(itemID)
    else
        local vendor, de = ns.Vendor(itemID), ns.Disenchant and ns.Disenchant(itemID)
        if vendor or de then p = { vendor = vendor, disenchant = de } end
    end
    return p
end

function ns.Vendor(itemID)
    local sell = select(11, C_Item.GetItemInfo(itemID))
    return (sell and sell > 0) and sell or nil
end

local function Ago(t)
    if not t or t == 0 then return "never" end
    local m = math.floor((Now() - t) / 60)
    if m < 60 then return m .. " min ago" end
    if m < 2880 then return math.floor(m / 60) .. " h ago" end
    return math.floor(m / 1440) .. " days ago"
end

ns.AddSettings({
    { type = "section", tab = "Tools", label = "Auction prices" },
    { type = "toggle", label = "Scan when the auction house opens",
      hint = "Takes a snapshot of every auction when you open the auction house, if the last one is over an "
          .. "hour old (Blizzard allows one every 15 minutes). Prices are kept per auction house, for all your "
          .. "characters.",
      get = function() return db.autoScan ~= false end, set = function(on) db.autoScan = on end },
    { type = "toggle", label = "Ring the bell when a snapshot is done",
      hint = "The boat-docked bell, as the scan bar finishes.",
      get = function() return db.bell ~= false end, set = function(on) db.bell = on end },
    { type = "toggle", label = "Prices in item tooltips",
      hint = "Auction (lowest now, and the two-week market price), vendor, and disenchant value.",
      get = function() return db.tooltips ~= false end, set = function(on) db.tooltips = on end },
    { type = "status", label = "Last snapshot",
      get = function() return Ago(House().scanned) end },
})

ns.AddCommand("market", function(arg)
    local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if word == "test" and rest ~= "" then
        local mode, value = rest:match("^(%S+)%s*(%S*)")
        return ns.ProgressTestFinish(mode, value)
    end
    if arg == "test" then return ns.ProgressTest() end
    if arg == "scan" then
        if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return ns.Print("open the auction house first") end
        ns.houseKey = ns.HouseKey()
        return ns.Scan(true)
    end
    local h = House()
    local n = 0
    for _ in pairs(h.now) do n = n + 1 end
    ns.Print(("%s: %d items priced, last snapshot %s"):format(ns.houseKey or "this auction house", n, Ago(h.scanned)))
    local t = db.lastTiming
    if t and t.wait then
        ns.Print(("last snapshot: %.0f s waiting for the server, %.1f s reading %d auctions"):format(t.wait, t.read or 0,
            t.auctions or 0))
    end
end, "MarketDeck: auction prices (scan: take a snapshot now, with the auction house open; test: show the bar)")
