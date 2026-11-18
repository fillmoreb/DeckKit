-- The menu's layout: the tabs in order, the cheat sheet chosen from the grip tables (Y on a slot), and the marks
-- that say a setting is per character, needs a /reload or can't be undone.
local UI, Chords, Settings = DeckKit.UI, DeckKit.Chords, DeckKit.Settings

local function MenuScreen()
    for _, s in ipairs(UI.Screens()) do if s.win == DeckKitMenu then return s end end
end

step("the tabs, in order")
eq(table.concat(Settings.TABS, ","), "Setup,Controls,Screen,Quests,Chat,Party,Trade,Advanced", "tab list")
local controls
for _, sec in ipairs(Settings.SectionsOf("Controls")) do if sec.label == "Cheat sheet" then controls = sec end end
check(controls, "a Cheat sheet section")
eq(#controls.rows, 2, "just Show and Where: the slots are ticked in the grip tables")

step("Y on a grip slot puts it on the cheat sheet and takes it off")
Chords.Set("L5", "press", "DECKKIT_CHEATSHEET")
check(Chords.OnSheet("L5", "press"), "an assigned slot starts on the sheet")
DeckKit.Menu.Open()
local screen = MenuScreen()
H.pad("PADRSHOULDER") -- Controls
local cell
for _, f in ipairs(screen:Focusables()) do
    if f.check and f.dk and f.dk.y then
        local _, y = f:GetCenter()
        for _, fs in ipairs(H.frames()) do
            if fs:GetObjectType() == "FontString" and fs:IsVisible() and H.Plain(fs:GetText() or ""):find("L5$") then
                local _, ly = fs:GetCenter()
                if ly and y and math.abs(ly - y) < 6 and not cell then cell = f end
            end
        end
    end
end
check(cell, "the L5 press cell, with a cheat sheet mark")
screen:SetFocus(cell)
check(cell.check:IsShown(), "its check shows")
H.pad("PAD4")
check(not Chords.OnSheet("L5", "press"), "Y took it off the sheet")
check(not cell.check:IsShown(), "and the check went")
H.pad("PAD4")
check(Chords.OnSheet("L5", "press"), "Y again puts it back")
screen:Hide()
Chords.Set("L5", "press", nil)

step("a module's scope reaches its rows; a row can say otherwise")
local ns = {}
DeckKit.NewModule(ns, "TestScope", "TestScope")
ns.settingsScope = "char"
ns.AddSettings({
    { type = "section", tab = "Advanced", label = "Scope test" },
    { type = "toggle", label = "Mine", get = function() return true end, set = function() end },
    { type = "toggle", label = "Shared", scope = "account", get = function() return true end, set = function() end },
})
local sec
for _, s in ipairs(Settings.SectionsOf("Advanced")) do if s.label == "Scope test" then sec = s end end
eq(sec.rows[1].scope, "char", "module default")
eq(sec.rows[2].scope, "account", "row override")
