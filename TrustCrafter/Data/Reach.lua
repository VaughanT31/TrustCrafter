-- TrustCrafter - what quality you can craft (4.0, for the Crafter Desk).
--
-- The game only answers "what quality would this make" while it has the
-- profession loaded, so the answer is worked out when you open a
-- profession and kept: a few recipes a moment in the background, for this
-- expansion's recipes that have qualities. For each:
--   lo  quality with the lowest quality materials
--   hi  quality with the best materials
--   hc  quality with the best materials and concentration, cc its cost
--   n   how many qualities the item has (0: no ranks, nothing else kept)
--   fx  quality with the best materials and the optional or finishing
--       reagents that add the most skill (fr = their itemIDs), and fc
--       the same with concentration, fcc its cost. Only kept when they
--       beat hi or hc. Reagents that add other stats (multicraft,
--       resourcefulness, ingenuity) don't change the rank and are left out.
--   st  when it already makes max quality (without skill reagents): the
--       finishing reagent to add, by Reach.STAT_ORDER
-- Kept per character, beside the recipe list:
--   recipes[character].p[professionID].q = { [recipeID] = { lo, hi, hc, cc, n, fx, fc, fcc, fr, st, at } }
--
-- Material cost comes from Auction Coach when it's installed (its public
-- API), at the lowest quality, so it's what a basic craft costs.

local _, ns = ...
local Util = ns.Util

local Reach = {}
ns.Reach = Reach

local BATCH = 3                     -- recipes per step
local STEP = 0.2                    -- seconds between steps
local MAX_EXTRA_SLOTS = 4           -- optional slots tried per recipe
local MAX_EXTRA_TRIES = 12          -- reagents tried per optional slot

-- Finishing reagents for a craft that already makes max quality, best
-- first, each with its better version first. Resourcefulness gives
-- materials back, so it leads. Ingenuity only refunds concentration, so
-- it's last when no concentration is spent and second when it is.
local RESOURCEFUL = { 247726, 247725 }    -- Resourceful Routing, Rebar
local INGENIOUS = { 247788, 260630 }      -- Ingenious Identity, Identifier
local MULTICRAFT = { 247724, 247719 }     -- Multicraft Manifold, Matrix
Reach.STAT_ORDER = {
    plain = { RESOURCEFUL, MULTICRAFT, INGENIOUS },
    concentration = { RESOURCEFUL, INGENIOUS, MULTICRAFT },
}

-- The first of order a recipe's optional slots accept, or nil.
function Reach.PickStat(extras, order)
    local accepts = {}
    for _, slot in ipairs(extras) do
        for _, itemID in ipairs(slot.reagents) do accepts[itemID] = true end
    end
    for _, family in ipairs(order) do
        for _, itemID in ipairs(family) do
            if accepts[itemID] then return itemID end
        end
    end
    return nil
end

-- Reagents that combine 5 into 1 of the next: [made] = { from, count }.
Reach.MADE_FROM = {
    [246448] = { 246447, 5 },       -- Apprentice's Scribbles > Artisan's Ledger
    [246449] = { 246448, 5 },       -- > Mentor's Helpful Handiwork
    [246450] = { 246449, 5 },       -- > Artisan's Consortium Gold Star
    [247788] = { 260630, 5 },       -- Ingenious Identifier > Ingenious Identity
    [247726] = { 247725, 5 },       -- Resourceful Rebar > Resourceful Routing
    [247724] = { 247719, 5 },       -- Multicraft Matrix > Multicraft Manifold
}

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a = pcall(fn, ...)
    return ok and a or nil
end

-- One material for GetCraftingOperationInfo, in whichever shape this
-- client builds them.
local function ReagentInfo(itemID, dataSlotIndex, quantity)
    local make = Professions and Professions.CreateCraftingReagentInfo
    local made = make and Call(make, itemID, dataSlotIndex, quantity)
    if type(made) == "table" then return made end
    return { itemID = itemID, reagent = { itemID = itemID }, dataSlotIndex = dataSlotIndex, quantity = quantity }
end

