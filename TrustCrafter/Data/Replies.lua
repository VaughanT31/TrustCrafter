-- TrustCrafter - Crafter Desk replies (4.0): one whisper per click, built
-- so it doesn't read like a bot.
--
--   - Pieces are picked at random from pools per tone (Short, Friendly,
--     Formal): an opener, a body, then only what they asked about (quality,
--     whose mats, price), the order line and an optional closer.
--   - Never the same text twice in a row, and never the same opener to the
--     same person twice in a row.
--   - One greeting per request, none to the same person for the same thing
--     within REGREET, and at most PER_MINUTE a minute, so trade chat never
--     gets machine-gunned.
--   - Nothing is sent without a click.
--
-- Your own replies: each character can have their own (the desk window's
-- Messages page), one per line, and one line is picked at random (never
-- the same twice in a row). Without them the pools below are used.
--
-- Placeholders: {name} {item} {character} (or {crafter}) {profession}
-- {quality} {commission} {mats}
-- Pieces start in lower case unless they start with "I" or a name: after
-- an opener ending in "!" or "." the first letter is raised.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Replies = {}
ns.Replies = Replies

local REGREET = 10 * 60
local PER_MINUTE = 5
local MAX_LENGTH = 255

Replies.TONES = { "friendly", "short", "formal" }

-- Pools. Every list has several entries so picks vary.
local P = {
    friendly = {
        open = { "Hey {name}!", "Hi {name}!", "Hey {name},", "Hello {name}!", "Hey there {name},", "Hi there!" },
        item = { "I can craft {item} for you{quality}.", "I can make {item}{quality}, happy to help.",
            "{item} is no problem, I can do that{quality}.", "I can do {item} for you{quality}." },
        alt = { "my alt {crafter} can craft {item}{quality}.", "{item} is on my alt {crafter}{quality}, happy to help.",
            "I can do {item}{quality} on my alt {crafter}." },
        profession = { "I do {profession}, what do you need made?", "{profession} here, what are you after?",
            "I can help with {profession}, what do you need?" },
        manual = { "saw your message, I might be able to help. What do you need crafted?",
            "what are you looking to get crafted? I might be able to help." },
        order = { "Send a personal order to {crafter} whenever you're ready.", "Just send a personal order to {crafter}.",
            "Pop a personal order to {crafter} and I'll get it done." },
        close = { "Cheers!", "Thanks!", ":)", "", "" },
    },
    short = {
        open = { "Hi,", "Hey,", "Hi {name},", "o/", "Hey {name}," },
        item = { "can craft {item}{quality}.", "can do {item}{quality}.", "{item}{quality}, can do." },
        alt = { "can craft {item}{quality} on {crafter}.", "{item}{quality} on my alt {crafter}." },
        profession = { "{profession} here, what do you need?", "can help, what do you need made?" },
        manual = { "can help, what do you need?", "what do you need crafted?" },
        order = { "Personal order to {crafter}.", "Send it to {crafter}.", "Order to {crafter} please." },
        close = { "", "", "ty" },
    },
    formal = {
        open = { "Hello {name},", "Good day {name},", "Greetings {name},", "Hello," },
        item = { "I am able to craft {item} for you{quality}.", "I can provide {item}{quality}.",
            "I would be glad to craft {item}{quality}." },
        alt = { "my character {crafter} can craft {item}{quality}.", "I can craft {item}{quality} on {crafter}." },
        profession = { "I craft {profession}. What would you like made?", "I can help with {profession}. What do you need?" },
        manual = { "I noticed your message. What would you like crafted?", "I may be able to help. What do you need crafted?" },
        order = { "Please send a personal order to {crafter} when convenient.", "You are welcome to send a personal order to {crafter}." },
        close = { "Thank you.", "Kind regards.", "" },
    },
}

-- Extra lines, by tone, for what they asked.
local EXTRA = {
    friendly = {
        theirs = { "Send it over with your mats.", "Just include your mats in the order." },
        mine = { "I can supply the mats.", "I've got the mats if you need them." },
        busy = { "I'm a bit busy right now, but send it and I'll do it shortly.", "Might take me a little while, but send it over." },
    },
    short = {
        theirs = { "Your mats.", "Bring mats." },
        mine = { "Can use my mats.", "Have mats." },
        busy = { "Busy atm, will do it soon.", "Bit busy, send anyway." },
    },
    formal = {
        theirs = { "Please include your materials with the order.", "Your materials in the order would be ideal." },
        mine = { "I can provide the materials.", "Materials can be supplied on my end." },
        busy = { "I am a little occupied at the moment, but will complete it shortly.", "There may be a short delay, but please send it." },
    },
}

