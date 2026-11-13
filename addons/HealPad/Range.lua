-- Range dots for focus macros. The crossbar's range dot (a "●" on each button) checks your *target*,
-- even for a macro that casts [@focus]: with your focus beside you and your target across the zone,
-- every heal shows red. On buttons holding a [@focus] macro, while you have a living friendly focus,
-- the game's dot is made transparent and ours shows in its place: white when the focus is in range of
-- that spell, red when not. No focus (the macro then casts on your target, as usual): the game's dot
-- is back.
--
-- Nothing on Blizzard's buttons is hooked or changed except the dot's alpha (alpha only, like
-- DeckHUD's hidden prompts: other changes to the crossbar taint it). Our dot is a separate font string
-- on a frame of our own, laid over the button.
local _, ns = ...

local IN_RANGE = { 1, 1, 1 }
local OUT_OF_RANGE = { 1, 0.15, 0.15 }

local buttons = {} -- the crossbar's action buttons
local dots = {}    -- button -> our dot
local isFocusMacro = {} -- macro name -> true / false

-- The crossbar's buttons (not the Edit Mode copies), found once they exist.
local function FindButtons()
    wipe(buttons)
    local f = EnumerateFrames()
    while f do
        if not f:IsForbidden() then
            local name = f:GetName()
            if type(name) == "string" and not (issecretvalue and issecretvalue(name))
                and string.find(name, "^GamepadMainActionBarFramePage") and string.find(name, "ActionButton%d+$")
                and f.RangeIndicator then
                buttons[#buttons + 1] = f
            end
        end
        f = EnumerateFrames(f)
    end
end

-- The spell a [@focus] macro in this slot casts, or nil.
local function FocusSpell(slot)
    if not slot or slot == 0 then return end
    local kind, id, sub = GetActionInfo(slot)
    if kind ~= "macro" or sub ~= "spell" or not id then return end
    local name = GetActionText(slot)
    if not name then return end
    local known = isFocusMacro[name]
    if known == nil then
        local index = GetMacroIndexByName(name)
        local body = index and index > 0 and GetMacroBody(index) or ""
        known = body:lower():find("@focus", 1, true) ~= nil
        isFocusMacro[name] = known
    end
    return known and id or nil
end

local function Dot(button)
    local d = dots[button]
    if d then return d end
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button.RangeIndicator)
    holder:SetFrameLevel(button:GetFrameLevel() + 10)
    local fs = holder:CreateFontString(nil, "OVERLAY")
    local font, size, flags = button.RangeIndicator:GetFont()
    fs:SetFont(font or STANDARD_TEXT_FONT, size or 12, flags or "OUTLINE")
    fs:SetText(button.RangeIndicator:GetText() or "●")
    fs:SetJustifyH(button.RangeIndicator:GetJustifyH())
    fs:SetAllPoints(holder)
    fs:Hide()
    dots[button] = fs
    return fs
end

local function FocusUsable()
    return UnitExists("focus") and UnitCanAssist("player", "focus") and not UnitIsDeadOrGhost("focus")
end

local function Update()
    local haveFocus = FocusUsable()
    for _, button in ipairs(buttons) do
        local spell = haveFocus and FocusSpell(button.action)
        local inRange = spell and C_Spell.IsSpellInRange(spell, "focus")
        if inRange ~= nil and not (issecretvalue and issecretvalue(inRange)) then
            local d = Dot(button)
            d:SetTextColor(unpack(inRange and IN_RANGE or OUT_OF_RANGE))
            d:Show()
            if button.RangeIndicator:GetAlpha() ~= 0 then button.RangeIndicator:SetAlpha(0) end
        else
            if dots[button] then dots[button]:Hide() end
            if button.RangeIndicator:GetAlpha() ~= 1 then button.RangeIndicator:SetAlpha(1) end
        end
    end
end

-- Built at login, out of combat (our frames hang off the crossbar's buttons).
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(1, function()
        FindButtons()
        for _, button in ipairs(buttons) do Dot(button) end
        C_Timer.NewTicker(0.2, Update)
    end)
end)
-- A macro edited or renamed: look again.
ns.On("UPDATE_MACROS", function() wipe(isFocusMacro) end)
