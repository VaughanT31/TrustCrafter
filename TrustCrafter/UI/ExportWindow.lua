-- TrustCrafter - export window (/tc export, or Export in the history
-- window): your orders on this realm as CSV, selected and ready to copy
-- with Ctrl+C, for pasting into a spreadsheet.

local _, ns = ...
local L, Skin = ns.L, ns.Skin

local ExportWindow = {}
ns.ExportWindow = ExportWindow

local WIDTH, HEIGHT = 640, 420

local frame

local function Create()
    frame = Skin.Window("TrustCrafterExport", WIDTH, HEIGHT, "DIALOG")
    frame:SetPoint("CENTER", 0, 40)
    frame.title:SetText(L.EXPORT_TITLE)

    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.help:SetPoint("TOPLEFT", 16, -42)
    frame.help:SetPoint("RIGHT", -16, 0)
    frame.help:SetJustifyH("LEFT")

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", 0, -10)
    box:SetPoint("BOTTOMRIGHT", -16, 48)
    Skin.Backdrop(box, { 0, 0, 0, 0.5 }, Skin.BORDER)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
    edit:SetWidth(WIDTH - 80)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only: any typing puts the export back.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and frame.text then
            self:SetText(frame.text)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(_, width) edit:SetWidth(width) end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    frame.edit = edit

    local close = Skin.Button(frame, CLOSE or "Close", 100, 22)
    close:SetPoint("BOTTOMRIGHT", -16, 16)
    close:SetScript("OnClick", function() frame:Hide() end)
end

function ExportWindow:Show()
    if not ns.db then return end
    if not frame then Create() end
    local text, count = ns.Ledger:ExportCSV()
    frame.text = text
    frame.help:SetText(L.EXPORT_HELP:format(count))
    frame.edit:SetText(text)
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
end

ns:RegisterCommand("export", function() ExportWindow:Show() end, L.HELP_EXPORT)
