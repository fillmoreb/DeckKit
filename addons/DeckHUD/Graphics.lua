-- DeckHUD graphics presets: Steam Deck presets for the game's graphics settings (Battery, Balanced, Max FPS,
-- Max Quality), in the DeckKit menu (Screen > Graphics). Your own settings are saved before the first preset
-- goes on, and "Your own settings" puts them back. A grip chord action steps to the next preset.
--
-- Adapted from DeckForever by eliog and the DeckForever contributors (MIT,
-- https://github.com/eliog/DeckForeverAddon): the presets and their measured values, the CVar write order
-- (graphicsQuality, then the Options sliders' index CVars, then the raw CVars they rewrite, then frame rate
-- and rendering), the raid twins, the snapshot, and the Steam Deck Performance settings and battery hours
-- that go with each preset. Its window, minimap button, per-preset customising and keep-or-revert prompt are
-- left out. DeckForever's active preset and snapshot are taken over once, if it was installed.
local _, ns = ...

------------------------------------------------------------------------
-- CVars, in write order (DeckForever's Presets.lua): writing a graphics* index CVar makes the client
-- rewrite the raw CVars behind it, so index CVars go first and raw values after.
------------------------------------------------------------------------

local ORDER, TWIN, RANGE = {}, {}, {}
local function def(name, twin, min, max)
    ORDER[#ORDER + 1] = name
    TWIN[name] = twin
    if min then RANGE[name] = { min, max }; if twin then RANGE[twin] = RANGE[name] end end
end

-- master
def("graphicsQuality", "RAIDgraphicsQuality", 0, 9)
-- index (the Options panel's sliders)
def("graphicsShadowQuality", "raidGraphicsShadowQuality", 0, 5)
def("graphicsLiquidDetail", "raidGraphicsLiquidDetail", 0, 3)
def("graphicsParticleDensity", "raidGraphicsParticleDensity", 0, 5)
def("graphicsSSAO", "raidGraphicsSSAO", 0, 4)
def("graphicsDepthEffects", "raidGraphicsDepthEffects", 0, 3)
def("graphicsComputeEffects", "raidGraphicsComputeEffects", 0, 4)
def("graphicsOutlineMode", "raidGraphicsOutlineMode", 0, 2)
def("graphicsTextureResolution", "raidGraphicsTextureResolution", 0, 2)
def("graphicsSpellDensity", "raidGraphicsSpellDensity", 0, 2)
def("graphicsProjectedTextures", "raidGraphicsProjectedTextures", 0, 1)
def("graphicsViewDistance", "raidGraphicsViewDistance", 0, 9)
def("graphicsEnvironmentDetail", "raidGraphicsEnvironmentDetail", 0, 9)
def("graphicsGroundClutter", "raidGraphicsGroundClutter", 0, 9)
def("graphicsLightMode", "raidGraphicsLightMode", 0, 2)
def("graphicsPBRLiquidDetail", "raidGraphicsPBRLiquidDetail")
def("graphicsBloomUserMult", "raidGraphicsBloomUserMult")
-- raw
def("giQuality", "RAIDgiQuality", 1, 3)
def("shadowMode", "RAIDshadowMode", 0, 3)
def("SSAO", "RAIDSSAO", 0, 4)
def("particleDensity", "RAIDparticleDensity", 10, 100)
def("waterDetail", "RAIDWaterDetail", 0, 3)
def("projectedTextures", "RAIDprojectedTextures", 0, 1)
def("sunShafts", "RAIDsunShafts", 0, 2)
def("refraction", "RAIDrefraction", 0, 2)
def("reflectionMode", "RAIDreflectionMode", 0, 3)
def("rippleDetail", "RAIDrippleDetail", 0, 2)
def("volumeFogLevel", "RAIDVolumeFogLevel", 0, 3)
def("weatherDensity", "RAIDweatherDensity", 0, 3)
-- raw CVars the index CVars rewrite: in no preset, saved in the snapshot so a restore is exact
for _, n in ipairs({ "farclip", "horizonStart", "horizonClip", "groundEffectDensity", "groundEffectDist",
    "lodObjectCullSize", "lodObjectFadeScale", "lodObjectMinSize", "wmoLodDist", "entityLodDist",
    "entityShadowFadeScale", "TerrainLodDiv", "shadowNumCascades", "shadowBlendCascades", "particleMTDensity",
    "pbrLiquidDetail", "OutlineEngineMode" }) do
    def(n, "RAID" .. n)
end
def("spellClutter")
-- frame rate and rendering
def("vsync", nil, 0, 1)
def("useTargetFPS", nil, 0, 1)
def("useMaxFPS", nil, 0, 1)
def("maxFPS", nil, 8, 200)
def("useMaxFPSBk", nil, 0, 1)
def("maxFPSBk", nil, 8, 200)
def("maxFPSLoading", nil, 8, 200)
def("RenderScale", nil, 0.33, 1.0)
def("ResampleQuality", nil, 0, 3)
def("ffxAntiAliasingMode", nil, 0, 4)
def("MSAAQuality", nil, 0, 4)
def("physicsLevel", nil, 0, 2)
-- interface
def("cameraDistanceMaxZoomFactor", nil, 1.0, 2.6)

local RANK = {}
for i, n in ipairs(ORDER) do RANK[n] = i * 2; if TWIN[n] then RANK[TWIN[n]] = i * 2 + 1 end end

------------------------------------------------------------------------
-- The presets (DeckForever's values, measured on a Steam Deck)
------------------------------------------------------------------------

local COMMON = {
    useTargetFPS = 0, useMaxFPS = 1, useMaxFPSBk = 1, maxFPSLoading = 30, vsync = 1,
    ResampleQuality = 3, graphicsProjectedTextures = 1, projectedTextures = 1,
    graphicsTextureResolution = 2, graphicsSpellDensity = 0, MSAAQuality = 0, physicsLevel = 1,
    cameraDistanceMaxZoomFactor = 2.6,
}
local LOW = { -- shared by Battery and Balanced
    graphicsLightMode = 0, giQuality = 1, RenderScale = 0.85, graphicsSSAO = 1, SSAO = 1,
    graphicsDepthEffects = 0, graphicsComputeEffects = 1, graphicsParticleDensity = 2, particleDensity = 40,
    graphicsLiquidDetail = 1, waterDetail = 1, graphicsViewDistance = 3, graphicsEnvironmentDetail = 4,
    graphicsGroundClutter = 3, ffxAntiAliasingMode = 2, sunShafts = 0, refraction = 0, reflectionMode = 0,
    rippleDetail = 1, volumeFogLevel = 0, weatherDensity = 1,
}

local function Preset(t, ...)
    local values = {}
    for _, src in ipairs({ COMMON, ... }) do for k, v in pairs(src) do values[k] = v end end
    for k, v in pairs(t.values) do values[k] = v end
    t.values = values
    return t
end

-- deck: the Steam Deck's own Performance settings that go with it (... > Performance, per-game profile);
-- hours: battery hours measured on a Steam Deck OLED, questing / in a capital.
local PRESETS = {
    battery = Preset({ label = "Battery", desc = "30 fps, the longest play time", hours = { 4.5, 4.2 },
        deck = "Frame Limit 30 FPS (90 Hz), TDP Limit on, 8-10 W", short = "30 FPS (90 Hz) · TDP 8-10 W",
        values = { maxFPS = 30, maxFPSBk = 20, graphicsShadowQuality = 0, shadowMode = 0 },
        raid = { graphicsViewDistance = 3, graphicsGroundClutter = 1, graphicsSSAO = 0 } }, LOW),
    -- Battery plus real shadows (level 2 is where the shaded lighting starts). Measured +1 W.
    balanced = Preset({ label = "Balanced", desc = "45 fps, shadows and shading", hours = { 3.7, 3.2 },
        deck = "Frame Limit 45 FPS (90 Hz), TDP Limit on, 10 W", short = "45 FPS (90 Hz) · TDP 10 W",
        values = { maxFPS = 45, maxFPSBk = 20, graphicsShadowQuality = 2, shadowMode = 2 },
        raid = { graphicsViewDistance = 3, graphicsGroundClutter = 1, graphicsSSAO = 0, graphicsShadowQuality = 0 } }, LOW),
    performance = Preset({ label = "Max FPS", desc = "60 fps at full power (cities about 50)", hours = { 2.7, 2.3 },
        deck = "Frame Limit 60 FPS (60 Hz), TDP Limit off", short = "60 FPS (60 Hz) · no TDP limit",
        values = {
            graphicsLightMode = 0, giQuality = 1, maxFPS = 60, maxFPSBk = 30, RenderScale = 1.0,
            graphicsShadowQuality = 2, shadowMode = 2, graphicsSSAO = 1, SSAO = 1,
            graphicsDepthEffects = 0, graphicsComputeEffects = 1, graphicsParticleDensity = 3, particleDensity = 60,
            graphicsLiquidDetail = 1, waterDetail = 1, graphicsViewDistance = 5, graphicsEnvironmentDetail = 4,
            graphicsGroundClutter = 5, ffxAntiAliasingMode = 4, sunShafts = 0, refraction = 1, reflectionMode = 0,
            rippleDetail = 1, volumeFogLevel = 0, weatherDensity = 2 },
        raid = { graphicsViewDistance = 4, graphicsGroundClutter = 3, graphicsParticleDensity = 2 } }),
    -- Everything high at 30 fps; reflections, fog and SSAO a step short of max (all at max: 2.5 fps on a Deck).
    quality = Preset({ label = "Max Quality", desc = "30 fps, the best picture; plugged in, not for cities",
        hours = { 2.6, 2.3 }, deck = "Frame Limit 30 FPS (90 Hz), TDP Limit off",
        short = "30 FPS (90 Hz) · no TDP limit",
        values = {
            graphicsLightMode = 2, giQuality = 3, maxFPS = 30, maxFPSBk = 30, RenderScale = 1.0,
            graphicsShadowQuality = 4, shadowMode = 3, graphicsSSAO = 3, SSAO = 3,
            graphicsDepthEffects = 2, graphicsComputeEffects = 4, graphicsParticleDensity = 5, particleDensity = 100,
            graphicsLiquidDetail = 3, waterDetail = 3, graphicsViewDistance = 8, graphicsEnvironmentDetail = 8,
            graphicsGroundClutter = 8, ffxAntiAliasingMode = 4, sunShafts = 2, refraction = 2, reflectionMode = 2,
            rippleDetail = 2, volumeFogLevel = 2, weatherDensity = 3, graphicsSpellDensity = 2 },
        raid = { graphicsViewDistance = 6, graphicsEnvironmentDetail = 6, graphicsGroundClutter = 5,
            graphicsShadowQuality = 3, graphicsParticleDensity = 4, reflectionMode = 1 } }),
}
local PRESET_ORDER = { "battery", "balanced", "performance", "quality" }

------------------------------------------------------------------------
-- Reading and writing (DeckForever's CVars.lua: never assume a CVar exists; secure ones can't be written)
------------------------------------------------------------------------

local function Format(v)
    if type(v) == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return (string.format("%.4f", v):gsub("0+$", ""))
    end
    return tostring(v)
end

local function Same(a, b)
    if a == nil or b == nil then return a == b end
    a, b = tostring(a):match("^([^,]*)") or a, tostring(b):match("^([^,]*)") or b -- MSAAQuality: "samples,coverage"
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return math.abs(na - nb) < 1e-4 end
    return tostring(a):lower() == tostring(b):lower()
end

local function State(name)
    local value, default, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(name)
    if value == nil and default == nil then return nil end
    return { value = value, writable = not (locked or secure or readOnly) }
end

local function Sorted(names)
    table.sort(names, function(a, b)
        local ra, rb = RANK[a] or 9999, RANK[b] or 9999
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return names
end

-- Writes { name = value } in order; each compared with a live read, as raw CVars see what the index ones changed.
local function Write(values, checkRange)
    local names = {}
    for n in pairs(values) do names[#names + 1] = n end
    local changed, failed = 0, {}
    for _, name in ipairs(Sorted(names)) do
        local want, st = values[name], State(name)
        local r = RANGE[name]
        local ok = st and st.writable and not (checkRange and r and tonumber(want)
            and (tonumber(want) < r[1] or tonumber(want) > r[2]))
        if ok and not Same(st.value, want) then
            pcall(C_CVar.SetCVar, name, Format(want))
            if Same(C_CVar.GetCVar(name), want) then changed = changed + 1 else failed[#failed + 1] = name end
        end
    end
    return changed, failed
end

local function DB()
    ns.db.graphics = ns.db.graphics or {}
    return ns.db.graphics
end

-- Every known CVar's current value (for the snapshot).
local function Capture()
    local out = {}
    for _, name in ipairs(ORDER) do
        for _, n in ipairs({ name, TWIN[name] }) do
            local st = State(n)
            if st and st.value ~= nil then out[n] = st.value end
        end
    end
    return out
end

local pending -- a preset waiting for combat to end
local function WhenSafe(fn)
    if not InCombatLockdown() then fn() return end
    pending = fn
    ns.Print("In combat: the graphics change waits until it ends.")
end
ns.On("PLAYER_REGEN_ENABLED", function() if pending then local fn = pending; pending = nil; fn() end end)

local Graphics = {}
ns.Graphics = Graphics

function Graphics.Apply(key)
    local p = PRESETS[key]
    if not p then return end
    WhenSafe(function()
        local db = DB()
        if not db.snapshot then db.snapshot = { taken = time(), cvars = Capture() } end
        local values = {}
        for name, v in pairs(p.values) do
            values[name] = v
            if TWIN[name] then values[TWIN[name]] = p.raid[name] or v end
        end
        local changed, failed = Write(values, true)
        db.active = key
        ns.Print(string.format("Graphics: %s (%d settings changed%s). On the Deck (... > Performance): %s.",
            p.label, changed, #failed > 0 and (", " .. #failed .. " refused") or "", p.deck))
    end)
end

function Graphics.Restore()
    local db = DB()
    if not db.snapshot then ns.Print("Nothing to restore: no graphics preset has been used.") return end
    WhenSafe(function()
        local _, failed = Write(db.snapshot.cvars, false)
        if #failed == 0 then db.snapshot = nil end
        db.active = nil
        ns.Print(#failed == 0 and "Graphics: your own settings are back."
            or ("Graphics: " .. #failed .. " settings refused; your saved settings are kept to try again."))
    end)
end

-- DeckForever's choice and snapshot, taken over once (its saved variables load only while it's installed).
ns.On("PLAYER_LOGIN", function()
    local db, df = DB(), _G.DeckForeverDB
    if db.imported or type(df) ~= "table" then return end
    db.imported = true
    if PRESETS[df.activePreset or ""] and not db.active then db.active = df.activePreset end
    if type(df.snapshot) == "table" and type(df.snapshot.cvars) == "table" and not db.snapshot then
        db.snapshot = { taken = df.snapshot.taken, cvars = df.snapshot.cvars }
    end
end)

-- A grip chord action: the next preset round (Battery, Balanced, Max FPS, Max Quality), with a short notice.
function Graphics.Next()
    local cur, nextKey = DB().active, PRESET_ORDER[1]
    for i, key in ipairs(PRESET_ORDER) do
        if key == cur then nextKey = PRESET_ORDER[i % #PRESET_ORDER + 1] end
    end
    Graphics.Apply(nextKey)
    ns.Notice("Graphics: " .. PRESETS[nextKey].label, 2.5)
end
DeckKit.Chords.OfferPress("DECKHUD_GRAPHICS_NEXT", Graphics.Next, "Graphics: next preset")

------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------

local VALUES = { { false, "Your own settings" } }
for _, key in ipairs(PRESET_ORDER) do VALUES[#VALUES + 1] = { key, PRESETS[key].label } end

local function Hint()
    local lines = { "Steam Deck presets for the game's graphics. Your own settings are saved before the first one goes on." }
    for _, key in ipairs(PRESET_ORDER) do
        local p = PRESETS[key]
        lines[#lines + 1] = string.format("%s: %s. About %.1f h questing, %.1f h in cities.", p.label, p.desc, p.hours[1], p.hours[2])
    end
    lines[#lines + 1] = "A grip chord action, Graphics: next preset, steps through them while you play."
    lines[#lines + 1] = "From DeckForever, by eliog."
    return table.concat(lines, "\n")
end

ns.AddSettings({
    { type = "section", tab = "Screen", label = "Graphics", order = 1 },
    { type = "choice", label = "Graphics preset", values = VALUES, listOnly = true, hint = Hint(),
      get = function() return DB().active or false end,
      set = function(key)
          if key then Graphics.Apply(key) else Graphics.Restore() end
      end },
    { type = "status", label = "On the Deck", indent = true,
      get = function()
          local p = PRESETS[DB().active or ""]
          return p and p.short or "Your own"
      end },
    { type = "info", indent = true,
      label = "Set the Deck's Frame Limit and TDP to match, in ... > Performance (per-game profile): an addon can't." },
})
