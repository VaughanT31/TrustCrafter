-- TrustCrafter - the Crafter Desk window (4.0), /tc desk.
--
-- Left: your characters on this realm. Tick the ones to watch for; one
-- that hasn't opened its professions since 4.0 says so. Click one to see
-- its watchlist and replies.
--   Requests   everything the desk picked up in the last week, newest
--              first, with today's numbers (asked, greeted, ordered).
--              Right-click a request to greet, whisper, mute the item or
--              ignore the player.
--   Items      the selected character's watchlist: every recipe it knows,
--              the quality it makes, on or off, and extra keywords; "only
--              max quality" limits it to what it makes at max quality.
--   Messages   the selected character's own replies, one per line, with
--              placeholders, and their own commission.
--   Settings   on/off, which chats, tone, default commission, the request
--              and ignore words, and a box to test a chat line.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local DeskWindow = {}
ns.DeskWindow = DeskWindow

local SIDEBAR = 200
local WIDTH, HEIGHT = 600 + SIDEBAR + 12, 660
local PAD = 16
local PAGE_W = WIDTH - 2 * PAD - SIDEBAR - 12
local CHAR_ROW = 34
local CHAR_ROWS = 16
local ITEM_ROWS = 22
local SCALE_MIN, SCALE_MAX, SCALE_DEFAULT = 0.8, 1.8, 1.2
local ROW = 20
local ROWS = 24
local GREY = "|cff999999"
local CHAT_LINES = 10                 -- whispers shown when hovering a request

local STATUS_COLORS = { new = "|cff66ccff", greeted = "|cff66dd77", ordered = "|cffffd100", dismissed = GREY }

local frame, pages, tabs, rows, charRows, itemRows
local view = "requests"
local offset = 0
local selected                     -- the character in the Items and Messages pages
local itemOffset, itemFilter, itemSearch, itemPicked = 0, "current", "", nil
local charOffset = 0

local function S() return ns.db.settings end

local function Changed()
    ns.Events:Fire("TC_SETTINGS_CHANGED")
end

-- Requests page ------------------------------------------------------------

local function RowMenu(row, request)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(request.customer)
        if ns.Replies:CanGreet(request) then
            root:CreateButton(L.DESK_GREET, function() ns.Replies:Greet(request) end)
        end
        root:CreateButton(L.DESK_WHISPER, function()
            if ChatFrame_SendTell then ChatFrame_SendTell(request.customer) end
        end)
        if request.recipeID then
            root:CreateButton(L.DESK_MUTE, function() ns.Watch:Mute(request.recipeID) end)
        end
        root:CreateButton(L.DESK_IGNORE, function()
            ns.Sharing:Ignore(request.customer)
            Util.Print(L.IGNORED:format(request.customer))
        end)
    end)
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
    row:SetPoint("RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Skin.RowBand(row)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    local function Cell(x, w, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.time = Cell(4, 54)
    row.who = Cell(62, 120)
    row.what = Cell(186, 210)
    row.crafter = Cell(400, 90)
    row.status = Cell(494, 72)
    row:SetScript("OnClick", function(self, mouse)
        if not self.request then return end
        if mouse == "RightButton" then
            RowMenu(self, self.request)
        elseif ChatFrame_SendTell then
            ChatFrame_SendTell(self.request.customer)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local request = self.request
        if not request then return end
        local lines = ns.DeskAlert.Lines(request)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(lines.what)
        GameTooltip:AddLine(request.text, 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L.DESK_ASKED_AT:format(date("%H:%M", request.lastAt or request.t), Util.FormatDate(request.t)), 0.6, 0.6, 0.6)
        if lines.data ~= "" then GameTooltip:AddLine(lines.data, 1, 1, 1, true) end
        GameTooltip:AddLine(lines.history, 1, 1, 1, true)
        if lines.demand then GameTooltip:AddLine(lines.demand, 1, 1, 1, true) end
        -- The whispers since, newest last.
        local chat = ns.Watch:Chat(request.customer)
        if #chat > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.DESK_CHAT_TITLE)
            local short = Util.ShortName(request.customer)
            for i = math.max(1, #chat - CHAT_LINES + 1), #chat do
                local m = chat[i]
                local stamp = date("%H:%M", m.t)
                if m.out then
                    GameTooltip:AddLine(L.DESK_CHAT_OUT:format(stamp, m.text), 1, 0.5, 1, true)
                else
                    GameTooltip:AddLine(L.DESK_CHAT_IN:format(stamp, short, m.text), 1, 0.5, 1, true)
                end
            end
            if #chat > CHAT_LINES then GameTooltip:AddLine(L.DESK_CHAT_MORE:format(#chat - CHAT_LINES), 0.6, 0.6, 0.6) end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.DESK_ROW_TIP, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function BuildRequests(page)
    page.summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.summary:SetPoint("TOPLEFT", 0, 0)
    page.summary:SetPoint("RIGHT", 0, 0)
    page.summary:SetJustifyH("LEFT")

    local heads = { { 4, L.DESK_COL_TIME }, { 62, L.DESK_COL_WHO }, { 186, L.DESK_COL_WHAT }, { 400, L.DESK_COL_CRAFTER }, { 494, L.DESK_COL_STATUS } }
    for _, h in ipairs(heads) do
        local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[1], -24)
        fs:SetText(h[2])
    end
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 0, -42)
    list:SetPoint("RIGHT", 0, 0)
    list:SetHeight(ROWS * ROW)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        DeskWindow:Refresh()
    end)
    rows = {}
    for i = 1, ROWS do rows[i] = CreateRow(list, i) end

    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("TOPLEFT", 0, -50)
    page.empty:SetPoint("RIGHT", 0, 0)
    page.empty:SetJustifyH("LEFT")
