-- DeckKit.People: who you've been dealing with, from DeckKit.Ledger (whispers, chat, trades, party invites; kept in
-- memory only) plus your group and your player target, read live. For turning "the guy who just gave me a linen bag"
-- or a misheard "Jesse" into a real name, and for acting on them.
--
--   People.Recent(kinds [, seconds])   a list of { kind, name, t, ... }, one per person and kind (their latest),
--                                      newest first, chat last (so busy chat can't push the rest out of a cut list).
--                                      kinds: a set of "whisper", "bnet", "chat", "trade", "invite", "group",
--                                      "target" (nil: all). seconds overrides each kind's window (whispers and trades
--                                      30 min, chat 2, invites 10). Group and target entries have t = nil (now).
--   People.Invite(name)                a party invite: true, or nil and why not (not the leader, full)
local _, ns = ...

local P = {}
ns.People = P
local L = ns.Ledger
local Readable = ns.Readable

local WINDOW = { whisper = 1800, bnet = 1800, chat = 120, trade = 1800, invite = 600 }

local function Me() return UnitName("player") end

local function Live(want, out)
    if want.group and IsInGroup() then
        local raid = IsInRaid()
        for i = 1, raid and 40 or 4 do
            local unit = (raid and "raid" or "party") .. i
            local name, realm = UnitName(unit)
            if Readable(name) and name and name ~= Me() then
                if Readable(realm) and realm and realm ~= "" then name = name .. "-" .. realm end
                out[#out + 1] = { kind = "group", name = L.Short(name),
                                  leader = UnitIsGroupLeader and UnitIsGroupLeader(unit) or false }
            end
        end
    end
    if want.target and UnitExists("target") and UnitIsPlayer("target") then
        local name, realm = UnitName("target")
        if Readable(name) and name and name ~= Me() then
            if Readable(realm) and realm and realm ~= "" then name = name .. "-" .. realm end
            out[#out + 1] = { kind = "target", name = L.Short(name) }
        end
    end
end

function P.Recent(kinds, seconds)
    local want = kinds
    if not want then
        want = {}
        for k in pairs(WINDOW) do want[k] = true end
        want.group, want.target = true, true
    end
    local now, seen, out = GetServerTime(), {}, {}
    for _, e in ipairs(L.Events(nil, 1800)) do
        local window = WINDOW[e.kind]
        if window and want[e.kind] and now - e.t <= (seconds or window) then
            local key = e.kind .. "\0" .. e.name
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = e
            end
        end
    end
    Live(want, out)
    table.sort(out, function(a, b)
        if (a.kind == "chat") ~= (b.kind == "chat") then return b.kind == "chat" end
        local at, bt = a.t or math.huge, b.t or math.huge
        if at ~= bt then return at > bt end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.name < b.name
    end)
    return out
end

function P.Invite(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" or name:find("[%c|]") then return nil, "no name" end
    if IsInGroup() and not (UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
        return nil, "you're not the group leader"
    end
    if IsInGroup() and not IsInRaid() and (GetNumGroupMembers() or 0) >= 5 then return nil, "your group is full" end
    local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    if not invite then return nil, "this client can't invite" end
    invite(name)
    return true
end
