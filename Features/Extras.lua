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

	This client lets an addon post in chat only from a click, and not at all
	while chat is locked down (boss fights, rated PvP). Posting by itself, as
	the Turtle addon did, is blocked ("ADDON BLOCKED: UNKNOWN()"). So a
	level-up brings a small card with a button for each place ticked, and a
	click sends it.
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

--- Only ever from a click (see the top of this file).
local function Send(message, channel)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	return pcall(send, message, channel)
end

local function ChatLocked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Call(C_ChatInfo.InChatMessagingLockdown) == true
end

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

--- Offers to tell others about a level up to `level`. Returns how many buttons the card has.
function Extras:OfferAnnouncement(level)
	local choices, secs = self:LevelChoices(level)
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

AP:OnLogin(function()
	AP:On("PLAYER_LEVEL_UP", function(_, level)
		level = Readable(level)
		-- After the collector has put the level's time aside.
		C_Timer.After(0.5, function() Extras:OfferAnnouncement(level) end)
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
