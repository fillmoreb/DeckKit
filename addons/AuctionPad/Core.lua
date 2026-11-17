-- AuctionPad: the auction house, controller first. Talking to an auctioneer opens AuctionPad's window instead of
-- Blizzard's (whose window stays open but invisible: the auction house closes when its window does).
--
--   Core.lua     the window, its tabs, opening and closing with the auction house, Blizzard's window kept out of sight
--   Pricing.lua  what to ask: beat the lowest, match, market, vendor (pure, tested offline)
--   Sell.lua     the Sell tab: your bags' auctionable items, the price, quantity and length, A posts
--   Mine.lua     the My auctions tab: what you have up, X cancels
--   Buy.lua      the Buy tab: Blizzard's categories drilled into, level / rarity / usable filters, a search box, buying
--
-- Posting and cancelling need a real button press (the game's rule), so they happen inside your A press. Prices come
-- from MarketDeck when it's installed (market, vendor); the current listings from the auction house's own search.
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffffd166AuctionPad|r")

local UI = DeckKit.UI
local WIDTH, HEIGHT = 860, 540

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    AuctionPadDB = AuctionPadDB or {}
    AuctionPadDB.last = AuctionPadDB.last or {}     -- itemID -> the price you last posted at (copper, each)
    AuctionPadDB.duration = AuctionPadDB.duration or 2 -- 1: 12 h, 2: 24 h, 3: 48 h
    ns.db = AuctionPadDB
end)

-- Money as the game writes it, with coin icons.
function ns.Money(c)
    c = math.max(0, math.floor(c or 0))
    if GetMoneyString then return GetMoneyString(c, true) end
    return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------

local screen
function ns.Screen() return screen end

local function Build()
    if screen then return screen end
    screen = UI.NewScreen("AuctionPadWindow", WIDTH, HEIGHT, "Auction House")
    ns.sellTab = screen:AddTab("Sell")
    ns.mineTab = screen:AddTab("My auctions")
    ns.buyTab = screen:AddTab("Buy")
    ns.BuildSell(ns.sellTab)
    ns.BuildMine(ns.mineTab)
    ns.BuildBuy(ns.buyTab)

    -- B steps back in Buy (out of an item, up a category) before it closes the auction house.
    function screen:OnBack() return self.tab == 3 and ns.BuyBack() or false end
    function screen:BackLabel() return self.tab == 3 and ns.BuyBackLabel() or nil end

    -- B (or Menu) closes the auction house itself, as walking away would.
    function screen:OnPlayerClose()
        if C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then C_AuctionHouse.CloseAuctionHouse() end
    end
    return screen
end

------------------------------------------------------------------------
-- Blizzard's window: open (the auction house needs it) but invisible while AuctionPad is up
------------------------------------------------------------------------

local blizzardShown = false -- the player asked for Blizzard's window this visit
local function Blizzard() return AuctionHouseFrame end

local function Conceal(on)
    local f = Blizzard()
    if not f then return end
    -- Alpha only: never Hide or move Blizzard's frame (hiding it closes the auction house; moving a panel taints).
    f:SetAlpha(on and 0 or 1)
end

function ns.UseBlizzard()
    blizzardShown = true
    Conceal(false)
    if screen then screen:Hide() end
end

ns.On("AUCTION_HOUSE_SHOW", function()
    blizzardShown = false
    Build()
    Conceal(true)
    -- Blizzard lays its window out as it opens: conceal it again on the next frame, after that.
    C_Timer.After(0, function() if not blizzardShown then Conceal(true) end end)
    screen:Show()
    if not screen.win:IsShown() then -- couldn't open (combat): Blizzard's window it is
        ns.UseBlizzard()
        return
    end
    screen:SelectTab(1)
    if ns.OnOpen then ns.OnOpen() end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
    Conceal(false)
    blizzardShown = false
    if screen and screen.win:IsShown() then screen:Hide() end
end)

ns.AddCommand("auction", function()
    if screen and screen.win:IsShown() then screen:Hide() else ns.Print("talk to an auctioneer to open it") end
end)

ns.AddSettings({
    { type = "section", tab = "Tools", label = "Auction house" },
    { type = "info", label = "Talking to an auctioneer opens AuctionPad instead of Blizzard's window: LB/RB switch "
        .. "between Sell and My auctions. In Sell, pick an item on the left, set its price, amount and length on the "
        .. "right, and {A} posts it. In Buy, open a category (or search), set the level, rarity and usable filters, "
        .. "{A} on an item shows its listings and {A} buys. {B} goes back a step." },
})
