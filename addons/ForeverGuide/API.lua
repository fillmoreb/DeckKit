-- ForeverGuide.v1: the guide a character is on and where it is in it, for any addon to show.
--
--   local G = ForeverGuide.v1
--   G.OnChange(fn)          fn(view) whenever what the guide says changes (view as G.View())
--   G.View()                { guideId, guideTitle, minLevel, maxLevel, steps, stepNumber, stepIndex, title, note,
--                             goals = { goal... }, along = { goal... }, finished } or nil before it's ready
--                             goal: { t, text, done, now, info, optional, quest, questTitle, note, npc, item,
--                                     map, x, y, f, have, need }
--   G.Skip() / G.Unskip()   pass the current step by hand / take back the last pass
--   G.SetGuide(id)          follow another guide (nil: the best suggestion)
--   G.Suggestions()         { { id, title, minLevel, maxLevel } } leveling guides for the character now, best first
--   G.Point(goal)           a goal's place on the live map: uiMapID, x, y (0-100), or nil
--   G.Ready()               data loaded and the quest log read
--
-- Saved per character in ForeverGuideCharDB: the guide, steps passed by hand, goals seen done that the game
-- can't tell afterwards, flight paths known.
local FG = ForeverGuide
local E, Game, Text = FG.Engine, FG.Game, FG.Text
local v1 = {}
FG.v1 = v1

local ready = false
local view, sig
local listeners = {}
local db

local function Guide() return db and db.guide and FG.guides[db.guide] end

local function Signature(v)
    if not v then return "" end
    local parts = { v.guideId or "", tostring(v.stepIndex), tostring(v.finished) }
    for _, list in ipairs({ v.goals or {}, v.along }) do
        for _, g in ipairs(list) do parts[#parts + 1] = (g.done and "1" or "0") .. (g.text or "") .. (g.note or "") end
        parts[#parts + 1] = "|"
    end
    return table.concat(parts, ";")
end

-- Pick a guide when there's none, and move on when one is finished.
local function Settle()
    if not db.guide or not FG.guides[db.guide] then
        local best = E.Suggestions()[1]
        db.guide = best and best.id or nil
    end
    for _ = 1, 5 do
        local guide = Guide()
        if not guide or E.Place(guide) then return end
        local nextId = E.Next(guide)
        if not nextId then return end
        db.guide = nextId
    end
end

local function Refresh()
    if not ready then return end
    Settle()
    local guide = Guide()
    view = guide and E.View(guide) or nil
    local s = Signature(view)
    if s == sig then return end
    sig = s
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, view)
        if not ok then geterrorhandler()(err) end
    end
end

local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false Refresh() end)
end
FG.Refresh = Soon

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local events = CreateFrame("Frame")
local function Listen(...)
    for i = 1, select("#", ...) do pcall(events.RegisterEvent, events, (select(i, ...))) end
end
Listen("PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB",
    "SPELLS_CHANGED", "PLAYER_MONEY", "UPDATE_FACTION", "HEARTHSTONE_BOUND", "GOSSIP_SHOW", "QUEST_DETAIL",
    "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "TRAINER_SHOW", "MERCHANT_SHOW", "TAXIMAP_OPENED",
    "UNIT_SPELLCAST_SUCCEEDED")

-- The flight map lists the nodes this character knows.
local function ReadTaxi()
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return end
    local nodes = C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())
    local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable
    for _, n in ipairs(nodes or {}) do
        if n.nodeID and (unreachable == nil or n.state ~= unreachable) then db.taxi[n.nodeID] = true end
    end
end

local NPC_WINDOW = { GOSSIP_SHOW = "gossip", QUEST_DETAIL = "quest", QUEST_PROGRESS = "quest",
                     QUEST_COMPLETE = "quest", QUEST_GREETING = "quest", TRAINER_SHOW = "trainer",
                     MERCHANT_SHOW = "merchant", TAXIMAP_OPENED = "taxi" }

