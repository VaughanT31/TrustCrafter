-- TrustCrafter - your history on Blizzard's crafting orders window:
--   - Personal order: typing a crafter's name shows what you know about
--     them right beside the name box, before you send the order.
--   - My Orders: a badge on orders from crafters you have used before, and
--     your history with them added to the row's tooltip.
-- That window is load-on-demand (Blizzard_ProfessionsCustomerOrders), so
-- the hooks are added once it loads. Every frame is looked up defensively:
-- if Blizzard renames something, that part is skipped, nothing breaks.

local _, ns = ...
local Util = ns.Util

local BLIZZARD_ADDON = "Blizzard_ProfessionsCustomerOrders"
local BADGE_GOOD = "Interface\\RaidFrame\\ReadyCheck-Ready"
local BADGE_MIXED = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local hooked = false

local function SummaryFor(name)
    if not name or name == "" or (issecretvalue and issecretvalue(name)) then return nil, nil end
    local crafter = ns.Ledger:FindCrafter(name)
    return crafter and ns.Ledger:Summary(crafter), crafter
end

-- Personal order recipient box ----------------------------------------

local function HookRecipient(form)
    local box = form and form.OrderRecipientTarget
    if not box or not box.HookScript then return end
    -- Parented to the box, so it hides along with it.
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", box, "RIGHT", 10, 0)
    text:SetWidth(280)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    box:HookScript("OnTextChanged", function(self)
        if not ns.db then return end
        local s = SummaryFor(self:GetText())
        text:SetText(s and ("|cff66ccffTrustCrafter:|r " .. ns.Tooltip.SummaryLine(nil, s)) or "")
    end)
end

-- My Orders rows ----------------------------------------------------------

local function RowOrder(row)
    if row.option then return row.option end
    local data = row.GetElementData and row:GetElementData()
    return data and data.option
end

local function UpdateBadge(row)
    if not row.tcBadge then
        row.tcBadge = row:CreateTexture(nil, "OVERLAY")
        row.tcBadge:SetSize(12, 12)
        row.tcBadge:SetPoint("RIGHT", -4, 0)
    end
    local order = RowOrder(row)
    local s = order and ns.db and SummaryFor(order.crafterName)
    if s and s.filled > 0 then
        row.tcBadge:SetTexture(s.below == 0 and BADGE_GOOD or BADGE_MIXED)
        row.tcBadge:Show()
    else
        row.tcBadge:Hide()
    end
end

local function OnRowEnter(row)
    local order = RowOrder(row)
    local s = order and ns.db and ns.db.settings.tooltip and SummaryFor(order.crafterName)
    if not s then return end
    if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff66ccffTrustCrafter:|r " .. Util.ShortName(Util.FullName(order.crafterName))
        .. ": " .. ns.Tooltip.SummaryLine(nil, s), 1, 1, 1, true)
    GameTooltip:Show()
end

local function HookMyOrders(page)
    local scrollBox = page and page.OrderList and page.OrderList.ScrollBox
    if not scrollBox or not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row)
        if not row.tcHooked then
            row.tcHooked = true
            row:HookScript("OnEnter", OnRowEnter)
        end
        UpdateBadge(row)
    end, ns, true)
end

local function Hook()
    if hooked or not ProfessionsCustomerOrdersFrame then return end
    hooked = true
    pcall(HookRecipient, ProfessionsCustomerOrdersFrame.Form)
    pcall(HookMyOrders, ProfessionsCustomerOrdersFrame.MyOrdersPage)
end

ns.Events:On("ADDON_LOADED", function(_, name)
    if name == BLIZZARD_ADDON then Hook() end
end)

ns.Events:On("TC_LOGIN", function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(BLIZZARD_ADDON)
    if loaded then Hook() end
end)
