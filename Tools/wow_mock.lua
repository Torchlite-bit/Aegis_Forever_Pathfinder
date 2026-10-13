--[[
	Stand-ins for the parts of the WoW: Forever API the addon uses, for
	Tools/smoke_test.py. Modelled on the Aegis: Forever Instance Journal's mock.

	This is not an emulator. Frames remember what was set on them and run their
	scripts when told to; unknown methods are quiet no-ops. The quest, map, unit
	and reputation calls answer from WOWMOCK.state, which the scenario sets, so a
	quest can be offered, accepted, progressed and handed in without a client.
	The point is to catch errors in the addon's own logic -- a nil called, a wrong
	field, a broken merge -- before a client restart.
]]

local Mock = { chat = {}, frames = {}, events = {}, timers = {}, now = 1000, popups = {}, sent = {}, hooks = {} }
WOWMOCK = Mock

-- Which templates the Forever client lacks (Aegis Probe, 1.60.1).
Mock.missingTemplates = { ItemButtonTemplate = true }

------------------------------------------------------------------------------------------
-- Regions
------------------------------------------------------------------------------------------

local Region = {}
local RegionMeta = {
	__index = function(self, key)
		local method = Region[key]
		if method then return method end
		if type(key) == "string" and key:match("^%u") then return function() end end
		return nil
	end,
}

