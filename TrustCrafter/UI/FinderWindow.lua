-- TrustCrafter - Find a Crafter results (3.1), opened from the personal
-- order form's "Find a Crafter" button (UI/OrderScreen.lua).
--
-- One row per character that knows the recipe, best first: crafters you've
-- had good orders from, then good guild and realm reviews, then crafters
-- who are online and not busy. Your own characters come last.
--   Use       puts the name in the order's recipient box
--   Whisper   opens a whisper
--   Hover     your history with them, and asks your guild and realm too
-- Answers keep arriving for a few seconds after the search.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local FinderWindow = {}
ns.FinderWindow = FinderWindow

local WIDTH, HEIGHT = 660, 380
local PAD = 16
local ROW_HEIGHT = 24
local ROWS = 11
local HEADER_Y = -62
local AUTO_ASK = 3                  -- crafters whose reviews are asked for at once

local GREEN = "|cff66dd77"
local AMBER = "|cffffaa44"
local GREY = "|cff999999"

local COLUMNS = {
    { key = "name", x = 4, w = 150 },
    { key = "skill", x = 158, w = 56, justify = "CENTER" },
    { key = "history", x = 218, w = 196 },
    { key = "note", x = 418, w = 112 },
}

local frame, rows, statusText, onUse
local offset = 0
local asked = {}

local function RecipeName(recipeID)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID)
    return name or ("#" .. tostring(recipeID))
end

-- "You 3/3", "Guild 6/7", "Realm 4/4" or "No history", coloured.
local function HistoryText(name)
    local rank, tier, s = ns.Finder.Trust(name)
    if not tier then return GREY .. L.FINDER_NO_HISTORY .. "|r" end
    local color = rank > 0 and GREEN or AMBER
    if tier == "mine" then
        return color .. L.FINDER_HIST_MINE:format(s.metOrBetter, s.filled) .. "|r"
    end
    local label = tier == "guild" and L.FINDER_HIST_GUILD or L.FINDER_HIST_REALM
    return color .. label:format(s.metOrBetter, s.orders, s.people) .. "|r"
end

local function NameText(row)
    local text = Util.ShortName(row.name)
    if row.mine then return text .. GREY .. " " .. L.FINDER_YOURS .. "|r" end
    if row.online then
        text = GREEN .. "\226\128\162|r " .. text
    elseif row.via then
        text = GREY .. "\226\128\162|r " .. text .. GREY .. " " .. L.FINDER_ALT_OF:format(Util.ShortName(row.via)) .. "|r"
    end
    return text
end

