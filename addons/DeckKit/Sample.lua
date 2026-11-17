-- The DeckKit design sample: every UI.lua element together, to try with the controller.
-- /deckkit sample, or "Design sample" on the DeckKit page of the menu. Nothing here is saved or
-- bound for real.
local _, ns = ...
local UI = ns.UI

local screen

local ABILITIES = {
    { "Flash Heal", "Spell_Holy_FlashHeal", "A fast, expensive heal. Use it when someone is about to die." },
    { "Renew", "Spell_Holy_Renew", "Heals over 15 seconds. Cheap; keep it rolling on the tank." },
    { "Power Word: Shield", "Spell_Holy_PowerWordShield", "Absorbs damage for 30 seconds." },
    { "Lesser Heal", "Spell_Holy_LesserHeal", "A slow, efficient heal for steady damage." },
    { "Heal", "Spell_Holy_Heal", "A solid heal with a 3 second cast." },
    { "Greater Heal", "Spell_Holy_GreaterHeal", "A big, slow heal for heavy damage on one target." },
    { "Prayer of Healing", "Spell_Holy_PrayerOfHealing02", "Heals your whole group." },
    { "Dispel Magic", "Spell_Holy_DispelMagic", "Removes a harmful magic effect from a friend." },
    { "Cure Disease", "Spell_Holy_NullifyDisease", "Removes a disease." },
    { "Resurrection", "Spell_Holy_Resurrection", "Brings a dead ally back to life." },
    { "Holy Fire", "Spell_Holy_SearingLight", "Not learned yet.", disabled = true },
    { "Smite", "Spell_Holy_HolySmite", "Damages an enemy." },
}

-- Sample state (not saved).
local state = {
    grid = true, wrap = false, target = "focus",
    healBind = { "PADLTRIGGER", "PAD1" }, nextBind = nil,
    selected = { [1] = true, [2] = true }, binds = { [1] = { "PADDUP" }, [2] = { "PADDLEFT" } },
    list = { { "PADDUP" }, { "PADDDOWN" }, nil, { "PADDRIGHT" } },
    range = 40, x = 452, y = 628,
    cells = {}, quick = nil, pressSlot = nil, holdSlot = nil,
}

