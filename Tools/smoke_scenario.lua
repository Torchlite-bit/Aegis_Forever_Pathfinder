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
check(guide.ui.empty:IsShown(), "with no guide open, the guide window shows its empty state")
equal(guide.ui.empty.title:GetText(), "PICK A GUIDE", "and, now there is a guide, says to pick one")
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

-- Two quests handed in to Marshal McBride less than a second apart, as quest automation
-- does it, each leaving the log as it goes. Up to 0.4.0 only the last turn-in was kept:
-- the first quest counted as abandoned, its XP went unchecked, and the next quest
-- McBride offered was linked to the second.
S.npc = { guid = "Creature-0-1-0-1-197-0000000002", name = "Marshal McBride" }
S.xp = 1000
S.frame = { questID = 21, title = "Skirmish at Echo Ridge", xp = 450 }
Mock.Fire("QUEST_COMPLETE")
Mock.Fire("QUEST_TURNED_IN", 21, 450, 0)
Mock.Fire("QUEST_REMOVED", 21, false)
S.xp = 1450
Mock.Advance(0.3)
S.frame = { questID = 91752, title = "The Big Picture", xp = 320 }
Mock.Fire("QUEST_COMPLETE")
Mock.Fire("QUEST_TURNED_IN", 91752, 320, 0)
Mock.Fire("QUEST_REMOVED", 91752, false)
S.xp = 1770
S.frame = { questID = 54, title = "Report to Goldshire" }
Mock.Fire("QUEST_DETAIL", 0)
Mock.Advance(2)
for _, id in ipairs({ 21, 91752 }) do
	equal(data.quests[id].seen.turnedIn, 1, id .. " is turned in")
	check(not data.quests[id].seen.abandoned, id .. ", handed in just before or after another, is not abandoned")
end
equal(data.quests[21].rewards.xpObserved[5].last, 450, "the first quest's XP is checked, up to the second's frame")
equal(data.quests[91752].rewards.xpObserved[5].last, 320, "and the second's on its own")
check(not data.quests[54].chain and not data.quests[21].chain and not data.quests[91752].chain,
	"a quest offered after two turn-ins to the NPC is linked to neither: it could follow either")
-- A quest leaving the log with no turn-in is still abandoned.
S.npc, S.frame = nil, nil
Mock.Fire("QUEST_REMOVED", 54, false)
Mock.Advance(2)
equal(data.quests[54].seen.abandoned, 1, "a quest dropped from the log is abandoned")
-- The first quest's XP not on the bar yet as the second's frame opens: it would show as
-- the second's, so neither is checked.
S.npc = { guid = "Creature-0-1-0-1-197-0000000002", name = "Marshal McBride" }
S.xp = 1000
S.frame = { questID = 21, title = "Skirmish at Echo Ridge", xp = 450 }
Mock.Fire("QUEST_COMPLETE")
Mock.Fire("QUEST_TURNED_IN", 21, 450, 0)
Mock.Advance(0.3)
S.frame = { questID = 91752, title = "The Big Picture", xp = 320 }
Mock.Fire("QUEST_COMPLETE")
Mock.Fire("QUEST_TURNED_IN", 91752, 320, 0)
S.xp = 1770
Mock.Advance(2)
equal(data.quests[21].rewards.xpObserved[5].count, 1, "a late XP bar checks neither quest: not the first")
equal(data.quests[91752].rewards.xpObserved[5].count, 1, "nor the second")
data.quests[21], data.quests[91752], data.quests[54] = nil, nil, nil -- out again, for the counts below
S.npc, S.frame, S.xp = nil, nil, 1550

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
if skin == "blizzard" then
	local _, _, _, _, titleY = levelCard.title:GetPoint(1)
	local _, noteTo, _, _, noteY = levelCard.note:GetPoint(1)
	check(titleY >= -5 and noteTo == levelCard and noteY <= -AP.Theme.metrics.header,
		"Default: the title sits in the top bar, the note below it")
