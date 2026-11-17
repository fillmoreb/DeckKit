-- AuctionPad's pricing: what to ask for an item, from what's listed now, the market price and the vendor's.
--
--   Pricing.Suggest(info) -> price (copper, per item), reason
--     info = { commodity = true (stackable: sold by unit price) or false (gear),
--              listings = { { price, quantity, mine }, ... } (others' and yours; sorted or not),
--              vendor = copper or nil, market = copper or nil, last = copper or nil,
--              preset = "undercut" (default) | "market" | "last" | "vendor" }
--     reasons: "undercut" (1c under the lowest), "match" (the lowest), "market", "last", "vendor" (vendor x1.5),
--              "none" (nothing to go on)
--   Pricing.Earns(price, quantity) -> copper after the auction house's cut: 5% of the sale, rounded down (Ben's own
--                                     invoices, 2026-11-17: 19 Rough Stone sold for 152c, cut 7c, not 8)
--   Pricing.Cut(sale) -> that cut, for a whole sale
--   Pricing.VendorIt(price, vendor) -> true when selling to a vendor is about as good (the cut eats the difference)
--   Pricing.Step(price) -> the price step the d-pad moves by: two significant figures (27c by 1c, 6s 20c by 10c)
--
-- The rule (Ben, 2026-11-17):
--   * Gear: undercut the lowest by 1c. Buyers see a list sorted by price and take the top.
--   * Stackables: buyers fill from the cheapest up, the oldest first at one price, so matching waits behind the rest.
--     Undercut by 1c when that's under 1% of the price (nearly free, and you jump the queue); otherwise match.
--   * A bait floor (the cheapest price holds under 5% of what's listed and sits more than 15% below the next price)
--     is ignored: it sells first anyway, so price against the next one up.
--   * Your own listings are never what you undercut.
local _, ns = ...

local Pricing = {}
ns.Pricing = Pricing
AuctionPadPricingForTests = Pricing -- (the offline tests reach it here; harmless otherwise)

local CUT = 0.05
local VENDOR_MARGIN = 1.3 -- the auction house must earn this much more than the vendor to be worth the trouble
local BAIT_SHARE, BAIT_GAP = 0.05, 0.15
local UNDERCUT_MAX = 0.01 -- a 1c undercut on a stackable is taken when it costs under 1% of the price

function Pricing.Cut(sale) return math.floor(sale * CUT) end
function Pricing.Earns(price, quantity)
    local sale = price * (quantity or 1)
    return sale - Pricing.Cut(sale)
end

function Pricing.VendorIt(price, vendor)
    if not (vendor and vendor > 0) then return false end
    if not price or price <= 0 then return true end
    return price * (1 - CUT) < vendor * VENDOR_MARGIN
end

function Pricing.Step(price)
    if not price or price < 100 then return 1 end
    return 10 ^ (math.floor(math.log10(price)) - 1)
end

-- Others' listings grouped by price, cheapest first: { { price, quantity }, ... }.
local function Tiers(listings)
    local by, out = {}, {}
    for _, l in ipairs(listings or {}) do
        if not l.mine and l.price and l.price > 0 then
            by[l.price] = (by[l.price] or 0) + (l.quantity or 1)
        end
    end
    for price, quantity in pairs(by) do out[#out + 1] = { price = price, quantity = quantity } end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end
Pricing.Tiers = Tiers

-- The price to beat: the lowest, unless it's bait.
local function Floor(tiers)
    local first, second = tiers[1], tiers[2]
    if not first then return nil end
    if second then
        local total = 0
        for _, t in ipairs(tiers) do total = total + t.quantity end
        if first.quantity < total * BAIT_SHARE and first.price < second.price * (1 - BAIT_GAP) then return second.price end
    end
    return first.price
end
Pricing.Floor = Floor

function Pricing.Suggest(info)
    local preset = info.preset or "undercut"
    if preset == "market" and info.market then return info.market, "market" end
    if preset == "last" and info.last then return info.last, "last" end
    if preset == "vendor" and info.vendor then return math.ceil(info.vendor * 1.5), "vendor" end
    local floor = Floor(Tiers(info.listings))
    if not floor then
        if info.market then return info.market, "market" end
        if info.last then return info.last, "last" end
        if info.vendor then return math.ceil(info.vendor * 1.5), "vendor" end
        return nil, "none"
    end
    if floor <= 1 then return 1, "match" end
    if not info.commodity or 1 / floor < UNDERCUT_MAX then return floor - 1, "undercut" end
    return floor, "match"
end

-- The presets X cycles through, in order.
Pricing.PRESETS = { "undercut", "market", "last", "vendor" }
Pricing.PRESET_LABEL = { undercut = "Beat the lowest", market = "Market price", last = "Last time", vendor = "Vendor x1.5" }
