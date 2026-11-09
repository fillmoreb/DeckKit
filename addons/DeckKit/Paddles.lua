-- Paddle chords: what the two peek buttons (on the Deck's top back grips) do together.
--
--   Left  = ChatDeck's peek binding, right = MapDeck's peek binding (Key Bindings > DeckKit).
--   Hold one     after a short delay, that side's peek (chat / map) until you let go. The delay
--                leaves room to press the other one first.
--   Hold both    no peeks: dictation (set Decktation's push-to-talk to the same two grips). A
--                "Listening" indicator shows mid-screen; when you let go it says "Transcribing"
--                until your next chat message arrives (or a timeout).
--   Double-tap   hide / show that side's interface (modules add what goes: DeckHUD hides the chat
--                and the guide on the left, the minimap and quest tracker on the right).
--
-- Modules: ns.Paddles.SetPeek(side, fn(on)), ns.Paddles.AddSideToggle(side, fn(hidden)),
-- and their peek bindings call ns.Paddles.Press(side, down). With chords off in the menu, each
-- button is just its peek again.
local _, ns = ...

local Paddles = {}
ns.Paddles = Paddles

local TRANSCRIBE_TIMEOUT = 12 -- seconds "Transcribing" can show without a chat message arriving
local DEFAULTS = { paddleChords = true, peekDelay = 0.12, doubleTap = 0.35, dictationIndicator = true }

local function Setting(key)
    local v = ns.db[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local sides = { left = {}, right = {} }
local peeks, toggles = {}, { left = {}, right = {} }
local chord = false -- both were held: no peeks or taps until both are up again
local OTHER = { left = "right", right = "left" }
local SIDE_NAME = { left = "Left side", right = "Right side" }

function Paddles.SetPeek(side, fn) peeks[side] = fn end
function Paddles.AddSideToggle(side, fn) table.insert(toggles[side], fn) end

local function Peek(side, on)
    if peeks[side] then peeks[side](on) end
end

------------------------------------------------------------------------
-- The mid-screen indicator (dictation state, and side-toggle notices)
------------------------------------------------------------------------

local box, dot, label, pulse, timer, transcribing

local function Box()
    if box then return box end
    box = CreateFrame("Frame", "DeckKitPaddleIndicator", UIParent, "BackdropTemplate")
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
    dot:SetTexture("Interface\\COMMON\\Indicator-Red")
    if not dot:GetTexture() then dot:SetColorTexture(0.9, 0.15, 0.15) end
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

local function Show(text, r, g, b, withDot, seconds)
    Box()
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

local function HideBox()
    if timer then timer:Cancel(); timer = nil end
    transcribing = false
    if box then box:Hide() end
end

------------------------------------------------------------------------
-- Chords, holds and taps
------------------------------------------------------------------------

local function StartChord()
    chord = true
    for _, s in pairs(sides) do
        if s.timer then s.timer:Cancel(); s.timer = nil end
        s.lastTap = nil
    end
    for side, s in pairs(sides) do
        if s.peeking then s.peeking = false; Peek(side, false) end
    end
    transcribing = false
    if Setting("dictationIndicator") then Show("Listening", 1, 0.3, 0.3, true) end
end

local function ChordLetGo() -- the first grip released: dictation stops, transcription starts
    if transcribing or not Setting("dictationIndicator") then return end
    transcribing = true
    Show("Transcribing", 1, 0.82, 0, false, TRANSCRIBE_TIMEOUT)
end

function Paddles.ToggleSide(side)
    ns.db.hidden = ns.db.hidden or {}
    ns.db.hidden[side] = not ns.db.hidden[side]
    for _, fn in ipairs(toggles[side]) do fn(ns.db.hidden[side]) end
    Show(SIDE_NAME[side] .. (ns.db.hidden[side] and " hidden" or " shown"), 1, 1, 1, false, 1.2)
end

function Paddles.Press(side, down)
    local s, other = sides[side], sides[OTHER[side]]
    if not Setting("paddleChords") then
        Peek(side, down)
        return
    end
    if down then
        if s.down then return end -- a held key repeats "down"
        s.down = true
        if other.down or chord then
            if not chord then StartChord() end
            return
        end
        if s.timer then s.timer:Cancel() end
        s.timer = C_Timer.NewTimer(Setting("peekDelay"), function()
            s.timer = nil
            if s.down and not chord then
                s.peeking = true
                Peek(side, true)
            end
        end)
        return
    end

    if not s.down then return end
    s.down = false
    if s.timer then s.timer:Cancel(); s.timer = nil end
    if chord then
        ChordLetGo()
        if not other.down then chord = false end
        return
    end
    if s.peeking then
        s.peeking = false
        Peek(side, false)
        return
    end
    -- Let go before the peek showed: a tap. Two quick ones toggle the side.
    local now = GetTime()
    if s.lastTap and now - s.lastTap <= Setting("doubleTap") then
        s.lastTap = nil
        Paddles.ToggleSide(side)
    else
        s.lastTap = now
    end
end

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
        for side, fns in pairs(toggles) do
            local hidden = ns.db.hidden and ns.db.hidden[side] or false
            if hidden then for _, fn in ipairs(fns) do fn(true) end end
        end
    end)
end)

ns.Settings.Add("DeckKit", ns.TITLE, {
    { type = "toggle", label = "Paddle chords",
      hint = "Peek buttons: hold for the peek, hold both for dictation, double-tap to hide that side.",
      get = function() return Setting("paddleChords") end,
      set = function(on) ns.db.paddleChords = on end },
    { type = "range", label = "Peek delay", min = 0, max = 0.3, step = 0.02,
      format = function(v) return string.format("%d ms", math.floor(v * 1000 + 0.5)) end,
      hint = "How long a peek button is held before the peek shows (room to press both for dictation).",
      get = function() return Setting("peekDelay") end,
      set = function(v) ns.db.peekDelay = v end },
    { type = "range", label = "Double-tap window", min = 0.2, max = 0.6, step = 0.05,
      format = function(v) return string.format("%d ms", math.floor(v * 1000 + 0.5)) end,
      get = function() return Setting("doubleTap") end,
      set = function(v) ns.db.doubleTap = v end },
    { type = "toggle", label = "Dictation indicator",
      hint = "\"Listening\" while both peek buttons are held, then \"Transcribing\".",
      get = function() return Setting("dictationIndicator") end,
      set = function(on) ns.db.dictationIndicator = on end },
    { type = "info", label = "Left: chat peek binding. Right: map peek binding." },
})
