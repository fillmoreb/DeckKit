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
-- Practice frames: Blizzard hides its raid-style frames when you're alone, so these stand in for
-- them, laid out exactly as your Edit Mode party or raid frames would be. Every frame is you, so
-- the cursor works on them as on the real ones and focus lands on you. They look like Blizzard's:
-- class-coloured health, name, dark background. Made and moved out of combat only; off after a
-- /reload.
------------------------------------------------------------------------

local GROUP_TITLE_H = 14 -- a raid-style group's title ("Party", "Group 1") above its members
local members = {}       -- every practice frame made so far, for health updates

local function UpdateHealth()
    local max = UnitHealthMax("player")
    for _, f in ipairs(members) do
        f.health:SetMinMaxValues(0, max > 0 and max or 1)
        f.health:SetValue(UnitHealth("player"))
    end
end

local healthEvents = CreateFrame("Frame")
healthEvents:RegisterUnitEvent("UNIT_HEALTH", "player")
healthEvents:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
healthEvents:SetScript("OnEvent", UpdateHealth)

local function Member(name, parent)
    local f = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
    f:SetAttribute("unit", "player")
    f:SetAttribute("*type1", "target")
    f:RegisterForClicks("AnyUp")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    local _, class = UnitClass("player")
    local c = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or { r = 0.1, g = 0.8, b = 0.1 }
    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetPoint("TOPLEFT", 1, -1)
    f.health:SetPoint("BOTTOMRIGHT", -1, 1)
    f.health:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
    f.health:SetStatusBarColor(c.r, c.g, c.b)
    local label = f.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 3, -3)
    label:SetPoint("RIGHT", -3, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(UnitName("player"))
    table.insert(members, f)
    return f
end

-- One raid-style group: a title, then its members in a column or a row (CompactRaidGroup's layout).
-- first: the number of its first member, named HealPadPractice<first>.. (HealPad's frame list knows them).
local function Group(parent, title, first)
    local g = CreateFrame("Frame", nil, parent)
    g.isFlowGroup = true -- like Blizzard's group frames: the flow starts a new line (row or column) for each
    g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    g.title:SetText(title)
    g.members = {}
    for m = 1, 5 do g.members[m] = Member("HealPadPractice" .. (first + m - 1), g) end
    return g
end

local function LayGroup(g, w, h, horizontal)
    g.title:ClearAllPoints()
    g.title:SetPoint(horizontal and "TOPLEFT" or "TOP")
    for m, f in ipairs(g.members) do
        f:ClearAllPoints()
        f:SetSize(w, h)
        if m == 1 then
            f:SetPoint(horizontal and "TOPLEFT" or "TOP", g, horizontal and "TOPLEFT" or "TOP", 0, -GROUP_TITLE_H)
        elseif horizontal then
            f:SetPoint("LEFT", g.members[m - 1], "RIGHT")
        else
            f:SetPoint("TOP", g.members[m - 1], "BOTTOM")
        end
    end
    if horizontal then g:SetSize(5 * w, GROUP_TITLE_H + h) else g:SetSize(w, GROUP_TITLE_H + 5 * h) end
end

------------------------------------------------------------------------
-- Practice party: five frames where your raid-style party frames would be.
------------------------------------------------------------------------

local party -- a group frame, made on first use
local partyShown = false

local function PlaceParty()
    local S = Enum.EditModeUnitFrameSetting
    local p = PartyFrame
    local w, h = p:GetSettingValue(S.FrameWidth), p:GetSettingValue(S.FrameHeight)
    local l, b, pw, ph = p:GetRect()
    if not l or w == 0 or h == 0 then return false end
    -- The group sits right of PartyFrame's padding, at its top (PartyFrameMixin:UpdatePaddingAndLayout).
    LayGroup(party, w, h, p:GetSettingValueBool(S.UseHorizontalGroups))
    party:ClearAllPoints()
    party:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l + (p.leftPadding or 2), b + ph)
    return true
end

local function PracticePartyShown() return partyShown end

local function SetPracticeParty(on)
    if InCombatLockdown() then ns.Print("can't change the practice party in combat.") return end
    if on and not party then
        party = CreateFrame("Frame", nil, UIParent)
        party.title = party:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        party.title:SetText(PARTY or "Party")
        party.members = {}
        for m = 1, 5 do party.members[m] = Member("HealPadPracticeParty" .. m, party) end
    end
    if on and not PlaceParty() then ns.Print("couldn't read your party frame layout.") on = false end
    partyShown = on
    if party then party:SetShown(on) end
    if on then UpdateHealth(); Refresh() end
end

------------------------------------------------------------------------
-- Practice raid: 10, 25 or 40 frames where your raid frames would be, flowed the way Blizzard flows
-- them (EditModeManagerFrameMixin:UpdateRaidContainerFlow), with its own FlowContainer helpers:
-- separate groups (each a column or a row) or all members together, rows of your Edit Mode size.
------------------------------------------------------------------------

local RAID_GROUPS = { [10] = 2, [25] = 5, [40] = 8 } -- the groups Edit Mode's preview shows per size
local raidSize = 25
local raid -- the flow container, made on first use
local raidShown = false

-- Where a frame's TOPLEFT would be from its first anchor alone. The raid container has no size while
-- you're solo, and its clamping to the screen then pushes it to the top edge, so its own GetTop lies.
local function AnchoredTopLeft(frame)
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    rel = rel or UIParent
    if not (point and rel:GetLeft()) then return frame:GetLeft(), frame:GetTop() end
    local rx = relPoint:find("LEFT") and rel:GetLeft() or relPoint:find("RIGHT") and rel:GetRight() or (rel:GetLeft() + rel:GetRight()) / 2
    local ry = relPoint:find("TOP") and rel:GetTop() or relPoint:find("BOTTOM") and rel:GetBottom() or (rel:GetTop() + rel:GetBottom()) / 2
    return rx + x, ry + y -- any point of a frame with no size is its top left
end

local function PlaceRaid()
    local S, T = Enum.EditModeUnitFrameSetting, Enum.RaidGroupDisplayType
    local c = CompactRaidFrameContainer
    local w, h = c:GetSettingValue(S.FrameWidth), c:GetSettingValue(S.FrameHeight)
    local left, top = AnchoredTopLeft(c)
    if not left or w == 0 or h == 0 then return false end
    local display = c:GetSettingValue(S.RaidGroupDisplayType)
    local separate = display == T.SeparateGroupsVertical or display == T.SeparateGroupsHorizontal
    local orientation = (display == T.SeparateGroupsVertical or display == T.CombineGroupsVertical) and "vertical" or "horizontal"
    local perLine = separate and 5 or c:GetSettingValue(S.RowSize)
    local groups = RAID_GROUPS[raidSize]

    FlowContainer_RemoveAllObjects(raid)
    FlowContainer_PauseUpdates(raid)
    FlowContainer_SetOrientation(raid, orientation)
    FlowContainer_SetMaxPerLine(raid, perLine)
    raid:SetSize(3000, 3000) -- the flow fits to the container's size, as Blizzard's does
    for gi, g in ipairs(raid.groups) do
        local used = gi <= groups
        g:SetShown(used and separate)
        if used and separate then
            LayGroup(g, w, h, display == T.SeparateGroupsHorizontal)
            FlowContainer_AddObject(raid, g)
        end
        for _, f in ipairs(g.members) do
            if not separate then
                f:SetParent(raid)
                f:SetSize(w, h)
                f:SetShown(used)
                if used then FlowContainer_AddObject(raid, f) end
            else
                f:SetParent(g)
                f:Show()
            end
        end
    end
    FlowContainer_ResumeUpdates(raid)
    raid:ClearAllPoints()
    raid:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return true
end

local function PracticeRaidShown() return raidShown end

local function SetPracticeRaid(on)
    if InCombatLockdown() then ns.Print("can't change the practice raid in combat.") return end
    if on and not raid then
        raid = CreateFrame("Frame", nil, UIParent)
        FlowContainer_Initialize(raid)
        raid.groups = {}
        for g = 1, 8 do raid.groups[g] = Group(raid, GROUP .. " " .. g, (g - 1) * 5 + 1) end
    end
    if on and not PlaceRaid() then ns.Print("couldn't read your raid frame layout.") on = false end
    raidShown = on
    if raid then raid:SetShown(on) end
    if on then UpdateHealth(); Refresh() end
end

local function SetRaidSize(size)
    raidSize = size
    if raidShown and not InCombatLockdown() then PlaceRaid(); Refresh() end
end

-- Follow Edit Mode changes while they're showing.
ns.On("EDIT_MODE_LAYOUTS_UPDATED", function()
    if InCombatLockdown() then return end
    C_Timer.After(0, function()
        if partyShown then PlaceParty() end
        if raidShown then PlaceRaid() end
    end)
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
    elseif arg == "heals" then ns.OpenHealMacros()
    elseif arg == "party" then
        SetPracticeParty(not PracticePartyShown())
        ns.Print("practice party " .. (PracticePartyShown() and "on" or "off") .. ".")
    elseif arg == "practice" or arg == "raid" then
        SetPracticeRaid(not PracticeRaidShown())
        ns.Print("practice raid " .. (PracticeRaidShown() and "on" or "off") .. ".")
    else
        ns.Print("/deckkit healpad macros: make the four d-pad macros. /deckkit healpad bind: open "
            .. "the Macros window to put them on your crossbar. Heal with [@focus], e.g. "
            .. "/cast [@focus,help,nodead][] Flash Heal")
    end
end, "d-pad cursor on the raid frames: macros, heals, bind, party, raid")

ns.AddSettings({
    { type = "section", tab = "Healing", label = "HealPad", order = 1 },
    { type = "action", label = "Make the d-pad macros", run = MakeMacros,
      hint = "Makes HealPad Up / Down / Left / Right. Put them on your healing page's d-pad." },
    { type = "action", label = "Make heal macros",
      hint = "One macro per helpful spell you know (and Resurrection), cast on your focus: for your healing "
          .. "page's face buttons. Pick which in the list.",
      run = function() ns.OpenHealMacros() end },
    { type = "action", label = "Open Macros to bind them",
      hint = "WoW's Macros window: pick a HealPad macro, press {X} (Bind to Action Bar), then the d-pad button.",
      run = OpenMacros },
    { type = "toggle", label = "Practice party",
      hint = "Five frames where your party frames would be (your Edit Mode party layout), to see it and try "
          .. "the cursor while solo. Every one is you. Off again after a /reload.",
      get = PracticePartyShown, set = SetPracticeParty },
    { type = "toggle", label = "Practice raid",
      hint = "Raid frames where yours would be (your Edit Mode raid layout), to see it and try the cursor "
          .. "while solo. Every one is you. Off again after a /reload.",
      get = PracticeRaidShown, set = SetPracticeRaid },
    { type = "choice", label = "Practice raid size", values = { { 10, "10" }, { 25, "25" }, { 40, "40" } },
      get = function() return raidSize end, set = SetRaidSize },
    { type = "info", label = "Heal macros aim at the selection with [@focus]." },
})
