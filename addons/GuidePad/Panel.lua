-- The guide panel: drawn like Forever's Objectives panel (Blizzard_ObjectiveTracker) and in its place. The
-- tracker's own art, fonts, colors and spacing: a primary header (the guide), a section header per part (the
-- step, along the way, your other quests), blocks of a yellow title and dashed lines, a check for what's done.
-- It takes no input, so it reads the same with a controller as the tracker does.
--
-- Numbers from Forever's FrameXML (Blizzard_ObjectiveTracker*.xml/.lua, 1.60.1): the panel is 260 wide, modules
-- start 38 below its top and sit 10 apart; a section header is 26 high (25 counted), its first block 10 below;
-- blocks are indented 20, 10 apart; lines 4 apart; a check is 16 px at the line's top left, -10, +2; a quest's POI
-- icon is 20 px, its top right at the title's top left, -7, +5.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local WIDTH, TOP_PAD, MODULE_GAP = 260, 38, 10
local HEADER_H, FIRST_BLOCK, BLOCK_X, BLOCK_GAP, LINE_GAP = 25, 10, 20, 10, 4
local BLOCK_W = WIDTH - BLOCK_X
local BOTTOM_ROOM = 180 -- keep clear of the crossbar at the bottom

local COLOR = {
    header = { 0.75, 0.61, 0 },  -- OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR (read from the client at build)
    normal = { 0.8, 0.8, 0.8 },
    now = { 1, 1, 1 },           -- NormalHighlight: the line to do now
    complete = { 0.6, 0.6, 0.6 },
}

local frame, headerText, headerCount
local pools = { header = {}, title = {}, line = {}, check = {}, poi = {} }
local used = { header = 0, title = 0, line = 0, check = 0, poi = 0 }

local function LineFont() return _G.ObjectiveTrackerLineFont or GameFontHighlight end
local function HeaderFont() return _G.ObjectiveTrackerHeaderFont or GameFontNormalMed2 or GameFontNormal end

local function Atlas(tex, name, useSize)
    if C_Texture.GetAtlasInfo(name) then tex:SetAtlas(name, useSize) return true end
end

------------------------------------------------------------------------
-- Pieces, reused each draw
------------------------------------------------------------------------

local function Acquire(kind, make)
    used[kind] = used[kind] + 1
    local p = pools[kind][used[kind]]
    if not p then
        p = make()
        pools[kind][used[kind]] = p
    end
    p:Show()
    return p
end

local function SectionHeader()
    return Acquire("header", function()
        local h = CreateFrame("Frame", nil, frame)
        h:SetSize(WIDTH, 26)
        local bg = h:CreateTexture(nil, "ARTWORK")
        bg:SetPoint("CENTER")
        Atlas(bg, "UI-QuestTracker-Secondary-Objective-Header", true)
        h.text = h:CreateFontString(nil, "OVERLAY")
        h.text:SetFontObject(HeaderFont())
        h.text:SetPoint("LEFT", 7, 0)
        h.text:SetWidth(200)
        h.text:SetJustifyH("LEFT")
        h.text:SetWordWrap(false)
        return h
    end)
end

local function Title()
    return Acquire("title", function()
        local fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(LineFont())
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWidth(BLOCK_W)
        fs:SetMaxLines(2)
        return fs
    end)
end

local function Line()
    return Acquire("line", function()
        local l = CreateFrame("Frame", nil, frame)
        l.dash = l:CreateFontString(nil, "OVERLAY")
        l.dash:SetFontObject(LineFont())
        l.dash:SetPoint("TOPLEFT", 0, 1)
        l.dash:SetText(QUEST_DASH or "- ")
        l.text = l:CreateFontString(nil, "OVERLAY")
        l.text:SetFontObject(LineFont())
        l.text:SetJustifyH("LEFT")
        l.text:SetJustifyV("TOP")
        l.text:SetPoint("TOPLEFT", l.dash, "TOPRIGHT", 0, 0)
        return l
    end)
end

local function Check(line)
    local c = Acquire("check", function()
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetSize(16, 16)
        if not Atlas(t, "ui-questtracker-tracker-check", false) then t:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") end
        return t
    end)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", line, "TOPLEFT", -10, 2)
end

