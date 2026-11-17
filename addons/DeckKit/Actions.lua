-- DeckKit.Actions: what a player can bind, wherever they bind it (grip chord slots, PadGrid's cells...).
--
-- An action is an id string, saved as is:
--   SPELL:<id>                  a spell from the spellbook
--   ITEM:<id>                   an item with a use, from your bags (by item, so a stack moving or running out keeps it)
--   SLOT:<n>                    what's equipped in inventory slot n, if it has a use (13, 14: the trinkets)
--   MACRO:<name>                one of your macros
--   ACTIONBUTTON<n>, MULTIACTIONBAR<b>BUTTON<n>   an action bar button, run as the button would
--   anything offered            DeckKit's own and modules' actions (Actions.Offer below), by binding name
-- How it runs:
--   attributes   a secure button set up with Actions.Attributes(id) does it (spells, items, slots, macros)
--   mirror       a secure button's own attributes are copied onto yours as it fires (action bar buttons, and
--                offers with mirror = "FrameName", like QuestPad's button)
--   run          an offer's function, run(down), from insecure code: fine for DeckKit's own windows and peeks
-- The grip chords (Chords.lua) were first; their saved slots are ids from this same list.
local _, ns = ...

local Actions = {}
ns.Actions = Actions

------------------------------------------------------------------------
-- Offers
------------------------------------------------------------------------

local offers = {}
local listeners = {}

-- Called when an offer is added or renamed (lists and the cheat sheet follow).
function Actions.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

-- opts: label (else the binding's own name), icon (a texture), mirror = secure button name, run = fn(down).
function Actions.Offer(id, opts) offers[id] = opts or {} end

-- An action that just happens once, when it fires.
function Actions.OfferPress(id, fn, label, icon)
    offers[id] = { label = label, icon = icon, run = function(down) if down then fn() end end }
end

-- A new name for an offered action (for an offer whose name another addon knows better).
function Actions.SetLabel(id, label)
    if not offers[id] then return end
    offers[id].label = label
    Changed()
end

function Actions.Offered(id) return offers[id] end

------------------------------------------------------------------------
-- What an id is
------------------------------------------------------------------------

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton" }

-- The action bar button an id names: its frame name, or nil.
local function BarButton(id)
    local n = id:match("^ACTIONBUTTON(%d+)$")
    if n then return BARS[1] .. n end
    local bar, b = id:match("^MULTIACTIONBAR(%d)BUTTON(%d+)$")
    if bar and BARS[tonumber(bar) + 1] then return BARS[tonumber(bar) + 1] .. b end
end

-- kind, ref: "spell", spellID | "item", itemID | "slot", slot | "macro", name | "mirror", frame name | "run" | nil.
function Actions.Kind(id)
    if type(id) ~= "string" then return nil end
    local n = id:match("^SPELL:(%d+)$")
    if n then return "spell", tonumber(n) end
    n = id:match("^ITEM:(%d+)$")
    if n then return "item", tonumber(n) end
    n = id:match("^SLOT:(%d+)$")
    if n then return "slot", tonumber(n) end
    local name = id:match("^MACRO:(.+)$")
    if name then return "macro", name end
    local o = offers[id]
    if o and o.mirror then return "mirror", o.mirror end
    if o and o.run then return "run" end
    local frame = BarButton(id)
    if frame then return "mirror", frame end
end

function Actions.CanRun(id) return Actions.Kind(id) ~= nil end

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return name
end

local SLOT_NAMES = { [13] = "Top trinket", [14] = "Bottom trinket", [16] = "Main hand", [17] = "Off hand",
    [18] = "Ranged", [1] = "Head", [2] = "Neck", [6] = "Waist", [10] = "Hands", [11] = "Top ring", [12] = "Bottom ring",
    [15] = "Back", [3] = "Shoulder", [5] = "Chest", [7] = "Legs", [8] = "Feet", [9] = "Wrist" }

function Actions.Label(id)
    local kind, ref = Actions.Kind(id)
    if kind == "spell" then return (C_Spell.GetSpellName(ref)) or ("Spell " .. ref) end
    if kind == "item" then return ItemName(ref) or ("Item " .. ref) end
    if kind == "slot" then
        local item = GetInventoryItemID("player", ref)
        local where = SLOT_NAMES[ref] or ("Slot " .. ref)
        return item and (where .. ": " .. (ItemName(item) or "...")) or where
    end
    if kind == "macro" then return ref end
    local o = offers[id]
    return (o and o.label) or _G["BINDING_NAME_" .. tostring(id)] or tostring(id)
end

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_OFFER_ICON = "Interface\\Icons\\INV_Misc_Gear_01"

-- The texture to show for an id (never nil).
function Actions.Icon(id)
    local kind, ref = Actions.Kind(id)
    if kind == "spell" then return C_Spell.GetSpellTexture(ref) or QUESTION end
    if kind == "item" then return C_Item.GetItemIconByID(ref) or QUESTION end
    if kind == "slot" then return GetInventoryItemTexture("player", ref) or QUESTION end
    if kind == "macro" then
        local _, icon = GetMacroInfo(ref)
        return icon or QUESTION
    end
    local o = offers[id]
    if o and o.icon then return o.icon end
    local frame = BarButton(tostring(id))
    if frame then
        local b = _G[frame]
        local slot = b and (b.action or (b.GetAttribute and b:GetAttribute("action")))
        return slot and GetActionTexture(slot) or QUESTION
    end
    if o and o.mirror then
        local b = _G[o.mirror]
        local tex = b and b.icon and b.icon.GetTexture and b.icon:GetTexture()
        if tex then return tex end
    end
    return DEFAULT_OFFER_ICON
end

-- How many you have, for items (nil for anything else).
function Actions.Count(id)
    local kind, ref = Actions.Kind(id)
    if kind == "item" then return C_Item.GetItemCount(ref, false, true) or 0 end
end

-- Whether it can be used now: a spell you know, an item you carry, a slot with something usable in it, a macro
-- that exists. Offers and action bar buttons always can.
function Actions.Available(id)
    local kind, ref = Actions.Kind(id)
    if not kind then return false end
    if kind == "spell" then return C_SpellBook.IsSpellKnown(ref) ~= false end
    if kind == "item" then return (Actions.Count(id) or 0) > 0 end
    if kind == "slot" then
        local item = GetInventoryItemID("player", ref)
        return item ~= nil and C_Item.GetItemSpell(item) ~= nil
    end
    if kind == "macro" then return GetMacroIndexByName(ref) > 0 end
    return true
end

-- The attributes a SecureActionButton needs to do it, or nil (mirror and run aren't attributes).
function Actions.Attributes(id)
    local kind, ref = Actions.Kind(id)
    if kind == "spell" then return { type = "spell", spell = ref } end
    if kind == "item" then return { type = "item", item = "item:" .. ref } end
    if kind == "slot" then return { type = "item", item = tostring(ref) } end
    if kind == "macro" then return { type = "macro", macro = ref } end
end

------------------------------------------------------------------------
-- What can be bound: the picker's lists
------------------------------------------------------------------------

Actions.CATEGORIES = {
    { key = "deckkit", label = "DeckKit" },
    { key = "spells", label = "Spells" },
    { key = "items", label = "Items" },
    { key = "macros", label = "Macros" },
    { key = "bars", label = "Action bars" },
}

local function Entry(id) return { id = id, label = Actions.Label(id), icon = Actions.Icon(id) } end

local lists = {}

lists.deckkit = function()
    local out = {}
    for id in pairs(offers) do out[#out + 1] = Entry(id) end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- The spellbook's castable spells, in book order.
lists.spells = function()
    local out = {}
    local book = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(i, book)
            if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and item.spellID then
                out[#out + 1] = Entry("SPELL:" .. item.spellID)
            end
        end
    end
    return out
end

-- What you carry that has a use, once each, in bag order; then what you wear that has one.
lists.items = function()
    local out, seen = {}, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local item = C_Container.GetContainerItemID(bag, slot)
            if item and not seen[item] and C_Item.GetItemSpell(item) then
                seen[item] = true
                out[#out + 1] = Entry("ITEM:" .. item)
            end
        end
    end
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        local item = GetInventoryItemID("player", slot)
        if item and C_Item.GetItemSpell(item) then out[#out + 1] = Entry("SLOT:" .. slot) end
    end
    return out
end

-- Account macros, then this character's.
lists.macros = function()
    local out = {}
    local account, char = GetNumMacros()
    local function add(i)
        local name = GetMacroInfo(i)
        if name then out[#out + 1] = Entry("MACRO:" .. name) end
    end
    for i = 1, account or 0 do add(i) end
    local base = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
    for i = 1, char or 0 do add(base + i) end
    return out
end

lists.bars = function()
    local out = {}
    for b = 1, 12 do out[#out + 1] = Entry("ACTIONBUTTON" .. b) end
    for bar = 1, 4 do
        for b = 1, 12 do out[#out + 1] = Entry("MULTIACTIONBAR" .. bar .. "BUTTON" .. b) end
    end
    return out
end

-- { { id, label, icon }, ... } for one category (Actions.CATEGORIES' keys).
function Actions.List(category)
    local fn = lists[category]
    return fn and fn() or {}
end

-- The category an id is listed under.
function Actions.CategoryOf(id)
    local kind = Actions.Kind(id)
    if kind == "spell" then return "spells" end
    if kind == "item" or kind == "slot" then return "items" end
    if kind == "macro" then return "macros" end
    if offers[id] then return "deckkit" end
    if kind == "mirror" then return "bars" end
end
