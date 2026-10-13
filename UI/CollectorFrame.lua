local _, AP = ...
local L = AP.L
local Theme = AP.Theme

--[[ The data collection window.

	What the collector is doing and what it has: a switch to start and stop it,
	"Automatically run" to have it start at every login, the counts so far, the
	last things it wrote down, and the way out for the data -- Export, as text
	to copy -- and Clear. Opened from the guide window (its ● chip, its ≡ menu
	and its empty body), the minimap button, the options' Data Collection page
	and /apg collect.
]]

local WIDTH, HEIGHT = 360, 470
local PAD = 14
local LOG_LINES = 12

local frame, ui
local function Char() return AP.db.char end

StaticPopupDialogs.AEGISPATHFINDER_CLEAR_DATA = {
	text = L.COLLECTOR_CLEAR_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() AP.Collector:Clear() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
}

--[[ The export: the text in a box to select and copy. ]]
local exportFrame

local function BuildExport()
	local f = CreateFrame("Frame", "AegisPathfinderExport", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetSize(560, 420)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	Theme:Panel(f, "panel")
	Theme:Chrome(f, L.COLLECTOR_EXPORT, nil)
	tinsert(UISpecialFrames, "AegisPathfinderExport")

	local hint = Theme:FinePrint(f, 560 - PAD * 2)
	hint:SetPoint("TOPLEFT", f.subhead, "BOTTOMLEFT", PAD, -8)
	hint:SetText(L.COLLECTOR_EXPORT_HINT)

	local holder = CreateFrame("Frame", nil, f)
	holder:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
	holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 30)
	if Theme:IsBlizzard() then
		Theme:Backdrop(holder, "tooltip")
		holder:SetBackdropColor(0, 0, 0, 0.8)
	else
		Theme:NineSlice(holder, Theme.texture.tabFill, "BACKGROUND", "panel2")
		Theme:NineSlice(holder, Theme.texture.tabBorder, "BORDER", "border")
	end

	local scroll = CreateFrame("ScrollFrame", nil, holder)
	scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -8, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetWidth(560 - PAD * 2 - 16)
	box:SetFontObject(ChatFontNormal)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	-- The text is for copying, not editing: typing puts it back.
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput and f.text then
			self:SetText(f.text)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(box)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local target = self:GetVerticalScroll() - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), target)))
	end)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)

	local size = f:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(size, "body", 11)
	size:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD + 6)
	Theme:TextColor(size, "textDim")

	local select = Theme:PanelButton(f, "Select all", 120, 24)
	select:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
	select:SetScript("OnClick", function()
		box:SetFocus()
		box:HighlightText()
	end)

	f.box, f.size = box, size
	f:Hide()
	exportFrame = f
end

