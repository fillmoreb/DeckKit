-- Binding the cells: a DeckKit window with the two grids as they sit on screen, left pad's on the left. The d-pad
-- moves over all 18 cells; X on one opens DeckKit's action picker (LB/RB lists, A chooses, B leaves it). Opened
-- from the menu (Controls > Touch grids) or /deckkit touchgrid. The grids themselves open with a grip chord slot
-- set to "Touch grids" (Controls > Grips).
local _, ns = ...
local UI, Actions = DeckKit.UI, DeckKit.Actions

-- A grip chord slot (or any key) opens them: the grip button clicks PadTouchGridOpen's target, secure.
Actions.Offer("PADTOUCHGRID_OPEN", { label = "Touch grids", mirror = "PadTouchGridOpen",
    icon = "Interface\\Icons\\INV_Misc_Note_02" })

local WIDTH, HEIGHT = 760, 440
local SLOT = 60
local screen

local function Build()
    screen = UI.NewScreen("PadTouchGridEditor", WIDTH, HEIGHT, "Touch grids")
    local tab = screen:AddTab("Cells")
    local PANEL_W = (WIDTH - 28 - 12) / 2
    for s, side in ipairs(ns.SIDES) do
        local panel = UI.Panel(tab.frame, ns.SIDE_NAMES[side])
        panel:SetSize(PANEL_W, 300)
        panel:SetPoint("TOPLEFT", (s - 1) * (PANEL_W + 12), 0)
        local slots = {}
        for i = 1, ns.CELLS do
            slots[i] = UI.ActionSlot(panel, { size = SLOT, title = ns.CellName(side, i),
                get = function() return ns.Get(side, i) end,
                set = function(id) ns.Set(side, i, id) end })
        end
        local gridW = 3 * SLOT + 2 * 26
        UI.Grid(slots, panel, 3, SLOT, 26, (PANEL_W - gridW) / 2, panel.top - 6)
        panel.name = UI.Heading(panel, "")
        panel.name:SetFontObject(UI.Font.small)
        panel.name:SetPoint("BOTTOM", 0, 14)
        for i, slot in ipairs(slots) do
            slot.dk.onFocus = function()
                local id = ns.Get(side, i)
                panel.name:SetText(ns.CellName(side, i) .. ": " .. (id and Actions.Label(id) or "empty"))
            end
            slot.dk.onBlur = function() panel.name:SetText("") end
        end
    end
    local note = UI.Description(tab.frame, "{X} on a cell chooses what it does. In the game a grip chord slot set to "
        .. "Touch grids (Controls › Grips) opens both grids; rest a thumb on a pad to light a cell, click the pad "
        .. "to use it. {B} closes them.", WIDTH - 40)
    note:SetPoint("TOPLEFT", 4, -312)
end

function ns.OpenEditor()
    if InCombatLockdown() then ns.Print("can't open in combat.") return end
    if not screen then Build() end
    screen:Show()
end
ns.Editor = function() return screen end

ns.AddCommand("touchgrid", function() ns.OpenEditor() end, "bind the touch grids' cells")

ns.AddSettings({
    { type = "section", tab = "Controls", label = "Touch grids", order = 4 },
    { type = "action", label = "Set the touch grids' cells", verb = "Open",
      hint = "Two 3x3 grids of actions, one under each trackpad. A grip chord slot set to Touch grids opens them;"
          .. " a thumb on a pad lights its cell, a pad click uses it, {B} closes them. Works in combat.",
      run = function() ns.OpenEditor() end },
    { type = "info", label = "Open them with a grip chord: set a slot to Touch grids in Controls › Grips. The pads"
        .. " need DeckKit's Steam layout (Mouse Region, clicks send F11)." },
})
