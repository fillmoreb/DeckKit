-- DeckKit UI: the shared look and controller behavior for DeckKit windows.
--
-- Built to behave like Forever's own gamepad windows:
--   * The cursor is the game's own pointer (SmartNavigationPointerTemplate: the white chevron with
--     its bob and intro animation), sitting at the left edge of the focused control.
--   * The d-pad moves like the game's: to the nearest control inside a 45 degree cone in that
--     direction, no wrapping.
--   * A activates, B goes back (closes a list, cancels a bind, then closes the window), LB/RB
--     switch tabs. The footer always lists what each button does for the focused control.
-- We only borrow the game's art and templates. Navigation and input stay ours (DeckKit.Input),
-- because opening a Blizzard SmartNavigation panel from addon code changes the gamepad binding
-- stack and trips protected calls (see CLAUDE.md).
--
-- States, the same everywhere:
--   normal    plain
--   focused   chevron + the control's highlight held on (focus is never shown any other way)
--   pressed   a short pushed flash on A
--   disabled  gray; still focusable, the footer says why instead of offering A
--   selected  gold: a ticked box, a lit switch side, a check in a list, the gold action-button
--             glow on an icon. Never the chevron, so focus and selection can't be confused.
local _, ns = ...

local UI = {}
ns.UI = UI

-- The game's glyph atlases have padding, so they're drawn larger than the text around them.
local GLYPH = 26
local Glyph = function(key, size) return ns.Window.Glyph(key, size or GLYPH) end

------------------------------------------------------------------------
-- Fonts: the game's own faces, a little larger for the Deck's 7" screen
------------------------------------------------------------------------

local function MakeFont(name, base, size)
    local font = CreateFont(name)
    font:CopyFontObject(base)
    local path, _, flags = base:GetFont()
    if path then font:SetFont(path, size, flags) end
    return font
end

UI.Font = {
    title = MakeFont("DeckKitFontTitle", GameFontNormalLarge, 18),     -- gold
    heading = MakeFont("DeckKitFontHeading", GameFontNormal, 15),      -- gold
    body = MakeFont("DeckKitFontBody", GameFontHighlight, 14),         -- white
    dim = MakeFont("DeckKitFontDim", GameFontDisable, 14),             -- gray
    small = MakeFont("DeckKitFontSmall", GameFontHighlightSmall, 12),  -- white, small
    smallDim = MakeFont("DeckKitFontSmallDim", GameFontDisableSmall, 12),
}

UI.Color = {
    gold = { 1, 0.82, 0 },
    good = { 0.37, 0.83, 0.37 },
    bad = { 0.9, 0.33, 0.33 },
    dim = { 0.55, 0.55, 0.55 },
}
local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
UI.Hex = Hex

------------------------------------------------------------------------
-- Frame art
------------------------------------------------------------------------

-- Forever's metal borders (NineSliceLayouts): "SimplePanelTemplate" is the thin one used for
-- windows here, "InsetFrameTemplate" the recessed one for groups inside them.
local function Border(frame, layout)
    if NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.GetLayout(layout) then
        if pcall(NineSliceUtil.ApplyLayoutByName, frame, layout) then return true end
    end
    -- No layout: a plain thin edge.
    local edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    edge:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    return false
end
UI.Border = Border

local function Fill(frame, r, g, b, a, inset)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    t:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Line(parent, r, g, b, a, height)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(height or 1)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

------------------------------------------------------------------------
-- The cursor
------------------------------------------------------------------------

-- The game's own gamepad chevron (SmartNavigationPointerTemplate, or a look-alike), for any DeckKit
-- control or one a module adds to a Blizzard frame (PackPad's broom). UI.PlacePointer puts it on one.
local function MakePointer(parent)
    local ok, p = pcall(CreateFrame, "Frame", nil, parent, "SmartNavigationPointerTemplate")
    if not (ok and p and p.Icon) then
        p = CreateFrame("Frame", nil, parent)
        p:SetSize(10, 10)
        p.Icon = CreateFrame("Frame", nil, p)
        p.Icon:SetAllPoints()
        local t = p.Icon:CreateTexture(nil, "ARTWORK")
        if not t:SetAtlas("gamepad-largecursor-white", true) then t:SetColorTexture(1, 1, 1, 1); t:SetSize(20, 32) end
        t:SetScale(0.8)
        t:SetPoint("LEFT")
        p.Icon.Cursor = t
    end
    p.Icon:SetFrameStrata("FULLSCREEN_DIALOG")
    p:Hide()
    return p
end

-- The chevron is 56 px tall at the game's size; on small controls it's scaled to fit.
local CURSOR_H, CURSOR_W = 56, 34
local function PlacePointer(p, target)
    local h = target:GetHeight() or 30
    local scale = math.max(0.45, math.min(1, h * 1.25 / CURSOR_H))
    p:SetScale(scale)
    p:ClearAllPoints()
    -- The tip overlaps the control's left edge a little, like the game's.
    -- (offsets are in the pointer's own scaled units)
    p:SetPoint("LEFT", target, "LEFT", -(CURSOR_W - 8), 0)
    p:Show()
end
UI.MakePointer, UI.PlacePointer = MakePointer, PlacePointer

------------------------------------------------------------------------
-- The window ("screen"): title, tabs, body, footer with button prompts
------------------------------------------------------------------------

local Screen = {}
Screen.__index = Screen

local ScrollOf -- (defined with the scrolling list below)

-- Focus leaving a control: its highlight off, and its onBlur (a tooltip or peek it opened goes away).
local function Blur(old)
    if old.UnlockHighlight then old:UnlockHighlight() end
    if old.dk and old.dk.onBlur then old.dk.onBlur(old) end
end

local TAB_H, FOOTER_H, PAD = 30, 34, 14
-- The footer legend, after Blizzard's (InputLegendPromptGroup.lua): 10 px inside the slot, 15 between
-- prompts, glyphs drawn 24 px (ours a little bigger: their atlases have padding).
local LEGEND_H, LEGEND_PAD, LEGEND_GAP, LEGEND_GLYPH = 32, 10, 15, 26
-- The game's order, left to right, whatever order a control lists them in.
local LEGEND_ORDER = { A = 1, X = 2, Y = 3, DPAD_LR = 4, DPAD_UD = 5, DPAD = 6, LB = 13, RB = 14, LT = 20, RT = 21, B = 99 }

local PAD_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD1", "PAD2", "PAD3", "PAD4",
    "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER", "PADFORWARD" }

-- Glyph names for pad keys (for binding controls).
UI.KeyGlyph = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
    PADLTRIGGER = "LT", PADRTRIGGER = "RT", PADDUP = "DUP", PADDDOWN = "DDOWN", PADDLEFT = "DLEFT",
    PADDRIGHT = "DRIGHT", PADFORWARD = "MENU", PADLSTICK = "L3", PADRSTICK = "R3" }
-- The Deck's back grips reach the game as their held keys (ns.GRIPS, DeckKit's Steam layout).
for _, g in ipairs(ns.GRIPS) do
    table.insert(PAD_KEYS, g.key)
    UI.KeyGlyph[g.key] = g.name
end

local screens = {} -- every DeckKit screen made so far

-- Every DeckKit screen made so far (for tests: AddonTools' harness finds a window's screen here).
function UI.Screens() return screens end

