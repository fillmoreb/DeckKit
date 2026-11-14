-- The status bar: a dark strip across the top of the screen, with readings from the game (clock, FPS,
-- latency, gold, bags, durability, XP, coordinates) and, when DeckKitAfterDark's DeckTelemetry is
-- installed, from the Steam Deck itself (battery, power, load, temperature, fan). An XP line runs along
-- its bottom, so Blizzard's XP bars are hidden (alpha only: they're Edit Mode frames, never moved).
--
-- DeckKit doesn't depend on DeckTelemetry: the Deck readings look for its global and stay blank
-- without it.
--
-- Readings sit in three groups (left, middle, right), each a row of slots picked in the menu
-- (Screen > Status bar). The minimap sits under the bar, and the raid frame lineup and loot rolls
-- measure from its bottom (ns.TopEdge).
local _, ns = ...

local HEIGHT = 20        -- UIParent units (1 per pixel on the Deck)
local XP_H = 2           -- the XP line
local XP_Y = 4           -- its bottom, above the metal edge
local EDGE_OUT = 3       -- the metal edge hangs this far below the bar (SimplePanelTemplate's corners do)
local TICK = 1           -- seconds between updates
local SLOTS = { left = 5, middle = 3, right = 5 }
local DEFAULT_SLOTS = {
    left = { "xp", "gold", "bags", "durability" },
    middle = { "clock" },
    right = { "fps", "latency", "battery", "tapu" },
}

local function DB() return ns.db end
local function On() return DB().statusBar ~= false end
local function HideXP() return DB().statusHideXP ~= false end
local function ShowXPLine() return DB().statusXPLine ~= false end
local function Alpha() return DB().statusAlpha or 1 end

------------------------------------------------------------------------
-- Readings
------------------------------------------------------------------------

local GRAY = "|cff9d9d9d"
local function Label(label, value) return GRAY .. label .. "|r " .. value end
local function Colored(value, r, g, b) return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, value) end
local WARN, BAD = { 1, 0.82, 0 }, { 1, 0.25, 0.25 }

local function Telemetry(key)
    local t = _G.DeckTelemetry
    if not (t and t.Get) then return nil end
    local age = t.Age and t.Age()
    if not age or age > 30 then return nil end -- no sender, or the Deck was asleep
    return t.Get(key)
end

local function Money()
    local copper = GetMoney() or 0
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local icon = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
    if g > 0 then return g .. icon:format("Gold") .. " " .. s .. icon:format("Silver") end
    if s > 0 then return s .. icon:format("Silver") .. " " .. c .. icon:format("Copper") end
    return c .. icon:format("Copper")
end

local function FreeBagSlots()
    local free = 0
    local get = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not get then return nil end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n, family = get(bag)
        if n and (family == 0 or family == nil) then free = free + n end
    end
    return free
end

local function LowestDurability()
    local low
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not low or pct < low then low = pct end
        end
    end
    return low
end

local function AtMaxLevel()
    local max = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or MAX_PLAYER_LEVEL
    return max and UnitLevel("player") >= max
end

