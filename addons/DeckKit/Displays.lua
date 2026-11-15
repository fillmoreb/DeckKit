-- Where a layout (Layout.lua) shows when it's a display of its own, rather than part of a module's window:
--
--   window    UI.ShowLayout(spec, opts)   takes the pad: you move through it, act on pieces, reply
--   card      UI.ShowCard(spec, opts)     on screen for a while, never takes the pad, fine in combat
--   tracker   UI.ShowTracker(spec, opts)  pinned at the top left while you play, ticking itself off
--
-- One of each at a time: a new one replaces the one up. The card sits to the right of the tracker while
-- both are up. Each is one spec (the same vocabulary everywhere), so an assistant answers with whichever
-- host fits: something to act on, something to glance at, something to play alongside.
--
-- Shared spec fields: `title` (the window's tab label, the card's and tracker's heading), `width`.
local _, ns = ...
local UI = ns.UI

local function Num(v) return tonumber(v) end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- A panel for the card and the tracker: the window look, without the pad.
local PAD = 12
local function Panel(name, alpha)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.035, 0.035, 0.045, alpha)
    UI.Border(f, "SimplePanelTemplate")
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFontObject(UI.Font.heading)
    f.title:SetPoint("TOPLEFT", PAD, -PAD)
    f.title:SetJustifyH("LEFT")
    f.body = CreateFrame("Frame", nil, f)
    return f
end

-- Builds spec in panel p, w wide; sizes the panel to it.
local function Fill(p, spec, w, opts)
    if p.L then p.L:Release() end
    local title = spec.title and tostring(spec.title) or ""
    p.title:SetText(title)
    p.title:SetWidth(w - 2 * PAD)
    local top = title ~= "" and (PAD + 28) or PAD -- the heading, and a little air before a first section
    p.body:ClearAllPoints()
    p.body:SetPoint("TOPLEFT", PAD, -top)
    p.body:SetSize(w - 2 * PAD, 1)
    p.L = UI.Build(p.body, spec, { width = w - 2 * PAD, onUpdate = opts and opts.onUpdate, ticks = opts and opts.ticks })
    local h = p.L.height + (p.L.footerH > 0 and p.L.footerH + 10 or 0)
    p:SetSize(w, top + h + PAD)
end

------------------------------------------------------------------------
-- The tracker
------------------------------------------------------------------------
--   opts.fade (default true)   fade out a minute after every check in it is ticked
--   opts.onDone()              it faded away finished (the owner forgets it)
--   opts.ticks                 as for UI.Build (a tracker's checks are usually the game's, not yours)

local tracker, card
local TRACKER_W, CARD_W = 300, 340

local function PlaceCard()
    if not (card and card:IsShown()) then return end
    card:ClearAllPoints()
    if tracker and tracker:IsShown() then
        card:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 8, 0)
    else
        card:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -80)
    end
end

function UI.ShowTracker(spec, opts)
    opts = opts or {}
    if not tracker then
        tracker = Panel("DeckKitTracker", 0.7)
        tracker:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -80)
    end
    if tracker.fadeTimer then tracker.fadeTimer:Cancel(); tracker.fadeTimer = nil end
    tracker:SetAlpha(1)
    local w = Clamp(Num(spec.width) or TRACKER_W, 200, 520)
    Fill(tracker, spec, w, { ticks = opts.ticks, onUpdate = function(L)
        if opts.fade == false then return end
        if L:AllDone() then
            if not tracker.fadeTimer then
                tracker.fadeTimer = C_Timer.NewTimer(60, function()
                    tracker.fadeTimer = nil
                    UIFrameFadeOut(tracker, 1.5, 1, 0)
                    C_Timer.After(1.5, function()
                        UI.HideTracker()
                        if opts.onDone then opts.onDone() end
                    end)
                end)
            end
        elseif tracker.fadeTimer then -- un-ticked again (dropped an item): not finished after all
            tracker.fadeTimer:Cancel()
            tracker.fadeTimer = nil
        end
    end })
    tracker:Show()
    tracker.L:Update()
    PlaceCard()
