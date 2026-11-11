-- DeckHUD chat: a thin frame instead of Blizzard's chat art, no gamepad button
-- hints under the edit box, and the chat tucked into the bottom-left corner. Each is a toggle on
-- DeckHUD's page of the DeckKit menu.
--
-- Forever's chat is Blizzard's floating chat frame: ChatFrame1 (General) with its edit box hanging
-- 2 px below it (5 px further left, 32 tall), ChatFrame2 (Combat Log) docked as a second tab.
local _, ns = ...

local DEFAULTS = { chatThin = true, chatTuck = true, chatNoLegend = true }
local MARGIN = 4                -- gap to the left edge, in UIParent units (1 per pixel on the Deck)
local BOTTOM = 4                -- the edit box's frame bottom...
local BAR_GAP = 2               -- ...or this far above the XP bar, while that's along the bottom
local EDIT_DX, EDIT_DY = 5, 34  -- the edit box's offset from the chat frame's bottom-left
local EDIT_PAD = 5              -- the edit box's typing area sits 5 px inside its frame
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function DB() return ns.db end

-- Keep f hidden while setting `flag` is on (Blizzard shows some of these again on its own).
local hooked = {}
local function Keep(f, flag)
    if type(f) ~= "table" or type(f.Hide) ~= "function" then return end
    if not hooked[f] then
        hooked[f] = true
        local function again(self) if DB()[flag] ~= false then self:Hide() end end
        hooksecurefunc(f, "Show", again)
        if f.SetShown then hooksecurefunc(f, "SetShown", function(self, on) if on then again(self) end end) end
    end
    f:Hide()
end

------------------------------------------------------------------------
-- Thin frame
------------------------------------------------------------------------

local ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local EDIT_ART = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }

local chatBox, editBox

local function ThinBox(target)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.35)
    f:SetBackdropBorderColor(0, 0, 0, 0.9)
    f:SetFrameStrata(target:GetFrameStrata())
    f:SetFrameLevel(math.max(0, target:GetFrameLevel() - 1)) -- under the text
    return f
end

local function Thin()
    local on = DB().chatThin ~= false
    if on then
        for i = 1, 2 do
            for _, part in ipairs(ART) do Keep(_G["ChatFrame" .. i .. part], "chatThin") end
        end
        for _, part in ipairs(EDIT_ART) do Keep(_G["ChatFrame1EditBox" .. part], "chatThin") end
        -- Around the text (4 px of room); the edit box's under it, the same width.
        if not chatBox then
            chatBox = ThinBox(ChatFrame1)
            chatBox:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", -4, 4)
            chatBox:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", 4, -4)
            editBox = ThinBox(ChatFrame1EditBox)
            editBox:SetPoint("LEFT", chatBox, "LEFT")
            editBox:SetPoint("RIGHT", chatBox, "RIGHT")
            editBox:SetPoint("TOP", ChatFrame1EditBox, "TOP", 0, -EDIT_PAD)
            editBox:SetPoint("BOTTOM", ChatFrame1EditBox, "BOTTOM", 0, EDIT_PAD)
        end
    end
    if chatBox then chatBox:SetShown(on) end
    if editBox then editBox:SetShown(on) end
end

------------------------------------------------------------------------
-- No button hints under the edit box
------------------------------------------------------------------------

-- Forever's gamepad legend under the chat box ("{A} Send  {X} Chat Channels  {Y} Tab Settings
-- {B} Back"), shown whenever the edit box has focus while Gamepad UI is on. It's the footer's
-- ChatFrameN.FloatingChatFrameinputLegend (lowercase i), made the first time the box gets focus.
-- Only its alpha is touched: hooking or hiding it taints the chat box, and then Enter can't run
-- slash commands. Blizzard sets the alpha of its parts but never of the legend itself.
local function NoLegend()
    local alpha = DB().chatNoLegend ~= false and 0 or 1
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        local legend = cf and cf.FloatingChatFrameinputLegend
        if legend and legend:GetAlpha() ~= alpha then legend:SetAlpha(alpha) end
    end
end

------------------------------------------------------------------------
-- Tucked into the corner
------------------------------------------------------------------------

local placing = false

-- Where the edit box's bottom goes: near the edge, unless the XP bar runs along the bottom under it.
local function Bottom()
    -- (the bars themselves: StatusTrackingBarManager is an invisible holder that stays at the bottom)
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "MainMenuExpBar" }) do
        local bar = _G[name]
        local bottom, left, top = bar and bar.GetBottom and bar:GetBottom(), bar and bar.GetLeft and bar:GetLeft(), bar and bar.GetTop and bar:GetTop()
        if type(bottom) == "number" and type(left) == "number" and type(top) == "number" and bar:IsShown()
            and bottom < 40 and left < MARGIN + 4 + ChatFrame1:GetWidth() + 10 then
            return math.max(BOTTOM, top + BAR_GAP)
        end
    end
    return BOTTOM
end

local function Tuck()
    if DB().chatTuck == false then return end
    placing = true
    -- Blizzard clamps the chat on screen with room for its button column on the left; that
    -- column is hidden here, so drop the clamp to get into the corner.
    ChatFrame1:SetClampedToScreen(false)
    ChatFrame1:ClearAllPoints()
    ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", MARGIN + 4, Bottom() + EDIT_DY)
    placing = false
end

------------------------------------------------------------------------

local function Apply()
    Thin()
    NoLegend()
    Tuck()
end

ns.On("ADDON_LOADED", function(name)
    if name ~= "DeckHUD" then return end
    for k, v in pairs(DEFAULTS) do
        if DeckHUDDB[k] == nil then DeckHUDDB[k] = v end
    end
end)

ns.On("PLAYER_LOGIN", function()
    if not ChatFrame1 then return end
    Apply()
    C_Timer.After(1, Apply) -- after the chat frames and Edit Mode have settled
    C_Timer.NewTicker(0.1, NoLegend) -- the legend is made on the first focus; no hooks (see NoLegend)
    -- Edit Mode (or the chat's own layout code) moving it back: tuck it in again.
    hooksecurefunc(ChatFrame1, "SetPoint", function()
        if not placing and DB().chatTuck ~= false then C_Timer.After(0, Tuck) end
    end)
end)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Chat", order = 2 },
    { type = "toggle", label = "Chat: thin frame",
      hint = "A thin dark edge instead of Blizzard's chat art. Turning it off needs a /reload.",
      get = function() return DB().chatThin ~= false end,
      set = function(on)
          DB().chatThin = on
          Thin()
          if not on then ns.Print("Type /reload to bring back the original chat frame art.") end
      end },
    { type = "toggle", label = "Chat: hide the button hints",
      hint = "No {A} Send / {X} Chat Channels / {Y} Tab Settings bar under the chat box.",
      get = function() return DB().chatNoLegend ~= false end,
      set = function(on) DB().chatNoLegend = on; NoLegend() end },
    { type = "toggle", label = "Chat: tuck into the corner",
      hint = "Bottom-left, close to the edges. Turning it off needs a /reload.",
      get = function() return DB().chatTuck ~= false end,
      set = function(on)
          DB().chatTuck = on
          if on then Tuck() else ns.Print("Type /reload to put the chat back where it was.") end
      end },
})
