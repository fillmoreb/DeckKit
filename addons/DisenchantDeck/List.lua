-- The list.
--   Up/Down: select   A: disenchant   Y: hide (in Hidden: show again)   LB/RB: Disenchant <-> Hidden   B: close
--
-- Disenchanting is a protected action, so addon code can't start it. Each row is a secure button
-- whose macro is "/cast Disenchant" + "/use <bag> <slot>"; while the window is open, A is bound
-- (override binding) to click the selected row. Tapping a row on the touchscreen works too.
-- A row must never run its macro while a cast is going: "/cast" would fail and "/use" would
-- equip the item instead. PreClick disarms the row if anything is being cast.
local _, ns = ...

local List = {}
ns.List = List

local ROWS, ROW_H, WIDTH = 9, 30, 420
local win, rows
local view = "shown" -- or "hidden"
local entries = {}   -- the current view's items
local counts = { shown = 0, hidden = 0 }
local sel, offset = 1, 0

local function Casting()
    return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

-- Rows' macros and A's binding: only out of combat, only while open.
local function Arm()
    if InCombatLockdown() or not (win and win:IsShown()) then return end
    local spell = ns.DisenchantName()
    local canCast = view == "shown" and ns.KnowsDisenchant() and spell and not Casting()
    for r, row in ipairs(rows) do
        local e = entries[offset + r]
        if canCast and e and not e.locked then
            row:SetAttribute("type", "macro")
            row:SetAttribute("macrotext", "/cast " .. spell .. "\n/use " .. e.bag .. " " .. e.slot)
        else
            row:SetAttribute("type", nil)
            row:SetAttribute("macrotext", nil)
        end
    end
    -- A clicks the selected row (a disarmed row does nothing, so A never reaches the game here).
    local r = math.max(1, math.min(ROWS, sel - offset))
    SetOverrideBindingClick(win, true, "PAD1", rows[r]:GetName(), "LeftButton")
    SetOverrideBindingClick(win, true, "ENTER", rows[r]:GetName(), "LeftButton")
end

function List.Refresh()
    if not (win and win:IsShown()) or InCombatLockdown() then return end
    local shown, hidden = ns.Scan()
    counts.shown, counts.hidden = #shown, #hidden
    entries = view == "shown" and shown or hidden

    local n = #entries
    sel = math.max(1, math.min(sel, n))
    if sel <= offset then offset = sel - 1 end
    if sel > offset + ROWS then offset = sel - ROWS end
    offset = math.max(0, math.min(offset, math.max(0, n - ROWS)))

    win.title:SetText(view == "shown" and ("Disenchant  |cff888888(" .. n .. ")|r")
        or ("Hidden  |cff888888(" .. n .. ")|r"))
    for r, row in ipairs(rows) do
        local e = entries[offset + r]
        if e then
            row.icon:SetTexture(e.icon)
            row.text:SetText((e.link or "?") .. (e.count > 1 and (" |cffaaaaaax" .. e.count .. "|r") or ""))
            row.icon:SetDesaturated(e.locked and true or false)
            row:SetAlpha(e.locked and 0.5 or 1)
            row:Show()
        else
            row:Hide()
        end
        if offset + r == sel and e then
            row.bg:SetColorTexture(1, 0.82, 0, 0.25)
        else
            row.bg:SetColorTexture(1, 1, 1, ((offset + r) % 2 == 0) and 0.03 or 0)
        end
    end

    if n == 0 then
        win.empty:SetText(view == "shown"
            and (ns.KnowsDisenchant() and "Nothing to disenchant in your bags." or "You don't know Disenchant yet.")
            or "Nothing hidden.")
        win.empty:Show()
    else
        win.empty:Hide()
    end
    local other = view == "shown" and ("Hidden (" .. counts.hidden .. ")") or ("Disenchant (" .. counts.shown .. ")")
    if view == "shown" then
        win:SetHints((n > 0 and "A Disenchant   Y Hide   " or "") .. "LB/RB  " .. other .. "   B Close")
    else
        win:SetHints((n > 0 and "Y Show again   " or "") .. "LB/RB  " .. other .. "   B Close")
    end
    Arm()
