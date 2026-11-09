-- One-button fishing: with a fishing pole equipped, Square (X on the Deck, PAD3) casts Fishing.
--
-- Claims Square through DeckKit.Override, out of combat and only while you aren't already
-- channeling. Once the line is out, X is the game's Interact again, so it clicks the bobber.
-- Wand shoot (DeckSundries) outranks it while a living enemy is targeted.
-- /deckkit fish button on|off.
local _, ns = ...

local MAIN_HAND = 16

local function FishingName()
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7620)
    if not name and GetSpellInfo then name = GetSpellInfo(7620) end
    return name or "Fishing"
end

function ns.OneButtonApply()
    local db = DeckAnglerDB or {}
    local on = db.oneButton ~= false and ns.PoleEquipped()
    ns.Override.Set("PAD3", "fish", on and {
        when = "[nocombat,nochanneling]",
        priority = 10,
        macro = "/cast " .. FishingName(),
    } or nil)
end

ns.On("PLAYER_LOGIN", ns.OneButtonApply)
ns.On("PLAYER_ENTERING_WORLD", ns.OneButtonApply)
ns.On("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if slot == MAIN_HAND then ns.OneButtonApply() end
end)