-- Each reading: label (menu), text() (nil = nothing to show), telemetry = needs DeckTelemetry.
local READINGS = {
    clock = { label = "Clock", text = function()
        local military = GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime")
        return (date(military and "%H:%M" or "%I:%M %p"):gsub("^0", ""))
    end },
    fps = { label = "Frames per second", text = function()
        return Label("FPS", math.floor((GetFramerate() or 0) + 0.5))
    end },
    latency = { label = "Latency", text = function()
        local _, _, home, world = GetNetStats()
        local ms = math.max(home or 0, world or 0)
        local v = ms .. "ms"
        if ms >= 400 then v = Colored(v, unpack(BAD)) elseif ms >= 200 then v = Colored(v, unpack(WARN)) end
        return v
    end },
    gold = { label = "Gold", text = Money },
    bags = { label = "Free bag slots", text = function()
        local n = FreeBagSlots()
        if not n then return nil end
        local v = tostring(n)
        if n == 0 then v = Colored(v, unpack(BAD)) elseif n <= 3 then v = Colored(v, unpack(WARN)) end
        return Label("Bags", v)
    end },
    durability = { label = "Durability (lowest item)", text = function()
        local pct = LowestDurability()
        if not pct then return nil end
        local v = math.floor(pct + 0.5) .. "%"
        if pct <= 20 then v = Colored(v, unpack(BAD)) elseif pct <= 50 then v = Colored(v, unpack(WARN)) end
        return Label("Dur", v)
    end },
    xp = { label = "Experience", text = function()
        if AtMaxLevel() then return nil end
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if not max or max == 0 then return nil end
        local v = string.format("%.1f%%", cur / max * 100)
        local rested = GetXPExhaustion and GetXPExhaustion()
        if rested and rested > 0 then
            v = v .. Colored(string.format(" +%d%%", math.floor(rested / max * 100 + 0.5)), 0.4, 0.6, 1)
        end
        return Label("XP", v)
    end },
    coords = { label = "Coordinates", text = function()
        local map = C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        if not pos then return nil end
        local x, y = pos:GetXY()
        if not x then return nil end
        return string.format("%.1f, %.1f", x * 100, y * 100)
    end },

    battery = { label = "Battery", telemetry = true, text = function()
        local pct = Telemetry("bat")
        if not pct then return nil end
        local v = math.floor(pct + 0.5) .. "%"
        local state = Telemetry("st")
        if state == "charging" then v = v .. "+" end
        if not Telemetry("ac") then
            if pct <= 10 then v = Colored(v, unpack(BAD)) elseif pct <= 20 then v = Colored(v, unpack(WARN)) end
        end
        return Label("Bat", v)
    end },
    bw = { label = "Battery draw", telemetry = true, text = function()
        local w = Telemetry("bw")
        if not w then return nil end
        return Label("Draw", string.format("%.1fW", w))
    end },
    apu = { label = "APU power", telemetry = true, text = function()
        local w = Telemetry("apu")
        return w and Label("APU", string.format("%.0fW", w)) or nil
    end },
    cpu = { label = "CPU load", telemetry = true, text = function()
        local v = Telemetry("cpu")
        return v and Label("CPU", math.floor(v + 0.5) .. "%") or nil
    end },
    gpu = { label = "GPU load", telemetry = true, text = function()
        local v = Telemetry("gpu")
        return v and Label("GPU", math.floor(v + 0.5) .. "%") or nil
    end },
    mem = { label = "Memory", telemetry = true, text = function()
        local v = Telemetry("mem")
        return v and Label("Mem", math.floor(v + 0.5) .. "%") or nil
    end },
    tapu = { label = "APU temperature", telemetry = true, text = function()
        local c = Telemetry("tapu")
        if not c then return nil end
        local v = math.floor(c + 0.5) .. "°C"
        if c >= 95 then v = Colored(v, unpack(BAD)) elseif c >= 85 then v = Colored(v, unpack(WARN)) end
        return v
    end },
    fan = { label = "Fan speed", telemetry = true, text = function()
        local rpm = Telemetry("fan")
        return rpm and Label("Fan", math.floor(rpm + 0.5) .. "rpm") or nil
    end },
}
local ORDER = { "clock", "fps", "latency", "gold", "bags", "durability", "xp", "coords",
    "battery", "bw", "apu", "cpu", "gpu", "mem", "tapu", "fan" }

local function Slots(group)
    local saved = DB().statusSlots and DB().statusSlots[group]
    return saved or DEFAULT_SLOTS[group]
end

------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------

local bar, texts, xpFill, xpRested
local edgeOut = 0 -- how far the metal edge hangs below the bar

