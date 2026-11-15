-- MarketDeck: what an item is worth disenchanted, at this auction house's prices: the chance of each
-- material times how many on average, times its price. The odds are Classic's disenchanting tables
-- (warcraft.wiki.gg "Disenchanting tables"); Forever may differ a little, so it's shown as an estimate.
-- Uncommon, rare and epic armor and weapons only, item level 5-65.
local _, ns = ...

-- Materials (item IDs).
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LMAGIC, GMAGIC, LASTRAL, GASTRAL, LMYSTIC, GMYSTIC = 10938, 10939, 10998, 11082, 11134, 11135
local LNETHER, GNETHER, LETERNAL, GETERNAL = 11174, 11175, 16202, 16203
local SGLIM, LGLIM, SGLOW, LGLOW, SRAD, LRAD, SBRIL, LBRIL, NEXUS = 10978, 11084, 11138, 11139, 11177, 11178,
    14343, 14344, 20725

-- Uncommon armor: { up to item level, { material, chance, min, max }, ... }. Weapons swap the dust and
-- essence chances (WEAPON below).
local UNCOMMON = {
    { 15, { STRANGE, .80, 1, 2 }, { LMAGIC, .20, 1, 2 } },
    { 20, { STRANGE, .75, 2, 3 }, { GMAGIC, .20, 1, 2 }, { SGLIM, .05, 1, 1 } },
    { 25, { STRANGE, .75, 4, 6 }, { LASTRAL, .15, 1, 2 }, { SGLIM, .10, 1, 1 } },
    { 30, { SOUL, .75, 1, 2 }, { GASTRAL, .20, 1, 2 }, { LGLIM, .05, 1, 1 } },
    { 35, { SOUL, .75, 2, 5 }, { LMYSTIC, .20, 1, 2 }, { SGLOW, .05, 1, 1 } },
    { 40, { VISION, .75, 1, 2 }, { GMYSTIC, .20, 1, 2 }, { LGLOW, .05, 1, 1 } },
    { 45, { VISION, .75, 2, 5 }, { LNETHER, .20, 1, 2 }, { SRAD, .05, 1, 1 } },
    { 50, { DREAM, .75, 1, 2 }, { GNETHER, .20, 1, 2 }, { LRAD, .05, 1, 1 } },
    { 55, { DREAM, .75, 2, 5 }, { LETERNAL, .20, 1, 2 }, { SBRIL, .05, 1, 1 } },
    { 60, { ILLUSION, .75, 1, 2 }, { GETERNAL, .20, 1, 2 }, { LBRIL, .05, 1, 1 } },
    { 65, { ILLUSION, .75, 2, 5 }, { GETERNAL, .20, 2, 3 }, { LBRIL, .05, 1, 1 } },
}
-- Weapons: dust and essence chances by level band (shards 3% from 51 up).
local WEAPON = {
    [15] = { .20, .80, 0 }, [20] = { .20, .75, .05 }, [25] = { .15, .75, .10 }, [30] = { .20, .75, .05 },
    [35] = { .20, .75, .05 }, [40] = { .20, .75, .05 }, [45] = { .20, .75, .05 }, [50] = { .20, .75, .05 },
    [55] = { .22, .75, .03 }, [60] = { .22, .75, .03 }, [65] = { .22, .75, .03 },
}
local RARE = { { 25, SGLIM }, { 30, LGLIM }, { 35, SGLOW }, { 40, LGLOW }, { 45, SRAD }, { 50, LRAD }, { 55, SBRIL },
    { 65, LBRIL } }
local EPIC = { { 45, { SRAD, 1, 2, 4 } }, { 50, { LRAD, 1, 2, 4 } }, { 55, { SBRIL, 1, 2, 4 } },
    { 60, { NEXUS, 1, 1, 1 } }, { 65, { NEXUS, 1, 1, 2 } } }

local function Band(list, ilvl)
    for _, row in ipairs(list) do if ilvl <= row[1] then return row end end
end

-- The results of disenchanting: { { material, chance, min, max }, ... } or nil if it can't be.
function ns.DisenchantResults(itemID)
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= 2 and classID ~= 4 then return nil end
    local _, _, quality, ilvl = C_Item.GetItemInfo(itemID)
    if not quality or not ilvl or ilvl < 5 or ilvl > 65 then return nil end
    if quality == 2 then
        local row = Band(UNCOMMON, ilvl)
        if not row then return nil end
        local out = {}
        for i = 2, #row do out[#out + 1] = { row[i][1], row[i][2], row[i][3], row[i][4] } end
        if classID == 2 then -- weapon: its own dust / essence / shard chances
            local w = WEAPON[row[1]]
            for i, r in ipairs(out) do r[2] = w[i] end
        end
        return out
    elseif quality == 3 then
        local row = Band(RARE, ilvl)
        if not row then return nil end
        if row[2] == LBRIL then return { { LBRIL, .995, 1, 1 }, { NEXUS, .005, 1, 1 } } end
        return { { row[2], 1, 1, 1 } }
    elseif quality == 4 then
        local row = ilvl >= 40 and Band(EPIC, ilvl)
        if not row then return nil end
        return { { row[2][1], 1, row[2][3], row[2][4] } }
    end
end

-- Expected value in copper at this house's prices (market price, else the lowest now); nil when it
-- can't be disenchanted or none of its materials has a price yet.
function ns.Disenchant(itemID)
    local results = ns.DisenchantResults(itemID)
    if not results then return nil end
    local total, priced = 0, false
    for _, r in ipairs(results) do
        local p = ns.Price(r[1])
        local each = p and (p.market or p.now)
        if each then
            total = total + r[2] * (r[3] + r[4]) / 2 * each
            priced = true
        end
    end
    return priced and math.floor(total + 0.5) or nil
end
