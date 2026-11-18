-- MailPad: the mailbox, controller first. Opening a mailbox opens MailPad's window instead of Blizzard's (whose window
-- stays open but invisible: the mailbox closes when its window does, as AuctionPad does with the auction house).
--
--   Core.lua    the window, opening and closing with the mailbox, Blizzard's window kept out of sight, settings
--   Take.lua    taking money and items one at a time, as the game allows: one mail, or the whole inbox (Take all)
--   Inbox.lua   the Inbox tab: a row per mail, the auction house's mail summed up, a mail opened to read and take
--   Send.lua    the Send tab: who to (your characters, recent names, friends, guild, or typed), money or COD, items
--               from your bags, a subject filled in for you
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffd8b4ffMailPad|r")

local UI = DeckKit.UI
local WIDTH, HEIGHT = 860, 540

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    MailPadDB = MailPadDB or {}
    if MailPadDB.on == nil then MailPadDB.on = true end
    ns.db = MailPadDB
end)

-- Money as the game writes it, with coin icons.
function ns.Money(c)
    c = math.max(0, math.floor(c or 0))
    if GetMoneyString then return GetMoneyString(c, true) end
    return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------

local screen
function ns.Screen() return screen end

local function Build()
    if screen then return screen end
    screen = UI.NewScreen("MailPadWindow", WIDTH, HEIGHT, "Mailbox")
    ns.inboxTab = screen:AddTab("Inbox")
    ns.sendTab = screen:AddTab("Send")
    ns.BuildInbox(ns.inboxTab)
    ns.BuildSend(ns.sendTab)
    -- B steps back from a mail to the list before it closes the mailbox.
    function screen:OnBack() return self.tab == 1 and ns.InboxBack() or false end
    function screen:BackLabel() return self.tab == 1 and ns.InboxBackLabel() or nil end
    -- Closing the window closes the mailbox, as walking away would.
    function screen:OnPlayerClose() if CloseMail then CloseMail() end end
    return screen
end

------------------------------------------------------------------------
-- Blizzard's window: open (the mailbox needs it) but invisible while MailPad is up
------------------------------------------------------------------------

local function Conceal(on)
    -- Alpha only: hiding MailFrame closes the mailbox, and moving a panel taints.
    for _, f in ipairs({ _G.MailFrame, _G.OpenMailFrame }) do f:SetAlpha(on and 0 or 1) end
end

local blizzard = false -- the player went back to Blizzard's window this visit

function ns.UseBlizzard()
    blizzard = true
    Conceal(false)
    if screen then screen:Hide() end
end

ns.On("MAIL_SHOW", function()
    if not ns.db.on then return end
    blizzard = false
    Build()
    Conceal(true)
    C_Timer.After(0, function() if not blizzard then Conceal(true) end end) -- after Blizzard lays it out
    screen:Show()
    if not screen.win:IsShown() then ns.UseBlizzard() return end -- couldn't open (combat): Blizzard's it is
    screen:SelectTab(1)
    if CheckInbox then CheckInbox() end
    ns.InboxOpened()
end)

ns.On("MAIL_CLOSED", function()
    Conceal(false)
    blizzard = false
    ns.Take.Stop()
    if screen and screen.win:IsShown() then screen:Hide() end
end)

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

ns.AddSettings({
    { type = "section", tab = "Trade", label = "Mailbox", order = 4 },
    { type = "toggle", label = "MailPad instead of Blizzard's mailbox",
      hint = "Opening a mailbox opens MailPad. Inbox: your mail as a list, {A} opens one, {X} takes everything from it, "
          .. "{Y} takes everything from every mail (COD mail is left alone). Send: pick who (your characters, recent "
          .. "names, friends, guild) or type a name, add money or COD, {A} attaches items from your bags. Off: "
          .. "Blizzard's own window.",
      get = function() return ns.db.on end,
      set = function(on) ns.db.on = on end },
})
