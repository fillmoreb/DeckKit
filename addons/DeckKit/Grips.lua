-- Grip actions: the peeks, the dictation indicator and hiding a side. Which grip or chord does
-- what is up to Chords.lua (slots); this file is what those actions do.
--
--   Peeks        ChatDeck's / MapDeck's peek bindings show that peek while held.
--   Dictation    DECKKIT_DICTATION (a chord slot, L4+R4 at first, Decktation's push-to-talk): a
--                "Listening" indicator mid-screen while held; when you let go it says "Transcribing"
--                until your next chat message arrives (or a timeout). With Decktation's status hook
--                set up (deck-setup/decktation-hook.sh), it follows Decktation's real state instead:
--                signal keys (INSERT recording, HOME transcribing, END done, DELETE error) bound to
--                DeckKit's dictation-signal bindings.
--   Hiding a side  DECKKIT_HIDE_LEFT / _RIGHT: whatever sits along that screen edge, from any addon
--                (see "Hiding a side" below), plus anything a module adds.
--
-- Modules: ns.Grips.SetPeek(side, fn(on)), ns.Grips.AddSideToggle(side, fn(hidden)), and their
-- peek bindings call ns.Grips.Press(side, down).
local _, ns = ...

local Grips = {}
ns.Grips = Grips

local TRANSCRIBE_TIMEOUT = 12 -- seconds "Transcribing" can show without a chat message arriving
local DEFAULTS = { dictationIndicator = true }

local function Setting(key)
    local v = ns.db[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local peeks, toggles = {}, { left = {}, right = {} }
local SIDE_NAME = { left = "Left side", right = "Right side" }

function Grips.SetPeek(side, fn) peeks[side] = fn end
function Grips.AddSideToggle(side, fn) table.insert(toggles[side], fn) end

local function Peek(side, on)
    if peeks[side] then peeks[side](on) end
end

------------------------------------------------------------------------
-- The mid-screen indicator (dictation state, and side-toggle notices)
------------------------------------------------------------------------

local box, dot, label, pulse, timer, transcribing

local function Box()
    if box then return box end
    box = CreateFrame("Frame", "DeckKitGripIndicator", UIParent, "BackdropTemplate")
    box:SetPoint("CENTER", 0, 140)
    box:SetSize(220, 44)
    box:SetFrameStrata("HIGH")
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0, 0, 0, 0.9)
    box:Hide()
    dot = box:CreateTexture(nil, "OVERLAY")
    dot:SetSize(14, 14)
    dot:SetPoint("LEFT", 16, 0)
    label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT", dot, "RIGHT", 10, 0)
    pulse = dot:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.6)
    return box
end

