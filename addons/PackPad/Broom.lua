-- PackPad: the broom (Clean Up Bags, C_Container.SortBags) in the bag window's footer, left of the money. Blizzard
-- hides its own sort button in the gamepad UI (Clean Up Bags is otherwise in the portrait's menu).
--
-- Reaching it with the controller (from BagPad's HeaderNav; MIT, see LICENSE): Down from the bottom row
-- of the bags selects it; A cleans up; Up or B goes back. The broom lives outside Blizzard's bag frame
-- (its own holder on UIParent, matched to the bags' scale), so it never joins Blizzard's cursor grid:
-- a button inside the frame would get a grid column of its own or lengthen an item column, and telling
-- Blizzard "Up from here goes there" would mean writing onto its item buttons, which taints. PackPad
-- only reads which button Blizzard's cursor is on (SmartNavigation.currentButton) and whether the bags
-- have the controller focus; it never calls into either.
--
-- Two invisible input states (DeckKit.Input takes its keys for as long as its window is shown):
--   armed     shown only while Blizzard's cursor is on the bottom row: takes Down, to select the broom
--   selected  while the broom is selected: takes the d-pad, A and B (Blizzard's cursor stays put)
-- Nothing is taken in combat.
--
-- While the broom is selected it looks like a native control: Blizzard's pointer (SmartNavigation.Pointer)
-- fades out, the item it was on loses its locked highlight, and the game's chevron (the same template)
-- points at the broom. Going back puts both back and shows the item's tooltip again (the tooltip API,
-- GameTooltip:SetBagItem: calling Blizzard's own OnEnter from addon code would taint). Only widget methods
-- on Blizzard's frames (SetAlpha, SetHighlightLocked), never its Lua.
local _, ns = ...

local SIZE = 22

local Broom = {}
ns.Broom = Broom

local holder, button, pointer, armed, selected, watcher
local leftItem -- the item Blizzard's cursor was on when the broom was selected

local function BagFrame() return ContainerFrameCombinedBags end

local function BagsHaveFocus()
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    return manager ~= nil and manager.isUIFocused == true and manager.focusedFrame == BagFrame()
end

local function OnBottomRow()
    local current = SmartNavigation and SmartNavigation.currentButton
    return current ~= nil and ns.bottomRow ~= nil and ns.bottomRow[current] == true
end

local function BlizzardPointer(alpha)
    local p = SmartNavigation and SmartNavigation.Pointer
    if p then p:SetAlpha(alpha) end
end

local function Highlight(on)
    if on then
        leftItem = SmartNavigation and SmartNavigation.currentButton
        BlizzardPointer(0)
        if leftItem and leftItem.SetHighlightLocked then leftItem:SetHighlightLocked(false) end
        button:LockHighlight()
        if pointer then DeckKit.UI.PlacePointer(pointer, button) end -- the game's chevron, as DeckKit's windows place it
        button:GetScript("OnEnter")(button)
    else
        button:UnlockHighlight()
        if pointer then pointer:Hide() end
        if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
        BlizzardPointer(1)
        local item = leftItem
        leftItem = nil
        if item and SmartNavigation and SmartNavigation.currentButton == item then
            if item.SetHighlightLocked then item:SetHighlightLocked(true) end
            if item.GetBagID and item:IsVisible() then
                -- Where Blizzard's gamepad UI puts an item's tooltip (read off the game: ANCHOR_LEFT, its
                -- bottom-right on the slot's top-left), and nothing else: Blizzard fades it in itself.
                GameTooltip:SetOwner(item, "ANCHOR_LEFT")
                GameTooltip:SetBagItem(item:GetBagID(), item:GetID())
            end
        end
    end
end

local function Leave()
    if selected:IsShown() then
        selected:Hide()
        Highlight(false)
    end
end

local function Select()
    armed:Hide()
    selected:Show()
    Highlight(true)
end

local function Clean()
    Leave()
    C_Timer.After(0, function()
        PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
        C_Container.SortBags()
    end)
end

function Broom.Create()
    local frame = BagFrame()
    holder = CreateFrame("Frame", "PackPadBroomHolder", UIParent)
    holder:SetFrameStrata("HIGH")
    holder:SetAllPoints(UIParent)
    holder:Hide()

    button = CreateFrame("Button", "PackPadBroom", holder)
    button:SetSize(SIZE, SIZE)
    button:SetNormalAtlas("bags-button-autosort-up")
    button:SetPushedAtlas("bags-button-autosort-down")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:RegisterForClicks("LeftButtonUp")
    -- The footer's left end, just left of the money bar (Core.lua ApplyMoney), centered on it.
    button:SetPoint("LEFT", frame, "BOTTOMLEFT", 9, 8 + (frame.MoneyFrame and frame.MoneyFrame:GetHeight() or 22) / 2)
    button:SetScript("OnClick", Clean)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(BAG_CLEANUP_BAGS or "Clean Up Bags")
        if BAG_CLEANUP_BAGS_DESCRIPTION then GameTooltip:AddLine(BAG_CLEANUP_BAGS_DESCRIPTION, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pointer = DeckKit.UI.MakePointer(holder)

    armed = CreateFrame("Frame", nil, UIParent)
    armed:Hide()
    ns.Input.New(armed, { PADDDOWN = Select }, { shared = true }) -- a button on Blizzard's bag window
    selected = CreateFrame("Frame", nil, UIParent)
    selected:Hide()
    local stay = function() end
    ns.Input.New(selected, { PADDDOWN = stay, PADDLEFT = stay, PADDRIGHT = stay, PADDUP = Leave, PAD2 = Leave,
        PAD1 = Clean }, { shared = true })

    -- Arms on the top row, drops the selection if the bags lose focus or a fight starts.
    watcher = CreateFrame("Frame", nil, holder)
    watcher:SetScript("OnUpdate", function()
        -- Not while a DeckKit window has the pad: its presses aren't the bags'.
        local ok = not InCombatLockdown() and BagsHaveFocus() and not ns.Input.Owned()
        if selected:IsShown() then
            if not ok then Leave() end
        else
            local want = ok and OnBottomRow()
            if armed:IsShown() ~= want then armed:SetShown(want) end
        end
    end)

    local function MatchScale() holder:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale()) end
    frame:HookScript("OnShow", function() MatchScale(); holder:Show() end)
    frame:HookScript("OnHide", function() Leave(); armed:Hide(); holder:Hide() end)
    hooksecurefunc("UpdateContainerFrameAnchors", MatchScale)
end