-- The quest's icon left of its title, as the tracker's POI button looks (Blizzard_POIButton's art, drawn only: a
-- real POI button ties into gamepad focus and quest focus): a disc with "..." while in progress, with "?" once
-- ready to hand in; the map's "!" for a quest not taken yet.
local function QuestIcon(title, questID)
    local p = Acquire("poi", function()
        local f = CreateFrame("Frame", nil, frame)
        f:SetSize(20, 20)
        f.disc = f:CreateTexture(nil, "ARTWORK")
        f.disc:SetAllPoints()
        Atlas(f.disc, "UI-QuestPoi-QuestNumber", false)
        f.mark = f:CreateTexture(nil, "OVERLAY")
        f.mark:SetAllPoints()
        return f
    end)
    p:ClearAllPoints()
    p:SetPoint("TOPRIGHT", title, "TOPLEFT", -7, 5)
    local inLog = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)
    local ready = inLog and ((C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)) or C_QuestLog.IsComplete(questID))
    p.disc:SetShown(inLog and true or false)
    Atlas(p.mark, not inLog and "QuestNormal" or ready and "UI-QuestIcon-TurnIn-Normal" or "Quest-In-Progress-Icon-yellow", false)
end

local function ReleaseAll()
    for kind, list in pairs(pools) do
        for i = 1, used[kind] do list[i]:Hide() end
        used[kind] = 0
    end
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------

local y          -- distance from the panel's top to the next free spot
local limit      -- how far down the panel may go
local full       -- out of room: everything after is left out

local function Room(h)
    if full or y + h > limit then full = true return false end
    return true
end

local function AddSection(label)
    if not Room(HEADER_H + FIRST_BLOCK + 14) then return false end
    if y > TOP_PAD then y = y + MODULE_GAP end
    local h = SectionHeader()
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    h.text:SetText(label)
    y = y + HEADER_H + FIRST_BLOCK
    return true
