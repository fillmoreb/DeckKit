-- Heal macros: one macro per helpful spell, aimed at your focus (the cursor's pick), for the face
-- buttons of your healing page. Resurrection spells aim at a dead focus instead.
--
--   /cast [@focus,help,nodead][] Flash Heal       heals, shields, buffs, dispels: focus, else as usual
--   /cast [@focus,help,dead] Resurrection         only on a dead focus
--
-- Which spells: from your spellbook, the ones that are helpful and have a range (so they can be cast
-- on someone else; self-only spells like Inner Fire are left out), plus your resurrection spells.
-- A window lists them, all ticked; untick what you don't want, then make them. Ranks fold into one
-- macro per spell name (/cast picks your highest rank). They're character macros: WoW allows 18.
local ADDON, ns = ...
local UI = DeckKit.UI

local MAX_CHARACTER = 18
-- Resurrection spells (rank 1 IDs; matched by name, so every rank and language counts).
-- Resurrection, Redemption, Ancestral Spirit, Rebirth, and Forever's druid Revive (out of combat).
local RESURRECT = { 2006, 7328, 2008, 20484, 437138 }

local function ResurrectNames()
    local names = {}
    for _, id in ipairs(RESURRECT) do
        local name = C_Spell.GetSpellName(id)
        if name then names[name] = true end
    end
    return names
end

-- The spells a heal macro makes sense for: { name, icon, resurrect }, in spellbook order.
local function Spells()
    local list, seen, rez = {}, {}, ResurrectNames()
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
            if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and item.spellID
                and not seen[item.name] then
                local id = item.spellID
                local isRez = rez[item.name]
                if isRez or (C_Spell.IsSpellHelpful(id) and C_Spell.SpellHasRange(id)) then
                    seen[item.name] = true
                    table.insert(list, { name = item.name, icon = C_Spell.GetSpellTexture(id), resurrect = isRez })
                end
            end
        end
    end
    return list
end

local function Body(spell)
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
        if chosen[spell.name] == nil then chosen[spell.name] = true end
        local r = rows[i]
        if not r then
            r = UI.Checkbox(list.content, W, {
                label = "",
                get = function() local s = spells[i] return s and chosen[s.name] end,
                set = function(on) local s = spells[i] if s then chosen[s.name] = on end end,
            })
            rows[i] = r
        end
        local label = "|T" .. (spell.icon or 134400) .. ":18:18|t  " .. spell.name
            .. (spell.resurrect and "  |cff9d9d9d(on a dead focus)|r" or "")
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
