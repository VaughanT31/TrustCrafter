-- TrustCrafter - Crafter Desk (4.0): watches chat for people asking for a
-- craft you can make.
--
-- A message counts when it has one of the request words (LF, WTB, need,
-- recraft, anyone craft...) and none of the ignore words (WTS, LFW, LF
-- work, selling...). Both lists are editable. Then, in this order:
--   1. an item link to something one of your characters makes
--   2. a keyword you gave an item on a character's watchlist
--   3. the name of something one of your characters makes, this expansion's
--      recipes only (names from older ones match too much)
--   4. a profession you have, by name or short form ("LF blacksmith")
-- Each character can be switched off, items taken off their watchlist,
-- or limited to what they make at max quality (see Watch.CharSettings).
-- Your recipes come from the profession scan (Data/Finder.lua): open each
-- profession once on each character. The character that makes it at max
-- quality is picked first, then the one you're playing, then the most
-- skill ("include my other characters" can turn alts off).
--
-- Each match becomes a request; the same person asking for the same thing
-- again within REPEAT_WINDOW counts on the same request. Nothing is ever
-- sent from here: replies are one click each (Data/Replies.lua).
--
-- Kept per realm, newest last, KEEP_DAYS days and at most KEEP requests:
--   requests = { { id, t, customer, guid, text, channel, recipeID, itemID,
--                  link, crafter, profession, how, asks, times,
--                  status = "new" | "greeted" | "ordered" | "dismissed",
--                  greetedAt }, ... }

local _, ns = ...
local L, Util = ns.L, ns.Util

local Watch = {}
ns.Watch = Watch

local REPEAT_WINDOW = 15 * 60
local KEEP_DAYS = 7
local KEEP = 300
local LAST_SEEN = 10 * 60          -- a player's last message, for "Reply as a crafter"

Watch.DEFAULT_WORDS = "lf, lfc, wtb, looking for, need, needing, recraft, anyone craft, anyone can, can anyone, can someone, who can, any crafter, crafter for"
Watch.DEFAULT_IGNORE = "wts, lfw, lf work, lf orders, selling, crafting service, my services, taking orders, send orders, lfg, lfm, boost, carry"

-- Short forms people use, by profession ID (English clients).
local PROFESSION_WORDS = {
    [164] = { "blacksmith", "blacksmithing", "bs" },
    [165] = { "leatherworker", "leatherworking", "lw" },
    [171] = { "alchemist", "alchemy", "alch" },
    [197] = { "tailor", "tailoring" },
    [202] = { "engineer", "engineering", "engi" },
    [333] = { "enchanter", "enchanting", "enchant", "ench" },
    [755] = { "jewelcrafter", "jewelcrafting", "jc" },
    [773] = { "scribe", "inscription", "inscriptionist" },
}

local lastSeen = {}                -- "Name-Realm" -> { t, text, guid, channel }
local nextID = 0

local function Settings() return ns.db and ns.db.settings or {} end

