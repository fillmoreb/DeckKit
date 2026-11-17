-- The grids on screen. Everything that has to work in combat is secure:
--   PadTouchGridHeader   holds both grids; shown and hidden from secure code only
--   PadTouchGridOpen     a grip chord slot mirrors this (type "click" on the toggle button below)
--   PadTouchGridToggle   its wrapped click opens the grids (and binds the click key and B), or closes them
--   PadTouchGridFire     the click key (F11, a pad click) clicks it: its wrapped click finds the cell under the
--                        pointer (IsUnderMouse: where the pad puts it), closes the grids and has that cell do its
--                        action; a click between cells does nothing and the grids stay
--   PadTouchGridClose    B clicks it: closes the grids
-- The keys are bound from secure code on the header while the grids are open, and cleared as they close: they do
-- nothing at any other time, so a stray pad click with the grids closed can't press anything. (DeckKit.Override
-- can't hold them: its claims follow macro conditions, and "the grids are open" isn't one.)
-- How a cell does its action: spells, items, slots and macros are its own attributes (DeckKit.Actions); an action
-- bar button is clicked through; DeckKit's own actions (peeks, windows) are run from insecure code, signalled with
-- an attribute as the grip chords do. The highlight under the pointer is drawn by insecure code: looks only.
local _, ns = ...
local UI, Actions = DeckKit.UI, DeckKit.Actions

local L = ns.LAYOUT
local GRID = 3 * L.cell + 2 * L.gap

local header = CreateFrame("Frame", "PadTouchGridHeader", UIParent, "SecureHandlerBaseTemplate")
header:SetAllPoints()
header:SetFrameStrata("DIALOG")
header:Hide()
ns.header = header

local cells = { left = {}, right = {} }
ns.cells = cells
local grids = {}

for _, side in ipairs(ns.SIDES) do
    local grid = CreateFrame("Frame", nil, header)
    grid:SetSize(GRID + 24, GRID + 46)
    local W, Hh = UIParent:GetWidth(), UIParent:GetHeight()
    grid:SetPoint("CENTER", UIParent, "TOPLEFT", L[side].x * W, -L[side].y * Hh + 11)
    local panel = UI.Panel(grid, nil)
    panel:SetAllPoints()
    grid.name = grid:CreateFontString(nil, "OVERLAY")
    grid.name:SetFontObject(UI.Font.small)
    grid.name:SetPoint("BOTTOM", 0, 10)
    grids[side] = grid
    for i = 1, ns.CELLS do
        local b = CreateFrame("Button", "PadTouchGrid" .. (side == "left" and "Left" or "Right") .. i, grid,
            "SecureActionButtonTemplate")
        UI.ActionArt(b, L.cell)
        b:EnableMouse(false)
        -- The cell under the pointer: our own texture (insecure code may show it in combat; a secure button's
        -- own highlight it may not touch).
        b.hover = b:CreateTexture(nil, "OVERLAY", nil, 3)
        b.hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        b.hover:SetBlendMode("ADD")
        b.hover:SetAllPoints()
        b.hover:Hide()
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        b:SetPoint("TOPLEFT", 12 + col * (L.cell + L.gap), -12 - row * (L.cell + L.gap))
        b.side, b.index = side, i
        cells[side][i] = b
    end
end

-- The toggle, and the source a chord slot mirrors to click it.
local toggle = CreateFrame("Button", "PadTouchGridToggle", UIParent, "SecureActionButtonTemplate")
local fire = CreateFrame("Button", "PadTouchGridFire", UIParent, "SecureActionButtonTemplate")
fire:RegisterForClicks("AnyDown")
local close = CreateFrame("Button", "PadTouchGridClose", UIParent, "SecureActionButtonTemplate")
close:RegisterForClicks("AnyDown")
local open = CreateFrame("Button", "PadTouchGridOpen", UIParent, "SecureActionButtonTemplate")
open:SetAttribute("type", "click")
open:SetAttribute("clickbutton", toggle)

header:SetAttribute("clickKey", ns.CLICK_KEY)
header:SetAttribute("closeKey", ns.CLOSE_KEY)
local n = 0
for _, side in ipairs(ns.SIDES) do
    for i = 1, ns.CELLS do
        n = n + 1
        header:SetFrameRef("cell" .. n, cells[side][i])
    end
