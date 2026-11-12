-- HealPad: a cursor on the raid frames, moved with the d-pad, that sets your focus.
--
-- Put the four HealPad macros (made from the DeckKit menu, or /deckkit healpad macros) on the
-- d-pad slots of your healing crossbar page. Each press moves the cursor to the nearest raid frame in
-- that direction and makes that member your focus, so heal macros aim with [@focus]:
--   /cast [@focus,help,nodead][] Flash Heal
-- Works with any of Blizzard's raid-style frames: a 5-player party, or a raid of 10 to 40, groups
-- kept together or not, horizontal or vertical. It goes by where the frames are on screen.
--
-- Focus can only be set by secure code, so the moving is done in a restricted snippet that runs
-- before each button's click (in combat too). Out of combat we hand that snippet the raid frames.
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff7ee08fHealPad|r")

local DIRS = { "Up", "Down", "Left", "Right" }
local MACRO_PREFIX = "HealPad "

-- The header keeps the frame list (frame refs f1..fN) and the cursor position (attribute "cur").
local header = CreateFrame("Frame", "HealPadHeader", UIParent, "SecureHandlerBaseTemplate")
header:SetAttribute("count", 0)

-- The cursor. A protected frame the snippet lays over the selected raid frame (so it can move in
-- combat); on it, Forever's own gamepad cursor chevron on both sides of the frame, pointing in, in
-- the game's cursor yellow, bobbing a little, faster than the game's pointer (SmartNavigationPointerTemplate),
-- and a border in the same yellow. The
-- chevrons sit on a plain child, so we can hide them when their raid frame goes away (a protected
-- frame can't be hidden from our code in combat).
local cursor = CreateFrame("Frame", "HealPadCursor", UIParent, "SecureHandlerBaseTemplate")
cursor:SetFrameStrata("DIALOG")
cursor:SetSize(1, 1)
cursor:Hide()
header:SetFrameRef("cursor", cursor)

local look = CreateFrame("Frame", nil, cursor)
look:SetAllPoints()
local CHEVRON_RATIO = 42 / 70 -- the atlas's width / height
local YELLOW = GAMEPAD_SMARTNAV_CURSOR_COLOR -- the game's cursor tint (#ffe600)
local INSET = 10    -- how far each chevron reaches in over the frame's edge, on average
local BOB = 1       -- it bobs this far either side of INSET...
local BOB_TIME = 0.4 -- ...taking this long each way (the game's pointer: 4 px, 1 s)

-- side "left": on the frame's left edge, pointing right (the atlas as it is); "right": mirrored.
local function Chevron(side)
    local holder = CreateFrame("Frame", nil, look)
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    if tex:SetAtlas("gamepad-largecursor-white") then
        if side == "right" then tex:SetTexCoord(1, 0, 0, 1) end
        if YELLOW then tex:SetVertexColor(YELLOW:GetRGBA()) end
    else
        tex:SetColorTexture(1, 0.9, 0, 1) -- no atlas: a plain marker, still visible
    end
    -- Starts BOB further out than INSET and travels 2 * BOB in and back, so it's centred on INSET.
    if side == "left" then
        holder:SetPoint("RIGHT", look, "LEFT", INSET - BOB, 0)
    else
        holder:SetPoint("LEFT", look, "RIGHT", -(INSET - BOB), 0)
    end
    local inward = (side == "left" and 1 or -1) * 2 * BOB
    local bob = holder:CreateAnimationGroup()
    bob:SetLooping("REPEAT")
    local go = bob:CreateAnimation("Translation")
    go:SetOffset(inward, 0); go:SetDuration(BOB_TIME); go:SetOrder(1); go:SetSmoothing("IN_OUT")
    local back = bob:CreateAnimation("Translation")
    back:SetOffset(-inward, 0); back:SetDuration(BOB_TIME); back:SetOrder(2); back:SetSmoothing("IN_OUT")
    bob:Play()
    return holder
end
local chevrons = { Chevron("left"), Chevron("right") }

-- A border in the same yellow, just inside the selected frame's edges.
local BORDER = 2
local function Edge(p1, p2, horizontal)
    local t = look:CreateTexture(nil, "OVERLAY", nil, -1) -- under the chevrons
    if YELLOW then t:SetColorTexture(YELLOW:GetRGBA()) else t:SetColorTexture(1, 0.9, 0, 1) end
    t:SetPoint(p1)
    t:SetPoint(p2)
    if horizontal then t:SetHeight(BORDER) else t:SetWidth(BORDER) end
end
Edge("TOPLEFT", "TOPRIGHT", true)
Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
Edge("TOPLEFT", "BOTTOMLEFT", false)
Edge("TOPRIGHT", "BOTTOMRIGHT", false)

look:SetScript("OnUpdate", function()
    local _, anchor = cursor:GetPoint(1)
    local on = anchor and anchor:IsVisible()
    look:SetAlpha(on and 1 or 0)
    if on then
        local h = math.max(16, math.min(40, anchor:GetHeight() * 0.9))
        for _, c in ipairs(chevrons) do c:SetSize(h * CHEVRON_RATIO, h) end
    end
end)

-- Runs in the restricted environment before a direction button's click. self = the button,
-- owner = the header. Picks the next frame, moves the cursor, and sets the button's unit; the click
-- itself then sets focus (type "focus"). Returning false cancels the click. Errors in a snippet
-- fail silently (no Lua error), so keep it plain. Frame handles have GetRect but not GetCenter.
local MOVE = [[
    if down == false then return false end -- a key press clicks twice (down, up); move once
    local dir = self:GetAttribute("dir")
    local n = owner:GetAttribute("count") or 0
    local cur = owner:GetAttribute("cur")
    local from = cur and owner:GetFrameRef("f" .. cur)
    if from and not (from:IsVisible() and from:GetAttribute("unit")) then from = nil end
    local best, bestScore
    local fx, fy, w, h
    if from then
        local l, b
        l, b, w, h = from:GetRect()
        fx, fy = l + w / 2, b + h / 2
    end
    for i = 1, n do
        local f = owner:GetFrameRef("f" .. i)
        if i ~= cur and f and f:IsVisible() and f:GetAttribute("unit") then
            local l, b, fw, fh = f:GetRect()
            local x, y = l + fw / 2, b + fh / 2
            local score
            if from then
                local dx, dy = x - fx, y - fy
                local along, across, size
                if dir == "Right" then along, across, size = dx, dy, w
                elseif dir == "Left" then along, across, size = -dx, dy, w
                elseif dir == "Up" then along, across, size = dy, dx, h
                else along, across, size = -dy, dx, h end
                if across < 0 then across = -across end
                -- the next one in line first; drifting sideways costs more than going further
                if along > size * 0.25 then score = along + 3 * across end
            else
                score = x - 3 * y -- no cursor yet (or its frame is gone): start at the top left
            end
            if score and (not bestScore or score < bestScore) then best, bestScore = i, score end
        end
    end
    -- At the edge: wrap around to the far end of the same row (left / right) or column (up / down).
    if not best and from then
        for i = 1, n do
            local f = owner:GetFrameRef("f" .. i)
            if i ~= cur and f and f:IsVisible() and f:GetAttribute("unit") then
                local l, b, fw, fh = f:GetRect()
                local dx, dy = l + fw / 2 - fx, b + fh / 2 - fy
                local along, across, size, line
                if dir == "Right" then along, across, size, line = dx, dy, w, h
                elseif dir == "Left" then along, across, size, line = -dx, dy, w, h
                elseif dir == "Up" then along, across, size, line = dy, dx, h, w
                else along, across, size, line = -dy, dx, h, w end
                if across < 0 then across = -across end
                -- behind us and in our line; the furthest back wins
                if along < -size * 0.25 and across <= line * 0.5 then
                    local score = along + 3 * across
                    if not bestScore or score < bestScore then best, bestScore = i, score end
                end
            end
        end
    end
    if not best then
        if from then
            self:SetAttribute("unit", from:GetAttribute("unit")) -- alone in its line: stay, refocus
            return
        end
        return false
    end
    local f = owner:GetFrameRef("f" .. best)
    owner:SetAttribute("cur", best)
    self:SetAttribute("unit", f:GetAttribute("unit"))
    local box = owner:GetFrameRef("cursor")
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    box:Show()
]]

for _, dir in ipairs(DIRS) do
    local b = CreateFrame("Button", "HealPad" .. dir, UIParent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "focus")
    b:SetAttribute("dir", dir)
    b:RegisterForClicks("AnyDown", "AnyUp")
    header:WrapScript(b, "OnClick", MOVE)
end

------------------------------------------------------------------------
-- The raid frames (handed to the snippet out of combat)
------------------------------------------------------------------------

-- Blizzard's raid-style frame names. New ones are only ever appended, so the cursor's index keeps
-- pointing at the same frame.
local known, knownSet = {}, {}

local function Candidates()
    local names = {}
    for m = 1, 5 do table.insert(names, "CompactPartyFrameMember" .. m) end
    for g = 1, 8 do
        for m = 1, 5 do table.insert(names, "CompactRaidGroup" .. g .. "Member" .. m) end
    end
    for i = 1, 40 do table.insert(names, "CompactRaidFrame" .. i) end
    for i = 1, 40 do table.insert(names, "HealPadPractice" .. i) end -- the practice grid, below
    for i = 1, 5 do table.insert(names, "HealPadPracticeParty" .. i) end -- the practice party, below
    return names
end

local pending = false
local function Refresh()
    if InCombatLockdown() then pending = true return end
    pending = false
    for _, name in ipairs(Candidates()) do
        local f = _G[name]
        if f and not knownSet[f] then
            table.insert(known, f)
            knownSet[f] = true
            header:SetFrameRef("f" .. #known, f)
        end
    end
    header:SetAttribute("count", #known)
end

ns.On("PLAYER_LOGIN", Refresh)
ns.On("GROUP_ROSTER_UPDATE", Refresh)
ns.On("PLAYER_ENTERING_WORLD", Refresh)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then Refresh() end end)
if CompactUnitFrame_SetUpFrame then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", function() Refresh() end)
end

------------------------------------------------------------------------
-- Practice grid: fake raid frames to try the cursor solo (Blizzard hides its raid frames when
-- you're alone). Every frame is you, so focus lands on you. Out of combat only.
------------------------------------------------------------------------

local PRACTICE_COLS, PRACTICE_ROWS = 5, 4
local PRACTICE_W, PRACTICE_H, PRACTICE_GAP = 72, 36, 2
local practice -- the holder frame, made on first use

local function MakePractice()
    practice = CreateFrame("Frame", nil, UIParent)
    practice:SetSize(PRACTICE_COLS * (PRACTICE_W + PRACTICE_GAP), PRACTICE_ROWS * (PRACTICE_H + PRACTICE_GAP))
    practice:SetPoint("LEFT", UIParent, "LEFT", 260, 40)
    local title = practice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", practice, "TOPLEFT", 0, 4)
    title:SetText("HealPad practice")
    for i = 1, PRACTICE_COLS * PRACTICE_ROWS do
        local col, row = (i - 1) % PRACTICE_COLS, math.floor((i - 1) / PRACTICE_COLS)
        local f = CreateFrame("Button", "HealPadPractice" .. i, practice, "SecureUnitButtonTemplate")
        f:SetSize(PRACTICE_W, PRACTICE_H)
        f:SetPoint("TOPLEFT", col * (PRACTICE_W + PRACTICE_GAP), -row * (PRACTICE_H + PRACTICE_GAP))
        f:SetAttribute("unit", "player")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.45, 0.15, 0.85)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(string.format("%d,%d", col + 1, row + 1))
    end
end

local function SetPractice(on)
    if InCombatLockdown() then ns.Print("can't change the practice grid in combat.") return end
    if on and not practice then MakePractice() end
    if practice then practice:SetShown(on) end
    if on then Refresh() end
end

local function PracticeShown() return practice ~= nil and practice:IsShown() end

------------------------------------------------------------------------
-- Practice party: five frames exactly where your raid-style party frames would be (your Edit Mode
-- party position, size and direction), to see the layout and try the cursor while solo. Every frame
-- is you. They look like Blizzard's raid frames: class-coloured health, name, dark background.
------------------------------------------------------------------------

local PARTY_TITLE_H = 14 -- the group's "Party" title above the first member, if it can't be measured
local party -- the frames, made on first use

local function PartyLayout()
    local S = Enum.EditModeUnitFrameSetting
    local p = PartyFrame
    local w, h = p:GetSettingValue(S.FrameWidth), p:GetSettingValue(S.FrameHeight)
    local horizontal = p:GetSettingValueBool(S.UseHorizontalGroups)
    local l, b, pw, ph = p:GetRect()
    if not l or w == 0 or h == 0 then return end
    -- Members start right of PartyFrame's padding and under the group title (CompactRaidGroup's layout).
    local pad = p.leftPadding or 2
    local title = CompactPartyFrame and CompactPartyFrame.title and CompactPartyFrame.title:GetHeight() or PARTY_TITLE_H
    return l + pad, b + ph - title, w, h, horizontal
end

local function UpdatePartyHealth()
    if not party then return end
    local max = UnitHealthMax("player")
    for _, f in ipairs(party) do
        f.health:SetMinMaxValues(0, max > 0 and max or 1)
        f.health:SetValue(UnitHealth("player"))
    end
end

local function MakeParty()
    party = {}
    local _, class = UnitClass("player")
    local c = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or { r = 0.1, g = 0.8, b = 0.1 }
    for i = 1, 5 do
        local f = CreateFrame("Button", "HealPadPracticeParty" .. i, UIParent, "SecureUnitButtonTemplate")
        f:SetAttribute("unit", "player")
        f:SetAttribute("*type1", "target")
        f:RegisterForClicks("AnyUp")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        f.health = CreateFrame("StatusBar", nil, f)
        f.health:SetPoint("TOPLEFT", 1, -1)
        f.health:SetPoint("BOTTOMRIGHT", -1, 1)
        f.health:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
        f.health:SetStatusBarColor(c.r, c.g, c.b)
        local name = f.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", 3, -3)
        name:SetPoint("RIGHT", -3, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(UnitName("player"))
        f:Hide()
        party[i] = f
    end
    local events = CreateFrame("Frame", nil, party[1])
    events:RegisterUnitEvent("UNIT_HEALTH", "player")
    events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    events:SetScript("OnEvent", UpdatePartyHealth)
end

local function PlaceParty()
    local x, top, w, h, horizontal = PartyLayout()
    if not x then return false end
    for i, f in ipairs(party) do
        f:ClearAllPoints()
        f:SetSize(w, h)
        if horizontal then
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + (i - 1) * w, top)
        else
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top - (i - 1) * h)
        end
    end
    return true
end

local partyShown = false
local function PracticePartyShown() return partyShown end

local function SetPracticeParty(on)
    if InCombatLockdown() then ns.Print("can't change the practice party in combat.") return end
    if on and not party then MakeParty() end
    if on and not PlaceParty() then ns.Print("couldn't read your party frame layout.") on = false end
    partyShown = on
    for _, f in ipairs(party or {}) do f:SetShown(on) end
    if on then UpdatePartyHealth(); Refresh() end
end

-- Follow Edit Mode changes while it's showing.
ns.On("EDIT_MODE_LAYOUTS_UPDATED", function()
    if partyShown and not InCombatLockdown() then C_Timer.After(0, PlaceParty) end
end)

------------------------------------------------------------------------
-- The macros
------------------------------------------------------------------------

local ICONS = { Up = "misc_arrowlup", Down = "misc_arrowdown", Left = "misc_arrowleft", Right = "misc_arrowright" }

local function MakeMacros()
    if InCombatLockdown() then ns.Print("can't make macros in combat.") return end
    local made, have = 0, 0
    for _, dir in ipairs(DIRS) do
        local name = MACRO_PREFIX .. dir
        local body = "/click HealPad" .. dir .. " LeftButton true"
        local index = GetMacroIndexByName(name)
        if index and index > 0 then
            EditMacro(index, name, nil, body)
            have = have + 1
        else
            local ok = pcall(CreateMacro, name, ICONS[dir] or "INV_MISC_QUESTIONMARK", body, nil)
            if ok then made = made + 1 end
        end
    end
    ns.Print(string.format("macros ready (%d new, %d updated): \"%sUp\", Down, Left, Right. "
        .. "Put them on your healing page's d-pad.", made, have, MACRO_PREFIX))
end

-- WoW's Macros window. With the gamepad UI, {X} on a macro there is "Bind to Action Bar": the same
-- "press the button combination" screen the spellbook uses. Binding is left to that window: started
-- from our menu, the bind screen trips a protected call (SetPreferredGamepadInteractTarget) and the
-- game shows an "addon blocked" popup.
local function OpenMacros()
    if InCombatLockdown() then ns.Print("can't open the Macros window in combat.") return end
    if ShowMacroFrame then
        ShowMacroFrame()
    else
        local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if load then load("Blizzard_MacroUI") end
        if MacroFrame_Show then MacroFrame_Show() end
    end
end

ns.AddCommand("healpad", function(arg)
    arg = strtrim(arg or ""):lower()
    if arg == "macros" then MakeMacros()
    elseif arg == "bind" then OpenMacros()
    elseif arg == "party" then
        SetPracticeParty(not PracticePartyShown())
        ns.Print("practice party " .. (PracticePartyShown() and "on" or "off") .. ".")
    elseif arg == "practice" then
        SetPractice(not PracticeShown())
        ns.Print("practice grid " .. (PracticeShown() and "on" or "off") .. ".")
    else
        ns.Print("/deckkit healpad macros: make the four d-pad macros. /deckkit healpad bind: open "
            .. "the Macros window to put them on your crossbar. Heal with [@focus], e.g. "
            .. "/cast [@focus,help,nodead][] Flash Heal")
    end
end, "d-pad cursor on the raid frames: macros, bind, practice, party")

ns.AddSettings({
    { type = "section", tab = "Healing", label = "HealPad", order = 1 },
    { type = "action", label = "Make the d-pad macros", run = MakeMacros,
      hint = "Makes HealPad Up / Down / Left / Right. Put them on your healing page's d-pad." },
    { type = "action", label = "Open Macros to bind them",
      hint = "WoW's Macros window: pick a HealPad macro, press {X} (Bind to Action Bar), then the d-pad button.",
      run = OpenMacros },
    { type = "toggle", label = "Practice party",
      hint = "Five frames where your party frames would be (your Edit Mode party layout), to see it and try "
          .. "the cursor while solo. Every one is you. Off again after a /reload.",
      get = PracticePartyShown, set = SetPracticeParty },
    { type = "toggle", label = "Practice grid",
      hint = "20 fake raid frames to try the cursor solo. Every one is you. Off again after a /reload.",
      get = PracticeShown, set = SetPractice },
    { type = "info", label = "Heal macros aim at the selection with [@focus]." },
})
