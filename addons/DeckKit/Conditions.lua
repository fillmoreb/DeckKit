-- DeckKit.Conditions: questions about the game a display can follow live ("is this quest taken?",
-- "do I carry 3 of these?"). Layout.lua's bound checks and progress bars use them, and anything else
-- that wants to tick itself off as the player plays.
--
-- A condition is a plain table (it can come from JSON):
--   { quest = 1013 }                       taken: in the log, or already turned in
--   { quest = 1013, state = "ready" }      ready to turn in (objectives done), or turned in
--   { quest = 1013, state = "done" }       turned in
--   { quest = 1013, objective = 2 }        that objective done (1-based), or the quest ready / done
--   { item = 6265, count = 3 }             carrying at least that many (bags; count 1 if left out)
--   { level = 20 }                         level reached
--   { zone = 1421 }                        in that UiMap, or a place inside it
--   { ["not"] = { ... } }                  the opposite (false while the game can't tell)
--
--   Conditions.Check(c)      true / false; nil when the game can't tell (a loading screen's no map)
--   Conditions.Progress(c)   have, need for counted ones (items, an objective's 3/8); nil otherwise
--   Conditions.OnChange(fn)  fn() once, shortly after anything a condition reads may have changed
local _, ns = ...

local C = {}
ns.Conditions = C

local turnedIn = {} -- quest IDs turned in this session (IsQuestFlaggedCompleted can lag behind)

local function Done(q)
    return turnedIn[q] or (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q)) or false
end
local function OnQuest(q) return C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q) or false end
local function Ready(q) return Done(q) or (OnQuest(q) and C_QuestLog.IsComplete and C_QuestLog.IsComplete(q)) or false end

local function InZone(target)
    local m = C_Map.GetBestMapForUnit("player")
    if not m or m == 0 then return nil end -- can't tell (a loading screen)
    for _ = 1, 8 do
        if not m or m == 0 then return false end
        if m == target then return true end
        local info = C_Map.GetMapInfo(m)
        m = info and info.parentMapID
    end
    return false
end

local function Objective(q, n)
    local goals = OnQuest(q) and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q)
    return goals and goals[n]
end

function C.Check(c)
    if type(c) ~= "table" then return nil end
    if c["not"] then
        local v = C.Check(c["not"])
        if v == nil then return false end
        return not v
    end
    if c.quest then
        local q = c.quest
        if c.objective then
            if Ready(q) then return true end
            local g = Objective(q, c.objective)
            return g and g.finished or false
        end
        if c.state == "ready" then return Ready(q) end
        if c.state == "done" then return Done(q) end
        return OnQuest(q) or Done(q)
    end
    if c.item then return (C_Item.GetItemCount(c.item) or 0) >= (c.count or 1) end
    if c.level then return (UnitLevel("player") or 0) >= c.level end
    if c.zone then return InZone(c.zone) end
    return nil
end

function C.Progress(c)
    if type(c) ~= "table" then return end
    if c.item then return C_Item.GetItemCount(c.item) or 0, c.count or 1 end
    if c.quest and c.objective then
        if Ready(c.quest) then
            local g = Objective(c.quest, c.objective)
            local need = g and g.numRequired or 1
            return need, need
        end
        local g = Objective(c.quest, c.objective)
        if g and g.numRequired and g.numRequired > 0 then return g.numFulfilled or 0, g.numRequired end
    end
end

-- Watching: game events coalesce into one round of callbacks a moment later (bags and the quest log
-- fire in bursts).
local listeners, pending = {}, false
function C.OnChange(fn) listeners[#listeners + 1] = fn end

local function Soon()
    if pending then return end
    pending = true
    C_Timer.NewTimer(0.25, function()
        pending = false
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end
C.Soon = Soon

for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
    "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do
    ns.On(e, Soon)
end
ns.On("QUEST_TURNED_IN", function(questID)
    if questID then turnedIn[questID] = true end
    Soon()
end)
