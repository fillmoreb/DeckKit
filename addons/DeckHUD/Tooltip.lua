-- DeckHUD: the mouseover tooltip (players, NPCs, objects under Forever's gamepad reticle, where the hidden
-- cursor sits) is drawn by DeckHUD instead, at the top of the screen, centered under the status bar,
-- clear of the compass's pointer and pin (or at the screen's top edge with the status bar off),
-- see-through by the Opacity setting: out of the way, and still there at a glance.
--
-- The game's own tooltip keeps doing all the work, unseen: Blizzard (and any addon adding lines or
-- colors, e.g. class-colored names) builds it as usual, and DeckHUD's card copies its lines, colors,
-- border color and health bar each frame. Its pieces are faded to nothing rather than the tooltip hidden
-- or moved off: hiding it from addon code taints the next tooltip, and the game sets the tooltip's own
-- alpha from C (to 1 on every show, down through its fade-out when you look away), after Lua runs, so the
-- card follows that alpha for the fade.
--
-- Only tooltips Blizzard puts at its default spot for the world (GameTooltip_SetDefaultAnchor with
-- UIParent as the owner) are taken; tooltips owned by a frame (bags, buttons, the bag peek) are left alone.
local _, ns = ...

local GAP, PAD, SPACING, BAR_H = 34, 9, 2, 6 -- under the status bar (clear of the compass pointer, pin and distance); inside the card; between lines; health bar
local DEFAULT_ALPHA = 0.3

local function DB() return ns.db end

local function On()
    local db = DB()
    return not db or db.tooltipPlace ~= "blizzard"
end

local function Opacity()
    local db = DB()
    return db and db.tooltipAlpha or DEFAULT_ALPHA
end

------------------------------------------------------------------------
-- The card
------------------------------------------------------------------------

local card, lefts, rights, bar

local function Create()
    local ok, f = pcall(CreateFrame, "Frame", "DeckHUDLookAt", UIParent, "TooltipBackdropTemplate")
    if not ok then
        f = CreateFrame("Frame", "DeckHUDLookAt", UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.85)
    end
    f:SetFrameStrata("HIGH") -- above the HUD, under DeckKit's windows and peeks (DIALOG and up)
    f:Hide()
    lefts, rights = {}, {}
    -- The lines go on a layer above the backdrop (TooltipBackdropTemplate's NineSlice is a child frame, so
    -- it covers the card's own regions).
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetAllPoints()
    f.content:SetFrameLevel(f:GetFrameLevel() + 5)
    bar = CreateFrame("StatusBar", nil, f.content)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetHeight(BAR_H)
    bar:Hide()
    card = f
end

local function Line(i)
    if not lefts[i] then
        lefts[i] = card.content:CreateFontString(nil, "ARTWORK", "GameTooltipText")
        lefts[i]:SetJustifyH("LEFT")
        rights[i] = card.content:CreateFontString(nil, "ARTWORK", "GameTooltipText")
        rights[i]:SetJustifyH("RIGHT")
    end
    return lefts[i], rights[i]
end

-- One fontstring copied from the tooltip's: text, font, color. The text may be secret (unit data in
-- combat); it goes straight to the setter.
local function Copy(dst, src)
    if not (src and src:IsShown()) then dst:SetText(""); dst:Hide(); return false end
    local font, size, flags = src:GetFont()
    if font then dst:SetFont(font, size, flags or "") end
    dst:SetText(src:GetText())
    local r, g, b = src:GetTextColor() -- not its alpha: that's the faded-out 0
    dst:SetTextColor(r, g, b, 1)
    dst:Show()
    return true
end

local function Width(fs)
    local ok, w = pcall(fs.GetStringWidth, fs)
    return ok and type(w) == "number" and w or 0
end

