-- Suggested game settings for playing on the Deck: a "Suggested settings" page in the DeckKit
-- menu with a toggle per setting and one action that applies them all. Turning one on remembers
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
}

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
table.insert(items, { type = "action", label = "Apply all suggested",
    hint = "Turns every suggestion on. Each one can be switched back on its own.",
    run = function()
        local n = 0
        for _, s in ipairs(SUGGESTED) do
            if GetCVar(s.cvar) ~= nil and not IsOn(s) then Set(s, true); n = n + 1 end
        end
        ns.Print(n == 0 and "All suggested settings were already on."
            or ("Applied " .. n .. " suggested setting" .. (n == 1 and "" or "s") .. "."))
    end })
table.insert(items, { type = "info", label = "Switching one off puts back what you had before." })
for _, item in ipairs(ns.Layout and ns.Layout.MenuItems or {}) do table.insert(items, item) end

DeckKit.Settings.Add("DeckHUD-Suggested", "|cffe0c060Suggested settings|r", items)