end

local function ItemShort(request)
    if request.itemID then
        return C_Item.GetItemNameByID(request.itemID) or ("item " .. request.itemID)
    end
    if request.how == "profession" then return L.DESK_A_PROFESSION:format(request.profession or "?") end
    return L.DESK_SOMETHING
end

local function RefreshRequests(page)
    local now = Util.Now()
    local list = ns.Watch:Visible(now)
    local asked, greeted, ordered = ns.Watch:Today()
    page.summary:SetText(L.DESK_TODAY:format(asked, greeted, ordered))
    local count = #list
    offset = math.min(offset, math.max(0, count - ROWS))
    for i, row in ipairs(rows) do
        local request = list[count - offset - i + 1]
        row.request = request
        row:SetShown(request ~= nil)
        if request then
            local age = now - (request.lastAt or request.t)
            row.time:SetText(age < 60 and L.DESK_JUST_NOW or Util.FormatDuration(age))
            row.who:SetText(Util.ShortName(request.customer) .. ((request.times or 1) > 1 and (GREY .. " x" .. request.times .. "|r") or ""))
            row.what:SetText(ItemShort(request))
            row.crafter:SetText(request.crafter and Util.ShortName(request.crafter) or GREY .. "-|r")
            row.status:SetText((STATUS_COLORS[request.status] or "") .. L["DESK_STATUS_" .. request.status:upper()] .. "|r")
        end
    end
    local empty = ""
    if count == 0 then
        empty = not ns.Watch:Enabled() and L.DESK_EMPTY_OFF
            or #ns.Watch:Requests() > 0 and L.DESK_EMPTY_QUIET or L.DESK_EMPTY
    end
    page.empty:SetText(empty)
end

-- Ages tick and quiet requests drop off while the list is open.
C_Timer.NewTicker(15, function()
    if frame and frame:IsShown() and view == "requests" then DeskWindow:Refresh() end
end)

-- Settings page --------------------------------------------------------------

local function Check(parent, field, label, tip, x, y, onChange)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    box:SetPoint("TOPLEFT", x, y)
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    box.text:SetText(label)
    box.field = field
    box:SetScript("OnClick", function(self)
        S()[field] = self:GetChecked() and true or false
        if onChange then onChange(S()[field]) end
        Changed()
        DeskWindow:Refresh()
    end)
    if tip then
        box:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return box
end

local function Box(parent, width, y, x)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", x or 0, y)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    Skin.Backdrop(box, { 0, 0, 0, 0.5 }, Skin.BORDER)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function Label(parent, text, y, x)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x or 0, y)
    fs:SetText(text)
    return fs
end

-- A made-up request, to show what the chosen tone sounds like.
local function SampleRequest()
    return { customer = "Kaelyn-" .. Util.Realm(), recipeID = 1, sampleItem = L.DESK_SAMPLE_ITEM,
        asks = { quality = true, mats = "theirs" } }
end