local function Build()
    screen = UI.NewScreen("DeckKitSample", 880, 560, "DeckKit design sample")
    local W = 880 - 28

    ------------------------------------------------------------------
    -- Tab 1: controls on the left, an icon grid with details on the right
    ------------------------------------------------------------------
    local t1 = screen:AddTab("Overview")
    local left = UI.Panel(t1.frame, "Healing setup")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(380)
    local RW = 380 - 24
    local y = left.top
    local function Place(f, h) f:SetPoint("TOPLEFT", left, "TOPLEFT", 12, y); y = y - (h or UI.ROW_H) - 2 end

    Place(UI.Checkbox(left, RW, { label = "Show the practice grid",
        get = function() return state.grid end, set = function(v) state.grid = v end }))
    Place(UI.Switch(left, RW, { label = "Cursor at the edge", off = "Stop", on = "Wrap",
        get = function() return state.wrap end, set = function(v) state.wrap = v end }))
    Place(UI.Selector(left, RW, { label = "Heal target", boxWidth = 140,
        values = { { "focus", "Focus" }, { "mouseover", "Mouseover" }, { "target", "Target" }, { "player", "Yourself" } },
        get = function() return state.target end, set = function(v) state.target = v end }))
    Place(UI.TextBox(left, RW, { label = "Macro name", boxWidth = 180, placeholder = "type a name",
        get = function() return state.macroName or "" end, set = function(v) state.macroName = v end }))
    Place(UI.Binding(left, RW, { label = "Quick heal",
        get = function() return state.healBind end, set = function(v) state.healBind = v end }))
    Place(UI.Binding(left, RW, { label = "Next party member",
        get = function() return state.nextBind end, set = function(v) state.nextBind = v end }))
    Place(UI.Checkbox(left, RW, { label = "Heal in combat only",
        disabled = true, reason = "Needs HealPad's raid mode, which isn't built yet",
        get = function() return false end, set = function() end }))

    y = y - 8
    local d = UI.Description(left, "Readouts below don't take the cursor: they only report.", RW)
    d:SetPoint("TOPLEFT", left, "TOPLEFT", 12, y)
    y = y - 40
    local s1, s2, s3 = UI.Status(left, RW), UI.Status(left, RW), UI.Status(left, RW)
    for _, s in ipairs({ s1, s2, s3 }) do s:SetPoint("TOPLEFT", left, "TOPLEFT", 12, y); y = y - 22 end
    local function Readouts()
        s1:Set("Macros", "4 of 4 made", UI.Color.good)
        local n = 0
        for _, b in pairs(state.list) do if b then n = n + 1 end end
        s2:Set("On the d-pad", n .. " of 4", n == 4 and UI.Color.good or UI.Color.gold)
        s3:Set("In a group", IsInGroup() and "Yes" or "No", IsInGroup() and UI.Color.good or UI.Color.dim)
    end

    local make = UI.Button(left, 150, { label = "Make macros", verb = "Make the macros",
        run = function() screen.footerLeft:SetText(UI.Hex(UI.Color.good) .. "Sample: nothing was made.|r") end })
    make:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 12, 12)
    local reset = UI.Button(left, 150, { label = "Reset", disabled = true, reason = "Nothing to reset yet",
        run = function() end })
    reset:SetPoint("LEFT", make, "RIGHT", 10, 0)

    -- Right: abilities grid + details of the focused one.
    local right = UI.Panel(t1.frame, "Abilities")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT")

    local details = {}
    local icons = {}
    local function ShowDetails(i)
        local a = ABILITIES[i]
        details.icon:SetTexture("Interface\\Icons\\" .. a[2])
        details.icon:SetDesaturated(a.disabled or false)
        details.name:SetText(a[1])
        details.desc:SetText(a[3])
        details.bind:Set("Bound to", UI.BindingText(state.binds[i]), nil)
        details.sel:Set("On the healing page", a.disabled and "Can't add" or (state.selected[i] and "Yes" or "No"),
            a.disabled and UI.Color.dim or (state.selected[i] and UI.Color.good or UI.Color.dim))
        details.current = i
    end
    for i, a in ipairs(ABILITIES) do
        icons[i] = UI.Icon(right, 44, {
            icon = "Interface\\Icons\\" .. a[2],
            disabled = a.disabled, reason = "Holy Fire: not learned yet",
            isSelected = function() return state.selected[i] end,
            binding = function() return state.binds[i] end,
            onFocus = function() ShowDetails(i) end,
            prompts = function()
                local p = { { "A", state.selected[i] and "Remove from page" or "Add to page" }, { "X", "Bind" } }
                if state.binds[i] then p[#p + 1] = { "Y", "Clear" } end
                return p
            end,
            activate = function() state.selected[i] = not state.selected[i] or nil; ShowDetails(i) end,
            x = function(self)
                screen.mode, screen.capture = "capture", self
                details.bind:Set("Bound to", "Press a button...", UI.Color.gold)
            end,
            y = function() state.binds[i] = nil; ShowDetails(i) end,
        })
        icons[i].dk.captured = function(_, key) state.binds[i] = { key }; ShowDetails(i) end
    end
    UI.Grid(icons, right, 6, 44, 18, 30, right.top - 6)

    local rule = right:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.45, 0.42, 0.35, 0.6)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", right, "TOPLEFT", 12, right.top - 6 - 2 * 62 - 6)
    rule:SetPoint("TOPRIGHT", right, "TOPRIGHT", -12, 0)
    local dw = W - 380 - 12 - 24
    details.icon = right:CreateTexture(nil, "ARTWORK")
    details.icon:SetSize(52, 52)
    details.icon:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 4, -14)
    details.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    details.name = UI.Heading(right, "")
    details.name:SetFontObject(UI.Font.title)
    details.name:SetPoint("TOPLEFT", details.icon, "TOPRIGHT", 12, -4)
    details.desc = UI.Description(right, "", dw - 72)
    details.desc:SetPoint("TOPLEFT", details.name, "BOTTOMLEFT", 0, -6)
    details.bind = UI.Status(right, dw - 8)
    details.bind:SetPoint("TOPLEFT", details.icon, "BOTTOMLEFT", 0, -18)
    details.sel = UI.Status(right, dw - 8)
    details.sel:SetPoint("TOPLEFT", details.bind, "BOTTOMLEFT", 0, -4)
    local legend = UI.Description(right, "Gold glow: on the healing page.  Corner glyph: its button.  "
        .. "The chevron is only ever the cursor.", dw - 8)
    legend:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 12)
    ShowDetails(1)

    t1.onShow = Readouts
    t1.onRefresh = Readouts

    ------------------------------------------------------------------
    -- Tab 2: a plain list of bindings, with the focused row explained beside it
    ------------------------------------------------------------------
    local t2 = screen:AddTab("Bindings")
    local list = UI.Panel(t2.frame, "D-pad on the healing page")
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMLEFT")
    list:SetWidth(460)
    local side = UI.Panel(t2.frame, nil)
    side:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
    side:SetPoint("BOTTOMRIGHT")
    local sideHead = UI.Heading(side, "")
    sideHead:SetPoint("TOPLEFT", 14, -14)
    local sideText = UI.Description(side, "", W - 460 - 12 - 30)
    sideText:SetPoint("TOPLEFT", sideHead, "BOTTOMLEFT", 0, -8)
    local NAMES = { "HealPad Up", "HealPad Down", "HealPad Left", "HealPad Right" }
    local WHAT = { "Moves the cursor up the raid frames and focuses that member.",
        "Moves the cursor down.", "Moves the cursor left.", "Moves the cursor right." }
    for i = 1, 12 do
        NAMES[#NAMES + 1] = "Heal slot " .. i
        WHAT[#WHAT + 1] = "Casts whatever heal you put in slot " .. i .. " on your focus."
    end
    local scroll = UI.ScrollList(list, 460 - 16, 442 + list.top - 12)
    scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 8, list.top)
    local ly = 0
    for i, name in ipairs(NAMES) do
        local row = UI.Binding(scroll.content, 460 - 16 - 22, { label = name,
            get = function() return state.list[i] end, set = function(v) state.list[i] = v end,
            onFocus = function()
                sideHead:SetText(name)
                sideText:SetText(WHAT[i] .. "\n\nA binds it to the next button you press; X clears it."
                    .. "\n\nThe list follows the cursor; the right stick scrolls it.")
            end })
        row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 4, -ly)
        ly = ly + UI.ROW_H + 2
    end
    scroll:SetContentHeight(ly)

    ------------------------------------------------------------------
    -- Tab: actions (DeckKit.Actions). Slots in a 3x3 grid as PadGrid lays them out, a menu row, and a table
    -- of cells as the grip slots use. {X} on any of them opens the picker; nothing is bound for real.
    ------------------------------------------------------------------
    local ta = screen:AddTab("Actions")
    local gridPanel = UI.Panel(ta.frame, "A 3x3 grid")
    gridPanel:SetPoint("TOPLEFT")
    gridPanel:SetSize(250, 260)
    local cells = {}
    for i = 1, 9 do
        cells[i] = UI.ActionSlot(gridPanel, { size = 52, title = "Cell " .. i,
            get = function() return state.cells[i] end, set = function(id) state.cells[i] = id end })
    end
    UI.Grid(cells, gridPanel, 3, 52, 22, 34, gridPanel.top - 10)
    local rowsPanel = UI.Panel(ta.frame, "As menu rows")
    rowsPanel:SetPoint("TOPLEFT", gridPanel, "TOPRIGHT", 12, 0)
    rowsPanel:SetPoint("BOTTOMRIGHT")
    local RW2 = W - 250 - 12 - 24
    local ry = rowsPanel.top
    local quick = UI.ActionRow(rowsPanel, RW2, { label = "Quick heal",
        get = function() return state.quick end, set = function(id) state.quick = id end })
    quick:SetPoint("TOPLEFT", 12, ry)
    ry = ry - UI.ROW_H - 16
    local head = UI.Heading(rowsPanel, "")
    head:SetFontObject(UI.Font.smallDim)
    head:SetText("Press                                      Hold")
    head:SetPoint("TOPLEFT", 160, ry)
    ry = ry - 22
    local label = UI.Heading(rowsPanel, "L4 + R5")
    label:SetFontObject(UI.Font.body)
    label:SetPoint("TOPLEFT", 22, ry - 7)
    local cw = math.floor((RW2 - 150) / 2)
    local press = UI.ActionCell(rowsPanel, cw - 4, { title = "L4 + R5 pressed",
        get = function() return state.pressSlot end, set = function(id) state.pressSlot = id end })
    press:SetPoint("TOPLEFT", 12 + 150, ry)
    local hold = UI.ActionCell(rowsPanel, cw - 4, { title = "L4 + R5 held", mine = function() return true end,
        get = function() return state.holdSlot end, set = function(id) state.holdSlot = id end })
    hold:SetPoint("TOPLEFT", 12 + 150 + cw, ry)
    ry = ry - UI.ROW_H - 16
    local note = UI.Description(rowsPanel, "{X} on a slot opens the picker: {LB} {RB} change the list (DeckKit, spells, items, "
        .. "macros, action bars), {A} chooses, {B} leaves it as it was. The first cell of every list empties the slot. "
        .. "A held name in lilac is this character's own.", RW2 - 10)
    note:SetPoint("TOPLEFT", 12, ry)

    ------------------------------------------------------------------
    -- Tab 3: numbers. A stepper for a value nudged up and down; dials for one typed digit by digit.
    ------------------------------------------------------------------
    local tn = screen:AddTab("Numbers")
    local np = UI.Panel(tn.frame, "Numbers")
    np:SetAllPoints()
    local stepper = UI.Stepper(np, 420, { label = "Practice range", min = 10, max = 100, step = 5,
        format = function(v) return v .. " yd" end,
        get = function() return state.range end, set = function(v) state.range = v end })
    stepper:SetPoint("TOPLEFT", 12, np.top)
    -- A popover stepper sits beside other controls: the d-pad passes over it, A opens it.
    local popover = UI.Stepper(np, 260, { label = "Level (A)", min = 1, max = 60, popover = true, any = 0,
        anyText = "any",
        get = function() return state.level or 20 end, set = function(v) state.level = v end })
    popover:SetPoint("LEFT", stepper, "RIGHT", 10, 0)
    local nd = UI.Description(np, "Dials: {DPAD_UD} turns a digit, {DPAD_LR} picks one; past the last "
        .. "digit the cursor moves on to the next control. {A} does the dial's action.", W - 24)
    nd:SetPoint("TOPLEFT", 12, np.top - UI.ROW_H - 16)
    local said = UI.Status(np, 360)
    local function Say() said:Set("Saved", string.format("%.1f, %.1f", state.x / 10, state.y / 10), UI.Color.gold) end
    local dx = UI.Dial(np, { label = "X", digits = 3, point = 1, verb = "Save", activate = Say,
        get = function() return state.x end, set = function(v) state.x = v end })
    local dy = UI.Dial(np, { label = "Y", digits = 3, point = 1, verb = "Save", activate = Say,
        get = function() return state.y end, set = function(v) state.y = v end })
    dx:SetPoint("TOPLEFT", 12, np.top - UI.ROW_H - 70)
    dy:SetPoint("LEFT", dx, "RIGHT", 40, 0)
    said:SetPoint("TOPLEFT", dx, "BOTTOMLEFT", 0, -16)
    said:Set("Saved", "nothing yet", UI.Color.dim)

    ------------------------------------------------------------------
    -- Tab 4: a layout (Layout.lua): the same kind of window described as data, the way an assistant
    -- would send it. Checks tick themselves from your bags and quest log.
    ------------------------------------------------------------------
    local tl = screen:AddTab("Layout")
    local said2 = UI.Status(tl.frame, 250)
    said2:SetPoint("BOTTOMLEFT", 4, 0)
    said2:Set("Reply", "nothing yet", UI.Color.dim)
    local ticks = {} -- your own ticks, kept while the sample is (an owner saves them for real)
    local SPEC = {
        type = "list", items = {
            { type = "section", title = "Before Shadowfang Keep", items = {
                { type = "row", items = { { type = "item", id = 6948 }, { type = "check", bind = { item = 6948 } } } },
                { type = "row", items = { { type = "item", id = 159, count = 10 },
                    { type = "check", bind = { item = 159, count = 10 } } } },
                { type = "row", items = { { type = "item", id = 4306 }, { type = "check", toggle = true } } },
                { type = "progress", text = "Linen Cloth", bind = { item = 2589, count = 20 } },
            } },
            { type = "section", title = "Quests", items = {
                { type = "row", items = { { type = "quest", id = 1013, text = "The Book of Ur" },
                    { type = "check", bind = { quest = 1013 } } } },
                { type = "row", items = { { type = "quest", id = 1014, text = "Arugal Must Die" },
                    { type = "check", bind = { quest = 1014 } } } },
            } },
            { type = "section", title = "Where", items = {
                { type = "waypoint", map = 1421, x = 44.8, y = 67.8, label = "Shadowfang Keep" },
                { type = "waypoint", map = 1458, x = 84.2, y = 17.4, label = "Bethor Iceshard" },
                { type = "text", style = "dim", text = "Hold {Y} to see an item's tooltip or a place's map beside the window (move "
                    .. "while holding to look at others). On a place, {A} makes it your waypoint." },
            } },
        },
        footer = { type = "row", items = {
            { type = "space" },
            { type = "button", text = "Count me in", width = 150, buttons = { a = { reply = "in", label = "Join" } } },
            { type = "button", text = "Not tonight", width = 150, buttons = { a = { reply = "out", label = "Decline" } } },
        } },
        title = "Shadowfang Keep",
    }
    local function Reply(v) said2:Set("Reply", v, UI.Color.gold) end
    UI.Build(tl.frame, SPEC, { width = W, height = 442 - 30, onReply = Reply, ticks = ticks })
    -- The same spec in each of the hosts a display can have (Displays.lua).
    local asTracker = UI.Action(tl.frame, 190, { label = "As a tracker", verb = "Show",
        run = function()
            if UI.TrackerShown() then UI.HideTracker() else UI.ShowTracker(SPEC, { ticks = ticks }) end
        end })
    asTracker:SetPoint("BOTTOMRIGHT", 0, 0)
    local asCard = UI.Action(tl.frame, 190, { label = "As a card", verb = "Show",
        run = function() UI.ShowCard(SPEC, { ticks = ticks }) end })
    asCard:SetPoint("RIGHT", asTracker, "LEFT", -6, 0)
    -- The window gets a second page (LB/RB): the other pieces.
    local PAGES = { type = "pages", footer = SPEC.footer, items = { SPEC, {
        type = "list", title = "More pieces", items = {
            { type = "section", title = "Spells", items = {
                { type = "spell", id = 2061 }, { type = "spell", id = 139 } } },
            { type = "section", title = "People", items = {
                { type = "npc", name = "Dalar Dawnweaver", title = "Sepulcher", map = 1421, x = 44.2, y = 39.8 },
                { type = "npc", name = "Bethor Iceshard", map = 1458, x = 84.2, y = 17.4 } } },
            { type = "section", title = "Money", items = {
                { type = "money", text = "Repairs", copper = 4382 },
                { type = "money", text = "Your gold", copper = GetMoney and GetMoney() or 0 } } },
        } } } }
    local asWindow = UI.Action(tl.frame, 190, { label = "As a window", verb = "Open",
        run = function() UI.ShowLayout(PAGES, { title = "Sample display", ticks = ticks,
            onReply = function(v) ns.Print("Sample display: replied " .. tostring(v)) end }) end })
    asWindow:SetPoint("RIGHT", asCard, "LEFT", -6, 0)

    ------------------------------------------------------------------
    -- Tab 5: information only. Nothing takes the cursor.
    ------------------------------------------------------------------
    local t3 = screen:AddTab("Status")
    local info = UI.Panel(t3.frame, "HealPad")
    info:SetAllPoints()
    local iy = info.top
    local para = UI.Description(info, "This tab only reports. There's nothing to select, so there's no "
        .. "cursor and the footer only offers {LB} {RB} and {B}.", W - 24)
    para:SetPoint("TOPLEFT", 12, iy)
    iy = iy - 46
    local h2 = UI.Heading(info, "Raid frames")
    h2:SetPoint("TOPLEFT", 12, iy)
    iy = iy - 26
    local r1, r2, r3 = UI.Status(info, 360), UI.Status(info, 360), UI.Status(info, 360)
    for _, r in ipairs({ r1, r2, r3 }) do r:SetPoint("TOPLEFT", 12, iy); iy = iy - 22 end
    iy = iy - 16
    local h3 = UI.Heading(info, "Grip chord glyphs")
    h3:SetPoint("TOPLEFT", 12, iy)
    iy = iy - 30
    -- ns.Chords.Glyph(chord, gesture, size): inline markup for any text. Held grips lilac, a bar for a hold.
    local samples = UI.Description(info, ns.Chords.Glyph("L4") .. " L4    " .. ns.Chords.Glyph("L4", "hold")
        .. " L4 held    " .. ns.Chords.Glyph("L4+L5") .. " L4+L5    " .. ns.Chords.Glyph("R4+L5+R5", "hold")
        .. " R4+L5+R5 held    " .. ns.Chords.Glyph("L4+R4+L5+R5") .. " all four", W - 24)
    samples:SetPoint("TOPLEFT", 12, iy)
    t3.onShow = function()
        r1:Set("Frames found", GetNumGroupMembers() > 0 and GetNumGroupMembers() or "None (solo)", UI.Color.gold)
        r2:Set("Focus", UnitExists("focus") and UnitName("focus") or "None", UnitExists("focus") and UI.Color.good or UI.Color.dim)
        r3:Set("Combat", InCombatLockdown() and "In combat" or "Out of combat", InCombatLockdown() and UI.Color.bad or UI.Color.good)
    end
end

local function Open()
    if not screen then Build() end
    screen:Toggle()
end
ns.OpenSample = Open

-- /deckkit sample [keys]: with pad key names ("PADDRIGHT PAD1 ..."), opens the sample and plays
-- them a third of a second apart (for testing without a controller).
ns.AddCommand("sample", function(arg)
    local keys = {}
    for k in (arg or ""):gmatch("%S+") do keys[#keys + 1] = k:upper() end
    if #keys == 0 then Open() return end
    if not screen then Build() end
    if not screen.win:IsShown() then
        local ok, err = pcall(screen.Show, screen)
        if not ok then ns.Print("|cffff5555" .. tostring(err) .. "|r") end
    end
    for i, k in ipairs(keys) do
        C_Timer.After(0.33 * i, function()
            local ok, err = pcall(screen.Key, screen, k)
            if not ok then ns.Print("|cffff5555" .. k .. ": " .. tostring(err) .. "|r") end
        end)
    end
end, "the DeckKit design sample window")
ns.Settings.Add("DeckKit", ns.TITLE, {
    { type = "section", tab = "Tools", label = "DeckKit", order = 9 },
    { type = "action", label = "Design sample", run = Open,
      hint = "Every DeckKit control in one window, to try with the controller." },
})
