-- TrustCrafter - history window (/tc): every crafting order you placed on
-- this realm, newest first. Sort by clicking a column, filter by text,
-- outcome and profession. Click an order to see its facts and add a note
-- or tags. The facts themselves can't be edited.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow

local WIDTH, HEIGHT = 780, 560
local PAD = 16
local ROW_HEIGHT = 22
local DETAIL_HEIGHT = 160
local CONTROLS_Y = -44
local HEADER_Y = -78

-- Column layout: key, x offset, width, justify. Shared by header and rows.
local COLUMNS = {
    { key = "date", x = 4, w = 52 },
    { key = "crafter", x = 60, w = 118 },
    { key = "item", x = 182, w = 196 },
    { key = "asked", x = 384, w = 40, justify = "CENTER" },
    { key = "got", x = 428, w = 40, justify = "CENTER" },
    { key = "outcome", x = 474, w = 92 },
    { key = "time", x = 570, w = 74 },
    { key = "tip", x = 648, w = 66, justify = "RIGHT" },
}
local SORTABLE = { date = true, crafter = true, item = true, outcome = true, time = true, tip = true }

local OUTCOME_COLORS = {
    EXCEEDED = { 0.4, 1, 0.5 },
    MET = { 0.4, 0.85, 0.5 },
    BELOW = { 1, 0.67, 0.27 },
    NOT_FILLED = { 0.6, 0.6, 0.6 },
    OPEN = { 0.4, 0.8, 1 },
}
local OUTCOME_ORDER = { EXCEEDED = 1, MET = 2, BELOW = 3, OPEN = 4, NOT_FILLED = 5 }

local OUTCOME_FILTERS = { "ALL", "MET_OR_BETTER", "BELOW", "NOT_FILLED", "OPEN" }

local frame
local rows = {}
local state = { sort = "date", desc = true, search = "", outcome = 1, profession = nil, selected = nil }

-- ---------------------------------------------------------------------
-- Record helpers
-- ---------------------------------------------------------------------

local function OutcomeKey(record)
    return record.outcome or "OPEN"
end

local function ItemName(record)
    local item = record.link or record.itemID
    if not item then return nil end
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item)
    if not name and record.itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(record.itemID)
    end
    return name
end

local function TimeText(record)
    local seconds = ns.Ledger.Turnaround(record)
    if not seconds then return "-" end
    local text = Util.FormatDuration(seconds)
    if record.placedApprox or record.completedApprox then text = "~" .. text end
    return text
end

local SORT_VALUE = {
    date = function(r) return r.completedAt or r.placedAt or 0 end,
    crafter = function(r) return (r.crafter or "~"):lower() end,
    item = function(r) return (ItemName(r) or "~"):lower() end,
    outcome = function(r) return OUTCOME_ORDER[OutcomeKey(r)] end,
    time = function(r) return ns.Ledger.Turnaround(r) or math.huge end,
    tip = function(r) return r.tip or 0 end,
}

local function MatchesFilters(record)
    local filter = OUTCOME_FILTERS[state.outcome]
    local outcome = OutcomeKey(record)
    if filter == "MET_OR_BETTER" and outcome ~= "MET" and outcome ~= "EXCEEDED" then return false end
    if filter ~= "ALL" and filter ~= "MET_OR_BETTER" and outcome ~= filter then return false end
    if state.profession and record.profession ~= state.profession then return false end
    if state.search ~= "" then
        local hay = ((record.crafter or "") .. " " .. (ItemName(record) or "")):lower()
        if not hay:find(state.search, 1, true) then return false end
    end
    return true
end

