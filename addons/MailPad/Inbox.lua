-- MailPad's Inbox tab. The list: a row per mail (what's in it, who from, the subject, days left), unread ones bright;
-- above it, the auction house's mail summed up. A opens a mail, X takes everything from it, Y takes everything from
-- every mail (Take.lua). Opened: its text and its attachments, A takes the one under the cursor, X all of them, Y sends
-- it back (or deletes it, when it can't go back), B returns to the list.
local _, ns = ...

local UI = DeckKit.UI

local ROW_W, ROW_H = 820, 30
local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 16
local tab, list, rows, summary, emptyText, countText
local detail, dHead, dBody, dMoney, slots = nil, nil, nil, nil, {}
local opened -- the mail open in the detail view: its index in the list

local function Header(i)
    local packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft, hasItem, wasRead, wasReturned,
        _, canReply = GetInboxHeaderInfo(i)
    return { icon = packageIcon or stationeryIcon, sender = sender or "?", subject = subject or "", money = money or 0,
             cod = cod or 0, days = daysLeft or 0, items = hasItem or 0, read = wasRead, returned = wasReturned,
             canReply = canReply }
end

local function Days(d)
    if d < 1 then return "|cffff6060< 1 d|r" end
    return math.floor(d) .. " d"
end

-- What's in a mail, short: its money, how many items, COD.
local function Contents(h)
    local parts = {}
    if h.money > 0 then parts[#parts + 1] = ns.Money(h.money) end
    if h.items > 0 then parts[#parts + 1] = h.items .. (h.items == 1 and " item" or " items") end
    if h.cod > 0 then parts[#parts + 1] = "|cffff6060COD " .. ns.Money(h.cod) .. "|r" end
    return table.concat(parts, "  ")
end

-- The first attachment's icon, else the mail's own.
local function Icon(i, h)
    for a = 1, MAX_ATTACH do
        local name, _, texture = GetInboxItem(i, a)
        if name then return texture end
    end
    return h.icon
end

------------------------------------------------------------------------
-- The auction house's mail, summed up: sold (and what it brings in), expired, won, outbid
------------------------------------------------------------------------

local function Summary()
    local sold, soldMoney, expired = 0, 0, 0
    local expiredSubject = AUCTION_EXPIRED_MAIL_SUBJECT and AUCTION_EXPIRED_MAIL_SUBJECT:gsub("%%s", ".*")
    for i = 1, GetInboxNumItems() do
        local h = Header(i)
        local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
        if invoice == "seller" then
            sold = sold + 1
            soldMoney = soldMoney + h.money
        elseif expiredSubject and h.subject:match("^" .. expiredSubject .. "$") then
            expired = expired + 1
        end
    end
    local parts = {}
    if sold > 0 then parts[#parts + 1] = sold .. " sold: " .. ns.Money(soldMoney) end
    if expired > 0 then parts[#parts + 1] = expired .. " expired" end
    return #parts > 0 and ("|cffffd100Auction house|r  " .. table.concat(parts, "  ·  ")) or nil
end

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------

local function Prompts(self)
    if not self.index then return {} end
    return { { "A", "Open" }, { "X", "Take" }, { "Y", "Take all" } }
end

local function OpenMail(i)
    opened = i
    ns.ShowDetail()
end

local function MakeRow(i)
    local f = CreateFrame("Button", nil, list.content)
    f:SetSize(ROW_W - 22, ROW_H)
    f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)
    f:SetHighlightTexture(hl)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(22, 22)
    f.icon:SetPoint("LEFT", 8, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local function Col(x, w, justify)
        local t = f:CreateFontString(nil, "OVERLAY")
        t:SetFontObject(UI.Font.body)
        t:SetPoint("LEFT", x, 0)
        t:SetWidth(w)
        t:SetJustifyH(justify or "LEFT")
        t:SetWordWrap(false)
        return t
    end
    f.sender = Col(40, 170)
    f.subject = Col(220, 320)
    f.contents = Col(550, 180, "RIGHT")
    f.days = Col(740, 50, "RIGHT")
    return UI.Register(f, {
        prompts = Prompts,
        activate = function(self) if self.index then OpenMail(self.index) end end,
        x = function(self) if self.index then ns.Take.Start(self.index) end end,
        y = function() ns.Take.Start(nil) end,
        refresh = function(self)
            local i = self.index
            if not i then return end
            local h = Header(i)
            self.icon:SetTexture(Icon(i, h))
            local c = h.read and "|cffb0b0b0" or "|cffffffff"
            self.sender:SetText(c .. h.sender .. "|r")
            self.subject:SetText(c .. h.subject .. "|r")
            self.contents:SetText(Contents(h))
            self.days:SetText(Days(h.days))
        end,
    })
end

local function Rebuild()
    if not list then return end
    local shown, total = GetInboxNumItems()
    for i = 1, shown do
        local row = rows[i] or MakeRow(i)
        rows[i] = row
        row.index = i
        row:Show()
    end
    for i = shown + 1, #rows do rows[i].index = nil; rows[i]:Hide() end
    list:SetContentHeight(shown * ROW_H)
    emptyText:SetShown(shown == 0)
    local s = Summary()
    summary:SetText(s or "")
    countText:SetText((total and total > shown) and ("|cff9d9d9d%d of %d shown: take some to see the rest|r"):format(shown, total) or "")
    local screen = ns.Screen()
    if screen and screen.win:IsShown() and not detail:IsShown() then
        local f = screen:Focused()
        if not (f and f:IsVisible() and f.index) then screen:SetFocus(rows[1] and rows[1]:IsShown() and rows[1] or nil) end
        screen:Refresh()
    end
end

------------------------------------------------------------------------
-- One mail, open
------------------------------------------------------------------------

local function SlotPrompts(self)
    local p = {}
    if self.attach then p[#p + 1] = { "A", "Take" } end
    p[#p + 1] = { "X", "Take all" }
    p[#p + 1] = { "Y", opened and InboxItemCanDelete(opened) and "Delete" or "Send back" }
    return p
end

-- Y: send it back to whoever sent it, or delete it when it can't go back (the game's own mail, emptied mail).
local function ReturnOrDelete()
    local i = opened
    if not i then return end
    local h = Header(i)
    local delete = InboxItemCanDelete(i)
    ns.Screen():Ask({
        text = (delete and "Delete \"%s\"?" or "Send \"%s\" back to %s?"):format(h.subject, h.sender)
            .. ((delete and (h.money > 0 or h.items > 0)) and "\nWhat's still in it goes with it." or ""),
        yes = delete and "Delete" or "Send back", no = "Keep",
        onYes = function()
            if delete then DeleteInboxItem(i) else ReturnInboxItem(i) end
            ns.InboxBack()
        end })
end

local function MakeSlot(a)
    local f = UI.Icon(detail, 36, {
        prompts = SlotPrompts,
        activate = function(self) if opened and self.attach then TakeInboxItem(opened, self.attach) end end,
        x = function() if opened then ns.Take.Start(opened) end end,
        y = ReturnOrDelete,
    })
    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFontObject(UI.Font.small)
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local col, row = (a - 1) % 8, math.floor((a - 1) / 8)
    f:SetPoint("TOPLEFT", dMoney, "BOTTOMLEFT", col * 52, -16 - row * 52)
    return f
end

-- The money line doubles as a control when there are no items: something for the cursor to sit on.
local moneyRow

function ns.ShowDetail()
    local i = opened
    if not i or i > GetInboxNumItems() then ns.InboxBack() return end
    local h = Header(i)
    local body = GetInboxText(i) -- marks it read
    list:Hide(); summary:Hide(); countText:Hide(); emptyText:Hide()
    detail:Show()
    dHead:SetText(("|cffffd100%s|r   %s"):format(h.subject, "|cff9d9d9dfrom " .. h.sender .. "|r"))
    dBody:SetText(body and body ~= "" and body or "|cff6d6d6d(no text)|r")
    dMoney:SetText(h.cod > 0 and ("|cffff6060COD: pay " .. ns.Money(h.cod) .. " to take its items (in Blizzard's window).|r")
        or (h.money > 0 and ("Money: " .. ns.Money(h.money)) or ""))
    local first
    for a = 1, MAX_ATTACH do
        local slot = slots[a] or MakeSlot(a)
        slots[a] = slot
        local name, _, texture, count = GetInboxItem(i, a)
        if name then
            slot.attach = a
            slot.icon:SetTexture(texture)
            slot.count:SetText(count and count > 1 and count or "")
            slot:Show()
            first = first or slot
        else
            slot.attach = nil
            slot:Hide()
        end
    end
    moneyRow:SetShown(first == nil)
    local screen = ns.Screen()
    screen:SetFocus(first or moneyRow)
    screen:Refresh()
end

function ns.InboxBack()
    if not (detail and detail:IsShown()) then return false end
    opened = nil
    detail:Hide()
    list:Show(); summary:Show(); countText:Show()
    Rebuild()
    local screen = ns.Screen()
    screen:SetFocus(rows[1] and rows[1]:IsShown() and rows[1] or nil)
    return true
end

function ns.InboxBackLabel()
    return detail and detail:IsShown() and "Back" or nil
end

------------------------------------------------------------------------

function ns.BuildInbox(t)
    tab = t
    summary = t.frame:CreateFontString(nil, "OVERLAY")
    summary:SetFontObject(UI.Font.body)
    summary:SetPoint("TOPLEFT", 10, -2)
    list = UI.ScrollList(t.frame, ROW_W, 370)
    list:SetPoint("TOPLEFT", 0, -26)
    countText = t.frame:CreateFontString(nil, "OVERLAY")
    countText:SetFontObject(UI.Font.body)
    countText:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 10, -10)
    emptyText = UI.Description(t.frame, "Your mailbox is empty.", 400)
    emptyText:SetPoint("TOPLEFT", 20, -40)
    rows = {}

    detail = CreateFrame("Frame", nil, t.frame)
    detail:SetAllPoints()
    detail:Hide()
    dHead = detail:CreateFontString(nil, "OVERLAY")
    dHead:SetFontObject(UI.Font.heading)
    dHead:SetPoint("TOPLEFT", 10, -4)
    dHead:SetWidth(ROW_W - 20)
    dHead:SetJustifyH("LEFT")
    dBody = UI.Description(detail, "", ROW_W - 40)
    dBody:SetPoint("TOPLEFT", dHead, "BOTTOMLEFT", 0, -12)
    dBody:SetMaxLines(10)
    dMoney = detail:CreateFontString(nil, "OVERLAY")
    dMoney:SetFontObject(UI.Font.body)
    dMoney:SetPoint("TOPLEFT", dBody, "BOTTOMLEFT", 0, -14)
    moneyRow = UI.Action(detail, 300, { label = "Take the money", verb = "Take",
        run = function() if opened then ns.Take.Start(opened) end end })
    moneyRow:SetPoint("TOPLEFT", dMoney, "BOTTOMLEFT", -10, -12)
    moneyRow.dk.y = ReturnOrDelete
    moneyRow.dk.prompts = function()
        return { { "A", "Take" }, { "Y", opened and InboxItemCanDelete(opened) and "Delete" or "Send back" } }
    end

    t.onShow = Rebuild
end

-- Called when the inbox opens, and as takes go through.
function ns.InboxOpened()
    if detail then ns.InboxBack() end
    Rebuild()
end

function ns.InboxChanged()
    if detail and detail:IsShown() then
        if opened and opened <= GetInboxNumItems() then ns.ShowDetail() else ns.InboxBack() end
    else
        Rebuild()
    end
end

ns.On("MAIL_INBOX_UPDATE", function() if ns.Screen() and ns.Screen().win:IsShown() then ns.InboxChanged() end end)
