-- Need / Greed / Pass. With Gamepad UI on, Forever shows loot rolls in its own "Loot Rolls" window
-- (GamepadGroupLootRollFrame: a card per item, A Need, X Greed, B Pass, d-pad between cards). It
-- shows up without the pad, with the game's "View to focus" hint under it; View gives it the pad.
--
--   * Top-left corner: the window's place is fixed in Blizzard's XML (left side, over the chat and
--     the player frame). This moves it to the top-left corner, under the XP bar if that runs along
--     the top. Only its anchor changes, out of combat: it isn't an Edit Mode frame, it isn't
--     protected, and Blizzard never re-anchors it.
--   * Compact until focused: while the window doesn't have the pad, it's made transparent and a
--     small list of ours shows in its place: each item's name in its quality color, over a bar that
--     runs down with the roll's time, and the View glyph on the bottom edge. Press View and the game's
--     window comes back with the pad; ours hides. Only the window's alpha is changed (alpha only,
--     like the hidden crossbar labels), nothing of Blizzard's is hooked but OnShow / OnHide
--     (HookScript, after theirs). Ours reads the rolls from the window's own list and the game's
--     roll functions.
local _, ns = ...

local EDGE = 4      -- gap to the screen edges and the XP bar, as for the raid frames (Layout.lua)
local ROW_W, ROW_H, ROW_GAP = 230, 24, 2
local MAX_ROWS = 8
local PAD = 10       -- inside the frame
local MIN_H = 64     -- the metal edge's corners are 64 tall (as for the dictation box)

local function TopLeft() return ns.db.lootRollsTopLeft ~= false end
local function Compact() return ns.db.lootRollsCompact ~= false end
local function ListAlpha() return ns.db.lootRollsAlpha or 1 end -- our list only, never the game's window

local function Window() return _G.GamepadGroupLootRollFrame end

------------------------------------------------------------------------
-- Top-left corner
------------------------------------------------------------------------

-- How far down from the top the XP bar (and the bar stacked with it) reach, 0 when not along the top.
local function BarsBottom()
    local top = UIParent:GetTop()
    local below = 0
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local bar = _G[name]
        if bar and bar:IsVisible() and bar:GetTop() and top - bar:GetTop() < 2 + below then
            below = math.max(below, top - bar:GetBottom())
        end
    end
    return below
end

local original -- Blizzard's anchor, to put back when turned off
local list     -- our compact list

local function Place()
    local f = Window()
    if not f or InCombatLockdown() then return end
    if not original then original = { f:GetPoint(1) } end
    f:ClearAllPoints()
    if TopLeft() then
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", EDGE, -math.floor(BarsBottom() + EDGE + 0.5))
    else
        f:SetPoint(unpack(original))
    end
    if list then
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    end
end

------------------------------------------------------------------------
-- Compact list
------------------------------------------------------------------------

local rows = {}

-- How each row shows its time left: "line" a thin bar under the name, "seconds" a countdown at the
-- right end, "behind" a bar filling the row behind the name.
local function TimerStyle() return ns.db.lootRollsTimer or "line" end

local LINE_H = 3

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, list)
    r:SetSize(ROW_W, ROW_H)
    r:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * (ROW_H + ROW_GAP))
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.6)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r.bar:GetStatusBarTexture():SetHorizTile(false)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetFrameLevel(r:GetFrameLevel())
    r.track = r.bar:CreateTexture(nil, "BACKGROUND")
    r.track:SetAllPoints()
    r.track:SetColorTexture(0, 0, 0, 1) -- as under the game's own timer bar
    local text = CreateFrame("Frame", nil, r)
    text:SetAllPoints()
    text:SetFrameLevel(r.bar:GetFrameLevel() + 1)
    r.secs = text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.secs:SetPoint("RIGHT", -6, 0)
    r.secs:SetJustifyH("RIGHT")
    r.name = text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    rows[i] = r
    return r
end

