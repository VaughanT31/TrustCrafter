-- TrustCrafter - bootstrap: SavedVariables, slash commands, the addon
-- compartment button. Other modules wait for these internal messages:
--   TC_DB_READY  ns.db is ready (ADDON_LOADED)
--   TC_LOGIN     the character is in the world (PLAYER_LOGIN)
--
-- Everything is kept per realm, because public crafting orders only reach
-- crafters on your own realm:
--   TrustCrafterDB.realms[realm] = {
--     orders  = { [orderID] = record, ... }   see Data/Orders.lua
--     placing = { { t, orderType, tip }, ... } orders just placed, waiting
--                                              for their order ID
--   }

local ADDON_NAME, ns = ...
local L, Util = ns.L, ns.Util

local DB_VERSION = 1

local DEFAULTS = {
    version = DB_VERSION,
    settings = {
        tooltip = true,
        debug = false,
    },
    realms = {},
    debugLog = {},
}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                ApplyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

-- This realm's data, created on first use.
function ns:RealmData(realm)
    realm = realm or Util.Realm()
    local data = ns.db.realms[realm]
    if not data then
        data = {}
        ns.db.realms[realm] = data
    end
    data.orders = data.orders or {}
    data.placing = data.placing or {}
    -- Your own characters on this realm ("Name-Realm" = true), so you can't
    -- rate an order one of them crafted.
    data.characters = data.characters or {}
    -- Crafting order mails already matched to an order (Data/Orders.lua).
    data.mailSeen = data.mailSeen or {}
    return data
end

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------

local commands, commandOrder = {}, {}

-- fn(args) runs for "/tc <name> <args>". help is a line for "/tc help".
function ns:RegisterCommand(name, fn, help)
    commands[name] = { fn = fn, help = help }
    commandOrder[#commandOrder + 1] = name
end

local function ShowHelp()
    Util.Print(L.HELP_HEADER)
    print("  " .. L.HELP_TOGGLE)
    for _, name in ipairs(commandOrder) do
        if commands[name].help then print("  " .. commands[name].help) end
    end
end

SLASH_TRUSTCRAFTER1 = "/tc"
SLASH_TRUSTCRAFTER2 = "/trustcrafter"
SlashCmdList.TRUSTCRAFTER = function(input)
    if not ns.db then return end
    local name, args = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    name = (name or ""):lower()
    if name == "" then
        if ns.HistoryWindow then ns.HistoryWindow:Toggle() end
    elseif name == "help" then
        ShowHelp()
    elseif commands[name] then
        commands[name].fn(args)
    else
        Util.Print(L.UNKNOWN_COMMAND:format(name))
        ShowHelp()
    end
end

function TrustCrafter_OnAddonCompartmentClick()
    if ns.HistoryWindow then ns.HistoryWindow:Toggle() end
end

ns:RegisterCommand("tooltip", function()
    ns.db.settings.tooltip = not ns.db.settings.tooltip
    Util.Print(ns.db.settings.tooltip and L.TOOLTIP_ON or L.TOOLTIP_OFF)
end, L.HELP_TOOLTIP)

-- Wiping asks first: it cannot be undone.
StaticPopupDialogs["TRUSTCRAFTER_WIPE"] = {
    text = L.WIPE_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.db.realms[Util.Realm()] = nil
        ns.Events:Fire("TC_LEDGER_CHANGED")
        Util.Print(L.WIPE_DONE)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

ns:RegisterCommand("wipe", function()
    StaticPopup_Show("TRUSTCRAFTER_WIPE", Util.Realm())
end, L.HELP_WIPE)

-- ---------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------

ns.Events:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    TrustCrafterDB = TrustCrafterDB or {}
    ApplyDefaults(TrustCrafterDB, DEFAULTS)
    TrustCrafterDB.version = DB_VERSION
    ns.db = TrustCrafterDB
    ns.Events:Fire("TC_DB_READY")
end)

ns.Events:On("PLAYER_LOGIN", function()
    ns:RealmData().characters[Util.FullName(UnitName("player"))] = true
    ns.Events:Fire("TC_LOGIN")
end)
