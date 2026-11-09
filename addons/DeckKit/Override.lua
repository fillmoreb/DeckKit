-- Shared gamepad button overrides: several modules can ask for the same button, and the core
-- decides which one gets it.
--
--   DeckKit.Override.Set("PAD3", "wand", { when = "[harm,nodead]", priority = 20,
--                                          macro = "/cast [harm,nodead] !Shoot" })
--   DeckKit.Override.Set("PAD3", "wand", nil)   -- give it back
--
-- when:     macro conditions under which this claim wants the button ("" = always)
-- priority: when several claims match, the highest wins
-- macro:    what the press runs
--
-- Each button has one secure button of ours and one secure state driver. The driver's state is
-- the winning claim's id (or "none"), worked out from the claims' conditions in secure code, so it
-- follows the target, combat and channeling even in combat. While a claim wins, the button gets a
-- priority override binding to our secure button; with no winner, the button is the game's own.
--
-- Claims can only be added, changed or removed out of combat (Set queues them until it ends).
-- While one of Forever's gamepad windows has the pad, no button is taken.
--
-- Square (PAD3) with L2 / R2 held is that crossbar layer's button. The secure button clicks the
-- game's crossbar button for that layer then, so the bars keep working.
--
-- Adapted from Improved Forever's Override.lua and WandShoot.lua
-- (MIT License, Copyright (c) 2026 markg).
local _, ns = ...

local Override = {}
ns.Override = Override

-- The game's crossbar button for a pad key, per layer: top (no trigger), left (L2), right (R2),
-- bottom (both). Only Square's is known so far: the first button of the right face group.
local CROSSBAR = { PAD3 = { group = "Right", button = "ActionButton1" } }
local BARS = { LT = "leftBar", RT = "rightBar", LTRT = "bottomBar" }

local function CrossbarClick(key, layer)
    local where = CROSSBAR[key]
    local main = _G.GamepadMainActionBarFrame
    local bars = where and main and main.PageUnit and main.PageUnit.actionBars
    local bar = bars and bars[BARS[layer]]
    local group = bar and bar[where.group]
    local button = group and group[where.button]
    local name = button and button.GetName and button:GetName()
    return name and ("/click " .. name .. " LeftButton true") or nil
end

local function PadIndex(key)
    local index = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(key)
    return index and index + 1 or nil
end

-- True unless one of Forever's gamepad windows has the pad (always true in combat).
local function InGame()
    if InCombatLockdown() then return true end
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if not (manager and manager.IsOnlyCoreBindingSetActive) then return true end
    return manager:IsOnlyCoreBindingSetActive() and true or false
end

local keys = {} -- key -> { claims = { id -> claim }, button, driver, waitingForBars }
local pending = false

