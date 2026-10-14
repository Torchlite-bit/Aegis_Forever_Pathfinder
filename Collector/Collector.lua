local _, AP = ...
local L = AP.L
local Compat = AP.Compat
local Call, Readable = Compat.Call, Compat.Readable

--[[
	The data collector.

	While it runs it writes down what the client will tell an addon about
	leveling on WoW: Forever, merged by quest and by level rather than kept as a
	stream of events, so the saved file stays small and reads straight into the
	tools that will turn it into guides (docs/data-schema.md has every field):

	  levels   the XP each level needs (UnitXPMax), and how long it took
	  quests   per quest id: its text, level and objectives; where it was picked
	           up and handed in (who, map, x/y, the player's level); where its
	           objectives moved on; the client's own map points for it; and what
	           it gave -- XP at each player level, money, items to choose from
	           and items given, spells, currencies and reputation

	Everything is stamped with the client build and the race, class and faction
	that saw it (never the character's name), counted, and merged: a second
	sighting of a quest adds to the first, keeping counts and the lowest and
	highest XP, money and coordinates.

	It only listens while it runs. Nothing is read every frame; the quest log is
	read at most twice a second, after it changes. Values the client withholds
	(secret values, in instances and some fights) are skipped, never stored.
]]

local Collector = {}
AP.Collector = Collector

Collector.SCHEMA_VERSION = 1

local MAX_LOG = 100                -- recent lines kept for the collection window
local MAX_POINTS = 40              -- grid cells kept per objective / map point list
local GRID = 100                   -- coordinates are merged on a 1% grid
local CHAIN_SECONDS = 10           -- a quest offered this soon after a turn-in, by the same NPC, follows it
local TURNIN_SECONDS = 3           -- reputation and XP this soon after a turn-in belong to that quest
local LOG_THROTTLE = 0.5           -- the quest log is read at most this often

local data                          -- AegisPathfinderDB.collect
local listeners = {}

-- Turn-in and pickup in progress, between the quest frame opening and the event that closes it.
local pendingDetail, pendingComplete, lastTurnIn
-- The quest log's objectives as last read: [questID] = { [index] = numFulfilled }
local objectiveCache = {}
local logQueued
-- Reputation values as last read, by faction id, to tell how much a change was.
local repCache = {}

------------------------------------------------------------------------------------------
-- The player's name in quest text
------------------------------------------------------------------------------------------

--[[ The game writes the player's name into some quest text ("You there!
	Genesys, right?"). It stays at home: the text keeps NAME_MARK in its place,
	and the one name that goes out is the credit name. Only a whole name is
	replaced, never one inside a longer word. ]]
Collector.NAME_MARK = "<name>"
local TEXT_FIELDS = { "title", "description", "objectiveText", "progressText", "completionText" }

--- `text` with `name` (default: this character's) replaced by NAME_MARK.
function Collector.Unnamed(text, name)
	if type(text) ~= "string" or text == "" then return text end
	name = name or Call(UnitName, "player")
	if type(name) ~= "string" or #name < 2 then return text end
	local pattern = "()" .. name:gsub("%W", "%%%0") .. "()"
	local out, from = {}, 1
	for first, after in text:gmatch(pattern) do
		local before, next = text:sub(first - 1, first - 1), text:sub(after, after)
		-- Whole names only: no ASCII letter, and no byte of a longer UTF-8 letter, on either side.
		if not before:find("[%a\128-\255]") and not next:find("[%a\128-\255]") then
			out[#out + 1] = text:sub(from, first - 1)
			out[#out + 1] = Collector.NAME_MARK
			from = after
		end
	end
	if from == 1 then return text end
	out[#out + 1] = text:sub(from)
	return table.concat(out)
end

--- Takes this character's name out of every quest text already saved. Returns
--- how many texts changed.
function Collector:ForgetName(name)
	local changed = 0
	for _, quest in pairs(data and data.quests or {}) do
		for _, field in ipairs(TEXT_FIELDS) do
			local text = quest[field]
			local clean = Collector.Unnamed(text, name)
			if clean ~= text then
				quest[field] = clean
				changed = changed + 1
			end
		end
	end
	return changed
end

------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------

local function Changed()
	for _, listener in ipairs(listeners) do pcall(listener) end
end

function Collector:OnChange(listener)
	listeners[#listeners + 1] = listener
end

--[[ A random id for this collection, made once and kept until Clear. Players send
	the same growing file again and again: the tools that merge submissions keep
	only the newest copy of each id, so nothing is counted twice. ]]
local function NewID()
	local parts = {}
	for index = 1, 4 do parts[index] = string.format("%04x", math.random(0, 0xffff)) end
	return string.format("%08x", Compat.Timestamp() % 0x100000000) .. table.concat(parts)
end

local function Fresh()
	return {
		schemaVersion = Collector.SCHEMA_VERSION,
		id = NewID(),
		created = Compat.Timestamp(),
		builds = {},
		observers = {},
		levels = {},
		quests = {},
		log = {},
	}
end

function Collector:Init()
	local global = AP.db.global
	if type(global.collect) ~= "table" then global.collect = Fresh() end
	-- Older schemas migrate here, one version at a time; there is only version 1 so far.
	global.collect.schemaVersion = self.SCHEMA_VERSION
	global.collect.id = global.collect.id or NewID()
	data = global.collect
	for _, key in ipairs({ "builds", "observers", "levels", "quests", "log" }) do
		data[key] = data[key] or {}
	end
end

-- Quest text saved before 0.2.4 can hold this character's name: it comes out once
-- the game knows who is playing, before anything can be sent (the file goes out too).
AP:On("PLAYER_ENTERING_WORLD", function()
	local name = Call(UnitName, "player")
	if data and type(name) == "string" and name ~= "" and name ~= (UNKNOWNOBJECT or "Unknown") then
		Collector:ForgetName(name)
	end
end)

function Collector:GetData()
	return data
end

function Collector:IsRunning()
	return AP.db.char.collecting == true
end

--- Whether this character starts collecting by itself at login: its own
--- choice, or the account's default until it makes one.
function Collector:IsAuto()
	local own = AP.db.char.collectauto
	if own == nil then return AP.db.profile.collectautodefault == true end
	return own == true
end

function Collector:SetAuto(on)
	AP.db.char.collectauto = on and true or false
	-- The last choice made becomes the default for characters that have not made one.
	AP.db.profile.collectautodefault = on and true or false
	Changed()
end

local function Log(text)
	local log = data.log
	log[#log + 1] = date("%H:%M") .. "  " .. text
	while #log > MAX_LOG do table.remove(log, 1) end
	Changed()
end

function Collector:GetLog()
	return data and data.log or {}
end

------------------------------------------------------------------------------------------
-- Stamps and merging
------------------------------------------------------------------------------------------

local stamp       -- { build = "1.60.1.70338", who = "Human:WARRIOR:Alliance" }

local function Stamp()
	if stamp then return stamp end
	local version, build = Compat.Build()
	local player = Compat.Player()
	stamp = {
		build = version .. "." .. build,
		who = (player.race or "?") .. ":" .. (player.class or "?") .. ":" .. (player.faction or "?"),
		faction = player.faction,
		realm = player.realm,
	}
	return stamp
end

local function Note(record)
	local s = Stamp()
	record.builds = record.builds or {}
	record.builds[s.build] = true
	record.by = record.by or {}
	record.by[s.who] = (record.by[s.who] or 0) + 1
	local now = Compat.Timestamp()
	record.first = record.first or now
	record.last = now
end

-- { min, max, count, last } kept for a number seen again and again.
local function Range(range, value)
	if type(value) ~= "number" then return range end
	range = range or {}
	range.min = range.min and math.min(range.min, value) or value
	range.max = range.max and math.max(range.max, value) or value
	range.count = (range.count or 0) + 1
	range.last = value
	return range
end

local function Grid(value)
	return math.floor(value * GRID + 0.5)
end

-- Adds the place to a set of grid cells, { ["mapID:x:y"] = count }, at most MAX_POINTS of them.
local function AddPoint(cells, mapID, x, y)
	if not (mapID and x and y) then return cells end
	cells = cells or {}
	local key = mapID .. ":" .. Grid(x) .. ":" .. Grid(y)
	if cells[key] then
		cells[key] = cells[key] + 1
	else
		local count = 0
		for _ in pairs(cells) do count = count + 1 end
		if count < MAX_POINTS then cells[key] = 1 end
	end
	return cells
end

-- Where the player is, and who they are talking to.
local function Here()
	local place = { zone = Call(GetRealZoneText), subzone = Call(GetSubZoneText), level = Call(UnitLevel, "player") }
	place.mapID, place.x, place.y = Compat.PlayerMapPosition()
	if place.subzone == "" then place.subzone = nil end
	return place
end

-- The quest giver: "npc" names an NPC, and an object's guid when the quest comes from one.
-- When it is a player (a party member sharing the quest), the pickup is "shared": that
-- player's name is theirs, not the quest's, and stays out of the data.
local function Talker()
	local guid, name = Call(UnitGUID, "npc"), Call(UnitName, "npc")
	if not (guid or name) then return nil end
	local kind, id = Compat.ParseGUID(guid)
	if kind == "Player" or Call(UnitIsPlayer, "npc") then return { kind = "shared" } end
	return {
		kind = kind == "GameObject" and "object" or "npc",
		id = id,
		name = name,
	}
end

--[[ Merges one sighting of a pickup or turn-in into the quest's set of them,
	keyed by who (or what) and on which map. Coordinates keep a running mean and
	their extremes; the player's level its range. ]]
local function AddPlace(places, who, place)
	who = who or { kind = "unknown" }
	local key = (who.kind or "unknown") .. ":" .. tostring(who.id or who.name or "?") .. "@" .. tostring(place.mapID or "?")
	local entry = places[key]
	if not entry then
		entry = { kind = who.kind, id = who.id, name = who.name, mapID = place.mapID, zone = place.zone,
			subzone = place.subzone, count = 0 }
		places[key] = entry
	end
	entry.count = entry.count + 1
	entry.name = entry.name or who.name
	entry.subzone = entry.subzone or place.subzone
	if place.x and place.y then
		local n = (entry.xyCount or 0) + 1
		entry.x = Compat.Round(((entry.x or 0) * (n - 1) + place.x) / n)
		entry.y = Compat.Round(((entry.y or 0) * (n - 1) + place.y) / n)
		entry.xyCount = n
		entry.xMin = entry.xMin and math.min(entry.xMin, place.x) or place.x
		entry.xMax = entry.xMax and math.max(entry.xMax, place.x) or place.x
		entry.yMin = entry.yMin and math.min(entry.yMin, place.y) or place.y
		entry.yMax = entry.yMax and math.max(entry.yMax, place.y) or place.y
	end
	entry.playerLevel = Range(entry.playerLevel, place.level)
	return entry
end

local function Quest(questID)
	local quest = data.quests[questID]
	if not quest then
		quest = { seen = {}, pickups = {}, turnins = {}, rewards = {} }
		data.quests[questID] = quest
	end
	return quest
end

local function Count(quest, what)
	quest.seen[what] = (quest.seen[what] or 0) + 1
end

local function Title(quest, questID)
	return quest.title or Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID) or ("#" .. tostring(questID))
end

------------------------------------------------------------------------------------------
-- Rewards on the quest frame
------------------------------------------------------------------------------------------

local function FrameItems(kind, count)
	local items
	for index = 1, count or 0 do
		local link = Call(GetQuestItemLink, kind, index)
		local itemID = Compat.ItemIDFromLink(link)
		if itemID then
			local name, _, amount = Compat.CallAll(GetQuestItemInfo, kind, index)
			items = items or {}
			items[itemID] = { name = name, count = amount or 1 }
		end
	end
	return items
end

-- The rewards the open quest frame shows for `questID`.
local function FrameRewards(questID)
	local rewards = {
		xp = Call(GetRewardXP),
		money = Call(GetRewardMoney),
		choices = FrameItems("choice", Call(GetNumQuestChoices)),
		items = FrameItems("reward", Call(GetNumQuestRewards)),
		title = Call(GetRewardTitle),
		skillPoints = Call(GetRewardSkillPoints),
		honor = Call(GetRewardHonor),
	}
	if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells then
		local spells = Call(C_QuestInfoSystem.GetQuestRewardSpells, questID)
		if type(spells) == "table" and #spells > 0 then
			rewards.spells = {}
			for _, spellID in ipairs(spells) do
				local info = Call(C_QuestInfoSystem.GetQuestRewardSpellInfo, questID, spellID)
				rewards.spells[spellID] = type(info) == "table" and Readable(info.name) or true
			end
		end
	end
	if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
		local currencies = Call(C_QuestInfoSystem.GetQuestRewardCurrencies, questID)
		for _, info in ipairs(type(currencies) == "table" and currencies or {}) do
			local currencyID = Readable(info.currencyID)
			if currencyID then
				rewards.currencies = rewards.currencies or {}
				rewards.currencies[currencyID] = { name = Readable(info.name), amount = Readable(info.totalRewardAmount) }
			end
		end
	end
	return rewards
end

-- Folds what a quest frame offered into the quest's rewards.
local function MergeOffered(quest, offered, playerLevel)
	local rewards = quest.rewards
	if offered.xp and offered.xp > 0 and playerLevel then
		rewards.xpOffered = rewards.xpOffered or {}
		rewards.xpOffered[playerLevel] = offered.xp
	end
	if offered.money and offered.money > 0 then rewards.moneyOffered = offered.money end
	for _, kind in ipairs({ "choices", "items", "spells", "currencies" }) do
		if offered[kind] then
			rewards[kind] = rewards[kind] or {}
			for id, value in pairs(offered[kind]) do rewards[kind][id] = value end
		end
	end
	for _, key in ipairs({ "title", "skillPoints", "honor" }) do
		if offered[key] and offered[key] ~= 0 and offered[key] ~= "" then rewards[key] = offered[key] end
	end
end

------------------------------------------------------------------------------------------
-- Quest events
------------------------------------------------------------------------------------------

-- An NPC, an object or an item offering a quest.
function Collector:QuestDetail(startItemID)
	local questID = Call(GetQuestID)
	if not questID or questID == 0 then return end
	local quest = Quest(questID)
	quest.title = Collector.Unnamed(Call(GetTitleText)) or quest.title
	quest.description = Collector.Unnamed(Call(GetQuestText)) or quest.description
	quest.objectiveText = Collector.Unnamed(Call(GetObjectiveText)) or quest.objectiveText
	startItemID = Readable(startItemID)
	local who = Talker()
	if startItemID and startItemID ~= 0 then
		who = { kind = "item", id = startItemID, name = Call(C_Item and C_Item.GetItemNameByID, startItemID) }
	end
	local here = Here()
	pendingDetail = { questID = questID, who = who, place = here, time = GetTime() }
	MergeOffered(quest, FrameRewards(questID), here.level)
	Count(quest, "offered")

	-- Offered by the same NPC just after handing one in: the next in a chain.
	if lastTurnIn and lastTurnIn.questID ~= questID and GetTime() - lastTurnIn.time <= CHAIN_SECONDS
		and who and lastTurnIn.who and who.id and who.id == lastTurnIn.who.id then
		local before = Quest(lastTurnIn.questID)
		before.chain = before.chain or {}
		before.chain.next = before.chain.next or {}
		before.chain.next[questID] = true
		quest.chain = quest.chain or {}
		quest.chain.prev = quest.chain.prev or {}
		quest.chain.prev[lastTurnIn.questID] = true
	end
	Note(quest)
	Log(string.format(L.LOG_QUEST_OFFERED, Title(quest, questID)))
end

-- What the quest log says about a quest in it.
local function ReadLog(quest, questID)
	if not C_QuestLog then return end
	quest.level = Call(C_QuestLog.GetQuestDifficultyLevel, questID) or quest.level
	local index = Call(C_QuestLog.GetLogIndexForQuestID, questID)
	local info = index and Call(C_QuestLog.GetInfo, index)
	if type(info) == "table" then
		quest.level = Readable(info.level) or quest.level
		quest.suggestedGroup = Readable(info.suggestedGroup)
		if quest.suggestedGroup == 0 then quest.suggestedGroup = nil end
		quest.frequency = Readable(info.frequency)
		quest.title = quest.title or Readable(info.title)
	end
	local tag = Call(C_QuestLog.GetQuestTagInfo, questID)
	if type(tag) == "table" then
		quest.tag = Readable(tag.tagName)
		quest.tagID = Readable(tag.tagID)
	end
	local money = Call(C_QuestLog.GetRequiredMoney, questID)
	if money and money > 0 then quest.requiredMoney = money end
	local objectives = Call(C_QuestLog.GetQuestObjectives, questID)
	if type(objectives) == "table" and #objectives > 0 then
		quest.objectives = quest.objectives or {}
		local cache = {}
		for i, objective in ipairs(objectives) do
			local text = Readable(objective.text)
			quest.objectives[i] = quest.objectives[i] or {}
			local entry = quest.objectives[i]
			-- "Kobold Vermin slain: 3/8" -> "Kobold Vermin slain"
			entry.text = text and (text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":?%s*%d+%s*/%s*%d+%s*$", "")) or entry.text
			entry.type = Readable(objective.type) or entry.type
			entry.required = Readable(objective.numRequired) or entry.required
			cache[i] = Readable(objective.numFulfilled) or 0
		end
		objectiveCache[questID] = objectiveCache[questID] or cache
	end
end

function Collector:QuestAccepted(questID)
	questID = Readable(questID)
	if not questID then return end
	local quest = Quest(questID)
	local detail = pendingDetail and pendingDetail.questID == questID and pendingDetail or nil
	pendingDetail = nil
	local here = detail and detail.place or Here()
	-- No quest frame: shared by a party member, auto-accepted, or started some way the client did not show.
	local who = detail and detail.who or { kind = "auto" }
	AddPlace(quest.pickups, who, here)
	ReadLog(quest, questID)
	quest.title = quest.title or Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
	Count(quest, "accepted")
	Note(quest)
	Log(string.format(L.LOG_QUEST_ACCEPTED, Title(quest, questID)))
end

-- The NPC asking whether you have what they want.
function Collector:QuestProgress()
	local questID = Call(GetQuestID)
	if not questID or questID == 0 then return end
	local quest = Quest(questID)
	quest.progressText = Collector.Unnamed(Call(GetProgressText)) or quest.progressText
end

-- The reward frame at the turn-in NPC.
function Collector:QuestComplete()
	local questID = Call(GetQuestID)
	if not questID or questID == 0 then return end
	local quest = Quest(questID)
	quest.title = Collector.Unnamed(Call(GetTitleText)) or quest.title
	quest.completionText = Collector.Unnamed(Call(GetRewardText)) or quest.completionText
	local here = Here()
	MergeOffered(quest, FrameRewards(questID), here.level)
	pendingComplete = {
		questID = questID, who = Talker(), place = here, time = GetTime(),
		xp = Call(UnitXP, "player"), xpMax = Call(UnitXPMax, "player"), level = here.level,
	}
end

-- What the player chose, from the reward frame's choices.
function Collector:RewardChosen(choice)
	if not (pendingComplete and choice and choice > 0) then return end
	local itemID = Compat.ItemIDFromLink(Call(GetQuestItemLink, "choice", choice))
	if not itemID then return end
	local quest = Quest(pendingComplete.questID)
	quest.rewards.chosen = quest.rewards.chosen or {}
	local s = Stamp()
	local class = s.who:match("^[^:]*:([^:]*)") or "?"
	quest.rewards.chosen[class] = quest.rewards.chosen[class] or {}
	quest.rewards.chosen[class][itemID] = (quest.rewards.chosen[class][itemID] or 0) + 1
end

function Collector:QuestTurnedIn(questID, xpReward, moneyReward)
	questID = Readable(questID)
	if not questID then return end
	local quest = Quest(questID)
	local complete = pendingComplete and pendingComplete.questID == questID and pendingComplete or nil
	pendingComplete = nil
	local here = complete and complete.place or Here()
	local level = complete and complete.level or here.level
	AddPlace(quest.turnins, complete and complete.who or { kind = "auto" }, here)

	-- What the client says the turn-in gave: the XP at this player level, and the money.
	xpReward, moneyReward = Readable(xpReward), Readable(moneyReward)
	local rewards = quest.rewards
	if level and xpReward then
		rewards.xp = rewards.xp or {}
		rewards.xp[level] = Range(rewards.xp[level], xpReward)
	end
	if moneyReward then rewards.money = Range(rewards.money, moneyReward) end

	Count(quest, "turnedIn")
	Note(quest)
	objectiveCache[questID] = nil
	lastTurnIn = { questID = questID, time = GetTime(), who = complete and complete.who, level = level,
		xp = complete and complete.xp, xpMax = complete and complete.xpMax }
	-- The XP bar is read again once it has moved, to check the client's figure.
	C_Timer.After(1, function() Collector:ObserveXP(questID) end)
	Log(string.format(L.LOG_QUEST_TURNED_IN, Title(quest, questID), tostring(xpReward or "?")))
end

--[[ The XP the bar actually moved by, across a level-up if there was one. It
	checks the turn-in's own figure (rested XP does not apply to quests). ]]
function Collector:ObserveXP(questID)
	local turnIn = lastTurnIn
	if not (turnIn and turnIn.questID == questID and turnIn.xp and turnIn.level) then return end
	local level, xp = Call(UnitLevel, "player"), Call(UnitXP, "player")
	if not (level and xp) then return end
	local gained
	if level == turnIn.level then
		gained = xp - turnIn.xp
	elseif level == turnIn.level + 1 and turnIn.xpMax then
		gained = (turnIn.xpMax - turnIn.xp) + xp
	end
	if gained and gained >= 0 then
		local rewards = Quest(questID).rewards
		rewards.xpObserved = rewards.xpObserved or {}
		rewards.xpObserved[turnIn.level] = Range(rewards.xpObserved[turnIn.level], gained)
	end
end

function Collector:QuestRemoved(questID)
	questID = Readable(questID)
	if not questID then return end
	objectiveCache[questID] = nil
	-- Removed without a turn-in just before it: abandoned (or failed).
	C_Timer.After(1, function()
		if lastTurnIn and lastTurnIn.questID == questID and GetTime() - lastTurnIn.time < 5 then return end
		local quest = data.quests[questID]
		if quest then Count(quest, "abandoned") end
	end)
end

------------------------------------------------------------------------------------------
-- Objectives: where they moved on, and the client's own map points
------------------------------------------------------------------------------------------

function Collector:ReadQuestLog()
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
	local mapID, x, y = Compat.PlayerMapPosition()
	local entries = Call(C_QuestLog.GetNumQuestLogEntries) or 0
	for index = 1, entries do
		local info = Call(C_QuestLog.GetInfo, index)
		local questID = type(info) == "table" and not Readable(info.isHeader) and Readable(info.questID)
		if questID and questID ~= 0 then
			local objectives = Call(C_QuestLog.GetQuestObjectives, questID)
			if type(objectives) == "table" then
				local cache = objectiveCache[questID]
				local quest = data.quests[questID] or Quest(questID)
				if not cache then
					-- A quest already in the log when collecting started: its objectives, without a pickup.
					ReadLog(quest, questID)
					cache = objectiveCache[questID] or {}
					objectiveCache[questID] = cache
				end
				for i, objective in ipairs(objectives) do
					local now = Readable(objective.numFulfilled) or 0
					if now > (cache[i] or 0) and mapID and x then
						quest.progress = quest.progress or {}
						quest.progress[i] = AddPoint(quest.progress[i], mapID, x, y)
						Log(string.format(L.LOG_QUEST_PROGRESS, Readable(objective.text) or Title(quest, questID)))
					end
					cache[i] = now
				end
			end
		end
	end
	self:ReadMapPoints(mapID)
end

--[[ The client's own map points for quests in the log, on the map the player
	is on: where it sends the player for the objectives, and for the turn-in once
	they are done. Kept apart from what was observed (quest.poi). ]]
function Collector:ReadMapPoints(mapID)
	if not (mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
	local points = Call(C_QuestLog.GetQuestsOnMap, mapID)
	if type(points) ~= "table" then return end
	for _, point in ipairs(points) do
		local questID, x, y = Readable(point.questID), Readable(point.x), Readable(point.y)
		if questID and x and y and data.quests[questID] then
			local quest = data.quests[questID]
			local ready = Call(C_QuestLog.ReadyForTurnIn, questID)
			local which = ready and "turnin" or "objective"
			quest.poi = quest.poi or {}
			quest.poi[which] = AddPoint(quest.poi[which], mapID, x, y)
		end
	end
end

-- Quests the client marks as available to pick up on this map ("!" on the world map).
function Collector:ReadAvailable()
	if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return end
	local mapID = Compat.PlayerMapPosition()
	if not mapID then return end
	local lines = Call(C_QuestLine.GetAvailableQuestLines, mapID)
	if type(lines) ~= "table" then return end
	for _, line in ipairs(lines) do
		local questID, x, y = Readable(line.questID), Readable(line.x), Readable(line.y)
		if questID and x and y then
			local quest = Quest(questID)
			quest.title = quest.title or Readable(line.questName)
			quest.questLine = Readable(line.questLineName) or quest.questLine
			quest.poi = quest.poi or {}
			quest.poi.available = AddPoint(quest.poi.available, Readable(line.startMapID) or mapID, x, y)
		end
	end
end

function Collector:RequestAvailable()
	if not (C_QuestLine and C_QuestLine.RequestQuestLinesForMap) then return end
	local mapID = Compat.PlayerMapPosition()
	if mapID then pcall(C_QuestLine.RequestQuestLinesForMap, mapID) end
end

local function QueueLogRead()
	if logQueued then return end
	logQueued = true
	C_Timer.After(LOG_THROTTLE, function()
		logQueued = nil
		if Collector:IsRunning() then Collector:ReadQuestLog() end
	end)
end

------------------------------------------------------------------------------------------
-- Reputation
------------------------------------------------------------------------------------------

local function ReputationOf(factionID)
	local info = Call(C_Reputation and C_Reputation.GetFactionDataByID, factionID)
	if type(info) ~= "table" then return nil end
	return Readable(info.currentStanding), Readable(info.name)
end

-- Every faction the reputation list shows now, so the next change has a "before".
function Collector:ReadReputations()
	if not (C_Reputation and C_Reputation.GetNumFactions) then return end
	for index = 1, Call(C_Reputation.GetNumFactions) or 0 do
		local info = Call(C_Reputation.GetFactionDataByIndex, index)
		if type(info) == "table" and Readable(info.factionID) and not Readable(info.isHeader) then
			repCache[info.factionID] = Readable(info.currentStanding)
		end
	end
end

-- The gains already counted for the last turn-in, by faction name: the id event
-- and the chat line both report one gain, and it is counted once.
local repCounted = {}

local function AddReputation(name, factionID, amount)
	if not (lastTurnIn and GetTime() - lastTurnIn.time <= TURNIN_SECONDS) then return end
	if not (name and amount) or amount == 0 then return end
	local quest = Quest(lastTurnIn.questID)
	quest.rewards.reputation = quest.rewards.reputation or {}
	local entry = quest.rewards.reputation[name] or {}
	quest.rewards.reputation[name] = entry
	entry.factionID = entry.factionID or factionID
	if repCounted.turnIn ~= lastTurnIn then repCounted = { turnIn = lastTurnIn } end
	if repCounted[name] then return end
	repCounted[name] = true
	Range(entry, amount)
	Log(string.format(L.LOG_REPUTATION, name, amount, Title(quest, lastTurnIn.questID)))
end

-- The client's change event, by faction id: how much is the new value less the last read.
function Collector:FactionChanged(factionID)
	factionID = Readable(factionID)
	if not factionID then return end
	local value, name = ReputationOf(factionID)
	local before = repCache[factionID]
	repCache[factionID] = value
	if value and before then AddReputation(name, factionID, value - before) end
end

--[[ A client chat template as a pattern, up to its number: "Reputation with
	%s increased by %d." -> "^Reputation with (.+) increased by (%d+)". What
	follows the number (a bonus in brackets) is left unmatched. ]]
function Collector.ChatPattern(template)
	if type(template) ~= "string" then return nil end
	local cut = template:find("%d", 1, true)
	if not cut then return nil end
	local head = template:sub(1, cut + 1)
	local pattern = head:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. pattern
end

-- "Reputation with Stormwind increased by 250." -- the same, from the chat line.
local repPatterns
function Collector:ReputationMessage(text)
	text = Readable(text)
	if type(text) ~= "string" then return end
	if not repPatterns then
		repPatterns = {}
		for _, name in ipairs({ "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_ACH_BONUS",
			"FACTION_STANDING_INCREASED_BONUS", "FACTION_STANDING_INCREASED_DOUBLE_BONUS",
			"FACTION_STANDING_DECREASED" }) do
			local pattern = Collector.ChatPattern(_G[name])
			if pattern then
				repPatterns[#repPatterns + 1] = { pattern, name == "FACTION_STANDING_DECREASED" and -1 or 1 }
			end
		end
		if #repPatterns == 0 then repPatterns[1] = { "^Reputation with (.+) increased by (%d+)", 1 } end
	end
	for _, entry in ipairs(repPatterns) do
		local faction, amount = text:match(entry[1])
		if faction and tonumber(amount) then
			AddReputation(faction, nil, tonumber(amount) * entry[2])
			return
		end
	end
end

------------------------------------------------------------------------------------------
-- Levels
------------------------------------------------------------------------------------------

--[[ The XP the level needs, every time it is seen (the same on every
	character, so the range shows if anything disagrees), and how long a level
	took when the collector saw all of it. ]]
-- What each level needed when last noted this session: XP gained does not note it again.
local levelNoted = {}

function Collector:NoteLevel()
	local level, xpMax = Call(UnitLevel, "player"), Call(UnitXPMax, "player")
	if not (level and xpMax and xpMax > 0) or levelNoted[level] == xpMax then return end
	levelNoted[level] = xpMax
	local entry = data.levels[level] or {}
	data.levels[level] = entry
	local before = entry.xpMax and entry.xpMax.last
	entry.xpMax = Range(entry.xpMax, xpMax)
	Note(entry)
	if before ~= xpMax then Log(string.format(L.LOG_LEVEL, level, tostring(xpMax))) end
end

-- Time at a level, per character: seconds counted while collecting, and
-- whether the whole level was seen.
local function Clock()
	local clock = AP.db.char.levelclock
	local level = Call(UnitLevel, "player")
	if not clock or clock.level ~= level then
		clock = { level = level, seconds = 0, whole = false }
		AP.db.char.levelclock = clock
	end
	return clock
end

local clockMark

-- Adds the time since the clock started to the level it was started at.
local function ClockStop()
	if not clockMark then return end
	local clock = AP.db.char.levelclock
	if clock then clock.seconds = clock.seconds + (GetTime() - clockMark) end
	clockMark = nil
end

local function ClockStart()
	if clockMark then return end
	Clock()
	clockMark = GetTime()
end

function Collector:LevelUp(newLevel)
	newLevel = Readable(newLevel)
	ClockStop()
	local clock = AP.db.char.levelclock
	-- Kept for the level-up announcement (Extras.lua), which reads it after this.
	AP.db.char.lastlevelclock = clock and { level = clock.level, seconds = clock.seconds, whole = clock.whole } or nil
	if clock and clock.level and newLevel and clock.level == newLevel - 1 and clock.whole then
		local entry = data.levels[clock.level] or {}
		data.levels[clock.level] = entry
		entry.seconds = Range(entry.seconds, math.floor(clock.seconds + 0.5))
	end
	-- The new level is seen from its start. UnitLevel may still answer the old
	-- level during this event, so the clock is set from the event's own.
	AP.db.char.levelclock = { level = newLevel, seconds = 0, whole = true }
	if self:IsRunning() then clockMark = GetTime() end
	-- UnitXPMax answers for the new level a moment later.
	C_Timer.After(1, function() if Collector:IsRunning() then Collector:NoteLevel() end end)
end

------------------------------------------------------------------------------------------
-- Starting and stopping
------------------------------------------------------------------------------------------

local HANDLERS = {
	QUEST_DETAIL = function(_, startItemID) Collector:QuestDetail(startItemID) end,
	QUEST_ACCEPTED = function(_, questID) Collector:QuestAccepted(questID) end,
	QUEST_PROGRESS = function() Collector:QuestProgress() end,
	QUEST_COMPLETE = function() Collector:QuestComplete() end,
	QUEST_TURNED_IN = function(_, questID, xp, money) Collector:QuestTurnedIn(questID, xp, money) end,
	QUEST_REMOVED = function(_, questID) Collector:QuestRemoved(questID) end,
	QUEST_LOG_UPDATE = QueueLogRead,
	QUEST_WATCH_UPDATE = QueueLogRead,
	QUEST_LOG_CRITERIA_UPDATE = QueueLogRead,
	QUESTLINE_UPDATE = function() Collector:ReadAvailable() end,
	ZONE_CHANGED_NEW_AREA = function() Collector:RequestAvailable() end,
	PLAYER_LEVEL_UP = function(_, level) Collector:LevelUp(level) end,
	PLAYER_XP_UPDATE = function() Collector:NoteLevel() end,
	FACTION_STANDING_CHANGED = function(_, factionID) Collector:FactionChanged(factionID) end,
	CHAT_MSG_COMBAT_FACTION_CHANGE = function(_, text) Collector:ReputationMessage(text) end,
	PLAYER_LOGOUT = function() ClockStop() end,
}

local function Guarded(handler)
	return function(...)
		local ok, err = pcall(handler, ...)
		if not ok and data then Log("|cffff4040" .. tostring(err) .. "|r") end
	end
end
local guarded = {}
for event, handler in pairs(HANDLERS) do guarded[event] = Guarded(handler) end

local listening = false
local function Listen(on)
	if on == listening then return end
	listening = on
	for event, handler in pairs(guarded) do
		if on then AP:On(event, handler) else AP:Off(event, handler) end
	end
end

-- The reward choice is only known as the client is told it.
local hooked = false
local function HookRewardChoice()
	if hooked or type(GetQuestReward) ~= "function" then return end
	hooked = true
	hooksecurefunc("GetQuestReward", function(choice)
		if Collector:IsRunning() then pcall(Collector.RewardChosen, Collector, Readable(choice)) end
	end)
end

function Collector:Start(quiet)
	AP.db.char.collecting = true
	Listen(true)
	HookRewardChoice()
	Stamp()
	data.builds[stamp.build] = true
	data.observers[stamp.who] = (data.observers[stamp.who] or 0) + 1
	self:ReadReputations()
	self:NoteLevel()
	self:ReadQuestLog()
	self:RequestAvailable()
	ClockStart()
	if not quiet then AP:Print(L.COLLECTOR_STARTED) end
	Changed()
end

function Collector:Stop()
	AP.db.char.collecting = false
	Listen(false)
	ClockStop()
	-- A level the collector did not see all of has no time worth keeping.
	local clock = AP.db.char.levelclock
	if clock then clock.whole = false end
	pendingDetail, pendingComplete = nil, nil
	AP:Print(L.COLLECTOR_STOPPED)
	Changed()
end

function Collector:Toggle()
	if self:IsRunning() then self:Stop() else self:Start() end
end

--- Forget everything collected, on every character; the switches stay.
function Collector:Clear()
	local global = AP.db.global
	global.collect = Fresh()
	data = global.collect
	objectiveCache, repCache, levelNoted = {}, {}, {}
	lastTurnIn, pendingDetail, pendingComplete = nil, nil, nil
	if self:IsRunning() then
		data.builds[Stamp().build] = true
		self:ReadReputations()
		self:NoteLevel()
	end
	AP:Print(L.COLLECTOR_CLEARED)
	Changed()
end

local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

--- "16 quests, 3 turned in, 1 level": the counts, as every window says them.
function Collector:StatsText()
	local counts = self:Counts()
	return string.format(L.COLLECTOR_STATS, Plural(counts.quests, "quest"), counts.turnedIn, Plural(counts.levels, "level"))
end

--- What the collection window shows: quests seen, turned in, levels, and in the log now.
function Collector:Counts()
	local counts = { quests = 0, turnedIn = 0, levels = 0, pickups = 0, rewards = 0 }
	if not data then return counts end
	for _, quest in pairs(data.quests) do
		counts.quests = counts.quests + 1
		if (quest.seen.turnedIn or 0) > 0 then counts.turnedIn = counts.turnedIn + 1 end
		if next(quest.pickups) then counts.pickups = counts.pickups + 1 end
	end
	for _ in pairs(data.levels) do counts.levels = counts.levels + 1 end
	return counts
end

AP:OnInit(function() Collector:Init() end)

AP:OnLogin(function()
	-- Running when the character logged out, or set to start by itself: it runs.
	if Collector:IsRunning() or Collector:IsAuto() then
		Collector:Start(true)
	else
		-- The time at this level is not all seen any more.
		local clock = AP.db.char.levelclock
		if clock then clock.whole = false end
	end
end)
