local _, AP = ...
local L = AP.L
local Theme = AP.Theme

--[[ The objectives panel -- the guide window, and the addon's main surface.

	Laid out as the concept's `#objectives` panel and the 1.12 addon's, top to
	bottom:

	  header       ☰ · ⤢ · ● · PATHFINDER · ✕, and the drag handle
	  tab bar      the guide you are on, and + for the guide browser
	  nav row      ← step number →, with the step count on the right
	  progress     4px bar of guide completion
	  body         the steps -- or, with no guide, what to do instead
	  footer       the step's quest id, or the collector's state; the count

	Forever has one short test guide so far (Northshire), so with no guide open
	the body says to pick one from the browser (+), and offers the button that
	starts collecting the data the rest will be written from. The ● chip
	lights while it collects.

	Rows follow the concept's two models: most steps are a `.zrow` (a dot, an
	action glyph, the title and the note under it); ACCEPT and TURNIN steps
	become a full-width `.zband` once current or done, red while outstanding and
	green once satisfied -- with the step's note under the band in focus mode.
	Only the character's own steps are painted and counted (AP:GuideSteps).

	In focus mode a COMPLETE step shows its quest's live progress in a box
	under it, as the 1.12 addon's meter did: what the quest wants, "3 / 10",
	and a bar. Steps done together (a kill area's quests, the book a kobold
	drops) show as one block: a row for each, the current one's note in full,
	no bands, each ticking itself.
]]

local G = {
	HEADER_H = 30, TABBAR_H = 26, NAVROW_H = 26, PROGRESS_H = 4, FOOTER_H = 24,
	ROWHEIGHT = 44, ROWPAD = 14, DOTSIZE = 14, ICONSIZE = 16,
	DEFAULT_WIDTH = 396,                                     -- .panel{width:396px}
	DEFAULT_ANCHOR = { "TOPRIGHT", "TOPRIGHT", -40, -180 },  -- top:180px; right:40px
	MIN_WIDTH = 320, MAX_WIDTH = 1200,
	DEFAULT_CAP = 600, MIN_CAP = 260,
	EMPTY_PAD = 18,
	MAX_ROWS = 30,
	EDGE_L = 1, EDGE_R = 1, EDGE_B = 1,
}
-- Set from the skin as the window is built (Build): the header's height and the frame's edges.
G.CHROME_TOP = G.HEADER_H + G.TABBAR_H + G.NAVROW_H + G.PROGRESS_H

local function Measure()
	local m = Theme.metrics
	G.HEADER_H = m.header
	G.CHROME_TOP = m.top + G.HEADER_H + G.TABBAR_H + G.NAVROW_H + G.PROGRESS_H
	G.EDGE_L, G.EDGE_R, G.EDGE_B = m.left, m.right, m.bottom
end

local frame, ui
local rows = {}
local offset = 0

local function Char() return AP.db.char end
local function Profile() return AP.db.profile end

--- The tallest the panel may be: what the player set with the grip, or min(70vh, 600px).
function AP:GetPanelCap()
	local cap = Profile().objframemaxheight
	local screen = UIParent:GetHeight()
	if not cap then cap = math.min(G.DEFAULT_CAP, math.floor(screen * 0.7)) end
	return math.max(G.MIN_CAP, math.min(cap, screen - 20))
end

--[[ The ≡ menu, Zygor's: the guide browser, data collection, locking the
	window where it is, a see-through panel, putting the windows back,
	reloading, and the settings. It opens under the chip, above every window. ]]
local GUIDE_MENU = {
	{ label = "Guide menu", glyph = "book", run = function() AP:ShowGuideBrowser() end },
	{ label = "Data collection", glyph = "record", run = function() AP:ToggleCollectorFrame() end },
	"-",
	{ label = "Lock window", glyph = "lock", key = "objframelocked", run = function(on) AP:SetGuideLocked(on) end },
	{ label = "Transparency", glyph = "dashed", key = "objframetransparent",
		run = function(on) AP:SetGuideTransparent(on) end },
	"-",
	{ label = "Reset window", glyph = "reset", run = function() AP:ResetWindowLayout() end },
	-- Only the game's own code can reload: this asks through the Reload dialog (Theme:AskReload).
	{ label = "Reload", glyph = "reload", run = function() Theme:AskReload() end },
	"-",
	{ label = "Settings", glyph = "gear", run = function() AP:ToggleConfigPanel() end },
}
local MENU_W, MENU_ROW = 220, 28

--- Hold the guide where it is: no dragging it, and no grip to size it by.
function AP:SetGuideLocked(on)
	Profile().objframelocked = on and true or nil
	if not frame then return end
	frame.locked = on and true or nil
	frame.grip:SetShown(not on)
	if self.RefreshNavArrow then self:RefreshNavArrow() end
	if self.RefreshConfigPanel then self:RefreshConfigPanel() end
end

--- A see-through panel: its body at the Appearance page's opacity, and no shadow.
function AP:SetGuideTransparent(on)
	Profile().objframetransparent = on and true or nil
	if not frame then return end
	local skin = frame.skin
	skin.fill:SetTint("panel", on and (Profile().objframeopacity or 0.5) or 1)
	if skin.shadow then skin.shadow:SetTint({ 0, 0, 0 }, on and 0 or 0.62) end
	if self.RefreshConfigPanel then self:RefreshConfigPanel() end
end

--- How see-through Transparency makes the guide: 20% to 100%.
function AP:SetGuideOpacity(v)
	v = math.max(0.2, math.min(1, v or 0.5))
	Profile().objframeopacity = v
	if Profile().objframetransparent then self:SetGuideTransparent(true) end
	return v
