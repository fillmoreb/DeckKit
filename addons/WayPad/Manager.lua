-- The waypoint list.
--   Up/Down: select   A: make active (on "Clear all": asks, A again clears)   X: edit   Y: remove   B: close
--   LB/RB: switch to Add waypoint
local _, ns = ...

local Manager = {}
ns.Manager = Manager

local ROWS, ROW_H, WIDTH = 8, 24, 420
local win, rows
local sel, offset, confirming = 1, 0, false

local function Count() return #ns.points + 1 end -- the waypoints, then "Clear all"

local function DistanceText(p)
    local g = ns.Guide(p)
    if g.state == "ok" then return string.format("%d yd", g.yards + 0.5) end
    if g.state == "far" then return "|cff888888far|r" end
    return ""
end

function Manager.Refresh()
    if not (win and win:IsShown()) then return end
    local n = #ns.points
    sel = math.max(1, math.min(sel, Count()))
    if sel <= offset then offset = sel - 1 end
    if sel > offset + ROWS then offset = sel - ROWS end
    if n == 0 then
        win.empty:Show()
    else
        win.empty:Hide()
    end
    for r, row in ipairs(rows) do
        local i = offset + r
        if i <= n then
            local p = ns.points[i]
            local text = ns.Coords(p.x, p.y) .. "  |cffaaaaaa" .. ns.MapName(p.mapID) .. "|r"
            if p.label then text = p.label .. "  " .. text end
            row.mark:SetText(i == ns.active and "|cffffd100>|r" or "")
            row.text:SetText(text)
            row.right:SetText(DistanceText(p))
            row:Show()
        elseif i == n + 1 and n > 0 then
            row.mark:SetText("")
            row.text:SetText(confirming and "|cffff5050Clear all waypoints?|r" or "|cffff7070Clear all|r")
            row.right:SetText("")
            row:Show()
        else
            row:Hide()
        end
        if i == sel and row:IsShown() then
            row.bg:SetColorTexture(1, 0.82, 0, 0.25)
        else
            row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
        end
    end
    if n == 0 then
        win:SetHints("B Close   LB/RB  Add waypoint")
    elseif sel > n then
        win:SetHints(confirming and "A Yes, clear all   B No" or "A Clear all   B Close   LB/RB  Add")
    else
        win:SetHints("A Make active   X Edit   Y Remove   B Close   LB/RB  Add")
    end
end

local function Move(d)
    if #ns.points == 0 then return end
    confirming = false
    sel = (sel - 1 + d) % Count() + 1
    ns.Window.Tick()
    Manager.Refresh()
end

local function Close()
    win:Hide()
    ns.Window.Sound(false)
end

local function Accept()
    local n = #ns.points
    if n == 0 then return end
    if sel <= n then
        ns.SetActive(sel)
        ns.Window.Tick()
    elseif confirming then
        confirming = false
        ns.ClearAll()
        ns.Print("All waypoints cleared.")
    else
        confirming = true
        Manager.Refresh()
    end
end

local function Back()
    if confirming then
        confirming = false
        Manager.Refresh()
    else
        Close()
    end
end

local function EditSelected()
    if sel > #ns.points then return end
    win:Hide()
    ns.Editor.Open(sel, true)
end

local function RemoveSelected()
    if sel > #ns.points then return end
    ns.Print("Removed " .. ns.Describe(ns.points[sel]))
    ns.Remove(sel)
end

-- LB/RB: over to Add waypoint.
local function SwitchToEditor()
    win:Hide()
    ns.Editor.Open()
end

local function Create()
    win = ns.Window.New("WayPadManager", WIDTH, ROWS * ROW_H + 80, "Waypoints")
    rows = {}
    for r = 1, ROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetSize(WIDTH - 24, ROW_H)
        row:SetPoint("TOPLEFT", 12, -36 - (r - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.mark:SetPoint("LEFT", 4, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", 18, 0)
        row.text:SetPoint("RIGHT", -70, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function() -- touch / mouse: select, tap again to accept
            local i = offset + r
            if sel == i then Accept() else sel = i; confirming = false; Manager.Refresh() end
        end)
        rows[r] = row
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("CENTER", 0, 10)
    win.empty:SetText("No waypoints. Use your Add Waypoint button or /way.")

    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt) -- keep the distances fresh
        elapsed = elapsed + dt
        if elapsed > 0.5 then
            elapsed = 0
            Manager.Refresh()
        end
    end)

    ns.Input.New(win, {
        PADDUP = function() Move(-1) end,
        PADDDOWN = function() Move(1) end,
        PAD1 = Accept,
        PAD2 = Back,
        PAD3 = EditSelected,
        PAD4 = RemoveSelected,
        PADLSHOULDER = SwitchToEditor,
        PADRSHOULDER = SwitchToEditor,
    })
end

function Manager.Open()
    if InCombatLockdown() then
        ns.Print("Not in combat.")
        return
    end
    if not win then Create() end
    confirming = false
    sel = ns.active or 1
    win:Show()
    ns.Window.Sound(true)
    Manager.Refresh()
end

function Manager.Toggle()
    if win and win:IsShown() then Close() else Manager.Open() end
end
