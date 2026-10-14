local _, AP = ...
local Theme = AP.Theme
local Compat = AP.Compat
local Call, Readable = Compat.Call, Compat.Readable

--[[
	Automation.lua -- the Automation page: what the addon does for you that
	needs no guide.

	  * Quests: accept what an NPC offers, hand in what is done, and pick a
	    quest out of an NPC's list. Never a grey quest, never a reward choice
	    (that is the player's), never past two free places in the quest log.
	  * Selling greys by themselves as a vendor opens, with the game's own
	    "Sell All Junk" where it has it; and a "Sell greys" button on the vendor
	    window when the game has no button of its own.
	  * Repairing as the vendor opens: with your own money, or the guild's first.
	  * Quests from items: a looted item that starts a quest (a kobold's chewed
	    book) is opened at once, so its quest comes up and is accepted like an
	    NPC's. Out of combat only, once per quest a session, with quest
	    automation on.

	Holding Shift as a window opens does none of it. Everything waits a moment
	after the window's event, so the data collector reads the quest frame first.
	An error on the way is reported, not swallowed, so a step that fails in a
	client shows why.
]]

local Auto = {}
AP.Automation = Auto

local DELAY = 0.15        -- after the event, before acting on it
local KEEP_FREE = 2       -- quest log places kept free

local function Char() return AP.db.char end

local function Wanted()
	return Char().autoquest and not IsShiftKeyDown()
end

local function Later(fn)
	C_Timer.After(DELAY, function()
		if IsShiftKeyDown() then return end
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end)
end

local function LogHasRoom()
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetMaxNumQuestsCanAccept) then return true end
	local _, count = Compat.CallAll(C_QuestLog.GetNumQuestLogEntries)
	local max = Call(C_QuestLog.GetMaxNumQuestsCanAccept)
	if not (count and max) then return true end
	return max - count > KEEP_FREE
end

--[[ Quests ]]

-- Whether an NPC's quest is open, from QUEST_DETAIL to QUEST_FINISHED. Not the
-- game's QuestFrame: an addon such as DialogueUI shows its own window instead,
-- and the game's never opens.
local questOpen = false

function Auto:QuestDetail()
	questOpen = true
	if not Wanted() then return end
	local questID = Call(GetQuestID)
	if questID and Call(C_QuestLog.IsQuestTrivial, questID) then return end
	if not LogHasRoom() then return end
	Later(function()
		if not questOpen then return end
		if QuestGetAutoAccept and QuestGetAutoAccept() then
			if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
		else
			AcceptQuest()
		end
	end)
end

function Auto:QuestFinished() questOpen = false end

function Auto:QuestProgress()
	if not Wanted() then return end
	Later(function()
		if IsQuestCompletable() then CompleteQuest() end
	end)
end

function Auto:QuestComplete()
	if not Wanted() then return end
	local choices = Call(GetNumQuestChoices) or 0
	if choices > 1 then return end
	-- A quest that costs money to hand in asks the player.
	local cost = Call(GetQuestMoneyToGet) or 0
	if cost > 0 then return end
	Later(function() GetQuestReward(choices == 1 and 1 or 0) end)
end

-- An NPC's list: a quest to hand in first, then one to take.
function Auto:Gossip()
	if not (Wanted() and Char().autogossip ~= false and C_GossipInfo) then return end
	local active = Call(C_GossipInfo.GetActiveQuests) or {}
	for _, quest in ipairs(active) do
		if Readable(quest.isComplete) then
			local questID = Readable(quest.questID)
			return Later(function() C_GossipInfo.SelectActiveQuest(questID) end)
		end
	end
	if not LogHasRoom() then return end
	local available = Call(C_GossipInfo.GetAvailableQuests) or {}
	for _, quest in ipairs(available) do
		if not Readable(quest.isTrivial) and not Readable(quest.isIgnored) then
			local questID = Readable(quest.questID)
			return Later(function() C_GossipInfo.SelectAvailableQuest(questID) end)
		end
	end
end

-- The older quest greeting, for NPCs with only quests to offer.
function Auto:Greeting()
	if not (Wanted() and Char().autogossip ~= false) then return end
	for index = 1, Call(GetNumActiveQuests) or 0 do
		local _, isComplete = Compat.CallAll(GetActiveTitle, index)
		if isComplete then return Later(function() SelectActiveQuest(index) end) end
	end
	if not LogHasRoom() then return end
	for index = 1, Call(GetNumAvailableQuests) or 0 do
		local isTrivial = Call(GetAvailableQuestInfo, index)
		if not isTrivial then return Later(function() SelectAvailableQuest(index) end) end
	end
end

--[[ Quests from items ]]

local opened = {}        -- [questID] = true: its item was opened this session

