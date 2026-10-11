-- TrustCrafter - adds your history with a crafter to their tooltip:
--   TrustCrafter: crafted 4x for you | 4/4 met or exceeded | avg 38 min
-- Shown on player tooltips (unit frames, nameplates, mouseover in the
-- world). Rates, never stars, and only from facts the addon logged itself.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Tooltip = {}
ns.Tooltip = Tooltip

local GREEN = "|cff66dd77"
local AMBER = "|cffffaa44"
local GREY = "|cff999999"

-- One line for a crafter summary (Ledger:Summary). name is shown first
-- when given (chat output); the tooltip already has the name above it.
function Tooltip.SummaryLine(name, s)
    local parts = {}
    if s.filled > 0 then
        parts[#parts + 1] = L.TIP_CRAFTED:format(s.filled)
        local color = s.below == 0 and GREEN or AMBER
        parts[#parts + 1] = color .. L.TIP_MET:format(s.metOrBetter, s.filled) .. "|r"
        if s.avgTurnaround then
            parts[#parts + 1] = L.TIP_AVG:format(Util.FormatDuration(s.avgTurnaround))
        end
    end
    if s.notFilled > 0 then
        parts[#parts + 1] = GREY .. L.TIP_NOT_FILLED:format(s.notFilled) .. "|r"
    end
    local line = table.concat(parts, "  |  ")
    return name and (name .. ": " .. line) or line
end

-- "you crafted 3x for them  |  45g in tips"
function Tooltip.CraftedLine(c)
    local text = L.TIP_YOU_CRAFTED:format(c.count)
    if c.tips > 0 then text = text .. "  |  " .. L.TIP_TIPS:format(Util.FormatMoney(c.tips)) end
    return text
end

function Tooltip.HasHistory(fullName)
    return ns.Ledger:Summary(fullName) ~= nil or ns.Crafted:Summary(fullName) ~= nil
end

-- Adds both sides of your history with a player ("Name-Realm") to a
-- tooltip: as your crafter, and as a customer you crafted for. Used here
-- and by UI/CraftScan.lua. Returns true when anything was added.
function Tooltip.AddHistory(tooltip, fullName)
    local s = ns.Ledger:Summary(fullName)
    local crafted = ns.Crafted:Summary(fullName)
    if not s and not crafted then return false end
    if s then
        tooltip:AddLine("|cff66ccffTrustCrafter:|r " .. Tooltip.SummaryLine(nil, s), 1, 1, 1, true)
    end
    if crafted then
        local line = Tooltip.CraftedLine(crafted)
        tooltip:AddLine(s and line or ("|cff66ccffTrustCrafter:|r " .. line), 1, 1, 1, true)
    end
    return true
end

local function OnUnitTooltip(tooltip)
    if not ns.db or not ns.db.settings.tooltip then return end
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    -- The unit token and names can be secret values in restricted content
    -- (instances, combat); never touch those.
    if not unit or (issecretvalue and issecretvalue(unit)) or not UnitIsPlayer(unit) then return end
    local name, realm = UnitFullName(unit)
    if not name or (issecretvalue and (issecretvalue(name) or (realm and issecretvalue(realm)))) then return end
    if Tooltip.AddHistory(tooltip, Util.FullName(name, realm)) then tooltip:Show() end
end

if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end
