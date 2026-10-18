-- TrustCrafter - Find a Crafter (3.1): who on your realm can craft this?
--
-- Customer side: the personal order form gets a "Find a Crafter" button.
-- It asks the hidden realm channel (Data/Channel.lua) and your guild "who
-- can craft recipe 12345?". Crafters who turned on Find a Crafter whisper
-- back which of their characters know it, so the answers come straight from
-- the crafter, like every other Trust Crafter answer. The results window
-- (UI/FinderWindow.lua) shows them next to your history, your guild's and
-- the realm's reviews, so you pick a crafter by trust, not by who shouted
-- first in trade chat.
--
-- Crafter side: every time you open a profession, the recipes that
-- character has learned are noted. Answers list your characters on this
-- realm that know the recipe (or only the one you're playing, if "Include
-- my other characters" is off), your skill, whether you're busy, and a short
-- note you write yourself ("Free with your mats").
--
-- Both sides need "Find a Crafter" turned on (settings.finder, off by
-- default). "Let customers find me" (settings.discoverable) can be turned
-- off to search without being listed.
--
-- Kept per realm:
--   recipes[character] = { at, p = { [professionID] = { n, s, m, r = { [recipeID] = true } } } }

local _, ns = ...
local Util = ns.Util

local Finder = {}
ns.Finder = Finder

local SEARCH_EVERY = 30             -- seconds, per recipe
local SEARCHES_PER_HOUR = 20
local SEARCH_TIMEOUT = 30           -- answers after this are dropped
local ANSWERS_PER_MINUTE = 10
local ANSWER_DELAY = 2              -- up to this many seconds, so answers spread out
local MAX_CHARS = 5                 -- characters per answer
local MAX_RESULTS = 40              -- answers kept per search
local NOTE_MAX = 80
local SCAN_DELAY = 1                -- seconds after the recipe list settles

local searchedAt = {}               -- recipeID -> time
local searches = {}                 -- times of our searches
local answers = {}                  -- times we answered
local nextID = 0

-- The search shown in the results window:
-- { id, recipeID, at, results = { [sender] = { at, chars, busy, note, guild } } }
local current

local function Settings() return ns.db and ns.db.settings or {} end
local function Realm() return ns:RealmData() end

local function UnderLimit(times, window, max, now)
    for i = #times, 1, -1 do
        if now - times[i] >= window then table.remove(times, i) end
    end
    return #times < max
end

function Finder:Enabled()
    return Settings().finder == true and ns.Comm:Available()
end

-- Whether a question can go out now: on the realm channel, or to the guild.
function Finder:CanSearch()
    if not self:Enabled() then return false end
    return ns.Channel:Number() ~= nil or (IsInGuild and IsInGuild()) or false
end

function Finder.CleanNote(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if text == "" then return nil end
    return text:sub(1, NOTE_MAX)
end

function Finder:SetNote(text)
    ns.db.settings.crafterNote = Finder.CleanNote(text) or ""
end

-- Recipes you know -------------------------------------------------------

local function UsableRecipe(info)
    return info and info.learned and not info.isDummyRecipe and not info.isGatheringRecipe
        and not info.isSalvageRecipe and not info.isRecraft
end

-- Notes the open profession's learned recipes for the current character.
-- Skipped for another player's linked profession and guild views.
function Finder:ScanProfession()
    local T = C_TradeSkillUI
    if not ns.db or not T or not T.GetAllRecipeIDs or not T.GetBaseProfessionInfo then return false end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsNPCCrafting and T.IsNPCCrafting()) then
        return false
    end
    local base = T.GetBaseProfessionInfo()
    if not base or not base.professionID or base.professionID == 0 then return false end
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo() or nil
    local known, count = {}, 0
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        if UsableRecipe(T.GetRecipeInfo(id)) then
            known[id] = true
            count = count + 1
        end
    end
    if count == 0 then return false end
    local me = Util.FullName(UnitName("player"))
    local realm = Realm()
    local entry = realm.recipes[me] or { p = {} }
    entry.at = Util.Now()
    entry.p[base.professionID] = {
        n = base.professionName,
        s = child and child.skillLevel or nil,
        m = child and child.maxSkillLevel or nil,
        r = known,
    }
    realm.recipes[me] = entry
    return true, count
end

-- Your characters on this realm that know a recipe:
-- { { name, skill, max, profession }, ... }, the one you're playing first.
function Finder:MyCrafters(recipeID, all)
    local me = Util.FullName(UnitName("player"))
    local list = {}
    for name, entry in pairs(Realm().recipes) do
        if all or name == me then
            for _, prof in pairs(entry.p or {}) do
                if prof.r and prof.r[recipeID] then
                    list[#list + 1] = { name = name, skill = prof.s, max = prof.m, profession = prof.n, me = name == me }
                    break
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.skill or 0) > (b.skill or 0)
    end)
    return list
