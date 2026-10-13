local _, AP = ...

--[[
	Theme.lua -- the shared visual language for Aegis: Pathfinder.

	Ported from the 1.12 addon unchanged in what it draws: every colour, font and
	texture the UI uses is declared here and nowhere else, the hex strings are
	the design concept's CSS custom properties, and the shapes are white masks
	tinted at runtime, so one 32x32 rounded-rect serves every panel, band, pill
	and tab.

	Two skins draw the same widgets:

	  pathfinder  the concept: rounded dark panels, the bundled Rajdhani and
	              Inter faces, and the colour themes below. A theme applies at
	              once, without a reload.
	  blizzard    the client's own art: dialog frames, Blizzard's buttons and
	              check boxes, Friz Quadrata, gold headings. It is chosen as the
	              "Blizzard" theme and drawn as the windows are built, so
	              switching to it or away from it reloads the interface.

	Every widget keeps one API in both skins (SetOn, SetActive, SetTint, ...),
	so the windows never ask which skin they are in.
]]

local MEDIA = AP.media
local Compat = AP.Compat

AP.Theme = {}
local Theme = AP.Theme

Theme.media = MEDIA

-- "52c722" -> 0.322, 0.780, 0.133
local function hex(s)
	return {
		tonumber(s:sub(1, 2), 16) / 255,
		tonumber(s:sub(3, 4), 16) / 255,
		tonumber(s:sub(5, 6), 16) / 255,
	}
end

Theme.color = {
	bg1        = hex("12160f"),
	bg2        = hex("0a0d09"),
	panel      = hex("202020"),   -- --panel:      body of a floating window
	panel2     = hex("111111"),   -- --panel-2:    header / footer strips
	panel3     = hex("1a1a1a"),   -- --panel-3
	tabbg      = hex("3b3b3b"),   -- --tabbg:      tab strip and nav rows
	accent     = hex("52c722"),
	accentDeep = hex("2e850e"),
	accentGlow = hex("8fe066"),
	gold       = hex("ffed71"),
	goldDeep   = hex("e8b93a"),
	danger     = hex("e8636b"),
	bandGreen  = hex("2e850e"),   -- step satisfied
	bandRed    = hex("7c1820"),   -- step outstanding
	blue       = hex("5b9fd6"),
	text       = hex("ffffff"),
	textDim    = hex("c7c7bd"),
	border     = hex("050505"),
	subtle     = hex("545454"),   -- unchecked control outlines
	switchOn   = hex("2e850e"),   -- an on switch's track, in the theme's colours
}

--- A colour as a chat colour code, "|cffrrggbb".
function Theme:Code(name)
	local c = Theme.color[name] or Theme.color.text
	return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
		math.floor(c[3] * 255 + 0.5))
end

--[[ Themes.

	A theme names only the colours it changes -- the accent family, and for Day
	and Night the panel shades as well. Text, gold, danger and the satisfied
	and outstanding step bands keep their meaning in every theme. The 1.12
	addon's server colours are all kept; its Turtle WoW green, the concept's
	own, is "Pathfinder" here and the default.

	"Blizzard" is the other skin: its colours are the client's (gold headings,
	white text on dark dialog stone) and its art is the client's own.
]]
Theme.THEMES = {
	{ key = "day", label = "Pathfinder Day", note = "Warm amber on lighter panels.",
		colors = { accent = "f0b43c", accentDeep = "a8740f", accentGlow = "ffd98a", switchOn = "a8740f",
			panel = "2b2925", panel2 = "1c1a17", panel3 = "24221f", tabbg = "4a463e",
			bg1 = "1f1c16", bg2 = "15130f" } },
	{ key = "night", label = "Pathfinder Night", note = "Moonlight blue on deeper panels.",
		colors = { accent = "6fa8ff", accentDeep = "2f5fae", accentGlow = "a9cbff", switchOn = "2f5fae",
			panel = "171b25", panel2 = "0c0f16", panel3 = "12151e", tabbg = "2b3242",
			bg1 = "0e1119", bg2 = "080a10" } },
	{ key = "pathfinder", label = "Pathfinder Green", note = "The original green.", colors = {} },
	{ key = "octowow", label = "Pathfinder Purple", note = "Purple accents.",
		colors = { accent = "a970ff", accentDeep = "6526c4", accentGlow = "cfb0ff", switchOn = "6526c4" } },
	{ key = "ravencraft", label = "Pathfinder Grey",
		note = "Dark grey, with a lighter grey where the green was so it stays readable.",
		colors = { accent = "a3aab3", accentDeep = "474d55", accentGlow = "d2d6db", switchOn = "eceff2",
			panel = "1a1a1c", panel2 = "0d0d0f", panel3 = "151517", tabbg = "323235" } },
	{ key = "capybara", label = "Pathfinder Tan", note = "Tan accents.",
		colors = { accent = "cfa77c", accentDeep = "8b5a2b", accentGlow = "ead0b0", switchOn = "8b5a2b" } },
	{ key = "aegis", label = "Pathfinder Red", note = "Red accents.",
		colors = { accent = "ea5f56", accentDeep = "9e2a22", accentGlow = "f4958e", switchOn = "9e2a22" } },
	{ key = "blizzard", label = "Default", skin = "blizzard",
		note = "Today's Blizzard windows, as the game's own Options window: the metal border, a solid panel, "
			.. "Blizzard's buttons, check boxes and sliders. Switching to it or away from it reloads the interface.",
		colors = { accent = "ffd100", accentDeep = "8c6d00", accentGlow = "ffe766", switchOn = "ffd100",
			panel = "131313", panel2 = "0d0d0d", panel3 = "1a1a1a", tabbg = "1f1f1f", textDim = "cfcfcf",
			subtle = "6e6e6e", border = "000000", bg1 = "0d0d0d", bg2 = "0d0d0d" } },
}
Theme.DEFAULT_THEME = "pathfinder"
-- Keys the 1.12 addon saved, read as their Forever names.
Theme.RENAMED = { turtle = "pathfinder" }

Theme.themeByKey = {}
local RETINT = {}          -- every colour name some theme changes
for _, def in ipairs(Theme.THEMES) do
	Theme.themeByKey[def.key] = def
	for name in pairs(def.colors) do RETINT[name] = true end
end

-- The concept's values, to go back to.
local BASE = {}
for name, c in pairs(Theme.color) do BASE[name] = { c[1], c[2], c[3] } end

Theme.texture = {
	solid       = MEDIA .. "solid",
	panelFill   = MEDIA .. "panel-fill",
	panelBorder = MEDIA .. "panel-border",
	pillFill    = MEDIA .. "pill-fill",
	pillBorder  = MEDIA .. "pill-border",
	capTop      = MEDIA .. "cap-top",
	capBottom   = MEDIA .. "cap-bottom",
	tabFill     = MEDIA .. "tab-fill",
	tabBorder   = MEDIA .. "tab-border",
	circleFill  = MEDIA .. "circle-fill",
	circleBorder= MEDIA .. "circle-border",
	shadow      = MEDIA .. "shadow",
	progress    = MEDIA .. "progress-fill",
	minimapLogo = MEDIA .. "minimap-logo",
	logo        = MEDIA .. "logo",
	wordmark    = MEDIA .. "wordmark",
	grip        = MEDIA .. "grip",
	navArrow    = MEDIA .. "nav-arrow",
	navArrowMask = MEDIA .. "nav-arrow-mask",
	progressMask = MEDIA .. "progress-mask",
	scrollThumb = MEDIA .. "scroll-thumb",
	switchTrack = MEDIA .. "switch-track",
}

--[[ The Blizzard skin's art: files the Forever client's own interface draws
	with (checked against its FrameXML, build 1.60.1.70338). ]]
Theme.blizzardArt = {
	dialogBg     = "Interface\\DialogFrame\\UI-DialogBox-Background",
	dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
	dialogHeader = "Interface\\DialogFrame\\UI-DialogBox-Header",
	tooltipBg    = "Interface\\Tooltips\\UI-Tooltip-Background",
	tooltipBorder= "Interface\\Tooltips\\UI-Tooltip-Border",
	checkUp      = "Interface\\Buttons\\UI-CheckBox-Up",
	checkDown    = "Interface\\Buttons\\UI-CheckBox-Down",
	checkCheck   = "Interface\\Buttons\\UI-CheckBox-Check",
	checkHighlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
	statusBar    = "Interface\\TargetingFrame\\UI-StatusBar",
	scrollKnob   = "Interface\\Buttons\\UI-ScrollBar-Knob",
	sliderBorder = "Interface\\Buttons\\UI-SliderBar-Border",
	sliderBg     = "Interface\\Buttons\\UI-SliderBar-Background",
	sliderThumb  = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal",
	highlight    = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
	rule         = "Interface\\QuestFrame\\UI-HorizontalBreak",
	minimapBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
	minimapBg    = "Interface\\Minimap\\UI-Minimap-Background",
	minimapHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
}

--[[ Chrome glyphs: the concept's characters (a hamburger, a close cross,
	arrows, a tick) as generated masks. ]]
Theme.glyph = {
	auto         = MEDIA .. "icons\\auto",
	menu         = MEDIA .. "icons\\menu",
	close        = MEDIA .. "icons\\close",
	plus         = MEDIA .. "icons\\plus",
	arrowLeft    = MEDIA .. "icons\\arrow-left",
	arrowRight   = MEDIA .. "icons\\arrow-right",
	chevronLeft  = MEDIA .. "icons\\chevron-left",
	chevronRight = MEDIA .. "icons\\chevron-right",
	tick         = MEDIA .. "icons\\tick",
	bang         = MEDIA .. "icons\\bang",
	pin          = MEDIA .. "icons\\pin",
	expand       = MEDIA .. "icons\\expand",
	party        = MEDIA .. "icons\\party",
	caretUp      = MEDIA .. "icons\\caret-up",
	caretDown    = MEDIA .. "icons\\caret-down",
	star         = MEDIA .. "icons\\star",
	search       = MEDIA .. "icons\\search",
	gear         = MEDIA .. "icons\\gear",
	folder       = MEDIA .. "icons\\folder",
	heart        = MEDIA .. "icons\\heart",
	calendar     = MEDIA .. "icons\\calendar",
	medal        = MEDIA .. "icons\\medal",
	dots         = MEDIA .. "icons\\dots",
	lock         = MEDIA .. "icons\\lock",
	dashed       = MEDIA .. "icons\\dashed",
	wand         = MEDIA .. "icons\\wand",
	reload       = MEDIA .. "icons\\auto",
	reset        = MEDIA .. "icons\\expand",
	book         = MEDIA .. "icons\\train",
	note         = MEDIA .. "icons\\note",
	record       = MEDIA .. "icons\\pin",
}

Theme.font = {
	display  = MEDIA .. "fonts\\Rajdhani-Bold.ttf",
	display2 = MEDIA .. "fonts\\Rajdhani-SemiBold.ttf",
	body     = MEDIA .. "fonts\\Inter-Regular.ttf",
	body2    = MEDIA .. "fonts\\Inter-SemiBold.ttf",
}

-- Action code -> icon texture, for the guides to come (docs/guide-api.md).
Theme.actionIcon = {
	A = MEDIA .. "icons\\accept",
	T = MEDIA .. "icons\\turnin",
	C = MEDIA .. "icons\\complete",
	N = MEDIA .. "icons\\note",
	R = MEDIA .. "icons\\run",
	H = MEDIA .. "icons\\hearth",
	h = MEDIA .. "icons\\sethearth",
	F = MEDIA .. "icons\\fly",
	f = MEDIA .. "icons\\getflightpoint",
	B = MEDIA .. "icons\\buy",
	b = MEDIA .. "icons\\boat",
	K = MEDIA .. "icons\\kill",
	G = MEDIA .. "icons\\grind",
	U = MEDIA .. "icons\\use",
	t = MEDIA .. "icons\\train",
	D = MEDIA .. "icons\\die",
	P = MEDIA .. "icons\\pet",
}