-- dot: nil, or a color for a pulsing light ("Red", "Yellow": the game's Indicator-<color>).
local DOT_FALLBACK = { Red = { 0.9, 0.15, 0.15 }, Yellow = { 1, 0.82, 0 } }

local function Show(text, r, g, b, dot_, seconds)
    Box()
    local withDot = type(dot_) == "string"
    if withDot then
        dot:SetTexture("Interface\\COMMON\\Indicator-" .. dot_)
        if not dot:GetTexture() then local c = DOT_FALLBACK[dot_]; dot:SetColorTexture(c[1], c[2], c[3]) end
    end
    if timer then timer:Cancel(); timer = nil end
    label:SetText(text)
    label:SetTextColor(r, g, b)
    dot:SetShown(withDot)
    if withDot then pulse:Play() else pulse:Stop() end
    box:SetWidth(label:GetStringWidth() + (withDot and 62 or 32))
    label:ClearAllPoints()
    if withDot then label:SetPoint("LEFT", dot, "RIGHT", 10, 0) else label:SetPoint("CENTER") end
    box:Show()
    if seconds then timer = C_Timer.NewTimer(seconds, function() timer = nil; box:Hide(); transcribing = false end) end
end

-- A short notice in the same spot, for any module: DeckKit.Notice("text", seconds).
function ns.Notice(text, seconds) Show(text, 1, 1, 1, false, seconds or 2) end

local function HideBox()
    if timer then timer:Cancel(); timer = nil end
    transcribing = false
    if box then box:Hide() end
end

------------------------------------------------------------------------
-- Dictation, from the grips (when Decktation's status hook isn't sending its real state)
------------------------------------------------------------------------

local signalled = false -- Decktation has sent a real status: follow those, not the grips

local function Dictation(down)
    if signalled or not Setting("dictationIndicator") then return end
    if down then
        transcribing = false
        Show("Listening", 1, 0.3, 0.3, "Red")
    elseif not transcribing then
        transcribing = true
        Show("Transcribing", 1, 0.82, 0, "Yellow", TRANSCRIBE_TIMEOUT)
    end
end
ns.Chords.Offer("DECKKIT_DICTATION", { label = "Dictation", run = Dictation })

------------------------------------------------------------------------
-- Hiding a side
--
-- Every top-level frame touching the outer EDGE of the screen on that side is made transparent,
-- whichever addon made it, and given back its own transparency when the side comes back. Only
-- what's on screen when you hide it: windows opened afterwards still show. Full-screen frames,
-- tooltips, popups and DeckKit's own frames are left alone. While hidden, frames that fade
-- themselves back in are put back to transparent once a second.
------------------------------------------------------------------------

local EDGE = 0.15
local swept = { left = {}, right = {} } -- frame -> its alpha before hiding
local SKIP_NAMES = { "Tooltip", "^DropDownList", "^StaticPopup", "^DeckKit", "^DeckHUD" }

local function Skip(f)
    if f.IsForbidden and f:IsForbidden() then return true end
    local name = f:GetName()
    if name then
        for _, pattern in ipairs(SKIP_NAMES) do
            if name:find(pattern) then return true end
        end
    end
end

local function OnEdge(f, side, W, H)
    if not f:IsShown() or f:GetAlpha() == 0 then return false end
    local l, r, w, h = f:GetLeft(), f:GetRight(), f:GetWidth(), f:GetHeight()
    if not (l and r and w and h) or w > W * 0.6 or h > H * 0.9 then return false end
    if side == "left" then return l < W * EDGE end
    return r > W * (1 - EDGE)
end

local function Sweep(side)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    for _, f in ipairs({ UIParent:GetChildren() }) do
        if not swept[side][f] and not Skip(f) and OnEdge(f, side, W, H) then
            swept[side][f] = f:GetAlpha()
            f:SetAlpha(0)
        end
    end
end

local function Unsweep(side)
    for f, alpha in pairs(swept[side]) do f:SetAlpha(alpha) end
    wipe(swept[side])
end

local keeper
local function KeepSwept()
    local any = next(swept.left) or next(swept.right)
    if any and not keeper then
        keeper = C_Timer.NewTicker(1, function()
            for _, list in pairs(swept) do
                for f in pairs(list) do if f:GetAlpha() > 0 then f:SetAlpha(0) end end
            end
        end)
    elseif not any and keeper then
        keeper:Cancel()
        keeper = nil
    end
end

local function SetSide(side, hidden)
    if hidden then Sweep(side) else Unsweep(side) end
    KeepSwept()
    for _, fn in ipairs(toggles[side]) do fn(hidden) end
end

function Grips.ToggleSide(side)
    ns.db.hidden = ns.db.hidden or {}
    ns.db.hidden[side] = not ns.db.hidden[side]
    SetSide(side, ns.db.hidden[side])
    Show(SIDE_NAME[side] .. (ns.db.hidden[side] and " hidden" or " shown"), 1, 1, 1, false, 1.2)
end

-- A peek binding went down / up.
function Grips.Press(side, down) Peek(side, down) end

function DeckKit_HideSide(side) Grips.ToggleSide(side) end
ns.Chords.OfferPress("DECKKIT_HIDE_LEFT", function() Grips.ToggleSide("left") end, "Hide left side")
ns.Chords.OfferPress("DECKKIT_HIDE_RIGHT", function() Grips.ToggleSide("right") end, "Hide right side")
ns.Chords.OfferPress("DECKKIT_RELOAD", ReloadUI, "Reload UI")
BINDING_NAME_DECKKIT_HIDE_LEFT = "Hide / show the left side"
BINDING_NAME_DECKKIT_HIDE_RIGHT = "Hide / show the right side"

-- Decktation's status, sent as key presses by its status hook (see the top of this file).
function Grips.Signal(event)
    signalled = true
    ns.Debug("dictation", event)
    if not Setting("dictationIndicator") then return end
    if event == "record_start" then
        transcribing = false
        Show("Listening", 1, 0.3, 0.3, "Red")
    elseif event == "record_stop" then
        transcribing = true
        Show("Transcribing", 1, 0.82, 0, "Yellow", TRANSCRIBE_TIMEOUT)
    elseif event == "transcription_done" then
        HideBox()
    elseif event == "error" then
        Show("Didn't catch that", 1, 0.45, 0.45, false, 2)
    end
end
function DeckKit_DictationSignal(event) Grips.Signal(event) end

BINDING_NAME_DECKKIT_DICTATION_START = "Dictation signal: recording (sent by Decktation)"
BINDING_NAME_DECKKIT_DICTATION_STOP = "Dictation signal: transcribing (sent by Decktation)"
BINDING_NAME_DECKKIT_DICTATION_DONE = "Dictation signal: done (sent by Decktation)"
BINDING_NAME_DECKKIT_DICTATION_ERROR = "Dictation signal: error (sent by Decktation)"

-- The signal keys start out bound, once, only where a key still has its default binding (camera
-- pitch / view presets, which a gamepad doesn't use) or none. Rebinding them afterwards sticks.
local SIGNAL_KEYS = {
    { key = "INSERT", action = "DECKKIT_DICTATION_START", default = "PITCHUP" },
    { key = "HOME", action = "DECKKIT_DICTATION_STOP", default = "PREVVIEW" },
    { key = "END", action = "DECKKIT_DICTATION_DONE", default = "NEXTVIEW" },
    { key = "DELETE", action = "DECKKIT_DICTATION_ERROR", default = "PITCHDOWN" },
}
ns.On("PLAYER_LOGIN", function()
    if ns.db.dictationKeysSet or InCombatLockdown() then return end
    ns.db.dictationKeysSet = true
    local changed = false
    for _, s in ipairs(SIGNAL_KEYS) do
        local current = GetBindingAction(s.key) or ""
        if not GetBindingKey(s.action) and (current == "" or current == s.default) then
            SetBinding(s.key, s.action)
            changed = true
        end
    end
    if changed then SaveBindings(GetCurrentBindingSet()) end
end)

-- "Transcribing" ends when your own message shows up in chat.
local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL" }
for _, event in ipairs(CHAT_EVENTS) do
    pcall(ns.On, event, function(_, author)
        if transcribing and type(author) == "string" and author:match("^[^-]+") == UnitName("player") then
            HideBox()
        end
    end)
end

-- Put the sides back the way they were left.
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(1, function()
        for side in pairs(toggles) do
            if ns.db.hidden and ns.db.hidden[side] then SetSide(side, true) end
        end
        -- Some addons show their frames a little later: catch those too.
        C_Timer.After(4, function()
            for side in pairs(toggles) do
                if ns.db.hidden and ns.db.hidden[side] then Sweep(side); KeepSwept() end
            end
        end)
    end)
end)

ns.Settings.Add("DeckKit", ns.TITLE, {
    { type = "toggle", label = "Dictation indicator", tab = "Screen", section = "Dictation", sectionOrder = 4,
      hint = "\"Listening\" while the dictation chord is held, then \"Transcribing\".",
      get = function() return Setting("dictationIndicator") end,
      set = function(on) ns.db.dictationIndicator = on end },
})
