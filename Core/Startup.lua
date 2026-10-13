local _, AP = ...
local L = AP.L

--[[
	Slash commands and the key binding's entry point. Loaded last: every
	command reaches a window or module that already exists.

	/apg and /pathfinder. There is deliberately no /aegis -- that belongs to
	another addon in the Aegis suite (the Instance Journal).
]]

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
	next = function()
		local current = AP:GetCurrentStep()
		if current then AP:SetStepDone(current, true) end
	end,
	prev = function()
		local current = AP:GetCurrentStep()
		if current and current > 1 then AP:SetStepDone(current - 1, false) end
	end,
	status = function()
		AP:Print((AP.Collector:IsRunning() and L.COLLECTOR_ON or L.COLLECTOR_OFF) .. ": " .. AP.Collector:StatsText())
	end,
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