-- True while any DeckKit screen (the menu, a module's window) is open: it has the pad then, whatever
-- the game's own gamepad focus says.
function UI.AnyScreenShown()
    for _, s in ipairs(screens) do
        if s.win:IsShown() then return true end
    end
    return false
end

function UI.NewScreen(name, width, height, title)
    local s = setmetatable({ tabs = {}, tab = 1, mode = nil }, Screen)
    screens[#screens + 1] = s

    local win = CreateFrame("Frame", name, UIParent)
    win:SetSize(width, height)
    win:SetPoint("CENTER", 0, 30)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    Fill(win, 0.035, 0.035, 0.045, 0.96, 2)
    Border(win, "SimplePanelTemplate")
    s.win = win

    s.title = Text(win, UI.Font.title, "CENTER")
    s.title:SetPoint("TOP", 0, -12)
    s.title:SetText(title)

    -- Tab strip: LB [tab] [tab] [tab] RB, the active one gold and underlined.
    local strip = CreateFrame("Frame", nil, win)
    strip:SetPoint("TOPLEFT", PAD, -36)
    strip:SetPoint("TOPRIGHT", -PAD, -36)
    strip:SetHeight(TAB_H)
    local rule = Line(strip, 0.45, 0.42, 0.35, 0.8)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    s.strip = strip
    s.lb = Text(strip, UI.Font.body, "CENTER")
    s.rb = Text(strip, UI.Font.body, "CENTER")

    -- How much taller a screen is than its tab body (title, tab strip, footer): for sizing a window to
    -- its content (Layout.lua's UI.ShowLayout).
    UI.SCREEN_CHROME = 36 + TAB_H + 10 + FOOTER_H + 8
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", PAD, -36 - TAB_H - 10)
    body:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 8)
    s.body = body

    -- Footer: what the buttons do right now, as the game's own gamepad windows show it (Blizzard's
    -- input legend: the footer slot with each button's glyph and its gold label, in the game's button
    -- order). Left of it: why the focused control is unavailable, when it is.
    local footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", 2, 2)
    footer:SetPoint("BOTTOMRIGHT", -2, 2)
    footer:SetHeight(FOOTER_H)
    s.footerLeft = Text(footer, UI.Font.small)
    s.footerLeft:SetPoint("LEFT", PAD, 0)
    local legend = CreateFrame("Frame", nil, footer)
    legend:SetPoint("RIGHT", -6, 2)
    legend:SetHeight(LEGEND_H)
    legend.bg = legend:CreateTexture(nil, "BACKGROUND")
    legend.bg:SetAllPoints()
    if not legend.bg:SetAtlas("gamepad-footer-slot-bg") then legend.bg:SetColorTexture(0, 0, 0, 0.55) end
    legend.border = legend:CreateTexture(nil, "BORDER")
    legend.border:SetAllPoints()
    legend.border:SetAtlas("gamepad-footer-slot-frameneutral")
    legend.items = {}
    s.legend = legend
    s.footer = footer

    s.pointer = MakePointer(win)

    -- The right stick scrolls the list the cursor is in (or the tab's first list).
    local stickY, DEADZONE = 0, 0.2
    ns.TakeSticks(win, function(y) stickY = y end)
    win:HookScript("OnUpdate", function(_, elapsed)
        if math.abs(stickY) < DEADZONE then return end
        s:StickScroll(stickY, elapsed)
    end)

    local handlers = {}
    for _, key in ipairs(PAD_KEYS) do handlers[key] = function() s:Key(key) end end
    s.input = ns.Input.New(win, handlers, { release = function(key) s:KeyUp(key) end })

    win:HookScript("OnShow", function()
        ns.Window.Sound(true)
        s:SelectTab(s.tab, true)
    end)
    win:HookScript("OnHide", function()
        ns.Window.Sound(false)
        s:ClosePopup()
        -- Closed mid-typing: the text box lets go of the keyboard (and keeps what was there).
        if s.mode == "text" and s.capture and s.capture.dk.finish then s.capture.dk.finish(s.capture, false) end
        if s.mode == "edit" and s.capture and s.capture.dk.edit then s.capture.dk.edit(s.capture, "PAD2") end
        s:EndEdit()
        s.mode, s.capture = nil, nil
        s.pointer:Hide()
        local f = s:Focused()
        if f and f.dk and f.dk.onBlur then f.dk.onBlur(f) end
    end)
    return s
end

function Screen:FindScroll()
    local f = self:Focused()
    local sf = ScrollOf(f)
    if sf then return sf end
    for _, item in ipairs(self:Focusables()) do
        sf = ScrollOf(item)
        if sf then return sf end
    end
end

function Screen:StickScroll(y, elapsed)
    if self.popup and self.popup:IsShown() then return end
    local sf = self:FindScroll()
    if not (sf and sf:MaxScroll() > 0) then return end
    -- Pixels per second grows with how far the stick is pushed (up = towards the top).
    local speed = 120 + 900 * ((math.abs(y) - 0.2) / 0.8) ^ 2
    sf:ScrollTo(sf:GetVerticalScroll() + (y > 0 and -1 or 1) * speed * elapsed)
    -- Keep the cursor on a row you can see.
    local cur = self:Focused()
    if cur and ScrollOf(cur) == sf and not sf:InView(cur) then
        local best, bestD
        local _, cy = cur:GetCenter()
        for _, f in ipairs(self:Focusables()) do
            if ScrollOf(f) == sf and sf:InView(f) then
                local _, fy = f:GetCenter()
                local d = math.abs(fy - cy)
                if not bestD or d < bestD then best, bestD = f, d end
            end
        end
        if best then
            local old = self.tabs[self.tab].focus
            if old then Blur(old) end
            self.tabs[self.tab].focus = best
            best:LockHighlight()
            PlacePointer(self.pointer, best)
            if best.dk and best.dk.onFocus then best.dk.onFocus(best) end
            self:UpdatePrompts()
        end
    elseif cur and ScrollOf(cur) == sf then
        PlacePointer(self.pointer, cur)
    end
end

function Screen:Show()
    if InCombatLockdown() then ns.Print("DeckKit windows can't open in combat.") return end
    self.win:Show()
end
function Screen:Hide() self.win:Hide() end
function Screen:Toggle() if self.win:IsShown() then self:Hide() else self:Show() end end

-- A tab: a content frame filling the body. Controls made under it register with it.
function Screen:AddTab(title)
    local frame = CreateFrame("Frame", nil, self.body)
    frame:SetAllPoints()
    frame:Hide()
    local tab = { title = title, frame = frame, items = {}, screen = self }
    frame.dkTab = tab
    tab.label = Text(self.strip, UI.Font.heading, "CENTER")
    tab.underline = Line(self.strip, 1, 0.82, 0, 1, 2)
    table.insert(self.tabs, tab)
    self:LayoutTabs()
    return tab
end

function Screen:LayoutTabs()
    local n = #self.tabs
    self.lb:SetText(n > 1 and Glyph("LB", 30) or "")
    self.rb:SetText(n > 1 and Glyph("RB", 30) or "")
    self.lb:SetPoint("LEFT", 4, 0)
    self.rb:SetPoint("RIGHT", -4, 0)
    local prev
    local widths, total = {}, 0
    for i, tab in ipairs(self.tabs) do
        tab.label:SetText(tab.title)
        widths[i] = tab.label:GetStringWidth() + 36
        total = total + widths[i]
    end
    local x = -total / 2
    for i, tab in ipairs(self.tabs) do
        tab.label:ClearAllPoints()
        tab.label:SetPoint("CENTER", self.strip, "CENTER", x + widths[i] / 2, 1)
        tab.underline:ClearAllPoints()
        tab.underline:SetPoint("BOTTOM", tab.label, "BOTTOM", 0, -8)
        tab.underline:SetWidth(widths[i] - 16)
        x = x + widths[i]
    end
end

function Screen:SelectTab(i, quiet)
    if not self.tabs[i] then return end
    self:ClosePopup()
    local was = self.tabs[self.tab] and self.tabs[self.tab].focus
    if was and i ~= self.tab then Blur(was) end
    self.mode, self.capture = nil, nil
    self.tab = i
    for j, tab in ipairs(self.tabs) do
        local on = j == i
        tab.frame:SetShown(on)
        tab.label:SetFontObject(on and UI.Font.heading or UI.Font.dim)
        tab.underline:SetShown(on)
    end
    if not quiet then ns.Window.Tick() end
    local tab = self.tabs[i]
    if tab.onShow then tab.onShow(tab) end
    -- Settings can change while the screen is closed (a grip chord toggling the cheat sheet, say):
    -- every control shows its current value before anything is focused.
    self:Refresh()
    -- Keep the tab's last focus, or start at its first control.
    local f = tab.focus
    if not (f and f:IsVisible()) then f = self:Focusables()[1] end
    self:SetFocus(f, true)
end

function Screen:Focusables()
    local list = {}
    for _, f in ipairs(self.tabs[self.tab].items) do
        if f:IsVisible() then list[#list + 1] = f end
    end
    return list
end

function Screen:Focused()
    if self.popup and self.popup:IsShown() then return self.popup.focus end
    return self.tabs[self.tab] and self.tabs[self.tab].focus
end

function Screen:SetFocus(f, intro)
    local old = self:Focused()
    if old and old ~= f then Blur(old) end
    if self.popup and self.popup:IsShown() then self.popup.focus = f else self.tabs[self.tab].focus = f end
    if f then
        local sf = ScrollOf(f)
        if sf then sf:Reveal(f) end
        if f.LockHighlight then f:LockHighlight() end
        PlacePointer(self.pointer, f)
        if intro and self.pointer.IntroAnim then self.pointer.IntroAnim:Play() end
        if f.dk and f.dk.onFocus then f.dk.onFocus(f) end
    else
        self.pointer:Hide()
    end
    self:UpdatePrompts()
end

-- The game's rule: the nearest control whose center is inside a 45 degree cone that way (nearest counting
-- sideways distance double, so a control in line wins).
function Screen:Move(dir)
    local cur = self:Focused()
    local list = (self.popup and self.popup:IsShown()) and self.popup.items or self:Focusables()
    if not cur then
        if list[1] then self:SetFocus(list[1]) end
        return
    end
    local cx, cy = cur:GetCenter()
    local best, bestD
    for _, f in ipairs(list) do
        local sf = ScrollOf(f)
        local reachable = not sf or sf == ScrollOf(cur) or sf:InView(f)
        if f ~= cur and f:IsVisible() and reachable then
            local x, y = f:GetCenter()
            local dx, dy = x - cx, y - cy
            local along, across
            if dir == "PADDRIGHT" then along, across = dx, dy
            elseif dir == "PADDLEFT" then along, across = -dx, dy
            elseif dir == "PADDUP" then along, across = dy, dx
            else along, across = -dy, dx end
            if along > 1 and math.abs(across) <= along then
                -- Nearest, with sideways counted double: the control in line wins over one off to the side
                -- whose centre happens to be close (a full-width row's centre, next to a table's cells).
                local d = along + 2 * math.abs(across)
                if not bestD or d < bestD then best, bestD = f, d end
            end
        end
    end
    if best then self:SetFocus(best) end
end

local function Press(f)
    if f.press then
        f.press:Show()
        C_Timer.After(0.12, function() f.press:Hide() end)
    elseif f.SetButtonState then
        f:SetButtonState("PUSHED")
        C_Timer.After(0.12, function() if f:IsEnabled() then f:SetButtonState("NORMAL") end end)
    end
end
UI.Press = Press

local function IsDisabled(f)
    local d = f.dk and f.dk.disabled
    if type(d) == "function" then d = d(f) end
    return d
end
UI.IsDisabled = IsDisabled

function Screen:Key(key)
    -- A control being edited in place (a popover stepper): every press is its own until it says it's done.
    if self.mode == "edit" then
        local f = self.capture
        local result = f and f.dk.edit and f.dk.edit(f, key)
        if result == "done" or result == "cancel" or not f then self:EndEdit() end
        if result then ns.Window.Tick() end
        self:Refresh()
        return
    end
    -- Typing in a text box: A keeps the text, B puts back what was there; the keyboard (the Deck's on-screen one,
    -- a real one, dictation) types. Nothing else moves the cursor until it's done.
    if self.mode == "text" then
        local f = self.capture
        if key == "PAD1" or key == "PAD2" then
            self.mode, self.capture = nil, nil
            if f and f.dk.finish then f.dk.finish(f, key == "PAD1") end
            ns.Window.Tick()
            self:Refresh()
        end
        return
    end
    -- A question on a control ("replace that binding?"): A yes, B no.
    if self.mode == "confirm" then
        if key ~= "PAD1" and key ~= "PAD2" then return end
        local f, yes = self.capture, key == "PAD1"
        self.mode, self.capture = nil, nil
        if f and f.dk.confirmed then f.dk.confirmed(f, yes) end
        ns.Window.Tick()
        self:Refresh()
        return
    end
    -- Binding capture: the next button is the binding; B cancels.
    if self.mode == "capture" then
        local f = self.capture
        self.mode, self.capture = nil, nil
        if key ~= "PAD2" and f and f.dk.captured then f.dk.captured(f, key) end
        if self.mode == "confirm" then self:UpdatePrompts() return end
        if f and f.dk.onFocus then f.dk.onFocus(f) end
        ns.Window.Tick()
        self:Refresh()
        return
    end
    if key == "PADDLEFT" or key == "PADDRIGHT" or key == "PADDUP" or key == "PADDDOWN" then
        -- Steppers and choices take left/right themselves, dials up/down too. A control's handler
        -- returns false when it doesn't use that press (a dial's last digit): the cursor moves on.
        local f = self:Focused()
        local name = ({ PADDLEFT = "left", PADDRIGHT = "right", PADDUP = "up", PADDDOWN = "down" })[key]
        local fn = f and f.dk and not IsDisabled(f) and f.dk[name]
        if fn and fn(f) ~= false then
            ns.Window.Tick()
            self:Refresh()
            return
        end
    end
    if key == "PADDUP" or key == "PADDDOWN" or key == "PADDLEFT" or key == "PADDRIGHT" then
        self:Move(key)
        return
    end
    if key == "PADLSHOULDER" or key == "PADRSHOULDER" then
        if self.popup and self.popup:IsShown() then
            if self.popup.onShoulder then
                self.popup.onShoulder(key == "PADRSHOULDER" and 1 or -1)
                ns.Window.Tick()
            end
            return
        end
        local n = #self.tabs
        if n > 1 then self:SelectTab((self.tab - 1 + (key == "PADRSHOULDER" and 1 or -1)) % n + 1) end
        return
    end
    if key == "PAD2" or key == "PADFORWARD" then
        if self.popup and self.popup:IsShown() then self:ClosePopup() return end
        -- A screen with places to go back from (a category drilled into, a detail view) says so: B goes back there
        -- first, and only closes the window from the top.
        if key == "PAD2" and self.OnBack and self:OnBack() then ns.Window.Tick() self:Refresh() return end
        -- The player closed it (not combat or another window): screens that care set OnPlayerClose.
        if self.OnPlayerClose then self:OnPlayerClose() end
        self:Hide()
        return
    end
    local f = self:Focused()
    if not (f and f.dk) or IsDisabled(f) then return end
    local action = (key == "PAD1" and f.dk.activate) or (key == "PAD3" and f.dk.x) or (key == "PAD4" and f.dk.y)
    if action then
        Press(f)
        action(f)
        if self.win:IsShown() then self:Refresh() end
    end
end

-- Lays the legend out: prompts = { {key, label, glyphs = markup or nil}, ... }, sorted into the game's order.
function Screen:SetLegend(prompts)
    local legend = self.legend
    for i, p in ipairs(prompts) do p.i = i end
    table.sort(prompts, function(a, b)
        local oa, ob = LEGEND_ORDER[a[1]] or 50, LEGEND_ORDER[b[1]] or 50
        if oa ~= ob then return oa < ob end
        return a.i < b.i
    end)
    local x = LEGEND_PAD
    for i, p in ipairs(prompts) do
        local fs = legend.items[i]
        if not fs then
            fs = Text(legend, UI.Font.heading)
            legend.items[i] = fs
        end
        local glyphs = p.glyphs or (p[1] and Glyph(p[1], LEGEND_GLYPH))
        fs:SetText((glyphs and (glyphs .. " ") or "") .. p[2])
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", legend, "LEFT", x, 0)
        fs:Show()
        x = x + fs:GetStringWidth() + LEGEND_GAP
    end
    for i = #prompts + 1, #legend.items do legend.items[i]:Hide() end
    legend:SetWidth(x - LEGEND_GAP + LEGEND_PAD)
end

-- A button let go: a control's hold-to-see (dk.release = { y = fn }) ends.
function Screen:KeyUp(key)
    local name = ({ PAD1 = "a", PAD3 = "x", PAD4 = "y" })[key]
    local f = self:Focused()
    local fn = name and f and f.dk and f.dk.release and f.dk.release[name]
    if fn then fn(f) end
end

-- Footer prompts for the focused control. Each control's dk.prompts returns
-- { {"A", "Toggle"}, {"X", "Clear"} }; B and LB/RB are added here.
function Screen:UpdatePrompts()
    local parts = {}
    local left = ""
    if self.mode == "edit" and self.capture and self.capture.dk.editPrompts then
        for _, p in ipairs(self.capture.dk.editPrompts(self.capture)) do parts[#parts + 1] = p end
    elseif self.mode == "edit" then
        parts[#parts + 1] = { "DPAD", "Change", glyphs = Glyph("DPAD_UD", LEGEND_GLYPH) }
        parts[#parts + 1] = { "LT", "x10", glyphs = Glyph("LT", LEGEND_GLYPH) .. Glyph("RT", LEGEND_GLYPH) }
        parts[#parts + 1] = { "A", "Done" }
        parts[#parts + 1] = { "B", "Cancel" }
    elseif self.mode == "text" then
        parts[#parts + 1] = { nil, Hex(UI.Color.gold) .. "Type (Steam + X: keyboard)" .. "|r" }
        parts[#parts + 1] = { "A", "Done" }
        parts[#parts + 1] = { "B", "Cancel" }
    elseif self.mode == "capture" then
        parts[#parts + 1] = { nil, Hex(UI.Color.gold) .. (self.capture and self.capture.dk.captureText or "Press a button") .. "|r" }
        parts[#parts + 1] = { "B", "Cancel" }
    elseif self.mode == "confirm" then
        parts[#parts + 1] = { "A", self.capture and self.capture.dk.confirmText or "Yes" }
        parts[#parts + 1] = { "B", "Cancel" }
    else
        local f = self:Focused()
        if f and f.dk then
            if IsDisabled(f) then
                local why = f.dk.reason
                if type(why) == "function" then why = why(f) end
                left = Hex(UI.Color.dim) .. (why or "Unavailable") .. "|r"
            elseif f.dk.prompts then
                for _, p in ipairs(f.dk.prompts(f)) do parts[#parts + 1] = { p[1], p[2] } end
            end
        end
        local inPopup = self.popup and self.popup:IsShown()
        local back = not inPopup and self.BackLabel and self:BackLabel()
        parts[#parts + 1] = { "B", inPopup and "Cancel" or back or "Close" }
        if inPopup and self.popup.onShoulder then
            parts[#parts + 1] = { "LB", self.popup.shoulderText or "Tabs",
                glyphs = Glyph("LB", LEGEND_GLYPH) .. Glyph("RB", LEGEND_GLYPH) }
        end
        if #self.tabs > 1 and not inPopup then
            parts[#parts + 1] = { "LB", "Tabs", glyphs = Glyph("LB", LEGEND_GLYPH) .. Glyph("RB", LEGEND_GLYPH) }
        end
    end
    self:SetLegend(parts)
    self.footerLeft:SetText(left)
end

------------------------------------------------------------------------
-- Building blocks. Controls register with the tab they're created under.
------------------------------------------------------------------------

local function TabOf(frame)
    while frame do
        if frame.dkTab then return frame.dkTab end
        frame = frame:GetParent()
    end
end

local function Register(f, spec)
    f.dk = spec
    -- Controller only: the hidden mouse pointer must not light controls up by hovering.
    f:EnableMouse(false)
    local tab = TabOf(f:GetParent())
    if tab then table.insert(tab.items, f) end
    if spec.refresh then spec.refresh(f) end
    return f
end
UI.Register = Register

-- Takes a control out of its tab's focus order (Layout.lua, rebuilding a display in place).
function UI.Unregister(f)
    local tab = TabOf(f:GetParent())
    if not tab then return end
    for i = #tab.items, 1, -1 do
        if tab.items[i] == f then table.remove(tab.items, i) end
    end
    if tab.focus == f then tab.focus = nil end
end

-- A recessed group with a gold heading. Content goes below panel.top (y offset from TOPLEFT).
function UI.Panel(parent, title)
    local p = CreateFrame("Frame", nil, parent)
    Fill(p, 0, 0, 0, 0.35, 2)
    Border(p, "InsetFrameTemplate")
    p.top = -10
    if title then
        p.heading = Text(p, UI.Font.heading)
        p.heading:SetPoint("TOPLEFT", 12, -10)
        p.heading:SetText(title)
        p.top = -34
    end
    return p
end

-- Non-focusable text: headings, descriptions, status readouts.
function UI.Heading(parent, text)
    local fs = Text(parent, UI.Font.heading)
    fs:SetText(text)
    return fs
end

function UI.Description(parent, text, width)
    local fs = Text(parent, UI.Font.dim)
    fs:SetWordWrap(true)
    fs:SetWidth(width)
    fs:SetText(ns.Window.Glyphs(text))
    return fs
end

-- "Label ........ value", value colored by state (good / bad / gold / nil = white).
function UI.Status(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 22)
    f.label = Text(f, UI.Font.dim)
    f.label:SetPoint("LEFT")
    f.value = Text(f, UI.Font.body, "RIGHT")
    f.value:SetPoint("RIGHT")
    function f:Set(label, value, color)
        self.label:SetText(label)
        self.value:SetText((color and Hex(color) or "") .. ns.Window.Glyphs(tostring(value)) .. (color and "|r" or ""))
    end
    return f
end

-- Row controls: a full-width line, label on the left, its control on the right. Focus holds the
-- row's highlight on (the game's quest-list highlight) under the chevron.
local ROW_H = 30
UI.ROW_H = ROW_H

local function Row(parent, width, label)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(width, ROW_H)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)
    f:SetHighlightTexture(hl)
    f.press = f:CreateTexture(nil, "OVERLAY")
    f.press:SetAllPoints()
    f.press:SetColorTexture(0, 0, 0, 0.35)
    f.press:Hide()
    f.label = Text(f, UI.Font.body)
    f.label:SetPoint("LEFT", 10, 0)
    -- A label can be a function, for a row that names something that changes (re-read on refresh).
    if type(label) == "function" then f.labelFn = label end
    f.label:SetText(ns.Window.Glyphs(f.labelFn and f.labelFn() or label or ""))
    return f
end

local function RowEnabled(f)
    local off = IsDisabled(f)
    if f.labelFn then f.label:SetText(ns.Window.Glyphs(f.labelFn() or "")) end
    f.label:SetFontObject(off and UI.Font.dim or UI.Font.body)
    return not off
end

-- Checkbox: the game's check box at the right. Selected = ticked.
function UI.Checkbox(parent, width, opts)
    local f = Row(parent, width, opts.label)
    f.box = f:CreateTexture(nil, "ARTWORK")
    f.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    f.box:SetSize(26, 26)
    f.box:SetPoint("RIGHT", -6, 0)
    f.check = f:CreateTexture(nil, "OVERLAY")
    f.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.check:SetAllPoints(f.box)
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "A", opts.get() and "Turn off" or "Turn on" } } end,
        activate = function() opts.set(not opts.get()) end,
        refresh = function(self)
            local on = RowEnabled(self)
            self.check:SetShown(opts.get())
            self.check:SetDesaturated(not on)
            self.box:SetDesaturated(not on)
        end,
    })
end

-- Switch: two sides, the chosen one lit gold. For a setting with two named states.
function UI.Switch(parent, width, opts)
    local f = Row(parent, width, opts.label)
    local sideW = 54
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(sideW * 2, 22)
    box:SetPoint("RIGHT", -6, 0)
    Fill(box, 0, 0, 0, 0.6)
    local edge = CreateFrame("Frame", nil, box, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    edge:SetBackdropBorderColor(0.45, 0.42, 0.35, 1)
    f.sides = {}
    for i, name in ipairs({ opts.off or "Off", opts.on or "On" }) do
        local lit = box:CreateTexture(nil, "ARTWORK")
        lit:SetColorTexture(1, 0.82, 0, 0.28)
        lit:SetSize(sideW - 2, 20)
        lit:SetPoint("LEFT", 1 + (i - 1) * sideW, 0)
        local t = Text(box, UI.Font.small, "CENTER")
        t:SetPoint("CENTER", lit)
        t:SetText(name)
        f.sides[i] = { lit = lit, text = t }
    end
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "A", "Switch to " .. (opts.get() and (opts.off or "Off") or (opts.on or "On")) } } end,
        activate = function() opts.set(not opts.get()) end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            local cur = opts.get() and 2 or 1
            for i, side in ipairs(self.sides) do
                side.lit:SetShown(i == cur and enabled)
                side.text:SetFontObject(i == cur and (enabled and UI.Font.small or UI.Font.smallDim) or UI.Font.smallDim)
                if i == cur and enabled then side.text:SetTextColor(1, 0.82, 0) end
            end
        end,
    })
end

local function Cycle(values, cur, d)
    local n, at = #values, 1
    for i, c in ipairs(values) do if c[1] == cur then at = i end end
    return values[(at - 1 + d) % n + 1][1]
end

-- Selector: shows the current choice in a box; A opens the list (a popup over the window).
-- opts.values = { { value, "Text" }, ... }
function UI.Selector(parent, width, opts)
    local f = Row(parent, width, opts.label)
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(opts.boxWidth or 150, 22)
    box:SetPoint("RIGHT", -6, 0)
    Fill(box, 0, 0, 0, 0.6)
    local edge = CreateFrame("Frame", nil, box, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    edge:SetBackdropBorderColor(0.45, 0.42, 0.35, 1)
    f.value = Text(box, UI.Font.small)
    f.value:SetPoint("LEFT", 8, 0)
    f.value:SetPoint("RIGHT", -20, 0)
    f.arrow = box:CreateTexture(nil, "ARTWORK")
    f.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    f.arrow:SetSize(14, 14)
    f.arrow:SetPoint("RIGHT", -4, -3)
    f.box = box
    local function TextOf(v)
        for _, c in ipairs(opts.values) do if c[1] == v then return c[2] end end
        return tostring(v)
    end
    -- opts.listOnly: left/right move the cursor past it (it sits beside other controls); A opens its list.
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function()
            if opts.listOnly then return { { "A", "Choose" } } end
            return { { "DPAD_LR", "Change" }, { "A", "Choose" } }
        end,
        left = not opts.listOnly and function() opts.set(Cycle(opts.values, opts.get(), -1)) end or nil,
        right = not opts.listOnly and function() opts.set(Cycle(opts.values, opts.get(), 1)) end or nil,
        activate = function(self)
            local screen = TabOf(self).screen
            screen:OpenList(self, opts.values, opts.get(), opts.set)
        end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            self.value:SetText(TextOf(opts.get()))
            self.value:SetFontObject(enabled and UI.Font.small or UI.Font.smallDim)
            self.arrow:SetDesaturated(not enabled)
        end,
    })
end

-- Text box: a line of text you type. A starts typing (the Deck's on-screen keyboard is Steam + X; a real keyboard or
-- dictation types too), A or Enter keeps it, B or Escape puts back what was there. opts: label, get() -> text,
-- set(text), placeholder (shown dim while empty), boxWidth, maxLetters, enter(text) (run after a kept edit: a
-- search box searches). An assistant can fill the one under the cursor without typing (UI.ActiveTextBox).
function UI.TextBox(parent, width, opts)
    local f = Row(parent, width, opts.label)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetSize(opts.boxWidth or 260, 22)
    eb:SetPoint("RIGHT", -6, 0)
    eb:SetAutoFocus(false)
    eb:SetFontObject(UI.Font.small)
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetMaxLetters(opts.maxLetters or 80)
    eb:EnableMouse(false)
    Fill(eb, 0, 0, 0, 0.6)
    local edge = CreateFrame("Frame", nil, eb, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    edge:SetBackdropBorderColor(0.45, 0.42, 0.35, 1)
    f.edge = edge
    f.hint = Text(eb, UI.Font.smallDim)
    f.hint:SetPoint("LEFT", 8, 0)
    f.box = eb
    local function Finish(keep)
        if not f.editing then return end
        f.editing = false
        local text = eb:GetText() or ""
        eb:ClearFocus()
        edge:SetBackdropBorderColor(0.45, 0.42, 0.35, 1)
        if keep then
            opts.set(text)
            if opts.enter then opts.enter(text) end
        end
        f.dk.refresh(f)
    end
    -- Enter and Escape from the keyboard end it the same as A and B (the screen leaves its typing mode too).
    local function FromKeyboard(keep)
        local screen = TabOf(f).screen
        if screen.mode == "text" and screen.capture == f then
            screen.mode, screen.capture = nil, nil
            Finish(keep)
            screen:Refresh()
        else
            Finish(keep)
        end
    end
    eb:SetScript("OnEnterPressed", function() FromKeyboard(true) end)
    eb:SetScript("OnEscapePressed", function() FromKeyboard(false) end)
    eb:SetScript("OnTextChanged", function(self) f.hint:SetShown((self:GetText() or "") == "") end)
    f.textbox = { label = opts.label, get = opts.get,
        fill = function(text, run)
            opts.set(text)
            f.dk.refresh(f)
            if run and opts.enter then opts.enter(text) end
        end }
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "A", "Type" } } end,
        activate = function(self)
            local screen = TabOf(self).screen
            self.editing = true
            eb:SetText(opts.get() or "")
            eb:SetFocus()
            eb:HighlightText()
            edge:SetBackdropBorderColor(1, 0.82, 0, 1)
            screen.mode, screen.capture = "text", self
        end,
        finish = function(_, keep) Finish(keep) end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            if not self.editing then eb:SetText(opts.get() or "") end
            f.hint:SetText(opts.placeholder or "")
            f.hint:SetShown((eb:GetText() or "") == "")
            eb:SetAlpha(enabled and 1 or 0.5)
        end,
    })
end

-- The text box under the cursor of an open DeckKit window, for an assistant asked to "type X into this box":
-- { label, get() -> text, fill(text, run) } (run: what the box's own Enter does, e.g. search), or nil.
function UI.ActiveTextBox()
    for _, s in ipairs(screens) do
        if s.win:IsShown() then
            local f = s:Focused()
            if f and f.textbox and f:IsVisible() and not f.editing then return f.textbox end
        end
    end
end

-- Binding: shows the assigned button(s) as glyphs. A: press a button to bind. X: clear.
-- opts.get() -> list of pad keys (e.g. { "PADLTRIGGER", "PAD1" }) or nil; opts.set(list or nil)
function UI.BindingText(keys, size)
    if not keys or #keys == 0 then return Hex(UI.Color.dim) .. "Not bound|r" end
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = Glyph(UI.KeyGlyph[k] or k, size or GLYPH) end
    return table.concat(parts, " + ")
end

function UI.Binding(parent, width, opts)
    local f = Row(parent, width, opts.label)
    f.value = Text(f, UI.Font.body, "RIGHT")
    f.value:SetPoint("RIGHT", -10, 0)
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function()
            local p = { { "A", "Bind" } }
            if opts.get() then p[#p + 1] = { "X", "Clear" } end
            return p
        end,
        activate = function(self)
            local screen = TabOf(self).screen
            screen.mode, screen.capture = "capture", self
            self.value:SetText(Hex(UI.Color.gold) .. "Press a button...|r")
        end,
        x = function() if opts.get() then opts.set(nil) end end,
        captured = function(_, key) opts.set({ key }) end,
        refresh = function(self)
            local screen = TabOf(self).screen
            if screen.mode == "capture" and screen.capture == self then return end
            RowEnabled(self)
            self.value:SetText(UI.BindingText(opts.get()))
        end,
    })
end

-- Button: the game's red panel button. Pressed / disabled / focus highlight are its own.
function UI.Button(parent, width, opts)
    local f = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    f:SetSize(width, 28)
    f:SetText(opts.label)
    f:SetNormalFontObject(UI.Font.body)
    f:SetHighlightFontObject(UI.Font.body)
    f:SetDisabledFontObject(UI.Font.dim)
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "A", opts.verb or opts.label } } end,
        activate = function() opts.run() end,
        refresh = function(self)
            if IsDisabled(self) then self:Disable() else self:Enable() end
        end,
    })
