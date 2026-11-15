-- MarketDeck's progress bar for a snapshot: the cast bar's art in a deep purple, just below where the
-- breath timer sits. While the server puts the snapshot together, the fill sweeps out from the middle
-- and back ("Scanning AH"); while it's read, it fills ("Processing Y/Z"); at the end the glow comes up,
-- the bell rings and the whole bar fades out.
--   ns.Progress(text, value, count)   value 0-1, or nil for waiting; count = { done, total }
--   ns.ProgressDone(text, full)       the end: full (the finish) or not (it just fades)
--   ns.ProgressTest() / ns.ProgressTestFinish(mode, value)   /deckkit market test [flash | freeze A | off]
local _, ns = ...

local bar, fadeTimer
-- Colors: the cast bar's gold art, desaturated and tinted (Ben: "contusion purple").
local FILL = DeckKit.COLORS.PLUM -- a deep bruise purple
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
function ns.Progress(text, value, count)
    local b = Bar()
    local phase = count and "processing" or "scanning"
    if b.phase ~= phase then -- log the phase changes only: this runs every frame while it reads
        b.phase = phase
        ns.Debug("progress", text)
    end
    if count then
        b.text:SetText(("Processing %s/%s"):format(ns.Thousands(count[1]), ns.Thousands(count[2])))
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
function ns.ProgressDone(text, full)
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
                if ns.db and ns.db.bell ~= false then PlaySoundFile(DONE_SOUND, "SFX") end
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

-- /deckkit market test: the progress bar's whole sequence, without asking the auction house.
function ns.ProgressTest()
    ns.Progress("Asking the auction house for prices...", nil)
    local steps, total = 0, 9800
    C_Timer.After(20, function() -- about how long the house took to answer the first real one
        local t
        t = C_Timer.NewTicker(0.1, function() -- ~5 s of reading, like a real one
            steps = steps + 1
            local done = math.min(total, steps * 200)
            ns.Progress("reading auctions (a test)", done / total, { done, total })
            if done >= total then
                t:Cancel()
                ns.ProgressDone("prices updated: 9,800 auctions, 6,168 items (a test)", true)
            end
        end)
    end)
end

-- Test helpers for the finish: "flash" repeats it on a full bar; "freeze A" holds it at alpha A (for
-- screenshots); "off" hides the bar.
local flashTicker
function ns.ProgressTestFinish(mode, value)
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
            ns.ProgressDone(nil, true)
        end
        Ending()
        flashTicker = C_Timer.NewTicker(4, Ending, 3)
    end
end
