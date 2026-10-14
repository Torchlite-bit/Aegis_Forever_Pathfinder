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

	This client won't let an addon post an emote without a click ("ADDON
	BLOCKED: UNKNOWN()", even with none of its restrictions on), and nothing
	while chat is locked down (boss fights, rated PvP). Party, raid and guild
	chat goes out by itself (/apg chattest, 2026-10-14; raid and guild are taken to
	work the same, and fall back to a button if not). So a level-up
	tells your party and guild at once, as the Turtle addon did, once any fight
	is over; and brings a small card with a button for the emote (and for
	anything the client blocked), which a click sends.
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

--- From a click (see the top of this file), or from /apg chattest trying without one.
local function Send(message, channel)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	return pcall(send, message, channel)
end

local function ChatLocked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Call(C_ChatInfo.InChatMessagingLockdown) == true
end

--[[ What /apg chattest found on Forever (2026-10-14): an addon's emote is blocked
	without a click even with no restriction on, while party chat goes out by
	itself. Raid and guild chat are taken to be the same kind (seen only by your
	own group or guild), not yet seen; when the client blocks one, it goes on the
	card as a button instead. The emote stays a button. ]]
local BY_ITSELF = { PARTY = true, RAID = true, GUILD = true }

local blockedNow          -- false while a send with no click is being tried; true once blocked
--- Send with no click. False when the client blocks it (it says so at once) or chat is locked.
local function TrySend(message, channel)
	if ChatLocked() then return false end
	blockedNow = false
	local ok = Send(message, channel)
	local fine = ok and not blockedNow
	blockedNow = nil
	return fine
end
Extras.TrySend = TrySend

