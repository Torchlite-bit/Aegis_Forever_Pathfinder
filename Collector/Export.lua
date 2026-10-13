local _, AP = ...
local Compat = AP.Compat
local Collector = AP.Collector

--[[
	What the collector wrote, as text to copy out of the game: one line naming
	the format, then the data as JSON, keys sorted so two exports of the same
	data are the same text. Tools/merge_exports.py merges many players' exports
	into one file to write guides from.

	The session-only bits of the saved data (the window's log) are left out, and
	nothing in it names a character: observers are race, class and faction.
]]

local Export = {}
AP.Export = Export

Export.HEADER = "AEGIS PATHFINDER FOREVER DATA"
Export.FORMAT = 1

local LEFT_OUT = { log = true }

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function EncodeString(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function IsArray(t)
	local count = 0
	for key in pairs(t) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count = count + 1
	end
	return count == #t
end

local function SortKeys(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta < tb end
	return a < b
end

local function Encode(value, out, depth)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = EncodeString(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			out[#out + 1] = "null"
		elseif value % 1 == 0 then
			out[#out + 1] = string.format("%d", value)
		else
			out[#out + 1] = string.format("%.4f", value):gsub("0+$", "")
		end
	elseif kind == "boolean" then
		out[#out + 1] = value and "true" or "false"
	elseif kind == "table" then
		if depth > 20 then
			out[#out + 1] = "null"
			return
		end
		if next(value) ~= nil and IsArray(value) then
			out[#out + 1] = "["
			for index, item in ipairs(value) do
				if index > 1 then out[#out + 1] = "," end
				Encode(item, out, depth + 1)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for key in pairs(value) do
				if depth > 0 or not LEFT_OUT[key] then keys[#keys + 1] = key end
			end
			table.sort(keys, SortKeys)
			out[#out + 1] = "{"
			for index, key in ipairs(keys) do
				if index > 1 then out[#out + 1] = "," end
				out[#out + 1] = EncodeString(tostring(key))
				out[#out + 1] = ":"
				Encode(value[key], out, depth + 1)
			end
			out[#out + 1] = "}"
		end
	else
		out[#out + 1] = "null"
	end
end

--- Any Lua value as JSON. Number keys become strings, as JSON has it.
function Export.ToJSON(value)
	local out = {}
	Encode(value, out, 0)
	return table.concat(out)
end

--- The whole export: the header line, then the collected data as JSON.
function Export.Build()
	local version, build, interface = Compat.Build()
	local header = table.concat({ Export.HEADER, Export.FORMAT, AP.version, version .. "." .. build,
		tostring(interface), date("!%Y-%m-%dT%H:%M:%SZ") }, ";")
	return header .. "\n" .. Export.ToJSON(Collector:GetData() or {})
end
