-- Paddle chords: the four back grips, alone or together, pressed or held, each a slot for an action.
--
-- Steam sends plain keys only (deck-setup/make-chord-layout.py): a grip's own key while it's held,
-- and a second key once it has been held for the long-press time (400 ms by default):
--   L4 = F8 / F1    R4 = F9 / F2    L5 = F10 / F3    R5 = F11 / F4
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

Chords.GRIPS = {
    { name = "L4", key = "F8",  long = "F1" },
    { name = "R4", key = "F9",  long = "F2" },
    { name = "L5", key = "F10", long = "F3" },
    { name = "R5", key = "F11", long = "F4" },
}
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

local offers = {}

-- opts: label (else the binding's own name), mirror = secure button name, run = fn(down) (insecure).
function Chords.Offer(id, opts) offers[id] = opts or {} end

-- An action that just happens once, when the slot fires.
function Chords.OfferPress(id, fn, label)
    offers[id] = { label = label, run = function(down) if down then fn() end end }
end

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton" }

-- How a binding id runs: "mirror", frame name; "run"; or nil (nothing can run it).
local function HowToRun(id)
    local spell = id:match("^SPELL:(%d+)$")
    if spell then return "spell", spell end
    local o = offers[id]
    if o and o.mirror then return "mirror", o.mirror end
    if o and o.run then return "run" end
    local n = id:match("^ACTIONBUTTON(%d+)$")
    if n then return "mirror", BARS[1] .. n end
    local bar, b = id:match("^MULTIACTIONBAR(%d)BUTTON(%d+)$")
    if bar and BARS[tonumber(bar) + 1] then return "mirror", BARS[tonumber(bar) + 1] .. b end
end
Chords.CanRun = function(id) return HowToRun(id) ~= nil end

function Chords.Label(id)
    if not id then return nil end
    local spell = id:match("^SPELL:(%d+)$")
    if spell then return (C_Spell.GetSpellName(tonumber(spell))) or ("Spell " .. spell) end
    local o = offers[id]
    return (o and o.label) or _G["BINDING_NAME_" .. id] or id
end

------------------------------------------------------------------------
-- Slots (DeckKitDB.chords = { ["L4+L5"] = { press = id, hold = id } })
------------------------------------------------------------------------

function Chords.Get(chord, gesture)
    local c = ns.db.chords and ns.db.chords[chord]
    return c and c[gesture]
end

local Apply -- below

function Chords.Set(chord, gesture, id)
    ns.db.chords = ns.db.chords or {}
    local c = ns.db.chords[chord] or {}
    c[gesture] = id
    ns.db.chords[chord] = next(c) and c or nil
    Apply()
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
    if fire.kind == "spell" then
        for n = 1, NMIRROR do self:SetAttribute(MIRROR[n], nil) end
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", tonumber(fire.ref))
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
    local o = offers[id]
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
        local id = GetBindingAction(g.key)
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
-- Describing a slot: a glyph (media/chords.tga, made by deck-setup/make-chord-glyphs.py) and words
------------------------------------------------------------------------

local GLYPHS = "Interface\\AddOns\\DeckKit\\media\\chords"

-- Inline markup for a chord's glyph, for any FontString: the Deck's back, held grips lit, a bar
-- under it for a hold.
function Chords.Glyph(chord, gesture, size)
    size = size or 22
    local mask = 0
    for j, g in ipairs(GRIPS) do
        if ("+" .. chord .. "+"):find("+" .. g.name .. "+", 1, true) then mask = mask + 2 ^ (j - 1) end
    end
    local n = mask + (gesture == "hold" and 16 or 0)
    local x, y = (n % 8) * 64, math.floor(n / 8) * 64
    return string.format("|T%s:%d:%d:0:0:512:256:%d:%d:%d:%d|t", GLYPHS, size, size, x, x + 64, y, y + 64)
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
local function Choices()
    local list = { { false, "Nothing" } }
    local ids = {}
    for id in pairs(offers) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return Chords.Label(a) < Chords.Label(b) end)
    for _, id in ipairs(ids) do list[#list + 1] = { id, Chords.Label(id) } end
    -- The spellbook's castable spells, in book order.
    local book = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(i, book)
            if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and item.spellID then
                list[#list + 1] = { "SPELL:" .. item.spellID, item.name }
            end
        end
    end
    for b = 1, 12 do list[#list + 1] = { "ACTIONBUTTON" .. b, Chords.Label("ACTIONBUTTON" .. b) } end
    for bar = 1, 4 do
        for b = 1, 12 do
            local id = "MULTIACTIONBAR" .. bar .. "BUTTON" .. b
            list[#list + 1] = { id, Chords.Label(id) }
        end
    end
    return list
end

local HINT = {
    press = "Fires when you let go, or the moment the grips are down if nothing else could follow "
        .. "(no hold here, nothing on a bigger chord). {DPAD_LR} or {A} to choose.",
    hold = "Fires once every grip in it has been held for the long-press time (Steam's, 400 ms unless "
        .. "changed); letting go then does nothing more. {DPAD_LR} or {A} to choose.",
}

local rows = {
    { type = "section", tab = "Controls", label = "Paddles", order = 3 },
    { type = "toggle", label = "Paddle chords",
      hint = "The back grips, alone or together, pressed or held: each one a slot below. Needs DeckKit's "
          .. "Steam layout (deck-setup/make-chord-layout.py).",
      get = function() return Chords.Enabled() end,
      set = function(on) ns.db.chordsOff = not on or nil; Apply() end },
}
local GROUPS = { { 1, "Paddles: one grip" }, { 2, "Paddles: two grips" }, { 3, "Paddles: three or four grips" } }
-- One list for every slot row, filled in at login once the modules have made their offers.
local choices = {}
local function FillChoices()
    wipe(choices)
    for i, c in ipairs(Choices()) do choices[i] = c end
end
ns.On("PLAYER_LOGIN", FillChoices)
ns.On("SPELLS_CHANGED", function() if IsLoggedIn() then FillChoices() end end)
for gi, group in ipairs(GROUPS) do
    if gi > 1 then rows[#rows + 1] = { type = "section", tab = "Controls", label = group[2], order = 3 + gi * 0.1 } end
    for _, chord in ipairs(Chords.LIST) do
        local size = select(2, chord:gsub("+", "")) + 1
        if size == group[1] or (group[1] == 3 and size == 4) then
            for _, gesture in ipairs({ "press", "hold" }) do
                rows[#rows + 1] = {
                    type = "choice", label = Chords.Glyph(chord, gesture) .. "  " .. Chords.Describe(chord, gesture),
                    hint = HINT[gesture],
                    values = choices,
                    get = function() return Chords.Get(chord, gesture) or false end,
                    set = function(v) Chords.Set(chord, gesture, v or nil) end,
                }
            end
        end
    end
end
ns.Settings.Add("DeckKit", ns.TITLE, rows)

ns.AddCommand("chords", function()
    ns.Print(Chords.Enabled() and "paddle chords on" or "paddle chords off")
    for line in Summary():gmatch("[^\n]+") do ns.Print("  " .. line) end
end, "list the paddle chord slots")
