-- Suggested game settings for playing on the Deck: a "Suggested settings" page in the DeckKit
-- menu with a toggle per setting and one action that applies them all, with the suggested layout. Turning one on remembers
-- what it was; turning it off puts that back (or the game's usual value).
--
-- Add a suggestion by adding a row to SUGGESTED: the CVar, the suggested value, the value to use
-- when switched off if nothing was remembered, and the words for the menu.
local _, ns = ...

local SUGGESTED = {
    { cvar = "chatStyle", value = "classic", off = "im",
      label = "Classic chat style",
      hint = "Enter sends a chat message and closes the input box, dictated messages included. "
          .. "Turned on, it works particularly well with Decktation." },
    { cvar = "autoLootDefault", value = "1", off = "0",
      label = "Auto loot",
      hint = "Opening a corpse takes everything, with no picking items one by one." },
    { cvar = "GamePadShowPersistentInputLegend", value = "0", off = "1",
      label = "Hide the controller button legend",
      hint = "The game's always-on list of what each button does." },
    { cvar = "useUiScale", value = "0", off = "1",
      label = "Game's own UI scale",
      hint = "No custom UI scale. The suggested layout's positions are measured at the game's own scale." },
}

-- The grips' keys (DeckKit.GRIPS: F1-F8) with the game's own bindings on them: F1-F5 target you and your
-- party by default. DeckKit's grip bindings win anyway; clearing them keeps a stray F-key from targeting
-- someone if grip chords are ever off.
local function GripKeysBound()
    local list = {}
    for _, g in ipairs(DeckKit.GRIPS or {}) do
        for _, key in ipairs({ g.key, g.long }) do
            local action = GetBindingAction(key)
            if action and action ~= "" then list[#list + 1] = key end
        end
    end
    return list
end

local function ClearGripKeys()
    if InCombatLockdown() then return 0 end
    local keys = GripKeysBound()
    for _, key in ipairs(keys) do SetBinding(key) end
    if #keys > 0 then SaveBindings(GetCurrentBindingSet()) end
    return #keys
end

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

local function IsOn(s) return tostring(GetCVar(s.cvar)) == s.value end

local function Set(s, on)
    ns.db.prevCVars = ns.db.prevCVars or {}
    local prev = ns.db.prevCVars
    if on then
        if not IsOn(s) then prev[s.cvar] = GetCVar(s.cvar) end
        SetCVar(s.cvar, s.value)
    else
        local back = prev[s.cvar]
        if back == nil or tostring(back) == s.value then back = s.off end
        SetCVar(s.cvar, back)
        prev[s.cvar] = nil
    end
end

local items = { { type = "section", tab = "Screen", label = "Suggested settings", order = 1 } }
for _, s in ipairs(SUGGESTED) do
    if GetCVar(s.cvar) ~= nil then -- only settings this client has
        table.insert(items, { type = "toggle", label = s.label, hint = s.hint,
            get = function() return IsOn(s) end,
            set = function(on) Set(s, on) end })
    end
end
-- One button for a first install: every suggested setting above, and the suggested Edit Mode layout
-- (Layout.lua: unit frames, party, focus, raid, buffs, the compact crossbar), then a reload.
table.insert(items, { type = "toggle", label = "Free the grip keys (F1-F8)",
    hint = "Clears the game's own key bindings on the keys the back grips send (F1-F5 target you and "
        .. "your party by default). Can't be undone from here: rebind them in Key Bindings.",
    get = function() return #GripKeysBound() == 0 end,
    set = function(on)
        if not on then return ns.Print("Rebind F1-F8 yourself in Key Bindings if you want them back.") end
        local n = ClearGripKeys()
        ns.Print(n == 0 and "The grip keys were already free." or ("Cleared the game's bindings on " .. n .. " grip key" .. (n == 1 and "" or "s") .. "."))
    end })

-- Everything suggested in one go: the settings above, the grip keys, the layout, then a reload. Also
-- the welcome window's first step (DeckKit/Setup.lua). Nothing changes unless the layout can be saved.
local function ApplyEverything()
    local can, why = ns.Layout.CanChange()
    if not can then ns.Print("Nothing changed: " .. why .. ".") return end
    local n = 0
    for _, s in ipairs(SUGGESTED) do
        if GetCVar(s.cvar) ~= nil and not IsOn(s) then Set(s, true); n = n + 1 end
    end
    local keys = ClearGripKeys()
    local ok, info = ns.Layout.ApplySuggested()
    if keys > 0 then ns.Print("Cleared the game's bindings on " .. keys .. " grip key" .. (keys == 1 and "" or "s") .. ".") end
    local settings = n .. " suggested setting" .. (n == 1 and "" or "s")
    if ok then
        ns.db.suggestedApplied = true
        ns.ReloadSoon("Applied " .. settings .. " and the suggested layout.")
    else
        ns.Print("Applied " .. settings .. "; layout not changed: " .. info .. ".")
    end
end

-- For the welcome window: why the layout can't be changed, in words for that window (nil when it can).
local function LayoutProblem()
    local info, layout = ns.Layout.Active()
    if info and not layout then
        return "Your Edit Mode layout is one of the game's presets, which can't be changed. Open Edit Mode "
            .. "(game menu > Edit Mode), copy it to a new layout of your own, then come back here."
    end
end

local EVERYTHING_HINT = "Turns every suggestion above on, frees the grip keys, and applies the suggested layout: "
    .. "your frame and the target's, the party frames in a row between them, the focus frame centered, raid "
    .. "frames top-left and buffs under the status bar, the compact crossbar near the bottom. Backs up your "
    .. "Edit Mode layout first (one undo), then reloads."

table.insert(items, { type = "action", label = "Apply everything suggested", keepOpen = true,
    hint = EVERYTHING_HINT, run = ApplyEverything })

if DeckKit.Setup then
    DeckKit.Setup.AddStep({
        id = "suggested", order = 10,
        title = "Suggested settings and layout",
        text = "Classic chat, auto loot, no button legend, the game's own UI scale, and every frame placed for "
            .. "the Deck's screen. Also clears the game's bindings on F1-F8 (the grips' keys). Your layout is "
            .. "backed up first (Screen > Suggested settings > Undo the last layout change), then the UI reloads.",
        done = function() return ns.db.suggestedApplied == true end,
        problem = LayoutProblem,
        action = { label = "Apply everything suggested", verb = "Apply", reloads = true, run = ApplyEverything,
                   doneReason = "change single settings in Screen > Suggested settings" },
    })
end
