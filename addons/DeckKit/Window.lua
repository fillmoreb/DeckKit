-- The DeckKit window look: a dark panel, a title, and a button-hint line at the bottom.
local _, ns = ...

local Window = {}
ns.Window = Window

-- Controller button glyphs: the game's own prompt art (atlases), Xbox style, which is how the
-- Deck's controller shows up. Newer atlas names first, then the older set. Atlas list from
-- Improved Forever's Pad.lua (MIT License, Copyright (c) 2026 markg).
local GLYPHS = {
    A = { "gamepad-xbox1-buttona-normal", "Gamepad_Ltr_A_64" },
    B = { "gamepad-xbox1-buttonb-normal", "Gamepad_Ltr_B_64" },
    X = { "gamepad-xbox1-buttonx-normal", "Gamepad_Ltr_X_64" },
    Y = { "gamepad-xbox1-buttony-normal", "Gamepad_Ltr_Y_64" },
    LB = { "gamepad-xbox1-trigger-lb-normal", "Gamepad_Ltr_LShoulder_64" },
    RB = { "gamepad-xbox1-trigger-rb-normal", "Gamepad_Ltr_RShoulder_64" },
    LT = { "gamepad-xbox1-trigger-lt-normal", "Gamepad_Ltr_LTrigger_64" },
    RT = { "gamepad-xbox1-trigger-rt-normal", "Gamepad_Ltr_RTrigger_64" },
    MENU = { "gamepad-xbox1-menu-normal", "Gamepad_Ltr_Menu_64" },
    VIEW = { "gamepad-xbox1-view-normal", "Gamepad_Ltr_View_64" },
    DPAD = { "gamepad-xbox1-dpadall-normal" },
    DPAD_LR = { "gamepad-xbox1-dpadleftright-normal" },
    DPAD_UD = { "gamepad-xbox1-dpadupdown-normal" },
}
-- Without the art: the name, face buttons in the Deck's colors.
local FALLBACK = {
    A = "|cff5fd35fA|r", B = "|cffe05555B|r", X = "|cff5a9cf0X|r", Y = "|cfff0d050Y|r",
    MENU = "Menu", VIEW = "View", DPAD = "D-pad", DPAD_LR = "Left/Right", DPAD_UD = "Up/Down",
}
local glyphCache = {}

-- Inline markup for a button ("A", "LB", "MENU", "DPAD_LR", ...), for any FontString.
function Window.Glyph(key, size)
    size = size or 18
    local cacheKey = key .. size
    if glyphCache[cacheKey] then return glyphCache[cacheKey] end
    local markup = FALLBACK[key] or key
    for _, atlas in ipairs(GLYPHS[key] or {}) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            markup = string.format("|A:%s:%d:%d|a", atlas, size, size)
            break
        end
    end
    glyphCache[cacheKey] = markup
    return markup
end

-- "{MENU} twice" -> the same with the button's glyph. For any text.
function Window.Glyphs(text)
    return (text:gsub("{([%u_]+)}", function(key) return Window.Glyph(key) end))
end

-- Button-hint lines. Written either with {KEY} tokens, or with bare button words
-- ("A Save   B Cancel", "LB/RB Hidden"), which become tokens first. (Not both in one line, and
-- never converting after markup exists: an inline icon starts with "|A:".)
function Window.Hints(text)
    if not text:find("{", 1, true) then
        text = text:gsub("%f[%w]([ABXY])%f[%W]", "{%1}")    -- first: "LB" has no bare B
        text = text:gsub("%f[%w]([LR][BT])%f[%W]", "{%1}")
    end
    return Window.Glyphs(text)
end

function Window.New(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    f:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    f:EnableMouse(true)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText(title)

    f.hints = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hints:SetPoint("BOTTOM", 0, 12)

    function f:SetHints(text) self.hints:SetText(Window.Hints(text)) end
    return f
end

function Window.Sound(open)
    local kit = SOUNDKIT and (open and SOUNDKIT.IG_MAINMENU_OPEN or SOUNDKIT.IG_MAINMENU_CLOSE)
    if kit then PlaySound(kit) end
end

function Window.Tick()
    local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if kit then PlaySound(kit) end
end
