-- MarketDeck: prices on item tooltips (any tooltip that shows an item: bags, loot, chat links, the quest
-- log's rewards, the auction house itself).
--   Auction (how many up)    the lowest now, and the two-week market price when there's history
--   Vendor     what a vendor pays (in place of Blizzard's own "Sell Price:" line)
--   Disenchant the estimated value of its materials at this house (Classic's odds)
local _, ns = ...

local function Money(copper) return GetMoneyString(copper, true) end

local function Add(tooltip, data)
    if not (MarketDeckDB and MarketDeckDB.tooltips ~= false) then return end
    local id = data and data.id
    if type(id) ~= "number" or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    local p = ns.Price(id)
    if p then
        -- How many are up goes with the label, so the price alone sits on the right, in line with the
        -- vendor and disenchant prices.
        local label = "Auction" .. (p.quantity > 0 and ("  |cff9d9d9d(" .. p.quantity .. " up)|r") or "")
        tooltip:AddDoubleLine(label, p.now and Money(p.now) or "|cff9d9d9dnone up|r", 1, 0.82, 0, 1, 1, 1)
        if p.market and p.days >= 2 then
            tooltip:AddDoubleLine("  " .. p.days .. "-day market", Money(p.market), 0.6, 0.6, 0.6, 1, 1, 1)
        end
    end
    local vendor = ns.Vendor(id)
    if vendor then tooltip:AddDoubleLine("Vendor", Money(vendor), 1, 0.82, 0, 1, 1, 1) end
    local de = ns.Disenchant(id)
    if de then tooltip:AddDoubleLine("Disenchant", Money(de), 1, 0.82, 0, 1, 1, 1) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Add)
end

-- Blizzard's own "Sell Price:" line duplicates the Vendor line: skipped (a line pre-call returning true
-- skips it) while MarketDeck's tooltip prices are on; with them off, Blizzard's line is back.
if TooltipDataProcessor and TooltipDataProcessor.AddLinePreCall and Enum.TooltipDataLineType
    and Enum.TooltipDataLineType.SellPrice then
    TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.SellPrice, function()
        return MarketDeckDB ~= nil and MarketDeckDB.tooltips ~= false
    end)
end