-- The required slots: { { d, n, tiers = { itemID, ... } }, ... }, and
-- whether any slot has more than one quality.
function Reach.Slots(schematic)
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local slots, qualities = {}, false
    for index, slot in ipairs(type(schematic) == "table" and schematic.reagentSlotSchematics or {}) do
        local required = slot.required
        if required == nil then required = basic ~= nil and slot.reagentType == basic end
        if required then
            local tiers = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID then tiers[#tiers + 1] = reagent.itemID end
            end
            if #tiers > 0 then
                slots[#slots + 1] = { d = slot.dataSlotIndex or index, n = slot.quantityRequired or 1, tiers = tiers }
                if #tiers > 1 then qualities = true end
            end
        end
    end
    return slots, qualities
end

-- The optional and finishing slots: { { d, n, reagents = { itemID, ... } } }.
function Reach.Extras(schematic)
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local extras = {}
    for index, slot in ipairs(type(schematic) == "table" and schematic.reagentSlotSchematics or {}) do
        local required = slot.required
        if required == nil then required = basic ~= nil and slot.reagentType == basic end
        if not required and #extras < MAX_EXTRA_SLOTS then
            local reagents = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                if reagent.itemID and #reagents < MAX_EXTRA_TRIES then reagents[#reagents + 1] = reagent.itemID end
            end
            if #reagents > 0 then
                extras[#extras + 1] = { d = slot.dataSlotIndex or index, n = slot.quantityRequired or 1, reagents = reagents }
            end
        end
    end
    return extras
end

-- The materials list for one end of the range: "low" or "high" quality.
-- Only slots with qualities go in: the rest don't change the result, and
-- the game answers nothing when they're included.
function Reach.Mix(slots, which)
    local list = {}
    for _, slot in ipairs(slots) do
        if #slot.tiers > 1 then
            local itemID = which == "high" and slot.tiers[#slot.tiers] or slot.tiers[1]
            list[#list + 1] = ReagentInfo(itemID, slot.d, slot.n)
        end
    end
    return list
end

-- quality, concentration cost, skill
local function Ask(recipeID, list, concentration)
    local info = Call(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, list, nil, concentration == true)
    if type(info) ~= "table" then return nil end
    local skill = (tonumber(info.baseSkill) or 0) + (tonumber(info.bonusSkill) or 0)
    return tonumber(info.craftingQuality), tonumber(info.concentrationCost), skill
end

local function With(list, extra)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    for _, v in ipairs(extra) do copy[#copy + 1] = v end
    return copy
end

-- The optional reagents that add the most skill, one per slot, on top of
-- the best materials: picks = { info, ... }, ids = { itemID, ... }.
local function BestExtras(recipeID, high, extras, baseSkill)
    local picks, ids = {}, {}
    for _, slot in ipairs(extras) do
        local bestGain, bestID = 0, nil
        for _, itemID in ipairs(slot.reagents) do
            local _, _, skill = Ask(recipeID, With(high, { ReagentInfo(itemID, slot.d, slot.n) }))
            if skill and skill - baseSkill > bestGain then bestGain, bestID = skill - baseSkill, itemID end
        end
        if bestID then
            picks[#picks + 1] = ReagentInfo(bestID, slot.d, slot.n)
            ids[#ids + 1] = bestID
        end
    end
    return picks, ids
end

-- Works out one recipe now. nil when the game won't say.
function Reach.Compute(recipeID)
    local tiers = Call(C_TradeSkillUI.GetQualitiesForRecipe, recipeID)
    local n = type(tiers) == "table" and #tiers or 0
    if n <= 1 then return { n = 0, at = Util.Now() } end
    local schematic = Call(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    local slots = Reach.Slots(schematic)
    local lo = Ask(recipeID, Reach.Mix(slots, "low"))
    local high = Reach.Mix(slots, "high")
    local hi, _, skill = Ask(recipeID, high)
    if not lo or not hi then return nil end
    local hc, cc = Ask(recipeID, high, true)
    local result = { lo = lo, hi = hi, hc = hc, cc = cc, n = n, at = Util.Now() }
    if hi >= n then
        result.st = Reach.PickStat(Reach.Extras(schematic), Reach.STAT_ORDER.plain)
    elseif (hc or 0) >= n then
        result.st = Reach.PickStat(Reach.Extras(schematic), Reach.STAT_ORDER.concentration)
    end
    if hi < n or (hc or 0) < n then
        local picks, ids = BestExtras(recipeID, high, Reach.Extras(schematic), skill or 0)
        if #picks > 0 then
            local all = With(high, picks)
            local fx = Ask(recipeID, all)
            local fc, fcc = Ask(recipeID, all, true)
            if (fx and fx > hi) or (fc and fc > (hc or hi)) then
                result.fx, result.fc, result.fcc, result.fr = fx, fc, fcc, ids
            end
        end
    end
    return result
end

-- The best quality reachable at all, and whether that needs concentration
-- and/or the extra reagents.
function Reach.Best(reach)
    if not reach or not reach.hi then return nil end
    local best, conc, extra = reach.hi, false, false
    if reach.hc and reach.hc > best then best, conc = reach.hc, true end
    if reach.fx and reach.fx > best then best, conc, extra = reach.fx, false, true end
    if reach.fc and reach.fc > best then best, conc, extra = reach.fc, true, true end
    return best, conc, extra
end

-- What one of these reagents costs, from Auction Coach: its own price or
-- what the 5 it's made from cost, whichever is less.
function Reach.ReagentCost(itemID, depth)
    local api = AuctionCoachAPI
    if not (api and type(api.GetMarketValue) == "function") or not itemID then return nil end
    local ok, price = pcall(api.GetMarketValue, itemID)
    price = ok and type(price) == "number" and price > 0 and price or nil
    local from = Reach.MADE_FROM[itemID]
    if from and (depth or 0) < 4 then
        local part = Reach.ReagentCost(from[1], (depth or 0) + 1)
        if part and (not price or part * from[2] < price) then price = part * from[2] end
    end
    return price
end

-- "Artisan's Consortium Gold Star (or 5 Mentor's Helpful Handiwork)"
function Reach.ReagentName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    name = name or ("item " .. itemID)
    local from = Reach.MADE_FROM[itemID]
    local fromName = from and C_Item.GetItemNameByID(from[1])
    if fromName then name = name .. " " .. ns.L.DESK_MADE_FROM:format(from[2], fromName) end
    return name
end

-- What a character can reach on a recipe, from the kept answers.
function Reach:Get(character, recipeID)
    local entry = ns.db and ns:RealmData().recipes[character]
    for _, prof in pairs(entry and entry.p or {}) do
        if prof.q and prof.q[recipeID] then return prof.q[recipeID] end
    end
    return nil
end

-- The cost of one craft at the lowest quality, from Auction Coach. nil
-- without Auction Coach or when a material has no price.
function Reach.MaterialCost(recipeID)
    local api = AuctionCoachAPI
    if not (api and type(api.GetMarketValue) == "function") then return nil end
    local slots = Reach.Slots(Call(C_TradeSkillUI.GetRecipeSchematic, recipeID, false))
    if #slots == 0 then return nil end
    local total = 0
    for _, slot in ipairs(slots) do
        local ok, price = pcall(api.GetMarketValue, slot.tiers[1])
        if not ok or type(price) ~= "number" or price <= 0 then return nil end
        total = total + price * slot.n
    end
    return total
end

-- Background work: after a profession scan, this expansion's recipes.
local queue, running = {}, false

local function Step()
    if InCombatLockdown() then
        C_Timer.After(2, Step)        -- wait for combat to end
        return
    end
    for _ = 1, BATCH do
        local job = table.remove(queue, 1)
        if not job then
            running = false
            return
        end
        local result = Reach.Compute(job.recipeID)
        if result then job.prof.q[job.recipeID] = result end
    end
    C_Timer.After(STEP, Step)
end

ns.Events:On("TC_RECIPES_SCANNED", function(_, character, professionID)
    local entry = ns:RealmData().recipes[character]
    local prof = entry and entry.p and entry.p[professionID]
    if not prof or not prof.w then return end
    prof.q = prof.q or {}
    wipe(queue)
    for recipeID in pairs(prof.w) do queue[#queue + 1] = { recipeID = recipeID, prof = prof } end
    if not running and #queue > 0 then
        running = true
        C_Timer.After(STEP, Step)
    end
end)
