-- AuctionPad's Sell tab: what in your bags can go on the auction house, one row per item (stackables summed, gear
-- one row each), sorted by what it would earn. On the right, the focused item: what it's worth (lowest listed now,
-- market, vendor, last time), the price, quantity and length to post at, what you'd get, and what's listed now.
--   d-pad      up/down the list; right into the item's settings, left/right to change one
--   A          post it (one press, one post: the game's rule)
--   X          the next price preset: beat the lowest, market, last time, vendor x1.5
--   * worth posting   v the vendor pays about as much (the cut eats the difference)
local _, ns = ...

local UI = DeckKit.UI
local Pricing = ns.Pricing

local LIST_W, PANEL_W, ROW_H = 410, 404, 30
local SEARCH_DELAY = 0.4 -- after the cursor stops on a row, before asking the auction house what's listed
local DURATION_HOURS = { 12, 24, 48 }

local entries = {}  -- the rows' items, in list order
local selected      -- the entry the panel shows
local rows = {}     -- pooled row frames
local list, panel, info, listingsText, emptyText
local priceStep, qtyStep, durStep
local searchTimer
local tab

------------------------------------------------------------------------
-- Your bags: what can be sold, grouped
------------------------------------------------------------------------

local function IsCommodity(loc)
    local status = C_AuctionHouse.GetItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus(loc)
    return status == (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2)
end

local function Market(id)
    local p = MarketDeck_GetPrice and MarketDeck_GetPrice(id)
    return p and (p.market or p.now) or nil, p and p.now or nil
end

local function Vendor(id)
    local sell = select(11, C_Item.GetItemInfo(id))
    return (type(sell) == "number" and sell > 0) and sell or nil
end

-- What it would earn, to sort by: the best price we know of, times how many.
local function Worth(e)
    return (e.price or e.market or e.vendor or 0) * e.count
end

local function Scan()
    local byItem, out = {}, {}
    -- The backpack and bags, and the reagent bag (its own bag index, past the others).
    local bags = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = bag end
    bags[#bags + 1] = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- Gray (poor) items aren't listed: a vendor takes them (Ben, 2026-11-17).
            if info and info.itemID and not info.isBound and (info.quality or 1) > 0 then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if C_AuctionHouse.IsSellItemValid(loc, false) then
                    local commodity = IsCommodity(loc)
                    local key = commodity and ("c" .. info.itemID) or (info.hyperlink or ("i" .. bag .. ":" .. slot))
                    local e = byItem[key]
                    if not e then
                        local old
                        for _, prev in ipairs(entries) do if prev.key == key then old = prev end end
                        e = { key = key, id = info.itemID, link = info.hyperlink, icon = info.iconFileID, count = 0,
                              commodity = commodity, loc = loc, quality = info.quality }
                        -- Keep what was already worked out for it (listings, a price you set).
                        if old then
                            e.listings, e.price, e.edited, e.preset, e.quantity = old.listings, old.price, old.edited,
                                old.preset, old.quantity
                        end
                        e.vendor = Vendor(info.itemID)
                        e.market, e.lowestKnown = Market(info.itemID)
                        e.last = ns.db.last[info.itemID]
                        byItem[key] = e
                        out[#out + 1] = e
                    end
                    e.count = e.count + (info.stackCount or 1)
                end
            end
        end
    end
    for _, e in ipairs(out) do
        if not e.edited then e.price = Pricing.Suggest(e) end
        e.quantity = math.min(e.quantity or e.count, e.count)
        if not e.commodity then e.quantity = 1 end
    end
    table.sort(out, function(a, b)
        local va, vb = Pricing.VendorIt(a.price, a.vendor), Pricing.VendorIt(b.price, b.vendor)
        if va ~= vb then return vb end -- worth posting first
        return Worth(a) > Worth(b)
    end)
    return out
end

------------------------------------------------------------------------
-- What's listed now: the auction house's own search, for the selected item
------------------------------------------------------------------------

local function Search(e)
    if not (e and C_AuctionHouse.SendSellSearchQuery) then return end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        searchTimer = C_Timer.NewTimer(1, function() Search(selected) end) -- busy: try again shortly
        return
    end
    local key = C_AuctionHouse.GetItemKeyFromItem(e.loc)
    if not key then return end
    e.itemKey = key
    e.searching = true
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    C_AuctionHouse.SendSellSearchQuery(key, sorts, true)
end

local function ScheduleSearch(e)
    if searchTimer then searchTimer:Cancel() end
    searchTimer = C_Timer.NewTimer(SEARCH_DELAY, function() searchTimer = nil; Search(e) end)
end

local function Listed(e)
    local out = {}
    if e.commodity then
        for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(e.id) or 0 do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(e.id, i)
            if r then out[#out + 1] = { price = r.unitPrice, quantity = r.quantity, mine = r.containsOwnerItem } end
        end
    elseif e.itemKey then
        for i = 1, C_AuctionHouse.GetNumItemSearchResults(e.itemKey) or 0 do
            local r = C_AuctionHouse.GetItemSearchResultInfo(e.itemKey, i)
            if r and r.buyoutAmount then
                out[#out + 1] = { price = r.buyoutAmount, quantity = r.quantity or 1, mine = r.containsOwnerItem }
            end
        end
    end
    return out
end

local function Results(match)
    for _, e in ipairs(entries) do
        if e.searching and match(e) then
            e.searching = false
            e.listings = Listed(e)
            if not e.edited then e.price = Pricing.Suggest(e) end
        end
    end
    if tab and tab.frame:IsVisible() then ns.Screen():Refresh() end
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID) Results(function(e) return e.commodity and e.id == itemID end) end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    Results(function(e) return not e.commodity and e.itemKey and itemKey and e.itemKey.itemID == itemKey.itemID end)
end)

------------------------------------------------------------------------
-- Posting
------------------------------------------------------------------------

local pending -- a post the game wants confirmed: { commodity, entry, args }

local function Deposit(e)
    if not e then return nil end
    local d = ns.db.duration
    if e.commodity then return C_AuctionHouse.CalculateCommodityDeposit(e.id, d, e.quantity) end
    return C_AuctionHouse.CalculateItemDeposit(e.loc, d, 1)
end

-- The deposit paid on the post now on its way, kept by the auction's ID when the game makes it: it comes back with the
-- sale, so My auctions counts it in what's coming by mail.
local lastDeposit
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function(auctionID)
    if auctionID and lastDeposit then
        ns.db.deposits = ns.db.deposits or {}
        ns.db.deposits[auctionID] = lastDeposit
    end
    lastDeposit = nil
end)

local function Posted(e)
    lastDeposit = Deposit(e)
    ns.db.last[e.id] = e.price
    e.last = e.price
    PlaySound(SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 5274)
    ns.Print(("posted %s x%d at %s each"):format(e.link or "?", e.quantity, ns.Money(e.price)))
end

-- A question in DeckKit's blocking popup (screen:Ask): yes runs inside the A press, as posting needs.
local function Ask(question, yesLabel, noLabel, yes)
    ns.Screen():Ask({ text = question, yes = yesLabel, no = noLabel, onYes = yes })
end

local Post
local function PostNow(e)
    if not C_Item.DoesItemExist(e.loc) then ns.Print("that item has moved: try again") ns.Refresh() return end
    local d = ns.db.duration
    local needs
    if e.commodity then
        pending = { true, e, { e.loc, d, e.quantity, e.price } }
        needs = C_AuctionHouse.PostCommodity(e.loc, d, e.quantity, e.price)
    else
        pending = { false, e, { e.loc, d, 1, nil, e.price } }
        needs = C_AuctionHouse.PostItem(e.loc, d, 1, nil, e.price)
    end
    if needs then
        -- The game wants a second yes (a price far from what it expects): A confirms, B doesn't.
        Ask("|cffff8040The auction house asks: post at this price?|r", "Post anyway", "Don't", function()
            local p = pending
            pending = nil
            if not p then return end
            if p[1] then C_AuctionHouse.ConfirmPostCommodity(unpack(p[3], 1, 4))
            else C_AuctionHouse.ConfirmPostItem(unpack(p[3], 1, 5)) end
            Posted(p[2])
        end)
        return
    end
    pending = nil
    Posted(e)
end

-- A posts; when a vendor pays about as much, it asks first (Ben, 2026-11-17).
function Post(e)
    e = e or selected
    if not (e and e.price and e.price > 0) then return end
    if Pricing.VendorIt(e.price, e.vendor) then
        Ask(("|cffff8040A vendor pays about as much (%s).|r List it anyway?"):format(ns.Money(e.vendor * e.quantity)),
            "List it", "Don't", function() PostNow(e) end)
        return
    end
    PostNow(e)
end


------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------

local function Select(e)
    if selected == e then return end
    selected = e
    if e and not e.listings then ScheduleSearch(e) end
    -- The panel and its settings show the new item at once (moving the cursor doesn't refresh the screen).
    local s = ns.Screen()
    if s and s.win:IsShown() then s:Refresh() end
end

local function CyclePreset()
    local e = selected
    if not e then return end
    local presets, at = Pricing.PRESETS, 1
    for i, p in ipairs(presets) do if p == (e.preset or "undercut") then at = i end end
    for step = 1, #presets do -- the next preset that gives a price
        local p = presets[(at - 1 + step) % #presets + 1]
        local price = Pricing.Suggest({ commodity = e.commodity, listings = e.listings, vendor = e.vendor,
            market = e.market, last = e.last, preset = p })
        if price then e.preset, e.price, e.edited = p, price, false return end
    end
end

local function Prompts()
    local e = selected
    local label = Pricing.PRESET_LABEL[(e and e.preset) or "undercut"]
    return { { "A", "Post" }, { "X", "Price: " .. label } }
end

local function MakeRow(i)
    local f = CreateFrame("Button", nil, list.content)
    f:SetSize(LIST_W - 22, ROW_H)
    f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
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
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetFontObject(UI.Font.body)
    f.name:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.name:SetPoint("RIGHT", -70, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFontObject(UI.Font.body)
    f.count:SetPoint("RIGHT", -28, 0)
    f.mark = f:CreateFontString(nil, "OVERLAY")
    f.mark:SetFontObject(UI.Font.body)
    f.mark:SetPoint("RIGHT", -6, 0)
    return UI.Register(f, {
        prompts = Prompts,
        activate = function(self) Post(self.entry) end,
        x = function() CyclePreset() end,
        onFocus = function(self) Select(self.entry) end,
        refresh = function(self)
            local e = self.entry
            if not e then return end
            self.icon:SetTexture(e.icon)
            self.name:SetText(e.link or "?")
            self.count:SetText(e.count > 1 and ("x" .. e.count) or "")
            local vendor = Pricing.VendorIt(e.price, e.vendor)
            self.mark:SetText(vendor and "|cff9d9d9dv|r" or "|cffffd100*|r")
        end,
    })
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------

local function Line(label, value)
    return ("|cff9d9d9d%s|r  %s"):format(label, value or "|cff6d6d6d-|r")
end

local function PanelText()
    local e = selected
    if not e then
        info:SetText("")
        listingsText:SetText("")
        return
    end
    local lowest = e.listings and Pricing.Floor(Pricing.Tiers(e.listings)) or nil
    local parts = {
        (e.link or "?") .. (e.count > 1 and ("  |cffaaaaaax" .. e.count .. "|r") or ""),
        Line("Lowest now", lowest and ns.Money(lowest) or (e.searching and "|cff6d6d6dlooking...|r" or nil)),
        Line("Market", e.market and ns.Money(e.market) or nil),
        Line("Vendor", e.vendor and ns.Money(e.vendor) or nil),
        Line("Last time", e.last and ns.Money(e.last) or nil),
    }
    info:SetText(table.concat(parts, "\n"))
    local earn = e.price and Pricing.Earns(e.price, e.quantity) or 0
    local deposit = Deposit(e)
    local tail = {
        Line("You get", "|cffffffff" .. ns.Money(earn) .. "|r"),
        Line("Deposit", deposit and (ns.Money(deposit) .. " |cff6d6d6d(back if it sells)|r") or nil),
    }
    if e.vendor then
        local v = e.vendor * e.quantity
        tail[#tail + 1] = Line("A vendor pays", ns.Money(v) ..
            (Pricing.VendorIt(e.price, e.vendor) and "  |cffff8040about as much: vendor it|r" or ""))
    end
    local shown = {}
    for i, t in ipairs(Pricing.Tiers(e.listings or {})) do
        if i > 5 then break end
        shown[#shown + 1] = ("%s  x%d"):format(ns.Money(t.price), t.quantity)
    end
    local mine = 0
    for _, l in ipairs(e.listings or {}) do if l.mine then mine = mine + (l.quantity or 1) end end
    listingsText:SetText(table.concat(tail, "\n") .. "\n\n|cffffd100On the auction house|r\n" ..
        (#shown > 0 and table.concat(shown, "\n") or (e.listings and "nothing listed" or "")) ..
        (mine > 0 and ("\n|cff9d9d9dyours: %d|r"):format(mine) or ""))
end

-- The settings are popover steppers (A opens one, the d-pad passes over them): left goes back to the list.
local function WithPost(f) return f end

function ns.BuildSell(t)
    tab = t
    local body = t.frame
    list = UI.ScrollList(body, LIST_W, 410)
    list:SetPoint("TOPLEFT", 0, -4)
    emptyText = UI.Description(body, "Nothing in your bags can go on the auction house.", LIST_W - 40)
    emptyText:SetPoint("TOPLEFT", 20, -30)

    panel = UI.Panel(body)
    panel:SetPoint("TOPRIGHT", 0, -4)
    panel:SetSize(PANEL_W, 410)
    info = panel:CreateFontString(nil, "OVERLAY")
    info:SetFontObject(UI.Font.body)
    info:SetPoint("TOPLEFT", 14, -12)
    info:SetWidth(PANEL_W - 28)
    info:SetJustifyH("LEFT")
    info:SetSpacing(4)

    priceStep = WithPost(UI.Stepper(panel, PANEL_W - 16, { label = "Price each", popover = true, widest = 999999, -- 99g 99s 99c: room for a big price
        min = 1, max = 99999999, get = function() return selected and selected.price or 1 end,
        set = function(v)
            if not selected then return end
            local step = Pricing.Step(selected.price)
            -- The stepper moved by 1: scale that to the price's own step.
            local d = v - selected.price
            selected.price = math.max(1, selected.price + d * step)
            selected.edited = true
        end, format = function(v) return ns.Money(v) end }))
    priceStep:SetPoint("TOPLEFT", 8, -128)
    priceStep.value:SetWidth(170)
    qtyStep = WithPost(UI.Stepper(panel, PANEL_W - 16, { label = "Quantity", popover = true, min = 1, max = 9999,
        get = function() return selected and selected.quantity or 1 end,
        set = function(v) if selected then selected.quantity = math.max(1, math.min(selected.count, v)) end end,
        disabled = function() return not (selected and selected.commodity and selected.count > 1) end }))
    qtyStep:SetPoint("TOPLEFT", priceStep, "BOTTOMLEFT", 0, -2)
    durStep = WithPost(UI.Stepper(panel, PANEL_W - 16, { label = "Length", popover = true, min = 1, max = 3,
        get = function() return ns.db.duration end, set = function(v) ns.db.duration = v end,
        format = function(v) return DURATION_HOURS[v] .. " h" end }))
    durStep:SetPoint("TOPLEFT", qtyStep, "BOTTOMLEFT", 0, -2)

    listingsText = panel:CreateFontString(nil, "OVERLAY")
    listingsText:SetFontObject(UI.Font.body)
    listingsText:SetPoint("TOPLEFT", durStep, "BOTTOMLEFT", 6, -10)
    listingsText:SetWidth(PANEL_W - 28)
    listingsText:SetJustifyH("LEFT")
    listingsText:SetSpacing(3)

    t.onRefresh = function() PanelText() end
    t.onShow = function() ns.Refresh() end
end

-- Rescans your bags and rebuilds the list (keeping the cursor on the same item where it can).
function ns.Refresh()
    if not (tab and C_AuctionHouse) then return end
    local keep = selected and selected.key
    entries = Scan()
    for i, e in ipairs(entries) do
        local row = rows[i] or MakeRow(i)
        rows[i] = row
        row.entry = e
        row:Show()
    end
    for i = #entries + 1, #rows do rows[i].entry = nil; rows[i]:Hide() end
    list:SetContentHeight(#entries * ROW_H)
    emptyText:SetShown(#entries == 0)
    selected = nil
    local focusRow
    for i, e in ipairs(entries) do if e.key == keep then focusRow = rows[i] end end
    focusRow = focusRow or (entries[1] and rows[1])
    if focusRow then Select(focusRow.entry) end
    local s = ns.Screen()
    if s and s.win:IsShown() and s.tab == 1 then
        local f = s:Focused()
        -- On a row: stay on the same item (it may have moved). On a setting: stay there.
        if not (f and f:IsVisible() and not f.entry) then s:SetFocus(focusRow) end
        s:Refresh()
    end
end

-- Bags change as you post (and as mail arrives): rebuild, a moment later so a burst is one rebuild.
local refreshTimer
ns.On("BAG_UPDATE_DELAYED", function()
    local s = ns.Screen()
    if not (s and s.win:IsShown()) then return end
    if refreshTimer then refreshTimer:Cancel() end
    refreshTimer = C_Timer.NewTimer(0.2, function() refreshTimer = nil; ns.Refresh() end)
end)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function() if selected then selected.listings = nil end end)