local function Mirror(tip)
    local n = tip:NumLines()
    local width, y = 0, -PAD
    for i = 1, n do
        local l, r = Line(i)
        local hasL = Copy(l, _G["GameTooltipTextLeft" .. i])
        local hasR = Copy(r, _G["GameTooltipTextRight" .. i])
        local h = math.max(hasL and l:GetStringHeight() or 0, hasR and r:GetStringHeight() or 0)
        if h > 0 then
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y)
            r:ClearAllPoints()
            r:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y)
            width = math.max(width, Width(l) + (hasR and (Width(r) + 16) or 0))
            y = y - h - SPACING
        end
    end
    for i = n + 1, #lefts do lefts[i]:Hide(); rights[i]:Hide() end

    local src = GameTooltipStatusBar
    if src and src:IsShown() then
        bar:SetMinMaxValues(src:GetMinMaxValues())
        bar:SetValue(src:GetValue())
        bar:SetStatusBarColor(src:GetStatusBarColor())
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y - 2)
        bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, y - 2)
        bar:Show()
        y = y - 2 - BAR_H - SPACING
    else
        bar:Hide()
    end

    local edge = tip.NineSlice and tip.NineSlice.TopEdge
    if edge and card.SetBackdropBorderColor then
        card:SetBackdropBorderColor(edge:GetVertexColor())
    end
    card:SetSize(math.max(width, 60) + 2 * PAD, -y + PAD - SPACING)
    card:SetAlpha(tip:GetAlpha() * Opacity())
end

-- Under the bar, and further down while the compass shows a route's lines under its pointer (Compass.lua).
local placedGap
local function Place()
    local gap = GAP + (ns.CompassLinesHeight and ns.CompassLinesHeight() or 0)
    placedGap = gap
    card:ClearAllPoints()
    local status = DeckHUDStatusBar
    if status and status:IsShown() then
        card:SetPoint("TOP", status, "BOTTOM", 0, -gap)
    else
        card:SetPoint("TOP", UIParent, "TOP", 0, -gap)
    end
end

------------------------------------------------------------------------
-- Taking the game's tooltip
------------------------------------------------------------------------

local ours, faded = false, false

-- The game's tooltip, unseen (its pieces at 0) or back (at 1).
local function Fade(tip, a)
    for _, r in ipairs({ tip:GetRegions() }) do r:SetAlpha(a) end
    for _, c in ipairs({ tip:GetChildren() }) do c:SetAlpha(a) end
    faded = a < 1
end

-- Any other use of GameTooltip (SetOwner runs first in each, ours included) gives it back.
hooksecurefunc(GameTooltip, "SetOwner", function(tip)
    ours = false
    if faded then Fade(tip, 1) end
    if card then card:Hide() end
end)

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip, parent)
    if tip ~= GameTooltip or parent ~= UIParent or not On() then return end
    if not card then Create() end
    ours = true
    Fade(tip, 0)
    Place()
end)

-- Each frame while it's ours: keep the game's unseen (new lines come in as it's built) and copy it.
GameTooltip:HookScript("OnUpdate", function(tip)
    if not ours then return end
    Fade(tip, 0)
    Mirror(tip)
    -- The compass's route lines come and go: follow them.
    if GAP + (ns.CompassLinesHeight and ns.CompassLinesHeight() or 0) ~= placedGap then Place() end
    card:Show()
end)
GameTooltip:HookScript("OnShow", function(tip)
    if ours then Fade(tip, 0) end
end)
GameTooltip:HookScript("OnHide", function()
    if card then card:Hide() end
end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Tooltips", order = 6 },
    { type = "choice", label = "Mouseover tooltip",
      values = { { "top", "Top of the screen" }, { "blizzard", "Blizzard's corner" } },
      hint = "Where the tooltip for players, NPCs and objects under the reticle shows. Item and button "
          .. "tooltips keep their own places.",
      get = function() return On() and "top" or "blizzard" end,
      set = function(v) DB().tooltipPlace = v end },
    { type = "range", label = "Opacity", indent = true,
      min = 0.2, max = 1, step = 0.1, format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
      hint = "How solid the tooltip at the top is.",
      get = Opacity,
      set = function(v) DB().tooltipAlpha = v end },
})
