-- ForeverGuide's engine against a stand-in game: the real synced guides, a character played through the
-- first steps of Zephras Isle. Run from guide/:  lua5.1 tests/test_engine.lua
local ADDONS = "../addons/"

-- The few client globals the files touch at load.
C_Timer = { After = function() end, NewTicker = function() end }
C_Map = { GetAreaInfo = function() return nil end, GetMapInfo = function() return nil end }
C_QuestLog = {}
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = part end
    return unpack(out)
end

local function load(path, ...)
    local f = assert(loadfile(ADDONS .. path))
    return f(...)
end

load("ForeverGuide/Core.lua", "ForeverGuide")
load("ForeverGuide/Game.lua")
load("ForeverGuide/Text.lua")
load("ForeverGuide/Engine.lua")
load("ForeverGuide/Data/MapFrames.lua")
load("ForeverGuide/Data/Guides.lua")
load("ForeverGuide_Horde/Guides.lua")
local FG = ForeverGuide
local E = FG.Engine

-- The stand-in game: a Skyborne rogue.
local W = { level = 1, xp = 0, quests = {}, done = {}, ready = {}, objs = {}, items = {}, zone = "Zephras Isle",
            sub = "Shen'dar Village", pos = nil }
local G = FG.Game
G.OnQuest = function(q) return W.quests[q] == true end
G.Completed = function(q) return W.done[q] == true end
G.Ready = function(q) return W.ready[q] == true end
G.Objectives = function(q) return W.quests[q] and (W.objs[q] or {}) or nil end
G.QuestTitle = function() return nil end
G.Level = function() return W.level end
G.XPFrac = function() return W.xp end
G.Faction = function() return "Horde" end
G.Race = function() return "Skyborne" end
G.Class = function() return "ROGUE" end
G.ItemCount = function(i) return W.items[i] or 0 end
G.SpellKnown = function() return false end
G.SkillRank = function() return 0 end
G.Standing = function() return nil end
G.BindLocation = function() return nil end
G.Money = function() return 0 end
G.Zone = function() return W.zone end
G.SubZone = function() return W.sub end
G.AreaName = function() return nil end
G.MapName = function() return nil end
G.PlayerMap = function() return 2521, 42.8, 23.3 end
G.Distance = function() return W.pos end

local failures, checks = 0, 0
local function eq(a, b, what)
    checks = checks + 1
    if a ~= b then failures = failures + 1 print(("FAIL %s: got %s, want %s"):format(what, tostring(a), tostring(b))) end
end
local function step(name) print("-- " .. name) end

local function Accept(q) W.quests[q] = true end
local function TurnIn(q) W.quests[q] = nil W.ready[q] = nil W.done[q] = true end
local function Ready(q) W.ready[q] = true end

step("the data loads and the Skyborne guide is suggested at level 1")
local count = 0
for _ in pairs(FG.guides) do count = count + 1 end
eq(count > 150, true, "guides loaded (" .. count .. ")")
local ID = "forever/horde/skyborne/01-zephras-isle"
local guide = FG.guides[ID]
eq(guide ~= nil, true, "Zephras Isle guide")
-- PlayerZone needs map info; the stand-in has none, so the zone match is off and race wins.
eq(E.Suggestions()[1].id, ID, "first suggestion")

step("a new character starts on step 1, its first goal the one to do now")
local v = E.View(guide)
eq(v.stepIndex, 1, "step")
eq(v.stepNumber, 1, "step number")
eq(v.title, "Thendal Village", "title from the names table")
eq(v.goals[1].text, "Accept from Ailee Farheart", "accept line")
eq(v.goals[1].now, true, "now")
eq(v.goals[2].text, "Turn in to Rorian the Dayseeker", "turn-in line")

step("taking and handing in moves the step on")
Accept(92460) TurnIn(92460) Accept(92461) Accept(92462)
v = E.View(guide)
eq(v.stepIndex, 2, "step 2: the grove")
eq(v.goals[1].text, "Kill Juvenile Vuldren x8", "kill line before the log has lines")
W.objs[92461] = { { text = "Juvenile Vuldren slain: 3/8", finished = false, have = 3, need = 8 } }
v = E.View(guide)
eq(v.goals[1].text, "Juvenile Vuldren slain: 3/8", "the game's own words once in the log")
eq(v.goals[1].done, false, "not done at 3/8")
W.objs[92461] = { { text = "Juvenile Vuldren slain: 8/8", finished = true, have = 8, need = 8 } }
Ready(92462)
v = E.View(guide)
eq(v.stepIndex, 3, "both done: back to the village")

step("a class-only goal shows only for that class")
TurnIn(92462) Accept(92463) Accept(94414) Ready(94414) TurnIn(94414) Accept(92474)
v = E.View(guide)
eq(v.stepIndex, 4, "the errands")
local rogue, warrior = false, false
for _, g in ipairs(v.goals) do
    if g.quest == 92483 then rogue = true end
    if g.quest == 92532 then warrior = true end
end
eq(rogue, true, "the rogue's quest is there")
eq(warrior, false, "the warrior's isn't")

step("skipping by hand passes a step; a step done ahead is passed too")
E.state.skips[ID] = { [4] = true }
v = E.View(guide)
eq(v.stepIndex, 5, "skipped to the windstones")
E.state.skips[ID] = nil

step("soft goals: a goto is passed once a later goal in its step is done")
local fake = { id = "test/soft", title = "T", steps = {
    { title = "A", goals = { { t = "goto", map = 1, x = 1, y = 1 }, { t = "accept", quest = 9001, title = "Q" } } },
    { title = "B", goals = { { t = "goto", map = 1, x = 2, y = 2 } } },
    { title = "C", goals = { { t = "turnin", quest = 9001, title = "Q" } } },
} }
eq(E.View(fake).stepIndex, 1, "nothing done: step 1")
Accept(9001)
eq(E.View(fake).stepIndex, 2, "the accept passes the goto before it")
TurnIn(9001)
eq(E.View(fake).finished, true, "work done ahead passes the soft step 2")

step("when conditions")
local cond = { id = "test/when", title = "T", steps = {
    { title = "Only below 5", when = { { k = "level", op = "<", n = 5 } }, goals = { { t = "accept", quest = 9100, title = "X" } } },
    { title = "Not done", when = { { k = "turnedin", neg = true, q = 9101 } }, goals = { { t = "accept", quest = 9102, title = "Y" } } },
} }
eq(E.View(cond).stepIndex, 1, "level 1: step 1 applies")
W.level = 6
eq(E.View(cond).stepIndex, 2, "level 6: step 1 doesn't")
W.done[9101] = true
eq(E.View(cond).finished, true, "neg turnedin: step 2 doesn't either")

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
