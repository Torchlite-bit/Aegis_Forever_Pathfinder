local _, AP = ...
local L = AP.L
local Theme = AP.Theme

--[[ OptionsFrame.lua -- the concept's #options panel, in pages.

	Categories down the left, as Zygor's options and the 1.12 addon's have
	them; the page picked on the right, scrolling when it is taller than the
	window. The pages are the 1.12 addon's that have something to set without a
	guide, and one new one:

	  Data Collection  starting and stopping, Automatically run, export, clear
	  Appearance       theme (the Blizzard skin among them), switch colours,
	                   window scale, the guide window, hiding it, the minimap
	  Navigation       the step's map pin and arrow
	  Automation       quests, selling greys, repairing
	  Extras           chat lines, reputation detail, level-up announcements
	  Maintenance      windows, rescanning
	  About            version and credits

	The 1.12 addon's Route, Dungeons, Filters, Step Display, Action Buttons,
	Maps and Gear pages set what its guides and gear data do; they come back
	with the guides (docs/feature-inventory.md).

	Every control registers how to show its saved value, and RefreshConfigPanel
	runs them all, so a setting changed elsewhere (the guide's ≡ menu, a slash
	command) shows here the next time the window is drawn.
]]

local PANE_W, HEIGHT = 396, 560
local NAV_W, NAV_ROW_H = 150, 30
local WIDTH = PANE_W + NAV_W
local HEADER_H, SUBHEAD_H = 30, 18
local CHROME_TOP = HEADER_H + SUBHEAD_H
local PAD_X, PAD_TOP, PAD_BOTTOM = 14, 12, 16
local SCROLL_W = 10
local BODY_W = PANE_W - PAD_X * 2 - SCROLL_W - 4
local SECTION_GAP = 16
local HEADER_GAP = 7
local SUB_INDENT = 24

local frame

local function Char() return AP.db.char end
local function Profile() return AP.db.profile end

local function TextHeight(fs, width)
	local sw = fs:GetStringWidth() or 0
	local lines = sw <= width and 1 or math.ceil(sw / (width * 0.9))
	return math.max(fs:GetStringHeight() or 0, lines * 13)
end

local function Percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