end

local function Move(d)
    local n = #entries
    if n == 0 then return end
    sel = (sel - 1 + d) % n + 1
    ns.Window.Tick()
    List.Refresh()
end

local function ToggleHidden()
    local e = entries[sel]
    if not e then return end
    if view == "shown" then
        ns.db.hidden[e.itemID] = true
        ns.Print("Hid " .. (e.link or e.itemID) .. ". RB shows hidden items.")
    else
        ns.db.hidden[e.itemID] = nil
        ns.Print("Showing " .. (e.link or e.itemID) .. " again.")
    end
    ns.Window.Tick()
    List.Refresh()
end

local function SwitchView()
    view = view == "shown" and "hidden" or "shown"
    sel, offset = 1, 0
    ns.Window.Tick()
    List.Refresh()
end

local function Close()
    win:Hide()
    ns.Window.Sound(false)
end

local function Create()
    win = ns.Window.New("DisenchantDeckFrame", WIDTH, ROWS * ROW_H + 86, "Disenchant")
    rows = {}
    for r = 1, ROWS do
        local row = CreateFrame("Button", "DisenchantDeckRow" .. r, win, "SecureActionButtonTemplate")
        row:SetSize(WIDTH - 24, ROW_H)
        row:SetPoint("TOPLEFT", 12, -38 - (r - 1) * ROW_H)
        row:RegisterForClicks("AnyUp", "AnyDown")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_H - 6, ROW_H - 6)
        row.icon:SetPoint("LEFT", 4, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("PreClick", function(self)
            if Casting() and not InCombatLockdown() then
                self:SetAttribute("type", nil) -- see the top of this file
            end
            sel = offset + r -- a tap selects the row it disenchants
        end)
        row:SetScript("OnEnter", function(self)
            local e = entries[offset + r]
            if e and e.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(e.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[r] = row
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("CENTER", 0, 10)

    win:HookScript("OnHide", function()
        if not InCombatLockdown() then ClearOverrideBindings(win) end
    end)

    ns.Input.New(win, {
        PADDUP = function() Move(-1) end,
        PADDDOWN = function() Move(1) end,
        PAD2 = Close,
        PAD4 = ToggleHidden,
        PADLSHOULDER = SwitchView,
        PADRSHOULDER = SwitchView,
    })
end

function List.Open()
    if InCombatLockdown() then
        ns.Print("Not in combat.")
        return
    end
    if not win then Create() end
    view, sel, offset = "shown", 1, 0
    win:Show()
    ns.Window.Sound(true)
    List.Refresh()
end

function List.Toggle()
    if win and win:IsShown() then Close() else List.Open() end
end

-- Bags change as items get disenchanted; casts start and stop.
local function Later() C_Timer.After(0, List.Refresh) end
ns.On("BAG_UPDATE_DELAYED", Later)
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    ns.On(event, function(unit) if unit == "player" then Later() end end)
end

function DisenchantDeck_Toggle() List.Toggle() end
SLASH_DISENCHANTDECK1 = "/dd"
SLASH_DISENCHANTDECK2 = "/disenchantdeck"
SlashCmdList.DISENCHANTDECK = function() List.Toggle() end

ns.AddSettings({
    { type = "action", label = "Open the disenchant list", run = List.Open },
    { type = "action", label = "Show hidden items again", hint = "Un-hides everything you hid with Y.",
      run = function()
          local n = 0
          for id in pairs(ns.db.hidden) do ns.db.hidden[id] = nil; n = n + 1 end
          ns.Print(n == 0 and "Nothing was hidden." or ("Showing " .. n .. " hidden item" .. (n == 1 and "" or "s") .. " again."))
      end },
})
