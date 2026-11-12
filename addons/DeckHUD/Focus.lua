-- The focus frame without its portrait: a thin border around the name and bars, no portrait, no
-- level badge. Forever's Edit Mode has no "hide portrait" for it, and has no portrait-less target
-- art, so this uses the player frame's portrait-less art ("UI-HUD-UnitFrame-Player-PortraitOff"),
-- mirrored to face the other way, centred on the bars. Blizzard sets the frame's art again whenever
-- the focus changes (CheckClassification), so it's reapplied after that. Only textures change
-- (alpha, art, position), nothing protected, so it's safe in combat too.
--
-- Where the frame sits is Edit Mode's business: Layout.lua's "Centre the focus frame".
local _, ns = ...

local ART = "UI-HUD-UnitFrame-Player-PortraitOff"

local function Enabled() return ns.db.focusNoPortrait == true end

-- The parts: the art container (border, portrait, combat glow, elite dragon) and the content
-- (name, bars, level).
local function Parts()
    local f = FocusFrame
    local c = f and f.TargetFrameContainer
    local m = f and f.TargetFrameContent and f.TargetFrameContent.TargetFrameContentMain
    if c and c.FrameTexture and m and m.HealthBarsContainer and m.ManaBar then return f, c, m end
end

local function Hide(region, hidden)
    if region then region:SetAlpha(hidden and 0 or 1) end
end

local applying = false
local function Apply()
    local f, c, m = Parts()
    if not f or applying then return end
    local on = Enabled()
    Hide(c.Portrait, on)
    Hide(c.PortraitMask, on)
    Hide(c.Flash, on)                    -- the in-combat glow is portrait-shaped
    Hide(c.BossPortraitFrameTexture, on) -- the elite / rare dragon
    Hide(m.LevelText, on)
    Hide(m.LevelBackgroundCircle, on)
    Hide(m.HighLevelTexture, on)
    if not on then return end -- off: Blizzard's own art comes back with its next update
    applying = true
    local t = c.FrameTexture
    if t:SetAtlas(ART, true) then
        t:SetTexCoord(1, 0, 0, 1) -- mirrored: the target-style frame faces the other way
        -- Centred on the content: across the bars, and from the name down to the mana bar.
        local hx = select(1, m.HealthBarsContainer:GetCenter())
        local mx, my = m.ManaBar:GetCenter()
        local _, ny = (m.Name or m.HealthBarsContainer):GetCenter()
        if hx and mx and ny and f:GetLeft() then
            t:ClearAllPoints()
            t:SetPoint("CENTER", f, "BOTTOMLEFT", (hx + mx) / 2 - f:GetLeft(), (ny + my) / 2 - f:GetBottom())
        end
    end
    applying = false
end
ns.FocusFrameApply = Apply

ns.On("PLAYER_LOGIN", function()
    local f = Parts()
    if not f then return end
    if f.CheckClassification then hooksecurefunc(f, "CheckClassification", Apply) end
    Apply()
end)
ns.On("PLAYER_FOCUS_CHANGED", function() C_Timer.After(0, Apply) end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Unit frames", order = 4 },
    { type = "toggle", label = "Focus frame without portrait",
      hint = "Just a thin border around the focus's name and bars: no portrait, no level. Handy when the "
          .. "focus is the player your heals go to.",
      get = Enabled,
      set = function(on)
          ns.db.focusNoPortrait = on
          if on then Apply() else Apply(); ns.Print("Reload (F6) to get the focus frame's portrait back.") end
      end },
})
