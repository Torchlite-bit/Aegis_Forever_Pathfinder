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
	  * A "Sell greys" button on the vendor window, and selling greys by
	    themselves as it opens.
	  * Repairing as the vendor opens: with your own money, or the guild's first.

	Holding Shift as a window opens does none of it. Everything waits a moment
	after the window's event, so the data collector reads the quest frame first.
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
		if not IsShiftKeyDown() then pcall(fn) end
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

function Auto:QuestDetail()
	if not Wanted() then return end
	local questID = Call(GetQuestID)
	if questID and Call(C_QuestLog.IsQuestTrivial, questID) then return end
	if not LogHasRoom() then return end
	Later(function()
		if QuestFrame and not QuestFrame:IsShown() then return end
		if QuestGetAutoAccept and QuestGetAutoAccept() then
			if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
		else
			AcceptQuest()
		end
	end)
end

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

function Auto:SellGreys(quiet)
	if not (MerchantFrame and MerchantFrame:IsVisible()) then return 0 end
	local greys = Auto.Greys()
	if #greys == 0 then
		if not quiet then AP:Print("No grey items to sell.") end
		return 0
	end
	local before = GetMoney()
	for _, g in ipairs(greys) do C_Container.UseContainerItem(g[1], g[2]) end
	C_Timer.After(1, function()
		local gained = GetMoney() - before
		AP:Say(string.format("Sold %d grey item%s%s.", #greys, #greys == 1 and "" or "s",
			gained > 0 and (" for " .. Compat.MoneyText(gained)) or ""))
	end)
	return #greys
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
	if b then b:SetShown(Char().sellbutton ~= false) end
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
	self:PlaceButton()
	if IsShiftKeyDown() then return end
	self:Repair()
	if Char().autosell then self:SellGreys(true) end
end

AP:OnLogin(function()
	AP:On("QUEST_DETAIL", function() Auto:QuestDetail() end)
	AP:On("QUEST_PROGRESS", function() Auto:QuestProgress() end)
	AP:On("QUEST_COMPLETE", function() Auto:QuestComplete() end)
	AP:On("GOSSIP_SHOW", function() Auto:Gossip() end)
	AP:On("QUEST_GREETING", function() Auto:Greeting() end)
	AP:On("MERCHANT_SHOW", function() Auto:MerchantShow() end)
end)
