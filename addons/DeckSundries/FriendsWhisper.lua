-- Friends whisper: in the friends list (Forever's Social window), Y on a friend makes them your
-- reply target, so the next /r (or "reply ..." by dictation) whispers them.
--
-- Why the reply target and not opening a whisper: in controller mode, opening the chat box moves
-- the controller focus (SetPreferredGamepadInteractTarget), which only Blizzard's own code may do,
-- and dictation tools paste their own channel prefix (/s ...) over whatever mode the box was in.
-- The reply target is just remembered, and /r turns it into a whisper itself. The next whisper you
-- receive takes the reply target back, as usual.
--
-- Forever's controller navigation (the SmartNavigation object) knows which button the cursor is on;
-- a friend card's element data holds its friend: accountInfo for Battle.net friends, friendIndex for
-- character friends. Y is only watched, never taken (it does nothing else in that window).
local _, ns = ...

-- The friend under the cursor: chat type, whisper target, display label (or nil).
local function CurrentFriend()
    local nav = _G.SmartNavigation
    if not (nav and nav.GetCurrentButton) then return end
    local ok, button = pcall(nav.GetCurrentButton, nav)
    if not (ok and button and button.GetElementData) then return end
    local node = button:GetElementData()
    local data = type(node) == "table" and (node.data or node)
    if type(data) ~= "table" then return end
    local account = data.accountInfo
    if type(account) == "table" and account.accountName then
        return "BN_WHISPER", account.accountName, account.accountName
    end
    local info = data.friendInfo or data.info
    if type(info) ~= "table" and data.friendIndex and C_FriendList and C_FriendList.GetFriendInfoByIndex then
        info = C_FriendList.GetFriendInfoByIndex(data.friendIndex)
    end
    if type(info) == "table" and info.name then return "WHISPER", info.name, info.name end
end

local function SetReplyTarget()
    local chatType, target, label = CurrentFriend()
    if not chatType then return end
    local set = (ChatFrameUtil and ChatFrameUtil.SetLastTellTarget) or _G.ChatEdit_SetLastTellTarget
    if not set then
        ns.Debug("no SetLastTellTarget")
        return
    end
    set(target, chatType)
    ns.Debug("reply target", chatType, label)
    ns.Notice("Reply goes to " .. label, 3)
end

-- Watch Y while the Social window is open.
local wasDown = false
CreateFrame("Frame"):SetScript("OnUpdate", function()
    local social = _G.SocialUIFrame
    if ns.db.friendsWhisper == false or not (social and social:IsShown()) or not IsKeyDown then
        wasDown = false
        return
    end
    local down = IsKeyDown("PAD4")
    if down and not wasDown then SetReplyTarget() end
    wasDown = down
end)

ns.AddSettings({
    { type = "section", tab = "Controls", label = "Buttons", order = 2 },
    { type = "toggle", label = "Y sets reply in the friends list",
      hint = "Y on a friend makes them your reply target: /r (or dictating \"reply ...\") whispers them.",
      get = function() return ns.db.friendsWhisper ~= false end,
      set = function(on) ns.db.friendsWhisper = on end },
})
