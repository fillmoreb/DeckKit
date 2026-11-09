-- The DeckKit menu: every module's settings in one window, run entirely from the controller.
--
--   Up/Down     pick a setting           Left/Right  change it
--   A           toggle / next choice / run an action
--   LB/RB       previous / next module   B or Menu   close
--
-- Opens when the controller's Menu button (three lines, PADFORWARD) is pressed twice quickly, or
-- with /deckkit. The first press still opens the game's own menu wheel; that wheel is closed when
-- this opens. The button is only watched, never taken. (Double-press approach from Improved
-- Forever's Menu.lua, MIT License, Copyright (c) 2026 markg.)
local _, ns = ...

local Menu = {}
ns.Menu = Menu

local ROWS, ROW_H, WIDTH = 9, 30, 460
local DOUBLE = 0.35 -- seconds between the two Menu presses

local win, rows, header, desc
local page, sel, offset = 1, nil, 0

local function Pages() return ns.Settings.pages end
local function Items() local p = Pages()[page]; return p and p.items or {} end
local function Selectable(item) return item and item.type ~= "info" end

local function ValueText(item)
    if item.type == "toggle" then
        return item.get() and "|cff5fd35fOn|r" or "|cff888888Off|r"
    elseif item.type == "choice" then
        local v, text = item.get(), nil
        for _, c in ipairs(item.values) do
            if c[1] == v then text = c[2] end
        end
        return "<   " .. (text or tostring(v)) .. "   >"
    elseif item.type == "range" then
        local v = item.get()
        return "<   " .. (item.format and item.format(v) or tostring(v)) .. "   >"
    elseif item.type == "action" then
        return ns.Window.Glyph("A")
    end
    return ""
end

local function Hints(item)
    local what = ""
    if item then
        if item.type == "toggle" then what = "{A} {DPAD_LR} Change     "
        elseif item.type == "choice" or item.type == "range" then what = "{DPAD_LR} Change     "
        elseif item.type == "action" then what = "{A} Go     " end
    end
    return what .. (#Pages() > 1 and "{LB} {RB} Module     " or "") .. "{B} Close"
end

function Menu.Render()
    if not (win and win:IsShown()) then return end
    local pages, items = Pages(), Items()
    local p = pages[page]
    header:SetText(#pages > 1 and (ns.Window.Glyph("LB") .. "   " .. p.title .. "   " .. ns.Window.Glyph("RB")
        .. "   |cff888888" .. page .. "/" .. #pages .. "|r") or p.title)

    if sel then
        if sel <= offset then offset = sel - 1 end
        if sel > offset + ROWS then offset = sel - ROWS end
    end
    offset = math.max(0, math.min(offset, math.max(0, #items - ROWS)))

    for r, row in ipairs(rows) do
        local i = offset + r
        local item = items[i]
        if item then
            if item.type == "info" then
                row.label:SetFontObject("GameFontDisable")
                row.label:SetText(ns.Window.Glyphs(item.label))
                row.value:SetText("")
            else
                row.label:SetFontObject("GameFontHighlight")
                row.label:SetText(ns.Window.Glyphs(item.label))
                row.value:SetText(ValueText(item))
            end
            row.bg:SetColorTexture(1, 0.82, 0, i == sel and 0.25 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
    local item = sel and items[sel]
    desc:SetText(item and item.hint and ns.Window.Glyphs(item.hint) or "")
    win:SetHints(Hints(item))
end

local function FirstSelectable()
    for i, item in ipairs(Items()) do
        if Selectable(item) then return i end
    end
end

local function Move(d)
    local items = Items()
    if not sel then return end
    local i = sel
    for _ = 1, #items do
        i = (i - 1 + d) % #items + 1
        if Selectable(items[i]) then break end
    end
    if i ~= sel then
        sel = i
        ns.Window.Tick()
        Menu.Render()
    end
end

local function SwitchPage(d)
    local n = #Pages()
    if n < 2 then return end
    page = (page - 1 + d) % n + 1
    sel, offset = FirstSelectable(), 0
    ns.Window.Tick()
    Menu.Render()
end

function Menu.Close()
    if win and win:IsShown() then
        win:Hide()
        ns.Window.Sound(false)
    end
end

-- dir: -1 / 1 for Left / Right, 0 for A.
local function Change(dir)
    local item = sel and Items()[sel]
    if not item then return end
    if item.type == "toggle" then
        item.set(not item.get())
    elseif item.type == "choice" then
        local n, cur = #item.values, 1
        for i, c in ipairs(item.values) do
            if c[1] == item.get() then cur = i end
        end
        item.set(item.values[(cur - 1 + (dir == 0 and 1 or dir)) % n + 1][1])
    elseif item.type == "range" then
        if dir == 0 then return end
        local v = math.max(item.min, math.min(item.max, item.get() + dir * (item.step or 1)))
        if v == item.get() then return end
        item.set(v)
    elseif item.type == "action" then
        if dir ~= 0 then return end
        -- Close first: the action often opens another DeckKit window, which takes the pad next.
        Menu.Close()
        C_Timer.After(0, item.run)
        return
    end
    ns.Window.Tick()
    Menu.Render()
end

local function Create()
    win = ns.Window.New("DeckKitMenu", WIDTH, 60 + ROWS * ROW_H + 64, "DeckKit")
    header = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -36)
    rows = {}
    for r = 1, ROWS do
        local row = CreateFrame("Frame", nil, win)
        row:SetSize(WIDTH - 24, ROW_H)
        row:SetPoint("TOPLEFT", 12, -58 - (r - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 10, 0)
        row.label:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.value:SetPoint("RIGHT", -10, 0)
        row.value:SetJustifyH("RIGHT")
        row.label:SetPoint("RIGHT", row.value, "LEFT", -10, 0)
        row.label:SetWordWrap(false)
        rows[r] = row
    end
    desc = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("BOTTOMLEFT", 20, 34)
    desc:SetPoint("BOTTOMRIGHT", -20, 34)
    desc:SetHeight(28)
    desc:SetJustifyH("CENTER")
    desc:SetJustifyV("MIDDLE")

    ns.Input.New(win, {
        PADDUP = function() Move(-1) end,
        PADDDOWN = function() Move(1) end,
        PADDLEFT = function() Change(-1) end,
        PADDRIGHT = function() Change(1) end,
        PAD1 = function() Change(0) end,
        PAD2 = Menu.Close,
        PADFORWARD = Menu.Close,
        PADLSHOULDER = function() SwitchPage(-1) end,
        PADRSHOULDER = function() SwitchPage(1) end,
    })
end

function Menu.Open()
    if InCombatLockdown() then
        ns.Print("The menu can't open in combat.")
        return
    end
    if not win then Create() end
    if not Pages()[page] then page = 1 end
    if not (sel and Selectable(Items()[sel])) then sel, offset = FirstSelectable(), 0 end
    win:Show()
    ns.Window.Sound(true)
    Menu.Render()
end

function Menu.Toggle()
    if win and win:IsShown() then Menu.Close() else Menu.Open() end
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
            if ns.db.menuDouble ~= false and not InCombatLockdown() and not (win and win:IsShown()) then
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

-- The core's own page.
ns.Settings.Add("DeckKit", ns.TITLE, {
    { type = "toggle", label = "Double-tap {MENU} opens this",
      hint = "Press {MENU} twice quickly to open this menu. Typing /deckkit always works.",
      get = function() return ns.db.menuDouble ~= false end,
      set = function(on) ns.db.menuDouble = on end },
    { type = "info", label = "Module key bindings: Key Bindings > DeckKit." },
    { type = "info", label = "Chat commands: /deckkit help" },
})