local function BuildSettings(page)
    page.checks = {}
    local function Add(...) local c = Check(page, ...) page.checks[#page.checks + 1] = c return c end
    Add("desk", L.DESK_OPT_ON, L.DESK_OPT_ON_TIP, 0, 0, function(on) Util.Print(on and L.DESK_ON or L.DESK_OFF) end)
    Label(page, L.DESK_OPT_WATCH, -30)
    Add("deskTrade", L.DESK_OPT_TRADE, nil, 0, -48)
    Add("deskServices", L.DESK_OPT_SERVICES, nil, 130, -48)
    Add("deskGeneral", L.DESK_OPT_GENERAL, nil, 260, -48)
    Add("deskWhispers", L.DESK_OPT_WHISPERS, nil, 390, -48)
    Add("deskAlts", L.DESK_OPT_ALTS, L.DESK_OPT_ALTS_TIP, 0, -72)
    Add("deskSound", L.DESK_OPT_SOUND, nil, 260, -72)
    Add("busy", L.OPT_BUSY, L.OPT_BUSY_TIP, 390, -72)

    Label(page, L.DESK_OPT_TONE, -104)
    page.tones = {}
    for i, tone in ipairs(ns.Replies.TONES) do
        local tab = Skin.Tab(page, L["DESK_TONE_" .. tone:upper()], 90, 20)
        tab:SetPoint("TOPLEFT", 120 + (i - 1) * 94, -102)
        tab:SetScript("OnClick", function()
            S().deskTone = tone
            DeskWindow:Refresh()
        end)
        page.tones[tone] = tab
    end
    page.sample = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.sample:SetPoint("TOPLEFT", 0, -128)
    page.sample:SetPoint("RIGHT", 0, 0)
    page.sample:SetJustifyH("LEFT")

    Label(page, L.DESK_OPT_COMMISSION_DEFAULT, -164)
    page.commission = Box(page, 330, -160, 120)
    page.commission:SetMaxLetters(80)
    page.commission:SetScript("OnTextChanged", function(self, user)
        if user then S().deskCommission = self:GetText() DeskWindow:RefreshSample() end
    end)
    Add("deskCommissionAlways", L.DESK_OPT_ALWAYS, L.DESK_OPT_ALWAYS_TIP, 456, -160)

    Label(page, L.DESK_OPT_WORDS, -196)
    page.words = Box(page, PAGE_W - 70, -214)
    page.words:SetScript("OnTextChanged", function(self, user) if user then S().deskWords = self:GetText() end end)
    local reset1 = Skin.Button(page, L.DESK_RESET, 64, 22)
    reset1:SetPoint("LEFT", page.words, "RIGHT", 6, 0)
    reset1:SetScript("OnClick", function() S().deskWords = nil DeskWindow:Refresh() end)

    Label(page, L.DESK_OPT_IGNORE, -244)
    page.ignore = Box(page, PAGE_W - 70, -262)
    page.ignore:SetScript("OnTextChanged", function(self, user) if user then S().deskIgnore = self:GetText() end end)
    local reset2 = Skin.Button(page, L.DESK_RESET, 64, 22)
    reset2:SetPoint("LEFT", page.ignore, "RIGHT", 6, 0)
    reset2:SetScript("OnClick", function() S().deskIgnore = nil DeskWindow:Refresh() end)

    Label(page, L.DESK_OPT_TEST, -294)
    page.test = Box(page, PAGE_W, -312)
    page.testResult = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.testResult:SetPoint("TOPLEFT", 0, -340)
    page.testResult:SetPoint("RIGHT", 0, 0)
    page.testResult:SetJustifyH("LEFT")
    page.test:SetScript("OnTextChanged", function(self) DeskWindow:Test(self:GetText()) end)
    -- Shift-click an item into the test box.
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and page.test:HasFocus() then page.test:Insert(link) end
    end)

    page.recipes = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.recipes:SetPoint("TOPLEFT", 0, -372)
    page.recipes:SetPoint("RIGHT", 0, 0)
    page.recipes:SetJustifyH("LEFT")

    page.unmute = Skin.Button(page, L.DESK_UNMUTE, 140, 22)
    page.unmute:SetPoint("TOPLEFT", 0, -404)
    page.unmute:SetScript("OnClick", function()
        S().deskMuted = {}
        DeskWindow:Refresh()
    end)
end

function DeskWindow:RefreshSample()
    local page = pages and pages.settings
    if not page then return end
    local request = SampleRequest()
    local text = ns.Replies.Build(request, S(), Util.FullName(UnitName("player")))
    page.sample:SetText(GREY .. L.DESK_SAMPLE .. "|r " .. text)
end

function DeskWindow:Test(text)
    local page = pages.settings
    local match, why, word = ns.Watch:Test(text)
    if match then
        local request = { itemID = match.itemID, how = match.how, profession = match.crafter and match.crafter.profession }
        local who = match.crafter and Util.ShortName(match.crafter.name) or "?"
        page.testResult:SetText("|cff66dd77" .. L.DESK_TEST_YES:format(ItemShort(request), who, L["DESK_HOW_" .. match.how:upper()]) .. "|r")
    elseif why == "empty" then
        page.testResult:SetText(GREY .. L.DESK_TEST_HINT .. "|r")
    elseif why == "ignore" then
        page.testResult:SetText("|cffff8866" .. L.DESK_TEST_IGNORED:format(word) .. "|r")
    elseif why == "noword" then
        page.testResult:SetText("|cffff8866" .. L.DESK_TEST_NOWORD .. "|r")
    elseif why == "muted" then
        page.testResult:SetText("|cffff8866" .. L.DESK_TEST_MUTED .. "|r")
    else
        page.testResult:SetText("|cffff8866" .. L.DESK_TEST_NOMATCH .. "|r")
    end
end

