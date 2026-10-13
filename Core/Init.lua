local addonName, AP = ...
local L = AP.L

--[[
	The namespace every file shares, and the one global it is published as
	(AegisPathfinder, for /dump and for the key binding). The saved variables,
	the events and the start-up order live here.

	Saved variables:
	  AegisPathfinderDB       account-wide. `profile` holds the look and the
	                          windows (as the 1.12 addon's AceDB profile did),
	                          `collect` holds what the collector has written.
	  AegisPathfinderCharDB   per character: the switches the 1.12 addon kept
	                          in its `char` table.
]]

AegisPathfinder = AP
AP.name = addonName
AP.title = L.TITLE
AP.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "0.2.0"
AP.media = "Interface\\AddOns\\" .. addonName .. "\\media\\"

AP.PROFILE_DEFAULTS = {
	theme = "pathfinder",
	windowscale = 1,
	switchcolours = "theme",
	objframeopacity = 0.5,
	browseropacity = 1,
	steptextsize = 1,
	showprogress = true,
	minimapangle = 215,
}

AP.CHAR_DEFAULTS = {
	panelopen = true,
	overviewmode = false,
	showminimapbutton = true,
	chatmessages = true,
	-- Automation. With no guide to say which quests are its own, "all quests" is the default.
	autoquest = false,
	allquests = true,
	autogossip = true,
	sellbutton = true,
	autosell = false,
	autorepair = "off",
	-- Extras
	repdetail = false,
	levelemote = true,
	levelparty = false,
	levelguild = false,
}

local function Fill(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then target[key] = value end
	end
	return target
end

--[[ Events.

	One frame hears every event and hands it to whoever asked. A listener that
	errors is reported through the client's error handler and does not stop the
	others hearing the same event.
]]
local eventFrame = CreateFrame("Frame")
local listeners = {}

local function Dispatch(event, ...)
	local list = listeners[event]
	if not list then return end
	for index = 1, #list do
		local ok, err = pcall(list[index], event, ...)
		if not ok then geterrorhandler()(err) end
	end
end
eventFrame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)

--- Call `fn(event, ...)` on `event`. An event the client does not have is skipped.
function AP:On(event, fn)
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then return false end
	end
	list[#list + 1] = fn
	return true
end

--- Stop calling `fn` on `event`.
function AP:Off(event, fn)
	local list = listeners[event]
	if not list then return end
	for index = #list, 1, -1 do
		if list[index] == fn then table.remove(list, index) end
	end
	if #list == 0 then
		listeners[event] = nil
		pcall(eventFrame.UnregisterEvent, eventFrame, event)
	end
end

-- Start-up: what runs once the saved variables are in, and what runs at login.
local onInit, onLogin = {}, {}
function AP:OnInit(fn) onInit[#onInit + 1] = fn end
function AP:OnLogin(fn) onLogin[#onLogin + 1] = fn end

local function RunAll(list)
	for index = 1, #list do
		local ok, err = pcall(list[index])
		if not ok then geterrorhandler()(err) end
	end
end

AP:On("ADDON_LOADED", function(_, loaded)
	if loaded ~= addonName then return end
	AegisPathfinderDB = AegisPathfinderDB or {}
	AegisPathfinderCharDB = AegisPathfinderCharDB or {}
	local db = AegisPathfinderDB
	db.profile = Fill(db.profile or {}, AP.PROFILE_DEFAULTS)
	AP.db = { profile = db.profile, char = Fill(AegisPathfinderCharDB, AP.CHAR_DEFAULTS), global = db }
	RunAll(onInit)
end)

AP:On("PLAYER_LOGIN", function()
	RunAll(onLogin)
	if AP.db.char.chatmessages ~= false then
		AP:Print(string.format(L.LOADED, AP.title, AP.version))
	end
end)

--[[ Chat ]]

function AP:Print(message)
	local code = self.Theme and self.Theme:Code("accent") or "|cff52c722"
	DEFAULT_CHAT_FRAME:AddMessage(code .. L.SHORT .. ":|r " .. tostring(message))
end

--- A routine line -- a quest handed in, greys sold -- left out while "Show
--- Pathfinder chat messages" is off. Errors and replies to what the player
--- typed use Print and always show.
function AP:Say(message)
	if self.db and self.db.char.chatmessages == false then return end
	self:Print(message)
end
