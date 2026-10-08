-- TrustCrafter - is a crafter online right now? A small dot next to their
-- name: green online, red offline, grey when the game won't say.
--
-- The main source is the game's own whisper check: given a character's
-- GUID it answers whether they can be whispered (online), are offline, or
-- neither (a cross-realm or other-faction player it can't reach). Only a
-- plain "offline" answer turns the dot red. Friends, your group and
-- Battle.net friends can turn an unclear answer green. Nothing here needs
-- a click and nothing is sent to the crafter.

local _, ns = ...
local L, Util = ns.L, ns.Util

local Presence = {}
ns.Presence = Presence

local REQUEST_EVERY = 30 -- seconds between checks of one crafter
local STATUS_ONLINE, STATUS_OFFLINE = 0, 1 -- Enum.ChatWhisperTargetStatus

local DOT = "|TInterface\\CharacterFrame\\TempPortraitAlphaMask:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"
local COLORS = {
    online = { 70, 210, 90 },
    offline = { 220, 70, 60 },
    unknown = { 130, 130, 130 },
}

local status = {}      -- guid -> "online" | "offline" (missing = unknown)
local requestedAt = {} -- guid -> time of the last check
local guidByName       -- "name-realm" (lower case) -> newest crafterGuid
local changedTimer

local function Secret(value)
    return issecretvalue and value ~= nil and issecretvalue(value)
end

local function Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked == true
    end
    return false
end

-- Asks the game again, at most once every REQUEST_EVERY per crafter.
local function Request(guid)
    if not (C_ChatInfo and C_ChatInfo.RequestCanLocalWhisperTarget) or Locked() then return end
    local now = GetTime()
    if requestedAt[guid] and now - requestedAt[guid] < REQUEST_EVERY then return end
    requestedAt[guid] = now
    pcall(C_ChatInfo.RequestCanLocalWhisperTarget, guid)
end

-- Online according to something other than the whisper check: a friend,
-- someone in your group or a Battle.net friend on that character.
local function SeenElsewhere(guid, fullName)
    if fullName then
        -- Same-realm names are looked up bare, as the game lists them.
        local suffix = "-" .. Util.Realm()
        local short = fullName
        if fullName:sub(-#suffix) == suffix then short = fullName:sub(1, -#suffix - 1) end
        if C_FriendList and C_FriendList.GetFriendInfo then
            local ok, info = pcall(C_FriendList.GetFriendInfo, short)
            if ok and type(info) == "table" and info.connected then return true end
        end
        local ok, connected = pcall(function()
            return (UnitInParty(short) or UnitInRaid(short)) and UnitIsConnected(short)
        end)
        if ok and connected then return true end
    end
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        local ok, account = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
        local game = ok and type(account) == "table" and account.gameAccountInfo
        if game and game.isOnline and game.playerGuid == guid then return true end
    end
    return false
end

-- The newest GUID logged for a crafter ("Name-Realm"), or nil.
function Presence:GuidFor(crafter)
    if not crafter or not ns.db then return nil end
    if not guidByName then
        guidByName = {}
        local newest = {}
        for _, record in pairs(ns:RealmData().orders) do
            if record.crafter and record.crafterGuid then
                local key = record.crafter:lower()
                local at = record.completedAt or record.placedAt or 0
                if not newest[key] or at > newest[key] then
                    newest[key] = at
                    guidByName[key] = record.crafterGuid
                end
            end
        end
    end
    return guidByName[crafter:lower()]
end

-- "online", "offline" or "unknown". Also asks the game for a fresh answer,
-- which arrives a moment later as TC_PRESENCE_CHANGED.
function Presence:Get(guid, crafter)
    if not guid or Secret(guid) then return "unknown" end
    if guid == UnitGUID("player") then return "online" end
    Request(guid)
    local known = status[guid]
    if known == "online" then return "online" end
    if SeenElsewhere(guid, crafter) then return "online" end
    return known or "unknown"
end

-- The dot as text, ready to put in front of a name.
function Presence:Dot(guid, crafter, size)
    local c = COLORS[self:Get(guid, crafter)]
    size = size or 8
    return DOT:format(size, size, c[1], c[2], c[3])
end

-- Dot plus "Online" / "Offline" / "Status unknown", for detail lines.
function Presence:Label(guid, crafter)
    local s = self:Get(guid, crafter)
    local c = COLORS[s]
    return DOT:format(8, 8, c[1], c[2], c[3]) .. " " .. L["STATUS_" .. s:upper()]
end

function Presence:ForCrafter(crafter)
    return self:Dot(self:GuidFor(crafter), crafter)
end

local function Changed()
    if changedTimer then return end
    changedTimer = C_Timer.NewTimer(0.3, function()
        changedTimer = nil
        ns.Events:Fire("TC_PRESENCE_CHANGED")
    end)
end

ns.Events:On("CAN_LOCAL_WHISPER_TARGET_RESPONSE", function(_, guid, code)
    if not guid or Secret(guid) or Secret(code) then return end
    local new = code == STATUS_ONLINE and "online" or code == STATUS_OFFLINE and "offline" or nil
    if status[guid] ~= new then
        status[guid] = new
        Changed()
    end
end)

ns.Events:On("TC_LEDGER_CHANGED", function() guidByName = nil end)
