local _, AP = ...
local L = AP.L
local Theme = AP.Theme
local Compat = AP.Compat

--[[ NavArrow.lua -- Pathfinder's arrow, as the Turtle addon's nav callout.

	An arrow that turns to point at the current step's place, what to do there
	under it, and how far it is and about how long it takes under that. No
	panel behind it: it floats on the game world, so every line is shadowed to
	stay readable over snow or a lit doorway. Drag it anywhere; its place is
	saved like a window's, and Reset windows puts it back.

	The sums, from the client's own source (Blizzard_QuestNavigation,
	Blizzard_HybridMinimap):
	  * map x grows east and y grows south; C_Map.GetMapWorldSize gives a map's
	    size in yards, so the step's offset in yards is (dx, dy) * size;
	  * GetPlayerFacing is in radians from north, turning left adds;
	  * Texture:SetRotation turns the art left for a positive angle, and the
	    art points up at rest. So the arrow's angle is the place's bearing
	    from north, measured the same way, minus the way you face.
	When the step's map hasn't got you on it, both points are lifted onto the
	first map above it that has (C_Map.GetMapRectOnMap), up to the continent.

	It shows with the guide window, while the step you are on has a place,
	and hides with it, so "Hide the guide in combat" and "in dungeons" hide it
	too. Where the client gives no position (inside Forever's dungeons) the
	arrow and its words hide, and the frame lets the mouse through; without a
	facing it still says how far.
]]

local ARROW = 40          -- the arrow's box
local WIDTH = 200
local TICK = 0.1          -- seconds between updates
local HERE = 8            -- yards: close enough to say you're there
local RUN_SPEED = 7       -- yards a second, running, when the client won't say
-- Top middle, above where Settings opens (its top is 180 down) and the game's red error lines.
local DEFAULT_POINT = { "TOP", "TOP", 0, -40 }
local SCALE_MIN, SCALE_MAX = 0.6, 1.6

local frame
local target              -- { map =, x =, y =, action = }: the step pointed at

local function Char() return AP.db.char end
local function Profile() return AP.db.profile end

--- Whether the player wants the arrow (on unless switched off).
function AP:IsNavArrowOn()
	return self.db ~= nil and Char().navarrow ~= false
end

--[[ The sums ]]

