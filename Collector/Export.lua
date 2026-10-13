local _, AP = ...
local Compat = AP.Compat
local Collector = AP.Collector

--[[
	What the collector wrote, ready to send.

	Two forms of the same thing, an "envelope": the format, the addon and client
	versions, when it was made, the name the player asked to be credited under,
	and the collected data.

	- The share code (Export.ShareCode): "APF1:" and the envelope as JSON,
	  compressed and written in Base64 by the client's own C_EncodingUtil.
	  Several times smaller than the text, and one line, so it pastes whole
	  into a GitHub issue, where Tools/ingest_issue.py reads it.
	- The plain export (Export.Build): a header line, then the envelope as JSON.
	  What a client without C_EncodingUtil gets, and what "As text" shows.

	JSON keys are sorted, so two exports of the same data are the same text.
	The session-only bits of the saved data (the window's log) are left out, and
	nothing in it names a character: observers are race, class and faction. The
	one name in it is the credit name, which the player chooses (empty: the
	character's name).
]]

local Export = {}
AP.Export = Export

Export.HEADER = "AEGIS PATHFINDER FOREVER DATA"
Export.FORMAT = 2
Export.CODE_PREFIX = "APF1:"
Export.ADDON = "Aegis_Forever_Pathfinder"
Export.CREDIT_MAX = 40

-- Where to send it. The GitHub form files the data by itself (.github/workflows/ingest-data.yml).
Export.GITHUB_URL = "https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever/issues/new?template=submit-data.yml"
Export.DISCORD_URL = "https://discord.gg/Hr66t25vE7"
-- A GitHub issue takes about 65,000 characters; past that, send the file.
Export.ISSUE_LIMIT = 60000

-- Parts of the saved data that stay at home.
local LEFT_OUT = { log = true }

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function EncodeString(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

-- An array only when its keys are exactly 1..n. Not `#t`: in Lua 5.1 a table
-- with gaps can report any border, and ipairs would then drop what follows a gap.
local function IsArray(t)
	local count, largest = 0, 0
	for key in pairs(t) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count = count + 1
		if key > largest then largest = key end
	end
	return count == largest
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
			for key in pairs(value) do keys[#keys + 1] = key end
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

--[[ The credit name ]]

--- A name made safe to send: no line breaks, no field separators, no UI escape codes, at most 40 letters.
function Export.CleanName(name)
	if type(name) ~= "string" then return "" end
	name = name:gsub("|", ""):gsub("[%c;]", " "):gsub("%s+", " ")
	name = name:match("^%s*(.-)%s*$")
	-- At most 40 letters, counted as UTF-8 characters so a name is never cut inside one.
	local letters, cut = 0, #name
	for start in name:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
		letters = letters + 1
		if letters > Export.CREDIT_MAX then
			cut = start - 1
			break
		end
	end
	return (name:sub(1, cut):match("^(.-)%s*$"))
end

--- What the player typed in "Credit me as", or "".
function Export.GetCreditName()
	return Export.CleanName(AP.db.profile.creditName)
end

function Export.SetCreditName(name)
	name = Export.CleanName(name)
	AP.db.profile.creditName = name ~= "" and name or nil
end

--- The name the data goes out under: the chosen one, else the character's.
function Export.CreditName()
	local name = Export.GetCreditName()
	if name ~= "" then return name end
	return Export.CleanName(Compat.Call(UnitName, "player") or "")
end

--[[ The envelope ]]

--- The collected data without what stays at home.
local function Sendable(data)
	local copy = {}
	for key, value in pairs(data or {}) do
		if not LEFT_OUT[key] then copy[key] = value end
	end
	return copy
end

function Export.Envelope()
	local version, build, interface = Compat.Build()
	return {
		format = Export.FORMAT,
		addon = Export.ADDON,
		addonVersion = AP.version,
		build = version .. "." .. build,
		interface = tonumber(interface) or 0,
		exportedAt = Compat.Timestamp(),
		contributor = Export.CreditName(),
		data = Sendable(Collector:GetData()),
	}
end

--- The plain export: the header line, then the envelope as JSON.
function Export.Build(envelope)
	envelope = envelope or Export.Envelope()
	local header = table.concat({ Export.HEADER, Export.FORMAT, envelope.addonVersion, envelope.build,
		tostring(envelope.interface), date("!%Y-%m-%dT%H:%M:%SZ", envelope.exportedAt), envelope.contributor }, ";")
	return header .. "\n" .. Export.ToJSON(envelope)
end

--- True when this client can make share codes.
function Export.CanEncode()
	local util = C_EncodingUtil
	return type(util) == "table" and type(util.CompressString) == "function"
		and type(util.EncodeBase64) == "function" and type(Enum) == "table"
		and type(Enum.CompressionMethod) == "table" and Enum.CompressionMethod.Zlib ~= nil
end

--- The share code: "APF1:" then Base64 of the zlib-compressed envelope JSON. Nil when the client can't.
function Export.ShareCode(envelope)
	if not Export.CanEncode() then return nil end
	local json = Export.ToJSON(envelope or Export.Envelope())
	local ok, packed = pcall(C_EncodingUtil.CompressString, json, Enum.CompressionMethod.Zlib)
	if not ok or type(packed) ~= "string" or packed == "" then return nil end
	local encoded
	ok, encoded = pcall(C_EncodingUtil.EncodeBase64, packed)
	if not ok or type(encoded) ~= "string" or encoded == "" then return nil end
	return Export.CODE_PREFIX .. encoded
end

--[[ "New since your last send": what the collection held the last time the
	Submit window showed it, kept outside the data so it never goes out. ]]

function Export.MarkSent()
	local data, counts = Collector:GetData(), Collector:Counts()
	AP.db.global.lastSent = { id = data and data.id, quests = counts.quests, levels = counts.levels,
		at = Compat.Timestamp() }
end

--- Quests and levels added since the last send (all of them for a collection never sent).
function Export.NewSinceSent()
	local data, counts = Collector:GetData(), Collector:Counts()
	local sent = AP.db.global.lastSent
	if type(sent) ~= "table" or not data or sent.id ~= data.id then return counts.quests, counts.levels, nil end
	return math.max(0, counts.quests - (sent.quests or 0)), math.max(0, counts.levels - (sent.levels or 0)), sent.at
end