end

-- Forgets a character's recipes (a deleted or renamed character).
function Finder:Forget(name)
    Realm().recipes[name] = nil
end

-- Asking -------------------------------------------------------------------

function Finder:Current()
    return current
end

-- Asks who can craft a recipe. Returns true, or false and a reason:
-- "off", "nochannel", "wait" (asked about it a moment ago), "limit".
function Finder:Search(recipeID, now)
    if type(recipeID) ~= "number" then return false, "off" end
    if not self:Enabled() then return false, "off" end
    if not self:CanSearch() then return false, "nochannel" end
    now = now or Util.Now()
    if current and current.recipeID == recipeID and searchedAt[recipeID] and now - searchedAt[recipeID] < SEARCH_EVERY then
        return false, "wait"
    end
    if not UnderLimit(searches, 3600, SEARCHES_PER_HOUR, now) then return false, "limit" end
    searches[#searches + 1] = now
    searchedAt[recipeID] = now
    nextID = nextID + 1
    current = { id = nextID .. "-" .. now, recipeID = recipeID, at = now, results = {} }
    local ask = { id = current.id, r = recipeID }
    local number = ns.Channel:Number()
    if number then ns.Comm:Send("fc", ask, "CHANNEL", number) end
    if IsInGuild and IsInGuild() then ns.Comm:Send("fc", ask, "GUILD") end
    ns.Events:Fire("TC_FINDER_CHANGED")
    return true
end

-- Answering ------------------------------------------------------------------

ns.Comm:On("fc", function(p, sender, channel)
    if channel ~= "CHANNEL" and channel ~= "GUILD" then return end
    if not Finder:Enabled() or Settings().discoverable == false then return end
    if type(p) ~= "table" or type(p.id) ~= "string" or type(p.r) ~= "number" then return end
    local found = Finder:MyCrafters(p.r, Settings().finderAlts ~= false)
    if #found == 0 then return end
    local now = Util.Now()
    if not UnderLimit(answers, 60, ANSWERS_PER_MINUTE, now) then return end
    answers[#answers + 1] = now
    local chars = {}
    for i = 1, math.min(#found, MAX_CHARS) do
        local c = found[i]
        chars[i] = { n = c.name, s = c.skill, m = c.max }
    end
    local reply = { id = p.id, r = p.r, c = chars, b = Settings().busy == true or nil,
        t = Finder.CleanNote(Settings().crafterNote) }
    C_Timer.After(math.random() * ANSWER_DELAY, function()
        ns.Comm:Send("fca", reply, "WHISPER", sender)
    end)
end)

-- Cleans one character from an answer. The sender is the only name the
-- server vouches for; the others are what the sender says are their alts.
local function CleanChar(c)
    if type(c) ~= "table" or type(c.n) ~= "string" then return nil end
    local name = Util.FullName(c.n)
    if not name or #name > 60 or name:find("[%s|]") then return nil end
    local clean = { name = name }
    if type(c.s) == "number" and c.s >= 0 and c.s < 1000 then clean.skill = math.floor(c.s) end
    if type(c.m) == "number" and c.m > 0 and c.m < 1000 then clean.max = math.floor(c.m) end
    return clean
end

ns.Comm:On("fca", function(p, sender, channel)
    if channel ~= "WHISPER" or not current or type(p) ~= "table" then return end
    if p.id ~= current.id or p.r ~= current.recipeID then return end
    if Util.Now() - current.at > SEARCH_TIMEOUT then return end
    if ns.db and Realm().ignored[sender] then return end
    if not current.results[sender] then
        local count = 0
        for _ in pairs(current.results) do count = count + 1 end
        if count >= MAX_RESULTS then return end
    end
    local chars, seen = {}, {}
    for _, c in ipairs(type(p.c) == "table" and p.c or {}) do
        local clean = CleanChar(c)
        if clean and not seen[clean.name] and #chars < MAX_CHARS then
            seen[clean.name] = true
            clean.online = clean.name == sender
            chars[#chars + 1] = clean
        end
    end
    if #chars == 0 then return end
    current.results[sender] = { at = Util.Now(), chars = chars, busy = p.b == true, note = Finder.CleanNote(p.t) }
    ns.Events:Fire("TC_FINDER_CHANGED")
end)

-- Reading ------------------------------------------------------------------------

-- How a crafter's history reads, best first: your own orders, then your
-- guild's, then the realm's. Returns rank (3 good .. 0 nothing, -1 mixed)
-- and the summary.
function Finder.Trust(name)
    local mine = ns.Ledger:Summary(name)
    if mine and mine.filled > 0 then return mine.below == 0 and 3 or -1, "mine", mine end
    local guild = ns.Sharing:Summary(name)
    if guild then return guild.below == 0 and 2 or -1, "guild", guild end
    local realm = ns.Sharing:Summary(name, "realm")
    if realm then return realm.below == 0 and 1 or -1, "realm", realm end
    return 0
end

-- The current search as rows, best first:
-- { { name, via, skill, max, online, busy, note, mine, rank }, ... }
-- Your own characters that know the recipe are included as "mine".
function Finder:Rows()
    if not current then return {} end
    local rows = {}
    for sender, result in pairs(current.results) do
        for _, c in ipairs(result.chars) do
            rows[#rows + 1] = {
                name = c.name, via = not c.online and sender or nil, skill = c.skill, max = c.max,
                online = c.online, busy = result.busy, note = result.note,
            }
        end
    end
    for _, c in ipairs(self:MyCrafters(current.recipeID, true)) do
        rows[#rows + 1] = { name = c.name, skill = c.skill, max = c.max, online = c.me, mine = true }
    end
    for _, row in ipairs(rows) do row.rank = Finder.Trust(row.name) end
    table.sort(rows, function(a, b)
        if a.mine ~= b.mine then return b.mine == true end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.online ~= b.online then return a.online == true end
        if (a.busy == true) ~= (b.busy == true) then return not a.busy end
        if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) > (b.skill or 0) end
        return a.name < b.name
    end)
    return rows
end

-- Once, the first time a crafter opens a profession with Find a Crafter
-- off: say it exists.
local function MaybeTip(count)
    local s = Settings()
    if s.finder or s.finderTipShown or not count then return end
    s.finderTipShown = true
    Util.Print(ns.L.FINDER_TIP)
end

local scanTimer
local function ScanLater()
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(SCAN_DELAY, function()
        scanTimer = nil
        local ok, count = Finder:ScanProfession()
        if ok then MaybeTip(count) end
    end)
end
ns.Events:On("TRADE_SKILL_SHOW", ScanLater)
ns.Events:On("TRADE_SKILL_LIST_UPDATE", ScanLater)

-- /tc note <text>, /tc busy
local L = ns.L
ns:RegisterCommand("note", function(args)
    Finder:SetNote(args)
    local note = ns.db.settings.crafterNote
    Util.Print(note ~= "" and L.NOTE_SET:format(note) or L.NOTE_CLEARED)
end, L.HELP_NOTE)
ns:RegisterCommand("busy", function()
    ns.db.settings.busy = not ns.db.settings.busy
    Util.Print(ns.db.settings.busy and L.BUSY_ON or L.BUSY_OFF)
    ns.Events:Fire("TC_SETTINGS_CHANGED")
end, L.HELP_BUSY)
