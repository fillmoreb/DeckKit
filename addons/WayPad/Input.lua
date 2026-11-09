-- Controller input for WayPad's windows.
--
-- Adapted from BagPad's Input/Controller.lua (MIT License, Copyright (c) 2026 Chris).
--
-- While a WayPad window is open, an invisible catcher frame at the top strata receives
-- OnGamePadButtonDown. Keys the window handles are consumed (propagation off for that press);
-- every other key reaches the game as normal. The controller's mapped state is also polled each
-- frame, as a backup and to repeat a held D-pad direction. Each press is handled once.
--
-- Never call into Blizzard's gamepad systems: that taints the player's bindings.
-- Propagation can't change in combat, so windows close when combat starts.
local _, ns = ...

local Input = {}
ns.Input = Input

local REPEAT_DELAY, REPEAT_RATE = 0.35, 0.09
local REPEAT_KEYS = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }

local function SetPropagate(frame, propagate)
    if not InCombatLockdown() then frame:SetPropagateKeyboardInput(propagate) end
end

local stateTime, state, stateDevice
local indexes = {}

local function MappedState()
    local now = GetTime()
    if now ~= stateTime then
        local device = C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()
        stateTime, stateDevice, state = now, device or 0, C_GamePad.GetDeviceMappedState(device)
    end
    return state, stateDevice
end

-- true/false for a binding name ("PAD2"), or nil when the state can't be read.
local function PolledDown(key)
    if not (C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.ButtonBindingToIndex) then return nil end
    local current, device = MappedState()
    local known = indexes[device]
    if not known then
        known = {}
        indexes[device] = known
    end
    local index = known[key]
    if index == nil then
        index = C_GamePad.ButtonBindingToIndex(key)
        if type(index) == "number" then known[key] = index end
    end
    if type(current) ~= "table" or type(current.buttons) ~= "table" or type(index) ~= "number" then return nil end
    return current.buttons[index + 1] == true
end

local Handler = {}
Handler.__index = Handler

-- window: the frame whose visibility turns input on and off.
-- handlers: key ("PADDUP", "PAD1", ...) -> function(). Unlisted keys reach the game.
function Input.New(window, handlers)
    local h = setmetatable({ window = window, handlers = handlers, pressed = {}, polled = {}, held = {} }, Handler)

    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetFrameStrata("TOOLTIP")
    catcher:SetFrameLevel(9000)
    catcher:SetSize(1, 1)
    catcher:SetPoint("TOPLEFT")
    catcher:Hide()
    catcher:SetScript("OnGamePadButtonDown", function(_, key)
        if h.draining then -- window already closed: only the press that closed it stays ours
            SetPropagate(catcher, not h.draining[key])
            return
        end
        local handled = h.handlers[key] ~= nil
        SetPropagate(catcher, not handled)
        if handled then h:Handle(key) end
    end)
    catcher:SetScript("OnGamePadButtonUp", function(_, key)
        if h.draining then
            h.draining[key] = nil
            SetPropagate(catcher, true)
            if not next(h.draining) then h:Teardown() end
            return
        end
        h:Release(key)
        SetPropagate(catcher, true)
    end)
    -- Keyboard fallback (arrows, Enter, Escape) for testing at a desk.
    local KEYS = { UP = "PADDUP", DOWN = "PADDDOWN", LEFT = "PADDLEFT", RIGHT = "PADDRIGHT",
        ENTER = "PAD1", ESCAPE = "PAD2", DELETE = "PAD4", E = "PAD3" }
    catcher:SetScript("OnKeyDown", function(_, key)
        if h.draining then
            SetPropagate(catcher, true)
            return
        end
        local pad = KEYS[key]
        local handled = pad and h.handlers[pad] ~= nil
        SetPropagate(catcher, not handled)
        if handled then h.handlers[pad]() end
    end)
    SetPropagate(catcher, true)
    h.catcher = catcher

    window:HookScript("OnShow", function() h:Start() end)
    window:HookScript("OnHide", function() h:Stop() end)
    ns.On("PLAYER_REGEN_DISABLED", function()
        if window:IsShown() then window:Hide() end
    end)
    return h
end

function Handler:Handle(key)
    if self.pressed[key] then return end
    self.pressed[key] = true
    self.held[key] = REPEAT_KEYS[key] and -REPEAT_DELAY or nil
    self.handlers[key]()
end

function Handler:Release(key)
    self.pressed[key] = nil
    self.held[key] = nil
end

function Handler:Poll(elapsed)
    for key in pairs(self.handlers) do
        local down = PolledDown(key)
        if down == nil then return end
        if down and not self.polled[key] then
            self:Handle(key)
        elseif down and self.held[key] then
            self.held[key] = self.held[key] + elapsed
            if self.held[key] >= REPEAT_RATE then
                self.held[key] = 0
                self.handlers[key]()
            end
        elseif not down then
            self:Release(key)
        end
        self.polled[key] = down
    end
end

function Handler:Start()
    self.draining = nil
    wipe(self.pressed)
    wipe(self.polled)
    wipe(self.held)
    -- Buttons already held (e.g. the one that opened the window) don't count until released.
    for key in pairs(self.handlers) do
        local down = PolledDown(key)
        self.polled[key] = down
        self.pressed[key] = down or nil
    end
    local catcher = self.catcher
    catcher:Show()
    if not InCombatLockdown() then
        if catcher.EnableGamePadButton then catcher:EnableGamePadButton(true) end
        catcher:EnableKeyboard(true)
    end
    SetPropagate(catcher, true)
    catcher:SetScript("OnUpdate", function(_, elapsed) self:Poll(elapsed) end)
end

-- The window closed. A button still held (usually the A or B that closed it) stays ours until
-- it's released: its press already counted, and letting it through would make the game act on
-- it too (A = jump). Everything else reaches the game right away.
function Handler:Stop()
    wipe(self.held)
    local draining = {}
    for key in pairs(self.handlers) do
        if self.pressed[key] or PolledDown(key) then draining[key] = true end
    end
    wipe(self.pressed)
    if not next(draining) or InCombatLockdown() then
        self:Teardown()
        return
    end
    self.draining = draining
    local waited = 0
    self.catcher:SetScript("OnUpdate", function(_, elapsed)
        -- Backup for a missed button-up: stop once nothing we hold is down (or after 3 s).
        waited = waited + elapsed
        local any = false
        for key in pairs(draining) do
            if PolledDown(key) ~= false then any = true else draining[key] = nil end
        end
        if not any or waited > 3 then self:Teardown() end
    end)
end

function Handler:Teardown()
    self.draining = nil
    local catcher = self.catcher
    catcher:SetScript("OnUpdate", nil)
    if not InCombatLockdown() then
        if catcher.EnableGamePadButton then catcher:EnableGamePadButton(false) end
        catcher:EnableKeyboard(false)
    end
    SetPropagate(catcher, true)
    catcher:Hide()
end
