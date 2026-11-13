-- The focus frame, slimmed down for healing. Three looks (Screen > Unit frames > Focus frame):
--   Blizzard's     as the game draws it
--   No portrait    a thin border around the name and bars: no portrait, no level badge
--   Name and health  just a big first name in the player's class color over a tall health bar,
--                  a little wider than Blizzard's, in a thin border of our own; no cast bar
-- Forever's Edit Mode has no "hide portrait" for the focus frame and no portrait-less target art,
-- so "No portrait" uses the player frame's portrait-less art ("UI-HUD-UnitFrame-Player-PortraitOff"),
-- mirrored and centered on the bars. Blizzard redraws the frame's art when the focus changes
-- (CheckClassification) and its name on every update (UnitFrame_Update), so both are hooked and
-- the look reapplied. Only regions and unprotected child frames change, so it works in combat.
--
-- Where the frame sits is Edit Mode's business: Layout.lua's "Center the focus frame".
local _, ns = ...

local ART = "UI-HUD-UnitFrame-Player-PortraitOff"
local COMPACT_W, COMPACT_HEALTH_H, NAME_H = 160, 24, 18 -- frame units (the focus frame is drawn at 0.75)
local NAME_SIZE = 16
local BORDER = { 0.75, 0.7, 0.6, 0.9 }

local function Style()
    local s = ns.db.focusStyle
    if s == nil and ns.db.focusNoPortrait then s = "noportrait" end -- the earlier on/off setting
    return s or "blizzard"
end

-- The parts: the art container (border, portrait, combat glow, elite dragon) and the content
-- (name and its band, bars, level).
local function Parts()
    local f = FocusFrame
    local c = f and f.TargetFrameContainer
    local m = f and f.TargetFrameContent and f.TargetFrameContent.TargetFrameContentMain
    if c and c.FrameTexture and m and m.HealthBarsContainer and m.ManaBar and m.Name then return f, c, m end
end

local function Alpha(region, hidden) if region then region:SetAlpha(hidden and 0 or 1) end end

-- Our border, for "Name and health".
local border
local function Border(f, m)
    if not border then
        border = CreateFrame("Frame", nil, f)
        border:SetFrameLevel(m.HealthBarsContainer:GetFrameLevel() + 5)
        local function Edge(p1, p2, horizontal)
            local t = border:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(unpack(BORDER))
            t:SetPoint(p1)
            t:SetPoint(p2)
            if horizontal then t:SetHeight(1.5) else t:SetWidth(1.5) end
        end
        Edge("TOPLEFT", "TOPRIGHT", true)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
        Edge("TOPLEFT", "BOTTOMLEFT", false)
        Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    end
    return border
end

-- The name: a player's first name in their class color; an NPC's whole name ("Lazy Peon", not
-- "Lazy") in the usual reaction color (red hostile, yellow neutral, green friendly). Shrunk to fit
-- if it's long. Re-run after every Blizzard update.
------------------------------------------------------------------------
-- Buffs and debuffs. Never read auras from addon code (C_UnitAuras): that hands back the aura tables
-- Blizzard's frames share, marked as DeckHUD's; Blizzard's buff frame then spread the taint to the
-- gamepad bar ("DeckHUD called SetPreferredGamepadInteractTarget" after looting; found with deckctl
-- taint, 2026-11-12). And never move Blizzard's aura row: moving it makes Blizzard lay it out inside
-- our call, which taints its buttons the same way. In the Name and health look, FocusAuras.lua shows
-- the game's own filtered aura container instead, and Blizzard's row is hidden by alpha.
------------------------------------------------------------------------

local defaults -- Blizzard's own name font (Apply keeps it)
local naming = false
local function Name()
    local f, _, m = Parts()
    if not f or naming or Style() ~= "compact" or not UnitExists("focus") then return end
    naming = true
    local full = GetUnitName("focus", false) or ""
    local r, g, b = 1, 0.82, 0
    if UnitIsPlayer("focus") then
        full = full:match("^(%S+)") or full
        local _, class = UnitClass("focus")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then r, g, b = c.r, c.g, c.b end
    else
        local reaction = UnitReaction("focus", "player")
        local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if c then r, g, b = c.r, c.g, c.b end
    end
    m.Name:SetText(full)
    m.Name:SetTextColor(r, g, b)
    -- Shrink a long name until it fits the strip, down to a floor.
    if not defaults then defaults = { m.Name:GetFont() } end
    local k = 0.75 / (f:GetScale() > 0 and f:GetScale() or 0.75) -- same on screen at either frame size
    local size = math.floor(NAME_SIZE * k + 0.5)
    m.Name:SetFont(defaults[1], size, "OUTLINE")
    local room = m.Name:GetWidth()
    while size > 8 and room and room > 0 and m.Name:GetUnboundedStringWidth() > room do
        size = size - 1
        m.Name:SetFont(defaults[1], size, "OUTLINE")
    end
    naming = false
