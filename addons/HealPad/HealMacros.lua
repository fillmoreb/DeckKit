-- Heal macros: one macro per helpful spell, aimed at your focus (the cursor's pick), for the face
-- buttons of your healing page. Resurrection spells aim at a dead focus instead.
--
--   /cast [@focus,help,nodead][] Flash Heal       heals, shields, dispels: focus, else as usual
--   /cast [@focus,help,dead] Resurrection         only on a dead focus
--   /castsequence [@focus,help,nodead][] reset=8 Power Word: Fortitude, Divine Spirit, Shadow Protection
--                                                 buffs: one press per buff, so a whole set takes
--                                                 one macro; 8 s idle starts it over (next person)
--
-- Paladin blessings don't go in a sequence (only one of your blessings fits on a person at a time);
-- each is its own macro, unticked to start, so you choose the ones you use. A cure you've learned a
-- better version of (Cure Disease once you have Abolish Disease...) isn't offered.
--
-- Which spells: from your spellbook, the ones that are helpful and have a range (so they can be cast
-- on someone else; self-only spells like Inner Fire are left out), plus your resurrection spells,
-- with a few corrections by hand (ALWAYS / NEVER below).
-- A window lists them, all ticked; untick what you don't want, then make them. Ranks fold into one
-- macro per spell name (/cast picks your highest rank). They're character macros: WoW allows 18.
local ADDON, ns = ...
local UI = DeckKit.UI

local MAX_CHARACTER = 18
-- Resurrection spells (rank 1 IDs; matched by name, so every rank and language counts).
-- Resurrection, Redemption, Ancestral Spirit, Rebirth, and Forever's druid Revive (out of combat).
local RESURRECT = { 2006, 7328, 2008, 20484, 437138 }

-- Corrections to "helpful with a range", checked against every healer's full Forever spell list
-- (wago.tools' tables, then the same test in game; 2026-11-11):
-- spells that heal or damage aren't flagged helpful, so they're added by hand...
local ALWAYS = { 402289, 20473 } -- Penance, Holy Shock
-- ...and these are flagged helpful but aren't focus spells: cast on the ground (Healing Rain,
-- Efflorescence), triggered by something else (Lightwell Renew, Living Seed, Ancestral Fortitude),
-- not aimed at an ally at all (Fire Nova, Decoy Totem, Mind Vision, Far Sight), or not for healing
-- (Water Walking, Water Breathing, Spirit of the Alpha: a threat buff).
local NEVER = { 415236, 417148, 7001, 414683, 16177, 408341, 425874, 2096, 6196, 546, 131, 408696 }

-- Buffs, folded into sequence macros: one for single targets, one for group versions.
local BUFFS = {
    { name = "Buffs", ids = { 1243, 14752, 976, 1126, 467 } },
    -- Power Word: Fortitude, Divine Spirit, Shadow Protection, Mark of the Wild, Thorns
    { name = "Group buffs", ids = { 21562, 27681, 27683, 21849 } },
    -- Prayer of Fortitude, Prayer of Spirit, Prayer of Shadow Protection, Gift of the Wild
}
-- Offered unticked: paladin blessings, one at a time on a person, so you pick yours.
local UNTICKED = { 19740, 19742, 20217, 25782, 25894, 25898 } -- Blessing / Greater Blessing of Might, Wisdom, Kings
-- A cure and the better one that replaces it: the old one isn't offered once you know the new one.
local REPLACED_BY = { [528] = 552, [526] = 2893, [1152] = 4987 } -- Cure Disease, Cure Poison, Purify
-- Heals outgrown by a better one: still offered (for downranking), but unticked once you know it.
local OUTGROWN_BY = { [2050] = 2060, [2054] = 2060 } -- Lesser Heal, Heal: by Greater Heal

-- Spell names from a list of IDs (any rank's ID names every rank, in any language).
local function NamesOf(ids)
    local names = {}
    for _, id in ipairs(ids) do
        local name = C_Spell.GetSpellName(id)
        if name then names[name] = true end
    end
    return names
end
local function ResurrectNames() return NamesOf(RESURRECT) end

-- The entries a heal macro makes sense for, in spellbook order: { name, icon, resurrect, unticked },
-- then the buff sequences: { name, icon, sequence = { spell names } }.
local function Spells()
    local list, seen, rez = {}, {}, ResurrectNames()
    local always, never, unticked = NamesOf(ALWAYS), NamesOf(NEVER), NamesOf(UNTICKED)
    local buffOf = {} -- spell name -> its sequence
    for _, b in ipairs(BUFFS) do
        for name in pairs(NamesOf(b.ids)) do buffOf[name] = b end
    end
    local known = {}
    local sequences = {}
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
            if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and item.spellID
                and not seen[item.name] then
                local id = item.spellID
                local isRez = rez[item.name]
                known[item.name] = true
                local b = buffOf[item.name]
                if b then
                    seen[item.name] = true
                    sequences[b] = sequences[b] or { name = b.name, icon = C_Spell.GetSpellTexture(id), sequence = {} }
                    table.insert(sequences[b].sequence, item.name)
                elseif isRez or always[item.name]
                    or (not never[item.name] and C_Spell.IsSpellHelpful(id) and C_Spell.SpellHasRange(id)) then
                    seen[item.name] = true
                    table.insert(list, { name = item.name, icon = C_Spell.GetSpellTexture(id), resurrect = isRez,
                        unticked = unticked[item.name] })
                end
            end
        end
    end
    -- Drop a cure when its better version is known too.
    local dropped = {}
    for old, new in pairs(REPLACED_BY) do
        local oldName, newName = C_Spell.GetSpellName(old), C_Spell.GetSpellName(new)
        if oldName and newName and known[newName] then dropped[oldName] = true end
    end
    for i = #list, 1, -1 do if dropped[list[i].name] then table.remove(list, i) end end
    for old, new in pairs(OUTGROWN_BY) do
        local oldName, newName = C_Spell.GetSpellName(old), C_Spell.GetSpellName(new)
        if oldName and newName and known[newName] then
            for _, e in ipairs(list) do if e.name == oldName then e.unticked = true end end
        end
    end
    -- Each sequence casts in BUFFS' order (most wanted first), not spellbook order.
    for _, b in ipairs(BUFFS) do
        local seq = sequences[b]
        if seq then
            local inBook = {}
            for _, name in ipairs(seq.sequence) do inBook[name] = true end
            seq.sequence = {}
            for _, id in ipairs(b.ids) do
                local name = C_Spell.GetSpellName(id)
                if name and inBook[name] then table.insert(seq.sequence, name) end
            end
            table.insert(list, seq)
        end
    end
    return list
end

local function Body(spell)
    if spell.sequence then
        return "#showtooltip\n/castsequence [@focus,help,nodead][] reset=8 " .. table.concat(spell.sequence, ", ")
    end
    local cast = spell.resurrect and "/cast [@focus,help,dead] " or "/cast [@focus,help,nodead][] "
    return "#showtooltip " .. spell.name .. "\n" .. cast .. spell.name
end

-- Macro names are at most 16 characters.
local function MacroName(spell) return spell.name:sub(1, 16) end

-- Makes or updates a character macro for each spell. Returns made, updated, skipped (no room).
local function Make(spells)
    local made, updated, skipped = 0, 0, 0
    for _, spell in ipairs(spells) do
        local name = MacroName(spell)
        local index = GetMacroIndexByName(name)
        if index and index > 0 then
            EditMacro(index, name, nil, Body(spell))
            updated = updated + 1
        else
            local _, count = GetNumMacros()
            if count < MAX_CHARACTER and pcall(CreateMacro, name, "INV_MISC_QUESTIONMARK", Body(spell), true) then
                made = made + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return made, updated, skipped
end

------------------------------------------------------------------------
-- The window: the spells, each with a tick, and a button to make them.
------------------------------------------------------------------------

local WIDTH, HEIGHT = 520, 470
local screen, list, rows, makeButton, summary
local spells, chosen = {}, {}

local function Chosen()
    local out = {}
    for _, spell in ipairs(spells) do if chosen[spell.name] then out[#out + 1] = spell end end
    return out
end

local function Fill()
    spells = Spells()
    for _, r in ipairs(rows) do r:Hide() end
    local W = WIDTH - 28 - 24 - 22
    for i, spell in ipairs(spells) do
        if chosen[spell.name] == nil then chosen[spell.name] = not spell.unticked end
        local r = rows[i]
        if not r then
            r = UI.Checkbox(list.content, W, {
                label = "",
                get = function() local s = spells[i] return s and chosen[s.name] end,
                set = function(on) local s = spells[i] if s then chosen[s.name] = on end end,
            })
            rows[i] = r
        end
        local note = spell.resurrect and "on a dead focus"
            or spell.sequence and table.concat(spell.sequence, ", ") .. ": one press each"
        local label = "|T" .. (spell.icon or 134400) .. ":18:18|t  " .. spell.name
            .. (note and ("  |cff9d9d9d(" .. note .. ")|r") or "")
        if r.label then r.label:SetText(label) end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (UI.ROW_H + 2))
        r:Show()
    end
    list:SetContentHeight(#spells * (UI.ROW_H + 2))
end

local function Build()
    screen = UI.NewScreen("HealPadMacros", WIDTH, HEIGHT, "Heal macros")
    local tab = screen:AddTab("Spells")
    local panel = UI.Panel(tab.frame, nil)
    panel:SetAllPoints()
    local intro = UI.Description(panel, "One macro per spell, cast on your focus (the d-pad cursor's pick). "
        .. "Put them on your healing page's face buttons.", WIDTH - 52)
    intro:SetPoint("TOPLEFT", 12, -12)
    list = UI.ScrollList(panel, WIDTH - 52, HEIGHT - 76 - 42 - 120)
    list:SetPoint("TOPLEFT", 12, -52)
    rows = {}
    makeButton = UI.Button(panel, 220, { label = "Make the macros", run = function()
        if InCombatLockdown() then ns.Print("can't make macros in combat.") return end
        local made, updated, skipped = Make(Chosen())
        local msg = string.format("heal macros: %d new, %d updated", made, updated)
        if skipped > 0 then msg = msg .. string.format(", %d skipped (WoW's %d character macros are full)", skipped, MAX_CHARACTER) end
        ns.Print(msg .. ".")
        summary:SetText(msg .. ".")
    end })
    makeButton:SetPoint("BOTTOMLEFT", 12, 12)
    -- Where to place them: the game's own Macros window (see PLACE_HINT in HealPad.lua for why not ours).
    local how = UI.Description(panel, ns.Window.Glyphs(ns.PLACE_HINT .. " They're on its Character tab."), WIDTH - 52)
    how:SetPoint("BOTTOMLEFT", makeButton, "TOPLEFT", 0, 8)
    summary = UI.Description(panel, "", WIDTH - 52 - 232)
    summary:SetPoint("LEFT", makeButton, "RIGHT", 12, 0)
end

function ns.OpenHealMacros()
    if InCombatLockdown() then ns.Print("can't open that in combat.") return end
    if not screen then Build() end
    Fill()
    summary:SetText("")
    screen:Show()
end
