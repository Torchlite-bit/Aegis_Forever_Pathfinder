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
S.frame = { questID = 176, title = "Wanted: Hogger", text = "A huge gnoll...", objective = "Kill Hogger.",
	xp = 1450, money = 500, choices = { { id = 2224, name = "Militia Dagger" }, { id = 2225, name = "Sharp Kitchen Knife" } } }
Mock.Fire("QUEST_DETAIL", 0)
local quest = data.quests[176]
check(quest, "the offered quest is written down")
equal(quest.title, "Wanted: Hogger", "its title")
equal(quest.objectiveText, "Kill Hogger.", "its objective text")
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
check(#Mock.sent >= 1 and Mock.sent[1][1]:find("leveled up from 5 to 6"), "the level-up emote")

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
	equal(submit.codeHead.label:GetText(), L.SUBMIT_CODE, "under its name")
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

local confirm = function() return _G.AegisPathfinderConfirm end
if skin == "pathfinder" then
	AP:SetTheme("night")
	equal(AP.Theme.current, "night", "a colour theme applies at once")
	check(not (confirm() and confirm():IsShown()), "without a reload")
	AP:SetTheme("blizzard")
	check(confirm() and confirm():IsShown(), "the Blizzard skin asks for a reload")
	Mock.Click(confirm().yes)
	check(Mock.reloaded, "and reloads when told to")
	Mock.reloaded = nil
	AP:SetTheme("pathfinder")
else
	AP:SetTheme("pathfinder")
	check(confirm() and confirm():IsShown(), "leaving the Blizzard skin asks for a reload")
	Mock.Click(confirm().no)
	check(not confirm():IsShown() and not Mock.reloaded, "Later leaves it be")
end
equal(#Mock.popups, 0, "the game's own popups are never used")

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

AP.db.char.autoquest = true
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
MerchantFrame:Show()
Mock.Fire("MERCHANT_SHOW")
equal(#Mock.sold, 1, "greys are sold")
equal(Mock.repaired, "own", "and gear repaired")
check(AP.Automation.button, "the Sell greys button is on the vendor window")

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
AP:ConfirmClearData()
check(confirm():IsShown(), "Clear data asks first")
Mock.Click(confirm().yes)
equal(next(AP.Collector:GetData().quests), nil, "Clear data forgets the quests")
Mock.export = exportText

-- Nothing of Blizzard's popup system was touched: writing into it taints Escape.
equal(next(StaticPopupDialogs), nil, "StaticPopupDialogs is left alone")
check(rawequal(StaticPopupDialogs, Mock.staticPopupDialogs), "and never reassigned")

return string.format("%d checks passed", checks)
