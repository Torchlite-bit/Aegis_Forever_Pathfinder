--[[
	The smoke test's scenario (Tools/smoke_test.py runs it once per skin): log in,
	start collecting, play a quest from offer to turn-in, level up, pack it to
	submit, and click through every window and setting.
]]

local AP, skin = ...
local Mock = WOWMOCK
local S = Mock.state
local checks = 0

local function check(condition, message)
	checks = checks + 1
	if not condition then error("check failed: " .. tostring(message), 2) end
end

local function equal(actual, expected, message)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("check failed: %s (expected %s, got %s)", message, tostring(expected), tostring(actual)), 2)
	end
end

local function Chat(pattern)
	for _, line in ipairs(Mock.chat) do
		if line:find(pattern) then return true end
	end
	return false
end

------------------------------------------------------------------------------------------
-- Logging in
------------------------------------------------------------------------------------------

Mock.Fire("ADDON_LOADED", "Aegis_Forever_Pathfinder")
Mock.Fire("PLAYER_LOGIN")
Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
Mock.Advance(1)

equal(AP.Theme:IsBlizzard(), skin == "blizzard", "the skin follows the saved theme")
-- The Blizzard run is a new install (nothing saved); the Pathfinder run an earlier one.
equal(AP.db.profile.theme, skin == "blizzard" and "blizzard" or "pathfinder",
	"a new install starts in Default, and an earlier one keeps the theme it saved")
check(Chat("loaded"), "the load line is said")
local guide = AP.objectiveframe
check(guide and guide:IsShown(), "the guide window opens at login")
check(guide.ui.empty:IsShown(), "with no guides, the guide window shows its empty state")
equal(guide.ui.empty.start:GetText(), skin == "blizzard" and "Start collecting data" or "START COLLECTING DATA",
	"the empty state offers to start collecting")
check(not AP.Collector:IsRunning(), "the collector is off until started")
check(AP.minimapbutton:IsShown(), "the minimap button shows")
check(Mock.settingsCategory, "a page is registered in the game's own options")
if skin == "blizzard" then
	local modern = C_Texture ~= nil
	if modern then
		equal(rawget(guide, "_layout"), "ButtonFrameTemplateNoPortrait", "the Blizzard skin draws the metal window border")
		equal(rawget(AP.guidebrowserframe, "_layout"), "ButtonFrameTemplateNoPortrait", "on every window")
	else
		check(guide:GetBackdrop() and guide:GetBackdrop().edgeFile:find("DialogBox"), "without the metal art, a dialog edge")
	end
	local fill = guide.skin.fill.texture
	check(fill and rawget(fill, "_color") and fill._color[4] == 1, "and a solid, not see-through, background")
	check(guide.header.title and guide.header.title:GetText() == "Aegis: Pathfinder", "the title sits in the top bar")
end

------------------------------------------------------------------------------------------
-- Starting the collector from the guide window
------------------------------------------------------------------------------------------

Mock.Click(guide.ui.empty.start)
check(AP.Collector:IsRunning(), "Start collecting data starts it")
check(guide.ui.collectChip:IsActive(), "the guide's collection chip lights")
equal(AP.db.char.collecting, true, "running is saved for the next login")
local data = AP.Collector:GetData()
equal(data.levels[5].xpMax.last, 2800, "the XP the level needs is noted on start")
check(data.builds["1.60.1.70338"], "the client build is stamped")
check(data.observers["Human:WARRIOR:Alliance"], "the observer is race, class and faction")

-- The collection window and its checkbox.
AP:ToggleCollectorFrame()
local collector = AP.collectorframe
check(collector:IsShown(), "the collection window opens")
check(not AP.Collector:IsAuto(), "Automatically run is off to start with")
Mock.Click(collector.ui.auto)
check(AP.Collector:IsAuto(), "Automatically run ticks")
equal(AP.db.char.collectauto, true, "Automatically run is saved per character")
equal(AP.db.profile.collectautodefault, true, "and becomes the default for new characters")

------------------------------------------------------------------------------------------
-- A quest, from offer to turn-in
------------------------------------------------------------------------------------------

S.reputationGainPending = nil
S.factions = { { factionID = 72, name = "Stormwind", currentStanding = 3000, reaction = 5,
	currentReactionThreshold = 3000, nextReactionThreshold = 9000, isHeader = false } }
AP.Collector:ReadReputations()

-- Offered by Marshal Dughan in Goldshire.
S.npc = { guid = "Creature-0-1-0-1-240-0000000001", name = "Marshal Dughan" }
S.mapID, S.x, S.y = 1429, 0.4215, 0.6590
S.frame = { questID = 176, title = "Wanted: Hogger", text = "A huge gnoll, Tester.", objective = "Kill Hogger.",
	xp = 1450, money = 500, choices = { { id = 2224, name = "Militia Dagger" }, { id = 2225, name = "Sharp Kitchen Knife" } } }
