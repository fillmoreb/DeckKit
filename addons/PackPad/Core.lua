-- PackPad: your bags, controller first, built on Blizzard's own combined bag frame
-- (ContainerFrameCombinedBags) rather than replacing it. Blizzard's trusted code opens it (at
-- merchants too), registers it with the gamepad UI and drives it: the real cursor, A/B/X/Y, search,
-- the bag menus, using items in combat. PackPad only re-places Blizzard's own buttons:
--   * the bag icons (the gamepad bag bar's) in their own column on the left;
--   * the item slots in grids to their right, 10 wide, empty slots in place, one grid per kind of
--     storage: Bags (backpack and normal bags, as one), Reagents (the reagent bag), then each
--     profession bag type, quiver and ammo pouch (bags of one type share a grid), and the Keyring.
--     X on a bag icon is Blizzard's collapse: its slots leave the grid.
--
-- The approach and its rules come from BagPad (MIT, by Chris; see LICENSE), which proved them on
-- Forever's gamepad bags:
--   * Only post-hook Blizzard (hooksecurefunc). Never replace a Blizzard function, never call its
--     gamepad systems or Lua that writes state, never write fields onto its frames. Widget methods
--     (SetPoint, SetSize...) are fine: they change the frame, not Lua state.
--   * Never :Hide() Blizzard's buttons: a slot that shouldn't show is left with no anchor points. A
--     shown button without a position isn't drawn, and SmartNavigation skips it.
--   * Never CreateFrame inside the open bag frame (SmartNavigation would rescan it from our code): the
--     filler slots are made at login.
--   * The cursor's grid is built from button positions, one column per distinct X; left/right go to
--     the same index in the next column. So every row is kept full: a short last row is padded with
--     filler slots (dim, click-less buttons the cursor can rest on).
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff8fd16aPackPad|r")

local NATIVE_COLUMNS, SPACING = 10, 5 -- Blizzard's own grid
local MIN_COLUMNS, MAX_COLUMNS = 6, 20 -- the setting's range (Blizzard's 10 by default)
local SEARCH_ROW = 30 -- of the 63 px Blizzard reserves above the items (title + search): given back
local FOOT_GAP = 12 -- between the bottom row and the money bar: the same as the title's gap above the top row
local NATIVE_FOOT_GAP = 4 -- Blizzard's
-- 8 px between the border's visible inner edge and the content on each side (measured off the game:
-- Blizzard's layout leaves ~2 on the right and ~4 on the left): the grid moves in this much from the
-- right, and the frame grows by both.
local EXTRA_RIGHT, EXTRA_LEFT = 6, 6
local SIDE_GAP = 8 -- between the bag icon column and the items
local GROUP_GAP = 6 -- above a grid's label
local LABEL_HEIGHT = 14 -- a grid's label (every grid but the first)
local MAX_GROUPS = 8
local FILLER_COUNT = MAX_GROUPS * (MAX_COLUMNS - 1) -- each grid can be a row's worth short, at the widest
local FILLER_ATLAS = "bags-item-slot64"
local KEYRING = Enum and Enum.BagIndex and Enum.BagIndex.Keyring or -2 -- Forever: -1
local REAGENT = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
local BAG_ORDER = { KEYRING, 0, 1, 2, 3, 4, 5 } -- Blizzard's reading order (the bag icon column's)

-- Bag types (C_Container.GetContainerNumFreeSlots' bag family flags): a bag of one of these gets its
-- type's grid; anything else is a normal bag.
local FAMILIES = { { 1, "Quiver" }, { 2, "Ammo pouch" }, { 4, "Soul bag" }, { 8, "Leatherworking" },
    { 16, "Inscription" }, { 32, "Herbs" }, { 64, "Enchanting" }, { 128, "Engineering" }, { 512, "Gems" },
    { 1024, "Mining" } }

-- A bag's grid: its key (also the order: Bags, Reagents, the types in bag order, Keyring) and label.
local function GroupOf(bag)
    if bag == KEYRING then return "keyring", "Keyring" end
    if bag == REAGENT then return "reagent", "Reagents" end
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    family = tonumber(family) or 0
    for _, f in ipairs(FAMILIES) do
        if bit.band(family, f[1]) ~= 0 then return "family" .. f[1], f[2] end
    end
    return "bags", nil
end
ns.GroupOf = GroupOf -- for the bag peek (Peek.lua)
ns.KEYRING, ns.REAGENT = KEYRING, REAGENT

local frame -- ContainerFrameCombinedBags
local DEFAULT_SCALE = 0.7 -- the slots' and bag icons' size, of Blizzard's own (the window's header stays)