local function NewRegion(objectType, name, parent)
	local region = setmetatable({
		_type = objectType, _name = name, _parent = parent, _shown = true, _points = {}, _scripts = {},
		_hooks = {}, _width = 0, _height = 0, _level = parent and (rawget(parent, "_level") or 0) + 1 or 1,
		_alpha = 1, _min = 0, _max = 0, _value = 0, _scroll = 0, _scale = 1,
	}, RegionMeta)
	if name then _G[name] = region end
	if parent and objectType ~= "Texture" and objectType ~= "FontString" then
		local children = rawget(parent, "_children")
		if not children then
			children = {}
			rawset(parent, "_children", children)
		end
		children[#children + 1] = region
	end
	return region
end
Mock.NewRegion = NewRegion

function Region:GetObjectType() return self._type end
function Region:GetName() return self._name end
function Region:GetParent() return self._parent end
function Region:SetParent(parent) self._parent = parent end
function Region:GetChildren() return unpack(rawget(self, "_children") or {}) end
function Region:Show() local was = self._shown; self._shown = true; if not was then self:_Run("OnShow") end end
function Region:Hide() local was = self._shown; self._shown = false; if was then self:_Run("OnHide") end end
function Region:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown end
function Region:IsVisible()
	if not self._shown then return false end
	local parent = self._parent
	if parent and parent ~= UIParent and parent.IsVisible then return parent:IsVisible() end
	return true
end
function Region:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Region:ClearAllPoints() self._points = {} end
function Region:GetNumPoints() return #self._points end
function Region:GetPoint(index)
	local p = self._points[index or 1]
	if not p then return nil end
	if type(p[2]) == "number" or p[2] == nil then return p[1], self._parent, p[1], p[2] or 0, p[3] or 0 end
	return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0
end
function Region:SetAllPoints(target) self._points = { { "ALL", target } } end
function Region:SetSize(w, h) self._width, self._height = w, h end
function Region:SetWidth(w)
	assert(type(w) == "number", "SetWidth needs a number")
	local was = self._width
	self._width = w
	if was ~= w then self:_Run("OnSizeChanged", w, self._height) end
end
function Region:SetHeight(h)
	assert(type(h) == "number", "SetHeight needs a number")
	local was = self._height
	self._height = h
	if was ~= h then self:_Run("OnSizeChanged", self._width, h) end
end
function Region:GetWidth() return self._width end
function Region:GetHeight() return self._height end
function Region:GetSize() return self._width, self._height end
function Region:GetLeft() return 600 end
function Region:GetRight() return 600 + self._width end
function Region:GetTop() return 700 end
function Region:GetBottom() return 700 - self._height end
function Region:GetCenter() return 600, 600 end
function Region:GetEffectiveScale() return 1 end
function Region:SetScale(scale) self._scale = scale end
function Region:GetScale() return self._scale end
function Region:SetAlpha(alpha) self._alpha = alpha end
function Region:GetAlpha() return self._alpha end
function Region:SetFrameLevel(level) self._level = level end
function Region:GetFrameLevel() return self._level end
function Region:SetText(text) self._text = text end
function Region:GetText() return self._text end
function Region:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Region:GetStringWidth() return #(tostring(self._text or "")) * 6 end
function Region:GetUnboundedStringWidth() return #(tostring(self._text or "")) * 6 end
function Region:GetStringHeight()
	local width = self._width > 0 and self._width or 1e9
	return math.max(1, math.ceil(self:GetStringWidth() / width)) * 14
end
function Region:SetFont(path, size, flags)
	assert(type(path) == "string" and path ~= "", "SetFont needs a font file")
	assert(type(size) == "number" and size > 0, "SetFont needs a height")
	self._font = { path, size, flags }
	return true
end
function Region:GetFont() local f = self._font or {} return f[1], f[2], f[3] end
function Region:SetTexture(texture) self._texture = texture; return true end
function Region:GetTexture() return self._texture end
function Region:SetVertexColor(r, g, b, a) self._color = { r, g, b, a } end
function Region:GetVertexColor() local c = self._color or {} return c[1], c[2], c[3], c[4] end
function Region:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
function Region:CreateTexture(name) return NewRegion("Texture", name, self) end
function Region:CreateFontString(name) return NewRegion("FontString", name, self) end

-- Scripts: SetScript replaces the handler and drops hooks, as the client does.
function Region:SetScript(name, fn) self._scripts[name] = fn; self._hooks[name] = nil end
function Region:GetScript(name) return self._scripts[name] end
function Region:HookScript(name, fn)
	self._hooks[name] = self._hooks[name] or {}
	table.insert(self._hooks[name], fn)
end
function Region:HasScript() return true end
function Region:_Run(name, ...)
	local fn = self._scripts[name]
	if fn then fn(self, ...) end
	for _, hook in ipairs(self._hooks[name] or {}) do hook(self, ...) end
end

function Region:RegisterEvent(event)
	if Mock.unknownEvents and Mock.unknownEvents[event] then error("unknown event " .. event) end
	Mock.events[event] = Mock.events[event] or {}
	Mock.events[event][self] = true
end
function Region:UnregisterEvent(event) if Mock.events[event] then Mock.events[event][self] = nil end end
function Region:UnregisterAllEvents() for _, set in pairs(Mock.events) do set[self] = nil end end

-- Buttons, check buttons, sliders, status bars, scroll frames, edit boxes.
function Region:Enable() self._enabled = true end
function Region:Disable() self._enabled = false end
function Region:SetEnabled(on) self._enabled = on and true or false end
function Region:IsEnabled() return self._enabled ~= false end
function Region:GetFontString() self._fs = self._fs or NewRegion("FontString", nil, self) return self._fs end
function Region:SetChecked(on) self._checked = on end
function Region:GetChecked() return self._checked end
function Region:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function Region:GetMinMaxValues() return self._min, self._max end
function Region:SetValue(v)
	v = math.max(self._min, math.min(self._max, v))
	local was = self._value
	self._value = v
	if was ~= v or self._type == "Slider" then self:_Run("OnValueChanged", v) end
end
function Region:GetValue() return self._value end
function Region:SetThumbTexture(path) self._thumb = self._thumb or NewRegion("Texture", nil, self); self._thumb._texture = path end
function Region:GetThumbTexture() self._thumb = self._thumb or NewRegion("Texture", nil, self) return self._thumb end
function Region:SetStatusBarTexture(path) self._barTexture = path end
function Region:SetVerticalScroll(v) self._scroll = v end
function Region:GetVerticalScroll() return self._scroll end
function Region:GetVerticalScrollRange() return 1000 end
function Region:SetScrollChild(child) self._child = child end
function Region:HasFocus() return self._focus == true end
function Region:SetFocus() self._focus = true end
function Region:ClearFocus() self._focus = false end
function Region:GetNumLines() return 0 end

-- Backdrops (BackdropTemplate).
function Region:SetBackdrop(info) self._backdrop = info end
function Region:GetBackdrop() return self._backdrop end
function Region:SetBackdropColor(...) self._backdropColor = { ... } end
function Region:SetBackdropBorderColor(...) self._backdropBorder = { ... } end

------------------------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------------------------

local TEMPLATE_SETUP = {
	BackdropTemplate = function(frame)
		frame.SetBackdrop = Region.SetBackdrop
		frame.OnBackdropSizeChanged = function() end
	end,
}

function CreateFrame(frameType, name, parent, template)
	if template then
		for t in tostring(template):gmatch("[^,%s]+") do
			if Mock.missingTemplates[t] then error("Couldn't find inherited node \"" .. t .. "\"", 2) end
		end
	end
	local frame = NewRegion(frameType, name, parent or UIParent)
	if template then
		for t in tostring(template):gmatch("[^,%s]+") do
			if TEMPLATE_SETUP[t] then TEMPLATE_SETUP[t](frame) end
		end
	end
	Mock.frames[#Mock.frames + 1] = frame
	return frame
end

UIParent = NewRegion("Frame", "UIParent")
UIParent._width, UIParent._height = 1920, 1080
UIParent.GetLeft = function() return 0 end
WorldFrame = NewRegion("Frame", "WorldFrame")
Minimap = NewRegion("Frame", "Minimap")
MerchantFrame = NewRegion("Frame", "MerchantFrame")
MerchantFrame._shown = false
QuestFrame = NewRegion("Frame", "QuestFrame")
GameTooltip = NewRegion("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(Mock.chat, text) end }
ChatFontNormal = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
Mock.staticPopupDialogs = StaticPopupDialogs
function StaticPopup_Show(name) table.insert(Mock.popups, name) return {} end
function ReloadUI() Mock.reloaded = true end

Mixin = function(object, ...)
	for index = 1, select("#", ...) do
		for key, value in pairs((select(index, ...))) do object[key] = value end
	end
	return object
end
BackdropTemplateMixin = { SetBackdrop = Region.SetBackdrop, OnBackdropSizeChanged = function() end }
C_XMLUtil = { GetTemplateInfo = function(name) if Mock.missingTemplates[name] then return nil end return {} end }

------------------------------------------------------------------------------------------
-- Lua and system helpers
------------------------------------------------------------------------------------------

function strsplit(sep, text)
	local out = {}
	for piece in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
	return unpack(out)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert = table.insert
tremove = table.remove
function geterrorhandler() return function(err) error(err, 0) end end
function hooksecurefunc(name, fn)
	local original = _G[name]
	Mock.hooks[name] = fn
	_G[name] = function(...)
		local results = { original(...) }
		fn(...)
		return unpack(results)
	end
end
function GetTime() return Mock.now end
function GetServerTime() return 1760000000 + math.floor(Mock.now) end
function GetBuildInfo() return "1.60.1", "70338", "Oct 10 2026", 16001 end
function issecretvalue(value) return Mock.secret ~= nil and Mock.secret[value] == true end
function InCombatLockdown() return false end
function IsInInstance() return Mock.state.inInstance or false, "none" end
function IsShiftKeyDown() return Mock.state.shift == true end
function IsMouseButtonDown() return false end
function GetCursorPosition() return 0, 0 end
function PlaySound() end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
YES, NO = "Yes", "No"
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
FACTION_STANDING_INCREASED_ACH_BONUS = "Reputation with %s increased by %d. (+%.1f bonus)"
FACTION_STANDING_DECREASED = "Reputation with %s decreased by %d."
for index, label in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
	_G["FACTION_STANDING_LABEL" .. index] = label
end
NUM_BAG_SLOTS = 4

C_AddOns = { GetAddOnMetadata = function(_, key) if key == "Version" then return "0.2.0" end end }
C_Timer = {
	After = function(seconds, fn) table.insert(Mock.timers, { at = Mock.now + seconds, fn = fn }) end,
}
--- Moves time on and runs what is due.
function Mock.Advance(seconds)
	Mock.now = Mock.now + (seconds or 0)
	local ran = true
	while ran do
		ran = false
		for index, timer in ipairs(Mock.timers) do
			if timer.at <= Mock.now then
				table.remove(Mock.timers, index)
				timer.fn()
				ran = true
				break
			end
		end
	end
end

--[[ The client's modern art, as the Forever client has it: the atlases the
	Blizzard skin asks for, and NineSliceUtil drawing a layout as textures on a
	frame. Mock.noModernArt (the "blizzard-plain" run) takes them away, so the
	skin's fallbacks are exercised too. ]]
Mock.atlases = {}
for name in ([[UI-Frame-Metal-CornerTopLeft Tooltip-NineSlice-CornerTopLeft UI-Frame-InnerTopLeft
	Options_HorizontalDivider checkbox-minimal checkmark-minimal !minimal-scrollbar-track-middle
	minimal-scrollbar-small-thumb-middle minimal-scrollbar-arrow-top minimal-scrollbar-arrow-bottom
	Minimal_SliderBar_Left Minimal_SliderBar_Right _Minimal_SliderBar_Middle Minimal_SliderBar_Button
	common-dropdown-textholder common-dropdown-a-button common-dropdown-a-button-hover Options_List_Active
	Options_List_Hover Options_CategoryHeader_1 common-search-border-left common-search-border-middle
	common-search-border-right]]):gmatch("%S+") do Mock.atlases[name] = true end
function Region:SetAtlas(name)
	assert(Mock.atlases[name], "no such atlas: " .. tostring(name))
	self._atlas = name
	return true
end
function Region:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Region:SetBlendMode(mode) self._blend = mode end
local LAYOUT_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge", "Center" }
function Mock.InstallModernArt()
	C_Texture = { GetAtlasInfo = function(name) if Mock.atlases[name] then return { width = 16, height = 16 } end end }
	NineSliceUtil = {
		GetLayout = function(name)
			if name == "ButtonFrameTemplateNoPortrait" or name == "TooltipDefaultLayout" or name == "InsetFrameTemplate" then
				return {}
			end
		end,
		ApplyLayoutByName = function(frame, name)
			assert(NineSliceUtil.GetLayout(name), "no such layout " .. tostring(name))
			for _, piece in ipairs(LAYOUT_PIECES) do rawset(frame, piece, rawget(frame, piece) or frame:CreateTexture()) end
			frame._layout = name
		end,
	}
	PANEL_BACKGROUND_COLOR = { GetRGB = function() return 0.08, 0.08, 0.08 end }
end

--[[ C_EncodingUtil, for the share code: Base64 as the client writes it, and a zlib
	stream made of stored (uncompressed) deflate blocks -- real zlib that any inflater
	reads, without writing a compressor in Lua. Clients without it get the plain text. ]]
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local digits = { math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64 }
		for k = 1, 4 do digits[k] = B64:sub(digits[k] + 1, digits[k] + 1) end
		if not b then digits[3] = "=" end
		if not c then digits[4] = "=" end
		out[#out + 1] = table.concat(digits)
	end
	return table.concat(out)
end

local function Zlib(s)
	local out = { string.char(0x78, 0x01) }
	local pos = 1
	repeat
		local chunk = s:sub(pos, pos + 65534)
		pos = pos + #chunk
		local len, nlen = #chunk, 65535 - #chunk
		out[#out + 1] = string.char(pos > #s and 1 or 0, len % 256, math.floor(len / 256), nlen % 256,
			math.floor(nlen / 256)) .. chunk
	until pos > #s
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	out[#out + 1] = string.char(math.floor(b / 256), b % 256, math.floor(a / 256), a % 256)
	return table.concat(out)
end

function Mock.InstallEncoding()
	Enum = Enum or {}
	Enum.CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 }
	C_EncodingUtil = {
		CompressString = function(source, method)
			assert(type(source) == "string", "CompressString needs a string")
			assert(method == Enum.CompressionMethod.Zlib, "the share code is zlib")
			return Zlib(source)
		end,
		EncodeBase64 = function(source)
			assert(type(source) == "string", "EncodeBase64 needs a string")
			return Base64(source)
		end,
	}
end

Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
	RegisterAddOnCategory = function(category) Mock.settingsCategory = category end,
}

------------------------------------------------------------------------------------------
-- The game, from Mock.state
------------------------------------------------------------------------------------------

Mock.state = {
	level = 5, xp = 100, xpMax = 2800, money = 1000, race = "Human", class = "WARRIOR", faction = "Alliance",
	mapID = 1429, x = 0.4, y = 0.6, zone = "Elwynn Forest", subzone = "Goldshire",
	npc = nil,              -- { guid =, name = }
	frame = nil,            -- the open quest frame: { questID, title, text, objective, progress, reward, xp, money, choices, rewards }
	log = {},               -- { { questID, title, level, objectives = { { text, type, numFulfilled, numRequired } } } }
	completed = {},
	factions = {},          -- { { factionID, name, currentStanding, reaction, currentReactionThreshold, nextReactionThreshold } }
	poi = {},               -- [mapID] = { { questID, x, y } }
	available = {},         -- [mapID] = { { questID, questName, questLineName, x, y } }
}
local S = function() return Mock.state end

function UnitRace() return S().race, S().race, 1 end
function UnitClass() return "Warrior", S().class, 1 end
function UnitFactionGroup() return S().faction, S().faction end
function UnitName(unit)
	if unit == "npc" then return S().npc and S().npc.name end
	return "Tester"
end
function GetRealmName() return "Forever-Test" end
function UnitLevel() return S().level end
function UnitXP() return S().xp end
function UnitXPMax() return S().xpMax end
function GetXPExhaustion() return nil end
function UnitGUID(unit)
	if unit == "npc" then return S().npc and S().npc.guid end
	return "Player-1-0000001"
end
function UnitExists(unit) if unit == "npc" then return S().npc ~= nil end return true end
function GetRealZoneText() return S().zone end
function GetSubZoneText() return S().subzone end
function GetMoney() return S().money end
function IsInGroup() return false end
function IsInRaid() return false end
function IsInGuild() return false end

local Vector = {}
Vector.__index = Vector
function Vector:GetXY() return self.x, self.y end
C_Map = {
	GetBestMapForUnit = function() return S().mapID end,
	GetPlayerMapPosition = function() if S().x then return setmetatable({ x = S().x, y = S().y }, Vector) end end,
	GetMapInfo = function(mapID) return { name = "Map " .. mapID } end,
	CanSetUserWaypointOnMap = function() return true end,
	SetUserWaypoint = function(point) Mock.waypoint = point end,
}
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) Mock.superTracked = on end }

local function Frame() return S().frame or {} end
function GetQuestID() return Frame().questID or 0 end
function GetTitleText() return Frame().title end
function GetQuestText() return Frame().text end
function GetObjectiveText() return Frame().objective end
function GetProgressText() return Frame().progress end
function GetRewardText() return Frame().reward end
function GetRewardXP() return Frame().xp or 0 end
function GetRewardMoney() return Frame().money or 0 end
function GetRewardTitle() return nil end
function GetRewardSkillPoints() return nil end
function GetRewardHonor() return 0 end
function GetNumQuestChoices() return #(Frame().choices or {}) end
function GetNumQuestRewards() return #(Frame().rewards or {}) end
function GetQuestItemLink(kind, index)
	local list = kind == "choice" and Frame().choices or Frame().rewards
	local item = list and list[index]
	return item and ("|cffffffff|Hitem:" .. item.id .. "::::::::5:::::|h[" .. item.name .. "]|h|r")
end
function GetQuestItemInfo(kind, index)
	local list = kind == "choice" and Frame().choices or Frame().rewards
	local item = list and list[index]
	if item then return item.name, 1, item.count or 1, 2, true, item.id end
end
function GetQuestMoneyToGet() return 0 end
function IsQuestCompletable() return true end
function GetQuestReward(choice) Mock.rewardTaken = choice end
function AcceptQuest() Mock.accepted = true end
function CompleteQuest() Mock.completedQuest = true end
function QuestGetAutoAccept() return false end
function GetNumActiveQuests() return 0 end
function GetNumAvailableQuests() return 0 end

local function LogEntry(questID)
	for index, entry in ipairs(S().log) do
		if entry.questID == questID then return entry, index end
	end
end
C_QuestLog = {
	GetNumQuestLogEntries = function() return #S().log, #S().log end,
	GetMaxNumQuestsCanAccept = function() return 25 end,
	GetInfo = function(index)
		local entry = S().log[index]
		if entry then return { questID = entry.questID, title = entry.title, level = entry.level, isHeader = false,
			suggestedGroup = 0, frequency = 0 } end
	end,
	GetLogIndexForQuestID = function(questID) local _, index = LogEntry(questID) return index end,
	GetQuestDifficultyLevel = function(questID) local e = LogEntry(questID) return e and e.level end,
	GetQuestTagInfo = function() return nil end,
	GetRequiredMoney = function() return 0 end,
	GetQuestObjectives = function(questID)
		local e = LogEntry(questID)
		if not e then return {} end
		local out = {}
		for i, o in ipairs(e.objectives or {}) do
			out[i] = { text = string.format("%s: %d/%d", o.text, o.numFulfilled, o.numRequired), type = o.type or "monster",
				finished = o.numFulfilled >= o.numRequired, numFulfilled = o.numFulfilled, numRequired = o.numRequired }
		end
		return out
	end,
	GetTitleForQuestID = function(questID) local e = LogEntry(questID) return e and e.title end,
	IsOnQuest = function(questID) return LogEntry(questID) ~= nil end,
	IsQuestFlaggedCompleted = function(questID) return S().completed[questID] == true end,
	ReadyForTurnIn = function(questID)
		local e = LogEntry(questID)
		if not e then return false end
		for _, o in ipairs(e.objectives or {}) do if o.numFulfilled < o.numRequired then return false end end
		return true
	end,
	IsComplete = function(questID) return C_QuestLog.ReadyForTurnIn(questID) end,
	IsQuestTrivial = function() return false end,
	GetQuestsOnMap = function(mapID) return S().poi[mapID] or {} end,
}
C_QuestLine = {
	RequestQuestLinesForMap = function(mapID) Mock.requestedLines = mapID end,
	GetAvailableQuestLines = function(mapID) return S().available[mapID] or {} end,
}
C_QuestInfoSystem = {
	GetQuestRewardSpells = function() return {} end,
	GetQuestRewardCurrencies = function() return {} end,
}
C_Reputation = {
	GetNumFactions = function() return #S().factions end,
	GetFactionDataByIndex = function(index) return S().factions[index] end,
	GetFactionDataByID = function(factionID)
		for _, f in ipairs(S().factions) do if f.factionID == factionID then return f end end
	end,
}
C_Item = { GetItemNameByID = function(itemID) return "Item " .. itemID end }
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
	GetContainerItemInfo = function(bag, slot)
		if bag == 0 and slot == 1 then return { quality = 0, hasNoValue = false, isLocked = false, itemID = 1 } end
	end,
	UseContainerItem = function(bag, slot) table.insert(Mock.sold, { bag, slot }) end,
}
Mock.sold = {}
C_GossipInfo = { GetActiveQuests = function() return {} end, GetAvailableQuests = function() return {} end }
-- Chat goes out only from a click: anything else is what the client reports as
-- "ADDON BLOCKED". Mock.Click is the click (the hardware event).
Mock.blocked = {}
C_ChatInfo = {
	SendChatMessage = function(message, channel)
		if not Mock.hardware then
			table.insert(Mock.blocked, { message, channel })
			return
		end
		table.insert(Mock.sent, { message, channel })
	end,
	InChatMessagingLockdown = function() return Mock.chatLockdown == true end,
}
-- Blizzard's own "Sell All Junk" (Mainline MerchantFrame).
C_MerchantFrame = {
	GetNumJunkItems = function() return #Mock.Junk() end,
	IsSellAllJunkEnabled = function() return Mock.sellAllJunk ~= false end,
	SellAllJunkItems = function()
		for _, item in ipairs(Mock.Junk()) do table.insert(Mock.sold, item) end
	end,
}
function Mock.Junk()
	local out = {}
	for slot = 1, C_Container.GetContainerNumSlots(0) do
		local info = C_Container.GetContainerItemInfo(0, slot)
		if info and info.quality == 0 and not Mock.soldSlot(0, slot) then out[#out + 1] = { 0, slot } end
	end
	return out
end
function Mock.soldSlot(bag, slot)
	for _, item in ipairs(Mock.sold) do if item[1] == bag and item[2] == slot then return true end end
	return false
end
C_CurrencyInfo = { GetCoinTextureString = function(copper) return tostring(copper) .. "c" end }
function CanMerchantRepair() return true end
function GetRepairAllCost() return 250, true end
function RepairAllItems(guild) Mock.repaired = guild and "guild" or "own" end
function CanGuildBankRepair() return false end

------------------------------------------------------------------------------------------
-- Driving it
------------------------------------------------------------------------------------------

--- Fire an event at every frame registered for it.
function Mock.Fire(event, ...)
	local list = {}
	for frame in pairs(Mock.events[event] or {}) do list[#list + 1] = frame end
	for _, frame in ipairs(list) do frame:_Run("OnEvent", event, ...) end
end

function Mock.Click(frame, button)
	assert(frame, "nothing to click")
	Mock.hardware = true
	local ok, err = pcall(frame._Run, frame, "OnClick", button or "LeftButton")
	Mock.hardware = false
	if not ok then error(err, 0) end
end

--- Every frame whose text is `text`, or a button whose label is.
function Mock.FindText(text, root)
	local found = {}
	local function Walk(region)
		local own = rawget(region, "_text")
		if own == text then found[#found + 1] = region end
		local fs = rawget(region, "_fs")
		if fs and rawget(fs, "_text") == text then found[#found + 1] = region end
		for _, child in ipairs(rawget(region, "_children") or {}) do Walk(child) end
		for key, value in pairs(region) do
			if type(value) == "table" and rawget(value, "_type") == "FontString" and value ~= fs then
				if rawget(value, "_text") == text then found[#found + 1] = region end
			end
		end
	end
	Walk(root or UIParent)
	return found
end
