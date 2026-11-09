-- DeckSundries: small controller extras that don't need an addon of their own.
--
--   Core.lua       settings
--   WandShoot.lua  Square fires your wand at an enemy instead of a melee swing
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffd9b38cDeckSundries|r")

local DEFAULTS = { wandShoot = true }

ns.db = {}
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    DeckSundriesDB = DeckSundriesDB or {}
    for k, v in pairs(DEFAULTS) do
        if DeckSundriesDB[k] == nil then DeckSundriesDB[k] = v end
    end
    ns.db = DeckSundriesDB
end)
