-- DisenchantDeck's window look (same as WayPad's): a dark panel, a title, and a button-hint line at the bottom.
local _, ns = ...

local Window = {}
ns.Window = Window

-- Button letters in the Deck's face-button colors.
local HINT = { A = "|cff5fd35fA|r", B = "|cffe05555B|r", X = "|cff5a9cf0X|r", Y = "|cfff0d050Y|r" }

-- "A Save  B Cancel" -> the same with colored letters.
function Window.Hints(text)
    return (text:gsub("%f[%w]([ABXY])%f[%W]", HINT))
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