end

-- Stepper: a number changed with left/right ("<  170  >"). opts: min, max, step, format(v).
------------------------------------------------------------------------
-- Editing in place: a control takes the controller for a moment (a popover stepper, and later others). The window
-- fades behind it; its popover, if it has one, shows bright on the top layer. The control's dk.edit(f, key) gets
-- every press while it's open and returns "done" or "cancel" to end it (anything else: still open).
------------------------------------------------------------------------

-- Behind an open popover the window is veiled: a dark layer over it at this alpha, the window itself still opaque, so
-- nothing of the world shows through (fading the window's own alpha let player names read through it).
local EDIT_VEIL = { 1, 1, 1, 0.2 } -- white, frosting it (black at 0.55 tried first; white 0.25 a touch strong)

-- A popover panel above `anchor` (a region of the control; with `center`, over its middle instead), on the top layer so the faded window and any list
-- around the control leave it bright and unclipped. pop:SetLegend({ { "DPAD", "change" }, ... }, ...) writes its
-- legend lines (each argument one line of button glyphs and what they do) under whatever the control puts at
-- pop.top (its content's TOP anchor offset, -14 by default).
local POP_GLYPH = 24
function UI.Popover(anchor, width, height, center)
    local pop = CreateFrame("Frame", nil, UIParent)
    pop:SetSize(width, height)
    if center then pop:SetPoint("CENTER", anchor, "CENTER", 0, 0) else pop:SetPoint("BOTTOM", anchor, "TOP", 0, 4) end
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    -- The game's gamepad legend slot, as the window's footer legend wears it: made for something this small.
    pop.bg = pop:CreateTexture(nil, "BACKGROUND")
    pop.bg:SetAllPoints()
    if not pop.bg:SetAtlas("gamepad-footer-slot-bg") then pop.bg:SetColorTexture(0, 0, 0, 0.85) end
    pop.frame = pop:CreateTexture(nil, "BORDER")
    pop.frame:SetAllPoints()
    pop.frame:SetAtlas("gamepad-footer-slot-frameneutral")
    pop.top = -14
    pop.lines = {}
    function pop:SetLegend(...)
        local after
        for i = 1, select("#", ...) do
            local items = select(i, ...)
            local line = self.lines[i] or Text(self, UI.Font.body, "CENTER")
            self.lines[i] = line
            local parts = {}
            for _, it in ipairs(items) do
                local glyphs = ""
                for key in it[1]:gmatch("%S+") do glyphs = glyphs .. Glyph(key, POP_GLYPH) end
                parts[#parts + 1] = glyphs .. " " .. it[2]
            end
            line:SetText(table.concat(parts, "    "))
            line:ClearAllPoints()
            if after then line:SetPoint("TOP", after, "BOTTOM", 0, -6) else line:SetPoint("BOTTOM", 0, 8 + (select("#", ...) - 1) * 30) end
            line:Show()
            after = line
        end
        for i = select("#", ...) + 1, #self.lines do self.lines[i]:Hide() end
    end
    pop:Hide()
    return pop
end

-- Starts f's editing session: f takes every press (its dk.edit), the window is veiled, its popover shows.
function Screen:BeginEdit(f, popover)
    self.mode, self.capture, self.editPopover = "edit", f, popover
    if not self.veil then
        local v = CreateFrame("Frame", nil, self.win)
        v:SetAllPoints()
        v:SetFrameLevel(self.win:GetFrameLevel() + 50) -- over every control in the window
        local t = v:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetColorTexture(unpack(EDIT_VEIL))
        self.veil = v
    end
    self.veil:Show()
    if popover then popover:Show() end
end

-- Ends it: the veil lifts, the popover goes.
function Screen:EndEdit()
    if self.editPopover then self.editPopover:Hide() end
    self.editPopover = nil
    if self.veil then self.veil:Hide() end
    if self.mode == "edit" then self.mode, self.capture = nil, nil end
end

-- A question that blocks the window until it's answered, in a popover over its middle (the window veiled, as for a
-- spinner): opts.text (a line or two), opts.yes / opts.no (labels, "Yes" / "No"), opts.onYes() / opts.onNo().
-- A answers yes, B no; onYes runs inside that A press, so things the game wants a real press for (posting, buying,
-- cancelling an auction) can happen there.
local ASK_W = 380
function Screen:Ask(opts)
    if not self.askPop then
        local pop = UI.Popover(self.win, ASK_W, 110, true)
        pop.text = Text(pop, UI.Font.body, "CENTER")
        pop.text:SetPoint("TOP", 0, -16)
        pop.text:SetWidth(ASK_W - 32)
        pop.text:SetWordWrap(true)
        self.askPop = pop
    end
    local pop = self.askPop
    local yes, no = opts.yes or "Yes", opts.no or "No"
    pop.text:SetText(ns.Window.Glyphs(opts.text or ""))
    pop:SetLegend({ { "A", yes }, { "B", no } })
    pop:SetHeight(math.max(96, math.ceil(pop.text:GetStringHeight() or 20) + 70))
    local question = { dk = {
        edit = function(_, key)
            if key == "PAD1" then if opts.onYes then opts.onYes() end return "done" end
            if key == "PAD2" then if opts.onNo then opts.onNo() end return "cancel" end
        end,
        editPrompts = function() return { { "A", yes }, { "B", no } } end,
    } }
    self:BeginEdit(question, pop)
    self:UpdatePrompts()
end

-- Stepper: a number changed a step at a time. Left/right step it while it has the cursor. With opts.popover the
-- d-pad passes over it like any control and A opens it: up/right add, down/left subtract, LT/RT ten steps, A keeps,
-- B puts back the old value (for steppers that sit beside other controls, where left/right must move the cursor).
-- opts.done(v): after an A keeps a popover's value (do the expensive part there, e.g. search again).
-- opts.widest: the widest value it shows (default 999), so the popover is sized once and doesn't wiggle as it changes.
-- opts.min / opts.max: numbers, or functions read each time (so two spinners can bound each other: "from" never above
-- "to"). opts.any + opts.anyText: a value that means "no limit" (0, shown "any"), just below the minimum: stepping
-- down from the minimum reaches it, stepping up from it reaches the minimum; the min/max don't apply to it.
-- opts.bigStep: how many steps LT/RT take (10).
function UI.Stepper(parent, width, opts)
    local f = Row(parent, width, opts.label)
    f.value = Text(f, UI.Font.body, "CENTER")
    f.value:SetPoint("RIGHT", -34, 0)
    f.value:SetWidth(90)
    f.lt = Text(f, UI.Font.heading, "CENTER")
    f.lt:SetPoint("RIGHT", f.value, "LEFT", -2, 0)
    f.lt:SetText("<")
    f.gt = Text(f, UI.Font.heading, "CENTER")
    f.gt:SetPoint("LEFT", f.value, "RIGHT", 2, 0)
    f.gt:SetText(">")
    local function Lo() return type(opts.min) == "function" and opts.min() or opts.min end
    local function Hi() return type(opts.max) == "function" and opts.max() or opts.max end
    local userFormat = opts.format
    local function Show(v)
        if opts.any ~= nil and v == opts.any then return opts.anyText or "any" end
        return userFormat and userFormat(v) or tostring(v)
    end
    local function Step(d)
        local step = opts.step or 1
        local cur, lo, hi = opts.get(), Lo(), Hi()
        local v
        if opts.any ~= nil and cur == opts.any then
            if d <= 0 then return end -- "any" is the bottom
            v = lo + (d - 1) * step
        else
            v = cur + d * step
            if v < lo then
                if opts.any ~= nil then v = opts.any else v = lo end
            end
        end
        if v ~= opts.any then
            v = math.max(lo, math.min(hi, v))
            v = math.floor(v / step + 0.5) * step -- no float drift
        end
        if v ~= cur then opts.set(v) end
    end
    local bigStep = opts.bigStep or 10
    if opts.popover then
        -- Its popover: one line, the d-pad's left/right glyph (the footer legend's size) and then the value (Ben,
        -- 2026-11-17). A keeps, B cancels and LT/RT step ten, as the footer says.
        local pop = UI.Popover(f.value, 120, 44)
        -- The glyph in a fixed spot on the left; the number in a quiet field box (dark fill, a dark edge: just enough
        -- to set it apart, no focus look), fixed width, centred: nothing moves as the number changes.
        local PAD, GAP = 12, 8
        pop.glyph = Text(pop, UI.Font.title, "LEFT")
        pop.glyph:SetPoint("LEFT", PAD, 0)
        pop.glyph:SetText(Glyph("DPAD_LR", LEGEND_GLYPH))
        local glyphW = math.ceil(pop.glyph:GetStringWidth() or LEGEND_GLYPH)
        pop.box = CreateFrame("Frame", nil, pop)
        Fill(pop.box, 0, 0, 0, 0.6)
        local edge = CreateFrame("Frame", nil, pop.box, "BackdropTemplate")
        edge:SetAllPoints()
        edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        edge:SetBackdropBorderColor(0.25, 0.24, 0.21, 1)
        pop.box:SetPoint("LEFT", pop, "LEFT", PAD + glyphW + GAP, 0)
        pop.value = Text(pop.box, UI.Font.title, "CENTER")
        pop.value:SetPoint("CENTER", 0, 0)
        -- Sized once to the widest thing it shows: its minimum, its maximum (up to 999) and opts.widest, as formatted
        -- (0 can read "any", wider than 70). A format that can't show one is skipped rather than break the window.
        local widest = 0
        local samples = { Lo(), math.min(Hi() or 999, 999), opts.widest }
        if opts.any ~= nil then samples[#samples + 1] = opts.any end
        for _, v in pairs(samples) do
            local ok, shown = pcall(Show, v)
            if ok and shown then
                pop.value:SetText(shown)
                widest = math.max(widest, pop.value:GetStringWidth() or 0)
            end
        end
        local boxW = math.ceil(math.max(widest, 24) + 20)
        pop.box:SetSize(boxW, 28)
        pop:SetWidth(PAD + glyphW + GAP + boxW + PAD)
        f.pop = pop
        f.glow = f:CreateTexture(nil, "BACKGROUND")
        f.glow:SetPoint("TOPLEFT", f.lt, "TOPLEFT", -4, 4)
        f.glow:SetPoint("BOTTOMRIGHT", f.gt, "BOTTOMRIGHT", 4, -4)
        f.glow:SetColorTexture(1, 0.82, 0, 0.18)
        f.glow:Hide()
        local before
        return Register(f, {
            disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
            prompts = function() return { { "A", "Change" } } end,
            activate = function(self)
                before = opts.get()
                self.spinning = true
                TabOf(self).screen:BeginEdit(self, self.pop)
            end,
            edit = function(self, key)
                if key == "PADDUP" or key == "PADDRIGHT" then Step(1) return "step" end
                if key == "PADDDOWN" or key == "PADDLEFT" then Step(-1) return "step" end
                if key == "PADRTRIGGER" then Step(bigStep) return "step" end
                if key == "PADLTRIGGER" then Step(-bigStep) return "step" end
                if key == "PAD1" then
                    self.spinning = false
                    if opts.done then opts.done(opts.get()) end
                    return "done"
                end
                if key == "PAD2" then
                    self.spinning = false
                    if before ~= nil and before ~= opts.get() then opts.set(before) end
                    return "cancel"
                end
            end,
            refresh = function(self)
                local enabled = RowEnabled(self)
                local v = opts.get()
                self.value:SetText(Show(v))
                self.value:SetFontObject(self.spinning and UI.Font.heading or (enabled and UI.Font.body or UI.Font.dim))
                local open = self.spinning and true or false
                self.lt:SetShown(open)
                self.gt:SetShown(open)
                self.glow:SetShown(open)
                if open then
                    self.pop.value:SetText(Show(v))
                end
            end,
        })
    end
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "DPAD_LR", "Change" } } end,
        left = function() Step(-1) end,
        right = function() Step(1) end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            local v = opts.get()
            self.value:SetText(Show(v))
            self.value:SetFontObject(enabled and UI.Font.body or UI.Font.dim)
            self.lt:SetFontObject((v > Lo() or (opts.any ~= nil and v ~= opts.any)) and enabled and UI.Font.heading or UI.Font.dim)
            self.gt:SetFontObject(v < Hi() and enabled and UI.Font.heading or UI.Font.dim)
        end,
    })