Theme.actionIconByName = {
	ACCEPT = Theme.actionIcon.A, TURNIN = Theme.actionIcon.T, COMPLETE = Theme.actionIcon.C,
	NOTE = Theme.actionIcon.N, RUN = Theme.actionIcon.R, MAP = Theme.actionIcon.R,
	HEARTH = Theme.actionIcon.H, SETHEARTH = Theme.actionIcon.h, FLY = Theme.actionIcon.F,
	GETFLIGHTPOINT = Theme.actionIcon.f, BUY = Theme.actionIcon.B, BOAT = Theme.actionIcon.b,
	KILL = Theme.actionIcon.K, GRIND = Theme.actionIcon.G, USE = Theme.actionIcon.U,
	TRAIN = Theme.actionIcon.t, DIE = Theme.actionIcon.D, PET = Theme.actionIcon.P,
}

-- A guide by how it suits your level, as the quest log colours a quest.
Theme.LEVEL_COLORS = {
	grey   = { 0.50, 0.50, 0.50 },
	green  = { 0.25, 0.75, 0.25 },
	yellow = { 1.00, 1.00, 0.00 },
	orange = { 1.00, 0.50, 0.25 },
	red    = { 1.00, 0.10, 0.10 },
}

Theme.CORNER = 10        -- --radius:10px

-- Slice boundaries inside the 32px rounded-rect masks: the first and last
-- 10px are corners, the middle 12px stretches.
local S0, S1 = 10 / 32, 22 / 32

--[[ Which skin. Read once, when the theme is first applied: the Blizzard
	skin's widgets are different frames, not different colours, so it is
	chosen before anything is built and changed by a reload. ]]
Theme.skin = "pathfinder"

--[[ Where a window's content sits inside its frame, per skin: the header's
	height and the frame's edges. The concept's panel has a 1px border and a
	30px header; the Blizzard window has its metal border (7px left, 3px right
	and bottom) and its title in the 22px top bar. ]]
local METRICS = {
	pathfinder = { header = 30, left = 1, right = 1, top = 1, bottom = 1 },
	blizzard = { header = 22, left = 7, right = 3, top = 0, bottom = 3 },
}
Theme.metrics = METRICS.pathfinder

function Theme:IsBlizzard()
	return self.skin == "blizzard"
end

--- Fix the skin for this session from the saved theme. Called before any window is built.
function Theme:ChooseSkin(themeKey)
	themeKey = self.RENAMED[themeKey] or themeKey
	local def = self.themeByKey[themeKey]
	self.skin = def and def.skin or "pathfinder"
	self.metrics = METRICS[self.skin]
	return self.skin
end

-- Does nothing, so the skins share one API: a Blizzard widget has no tint to change.
local NOOP_TINT = { SetTint = function() end }

--[[ Colour helpers ]]

-- Which colour each texture and font string was last given by name, so a
-- theme change can re-tint what is already on screen. Weak keys.
local tintName = setmetatable({}, { __mode = "k" })
local tintAlpha = setmetatable({}, { __mode = "k" })
local textName = setmetatable({}, { __mode = "k" })

function Theme:Tint(tex, name, alpha)
	local c = self.color[name] or name
	tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
	if type(name) == "string" then
		tintName[tex], tintAlpha[tex] = name, alpha
	else
		tintName[tex], tintAlpha[tex] = nil, nil
	end
	return tex
end

function Theme:TextColor(fs, name)
	local c = self.color[name] or name
	fs:SetTextColor(c[1], c[2], c[3])
	textName[fs] = type(name) == "string" and name or nil
	return fs
end

--[[ Art with the concept's green baked in: the navigation arrow and the
	progress fill. The concept's theme keeps that art exactly; any other theme
	gets the same shape in grey, tinted with its accent glow; the Blizzard skin
	the client's status bar. ]]
local SKINS = {
	navArrow = { art = "navArrow", mask = "navArrowMask" },
	progress = { art = "progress", mask = "progressMask" },
}
local skinned = setmetatable({}, { __mode = "k" })

local function ApplySkin(tex, kind)
	local skin = SKINS[kind]
	if kind == "progress" and Theme:IsBlizzard() then
		tex:SetTexture(Theme.blizzardArt.statusBar)
		local c = Theme.color.accent
		tex:SetVertexColor(c[1], c[2], c[3], 1)
	elseif Theme.current == nil or Theme.current == Theme.DEFAULT_THEME then
		tex:SetTexture(Theme.texture[skin.art])
		tex:SetVertexColor(1, 1, 1, 1)
	else
		tex:SetTexture(Theme.texture[skin.mask])
		local c = Theme.color.accentGlow
		tex:SetVertexColor(c[1], c[2], c[3], 1)
	end
end

function Theme:Skin(tex, kind)
	skinned[tex] = kind
	ApplySkin(tex, kind)
	return tex
end

--- Switch to a theme by key (an unknown key is the default). Returns its definition.
function Theme:ApplyTheme(key)
	key = self.RENAMED[key] or key
	local def = self.themeByKey[key] or self.themeByKey[self.DEFAULT_THEME]
	for name, base in pairs(BASE) do
		local v = def.colors[name] and hex(def.colors[name]) or base
		local c = self.color[name]
		c[1], c[2], c[3] = v[1], v[2], v[3]
	end
	self.current = def.key
	for tex, name in pairs(tintName) do
		if RETINT[name] then
			local c = self.color[name]
			tex:SetVertexColor(c[1], c[2], c[3], tintAlpha[tex] or 1)
		end
	end
	for fs, name in pairs(textName) do
		if RETINT[name] then
			local c = self.color[name]
			fs:SetTextColor(c[1], c[2], c[3])
		end
	end
	for tex, kind in pairs(skinned) do ApplySkin(tex, kind) end
	return def
end

--[[ Typography ]]

-- The Blizzard skin's faces: Friz Quadrata for headings and body alike, as
-- the client's own panels have it, a point smaller than the bundled faces.
local BLIZZARD_FONT = {
	display = { "Fonts\\FRIZQT__.TTF", -1 },
	display2 = { "Fonts\\FRIZQT__.TTF", -1 },
	body = { "Fonts\\FRIZQT__.TTF", -1 },
	body2 = { "Fonts\\FRIZQT__.TTF", -1 },
}

--- Applies a bundled face, falling back to the client font if it is rejected.
function Theme:SetFont(fs, role, size, flags)
	local path = self.font[role]
	if self:IsBlizzard() then
		local face = BLIZZARD_FONT[role] or BLIZZARD_FONT.body
		path, size = face[1], math.max(8, size + face[2])
	end
	local ok, success = pcall(fs.SetFont, fs, path or "", size, flags or "")
	if not (ok and success ~= false) then
		fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "")
		return false
	end
	return true
end

--[[ Nine-slice panels ]]

-- Builds a rounded panel out of a 32x32 mask: four fixed corners, four edges
-- that stretch along one axis, and a stretched centre.
--
-- `geom` is for masks sliced differently from the 32px/10px panel set:
-- `corner` is the corner's size on screen, `slice` where it ends in the
-- texture (0..0.5), `outset` how far past the frame's edges the whole thing
-- reaches, and `noCenter` skips the middle piece.
function Theme:NineSlice(frame, file, layer, colorName, alpha, geom)
	local parts = {}
	local C = geom and geom.corner or self.CORNER
	local s0, s1 = S0, S1
	if geom and geom.slice then s0, s1 = geom.slice, 1 - geom.slice end
	local O = geom and geom.outset or 0

	local function piece(name, coords)
		local t = frame:CreateTexture(nil, layer or "BACKGROUND")
		t:SetTexture(file)
		t:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		self:Tint(t, colorName, alpha)
		parts[name] = t
		return t
	end

	local tl, tr = piece("tl", { 0, s0, 0, s0 }), piece("tr", { s1, 1, 0, s0 })
	local bl, br = piece("bl", { 0, s0, s1, 1 }), piece("br", { s1, 1, s1, 1 })
	for _, c in pairs({ tl, tr, bl, br }) do c:SetSize(C, C) end
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -O, O)
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", O, O)
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -O, -O)
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", O, -O)

	local top = piece("top", { s0, s1, 0, s0 })
	top:SetHeight(C)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
	top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)

	local bottom = piece("bottom", { s0, s1, s1, 1 })
	bottom:SetHeight(C)
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)

	local left = piece("left", { 0, s0, s0, s1 })
	left:SetWidth(C)
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)

	local right = piece("right", { s1, 1, s0, s1 })
	right:SetWidth(C)
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)

	if not (geom and geom.noCenter) then
		local center = piece("center", { s0, s1, s0, s1 })
		center:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0)
		center:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
	end

	function parts:SetTint(name, a)
		for _, tex in pairs(self) do
			if type(tex) == "table" and tex.SetVertexColor then Theme:Tint(tex, name, a) end
		end
	end

	return parts
end

--[[ Backdrops, for the Blizzard skin. A frame not built with BackdropTemplate
	takes its mixin here; the size hook keeps the edges drawn as it grows. ]]
local function EnsureBackdrop(frame)
	if frame.SetBackdrop then return frame end
	Mixin(frame, BackdropTemplateMixin)
	frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
	return frame
end

local BACKDROPS = {
	dialog = { bgFile = Theme.blizzardArt.dialogBg, edgeFile = Theme.blizzardArt.dialogBorder, tile = true,
		tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } },
	tooltip = { bgFile = Theme.blizzardArt.tooltipBg, edgeFile = Theme.blizzardArt.tooltipBorder, tile = true,
		tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } },
	slider = { bgFile = Theme.blizzardArt.sliderBg, edgeFile = Theme.blizzardArt.sliderBorder, tile = true,
		tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } },
}
Theme.BACKDROPS = BACKDROPS

--- A Blizzard backdrop of `kind` ("dialog", "tooltip", "slider") on `frame`,
--- with a tint proxy so the guide's transparency still works.
function Theme:Backdrop(frame, kind, alpha)
	EnsureBackdrop(frame)
	frame:SetBackdrop(BACKDROPS[kind or "dialog"])
	frame:SetBackdropColor(1, 1, 1, alpha or 1)
	local proxy = {}
	function proxy:SetTint(_, a)
		frame:SetBackdropColor(1, 1, 1, a or 1)
		frame:SetBackdropBorderColor(1, 1, 1, 1)
	end
	return proxy
end

--[[ The Blizzard skin's art.

	Today's Blizzard windows, as the game's own Options window draws them
	(SettingsFrameTemplate in the Forever client): the metal nine-slice border,
	a solid flat background in the client's panel colour, the title in the top
	bar, and the minimal check boxes, sliders, dropdowns and scroll bars. All of
	it is the client's own art. Every atlas is asked for before it is used, with
	a plain fallback, so a client without one still draws a solid, readable
	window. Nothing here is see-through unless the player turns Transparency on.
]]
local Modern = {}
Theme.Modern = Modern

function Modern.HasAtlas(name)
	if not (name and C_Texture and C_Texture.GetAtlasInfo) then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end

--- Put an atlas on a texture. False, and nothing set, when the client lacks it.
function Modern.Atlas(tex, name, useSize)
	if not Modern.HasAtlas(name) then return false end
	tex:SetAtlas(name, useSize and true or false)
	return true
