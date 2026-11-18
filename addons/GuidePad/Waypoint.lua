-- The guide's waypoint: the next goal of the step that has a place (the NPC to talk to, the spot to reach,
-- where the mobs are) becomes one of DeckKit's waypoints, so the compass, the walk on the minimap and the
-- peek map lead there. One at a time: a new goal moves the guide's waypoint (the player's own are left
-- alone). Arriving removes it as usual, and it isn't put back for the same goal.
-- Your own waypoints come first: while you have one, the guide's is kept up to date behind it without taking
-- the compass; once yours are reached or removed, the guide's is the one left and leads again.
local _, ns = ...

local G = ForeverGuide.v1
local WP = DeckKit.Waypoints

local Waypoint = {}
ns.Waypoint = Waypoint

local db -- GuidePadDB: wpId (our waypoint's id), wpKey (the goal it is for)

-- The first open goal with a place, and its place on the live map (0-100).
local function Target(view)
    if not view or view.finished then return nil end
    for i, g in ipairs(view.goals or {}) do
        if not g.done and not g.info and not g.optional then
            local map, x, y = G.Point(g)
            if map then return view.guideId .. ":" .. view.stepIndex .. ":" .. i, g, map, x, y end
        end
    end
end

local function RemoveOurs()
    local i = db.wpId and WP.Find(db.wpId)
    if i then WP.Remove(i) end
    db.wpId = nil
end

-- Follow the view: a new goal gets a new waypoint; no goal with a place, none.
function Waypoint.Update(view, on)
    if not db then return end
    if not on then
        RemoveOurs()
        db.wpKey = nil
        return
    end
    local key, g, map, x, y = Target(view)
    if key == db.wpKey then return end -- same goal: leave it (or leave it gone, after arriving)
    db.wpKey = key
    local i, p = nil, nil
    if db.wpId then i, p = WP.Find(db.wpId) end
    if not key then RemoveOurs() return end
    -- Ours still there on the same map: move it, keeping whether it's the active one.
    if p and p.mapID == map then
        p.label, p.behind = g.text, true
        WP.Edit(i, x / 100, y / 100)
        return
    end
    RemoveOurs()
    local added = WP.Add(map, x / 100, y / 100, g.text, true) -- behind yours: active only when you have none
    db.wpId = added and added.id
end

function Waypoint.Init(saved) db = saved end
