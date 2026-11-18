-- DeckKit.Bags: small shared bag helpers for modules (MailPad attaching part of a stack, PackPad splitting one).
--
--   Bags.PadHeld(key)          is a pad button held now ("PADLTRIGGER", "PAD1"...)
-- (Forever's gamepad bags split a stack from Y's More actions menu, "Split Stack"; LT in a gamepad window is "previous
-- window", so a Shift-click split never happens there.)
--   Bags.Split(bag, slot, n)   n of a stack onto the cursor (C_Container.SplitContainerItem); true if it's there
--   Bags.FreeSlot()            an empty slot in your bags: bag, slot (the backpack and normal bags), or nil
--   Bags.PutDown(bag, slot)    the cursor's item into that slot
local _, ns = ...

local Bags = {}
ns.Bags = Bags

function Bags.PadHeld(key)
    if IsKeyDown and IsKeyDown(key) then return true end -- (as Menu.lua watches PADFORWARD)
    -- LT is Shift while the game emulates it, and a keyboard's Shift does the same at a desk.
    return key == "PADLTRIGGER" and IsShiftKeyDown() or false
end

function Bags.Split(bag, slot, n)
    ClearCursor()
    C_Container.SplitContainerItem(bag, slot, n)
    return CursorHasItem()
end

function Bags.FreeSlot()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if free and free > 0 and (family or 0) == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if not C_Container.GetContainerItemInfo(bag, slot) then return bag, slot end
            end
        end
    end
end

function Bags.PutDown(bag, slot)
    C_Container.PickupContainerItem(bag, slot)
end
