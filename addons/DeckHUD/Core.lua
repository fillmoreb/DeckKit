-- DeckHUD: interface tweaks for playing on the Deck. One addon, a file per part:
--
--   Core.lua         the module, its settings (DeckHUDDB) and their defaults
--   Minimap.lua      the minimap: square, in the top-right corner, without the clutter around it
--   StatusBar.lua    the strip across the top with readings, and an XP line
--   Compass.lua      the compass in the middle of the status bar
--   Chat.lua         a thin chat frame tucked into the bottom-left
--   Layout.lua       Edit Mode layouts through C_EditMode (with backups), and the party/raid LB prompt
--   Focus.lua        the focus frame, slimmed down for healing; FocusAuras.lua its aura row
--   ActionBars.lua   macro names on action buttons
--   LootRolls.lua    loot rolls as a compact list
--   Tooltip.lua      the mouseover tooltip as a see-through card at the top
--   Suggested.lua    suggested game settings, a page of the DeckKit menu
--
-- Settings live in the DeckKit menu (double-tap Menu, or /deckkit), mostly under Screen.
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffe0c060DeckHUD|r")

-- The settings: an empty table until DeckHUDDB loads (files read ns.db each time, never keep a copy).
ns.db = {}

-- Each file hands its defaults over as it loads; they fill in what DeckHUDDB doesn't have yet.
local defaults = {}
function ns.Defaults(t)
    for k, v in pairs(t) do defaults[k] = v end
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    DeckHUDDB = DeckHUDDB or {}
    for k, v in pairs(defaults) do
        if DeckHUDDB[k] == nil then DeckHUDDB[k] = v end
    end
    -- Development dumps earlier versions saved at every login (deckctl inspect does this now).
    DeckHUDDB.dump, DeckHUDDB.layoutDump = nil, nil
    ns.db = DeckHUDDB
end)
