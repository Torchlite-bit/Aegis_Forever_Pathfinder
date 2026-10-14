local _, AP = ...
local Compat = AP.Compat

--[[
	Guides: where they register, and the little engine that follows one.

	Guides live in Guides\ (the first, a short test guide for Northshire, is
	written from collected data). This is the seam they plug into, kept small
	and documented (docs/guide-api.md):

	  AegisPathfinder:RegisterGuide({
	      name = "Elwynn Forest (1-10)",   -- unique, shown on tabs and in the browser
	      category = "leveling",           -- a key of AP.CATEGORIES
	      faction = "Alliance",            -- "Alliance", "Horde" or "Both"
	      minLevel = 1, maxLevel = 10,
	      next = "Westfall (10-20)",       -- the guide offered when this one ends
	      steps = {
	          { action = "ACCEPT", qid = 176, title = "Wanted: Hogger", npc = 823,
	            map = 1429, x = 0.4237, y = 0.6587, note = "On the post by the inn." },
	          { action = "COMPLETE", qid = 176, title = "Wanted: Hogger" },
	          { action = "TURNIN", qid = 176, title = "Wanted: Hogger" },
	          { action = "RUN", title = "Westfall", map = 1436, x = 0.5, y = 0.5 },
	      },
	  })

	Actions are the 1.12 addon's (Theme.actionIconByName). ACCEPT, COMPLETE and
	TURNIN tick themselves from the quest events; the rest are ticked by hand.

	A step can be for some characters only: class = { "WARLOCK" } (UnitClass's
	second return) and race = { "Human" } (UnitRace's second return; an Undead's
	is "Scourge"). Everyone else never sees it: it is left out of the current
	step, the list, the counts and the arrows. Progress stays keyed by the
	step's index in the guide.

	Steps done together: together = true joins a step to the one before it, so
	a kill area's quests (and the book a kobold drops) show as one block, each
	with its live progress, and each still ticks itself. fromitem = true on an
	ACCEPT says its quest starts from a looted item: the step ticks as soon as
	that item is in the bags.

	Pick-ups and travel: a LOOT step with item = "<name>" ticks once an item of
	that name is in the bags (a library book). A RUN, FLY, BOAT, HEARTH or MAP
	step ticks once you are within TRAVEL_ARRIVE yards of its place. A
	GETFLIGHTPOINT step with node = <taxi node id> ticks once the client says
	you know that flight point.

	Kill areas: once you are within ARRIVE yards of the place of a block with a
	COMPLETE, KILL or GRIND step, the pin and Pathfinder's arrow stop marking it
	(the mobs are all around you). A later step of the block more than NEAR
	yards away is marked again. The arrival is saved per character.
]]

AP.guides = {}
AP.guidelist = {}

AP.CATEGORIES = {
	{ key = "leveling", label = "Leveling", glyph = "book" },
	{ key = "dungeons", label = "Dungeons", glyph = "medal" },
	{ key = "class", label = "Class Quests", glyph = "star" },
	{ key = "professions", label = "Professions", glyph = "gear" },
	{ key = "collections", label = "Collections", glyph = "book" },
	{ key = "favorites", label = "Favorites", glyph = "heart" },
}

local VALID_ACTION = {}
for action in pairs(AP.Theme.actionIconByName) do VALID_ACTION[action] = true end

-- The tokens a step's `class` and `race` lists may hold.
local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
	SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
local RACES = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Orc = true, Scourge = true,
	Tauren = true, Troll = true }

-- The first token in a list that isn't a known one (or the list itself, when it isn't one).
local function BadToken(list, known)
	if list == nil then return nil end
	if type(list) ~= "table" or next(list) == nil then return tostring(list) end
	for _, token in ipairs(list) do
		if not known[token] then return tostring(token) end
	end
end

-- Whether a step's list lets this character in: no list, a list naming them,
-- or a character the client can't name yet.
local function Allowed(list, token)
	if not list or not token then return true end
	for _, value in ipairs(list) do
		if value == token then return true end
	end
	return false
end

local BADGE_KIND = { dungeons = "dg", class = "cl", professions = "pf", collections = "co" }

--- The badge a guide of `category` wears: "xp" for leveling.
function AP:BadgeKind(category)
	return BADGE_KIND[category] or "xp"
end

