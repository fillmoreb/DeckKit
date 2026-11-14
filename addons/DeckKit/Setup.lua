-- The welcome window: DeckKit's first-time setup as a short list of steps, each saying how it's going,
-- with a button to do it. It opens by itself at login while a step is unfinished, until you close it
-- with B; a step you haven't seen yet (the healing step on your first healer) brings it back once.
-- Double-tap Menu > Controls > Setup, or /deckkit setup, opens it any time.
--
-- Modules add their own steps (DeckKit never knows about them):
--   DeckKit.Setup.AddStep({
--       id = "suggested", order = 10,
--       title = "Suggested settings and layout",
--       text = "What it does, in a sentence or two. {A} tokens work.",
--       shown = function() return true end,      -- optional: leave the step out when false
--       done = function() return true end,       -- is it done? (checked each time the window shows)
--       problem = function() return nil end,     -- optional: text when it can't be done yet, and why
--       action = {                               -- optional
--           label = "Apply", verb = "Apply", run = function() ... end,
--           reloads = true,      -- it reloads the UI: the window comes back afterwards
--           opensWindow = true,  -- it opens a window of its own: this one closes first (two DeckKit
--                                -- windows would both take the pad); call DeckKit.Setup.Open() when
--                                -- that window closes to come back
--       },
--   })
-- A finished step's button is disabled (the footer says Done), so A can't redo it by accident.
--
-- The core's own step: the Steam controller layout for the grips. It can't be installed from the game,
-- but it can be checked: done once a grip's key and its long-press key (DeckKit.GRIPS) are both seen
-- held, which proves the press and the hold halves of the layout.
local _, ns = ...
local UI = ns.UI

local Setup = {}
ns.Setup = Setup

local WIDTH, HEIGHT = 700, 540
local steps = {}
local screen

