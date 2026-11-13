-- The focus frame's aura row, for the "Name and health" look (Focus.lua): under the health bar,
--   buffs              only the ones you tick (or all of them)
--   your debuffs       on a friendly focus, the only one is a priest's Weakened Soul: when you can
--                      shield them again
--   dispellable        debuffs you can remove (the game decides, from your spells)
--
-- It's one of the game's own aura containers ("CustomAuraContainerTemplate", the one oUF / ElvUI /
-- BigWigs use): the game reads and filters the auras itself, so nothing here touches aura data. We
-- can't read auras ourselves: doing that marked Blizzard's shared aura tables as ours and blocked
-- the gamepad bar (see Focus.lua). Filters the game allows (from Blizzard_CustomAuraContainer.lua):
--   * spell IDs (includeSpellIDs) work for buffs on friendly units and debuffs on enemies only, so
--     a friend's Weakened Soul can't be picked out by ID; "HARMFUL|PLAYER" (cast by you) finds yours
--   * IDs are exact, so every rank of each buff comes from FocusAuraSpells.lua (generated from
--     Forever's data by deck-setup/make-focus-aura-spells.py)
--   * "dispellable by me": the ProcessAura policy with displayOnlyDispellableDebuffs, and the
--     group's processedAuraType = Dispel. That policy is container-wide (it hides every debuff you
--     can't dispel, Weakened Soul too), so dispellable debuffs get a second container of their own.
local _, ns = ...
local UI = DeckKit.UI

local ICON, GAP = 16, 2 -- screen pixels
local MAX_PER_GROUP = 8

local function DB() return ns.db end

-- Settings, with defaults: your own class's buffs ticked, both debuff groups on.
local function BuffMode() return DB().focusAuraBuffs or "list" end -- "list" | "all" | "none"
local function ShowMine() return DB().focusAuraMine ~= false end
local function ShowDispel() return DB().focusAuraDispel ~= false end

local function Ticked()
    local t = DB().focusAuraTicked
    if not t then
        t = {}
        local _, class = UnitClass("player")
        for _, spell in ipairs(ns.FOCUS_AURA_SPELLS or {}) do
            if spell.class:upper() == class then t[spell.name] = true end
        end
        DB().focusAuraTicked = t
    end
    return t
end

local function TickedIDs()
    local ids, ticked = {}, Ticked()
    for _, spell in ipairs(ns.FOCUS_AURA_SPELLS or {}) do
        if ticked[spell.name] then
            for _, id in ipairs(spell.ids) do ids[id] = true end
        end
    end
    return ids
end

------------------------------------------------------------------------
-- The container
------------------------------------------------------------------------

local container, dispelContainer

-- Each icon: the spell's icon, a cooldown sweep (no numbers), a stack count, and for debuffs a border
-- in the dispel type's color (the game picks it).
local function InitIcon(button, harmful)
    button:SetSize(ICON, ICON)
    button:SetHideTooltipInCombat(true)
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cd)
    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
    local text = CreateFrame("Frame", nil, button)
    text:SetAllPoints()
    text:SetFrameLevel(cd:GetFrameLevel() + 1)
    local count = text:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 2, -2)
    button:SetApplicationCount(count, {})
    if harmful then
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        button:AddDispelTypeTexture(border, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.Border,
            showWhenHarmful = true,
        })
    end
end

local function GroupOptions(harmful, candidateFilters)
    return {
        initializeFrame = function(button) InitIcon(button, harmful) end,
        candidateFilters = candidateFilters,
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        maxFrameCount = MAX_PER_GROUP,
        layout = { elementSpacing = GAP, groupSpacing = GAP * 3 },
    }
end

local function BuffFilters()
    if BuffMode() == "all" then return nil end
    return { includeSpellIDs = TickedIDs() }
end

local function Build()
    if container or not (C_UnitAuras and AuraContainerSortMethod and Enum.CustomAuraButtonDispelTypeTextureStyle) then
        return container
    end
    local function New(name)
        local c = CreateFrame("AuraContainer", name, UIParent, "CustomAuraContainerTemplate")
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
        c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        c:SetFlowLayoutGrowthDirection(1, -1)
        return c
    end
    container = New("DeckHUDFocusAuras")
    container:AddAuraGroup("buffs", "HELPFUL", GroupOptions(false, BuffFilters()))
    container:AddAuraGroup("mine", "HARMFUL|PLAYER", GroupOptions(true, nil))
    container:SetUnit("focus")
    dispelContainer = New("DeckHUDFocusDispels")
    dispelContainer:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura,
        { displayOnlyDispellableDebuffs = true })
    dispelContainer:AddAuraGroup("dispel", "HARMFUL",
        GroupOptions(true, { processedAuraType = AuraUtil.AuraUpdateChangedType.Dispel }))
    dispelContainer:SetUnit("focus")
    return container
