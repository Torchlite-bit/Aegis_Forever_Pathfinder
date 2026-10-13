local _, AP = ...
local Compat = AP.Compat
local Call, Readable = Compat.Call, Compat.Readable

--[[ Extras.lua -- the options' Extras page: what it adds to chat.

	  * Detailed reputation gains: when a reputation goes up, where it stands
	    and how far it is to the next rank -- "Stormwind +25: Honored 4,350 /
	    12,000, 7,650 to Revered" -- after the client's own line.
	  * Level-up announcements: an emote others nearby see, on until unticked,
	    and the same news to your party and guild, each off until ticked. The
	    time is how long you spent at the level just left, when the collector
	    saw all of it.
]]

local Extras = {}
AP.Extras = Extras

local REP_DELAY = 0.2     -- the standing and the chat line come from one message, in either order

local function Char() return AP.db and AP.db.char end

--[[ Words ]]

--- 7650 as "7,650".
function Extras.Thousands(n)
	local s = tostring(math.floor(n))
	local sign = ""
	if s:sub(1, 1) == "-" then sign, s = "-", s:sub(2) end
	while true do
		local done
		s, done = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if done == 0 then break end
	end
	return sign .. s
end

local function Count(n, word)
	return n .. " " .. word .. (n == 1 and "" or "s")
end

--- Seconds as "2 hours 1 minute", "1 minute", "less than a minute".
function Extras.Duration(secs)
	local mins = math.floor(secs / 60)
	local hours = math.floor(mins / 60)
	mins = mins - hours * 60
	if hours > 0 then
		return Count(hours, "hour") .. (mins > 0 and (" " .. Count(mins, "minute")) or "")
	elseif mins > 0 then
		return Count(mins, "minute")
	end
	return "less than a minute"
end

--[[ Reputation ]]

--- The faction and the gain in a reputation line; nil for any other line.
function Extras.ParseGain(msg)
	local pattern = AP.Collector.ChatPattern(FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.")
	if not (pattern and type(msg) == "string") then return nil end
	local faction, amount = msg:match(pattern)
	if faction then return faction, tonumber(amount) end
end

-- The faction's data, if the reputation list shows it.
local function FindFaction(name)
	if not (C_Reputation and C_Reputation.GetNumFactions) then return nil end
	for index = 1, Call(C_Reputation.GetNumFactions) or 0 do
		local data = Call(C_Reputation.GetFactionDataByIndex, index)
		if type(data) == "table" and Readable(data.name) == name and not Readable(data.isHeader) then return data end
	end
end

local function RankName(reaction)
	return _G["FACTION_STANDING_LABEL" .. reaction] or ("Rank " .. reaction)
end

--- "Stormwind +25: Honored 4,350 / 12,000, 7,650 to Revered"; just the gain when the faction cannot be found.
function Extras.ReputationLine(faction, amount)
	local head = faction .. " +" .. Extras.Thousands(amount)
	local data = FindFaction(faction)
	if not data then return head end
	local reaction = Readable(data.reaction)
	local bottom, top = Readable(data.currentReactionThreshold), Readable(data.nextReactionThreshold)
	local value = Readable(data.currentStanding)
	if not (reaction and bottom and top and value) or top <= bottom then return head end
	local line = string.format("%s: %s %s / %s", head, RankName(reaction), Extras.Thousands(value - bottom),
		Extras.Thousands(top - bottom))
	local nextName = _G["FACTION_STANDING_LABEL" .. (reaction + 1)]
	if nextName and reaction < 8 then
		line = line .. string.format(", %s to %s", Extras.Thousands(top - value), nextName)
	end
	return line
end

--[[ Level-ups ]]

function Extras.LevelMessages(from, to, secs)
	local time = secs and (" (" .. Extras.Duration(secs) .. ")") or ""
	return "Pathfinder: I just leveled up from " .. from .. " to " .. to .. "!" .. time,
		"Pathfinder: I leveled up from " .. from .. " to " .. to .. "!" .. time
end

local function Send(message, channel)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	return pcall(send, message, channel)
end

--- Announce a level up to `level` where it is ticked. Returns how many went out.
function Extras:AnnounceLevel(level)
	local char = Char()
	if not (char and level) then return 0 end
	local from = level - 1
	local clock = char.lastlevelclock
	local secs = clock and clock.level == from and clock.whole and clock.seconds or nil
	local emote, group = Extras.LevelMessages(from, level, secs)
	local sent = 0
	if char.levelemote ~= false and Send(emote, "EMOTE") then sent = sent + 1 end
	if char.levelparty and IsInGroup() and Send(group, IsInRaid() and "RAID" or "PARTY") then sent = sent + 1 end
	if char.levelguild and IsInGuild() and Send(group, "GUILD") then sent = sent + 1 end
	return sent
end

AP:OnLogin(function()
	AP:On("PLAYER_LEVEL_UP", function(_, level)
		level = Readable(level)
		-- After the collector has put the level's time aside.
		C_Timer.After(0.5, function() Extras:AnnounceLevel(level) end)
	end)
	AP:On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(_, text)
		local char = Char()
		if not (char and char.repdetail) then return end
		local faction, amount = Extras.ParseGain(Readable(text))
		if faction then
			C_Timer.After(REP_DELAY, function() AP:Print(Extras.ReputationLine(faction, amount)) end)
		end
	end)
end)