function Setup.AddStep(step)
    steps[#steps + 1] = step
    table.sort(steps, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

local function Shown(step) return not step.shown or step.shown() end
local function Done(step) return step.done and step.done() or false end

-- Steps you closed the window on (per account): the window doesn't open by itself for them again.
local function Closed() ns.db.setupClosed = ns.db.setupClosed or {} return ns.db.setupClosed end

local function WantsToOpen()
    local closed = Closed()
    for _, step in ipairs(steps) do
        if Shown(step) and not Done(step) and not closed[step.id] then return true end
    end
    return false
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------

local GOOD, TODO, BAD = { 0.4, 0.9, 0.35 }, { 1, 0.82, 0 }, { 1, 0.35, 0.3 }
local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function Build()
    screen = UI.NewScreen("DeckKitSetup", WIDTH, HEIGHT, "Welcome to DeckKit")
    local tab = screen:AddTab("Setup")
    local panel = UI.Panel(tab.frame, nil)
    panel:SetAllPoints()
    -- B: you've seen these steps; don't open by itself for them again.
    function screen:OnPlayerClose()
        for _, step in ipairs(steps) do
            if Shown(step) and not Done(step) then Closed()[step.id] = true end
        end
    end
    local W = WIDTH - 52
    -- Each piece sits under the one before (so an empty problem line takes no room).
    local prev
    local function Below(region, x, gap)
        region:ClearAllPoints()
        region:SetPoint("LEFT", panel, "LEFT", x, 0)
        if prev then region:SetPoint("TOP", prev, "BOTTOM", 0, -gap) else region:SetPoint("TOP", panel, "TOP", 0, -12) end
        prev = region
    end
    local intro = UI.Description(panel, "A few things to set up once, in order. Each step says how it's going. "
        .. "{B} closes this; double-tap {MENU} > Controls > Setup brings it back.", W)
    Below(intro, 12)
    screen.rows = {}
    local n = 0
    for _, step in ipairs(steps) do
        if Shown(step) then
            n = n + 1
            local row = { step = step, n = n }
            row.heading = UI.Heading(panel, "")
            Below(row.heading, 12, n == 1 and 14 or 18)
            local text = UI.Description(panel, step.text or "", W - 12)
            Below(text, 24, 6)
            if step.problem then
                row.problem = UI.Description(panel, "", W - 12)
                Below(row.problem, 24, 4)
            end
            if step.action then
                local a = step.action
                row.action = UI.Action(panel, W, { label = a.label, verb = a.verb,
                    disabled = function() return Done(step) or (step.problem and step.problem() ~= nil) end,
                    reason = function()
                        if Done(step) then return "Done" .. (a.doneReason and (": " .. a.doneReason) or "") end
                        return "Can't do this yet: see above"
                    end,
                    run = function()
                        if a.opensWindow then screen:Hide() end -- not B, so it doesn't count as closing
                        if a.reloads then ns.db.setupReopen = true end
                        a.run()
                        if a.reloads then ns.db.setupReopen = nil end -- still here: it didn't reload
                        if screen.win:IsShown() then Setup.Refresh() end
                    end })
                Below(row.action, 12, 4)
            end
            screen.rows[#screen.rows + 1] = row
        end
    end
end

function Setup.Refresh()
    if not screen or not screen.rows then return end
    for _, row in ipairs(screen.rows) do
        local done = Done(row.step)
        local problem = not done and row.step.problem and row.step.problem()
        row.heading:SetText(string.format("%d. %s   %s%s|r", row.n, row.step.title,
            Hex(done and GOOD or problem and BAD or TODO), done and "Done" or problem and "Needs you" or "Not yet"))
        if row.problem then
            row.problem:SetText(problem and (Hex(BAD) .. problem .. "|r") or "")
            row.problem:SetHeight(problem and row.problem:GetStringHeight() or 0.01) -- empty: no room taken
        end
    end
    screen:Refresh()
end

-- Focus the first unfinished step's button.
local function FocusNext()
    for _, row in ipairs(screen.rows) do
        if row.action and not UI.IsDisabled(row.action) then screen:SetFocus(row.action, true) return end
    end
end

function Setup.Open()
    if InCombatLockdown() then ns.Print("can't open that in combat.") return end
    if UI.AnyScreenShown() and not (screen and screen.win:IsShown()) then return end
    if not screen then Build() end
    screen:Show()
    Setup.Refresh()
    FocusNext()
end

ns.AddCommand("setup", function() Setup.Open() end, "the welcome window: first-time setup steps")

------------------------------------------------------------------------
-- The core's step: the Steam controller layout, detected from the grip keys
------------------------------------------------------------------------

local function GripsSeen() return ns.db.gripsSeen == true end

Setup.AddStep({
    id = "grips", order = 20,
    title = "Steam controller layout for the grips",
    text = "Hold any back grip (L4 R4 L5 R5) for a second: this step turns Done when its keys arrive. "
        .. "If it stays Not yet, install DeckKit's controller layout from Desktop Mode: the README on "
        .. "github.com/fillmoreb/DeckKit, \"Grip chords\", has the steps.",
    done = GripsSeen,
})

-- Watch for a grip held long enough to send both its keys, until it's been seen once (then stop).
local watcher = CreateFrame("Frame")
local wait = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    wait = wait - elapsed
    if wait > 0 then return end
    wait = 0.1
    if not IsKeyDown then return end
    if GripsSeen() then self:SetScript("OnUpdate", nil) return end
    for _, g in ipairs(ns.GRIPS) do
        if IsKeyDown(g.key) and IsKeyDown(g.long) then
            ns.db.gripsSeen = true
            self:SetScript("OnUpdate", nil)
            if screen and screen.win:IsShown() then Setup.Refresh(); FocusNext() end
            return
        end
    end
end)

------------------------------------------------------------------------
-- Opening by itself: after login, or after a step's reload, once nothing's in the way (combat, another
-- DeckKit window, the game menu).
------------------------------------------------------------------------

local pending = false
local function TryOpen()
    if not pending then return end
    if InCombatLockdown() or UI.AnyScreenShown() or (GameMenuFrame and GameMenuFrame:IsShown()) then return end
    pending = false
    ns.db.setupReopen = nil
    Setup.Open()
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(3, function()
        pending = ns.db.setupReopen or WantsToOpen()
        if not pending then return end
        local ticker
        ticker = C_Timer.NewTicker(1, function()
            TryOpen()
            if not pending then ticker:Cancel() end
        end)
        TryOpen()
    end)
end)
