local _, AP = ...
local L = AP.L
local Theme = AP.Theme

--[[ The guide browser, laid out like Zygor's guide menu and the 1.12 addon's:
	HOME, CURRENT and RECENT along the top; search and the categories down the
	left; a category's guides in the middle; and on the right the guide you
	point at, with the button that opens it.

	There are no Forever guides yet, so every list says so and points at data
	collection, and Home shows what has been collected instead: the XP each
	level needs, as the collector has seen it, and the counts so far.
]]

local DEFAULT_W, DEFAULT_H = 820, 520
local HEADER_H = 30
local SIDE_W, PANE_W = 196, 268
local ROW_H = 26
local MAX_ROWS = 14
local PAD = 14

local frame, ui
local view = { tab = "home", search = "" }

local function Char() return AP.db.char end

local function Text(parent, role, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Theme:SetFont(fs, role, size)
	Theme:TextColor(fs, color or "text")
	fs:SetJustifyH("LEFT")
	return fs
end

local function Fill(f, name, alpha)
	local t = f:CreateTexture(nil, "BACKGROUND")
	t:SetTexture(Theme.texture.solid)
	t:SetAllPoints(f)
	if Theme:IsBlizzard() then t:SetVertexColor(0, 0, 0, 0.3) else Theme:Tint(t, name, alpha) end
	return t
end

local function Open(tab, category)
	view.tab, view.category, view.selected = tab, category, nil
	Char().browsertab = tab or category
	AP:RefreshGuideBrowser()
end

--[[ The header's tabs: HOME, CURRENT, RECENT, an accent line under the one open. ]]
local function HeaderTab(header, key, label)
	local b = CreateFrame("Button", nil, header)
	b:SetHeight(HEADER_H - 2)
	local fs = Text(b, "display", 13, "textDim")
	fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	fs:SetText(label:upper())
	b:SetWidth(math.ceil(fs:GetStringWidth() or 40) + 18)
	local line = b:CreateTexture(nil, "OVERLAY")
	line:SetTexture(Theme.texture.solid)
	line:SetHeight(2)
	line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 0)
	line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 0)
	Theme:Tint(line, "accent")
	b.label, b.line, b.key = fs, line, key
	function b:SetActive(on)
		self.active = on
		Theme:TextColor(self.label, on and "accent" or "textDim")
		self.line:SetShown(on)
	end
	b:SetScript("OnClick", function(self) Open(self.key, nil) end)
	b:SetScript("OnEnter", function(self) if not self.active then Theme:TextColor(self.label, "text") end end)
	b:SetScript("OnLeave", function(self) if not self.active then Theme:TextColor(self.label, "textDim") end end)
	b:SetActive(false)
	return b
end

-- A sidebar row: glyph and label, the accent bar while it is open.
local function SideRow(parent, def, y)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(30)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(Theme.texture.solid)
	hl:SetAllPoints(b)
	Theme:Tint(hl, "text", 0.05)
	local bar = b:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(Theme.texture.solid)
	bar:SetWidth(3)
	bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	Theme:Tint(bar, "accent")
	local g = b:CreateTexture(nil, "ARTWORK")
	g:SetTexture(Theme.glyph[def.glyph])
	g:SetSize(14, 14)
	g:SetPoint("LEFT", b, "LEFT", 14, 0)
	Theme:Tint(g, "textDim")
	b.label = Text(b, "body", 13, "text")
	b.label:SetPoint("LEFT", g, "RIGHT", 10, 0)
	b.label:SetText(def.label)
	b.count = Text(b, "body", 11, "textDim")
	b.count:SetPoint("RIGHT", b, "RIGHT", -12, 0)
	b.key, b.bar, b.glyph = def.key, bar, g
	function b:SetActive(on)
		self.bar:SetShown(on)
		Theme:Tint(self.glyph, on and "accent" or "textDim")
		Theme:TextColor(self.label, on and "text" or "textDim")
	end
	return b
end

-- A Home card: a titled panel.
local function Card(parent, title)
	local c = CreateFrame("Frame", nil, parent)
	if Theme:IsBlizzard() then
		Theme:Backdrop(c, "tooltip")
		c:SetBackdropColor(0, 0, 0, 0.45)
	else
		Theme:NineSlice(c, Theme.texture.tabFill, "BACKGROUND", "panel3")
		Theme:NineSlice(c, Theme.texture.tabBorder, "BORDER", "border")
	end
	c.title = Text(c, "display", 12, "accent")
	c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -10)
	c.title:SetText(title:upper())
	c.lines = {}
	function c:Line(i)
		if not self.lines[i] then
			local left = Text(self, "body", 11, "text")
			left:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -28 - (i - 1) * 16)
			local right = Text(self, "body2", 11, "textDim")
			right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -12, -28 - (i - 1) * 16)
			right:SetJustifyH("RIGHT")
			self.lines[i] = { left = left, right = right }
		end
		return self.lines[i]
	end
	function c:SetLines(list)
		for i, entry in ipairs(list) do
			local line = self:Line(i)
			line.left:SetText(entry[1])
			line.right:SetText(entry[2] or "")
			Theme:TextColor(line.left, entry[3] or "text")
			line.left:Show()
			line.right:Show()
		end
		for i = #list + 1, #self.lines do
			self.lines[i].left:Hide()
			self.lines[i].right:Hide()
		end
	end
	return c