end

--- The client's panel colour (the Options window's background), `shade` times as bright.
function Modern.PanelColor(shade)
	local r, g, b = 0.075, 0.075, 0.075
	if PANEL_BACKGROUND_COLOR and PANEL_BACKGROUND_COLOR.GetRGB then
		local ok, cr, cg, cb = pcall(PANEL_BACKGROUND_COLOR.GetRGB, PANEL_BACKGROUND_COLOR)
		if ok and type(cr) == "number" then r, g, b = cr, cg, cb end
	end
	shade = shade or 1
	return math.min(1, r * shade), math.min(1, g * shade), math.min(1, b * shade)
end

--[[ One of the client's nine-slice layouts, drawn as the frame's own textures
	(so its children draw over it). Through NineSliceUtil, so the Forever
	client's own corrections to the layouts apply. False when the art is missing. ]]
function Modern.Border(frame, layout, probeAtlas)
	if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName and NineSliceUtil.GetLayout) then return false end
	if not NineSliceUtil.GetLayout(layout) then return false end
	if probeAtlas and not Modern.HasAtlas(probeAtlas) then return false end
	return (pcall(NineSliceUtil.ApplyLayoutByName, frame, layout))
end

-- A solid fill in the panel colour. Its proxy's SetTint only changes how
-- see-through it is: the guide's Transparency setting.
local function SolidFill(frame, shade, inset)
	local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	if inset then
		t:SetPoint("TOPLEFT", frame, "TOPLEFT", inset[1], inset[2])
		t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset[3], inset[4])
	else
		t:SetAllPoints(frame)
	end
	local r, g, b = Modern.PanelColor(shade)
	t:SetColorTexture(r, g, b, 1)
	local proxy = { texture = t }
	function proxy:SetTint(_, alpha) t:SetAlpha(alpha or 1) end
	return proxy
end
Modern.SolidFill = SolidFill

--- A window: the solid background and the metal border.
function Modern.Window(frame)
	local fill = SolidFill(frame, 1, { 7, -18, -3, 3 })
	if not Modern.Border(frame, "ButtonFrameTemplateNoPortrait", "UI-Frame-Metal-CornerTopLeft") then
		-- No metal on this client: a dialog edge, over the same solid fill.
		EnsureBackdrop(frame)
		frame:SetBackdrop({ edgeFile = Theme.blizzardArt.dialogBorder, edgeSize = 24 })
	end
	return { fill = fill, border = NOOP_TINT, shadow = NOOP_TINT }
end

--- A panel that floats over others -- a menu, a dropdown's list, a hint: the
--- tooltip's border, solid inside.
function Modern.Floating(frame)
	local fill = SolidFill(frame, 0.7)
	if Modern.Border(frame, "TooltipDefaultLayout", "Tooltip-NineSlice-CornerTopLeft") then
		-- The layout's own middle is see-through; the solid fill shows instead.
		if frame.Center then frame.Center:Hide() end
	else
		EnsureBackdrop(frame)
		frame:SetBackdrop({ edgeFile = Theme.blizzardArt.tooltipBorder, edgeSize = 14 })
	end
	return { fill = fill, border = NOOP_TINT }
end

--- A recessed panel inside a window -- a list, a card, the export box: the
--- inset frame's edges, darker and solid inside.
function Modern.Inset(frame)
	local fill = SolidFill(frame, 0.55)
	if not Modern.Border(frame, "InsetFrameTemplate", "UI-Frame-InnerTopLeft") then
		EnsureBackdrop(frame)
		frame:SetBackdrop({ edgeFile = Theme.blizzardArt.tooltipBorder, edgeSize = 12 })
		frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	end
	return { fill = fill, border = NOOP_TINT }
end

--[[ Composite widgets ]]

-- A floating window: tinted fill, 1px border in the concept's near-black, and
-- a soft drop shadow standing in for CSS box-shadow. The shadow is a ring,
-- clear inside the panel's edge, nine-sliced 7px outside it.
local SHADOW_GEOM = { corner = 18, slice = 18 / 64, outset = 7, noCenter = true }
Theme.SHADOW_GEOM = SHADOW_GEOM

function Theme:Panel(frame, colorName, withShadow)
	if self:IsBlizzard() then
		if colorName == "panel2" then return Modern.Floating(frame) end
		if colorName == "panel3" then return Modern.Inset(frame) end
		return Modern.Window(frame)
	end
	local skin = {}
	if withShadow ~= false then
		skin.shadow = self:NineSlice(frame, self.texture.shadow, "BACKGROUND", { 0, 0, 0 }, 0.62, SHADOW_GEOM)
	end
	skin.fill = self:NineSlice(frame, self.texture.panelFill, "BACKGROUND", colorName or "panel")
	skin.border = self:NineSlice(frame, self.texture.panelBorder, "BORDER", "border")
	return skin
end

--- A recessed box inside a window -- a card, a list, a text box: the concept's
--- tab-fill rounded rect with a border, or the Blizzard inset frame.
function Theme:Inset(frame, colorName)
	if self:IsBlizzard() then return Modern.Inset(frame) end
	local fill = self:NineSlice(frame, self.texture.tabFill, "BACKGROUND", colorName or "panel3")
	local border = self:NineSlice(frame, self.texture.tabBorder, "BORDER", "border")
	return { fill = fill, border = border }
end

-- Flat strip used for headers, footers, tab bars and nav rows.
function Theme:Strip(frame, colorName, alpha)
	local t = frame:CreateTexture(nil, "BACKGROUND")
	t:SetTexture(self.texture.solid)
	t:SetAllPoints(frame)
	if self:IsBlizzard() then
		-- On the flat panel a strip is a slightly darker band, not a colour of its own.
		t:SetVertexColor(0, 0, 0, colorName == "tabbg" and 0.18 or 0.28)
	else
		self:Tint(t, colorName or "panel2", alpha)
	end
	return t
end

--- A strip that meets a panel edge: rounded on that edge, square on the body's.
function Theme:CapStrip(frame, colorName, edge, alpha)
	if self:IsBlizzard() then return { SetTint = function() end } end
	return self:NineSlice(frame, edge == "bottom" and self.texture.capBottom or self.texture.capTop,
		"BACKGROUND", colorName or "panel2", alpha)
end

-- 1px rule in the concept's border colour; a faint gold one in the Blizzard skin.
function Theme:Divider(parent, anchor, relPoint, x, y, width)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(self.texture.solid)
	t:SetHeight(1)
	if width then t:SetWidth(width) end
	t:SetPoint("TOPLEFT", anchor, relPoint or "BOTTOMLEFT", x or 0, y or 0)
	if not width then t:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, y or 0) end
	if self:IsBlizzard() then
		-- The Options window's own rule, or a faint gold line.
		if Modern.Atlas(t, "Options_HorizontalDivider") then
			t:SetHeight(2)
		else
			t:SetVertexColor(1, 0.82, 0, 0.25)
		end
	else
		self:Tint(t, "border")
	end
	return t
end

--[[ Progress track + gradient fill: a StatusBar, so the client fills it to the
	value itself. `bar.fill` stands in for its texture so Theme:Skin can swap
	its art and tint with the theme. ]]
function Theme:ProgressBar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height or 5)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)

	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(self.texture.solid)
	track:SetAllPoints(bar)
	track:SetVertexColor(0, 0, 0, 0.4)

	local fill = {}
	function fill:SetTexture(path) self.__texture = path; bar:SetStatusBarTexture(path) end
	function fill:SetVertexColor(r, g, b, a) bar:SetStatusBarColor(r, g, b, a or 1) end
	self:Skin(fill, "progress")

	bar.track, bar.fill = track, fill
	bar.ratio = 0

	function bar:SetProgress(ratio)
		if not ratio or ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
		self.ratio = ratio
		self:SetValue(ratio)
	end

	return bar
end

-- The step checkbox: a ring that fills with accent when complete. A step the
-- addon ticks for you shows a small ⟳ inside the ring (SetAutoEligible).
function Theme:StepCheck(parent, size)
	local b = CreateFrame("CheckButton", nil, parent)
	size = size or 15
	b:SetSize(size, size)

	local ring = b:CreateTexture(nil, "ARTWORK")
	ring:SetAllPoints(b)
	local fill = b:CreateTexture(nil, "ARTWORK")
	fill:SetAllPoints(b)
	if self:IsBlizzard() then
		if not Modern.Atlas(ring, "checkbox-minimal") then ring:SetTexture(self.blizzardArt.checkUp) end
		if not Modern.Atlas(fill, "checkmark-minimal") then fill:SetTexture(self.blizzardArt.checkCheck) end
	else
		ring:SetTexture(self.texture.circleBorder)
		self:Tint(ring, "subtle")
		fill:SetTexture(self.texture.circleFill)
		self:Tint(fill, "accent")
	end
	fill:Hide()

	local auto = b:CreateTexture(nil, "OVERLAY")
	auto:SetTexture(self.glyph.auto)
	auto:SetPoint("CENTER", b, "CENTER", 0, 0)
	auto:SetSize(math.floor(size * 0.72 + 0.5), math.floor(size * 0.72 + 0.5))
	self:Tint(auto, "accent")
	auto:Hide()

	b.ring, b.fill, b.auto = ring, fill, auto

	function b:SetChecked(done)
		self.__checked = done and true or false
		self.fill:SetShown(self.__checked)
		self.auto:SetShown(not self.__checked and self.__auto == true)
		if not Theme:IsBlizzard() then Theme:Tint(self.ring, self.__checked and "accent" or "subtle") end
	end
	function b:GetChecked() return self.__checked end
	function b:SetAutoEligible(eligible)
		self.__auto = eligible and true or false
		self.auto:SetShown(self.__auto and not self.__checked)
	end

	b:SetChecked(false)
	return b
end

--[[ A button from Blizzard's own template, wearing the API the concept's pills
	have: SetActive (held lit), label, fill. ]]
local function BlizzardButton(parent, label, width, height)
	local b = Compat.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 150, height or 22)
	b:SetText(label or "")
	b.label = b:GetFontString() or b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.fill, b.border = NOOP_TINT, NOOP_TINT
	function b:SetActive(active)
		self.__active = active and true or false
		if self.__active then self:LockHighlight() else self:UnlockHighlight() end
	end
	function b:IsActive() return self.__active end
	return b
end

-- Uppercase display-face pill.
function Theme:Pill(parent, label, width, height)
	if self:IsBlizzard() then return BlizzardButton(parent, label, width or 90, height or 22) end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 90, height or 22)

	local fill = self:NineSlice(b, self.texture.pillFill, "BACKGROUND", "panel3")
	local border = self:NineSlice(b, self.texture.pillBorder, "BORDER", "border")

	local fs = b:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "display", 11)
	fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	fs:SetText((label or ""):upper())
	self:TextColor(fs, "textDim")

	b.label, b.fill, b.border = fs, fill, border

	function b:SetActive(active)
		self.__active = active and true or false
		if active then
			self.fill:SetTint("accent")
			self.label:SetTextColor(0.05, 0.10, 0.02)
		else
			self.fill:SetTint("panel3")
			Theme:TextColor(self.label, "textDim")
		end
	end
	function b:IsActive() return self.__active end

	b:SetActive(false)
	return b
end

--[[ Panel button: `.pill` sized for a panel row, shadowing SetText/GetText and
	uppercasing like the concept does in CSS. In the Blizzard skin, Blizzard's
	red button as it is. ]]
