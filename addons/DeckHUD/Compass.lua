-- DeckHUD: the compass. A strip across the middle of the status bar, centered on the way you face (180
-- degrees of horizon in 360 px to start; both set in Quests > Compass): ticks every 15 degrees and
-- N, NE, E... slide past as you turn, and an ornament hangs from the bar's middle as the pointer, its gem
-- plum at rest, lilac as the waypoint comes within 45 degrees. On the strip:
--   * the active waypoint (DeckKit.Waypoints): the lilac pin, hanging below the bar, pointing along the walk
--     there (its next corner, when ForeverNav has a walk), with the time to get there under it at your run
--     speed (dropping clear of the pointer as it reaches the middle); on a route, under the pointer instead:
--     the step and its time, and below it, dimmer, where the trip ends and the whole time; "Arrived" when reached
--   * Blizzard's map pin and a guard's directions (the flag), sized and hung like the pin
--   * the focused quest (the game's super-tracked one), drawn as Blizzard's map and objective tracker draw
--     it: its classification's disc (gold, blue for dailies...) with the dots, or the ? once complete;
--     pulsing with the map's quest glow while you stand in its area (DeckKit.Map.QuestArea)
--   * your corpse, while you're dead or a ghost: the tombstone the world map draws for it, with its distance
--     in yards under it, as the waypoint's
--   * your group: class-colored dots, or the raid marker one wears
-- Waypoint-like marks (the corpse too) stay on the strip: out of view they wait at the nearer end, side by side (Park).
-- Group dots fade toward the ends like the ticks. Each kind of mark is a menu toggle.
--
-- The strip isn't one long image: the ticks and letters are separate pieces placed each frame inside a
-- frame that clips them (unsnapped from the pixel grid, so they glide), so they stay crisp. With the
-- status bar off, the compass sits at the top of the screen on its own dark backing. The status bar's
-- middle readings (the clock) move to the front of its right side while the compass is on.
-- /deckkit compass test puts pretend party members on it.
local _, ns = ...

local WIDTH, HEIGHT = 360, 20 -- the strip (set in the menu: Size below); the status bar's height
-- The pointer: Ben's drawing of a winged ornament with a gem, cut out by deck-setup/make-compass-pointer.py (which
-- describes the texture): the metal in rows 0..25 of a 128 x 64 sheet, the gem in gray in rows 32..57, both 96 wide.
local POINTER_FILE = "Interface\\AddOns\\DeckHUD\\media\\compass-pointer"
local POINTER_W, POINTER_H = 96, 26
local POINTER_TEX = { 0, 96 / 128, 0, 26 / 64 }       -- the metal
local GEM_TEX = { 0, 96 / 128, 32 / 64, 58 / 64 }     -- the gem
local POINTER_TOP = 5         -- its top above the frame's bottom: its 6 px of bar sit over the status bar's 4 px metal edge
local GEM_REST = 0.35         -- the gem at rest: this far from plum toward lilac (plum itself is too dark to see)
local POINTER_LIGHT = math.pi / 4 -- it turns from plum to lilac as the pin comes within 45 degrees of the middle
local YARDS_DROP = 15         -- how far the distance drops below the pin at the middle, to clear the pointer
local FOV = math.pi           -- how much of the horizon the strip shows (set in the menu)
local PPR = WIDTH / FOV       -- pixels per radian (from the two)
local TICK_STEP = math.pi / 12 -- 15 degrees
local MARK = 28               -- the waypoint pin (bigger than the bar: it hangs below it)
local MARK_Y = -4             -- its center below the strip's, so its top stays on screen
local TWO_PI = 2 * math.pi
local LILAC, PLUM = DeckKit.COLORS.LILAC, DeckKit.COLORS.PLUM -- the suite's accent; the pointer at rest

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
local frame, clip, backing, ticks, letters, pin, yards, dist, note, step, trip
local pointer, gem
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
    -- The pointer: over the status bar's metal edge, under the pin and the other marks (ARTWORK, below their
    -- OVERLAY), the metal as drawn and the gem tinted by Pointer() below.
    pointer = over:CreateTexture(nil, "ARTWORK", nil, 1)
    pointer:SetTexture(POINTER_FILE)
    pointer:SetTexCoord(unpack(POINTER_TEX))
    pointer:SetSize(POINTER_W, POINTER_H)
    gem = over:CreateTexture(nil, "ARTWORK", nil, 2)
    gem:SetTexture(POINTER_FILE)
    gem:SetTexCoord(unpack(GEM_TEX))
    gem:SetAllPoints(pointer)

    pin = over:CreateTexture(nil, "OVERLAY", nil, 3)
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Waypoint-MapPin-Tracked")
        and pin:SetAtlas("Waypoint-MapPin-Tracked")) then
        pin:SetColorTexture(1, 1, 1, 1)
    end
    -- The suite's lilac: Blizzard's gold pin, its color taken out, then tinted (WayPad's map pins match).
    pin:SetDesaturated(true)
    pin:SetVertexColor(LILAC[1], LILAC[2], LILAC[3])
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
    -- The route's current step, when the waypoint has a route (DeckKit.Route): one line under the pointer.
    step = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local sfont = step:GetFont()
    if sfont then step:SetFont(sfont, 11, "OUTLINE") end
    step:SetPoint("TOP", pointer, "BOTTOM", 0, -1)
    step:Hide()
    -- Under it, dimmer: where the trip ends, and the time for all of it.
    trip = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if sfont then trip:SetFont(sfont, 11, "OUTLINE") end
    trip:SetPoint("TOP", step, "BOTTOM", 0, -1)
    trip:SetTextColor(0.62, 0.62, 0.62)
    trip:Hide()
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
            pointer:SetPoint("TOP", frame, "BOTTOM", 0, POINTER_TOP) -- its bar over the status bar's edge
        end
    else
        frame:SetParent(UIParent)
        frame:SetPoint("TOP", UIParent, "TOP", 0, 0)
        backing:Show()
        if pointer then
            pointer:ClearAllPoints()
            pointer:SetPoint("TOP", frame, "BOTTOM", 0, POINTER_TOP)
        end
    end
end

local function At(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("CENTER", clip, "CENTER", x, y or 0)
end

-- The pointer: plum, warming to lilac as the pin comes within 45 degrees of the middle (lilac when
-- it's centered). x: the pin's offset in pixels, or nil (no pin on the strip).
local function Pointer(x)
    local t = 0
    if x then t = math.max(0, 1 - math.abs(x) / (POINTER_LIGHT * PPR)) end
    if not gem then return t end
    local c = GEM_REST + (1 - GEM_REST) * t
    gem:SetVertexColor(PLUM[1] + (LILAC[1] - PLUM[1]) * c, PLUM[2] + (LILAC[2] - PLUM[2]) * c,
        PLUM[3] + (LILAC[3] - PLUM[3]) * c)
    return t
end

------------------------------------------------------------------------
-- Other marks on the strip: Blizzard's map pin, a guard's directions, party and raid members (with
-- their raid marker when they wear one). Positions are read 10 times a second (Collect); the strip
-- places them every frame against the live facing. Blizzard's pin and the guard's flag behave like the
-- waypoint (kept in view, waiting at the ends: Park); group members show only while in view and fade
-- toward the ends like the ticks.
--
-- The game gives positions for group members only, so a raid marker on a mob can't be shown: only
-- the ones party members wear.
------------------------------------------------------------------------

local marks = {}      -- { bearing, kind, unit or label } from the last Collect
local markPool = {}   -- textures, reused
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local MARK_SIZE = { blizzard = 22, guard = 26, quest = 26, corpse = 20, member = 12, marked = 14 } -- guard: sized by eye against the pin (its flag fills its cell; the pin has margin)
-- Waypoint-like marks: on the unclipped layer, level with the waypoint pin, kept in view (Park).
local BIG = { guard = true, blizzard = true, quest = true, corpse = true }
local PULSE = 4 -- the in-area glow's beat (radians a second: about one and a half a second)
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

local Bearing = DeckKit.Map.Bearing

-- The focused quest's spot: where the map draws its icon (its area, or the turn-in once complete), on the
-- map you're in or the first one above it that has it (zone, then continent). x, y, map; nil if none.
local function QuestSpot(questID, pmap)
    local m = pmap
    for _ = 1, 4 do
        if not m or m == 0 then return end
        for _, q in ipairs(C_QuestLog.GetQuestsOnMap(m) or {}) do
            if q.questID == questID and q.x then return q.x, q.y, m end
        end
        local info = C_Map.GetMapInfo(m)
        m = info and info.parentMapID
    end
end

-- Blizzard's quest icons (Blizzard_POIButton/POIButton.lua): a disc per classification (the focused
-- look: "-SuperTracked"), and on it the in-progress dots or the classification's turn-in mark.
local QC = Enum.QuestClassification or {}
local DISC = { [QC.Legendary or -1] = "UI-QuestPoiLegendary-QuestNumber", [QC.Campaign or -2] = "UI-QuestPoiCampaign-QuestNumber",
    [QC.Calling or -3] = "UI-QuestPoiCampaign-QuestNumber", [QC.Recurring or -4] = "UI-QuestPoiRecurring-QuestNumber",
    [QC.Important or -5] = "UI-QuestPoiImportant-QuestNumber", [QC.Meta or -6] = "UI-QuestPoiWrapper-QuestNumber" }
local TURN_IN = { [QC.Legendary or -1] = "UI-QuestPoiLegendary-QuestBangTurnIn", [QC.Campaign or -2] = "UI-QuestPoiCampaign-QuestBangTurnIn",
    [QC.Calling or -3] = "UI-DailyQuestPoiCampaign-QuestBangTurnIn", [QC.Recurring or -4] = "UI-QuestPoiRecurring-QuestBangTurnIn",
    [QC.Important or -5] = "UI-QuestPoiImportant-QuestBangTurnIn", [QC.Meta or -6] = "UI-QuestPoiWrapper-QuestBangTurnIn" }
local function QuestAtlases(questID)
    local class = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification
        and C_QuestInfoSystem.GetQuestClassification(questID)
    local disc = (DISC[class] or "UI-QuestPoi-QuestNumber") .. "-SuperTracked"
    local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    return disc, done and (TURN_IN[class] or "UI-QuestIcon-TurnIn-Normal") or "Quest-In-Progress-Icon-Brown"
end

local questArea, insideOf, inside -- the focused quest's area tester; which quest, and are you in it

local function Collect()
    wipe(marks)
    if Shows("compassGroup") then AddFakes() end
    local pmap, px, py = DeckKit.Map.PlayerPosition()
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
    -- The focused quest (super tracked: the one the map and objective tracker single out), and whether
    -- you're in its area (kept from the last answer while the area can't tell yet).
    -- Not while the leveling guide is on screen (GuidePad's panel): its waypoint is the one to follow.
    local guide = _G.GuidePadPanel and _G.GuidePadPanel:IsShown()
    if Shows("compassQuest") and not guide and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local q = C_SuperTrack.GetSuperTrackedQuestID()
        if q and q > 0 then
            questArea = questArea or DeckKit.Map.QuestArea()
            if q ~= insideOf then insideOf, inside = q, false end
            local hit, pending = questArea:At({ q })
            if not pending then inside = hit == q end
            local qx, qy, qmap = QuestSpot(q, pmap)
            local b = qx and Bearing(pmap, px, py, qmap, qx, qy)
            if b then marks[#marks + 1] = { bearing = b, kind = "quest", quest = q, inside = inside } end
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
    -- Your corpse while you're dead or a ghost: asked on your map first, then the maps above it (a ghost at a
    -- graveyard in the next zone still gets a bearing from the continent's map).
    if Shows("compassCorpse") and UnitIsDeadOrGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        local m = pmap
        for _ = 1, 4 do
            if not m or m == 0 then break end
            local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
            local cx, cy
            if ok and pos then cx, cy = pos:GetXY() end
            if DeckKit.Readable(cx) and DeckKit.Readable(cy) and (cx ~= 0 or cy ~= 0) then
                local b = Bearing(pmap, px, py, m, cx, cy)
                local _, fn, fw = DeckKit.Map.WorldPosition(pmap, px, py)
                local _, tn, tw = DeckKit.Map.WorldPosition(m, cx, cy)
                local yd = fn and tn and math.sqrt((tn - fn) ^ 2 + (tw - fw) ^ 2) or nil
                if b then marks[#marks + 1] = { bearing = b, kind = "corpse", yards = yd } end
                break
            end
            local info = C_Map.GetMapInfo(m)
            m = info and info.parentMapID
        end
    end
    -- Party or raid members, as class-colored dots, or their raid marker.
    if Shows("compassGroup") and IsInGroup() then
        local raid = IsInRaid()
        for i = 1, raid and 40 or 4 do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local ux, uy = DeckKit.Map.UnitPosition(unit, pmap)
                local b = ux and Bearing(pmap, px, py, pmap, ux, uy)
                if b then
                    local icon = Shows("compassRaidMarks") and GetRaidTargetIndex(unit)
                    marks[#marks + 1] = { bearing = b, kind = icon and "marked" or "member", unit = unit, icon = icon }
                end
            end
        end
    end
end

local bigPool = {}
-- A mark's texture, with a second one riding on it (t.top: a quest disc's dots or ?), hidden and faded
-- along with it.
local function MarkTexture(pool, i, layer)
    local t = pool[i]
    if not t then
        t = layer:CreateTexture(nil, "OVERLAY", nil, 1)
        Glide(t)
        t.top = layer:CreateTexture(nil, "OVERLAY", nil, 2)
        Glide(t.top)
        t.top:SetPoint("CENTER", t)
        t.top:Hide()
        -- Behind it: the map's quest glow, pulsing while you're in the focused quest's area.
        t.glow = layer:CreateTexture(nil, "OVERLAY", nil, 0)
        Glide(t.glow)
        t.glow:SetAtlas("UI-QuestPoi-OuterGlow")
        t.glow:SetBlendMode("ADD")
        t.glow:SetPoint("CENTER", t)
        t.glow:Hide()
        local hide, alpha = t.Hide, t.SetAlpha
        function t:Hide() hide(self); self.top:Hide(); self.glow:Hide(); if self.yards then self.yards:Hide() end end
        function t:SetAlpha(a) alpha(self, a); self.top:SetAlpha(a) end
        pool[i] = t
    end
    return t
end

local function Paint(t, m)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetVertexColor(1, 1, 1)
    t.top:Hide()
    if m.kind == "quest" then
        local disc, top = QuestAtlases(m.quest)
        t:SetAtlas(disc)
        t.top:SetAtlas(top)
        -- The mark at its size against the disc's, as the map draws them.
        local d, o = C_Texture.GetAtlasInfo(disc), C_Texture.GetAtlasInfo(top)
        local k = (d and o and d.width > 0) and o.width / d.width or 0.7
        t.top:SetSize(MARK_SIZE.quest * k, MARK_SIZE.quest * k * ((o and o.width > 0) and o.height / o.width or 1))
        t.top:Show()
    elseif m.kind == "blizzard" then
        t:SetAtlas("Waypoint-MapPin-Untracked")
    elseif m.kind == "corpse" then
        -- The world map's tombstone (MapDeck draws it the same); the gray pin if this client lacks it.
        if not (C_Texture.GetAtlasInfo("poi-graveyard-neutral") and t:SetAtlas("poi-graveyard-neutral")) then
            t:SetAtlas("Waypoint-MapPin-Untracked")
        end
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
            -- The corpse's distance, under it as the waypoint's is under the pin: dropping clear of the pointer
            -- as it comes to the middle.
            if m.kind == "corpse" and m.yards then
                if not t.yards then
                    t.yards = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    local yfont = t.yards:GetFont()
                    if yfont then t.yards:SetFont(yfont, 11, "OUTLINE") end
                end
                local near = m.parked and 0 or math.max(0, 1 - math.abs(m.px) / (POINTER_LIGHT * PPR))
                t.yards:ClearAllPoints()
                t.yards:SetPoint("TOP", t, "BOTTOM", 0, 1 - (YARDS_DROP + 1) * near)
                t.yards:SetText(string.format("%d", m.yards + 0.5))
                t.yards:SetAlpha(m.parked and 0.6 or 1)
                t.yards:Show()
            elseif t.yards then
                t.yards:Hide()
            end
            if m.inside then
                local s = MARK_SIZE.quest * 2 -- the glow's art is twice the disc's
                t.glow:SetSize(s, s)
                t.glow:SetAlpha(0.3 + 0.6 * (0.5 + 0.5 * math.sin(GetTime() * PULSE)))
                t.glow:Show()
            else
                t.glow:Hide()
            end
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

-- The strip follows your facing smoothly: it eases toward it (SMOOTH per second, exponential) instead of
-- jumping with each step of the camera, a short glide that still keeps up with a fast turn.
local SMOOTH = 16
local shownFacing

-- How far the route's lines under the pointer reach below the compass (0 when none show), for the mouseover
-- tooltip (Tooltip.lua), which moves down to clear them.
function ns.CompassLinesHeight()
    if not (step and step:IsShown()) then return 0 end
    return step:GetStringHeight() + 1 + ((trip and trip:IsShown()) and (trip:GetStringHeight() + 1) or 0)
end

-- The route's step under the pointer: shown whenever the waypoint has one, whatever else the strip shows.
local function Step(g)
    if not step then return end
    local leg = not W.arrival and g and g.leg
    if leg then
        -- The step and its own time; under it, dimmer, where the trip ends and the time for all of it.
        local when = g.legEta and ("  (" .. W.FormatETA(g.legEta) .. ")") or ""
        local r = g.ride
        if r then -- a ride: when it leaves, then when it gets there; "~" while the route was never timed
            when = r.departIn > 0 and ("  (leaves in " .. (r.guess and "~" or "") .. W.FormatETA(r.departIn) .. ")")
                or ("  (arrives in " .. (r.guess and "~" or "") .. W.FormatETA(r.arriveIn) .. ")")
        end
        step:SetText(leg.text .. when)
        step:Show()
        local dest = g.goal and g.goal.point
        local name = dest and (dest.label or DeckKit.Map.Name(dest.mapID))
        if name and g.eta then
            trip:SetTextColor(0.62, 0.62, 0.62) -- dimmer: the whole trip, under the step
            trip:SetText(name .. "  (" .. W.FormatETA(g.eta) .. ")")
            trip:Show()
        else
            trip:Hide()
        end
    else
        -- No route step: aboard a boat or zeppelin, where it's going; else at a dock (or a pair of towers), what
        -- leaves (the first two, soonest), in the same two lines.
        local lines = {}
        local aboard = not W.arrival and DeckKit.Route and DeckKit.Route.Riding and DeckKit.Route.Riding()
        if aboard then
            step:SetText("On the " .. aboard.kind .. (aboard.to and (" to " .. aboard.to) or "")
                .. (aboard.arriveIn and ("  (arrives in " .. W.FormatETA(aboard.arriveIn) .. ")") or ""))
            step:Show()
            trip:Hide()
            return
        end
        local b = not W.arrival and DeckKit.Route and DeckKit.Route.DockBoard and DeckKit.Route.DockBoard()
        for i, d in ipairs(b and b.departures or {}) do
            if i > 2 then break end
            local kind = d.kind:sub(1, 1):upper() .. d.kind:sub(2)
            local when
            if not d.known then when = "not timed yet"
            elseif d.docked then when = "boarding, leaves in " .. W.FormatETA(d.departIn)
            elseif d.arriveIn then when = "arrives in " .. W.FormatETA(d.arriveIn) -- en route here: when it docks
            else when = "leaves in " .. W.FormatETA(d.departIn) end
            lines[i] = kind .. " to " .. d.to .. "  (" .. when .. ")"
        end
        if lines[1] then step:SetText(lines[1]) step:Show() else step:Hide() end
        if lines[2] then trip:SetTextColor(1, 1, 1) trip:SetText(lines[2]) trip:Show() else trip:Hide() end
    end
end

local function Draw(_, elapsed)
    Step(W.guide)
    local facing = DeckKit.Map.Facing()
    if facing then
        if shownFacing then
            shownFacing = shownFacing + Wrap(facing - shownFacing) * math.min(1, (elapsed or 0) * SMOOTH)
        else
            shownFacing = facing
        end
        facing = shownFacing
    else
        shownFacing = nil
    end
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
    -- The pin follows the walk (the next corner of the path), else points straight at the waypoint.
    local bearing = g and (g.steer and g.steer.bearing or g.bearing)
    local wp = (not W.arrival and g and g.state == "ok" and bearing)
        and { x = -Wrap(bearing - facing) * PPR, size = MARK, id = "waypoint" } or nil
    DrawMarks(facing, wp, elapsed)
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
        -- The distance tucks under the pin, and drops away from it (clearing the pointer) as the pin
        -- comes to the middle, in step with the pointer's color.
        local near = Pointer(not off and x or nil)
        yards:ClearAllPoints()
        yards:SetPoint("TOP", pin, "BOTTOM", 0, 1 - (YARDS_DROP + 1) * near)
        pin:SetAlpha(off and 0.6 or 1)
        pin:Show()
        -- The time under the pin, unless the route's step line above says it (the whole trip, Step).
        yards:SetText(g.eta and W.FormatETA(g.eta) or string.format("%d", g.yards + 0.5))
        yards:SetAlpha(off and 0.6 or 1)
        yards:SetShown(not g.leg)
        dist:Hide()
    elseif g and g.state == "far" then
        pin:Hide(); yards:Hide()
        dist:SetText("|cff9d9d9dWaypoint in " .. DeckKit.Map.Name(g.point.mapID) .. "|r")
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
            local facing = DeckKit.Map.Facing() or 0
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