local function Build()
    if bar then return end
    bar = CreateFrame("Frame", "DeckHUDStatusBar", UIParent)
    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
    bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT")
    bar:SetHeight(HEIGHT)
    bar:SetFrameStrata("MEDIUM")
    local fill = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetAllPoints()
    fill:SetColorTexture(0.035, 0.035, 0.045, 0.9) -- DeckKit's windows' dark fill

    -- The thin metal edge along the bottom only: the one tiling piece of Blizzard's SimplePanelTemplate
    -- nine-slice (its bottom edge is the top edge's atlas, flipped). The sides and top would sit off
    -- the screen anyway.
    local edge = bar:CreateTexture(nil, "BORDER")
    edge:SetTexCoord(0, 1, 1, 0) -- flipped before the atlas goes on, as NineSliceUtil does it
    edge:SetHorizTile(true)
    if edge:SetAtlas("_UI-Frame-SimpleMetal-EdgeTop", true) then
        -- The art is 64 tall with the metal at one end: flipped, it sits at the bottom of the piece,
        -- which hangs EDGE_OUT below the bar like the panel's own bottom edge.
        edge:ClearAllPoints()
        edge:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, -EDGE_OUT)
        edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -EDGE_OUT)
        edgeOut = EDGE_OUT
    else
        edge:SetColorTexture(0.45, 0.45, 0.45, 1)
        edge:SetHeight(1)
        edge:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
        edge:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
    end

    -- XP along the bottom, inside the bar: purple to where you are, blue for the rested part beyond.
    xpRested = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    xpRested:SetColorTexture(0.25, 0.45, 1, 0.55)
    xpRested:SetHeight(XP_H)
    xpFill = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    xpFill:SetColorTexture(0.58, 0.3, 0.9, 1)
    xpFill:SetHeight(XP_H)
    xpFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, XP_Y) -- just above the metal edge
    xpRested:SetPoint("BOTTOMLEFT", xpFill, "BOTTOMRIGHT")

    texts = {}
    for _, group in ipairs({ "left", "middle", "right" }) do
        local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        texts[group] = fs
    end
    texts.left:SetPoint("LEFT", 8, 1)
    texts.left:SetJustifyH("LEFT")
    texts.middle:SetPoint("CENTER", 0, 1)
    texts.right:SetPoint("RIGHT", -8, 1)
    texts.right:SetJustifyH("RIGHT")
end

local SEP = "    "

local function UpdateXP()
    local width = bar:GetWidth() or 0
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not ShowXPLine() or AtMaxLevel() or not max or max == 0 or width == 0 then
        xpFill:Hide(); xpRested:Hide()
        return
    end
    local done = cur / max
    xpFill:SetWidth(math.max(0.01, width * done))
    xpFill:Show()
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local extra = math.min(rested / max, 1 - done)
    xpRested:SetWidth(math.max(0.01, width * extra))
    xpRested:SetShown(extra > 0)
end

local function Update()
    if not bar then return end
    for group, fs in pairs(texts) do
        local parts = {}
        for _, key in ipairs(Slots(group)) do
            local r = READINGS[key]
            if r then
                local ok, text = pcall(r.text)
                if ok and text and text ~= "" then parts[#parts + 1] = text end
            end
        end
        fs:SetText(table.concat(parts, SEP))
    end
    UpdateXP()
end

-- Blizzard's XP and reputation bars, hidden by alpha while ours shows.
local BLIZZARD_BARS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local function BlizzardBars()
    local alpha = (On() and HideXP()) and 0 or 1
    for _, name in ipairs(BLIZZARD_BARS) do
        local f = _G[name]
        if f and f:GetAlpha() ~= alpha then f:SetAlpha(alpha) end
    end
end

local ticker
local function Apply()
    if On() then
        Build()
        bar:SetAlpha(Alpha())
        bar:Show()
        Update()
        if not ticker then ticker = C_Timer.NewTicker(TICK, function() Update(); BlizzardBars() end) end
    elseif bar then
        bar:Hide()
    end
    BlizzardBars()
    if ns.Apply then ns.Apply() end -- the minimap moves under (or back up from) the bar
end
ns.StatusBarApply = Apply

-- How far down from the top of the screen the top-edge bars reach, in UIParent units: the status bar,
-- and Blizzard's XP bars while they show along the top. For things placed just under them.
function ns.TopEdge()
    local top = UIParent:GetTop()
    local below = 0
    if bar and bar:IsShown() then below = HEIGHT + edgeOut end
    for _, name in ipairs(BLIZZARD_BARS) do
        local f = _G[name]
        if f and f:IsVisible() and f:GetAlpha() > 0 and f:GetTop() and top - f:GetTop() < 2 + below then
            below = math.max(below, top - f:GetBottom())
        end
    end
    return below
end

-- The bar's height with its metal edge while it shows (the minimap's top margin), else 0.
function ns.StatusBarHeight()
    return (On() and bar and bar:IsShown()) and (HEIGHT + edgeOut) or 0
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(0.5, Apply) end)
for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "BAG_UPDATE_DELAYED",
    "UPDATE_INVENTORY_DURABILITY" }) do
    ns.On(e, function() if bar and bar:IsShown() then Update() end end)
