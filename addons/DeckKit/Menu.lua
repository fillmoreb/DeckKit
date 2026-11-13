-- The DeckKit menu: every module's settings in one window, run entirely from the controller.
--
-- Tabs (LB/RB) group settings by what they're about, not by addon: Controls, Screen, Map & travel,
-- Healing, Tools. Each tab is a scrolling list of sections on the left (each addon's rows under a
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
    binding = "{A}, then press a back grip (L4 R4 L5 R5). {X} clears it.",
}

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

    local function Details(item, label)
        label = label or item.label
        if type(label) == "function" then label = label() end
        dHead:SetText(ns.Window.Glyphs(label or ""))
        dText:SetText(ns.Window.Glyphs(item.hint or DEFAULT_HINT[item.type] or ""))
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
            local focus = function(self) Details(item, self and self.dkLabel) end
            local opts = { label = item.label, get = item.get, set = item.set, onFocus = focus,
                disabled = item.disabled, reason = item.reason }
            if item.type == "toggle" then
                f = UI.Checkbox(content, W, opts)
            elseif item.type == "choice" then
                opts.values = item.values
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
                if _G["BINDING_NAME_" .. item.action] then
                    opts.action, opts.label = item.action, item.label
                    f = UI.KeyBinding(content, W, opts)
                    f.dkLabel = _G["BINDING_NAME_" .. item.action]
                end
            elseif item.type == "status" then
                f = UI.StatusRow(content, W, item)
                statuses[#statuses + 1] = f
                h2 = 24
            elseif item.type == "info" then
                local d = UI.Description(content, item.label, W - 20)
                d:SetPoint("TOPLEFT", 10, -y - 2)
                y = y + d:GetStringHeight() + 8
            end
            if f then
                f:SetPoint("TOPLEFT", 0, -y)
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
    { type = "section", tab = "Controls", label = "Menu", order = 1 },
    { type = "toggle", label = "Double-tap {MENU} opens this",
      hint = "Press {MENU} twice quickly to open this menu. Typing /deckkit always works.",
      get = function() return ns.db.menuDouble ~= false end,
      set = function(on)
          ns.db.menuDouble = on
          if not on then ns.Print("double-tap Menu is off. Type /deckkit to open the menu.") end
      end },
    { type = "section", tab = "Tools", label = "DeckKit", order = 9 },
    { type = "info", label = "Chat commands: /deckkit help" },
    { type = "section", tab = "Controls", label = "Bindings", order = 9 },
    { type = "status", label = "Reload UI", hint = "A keyboard key, for testing at a desk.",
      get = function()
          local k = GetBindingKey("DECKKIT_RELOAD")
          return k or "Not bound", (not k) and UI.Color.dim or nil
      end },
    { type = "status", label = "Dictation signals",
      hint = "Keys Decktation sends while you dictate. Changing them would break the indicator.",
      get = function()
          local ok = GetBindingKey("DECKKIT_DICTATION_START") ~= nil
          return ok and "Set up" or "Not set up", ok and UI.Color.good or UI.Color.dim
      end },
})