-- Lays a row out for the timer style (only when the style changed).
local function Layout(r, style)
    if r.style == style then return end
    r.style = style
    r.bar:ClearAllPoints()
    r.name:ClearAllPoints()
    if style == "behind" then
        r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        r.bar:SetAllPoints()
        r.track:Hide()
        r.bg:Show()
        r.name:SetPoint("LEFT", 6, 0)
        r.name:SetPoint("RIGHT", -6, 0)
    elseif style == "seconds" then
        r.bg:Hide()
        r.name:SetPoint("LEFT", 2, 0)
        r.name:SetPoint("RIGHT", r.secs, "LEFT", -6, 0)
    else -- line
        -- The game's own loot roll timer: its texture and yellow, on black.
        r.bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
        r.bar:SetStatusBarColor(1, 1, 0)
        r.bar:SetPoint("BOTTOMLEFT", 2, -3)
        r.bar:SetPoint("BOTTOMRIGHT", -2, -3)
        r.bar:SetHeight(LINE_H)
        r.track:Show()
        r.bg:Hide()
        r.name:SetPoint("BOTTOMLEFT", 2, 7) -- the bar sits lower, about midway to the next name
        r.name:SetPoint("RIGHT", -2, 0)
    end
    r.bar:SetShown(style ~= "seconds")
    r.secs:SetShown(style == "seconds")
end

local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- The rolls the game's window is waiting on, one row each.
local function DrawRows()
    local f = Window()
    local style = TimerStyle()
    local n = 0
    for _, roll in ipairs(f and f.waitingRolls or {}) do
        if n >= MAX_ROWS then break end
        local _, name, count, quality = GetLootRollItemInfo(roll.rollID)
        if name then
            n = n + 1
            local r = Row(n)
            Layout(r, style)
            local cr, cg, cb = QualityColor(quality)
            -- In brackets, as items are in chat.
            r.name:SetText("[" .. name .. "]" .. (count and count > 1 and (" x" .. count) or ""))
            r.name:SetTextColor(cr, cg, cb)
            local left = GetLootRollTimeLeft(roll.rollID) or 0 -- milliseconds
            if style == "seconds" then
                r.secs:SetText(math.ceil(left / 1000))
            else
                if style == "behind" then
                    -- Neutral behind the name, so its quality color stays readable.
                    r.bar:SetStatusBarColor(0.5, 0.5, 0.5, 0.45)
                end
                r.bar:SetValue(roll.rollTime and roll.rollTime > 0 and math.min(1, left / roll.rollTime) or 0)
            end
            r:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    -- Room at the bottom for the View hint, clear of the last row.
    list:SetHeight(math.max(MIN_H, PAD * 2 + n * (ROW_H + ROW_GAP) - ROW_GAP + 18))
    return n
end

-- The game's window has the pad: the player pressed View (or it was the frame View went to). Not
-- while a DeckKit window is open: opening the DeckKit menu with Menu twice opens and closes the
-- game's menu wheel, and the wheel hands the game's focus to whatever window is up as it closes
-- (GamepadRadial OnHide), though the DeckKit menu has the pad.
local function GameFocused(f)
    local m = GamepadMode and GamepadMode.FrameControlsManager
    return m and m.isUIFocused and m.focusedFrame == f
end

local function DeckKitScreenShown()
    return DeckKit.UI.AnyScreenShown and DeckKit.UI.AnyScreenShown() or false
end

local function Focused(f)
    return GameFocused(f) and not DeckKitScreenShown()
end

-- With the game's focus on its (hidden) window while a DeckKit window has the pad, its focus effects
-- would float over the screen: the selection cursor (the game's SmartNavigation pointer) and the
-- item tooltip it opens for the selected card. Both are hidden then: the pointer by alpha, put back
-- after; the tooltip only when it belongs to one of the window's cards.
-- TODO: better would be taking the game's focus back as the DeckKit menu opens (Menu.lua, where the
-- wheel is closed), so nothing is focused behind it. That changes the game's gamepad focus from addon
-- code, so it needs a clean taint-log test first.
local pointerHidden = false

