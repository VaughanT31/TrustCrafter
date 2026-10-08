-- TrustCrafter - small shared helpers: time, names, formatting.

local _, ns = ...
local L = ns.L

local Util = {}
ns.Util = Util

function Util.Now()
    return GetServerTime()
end

function Util.Print(msg)
    print("|cff66ccffTrustCrafter:|r " .. msg)
end

-- The player's realm, without spaces ("Draenor", "ArgentDawn"): the same
-- form the game uses in "Name-Realm".
function Util.Realm()
    return GetNormalizedRealmName() or ""
end

-- "Name-Realm" for any name, adding the player's realm when it is left off.
-- Crafters and reviewers are always stored this way, because the game
-- sometimes gives a name with its realm and sometimes without.
function Util.FullName(name, realm)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    if not realm or realm == "" then realm = Util.Realm() end
    return name .. "-" .. realm:gsub("%s", "")
end

function Util.ShortName(fullName)
    return fullName and (fullName:match("^([^%-]+)") or fullName) or "?"
end

-- "38 min", "5 h 10 min", "2 d 3 h".
function Util.FormatDuration(seconds)
    if not seconds or seconds < 0 then return nil end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return L.DURATION_MIN:format(math.max(1, minutes)) end
    local hours = math.floor(minutes / 60)
    if hours < 24 then
        local rest = minutes % 60
        return rest > 0 and L.DURATION_H_MIN:format(hours, rest) or L.DURATION_H:format(hours)
    end
    local days = math.floor(hours / 24)
    local rest = hours % 24
    return rest > 0 and L.DURATION_D_H:format(days, rest) or L.DURATION_D:format(days)
end

-- "3 Oct" style short date.
function Util.FormatDate(timestamp)
    return timestamp and date("%d %b", timestamp) or ""
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"

-- Tips are shown to the gold (silver below 1g); copper never matters here.
function Util.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10000 then
        return BreakUpLargeNumbers(math.floor(copper / 10000)) .. GOLD_ICON
    end
    return math.floor(copper / 100) .. SILVER_ICON
end

-- Crafting quality as the game's own rank icon, or "R3" when the atlas is
-- missing.
function Util.QualityText(quality)
    if not quality or quality <= 0 then return "-" end
    local atlas = "Professions-Icon-Quality-Tier" .. quality .. "-Small"
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return CreateAtlasMarkup(atlas, 18, 18)
    end
    return "R" .. quality
end
