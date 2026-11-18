-- A DeckKit screen and the grip keys: they reach the grip chords while a screen is open (so the chord that opened
-- a window closes it again), and are the screen's only while a binding control waits for a button. The harness
-- sends keys straight through the bindings, so this checks what the screen claims rather than propagation.
local UI = DeckKit.UI

local function MenuScreen()
    for _, s in ipairs(UI.Screens()) do if s.win == DeckKitMenu then return s end end
end

step("an open screen leaves the grip keys to the chords")
DeckKit.Menu.Open()
local screen = MenuScreen()
check(screen and screen.win:IsShown(), "the menu is open")
for _, g in ipairs(DeckKit.GRIPS) do
    eq(screen.input.handlers[g.key], nil, g.name .. " (" .. g.key .. ") isn't the screen's")
end
check(screen.input.handlers.PAD1 ~= nil, "A still is")

step("while a binding waits for a button, the grips are the screen's")
screen.mode = "capture"
for _, g in ipairs(DeckKit.GRIPS) do
    check(screen.input.handlers[g.key] ~= nil, g.name .. " can be captured")
end
screen.mode = nil
eq(screen.input.handlers[DeckKit.GRIPS[1].key], nil, "and let go after")

step("the legend has no LB / RB entry")
screen:UpdatePrompts()
local text = ""
for _, f in ipairs(H.frames()) do
    if f:GetObjectType() == "FontString" and f:IsVisible() and H.IsInside(f, screen.win) then text = text .. " " .. (f:GetText() or "") end
end
check(not H.Plain(text):find("Tabs"), "no Tabs prompt")
