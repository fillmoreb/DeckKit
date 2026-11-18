-- Taking from the mail, one thing at a time as the game allows (a take waits until the last one has gone through:
-- C_Mail.IsCommandPending): a mail's money, then its items, then the next mail's. For one mail (X) or the whole inbox
-- (Y, Take all). COD mail is skipped (paying is a choice, made in the mail itself), and it stops when your bags are
-- full. A mail can vanish once emptied and the list closes up, so one mail is followed by what it is (sender, subject,
-- days left), not its place in the list.
local _, ns = ...

local Take = {}
ns.Take = Take
MailPadTakeForTests = Take -- tests/test_mailpad_take.lua

local STEP = 0.2       -- seconds between takes
local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 16

local job -- { mail = identity or nil (all), money, items, mails = { identities seen }, skippedCOD }

local function Identity(i)
    local _, _, sender, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
    if not sender and not subject then return nil end
    return (sender or "?") .. "\1" .. (subject or "") .. "\1" .. string.format("%.2f", daysLeft or 0)
end

-- Where a mail is in the list now, by what it is; nil once it's gone.
local function Find(identity)
    for i = 1, GetInboxNumItems() do
        if Identity(i) == identity then return i end
    end
end

-- The next thing to take: a function doing it, or nil when there's nothing left.
local function NextTake()
    local first, last = 1, GetInboxNumItems()
    if job.mail then
        local i = Find(job.mail)
        if not i then return nil end
        first, last = i, i
    end
    for i = first, last do
        local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
        local id = Identity(i)
        if cod and cod > 0 then
            if not job.skipped[id] then job.skipped[id] = true; job.skippedCOD = job.skippedCOD + 1 end
        elseif money and money > 0 then
            return function()
                job.mails[id] = true
                job.money = job.money + money
                TakeInboxMoney(i)
            end
        elseif hasItem then
            for a = 1, MAX_ATTACH do
                local name, _, _, count = GetInboxItem(i, a)
                if name then
                    return function()
                        job.mails[id] = true
                        job.items = job.items + (count or 1)
                        TakeInboxItem(i, a)
                    end
                end
            end
        end
    end
end

local function Finish(why)
    if not job then return end
    local mails = 0
    for _ in pairs(job.mails) do mails = mails + 1 end
    local parts = {}
    if job.money > 0 then parts[#parts + 1] = ns.Money(job.money) end
    if job.items > 0 then parts[#parts + 1] = job.items .. " item" .. (job.items == 1 and "" or "s") end
    local took = #parts > 0 and ("Took " .. table.concat(parts, " and ") .. " from " .. mails .. " mail"
        .. (mails == 1 and "" or "s") .. ".") or "Nothing to take."
    if job.skippedCOD > 0 then took = took .. " " .. job.skippedCOD .. " COD mail left alone." end
    if why then took = took .. " " .. why end
    ns.Print(took)
    job = nil
    if ns.InboxChanged then ns.InboxChanged() end
end

local function Step()
    if not job then return end
    if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
        C_Timer.After(STEP, Step)
        return
    end
    local take = NextTake()
    if not take then Finish() return end
    take()
    if ns.InboxChanged then ns.InboxChanged() end
    C_Timer.After(STEP, Step)
end

-- Take everything from one mail (its index in the list now), or from every mail (nil).
function Take.Start(index)
    if job then return false end
    local mail = index and Identity(index)
    if index and not mail then return false end
    job = { mail = mail, money = 0, items = 0, mails = {}, skipped = {}, skippedCOD = 0 }
    Step()
    return true
end

function Take.Running() return job ~= nil end

function Take.Stop(why)
    if job then Finish(why) end
end

-- A full bag stops it, saying how many mails still hold something.
ns.On("UI_ERROR_MESSAGE", function(_, message)
    if job and message == ERR_INV_FULL then Take.Stop("Your bags are full.") end
end)
