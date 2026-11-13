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

------------------------------------------------------------------------
-- The window ("screen"): title, tabs, body, footer with button prompts
------------------------------------------------------------------------

local Screen = {}
Screen.__index = Screen

local ScrollOf -- (defined with the scrolling list below)

local TAB_H, FOOTER_H, PAD = 30, 34, 14

local PAD_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD1", "PAD2", "PAD3", "PAD4",
    "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER", "PADFORWARD",
    "F8", "F9", "F10", "F11" }

-- Glyph names for pad keys (for binding controls).
UI.KeyGlyph = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
    PADLTRIGGER = "LT", PADRTRIGGER = "RT", PADDUP = "DUP", PADDDOWN = "DDOWN", PADDLEFT = "DLEFT",
    PADDRIGHT = "DRIGHT", PADFORWARD = "MENU", PADLSTICK = "L3", PADRSTICK = "R3",
    -- The Deck's back grips reach the game as F8-F11 (DeckKit's Steam layout).
    F8 = "L4", F9 = "R4", F10 = "L5", F11 = "R5" }

function UI.NewScreen(name, width, height, title)
    local s = setmetatable({ tabs = {}, tab = 1, mode = nil }, Screen)

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

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", PAD, -36 - TAB_H - 10)
    body:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 8)
    s.body = body

    -- Footer: what the buttons do right now. Left: tab switching / messages; right: the prompts.
    local footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", 2, 2)
    footer:SetPoint("BOTTOMRIGHT", -2, 2)
    footer:SetHeight(FOOTER_H)
    Fill(footer, 0, 0, 0, 0.45)
    local top = Line(footer, 0.45, 0.42, 0.35, 0.6)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    s.footerLeft = Text(footer, UI.Font.small)
    s.footerLeft:SetPoint("LEFT", PAD, 0)
    s.prompts = Text(footer, UI.Font.body, "RIGHT")
    s.prompts:SetPoint("RIGHT", -PAD, 0)
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
    s.input = ns.Input.New(win, handlers)

    win:HookScript("OnShow", function()
        ns.Window.Sound(true)
        s:SelectTab(s.tab, true)
    end)
    win:HookScript("OnHide", function()
        ns.Window.Sound(false)
        s:ClosePopup()
        s.mode, s.capture = nil, nil
        s.pointer:Hide()
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
            if old and old.UnlockHighlight then old:UnlockHighlight() end
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
    if old and old ~= f and old.UnlockHighlight then old:UnlockHighlight() end
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

-- The game's rule: nearest control whose center is inside a 45 degree cone that way.
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
                local d = dx * dx + dy * dy
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
    if key == "PADDLEFT" or key == "PADDRIGHT" then
        -- Steppers and choices take left/right themselves.
        local f = self:Focused()
        local fn = f and f.dk and not IsDisabled(f) and (key == "PADDLEFT" and f.dk.left or f.dk.right)
        if fn then
            fn(f)
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
        if self.popup and self.popup:IsShown() then return end
        local n = #self.tabs
        if n > 1 then self:SelectTab((self.tab - 1 + (key == "PADRSHOULDER" and 1 or -1)) % n + 1) end
        return
    end
    if key == "PAD2" or key == "PADFORWARD" then
        if self.popup and self.popup:IsShown() then self:ClosePopup() return end
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

-- Footer prompts for the focused control. Each control's dk.prompts returns
-- { {"A", "Toggle"}, {"X", "Clear"} }; B and LB/RB are added here.
function Screen:UpdatePrompts()
    local parts = {}
    local left = ""
    if self.mode == "capture" then
        parts[#parts + 1] = Hex(UI.Color.gold) .. (self.capture and self.capture.dk.captureText or "Press a button") .. "|r"
        parts[#parts + 1] = Glyph("B") .. " Cancel"
    elseif self.mode == "confirm" then
        parts[#parts + 1] = Glyph("A") .. " " .. (self.capture and self.capture.dk.confirmText or "Yes")
        parts[#parts + 1] = Glyph("B") .. " Cancel"
    else
        local f = self:Focused()
        if f and f.dk then
            if IsDisabled(f) then
                local why = f.dk.reason
                if type(why) == "function" then why = why(f) end
                left = Hex(UI.Color.dim) .. (why or "Unavailable") .. "|r"
            elseif f.dk.prompts then
                for _, p in ipairs(f.dk.prompts(f)) do parts[#parts + 1] = Glyph(p[1]) .. " " .. p[2] end
            end
        end
        local inPopup = self.popup and self.popup:IsShown()
        parts[#parts + 1] = Glyph("B") .. (inPopup and " Cancel" or " Close")
        if #self.tabs > 1 and not inPopup and left == "" then left = Glyph("LB") .. " " .. Glyph("RB") .. " Tabs" end
    end
    self.prompts:SetText(table.concat(parts, "     "))
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
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "DPAD_LR", "Change" }, { "A", "Choose" } } end,
        left = function() opts.set(Cycle(opts.values, opts.get(), -1)) end,
        right = function() opts.set(Cycle(opts.values, opts.get(), 1)) end,
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
    local function Step(d)
        local v = opts.get() + d * (opts.step or 1)
        v = math.max(opts.min, math.min(opts.max, v))
        v = math.floor(v / (opts.step or 1) + 0.5) * (opts.step or 1) -- no float drift
        if v ~= opts.get() then opts.set(v) end
    end
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        prompts = function() return { { "DPAD_LR", "Change" } } end,
        left = function() Step(-1) end,
        right = function() Step(1) end,
        refresh = function(self)
            local enabled = RowEnabled(self)
            local v = opts.get()
            self.value:SetText(opts.format and opts.format(v) or tostring(v))
            self.value:SetFontObject(enabled and UI.Font.body or UI.Font.dim)
            self.lt:SetFontObject(v > opts.min and enabled and UI.Font.heading or UI.Font.dim)
            self.gt:SetFontObject(v < opts.max and enabled and UI.Font.heading or UI.Font.dim)
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

-- Key binding for a game binding action (e.g. "CHATDECK_PEEK"), bound for real with SetBinding.
-- Only the back grips are offered: everything else on the pad belongs to the crossbar or the game.
local BINDABLE = { F8 = true, F9 = true, F10 = true, F11 = true }

local function KeyName(key)
    local g = UI.KeyGlyph[key]
    if g and g:match("^[LR][345]$") then return Hex(UI.Color.gold) .. g .. "|r" end
    return g and Glyph(g, 24) or key
end

local function ActionName(action)
    local name = _G["BINDING_NAME_" .. action]
    return name or action
end

function UI.KeyBinding(parent, width, opts)
    local action = opts.action
    local f = Row(parent, width, opts.label or ActionName(action))
    f.value = Text(f, UI.Font.body, "RIGHT")
    f.value:SetPoint("RIGHT", -10, 0)
    local pending
    local function Apply(key)
        if InCombatLockdown() then ns.Print("can't change bindings in combat.") return end
        for _, old in ipairs({ GetBindingKey(action) }) do SetBinding(old) end
        if key then SetBinding(key, action) end
        SaveBindings(GetCurrentBindingSet())
    end
    return Register(f, {
        disabled = opts.disabled, reason = opts.reason, onFocus = opts.onFocus,
        captureText = "Press a back grip (L4 R4 L5 R5)",
        prompts = function()
            local p = { { "A", "Bind" } }
            if GetBindingKey(action) then p[#p + 1] = { "X", "Clear" } end
            return p
        end,
        activate = function(self)
            local screen = TabOf(self).screen
            screen.mode, screen.capture = "capture", self
            self.value:SetText(Hex(UI.Color.gold) .. "Press a button...|r")
        end,
        x = function() if GetBindingKey(action) then Apply(nil) end end,
        captured = function(self, key)
            local screen = TabOf(self).screen
            if not BINDABLE[key] then
                screen.footerLeft:SetText(Hex(UI.Color.bad) .. "Only the back grips (L4 R4 L5 R5) can be bound here.|r")
                return
            end
            local current = GetBindingAction(key)
            if current and current ~= "" and current ~= action then
                pending = key
                screen.mode, screen.capture = "confirm", self
                self.dk.confirmText = "Replace " .. ActionName(current)
                self.value:SetText(KeyName(key) .. Hex(UI.Color.gold) .. "  replaces " .. ActionName(current) .. "|r")
                return
            end
            Apply(key)
        end,
        confirmed = function(_, yes)
            if yes and pending then Apply(pending) end
            pending = nil
        end,
        refresh = function(self)
            RowEnabled(self)
            local keys = { GetBindingKey(action) }
            if #keys == 0 then
                self.value:SetText(Hex(UI.Color.dim) .. "Not bound|r")
            else
                local parts = {}
                for _, k in ipairs(keys) do parts[#parts + 1] = KeyName(k) end
                self.value:SetText(table.concat(parts, "  "))
            end
        end,
    })
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
            if f.dk.refresh and not (self.mode and self.capture == f) then f.dk.refresh(f) end
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
    local pop = self.popup
    if not pop then
        pop = CreateFrame("Frame", nil, self.win)
        pop:SetFrameStrata("FULLSCREEN")
        Fill(pop, 0.035, 0.035, 0.045, 0.98, 2)
        Border(pop, "SimplePanelTemplate")
        pop.rows, pop.longRows = {}, {}
        self.popup = pop
    end
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