--- Add a guide. Returns true, or false and why not.
function AP:RegisterGuide(def)
	if type(def) ~= "table" or type(def.name) ~= "string" or type(def.steps) ~= "table" then
		return false, "a guide needs a name and a list of steps"
	end
	for index, step in ipairs(def.steps) do
		if not VALID_ACTION[step.action] then
			return false, string.format("%s, step %d: unknown action %s", def.name, index, tostring(step.action))
		end
		if type(step.class) == "string" then step.class = { step.class } end
		if type(step.race) == "string" then step.race = { step.race } end
		local bad = BadToken(step.class, CLASSES) or BadToken(step.race, RACES)
		if bad then
			return false, string.format("%s, step %d: unknown class or race %s", def.name, index, bad)
		end
		if step.together and index == 1 then
			return false, string.format("%s, step 1: together needs a step before it", def.name)
		end
	end
	if not self.guides[def.name] then self.guidelist[#self.guidelist + 1] = def.name end
	def.category = def.category or "leveling"
	def.faction = def.faction or "Both"
	self.guides[def.name] = def
	if self.RefreshGuideBrowser then self:RefreshGuideBrowser() end
	return true
end

--- Whether there is a guide for this character (the browser lists only their faction's).
function AP:HasGuides()
	return #self:GetGuides(nil) > 0
end

--- The guides for the player's faction in a category ("favorites" reads the
--- character's starred guides), sorted by level.
function AP:GetGuides(category)
	local faction = Compat.Call(UnitFactionGroup, "player")
	local favorites = self.db and self.db.char.favorites or {}
	local list = {}
	for _, name in ipairs(self.guidelist) do
		local guide = self.guides[name]
		local mine = guide.faction == "Both" or guide.faction == faction or not faction
		local wanted = category == nil or guide.category == category or (category == "favorites" and favorites[name])
		if mine and wanted then list[#list + 1] = guide end
	end
	table.sort(list, function(a, b)
		if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
		return a.name < b.name
	end)
	return list
end

--[[ Following a guide ]]

local function Progress()
	local char = AP.db.char
	char.progress = char.progress or {}
	return char.progress
end

function AP:GetCurrentGuide()
	local name = self.db and self.db.char.currentguide
	return name and self.guides[name] or nil
end

--- Open a guide, at the first step not yet done.
function AP:LoadGuide(name)
	if not self.guides[name] then return false end
	self.db.char.currentguide = name
	local recent = self.db.char.recentguides or {}
	for index = #recent, 1, -1 do
		if recent[index] == name then table.remove(recent, index) end
	end
	table.insert(recent, 1, name)
	while #recent > 8 do table.remove(recent) end
	self.db.char.recentguides = recent
	self:ScanGuide()
	return true
end

function AP:UnloadGuide()
	self.db.char.currentguide = nil
	self:GuideChanged()
end

--- The steps of a guide that are for this character, in order: their indices in guide.steps.
function AP:GuideSteps(guide)
	local _, class = Compat.CallAll(UnitClass, "player")
	local _, race = Compat.CallAll(UnitRace, "player")
	local mine = {}
	for index, step in ipairs(guide.steps) do
		if Allowed(step.class, class) and Allowed(step.race, race) then mine[#mine + 1] = index end
	end
	return mine
end

function AP:IsStepDone(guideName, index)
	local done = Progress()[guideName]
	return done and done[index] == true
end

function AP:SetStepDone(index, done, guideName)
	guideName = guideName or self.db.char.currentguide
	if not guideName then return end
	local progress = Progress()
	progress[guideName] = progress[guideName] or {}
	progress[guideName][index] = done and true or nil
	self:GuideChanged()
end

--- The step you are on: the first of yours not yet done. Returns its index in
--- guide.steps and the step, then its place among your steps and how many you have.
--- Once all are done: past the end, no step.
function AP:GetCurrentStep()
	local guide = self:GetCurrentGuide()
	if not guide then return nil end
	local mine = self:GuideSteps(guide)
	for position, index in ipairs(mine) do
		if not self:IsStepDone(guide.name, index) then return index, guide.steps[index], position, #mine end
	end
	return #guide.steps + 1, nil, #mine + 1, #mine
end

--- The → arrow and /apg next: tick the step you are on.
function AP:StepForward()
	local index, step = self:GetCurrentStep()
	if step then self:SetStepDone(index, true) end
end

--- The ← arrow and /apg prev: untick the step of yours before the one you are on.
function AP:StepBack()
	local guide = self:GetCurrentGuide()
	if not guide then return end
	local _, _, position = self:GetCurrentStep()
	local previous = self:GuideSteps(guide)[position - 1]
	if previous then self:SetStepDone(previous, false) end
end

--[[ Steps done together ]]

-- The first step of the block `index` is in. Blocks are worked out over the whole
-- guide, so a step for another class can't join an earlier, unrelated block.
local function BlockHead(guide, index)
	while index > 1 and guide.steps[index] and guide.steps[index].together do index = index - 1 end
	return index
end

--- The block you are on: your steps in it (their indices, in order) and its first
--- step's index. Nothing past the end of the guide.
function AP:GetCurrentBlock()
	local guide = self:GetCurrentGuide()
	if not guide then return nil end
	local index, step = self:GetCurrentStep()
	if not step then return nil end
	local head, members = BlockHead(guide, index), {}
	for _, i in ipairs(self:GuideSteps(guide)) do
		if i >= head and BlockHead(guide, i) == head then members[#members + 1] = i end
	end
	return members, head
end

local AREA = { COMPLETE = true, KILL = true, GRIND = true }

--- Whether a block (indices in `guide`) is a kill or collect area.
function AP:IsAreaBlock(guide, members)
	for _, i in ipairs(members or {}) do
		if AREA[guide.steps[i].action] then return true end
	end
	return false
end

-- "Kobold Vermin slain: 3/10" or "3/10 Kobold Vermin slain" -> "Kobold Vermin slain".
local function ObjectiveLabel(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":?%s*%d+%s*/%s*%d+%s*$", "")
	return text ~= "" and text or nil
end

--- A quest's objectives as the log has them now: { { label =, have =, need = } }, or
--- nil when the quest isn't in the log. `fallback` names an objective with no text.
function AP:QuestProgress(questID, fallback)
	if not (questID and C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	if Compat.Call(C_QuestLog.IsOnQuest, questID) ~= true then return nil end
	local objectives = Compat.Call(C_QuestLog.GetQuestObjectives, questID)
	if type(objectives) ~= "table" then return nil end
	local out = {}
	for _, objective in ipairs(objectives) do
		local need = Compat.Readable(objective.numRequired)
		if type(need) == "number" and need > 0 then
			out[#out + 1] = { label = ObjectiveLabel(Compat.Readable(objective.text)) or fallback,
				have = math.min(Compat.Readable(objective.numFulfilled) or 0, need), need = need }
		end
	end
	return out
end

-- Whether the client already says a step is done.
-- Whether a bag item starts quest `questID` (a kobold's chewed book). The client says
-- which quest an item starts, so its name or id needn't be known.
local function HoldsQuestItem(questID)
	if not (C_Container and C_Container.GetContainerItemQuestInfo) then return false end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
		for slot = 1, Compat.Call(C_Container.GetContainerNumSlots, bag) or 0 do
			local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
			if ok and type(info) == "table" and Compat.Readable(info.questID) == questID then return true end
		end
	end
	return false
end

-- Whether an item named `name` is in the bags.
local function HoldsItemNamed(name)
	if not (C_Container and C_Container.GetContainerItemInfo) then return false end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
		for slot = 1, Compat.Call(C_Container.GetContainerNumSlots, bag) or 0 do
			local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
			if ok and type(info) == "table" then
				local held = Compat.Readable(info.itemName)
				if type(held) ~= "string" then
					local link = Compat.Readable(info.hyperlink)
					held = type(link) == "string" and link:match("%[(.-)%]") or nil
				end
				if held == name then return true end
			end
		end
	end
	return false
end

-- Whether the client says you know flight point `node` on `map`.
local function KnowsFlightPoint(map, node)
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and map) then return false end
	local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, map)
	if not (ok and type(nodes) == "table") then return false end
	for _, info in ipairs(nodes) do
		if Compat.Readable(info.nodeID) == node then return Compat.Readable(info.isUndiscovered) == false end
	end
	return false
end

local TRAVEL = { RUN = true, FLY = true, BOAT = true, HEARTH = true, MAP = true }

--- Whether a step ticks without a click: a quest step with its quest, a pick-up
--- with its item, a flight point with its node, a trip with its place.
function AP:TicksItself(step)
	if step.item then return true end
	if step.action == "GETFLIGHTPOINT" then return step.node ~= nil end
	if TRAVEL[step.action] then return step.map ~= nil end
	return step.qid ~= nil and (step.action == "ACCEPT" or step.action == "TURNIN" or step.action == "COMPLETE")
end

local function Satisfied(step)
	if step.item and HoldsItemNamed(step.item) then return true end
	if step.action == "GETFLIGHTPOINT" and step.node and KnowsFlightPoint(step.map, step.node) then return true end
	local qid = step.qid
	if not qid or not C_QuestLog then return false end
	if Compat.Call(C_QuestLog.IsQuestFlaggedCompleted, qid) then return true end
	if step.action == "ACCEPT" then
		if step.fromitem and HoldsQuestItem(qid) then return true end
		return Compat.Call(C_QuestLog.IsOnQuest, qid) == true
	elseif step.action == "COMPLETE" then
		return Compat.Call(C_QuestLog.ReadyForTurnIn, qid) == true or Compat.Call(C_QuestLog.IsComplete, qid) == true
	end
	return false
end

--- Tick every step the client already says is done.
function AP:ScanGuide()
	local guide = self:GetCurrentGuide()
	if guide then
		local progress = Progress()
		progress[guide.name] = progress[guide.name] or {}
		for _, index in ipairs(self:GuideSteps(guide)) do
			if Satisfied(guide.steps[index]) then progress[guide.name][index] = true end
		end
	end
	self:GuideChanged()
end

--- Whoever draws the guide hears about every change here.
function AP:GuideChanged()
	self:WatchArrival()
	local index, step = self:GetCurrentStep()
	self:PointAt(step, index)
	if self.RefreshObjectivePanel then self:RefreshObjectivePanel() end
	if self.RefreshNavArrow then self:RefreshNavArrow() end
end

--[[ Where a place is from you ]]

-- Both points on one map: the place's, or the first map above it that has you on it.
local function OneMap(t)
	local map, tx, ty = t.map, t.x, t.y
	for _ = 1, 8 do
		local px, py = Compat.PlayerPositionOn(map)
		if px then return map, tx, ty, px, py end
		if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapRectOnMap) then return nil end
		local ok, info = pcall(C_Map.GetMapInfo, map)
		local parent = ok and info and Compat.Readable(info.parentMapID)
		if type(parent) ~= "number" or parent == 0 then return nil end
		local left, right, top, bottom = Compat.CallAll(C_Map.GetMapRectOnMap, t.map, parent)
		if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number"
			or type(bottom) ~= "number" then
			return nil
		end
		map, tx, ty = parent, left + t.x * (right - left), top + t.y * (bottom - top)
	end
end

--- How far a place ({ map, x, y }) is from you, east and south, in yards (in map
--- widths when the map's size is unknown: then `sized` is false). Nothing when the
--- client gives no position for you.
function AP:OffsetTo(t)
	local map, tx, ty, px, py = OneMap(t)
	if not map then return nil end
	local w, h = Compat.CallAll(C_Map.GetMapWorldSize, map)
	local sized = type(w) == "number" and type(h) == "number" and w > 0 and h > 0
	if not sized then w, h = 1, 1 end
	return (tx - px) * w, (ty - py) * h, sized
end

-- Yards between two places on one map; nil when they're on different maps or its size is unknown.
local function Apart(a, b)
	if a.map ~= b.map then return nil end
	local w, h = Compat.CallAll(C_Map.GetMapWorldSize, a.map)
	if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
	local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
	return math.sqrt(dx * dx + dy * dy)
end

--[[ Arriving in a kill area ]]

local ARRIVE = 60          -- yards: you're in the area
local TRAVEL_ARRIVE = 40   -- yards: a trip's end (a flight master, an inn, a dock) reached
local NEAR = 100           -- yards: a later step of the block this close is in the same area
local watch = 0            -- the arrival check's generation; a newer one ends the old

--- Whether the step you are on is in a kill area you have arrived in: nothing marks it.
function AP:InArrivedArea(step)
	local saved = self.db and self.db.char.arrived
	if not (saved and step and step.map and step.x and step.y) then return false end
	local guide = self:GetCurrentGuide()
	local _, head = self:GetCurrentBlock()
	if not (guide and saved.guide == guide.name and saved.block == head) then return false end
	local yards = Apart(saved, step)
	return yards ~= nil and yards <= NEAR
end

--- Check, once a second while it matters, whether you have reached the kill area
--- the guide is marking. It runs whatever the arrow or pin switches say.
function AP:WatchArrival()
	watch = watch + 1
	local gen, char, guide = watch, self.db.char, self:GetCurrentGuide()
	local members, head = self:GetCurrentBlock()
	local saved = char.arrived
	if saved and not (guide and saved.guide == guide.name and saved.block == head) then
		char.arrived = nil
	end
	local index, step = self:GetCurrentStep()
	-- A trip ticks once you get there.
	if step and TRAVEL[step.action] and step.map and step.x and step.y then
		local trip = { map = step.map, x = step.x, y = step.y }
		local function Arrived(fromTimer)
			if gen ~= watch then return end
			local dx, dy, sized = self:OffsetTo(trip)
			if dx and sized and math.sqrt(dx * dx + dy * dy) <= TRAVEL_ARRIVE then
				return self:SetStepDone(index, true)
			end
			C_Timer.After(1, function() Arrived(true) end)
		end
		return Arrived(false)
	end
	if not members or not self:IsAreaBlock(guide, members) then return end
	if not (step and step.map and step.x and step.y) or self:InArrivedArea(step) then return end
	local place = { map = step.map, x = step.x, y = step.y }
	local function Check(fromTimer)
		if gen ~= watch then return end
		local dx, dy, sized = self:OffsetTo(place)
		if dx and sized and math.sqrt(dx * dx + dy * dy) <= ARRIVE then
			char.arrived = { guide = guide.name, block = head, map = place.map, x = place.x, y = place.y }
			if fromTimer then self:GuideChanged() end
			return
		end
		C_Timer.After(1, function() Check(true) end)
	end
	Check(false)
end

--[[ The waypoint: the client's own map pin and arrow (C_Map user waypoints,
	super-tracked), the one navigation every Forever player already has. Set
	once as a step becomes current, not on every scan, so a quest the player
	tracks in between keeps the arrow. Which step that was is saved, so a
	/reload on the same step leaves the pin and the arrow as they are. A step
	with no place, the guide's end, closing the guide or switching waypoints
	off takes our pin away -- only while it is still ours. ]]
local pointed   -- { step =, map =, x =, y = }: the pin we put down

local function ClearOurPin()
	if AP.db then AP.db.char.pointed = nil end
	if not pointed then return end
	local mine = pointed
	pointed = nil
	if not (C_Map and C_Map.ClearUserWaypoint) then return end
	local pin = Compat.Call(C_Map.GetUserWaypoint)
	if pin and pin.uiMapID == mine.map and pin.position and math.abs((pin.position.x or 0) - mine.x) < 0.002
		and math.abs((pin.position.y or 0) - mine.y) < 0.002 then
		pcall(C_Map.ClearUserWaypoint)
	end
end

--- Put the step's pin down. `index`: the step's index in the current guide.
function AP:PointAt(step, index)
	local char = self.db.char
	if char.waypoints == false or self:InArrivedArea(step) then return ClearOurPin() end
	if pointed and pointed.step == step then return end
	if not (step and step.map and step.x and step.y) then return ClearOurPin() end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
	local saved = char.pointed
	if not pointed and saved and saved.guide == char.currentguide and saved.index == index
		and Compat.Call(C_Map.GetUserWaypoint) then
		-- A /reload on the step we pointed at: its pin (or one the player put down since) is still there.
		pointed = { step = step, map = step.map, x = step.x, y = step.y }
		return
	end
	if Compat.Call(C_Map.CanSetUserWaypointOnMap, step.map) == false then return ClearOurPin() end
	local ok, wasSet = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y))
	if not ok or wasSet == false then return ClearOurPin() end
	pointed = { step = step, map = step.map, x = step.x, y = step.y }
	char.pointed = { guide = char.currentguide, index = index }
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
end

-- The client's completed-quest flags can lag a turn-in by a moment, so the
-- event's own quest id ticks that quest's steps at once.
local function OnQuestEvent(event, questID)
	local guide = AP:GetCurrentGuide()
	if not guide then return end
	questID = Compat.Readable(questID)
	if event == "QUEST_TURNED_IN" and questID then
		local done = Progress()
		done[guide.name] = done[guide.name] or {}
		for _, index in ipairs(AP:GuideSteps(guide)) do
			if guide.steps[index].qid == questID then done[guide.name][index] = true end
		end
	end
	AP:ScanGuide()
end

AP:OnLogin(function()
	AP:On("QUEST_ACCEPTED", OnQuestEvent)
	AP:On("QUEST_TURNED_IN", OnQuestEvent)
	AP:On("QUEST_REMOVED", OnQuestEvent)
	-- The log and the bags change often; the guide is scanned at most twice a second.
	local function QueueScan()
		if AP.scanQueued or not AP:GetCurrentGuide() then return end
		AP.scanQueued = true
		C_Timer.After(0.5, function()
			AP.scanQueued = nil
			AP:ScanGuide()
		end)
	end
	AP:On("QUEST_LOG_UPDATE", QueueScan)
	AP:On("BAG_UPDATE_DELAYED", QueueScan)
	AP:On("TAXIMAP_OPENED", QueueScan)
	if AP:GetCurrentGuide() then AP:ScanGuide() end
end)