--- Where the step's place is from you: the arrow's angle (nil without a facing)
--- and the yards (nil when the map's size is unknown). Nothing at all when the
--- client gives no position for you. AP:OffsetTo (Core/Guides.lua) measures.
function AP:NavArrowBearing(t)
	t = t or target
	if not t then return nil end
	local dx, dy, sized = self:OffsetTo(t)               -- east, south
	if not dx then return nil end
	local yards = sized and math.sqrt(dx * dx + dy * dy) or nil
	local facing = Compat.Call(GetPlayerFacing)
	local angle
	if type(facing) == "number" then angle = math.atan2(-dx, -dy) - facing end
	return angle, yards, true
end

--- "1:05": minutes and seconds.
function AP.FormatEta(seconds)
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Your running pace in yards a second (a mount's, when on one).
local function Pace()
	local _, run = Compat.CallAll(GetUnitSpeed, "player")
	if type(run) == "number" and run > 0 then return run end
	return RUN_SPEED
end

--[[ Drawing ]]

local function SetText(fs, text)
	if fs:GetText() ~= text then fs:SetText(text) end
end

-- "You're here" goes under the middle; yards and time sit either side of it.
local function CentreDistance(centred)
	if frame.centred == centred then return end
	frame.centred = centred
	local distance = frame.distance
	distance:ClearAllPoints()
	if centred then
		distance:SetPoint("TOP", frame.instruction, "BOTTOM", 0, -6)
		distance:SetJustifyH("CENTER")
	else
		distance:SetPoint("TOPRIGHT", frame.instruction, "BOTTOM", -5, -6)
		distance:SetJustifyH("RIGHT")
	end
end

-- The arrow and its words shown or not; a frame with nothing on it lets the mouse through.
local function ShowParts(on)
	frame.icon:SetShown(on)
	frame.instruction:SetShown(on)
	frame.distance:SetShown(on)
	frame.eta:SetShown(on)
	frame:EnableMouse(on and not Profile().objframelocked)
end

local function Update()
	local angle, yards, placed = AP:NavArrowBearing()
	if not placed then
		ShowParts(false)
		return
	end
	ShowParts(true)
	frame.angle = angle
	if angle then frame.icon:SetRotation(angle) end
	frame.icon:SetShown(angle ~= nil)
	SetText(frame.instruction, L.ARROW_PHRASES[target.action] or L.ARROW_PHRASE)
	CentreDistance(yards ~= nil and yards < HERE)
	if yards and yards < HERE then
		SetText(frame.distance, L.ARROW_HERE)
		SetText(frame.eta, "")
	elseif yards then
		SetText(frame.distance, string.format(L.ARROW_YARDS, math.floor(yards + 0.5)))
		SetText(frame.eta, AP.FormatEta(math.max(1, yards / Pace())))
	else
		SetText(frame.distance, "")
		SetText(frame.eta, "")
	end
end

--- Point at the step you are on, or hide: called on every change to the guide.
function AP:RefreshNavArrow()
	if not frame then return end
	local _, step
	local guide = self:GetCurrentGuide()
	if guide then _, step = self:GetCurrentStep() end
	if step and step.map and step.x and step.y and not self:InArrivedArea(step) then
		-- In a kill area's block every step reads as the area, the book a kobold drops too.
		local action = self:IsAreaBlock(guide, (self:GetCurrentBlock())) and "COMPLETE" or step.action
		target = { map = step.map, x = step.x, y = step.y, action = action }
	else
		target = nil
	end
	local guideShown = self.objectiveframe and self.objectiveframe:IsShown()
	local shown = target ~= nil and self:IsNavArrowOn() and guideShown
	frame:SetShown(shown and true or false)
	if shown then
		frame.elapsed = 0
		Update()
	end
end

function AP:ToggleNavArrow()
	Char().navarrow = not self:IsNavArrowOn()
	self:Print(self:IsNavArrowOn() and L.ARROW_ON or L.ARROW_OFF)
	self:RefreshNavArrow()
	if self.RefreshConfigPanel then self:RefreshConfigPanel() end
end

function AP:SetNavArrowScale(scale)
	scale = math.max(SCALE_MIN, math.min(SCALE_MAX, tonumber(scale) or 1))
	Profile().navarrowscale = scale
	if not frame then return end
	frame.scaleFactor = scale
	frame:SetScale(Theme.windowScale * scale)
end

function AP:ResetNavArrowPosition()
	Theme:ForgetPosition("navarrow")
	if not frame then return end
	frame:ClearAllPoints()
	frame:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
end

--[[ Building it ]]

local function Shadowed(fs)
	fs:SetShadowOffset(0, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	return fs
end

local function Build()
	frame = CreateFrame("Frame", "AegisPathfinderNavArrow", UIParent)
	AP.navarrow = frame
	-- Under every window: one dragged over it covers it, never the other way round.
	frame:SetFrameStrata("MEDIUM")
	frame:SetSize(WIDTH, ARROW + 46)
	frame:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
	frame:SetClampedToScreen(true)
	frame:Hide()
	Theme:RestorePosition(frame, "navarrow")
	frame.scaleFactor = Profile().navarrowscale or 1
	Theme:Scaled(frame)

	local box = CreateFrame("Frame", nil, frame)
	box:SetSize(ARROW, ARROW)
	box:SetPoint("TOP", frame, "TOP", 0, 0)
	local icon = box:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(box)
	Theme:Skin(icon, "navArrow")      -- the theme's colour; recoloured with the theme
	frame.box, frame.icon = box, icon

	-- The concept's colours, the same in every theme: they float on the world, not on a panel.
	local instruction = Shadowed(frame:CreateFontString(nil, "OVERLAY"))
	Theme:SetFont(instruction, "body2", 14)
	instruction:SetPoint("TOP", box, "BOTTOM", 0, -7)
	instruction:SetWidth(WIDTH)
	instruction:SetJustifyH("CENTER")
	instruction:SetTextColor(0.96, 0.95, 0.91)
	local distance = Shadowed(frame:CreateFontString(nil, "OVERLAY"))
	Theme:SetFont(distance, "body2", 13)
	distance:SetTextColor(0.91, 0.60, 0.32)
	local eta = Shadowed(frame:CreateFontString(nil, "OVERLAY"))
	Theme:SetFont(eta, "body2", 13)
	eta:SetPoint("TOPLEFT", instruction, "BOTTOM", 5, -6)
	eta:SetJustifyH("LEFT")
	eta:SetTextColor(0.93, 0.90, 0.85)
	frame.instruction, frame.distance, frame.eta = instruction, distance, eta
	CentreDistance(false)

	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not Profile().objframelocked then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Theme:PositionSaver("navarrow")(self)
	end)

	-- About ten times a second while it shows; a hidden frame gets no updates.
	frame.elapsed = 0
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + (elapsed or 0)
		if self.elapsed < TICK then return end
		self.elapsed = 0
		Update()
	end)

	-- With the guide window: hooked, not set, as the window stack hooks these too.
	local guide = AP.objectiveframe
	if guide then
		guide:HookScript("OnShow", function() AP:RefreshNavArrow() end)
		guide:HookScript("OnHide", function() AP:RefreshNavArrow() end)
	end
	AP:RefreshNavArrow()
end

AP:OnInit(Build)
