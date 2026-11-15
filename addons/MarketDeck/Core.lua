-- MarketDeck: auction house prices, with nothing to press. Opening the auction house takes a snapshot of
-- every auction (C_AuctionHouse.ReplicateItems, Blizzard's whole-house query, allowed every 15 minutes)
-- when the last one is over an hour old, and boils it down to the lowest buyout per item and how many
-- are up. Prices are kept per auction house (realm + Alliance, Horde or the goblins' neutral one),
-- account-wide, with each day's lowest price for two weeks: the market price is the middle of those.
--
-- For other addons:
--   MarketDeck_GetPrice(itemID) -> nil, or { now = copper, quantity = n, market = copper, days = n,
--       scanned = server time, vendor = copper or nil, disenchant = copper or nil } (this house)
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffffd100MarketDeck|r")

local RESCAN_AFTER = 3600 -- seconds: an older snapshot is retaken when the auction house opens
local KEEP_DAYS = 14
local BUDGET_MS = 5 -- milliseconds of each frame spent reading auctions, so a big house never hitches
local CHECK_EVERY = 100 -- auctions read between looks at the clock

local db
-- Goblin towns' auction houses are neutral (one house for both factions): their zones' maps.
local NEUTRAL_ZONES = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn, Tanaris, Winterspring

local function Now() return GetServerTime and GetServerTime() or time() end
local function Today() return math.floor(Now() / 86400) end

local function HouseKey()
    local side = UnitFactionGroup("player") or "?"
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if not map or map == 0 then break end
        if NEUTRAL_ZONES[map] then side = "Neutral" break end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    return (GetRealmName() or "?") .. "-" .. side
end

local houseKey -- the house prices are read from: the last one opened, else this character's faction's

local function House(key)
    key = key or houseKey or ((GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?"))
    db.houses[key] = db.houses[key] or { scanned = 0, now = {}, days = {} }
    return db.houses[key]
end

------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------

-- days[itemID] is "day:copper day:copper ..." (newest last), one entry per day: that day's lowest.
local function Days(h, id)
    local out = {}
    for day, copper in (h.days[id] or ""):gmatch("(%d+):(%d+)") do out[#out + 1] = { tonumber(day), tonumber(copper) } end
    return out
end

local function Median(list)
    if #list == 0 then return nil end
    table.sort(list)
    local m = math.floor((#list + 1) / 2)
    if #list % 2 == 0 then return math.floor((list[m] + list[m + 1]) / 2) end
    return list[m]
end

function ns.Price(id, key)
    local h = House(key)
    local now = h.now[id]
    local lowest, qty
    if now then lowest, qty = now:match("(%d+):(%d+)") end
    local prices, cutoff = {}, Today() - KEEP_DAYS
    for _, d in ipairs(Days(h, id)) do
        if d[1] > cutoff then prices[#prices + 1] = d[2] end
    end
    if not lowest and #prices == 0 then return nil end
    return { now = tonumber(lowest), quantity = tonumber(qty) or 0, market = Median(prices), days = #prices,
        scanned = h.scanned }
end

------------------------------------------------------------------------
-- The progress bar: the breath timer's look (Blizzard_MirrorTimer), just below where it sits
------------------------------------------------------------------------

local bar, fadeTimer
-- Colors: the cast bar's gold art, desaturated and tinted (Ben: "contusion purple").
local FILL = { 0.30, 0.12, 0.42 }  -- a deep bruise purple
local GLOW = { 0.60, 0.34, 0.92 }  -- the same, lit: the finish flash and halo
local SPARK = { 0.86, 0.74, 1.00 } -- pale lilac
local DONE_SOUND = 566652 -- sound/doodad/boatdockedwarning.ogg: the boat-docked bell, "ding ding"
local EMPTY = { 0.50, 0.43, 0.56 } -- the unfilled background: darker, a little purple
local function Tint(tex, c)
    tex:SetDesaturated(true)
    tex:SetVertexColor(c[1], c[2], c[3])
end
local shown, target = 0, 0 -- the bar's value on screen, and where it's sliding to
local TWEEN = 8 -- how fast it closes the gap (per second, exponential): ~0.3 s to get most of the way

local function Bar()
    if bar then return bar end
    bar = CreateFrame("Frame", "MarketDeckProgress", UIParent)
    bar:SetSize(206, 18)
    bar:SetPoint("TOP", 0, -150)
    bar:SetFrameStrata("HIGH")
    bar:Hide()
    local sb = CreateFrame("StatusBar", nil, bar)
    sb:SetSize(195, 13)
    sb:SetPoint("TOP", 0, -2)
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sb:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")
    Tint(sb:GetStatusBarTexture(), FILL)
    sb:SetMinMaxValues(0, 1)
    bar.status = sb
    -- While waiting: the same fill, from the middle out to both edges and back (the bar's own fill stays empty).
    -- It shows a slice of the full-width fill, not the whole fill squeezed (no rubber banding): the atlas's
    -- own texture coordinates, narrowed around the middle as the slice narrows.
    local sweep = sb:CreateTexture(nil, "ARTWORK")
    local info = C_Texture.GetAtlasInfo("ui-castingbar-filling-standard")
    if info and info.file then
        sweep:SetTexture(info.file)
        sweep.coords = { info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord }
    else
        sweep:SetAtlas("ui-castingbar-filling-standard")
    end
    Tint(sweep, FILL)
    sweep:SetPoint("CENTER")
    sweep:SetHeight(13)
    sweep:Hide()
    bar.sweep = sweep
    -- The cast bar's spark (ui-castingbar-pip, 6x16 as on Blizzard's smaller bars): one on the fill's edge,
    -- or one on each edge of the sweep.
    -- The cast bar's finish flash (ui-castingbar-full-glow-standard, additive, just over the bar): in over
    -- 0.2 s as Blizzard's FlashAnim; it stays lit and goes out with the bar.
    local flash = sb:CreateTexture(nil, "OVERLAY", nil, 2)
    flash:SetAtlas("ui-castingbar-full-glow-standard")
    flash:SetBlendMode("ADD")
    Tint(flash, GLOW)
    flash:SetPoint("TOPLEFT", -1, 1)
    flash:SetPoint("BOTTOMRIGHT", 1, -1)
    flash:SetAlpha(0)
    -- With it, a halo outside the bar (the empowered cast's outer glow, at Blizzard's half size): the
    -- flash alone is gold on gold and barely shows; the halo lights up the dark around the bar.
    local halo = sb:CreateTexture(nil, "OVERLAY", nil, 3)
    halo:SetAtlas("cast_empowered_outerglow")
    halo:SetBlendMode("ADD")
    Tint(halo, GLOW)
    halo:SetSize(222, 25)
    halo:SetPoint("CENTER")
    halo:SetAlpha(0)
    bar.halo = halo
    local anim = flash:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    bar.flash = anim
    -- The halo pulses with it (its own group: an animation group drives one texture).
    local haloAnim = halo:CreateAnimationGroup()
    haloAnim:SetToFinalAlpha(true)
    local hIn = haloAnim:CreateAnimation("Alpha")
    hIn:SetFromAlpha(0)
    hIn:SetToAlpha(1)
    hIn:SetDuration(0.2)
    hIn:SetOrder(1)
    bar.haloAnim = haloAnim
    bar.sparks = {}
    for i = 1, 2 do
        local spark = sb:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetAtlas("ui-castingbar-pip")
        spark:SetSize(6, 16)
        Tint(spark, SPARK)
        spark:Hide()
        bar.sparks[i] = spark
    end
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAtlas("ui-castingbar-background")
    Tint(bg, EMPTY)
    bg:SetPoint("TOPLEFT", sb, "TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, -1)
    local border = sb:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("ui-castingbar-frame")
    border:SetPoint("TOPLEFT", sb, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 2, -2)
    -- The label sits in the bar, like a spell's name on the cast bar (above the fill, sweep and sparks).
    local label = CreateFrame("Frame", nil, sb)
    label:SetAllPoints()
    label:SetFrameLevel(sb:GetFrameLevel() + 5)
    local text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetText("Scanning AH")
    bar.text = text
    return bar
end

local function Thousands(n)
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then return s end
    end
end

local function Glow(on)
    local b = Bar()
    b.flash:Stop()
    b.haloAnim:Stop()
    if on then
        b.flash:Play()
        b.haloAnim:Play()
    else
        b.flash:GetParent():SetAlpha(0)
        b.halo:SetAlpha(0)
    end
end

-- value 0-1, or nil for "waiting" (the fill sweeps out from the middle and back while the server puts the
-- snapshot together, which can take half a minute). The bar says "Scanning AH" while it waits, then
-- "Processing Y/Z" (`count` = { done, total }) while it reads; `text` is for the log.
local function Progress(text, value, count)
    local b = Bar()
    local phase = count and "processing" or "scanning"
    if b.phase ~= phase then -- log the phase changes only: this runs every frame while it reads
        b.phase = phase
        ns.Debug("progress", text)
    end
    if count then
        b.text:SetText(("Processing %s/%s"):format(Thousands(count[1]), Thousands(count[2])))
    else
        b.text:SetText("Scanning AH")
    end
    if value == nil and not b.waiting then b.waitSince = GetTime() end
    if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
    if value ~= nil and b.waiting then shown = 0 end -- from the sweep to real progress: start from empty
    if b.flash:GetParent():GetAlpha() > 0 then Glow(false) end
    b.waiting = value == nil
    target = value or 0
    b:SetAlpha(1)
    b:Show()
end

-- The end: full (the fill slides home, the glow comes up, and the whole bar fades out with it as it
-- peaks) or not (it just fades). What happened goes to chat, not the bar.
local function ProgressDone(text, full)
    local b = Bar()
    b.waiting, b.phase = false, nil
    if text then ns.Print(text) end
    target = full and 1 or 0
    b:SetAlpha(1)
    b:Show()
    Glow(false)
    if fadeTimer then fadeTimer:Cancel() end
    if full then
        C_Timer.After(0.35, function()
            if b:IsShown() and not b.waiting then
                Glow(true)
                if db and db.bell ~= false then PlaySoundFile(DONE_SOUND, "SFX") end
            end
        end)
    end
    fadeTimer = C_Timer.NewTimer(full and 0.55 or 0.8, function()
        fadeTimer = nil
        if UIFrameFadeOut then UIFrameFadeOut(b, 0.9, 1, 0) end
        C_Timer.After(1.0, function()
            if not b.waiting then
                b:Hide()
                Glow(false)
            end
        end)
    end)
end

local LEG = 1.8 -- seconds to grow from the middle to the edges, and the same to fall back
local function EaseInOut(x) return 0.5 - math.cos(math.pi * x) / 2 end

local pulser = CreateFrame("Frame")
pulser:SetScript("OnUpdate", function(_, elapsed)
    if not (bar and bar:IsShown()) then return end
    bar.sweep:SetShown(bar.waiting)
    if bar.waiting then
        local t = (GetTime() - (bar.waitSince or GetTime())) % (2 * LEG) -- from 0 (the middle) when waiting began
        local grow = t < LEG and EaseInOut(t / LEG) or EaseInOut((2 * LEG - t) / LEG)
        bar.sweep:SetWidth(math.max(0.5, grow * bar.status:GetWidth()))
        local c = bar.sweep.coords
        if c then -- the middle slice of the fill, the same share of it as of the bar
            local mid, half = (c[1] + c[2]) / 2, (c[2] - c[1]) * grow / 2
            bar.sweep:SetTexCoord(mid - half, mid + half, c[3], c[4])
        end
        bar.sweep:SetAlpha(grow > 0.01 and 1 or 0)
        local half, on = grow * bar.status:GetWidth() / 2, grow > 0.03
        for i, spark in ipairs(bar.sparks) do
            spark:ClearAllPoints()
            spark:SetPoint("CENTER", bar.status, "CENTER", i == 1 and -half or half, 0)
            spark:SetShown(on)
        end
        bar.status:SetValue(0)
        shown = 0
        return
    else
        shown = shown + (target - shown) * math.min(1, elapsed * TWEEN) -- slide to the new value
        if math.abs(target - shown) < 0.002 then shown = target end
    end
    bar.status:SetValue(shown)
    local spark = bar.sparks[1]
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar.status, "LEFT", shown * bar.status:GetWidth(), 0)
    spark:SetShown(shown > 0.005 and shown < 0.995)
    bar.sparks[2]:Hide()
end)

------------------------------------------------------------------------
-- The snapshot
------------------------------------------------------------------------

local scanning, scanKey, lowest, counts, index, total
local askedAt, readAt -- GetTime() when the snapshot was asked for, and when it arrived

local function Finish()
    local h, today, cutoff = House(scanKey), Today(), Today() - KEEP_DAYS
    h.now = {}
    for id, copper in pairs(lowest) do
        h.now[id] = copper .. ":" .. counts[id]
        local kept, todays = {}, copper
        for _, d in ipairs(Days(h, id)) do
            if d[1] == today then todays = math.min(todays, d[2])
            elseif d[1] > cutoff then kept[#kept + 1] = d[1] .. ":" .. d[2] end
        end
        kept[#kept + 1] = today .. ":" .. todays
        h.days[id] = table.concat(kept, " ")
    end
    h.scanned = Now()
    db.lastTiming = { wait = readAt and askedAt and (readAt - askedAt) or nil, read = readAt and (GetTime() - readAt),
        auctions = total }
    local n = 0
    for _ in pairs(lowest) do n = n + 1 end
    ProgressDone(("prices updated: %s auctions, %s items"):format(Thousands(total), Thousands(n)), true)
    scanning, lowest, counts = nil, nil, nil
end

local reader = CreateFrame("Frame")
reader:Hide()
reader:SetScript("OnUpdate", function(self)
    -- As many as fit in BUDGET_MS this frame (a fixed count would be slow on a fast frame and could hitch
    -- on a slow one; a big house has a quarter of a million auctions).
    local started, stop = debugprofilestop(), index - 1
    while stop < total - 1 and debugprofilestop() - started < BUDGET_MS do
        local from = stop + 1
        stop = math.min(from + CHECK_EVERY - 1, total - 1)
        for i = from, stop do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local each = math.floor(buyout / count)
                if not lowest[itemID] or each < lowest[itemID] then lowest[itemID] = each end
                counts[itemID] = (counts[itemID] or 0) + count
            end
        end
    end
    index = stop + 1
    Progress("reading auctions", total > 0 and index / total or 1, { index, total })
    if index >= total then
        self:Hide()
        Finish()
    end
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if scanning ~= "asked" then return end
    scanning, lowest, counts, index = "reading", {}, {}, 0
    readAt = GetTime()
    total = C_AuctionHouse.GetNumReplicateItems() or 0
    Progress("reading auctions", 0, { 0, total })
    reader:Show()
end)

local function Scan(force)
    if scanning then return end
    local h = House(houseKey)
    if not force and Now() - (h.scanned or 0) < RESCAN_AFTER then return end
    scanKey, scanning, askedAt = houseKey, "asked", GetTime()
    Progress("Asking the auction house for prices...", nil)
    C_AuctionHouse.ReplicateItems()
    C_Timer.After(120, function()
        if scanning == "asked" then -- refused (the 15-minute limit), or the server never answered
            scanning = nil
            ProgressDone("no auction snapshot this time (the auction house allows one every 15 minutes)", false)
        end
    end)
end

ns.On("AUCTION_HOUSE_SHOW", function()
    houseKey = HouseKey()
    if db.autoScan ~= false then Scan() end
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if scanning == "reading" then return end -- the snapshot is already here: let it finish
    if scanning == "asked" then ProgressDone("the auction house closed before the snapshot came", false) end
    scanning = nil
end)

------------------------------------------------------------------------
-- Setup, settings, commands
------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    MarketDeckDB = MarketDeckDB or {}
    db = MarketDeckDB
    db.houses = db.houses or {}
end)

function MarketDeck_GetPrice(itemID)
    if not db or type(itemID) ~= "number" then return nil end
    local p = ns.Price(itemID)
    if p then
        p.vendor = ns.Vendor(itemID)
        p.disenchant = ns.Disenchant and ns.Disenchant(itemID)
    else
        local vendor, de = ns.Vendor(itemID), ns.Disenchant and ns.Disenchant(itemID)
        if vendor or de then p = { vendor = vendor, disenchant = de } end
    end
    return p
end

function ns.Vendor(itemID)
    local sell = select(11, C_Item.GetItemInfo(itemID))
    return (sell and sell > 0) and sell or nil
end

local function Ago(t)
    if not t or t == 0 then return "never" end
    local m = math.floor((Now() - t) / 60)
    if m < 60 then return m .. " min ago" end
    if m < 2880 then return math.floor(m / 60) .. " h ago" end
    return math.floor(m / 1440) .. " days ago"
end

ns.AddSettings({
    { type = "section", tab = "Tools", label = "Auction prices" },
    { type = "toggle", label = "Scan when the auction house opens",
      hint = "Takes a snapshot of every auction when you open the auction house, if the last one is over an "
          .. "hour old (Blizzard allows one every 15 minutes). Prices are kept per auction house, for all your "
          .. "characters.",
      get = function() return db.autoScan ~= false end, set = function(on) db.autoScan = on end },
    { type = "toggle", label = "Ring the bell when a snapshot is done",
      hint = "The boat-docked bell, as the scan bar finishes.",
      get = function() return db.bell ~= false end, set = function(on) db.bell = on end },
    { type = "toggle", label = "Prices in item tooltips",
      hint = "Auction (lowest now, and the two-week market price), vendor, and disenchant value.",
      get = function() return db.tooltips ~= false end, set = function(on) db.tooltips = on end },
    { type = "status", label = "Last snapshot",
      get = function() return Ago(House().scanned) end },
})

-- /deckkit market test: the progress bar's whole sequence, without asking the auction house.
local function TestBar()
    Progress("Asking the auction house for prices...", nil)
    local steps, total = 0, 9800
    C_Timer.After(20, function() -- about how long the house took to answer the first real one
        local t
        t = C_Timer.NewTicker(0.1, function() -- ~5 s of reading, like a real one
            steps = steps + 1
            local done = math.min(total, steps * 200)
            Progress("reading auctions (a test)", done / total, { done, total })
            if done >= total then
                t:Cancel()
                ProgressDone("prices updated: 9,800 auctions, 6,168 items (a test)", true)
            end
        end)
    end)
end

-- Test helpers for the finish: "flash" repeats it on a full bar; "freeze A" holds it at alpha A (for
-- screenshots); "off" hides the bar.
local flashTicker
local function TestFinish(mode, value)
    if flashTicker then flashTicker:Cancel(); flashTicker = nil end
    local b = Bar()
    if mode == "off" then Glow(false); b:Hide() return end
    if fadeTimer then fadeTimer:Cancel(); fadeTimer = nil end
    b.waiting, target, shown = false, 1, 1
    b:SetAlpha(1)
    b:Show()
    if mode == "freeze" then
        Glow(false)
        b.flash:GetParent():SetAlpha(tonumber(value) or 1)
        b.halo:SetAlpha(tonumber(value) or 1)
    else -- the whole ending, every 4 s, 4 times
        local function Ending()
            shown = 0.85
            ProgressDone(nil, true)
        end
        Ending()
        flashTicker = C_Timer.NewTicker(4, Ending, 3)
    end
end

ns.AddCommand("market", function(arg)
    local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if word == "test" and rest ~= "" then
        local mode, value = rest:match("^(%S+)%s*(%S*)")
        return TestFinish(mode, value)
    end
    if arg == "test" then return TestBar() end
    if arg == "scan" then
        if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return ns.Print("open the auction house first") end
        houseKey = HouseKey()
        return Scan(true)
    end
    local h = House()
    local n = 0
    for _ in pairs(h.now) do n = n + 1 end
    ns.Print(("%s: %d items priced, last snapshot %s"):format(houseKey or "this auction house", n, Ago(h.scanned)))
    local t = db.lastTiming
    if t and t.wait then
        ns.Print(("last snapshot: %.0f s waiting for the server, %.1f s reading %d auctions"):format(t.wait, t.read or 0,
            t.auctions or 0))
    end
end, "MarketDeck: auction prices (scan: take a snapshot now, with the auction house open; test: show the bar)")
