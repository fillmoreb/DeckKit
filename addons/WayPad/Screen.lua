-- WayPad's window: one DeckKit screen (DeckKit/UI.lua) with two tabs, LB/RB between them.
--
--   Waypoints   the list: A makes one active (the compass points at it), X edits it, Y removes it;
--               "Clear all" at the bottom asks first. Each row: the active one ticked gold, its label
--               and coordinates, the zone, and how far it is (kept fresh while the tab is open).
--   Add         two dials, X and Y (45.2, 62.8: Blizzard's coordinates), starting at where you stand
--               in the zone you're in, so you only change what differs; A saves. Editing a waypoint
--               from the list opens this tab on its numbers instead ("Edit"), and saving goes back
--               to the list.
--
-- The Add waypoint chord / binding opens straight on Add (and closes the window again after saving);
-- the Waypoint list one on Waypoints.
local _, ns = ...
local UI = DeckKit.UI

local Editor, Manager = {}, {}
ns.Editor, ns.Manager = Editor, Manager

local WIDTH, HEIGHT = 470, 380
local LIST, ADD = 1, 2
local screen, listTab, addTab
local rows, empty, clearRow = {}, nil, nil
local x, y = 0, 0         -- the dials: tenths of a percent, 0-999 (452 = 45.2)
local mapID               -- the map the dials are on
local editId              -- the waypoint being edited (by id: list places shift), or nil for a new one
local pendingEdit         -- the id X asked to edit, for the Add tab to pick up as it shows
local closeAfterSave      -- opened straight on Add (the chord): close after saving

local function Tenths(v) return math.max(0, math.min(999, math.floor(v * 1000 + 0.5))) end

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------

local function Distance(p)
    local g = ns.Guide(p)
    if g.state == "ok" then return string.format("%d yd", g.yards + 0.5) end
    if g.state == "far" then return UI.Hex(UI.Color.dim) .. "far|r" end
    return ""
end

-- Row i of the list: a waypoint row, made on demand and reused.
local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, listTab.list.content)
    row:SetSize(WIDTH - 2 * 14 - 18 - 4, UI.ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * (UI.ROW_H + 2))
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)
    row:SetHighlightTexture(hl)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") -- the active one: selected = gold (UI.lua)
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", 6, 0)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetFontObject(UI.Font.body)
    row.text:SetPoint("LEFT", 30, 0)
    row.text:SetPoint("RIGHT", -70, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.dist = row:CreateFontString(nil, "OVERLAY")
    row.dist:SetFontObject(UI.Font.small)
    row.dist:SetPoint("RIGHT", -8, 0)
    row.index = i
    UI.Register(row, {
        prompts = function(self)
            local p = {}
            if self.index ~= ns.active then p[#p + 1] = { "A", "Make active" } end
            p[#p + 1] = { "X", "Edit" }
            p[#p + 1] = { "Y", "Remove" }
            return p
        end,
        activate = function(self) if ns.points[self.index] then ns.SetActive(self.index) end end,
        x = function(self)
            local p = ns.points[self.index]
            if not p then return end
            pendingEdit = p.id
            screen:SelectTab(ADD)
        end,
        y = function(self)
            local p = ns.points[self.index]
            if not p then return end
            ns.Print("Removed " .. ns.Describe(p))
            ns.Remove(self.index)
        end,
        refresh = function(self)
            local p = ns.points[self.index]
            if not p then return end
            local text = ns.Coords(p.x, p.y) .. "  " .. UI.Hex(UI.Color.dim) .. ns.MapName(p.mapID) .. "|r"
            if p.label then text = p.label .. "  " .. text end
            self.text:SetText(text)
            self.check:SetShown(self.index == ns.active)
            self.dist:SetText(Distance(p))
        end,
    })
    rows[i] = row
    return row
end

-- Lays the list out again after the waypoints change.
local function FillList()
    if not listTab then return end
    local n = #ns.points
    for i = 1, n do Row(i):Show() end
    for i = n + 1, #rows do rows[i]:Hide() end
    clearRow:ClearAllPoints()
    clearRow:SetPoint("TOPLEFT", 0, -n * (UI.ROW_H + 2) - 8)
    clearRow:SetShown(n > 0)
    empty:SetShown(n == 0)
    listTab.list:SetContentHeight(n * (UI.ROW_H + 2) + (n > 0 and UI.ROW_H + 8 or 0))
    -- Focus fell off the end (the last waypoint removed): onto the new last row, or nothing.
    local f = screen:Focused()
    if screen.win:IsShown() and screen.tab == LIST and not (f and f:IsVisible()) then
        screen:SetFocus(n > 0 and rows[n] or nil)
    end
end

local function BuildList()
    listTab = screen:AddTab("Waypoints")
    local list = UI.ScrollList(listTab.frame, WIDTH - 2 * 14, HEIGHT - 36 - 30 - 10 - 34 - 8 - 4)
    list:SetPoint("TOPLEFT", 0, 0)
    listTab.list = list
    empty = UI.Description(listTab.frame,
        DeckKit.Window.Glyphs("No waypoints yet. {LB} {RB} over to Add, or type /way 45.2 62.8."), WIDTH - 60)
    empty:SetPoint("CENTER", 0, 20)
    clearRow = UI.Action(list.content, WIDTH - 2 * 14 - 18 - 4, {
        label = UI.Hex(UI.Color.bad) .. "Clear all|r", verb = "Clear all",
        run = function()
            screen.mode, screen.capture = "confirm", clearRow
            clearRow.dk.confirmText = "Clear every waypoint"
            screen:UpdatePrompts()
        end,
    })
    clearRow.dk.confirmed = function(_, yes)
        if yes then
            ns.ClearAll()
            ns.Print("All waypoints cleared.")
        end
    end
    -- Distances change as you move: kept fresh while the list is up.
    local elapsed = 0
    listTab.frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        for i = 1, #ns.points do if rows[i] then rows[i].dist:SetText(Distance(ns.points[i])) end end
    end)
    listTab.onShow = function()
        FillList()
        -- Start on the active waypoint.
        if ns.active and rows[ns.active] then listTab.focus = rows[ns.active] end
    end
end

------------------------------------------------------------------------
-- Add / Edit
------------------------------------------------------------------------

local function Save()
    local px, py = x / 1000, y / 1000
    if editId then
        -- Found again by id: the list may have shifted while the tab was open (arriving at a waypoint
        -- removes it), and the one being edited may be gone.
        local i = ns.Find(editId)
        if i then
            ns.Edit(i, px, py)
            ns.Print("Waypoint moved to " .. ns.Describe(ns.points[i]))
        else
            ns.Print("That waypoint is gone (reached or removed), so nothing was changed.")
        end
        screen:SelectTab(LIST)
    else
        ns.Print("Waypoint added: " .. ns.Describe(ns.Add(mapID, px, py)))
        if closeAfterSave then screen:Hide() else screen:SelectTab(LIST) end
    end
end

local function BuildAdd()
    addTab = screen:AddTab("Add")
    local f = addTab.frame
    addTab.zone = f:CreateFontString(nil, "OVERLAY")
    addTab.zone:SetFontObject(UI.Font.heading)
    addTab.zone:SetPoint("TOP", 0, -8)
    local dx = UI.Dial(f, { label = "X (left - right)", digits = 3, point = 1,
        get = function() return x end, set = function(v) x = v end, activate = Save, verb = "Save" })
    local dy = UI.Dial(f, { label = "Y (top - bottom)", digits = 3, point = 1,
        get = function() return y end, set = function(v) y = v end, activate = Save, verb = "Save" })
    local w = dx:GetWidth()
    dx:SetPoint("TOP", -(w / 2 + 28), -44)
    dy:SetPoint("TOP", w / 2 + 28, -44)
    local comma = f:CreateFontString(nil, "OVERLAY")
    comma:SetFontObject(UI.Font.title)
    comma:SetPoint("BOTTOM", dx, "BOTTOMRIGHT", 28, 0)
    comma:SetText(",")
    addTab.dx = dx
    addTab.save = UI.Button(f, 200, { label = "Add waypoint", verb = "Save", run = Save })
    addTab.save:SetPoint("TOP", 0, -150)
    local here = UI.Action(f, 260, { label = "Start again from where I stand", verb = "Reset",
        disabled = function() return editId ~= nil end, reason = "Editing a waypoint: its own numbers",
        run = function()
            local m, px, py = ns.PlayerPosition()
            if m then mapID, x, y = m, Tenths(px), Tenths(py); addTab.zone:SetText(ns.MapName(m)) end
        end })
    here:SetPoint("TOP", 0, -190)
    addTab.onShow = function()
        editId, pendingEdit = pendingEdit, nil
        local p = editId and select(2, ns.Find(editId))
        if p then
            mapID, x, y = p.mapID, Tenths(p.x), Tenths(p.y)
        else
            editId = nil
            local m, px, py = ns.PlayerPosition()
            mapID = m
            x, y = Tenths(px or 0), Tenths(py or 0)
        end
        addTab.title = editId and "Edit" or "Add"
        screen:LayoutTabs()
        addTab.zone:SetText(mapID and ns.MapName(mapID) or "Can't read your position here")
        addTab.save:SetText(editId and "Save" or "Add waypoint")
        addTab.dx.pick = 1
        addTab.focus = addTab.dx
    end
end

local function Create()
    screen = UI.NewScreen("WayPadScreen", WIDTH, HEIGHT, "Waypoints")
    BuildList()
    BuildAdd()
end

------------------------------------------------------------------------
-- Opening it
------------------------------------------------------------------------

local function Open(tab, editIndex)
    if InCombatLockdown() then ns.Print("Not in combat.") return end
    if not screen then Create() end
    closeAfterSave = tab == ADD and not editIndex
    pendingEdit = editIndex and ns.points[editIndex] and ns.points[editIndex].id or nil
    screen.tab = tab
    if screen.win:IsShown() then screen:SelectTab(tab) else screen:Show() end
end

-- index: edit that waypoint; nil: add a new one.
function Editor.Open(index) Open(ADD, index) end
function Editor.Toggle()
    if screen and screen.win:IsShown() and screen.tab == ADD then screen:Hide() else Editor.Open() end
end
function Editor.IsShown() return screen ~= nil and screen.win:IsShown() and screen.tab == ADD end

function Manager.Open() Open(LIST) end
function Manager.Toggle()
    if screen and screen.win:IsShown() and screen.tab == LIST then screen:Hide() else Manager.Open() end
end

-- The waypoints changed (DeckKit.Waypoints.OnChange, Core.lua): the list follows.
function Manager.Refresh()
    if not (screen and screen.win:IsShown()) then return end
    FillList()
    screen:Refresh()
end