function Theme:PanelButton(parent, label, width, height)
	if self:IsBlizzard() then return BlizzardButton(parent, label, width or 150, height or 22) end
	local b = self:Pill(parent, label, width or 150, height or 22)

	function b:SetText(t) self.label:SetText((t or ""):upper()) end
	function b:GetText() return self.label:GetText() end

	b:SetScript("OnEnter", function(self)
		if self.__active then return end
		self.fill:SetTint("tabbg")
		Theme:TextColor(self.label, "text")
	end)
	b:SetScript("OnLeave", function(self)
		if self.__active then return end
		self.fill:SetTint("panel3")
		Theme:TextColor(self.label, "textDim")
	end)

	return b
end

--[[ Close chip: the concept's header ✕, or Blizzard's close button. The frame
	to hide is passed explicitly. ]]
function Theme:CloseChip(parent, target)
	local b
	if self:IsBlizzard() then
		-- The red close button of today's windows (RedButton-Exit), without Blizzard's own click handler.
		b = Compat.CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts", "UIPanelCloseButton")
		b:SetSize(24, 24)
		b.fill, b.glyph = NOOP_TINT, b:CreateTexture()
		function b:SetActive() end
		function b:SetTints() end
	else
		b = self:ChipButton(parent, "close")
	end
	b:SetScript("OnClick", function() (target or parent):Hide() end)
	return b
end

--- Where a window's close button goes: on the header's right, or, in the
--- Blizzard skin, on the metal top-right corner as the game's own windows have it.
function Theme:PlaceClose(close, frame, header)
	close:ClearAllPoints()
	if self:IsBlizzard() then
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 1)
	else
		close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
	end
end

--[[ Category tab: uppercase display face, transparent until selected, and
	accent-on-panel when it is. ]]
function Theme:Tab(parent, label, width, height)
	if self:IsBlizzard() then return BlizzardButton(parent, label, width or 88, height or 22) end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 88, height or 22)

	local fill = self:NineSlice(b, self.texture.tabFill, "BACKGROUND", "panel")
	fill:SetTint("tabbg")

	local fs = b:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "display", 11)
	fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	fs:SetText((label or ""):upper())
	self:TextColor(fs, "textDim")

	b.fill, b.label = fill, fs

	function b:SetActive(active)
		self.__active = active and true or false
		if self.__active then
			self.fill:SetTint("panel")
			Theme:TextColor(self.label, "accent")
		else
			self.fill:SetTint("tabbg")
			Theme:TextColor(self.label, "textDim")
		end
	end
	function b:IsActive() return self.__active end

	b:SetActive(false)
	return b
end

--[[ Badge: what a guide is, on its tab -- XP leveling, PF profession, DG
	dungeon, CL class quest, AT attunement, HC hardcore, TPL a placeholder. ]]
local DARK, LIGHT = { 0.08, 0.07, 0.06 }, { 0.93, 0.93, 0.93 }
Theme.BADGES = {
	xp  = { bg = "goldDeep", text = DARK },
	pf  = { bg = { 0.36, 0.62, 0.84 }, text = DARK },
	dg  = { bg = { 0.60, 0.48, 0.86 }, text = DARK },
	cl  = { bg = { 0.30, 0.70, 0.64 }, text = DARK },
	at  = { bg = { 0.91, 0.51, 0.23 }, text = DARK },
	hc  = { bg = { 0.85, 0.30, 0.30 }, text = LIGHT },
	tpl = { bg = "subtle", text = LIGHT },
	new = { bg = "accent", text = DARK },
}

function Theme:Badge(parent, text, kind)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(12)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(self:IsBlizzard() and self.texture.solid or self.texture.tabFill)
	bg:SetAllPoints(f)

	local fs = f:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "display", 9)
	fs:SetPoint("CENTER", f, "CENTER", 0, 0)

	f.bg, f.label = bg, fs

	function f:SetKind(k, t)
		self.label:SetText((t or k or ""):upper())
		local look = Theme.BADGES[k] or Theme.BADGES.xp
		Theme:Tint(self.bg, look.bg)
		self.label:SetTextColor(look.text[1], look.text[2], look.text[3])
		self:SetWidth(math.max(22, self.label:GetStringWidth() + 10))
	end

	f:SetKind(kind, text)
	return f
end

-- Coloured full-width band for ACCEPT / TURNIN steps: red while outstanding,
-- green once satisfied, in every theme and both skins.
function Theme:Band(parent, height)
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(height or 26)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(self.texture.solid)
	bg:SetAllPoints(f)
	self:Tint(bg, "bandRed")

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(13, 13)
	icon:SetPoint("LEFT", f, "LEFT", 10, 0)

	local fs = f:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "body", 12)
	fs:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	fs:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(1, 1, 1)

	f.bg, f.icon, f.label = bg, icon, fs

	function f:SetDone(done)
		Theme:Tint(self.bg, done and "bandGreen" or "bandRed")
	end

	return f
end

--[[ Bare glyph button: transparent until hovered, then the accent. `size` is
	the glyph, `box` the click target around it. ]]
function Theme:GlyphButton(parent, glyphName, size, box)
	local b = CreateFrame("Button", nil, parent)
	size = size or 12
	b:SetSize(box or (size + 8), box or (size + 8))

	local g = b:CreateTexture(nil, "ARTWORK")
	g:SetTexture(self.glyph[glyphName] or glyphName)
	g:SetSize(size, size)
	g:SetPoint("CENTER", b, "CENTER", 0, 0)
	self:Tint(g, "textDim")

	b.glyph = g
	b.__idle, b.__hover = "textDim", "accent"

	function b:SetTints(idle, hover)
		self.__idle, self.__hover = idle, hover
		Theme:Tint(self.glyph, idle)
	end

	b:SetScript("OnEnter", function(self) Theme:Tint(self.glyph, self.__hover) end)
	b:SetScript("OnLeave", function(self) Theme:Tint(self.glyph, self.__idle) end)

	return b
end

--[[ Header chip: the concept's `.chip-btn`, a 20px rounded square with a 1px
	border and a barely-there fill, carrying one glyph. In the Blizzard skin a
	small tooltip-bordered square. `tip` is its hint. ]]
function Theme:ChipButton(parent, glyphName, size, tip)
	local b = self:GlyphButton(parent, glyphName, 10, size or 20)

	local fill
	if self:IsBlizzard() then
		-- A gold glyph on the title bar, as the game's own title-bar buttons are;
		-- a soft gold square behind it while what it toggles is on.
		local back = b:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints(b)
		back:SetColorTexture(1, 0.82, 0, 0.28)
		back:Hide()
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b)
		hl:SetColorTexture(1, 1, 1, 0.12)
		fill = { SetTint = function(_, name) back:SetShown(name == "accent") end }
		b:SetTints("accent", "text")
	else
		fill = self:NineSlice(b, self.texture.tabFill, "BACKGROUND", "text", 0.04)
		self:NineSlice(b, self.texture.tabBorder, "BORDER", "border")
		b:SetTints("textDim", "text")
	end
	b.fill = fill
	b.tip = tip

	-- Accent fill, dark glyph: the chip toggles something which is now on.
	function b:SetActive(active)
		self.__active = active and true or false
		if self.__active then
			self.fill:SetTint("accent", 1)
			if Theme:IsBlizzard() then
				Theme:Tint(self.glyph, "text")
			else
				self.glyph:SetVertexColor(0.05, 0.10, 0.02, 1)
			end
		else
			self.fill:SetTint("text", 0.04)
			Theme:Tint(self.glyph, self.__idle)
		end
	end
	function b:IsActive() return self.__active end

	b:SetScript("OnEnter", function(self)
		if not self.__active then
			self.fill:SetTint("text", 0.10)
			Theme:Tint(self.glyph, self.__hover)
		end
		local text = type(self.tip) == "function" and self.tip() or self.tip
		if text then Theme:ShowTip(self, "BOTTOM", text) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.__active then
			self.fill:SetTint("text", 0.04)
			Theme:Tint(self.glyph, self.__idle)
		end
		Theme:HideTip(self)
	end)

	return b
end

--[[ Panel header: a `--panel-2` strip with the PATHFINDER wordmark centred, a
	1px rule beneath it, and the whole strip as the window's drag handle. In
	the Blizzard skin the window's top bar, with its name in gold in the middle
	of the metal, as the game's own Options window has it. ]]
function Theme:Header(frame, height, title)
	local h = CreateFrame("Frame", nil, frame)
	local m = self.metrics
	h:SetHeight(height or m.header)
	h:SetPoint("TOPLEFT", frame, "TOPLEFT", m.left, -m.top)
	h:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -m.right, -m.top)
	if self:IsBlizzard() then
		local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOP", h, "TOP", 0, -5)
		fs:SetPoint("LEFT", h, "LEFT", 60, 0)
		fs:SetPoint("RIGHT", h, "RIGHT", -60, 0)
		fs:SetWordWrap(false)
		fs:SetText(title or AP.L.TITLE)
		h.title = fs
	else
		self:CapStrip(h, "panel2", "top")
		self:Divider(h, h, "BOTTOMLEFT", 0, 0)

		local mark = h:CreateTexture(nil, "ARTWORK")
		mark:SetTexture(self.texture.wordmark)
		mark:SetSize(128, 16)
		mark:SetPoint("CENTER", h, "CENTER", 0, 0)
		self:Tint(mark, "text")
		h.wordmark = mark
	end

	--- Make the window follow this header; `onMoved(frame)` persists where it was dropped.
	function h:MakeDragHandle(target, onMoved)
		target:SetMovable(true)
		target:EnableMouse(true)
		self:EnableMouse(true)
		self:RegisterForDrag("LeftButton")
		self:SetScript("OnMouseDown", function() Theme:BringToFront(target) end)
		self:SetScript("OnDragStart", function()
			if target.locked then return end
			target:StartMoving()
		end)
		self:SetScript("OnDragStop", function()
			target:StopMovingOrSizing()
			Theme:AnchorTopLeft(target)
			if onMoved then onMoved(target) end
		end)
		return self
	end

	return h
end

--[[ Fade a window in as it opens: from clear to solid over `seconds` -- or to
	`frame.fadeTo`, a window with an opacity of its own. ]]
function Theme:FadeIn(frame, seconds)
	local elapsed = 0
	frame:SetAlpha(0)
	frame:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + (delta or 0)
		local to = self.fadeTo or 1
		if elapsed >= seconds then
			self:SetScript("OnUpdate", nil)
			self:SetAlpha(to)
		else
			self:SetAlpha(to * elapsed / seconds)
		end
	end)
end

--[[ Scrollbar: a dark track, a stadium thumb at the accent, and small caret
	buttons at either end. A Slider, so SetMinMaxValues / SetValue /
	OnValueChanged work as on any slider. ]]
