-- TrustCrafter - your history with customers on the crafter's side of
-- Blizzard's crafting orders window (the Crafting Orders tab of a
-- profession):
--   - Order list: a mark beside customers you have crafted for, and your
--     history with them added to the row's tooltip.
--   - Order details: a short line beside the customer's name.
-- That window is load-on-demand (Blizzard_Professions), so the hooks are
-- added once it loads. Every frame is looked up defensively: if Blizzard
-- renames something, that part is skipped, nothing breaks.

local _, ns = ...
local L, Util = ns.L, ns.Util

local CrafterOrders = {}
ns.CrafterOrders = CrafterOrders

local BLIZZARD_ADDON = "Blizzard_Professions"
local MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "

local hooked = false

local function Enabled()
    return ns.db and ns.db.settings.orderScreen
end

local function Readable(name)
    return type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name))
end

-- What you've crafted for a customer, or nil. NPC (patron) orders never
-- match, since they aren't logged.
function CrafterOrders.CraftedFor(order)
    if not order or not Readable(order.customerName) then return nil end
    if Enum.CraftingOrderType and order.orderType == Enum.CraftingOrderType.Npc then return nil end
    return ns.Crafted:Summary(Util.FullName(order.customerName))
end

-- "crafted 3x  |  45g in tips", kept short to fit beside the name.
function CrafterOrders.ShortLine(c)
    local text = L.BOARD_CRAFTED:format(c.count)
    if c.tips > 0 then text = text .. "  |  " .. L.TIP_TIPS:format(Util.FormatMoney(c.tips)) end
    return text
end

-- Order list ------------------------------------------------------------

-- The customer column: the name with a mark in front when you know them.
local function OnCustomerCell(cell, rowData)
    if not Enabled() or not cell.Text then return end
    local order = rowData and rowData.option
    if order and CrafterOrders.CraftedFor(order) then
        cell.Text:SetText(MARK .. order.customerName)
    end
end

local function RowOrder(row)
    if row.option then return row.option end
    local data = row.GetElementData and row:GetElementData()
    return data and data.option
end

local function OnRowEnter(row)
    if not Enabled() or not ns.db.settings.tooltip then return end
    local order = RowOrder(row)
    if not order or not Readable(order.customerName) then return end
    if Enum.CraftingOrderType and order.orderType == Enum.CraftingOrderType.Npc then return end
    local fullName = Util.FullName(order.customerName)
    if not ns.Tooltip.HasHistory(fullName) then return end
    if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
    GameTooltip:AddLine(" ")
    ns.Tooltip.AddHistory(GameTooltip, fullName)
    GameTooltip:Show()
end

local function HookOrderList(page)
    local scrollBox = page and page.BrowseFrame and page.BrowseFrame.OrderList and page.BrowseFrame.OrderList.ScrollBox
    if not scrollBox or not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row)
        if not row.tcHooked then
            row.tcHooked = true
            row:HookScript("OnEnter", OnRowEnter)
        end
    end, ns, true)
end

-- Order details -----------------------------------------------------------

local function HookOrderView(view)
    local info = view and view.OrderInfo
    local name = info and info.PostedByValue
    if not name or type(view.SetOrder) ~= "function" then return end
    local text = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", info.SocialDropdown or name, "RIGHT", 6, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    hooksecurefunc(view, "SetOrder", function(_, order)
        local c = Enabled() and CrafterOrders.CraftedFor(order)
        if not c then
            text:SetText("")
            return
        end
        -- Whatever room is left on the panel after the name and its button.
        local used = name:GetStringWidth() + (info.SocialDropdown and info.SocialDropdown:GetWidth() or 0) + 30
        text:SetWidth(math.max(60, (info:GetWidth() or 300) - used - 20))
        text:SetText(MARK .. CrafterOrders.ShortLine(c))
    end)
end

local function Hook()
    if hooked then return end
    local page = ProfessionsFrame and ProfessionsFrame.OrdersPage
    if not page then return end
    hooked = true
    local cell = _G.ProfessionsCrafterTableCellCustomerNameMixin
    if type(cell) == "table" and type(cell.Populate) == "function" then
        hooksecurefunc(cell, "Populate", OnCustomerCell)
    end
    pcall(HookOrderList, page)
    pcall(HookOrderView, page.OrderView)
end

ns.Events:On("ADDON_LOADED", function(_, name)
    if name == BLIZZARD_ADDON then Hook() end
end)

ns.Events:On("TC_LOGIN", function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(BLIZZARD_ADDON)
    if loaded then Hook() end
end)