local function VisibleRecords()
    local list = {}
    for _, record in ipairs(ns.Ledger:All()) do
        if MatchesFilters(record) then list[#list + 1] = record end
    end
    local value = SORT_VALUE[state.sort]
    table.sort(list, function(a, b)
        local va, vb = value(a), value(b)
        if va == vb then return a.id > b.id end
        if state.desc then return va > vb end
        return va < vb
    end)
    return list
end

local function Professions()
    local seen, list = {}, {}
    for _, record in ipairs(ns.Ledger:All()) do
        if record.profession and not seen[record.profession] then
            seen[record.profession] = true
            list[#list + 1] = record.profession
        end
    end
    table.sort(list)
    return list
end

-- ---------------------------------------------------------------------
-- List rows
-- ---------------------------------------------------------------------

local function Cell(parent, column, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetPoint("LEFT", column.x, 0)
    fs:SetWidth(column.w)
    fs:SetJustifyH(column.justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")
    Skin.RowBand(row)

    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(Skin.GOLD[1], Skin.GOLD[2], Skin.GOLD[3], 0.12)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        row.cells[column.key] = Cell(row, column)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", COLUMNS[3].x, 0)
    row.cells.item:SetPoint("LEFT", COLUMNS[3].x + 20, 0)
    row.cells.item:SetWidth(COLUMNS[3].w - 20)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    row:SetScript("OnClick", function(self)
        state.selected = self.record and self.record.id
        HistoryWindow:Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        local link = self.record and self.record.link
        if not link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function SetRow(row, record)
    row.record = record
    local c = row.cells
    c.date:SetText(Util.FormatDate(record.completedAt or record.placedAt))
    c.crafter:SetText(record.crafter
        and (ns.Presence:Dot(record.crafterGuid, record.crafter) .. " " .. Util.ShortName(record.crafter))
        or ("|cff999999" .. L.NO_CRAFTER .. "|r"))
    c.item:SetText(ItemName(record) or ("|cff999999" .. L.ITEM_LOADING .. "|r"))
    row.icon:SetTexture(record.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(record.itemID) or 134400)
    c.asked:SetText((record.minQuality or 0) > 0 and Util.QualityText(record.minQuality) or "|cff999999-|r")
    c.got:SetText(record.delivered and Util.QualityText(record.delivered) or "|cff999999-|r")

    local outcome = OutcomeKey(record)
    local color = OUTCOME_COLORS[outcome]
    c.outcome:SetText(L["OUTCOME_" .. outcome])
    c.outcome:SetTextColor(color[1], color[2], color[3])
    c.time:SetText(TimeText(record))
    c.tip:SetText((record.tip or 0) > 0 and Util.FormatMoney(record.tip) or "|cff999999-|r")
    row.selected:SetShown(state.selected == record.id)
    row:Show()
end

-- ---------------------------------------------------------------------
-- Detail panel: facts, note, tags
-- ---------------------------------------------------------------------

local function BuildDetail(parent)
    local detail = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    detail:SetPoint("BOTTOMLEFT", PAD, PAD)
    detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    detail:SetHeight(DETAIL_HEIGHT)
    Skin.Backdrop(detail, { 1, 1, 1, 0.025 }, Skin.BORDER)

    detail.empty = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    detail.empty:SetPoint("CENTER")
    detail.empty:SetText(L.DETAIL_PICK)

    -- Facts: left half, read-only.
    detail.title = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail.title:SetPoint("TOPLEFT", 12, -10)
    detail.title:SetWidth(330)
    detail.title:SetJustifyH("LEFT")
    detail.title:SetWordWrap(false)

    detail.facts = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.facts:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -8)
    detail.facts:SetWidth(330)
    detail.facts:SetJustifyH("LEFT")
    detail.facts:SetSpacing(4)

    -- Note and tags: right half, the player's own words.
    local right = 370
    detail.noteLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail.noteLabel:SetPoint("TOPLEFT", right, -10)
    detail.noteLabel:SetText(L.NOTE_LABEL)

    detail.counter = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail.counter:SetPoint("TOPRIGHT", -12, -10)

    local box = CreateFrame("EditBox", nil, detail, "BackdropTemplate")
    box:SetPoint("TOPLEFT", right, -28)
    box:SetPoint("RIGHT", -12, 0)
    box:SetHeight(24)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetMaxLetters(ns.Ledger.NOTE_MAX)
    Skin.Backdrop(box, { 0, 0, 0, 0.5 }, Skin.BORDER)
    detail.note = box

    box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.placeholder:SetPoint("LEFT", 6, 0)
    box.placeholder:SetText(L.NOTE_PLACEHOLDER)

    local function UpdatePlaceholder()
        box.placeholder:SetShown(box:GetText() == "" and not box:HasFocus())
        detail.counter:SetText(L.NOTE_COUNTER:format(#box:GetText(), ns.Ledger.NOTE_MAX))
    end
    local function Save()
        if detail.recordID then ns.Ledger:SetNote(detail.recordID, box:GetText()) end
    end
    box:SetScript("OnTextChanged", UpdatePlaceholder)
    box:SetScript("OnEditFocusGained", UpdatePlaceholder)
    box:SetScript("OnEditFocusLost", function()
        Save()
        UpdatePlaceholder()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        local record = detail.recordID and ns.Ledger:Get(detail.recordID)
        self:SetText(record and record.note or "")
        self:ClearFocus()
    end)
    detail.UpdatePlaceholder = UpdatePlaceholder

    detail.hint = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail.hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
    detail.hint:SetPoint("RIGHT", -12, 0)
    detail.hint:SetJustifyH("LEFT")
    detail.hint:SetText(L.NOTE_HINT)

    detail.tagLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail.tagLabel:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -24)
    detail.tagLabel:SetText(L.TAGS_LABEL)

    detail.tags = {}
    local previous
    for _, tag in ipairs(ns.Ledger.TAGS) do
        local button = Skin.Tab(detail, L["TAG_" .. tag], 70, 20)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("TOPLEFT", detail.tagLabel, "BOTTOMLEFT", 0, -4)
        end
        button.tag = tag
        button:SetScript("OnClick", function(self)
            local record = detail.recordID and ns.Ledger:Get(detail.recordID)
            if record then ns.Ledger:SetTag(record.id, self.tag, not (record.tags and record.tags[self.tag])) end
        end)
        detail.tags[tag] = button
        previous = button
    end

    detail.private = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
    detail.private:SetSize(22, 22)
    detail.private:SetPoint("BOTTOMLEFT", right - 4, 8)
    detail.private.Text:SetText(L.PRIVATE_LABEL)
    detail.private.Text:SetFontObject(GameFontHighlightSmall)
    detail.private:SetScript("OnClick", function(self)
        if detail.recordID then ns.Ledger:SetPrivate(detail.recordID, self:GetChecked()) end
    end)
    detail.private:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.PRIVATE_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    detail.private:SetScript("OnLeave", function() GameTooltip:Hide() end)

    detail.parts = { detail.title, detail.facts, detail.noteLabel, detail.counter, box, detail.hint,
        detail.tagLabel, detail.private }
    return detail
end

local function FactLines(record)
    local lines = {}
    local function Add(label, value) lines[#lines + 1] = "|cff999999" .. label .. "|r  " .. value end

    Add(L.FACT_CRAFTER, record.crafter
        and (record.crafter .. "   " .. ns.Presence:Label(record.crafterGuid, record.crafter))
        or L.NO_CRAFTER)
    if record.customer then Add(L.FACT_CUSTOMER, Util.ShortName(record.customer)) end
    Add(L.FACT_TYPE, L["TYPE_" .. (record.orderType or "PUBLIC")] or record.orderType or "-")
    local asked = (record.minQuality or 0) > 0 and Util.QualityText(record.minQuality) or L.FACT_NO_MINIMUM
    local got = record.delivered and Util.QualityText(record.delivered) or "-"
    local color = OUTCOME_COLORS[OutcomeKey(record)]
    local outcome = ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255,
        L["OUTCOME_" .. OutcomeKey(record)])
    Add(L.FACT_QUALITY, L.FACT_QUALITY_VALUE:format(asked, got, outcome))
    if record.placedAt then
        Add(L.FACT_PLACED, date("%d %b %H:%M", record.placedAt) .. (record.placedApprox and (" " .. L.FACT_APPROX) or ""))
    end
    if record.completedAt then
        local label = record.state == "FILLED" and L.FACT_FILLED or L.FACT_CLOSED
        Add(label, date("%d %b %H:%M", record.completedAt) .. (record.completedApprox and (" " .. L.FACT_APPROX) or ""))
    end
    Add(L.FACT_TURNAROUND, TimeText(record))
    Add(L.FACT_TIP, (record.tip or 0) > 0 and Util.FormatMoney(record.tip) or "-")
    return table.concat(lines, "\n")
end

local function RefreshDetail(detail)
    local record = state.selected and ns.Ledger:Get(state.selected)
    detail.empty:SetShown(record == nil)
    for _, part in ipairs(detail.parts) do part:SetShown(record ~= nil) end
    for _, button in pairs(detail.tags) do button:SetShown(record ~= nil) end
    if not record then
        detail.recordID = nil
        return
    end

    -- Switching orders while typing saves what was typed first.
    if detail.recordID ~= record.id and detail.note:HasFocus() then detail.note:ClearFocus() end
    detail.recordID = record.id

    local name = ItemName(record)
    detail.title:SetText(record.link or name or L.ITEM_LOADING)
    detail.facts:SetText(FactLines(record))
    if not detail.note:HasFocus() then detail.note:SetText(record.note or "") end
    detail.UpdatePlaceholder()
    for tag, button in pairs(detail.tags) do
        button:SetActive(record.tags and record.tags[tag] or false)
    end
    detail.private:SetChecked(record.private == true)

    -- Locked when you can't rate this order, with the reason in place of
    -- the usual hint.
    local canReview, why = ns.Ledger:CanReview(record)
    if not canReview and detail.note:HasFocus() then detail.note:ClearFocus() end
    detail.note:SetEnabled(canReview)
    detail.note:SetAlpha(canReview and 1 or 0.5)
    for _, button in pairs(detail.tags) do
        button:SetEnabled(canReview)
        button:SetAlpha(canReview and 1 or 0.5)
    end
    detail.private:SetEnabled(canReview)
    if canReview then
        detail.hint:SetText(L.NOTE_HINT)
        detail.hint:SetTextColor(0.5, 0.5, 0.5)
    else
        detail.hint:SetText(L["REVIEW_" .. why]:format(Util.ShortName(record.customer)))
        detail.hint:SetTextColor(1, 0.67, 0.27)
    end
end

-- ---------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------

local function UpdateFilterButtons()
    frame.outcomeButton:SetText(L.FILTER_OUTCOME:format(L["FILTER_" .. OUTCOME_FILTERS[state.outcome]]))
    frame.professionButton:SetText(L.FILTER_PROFESSION:format(state.profession or L.FILTER_ALL))
    for key, header in pairs(frame.headers) do
        local arrow = ""
        if state.sort == key then arrow = state.desc and " v" or " ^" end
        header.label:SetText(L["COL_" .. key:upper()] .. arrow)
    end
end

local function Create()
    frame = Skin.Window("TrustCrafterHistory", WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame.title:SetText(L.WINDOW_TITLE)

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.count:SetPoint("RIGHT", frame.closeButton, "LEFT", -6, 0)

    -- Search box: crafter or item name.
    local search = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    search:SetSize(200, 24)
    search:SetPoint("TOPLEFT", PAD, CONTROLS_Y)
    search:SetAutoFocus(false)
    search:SetFontObject(ChatFontNormal)
    search:SetTextInsets(6, 6, 0, 0)
    Skin.Backdrop(search, { 0, 0, 0, 0.5 }, Skin.BORDER)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search.placeholder:SetText(L.SEARCH_PLACEHOLDER)
    search:SetScript("OnTextChanged", function(self)
        state.search = self:GetText():lower()
        self.placeholder:SetShown(self:GetText() == "")
        HistoryWindow:Refresh()
    end)
    frame.search = search
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    frame.outcomeButton = Skin.Button(frame, nil, 170, 24)
    frame.outcomeButton:SetPoint("LEFT", search, "RIGHT", 8, 0)
    frame.outcomeButton:SetScript("OnClick", function()
        state.outcome = state.outcome % #OUTCOME_FILTERS + 1
        HistoryWindow:Refresh()
    end)

    frame.professionButton = Skin.Button(frame, nil, 200, 24)
    frame.professionButton:SetPoint("LEFT", frame.outcomeButton, "RIGHT", 8, 0)
    frame.professionButton:SetScript("OnClick", function()
        local list = Professions()
        local nextIndex = 1
        for i, name in ipairs(list) do
            if name == state.profession then nextIndex = i + 1 end
        end
        state.profession = list[nextIndex] -- past the end: back to all
        HistoryWindow:Refresh()
    end)

    local export = Skin.Button(frame, L.EXPORT_BUTTON, 90, 24)
    export:SetPoint("TOPRIGHT", -PAD, CONTROLS_Y)
    export:SetScript("OnClick", function() ns.ExportWindow:Show() end)

    -- Column headers; sortable ones toggle direction on a second click.
    local headerRow = CreateFrame("Frame", nil, frame)
    headerRow:SetPoint("TOPLEFT", PAD, HEADER_Y)
    headerRow:SetPoint("RIGHT", -PAD - 26, 0)
    headerRow:SetHeight(18)
    frame.headers = {}
    for _, column in ipairs(COLUMNS) do
        local header = CreateFrame("Button", nil, headerRow)
        header:SetPoint("LEFT", column.x, 0)
        header:SetSize(column.w, 18)
        header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.label:SetAllPoints()
        header.label:SetJustifyH(column.justify or "LEFT")
        if SORTABLE[column.key] then
            header:SetScript("OnClick", function()
                if state.sort == column.key then
                    state.desc = not state.desc
                else
                    state.sort = column.key
                    state.desc = column.key == "date" or column.key == "tip"
                end
                HistoryWindow:Refresh()
            end)
        end
        frame.headers[column.key] = header
    end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 26, PAD + DETAIL_HEIGHT + 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    frame.content = content

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    frame.empty:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetSpacing(4)

    frame.detail = BuildDetail(frame)
    frame:HookScript("OnShow", function()
        HistoryWindow:Refresh()
        -- Keeps the online dots current while the window is open.
        if not frame.presenceTicker then
            frame.presenceTicker = C_Timer.NewTicker(30, function() HistoryWindow:Refresh() end)
        end
    end)
    frame:HookScript("OnHide", function()
        if frame.presenceTicker then
            frame.presenceTicker:Cancel()
            frame.presenceTicker = nil
        end
    end)
end

function HistoryWindow:Refresh()
    if not frame or not frame:IsShown() then return end
    UpdateFilterButtons()

    local all = #ns.Ledger:All()
    local list = VisibleRecords()
    frame.count:SetText(L.COUNT:format(#list, all))
    if all == 0 then
        frame.empty:SetText(L.EMPTY_NONE)
    elseif #list == 0 then
        frame.empty:SetText(L.EMPTY_FILTERED)
    else
        frame.empty:SetText("")
    end

    for i, record in ipairs(list) do
        rows[i] = rows[i] or CreateRow(frame.content, i)
        SetRow(rows[i], record)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    frame.content:SetHeight(math.max(1, #list * ROW_HEIGHT))

    RefreshDetail(frame.detail)
end

-- Opens the window searched to one crafter ("Name-Realm"), from the
-- right-click player menu.
function HistoryWindow:ShowCrafter(crafter)
    if not ns.db then return end
    if not frame then Create() end
    state.outcome, state.profession = 1, nil
    frame:Show()
    frame.search:SetText(Util.ShortName(crafter))
    self:Refresh()
end

function HistoryWindow:Toggle()
    if not ns.db then return end
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

ns.Events:On("TC_LEDGER_CHANGED", function() HistoryWindow:Refresh() end)
ns.Events:On("TC_PRESENCE_CHANGED", function() HistoryWindow:Refresh() end)

-- Item names arrive from the server a moment after they're first asked for.
local namesTimer
ns.Events:On("GET_ITEM_INFO_RECEIVED", function()
    if not frame or not frame:IsShown() or namesTimer then return end
    namesTimer = C_Timer.NewTimer(0.5, function()
        namesTimer = nil
        HistoryWindow:Refresh()
    end)
end)
