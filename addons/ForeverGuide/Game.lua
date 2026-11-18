-- Every read of the game the engine makes, in one table (ForeverGuide.Game) so a test can put a stand-in
-- game in its place. Each function answers nil when the client can't.
-- Map frames: a point marked f = "e" is in the Era map frame (Forever moved some zones); its world position
-- comes from Data/MapFrames.lua's bounds, the formula Polestar's Compat.MapToWorld uses (credit: Polestar).
local FG = ForeverGuide
local Game = {}
FG.Game = Game

local function vec(x, y)
    if CreateVector2D then return CreateVector2D(x, y) end
    return { x = x, y = y }
end

-- Quests --------------------------------------------------------------------------------------------

function Game.OnQuest(q) return C_QuestLog.IsOnQuest(q) == true end
function Game.Completed(q) return C_QuestLog.IsQuestFlaggedCompleted(q) == true end
function Game.Ready(q)
    if C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(q) == true end
    return C_QuestLog.IsComplete(q) == true
end
-- The quest log's lines for a quest in the log: { { text, finished, have, need } }, or nil.
function Game.Objectives(q)
    local objs = C_QuestLog.GetQuestObjectives(q)
    if not objs then return nil end
    local out = {}
    for i, o in ipairs(objs) do
        out[i] = { text = o.text, finished = o.finished, have = o.numFulfilled, need = o.numRequired }
    end
    return out
end
function Game.QuestTitle(q) return C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q) end

-- The character -------------------------------------------------------------------------------------

function Game.Level() return UnitLevel("player") end
function Game.XPFrac()
    local max = UnitXPMax("player")
    return (max and max > 0) and UnitXP("player") / max or 0
end
function Game.Faction() return (UnitFactionGroup("player")) end
function Game.Race() return select(2, UnitRace("player")) end
function Game.Class() return select(2, UnitClass("player")) end
function Game.Money() return GetMoney() end
function Game.ItemCount(item)
    local f = C_Item and C_Item.GetItemCount or GetItemCount
    return f(item) or 0
end
function Game.SpellKnown(spell)
    if IsSpellKnown and IsSpellKnown(spell) then return true end
    return IsPlayerSpell and IsPlayerSpell(spell) or false
end
-- A profession's rank by its skill line or name: 0 when not learned (C_SkillInfo, as Polestar's Compat reads it).
local function Learned(info)
    if not info or info.isHeader then return nil end
    local rank, max = tonumber(info.rank) or 0, tonumber(info.maxRank) or 0
    if rank == 0 and max == 0 then return nil end
    return rank
end
function Game.SkillRank(name, line)
    local S = C_SkillInfo
    if not S then return 0 end
    if line and S.GetSkillLineInfoByID then
        local rank = Learned(S.GetSkillLineInfoByID(line))
        if rank then return rank end
    end
    local lower = name and name:lower()
    for i = 1, (S.GetNumSkillLines and S.GetNumSkillLines() or 0) do
        local info = S.GetSkillLineInfo(i)
        if info and ((line and info.skillID == line) or (lower and info.name and info.name:lower() == lower)) then
            local rank = Learned(info)
            if rank then return rank end
        end
    end
    return 0
end
-- Standing with a faction (1 Hated .. 8 Exalted), or nil when not met.
function Game.Standing(faction)
    local d = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(faction)
    return d and d.reaction or nil
end
function Game.Equipped(item)
    local f = C_Item and C_Item.IsEquippedItem
    return f and f(item) and true or false
end
function Game.BindLocation() return GetBindLocation and GetBindLocation() end

-- Places ----------------------------------------------------------------------------------------------

function Game.Zone() return GetRealZoneText and GetRealZoneText() or GetZoneText() end
function Game.SubZone() return GetSubZoneText and GetSubZoneText() end
function Game.AreaName(area)
    return area and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area) or nil
end
function Game.MapName(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and info.name
end

local function LiveToWorld(map, x, y)
    if not C_Map.GetWorldPosFromMapPos then return nil end
    local c, pos = C_Map.GetWorldPosFromMapPos(map, vec(x / 100, y / 100))
    if not (c and pos) then return nil end
    local wx, wy
    if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
    return c, wx, wy
end

-- A point's world position: continent, x (north), y (west).
function Game.MapToWorld(map, x, y, frame)
    if not (map and x and y) then return nil end
    if frame == "e" then
        local b = FG.mapFrames[map]
        if not b then return nil end
        return b.c, b.top + (b.bottom - b.top) * y / 100, b.left + (b.right - b.left) * x / 100
    end
    return LiveToWorld(map, x, y)
end

-- A world position on a map, 0-100 (for a point in the Era frame, where the live map draws it).
function Game.WorldToMap(c, wx, wy, map)
    if not (c and wx and wy and map) then return nil end
    if C_Map.GetMapPosFromWorldPos then
        local m, pos = C_Map.GetMapPosFromWorldPos(c, vec(wx, wy), map)
        if m == map and pos then
            local x, y
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            return x * 100, y * 100
        end
    end
end

function Game.PlayerMap()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos:GetXY()
    return map, x * 100, y * 100
end

-- Yards from the player to a point, or nil (another continent, or no position).
function Game.Distance(map, x, y, frame)
    local pm, px, py = Game.PlayerMap()
    if not px then return nil end
    local c1, ax, ay = Game.MapToWorld(pm, px, py)
    local c2, bx, by = Game.MapToWorld(map, x, y, frame)
    if not (c1 and c2) or c1 ~= c2 then return nil end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- The NPC the player is talking to (gossip, quest, trainer or merchant window), by id.
function Game.NpcID()
    local guid = UnitGUID and UnitGUID("npc")
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
