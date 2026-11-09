-- MapDeck: hold a button to see the map full-screen.
--
-- This draws the map itself (the zone's art tiles plus the explored-area overlays) instead of
-- opening Blizzard's map window, so it works in combat and fills the screen. On it: you (an
-- arrow that turns with you), your party, quest markers, and WayPad's waypoints.
-- While it's up the frame takes the gamepad sticks, like ChatDeck: the right stick zooms out
-- (up: zone -> continent) and back in (down). The camera stays still; auto-run keeps going.
--
-- /mapdeck   show / hide (for testing at a desk)
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff8fd16fMapDeck|r")

local MARGIN, HEADER = 24, 44
local TILE = 256
local DEADZONE, STEP = 0.6, 0.35 -- zoom: push past 60%, at most one step per 0.35 s

local frame, canvas, art, title, coords, hint
local tiles, overlays, dots = {}, {}, {}
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

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------

local function Pool(list, i, layer, sub)
    local t = list[i]
    if not t then
        t = art:CreateTexture(nil, layer, nil, sub)
        list[i] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function HideFrom(list, n)
    for i = n, #list do list[i]:Hide() end
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
local function Dot(i, x, y, size, r, g, b, a, atlas)
    local t = Pool(dots, i, "OVERLAY", 1)
    local s = size / art:GetScale()
    t:SetSize(s, s)
    t:SetPoint("CENTER", art, "TOPLEFT", x * layerW, -y * layerH)
    if atlas and t.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        t:SetAtlas(atlas)
        t:SetVertexColor(1, 1, 1, a or 1)
    else
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(r, g, b, a or 1)
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
                n = n + 1
                Dot(n, q.x, q.y, 14, 1, 0.82, 0, 1)
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
    -- Party
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local x, y = UnitPos(unit, mapID)
            if x then
                n = n + 1
                Dot(n, x, y, 12, 0.35, 0.65, 1, 1)
            end
        end
    end
    HideFrom(dots, n + 1)
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

local function Render()
    local info = MapInfo(mapID)
    title:SetText(info and info.name or "")
    if not DrawArt() then
        title:SetText((info and info.name or "") .. "  |cff888888(no map here)|r")
    end
    DrawMarkers()
    DrawPlayer()
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

    playerArrow = art:CreateTexture(nil, "OVERLAY", nil, 7)
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
    { type = "info", label = "Hold your peek button for the map; right stick up zooms out." },
    { type = "info", label = "Bind it in Key Bindings > DeckKit." },
})