end

function AP:SetGuideProgressShown(on)
	Profile().showprogress = on and true or false
	self:RefreshObjectivePanel()
end

function AP:SetStepTextSize(v)
	Profile().steptextsize = math.max(0.8, math.min(1.4, v or 1))
	if frame then
		for _, row in ipairs(rows) do row.sized = nil end
		self:RefreshObjectivePanel()
	end
	return Profile().steptextsize
end

-- A menu row's box, ticked while what it stands for is on.
local function MenuBox(row)
	local box = Theme:Checkbox(row, "", nil)
	box:EnableMouse(false)
	box:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	box:SetWidth(20)
	function row:SetChecked(on)
		self.on = on
		box:SetOn(on)
	end
end

local function MenuRow(menu, item, y)
	local row = CreateFrame("Button", nil, menu)
	row:SetHeight(MENU_ROW)
	row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
	row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, y)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(Theme.texture.solid)
	hl:SetAllPoints(row)
	Theme:Tint(hl, "text", 0.06)
	local g = row:CreateTexture(nil, "ARTWORK")
	g:SetTexture(Theme.glyph[item.glyph])
	g:SetSize(14, 14)
	g:SetPoint("LEFT", row, "LEFT", 10, 0)
	Theme:Tint(g, Theme:IsBlizzard() and "accent" or "textDim")
	local fs = row:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(fs, "body", 13)
	fs:SetPoint("LEFT", row, "LEFT", 34, 0)
	fs:SetText(item.label)
	Theme:TextColor(fs, "text")
	row.item, row.label = item, fs
	if item.key then MenuBox(row) end
	row:SetScript("OnClick", function(self)
		local it = self.item
		if it.key then
			it.run(not self.on)
			self:SetChecked(Profile()[it.key])
		else
			ui.menu:Hide()
			it.run()
		end
	end)
	return row
end