local function NoteText(row)
    local parts = {}
    if row.busy then parts[#parts + 1] = AMBER .. L.FINDER_BUSY .. "|r" end
    if row.note then parts[#parts + 1] = row.note end
    return table.concat(parts, " ")
end

-- The recipient box takes a short name for your own realm.
local function TargetName(name)
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    if short and realm == Util.Realm() then return short end
    return name
end

local function ShowRowTooltip(self)
    local data = self.data
    if not data then return end
    if not data.mine then ns.Sharing:Ask(data.name) end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(data.name, 1, 1, 1)
    if data.via then GameTooltip:AddLine(L.FINDER_ALT_TIP:format(Util.ShortName(data.via)), 0.8, 0.8, 0.8, true) end
    if data.skill then
        GameTooltip:AddLine(L.FINDER_SKILL_TIP:format(data.skill, data.max or data.skill), 0.8, 0.8, 0.8)
    end
    if data.note then GameTooltip:AddLine(data.note, 1, 0.82, 0.15, true) end
    if not ns.Tooltip.AddHistory(GameTooltip, data.name) then
        GameTooltip:AddLine(L.FINDER_NO_HISTORY_TIP, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, HEADER_Y - 18 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", -PAD, 0)
    row:EnableMouse(true)
    Skin.RowBand(row)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", column.x, 0)
        fs:SetWidth(column.w)
        fs:SetJustifyH(column.justify or "LEFT")
        fs:SetWordWrap(false)
        row.cells[column.key] = fs
    end
    row.use = Skin.Button(row, L.FINDER_USE, 48, 20)
    row.use:SetPoint("RIGHT", -60, 0)
    row.use:SetScript("OnClick", function()
        if row.data and onUse then onUse(TargetName(row.data.name)) end
    end)
    row.whisper = Skin.Button(row, L.FINDER_WHISPER, 56, 20)
    row.whisper:SetPoint("RIGHT", 0, 0)
    row.whisper:SetScript("OnClick", function()
        if row.data then ChatFrame_SendTell(row.data.name) end
    end)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Create()
    frame = Skin.Window("TrustCrafterFinderWindow", WIDTH, HEIGHT)
    frame:SetPoint("CENTER")

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", PAD, -40)
    statusText:SetPoint("RIGHT", -PAD, 0)
    statusText:SetJustifyH("LEFT")

    local headers = { name = L.FINDER_COL_CRAFTER, skill = L.FINDER_COL_SKILL, history = L.FINDER_COL_HISTORY, note = L.FINDER_COL_NOTE }
    for _, column in ipairs(COLUMNS) do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", PAD + column.x, HEADER_Y)
        fs:SetWidth(column.w)
        fs:SetJustifyH(column.justify or "LEFT")
        fs:SetText(headers[column.key])
    end

    rows = {}
    for i = 1, ROWS do rows[i] = CreateRow(frame, i) end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        FinderWindow:Refresh()
    end)

    local again = Skin.Button(frame, L.FINDER_AGAIN, 110, 22)
    again:SetPoint("BOTTOMRIGHT", -PAD, 12)
    again:SetScript("OnClick", function()
        local search = ns.Finder:Current()
        if search then FinderWindow:Search(search.recipeID) end
    end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", PAD, 18)
    hint:SetPoint("RIGHT", again, "LEFT", -10, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.FINDER_HINT)
end

function FinderWindow:Refresh()
    if not frame or not frame:IsShown() then return end
    local search = ns.Finder:Current()
    local list = ns.Finder:Rows()
    offset = math.min(offset, math.max(0, #list - ROWS))
    if search then
        frame.title:SetText(L.FINDER_TITLE:format(RecipeName(search.recipeID)))
        local others = 0
        for _, row in ipairs(list) do if not row.mine then others = others + 1 end end
        local waiting = Util.Now() - search.at < 10
        if others == 0 then
            statusText:SetText(waiting and L.FINDER_SEARCHING or L.FINDER_NONE)
        else
            statusText:SetText(L.FINDER_FOUND:format(others) .. (waiting and ("  " .. GREY .. L.FINDER_STILL .. "|r") or ""))
        end
    end
    for i, row in ipairs(rows) do
        local data = list[i + offset]
        row.data = data
        row:SetShown(data ~= nil)
        if data then
            row.cells.name:SetText(NameText(data))
            row.cells.skill:SetText(data.skill and ((data.skill) .. "/" .. (data.max or data.skill)) or "-")
            row.cells.history:SetText(data.mine and "" or HistoryText(data.name))
            row.cells.note:SetText(NoteText(data))
            row.use:SetShown(onUse ~= nil)
        end
    end
    -- Ask about the first few answers' reviews straight away.
    local count = 0
    for _, data in ipairs(list) do
        if count >= AUTO_ASK then break end
        if not data.mine and data.online then
            count = count + 1
            if not asked[data.name] then
                asked[data.name] = true
                ns.Sharing:Ask(data.name)
            end
        end
    end
end

-- Searches and shows the window. use(name) fills the order's recipient box.
function FinderWindow:Search(recipeID, use, anchor)
    if not frame then Create() end
    if use then onUse = use end
    local ok, reason = ns.Finder:Search(recipeID)
    if not ok and reason ~= "wait" then
        Util.Print(L["FINDER_ERR_" .. reason] or reason)
        if reason ~= "limit" then return end
    end
    offset = 0
    if anchor then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    end
    frame:Show()
    self:Refresh()
    -- Redraws while answers come in, for the status line.
    for _, wait in ipairs({ 3, 6, 11 }) do C_Timer.After(wait, function() FinderWindow:Refresh() end) end
end

function FinderWindow:Hide()
    if frame then frame:Hide() end
end

ns.Events:On("TC_FINDER_CHANGED", function() FinderWindow:Refresh() end)
ns.Events:On("TC_SHARED_CHANGED", function() FinderWindow:Refresh() end)
ns.Events:On("TC_LEDGER_CHANGED", function() FinderWindow:Refresh() end)
