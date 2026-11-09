-- "Add waypoint": six digit slots, XX.X , YY.Y, dialed with the d-pad.
--   Up/Down: digit +1/-1 (wraps 0-9)   Left/Right: move between slots   A: save   B: cancel
--   LB/RB: switch to the waypoint list
-- Starts at your current coordinates, so you only change what differs. The waypoint goes in the
-- zone you're standing in. Edit uses the same window, starting at that waypoint's numbers.
local _, ns = ...

local Editor = {}
ns.Editor = Editor

local SLOT_W, SLOT_H, GAP = 34, 46, 4
local win, slots
local digits = { 0, 0, 0, 0, 0, 0 }
local sel = 1
local editIndex, mapID, backToManager

local function ToDigits(v, first)
    local n = math.floor(v * 1000 + 0.5)
    n = math.max(0, math.min(999, n))
    digits[first] = math.floor(n / 100)
    digits[first + 1] = math.floor(n / 10) % 10
    digits[first + 2] = n % 10
end

local function FromDigits(first)
    return (digits[first] * 100 + digits[first + 1] * 10 + digits[first + 2]) / 1000
end

local function Render()
    for i, slot in ipairs(slots) do
        slot.text:SetText(digits[i])
        if i == sel then
            slot.bg:SetColorTexture(1, 0.82, 0, 0.35)
            slot.text:SetTextColor(1, 1, 1)
        else
            slot.bg:SetColorTexture(1, 1, 1, 0.07)
            slot.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end
end

local function Close()
    win:Hide()
    ns.Window.Sound(false)
    if backToManager and ns.Manager then ns.Manager.Open() end
end

-- LB/RB: over to the waypoint list (drops any unsaved change).
local function SwitchToManager()
    backToManager = false
    win:Hide()
    if ns.Manager then ns.Manager.Open() end
end

local function Save()
    local x, y = FromDigits(1), FromDigits(4)
    if editIndex then
        ns.Edit(editIndex, x, y)
        ns.Print("Waypoint moved to " .. ns.Describe(ns.points[editIndex]))
    else
        ns.Print("Waypoint added: " .. ns.Describe(ns.Add(mapID, x, y)))
    end
    Close()
end

local function Create()
    win = ns.Window.New("WayPadEditor", 2 * (3 * SLOT_W + 2 * GAP) + 90, 170, "Add waypoint")
    win.zone = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.zone:SetPoint("TOP", win.title, "BOTTOM", 0, -4)

    slots = {}
    local groupW = 3 * SLOT_W + 2 * GAP + 10 -- 10 = room for the decimal point
    local left = -(2 * groupW + 30) / 2
    for i = 1, 6 do
        local group, k = i <= 3 and 0 or 1, (i - 1) % 3
        local x = left + group * (groupW + 30) + k * (SLOT_W + GAP) + (k == 2 and 10 or 0)
        local slot = CreateFrame("Frame", nil, win)
        slot:SetSize(SLOT_W, SLOT_H)
        slot:SetPoint("TOPLEFT", win, "TOP", x, -62)
        slot.bg = slot:CreateTexture(nil, "BACKGROUND")
        slot.bg:SetAllPoints()
        slot.text = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        local font = slot.text:GetFont()
        if font then slot.text:SetFont(font, 30, "OUTLINE") end
        slot.text:SetPoint("CENTER")
        slot:EnableMouse(true)
        slot:SetScript("OnMouseDown", function()
            sel = i
            Render()
        end)
        slot:EnableMouseWheel(true)
        slot:SetScript("OnMouseWheel", function(_, delta)
            sel = i
            digits[i] = (digits[i] + (delta > 0 and 1 or -1)) % 10
            Render()
        end)
        slots[i] = slot

        if k == 1 then -- decimal point after the second digit
            local dot = win:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
            dot:SetPoint("BOTTOM", slot, "BOTTOMRIGHT", GAP / 2 + 5, 4)
            dot:SetText(".")
        end
        if i == 1 or i == 4 then
            local cap = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            cap:SetPoint("BOTTOMLEFT", slot, "TOPLEFT", 0, 3)
            cap:SetText(i == 1 and "X (left - right)" or "Y (top - bottom)")
        end
    end
    local comma = win:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    comma:SetPoint("BOTTOMLEFT", slots[3], "BOTTOMRIGHT", 12, 2)
    comma:SetText(",")

    win:SetHints("D-pad  Change   A Save   B Cancel   LB/RB  Waypoints")

    ns.Input.New(win, {
        PADDUP = function() digits[sel] = (digits[sel] + 1) % 10; ns.Window.Tick(); Render() end,
        PADDDOWN = function() digits[sel] = (digits[sel] - 1) % 10; ns.Window.Tick(); Render() end,
        PADDLEFT = function() sel = sel > 1 and sel - 1 or 6; Render() end,
        PADDRIGHT = function() sel = sel < 6 and sel + 1 or 1; Render() end,
        PAD1 = Save,
        PAD2 = Close,
        PADLSHOULDER = SwitchToManager,
        PADRSHOULDER = SwitchToManager,
    })
end

-- index: edit that waypoint; nil: add a new one. fromManager: go back to the list afterwards.
function Editor.Open(index, fromManager)
    if InCombatLockdown() then
        ns.Print("Not in combat.")
        return
    end
    if not win then Create() end
    editIndex, backToManager = nil, fromManager
    local p = index and ns.points[index]
    if p then
        editIndex, mapID = index, p.mapID
        ToDigits(p.x, 1)
        ToDigits(p.y, 4)
        win.title:SetText("Edit waypoint")
    else
        local px, py
        mapID, px, py = ns.PlayerPosition()
        if not mapID then
            ns.Print("Can't read your position here.")
            return
        end
        ToDigits(px, 1)
        ToDigits(py, 4)
        win.title:SetText("Add waypoint")
    end
    win.zone:SetText(ns.MapName(mapID))
    sel = 1
    Render()
    win:Show()
    ns.Window.Sound(true)
end

function Editor.Toggle()
    if win and win:IsShown() then
        Close()
    else
        Editor.Open()
    end
end

function Editor.IsShown()
    return win and win:IsShown()
end
