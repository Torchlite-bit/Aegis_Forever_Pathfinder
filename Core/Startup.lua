local _, AP = ...
local L = AP.L
local Compat = AP.Compat

--[[
	Slash commands and the key binding's entry point. Loaded last: every
	command reaches a window or module that already exists.

	/apg and /pathfinder. There is deliberately no /aegis -- that belongs to
	another addon in the Aegis suite (the Instance Journal).
]]

--[[ /apg flights: Forever's maps and flight masters, saved for writing routes.

	Every map under Azeroth's world map: its name, kind, parent, size in yards
	and where it lies on its continent; and every flight master the client knows
	on each zone (C_TaxiMap.GetTaxiNodesForMap: all of them, either faction, with
	their faction). Saved in AegisPathfinderDB.atlas; a /reload writes it to disk,
	where the guides' routes are worked out from it. ]]
local CONTINENT, ZONE = 2, 3
-- Classic's ids, tried when the top can't be found from where you stand.
local KNOWN_TOPS = { 947, 1414, 1415 }

-- The top of the map tree above the map you stand on (the world, or the cosmos).
local function TopMap()
	local mapID = Compat.Call(C_Map.GetBestMapForUnit, "player")
	local top
	for _ = 1, 12 do
		if type(mapID) ~= "number" or mapID == 0 then break end
		top = mapID
		local info = Compat.Call(C_Map.GetMapInfo, mapID)
		mapID = info and Compat.Readable(info.parentMapID)
	end
	return top
end

-- Every map under `top`, all levels: nil when the client lists none.
local function Descendants(top)
	local ok, list = pcall(C_Map.GetMapChildrenInfo, top, nil, true)
	if ok and type(list) == "table" and #list > 0 then return list end
end

function AP:SaveAtlas()
	if not (C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapInfo) then
		return self:Print("This client can't list its maps.")
	end
	local maps, flights, count = {}, {}, 0
	-- From the top above you; else each known top, merged.
	local top, children = TopMap(), nil
	if top then children = Descendants(top) end
	if not children then
		children = {}
		local seen = {}
		for _, id in ipairs(KNOWN_TOPS) do
			for _, info in ipairs(Descendants(id) or {}) do
				local mapID = Compat.Readable(info.mapID)
				if mapID and not seen[mapID] then
					seen[mapID] = true
					children[#children + 1] = info
				end
			end
		end
	end
	if #children == 0 then
		return self:Print(string.format("This client listed no maps (top map %s). Nothing saved.", tostring(top)))
	end
	-- The continents themselves too, for their own flight masters.
	for _, id in ipairs({ 1414, 1415 }) do
		local info = Compat.Call(C_Map.GetMapInfo, id)
		if info then children[#children + 1] = info end
	end
	-- Each map's continent: the first continent above it.
	local function ContinentOf(mapID)
		for _ = 1, 10 do
			local info = Compat.Call(C_Map.GetMapInfo, mapID)
			if not info then return nil end
			if Compat.Readable(info.mapType) == CONTINENT then return mapID end
			mapID = Compat.Readable(info.parentMapID)
			if not mapID or mapID == 0 then return nil end
		end
	end
	for _, info in ipairs(children) do
		local id = Compat.Readable(info.mapID)
		if type(id) == "number" then
			local entry = { name = Compat.Readable(info.name), type = Compat.Readable(info.mapType),
				parent = Compat.Readable(info.parentMapID) }
			local w, h = Compat.CallAll(C_Map.GetMapWorldSize, id)
			if type(w) == "number" and w > 0 then entry.yards = { w, h } end
			local continent = ContinentOf(id)
			if continent and continent ~= id then
				local left, right, top, bottom = Compat.CallAll(C_Map.GetMapRectOnMap, id, continent)
				if type(left) == "number" then entry.continent, entry.rect = continent, { left, right, top, bottom } end
			end
			maps[id] = entry
			if (entry.type == ZONE or entry.type == CONTINENT) and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
				local okNodes, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, id)
				if okNodes and type(nodes) == "table" and #nodes > 0 then
					local list = {}
					for _, node in ipairs(nodes) do
						local x, y
						if node.position and node.position.GetXY then x, y = node.position:GetXY() end
						list[#list + 1] = { id = Compat.Readable(node.nodeID), name = Compat.Readable(node.name),
							faction = Compat.Readable(node.faction), x = Compat.Readable(x), y = Compat.Readable(y),
							undiscovered = Compat.Readable(node.isUndiscovered) }
						count = count + 1
					end
					flights[id] = list
				end
			end
		end
	end
	AegisPathfinderDB.atlas = { taken = GetServerTime and GetServerTime() or 0, version = self.version,
		faction = Compat.Call(UnitFactionGroup, "player"), maps = maps, flights = flights }
	local n = 0
	for _ in pairs(maps) do n = n + 1 end
	self:Print(string.format("Saved %d maps and %d flight masters (from map %s). Type /reload to write them to disk.",
		n, count, tostring(top)))
end

--- /apg mouse: three seconds later, which frames have the mouse, top first. For a
--- button that doesn't take a click where it should: only the game knows that.
function AP:ReportMouse()
	self:Print(L.MOUSE_WAIT)
	C_Timer.After(3, function()
		local foci = {}
		if GetMouseFoci then
			foci = GetMouseFoci() or {}
		elseif GetMouseFocus and GetMouseFocus() then
			foci = { GetMouseFocus() }
		end
		if #foci == 0 then
			AP:Print(L.MOUSE_NOTHING)
			return
		end
		for i, f in ipairs(foci) do
			if i > 3 then break end
			local ok, name = pcall(function() return f:GetDebugName() end)
			if not (ok and name and name ~= "") then name = f:GetName() or "?" end
			AP:Print(("%d. %s (%s, level %s)"):format(i, name, tostring(f:GetFrameStrata()), tostring(f:GetFrameLevel())))
		end
	end)
end

local COMMANDS = {
	[""] = function() AP:ToggleObjectivePanel() end,
	collect = function() AP:ToggleCollectorFrame() end,
	start = function() if not AP.Collector:IsRunning() then AP.Collector:Start() end end,
	stop = function() if AP.Collector:IsRunning() then AP.Collector:Stop() end end,
	submit = function() AP:ShowSubmit() end,
	export = function() AP:ShowSubmit() end,
	config = function() AP:ToggleConfigPanel() end,
	options = function() AP:ToggleConfigPanel() end,
	browser = function() AP:ToggleGuideBrowser() end,
	guides = function() AP:ToggleGuideBrowser() end,
	resetpanels = function() AP:ResetWindowLayout() end,
	minimapbutton = function() AP:ToggleMinimapButton() end,
	next = function() AP:StepForward() end,
	prev = function() AP:StepBack() end,
	status = function()
		AP:Print((AP.Collector:IsRunning() and L.COLLECTOR_ON or L.COLLECTOR_OFF) .. ": " .. AP.Collector:StatsText())
	end,
	mouse = function() AP:ReportMouse() end,
	flights = function() AP:SaveAtlas() end,
	arrow = function() AP:ToggleNavArrow() end,
	chattest = function() AP.Extras:ChatTest() end,
	help = function() AP:Print(L.SLASH_HELP) end,
}

SLASH_AEGISPATHFINDER1 = "/apg"
SLASH_AEGISPATHFINDER2 = "/pathfinder"
SlashCmdList.AEGISPATHFINDER = function(message)
	local command = strtrim(message or ""):match("^(%S*)"):lower()
	local run = COMMANDS[command]
	if run then run() else AP:Print(L.SLASH_HELP) end
end

-- The key binding (Bindings.xml).
BINDING_HEADER_AEGISPATHFINDER = L.TITLE
BINDING_NAME_AEGISPATHFINDER_TOGGLE = "Show or hide the guide"
BINDING_NAME_AEGISPATHFINDER_COLLECT = "Data collection window"

function AegisPathfinder_Toggle() AP:ToggleObjectivePanel() end
function AegisPathfinder_Collect() AP:ToggleCollectorFrame() end
