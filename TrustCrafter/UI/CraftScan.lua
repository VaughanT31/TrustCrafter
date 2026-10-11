-- TrustCrafter - adds your history with a customer to CraftScan's tooltips,
-- when CraftScan is installed:
--   TrustCrafter: you crafted 3x for them  |  150g in tips
-- Shown under the chat history when hovering a customer in CraftScan's
-- orders window, and when hovering its new request banner.
--
-- CraftScan has no API for this, so we hook what it exposes globally: the
-- order row mixin, the scanner menu frame and its banner button. Every name
-- is checked first; if CraftScan changes them, the line just doesn't show.

local _, ns = ...

local CraftScanHook = {}
ns.CraftScanHook = CraftScanHook

local ROW_TOOLTIP = "CraftScanChatHistoryTooltip"
local BANNER_TOOLTIP = "CraftScanChatHistoryBannerTooltip"

local installed = false
local bannerOrder

-- Adds the history lines to a CraftScan tooltip. Returns true when added.
function CraftScanHook.AddTo(tooltip, customer)
    if not tooltip or not tooltip:IsShown() then return false end
    if not ns.db or not ns.db.settings.tooltip then return false end
    if type(customer) ~= "string" or (issecretvalue and issecretvalue(customer)) then return false end
    local fullName = ns.Util.FullName(customer)
    if not fullName or not ns.Tooltip.HasHistory(fullName) then return false end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    ns.Tooltip.AddHistory(tooltip, fullName)
    tooltip:Show()
    return true
end

local function OnRowEnter(row)
    CraftScanHook.AddTo(_G[ROW_TOOLTIP], row and row.order and row.order.customerName)
end

local function OnBannerEnter()
    if bannerOrder then CraftScanHook.AddTo(_G[BANNER_TOOLTIP], bannerOrder.customerName) end
end

function CraftScanHook:Install()
    if installed then return true end
    local rows = _G.CraftScanCrafterOrderListElementMixin
    local menu = _G.CraftScanScannerMenu
    if type(rows) ~= "table" or type(rows.OnLineEnter) ~= "function" then return false end
    installed = true

    -- Rows copy the mixin's functions when CraftScan creates them, which
    -- happens once its orders list fills, after both addons have loaded.
    hooksecurefunc(rows, "OnLineEnter", OnRowEnter)

    if type(menu) == "table" and type(menu.TriggerAlert) == "function" and type(menu.ClearAlert) == "function" then
        hooksecurefunc(menu, "TriggerAlert", function(_, _, order)
            bannerOrder = type(order) == "table" and order or nil
        end)
        hooksecurefunc(menu, "ClearAlert", function(_, order)
            if order == bannerOrder then bannerOrder = nil end
        end)
        local banner = menu.AlertBGButton
        if banner and banner.HookScript then banner:HookScript("OnEnter", OnBannerEnter) end
    end
    return true
end

-- CraftScan is an optional dependency, so it loads first when installed;
-- the ADDON_LOADED check covers it being loaded later.
if not CraftScanHook:Install() then
    ns.Events:On("ADDON_LOADED", function(_, name)
        if name == "CraftScan" then CraftScanHook:Install() end
    end)
end