end

local strip -- the dark strip under the name

-- Status icons, for "Name and health". The raid marker moves to the left of the name strip; quest,
-- boss, leader, PvP and similar badges are hidden (clutter on a healer's focus frame). Buffs and
-- debuffs: our own row (below).
local CLUTTER = { "QuestIcon", "BossIcon", "LeaderIcon", "PvpIcon", "PvpBackgroundIcon", "GuideIcon", "PetBattleIcon" }

local function Context(f)
    return f.TargetFrameContent and f.TargetFrameContent.TargetFrameContentContextual
end

local function Icons(compact)
    local f, _, m = Parts()
    local ctx = f and Context(f)
    if not ctx then return end
    for _, key in ipairs(CLUTTER) do Alpha(ctx[key], compact) end
    local mark = ctx.RaidTargetIcon
    if compact and mark and strip then
        mark:ClearAllPoints()
        mark:SetSize(NAME_H + 4, NAME_H + 4)
        mark:SetPoint("RIGHT", strip, "LEFT", -5, -(COMPACT_HEALTH_H / 2))
    end
    -- Blizzard's aura row: hidden by alpha only, never moved. Moving it from addon code makes Blizzard
    -- lay it out right then, inside our call, and its aura buttons come out tainted: that spread to
    -- secret-value checks in BuffFrame.lua and blocked the gamepad bar's SetPreferredGamepadInteractTarget
    -- (found with deckctl taint, 2026-11-12). Our own row replaces it.
end

local pending = false -- sizes to set once combat ends
local applying = false
local function Apply()
    local f, c, m = Parts()
    if not f or applying then return end
    applying = true
    local style = Style()
    local slim = style ~= "blizzard"
    local compact = style == "compact"
    Alpha(c.Portrait, slim)
    Alpha(c.PortraitMask, slim)
    Alpha(c.Flash, slim)                    -- the in-combat glow is portrait-shaped
    Alpha(c.BossPortraitFrameTexture, slim) -- the elite / rare dragon
    Alpha(m.LevelText, slim)
    Alpha(m.LevelBackgroundCircle, slim)
    Alpha(m.HighLevelTexture, slim)
    Alpha(m.ManaBar, compact)
    Alpha(f.spellbar, compact) -- the cast bar: not what a healer's focus frame is for (and see the hook below)
    Alpha(c.FrameTexture, compact)
    if border then border:SetShown(compact) end
    if strip then strip:SetShown(compact) end
    if not defaults then defaults = { m.Name:GetFont() } end

    if style == "noportrait" then
        local t = c.FrameTexture
        if t:SetAtlas(ART, true) then
            t:SetTexCoord(1, 0, 0, 1) -- mirrored: the target-style frame faces the other way
            -- Centered on the content: across the bars, and from the name down to the mana bar.
            local hx = m.HealthBarsContainer:GetCenter()
            local mx, my = m.ManaBar:GetCenter()
            local _, ny = m.Name:GetCenter()
            if hx and mx and ny and f:GetLeft() then
                t:ClearAllPoints()
                t:SetPoint("CENTER", f, "BOTTOMLEFT", (hx + mx) / 2 - f:GetLeft(), (ny + my) / 2 - f:GetBottom())
            end
        end
    elseif compact then
        -- The health bar stays where Blizzard put it, only bigger (its holder is a protected frame:
        -- it can be resized, out of combat, but not anchored to the name band, a plain texture). The
        -- name band then sits on top of it, the same width.
        local band, hb = m.ReputationColor, m.HealthBarsContainer
        -- Sizes are for the small frame (0.75); with "Use Larger Frame" (1.0) they shrink to match on screen.
        local k = 0.75 / (f:GetScale() > 0 and f:GetScale() or 0.75)
        -- On every focus change Blizzard resets the bar (CheckClassification): its holder's size and
        -- position, its fill texture's atlas and its mask. The holder and the bar are protected frames,
        -- so their size and anchors can only be set out of combat (after a fight, if the focus changed
        -- during one). The fill and the mask are plain texture regions, never protected: those are
        -- put back right away, in combat too, so the bar keeps its look.
        if InCombatLockdown() then
            pending = true
        else
            hb:SetSize(COMPACT_W * k, COMPACT_HEALTH_H * k)
            if hb.HealthBar then hb.HealthBar:ClearAllPoints(); hb.HealthBar:SetAllPoints(hb) end
            if hb.HealthBarMask then hb.HealthBarMask:ClearAllPoints(); hb.HealthBarMask:SetAllPoints(hb) end
        end
        -- Blizzard's bar art has transparent padding, so stretched it stays thin: a flat green fill.
        local fill = hb.HealthBar and (hb.HealthBar.HealthBarTexture or hb.HealthBar:GetStatusBarTexture())
        if fill then
            fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
            fill:SetVertexColor(0.1, 0.8, 0.1) -- the old art was green by itself
        end
        -- The bar is clipped by a mask with the same padded shape: a plain rectangle instead.
        if hb.HealthBarMask then
            hb.HealthBarMask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        -- Under the name: our own strip, the minimap title's black (Minimap.lua), in place of Blizzard's
        -- band, which it recolors by reputation on every update.
        if band then band:SetAlpha(0) end
        if not strip then
            strip = m:CreateTexture(nil, "BACKGROUND")
            strip:SetColorTexture(0, 0, 0, 0.55)
        end
        strip:ClearAllPoints()
        strip:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", 0, 1)
        strip:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", 0, 1)
        strip:SetHeight(NAME_H * k)
        strip:Show()
        band = strip
        m.Name:ClearAllPoints()
        if band then
            m.Name:SetPoint("LEFT", band, "LEFT", 4, 0)
            m.Name:SetPoint("RIGHT", band, "RIGHT", -4, 0)
        end
        m.Name:SetFont(defaults[1], NAME_SIZE * k, "OUTLINE")
        local b = Border(f, m)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", band or hb, "TOPLEFT", -2, 2)
        b:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 2, -2)
        b:Show()
    end
    -- Auras: our own row (FocusAuras.lua) in this look; Blizzard's is hidden by alpha only (never moved:
    -- see "Buffs and debuffs" above).
    local ours = ns.FocusAurasPlace and ns.FocusAurasPlace(compact, m.HealthBarsContainer)
    local blizzard = f.GetAuraContainer and f:GetAuraContainer()
    Alpha(blizzard, ours)
    Icons(compact)
    applying = false
    Name()
