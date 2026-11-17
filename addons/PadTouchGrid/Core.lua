-- PadTouchGrid: two 3x3 grids of actions, one under each of the Deck's trackpads. A grip chord opens both; each
-- pad (Steam's Mouse Region mode) maps onto its grid, so where your thumb rests is the cell, lit; a pad click
-- fires that cell and closes both; B closes them. Any action DeckKit can bind (DeckKit.Actions: spells, items,
-- macros, DeckKit's own) goes in a cell, per character. Opens and fires in combat: the grids are secure.
--
--   Core.lua    the module, the saved cells, the layout (where each grid sits), and putting cells on buttons
--   Grids.lua   the grids on screen: the secure header and cells, opening and closing, the pad click and B
--   Editor.lua  binding the cells (a DeckKit screen: the two grids, X binds), the menu rows, the chord offer
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffb87affPadTouchGrid|r")

ns.SIDES = { "left", "right" }
ns.SIDE_NAMES = { left = "Left pad", right = "Right pad" }
ns.CELLS = 9
-- Where the grids are: each one's centre as fractions of the screen from the top left, and its cells' size and
-- gap in UI units (one unit is a pixel on the Deck). deck-setup/make-chord-layout.py reads these numbers for the
-- trackpads' Mouse Region boxes, so a pad and its grid cover the same rectangle: keep them plain literals.
ns.LAYOUT = {
    cell = 64, gap = 8,
    left = { x = 0.12, y = 0.60 },
    right = { x = 0.88, y = 0.60 },
}
-- The key a pad click sends (Steam layout), bound only while the grids are open. README "Keys".
ns.CLICK_KEY = "F11"
ns.CLOSE_KEY = "PAD2"

local CELL_NAMES = { "top left", "top", "top right", "left", "middle", "right", "bottom left", "bottom", "bottom right" }
function ns.CellName(side, i) return ns.SIDE_NAMES[side] .. ", " .. CELL_NAMES[i] end

local function DB()
    PadTouchGridCharDB = PadTouchGridCharDB or {}
    for _, side in ipairs(ns.SIDES) do PadTouchGridCharDB[side] = PadTouchGridCharDB[side] or {} end
    return PadTouchGridCharDB
end

-- The action in a cell (an id, DeckKit.Actions), or nil.
function ns.Get(side, i)
    local cells = DB()[side]
    return cells and cells[i] or nil
end

local listeners = {}
function ns.OnChange(fn) listeners[#listeners + 1] = fn end
function ns.Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

function ns.Set(side, i, id)
    DB()[side][i] = id
    ns.Apply()
    ns.Changed()
end

-- Puts every cell's action on its secure button (Grids.lua). Out of combat only: in combat it waits for the end.
local pending = false
function ns.Apply()
    if InCombatLockdown() then pending = true return end
    pending = false
    if ns.ApplyCells then ns.ApplyCells() end
end
ns.On("PLAYER_REGEN_ENABLED", function() if pending then ns.Apply() end end)
ns.On("PLAYER_LOGIN", function() DB(); ns.Apply(); ns.Changed() end)