end

--[[ The list: a row per guide. ]]
local function ListRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(Theme.texture.solid)
	hl:SetAllPoints(row)
	Theme:Tint(hl, "text", 0.05)
	row.badge = Theme:Badge(row, "XP", "xp")
	row.badge:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.label = Text(row, "body", 12, "text")
	row.label:SetPoint("LEFT", row.badge, "RIGHT", 8, 0)
	row.levels = Text(row, "body2", 11, "textDim")
	row.levels:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row:SetScript("OnClick", function(self)
		view.selected = self.guide
		AP:RefreshGuideBrowser()
	end)
	row:SetScript("OnDoubleClick", function(self)
		if self.guide then AP:LoadGuide(self.guide.name) end
	end)
	return row
end

local function Build()
	frame = CreateFrame("Frame", "AegisPathfinderGuideBrowser", UIParent)
	AP.guidebrowserframe = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetSize(DEFAULT_W, DEFAULT_H)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	Theme:Panel(frame, "panel")
	frame:Hide()
	tinsert(UISpecialFrames, "AegisPathfinderGuideBrowser")
	ui = {}
	frame.ui = ui

	local header = Theme:Chrome(frame, nil, Theme:PositionSaver("browserframe"), "Guides")
	Theme:RestorePosition(frame, "browserframe")
	ui.tabs = {}
	for i, def in ipairs({ { "home", "Home" }, { "current", "Current" }, { "recent", "Recent" } }) do
		local b = HeaderTab(header, def[1], def[2])
		if i == 1 then b:SetPoint("LEFT", header, "LEFT", 10, 0) else b:SetPoint("LEFT", ui.tabs[i - 1], "RIGHT", 4, 0) end
		ui.tabs[i] = b
	end
	local inset = Theme:IsBlizzard() and 6 or 1

	-- The sidebar: search, the categories, and Options at the foot.
	local side = CreateFrame("Frame", nil, frame)
	side:SetWidth(SIDE_W)
	side:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -HEADER_H - inset)
	side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
	if Theme:IsBlizzard() then Fill(side, "panel3") else Theme:CapStrip(side, "panel3", "bottom") end
	local edge = side:CreateTexture(nil, "BORDER")
	edge:SetTexture(Theme.texture.solid)
	edge:SetWidth(1)
	edge:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
	edge:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
	Theme:Tint(edge, "border")

	local search = CreateFrame("EditBox", nil, side)
	search:SetHeight(26)
	search:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -12)
	search:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -12)
	search:SetAutoFocus(false)
	search:SetTextInsets(24, 6, 0, 0)
	search:SetMaxLetters(40)
	search:SetFontObject(ChatFontNormal)
	Theme:SetFont(search, "body", 12)
	if Theme:IsBlizzard() then
		Theme:Backdrop(search, "tooltip")
		search:SetBackdropColor(0, 0, 0, 0.8)
	else
		Theme:NineSlice(search, Theme.texture.tabFill, "BACKGROUND", "panel2")
		Theme:NineSlice(search, Theme.texture.tabBorder, "BORDER", "subtle")
	end
	local lens = search:CreateTexture(nil, "ARTWORK")
	lens:SetTexture(Theme.glyph.search)
	lens:SetSize(12, 12)
	lens:SetPoint("LEFT", search, "LEFT", 7, 0)
	Theme:Tint(lens, "textDim")
	local hint = Text(search, "body", 12, "textDim")
	hint:SetPoint("LEFT", search, "LEFT", 24, 0)
	hint:SetText("Search guides")
	local function ShowHint() hint:SetShown(search:GetText() == "" and not search:HasFocus()) end
	search:SetScript("OnTextChanged", function(self)
		ShowHint()
		view.search = self:GetText() or ""
		if view.search ~= "" then view.tab, view.category = nil, "search" end
		AP:RefreshGuideBrowser()
	end)
	search:SetScript("OnEditFocusGained", ShowHint)
	search:SetScript("OnEditFocusLost", ShowHint)
	search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	ui.search = search

	ui.categories = {}
	for i, def in ipairs(AP.CATEGORIES) do
		local row = SideRow(side, def, -50 - (i - 1) * 30)
		row:SetScript("OnClick", function(self) Open(nil, self.key) end)
		ui.categories[i] = row
	end
	local options = SideRow(side, { key = "options", label = "Options", glyph = "gear" }, 0)
	options:ClearAllPoints()
	options:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 10)
	options:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 10)
	options:SetScript("OnClick", function() AP:ToggleConfigPanel() end)
	options:SetActive(false)

	-- The right pane: the guide pointed at, or the logo.
	local pane = CreateFrame("Frame", nil, frame)
	pane:SetWidth(PANE_W)
	pane:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -HEADER_H - inset)
	pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	Fill(pane, "panel2", 0.6)
	local logo = pane:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(Theme.texture.logo)
	logo:SetSize(128, 128)
	logo:SetPoint("TOP", pane, "TOP", 0, -24)
	local paneTitle = Text(pane, "display", 16, "text")
	paneTitle:SetPoint("TOP", logo, "BOTTOM", 0, -12)
	paneTitle:SetJustifyH("CENTER")
	paneTitle:SetWidth(PANE_W - 2 * PAD)
	local paneText = Theme:FinePrint(pane, PANE_W - 2 * PAD)
	paneText:SetPoint("TOP", paneTitle, "BOTTOM", 0, -8)
	paneText:SetJustifyH("CENTER")
	local paneButton = Theme:PanelButton(pane, L.START_COLLECTING, PANE_W - 2 * PAD, 26)
	paneButton:SetPoint("BOTTOM", pane, "BOTTOM", 0, PAD)
	ui.pane, ui.paneTitle, ui.paneText, ui.paneButton = pane, paneTitle, paneText, paneButton

	-- The middle: a title bar, then the list -- or the Home cards.
	local middle = CreateFrame("Frame", nil, frame)
	middle:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	middle:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", 0, 0)
	ui.middle = middle
	local title = Text(middle, "display", 16, "text")
	title:SetPoint("TOPLEFT", middle, "TOPLEFT", PAD, -14)
	ui.title = title
	local sub = Text(middle, "body", 11, "textDim")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	ui.sub = sub

	local list = CreateFrame("Frame", nil, middle)
	list:SetPoint("TOPLEFT", middle, "TOPLEFT", 0, -56)
	list:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", 0, 0)
	ui.list, ui.rows = list, {}
	for i = 1, MAX_ROWS do ui.rows[i] = ListRow(list, i) end
	local empty = Theme:FinePrint(list, DEFAULT_W - SIDE_W - PANE_W - 2 * PAD)
	empty:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -8)
	ui.empty = empty
	local emptyButton = Theme:PanelButton(list, L.OPEN_COLLECTOR, 160, 26)
	emptyButton:SetPoint("TOPLEFT", empty, "BOTTOMLEFT", 0, -12)
	emptyButton:SetScript("OnClick", function() AP:ToggleCollectorFrame() end)
	ui.emptyButton = emptyButton

	-- Home: what has been collected, in place of the guides there are not yet.
	local home = CreateFrame("Frame", nil, middle)
	home:SetPoint("TOPLEFT", middle, "TOPLEFT", PAD, -56)
	home:SetPoint("BOTTOMRIGHT", middle, "BOTTOMRIGHT", -PAD, PAD)
	ui.home = home
	local mid = DEFAULT_W - SIDE_W - PANE_W - 2 * PAD - 2 * inset
	ui.recentCard = Card(home, "Your guides")
	ui.recentCard:SetPoint("TOPLEFT", home, "TOPLEFT", 0, 0)
	ui.recentCard:SetSize(mid, 110)
	ui.levelCard = Card(home, "XP to level, as collected")
	ui.levelCard:SetPoint("TOPLEFT", ui.recentCard, "BOTTOMLEFT", 0, -10)
	ui.levelCard:SetSize(mid, 300)

	frame:HookScript("OnShow", function(self)
		AP:RefreshGuideBrowser()
		Theme:FadeIn(self, 0.2)
	end)
	frame.fadeTo = AP.db.profile.browseropacity or 1
	AP.Collector:OnChange(function() if frame:IsShown() then AP:RefreshGuideBrowser() end end)
	-- It opens where it was left: a header tab, or a category.
	local saved = Char().browsertab or "home"
	if saved == "home" or saved == "current" or saved == "recent" then
		view.tab = saved
	else
		view.tab, view.category = nil, saved
	end