end

-- Settings changed: filters and which groups show.
local function Configure()
    if not container then return end
    container:SetAuraGroupCandidateFilters("buffs", BuffFilters())
    container:SetAuraGroupEnabled("buffs", BuffMode() ~= "none")
    container:SetAuraGroupEnabled("mine", ShowMine())
    dispelContainer:SetAuraGroupEnabled("dispel", ShowDispel())
end

-- Shown with the compact focus frame, under its health bar, as wide as it.
function ns.FocusAurasPlace(compact, healthBar)
    if not compact then
        if container then container:Hide(); dispelContainer:Hide() end
        return false
    end
    local c = Build()
    if not c then return false end
    -- Buffs and your debuffs under the health bar; dispellable debuffs off its right end, where they
    -- catch the eye.
    local k = healthBar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -4)
    c:SetFlowLayoutMaximumLineSize(math.max(ICON * 4, (healthBar:GetWidth() or 0) * k))
    dispelContainer:ClearAllPoints()
    dispelContainer:SetPoint("LEFT", healthBar, "RIGHT", 6, 0)
    dispelContainer:SetFlowLayoutMaximumLineSize(ICON * 4 + GAP * 3)
    for _, x in ipairs({ c, dispelContainer }) do x:Show(); x:UpdateAllAuras() end
    return true
end

ns.On("PLAYER_FOCUS_CHANGED", function()
    if container then container:UpdateAllAuras(); dispelContainer:UpdateAllAuras() end
end)

------------------------------------------------------------------------
-- The window: which buffs show, and the two debuff groups
------------------------------------------------------------------------

local WIDTH, HEIGHT = 560, 540
local screen

local CLASS_ORDER = { "Priest", "Druid", "Shaman", "Paladin", "Mage", "Warlock" }

local function BuildWindow()
    screen = UI.NewScreen("DeckHUDFocusAurasWindow", WIDTH, HEIGHT, "Focus auras")
    local tab = screen:AddTab("Auras")
    local panel = UI.Panel(tab.frame, nil)
    panel:SetAllPoints()
    local W = WIDTH - 52
    local y = -12
    local intro = UI.Description(panel, "What shows under the focus frame (with its Name and health look). "
        .. "The game does the filtering, so it works in combat.", W)
    intro:SetPoint("TOPLEFT", 12, y)
    y = y - 40
    local function Place(f) f:SetPoint("TOPLEFT", 12, y); y = y - UI.ROW_H - 2 end

    Place(UI.Selector(panel, W, { label = "Buffs", boxWidth = 200,
        values = { { "list", "Only the ticked ones" }, { "all", "All of them" }, { "none", "None" } },
        get = BuffMode, set = function(v) DB().focusAuraBuffs = v; Configure() end }))
    Place(UI.Checkbox(panel, W, { label = "Your own debuffs (a priest's Weakened Soul)",
        get = ShowMine, set = function(on) DB().focusAuraMine = on; Configure() end }))
    Place(UI.Checkbox(panel, W, { label = "Debuffs you can dispel",
        get = ShowDispel, set = function(on) DB().focusAuraDispel = on; Configure() end }))
    y = y - 6

    local list = UI.ScrollList(panel, W, HEIGHT - 76 - 42 - 24 + y - 16)
    list:SetPoint("TOPLEFT", 12, y)
    local content, ly = list.content, 0
    local RW = W - 22
    local ticked = Ticked()
    for _, class in ipairs(CLASS_ORDER) do
        local h = UI.Heading(content, LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class:upper()] or class)
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
        if color then h:SetTextColor(color.r, color.g, color.b) end
        h:SetPoint("TOPLEFT", 6, -ly - 4)
        ly = ly + 26
        for _, spell in ipairs(ns.FOCUS_AURA_SPELLS or {}) do
            if spell.class == class then
                local icon = C_Spell.GetSpellTexture(spell.ids[1])
                local row = UI.Checkbox(content, RW, {
                    label = (icon and ("|T" .. icon .. ":18:18|t  ") or "") .. spell.name,
                    get = function() return ticked[spell.name] == true end,
                    set = function(on) ticked[spell.name] = on or nil; Configure() end,
                })
                row:SetPoint("TOPLEFT", 0, -ly)
                ly = ly + UI.ROW_H + 2
            end
        end
        ly = ly + 6
    end
    list:SetContentHeight(ly)
end

function ns.OpenFocusAuras()
    if InCombatLockdown() then ns.Print("can't open that in combat.") return end
    if not screen then BuildWindow() end
    screen:Show()
end

ns.AddCommand("focusauras", function() ns.OpenFocusAuras() end, "what shows under the focus frame")