function Theme:ScrollBar(parent, width)
	local f = CreateFrame("Slider", nil, parent)
	width = width or 10
	f:SetWidth(width)
	f:SetOrientation("VERTICAL")
	f:SetObeyStepOnDrag(false)

	local track = f:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(self.texture.solid)
	track:SetAllPoints(f)
	track:SetVertexColor(0, 0, 0, 0.35)

	if self:IsBlizzard() then
		-- The minimal scroll bar of today's windows: a thin track and a rounded thumb.
		if Modern.Atlas(track, "!minimal-scrollbar-track-middle") then
			track:SetVertexColor(1, 1, 1, 1)
			track:ClearAllPoints()
			track:SetPoint("TOP", f, "TOP", 0, 0)
			track:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
			track:SetWidth(8)
		end
		f:SetThumbTexture(self.texture.solid)
		local thumb = f:GetThumbTexture()
		if not Modern.Atlas(thumb, "minimal-scrollbar-small-thumb-middle") then
			thumb:SetTexture(self.blizzardArt.scrollKnob)
		end
		thumb:SetSize(8, 28)
	else
		f:SetThumbTexture(self.texture.scrollThumb)
		local thumb = f:GetThumbTexture()
		thumb:SetSize(width, 28)
		self:Tint(thumb, "subtle")
	end

	local function StepButton(glyphName, point, rel, atlas)
		local b = self:GlyphButton(f, glyphName, 7, width)
		b:SetPoint(point, f, rel)
		if self:IsBlizzard() and Modern.Atlas(b.glyph, atlas) then
			-- The minimal scroll bar's own arrows, lit on hover.
			b.glyph:SetSize(12, 8)
			b:SetTints({ 1, 1, 1 }, { 1, 0.82, 0 })
		else
			b:SetTints(self:IsBlizzard() and "accent" or "textDim", self:IsBlizzard() and "text" or "accent")
		end
		return b
	end

	local up = StepButton("caretUp", "BOTTOM", "TOP", "minimal-scrollbar-arrow-top")
	local down = StepButton("caretDown", "TOP", "BOTTOM", "minimal-scrollbar-arrow-bottom")

	f.step = 1
	function f:Nudge(delta)
		local lo, hi = self:GetMinMaxValues()
		local v = self:GetValue() + delta
		if v < lo then v = lo elseif v > hi then v = hi end
		self:SetValue(v)
	end
	up:SetScript("OnClick", function() f:Nudge(-f.step) end)
	down:SetScript("OnClick", function() f:Nudge(f.step) end)

	f.track, f.up, f.down = track, up, down
	return f, up, down
end

--[[ Form widgets for the options window. ]]

--- `.options-body h3`: 12px uppercase display face in accent, a 1px rule under it.
function Theme:SectionHeader(parent, text, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(20)
	if width then f:SetWidth(width) end

	local fs = f:CreateFontString(nil, "OVERLAY")
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)

	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(self.texture.solid)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	if self:IsBlizzard() then
		-- As the Options window's sections: the name in white, the Options rule under it.
		self:SetFont(fs, "display", 15)
		fs:SetText(text or "")
		self:TextColor(fs, "text")
		if Modern.Atlas(rule, "Options_HorizontalDivider") then
			rule:SetHeight(2)
		else
			rule:SetVertexColor(1, 0.82, 0, 0.25)
		end
	else
		self:SetFont(fs, "display", 12)
		fs:SetText((text or ""):upper())
		self:TextColor(fs, "accent")
		self:Tint(rule, "border")
	end

	f.label, f.rule = fs, rule
	return f
end

--- `.fine-print`: 11px dim prose that wraps to the width it is given.
function Theme:FinePrint(parent, width)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "body", 11)
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	self:TextColor(fs, "textDim")
	return fs
end

--[[ The concept's `.toggle-row`: a sliding switch and its label, the whole row
	clickable. Off: a faint track with a white knob on the left. On: a track in
	the theme's switchOn colour with a near-black knob on the right. Or green
	and red whatever the theme (`Theme:SetSwitchColours("redgreen")`). In the
	Blizzard skin a Blizzard check box. ]]
Theme.SWITCH_ON = { 0.22, 0.68, 0.32 }
Theme.SWITCH_OFF = { 0.76, 0.24, 0.20 }
Theme.SWITCH_KNOB = { 0.96, 0.96, 0.94 }
Theme.SWITCH_KNOB_ON = { 0.04, 0.05, 0.04 }

Theme.switchColours = "theme"
local switches = setmetatable({}, { __mode = "k" })

function Theme:SetSwitchColours(style)
	self.switchColours = style == "redgreen" and "redgreen" or "theme"
	for row in pairs(switches) do row:SetOn(row.__on) end
	return self.switchColours
end

-- Shared by the switch and the check box: dimmed and not clickable while held.
local function SetLocked(self, locked)
	self:SetEnabled(not locked)
	self:SetAlpha(locked and 0.45 or 1)
end

--[[ The Blizzard skin's switch and check box: the Options window's own
	check box (a dark square, a gold tick) and a gold label, with the row's API.
	The old check box art where a client lacks the new. ]]
local function BlizzardCheckRow(parent, label, onChange)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(24)
	local box = row:CreateTexture(nil, "ARTWORK")
	box:SetSize(24, 24)
	box:SetPoint("LEFT", row, "LEFT", -2, 0)
	local tick = row:CreateTexture(nil, "OVERLAY")
	tick:SetAllPoints(box)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(box)
	if Modern.Atlas(box, "checkbox-minimal") and Modern.Atlas(tick, "checkmark-minimal") then
		Modern.Atlas(hl, "checkbox-minimal")
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.4)
	else
		box:SetTexture(Theme.blizzardArt.checkUp)
		tick:SetTexture(Theme.blizzardArt.checkCheck)
		hl:SetTexture(Theme.blizzardArt.checkHighlight)
		hl:SetBlendMode("ADD")
	end
	local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", box, "RIGHT", 4, 0)
	fs:SetJustifyH("LEFT")
	fs:SetText(label or "")
	row.track, row.knob, row.label, row.box = box, tick, fs, box

	function row:SetOn(on)
		self.__on = on and true or false
		tick:SetShown(self.__on)
	end
	function row:IsOn() return self.__on end
	row.SetLocked = SetLocked
	function row:Fit(width)
		if not width then
			self:SetWidth(26 + (fs:GetStringWidth() or 0) + 4)
			return 24
		end
		self:SetWidth(width)
		local room = width - 26
		fs:SetWidth(room)
		local sw = fs:GetStringWidth() or 0
		local lines = sw <= room and 1 or math.ceil(sw / (room * 0.95))
		local h = math.max(24, lines * 14 + 6)
		self:SetHeight(h)
		return h
	end
	row:SetScript("OnClick", function(self)
		self:SetOn(not self.__on)
		Compat.PlaySound(self.__on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if onChange then onChange(self.__on) end
	end)
	row:SetOn(false)
	return row
end

function Theme:Switch(parent, label, onChange)
	if self:IsBlizzard() then return BlizzardCheckRow(parent, label, onChange) end
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(22)

	local track = row:CreateTexture(nil, "ARTWORK")
	track:SetTexture(self.texture.switchTrack)
	track:SetSize(36, 20)
	track:SetPoint("LEFT", row, "LEFT", 0, 0)

	local knob = row:CreateTexture(nil, "OVERLAY")
	knob:SetTexture(self.texture.circleFill)
	knob:SetSize(16, 16)

	local fs = row:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "body", 13)
	fs:SetPoint("LEFT", track, "RIGHT", 9, 0)
	fs:SetText(label or "")
	fs:SetJustifyH("LEFT")
	self:TextColor(fs, "text")

	row.track, row.knob, row.label = track, knob, fs

	function row:SetOn(on)
		self.__on = on and true or false
		self.knob:ClearAllPoints()
		self.knob:SetPoint("LEFT", self.track, "LEFT", self.__on and 18 or 2, 0)
		if Theme.switchColours == "redgreen" then
			Theme:Tint(self.track, self.__on and Theme.SWITCH_ON or Theme.SWITCH_OFF)
			Theme:Tint(self.knob, Theme.SWITCH_KNOB)
		elseif self.__on then
			Theme:Tint(self.track, "switchOn")
			Theme:Tint(self.knob, Theme.SWITCH_KNOB_ON)
		else
			Theme:Tint(self.track, "text", 0.10)
			Theme:Tint(self.knob, "text")
		end
	end
	function row:IsOn() return self.__on end
	row.SetLocked = SetLocked

	--- Lay the row out `width` wide; a long label wraps and the row grows. Returns its height.
	function row:Fit(width)
		self:SetWidth(width)
		local room = width - 45
		self.label:SetWidth(room)
		local sw = self.label:GetStringWidth() or 0
		local lines = sw <= room and 1 or math.ceil(sw / (room * 0.95))
		local h = math.max(22, lines * 15 + 4)
		self:SetHeight(h)
		return h
	end

	row:SetScript("OnClick", function(self)
		self:SetOn(not self.__on)
		if onChange then onChange(self.__on) end
	end)

	switches[row] = true
	row:SetOn(false)
	return row
end

--[[ A checkbox and its label, the whole row clickable: for a few choices side
	by side. Same methods as a switch. ]]
function Theme:Checkbox(parent, label, onChange)
	if self:IsBlizzard() then return BlizzardCheckRow(parent, label, onChange) end
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(22)

	local edge = row:CreateTexture(nil, "BORDER")
	edge:SetTexture(self.texture.solid)
	edge:SetSize(16, 16)
	edge:SetPoint("LEFT", row, "LEFT", 0, 0)
	local fill = row:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(self.texture.solid)
	fill:SetSize(14, 14)
	fill:SetPoint("CENTER", edge, "CENTER", 0, 0)
	local tick = row:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(self.glyph.tick)
	tick:SetSize(12, 12)
	tick:SetPoint("CENTER", edge, "CENTER", 0, 0)
	self:Tint(tick, "text")

	local fs = row:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "body", 13)
	fs:SetPoint("LEFT", edge, "RIGHT", 8, 0)
	fs:SetText(label or "")
	self:TextColor(fs, "text")

	row.edge, row.fill, row.tick, row.label = edge, fill, tick, fs

	function row:SetOn(on)
		self.__on = on and true or false
		if self.__on then
			Theme:Tint(self.edge, "accent")
			Theme:Tint(self.fill, "switchOn")
			self.tick:Show()
		else
			Theme:Tint(self.edge, "subtle")
			Theme:Tint(self.fill, "panel2")
			self.tick:Hide()
		end
	end
	function row:IsOn() return self.__on end
	row.SetLocked = SetLocked
	function row:Fit()
		self:SetWidth(24 + (self.label:GetStringWidth() or 0) + 4)
		return 22
	end

	row:SetScript("OnClick", function(self)
		self:SetOn(not self.__on)
		if onChange then onChange(self.__on) end
	end)

	row:SetOn(false)
	return row
end

--[[ A slider: its label on the left, the value on the right, and a thin track
	under them. `format(value)` writes the value; `onChange(value)` hears what
	the player drags to, snapped to `step`, once the mouse is released -- a
	change that scales the window the slider sits in would otherwise chase
	itself to one end. Never a SetValue from code. ]]
