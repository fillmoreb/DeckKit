-- PackPad: item marks, and a bounce when the bags open.
--
-- Marks: other addons (DeckAgent's "flag these items", for one) mark items by ID; every stack of a marked
-- item gets a lilac star (on a dark shadow) in its slot's top-right corner (Blizzard's upgrade arrow keeps
-- the top-left), and its tooltip says why ("Flagged: Red Linen Bag"). Marks are kept per character until cleared.
--   PackPad_SetMarks(source, itemIDs, label)   marks the items for `source` (replacing its last set)
--   PackPad_ClearMarks(source)                 clears `source`'s marks (nil: all of them)
--   PackPad_GetMarks()                         { [source] = { label, ids = { [itemID] = true } } }
--
-- Bounce: when the bags open, every mark and every upgrade arrow (Blizzard's UpgradeIcon slot, whoever
-- shows it) hops four times, to draw the eye, then twice every 10 seconds while the bags stay open.
--
-- Like the rest of PackPad: the marks are PackPad's own textures, kept in PackPad's tables (nothing written
-- onto Blizzard's buttons), and textures are fine to add to the open frame (frames are not).
local _, ns = ...

local MARK_ATLAS = "Bonus-Objective-Star"
local GOLD = { 1, 0.82, 0 } -- the tooltip line
local MARK_SIZE = 24 -- in the button's own units (the button is scaled with the slots: ~17 px at 70%)
local HOP, HOP_TIME = 5, 0.16 -- pixels up (the first hop; each after is smaller), seconds per half-hop
local OPEN_HOPS, NUDGE_HOPS, NUDGE_EVERY = 4, 2, 10 -- hops on opening; a nudge every 10 s while open

local Marks = {}
ns.Marks = Marks

local marks = {} -- button -> star texture
local shadows = {} -- button -> the dark blot behind its star (so the star shows on any icon)
local anims = {} -- texture -> { [hops] = its bounce }

local function DB()
    PackPadDB = PackPadDB or {}
    PackPadDB.marks = PackPadDB.marks or {}
    return PackPadDB.marks
end

-- itemID -> the labels marking it.
local function Labels(itemID)
    local out
    for _, m in pairs(DB()) do
        if m.ids and m.ids[itemID] then
            out = out or {}
            out[#out + 1] = m.label
        end
    end
    return out
end

------------------------------------------------------------------------
-- The bounce
------------------------------------------------------------------------

local function Bounce(tex, hops)
    anims[tex] = anims[tex] or {}
    local anim = anims[tex][hops]
    if not anim then
        anim = tex:CreateAnimationGroup()
        for i = 1, hops do
            local up = anim:CreateAnimation("Translation")
            up:SetOffset(0, HOP / i)
            up:SetDuration(HOP_TIME)
            up:SetSmoothing("OUT")
            up:SetOrder(2 * i - 1)
            local down = anim:CreateAnimation("Translation")
            down:SetOffset(0, -HOP / i)
            down:SetDuration(HOP_TIME)
            down:SetSmoothing("IN")
            down:SetOrder(2 * i)
        end
        anims[tex][hops] = anim
    end
    for _, other in pairs(anims[tex]) do other:Stop() end
    anim:Play()
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------

local function Mark(button)
    local tex = marks[button]
    if not tex then
        tex = button:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetAtlas(MARK_ATLAS)
        tex:SetDesaturated(true)
        tex:SetVertexColor(0.72, 0.48, 1.00) -- lilac, desaturated first; on a black shadow so it shows on any icon
        tex:SetSize(MARK_SIZE, MARK_SIZE)
        tex:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
        marks[button] = tex
        -- A soft dark blot under it: the star's own shape, black and a little larger.
        local shadow = button:CreateTexture(nil, "OVERLAY", nil, 5)
        shadow:SetAtlas(MARK_ATLAS)
        shadow:SetVertexColor(0, 0, 0, 0.9)
        shadow:SetSize(MARK_SIZE + 6, MARK_SIZE + 6)
        shadow:SetPoint("CENTER", tex, "CENTER", 0, 0)
        shadows[button] = shadow
    end
    return tex
end

------------------------------------------------------------------------
-- Upgrade arrows, remembered for the bag peek
------------------------------------------------------------------------

-- Whoever draws upgrade arrows on the bag buttons (Blizzard's UpgradeIcon, or an addon's own texture in
-- Blizzard's green arrow atlas), the bag peek shows the same arrow. The peek draws while the bags are
-- closed, when the bag buttons are gone, so the arrows are remembered per item link each time the bag
-- window lays out: link -> { corner, desaturated, rotation, r, g, b } or false (seen, no arrow).
-- Forgotten when your gear changes, since what counts as an upgrade changes with it.
local ARROW_ATLAS = "bags-greenarrow"
local arrows = {}

local function ArrowOf(button)
    local icon = button.UpgradeIcon
    if icon and icon:IsShown() and icon:GetAlpha() > 0 then return icon end
    for _, r in ipairs({ button:GetRegions() }) do
        if r ~= marks[button] and r.GetAtlas and r:GetAtlas() == ARROW_ATLAS and r:IsShown() and r:GetAlpha() > 0 then
            return r
        end
    end
end

function Marks.RememberArrows(frame)
    for _, button in ipairs(frame.Items or {}) do
        if button:IsShown() and button.GetBagID then
            local link = C_Container.GetContainerItemLink(button:GetBagID(), button:GetID())
            if link then
                local a = ArrowOf(button)
                if a then
                    local corner = a:GetPoint(1)
                    local r, g, b = a:GetVertexColor()
                    arrows[link] = { corner = corner or "TOPLEFT", desaturated = a:IsDesaturated(),
                        rotation = a.GetRotation and a:GetRotation() or 0, r = r, g = g, b = b }
                else
                    arrows[link] = false
                end
            end
        end
    end
end

-- The remembered arrow for an item link (nil: never seen in the open bags; false: no arrow).
function Marks.Arrow(link) return link and arrows[link] end

function Marks.ForgetArrows() wipe(arrows) end -- on gear changes (hooked up in Peek.lua; ns.On comes later)

-- Shows each slot's mark (or not) from its item. Called after PackPad lays the bags out.
function Marks.Refresh(frame)
    -- Arrow makers update after the layout too: read theirs a moment later.
    C_Timer.After(0.3, function() if frame:IsShown() then Marks.RememberArrows(frame) end end)
    for _, button in ipairs(frame.Items or {}) do
        local itemID
        if button:IsShown() and button.GetBagID then
            itemID = C_Container.GetContainerItemID(button:GetBagID(), button:GetID())
        end
        local on = itemID ~= nil and Labels(itemID) ~= nil
        if on then
            Mark(button):Show()
            shadows[button]:Show()
        elseif marks[button] then
            marks[button]:Hide()
            shadows[button]:Hide()
        end
    end
end

-- Bounces every shown mark and upgrade arrow: longer when the bags open (hops nil), a short nudge after.
function Marks.BounceAll(frame, hops)
    hops = hops or OPEN_HOPS
    for _, button in ipairs(frame.Items or {}) do
        if button:IsVisible() then
            local m = marks[button]
            if m and m:IsShown() then
                Bounce(m, hops)
                Bounce(shadows[button], hops)
            end
            local arrow = button.UpgradeIcon
            if arrow and arrow:IsShown() and arrow:GetAlpha() > 0 then Bounce(arrow, hops) end
        end
    end
end

-- The nudge: every NUDGE_EVERY seconds while the bags are open.
local nudger
function Marks.StartNudging(frame)
    if nudger then nudger:Cancel() end
    nudger = C_Timer.NewTicker(NUDGE_EVERY, function()
        if frame:IsShown() then Marks.RememberArrows(frame); Marks.BounceAll(frame, NUDGE_HOPS) else Marks.StopNudging() end
    end)
end
function Marks.StopNudging()
    if nudger then nudger:Cancel(); nudger = nil end
end

------------------------------------------------------------------------
-- The API, the tooltip line, clearing
------------------------------------------------------------------------

local function Refresh()
    local frame = ContainerFrameCombinedBags
    if frame and frame:IsShown() then Marks.Refresh(frame) end
end

function PackPad_SetMarks(source, itemIDs, label)
    if type(source) ~= "string" then return false end
    local ids = {}
    for _, id in ipairs(itemIDs or {}) do
        if type(id) == "number" then ids[id] = true end
    end
    DB()[source] = next(ids) and { label = tostring(label or source), ids = ids, at = time() } or nil
    Refresh()
    return true
end

function PackPad_ClearMarks(source)
    if source == nil then wipe(DB()) else DB()[source] = nil end
    Refresh()
end

function PackPad_GetMarks() return DB() end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local id = data and data.id
        if type(id) ~= "number" or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
        local labels = PackPadDB and PackPadDB.marks and Labels(id)
        if labels then tooltip:AddLine("Flagged: " .. table.concat(labels, ", "), GOLD[1], GOLD[2], GOLD[3]) end
    end)
end

function Marks.ClearAll() PackPad_ClearMarks(nil) end
function Marks.IsMarked(itemID) return itemID ~= nil and PackPadDB ~= nil and PackPadDB.marks ~= nil and Labels(itemID) ~= nil end
