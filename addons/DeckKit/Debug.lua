-- Debug lines go to DeckDev, the dev-only addon from ~/Projects/AddonTools (its log, read off the
-- screen by deckctl). Without DeckDev installed, debug calls do nothing.
--
--   ns.Debug("text", ...)        in the core: "DeckKit: text ..."
--   ns.Debug(...) in a module    prefixed with the module's folder name (set up by NewModule)
local _, ns = ...

-- A log function for source; a no-op when DeckDev isn't loaded. DeckDev's own loggers cost
-- nothing while its log is off.
function ns.Logger(source)
    if DeckDev and DeckDev.Logger then return DeckDev.Logger(source) end
    return function() end
end

ns.Debug = ns.Logger("DeckKit")
