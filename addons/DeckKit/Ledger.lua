-- DeckKit.Ledger: a record of what happens to you as you play, for live numbers (Measures.lua) and for who you've
-- been dealing with (People.lua). Read from chat lines and plain events the game still gives addons: the combat log
-- is closed to them, and buffs are never read (reading auras taints the gamepad bar).
--
-- What's recorded (kind: fields):
--   loot      item, count            "You receive loot/item: ..." (looting, gathering, quest rewards)
--   created   item, count            "You create: ..." (crafting)
--   coin      copper                 looted coin ("You loot 1 Silver, 20 Copper")
--   money     copper (+ or -)        every change to your money (sales, repairs, purchases, coin too)
--   xp        amount                 every XP gain, across level-ups
--   rep       faction (name), amount "Reputation with X increased by N." (negative for decreases)
--   skill     skill (name), rank     "Your skill in X has increased to N."
--   quest     quest (ID)             a quest turned in
--   whisper   name, direction ("in" / "out"), text
--   bnet      name (BattleTag), character, direction, text   never the friend's real name
--   chat      name, channel, text
--   trade     name, theirs, yours    a finished trade: { money = copper, items = { {name, count} } } each side
--   invite    name                   a party invite you received
--
-- Two kinds of memory:
--   * Totals (loot, created, coin, money, xp, rep, skill, quest) are saved per minute, per character, for KEEP_DAYS,
--     in DeckKitDB.ledger, so "since I started" survives a reload and "yesterday" can be asked. The same table holds
--     every character's totals, so account-wide sums are possible.
--   * People's events (whisper, bnet, chat, trade, invite) are kept in memory only, never written to disk, and
--     dropped after PEOPLE_SECONDS.
-- Values the game hides from addons (secrets) are skipped, and counted, in and out of combat and instances
-- (Diagnostics), so it's possible to see what the game withholds.
--
--   Ledger.Listen(fn)                      fn(event) after each event is recorded ({ kind, t, ... })
--   Ledger.Mark(name [, scope]) / Ledger.MarkTime(name [, scope])   named start times (scope "account" or the
--                                          character's own, the default), saved
--   Ledger.Totals(kind, since [, scope])   { [key] = sum } since a server time: key is the item ID (loot,
--                                          created), faction (rep), skill (skill), or 1 for the rest
--   Ledger.Events(kind, seconds)           this session's events of a kind (people's or totals'), newest first
--   Ledger.SessionStart()                  when this session's record began (server time)
--   Ledger.Diagnostics()                   { [kind] = { ["combat/instance"] = { seen = n, hidden = n } } }
local _, ns = ...

local L = {}
ns.Ledger = L

local KEEP_DAYS = 4
local PEOPLE_SECONDS = 1800
local TOTAL_KINDS = { loot = true, created = true, coin = true, money = true, xp = true, rep = true, skill = true,
                      quest = true }

local Readable = ns.Readable
local function Now() return GetServerTime() end

local listeners = {}
function L.Listen(fn) listeners[#listeners + 1] = fn end

local session = { start = nil, events = {} } -- this session, in memory
local diag = {}
local store -- DeckKitDB.ledger
local char -- store.chars[this character]

local function CharKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    return (name or "?") .. "-" .. (realm or "")
end

local function Context()
    local instance = IsInInstance and IsInInstance()
    return (InCombatLockdown() and "combat" or "calm") .. "/" .. (instance and "instance" or "world")
end

local function Count(kind, hidden)
    local d = diag[kind] or {}
    diag[kind] = d
    local c = d[Context()] or { seen = 0, hidden = 0 }
    d[Context()] = c
    c.seen = c.seen + 1
    if hidden then c.hidden = c.hidden + 1 end
end

-- Whether every value is usable; counts the event as seen (and hidden if not).
local function Usable(kind, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and not Readable(v) then Count(kind, true) return false end
    end
    Count(kind, false)
    return true
end

------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------

local function Bucket(t)
    local m = math.floor(t / 60)
    local b = char.buckets[m]
    if not b then b = {}; char.buckets[m] = b end
    return b
end

local function Add(kind, key, amount, t)
    if not char then return end
    local b = Bucket(t)
    local k = b[kind]
    if not k then k = {}; b[kind] = k end
    k[key] = (k[key] or 0) + amount
end

local KEYS = { loot = "item", created = "item", rep = "faction", skill = "skill" }
local AMOUNTS = { loot = "count", created = "count", coin = "copper", money = "copper", xp = "amount", rep = "amount" }

local function Record(e)
    e.t = e.t or Now()
    table.insert(session.events, 1, e)
    if TOTAL_KINDS[e.kind] then
        local key = KEYS[e.kind] and e[KEYS[e.kind]] or 1
        local amount = AMOUNTS[e.kind] and e[AMOUNTS[e.kind]] or 1
        Add(e.kind, key, amount, e.t)
    end
    for _, fn in ipairs(listeners) do fn(e) end
end
L.Record = Record -- for tests and for modules with an event of their own to add

-- People's events older than PEOPLE_SECONDS go (totals' events stay for the session: they're small).
local function Prune()
    local cutoff = Now() - PEOPLE_SECONDS
    for i = #session.events, 1, -1 do
        local e = session.events[i]
        if not TOTAL_KINDS[e.kind] and e.t < cutoff then table.remove(session.events, i) end
    end
    if char then
        local old = math.floor((Now() - KEEP_DAYS * 86400) / 60)
        for _, c in pairs(store.chars) do
            for m in pairs(c.buckets) do if m < old then c.buckets[m] = nil end end
        end
    end
end

------------------------------------------------------------------------
-- Chat lines: patterns from the game's own (localized) format strings
------------------------------------------------------------------------

-- "You receive loot: %sx%d." -> a pattern capturing the %s and %d in order.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?([sd])", "\1%1"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1s", "(.-)"):gsub("\1d", "(%%d+)")
    return "^" .. p .. "$"
end

local function Patterns(names)
    local out = {}
    for _, n in ipairs(names) do
        local p = Pattern(_G[n])
        if p then out[#out + 1] = p end
    end
    return out
end

local LOOT, CREATED, REP_UP, REP_DOWN, SKILL, COINS

local function BuildPatterns()
    -- Multiple first: "x5" would otherwise end up inside the item's name.
    LOOT = Patterns({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF",
                      "LOOT_ITEM_PUSHED_SELF" })
    CREATED = Patterns({ "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" })
    REP_UP = Patterns({ "FACTION_STANDING_INCREASED" })
    REP_DOWN = Patterns({ "FACTION_STANDING_DECREASED" })
    SKILL = Patterns({ "SKILL_RANK_UP" })
    COINS = {}
    for _, c in ipairs({ { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }) do
        local f = _G[c[1]]
        if type(f) == "string" then
            COINS[#COINS + 1] = { f:gsub("%%d", "(%%d+)"), c[2] }
        end
    end
end

local function Match(patterns, text)
    for _, p in ipairs(patterns) do
        local a, b = text:match(p)
        if a then return a, b end
    end
end

local function ItemID(link) return tonumber(link:match("|Hitem:(%d+)")) end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local function Short(name)
    if not Readable(name) or name == "" then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return name
end
L.Short = Short

local function Me() return UnitName("player") end

-- Chat text as plain words, cut to `limit` bytes without splitting a character.
local function Plain(text, limit)
    if not Readable(text) then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
        :gsub("|", "/"):gsub("%c", " ")
    if #text > limit then text = text:sub(1, limit):gsub("[\192-\255][\128-\191]*$", "") end
    return text
end
L.Plain = Plain
local TEXT_BYTES = 100

local On = ns.On

On("CHAT_MSG_LOOT", function(text, _, _, _, playerName2, _, _, _, _, _, _, guid)
    if not Usable("loot", text) or not text then return end
    if not LOOT or #LOOT == 0 then BuildPatterns() end
    local link, n = Match(LOOT, text)
    local kind = "loot"
    if not link then link, n = Match(CREATED, text); kind = "created" end
    if not link then return end -- someone else's loot
    local id = ItemID(link)
    if id then Record({ kind = kind, item = id, count = tonumber(n) or 1 }) end
end)

On("CHAT_MSG_MONEY", function(text)
    if not Usable("coin", text) or not text then return end
    if not COINS or #COINS == 0 then BuildPatterns() end
    local total = 0
    for _, c in ipairs(COINS) do
        local n = text:match(c[1])
        if n then total = total + tonumber(n) * c[2] end
    end
    if total > 0 then Record({ kind = "coin", copper = total }) end
end)

local lastMoney
local function MoneyNow() local m = GetMoney and GetMoney(); return Readable(m) and m or nil end
On("PLAYER_MONEY", function()
    local m = GetMoney and GetMoney()
    if not Usable("money", m) or not m then return end
    if lastMoney and m ~= lastMoney then Record({ kind = "money", copper = m - lastMoney }) end
    lastMoney = m
end)

local lastXP, lastMax
local function XPNow()
    if not (UnitXP and UnitXPMax) then return end
    local x, max = UnitXP("player"), UnitXPMax("player")
    if Readable(x) and Readable(max) then return x, max end
end
On("PLAYER_XP_UPDATE", function()
    if not (UnitXP and UnitXPMax) then return end
    local x, max = UnitXP("player"), UnitXPMax("player")
    if not Usable("xp", x, max) or not x then return end
    if lastXP then
        local gained = x >= lastXP and (x - lastXP) or ((lastMax or 0) - lastXP + x) -- across a level-up
        if gained > 0 then Record({ kind = "xp", amount = gained }) end
    end
    lastXP, lastMax = x, max
end)

On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(text)
    if not Usable("rep", text) or not text then return end
    if not REP_UP or #REP_UP == 0 then BuildPatterns() end
    local faction, n = Match(REP_UP, text)
    local sign = 1
    if not faction then faction, n = Match(REP_DOWN, text); sign = -1 end
    if faction and n then Record({ kind = "rep", faction = faction, amount = sign * tonumber(n) }) end
end)

On("CHAT_MSG_SKILL", function(text)
    if not Usable("skill", text) or not text then return end
    if not SKILL or #SKILL == 0 then BuildPatterns() end
    local skill, rank = Match(SKILL, text)
    if skill then Record({ kind = "skill", skill = skill, rank = tonumber(rank) }) end
end)

On("QUEST_TURNED_IN", function(questID)
    if not Usable("quest", questID) or not questID then return end
    Record({ kind = "quest", quest = questID })
end)

-- Whispers and chat.
local function Whisper(direction)
    return function(text, name)
        if not Usable("whisper", text, name) then return end
        name = Short(name)
        if name and name ~= Me() then
            Record({ kind = "whisper", name = name, direction = direction, text = Plain(text, TEXT_BYTES) })
        end
    end
end
On("CHAT_MSG_WHISPER", Whisper("in"))
On("CHAT_MSG_WHISPER_INFORM", Whisper("out"))

-- Battle.net whispers: arg 2 is the friend's real name, so it's never read; the account ID (arg 13) gives the
-- BattleTag and the character they're on.
local function BNWhisper(direction)
    return function(text, _, _, _, _, _, _, _, _, _, _, _, accountID)
        if not Usable("bnet", text, accountID) then return end
        if not (accountID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return end
        local a = C_BattleNet.GetAccountInfoByID(accountID)
        if not (a and Readable(a.battleTag)) then return end
        local g = a.gameAccountInfo
        local character = g and g.clientProgram == "WoW" and Readable(g.characterName) and g.characterName or ""
        Record({ kind = "bnet", name = a.battleTag, character = character, direction = direction,
                 text = Plain(text, TEXT_BYTES) })
    end
end
On("CHAT_MSG_BN_WHISPER", BNWhisper("in"))
On("CHAT_MSG_BN_WHISPER_INFORM", BNWhisper("out"))

local CHAT_EVENTS = {
    CHAT_MSG_SAY = "Say", CHAT_MSG_YELL = "Yell", CHAT_MSG_EMOTE = "Emote", CHAT_MSG_TEXT_EMOTE = "Emote",
    CHAT_MSG_PARTY = "Party", CHAT_MSG_PARTY_LEADER = "Party", CHAT_MSG_RAID = "Raid",
    CHAT_MSG_RAID_LEADER = "Raid", CHAT_MSG_RAID_WARNING = "Raid warning", CHAT_MSG_GUILD = "Guild",
    CHAT_MSG_OFFICER = "Officer", CHAT_MSG_INSTANCE_CHAT = "Instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "Instance",
    CHAT_MSG_CHANNEL = false, -- named by its channel: General, Trade...
}
for event, label in pairs(CHAT_EVENTS) do
    On(event, function(text, name, _, _, _, _, _, _, channelBase)
        if not Readable(name) then Count("chat", true) return end -- no name: nothing to keep
        Count("chat", not Readable(text))
        name = Short(name)
        if not name or name == Me() then return end
        local channel = label
        if not channel then channel = Readable(channelBase) and channelBase ~= "" and channelBase or "Channel" end
        Record({ kind = "chat", name = name, channel = channel, text = Plain(text, TEXT_BYTES) })
    end)
end

On("PARTY_INVITE_REQUEST", function(name)
    if not Usable("invite", name) then return end
    name = Short(name)
    if name then Record({ kind = "invite", name = name }) end
end)

-- Trades: what each side put in, kept as the trade changes, recorded when the game says it's done.
local pending
local function Side(itemInfo, money)
    local items = {}
    for i = 1, (MAX_TRADABLE_ITEMS or 6) do
        local name, _, count = itemInfo(i)
        if Readable(name) and name and name ~= "" then
            items[#items + 1] = { name = name, count = Readable(count) and count or 1 }
        end
    end
    local m = money and money() or 0
    return { money = Readable(m) and tonumber(m) or 0, items = items }
end
local function Snapshot()
    if not pending then return end
    if GetTradeTargetItemInfo then pending.theirs = Side(GetTradeTargetItemInfo, GetTargetTradeMoney) end
    if GetTradePlayerItemInfo then pending.yours = Side(GetTradePlayerItemInfo, GetPlayerTradeMoney) end
end
On("TRADE_SHOW", function()
    local name, realm = UnitName("NPC")
    if not Usable("trade", name, realm) or not name then pending = nil return end
    if realm and realm ~= "" then name = name .. "-" .. realm end
    pending = { name = Short(name) }
    Snapshot()
end)
for _, event in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
                         "TRADE_ACCEPT_UPDATE" }) do
    On(event, Snapshot)
end
On("UI_INFO_MESSAGE", function(_, message)
    if pending and Readable(message) and message == ERR_TRADE_COMPLETE then
        Record({ kind = "trade", name = pending.name, theirs = pending.theirs or { money = 0, items = {} },
                 yours = pending.yours or { money = 0, items = {} } })
        pending = nil
    end
end)

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

local function Setup()
    if char then return end
    DeckKitDB = DeckKitDB or {}
    store = DeckKitDB.ledger or { chars = {}, marks = {} }
    DeckKitDB.ledger = store
    store.chars = store.chars or {}
    store.marks = store.marks or {}
    local key = CharKey()
    char = store.chars[key] or { buckets = {}, marks = {} }
    store.chars[key] = char
    char.buckets, char.marks = char.buckets or {}, char.marks or {}
    session.start = Now()
    lastMoney = MoneyNow()
    lastXP, lastMax = XPNow()
    BuildPatterns()
    Prune()
end
On("PLAYER_LOGIN", Setup)
On("PLAYER_ENTERING_WORLD", function()
    Setup()
    if not lastMoney then lastMoney = MoneyNow() end
    if not lastXP then lastXP, lastMax = XPNow() end
end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, Prune) end

------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------

function L.SessionStart() return session.start or Now() end

local function Marks(scope)
    if not char then return {} end
    return scope == "account" and store.marks or char.marks
end

function L.Mark(name, scope)
    Setup()
    Marks(scope)[name] = Now()
    return Marks(scope)[name]
end

function L.MarkTime(name, scope) return Marks(scope)[name] end

-- { [key] = sum } of a totals kind since server time `since` (nil: this session). The minute `since` falls in
-- counts only what came after it when this session saw that minute (its events are still in memory).
function L.Totals(kind, since, scope)
    local out = {}
    if not char or not TOTAL_KINDS[kind] then return out end
    since = since or L.SessionStart()
    local first = math.floor(since / 60)
    local exact = since >= L.SessionStart()
    local function AddBucket(b)
        local k = b and b[kind]
        if k then for key, v in pairs(k) do out[key] = (out[key] or 0) + v end end
    end
    local chars = scope == "account" and store.chars or { [CharKey()] = char }
    for _, c in pairs(chars) do
        for m, b in pairs(c.buckets) do
            if m > first or (m == first and not (exact and c == char)) then AddBucket(b) end
        end
    end
    if exact then -- the first minute, exactly, from this session's events
        for _, e in ipairs(session.events) do
            if e.kind == kind and e.t >= since and math.floor(e.t / 60) == first then
                local key = KEYS[kind] and e[KEYS[kind]] or 1
                out[key] = (out[key] or 0) + (AMOUNTS[kind] and e[AMOUNTS[kind]] or 1)
            end
        end
    end
    return out
end

function L.Events(kind, seconds)
    local out, cutoff = {}, seconds and (Now() - seconds) or nil
    for _, e in ipairs(session.events) do
        if cutoff and e.t < cutoff then break end
        if not kind or e.kind == kind then out[#out + 1] = e end
    end
    return out
end

function L.Diagnostics() return diag end
