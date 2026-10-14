local _, AP = ...
local L = AP.L

--[[
	Slash commands and the key binding's entry point. Loaded last: every
	command reaches a window or module that already exists.

	/apg and /pathfinder. There is deliberately no /aegis -- that belongs to
	another addon in the Aegis suite (the Instance Journal).
]]

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