end
header:Execute(([[ seq = 0; NCELLS = %d
    OpenGrids = [=[
        self:Show()
        self:SetBindingClick(true, self:GetAttribute("clickKey"), "PadTouchGridFire")
        self:SetBindingClick(true, self:GetAttribute("closeKey"), "PadTouchGridClose")
    ]=]
    CloseGrids = [=[
        self:ClearBindings()
        self:Hide()
    ]=]
]]):format(n))

header:WrapScript(toggle, "OnClick", [[
    if owner:IsShown() then owner:Run(CloseGrids) else owner:Run(OpenGrids) end
    return false
]])
header:WrapScript(close, "OnClick", [[
    owner:Run(CloseGrids)
    return false
]])
header:WrapScript(fire, "OnClick", [[
    self:SetAttribute("type", nil)
    self:SetAttribute("clickbutton", nil)
    if not owner:IsShown() then return false end
    local hit
    for n = 1, NCELLS do
        local c = owner:GetFrameRef("cell" .. n)
        if c:IsVisible() and c:IsUnderMouse() then hit = c break end
    end
    if not hit then return false end
    owner:Run(CloseGrids)
    local run = hit:GetAttribute("ptg-run")
    if run then
        seq = seq + 1
        owner:SetAttribute("run", run .. " " .. seq)
        return false
    end
    if not hit:GetAttribute("type") then return false end
    self:SetAttribute("type", "click")
    self:SetAttribute("clickbutton", hit)
]])

-- DeckKit's own actions (run from insecure code), as the grip chords run them.
header:HookScript("OnAttributeChanged", function(_, name, value)
    if name ~= "run" or not value then return end
    local id = value:match("^(%S+)")
    local o = Actions.Offered(id)
    ns.Debug("cell run", id)
    if o and o.run then
        local ok, err = pcall(o.run, true)
        if ok then ok, err = pcall(o.run, false) end
        if not ok then geterrorhandler()(err) end
    end
end)

-- Every cell's action on its button (out of combat: Core.lua's ns.Apply).
local CLEAR = { "type", "spell", "item", "macro", "macrotext", "action", "clickbutton", "ptg-run" }
function ns.ApplyCells()
    for _, side in ipairs(ns.SIDES) do
        for i, b in ipairs(cells[side]) do
            for _, k in ipairs(CLEAR) do b:SetAttribute(k, nil) end
            local id = ns.Get(side, i)
            local kind, ref = Actions.Kind(id)
            if kind == "run" then
                b:SetAttribute("ptg-run", id)
            elseif kind == "mirror" then
                local src = _G[ref]
                if src then
                    b:SetAttribute("type", "click")
                    b:SetAttribute("clickbutton", src)
                end
            elseif kind then
                for k, v in pairs(Actions.Attributes(id) or {}) do b:SetAttribute(k, v) end
            end
        end
    end
end

-- Looks: each cell's icon, count and whether it's usable now; the cell under the pointer lit and named.
local function Draw()
    for _, side in ipairs(ns.SIDES) do
        for i, b in ipairs(cells[side]) do UI.DrawAction(b, ns.Get(side, i)) end
    end
end
ns.OnChange(Draw)
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "UPDATE_MACROS", "PLAYER_EQUIPMENT_CHANGED" }) do
    ns.On(e, function() if header:IsShown() then Draw() end end)
end

local lit
header:HookScript("OnShow", function() Draw(); ns.Debug("open") end)
header:HookScript("OnHide", function()
    if lit then lit.hover:Hide(); lit = nil end
    for _, side in ipairs(ns.SIDES) do grids[side].name:SetText("") end
end)
header:HookScript("OnUpdate", function()
    local over
    for _, side in ipairs(ns.SIDES) do
        for _, b in ipairs(cells[side]) do if b:IsMouseOver() then over = b end end
    end
    if over == lit then return end
    if lit then lit.hover:Hide() end
    lit = over
    for _, side in ipairs(ns.SIDES) do grids[side].name:SetText("") end
    if over then
        over.hover:Show()
        local id = ns.Get(over.side, over.index)
        grids[over.side].name:SetText(id and Actions.Label(id) or "")
    end
end)

-- The grids' state, for tests and /deckkit touchgrid.
function ns.IsOpen() return header:IsShown() end
function ns.Lit() return lit end
