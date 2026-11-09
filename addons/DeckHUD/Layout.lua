-- DeckHUD layout: reads and changes Edit Mode layouts through C_EditMode, the way
-- LibEditModeOverride does. Changes are saved to the layout (account-wide, on Blizzard's servers)
-- and take effect cleanly after a /reload; nothing here fights Edit Mode while you play.
--
-- Every change first saves a backup of the whole layout as an Edit Mode import string in
-- DeckHUDDB.layoutBackups; /deckkit layout restore puts the newest one back.
--
--   /deckkit layout crossbar <height>   the gamepad action bar's bottom, in pixels from the bottom
--   /deckkit layout restore             the newest backup, back into the active layout
--   /deckkit layout backups             list them
--
-- (Development, for now) the active layout's systems are recorded in DeckHUDDB.layoutDump at login.
local _, ns = ...

local Layout = {}
ns.Layout = Layout

-- Enum.EditModeSystem number -> name, for readable dumps.
local function SystemNames()
    local names = {}
    for name, id in pairs(Enum and Enum.EditModeSystem or {}) do names[id] = name end
    return names
end

local function PresetCount()
    local mgr = _G.EditModePresetLayoutManager
    if mgr and mgr.GetCopyOfPresetLayouts then
        local ok, presets = pcall(mgr.GetCopyOfPresetLayouts, mgr)
        if ok and type(presets) == "table" then return #presets end
    end
    return 0
end

-- The layouts table from C_EditMode, the active layout (a table inside it, or nil for a preset)
-- and its name.
function Layout.Active()
    local info = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    if not info then return end
    local presets = PresetCount()
    local layout = info.layouts[info.activeLayout - presets]
    return info, layout, presets
end

function Layout.Dump()
    local out = {}
    local info, layout, presets = Layout.Active()
    if not info then return { "no C_EditMode" } end
    table.insert(out, string.format("activeLayout=%s presets=%d saved=%d", tostring(info.activeLayout), presets, #info.layouts))
    for i, l in ipairs(info.layouts) do
        table.insert(out, string.format("layout %d: %s type=%s systems=%d", i, tostring(l.layoutName), tostring(l.layoutType), #l.systems))
    end
    if not layout then
        table.insert(out, "active layout is a preset")
        return out
    end
    local names = SystemNames()
    for _, sys in ipairs(layout.systems) do
        local a = sys.anchorInfo or {}
        local settings = {}
        for _, s in ipairs(sys.settings or {}) do table.insert(settings, s.setting .. "=" .. tostring(s.value)) end
        table.insert(out, string.format("system %s (%s) idx=%s default=%s anchor %s %s %s %.1f %.1f  settings: %s",
            tostring(sys.system), tostring(names[sys.system]), tostring(sys.systemIndex), tostring(sys.isInDefaultPosition),
            tostring(a.point), tostring(a.relativeTo), tostring(a.relativePoint), a.offsetX or 0, a.offsetY or 0,
            table.concat(settings, " ")))
    end
    return out
end

local function FindSystem(layout, system, index)
    for _, sys in ipairs(layout.systems) do
        if sys.system == system and (index == nil or sys.systemIndex == index) then return sys end
    end
end

local function Backup(layout)
    if not (C_EditMode.ConvertLayoutInfoToString) then return false end
    local ok, str = pcall(C_EditMode.ConvertLayoutInfoToString, layout)
    if not ok or type(str) ~= "string" then return false end
    ns.db.layoutBackups = ns.db.layoutBackups or {}
    table.insert(ns.db.layoutBackups, { when = date("%Y-%m-%d %H:%M"), name = layout.layoutName, layout = str })
    while #ns.db.layoutBackups > 10 do table.remove(ns.db.layoutBackups, 1) end
    return true
end

-- Change one system's anchor in the active layout and save. fields: point, relativeTo,
-- relativePoint, offsetX, offsetY (any of them). Takes effect after a /reload.
function Layout.SetAnchor(system, index, fields)
    if InCombatLockdown() then return false, "not in combat" end
    local info, layout = Layout.Active()
    if not layout then return false, "your active Edit Mode layout is a preset; pick or copy a custom one" end
    local sys = FindSystem(layout, system, index)
    if not sys then return false, "that frame isn't in your layout" end
    if not Backup(layout) then return false, "couldn't back up the layout first" end
    for k, v in pairs(fields) do sys.anchorInfo[k] = v end
    sys.isInDefaultPosition = false -- or Edit Mode puts it back at its default spot
    C_EditMode.SaveLayouts(info)
    return true
end

function Layout.Restore()
    if InCombatLockdown() then return false, "not in combat" end
    local backup = ns.db.layoutBackups and ns.db.layoutBackups[#ns.db.layoutBackups]
    if not backup then return false, "no backups yet" end
    local info, layout = Layout.Active()
    if not layout then return false, "your active Edit Mode layout is a preset" end
    local ok, restored = pcall(C_EditMode.ConvertStringToLayoutInfo, backup.layout)
    if not ok or type(restored) ~= "table" or type(restored.systems) ~= "table" then return false, "the backup didn't read back" end
    layout.systems = restored.systems
    C_EditMode.SaveLayouts(info)
    table.remove(ns.db.layoutBackups)
    return true, backup.when
end

local SYSTEMS = Enum and Enum.EditModeSystem or {}
local GAMEPAD_BAR = SYSTEMS.GamepadMainActionBar

-- The suggested layout for the Deck: the XP bar (and the bar that stacks with it, e.g.
-- reputation) along the top edge, which frees the bottom so the crossbar can sit low.
local SUGGESTED = {
    { system = SYSTEMS.StatusTrackingBar, index = 1,
      anchor = { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 0, offsetY = 0 } },
    { system = SYSTEMS.StatusTrackingBar, index = 2,
      anchor = { point = "TOP", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 0, offsetY = -17 } },
    { system = GAMEPAD_BAR,
      anchor = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 6 } },
}

-- All the suggested positions in one change (one backup). Takes effect after a reload.
function Layout.ApplySuggested()
    if InCombatLockdown() then return false, "not in combat" end
    local info, layout = Layout.Active()
    if not layout then return false, "your active Edit Mode layout is a preset; pick or copy a custom one" end
    if not Backup(layout) then return false, "couldn't back up the layout first" end
    local n = 0
    for _, s in ipairs(SUGGESTED) do
        local sys = s.system and FindSystem(layout, s.system, s.index)
        if sys then
            for k, v in pairs(s.anchor) do sys.anchorInfo[k] = v end
            sys.isInDefaultPosition = false
            n = n + 1
        end
    end
    C_EditMode.SaveLayouts(info)
    return true, n
end

local function ReloadSoon(what)
    ns.Print(what .. " Reloading the interface...")
    C_Timer.After(1, function() if not pcall(ReloadUI) then ns.Print("Reload (F6 or /reload) to see it.") end end)
end

ns.AddCommand("layout", function(arg)
    local cmd, rest = strtrim(arg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "crossbar" and tonumber(rest) then
        if not GAMEPAD_BAR then return ns.Print("This client has no gamepad action bar in Edit Mode.") end
        local ok, err = Layout.SetAnchor(GAMEPAD_BAR, nil, { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetY = tonumber(rest) })
        ns.Print(ok and ("Crossbar moved to " .. rest .. " px from the bottom (layout backed up). /reload to see it.") or ("Not changed: " .. err .. "."))
    elseif cmd == "suggested" then
        local ok, info = Layout.ApplySuggested()
        if ok then ReloadSoon("Suggested layout applied (" .. info .. " frames, layout backed up).")
        else ns.Print("Not changed: " .. info .. ".") end
    elseif cmd == "restore" then
        local ok, info = Layout.Restore()
        ns.Print(ok and ("Restored the layout backup from " .. info .. ". /reload to see it.") or ("Not restored: " .. info .. "."))
    elseif cmd == "backups" then
        local list = ns.db.layoutBackups or {}
        if #list == 0 then return ns.Print("No layout backups yet.") end
        for i, b in ipairs(list) do ns.Print(i .. ". " .. b.when .. "  " .. tostring(b.name)) end
    else
        ns.Print("/deckkit layout suggested  |  crossbar <px from bottom>  |  restore  |  backups")
    end
end, "Edit Mode layout: suggested, crossbar <height>, restore, backups")

-- On the Suggested settings page (Suggested.lua makes the page; these go after its rows).
Layout.MenuItems = {
    { type = "action", label = "Apply suggested layout",
      hint = "XP bar along the top, crossbar near the bottom. Backs up your Edit Mode layout, then reloads.",
      run = function()
          local ok, info = Layout.ApplySuggested()
          if ok then ReloadSoon("Suggested layout applied.") else ns.Print("Not changed: " .. info .. ".") end
      end },
    { type = "action", label = "Undo the last layout change",
      hint = "Puts back your Edit Mode layout from before DeckKit's last change, then reloads.",
      run = function()
          local ok, info = Layout.Restore()
          if ok then ReloadSoon("Layout from " .. info .. " restored.") else ns.Print("Not restored: " .. info .. ".") end
      end },
}

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(3, function()
        local ok, dump = pcall(Layout.Dump)
        ns.db.layoutDump = ok and dump or { "dump failed: " .. tostring(dump) }
    end)
end)
