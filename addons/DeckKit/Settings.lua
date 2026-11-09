-- Settings registry for the DeckKit menu (Menu.lua). Each module adds rows to its own page:
--
--   ns.AddSettings({
--       { type = "toggle", label = "Wand shoot", hint = "...", get = function() ... end, set = function(on) ... end },
--       { type = "choice", label = "Idle reminder", values = { { false, "Off" }, { 60, "1 min" } }, get, set },
--       { type = "range",  label = "Font size", min = 12, max = 40, step = 2, format = fn(v) -> text, get, set },
--       { type = "action", label = "Add a waypoint", run = function() ... end },
--       { type = "info",   label = "Bind it in Key Bindings > DeckKit." },
--   })
--
-- get/set read and write the module's own saved settings; the menu only calls them while it's
-- open (after login), so saved variables are loaded by then. hint: a line shown under the list
-- for the selected row. Calling AddSettings again appends to the same page.
local _, ns = ...

local Settings = { pages = {} }
ns.Settings = Settings

function Settings.Add(name, title, items)
    local page
    for _, p in ipairs(Settings.pages) do
        if p.name == name then page = p end
    end
    if not page then
        page = { name = name, title = title, items = {} }
        table.insert(Settings.pages, page)
    end
    for _, item in ipairs(items) do table.insert(page.items, item) end
end
