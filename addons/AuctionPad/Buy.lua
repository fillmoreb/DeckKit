-- AuctionPad's Buy tab: browse by Blizzard's own categories, filter, pick, buy.
--   Left: a Search box (DeckKit's text box: A types, the Deck's keyboard is Steam + X; Decky can fill it), then the
--         categories: A opens one (and browses it), B or d-pad left goes back up.
--   Top: level from and to (0: any), rarity, "Usable by me" (remembered).
--   Right: what's for sale, cheapest first, with a "deal" mark when it's well under MarketDeck's market price.
--   A on a result: its listings. Stackables: choose how many, A gets the game's quote, A again buys. Gear: one row
--   per auction, A buys that one (after a yes). B goes back to the results.
-- Buying needs a real press (the game's rule): every purchase happens inside an A press.
local _, ns = ...

local UI = DeckKit.UI

local LEFT_W, RIGHT_W, ROW_H = 230, 590, 28
local DEAL = 0.8 -- under 80% of the market price is a deal
local RARITY = { { 0, "Any rarity" }, { 1, "Common+" }, { 2, "Uncommon+" }, { 3, "Rare+" }, { 4, "Epic+" } }
-- How results are ordered: by the auction house itself (so it covers them all), cheapest first within a level or name.
local SORTS = { { "price", "Price" }, { "level", "Level" }, { "name", "Name" } }
local function Sorts()
    local O = Enum.AuctionHouseSortOrder
    local by = ns.db.sort or "price"
    local price = { sortOrder = O.Price, reverseSort = false }
    if by == "level" then return { { sortOrder = O.Level, reverseSort = false }, price } end
    if by == "name" then return { { sortOrder = O.Name, reverseSort = false }, price } end
    return { price }
end

local tab, catList, resList, emptyText, header, searchBox
local catRows, resRows = {}, {}
local path = {}        -- the categories drilled into, top first
local node             -- the category browsed (nil: none yet)
local results = {}     -- browse results, or the open item's listings
local detail           -- nil: browsing; { key, info, commodity, quantity, quote } while an item is open
local filters = { min = 0, max = 0, rarity = 0, text = "" }

------------------------------------------------------------------------
-- Browsing
------------------------------------------------------------------------

local QUALITY_FILTERS -- Enum.AuctionHouseFilter by quality, Poor first
local function QualityFilters(from)
    local F = Enum.AuctionHouseFilter
    QUALITY_FILTERS = QUALITY_FILTERS or { F.PoorQuality, F.CommonQuality, F.UncommonQuality, F.RareQuality,
        F.EpicQuality, F.LegendaryQuality, F.ArtifactQuality }
    local out = {}
    for q = from + 1, #QUALITY_FILTERS do out[#out + 1] = QUALITY_FILTERS[q] end
    return out
end

local function Browse()
    if not C_AuctionHouse.SendBrowseQuery then return end
    if not node and (filters.text or "") == "" then -- nothing picked: don't fetch the whole auction house
        detail, results = nil, {}
        ns.RefreshBuy()
        return
    end
    local list = QualityFilters(filters.rarity)
    if ns.db.usable ~= false then list[#list + 1] = Enum.AuctionHouseFilter.UsableOnly end
    if node and node.implicitFilter then list[#list + 1] = node.implicitFilter end
    detail = nil
    results = {}
    header:SetText("|cff9d9d9dlooking...|r")
    C_AuctionHouse.SendBrowseQuery({
        searchString = filters.text or "",
        sorts = Sorts(),
        minLevel = filters.min, maxLevel = filters.max,
        filters = list,
        itemClassFilters = node and node.filters or {},
    })
    ns.RefreshBuy()
end

local function ItemInfo(key)
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if not info and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(key.itemID) end
    return info
end

local function Market(id)
    local p = MarketDeck_GetPrice and MarketDeck_GetPrice(id)
    return p and (p.market or p.now) or nil
end

local function OnBrowse()
    if detail then return end
    results = {}
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        results[#results + 1] = { key = r.itemKey, price = r.minPrice, quantity = r.totalQuantity }
    end
    ns.RefreshBuy()
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)

------------------------------------------------------------------------
-- An item's listings, and buying
------------------------------------------------------------------------

local function Open(r)
    local info = ItemInfo(r.key)
    detail = { key = r.key, info = info, commodity = info and info.isCommodity, quantity = 1, price = r.price,
        total = r.quantity }
    results = {}
    header:SetText("|cff9d9d9dlooking...|r")
    C_AuctionHouse.SendSearchQuery(r.key, { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
        true)
    ns.RefreshBuy()
end

local function OnListings()
    if not detail then return end
    results = {}
    if detail.commodity then
        local id = detail.key.itemID
        for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) or 0 do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
            if r then results[#results + 1] = { price = r.unitPrice, quantity = r.quantity, mine = r.containsOwnerItem } end
        end
    else
        for i = 1, C_AuctionHouse.GetNumItemSearchResults(detail.key) or 0 do
            local r = C_AuctionHouse.GetItemSearchResultInfo(detail.key, i)
            if r and r.buyoutAmount then
                results[#results + 1] = { price = r.buyoutAmount, auctionID = r.auctionID, link = r.itemLink,
                    left = r.timeLeft, mine = r.containsOwnerItem }
            end
        end
    end
    ns.RefreshBuy()
end
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(id) if detail and detail.commodity and detail.key.itemID == id then OnListings() end end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(key) if detail and not detail.commodity and key and key.itemID == detail.key.itemID then OnListings() end end)

-- What buying `n` from the cheapest up would cost, from the listings (the game's own quote comes after A).
local function Estimate(n)
    local left, total = n, 0
    for _, r in ipairs(results) do
        if not r.mine then
            local take = math.min(left, r.quantity or 0)
            total = total + take * r.price
            left = left - take
            if left <= 0 then break end
        end
    end
    return left <= 0 and total or nil
end

-- A question in DeckKit's blocking popup (screen:Ask): yes runs inside the A press, as buying needs. No on a quote lets
-- the game know the purchase isn't going ahead.
local function Ask(question, yesLabel, yes)
    ns.Screen():Ask({ text = question, yes = yesLabel, no = "Don't", onYes = yes, onNo = function()
        if detail and detail.quote then
            C_AuctionHouse.CancelCommoditiesPurchase()
            detail.quote = nil
        end
    end })
end

-- Stackables: A asks the game for the price of `quantity`; its answer (COMMODITY_PRICE_UPDATED) is the question.
local function BuyCommodity()
    if not (detail and detail.commodity) then return end
    detail.quote = { quantity = detail.quantity }
    C_AuctionHouse.StartCommoditiesPurchase(detail.key.itemID, detail.quantity)
end
ns.On("COMMODITY_PRICE_UPDATED", function(unit, total)
    local q = detail and detail.quote
    if not q then return end
    Ask(("Buy %d for %s (%s each)?"):format(q.quantity, ns.Money(total), ns.Money(unit)), "Buy", function()
        C_AuctionHouse.ConfirmCommoditiesPurchase(detail.key.itemID, q.quantity)
        detail.quote = nil
    end)
end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
    if detail and detail.quote then detail.quote = nil; ns.Print("that many aren't for sale any more: look again") end
end)
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function() ns.Print("bought") if detail then Open({ key = detail.key }) end end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function() if detail and not detail.commodity then Open({ key = detail.key }) end end)

local function BuyItem(r)
    if not (r and r.auctionID) then return end
    Ask(("Buy %s for %s?"):format(r.link or "it", ns.Money(r.price)), "Buy", function()
        C_AuctionHouse.PlaceBid(r.auctionID, r.price)
    end)
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function RowFrame(parent, width)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(width, ROW_H)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)
    f:SetHighlightTexture(hl)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(ROW_H - 6, ROW_H - 6)
    f.icon:SetPoint("LEFT", 6, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFontObject(UI.Font.body)
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.text:SetPoint("RIGHT", -190, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.right = f:CreateFontString(nil, "OVERLAY")
    f.right:SetFontObject(UI.Font.body)
    f.right:SetPoint("RIGHT", -8, 0)
    f.right:SetWidth(180)
    f.right:SetJustifyH("RIGHT")
    return f
end

local function Drill(n)
    path[#path + 1] = n
    node = n
    Browse()
end

local function Up()
    if #path == 0 then return false end
    table.remove(path)
    node = path[#path]
    Browse()
    return true
end

local function CatRow(i)
    local f = RowFrame(catList.content, LEFT_W - 18)
    f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    f.icon:Hide()
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", 10, 0)
    f.text:SetPoint("RIGHT", -20, 0)
    return UI.Register(f, {
        prompts = function(self)
            return { { "A", self.cat and self.cat.subCategories and "Open" or "Browse" } }
        end,
        activate = function(self) if self.cat then Drill(self.cat) end end,
        left = function() return Up() end,
        refresh = function(self)
            local c = self.cat
            if not c then return end
            local here = node == c
            self.text:SetText((here and "|cffffd100" or "") .. (c.name or "?") .. (here and "|r" or ""))
            self.right:SetText(c.subCategories and "|cff9d9d9d>|r" or "")
            self.right:SetWidth(16)
        end,
    })
end

local function ResRow(i)
    local f = RowFrame(resList.content, RIGHT_W - 18)
    f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    return UI.Register(f, {
        prompts = function(self)
            if not self.r then return {} end
            if not detail then return { { "A", "Look" } } end
            if detail.commodity then return { { "A", "Buy " .. detail.quantity }, { "DPAD_LR", "How many" } } end
            return { { "A", "Buy this one" } }
        end,
        activate = function(self)
            if not self.r then return end
            if not detail then Open(self.r) elseif detail.commodity then BuyCommodity() else BuyItem(self.r) end
        end,
        left = function()
            if not (detail and detail.commodity) then return false end
            detail.quantity = math.max(1, detail.quantity - 1)
        end,
        right = function()
            if not (detail and detail.commodity) then return false end
            detail.quantity = math.min(detail.total or 9999, detail.quantity + 1)
        end,
        refresh = function(self)
            local r = self.r
            if not r then return end
            if detail then
                local info = detail.info
                self.icon:SetTexture(info and info.iconFileID)
                local text = detail.commodity and ("x%d"):format(r.quantity or 0) or (r.link or (info and info.itemName) or "?")
                if r.mine then text = text .. "  |cff9d9d9d(yours)|r" end
                self.text:SetText(text)
                self.right:SetText(ns.Money(r.price) .. (detail.commodity and " each" or ""))
                return
            end
            local info = ItemInfo(r.key)
            self.icon:SetTexture(info and info.iconFileID)
            local name = info and info.itemName or "|cff6d6d6dloading...|r"
            local color = info and info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
            local level = select(5, C_Item.GetItemInfo(r.key.itemID))
            self.text:SetText((color and color.hex or "") .. name .. (color and "|r" or "")
                .. ((level and level > 1) and ("  |cff9d9d9dlvl " .. level .. "|r") or "")
                .. ((r.quantity and r.quantity > 1) and ("  |cff9d9d9dx" .. r.quantity .. "|r") or ""))
            local market = Market(r.key.itemID)
            local deal = market and r.price and r.price <= market * DEAL
                and ("|cff40ff40 -%d%%|r "):format(math.floor((1 - r.price / market) * 100 + 0.5)) or ""
            self.right:SetText(deal .. ns.Money(r.price))
        end,
    })
end

------------------------------------------------------------------------
-- The tab
------------------------------------------------------------------------

-- The categories to show: the open one's own, or (a category with none) its siblings, or the top ones.
local function Categories()
    if node and node.subCategories then return node.subCategories end
    local parent = path[#path - 1]
    if node and parent then return parent.subCategories or {} end
    return AuctionCategories or {}
end

function ns.RefreshBuy()
    if not tab then return end
    local cats = Categories()
    for i, c in ipairs(cats) do
        local row = catRows[i] or CatRow(i)
        catRows[i] = row
        row.cat = c
        row:Show()
    end
    for i = #cats + 1, #catRows do catRows[i].cat = nil; catRows[i]:Hide() end
    catList:SetContentHeight(#cats * ROW_H)

    for i, r in ipairs(results) do
        local row = resRows[i] or ResRow(i)
        resRows[i] = row
        row.r = r
        row:Show()
    end
    for i = #results + 1, #resRows do resRows[i].r = nil; resRows[i]:Hide() end
    resList:SetContentHeight(#results * ROW_H)

    local where = {}
    for _, p in ipairs(path) do where[#where + 1] = p.name end
    if detail then
        local info = detail.info
        local text = (info and info.itemName or "?")
        if detail.commodity then
            local est = Estimate(detail.quantity)
            text = text .. ("   |cff9d9d9dbuying|r %d   |cff9d9d9dabout|r %s"):format(detail.quantity,
                est and ns.Money(est) or "|cffff8040more than are listed|r")
        end
        header:SetText(text)
    else
        header:SetText(#where > 0 and table.concat(where, " > ") or "Pick a category, or search")
    end
    emptyText:SetShown(#results == 0 and (node ~= nil or filters.text ~= ""))

    local s = ns.Screen()
    if s and s.win:IsShown() and s.tab == 3 then
        local f = s:Focused()
        if not (f and f:IsVisible()) then s:SetFocus(searchBox) end
        s:Refresh()
    end
end

function ns.BuildBuy(t)
    tab = t
    local body = t.frame
    searchBox = UI.TextBox(body, LEFT_W, { label = "Search", boxWidth = LEFT_W - 70, placeholder = "a name",
        get = function() return filters.text end, set = function(v) filters.text = v or "" end,
        enter = function() Browse() end })
    searchBox:SetPoint("TOPLEFT", 0, 0)
    catList = UI.ScrollList(body, LEFT_W, 350)
    catList:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -6)
    local blizzard = UI.Action(body, LEFT_W, { label = "Blizzard's window", verb = "Open",
        run = function() ns.UseBlizzard() end })
    blizzard:SetPoint("TOPLEFT", catList, "BOTTOMLEFT", 0, -6)

    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", LEFT_W + 10, 0)
    right:SetSize(RIGHT_W, 420)
    -- Level from and to: "any" below 1; "from" can't pass "to", "to" can't go under "from" (DeckKit's live bounds).
    local minLvl = UI.Stepper(right, 150, { label = "Lvl", popover = true, any = 0, anyText = "any",
        min = 1, max = function() return filters.max ~= 0 and filters.max or 70 end,
        get = function() return filters.min end, set = function(v) filters.min = v end, done = function() Browse() end,
    })
    minLvl:SetPoint("TOPLEFT", 0, 0)
    minLvl.value:SetWidth(40)
    local maxLvl = UI.Stepper(right, 130, { label = "to", popover = true, any = 0, anyText = "any",
        min = function() return math.max(1, filters.min) end, max = 70,
        get = function() return filters.max end, set = function(v) filters.max = v end, done = function() Browse() end,
    })
    maxLvl:SetPoint("LEFT", minLvl, "RIGHT", 4, 0)
    maxLvl.value:SetWidth(40)
    local rarity = UI.Selector(right, 160, { label = "", boxWidth = 140, values = RARITY, listOnly = true,
        get = function() return filters.rarity end, set = function(v) filters.rarity = v; Browse() end })
    rarity:SetPoint("LEFT", maxLvl, "RIGHT", 4, 0)
    local usable = UI.Checkbox(right, 140, { label = "Usable",
        get = function() return ns.db.usable ~= false end,
        set = function(v) ns.db.usable = v and true or false; Browse() end })
    usable:SetPoint("LEFT", rarity, "RIGHT", 4, 0)

    local sort = UI.Selector(right, 190, { label = "Sort", boxWidth = 120, values = SORTS, listOnly = true,
        get = function() return ns.db.sort or "price" end,
        set = function(v) ns.db.sort = v; Browse() end })
    sort:SetPoint("TOPRIGHT", 0, -34)
    header = right:CreateFontString(nil, "OVERLAY")
    header:SetFontObject(UI.Font.heading)
    header:SetPoint("TOPLEFT", 6, -40)
    header:SetWidth(RIGHT_W - 210)
    header:SetJustifyH("LEFT")
    resList = UI.ScrollList(right, RIGHT_W, 340)
    resList:SetPoint("TOPLEFT", 0, -64)
    emptyText = UI.Description(right, "Nothing for sale here with these filters.", RIGHT_W - 40)
    emptyText:SetPoint("TOPLEFT", 20, -80)

    t.onShow = function() ns.RefreshBuy() end
end

-- B goes back: out of an item's listings, then up a category; only then does it close the auction house.
function ns.BuyBack()
    if detail then
        if detail.quote then C_AuctionHouse.CancelCommoditiesPurchase() end
        detail = nil
        if node then Browse() else results = {}; ns.RefreshBuy() end
        return true
    end
    return Up()
end
function ns.BuyBackLabel()
    if detail then return "Back to results" end
    if #path > 0 then return "Up" end
end

-- Names, icons and qualities the game didn't have yet arrive later: redraw the rows then (a burst at once, as one).
local redrawTimer
local function ItemDataArrived()
    local s = ns.Screen()
    if not (s and s.win:IsShown() and s.tab == 3) or redrawTimer then return end
    redrawTimer = C_Timer.NewTimer(0.1, function()
        redrawTimer = nil
        if s.win:IsShown() and s.tab == 3 then s:Refresh() end
    end)
end
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", ItemDataArrived)
ns.On("GET_ITEM_INFO_RECEIVED", ItemDataArrived)