local function Start()
    if ready then return end
    ready = true
    Refresh()
end

events:SetScript("OnEvent", function(_, event, a1, _, a3)
    if event == "PLAYER_LOGIN" then
        ForeverGuideCharDB = ForeverGuideCharDB or {}
        db = ForeverGuideCharDB
        db.skips, db.ticks, db.taxi = db.skips or {}, db.ticks or {}, db.taxi or {}
        db.skipOrder = db.skipOrder or {}
        E.state = db
        FG.LoadFaction(Game.Faction())
        -- The quest log isn't read yet at login: wait for it (or a few seconds).
        C_Timer.After(5, Start)
        return
    end
    if not db then return end
    if event == "QUEST_LOG_UPDATE" and not ready then Start() return end
    local guide = Guide()
    if guide and ready then
        if NPC_WINDOW[event] then
            if event == "TAXIMAP_OPENED" then ReadTaxi() end
            E.NpcEvent(guide, NPC_WINDOW[event], Game.NpcID())
        elseif event == "QUEST_TURNED_IN" then
            E.TurnedIn(guide, a1)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if a1 ~= "player" then return end
            if not E.Cast(guide, a3) then return end
        elseif event:find("^ZONE_CHANGED") or event == "PLAYER_ENTERING_WORLD" then
            E.SenseTicks(guide)
        end
    end
    Soon()
end)

-- Spots to reach: look once a second while the step has one open.
local SPOT = { ["goto"] = true, explore = true }
C_Timer.NewTicker(1, function()
    if not (ready and view and view.goals) then return end
    for _, g in ipairs(view.goals) do
        if not g.done and SPOT[g.t] then
            if E.SenseTicks(Guide(), SPOT) then Refresh() end
            return
        end
    end
end)

------------------------------------------------------------------------
-- v1
------------------------------------------------------------------------

function v1.Ready() return ready end
function v1.View() return view end

function v1.OnChange(fn)
    listeners[#listeners + 1] = fn
    if view then pcall(fn, view) end
end

function v1.Skip()
    local guide = Guide()
    local current = guide and E.Place(guide)
    if not current then return false end
    db.skips[guide.id] = db.skips[guide.id] or {}
    db.skips[guide.id][current] = true
    table.insert(db.skipOrder, { guide.id, current })
    Refresh()
    return true
end

function v1.Unskip()
    local last = table.remove(db.skipOrder)
    if not last then return false end
    local s = db.skips[last[1]]
    if s then s[last[2]] = nil end
    if last[1] ~= db.guide and FG.guides[last[1]] then db.guide = last[1] end
    Refresh()
    return true
end

function v1.SetGuide(id)
    if id and not FG.guides[id] then return false end
    db.guide = id
    sig = nil
    Refresh()
    return true
end

function v1.GuideId() return db and db.guide end

local function Entry(def)
    local lo, hi = E.Levels(def)
    return { id = def.id, title = Text.Resolve(def, def.title), minLevel = lo, maxLevel = hi }
end

function v1.Suggestions()
    local out = {}
    for _, s in ipairs(E.Suggestions()) do out[#out + 1] = Entry(s.def) end
    return out
end

-- Every leveling guide for this character, by level.
function v1.Guides()
    local out = {}
    for _, id in ipairs(FG.order) do
        local def = FG.guides[id]
        if (def.category or "Leveling") == "Leveling" and E.GuideFits(def) then out[#out + 1] = Entry(def) end
    end
    table.sort(out, function(a, b)
        if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
        return a.id < b.id
    end)
    return out
end

-- Where a goal is on the live map (an Era-frame point converted).
function v1.Point(g)
    if not (g and g.map and g.x) then return nil end
    if g.f ~= "e" then return g.map, g.x, g.y end
    local c, wx, wy = Game.MapToWorld(g.map, g.x, g.y, "e")
    local x, y = Game.WorldToMap(c, wx, wy, g.map)
    if x then return g.map, x, y end
end
