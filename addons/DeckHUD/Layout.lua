-- DeckHUD layout: reads and changes Edit Mode layouts through C_EditMode, the way
-- LibEditModeOverride does. Changes are saved to the layout (account-wide, on Blizzard's servers)
-- and take effect cleanly after a /reload; nothing here fights Edit Mode while you play.
--
-- Every change first saves a backup of the whole layout as an Edit Mode import string in
-- DeckHUDDB.layoutBackups; /deckkit layout restore puts the newest one back.
--
--   /deckkit layout crossbar <height>   the gamepad action bar's bottom, in pixels from the bottom
--   /deckkit layout party               raid-style party frames in a row under your frame and the target's
--   /deckkit layout raid <left> <top>   the raid frames' top left corner, in pixels from the screen's
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

------------------------------------------------------------------------
-- Party frames in a row: raid-style, side by side, filling the gap between the inner edges of
-- your frame and the target frame, just under them. Measured from where those frames are when you
-- ask (the target frame has its place even with no target), so it follows any layout.
------------------------------------------------------------------------

local UF = Enum and Enum.EditModeUnitFrameSetting or {}
local PARTY = Enum and Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Party
local PARTY_SIZE = 5            -- raid-style party frames include you
local MIN_W, MAX_W, STEP = 72, 144, 2  -- Edit Mode's frame width slider (stored as pixels above 72)
local GAP = 4                   -- between the bottom of the two frames and the row
local PAD_X = 2                 -- PartyFrame's left padding before the raid-style group (no border)
local TITLE_H = 14              -- the group's title, above the first member, when it can't be measured

-- A region's rectangle in UIParent's units: left, right, bottom, top.
local function Rect(region)
    local l, b, w, h = region:GetRect()
    if not l then return end
    local k = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * k, (l + w) * k, b * k, (b + h) * k
end

-- The visible art of a unit frame (its frame has invisible padding around it), else the frame.
local function Art(frame, container)
    local c = frame[container]
    return (c and c.FrameTexture) or frame
end

local function SetSetting(sys, setting, value)
    for _, st in ipairs(sys.settings) do
        if st.setting == setting then st.value = value; return end
    end
    table.insert(sys.settings, { setting = setting, value = value })
end

function Layout.PartyRow()
    if InCombatLockdown() then return false, "not in combat" end
    if not (PARTY and UF.FrameWidth) then return false, "this client has no party frames in Edit Mode" end
    local _, pRight, pBottom = Rect(Art(PlayerFrame, "PlayerFrameContainer"))
    local tLeft, _, tBottom = Rect(Art(TargetFrame, "TargetFrameContainer"))
    if not (pRight and tLeft) then return false, "couldn't find your frame and the target frame" end
    local span = tLeft - pRight
    if span < PARTY_SIZE * MIN_W then
        return false, string.format("only %d px between your frame and the target frame (%d needed)", span, PARTY_SIZE * MIN_W)
    end
    local width = math.min(MAX_W, math.floor(span / PARTY_SIZE / STEP) * STEP)
    local spare = span - PARTY_SIZE * width -- split evenly on both sides
    local titleH = (CompactPartyFrame and CompactPartyFrame.title and CompactPartyFrame.title:GetHeight()) or TITLE_H
    local top = math.min(pBottom, tBottom) - GAP

    local info, layout = Layout.Active()
    if not layout then return false, "your active Edit Mode layout is a preset; pick or copy a custom one" end
    local sys = FindSystem(layout, SYSTEMS.UnitFrame, PARTY)
    if not sys then return false, "party frames aren't in your layout" end
    if not Backup(layout) then return false, "couldn't back up the layout first" end
    SetSetting(sys, UF.UseRaidStylePartyFrames, 1)
    SetSetting(sys, UF.UseHorizontalGroups, 1)
    SetSetting(sys, UF.FrameWidth, width - MIN_W)
    -- The first member sits PAD_X right of PartyFrame's left edge and the title's height below its top.
    local a = sys.anchorInfo
    a.point, a.relativeTo, a.relativePoint = "TOPLEFT", "UIParent", "BOTTOMLEFT"
    a.offsetX = math.floor(pRight + spare / 2 - PAD_X + 0.5)
    a.offsetY = math.floor(top + titleH + 0.5)
    sys.isInDefaultPosition = false
    C_EditMode.SaveLayouts(info)
    ns.Debug("party row", "span", span, "width", width, "x", a.offsetX, "y", a.offsetY, "title", titleH)
    return true, width
end

-- Forever only lets an addon reload from a key press or a typed command, never from a timer: so
-- this runs in the press's own call (menu actions that use it are keepOpen, which runs them
-- straight from the press).
------------------------------------------------------------------------
-- Raid frames in the top left corner: EDGE from the screen's left edge, and EDGE under any status
-- bars (XP, reputation...) showing along the top of the screen when you ask.
------------------------------------------------------------------------