end

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- One block: an optional yellow title, then lines. line: { text, done, now, plain, sub }
-- (plain: no dash, as a quest's "Ready for turn-in"; sub: a dim note under the line before).
local function AddBlock(title, lines, firstOfSection, questID)
    local need = (title and 14 or 0) + #lines * 16
    if not Room(math.min(need, 30)) then return false end
    if not firstOfSection then y = y + BLOCK_GAP end
    if title then
        local fs = Title()
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", BLOCK_X, -y)
        fs:SetText(title)
        SetColor(fs, COLOR.header)
        if questID then QuestIcon(fs, questID) end
        y = y + fs:GetStringHeight()
    end
    for i, ln in ipairs(lines) do
        if y + 14 > limit then full = true break end
        if title or i > 1 then y = y + LINE_GAP end
        local l = Line()
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", frame, "TOPLEFT", BLOCK_X + (ln.sub and 10 or 0), -y)
        l:SetWidth(BLOCK_W - (ln.sub and 10 or 0))
        -- The dash keeps its width when hidden (Blizzard's OBJECTIVE_DASH_STYLE_HIDE), so text lines up.
        l.dash:SetAlpha((ln.done or ln.plain or ln.sub) and 0 or 1)
        l.text:SetWidth(l:GetWidth() - l.dash:GetStringWidth())
        l.text:SetText(ln.text)
        local c = ln.done and COLOR.complete or (ln.sub and COLOR.complete) or (ln.now and COLOR.now) or COLOR.normal
        SetColor(l.text, c)
        SetColor(l.dash, c)
        local h = math.max(l.text:GetStringHeight(), 12)
        l:SetHeight(h)
        if ln.done then Check(l) end
        y = y + h
    end
    return true
end

-- Goals into blocks the way the tracker groups objectives under their quest: each quest's goals under its
-- title (where it first comes up), goals of no quest as plain lines.
local function GoalBlocks(goals)
    local blocks, byQuest = {}, {}
    local loose
    for _, g in ipairs(goals) do
        local line = { text = g.text, done = g.done, now = g.now, plain = g.info }
        local b
        if g.quest then
            b = byQuest[g.quest]
            if not b then
                b = { title = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(g.quest)) or g.questTitle, lines = {},
                      quest = g.quest }
                byQuest[g.quest] = b
                blocks[#blocks + 1] = b
            end
            loose = nil
        else
            if not loose then loose = { lines = {} } blocks[#blocks + 1] = loose end
            b = loose
        end
        b.lines[#b.lines + 1] = line
        if g.note and not g.done and not g.info then b.lines[#b.lines + 1] = { text = g.note, sub = true } end
    end
    return blocks
end

local function DrawBlocks(blocks)
    for i, b in ipairs(blocks) do
        if not AddBlock(b.title, b.lines, i == 1, b.quest) then return end
    end
end

-- The watched quests the guide part didn't already show, as the tracker shows them.
local function OtherQuests(shown)
    local blocks = {}
    local n = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
    for i = 1, n do
        local q = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if q and not shown[q] then
            local lines = {}
            if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q) or C_QuestLog.IsComplete(q) then
                lines[1] = { text = QUEST_WATCH_QUEST_READY or "Ready for turn-in", plain = true, done = false }
            else
                for _, o in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
                    if o.text and o.text ~= "" then lines[#lines + 1] = { text = o.text, done = o.finished } end
                end
            end
            blocks[#blocks + 1] = { title = C_QuestLog.GetTitleForQuestID(q) or ("Quest " .. q), lines = lines, quest = q }
        end
    end
    return blocks
end

------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------

function Panel.Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "GuidePadPanel", UIParent)
    frame:SetFrameStrata("LOW") -- the tracker's strata
    frame:SetWidth(WIDTH)
    frame:SetHeight(TOP_PAD)
    frame:EnableMouse(false)
    if OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR and OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR.GetRGB then
        COLOR.header = { OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR:GetRGB() }
    end
    -- The primary header: the guide's name, and where you are in it on the right.
    local head = CreateFrame("Frame", nil, frame)
    head:SetSize(WIDTH, 32)
    head:SetPoint("TOPLEFT")
    local bg = head:CreateTexture(nil, "ARTWORK")
    bg:SetPoint("CENTER")
    Atlas(bg, "ui-questtracker-primary-objective-header", true)
    headerText = head:CreateFontString(nil, "OVERLAY")
    headerText:SetFontObject(HeaderFont())
    headerText:SetPoint("LEFT", 7, 0)
    headerText:SetWidth(190)
    headerText:SetJustifyH("LEFT")
    headerText:SetWordWrap(false)
    headerCount = head:CreateFontString(nil, "OVERLAY")
    headerCount:SetFontObject(LineFont())
    headerCount:SetPoint("RIGHT", -10, 0)
    SetColor(headerCount, COLOR.normal)
    frame:Hide()
    return frame
end

-- Where the tracker sits on the Deck, by value (1280 x 800 UI units, measured on Ben's priest 2026-11-17):
-- right edge 5 from the screen's, top 286 down, just under DeckHUD's minimap. Not read from the tracker
-- itself: a character with no quests has it hidden, somewhere else.
local RIGHT, TOP = 5, 286
function Panel.Place()
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -RIGHT, -TOP)
end

-- Draw a ForeverGuide view (nil: nothing to show).
function Panel.Draw(view, showQuests)
    Panel.Build()
    ReleaseAll()
    if not view then frame:Hide() return end
    Panel.Place()
    local top = frame:GetTop()
    limit = top and (top - BOTTOM_ROOM) or 500
    y, full = TOP_PAD, false

    headerText:SetText(view.guideTitle or "Guide")
    headerCount:SetText(view.stepNumber and (view.stepNumber .. "/" .. view.steps) or "")

    local shown = {}
    if view.finished then
        AddSection("Guide finished")
        AddBlock(nil, { { text = "No next guide for your character here. Pick one in the DeckKit menu (Quests).", plain = true } }, true)
    else
        AddSection(view.title or ("Step " .. (view.stepNumber or "")))
        local blocks = GoalBlocks(view.goals or {})
        if view.note then table.insert(blocks, 1, { lines = { { text = view.note, plain = true } } }) end
        DrawBlocks(blocks)
        for _, g in ipairs(view.goals or {}) do if g.quest then shown[g.quest] = true end end
        if #view.along > 0 and AddSection("Along the way") then
            DrawBlocks(GoalBlocks(view.along))
            for _, g in ipairs(view.along) do if g.quest then shown[g.quest] = true end end
        end
    end
    if showQuests then
        local others = OtherQuests(shown)
        if #others > 0 and AddSection(TRACKER_HEADER_QUESTS or "Quests") then DrawBlocks(others) end
    end
    frame:SetHeight(y)
    frame:Show()
end

function Panel.Hide() if frame then frame:Hide() end end
function Panel.Shown() return frame and frame:IsShown() end
