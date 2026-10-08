-- TrustCrafter - logs the crafting orders you place, as one record each.
--
-- The game lists your own orders (C_CraftingOrders.GetMyOrders) while the
-- crafting orders NPC is open, filled in by Blizzard's "My Orders" page.
-- Every order seen there becomes or updates a record:
--
--   orders[orderID] = {
--     id            order ID (string)
--     customer      "Name-Realm" of which of your characters placed it
--     crafter       "Name-Realm" of who took it, crafterGuid survives renames
--     itemID, link  the item ordered; link is the delivered item once filled
--     orderType     "PUBLIC" | "GUILD" | "PERSONAL"
--     recipe        spellID, profession = its profession's name
--     minQuality    quality asked for (0 = no minimum)
--     delivered     quality received, read from the delivered item
--     tip           copper
--     placedAt      when it was placed; placedApprox when only first seen
--     completedAt   when it was filled; completedApprox when only first seen
--     state         "OPEN" | "FILLED" | "NOT_FILLED"
--     outcome       "MET" | "EXCEEDED" | "BELOW" | "NOT_FILLED" | nil (open)
--     note, tags, private   the player's own words (Data/Ledger.lua)
--   }
--
-- Facts are only ever filled in, never overwritten once set: what you asked
-- for, what you got and when cannot be edited afterwards.

local _, ns = ...
local Util = ns.Util

local Orders = {}
ns.Orders = Orders

-- Debug logger, defined in the debug section at the end of this file.
local Log

-- How long a just-placed order waits for its order ID to show up.
local PLACING_WINDOW = 15 * 60
local POLL_SECONDS = 2

-- Enum.CraftingOrderState / Type values by name, so a renumbering in a
-- patch can't silently mix them up.
local STATE_NAMES, TYPE_NAMES = {}, {}
if Enum and Enum.CraftingOrderState then
    for name, value in pairs(Enum.CraftingOrderState) do STATE_NAMES[value] = name end
end
if Enum and Enum.CraftingOrderType then
    for name, value in pairs(Enum.CraftingOrderType) do TYPE_NAMES[value] = name end
end

local FILLED_STATES = { Fulfilled = true, Fulfilling = true }
local NOT_FILLED_STATES = {
    Expired = true, Expiring = true, Canceled = true, Canceling = true, Rejected = true, Rejecting = true,
}

local function StateOf(order)
    local name = STATE_NAMES[order.orderState]
    if name and FILLED_STATES[name] then return "FILLED" end
    if name and NOT_FILLED_STATES[name] then return "NOT_FILLED" end
    return "OPEN"
end

local TYPE_KEYS = { Public = "PUBLIC", Guild = "GUILD", Personal = "PERSONAL", Npc = "NPC" }
local function TypeOf(orderType)
    return TYPE_KEYS[TYPE_NAMES[orderType] or ""] or "PUBLIC"
end

-- ---------------------------------------------------------------------
-- Quality
-- ---------------------------------------------------------------------

-- Crafting quality of a delivered item: the game's own crafted-gear and
-- reagent lookups first, then the rank icon in the link's text.
function Orders.QualityOfLink(link)
    if not link then return nil end
    local trade = C_TradeSkillUI
    for _, fnName in ipairs({ "GetItemCraftedQualityByItemInfo", "GetItemReagentQualityByItemInfo" }) do
        local fn = trade and trade[fnName]
        if fn then
            local ok, quality = pcall(fn, link)
            if ok and type(quality) == "number" and quality > 0 then return quality end
        end
    end
    local tier = link:match("Quality%-Tier(%d)")
    return tier and tonumber(tier) or nil
end

-- MET / EXCEEDED / BELOW once filled, NOT_FILLED when it never was.
function Orders.Outcome(record)
    if record.state == "NOT_FILLED" then return "NOT_FILLED" end
    if record.state ~= "FILLED" then return nil end
    local asked, got = record.minQuality or 0, record.delivered
    if not got or asked <= 0 then return "MET" end
    if got > asked then return "EXCEEDED" end
    if got < asked then return "BELOW" end
    return "MET"
end

-- ---------------------------------------------------------------------
-- Profession of a recipe
-- ---------------------------------------------------------------------

local function ProfessionOf(spellID)
    local trade = C_TradeSkillUI
    if not spellID or not (trade and trade.GetTradeSkillLineForRecipe) then return nil end
    local ok, _, skillLineName, parentID = pcall(trade.GetTradeSkillLineForRecipe, spellID)
    if not ok then return nil end
    if parentID and trade.GetProfessionInfoBySkillLineID then
        local okInfo, info = pcall(trade.GetProfessionInfoBySkillLineID, parentID)
        if okInfo and info and info.professionName and info.professionName ~= "" then
            return info.professionName
        end
    end
    return skillLineName
