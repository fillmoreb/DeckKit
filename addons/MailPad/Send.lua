-- MailPad's Send tab: a letter on the left, your bags on the right. Built to need as little typing as a controller can:
--   To        picked from a list (your characters on this realm and side, recent names, friends, guild), or typed
--   Subject   filled in from what's attached ("Linen Cloth and 2 more", "25g") unless you write one
--   Money     gold, silver and copper; COD makes it what they pay instead
--   Items     up to 12, A on a bag item attaches it, Y on a stack splits it (how many asked), Y on an attached one
--             takes it back out
--   Send      asks first (who, what, the postage), then sends, inside your A press (the game's rule)
-- Your characters are remembered as you log in on them (MailPadDB.chars), recent names as you send (MailPadDB.recent).
local _, ns = ...

local UI = DeckKit.UI

local FORM_W, LIST_W, ROW_H = 400, 420, 30
local MAX_SEND = ATTACHMENTS_MAX_SEND or 12
local tab, list, rows, emptyText, info
local slots = {}
local letter = { to = nil, subject = "", gold = 0, silver = 0, copper = 0, cod = false }
local RECIPIENTS = {} -- the To list's values: { { name, "Name  (alt)" }, ... }, filled each time the tab opens

------------------------------------------------------------------------
-- Who to send to
------------------------------------------------------------------------

local function Realm() return GetRealmName() end

ns.On("PLAYER_LOGIN", function()
    local db = ns.db
    db.chars = db.chars or {}
    db.chars[Realm()] = db.chars[Realm()] or {}
    db.chars[Realm()][UnitName("player")] = { faction = UnitFactionGroup("player"), class = select(2, UnitClass("player")) }
    db.recent = db.recent or {}
end)

local function FillRecipients()
    for i = #RECIPIENTS, 1, -1 do RECIPIENTS[i] = nil end
    local seen, me, side = {}, UnitName("player"), UnitFactionGroup("player")
    local function Add(name, why)
        if not name or name == "" or name == me or seen[name] then return end
        seen[name] = true
        RECIPIENTS[#RECIPIENTS + 1] = { name, name .. "  |cff9d9d9d" .. why .. "|r" }
    end
    local chars = ns.db.chars and ns.db.chars[Realm()] or {}
    local alts = {}
    for name, c in pairs(chars) do if c.faction == side then alts[#alts + 1] = name end end
    table.sort(alts)
    for _, name in ipairs(alts) do Add(name, "your character") end
    for _, name in ipairs(ns.db.recent or {}) do Add(name, "sent to before") end
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() do
            local f = C_FriendList.GetFriendInfoByIndex(i)
            if f and f.name then Add((f.name:gsub("%-.*$", "")), "friend") end
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers then
        for i = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(i)
            if name then Add((name:gsub("%-.*$", "")), "guild") end
        end
    end
    if #RECIPIENTS == 0 then RECIPIENTS[1] = { false, "|cff9d9d9dNo names yet: type one below|r" } end
end

------------------------------------------------------------------------
-- What's attached
------------------------------------------------------------------------

local function Attached()
    local out = {}
    for k = 1, MAX_SEND do
        local name, _, texture, count = GetSendMailItem(k)
        if name then out[#out + 1] = { slot = k, name = name, icon = texture, count = count } end
    end
    return out
end

local function FreeSlot()
    for k = 1, MAX_SEND do if not GetSendMailItem(k) then return k end end
end

local function Money() return letter.gold * 10000 + letter.silver * 100 + letter.copper end

local function PlainMoney(c)
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if cu > 0 or #parts == 0 then parts[#parts + 1] = cu .. "c" end
    return table.concat(parts, " ")
end

-- The subject when you haven't written one: what's attached, else the money.
local function AutoSubject()
    local items = Attached()
    if #items > 0 then
        local first = items[1].name
        return #items == 1 and first or (first .. " and " .. (#items - 1) .. " more")
    end
    local m = Money()
    if m > 0 then return (letter.cod and "COD " or "") .. PlainMoney(m) end
    return "Hello"
end

local function Subject()
    return (letter.subject ~= "" and letter.subject) or AutoSubject()
end

------------------------------------------------------------------------
-- Your bags: what can be mailed (not bound, not already attached)
------------------------------------------------------------------------

local items = {}

local function Scan()
    items = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it and it.itemID and not it.isBound and not it.isLocked then
                items[#items + 1] = { bag = bag, slot = slot, icon = it.iconFileID, link = it.hyperlink,
                                      count = it.stackCount or 1 }
            end
        end
    end
end

local function Attach(e)
    local k = FreeSlot()
    if not k then ns.Print("A letter holds " .. MAX_SEND .. " items.") return end
    ClearCursor()
    C_Container.PickupContainerItem(e.bag, e.slot)
    ClickSendMailItemButton(k)
    if CursorHasItem() then ClearCursor() end
end

-- Y on a stack: how many, then just those (Forever's gamepad bags split from Y's More actions menu).
local function AttachSome(e)
    local k = FreeSlot()
    if not k then ns.Print("A letter holds " .. MAX_SEND .. " items.") return end
    ns.Screen():AskNumber({ text = "Split stack: how many " .. (e.link or "?") .. " to attach?", min = 1, max = e.count - 1,
        value = math.max(1, math.floor(e.count / 2)), yes = "Attach",
        onYes = function(n)
            -- A split held on the cursor still points at its whole stack, and the mail attaches by bag slot, so it
            -- took the whole stack (Ben, 2026-11-18). The part goes into an empty bag slot first; once it has landed
            -- there (the server answers a moment later), that stack is attached.
            local fb, fs = DeckKit.Bags.FreeSlot()
            if not fb then ns.Print("Attaching part of a stack needs one empty bag slot.") return end
            if not DeckKit.Bags.Split(e.bag, e.slot, n) then return end
            DeckKit.Bags.PutDown(fb, fs)
            local tries = 0
            local function Landed()
                tries = tries + 1
                local it = C_Container.GetContainerItemInfo(fb, fs)
                if it and not it.isLocked and it.stackCount == n then
                    ClearCursor()
                    C_Container.PickupContainerItem(fb, fs)
                    ClickSendMailItemButton(k)
                    if CursorHasItem() then ClearCursor() end
                elseif tries < 30 then
                    C_Timer.After(0.1, Landed)
                else
                    ns.Print("The " .. n .. " are in your bags; attach them from there.")
                end
            end
            C_Timer.After(0.1, Landed)
        end })
end

local function MakeRow(i)
    local f = CreateFrame("Button", nil, list.content)
    f:SetSize(LIST_W - 22, ROW_H)
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
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetFontObject(UI.Font.body)
    f.name:SetPoint("LEFT", 40, 0)
    f.name:SetWidth(LIST_W - 120)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFontObject(UI.Font.body)
    f.count:SetPoint("RIGHT", -10, 0)
    return UI.Register(f, {
        prompts = function(self)
            local p = { { "A", "Attach" } }
            if self.item and self.item.count > 1 then p[#p + 1] = { "Y", "Split stack" } end
            return p
        end,
        activate = function(self) if self.item then Attach(self.item) end end,
        -- Y on a stack: split it, as Forever's gamepad bags offer it (Y, More actions > Split Stack).
        y = function(self) local e = self.item if e and e.count > 1 then AttachSome(e) end end,
        refresh = function(self)
            local e = self.item
            if not e then return end
            self.icon:SetTexture(e.icon)
            self.name:SetText(e.link or "?")
            self.count:SetText(e.count > 1 and ("x" .. e.count) or "")
        end,
    })
end

local function Rebuild()
    if not list then return end
    Scan()
    for i, e in ipairs(items) do
        local row = rows[i] or MakeRow(i)
        rows[i] = row
        row.item = e
        row:Show()
    end
    for i = #items + 1, #rows do rows[i].item = nil; rows[i]:Hide() end
    list:SetContentHeight(#items * ROW_H)
    emptyText:SetShown(#items == 0)
    -- The attached items, in their slots.
    local att = Attached()
    for k = 1, MAX_SEND do
        local s, a = slots[k], att[k]
        s.attached = a
        s.icon:SetTexture(a and a.icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        s.count:SetText(a and a.count and a.count > 1 and a.count or "")
    end
    local postage = GetSendMailPrice and GetSendMailPrice() or 0
    info:SetText(("Subject: |cffffffff%s|r\nPostage: %s"):format(Subject(), ns.Money(postage)))
    local screen = ns.Screen()
    if screen and screen.win:IsShown() and screen.tab == 2 then screen:Refresh() end
end
ns.SendChanged = Rebuild

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------

local sending -- the name a send went to, until the game answers

local function Send()
    local to = letter.to
    if not to or to == "" then ns.Print("Pick who it's for first.") return end
    local att, money = Attached(), Money()
    if letter.cod and #att == 0 then ns.Print("COD needs at least one item attached.") return end
    if #att == 0 and money == 0 then ns.Print("Nothing to send: attach an item or add money.") return end
    local postage = GetSendMailPrice and GetSendMailPrice() or 0
    if not letter.cod and money + postage > GetMoney() then ns.Print("You don't have that much money (with the postage).") return end
    local what = {}
    if #att > 0 then what[#what + 1] = #att .. (#att == 1 and " item" or " items") end
    if money > 0 then what[#what + 1] = letter.cod and ("COD " .. ns.Money(money)) or ns.Money(money) end
    ns.Screen():Ask({
        text = ("Send %s to %s?\nPostage %s."):format(table.concat(what, " and "), to, ns.Money(postage)),
        yes = "Send", no = "Not yet",
        onYes = function()
            if letter.cod then SetSendMailCOD(money) SetSendMailMoney(0) else SetSendMailCOD(0) SetSendMailMoney(money) end
            sending = to
            SendMail(to, Subject(), "")
        end })
end

ns.On("MAIL_SEND_SUCCESS", function()
    if not sending then return end
    ns.Print("Sent to " .. sending .. ".")
    local recent = ns.db.recent or {}
    for i = #recent, 1, -1 do if recent[i] == sending then table.remove(recent, i) end end
    table.insert(recent, 1, sending)
    while #recent > 10 do table.remove(recent) end
    ns.db.recent = recent
    sending = nil
    letter.subject, letter.gold, letter.silver, letter.copper, letter.cod = "", 0, 0, 0, false
    C_Timer.After(0.2, Rebuild)
end)
ns.On("MAIL_FAILED", function()
    if sending then ns.Print("Not sent to " .. sending .. ".") sending = nil end
end)
ns.On("MAIL_SEND_INFO_UPDATE", function() C_Timer.After(0, Rebuild) end)
ns.On("BAG_UPDATE_DELAYED", function()
    local s = ns.Screen()
    if s and s.win:IsShown() and s.tab == 2 then Rebuild() end
end)

------------------------------------------------------------------------

function ns.BuildSend(t)
    tab = t
    local body = t.frame
    local form = UI.Panel(body)
    form:SetPoint("TOPLEFT", 0, -4)
    form:SetSize(FORM_W, 410)
    local W = FORM_W - 16

    local toSel = UI.Selector(form, W, { label = "To", values = RECIPIENTS, listOnly = true, boxWidth = 200,
        get = function() return letter.to or false end,
        set = function(v) if v then letter.to = v end end })
    toSel:SetPoint("TOPLEFT", 8, -8)
    local typed = UI.TextBox(form, W, { label = "Or type a name", placeholder = "a name", boxWidth = 200, maxLetters = 48,
        get = function() return "" end,
        set = function(text) text = strtrim(text or "") if text ~= "" then letter.to = text end end })
    typed:SetPoint("TOPLEFT", toSel, "BOTTOMLEFT", 0, -2)
    local subj = UI.TextBox(form, W, { label = "Subject", placeholder = "filled in for you", boxWidth = 200, maxLetters = 64,
        get = function() return letter.subject end,
        set = function(text) letter.subject = strtrim(text or "") Rebuild() end })
    subj:SetPoint("TOPLEFT", typed, "BOTTOMLEFT", 0, -2)
    local function Coin(label, key, max, after)
        local s = UI.Stepper(form, W, { label = label, popover = true, min = 0, max = max, widest = max,
            get = function() return letter[key] end, set = function(v) letter[key] = v Rebuild() end })
        s:SetPoint("TOPLEFT", after, "BOTTOMLEFT", 0, -2)
        return s
    end
    local g = Coin("Gold", "gold", 99999, subj)
    local s = Coin("Silver", "silver", 99, g)
    local c = Coin("Copper", "copper", 99, s)
    local cod = UI.Checkbox(form, W, { label = "COD: the money is what they pay",
        get = function() return letter.cod end, set = function(on) letter.cod = on Rebuild() end })
    cod:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -2)

    -- The attachments: 12 slots, two rows. Y takes one back out.
    for k = 1, MAX_SEND do
        local slot = UI.Icon(form, 30, {
            prompts = function(self) return self.attached and { { "Y", "Take out" } } or {} end,
            y = function(self) if self.attached then ClickSendMailItemButton(self.attached.slot, true) end end,
        })
        slot.count = slot:CreateFontString(nil, "OVERLAY")
        slot.count:SetFontObject(UI.Font.small)
        slot.count:SetPoint("BOTTOMRIGHT", -1, 1)
        local col, row = (k - 1) % 6, math.floor((k - 1) / 6)
        slot:SetPoint("TOPLEFT", cod, "BOTTOMLEFT", 14 + col * 44, -14 - row * 44)
        slots[k] = slot
    end
    info = form:CreateFontString(nil, "OVERLAY")
    info:SetFontObject(UI.Font.body)
    info:SetPoint("TOPLEFT", slots[7], "BOTTOMLEFT", -6, -12)
    info:SetWidth(W - 10)
    info:SetJustifyH("LEFT")
    info:SetSpacing(3)
    local send = UI.Action(form, W, { label = "Send", verb = "Send", run = Send })
    send:SetPoint("BOTTOMLEFT", 8, 8)

    list = UI.ScrollList(body, LIST_W, 410)
    list:SetPoint("TOPRIGHT", 0, -4)
    rows = {}
    emptyText = UI.Description(body, "Nothing in your bags can be mailed.", LIST_W - 40)
    emptyText:SetPoint("TOPLEFT", list, "TOPLEFT", 20, -26)

    t.onShow = function() FillRecipients() Rebuild() end
end
