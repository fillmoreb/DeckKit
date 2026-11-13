-- ChatDeck: hold a button to read chat full-screen in a big font. Not for typing.
--
-- The keybinding (Bindings.xml, runOnUp) shows the peek on press and hides it on release.
-- It shows the chat tab you have selected: its latest lines, plus anything new while you look.
-- It leaves both sticks alone, so you keep full control of your character while it's up. (It used
-- to take the sticks for a right-stick scroll; moving freely mattered more, so scrolling went.)
--
-- /chatdeck size <12-40>   font size        /chatdeck   show / hide (for testing at a desk)
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff7fd8ffChatDeck|r")
local Print = ns.Print

local DEFAULTS = { size = 22, lines = 300 }
local MARGIN = 60

local db
local frame, text
local source -- the chat frame being shown

local function SourceFrame()
    return SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1
end

-- Copy one line into the peek. Lines can hold values the game won't let addons read; skip those.
local function Add(msg, r, g, b)
    if type(msg) ~= "string" then return end
    if issecretvalue and issecretvalue(msg) then return end
    pcall(text.AddMessage, text, msg, r or 1, g or 1, b or 1)
end

local function Fill()
    text:Clear()
    local n = source.GetNumMessages and source:GetNumMessages() or 0
    for i = math.max(1, n - db.lines + 1), n do
        local ok, msg, r, g, b = pcall(source.GetMessageInfo, source, i)
        if ok then Add(msg, r, g, b) end
    end
    text:ScrollToBottom()
end

local function Create()
    frame = CreateFrame("Frame", "ChatDeckPeek", UIParent, "BackdropTemplate")
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(0, 0, 0, 0.82)
    frame:Hide()

    text = CreateFrame("ScrollingMessageFrame", nil, frame)
    text:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    text:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN + 10)
    text:SetFont(STANDARD_TEXT_FONT, db.size, "")
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    text:SetFading(false)
    text:SetMaxLines(db.lines)
    if text.SetIndentedWordWrap then text:SetIndentedWordWrap(true) end

    -- New lines arrive while you look.
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.AddMessage then
            hooksecurefunc(cf, "AddMessage", function(self, msg, r, g, b)
                if frame:IsShown() and self == source then Add(msg, r, g, b) end
            end)
        end
    end
end

local function Show()
    if not frame then Create() end
    source = SourceFrame()
    Fill()
    frame:Show()
end

local function Hide()
    if frame then frame:Hide() end
end

-- keystate: "down" on press, "up" on release (runOnUp). Repeats of "down" just keep it up.
local function Peek(on)
    if not on then Hide()
    elseif not (frame and frame:IsShown()) then Show() end
end

-- The old peek binding (runOnUp) still works: it goes through DeckKit's grip actions.
-- keystate: "down" on press (repeats while held), "up" on release (runOnUp).
function ChatDeck_Peek(keystate)
    DeckKit.Grips.Press("left", keystate ~= "up")
end
DeckKit.Grips.SetPeek("left", Peek)

BINDING_HEADER_CHATDECK = "ChatDeck"
BINDING_NAME_CHATDECK_PEEK = "Peek at chat (hold)"
DeckKit.Chords.Offer("CHATDECK_PEEK", { label = "Chat peek", run = function(down) Peek(down) end })

SLASH_CHATDECK1 = "/chatdeck"
SlashCmdList.CHATDECK = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "size" and tonumber(arg) then
        db.size = math.max(12, math.min(40, math.floor(tonumber(arg))))
        if text then text:SetFont(STANDARD_TEXT_FONT, db.size, "") end
        Print("font size " .. db.size .. ".")
    elseif cmd == "" then
        if frame and frame:IsShown() then Hide() else Show() end
    else
        Print("chat peek: a grip chord slot (DeckKit menu, Controls > Grips).  /chatdeck size <12-40>  ·  /chatdeck to show/hide")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "ChatDeck" then
        ChatDeckDB = ChatDeckDB or {}
        for k, v in pairs(DEFAULTS) do if ChatDeckDB[k] == nil then ChatDeckDB[k] = v end end
        db = ChatDeckDB
    elseif event == "PLAYER_LOGIN" then
        -- Built now, out of combat, so it's ready even if the first peek is mid-fight.
        if not frame then Create() end
        self:UnregisterAllEvents()
    end
end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Chat", order = 2 },
    { type = "range", label = "Font size", min = 12, max = 40, step = 2,
      hint = "Text size in the chat peek.",
      get = function() return db and db.size or DEFAULTS.size end,
      set = function(v)
          db.size = v
          if text then text:SetFont(STANDARD_TEXT_FONT, v, "") end
      end },
    { type = "info", label = "Hold the chat peek's grip slot (Controls > Grips, L4 at first) to read chat. Both sticks stay yours: you can keep running while it's up." },
})