function Theme:Slider(parent, label, lo, hi, step, onChange, format)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(38)

	local fs = row:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "body", 13)
	fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
	fs:SetJustifyH("LEFT")
	fs:SetText(label or "")
	self:TextColor(fs, "text")

	local val = row:CreateFontString(nil, "OVERLAY")
	self:SetFont(val, "body", 13)
	val:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
	val:SetJustifyH("RIGHT")
	self:TextColor(val, "accent")

	local s = CreateFrame("Slider", nil, row)
	s:SetOrientation("HORIZONTAL")
	s:SetHeight(16)
	s:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	s:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	s:EnableMouse(true)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)

	local track
	if self:IsBlizzard() then
		-- The Options window's slider: a thin dark bar and a diamond thumb.
		local left, middle, right = s:CreateTexture(nil, "BACKGROUND"), s:CreateTexture(nil, "BACKGROUND"),
			s:CreateTexture(nil, "BACKGROUND")
		if Modern.Atlas(left, "Minimal_SliderBar_Left", true) and Modern.Atlas(right, "Minimal_SliderBar_Right", true)
			and Modern.Atlas(middle, "_Minimal_SliderBar_Middle", true) then
			left:SetPoint("LEFT", s, "LEFT", 0, 0)
			right:SetPoint("RIGHT", s, "RIGHT", 0, 0)
			middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
			middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
			s:SetThumbTexture(self.texture.solid)
			if not Modern.Atlas(s:GetThumbTexture(), "Minimal_SliderBar_Button", true) then
				s:SetThumbTexture(self.blizzardArt.sliderThumb)
				s:GetThumbTexture():SetSize(32, 32)
			end
		else
			self:Backdrop(s, "slider")
			s:SetThumbTexture(self.blizzardArt.sliderThumb)
			s:GetThumbTexture():SetSize(32, 32)
		end
		self:TextColor(fs, "accent")
		self:TextColor(val, "text")
		track = NOOP_TINT
	else
		track = s:CreateTexture(nil, "BACKGROUND")
		track:SetTexture(self.texture.solid)
		track:SetHeight(4)
		track:SetPoint("LEFT", s, "LEFT", 0, 0)
		track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
		self:Tint(track, "text", 0.14)
		s:SetThumbTexture(self.texture.circleFill)
		local thumb = s:GetThumbTexture()
		thumb:SetSize(14, 14)
		self:Tint(thumb, "accent")
	end

	local function Show(v)
		val:SetText(format and format(v) or tostring(v))
	end
	local pending
	s:SetScript("OnValueChanged", function(self, value)
		local v = math.floor(value / step + 0.5) * step
		Show(v)
		if self.__quiet or not onChange then return end
		if self.__held then pending = v else pending = nil; onChange(v) end
	end)
	local function release()
		s.__held = nil
		if pending ~= nil and onChange then
			local v = pending
			pending = nil
			onChange(v)
		end
	end
	s:SetScript("OnMouseDown", function() s.__held = true end)
	s:SetScript("OnMouseUp", release)
	s:SetScript("OnHide", release)

	row.slider, row.label, row.value, row.track = s, fs, val, track
	function row:SetValue(v)
		s.__quiet = true
		s:SetValue(v)
		s.__quiet = nil
		Show(v)
	end
	function row:GetValue() return s:GetValue() end
	function row:Fit(width)
		self:SetWidth(width)
		return self:GetHeight()
	end
	return row
end

--[[ The concept's <select>: a button showing the current choice with a caret,
	and a list that opens under it, parented to UIParent at a higher strata so
	a scrolling panel cannot draw over it. ]]
