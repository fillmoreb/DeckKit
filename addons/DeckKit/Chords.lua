-- Grip chords: the four back grips, alone or together, pressed or held, each a slot for an action.
--
-- Steam sends plain keys only (deck-setup/make-chord-layout.py): a grip's own key while it's held,
-- and a second key once it has been held for the long-press time (400 ms by default):
--   L4 = F1 / F5    R4 = F2 / F6    L5 = F3 / F7    R5 = F4 / F8     (ns.GRIPS, in Core.lua)
-- Everything else is decided here, in secure code, so a slot can cast and use items in combat:
--   chord   every grip that was down together (L4, L4+L5, L4+R4+L5+R5... 15 in all)
--   press   fires when the first grip of the chord lets go. If nothing could follow (no hold on
--           that chord, and no bigger chord containing it has anything bound), it fires the moment
--           the chord is complete instead, so a plain grip press has no wait.
--   hold    fires when the long key of the grip pressed LAST arrives: every grip in the chord has
--           then been held for the long-press time. The release then does nothing more.
-- Restricted code has no clock, which is why the hold's timing comes from Steam, and why there is
-- no double-tap.
--
-- A slot holds a binding name, or "SPELL:<id>" for a spell from the spellbook. How it runs:
--   spell   cast by the grip button itself (secure)
--   mirror  a secure button's attributes are copied onto the grip button as it fires (action bar
--           buttons, QuestPad's button: anything ns.Chords.Offer(id, { mirror = "FrameName" }) names)
--   run     an offer's own function, run(down), from an insecure hook: fine for DeckKit's own
--           actions (peeks, windows) at any time, even in combat. A held slot gets its "down" when
--           it fires and its "up" when the chord lets go. (Addons can't call RunBinding, so a
--           binding needs an offer to be usable in a slot.)
local _, ns = ...

local Chords = {}
ns.Chords = Chords

Chords.GRIPS = ns.GRIPS
local GRIPS = Chords.GRIPS

-- The 15 chords, singles first, in grip order: "L4", "R4", ..., "L4+R4", ..., "L4+R4+L5+R5".
Chords.LIST = {}
for size = 1, 4 do
    for mask = 1, 15 do
        local parts = {}
        for j = 1, 4 do
            if bit.band(mask, 2 ^ (j - 1)) > 0 then parts[#parts + 1] = GRIPS[j].name end
        end
        if #parts == size then table.insert(Chords.LIST, table.concat(parts, "+")) end
    end
end

-- Attributes a mirrored button's action lives in.
local MIRROR = { "type", "action", "spell", "item", "macro", "macrotext", "unit", "target-slot", "clickbutton" }

------------------------------------------------------------------------
-- Offers: what a slot can hold, and how it runs
------------------------------------------------------------------------

-- What a slot can hold and how it runs live in DeckKit.Actions (Actions.lua), shared with every other place that
-- binds an action. These names stay for the modules that call them.
local Actions = ns.Actions
Chords.Offer = Actions.Offer
Chords.OfferPress = Actions.OfferPress
Chords.Label = function(id) if id then return Actions.Label(id) end end
Chords.CanRun = Actions.CanRun

-- How a slot runs in the secure snippet: "attrs" (the grip button is set up as Actions.Attributes says: spells,
-- items, equipped slots, macros), "mirror" + frame name, "run", or nil (nothing can run it).
local function HowToRun(id)
    local kind, ref = Actions.Kind(id)
    if kind == "spell" or kind == "item" or kind == "slot" or kind == "macro" then return "attrs" end
    if kind == "mirror" then return "mirror", ref end
    if kind == "run" then return "run" end
end

------------------------------------------------------------------------
-- Slots: the account's (DeckKitDB.chords = { ["L4+L5"] = { press = id, hold = id } }), and on top of
-- them each character's own changes (DeckKitCharDB.chords, the same shape; false = Nothing on this
-- character), for things like class spells. Which a change goes to is the "Slot changes apply to"
-- choice (DeckKitCharDB.chordScope: "all", the default, or "char").
------------------------------------------------------------------------

local function CharSlots()
    DeckKitCharDB = DeckKitCharDB or {}
    DeckKitCharDB.chords = DeckKitCharDB.chords or {}
    return DeckKitCharDB.chords
end