Mock.Fire("QUEST_DETAIL", 0)
local quest = data.quests[176]
check(quest, "the offered quest is written down")
equal(quest.title, "Wanted: Hogger", "its title")
equal(quest.objectiveText, "Kill Hogger.", "its objective text")
-- The game writes the player's name into quest text: it stays at home.
equal(quest.description, "A huge gnoll, <name>.", "the player's name is left out of its text")
local Unnamed = AP.Collector.Unnamed
equal(Unnamed("You there! Tester, right?"), "You there! <name>, right?", "a name before a comma")
equal(Unnamed("Tester"), "<name>", "a name alone")
equal(Unnamed("Testers and retesters"), "Testers and retesters", "not inside a longer word")
equal(Unnamed("Hi Zoë!", "Zoë"), "Hi <name>!", "a name with an accent")
equal(Unnamed("Zoëlle", "Zoë"), "Zoëlle", "and not inside a longer one")
equal(Unnamed("50% of (Tester)", "Tester"), "50% of (<name>)", "pattern characters around it are fine")
-- Text saved before 0.2.4 is cleaned once the game knows who is playing.
quest.completionText = "Well done, Tester."
Mock.Fire("PLAYER_ENTERING_WORLD")
equal(quest.completionText, "Well done, <name>.", "saved text loses the name at login")
equal(quest.rewards.xpOffered[5], 1450, "the XP the frame offers, at the player's level")
check(quest.rewards.choices[2224] and quest.rewards.choices[2225], "the rewards to choose from")

-- Accepted: the pickup is the NPC, where the player stood.
S.log = { { questID = 176, title = "Wanted: Hogger", level = 11,
	objectives = { { text = "Hogger slain", numFulfilled = 0, numRequired = 1 } } } }
Mock.Fire("QUEST_ACCEPTED", 176)
local pickup = quest.pickups["npc:240@1429"]
check(pickup, "the pickup is keyed by the NPC and the map")
equal(pickup.name, "Marshal Dughan", "the giver's name")
equal(pickup.x, 0.4215, "the giver's x")
equal(pickup.playerLevel.min, 5, "the player's level at pickup")
equal(quest.level, 11, "the quest's level, from the log")
equal(quest.objectives[1].text, "Hogger slain", "the objective's text, without its count")
equal(quest.objectives[1].required, 1, "how many it wants")

-- Hogger dies at the Elwynn camp: the objective moves on there.
S.npc, S.frame = nil, nil
S.x, S.y = 0.2581, 0.7712
S.log[1].objectives[1].numFulfilled = 1
S.poi[1429] = { { questID = 176, x = 0.42, y = 0.66 } }
Mock.Fire("QUEST_LOG_UPDATE")
Mock.Fire("QUEST_LOG_UPDATE")
Mock.Advance(1)
check(quest.progress and quest.progress[1] and quest.progress[1]["1429:26:77"], "where the objective moved on")
check(quest.poi and quest.poi.turnin and quest.poi.turnin["1429:42:66"], "the client's own map point for the turn-in")

-- Handed in to the same NPC: the reward frame, the turn-in, the reputation line.
S.npc = { guid = "Creature-0-1-0-1-240-0000000001", name = "Marshal Dughan" }
S.x, S.y = 0.4221, 0.6588
S.frame = { questID = 176, title = "Wanted: Hogger", reward = "You did it!", xp = 1450, money = 500,
	choices = { { id = 2224, name = "Militia Dagger" }, { id = 2225, name = "Sharp Kitchen Knife" } } }
Mock.Fire("QUEST_COMPLETE")
GetQuestReward(2)
S.log, S.completed[176] = {}, true
Mock.Fire("QUEST_TURNED_IN", 176, 1450, 500)
S.factions[1].currentStanding = 3250
Mock.Fire("FACTION_STANDING_CHANGED", 72, 3250)
Mock.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 250.")
S.xp = 100 + 1450
Mock.Advance(1.5)
Mock.Fire("QUEST_REMOVED", 176, false)
Mock.Advance(2)

local turnin = quest.turnins["npc:240@1429"]
check(turnin, "the turn-in is keyed by the NPC and the map")
equal(turnin.xyCount, 1, "one turn-in seen")
equal(quest.rewards.xp[5].last, 1450, "the XP the turn-in gave at level 5")
equal(quest.rewards.money.last, 500, "the money it gave")
equal(quest.rewards.xpObserved[5].last, 1450, "the XP bar moved by as much")
equal(quest.rewards.reputation.Stormwind.last, 250, "the reputation it gave")
equal(quest.rewards.reputation.Stormwind.count, 1, "counted once, though the id event and the chat line both said it")
equal(quest.rewards.reputation.Stormwind.factionID, 72, "with the faction's id")
equal(quest.rewards.chosen.WARRIOR[2225], 1, "the reward a warrior chose")
equal(quest.seen.turnedIn, 1, "turned in once")
check(not quest.seen.abandoned, "a quest removed by its turn-in is not abandoned")
equal(quest.completionText, "You did it!", "the completion text")

