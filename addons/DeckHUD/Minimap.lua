-- DeckHUD: interface tweaks for playing on the Deck. For now, the minimap: square, a thin border
-- (or none), in the top-right corner, without the buttons and frame art around its edge.
--
-- The minimap is moved out of Blizzard's MinimapCluster (which holds the zone text, tracking,
-- calendar, mail and the other edge buttons) onto UIParent, and the cluster is hidden. Addon
-- minimap buttons (LibDBIcon ones, or any named "...MinimapButton") are hidden too.
-- Optionally it leaves room above the map for the Steam performance overlay's battery readout.
--
-- Settings live in the DeckKit menu (double-tap Menu, or /deckkit).
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffe0c060DeckHUD|r")

local DEFAULTS = { square = true, hideButtons = true, border = true, overlayRoom = true, matchTracker = true, size = 170 }
local OVERLAY_PX = 30 -- screen pixels kept clear for the Steam battery overlay (it's about 26 tall)
local MARGIN_PX = 4   -- gap to the screen edges

ns.db = {}
local db = ns.db

-- Blizzard's minimap decorations: modern and classic names, whichever exist. MinimapCluster holds
-- most of them; the rest sit on the minimap itself.
local DECOR = {
    "MinimapCluster", "MinimapBackdrop", "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture",
    "MinimapZoomIn", "MinimapZoomOut", "MiniMapTracking", "MiniMapWorldMapButton", "MiniMapMailFrame",
    "MinimapZoneTextButton", "GameTimeFrame", "TimeManagerClockButton", "ExpansionLandingPageMinimapButton",
    "AddonCompartmentFrame", "MiniMapInstanceDifficulty", "GuildInstanceDifficulty", "MiniMapChallengeMode",
}
local DECOR_KEYS = { "ZoomIn", "ZoomOut", "ZoomHitArea" } -- Minimap.<key>

function GetMinimapShape() -- the convention minimap addons (and WayPad's pins) read
    return db.square ~= false and "SQUARE" or "ROUND"
end

------------------------------------------------------------------------
-- Hiding things
------------------------------------------------------------------------

local hooked = {}

local function KeepHidden(f)
    if type(f) ~= "table" or type(f.Hide) ~= "function" then return end
    if not hooked[f] then
        hooked[f] = true
        local function again(self) if db.hideButtons ~= false then self:Hide() end end
        hooksecurefunc(f, "Show", again)
        if f.SetShown then hooksecurefunc(f, "SetShown", function(self, on) if on then again(self) end end) end
    end
    f:Hide()
end

local function IsEdgeButton(f)
    local name = f.GetName and f:GetName()
    return name and (name:find("^LibDBIcon10_") or name:find("MinimapButton") or name:find("MiniMapButton")) and true
end

local function HideButtons()
    if db.hideButtons == false then return end
    for _, name in ipairs(DECOR) do KeepHidden(_G[name]) end
    for _, key in ipairs(DECOR_KEYS) do KeepHidden(Minimap[key]) end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if IsEdgeButton(child) then KeepHidden(child) end
    end
    local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBI and LDBI.GetButtonList and LDBI.GetMinimapButton then
        for _, name in ipairs(LDBI:GetButtonList()) do KeepHidden(LDBI:GetMinimapButton(name)) end
    end
end

------------------------------------------------------------------------
-- Shape, border, place
------------------------------------------------------------------------

local border, holder
local placing = false
local placed = {} -- last width / height / right / top, to skip needless re-placing

local function PixelsToUnits(px)
    local _, physical = GetPhysicalScreenSize()
    return px * UIParent:GetHeight() / (physical or 800)
end

-- The quest tracker the map lines up with, if it's on screen.
local function Tracker()
    local t = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame or _G.WatchFrame
    if t and t:IsShown() and t:GetLeft() and t:GetTop() then return t end
end

-- The map sits centred in a holder the size of the part you see. The minimap itself stays
-- square (it can't stretch, and it ignores frame clipping), so a shorter map is a square one with
-- a mask cutting the same amount off its top and bottom: masks/crop_NN.tga, NN% of the height
-- (deck-setup/make-minimap-masks.py makes them).
local MAX_CROP = 45
local cropPct = 0

local function Holder()
    if not holder then
        holder = CreateFrame("Frame", "DeckHUDMinimapHolder", UIParent)
        holder:SetFrameStrata("LOW")
    end
    return holder
end

local function Mask()
    if db.square == false then return "Interface\\Masks\\CircleMaskScalable" end
    if cropPct <= 0 then return "Interface\\Buttons\\WHITE8X8" end
    return string.format("Interface\\AddOns\\DeckHUD\\masks\\crop_%02d", cropPct)
end

local function Shape()
    Minimap:SetMaskTexture(Mask())
    if not border then
        border = CreateFrame("Frame", nil, Holder(), "BackdropTemplate")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(0, 0, 0, 0.9)
        border:SetFrameLevel(Holder():GetFrameLevel() + 20)
    end
    border:SetShown(db.border ~= false and db.square ~= false)
end

-- Width, height and offsets from the top-right corner, in UIParent units.
local function Layout()
    local margin = PixelsToUnits(MARGIN_PX)
    local top = PixelsToUnits(MARGIN_PX + (db.overlayRoom ~= false and OVERLAY_PX or 0))
    local size = db.size or DEFAULTS.size
    local t = db.matchTracker ~= false and db.square ~= false and Tracker()
    if not t then return size, size, margin, top end
    local k = t:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w = (t:GetRight() - t:GetLeft()) * k
    local right = UIParent:GetRight() - t:GetRight() * k
    local h = (UIParent:GetTop() - top) - (t:GetTop() * k + margin) -- down to just above the tracker
    return w, math.max(60, math.min(w, h)), right, top
end

local function Place(force)
    if InCombatLockdown() and Minimap:IsProtected() then return end
    local w, h, right, top = Layout()
    if not force and placed.w == w and placed.h == h and placed.right == right and placed.top == top
        and Minimap:GetParent() == holder then return end
    placed.w, placed.h, placed.right, placed.top = w, h, right, top
    -- Round the cut up to a whole percent, so the map never reaches past h.
    cropPct = math.min(MAX_CROP, math.max(0, math.ceil((1 - h / w) * 100 - 0.001)))
    if db.square == false then cropPct = 0 end
    local box = Holder()
    box:SetSize(w, w * (1 - cropPct / 100))
    box:ClearAllPoints()
    box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -right, -top)
    placing = true
    if Minimap:GetParent() ~= box then Minimap:SetParent(box) end
    Minimap:SetScale(1)
    Minimap:SetSize(w, w)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", box, "CENTER")
    Minimap:SetMaskTexture(Mask())
    placing = false
    -- The map's image only redraws for the new size on a zoom change.
    local z = Minimap:GetZoom()
    Minimap:SetZoom(z > 0 and z - 1 or z + 1)
    Minimap:SetZoom(z)
end

local function Apply()
    if not Minimap then return end
    Place(true)
    Shape()
    HideButtons()
end
ns.Apply = Apply

------------------------------------------------------------------------
-- Inventory (for development): what's on and around the minimap at load, saved in DeckHUDDB.dump.
------------------------------------------------------------------------

local function Inventory(names)
    local out = {}
    local function add(parentName, f)
        local ok, name = pcall(f.GetName, f)
        local point = f.GetPoint and { f:GetPoint(1) } or {}
        local rel = point[2]
        table.insert(out, string.format("%s > %s [%s] shown=%s %dx%d at %s %s %s",
            parentName, tostring(ok and name or "?"), f.GetObjectType and f:GetObjectType() or "?",
            tostring(f.IsShown and f:IsShown()), math.floor(f.GetWidth and f:GetWidth() or 0), math.floor(f.GetHeight and f:GetHeight() or 0),
            tostring(point[1]), rel and rel.GetName and tostring(rel:GetName()) or "?", tostring(point[3])))
    end
    for _, parentName in ipairs(names) do
        local p = _G[parentName]
        if p then
            add("UIParent", p)
            if p.GetChildren then for _, c in ipairs({ p:GetChildren() }) do add(parentName, c) end end
            if p.GetRegions then for _, r in ipairs({ p:GetRegions() }) do add(parentName .. "(region)", r) end end
        end
    end
    return out
end

------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    DeckHUDDB = DeckHUDDB or {}
    for k, v in pairs(DEFAULTS) do
        if DeckHUDDB[k] == nil then DeckHUDDB[k] = v end
    end
    db = DeckHUDDB
    ns.db = db
    local ok, dump = pcall(Inventory, { "MinimapCluster", "Minimap", "MinimapBackdrop" })
    db.dump = ok and dump or { "inventory failed: " .. tostring(dump) }
end)

ns.On("PLAYER_LOGIN", function()
    Apply()
    if db.zoom then Minimap:SetZoom(math.min(db.zoom, Minimap:GetZoomLevels() - 1)) end
    -- Addons register their minimap buttons at different times.
    C_Timer.After(2, HideButtons)
    C_Timer.After(10, HideButtons)
    local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBI and LDBI.RegisterCallback then
        LDBI.RegisterCallback(ns, "LibDBIcon_IconCreated", function(_, button) if db.hideButtons ~= false then KeepHidden(button) end end)
    end
    -- Edit Mode (or anything else) moving the map back: put it where it belongs again.
    hooksecurefunc(Minimap, "SetPoint", function()
        if not placing then C_Timer.After(0, function() Place(true) end) end
    end)
    -- Follow the quest tracker if it moves or changes width (checked, not hooked: hooking the
    -- tracker's own scripts risks tainting it).
    C_Timer.NewTicker(2, function() Place() end)
end)
ns.On("DISPLAY_SIZE_CHANGED", function() if Minimap then Place(true) end end)
ns.On("UI_SCALE_CHANGED", function() if Minimap then Place(true) end end)

ns.AddSettings({
    { type = "toggle", label = "Square minimap",
      get = function() return db.square ~= false end,
      set = function(on) db.square = on; Shape(); Place(true) end },
    { type = "toggle", label = "Thin border", hint = "A 1-pixel dark edge around the square map.",
      get = function() return db.border ~= false end,
      set = function(on) db.border = on; Shape() end },
    { type = "toggle", label = "Hide buttons around the edge",
      hint = "Zone text, tracking, calendar, mail, zoom and addon buttons. Turning it off needs a /reload.",
      get = function() return db.hideButtons ~= false end,
      set = function(on)
          db.hideButtons = on
          if on then HideButtons() else ns.Print("Type /reload to bring the minimap buttons back.") end
      end },
    { type = "toggle", label = "Leave room for the battery overlay",
      hint = "Moves the map down so the Steam performance overlay's battery doesn't cover it.",
      get = function() return db.overlayRoom ~= false end,
      set = function(on) db.overlayRoom = on; Place(true) end },
    { type = "toggle", label = "As wide as the quest tracker",
      hint = "Lines the map up with the tracker below it; it gets shorter to fit above it.",
      get = function() return db.matchTracker ~= false end,
      set = function(on) db.matchTracker = on; Place(true) end },
    { type = "range", label = "Size (when not matching the tracker)", min = 120, max = 260, step = 10,
      get = function() return db.size or DEFAULTS.size end,
      set = function(v) db.size = v; Place(true) end },
    { type = "range", label = "Zoom", min = 0, max = 5, step = 1,
      hint = "0 is the widest view.",
      get = function() return Minimap:GetZoom() end,
      set = function(v)
          v = math.min(v, Minimap:GetZoomLevels() - 1)
          Minimap:SetZoom(v)
          db.zoom = v
      end },
    { type = "info", label = "Disable DeckHUD in the AddOns list for Blizzard's minimap." },
})

-- Double-tapping the right paddle (DeckKit's paddle chords) hides the right side: the minimap and
-- the quest tracker. The minimap is hidden outright: its quest-area outlines and player arrow are
-- drawn by the engine and ignore transparency (it isn't a protected frame, so this works in combat).
-- The tracker only goes transparent, so its secure quest-item buttons are never touched.
DeckKit.Paddles.AddSideToggle("right", function(hidden)
    Holder():SetShown(not hidden)
    Minimap:SetAlpha(1)
    local tracker = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame or _G.WatchFrame
    if tracker then tracker:SetAlpha(hidden and 0 or 1) end
end)