end

function UI.HideTracker()
    if not tracker then return end
    if tracker.fadeTimer then tracker.fadeTimer:Cancel(); tracker.fadeTimer = nil end
    if tracker.L then tracker.L:Release(); tracker.L = nil end
    tracker:Hide()
    tracker:SetAlpha(1)
    PlaceCard()
end

function UI.TrackerShown() return tracker ~= nil and tracker:IsShown() end

------------------------------------------------------------------------
-- The card
------------------------------------------------------------------------
--   opts.seconds   how long it stays (default: long enough to read it, 8 s plus a little per line, at
--                  most a minute); 0: until B or UI.HideCard
--   opts.onHide()  it went (its time, B, or replaced)
-- B closes it, out of combat and while no DeckKit window has the pad (a "B Close" hint says so); every
-- other button reaches the game. In combat B is the game's: the card waits out its time.

-- B for the card: a catcher that keeps only B, only while it can (out of combat: propagation can't
-- change in combat), only while no window owns the pad (B is the window's then).
local catcher
local function Catch(on)
    if not catcher then
        catcher = CreateFrame("Frame", nil, UIParent)
        catcher:SetSize(1, 1)
        catcher:SetPoint("TOPLEFT")
        catcher:Hide()
        catcher:SetScript("OnGamePadButtonDown", function(self, key)
            local mine = key == "PAD2" and not ns.Input.Owned() and not InCombatLockdown()
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(not mine) end
            if mine then UI.HideCard() end
        end)
        catcher:SetScript("OnGamePadButtonUp", function(self)
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end)
    end
    if on and not InCombatLockdown() then
        catcher:SetPropagateKeyboardInput(true)
        if catcher.EnableGamePadButton then catcher:EnableGamePadButton(true) end
        catcher:Show()
    elseif not on then
        catcher:Hide()
    end
    if card then card.hint:SetShown(on and not InCombatLockdown()) end
end
ns.On("PLAYER_REGEN_DISABLED", function() if card and card:IsShown() then Catch(false) end end)
ns.On("PLAYER_REGEN_ENABLED", function() if card and card:IsShown() then Catch(true) end end)

local function ReadingTime(L)
    return math.min(60, 8 + math.floor(L.height / 30) * 2)
end

function UI.ShowCard(spec, opts)
    opts = opts or {}
    if not card then
        card = Panel("DeckKitCard", 0.92)
        card:SetFrameStrata("HIGH")
        card.hint = card:CreateFontString(nil, "OVERLAY")
        card.hint:SetFontObject(UI.Font.small)
        card.hint:SetPoint("BOTTOMRIGHT", -PAD, 8)
        card.hint:SetText(ns.Window.Glyph("B", 22) .. " Close")
    end
    if card.timer then card.timer:Cancel(); card.timer = nil end
    local before = card.onHide
    card.onHide = nil
    if before and card:IsShown() then before() end
    local w = Clamp(Num(spec.width) or CARD_W, 220, 560)
    Fill(card, spec, w, { ticks = opts.ticks })
    card:SetHeight(card:GetHeight() + 20) -- room for the hint
    card.onHide = opts.onHide
    card:SetAlpha(1)
    card:Show()
    Catch(true)
    PlaceCard()
    local secs = opts.seconds or ReadingTime(card.L)
    if secs > 0 then card.timer = C_Timer.NewTimer(secs, UI.HideCard) end
end

function UI.HideCard()
    if not card then return end
    if card.timer then card.timer:Cancel(); card.timer = nil end
    if card.L then card.L:Release(); card.L = nil end
    card:Hide()
    Catch(false)
    local done = card.onHide
    card.onHide = nil
    if done then done() end
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
--   spec.width     how wide (default 560: room for tooltips beside it on the Deck's screen), 360-900
--   spec.height    the most it grows to (default 600); shorter content gets a shorter window
--   spec.title     the tab's label (a "pages" spec: each page's own title labels its tab; LB/RB between)
--   opts.title     the window's title (whose display it is: "Decky")
--   opts.onReply, opts.onChange, opts.ticks    as for UI.Build
--   opts.onClose(why)   the display went: "closed" (the player, or combat), "replaced" (a new one)
-- Returns false in combat (windows can't take the pad then).

local win -- { screen, tabs (all made so far), Ls (one per page shown), onClose }

-- The pages a spec shows as: a "pages" spec's items (each with its title, the footer its own or the
-- spec's), or the spec itself as one page.
local function PagesOf(spec)
    if spec.type ~= "pages" then return { spec } end
    local out = {}
    for i, page in ipairs(type(spec.items) == "table" and spec.items or {}) do
        if type(page) == "table" then
            local p = page
            if spec.footer and not page.footer then
                p = setmetatable({ footer = spec.footer }, { __index = page })
            end
            p.title = page.title or ("Page " .. i)
            out[#out + 1] = p
        end
    end
    return out
end

function UI.ShowLayout(spec, opts)
    opts = opts or {}
    if InCombatLockdown() then return false end
    if not win then
        local screen = UI.NewScreen("DeckKitLayoutWindow", 560, 400, "")
        win = { screen = screen, tabs = {}, Ls = {} }
        screen.tabs = {}
        screen.win:HookScript("OnHide", function()
            local done = win.onClose
            win.onClose = nil
            if done then done("closed") end
        end)
    end
    local s = win.screen
    for _, L in ipairs(win.Ls) do L:Release() end
    win.Ls = {}
    local before = win.onClose
    win.onClose = opts.onClose
    if before and s.win:IsShown() then before("replaced") end

    local pages = PagesOf(spec)
    if #pages == 0 then pages = { { type = "text", text = "(empty)" } } end
    -- One tab per page: tabs made once and reused; the screen sees only as many as there are pages.
    for i = #win.tabs + 1, #pages do
        win.tabs[i] = s:AddTab("")
    end
    s.tabs = {}
    for i, tab in ipairs(win.tabs) do
        local used = i <= #pages
        if used then s.tabs[i] = tab end
        tab.frame:SetShown(false)
        tab.label:SetShown(used)
        tab.underline:SetShown(false)
        tab.focus = nil
    end
    local w = Clamp(Num(spec.width) or 560, 360, 900)
    local maxH = Clamp(Num(spec.height) or 600, 240, 700)
    s.title:SetText(opts.title or "DeckKit")
    local bodyW, bodyMax = w - 28, maxH - UI.SCREEN_CHROME
    -- Ticks are kept by place in the page, so each page of several keeps its own.
    local function Ticks(i)
        if not opts.ticks or #pages == 1 then return opts.ticks end
        local key = "page" .. i
        opts.ticks[key] = opts.ticks[key] or {}
        return opts.ticks[key]
    end
    local function Build(page, i, height)
        return UI.Build(win.tabs[i].frame, page, { width = bodyW, height = height, onReply = opts.onReply,
            onChange = opts.onChange, ticks = Ticks(i) })
    end
    -- Built at the most height first; if every page is shorter, again at the tallest page's height.
    local need = 0
    for i, page in ipairs(pages) do
        win.tabs[i].title = page.title or spec.title or "Details"
        win.Ls[i] = Build(page, i, bodyMax)
        local L = win.Ls[i]
        need = math.max(need, L.height + (L.footerH > 0 and L.footerH + 10 or 0) + 4)
    end
    if need < bodyMax then
        for i, page in ipairs(pages) do
            win.Ls[i]:Release()
            win.Ls[i] = Build(page, i, need)
        end
        maxH = need + UI.SCREEN_CHROME
    end
    s:LayoutTabs()
    s.win:SetSize(w, maxH)
    s.tab = 1
    if s.win:IsShown() then s:SelectTab(1, true) else s:Show() end
    return true
end

function UI.HideLayout()
    if win and win.screen.win:IsShown() then win.screen:Hide() end
end
