local _, AP = ...
local Theme = AP.Theme

--[[
	MinimapButton.lua -- the button on the minimap's edge.

	The Aegis: Pathfinder logo in its own colours, the accent ring round it on
	hover; in the Blizzard skin, the gold tracking ring every minimap button
	wears. Click shows or hides the guide, right-click opens the options,
	shift-click the data collection window, and dragging walks it round the
	minimap's edge. The Appearance page (or /apg minimapbutton) hides it.
]]

local SIZE = 26
local RADIUS = 80           -- from the minimap's centre, where its buttons sit
local DEFAULT_ANGLE = 215   -- degrees anticlockwise from east: lower left

local button

local function Place(angle)
	local r = math.rad(angle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * RADIUS, math.sin(r) * RADIUS)
end

local function Dragging()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	AP.db.profile.minimapangle = angle
	Place(angle)
end

local function Build()
	button = CreateFrame("Button", "AegisPathfinderMinimapButton", Minimap)
	AP.minimapbutton = button
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:EnableMouse(true)
	button:SetMovable(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:Hide()

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(Theme.texture.minimapLogo)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)

	local ring = button:CreateTexture(nil, "OVERLAY")
	if Theme:IsBlizzard() then
		-- Blizzard's own minimap button: a dark disc, the icon, the gold tracking ring.
		button:SetSize(31, 31)
		local bg = button:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture(Theme.blizzardArt.minimapBg)
		bg:SetSize(20, 20)
		bg:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
		icon:SetSize(20, 20)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
		local border = button:CreateTexture(nil, "OVERLAY")
		border:SetTexture(Theme.blizzardArt.minimapBorder)
		border:SetSize(53, 53)
		border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
		button:SetHighlightTexture(Theme.blizzardArt.minimapHighlight)
		ring:Hide()
	else
		icon:SetSize(SIZE, SIZE)
		ring:SetTexture(Theme.texture.circleBorder)
		ring:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
		ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
		Theme:Tint(ring, "accent")
		ring:Hide()
	end
	button.ring, button.icon = ring, icon

	button:SetScript("OnDragStart", function(self)
		Theme:HideTip(self)
		self:SetScript("OnUpdate", Dragging)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			AP:ToggleConfigPanel()
		elseif IsShiftKeyDown() then
			AP:ToggleCollectorFrame()
		else
			AP:ToggleObjectivePanel()
		end
	end)
	local x, y = 0, 0
	button:SetScript("OnMouseDown", function()
		local point, rel, relPoint
		point, rel, relPoint, x, y = icon:GetPoint()
		icon:SetPoint(point, rel, relPoint, x + 1, y - 1)
	end)
	button:SetScript("OnMouseUp", function()
		local point, rel, relPoint = icon:GetPoint()
		icon:SetPoint(point, rel, relPoint, x, y)
	end)
	button:SetScript("OnEnter", function(self)
		if not Theme:IsBlizzard() then ring:Show() end
		Theme:ShowTip(self, "LEFT", AP.title .. " v" .. (AP.version or "?"), {
			AP.Collector:IsRunning() and "|cff52c722Collecting data|r" or "Not collecting data",
			"Click to show or hide the guide",
			"Shift-click for data collection",
			"Right-click for settings",
			"Drag to move this button",
		})
	end)
	button:SetScript("OnLeave", function(self)
		ring:Hide()
		Theme:HideTip(self)
	end)
end

--- Show or hide the button to match the setting, where it was left.
function AP:UpdateMinimapButton()
	if not button then return end
	Place(self.db.profile.minimapangle or DEFAULT_ANGLE)
	button:SetShown(self.db.char.showminimapbutton ~= false)
end

function AP:ToggleMinimapButton()
	self.db.char.showminimapbutton = self.db.char.showminimapbutton == false
	self:UpdateMinimapButton()
	self:RefreshConfigPanel()
end

AP:OnInit(Build)
AP:OnLogin(function() AP:UpdateMinimapButton() end)