local function Scale() return (PackPadDB and PackPadDB.scale) or DEFAULT_SCALE end
local function Columns()
    local n = math.floor(((PackPadDB and PackPadDB.columns) or NATIVE_COLUMNS) + 0.5)
    return math.max(MIN_COLUMNS, math.min(MAX_COLUMNS, n))
end
local DEFAULT_BOTTOM = 48 -- pixels from the bottom edge (Blizzard leaves 85, for action bars)
local RIGHT_MARGIN = 10 -- from the right edge (Blizzard leaves 20)
local function Bottom() return (PackPadDB and PackPadDB.bottom) or DEFAULT_BOTTOM end

-- Blizzard places the frame (bottom-right of the screen, 20 in and 85 up) on every anchor pass: move it
-- after, to RIGHT_MARGIN in and Bottom() up.
local function ApplyPosition()
    if not frame or frame:GetNumPoints() ~= 1 then return end
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    if point ~= "BOTTOMRIGHT" then return end
    if math.abs(y - Bottom()) < 0.5 and math.abs(x + RIGHT_MARGIN) < 0.5 then return end
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, -RIGHT_MARGIN, Bottom())
end
local fillers = {}
local baseW, baseH -- the size Blizzard last computed
local areaW, areaH -- our item area

-- Other addons that move the same buttons: PackPad stands down while one is loaded.
local CONFLICTS = { "BagPad", "Bagnon", "AdiBags", "ArkInventory", "Baganator", "BetterBags", "Combuctor" }

local function Loaded(name) return C_AddOns.IsAddOnLoaded(name) end

------------------------------------------------------------------------
-- What's shown
------------------------------------------------------------------------

local function BagBar() return GamepadBagBar and InputUtil and InputUtil.IsGamepadUIEnabled() and GamepadBagBar end