end

-- Dial: a number dialed digit by digit, like a combination lock ("45.2"): up/down turn the chosen digit
-- (0-9, wrapping), left/right choose the digit, and past the first or last one the cursor moves on to
-- the next control. The chosen digit is lit gold while the dial has focus. For numbers typed exactly,
-- like map coordinates. opts: label (a caption above), digits (how many), point (digits after the
-- decimal point, 0 for none), get() / set(n) with n the digits as a whole number (452 for "45.2"),
-- activate + verb (what A does: a dial is usually the last step before saving).
local DIAL_W, DIAL_H, DIAL_GAP = 34, 46, 4
function UI.Dial(parent, opts)
    local n, point = opts.digits or 3, opts.point or 0
    local pointW = point > 0 and 10 or 0
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(n * DIAL_W + (n - 1) * DIAL_GAP + pointW, DIAL_H + 18)
    f.caption = Text(f, UI.Font.smallDim)
    f.caption:SetPoint("TOPLEFT", 0, 0)
    f.caption:SetText(opts.label or "")
    f.slots = {}
    for i = 1, n do
        local slot = CreateFrame("Frame", nil, f)
        slot:SetSize(DIAL_W, DIAL_H)
        local x = (i - 1) * (DIAL_W + DIAL_GAP) + ((point > 0 and i > n - point) and pointW or 0)
        slot:SetPoint("TOPLEFT", x, -18)
        Fill(slot, 1, 1, 1, 0.07)
        slot.lit = slot:CreateTexture(nil, "BORDER")
        slot.lit:SetAllPoints()
        slot.lit:SetColorTexture(1, 0.82, 0, 0.35)
        slot.text = Text(slot, UI.Font.title, "CENTER")
        local font = slot.text:GetFont()
        if font then slot.text:SetFont(font, 30, "OUTLINE") end
        slot.text:SetPoint("CENTER")
        f.slots[i] = slot
    end
    if point > 0 then
        local dot = Text(f, UI.Font.title, "CENTER")
        local font = dot:GetFont()
        if font then dot:SetFont(font, 30, "OUTLINE") end
        dot:SetPoint("BOTTOM", f.slots[n - point], "BOTTOMRIGHT", (DIAL_GAP + pointW) / 2, 2)
        dot:SetText(".")
    end
    f.pick = 1
    local function Digits()
        local v, out = math.max(0, math.floor(opts.get() + 0.5)), {}
        for i = n, 1, -1 do out[i] = v % 10; v = math.floor(v / 10) end
        return out
    end
    local function Turn(d)
        local ds = Digits()
        ds[f.pick] = (ds[f.pick] + d) % 10
        local v = 0
        for i = 1, n do v = v * 10 + ds[i] end
        opts.set(v)
    end
    -- The screen calls these as focus arrives and leaves (it does for every control): they light the
    -- chosen digit only while the dial has focus.
    local focused = false
    function f:LockHighlight() focused = true; self.dk.refresh(self) end
    function f:UnlockHighlight() focused = false; self.dk.refresh(self) end
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function()
            local p = { { "DPAD_UD", "Change" }, { "DPAD_LR", "Digit" } }
            if opts.activate then p[#p + 1] = { "A", opts.verb or "OK" } end
            return p
        end,
        up = function() Turn(1) end,
        down = function() Turn(-1) end,
        left = function(self) if self.pick > 1 then self.pick = self.pick - 1 else return false end end,
        right = function(self) if self.pick < n then self.pick = self.pick + 1 else return false end end,
        activate = opts.activate and function() opts.activate() end,
        refresh = function(self)
            local on = not IsDisabled(self)
            for i, d in ipairs(Digits()) do
                local slot = self.slots[i]
                slot.text:SetText(d)
                local lit = focused and i == self.pick
                slot.lit:SetShown(lit)
                slot.text:SetTextColor(unpack((lit and { 1, 1, 1 }) or (on and { 0.8, 0.8, 0.8 }) or UI.Color.dim))
            end
        end,
    })
