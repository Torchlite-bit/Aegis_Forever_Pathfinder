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

	There are no guides for Forever yet, so the body's usual state is the empty
	one: what Pathfinder is waiting for, and the button that starts collecting
	the data guides will be written from. The ● chip lights while it collects.

	Rows follow the concept's two models: most steps are a `.zrow` (a dot, an
	action glyph, the title and the note under it); ACCEPT and TURNIN steps
	become a full-width `.zband` once current or done, red while outstanding and
	green once satisfied.
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
	-- Reloads through the secure button over it (Theme:OfferReload); a click that reaches the row was in combat.
	{ label = "Reload", glyph = "reload", reload = true, run = function() Theme:ReloadFallback() end },
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
	if item.reload then Theme:OfferReload(row) end
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
		for _, row in ipairs(self.rows) do
			if row.item.key then row:SetChecked(Profile()[row.item.key]) end
		end
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

	local band = Theme:Band(row, G.ROWHEIGHT)
	band:SetAllPoints(row)
	band:EnableMouse(false)
	band:Hide()
	row.band = band

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
	Theme:SetFont(row.band.label, "body", math.floor(12 * TextScale() + 0.5))
end

local function PaintRow(row, guide, index, current, focus)
	local step = guide.steps[index]
	row.step, row.data = index, step
	SizeRowFonts(row)
	local done = AP:IsStepDone(guide.name, index)
	local isCurrent = index == current
	local bandable = (step.action == "ACCEPT" or step.action == "TURNIN") and (done or isCurrent)
	row.band:SetShown(bandable)
	for _, region in ipairs({ row.check, row.icon, row.title, row.note }) do region:SetShown(not bandable) end
	if bandable then
		row.band.icon:SetTexture(Theme.actionIconByName[step.action])
		row.band.label:SetText(step.title or step.action)
		row.band:SetDone(done)
	else
		row.check:SetChecked(done)
		row.check:SetAutoEligible(step.qid ~= nil and (step.action == "ACCEPT" or step.action == "TURNIN"
			or step.action == "COMPLETE"))
		Theme:SetActionIcon(row.icon, ({ ACCEPT = "A", TURNIN = "T", COMPLETE = "C", RUN = "R", KILL = "K", USE = "U",
			NOTE = "N", HEARTH = "H", SETHEARTH = "h", FLY = "F", GETFLIGHTPOINT = "f", BUY = "B", BOAT = "b",
			GRIND = "G", TRAIN = "t", DIE = "D", PET = "P", MAP = "R" })[step.action])
		row.title:SetText(step.title or step.action)
		row.note:SetText(step.note or "")
		row.note:SetWordWrap(focus)
	end
	row.wash:SetShown(isCurrent)
	row.bar:SetShown(isCurrent)
	row:SetAlpha(done and not isCurrent and 0.55 or 1)
	row:Show()
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

local function PaintSteps(guide, current)
	local overview = Char().overviewmode
	local count = #guide.steps
	local rowH = math.floor(G.ROWHEIGHT * TextScale() + 0.5)
	if not overview then
		-- Focus: the step you are on, its note in full.
		for i = 2, #rows do rows[i]:Hide() end
		local row = rows[1] or NewRow(1)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, 0)
		row:SetPoint("RIGHT", ui.body, "RIGHT", 0, 0)
		if current > count then
			row:Hide()
			return rowH
		end
		PaintRow(row, guide, current, current, true)
		local noteH = row.note:IsShown() and (row.note:GetStringHeight() or 0) or 0
		local h = math.max(rowH, 31 + noteH + 10)
		row:SetHeight(h)
		ui.scroll:Hide()
		return h
	end
	-- Overview: the whole list, scrolled by step.
	local cap = AP:GetPanelCap() - G.CHROME_TOP - G.FOOTER_H
	local shown = math.min(count, VisibleRows(cap))
	offset = math.max(0, math.min(offset, count - shown))
	for i = 1, shown do
		local row = rows[i] or NewRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -(i - 1) * rowH)
		row:SetPoint("RIGHT", ui.scroll, "LEFT", -4, 0)
		row:SetHeight(rowH)
		PaintRow(row, guide, offset + i, current, false)
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
	local current = guide and self:GetCurrentStep() or 0
	local count = guide and #guide.steps or 0
	local running = self.Collector:IsRunning()

	-- Header chips that show state.
	ui.expandChip:SetActive(Char().overviewmode)
	ui.collectChip:SetActive(running)

	-- Tab bar: the guide you are on, or nothing yet.
	if guide then
		ui.tab:Show()
		ui.tab.label:SetText(guide.name)
		ui.tab.badge:SetKind(guide.category == "dungeons" and "dg" or guide.category == "class" and "cl"
			or guide.category == "professions" and "pf" or "xp", nil)
	else
		ui.tab:Hide()
	end

	-- Nav row and progress.
	local done = 0
	if guide then
		for i = 1, count do
			if self:IsStepDone(guide.name, i) then done = done + 1 end
		end
	end
	ui.navStep:SetText(guide and string.format("STEP %d", math.min(current, count)) or "NO GUIDE")
	ui.navCount:SetText(guide and string.format("%d / %d", done, count) or "")
	ui.prev:SetEnabled(guide ~= nil)
	ui.next:SetEnabled(guide ~= nil)
	ui.progress:SetProgress(count > 0 and done / count or 0)
	ui.progress:SetShown(Profile().showprogress ~= false)

	-- Body.
	local bodyH
	if guide then
		ui.empty:Hide()
		bodyH = PaintSteps(guide, current)
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
	offset = math.max(0, (self:GetCurrentStep() or 1) - 3)
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
	ui = {}
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
			local guide = AP:GetCurrentGuide()
			if not guide then return end
			local current = AP:GetCurrentStep()
			if delta > 0 then
				AP:SetStepDone(current, true)
			elseif current > 1 then
				AP:SetStepDone(current - 1, false)
			end
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
end