local function RefreshSettings(page)
    for _, box in ipairs(page.checks) do
        box:SetChecked(S()[box.field] and true or false)
    end
    for tone, tab in pairs(page.tones) do tab:SetActive((S().deskTone or "friendly") == tone) end
    if not page.commission:HasFocus() then page.commission:SetText(S().deskCommission or "") end
    if not page.words:HasFocus() then
        page.words:SetText(S().deskWords or ns.Watch.DEFAULT_WORDS)
        page.words:SetCursorPosition(0)
    end
    if not page.ignore:HasFocus() then
        page.ignore:SetText(S().deskIgnore or ns.Watch.DEFAULT_IGNORE)
        page.ignore:SetCursorPosition(0)
    end
    local recipes, characters = ns.Watch:RecipeCount()
    page.recipes:SetText(recipes > 0 and L.DESK_RECIPES:format(recipes, characters) or L.DESK_RECIPES_NONE)
    local muted = 0
    for _ in pairs(S().deskMuted or {}) do muted = muted + 1 end
    page.unmute:SetText(L.DESK_UNMUTE_N:format(muted))
    page.unmute:SetEnabled(muted > 0)
    DeskWindow:RefreshSample()
    DeskWindow:Test(page.test:GetText())
end

-- Characters ------------------------------------------------------------------

local GREEN = "|cff66dd77"

