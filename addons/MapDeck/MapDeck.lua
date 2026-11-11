-- MapDeck: hold a button to see the map full-screen.
--
-- This draws the map itself (the zone's art tiles plus the explored-area overlays) instead of
-- opening Blizzard's map window, so it works in combat and fills the screen. On it: you (an
-- arrow that turns with you), your party, quests (? / ! / in progress), the tracked quest's
-- areas, WayPad's waypoints, the game's map pin, where a guard pointed you, flight masters, dungeon
-- entrances, your raid, zone names on a continent, your corpse and (while dead) the spirit healer.
-- While it's up the frame takes the gamepad sticks, like ChatDeck: the right stick zooms out
-- (up: zone -> continent) and back in (down). The camera stays still; auto-run keeps going.
--
-- /mapdeck   show / hide (for testing at a desk)
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff8fd16fMapDeck|r")

local MARGIN, HEADER = 24, 44
local TILE = 256
local DEADZONE, STEP = 0.6, 0.35 -- zoom: push past 60%, at most one step per 0.35 s

local frame, canvas, art, marks, blob, title, coords, hint
local tiles, overlays, dots, backs = {}, {}, {}, {}
local playerArrow
local mapID, homeMap -- shown map; the map you're standing in
local layerW, layerH = 1, 1
local stickY, cooldown = 0, 0

local function Readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function MapInfo(id)
    local ok, info = pcall(C_Map.GetMapInfo, id)
    return ok and info or nil
end

-- A point on one map, on another (parent or child). nil when it's off that map.
local function Translate(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, fromMap, toMap)
    if ok and Readable(minX) and Readable(maxY) and maxX > minX and maxY > minY then
        x, y = minX + x * (maxX - minX), minY + y * (maxY - minY)
    else
        ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, toMap, fromMap)
        if not (ok and Readable(minX) and Readable(maxY) and maxX > minX and maxY > minY) then return end
        x, y = (x - minX) / (maxX - minX), (y - minY) / (maxY - minY)
    end
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    return x, y
end

local function UnitPos(unit, onMap)
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, onMap, unit)
    if not (ok and pos) then return end
    local x, y = pos:GetXY()
    if Readable(x) and Readable(y) and (x ~= 0 or y ~= 0) then return x, y end
end

-- Your corpse, on whichever map we ask about (zone or continent). Blizzard's map draws it as a tombstone.
local function CorpsePos(onMap)
    local getCorpse = C_DeathInfo and C_DeathInfo.GetCorpseMapPosition
    if not getCorpse then return end
    local ok, pos = pcall(getCorpse, onMap)
    if not (ok and pos) then return end
    local x, y = pos:GetXY()
    if Readable(x) and Readable(y) and (x ~= 0 or y ~= 0) then return x, y end
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------

local function Pool(list, i, layer, sub, owner)
    local t = list[i]
    if not t then
        t = (owner or art):CreateTexture(nil, layer, nil, sub)
        list[i] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function HideFrom(list, n)
    for i = n, #list do list[i]:Hide() end
end

-- Text on the map lives on an unscaled layer above the markers, so it stays readable at any zoom.
local labelLayer
local function Label(list, i, font)
    local l = list[i]
    if not l then
        l = labelLayer:CreateFontString(nil, "OVERLAY", font)
        l:SetShadowOffset(1, -1)
        list[i] = l
    end
    l:ClearAllPoints()
    l:Show()
    return l
end

-- A texture file (Interface\...) in place of an atlas, if the game has it.
local function UseFile(t, file)
    t:SetTexture(file)
    if t.GetTextureFileID and not t:GetTextureFileID() then return false end
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t:SetVertexColor(1, 1, 1, 1)
    return true
end