local lastText, lastLine
local lastOpener = {}              -- customer -> opener template (or custom line)
local sent = {}                    -- times of recent whispers
local greetedFor = {}              -- customer .. "|" .. recipe -> time

Replies.random = math.random

local function Pick(list, avoid)
    if #list == 0 then return "" end
    for _ = 1, 6 do
        local choice = list[Replies.random(#list)]
        if choice ~= avoid then return choice end
    end
    return list[1] ~= avoid and list[1] or list[#list]
end

local function Fill(template, values)
    return (template:gsub("{(%a+)}", function(key) return values[key] or "" end))
end

-- "max quality", "rank 2" or nil, from what this character can reach.
-- Items without ranks say nothing about quality.
function Replies.QualityPhrase(reach)
    if not reach or not reach.hi or reach.n == 0 then return nil end
    local best, conc, extra = ns.Reach.Best(reach)
    local text = (reach.n and best >= reach.n) and L.REPLY_MAX_QUALITY or L.REPLY_RANK:format(best)
    if extra then return L.REPLY_WITH_EXTRA:format(text) end
    return conc and L.REPLY_WITH_CONC:format(text) or text
end

-- Their own link when they linked it (their item level and quality, or
-- the very item to recraft), else the plain one.
local function ItemText(request, plainLink)
    if request.sampleItem then return request.sampleItem end
    if request.link and not plainLink then return request.link end
    if request.itemID then
        local _, link = C_Item.GetItemInfo(request.itemID)
        if link then return link end
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(request.itemID)
        if name then return name end
    end
    return L.REPLY_THAT
end

-- The lines of a custom reply text, or nil when there are none.
function Replies.Lines(text)
    if type(text) ~= "string" then return nil end
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then lines[#lines + 1] = line end
    end
    return #lines > 0 and lines or nil
end

-- A custom line filled in: placeholders with nothing to say are dropped
-- cleanly ("at {quality}" with no quality known leaves no gap).
local function FillCustom(line, values)
    local text = line:gsub("{(%a+)}", function(key) return values[key] or "" end)
    text = text:gsub("%s+([%.,!%?])", "%1"):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- The whisper for a request. Pure apart from the item link and settings.
-- Their own link can be long; if it won't fit, the plain one is used.
local BuildOnce

function Replies.Build(request, settings, me)
    local text, line = BuildOnce(request, settings, me)
    if request.link and #text >= MAX_LENGTH then text, line = BuildOnce(request, settings, me, true) end
    return text, line
end

function BuildOnce(request, settings, me, plainLink)
    settings = settings or {}
    local tone = P[settings.deskTone or "friendly"] and (settings.deskTone or "friendly") or "friendly"
    local pool, extra = P[tone], EXTRA[tone]
    local crafter = request.crafter and Util.ShortName(request.crafter) or Util.ShortName(me)
    local isMe = not request.crafter or request.crafter == me
    local reach = request.recipeID and ns.Reach and ns.Reach:Get(request.crafter or me, request.recipeID)
    local quality = request.asks and request.asks.quality and Replies.QualityPhrase(reach)
    local cs = ns.Watch and ns.Watch.CharSettings(request.crafter or me) or {}
    local commissionText = (cs.commission and cs.commission ~= "") and cs.commission or settings.deskCommission or ""
    local values = {
        name = Util.ShortName(request.customer), item = request.recipeID and ItemText(request, plainLink) or "",
        crafter = crafter, character = crafter, profession = request.profession or "",
        quality = quality and (" " .. L.REPLY_AT:format(quality)) or "",
        commission = commissionText,
    }

    -- Your own replies for this character.
    local custom = Replies.Lines(cs.greeting)
    if custom then
        local asks = request.asks or {}
        local filled = {
            name = values.name, item = values.item ~= "" and values.item or L.REPLY_THAT, crafter = crafter, character = crafter,
            profession = values.profession, commission = commissionText,
            quality = Replies.QualityPhrase(reach) or "",
            mats = asks.mats == "theirs" and L.REPLY_MATS_THEIRS or asks.mats == "mine" and L.REPLY_MATS_MINE or "",
        }
        local line = Pick(custom, lastLine)
        local text = FillCustom(line, filled)
        if text == lastText and #custom > 1 then
            line = Pick(custom, line)
            text = FillCustom(line, filled)
        end
        return text:sub(1, MAX_LENGTH), line
    end

    local opener = Pick(pool.open, lastOpener[request.customer])
    local parts = { Fill(opener, values) }
    local hasItem = request.recipeID ~= nil
    if hasItem then
        parts[#parts + 1] = Fill(Pick(isMe and pool.item or pool.alt), values)
    elseif request.how == "profession" then
        parts[#parts + 1] = Fill(Pick(pool.profession), values)
    else
        parts[#parts + 1] = Fill(Pick(pool.manual), values)
    end
    local asks = request.asks or {}
    if asks.mats then parts[#parts + 1] = Pick(extra[asks.mats]) end
    -- A character's own commission is always said; the general one only
    -- when they ask about price, or with "Always" ticked.
    local ownCommission = cs.commission and cs.commission ~= ""
    if commissionText ~= "" and (ownCommission or asks.price or settings.deskCommissionAlways) then
        parts[#parts + 1] = commissionText
    end
    if settings.busy then parts[#parts + 1] = Pick(extra.busy) end
    if hasItem then parts[#parts + 1] = Fill(Pick(pool.order), values) end
    local closer = Pick(pool.close)

    local function Join(withCloser)
        local list = {}
        for _, p in ipairs(parts) do if p ~= "" then list[#list + 1] = p end end
        if withCloser and closer ~= "" then list[#list + 1] = closer end
        local text = table.concat(list, " ")
        -- "Hi, can craft" reads better than "Hi, Can craft"; a sentence
        -- after "!" or "." starts with a capital.
        text = text:gsub("([%.!%?] )(%l)", function(a, b) return a .. b:upper() end)
        return text
    end
    local text = Join(true)
    if text == lastText or #text > MAX_LENGTH then text = Join(false) end
    while #text > MAX_LENGTH and #parts > 2 do
        table.remove(parts, #parts)
        text = Join(false)
    end
    return text, opener
end

-- Whether a request can be greeted now, or false and why: "done" (already
-- greeted), "recent" (greeted them for this a moment ago), "limit" (too
-- many whispers this minute).
function Replies:CanGreet(request, now)
    now = now or Util.Now()
    if request.status == "greeted" or request.status == "ordered" or request.status == "delivered" then return false, "done" end
    local key = request.customer .. "|" .. tostring(request.recipeID or request.professionID or "")
    if greetedFor[key] and now - greetedFor[key] < REGREET then return false, "recent" end
    for i = #sent, 1, -1 do
        if now - sent[i] >= 60 then table.remove(sent, i) end
    end
    if #sent >= PER_MINUTE then return false, "limit" end
    return true
end

local function Whisper(text, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, "WHISPER", nil, target)
    else
        SendChatMessage(text, "WHISPER", nil, target)
    end
end

-- The reply for a request (for a preview), without sending it.
function Replies:Preview(request)
    if not request.preview then
        request.preview, request.previewOpener = Replies.Build(request, ns.db.settings, Util.FullName(UnitName("player")))
    end
    return request.preview
end

-- Sends the previewed reply (a click). Returns true, or false and why.
function Replies:Greet(request, now)
    now = now or Util.Now()
    local ok, why = self:CanGreet(request, now)
    if not ok then return false, why end
    local text = self:Preview(request)
    Whisper(text, request.customer)
    lastText = text
    lastLine = request.previewOpener
    lastOpener[request.customer] = request.previewOpener
    sent[#sent + 1] = now
    greetedFor[request.customer .. "|" .. tostring(request.recipeID or request.professionID or "")] = now
    request.preview, request.previewOpener = nil, nil
    ns.Watch:SetStatus(request, "greeted")
    return true
end

-- A new pick for the preview ("another wording").
function Replies:Reroll(request)
    request.preview, request.previewOpener = nil, nil
    return self:Preview(request)
end