local function BuildMenu(chip)
	local menu = CreateFrame("Frame", "AegisPathfinderGuideMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetWidth(MENU_W)
	menu:SetPoint("TOPLEFT", chip, "BOTTOMLEFT", -2, -4)
	Theme:Panel(menu, "panel2")
	Theme:Scaled(menu)
	menu:EnableMouse(true)
	menu:Hide()
	menu.rows = {}
	local y = -6
	for _, item in ipairs(GUIDE_MENU) do
		if item == "-" then
			local rule = menu:CreateTexture(nil, "ARTWORK")
			rule:SetTexture(Theme.texture.solid)
			rule:SetHeight(1)
			rule:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, y - 4)
			rule:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -12, y - 4)
			Theme:Tint(rule, "tabbg")
			y = y - 9
		else
			menu.rows[#menu.rows + 1] = MenuRow(menu, item, y)
			y = y - MENU_ROW
		end
	end
	menu:SetHeight(6 - y)
	menu:SetScript("OnShow", function(self)
		local labels = {}
		for _, row in ipairs(self.rows) do
			if row.item.key then row:SetChecked(Profile()[row.item.key]) end
			labels[#labels + 1] = row.label
		end
		-- Built at login, maybe before our fonts had loaded: draw the labels again.
		Theme:RefreshFontStrings(labels)
	end)
	chip:HookScript("OnHide", function() menu:Hide() end)
	tinsert(UISpecialFrames, "AegisPathfinderGuideMenu")
	return menu
end

--[[ Resize grip: sideways sets the width, down or up sets the panel's height
	cap -- the concept's grip exactly. It does its own sizing rather than
	StartSizing, so the panel stays pinned by its top-left. ]]
local function BuildGrip()
	local grip = CreateFrame("Frame", nil, frame)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", -(G.EDGE_R + 3), G.EDGE_B + 3)
	grip:EnableMouse(true)
	grip:SetFrameLevel(frame:GetFrameLevel() + 6)
	local tex = grip:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(Theme.texture.grip)
	tex:SetAllPoints(grip)
	Theme:Tint(tex, "textDim", 0.55)

	local function Cursor()
		local scale = frame:GetEffectiveScale()
		local x, y = GetCursorPosition()
		return x / scale, y / scale
	end
	local function Stop()
		grip.sizing = nil
		grip:SetScript("OnUpdate", nil)
		Theme:Tint(tex, "textDim", 0.55)
	end
	local function Sizing()
		local s = grip.sizing
		if not s then return end
		if not IsMouseButtonDown("LeftButton") then return Stop() end
		local x, y = Cursor()
		local w = math.max(G.MIN_WIDTH, math.min(G.MAX_WIDTH, math.floor(s.w + x - s.x + 0.5)))
		local cap = math.max(G.MIN_CAP, math.min(UIParent:GetHeight() - 20, math.floor(s.cap + s.y - y + 0.5)))
		Profile().objframemaxheight = cap
		Profile().objframewidth = w
		frame:SetWidth(w)
		AP:RefreshObjectivePanel()
	end
	grip:SetScript("OnMouseDown", function()
		Theme:Tint(tex, "accentGlow", 1)
		Theme:AnchorTopLeft(frame)
		local x, y = Cursor()
		grip.sizing = { x = x, y = y, w = frame:GetWidth(), cap = AP:GetPanelCap() }
		grip:SetScript("OnUpdate", Sizing)
	end)
	grip:SetScript("OnMouseUp", function()
		Sizing()
		Stop()
		frame.savePosition(frame)
	end)
	grip:SetScript("OnEnter", function(self)
		Theme:Tint(tex, "accent", 1)
		Theme:ShowTip(self, "LEFT", "Drag to set the width and the tallest the panel may grow")
	end)
	grip:SetScript("OnLeave", function(self)
		if not grip.sizing then Theme:Tint(tex, "textDim", 0.55) end
		Theme:HideTip(self)
	end)
	return grip
end

--[[ A step row: dot, action glyph, title and note -- or a band for a hand-off. ]]
local function TextScale() return Profile().steptextsize or 1 end

local function NewRow(i)
	local row = CreateFrame("Button", nil, ui.body)
	row:SetHeight(G.ROWHEIGHT)
	row.index = i

	local wash = row:CreateTexture(nil, "BACKGROUND")
	wash:SetTexture(Theme.texture.solid)
	wash:SetAllPoints(row)
	Theme:Tint(wash, "accent", 0.06)
	row.wash = wash

	local bar = row:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(Theme.texture.solid)
	bar:SetWidth(3)
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	Theme:Tint(bar, "accent")
	row.bar = bar

	local check = Theme:StepCheck(row, G.DOTSIZE)
	check:SetPoint("TOPLEFT", row, "TOPLEFT", G.ROWPAD, -10)
	check:SetScript("OnClick", function(self)
		local done = not self:GetChecked()
		AP:SetStepDone(row.step, done)
	end)
	row.check = check

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(G.ICONSIZE, G.ICONSIZE)
	icon:SetPoint("LEFT", check, "RIGHT", 9, 0)
	row.icon = icon

	local title = row:CreateFontString(nil, "OVERLAY")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, 1)
	title:SetPoint("RIGHT", row, "RIGHT", -G.ROWPAD, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	Theme:TextColor(title, "text")
	row.title = title

	local note = row:CreateFontString(nil, "OVERLAY")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	note:SetPoint("RIGHT", row, "RIGHT", -G.ROWPAD, 0)
	note:SetJustifyH("LEFT")
	note:SetJustifyV("TOP")
	Theme:TextColor(note, "textDim")
	row.note = note

	-- The band keeps a row's height at the top; in focus mode its note shows under it.
	local band = Theme:Band(row, G.ROWHEIGHT)
	band:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	band:EnableMouse(false)
	band:Hide()
	row.band = band

	local bandNote = row:CreateFontString(nil, "OVERLAY")
	bandNote:SetPoint("TOPLEFT", band, "BOTTOMLEFT", G.ROWPAD, -6)
	bandNote:SetPoint("RIGHT", row, "RIGHT", -G.ROWPAD, 0)
	bandNote:SetJustifyH("LEFT")
	bandNote:SetJustifyV("TOP")
	Theme:TextColor(bandNote, "textDim")
	bandNote:Hide()
	row.bandNote = bandNote

	row:SetScript("OnEnter", function(self)
		if not self.data then return end
		local detail = {}
		if self.data.note then detail[#detail + 1] = self.data.note end
		if self.data.qid then detail[#detail + 1] = "Quest " .. self.data.qid end
		Theme:ShowTip(self, "RIGHT", self.data.title or self.data.action, detail)
	end)
	row:SetScript("OnLeave", function(self) Theme:HideTip(self) end)
	rows[i] = row
	return row
end

local function SizeRowFonts(row)
	if row.sized == TextScale() then return end
	row.sized = TextScale()
	Theme:SetFont(row.title, "body2", math.floor(12 * TextScale() + 0.5))
	Theme:SetFont(row.note, "body", math.floor(11 * TextScale() + 0.5))
	Theme:SetFont(row.bandNote, "body", math.floor(11 * TextScale() + 0.5))
	Theme:SetFont(row.band.label, "body", math.floor(12 * TextScale() + 0.5))
end

--[[ The meter: a COMPLETE step's live progress, as the 1.12 addon drew it -- a
	recessed box, a line for each counted objective: its name, "3 / 10" in the
	accent, and a 6px bar under them. ]]
local METER_PAD, METER_LINE, METER_GAP = 8, 22, 8
-- Where a row's title starts: past the ring and the action glyph.
local TEXT_LEFT = G.ROWPAD + G.DOTSIZE + 9 + G.ICONSIZE + 9

-- A meter line's height at the step text size.
local function MeterLineHeight() return math.floor(METER_LINE * TextScale() + 0.5) end

local function MeterHeight(n)
	return METER_PAD * 2 + n * MeterLineHeight() + (n - 1) * METER_GAP
end

-- Size and place line `k` for the step text size: its words, and the bar under them.
local function LayOutLine(meter, line, k)
	local size = math.floor(12 * TextScale() + 0.5)
	Theme:SetFont(line.count, "body2", size)
	Theme:SetFont(line.label, "body", size)
	local y = -(METER_PAD + (k - 1) * (MeterLineHeight() + METER_GAP))
	line.count:ClearAllPoints()
	line.count:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -11, y)
	line.label:ClearAllPoints()
	line.label:SetPoint("TOPLEFT", meter, "TOPLEFT", 11, y)
	line.label:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
	line.bar:ClearAllPoints()
	line.bar:SetPoint("TOPLEFT", meter, "TOPLEFT", 11, y - (MeterLineHeight() - 6))
	line.bar:SetPoint("RIGHT", meter, "RIGHT", -11, 0)
end

local function MeterLine(meter, k)
	local line = meter.lines[k]
	if line then return line end
	line = {}
	line.count = meter:CreateFontString(nil, "OVERLAY")
	Theme:TextColor(line.count, "accent")
	line.count:SetJustifyH("RIGHT")
	line.label = meter:CreateFontString(nil, "OVERLAY")
	Theme:TextColor(line.label, "textDim")
	line.label:SetJustifyH("LEFT")
	line.label:SetWordWrap(false)
	line.bar = Theme:ProgressBar(meter, 6)
	LayOutLine(meter, line, k)
	meter.lines[k] = line
	return line
end

-- Fill the row's meter from the quest log, under `below`; false (and hidden) with nothing to show.
local function PaintMeter(row, step, below)
	local progress = AP:QuestProgress(step.qid, step.title)
	if not (progress and #progress > 0) then
		if row.meter then row.meter:Hide() end
		return false
	end
	local meter = row.meter
	if not meter then
		meter = CreateFrame("Frame", nil, row)
		Theme:Inset(meter)
		meter.lines = {}
		meter.sized = TextScale()
		row.meter = meter
	end
	if meter.sized ~= TextScale() then
		meter.sized = TextScale()
		for k, line in ipairs(meter.lines) do LayOutLine(meter, line, k) end
	end
	meter:ClearAllPoints()
	meter:SetPoint("TOPLEFT", below, "BOTTOMLEFT", G.ROWPAD - TEXT_LEFT, -6)
	meter:SetPoint("RIGHT", row, "RIGHT", -G.ROWPAD, 0)
	meter:SetHeight(MeterHeight(#progress))
	for k, objective in ipairs(progress) do
		local line = MeterLine(meter, k)
		line.label:SetText(objective.label or "")
		line.count:SetText(string.format("%d / %d", objective.have, objective.need))
		line.bar:SetProgress(objective.have / objective.need)
		line.label:Show()
		line.count:Show()
		line.bar:Show()
	end
	for k = #progress + 1, #meter.lines do
		local line = meter.lines[k]
		line.label:Hide()
		line.count:Hide()
		line.bar:Hide()
	end
	meter:Show()
	return true
end

-- The first unfinished objective, for a COMPLETE step's line in the list: "Kobold Vermin slain - 3/10".
local function ProgressLine(step)
	for _, objective in ipairs(AP:QuestProgress(step.qid, step.title) or {}) do
		if objective.have < objective.need then
			return string.format("%s - %d/%d", objective.label or step.title, objective.have, objective.need)
		end
	end
end

--- Paint step `index` on `row`. `focus`: the one-step view; `inBlock`: one of several
--- steps done together, on now; `compact`: just its title (a block too tall for the window).
local function PaintRow(row, guide, index, current, focus, inBlock, compact)
	local step = guide.steps[index]
	row.step, row.data = index, step
	SizeRowFonts(row)
	local done = AP:IsStepDone(guide.name, index)
	local isCurrent = index == current
	local bandable = not inBlock and (step.action == "ACCEPT" or step.action == "TURNIN") and (done or isCurrent)
	row.band:SetShown(bandable)
	row.band:SetHeight(math.floor(G.ROWHEIGHT * TextScale() + 0.5))
	for _, region in ipairs({ row.check, row.icon, row.title, row.note }) do region:SetShown(not bandable) end
	-- Who and where for a hand-off: under the band, in focus mode (in the list, on hover).
	local bandNote = bandable and focus and step.note and step.note ~= ""
	row.bandNote:SetShown(bandNote)
	row.bandNote:SetText(bandNote and step.note or "")
	if bandable then
		row.band.icon:SetTexture(Theme.actionIconByName[step.action])
		row.band.label:SetText(step.title or step.action)
		row.band:SetDone(done)
	else
		row.check:SetChecked(done)
		row.check:SetAutoEligible(AP:TicksItself(step))
		Theme:SetActionIcon(row.icon, ({ ACCEPT = "A", TURNIN = "T", COMPLETE = "C", RUN = "R", KILL = "K", USE = "U",
			NOTE = "N", HEARTH = "H", SETHEARTH = "h", FLY = "F", GETFLIGHTPOINT = "f", BUY = "B", BOAT = "b",
			GRIND = "G", TRAIN = "t", DIE = "D", PET = "P", MAP = "R", LOOT = "L" })[step.action])
		row.title:SetText(step.title or step.action)
		local note = step.note or ""
		if not focus and step.action == "COMPLETE" and (isCurrent or inBlock) then
			note = ProgressLine(step) or note
		end
		-- In a block, only the step you're on has its note in full; the rest have theirs on hover.
		local noted = not (focus and inBlock and not isCurrent) and not compact
		row.note:SetText(noted and note or "")
		row.note:SetShown(noted)
		row.note:SetWordWrap(focus)
	end
	local metered = false
	if focus and not bandable and not compact and step.action == "COMPLETE" and (isCurrent or inBlock) then
		metered = PaintMeter(row, step, row.note:IsShown() and row.note:GetText() ~= "" and row.note or row.title)
	elseif row.meter then
		row.meter:Hide()
	end
	row.metered = metered
	row.wash:SetShown(isCurrent or inBlock)
	row.bar:SetShown(isCurrent or inBlock)
	row:SetAlpha(done and not isCurrent and 0.55 or 1)
	row:Show()
end

-- A painted focus row's height: the band and its note, or the title, the note and the meter.
local function FocusHeight(row, rowH)
	if row.bandNote:IsShown() then
		return rowH + 6 + (row.bandNote:GetStringHeight() or 0) + 10
	end
	local noteH = row.note:IsShown() and (row.note:GetStringHeight() or 0) or 0
	local meterH = row.metered and (6 + row.meter:GetHeight()) or 0
	return math.max(rowH, 31 + noteH + meterH + 10)
end

--[[ The empty body: no guide to follow, so what to do instead. ]]
local function BuildEmpty()
	local empty = CreateFrame("Frame", nil, ui.body)
	empty:SetPoint("TOPLEFT", ui.body, "TOPLEFT", G.EMPTY_PAD, -G.EMPTY_PAD)
	empty:SetPoint("TOPRIGHT", ui.body, "TOPRIGHT", -G.EMPTY_PAD, -G.EMPTY_PAD)

	local logo = empty:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(Theme.texture.minimapLogo)
	logo:SetSize(40, 40)
	logo:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)

	local title = empty:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(title, "display", 18)
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
	title:SetText(L.NO_GUIDES_TITLE:upper())
	Theme:TextColor(title, "accent")

	local status = empty:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(status, "body2", 11)
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	Theme:TextColor(status, "textDim")

	local body = Theme:FinePrint(empty, 300)
	Theme:SetFont(body, "body", 12)
	body:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -12)
	body:SetPoint("RIGHT", empty, "RIGHT", 0, 0)
	body:SetText(L.NO_GUIDES_BODY)

	local start = Theme:PanelButton(empty, L.START_COLLECTING, 200, 26)
	start:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -14)
	start:SetScript("OnClick", function() AP.Collector:Toggle() end)

	local open = Theme:PanelButton(empty, L.OPEN_COLLECTOR, 140, 26)
	open:SetPoint("LEFT", start, "RIGHT", 8, 0)
	open:SetScript("OnClick", function() AP:ToggleCollectorFrame() end)

	-- The collection window's own checkbox, here too: the one setting worth having at hand.
	local auto = Theme:Checkbox(empty, L.COLLECTOR_AUTO, function(on) AP.Collector:SetAuto(on) end)
	auto:SetPoint("TOPLEFT", start, "BOTTOMLEFT", 0, -10)
	auto:Fit()
	auto:HookScript("OnEnter", function(self) Theme:ShowTip(self, "BOTTOM", L.COLLECTOR_AUTO, L.COLLECTOR_AUTO_NOTE) end)
	auto:HookScript("OnLeave", function(self) Theme:HideTip(self) end)

	empty.logo, empty.title, empty.status, empty.text, empty.start, empty.open = logo, title, status, body, start, open
	empty.auto = auto
	ui.empty = empty
end

local function PaintEmpty()
	local empty = ui.empty
	local running = AP.Collector:IsRunning()
	local any = AP:HasGuides()
	empty.title:SetText((any and L.PICK_GUIDE_TITLE or L.NO_GUIDES_TITLE):upper())
	empty.text:SetText(any and L.PICK_GUIDE_BODY or L.NO_GUIDES_BODY)
	empty.start:SetText(running and L.STOP_COLLECTING or L.START_COLLECTING)
	empty.start:SetActive(running)
	empty.auto:SetOn(AP.Collector:IsAuto())
	empty.status:SetText((running and L.COLLECTOR_ON or L.COLLECTOR_OFF) .. " -- " .. AP.Collector:StatsText())
	Theme:TextColor(empty.status, running and "accent" or "textDim")
	empty.text:SetWidth(math.max(100, frame:GetWidth() - 2 * G.EMPTY_PAD - G.EDGE_L - G.EDGE_R))
	-- A wrapped string can measure nothing before its first frame on screen: never less than three lines.
	local textH = math.max(empty.text:GetStringHeight() or 0, 48)
	local h = 40 + 12 + textH + 14 + 26 + 10 + 24
	empty:SetHeight(h)
	empty:Show()
	return h + 2 * G.EMPTY_PAD
end

--[[ Painting ]]

local function VisibleRows(available)
	return math.max(1, math.min(G.MAX_ROWS, math.floor(available / (G.ROWHEIGHT * TextScale()))))
end

-- The guide is done: a row saying so, where the step would be.
local function PaintDone(row, guide)
	row.step, row.data = nil, nil
	SizeRowFonts(row)
	if row.meter then row.meter:Hide() end
	row.metered = false
	row.band:Hide()
	row.bandNote:Hide()
	row.check:Hide()
	row.icon:Hide()
	row.title:Show()
	row.note:Show()
	row.title:SetText(L.GUIDE_DONE)
	row.note:SetText(string.format(L.GUIDE_DONE_NOTE, guide.name))
	row.note:SetWordWrap(true)
	row.wash:Hide()
	row.bar:Hide()
	row:SetAlpha(1)
	row:Show()
end

-- `mine`: the indices of the character's own steps (AP:GuideSteps); `current`
-- the index of the step they are on.
local function PaintSteps(guide, current, mine)
	local overview = Char().overviewmode
	local count = #mine
	local rowH = math.floor(G.ROWHEIGHT * TextScale() + 0.5)
	if not overview then
		-- Focus: the step you are on, its note in full -- or the steps done with it, one row each.
		ui.scroll:Hide()
		if not guide.steps[current] then
			for i = 2, #rows do rows[i]:Hide() end
			local row = rows[1] or NewRow(1)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, 0)
			row:SetPoint("RIGHT", ui.body, "RIGHT", 0, 0)
			PaintDone(row, guide)
			local h = math.max(rowH, 31 + (row.note:GetStringHeight() or 0) + 10)
			row:SetHeight(h)
			return h
		end
		local members = AP:GetCurrentBlock()
		local list = members and #members > 1 and members or { current }
		local room = AP:GetPanelCap() - G.CHROME_TOP - G.FOOTER_H - G.EDGE_B
		-- A block too tall for the window: the steps but the current one as just their
		-- titles, and those that still don't fit left for the list.
		local function LayOut(compact)
			local y = 0
			for i, index in ipairs(list) do
				local row = rows[i] or NewRow(i)
				PaintRow(row, guide, index, current, true, #list > 1, compact and index ~= current)
				local h = FocusHeight(row, rowH)
				if compact and index ~= current and y + h > room then
					row:Hide()
				else
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -y)
					row:SetPoint("RIGHT", ui.body, "RIGHT", 0, 0)
					row:SetHeight(h)
					y = y + h
				end
			end
			return y
		end
		local y = LayOut(false)
		if #list > 1 and y > room then y = LayOut(true) end
		for i = #list + 1, #rows do rows[i]:Hide() end
		return y
	end
	-- Overview: the whole list, scrolled by step.
	local cap = AP:GetPanelCap() - G.CHROME_TOP - G.FOOTER_H
	local shown = math.min(count, VisibleRows(cap))
	local inBlock = {}
	local members = guide.steps[current] and AP:GetCurrentBlock()
	if members and #members > 1 then
		for _, index in ipairs(members) do inBlock[index] = true end
	end
	offset = math.max(0, math.min(offset, count - shown))
	for i = 1, shown do
		local row = rows[i] or NewRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -(i - 1) * rowH)
		row:SetPoint("RIGHT", ui.scroll, "LEFT", -4, 0)
		row:SetHeight(rowH)
		PaintRow(row, guide, mine[offset + i], current, false, inBlock[mine[offset + i]])
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	ui.scroll:SetShown(count > shown)
	ui.scroll:SetMinMaxValues(0, math.max(0, count - shown))
	ui.scroll.quiet = true
	ui.scroll:SetValue(offset)
	ui.scroll.quiet = nil
	return shown * rowH
end

function AP:RefreshObjectivePanel()
	if not frame then return end
	local guide = self:GetCurrentGuide()
	local mine = guide and self:GuideSteps(guide) or {}
	local current, position = 0, 0
	if guide then
		local _
		current, _, position = self:GetCurrentStep()
	end
	local count = #mine
	local running = self.Collector:IsRunning()

	-- Header chips that show state.
	ui.expandChip:SetActive(Char().overviewmode)
	ui.collectChip:SetActive(running)

	-- Tab bar: the guide you are on, or nothing yet.
	if guide then
		ui.tab:Show()
		ui.tab.label:SetText(guide.name)
		ui.tab.badge:SetKind(self:BadgeKind(guide.category), nil)
	else
		ui.tab:Hide()
	end

	-- Nav row and progress.
	local done = 0
	if guide then
		for _, index in ipairs(mine) do
			if self:IsStepDone(guide.name, index) then done = done + 1 end
		end
	end
	ui.navStep:SetText(guide and string.format("STEP %d", math.min(position, count)) or "NO GUIDE")
	ui.navCount:SetText(guide and string.format("%d / %d", done, count) or "")
	ui.prev:SetEnabled(guide ~= nil)
	ui.next:SetEnabled(guide ~= nil)
	ui.progress:SetProgress(count > 0 and done / count or 0)
	ui.progress:SetShown(Profile().showprogress ~= false)

	-- Body.
	local bodyH
	if guide then
		ui.empty:Hide()
		bodyH = PaintSteps(guide, current, mine)
	else
		for _, row in ipairs(rows) do row:Hide() end
		ui.scroll:Hide()
		bodyH = PaintEmpty()
	end

	-- Footer: the step's quest, or what the collector is doing.
	local step = guide and guide.steps[current]
	if step and step.qid then
		ui.footerLeft:SetText("QUEST " .. step.qid)
		Theme:TextColor(ui.footerLeft, "accent")
	else
		ui.footerLeft:SetText(running and L.COLLECTOR_ON:upper() or L.COLLECTOR_OFF:upper())
		Theme:TextColor(ui.footerLeft, running and "accent" or "textDim")
	end
	ui.footerRight:SetText(guide and string.format("%d%%", count > 0 and math.floor(done / count * 100) or 0) or "")

	local height = G.CHROME_TOP + bodyH + G.FOOTER_H + G.EDGE_B
	frame:SetHeight(math.min(height, AP:GetPanelCap()))
end

--- Focus mode (one step) or overview (all of them).
function AP:ToggleOverviewMode()
	Char().overviewmode = not Char().overviewmode
	local _, _, position = self:GetCurrentStep()
	offset = math.max(0, (position or 1) - 3)
	self:RefreshObjectivePanel()
end

function AP:ToggleObjectivePanel()
	if not frame then return end
	if frame:IsShown() then
		Char().panelopen = false
		frame:Hide()
	else
		frame:Show()
	end
end

--[[ Building it ]]

local function Build()
	Measure()
	frame = CreateFrame("Frame", "AegisPathfinderObjectives", UIParent)
	AP.objectiveframe = frame
	Theme:TipOutside(frame)
	frame:SetFrameStrata("DIALOG")
	frame:SetWidth(Profile().objframewidth or G.DEFAULT_WIDTH)
	frame:SetHeight(G.CHROME_TOP + G.ROWHEIGHT + G.FOOTER_H)
	frame:SetPoint(G.DEFAULT_ANCHOR[1], UIParent, G.DEFAULT_ANCHOR[2], G.DEFAULT_ANCHOR[3], G.DEFAULT_ANCHOR[4])
	frame.skin = Theme:Panel(frame, "panel")
	frame:Hide()
	-- Not in UISpecialFrames: Escape clears a target in a fight, and must not close the guide.
	Theme:RegisterWindow(frame)
	Theme:RestorePosition(frame, "objframe")
	ui = { rows = rows }
	frame.ui = ui   -- for the smoke test, and /dump

	-- Header.
	local header = Theme:Header(frame, G.HEADER_H)
	frame.savePosition = Theme:PositionSaver("objframe")
	header:MakeDragHandle(frame, frame.savePosition)
	frame.header = header
	local inset = Theme:IsBlizzard() and 0 or 8

	local menuChip = Theme:ChipButton(header, "menu", nil, "Menu")
	menuChip:SetPoint("LEFT", header, "LEFT", inset, 0)
	ui.menu = BuildMenu(menuChip)
	menuChip:SetScript("OnClick", function(self)
		Theme:HideTip(self)
		ui.menu:SetShown(not ui.menu:IsShown())
	end)

	local expandChip = Theme:ChipButton(header, "expand", nil, function()
		return Char().overviewmode and "Show one step at a time" or "Show all steps"
	end)
	expandChip:SetPoint("LEFT", menuChip, "RIGHT", 6, 0)
	expandChip:SetScript("OnClick", function() AP:ToggleOverviewMode() end)
	ui.expandChip = expandChip

	-- Lit while the collector runs; opens its window.
	local collectChip = Theme:ChipButton(header, "record", nil, function()
		return AP.Collector:IsRunning() and "Collecting data -- open data collection" or "Data collection"
	end)
	collectChip:SetPoint("LEFT", expandChip, "RIGHT", 6, 0)
	collectChip:SetScript("OnClick", function() AP:ToggleCollectorFrame() end)
	ui.collectChip = collectChip

	local close = Theme:CloseChip(header, frame)
	Theme:PlaceClose(close, frame, header)
	close:HookScript("OnClick", function() Char().panelopen = false end)

	-- Tab bar.
	local tabbar = CreateFrame("Frame", nil, frame)
	tabbar:SetHeight(G.TABBAR_H)
	tabbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	tabbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	Theme:Strip(tabbar, "tabbg")
	Theme:Divider(tabbar, tabbar, "BOTTOMLEFT", 0, 0)

	local tab = CreateFrame("Button", nil, tabbar)
	tab:SetSize(190, G.TABBAR_H - 5)
	tab:SetPoint("BOTTOMLEFT", tabbar, "BOTTOMLEFT", 8, 0)
	tab.fill = Theme:IsBlizzard() and Theme:Strip(tab, "panel") or Theme:NineSlice(tab, Theme.texture.tabFill, "BACKGROUND", "panel")
	tab.badge = Theme:Badge(tab, "XP", "xp")
	tab.badge:SetPoint("LEFT", tab, "LEFT", 7, 0)
	tab.label = tab:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(tab.label, "body", 11)
	tab.label:SetPoint("LEFT", tab.badge, "RIGHT", 6, 0)
	tab.label:SetPoint("RIGHT", tab, "RIGHT", -18, 0)
	tab.label:SetJustifyH("LEFT")
	tab.label:SetWordWrap(false)
	Theme:TextColor(tab.label, "text")
	local tabClose = Theme:GlyphButton(tab, "close", 8, 14)
	tabClose:SetPoint("RIGHT", tab, "RIGHT", -4, 0)
	tabClose:SetScript("OnClick", function() AP:UnloadGuide() end)
	tab:Hide()
	ui.tab = tab

	local addTab = Theme:GlyphButton(tabbar, "plus", 10, G.TABBAR_H - 9)
	if not Theme:IsBlizzard() then Theme:NineSlice(addTab, Theme.texture.tabBorder, "BORDER", "subtle") end
	addTab:SetPoint("LEFT", tabbar, "LEFT", 8, -1)
	addTab:SetScript("OnClick", function() AP:ShowGuideBrowser() end)
	addTab:HookScript("OnEnter", function(self) Theme:ShowTip(self, "BOTTOM", "Open a guide") end)
	addTab:HookScript("OnLeave", function(self) Theme:HideTip(self) end)
	tab:HookScript("OnShow", function()
		addTab:ClearAllPoints()
		addTab:SetPoint("LEFT", tab, "RIGHT", 6, 0)
	end)
	tab:HookScript("OnHide", function()
		addTab:ClearAllPoints()
		addTab:SetPoint("LEFT", tabbar, "LEFT", 8, -1)
	end)

	-- Nav row.
	local navrow = CreateFrame("Frame", nil, frame)
	navrow:SetHeight(G.NAVROW_H)
	navrow:SetPoint("TOPLEFT", tabbar, "BOTTOMLEFT", 0, 0)
	navrow:SetPoint("TOPRIGHT", tabbar, "BOTTOMRIGHT", 0, 0)
	Theme:Strip(navrow, "panel2")

	local function NavButton(glyph, tipText, delta)
		local b = Theme:GlyphButton(navrow, glyph, 11, 20)
		b:SetScript("OnClick", function()
			if delta > 0 then AP:StepForward() else AP:StepBack() end
		end)
		b:HookScript("OnEnter", function(self) Theme:ShowTip(self, "BOTTOM", tipText) end)
		b:HookScript("OnLeave", function(self) Theme:HideTip(self) end)
		function b:SetEnabled(on)
			self:EnableMouse(on)
			Theme:Tint(self.glyph, on and "textDim" or "subtle")
		end
		return b
	end
	ui.prev = NavButton("arrowLeft", "Previous step", -1)
	ui.prev:SetPoint("LEFT", navrow, "LEFT", 8, 0)
	ui.navStep = navrow:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(ui.navStep, "display", 12)
	ui.navStep:SetPoint("LEFT", ui.prev, "RIGHT", 4, 0)
	Theme:TextColor(ui.navStep, "text")
	ui.next = NavButton("arrowRight", "Next step", 1)
	ui.next:SetPoint("LEFT", ui.navStep, "RIGHT", 4, 0)
	ui.navCount = navrow:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(ui.navCount, "body", 11)
	ui.navCount:SetPoint("RIGHT", navrow, "RIGHT", -14, 0)
	Theme:TextColor(ui.navCount, "textDim")

	-- Progress.
	ui.progress = Theme:ProgressBar(frame, G.PROGRESS_H)
	ui.progress:SetPoint("TOPLEFT", navrow, "BOTTOMLEFT", 0, 0)
	ui.progress:SetPoint("TOPRIGHT", navrow, "BOTTOMRIGHT", 0, 0)

	-- Body.
	local body = CreateFrame("Frame", nil, frame)
	body:SetClipsChildren(true)     -- nothing drawn past the footer, whatever the steps need
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", G.EDGE_L, -G.CHROME_TOP)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -G.EDGE_R, G.FOOTER_H + G.EDGE_B)
	ui.body = body
	body:EnableMouseWheel(true)
	body:SetScript("OnMouseWheel", function(_, delta)
		if not Char().overviewmode then return end
		offset = math.max(0, offset - delta)
		AP:RefreshObjectivePanel()
	end)

	local scroll = Theme:ScrollBar(body, 10)
	scroll:SetPoint("TOPRIGHT", body, "TOPRIGHT", -4, -14)
	scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -4, 14)
	scroll:SetScript("OnValueChanged", function(self, value)
		if self.quiet then return end
		offset = math.floor(value + 0.5)
		AP:RefreshObjectivePanel()
	end)
	scroll:Hide()
	ui.scroll = scroll

	BuildEmpty()

	-- Footer.
	local footer = CreateFrame("Frame", nil, frame)
	footer:SetHeight(G.FOOTER_H)
	footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", G.EDGE_L, G.EDGE_B)
	footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -G.EDGE_R, G.EDGE_B)
	Theme:CapStrip(footer, "panel2", "bottom")
	ui.footerLeft = footer:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(ui.footerLeft, "display", 11)
	ui.footerLeft:SetPoint("LEFT", footer, "LEFT", 14, 0)
	ui.footerRight = footer:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(ui.footerRight, "body", 11)
	ui.footerRight:SetPoint("RIGHT", footer, "RIGHT", -24, 0)
	Theme:TextColor(ui.footerRight, "textDim")
	frame.footer = footer

	frame.grip = BuildGrip()
	AP:SetGuideLocked(Profile().objframelocked)
	AP:SetGuideTransparent(Profile().objframetransparent)

	-- Hooked, not set: the window stack and the Blizzard skin's backdrop hook these too.
	frame:HookScript("OnShow", function(self)
		Char().panelopen = true
		AP:RefreshObjectivePanel()
		Theme:FadeIn(self, 0.3)
		-- Again once the text has been laid out, so wrapped notes have their height.
		C_Timer.After(0, function() AP:RefreshObjectivePanel() end)
	end)
	frame:HookScript("OnSizeChanged", function()
		if ui.empty and ui.empty:IsShown() then ui.empty.text:SetWidth(math.max(100, frame:GetWidth() - 2 * G.EMPTY_PAD - G.EDGE_L - G.EDGE_R)) end
	end)
	AP.Collector:OnChange(function() if frame:IsShown() then AP:RefreshObjectivePanel() end end)
