-- Live widgets: a layout with stat pieces bound to DeckKit.Measures, saved by name, toggled as an action (a grip
-- slot here), counting from its own mark each time it opens, stacked with other trackers.
local Widgets, Actions, Chords, UI, W = DeckKit.Widgets, DeckKit.Actions, DeckKit.Chords, DeckKit.UI, H.world

local function Plain(fs) return (H.Plain(fs and fs:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
-- The value shown on the row whose label reads `label`, in tracker `frame`.
local function ValueOf(frame, label)
    for _, f in ipairs(H.frames()) do
        if f:GetObjectType() == "FontString" and f:IsVisible() and H.IsInside(f, frame) and Plain(f) == label then
            local row = f:GetParent()
            return row.value and Plain(row.value)
        end
    end
end

local HAUL = { type = "list", title = "Haul", items = {
    { type = "stat", text = "Light Leather", bind = { measure = "looted", item = 2318, since = "haul" } },
    { type = "stat", text = "per hour", bind = { measure = "looted", item = 2318, since = "haul", per = "hour" } },
    { type = "stat", text = "Worth", format = "money",
      bind = { measure = "value", of = { measure = "looted", since = "haul" } } },
    { type = "stat", text = "Time", format = "time", bind = { measure = "elapsed", since = "haul" } },
} }

step("saving: a name, a layout, where it's kept")
check(not Widgets.Save("", HAUL), "a name is needed")
check(not Widgets.Save("Bad", { "not a layout" }), "a layout is needed")
check(Widgets.Save("Haul", HAUL, { mark = "haul" }), "saved")
eq(Widgets.List()[1].scope, "character", "this character's by default")
check(DeckKitCharDB.widgets.Haul, "in DeckKitCharDB")
eq(Actions.Label("WIDGET:Haul"), "Haul", "offered as an action, by name")

step("bound to a grip slot, a press opens it, counting from then")
H.fire("CHAT_MSG_LOOT", W.Loot(2318, 5)) -- before it opens: not counted
H.advance(2)
Chords.Set("L4", "press", "WIDGET:Haul")
H.key("F1", true); H.key("F1", false)
check(Widgets.Shown("Haul"), "open")
local frame = UI.TrackerFrame("widget:Haul")
eq(ValueOf(frame, "Light Leather"), "0", "nothing looted yet")
eq(ValueOf(frame, "per hour"), "…", "no rate in the first minute")
H.fire("CHAT_MSG_LOOT", W.Loot(2318, 3))
H.advance(1)
eq(ValueOf(frame, "Light Leather"), "3", "counts up as loot arrives")
H.advance(119)
eq(ValueOf(frame, "per hour"), "90/h", "3 in two minutes")
eq(ValueOf(frame, "Worth"), "45c", "at the vendor price (no price addon)")
eq(ValueOf(frame, "Time"), "2 min", "time since it opened")

step("stacked with another tracker, below it; the default tracker stays where it was")
UI.ShowTracker({ type = "list", title = "Checklist", items = { { type = "check", done = false, text = "x" } } })
local default = UI.TrackerFrame()
check(default and default:IsShown(), "the default tracker is up")
local _, haulTop = frame:GetCenter()
local _, defaultTop = default:GetCenter()
check(haulTop and defaultTop and haulTop > defaultTop, "the one that showed first stays on top")
check(frame:GetBottom() > default:GetTop(), "and they don't overlap")

step("a second press closes it; opening again starts the count over")
H.key("F1", true); H.key("F1", false)
check(not Widgets.Shown("Haul"), "closed")
H.key("F1", true); H.key("F1", false)
H.advance(1)
eq(ValueOf(UI.TrackerFrame("widget:Haul"), "Light Leather"), "0", "a fresh mark")

step("account-wide: one per name, and deleting takes the action back")
check(Widgets.Save("XP", { type = "stat", text = "XP/h", bind = { measure = "xp", per = "hour" } }, { scope = "account" }),
      "saved for every character")
check(DeckKitDB.widgets.XP and not DeckKitCharDB.widgets.XP, "in DeckKitDB")
Widgets.Save("XP", { type = "stat", text = "XP/h", bind = { measure = "xp", per = "hour" } })
check(DeckKitCharDB.widgets.XP and not DeckKitDB.widgets.XP, "moving it to the character takes it out of the account")
check(Widgets.Delete("Haul"), "deleted")
check(not Widgets.Shown("Haul") and not Actions.Offered("WIDGET:Haul"), "closed and no longer an action")
check(not H.snippetErrors, "no secure snippet errors: " .. table.concat(H.snippetErrors or {}, " | "))

step("a widget shown without saving is listed while it's up, then gone")
Widgets.ShowSpec("Peek", { type = "stat", text = "XP", bind = { measure = "xp" } })
local found
for _, w in ipairs(Widgets.List()) do if w.name == "Peek" then found = w end end
check(found and found.shown and found.saved == false and found.scope == nil, "listed: shown, not saved")
Widgets.Hide("Peek")
for _, w in ipairs(Widgets.List()) do check(w.name ~= "Peek", "hidden: no longer listed") end
