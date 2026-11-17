-- PadTouchGrid: binding its cells in the editor, opening the grids with a grip chord, and firing a cell from where
-- the pointer is (the pad puts it there) with the click key, in and out of combat.
local Actions, Chords, UI = DeckKit.Actions, DeckKit.Chords, DeckKit.UI
local CLICK = "F11"

local function Screen(win) for _, s in ipairs(UI.Screens()) do if s.win == win then return s end end end
local function LastAction() return H.actions[#H.actions] end
local function Pointer(b) H.mouse.x, H.mouse.y = b:GetCenter() end
local function Header() return PadTouchGridHeader end
local function Cell(side, i) return _G["PadTouchGrid" .. (side == "left" and "Left" or "Right") .. i] end

step("nothing is bound to the click key or B while the grids are closed")
check(not Header():IsShown(), "closed at login")
eq(H.key(CLICK), "unbound", "a stray pad click does nothing")

step("the editor: two grids, the d-pad crosses from the left one to the right one, X binds")
SlashCmdList.DECKKIT("touchgrid")
local editor = Screen(PadTouchGridEditor)
check(editor and editor.win:IsShown(), "the editor is open")
local slots = editor:Focusables()
eq(#slots, 18, "eighteen cells")
editor:SetFocus(slots[3]) -- left grid, top right
H.pad("PADDRIGHT")
check(editor:Focused() == slots[10], "right from the left grid's top right is the right grid's top left")
editor:SetFocus(slots[1])
H.pad("PAD3")
H.pad("PADRSHOULDER") -- spells
H.pad("PAD1") -- Flash Heal, the first spell
eq(DeckKit.Actions.Label(PadTouchGridCharDB.left[1]), "Flash Heal", "left top left: Flash Heal")

step("more cells: an item, a macro and a DeckKit action")
editor:SetFocus(slots[5]) -- left middle
H.pad("PAD3"); H.pad("PADRSHOULDER"); H.pad("PADRSHOULDER"); H.pad("PAD1") -- items: Healing Potion
editor:SetFocus(slots[14]) -- right middle
H.pad("PAD3"); for _ = 1, 3 do H.pad("PADRSHOULDER") end; H.pad("PAD1") -- macros: Heal focus
local ran = 0
Actions.Offer("TEST_PING", { label = "Ping", run = function(down) if down then ran = ran + 1 end end })
editor:SetFocus(slots[18]) -- right bottom right
H.pad("PAD3") -- opens on DeckKit's list
local picker = editor.picker
local ping
for _, c in ipairs(picker.items) do if c.dk and c.dk.onFocus then editor:SetFocus(c); if H.Plain(picker.name:GetText()) == "Ping" then ping = c end end end
check(ping, "Ping is in DeckKit's list")
editor:SetFocus(ping); H.pad("PAD1")
eq(PadTouchGridCharDB.left[5], "ITEM:929", "left middle: the potion")
eq(PadTouchGridCharDB.right[5], "MACRO:Heal focus", "right middle: the macro")
eq(PadTouchGridCharDB.right[9], "TEST_PING", "right bottom right: Ping")
editor.win:Hide()

step("a grip chord set to Touch grids opens them, and binds the click key and B")
Chords.Set("R5", "hold", "PADTOUCHGRID_OPEN")
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
check(Header():IsShown(), "open")
check(H.Binding(CLICK) and H.Binding(CLICK).button == PadTouchGridFire, "the click key fires the cell")
check(H.Binding("PAD2") and H.Binding("PAD2").button == PadTouchGridClose, "B closes")

step("the cell under the pointer is lit and named")
Pointer(Cell("left", 1))
H.advance(0.1)
check(Cell("left", 1).hover:IsShown(), "lit")
check(H.findText("Flash Heal"), "named under its grid")

step("a pad click fires the cell under the pointer and closes both grids")
local before = #H.actions
H.key(CLICK, true); H.key(CLICK, false)
eq(#H.actions, before + 2, "the fire button clicked the cell, and the cell cast")
eq(LastAction().type, "spell", "a spell"); eq(LastAction().spell, 2061, "Flash Heal")
check(not Header():IsShown(), "closed")
eq(H.key(CLICK), "unbound", "the click key is free again")
check(not H.Binding("PAD2") or H.Binding("PAD2").button ~= PadTouchGridClose, "and B")

step("between cells nothing fires and the grids stay")
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
local l1, l2 = Cell("left", 1), Cell("left", 2)
H.mouse.x = (l1:GetRight() + l2:GetLeft()) / 2
H.mouse.y = select(2, l1:GetCenter())
before = #H.actions
H.key(CLICK, true)
eq(#H.actions, before, "nothing")
check(Header():IsShown(), "still open")

step("an item, a macro, and DeckKit's own action")
Pointer(Cell("left", 5)); H.key(CLICK, true)
eq(LastAction().item, "item:929", "the potion")
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
Pointer(Cell("right", 5)); H.key(CLICK, true)
eq(LastAction().macro, "Heal focus", "the macro")
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
Pointer(Cell("right", 9)); H.key(CLICK, true)
eq(ran, 1, "Ping ran (insecure, signalled from the secure click)")
check(not Header():IsShown(), "closed after each")

step("B closes them; the chord again toggles them shut too")
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
H.key("PAD2", true)
check(not Header():IsShown(), "B closed them")
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
check(not Header():IsShown(), "the chord twice: open, then shut")

step("in combat: opens, fires, closes")
H.combat(true)
H.key("F4", true); H.key("F8", true); H.key("F8", false); H.key("F4", false)
check(Header():IsShown(), "open in combat")
Pointer(Cell("left", 1))
before = #H.actions
H.key(CLICK, true)
eq(LastAction().spell, 2061, "cast in combat")
check(not Header():IsShown(), "closed")
step("the editor stays shut in combat")
SlashCmdList.DECKKIT("touchgrid")
check(not PadTouchGridEditor:IsShown(), "the editor doesn't open in combat")
H.combat(false)
check(not H.snippetErrors, "no errors in secure snippets: " .. table.concat(H.snippetErrors or {}, " | "))
