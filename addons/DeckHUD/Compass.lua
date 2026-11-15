-- DeckHUD: the compass. A strip across the middle of the status bar, centered on the way you face,
-- showing half the horizon (90 degrees each side): ticks every 15 degrees and N, NE, E... slide past
-- as you turn, and the active waypoint (DeckKit.Waypoints) rides the strip at its bearing with its
-- distance in yards (just the number) under it; when it's behind you it waits at the nearer edge. "Arrived" shows in the middle
-- when you reach it. Replaces WayPad's old floating arrow.
--
-- The strip isn't one long image: the ticks and letters are separate pieces placed each frame inside a
-- frame that clips them, so they stay crisp, and they fade out toward the ends. With the status bar
-- off the compass sits at the top of the screen on its own dark backing. The status bar's middle
-- readings (the clock) move to the front of its right side while the compass is on.
local _, ns = ...

local WIDTH, HEIGHT = 360, 20 -- the strip (set in the menu: Size below); the status bar's height
local POINTER = 63            -- the down pointer's width (half again the pair's 42)
local POINTER_TRIM = 17       -- how far up it sits: its art's clear space (15 at this size) plus the bit hidden behind the bar (2)
local POINTER_LIGHT = math.pi / 4 -- it turns from plum to lilac as the pin comes within 45 degrees of the middle
local YARDS_DROP = 10         -- how far the distance drops below the pin at the middle, to clear the pointer
local FOV = math.pi           -- how much of the horizon the strip shows (set in the menu)
local PPR = WIDTH / FOV       -- pixels per radian (from the two)
local TICK_STEP = math.pi / 12 -- 15 degrees
local MARK = 28               -- the waypoint pin (bigger than the bar: it hangs below it)
local MARK_Y = -4             -- its center below the strip's, so its top stays on screen
local CHEVRON = 42            -- the chevrons framing the middle: their height
local CHEVRON_ATLAS = "covenantsanctum-renown-arrow"
local CENTER = "down"         -- the middle's marker: "down" (one under the bar) or "pair" (each side of the pin)
local CHEVRON_DIM = 0         -- their opacity while the waypoint is away from the middle
local CHEVRON_FADE_TICKS = 3  -- they fade in as the pin comes within 3 ticks of the middle
local CHEVRON_GAP = 6          -- from the middle to a chevron's inner edge
local TWO_PI = 2 * math.pi
local LILAC = { 0.72, 0.48, 1.00 } -- the suite's accent (PackPad's marks, MarketDeck's bar glow)
local PLUM = { 0.30, 0.13, 0.42 }  -- the pointer at rest: a dark plum (darker than MarketDeck's bar fill)

local LETTERS = { -- bearing (counter-clockwise from north), text, cardinal
    { 0, "N", true }, { math.pi / 4, "NW" }, { math.pi / 2, "W", true }, { 3 * math.pi / 4, "SW" },
    { math.pi, "S", true }, { 5 * math.pi / 4, "SE" }, { 3 * math.pi / 2, "E", true }, { 7 * math.pi / 4, "NE" },
}

local function DB() return ns.db end
function ns.CompassOn() return DB() and DB().compass ~= false end

local DEFAULT_WIDTH, DEFAULT_VIEW = 360, 180 -- pixels; degrees
-- What else rides the strip (each a menu toggle, all on to start): DB key -> on unless set false.
local function Shows(key) return not DB() or DB()[key] ~= false end
local function Width() return DB() and DB().compassWidth or DEFAULT_WIDTH end
local function View() return DB() and DB().compassView or DEFAULT_VIEW end

local W -- DeckKit.Waypoints
local frame, clip, backing, ticks, letters, pin, yards, dist, note
local chevrons, pointer = {}, nil
local over -- the layer above the strip, not clipped (the pin, the pointer, big marks)

-- An angle into (-pi, pi].
local function Wrap(a)
    a = a % TWO_PI
    if a > math.pi then a = a - TWO_PI end
    return a
end

-- Fades pieces out toward the ends of the strip.
local function EdgeAlpha(x)
    local t = math.abs(x) / (WIDTH / 2)
    return math.max(0, 1 - t * t * t * t)
end

-- Moving pieces glide between pixels instead of jumping: by default the client snaps each texture to the
-- pixel grid, so a 1 px tick sliding by fractions of a pixel (UI scale 0.96) hops from pixel to pixel
-- and flickers. Unsnapped, it's blended across the two (what a scrolled strip texture would do).
local function Glide(tex)
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end

local function Create()
    W = DeckKit.Waypoints
    frame = CreateFrame("Frame", "DeckHUDCompass", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    backing = frame:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(0.035, 0.035, 0.045, 0.9)

    clip = CreateFrame("Frame", nil, frame)
    clip:SetAllPoints()
    clip:SetClipsChildren(true)

    ticks = {}
    for i = 0, 23 do
        if i % 3 ~= 0 then -- every 45 degrees is a letter instead
            local t = clip:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(0.75, 0.75, 0.75, 1)
            t:SetSize(1, 5)
            Glide(t)
            ticks[#ticks + 1] = { tex = t, bearing = i * TICK_STEP }
        end
    end
    letters = {}
    for _, l in ipairs(LETTERS) do
        local fs = clip:CreateFontString(nil, "ARTWORK", l[3] and "GameFontNormalSmall" or "GameFontHighlightSmall")
        fs:SetText(l[2])
        if l[3] then fs:SetTextColor(LILAC[1], LILAC[2], LILAC[3]) else fs:SetTextColor(0.65, 0.65, 0.65) end
        letters[#letters + 1] = { fs = fs, bearing = l[1] }
    end

    -- On the frame, not the clipping strip, so it can hang below the bar (it's kept inside the ends).
    over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints()
    over:SetFrameLevel(clip:GetFrameLevel() + 5)
    -- The middle's marker, in one of two styles (CENTER). The art is the covenant renown arrow (it points
    -- left in the art), tinted lilac, turned with texture coordinates on the sheet: SetRotation on an
    -- atlas piece turns its coordinates on the whole sheet, so the neighbouring art shows through.
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CHEVRON_ATLAS)
    local function Chevron(coords, parent)
        local chev = (parent or over):CreateTexture(nil, "OVERLAY", nil, 2)
        if info then
            chev:SetTexture(info.file)
            chev:SetTexCoord(coords(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord))
        else
            chev:SetColorTexture(1, 1, 1, 1)
        end
        chev:SetDesaturated(true) -- then tinted lilac, like the letters
        chev:SetVertexColor(LILAC[1], LILAC[2], LILAC[3])
        return chev
    end
    local aspect = info and info.width / info.height or 0.5
    if CENTER == "pair" then
        -- "pair" (a good possibility, kept): one each side pointing out, level with the pin (hanging below
        -- the bar with it, cut off at the screen's top), unseen until the pin comes near (Chevrons below).
        for _, side in ipairs({ -1, 1 }) do
            local chev = Chevron(side < 0
                and function(l, r, t, b) return l, t, l, b, r, t, r, b end  -- as drawn: pointing left
                or function(l, r, t, b) return r, b, r, t, l, b, l, t end)  -- half way round: pointing right
            chevrons[#chevrons + 1] = chev
            chev:SetSize(CHEVRON * aspect, CHEVRON)
            chev:SetPoint(side < 0 and "RIGHT" or "LEFT", frame, "CENTER", side * CHEVRON_GAP, MARK_Y)
        end
    else
        -- "down": one, pointing down, centered under the bar and behind it, so it peeks out from under
        -- the bar's bottom edge. Its own frame, a stratum below the bar (it still shows and hides with
        -- the compass).
        local behind = CreateFrame("Frame", nil, frame)
        behind:SetAllPoints()
        behind:SetFrameStrata("LOW")
        pointer = Chevron(function(l, r, t, b) return r, t, l, t, r, b, l, b end, behind) -- a quarter turn: down
        pointer:SetSize(POINTER, POINTER * aspect) -- turned: the art's height runs across
    end

    pin = over:CreateTexture(nil, "OVERLAY", nil, 3)
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Waypoint-MapPin-Tracked")
        and pin:SetAtlas("Waypoint-MapPin-Tracked")) then
        pin:SetColorTexture(1, 0.82, 0, 1)
    end -- the pin keeps Blizzard's gold; the strip's own marks are lilac
    pin:SetSize(MARK, MARK)
    Glide(pin)
    -- The distance in yards, just a number, under the pin's tip (over the game, below the bar).
    yards = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local yfont = yards:GetFont()
    if yfont then yards:SetFont(yfont, 11, "OUTLINE") end
    dist = clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font = dist:GetFont()
    if font then dist:SetFont(font, 10, "OUTLINE") end
    note = clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("CENTER", clip, "CENTER", 0, 1)
end

local function Place()
    frame:ClearAllPoints()
    local bar = DeckHUDStatusBar
    if bar and bar:IsShown() then
        frame:SetParent(bar)
        frame:SetPoint("CENTER", bar, "CENTER", 0, 0)
        backing:Hide()
        if pointer then
            pointer:ClearAllPoints()
            pointer:SetPoint("TOP", frame, "BOTTOM", 0, POINTER_TRIM) -- tucked up behind the bar
        end
    else
        frame:SetParent(UIParent)
        frame:SetPoint("TOP", UIParent, "TOP", 0, 0)
        backing:Show()
        if pointer then
            pointer:ClearAllPoints()
            pointer:SetPoint("TOP", frame, "BOTTOM", 0, POINTER_TRIM)
        end
    end
end

local function At(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("CENTER", clip, "CENTER", x, y or 0)
end

-- The chevrons, unseen until the pin comes within 3 ticks of the middle, then fading in to full
-- lilac as it reaches the middle.
local function Chevrons(x)
    local a = CHEVRON_DIM
    if x then
        local t = 1 - math.abs(x) / (CHEVRON_FADE_TICKS * TICK_STEP * PPR)
        if t > 0 then a = CHEVRON_DIM + (1 - CHEVRON_DIM) * t end
    end
    for _, c in ipairs(chevrons) do c:SetAlpha(a) end
end

-- The down pointer: plum, warming to lilac as the pin comes within 45 degrees of the middle (lilac when
-- it's centered). x: the pin's offset in pixels, or nil (no pin on the strip).
local function Pointer(x)
    local t = 0
    if x then t = math.max(0, 1 - math.abs(x) / (POINTER_LIGHT * PPR)) end
    if not pointer then return t end
    pointer:SetVertexColor(PLUM[1] + (LILAC[1] - PLUM[1]) * t, PLUM[2] + (LILAC[2] - PLUM[2]) * t,
        PLUM[3] + (LILAC[3] - PLUM[3]) * t)
    return t
end

------------------------------------------------------------------------
-- Other marks on the strip: Blizzard's map pin, a guard's directions, party and raid members (with
-- their raid marker when they wear one). Positions are read 10 times a second (Collect); the strip
-- places them every frame against the live facing. They show only while they're in view (no parking
-- at the edge, unlike the waypoint) and fade toward the ends like the ticks.
--
-- The game gives positions for group members only, so a raid marker on a mob can't be shown: only
-- the ones party members wear.
------------------------------------------------------------------------

local marks = {}      -- { bearing, kind, unit or label } from the last Collect
local markPool = {}   -- textures, reused
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local MARK_SIZE = { blizzard = 22, guard = 26, member = 12, marked = 14 } -- guard: sized by eye against the pin (its flag fills its cell; the pin has margin)
-- Waypoint-like marks: on the unclipped layer, level with the waypoint pin, kept in view (Park).
local BIG = { guard = true, blizzard = true }
local MARK_DROP = { guard = 2 }  -- hung this much lower than the pin
local SOLID = { guard = true }   -- full strength even while waiting at an end

-- /deckkit compass test: pretend party members at fixed bearings round you (so they slide as you turn),
-- for sizing and looks without a group. Bearings are set from where you face when it's turned on.
local fakes
local FAKE = { -- bearing (from your facing then; counter-clockwise), class, raid marker
    { 0.35, "PRIEST" }, { -0.6, "WARRIOR" }, { 1.1, "MAGE", 1 }, { -1.3, "HUNTER" },
    { 0.12, "DRUID", 8 }, { 2.6, "ROGUE" }, { -0.25, "PALADIN" },
}
local function AddFakes()
    if not fakes then return end
    for _, f in ipairs(fakes) do
        local icon = f.icon and Shows("compassRaidMarks") and f.icon
        marks[#marks + 1] = { bearing = f.bearing, kind = icon and "marked" or "member", class = f.class, icon = icon }
    end
end

local function Bearing(pmap, px, py, mapID, x, y)
    local pc, pn, pw = W.WorldPosition(pmap, px, py)
    local c, n, w = W.WorldPosition(mapID, x, y)
    if not (pc and c) or pc ~= c then return end
    local dN, dW = n - pn, w - pw
    if dN == 0 and dW == 0 then return end
    return math.atan2(dW, dN)
end

local function Collect()
    wipe(marks)
    if Shows("compassGroup") then AddFakes() end
    local pmap, px, py = W.PlayerPosition()
    if not pmap then return end
    -- Blizzard's own map pin (the one you place on the world map).
    if Shows("compassBlizzardPin") and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
        local point = C_Map.GetUserWaypoint()
        if point and point.position then
            local px2, py2 = point.position:GetXY()
            local b = Bearing(pmap, px, py, point.uiMapID, px2, py2)
            if b then marks[#marks + 1] = { bearing = b, kind = "blizzard" } end
        end
    end
    -- A guard's directions (the flag a city guard puts on your map).
    if Shows("compassGuard") and C_GossipInfo and C_GossipInfo.GetPoiForUiMapID then
        local poiID = C_GossipInfo.GetPoiForUiMapID(pmap)
        local info = poiID and C_GossipInfo.GetPoiInfo(pmap, poiID)
        if info and info.position then
            local gx, gy = info.position:GetXY()
            local b = Bearing(pmap, px, py, pmap, gx, gy)
            if b then marks[#marks + 1] = { bearing = b, kind = "guard", index = info.textureIndex } end
        end
    end
    -- Party or raid members, as class-colored dots, or their raid marker.
    if Shows("compassGroup") and IsInGroup() then
        local raid = IsInRaid()
        for i = 1, raid and 40 or 4 do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local ok, pos = pcall(C_Map.GetPlayerMapPosition, pmap, unit)
                if ok and pos then
                    local ux, uy = pos:GetXY()
                    local b = W.Readable(ux) and W.Readable(uy) and (ux ~= 0 or uy ~= 0)
                        and Bearing(pmap, px, py, pmap, ux, uy)
                    if b then
                        local icon = Shows("compassRaidMarks") and GetRaidTargetIndex(unit)
                        marks[#marks + 1] = { bearing = b, kind = icon and "marked" or "member", unit = unit, icon = icon }
                    end
                end
            end
        end
    end
end

local bigPool = {}
local function MarkTexture(pool, i, layer)
    local t = pool[i]
    if not t then
        t = layer:CreateTexture(nil, "OVERLAY", nil, 1)
        Glide(t)
        pool[i] = t
    end
    return t
end

local function Paint(t, m)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetVertexColor(1, 1, 1)
    if m.kind == "blizzard" then
        t:SetAtlas("Waypoint-MapPin-Untracked")
    elseif m.kind == "guard" then
        -- The guard's flag, as the world map draws it: a cell of the minimap's POI sheet.
        local x1, x2, y1, y2
        if m.index and C_Minimap and C_Minimap.GetPOITextureCoords then
            x1, x2, y1, y2 = C_Minimap.GetPOITextureCoords(m.index)
        end
        if x1 then
            t:SetTexture("Interface/Minimap/POIIcons")
            t:SetTexCoord(x1, x2, y1, y2)
        else
            t:SetAtlas("VignetteEvent")
        end
    elseif m.kind == "marked" then
        t:SetTexture(RAID_ICON:format(m.icon))
    else
        t:SetAtlas("WhiteCircle-RaidBlips")
        local class = m.class or select(2, UnitClass(m.unit))
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then t:SetVertexColor(c.r, c.g, c.b) end
    end
    local size = MARK_SIZE[m.kind]
    t:SetSize(size, size)
end

-- Waypoints (DeckKit's, Blizzard's pin, a guard's flag) stay on the strip: out of view, each waits at the
-- nearer end, and several at one end stand side by side, the furthest round at the very end, the rest in
-- toward the middle. One pass per side, from the end inward: each is pushed in only as far as it must to
-- clear the one outside it, so one coming toward the end slides up against those waiting there instead
-- of running into them and jumping. The chain stops at the first one that needn't move, so marks out in
-- the strip keep their true places. Sets px (where it's drawn) and parked (moved from its true place).
local STACK_MAX, STACK_GAP = 4, 2
local EASE = 14     -- how fast a waiting mark glides to a new place in the line (per second; ~0.2 s)
local shown = {}    -- id -> { px, side, parked }: where each waiting mark was last drawn
local function Park(items, elapsed)
    for _, side in ipairs({ -1, 1 }) do
        local list = {}
        for _, it in ipairs(items) do
            if (it.x > 0 and 1 or -1) == side then list[#list + 1] = it end
        end
        table.sort(list, function(p, q) return math.abs(p.x) > math.abs(q.x) end)
        local limit, moved, last = WIDTH / 2 - 2, 0, nil -- the innermost free spot, from the middle
        for _, it in ipairs(list) do
            local want = math.abs(it.x)
            local pos = math.min(want, limit - it.size / 2)
            if pos < want then
                moved = moved + 1
                if moved > STACK_MAX then pos = last end
                last = pos
                it.parked = true
                limit = pos - it.size / 2 - STACK_GAP
            else
                it.parked = false
                limit = math.huge -- nothing outside it pushes further in
            end
            it.px = side * pos
            -- A waiting mark whose place in the line changes (one beside it left for the other end, or
            -- came in) glides there instead of jumping; one just arrived, out in the strip, or crossing
            -- to the other end goes straight to its place.
            local st = it.id and shown[it.id]
            if st and it.parked and st.parked and st.side == side then
                st.px = st.px + (it.px - st.px) * math.min(1, (elapsed or 0) * EASE)
                it.px = st.px
            elseif it.id then
                shown[it.id] = { px = it.px, side = side, parked = it.parked }
                st = shown[it.id]
            end
            if st then st.parked, st.side = it.parked, side end
        end
    end
end

local function DrawMarks(facing, waypoint, elapsed)
    local n, nb = 0, 0
    local parkable = { waypoint }
    for _, m in ipairs(marks) do
        m.x = -Wrap(m.bearing - facing) * PPR
        if BIG[m.kind] then
            m.size = MARK_SIZE[m.kind]
            m.id = m.kind -- one of each (Blizzard's pin, a guard's flag)
            parkable[#parkable + 1] = m
        end
    end
    Park(parkable, elapsed)
    for _, m in ipairs(marks) do
        if BIG[m.kind] then
            -- A waypoint-like mark: kept in view, full strength (dimmed while waiting at an end), hanging
            -- below the bar like the pin.
            nb = nb + 1
            local t = MarkTexture(bigPool, nb, over)
            Paint(t, m)
            At(t, m.px, MARK_Y - (MARK_DROP[m.kind] or 0))
            t:SetAlpha((m.parked and not SOLID[m.kind]) and 0.6 or 1)
            t:Show()
        else
            local a = EdgeAlpha(m.x)
            if a > 0 then
                n = n + 1
                local t = MarkTexture(markPool, n, clip)
                Paint(t, m)
                At(t, m.x, 1)
                t:SetAlpha(a)
                t:Show()
            end
        end
    end
    for i = n + 1, #markPool do markPool[i]:Hide() end
    for i = nb + 1, #bigPool do bigPool[i]:Hide() end
end

local function Draw(_, elapsed)
    local facing = W.Facing()
    if not facing then
        for _, t in ipairs(ticks) do t.tex:Hide() end
        for _, l in ipairs(letters) do l.fs:Hide() end
        pin:Hide(); yards:Hide(); dist:Hide()
        for _, t in ipairs(markPool) do t:Hide() end
        for _, t in ipairs(bigPool) do t:Hide() end
        note:SetText("|cff9d9d9dNo heading here|r")
        note:Show()
        return
    end
    for _, t in ipairs(ticks) do
        local x = -Wrap(t.bearing - facing) * PPR
        local a = EdgeAlpha(x)
        if a > 0 then At(t.tex, x, 1); t.tex:SetAlpha(a); t.tex:Show() else t.tex:Hide() end
    end
    for _, l in ipairs(letters) do
        local x = -Wrap(l.bearing - facing) * PPR
        local a = EdgeAlpha(x)
        if a > 0 then At(l.fs, x, 1); l.fs:SetAlpha(a); l.fs:Show() else l.fs:Hide() end
    end

    local g = W.guide
    local wp = (not W.arrival and g and g.state == "ok" and g.bearing)
        and { x = -Wrap(g.bearing - facing) * PPR, size = MARK, id = "waypoint" } or nil
    DrawMarks(facing, wp, elapsed)
    Chevrons(nil)
    Pointer(nil)
    if W.arrival then
        pin:Hide(); yards:Hide(); dist:Hide()
        note:SetText("|cff40ff40Arrived|r  " .. (W.arrival.label or ""))
        note:Show()
        return
    end
    note:Hide()
    if wp then
        local x, off = wp.px, wp.parked
        At(pin, x, MARK_Y)
        Chevrons(not off and x or nil)
        -- The distance tucks under the pin, and drops away from it (clearing the pointer) as the pin
        -- comes to the middle, in step with the pointer's color.
        local near = Pointer(not off and x or nil)
        yards:ClearAllPoints()
        yards:SetPoint("TOP", pin, "BOTTOM", 0, 1 - (YARDS_DROP + 1) * near)
        pin:SetAlpha(off and 0.6 or 1)
        pin:Show()
        yards:SetText(string.format("%d", g.yards + 0.5))
        yards:SetAlpha(off and 0.6 or 1)
        yards:Show()
        dist:Hide()
    elseif g and g.state == "far" then
        pin:Hide(); yards:Hide()
        dist:SetText("|cff9d9d9dWaypoint in " .. W.MapName(g.point.mapID) .. "|r")
        dist:ClearAllPoints()
        dist:SetPoint("RIGHT", clip, "RIGHT", -4, 1)
        dist:Show()
    else
        pin:Hide(); yards:Hide(); dist:Hide()
    end
end

-- The strip's width and view from the menu.
local function Size()
    WIDTH = Width()
    FOV = math.rad(View())
    PPR = WIDTH / FOV
    if frame then frame:SetSize(WIDTH, HEIGHT) end
end

ns.AddCommand("compass", function(msg)
    if (msg or ""):lower():match("^test") then
        if fakes then
            fakes = nil
            ns.Print("Compass test off.")
        else
            local facing = W and W.Facing() or 0
            fakes = {}
            for _, f in ipairs(FAKE) do
                fakes[#fakes + 1] = { bearing = (facing or 0) + f[1], class = f[2], icon = f[3] }
            end
            ns.Print("Compass test: pretend party members round you. /deckkit compass test again to clear.")
        end
    else
        ns.Print("/deckkit compass test: pretend party members on the compass (again to clear).")
    end
end, "DeckHUD: the compass (test: pretend party members)")

local collector
local function Apply()
    Size()
    if ns.CompassOn() then
        if not frame then Create() end
        Place()
        frame:SetScript("OnUpdate", Draw)
        frame:Show()
        if not collector then collector = C_Timer.NewTicker(0.1, function() if frame:IsShown() then Collect() end end) end
    elseif frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    if ns.StatusBarUpdate then ns.StatusBarUpdate() end -- the clock moves aside, or back
end
ns.CompassApply = Apply

ns.On("PLAYER_LOGIN", function() C_Timer.After(1, Apply) end) -- after the status bar (0.5 s)