function Theme:Dropdown(parent, width, onSelect)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 30)
	local blizzardArrow = false
	if self:IsBlizzard() then
		-- The dropdown of today's windows: a dark text holder with a gold arrow button.
		local holder = b:CreateTexture(nil, "BACKGROUND")
		holder:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 3)
		holder:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
		if Modern.Atlas(holder, "common-dropdown-textholder") then
			b.fill = NOOP_TINT
			blizzardArrow = true
		else
			holder:Hide()
			b.fill = Modern.Inset(b)
		end
	else
		b.fill = self:NineSlice(b, self.texture.tabFill, "BACKGROUND", "panel2")
		self:NineSlice(b, self.texture.tabBorder, "BORDER", "border")
	end

	local fs = b:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "body", 13)
	fs:SetPoint("LEFT", b, "LEFT", 10, 0)
	fs:SetPoint("RIGHT", b, "RIGHT", -24, 0)
	fs:SetJustifyH("LEFT")
	self:TextColor(fs, "text")

	local caret = b:CreateTexture(nil, "OVERLAY")
	caret:SetTexture(self.glyph.caretDown)
	caret:SetSize(10, 10)
	caret:SetPoint("RIGHT", b, "RIGHT", -10, 0)
	if blizzardArrow and Modern.Atlas(caret, "common-dropdown-a-button", true) then
		caret:ClearAllPoints()
		caret:SetPoint("RIGHT", b, "RIGHT", 2, -2)
		-- The atlas is gold already: untinted, and left out of re-tinting on a theme change.
		caret:SetVertexColor(1, 1, 1, 1)
		b.arrowAtlas = true
	else
		self:Tint(caret, self:IsBlizzard() and "accent" or "textDim")
	end

	local list = CreateFrame("Frame", nil, UIParent)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetWidth(width)
	list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	self:Panel(list, "panel2", false)
	list:EnableMouse(true)
	list:Hide()
	self:Scaled(list)

	b.label, b.caret, b.list, b.items, b.rows = fs, caret, list, {}, {}

	--- items: a list of { value = ..., label = ... }
	function b:SetItems(items)
		self.items = items or {}
		for i, item in ipairs(self.items) do
			local row = self.rows[i]
			if not row then
				row = CreateFrame("Button", nil, self.list)
				row:SetHeight(22)
				row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 1, -(4 + (i - 1) * 22))
				row:SetPoint("RIGHT", self.list, "RIGHT", -1, 0)
				local hl = row:CreateTexture(nil, "HIGHLIGHT")
				hl:SetTexture(Theme.texture.solid)
				hl:SetAllPoints(row)
				hl:SetVertexColor(1, 1, 1, 0.06)
				row.text = row:CreateFontString(nil, "OVERLAY")
				Theme:SetFont(row.text, "body", 12)
				row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
				row.owner = self
				row:SetScript("OnClick", function(r)
					local owner = r.owner
					owner:SetValue(r.value)
					owner.list:Hide()
					if owner.onSelect then owner.onSelect(r.value) end
				end)
				self.rows[i] = row
			end
			row.value = item.value
			row.text:SetText(item.label)
			row:Show()
		end
		for i = #self.items + 1, #self.rows do self.rows[i]:Hide() end
		self.list:SetHeight(8 + #self.items * 22)
		self:SetValue(self.value)
	end

	function b:SetValue(value)
		self.value = value
		local shown = ""
		for _, item in ipairs(self.items) do
			if item.value == value then shown = item.label end
		end
		self.label:SetText(shown)
		for _, row in ipairs(self.rows) do
			Theme:TextColor(row.text, row.value == value and "accent" or "text")
		end
	end
	function b:GetValue() return self.value end

	b.onSelect = onSelect
	b:SetScript("OnClick", function(self)
		self.list:SetShown(not self.list:IsShown())
	end)
	b:SetScript("OnHide", function(self) self.list:Hide() end)
	b:SetScript("OnEnter", function(self)
		if self.arrowAtlas then Modern.Atlas(self.caret, "common-dropdown-a-button-hover", true) return end
		Theme:Tint(self.caret, Theme:IsBlizzard() and "text" or "accent")
	end)
	b:SetScript("OnLeave", function(self)
		if self.arrowAtlas then Modern.Atlas(self.caret, "common-dropdown-a-button", true) return end
		Theme:Tint(self.caret, Theme:IsBlizzard() and "accent" or "textDim")
	end)

	return b
end

--[[ Subhead: a `--tabbg` strip under the header naming the page, in small
	uppercase. The header carries the product, the subhead carries the page. ]]
function Theme:Subhead(frame, anchor, text)
	local s = CreateFrame("Frame", nil, frame)
	s:SetHeight(18)
	s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
	s:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	self:Strip(s, "tabbg")
	self:Divider(s, s, "BOTTOMLEFT", 0, 0)

	local fs = s:CreateFontString(nil, "OVERLAY")
	self:SetFont(fs, "display", 10)
	fs:SetPoint("LEFT", s, "LEFT", 14, 0)
	fs:SetText((text or ""):upper())
	self:TextColor(fs, self:IsBlizzard() and "accent" or "textDim")

	s.label = fs
	return s
end

--[[ A row in a list of pages or categories -- the options' pages, the guide
	browser's categories: the concept's faint fill and accent bar, or the
	Options window's own highlight for the row picked and the row hovered.
	Returns an object with SetActive(on). ]]
function Theme:ListRow(row)
	local art = {}
	if self:IsBlizzard() then
		local active = row:CreateTexture(nil, "BACKGROUND")
		active:SetAllPoints(row)
		if not Modern.Atlas(active, "Options_List_Active") then active:SetColorTexture(1, 0.82, 0, 0.18) end
		active:Hide()
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints(row)
		if not Modern.Atlas(hover, "Options_List_Hover") then hover:SetColorTexture(1, 1, 1, 0.08) end
		function art:SetActive(on) active:SetShown(on) end
		return art
	end
	local fill = row:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(self.texture.solid)
	fill:SetAllPoints(row)
	self:Tint(fill, "text", 0)
	local mark = row:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(self.texture.solid)
	mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	mark:SetWidth(3)
	self:Tint(mark, "accent")
	mark:Hide()
	row:HookScript("OnEnter", function() if not art.on then Theme:Tint(fill, "text", 0.04) end end)
	row:HookScript("OnLeave", function() if not art.on then Theme:Tint(fill, "text", 0) end end)
	function art:SetActive(on)
		self.on = on
		Theme:Tint(fill, "text", on and 0.08 or 0)
		mark:SetShown(on)
	end
	return art
end

--[[ A text box's frame: the concept's dark rounded field, or the search box of
	today's windows (its rounded left, middle and right). ]]
function Theme:EditBoxArt(box)
	if self:IsBlizzard() then
		local left, middle, right = box:CreateTexture(nil, "BACKGROUND"), box:CreateTexture(nil, "BACKGROUND"),
			box:CreateTexture(nil, "BACKGROUND")
		if Modern.Atlas(left, "common-search-border-left") and Modern.Atlas(right, "common-search-border-right")
			and Modern.Atlas(middle, "common-search-border-middle") then
			left:SetSize(8, box:GetHeight())
			left:SetPoint("LEFT", box, "LEFT", -2, 0)
			right:SetSize(8, box:GetHeight())
			right:SetPoint("RIGHT", box, "RIGHT", 2, 0)
			middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
			middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
			return
		end
		left:Hide(); middle:Hide(); right:Hide()
		Modern.Inset(box)
		return
	end
	self:NineSlice(box, self.texture.tabFill, "BACKGROUND", "panel2")
	self:NineSlice(box, self.texture.tabBorder, "BORDER", "subtle")
end

--[[ The whole window chrome in one call: header, a close chip, the drag
	wiring, and a subhead when the window names itself. ]]
function Theme:Chrome(frame, subtitle, onMoved, title)
	local header = self:Header(frame, nil, title)
	header:MakeDragHandle(frame, onMoved)

	local close = self:CloseChip(header, frame)
	self:PlaceClose(close, frame, header)

	local sub = subtitle and self:Subhead(frame, header, subtitle) or nil

	frame.header, frame.subhead, frame.closeChip = header, sub, close
	self:RegisterWindow(frame)
	return header, sub
end

--[[ Tooltip.

	GameTooltip is shared with the whole UI, so restyling it would restyle
	every other addon's tooltips as well. The Pathfinder skin has its own small
	dark card; the Blizzard skin uses GameTooltip as it is.
]]
local TIP_MAX_W = 260
local TIP_PAD = 8
local TIP_GAP = 3
local tip

local function TipLine(i)
	local fs = tip.lines[i]
	if not fs then
		fs = tip:CreateFontString(nil, "OVERLAY")
		Theme:SetFont(fs, "body", i == 1 and 12 or 11)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		fs:SetWordWrap(true)
		if i == 1 then
			fs:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, -TIP_PAD)
		else
			fs:SetPoint("TOPLEFT", tip.lines[i - 1], "BOTTOMLEFT", 0, -TIP_GAP)
		end
		tip.lines[i] = fs
	end
	return fs
end

local TIP_ANCHOR = {
	BOTTOM = { "TOP", "BOTTOM", 0, -4 },
	TOP    = { "BOTTOM", "TOP", 0, 4 },
	RIGHT  = { "BOTTOMLEFT", "TOPRIGHT", 0, 0 },
	LEFT   = { "BOTTOMRIGHT", "TOPLEFT", 0, 0 },
}
local TOOLTIP_ANCHOR = { BOTTOM = "ANCHOR_BOTTOM", TOP = "ANCHOR_TOP", RIGHT = "ANCHOR_RIGHT", LEFT = "ANCHOR_LEFT" }

-- Windows whose hints open outside them rather than over them.
local tipOutside = {}
local TIP_CLEAR = 4

function Theme:TipOutside(window)
	tipOutside[window] = true
end

--[[ Where a hint goes when its owner is in a TipOutside window: beside the
	window on the side facing the middle of the screen, level with the owner;
	with too little room there, below or above it. False when it fits nowhere
	outside. ]]
local function PlaceOutside(owner)
	local w = owner
	while w and not tipOutside[w] do w = w:GetParent() end
	if not w or not w:GetLeft() or not owner:GetLeft() then return false end
	local ws, os_, ts = w:GetEffectiveScale(), owner:GetEffectiveScale(), tip:GetEffectiveScale()
	local L, R, T, B = w:GetLeft() * ws, w:GetRight() * ws, w:GetTop() * ws, w:GetBottom() * ws
	local us = UIParent:GetEffectiveScale()
	local SW, SH = UIParent:GetWidth() * us, UIParent:GetHeight() * us
	local tw, th, gap = tip:GetWidth() * ts, tip:GetHeight() * ts, TIP_CLEAR * ts
	local x, y
	if (L + R) / 2 < SW / 2 then
		x = SW - R >= tw + gap and R + gap
	else
		x = L >= tw + gap and L - gap - tw
	end
	if x then
		y = math.min(math.max(owner:GetTop() * os_, th), SH)
	else
		local below, above = B - gap - th >= 0, SH - T >= th + gap
		if below and ((T + B) / 2 > SH / 2 or not above) then
			y = B - gap
		elseif above then
			y = T + gap + th
		else
			return false
		end
		x = math.min(math.max(owner:GetLeft() * os_, 0), SW - tw)
	end
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / ts, y / ts)
	return true
end

--- Show the hint for `owner`, opening on its `side`; `detail` is a list of
--- further lines (or one), `color` a theme colour for the hint.
function Theme:ShowTip(owner, side, text, detail, color)
	if not text or text == "" then return self:HideTip() end
	if type(detail) == "string" then detail = { detail } end

	if self:IsBlizzard() then
		GameTooltip:SetOwner(owner, TOOLTIP_ANCHOR[side] or "ANCHOR_BOTTOM")
		GameTooltip:SetText(text, 1, 0.82, 0, 1, true)
		for _, line in ipairs(detail or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
		GameTooltip:Show()
		self.tipOwner = owner
		return
	end

	if not tip then
		tip = CreateFrame("Frame", "AegisPathfinderTip", UIParent)
		tip:SetFrameStrata("TOOLTIP")
		tip:SetClampedToScreen(true)
		self:Panel(tip, "panel2")
		tip.lines = {}
		-- A hidden owner gets no OnLeave to take its hint with it.
		tip:SetScript("OnUpdate", function(self)
			if self.owner and not self.owner:IsVisible() then Theme:HideTip() end
		end)
		self.tip = tip
	end

	local all = { text }
	for _, line in ipairs(detail or {}) do all[#all + 1] = line end

	local width = 0
	for i, line in ipairs(all) do
		local fs = TipLine(i)
		fs:SetWidth(0)
		fs:SetText(line)
		width = math.max(width, fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth())
	end
	width = math.min(math.ceil(width) + 1, TIP_MAX_W)

	local height = 0
	for i = 1, #tip.lines do
		local fs = tip.lines[i]
		if i <= #all then
			fs:SetWidth(width)
			self:TextColor(fs, i == 1 and (color or "text") or "textDim")
			fs:Show()
			local h = fs:GetStringHeight() or 0
			if h < 1 then h = math.ceil(fs:GetStringWidth() / width) * 14 end
			height = height + h + (i > 1 and TIP_GAP or 0)
		else
			fs:Hide()
		end
	end

	tip:SetSize(width + TIP_PAD * 2, height + TIP_PAD * 2)
	if not PlaceOutside(owner) then
		local a = TIP_ANCHOR[side] or TIP_ANCHOR.BOTTOM
		tip:ClearAllPoints()
		tip:SetPoint(a[1], owner, a[2], a[3], a[4])
	end
	tip.owner = owner
	tip:Show()
end

--- Hide the hint -- only if `owner` is the one showing it, when given.
function Theme:HideTip(owner)
	if self:IsBlizzard() then
		if owner and self.tipOwner ~= owner then return end
		self.tipOwner = nil
		GameTooltip:Hide()
		return
	end
	if not tip then return end
	if owner and tip.owner ~= owner then return end
	tip.owner = nil
	tip:Hide()
end

--[[ Window stacking.

	Every window lives in the DIALOG strata, and the client draws a strata in
	frame-level order across windows, so two overlapping windows built at the
	same level interleave. Showing one, or grabbing its header, moves its whole
	frame tree above every other open window's; levels are rebuilt from
	STACK_BASE every time rather than raised, so they never climb.
]]
local STACK_BASE = 10
local STACK_GAP = 4
Theme.windows = {}

local function Descendants(f, out)
	for _, k in ipairs({ f:GetChildren() }) do
		out[#out + 1] = k
		Descendants(k, out)
	end
	return out
end

local function Restack(w, base)
	local root = w:GetFrameLevel()
	local tree = Descendants(w, {})
	local offsets = {}
	for i, k in ipairs(tree) do offsets[i] = math.max(k:GetFrameLevel() - root, 1) end
	w:SetFrameLevel(base)
	local top = base
	for i, k in ipairs(tree) do
		local level = base + offsets[i]
		k:SetFrameLevel(level)
		if level > top then top = level end
	end
	return top
end

--[[ Window scale: one scale for every Pathfinder window, set on the
	Appearance page. ]]
Theme.SCALE_MIN, Theme.SCALE_MAX, Theme.SCALE_STEP = 0.6, 1.5, 0.05
Theme.windowScale = 1
Theme.scaled = {}

function Theme:Scaled(frame)
	for _, f in ipairs(self.scaled) do
		if f == frame then return frame end
	end
	self.scaled[#self.scaled + 1] = frame
	if frame.SetScale then frame:SetScale(self.windowScale * (frame.scaleFactor or 1)) end
	return frame
end

function Theme:SetWindowScale(scale)
	scale = tonumber(scale) or 1
	scale = math.floor(scale / self.SCALE_STEP + 0.5) * self.SCALE_STEP
	scale = math.max(self.SCALE_MIN, math.min(self.SCALE_MAX, scale))
	self.windowScale = scale
	for _, f in ipairs(self.scaled) do
		if f.SetScale then f:SetScale(scale * (f.scaleFactor or 1)) end
	end
	return scale
end

function Theme:RegisterWindow(frame)
	if self:IsWindow(frame) then return frame end
	self.windows[#self.windows + 1] = frame
	self:Scaled(frame)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:HookScript("OnShow", function() Theme:BringToFront(frame) end)
	return frame
end

function Theme:IsWindow(frame)
	for _, w in ipairs(self.windows) do
		if w == frame then return true end
	end
	return false
end

function Theme:BringToFront(frame)
	if not self:IsWindow(frame) then return end
	local order, index = {}, {}
	for i, w in ipairs(self.windows) do
		index[w] = i
		if w ~= frame and w:IsShown() then order[#order + 1] = w end
	end
	table.sort(order, function(a, b)
		local la, lb = a:GetFrameLevel(), b:GetFrameLevel()
		if la ~= lb then return la < lb end
		return index[a] < index[b]
	end)
	order[#order + 1] = frame

	local cursor = STACK_BASE
	for _, w in ipairs(order) do
		cursor = Restack(w, cursor) + 1 + STACK_GAP
	end
end

--[[ Pin a frame by its top-left corner, exactly where it is now: one TOPLEFT
	anchor on UIParent's bottom-left is the one arrangement where a window grows
	down and to the right and its height is its own. ]]
function Theme:AnchorTopLeft(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return false end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	return true
end

--- Persist a frame's position under `key` in the profile, as a drag callback.
function Theme:PositionSaver(key)
	return function(f)
		local point, _, rel, x, y = f:GetPoint()
		local db = AP.db and AP.db.profile
		if not db then return end
		db[key .. "point"], db[key .. "rel"] = point, rel
		db[key .. "x"], db[key .. "y"] = x, y
	end
end

--- Restore what PositionSaver stored; nothing saved leaves the frame's own anchors alone.
function Theme:RestorePosition(frame, key)
	local db = AP.db and AP.db.profile
	if not db or not db[key .. "point"] then return false end
	local point = db[key .. "point"]
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, db[key .. "rel"] or point, db[key .. "x"], db[key .. "y"])
	return true
end

function Theme:ForgetPosition(key)
	local db = AP.db and AP.db.profile
	if not db then return end
	db[key .. "point"], db[key .. "rel"], db[key .. "x"], db[key .. "y"] = nil, nil, nil, nil
end

function Theme:SetActionIcon(tex, code)
	tex:SetTexture(self.actionIcon[code] or self.actionIcon.N)
	self:Tint(tex, "textDim")
	return tex
end

--[[ Choosing a theme ]]

function AP:GetTheme()
	local key = self.db and self.db.profile.theme
	key = Theme.RENAMED[key] or key
	return Theme.themeByKey[key] and key or Theme.DEFAULT_THEME
end

function AP:SetWindowScale(scale)
	self.db.profile.windowscale = Theme:SetWindowScale(scale)
	return self.db.profile.windowscale
end

function AP:SetSwitchColours(style)
	self.db.profile.switchcolours = Theme:SetSwitchColours(style)
	return self.db.profile.switchcolours
end

--[[ A question with two answers, in the addon's own window.

	Not the game's StaticPopup. 0.1.0 wrote `StaticPopupDialogs =
	StaticPopupDialogs or {}`, which taints that global. Blizzard_Calendar,
	loaded later on demand, reads it at the top of its file and then calls
	RegisterGameMenuEscHandler, whose table.sort taints the game's list of
	Escape handlers. From then on, every Escape fails with "ADDON FORBIDDEN:
	SpellStopCasting()". This dialog touches nothing of Blizzard's.

	Theme:Confirm{ text =, accept =, cancel =, onAccept = function, onCancel = function,
		reload = true when Accept reloads the interface (see Theme:OfferReload) }
]]
local confirm

function Theme:Confirm(spec)
	if not confirm then
		confirm = CreateFrame("Frame", "AegisPathfinderConfirm", UIParent)
		confirm:SetFrameStrata("FULLSCREEN_DIALOG")
		confirm:SetSize(340, 150)
		confirm:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
		confirm:EnableMouse(true)
		self:Panel(confirm, "panel")
		local header = self:Chrome(confirm, nil, nil, AP.L.TITLE)
		confirm.text = confirm:CreateFontString(nil, "OVERLAY")
		self:SetFont(confirm.text, "body", 13)
		self:TextColor(confirm.text, "text")
		confirm.text:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 16, -14)
		confirm.text:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -16, -14)
		confirm.text:SetJustifyH("CENTER")
		confirm.text:SetWordWrap(true)
		confirm.yes = self:PanelButton(confirm, "", 140, 24)
		confirm.no = self:PanelButton(confirm, "", 140, 24)
		local m = self.metrics
		confirm.yes:SetPoint("BOTTOMLEFT", confirm, "BOTTOMLEFT", 14 + m.left, 12 + m.bottom)
		confirm.no:SetPoint("BOTTOMRIGHT", confirm, "BOTTOMRIGHT", -14 - m.right, 12 + m.bottom)
		confirm.yes:SetScript("OnClick", function(self)
			local spec = confirm.spec
			if spec and spec.reload then
				-- Reached only when the secure button over it wasn't there (Theme:OfferReload):
				-- in combat the dialog goes; outside it, it stays for another try.
				if Theme:ReloadFallback(self) then confirm:Hide() end
				return
			end
			confirm:Hide()
			if spec and spec.onAccept then spec.onAccept() end
		end)
		confirm.no:SetScript("OnClick", function()
			local spec = confirm.spec
			confirm:Hide()
			if spec and spec.onCancel then spec.onCancel() end
		end)
		tinsert(UISpecialFrames, "AegisPathfinderConfirm")
		Theme:OfferReload(confirm.yes, function() return confirm.spec and confirm.spec.reload end)
		confirm:Hide()
	end
	confirm.spec = spec
	confirm.text:SetText(spec.text or "")
	confirm.yes:SetText(spec.accept or YES or "Yes")
	confirm.no:SetText(spec.cancel or NO or "No")
	confirm:Show()
	self:BringToFront(confirm)
	self:SyncReload(confirm.yes)
	return confirm
end

--[[ Reloading the interface.

	The game lets only its own code reload the interface: ReloadUI() from an
	addon is "ADDON BLOCKED: Reload()", even from a click. A secure action
	button running the /reload macro goes through Blizzard's code instead. So
	each of our Reload buttons gets one such button, invisible, lying over it
	for as long as it is shown, outside combat: the click lands on that.

	It lies there from the moment the button shows, and follows it if its
	window moves. 0.2.0 put it there only as the mouse arrived: a frame moved
	under the mouse can trade the mouse back and forth with the one below it,
	and the click then reached our own button, which only said to type /reload.

	It belongs to UIParent, not to our windows: a window holding a secure
	button becomes protected, and could then not be hidden or moved in a fight.
	A secure button can be set up, moved, shown and hidden only out of combat:
	they step aside as combat starts, and in combat our own button takes the
	click and says to type /reload. ]]
local covers = {} -- our Reload button -> { cover = its secure button, active = function or nil }

-- Our button looks hovered while the mouse is on the secure button over it.
local function Hover(host, on)
	if host.LockHighlight then
		if on then host:LockHighlight() else host:UnlockHighlight() end
	end
	local script = host:GetScript(on and "OnEnter" or "OnLeave")
	if script then script(host) end
end

-- Over its button, in the same strata and above it. False while the button has no place yet.
local function Place(cover, host)
	local x, y = host:GetCenter()
	if not x then return false end
	local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local w, h = host:GetWidth() * scale, host:GetHeight() * scale
	x, y = x * scale, y * scale
	if cover.x ~= x or cover.y ~= y or cover.w ~= w or cover.h ~= h then
		cover:ClearAllPoints()
		cover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		cover:SetSize(w, h)
		cover.x, cover.y, cover.w, cover.h = x, y, w, h
	end
	local strata, level = host:GetFrameStrata(), host:GetFrameLevel() + 20
	if cover:GetFrameStrata() ~= strata then cover:SetFrameStrata(strata) end
	if cover:GetFrameLevel() ~= level then cover:SetFrameLevel(level) end
	return true
end

local function Wanted(host)
	local entry = covers[host]
	return entry ~= nil and host:IsVisible() and (not entry.active or entry.active()) and true or false
end

local function Leave(cover)
	if not cover:IsShown() then return end
	cover:Hide()
	if cover.hovered then
		cover.hovered = nil
		Hover(cover.host, false)
	end
end

local Sync

local function NewCover(host)
	local cover = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	cover:EnableMouse(true)
	cover:RegisterForClicks("AnyUp")
	cover:SetAttribute("useOnKeyDown", false)
	cover:SetAttribute("type", "macro")
	cover:SetAttribute("macrotext", "/reload")
	cover:Hide()
	cover.host = host
	cover.tint = cover:CreateTexture(nil, "OVERLAY")
	cover.tint:SetAllPoints(cover)
	cover.tint:SetColorTexture(1, 0.1, 0.1, 0.4)
	cover.tint:SetShown(Theme.reloadDebug == true)
	cover:SetScript("OnEnter", function(self) self.hovered = true; Hover(self.host, true) end)
	cover:SetScript("OnLeave", function(self) self.hovered = nil; Hover(self.host, false) end)
	cover:HookScript("OnMouseDown", function(self)
		if self.host.SetButtonState then self.host:SetButtonState("PUSHED") end
	end)
	cover:HookScript("OnMouseUp", function(self)
		if self.host.SetButtonState then self.host:SetButtonState("NORMAL") end
	end)
	cover:SetScript("OnUpdate", function(self)
		if Compat.InCombat() then return end
		if Wanted(self.host) then Place(self, self.host) else Leave(self) end
	end)
	return cover
end

--- Puts the secure button over `host`, or takes it away, as the button is shown
--- and wanted. Out of combat only.
function Sync(host)
	local entry = covers[host]
	if not entry or Compat.InCombat() then return end
	if not Wanted(host) then
		if entry.cover then Leave(entry.cover) end
		return
	end
	entry.cover = entry.cover or NewCover(host)
	if Place(entry.cover, host) then
		entry.waits = 0
		entry.cover:Show()
	elseif (entry.waits or 0) < 10 and C_Timer and C_Timer.After then
		-- Shown this very moment: its window has no place on screen until the next frame.
		entry.waits = (entry.waits or 0) + 1
		C_Timer.After(0, function() Sync(host) end)
	end
end

-- Out of the way before combat starts (they couldn't be hidden during it), and back after.
AP:On("PLAYER_REGEN_DISABLED", function()
	for _, entry in pairs(covers) do
		if entry.cover then Leave(entry.cover) end
	end
end)
AP:On("PLAYER_REGEN_ENABLED", function()
	for host in pairs(covers) do Sync(host) end
end)

--- Makes `button` reload the interface when clicked, outside combat, while `active()` (if given) says so.
--- Its own OnClick runs only when the secure button isn't over it: have it call Theme:ReloadFallback().
function Theme:OfferReload(button, active)
	covers[button] = covers[button] or {}
	covers[button].active = active
	button:HookScript("OnShow", Sync)
	button:HookScript("OnHide", Sync)
	Sync(button)
end

--- After `active()` changed for a button already on screen.
function Theme:SyncReload(button) Sync(button) end

--- The secure button over `button`, if it has one (for the smoke test).
function Theme:ReloadCover(button) return covers[button] and covers[button].cover end

-- Where a frame is, in UIParent's units: "left,bottom widthxheight".
local function Where(f)
	local left, bottom = f:GetLeft(), f:GetBottom()
	if not left then return "nowhere" end
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local function n(v) return math.floor((v or 0) * s + 0.5) end
	return n(left) .. "," .. n(bottom) .. " " .. n(f:GetWidth()) .. "x" .. n(f:GetHeight())
end

local function Named(f)
	if not f then return "nothing" end
	if f == UIParent or f == WorldFrame then return f:GetName() end
	for host, entry in pairs(covers) do
		if entry.cover == f then return "the secure button" end
		if host == f then return "our Reload" end
	end
	local ok, name = pcall(function() return f.GetDebugName and f:GetDebugName() or f:GetName() end)
	return ok and name and name ~= "" and name or "a frame"
end

local function UnderMouse()
	if GetMouseFoci then
		local names = {}
		for _, f in ipairs(GetMouseFoci() or {}) do
			names[#names + 1] = Named(f)
			if #names == 3 then break end
		end
		return #names > 0 and table.concat(names, ", ") or "nothing"
	end
	return GetMouseFocus and Named(GetMouseFocus()) or "?"
end

--- One line on the secure button over `host`: whether it is there, where, in which
--- layer, and what has the mouse. For a click that missed it, and /apg reloaddebug.
function Theme:ReloadReport(host)
	local entry = host and covers[host]
	local cover = entry and entry.cover
	if not cover then
		return "no secure button yet (wanted: " .. tostring(host ~= nil and Wanted(host)) .. ")"
	end
	local mouse = cover.IsMouseClickEnabled and cover:IsMouseClickEnabled() or cover:IsMouseEnabled()
	return ("secure button shown %s, visible %s, takes clicks %s, under the mouse %s; %s %d over Reload's %s %d;"
		.. " at %s, Reload at %s; the mouse is on %s"):format(
		tostring(cover:IsShown()), tostring(cover:IsVisible()), tostring(mouse), tostring(cover:IsMouseOver()),
		tostring(cover:GetFrameStrata()), cover:GetFrameLevel() or -1, tostring(host:GetFrameStrata()),
		host:GetFrameLevel() or -1, Where(cover), Where(host), UnderMouse())
end

--- Our own Reload button was clicked. In combat that's expected: true, say to type
--- /reload. Outside it the secure button wasn't there: say so, with what we can see.
function Theme:ReloadFallback(host)
	if Compat.InCombat() then
		AP:Print(AP.L.TYPE_RELOAD)
		return true
	end
	AP:Print(AP.L.TYPE_RELOAD_MISSED)
	AP:Print(AP.L.RELOAD_CHECK .. self:ReloadReport(host))
	return false
end

--- /apg reloaddebug: tints the secure buttons red, and reports each one on screen.
function Theme:ToggleReloadDebug()
	self.reloadDebug = not self.reloadDebug
	AP:Print(self.reloadDebug and AP.L.RELOAD_DEBUG_ON or AP.L.RELOAD_DEBUG_OFF)
	for host, entry in pairs(covers) do
		if entry.cover then entry.cover.tint:SetShown(self.reloadDebug) end
		if self.reloadDebug and host:IsVisible() then AP:Print(AP.L.RELOAD_CHECK .. self:ReloadReport(host)) end
	end
end

--- Save and apply a theme. A colour theme applies at once; moving to or from
--- the Blizzard skin asks to reload, since its widgets are other frames.
function AP:SetTheme(key)
	local def = Theme.themeByKey[key] or Theme.themeByKey[Theme.DEFAULT_THEME]
	self.db.profile.theme = def.key
	if (def.skin or "pathfinder") ~= Theme.skin then
		-- The Reload button reloads through the secure button over it (Theme:OfferReload);
		-- a click that reaches the button itself was in combat.
		Theme:Confirm({ text = AP.L.RELOAD_FOR_SKIN, accept = AP.L.RELOAD, cancel = AP.L.LATER, reload = true })
		return def
	end
	Theme:ApplyTheme(def.key)
	for _, refresh in ipairs({ "RefreshObjectivePanel", "RefreshConfigPanel", "RefreshGuideBrowser",
		"RefreshCollectorFrame", "UpdateMinimapButton" }) do
		if self[refresh] then self[refresh](self) end
	end
	return def
end

--[[ The skin and the colours are fixed from the saved theme before any window
	is built: every window builds itself after this (UI/*.lua register later). ]]
AP:OnInit(function()
	local profile = AP.db.profile
	profile.theme = Theme.RENAMED[profile.theme] or profile.theme
	Theme:ChooseSkin(profile.theme)
	Theme:ApplyTheme(profile.theme)
	Theme:SetWindowScale(profile.windowscale or 1)
	Theme:SetSwitchColours(profile.switchcolours)
end)
