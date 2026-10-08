-- TrustCrafter - your history with a crafter in the right-click player
-- menu. Chat names have no hover tooltip in WoW, so this is how the summary
-- reaches a name in chat, the friends list, a guild roster or a unit frame.
-- Only shown for crafters you have used; clicking it opens the history
-- window filtered to them.

local _, ns = ...
local L, Util = ns.L, ns.Util

-- Menus that are about one player. A tag this client doesn't have is
-- simply never opened, so listing extra ones is harmless.
local MENU_TAGS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_BN_FRIEND", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_GUILD",
}

local function NameFrom(contextData)
    if not contextData then return nil end
    local name, server = contextData.name, contextData.server
    if (not name or name == "") and contextData.unit and UnitFullName then
        name, server = UnitFullName(contextData.unit)
    end
    if not name or name == "" then return nil end
    if issecretvalue and (issecretvalue(name) or (server and issecretvalue(server))) then return nil end
    return Util.FullName(name, server)
end

local function AddToMenu(_, rootDescription, contextData)
    if not ns.db then return end
    local crafter = ns.Ledger:FindCrafter(NameFrom(contextData))
    local s = crafter and ns.Ledger:Summary(crafter)
    if not s then return end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle(L.WINDOW_TITLE)
    rootDescription:CreateButton(ns.Tooltip.SummaryLine(nil, s), function()
        ns.HistoryWindow:ShowCrafter(crafter)
    end)
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(MENU_TAGS) do
        pcall(Menu.ModifyMenu, tag, AddToMenu)
    end
end
