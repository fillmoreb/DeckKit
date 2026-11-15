-- PackPad: the bag peek. Hold its grip slot (Controls > Grips: "Bag peek") to see everything you carry,
-- full screen, big icons; let go and it's gone. Like ChatDeck's and MapDeck's peeks it takes no buttons
-- and neither stick, so you keep full control of your character, and it works in combat (it's only
-- drawing). It reads the bags itself (C_Container), so the bag window needn't be open.
--
-- The same grids as the bag window (Bags, Reagents, each profession bag type, Keyring; empty slots in
-- place; the keyring only its keys; a grid with nothing in it is left out), without the bag icon column, at the icon size that fills the screen best: every column count
-- is tried and the one giving the biggest icons that still fit wins. Quality borders, stack counts and
-- item marks (the lilac star) as in the bags, and Pawn's upgrade arrows (see Upgrade below). Your money
-- sits under the grids on the right, as in the bag window's footer.
local _, ns = ...

local MARGIN, LABEL_H, GAP = 40, 24, 0.12 -- screen margin; a grid's label; the gap between slots (of a slot)
local MONEY_H = 36 -- the money line under the grids, right-aligned like the bag window's footer
local MAX_SLOT = 96 -- the biggest a slot gets (a few items on a big screen)
local STAR = 0.5 -- the mark's size, of a slot
local ARROW = 0.42 -- an upgrade arrow's size, of a slot

local frame, cells, labels = nil, {}, {}
local Arrow -- below

local function Create()
    frame = CreateFrame("Frame", "PackPadPeek", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.82)
    frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.money:SetFont(GameFontHighlightLarge:GetFont(), 22, "OUTLINE")
    frame.money:SetJustifyH("RIGHT")
    frame:Hide()
end

local function Money()
    frame.money:SetText(GetMoneyString(GetMoney(), true))
end

