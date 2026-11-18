-- DeckHUD's minimap: square, a thin border (or none), in the top-right corner, without the buttons
-- and frame art around its edge.
--
-- The minimap is moved out of Blizzard's MinimapCluster (which holds the zone text, tracking,
-- calendar, mail and the other edge buttons) onto UIParent, and the cluster is hidden. Addon
-- minimap buttons (LibDBIcon ones, or any named "...MinimapButton") are hidden too.
-- Optionally it leaves room above the map for the Steam performance overlay's battery readout.
--
-- Settings live in the DeckKit menu (double-tap Menu, or /deckkit).
local _, ns = ...

local DEFAULTS = { square = true, hideButtons = true, border = true, overlayRoom = true }
ns.Defaults(DEFAULTS)
local OVERLAY_PX = 30 -- screen pixels kept clear for the Steam battery overlay (it's about 26 tall)
local MARGIN_PX = 4   -- gap to the screen edges
local DIALOG_PX = 4   -- extra gap on the right for the dialog border
-- The map's size, fixed (the Deck's screen is known: 1280 x 800 UI units). Measured on Ben's priest on
-- 2026-11-17, where it was sized to the quest tracker: 260 wide with its border (256 of map inside the dialog
-- border's gap), 253.44 tall, so its bottom sits about 6 above the tracker's top (514 up from the screen's
-- bottom; GuidePad's panel takes the same spot).
local MAP_W, MAP_H, RIGHT = 260, 253.44, 5 -- 253.44: 256 with a 1% cut (masks/crop_01)
local DIALOG_OUT = 3  -- how far the dialog border sits outside the map

local function DB() return ns.db end

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
    return DB().square ~= false and "SQUARE" or "ROUND"
end

------------------------------------------------------------------------
-- Hiding things
------------------------------------------------------------------------

local hooked = {}

local function KeepHidden(f)
    if type(f) ~= "table" or type(f.Hide) ~= "function" then return end
    if not hooked[f] then
        hooked[f] = true
        local function again(self) if DB().hideButtons ~= false then self:Hide() end end
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
    if DB().hideButtons == false then return end
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

local border, metal, dialog, holder
local placing = false
local placed = {} -- last width / height / right / top, to skip needless re-placing

local function PixelsToUnits(px)
    local _, physical = GetPhysicalScreenSize()
    return px * UIParent:GetHeight() / (physical or 800)
end

-- The map sits centered in a holder the size of the part you see. The minimap itself stays
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
    if DB().square == false then return "Interface\\Masks\\CircleMaskScalable" end
    if cropPct <= 0 then return "Interface\\Buttons\\WHITE8X8" end
    return string.format("Interface\\AddOns\\DeckHUD\\masks\\crop_%02d", cropPct)
end

-- Border style: "dialog" (the classic tooltip edge, BACKDROP_TUTORIAL_16_16, edge only),
-- "metal" (the thin metal frame of DeckKit windows: the SimplePanelTemplate nine-slice), "line"
-- (1 px dark edge) or false (none). Older saves only have border = false for none.
local function BorderStyle()
    if DB().borderStyle ~= nil then return DB().borderStyle end
    if DB().border == false then return false end
    return "dialog"
end

-- Quest, task and archaeology areas on the minimap: where an area reaches past the edge, the game
-- draws a "ring" glow along a circle, which cuts across a square map. Square: no ring. Round: the
-- game's own look comes back on a /reload (the default values can't be read back).
local function Blobs()
    if DB().square == false then return end
    for _, kind in ipairs({ "Quest", "Task", "Arch" }) do
        local scalar, alpha = Minimap["Set" .. kind .. "BlobRingScalar"], Minimap["Set" .. kind .. "BlobRingAlpha"]
        if scalar then scalar(Minimap, 0) end
        if alpha then alpha(Minimap, 0) end
    end
end

local function Shape()
    Minimap:SetMaskTexture(Mask())
    Blobs()
    if not border then
        border = CreateFrame("Frame", nil, Holder(), "BackdropTemplate")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(0, 0, 0, 0.9)
        border:SetFrameLevel(Holder():GetFrameLevel() + 20)
    end
    if not metal then
        -- Its own frame above the map (the map would draw over textures on the holder itself).
        metal = CreateFrame("Frame", nil, Holder())
        metal:SetAllPoints()
        metal:SetFrameLevel(Holder():GetFrameLevel() + 30)
        DeckKit.UI.Border(metal, "SimplePanelTemplate")
    end
    if not dialog then
        -- Edge only (its background would cover the map), pushed out so the edge sits mostly
        -- outside the map: the edge art draws a few px in from the frame's bounds.
        dialog = CreateFrame("Frame", nil, Holder(), "BackdropTemplate")
        dialog:SetPoint("TOPLEFT", -DIALOG_OUT, DIALOG_OUT)
        dialog:SetPoint("BOTTOMRIGHT", DIALOG_OUT, -DIALOG_OUT)
        local b = BACKDROP_TUTORIAL_16_16
        dialog:SetBackdrop({ edgeFile = b and b.edgeFile or "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = b and b.edgeSize or 16, tile = true, tileEdge = true })
        dialog:SetFrameLevel(Holder():GetFrameLevel() + 30)
    end
    local style, square = BorderStyle(), DB().square ~= false
    border:SetShown(square and style == "line")
    metal:SetShown(square and style == "metal")
    dialog:SetShown(square and style == "dialog")
end

-- Width, height and offsets from the top-right corner, in UIParent units.
local function Layout()
    -- Under the status bar while it shows (StatusBar.lua); else clear of the Steam overlay, if asked.
    local bar = ns.StatusBarHeight and ns.StatusBarHeight() or 0
    local top = bar > 0 and (bar + PixelsToUnits(MARGIN_PX))
        or PixelsToUnits(MARGIN_PX + (DB().overlayRoom ~= false and OVERLAY_PX or 0))
    -- The dialog border sticks out past the map; keep it clear of the screen's right edge.
    local inset = (DB().square ~= false and BorderStyle() == "dialog") and PixelsToUnits(DIALOG_PX) or 0
    local w = MAP_W - inset
    return w, DB().square ~= false and MAP_H or w, RIGHT + inset, top
end

local function Place(force)
    if InCombatLockdown() and Minimap:IsProtected() then return end
    local w, h, right, top = Layout()
    if not force and placed.w == w and placed.h == h and placed.right == right and placed.top == top
        and Minimap:GetParent() == holder then return end
    placed.w, placed.h, placed.right, placed.top = w, h, right, top
    -- Round the cut up to a whole percent, so the map never reaches past h.
    cropPct = math.min(MAX_CROP, math.max(0, math.ceil((1 - h / w) * 100 - 0.001)))
    if DB().square == false then cropPct = 0 end
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

-- The zone's name across the top of the map (Blizzard's sits in the hidden cluster), colored
-- like Blizzard's: green friendly, red hostile, gold contested, blue sanctuary.
local zoneBar
local ZONE_COLORS = { friendly = { 0.1, 1, 0.1 }, hostile = { 1, 0.1, 0.1 }, contested = { 1, 0.7, 0 },
    sanctuary = { 0.41, 0.8, 0.94 }, arena = { 1, 0.1, 0.1 }, combat = { 1, 0.1, 0.1 } }

local function ZoneTitle()
    if not zoneBar then
        zoneBar = CreateFrame("Frame", nil, Holder())
        zoneBar:SetPoint("TOPLEFT")
        zoneBar:SetPoint("TOPRIGHT")
        zoneBar:SetHeight(18)
        zoneBar:SetFrameLevel(Holder():GetFrameLevel() + 25)
        local bg = zoneBar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        zoneBar.text = zoneBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        zoneBar.text:SetPoint("LEFT", 4, 0)
        zoneBar.text:SetPoint("RIGHT", -4, 0)
        zoneBar.text:SetWordWrap(false)
    end
    zoneBar:SetShown(DB().zoneTitle ~= false)
    local name = GetMinimapZoneText and GetMinimapZoneText() or GetZoneText()
    zoneBar.text:SetText(name or "")
    local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    local c = ZONE_COLORS[pvp or ""] or { 1, 0.82, 0 }
    zoneBar.text:SetTextColor(c[1], c[2], c[3])
end
for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    ns.On(e, function() if Minimap then ZoneTitle() end end)
end

local function Apply()
    if not Minimap then return end
    Place(true)
    Shape()
    HideButtons()
    ZoneTitle()
end
ns.Apply = Apply

ns.On("PLAYER_LOGIN", function()
    Apply()
    if DB().zoom then Minimap:SetZoom(math.min(DB().zoom, Minimap:GetZoomLevels() - 1)) end
    -- Addons register their minimap buttons at different times.
    C_Timer.After(2, HideButtons)
    C_Timer.After(10, HideButtons)
    local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBI and LDBI.RegisterCallback then
        LDBI.RegisterCallback(ns, "LibDBIcon_IconCreated", function(_, button) if DB().hideButtons ~= false then KeepHidden(button) end end)
    end
    -- Edit Mode (or anything else) moving the map back: put it where it belongs again.
    hooksecurefunc(Minimap, "SetPoint", function()
        if not placing then C_Timer.After(0, function() Place(true) end) end
    end)
    -- The status bar showing or hiding moves the map's top: checked now and then.
    C_Timer.NewTicker(2, function() Place() end)
end)
ns.On("DISPLAY_SIZE_CHANGED", function() if Minimap then Place(true) end end)
ns.On("UI_SCALE_CHANGED", function() if Minimap then Place(true) end end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Minimap", order = 3 },
    { type = "toggle", label = "Square minimap",
      get = function() return DB().square ~= false end,
      set = function(on) DB().square = on; Shape(); Place(true) end },
    { type = "toggle", label = "Zone name on the map",
      hint = "The zone or area you're in, across the top of the minimap, colored friendly / hostile / contested.",
      get = function() return DB().zoneTitle ~= false end,
      set = function(on) DB().zoneTitle = on; ZoneTitle() end },
    { type = "choice", label = "Border", values = { { "dialog", "Dialog" }, { "metal", "Thin metal" }, { "line", "Thin line" }, { false, "None" } },
      hint = "Dialog: the classic dialog box edge. Thin metal: the frame of DeckKit's windows. Thin line: a 1-pixel dark edge.",
      get = function() return BorderStyle() end,
      set = function(v) DB().borderStyle = v; Shape(); Place(true) end },
    { type = "toggle", label = "Hide buttons around the edge", reload = true,
      hint = "Zone text, tracking, calendar, mail, zoom and addon buttons. Turning it off needs a /reload.",
      get = function() return DB().hideButtons ~= false end,
      set = function(on)
          DB().hideButtons = on
          if on then HideButtons() else ns.Print("Type /reload to bring the minimap buttons back.") end
      end },
    { type = "toggle", label = "Leave room for the battery overlay",
      hint = "Moves the map down so the Steam performance overlay's battery doesn't cover it.",
      get = function() return DB().overlayRoom ~= false end,
      set = function(on) DB().overlayRoom = on; Place(true) end },
    { type = "range", label = "Zoom", min = 0, max = 5, step = 1,
      hint = "0 is the widest view.",
      get = function() return Minimap:GetZoom() end,
      set = function(v)
          v = math.min(v, Minimap:GetZoomLevels() - 1)
          Minimap:SetZoom(v)
          DB().zoom = v
      end },
    { type = "info", label = "Disable DeckHUD in the AddOns list for Blizzard's minimap." },
})

-- Hiding the right side (a DeckKit grip chord slot, "Hide right side") hides it too. DeckKit makes
-- whatever sits along that edge transparent; the minimap has to be hidden outright instead, since
-- its quest-area outlines and player arrow are drawn by the engine and ignore transparency (it
-- isn't a protected frame, so this works in combat).
DeckKit.Grips.AddSideToggle("right", function(hidden)
    Holder():SetShown(not hidden)
    Minimap:SetAlpha(1)
end)