end

-- Action: a row that does something (opens a window, applies a change). The A glyph at the right.
function UI.Action(parent, width, opts)
    local f = Row(parent, width, opts.label)
    f.value = Text(f, UI.Font.small, "RIGHT")
    f.value:SetPoint("RIGHT", -10, 0)
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "A", opts.verb or "Go" } } end,
        activate = function() opts.run() end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            self.value:SetText(enabled and Glyph("A", 22) or "")
        end,
    })
end

-- A read-only line in a list: "Label ...... value". opts.get() -> text, color
function UI.StatusRow(parent, width, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 24)
    f.label = Text(f, UI.Font.dim)
    f.label:SetPoint("LEFT", 10, 0)
    f.label:SetText(opts.label)
    f.value = Text(f, UI.Font.body, "RIGHT")
    f.value:SetPoint("RIGHT", -10, 0)
    function f:Update()
        local text, color = opts.get()
        self.value:SetText((color and Hex(color) or "") .. ns.Window.Glyphs(tostring(text)) .. (color and "|r" or ""))
    end
    f:Update()
    return f
end

-- Icon: an action-button-style square. Selected = the game's gold "checked" glow; a binding shows
-- as a glyph in the corner, like a hotkey on the action bar.
function UI.Icon(parent, size, opts)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(size, size)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexture(opts.icon)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    -- (the action bar's slot art: 66 px around a 36 px icon)
    f.border:SetPoint("TOPLEFT", -size * 0.42, size * 0.42)
    f.border:SetPoint("BOTTOMRIGHT", size * 0.42, -size * 0.42)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    f:SetHighlightTexture(hl)
    f.press = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.press:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    f.press:SetAllPoints()
    f.press:Hide()
    f.selected = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    f.selected:SetBlendMode("ADD")
    f.selected:SetAllPoints()
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 2)
    f.hotkey = Text(top, UI.Font.small, "RIGHT")
    f.hotkey:SetPoint("TOPRIGHT", 6, 6)
    f.opts = opts
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = opts.prompts, activate = opts.activate, x = opts.x, y = opts.y,
        refresh = function(self)
            local off = IsDisabled(self)
            self.icon:SetDesaturated(off)
            self.icon:SetVertexColor(off and 0.6 or 1, off and 0.6 or 1, off and 0.6 or 1)
            self.selected:SetShown(opts.isSelected and opts.isSelected() or false)
            local keys = opts.binding and opts.binding()
            self.hotkey:SetText(keys and #keys > 0 and UI.BindingText(keys, 22) or "")
        end,
    })