end
Mock.chatLockdown = true
Mock.Click(levelCard.buttons[1])
equal(#Mock.sent, 0, "chat lockdown: the click sends nothing")
Mock.chatLockdown = nil
Mock.Click(levelCard.buttons[1])
check(Mock.sent[1] and Mock.sent[1][1]:find("leveled up from 5 to 6") and Mock.sent[1][2] == "EMOTE",
	"a click sends the emote")
check(not levelCard:IsShown(), "and the card goes once all it offers is sent")
-- In a party, with party chat ticked: the party is told at once, after any fight; the emote waits for its click.
S.inGroup, AP.db.char.levelparty = true, true
Mock.inCombat = true
Mock.Fire("PLAYER_LEVEL_UP", 7, 10, 0, 0, 0)
Mock.Advance(1)
equal(#Mock.sent, 1, "in a fight, the party waits")
Mock.inCombat = false
Mock.Fire("PLAYER_REGEN_ENABLED")
check(Mock.sent[2] and Mock.sent[2][2] == "PARTY" and Mock.sent[2][1]:find("to 7", 1, true),
	"after it, the party is told by itself")
equal(#Mock.blocked, 0, "and nothing the client blocks is tried")
check(levelCard:IsShown() and levelCard.buttons[1]:GetText():upper() == "EMOTE" and not levelCard.buttons[2]:IsShown(),
	"the card offers only the emote")
levelCard:Hide()
S.inGroup, AP.db.char.levelparty = nil, false

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
	if row.key == "leveling" then
		check(not browser.ui.empty:IsShown(), "Leveling isn't empty")
		equal(browser.ui.rows[1].guide and browser.ui.rows[1].guide.name, "Northshire Valley (1-6)",
			"it lists the Northshire test guide")
	else
		check(browser.ui.empty:IsShown(), "an empty category says so")
	end
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
	-- /apg chattest tries chat with no click; the mock blocks it, as the client did.
	local blockedBefore = #Mock.blocked
	Mock.restrictions[5] = 2                   -- the client's Chat restriction on
	SlashCmdList.AEGISPATHFINDER("chattest")
	check(Chat("Chat test: in 2 seconds"), "/apg chattest says what it will try")
	Mock.Advance(2.5)
	check(Mock.blocked[blockedBefore + 1] and Mock.blocked[blockedBefore + 1][2] == "EMOTE"
		and Mock.blocked[blockedBefore + 1][1]:find("(a test)", 1, true), "it tries the emote with no click")
	Mock.Advance(4)
	check(Chat("Chat test, Emote: "), "and reports how it went")
	check(Chat("restrictions on as it sent: Chat"), "and which of the client's restrictions were on as it sent")
	Mock.restrictions[5] = nil
	check(AP.Extras.RestrictionsNow() == "none", "none on, it says so")
	for index = #Mock.blocked, blockedBefore + 1, -1 do table.remove(Mock.blocked, index) end
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
-- With DialogueUI the game's quest window never opens: its own does. 0.3.2 asked the
-- game's window and accepted nothing.
QuestFrame:Hide()
Mock.accepted = nil
Mock.Fire("QUEST_DETAIL", 0)
Mock.Advance(0.5)
check(Mock.accepted, "an offered quest is accepted by itself, though the game's quest window stays shut")
-- Closed before the moment passes: nothing is accepted.
Mock.accepted = nil
Mock.Fire("QUEST_DETAIL", 0)
Mock.Fire("QUEST_FINISHED")
Mock.Advance(0.5)
check(not Mock.accepted, "a quest closed at once is not accepted")
-- A looted item that starts a quest (the kobold's chewed book) is opened by itself.
Mock.bagSlot2 = { itemID = 990001, name = "Nibbled-On Book", questID = 91741 }
Mock.inCombat = true
Mock.Fire("BAG_UPDATE_DELAYED")
Mock.Advance(0.5)
equal(#Mock.used, 0, "a quest's item looted in a fight waits")
Mock.inCombat = false
Mock.Fire("PLAYER_REGEN_ENABLED")
Mock.Advance(0.5)
equal(Mock.used[1] and Mock.used[1].questID, 91741, "and is opened by itself once the fight ends")
Mock.Fire("BAG_UPDATE_DELAYED")
Mock.Advance(0.5)
equal(#Mock.used, 1, "only once")
Mock.bagSlot2 = { itemID = 990002, name = "Old Letter", questID = 91999, isActive = true }
Mock.Fire("BAG_UPDATE_DELAYED")
Mock.Advance(0.5)
equal(#Mock.used, 1, "never one whose quest you already have")
Mock.bagSlot2 = nil
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

-- The mock is a Human Warrior: the Mage's and the Dwarf's steps (2 and 4) aren't theirs.
local ok, why = AP:RegisterGuide({ name = "Test Guide (1-2)", category = "leveling", faction = "Alliance",
	minLevel = 1, maxLevel = 2, steps = {
		{ action = "ACCEPT", qid = 600, title = "First", map = 1429, x = 0.5, y = 0.5, note = "Here." },
		{ action = "NOTE", title = "Mages only", class = { "MAGE" }, map = 1429, x = 0.9, y = 0.9 },
		{ action = "COMPLETE", qid = 600, title = "First" },
		{ action = "NOTE", title = "Dwarves only", race = "Dwarf", map = 1429, x = 0.8, y = 0.8 },
		{ action = "TURNIN", qid = 600, title = "First" },
		{ action = "RUN", title = "Onwards", map = 1429, x = 0.3, y = 0.3 },
	} })
check(ok, "a guide registers: " .. tostring(why))
check(not AP:RegisterGuide({ name = "Bad", steps = { { action = "FLAP" } } }), "an unknown action is refused")
check(not AP:RegisterGuide({ name = "Bad", steps = { { action = "NOTE", class = { "Warlock" } } } }),
	"a class not written as the client's token is refused")
check(not AP:RegisterGuide({ name = "Bad", steps = { { action = "NOTE", race = { "Undead" } } } }),
	"so is a race (an Undead is Scourge)")
local test = AP.guides["Test Guide (1-2)"]
AP:LoadGuide("Test Guide (1-2)")
equal(#AP:GuideSteps(test), 4, "a step for another class or race isn't the character's")
equal(guide.ui.navCount:GetText(), "0 / 4", "and isn't counted")
equal((AP:GetCurrentStep()), 1, "the guide starts at its first step")
check(Mock.waypoint and Mock.waypoint.x == 0.5, "the step's place goes on the map")
check(not guide.ui.empty:IsShown(), "the empty state gives way to the steps")
local focusRow = guide.ui.rows[1]
check(focusRow.band:IsShown() and focusRow.bandNote:IsShown() and focusRow.bandNote:GetText() == "Here.",
	"an ACCEPT step's band shows its note under it, in focus mode")
equal((focusRow.band:GetPoint(1)), "TOPLEFT", "the band sits at the top of the row, not over all of it")
check(select(2, focusRow.bandNote:GetPoint(1)) == focusRow.band, "the note hangs under the band")
check(focusRow:GetHeight() >= focusRow.band:GetHeight() + 6 + focusRow.bandNote:GetStringHeight(),
	"and the row is tall enough for it")
equal(AP.db.char.pointed and AP.db.char.pointed.index, 1, "which step's pin is down is saved, for a /reload")
AP.db.char.waypoints = false
AP:GuideChanged()
check(Mock.waypoint == nil, "switching waypoints off takes our pin away")
AP.db.char.waypoints = true
AP:GuideChanged()
check(Mock.waypoint and Mock.waypoint.x == 0.5, "and on puts it back")

-- Pathfinder's arrow points at the step's place, as the Turtle addon's did. Map 1429 is
-- 3000 x 2000 yards in the mock; the step is at 0.5, 0.5.
local arrow = AP.navarrow
check(arrow and arrow:IsShown(), "Pathfinder's arrow shows for a step with a place")
equal(arrow:GetFrameStrata(), "MEDIUM", "under the windows, never over them")
check(not AP.Theme:IsWindow(arrow), "and not stacked with them")
local wasX, wasY = S.x, S.y
S.x, S.y, S.facing = 0.5, 0.6, 0                  -- 200 yards south of the place, facing north
Mock.Update(0.2)
equal(arrow.distance:GetText(), "200 yd", "how far, in yards")
check(math.abs(arrow.angle) < 1e-6, "straight ahead: the place is north, and you face north")
equal(arrow.icon:GetRotation(), arrow.angle, "the art is turned to match")
equal(arrow.eta:GetText(), "0:29", "about how long it takes to run there")
equal(arrow.instruction:GetText(), "Head to the quest giver", "and what to do there")
S.facing = math.pi / 2                            -- facing west: the place is to your right
Mock.Update(0.2)
check(math.abs(arrow.angle + math.pi / 2) < 1e-6, "facing west, it points right")
S.facing, S.x, S.y = 0, 0.6, 0.5                  -- 300 yards east of it, facing north
Mock.Update(0.2)
check(math.abs(arrow.angle - math.pi / 2) < 1e-6, "with the place to the west, it points left")
equal(arrow.distance:GetText(), "300 yd", "east to west in the map's own yards")
S.x, S.y = 0.5, 0.55
Mock.Update(0.05)
equal(arrow.distance:GetText(), "300 yd", "it updates about ten times a second, not every frame")
Mock.Update(0.06)
equal(arrow.distance:GetText(), "100 yd", "and then it does")
S.y = 0.5015                                      -- 3 yards away
Mock.Update(0.2)
equal(arrow.distance:GetText(), "You're here", "close by, it says you're there")
equal((arrow.distance:GetPoint(1)), "TOP", "under the middle of the arrow")
S.y, S.runSpeed = 0.6, 14
Mock.Update(0.2)
equal(arrow.eta:GetText(), "0:14", "the time goes by your speed (a mount's, on one)")
S.runSpeed, S.facing = 7, nil
Mock.Update(0.2)
check(arrow:IsShown() and not arrow.icon:IsShown() and arrow.distance:GetText() == "200 yd",
	"with no facing from the client, no arrow, but still how far")
S.facing = 0
-- The place on a map you aren't on: both points go onto the map above them.
S.positions, S.parents[1429], S.rects["1429>1415"], S.mapSize[1415] = { [1415] = { 0.45, 0.72 } },
	1415, { 0.4, 0.5, 0.6, 0.8 }, { 30000, 20000 }
Mock.Update(0.2)
equal(arrow.distance:GetText(), "400 yd", "a place on another map is measured on the map above both")
check(math.abs(arrow.angle) < 1e-6, "and pointed at")
S.positions[1415] = { 0.43, 0.72 }
local offAngle, offYards = AP:NavArrowBearing({ map = 1429, x = 0.2, y = 0.7 })
check(math.abs(offYards - 500) < 1e-6 and math.abs(offAngle - math.atan2(300, -400)) < 1e-6,
	"an off-centre place goes onto it x to x and y to y")
S.positions, S.parents[1429], S.rects["1429>1415"] = nil, nil, nil
S.x = nil                                         -- no position, as inside Forever's dungeons
Mock.Update(0.2)
check(arrow:IsShown() and not arrow.icon:IsShown() and not arrow.distance:IsShown(),
	"no position for you (a dungeon): nothing on it")
check(not arrow:IsMouseEnabled(), "and the empty frame lets the mouse through")
S.x, S.y = 0.5, 0.6
Mock.Update(0.2)
check(arrow.icon:IsShown() and arrow:IsMouseEnabled(), "back outside, it points again, and can be dragged")
AP:SetGuideLocked(true)
check(arrow:IsShown() and not arrow:IsMouseEnabled(), "Lock window holds the arrow too, and the mouse goes through")
AP:SetGuideLocked(false)
check(arrow:IsMouseEnabled(), "unlocked, it can be dragged again")
check(arrow.icon:GetTexture() == AP.Theme.texture.navArrow or arrow.icon:GetTexture() == AP.Theme.texture.navArrowMask,
	"it draws Pathfinder's arrow art")
check(arrow.distance._shadowColor and arrow.instruction._shadowColor, "its words are shadowed, to read over the world")
-- Its switch, its command, its place, its size.
SlashCmdList.AEGISPATHFINDER("arrow")
check(AP.db.char.navarrow == false and not arrow:IsShown(), "/apg arrow hides it")
SlashCmdList.AEGISPATHFINDER("arrow")
check(AP:IsNavArrowOn() and arrow:IsShown(), "and shows it again")
AP:OpenConfigPage("Navigation")
local arrowSwitch
for _, found in ipairs(Mock.FindText("Show Pathfinder's arrow", AP.optionsframe)) do
	if found.label then arrowSwitch = found end
end
check(arrowSwitch, "Settings, Navigation has the arrow's switch")
Mock.Click(arrowSwitch)
check(AP.db.char.navarrow == false and not arrow:IsShown(), "switching it off hides the arrow")
Mock.Click(arrowSwitch)
check(AP:IsNavArrowOn() and arrow:IsShown(), "and on shows it")
AP:ToggleConfigPanel()
arrow:ClearAllPoints()
arrow:SetPoint("CENTER", UIParent, "CENTER", 10, 20)
arrow:_Run("OnDragStop")
equal(AP.db.profile.navarrowpoint, "CENTER", "where it's dragged to is saved")
AP:ResetWindowLayout()
equal(AP.db.profile.navarrowpoint, nil, "Reset windows puts it back")
equal((arrow:GetPoint(1)), "TOP", "at the top of the screen")
AP:SetNavArrowScale(1.5)
equal(arrow:GetScale(), AP.Theme.windowScale * 1.5, "its size goes with the window scale")
local wasScale = AP.Theme.windowScale
AP:SetWindowScale(1.2)
equal(arrow:GetScale(), AP.Theme.windowScale * 1.5, "and keeps its own size when the window scale changes")
AP:SetWindowScale(wasScale)
AP:SetNavArrowScale(1)
guide:Hide()
check(not arrow:IsShown(), "it hides with the guide window")
guide:Show()
check(arrow:IsShown(), "and comes back with it")
S.x, S.y = wasX, wasY
S.log = { { questID = 600, title = "First", level = 1, objectives = { { text = "Thing", numFulfilled = 0, numRequired = 1 } } } }
Mock.Fire("QUEST_ACCEPTED", 600)
equal((AP:GetCurrentStep()), 3, "accepting ticks the ACCEPT step, and the Mage's step is passed by")
check(Mock.waypoint == nil, "a step with no place takes our pin away")
check(not arrow:IsShown(), "and the arrow hides")
S.log[1].objectives[1].numFulfilled = 1
Mock.Fire("QUEST_LOG_UPDATE")
Mock.Advance(1)
equal((AP:GetCurrentStep()), 5, "finishing the objectives ticks COMPLETE, past the Dwarf's step")
S.log = {}
Mock.Fire("QUEST_TURNED_IN", 600, 100, 0)
Mock.Advance(2)
local current, _, position, mineCount = AP:GetCurrentStep()
equal(current, 6, "handing in ticks TURNIN")
equal(position .. " of " .. mineCount, "4 of 4", "the step's place among the character's own")
equal(guide.ui.navStep:GetText(), "STEP 4", "the nav row counts the character's steps")
check(Mock.waypoint and Mock.waypoint.x == 0.3, "the next step's place goes on the map, never another class's")
check(arrow:IsShown(), "the next step with a place brings the arrow back")
Mock.waypoint = { uiMapID = 1429, x = 0.11, y = 0.22 }
AP:ScanGuide()
equal(Mock.waypoint.x, 0.11, "the same step isn't pointed at again: a pin the player set stays")
AP:StepBack()
equal((AP:GetCurrentStep()), 5, "the left arrow goes back to the hand-in")
equal(Mock.waypoint and Mock.waypoint.x, 0.11, "a step with no place leaves a pin the player set")
AP:StepBack()
equal((AP:GetCurrentStep()), 3, "and back again, over the Dwarf's step")
AP:StepForward()
equal((AP:GetCurrentStep()), 5, "the right arrow forward, over it too")
AP:StepForward()
equal((AP:GetCurrentStep()), 6, "and on to the end")
S.class = "MAGE"
equal(#AP:GuideSteps(test), 5, "a Mage has the Mage's step")
S.class = "WARRIOR"
AP:ToggleOverviewMode()
AP:RefreshObjectivePanel()
for _, row in ipairs(guide.ui.rows) do
	if row:IsShown() then
		check(not (row.data and (row.data.class or row.data.race)), "the list leaves the others' steps out")
		check(not row.bandNote:IsShown(), "the list shows no notes under bands (they're on hover)")
	end
end
AP:ToggleOverviewMode()
Mock.waypoint = { uiMapID = 1429, x = 0.3, y = 0.3 }
AP:StepForward()
check(select(2, AP:GetCurrentStep()) == nil, "the last step done, the guide is done")
equal(focusRow.title:GetText(), "Guide done", "and says so")
check(Mock.waypoint == nil, "its pin is taken away")
check(not arrow:IsShown(), "and the arrow goes")
AP:UnloadGuide()
check(guide.ui.empty:IsShown(), "no guide, the empty state again")
S.faction = "Horde"
AP:RefreshObjectivePanel()
equal(guide.ui.empty.title:GetText(), "NO GUIDES YET", "a Horde character, with no guide for them, isn't told to pick one")
S.faction = "Alliance"
AP:RefreshObjectivePanel()

------------------------------------------------------------------------------------------
-- Steps done together, a COMPLETE step's live progress, and arriving in a kill area
------------------------------------------------------------------------------------------

do
	check(not AP:RegisterGuide({ name = "Bad", steps = { { action = "NOTE", title = "x", together = true } } }),
		"the first step can't be done together with a step before it")
	-- Map 1429 is 3000 x 2000 yards in the mock. Steps 2, 3, 5 (and 4, for a Mage) are one block.
	local ok, why = AP:RegisterGuide({ name = "Together Test (1-2)", category = "leveling", faction = "Alliance",
		minLevel = 1, maxLevel = 2, steps = {
			{ action = "ACCEPT", qid = 700, title = "Camp", map = 1429, x = 0.3, y = 0.3 },
			{ action = "COMPLETE", qid = 700, title = "Camp", map = 1429, x = 0.5, y = 0.5, note = "Kill kobolds." },
			{ action = "ACCEPT", qid = 701, title = "Chewed Book", together = true, fromitem = true, map = 1429, x = 0.51, y = 0.5 },
			{ action = "NOTE", title = "Mages only", class = { "MAGE" }, together = true },
			{ action = "COMPLETE", qid = 702, title = "Wolves", together = true, map = 1429, x = 0.7, y = 0.5 },
			{ action = "TURNIN", qid = 700, title = "Camp", map = 1429, x = 0.3, y = 0.3 },
		} })
	check(ok, "a guide with steps done together registers: " .. tostring(why))
	local tg = AP.guides["Together Test (1-2)"]
	local arrow, rows = AP.navarrow, guide.ui.rows
	S.log, S.completed, S.x, S.y, S.facing = {}, {}, 0.3, 0.3, 0
	AP.db.char.progress, AP.db.char.arrived = {}, nil
	AP:LoadGuide(tg.name)
	S.log[1] = { questID = 700, title = "Camp", level = 1,
		objectives = { { text = "Kobold Vermin slain", numFulfilled = 0, numRequired = 10 } } }
	S.log[2] = { questID = 702, title = "Wolves", level = 1,
		objectives = { { text = "Tough Wolf Meat", type = "item", numFulfilled = 0, numRequired = 8 } } }
	Mock.Fire("QUEST_ACCEPTED", 700)
	equal((AP:GetCurrentStep()), 2, "the camp's first step")
	equal(table.concat(AP:GetCurrentBlock(), ","), "2,3,5", "it's a block with the book and the wolves")
	S.class = "MAGE"
	equal(#AP:GetCurrentBlock(), 4, "with the Mage's step, for a Mage")
	S.class = "WARRIOR"
	AP:RefreshObjectivePanel()
	check(rows[1]:IsShown() and rows[2]:IsShown() and rows[3]:IsShown() and not (rows[4] and rows[4]:IsShown()),
		"focus shows the block's three steps")
	check(not rows[2].band:IsShown() and rows[2].check:IsShown(), "the book is a box to tick, not a band")
	equal(select(5, rows[2]:GetPoint(1)), -rows[1]:GetHeight(), "each under the one before")
	check(rows[1].meter and rows[1].meter:IsShown(), "the kobolds' progress shows in a box")
	equal(rows[1].meter.lines[1].label:GetText(), "Kobold Vermin slain", "what the quest wants")
	equal(rows[1].meter.lines[1].count:GetText(), "0 / 10", "and how much of it")
	equal(rows[3].meter.lines[1].count:GetText(), "0 / 8", "the wolves' too")
	check(rows[1].note:IsShown() and not rows[3].note:IsShown(), "the step you're on has its note; the others on hover")
	S.log[1].objectives[1].numFulfilled = 3
	Mock.Fire("QUEST_LOG_UPDATE")
	Mock.Advance(1)
	equal(rows[1].meter.lines[1].count:GetText(), "3 / 10", "it counts as you kill")
	check(math.abs(rows[1].meter.lines[1].bar.ratio - 0.3) < 1e-6, "and the bar fills")
	-- The book: looted, it ticks; the step you're on stays the kobolds.
	Mock.bagSlot2 = { itemID = 990003, name = "Chewed Book", questID = 701 }
	Mock.Fire("BAG_UPDATE_DELAYED")
	Mock.Advance(1)
	check(AP:IsStepDone(tg.name, 3) and rows[2].check:GetChecked(), "the book in your bags ticks its box")
	equal((AP:GetCurrentStep()), 2, "while the kobolds are still to do")
	Mock.bagSlot2 = nil
	-- The list: the block without bands, a COMPLETE's line saying how far along it is.
	AP:ToggleOverviewMode()
	local listNote
	for _, row in ipairs(rows) do
		if row:IsShown() and row.step == 2 then listNote = row.note:GetText() end
		if row:IsShown() and row.step == 3 then check(not row.band:IsShown(), "the list shows the book without a band") end
	end
	equal(listNote, "Kobold Vermin slain - 3/10", "the list says how far along the kobolds are")
	AP:ToggleOverviewMode()

	-- Arriving: 200 yards off, the camp is marked; 40 yards off, it isn't (the pin and the arrow go).
	S.x, S.y = 0.5, 0.6
	AP:GuideChanged()
	Mock.Update(0.2)
	check(Mock.waypoint and Mock.waypoint.x == 0.5 and arrow:IsShown(), "on the way, the camp is marked")
	S.y = 0.52
	Mock.Advance(1)
	Mock.Update(0.2)
	check(Mock.waypoint == nil and not arrow:IsShown(), "in the camp, nothing marks it")
	equal(AP.db.char.arrived and AP.db.char.arrived.block, 2, "and that is saved for a /reload")
	AP:GuideChanged()
	check(Mock.waypoint == nil, "it stays unmarked")
	-- The kobolds done, the wolves are 600 yards on: marked again, until you get there.
	S.log[1].objectives[1].numFulfilled = 10
	Mock.Fire("QUEST_LOG_UPDATE")
	Mock.Advance(1)
	equal((AP:GetCurrentStep()), 5, "the kobolds done, the wolves are next")
	check(Mock.waypoint and Mock.waypoint.x == 0.7, "far off, the wolves are marked")
	Mock.waypoint = nil
	AP:GuideChanged()
	Mock.waypoint = { uiMapID = 1429, x = 0.11, y = 0.22 }      -- a pin the player put down
	S.x, S.y = 0.7, 0.52
	Mock.Advance(1)
	equal(Mock.waypoint and Mock.waypoint.x, 0.11, "arriving leaves a pin the player set")
	Mock.waypoint = nil
	S.log[2].objectives[1].numFulfilled = 8
	Mock.Fire("QUEST_LOG_UPDATE")
	Mock.Advance(1)
	equal((AP:GetCurrentStep()), 6, "the block done, the hand-in")
	check(Mock.waypoint and Mock.waypoint.x == 0.3, "is marked")
	equal(AP.db.char.arrived, nil, "and the arrival is forgotten")
	-- With the arrow switched off, arriving still takes the pin away.
	AP:StepBack()
	AP.db.char.arrived = nil
	S.x, S.y = 0.7, 0.8
	AP.db.char.navarrow = false
	AP:GuideChanged()
	check(Mock.waypoint and Mock.waypoint.x == 0.7, "back in the block, away from the wolves, they're marked")
	S.y = 0.52
	Mock.Advance(1)
	check(Mock.waypoint == nil, "arriving takes the pin away, with the arrow off too")
	AP.db.char.navarrow = nil
	-- No position (a dungeon): never counted as arrived.
	AP.db.char.arrived = nil
	S.x = nil
	AP:GuideChanged()
	Mock.Advance(2)
	equal(AP.db.char.arrived, nil, "with no position, never arrived")
	AP:UnloadGuide()
	S.log, S.completed, S.x, S.y = {}, {}, 0.4, 0.6
	AP.db.char.progress, AP.db.char.arrived = {}, nil
end

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

------------------------------------------------------------------------------------------
-- The Northshire test guide (Guides/Northshire.lua), played through
------------------------------------------------------------------------------------------

local NORTH = "Northshire Valley (1-6)"
local north = AP.guides[NORTH]
check(north, "the Northshire guide registers (RegisterGuide refused nothing)")
equal(north.faction, "Alliance", "for the Alliance")
local wellFormed = true
for index, step in ipairs(north.steps) do
	local where = "Northshire step " .. index
	local quest = step.action == "ACCEPT" or step.action == "COMPLETE" or step.action == "TURNIN"
	local placed = step.map ~= nil
	if not (step.title and step.title ~= "") then wellFormed = false; check(false, where .. " has a title") end
	if quest and type(step.qid) ~= "number" then wellFormed = false; check(false, where .. " has a quest id") end
	if placed ~= (step.x ~= nil) or placed ~= (step.y ~= nil)
		or (placed and not (step.x > 0 and step.x < 1 and step.y > 0 and step.y < 1)) then
		wellFormed = false
		check(false, where .. " has a whole place on the map")
	end
	if step.note and step.note:find("<name>", 1, true) then wellFormed = false; check(false, where .. " names no one") end
end
check(wellFormed, "every Northshire step has a title, its quest id and a whole place, and names no one")

-- Plays the guide through as `class`, doing each step as the game would tick it.
-- Returns how many steps the class had.
local function PlayThrough(class)
	S.class, S.log, S.completed = class, {}, {}
	AP.db.char.progress = {}
	AP:LoadGuide(NORTH)
	local mine = AP:GuideSteps(north)
	local stuck
	for _, index in ipairs(mine) do
		local current, step = AP:GetCurrentStep()
		if current ~= index then
			stuck = string.format("%s: step %d (%s %s) came when step %d was due", class, current,
				step and step.action or "?", step and step.title or "the end", index)
			break
		end
		if step.action == "ACCEPT" then
			S.log[#S.log + 1] = { questID = step.qid, title = step.title, level = 1,
				objectives = { { text = "Thing", numFulfilled = 0, numRequired = 1 } } }
			Mock.Fire("QUEST_ACCEPTED", step.qid)
		elseif step.action == "COMPLETE" then
			for _, entry in ipairs(S.log) do
				if entry.questID == step.qid then entry.objectives[1].numFulfilled = 1 end
			end
			Mock.Fire("QUEST_LOG_UPDATE")
			Mock.Advance(1)
		elseif step.action == "TURNIN" then
			for i = #S.log, 1, -1 do
				if S.log[i].questID == step.qid then table.remove(S.log, i) end
			end
			S.completed[step.qid] = true
			Mock.Fire("QUEST_TURNED_IN", step.qid, 0, 0)
			Mock.Advance(1)
		else
			AP:StepForward()
		end
	end
	check(not stuck, stuck or (class .. ": every step comes in order, and each one ticks"))
	check(select(2, AP:GetCurrentStep()) == nil, class .. ": the guide ends")
	equal(guide.ui.navCount:GetText(), #mine .. " / " .. #mine, class .. ": all of the class's steps are counted done")
	AP:UnloadGuide()
	return #mine
end

-- How many steps are for everyone, and for one class.
local function StepsFor(class)
	local n = 0
	for _, step in ipairs(north.steps) do
		local mine = not step.class
		for _, token in ipairs(step.class or {}) do
			if token == class then mine = true end
		end
		if mine then n = n + 1 end
	end
	return n
end

AP:LoadGuide(NORTH)
check(Mock.waypoint and Mock.waypoint.uiMapID == 1429 and math.abs(Mock.waypoint.x - 0.4814) < 0.01,
	"opening Northshire points at Deputy Willem")
equal(guide.ui.rows[1].bandNote:GetText(), north.steps[1].note, "the first step says who and where")
AP:UnloadGuide()
AP:UnloadGuide()
S.log, S.completed, S.class = {}, {}, "WARRIOR"
AP.db.char.progress, AP.db.char.arrived = {}, nil
AP:LoadGuide(NORTH)
while (AP:GetCurrentStep()) < 8 do AP:StepForward() end
equal(table.concat(AP:GetCurrentBlock(), ","), "8,9,10", "Northshire's kobold camp: the kobolds, the book and the wolves")
S.x, S.y = 0.47, 0.365
Mock.Advance(1)
Mock.Update(0.2)
check(Mock.waypoint == nil and not AP.navarrow:IsShown(), "in the camp, the guide stops marking it")
AP:UnloadGuide()
AP.db.char.arrived = nil
equal(PlayThrough("WARLOCK"), StepsFor("WARLOCK"), "a Warlock gets the Warlock's letter and tome")
equal(PlayThrough("WARRIOR"), StepsFor("WARRIOR"), "a Warrior gets the Warrior's letter, and no Warlock steps")
check(StepsFor("WARLOCK") > StepsFor("WARRIOR"), "the classes' guides differ")
S.class, S.log, S.completed = "WARRIOR", {}, {}
AP.db.char.progress = {}

equal(#Mock.blocked, 0, "nothing the client would block was tried")

-- Nothing of Blizzard's popup system was touched: writing into it taints Escape.
equal(next(StaticPopupDialogs), nil, "StaticPopupDialogs is left alone")
check(rawequal(StaticPopupDialogs, Mock.staticPopupDialogs), "and never reassigned")

return string.format("%d checks passed", checks)
