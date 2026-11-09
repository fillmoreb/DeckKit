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
        for i, p in ipairs(ns.points) do
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
    for i, p in ipairs(ns.points) do
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
    for i = #ns.points + 1, #minipins do minipins[i]:Hide() end
end

function Pins.Refresh()
    if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
    Pins.UpdateMinimap()
end

ns.On("PLAYER_LOGIN", InstallMap)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" then InstallMap() end
end)
