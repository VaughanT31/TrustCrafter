-- TrustCrafter - shared look, matching the other CtrlShift_Zed addons
-- (RecommendedStats' default skin): near-black flat panels with a 1px grey
-- border, flat toggle-style tabs with a gold active label, flat buttons and
-- faint row bands. Every window and button is built through here so the
-- look stays in one place.

local _, ns = ...

local Skin = {}
ns.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Every window, the alert cards and the desk button sit in one holder, so
-- hiding it in combat or an instance puts them all away, and showing it
-- again brings back exactly the ones that were open.
local holder = CreateFrame("Frame", "TrustCrafterHolder", UIParent)
holder:SetAllPoints(UIParent)
Skin.Holder = holder

-- Instance types the windows hide in. Housing (neighborhood, interior) and
-- the open world aren't.
local HIDE_IN = { party = true, raid = true, pvp = true, arena = true, scenario = true }
local special = {}        -- names Skin.Window put on UISpecialFrames
local inCombat = InCombatLockdown()

-- True while the windows are put away.
function Skin.Hidden()
    return not holder:IsShown()
end

-- Escape only closes windows you can see: put away, they come off the list,
-- so Escape in combat still reaches the game and doesn't close them.
local function SetSpecial(on)
    for _, name in ipairs(special) do
        tDeleteItem(UISpecialFrames, name)
        if on then table.insert(UISpecialFrames, name) end
    end
end

function Skin.UpdateHidden()
    local s = ns.db and ns.db.settings or {}
    local _, kind = IsInInstance()
    local hide = (inCombat and s.hideInCombat ~= false)
        or (HIDE_IN[kind] and s.hideInInstances ~= false) or false
    if hide == Skin.Hidden() then return end
    holder:SetShown(not hide)
    SetSpecial(not hide)
end

ns.Events:On("PLAYER_REGEN_DISABLED", function() inCombat = true; Skin.UpdateHidden() end)
ns.Events:On("PLAYER_REGEN_ENABLED", function() inCombat = false; Skin.UpdateHidden() end)
ns.Events:On("PLAYER_ENTERING_WORLD", Skin.UpdateHidden)
ns.Events:On("ZONE_CHANGED_NEW_AREA", Skin.UpdateHidden)
ns.Events:On("TC_DB_READY", Skin.UpdateHidden)
ns.Events:On("TC_SETTINGS_CHANGED", Skin.UpdateHidden)

Skin.BG = { 0.043, 0.047, 0.063, 0.97 }
Skin.BORDER = { 0.25, 0.27, 0.33, 0.7 }
Skin.GOLD = { 1, 0.82, 0.15 }
Skin.DIM = { 0.62, 0.62, 0.66 }
local TAB_ACTIVE_BG = { 0.16, 0.17, 0.22, 1 }
local TAB_IDLE_BG = { 0.043, 0.047, 0.063, 1 }
local BUTTON_BG = { 0.10, 0.11, 0.14, 1 }
local BUTTON_BG_DISABLED = { 0.07, 0.075, 0.09, 1 }

-- A flat edgeSize = 1 is one UI unit, not one screen pixel: below 1.0 UI
-- scale an edge can round away to nothing. Snapping to the nearest real
-- pixel (at least one) keeps all four edges. A fresh table every call:
-- SetBackdrop skips recomputing the border when handed the same table.
function Skin.Backdrop(frame, bg, border)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    local edge = PixelUtil and PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1) or 1
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge })
    bg, border = bg or Skin.BG, border or Skin.BORDER
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- A movable window with a title and a close button, closed by Escape.
-- name must be a unique global frame name.
function Skin.Window(name, width, height, strata)
    local frame = CreateFrame("Frame", name, holder, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetFrameStrata(strata or "HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Skin.Backdrop(frame)
    -- Re-snapped on every open, so a UI scale change can't drop an edge.
    frame:HookScript("OnShow", function(self)
        self:Raise()
        Skin.Backdrop(self)
    end)
    special[#special + 1] = name
    if not Skin.Hidden() then table.insert(UISpecialFrames, name) end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 16, -14)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -2, -2)

    frame:Hide()
    return frame
end

local function PaintButton(button)
    local bg = button:IsEnabled() and BUTTON_BG or BUTTON_BG_DISABLED
    button.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
end

-- A flat button. SetText, SetEnabled and the OnClick script work as on
-- Blizzard's UIPanelButtonTemplate.
function Skin.Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 90, height or 22)
    Skin.Backdrop(button, BUTTON_BG, Skin.BORDER)

    button.bg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.bg:SetPoint("TOPLEFT", 1, -1)
    button.bg:SetPoint("BOTTOMRIGHT", -1, 1)

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
    if text then button:SetText(text) end

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(1, 1, 1, 0.06)

    button:HookScript("OnEnable", PaintButton)
    button:HookScript("OnDisable", PaintButton)
    PaintButton(button)
    return button
end

-- A flat toggle-style tab. tab:SetActive(true) shows it as selected: a
-- lighter fill, a gold label and a gold line along its bottom.
function Skin.Tab(parent, text, width, height)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(width, height)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()

    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.label:SetPoint("CENTER")
    tab.label:SetText(text)

    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetPoint("BOTTOMLEFT")
    tab.line:SetPoint("BOTTOMRIGHT")
    tab.line:SetHeight(2)
    tab.line:SetColorTexture(Skin.GOLD[1], Skin.GOLD[2], Skin.GOLD[3], 1)

    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    function tab:SetActive(active)
        local bg = active and TAB_ACTIVE_BG or TAB_IDLE_BG
        self.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        local c = active and Skin.GOLD or Skin.DIM
        self.label:SetTextColor(c[1], c[2], c[3])
        self.line:SetShown(active)
    end
    tab:SetActive(false)
    return tab
end

-- Faint band behind a list row, so a row's columns read as one line.
function Skin.RowBand(row)
    local band = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    band:SetAllPoints()
    band:SetColorTexture(1, 1, 1, 0.025)
    return band
end

-- Thin horizontal divider under anchor, spanning its parent.
function Skin.Divider(parent, anchor, offsetY)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -6)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return line
end
