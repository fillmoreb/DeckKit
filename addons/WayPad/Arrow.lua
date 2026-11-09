-- The floating arrow: just the arrow and an outlined distance line. No panel, no backdrop.
-- /waypad move unlocks it for dragging (touch or mouse); /waypad reset puts it back.
local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local SIZE = 56
local frame, tex, dist, label

local function TrySetAtlas(texture, name)
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
        texture:SetAtlas(name)
        return true
    end
end

local function Outlined(fs, scale)
    local font, size = fs:GetFont()
    if font then fs:SetFont(font, (size or 14) * (scale or 1), "OUTLINE") end
    fs:SetShadowOffset(0, 0)
end

local function Place()
    frame:ClearAllPoints()
    local pos = ns.db and ns.db.arrowPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -40) -- above RestedXP's arrow (CENTER +200)
    end
end

local function Create()
    frame = CreateFrame("Frame", "WayPadArrow", UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p1, _, p2, x, y = self:GetPoint()
        ns.db.arrowPos = { p1, p2, x, y }
    end)

    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    if not TrySetAtlas(tex, "Navigation-Tracked-Arrow") then
        tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    end

    -- Shown only while unlocked, so you can see what you're dragging.
    frame.outline = frame:CreateTexture(nil, "BACKGROUND")
    frame.outline:SetAllPoints()
    frame.outline:SetColorTexture(1, 1, 1, 0.15)
    frame.outline:Hide()

    dist = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dist:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    Outlined(dist)
    label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOP", dist, "BOTTOM", 0, -1)
    Outlined(label, 0.9)

    Place()
    frame:Hide()
end

function Arrow.SetUnlocked(on)
    frame:EnableMouse(on)
    frame.outline:SetShown(on)
    Arrow.unlocked = on
    if on then frame:Show() end
end

function Arrow.Reset()
    ns.db.arrowPos = nil
    Place()
end

-- g: guidance for the active waypoint (Core.lua), or nil.
function Arrow.Update(g)
    if not frame then return end
    if ns.arrival and not g then
        tex:Hide()
        dist:SetText("|cff40ff40Arrived|r")
        label:SetText(ns.arrival.label)
        frame:Show()
        return
    end
    if not g then
        if Arrow.unlocked then
            tex:Show()
            tex:SetRotation(0)
            dist:SetText("drag me")
            label:SetText("")
        else
            frame:Hide()
        end
        return
    end
    local p = g.point
    label:SetText(p.label or "")
    if g.state == "ok" then
        if g.angle then
            tex:SetRotation(g.angle)
            tex:Show()
        else
            tex:Hide()
        end
        dist:SetText(string.format("%d yd", g.yards + 0.5))
        -- Greener the closer you're facing it.
        local off = g.angle and math.abs(((g.angle + math.pi) % (2 * math.pi)) - math.pi) or math.pi
        local t = math.max(0, 1 - off / (math.pi / 4))
        tex:SetVertexColor(1 - 0.6 * t, 1, 1 - 0.6 * t)
    elseif g.state == "far" then
        tex:Hide()
        dist:SetText(ns.MapName(p.mapID))
    else
        tex:Hide()
        dist:SetText("?")
    end
    if ns.arrival then
        dist:SetText("|cff40ff40Arrived|r  " .. dist:GetText())
    end
    frame:Show()
end

ns.On("PLAYER_LOGIN", Create)
