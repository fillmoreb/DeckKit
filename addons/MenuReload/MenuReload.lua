-- MenuReload: a "Reload UI" button in the game menu (Esc / Menu), right below AddOns.
-- Handles both game-menu designs: the pooled one (GameMenuFrame:InitButtons / AddButton, ordered
-- by layoutIndex) and the older one with fixed named buttons (GameMenuButtonAddons).
-- If it can't find either, it says so once and saves what it saw in MenuReloadDB.probe.
local LABEL = RELOADUI or "Reload UI"
local ADDONS_TEXT = ADDONS or "AddOns"

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MenuReload|r: " .. msg) end

local function Probe(why)
    MenuReloadDB = MenuReloadDB or {}
    local probe = { why = why, time = date("%Y-%m-%d %H:%M:%S"), keys = {}, buttons = {} }
    if GameMenuFrame then
        for k, v in pairs(GameMenuFrame) do
            if type(k) == "string" then table.insert(probe.keys, k .. ":" .. type(v)) end
        end
        for _, child in ipairs({ GameMenuFrame:GetChildren() }) do
            local text = child.GetText and child:GetText()
            table.insert(probe.buttons, tostring(child:GetName()) .. " = " .. tostring(text)
                .. " li=" .. tostring(child.layoutIndex))
        end
        table.sort(probe.keys)
    end
    MenuReloadDB.probe = probe
    Say(why .. " (details saved; /reload and tell Claude)")
end

------------------------------------------------------------------------
-- Pooled menu: buttons are rebuilt each time the menu opens.
------------------------------------------------------------------------
local function AddPooled(menu)
    local addons
    if menu.buttonPool then
        for button in menu.buttonPool:EnumerateActive() do
            if button:GetText() == ADDONS_TEXT then addons = button break end
        end
    end
    local reload = menu:AddButton(LABEL, function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        ReloadUI()
    end)
    if addons and reload and addons.layoutIndex then
        -- Sort right after AddOns, in the same section (same spacing above it).
        reload.layoutIndex = addons.layoutIndex + 0.5
        reload.topPadding = nil
        if menu.MarkDirty then menu:MarkDirty() end
    elseif not addons then
        Probe("menu has no AddOns button; Reload UI added at the bottom")
    end
end

------------------------------------------------------------------------
-- Older fixed menu: anchor under AddOns and push the rest down.
------------------------------------------------------------------------
local function AddFixed()
    local addons = GameMenuButtonAddons
    local button = CreateFrame("Button", "GameMenuButtonMenuReload", GameMenuFrame, "GameMenuButtonTemplate")
    button:SetText(LABEL)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        ReloadUI()
    end)
    -- Whatever hung under AddOns now hangs under us.
    for _, child in ipairs({ GameMenuFrame:GetChildren() }) do
        if child ~= button then
            for i = 1, child:GetNumPoints() do
                local point, rel, relPoint, x, y = child:GetPoint(i)
                if rel == addons and point == "TOP" then
                    child:SetPoint(point, button, relPoint, x, y)
                end
            end
        end
    end
    button:SetPoint("TOP", addons, "BOTTOM", 0, -1)
    -- Grow the menu once per height the game sets (it may reset it on each open).
    local extra, last = button:GetHeight() + 1, nil
    local function Grow(self)
        local h = self:GetHeight()
        if h ~= last then
            last = h + extra
            self:SetHeight(last)
        end
    end
    GameMenuFrame:HookScript("OnShow", Grow)
    Grow(GameMenuFrame)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not GameMenuFrame then
        Say("no game menu frame found.")
        return
    end
    if GameMenuFrame.InitButtons and GameMenuFrame.AddButton then
        hooksecurefunc(GameMenuFrame, "InitButtons", AddPooled)
    elseif GameMenuButtonAddons then
        AddFixed()
    else
        Probe("unknown game menu layout; no button added")
    end
end)