end

-- ---------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------

-- Orders seen open during this session: a fill seen after that is timed
-- to the minute, one first seen already filled only roughly.
local seenOpen = {}

local function SetOnce(record, field, value)
    if record[field] == nil and value ~= nil then record[field] = value end
end

-- The placement this new order came from: same type and tip, placed within
-- PLACING_WINDOW. Used once, then removed.
local function TakePlacement(realm, order, now)
    local placing = realm.placing
    for i = #placing, 1, -1 do
        local p = placing[i]
        if now - p.t > PLACING_WINDOW then
            table.remove(placing, i)
        elseif p.orderType == order.orderType and (p.tip or 0) == (order.tipAmount or 0) then
            table.remove(placing, i)
            return p.t
        end
    end
    return nil
end

-- Adds or updates the record for one CraftingOrderInfo. Returns true when
-- anything changed.
function Orders:Record(order, now)
    if not order or not order.orderID then return false end
    if TypeOf(order.orderType) == "NPC" then return false end
    now = now or Util.Now()
    local realm = ns:RealmData()
    local id = tostring(order.orderID)
    local record = realm.orders[id]
    local changed = false

    if not record then
        record = { id = id, tags = {} }
        realm.orders[id] = record
        -- An order first seen already filled or closed (placed before the
        -- addon was installed) has no known placing time, so no turnaround.
        local placedAt = TakePlacement(realm, order, now)
        if placedAt then
            record.placedAt = placedAt
        elseif StateOf(order) == "OPEN" then
            record.placedAt = now
            record.placedApprox = true
        end
        changed = true
    end

    local before = record.state
    -- All your characters on a realm share one ledger, so note which one
    -- placed it (GetMyOrders only lists the current character's orders).
    SetOnce(record, "customer", Util.FullName(UnitName("player")))
    SetOnce(record, "itemID", order.itemID)
    SetOnce(record, "recipe", order.spellID)
    SetOnce(record, "orderType", TypeOf(order.orderType))
    SetOnce(record, "minQuality", order.minQuality or 0)
    SetOnce(record, "tip", order.tipAmount or 0)
    if order.crafterName and order.crafterName ~= "" then
        SetOnce(record, "crafter", Util.FullName(order.crafterName))
        SetOnce(record, "crafterGuid", order.crafterGuid)
    end
    if not record.profession then record.profession = ProfessionOf(order.spellID) end

    local state = StateOf(order)
    if state == "OPEN" then
        seenOpen[id] = true
        record.state = record.state or "OPEN"
    elseif record.state ~= "FILLED" and record.state ~= "NOT_FILLED" then
        -- Open to closed happens once; a closed order never reopens.
        record.state = state
        record.completedAt = now
        record.completedApprox = not seenOpen[id] or nil
    end

    if record.state == "FILLED" then
        local link = order.outputItemHyperlink
        if link and link ~= "" then
            SetOnce(record, "link", link)
            SetOnce(record, "delivered", Orders.QualityOfLink(link))
        end
    end
    record.outcome = Orders.Outcome(record)

    return changed or before ~= record.state
end

-- Reads every order the game currently lists for you.
function Orders:Scan()
    if not ns.db or not (C_CraftingOrders and C_CraftingOrders.GetMyOrders) then return end
    local ok, list = pcall(C_CraftingOrders.GetMyOrders)
    if not ok or type(list) ~= "table" then return end
    local now, changed = Util.Now(), false
    for _, order in ipairs(list) do
        if self:Record(order, now) then changed = true end
    end
    if changed then ns.Events:Fire("TC_LEDGER_CHANGED") end
end

-- ---------------------------------------------------------------------
-- Watching the crafting orders NPC
-- ---------------------------------------------------------------------

local ticker

local function StartPolling()
    if ticker then return end
    Orders:Scan()
    ticker = C_Timer.NewTicker(POLL_SECONDS, function() Orders:Scan() end)
end

local function StopPolling()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    Orders:Scan()
end

local Events = ns.Events

Events:On("CRAFTINGORDERS_SHOW_CUSTOMER", StartPolling)
Events:On("CRAFTINGORDERS_HIDE_CUSTOMER", StopPolling)

for _, event in ipairs({ "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE", "CRAFTINGORDERS_ORDER_CANCEL_RESPONSE" }) do
    Events:On(event, function()
        C_Timer.After(1, function() Orders:Scan() end)
    end)
end

-- ---------------------------------------------------------------------
-- Filled by one of your own characters
--
-- When you fill an order, the game confirms it with
-- CRAFTINGORDERS_FULFILL_ORDER_RESPONSE(result, orderID). If that order is
-- in the ledger, one of your own characters on this realm placed it, so it
-- is marked filled right away: exact time, no need for the customer to
-- reopen My Orders. The claimed order is read while it is being crafted, for
-- the delivered item and its quality.
-- ---------------------------------------------------------------------

local claimed = {}

local function ReadClaimed(orderID)
    if not (C_CraftingOrders and C_CraftingOrders.GetClaimedOrder) then return end
    local ok, info = pcall(C_CraftingOrders.GetClaimedOrder)
    if ok and type(info) == "table" and info.orderID == orderID then claimed[orderID] = info end
end

Events:On("CRAFTINGORDERS_CLAIMED_ORDER_UPDATED", function(_, orderID)
    if orderID then ReadClaimed(orderID) end
end)

local FULFILL_OK = (Enum and Enum.CraftingOrderResult and Enum.CraftingOrderResult.Ok) or 0

function Orders:FilledByMe(orderID, now)
    local record = ns.db and orderID and ns:RealmData().orders[tostring(orderID)]
    if not record or record.state == "FILLED" or record.state == "NOT_FILLED" then return false end
    record.state = "FILLED"
    record.completedAt = now or Util.Now()
    record.completedApprox = nil
    -- Your own work: it can never be rated (Ledger:CanReview).
    record.ownCraft = true
    SetOnce(record, "crafter", Util.FullName(UnitName("player")))
    SetOnce(record, "crafterGuid", UnitGUID("player"))
    local info = claimed[orderID]
    local link = info and info.outputItemHyperlink
    if link and link ~= "" then
        SetOnce(record, "link", link)
        SetOnce(record, "delivered", Orders.QualityOfLink(link))
    end
    record.outcome = Orders.Outcome(record)
    claimed[orderID] = nil
    ns.Events:Fire("TC_LEDGER_CHANGED")
    return true
end

Events:On("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", function(_, result, orderID)
    if result ~= FULFILL_OK or not orderID then return end
    -- The finished item may only be on the claimed order a moment later.
    ReadClaimed(orderID)
    local now = Util.Now()
    C_Timer.After(0.5, function()
        ReadClaimed(orderID)
        Orders:FilledByMe(orderID, now)
    end)
end)

-- ---------------------------------------------------------------------
-- Crafting order mail
--
-- A filled order arrives by mail, and that is when most players notice it,
-- not by reopening My Orders. When the mailbox opens, each crafting order
-- mail (C_Mail.GetCraftingOrderMailInfo) is matched to an open order of
-- this character: same item, same crafter if one is known, oldest first.
-- Mail has no sent time, only days left, so the fill time is worked out
-- from that and marked approximate. Each mail is used once (mailSeen).
-- ---------------------------------------------------------------------

-- How long a crafting order mail lasts, for working back to when it was sent.
local MAIL_DAYS = 30

local REASON_NAMES = {}
if Enum and Enum.RcoCloseReason then
    for name, value in pairs(Enum.RcoCloseReason) do REASON_NAMES[value] = name end
end

-- "FILLED", "NOT_FILLED", or nil when the mail's reason can't be read (then
-- an item attached is taken to mean filled).
local function MailResult(info, hasItem)
    local name = REASON_NAMES[info.reason] or ""
    if name:find("Fulfill") then return "FILLED" end
    if name:find("Expire") or name:find("Cancel") or name:find("Reject") then return "NOT_FILLED" end
    return hasItem and "FILLED" or nil
end

local function MatchOpenOrder(realm, me, itemID, crafter)
    local best
    for _, record in pairs(realm.orders) do
        if record.state == "OPEN" and record.customer == me and record.itemID == itemID
            and (not record.crafter or not crafter or record.crafter == crafter) then
            if not best or (record.placedAt or 0) < (best.placedAt or 0) then best = record end
        end
    end
    return best
end

function Orders:ScanMail()
    if not ns.db or not (C_Mail and C_Mail.GetCraftingOrderMailInfo) then return end
    local realm = ns:RealmData()
    local me = Util.FullName(UnitName("player"))
    local now, changed = Util.Now(), false

    for i = 1, GetInboxNumItems() do
        local ok, info = pcall(C_Mail.GetCraftingOrderMailInfo, i)
        if ok and type(info) == "table" then
            local daysLeft = select(7, GetInboxHeaderInfo(i))
            local itemID = select(2, GetInboxItem(i, 1))
            local link = GetInboxItemLink(i, 1)
            local crafter = info.crafterName and info.crafterName ~= "" and Util.FullName(info.crafterName) or nil
            local sentAt = daysLeft and math.floor(now - (MAIL_DAYS - daysLeft) * 86400) or now
            local key = table.concat({ tostring(crafter), tostring(itemID), tostring(math.floor(sentAt / 600)) }, ":")
            local result = MailResult(info, link ~= nil)
            Log("MAIL", tostring(info.recipeName), tostring(crafter), tostring(REASON_NAMES[info.reason] or info.reason),
                "daysLeft " .. tostring(daysLeft))

            local record = result and itemID and not realm.mailSeen[key] and MatchOpenOrder(realm, me, itemID, crafter)
            if record then
                realm.mailSeen[key] = now
                record.state = result
                -- Sent time from days left, unless that lands outside the
                -- order's life (then the mail lasts a different time).
                local placed = record.placedAt or 0
                record.completedAt = (sentAt >= placed and sentAt <= now) and sentAt or now
                record.completedApprox = true
                if crafter then SetOnce(record, "crafter", crafter) end
                SetOnce(record, "crafterGuid", info.crafterGUID)
                if result == "FILLED" and link then
                    SetOnce(record, "link", link)
                    SetOnce(record, "delivered", Orders.QualityOfLink(link))
                end
                if crafter and ns.Ledger:IsMine(crafter) then record.ownCraft = true end
                record.outcome = Orders.Outcome(record)
                changed = true
            end
        end
    end

    -- Forget matched mails after their longest possible life.
    for key, seenAt in pairs(realm.mailSeen) do
        if now - seenAt > MAIL_DAYS * 86400 then realm.mailSeen[key] = nil end
    end
    if changed then ns.Events:Fire("TC_LEDGER_CHANGED") end
end

local mailTimer
Events:On("MAIL_INBOX_UPDATE", function()
    if mailTimer then return end
    mailTimer = C_Timer.NewTimer(0.5, function()
        mailTimer = nil
        Orders:ScanMail()
    end)
end)

-- Placing an order: remember when, so the new order's real placing time
-- is known once its ID appears in the list.
Events:On("TC_LOGIN", function()
    if C_CraftingOrders and C_CraftingOrders.PlaceNewOrder then
        hooksecurefunc(C_CraftingOrders, "PlaceNewOrder", function(info)
            if not ns.db or type(info) ~= "table" then return end
            local placing = ns:RealmData().placing
            placing[#placing + 1] = { t = Util.Now(), orderType = info.orderType, tip = info.tipAmount }
        end)
    end
end)

-- ---------------------------------------------------------------------
-- Debug log: which crafting order events fire, and what the order list
-- holds at that moment. Turned on with /tc debug; kept for the last 100.
-- ---------------------------------------------------------------------

local DEBUG_EVENTS = {
    "CRAFTINGORDERS_SHOW_CUSTOMER", "CRAFTINGORDERS_HIDE_CUSTOMER",
    "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE", "CRAFTINGORDERS_ORDER_CANCEL_RESPONSE",
    "CRAFTINGORDERS_CAN_REQUEST", "CRAFTINGORDERS_UPDATE_ORDER_COUNT",
    "CRAFTINGORDERS_CUSTOMER_OPTIONS_PARSED", "CRAFTINGORDERS_UPDATE_CUSTOMER_NAME",
    "CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG", "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE",
    "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED", "CRAFTINGORDERS_UNEXPECTED_ERROR",
}

function Log(event, ...)
    if not ns.db or not ns.db.settings.debug then return end
    local args = {}
    for i = 1, select("#", ...) do args[#args + 1] = tostring((select(i, ...))) end
    local line = date("%H:%M:%S") .. " " .. event .. " " .. table.concat(args, ", ")
    local log = ns.db.debugLog
    log[#log + 1] = line
    while #log > 100 do table.remove(log, 1) end
    Util.Print("|cff999999" .. line .. "|r")
end

for _, event in ipairs(DEBUG_EVENTS) do
    Events:On(event, Log)
end

ns:RegisterCommand("debug", function()
    ns.db.settings.debug = not ns.db.settings.debug
    Util.Print(ns.db.settings.debug and ns.L.DEBUG_ON or ns.L.DEBUG_OFF)
end, ns.L.HELP_DEBUG)
