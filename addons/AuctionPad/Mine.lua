-- AuctionPad's My auctions tab: what you have up, its price, how long it has left. X cancels one (A confirms: the
-- game's rule wants a real press, and cancelling costs the deposit). Undercut alerts and relisting come later.
local _, ns = ...

local UI = DeckKit.UI

local ROW_W, ROW_H = 820, 30
local rows, auctions = {}, {}
local list, emptyText, tab, totalText

function ns.Sold(a) return a.status == (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1) end

local function Left(seconds)
    if not seconds then return "" end
    local h = math.floor(seconds / 3600)
    if h >= 1 then return h .. " h" end
    return math.max(1, math.floor(seconds / 60)) .. " min"
end

-- What an auction is: its link when the game gives one (gear), else the item's own, from its ID (stackables come with
-- only an item key). Asks for the item's data when the game doesn't have it yet; the list redraws when it arrives.
local function Name(a)
    if a.itemLink then return a.itemLink end
    local id = a.itemKey and a.itemKey.itemID
    if not id then return "?" end
    local _, link = C_Item.GetItemInfo(id)
    if link then return link end
    local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(a.itemKey)
    if info and info.itemName then return info.itemName end
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return "|cff6d6d6dloading...|r"
end

local function Prompts(self)
    if not self.auction then return {} end
    return { { "X", "Cancel" } }
end

local function MakeRow(i)
    local f = CreateFrame("Button", nil, list.content)
    f:SetSize(ROW_W - 22, ROW_H)
    f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)
    f:SetHighlightTexture(hl)
    local function Col(x, w, justify)
        local t = f:CreateFontString(nil, "OVERLAY")
        t:SetFontObject(UI.Font.body)
        t:SetPoint("LEFT", x, 0)
        t:SetWidth(w)
        t:SetJustifyH(justify or "LEFT")
        t:SetWordWrap(false)
        return t
    end
    f.name = Col(10, 380)
    f.qty = Col(400, 70, "RIGHT")
    f.price = Col(480, 190, "RIGHT")
    f.left = Col(690, 90, "RIGHT")
    return UI.Register(f, {
        prompts = Prompts,
        -- X: cancel it, after a yes in DeckKit's blocking popup (cancelling needs a real press: the A that says yes).
        x = function(self)
            local a = self.auction
            if not a then return end
            local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(a.auctionID)
            ns.Screen():Ask({ text = ("Cancel %s?%s"):format(Name(a),
                    cost and cost > 0 and ("\nIt costs " .. ns.Money(cost) .. ".") or ""),
                yes = "Cancel it", no = "Keep it",
                onYes = function() C_AuctionHouse.CancelAuction(a.auctionID) end })
        end,
        refresh = function(self)
            local a = self.auction
            if not a then return end
            self.name:SetText(Name(a))
            self.qty:SetText(a.quantity and a.quantity > 1 and ("x" .. a.quantity) or "")
            -- Sold: what it sold for in all. Active stacks: the price of one ("each"), as the game reports it.
            local sold = ns.Sold(a)
            local each = not sold and (a.quantity or 1) > 1
            self.price:SetText(a.buyoutAmount and (ns.Money(a.buyoutAmount) .. (each and " |cff9d9d9deach|r" or ""))
                or "|cff6d6d6dbid only|r")
            self.left:SetText(sold and "|cff40ff40sold|r" or Left(a.timeLeftSeconds))
        end,
    })
end

local function Rebuild()
    auctions = {}
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if a then auctions[#auctions + 1] = a end
    end
    for i, a in ipairs(auctions) do
        local row = rows[i] or MakeRow(i)
        rows[i] = row
        row.auction = a
        row:Show()
    end
    for i = #auctions + 1, #rows do rows[i].auction = nil; rows[i]:Hide() end
    list:SetContentHeight(#auctions * ROW_H)
    emptyText:SetShown(#auctions == 0)
    -- What's sold but not yet in your mailbox: the game keeps a sold auction in this list until its gold is delivered.
    -- A sold auction's buyout is what it sold for in all (19 Rough Stone: 152c); an active stack's is the price of
    -- one (21 Boar Meat at 113c each). Checked against Ben's own auctions and MarketDeck's prices, 2026-11-17.
    -- Each sale's mail is the sale, less the cut (5% rounded down), plus the deposit back (Ben's invoices, 2026-11-17).
    -- Deposits are known for auctions AuctionPad posted (kept by auction ID); others' aren't, and the line says so.
    local copper, sold, unknown = 0, 0, 0
    local deposits = ns.db.deposits or {}
    local live = {}
    for _, a in ipairs(auctions) do
        live[a.auctionID] = true
        if ns.Sold(a) and a.buyoutAmount then
            copper = copper + a.buyoutAmount - ns.Pricing.Cut(a.buyoutAmount)
            local d = deposits[a.auctionID]
            if d then copper = copper + d else unknown = unknown + 1 end
            sold = sold + 1
        end
    end
    for id in pairs(deposits) do if not live[id] then deposits[id] = nil end end -- delivered: forget them
    local extra = unknown > 0 and (", plus %d deposit%s back"):format(unknown, unknown > 1 and "s" or "") or ""
    totalText:SetText(sold > 0 and ("|cffffd100Coming by mail|r  %s   |cff9d9d9d(%d sold, after the cut%s)|r"):format(
        ns.Money(copper), sold, extra) or "|cff9d9d9dNothing on its way by mail.|r")
    local s = ns.Screen()
    if s and s.win:IsShown() and s.tab == 2 then
        local f = s:Focused()
        if not (f and f:IsVisible()) then s:SetFocus(rows[1] and rows[1]:IsShown() and rows[1] or nil) end
        s:Refresh()
    end
end

function ns.BuildMine(t)
    tab = t
    local head = t.frame:CreateFontString(nil, "OVERLAY")
    head:SetFontObject(UI.Font.dim)
    head:SetPoint("TOPLEFT", 10, -2)
    head:SetText("Item" .. string.rep(" ", 1))
    local function Head(text, x, w)
        local h = t.frame:CreateFontString(nil, "OVERLAY")
        h:SetFontObject(UI.Font.dim)
        h:SetPoint("TOPLEFT", x, -2)
        h:SetWidth(w)
        h:SetJustifyH("RIGHT")
        h:SetText(text)
    end
    Head("Amount", 400, 70)
    Head("Price", 480, 190)
    Head("Left", 690, 90)
    list = UI.ScrollList(t.frame, ROW_W, 362)
    list:SetPoint("TOPLEFT", 0, -22)
    totalText = t.frame:CreateFontString(nil, "OVERLAY")
    totalText:SetFontObject(UI.Font.body)
    totalText:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 10, -10)
    emptyText = UI.Description(t.frame, "You have nothing on the auction house.", 400)
    emptyText:SetPoint("TOPLEFT", 20, -40)
    t.onShow = function()
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then C_AuctionHouse.QueryOwnedAuctions({}) end
        Rebuild()
    end
end

ns.On("OWNED_AUCTIONS_UPDATED", function() if list then Rebuild() end end)
local function Redraw()
    local s = ns.Screen()
    if s and s.win:IsShown() and s.tab == 2 then s:Refresh() end
end
ns.On("GET_ITEM_INFO_RECEIVED", Redraw)
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", Redraw)
ns.On("AUCTION_CANCELED", function()
    if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then C_AuctionHouse.QueryOwnedAuctions({}) end
end)
