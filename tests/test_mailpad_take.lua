-- MailPad's taking (Take.lua) against a stand-in mailbox: money then items, one take at a time while the game says a
-- command is pending; COD mail left alone; a mail emptied out of the list doesn't make "this mail" take from the
-- next one; a full bag stops it.

-- The stand-in mailbox: mails { sender, subject, money, cod, days, items = { {name, count} } }; empty ones vanish.
local box, pending = {}, false
local function Mail(sender, subject, money, cod, items)
    return { sender = sender, subject = subject, money = money or 0, cod = cod or 0, days = 20, items = items or {} }
end
local function Close(i)
    local m = box[i]
    if m and m.money == 0 and #m.items == 0 then table.remove(box, i) end
end
function GetInboxNumItems() return #box, #box end
function GetInboxHeaderInfo(i)
    local m = box[i]
    if not m then return nil end
    return nil, nil, m.sender, m.subject, m.money, m.cod, m.days, #m.items > 0 and #m.items or nil, false, false, nil, true
end
function GetInboxItem(i, a)
    local it = box[i] and box[i].items[a]
    if it then return it[1], 1, 134400, it[2] end
end
function TakeInboxMoney(i) box[i].money = 0 pending = true Close(i) end
function TakeInboxItem(i, a)
    if box.full then H.fire("UI_ERROR_MESSAGE", 3, ERR_INV_FULL) return end
    table.remove(box[i].items, a) pending = true Close(i)
end
C_Mail = C_Mail or {}
C_Mail.IsCommandPending = function() local p = pending pending = false return p end
ERR_INV_FULL = ERR_INV_FULL or "Inventory is full."

local Take = MailPadTakeForTests
check(Take, "MailPad's Take is reachable")

step("take all: money, then items, mail by mail; COD left alone")
box = {
    Mail("Auction House", "Auction successful: Rough Stone", 152),
    Mail("Grimshot", "herbs", 0, 500, { { "Peacebloom", 20 } }), -- COD
    Mail("Glitz", "stuff", 1000, 0, { { "Linen Cloth", 20 }, { "Copper Ore", 5 } }),
}
Take.Start(nil)
H.advance(5)
eq(#box, 1, "two mails emptied and gone")
eq(box[1].sender, "Grimshot", "the COD mail is left")
check(not Take.Running(), "finished")

step("one mail: stops when it's emptied, never takes from the next")
box = { Mail("A", "one", 10), Mail("B", "two", 20, 0, { { "Linen Cloth", 1 } }) }
Take.Start(1)
H.advance(3)
eq(#box, 1, "only the first mail went")
eq(box[1].sender, "B", "the second is untouched")
eq(box[1].money, 20, "its money too")

step("full bags stop it")
box = { Mail("C", "items", 0, 0, { { "Linen Cloth", 1 }, { "Wool Cloth", 1 } }) }
box.full = true
Take.Start(nil)
H.advance(2)
check(not Take.Running(), "stopped")
eq(#box[1].items, 2, "nothing taken")
