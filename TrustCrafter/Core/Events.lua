-- TrustCrafter - event dispatcher.
-- One frame for all game events, plus internal messages prefixed "TC_".
-- Handlers are called as fn(event, ...). An error in one handler is
-- reported but does not stop the others.

local _, ns = ...

local Events = {}
ns.Events = Events

local frame = CreateFrame("Frame")
local handlers = {}

local function Dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        xpcall(list[i], geterrorhandler(), event, ...)
    end
end

-- Returns false when the game does not know this event (renamed or removed
-- in a patch), so callers can carry on without it.
function Events:On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if not event:find("^TC_") then
            if not pcall(frame.RegisterEvent, frame, event) then
                handlers[event] = nil
                return false
            end
        end
    end
    list[#list + 1] = fn
    return true
end

function Events:Fire(message, ...)
    Dispatch(message, ...)
end

frame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(event, ...)
end)