end

------------------------------------------------------------------------
-- Settings: Screen > Status bar
------------------------------------------------------------------------

-- One list for every slot row, filled in at login: DeckTelemetry (if installed) loads after DeckHUD.
local VALUES = {}
local function FillValues()
    wipe(VALUES)
    local list = VALUES
    list[1] = { "", "Nothing" }
    for _, key in ipairs(ORDER) do
        local r = READINGS[key]
        local label = r.label
        if r.telemetry and not _G.DeckTelemetry then label = label .. " (needs DeckTelemetry)" end
        list[#list + 1] = { key, label }
    end
end
FillValues()
ns.On("PLAYER_LOGIN", FillValues)

local function SlotRow(group, i, title)
    return { type = "choice", label = title .. " " .. i, values = VALUES,
        hint = "What shows here. Readings from the Steam Deck itself (battery, temperature...) need "
            .. "DeckKitAfterDark's DeckTelemetry, and stay blank without it.",
        get = function() return Slots(group)[i] or "" end,
        set = function(v)
            DB().statusSlots = DB().statusSlots or {}
            local list = {}
            local cur = Slots(group)
            for n = 1, SLOTS[group] do list[n] = cur[n] or "" end
            list[i] = v
            -- Keep the saved list dense, without trailing blanks.
            local out = {}
            for n = 1, SLOTS[group] do if list[n] ~= "" then out[#out + 1] = list[n] end end
            DB().statusSlots[group] = out
            Update()
        end }
end

local rows = {
    { type = "section", tab = "Screen", label = "Status bar", order = 2 },
    { type = "toggle", label = "Status bar",
      hint = "A dark bar across the top of the screen with the readings below, and an XP line along it.",
      get = On, set = function(on) DB().statusBar = on; Apply() end },
    { type = "toggle", label = "Hide Blizzard's XP bar",
      hint = "While the status bar shows. Its XP line and reading take over.",
      get = HideXP, set = function(on) DB().statusHideXP = on; BlizzardBars() end },
    { type = "toggle", label = "XP line",
      hint = "Purple along the bottom of the bar; the rested part beyond it in blue.",
      get = ShowXPLine, set = function(on) DB().statusXPLine = on; if bar then UpdateXP() end end },
    { type = "action", label = "Buffs under the bar", verb = "Move", keepOpen = true,
      hint = "Moves your buffs down to just under the bar, keeping them where they are across. "
          .. "Backs up your Edit Mode layout, then reloads.",
      run = function()
          local ok, info = ns.Layout.BuffsUnderBar()
          if ok then ns.ReloadSoon("Buffs moved under the bar.") else ns.Print("Not changed: " .. info .. ".") end
      end },
    { type = "range", label = "Opacity", min = 0.2, max = 1, step = 0.1,
      format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
      get = Alpha, set = function(v) DB().statusAlpha = v; if bar then bar:SetAlpha(v) end end },
}
for i = 1, SLOTS.left do rows[#rows + 1] = SlotRow("left", i, "Left") end
for i = 1, SLOTS.middle do rows[#rows + 1] = SlotRow("middle", i, "Middle") end
for i = 1, SLOTS.right do rows[#rows + 1] = SlotRow("right", i, "Right") end
ns.AddSettings(rows)