end

-- Lay frames out in a grid (cols wide), gap between, from the panel's content top.
function UI.Grid(frames, parent, cols, size, gap, x, y)
    for i, f in ipairs(frames) do
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", x + c * (size + gap), y - r * (size + gap))
    end
end

-- Refresh every control on the current tab (after one changes something others show).
function Screen:Refresh()
    for _, tab in ipairs(self.tabs) do
        for _, f in ipairs(tab.items) do
            -- A control capturing a key isn't redrawn mid-capture; one being edited in place (a popover) is: it shows
            -- the change.
            if f.dk.refresh and not (self.mode and self.mode ~= "edit" and self.capture == f) then f.dk.refresh(f) end
        end
        if tab.onRefresh then tab.onRefresh(tab) end
    end
    self:UpdatePrompts()
end

------------------------------------------------------------------------
-- Scrolling list: rows go in list.content (any height); the view follows the cursor, keeping one
-- row of context past it, and the right stick scrolls freely (the cursor then stays on a row you
-- can see). A thin bar on the right shows where you are.
------------------------------------------------------------------------

local CONTEXT = 1.0 -- rows of context kept above/below the focused row

function UI.ScrollList(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(width, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 18, 1)
    sf:SetScrollChild(content)
    sf.content = content
    sf.dkScroll = true
    content.dkScrollFrame = sf

    local track = sf:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.08)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", -4, 0)
    track:SetPoint("BOTTOMRIGHT", -4, 0)
    local thumb = sf:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.85, 0.75, 0.45, 0.9)
    thumb:SetWidth(4)
    sf.track, sf.thumb = track, thumb

    -- Call after adding rows: contentHeight = how tall the rows are in total.
    function sf:SetContentHeight(h)
        self.content:SetHeight(math.max(1, h))
        self:UpdateBar()
    end
    function sf:MaxScroll() return math.max(0, self.content:GetHeight() - self:GetHeight()) end
    function sf:ScrollTo(v)
        self:SetVerticalScroll(math.max(0, math.min(self:MaxScroll(), v)))
        self:UpdateBar()
    end
    function sf:UpdateBar()
        local max = self:MaxScroll()
        local show = max > 0
        self.track:SetShown(show)
        self.thumb:SetShown(show)
        if not show then return end
        local h = self:GetHeight()
        local th = math.max(24, h * h / self.content:GetHeight())
        local y = (h - th) * (self:GetVerticalScroll() / max)
        self.thumb:SetHeight(th)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", -4, -y)
    end
    -- Is f (a row in this list) fully in view?
    function sf:InView(f)
        local top, bottom = self:GetTop(), self:GetBottom()
        local ft, fb = f:GetTop(), f:GetBottom()
        return ft and top and ft <= top + 0.5 and fb >= bottom - 0.5
    end
    -- Scroll just enough to show f with some context.
    function sf:Reveal(f)
        local ctop = self.content:GetTop()
        local ft, fb = f:GetTop(), f:GetBottom()
        if not (ctop and ft) then return end
        local y1, y2 = ctop - ft, ctop - fb -- f's offsets down from the content's top
        local margin = f:GetHeight() * CONTEXT
        local cur, h = self:GetVerticalScroll(), self:GetHeight()
        if y1 - margin < cur then self:ScrollTo(y1 - margin)
        elseif y2 + margin > cur + h then self:ScrollTo(y2 + margin - h) end
    end
    sf:SetScript("OnSizeChanged", function(self) self:UpdateBar() end)
    return sf
