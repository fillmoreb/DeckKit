-- No target menu in combat. With no trigger held, Triangle (Y on the Deck, PAD4) is the crossbar's
-- fixed "inspect" button: it opens your target's menu (Blizzard_GamepadActionBars,
-- SetupNonBindableInspect), and the open menu takes the pad until B closes it. Hit by accident in a
-- fight, it eats your next presses.
--
-- This claims Triangle through DeckKit.Override while in combat, with a press that does nothing.
-- It's all secure: the menu never opens, and nothing of Blizzard's is hooked or closed (closing the
-- menu from addon code would leave the gamepad bar's state tainted). With L2 or R2 held, Override
-- passes the press on to that layer's crossbar button, so the trigger pages work as before.
local _, ns = ...

local function On() return ns.db.noTargetMenuInCombat ~= false end

local function Apply()
    ns.Override.Set("PAD4", "notargetmenu", On() and {
        when = "[combat]",
        priority = 10,
        macro = "",
    } or nil)
end

ns.On("PLAYER_LOGIN", Apply)

ns.AddSettings({
    { type = "section", tab = "Controls", label = "Buttons", order = 2 },
    { type = "toggle", label = "No target menu in combat",
      hint = "{Y} on its own doesn't open your target's menu during a fight. "
          .. "With a trigger held, {Y} works as usual.",
      get = On,
      set = function(on) ns.db.noTargetMenuInCombat = on; Apply() end },
})
