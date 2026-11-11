-- The debug strip: a machine-readable readout of DeckKit's debug log, for tools outside the game.
--
-- Addons can't write files or talk to other programs, but the screen can be read. While the strip
-- is on, a few rows of small colored cells along the top-left edge encode the debug log as data;
-- deck-setup/read-debug-strip.py takes a screenshot and decodes it back to text. Off by default
-- (nothing is drawn or logged then).
--
--   /deckkit debug on | off | clear
--   /deckkit debug keys            also log the name of every key the game receives (keys still work)
--   /deckkit debug binds <KEY...>  log what each key is bound to
--   DeckKit.Debug("text")          from any module: add a line (only kept while the strip is on)
--
-- Encoding: each CELL x CELL cell carries three 2-bit digits in its red, green and blue (0, 85,
-- 170, 255): coarse enough to survive the renderer's gamma (and the player's gamma setting). Cells
-- run left to right, ROWS rows of PER_ROW. The first 4 cells are a sync pattern, the next 4 a gray
-- ramp of the 4 levels (the reader matches cells to how the ramp actually came out); then 8 digits
-- of length, 8 of Fletcher-16 checksum, then the text, 4 digits per byte, newest lines kept when it
-- doesn't all fit.
local _, ns = ...

local CELL, PER_ROW, ROWS = 4, 300, 3
local LEVELS = 4
local SYNC = { { 3, 0, 0 }, { 0, 3, 0 }, { 0, 0, 3 }, { 3, 3, 3 } }
local CAPACITY = math.floor(((PER_ROW * ROWS - #SYNC - LEVELS) * 3 - 16) / 4) -- bytes of text that fit

local on, keysOn = false, false
local lines = {}
local strip, cells, dirty, pending

local function Strip()
    if strip then return strip end
    strip = CreateFrame("Frame", "DeckKitDebugStrip", UIParent)
    strip:SetFrameStrata("TOOLTIP")
    strip:SetFrameLevel(9999)
    strip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    strip:SetSize(PER_ROW * CELL, ROWS * CELL)
    -- One UI unit per screen pixel, whatever the UI scale, so cells land on exact pixels.
    local _, physical = GetPhysicalScreenSize()
    strip:SetIgnoreParentScale(true)
    strip:SetScale(768 / (physical or 768))
    cells = {}
    for i = 0, PER_ROW * ROWS - 1 do
        local t = strip:CreateTexture(nil, "OVERLAY")
        t:SetSize(CELL, CELL)
        t:SetPoint("TOPLEFT", (i % PER_ROW) * CELL, -math.floor(i / PER_ROW) * CELL)
        cells[i + 1] = t
    end
    return strip
end

local function Render()
    pending = false
    if not on then return end
    Strip()
    -- Newest lines that fit.
    local text = table.concat(lines, "\n")
    if #text > CAPACITY then text = text:sub(-CAPACITY) end
    -- Fletcher-16: notices swapped and cancelling errors, not just changed sums.
    local s1, s2 = 0, 0
    for i = 1, #text do
        s1 = (s1 + text:byte(i)) % 255
        s2 = (s2 + s1) % 255
    end
    local digits = {}
    local function push(v, count) -- count base-4 digits, most significant first
        for d = count - 1, 0, -1 do table.insert(digits, math.floor(v / 4 ^ d) % 4) end
    end
    push(#text, 8)
    push(s2 * 256 + s1, 8)
    for i = 1, #text do push(text:byte(i), 4) end
    local function paint(cell, r, g, b) cell:SetColorTexture(r * 85 / 255, g * 85 / 255, b * 85 / 255, 1) end
    local n = 0
    for _, c in ipairs(SYNC) do n = n + 1; paint(cells[n], c[1], c[2], c[3]) end
    for level = 0, LEVELS - 1 do n = n + 1; paint(cells[n], level, level, level) end
    local k = 1
    for i = n + 1, #cells do
        paint(cells[i], digits[k] or 0, digits[k + 1] or 0, digits[k + 2] or 0)
        k = k + 3
    end
    strip:Show()
end

local function Changed()
    if on and not pending then
        pending = true
        C_Timer.After(0.1, Render) -- many lines at once: one redraw
    end
end

-- Add a line to the debug log (ignored while the strip is off).
function ns.Debug(...)
    if not on then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(lines, string.format("%.1f %s", GetTime() % 10000, table.concat(parts, " ")))
    while #lines > 60 do table.remove(lines, 1) end
    Changed()
end

-- Key logging: a keyboard-enabled frame that passes every key on to the game.
local keyFrame
local function SetKeys(enable)
    keysOn = enable
    if not keyFrame then
        keyFrame = CreateFrame("Frame", "DeckKitDebugKeys", UIParent)
        keyFrame:SetScript("OnKeyDown", function(_, key) ns.Debug("key", key) end)
    end
    if not InCombatLockdown() then keyFrame:SetPropagateKeyboardInput(true) end
    keyFrame:EnableKeyboard(enable)
end

local function SetOn(enable)
    on = enable
    ns.db.debug = enable or nil -- stays on across reloads until switched off
    if enable then
        Strip()
        Changed()
    else
        if keysOn then SetKeys(false) end
        if strip then strip:Hide() end
    end
end

ns.AddCommand("debug", function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "on" then
        SetOn(true)
        ns.Debug("debug strip on")
        ns.Print("Debug strip on (top-left). /deckkit debug off to hide it.")
    elseif cmd == "off" then
        SetOn(false)
        ns.Print("Debug strip off.")
    elseif cmd == "clear" then
        wipe(lines)
        Changed()
    elseif cmd == "keys" then
        if not on then SetOn(true) end
        SetKeys(not keysOn)
        ns.Debug("key logging", keysOn and "on" or "off")
    elseif cmd == "binds" then
        if not on then SetOn(true) end
        for key in rest:upper():gmatch("%S+") do
            local action = GetBindingAction(key)
            ns.Debug("bind", key, (action and action ~= "") and action or "-")
        end
    else
        ns.Print("/deckkit debug on | off | clear | keys | binds <KEY...>")
    end
end, "debug strip for tools outside the game: on | off | clear | keys | binds <KEY...>")

ns.On("PLAYER_LOGIN", function()
    if ns.db.debug then SetOn(true); ns.Debug("debug strip on (kept from last session)") end
end)

ns.Settings.Add("DeckKit", ns.TITLE, {
    { type = "section", tab = "Tools", label = "DeckKit", order = 9 },
    { type = "toggle", label = "Debug strip",
      hint = "Colored cells top-left that tools outside the game can read. Leave off unless debugging.",
      get = function() return on end,
      set = function(enable) SetOn(enable) end },
})

-- Blocked / forbidden actions (the "...has been blocked from an action..." message): which addon and
-- which protected function, while the strip is on.
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(ns.On, event, function(addon, func) ns.Debug(event, tostring(addon), tostring(func)) end)
end

-- Blocked / forbidden protected calls: say which addon and which function, in chat, the moment it
-- happens (the taint log only reaches the disk when the game exits). Only while debug is on.
local function Blocked(event, addon, func)
    if not on then return end
    ns.Print(string.format("|cffff5555%s|r: %s called %s", event == "ADDON_ACTION_FORBIDDEN" and "forbidden"
        or "blocked", tostring(addon), tostring(func)))
end
ns.On("ADDON_ACTION_BLOCKED", function(...) Blocked("ADDON_ACTION_BLOCKED", ...) end)
ns.On("ADDON_ACTION_FORBIDDEN", function(...) Blocked("ADDON_ACTION_FORBIDDEN", ...) end)
