-- DeckKit.Actions: what each kind of id is called, looks like and does, and what the picker's lists hold, against
-- the harness's default character (a priest: four castable spells and a passive, potions, a hearthstone, linen,
-- a trinket worn, two macros).
local A = DeckKit.Actions

step("spells")
eq(A.Label("SPELL:2061"), "Flash Heal", "name")
eq(A.Icon("SPELL:2061"), "Interface\\Icons\\Spell_Holy_FlashHeal", "icon")
check(A.Available("SPELL:2061"), "known")
check(not A.Available("SPELL:999"), "a spell this character doesn't know isn't available")
eq(A.Attributes("SPELL:2061").type, "spell", "cast by a secure button")

step("items from the bags: by item, counted across stacks")
eq(A.Label("ITEM:929"), "Healing Potion", "name")
eq(A.Count("ITEM:929"), 15, "three stacks of five")
check(A.Available("ITEM:929"), "carried")
H.world.Set({ bags = { [0] = { 6948 } } })
eq(A.Count("ITEM:929"), 0, "none left")
check(not A.Available("ITEM:929"), "so not available")
H.world.Reset()
eq(A.Attributes("ITEM:929").item, "item:929", "used by item id")

step("equipped slots")
eq(A.Label("SLOT:13"), "Top trinket: Burst of Knowledge", "named by slot and what's in it")
check(A.Available("SLOT:13"), "the trinket has a use")
check(not A.Available("SLOT:14"), "an empty slot hasn't")
eq(A.Attributes("SLOT:13").item, "13", "used by slot number")

step("macros, by name")
eq(A.Label("MACRO:Mount"), "Mount", "name")
eq(A.Icon("MACRO:Mount"), "Interface\\Icons\\Ability_Mount_RidingHorse", "icon")
check(A.Available("MACRO:Heal focus"), "exists")
check(not A.Available("MACRO:Gone"), "a deleted macro doesn't")

step("offers and action bar buttons")
A.Offer("TEST_PEEK", { label = "Test peek", run = function() end })
eq(A.Kind("TEST_PEEK"), "run", "an offer with run")
eq(A.Label("TEST_PEEK"), "Test peek", "its label")
eq(A.CategoryOf("TEST_PEEK"), "deckkit", "listed under DeckKit")
local kind, frame = A.Kind("MULTIACTIONBAR1BUTTON3")
eq(kind, "mirror", "a bar button is mirrored"); eq(frame, "MultiBarBottomLeftButton3", "from its frame")
eq(A.Kind("NOT_A_THING"), nil, "an unknown binding can't run")

step("the picker's lists")
local function ids(cat)
    local out = {}
    for _, e in ipairs(A.List(cat)) do out[#out + 1] = e.id end
    return table.concat(out, " ")
end
eq(ids("spells"), "SPELL:2061 SPELL:139 SPELL:17 SPELL:585", "castable spells in book order, no passives")
eq(ids("items"), "ITEM:929 ITEM:6948 SLOT:13", "usable bag items once each, then worn ones")
eq(ids("macros"), "MACRO:Heal focus MACRO:Mount", "account macros, then the character's")
eq(#A.List("bars"), 60, "five bars of twelve")
check(ids("deckkit"):find("TEST_PEEK", 1, true), "offers")

step("the grip chords' list for deckctl keeps its shape")
local choices = DeckKit.Chords.Choices()
eq(choices[1][1], false, "Nothing first"); eq(choices[1][2], "Nothing", "named")
local found
for _, c in ipairs(choices) do if c[1] == "ITEM:929" then found = c[2] end end
eq(found, "Healing Potion", "items are in it now")
