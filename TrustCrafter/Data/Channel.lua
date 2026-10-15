-- TrustCrafter - the hidden realm channel, for realm sharing (3.0).
--
-- When "Share on my realm" is on, TrustCrafter joins a channel the player
-- never sees: a temporary channel (so it isn't saved into their channel
-- list), removed from every chat tab, and used only for addon messages,
-- never chat text. It's only for short questions ("anyone have orders with
-- Thalric-Draenor?"); answers come back by whisper (Data/Sharing.lua).
--
--   - Joined 60 seconds after login, so it never takes /1 from General.
--   - Channels span the connected realm.
--   - It takes one of the player's 10 channel slots. With none free, realm
--     sharing stays off and the options page says why.
--   - Anyone can password-protect or ban people from a channel they own.
--     If joining fails, the next backup name is tried; if we drop out of
--     the channel, it's joined again (then the next name if that fails).
--     TrustCrafter never tries to own or moderate the channel.
--   - Turning realm sharing off leaves the channel straight away.

local _, ns = ...

local Channel = {}
ns.Channel = Channel

local NAMES = { "TrustCrafter", "TrustCrafter2", "TrustCrafter3" }
local JOIN_DELAY = 60
local JOIN_CHECK = 8      -- seconds to wait before deciding a join failed
local MAX_CHANNELS = 10

local state = {
    index = 1,            -- which of NAMES we're on
    joined = false,
    status = "off",       -- off | waiting | joining | joined | noslot | blocked
    loginAt = nil,
}

local function Settings() return ns.db and ns.db.settings or {} end

function Channel:Wanted()
    return Settings().realmShare == true and ns.Comm:Available()
end

function Channel:Name()
    return NAMES[state.index]
end

-- The channel's number for addon messages, or nil when not joined.
function Channel:Number()
    if not state.joined then return nil end
    local id = GetChannelName(self:Name())
    if type(id) == "number" and id > 0 then return id end
    return nil
end

function Channel:IsOurs(channelName)
    if type(channelName) ~= "string" then return false end
    local base = channelName:gsub("^%d+%.%s*", "")
    for _, name in ipairs(NAMES) do
        if base:lower() == name:lower() then return true end
    end
    return false
end

-- For the options page.
function Channel:Status()
    return state.status
end

local function CountChannels()
    local count, list = 0, { GetChannelList() }
    -- GetChannelList returns id, name, disabled triples.
    for i = 1, #list, 3 do
        if list[i] then count = count + 1 end
    end
    return count
end

-- Takes the channel out of every chat tab, so nothing about it shows.
local function HideFromChat(name)
    local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
    if not remove then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(remove, frame, name) end
    end
end

local function Fire()
    ns.Events:Fire("TC_CHANNEL_CHANGED", state.status)
end

local Join

local function TryNext()
    state.joined = false
    if state.index < #NAMES then
        state.index = state.index + 1
        Join()
    else
        state.status = "blocked"
        Fire()
    end
end

Join = function()
    if not Channel:Wanted() then return end
    local name = Channel:Name()
    if GetChannelName(name) > 0 then
        state.joined, state.status = true, "joined"
        HideFromChat(name)
        Fire()
        return
    end
    if CountChannels() >= MAX_CHANNELS then
        state.status = "noslot"
        Fire()
        return
    end
    state.status = "joining"
    JoinTemporaryChannel(name)
    C_Timer.After(JOIN_CHECK, function()
        if not Channel:Wanted() or Channel:Name() ~= name then return end
        if GetChannelName(name) > 0 then
            state.joined, state.status = true, "joined"
            HideFromChat(name)
            Fire()
        else
            TryNext()
        end
    end)
end

function Channel:Leave()
    for _, name in ipairs(NAMES) do
        if GetChannelName(name) > 0 then LeaveChannelByName(name) end
    end
    state.joined, state.status, state.index = false, "off", 1
    Fire()
end

-- Called when the option changes and at login.
function Channel:Update()
    if not self:Wanted() then
        if state.joined or state.status ~= "off" then self:Leave() end
        return
    end
    if state.joined or state.status == "joining" or state.status == "waiting" then return end
    local wait = state.loginAt and math.max(0, JOIN_DELAY - (GetTime() - state.loginAt)) or JOIN_DELAY
    state.status = "waiting"
    Fire()
    C_Timer.After(wait, Join)
end

-- Kicked, banned or a password set: every minute, check we're still in the
-- channel. If not, join again; a join that fails (banned, or a password set)
-- moves on to the next name. Only our own membership is looked at, never
-- channel notices, which also fire when someone else is kicked.
local CHECK_EVERY = 60
C_Timer.NewTicker(CHECK_EVERY, function()
    if not Channel:Wanted() or not state.joined then return end
    if GetChannelName(Channel:Name()) == 0 then
        state.joined = false
        Join()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
events:SetScript("OnEvent", function(_, event, text, _, _, channelName, _, _, _, _, baseName)
    if event == "PLAYER_LOGIN" then
        state.loginAt = GetTime()
        return
    end
    -- The game can put a channel back into a chat tab when it's joined or
    -- changes; take it out again.
    if issecretvalue and (issecretvalue(text) or issecretvalue(channelName)) then return end
    if Channel:Wanted() and (text == "YOU_JOINED" or text == "YOU_CHANGED")
        and (Channel:IsOurs(baseName) or Channel:IsOurs(channelName)) then
        HideFromChat(Channel:Name())
    end
end)

ns.Events:On("TC_DB_READY", function() Channel:Update() end)
