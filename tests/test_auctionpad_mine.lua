-- AuctionPad's My auctions total: what's sold but not yet delivered by mail. The game reports a sold auction's buyout
-- as its whole sale and an active stack's as the price of one (Ben's own auctions, 2026-11-17: 19 Rough Stone sold for
-- 152c at 8c each; 21 Boar Meat listed at 113c each). Ten sold auctions came to 58s 83c, about 55s 88c after the cut.
local SOLD, ACTIVE = 1, 0
local OWNED = {
    { status = SOLD, quantity = 19, buyoutAmount = 152 }, { status = SOLD, quantity = 13, buyoutAmount = 117 },
    { status = SOLD, quantity = 9, buyoutAmount = 171 }, { status = SOLD, quantity = 2, buyoutAmount = 40 },
    { status = SOLD, quantity = 27, buyoutAmount = 729 }, { status = SOLD, quantity = 2, buyoutAmount = 40 },
    { status = SOLD, quantity = 32, buyoutAmount = 3744 }, { status = SOLD, quantity = 9, buyoutAmount = 180 },
    { status = SOLD, quantity = 2, buyoutAmount = 386 }, { status = SOLD, quantity = 36, buyoutAmount = 324 },
    { status = ACTIVE, quantity = 1, buyoutAmount = 100 }, { status = ACTIVE, quantity = 21, buyoutAmount = 113 },
}
C_AuctionHouse.GetNumOwnedAuctions = function() return #OWNED end
C_AuctionHouse.GetOwnedAuctionInfo = function(i) local a = OWNED[i]; if a then a.itemKey = { itemID = 2318 }; a.auctionID = i end return a end
C_AuctionHouse.QueryOwnedAuctions = function() end
Enum.AuctionStatus = { Active = 0, Sold = 1 }
GetMoneyString = function(c) return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100) end

step("the auction house opens on AuctionPad; My auctions totals what's coming by mail")
H.fire("AUCTION_HOUSE_SHOW")
local screen
for _, s in ipairs(DeckKit.UI.Screens()) do if s.win:GetName() == "AuctionPadWindow" then screen = s end end
check(screen and screen.win:IsShown(), "AuctionPad's window is open")
screen:SelectTab(2)
local total
for _, f in ipairs(H.frames()) do
    if f:GetObjectType() == "FontString" and f:IsVisible() and H.Plain(f:GetText() or ""):find("Coming by mail") then
        total = H.Plain(f:GetText())
    end
end
check(total, "a Coming by mail line")
-- Each sale less its own cut, rounded down: 152-7, 117-5, 171-8, 40-2, 729-36, 40-2, 3744-187, 180-9, 386-19, 324-16.
check(total:find("0g 55s 92c", 1, true), "58s 83c sold, less each sale's cut: " .. tostring(total))
check(total:find("10 deposits back", 1, true), "deposits AuctionPad didn't see posted are mentioned: " .. tostring(total))
check(total:find("10 sold", 1, true), "ten sold: " .. tostring(total))