end

-- The XP each level needs, from the collected data: a line per level.
local function LevelLines(limit)
	local levels = AP.Collector:GetData() and AP.Collector:GetData().levels or {}
	local keys = {}
	for level in pairs(levels) do keys[#keys + 1] = level end
	table.sort(keys)
	local lines = {}
	for _, level in ipairs(keys) do
		local entry = levels[level]
		local xp = entry.xpMax and entry.xpMax.last
		local spread = entry.xpMax and entry.xpMax.min ~= entry.xpMax.max and " (varies)" or ""
		local time = entry.seconds and entry.seconds.min and AP.Extras and AP.Extras.Duration(entry.seconds.min) or nil
		lines[#lines + 1] = { "Level " .. level .. (time and ("  |cff8f8f86" .. time .. "|r") or ""),
			(xp and AP.Extras and AP.Extras.Thousands(xp) or tostring(xp or "?")) .. " XP" .. spread }
	end
	if #lines == 0 then lines[1] = { "Nothing collected yet.", "", "textDim" } end
	while #lines > limit do table.remove(lines, 1) end
	return lines
end

local function GuideLevels(guide)
	if guide.minLevel and guide.maxLevel then return guide.minLevel .. "-" .. guide.maxLevel end
	return ""
end

function AP:RefreshGuideBrowser()
	if not frame then return end
	for _, tab in ipairs(ui.tabs) do tab:SetActive(tab.key == view.tab) end
	for _, row in ipairs(ui.categories) do
		row:SetActive(view.tab == nil and row.key == view.category)
		row.count:SetText(#self:GetGuides(row.key))
	end

	-- Which guides the middle lists.
	local guides, title, sub = {}, "", ""
	if view.tab == "home" then
		title, sub = "Home", "What Pathfinder has for you, and what it has collected"
	elseif view.tab == "current" then
		local guide = self:GetCurrentGuide()
		guides = guide and { guide } or {}
		title, sub = "Current", "The guide you are on"
	elseif view.tab == "recent" then
		for _, name in ipairs(Char().recentguides or {}) do
			if self.guides[name] then guides[#guides + 1] = self.guides[name] end
		end
		title, sub = "Recent", "The guides you opened last"
	elseif view.category == "search" then
		local needle = view.search:lower()
		for _, guide in ipairs(self:GetGuides(nil)) do
			if guide.name:lower():find(needle, 1, true) then guides[#guides + 1] = guide end
		end
		title, sub = "Search", string.format("Guides matching \"%s\"", view.search)
	else
		guides = self:GetGuides(view.category)
		for _, def in ipairs(self.CATEGORIES) do
			if def.key == view.category then title = def.label end
		end
		sub = "Guides for your faction, by level"
	end
	ui.title:SetText(title:upper())
	ui.sub:SetText(sub)

	local home = view.tab == "home"
	ui.home:SetShown(home)
	ui.list:SetShown(not home)
	if home then
		local recent = {}
		for _, name in ipairs(Char().recentguides or {}) do
			if self.guides[name] and #recent < 4 then recent[#recent + 1] = { name, GuideLevels(self.guides[name]) } end
		end
		if #recent == 0 then
			recent[1] = { L.NO_GUIDES_TITLE .. " -- WoW: Forever is new.", "", "textDim" }
			recent[2] = { "Turn on data collection to help write them.", "", "textDim" }
		end
		ui.recentCard:SetLines(recent)
		ui.levelCard:SetLines(LevelLines(16))
	else
		for i, row in ipairs(ui.rows) do
			local guide = guides[i]
			row.guide = guide
			if guide then
				row.label:SetText(guide.name)
				row.levels:SetText(GuideLevels(guide))
				row.badge:SetKind(guide.category == "dungeons" and "dg" or guide.category == "class" and "cl"
					or guide.category == "professions" and "pf" or "xp")
				Theme:TextColor(row.label, view.selected == guide and "accent" or "text")
				row:Show()
			else
				row:Hide()
			end
		end
		local none = #guides == 0
		ui.empty:SetShown(none)
		ui.emptyButton:SetShown(none)
		ui.empty:SetText(self:HasGuides() and "Nothing here yet." or L.NO_GUIDES_BODY)
	end

	-- The right pane.
	local selected = view.selected
	local running = self.Collector:IsRunning()
	if selected then
		ui.paneTitle:SetText(selected.name)
		ui.paneText:SetText(string.format("Levels %s. %d steps.", GuideLevels(selected), #selected.steps))
		ui.paneButton:SetText("Open guide")
		ui.paneButton:SetActive(false)
		ui.paneButton:SetScript("OnClick", function() AP:LoadGuide(selected.name) end)
	else
		ui.paneTitle:SetText(L.TITLE)
		ui.paneText:SetText((running and L.COLLECTOR_ON or L.COLLECTOR_OFF) .. ". " .. self.Collector:StatsText() .. ".")
		ui.paneButton:SetText(running and L.STOP_COLLECTING or L.START_COLLECTING)
		ui.paneButton:SetActive(running)
		ui.paneButton:SetScript("OnClick", function() AP.Collector:Toggle() end)
	end
end

function AP:ShowGuideBrowser()
	if frame then frame:Show() end
end

function AP:ToggleGuideBrowser()
	if frame then frame:SetShown(not frame:IsShown()) end
end

--- The browser's opacity, on the Appearance page.
function AP:SetBrowserOpacity(v)
	v = math.max(0.4, math.min(1, v or 1))
	self.db.profile.browseropacity = v
	if frame then
		frame.fadeTo = v
		if frame:IsShown() then frame:SetAlpha(v) end
	end
	return v
end

function AP:ResetBrowserPosition()
	if not frame then return end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

AP:OnInit(Build)
