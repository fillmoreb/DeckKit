-- Settings registry for the DeckKit menu (Menu.lua). Modules add rows; the menu groups them by tab
-- and section, so related settings from different addons sit together.
--
--   ns.AddSettings({
--       { type = "section", tab = "Screen", label = "Chat", order = 2 },  -- where the rows below go
--       { type = "toggle", label = "Wand shoot", hint = "...", get = function() ... end, set = function(on) ... end },
--       { type = "choice", label = "Idle reminder", values = { { false, "Off" }, { 60, "1 min" } }, get, set },
--       { type = "range",  label = "Font size", min = 12, max = 40, step = 2, format = fn(v) -> text, get, set },
--       { type = "action", label = "Add a waypoint", verb = "Add", run = function() ... end },
--         (keepOpen = true runs it straight from the A press instead of after closing the menu:
--          needed for anything Forever only allows from a key press, like ReloadUI)
--       { type = "binding", action = "WAYPAD_ADD" },          -- a back-grip binding (unused: the grips are paddle chords now)
--       { type = "status", label = "Dictation signals", get = function() return text, color end },
--       { type = "info",   label = "Plain text that explains something." },
--   })
--
-- Tabs: Controls, Screen, Map & travel, Healing, Tools. A section row sets the tab/section for the
-- rows after it (in that call); any row can also carry its own tab/section. Without one, rows go to
-- Tools under the addon's name. order sorts sections within a tab (default 5).
-- get/set read and write the module's own saved settings; the menu only calls them while it's open
-- (after login), so saved variables are loaded by then. hint: shown beside the list for the
-- focused row.
local _, ns = ...

local Settings = { rows = {}, sections = {} }
ns.Settings = Settings

Settings.TABS = { "Controls", "Screen", "Map & travel", "Healing", "Tools" }

local function Section(tab, label, order, title)
    for _, s in ipairs(Settings.sections) do
        if s.tab == tab and s.label == label then
            if order then s.order = order end
            return s
        end
    end
    local s = { tab = tab, label = label, order = order or 5, rows = {}, title = title, seq = #Settings.sections }
    table.insert(Settings.sections, s)
    return s
end

-- name: the addon; title: its colored title (shown beside the list as "From ...").
function Settings.Add(name, title, items)
    local tab, label, order = "Tools", (title or name), nil
    for _, item in ipairs(items) do
        if item.type == "section" then
            tab, label, order = item.tab or tab, item.label or label, item.order
            Section(tab, label, order, title)
        else
            item.from = item.from or title
            local s = Section(item.tab or tab, item.section or label, item.section and item.sectionOrder or order, title)
            table.insert(s.rows, item)
        end
    end
end

-- Sections of one tab, in order.
function Settings.SectionsOf(tab)
    local list = {}
    for _, s in ipairs(Settings.sections) do
        if s.tab == tab and #s.rows > 0 then list[#list + 1] = s end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
    return list
end
