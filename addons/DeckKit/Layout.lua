-- DeckKit layouts: windows described as plain data (a Lua table, or JSON from outside) and built from
-- UI.lua's look. For displays made on the fly (an assistant's answer, a generated checklist) and for any
-- window whose content is easier to say than to place by hand.
--
--   local L = UI.Build(parent, spec, { width = 600, height = 380, onReply = fn(value, node) })
--   L.height          how tall it came out (with opts.height it scrolls inside that instead)
--   L:Update()        re-read everything live (done for you as the game changes and twice a second)
--   L:Release()       take it down (its frames go back to be reused)
--
-- parent sits in a screen's tab (UI.NewScreen): focusable pieces join that tab's d-pad order, the footer
-- lists what A / X / Y do on the focused one, and the cursor is the game's chevron as everywhere else.
--
-- A spec is a node. Every node has a `type`; containers have `items` (a list of nodes):
--   list      { type = "list", items = {...} }                      one under another
--   section   { type = "section", title = "Rewards", items = {...} }  a gold heading, then its items
--   row       { type = "row", items = {...} }                       side by side, centered on one line
-- Pieces:
--   text      { type = "text", text = "...", style = "dim" }        wraps; styles: body (default), dim,
--                                                                   small, heading, good, bad, gold;
--                                                                   {A}-style glyph tokens work
--   heading   { type = "heading", text = "..." }
--   item      { type = "item", id = 6265, count = 3 }               icon + name in its quality's color;
--                                                                   hold Y for the game's tooltip, left of
--                                                                   the window
--   quest     { type = "quest", id = 1013, text = "The Book of Ur" } name (text until the game knows it)
--                                                                   and where you are with it
--   check     { type = "check", bind = <condition> }                ticks itself (DeckKit.Conditions), drawn
--             { type = "check", done = true }                       as the quest tracker's marks; fixed ones
--             { type = "check", toggle = true }                     the same. toggle: the player's own, a
--                                                                   full check box that A ticks
--   progress  { type = "progress", bind = { item = 2589, count = 10 }, text = "Linen Cloth" }
--             { type = "progress", value = 3, max = 8 }             a bar with "3/8"
--   waypoint  { type = "waypoint", map = 1421, x = 45.2, y = 68.1, label = "Deathstalker Rendow" }
--                                                                   zone and live distance; A makes it the
--                                                                   active waypoint, hold Y for its map
--                                                                   (centered, over the window)
--   icon      { type = "icon", icon = 136243, size = 22 }
--   button    { type = "button", text = "Ready", buttons = { a = { reply = "ready" } } }
--   space     { type = "space", width = 12 }                        no width: takes the spare room in a row
--                                                                   (pushes what follows to the right)
-- In a row, pieces that hold text (text, item, quest, progress, waypoint, space with no width) share the
-- room left after the fixed ones (check, icon, button). A row with a ticked check grays the rest of it.
-- A row with a toggle check: A on its other piece ticks it (that piece's own A, if it has one, wins).
--
-- Buttons on any focusable piece: `buttons = { a = ..., x = ..., y = ... }` (a table of their own, as a
-- waypoint's x and y are its coordinates). Each is an action:
--   "waypoint"                   make this piece's place the active waypoint
--   "peek"                       hold to see details, let go to hide: tooltips (items, quests) left of
--                                 the window, maps (waypoints) centered over it; they follow the cursor
--                                 while it's held.
--   "toggle"                     tick / untick a toggle check
--   { reply = v, label = "Pick" } hand v to opts.onReply(v, node): the owner decides (an assistant gets
--                                 the player's choice back this way)
-- Pieces bring their own (item, quest: Y peek; waypoint: A waypoint, Y peek; toggle checks: A toggle); a
-- node's own `buttons` replace them one by one. A piece with any action can be focused.
--
-- Nothing in a spec is run as code. A node the engine doesn't know shows as a gray "?" line, so a
-- newer spec on an older client still mostly works.
local _, ns = ...
local UI = ns.UI
local Conditions = ns.Conditions

local GAP_X, GAP_Y = 8, 2
local ROW_H = UI.ROW_H
local ICON = 22
local Glyphs = function(s) return ns.Window.Glyphs(s) end

local widgets = {}   -- type -> { fixed = w | fn(node) | nil (shares a row's spare room), make, set, update, focus }
local pools = {}     -- type -> frames to reuse
local active = {}    -- live layouts
local peekOn = false -- Y held: details beside the window (tooltips left, maps right), following the cursor

------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A piece that can take focus: the quest-list highlight held on under the chevron, like every row.
local function Focusable(parent)
    local f = CreateFrame("Button", nil, parent)
    f:EnableMouse(false) -- controller only: the hidden mouse pointer mustn't light it up
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)
    f:SetHighlightTexture(hl)
    f.press = f:CreateTexture(nil, "OVERLAY")
    f.press:SetAllPoints()
    f.press:SetColorTexture(0, 0, 0, 0.35)
    f.press:Hide()
    return f
end

local STYLE = {
    body = { UI.Font.body }, dim = { UI.Font.dim }, small = { UI.Font.small }, heading = { UI.Font.heading },
    good = { UI.Font.body, UI.Color.good }, bad = { UI.Font.body, UI.Color.bad }, gold = { UI.Font.body, UI.Color.gold },
}

local function Num(v) return tonumber(v) end

-- The frame tooltips open beside (left of it): the window the layout sits in.
local function Side(f)
    local L = f.layout
    if L.opts.side then return L.opts.side end
    local p = f
    while p:GetParent() and p:GetParent() ~= UIParent do p = p:GetParent() end
    return p
end

local function TipBeside(f)
    local side = Side(f)
    GameTooltip:SetOwner(f, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", side, "TOPLEFT", -6, (f:GetTop() or 0) - (side:GetTop() or 0))
end

local function HideTip(f)
    if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
end

widgets.text = {
    make = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.text = Text(f, UI.Font.body)
        f.text:SetPoint("TOPLEFT")
        f.text:SetWordWrap(true)
        return f
    end,
    set = function(f, node, w)
        local style = STYLE[node.style] or STYLE.body
        f.text:SetFontObject(style[1])
        if style[2] then f.text:SetTextColor(unpack(style[2])) end
        f.text:SetWidth(w)
        f.text:SetText(Glyphs(tostring(node.text or "")))
        local h = math.max(16, math.ceil(f.text:GetStringHeight()))
        f:SetSize(w, h)
        return h
    end,
}

widgets.heading = {
    make = widgets.text.make,
    set = function(f, node, w) return widgets.text.set(f, { text = node.text, style = "heading" }, w) + 4 end,
}

widgets.icon = {
    fixed = function(node) return Num(node.size) or ICON end,
    make = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        return f
    end,
    set = function(f, node)
        local s = Num(node.size) or ICON
        f.icon:SetTexture(node.icon)
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f:SetSize(s, s)
        return s
    end,
}

-- Item: icon, then the name in its quality's color (and "x3"). Names the client hasn't seen yet are
-- asked for; the layout updates when they arrive.
local function ItemText(node)
    local id = Num(node.id)
    if not id then return "?", nil end
    local name, _, quality = C_Item.GetItemInfo(id)
    local icon = select(5, C_Item.GetItemInfoInstant(id))
    if not name then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return UI.Hex(UI.Color.dim) .. (node.text or ("Item " .. id)) .. "|r", icon
    end
    local hex = quality and select(4, C_Item.GetItemQualityColor(quality))
    local text = (hex and ("|c" .. hex) or "") .. name .. (hex and "|r" or "")
    local n = Num(node.count)
    if n and n > 1 then text = text .. UI.Hex(UI.Color.dim) .. "  x" .. n .. "|r" end
    return text, icon
end

widgets.item = {
    focus = function() return true end,
    actions = function() return { y = "peek" } end,
    make = function(parent)
        local f = Focusable(parent)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(ICON, ICON)
        f.icon:SetPoint("LEFT", 6, 0)
        f.text = Text(f, UI.Font.body)
        f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
        f.text:SetPoint("RIGHT", -6, 0)
        return f
    end,
    set = function(f, node, w)
        f:SetSize(w, ROW_H)
        widgets.item.update(f, node)
        return ROW_H
    end,
    update = function(f, node)
        local text, icon = ItemText(node)
        f.text:SetText(text)
        f.icon:SetTexture(icon or 134400) -- the question-mark bag icon
    end,
    peek = function(f, node)
        local id = Num(node.id)
        if not id then return end
        TipBeside(f)
        GameTooltip:SetItemByID(id)
        GameTooltip:Show()
    end,
    onBlur = HideTip,
}

-- Quest: its name (the game's: asked for by ID when it doesn't know the quest yet, the spec's text until it
-- arrives) and a status.
local questAsked = {}
local function QuestStatus(id)
    if Conditions.Check({ quest = id, state = "done" }) then return "Turned in", UI.Color.dim end
    if Conditions.Check({ quest = id, state = "ready" }) then return "Ready to turn in", UI.Color.good end
    if Conditions.Check({ quest = id }) then return "In your log", UI.Color.gold end
    return "Not taken", UI.Color.dim
end

widgets.quest = {
    focus = function() return true end,
    actions = function() return { y = "peek" } end,
    make = function(parent)
        local f = Focusable(parent)
        f.mark = f:CreateTexture(nil, "ARTWORK")
        f.mark:SetSize(ICON, ICON)
        f.mark:SetPoint("LEFT", 6, 0)
        f.text = Text(f, UI.Font.body)
        f.text:SetPoint("LEFT", f.mark, "RIGHT", 8, 0)
        f.status = Text(f, UI.Font.small, "RIGHT")
        f.status:SetPoint("RIGHT", -8, 0)
        f.text:SetPoint("RIGHT", f.status, "LEFT", -8, 0)
        return f
    end,
    set = function(f, node, w)
        f:SetSize(w, ROW_H)
        widgets.quest.update(f, node)
        return ROW_H
    end,
    update = function(f, node)
        local id = Num(node.id)
        local name = id and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
        if id and not name and C_QuestLog.RequestLoadQuestByID and not questAsked[id] then
            questAsked[id] = true -- the game loads it and says so (QUEST_DATA_LOAD_RESULT, below)
            C_QuestLog.RequestLoadQuestByID(id)
        end
        f.text:SetText(name or node.text or ("Quest " .. tostring(id)))
        local status, color = "", nil
        if id then status, color = QuestStatus(id) end
        f.status:SetText((color and UI.Hex(color) or "") .. status .. (color and "|r" or ""))
        local done = id and Conditions.Check({ quest = id, state = "done" })
        local atlas = "QuestNormal"
        if id and not done then
            if Conditions.Check({ quest = id, state = "ready" }) then atlas = "QuestTurnin"
            elseif Conditions.Check({ quest = id }) then atlas = "Quest-In-Progress-Icon-yellow" end
        end
        if not f.mark:SetAtlas(atlas) then f.mark:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon") end
        f.mark:SetDesaturated(done and true or false)
    end,
    peek = function(f, node)
        local id = Num(node.id)
        if not id then return end
        TipBeside(f)
        if pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. id) and GameTooltip:NumLines() > 0 then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end,
    onBlur = HideTip,
}

-- Check: two looks, so it's clear who ticks it.
--   The game does (bind, or a fixed done): the quest tracker's own marks, a small minimal box that becomes
--   its check, as objectives tick off. Not focusable.
--   You do (toggle): the full check box, as in DeckKit's settings, ticked with A.
local function CheckDone(node)
    if node.bind then return Conditions.Check(node.bind) or false end
    return node.done and true or false
end

widgets.check = {
    fixed = function() return 30 end,
    focus = function(node) return node.toggle end,
    actions = function(node) return node.toggle and { a = "toggle" } or nil end,
    make = function(parent)
        local f = Focusable(parent)
        f.box = f:CreateTexture(nil, "ARTWORK")
        f.box:SetPoint("CENTER")
        f.check = f:CreateTexture(nil, "OVERLAY")
        f.check:SetPoint("CENTER")
        return f
    end,
    set = function(f, node)
        f:SetSize(30, ROW_H)
        f.box:Show()
        if node.toggle then
            f.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
            f.box:SetTexCoord(0, 1, 0, 1) -- (a reused frame may have had an atlas)
            f.box:SetSize(26, 26)
            f.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            f.check:SetTexCoord(0, 1, 0, 1)
            f.check:SetSize(26, 26)
        else
            if not f.box:SetAtlas("checkbox-minimal") then f.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up") end
            f.box:SetSize(16, 16)
            if not f.check:SetAtlas("Tracker-Check") then f.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") end
            f.check:SetSize(18, 18)
        end
        widgets.check.update(f, node)
        return ROW_H
    end,
    update = function(f, node)
        local done = CheckDone(node)
        f.check:SetShown(done)
        if not node.toggle then f.box:SetShown(not done) end -- the tracker's check replaces its box
    end,
}

-- Progress: a bar with "have/need", in the suite's purple (MarketDeck's bar lit, as a fill); full, lilac.
local PROGRESS = { 0.52, 0.30, 0.80 }
local function ProgressOf(node)
    if node.bind then
        local have, need = Conditions.Progress(node.bind)
        if have then return have, need end
        local done = Conditions.Check(node.bind)
        return done and 1 or 0, 1
    end
    return Num(node.value) or 0, math.max(1, Num(node.max) or 1)
end

widgets.progress = {
    make = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.label = Text(f, UI.Font.body)
        f.label:SetPoint("LEFT", 6, 0)
        f.track = CreateFrame("Frame", nil, f)
        f.track:SetHeight(14)
        local bg = f.track:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.6)
        local edge = CreateFrame("Frame", nil, f.track, "BackdropTemplate")
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        edge:SetBackdropBorderColor(0.45, 0.42, 0.35, 1)
        f.fill = f.track:CreateTexture(nil, "ARTWORK")
        f.fill:SetPoint("TOPLEFT")
        f.fill:SetPoint("BOTTOMLEFT")
        f.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.count = Text(f.track, UI.Font.small, "CENTER")
        f.count:SetPoint("CENTER", 0, 0)
        local font, size = f.count:GetFont()
        if font then f.count:SetFont(font, size, "OUTLINE") end -- a thin black edge: readable on the fill
        return f
    end,
    set = function(f, node, w)
        f:SetSize(w, ROW_H)
        f.track:ClearAllPoints()
        if node.text then
            f.label:SetText(Glyphs(tostring(node.text)))
            f.label:Show()
            f.track:SetPoint("RIGHT", -6, 0)
            f.track:SetWidth(math.max(80, w * 0.4))
            f.label:SetPoint("RIGHT", f.track, "LEFT", -8, 0)
        else
            f.label:Hide()
            f.track:SetPoint("LEFT", 6, 0)
            f.track:SetPoint("RIGHT", -6, 0)
        end
        widgets.progress.update(f, node)
        return ROW_H
    end,
    update = function(f, node)
        local have, need = ProgressOf(node)
        local frac = math.max(0, math.min(1, have / need))
        local tw = f.track:GetWidth() or 0
        f.fill:SetWidth(math.max(0.01, tw * frac))
        f.fill:SetShown(frac > 0)
        local c = frac >= 1 and ns.COLORS.LILAC or PROGRESS
        f.fill:SetVertexColor(c[1], c[2], c[3])
        f.count:SetText(math.min(have, need) .. " / " .. need)
    end,
}

-- Waypoint: the gold pin, its label, the zone and how far (live). A sets it, Y shows its map.
local function PointOf(node)
    local m, x, y = Num(node.map), Num(node.x), Num(node.y)
    if not (m and x and y) then return end
    node._p = node._p or { mapID = m, x = x / 100, y = y / 100 }
    return node._p
end

local function Distance(node)
    local p = PointOf(node)
    if not p then return "" end
    local g = ns.Waypoints.Guide(p)
    if g.state == "ok" then return string.format("%d yd", g.yards + 0.5) end
    if g.state == "far" then return "far" end
    return ""
end

widgets.waypoint = {
    focus = function() return true end,
    actions = function() return { a = "waypoint", y = "peek" } end,
    make = function(parent)
        local f = Focusable(parent)
        f.pin = f:CreateTexture(nil, "ARTWORK")
        f.pin:SetSize(20, 20)
        f.pin:SetPoint("LEFT", 7, 0)
        if not f.pin:SetAtlas("Waypoint-MapPin-Tracked") then f.pin:SetTexture("Interface\\Minimap\\POIIcons") end
        f.dist = Text(f, UI.Font.small, "RIGHT")
        f.dist:SetPoint("RIGHT", -8, 0)
        f.zone = Text(f, UI.Font.dim, "RIGHT")
        f.zone:SetPoint("RIGHT", f.dist, "LEFT", -10, 0)
        f.text = Text(f, UI.Font.body)
        f.text:SetPoint("LEFT", f.pin, "RIGHT", 8, 0)
        f.text:SetPoint("RIGHT", f.zone, "LEFT", -8, 0)
        return f
    end,
    set = function(f, node, w)
        f:SetSize(w, ROW_H)
        local m = Num(node.map)
        local zone = m and ns.Map.Name(m) or "?"
        f.text:SetText(node.label and Glyphs(tostring(node.label))
            or string.format("%.1f, %.1f", Num(node.x) or 0, Num(node.y) or 0))
        f.zone:SetText(node.label and zone or "")
        if not node.label then f.text:SetText(zone .. "  " .. UI.Hex(UI.Color.dim) .. f.text:GetText() .. "|r") end
        widgets.waypoint.update(f, node)
        return ROW_H
    end,
    update = function(f, node) f.dist:SetText(Distance(node)) end,
    peek = function(f, node) UI.ShowMap(node, f) end,
    onBlur = function() UI.HideMap() end,
}

widgets.button = {
    fixed = function(node) return Num(node.width) or 160 end,
    focus = function() return true end,
    make = function(parent)
        local f = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        f:SetNormalFontObject(UI.Font.body)
        f:SetHighlightFontObject(UI.Font.body)
        f:SetDisabledFontObject(UI.Font.dim)
        return f
    end,
    set = function(f, node)
        f:SetSize(Num(node.width) or 160, 28)
        f:SetText(Glyphs(tostring(node.text or "OK")))
        return 28
    end,
}

widgets.space = {
    fixed = function(node) return Num(node.width) end,
    make = function(parent) return CreateFrame("Frame", nil, parent) end,
    set = function(f, node, w)
        f:SetSize(math.max(1, w), 1)
        return 1
    end,
}

-- (Not for specs: the strip behind a row that lights up while any piece in it has focus.)
widgets.rowbg = {
    make = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.hl = f:CreateTexture(nil, "BACKGROUND")
        f.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        f.hl:SetBlendMode("ADD")
        f.hl:SetAllPoints()
        f.hl:SetAlpha(0.6)
        f.hl:Hide()
        return f
    end,
    set = function(f, node, w) f:SetSize(w, ROW_H) return ROW_H end,
}
local function RowLock(self) self.dkRow.hl:Show() end
local function RowUnlock(self) self.dkRow.hl:Hide() end

widgets.unknown = {
    make = widgets.text.make,
    set = function(f, node, w)
        return widgets.text.set(f, { text = "? " .. tostring(node.type or "(no type)"), style = "dim" }, w)
    end,
}

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------

local VERB = { waypoint = "Set waypoint", toggle = "Tick" }

local function Act(v)
    if type(v) == "string" then return { run = v } end
    if type(v) == "table" and v.run then return v end
    if type(v) == "table" and v.reply ~= nil then return { reply = v.reply, label = v.label } end
end

local function ActionsOf(def, node)
    local base = def.actions and def.actions(node) or {}
    local own = type(node.buttons) == "table" and node.buttons or {}
    local out = {}
    for _, k in ipairs({ "a", "x", "y" }) do
        local a = Act(own[k] ~= nil and own[k] or base[k])
        if a then out[k] = a end
    end
    return out
end

local function Label(a, node)
    if a.reply ~= nil then return a.label or "Choose" end
    if a.run == "peek" or a.run == "map" then return node.type == "waypoint" and "Map (hold)" or "Tooltip (hold)" end
    if a.run == "toggle" then return CheckDone(a.target or node) and "Untick" or "Tick" end
    return VERB[a.run] or a.run
end

-- The peek button let go, or the window closed while it was held.
local function EndPeek(f)
    peekOn = false
    if f then HideTip(f) end
    if GameTooltip:GetOwner() and GameTooltip:GetOwner().layout then GameTooltip:Hide() end
    UI.HideMap()
end

local function Run(f, a)
    local node, L = f.node, f.layout
    if a.reply ~= nil then
        if L.opts.onReply then L.opts.onReply(a.reply, node) end
    elseif a.run == "waypoint" then
        local p = PointOf(node)
        if p then
            ns.Waypoints.Add(p.mapID, p.x, p.y, node.label)
            ns.Print("Waypoint set: " .. (node.label and (node.label .. ", ") or "") .. ns.Map.Name(p.mapID) .. ".")
        end
    elseif a.run == "peek" or a.run == "map" then
        peekOn = true -- until the button is let go (EndPeek)
        local def = widgets[f.kind]
        if def.peek then def.peek(f, node) end
    elseif a.run == "toggle" then
        local t = a.target or node -- a row's check, ticked from the row's other piece
        t.done = not CheckDone(t)
        if L.opts.ticks then L.opts.ticks[t.key or t._path] = t.done end
        if L.opts.onChange then L.opts.onChange(t) end
    end
    L:Update()
end

------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------

local Layout = {}
Layout.__index = Layout

local function Get(kind, parent)
    local pool = pools[kind]
    local f = pool and table.remove(pool)
    if f then
        f:SetParent(parent)
    else
        f = (widgets[kind] or widgets.unknown).make(parent)
    end
    f.kind = kind
    f:ClearAllPoints()
    f:SetAlpha(1)
    f:Show()
    return f
end

-- One piece: made (or reused), filled in, joined to the d-pad order if it can be focused.
function Layout:Leaf(node, parent, w)
    local kind = widgets[node.type] and node.type or "unknown"
    local def = widgets[kind]
    local f = Get(kind, parent)
    f.node, f.layout = node, self
    local ticks = self.opts.ticks
    if node.toggle and ticks and ticks[node.key or node._path] ~= nil then node.done = ticks[node.key or node._path] end
    -- The window closing while the peek button is held: the peek ends with it.
    local side = Side(f)
    if not side.dkPeekHook then
        side.dkPeekHook = true
        side:HookScript("OnHide", function() if peekOn then EndPeek() end end)
    end
    local ok, h = pcall(def.set, f, node, w)
    if not ok then
        geterrorhandler()(h)
        h = widgets.unknown.set(f, node, w)
    end
    self.frames[#self.frames + 1] = f
    if def.update then self.live[#self.live + 1] = f end
    local acts = ActionsOf(def, node)
    -- In a row with the player's own check box, A on the row's other piece ticks it (as A anywhere on a
    -- settings row toggles its box), and the box isn't a stop of its own.
    local rowCheck = self.rowCheck
    if rowCheck and node ~= rowCheck and not acts.a then acts.a = { run = "toggle", target = rowCheck } end
    if rowCheck and node == rowCheck and self.rowCheckHasHost then acts = {} end
    local canFocus = next(acts) or (def.focus and def.focus(node) and not (node == rowCheck and self.rowCheckHasHost))
    if canFocus then
        UI.Register(f, {
            prompts = function()
                local p = {}
                for _, k in ipairs({ "a", "x", "y" }) do
                    if acts[k] then p[#p + 1] = { k == "a" and "A" or k:upper(), Label(acts[k], node) } end
                end
                return p
            end,
            activate = acts.a and function(self) Run(self, acts.a) end,
            x = acts.x and function(self) Run(self, acts.x) end,
            y = acts.y and function(self) Run(self, acts.y) end,
            onFocus = def.peek and function(self) if peekOn then def.peek(self, node) end end,
            release = {
                a = acts.a and (acts.a.run == "peek" or acts.a.run == "map") and EndPeek or nil,
                x = acts.x and (acts.x.run == "peek" or acts.x.run == "map") and EndPeek or nil,
                y = acts.y and (acts.y.run == "peek" or acts.y.run == "map") and EndPeek or nil,
            },
            onBlur = def.onBlur and function(self) def.onBlur(self, node) end,
            refresh = def.update and function(self) def.update(self, node) end,
        })
        f.registered = true
    end
    return f, h
end

local function Width(def, node)
    local fx = def.fixed
    if type(fx) == "function" then return fx(node) end
    return fx
end

-- Places node with its top-left at x, y (offsets in parent), w wide. Returns its height. path: where the
-- node sits in the spec ("1.3.2"), the key a player's tick is remembered by when the node has no `key`.
function Layout:Place(node, parent, x, y, w, path)
    if type(node) ~= "table" then return 0 end
    path = path or "1"
    node._path = path
    local t = node.type
    if t == "list" or t == "section" then
        local h = 0
        if t == "section" and node.title then
            local f, fh = self:Leaf({ type = "heading", text = node.title }, parent, w)
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            h = fh + 4
        end
        for i, child in ipairs(type(node.items) == "table" and node.items or {}) do
            local ch = self:Place(child, parent, x, y - h, w, path .. "." .. i)
            if ch > 0 then h = h + ch + GAP_Y end
        end
        if t == "section" then h = h + 8 end
        return h
    end
    if t == "row" then
        local kids = type(node.items) == "table" and node.items or {}
        local fixedW, flex = 0, 0
        for _, child in ipairs(kids) do
            if type(child) == "table" then
                local def = widgets[child.type]
                local cw = def and Width(def, child)
                if cw then fixedW = fixedW + cw else flex = flex + 1 end
            end
        end
        -- The player's own check in this row, and whether another piece can take its A.
        local rowCheck, host
        for _, child in ipairs(kids) do
            if type(child) == "table" and child.type == "check" and child.toggle then rowCheck = child end
        end
        if rowCheck then
            for _, child in ipairs(kids) do
                local def = type(child) == "table" and child ~= rowCheck and widgets[child.type]
                if def and (def.focus and def.focus(child) or def.actions) then host = true end
            end
        end
        local outerCheck, outerHost = self.rowCheck, self.rowCheckHasHost
        self.rowCheck, self.rowCheckHasHost = rowCheck, host
        local spare = w - fixedW - GAP_X * math.max(0, #kids - 1)
        local flexW = flex > 0 and math.max(40, spare / flex) or 0
        local placed, rowH, cx = {}, 0, x
        for i, child in ipairs(kids) do
            if type(child) == "table" then
                local def = widgets[child.type]
                local cw = (def and Width(def, child)) or flexW
                local f, ch
                child._path = path .. "." .. i
                if child.type == "row" or child.type == "list" or child.type == "section" then
                    ch = self:Place(child, parent, cx, y, cw, child._path) -- a container inside a row: its own column
                else
                    f, ch = self:Leaf(child, parent, cw)
                end
                placed[#placed + 1] = { f = f, x = cx, h = ch, node = child }
                rowH = math.max(rowH, ch)
                cx = cx + cw + GAP_X
            end
        end
        self.rowCheck, self.rowCheckHasHost = outerCheck, outerHost
        local row = { items = placed }
        local lit
        for _, p in ipairs(placed) do
            if p.f then p.f:SetPoint("TOPLEFT", parent, "TOPLEFT", p.x, y - math.floor((rowH - p.h) / 2)) end
            if p.node.type == "check" then row.check = p.node end
            if p.f and p.f.registered then lit = true end
        end
        -- Focus anywhere in the row lights the whole row (what A acts on may be across it: a row's check).
        if lit and #placed > 1 then
            local bg = Get("rowbg", parent)
            bg:SetSize(w, rowH)
            bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            bg:SetFrameLevel(math.max(0, parent:GetFrameLevel()))
            bg.hl:Hide()
            self.frames[#self.frames + 1] = bg
            for _, p in ipairs(placed) do
                if p.f and p.f.registered then
                    p.f.dkRow, p.f.LockHighlight, p.f.UnlockHighlight = bg, RowLock, RowUnlock
                end
            end
        end
        if row.check then self.rows[#self.rows + 1] = row end
        return rowH
    end
    local f, h = self:Leaf(node, parent, w)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return h
end

-- Live values: checks, progress, distances, item names that just arrived; rows with a ticked check
-- grayed.
function Layout:Update()
    for _, f in ipairs(self.live) do
        local def = widgets[f.kind]
        local ok, err = pcall(def.update, f, f.node)
        if not ok then geterrorhandler()(err) end
    end
    for _, row in ipairs(self.rows) do
        local done = CheckDone(row.check)
        for _, p in ipairs(row.items) do
            if p.f and p.node.type ~= "check" then p.f:SetAlpha(done and 0.5 or 1) end
        end
    end
    if self.screenRefresh then self.screenRefresh() end
end

function Layout:Release()
    active[self] = nil
    for _, f in ipairs(self.frames) do
        if f.registered then
            if f.dk and f.dk.onBlur then f.dk.onBlur(f) end
            UI.Unregister(f)
            f.registered, f.dk = nil, nil
        end
        f:Hide()
        f:ClearAllPoints()
        f.node, f.layout = nil, nil
        f.dkRow, f.LockHighlight, f.UnlockHighlight = nil, nil, nil -- back to the frame's own
        pools[f.kind] = pools[f.kind] or {}
        table.insert(pools[f.kind], f)
    end
    self.frames, self.live, self.rows = {}, {}, {}
    if self.scroll then self.scroll:Hide() end
    if self.footerBox then self.footerBox:Hide() end
end

function UI.Build(parent, spec, opts)
    opts = opts or {}
    local L = setmetatable({ opts = opts, frames = {}, live = {}, rows = {} }, Layout)
    local width = opts.width or parent:GetWidth()
    local host = parent
    -- spec.footer: kept under the scrolling part, always in view (an answer's buttons).
    L.footerH = 0
    local height = opts.height
    if type(spec) == "table" and type(spec.footer) == "table" then
        local box = parent.dkLayoutFooter
        if not box then
            box = CreateFrame("Frame", nil, parent)
            parent.dkLayoutFooter = box
        end
        box:SetSize(width, 1)
        box:Show()
        L.footerH = L:Place(spec.footer, box, 0, 0, width - 22, "footer")
        box:SetHeight(math.max(1, L.footerH))
        box:ClearAllPoints()
        if height then
            box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(height - L.footerH))
            height = height - L.footerH - 10
        end
        L.footerBox = box
    end
    if height then
        -- One scrolling list per parent, kept for the next build there.
        local sf = parent.dkLayoutScroll
        if not sf then
            sf = UI.ScrollList(parent, width, height)
            sf:SetPoint("TOPLEFT")
            parent.dkLayoutScroll = sf
        end
        sf:SetSize(width, height)
        sf.content:SetWidth(width - 18)
        sf:ScrollTo(0)
        sf:Show()
        host, width = sf.content, width - 18 - 4
        L.scroll = sf
    end
    L.height = L:Place(spec, host, 0, 0, width)
    if L.scroll then L.scroll:SetContentHeight(L.height) end
    if L.footerBox and not height then -- no scrolling: the footer goes right under the content
        L.footerBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(L.height + 10))
    end
    active[L] = true
    L:Update()
    return L
end

-- Live: the game changing (Conditions), item names arriving, and distances twice a second.
local function UpdateAll()
    for L in pairs(active) do L:Update() end
end
Conditions.OnChange(UpdateAll)
ns.On("GET_ITEM_INFO_RECEIVED", function() C_Timer.After(0, UpdateAll) end)
ns.On("QUEST_DATA_LOAD_RESULT", function() C_Timer.After(0, UpdateAll) end)
local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.5 then return end
    since = 0
    for L in pairs(active) do
        if #L.frames > 0 and L.frames[1]:IsVisible() then L:Update() end
    end
    UI.UpdateMap()
end)

------------------------------------------------------------------------
-- The map peek (hold Y on a waypoint): the zone's map centered on screen, over the window, with the
-- place's pin (and you, on the same map)
------------------------------------------------------------------------

local MAP_W = 620
local peek

local function MakePeek()
    peek = CreateFrame("Frame", "DeckKitMapPeek", UIParent)
    peek:SetFrameStrata("FULLSCREEN")
    peek:SetClampedToScreen(true)
    local bg = peek:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.035, 0.035, 0.045, 0.96)
    UI.Border(peek, "SimplePanelTemplate")
    peek.title = Text(peek, UI.Font.heading, "CENTER")
    peek.title:SetPoint("TOP", 0, -10)
    peek.clip = CreateFrame("Frame", nil, peek)
    peek.clip:SetPoint("TOPLEFT", 10, -32)
    peek.clip:SetPoint("BOTTOMRIGHT", -10, 10)
    peek.clip:SetClipsChildren(true)
    peek.art = CreateFrame("Frame", nil, peek.clip)
    peek.marks = CreateFrame("Frame", nil, peek.clip)
    peek.marks:SetAllPoints()
    peek.marks:SetFrameLevel(peek.art:GetFrameLevel() + 5)
    peek.pin = peek.marks:CreateTexture(nil, "OVERLAY")
    peek.pin:SetSize(32, 32)
    if not peek.pin:SetAtlas("Waypoint-MapPin-Tracked") then peek.pin:SetColorTexture(1, 0.82, 0, 1) end
    peek.me = peek.marks:CreateTexture(nil, "OVERLAY", nil, 1)
    peek.me:SetTexture("Interface\\Minimap\\MinimapArrow")
    peek.me:SetSize(28, 28)
    peek:Hide()
end

-- The zone's art on `art` (a frame sized in the map layer's pixels): its tiles, plus the explored-area
-- pieces Blizzard's map lays over the base art (without them it all looks unexplored). Returns the layer's
-- width and height, or nil for a map with no art. MapDeck and the map peek both draw with it.
local TILE = 256
function UI.DrawMapArt(art, mapID)
    art.dkTiles, art.dkOverlays = art.dkTiles or {}, art.dkOverlays or {}
    local function Pool(list, i, layer)
        local t = list[i]
        if not t then
            t = art:CreateTexture(nil, layer)
            list[i] = t
        end
        t:ClearAllPoints()
        t:Show()
        return t
    end
    local function HideFrom(list, n) for i = n, #list do list[i]:Hide() end end

    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if not layer then
        HideFrom(art.dkTiles, 1)
        HideFrom(art.dkOverlays, 1)
        return nil
    end
    local lw, lh = layer.layerWidth, layer.layerHeight
    local tw, th = layer.tileWidth or TILE, layer.tileHeight or TILE
    local wide, tall = math.ceil(lw / tw), math.ceil(lh / th)
    local files = C_Map.GetMapArtLayerTextures(mapID, 1) or {}
    local n = 0
    for row = 1, tall do
        for col = 1, wide do
            local file = files[(row - 1) * wide + col]
            if file then
                n = n + 1
                local t = Pool(art.dkTiles, n, "BACKGROUND")
                t:SetSize(tw, th)
                t:SetTexCoord(0, 1, 0, 1)
                t:SetPoint("TOPLEFT", (col - 1) * tw, -(row - 1) * th)
                t:SetTexture(file, nil, nil, "TRILINEAR")
            end
        end
    end
    HideFrom(art.dkTiles, n + 1)

    n = 0
    local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
        and C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}
    for _, info in ipairs(explored) do
        -- Some maps leave out the piece counts; they follow from the size (256-pixel tiles).
        local rows = info.numTexturesTall or math.ceil((info.textureHeight or 0) / TILE)
        local cols = info.numTexturesWide or math.ceil((info.textureWidth or 0) / TILE)
        if not info.isShownByMouseOver and info.fileDataIDs then
            for j = 1, rows do
                local ph, fh = TILE, TILE
                if j == rows then
                    ph = info.textureHeight % TILE
                    if ph == 0 then ph = TILE end
                    fh = 16
                    while fh < ph do fh = fh * 2 end
                end
                for k = 1, cols do
                    local pw, fw = TILE, TILE
                    if k == cols then
                        pw = info.textureWidth % TILE
                        if pw == 0 then pw = TILE end
                        fw = 16
                        while fw < pw do fw = fw * 2 end
                    end
                    local file = info.fileDataIDs[(j - 1) * cols + k]
                    if file then
                        n = n + 1
                        local t = Pool(art.dkOverlays, n, "BORDER")
                        t:SetSize(pw, ph)
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:SetPoint("TOPLEFT", info.offsetX + TILE * (k - 1), -(info.offsetY + TILE * (j - 1)))
                        t:SetTexture(file, nil, nil, "TRILINEAR")
                    end
                end
            end
        end
    end
    HideFrom(art.dkOverlays, n + 1)
    return lw, lh
end

-- The peek's map: the zone at MAP_W wide.
local function DrawArt(mapID)
    local lw, lh = UI.DrawMapArt(peek.art, mapID)
    if not lw then return false end
    local scale = (MAP_W - 20) / lw
    peek.art:SetSize(lw, lh)
    peek.art:SetScale(scale)
    peek.art:ClearAllPoints()
    peek.art:SetPoint("TOPLEFT")
    peek:SetSize(MAP_W, lh * scale + 42)
    return true
end

local function Mark(t, x, y)
    local w, h = peek.clip:GetWidth(), peek.clip:GetHeight()
    t:ClearAllPoints()
    t:SetPoint("CENTER", peek.clip, "TOPLEFT", x * w, -y * h)
    t:Show()
end

function UI.UpdateMap()
    if not (peek and peek:IsShown() and peek.node) then return end
    local p = PointOf(peek.node)
    local m, px, py = ns.Map.PlayerPosition()
    if m == p.mapID and px then
        Mark(peek.me, px, py)
        local facing = ns.Map.Facing()
        if facing then peek.me:SetRotation(facing) end
    else
        peek.me:Hide()
    end
end

function UI.ShowMap(node, beside)
    local p = PointOf(node)
    if not p then return end
    if not peek then MakePeek() end
    if not DrawArt(p.mapID) then UI.HideMap() return end
    peek.node = node
    peek.title:SetText(node.label or ns.Map.Name(p.mapID))
    peek:ClearAllPoints()
    peek:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    peek:Show()
    Mark(peek.pin, p.x, p.y)
    UI.UpdateMap()
end

function UI.HideMap()
    if peek then
        peek:Hide()
        peek.node = nil
    end
end

------------------------------------------------------------------------
-- A layout in a window of its own (an assistant's display): UI.ShowLayout(spec, opts)
------------------------------------------------------------------------
--   spec.width     how wide (default 560: room for tooltips beside it on the Deck's screen), 360-900
--   spec.height    the most it grows to (default 600); shorter content gets a shorter window
--   spec.title     the tab's label
--   opts.title     the window's title (whose display it is: "Decky")
--   opts.onReply, opts.onChange, opts.ticks    as for UI.Build
--   opts.onClose(why)   the display went: "closed" (the player, or combat), "replaced" (a new one)
-- Returns false in combat (windows can't take the pad then). A new display replaces the one up.

local win -- { screen, tab, L }

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function UI.ShowLayout(spec, opts)
    opts = opts or {}
    if InCombatLockdown() then return false end
    if not win then
        local screen = UI.NewScreen("DeckKitLayoutWindow", 560, 400, "")
        win = { screen = screen, tab = screen:AddTab("") }
        screen.win:HookScript("OnHide", function()
            local done = win.onClose
            win.onClose = nil
            if done then done("closed") end
        end)
    end
    local s, tab = win.screen, win.tab
    if win.L then win.L:Release() end
    local before = win.onClose
    win.onClose = opts.onClose
    if before and s.win:IsShown() then before("replaced") end
    local w = Clamp(Num(spec.width) or 560, 360, 900)
    local maxH = Clamp(Num(spec.height) or 600, 240, 700)
    s.title:SetText(opts.title or "DeckKit")
    tab.title = spec.title or "Details"
    s:LayoutTabs()
    local bodyW, bodyMax = w - 28, maxH - UI.SCREEN_CHROME
    local build = { width = bodyW, height = bodyMax, onReply = opts.onReply, onChange = opts.onChange, ticks = opts.ticks }
    local L = UI.Build(tab.frame, spec, build)
    -- Shorter than the most it may be: the window shrinks to fit (built again at that height).
    local need = L.height + (L.footerH > 0 and L.footerH + 10 or 0) + 4
    if need < bodyMax then
        L:Release()
        build.height = need
        L = UI.Build(tab.frame, spec, build)
        maxH = need + UI.SCREEN_CHROME
    end
    win.L = L
    s.win:SetSize(w, maxH)
    if s.win:IsShown() then s:SelectTab(1, true) else s:Show() end
    return true
end

function UI.HideLayout()
    if win and win.screen.win:IsShown() then win.screen:Hide() end
end
