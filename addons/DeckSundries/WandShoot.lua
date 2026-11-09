-- Wand shoot: Square (X on the Deck, PAD3) fires your wand at an enemy instead of a melee swing.
--
-- Adapted from Improved Forever's WandShoot.lua (MIT License, Copyright (c) 2026 markg).
--
-- Square is the game's Interact: on an enemy it swings the melee weapon. With a wand in the
-- ranged slot this claims Square through DeckKit.Override while a living enemy is targeted, and
-- casts "!Shoot" (the "!" keeps a second press from stopping it). On anything else (loot, an NPC,
-- an object) Square stays the game's own press. It outranks DeckAngler's one-button fishing.
-- /deckkit wandshoot turns it on and off.
local _, ns = ...

local RANGED_SLOT = 18

local function Wielding()
    local id = GetInventoryItemID("player", RANGED_SLOT)
    if not id then return false end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local wand = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand or 19
    return class == weapon and subclass == wand
end

local function ShootName()
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo("Shoot")
    return info and info.name
end

local function Apply()
    local name = ns.db.wandShoot ~= false and Wielding() and ShootName()
    ns.Override.Set("PAD3", "wand", name and {
        when = "[harm,nodead]",
        priority = 20,
        macro = "/cast [harm,nodead] !" .. name,
    } or nil)
end

ns.On("PLAYER_LOGIN", Apply)
ns.On("PLAYER_EQUIPMENT_CHANGED", Apply)
ns.On("SPELLS_CHANGED", Apply)

ns.AddCommand("wandshoot", function()
    ns.db.wandShoot = ns.db.wandShoot == false
    Apply()
    ns.Print("Square fires your wand at enemies: " .. (ns.db.wandShoot and "on" or "off") .. ".")
end, "Square fires your wand at an enemy instead of a melee swing (on / off)")