local function ShortProfessions(c)
    if c.recipes == 0 then return GREY .. L.DESK_CHAR_NOT_SCANNED .. "|r" end
    local list = {}
    for _, p in ipairs(c.professions) do list[#list + 1] = (p.name or "?") .. " " .. p.count end
    return GREY .. table.concat(list, ", ") .. "|r"
end

local function CreateCharRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(CHAR_ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * CHAR_ROW)
    row:SetPoint("RIGHT", 0, 0)
    row.band = Skin.RowBand(row)
    row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
    row.selectedBg:SetAllPoints()
    row.selectedBg:SetColorTexture(1, 0.82, 0.15, 0.12)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        if row.char then ns.Watch:SetChar(row.char.name, "off", not self:GetChecked()) end
        DeskWindow:Refresh()
    end)
    row.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DESK_CHAR_WATCH)
        GameTooltip:AddLine(L.DESK_CHAR_WATCH_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 24, -3)
    row.name:SetPoint("RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", 24, -18)
    row.sub:SetPoint("RIGHT", -4, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouse)
        if not self.char then return end
        if mouse == "RightButton" then
            StaticPopup_Show("TRUSTCRAFTER_DESK_HIDE", Util.ShortName(self.char.name), nil, self.char.name)
            return
        end
        selected = self.char.name
        itemOffset, itemPicked = 0, nil
        if view == "requests" or view == "settings" then DeskWindow:SetView("items") else DeskWindow:Refresh() end
    end)
    row:SetScript("OnEnter", function(self)
        local c = self.char
        if not c then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(c.name)
        for _, p in ipairs(c.professions) do
            GameTooltip:AddDoubleLine(p.name or "?", L.DESK_CHAR_PROF:format(p.count, p.skill or 0, p.max or 0), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        if c.recipes == 0 then GameTooltip:AddLine(L.DESK_CHAR_NOT_SCANNED_TIP, 1, 0.6, 0.4, true) end
        if c.scannedAt then GameTooltip:AddLine(L.DESK_CHAR_SCANNED:format(Util.FormatAge(c.scannedAt) or "?"), 0.6, 0.6, 0.6) end
        GameTooltip:AddLine(L.DESK_CHAR_CLICK, 0.6, 0.8, 1, true)
        GameTooltip:AddLine(L.DESK_CHAR_RIGHT_CLICK, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function BuildCharacters(side)
    local title = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(L.DESK_CHARACTERS)
    local list = CreateFrame("Frame", nil, side)
    list:SetPoint("TOPLEFT", 0, -20)
    list:SetPoint("RIGHT", 0, 0)
    list:SetHeight(CHAR_ROWS * CHAR_ROW)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        charOffset = math.max(0, charOffset - delta * 2)
        DeskWindow:Refresh()
    end)
    charRows = {}
    for i = 1, CHAR_ROWS do charRows[i] = CreateCharRow(list, i) end
    side.hint = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    side.hint:SetPoint("BOTTOMLEFT", 0, 0)
    side.hint:SetPoint("RIGHT", 0, 0)
    side.hint:SetJustifyH("LEFT")
    side.hint:SetText(L.DESK_CHAR_HINT)
end

local function RefreshCharacters()
    local list = ns.Watch:Characters()
    if not selected then
        local me = Util.FullName(UnitName("player"))
        for _, c in ipairs(list) do if c.name == me then selected = me end end
        selected = selected or (list[1] and list[1].name)
    end
    charOffset = math.min(charOffset, math.max(0, #list - CHAR_ROWS))
    for i, row in ipairs(charRows) do
        local c = list[charOffset + i]
        row.char = c
        row:SetShown(c ~= nil)
        if c then
            row.check:SetChecked(not c.off)
            row.check:SetShown(c.recipes > 0)
            row.name:SetText((c.name == selected and "|cffffd100" or (c.off and GREY or "")) .. Util.ShortName(c.name)
                .. (c.maxOnly and (" " .. GREEN .. L.DESK_CHAR_MAX_TAG .. "|r") or "") .. ((c.name == selected or c.off) and "|r" or ""))
            row.sub:SetText(ShortProfessions(c))
            row.selectedBg:SetShown(c.name == selected)
        end
    end
end

-- Items page ---------------------------------------------------------------------

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return name
end

-- "R1-R2", plus the quality with concentration, or a grey dash.
local function ReachText(reach)
    if reach and reach.n == 0 then return GREY .. L.DESK_NO_RANK .. "|r" end
    if not reach or not reach.lo then return GREY .. "-|r" end
    local text = reach.lo == reach.hi and Util.QualityText(reach.lo) or (Util.QualityText(reach.lo) .. "-" .. Util.QualityText(reach.hi))
    if reach.hc and reach.hc > reach.hi then text = text .. " " .. GREY .. "(|r" .. Util.QualityText(reach.hc) .. GREY .. ")|r" end
    local best, _, extra = ns.Reach.Best(reach)
    if extra then text = text .. " " .. GREY .. "+|r" .. Util.QualityText(best) end
    return text
end

local function VisibleItems()
    if not selected then return {} end
    local search = itemSearch:lower()
    local list = {}
    for _, item in ipairs(ns.Watch:RecipeList(selected)) do
        item.name = ItemName(item.itemID)
        local shown = (itemFilter == "all" or item.current)
            and (search == "" or (item.name and item.name:lower():find(search, 1, true)) or (item.keys and item.keys:lower():find(search, 1, true)))
        if shown then list[#list + 1] = item end
    end
    table.sort(list, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        if (a.profession or "") ~= (b.profession or "") then return (a.profession or "") < (b.profession or "") end
        return (a.name or "~") < (b.name or "~")
    end)
    return list
end

local function CreateItemRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
    row:SetPoint("RIGHT", 0, 0)
    Skin.RowBand(row)
    row.picked = row:CreateTexture(nil, "BACKGROUND")
    row.picked:SetAllPoints()
    row.picked:SetColorTexture(1, 0.82, 0.15, 0.12)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(18, 18)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        if row.item then ns.Watch:SetItem(selected, row.item.recipeID, "off", not self:GetChecked()) end
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 22, 0)
    local function Cell(x, w, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.name = Cell(42, 210)
    row.prof = Cell(256, 90)
    row.reach = Cell(350, 80)
    row.keys = Cell(434, PAGE_W - 438)
    row:SetScript("OnClick", function(self)
        if not self.item then return end
        itemPicked = self.item.recipeID
        DeskWindow:Refresh()
        local page = pages.items
        page.keys:SetFocus()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.item.itemID)
        GameTooltip:AddLine(" ")
        local reach = self.item.reach
        if reach and reach.lo then
            GameTooltip:AddLine(L.DESK_ITEM_REACH:format(ReachText({ lo = reach.lo, hi = reach.hi })), 1, 1, 1, true)
            if reach.hc and reach.hc > reach.hi then
                GameTooltip:AddLine(L.DESK_ITEM_REACH_CONC:format(Util.QualityText(reach.hc), reach.cc or 0), 1, 1, 1, true)
            end
            local best, conc, extra = ns.Reach.Best(reach)
            if extra and reach.fr then
                GameTooltip:AddLine(L[conc and "DESK_ITEM_REACH_EXTRA_CONC" or "DESK_ITEM_REACH_EXTRA"]:format(Util.QualityText(best), reach.fcc or 0), 1, 1, 1, true)
                for _, itemID in ipairs(reach.fr) do
                    local cost = ns.Reach.ReagentCost(itemID)
                    GameTooltip:AddLine("  " .. ns.Reach.ReagentName(itemID) .. (cost and ("  ~" .. Util.FormatMoney(cost)) or ""), 0.8, 0.8, 0.8, true)
                end
            end
            if reach.st then
                local cost = ns.Reach.ReagentCost(reach.st)
                GameTooltip:AddLine(L.DESK_ITEM_FINISH:format(ns.Reach.ReagentName(reach.st)
                    .. (cost and ("  ~" .. Util.FormatMoney(cost)) or "")), 0.4, 1, 0.5, true)
            end
        elseif reach and reach.n == 0 then
            GameTooltip:AddLine(L.DESK_NO_RANK_TIP, 1, 1, 1, true)
        end
        local auto = ns.Watch:AutoKeysFor(self.item.recipeID)
        if auto then GameTooltip:AddLine(L.DESK_ITEM_AUTO:format(table.concat(auto, ", ")), 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(L.DESK_ITEM_CLICK, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function BuildItems(page)
    page.title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.title:SetPoint("TOPLEFT", 0, 0)
    page.maxOnly = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.maxOnly:SetSize(22, 22)
    page.maxOnly:SetPoint("TOPRIGHT", -150, 4)
    page.maxOnly.text = page.maxOnly:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.maxOnly.text:SetPoint("LEFT", page.maxOnly, "RIGHT", 2, 0)
    page.maxOnly.text:SetText(L.DESK_ITEMS_MAX_ONLY)
    page.maxOnly:SetScript("OnClick", function(self)
        if selected then ns.Watch:SetChar(selected, "maxOnly", self:GetChecked()) end
        DeskWindow:Refresh()
    end)
    page.maxOnly:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DESK_ITEMS_MAX_ONLY)
        GameTooltip:AddLine(L.DESK_ITEMS_MAX_ONLY_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    page.maxOnly:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page.search = Box(page, 170, -24)
    page.search:SetScript("OnTextChanged", function(self)
        itemSearch, itemOffset = self:GetText(), 0
        DeskWindow:Refresh()
    end)
    page.searchHint = page.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.searchHint:SetPoint("LEFT", 6, 0)
    page.searchHint:SetText(L.DESK_ITEMS_SEARCH)
    page.filters = {}
    for i, f in ipairs({ "current", "all" }) do
        local tab = Skin.Tab(page, L["DESK_ITEMS_" .. f:upper()], 100, 20)
        tab:SetPoint("TOPLEFT", 178 + (i - 1) * 104, -25)
        tab:SetScript("OnClick", function()
            itemFilter, itemOffset = f, 0
            DeskWindow:Refresh()
        end)
        page.filters[f] = tab
    end
    local function Bulk(off)
        for _, item in ipairs(VisibleItems()) do ns.Watch:SetItem(selected, item.recipeID, "off", off) end
        DeskWindow:Refresh()
    end
    page.all = Skin.Button(page, L.DESK_ITEMS_WATCH_ALL, 84, 20)
    page.all:SetPoint("TOPRIGHT", -88, -25)
    page.all:SetScript("OnClick", function() Bulk(false) end)
    page.none = Skin.Button(page, L.DESK_ITEMS_WATCH_NONE, 84, 20)
    page.none:SetPoint("TOPRIGHT", 0, -25)
    page.none:SetScript("OnClick", function() Bulk(true) end)

    for _, h in ipairs({ { 0, L.DESK_ITEMS_COL_WATCH }, { 42, L.DESK_ITEMS_COL_ITEM }, { 256, L.DESK_ITEMS_COL_PROF },
        { 350, L.DESK_ITEMS_COL_QUALITY }, { 434, L.DESK_ITEMS_COL_KEYS } }) do
        local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[1], -54)
        fs:SetText(h[2])
    end
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 0, -70)
    list:SetPoint("RIGHT", 0, 0)
    list:SetHeight(ITEM_ROWS * ROW)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        itemOffset = math.max(0, itemOffset - delta * 3)
        DeskWindow:Refresh()
    end)
    itemRows = {}
    for i = 1, ITEM_ROWS do itemRows[i] = CreateItemRow(list, i) end
    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("TOPLEFT", 0, -78)
    page.empty:SetPoint("RIGHT", 0, 0)
    page.empty:SetJustifyH("LEFT")

    page.keysLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    page.keysLabel:SetPoint("TOPLEFT", 0, -78 - ITEM_ROWS * ROW)
    page.keysLabel:SetPoint("RIGHT", 0, 0)
    page.keysLabel:SetJustifyH("LEFT")
    page.keysLabel:SetWordWrap(false)
    page.keys = Box(page, PAGE_W, -96 - ITEM_ROWS * ROW)
    page.keys:SetScript("OnTextChanged", function(self, user)
        if user and selected and itemPicked then ns.Watch:SetItem(selected, itemPicked, "keys", self:GetText()) end
    end)
    page.keys:SetScript("OnEnterPressed", function(self) self:ClearFocus() DeskWindow:Refresh() end)
end

local function RefreshItems(page)
    page.title:SetText(selected and L.DESK_ITEMS_TITLE:format(Util.ShortName(selected)) or L.DESK_PICK_CHAR)
    page.maxOnly:SetChecked(selected and ns.Watch.CharSettings(selected).maxOnly and true or false)
    page.searchHint:SetShown(page.search:GetText() == "")
    for f, tab in pairs(page.filters) do tab:SetActive(f == itemFilter) end
    local list = VisibleItems()
    itemOffset = math.min(itemOffset, math.max(0, #list - ITEM_ROWS))
    local pickedItem
    for _, item in ipairs(list) do if item.recipeID == itemPicked then pickedItem = item end end
    for i, row in ipairs(itemRows) do
        local item = list[itemOffset + i]
        row.item = item
        row:SetShown(item ~= nil)
        if item then
            row.check:SetChecked(not item.off)
            row.icon:SetTexture(C_Item.GetItemIconByID(item.itemID))
            row.name:SetText((item.off and GREY or "") .. (item.name or ("item " .. item.itemID)) .. (item.off and "|r" or ""))
            row.prof:SetText(GREY .. (item.profession or "") .. "|r")
            local ranked = not (item.reach and item.reach.n == 0)
            row.reach:SetText(ReachText(item.reach) .. (ranked and item.grade == 2 and (" " .. GREEN .. L.DESK_ITEMS_MAX .. "|r") or ""))
            local auto = ns.Watch:AutoKeysFor(item.recipeID)
            auto = auto and (GREY .. table.concat(auto, ", ") .. "|r") or ""
            row.keys:SetText(item.keys and item.keys ~= "" and (item.keys .. (auto ~= "" and ", " .. auto or "")) or auto)
            row.picked:SetShown(item.recipeID == itemPicked)
        end
    end
    local empty = ""
    if not selected then
        empty = L.DESK_PICK_CHAR
    elseif #list == 0 then
        empty = itemSearch ~= "" and L.DESK_ITEMS_NONE_SEARCH or L.DESK_CHAR_NOT_SCANNED_TIP
    end
    page.empty:SetText(empty)
    page.keysLabel:SetText(pickedItem and L.DESK_ITEMS_KEYS_FOR:format(pickedItem.name or "?") or GREY .. L.DESK_ITEMS_KEYS_HINT .. "|r")
    page.keys:SetEnabled(pickedItem ~= nil)
    if not page.keys:HasFocus() then page.keys:SetText(pickedItem and pickedItem.keys or "") end
end

-- Messages page ------------------------------------------------------------------

local function BuildMessages(page)
    page.title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.title:SetPoint("TOPLEFT", 0, 0)
    page.help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.help:SetPoint("TOPLEFT", 0, -20)
    page.help:SetPoint("RIGHT", 0, 0)
    page.help:SetJustifyH("LEFT")
    page.help:SetText(L.DESK_MSG_HELP)

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -82)
    scroll:SetSize(PAGE_W - 30, 150)
    local bg = CreateFrame("Frame", nil, page, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", scroll, -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, 26, -4)
    Skin.Backdrop(bg, { 0, 0, 0, 0.5 }, Skin.BORDER)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(PAGE_W - 34)
    edit:SetMaxLetters(2000)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self, user)
        if user and selected then
            ns.Watch:SetChar(selected, "greeting", self:GetText())
            DeskWindow:RefreshPreview()
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    page.edit = edit

    Label(page, L.DESK_MSG_COMMISSION, -250)
    page.commission = Box(page, PAGE_W - 170, -246, 170)
    page.commission:SetMaxLetters(80)
    page.commission:SetScript("OnTextChanged", function(self, user)
        if user and selected then
            ns.Watch:SetChar(selected, "commission", self:GetText())
            DeskWindow:RefreshPreview()
        end
    end)

    Label(page, L.DESK_MSG_PREVIEW, -284)
    page.preview = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.preview:SetPoint("TOPLEFT", 0, -304)
    page.preview:SetPoint("RIGHT", 0, 0)
    page.preview:SetJustifyH("LEFT")

    local again = Skin.Button(page, L.DESK_MSG_ANOTHER, 130, 22)
    again:SetPoint("TOPLEFT", 0, -350)
    again:SetScript("OnClick", function() DeskWindow:RefreshPreview() end)
    local copy = Skin.Button(page, L.DESK_MSG_COPY, 170, 22)
    copy:SetPoint("LEFT", again, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function()
        if not selected then return end
        local cs = ns.Watch.CharSettings(selected)
        for _, c in ipairs(ns.Watch:Characters()) do
            if c.name ~= selected and c.recipes > 0 then
                ns.Watch:SetChar(c.name, "greeting", cs.greeting or "")
                ns.Watch:SetChar(c.name, "commission", cs.commission or "")
            end
        end
        Util.Print(L.DESK_MSG_COPIED)
    end)
end

function DeskWindow:RefreshPreview()
    local page = pages and pages.messages
    if not page or not selected then return end
    local request = { customer = "Kaelyn-" .. Util.Realm(), recipeID = 1, sampleItem = L.DESK_SAMPLE_ITEM, crafter = selected,
        asks = { quality = true, mats = "theirs", price = true } }
    local text = ns.Replies.Build(request, S(), Util.FullName(UnitName("player")))
    page.preview:SetText(text)
end

local function RefreshMessages(page)
    page.title:SetText(selected and L.DESK_MSG_TITLE:format(Util.ShortName(selected)) or L.DESK_PICK_CHAR)
    local cs = selected and ns.Watch.CharSettings(selected) or {}
    if not page.edit:HasFocus() then page.edit:SetText(cs.greeting or "") end
    if not page.commission:HasFocus() then page.commission:SetText(cs.commission or "") end
    DeskWindow:RefreshPreview()
end

-- Window ---------------------------------------------------------------------

local VIEWS = { "requests", "items", "messages", "settings" }

StaticPopupDialogs["TRUSTCRAFTER_DESK_HIDE"] = {
    text = L.DESK_HIDE_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, name)
        ns.Watch:Hide(name)
        if selected == name then selected = nil end
        DeskWindow:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Scale, kept in settings.deskScale. Pinned at the top left corner so
-- the window grows down and to the right.
-- The biggest scale that still fits the screen: a window taller than the
-- screen gets clamped into a corner.
local function FitScale(scale)
    local fit = math.min(UIParent:GetWidth() * 0.96 / WIDTH, UIParent:GetHeight() * 0.94 / HEIGHT)
    return math.max(math.min(SCALE_MIN, fit), math.min(scale, SCALE_MAX, fit))
end

-- Position, kept in settings.deskWindowPoint as the top left corner in
-- screen (UIParent) units once you move it; centred until then.
local function SavePoint()
    local left, top, scale = frame:GetLeft(), frame:GetTop(), frame:GetScale()
    if left and top then S().deskWindowPoint = { left * scale, top * scale } end
end

local function Place()
    local p = S().deskWindowPoint
    local scale = frame:GetScale()
    frame:ClearAllPoints()
    if type(p) == "table" and p[1] and p[2] then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1] / scale, p[2] / scale)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function ApplyScale(scale)
    scale = FitScale(math.max(SCALE_MIN, scale))
    local old = frame:GetScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    frame:SetScale(scale)
    if left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        SavePoint()
    end
    S().deskScale = scale
end

-- Bottom right grip: drag to make the whole window bigger or smaller.
local function ScaleGrip()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self)
        local x, y = GetCursorPosition()
        self.start = { x = x, y = y, scale = frame:GetScale() }
        self:SetScript("OnUpdate", function()
            local cx, cy = GetCursorPosition()
            local moved = ((cx - self.start.x) + (self.start.y - cy)) / 2
            local size = WIDTH * self.start.scale * UIParent:GetEffectiveScale()
            ApplyScale(self.start.scale * (1 + moved / size))
        end)
    end)
    grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DESK_SCALE_TIP)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function DeskWindow:SetView(newView)
    view = newView
    for name, tab in pairs(tabs) do tab:SetActive(name == view) end
    for name, page in pairs(pages) do page:SetShown(name == view) end
    DeskWindow:Refresh()