--[[ The layout kit: pages laid out top to bottom with a running cursor. ]]
local function Kit(holder)
	local kit = { pages = {}, refreshers = {}, dropdowns = {} }
	local body, y

	function kit.page(name)
		if body then body.contentHeight = y + PAD_BOTTOM end
		body = CreateFrame("Frame", nil, holder)
		body:SetWidth(BODY_W)
		body:SetHeight(1)
		body:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		body:Hide()
		body.pageName = name
		kit.pages[#kit.pages + 1] = body
		y = 0
	end
	function kit.finish()
		if body then body.contentHeight = y + PAD_BOTTOM end
	end
	function kit.body() return body end
	function kit.place(region, height, gap, indent)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", body, "TOPLEFT", indent or 0, -y)
		y = y + (type(height) == "function" and height(BODY_W) or height) + (gap or 0)
	end
	function kit.space(n) y = y + n end
	function kit.section(title)
		local h = Theme:SectionHeader(body, title, BODY_W)
		kit.place(h, 20, HEADER_GAP)
		return h
	end
	function kit.note(text)
		local fs = Theme:FinePrint(body, BODY_W)
		fs:SetText(text or "")
		kit.place(fs, function(w) return TextHeight(fs, w) end, 0)
		return fs
	end
	function kit.refresh(fn) kit.refreshers[#kit.refreshers + 1] = fn end

	--- A switch for db[store][key]; `opts.parent` sets it in under, and holds it off with, another
	--- key; `opts.defaultOn` reads nil as on; `after(on)` updates what it shows.
	function kit.switch(store, key, label, after, opts)
		opts = opts or {}
		local indent = opts.parent and SUB_INDENT or nil
		local sw = Theme:Switch(body, label, function(on)
			AP.db[store][key] = on
			if after then after(on) end
			AP:RefreshConfigPanel()
		end)
		kit.place(sw, function(w) return sw:Fit(w - (indent or 0)) end, 8, indent)
		kit.refresh(function()
			local value = AP.db[store][key]
			if value == nil and opts.defaultOn then value = true end
			sw:SetOn(value)
			if opts.parent then sw:SetLocked(not AP.db[store][opts.parent]) end
		end)
		return sw
	end
	--- A switch whose value comes from `get()` and goes to `set(on)`.
	function kit.toggle(label, get, set, indent)
		local sw = Theme:Switch(body, label, function(on)
			set(on)
			AP:RefreshConfigPanel()
		end)
		kit.place(sw, function(w) return sw:Fit(w - (indent or 0)) end, 8, indent)
		kit.refresh(function() sw:SetOn(get()) end)
		return sw
	end
	function kit.slider(label, lo, hi, step, get, set, indent, held)
		local row = Theme:Slider(body, label, lo, hi, step, set, Percent)
		kit.place(row, function(w) return row:Fit(w - (indent or 0)) end, 6, indent)
		kit.refresh(function()
			row:SetValue(get())
			if held then
				local hold = held()
				row:SetAlpha(hold and 0.45 or 1)
				row.slider:EnableMouse(not hold)
			end
		end)
		return row
	end
	function kit.label(text)
		local fs = body:CreateFontString(nil, "OVERLAY")
		Theme:SetFont(fs, "body", 13)
		Theme:TextColor(fs, "text")
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		kit.place(fs, 16, 6)
		return fs
	end
	function kit.dropdown(label, items, get, set)
		if label then kit.label(label) end
		local d = Theme:Dropdown(body, BODY_W, set)
		d:SetItems(items)
		kit.place(d, 30, 8)
		kit.dropdowns[#kit.dropdowns + 1] = d
		kit.refresh(function() d:SetValue(get()) end)
		return d
	end
	--- Buttons side by side: { { label, width, onClick }, ... }.
	function kit.buttons(defs)
		local row = CreateFrame("Frame", nil, body)
		row:SetSize(BODY_W, 26)
		local x = 0
		local made = {}
		for _, def in ipairs(defs) do
			local b = Theme:PanelButton(row, def[1], def[2], 26)
			b:SetPoint("LEFT", row, "LEFT", x, 0)
			b:SetScript("OnClick", def[3])
			x = x + def[2] + 6
			made[#made + 1] = b
		end
		kit.place(row, 26, 8)
		return unpack(made)
	end
	--- A label over check boxes, two to a row, for db.char keys; `{ key, label, offByDefault }`.
	function kit.boxes(label, defs)
		local rows = math.ceil(#defs / 2)
		local h = 17 + rows * 26
		local holderFrame = CreateFrame("Frame", nil, body)
		holderFrame:SetSize(BODY_W, h)
		local fs = holderFrame:CreateFontString(nil, "OVERLAY")
		Theme:SetFont(fs, "body", 13)
		Theme:TextColor(fs, "text")
		fs:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
		fs:SetText(label)
		for i, def in ipairs(defs) do
			local key = def[1]
			local box = Theme:Checkbox(holderFrame, def[2], function(on) Char()[key] = on end)
			box:Fit()
			box:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", ((i - 1) % 2) * 170, -(4 + math.floor((i - 1) / 2) * 26))
			kit.refresh(function()
				local value = Char()[key]
				if value == nil then value = not def[3] end
				box:SetOn(value)
			end)
		end
		kit.place(holderFrame, h, 4)
	end
	return kit
end

--[[ The pages ]]

local Pages = {}

function Pages.DataCollection(k)
	local C = AP.Collector
	k.page("Data Collection")
	k.section("Collecting")
	local toggle = k.buttons({ { L.START_COLLECTING, 200, function() C:Toggle() end },
		{ "Open window", 140, function() AP:ToggleCollectorFrame() end } })
	k.refresh(function()
		toggle:SetText(C:IsRunning() and L.STOP_COLLECTING or L.START_COLLECTING)
		toggle:SetActive(C:IsRunning())
	end)
	k.toggle(L.COLLECTOR_AUTO, function() return C:IsAuto() end, function(on) C:SetAuto(on) end)
	k.note(L.COLLECTOR_AUTO_NOTE .. " A new character takes the last choice made here, on any character.")
	k.space(SECTION_GAP)
	k.section("What it writes down")
	k.note("Every quest you are offered, pick up and hand in: its text and level; who gave it and where, "
		.. "and who took it back; where its objectives moved on; the client's own map points for it; and "
		.. "what it gave -- XP at your level, money, items, spells and reputation. And the XP each level "
		.. "needs, with how long it took when the whole level was seen.")
	k.space(6)
	k.note("It stays in your saved variables until you export it: nothing is sent anywhere. Characters "
		.. "are written as race, class and faction, never by name.")
	k.space(SECTION_GAP)
	k.section("Your data")
	k.buttons({ { L.COLLECTOR_EXPORT, 120, function() AP:ShowExport() end },
		{ L.COLLECTOR_CLEAR, 120, function() StaticPopup_Show("AEGISPATHFINDER_CLEAR_DATA") end } })
	local stats = k.note("")
	k.refresh(function()
		local counts = C:Counts()
		stats:SetText(string.format(L.COLLECTOR_STATS, counts.quests, counts.turnedIn, counts.levels) .. " so far.")
	end)
	k.space(SECTION_GAP)
end

function Pages.Appearance(k)
	k.page("Appearance")
	k.section("Theme")
	local items = {}
	for _, def in ipairs(Theme.THEMES) do items[#items + 1] = { value = def.key, label = def.label } end
	k.dropdown(nil, items, function() return AP:GetTheme() end, function(key) AP:SetTheme(key) end)
	local themeNote = k.note("")
	k.refresh(function()
		local def = Theme.themeByKey[AP:GetTheme()]
		themeNote:SetText(def and def.note or "")
	end)
	k.space(10)
	k.dropdown("Switches", { { value = "theme", label = "In the theme's colours" },
		{ value = "redgreen", label = "Green when on, red when off" } },
		function() return Profile().switchcolours or "theme" end, function(v) AP:SetSwitchColours(v) end)
	k.slider("Window scale", Theme.SCALE_MIN, Theme.SCALE_MAX, Theme.SCALE_STEP,
		function() return Profile().windowscale or 1 end, function(v) AP:SetWindowScale(v) end)
	k.space(SECTION_GAP - 6)
	k.section("Guide window")
	k.toggle("Lock window", function() return Profile().objframelocked end, function(on) AP:SetGuideLocked(on) end)
	k.toggle("Transparency", function() return Profile().objframetransparent end,
		function(on) AP:SetGuideTransparent(on) end)
	k.slider("Guide window opacity", 0.2, 1, 0.05, function() return Profile().objframeopacity or 0.5 end,
		function(v) AP:SetGuideOpacity(v) end, SUB_INDENT, function() return not Profile().objframetransparent end)
	k.slider("Guide browser opacity", 0.4, 1, 0.05, function() return Profile().browseropacity or 1 end,
		function(v) AP:SetBrowserOpacity(v) end)
	k.slider("Step text size", 0.8, 1.4, 0.05, function() return Profile().steptextsize or 1 end,
		function(v) AP:SetStepTextSize(v) end)
	k.toggle("Show the progress bar", function() return Profile().showprogress ~= false end,
		function(on) AP:SetGuideProgressShown(on) end)
	k.note("Lock window and Transparency are in the menu at the guide's top left too.")
	k.space(SECTION_GAP)
	k.section("Hiding the guide")
	k.switch("profile", "hideininstance", "Hide the guide in dungeons and raids")
	k.switch("profile", "showafterinstance", "Show it again when I leave", nil,
		{ parent = "hideininstance", defaultOn = true })
	k.switch("profile", "hideincombat", "Hide the guide in combat")
	k.space(SECTION_GAP - 8)
	k.section("Minimap")
	k.switch("char", "showminimapbutton", "Minimap button", function() AP:UpdateMinimapButton() end)
	k.space(SECTION_GAP - 8)
end

function Pages.Navigation(k)
	k.page("Navigation")
	k.section("Waypoints")
	k.switch("char", "waypoints", "Put the step on the map with the game's own pin and arrow", nil,
		{ defaultOn = true })
	k.note("Forever's map pins and the arrow at the top of the screen, the ones you place by "
		.. "ctrl-clicking the map. Pathfinder sets one for each step that says where, once there are guides.")
	k.space(SECTION_GAP)
end

function Pages.Automation(k)
	k.page("Automation")
	k.section("Quests")
	k.switch("char", "autoquest", "Accept and turn in quests")
	k.switch("char", "autogossip", "Pick quests from an NPC's list", nil, { parent = "autoquest", defaultOn = true })
	k.note("Hold Shift as you talk to an NPC and nothing happens by itself. No grey quests, never "
		.. "a reward to choose from (the choice is yours), and two places are always left in your quest log.")
	k.space(SECTION_GAP)
	k.section("Inventory")
	k.switch("char", "sellbutton", "\"Sell greys\" button on the vendor window", function()
		if AP.Automation then AP.Automation:PlaceButton() end
	end, { defaultOn = true })
	k.switch("char", "autosell", "Sell greys automatically")
	k.dropdown("Repair automatically", { { value = "off", label = "Don't repair" },
		{ value = "own", label = "With my own money" }, { value = "guild", label = "Guild money first, then my own" } },
		function() return Char().autorepair or "off" end, function(v) Char().autorepair = v end)
	k.space(SECTION_GAP)
end

function Pages.Extras(k)
	k.page("Extras")
	k.section("Chat")
	k.switch("char", "chatmessages", "Show Pathfinder chat messages", nil, { defaultOn = true })
	k.note("Off, the routine lines stay out of your chat: the load message, greys sold, the "
		.. "collector starting. Errors and replies to what you type still show.")
	k.space(10)
	k.switch("char", "repdetail", "Show detailed reputation gains")
	k.note("When a reputation goes up, where it stands and how far it is to the next rank: "
		.. "\"Stormwind +25: Honored 4,350 / 12,000, 7,650 to Revered\".")
	k.space(SECTION_GAP)
	k.section("Level-ups")
	k.boxes("Announce level-ups to:", { { "levelemote", "Emote" }, { "levelparty", "Party chat", true },
		{ "levelguild", "Guild chat", true } })
	k.note("\"Pathfinder: I just leveled up from 22 to 23! (2 hours 1 minute)\". The time is how long "
		.. "you spent at the level, when the collector saw all of it. Nothing goes to a party or guild you are not in.")
	k.space(SECTION_GAP)
end

function Pages.Maintenance(k)
	k.page("Maintenance")
	k.section("Windows")
	k.buttons({ { "Reset windows", 140, function() AP:ResetWindowLayout() end },
		{ "Show the guide", 140, function() AP.objectiveframe:Show() end } })
	k.note("Puts every Pathfinder window back where it opens, at its own size. /apg resetpanels does the same.")
	k.space(SECTION_GAP)
	k.section("Quest log")
	k.buttons({ { "Rescan quest log", 160, function()
		if AP.Collector:IsRunning() then AP.Collector:ReadQuestLog() end
		if AP.ScanGuide then AP:ScanGuide() end
		AP:Print("Quest log read again.")
	end } })
	k.note("Reads the quest log again: the guide's steps, and, while it collects, the quests' objectives.")
	k.space(SECTION_GAP)
end

function Pages.About(k)
	k.page("About")
	k.section("About")
	k.note(string.format("%s v%s for WoW: Forever -- quote it in bug reports.", AP.title, AP.version))
	k.space(6)
	k.note("A port of Aegis: Pathfinder, the Turtle WoW leveling guide, to the Forever client: "
		.. "the same windows and settings, rebuilt on the modern interface API, waiting for its guides.")
	k.space(6)
	k.note("Built on other people's work: TourGuide (Tekkub), VanillaGuide (isalcedo), VanillaGuide-Plus "
		.. "(NostalgiaGeek, Brues), the Aegis: Pathfinder contributors, and what the Aegis: Forever "
		.. "Instance Journal learned about this client. Fonts: Rajdhani and Inter (SIL Open Font License).")
	k.space(SECTION_GAP)
end

local PAGE_ORDER = { "DataCollection", "Appearance", "Navigation", "Automation", "Extras", "Maintenance", "About" }

--[[ The window ]]

local function Build()
	frame = CreateFrame("Frame", "AegisPathfinderOptions", UIParent)
	AP.optionsframe = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("TOPRIGHT", AP.objectiveframe, "TOPLEFT", -8, 0)
	Theme:Panel(frame, "panel")
	frame:Hide()
	Theme:Chrome(frame, "Config", Theme:PositionSaver("optionsframe"))
	tinsert(UISpecialFrames, "AegisPathfinderOptions")
	local inset = Theme:IsBlizzard() and 6 or 0

	-- The header's ☰ brings the guide forward, as the concept's "Back" does.
	local back = Theme:ChipButton(frame.header, "menu", nil, "Back to the guide")
	back:SetPoint("LEFT", frame.header, "LEFT", Theme:IsBlizzard() and 2 or 8, 0)
	back:SetScript("OnClick", function()
		AP.objectiveframe:Show()
		Theme:BringToFront(AP.objectiveframe)
	end)

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_W + PAD_X, -(CHROME_TOP + PAD_TOP + inset))
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD_X + SCROLL_W), PAD_BOTTOM + inset)
	local holder = CreateFrame("Frame", nil, scroll)
	holder:SetSize(BODY_W, 1)
	scroll:SetScrollChild(holder)

	local bar = Theme:ScrollBar(frame, SCROLL_W)
	bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6 - inset, -(CHROME_TOP + PAD_TOP + SCROLL_W + inset))
	bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6 - inset, PAD_BOTTOM + SCROLL_W + inset)
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)
	bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value or 0) end)
	bar.up:SetScript("OnClick", function() bar:SetValue(math.max(0, bar:GetValue() - 40)) end)
	bar.down:SetScript("OnClick", function()
		local _, hi = bar:GetMinMaxValues()
		bar:SetValue(math.min(hi, bar:GetValue() + 40))
	end)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local _, hi = bar:GetMinMaxValues()
		bar:SetValue(math.max(0, math.min(hi, bar:GetValue() - delta * 40)))
	end)

	local kit = Kit(holder)
	for _, name in ipairs(PAGE_ORDER) do Pages[name](kit) end
	kit.finish()
	for _, p in ipairs(kit.pages) do p:SetHeight(p.contentHeight) end
	frame.pages, frame.refreshers, frame.dropdowns = kit.pages, kit.refreshers, kit.dropdowns
	frame.scroll, frame.holder, frame.scrollbar = scroll, holder, bar
	frame.visible = HEIGHT - CHROME_TOP - PAD_TOP - PAD_BOTTOM - 2 * inset

	-- The categories, down the left: a quieter column, the page shown marked with an accent bar.
	local nav = CreateFrame("Frame", nil, frame)
	nav:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -CHROME_TOP - inset)
	nav:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
	nav:SetWidth(NAV_W - inset)
	local navBg = nav:CreateTexture(nil, "BACKGROUND")
	navBg:SetTexture(Theme.texture.solid)
	navBg:SetAllPoints(nav)
	Theme:Tint(navBg, "text", 0.03)
	local navEdge = nav:CreateTexture(nil, "BORDER")
	navEdge:SetTexture(Theme.texture.solid)
	navEdge:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, 0)
	navEdge:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", 0, 0)
	navEdge:SetWidth(1)
	Theme:Tint(navEdge, "text", 0.08)
	frame.navButtons = {}
	for i, p in ipairs(frame.pages) do
		local b = CreateFrame("Button", nil, nav)
		b:SetHeight(NAV_ROW_H)
		b:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -(8 + (i - 1) * NAV_ROW_H))
		b:SetPoint("RIGHT", nav, "RIGHT", -1, 0)
		local fill = b:CreateTexture(nil, "BACKGROUND")
		fill:SetTexture(Theme.texture.solid)
		fill:SetAllPoints(b)
		local mark = b:CreateTexture(nil, "ARTWORK")
		mark:SetTexture(Theme.texture.solid)
		mark:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
		mark:SetWidth(3)
		Theme:Tint(mark, "accent")
		local label = b:CreateFontString(nil, "OVERLAY")
		Theme:SetFont(label, "body", 13)
		label:SetPoint("LEFT", b, "LEFT", 14, 0)
		label:SetText(p.pageName)
		b.fill, b.mark, b.label, b.pageName = fill, mark, label, p.pageName
		function b:SetActive(on)
			self.active = on
			Theme:Tint(self.fill, "text", on and 0.08 or 0)
			self.mark:SetShown(on)
			Theme:TextColor(self.label, on and "text" or "textDim")
		end
		b:SetScript("OnClick", function(self) AP:ShowConfigPage(self.pageName) end)
		b:SetScript("OnEnter", function(self) if not self.active then Theme:Tint(self.fill, "text", 0.04) end end)
		b:SetScript("OnLeave", function(self) if not self.active then Theme:Tint(self.fill, "text", 0) end end)
		b:SetActive(false)
		frame.navButtons[i] = b
	end

	frame:HookScript("OnShow", function(self)
		if not Theme:RestorePosition(self, "optionsframe") then
			self:ClearAllPoints()
			local guide = AP.objectiveframe
			if guide:GetLeft() and guide:GetLeft() < UIParent:GetWidth() / 2 then
				self:SetPoint("TOPLEFT", guide, "TOPRIGHT", 8, 0)
			else
				self:SetPoint("TOPRIGHT", guide, "TOPLEFT", -8, 0)
			end
		end
		AP:RefreshConfigPanel()
		Theme:FadeIn(self, 0.3)
	end)
	frame:HookScript("OnHide", function(self)
		for _, d in ipairs(self.dropdowns) do d.list:Hide() end
	end)
	AP.Collector:OnChange(function() if frame:IsShown() then AP:RefreshConfigPanel() end end)
	AP:ShowConfigPage(Char().configpage or frame.pages[1].pageName)
