-- Corrections to the synced data (Data/ is Shortest Path Forever's and never edited: tools/sync_spf.py rewrites it).
-- Each one says what's wrong and what's right, so it can go upstream and come out of here once a sync carries it.
-- nav/tests/test_docks.lua checks every dock's boarding point stays by its dock, so a sync that brings the same kind of
-- mistake back fails there.
local _, ns = ...

-- The Orgrimmar end of the Grom'gol zeppelin (route 285). Its boarding point (the dock's `walk`) came out as
-- (1405, -4605, z 73), a ledge about 50 yd north-east of the tower, nearest to the zeppelin's own height (71.9) rather
-- than the tower top under it: walks to the zeppelin ran past the tower, and the walk leg was never done standing on
-- it. The tower top is a platform at z 54, and the dock is on its edge.
local orgrimmarGromgol = ns.Docks[4]
if orgrimmarGromgol and orgrimmarGromgol.walk and math.abs(orgrimmarGromgol.walk.x - 1405.0) < 1 then
    orgrimmarGromgol.walk = { map = 1, x = 1360.9, y = -4631.3, z = 54.0 }
end
