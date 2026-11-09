-- DeckAngler: controller fishing.
--
--   Tally.lua      the session tally panel, missed-catch chime, idle reminder, /deckkit fish
--   OneButton.lua  with a pole equipped, Square (X) casts Fishing
--
-- The tally counts what you catch while a fishing pole is equipped.
-- A session starts when a fishing pole goes into the main hand and ends when
-- anything else replaces it. Only items actually looted from fishing loot
-- windows are counted. The panel shows the running tally; when the session
-- ends, a summary goes to chat and the final tally stays up briefly.
--
-- /deckkit fish          show the last session's tally again
-- /deckkit fish button   one-button fishing on X: /deckkit fish button on|off
-- /deckkit fish reset    move the panel back under the controller legend
-- /deckkit fish chime    play the missed-catch chime; /deckkit fish chime on|off
-- /deckkit fish alert    list idle alert sounds; /deckkit fish alert <name|number> picks and plays one (default: double)
-- /deckkit fish idle     play the idle sound; /deckkit fish idle <seconds>|on|off (default 60s)
-- (drag the panel with the mouse to move it)

local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cff3fd0c0DeckAngler|r")
local MAIN_HAND = 16
local LINGER = 20      -- seconds the final tally stays up after a session
local MAX_ROWS = 14
local ROW_H = 18
local WIDTH = 230

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local LOOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local FISHING_POLE_SUBCLASS = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20

local KNOWN_POLES = {
    [6256] = true, [6365] = true, [6366] = true, [6367] = true,
    [12225] = true, [19022] = true, [19970] = true, [25978] = true,
    [44050] = true, [45858] = true,
}

local db          -- DeckAnglerDB (per character)
local session     -- { started, catches, items = { [itemID] = { name, icon, quality, count } } }
local pending     -- loot slot -> item info, for the fishing loot window that's open
local ticker, hideTimer

local out = ns.Print

---------------------------------------------------------------------------
-- Pole detection (instant item info needs no item cache)

local function PoleEquipped()
    local id = GetInventoryItemID("player", MAIN_HAND)
    if not id then return false end
    if KNOWN_POLES[id] then return true end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE_SUBCLASS
end
ns.PoleEquipped = PoleEquipped

---------------------------------------------------------------------------
-- Display

local panel = CreateFrame("Frame", "DeckAnglerPanel", UIParent, "BackdropTemplate")
panel:SetSize(WIDTH, 40)
panel:SetFrameStrata("MEDIUM")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
panel:SetBackdropColor(0.05, 0.08, 0.12, 0.85)
panel:SetBackdropBorderColor(0.4, 0.6, 0.75, 0.9)
panel:Hide()

local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header:SetPoint("TOPLEFT", 10, -9)
header:SetPoint("TOPRIGHT", -10, -9)
header:SetJustifyH("LEFT")

local rows = {}

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = {}
    row.icon = panel:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("TOPLEFT", 10, -26 - (i - 1) * ROW_H)
    row.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.count:SetPoint("RIGHT", panel, "TOPRIGHT", -10, -26 - (i - 1) * ROW_H - (ROW_H - 2) / 2)
    row.count:SetJustifyH("RIGHT")
    row.name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    rows[i] = row
    return row
end

local function QualityHex(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    return (c and c.hex) or "|cffffffff"
end

local function Elapsed(s)
    local secs = math.max(0, (s.ended or time()) - s.started)
    local h, m = math.floor(secs / 3600), math.floor(secs / 60) % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, secs % 60) end
    return string.format("%d:%02d", m, secs % 60)
end

