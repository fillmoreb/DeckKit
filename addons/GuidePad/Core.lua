-- GuidePad: the leveling guide on screen, in the Objectives panel's place and look. The guide itself (which
-- guide, which step, what's done) is ForeverGuide's; this draws it and gives the controller its few actions.
--
-- Files, one job each:
--   Core.lua    the module: settings, grip chord actions, /deckkit guide, the game's tracker out of sight
--   Panel.lua   the panel, drawn like the tracker
--   Waypoint.lua  the next goal as a DeckKit waypoint (compass, minimap walk, peek map)
--
-- While the panel is up the game's own tracker is made invisible (alpha only: hiding it or hooking it would
-- fight its own updates and taint it), and the panel lists your other watched quests below the guide, so
-- nothing the tracker showed is lost.
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffffd100GuidePad|r")
ns.settingsScope = "char" -- its settings are kept per character (SavedVariablesPerCharacter)

local G = ForeverGuide.v1
local Panel = ns.Panel

local DEFAULTS = { on = true, quests = true, waypoint = true }
local db = {}
local GUIDE_VALUES = { { false, "The best for my level" } } -- filled once the guides load

------------------------------------------------------------------------
-- The game's tracker
------------------------------------------------------------------------

local trackerHidden = false
local function Tracker(show)
    local t = _G.ObjectiveTrackerFrame
    if not t then return end
    if show and trackerHidden then
        t:SetAlpha(1)
        trackerHidden = false
    elseif not show then
        t:SetAlpha(0)
        trackerHidden = true
    end
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------

local function Redraw(view)
    view = view or G.View()
    if db.on and view then
        Panel.Draw(view, db.quests)
        Tracker(false)
    else
        Panel.Hide()
        Tracker(true)
    end
    ns.Waypoint.Update(view, db.on and db.waypoint)
end

local function FillGuides()
    for i = #GUIDE_VALUES, 2, -1 do GUIDE_VALUES[i] = nil end
    for _, g in ipairs(G.Guides()) do
        local range = g.minLevel and string.format(" (%d-%d)", g.minLevel, g.maxLevel or g.minLevel) or ""
        GUIDE_VALUES[#GUIDE_VALUES + 1] = { g.id, g.title .. range }
    end
end

local function Skip()
    if G.Skip() then ns.Print("Step skipped.") else ns.Print("Nothing to skip.") end
end

local function Unskip()
    if G.Unskip() then ns.Print("Skip undone.") else ns.Print("No skipped step to take back.") end
end

local function Toggle()
    db.on = not db.on
    Redraw()
end

------------------------------------------------------------------------
-- Grip chords, command, settings
------------------------------------------------------------------------

DeckKit.Chords.Offer("GUIDEPAD_SKIP", { label = "Guide: skip step", run = function(down) if down then Skip() end end })
DeckKit.Chords.Offer("GUIDEPAD_UNSKIP", { label = "Guide: undo skip", run = function(down) if down then Unskip() end end })
DeckKit.Chords.Offer("GUIDEPAD_TOGGLE", { label = "Guide: show / hide", run = function(down) if down then Toggle() end end })

ns.AddCommand("guide", function(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "skip" then Skip()
    elseif arg == "back" or arg == "unskip" then Unskip()
    elseif arg == "on" or arg == "off" then db.on = arg == "on" Redraw()
    elseif arg == "" then Toggle()
    else
        local v = G.View()
        ns.Print(v and string.format("%s, step %s of %s: %s", v.guideTitle or "?", tostring(v.stepNumber), tostring(v.steps), v.title or "") or "No guide yet.")
    end
end, "show/hide the guide; skip, back (undo a skip), on, off, where")

ns.AddSettings({
    { type = "section", tab = "Quests", label = "Leveling guide", order = 1 },
    { type = "toggle", label = "Leveling guide",
      hint = "Shows the leveling guide where the quest tracker is, in its style: the step you're on, what's done, and your other quests below it. The guides are Polestar's, by Fitz.",
      get = function() return db.on end,
      set = function(on) db.on = on Redraw() end },
    { type = "choice", label = "Guide", values = GUIDE_VALUES,
      hint = "Which guide to follow. The best for my level picks one for your race, level and zone, and goes on to the next guide by itself when one is done.",
      get = function() return db.pick and G.GuideId() or false end,
      set = function(id) db.pick = id or nil G.SetGuide(id or nil) end },
    { type = "toggle", label = "Waypoint to the next goal",
      hint = "Puts a waypoint on the step's next goal that has a place (who to talk to, where to go, where the mobs are), so the compass and the walk on the map lead there. It moves on with the guide; your own waypoints stay as they are.",
      get = function() return db.waypoint end,
      set = function(on) db.waypoint = on Redraw() end },
    { type = "toggle", label = "Your other quests below it",
      hint = "Lists the quests you watch that the guide's step doesn't already show, the way the quest tracker does.",
      get = function() return db.quests end,
      set = function(on) db.quests = on Redraw() end },
    { type = "action", label = "Skip this step", verb = "Skip", keepOpen = true,
      hint = "Passes the step you're on, for one you've done some other way or don't want. Also a grip chord action (Guide: skip step).",
      run = Skip },
    { type = "action", label = "Undo the last skip", verb = "Undo", keepOpen = true,
      hint = "Brings back the last step you skipped.",
      run = Unskip },
    { type = "info", label = "The guides are Polestar's, by Fitz (github.com/fitzforge/polestar): every route, step and tip. Thank you, Fitz." },
    { type = "status", label = "Now",
      get = function()
          local v = G.View()
          if not v then return "Loading", nil end
          if v.finished then return v.guideTitle .. ": finished" end
          return string.format("%s, step %d of %d", v.guideTitle, v.stepNumber or 0, v.steps or 0)
      end },
})

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    GuidePadDB = GuidePadDB or {}
    for k, v in pairs(DEFAULTS) do if GuidePadDB[k] == nil then GuidePadDB[k] = v end end
    db = GuidePadDB
    ns.Waypoint.Init(db)
end)

ns.On("PLAYER_LOGIN", function()
    Panel.Build()
    G.OnChange(function(view)
        if #GUIDE_VALUES == 1 then FillGuides() end
        Redraw(view)
    end)
end)

-- The other quests part follows the quest log too, and the tracker may move (Edit Mode).
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = false if Panel.Shown() then Redraw() end end)
end
ns.On("QUEST_LOG_UPDATE", Soon)
ns.On("QUEST_WATCH_LIST_CHANGED", Soon)
ns.On("EDIT_MODE_LAYOUTS_UPDATED", Soon)
