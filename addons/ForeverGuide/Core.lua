-- ForeverGuide: leveling guides for WoW: Forever, as a library. It plays Polestar's guides (fitzforge/polestar,
-- by Fitz, GPL-3.0-only), synced unchanged into Data/ and the faction parts by guide/tools/sync_polestar.py,
-- with an engine of its own: which guide and step a character is on, and what each goal still needs. It draws
-- nothing; an addon shows it through ForeverGuide.v1 (API.lua). Not a DeckKit module: any addon may use it.
--
-- Files, one job each:
--   Core.lua     the ForeverGuide global, and the Polestar.* calls the synced data makes (ForeverGuide.Data)
--   Game.lua     every read of the game (quests, items, level, places), one replaceable table for tests
--   Text.lua     a guide's {npc:123} name tokens into words, and each goal's line
--   Engine.lua   the rules: which goals are done, which step is current, which guide comes next
--   API.lua      ForeverGuide.v1, events, saved state
--   Data/        Polestar's compiled guides (shared ones) and map frames; ForeverGuide_Horde and
--                ForeverGuide_Alliance hold each side's guides and load on demand
--
-- Credit: the guides, their facts and the rules for when a goal counts as done (docs/ARCHITECTURE.md, "Guide
-- data") are Polestar's. Data/LICENSE-DATA.txt is Polestar's notice of where the facts come from.
local ADDON = ...

ForeverGuide = ForeverGuide or {}
local FG = ForeverGuide
FG.ADDON = ADDON

FG.guides = {}      -- id -> the guide table as Polestar compiled it
FG.order = {}       -- ids in load order
FG.retired = {}     -- ids Polestar retired: never offered
FG.experimental = {}
FG.mapFrames = {}   -- uiMapID -> { c, left, right, top, bottom }: the Era map frame some points are in (f = "e")

local function Log(...)
    if FG.Debug then FG.Debug(...) end
end
FG.Log = Log

-- The calls Polestar's compiled files make, answered here. The synced files open with
-- `local Polestar = ForeverGuide.Data`, so there is no global named Polestar.
FG.Data = {
    RegisterGuide = function(def)
        if type(def) ~= "table" or type(def.id) ~= "string" or type(def.steps) ~= "table" then return false, "bad guide" end
        if FG.retired[def.id] then return false, "retired" end
        if not FG.guides[def.id] then FG.order[#FG.order + 1] = def.id end
        FG.guides[def.id] = def
        return true
    end,
    RetireGuides = function(_, ids)
        for _, id in ipairs(ids or {}) do
            FG.retired[id] = true
            FG.guides[id] = nil
        end
    end,
    RegisterExperimental = function(list)
        for _, def in ipairs(list or {}) do FG.experimental[def.id] = def end
    end,
    RegisterMapFrames = function(frames)
        for map, b in pairs(frames and frames.era or {}) do FG.mapFrames[map] = b end
    end,
}

-- Each side's guides are their own load-on-demand addon; load the player's.
function FG.LoadFaction(faction)
    local part = faction and ("ForeverGuide_" .. faction)
    if not part or FG.loadedFaction == faction then return FG.loadedFaction == faction end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    local ok, why = load(part)
    if ok then FG.loadedFaction = faction else Log("couldn't load", part, why) end
    return ok
end
