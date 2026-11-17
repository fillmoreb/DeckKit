-- DeckKit.Ledger, Measures and People: what happens to you, read from the game's chat lines and events, and the
-- live numbers and people built on it.
local Ledger, Measures, People, W = DeckKit.Ledger, DeckKit.Measures, DeckKit.People, H.world

step("loot lines: yours counted by item, others' ignored")
Ledger.Mark("haul")
H.advance(5)
H.fire("CHAT_MSG_LOOT", W.Loot(2318, 3))
H.fire("CHAT_MSG_LOOT", W.Loot(2318))
H.fire("CHAT_MSG_LOOT", W.Loot(2770, 2))
H.fire("CHAT_MSG_LOOT", LOOT_ITEM:format("Someone", W.Link(2318)))
H.fire("CHAT_MSG_LOOT", LOOT_ITEM_PUSHED_SELF:format(W.Link(929))) -- a quest reward counts as gained too
H.fire("CHAT_MSG_LOOT", LOOT_ITEM_CREATED_SELF_MULTIPLE:format(W.Link(2589), 2))
eq(Measures.Value({ measure = "looted", item = 2318, since = "haul" }), 4, "Light Leather")
eq(Measures.Value({ measure = "looted", item = 2770, since = "haul" }), 2, "Copper Ore")
eq(Measures.Value({ measure = "looted", since = "haul" }), 7, "everything looted")
eq(Measures.Value({ measure = "created", since = "haul" }), 2, "crafted, kept apart")

step("value: auction price from a provider, else vendor")
eq(Measures.Value({ measure = "value", of = { measure = "looted", item = 2318, since = "haul" } }), 4 * 15,
   "Light Leather at the vendor's 15c")
DeckKit.Prices.Provide(function(id) if id == 2318 then return 27 end end)
eq(Measures.Value({ measure = "value", of = { measure = "looted", item = 2318, since = "haul" } }), 4 * 27,
   "at the auction price once a price addon gives one")
eq(Measures.Value({ measure = "value", of = { measure = "looted", since = "haul" } }), 4 * 27 + 2 * 5,
   "everything looted, each at its own price (the potion has no price: 0)")

step("rates need a minute; a mark set later counts from then")
eq(Measures.Value({ measure = "looted", item = 2318, since = "haul", per = "hour" }), nil, "too early for a rate")
H.advance(115) -- two minutes after the mark
eq(Measures.Value({ measure = "looted", item = 2318, since = "haul", per = "hour" }), 4 * 30, "4 in 2 minutes: 120/h")
eq(Measures.Format(120, "count", "hour"), "120/h", "shown as a rate")
Ledger.Mark("later")
H.fire("CHAT_MSG_LOOT", W.Loot(2318, 2))
eq(Measures.Value({ measure = "looted", item = 2318, since = "later" }), 2, "only what came after the mark")
eq(Measures.Value({ measure = "looted", item = 2318, since = "haul" }), 6, "the first mark still sees all of it")
eq(Measures.Value({ measure = "looted", item = 2318, since = "nope" }), nil, "an unset mark: can't tell")

step("coin, money, XP across a level-up, reputation, skill-ups, quests")
H.fire("CHAT_MSG_MONEY", "You loot 1 Silver, 20 Copper")
eq(Measures.Value({ measure = "coin", since = "haul" }), 120, "looted coin")
W.Set({ money = 12345 + 120 }) H.fire("PLAYER_MONEY")
W.Set({ money = 12345 + 120 - 500 }) H.fire("PLAYER_MONEY") -- a repair
eq(Measures.Value({ measure = "money", since = "haul" }), 120 - 500, "money: net, spending too")
W.Set({ xp = 4800 }) H.fire("PLAYER_XP_UPDATE")
W.Set({ xp = 300, xpMax = 6000 }) H.fire("PLAYER_XP_UPDATE") -- dinged: 200 to finish the level, 300 into the next
eq(Measures.Value({ measure = "xp", since = "haul" }), 3800 + 200 + 300, "XP across the level-up")
H.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", FACTION_STANDING_INCREASED:format("Nightclaw Druids", 250))
H.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", FACTION_STANDING_DECREASED:format("Bloodsail Buccaneers", 25))
eq(Measures.Value({ measure = "rep", faction = "Nightclaw Druids", since = "haul" }), 250, "rep gained")
eq(Measures.Value({ measure = "rep", faction = "Bloodsail Buccaneers", since = "haul" }), -25, "rep lost")
H.fire("CHAT_MSG_SKILL", SKILL_RANK_UP:format("Mining", 12))
H.fire("CHAT_MSG_SKILL", SKILL_RANK_UP:format("Mining", 13))
H.fire("CHAT_MSG_SKILL", SKILL_RANK_UP:format("Skinning", 40))
eq(Measures.Value({ measure = "skill", skill = "Mining", since = "haul" }), 2, "Mining points")
H.fire("QUEST_TURNED_IN", 5728, 400, 0)
eq(Measures.Value({ measure = "quests", since = "haul" }), 1, "a quest turned in")
eq(Measures.Value({ measure = "sum", of = { { measure = "coin", since = "haul" }, { measure = "value",
   of = { measure = "looted", item = 2318, since = "haul" } } } }), 120 + 6 * 27, "a sum")

