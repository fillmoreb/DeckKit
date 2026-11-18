-- Words: a guide's texts hold name tokens ({npc:823}, {quest:783}, {area:24}, {zone:1429}, {item:750},
-- {object:460001}, {spell:1259416}); the guide's `names` table has each one's English and `written` has whole
-- texts an author worded by hand (Polestar's format 3, docs/PACK_FORMAT.md). Each goal gets a line in the
-- style of the quest tracker: "Accept from Deputy Willem", "Kill Juvenile Vuldren", the game's own objective
-- text while the quest is in the log.
local FG = ForeverGuide
local Text = {}
FG.Text = Text
local Game = FG.Game

local function Fallback(kind, id)
    id = tonumber(id)
    if kind == "item" and C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if kind == "spell" then
        if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    end
    if kind == "quest" then return Game.QuestTitle(id) end
    if kind == "zone" then return Game.MapName(id) end
    if kind == "area" then return Game.AreaName(id) end
end

-- A guide text with its tokens in words; | doubled so a FontString shows it as written.
function Text.Resolve(guide, s)
    if type(s) ~= "string" then return s end
    local w = guide.written and guide.written[s]
    if w then s = w end
    local names = guide.names or {}
    s = s:gsub("{(%a+):(%d+)}", function(kind, id)
        return names[kind .. ":" .. id] or Fallback(kind, id) or (kind .. " " .. id)
    end)
    return (s:gsub("|", "||"))
end

local function Count(n) return (n and n > 1) and (" x" .. n) or "" end

local VERB = {
    accept = function(g) return "Accept" .. ((g.npcName or g.objName or g.itemName) and (" from " .. (g.npcName or g.objName or g.itemName)) or "") end,
    turnin = function(g) return "Turn in" .. ((g.npcName or g.objName) and (" to " .. (g.npcName or g.objName)) or "") end,
    complete = function() return "Complete" end,
    kill = function(g) return "Kill " .. (g.target or "?") .. Count(g.count) end,
    collect = function(g) return (g.itemName or "?") .. ((g.count and g.count > 1) and (": 0/" .. g.count) or "") end,
    interact = function(g) return g.objName or "Use the object" end,
    use = function(g) return "Use " .. (g.itemName or "the item") end,
    ["goto"] = function(g, guide)
        local area = g.area and Game.AreaName(g.area)
        return "Go to " .. (area or (g.x and string.format("%.0f, %.0f", g.x, g.y)) or "the spot")
    end,
    talk = function(g) return "Talk to " .. (g.npcName or "?") end,
    train = function(g)
        if g.skill then return "Train " .. g.skill end
        if g.npcName then return "Train at " .. g.npcName end
        return "Train your class skills"
    end,
    vendor = function(g) return g.npcName and ("Visit " .. g.npcName) or "Visit a vendor" end,
    buy = function(g) return "Buy " .. (g.itemName or "?") .. Count(g.count) end,
    auction = function(g) return "Buy " .. (g.itemName or "?") .. Count(g.count) .. " at the auction house" end,
    fly = function(g) return "Fly to " .. (Game.AreaName(g.area) or g.location or "?") end,
    hearth = function(g) return "Hearth to " .. (Game.AreaName(g.area) or g.location or "?") end,
    enter = function(g) return "Enter " .. (Game.AreaName(g.area) or g.location or "?") end,
    getfp = function(g) return "Get the flight path" .. (g.location and (" at " .. g.location) or "") end,
    sethome = function(g) return "Make " .. (g.location or "this inn") .. " your home" end,
    level = function(g)
        if g.frac then return string.format("Reach level %d (%d%%)", g.level, math.floor(g.frac * 100 + 0.5)) end
        return "Reach level " .. tostring(g.level)
    end,
    skill = function(g) return string.format("%s to %d", g.skill or "Skill", g.level or 0) end,
    learn = function(g) return "Learn " .. (g.spellName or "?") end,
    craft = function(g) return "Make " .. (g.itemName or g.spellName or "?") .. Count(g.count) end,
    cast = function(g) return "Cast " .. (g.spellName or "?") end,
    rep = function(g) return (g.factionName or "Reputation") .. ": " .. (_G["FACTION_STANDING_LABEL" .. (g.standing or 0)] or g.standing or "?") end,
    explore = function() return "Explore the area" end,
    money = function(g) return "Have " .. (C_CurrencyInfo and C_CurrencyInfo.GetCoinText and C_CurrencyInfo.GetCoinText(g.money or 0) or tostring(g.money)) end,
    wait = function(g) return "Wait " .. tostring(g.seconds) .. " s" end,
    die = function(g) return "Die and return at " .. (g.location or "the spirit healer") end,
    abandon = function() return "Abandon the quest" end,
    destroy = function(g) return "Destroy " .. (g.itemName or "?") end,
}

-- A goal's line: its own `text` if it has one, else the verb's wording. obj: the quest log line it
-- reads (kill, collect, interact, use while the quest is in the log), which is the game's own words.
function Text.Goal(guide, g, obj)
    if obj and obj.text and obj.text ~= "" then return obj.text end
    if g.text then return Text.Resolve(guide, g.text) end
    local f = VERB[g.t]
    return Text.Resolve(guide, f and f(g, guide) or g.t)
end
