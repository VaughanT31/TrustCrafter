-- TrustCrafter - the player's own words on top of the logged facts, and
-- the summaries the tooltip and history window show.
--
-- Rating protection, as built here:
--   - A note or tag can only be attached to a logged order: no order, no
--     opinion. You can't rate a crafter you never used.
--   - Only the character who placed an order can rate it, and never when
--     one of your own characters crafted it (Ledger:CanReview).
--   - There is no "failed" mark at all. Whether an order met the quality
--     asked for comes only from the logged facts (Data/Orders.lua), so a
--     correctly filled order can't be made to look like a failure. The only
--     negative a player can add is the soft "slow" tag or a note.
--   - Turnaround is shown as a number, never turned into a score.
--   - One note per order: saving a note replaces the old one.

local _, ns = ...
local Util = ns.Util

local Ledger = {}
ns.Ledger = Ledger

Ledger.NOTE_MAX = 200

-- Tags a player can add, in display order. Positive first.
Ledger.TAGS = { "FAST", "FRIENDLY", "OWN_MATS", "AGAIN", "SLOW" }
local VALID_TAG = {}
for _, tag in ipairs(Ledger.TAGS) do VALID_TAG[tag] = true end

function Ledger:Get(orderID)
    return ns:RealmData().orders[tostring(orderID)]
end