-- The grids to lay out, in order: { label, cells = { buttons } } (Bags first, unlabeled; Reagents;
-- the bag types in bag order; Keyring last), and the bag icons in bag order. Slots of a bag collapsed
-- on the bag bar (X) get no anchor, as Blizzard does.
local function Collect()
    local bar = BagBar()
    local byBag, icons = {}, {}
    if bar then
        for _, bag in ipairs(BAG_ORDER) do
            local icon = bar:GetBagButton(bag)
            if icon then icons[#icons + 1] = icon end
        end
    end
    for _, button in ipairs(frame.Items or {}) do
        if button:IsShown() then
            local bag = button:GetBagID()
            local icon = bar and bar:GetBagButton(bag)
            if icon and icon.isCollapsed == true then
                button:ClearAllPoints()
            else
                byBag[bag] = byBag[bag] or {}
                table.insert(byBag[bag], button)
            end
        end
    end
    local groups, index = {}, {}
    local function Group(key, label)
        if not index[key] then
            index[key] = { key = key, label = label, cells = {} }
        end
        return index[key]
    end
    Group("bags", nil)
    Group("reagent", "Reagents")
    local order = { "bags", "reagent" }
    for _, bag in ipairs({ 0, 1, 2, 3, 4, 5, KEYRING }) do
        local list = byBag[bag]
        if list then
            table.sort(list, function(a, b) return a:GetID() < b:GetID() end)
            local key, label = GroupOf(bag)
            if not index[key] then order[#order + 1] = key end
            local g = Group(key, label)
            for _, button in ipairs(list) do g.cells[#g.cells + 1] = button end
        end
    end
    for _, key in ipairs(order) do
        if #index[key].cells > 0 then groups[#groups + 1] = index[key] end
    end
    return groups, icons
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------

-- A slot's size in the frame's units, at our scale (GetWidth is the button's own, unscaled size).
local function CellSize()
    local first = frame.Items and frame.Items[1]
    if first then return first:GetWidth() * Scale(), first:GetHeight() * Scale() end
end

local function ReleaseFillers(from)
    for i = from, #fillers do fillers[i]:ClearAllPoints() end
end

local labels = {}

local function Label(i)
    if not labels[i] then
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        labels[i] = text
    end
    return labels[i]
end

local function ApplyGrid()
    local cellW, cellH = CellSize()
    if not frame:IsShown() or not cellW then
        ReleaseFillers(1)
        for _, l in ipairs(labels) do l:Hide() end
        areaW = nil
        return
    end
    local COLUMNS = Columns()
    local spacing = SPACING * Scale() -- the gaps shrink with the slots
    local stepX, stepY = cellW + spacing, cellH + spacing
    local groups, icons = Collect()

    -- Pad each grid's short last row (see the top of the file).
    local used = 0
    for _, group in ipairs(groups) do
        local short = (COLUMNS - #group.cells % COLUMNS) % COLUMNS
        for _ = 1, short do
            local filler = fillers[used + 1]
            if not filler then break end
            used = used + 1
            filler:SetSize(cellW / Scale(), cellH / Scale()) -- scaled like the slots when placed
            group.cells[#group.cells + 1] = filler
        end
    end
    ReleaseFillers(used + 1)

    local gridW = COLUMNS * stepX - spacing
    local columnW = #icons > 0 and (stepX + SIDE_GAP) or 0

    -- Top-down: each grid after the first gets a gap and its label, then its rows.
    local placements, labelsAt, y = {}, {}, 0
    for gi, group in ipairs(groups) do
        if gi > 1 then
            y = y + GROUP_GAP
            if group.label then
                labelsAt[#labelsAt + 1] = { text = group.label, top = y }
                y = y + LABEL_HEIGHT
            end
        end
        for i, cell in ipairs(group.cells) do
            local r, c = math.floor((i - 1) / COLUMNS), (i - 1) % COLUMNS
            placements[#placements + 1] = { cell = cell, x = columnW + c * stepX, top = y + r * stepY }
        end
        y = y + math.ceil(#group.cells / COLUMNS) * stepY
    end
    local itemsH = math.max(cellH, y - spacing)
    local iconsH = #icons * stepY - spacing
    local width, height = gridW + columnW, math.max(itemsH, iconsH, cellH)

    -- Placed by top-left corner from the top-left of the item area, which sits on Blizzard's gold
    -- display (as Blizzard's own items do).
    -- Slots and icons are scaled (SetScale on the button), and a scaled region reads its anchor
    -- offsets in its own units: divide by its scale so the grid lands where it's computed.
    local money = frame.MoneyFrame
    local scale = Scale()
    local function Place(region, x, top, s)
        s = s or 1
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", money, "TOPRIGHT", (x - width - EXTRA_RIGHT) / s, (FOOT_GAP + height - top) / s)
    end
    for _, p in ipairs(placements) do
        p.cell:SetScale(scale)
        Place(p.cell, p.x, p.top, scale)
    end
    for k, icon in ipairs(icons) do
        icon:SetScale(scale)
        Place(icon, 0, (k - 1) * stepY, scale)
    end
    -- The bottom row (the last grid's last row, and the bottom bag icon): Down from there selects the
    -- broom, in the footer.
    local bottomRow, lastTop = {}, placements[#placements] and placements[#placements].top
    for _, p in ipairs(placements) do
        if p.top == lastTop then bottomRow[p.cell] = true end
    end
    if icons[#icons] then bottomRow[icons[#icons]] = true end
    ns.bottomRow = bottomRow
    for i, info in ipairs(labelsAt) do
        local label = Label(i)
        label:SetWidth(gridW)
        label:SetText(info.text)
        Place(label, columnW, info.top)
        label:Show()
    end
    for i = #labelsAt + 1, #labels do labels[i]:Hide() end

    -- Blizzard's "add an authenticator for more slots" button sits between two columns, which
    -- would pull the cursor off the grid: no anchor, like a collapsed slot (BagPad EB.8).
    if frame.AddSlotsButton then frame.AddSlotsButton:ClearAllPoints() end
    areaW, areaH = width, height
end

-- Swaps Blizzard's item area for ours, keeping what it reserves around it (title, search, gold).
local function ApplySize()
    local cellW, cellH = CellSize()
    if not cellW or not baseW or not areaW then return end
    -- Blizzard's own item area in gamepad mode: shown slots plus one cell per bag icon, 10 wide.
    local slots = (frame.shownSlots or 0) + (NUM_CONTAINER_FRAMES or 0)
    local rows = math.max(1, math.ceil(slots / NATIVE_COLUMNS))
    local nativeCellW, nativeCellH = cellW / Scale(), cellH / Scale() -- Blizzard's own cells are unscaled
    local nativeW = NATIVE_COLUMNS * nativeCellW + (NATIVE_COLUMNS - 1) * SPACING
    local nativeH = rows * nativeCellH + (rows - 1) * SPACING
    frame:SetSize(baseW - nativeW + areaW + EXTRA_LEFT + EXTRA_RIGHT,
        baseH - nativeH + areaH - SEARCH_ROW + FOOT_GAP - NATIVE_FOOT_GAP)
end

-- The search box (Blizzard's shared BagItemSearchBox) and its button prompt (SearchBoxIcon) are faded
-- out, and the search row's height is given back. Faded, not hidden or moved: Blizzard re-anchors the
-- box on every bag update, and nothing of Blizzard's is :Hide()-den (see the top of the file).
local function HideSearch()
    if BagItemSearchBox and BagItemSearchBox:GetParent() == frame then
        BagItemSearchBox:SetAlpha(0)
        BagItemSearchBox:EnableMouse(false)
    end
    if frame.SearchBoxIcon then frame.SearchBoxIcon:SetAlpha(0) end
end

-- The money bar starts just right of the broom (which sits at the footer's left end: Broom.lua), not
-- under it. Re-anchored with SetPoint only; the right edge (which the item area sits on) stays where
-- Blizzard put it.
local MONEY_LEFT = 36 -- the broom: 9 in, 22 wide, then a 5 px gap
local function ApplyMoney()
    local money = frame.MoneyFrame
    if not money then return end
    local _, _, _, x = money:GetPoint(1)
    if money:GetNumPoints() == 2 and x and math.abs(x - MONEY_LEFT) < 0.5 then return end
    money:ClearAllPoints()
    money:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", MONEY_LEFT, 8)
    money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
end

local function Relayout()
    ApplyGrid()
    ApplySize()
    HideSearch()
    ApplyMoney()
    ns.Marks.Refresh(frame)
end



------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------

-- The frame: Blizzard's bag border (HeldBagLayout, with the bag portrait in its top-left corner) gives
-- way to a portrait-less one, ButtonFrameTemplateNoPortrait (the same metal at Blizzard's own offsets; the
-- LessPadding variant pulls the right and bottom corners 3-4 px in, which reads chunkier), on PackPad's
-- own frame (a plain
-- Frame inside the bag frame, made at login: never a Button, so the cursor's grid doesn't see it).
-- Applying the layout to Blizzard's own NineSlice would run Blizzard's layout code on its frame, which
-- writes state onto it. Blizzard's border and portrait are faded out, and the portrait's button (the
-- bag menu) gets no anchor, so the cursor never stops on an invisible button (BagPad's way).
local border, backing
local function CreateBorder()
    if not (NineSliceUtil and NineSliceUtil.GetLayout("ButtonFrameTemplateNoPortrait")) then return end
    border = CreateFrame("Frame", "PackPadBorder", frame)
    border:SetAllPoints(frame)
    border:SetFrameLevel((frame.NineSlice and frame.NineSlice:GetFrameLevel()) or frame:GetFrameLevel() + 1)
    NineSliceUtil.ApplyLayoutByName(border, "ButtonFrameTemplateNoPortrait")
    -- Blizzard's own border filled the middle; this one is edges only, so the window gets its own dark
    -- backing (a texture on the bag frame, below everything in it), or what's behind shows through.
    backing = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backing:SetColorTexture(0.055, 0.055, 0.065, 0.97)
    backing:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    backing:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
end

-- "Backpack" (the game's own word, BACKPACK_TOOLTIP) instead of "Combined Backpack". Blizzard writes its
-- title on its own updates (SetTitle / UpdateName): this runs after them. Only SetText on its font string.
local function Retitle()
    local text = frame.TitleContainer and frame.TitleContainer.TitleText
    local name = BACKPACK_TOOLTIP or "Backpack"
    if text and text:GetText() ~= name then text:SetText(name) end
end

-- The focus glow (lit while the bags have the controller's focus): Blizzard's FrameGlow picks its art by
-- the frame's layout, so it still draws the portrait-shaped one (HeldBagLayout). PackPad fades that
-- texture (not the glow frame: Blizzard sets its alpha from the GamepadFocusStateOpacity setting) and
-- draws Blizzard's own glow for the new border (FocusEffects.lua's FrameGlowTable entry for
-- ButtonFrameTemplateNoPortrait: gamepad-uiframemetal-focus, -10,14 / 14,-14), shown and hidden with
-- Blizzard's and colored by the player's focus color and opacity settings, as Blizzard's is.
-- That art has a soft fill toward its middle, so it goes BEHIND the window (a frame on UIParent one
-- strata below the bag frame's, matched to its scale): the window covers the fill and only the outer
-- halo shows. Inside the window it would tint everything (an inner glow).
local glow
local GLOW_COLORS = { [1] = { 1, 0.9, 0.4 }, [2] = { 0, 0, 0 }, [3] = { 0.3, 0.5, 1 } } -- gold, black, blue

local function GlowLook()
    if not glow then return end
    local c = GLOW_COLORS[tonumber(C_CVar.GetCVar("GamepadFocusStateColor"))]
    if c then
        glow.texture:SetVertexColor(c[1], c[2], c[3])
        glow.boost:SetVertexColor(c[1], c[2], c[3])
    end
    glow:SetAlpha(tonumber(C_CVar.GetCVar("GamepadFocusStateOpacity")) or 1)
end

local STRATA_BELOW = { HIGH = "MEDIUM", DIALOG = "HIGH", FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN",
    MEDIUM = "LOW", LOW = "BACKGROUND", TOOLTIP = "FULLSCREEN_DIALOG" }

local function CreateGlow()
    local native = frame.FrameGlow
    if not (border and native) then return end
    glow = CreateFrame("Frame", "PackPadGlow", UIParent)
    local function Match()
        glow:SetFrameStrata(STRATA_BELOW[frame:GetFrameStrata()] or "MEDIUM")
        glow:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    Match()
    frame:HookScript("OnShow", Match)
    hooksecurefunc("UpdateContainerFrameAnchors", Match)
    frame:HookScript("OnHide", function() glow:Hide() end)
    -- Blizzard's offsets for this layout (wider looked wrong); a second, additive copy brightens it, since
    -- behind the window only the part past the border shows.
    glow:SetPoint("TOPLEFT", border, "TOPLEFT", -10, 14)
    glow:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 14, -14)
    glow.texture = glow:CreateTexture(nil, "BACKGROUND")
    glow.texture:SetAtlas("gamepad-uiframemetal-focus")
    glow.texture:SetAllPoints()
    glow.boost = glow:CreateTexture(nil, "BORDER")
    glow.boost:SetAtlas("gamepad-uiframemetal-focus")
    glow.boost:SetBlendMode("ADD")
    glow.boost:SetAllPoints()
    glow:SetShown(native:IsShown() and frame:IsShown())
    native:HookScript("OnShow", function() GlowLook(); Match(); glow:SetShown(frame:IsShown()) end)
    native:HookScript("OnHide", function() glow:Hide() end)
end

local function ApplyFrameLook()
    if not border then return end
    if frame.FrameGlow and frame.FrameGlow.GlowTexture then frame.FrameGlow.GlowTexture:SetAlpha(0) end
    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
    if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end
    if frame.CountContainer then frame.CountContainer:SetAlpha(0) end -- the free-slot count under the portrait
    local portrait = ContainerFrameCombinedBagsPortraitButton
    if portrait and portrait:GetNumPoints() > 0 then portrait:ClearAllPoints() end
    local title = frame.TitleContainer
    if title then
        local _, _, _, x = title:GetPoint(1)
        if x and math.abs(x - 8) > 0.5 then
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -1)
            title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -1)
        end
    end
    Retitle()
end

local function CreateFillers()
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FILLER_ATLAS) ~= nil
    for i = 1, FILLER_COUNT do
        local filler = CreateFrame("Button", nil, frame)
        filler:SetSize(37, 37) -- SmartNavigation only collects buttons that have a size
        local bg = filler:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if hasAtlas then bg:SetAtlas(FILLER_ATLAS) else bg:SetColorTexture(0.12, 0.12, 0.14, 1) end
        -- Solid, like Blizzard's own empty slots (a faint one shows whatever is behind the window).
        bg:SetDesaturated(true)
        bg:SetVertexColor(0.55, 0.55, 0.55)
        filler:ClearAllPoints()
        fillers[i] = filler
    end
end

ns.On("PLAYER_LOGIN", function()
    PackPadDB = PackPadDB or {}
    for _, name in ipairs(CONFLICTS) do
        if Loaded(name) then
            ns.Print(name .. " is loaded and moves the same bag buttons, so PackPad is staying out of the way. "
                .. "Turn one of them off.")
            return
        end
    end
    frame = ContainerFrameCombinedBags
    if not frame then
        ns.Print("Blizzard's combined bag frame isn't in this client: PackPad is off.")
        return
    end
    CreateFillers()
    CreateBorder()
    CreateGlow()
    ns.Broom.Create()
    hooksecurefunc(frame, "UpdateFrameSize", function()
        baseW, baseH = frame:GetSize()
        ApplySize()
    end)
    hooksecurefunc(frame, "UpdateItemLayout", Relayout)
    if frame.UpdateSearchBox then hooksecurefunc(frame, "UpdateSearchBox", HideSearch) end
    frame:HookScript("OnShow", HideSearch)
    frame:HookScript("OnShow", ApplyFrameLook)
    -- The bounce, once the slots are filled and placed (Blizzard updates them right after showing).
    frame:HookScript("OnShow", function()
        C_Timer.After(0.15, function()
            if frame:IsShown() then
                ns.Marks.Refresh(frame)
                ns.Marks.BounceAll(frame)
                ns.Marks.StartNudging(frame)
            end
        end)
    end)
    ns.On("BAG_UPDATE_DELAYED", function() if frame:IsShown() then ns.Marks.Refresh(frame) end end)
    frame:HookScript("OnHide", function() ns.Marks.StopNudging() end)
    hooksecurefunc(frame, "UpdateItemLayout", ApplyFrameLook)
    hooksecurefunc(frame, "SetTitle", Retitle)
    hooksecurefunc(frame, "UpdateName", Retitle)
    hooksecurefunc("UpdateContainerFrameAnchors", ApplyPosition)
    -- Update() calls UpdateFilterIcon before UpdateSearchBox, which rebuilds the cursor's grid from
    -- the buttons' positions: laying out here keeps that grid in step with ours (BagPad's finding).
    hooksecurefunc(frame, "UpdateFilterIcon", Relayout)
    ns.Debug("hooks installed")
end)

if ns.Chords and ns.Chords.OfferPress then
    ns.Chords.OfferPress("PACKPAD_CLEAR_MARKS", function() ns.Marks.ClearAll() end, "Clear item marks")
end

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Bags" },
    { type = "info", label = "Bag peek: hold its grip slot (Controls > Grips, \"Bag peek\") to see everything you carry, full screen. Both sticks stay yours." },
    { type = "action", label = "Clear item marks", verb = "Clear",
      hint = "Takes the stars off every marked item (the ones Decky flagged, for one).",
      run = function() ns.Marks.ClearAll() end },
    { type = "range", label = "Bag slot size", min = 0.5, max = 1, step = 0.05,
      format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
      hint = "The size of the item slots and bag icons, as a share of Blizzard's own (the window's title, "
          .. "search and gold stay as they are).",
      get = function() return Scale() end,
      set = function(v) PackPadDB.scale = v; if frame and frame:IsShown() then Relayout() end end },
    { type = "range", label = "Bag columns", min = MIN_COLUMNS, max = MAX_COLUMNS, step = 1,
      format = function(v) return tostring(math.floor(v + 0.5)) end,
      hint = "How many slots wide the grids are (Blizzard's own is 10).",
      get = function() return Columns() end,
      set = function(v) PackPadDB.columns = math.floor(v + 0.5); if frame and frame:IsShown() then Relayout() end end },
    { type = "range", label = "Bag window height", min = 0, max = 200, step = 4,
      format = function(v) return v .. " px up" end,
      hint = "How far above the bottom edge of the screen the bags sit (Blizzard's own spot is 85).",
      get = function() return Bottom() end,
      set = function(v) PackPadDB.bottom = v; ApplyPosition() end },
})

ns.AddCommand("pack", function()
    if not frame then return ns.Print("off (see the message at login)") end
    local groups = Collect()
    local parts = {}
    for _, g in ipairs(groups) do parts[#parts + 1] = (g.label or "Bags") .. " " .. #g.cells end
    ns.Print(("%s; %s"):format(table.concat(parts, ", "), frame:IsShown() and "bags open" or "bags closed"))
end, "PackPad: your bags, with the bag icons in their own column")
