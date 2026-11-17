-- AuctionPad's pricing rule (Pricing.lua): what to ask for an item from what's listed now (Ben, 2026-11-17).
local P = AuctionPadPricingForTests

step("gear: undercut the lowest by 1c")
eq(P.Suggest({ commodity = false, listings = { { price = 4500, quantity = 1 }, { price = 5200, quantity = 1 } } }),
   4499, "1c under the cheapest")

step("stackables: undercut when 1c is under 1% of the price, else match")
eq(P.Suggest({ commodity = true, listings = { { price = 620, quantity = 50 }, { price = 640, quantity = 20 } } }),
   619, "6s 20c ore: 1c is 0.16%, undercut")
eq(P.Suggest({ commodity = true, listings = { { price = 27, quantity = 1240 }, { price = 28, quantity = 4800 } } }),
   27, "27c leather: 1c is almost 4%, match")

step("bait at the bottom is ignored")
eq(P.Suggest({ commodity = true, listings = { { price = 15, quantity = 2 }, { price = 27, quantity = 1240 },
   { price = 28, quantity = 4800 } } }), 27, "2 at 15c against 1240 at 27c: price against 27c")
eq(P.Suggest({ commodity = true, listings = { { price = 25, quantity = 600 }, { price = 27, quantity = 1240 } } }),
   25, "a real lower price (lots of them) isn't bait")

step("your own listings are never what you undercut")
eq(P.Suggest({ commodity = false, listings = { { price = 4000, quantity = 1, mine = true },
   { price = 4500, quantity = 1 } } }), 4499, "beats the cheapest of others'")

step("nothing listed: market, else last time, else vendor x1.5")
eq(P.Suggest({ commodity = true, listings = {}, market = 30, vendor = 15 }), 30, "market")
eq(P.Suggest({ commodity = true, listings = {}, last = 29, vendor = 15 }), 29, "last time")
eq(P.Suggest({ commodity = true, listings = {}, vendor = 15 }), 23, "vendor x1.5, rounded up")
eq(P.Suggest({ commodity = true, listings = {} }), nil, "nothing to go on")

step("presets")
local info = { commodity = true, listings = { { price = 27, quantity = 100 } }, market = 30, last = 29, vendor = 15 }
info.preset = "market"; eq(P.Suggest(info), 30, "market")
info.preset = "last"; eq(P.Suggest(info), 29, "last time")
info.preset = "vendor"; eq(P.Suggest(info), 23, "vendor x1.5")

step("vendor it: when the cut leaves about what a vendor pays")
check(P.VendorIt(30, 15) == false, "30c against a 15c vendor price: post it")
check(P.VendorIt(19, 15) == true, "19c: after the cut, under 1.3x vendor: vendor it")
check(P.VendorIt(100, nil) == false, "no vendor price: post it")
eq(P.Earns(27, 46), 1180, "46 at 27c: 1242c less a 62c cut (62.1 rounded down)")
eq(P.Cut(152), 7, "the game's own invoice: 152c sold, 7c cut (7.6 rounded down)")
eq(P.Cut(3744), 187, "and 3744c, 187c")

step("price steps: two significant figures")
eq(P.Step(27), 1, "27c by 1c")
eq(P.Step(620), 10, "6s 20c by 10c")
eq(P.Step(45000), 1000, "4g 50s by 10s")
