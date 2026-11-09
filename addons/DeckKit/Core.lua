-- DeckKit: the shared core for the DeckKit addons (controller-first addons for WoW: Forever).
--
--   Core.lua    the DeckKit global, modules, events, sticks, /deckkit and its commands
--   Input.lua   controller capture for windows (DeckKit.Input)
--   Window.lua  the window look and sounds (DeckKit.Window)
--   Override.lua  shared pad button overrides, e.g. X for wand shoot and fishing (DeckKit.Override)
--
-- Each feature addon lists "## Dependencies: DeckKit" and starts with
--   DeckKit.NewModule(ns, "WayPad", "|cff4fc3f7WayPad|r")
-- which gives its namespace Print, On, Input, Window, Override and AddCommand.
local ADDON, ns = ...

DeckKit = ns

ns.TITLE = "|cffffb347DeckKit|r"

-- Modules put their bindings in a DeckKit section of the Key Bindings screen
-- (category="BINDING_HEADER_DECKKIT" in Bindings.xml), each under its own header.
BINDING_HEADER_DECKKIT = "DeckKit"

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
    addonNS.AddCommand = ns.AddCommand
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

SLASH_DECKKIT1 = "/deckkit"
SLASH_DECKKIT2 = "/dkit"
SlashCmdList.DECKKIT = function(msg)
    local name, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    local command = commands[name:lower()]
    if command then
        command.fn(rest)
        return
    end
    local names = {}
    for _, m in ipairs(modules) do
        table.insert(names, m.title .. " " .. m.version)
    end
    ns.Print("version " .. ns.version .. ". Modules: "
        .. (#names > 0 and table.concat(names, ", ") or "none loaded") .. ".")
    for _, n in ipairs(commandOrder) do
        DEFAULT_CHAT_FRAME:AddMessage("  /deckkit " .. n .. (commands[n].help and (": " .. commands[n].help) or ""))
    end
end