local RAID_EDGE = 4

function Layout.RaidTopLeft()
    local raid = Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Raid
    if not raid then return false, "this client has no raid frames in Edit Mode" end
    local screenTop = UIParent:GetTop()
    local below = 0 -- how far down from the top the bars reach
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local bar = _G[name]
        if bar and bar:IsVisible() and bar:GetTop() and screenTop - bar:GetTop() < 2 + below then
            below = math.max(below, screenTop - bar:GetBottom())
        end
    end
    local top = math.floor(below + RAID_EDGE + 0.5)
    local ok, err = Layout.SetAnchor(SYSTEMS.UnitFrame, raid, { point = "TOPLEFT", relativeTo = "UIParent",
        relativePoint = "TOPLEFT", offsetX = RAID_EDGE, offsetY = -top })
    if not ok then return false, err end
    return true, top
end

------------------------------------------------------------------------
-- The focus frame centered in the gap between your frame and the target frame, at their height.
-- Measured from what's visible: the focus frame's border (Focus.lua's portrait-less one, or
-- Blizzard's), and the two frames' art, wherever they are when you ask.
------------------------------------------------------------------------

function Layout.FocusCenter()
    local focus = Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Focus
    if not focus then return false, "this client has no focus frame in Edit Mode" end
    local _, pRight, pBottom, pTop = Rect(Art(PlayerFrame, "PlayerFrameContainer"))
    local tLeft = Rect(Art(TargetFrame, "TargetFrameContainer"))
    local aLeft, aRight, aBottom, aTop = Rect(ns.FocusVisual and ns.FocusVisual() or Art(FocusFrame, "TargetFrameContainer"))
    local fLeft, fRight, fBottom, fTop = Rect(FocusFrame)
    if not (pRight and tLeft and aLeft and fLeft) then return false, "couldn't find the unit frames" end
    -- Where the focus frame's center goes so that its border's center lands mid-gap, level with
    -- the middle of your frame's art.
    local cx = (pRight + tLeft) / 2 - ((aLeft + aRight) / 2 - (fLeft + fRight) / 2)
    local cy = (pBottom + pTop) / 2 - ((aBottom + aTop) / 2 - (fBottom + fTop) / 2)
    -- Edit Mode stores offsets in screen (UIParent) units and divides by the frame's own scale when
    -- it places it (the focus frame is drawn at 0.75), so these are plain screen positions.
    local info, layout = Layout.Active()
    if not layout then return false, "your active Edit Mode layout is a preset; pick or copy a custom one" end
    local sys = FindSystem(layout, SYSTEMS.UnitFrame, focus)
    if not sys then return false, "the focus frame isn't in your layout" end
    if not Backup(layout) then return false, "couldn't back up the layout first" end
    local a = sys.anchorInfo
    a.point, a.relativeTo, a.relativePoint = "CENTER", "UIParent", "BOTTOMLEFT"
    a.offsetX, a.offsetY = math.floor(cx + 0.5), math.floor(cy + 0.5)
    sys.isInDefaultPosition = false
    -- Focus.lua's "Name and health" look needs the larger frame: the small one shows no buffs.
    -- (Focus.lua keeps the look the same size on screen either way.)
    if ns.db.focusStyle == "compact" and UF.UseLargerFrame then SetSetting(sys, UF.UseLargerFrame, 1) end
    C_EditMode.SaveLayouts(info)
    return true
end

local function ReloadSoon(what)
    ns.Print(what .. " Reloading the interface...")
    ReloadUI()
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
    elseif cmd == "raid" then
        local x, y = rest:match("^(%-?%d+)%s+(%-?%d+)$")
        local raid = Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Raid
        if not (x and raid) then return ns.Print("/deckkit layout raid <px from the left> <px from the top>") end
        local ok, err = Layout.SetAnchor(SYSTEMS.UnitFrame, raid, { point = "TOPLEFT", relativeTo = "UIParent",
            relativePoint = "TOPLEFT", offsetX = tonumber(x), offsetY = -tonumber(y) })
        ns.Print(ok and ("Raid frames moved to " .. x .. ", " .. y .. " (layout backed up). /reload to see it.") or ("Not changed: " .. err .. "."))
    elseif cmd == "focus" then
        local ok, info = Layout.FocusCenter()
        if ok then ReloadSoon("Focus frame centered (layout backed up).") else ns.Print("Not changed: " .. info .. ".") end
    elseif cmd == "party" then
        local ok, info = Layout.PartyRow()
        if ok then ReloadSoon("Party frames lined up (" .. info .. " px wide each, layout backed up).")
        else ns.Print("Not changed: " .. info .. ".") end
    elseif cmd == "restore" then
        local ok, info = Layout.Restore()
        ns.Print(ok and ("Restored the layout backup from " .. info .. ". /reload to see it.") or ("Not restored: " .. info .. "."))
    elseif cmd == "backups" then
        local list = ns.db.layoutBackups or {}
        if #list == 0 then return ns.Print("No layout backups yet.") end
        for i, b in ipairs(list) do ns.Print(i .. ". " .. b.when .. "  " .. tostring(b.name)) end
    else
        ns.Print("/deckkit layout suggested  |  party  |  focus  |  raid <left> <top>  |  crossbar <px from bottom>  |  restore  |  backups")
    end
end, "Edit Mode layout: suggested, party, focus, raid <left> <top>, crossbar <height>, restore, backups")

