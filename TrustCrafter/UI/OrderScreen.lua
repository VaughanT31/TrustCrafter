-- TrustCrafter - your history on Blizzard's crafting orders window:
--   - Personal order: typing a crafter's name shows what you know about
--     them right beside the name box, before you send the order.
--   - Personal order: a "Find a Crafter" button beside the name box (3.1,
--     UI/FinderWindow.lua) lists crafters on your realm who know the recipe.
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
local recipientBox, UpdateRecipient

local ASK_DELAY = 1.5
local CHANNEL_WAIT = 12             -- seconds to wait for the channel after turning Find a Crafter on

-- The recipe the order form is showing.
local function FormRecipe(form)
    local transaction = form and form.transaction
    if transaction and transaction.GetRecipeID then
        local ok, id = pcall(transaction.GetRecipeID, transaction)
        if ok and type(id) == "number" then return id end
    end
    local order = form and form.order
    return order and type(order.spellID) == "number" and order.spellID or nil
end

local function StartSearch(form, box)
    local recipeID = FormRecipe(form)
    if not recipeID then
        Util.Print(ns.L.FINDER_ERR_norecipe)
        return
    end
    ns.FinderWindow:Search(recipeID, function(name)
        box:SetText(name)
        box:SetCursorPosition(0)
    end, ProfessionsCustomerOrdersFrame)
end

-- Turning Find a Crafter on from the button: join the channel, then search
-- once it's connected (or straight away for a guild-only search).
local function TurnOnAndSearch(form, box)
    ns.db.settings.finder = true
    ns.Channel:Update()
    ns.Events:Fire("TC_SETTINGS_CHANGED")
    Util.Print(ns.L.FINDER_ON)
    local waited = 0
    local function Try()
        local status = ns.Channel:Status()
        if ns.Channel:Number() or status == "noslot" or status == "blocked" or waited >= CHANNEL_WAIT then
            StartSearch(form, box)
            return
        end
        waited = waited + 1
        C_Timer.After(1, Try)
    end
    Try()
end

StaticPopupDialogs["TRUSTCRAFTER_FINDER_ON"] = {
    text = ns.L.FINDER_ASK_ON,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) TurnOnAndSearch(data.form, data.box) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
    local find = ns.Skin.Button(box, ns.L.FINDER_BUTTON, 110, 22)
    find:SetPoint("LEFT", box, "RIGHT", 10, 0)
    find:SetScript("OnClick", function()
        if ns.db.settings.finder then
            StartSearch(form, box)
        else
            StaticPopup_Show("TRUSTCRAFTER_FINDER_ON", nil, nil, { form = form, box = box })
        end
    end)
    find:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L.FINDER_BUTTON, 1, 1, 1)
        GameTooltip:AddLine(ns.L.FINDER_BUTTON_TIP, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    find:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", find, "RIGHT", 10, 0)
    text:SetWidth(240)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local askTimer
    UpdateRecipient = function()
        if not ns.db then return end
        local s, crafter, guild, realm = nil, nil, nil, nil
        local typed = box:GetText()
        if ns.db.settings.orderScreen then
            s, crafter = SummaryFor(typed)
            if typed ~= "" and not (issecretvalue and issecretvalue(typed)) then
                guild = ns.Sharing:Summary(crafter or Util.FullName(typed))
                realm = ns.Sharing:Summary(crafter or Util.FullName(typed), "realm")
            end
        end
        local parts = {}
        if s then parts[#parts + 1] = ns.Presence:ForCrafter(crafter) .. " " .. ns.Tooltip.SummaryLine(nil, s) end
        if guild then parts[#parts + 1] = ns.Tooltip.GuildLine(guild) end
        if realm then parts[#parts + 1] = ns.Tooltip.RealmLine(realm) end
        text:SetText(#parts > 0 and ("|cff66ccffTrustCrafter:|r " .. table.concat(parts, "  |  ")) or "")
    end
    -- Asks the guild about the typed name once typing stops.
    local function AskLater()
        if askTimer then askTimer:Cancel() end
        askTimer = C_Timer.NewTimer(ASK_DELAY, function()
            askTimer = nil
            local typed = box:GetText()
            if typed and #typed >= 2 and not (issecretvalue and issecretvalue(typed)) and ns.db.settings.orderScreen then
                ns.Sharing:Ask(ns.Ledger:FindCrafter(typed) or Util.FullName(typed))
            end
        end)
    end
    recipientBox = box
    box:HookScript("OnTextChanged", function()
        UpdateRecipient()
        AskLater()
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
    local s = order and ns.db and ns.db.settings.orderScreen and SummaryFor(order.crafterName)
    if s and s.filled > 0 then
        row.tcBadge:SetTexture(s.below == 0 and BADGE_GOOD or BADGE_MIXED)
        row.tcBadge:Show()
    else
        row.tcBadge:Hide()
    end
end

local function OnRowEnter(row)
    local order = RowOrder(row)
    if not order or not ns.db or not ns.db.settings.orderScreen then return end
    local s, known = SummaryFor(order.crafterName)
    local crafter = known or (order.crafterName and not (issecretvalue and issecretvalue(order.crafterName))
        and Util.FullName(order.crafterName))
    if crafter then ns.Sharing:Ask(crafter) end
    local guild = crafter and ns.Sharing:Summary(crafter)
    local realm = crafter and ns.Sharing:Summary(crafter, "realm")
    if not ns.db.settings.tooltip or not (s or guild or realm) then return end
    if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
    GameTooltip:AddLine(" ")
    local head = "|cff66ccffTrustCrafter:|r " .. Util.ShortName(crafter) .. ": "
    if s then
        GameTooltip:AddLine(head .. ns.Tooltip.SummaryLine(nil, s), 1, 1, 1, true)
        head = ""
    end
    if guild then
        GameTooltip:AddLine(head .. ns.Tooltip.GuildLine(guild), 1, 1, 1, true)
        head = ""
    end
    if realm then GameTooltip:AddLine(head .. ns.Tooltip.RealmLine(realm), 1, 1, 1, true) end
    local presence = ns.Presence:Label(order.crafterGuid or ns.Presence:GuidFor(crafter), crafter)
    if presence ~= "" then GameTooltip:AddLine(presence, 1, 1, 1) end
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

local function RefreshRecipient()
    if recipientBox and recipientBox:IsVisible() then UpdateRecipient() end
end
ns.Events:On("TC_PRESENCE_CHANGED", RefreshRecipient)
ns.Events:On("TC_SETTINGS_CHANGED", RefreshRecipient)
ns.Events:On("TC_SHARED_CHANGED", RefreshRecipient)

ns.Events:On("TC_LOGIN", function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(BLIZZARD_ADDON)
    if loaded then Hook() end
end)