-- This character's own setting for a slot: an id, false (Nothing here), or nil (none: the account's).
function Chords.Own(chord, gesture)
    local c = DeckKitCharDB and DeckKitCharDB.chords and DeckKitCharDB.chords[chord]
    if c then return c[gesture] end
end

function Chords.Get(chord, gesture)
    local own = Chords.Own(chord, gesture)
    if own ~= nil then return own or nil end
    local c = ns.db.chords and ns.db.chords[chord]
    return c and c[gesture]
end

Chords.GESTURES = { "press", "hold" }

-- The first slot set to action `id` (chord order, press before hold): chord, gesture; nil when none is
-- or chords are off. For showing a chord on what it does (QuestPad's button), as a key shows on a button.
function Chords.Find(id)
    if not Chords.Enabled() then return end
    for _, chord in ipairs(Chords.LIST) do
        for _, gesture in ipairs(Chords.GESTURES) do
            if Chords.Get(chord, gesture) == id then return chord, gesture end
        end
    end
end

function Chords.Scope() return DeckKitCharDB and DeckKitCharDB.chordScope == "char" and "char" or "all" end

local Apply -- below

-- Called after any slot changes, or chords are turned on or off (the cheat sheet follows them).
local listeners = {}
function Chords.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

-- A new name for an offered action (the cheat sheet and menu follow): Actions.SetLabel.
Chords.SetLabel = Actions.SetLabel
Actions.OnChange(function() Changed() end)

local function Store(t, chord, gesture, v)
    local c = t[chord] or {}
    c[gesture] = v
    t[chord] = next(c) ~= nil and c or nil
end

-- Sets a slot (id, or nil for Nothing), for every character or just this one by the scope choice.
function Chords.Set(chord, gesture, id)
    ns.db.chords = ns.db.chords or {}
    local mine = CharSlots()
    if Chords.Scope() == "char" then
        local account = ns.db.chords[chord] and ns.db.chords[chord][gesture]
        if id == account then
            Store(mine, chord, gesture, nil) -- the same as the account's: no change of its own
        else
            Store(mine, chord, gesture, id or false)
        end
    else
        Store(ns.db.chords, chord, gesture, id)
        Store(mine, chord, gesture, nil) -- so the change shows here too
    end
    Apply()
    Changed()
end

-- This character back on the account's slots.
function Chords.ClearOwn()
    if DeckKitCharDB then DeckKitCharDB.chords = nil end
    Apply()
    Changed()
end

function Chords.Enabled() return not ns.db.chordsOff end

-- The keys the chord system takes over while it's on (modules leave these alone).
function Chords.Owns(key)
    if not Chords.Enabled() then return false end
    for _, g in ipairs(GRIPS) do
        if key == g.key or key == g.long then return true end
    end
    return false
end

-- A chord is "early" (fires on press) if it has a press, no hold, and no bigger chord containing it
-- has anything bound.
local function Contains(big, small)
    for part in small:gmatch("[^+]+") do
        if not ("+" .. big .. "+"):find("+" .. part .. "+", 1, true) then return false end
    end
    return true
end

local function Early(chord)
    if not Chords.Get(chord, "press") or Chords.Get(chord, "hold") then return false end
    for _, other in ipairs(Chords.LIST) do
        if other ~= chord and Contains(other, chord)
            and (Chords.Get(other, "press") or Chords.Get(other, "hold")) then
            return false
        end
    end
    return true
end

------------------------------------------------------------------------
-- The secure part
------------------------------------------------------------------------

local owner = CreateFrame("Frame", "DeckKitChords", UIParent, "SecureHandlerBaseTemplate")
owner:Execute([[
    held = newtable(); peak = newtable(); nheld = 0; last = 0; fired = false; upFor = nil; seq = 0
    NAMES = newtable("L4", "R4", "L5", "R5")
    SLOTS = newtable()
]])
owner:Execute("MIRROR = newtable(" .. string.format(string.rep("%q, ", #MIRROR - 1) .. "%q", unpack(MIRROR))
    .. "); NMIRROR = " .. #MIRROR)

-- Applying a slot as it fires (shared by both snippets; "how" is "down" or "tap").
local FIRE = [[
    seq = seq + 1
    if fire.kind == "none" then return false end
    if fire.kind == "run" then
        owner:SetAttribute("run", fire.id .. " " .. how .. " " .. seq)
        return false
    end
    self:SetAttribute("useOnKeyDown", how == "down")
    if fire.kind == "attrs" then
        for n = 1, NMIRROR do self:SetAttribute(MIRROR[n], nil) end
        for k, v in pairs(fire.attrs) do self:SetAttribute(k, v) end
    else
        local src = owner:GetFrameRef(fire.ref)
        if not src then return false end
        for n = 1, NMIRROR do self:SetAttribute(MIRROR[n], src:GetAttribute(MIRROR[n])) end
    end
    owner:SetAttribute("fired", fire.id .. " " .. seq)
]]

-- A grip's own key: pressed (down) and let go (up).
local GRIP_SNIPPET = [[
    local i = self:GetAttribute("grip")
    local fire, how
    if down then
        if held[i] then return false end
        if nheld == 0 then peak = newtable(); fired = false; upFor = nil end
        held[i] = true; nheld = nheld + 1; peak[i] = true; last = i
        if fired then return false end
        local name = ""
        for j = 1, 4 do if held[j] then name = name .. NAMES[j] .. "+" end end
        local c = SLOTS[strsub(name, 1, -2)]
        if not (c and c.early and c.press) then return false end
        fired = true; fire = c.press; how = "down"; upFor = fire
    else
        if not held[i] then return false end
        held[i] = nil; nheld = nheld - 1
        if upFor then
            if upFor.kind == "run" then
                seq = seq + 1
                owner:SetAttribute("run", upFor.id .. " up " .. seq)
            end
            upFor = nil
        end
        if fired then return false end
        fired = true
        local name = ""
        for j = 1, 4 do if peak[j] then name = name .. NAMES[j] .. "+" end end
        local c = SLOTS[strsub(name, 1, -2)]
        if not (c and c.press) then return false end
        fire = c.press; how = "tap"
    end
]] .. FIRE

-- A grip's long key: when it's the grip pressed last, the whole chord has been held long enough.
local HOLD_SNIPPET = [[
    if not down then return false end
    local i = self:GetAttribute("grip")
    if fired or not held[i] or i ~= last then return false end
    local name = ""
    for j = 1, 4 do if held[j] then name = name .. NAMES[j] .. "+" end end
    local c = SLOTS[strsub(name, 1, -2)]
    if not (c and c.hold) then return false end
    fired = true
    local fire, how = c.hold, "down"
    upFor = fire
]] .. FIRE

local gripButtons, holdButtons = {}, {}
local function Button(name, i, snippet)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("grip", i)
    owner:WrapScript(b, "OnClick", snippet)
    return b
end
for i = 1, 4 do
    gripButtons[i] = Button("DeckKitGrip" .. i, i, GRIP_SNIPPET)
    holdButtons[i] = Button("DeckKitGripHold" .. i, i, HOLD_SNIPPET)
end

-- The insecure half: "run" slots, and a log line per fired slot.
local function Run(id, state)
    local o = Actions.Offered(id)
    if not (o and o.run) then return end
    if state ~= "up" then o.run(true) end
    if state ~= "down" then o.run(false) end
end

owner:HookScript("OnAttributeChanged", function(_, name, value)
    if name == "run" and value then
        local id, state = value:match("^(%S+) (%S+)")
        ns.Debug("chord run", id, state)
        local ok, err = pcall(Run, id, state)
        if not ok then geterrorhandler()(err) end
    elseif name == "fired" and value then
        ns.Debug("chord fired", (value:match("^%S+")), InCombatLockdown() and "(combat)" or "")
    end
end)

-- Slots into the restricted table, frame refs for mirrors, and the 8 key overrides. Out of combat.
local pending
Apply = function()
    if InCombatLockdown() then pending = true; return end
    pending = false
    ClearOverrideBindings(owner)
    local code = { "SLOTS = newtable()" }
    for _, chord in ipairs(Chords.LIST) do
        local press, hold = Chords.Get(chord, "press"), Chords.Get(chord, "hold")
        if press or hold then
            code[#code + 1] = string.format("do local c = newtable(); SLOTS[%q] = c; c.early = %s", chord,
                tostring(Early(chord)))
            for gesture, id in pairs({ press = press, hold = hold }) do
                local kind, ref = HowToRun(id)
                if kind == "mirror" and not _G[ref] then kind = nil end
                if kind == "mirror" then owner:SetFrameRef(ref, _G[ref]) end
                if not kind then ns.Debug("chord slot can't run", chord, gesture, id) end
                code[#code + 1] = string.format("c.%s = newtable(); c.%s.kind = %q; c.%s.id = %q; c.%s.ref = %q",
                    gesture, gesture, kind or "none", gesture, id, gesture, ref or "")
                if kind == "attrs" then
                    code[#code + 1] = string.format("c.%s.attrs = newtable()", gesture)
                    for k, v in pairs(Actions.Attributes(id)) do
                        code[#code + 1] = string.format(type(v) == "number" and "c.%s.attrs[%q] = %d" or "c.%s.attrs[%q] = %q",
                            gesture, k, v)
                    end
                end
            end
            code[#code + 1] = "end"
        end
    end
    owner:Execute(table.concat(code, "\n"))
    if not Chords.Enabled() then return end
    for i, g in ipairs(GRIPS) do
        SetOverrideBindingClick(owner, true, g.key, gripButtons[i]:GetName())
        SetOverrideBindingClick(owner, true, g.long, holdButtons[i]:GetName())
    end
end
Chords.Apply = function() Apply() end

ns.On("PLAYER_REGEN_ENABLED", function() if pending then Apply() end end)

------------------------------------------------------------------------
-- First run: today's grip bindings become slots
------------------------------------------------------------------------

-- Each grip's current game binding moves to that grip's slot: a peek (hold-to-see) becomes its
-- hold, anything else its press. Plus: L4 / R4 pressed hide that side (double-tap used to), and both
-- together drive the dictation indicator.
local function FirstSlots()
    ns.db.chords = {}
    for _, g in ipairs(GRIPS) do
        -- Bindings from before slots lived on the grips' old keys (F1-F4 now default to targeting).
        local id = GetBindingAction(ns.OLD_GRIP_KEYS[g.name])
        if id and id ~= "" then
            ns.db.chords[g.name] = { [id:find("_PEEK$") and "hold" or "press"] = id }
        end
    end
    local function Add(chord, gesture, id)
        ns.db.chords[chord] = ns.db.chords[chord] or {}
        if not ns.db.chords[chord][gesture] then ns.db.chords[chord][gesture] = id end
    end
    Add("L4", "press", "DECKKIT_HIDE_LEFT")
    Add("R4", "press", "DECKKIT_HIDE_RIGHT")
    Add("L4+R4", "press", "DECKKIT_DICTATION")
end

ns.On("PLAYER_LOGIN", function()
    if not ns.db.chords then FirstSlots() end
    -- Modules offer their actions as they load; apply once they all have.
    C_Timer.After(0, Apply)
end)

------------------------------------------------------------------------
-- Describing a slot: a glyph (media/chords-24.tga, made by deck-setup/make-chord-glyphs.py) and words
------------------------------------------------------------------------

-- The chord glyph: Ben's 24 px pixel art (media/chords-24.tga, made by deck-setup/make-chord-glyphs.py from
-- his drawings in deck-setup/glyphs/): the Deck's back grips, held ones lilac and the others dark gray,
-- outlined; a hold adds a bar along the bottom. 8 x 4 cells of 24 px (cell n = the grips held, bit 1 L4,
-- 2 R4, 4 L5, 8 R5, + 16 for a hold), padded to 256 x 128. Drawn at 24 it's 1:1 on the Deck's screen (a
-- UI unit is a screen pixel there).
local SHEET, CELL, SHEET_W, SHEET_H = "Interface\\AddOns\\DeckKit\\media\\chords-24", 24, 256, 128

-- Inline markup for a chord's glyph, for any FontString. size: 24 unless a spot needs otherwise (1:1 at 24).
function Chords.Glyph(chord, gesture, size)
    size = size or CELL
    local mask = 0
    for j, g in ipairs(GRIPS) do
        if ("+" .. chord .. "+"):find("+" .. g.name .. "+", 1, true) then mask = mask + 2 ^ (j - 1) end
    end
    local n = mask + (gesture == "hold" and 16 or 0)
    local x, y = (n % 8) * CELL, math.floor(n / 8) * CELL
    return string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t", SHEET, size, size, SHEET_W, SHEET_H,
        x, x + CELL, y, y + CELL)
end

function Chords.Describe(chord, gesture)
    return chord .. (gesture == "hold" and " held" or "")
end

------------------------------------------------------------------------
-- Settings (the full slot page comes with the chord glyphs)
------------------------------------------------------------------------

local function Summary()
    local lines = {}
    for _, chord in ipairs(Chords.LIST) do
        for _, gesture in ipairs({ "press", "hold" }) do
            local id = Chords.Get(chord, gesture)
            if id then lines[#lines + 1] = Chords.Describe(chord, gesture) .. ": " .. Chords.Label(id) end
        end
    end
    return #lines > 0 and table.concat(lines, "\n") or "Nothing bound"
end

-- What a slot can hold: every offer, then the action bar buttons. Built when the menu is.
-- What a slot can hold, as { {id, label}, ... } (the menu's list; deckctl chords resolves names with it).
local function Choices()
    local list = { { false, "Nothing" } }
    for _, cat in ipairs(Actions.CATEGORIES) do
        for _, e in ipairs(Actions.List(cat.key)) do list[#list + 1] = { e.id, e.label } end
    end
    return list
end

Chords.Choices = function() return Choices() end

-- A shared slot's own value, whatever this character has on top (deckctl chords; the menu's "shared").
function Chords.Shared(chord, gesture)
    local c = ns.db.chords and ns.db.chords[chord]
    return c and c[gesture]
end

local HINT = {
    press = "Fires when you let go, or the moment the grips are down if nothing else could follow "
        .. "(no hold here, nothing on a bigger chord). {X} chooses what it does.",
    hold = "Fires once every grip in it has been held for the long-press time (Steam's, 400 ms unless "
        .. "changed); letting go then does nothing more. {X} chooses what it does.",
}

local rows = {
    { type = "section", tab = "Controls", label = "Grips", order = 3 },
    { type = "toggle", label = "Grip chords",
      hint = "The back grips, alone or together, pressed or held: each one a slot below. Needs DeckKit's "
          .. "Steam layout (deck-setup/make-chord-layout.py).",
      get = function() return Chords.Enabled() end,
      set = function(on) ns.db.chordsOff = not on or nil; Apply(); Changed() end },
    { type = "choice", label = "Slot changes apply to",
      hint = "All characters: the slots every character shares. This character: changes kept for this "
          .. "character only, on top of the shared ones (class spells, say); those show in lilac.",
      values = { { "all", "All characters" }, { "char", "This character" } },
      get = function() return Chords.Scope() end,
      set = function(v)
          DeckKitCharDB = DeckKitCharDB or {}
          DeckKitCharDB.chordScope = v == "char" and "char" or nil
      end },
    { type = "action", label = "Clear this character's slots", verb = "Clear", keepOpen = true,
      hint = "This character goes back to the shared slots.",
      run = function() Chords.ClearOwn(); ns.Print("This character is back on the shared grip slots.") end },
}
local GROUPS = { { 1, "Grips: one" }, { 2, "Grips: two together" }, { 3, "Grips: three or four together" } }
-- Each group is a table: a row per chord, its press and hold side by side. {X} on a slot opens the action picker.
for gi, group in ipairs(GROUPS) do
    if gi > 1 then rows[#rows + 1] = { type = "section", tab = "Controls", label = group[2], order = 3 + gi * 0.1 } end
    local table_ = { type = "bindings", columns = { "Press", "Hold" }, rows = {}, labelWidth = 150 }
    for _, chord in ipairs(Chords.LIST) do
        local size = select(2, chord:gsub("+", "")) + 1
        if size == group[1] or (group[1] == 3 and size == 4) then
            local cells = {}
            for _, gesture in ipairs(Chords.GESTURES) do
                cells[#cells + 1] = {
                    title = Chords.Glyph(chord, gesture) .. "  " .. Chords.Describe(chord, gesture),
                    hint = HINT[gesture],
                    mine = function() return Chords.Own(chord, gesture) ~= nil end,
                    get = function() return Chords.Get(chord, gesture) end,
                    set = function(id) Chords.Set(chord, gesture, id) end,
                }
            end
            table.insert(table_.rows, { label = Chords.Glyph(chord, "press") .. "  " .. chord, cells = cells })
        end
    end
    rows[#rows + 1] = table_
end
ns.Settings.Add("DeckKit", ns.TITLE, rows)

ns.AddCommand("chords", function()
    ns.Print(Chords.Enabled() and "grip chords on" or "grip chords off")
    for line in Summary():gmatch("[^\n]+") do ns.Print("  " .. line) end
end, "list the grip chord slots")
