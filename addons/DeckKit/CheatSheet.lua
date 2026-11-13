-- Paddle cheat sheet: a small list on screen of what the paddle chords do, each row a chord glyph
-- (the Deck's back, held grips lit, a bar for a hold) and its action. Which slots it shows is picked
-- in the menu (Controls > Cheat sheet); everything assigned shows until it's unticked, so a newly
-- filled slot turns up by itself. It takes no input, and hides with its side (Hide left / right side).
-- On and off: the menu, a chord slot ("Cheat sheet"), or /deckkit sheet.
local _, ns = ...

local Chords, UI = ns.Chords, ns.UI
local Sheet = {}
ns.CheatSheet = Sheet

local GLYPH, PAD, ROW_GAP, MARGIN = 28, 10, 2, 8
local GESTURES = { "press", "hold" }

-- Where it can sit: name, label, which side it's on (for hiding a side), and how to anchor it.
local SPOTS = {
    { "bottomright", "Bottom right", "right", function(f) f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -MARGIN, MARGIN) end },
    { "leftchat", "Left, above chat", "left", function(f)
        if ChatFrame1 then f:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 36)
        else f:SetPoint("LEFT", UIParent, "LEFT", MARGIN, 0) end
    end },
    { "topcenter", "Top center", nil, function(f) f:SetPoint("TOP", UIParent, "TOP", 0, -150) end },
    { "righttracker", "Right, under the quest tracker", "right", function(f)
        local t = ObjectiveTrackerFrame
        if t and t:IsShown() and t:GetBottom() then
            f:SetPoint("TOPRIGHT", UIParent, "BOTTOMRIGHT", -MARGIN, t:GetBottom() - MARGIN)
        else
            f:SetPoint("RIGHT", UIParent, "RIGHT", -MARGIN, 0)
        end
    end },
}
local SPOT_VALUES = {}
for i, s in ipairs(SPOTS) do SPOT_VALUES[i] = { s[1], s[2] } end

local function DB()
    ns.db.cheatSheet = ns.db.cheatSheet or { on = false, pos = "bottomright", off = {} }
    local db = ns.db.cheatSheet
    db.off = db.off or {}
    return db
end

local function Spot()
    local pos = DB().pos
    for _, s in ipairs(SPOTS) do if s[1] == pos then return s end end
    return SPOTS[1]
end

local function Key(chord, gesture) return chord .. ":" .. gesture end

function Sheet.Shown(chord, gesture) return not DB().off[Key(chord, gesture)] end

------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------

local frame, rows, sideHidden = nil, {}, { left = false, right = false }

local function Build()
    frame = CreateFrame("Frame", "DeckKitCheatSheet", UIParent)
    frame:SetFrameStrata("MEDIUM") -- under dialogs, peeks and DeckKit's windows
    frame:EnableMouse(false)
    frame:EnableKeyboard(false)
    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(0.035, 0.035, 0.045, 0.7)
    UI.Border(frame, "SimplePanelTemplate")
end

local function Row(i)
    if rows[i] then return rows[i] end
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(UI.Font.small)
    fs:SetJustifyH("LEFT")
    rows[i] = fs
    return fs
end

function Sheet.Refresh()
    local db = DB()
    if not db.on or not Chords.Enabled() then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    local n, width = 0, 0
    for _, chord in ipairs(Chords.LIST) do
        for _, gesture in ipairs(GESTURES) do
            local id = Chords.Get(chord, gesture)
            if id and Sheet.Shown(chord, gesture) then
                n = n + 1
                local fs = Row(n)
                fs:SetText(Chords.Glyph(chord, gesture, GLYPH) .. "  " .. Chords.Label(id))
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", PAD, -PAD - (n - 1) * (GLYPH + ROW_GAP))
                fs:Show()
                width = math.max(width, fs:GetStringWidth())
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local spot = Spot()
    if n == 0 or (spot[3] and sideHidden[spot[3]]) then
        frame:Hide()
        return
    end
    frame:SetSize(width + 2 * PAD + 4, n * GLYPH + (n - 1) * ROW_GAP + 2 * PAD)
    frame:ClearAllPoints()
    spot[4](frame)
    frame:Show()
end

function Sheet.Toggle()
    local db = DB()
    db.on = not db.on
    Sheet.Refresh()
end

-- Things that change what it shows, or where.
Chords.OnChange(Sheet.Refresh)
for _, side in ipairs({ "left", "right" }) do
    ns.Paddles.AddSideToggle(side, function(hidden)
        sideHidden[side] = hidden
        Sheet.Refresh()
    end)
end
ns.On("PLAYER_LOGIN", function() C_Timer.After(0, Sheet.Refresh) end)
-- The tracker grows and shrinks; follow it when the sheet sits under it.
pcall(ns.On, "QUEST_WATCH_LIST_CHANGED", function()
    if DB().pos == "righttracker" then C_Timer.After(0.2, Sheet.Refresh) end
end)

Chords.OfferPress("DECKKIT_CHEATSHEET", Sheet.Toggle, "Cheat sheet")
BINDING_NAME_DECKKIT_CHEATSHEET = "Show / hide the paddle cheat sheet"
ns.AddCommand("sheet", function()
    Sheet.Toggle()
    ns.Print("cheat sheet " .. (DB().on and "on" or "off"))
end, "show or hide the paddle cheat sheet")

------------------------------------------------------------------------
-- Settings: Controls > Cheat sheet
------------------------------------------------------------------------

local items = {
    { type = "section", tab = "Controls", label = "Cheat sheet", order = 3.4 },
    { type = "toggle", label = "Show cheat sheet",
      hint = "A small list on screen of what your paddles do. Tick the slots it shows below. Also on a "
          .. "chord slot (\"Cheat sheet\") or /deckkit sheet.",
      get = function() return DB().on end,
      set = function(on) DB().on = on; Sheet.Refresh() end },
    { type = "choice", label = "Where", values = SPOT_VALUES,
      hint = "Where on screen it sits. It hides with its side when you hide that side.",
      get = function() return Spot()[1] end,
      set = function(v) DB().pos = v; Sheet.Refresh() end },
}
for _, chord in ipairs(Chords.LIST) do
    for _, gesture in ipairs(GESTURES) do
        items[#items + 1] = {
            type = "toggle",
            label = function()
                local id = Chords.Get(chord, gesture)
                return Chords.Glyph(chord, gesture) .. "  " .. (id and Chords.Label(id) or "Nothing")
            end,
            hint = Chords.Describe(chord, gesture) .. ". Ticked: it shows on the cheat sheet.",
            disabled = function() return not Chords.Get(chord, gesture) end,
            reason = "Nothing on this slot",
            get = function() return Chords.Get(chord, gesture) ~= nil and Sheet.Shown(chord, gesture) end,
            set = function(on) DB().off[Key(chord, gesture)] = (not on) or nil; Sheet.Refresh() end,
        }
    end
end
ns.Settings.Add("DeckKit", ns.TITLE, items)
