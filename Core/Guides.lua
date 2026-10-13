local _, AP = ...
local Compat = AP.Compat

--[[
	Guides: where they register, and the little engine that follows one.

	No guide ships yet. This is the seam they will plug into, kept small and
	documented (docs/guide-api.md) so the first guide written from collected data
	needs no change here:

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
]]

AP.guides = {}
AP.guidelist = {}

AP.CATEGORIES = {
	{ key = "leveling", label = "Leveling", glyph = "book" },
	{ key = "dungeons", label = "Dungeons", glyph = "medal" },
	{ key = "class", label = "Class Quests", glyph = "star" },
	{ key = "professions", label = "Professions", glyph = "gear" },
	{ key = "favorites", label = "Favorites", glyph = "heart" },
}

local VALID_ACTION = {}
for action in pairs(AP.Theme.actionIconByName) do VALID_ACTION[action] = true end

--- Add a guide. Returns true, or false and why not.
function AP:RegisterGuide(def)
	if type(def) ~= "table" or type(def.name) ~= "string" or type(def.steps) ~= "table" then
		return false, "a guide needs a name and a list of steps"
	end
	for index, step in ipairs(def.steps) do
		if not VALID_ACTION[step.action] then
			return false, string.format("%s, step %d: unknown action %s", def.name, index, tostring(step.action))
		end
	end
	if not self.guides[def.name] then self.guidelist[#self.guidelist + 1] = def.name end
	def.category = def.category or "leveling"
	def.faction = def.faction or "Both"
	self.guides[def.name] = def
	if self.RefreshGuideBrowser then self:RefreshGuideBrowser() end
	return true
end

function AP:HasGuides()
	return #self.guidelist > 0
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

--- The step you are on: the first not yet done.
function AP:GetCurrentStep()
	local guide = self:GetCurrentGuide()
	if not guide then return nil end
	for index, step in ipairs(guide.steps) do
		if not self:IsStepDone(guide.name, index) then return index, step end
	end
	return #guide.steps + 1, nil
end

-- Whether the client already says a step is done.
local function Satisfied(step)
	local qid = step.qid
	if not qid or not C_QuestLog then return false end
	if Compat.Call(C_QuestLog.IsQuestFlaggedCompleted, qid) then return true end
	if step.action == "ACCEPT" then
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
		for index, step in ipairs(guide.steps) do
			if Satisfied(step) then progress[guide.name][index] = true end
		end
	end
	self:GuideChanged()
end

--- Whoever draws the guide hears about every change here.
function AP:GuideChanged()
	local _, step = self:GetCurrentStep()
	self:PointAt(step)
	if self.RefreshObjectivePanel then self:RefreshObjectivePanel() end
end

--[[ The waypoint: the client's own map pin and arrow (C_Map user waypoints,
	super-tracked), the one navigation every Forever player already has. ]]
function AP:PointAt(step)
	if not (step and step.map and step.x and step.y) then return end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
	if self.db.char.waypoints == false then return end
	local can = Compat.Call(C_Map.CanSetUserWaypointOnMap, step.map)
	if can == false then return end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y))
	if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
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
		for index, step in ipairs(guide.steps) do
			if step.qid == questID then done[guide.name][index] = true end
		end
	end
	AP:ScanGuide()
end

AP:OnLogin(function()
	AP:On("QUEST_ACCEPTED", OnQuestEvent)
	AP:On("QUEST_TURNED_IN", OnQuestEvent)
	AP:On("QUEST_REMOVED", OnQuestEvent)
	AP:On("QUEST_LOG_UPDATE", function()
		-- The log changes often; the guide is scanned at most twice a second.
		if AP.scanQueued or not AP:GetCurrentGuide() then return end
		AP.scanQueued = true
		C_Timer.After(0.5, function()
			AP.scanQueued = nil
			AP:ScanGuide()
		end)
	end)
	if AP:GetCurrentGuide() then AP:ScanGuide() end
end)
