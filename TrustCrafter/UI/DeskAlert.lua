-- TrustCrafter - Crafter Desk alerts (4.0): a small stack of cards, one per
-- new request (Data/Watch.lua), newest on top.
--
--  +- Crafter Desk ------------------------------------------ [gear] -+
--  | * Kaelyn wants [Sunfire Silk Bolt]                     2m   [x]  |
--  |   "LF tailor sunfire silk bolt max quality, my mats"             |
--  |   You: rank 1-2, max with concentration (120)  |  mats ~45g      |
--  |   Crafted 3x for them, 150g in tips  |  asked 4x today by 3      |
--  |   You'd say: Hey Kaelyn, I can make Sunfire Silk Bolt at max...  |
--  |   [Greet]  [Whisper]  [Mute item]                                |
--  +------------------------------------------------------------------+
--
-- Greet sends one whisper (Data/Replies.lua); hover it to read the reply
-- first, right-click it for another wording. Cards leave after EXPIRE, when
-- dismissed, or once greeted. Drag the header to move the stack; Pin
-- (settings.deskBarPinned) keeps the header up where you left it, even
-- with no requests waiting.
-- settings.deskCards = false keeps the cards hidden and leaves the alert
-- to the desk button (UI/DeskButton.lua) and the sound.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local DeskAlert = {}
ns.DeskAlert = DeskAlert

local WIDTH = 380
local CARD_HEIGHT = 122
local MAX_CARDS = 3
local EXPIRE = 5 * 60
local GREY = "|cff999999"

local anchor, cards
local shown = {}                   -- requests on cards, newest first

-- The alert sounds you can pick (settings.deskSoundName), by SOUNDKIT
-- name with a fallback ID in case a name is missing on this client.
DeskAlert.SOUNDS = {
    { "whisper", "TELL_MESSAGE", 3081 },
    { "invite", "IG_PLAYER_INVITE", 880 },
    { "readycheck", "READY_CHECK", 8960 },
    { "raidwarning", "RAID_WARNING", 8959 },
    { "auction", "AUCTION_WINDOW_OPEN", 5274 },
    { "ping", "MAP_PING", 3175 },
    { "toast", "UI_BNET_TOAST", 18019 },
    { "alarm", "ALARM_CLOCK_WARNING_3", 12889 },
}

function DeskAlert.PlayAlert(name)
    local pick = DeskAlert.SOUNDS[1]
    for _, sound in ipairs(DeskAlert.SOUNDS) do
        if sound[1] == name then pick = sound end
    end
    PlaySound(SOUNDKIT and SOUNDKIT[pick[2]] or pick[3], "Master")
end

local function ClassName(guid, name)
    local short = Util.ShortName(name)
    if not guid or not GetPlayerInfoByGUID then return short end
    local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
    local color = ok and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return color and ("|c" .. color.colorStr .. short .. "|r") or short
end

-- The item's link. Until the game has loaded it (GET_ITEM_INFO_RECEIVED
-- redraws the cards), the link they posted, if any.
local function ItemText(request)
    if request.itemID then
        local _, link = C_Item.GetItemInfo(request.itemID)
        if not link and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(request.itemID) end
        return link or request.link or C_Item.GetItemNameByID(request.itemID) or ("item " .. request.itemID)
    end
    if request.how == "profession" then return L.DESK_A_PROFESSION:format(request.profession or "?") end
    return L.DESK_SOMETHING
end

