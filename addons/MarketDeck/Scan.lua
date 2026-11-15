-- MarketDeck's snapshot: C_AuctionHouse.ReplicateItems (the whole house in one query, allowed every 15
-- minutes) when the auction house opens and the last snapshot is over an hour old, read a few
-- milliseconds a frame (a big house has a quarter of a million auctions) and boiled down to each
-- item's lowest buyout and how many are up, plus the day's lowest for the two-week market price.
--   ns.Scan(force)   take one now (force: even if the last is recent)
local _, ns = ...

local BUDGET_MS = 5 -- milliseconds of each frame spent reading auctions, so a big house never hitches
local CHECK_EVERY = 100 -- auctions read between looks at the clock

local scanning, scanKey, lowest, counts, index, total
local scanId = 0 -- each snapshot asked for gets the next number: a late timeout only ends its own
local askedAt, readAt -- GetTime() when the snapshot was asked for, and when it arrived

local function Finish()
    local h, today, cutoff = ns.House(scanKey), ns.Today(), ns.Today() - ns.KEEP_DAYS
    h.now = {}
    for id, copper in pairs(lowest) do
        h.now[id] = copper .. ":" .. counts[id]
        local kept, todays = {}, copper
        for _, d in ipairs(ns.Days(h, id)) do
            if d[1] == today then todays = math.min(todays, d[2])
            elseif d[1] > cutoff then kept[#kept + 1] = d[1] .. ":" .. d[2] end
        end
        kept[#kept + 1] = today .. ":" .. todays
        h.days[id] = table.concat(kept, " ")
    end
    h.scanned = ns.Now()
    ns.db.lastTiming = { wait = readAt and askedAt and (readAt - askedAt) or nil, read = readAt and (GetTime() - readAt),
        auctions = total }
    local n = 0
    for _ in pairs(lowest) do n = n + 1 end
    ns.ProgressDone(("prices updated: %s auctions, %s items"):format(ns.Thousands(total), ns.Thousands(n)), true)
    scanning, lowest, counts = nil, nil, nil
end

local reader = CreateFrame("Frame")
reader:Hide()
reader:SetScript("OnUpdate", function(self)
    -- As many as fit in BUDGET_MS this frame (a fixed count would be slow on a fast frame and could hitch
    -- on a slow one; a big house has a quarter of a million auctions).
    local started, stop = debugprofilestop(), index - 1
    while stop < total - 1 and debugprofilestop() - started < BUDGET_MS do
        local from = stop + 1
        stop = math.min(from + CHECK_EVERY - 1, total - 1)
        for i = from, stop do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local each = math.floor(buyout / count)
                if not lowest[itemID] or each < lowest[itemID] then lowest[itemID] = each end
                counts[itemID] = (counts[itemID] or 0) + count
            end
        end
    end
    index = stop + 1
    ns.Progress("reading auctions", total > 0 and index / total or 1, { index, total })
    if index >= total then
        self:Hide()
        Finish()
    end
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if scanning ~= "asked" then return end
    scanning, lowest, counts, index = "reading", {}, {}, 0
    readAt = GetTime()
    total = C_AuctionHouse.GetNumReplicateItems() or 0
    ns.Progress("reading auctions", 0, { 0, total })
    reader:Show()
end)

function ns.Scan(force)
    if scanning then return end
    local h = ns.House(ns.houseKey)
    if not force and ns.Now() - (h.scanned or 0) < ns.RESCAN_AFTER then return end
    scanId = scanId + 1
    local id = scanId
    scanKey, scanning, askedAt = ns.houseKey, "asked", GetTime()
    ns.Progress("Asking the auction house for prices...", nil)
    C_AuctionHouse.ReplicateItems()
    C_Timer.After(120, function()
        -- Refused (the 15-minute limit), or the server never answered. Only this snapshot's timeout: one
        -- from a snapshot given up when the auction house closed mustn't end a newer one.
        if id == scanId and scanning == "asked" then
            scanning = nil
            ns.ProgressDone("no auction snapshot this time (the auction house allows one every 15 minutes)", false)
        end
    end)
end

ns.On("AUCTION_HOUSE_SHOW", function()
    ns.houseKey = ns.HouseKey()
    if ns.db.autoScan ~= false then ns.Scan() end
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if scanning == "reading" then return end -- the snapshot is already here: let it finish
    if scanning == "asked" then ns.ProgressDone("the auction house closed before the snapshot came", false) end
    scanning = nil
end)
