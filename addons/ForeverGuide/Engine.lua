-- The rules: which goals are done, which step a character is on, which guide comes next. Progress is read
-- from the game each time (quests, items, level); only what the game can't say afterwards is kept
-- (state.ticks: goals seen done, like reaching a spot or opening a trainer; state.skips).
--
-- When a goal is done (after Polestar's table, docs/ARCHITECTURE.md "Guide data"):
--   accept      the quest is in the log or done, or a quest that closes it is
--   turnin      the quest is done (a `direct` one also when seen handed in)
--   complete    the quest is ready to hand in, or done
--   kill, collect, interact, use (with a quest)
--               its quest-log line is finished (the line named after the target, item or object, else line
--               `oi`), or the quest is ready or done; a collect with no quest counts the bags
--   level, skill, learn, buy, money, rep, sethome
--               the character's level, rank, spells, bags, money, standing, bind location
--   the rest (goto, talk, train, vendor, fly, hearth, enter, getfp, explore, ...)
--               "soft": seen done during the step (a tick), or a later goal of the same step is done
-- A step is done when every goal that applies and isn't optional is. A step whose open goals are all soft is
-- passed once quest work further on is done (you went ahead of the guide). `along` steps never hold the
-- route; their open goals ride along under the steps after them.
local FG = ForeverGuide
local Game, Text = FG.Game, FG.Text
local E = {}
FG.Engine = E

E.state = { skips = {}, ticks = {}, taxi = {} } -- replaced by the saved per-character state (API.lua)

------------------------------------------------------------------------
-- Who a guide, step or goal is for
------------------------------------------------------------------------

-- One `only` list: OR within, "!X" for "not X"; no list: anyone.
local function InList(list, v)
    if not list then return true end
    local any, hit = false, false
    for _, x in ipairs(list) do
        if type(x) == "string" and x:sub(1, 1) == "!" then
            if x:sub(2) == v then return false end
        else
            any = true
            if x == v then hit = true end
        end
    end
    return hit or not any
end

local function Only(only)
    if not only then return true end
    return InList(only.classes, Game.Class()) and InList(only.races, Game.Race())
        and InList(only.factions, Game.Faction())
end

function E.GuideFits(def)
    if def.faction and def.faction ~= Game.Faction() then return false end
    return InList(def.races, Game.Race()) and InList(def.classes, Game.Class())
end

function E.Levels(def)
    local fl = def.factionLevels and def.factionLevels[Game.Faction()]
    if fl then return fl.min, fl.max end
    return def.minLevel, def.maxLevel
end

------------------------------------------------------------------------
-- Conditions (a step's `when`, a guide's `nextWhen`)
------------------------------------------------------------------------

local function List(q) return type(q) == "table" and q or { q } end

local function Any(q, f)
    for _, id in ipairs(List(q)) do if f(id) then return true end end
    return false
end

local function Compare(a, op, b)
    if op == "<" then return a < b elseif op == "<=" then return a <= b
    elseif op == ">" then return a > b elseif op == "==" or op == "=" then return a == b end
    return a >= b
end

local function PlaceIs(text, p)
    if not text or text == "" then return false end
    local name = p.area and Game.AreaName(p.area)
    return text == name or text == p.name or text == p.location
end

local StepDone -- below; `done` conditions read it

local PRED = {
    level = function(p)
        local lv, n = Game.Level(), p.n
        if p.frac then lv, n = lv + Game.XPFrac(), n + p.frac end
        return Compare(lv, p.op, n)
    end,
    onquest = function(p) return Any(p.q, Game.OnQuest) end,
    complete = function(p) return Any(p.q, Game.Ready) end,
    turnedin = function(p) return Any(p.q, Game.Completed) end,
    available = function(p)
        return Any(p.q, function(q)
            if Game.OnQuest(q) or Game.Completed(q) then return false end
            if p.minLevel and Game.Level() < p.minLevel then return false end
            if p.pre and not Any(p.pre, Game.Completed) then return false end
            for _, r in ipairs(p.preAll or {}) do if not Game.Completed(r) then return false end end
            if p.parent and not Game.OnQuest(p.parent) then return false end
            for _, c in ipairs(p.closedBy or {}) do
                if Game.OnQuest(c) or Game.Completed(c) then return false end
            end
            return true
        end)
    end,
    has = function(p) return Game.ItemCount(p.item) >= (p.n or 1) end,
    upgrade = function() return true end, -- can't judge gear: counts as one, as in Polestar
    zone = function(p) return PlaceIs(Game.Zone(), p) end,
    subzone = function(p) return PlaceIs(Game.SubZone(), p) end,
    bound = function(p) return PlaceIs(Game.BindLocation(), p) end,
    dungeon = function() return false end, -- dungeon runs: skipped for now
    group = function() return false end,   -- group quests: skipped for now (solo by default)
    done = function(p, ctx)
        local i = ctx and ctx.labels and ctx.labels[p.label]
        return i and StepDone(ctx.guide, i, ctx) or false
    end,
    skill = function(p) return Game.SkillRank(p.name, p.skillLine) >= (p.n or 1) end,
    knows = function(p) return Game.SpellKnown(p.spell) end,
    taxi = function(p) return p.node and E.state.taxi[p.node] == true or false end,
    rep = function(p) local s = Game.Standing(p.faction) return s ~= nil and s >= p.standing end,
    money = function(p) return Compare(Game.Money(), p.op or ">=", p.n or 0) end,
    cooldown = function() return false end,
    buff = function() return false end,
    equipped = function(p) return Game.Equipped(p.item) end,
    indoors = function() return IsIndoors and IsIndoors() or false end,
}

function E.Holds(preds, ctx)
    for _, p in ipairs(preds or {}) do
        local f = PRED[p.k]
        if f then
            local v = f(p, ctx) and true or false
            if p.neg then v = not v end
            if not v then return false end
        end -- a kind this engine doesn't know: holds
    end
    return true
end

------------------------------------------------------------------------
-- Goals
------------------------------------------------------------------------

local SOFT = {
    ["goto"] = true, talk = true, train = true, vendor = true, fly = true, hearth = true, enter = true,
    getfp = true, explore = true, cast = true, wait = true, task = true, buff = true, equip = true,
    deposit = true, die = true, achieve = true, abandon = true, destroy = true, auction = true,
}
local OBJECTIVE = { kill = "target", collect = "itemName", interact = "objName", use = false }

function E.IsSoft(g)
    if SOFT[g.t] then return true end
    if (g.t == "interact" or g.t == "use") and not g.quest then return true end
    if g.t == "craft" and not (g.untilSkill or g.count) then return true end
    return false
end

-- Goals that are only words: never hold a step.
local function Info(g) return g.t == "note" end

local function Ticks(guideId, si)
    local t = E.state.ticks[guideId]
    return t and t[si]
end

function E.Tick(guideId, si, gi)
    E.state.ticks[guideId] = E.state.ticks[guideId] or {}
    local t = E.state.ticks[guideId]
    t[si] = t[si] or {}
    t[si][gi] = true
end

-- The quest log line a goal reads, or nil.
local function Objective(g)
    local objs = Game.Objectives(g.quest)
    if not objs or #objs == 0 then return nil, objs end
    local field = OBJECTIVE[g.t]
    local name = field and g[field]
    if name then
        for _, o in ipairs(objs) do
            if o.text and o.text:find(name, 1, true) then return o, objs end
        end
    end
    return g.oi and objs[g.oi], objs
end

-- Is the goal done by what the game says now (not counting ticks or later goals)? done, objective line,
-- have, need.
function E.GoalNow(g)
    local t, q = g.t, g.quest
    if t == "accept" then
        if Game.OnQuest(q) or Game.Completed(q) then return true end
        for _, c in ipairs(g.closedBy or {}) do
            if Game.OnQuest(c) or Game.Completed(c) then return true end
        end
        return false
    elseif t == "turnin" then
        return Game.Completed(q)
    elseif t == "complete" then
        return Game.Ready(q) or Game.Completed(q)
    elseif OBJECTIVE[t] ~= nil and q then
        if Game.Completed(q) or Game.Ready(q) then return true end
        if not Game.OnQuest(q) then return false end
        local o = Objective(g)
        if not o then return false end
        local need = g.upto or o.need
        return o.finished or (o.have and need and o.have >= need) or false, o, o.have, need
    elseif t == "collect" or t == "buy" or t == "auction" then
        local have, need = Game.ItemCount(g.item), g.count or 1
        return have >= need, nil, have, need
    elseif t == "level" then
        local lv = Game.Level()
        if lv > g.level then return true end
        return lv == g.level and (not g.frac or Game.XPFrac() >= g.frac)
    elseif t == "skill" then
        return Game.SkillRank(g.skill, g.skillLine) >= (g.level or 1)
    elseif t == "craft" then
        if g.untilSkill then return Game.SkillRank(g.skill, g.skillLine) >= g.untilSkill end
        if g.count and g.item then
            local have = Game.ItemCount(g.item)
            return have >= g.count, nil, have, g.count
        end
        return false
    elseif t == "learn" then
        return Game.SpellKnown(g.spell)
    elseif t == "money" then
        return Game.Money() >= (g.money or 0)
    elseif t == "rep" then
        local s = Game.Standing(g.faction)
        return s ~= nil and s >= g.standing
    elseif t == "sethome" then
        return PlaceIs(Game.BindLocation(), g)
    elseif t == "getfp" and g.node and E.state.taxi[g.node] then
        return true
    end
    return false
end

-- Soft goals the game shows done right now, ticked so they stay done: a spot reached, a place entered.
function E.Sense(g)
    local t = g.t
    if t == "goto" or t == "explore" then
        if g.map and g.x then
            local d = Game.Distance(g.map, g.x, g.y, g.f)
            if d and d <= math.max(g.r or 8, 10) then return true end
        end
        if g.area and t == "goto" and PlaceIs(Game.SubZone(), { area = g.area }) then return true end
    elseif t == "fly" or t == "hearth" or t == "enter" then
        return PlaceIs(Game.Zone(), g) or PlaceIs(Game.SubZone(), g)
    end
    return false
end

local function Applies(g)
    if not Only(g.only) then return false end
    if g.profName and Game.SkillRank(g.profName, g.profLine) <= 0 then return false end
    return true
end
E.GoalApplies = Applies

------------------------------------------------------------------------
-- Steps
------------------------------------------------------------------------

-- Per refresh: what each step's goals say, so nothing is asked twice.
local function GoalStates(guide, si, ctx)
    local cache = ctx.goals[si]
    if cache then return cache end
    cache = {}
    ctx.goals[si] = cache
    local step = guide.steps[si]
    local ticks = Ticks(guide.id, si)
    local laterHard = false
    for gi = #step.goals, 1, -1 do
        local g = step.goals[gi]
        local s = { goal = g, index = gi, applies = Applies(g) }
        if s.applies then
            s.soft = E.IsSoft(g)
            s.info = Info(g)
            s.now, s.obj, s.have, s.need = E.GoalNow(g)
            s.ticked = ticks and ticks[gi] or false
            s.done = s.now or s.ticked or (s.soft and laterHard)
            if s.done and not s.soft and not s.info then laterHard = true end
            if not s.done and (s.info or g.optional) then s.done = nil end -- not part of done-ness
        end
        cache[gi] = s
    end
    return cache
end

local function StepApplies(guide, si, ctx)
    local step = guide.steps[si]
    if not Only(step.only) then return false end
    if step.when and not E.Holds(step.when, ctx) then return false end
    return true
end

-- Every goal that holds the step done (ticks and later goals counted), and is the open part only soft?
function StepDone(guide, si, ctx)
    local open, softOnly, any = false, true, false
    for _, s in ipairs(GoalStates(guide, si, ctx)) do
        if s.applies and not s.info and not s.goal.optional then
            any = true
            if not s.done then
                open = true
                if not s.soft then softOnly = false end
            end
        end
    end
    return not open, softOnly, any
end

-- Did quest work in this step get done (an accept, a turn-in, an objective)?
local function QuestWorkDone(guide, si, ctx)
    for _, s in ipairs(GoalStates(guide, si, ctx)) do
        if s.applies and s.now and s.goal.quest and not s.soft then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Where the character is in a guide
------------------------------------------------------------------------

local function NewContext(guide)
    local ctx = { guide = guide, goals = {}, labels = {} }
    for i, step in ipairs(guide.steps) do
        if step.label then ctx.labels[step.label] = i end
    end
    return ctx
end

local function Skipped(guide, si)
    local s = E.state.skips[guide.id]
    return s and s[si]
end

-- The guide's route right now: the current step's index (nil when the guide is finished), the steps that
-- apply in order (for "step 4 of 38"), and the context the answers came from.
function E.Place(guide)
    local ctx = NewContext(guide)
    local n = #guide.steps
    local applies, route = {}, {}
    for si = 1, n do
        applies[si] = StepApplies(guide, si, ctx)
        if applies[si] and not guide.steps[si].along then route[#route + 1] = si end
    end
    -- Quest work done further on passes soft steps before it.
    local workAhead = {}
    local seen = false
    for si = n, 1, -1 do
        workAhead[si] = seen
        if applies[si] and QuestWorkDone(guide, si, ctx) then seen = true end
    end
    local current
    for _, si in ipairs(route) do
        if not Skipped(guide, si) then
            local done, softOnly = StepDone(guide, si, ctx)
            if not done and not (softOnly and workAhead[si]) then current = si break end
        end
    end
    return current, route, ctx, applies
end

------------------------------------------------------------------------
-- The view an addon draws
------------------------------------------------------------------------

-- A goal with candidates (a trainer, vendor or innkeeper "nearest you": Polestar lists every one) and no place of its
-- own: the nearest that fits the character (faction, class, race), else the first that fits.
local FACTION = { Horde = "H", Alliance = "A" }
function E.Candidate(g)
    if g.map or not g.candidates then return nil end
    local side = FACTION[Game.Faction()] or ""
    local best, bestD, first
    for _, c in ipairs(g.candidates) do
        local fits = (not c.faction or c.faction:find(side, 1, true)) and InList(c.classes, Game.Class())
            and InList(c.races, Game.Race())
        if fits and c.map and c.x then
            first = first or c
            local d = Game.Distance(c.map, c.x, c.y, c.f)
            if d and (not bestD or d < bestD) then best, bestD = c, d end
        end
    end
    return best or first
end

local function GoalView(guide, s)
    local g = s.goal
    local cand = not s.done and E.Candidate(g)
    if cand and not g.text and not g.npcName then
        -- Name the one picked: "Train at Akeri Duskblade", "Visit Dalia the Collector".
        g = setmetatable({ npcName = cand.npcName }, { __index = g })
    end
    local text = FG.Text.Goal(guide, g, s.obj)
    -- Counts the quest log doesn't give: bags for a collect or buy outside a quest.
    if not s.obj and s.need and s.need > 1 and (g.t == "collect" or g.t == "buy" or g.t == "auction" or g.t == "craft") then
        text = string.format("%s: %d/%d", Text.Resolve(guide, g.itemName or g.spellName or "?"), math.min(s.have or 0, s.need), s.need)
    end
    return {
        t = g.t, text = text, done = s.done == true, info = s.info, optional = g.optional == true,
        quest = g.quest, questTitle = g.quest and (g.title or Game.QuestTitle(g.quest)),
        note = g.note and Text.Resolve(guide, g.note), npc = g.npc or (cand and cand.npc), item = g.item,
        map = g.map or (cand and cand.map), x = g.x or (cand and cand.x), y = g.y or (cand and cand.y),
        f = g.f or (cand and cand.f), have = s.have, need = s.need, goal = s.goal,
    }
end

local function GoalViews(guide, si, ctx, onlyOpen)
    local out = {}
    for _, s in ipairs(GoalStates(guide, si, ctx)) do
        if s.applies and not (onlyOpen and (s.done or s.info)) then out[#out + 1] = GoalView(guide, s) end
    end
    return out
end

-- Everything about where the character is in a guide, for drawing.
function E.View(guide)
    local current, route, ctx, applies = E.Place(guide)
    local v = { guideId = guide.id, guideTitle = Text.Resolve(guide, guide.title), steps = #route,
                finished = current == nil, along = {} }
    v.minLevel, v.maxLevel = E.Levels(guide)
    if not current then return v end
    for i, si in ipairs(route) do if si == current then v.stepNumber = i end end
    local step = guide.steps[current]
    v.stepIndex = current
    v.title = step.title and Text.Resolve(guide, step.title)
    v.note = step.note and Text.Resolve(guide, step.note)
    v.goals = GoalViews(guide, current, ctx)
    for _, gv in ipairs(v.goals) do -- the first open goal is the one to do now
        if not gv.done and not gv.info and not gv.optional then gv.now = true break end
    end
    -- Open goals of along steps passed on the way, until the step they ride to.
    for si = 1, current - 1 do
        local step2 = guide.steps[si]
        if step2.along and applies[si] and not Skipped(guide, si) then
            local untilStep = type(step2.along) == "string" and ctx.labels[step2.along]
            if not untilStep or current < untilStep then
                for _, gv in ipairs(GoalViews(guide, si, ctx, true)) do v.along[#v.along + 1] = gv end
            end
        end
    end
    -- Along steps ahead that apply right now ride along too ("kill these as you meet them").
    for si = current + 1, #guide.steps do
        local step2 = guide.steps[si]
        if not step2.along then break end
        if applies[si] and not Skipped(guide, si) then
            for _, gv in ipairs(GoalViews(guide, si, ctx, true)) do v.along[#v.along + 1] = gv end
        end
    end
    return v
end

-- Soft goals of the current step (and riding along) the game shows done now: tick them. True if any.
function E.SenseTicks(guide, kinds)
    local current = E.Place(guide)
    if not current then return false end
    local any = false
    for gi, g in ipairs(guide.steps[current].goals) do
        if E.IsSoft(g) and (not kinds or kinds[g.t]) and Applies(g) then
            local t = Ticks(guide.id, current)
            if not (t and t[gi]) and E.Sense(g) then E.Tick(guide.id, current, gi) any = true end
        end
    end
    return any
end

-- An NPC window opened (gossip, quest, trainer, merchant, flight map): tick the current step's goals it does.
function E.NpcEvent(guide, what, npc)
    local current = E.Place(guide)
    if not current then return false end
    local any = false
    local function Candidate(g)
        if not g.npc and not g.candidates then return true end
        if g.npc == npc then return true end
        for _, c in ipairs(g.candidates or {}) do if c.npc == npc then return true end end
        return false
    end
    for gi, g in ipairs(guide.steps[current].goals) do
        local hit = false
        if g.t == "talk" then hit = npc ~= nil and g.npc == npc
        elseif g.t == "train" and what == "trainer" then hit = g.class or Candidate(g)
        elseif g.t == "vendor" and what == "merchant" then hit = Candidate(g)
        elseif g.t == "getfp" and what == "taxi" then hit = true end
        if hit and Applies(g) then E.Tick(guide.id, current, gi) any = true end
    end
    return any
end

-- A quest handed in: tick `direct` turn-ins (never in the log, so nothing else says so).
function E.TurnedIn(guide, questID)
    local current = E.Place(guide)
    if not current then return false end
    for gi, g in ipairs(guide.steps[current].goals) do
        if g.t == "turnin" and g.quest == questID then E.Tick(guide.id, current, gi) return true end
    end
    return false
end

-- A spell cast: tick `cast` goals for it.
function E.Cast(guide, spell)
    local current = E.Place(guide)
    if not current then return false end
    for gi, g in ipairs(guide.steps[current].goals) do
        if g.t == "cast" and g.spell == spell then E.Tick(guide.id, current, gi) return true end
    end
    return false
end

------------------------------------------------------------------------
-- Which guide
------------------------------------------------------------------------

-- The guide after a finished one: the first of nextChoices whose nextWhen holds, else next.
function E.Next(def)
    if def.nextChoices then
        for _, id in ipairs(def.nextChoices) do
            local when = def.nextWhen and def.nextWhen[id]
            if FG.guides[id] and (not when or E.Holds(when)) then return id end
        end
    end
    if def.next and FG.guides[def.next] then return def.next end
end

-- The zone-level map the player is in.
local function PlayerZone()
    local map = Game.PlayerMap()
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _ = 1, 6 do
        local info = map and C_Map.GetMapInfo(map)
        if not info then return map end
        if info.mapType == zoneType then return map end
        if info.mapType and info.mapType < zoneType then return map end
        map = info.parentMapID
    end
    return map
end
E.PlayerZone = PlayerZone

-- Leveling guides for this character at its level, best first: in this zone, for its race or class,
-- the narrowest level range.
function E.Suggestions()
    local level, zone = Game.Level(), PlayerZone()
    local out = {}
    for _, id in ipairs(FG.order) do
        local def = FG.guides[id]
        if def and (def.category or "Leveling") == "Leveling" and E.GuideFits(def) then
            local lo, hi = E.Levels(def)
            if (not lo or level >= lo) and (not hi or level <= hi) then
                out[#out + 1] = { id = id, def = def, here = def.zone == zone, own = def.races ~= nil or def.classes ~= nil,
                                  span = (hi or 60) - (lo or 1) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.own ~= b.own then return a.own end
        if a.span ~= b.span then return a.span < b.span end
        return a.id < b.id
    end)
    return out
end