end

function ScrollOf(f)
    local p = f and f:GetParent()
    while p do
        if p.dkScrollFrame then return p.dkScrollFrame end
        if p.dkScroll then return p end
        p = p:GetParent()
    end
end
UI.ScrollOf = ScrollOf

------------------------------------------------------------------------
-- List popup (a selector's choices)
------------------------------------------------------------------------

-- Up to LIST_MAX choices drop down under the selector; a longer list becomes a scrolling one in the
-- middle of the window.
local LIST_MAX = 12

function Screen:OpenList(owner, values, current, choose)
    self:ClosePopup()
    local pop = self.listPopup
    if not pop then
        pop = CreateFrame("Frame", nil, self.win)
        pop:SetFrameStrata("FULLSCREEN")
        Fill(pop, 0.035, 0.035, 0.045, 0.98, 2)
        Border(pop, "SimplePanelTemplate")
        pop.rows, pop.longRows = {}, {}
        pop:Hide()
        self.listPopup = pop
    end
    self.popup = pop
    local long = #values > LIST_MAX
    local width = math.max(owner.box and owner.box:GetWidth() or 160, long and 320 or 160)
    pop:ClearAllPoints()
    local parent, pool = pop, pop.rows
    if long then
        if not pop.scroll then
            pop.scroll = UI.ScrollList(pop, width, LIST_MAX * ROW_H)
            pop.scroll:SetPoint("TOPLEFT", 8, -8)
            pop.scrollWidth = width
        end
        parent, pool = pop.scroll.content, pop.longRows
        width = pop.scrollWidth
        pop:SetSize(width + 16, LIST_MAX * ROW_H + 16)
        pop:SetPoint("CENTER", self.win)
        pop.scroll:SetContentHeight(#values * ROW_H)
        pop.scroll:Show()
    else
        pop:SetSize(width + 16, #values * ROW_H + 16)
        pop:SetPoint("TOPRIGHT", owner.box or owner, "BOTTOMRIGHT", 8, -2)
        if pop.scroll then pop.scroll:Hide() end
    end
    local rowW = long and (width - 18) or width
    pop.items = {}
    local focus
    for i, c in ipairs(values) do
        local r = pool[i]
        if not r then
            r = Row(parent, rowW, "")
            r:EnableMouse(false)
            r.check = r:CreateTexture(nil, "OVERLAY")
            r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            r.check:SetSize(20, 20)
            r.check:SetPoint("RIGHT", -6, 0)
            pool[i] = r
        end
        r:ClearAllPoints()
        if long then r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H) else r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * ROW_H) end
        r.label:SetText(c[2])
        r.check:SetShown(c[1] == current)
        r.dk = {
            prompts = function() return { { "A", "Choose" } } end,
            activate = function()
                choose(c[1])
                self:ClosePopup()
                self:Refresh()
            end,
        }
        r:Show()
        pop.items[i] = r
        if c[1] == current then focus = r end
    end
    for i = #values + 1, #pool do pool[i]:Hide() end
    local other = long and pop.rows or pop.longRows
    for _, r in ipairs(other) do r:Hide() end
    pop.owner = owner
    pop:Show()
    self:SetFocus(focus or pop.items[1])
end

function Screen:ClosePopup()
    local pop = self.popup
    if not (pop and pop:IsShown()) then return end
    if pop.focus and pop.focus.UnlockHighlight then pop.focus:UnlockHighlight() end
    pop.focus = nil
    pop:Hide()
    local owner = pop.owner
    if owner and self.win:IsShown() then self:SetFocus(owner) end
end

------------------------------------------------------------------------
-- Actions: a slot that holds one (DeckKit.Actions), the picker that chooses it, and a menu row for one.
-- The same everywhere something is bound: X on a slot starts binding (as Forever's spellbook and macros
-- bind with X), the picker opens over the window, A chooses, B leaves it as it was.
------------------------------------------------------------------------

local EMPTY_SLOT = "Interface\\Buttons\\UI-Quickslot"

-- Draws action `id` (or nothing) on a slot frame made by ActionArt.
local function DrawAction(f, id)
    local A = ns.Actions
    if not id then
        f.icon:SetTexture(nil)
        f.count:SetText("")
        f.empty:Show()
        return
    end
    f.empty:Hide()
    f.icon:SetTexture(A.Icon(id))
    local available = A.Available(id)
    f.icon:SetDesaturated(not available)
    f.icon:SetVertexColor(available and 1 or 0.6, available and 1 or 0.6, available and 1 or 0.6)
    local n = A.Count(id)
    f.count:SetText(n and n ~= 1 and tostring(n) or "")
end

-- The action bar's slot look, at any size: icon, border, highlight, a count in the corner, an empty state.
local function ActionArt(f, size)
    f:SetSize(size, size)
    f.empty = f:CreateTexture(nil, "BACKGROUND")
    f.empty:SetTexture(EMPTY_SLOT)
    f.empty:SetPoint("TOPLEFT", -size * 0.42, size * 0.42)
    f.empty:SetPoint("BOTTOMRIGHT", size * 0.42, -size * 0.42)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    f.border:SetPoint("TOPLEFT", -size * 0.42, size * 0.42)
    f.border:SetPoint("BOTTOMRIGHT", size * 0.42, -size * 0.42)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    if f.SetHighlightTexture then f:SetHighlightTexture(hl) end -- a button; the table cells' icons are plain frames
    f.press = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.press:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    f.press:SetAllPoints()
    f.press:Hide()
    f.selected = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    f.selected:SetBlendMode("ADD")
    f.selected:SetAllPoints()
    f.selected:Hide()
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 2)
    f.count = Text(top, UI.Font.small, "RIGHT")
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    f.hotkey = Text(top, UI.Font.small, "RIGHT")
    f.hotkey:SetPoint("TOPRIGHT", 6, 6)
    return f