-- All records on this realm, newest first.
function Ledger:All()
    local list = {}
    for _, record in pairs(ns:RealmData().orders) do list[#list + 1] = record end
    table.sort(list, function(a, b)
        local ta, tb = a.completedAt or a.placedAt or 0, b.completedAt or b.placedAt or 0
        if ta ~= tb then return ta > tb end
        return a.id > b.id
    end)
    return list
end

-- True when "Name-Realm" is one of your own characters on this realm.
function Ledger:IsMine(fullName)
    return fullName ~= nil and ns:RealmData().characters[fullName] == true
end

-- Whether the character you are on may add a note or tags to this order,
-- and if not, why: "OWN_CRAFT" (one of your characters crafted it, so it
-- would be rating yourself), "OTHER_CHAR" (another of your characters
-- placed it; only they can rate it) or "NOT_TAKEN" (no crafter yet).
function Ledger:CanReview(record)
    if not record then return false, nil end
    if record.ownCraft or self:IsMine(record.crafter) then return false, "OWN_CRAFT" end
    if not record.crafter then return false, "NOT_TAKEN" end
    if record.customer and record.customer ~= Util.FullName(UnitName("player")) then
        return false, "OTHER_CHAR"
    end
    return true
end

-- Saves the note for one order, replacing any earlier one. Trimmed and cut
-- to NOTE_MAX characters; an empty note removes it.
function Ledger:SetNote(orderID, text)
    local record = self:Get(orderID)
    if not self:CanReview(record) then return false end
    text = (text or ""):gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if #text > self.NOTE_MAX then text = text:sub(1, self.NOTE_MAX) end
    record.note = text ~= "" and text or nil
    ns.Events:Fire("TC_LEDGER_CHANGED")
    return true
end

function Ledger:SetTag(orderID, tag, on)
    local record = self:Get(orderID)
    if not VALID_TAG[tag] or not self:CanReview(record) then return false end
    record.tags = record.tags or {}
    record.tags[tag] = on and true or nil
    -- Fast and slow can't both be true for one order.
    if on and tag == "FAST" then record.tags.SLOW = nil end
    if on and tag == "SLOW" then record.tags.FAST = nil end
    ns.Events:Fire("TC_LEDGER_CHANGED")
    return true
end

-- Private notes stay on this computer, even once sharing exists.
function Ledger:SetPrivate(orderID, private)
    local record = self:Get(orderID)
    if not self:CanReview(record) then return false end
    record.private = private and true or nil
    ns.Events:Fire("TC_LEDGER_CHANGED")
    return true
end

-- What you know about one crafter ("Name-Realm"), or nil if you never used
-- them. Only filled orders count; ones that were never filled are listed
-- separately and never held against anyone.
-- Returns { filled, metOrBetter, below, notFilled, avgTurnaround, last }
function Ledger:Summary(crafter)
    if not crafter then return nil end
    local s = { filled = 0, metOrBetter = 0, below = 0, notFilled = 0 }
    local timeSum, timeCount = 0, 0
    for _, record in pairs(ns:RealmData().orders) do
        if record.crafter == crafter then
            if record.state == "FILLED" then
                s.filled = s.filled + 1
                if record.outcome == "BELOW" then
                    s.below = s.below + 1
                else
                    s.metOrBetter = s.metOrBetter + 1
                end
                local turnaround = Ledger.Turnaround(record)
                if turnaround and not record.completedApprox and not record.placedApprox then
                    timeSum, timeCount = timeSum + turnaround, timeCount + 1
                end
                s.last = math.max(s.last or 0, record.completedAt or 0)
            elseif record.state == "NOT_FILLED" then
                s.notFilled = s.notFilled + 1
            end
        end
    end
    if s.filled == 0 and s.notFilled == 0 then return nil end
    if timeCount > 0 then s.avgTurnaround = timeSum / timeCount end
    return s
end

-- ---------------------------------------------------------------------
-- Export: every order on this realm as CSV, oldest first, for a
-- spreadsheet. Includes private notes: it's your own copy of your data.
-- ---------------------------------------------------------------------

local CSV_COLUMNS = {
    "order_id", "placed", "filled_or_closed", "times_approximate", "customer", "crafter", "item_id", "item",
    "order_type", "profession", "quality_asked", "quality_got", "outcome", "took_minutes", "tip_gold",
    "tags", "note", "private",
}

local function Csv(value)
    if value == nil then return "" end
    value = tostring(value)
    if value:find('[,"\n]') then value = '"' .. value:gsub('"', '""') .. '"' end
    return value
end

local function IsoTime(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M", timestamp) or nil
end

function Ledger:ExportCSV()
    local lines = { table.concat(CSV_COLUMNS, ",") }
    local all = self:All()
    for i = #all, 1, -1 do
        local r = all[i]
        local tags = {}
        for _, tag in ipairs(self.TAGS) do
            if r.tags and r.tags[tag] then tags[#tags + 1] = tag:lower() end
        end
        local took = Ledger.Turnaround(r)
        local item = r.link and r.link:match("%[(.-)%]")
            or (r.itemID and C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(r.itemID))
        local row = {
            r.id, IsoTime(r.placedAt), IsoTime(r.completedAt),
            (r.placedApprox or r.completedApprox) and "yes" or "no",
            r.customer, r.crafter, r.itemID, item, r.orderType, r.profession,
            (r.minQuality or 0) > 0 and r.minQuality or nil, r.delivered, r.outcome or "OPEN",
            took and math.floor(took / 60 + 0.5) or nil,
            r.tip and string.format("%.2f", r.tip / 10000) or nil,
            table.concat(tags, " "), r.note, r.private and "yes" or "no",
        }
        local cells = {}
        for c = 1, #CSV_COLUMNS do cells[c] = Csv(row[c]) end
        lines[#lines + 1] = table.concat(cells, ",")
    end
    return table.concat(lines, "\n"), #all
end

-- Seconds from placing to filling, or nil when either end isn't known.
function Ledger.Turnaround(record)
    if record.placedAt and record.completedAt and record.state == "FILLED" then
        return math.max(0, record.completedAt - record.placedAt)
    end
    return nil
end

-- The stored "Name-Realm" for a typed name, ignoring case. A bare "Name"
-- matches a crafter from your own realm.
function Ledger:FindCrafter(input)
    if not input or input == "" then return nil end
    local wanted = Util.FullName(input):lower()
    for _, record in pairs(ns:RealmData().orders) do
        if record.crafter and record.crafter:lower() == wanted then return record.crafter end
    end
    return nil
end

ns:RegisterCommand("lookup", function(args)
    local L = ns.L
    if args == "" then
        Util.Print(L.LOOKUP_USAGE)
        return
    end
    local crafter = Ledger:FindCrafter(args)
    local s = crafter and Ledger:Summary(crafter)
    if not s then
        Util.Print(L.LOOKUP_NONE:format(args))
        return
    end
    Util.Print(ns.Tooltip.SummaryLine(Util.ShortName(crafter), s))
end, ns.L.HELP_LOOKUP)
