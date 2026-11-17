-- The grip slots table (Controls › Grips) and the action picker, driven with pad presses, and what the grip
-- chords then do when their keys arrive (the secure path, as far as the harness models it).
--   Table:   rows of chords, Press and Hold side by side; the d-pad moves across and down.
--   Picker:  X on a slot opens it; LB/RB change the list; A chooses; B leaves the slot as it was; Empty clears.
--   Firing:  a spell, a bag item and a macro each set up the grip's secure button to do that.
local Chords, Actions, UI = DeckKit.Chords, DeckKit.Actions, DeckKit.UI

local function Plain(fs) return H.Plain(fs and fs:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function MenuScreen()
    for _, s in ipairs(UI.Screens()) do if s.win == DeckKitMenu then return s end end
end

-- The table cell on chord `chord`'s row, in column `col` (1 press, 2 hold): the focusable whose centre is level
-- with the row's label and the col-th from the left.
local function Cell(screen, chord, col)
    local label
    for _, f in ipairs(H.frames()) do
        if f:GetObjectType() == "FontString" and f:IsVisible() and Plain(f) == chord then label = f end
    end
    check(label, "a row labelled " .. chord)
    local _, ly = label:GetCenter()
    local row = {}
    for _, f in ipairs(screen:Focusables()) do
        local x, y = f:GetCenter()
        if y and math.abs(y - ly) < 6 and f.slot then row[#row + 1] = { f = f, x = x } end
    end
    table.sort(row, function(a, b) return a.x < b.x end)
    check(row[col], ("%s has a column %d (found %d cells)"):format(chord, col, #row))
    return row[col].f
end

local function LastAction() return H.actions[#H.actions] end

step("the menu opens on Controls, with the grip slots as a table")
DeckKit.Menu.Open()
local screen = MenuScreen()
check(screen and screen.win:IsShown(), "the menu is open")
eq(screen.tabs[screen.tab].title, "Controls", "first tab")
local l4press, l4hold = Cell(screen, "L4", 1), Cell(screen, "L4", 2)
local r4hold = Cell(screen, "R4", 2)

step("the d-pad moves across a row and down a column")
screen:SetFocus(l4press)
H.pad("PADDRIGHT")
check(screen:Focused() == l4hold, "right from L4 press is L4 hold")
H.pad("PADDDOWN")
check(screen:Focused() == r4hold, "down from L4 hold is R4 hold")
H.pad("PADDLEFT")
check(screen:Focused() == Cell(screen, "R4", 1), "left from R4 hold is R4 press")

step("X opens the picker on DeckKit's list (nothing bound yet), RB goes to Spells")
Chords.Set("L4", "press", nil)
screen:SetFocus(l4press)
H.pad("PAD3")
local picker = screen.picker
check(picker and picker:IsShown() and screen.popup == picker, "the picker is open")
check(Plain(picker.title):find("L4", 1, true), "it says what's being bound: " .. Plain(picker.title))
eq(picker.cat, 1, "starts on the first list")
H.pad("PADRSHOULDER")
eq(Actions.CATEGORIES[picker.cat].key, "spells", "RB: spells")
eq(#picker.items, 1 + 4, "Empty and the four castable spells (the passive one isn't listed)")
check(screen:Focused() == picker.items[2], "the cursor starts on the first spell")
eq(Plain(picker.name), "Flash Heal", "its name shows under the grid")

step("A chooses: L4 press casts Renew")
H.pad("PADDRIGHT")
eq(Plain(picker.name), "Renew", "moved to Renew")
H.pad("PAD1")
check(not picker:IsShown(), "the picker closed")
check(screen:Focused() == l4press, "the cursor is back on the slot")
eq(Chords.Get("L4", "press"), "SPELL:139", "the slot")
eq(Plain(l4press.value), "Renew", "the slot shows the spell")
local before = #H.actions
H.key("F1", true)
H.key("F1", false)
check(#H.actions > before, "pressing L4 did something")
eq(LastAction().type, "spell", "a spell")
eq(LastAction().spell, 139, "Renew")

step("an item from the bags on L4 hold, with its count; held, it uses the item")
screen:SetFocus(l4hold)
H.pad("PAD3")
eq(picker.cat, 1, "an empty slot opens on the first list")
H.pad("PADRSHOULDER"); H.pad("PADRSHOULDER")
eq(Actions.CATEGORIES[picker.cat].key, "items", "RB twice: items")
-- Empty, Healing Potion, Hearthstone (bag order, once each; Linen Cloth has no use), then the trinket.
eq(#picker.items, 4, "Empty, two bag items, one equipped trinket")
eq(Plain(picker.items[2].count), "15", "the potion's count (three stacks of five)")
H.pad("PAD1")
eq(Chords.Get("L4", "hold"), "ITEM:929", "the slot")
before = #H.actions
H.key("F1", true)
H.key("F5", true) -- Steam's long-press key: L4 has been held long enough
H.key("F5", false)
H.key("F1", false)
eq(#H.actions, before + 1, "one action for the hold (the release does nothing more)")
eq(LastAction().type, "item", "an item")
eq(LastAction().item, "item:929", "the potion")

step("with a hold bound, L4's press fires on release")
before = #H.actions
H.key("F1", true)
eq(#H.actions, before, "nothing yet on the way down")
H.key("F1", false)
eq(LastAction().spell, 139, "Renew on release")

step("a macro on R4 hold")
screen:SetFocus(r4hold)
H.pad("PAD3")
for _ = 1, 3 do H.pad("PADRSHOULDER") end
eq(Actions.CATEGORIES[picker.cat].key, "macros", "RB three times: macros")
eq(#picker.items, 3, "Empty and both macros (account and character)")
H.pad("PAD1")
eq(Chords.Get("R4", "hold"), "MACRO:Heal focus", "the slot")
H.key("F2", true); H.key("F6", true); H.key("F6", false); H.key("F2", false)
eq(LastAction().type, "macro", "a macro")
eq(LastAction().macro, "Heal focus", "that macro")

step("B leaves a slot as it was; the picker opens on the list of what's bound, with it lit")
screen:SetFocus(l4hold)
H.pad("PAD3")
eq(Actions.CATEGORIES[picker.cat].key, "items", "opens on Items")
check(screen:Focused() == picker.items[2] and picker.items[2].selected:IsShown(), "on the bound item, lit")
H.pad("PADRIGHT")
H.pad("PAD2")
check(not picker:IsShown(), "closed")
check(screen.win:IsShown(), "and only the picker: the menu stays open")
eq(Chords.Get("L4", "hold"), "ITEM:929", "unchanged")

step("Empty clears a slot")
H.pad("PAD3")
screen:SetFocus(picker.items[1])
H.pad("PAD1")
eq(Chords.Get("L4", "hold"), nil, "cleared")
eq(Plain(l4hold.value), "Empty", "shows Empty")

step("in combat the grip still fires its spell")
H.combat(true)
check(not screen.win:IsShown(), "combat closed the menu")
before = #H.actions
H.key("F1", true); H.key("F1", false)
eq(#H.actions, before + 1, "fired")
eq(LastAction().spell, 139, "Renew")
H.combat(false)
check(not H.snippetErrors, "no errors inside secure snippets: " .. table.concat(H.snippetErrors or {}, " | "))