-- The next in the chain, offered by the same NPC straight after.
S.frame = { questID = 177, title = "Hogger's Revenge", text = "...", objective = "..." }
Mock.Fire("QUEST_DETAIL", 0)
check(quest.chain and quest.chain.next[177], "the chain: 176 leads to 177")
check(data.quests[177].chain.prev[176], "and 177 follows 176")

-- A quest started from an item.
S.npc = nil
S.frame = { questID = 300, title = "A Note", text = "...", objective = "..." }
Mock.Fire("QUEST_DETAIL", 1972)
S.log = { { questID = 300, title = "A Note", level = 5, objectives = {} } }
Mock.Fire("QUEST_ACCEPTED", 300)
check(data.quests[300].pickups["item:1972@1429"], "an item-started quest's pickup is the item")
S.log = {}

-- A quest a party member shares: the frame's "npc" is that player, whose name stays out.
S.npc = { guid = "Player-1-00000002", name = "Partymate" }
S.frame = { questID = 301, title = "Shared", text = "...", objective = "..." }
Mock.Fire("QUEST_DETAIL", 0)
S.log = { { questID = 301, title = "Shared", level = 5, objectives = {} } }
Mock.Fire("QUEST_ACCEPTED", 301)
local shared = data.quests[301].pickups["shared:?@1429"]
check(shared and shared.kind == "shared" and shared.name == nil, "a shared quest's pickup is \"shared\", without the sharer's name")
for key in pairs(data.quests[301].pickups) do check(not key:find("Partymate"), "the sharer's name is in no key either") end
S.log, S.npc = {}, nil
data.quests[301] = nil -- out again, so the counts below stay the walk-through's

-- A second sighting of the same turn-in merges, never overwrites.
S.frame = { questID = 176, title = "Wanted: Hogger" }
S.npc = { guid = "Creature-0-1-0-1-240-0000000001", name = "Marshal Dughan" }
S.x, S.y = 0.4231, 0.6600
S.level, S.xp, S.xpMax = 6, 0, 4500
Mock.Fire("QUEST_COMPLETE")
Mock.Fire("QUEST_TURNED_IN", 176, 1100, 500)
Mock.Advance(2)
equal(turnin.count, 2, "two turn-ins at the same NPC merge")
equal(turnin.xMin, 0.4221, "the lowest x is kept")
equal(turnin.xMax, 0.4231, "the highest x is kept")
equal(quest.rewards.xp[6].last, 1100, "the XP at the next level is kept beside the first")
equal(quest.rewards.xp[5].last, 1450, "and the first is still there")
equal(quest.rewards.money.count, 2, "money seen twice")
S.level, S.xp, S.xpMax = 5, 1550, 2800

-- Quests the map marks as available.
S.available[1429] = { { questID = 999, questName = "Lost in the Woods", questLineName = "Elwynn", x = 0.5, y = 0.5 } }
Mock.Fire("QUESTLINE_UPDATE")
check(data.quests[999].poi.available["1429:50:50"], "the client's available-quest pin")

------------------------------------------------------------------------------------------
-- Levels
------------------------------------------------------------------------------------------