local function Sorted(s)
    local list = {}
    for _, item in pairs(s.items) do list[#list + 1] = item end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local function Render(s)
    if not s then panel:Hide() return end
    local label = s.ended and "Last session" or "Fishing"
    local catches = s.catches == 1 and "1 catch" or (s.catches .. " catches")
    header:SetText(label .. "  |cffffffff" .. catches .. "  ·  " .. Elapsed(s) .. "|r")

    local list = Sorted(s)
    local shown = math.min(#list, MAX_ROWS)
    if #list > MAX_ROWS then shown = MAX_ROWS - 1 end
    for i = 1, shown do
        local item, row = list[i], Row(i)
        row.icon:SetTexture(item.icon)
        row.icon:Show()
        row.name:SetText(QualityHex(item.quality) .. (item.name or "?") .. "|r")
        row.count:SetText(item.count)
        row.name:Show(); row.count:Show()
    end
    local used = shown
    if #list > shown then
        local rest = 0
        for i = shown + 1, #list do rest = rest + list[i].count end
        used = shown + 1
        local row = Row(used)
        row.icon:Hide()
        row.name:SetText("|cff999999+" .. (#list - shown) .. " more|r")
        row.count:SetText(rest)
        row.name:Show(); row.count:Show()
    end
    if used == 0 then
        used = 1
        local row = Row(1)
        row.icon:Hide()
        row.name:SetText("|cff999999Nothing yet|r")
        row.count:SetText("")
        row.name:Show(); row.count:Show()
    end
    for i = used + 1, #rows do
        rows[i].icon:Hide(); rows[i].name:Hide(); rows[i].count:Hide()
    end
    panel:SetHeight(32 + used * ROW_H)
    panel:Show()
end

-- Default spot: just below the game's gamepad input legend (top left). The
-- legend has no global name, so find it by its entries, which are built from
-- GamepadPersistentInputLegendEntryTemplate (GamepadPersistentInputLegendEntryMixin),
-- and anchor to the frame that holds them. Entries can be created late, so
-- keep looking for a while. Anything that doesn't look like a smallish
-- top-left box is not trusted.
local legend
local legendTries = 0

local function LooksLikeLegend(f)
    if not (f and f.GetLeft and f:GetLeft() and f:GetTop()) then return false end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    return f:GetLeft() < sw * 0.4 and f:GetTop() > sh * 0.5 and f:GetHeight() < sh * 0.6 and f:GetWidth() < sw * 0.5
end

local function FindLegend()
    local mixin = _G.GamepadPersistentInputLegendEntryMixin
    if type(mixin) ~= "table" then return nil end
    local key, fn
    for k, v in pairs(mixin) do
        if type(v) == "function" then key, fn = k, v break end
    end
    if not key then return nil end
    local f = EnumerateFrames()
    while f do
        if f[key] == fn then
            local holder = f:GetParent()
            if holder and holder ~= UIParent and LooksLikeLegend(holder) then return holder end
        end
        f = EnumerateFrames(f)
    end
    return nil
end

local function PlacePanel()
    panel:ClearAllPoints()
    local p = db and db.pos
    if p then
        panel:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif legend then
        panel:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", 0, -8)
    else
        panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -260)
    end
end

local function SeekLegend()
    if legend or legendTries >= 30 then return end
    legendTries = legendTries + 1
    legend = FindLegend()
    if legend then
        PlacePanel()
    else
        C_Timer.After(2, SeekLegend)
    end
end

panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.pos = { point, relPoint, x, y }
end)

---------------------------------------------------------------------------
-- Idle reminder: pole equipped but no cast for a while. A soft blip every
-- IDLE_REPEAT seconds until you cast or unequip the pole; the big on-screen
-- text (fades by itself, nothing to click) on the first one and then once a
-- minute; one chat line.

local IDLE_DEFAULT = 60
local IDLE_REPEAT = 15
local IDLE_TEXT_EVERY = 60
-- Choices for /deckkit fish alert (soft UI sounds; numbers are fallbacks if a
-- SOUNDKIT name is missing).
local SK = SOUNDKIT or {}
local IDLE_SOUNDS = {
    { key = "ping",    label = "map ping blip",       kit = SK.MAP_PING or 3175 },
    { key = "whisper", label = "whisper bloop",       kit = SK.TELL_MESSAGE or 3081 },
    { key = "double",  label = "whisper double tap",  kit = SK.TELL_MESSAGE or 3081, again = 0.3,
                   file = 567421 },  -- sound/interface/itellmessage.ogg
    { key = "coin",    label = "coin clink",          kit = SK.LOOT_WINDOW_COIN_SOUND or 120 },
    { key = "bell",    label = "auction house bell",  kit = SK.AUCTION_WINDOW_OPEN or 5274 },
    { key = "page",    label = "quest log page turn", kit = SK.IG_QUEST_LOG_OPEN or 844 },
    { key = "click",   label = "checkbox click",      kit = SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856 },
}

local function PlayIdle(snd)
    -- false = allow duplicates; WoW otherwise drops a sound that's still playing
    PlaySound(snd.kit, "Master", false)
    if not snd.again then return end
    C_Timer.After(snd.again, function()
        local second = PlaySound(snd.kit, "Master", false)
        if not second and snd.file and PlaySoundFile then
            -- the sound kit refused a repeat: play its file directly
            PlaySoundFile(snd.file, "Master")
        end
    end)
end

local function IdleSound()
    local want = db and db.idleSound
    for _, s in ipairs(IDLE_SOUNDS) do
        if s.key == want then return s end
    end
    return IDLE_SOUNDS[3]   -- "double": the default
end
local lastActivity, nextRemind, nextText

local function Activity()
    lastActivity, nextRemind, nextText = GetTime(), nil, nil
end

local function CheckIdle()
    if not (session and lastActivity) or db.idle == false then return end
    local now = GetTime()
    if now < (nextRemind or (lastActivity + (db.idle or IDLE_DEFAULT))) then return end
    local first = nextRemind == nil
    nextRemind = now + IDLE_REPEAT
    PlayIdle(IdleSound())
    if first or now >= nextText then
        nextText = now + IDLE_TEXT_EVERY
        local mins = math.max(1, math.floor((now - lastActivity) / 60 + 0.5))
        local msg = string.format("Fishing pole still equipped: no cast for %d min", mins)
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, msg, (ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.3, b = 0.1 })
        end
        if first then out(msg .. ".") end
    end
end

---------------------------------------------------------------------------
-- Sessions

local function StopTimers()
    if ticker then ticker:Cancel(); ticker = nil end
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
end

local function StartSession(resume)
    StopTimers()
    session = resume or { started = time(), catches = 0, items = {} }
    db.session = session
    Render(session)
    Activity()
    ticker = C_Timer.NewTicker(1, function()
        Render(session)
        CheckIdle()
    end)
end

local function EndSession()
    if not session then return end
    StopTimers()
    pending = nil
    local s = session
    session, db.session = nil, nil
    s.ended = time()
    db.last = s

    if s.catches > 0 then
        local parts = {}
        for _, item in ipairs(Sorted(s)) do
            parts[#parts + 1] = item.count .. "x " .. QualityHex(item.quality) .. (item.name or "?") .. "|r"
        end
        out(string.format("session over: %d %s in %s. %s", s.catches, s.catches == 1 and "catch" or "catches",
            Elapsed(s), table.concat(parts, ", ")))
    end
    Render(s)
    hideTimer = C_Timer.NewTimer(LINGER, function() hideTimer = nil; panel:Hide() end)
end

local function CheckPole()
    if PoleEquipped() then
        if not session then StartSession() end
    else
        EndSession()
    end
end

---------------------------------------------------------------------------
-- Loot: snapshot the fishing loot window, count each slot as it's taken

local function Snapshot()
    if not session or pending or not IsFishingLoot() then return end
    pending = {}
    for slot = 1, GetNumLootItems() do
        if GetLootSlotType(slot) == LOOT_ITEM then
            local icon, name, quantity, _, quality = GetLootSlotInfo(slot)
            local link = GetLootSlotLink(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                pending[slot] = { id = id, name = name, icon = icon, quality = quality, quantity = quantity or 1 }
            end
        end
    end
    session.catches = session.catches + 1
    Render(session)
end

local function SlotTaken(slot)
    local loot = pending and pending[slot]
    if not (loot and session) then return end
    pending[slot] = nil
    local item = session.items[loot.id]
    if not item then
        item = { name = loot.name, icon = loot.icon, quality = loot.quality, count = 0 }
        session.items[loot.id] = item
    end
    item.count = item.count + loot.quantity
    Render(session)
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Missed-catch chime: the fishing channel ran its full length, so the bobber
-- timed out without a catch. Reeling in (clicking the bobber) or cancelling
-- (moving, jumping) ends the channel early and stays silent.

local CHIME = (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3) or 12889
local FULL_BAR_SLACK = 400   -- ms before the bar's end that still counts as "ran out"
local FISHING_IDS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
    [51294] = true, [88868] = true, [131474] = true }
local channelEnd             -- endTimeMS of the fishing channel in progress

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function IsFishing(spellID, name)
    return (spellID and FISHING_IDS[spellID]) or (name and name == SpellName(7620))
end

local function ChannelStarted(spellID)
    local name, _, _, _, endTimeMS = UnitChannelInfo("player")
    channelEnd = IsFishing(spellID, name) and endTimeMS or nil
    if channelEnd then Activity() end
end

local function ChannelStopped()
    local finish = channelEnd
    channelEnd = nil
    if finish and db.chime ~= false and GetTime() * 1000 >= finish - FULL_BAR_SLACK then
        PlaySound(CHIME, "Master")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_SLOT_CLEARED")
events:RegisterEvent("LOOT_CLOSED")
events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        DeckAnglerDB = DeckAnglerDB or {}
        db = DeckAnglerDB
        PlacePanel()
        SeekLegend()
    elseif not db then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1: initial login, arg2: /reload. Entering the game with a pole
        -- equipped starts a session; a /reload carries on with the same one.
        if arg2 and db.session and not session and PoleEquipped() then
            StartSession(db.session)
        else
            if not session then db.session = nil end
            CheckPole()
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == MAIN_HAND then CheckPole() end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        Snapshot()
    elseif event == "LOOT_SLOT_CLEARED" then
        SlotTaken(arg1)
    elseif event == "LOOT_CLOSED" then
        pending = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        ChannelStarted(arg3)   -- unit, castGUID, spellID
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ChannelStopped()
    end
end)

local function Command(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local buttonArg = msg:match("^button%s*(%S*)$")
    if buttonArg then
        if buttonArg == "on" or buttonArg == "off" then db.oneButton = buttonArg == "on" end
        if ns.OneButtonApply then ns.OneButtonApply() end
        out("one-button fishing on X " .. (db.oneButton == false and "off" or "on") .. " (/deckkit fish button on|off).")
        return
    end
    if msg == "chime" or msg == "chime on" or msg == "chime off" then
        if msg == "chime" then
            PlaySound(CHIME, "Master")
            out("missed-catch chime is " .. (db.chime == false and "off" or "on") .. " (/deckkit fish chime on|off).")
        else
            db.chime = msg == "chime on"
            out("missed-catch chime " .. (db.chime and "on" or "off") .. ".")
        end
        return
    end
    local soundArg = msg:match("^alert%s*(%S*)$")
    if soundArg then
        local pick = IDLE_SOUNDS[tonumber(soundArg) or 0]
        for _, snd in ipairs(IDLE_SOUNDS) do
            if snd.key == soundArg then pick = snd end
        end
        if pick then
            db.idleSound = pick.key
            PlayIdle(pick)
            out("alert sound: " .. pick.key .. " (" .. pick.label .. ").")
            return
        end
        local current = IdleSound().key
        local list = {}
        for i, snd in ipairs(IDLE_SOUNDS) do
            list[#list + 1] = (snd.key == current and "|cff00ff00" or "") .. i .. " " .. snd.key ..
                (snd.key == current and "|r" or "")
        end
        out("alert sounds: " .. table.concat(list, ", ") .. ". Pick one with /deckkit fish alert <name or number>.")
        PlayIdle(IdleSound())
        return
    end
    local idleArg = msg:match("^idle%s*(%S*)$")
    if idleArg then
        if idleArg == "off" then
            db.idle = false
        elseif tonumber(idleArg) and tonumber(idleArg) >= 10 then
            db.idle = math.floor(tonumber(idleArg))
        elseif idleArg == "on" then
            db.idle = nil
        elseif idleArg == "" then
            PlayIdle(IdleSound())
        end
        out("idle reminder " .. (db.idle == false and "off" or ("after " .. (db.idle or IDLE_DEFAULT) ..
            "s without a cast")) .. " (/deckkit fish idle <seconds>|on|off).")
        return
    end
    if msg == "reset" then
        db.pos = nil
        if not legend then legendTries = 0; SeekLegend() end
        PlacePanel()
        out(legend and "panel moved back under the controller legend."
            or "panel moved back to the top left (controller legend not found).")
        return
    end
    if session then
        out("session running: " .. session.catches .. " catches so far.")
        return
    end
    if not db.last then
        out("no session yet. Equip a fishing pole to start one.")
        return
    end
    StopTimers()
    Render(db.last)
    hideTimer = C_Timer.NewTimer(LINGER, function() hideTimer = nil; panel:Hide() end)
end

ns.AddCommand("fish", Command, "last fishing tally; button | chime | alert | idle | reset")

local soundChoices = {}
for _, snd in ipairs(IDLE_SOUNDS) do table.insert(soundChoices, { snd.key, snd.label }) end

ns.AddSettings({
    { type = "toggle", label = "X casts Fishing", hint = "With a fishing pole equipped, out of combat.",
      get = function() return db.oneButton ~= false end,
      set = function(on) db.oneButton = on; if ns.OneButtonApply then ns.OneButtonApply() end end },
    { type = "toggle", label = "Missed-catch chime", hint = "Plays when the bobber times out without a bite.",
      get = function() return db.chime ~= false end,
      set = function(on) db.chime = on; if on then PlaySound(CHIME, "Master") end end },
    { type = "choice", label = "Idle reminder", hint = "Pole equipped but no cast for this long.",
      values = { { false, "Off" }, { 30, "30 sec" }, { 60, "1 min" }, { 120, "2 min" }, { 300, "5 min" } },
      get = function() if db.idle == false then return false end return db.idle or IDLE_DEFAULT end,
      set = function(v) db.idle = v end },
    { type = "choice", label = "Reminder sound", hint = "Plays each one as you pick it.",
      values = soundChoices,
      get = function() return IdleSound().key end,
      set = function(key)
          db.idleSound = key
          PlayIdle(IdleSound())
      end },
    { type = "action", label = "Show the last tally", run = function() Command("") end },
    { type = "action", label = "Reset the tally panel position", run = function() Command("reset") end },
})
