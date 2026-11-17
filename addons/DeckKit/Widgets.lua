-- DeckKit.Widgets: layouts kept by name (a haul counter, an XP-per-hour line...), made by anyone, an assistant
-- included, and run with no one's help after: each saved widget is an action (WIDGET:<name>) a grip slot or a
-- touch grid cell can toggle. Widgets are plain layout specs (Layout.lua; live numbers from DeckKit.Measures), so
-- nothing in one is run as code.
--
--   Widgets.Save(name, spec, opts)   opts.scope "account" (every character) or the character's own (default);
--                                    opts.mark: a DeckKit.Ledger mark set afresh each time it opens (its
--                                    numbers count from then), in the same scope
--   Widgets.Delete(name [, scope])   (no scope: the character's own if there is one, else the account's)
--   Widgets.Get(name)                the widget: { spec, mark, scope }; a character's own wins over the account's
--   Widgets.List()                   { { name, scope, shown, saved }, ... } sorted by name: every saved widget, and
--                                    any shown without saving (scope nil, saved false) while it's up
--   Widgets.Show(name) / Hide(name) / Toggle(name) / Shown(name)   as a tracker, stacked at the top left
--   Widgets.ShowSpec(name, spec, opts)   one not saved (yet): shown the same way, opts.mark / opts.scope as Save
--   Widgets.OnChange(fn)             fn() after any save, delete, show or hide
-- Saved in DeckKitDB.widgets (account) and DeckKitCharDB.widgets (this character).
local _, ns = ...

local W = {}
ns.Widgets = W
local UI, Ledger, Actions = ns.UI, ns.Ledger, ns.Actions

local MAX_NAME = 40
local account, mine -- the saved tables, from login
local unsaved = {} -- name -> true: shown with ShowSpec and still up (not saved; gone at a reload)
local listeners = {}
function W.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

local function Store(scope) return scope == "account" and account or mine end
local function Tracker(name) return "widget:" .. name end
local function ActionID(name) return "WIDGET:" .. name end
-- A layout spec that will build: a table with a type (Layout.lua shows anything it doesn't know as "?").
local function Valid(spec) return type(spec) == "table" and type(spec.type) == "string" end

function W.Get(name)
    local w = mine and mine[name]
    if w then return w, "character" end
    w = account and account[name]
    if w then return w, "account" end
end

function W.Shown(name) return UI.TrackerShown(Tracker(name)) end

function W.Show(name)
    local w, scope = W.Get(name)
    if not w then return false end
    if w.mark then Ledger.Mark(w.mark, scope == "account" and "account" or nil) end
    UI.ShowTracker(w.spec, { name = Tracker(name), fade = false })
    Changed()
    return true
end

function W.ShowSpec(name, spec, opts)
    opts = opts or {}
    if type(name) ~= "string" or name == "" or not Valid(spec) then return nil, "a name and a layout" end
    if type(opts.mark) == "string" then Ledger.Mark(opts.mark, opts.scope == "account" and "account" or nil) end
    UI.ShowTracker(spec, { name = Tracker(name), fade = false })
    if not W.Get(name) then unsaved[name] = true end
    Changed()
    return true
end

function W.Hide(name)
    UI.HideTracker(Tracker(name))
    unsaved[name] = nil
    Changed()
end

function W.Toggle(name)
    if W.Shown(name) then W.Hide(name) else W.Show(name) end
end

local function Offer(name)
    Actions.OfferNow(ActionID(name), { label = name, run = function(down) if down then W.Toggle(name) end end })
end

function W.Save(name, spec, opts)
    opts = opts or {}
    if type(name) ~= "string" or name:gsub("%s", "") == "" or #name > MAX_NAME or name:find("[%c|]") then
        return nil, "a name of 1-" .. MAX_NAME .. " characters"
    end
    if not Valid(spec) then return nil, "not a layout" end
    if not (account and mine) then return nil, "not loaded yet" end
    local scope = opts.scope == "account" and "account" or "character"
    -- One widget per name: saving it in one place takes it out of the other.
    Store(scope == "account" and "character" or "account")[name] = nil
    Store(scope)[name] = { spec = spec, mark = type(opts.mark) == "string" and opts.mark or nil }
    unsaved[name] = nil
    Offer(name)
    if W.Shown(name) then UI.ShowTracker(spec, { name = Tracker(name), fade = false }) end
    Changed()
    return true
end

function W.Delete(name, scope)
    if not scope then scope = (mine and mine[name]) and "character" or "account" end
    local store = Store(scope)
    if not (store and store[name]) then return nil, "no widget " .. tostring(name) end
    store[name] = nil
    W.Hide(name)
    if not W.Get(name) then Actions.Withdraw(ActionID(name)) end
    Changed()
    return true
end

function W.List()
    local out = {}
    for _, pair in ipairs({ { mine, "character" }, { account, "account" } }) do
        for name in pairs(pair[1] or {}) do
            if pair[2] == "character" or not (mine and mine[name]) then
                out[#out + 1] = { name = name, scope = pair[2], shown = W.Shown(name), saved = true }
            end
        end
    end
    for name in pairs(unsaved) do
        if W.Shown(name) then out[#out + 1] = { name = name, shown = true, saved = false } else unsaved[name] = nil end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

ns.On("PLAYER_LOGIN", function()
    DeckKitDB = DeckKitDB or {}
    DeckKitCharDB = DeckKitCharDB or {}
    DeckKitDB.widgets = DeckKitDB.widgets or {}
    DeckKitCharDB.widgets = DeckKitCharDB.widgets or {}
    account, mine = DeckKitDB.widgets, DeckKitCharDB.widgets
    for _, w in ipairs(W.List()) do Offer(w.name) end
end)