--- Open a looted item that starts a quest not yet taken; the quest window it brings
--- up is then accepted (QuestDetail). Returns the quest id, when one was opened.
function Auto:OpenQuestItems()
	if not Wanted() or InCombatLockdown() then return end
	if not (C_Container and C_Container.GetContainerItemQuestInfo and C_Container.UseContainerItem) then return end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, Call(C_Container.GetContainerNumSlots, bag) or 0 do
			local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
			local questID = ok and type(info) == "table" and Readable(info.questID)
			if type(questID) == "number" and not Readable(info.isActive) and not opened[questID]
				and not Call(C_QuestLog.IsQuestFlaggedCompleted, questID) and LogHasRoom() then
				opened[questID] = true
				Later(function()
					if not InCombatLockdown() then C_Container.UseContainerItem(bag, slot) end
				end)
				return questID
			end
		end
	end
end

--[[ Selling greys ]]

function Auto.Greys()
	local out = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, Call(C_Container.GetContainerNumSlots, bag) or 0 do
			local info = Call(C_Container.GetContainerItemInfo, bag, slot)
			if type(info) == "table" and info.quality == 0 and not info.hasNoValue and not info.isLocked then
				out[#out + 1] = { bag, slot }
			end
		end
	end
	return out
end

-- The game's own "Sell All Junk" (Mainline's merchant window), when it has one.
local function GameSellsJunk()
	return C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and C_MerchantFrame.GetNumJunkItems and true or false
end

--[[ Whether a vendor is open, from MERCHANT_SHOW to MERCHANT_CLOSED. Forever opens its
	merchant window through the player interaction manager (its own event), so at
	MERCHANT_SHOW the window may not be shown yet: asking the window missed every sale. ]]
local merchantOpen = false

function Auto:SellGreys(quiet)
	if not (merchantOpen or (MerchantFrame and MerchantFrame:IsVisible())) then return 0 end
	local count
	if GameSellsJunk() then
		count = Call(C_MerchantFrame.GetNumJunkItems) or 0
	else
		count = #Auto.Greys()
	end
	if count == 0 then
		if not quiet then AP:Print("No grey items to sell.") end
		return 0
	end
	local before = GetMoney()
	if GameSellsJunk() then
		C_MerchantFrame.SellAllJunkItems()
	else
		for _, g in ipairs(Auto.Greys()) do C_Container.UseContainerItem(g[1], g[2]) end
	end
	C_Timer.After(1, function()
		local gained = GetMoney() - before
		AP:Say(string.format("Sold %d grey item%s%s.", count, count == 1 and "" or "s",
			gained > 0 and (" for " .. Compat.MoneyText(gained)) or ""))
	end)
	return count
end

function Auto:PlaceButton()
	local b = self.button
	if not b and MerchantFrame then
		b = Theme:PanelButton(MerchantFrame, "Sell greys", 92, 20)
		b:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -44, -32)
		b:SetFrameLevel(MerchantFrame:GetFrameLevel() + 5)
		b:SetScript("OnClick", function() Auto:SellGreys() end)
		self.button = b
	end
	-- Not beside the game's own Sell All Junk button.
	local gameButton = C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled
		and Call(C_MerchantFrame.IsSellAllJunkEnabled)
	if b then b:SetShown(Char().sellbutton ~= false and not gameButton) end
end

--[[ Repairing ]]

function Auto:Repair()
	local how = Char().autorepair
	if (how ~= "own" and how ~= "guild") or IsShiftKeyDown() then return end
	if not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost = Call(GetRepairAllCost) or 0
	if cost <= 0 then return end
	if how == "guild" and CanGuildBankRepair and CanGuildBankRepair() then
		RepairAllItems(true)
		AP:Say("Repaired with guild money for " .. Compat.MoneyText(cost) .. ".")
		return
	end
	if GetMoney() < cost then
		AP:Print("Not enough money to repair (" .. Compat.MoneyText(cost) .. ").")
		return
	end
	RepairAllItems()
	AP:Say("Repaired for " .. Compat.MoneyText(cost) .. ".")
end

function Auto:MerchantShow()
	merchantOpen = true
	self:PlaceButton()
	if IsShiftKeyDown() then return end
	self:Repair()
	-- A frame later, once the merchant window is up and the game has counted the junk.
	if Char().autosell then
		C_Timer.After(0, function()
			if merchantOpen then Auto:SellGreys(true) end
		end)
	end
end

function Auto:MerchantClosed()
	merchantOpen = false
end

AP:OnLogin(function()
	AP:On("QUEST_DETAIL", function() Auto:QuestDetail() end)
	AP:On("QUEST_FINISHED", function() Auto:QuestFinished() end)
	AP:On("QUEST_PROGRESS", function() Auto:QuestProgress() end)
	AP:On("QUEST_COMPLETE", function() Auto:QuestComplete() end)
	AP:On("GOSSIP_SHOW", function() Auto:Gossip() end)
	AP:On("QUEST_GREETING", function() Auto:Greeting() end)
	AP:On("MERCHANT_SHOW", function() Auto:MerchantShow() end)
	AP:On("MERCHANT_CLOSED", function() Auto:MerchantClosed() end)
	AP:On("BAG_UPDATE_DELAYED", function() Auto:OpenQuestItems() end)
	-- A book looted in a fight waits for the fight's end.
	AP:On("PLAYER_REGEN_ENABLED", function() Auto:OpenQuestItems() end)
end)
