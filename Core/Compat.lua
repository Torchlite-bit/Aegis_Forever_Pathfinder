local _, AP = ...

--[[
	What this client offers, asked rather than assumed.

	Forever (interface 16001, the "camelot" game type) runs the modern engine with
	its own subset of Blizzard's interface. Inside dungeons and in some fights it
	hands addons "secret" values -- unit names and guids, chat text -- which can be
	shown but not compared or stored. Everything that reads the client goes through
	these helpers, so a value it withholds is treated as unknown instead of raising
	an error. Learned on the Aegis: Forever Instance Journal.
]]

local Compat = {}
AP.Compat = Compat

function Compat.IsSecret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, value)
	return ok and secret == true
end

--- The value, or nil if the client withholds it.
function Compat.Readable(value)
	if Compat.IsSecret(value) then return nil end
	return value
end

--- Calls `fn(...)` and returns its first result, readable, or nil if it is
--- missing, errors or is secret.
function Compat.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return Compat.Readable(value) end
	return nil
end

--- Every result of `fn(...)`, each readable or nil; nothing when it is missing or errors.
local function Pack(...) return select("#", ...), { ... } end

function Compat.CallAll(fn, ...)
	if type(fn) ~= "function" then return end
	local count, results = Pack(pcall(fn, ...))
	if not results[1] then return end
	for index = 2, count do results[index] = Compat.Readable(results[index]) end
	return unpack(results, 2, count)
end

function Compat.HasTemplate(name)
	if not name then return false end
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
		local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
		if ok then return info ~= nil end
	end
	return true
end

--- A frame from the first template the client has, or a plain frame.
function Compat.CreateFrame(frameType, name, parent, ...)
	for index = 1, select("#", ...) do
		local template = select(index, ...)
		if Compat.HasTemplate(template) then
			local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
			if ok and frame then return frame, template end
		end
	end
	return CreateFrame(frameType, name, parent), nil
end

function Compat.InInstance()
	local ok, inside = pcall(IsInInstance)
	return ok and Compat.Readable(inside) == true
end

function Compat.InCombat()
	return InCombatLockdown and InCombatLockdown() or false
end

--- What a guid names: its kind ("Creature", "GameObject", "Player", ...) and,
--- for a creature or an object, its id.
function Compat.ParseGUID(guid)
	guid = Compat.Readable(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
		return kind, tonumber(id)
	end
	return kind, nil
end

function Compat.ItemIDFromLink(link)
	link = Compat.Readable(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function Round(value)
	return math.floor(value * 10000 + 0.5) / 10000
end
Compat.Round = Round

--- The player's map and position (0..1, four places), where the client reports
--- one: there is none inside Forever's dungeons.
function Compat.PlayerMapPosition()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local mapID = Compat.Call(C_Map.GetBestMapForUnit, "player")
	if type(mapID) ~= "number" then return nil end
	local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not ok or not position then return mapID end
	local x, y = position:GetXY()
	x, y = Compat.Readable(x), Compat.Readable(y)
	if type(x) ~= "number" or type(y) ~= "number" then return mapID end
	return mapID, Round(x), Round(y)
end

--- The player's position (0..1, not rounded) on `mapID`, which need not be the map
--- they stand on; nil when the client gives none there.
function Compat.PlayerPositionOn(mapID)
	if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
	local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not (ok and position and position.GetXY) then return nil end
	local x, y = position:GetXY()
	x, y = Compat.Readable(x), Compat.Readable(y)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

function Compat.MapName(mapID)
	if not (mapID and C_Map and C_Map.GetMapInfo) then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, mapID)
	return ok and info and Compat.Readable(info.name) or nil
end

--- Copper as coin icons.
function Compat.MoneyText(copper)
	copper = tonumber(copper) or 0
	for _, format in ipairs({ C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString, GetMoneyString,
		GetCoinTextureString }) do
		if type(format) == "function" then
			local ok, text = pcall(format, copper)
			if ok and type(text) == "string" and text ~= "" then return text end
		end
	end
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	return string.format("%dg %ds %dc", gold, silver, rest)
end

function Compat.Timestamp()
	return (GetServerTime and GetServerTime()) or time()
end

--- The client's version, build and interface number.
function Compat.Build()
	local ok, version, build, _, interface = pcall(GetBuildInfo)
	if not ok then return "?", "?", 0 end
	return version, build, interface
end

--- Who is playing, for stamping what the collector writes.
function Compat.Player()
	local _, race = Compat.CallAll(UnitRace, "player")
	local _, class = Compat.CallAll(UnitClass, "player")
	local faction = Compat.Call(UnitFactionGroup, "player")
	return {
		name = Compat.Call(UnitName, "player"),
		realm = Compat.Call(GetRealmName),
		race = race,
		class = class,
		faction = faction,
		level = Compat.Call(UnitLevel, "player"),
	}
end

function Compat.PlaySound(key)
	if SOUNDKIT and SOUNDKIT[key] and PlaySound then pcall(PlaySound, SOUNDKIT[key]) end
end