-- "a, b c, d" -> { "a", "b c", "d" }, lower case.
function Watch.WordList(text)
    local list = {}
    for word in (text or ""):lower():gmatch("[^,]+") do
        word = word:gsub("^%s+", ""):gsub("%s+$", "")
        if word ~= "" then list[#list + 1] = word end
    end
    return list
end

local function Escape(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Whether a whole word or phrase is in the (lower case) text.
function Watch.HasWord(text, word)
    return text:find("%f[%w]" .. Escape(word) .. "%f[%W]") ~= nil
end

-- Chat text without links, colours and textures, lower case, for words.
function Watch.Plain(text)
    text = text:gsub("|H.-|h%[?(.-)%]?|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text:lower()
end

-- Is this a request? Returns true, or false and why ("ignore", word) or
-- ("noword").
function Watch.Classify(plain, words, ignore)
    for _, word in ipairs(ignore) do
        if Watch.HasWord(plain, word) then return false, "ignore", word end
    end
    for _, word in ipairs(words) do
        if Watch.HasWord(plain, word) then return true, "word", word end
    end
    return false, "noword"
end

-- What they asked about besides the item: mats ("theirs" = they bring
-- them, "mine" = you supply them), quality, price.
function Watch.Asks(plain)
    local asks = {}
    if plain:find("my mats") or plain:find("own mats") or plain:find("have mats") or plain:find("have the mats")
        or plain:find("with mats") or plain:find("i provide") then
        asks.mats = "theirs"
    elseif plain:find("your mats") or plain:find("crafter mats") or plain:find("no mats") or plain:find("without mats")
        or plain:find("provide mats") or plain:find("full mats") then
        asks.mats = "mine"
    end
    for _, w in ipairs({ "max", "best quality", "top quality", "r5", "q5", "r3", "q3", "r2", "q2", "rank 2", "rank 3", "rank 5", "2%*", "3%*", "5%*", "quality" }) do
        if plain:find(w) then asks.quality = true break end
    end
    for _, w in ipairs({ "how much", "price", "cost", "commission", "tip", "fee", "charge" }) do
        if Watch.HasWord(plain, w) then asks.price = true break end
    end
    return asks
end

-- Item IDs linked in the raw text.
function Watch.Links(text)
    local list = {}
    for id in text:gmatch("|Hitem:(%d+)") do list[#list + 1] = tonumber(id) end
    return list
end

-- The whole link for an item in the raw text (colour, bonuses and all), so
-- a reply can show them their own item back.
function Watch.LinkText(text, itemID)
    for link, id in text:gmatch("(|c[^|]+|Hitem:(%d+)[^|]*|h%b[]|h|r)") do
        if tonumber(id) == itemID then return link end
    end
    return nil
end

-- Per character settings (the desk window's Characters list):
--   settings.deskChars[name] = { off, hidden, maxOnly, greeting, commission }
--     off        don't watch for this character's recipes
--     hidden     taken off the desk's list (right-click > delete); comes
--                back the next time that character opens a profession
--     maxOnly    only items this character can make at max quality
--     greeting   their own replies, one per line (Data/Replies.lua)
--     commission their own commission line
--   settings.deskItems[name][recipeID] = { off, keys }
--     off        not on this character's watchlist
--     keys       extra words that mean this item, comma separated
function Watch.CharSettings(name)
    local all = ns.db and ns.db.settings.deskChars
    return all and all[name] or {}
end

-- How good a character is at a recipe: 2 = makes max quality (with
-- concentration if needed), 1 = quality known but below max, 0 = unknown.
local function Grade(reach)
    if reach and reach.n == 0 then return 2 end          -- no ranks: anyone makes "the best"
    local best = ns.Reach and ns.Reach.Best(reach)
    if not best then return 0 end
    return (reach.n and best >= reach.n) and 2 or 1
end
Watch.Grade = Grade

-- Related words: the short ways people ask for an item, built from its
-- name. Gear pairs the name's own word with the slot people say
-- ("Allied Chestplate of Generosity" > "generosity chest", "generosity
-- chestplate", "chestplate of generosity"); anything else gives its word
-- pairs ("Sunfire Silk Bolt" > "sunfire silk", "silk bolt"). Never single
-- words: "reinforced" alone matched the wrong item. BuildIndex drops any
-- that two recipes share.
local SLOTS = {
    chest = { "chestplate", "breastplate", "chestguard", "hauberk", "vest", "robe", "robes", "tunic", "jerkin", "harness" },
    gloves = { "gauntlets", "gloves", "handguards", "grips", "handwraps", "grasps", "mitts" },
    legs = { "greaves", "leggings", "legguards", "legplates", "pants", "trousers", "breeches", "kilt", "faulds", "tassets", "legwraps", "cuisses" },
    boots = { "sabatons", "boots", "treads", "stompers", "footguards", "slippers", "sandals", "walkers" },
    helm = { "helm", "helmet", "headguard", "crown", "hood", "cowl", "circlet", "visage", "mask" },
    shoulders = { "pauldrons", "shoulderguards", "spaulders", "mantle", "shoulderpads", "amice", "epaulets" },
    bracers = { "vambraces", "bracers", "wristguards", "wristwraps", "cuffs", "bindings", "armbands" },
    belt = { "belt", "girdle", "waistguard", "cord", "sash", "cinch", "waistband" },
    cloak = { "cloak", "cape", "shawl", "drape", "shroud" },
    ring = { "ring", "band", "loop", "signet" },
    neck = { "necklace", "choker", "pendant", "amulet", "chain" },
}
local SLOT_OF = {}
for short, nouns in pairs(SLOTS) do
    for _, noun in ipairs(nouns) do SLOT_OF[noun] = short end
end
local FILLER = { ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["and"] = true, ["allied"] = true }

function Watch.AutoKeys(name)
    local words, slot, slotNoun = {}, nil, nil
    for word in (name or ""):lower():gsub("'", ""):gmatch("[%w]+") do
        if SLOT_OF[word] and not slot then
            slot, slotNoun = SLOT_OF[word], word
        elseif not FILLER[word] then
            words[#words + 1] = word
        end
    end
    local keys, seen = {}, { [(name or ""):lower()] = true }
    local function Add(key)
        if not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    if slot then
        for _, word in ipairs(words) do
            if #word >= 4 then
                Add(word .. " " .. slot)
                Add(word .. " " .. slotNoun)
                Add(slotNoun .. " of " .. word)
            end
        end
    else
        for i = 1, #words - 1 do Add(words[i] .. " " .. words[i + 1]) end
    end
    return keys
end

-- Who can make what, from the recipe scans and the per character
-- settings: { byItem = { [itemID] = { recipeID, itemID, crafters } },
-- byRecipe, names = { { name, recipeID } }, keywords = { { name,
-- recipeID } }, auto = { { name, recipeID } }, autoByRecipe =
-- { [recipeID] = { words } }, professions = { [professionID] = crafters } }.
-- Crafters are sorted best first: makes max quality, then the one you're
-- playing, then the most skill. noAuto leaves the related words out.
function Watch.BuildIndex(recipes, me, alts, chars, items, noAuto)
    chars, items = chars or {}, items or {}
    local index = { byItem = {}, byRecipe = {}, names = {}, keywords = {}, auto = {}, autoByRecipe = {}, professions = {} }
    local seenName, seenWord = {}, {}
    local autoOwner = {}               -- related word > recipeID, or false when shared
    for character, entry in pairs(recipes or {}) do
        local cs = chars[character] or {}
        if (alts or character == me) and not cs.off and not cs.hidden then
            local watch = items[character] or {}
            for professionID, prof in pairs(entry.p or {}) do
                local who = { name = character, skill = prof.s or 0, me = character == me, profession = prof.n, professionID = professionID }
                index.professions[professionID] = index.professions[professionID] or {}
                table.insert(index.professions[professionID], who)
                local q = prof.q or {}
                for itemID, recipeID in pairs(prof.o or {}) do
                    local item = watch[recipeID] or {}
                    local grade = Grade(q[recipeID])
                    -- Counted over every recipe, watched or not, so a word
                    -- two items share never picks one of them.
                    local fullName = prof.w and prof.w[recipeID]
                    if fullName and not noAuto then
                        for _, key in ipairs(Watch.AutoKeys(fullName)) do
                            local owner = autoOwner[key]
                            if owner == nil then autoOwner[key] = recipeID
                            elseif owner ~= recipeID then autoOwner[key] = false end
                        end
                    end
                    if not item.off and (not cs.maxOnly or grade == 2) then
                        local byItem = index.byItem[itemID]
                        if not byItem then
                            byItem = { recipeID = recipeID, itemID = itemID, crafters = {} }
                            index.byItem[itemID] = byItem
                            index.byRecipe[recipeID] = byItem
                        end
                        byItem.crafters[#byItem.crafters + 1] = {
                            name = character, skill = who.skill, me = who.me, profession = prof.n,
                            professionID = professionID, grade = grade,
                        }
                        local name = prof.w and prof.w[recipeID]
                        if name and #name >= 4 and not seenName[name] then
                            seenName[name] = true
                            index.names[#index.names + 1] = { name = name, recipeID = recipeID }
                        end
                        for _, word in ipairs(Watch.WordList(item.keys)) do
                            if not seenWord[word] then
                                seenWord[word] = true
                                index.keywords[#index.keywords + 1] = { name = word, recipeID = recipeID }
                            end
                        end
                    end
                end
            end
        end
    end
    local function Best(a, b)
        if (a.grade or 0) ~= (b.grade or 0) then return (a.grade or 0) > (b.grade or 0) end
        if a.me ~= b.me then return a.me end
        return a.skill > b.skill
    end
    for _, entry in pairs(index.byItem) do table.sort(entry.crafters, Best) end
    for _, list in pairs(index.professions) do table.sort(list, Best) end
    for key, recipeID in pairs(autoOwner) do
        if recipeID and index.byRecipe[recipeID] and not seenWord[key] and not seenName[key] then
            index.auto[#index.auto + 1] = { name = key, recipeID = recipeID }
            index.autoByRecipe[recipeID] = index.autoByRecipe[recipeID] or {}
            table.insert(index.autoByRecipe[recipeID], key)
        end
    end
    for _, words in pairs(index.autoByRecipe) do table.sort(words) end
    -- Longer first, so "Bright Linen Bolt" wins over "Linen".
    local function Longer(a, b)
        if #a.name ~= #b.name then return #a.name > #b.name end
        return a.name < b.name
    end
    table.sort(index.names, Longer)
    table.sort(index.keywords, Longer)
    table.sort(index.auto, Longer)
    return index
end

-- What in a request one of your characters makes, or nil:
-- { how = "link" | "keyword" | "name" | "auto" | "profession", recipeID, itemID, crafter }
function Watch.Match(text, plain, index)
    for _, itemID in ipairs(Watch.Links(text)) do
        local entry = index.byItem[itemID]
        if entry then
            return { how = "link", recipeID = entry.recipeID, itemID = itemID, crafter = entry.crafters[1],
                link = Watch.LinkText(text, itemID) }
        end
    end
    -- A linked item we don't make: its name says nothing about what else
    -- they want, so words inside links don't count.
    if #Watch.Links(text) > 0 then
        plain = Watch.Plain((text:gsub("|c[^|]+|Hitem:[^|]*|h%b[]|h|r", ""):gsub("|Hitem:[^|]*|h.-|h", "")))
    end
    for _, list in ipairs({ { index.keywords, "keyword" }, { index.names, "name" }, { index.auto or {}, "auto" } }) do
        for _, n in ipairs(list[1]) do
            if Watch.HasWord(plain, n.name) then
                local entry = index.byRecipe[n.recipeID]
                if entry then return { how = list[2], recipeID = n.recipeID, itemID = entry.itemID, crafter = entry.crafters[1] } end
            end
        end
    end
    for professionID, words in pairs(PROFESSION_WORDS) do
        local crafters = index.professions[professionID]
        if crafters then
            for _, word in ipairs(words) do
                if Watch.HasWord(plain, word) then
                    return { how = "profession", crafter = crafters[1], professionID = professionID }
                end
            end
        end
    end
    return nil
end

-- Characters for the desk window: every character of yours on this realm,
-- scanned or not, with their professions:
-- { { name, off, maxOnly, scannedAt, recipes, professions = { { name, count, skill, max } } } }
function Watch:Characters()
    local realm = ns:RealmData()
    local names = {}
    for name in pairs(realm.characters or {}) do names[name] = true end
    for name in pairs(realm.recipes or {}) do names[name] = true end
    local me = Util.FullName(UnitName("player"))
    local list = {}
    for name in pairs(names) do
        if Watch.CharSettings(name).hidden then names[name] = nil end
    end
    for name in pairs(names) do
        local entry = realm.recipes[name]
        local cs = Watch.CharSettings(name)
        local c = { name = name, off = cs.off, maxOnly = cs.maxOnly, me = name == me, scannedAt = entry and entry.at, recipes = 0, professions = {} }
        for _, prof in pairs(entry and entry.p or {}) do
            local count = 0
            for _ in pairs(prof.o or {}) do count = count + 1 end
            c.recipes = c.recipes + count
            c.professions[#c.professions + 1] = { name = prof.n, count = count, skill = prof.s, max = prof.m }
        end
        table.sort(c.professions, function(a, b) return (a.name or "") < (b.name or "") end)
        list[#list + 1] = c
    end
    table.sort(list, function(a, b)
        if (a.recipes > 0) ~= (b.recipes > 0) then return a.recipes > 0 end
        if a.me ~= b.me then return a.me end
        return a.name < b.name
    end)
    return list
end

-- One character's recipes for the watchlist:
-- { { recipeID, itemID, profession, current, reach, grade, off, keys } }
function Watch:RecipeList(name)
    local entry = ns:RealmData().recipes[name]
    local items = (ns.db.settings.deskItems or {})[name] or {}
    local list = {}
    for _, prof in pairs(entry and entry.p or {}) do
        for itemID, recipeID in pairs(prof.o or {}) do
            local item = items[recipeID] or {}
            local reach = prof.q and prof.q[recipeID]
            list[#list + 1] = {
                recipeID = recipeID, itemID = itemID, profession = prof.n, current = prof.w and prof.w[recipeID] ~= nil,
                reach = reach, grade = Grade(reach), off = item.off, keys = item.keys,
            }
        end
    end
    return list
end

local function Dirty()
    ns.Events:Fire("TC_SETTINGS_CHANGED")
end

function Watch:SetChar(name, field, value)
    local s = ns.db.settings
    s.deskChars = s.deskChars or {}
    s.deskChars[name] = s.deskChars[name] or {}
    if value == "" or value == false then value = nil end
    s.deskChars[name][field] = value
    Dirty()
end

function Watch:SetItem(name, recipeID, field, value)
    local s = ns.db.settings
    s.deskItems = s.deskItems or {}
    s.deskItems[name] = s.deskItems[name] or {}
    local item = s.deskItems[name][recipeID] or {}
    if value == "" or value == false then value = nil end
    item[field] = value
    s.deskItems[name][recipeID] = next(item) and item or nil
    Dirty()
end

-- Requests --------------------------------------------------------------

local index, indexDirty = nil, true

local function Index()
    if indexDirty or not index then
        index = Watch.BuildIndex(ns:RealmData().recipes, Util.FullName(UnitName("player")), Settings().deskAlts ~= false,
            Settings().deskChars, Settings().deskItems, Settings().deskAutoKeys == false)
        indexDirty = false
    end
    return index
end

-- The related words a request can match for a recipe (for the watchlist).
function Watch:AutoKeysFor(recipeID)
    return Index().autoByRecipe[recipeID]
end

function Watch:Requests()
    local realm = ns:RealmData()
    realm.requests = realm.requests or {}
    return realm.requests
end

function Watch:Enabled()
    return Settings().desk == true
end

-- Listening only happens where people trade crafts: in a city or a
-- sanctuary (rested areas count), and never in combat, where chat can't
-- be read safely and an alert would only get in the way.
function Watch.InTown()
    if InCombatLockdown and InCombatLockdown() then return false end
    if IsResting and IsResting() then return true end
    local pvp = GetZonePVPInfo and GetZonePVPInfo()
    return pvp == "sanctuary"
end

function Watch:Listening()
    return self:Enabled() and Watch.InTown()
end

local function Prune(list, now)
    local cutoff = now - KEEP_DAYS * 86400
    while #list > 0 and (list[1].t < cutoff or #list > KEEP) do table.remove(list, 1) end
end

-- How often the same thing was asked today, and by how many people.
function Watch:Demand(request, now)
    now = now or Util.Now()
    local times, people = 0, {}
    for _, r in ipairs(self:Requests()) do
        if now - r.t < 86400 and ((request.recipeID and r.recipeID == request.recipeID)
            or (not request.recipeID and r.professionID == request.professionID and not r.recipeID)) then
            times = times + (r.times or 1)
            people[r.customer] = true
        end
    end
    local count = 0
    for _ in pairs(people) do count = count + 1 end
    return times, count
end

-- One chat message. Returns the request it made or added to, or nil and
-- why (for the test box).
function Watch:Consider(text, sender, guid, channel, now)
    now = now or Util.Now()
    if type(text) ~= "string" or type(sender) ~= "string" then return nil, "invalid" end
    local customer = Util.FullName(sender)
    if not customer then return nil, "invalid" end
    lastSeen[customer] = { t = now, text = text, guid = guid, channel = channel }
    local realm = ns:RealmData()
    if realm.characters[customer] then return nil, "mine" end
    if realm.ignored and realm.ignored[customer] then return nil, "ignored" end

    local plain = Watch.Plain(text)
    local ok, why, word = Watch.Classify(plain, Watch.WordList(Settings().deskWords or Watch.DEFAULT_WORDS),
        Watch.WordList(Settings().deskIgnore or Watch.DEFAULT_IGNORE))
    if not ok then return nil, why, word end
    local match = Watch.Match(text, plain, Index())
    if not match then return nil, "nomatch" end
    if match.recipeID and Settings().deskMuted and Settings().deskMuted[match.recipeID] then return nil, "muted" end
    return self:Add(customer, guid, text, channel, match, Watch.Asks(plain), now)
end

-- The settings page's test box: what would happen to this line, without
-- keeping anything. Returns the match and its asks, or nil and why.
function Watch:Test(text)
    if type(text) ~= "string" or text == "" then return nil, "empty" end
    local plain = Watch.Plain(text)
    local ok, why, word = Watch.Classify(plain, Watch.WordList(Settings().deskWords or Watch.DEFAULT_WORDS),
        Watch.WordList(Settings().deskIgnore or Watch.DEFAULT_IGNORE))
    if not ok then return nil, why, word end
    local match = Watch.Match(text, plain, Index())
    if not match then return nil, "nomatch" end
    if match.recipeID and Settings().deskMuted and Settings().deskMuted[match.recipeID] then return nil, "muted" end
    return match, Watch.Asks(plain)
end

-- How many recipes the desk knows, and on how many characters.
function Watch:RecipeCount()
    local recipes, characters = 0, 0
    for _, entry in pairs(ns:RealmData().recipes) do
        local any = false
        for _, prof in pairs(entry.p or {}) do
            for _ in pairs(prof.o or {}) do recipes = recipes + 1 any = true end
        end
        if any then characters = characters + 1 end
    end
    return recipes, characters
end

function Watch:Add(customer, guid, text, channel, match, asks, now)
    local list = self:Requests()
    local crafter = match.crafter or {}
    local professionID = match.professionID or crafter.professionID
    for i = #list, 1, -1 do
        local r = list[i]
        if now - r.t > REPEAT_WINDOW then break end
        if r.customer == customer and r.recipeID == match.recipeID and r.professionID == professionID then
            r.times = (r.times or 1) + 1
            r.text, r.lastAt = text, now
            r.link = match.link or r.link
            for k, v in pairs(asks) do r.asks[k] = v end
            ns.Events:Fire("TC_DESK_CHANGED", r, "repeat")
            return r, "repeat"
        end
    end
    nextID = nextID + 1
    local request = {
        id = now .. "-" .. nextID, t = now, customer = customer, guid = guid, text = text, channel = channel,
        recipeID = match.recipeID, itemID = match.itemID, link = match.link, how = match.how, professionID = professionID,
        crafter = crafter.name, profession = crafter.profession, asks = asks, times = 1, status = "new",
    }
    list[#list + 1] = request
    Prune(list, now)
    ns.Events:Fire("TC_DESK_REQUEST", request)
    ns.Events:Fire("TC_DESK_CHANGED", request, "new")
    return request, "new"
end

-- "Reply as a crafter" from the player menu: their last message, matched
-- or not.
function Watch:Manual(customer, now)
    now = now or Util.Now()
    local seen = lastSeen[customer]
    if not seen or now - seen.t > LAST_SEEN then return nil end
    local plain = Watch.Plain(seen.text)
    local match = Watch.Match(seen.text, plain, Index()) or { how = "manual" }
    return self:Add(customer, seen.guid, seen.text, seen.channel, match, Watch.Asks(plain), now)
end

function Watch:HasRecent(customer, now)
    local seen = customer and lastSeen[customer]
    return seen ~= nil and (now or Util.Now()) - seen.t <= LAST_SEEN
end

function Watch:SetStatus(request, status)
    request.status = status
    if status == "greeted" then request.greetedAt = Util.Now() end
    ns.Events:Fire("TC_DESK_CHANGED", request, status)
end

function Watch:Mute(recipeID)
    if not recipeID then return end
    ns.db.settings.deskMuted = ns.db.settings.deskMuted or {}
    ns.db.settings.deskMuted[recipeID] = true
end

-- Greeted requests become "ordered" once you fill an order for that
-- customer after greeting them (within a day).
function Watch:CheckOrders()
    local crafted = ns:RealmData().crafted
    local changed = false
    for _, r in ipairs(self:Requests()) do
        if r.status == "greeted" and r.greetedAt then
            for _, record in pairs(crafted) do
                local at = record.completedAt or 0
                if record.customer == r.customer and at >= r.greetedAt and at - r.greetedAt < 86400 then
                    r.status = "ordered"
                    changed = true
                    break
                end
            end
        end
    end
    if changed then ns.Events:Fire("TC_DESK_CHANGED") end
end

-- Today's numbers for the requests page: requests, greeted, ordered.
function Watch:Today(now)
    now = now or Util.Now()
    local requests, greeted, ordered = 0, 0, 0
    for _, r in ipairs(self:Requests()) do
        if now - r.t < 86400 then
            requests = requests + 1
            if r.status == "greeted" or r.status == "ordered" then greeted = greeted + 1 end
            if r.status == "ordered" then ordered = ordered + 1 end
        end
    end
    return requests, greeted, ordered
end

-- Chat -----------------------------------------------------------------------

local function Secret(v)
    return issecretvalue ~= nil and v ~= nil and issecretvalue(v)
end

-- Which public channel a message came from: "trade", "services", "general"
-- or nil. Channel names are localized, so the zone channel ID is used
-- when the client gives it (2 = Trade, 42 = Trade (Services), 1 = General).
local ZONE_CHANNELS = { [1] = "general", [2] = "trade", [42] = "services" }
function Watch.ChannelKind(channelBaseName, zoneChannelID)
    if zoneChannelID and ZONE_CHANNELS[zoneChannelID] then return ZONE_CHANNELS[zoneChannelID] end
    local name = (channelBaseName or ""):lower()
    if name:find("services") then return "services" end
    if name:find("trade") then return "trade" end
    if name:find("general") then return "general" end
    return nil
end

local WANT = { trade = "deskTrade", services = "deskServices", general = "deskGeneral" }

ns.Events:On("CHAT_MSG_CHANNEL", function(_, text, sender, _, _, _, _, zoneChannelID, _, channelBaseName, _, _, guid)
    if not ns.db or not Watch:Listening() then return end
    if Secret(text) or Secret(sender) or Secret(guid) then return end
    local kind = Watch.ChannelKind(channelBaseName, zoneChannelID)
    if not kind or not Settings()[WANT[kind]] then return end
    if guid and guid == UnitGUID("player") then return end
    Watch:Consider(text, sender, guid, kind)
end)

-- Conversations: whispers to and from someone with a request, kept per
-- realm for KEEP_DAYS, at most CHAT_KEEP per person, newest last:
--   chats[customer] = { { t, out = true when you sent it, text }, ... }
local CHAT_KEEP = 40

local function HasRequest(customer)
    local list = Watch:Requests()
    for i = #list, 1, -1 do
        if list[i].customer == customer then return true end
    end
    return false
end

function Watch:Log(name, text, out, now)
    if type(name) ~= "string" or type(text) ~= "string" then return end
    local customer = Util.FullName(name)
    if not customer or not HasRequest(customer) then return end
    now = now or Util.Now()
    local realm = ns:RealmData()
    realm.chats = realm.chats or {}
    local chat = realm.chats[customer] or {}
    realm.chats[customer] = chat
    chat[#chat + 1] = { t = now, out = out or nil, text = text }
    local cutoff = now - KEEP_DAYS * 86400
    while #chat > 0 and (#chat > CHAT_KEEP or chat[1].t < cutoff) do table.remove(chat, 1) end
    ns.Events:Fire("TC_DESK_CHANGED")
end

function Watch:Chat(customer)
    local chats = ns:RealmData().chats
    return chats and chats[customer] or {}
end

-- The requests worth showing, newest last: anything from the last
-- SHOW_FOR (counted from their last ask), plus any they whispered you
-- back about or ordered. The rest stay stored for the day's numbers.
local SHOW_FOR = 10 * 60

function Watch:Visible(now)
    now = now or Util.Now()
    local visible = {}
    for _, request in ipairs(self:Requests()) do
        local keep = now - (request.lastAt or request.t) < SHOW_FOR or request.status == "ordered"
        if not keep then
            for _, m in ipairs(self:Chat(request.customer)) do
                if not m.out and m.t >= request.t then
                    keep = true
                    break
                end
            end
        end
        if keep then visible[#visible + 1] = request end
    end
    return visible
end

ns.Events:On("CHAT_MSG_WHISPER", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    if not ns.db or not Watch:Listening() then return end
    if Secret(text) or Secret(sender) or Secret(guid) then return end
    Watch:Log(sender, text, false)
    if Settings().deskWhispers == false then return end
    Watch:Consider(text, sender, guid, "whisper")
end)

ns.Events:On("CHAT_MSG_WHISPER_INFORM", function(_, text, target)
    if not ns.db or not Watch:Listening() then return end
    if Secret(text) or Secret(target) then return end
    Watch:Log(target, text, true)
end)

-- Takes a character off the desk: its desk settings go, and it's left
-- out until it opens a profession again. Its recipes stay for Find a
-- Crafter, and it stays one of your characters for rating.
function Watch:Hide(name)
    local s = ns.db.settings
    if s.deskItems then s.deskItems[name] = nil end
    s.deskChars = s.deskChars or {}
    s.deskChars[name] = { hidden = true }
    Dirty()
end

ns.Events:On("TC_RECIPES_SCANNED", function(_, character)
    indexDirty = true
    local cs = ns.db.settings.deskChars and ns.db.settings.deskChars[character]
    if cs and cs.hidden then cs.hidden = nil end
end)
ns.Events:On("TC_SETTINGS_CHANGED", function() indexDirty = true end)
ns.Events:On("TC_LEDGER_CHANGED", function() if ns.db then Watch:CheckOrders() end end)

-- /tc desk opens the Crafter Desk window.
ns:RegisterCommand("desk", function()
    if ns.DeskWindow then ns.DeskWindow:Toggle() end
end, L.HELP_DESK)
