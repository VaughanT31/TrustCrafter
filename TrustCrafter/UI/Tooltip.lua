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

local function OnUnitTooltip(tooltip)
    if not ns.db or not ns.db.settings.tooltip then return end
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name, realm = UnitFullName(unit)
    -- Names can be secret values in some restricted situations; never
    -- touch those.
    if not name or (issecretvalue and (issecretvalue(name) or (realm and issecretvalue(realm)))) then return end
    local s = ns.Ledger:Summary(Util.FullName(name, realm))
    if not s then return end
    tooltip:AddLine("|cff66ccffTrustCrafter:|r " .. Tooltip.SummaryLine(nil, s), 1, 1, 1, true)
    tooltip:Show()
end

if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end
