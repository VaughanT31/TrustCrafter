-- TrustCrafter - options page in Esc > Options > AddOns, built with
-- Blizzard's Settings API. Each option reads and writes ns.db.settings
-- through a proxy. /tc options opens it.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Options = {}
ns.Options = Options

local category

local function Refresh()
    ns.Events:Fire("TC_SETTINGS_CHANGED")
end

-- A checkbox for ns.db.settings[field]. invert shows "on" when the stored
-- value is false (used for "hide" style settings).
local function Checkbox(field, name, tooltip, default, onChange, invert)
    local function Get()
        local value = ns.db.settings[field] and true or false
        if invert then return not value end
        return value
    end
    local function Set(value)
        if invert then value = not value end
        ns.db.settings[field] = value
        if onChange then onChange(value) end
        Refresh()
    end
    local setting = Settings.RegisterProxySetting(category, "TrustCrafter_" .. field,
        Settings.VarType.Boolean, name, default, Get, Set)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- Headings and buttons are niceties: skipped if this client lacks them.
local function Layout()
    return SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)
end

local function Header(text)
    if not CreateSettingsListSectionHeaderInitializer then return end
    pcall(function() Layout():AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end)
end

-- A dropdown for ns.db.settings[field]; choices is a list of
-- { value, label }.
local function Dropdown(field, name, tooltip, default, choices, onChange)
    if not (Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
    local setting = Settings.RegisterProxySetting(category, "TrustCrafter_" .. field,
        Settings.VarType.String, name, default,
        function() return ns.db.settings[field] or default end,
        function(value)
            ns.db.settings[field] = value
            if onChange then onChange(value) end
            Refresh()
        end)
    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
        return container:GetData()
    end, tooltip)
end

local function Button(name, buttonText, onClick, tooltip)
    if not CreateSettingsButtonInitializer then return end
    pcall(function()
        Layout():AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
    end)
end

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        return
    end
    category = Settings.RegisterVerticalLayoutCategory(L.WINDOW_TITLE)

    Header(L.OPT_GENERAL)
    Checkbox("tooltip", L.OPT_TOOLTIP, L.OPT_TOOLTIP_TIP, true)
    Checkbox("presence", L.OPT_PRESENCE, L.OPT_PRESENCE_TIP, true)
    Checkbox("minimapHide", L.OPT_MINIMAP, L.OPT_MINIMAP_TIP, true, function()
        if ns.MinimapButton then ns.MinimapButton:Update() end
    end, true)

    Header(L.OPT_WINDOWS)
    Checkbox("orderScreen", L.OPT_ORDER_SCREEN, L.OPT_ORDER_SCREEN_TIP, true)
    Checkbox("craftScan", L.OPT_CRAFTSCAN, L.OPT_CRAFTSCAN_TIP, true)

    Header(L.OPT_SHARING)
    Checkbox("share", L.OPT_SHARE, L.OPT_SHARE_TIP, false, function(on)
        if on then Util.Print(L.SHARE_ON) else Util.Print(L.SHARE_OFF) end
    end)
    Checkbox("confirm", L.OPT_CONFIRM, L.OPT_CONFIRM_TIP, true)
    Button(L.OPT_FORGET, L.OPT_FORGET_BUTTON, function() ns.Sharing:ForgetShared() end, L.OPT_FORGET_TIP)

    Header(L.OPT_REALM_SHARING)
    Checkbox("realmShare", L.OPT_REALM_SHARE, L.OPT_REALM_SHARE_TIP, false, function(on)
        if on then Util.Print(L.REALM_ON) else Util.Print(L.REALM_OFF) end
        ns.Channel:Update()
    end)
    Button(L.OPT_FORGET_REALM, L.OPT_FORGET_BUTTON, function() ns.Sharing:ForgetRealm() end, L.OPT_FORGET_REALM_TIP)

    Header(L.OPT_FINDER)
    Checkbox("finder", L.OPT_FINDER_ON, L.OPT_FINDER_ON_TIP, false, function(on)
        Util.Print(on and L.FINDER_ON or L.FINDER_OFF)
        ns.Channel:Update()
    end)
    Checkbox("discoverable", L.OPT_DISCOVERABLE, L.OPT_DISCOVERABLE_TIP, true)
    Checkbox("finderAlts", L.OPT_FINDER_ALTS, L.OPT_FINDER_ALTS_TIP, true)
    Checkbox("busy", L.OPT_BUSY, L.OPT_BUSY_TIP, false)

    Header(L.DESK_TITLE)
    Checkbox("desk", L.DESK_OPT_ON, L.DESK_OPT_ON_TIP, false, function(on)
        Util.Print(on and L.DESK_ON or L.DESK_OFF)
    end)
    Button(L.DESK_TITLE, L.DESK_OPEN, function() ns.DeskWindow:Show() end, L.DESK_OPEN_TIP)
    local places = {}
    for _, place in ipairs(ns.DeskButton.PLACES) do
        places[#places + 1] = { place, L["DESK_PLACE_" .. place:upper()] }
    end
    Dropdown("deskButton", L.OPT_DESK_BUTTON, L.OPT_DESK_BUTTON_TIP, "minimap", places)
    Checkbox("deskCards", L.OPT_DESK_CARDS, L.OPT_DESK_CARDS_TIP, true)
    Checkbox("deskBarPinned", L.OPT_DESK_PINNED, L.DESK_PIN_TIP, false)
    Checkbox("deskAutoKeys", L.OPT_DESK_AUTO_KEYS, L.OPT_DESK_AUTO_KEYS_TIP, true)
    Checkbox("deskSound", L.DESK_OPT_SOUND, L.OPT_DESK_SOUND_TIP, true)
    local sounds = {}
    for _, sound in ipairs(ns.DeskAlert.SOUNDS) do
        sounds[#sounds + 1] = { sound[1], L["DESK_SOUND_" .. sound[1]:upper()] }
    end
    Dropdown("deskSoundName", L.OPT_DESK_SOUND_NAME, L.OPT_DESK_SOUND_NAME_TIP, "whisper", sounds,
        function(value) ns.DeskAlert.PlayAlert(value) end)

    Header(L.OPT_DATA)
    Button(L.OPT_EXPORT, L.EXPORT_BUTTON, function() ns.ExportWindow:Show() end, L.OPT_EXPORT_TIP)
    Button(L.OPT_WIPE, L.OPT_WIPE_BUTTON, function()
        StaticPopup_Show("TRUSTCRAFTER_WIPE", Util.Realm())
    end, L.OPT_WIPE_TIP)
    Checkbox("debug", L.OPT_DEBUG, L.OPT_DEBUG_TIP, false)

    Settings.RegisterAddOnCategory(category)
end

function Options:Open()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

ns.Events:On("TC_DB_READY", function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)

ns:RegisterCommand("options", function() Options:Open() end, L.HELP_OPTIONS)
