-- QuestPad: one big button (in the game's Extra Action Button art) for the quest item you need
-- right now. Which quest:
--   1. the quest your target belongs to (from the target's tooltip quest lines), else
--   2. the quest whose area you're standing in: the real shape the map draws for it, not a
--      distance from its centre. A hidden quest-area frame (QuestPOIFrame) draws the areas of
--      every quest that has an item, then answers "which area is this point in?" for your position.
-- The key bound to QUESTPAD_USE (Controls > Bindings) clicks the button. Items need a secure click,
-- so the item, the button and its key only change out of combat; in combat it keeps what it had.
-- It steps aside while the game shows its own Extra Action Button.
local ADDON, ns = ...

DeckKit.NewModule(ns, ADDON, "|cffffd060QuestPad|r")

BINDING_HEADER_QUESTPAD = "QuestPad"
BINDING_NAME_QUESTPAD_USE = "Use the quest item"

local DEFAULTS = { enabled = true, byTarget = true, y = -180 }
local ART = "Interface\\ExtraButton\\ExtraButtonGeneric"
local TICK = 0.25
local QUEST_TITLE_LINE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or 17

local db = {}
local button, area
local items = {}      -- questID -> { link, icon, whenComplete }
local itemsDirty = true
local drawnKey        -- what the area frame last drew (map + quests); nil = draw again
local drawnAt = 0     -- the area frame answers only after a frame has passed since drawing
local current         -- questID shown on the button
local previewUntil = 0 -- showing a sample (to place the button) until this time

------------------------------------------------------------------------
-- Quests with items
------------------------------------------------------------------------

local function ScanItems()
    wipe(items)
    itemsDirty = false
    if not GetQuestLogSpecialItemInfo then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local link, icon, _, whenComplete = GetQuestLogSpecialItemInfo(i)
            if link then items[info.questID] = { link = link, icon = icon, whenComplete = whenComplete } end
        end
    end
end

-- An item worth showing for this quest (not once the quest is done, unless the item is for turning in).
local function Wanted(questID)
    local it = questID and items[questID]
    if not it then return end
    if C_QuestLog.IsComplete(questID) and not it.whenComplete then return end
    return it
end

------------------------------------------------------------------------
-- Which quest
------------------------------------------------------------------------

-- The quest of an item-quest that the target belongs to (its tooltip lists the quest by title).
local function TargetQuest()
    if not db.byTarget or not UnitExists("target") or UnitIsDead("target") then return end
    if C_QuestLog.UnitIsRelatedToActiveQuest and not C_QuestLog.UnitIsRelatedToActiveQuest("target") then return end
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit("target")
    if not (data and data.lines) then return end
    for _, line in ipairs(data.lines) do
        if line.type == QUEST_TITLE_LINE then
            if line.id and Wanted(line.id) then return line.id end
            for questID in pairs(items) do
                if line.leftText == C_QuestLog.GetTitleForQuestID(questID) and Wanted(questID) then return questID end
            end
        end
    end
end

-- The item-quest whose area you're standing in.
local function AreaQuest()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local ids = {}
    for questID in pairs(items) do if Wanted(questID) then ids[#ids + 1] = questID end end
    if #ids == 0 then return end
    table.sort(ids)
    local key = map .. ":" .. table.concat(ids, ",")
    if key ~= drawnKey then
        area:SetMapID(map)
        area:DrawNone()
        for _, questID in ipairs(ids) do area:DrawBlob(questID, true) end
        drawnKey, drawnAt = key, GetTime()
        return Wanted(current) and current or nil -- ask again next tick, once it has drawn
    end
    if GetTime() == drawnAt then return Wanted(current) and current or nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    local questID = area:UpdateMouseOverTooltip(x, y)
    return Wanted(questID) and questID or nil
end

------------------------------------------------------------------------
-- The button
------------------------------------------------------------------------

local function Bind()
    if InCombatLockdown() then return end
    ClearOverrideBindings(button)
    if not button:IsShown() then return end
    for _, key in ipairs({ GetBindingKey("QUESTPAD_USE") }) do
        SetOverrideBindingClick(button, true, key, button:GetName(), "LeftButton")
    end
end

-- Changes what the button holds; out of combat only.
local function Show(questID)
    if InCombatLockdown() then return end
    local it = Wanted(questID)
    if not db.enabled or (HasExtraActionBar and HasExtraActionBar()) then it = nil end
    current = it and questID or nil
    if it then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", it.link)
        button.icon:SetTexture(it.icon or C_Item.GetItemIconByID(it.link))
        button.questID = questID
        button:Show()
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("item", nil)
        button.questID = nil
        button:Hide()
    end
    Bind()
end

-- Count, cooldown, usable and range: cosmetic, so these run in combat too.
local function Decorate()
    local it = current and items[current]
    if not it then return end
    local count = C_Item.GetItemCount(it.link)
    button.count:SetText(count and count > 1 and count or "")
    local start, duration = C_Container.GetItemCooldown(C_Item.GetItemInfoInstant(it.link))
    if start and duration and duration > 1.5 then button.cooldown:SetCooldown(start, duration) else button.cooldown:Clear() end
    local usable = C_Item.IsUsableItem(it.link)
    local inRange
    if not InCombatLockdown() and UnitExists("target") then -- IsItemInRange is restricted in combat
        local ok, r = pcall(C_Item.IsItemInRange, it.link, "target")
        if ok then inRange = r end
    end
    if not usable then
        button.icon:SetVertexColor(0.4, 0.4, 0.4)
    elseif inRange == false then
        button.icon:SetVertexColor(1, 0.35, 0.35)
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
end

local function Place()
    if InCombatLockdown() then return end
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER", 0, db.y or DEFAULTS.y)
end

local function Create()
    button = CreateFrame("Button", "QuestPadButton", UIParent, "SecureActionButtonTemplate")
    button:SetSize(52, 52)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("AnyDown") -- a bound key would otherwise click it twice (down, then up)
    button:Hide()

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    -- The Extra Action Button's frame art: 256 x 128, centred on the 52 px button.
    button.art = button:CreateTexture(nil, "OVERLAY")
    button.art:SetSize(256, 128)
    button.art:SetPoint("CENTER", -2, 0)
    button.art:SetTexture(ART)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button:SetScript("OnEnter", function(self)
        local it = self.questID and items[self.questID]
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetHyperlink(it.link)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    area = CreateFrame("QuestPOIFrame", nil, UIParent)
    area:SetSize(512, 512)
    area:SetPoint("CENTER")
    area:Hide() -- answers while hidden; nothing is ever drawn on screen

    Place()
end

------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------

-- Show the button with a sample icon for a few seconds, to see where it sits. Nothing to click.
local function Preview()
    if InCombatLockdown() then return end
    previewUntil = GetTime() + 6
    button:SetAttribute("type", nil)
    button:SetAttribute("item", nil)
    button.icon:SetTexture(134414) -- a hearthstone-ish sample
    button.icon:SetVertexColor(1, 1, 1)
    button.count:SetText("")
    button:Show()
end

local function Update()
    if GetTime() < previewUntil then return end
    if previewUntil > 0 then previewUntil = 0; Show(nil) end
    if itemsDirty then ScanItems() end
    if not InCombatLockdown() then
        local questID = TargetQuest() or AreaQuest()
        if questID ~= current or (button:IsShown() and not current) then Show(questID) end
        if current and (not items[current] or button:GetAttribute("item") ~= items[current].link) then Show(current) end
    end
    Decorate()
end

local clock = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    clock = clock + elapsed
    if clock < TICK then return end
    clock = 0
    if button then Update() end
end)

local function Dirty() itemsDirty = true; drawnKey = nil end
ns.On("QUEST_LOG_UPDATE", Dirty)
ns.On("BAG_UPDATE_DELAYED", Dirty)
ns.On("ZONE_CHANGED_NEW_AREA", function() drawnKey = nil end)
ns.On("PLAYER_TARGET_CHANGED", function() clock = TICK end) -- answer right away
ns.On("UPDATE_BINDINGS", function() if button then Bind() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if button then clock = TICK; Bind() end end)
ns.On("UPDATE_EXTRA_ACTIONBAR", function() if button then Show(current) end end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    QuestPadDB = QuestPadDB or {}
    for k, v in pairs(DEFAULTS) do if QuestPadDB[k] == nil then QuestPadDB[k] = v end end
    db = QuestPadDB
end)
ns.On("PLAYER_LOGIN", Create)

ns.AddCommand("questpad", function(arg)
    if strtrim(arg or "") == "preview" then Preview() return end
    local t = {}
    for questID, it in pairs(items) do
        t[#t + 1] = (C_QuestLog.GetTitleForQuestID(questID) or questID) .. " " .. it.link
    end
    ns.Print(#t == 0 and "No quests with items." or ("Quests with items: " .. table.concat(t, ", ")))
    ns.Print("Showing: " .. (current and (C_QuestLog.GetTitleForQuestID(current) or current) or "nothing"))
end, "list quests with items and what the button shows; preview: show the button for a few seconds")

ns.AddSettings({
    { type = "section", tab = "Tools", label = "Quest items", order = 3 },
    { type = "toggle", label = "Quest item button",
      hint = "A big button for the quest item you need: the quest whose area you're in, or the one your target belongs to.",
      get = function() return db.enabled end,
      set = function(on) db.enabled = on; Show(current) end },
    { type = "toggle", label = "Use your target's quest",
      hint = "Targeting a mob for one of your quests puts that quest's item on the button, even outside the quest's area.",
      get = function() return db.byTarget end,
      set = function(on) db.byTarget = on end },
    { type = "range", label = "Height", min = -360, max = 200, step = 10,
      hint = "Where the button sits, up or down from the middle of the screen.",
      get = function() return db.y end,
      set = function(v) db.y = v; Place(); Preview() end },
    { type = "action", label = "Show the button for a moment", verb = "Show", keepOpen = true,
      hint = "Shows it with a sample icon for a few seconds, so you can see where it sits.",
      run = function() Preview() end },
    { type = "binding", action = "QUESTPAD_USE", tab = "Controls", section = "Bindings", sectionOrder = 9 },
})
