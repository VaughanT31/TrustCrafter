-- TrustCrafter - a small public API for other addons (4.0).
--
--   TrustCrafterAPI.version                   1, raised only on breaking changes
--   TrustCrafterAPI.GetCustomerSummary(name)  one line about a customer from
--                                             your own logs, or nil:
--     "Trust Crafter: you crafted 3x for them | 150g in tips | last 12d ago"
--   TrustCrafterAPI.GetCrafterSummary(name)   the same for a crafter who
--                                             filled your orders, or nil
--
-- name is "Name" (your realm) or "Name-Realm". Patron Planner shows the
-- customer line on personal and guild order cards.

local _, ns = ...
local L, Util = ns.L, ns.Util

local API = { version = 1 }

local PREFIX = "|cff66ccffTrust Crafter:|r "

function API.GetCustomerSummary(name)
    if not ns.db or type(name) ~= "string" or name == "" then return nil end
    local c = ns.Crafted:Summary(Util.FullName(name))
    if not c then return nil end
    local text = ns.Tooltip.CraftedLine(c)
    local age = Util.FormatAge(c.last)
    if age then text = text .. "  |  " .. L.TIP_LAST:format(age) end
    return PREFIX .. text
end

function API.GetCrafterSummary(name)
    if not ns.db or type(name) ~= "string" or name == "" then return nil end
    local s = ns.Ledger:Summary(Util.FullName(name))
    return s and (PREFIX .. ns.Tooltip.SummaryLine(nil, s)) or nil
end

TrustCrafterAPI = API