end

--- Show one page: its content on the right, its name marked in the list and the subhead, at its top.
function AP:ShowConfigPage(name)
	if not frame then return end
	local shown
	for _, p in ipairs(frame.pages) do
		if p.pageName == name then shown = p end
	end
	shown = shown or frame.pages[1]
	for _, p in ipairs(frame.pages) do p:SetShown(p == shown) end
	for _, d in ipairs(frame.dropdowns) do d.list:Hide() end
	frame.page = shown.pageName
	Char().configpage = shown.pageName
	frame.holder:SetHeight(shown.contentHeight)
	local over = math.max(0, shown.contentHeight - frame.visible)
	frame.scrollbar:SetMinMaxValues(0, over)
	frame.scrollbar:SetValue(0)
	frame.scroll:SetVerticalScroll(0)
	frame.scrollbar:SetShown(over > 0)
	for _, b in ipairs(frame.navButtons) do b:SetActive(b.pageName == frame.page) end
	frame.subhead.label:SetText(("Config \194\183 " .. frame.page):upper())
end

function AP:RefreshConfigPanel()
	if not (frame and frame:IsShown()) then return end
	for _, refresh in ipairs(frame.refreshers) do pcall(refresh) end
end

function AP:ToggleConfigPanel()
	if not frame then return end
	frame:SetShown(not frame:IsShown())
end

function AP:OpenConfigPage(name)
	if not frame then return end
	frame:Show()
	self:ShowConfigPage(name)
end

function AP:ResetConfigPosition()
	if not frame then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", AP.objectiveframe, "TOPLEFT", -8, 0)
end

--[[ A page in the game's own Options, under AddOns, that opens this window:
	where players look for an addon's settings first. ]]
local function RegisterBlizzardCategory()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(AP.title)
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	text:SetText("Pathfinder's settings have a window of their own.")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(200, 24)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	button:SetText("Open Pathfinder settings")
	button:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
		frame:Show()
	end)
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, AP.title)
	if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

AP:OnInit(function()
	Build()
	pcall(RegisterBlizzardCategory)
end)