local function HideGhosts(f, ghost)
    local pointer = _G.SmartNavigation
    if ghost then
        local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if owner and owner.rollListFrame == f then GameTooltip:Hide() end
        if pointer and pointer:GetAlpha() ~= 0 then pointer:SetAlpha(0); pointerHidden = true end
    elseif pointerHidden then
        if pointer then pointer:SetAlpha(1) end
        pointerHidden = false
    end
end

local function Update()
    local f = Window()
    if not f then return end
    HideGhosts(f, Compact() and f:IsShown() and GameFocused(f) and DeckKitScreenShown())
    local showOurs = Compact() and f:IsShown() and not Focused(f)
    if showOurs and DrawRows() == 0 then showOurs = false end
    local alpha = showOurs and 0 or 1
    if f:GetAlpha() ~= alpha then f:SetAlpha(alpha) end
    list:SetShown(showOurs)
    if list:GetAlpha() ~= ListAlpha() then list:SetAlpha(ListAlpha()) end
end

local function Build()
    local f = Window()
    if list or not f then return end
    list = CreateFrame("Frame", "DeckHUDLootRolls", UIParent)
    list:SetSize(ROW_W + PAD * 2, MIN_H)
    -- DeckKit's window look, as on the dictation box: Forever's thin metal edge on a dark fill.
    local fill = list:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(0.035, 0.035, 0.045, 0.9)
    DeckKit.UI.Border(list, "SimplePanelTemplate")
    list:SetFrameStrata(f:GetFrameStrata())
    list:Hide()
    -- The View button on the middle of the bottom edge: the game's own "View to focus" hint (its
    -- template, as on its window: the button's icon with a drop shadow).
    if not pcall(CreateFrame, "Frame", nil, list, "FrameFocusJumpHintTemplate") then
        local glyph = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        glyph:SetPoint("CENTER", list, "BOTTOM", 0, 4)
        glyph:SetText(ns.Window.Glyph("VIEW", 28))
    end

    -- While the game's window is up: follow its rolls and its focus.
    local driver = CreateFrame("Frame")
    driver:Hide()
    local wait = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.05
        Update()
    end)
    f:HookScript("OnShow", function() driver:Show(); Update() end)
    f:HookScript("OnHide", function() driver:Hide(); Update() end)
    if f:IsShown() then driver:Show() end
    Place()
    Update()
end

-- After Edit Mode has placed the XP bar.
ns.On("PLAYER_LOGIN", function() C_Timer.After(1, function() Build(); Place() end) end)
ns.On("EDIT_MODE_LAYOUTS_UPDATED", function() C_Timer.After(0, Place) end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Loot rolls", order = 6 },
    { type = "toggle", label = "Loot rolls in the top-left corner",
      hint = "Need / Greed / Pass shows in the top-left corner, under the XP bar, instead of over the chat.",
      get = TopLeft,
      set = function(on) ns.db.lootRollsTopLeft = on; Place() end },
    { type = "toggle", label = "Compact until you press {VIEW}",
      hint = "Just the items' names, in their quality colors, and the time left. "
          .. "{VIEW} brings up the game's window to roll.",
      get = Compact,
      set = function(on) ns.db.lootRollsCompact = on; if list then Update() end end },
    { type = "choice", label = "Compact: time left",
      values = { { "line", "Thin bar" }, { "seconds", "Seconds" }, { "behind", "Bar behind the name" } },
      hint = "How each item in the compact list shows the time left to roll.",
      get = TimerStyle,
      set = function(v) ns.db.lootRollsTimer = v; if list then Update() end end },
    { type = "range", label = "Compact: opacity",
      min = 0.2, max = 1, step = 0.1, format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
      hint = "How solid the compact list is. The game's window ({VIEW}) always shows at full.",
      get = ListAlpha,
      set = function(v) ns.db.lootRollsAlpha = v; if list then Update() end end },
})