AP.db.char.levelclock = { level = 5, seconds = 0, whole = true }
Mock.Advance(600)
Mock.Fire("PLAYER_LEVEL_UP", 6, 10, 0, 0, 0)
S.level, S.xp, S.xpMax = 6, 0, 4500
Mock.Advance(1.5)
equal(data.levels[6].xpMax.last, 4500, "the XP level 6 needs")
check(data.levels[5].seconds and data.levels[5].seconds.last >= 600, "how long level 5 took, seen from its start")
-- The game lets an addon post in chat only from a click: a card offers it instead.
equal(#Mock.sent, 0, "nothing goes to chat by itself")
equal(#Mock.blocked, 0, "and nothing is tried without a click")
local levelCard = _G.AegisPathfinderLevelUp
check(levelCard and levelCard:IsShown(), "a level-up shows the card")
check(levelCard.title:GetText():find("Level 6", 1, true), "naming the level")
Mock.chatLockdown = true
Mock.Click(levelCard.buttons[1])
equal(#Mock.sent, 0, "chat lockdown: the click sends nothing")
Mock.chatLockdown = nil
Mock.Click(levelCard.buttons[1])
check(Mock.sent[1] and Mock.sent[1][1]:find("leveled up from 5 to 6") and Mock.sent[1][2] == "EMOTE",
	"a click sends the emote")
check(not levelCard:IsShown(), "and the card goes once all it offers is sent")

------------------------------------------------------------------------------------------
-- The windows show it
------------------------------------------------------------------------------------------

AP:RefreshCollectorFrame()
equal(collector.ui.quests:GetText(), 4, "the collection window counts the quests")
check(collector.ui.lines[1]:GetText() ~= "", "and lists what it wrote down")
AP:RefreshObjectivePanel()
check(guide.ui.empty.status:GetText():find("4 quests, 1 turned in, 2 levels", 1, true), "the guide's empty state counts them too")
check(guide.ui.empty.auto:IsOn(), "the guide's Automatically run box shows the setting")
Mock.Click(guide.ui.empty.auto)
check(not AP.Collector:IsAuto(), "and changes it from the guide window")
Mock.Click(guide.ui.empty.auto)
check(AP.Collector:IsAuto(), "both ways")

-- Submit: the share code and the plain export, handed back to Python to decode.
local L = AP.L
AP:ShowSubmit()
local submit = _G.AegisPathfinderSubmit
check(submit:IsShown(), "the Submit window opens")
check(submit.box:HasFocus(), "with the code in the box, ready for Ctrl+C")
if C_EncodingUtil then
	check(submit.text:find("^APF1:"), "it shows the share code")
	equal(submit.codeHead.label:GetText(), skin == "blizzard" and L.SUBMIT_CODE or L.SUBMIT_CODE:upper(),
		"under its name, cased like the skin's other headings")
	check(submit.as:IsShown(), "As text is offered")
	Mock.Click(submit.as)
	check(submit.text:find("^AEGIS PATHFINDER FOREVER DATA;2;"), "As text shows the plain export")
	equal(submit.as:GetText():lower(), L.SUBMIT_AS_CODE:lower(), "and offers the code back")
	Mock.Click(submit.as)
	check(submit.text:find("^APF1:"), "As code turns it back")
else
	check(submit.text:find("^AEGIS PATHFINDER FOREVER DATA;2;"), "a client without C_EncodingUtil gets the text")
	check(not submit.as:IsShown(), "and no As code button")
end
check(not submit.status:GetText():find("since your last send"), "a first send has nothing to compare with")
equal(submit.github:GetText(), AP.Export.GITHUB_URL, "the GitHub form link is there to copy")
equal(submit.discord:GetText(), AP.Export.DISCORD_URL, "and the Discord's")

-- The credit name: the character's by default, else what was typed, cleaned.
equal(AP.Export.Envelope().contributor, "Tester", "no name chosen: the character's")
check(AP.Export.Build():find(";Tester\n", 1, true), "in the header too")
submit.credit:SetText("  Bran|cffff0000dy; the\nGreat  ")
submit.credit:_Run("OnTextChanged", true)
equal(AP.db.profile.creditName, "Brancffff0000dy the Great", "the name loses UI codes, separators and line breaks")
submit.credit:SetText(string.rep("ä", 45))
submit.credit:_Run("OnTextChanged", true)
equal(AP.db.profile.creditName, string.rep("ä", 40), "and is cut at 40 letters, not inside one")
submit.credit:SetText("")
submit.credit:_Run("OnTextChanged", true)
equal(AP.db.profile.creditName, nil, "an empty box goes back to the character's name")
submit.credit:SetText("Brandy")
submit.credit:_Run("OnTextChanged", true)
Mock.Advance(1)
equal(AP.Export.Envelope().contributor, "Brandy", "the chosen name goes out")
-- With another credit name, the character's name still never goes out in quest text.
data.quests[176].progressText = "Back already, Tester?"
check(not AP.Export.Build():find("%f[%a]Tester%f[%A]"), "the character's name is nowhere in what goes out")
equal(data.quests[176].progressText, "Back already, <name>?", "and it's gone from the saved text too")
check(C_EncodingUtil == nil or submit.text:find("^APF1:"), "the code is made again with it")

-- New since your last send.
submit:Hide()
AP:ShowSubmit()
check(submit.status:GetText():find(string.format(L.SUBMIT_NEW, 0), 1, true), "nothing new since the last send")
submit:Hide()

-- What Python decodes.
local envelope = AP.Export.Envelope()
Mock.export = AP.Export.Build(envelope)
Mock.shareCode = AP.Export.ShareCode(envelope)
check(Mock.export:find('"Wanted: Hogger"', 1, true), "the export holds the quest")

-- Tables with gaps stay whole: an array only when the keys are exactly 1..n.
local ToJSON = AP.Export.ToJSON
equal(ToJSON({ "a", "b", "c" }), '["a","b","c"]', "a list is a JSON array")
equal(ToJSON({ [2] = "b", [4] = "d" }), '{"2":"b","4":"d"}', "levels 2 and 4 are kept, not an empty array")
equal(ToJSON({ [1] = "a", [3] = "c", [5] = "e" }), '{"1":"a","3":"c","5":"e"}', "nothing after a gap is lost")
equal(ToJSON({ [1] = 1.5, [2] = -0.25 }), "[1.5,-0.25]", "fractions are written plainly")
-- A layout where Lua 5.1's #t reports 4 for keys 1, 3, 4 and 6: the old check took it
-- for an array and ipairs kept only the first value.
local gappy = { "a", nil, "c", "d" }
gappy[6] = "f"
equal(ToJSON(gappy), '{"1":"a","3":"c","4":"d","6":"f"}', "a gap that fools #t loses nothing")

-- The contributors: none yet, or as many as fit and "and N more".
local listed = AP.CONTRIBUTORS
AP.CONTRIBUTORS = {}
equal(AP:ContributorsText(40), L.CONTRIBUTORS_NONE, "no contributors yet")
AP.CONTRIBUTORS = { "Subtilizer", "Brandy", "|cffff0000Ash|r", "Mira", "Tobias", "Quill" }
equal(AP:ContributorsText(20), "Subtilizer, Brandy, " .. string.format(L.CONTRIBUTORS_MORE, 4), "a long list ends in and N more")
check(AP:ContributorsText():find("Ash, Mira", 1, true), "every name, without UI codes, on the About page")
AP.CONTRIBUTORS = listed

------------------------------------------------------------------------------------------
-- The guide browser, the options and the commands
------------------------------------------------------------------------------------------

AP:ShowGuideBrowser()
local browser = AP.guidebrowserframe
check(browser:IsShown(), "the guide browser opens")
check(browser.ui.home:IsShown(), "on Home")
check(browser.ui.levelCard.lines[1].left:GetText():find("Level 5"), "Home lists the XP each level needs")
for _, row in ipairs(browser.ui.categories) do
	Mock.Click(row)
	check(browser.ui.empty:IsShown(), "an empty category says there are no guides yet")
end
Mock.Click(browser.ui.tabs[1])

AP:ToggleConfigPanel()
local options = AP.optionsframe
check(options:IsShown(), "the options open")
for _, button in ipairs(options.navButtons) do
	Mock.Click(button)
	equal(options.page, button.pageName, "the options page " .. button.pageName)
end
AP:RefreshConfigPanel()

-- The theme's note is set after the page is laid out: it has room for the longest of them
-- (an empty note was given one line, and Default's three ran into Switches).
do
	local note = options.themeNote
	check(note and note.reserved, "the theme note keeps its room")
	for _, def in ipairs(AP.Theme.THEMES) do
		note:SetText(def.note or "")
		check(note:GetStringHeight() <= note.reserved, "the note for " .. def.label .. " fits its room")
	end
	AP:RefreshConfigPanel()
	equal(options.navTitle ~= nil, skin == "blizzard", "the Blizzard skin names the list, with no header strip")
end
equal(AP.Theme.themeByKey.blizzard.label, "Default", "Blizzard's look is called Default")
equal(AP.Theme.themeByKey.capybara.label, "Pathfinder Tan", "and the colour themes are Pathfinder's")
-- Only the game's own code can reload: every Reload asks through one dialog whose Reload
-- button is a secure /reload button itself, not one laid over another button.
local function dialog() return AP.Theme:ReloadDialog() end
if skin == "pathfinder" then
	AP:SetTheme("night")
	equal(AP.Theme.current, "night", "a colour theme applies at once")
	check(not (dialog() and dialog():IsShown()), "without a reload")
	AP:SetTheme("blizzard")
	check(dialog() and dialog():IsShown(), "Default asks for a reload")
	equal(dialog().text:GetText(), AP.L.RELOAD_FOR_SKIN, "saying why, the first time too")
	local reload = dialog().reload
	check(rawget(reload, "_secure"), "its Reload button is the secure button itself")
	equal(reload:GetAttribute("type"), "macro", "a macro button")
	equal(reload:GetAttribute("macrotext"), "/reload", "running /reload")
	equal(reload:GetParent(), dialog(), "inside the dialog, so nothing lies over it")
	check(reload:IsVisible(), "and shown")
	check(not AP.Theme:IsWindow(dialog()), "the dialog isn't scaled or stacked with the Pathfinder windows")
	equal(reload:GetScript("OnClick"), Mock.SecureActionButton_OnClick, "keeping the secure template's own OnClick")
	equal(reload:GetAttribute("useOnKeyDown"), false, "acting on the mouse-up, whatever ActionButtonUseKeyDown says")
	Mock.ClickSecure(reload)
	check(Mock.reloaded, "and reloads when clicked")
	Mock.reloaded = nil
	check(reload:GetFrameLevel() and reload:GetFrameLevel() > dialog():GetFrameLevel()
		and dialog():GetFrameLevel() >= 500, "above the window stack, the guide menu and the drop-down lists")
	-- If the game didn't reload, the click says so a moment later.
	local mark = #Mock.chat
	Mock.ClickSecure(reload)
	Mock.reloaded = nil
	Mock.Advance(1.5)
	check(Mock.chat[mark + 1] and Mock.chat[mark + 1]:find("didn't reload"), "a Reload that didn't reload says so")
	-- Back to a theme of the running skin: the reload asked for Default isn't needed.
	AP:SetTheme("night")
	check(not dialog():IsShown(), "picking a Pathfinder theme again withdraws the request")
	AP:SetTheme("blizzard")
	Mock.Fire("PLAYER_REGEN_DISABLED")
	Mock.inCombat = true
	AP:SetTheme("night")
	Mock.inCombat = false
	Mock.Fire("PLAYER_REGEN_ENABLED")
	check(not dialog():IsShown(), "in combat too: it doesn't come back after the fight")
	-- The Clear-data question opens in the same place: the newest question wins.
	AP:SetTheme("blizzard")
	AP:ConfirmClearData()
	check(_G.AegisPathfinderConfirm:IsShown() and not dialog():IsShown(), "Clear data closes the Reload question")
	AP:SetTheme("blizzard")
	check(dialog():IsShown() and not _G.AegisPathfinderConfirm:IsShown(), "and a Reload question closes Clear data")
	AP:SetTheme("night")
	-- A frame holding a secure button can't be shown or hidden in combat: it steps aside
	-- before the fight and comes back after.
	AP:SetTheme("blizzard")
	Mock.Fire("PLAYER_REGEN_DISABLED")
	check(not dialog():IsShown(), "it steps aside as combat starts")
	Mock.inCombat = true
	AP.Theme:SetWindowScale(1.1)
	AP.Theme:SetWindowScale(1)
	AP:SetTheme("blizzard")
	check(not dialog():IsShown(), "and isn't shown in combat")
	check(Chat("Type /reload to reload"), "asked in combat, it says to type /reload")
	Mock.inCombat = false
	Mock.Fire("PLAYER_REGEN_ENABLED")
	check(dialog():IsShown(), "and asks again after the fight")
	Mock.Click(dialog().later)
	check(not dialog():IsShown(), "Later closes it")
	Mock.Fire("PLAYER_REGEN_DISABLED")
	Mock.Fire("PLAYER_REGEN_ENABLED")
	check(not dialog():IsShown(), "and it stays closed after the next fight")
	-- The guide menu's Reload and the Submit window's Save it now ask the same way.
	local menuReload
	for _, row in ipairs({ guide.ui.menu:GetChildren() }) do
		if row.item and row.item.label == "Reload" then menuReload = row end
	end
	check(menuReload, "the guide menu has Reload")
	-- Text set before our fonts load can stay blank: it's drawn again after login and as the menu opens.
	Mock.Fire("PLAYER_ENTERING_WORLD")
	Mock.Advance(9)
	guide.ui.menu:Show()
	equal(menuReload.label:GetText(), "Reload", "the menu's labels keep their text when drawn again")
	check(menuReload.label:GetFont(), "and their font")
	guide.ui.menu:Hide()
	-- /apg mouse says what has the mouse, for a button that doesn't take a click.
	SlashCmdList.AEGISPATHFINDER("mouse")
	check(Chat("Rest the mouse"), "/apg mouse explains itself")
	Mock.Advance(3.5)
	check(Chat("has the mouse there") or Chat("level"), "and then says what has the mouse")
	guide.ui.menu:Show()
	Mock.Click(menuReload)
	check(dialog():IsShown() and not guide.ui.menu:IsShown(), "the menu's Reload asks through the dialog")
	equal(dialog().text:GetText(), AP.L.RELOAD_NOW, "Reload the interface now?")
	Mock.Click(dialog().later)
	AP:ShowSubmit()
	local save = Mock.FindText(AP.L.SUBMIT_SAVE, _G.AegisPathfinderSubmit)[1]
		or Mock.FindText(AP.L.SUBMIT_SAVE:upper(), _G.AegisPathfinderSubmit)[1]
	check(save, "the Submit window has Save it now")
	Mock.Click(save)
	check(dialog():IsShown(), "Save it now asks through the dialog")
	equal(dialog().text:GetText(), AP.L.SUBMIT_SAVE_RELOAD, "saying why")
	Mock.Click(dialog().later)
	check(not Mock.IsProtected(_G.AegisPathfinderSubmit) and not Mock.IsProtected(guide.ui.menu),
		"no Pathfinder window holds a secure button")
	_G.AegisPathfinderSubmit:Hide()
	AP:SetTheme("pathfinder")
	Mock.Click(dialog().later)
else
	AP:SetTheme("pathfinder")
	check(dialog() and dialog():IsShown(), "leaving Default asks for a reload")
	equal(dialog().text:GetText(), AP.L.RELOAD_FOR_SKIN, "saying why, the first time too")
	check(rawget(dialog().reload, "_secure"), "with the secure Reload in this skin too")
	equal(dialog().reload:GetScript("OnClick"), Mock.SecureActionButton_OnClick, "keeping the secure OnClick here too")
	Mock.ClickSecure(dialog().reload)
	check(Mock.reloaded, "and it reloads")
	Mock.reloaded = nil
	Mock.Click(dialog().later)
	check(not dialog():IsShown() and not Mock.reloaded, "Later leaves it be")
end
equal(#Mock.popups, 0, "the game's own popups are never used")

-- Stacking keeps every frame above the one holding it: the Blizzard X (a level of its own)
-- once ended up level with its header, and the header took its clicks.
local function Below(f, parentLevel)
	for _, k in ipairs({ f:GetChildren() }) do
		if k:GetFrameLevel() <= parentLevel then return k end
		local bad = Below(k, k:GetFrameLevel())
		if bad then return bad end
	end
end
local wasShown = {}
for _, w in ipairs(AP.Theme.windows) do wasShown[w] = w:IsShown() end
for round = 1, 2 do
	for _, w in ipairs(AP.Theme.windows) do
		-- As a click raises a toplevel window in the client: the window alone, above its own children.
		if round == 2 then w:SetFrameLevel(5000) end
		w:Show()
		AP.Theme:BringToFront(w)
	end
end
for _, w in ipairs(AP.Theme.windows) do
	local bad = Below(w, w:GetFrameLevel())
	check(not bad, "every frame of " .. tostring(w:GetName()) .. " is above the frame holding it")
	if w.closeChip then
		check(w.closeChip:GetFrameLevel() > w.header:GetFrameLevel(), "its X is above its header")
	end
end
for _, w in ipairs(AP.Theme.windows) do w:SetShown(wasShown[w]) end

AP:SetGuideTransparent(true)
AP:SetGuideLocked(true)
check(guide.locked, "Lock window holds the guide")
AP:SetGuideLocked(false)
AP:SetGuideOpacity(0.4)
AP:SetStepTextSize(1.2)
AP:SetWindowScale(1.1)
AP:SetBrowserOpacity(0.8)
AP:SetSwitchColours("redgreen")
AP:ToggleOverviewMode()
AP:ToggleOverviewMode()
AP:ToggleMinimapButton()
check(not AP.minimapbutton:IsShown(), "/apg minimapbutton hides the button")
AP:ToggleMinimapButton()
AP:ResetWindowLayout()

for _, command in ipairs({ "", "", "collect", "submit", "export", "config", "browser", "status", "help", "next",
	"prev", "resetpanels", "unknown" }) do
	SlashCmdList.AEGISPATHFINDER(command)
end

------------------------------------------------------------------------------------------
-- Automation
------------------------------------------------------------------------------------------

check(AP.db.char.autoquest, "quests are accepted and turned in by default, as in the Turtle addon")
if skin == "pathfinder" then
	-- This run starts from a character 0.1.0 saved with automation off: it is turned on once.
	check(Chat("accepted and turned in by themselves"), "and an old character is told it was turned on")
end
S.frame = { questID = 500, title = "Auto", text = "", objective = "" }
Mock.Fire("QUEST_DETAIL", 0)
QuestFrame:Show()
Mock.Advance(0.5)
check(Mock.accepted, "an offered quest is accepted by itself")
S.frame = { questID = 500, title = "Auto", choices = { { id = 1, name = "A" }, { id = 2, name = "B" } } }
Mock.rewardTaken = nil
Mock.Fire("QUEST_COMPLETE")
Mock.Advance(0.5)
check(Mock.rewardTaken == nil, "never a reward choice")
S.frame = { questID = 501, title = "Auto 2" }
Mock.Fire("QUEST_COMPLETE")
Mock.Advance(0.5)
equal(Mock.rewardTaken, 0, "a quest without a choice is handed in")
AP.db.char.autoquest = false

AP.db.char.autosell, AP.db.char.autorepair = true, "own"
-- As Forever does it: MERCHANT_SHOW first, the merchant window a moment later (the player
-- interaction manager shows it on its own event). 0.3.1 asked the window and sold nothing.
Mock.Fire("MERCHANT_SHOW")
equal(Mock.repaired, "own", "gear is repaired as the vendor opens")
MerchantFrame:Show()
Mock.Advance(0.1)
equal(#Mock.sold, 1, "greys are sold, with the game's own Sell All Junk, though the window came after the event")
check(AP.Automation.button and not AP.Automation.button:IsShown(), "no Sell greys button beside the game's own")
-- Closed before the next frame: nothing is sold.
Mock.sold = {}
MerchantFrame:Hide()
Mock.Fire("MERCHANT_SHOW")
Mock.Fire("MERCHANT_CLOSED")
Mock.Advance(0.1)
equal(#Mock.sold, 0, "a vendor closed at once sells nothing")
-- A client without Sell All Junk: one item at a time, and the button.
local gameJunk = C_MerchantFrame
C_MerchantFrame, Mock.sold = nil, {}
MerchantFrame:Show()
Mock.Fire("MERCHANT_SHOW")
Mock.Advance(0.1)
equal(#Mock.sold, 1, "greys are sold one by one without it")
check(AP.Automation.button:IsShown(), "and the Sell greys button is there")
Mock.Fire("MERCHANT_CLOSED")
MerchantFrame:Hide()
C_MerchantFrame = gameJunk

------------------------------------------------------------------------------------------
-- A guide, through the registration API
------------------------------------------------------------------------------------------

local ok, why = AP:RegisterGuide({ name = "Test Guide (1-2)", category = "leveling", faction = "Alliance",
	minLevel = 1, maxLevel = 2, steps = {
		{ action = "ACCEPT", qid = 600, title = "First", map = 1429, x = 0.5, y = 0.5, note = "Here." },
		{ action = "COMPLETE", qid = 600, title = "First" },
		{ action = "TURNIN", qid = 600, title = "First" },
		{ action = "RUN", title = "Onwards", map = 1429, x = 0.3, y = 0.3 },
	} })
check(ok, "a guide registers: " .. tostring(why))
check(not AP:RegisterGuide({ name = "Bad", steps = { { action = "FLAP" } } }), "an unknown action is refused")
AP:LoadGuide("Test Guide (1-2)")
equal((AP:GetCurrentStep()), 1, "the guide starts at its first step")
check(Mock.waypoint and Mock.waypoint.x == 0.5, "the step's place goes on the map")
check(not guide.ui.empty:IsShown(), "the empty state gives way to the steps")
S.log = { { questID = 600, title = "First", level = 1, objectives = { { text = "Thing", numFulfilled = 0, numRequired = 1 } } } }
Mock.Fire("QUEST_ACCEPTED", 600)
equal((AP:GetCurrentStep()), 2, "accepting ticks the ACCEPT step")
S.log[1].objectives[1].numFulfilled = 1
Mock.Fire("QUEST_LOG_UPDATE")
Mock.Advance(1)
equal((AP:GetCurrentStep()), 3, "finishing the objectives ticks COMPLETE")
S.log = {}
Mock.Fire("QUEST_TURNED_IN", 600, 100, 0)
Mock.Advance(2)
equal((AP:GetCurrentStep()), 4, "handing in ticks TURNIN")
AP:ToggleOverviewMode()
AP:RefreshObjectivePanel()
AP:ToggleOverviewMode()
AP:UnloadGuide()
check(guide.ui.empty:IsShown(), "no guide, the empty state again")

------------------------------------------------------------------------------------------
-- Stopping, clearing
------------------------------------------------------------------------------------------

Mock.Click(collector.ui.toggle)
check(not AP.Collector:IsRunning(), "the window's switch stops it")
local before = data.quests[176].seen.offered
S.frame = { questID = 176, title = "Wanted: Hogger" }
Mock.Fire("QUEST_DETAIL", 0)
equal(data.quests[176].seen.offered, before, "nothing is written while stopped")

local exportText = Mock.export
local confirm = _G.AegisPathfinderConfirm
AP:ConfirmClearData()
confirm = confirm or _G.AegisPathfinderConfirm
check(confirm:IsShown(), "Clear data asks first")
Mock.Click(confirm.yes)
equal(next(AP.Collector:GetData().quests), nil, "Clear data forgets the quests")
Mock.export = exportText

equal(#Mock.blocked, 0, "nothing the client would block was tried")

-- Nothing of Blizzard's popup system was touched: writing into it taints Escape.
equal(next(StaticPopupDialogs), nil, "StaticPopupDialogs is left alone")
check(rawequal(StaticPopupDialogs, Mock.staticPopupDialogs), "and never reassigned")

return string.format("%d checks passed", checks)