-- Fit the art (layer pixels) into the screen below the header.
local function Fit()
    local w = frame:GetWidth() - 2 * MARGIN
    local h = frame:GetHeight() - 2 * MARGIN - HEADER
    local scale = math.min(w / layerW, h / layerH)
    art:SetSize(layerW, layerH)
    art:SetScale(scale)
    art:ClearAllPoints()
    -- SetPoint offsets are in the art's own (scaled) units.
    art:SetPoint("CENTER", frame, "CENTER", 0, -HEADER / 2 / scale)
    -- The quest areas are drawn to the blob frame's size at draw time, so give it that size now
    -- rather than through anchors (on the first open those aren't laid out yet).
    if blob then blob:SetSize(layerW, layerH) end
end

local function DrawArt()
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if not layer then
        HideFrom(tiles, 1)
        HideFrom(overlays, 1)
        return false
    end
    layerW, layerH = layer.layerWidth, layer.layerHeight
    Fit()

    local tw, th = layer.tileWidth or TILE, layer.tileHeight or TILE
    local wide, tall = math.ceil(layerW / tw), math.ceil(layerH / th)
    local files = C_Map.GetMapArtLayerTextures(mapID, 1) or {}
    local n = 0
    for row = 1, tall do
        for col = 1, wide do
            local file = files[(row - 1) * wide + col]
            if file then
                n = n + 1
                local t = Pool(tiles, n, "BACKGROUND")
                t:SetSize(tw, th)
                t:SetPoint("TOPLEFT", (col - 1) * tw, -(row - 1) * th)
                t:SetTexture(file, nil, nil, "TRILINEAR")
            end
        end
    end
    HideFrom(tiles, n + 1)

    -- Explored areas (the same pieces Blizzard's map lays over the base art).
    n = 0
    local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
        and C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}
    for _, info in ipairs(explored) do
        -- Some maps leave out the piece counts; they follow from the size (256-pixel tiles).
        local tall = info.numTexturesTall or math.ceil((info.textureHeight or 0) / TILE)
        local wide = info.numTexturesWide or math.ceil((info.textureWidth or 0) / TILE)
        if not info.isShownByMouseOver and info.fileDataIDs then
            for j = 1, tall do
                local ph, fh = TILE, TILE
                if j == tall then
                    ph = info.textureHeight % TILE
                    if ph == 0 then ph = TILE end
                    fh = 16
                    while fh < ph do fh = fh * 2 end
                end
                for k = 1, wide do
                    local pw, fw = TILE, TILE
                    if k == wide then
                        pw = info.textureWidth % TILE
                        if pw == 0 then pw = TILE end
                        fw = 16
                        while fw < pw do fw = fw * 2 end
                    end
                    local file = info.fileDataIDs[(j - 1) * wide + k]
                    if file then
                        n = n + 1
                        local t = Pool(overlays, n, "BORDER")
                        t:SetSize(pw, ph)
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:SetPoint("TOPLEFT", info.offsetX + TILE * (k - 1), -(info.offsetY + TILE * (j - 1)))
                        t:SetTexture(file, nil, nil, "TRILINEAR")
                    end
                end
            end
        end
    end
    HideFrom(overlays, n + 1)
    return true
end

-- Small markers in map space (scaled back so they stay a fixed size on screen).
-- back: an atlas drawn behind, a bit larger (the in-progress quest circle). Its texture is hidden otherwise.
local function Dot(i, x, y, size, r, g, b, a, atlas, back)
    local t = Pool(dots, i, "OVERLAY", 1, marks)
    local s = size / art:GetScale()
    t:SetSize(s, s)
    t:SetPoint("CENTER", art, "TOPLEFT", x * layerW, -y * layerH)
    if atlas and t.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        t:SetAtlas(atlas)
        t:SetVertexColor(1, 1, 1, a or 1)
    else
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetTexCoord(0, 1, 0, 1) -- pooled: undo an earlier atlas's crop
        t:SetVertexColor(r, g, b, a or 1)
    end
    if back then
        local bt = Pool(backs, i, "OVERLAY", 0, marks)
        bt:SetSize(s * 1.45, s * 1.45)
        bt:SetPoint("CENTER", t, "CENTER")
        bt:SetAtlas(back)
    elseif backs[i] then
        backs[i]:Hide()
    end
    return t
end

local function DrawMarkers()
    local n = 0
    -- Quests on this map
    local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if ok and type(quests) == "table" then
        for _, q in ipairs(quests) do
            if Readable(q.x) and Readable(q.y) then
                -- ? to turn in, ! to pick up, otherwise in progress (the same icons as the quest tracker)
                local okC, done = pcall(C_QuestLog.IsComplete, q.questID)
                local icon = (okC and done == true) and "QuestTurnin"
                    or q.isQuestStart and (q.isDaily and "QuestDaily" or "QuestNormal")
                local inProgress = not icon
                n = n + 1
                Dot(n, q.x, q.y, inProgress and 20 or 22, 1, 0.82, 0, 1, icon or "Quest-In-Progress-Icon-yellow",
                    inProgress and "UI-QuestPoi-QuestNumber" or nil)
            end
        end
    end
    -- WayPad waypoints
    if WayPad_GetPoints then
        local points, active = WayPad_GetPoints()
        for i, p in ipairs(points or {}) do
            local x, y = Translate(p.mapID, p.x, p.y, mapID)
            if x then
                n = n + 1
                Dot(n, x, y, i == active and 26 or 18, 1, 1, 1, 1,
                    i == active and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked")
            end
        end
    end
    -- Blizzard's own map pin (the one you place on the world map, or from a chat link)
    local okW, pin = pcall(C_Map.GetUserWaypointPositionForMap, mapID)
    if okW and pin and Readable(pin.x) then
        local tracked = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint
            and C_SuperTrack.IsSuperTrackingUserWaypoint()
        n = n + 1
        Dot(n, pin.x, pin.y, tracked and 26 or 20, 1, 1, 1, 1,
            tracked and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked")
    end
    -- Where a guard sent you ("Where is the weapon master?"): the game's flag, with its name
    -- (the label sits on its own unscaled layer so it stays readable at any zoom).
    if not ns.poiLabel then
        ns.poiLabel = labelLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ns.poiLabel:SetShadowOffset(1, -1)
    end
    ns.poiLabel:Hide()
    local okG, poiID = pcall(C_GossipInfo.GetPoiForUiMapID, mapID)
    if okG and poiID then
        local okI, info = pcall(C_GossipInfo.GetPoiInfo, mapID, poiID)
        local pos = okI and info and info.position
        if pos and Readable(pos.x) then
            n = n + 1
            local t = Dot(n, pos.x, pos.y, 26, 1, 1, 1, 1, info.atlasName)
            if not info.atlasName and GetPOITextureCoords and info.textureIndex then
                local l, r, top, b = GetPOITextureCoords(info.textureIndex)
                t:SetTexture("Interface\\Minimap\\POIIcons")
                t:SetTexCoord(l, r, top, b)
                t:SetVertexColor(1, 1, 1, 1)
            end
            if info.name then
                ns.poiLabel:ClearAllPoints()
                ns.poiLabel:SetPoint("BOTTOM", t, "TOP", 0, 2)
                ns.poiLabel:SetText(info.name)
                ns.poiLabel:Show()
            end
        end
    end
    -- Flight masters (the ones you haven't found yet, faded). Forever returns the whole
    -- continent's nodes for any map, in continent coordinates (ShouldMapShowTaxiNodes says no,
    -- since its own map doesn't draw them), so place them from the continent onto this map.
    local continent = mapID
    for _ = 1, 6 do
        local ci = MapInfo(continent)
        if not ci or ci.mapType == (Enum.UIMapType and Enum.UIMapType.Continent or 2) then break end
        continent = ci.parentMapID
    end
    local okN, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, continent)
    if okN and type(nodes) == "table" then
        local faction = UnitFactionGroup("player")
        local F = Enum.FlightPathFaction or {}
        local shown = 0
        for _, node in ipairs(nodes) do
            local pos = node.position
            local mine = not ((node.faction == F.Horde and faction ~= "Horde")
                or (node.faction == F.Alliance and faction ~= "Alliance"))
            local x, y
            if mine and pos then x, y = Translate(continent, pos.x, pos.y, mapID) end
            if x then
                n = n + 1
                shown = shown + 1
                Dot(n, x, y, 24, 0.3, 1, 0.3, node.isUndiscovered and 0.45 or 1,
                    node.atlasName or "TaxiNode_Neutral")
            end
        end
        local line = "mapdeck taxi map=" .. tostring(mapID) .. " cont=" .. tostring(continent)
            .. " nodes=" .. #nodes .. " shown=" .. shown
        if line ~= ns.lastTaxiLine and ns.Debug then ns.Debug(line) end -- once per change
        ns.lastTaxiLine = line
    end
    -- Dungeon and raid entrances
    local okD, dungeons = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
    if okD and type(dungeons) == "table" then
        for _, d in ipairs(dungeons) do
            local pos = d.position
            if pos and Readable(pos.x) then
                n = n + 1
                Dot(n, pos.x, pos.y, 24, 0.9, 0.5, 0.2, 1, d.atlasName or "Dungeon")
            end
        end
    end
    -- Where you'll come back to life if you release (the spirit healer), while you're dead
    if UnitIsDeadOrGhost("player") and C_DeathInfo and C_DeathInfo.GetDeathReleasePosition then
        local okR, rel = pcall(C_DeathInfo.GetDeathReleasePosition, mapID)
        if okR and rel then
            local x, y = rel:GetXY()
            if Readable(x) and (x ~= 0 or y ~= 0) then
                n = n + 1
                local t = Dot(n, x, y, 24, 0.5, 0.8, 1, 1)
                if not UseFile(t, "Interface\\Icons\\Spell_Holy_Resurrection") then
                    Dot(n, x, y, 14, 0.5, 0.8, 1, 1) -- no icon: a pale blue square
                end
            end
        end
    end
    -- Your group: the whole raid, or your party
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local x, y = UnitPos(unit, mapID)
            if x then
                n = n + 1
                local _, class = UnitClass(unit)
                local c = raid and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if c then Dot(n, x, y, 10, c.r, c.g, c.b, 1) else Dot(n, x, y, 12, 0.35, 0.65, 1, 1) end
            end
        end
    end
    -- Your corpse
    local cx, cy = CorpsePos(mapID)
    if cx then
        n = n + 1
        Dot(n, cx, cy, 28, 0.8, 0.8, 0.8, 1, "poi-graveyard-neutral")
    end
    HideFrom(dots, n + 1)
    for i, t in pairs(backs) do -- has gaps (only some markers have one)
        if i > n then t:Hide() end
    end
end

local function DrawPlayer()
    local x, y = UnitPos("player", mapID)
    if x then
        local s = 36 / art:GetScale()
        playerArrow:SetSize(s, s)
        playerArrow:ClearAllPoints()
        playerArrow:SetPoint("CENTER", art, "TOPLEFT", x * layerW, -y * layerH)
        local okF, facing = pcall(GetPlayerFacing)
        playerArrow:SetRotation(okF and Readable(facing) and facing or 0)
        playerArrow:Show()
    else
        playerArrow:Hide()
    end
    local hx, hy = UnitPos("player", homeMap)
    coords:SetText(hx and string.format("%.1f, %.1f", hx * 100, hy * 100) or "")
end

-- Quest areas, like Blizzard's map shows for a selected quest: the super-tracked quest, or else
-- every watched quest. The game fills the shapes in itself (QuestPOIFrame).
local function BlobQuests()
    local st = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if Readable(st) and st ~= 0 then return { st } end
    local list = {}
    local count = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
    for i = 1, count do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if id then table.insert(list, id) end
    end
    return list
end

local function DrawBlobs()
    if not blob then return end
    blob:DrawNone()
    blob:SetMapID(mapID)
    for _, id in ipairs(BlobQuests()) do
        pcall(blob.DrawBlob, blob, id, true)
    end
end

-- Zone names when zoomed out to a continent, at the middle of each zone.
local zoneLabels = {}
local function DrawZoneNames(info)
    local n = 0
    local continent = Enum.UIMapType and Enum.UIMapType.Continent or 2
    if info and info.mapType == continent and C_Map.GetMapChildrenInfo then
        local okC, children = pcall(C_Map.GetMapChildrenInfo, mapID, Enum.UIMapType and Enum.UIMapType.Zone or 3)
        local k = art:GetEffectiveScale() / labelLayer:GetEffectiveScale()
        for _, child in ipairs(okC and children or {}) do
            local okR, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, child.mapID, mapID)
            if okR and left and Readable(left) and right > left then
                n = n + 1
                local l = Label(zoneLabels, n, "GameFontNormal")
                l:SetText(child.name)
                l:SetPoint("CENTER", art, "TOPLEFT",
                    (left + right) / 2 * layerW * k, -(top + bottom) / 2 * layerH * k)
            end
        end
    end
    HideFrom(zoneLabels, n + 1)
end

local function Render()
    local info = MapInfo(mapID)
    title:SetText(info and info.name or "")
    if not DrawArt() then
        title:SetText((info and info.name or "") .. "  |cff888888(no map here)|r")
    end
    DrawBlobs()
    DrawMarkers()
    DrawPlayer()
    DrawZoneNames(info)
    local parent = info and info.parentMapID
    local canOut = parent and parent ~= 0 and MapInfo(parent) and (MapInfo(parent).mapType or 0) >= 2
    local parts = {}
    if canOut then table.insert(parts, "Right stick up: zoom out") end
    if mapID ~= homeMap then table.insert(parts, "down: back to your zone") end
    hint:SetText(table.concat(parts, "   "))
end

local function ZoomOut()
    local info = MapInfo(mapID)
    local parent = info and info.parentMapID
    local pinfo = parent and parent ~= 0 and MapInfo(parent)
    if pinfo and (pinfo.mapType or 0) >= 2 then -- stop at the continent (no world/cosmic)
        mapID = parent
        Render()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end
end

local function ZoomIn()
    if mapID ~= homeMap then
        mapID = homeMap
        Render()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
    end
end

------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------

local function Create()
    frame = CreateFrame("Frame", "MapDeckPeek", UIParent, "BackdropTemplate")
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(0, 0, 0, 0.88)
    frame:Hide()

    art = CreateFrame("Frame", nil, frame)
    art:SetClipsChildren(true)

    -- Above the art: the quest areas, then the markers (a child frame draws over its parent's textures).
    local ok, b = pcall(CreateFrame, "QuestPOIFrame", nil, art)
    if ok and b then
        blob = b
        blob:SetPoint("TOPLEFT", art, "TOPLEFT")
        blob:SetSize(1, 1)
        -- redraw once a new size lands, in case it lags behind Fit
        blob:SetScript("OnSizeChanged", function() if frame:IsShown() then DrawBlobs() end end)
        blob:SetFrameLevel(art:GetFrameLevel() + 1)
        blob:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
        blob:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
        blob:SetFillAlpha(128)
        blob:SetBorderAlpha(192)
        blob:SetBorderScalar(1.0)
    end
    marks = CreateFrame("Frame", nil, art)
    marks:SetAllPoints(art)
    marks:SetFrameLevel(art:GetFrameLevel() + 2)

    labelLayer = CreateFrame("Frame", nil, frame)
    labelLayer:SetAllPoints()
    labelLayer:SetFrameLevel(marks:GetFrameLevel() + 5)

    playerArrow = marks:CreateTexture(nil, "OVERLAY", nil, 7)
    playerArrow:SetTexture("Interface\\Minimap\\MinimapArrow")

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -16)
    coords = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    coords:SetPoint("TOPRIGHT", -MARGIN, -20)
    hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOPLEFT", MARGIN, -22)

    -- Take the sticks while shown (camera stays still); the right stick zooms.
    DeckKit.TakeSticks(frame, function(y) stickY = y end)

    local markerClock = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        DrawPlayer()
        markerClock = markerClock + elapsed
        if markerClock > 0.5 then -- party and waypoints move less often
            markerClock = 0
            DrawMarkers()
        end
        cooldown = math.max(0, cooldown - elapsed)
        if cooldown == 0 then
            if stickY > DEADZONE then
                ZoomOut()
                cooldown = STEP
            elseif stickY < -DEADZONE then
                ZoomIn()
                cooldown = STEP
            end
        elseif math.abs(stickY) < 0.2 then
            cooldown = 0 -- let go: the next push zooms at once
        end
    end)
    frame:SetScript("OnSizeChanged", function() if frame:IsShown() then Render() end end)
    for _, e in ipairs({ "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, e)
    end
    frame:SetScript("OnEvent", function() if frame:IsShown() then DrawBlobs() end end)
end

local function Show()
    if not frame then Create() end
    local here = C_Map.GetBestMapForUnit("player")
    if not Readable(here) then return end
    homeMap, mapID = here, here
    stickY, cooldown = 0, 0
    frame:Show()
    Render()
end

local function Hide()
    if frame then frame:Hide() end
    stickY = 0
end

-- keystate: "down" on press, "up" on release (runOnUp). Repeats of "down" just keep it up.
local function Peek(on)
    if not on then Hide()
    elseif not (frame and frame:IsShown()) then Show() end
end

-- The peek binding is the right paddle of DeckKit's paddle chords (hold, both held, double-tap).
function MapDeck_Peek(keystate)
    DeckKit.Paddles.Press("right", keystate ~= "up")
end
DeckKit.Paddles.SetPeek("right", Peek)

BINDING_HEADER_MAPDECK = "MapDeck"
BINDING_NAME_MAPDECK_PEEK = "Peek at the map (hold)"

SLASH_MAPDECK1 = "/mapdeck"
SlashCmdList.MAPDECK = function()
    if frame and frame:IsShown() then Hide() else Show() end
end

-- Built at login, out of combat, so taking the sticks is allowed even if the first peek is mid-fight.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    if not frame then Create() end
    self:UnregisterAllEvents()
end)

ns.AddSettings({
    { type = "section", tab = "Map & travel", label = "Map", order = 2 },
    { type = "info", label = "Hold your peek button for the map; right stick up zooms out." },
    { type = "binding", action = "MAPDECK_PEEK", tab = "Controls", section = "Bindings", sectionOrder = 9 },
})