--- Where a level up to `level` can be told now, as ticked: { { label, channel, message } }.
function Extras:LevelChoices(level)
	local char = Char()
	if not (char and level) then return {} end
	local from = level - 1
	local clock = char.lastlevelclock
	local secs = clock and clock.level == from and clock.whole and clock.seconds or nil
	local emote, group = Extras.LevelMessages(from, level, secs)
	local out = {}
	if char.levelemote ~= false then out[#out + 1] = { label = "Emote", channel = "EMOTE", message = emote } end
	if char.levelparty and IsInGroup() then
		out[#out + 1] = IsInRaid() and { label = "Raid", channel = "RAID", message = group }
			or { label = "Party", channel = "PARTY", message = group }
	end
	if char.levelguild and IsInGuild() then out[#out + 1] = { label = "Guild", channel = "GUILD", message = group } end
	return out, secs
end

--[[ The level-up card: "Level 23!", how long the last level took, and a button
	for each place to tell. It goes by itself after a minute. ]]
local CARD_SECONDS = 60
local card

local function BuildCard()
	local Theme = AP.Theme
	card = CreateFrame("Frame", "AegisPathfinderLevelUp", UIParent)
	card:SetFrameStrata("DIALOG")
	card:SetSize(300, 96)
	card:SetPoint("TOP", UIParent, "TOP", 0, -150)
	card:EnableMouse(true)
	Theme:Panel(card, "panel")
	local m = Theme.metrics
	card.title = card:CreateFontString(nil, "OVERLAY")
	Theme:TextColor(card.title, "accent")
	card.note = Theme:FinePrint(card, 300 - 24 - m.left - m.right)
	card.note:SetJustifyH("CENTER")
	if Theme:IsBlizzard() then
		-- In the metal top bar, as the game's own windows have their names; the note below it.
		Theme:SetFont(card.title, "display", 14)
		card.title:SetPoint("TOP", card, "TOP", 0, -4)
		card.note:SetPoint("TOP", card, "TOP", 0, -m.header - 8)
	else
		Theme:SetFont(card.title, "display", 16)
		card.title:SetPoint("TOP", card, "TOP", 0, -10 - m.top)
		card.note:SetPoint("TOP", card.title, "BOTTOM", 0, -4)
	end
	card.close = Theme:CloseChip(card, card)
	card.close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4 - m.right, -4 - m.top)
	card.buttons = {}
	for index = 1, 3 do
		local b = Theme:PanelButton(card, "", 84, 22)
		b:SetScript("OnClick", function(self)
			if ChatLocked() then
				AP:Print("Chat is locked for addons right now (a boss fight or rated PvP): try again after it.")
				return
			end
			Send(self.message, self.channel)
			self:Disable()
			self.sent = true
			for _, other in ipairs(card.buttons) do
				if other:IsShown() and not other.sent then return end
			end
			card:Hide()
		end)
		card.buttons[index] = b
	end
	tinsert(UISpecialFrames, "AegisPathfinderLevelUp")
	card:Hide()
end

--- Offers to tell others about a level up to `level` (`choices`: those still to send;
--- every ticked place when nil). Returns how many buttons the card has.
function Extras:OfferAnnouncement(level, choices, secs)
	if not choices then choices, secs = self:LevelChoices(level) end
	if #choices == 0 then return 0 end
	if not card then BuildCard() end
	card.level = level
	card.title:SetText("Level " .. level .. "!")
	card.note:SetText((secs and ("Level " .. (level - 1) .. " took " .. Extras.Duration(secs) .. ". ") or "")
		.. "Tell others?")
	local width = #choices * 84 + (#choices - 1) * 8
	for index, b in ipairs(card.buttons) do
		local choice = choices[index]
		b:ClearAllPoints()
		if choice then
			b:SetPoint("BOTTOMLEFT", card, "BOTTOM", -width / 2 + (index - 1) * 92, 12 + AP.Theme.metrics.bottom)
			b:SetText(choice.label)
			b.channel, b.message, b.sent = choice.channel, choice.message, nil
			b:Enable()
		end
		b:SetShown(choice ~= nil)
	end
	card:Show()
	C_Timer.After(CARD_SECONDS, function()
		if card.level == level then card:Hide() end
	end)
	return #choices
end

--[[ /apg chattest: can a level-up go to chat by itself? Two seconds after the
	command (so not from the key press), the level-up line, marked as a test,
	goes to Emote, and to Party/Raid and Guild where there's one. Each is then
	reported: posted (it came back in chat), blocked (the client said so), or
	not seen. Nothing is kept. ]]
local TEST_EVENTS = {
	CHAT_MSG_EMOTE = "EMOTE", CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
	CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID", CHAT_MSG_GUILD = "GUILD",
}
local LABELS = { EMOTE = "Emote", PARTY = "Party", RAID = "Raid", GUILD = "Guild" }

-- The client's addon restrictions (C_RestrictedActions, as on retail since Midnight),
-- by Enum.AddOnRestrictionType's values where the client has none of its own.
local RESTRICTIONS = { { "Combat", 0 }, { "Encounter", 1 }, { "ChallengeMode", 2 }, { "PvPMatch", 3 },
	{ "Map", 4 }, { "Chat", 5 } }

--- Which addon restrictions are on now, in plain words: "Combat, Chat (starting)", or "none".
function Extras.RestrictionsNow()
	local on = {}
	local get = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
	local types = Enum and Enum.AddOnRestrictionType
	for _, r in ipairs(RESTRICTIONS) do
		local value = types and types[r[1]] or r[2]
		local state = Call(get, value)
		if state == 2 then on[#on + 1] = r[1]
		elseif state == 1 then on[#on + 1] = r[1] .. " (starting)" end
	end
	if Call(InCombatLockdown) then on[#on + 1] = "in combat" end
	if ChatLocked() then on[#on + 1] = "chat lockdown" end
	if not get then on[#on + 1] = "(this client can't say)" end
	return #on > 0 and table.concat(on, ", ") or "none"
end

function Extras:ChatTest()
	local channels = { "EMOTE" }
	if IsInGroup() then channels[#channels + 1] = IsInRaid() and "RAID" or "PARTY" end
	if IsInGuild() then channels[#channels + 1] = "GUILD" end
	local level = Readable(UnitLevel("player")) or 2
	local _, line = Extras.LevelMessages(level - 1, level, 4 * 3600 + 28 * 60)
	line = line .. " (a test)"
	local result, sending, restricted, changes = {}, nil, nil, {}
	local function OnBlocked() if sending then result[sending] = "blocked" end end
	-- A restriction that switches on or off during the test, as the client announces it.
	local function OnRestriction(_, kind, state)
		changes[#changes + 1] = tostring(Readable(kind)) .. "=" .. tostring(Readable(state))
	end
	local function OnChat(event, text)
		local channel = TEST_EVENTS[event]
		text = Readable(text)
		if channel and type(text) == "string" and text:find("(a test)", 1, true) and not result[channel] then
			result[channel] = "posted"
		end
	end
	AP:On("ADDON_ACTION_BLOCKED", OnBlocked)
	AP:On("ADDON_ACTION_FORBIDDEN", OnBlocked)
	AP:On("ADDON_RESTRICTION_STATE_CHANGED", OnRestriction)
	for event in pairs(TEST_EVENTS) do AP:On(event, OnChat) end
	local names = {}
	for _, channel in ipairs(channels) do names[#names + 1] = LABELS[channel] end
	AP:Print("Chat test: in 2 seconds, one test line goes to " .. table.concat(names, ", ") .. ", with no click.")
	C_Timer.After(2, function()
		restricted = Extras.RestrictionsNow()
		for _, channel in ipairs(channels) do
			sending = channel
			local ok, err = Send(line, channel)
			if not ok and not result[channel] then result[channel] = "error: " .. tostring(err) end
			sending = nil
		end
	end)
	C_Timer.After(6, function()
		AP:Off("ADDON_ACTION_BLOCKED", OnBlocked)
		AP:Off("ADDON_ACTION_FORBIDDEN", OnBlocked)
		AP:Off("ADDON_RESTRICTION_STATE_CHANGED", OnRestriction)
		for event in pairs(TEST_EVENTS) do AP:Off(event, OnChat) end
		for _, channel in ipairs(channels) do
			AP:Print("Chat test, " .. LABELS[channel] .. ": " .. (result[channel] or "not seen in chat"))
		end
		AP:Print("Chat test, restrictions on as it sent: " .. tostring(restricted))
		AP:Print("Chat test, restrictions now: " .. Extras.RestrictionsNow()
			.. (#changes > 0 and (" (changed meanwhile: " .. table.concat(changes, " ") .. ")") or ""))
	end)
end

--- A level up to `level`: party, raid and guild are told at once (after the fight, if
--- you're in one); what the client won't send by itself, the emote always, goes on the card.
function Extras:AnnounceLevel(level)
	local choices, secs = self:LevelChoices(level)
	if #choices == 0 then return end
	local function Go()
		local left = {}
		for _, choice in ipairs(choices) do
			if not (BY_ITSELF[choice.channel] and TrySend(choice.message, choice.channel)) then
				left[#left + 1] = choice
			end
		end
		self:OfferAnnouncement(level, left, secs)
	end
	if not Call(InCombatLockdown) then return Go() end
	local function AfterFight()
		AP:Off("PLAYER_REGEN_ENABLED", AfterFight)
		Go()
	end
	AP:On("PLAYER_REGEN_ENABLED", AfterFight)
end

AP:OnLogin(function()
	AP:On("ADDON_ACTION_BLOCKED", function()
		if blockedNow == false then blockedNow = true end
	end)
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
