-- Waypoints kept behind the player's own (the leveling guide's): active only when nothing else is, and when the
-- active one goes, the player's own come before it.
local W = DeckKit.Waypoints
W.ClearAll()

step("alone, a waypoint kept behind leads")
local guide = W.Add(1411, 0.5, 0.5, "Guide", true)
eq(W.Active(), guide, "the guide's leads when it's the only one")

step("yours takes over and stays ahead of the guide's")
local mine = W.Add(1411, 0.4, 0.4, "Mine")
eq(W.Active(), mine, "a waypoint you add leads")
local i = W.Find(guide.id)
W.Remove(i)
guide = W.Add(1411, 0.6, 0.6, "Guide, next goal", true)
eq(W.Active(), mine, "the guide's next one doesn't take the lead from yours")

step("with yours gone, the guide's leads again; your others first")
local other = W.Add(1411, 0.3, 0.3, "Other of mine")
W.SetActive((W.Find(other.id)))
local j = W.Find(other.id)
W.Remove(j)
eq(W.Active(), mine, "another of yours before the guide's, though the guide's is newer")
W.Remove((W.Find(mine.id)))
eq(W.Active(), guide, "then the guide's")
check(W.Active().behind, "and it's still marked as kept behind")
W.ClearAll()
