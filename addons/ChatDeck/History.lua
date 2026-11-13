-- Chat history across reloads. Forever starts every chat tab empty after a /reload or login, so the
-- last lines of each tab are kept (per character, in ChatDeckHistory) and put back into the real
-- chat frames when the UI loads, under a gray divider with the time they were saved. The chat peek
-- copies from the chat frames, so it shows them too.
--
-- Lines are kept with their color and link text, so names and items stay clickable. Not kept: lines
-- the game marks secret, Battle.net name tokens (|K...|k, which only mean something in the session
-- that made them), and the combat log. Adding lines to a chat frame is ordinary addon work; the chat
-- *edit box* is never touched (that's what taints chat; see DeckHUD/Chat.lua).
--
-- Menu: Chat > Chat history > "Keep chat across reloads" (on by default) and "Clear saved chat".
local ADDON, ns = ...

local KEEP = 200 -- lines per chat tab
local restoring = false

local function On() return not (ChatDeckDB and ChatDeckDB.history == false) end

local function Store()
    ChatDeckHistory = ChatDeckHistory or {}
    ChatDeckHistory.frames = ChatDeckHistory.frames or {}
    return ChatDeckHistory
end

local function Keepable(msg)
    if type(msg) ~= "string" or msg == "" then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    return not msg:find("|K", 1, true)
end

local function Remember(i, msg, r, g, b)
    if restoring or not On() or not Keepable(msg) then return end
    local frames = Store().frames
    local lines = frames[i] or {}
    frames[i] = lines
    lines[#lines + 1] = { msg, r or 1, g or 1, b or 1 }
    if #lines > KEEP then table.remove(lines, 1) end
end

-- The combat log is its own world (huge, and rebuilt from the combat log itself).
local function IsChatTab(cf)
    if not (cf and cf.AddMessage) then return false end
    if IsCombatLog then return not IsCombatLog(cf) end
    return cf ~= ChatFrame2
end

local function Restore()
    local store = ChatDeckHistory
    if not (On() and store and store.frames) then return end
    local when = store.saved and date("%I:%M %p", store.saved):gsub("^0", "")
    restoring = true
    for i, lines in pairs(store.frames) do
        local cf = _G["ChatFrame" .. i]
        if IsChatTab(cf) and #lines > 0 then
            for _, line in ipairs(lines) do
                pcall(cf.AddMessage, cf, line[1], line[2], line[3], line[4])
            end
            cf:AddMessage("—— earlier chat" .. (when and (", saved " .. when) or "") .. " ——", 0.5, 0.5, 0.5)
        end
    end
    restoring = false
end

function ns.ClearChatHistory()
    ChatDeckHistory = { frames = {} }
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGOUT") -- also fires on /reload, just before saved variables are written
loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        -- The saved lines go in first, before anything new arrives; then every new line is kept.
        Restore()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if IsChatTab(cf) then
                hooksecurefunc(cf, "AddMessage", function(_, msg, r, g, b) Remember(i, msg, r, g, b) end)
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        if On() then Store().saved = time() else ChatDeckHistory = nil end
    end
end)

ns.AddSettings({
    { type = "section", tab = "Chat", label = "Chat history", order = 3 },
    { type = "toggle", label = "Keep chat across reloads",
      hint = "The last " .. KEEP .. " lines of each chat tab come back after a reload or login (and in the "
          .. "chat peek), under a gray line with the time they were saved. Kept per character, in your "
          .. "WoW folder's saved variables.",
      get = function() return On() end,
      set = function(on) ChatDeckDB.history = on and nil or false; if not on then ns.ClearChatHistory() end end },
    { type = "action", label = "Clear saved chat", verb = "Clear",
      hint = "Forgets the chat lines kept for after a reload. What's in the chat window now stays.",
      run = function() ns.ClearChatHistory(); ns.Print("saved chat cleared.") end },
})
