-- TrustCrafter - the crafting orders you fill for other players: your side
-- of each order. Logged when the game confirms a fill
-- (CRAFTINGORDERS_FULFILL_ORDER_RESPONSE, see Data/Orders.lua), from the
-- claimed order and the "order fulfilled" message that follows it:
--
--   crafted[orderID] = {
--     id            order ID (string)
--     customer      "Name-Realm" of who placed it, customerGuid
--     crafter       "Name-Realm" of which of your characters filled it
--     itemID, link  the item; link is the delivered item
--     orderType     "PUBLIC" | "GUILD" | "PERSONAL"
--     recipe        spellID, profession = its profession's name
--     minQuality    quality asked for (0 = no minimum)
--     delivered     quality you delivered
--     tip, cut      copper: the tip offered and the Consortium's cut of it
--     recraft       true for a recraft
--     claimedAt     when you took the order (nil when not seen)
--     completedAt   when you filled it
--     state         "FILLED", outcome as for your own orders
--   }
--
-- Orders placed by one of your own characters stay in your own ledger
-- instead, and NPC (patron) orders aren't logged. This is also the record
-- guild sharing will check customers' reviews against.

local _, ns = ...
local Util = ns.Util

local Crafted = {}
ns.Crafted = Crafted

-- How long a claim is remembered while waiting for its fill.
local CLAIM_DAYS = 2

local function SetOnce(record, field, value)
    if record[field] == nil and value ~= nil then record[field] = value end
end

local function Secret(value)
    return issecretvalue and value ~= nil and issecretvalue(value)
end

function Crafted:Get(orderID)
    return ns:RealmData().crafted[tostring(orderID)]
end

-- All crafted records on this realm, newest first.
function Crafted:All()
    local list = {}
    for _, record in pairs(ns:RealmData().crafted) do list[#list + 1] = record end
    table.sort(list, function(a, b)
        local ta, tb = a.completedAt or 0, b.completedAt or 0
        if ta ~= tb then return ta > tb end
        return a.id > b.id
    end)
    return list
end

-- Seconds from taking the order to filling it, or nil.
function Crafted.CraftTime(record)
    if record.claimedAt and record.completedAt then
        return math.max(0, record.completedAt - record.claimedAt)
    end
    return nil
end

-- Remembers when you took an order, so its craft time is known once filled.
function Crafted:NoteClaim(orderID, now)
    if not orderID then return end
    local claims = ns:RealmData().claims
    local id = tostring(orderID)
    claims[id] = claims[id] or now or Util.Now()
end

-- Adds the record for an order you just filled. info is the claimed
-- CraftingOrderInfo (may be nil), message the fulfilled message's
-- { customer, tip } (may be nil). Returns the record, or nil when it isn't
-- logged (your own character's order, an NPC order, nothing known).
function Crafted:Record(orderID, now, info, message)
    if not ns.db or not orderID then return nil end
    now = now or Util.Now()
    local realm = ns:RealmData()
    local id = tostring(orderID)
    info = type(info) == "table" and info or {}

    local customer = info.customerName
    if Secret(customer) or customer == "" then customer = nil end
    customer = customer or (message and message.customer)
    customer = customer and Util.FullName(customer)
    local orderType = ns.Orders.TypeOf(info.orderType)
    if info.orderType == nil and not customer then return nil end
    if orderType == "NPC" or (info.npcCustomerCreatureID and info.npcCustomerCreatureID > 0) then return nil end
    if customer and ns.Ledger:IsMine(customer) then return nil end

    local record = realm.crafted[id]
    if not record then
        record = { id = id, state = "FILLED" }
        realm.crafted[id] = record
    end
    SetOnce(record, "completedAt", now)
    SetOnce(record, "customer", customer)
    if not Secret(info.customerGuid) then SetOnce(record, "customerGuid", info.customerGuid) end
    SetOnce(record, "crafter", Util.FullName(UnitName("player")))
    SetOnce(record, "crafterGuid", UnitGUID("player"))
    SetOnce(record, "itemID", info.itemID)
    SetOnce(record, "recipe", info.spellID)
    if info.orderType ~= nil then SetOnce(record, "orderType", orderType) end
    SetOnce(record, "minQuality", info.minQuality)
    SetOnce(record, "tip", info.tipAmount or (message and message.tip))
    if (info.consortiumCut or 0) > 0 then SetOnce(record, "cut", info.consortiumCut) end
    if info.isRecraft then record.recraft = true end
    local link = info.outputItemHyperlink
    if link and link ~= "" and not Secret(link) then
        SetOnce(record, "link", link)
        SetOnce(record, "delivered", ns.Orders.QualityOfLink(link))
    end
    if not record.profession then record.profession = ns.Orders.ProfessionOf(info.spellID) end
    if not record.claimedAt and realm.claims[id] then record.claimedAt = realm.claims[id] end
    realm.claims[id] = nil
    record.outcome = ns.Orders.Outcome(record)
    return record
end

-- Fills in what the fulfilled message adds to a record logged a moment ago.
function Crafted:AddMessage(orderID, message)
    local record = orderID and self:Get(orderID)
    if not record or not message then return false end
    local changed = false
    if not record.customer and message.customer then
        local customer = Util.FullName(message.customer)
        if ns.Ledger:IsMine(customer) then
            ns:RealmData().crafted[record.id] = nil
            return true
        end
        record.customer = customer
        changed = true
    end
    if record.tip == nil and message.tip then
        record.tip = message.tip
        changed = true
    end
    return changed
end

-- Claims never filled (released, expired) are forgotten after a while.
function Crafted:PruneClaims(now)
    local claims = ns:RealmData().claims
    now = now or Util.Now()
    for id, at in pairs(claims) do
        if now - at > CLAIM_DAYS * 86400 then claims[id] = nil end
    end
end

-- What you've crafted for one customer ("Name-Realm"), or nil.
-- Returns { count, tips, last }
function Crafted:Summary(customer)
    if not customer then return nil end
    local s = { count = 0, tips = 0 }
    for _, record in pairs(ns:RealmData().crafted) do
        if record.customer == customer then
            s.count = s.count + 1
            s.tips = s.tips + (record.tip or 0)
            s.last = math.max(s.last or 0, record.completedAt or 0)
        end
    end
    return s.count > 0 and s or nil
end

-- Totals for the list header: orders, distinct customers, tips.
function Crafted.Totals(records)
    local customers, count, tips = {}, 0, 0
    for _, record in ipairs(records) do
        count = count + 1
        tips = tips + (record.tip or 0)
        if record.customer then customers[record.customer] = true end
    end
    local people = 0
    for _ in pairs(customers) do people = people + 1 end
    return count, people, tips
end