end
UI.ActionArt, UI.DrawAction = ActionArt, DrawAction

-- The picker: opens over the window. opts.current (the id bound now, or nil), opts.choose(id or nil),
-- opts.title (what's being bound, shown at the top). LB/RB change the list (DeckKit actions, spells,
-- items, macros, action bars); the first cell of every list is "Empty", which clears the slot.
local PICK_COLS, PICK_CELL, PICK_GAP, PICK_ROWS = 8, 44, 10, 5
local PICK_W = PICK_COLS * (PICK_CELL + PICK_GAP) + 18 -- the scroll bar's room

function Screen:OpenPicker(opts)
    self:ClosePopup()
    local A = ns.Actions
    local pop = self.picker
    if not pop then
        pop = CreateFrame("Frame", nil, self.win)
        pop:SetFrameStrata("FULLSCREEN")
        pop:SetSize(PICK_W + 40, 100 + PICK_ROWS * (PICK_CELL + PICK_GAP) + 50)
        Fill(pop, 0.035, 0.035, 0.045, 0.98, 2)
        Border(pop, "SimplePanelTemplate")
        pop.title = Text(pop, UI.Font.heading, "CENTER")
        pop.title:SetPoint("TOP", 0, -12)
        pop.strip = CreateFrame("Frame", nil, pop)
        pop.strip:SetPoint("TOPLEFT", 14, -34)
        pop.strip:SetPoint("TOPRIGHT", -14, -34)
        pop.strip:SetHeight(TAB_H)
        local rule = Line(pop.strip, 0.45, 0.42, 0.35, 0.8)
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        pop.lb = Text(pop.strip, UI.Font.body, "CENTER")
        pop.lb:SetPoint("LEFT", 4, 0)
        pop.lb:SetText(Glyph("LB", 30))
        pop.rb = Text(pop.strip, UI.Font.body, "CENTER")
        pop.rb:SetPoint("RIGHT", -4, 0)
        pop.rb:SetText(Glyph("RB", 30))
        pop.labels = {}
        for i, cat in ipairs(A.CATEGORIES) do
            local t = Text(pop.strip, UI.Font.dim, "CENTER")
            t:SetText(cat.label)
            pop.labels[i] = t
        end
        pop.underline = Line(pop.strip, 1, 0.82, 0, 1, 2)
        pop.scroll = UI.ScrollList(pop, PICK_W, PICK_ROWS * (PICK_CELL + PICK_GAP))
        pop.scroll:SetPoint("TOP", 0, -34 - TAB_H - 18)
        pop.name = Text(pop, UI.Font.body, "CENTER")
        pop.name:SetPoint("BOTTOM", 0, 16)
        pop.name:SetWidth(PICK_W)
        pop.cells = {}
        pop.shoulderText = "Lists"
        pop:Hide()
        self.picker = pop
    end

    -- Category labels laid out across the strip, the chosen one gold and underlined.
    local function Strip()
        local widths, total = {}, 0
        for i, t in ipairs(pop.labels) do
            widths[i] = t:GetStringWidth() + 26
            total = total + widths[i]
        end
        local x = -total / 2
        for i, t in ipairs(pop.labels) do
            t:ClearAllPoints()
            t:SetPoint("CENTER", pop.strip, "CENTER", x + widths[i] / 2, 1)
            t:SetFontObject(i == pop.cat and UI.Font.heading or UI.Font.dim)
            if i == pop.cat then
                pop.underline:ClearAllPoints()
                pop.underline:SetPoint("BOTTOM", t, "BOTTOM", 0, -8)
                pop.underline:SetWidth(widths[i] - 12)
            end
            x = x + widths[i]
        end
    end

    local screen = self
    local function Populate(catIndex)
        pop.cat = catIndex
        Strip()
        local list = { { id = false, label = "Empty" } }
        for _, e in ipairs(A.List(A.CATEGORIES[catIndex].key)) do list[#list + 1] = e end
        pop.items = {}
        local focus
        for i, e in ipairs(list) do
            local c = pop.cells[i]
            if not c then
                c = ActionArt(CreateFrame("Button", nil, pop.scroll.content), PICK_CELL)
                c:EnableMouse(false)
                pop.cells[i] = c
            end
            local col, row = (i - 1) % PICK_COLS, math.floor((i - 1) / PICK_COLS)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", PICK_GAP / 2 + col * (PICK_CELL + PICK_GAP), -(PICK_GAP / 2 + row * (PICK_CELL + PICK_GAP)))
            DrawAction(c, e.id or nil)
            c.selected:SetShown((e.id or nil) == opts.current)
            c.dk = {
                prompts = function() return { { "A", "Choose" } } end,
                onFocus = function() pop.name:SetText(e.label) end,
                activate = function()
                    screen:ClosePopup()
                    opts.choose(e.id or nil)
                    screen:Refresh()
                end,
            }
            c:Show()
            pop.items[i] = c
            if e.id and e.id == opts.current then focus = c end -- an empty slot starts on the first entry
        end
        for i = #list + 1, #pop.cells do pop.cells[i]:Hide() end
        pop.scroll:SetContentHeight(math.ceil(#list / PICK_COLS) * (PICK_CELL + PICK_GAP))
        pop.scroll:ScrollTo(0)
        screen:SetFocus(focus or pop.items[math.min(2, #pop.items)])
    end

    pop.onShoulder = function(d)
        local n = #A.CATEGORIES
        Populate((pop.cat - 1 + d) % n + 1)
    end
    pop.title:SetText(opts.title or "Bind")
    pop.owner = opts.owner
    pop:ClearAllPoints()
    pop:SetPoint("CENTER", self.win)
    self.popup = pop
    pop:Show()
    local start = 1
    local cat = opts.current and A.CategoryOf(opts.current)
    for i, c in ipairs(A.CATEGORIES) do if c.key == cat then start = i end end
    Populate(start)
end

-- A slot showing one action as an icon. opts: get() -> id or nil, set(id or nil), title (for the picker), size,
-- label (shown under the icon, or none), disabled/reason/onFocus. X starts binding.
function UI.ActionSlot(parent, opts)
    local f = ActionArt(CreateFrame("Button", nil, parent), opts.size or 44)
    if opts.label then
        f.caption = Text(f, UI.Font.smallDim, "CENTER")
        f.caption:SetPoint("TOP", f, "BOTTOM", 0, -6)
        f.caption:SetText(opts.label)
    end
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason,
        onFocus = opts.onFocus,
        prompts = function()
            local id = opts.get()
            return { { "X", id and "Change" or "Bind" } }
        end,
        x = function(self)
            TabOf(self).screen:OpenPicker({ owner = self, current = opts.get(), choose = opts.set,
                title = opts.title and (type(opts.title) == "function" and opts.title() or opts.title) })
        end,
        refresh = function(self) DrawAction(self, opts.get()) end,
    })
end

-- A menu row holding an action: label at the left, the action's icon and name at the right. X starts binding.
function UI.ActionRow(parent, width, opts)
    local f = Row(parent, width, opts.label)
    f.slot = ActionArt(CreateFrame("Frame", nil, f), 22)
    f.slot:EnableMouse(false)
    f.slot:SetPoint("RIGHT", -10, 0)
    f.slot.border:Hide()
    f.value = Text(f, UI.Font.small, "RIGHT")
    f.value:SetPoint("RIGHT", f.slot, "LEFT", -8, 0)
    f.value:SetWidth(width * 0.45)
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "X", opts.get() and "Change" or "Bind" } } end,
        x = function(self)
            local label = opts.label
            if type(label) == "function" then label = label() end
            TabOf(self).screen:OpenPicker({ owner = self, current = opts.get(), choose = opts.set,
                title = ns.Window.Glyphs(label or "Bind") })
        end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            local id = opts.get()
            DrawAction(self.slot, id)
            self.slot.empty:SetShown(false)
            self.value:SetText(id and ns.Actions.Label(id) or (Hex(UI.Color.dim) .. "Empty|r"))
            self.value:SetFontObject(enabled and UI.Font.small or UI.Font.smallDim)
        end,
    })
end

-- A compact cell holding an action, for tables of them (the grip slots): icon, then the action's name. opts:
-- width, get, set, title (for the picker), mine() -> true to show the name in lilac (a per-character setting),
-- onFocus. X starts binding.
function UI.ActionCell(parent, width, opts)
    local f = Row(parent, width, "")
    f.label:Hide()
    f.slot = ActionArt(CreateFrame("Frame", nil, f), 22)
    f.slot:EnableMouse(false)
    f.slot:SetPoint("LEFT", 8, 0)
    f.slot.border:Hide()
    f.value = Text(f, UI.Font.small)
    f.value:SetPoint("LEFT", f.slot, "RIGHT", 8, 0)
    f.value:SetPoint("RIGHT", -6, 0)
    f.value:SetWordWrap(false)
    return Register(f, {
        onFocus = opts.onFocus,
        prompts = function() return { { "X", opts.get() and "Change" or "Bind" } } end,
        x = function(self)
            local title = opts.title
            if type(title) == "function" then title = title() end
            TabOf(self).screen:OpenPicker({ owner = self, current = opts.get(), choose = opts.set, title = title })
        end,
        refresh = function(self)
            local id = opts.get()
            DrawAction(self.slot, id)
            self.slot.empty:SetShown(false)
            local text = id and ns.Actions.Label(id) or (Hex(UI.Color.dim) .. "Empty|r")
            if id and opts.mine and opts.mine() then
                local c = ns.COLORS and ns.COLORS.LILAC
                if c then text = Hex(c) .. text .. "|r" end
            end
            self.value:SetText(text)
        end,
    })
end
