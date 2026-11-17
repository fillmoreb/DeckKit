-- DeckKit's text box (UI.TextBox): A starts typing and holds the cursor there; A keeps the text, B puts back what was
-- there; an assistant can fill the box under the cursor without typing (UI.ActiveTextBox), and run it.
local UI = DeckKit.UI
local value, searched = "", nil
local screen = UI.NewScreen("TextBoxTest", 600, 300, "Text box")
local tab = screen:AddTab("One")
local box = UI.TextBox(tab.frame, 500, { label = "Search", placeholder = "a name",
    get = function() return value end, set = function(v) value = v end, enter = function(t) searched = t end })
box:SetPoint("TOPLEFT")
local other = UI.Action(tab.frame, 500, { label = "Something else", run = function() end })
other:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
screen:Show()
screen:SetFocus(box)

step("an assistant fills the box under the cursor, and can run it")
local tb = UI.ActiveTextBox()
check(tb and tb.label == "Search", "the box under the cursor is offered, by its label")
tb.fill("linen cloth", true)
eq(value, "linen cloth", "filled")
eq(searched, "linen cloth", "and run, as its own Enter would")
screen:SetFocus(other)
check(UI.ActiveTextBox() == nil, "not when the cursor is elsewhere")

step("A types: the cursor stays put until A or B")
screen:SetFocus(box)
H.pad("PAD1")
eq(screen.mode, "text", "typing")
check(UI.ActiveTextBox() == nil, "a box being typed in isn't offered (its keys are the keyboard's)")
H.pad("PADDDOWN")
check(screen:Focused() == box, "the d-pad doesn't move the cursor while typing")
box.box:SetText("wool cloth")
H.pad("PAD1")
eq(value, "wool cloth", "A keeps it")
eq(searched, "wool cloth", "and runs it")
eq(screen.mode, nil, "done typing")

step("B puts back what was there")
H.pad("PAD1")
box.box:SetText("silk")
H.pad("PAD2")
eq(value, "wool cloth", "unchanged")
check(screen.win:IsShown(), "B ends typing, it doesn't close the window")

step("closing the window mid-typing lets go of the keyboard")
H.pad("PAD1")
screen:Hide()
eq(screen.mode, nil, "typing ended")
check(not box.editing, "the box let go")
