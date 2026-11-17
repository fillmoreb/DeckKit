-- A popover stepper (UI.Stepper with popover = true): the d-pad passes over it like any control; A opens it, the
-- d-pad and triggers change it, A keeps (and runs done), B puts back the old value.
local UI = DeckKit.UI
local value, done = 10, nil
local screen = UI.NewScreen("PopoverTest", 700, 300, "Popover")
local tab = screen:AddTab("One")
local leftAction = UI.Action(tab.frame, 200, { label = "Left", run = function() end })
leftAction:SetPoint("TOPLEFT")
local stepper = UI.Stepper(tab.frame, 200, { label = "Level", min = 0, max = 70, popover = true,
    get = function() return value end, set = function(v) value = v end, done = function(v) done = v end })
stepper:SetPoint("LEFT", leftAction, "RIGHT", 10, 0)
local rightAction = UI.Action(tab.frame, 200, { label = "Right", run = function() end })
rightAction:SetPoint("LEFT", stepper, "RIGHT", 10, 0)
-- A second popover stepper in the tab: its own (closed) redraw mustn't undo the first one's fade.
local other = UI.Stepper(tab.frame, 200, { label = "Other", min = 0, max = 9, popover = true,
    get = function() return 1 end, set = function() end })
other:SetPoint("TOPLEFT", leftAction, "BOTTOMLEFT", 0, -40)
screen:Show()
screen:SetFocus(stepper)

step("the d-pad passes over it")
H.pad("PADDRIGHT")
check(screen:Focused() == rightAction, "right moves on past it")
H.pad("PADDLEFT")
H.pad("PADDLEFT")
check(screen:Focused() == leftAction, "and left past it the other way")
eq(value, 10, "without changing it")

step("A opens it; the d-pad and triggers change it; B puts it back")
screen:SetFocus(stepper)
H.pad("PAD1")
eq(screen.mode, "edit", "open")
check(stepper.pop:IsVisible(), "its popover shows")
check(screen.veil and screen.veil:IsVisible(), "and the window is veiled behind it")
eq(screen.win:GetAlpha(), 1, "the window itself stays opaque")
H.pad("PADDUP"); H.pad("PADDRIGHT"); H.pad("PADRTRIGGER")
eq(H.Plain(stepper.pop.value:GetText()), "22", "and follows the value")
eq(value, 22, "up, right and RT: 10 + 1 + 1 + 10")
check(screen:Focused() == stepper, "the cursor stays on it while it's open")
H.pad("PAD2")
eq(value, 10, "B puts back the old value")
check(not stepper.pop:IsVisible(), "the popover goes")
check(not screen.veil:IsVisible(), "and the veil lifts")
eq(done, nil, "nothing kept")
check(screen.win:IsShown(), "and the window stays open")

step("A keeps it, and runs done once")
H.pad("PAD1")
H.pad("PADDDOWN"); H.pad("PADLTRIGGER")
H.pad("PAD1")
eq(value, 0, "10 - 1 - 10, held at the minimum")
eq(done, 0, "done ran with the kept value")
eq(screen.mode, nil, "closed")

step("a spinner whose format only knows its own range still builds (its popover is sized from its maximum)")
local HOURS = { 12, 24, 48 }
local length = UI.Stepper(tab.frame, 200, { label = "Length", min = 1, max = 3, popover = true,
    get = function() return 2 end, set = function() end, format = function(v) return HOURS[v] .. " h" end })
check(length and length.pop, "built, with its popover")

step("an optional 'any' below the minimum, and bounds read live (from never above to)")
local from, to = 0, 0
local fromS = UI.Stepper(tab.frame, 200, { label = "From", popover = true, any = 0, anyText = "any",
    min = 1, max = function() return to ~= 0 and to or 70 end, get = function() return from end, set = function(v) from = v end })
local toS = UI.Stepper(tab.frame, 200, { label = "To", popover = true, any = 0, anyText = "any",
    min = function() return math.max(1, from) end, max = 70, get = function() return to end, set = function(v) to = v end })
fromS:SetPoint("TOPLEFT", other, "BOTTOMLEFT", 0, -20)
toS:SetPoint("LEFT", fromS, "RIGHT", 10, 0)
screen:SetFocus(fromS)
eq(H.Plain(fromS.value:GetText()), "any", "starts at any")
H.pad("PAD1")
H.pad("PADDDOWN")
eq(from, 0, "any is the bottom: down does nothing")
H.pad("PADDUP")
eq(from, 1, "up from any is the minimum")
H.pad("PADRTRIGGER")
eq(from, 11, "LT/RT: ten steps")
H.pad("PAD1")
screen:SetFocus(toS)
H.pad("PAD1")
H.pad("PADDUP")
eq(to, 11, "up from any goes to the lowest allowed: never under from")
H.pad("PADDDOWN")
eq(to, 0, "down from its minimum: back to any")
H.pad("PAD1")
to = 5
screen:SetFocus(fromS)
H.pad("PAD1"); H.pad("PADDUP"); H.pad("PAD1")
eq(from, 5, "from is held at to's value as soon as to drops")

step("a blocking question: A runs yes inside the press, B runs no; the window is veiled meanwhile")
local said
screen:SetFocus(leftAction)
screen:Ask({ text = "Sell it anyway?", yes = "Sell", no = "Don't", onYes = function() said = "yes" end,
    onNo = function() said = "no" end })
check(screen.askPop:IsVisible() and screen.veil:IsVisible(), "the question shows, the window veiled")
H.pad("PADDRIGHT")
check(screen:Focused() == leftAction, "the d-pad does nothing while it's up")
H.pad("PAD2")
eq(said, "no", "B: no")
check(not screen.askPop:IsVisible() and not screen.veil:IsVisible(), "gone, veil lifted")
screen:Ask({ text = "Again?", onYes = function() said = "yes" end })
H.pad("PAD1")
eq(said, "yes", "A: yes")
