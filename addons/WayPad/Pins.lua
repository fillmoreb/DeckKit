-- Pins for every waypoint: on the world map (a map data provider) and on the minimap.
-- The active waypoint is gold; the others are gray.
local _, ns = ...

local Pins = {}
ns.Pins = Pins

local PIN = "WayPadMapPinTemplate"

local function SetIcon(texture, active, size)
    local atlas = active and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked"
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        texture:SetVertexColor(1, 1, 1)
    else
        texture:SetTexture("Interface\\Common\\Indicator-Yellow")
        if active then texture:SetVertexColor(1, 1, 1) else texture:SetVertexColor(0.6, 0.6, 0.6) end
    end
end

------------------------------------------------------------------------
-- World map
------------------------------------------------------------------------

WayPad_MapPinMixin = CreateFromMixins(MapCanvasPinMixin or {})
local MapPin = WayPad_MapPinMixin

function MapPin.CheckMouseButtonPassthrough() end -- the pin takes no clicks

function MapPin:OnLoad()
    if self.SetScalingLimits then self:SetScalingLimits(1, 1, 1.2) end
end

function MapPin:OnAcquired(index)
    self.index = index
    SetIcon(self.Icon, index == ns.active)
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") end
end

function MapPin:OnMouseEnter()
    local p = ns.points[self.index]
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("WayPad" .. (self.index == ns.active and " (active)" or ""))
    GameTooltip:AddLine(ns.Describe(p), 1, 1, 1, true)
    GameTooltip:Show()
end

function MapPin:OnMouseLeave()
    GameTooltip:Hide()
end

local provider

local function CreateProvider()
    local dp = CreateFromMixins(MapCanvasDataProviderMixin)
    function dp:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(PIN)
    end
    function dp:RefreshAllData()
        self:RemoveAllData()
        local map = self:GetMap()
        local mapID = map:GetMapID()
        if not mapID then return end
        for i, p in ipairs(ns.DrawnPoints()) do
            local x, y = ns.TranslateToMap(p.mapID, p.x, p.y, mapID)
            if x then map:AcquirePin(PIN, i):SetPosition(x, y) end
        end
    end
    function dp:OnMapChanged()
        self:RefreshAllData()
    end
    return dp
end

local function InstallMap()
    if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    provider = CreateProvider()
    WorldMapFrame:AddDataProvider(provider)
end

------------------------------------------------------------------------
-- Minimap
------------------------------------------------------------------------

------------------------------------------------------------------------
-- The walk on the minimap: a lilac dotted trail along the path on foot to where the guidance points
-- (DeckKit.Route.Walk, with ForeverNav installed), from you onward, inside the minimap only. MapDeck draws the same
-- path on the peek map.
------------------------------------------------------------------------

local crumbs = {}
local crumbFrame
local CRUMB_PX, CRUMB_GAP_PX = 5, 9 -- dot size and the gap between dots, on screen
local CRUMB_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a white disc
local LILAC = DeckKit.COLORS.LILAC

local function Crumb(i)
    local t = crumbs[i]
    if not t then
        if not crumbFrame then
            crumbFrame = CreateFrame("Frame", nil, Minimap)
            crumbFrame:SetAllPoints(Minimap)
            crumbFrame:SetFrameLevel(Minimap:GetFrameLevel() + 9) -- under the waypoint pins (+10)
        end
        t = crumbFrame:CreateTexture(nil, "OVERLAY")
        t:SetTexture(CRUMB_TEXTURE)
        t:SetVertexColor(LILAC[1], LILAC[2], LILAC[3], 0.9)
        t:SetSize(CRUMB_PX, CRUMB_PX)
        crumbs[i] = t
    end
    return t
end

local function UpdateCrumbs(view, radius, rotates, square)
    local n = 0
    local walk = DeckKit.Route and DeckKit.Route.Walk and DeckKit.Route.Walk()
    local me = ns.player
    if walk and view and me.continent == walk.continent and me.north and not (rotates and not me.facing) then
        local turn = rotates and me.facing or 0
        local cosT, sinT = math.cos(turn), math.sin(turn)
        local perYard = radius / view
        local step = (CRUMB_PX + CRUMB_GAP_PX) / perYard -- yards between dots
        local edge = radius - CRUMB_PX
        -- From you along the rest of the path; a dot every `step` yards, while within reach of the minimap.
        local ax, ay = me.north, me.west
        local at, travelled = step, 0 -- the next dot's distance along the current stretch: the first a gap ahead of you
        for i = walk.next or 2, #walk.points do
            local b = walk.points[i]
            local dN, dW = b.x - ax, b.y - ay
            local len = math.sqrt(dN * dN + dW * dW)
            while at <= len do
                local f = len > 0 and at / len or 0
                local pn, pw = ax + dN * f - me.north, ay + dW * f - me.west
                -- On screen: north up and west left, turned with you when the minimap rotates.
                local sx, sy = -pw * perYard, pn * perYard
                sx, sy = sx * cosT + sy * sinT, -sx * sinT + sy * cosT
                local inside = square and (math.abs(sx) <= edge and math.abs(sy) <= edge)
                    or (not square and sx * sx + sy * sy <= edge * edge)
                if inside then
                    n = n + 1
                    local t = Crumb(n)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
                    t:Show()
                end
                at = at + step
            end
            at = at - len -- carried into the next stretch
            travelled = travelled + len
            if travelled > view * 3 then break end -- far past the minimap's reach
            ax, ay = b.x, b.y
        end
    end
    for i = n + 1, #crumbs do crumbs[i]:Hide() end
end


local minipins = {}

local function MiniPin(i)
    local pin = minipins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, Minimap)
        pin:SetSize(14, 14)
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 10)
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints()
        minipins[i] = pin
    end
    return pin
end

local function ViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and ns.Readable(r) and r > 0 then return r end
    end
end

function Pins.UpdateMinimap()
    if not Minimap then return end
    local view = ViewRadius()
    local radius = Minimap:GetWidth() / 2
    local rotates = GetCVar("rotateMinimap") == "1"
    local facing = ns.player.facing
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    for i, p in ipairs(ns.DrawnPoints()) do
        local pin = MiniPin(i)
        local active = i == ns.active
        local g = ns.Guide(p)
        local show = false
        if g.state == "ok" and not (rotates and not facing) then
            local angle = g.bearing - (rotates and facing or 0)
            -- angle is counter-clockwise from up: west (left) is +90 degrees.
            local dx, dy = -math.sin(angle), math.cos(angle)
            local scale
            if view and g.yards < view * 0.95 then
                scale = radius * g.yards / view -- on the spot itself
            elseif active then
                scale = square and radius / math.max(math.abs(dx), math.abs(dy)) or radius -- on the edge
            end
            if scale then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", dx * scale, dy * scale)
                show = true
            end
        end
        if show then
            if pin.active ~= active then
                pin.active = active
                SetIcon(pin.icon, active)
            end
            pin:Show()
        else
            pin:Hide()
        end
    end
    for i = #ns.DrawnPoints() + 1, #minipins do minipins[i]:Hide() end
    UpdateCrumbs(view, radius, rotates, square)
end

function Pins.Refresh()
    if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
    Pins.UpdateMinimap()
end

ns.On("PLAYER_LOGIN", InstallMap)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" then InstallMap() end
end)