function AP:ShowExport()
	if not exportFrame then BuildExport() end
	local text = AP.Export.Build()
	exportFrame.text = text
	exportFrame.box:SetText(text)
	exportFrame.size:SetText(string.format("%.1f KB", #text / 1024))
	exportFrame:Show()
	exportFrame.box:SetFocus()
	exportFrame.box:HighlightText()
end

--[[ The window ]]

local function Stat(parent, label, x, y)
	local value = parent:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(value, "display", 20)
	value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	Theme:TextColor(value, "text")
	local name = parent:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(name, "body", 10)
	name:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -1)
	name:SetText(label:upper())
	Theme:TextColor(name, "textDim")
	return value
end

local function Build()
	frame = CreateFrame("Frame", "AegisPathfinderCollector", UIParent)
	AP.collectorframe = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("TOPRIGHT", AP.objectiveframe, "TOPLEFT", -8, 0)
	Theme:Panel(frame, "panel")
	Theme:Chrome(frame, L.COLLECTOR_TITLE, Theme:PositionSaver("collectorframe"))
	Theme:RestorePosition(frame, "collectorframe")
	tinsert(UISpecialFrames, "AegisPathfinderCollector")
	frame:Hide()
	ui = {}
	frame.ui = ui

	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", frame.subhead, "BOTTOMLEFT", PAD, -12)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
	local W = WIDTH - PAD * 2 - (Theme:IsBlizzard() and 12 or 2)

	-- State: a dot, collecting or not, and the switch.
	local dot = body:CreateTexture(nil, "ARTWORK")
	dot:SetTexture(Theme.texture.circleFill)
	dot:SetSize(10, 10)
	dot:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -6)
	ui.dot = dot

	local state = body:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(state, "display", 16)
	state:SetPoint("LEFT", dot, "RIGHT", 8, 0)
	ui.state = state

	local toggle = Theme:PanelButton(body, L.START_COLLECTING, W, 28)
	toggle:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -26)
	toggle:SetScript("OnClick", function() AP.Collector:Toggle() end)
	ui.toggle = toggle

	local auto = Theme:Checkbox(body, L.COLLECTOR_AUTO, function(on) AP.Collector:SetAuto(on) end)
	auto:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 0, -10)
	auto:Fit()
	ui.auto = auto

	local autoNote = Theme:FinePrint(body, W)
	autoNote:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -2)
	autoNote:SetText(L.COLLECTOR_AUTO_NOTE)

	-- What it has so far.
	local stats = Theme:SectionHeader(body, "Collected", W)
	stats:SetPoint("TOPLEFT", autoNote, "BOTTOMLEFT", 0, -14)
	local grid = CreateFrame("Frame", nil, body)
	grid:SetSize(W, 40)
	grid:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -8)
	local col = W / 4
	ui.quests = Stat(grid, "Quests", 0, 0)
	ui.turnedIn = Stat(grid, "Turned in", col, 0)
	ui.pickups = Stat(grid, "Picked up", col * 2, 0)
	ui.levels = Stat(grid, "Levels", col * 3, 0)

	-- The last things it wrote down.
	local recent = Theme:SectionHeader(body, "Recent", W)
	recent:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -10)
	ui.lines = {}
	for i = 1, LOG_LINES do
		local fs = body:CreateFontString(nil, "OVERLAY")
		Theme:SetFont(fs, "body", 11)
		fs:SetWidth(W)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		fs:SetPoint("TOPLEFT", recent, "BOTTOMLEFT", 0, -6 - (i - 1) * 14)
		Theme:TextColor(fs, "textDim")
		ui.lines[i] = fs
	end

	-- Export and clear.
	local export = Theme:PanelButton(body, L.COLLECTOR_EXPORT, (W - 8) / 2, 26)
	export:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	export:SetScript("OnClick", function() AP:ShowExport() end)
	local clear = Theme:PanelButton(body, L.COLLECTOR_CLEAR, (W - 8) / 2, 26)
	clear:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	clear:SetScript("OnClick", function() StaticPopup_Show("AEGISPATHFINDER_CLEAR_DATA") end)

	frame:HookScript("OnShow", function(self)
		Char().collectoropen = true
		AP:RefreshCollectorFrame()
		Theme:FadeIn(self, 0.2)
	end)
	frame:HookScript("OnHide", function() Char().collectoropen = false end)
	AP.Collector:OnChange(function() if frame:IsShown() then AP:RefreshCollectorFrame() end end)
end

function AP:RefreshCollectorFrame()
	if not frame then return end
	local Collector = self.Collector
	local running = Collector:IsRunning()
	Theme:Tint(ui.dot, running and "accent" or "subtle")
	ui.state:SetText((running and L.COLLECTOR_ON or L.COLLECTOR_OFF):upper())
	Theme:TextColor(ui.state, running and "accent" or "textDim")
	ui.toggle:SetText(running and L.STOP_COLLECTING or L.START_COLLECTING)
	ui.toggle:SetActive(running)
	ui.auto:SetOn(Collector:IsAuto())

	local counts = Collector:Counts()
	ui.quests:SetText(counts.quests)
	ui.turnedIn:SetText(counts.turnedIn)
	ui.pickups:SetText(counts.pickups)
	ui.levels:SetText(counts.levels)

	local log = Collector:GetLog()
	for i = 1, LOG_LINES do
		local line = log[#log - i + 1]
		ui.lines[i]:SetText(line or (i == 1 and L.COLLECTOR_LOG_EMPTY or ""))
	end
end

function AP:ToggleCollectorFrame()
	if not frame then return end
	frame:SetShown(not frame:IsShown())
end

function AP:ResetCollectorPosition()
	if not frame then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", AP.objectiveframe, "TOPLEFT", -8, 0)
end

AP:OnInit(Build)