step("hidden values are skipped and counted, by combat and instance")
local SECRET = newproxy()
local was = issecretvalue
issecretvalue = function(v) return v == SECRET end
H.combat(true)
H.fire("CHAT_MSG_LOOT", SECRET)
issecretvalue = was
H.combat(false)
local d = Ledger.Diagnostics().loot
eq(d["combat/world"].hidden, 1, "hidden loot in combat in the world")
check(d["calm/world"].seen >= 6 and d["calm/world"].hidden == 0, "the rest seen, none hidden")

step("totals are saved per minute and survive a reload; people never are")
local saved = DeckKitDB.ledger.chars["Tester-Harness"]
check(saved and next(saved.buckets), "per-minute totals in DeckKitDB.ledger")
check(saved.marks.haul, "the mark is saved")
local function Mentions(t, text, depth)
    depth = depth or 0
    if depth > 6 then return false end
    for k, v in pairs(t) do
        if v == text or k == text then return true end
        if type(v) == "table" and Mentions(v, text, depth + 1) then return true end
    end
end
H.fire("CHAT_MSG_WHISPER", "want to group for RFC?", "Jessejames-Harness")
check(not Mentions(DeckKitDB, "Jessejames"), "a whisperer's name isn't in the saved variables")
check(not Mentions(DeckKitDB, "want to group for RFC?"), "nor their words")

step("account-wide: every character's totals, and the account's own marks")
-- The alt looted a minute ago (saved totals are per minute, so a mark can't split another character's minute).
DeckKitDB.ledger.chars["Alt-Harness"] = { marks = {}, buckets = { [math.floor(GetServerTime() / 60) - 1] = {
    loot = { [2318] = 10 } } } }
H.advance(1)
Ledger.Mark("trip", "account")
H.advance(61)
H.fire("CHAT_MSG_LOOT", W.Loot(2318, 1))
eq(Measures.Value({ measure = "looted", item = 2318, since = { minutes = 30 }, scope = "account" }), 6 + 1 + 10,
   "this character's and the alt's")
eq(Measures.Value({ measure = "looted", item = 2318, since = "trip", scope = "account" }), 1, "since the account mark")

step("people: whispers, chat, trades, invites, group, target; chat last")
H.fire("CHAT_MSG_SAY", "anyone for RFC", "Healer-Harness")
H.fire("CHAT_MSG_SAY", "hi", "Tester-Harness") -- your own line
H.fire("PARTY_INVITE_REQUEST", "Jessejames-Harness")
local recent = People.Recent()
local function Names(list) local out = {} for _, e in ipairs(list) do out[#out + 1] = e.kind .. ":" .. e.name end
    return table.concat(out, " ") end
eq(Names(recent), "invite:Jessejames whisper:Jessejames chat:Healer", "newest first, chat last, you left out")
eq(recent[2].text, "want to group for RFC?", "the whisper's words")
H.advance(130)
eq(Names(People.Recent()), "invite:Jessejames whisper:Jessejames", "chat is kept two minutes")
eq(Names(People.Recent({ whisper = true })), "whisper:Jessejames", "one kind")

step("a finished trade says what each side gave")
local THEIRS = { { "Linen Bag", 1 } }
GetTradeTargetItemInfo = function(i) local t = THEIRS[i]; if t then return t[1], 1, t[2] end end
GetTradePlayerItemInfo = function() end
GetTargetTradeMoney = function() return "0" end
GetPlayerTradeMoney = function() return "500" end
local unitName = UnitName
UnitName = function(u) if u == "NPC" then return "Thrallbro", nil end return unitName(u) end
H.fire("TRADE_SHOW")
H.fire("TRADE_ACCEPT_UPDATE", 1, 1)
H.fire("UI_INFO_MESSAGE", 0, "Trade cancelled.")
eq(#People.Recent({ trade = true }), 0, "another message isn't the end of a trade")
H.fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
local trade = People.Recent({ trade = true })[1]
eq(trade and trade.name, "Thrallbro", "the trade partner")
eq(trade.theirs.items[1].name, "Linen Bag", "what they gave")
eq(trade.yours.money, 500, "what you gave")
UnitName = unitName

step("invites: sent, or refused with why")
local invited
C_PartyInfo = { InviteUnit = function(n) invited = n end }
check(People.Invite(" Jessejames "), "sent")
eq(invited, "Jessejames", "to the trimmed name")
W.Set({ group = {} })
UnitIsGroupLeader = function() return false end
local ok, why = People.Invite("Someone")
eq(why, "you're not the group leader", "refused")
