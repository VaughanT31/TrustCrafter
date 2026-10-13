-- TrustCrafter - addon messages between TrustCrafter users, for guild
-- sharing (Data/Sharing.lua).
--
-- Messages are small tables: serialized (LibSerialize), compressed and made
-- safe for the addon channel (LibDeflate), then sent with AceComm, which
-- splits long ones and paces them through ChatThrottleLib.
--
-- The sender of an addon message is filled in by the server, not by the
-- sending addon, so a message received directly from someone really is
-- from them. Nothing is ever relayed.
--
-- Midnight locks addon messages during raid encounters and Mythic+ runs.
-- Outgoing messages wait in a queue until that lifts, and incoming ones
-- with secret values are dropped.

local _, ns = ...
local Util = ns.Util

local Comm = {}
ns.Comm = Comm

local PREFIX = "TrustCrafter"
local PROTOCOL = 1
local QUEUE_CHECK = 5
local QUEUE_MAX = 20

local AceComm = LibStub and LibStub("AceComm-3.0", true)
local LibSerialize = LibStub and LibStub("LibSerialize", true)
local LibDeflate = LibStub and LibStub("LibDeflate", true)

local handlers = {}
local queue = {}
local queueTicker

local function Secret(value)
    return issecretvalue and value ~= nil and issecretvalue(value)
end

function Comm:Available()
    return AceComm ~= nil and LibSerialize ~= nil and LibDeflate ~= nil
end

function Comm:Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked == true
    end
    return false
end

-- fn(message, sender, channel) runs for each message of this kind. sender
-- is "Name-Realm".
function Comm:On(kind, fn)
    handlers[kind] = fn
end

function Comm.Encode(kind, payload)
    local message = { v = PROTOCOL, k = kind, p = payload }
    local serialized = LibSerialize:Serialize(message)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

-- The message table, or nil when it is damaged or from a newer protocol
-- this version can't read.
function Comm.Decode(data)
    if type(data) ~= "string" then return nil end
    local compressed = LibDeflate:DecodeForWoWAddonChannel(data)
    if not compressed then return nil end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, message = LibSerialize:Deserialize(serialized)
    if not ok or type(message) ~= "table" or type(message.k) ~= "string" then return nil end
    if message.v ~= PROTOCOL then return nil end
    return message
end

local function Transmit(item)
    Comm:SendCommMessage(PREFIX, item.data, item.channel, item.target, "BULK")
end

local function FlushQueue()
    if Comm:Locked() then return end
    while #queue > 0 do Transmit(table.remove(queue, 1)) end
    if queueTicker then
        queueTicker:Cancel()
        queueTicker = nil
    end
end

-- Sends one message. channel is "GUILD" or "WHISPER" (with target).
function Comm:Send(kind, payload, channel, target)
    if not self:Available() then return false end
    local item = { data = Comm.Encode(kind, payload), channel = channel, target = target }
    if self:Locked() then
        if #queue >= QUEUE_MAX then table.remove(queue, 1) end
        queue[#queue + 1] = item
        if not queueTicker then queueTicker = C_Timer.NewTicker(QUEUE_CHECK, FlushQueue) end
        return true
    end
    Transmit(item)
    return true
end

function Comm.Receive(_, data, channel, sender)
    if Secret(data) or Secret(sender) or Secret(channel) or not sender then return end
    local fullName = Util.FullName(sender)
    if not fullName or ns.Ledger:IsMine(fullName) then return end
    local message = Comm.Decode(data)
    if not message then return end
    local handler = handlers[message.k]
    if handler then
        local ok, err = pcall(handler, message.p, fullName, channel)
        if not ok then geterrorhandler()(err) end
    end
end

if Comm:Available() then
    AceComm:Embed(Comm)
    Comm:RegisterComm(PREFIX, Comm.Receive)
end