end

AP:OnInit(Build)

--[[ Hiding the guide in dungeons and raids, or in combat (the Appearance page). ]]
local hiddenBy

local function Hide(reason)
	if frame and frame:IsShown() then
		hiddenBy = reason
		frame:Hide()
		Char().panelopen = true   -- it was not the player who closed it
	end
end

local function ShowAgain(reason)
	if frame and hiddenBy == reason then
		hiddenBy = nil
		frame:Show()
	end
end

AP:OnLogin(function()
	if Char().panelopen ~= false then frame:Show() end
	AP:On("PLAYER_REGEN_DISABLED", function() if Profile().hideincombat then Hide("combat") end end)
	AP:On("PLAYER_REGEN_ENABLED", function() ShowAgain("combat") end)
	AP:On("PLAYER_ENTERING_WORLD", function()
		local inside = AP.Compat.InInstance()
		if inside and Profile().hideininstance then
			Hide("instance")
		elseif not inside and Profile().showafterinstance ~= false then
			ShowAgain("instance")
		end
	end)
end)

--- Put every window back where it opens by default, at its default size.
function AP:ResetWindowLayout()
	for _, key in ipairs({ "objframe", "optionsframe", "browserframe", "collectorframe" }) do Theme:ForgetPosition(key) end
	Profile().objframewidth, Profile().objframemaxheight = nil, nil
	Profile().optionswidth, Profile().optionsheight = nil, nil
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint(G.DEFAULT_ANCHOR[1], UIParent, G.DEFAULT_ANCHOR[2], G.DEFAULT_ANCHOR[3], G.DEFAULT_ANCHOR[4])
		frame:SetWidth(G.DEFAULT_WIDTH)
		self:RefreshObjectivePanel()
	end
	if self.ResetCollectorPosition then self:ResetCollectorPosition() end
	if self.ResetConfigPosition then self:ResetConfigPosition() end
	if self.ResetBrowserPosition then self:ResetBrowserPosition() end
	if self.ResetNavArrowPosition then self:ResetNavArrowPosition() end
end