-- The bags as grids: { label, slots = { info or false } } in the bag window's order.
local function Grids()
    local order, index = {}, {}
    local function Grid(key, label)
        if not index[key] then
            index[key] = { label = label, slots = {} }
            order[#order + 1] = key
        end
        return index[key]
    end
    Grid("bags", nil)
    Grid("reagent", "Reagents")
    for _, bag in ipairs({ 0, 1, 2, 3, 4, ns.REAGENT, ns.KEYRING }) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        if n > 0 then
            local key, label = ns.GroupOf(bag)
            local g = Grid(key, label)
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then info.link = C_Container.GetContainerItemLink(bag, slot) end
                -- The keyring shows only its keys, packed together; other bags keep empty slots in place.
                if info or bag ~= ns.KEYRING then g.slots[#g.slots + 1] = info or false end
            end
        end
    end
    -- A grid with nothing in it (an empty keyring, say) is left out, except the bags themselves.
    local out = {}
    for _, key in ipairs(order) do
        local g, any = index[key], key == "bags"
        for _, info in ipairs(g.slots) do any = any or info ~= false end
        if #g.slots > 0 and any then out[#out + 1] = g end
    end
    return out
end

-- The column count giving the biggest slots that fit: returns columns, slot size.
local function BestFit(grids, w, h)
    local bestC, bestS = 10, 0
    for c = 4, 40 do
        local rows = 0
        for _, g in ipairs(grids) do rows = rows + math.ceil(#g.slots / c) end
        local labelsH = (#grids - 1) * LABEL_H + MONEY_H
        local s = math.min(w / (c + (c - 1) * GAP), (h - labelsH) / (rows + (rows - 1) * GAP))
        if s > bestS then bestC, bestS = c, s end
    end
    return bestC, math.min(bestS, MAX_SLOT)
end

local function Cell(i)
    local c = cells[i]
    if not c then
        c = {}
        c.bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.bg:SetAtlas("bags-item-slot64")
        c.icon = frame:CreateTexture(nil, "ARTWORK")
        c.border = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        c.border:SetTexture("Interface\\Common\\WhiteIconFrame")
        c.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        c.shadow = frame:CreateTexture(nil, "OVERLAY", nil, 5)
        c.shadow:SetAtlas("Bonus-Objective-Star")
        c.shadow:SetVertexColor(0, 0, 0, 0.9)
        c.star = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        c.star:SetAtlas("Bonus-Objective-Star")
        c.star:SetDesaturated(true)
        c.star:SetVertexColor(0.72, 0.48, 1.00)
        c.arrow = frame:CreateTexture(nil, "OVERLAY", nil, 4)
        c.arrow:SetAtlas("bags-greenarrow")
        cells[i] = c
    end
    return c
end

local function HideCell(c)
    for _, r in pairs(c) do
        if type(r) == "table" and r.Hide then r:Hide() end
    end
    c.link = nil
end

-- Upgrade arrows. Pawn answers for any item, fresh drops included, by its own documented route for bag
-- addons: PawnShouldItemLinkHaveUpgradeArrow(link, true) is true or false, or nil for "not yet" (the item
-- isn't cached, or Pawn's time budget is spent), so those cells ask again shortly. Without Pawn, the
-- arrows the bag window last showed (Marks.RememberArrows) stand in.
local PAWN_ARROW = { corner = "TOPLEFT" }
local pending = {} -- cells Pawn hasn't answered for yet

local function Upgrade(link)
    if PawnShouldItemLinkHaveUpgradeArrow then
        local ok, up = pcall(PawnShouldItemLinkHaveUpgradeArrow, link, true)
        if not ok then return false end
        if up == nil then return nil end
        return up and PAWN_ARROW or false
    end
    return ns.Marks and ns.Marks.Arrow(link) or false
end

Arrow = function(c)
    local up = c.link and Upgrade(c.link)
    if up == nil then pending[c] = true; up = false else pending[c] = nil end
    if up then
        local s, corner = c.size, up.corner or "TOPLEFT"
        c.arrow:SetSize(s * ARROW, s * ARROW)
        c.arrow:ClearAllPoints()
        c.arrow:SetPoint(corner, c.bg, corner, 0, 0)
        c.arrow:SetDesaturated(up.desaturated and true or false)
        c.arrow:SetRotation(up.rotation or 0)
        c.arrow:SetVertexColor(up.r or 1, up.g or 1, up.b or 1)
    end
    c.arrow:SetShown(up and true or false)
end

local retry
local function Retry()
    retry = nil
    if not (frame and frame:IsShown()) then wipe(pending); return end
    local cellsNow = {}
    for c in pairs(pending) do cellsNow[#cellsNow + 1] = c end
    for _, c in ipairs(cellsNow) do Arrow(c) end
    if next(pending) then retry = true; C_Timer.After(0.25, Retry) end
end

local function Fill()
    local grids = Grids()
    local w, h = UIParent:GetWidth() - 2 * MARGIN, UIParent:GetHeight() - 2 * MARGIN
    local cols, s = BestFit(grids, w, h)
    local step = s * (1 + GAP)
    -- The whole block, centered.
    local rows = 0
    for _, g in ipairs(grids) do rows = rows + math.ceil(#g.slots / cols) end
    local blockW = cols * step - s * GAP
    local blockH = rows * step - s * GAP + (#grids - 1) * LABEL_H
    local left, top = (UIParent:GetWidth() - blockW) / 2, (UIParent:GetHeight() - blockH - MONEY_H) / 2
    frame.money:ClearAllPoints()
    frame.money:SetPoint("TOPRIGHT", frame, "TOPLEFT", left + blockW, -(top + blockH + 10))
    Money()

    local n, y = 0, 0
    for gi, g in ipairs(grids) do
        if gi > 1 then
            local label = labels[gi]
            if not label then
                label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                label:SetJustifyH("LEFT")
                labels[gi] = label
            end
            label:SetText(g.label or "")
            label:ClearAllPoints()
            label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", left, -(top + y + LABEL_H - 4))
            label:Show()
            y = y + LABEL_H
        end
        for i, info in ipairs(g.slots) do
            n = n + 1
            local c = Cell(n)
            local x = left + ((i - 1) % cols) * step
            local cy = top + y + math.floor((i - 1) / cols) * step
            c.bg:ClearAllPoints()
            c.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -cy)
            c.bg:SetSize(s, s)
            c.bg:Show()
            if info then
                c.icon:ClearAllPoints()
                c.icon:SetPoint("TOPLEFT", c.bg, "TOPLEFT", s * 0.04, -s * 0.04)
                c.icon:SetPoint("BOTTOMRIGHT", c.bg, "BOTTOMRIGHT", -s * 0.04, s * 0.04)
                c.icon:SetTexture(info.iconFileID)
                c.icon:Show()
                local q = info.quality
                if q and q >= 2 then
                    local r, gg, b = C_Item.GetItemQualityColor(q)
                    c.border:SetAllPoints(c.bg)
                    c.border:SetVertexColor(r, gg, b)
                    c.border:Show()
                else
                    c.border:Hide()
                end
                if (info.stackCount or 1) > 1 then
                    c.count:SetFont(NumberFontNormal:GetFont(), math.max(12, math.floor(s * 0.3)), "OUTLINE")
                    c.count:SetText(info.stackCount)
                    c.count:ClearAllPoints()
                    c.count:SetPoint("BOTTOMRIGHT", c.bg, "BOTTOMRIGHT", -s * 0.06, s * 0.06)
                    c.count:Show()
                else
                    c.count:Hide()
                end
                local marked = ns.Marks and ns.Marks.IsMarked(info.itemID)
                if marked then
                    c.star:SetSize(s * STAR, s * STAR)
                    c.star:ClearAllPoints()
                    c.star:SetPoint("TOPRIGHT", c.bg, "TOPRIGHT", s * 0.08, s * 0.08)
                    c.shadow:SetSize(s * STAR * 1.25, s * STAR * 1.25)
                    c.shadow:ClearAllPoints()
                    c.shadow:SetPoint("CENTER", c.star, "CENTER")
                end
                c.star:SetShown(marked)
                c.shadow:SetShown(marked)
                c.link, c.size = info.link, s
                Arrow(c)
            else
                c.link = nil
                pending[c] = nil
                c.arrow:Hide()
                c.icon:Hide()
                c.border:Hide()
                c.count:Hide()
                c.star:Hide()
                c.shadow:Hide()
            end
        end
        y = y + math.ceil(#g.slots / cols) * step
    end
    for i = n + 1, #cells do HideCell(cells[i]); pending[cells[i]] = nil end
    if next(pending) and not retry then retry = true; C_Timer.After(0.25, Retry) end
    for i = #grids + 1, #labels do labels[i]:Hide() end
    if labels[1] then labels[1]:Hide() end
end

local function Peek(on)
    if not on then
        if frame then frame:Hide() end
    elseif not (frame and frame:IsShown()) then
        if not frame then Create() end
        Fill()
        frame:Show()
    end
end

ns.On("PLAYER_LOGIN", function() if not frame then Create() end end) -- ready before the first mid-fight peek
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Marks.ForgetArrows() end)
ns.On("PLAYER_MONEY", function() if frame and frame:IsShown() then Money() end end)
ns.On("BAG_UPDATE_DELAYED", function() if frame and frame:IsShown() then Fill() end end)

DeckKit.Chords.Offer("PACKPAD_PEEK", { label = "Bag peek", run = function(down) Peek(down) end })

ns.AddCommand("bagpeek", function()
    Peek(not (frame and frame:IsShown()))
end, "PackPad: show or hide the bag peek (for testing; hold its grip slot in play)")