end

local function Create()
    frame = Skin.Window("TrustCrafterDeskWindow", WIDTH, HEIGHT)
    frame.title:SetText(L.DESK_TITLE)
    frame:SetScale(FitScale(S().deskScale or SCALE_DEFAULT))
    Place()
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        SavePoint()
    end)
    ScaleGrip()

    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", PAD, -44)
    side:SetPoint("BOTTOMLEFT", PAD, PAD)
    side:SetWidth(SIDEBAR)
    BuildCharacters(side)
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", PAD + SIDEBAR + 5, -44)
    divider:SetPoint("BOTTOMLEFT", PAD + SIDEBAR + 5, PAD)

    local left = PAD + SIDEBAR + 12
    tabs, pages = {}, {}
    for i, name in ipairs(VIEWS) do
        local tab = Skin.Tab(frame, L["DESK_TAB_" .. name:upper()], 130, 24)
        tab:SetPoint("TOPLEFT", left + (i - 1) * 134, -40)
        tab:SetScript("OnClick", function() DeskWindow:SetView(name) end)
        tabs[name] = tab
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", left, -76)
        page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        pages[name] = page
    end
    BuildRequests(pages.requests)
    BuildItems(pages.items)
    BuildMessages(pages.messages)
    BuildSettings(pages.settings)
    frame:HookScript("OnShow", function() DeskWindow:Refresh() end)
    DeskWindow:SetView(ns.Watch:Enabled() and "requests" or "settings")
end

function DeskWindow:Refresh()
    if not frame or not frame:IsShown() then return end
    RefreshCharacters()
    if view == "requests" then
        RefreshRequests(pages.requests)
    elseif view == "items" then
        RefreshItems(pages.items)
    elseif view == "messages" then
        RefreshMessages(pages.messages)
    else
        RefreshSettings(pages.settings)
    end
end

function DeskWindow:Show(newView)
    if not ns.db then return end
    if not frame then Create() end
    frame:Show()
    if newView then DeskWindow:SetView(newView) end
end

function DeskWindow:Toggle()
    if not ns.db then return end
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

ns.Events:On("TC_DESK_CHANGED", function() DeskWindow:Refresh() end)
ns.Events:On("TC_RECIPES_SCANNED", function() DeskWindow:Refresh() end)
ns.Events:On("TC_SETTINGS_CHANGED", function() DeskWindow:Refresh() end)

-- Item names arrive after the list first draws.
local namesPending
ns.Events:On("GET_ITEM_INFO_RECEIVED", function()
    if namesPending or not frame or not frame:IsShown() or view ~= "items" then return end
    namesPending = true
    C_Timer.After(0.5, function()
        namesPending = false
        DeskWindow:Refresh()
    end)
end)
