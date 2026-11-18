-- The DeckKit menu: every module's settings in one window, run entirely from the controller.
--
-- Tabs (LB/RB) group settings by what they're about, not by addon: Setup, Controls, Screen, Quests,
-- Chat, Party, Trade, Advanced. Each tab is a scrolling list of sections on the left (each addon's rows under a
-- gold heading) and, on the right, what the focused setting does. Look and behavior come from
-- UI.lua (the game's pointer, 45 degree d-pad moves, A / B / footer prompts).
--
-- Opens when the controller's Menu button (three lines, PADFORWARD) is pressed twice quickly, or
-- with /deckkit. The first press still opens the game's own menu wheel; that wheel is closed when
-- this opens. The button is only watched, never taken. (Double-press approach from Improved
-- Forever's Menu.lua, MIT License, Copyright (c) 2026 markg.)
local _, ns = ...
local UI = ns.UI

local Menu = {}
ns.Menu = Menu

local DOUBLE = 0.35 -- seconds between the two Menu presses
local WIDTH, HEIGHT = 900, 580
local LIST_W = 560

local screen

local DEFAULT_HINT = {
    toggle = "{A} turns it on or off.",
    choice = "{DPAD_LR} steps through the choices; {A} shows them all.",
    range = "{DPAD_LR} changes it.",
    action = "{A} does it.",
    binding = "{X} chooses what it does.",
    bindings = "{X} chooses what it does.",
}

-- Marks after a row's label: kept for this character only (lilac), needs a /reload, can't be undone here.
local SETTING = { toggle = true, choice = true, range = true, binding = true }
-- The game's two-people icon (socialqueuing-icon-group), tinted the suite's lilac.
local function CharMark()
    local c = ns.COLORS and ns.COLORS.LILAC or { 0.72, 0.48, 1 }
    return string.format("|A:socialqueuing-icon-group:16:16:2:0:%d:%d:%d|a", c[1] * 255, c[2] * 255, c[3] * 255)
end
local RELOAD_MARK = "|A:UI-RefreshButton:14:14:2:0|a"
local PERMANENT_MARK = " |cffff6a5a!|r"

local function Marks(item)
    local m = ""
    if item.scope == "char" and SETTING[item.type] then m = m .. " " .. CharMark() end
    if item.reload then m = m .. " " .. RELOAD_MARK end
    if item.permanent then m = m .. PERMANENT_MARK end
    return m
end

local function MarkedLabel(item)
    local m = Marks(item)
    if m == "" then return item.label end
    if type(item.label) == "function" then return function() return (item.label() or "") .. m end end
    return (item.label or "") .. m
end

-- What the marks mean, under the hint beside the list.
local function MarkNotes(item)
    local notes = {}
    if SETTING[item.type] then
        if item.scope == "char" then
            notes[#notes + 1] = CharMark() .. "  Kept for this character only: your others keep their own."
        elseif item.scope == "session" then
            notes[#notes + 1] = "Only until the next /reload."
        else
            notes[#notes + 1] = "Shared by all your characters."
        end
    end
    if item.reload then notes[#notes + 1] = RELOAD_MARK .. "  Takes effect after a /reload." end
    if item.permanent then notes[#notes + 1] = "|cffff6a5a!  Can't be undone from here.|r" end
    return table.concat(notes, "\n")
end

local function BuildTab(tabName, sections)
    local tab = screen:AddTab(tabName)
    local bodyH = HEIGHT - 76 - 42

    local left = UI.Panel(tab.frame, nil)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)
    local list = UI.ScrollList(left, LIST_W - 12, bodyH - 12)
    list:SetPoint("TOPLEFT", 6, -6)
    local W = LIST_W - 12 - 22 -- room for the scroll bar

    local right = UI.Panel(tab.frame, nil)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT")
    local RW = WIDTH - 28 - LIST_W - 12 - 28
    local dHead = UI.Heading(right, "")
    dHead:SetPoint("TOPLEFT", 14, -14)
    dHead:SetWidth(RW)
    dHead:SetWordWrap(true)
    local dText = UI.Description(right, "", RW)
    dText:SetPoint("TOPLEFT", dHead, "BOTTOMLEFT", 0, -8)
    local dFrom = UI.Description(right, "", RW)
    dFrom:SetFontObject(UI.Font.smallDim)
    dFrom:SetPoint("BOTTOMLEFT", 14, 12)
    local dNotes = UI.Description(right, "", RW)
    dNotes:SetFontObject(UI.Font.smallDim)
    dNotes:SetPoint("BOTTOMLEFT", dFrom, "TOPLEFT", 0, 8)

    local function Details(item)
        local label = item.label
        if type(label) == "function" then label = label() end
        dHead:SetText(ns.Window.Glyphs(label or ""))
        dText:SetText(ns.Window.Glyphs(item.hint or DEFAULT_HINT[item.type] or ""))
        dNotes:SetText(MarkNotes(item))
        dFrom:SetText(item.from and ("From " .. item.from) or "")
    end

    local content = list.content
    local statuses = {}
    local y = 0
    for _, section in ipairs(sections) do
        local h = UI.Heading(content, section.label)
        h:SetPoint("TOPLEFT", 10, -y - 6)
        local rule = content:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(0.45, 0.42, 0.35, 0.5)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", 10, -y - 28)
        rule:SetWidth(W - 10)
        y = y + 34
        for _, item in ipairs(section.rows) do
            local f, h2
            local focus = function() Details(item) end
            local INDENT = item.indent and 22 or 0
            local W = W - INDENT
            local opts = { label = MarkedLabel(item), get = item.get, set = item.set, onFocus = focus,
                disabled = item.disabled, reason = item.reason }
            if item.type == "toggle" then
                f = UI.Checkbox(content, W, opts)
            elseif item.type == "choice" then
                opts.values, opts.listOnly = item.values, item.listOnly
                f = UI.Selector(content, W, opts)
            elseif item.type == "range" then
                opts.min, opts.max, opts.step, opts.format = item.min, item.max, item.step, item.format
                f = UI.Stepper(content, W, opts)
            elseif item.type == "action" then
                opts.verb = item.verb
                opts.run = function()
                    if item.keepOpen then item.run() return end
                    -- Close first: the action often opens another DeckKit window, which takes the pad next.
                    screen:Hide()
                    C_Timer.After(0, item.run)
                end
                f = UI.Action(content, W, opts)
            elseif item.type == "binding" then
                f = UI.ActionRow(content, W, opts)
            elseif item.type == "bindings" then
                -- A table of action slots: a label per row, a column per kind of slot (a chord's press and hold).
                local LABEL_W = item.labelWidth or 170
                local cols = #item.columns
                local cellW = math.floor((W - LABEL_W) / cols)
                for c, title in ipairs(item.columns) do
                    local t = UI.Heading(content, title)
                    t:SetFontObject(UI.Font.smallDim)
                    t:SetPoint("TOPLEFT", LABEL_W + (c - 1) * cellW + 8, -y - 4)
                end
                y = y + 22
                for _, r in ipairs(item.rows) do
                    local label = UI.Heading(content, "")
                    label:SetFontObject(UI.Font.body)
                    label:SetPoint("TOPLEFT", 10, -y - 7)
                    label:SetText(ns.Window.Glyphs(type(r.label) == "function" and r.label() or r.label))
                    for c, cell in ipairs(r.cells) do
                        local details = { label = cell.title, hint = cell.hint or item.hint, from = item.from }
                        local cf = UI.ActionCell(content, cellW - 4, {
                            get = cell.get, set = cell.set, mine = cell.mine, title = cell.title,
                            marked = cell.marked, mark = cell.mark, markText = cell.markText,
                            onFocus = function() Details(details) end,
                        })
                        cf:SetPoint("TOPLEFT", LABEL_W + (c - 1) * cellW, -y)
                    end
                    y = y + UI.ROW_H + 2
                end
            elseif item.type == "status" then
                f = UI.StatusRow(content, W, item)
                statuses[#statuses + 1] = f
                h2 = 24
            elseif item.type == "info" then
                local d = UI.Description(content, item.label, W - 20)
                d:SetPoint("TOPLEFT", 10 + INDENT, -y - 2)
                y = y + d:GetStringHeight() + 8
            end
            if f then
                f:SetPoint("TOPLEFT", INDENT, -y)
                y = y + (h2 or UI.ROW_H) + 2
            end
        end
        y = y + 12
    end
    list:SetContentHeight(y)

    local function Statuses() for _, s in ipairs(statuses) do s:Update() end end
    tab.onShow = Statuses
    tab.onRefresh = Statuses
end

local function Build()
    screen = UI.NewScreen("DeckKitMenu", WIDTH, HEIGHT, "DeckKit")
    for _, name in ipairs(ns.Settings.TABS) do
        local sections = ns.Settings.SectionsOf(name)
        if #sections > 0 then BuildTab(name, sections) end
    end
end

function Menu.Open()
    if InCombatLockdown() then
        ns.Print("The menu can't open in combat.")
        return
    end
    if not screen then Build() end
    screen:Show()
end

function Menu.Close()
    if screen then screen:Hide() end
end

function Menu.Toggle()
    if screen and screen.win:IsShown() then Menu.Close() else Menu.Open() end
end

-- Menu pressed twice quickly.
local wasDown, lastPress = false, 0
CreateFrame("Frame"):SetScript("OnUpdate", function()
    if not IsKeyDown then return end
    local down = IsKeyDown("PADFORWARD")
    if down and not wasDown then
        local now = GetTime()
        if now - lastPress <= DOUBLE then
            lastPress = 0
            if ns.db.menuDouble ~= false and not InCombatLockdown() and not (screen and screen.win:IsShown()) then
                -- Next frame: the game handles the press first (it closes or opens its wheel).
                C_Timer.After(0, function()
                    local radial = _G.GamepadRadial
                    if radial and radial:IsShown() then radial:Hide() end
                    Menu.Open()
                end)
            end
        else
            lastPress = now
        end
    end
    wasDown = down
end)

-- The core's own rows.
ns.Settings.Add("DeckKit", ns.TITLE, {
    { type = "section", tab = "Setup", label = "Welcome", order = 1 },
    { type = "action", label = "Setup steps", verb = "Open",
      hint = "The welcome window: the few things to set up once, and how each is going. Also /deckkit setup.",
      run = function() Menu.Close(); if ns.Setup then ns.Setup.Open() end end },
    { type = "section", tab = "Controls", label = "Menu", order = 5 },
    { type = "toggle", label = "Double-tap {MENU} opens this",
      hint = "Press {MENU} twice quickly to open this menu. Typing /deckkit always works.",
      get = function() return ns.db.menuDouble ~= false end,
      set = function(on)
          ns.db.menuDouble = on
          if not on then ns.Print("double-tap Menu is off. Type /deckkit to open the menu.") end
      end },
    { type = "section", tab = "Advanced", label = "Help and testing", order = 1 },
    { type = "info", label = "Chat commands: /deckkit help" },
    { type = "status", label = "Reload UI key", hint = "A keyboard key that reloads the interface, for testing at a desk.",
      get = function()
          local k = GetBindingKey("DECKKIT_RELOAD")
          return k or "Not bound", (not k) and UI.Color.dim or nil
      end },
})