ns.AddSettings({
    { type = "section", tab = "Healing", label = "Party, raid and focus frames", order = 2 },
    { type = "action", label = "Line up party frames", keepOpen = true,
      hint = "Raid-style party frames in a row, filling the gap between your frame and the target frame, just "
          .. "under them. Backs up your Edit Mode layout, then reloads. \"Undo the last layout change\" "
          .. "(Screen tab) puts it back.",
      run = function()
          local ok, info = Layout.PartyRow()
          if ok then ReloadSoon("Party frames lined up.") else ns.Print("Not changed: " .. info .. ".") end
      end },
    { type = "action", label = "Center the focus frame", keepOpen = true,
      hint = "The focus frame in the middle of the gap between your frame and the target frame, at their "
          .. "height (with the Name and health look, it also turns on Use Larger Frame, which the focus's "
          .. "buffs need). Backs up your Edit Mode layout, then reloads.",
      run = function()
          local ok, info = Layout.FocusCenter()
          if ok then ReloadSoon("Focus frame centered.") else ns.Print("Not changed: " .. info .. ".") end
      end },
    { type = "action", label = "Line up raid frames", keepOpen = true,
      hint = "Raid frames in the top left corner: just off the screen's edge and just under the XP and "
          .. "reputation bars showing now. Backs up your Edit Mode layout, then reloads.",
      run = function()
          local ok, info = Layout.RaidTopLeft()
          if ok then ReloadSoon("Raid frames lined up.") else ns.Print("Not changed: " .. info .. ".") end
      end },
})

-- On the Suggested settings page (Suggested.lua makes the page; these go after its rows).
Layout.MenuItems = {
    { type = "action", label = "Apply suggested layout", keepOpen = true,
      hint = "XP bar along the top, crossbar near the bottom. Backs up your Edit Mode layout, then reloads.",
      run = function()
          local ok, info = Layout.ApplySuggested()
          if ok then ReloadSoon("Suggested layout applied.") else ns.Print("Not changed: " .. info .. ".") end
      end },
    { type = "action", label = "Undo the last layout change", keepOpen = true,
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
