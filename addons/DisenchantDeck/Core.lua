-- DisenchantDeck: a controller list of what's in your bags that can be disenchanted.
--
--   Core.lua    events, saved hidden list, the bag scan
--   List.lua    the list: A disenchants, Y hides / shows again, LB/RB switch lists, B closes
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffb070ffDisenchantDeck|r") -- Print, On, Input, Window
ns.DISENCHANT = 13262

ns.On("ADDON_LOADED", function(name)
    if name ~= "DisenchantDeck" then return end
    DisenchantDeckDB = DisenchantDeckDB or {}
    DisenchantDeckDB.hidden = DisenchantDeckDB.hidden or {}
    ns.db = DisenchantDeckDB
end)

BINDING_HEADER_DISENCHANTDECK = "DisenchantDeck"
BINDING_NAME_DISENCHANTDECK_TOGGLE = "Open / close the disenchant list"

function ns.KnowsDisenchant()
    if IsPlayerSpell then return IsPlayerSpell(ns.DISENCHANT) end
    if IsSpellKnown then return IsSpellKnown(ns.DISENCHANT) end
    return true
end

function ns.DisenchantName()
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(ns.DISENCHANT) end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(ns.DISENCHANT)
        if info and info.name then return info.name end
    end
    return "Disenchant"
end

------------------------------------------------------------------------
-- Bag scan
------------------------------------------------------------------------

-- Gear that disenchants: uncommon (green) to epic, weapons and armor you can wear.
-- Shirts and tabards never do. The game has the final word: a few items refuse.
local NEVER = { INVTYPE_BODY = true, INVTYPE_TABARD = true, [""] = true }

local function ContainerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end
end

local function NumSlots(bag)
    return C_Container.GetContainerNumSlots(bag) or 0
end

local function Disenchantable(info)
    if not (info and info.itemID and info.quality) then return false end
    if info.quality < 2 or info.quality > 4 then return false end
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(info.itemID)
    return (classID == 2 or classID == 4) and not NEVER[equipLoc or ""]
end

-- Returns two lists of { bag, slot, itemID, link, icon, quality, count }: shown and hidden.
function ns.Scan()
    local shown, hidden = {}, {}
    local hiddenIDs = ns.db and ns.db.hidden or {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) do
            local info = ContainerInfo(bag, slot)
            if Disenchantable(info) then
                local entry = {
                    bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    icon = info.iconFileID, quality = info.quality, count = info.stackCount or 1,
                    locked = info.isLocked,
                }
                table.insert(hiddenIDs[info.itemID] and hidden or shown, entry)
            end
        end
    end
    return shown, hidden
end
