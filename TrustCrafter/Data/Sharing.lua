-- TrustCrafter - guild sharing: what your guild's orders with a crafter
-- were like, checked against the crafter's own log.
--
-- Ask the guild, answer by whisper:
--   1. You look a crafter up (history window, /tc lookup, the personal
--      order name box, a My Orders row). If sharing is on, your addon asks
--      the guild once: "anyone have orders with Thalric-Draenor?"
--   2. Each guild member with orders from Thalric whispers their facts back
--      (outcome, quality asked for and received, time taken, order type,
--      tags and notes not marked private). Replies come straight from their
--      author, and the server vouches for the sender: nothing is relayed.
--   3. Then, if Thalric is online and runs TrustCrafter, your addon asks
--      Thalric about those order IDs. Thalric's crafted log (Data/Crafted.lua)
--      answers with the quality delivered for each one it has, so every
--      shared order shows as:
--        CONFIRMED   the crafter's log says the same quality
--        DISPUTED    the crafter's log says a different quality
--        NORECORD    the crafter answered but has no record of it
--        (nothing)   one-sided: the crafter didn't answer
--      Your own orders with Thalric are checked the same way.
--
-- Sharing is off by default (settings.share). Confirming is on by default
-- (settings.confirm): it only tells a customer about their own order, or
-- repeats a fact a guild member already shared.
--
-- Kept per realm:
--   shared[crafter][author] = { at, o = { [orderID] = fact, ... } }
--   confirm[orderID] = { s = status, q = quality in the crafter's log, at }

local _, ns = ...
local Util = ns.Util

local Sharing = {}
ns.Sharing = Sharing

local ASK_EVERY = 10 * 60           -- per crafter
local REPLY_WAIT = 4                -- seconds to collect replies before confirming
local ASK_TIMEOUT = 60
local MAX_FACTS = 30                -- newest orders per reply
local MAX_CONFIRM = 60              -- order IDs per confirmation request
local CONFIRM_EVERY = 10 * 60       -- per crafter
local NOTE_MAX = 200

local ANSWER_EVERY = 60             -- per person asking a crafter to confirm

local askedAt = {}                  -- crafter -> time
local answeredAt = {}               -- person -> time
local confirmAskedAt = {}           -- crafter -> time
local pending = {}                  -- request id -> { crafter, at }
local confirmTimers = {}            -- crafter -> timer
local nextID = 0

local function Settings() return ns.db and ns.db.settings or {} end

function Sharing:Enabled()
    return Settings().share == true and ns.Comm:Available()
end

local function InGuild()
    return IsInGuild and IsInGuild() or false
end

-- Whether a "Name-Realm" is in your guild. When the game can't say, only
-- replies to one of our own requests are accepted anyway.
local function IsGuildMember(fullName)
    if C_GuildInfo and C_GuildInfo.MemberExistsByName then
        local ok, exists = pcall(C_GuildInfo.MemberExistsByName, fullName)
        if ok and exists ~= nil then return exists end
        ok, exists = pcall(C_GuildInfo.MemberExistsByName, Util.ShortName(fullName))
        if ok and exists ~= nil then return exists end
    end
    return true
end

local function Realm() return ns:RealmData() end

-- One fact about an order you placed, as shared with your guild.
function Sharing.Fact(record)
    local fact = {
        o = record.outcome,
        a = record.minQuality,
        q = record.delivered,
        ty = record.orderType,
        at = record.completedAt,
        t = ns.Ledger.Turnaround(record),
    }
    if not record.private then
        if record.tags and next(record.tags) then
            fact.g = {}
            for tag in pairs(record.tags) do fact.g[#fact.g + 1] = tag end
            table.sort(fact.g)
        end
        if type(record.note) == "string" and record.note ~= "" then fact.n = record.note:sub(1, NOTE_MAX) end
    end
    return fact
end

-- Your filled orders from a crafter, newest first, as { [orderID] = fact }.
-- Orders one of your own characters crafted are never shared.
function Sharing:MyFacts(crafter)
    local list = {}
    for id, record in pairs(Realm().orders) do
        if record.crafter == crafter and record.state == "FILLED" and not record.ownCraft
            and not ns.Ledger:IsMine(record.crafter) then
            list[#list + 1] = { id = id, record = record }
        end
    end
    table.sort(list, function(a, b) return (a.record.completedAt or 0) > (b.record.completedAt or 0) end)
    local facts, count = {}, 0
    for i = 1, math.min(#list, MAX_FACTS) do
        facts[list[i].id] = Sharing.Fact(list[i].record)
        count = count + 1
    end
    return facts, count
end

-- Cleans a fact received from someone else: only known fields, right types.
local OUTCOMES = { MET = true, EXCEEDED = true, BELOW = true }
local TYPES = { PUBLIC = true, GUILD = true, PERSONAL = true }
local TAGS = { FAST = true, FRIENDLY = true, OWN_MATS = true, AGAIN = true, SLOW = true }

function Sharing.CleanFact(fact)
    if type(fact) ~= "table" or not OUTCOMES[fact.o] then return nil end
    local clean = { o = fact.o }
    if type(fact.a) == "number" then clean.a = math.floor(fact.a) end
    if type(fact.q) == "number" then clean.q = math.floor(fact.q) end
    if TYPES[fact.ty] then clean.ty = fact.ty end
    if type(fact.at) == "number" then clean.at = fact.at end
    if type(fact.t) == "number" and fact.t >= 0 then clean.t = fact.t end
    if type(fact.g) == "table" then
        for _, tag in ipairs(fact.g) do
            if TAGS[tag] then
                clean.g = clean.g or {}
                clean.g[#clean.g + 1] = tag
            end
        end
    end
    if type(fact.n) == "string" and fact.n ~= "" then clean.n = fact.n:sub(1, NOTE_MAX) end
    return clean
end

-- Asking -------------------------------------------------------------------

local function ScheduleConfirm(crafter)
    if confirmTimers[crafter] then confirmTimers[crafter]:Cancel() end
    confirmTimers[crafter] = C_Timer.NewTimer(REPLY_WAIT, function()
        confirmTimers[crafter] = nil
        Sharing:AskCrafter(crafter)
    end)
end

-- Asks the guild about a crafter ("Name-Realm"), at most every ASK_EVERY.
-- Returns true when a question went out.
function Sharing:Ask(crafter, now)
    if not crafter or not self:Enabled() then return false end
    now = now or Util.Now()
    if askedAt[crafter] and now - askedAt[crafter] < ASK_EVERY then return false end
    askedAt[crafter] = now
    if InGuild() then
        nextID = nextID + 1
        local id = tostring(nextID) .. "-" .. tostring(now)
        pending[id] = { crafter = crafter, at = now }
        ns.Comm:Send("ask", { id = id, c = crafter }, "GUILD")
    end
    -- Your own orders get checked against the crafter's log either way.
    ScheduleConfirm(crafter)
    return true
end

-- Order IDs to check with the crafter: yours and those shared with you
-- that the crafter hasn't answered for yet.
function Sharing:Unconfirmed(crafter)
    local ids, seen = {}, {}
    local confirm = Realm().confirm
    local function Add(id)
        if not seen[id] and not confirm[id] and #ids < MAX_CONFIRM then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local mine = self:MyFacts(crafter)
    for id in pairs(mine) do Add(id) end
    for _, entry in pairs(Realm().shared[crafter] or {}) do
        for id in pairs(entry.o) do Add(id) end
    end
    table.sort(ids)
    return ids
end

-- Asks the crafter to check order IDs against their log, when they look
-- online (a whisper to someone offline shows an error in chat).
function Sharing:AskCrafter(crafter, now)
    if not self:Enabled() then return false end
    now = now or Util.Now()
    if confirmAskedAt[crafter] and now - confirmAskedAt[crafter] < CONFIRM_EVERY then return false end
    local ids = self:Unconfirmed(crafter)
    if #ids == 0 then return false end
    if ns.Presence:Get(ns.Presence:GuidFor(crafter), crafter) ~= "online" then return false end
    confirmAskedAt[crafter] = now
    ns.Comm:Send("cfq", { c = crafter, ids = ids }, "WHISPER", crafter)
    return true
end

-- Answering ------------------------------------------------------------------

-- Someone in your guild asks about a crafter: whisper back your facts.
ns.Comm:On("ask", function(p, sender, channel)
    if channel ~= "GUILD" or not Sharing:Enabled() or type(p) ~= "table" then return end
    if type(p.c) ~= "string" or type(p.id) ~= "string" then return end
    local crafter = Util.FullName(p.c)
    if not crafter or crafter == sender then return end
    local facts, count = Sharing:MyFacts(crafter)
    if count == 0 then return end
    ns.Comm:Send("rep", { id = p.id, c = crafter, o = facts }, "WHISPER", sender)
end)

-- A reply to one of our questions.
ns.Comm:On("rep", function(p, sender, channel)
    if channel ~= "WHISPER" or not Sharing:Enabled() or type(p) ~= "table" then return end
    local request = type(p.id) == "string" and pending[p.id]
    if not request or Util.Now() - request.at > ASK_TIMEOUT then return end
    if Util.FullName(p.c) ~= request.crafter or sender == request.crafter then return end
    if not IsGuildMember(sender) or type(p.o) ~= "table" then return end
    local facts, count = {}, 0
    for id, fact in pairs(p.o) do
        local clean = type(id) == "string" and id:match("^%d+$") and Sharing.CleanFact(fact)
        if clean and count < MAX_FACTS then
            facts[id] = clean
            count = count + 1
        end
    end
    if count == 0 then return end
    local shared = Realm().shared
    shared[request.crafter] = shared[request.crafter] or {}
    shared[request.crafter][sender] = { at = Util.Now(), o = facts }
    ns.Events:Fire("TC_SHARED_CHANGED", request.crafter)
    ScheduleConfirm(request.crafter)
end)

-- Someone asks you, the crafter, about orders: answer from your crafted log.
-- Only IDs you have are answered, with the quality you delivered; the rest
-- are listed as unknown so the asker can tell "no record" from "no answer".
ns.Comm:On("cfq", function(p, sender, channel)
    if channel ~= "WHISPER" or Settings().confirm == false or type(p) ~= "table" then return end
    if type(p.ids) ~= "table" or not ns.Ledger:IsMine(Util.FullName(p.c)) then return end
    -- Only the quality delivered is ever answered, never who the order was
    -- for, and at most once a minute per person.
    local now = Util.Now()
    if answeredAt[sender] and now - answeredAt[sender] < ANSWER_EVERY then return end
    answeredAt[sender] = now
    local known, unknown = {}, {}
    for i, id in ipairs(p.ids) do
        if i > MAX_CONFIRM then break end
        if type(id) == "string" then
            local record = ns.Crafted:Get(id)
            if record and record.delivered then
                known[id] = record.delivered
            else
                unknown[#unknown + 1] = id
            end
        end
    end
    ns.Comm:Send("cfa", { c = p.c, k = known, u = unknown }, "WHISPER", sender)
end)

-- The crafter's answer.
ns.Comm:On("cfa", function(p, sender, channel)
    if channel ~= "WHISPER" or type(p) ~= "table" then return end
    local crafter = Util.FullName(p.c)
    if crafter ~= sender or not confirmAskedAt[crafter] then return end
    local confirm, now = Realm().confirm, Util.Now()
    local expected = {}
    local mine = Sharing:MyFacts(crafter)
    for id, fact in pairs(mine) do expected[id] = { fact } end
    for _, entry in pairs(Realm().shared[crafter] or {}) do
        for id, fact in pairs(entry.o) do
            expected[id] = expected[id] or {}
            expected[id][#expected[id] + 1] = fact
        end
    end
    for id, quality in pairs(type(p.k) == "table" and p.k or {}) do
        if expected[id] and type(quality) == "number" then
            local same = true
            for _, fact in ipairs(expected[id]) do
                if fact.q and fact.q ~= quality then same = false end
            end
            confirm[id] = { s = same and "CONFIRMED" or "DISPUTED", q = quality, at = now }
        end
    end
    for _, id in ipairs(type(p.u) == "table" and p.u or {}) do
        if expected[id] then confirm[id] = { s = "NORECORD", at = now } end
    end
    ns.Events:Fire("TC_SHARED_CHANGED", crafter)
end)

-- Reading ------------------------------------------------------------------------

function Sharing:Confirmation(orderID)
    local c = ns.db and Realm().confirm[orderID]
    return c and c.s or nil
end

-- What your guild shared about a crafter, counted by people, not orders:
-- { people, orders, metOrBetter, below, confirmed, disputed, avgTurnaround }
-- or nil. Your own orders aren't included; they're shown as yours.
function Sharing:Summary(crafter)
    local entries = ns.db and Realm().shared[crafter]
    if not entries then return nil end
    local s = { people = 0, orders = 0, metOrBetter = 0, below = 0, confirmed = 0, disputed = 0 }
    local timeSum, timeCount = 0, 0
    local confirm = Realm().confirm
    for author, entry in pairs(entries) do
        if not ns.Ledger:IsMine(author) and next(entry.o) then
            s.people = s.people + 1
            for id, fact in pairs(entry.o) do
                s.orders = s.orders + 1
                if fact.o == "BELOW" then s.below = s.below + 1 else s.metOrBetter = s.metOrBetter + 1 end
                local c = confirm[id]
                if c and c.s == "CONFIRMED" then s.confirmed = s.confirmed + 1 end
                if c and c.s == "DISPUTED" then s.disputed = s.disputed + 1 end
                if fact.t then timeSum, timeCount = timeSum + fact.t, timeCount + 1 end
            end
        end
    end
    if s.people == 0 then return nil end
    if timeCount > 0 then s.avgTurnaround = timeSum / timeCount end
    return s
end

-- Each guild member's orders with a crafter, newest first, for the
-- history window: { { author, id, fact, status }, ... }
function Sharing:Orders(crafter)
    local list = {}
    local confirm = ns.db and Realm().confirm or {}
    for author, entry in pairs(ns.db and Realm().shared[crafter] or {}) do
        for id, fact in pairs(entry.o) do
            list[#list + 1] = { author = author, id = id, fact = fact, status = confirm[id] and confirm[id].s }
        end
    end
    table.sort(list, function(a, b) return (a.fact.at or 0) > (b.fact.at or 0) end)
    return list
end

-- Forgets what a guild member shared when sharing is turned off, and old
-- answers: shared facts older than a year, confirmations of orders nobody
-- has anymore.
function Sharing:Prune(now)
    now = now or Util.Now()
    local realm = Realm()
    for crafter, entries in pairs(realm.shared) do
        for author, entry in pairs(entries) do
            if now - (entry.at or 0) > 365 * 86400 then entries[author] = nil end
        end
        if not next(entries) then realm.shared[crafter] = nil end
    end
end

function Sharing:ForgetShared()
    Realm().shared = {}
    ns.Events:Fire("TC_SHARED_CHANGED")
end

-- Pending questions time out.
C_Timer.NewTicker(ASK_TIMEOUT, function()
    local now = Util.Now()
    for id, request in pairs(pending) do
        if now - request.at > ASK_TIMEOUT then pending[id] = nil end
    end
end)

ns.Events:On("TC_LOGIN", function() Sharing:Prune() end)
