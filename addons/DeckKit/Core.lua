-- DeckKit: the shared core for the DeckKit addons (controller-first addons for WoW: Forever).
--
--   Core.lua    the DeckKit global, modules, events, sticks, /deckkit and its commands
--   Input.lua   controller capture for windows (DeckKit.Input)
--   Window.lua  the window look and sounds (DeckKit.Window)
--   Override.lua  shared pad button overrides, e.g. X for wand shoot and fishing (DeckKit.Override)
--   Settings.lua  the settings registry modules add their options to (ns.AddSettings)
--   Menu.lua      the DeckKit menu: double-tap Menu (three lines) or /deckkit
--   Paddles.lua   paddle chords: the two peek buttons held, held together (dictation) or double-tapped
--   Debug.lua     ns.Debug / ns.Logger: forward to DeckDev (the dev addon) when it's installed
--
-- Each feature addon lists "## Dependencies: DeckKit" and starts with
--   DeckKit.NewModule(ns, "WayPad", "|cff4fc3f7WayPad|r")
-- which gives its namespace Print, On, Input, Window, Override, Paddles, AddCommand, AddSettings,
-- Debug (a line in DeckDev's log, if DeckDev is installed) and Notice (a short message mid-screen).
local ADDON, ns = ...

DeckKit = ns

ns.TITLE = "|cffffb347DeckKit|r"

-- Modules put their bindings in a DeckKit section of the Key Bindings screen
-- (category="BINDING_HEADER_DECKKIT" in Bindings.xml), each under its own header.
BINDING_HEADER_DECKKIT = "DeckKit"
BINDING_NAME_DECKKIT_RELOAD = "Reload UI"

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = GetMetadata and GetMetadata(ADDON, "Version") or "?"

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

-- An event bus: bus.On(event, fn) calls fn(...) whenever the event fires. Each module gets its
-- own, so an error in one addon's handler can't stop another addon's handlers running.
local function NewBus()
    local frame = CreateFrame("Frame")
    local listeners = {}
    frame:SetScript("OnEvent", function(_, event, ...)
        for _, fn in ipairs(listeners[event]) do fn(...) end
    end)
    return function(event, fn)
        if not listeners[event] then
            listeners[event] = {}
            frame:RegisterEvent(event)
        end
        table.insert(listeners[event], fn)
    end
end

ns.On = NewBus()

ns.db = {}
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    DeckKitDB = DeckKitDB or {}
    ns.db = DeckKitDB
end)

-- Reload UI starts out on F6 (if F6 is free), once: rebinding or clearing it sticks.
-- It lets tools outside the game reload it with a key press.
ns.On("PLAYER_LOGIN", function()
    if ns.db.reloadKeySet then return end
    ns.db.reloadKeySet = true
    if not GetBindingKey("DECKKIT_RELOAD") and (GetBindingAction("F6") or "") == "" then
        SetBinding("F6", "DECKKIT_RELOAD")
        SaveBindings(GetCurrentBindingSet())
    end
end)

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ns.TITLE .. ": " .. msg)
end

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------

local modules = {}

-- Call at the top of a feature addon's first file. name is the addon's folder name;
-- title is how it's shown in chat (usually colored).
function ns.NewModule(addonNS, name, title)
    addonNS.TITLE = title
    addonNS.Print = function(msg) DEFAULT_CHAT_FRAME:AddMessage(title .. ": " .. msg) end
    addonNS.On = NewBus()
    addonNS.Input = ns.Input
    addonNS.Window = ns.Window
    addonNS.Override = ns.Override
    addonNS.Paddles = ns.Paddles
    addonNS.Debug = ns.Logger(name)
    addonNS.Notice = function(...) if ns.Notice then ns.Notice(...) end end
    addonNS.AddCommand = ns.AddCommand
    addonNS.AddSettings = function(items) ns.Settings.Add(name, title, items) end
    table.insert(modules, { name = name, title = title,
        version = GetMetadata and GetMetadata(name, "Version") or "?" })
    return addonNS
end

------------------------------------------------------------------------
-- Sticks
------------------------------------------------------------------------

-- While frame is shown it takes the gamepad sticks: the camera and character stay still.
-- onRight(y, x) gets the right stick (-1..1, up is positive). Call it out of combat (at login),
-- the same as building any frame that takes input. Returns false if the client can't do it.
function ns.TakeSticks(frame, onRight)
    if not frame.EnableGamePadStick then return false end
    pcall(frame.EnableGamePadStick, frame, true)
    frame:SetScript("OnGamePadStick", function(_, stick, x, y)
        if stick == "Right" or stick == "Camera" then onRight(y or 0, x or 0) end
    end)
    return true
end

------------------------------------------------------------------------
-- /deckkit
------------------------------------------------------------------------

local commands, commandOrder = {}, {}

-- /deckkit <name> [args] runs fn(args). Modules use this instead of a slash command of their own.
function ns.AddCommand(name, fn, help)
    name = name:lower()
    if not commands[name] then table.insert(commandOrder, name) end
    commands[name] = { fn = fn, help = help }
end

-- WoW's taint log (Logs/taint.log): what an addon touched when the game says "Interface action
-- failed because of an AddOn". Off normally; on while hunting one down.
ns.AddCommand("taint", function(arg)
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    arg = strtrim(arg or ""):lower()
    if arg == "on" or arg == "off" then set("taintLog", arg == "on" and "1" or "0") end
    ns.Print("taint log " .. (tostring(get("taintLog")) ~= "0" and "on (Logs/taint.log)" or "off")
        .. ". /deckkit taint on|off")
end, "WoW's taint log for tracking down \"Interface action failed\": on | off")

SLASH_DECKKIT1 = "/deckkit"
SLASH_DECKKIT2 = "/dkit"
SlashCmdList.DECKKIT = function(msg)
    local name, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    local command = commands[name:lower()]
    if command then
        command.fn(rest)
        return
    end
    if name == "" then
        ns.Menu.Toggle()
        return
    end
    local names = {}
    for _, m in ipairs(modules) do
        table.insert(names, m.title .. " " .. m.version)
    end
    ns.Print("version " .. ns.version .. ". Modules: "
        .. (#names > 0 and table.concat(names, ", ") or "none loaded") .. ".")
    DEFAULT_CHAT_FRAME:AddMessage("  /deckkit: the DeckKit menu (or press Menu twice quickly)")
    for _, n in ipairs(commandOrder) do
        DEFAULT_CHAT_FRAME:AddMessage("  /deckkit " .. n .. (commands[n].help and (": " .. commands[n].help) or ""))
    end
end
