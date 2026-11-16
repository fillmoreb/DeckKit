-- Shared ride sightings (Share.lua): what's heard is checked hard, kept by shard, used in plans only on the shard it
-- was made on and only when newer than your own, compared with your own (Drift.lua), and asked for and answered.
ns.LoadSaved()
local Share, Shard, Timetable, Context = ns.Share, ns.Shard, ns.Timetable, ns.Context

local ROUTE = 285 -- the Orgrimmar - Grom'gol zeppelin
local route = ns.Routes[ROUTE]
local now = GetServerTime()
local function S(shard, routeID, epoch, seen) return ("S:1:%s:%d:%d:%d"):format(shard, routeID, epoch, seen) end
local function onShard(zone)
    Shard.Reset()
    Shard.Read(("Creature-0-4372-0-%d-3100-0000ABCDEF"):format(zone))
    Shard.Read(("Creature-0-4372-0-%d-3101-0000ABCDF0"):format(zone))
end

-- Off: nothing heard is used, nothing goes out.
check(ns.db.share == false, "sharing is off until turned on")
onShard(11)
Timetable.Sighted(ROUTE, { epoch = 1794699000000, seen = now - 7200 })
check(Context.Anchors()[ROUTE].epoch == 1794699000000, "your own sighting")

ns.db.share = true
CHANNEL = 7

-- Only well-formed sightings of routes ForeverNav knows, from the last two days, are taken.
local refused = {
    "S:1:11:285:1794699020000",                        -- a field short
    "S:2:11:285:1794699020000:" .. now,                -- another version
    "S:1:eleven:285:1794699020000:" .. now,            -- a shard that isn't digits
    S(11, 999999, 1794699020000, now),                 -- no such route
    S(11, ROUTE, 1794699020000, now + 3600),           -- from the future
    S(11, ROUTE, 1794699020000, now - 3 * 24 * 3600),  -- too old
    "S:1:11:285:1794699020000:" .. now .. ";print(1)", -- anything after
    "X:1:11",
    ("S:1:11:285:1:" .. now):rep(20),                  -- too long
}
for _, text in ipairs(refused) do check(not Share.OnMessage(text), "refused: " .. text:sub(1, 60)) end
check(Share.For("11") == nil, "nothing kept from them")

-- A sighting from another shard is kept for that shard and not used on yours.
check(Share.OnMessage(S(12, ROUTE, 1794699030000, now - 60)), "a sighting on shard 12 is taken")
check(Context.Anchors()[ROUTE].epoch == 1794699000000, "and not used on shard 11")

-- One on your shard, newer than yours, is used; it's compared with yours (20 s apart on the loop).
local driftBefore = #ns.db.drift
check(Share.OnMessage(S(11, ROUTE, 1794699020000, now - 30)), "a newer sighting on shard 11 is taken")
check(Context.Anchors()[ROUTE].epoch == 1794699020000, "and the plan uses it")
check(Timetable.Anchor(ROUTE).epoch == 1794699000000, "your own sighting is left as it was")
local entry = ns.db.drift[#ns.db.drift]
check(#ns.db.drift == driftBefore + 1 and entry.source == "shared", "the drift log has it")
check(math.abs(entry.drift - 20) < 0.01 and entry.shard == "11" and entry.before == "11",
    ("20 s from yours, both on shard 11: %.1f s"):format(entry.drift))
check(not Share.OnMessage(S(11, ROUTE, 1794699010000, now - 600)), "an older one than held isn't taken")

-- Turned off, plans go back to your own.
ns.db.share = false
check(Context.Anchors()[ROUTE].epoch == 1794699000000, "off: your own sighting again")
ns.db.share = true

-- A question about shard 11 is answered with what's held for it, after a short wait.
wipe(SENT)
wipe(TIMERS)
check(Share.OnMessage("Q:1:11"), "a question is taken")
check(#SENT == 0, "and not answered at once")
RunTimers()
check(SENT[1] == S(11, ROUTE, 1794699020000, now - 30), "answered with the sighting: " .. tostring(SENT[1]))

-- Someone else answering first stops ours.
wipe(SENT)
Share.OnMessage("Q:1:11")
Share.OnMessage(S(11, ROUTE, 1794699020000, now - 30)) -- the same sighting, from another player
RunTimers()
check(#SENT == 0, "an answer already given isn't repeated")

-- A ride of your own goes out once it has settled, under each shard you were on during it (shard ids are per zone: a
-- ride from Durotar on 11 to Stranglethorn on 12).
wipe(SENT)
Shard.Read("Creature-0-4372-0-12-3100-0000ABCDEF") -- crossing into Stranglethorn: two kinds of creature there
Shard.Read("Creature-0-4372-0-12-3101-0000ABCDF0")
check(Shard.Current() == "12", "now on shard 12")
Timetable.Sighted(ROUTE, { epoch = 1794699040000, seen = now })
RunTimers()
check(#SENT == 2, "your ride is shared under both shards: " .. #SENT)
check(SENT[1] == S(11, ROUTE, 1794699040000, now) and SENT[2] == S(12, ROUTE, 1794699040000, now),
    "boarding shard first, then landing: " .. tostring(SENT[1]) .. " / " .. tostring(SENT[2]))
check(Share.For("11")[ROUTE].epoch == 1794699040000 and Share.For("12")[ROUTE].epoch == 1794699040000,
    "and kept for both")
print(("share: %d malformed refused; shard-kept, newer-only, drift %.0f s logged; Q answered; own ride sent"):format(
    #refused, entry.drift))
