-- Macro names on action buttons. A macro on an action bar shows its name across the button ("HealPad
-- Left", "Power Word: Shie"), and the game has no setting to turn that off. With "Hide macro names"
-- on, that label is made transparent on the crossbar's buttons and on the regular action bars.
--
-- Alpha only: nothing on Blizzard's buttons is hooked, and the label keeps its text (other changes
-- to the crossbar taint it, see HealPad/Range.lua). Naming macros " " instead would also hide the
-- label, but HealPad finds its macros by name.
local _, ns = ...

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local labels = {} -- every action button's name label

local function Find()
    wipe(labels)
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b and b.Name then labels[#labels + 1] = b.Name end
        end
    end
    -- The crossbar's buttons have no global names to look up by number: walk the frames once.
    local f = EnumerateFrames()
    while f do
        if not f:IsForbidden() then
            local name = f:GetName()
            if type(name) == "string" and not (issecretvalue and issecretvalue(name))
                and string.find(name, "^GamepadMainActionBarFramePage") and string.find(name, "ActionButton%d+$")
                and f.Name then
                labels[#labels + 1] = f.Name
            end
        end
        f = EnumerateFrames(f)
    end
end

local function HideNames() return ns.db.hideMacroNames == true end

local function Apply()
    local alpha = HideNames() and 0 or 1
    for _, label in ipairs(labels) do
        if label:GetAlpha() ~= alpha then label:SetAlpha(alpha) end
    end
end

-- The crossbar's buttons exist a moment after login (as for HealPad's range dots).
ns.On("PLAYER_LOGIN", function()
    C_Timer.After(1, function() Find(); Apply() end)
end)
-- In case the game puts a label back: whenever a slot or a macro changes.
ns.On("ACTIONBAR_SLOT_CHANGED", Apply)
ns.On("UPDATE_MACROS", Apply)

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Action bars", order = 5 },
    { type = "toggle", label = "Hide macro names",
      hint = "No macro name across the buttons on the crossbar and the action bars. The icon still shows.",
      get = HideNames,
      set = function(on) ns.db.hideMacroNames = on; Apply() end },
})