local function Key(key)
    local k = keys[key]
    if k then return k end
    local safe = key:gsub("%W", "_")

    local button = CreateFrame("Button", "DeckKitOverride" .. safe, UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
    button:SetAttribute("type", "macro")
    -- Both edges: a binding's click doesn't reach a button registered for only one.
    -- dk-down says which edge acts (the game's ActionButtonUseKeyDown).
    button:RegisterForClicks("AnyDown", "AnyUp")
    SecureHandlerWrapScript(button, "OnClick", button, [[
        if not down ~= not self:GetAttribute("dk-down") then return false end
        local state = GetGamePadState()
        local pad = state and state.buttons
        local lt, rt = self:GetAttribute("dk-lt"), self:GetAttribute("dk-rt")
        if pad and (lt or rt) then
            local layer = ((lt and pad[lt]) and "LT" or "") .. ((rt and pad[rt]) and "RT" or "")
            local held = layer ~= "" and self:GetAttribute("dk-layer-" .. layer)
            if held then
                self:SetAttribute("macrotext", held)
                return
            end
        end
        local active = self:GetAttribute("dk-active")
        self:SetAttribute("macrotext", active and self:GetAttribute("dk-macro-" .. active))
        if not self:GetAttribute("macrotext") then return false end
    ]])

    local driver = CreateFrame("Frame", "DeckKitOverrideDriver" .. safe, UIParent, "SecureHandlerStateTemplate")
    SecureHandlerSetFrameRef(driver, "button", button)
    driver:SetAttribute("dk-key", key)
    driver:SetAttribute("dk-eval", [[
        self:ClearBindings()
        local button = self:GetFrameRef("button")
        local state = self:GetAttribute("state-claim")
        if self:GetAttribute("dk-on") and state and state ~= "none" then
            button:SetAttribute("dk-active", state)
            self:SetBindingClick(true, self:GetAttribute("dk-key"), button:GetName(), "LeftButton")
        else
            button:SetAttribute("dk-active", nil)
        end
    ]])
    driver:SetAttribute("_onstate-claim", [[ self:RunAttribute("dk-eval") ]])

    k = { claims = {}, button = button, driver = driver }
    keys[key] = k
    return k
end

-- Out of combat: rebuild a key's driver from its claims.
local function Rebuild(key)
    local k = Key(key)
    local list = {}
    for id, claim in pairs(k.claims) do list[#list + 1] = { id = id, claim = claim } end
    table.sort(list, function(a, b)
        if a.claim.priority ~= b.claim.priority then return a.claim.priority > b.claim.priority end
        return a.id < b.id
    end)

    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local onDown = get and get("ActionButtonUseKeyDown") ~= "0"
    local b = k.button
    b:SetAttribute("dk-down", onDown)
    b:SetAttribute("useOnKeyDown", onDown)
    k.waitingForBars = false
    if CROSSBAR[key] then
        b:SetAttribute("dk-lt", PadIndex("PADLTRIGGER"))
        b:SetAttribute("dk-rt", PadIndex("PADRTRIGGER"))
        for layer in pairs(BARS) do
            local click = CrossbarClick(key, layer)
            b:SetAttribute("dk-layer-" .. layer, click)
            if not click and #list > 0 then k.waitingForBars = true end
        end
    end

    local clauses = {}
    for _, entry in ipairs(list) do
        b:SetAttribute("dk-macro-" .. entry.id, entry.claim.macro)
        clauses[#clauses + 1] = (entry.claim.when or "") .. " " .. entry.id
    end
    clauses[#clauses + 1] = "none"
    UnregisterStateDriver(k.driver, "claim")
    RegisterStateDriver(k.driver, "claim", table.concat(clauses, "; "))
    k.driver:SetAttribute("dk-on", (#list > 0 and InGame()) or nil)
    SecureHandlerExecute(k.driver, [[ self:RunAttribute("dk-eval") ]])
end

local function RebuildAll()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    for key in pairs(keys) do Rebuild(key) end
end

-- Claim a pad button (opts as at the top), or give it back (opts nil). Safe to call often:
-- nothing is rebuilt when the claim didn't change.
function Override.Set(key, id, opts)
    local k = Key(key)
    local old = k.claims[id]
    if opts then
        opts = { when = opts.when or "", priority = opts.priority or 0, macro = opts.macro }
        if old and old.when == opts.when and old.priority == opts.priority and old.macro == opts.macro then
            return
        end
    elseif not old then
        return
    end
    k.claims[id] = opts
    if InCombatLockdown() then
        pending = true
    else
        Rebuild(key)
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if pending then RebuildAll() end
end)
ns.On("CVAR_UPDATE", RebuildAll)

-- Re-check when the pad moves between the game and a gamepad window, and retry until the game's
-- crossbar is built after login.
local lastInGame, wait, retry = nil, 0, 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
    wait = wait - elapsed
    if wait > 0 or InCombatLockdown() then return end
    wait = 0.1
    local now = InGame()
    if now ~= lastInGame then
        lastInGame = now
        RebuildAll()
        return
    end
    retry = retry + 0.1
    if retry >= 1 then
        retry = 0
        for key, k in pairs(keys) do
            if k.waitingForBars then Rebuild(key) end
        end
    end
end)