-- The lines a request shows, shared with the requests page:
-- what (who wants what), data (reach, crafter, mats), history, demand.
function DeskAlert.Lines(request)
    local me = Util.FullName(UnitName("player"))
    local lines = {}
    lines.what = L.DESK_WANTS:format(ClassName(request.guid, request.customer), ItemText(request))

    local data = {}
    if request.crafter and request.crafter ~= me then
        data[#data + 1] = L.DESK_ON_ALT:format(Util.ShortName(request.crafter))
    end
    local reach = request.recipeID and ns.Reach:Get(request.crafter or me, request.recipeID)
    if reach and reach.n == 0 then
        data[#data + 1] = L.DESK_NO_RANK
    elseif reach and reach.lo and reach.hi then
        local text = reach.lo == reach.hi and L.DESK_REACH_ONE:format(Util.QualityText(reach.lo))
            or L.DESK_REACH:format(Util.QualityText(reach.lo), Util.QualityText(reach.hi))
        if reach.hc and reach.hc > reach.hi then
            text = text .. " " .. L.DESK_REACH_CONC:format(Util.QualityText(reach.hc), reach.cc or 0)
        end
        local best, _, extra = ns.Reach.Best(reach)
        if extra and reach.fr then
            text = text .. " " .. L.DESK_REACH_EXTRA:format(Util.QualityText(best), ns.Reach.ReagentName(reach.fr[1]))
        end
        if reach.st then
            text = text .. "  |  " .. L.DESK_ADD_FINISH:format(C_Item.GetItemNameByID(reach.st) or ("item " .. reach.st))
        end
        data[#data + 1] = text
    elseif request.recipeID then
        data[#data + 1] = GREY .. L.DESK_REACH_UNKNOWN .. "|r"
    end
    local cost = request.recipeID and ns.Reach.MaterialCost(request.recipeID)
    if cost then data[#data + 1] = L.DESK_MATS:format(Util.FormatMoney(cost)) end
    lines.data = table.concat(data, "  |  ")

    local history = {}
    local crafted = ns.Crafted:Summary(request.customer)
    if crafted then
        local text = ns.Tooltip.CraftedLine(crafted)
        local age = Util.FormatAge(crafted.last)
        if age then text = text .. "  |  " .. L.TIP_LAST:format(age) end
        history[#history + 1] = text
    end
    local theirs = ns.Ledger:Summary(request.customer)
    if theirs then history[#history + 1] = L.DESK_THEY_CRAFTED:format(theirs.filled) end
    if #history == 0 then history[#history + 1] = GREY .. L.DESK_NEW_CUSTOMER .. "|r" end
    lines.history = table.concat(history, "  |  ")

    local times, people = ns.Watch:Demand(request)
    lines.demand = times > 1 and L.DESK_DEMAND:format(times, people) or nil
    return lines
end

local function Excerpt(text)
    local plain = (text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    plain = plain:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    if #plain > 90 then plain = plain:sub(1, 88) .. "..." end
    return GREY .. "\"" .. plain .. "\"|r"
end

local function Line(card, y, font)
    local fs = card:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 12, y)
    fs:SetPoint("RIGHT", -12, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function GreetTooltip(button)
    local request = button:GetParent().request
    if not request then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(L.DESK_GREET)
    GameTooltip:AddLine(ns.Replies:Preview(request), 1, 1, 1, true)
    local ok, why = ns.Replies:CanGreet(request)
    if not ok then GameTooltip:AddLine(L["DESK_CANT_" .. why:upper()], 1, 0.5, 0.4, true) end
    GameTooltip:AddLine(L.DESK_GREET_TIP, 0.6, 0.8, 1, true)
    GameTooltip:Show()
end

-- The actions on a request, shared by the cards, the desk button and
-- the key bindings.
function DeskAlert:Greet(request)
    local ok, why = ns.Replies:Greet(request)
    if not ok then Util.Print(L["DESK_CANT_" .. why:upper()]) end
    return ok
end

function DeskAlert:Whisper(request)
    if ChatFrame_SendTell then ChatFrame_SendTell(request.customer) end
end

function DeskAlert:Dismiss(request)
    ns.Watch:SetStatus(request, "dismissed")
end

local function CreateCard(index)
    local card = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    card:SetSize(WIDTH, CARD_HEIGHT)
    card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4 - (index - 1) * (CARD_HEIGHT + 4))
    Skin.Backdrop(card, Skin.BG, { 0.4, 0.8, 1, 0.6 })
    card:EnableMouse(true)

    card.what = Line(card, -8, "GameFontNormal")
    card.what:SetPoint("RIGHT", -52, 0)
    card.age = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.age:SetPoint("TOPRIGHT", -30, -10)
    card.close = CreateFrame("Button", nil, card, "UIPanelCloseButtonNoScripts")
    card.close:SetSize(20, 20)
    card.close:SetPoint("TOPRIGHT", -3, -3)
    card.close:SetScript("OnClick", function()
        if card.request then DeskAlert:Dismiss(card.request) end
    end)
    card.text = Line(card, -28)
    card.data = Line(card, -44)
    card.history = Line(card, -60)
    card.greeting = Line(card, -76)

    card.greet = Skin.Button(card, L.DESK_GREET, 80, 20)
    card.greet:SetPoint("BOTTOMLEFT", 10, 8)
    card.greet:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card.greet:SetScript("OnClick", function(self, mouse)
        local request = card.request
        if not request then return end
        if mouse == "RightButton" then
            ns.Replies:Reroll(request)
            GreetTooltip(self)
            return
        end
        DeskAlert:Greet(request)
    end)
    card.greet:SetScript("OnEnter", GreetTooltip)
    card.greet:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card.whisper = Skin.Button(card, L.DESK_WHISPER, 80, 20)
    card.whisper:SetPoint("LEFT", card.greet, "RIGHT", 6, 0)
    card.whisper:SetScript("OnClick", function()
        if card.request then DeskAlert:Whisper(card.request) end
    end)

    card.mute = Skin.Button(card, L.DESK_MUTE, 90, 20)
    card.mute:SetPoint("LEFT", card.whisper, "RIGHT", 6, 0)
    card.mute:SetScript("OnClick", function()
        local request = card.request
        if not (request and request.recipeID) then return end
        ns.Watch:Mute(request.recipeID)
        DeskAlert:Dismiss(request)
        Util.Print(L.DESK_MUTED:format(ItemText(request)))
    end)

    -- Hover the card for the whole message and your history in full.
    card:SetScript("OnEnter", function(self)
        local request = self.request
        if not request then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(request.customer)
        GameTooltip:AddLine(request.text, 1, 1, 1, true)
        ns.Tooltip.AddHistory(GameTooltip, request.customer)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return card
end

local function Create()
    anchor = CreateFrame("Frame", "TrustCrafterDeskAlerts", UIParent, "BackdropTemplate")
    anchor:SetSize(WIDTH, 22)
    anchor:SetFrameStrata("HIGH")
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    Skin.Backdrop(anchor)
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        ns.db.settings.deskPoint = { point, relative, x, y }
    end)
    local p = ns.db.settings.deskPoint
    if type(p) == "table" and p[1] then
        anchor:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end

    local title = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(L.DESK_TITLE)
    anchor.count = anchor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    anchor.count:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local open = Skin.Button(anchor, L.DESK_OPEN, 70, 16)
    open:SetPoint("RIGHT", -4, 0)
    open:SetScript("OnClick", function() ns.DeskWindow:Show() end)

    anchor.pin = Skin.Button(anchor, L.DESK_PIN, 60, 16)
    anchor.pin:SetPoint("RIGHT", open, "LEFT", -4, 0)
    anchor.pin:SetScript("OnClick", function()
        local s = ns.db.settings
        s.deskBarPinned = not s.deskBarPinned
        Util.Print(s.deskBarPinned and L.DESK_PINNED or L.DESK_UNPINNED)
        ns.Events:Fire("TC_SETTINGS_CHANGED")
    end)
    anchor.pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.db.settings.deskBarPinned and L.DESK_UNPIN or L.DESK_PIN)
        GameTooltip:AddLine(L.DESK_PIN_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    anchor.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cards = {}
    for i = 1, MAX_CARDS do cards[i] = CreateCard(i) end
    anchor:Hide()
end

local function Active(request, now)
    return request.status == "new" and now - (request.lastAt or request.t) < EXPIRE
end

-- The newest request still waiting, and how many are waiting.
function DeskAlert:Newest()
    local now = Util.Now()
    for _, request in ipairs(shown) do
        if Active(request, now) then return request end
    end
end

function DeskAlert:Count()
    return #shown
end

function DeskAlert:Refresh()
    if not ns.db then return end
    local now = Util.Now()
    for i = #shown, 1, -1 do
        if not Active(shown[i], now) then table.remove(shown, i) end
    end
    ns.Events:Fire("TC_DESK_ALERTS", #shown)
    local s = ns.db.settings
    local pinned = s.deskBarPinned and ns.Watch:Enabled()
    if (#shown == 0 and not pinned) or s.deskCards == false then
        if anchor then anchor:Hide() end
        return
    end
    if not anchor then Create() end
    anchor.pin:SetText(s.deskBarPinned and L.DESK_UNPIN or L.DESK_PIN)
    anchor.count:SetText(#shown == 0 and L.DESK_NONE_WAITING
        or #shown > MAX_CARDS and L.DESK_MORE:format(#shown - MAX_CARDS) or "")
    for i, card in ipairs(cards) do
        local request = shown[i]
        card.request = request
        card:SetShown(request ~= nil)
        if request then
            local lines = DeskAlert.Lines(request)
            card.what:SetText(ns.Presence:Dot(request.guid, request.customer) .. " " .. lines.what
                .. ((request.times or 1) > 1 and (" " .. GREY .. "x" .. request.times .. "|r") or ""))
            card.age:SetText(DeskAlert.Age(now - request.t))
            card.text:SetText(Excerpt(request.text))
            card.data:SetText(lines.data)
            card.history:SetText(lines.history .. (lines.demand and ("  |  " .. lines.demand) or ""))
            card.greeting:SetText(L.DESK_YOU_SAY:format(ns.Replies:Preview(request)))
            local ok = ns.Replies:CanGreet(request, now)
            card.greet:SetEnabled(ok)
            card.mute:SetShown(request.recipeID ~= nil)
        end
    end
    anchor:Show()
end

ns.Events:On("TC_DESK_REQUEST", function(_, request)
    table.insert(shown, 1, request)
    if ns.db.settings.deskSound ~= false and not InCombatLockdown() then
        DeskAlert.PlayAlert(ns.db.settings.deskSoundName)
        if FlashClientIcon then FlashClientIcon() end
    end
    DeskAlert:Refresh()
end)
ns.Events:On("TC_DESK_CHANGED", function() DeskAlert:Refresh() end)

-- "12 sec" for the first minute, then "1 min", "2 min" ... counted in
-- whole minutes.
function DeskAlert.Age(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then return L.DURATION_SEC:format(seconds) end
    return Util.FormatDuration(seconds - seconds % 60) or ""
end

-- Ages tick every second while cards are up; expiry every 15.
C_Timer.NewTicker(1, function()
    if #shown == 0 or not cards or not ns.db then return end
    local now = Util.Now()
    for _, card in ipairs(cards) do
        if card:IsShown() and card.request then card.age:SetText(DeskAlert.Age(now - card.request.t)) end
    end
end)
C_Timer.NewTicker(15, function()
    if #shown > 0 then DeskAlert:Refresh() end
end)

-- Item names arrive after the cards first draw.
local namesPending
ns.Events:On("GET_ITEM_INFO_RECEIVED", function()
    if namesPending or #shown == 0 then return end
    namesPending = true
    C_Timer.After(0.5, function()
        namesPending = false
        DeskAlert:Refresh()
    end)
end)
ns.Events:On("TC_SETTINGS_CHANGED", function() DeskAlert:Refresh() end)
ns.Events:On("TC_DB_READY", function() DeskAlert:Refresh() end)
