-- TrustCrafter - Crafter Desk button (4.0): a small icon that opens the
-- desk, placed where you pick in the options (settings.deskButton):
--
--   off       not shown
--   minimap   just below the minimap, on its left (default)
--   top       top of the screen, in the middle
--   right     right edge, halfway down
--   bottom    above the middle of the action bars
--   free      wherever you Shift-drag it (saved in deskButtonPoint)
--
-- It sits faded until a request comes in, then lights up with a count.
-- With a request waiting: left-click greets the newest, middle-click
-- opens a whisper, right-click dismisses it, Shift-click opens the desk.
-- The same three actions can be bound to keys (Bindings.xml).

local _, ns = ...
local L = ns.L

local DeskButton = {}
ns.DeskButton = DeskButton

local ICON = "Interface\\AddOns\\TrustCrafter\\icon"
local SIZE = 32
local IDLE_ALPHA = 0.45

local PLACES = {
    minimap = function(b) b:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -6, -4) end,
    top = function(b) b:SetPoint("TOP", UIParent, "TOP", 0, -6) end,
    right = function(b) b:SetPoint("RIGHT", UIParent, "RIGHT", -70, 0) end,
    bottom = function(b) b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150) end,
}
DeskButton.PLACES = { "off", "minimap", "top", "right", "bottom", "free" }

BINDING_HEADER_TRUSTCRAFTER = "TrustCrafter"
BINDING_NAME_TRUSTCRAFTER_GREET = L.BIND_GREET
BINDING_NAME_TRUSTCRAFTER_WHISPER = L.BIND_WHISPER
BINDING_NAME_TRUSTCRAFTER_DISMISS = L.BIND_DISMISS
BINDING_NAME_TRUSTCRAFTER_DESK = L.BIND_DESK

local button

local function Place()
    local s = ns.db.settings
    local where = s.deskButton or "minimap"
    button:ClearAllPoints()
    local p = s.deskButtonPoint
    if where == "free" and type(p) == "table" and p[1] then
        button:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    elseif PLACES[where] and (where ~= "minimap" or Minimap) then
        PLACES[where](button)
    else
        PLACES.top(button)
    end
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    local request = ns.DeskAlert:Newest()
    if not request then
        GameTooltip:SetText(L.DESK_TITLE)
        GameTooltip:AddLine(L.DESK_BUTTON_IDLE, 1, 1, 1, true)
        GameTooltip:AddLine(L.DESK_BUTTON_MOVE, 0.6, 0.8, 1, true)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText(L.DESK_BUTTON_FROM:format(ns.Util.ShortName(request.customer)))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.DESK_BUTTON_GREETING)
    GameTooltip:AddLine(ns.Replies:Preview(request), 1, 0.5, 1, true)
    local ok, why = ns.Replies:CanGreet(request)
    if not ok then GameTooltip:AddLine(L["DESK_CANT_" .. why:upper()], 1, 0.5, 0.4, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(request.text, 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.DESK_BUTTON_LEFT, 1, 0.82, 0)
    GameTooltip:AddLine(L.DESK_BUTTON_MIDDLE, 1, 0.82, 0)
    GameTooltip:AddLine(L.DESK_BUTTON_RIGHT, 1, 0.82, 0)
    GameTooltip:AddLine(L.DESK_BUTTON_SHIFT, 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function Create()
    button = CreateFrame("Button", "TrustCrafterDeskButton", UIParent, "BackdropTemplate")
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    ns.Skin.Backdrop(button, { 0, 0, 0, 0.6 }, { 0.4, 0.8, 1, 0.6 })

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    button.glow:SetBlendMode("ADD")
    button.glow:SetAllPoints()
    button.glow:Hide()
    local pulse = button.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.8)
    button.pulse = pulse

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -1, 2)

    button:SetScript("OnClick", function(_, mouse)
        local request = ns.DeskAlert:Newest()
        if IsShiftKeyDown() or not request then
            ns.DeskWindow:Toggle()
        elseif mouse == "LeftButton" then
            ns.DeskAlert:Greet(request)
        elseif mouse == "MiddleButton" then
            ns.DeskAlert:Whisper(request)
        else
            ns.DeskAlert:Dismiss(request)
        end
        if GameTooltip:IsOwned(button) then Tooltip(button) end
    end)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        ns.db.settings.deskButtonPoint = { point, relative, x, y }
        ns.db.settings.deskButton = "free"
    end)
    button:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        Tooltip(self)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        DeskButton:Update()
    end)
end

function DeskButton:Update()
    if not ns.db then return end
    local s = ns.db.settings
    local where = s.deskButton or "minimap"
    if not s.desk or where == "off" then
        if button then button:Hide() end
        return
    end
    if not button then Create() end
    Place()
    local waiting = ns.DeskAlert:Count()
    button.count:SetText(waiting > 0 and waiting or "")
    button.glow:SetShown(waiting > 0)
    if waiting > 0 then button.pulse:Play() else button.pulse:Stop() end
    if not button:IsMouseOver() then button:SetAlpha(waiting > 0 and 1 or IDLE_ALPHA) end
    button:Show()
end

-- Key bindings (Bindings.xml) act on the newest waiting request.
function TrustCrafter_Bind(action)
    if action == "desk" then
        ns.DeskWindow:Toggle()
        return
    end
    local request = ns.DeskAlert:Newest()
    if not request then return end
    if action == "greet" then
        ns.DeskAlert:Greet(request)
    elseif action == "whisper" then
        ns.DeskAlert:Whisper(request)
    elseif action == "dismiss" then
        ns.DeskAlert:Dismiss(request)
    end
end

ns.Events:On("TC_DB_READY", function() DeskButton:Update() end)
ns.Events:On("TC_SETTINGS_CHANGED", function() DeskButton:Update() end)
ns.Events:On("TC_DESK_ALERTS", function() DeskButton:Update() end)