end
ns.FocusFrameApply = Apply

-- What the focus frame looks like on screen right now: our border (Name and health), else its art.
function ns.FocusVisual()
    local f, c = Parts()
    if not f then return nil end
    if Style() == "compact" and border and border:IsShown() then return border end
    return c.FrameTexture
end

ns.On("PLAYER_LOGIN", function()
    local f = Parts()
    if not f then return end
    if f.CheckClassification then hooksecurefunc(f, "CheckClassification", Apply) end
    -- The cast bar fades itself in on every cast (it sets its own alpha as it animates), so hiding it
    -- once isn't enough: after each of its updates, set it back to invisible. A script hook runs after
    -- Blizzard's handler, without changing it.
    if f.spellbar then
        f.spellbar:HookScript("OnUpdate", function(self)
            if Style() == "compact" and self:GetAlpha() > 0 then self:SetAlpha(0) end
        end)
        f.spellbar:HookScript("OnShow", function(self)
            if Style() == "compact" then self:SetAlpha(0) end
        end)
    end
    -- Below 20% health Blizzard pulses a player's portrait (its alpha) as a warning: keep it hidden.
    if f.HealthUpdate then
        hooksecurefunc(f, "HealthUpdate", function(self)
            if Style() ~= "blizzard" and self.TargetFrameContainer.Portrait then
                self.TargetFrameContainer.Portrait:SetAlpha(0)
            end
        end)
    end
    if UnitFrame_Update then
        hooksecurefunc("UnitFrame_Update", function(frame) if frame == FocusFrame then Name() end end)
    end
    Apply()
end)
ns.On("PLAYER_FOCUS_CHANGED", function() C_Timer.After(0, Apply) end)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then pending = false; Apply() end end)
ns.On("UNIT_NAME_UPDATE", function(unit) if unit == "focus" then Name() end end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Unit frames", order = 4 },
    { type = "action", label = "Focus auras", verb = "Choose",
      hint = "With the Name and health look: which buffs show under the focus frame, your own debuffs "
          .. "(a priest's Weakened Soul), and debuffs you can dispel.",
      run = function() ns.OpenFocusAuras() end },
    { type = "choice", label = "Focus frame",
      values = { { "blizzard", "Blizzard's" }, { "noportrait", "No portrait" }, { "compact", "Name and health" } },
      hint = "No portrait: a thin border around the focus's name and bars. Name and health: just a big first "
          .. "name in their class color over a tall health bar. Handy when the focus is who your heals go to. "
          .. "Going back to Blizzard's look takes a reload.",
      get = Style,
      set = function(v)
          ns.db.focusStyle = v
          ns.db.focusNoPortrait = nil
          Apply()
          if v == "blizzard" then ns.Print("Reload (F6) to get Blizzard's focus frame back.") end
      end },
})
