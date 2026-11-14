-- Grip actions: the peeks, the dictation indicator and hiding a side. Which grip or chord does
-- what is up to Chords.lua (slots); this file is what those actions do.
--
--   Peeks        ChatDeck's / MapDeck's peek bindings show that peek while held.
--   Dictation    DECKKIT_DICTATION (a chord slot, L4+R4 at first, Decktation's push-to-talk): a
--                "Listening" indicator mid-screen while held; when you let go it says "Transcribing"
--                until your next chat message arrives (or a timeout). Something that knows the
--                dictation tool's real state can report it instead with DeckKit.Dictation.SetState
--                (below); from then on the grips no longer drive the indicator.
--   Hiding a side  DECKKIT_HIDE_LEFT / _RIGHT: whatever sits along that screen edge, from any addon
--                (see "Hiding a side" below), plus anything a module adds.
--
-- Modules: ns.Grips.SetPeek(side, fn(on)), ns.Grips.AddSideToggle(side, fn(hidden)), and their
-- peek bindings call ns.Grips.Press(side, down).
local _, ns = ...

local Grips = {}
ns.Grips = Grips

local TRANSCRIBE_TIMEOUT = 12 -- seconds "Transcribing" can show without a chat message arriving
local DEFAULTS = { dictationIndicator = true, indicatorAlpha = 1 }

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
    box = CreateFrame("Frame", "DeckKitGripIndicator", UIParent)
    box:SetPoint("CENTER", 0, 140)
    box:SetSize(220, 64) -- the metal edge's corners are 64 tall: any shorter and they poke out
    box:SetFrameStrata("HIGH")
    -- DeckKit's window look: Forever's thin metal edge on the windows' dark fill.
    local fill = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(0.035, 0.035, 0.045, 0.9)
    ns.UI.Border(box, "SimplePanelTemplate")
    box:Hide()
    dot = box:CreateTexture(nil, "OVERLAY")
    dot:SetSize(24, 24)
    dot:SetPoint("LEFT", 14, 0)
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

-- dot: nil, or which pulsing icon: "Red" (listening: the voice chat mic), "Yellow" (transcribing:
-- voice chat's speech-to-text bubble) or "Error" (failed: the same bubble, red). Without
-- those atlases, the game's Indicator-<color> light (a plain color for Error).
local DOT_ICON = { Red = "voicechat-icon-mic", Yellow = "voicechat-icon-stt-on", Error = "voicechat-icon-stt-silenced" }
local DOT_FALLBACK = { Red = { 0.9, 0.15, 0.15 }, Yellow = { 1, 0.82, 0 }, Error = { 0.9, 0.15, 0.15 } }

local function Show(text, r, g, b, dot_, seconds)
    Box()
    local withDot = type(dot_) == "string"
    if withDot then
        local atlas = DOT_ICON[dot_]
        if atlas and C_Texture.GetAtlasInfo(atlas) then
            dot:SetAtlas(atlas)
        else
            dot:SetTexture("Interface\\COMMON\\Indicator-" .. dot_)
            if not dot:GetTexture() then local c = DOT_FALLBACK[dot_]; dot:SetColorTexture(c[1], c[2], c[3]) end
        end
    end
    if timer then timer:Cancel(); timer = nil end
    label:SetText(text)
    label:SetTextColor(r, g, b)
    dot:SetShown(withDot)
    if withDot then pulse:Play() else pulse:Stop() end
    box:SetWidth(label:GetStringWidth() + (withDot and 70 or 32))
    label:ClearAllPoints()
    if withDot then label:SetPoint("LEFT", dot, "RIGHT", 10, 0) else label:SetPoint("CENTER") end
    box:SetAlpha(Setting("indicatorAlpha"))
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

local signalled = false -- something has reported the real state (SetState): follow that, not the grips

local function Dictation(down)
    if signalled or not Setting("dictationIndicator") then return end
    if down then
        transcribing = false
        Show("Listening", 1, 0.82, 0.2, "Red")
    elseif not transcribing then
        transcribing = true
        Show("Transcribing", 0.4, 0.9, 0.35, "Yellow", TRANSCRIBE_TIMEOUT)
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

-- The dictation tool's real state, from whatever can see it:
--   DeckKit.Dictation.SetState("recording" | "transcribing" | "done" | "error")
-- DeckKit doesn't know or care who calls it.
ns.Dictation = {}
function ns.Dictation.SetState(state)
    signalled = true
    ns.Debug("dictation", state)
    if not Setting("dictationIndicator") then return end
    if state == "recording" then
        transcribing = false
        Show("Listening", 1, 0.82, 0.2, "Red")
    elseif state == "transcribing" then
        transcribing = true
        Show("Transcribing", 0.4, 0.9, 0.35, "Yellow", TRANSCRIBE_TIMEOUT)
    elseif state == "done" then
        HideBox()
    elseif state == "error" then
        Show("Failed", 1, 0.3, 0.3, "Error", 2)
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
    { type = "toggle", label = "Dictation indicator", tab = "Chat", section = "Dictation", sectionOrder = 4,
      hint = "\"Listening\" while the dictation chord is held, then \"Transcribing\".",
      get = function() return Setting("dictationIndicator") end,
      set = function(on) ns.db.dictationIndicator = on end },
    { type = "range", label = "Indicator opacity", tab = "Chat", section = "Dictation", sectionOrder = 4,
      min = 0.2, max = 1, step = 0.1, format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
      hint = "How solid the Listening / Transcribing box is (and DeckKit's other short notices, which "
          .. "show in the same spot). It shows for a moment as you change it.",
      get = function() return Setting("indicatorAlpha") end,
      set = function(v)
          ns.db.indicatorAlpha = v
          Show("Indicator opacity " .. math.floor(v * 100 + 0.5) .. "%", 1, 1, 1, false, 1.5)
      end },
})
