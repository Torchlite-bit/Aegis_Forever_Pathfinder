# API migration: 1.12 / Turtle WoW → WoW: Forever

## The Forever client

Checked against the client's own interface code, build **1.60.1.70338**
(the `forever` branch of the Gethe/wow-ui-source mirror, 10 Oct 2026), and
against what the Aegis: Forever Instance Journal learned in game.

| | 1.12 (Turtle WoW) | WoW: Forever |
|---|---|---|
| `## Interface:` | `11200` | **`16001`** (1.60.1 → 1·10000 + 60·100 + 1) |
| Engine | vanilla 1.12 | the **modern retail engine** ("Mainline" family). The game type is **`camelot`**, so Blizzard's TOCs gate files with `[AllowLoadGameType camelot]` |
| `WOW_PROJECT_ID` | — | `WOW_PROJECT_CAMELOT = 18` in 1.60.1 (`Blizzard_ProjectConstants/Camelot`). Beta builds reported `1` (Mainline), so don't rely on it. Prefer the TOC's interface number. |
| Lua | 5.0 | 5.1 (with WoW's extensions) |
| Script handlers | globals `this`, `event`, `arg1`… | `function(self, ...)` arguments |
| Secret values | — | **Yes.** Midnight-era restrictions: unit names and guids, chat text and similar can be "secret" in instances and some fights. Test with `issecretvalue()`. Never compare or store a secret value (`Core/Compat.lua: Readable`). |
| Quest log UI | `QuestLogFrame` | retail `QuestMapFrame` and `QuestInfo` (`Blizzard_UIPanels_Game/Mainline`) |
| Templates missing | — | `ItemButtonTemplate` (found by the Instance Journal's probe). `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `UIPanelCloseButton`, `BackdropTemplate`, `ButtonFrameTemplate` and others are present. |
| Addon compartment | — | not in the camelot UI, so the minimap button stays |
| Player position | `GetPlayerMapPosition` everywhere | `C_Map.GetPlayerMapPosition`, but **none inside Forever's dungeons** |

## Calls the 1.12 addon made, and what replaces them

The counts are uses in the 1.12 addon's own code (guides, tools and libs
left out).

| 1.12 / Turtle | Uses | Forever | Notes |
|---|---|---|---|
| `this` in scripts | 528 | `self` (the handler's first argument) | Done throughout the port |
| `arg1`, `arg2`… in scripts | 40 | handler arguments: `OnEvent(self, event, ...)`, `OnUpdate(self, elapsed)`, `OnMouseWheel(self, delta)`, `OnValueChanged(self, value)`, `OnClick(self, button)` | |
| `table.getn(t)` | 191 | `#t` | |
| `math.mod(a, b)` | 29 | `a % b` | |
| `string.gfind` | 18 | `string.gmatch` | |
| `getglobal(name)` / `setglobal` | 17 | `_G[name]` | |
| `frame:SetScript` after a hook | — | `frame:HookScript` | `SetScript` removes hooks on the modern client. The port hooks `OnShow` and `OnSizeChanged`, because the window stack and the backdrop mixin hook them too. |
| `frame:SetBackdrop` (built in) | — | `CreateFrame(..., "BackdropTemplate")`, or `Mixin(frame, BackdropTemplateMixin)` plus the `OnSizeChanged` hook | `Theme:Backdrop` |
| `FontString:SetFont` returning `nil` on failure | — | returns `success` | `Theme:SetFont` falls back to `STANDARD_TEXT_FONT` |
| `GetNumQuestLogEntries`, `GetQuestLogTitle(i)` | 8 / 5 | `C_QuestLog.GetNumQuestLogEntries()`, `C_QuestLog.GetInfo(i)` (`.questID`, `.title`, `.level`, `.isHeader`, `.suggestedGroup`, `.frequency`) | |
| `GetNumQuestLeaderBoards`, `GetQuestLogLeaderBoard(i)` | 6 / 7 | `C_QuestLog.GetQuestObjectives(questID)` (`.text`, `.type`, `.numFulfilled`, `.numRequired`, `.finished`) | |
| `ExpandQuestHeader` (to see quests under collapsed zones) | 2 | not needed: `C_QuestLog.GetInfo` and `GetLogIndexForQuestID` see every quest | |
| ClassicAPI `C_QuestLog.IsOnQuest`, `GetQuestIDForLogIndex`, `GetTitleForQuestID`, `QUEST_ACCEPTED`, `QUEST_TURNED_IN` | 23 | **native** on Forever: `C_QuestLog.IsOnQuest`, `C_QuestLog.GetTitleForQuestID`, `QUEST_ACCEPTED(questID)`, `QUEST_TURNED_IN(questID, xpReward, moneyReward)` | No DLL required |
| ClassicAPI `IsQuestFlaggedCompleted` / server query | — | `C_QuestLog.IsQuestFlaggedCompleted(questID)`, `C_QuestLog.GetAllCompletedQuestIDs()` | |
| `GetQuestID`, `GetTitleText`, `GetQuestText`, `GetObjectiveText`, `GetProgressText`, `GetRewardText` | — | unchanged globals (the Mainline `QuestFrame` uses them) | Read on `QUEST_DETAIL` / `QUEST_PROGRESS` / `QUEST_COMPLETE` |
| `GetRewardXP`, `GetRewardMoney`, `GetNumQuestChoices`, `GetNumQuestRewards`, `GetQuestItemInfo`, `GetQuestItemLink` | — | unchanged globals | |
| `GetQuestReward(choice)` | — | unchanged. `0` when there's no choice (as `QuestInfoFrame.itemChoice` is) | |
| quest reward spells | — | `C_QuestInfoSystem.GetQuestRewardSpells(questID)`, `GetQuestRewardSpellInfo` | |
| quest reward currencies | — | `C_QuestInfoSystem.GetQuestRewardCurrencies(questID)` | |
| reputation on the quest frame | — | **not shown** for classic factions. Only `C_QuestOffer.GetQuestOfferMajorFactionReputationRewards` (major factions). Reputation is observed after the turn-in instead (see below). | |
| ClassicAPI `C_GossipInfo.GetAvailableQuests` / `SelectAvailableQuest` etc. | 10 | native `C_GossipInfo` (`.questID`, `.isTrivial`, `.isComplete`, `.isIgnored`) | |
| `GetNumAvailableQuests`, `SelectAvailableQuest`, `GetNumActiveQuests`, `GetActiveTitle`, `SelectActiveQuest` | — | unchanged (quest greeting), plus `GetAvailableQuestInfo(i)` for `isTrivial` | |
| `AcceptQuest`, `CompleteQuest`, `IsQuestCompletable` | — | unchanged. `QuestGetAutoAccept` / `AcknowledgeAutoAcceptQuest` for auto-accept quests | |
| `SetMapToCurrentZone`, `GetCurrentMapContinent`, `GetCurrentMapZone`, `GetMapZones`, `GetPlayerMapPosition` | 5 / 8 / 9 / 4 / 5 | `C_Map.GetBestMapForUnit("player")` → uiMapID, `C_Map.GetPlayerMapPosition(uiMapID, "player"):GetXY()` | uiMapIDs replace continent/zone indexes. Coordinates are 0–1. |
| Astrolabe (distance in yards) | 45 | `C_Map.GetWorldPosFromMapPos` if needed. The arrow is now the client's own (`C_SuperTrack`). | |
| TomTom / pfQuest waypoints and arrows | 61 / 85 | `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))`, `C_SuperTrack.SetSuperTrackedUserWaypoint(true)` | `AP:PointAt` |
| `GetContainerNumSlots`, `GetContainerItemLink`, `GetContainerItemInfo`, `UseContainerItem`, `PickupContainerItem` | 9 / 11 / 4 / 5 / 2 | `C_Container.GetContainerNumSlots`, `C_Container.GetContainerItemInfo` (a table: `.quality`, `.hasNoValue`, `.hyperlink`, `.itemID`), `C_Container.UseContainerItem`, `C_Container.PickupContainerItem` | Greys are `quality == 0` (no colour-code matching) |
| `GetItemInfo` | 15 | `C_Item.GetItemInfo`, `C_Item.GetItemInfoInstant`, `C_Item.GetItemNameByID` | |
| `GetFactionInfo(i)`, `GetNumFactions`, `ExpandFactionHeader` | 7 / – / 2 | `C_Reputation.GetNumFactions`, `C_Reputation.GetFactionDataByIndex(i)` / `GetFactionDataByID(id)` (`.factionID`, `.name`, `.reaction`, `.currentStanding`, `.currentReactionThreshold`, `.nextReactionThreshold`, `.isHeader`), event `FACTION_STANDING_CHANGED(factionID, updatedStanding)` | |
| `CHAT_MSG_COMBAT_FACTION_CHANGE` parsing `FACTION_STANDING_INCREASED` | — | unchanged. Its text can be secret in chat-messaging lockdown, so it's guarded. | |
| `SendChatMessage` | 3 | `C_ChatInfo.SendChatMessage` (the global is a deprecated wrapper) | Restricted in some contexts, so wrapped in `pcall` |
| `GetNumPartyMembers`, `GetNumRaidMembers` | 5 / 6 | `IsInGroup()`, `IsInRaid()`, `GetNumGroupMembers()` | |
| `UnitRaceBase` (Turtle) | 4 | `select(2, UnitRace("player"))` | |
| `GetSkillLineInfo`, `GetSpellName` | 6 / 4 | not needed until profession guides. Forever has `C_SpellBook` and its own `SkillsFrame` (camelot). | |
| `GetTalentInfo` etc. | 4 | Forever's own talent UI. Not ported. | |
| `NumTaxiNodes`, `TakeTaxiNode` | 1 / 1 | unchanged globals (`C_TaxiMap` for node info) | For FLY steps, when guides come |
| `CreateMacro` / `C_Macro.*` | 4 | `CreateMacro`, `EditMacro` (protected in combat) | For the Macros window, when guides come |
| `SetRaidTarget` | 4 | unchanged | |
| Interface Options panel | — | `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory` | A page under AddOns that opens our window |
| `UIDropDownMenu` (not used, the theme draws its own) | 0 | — | |
| AceLibrary / AceDB-2.0 / AceConsole-2.0 / AceEvent-2.0 / AceHook-2.1 | — | plain saved variables, `SlashCmdList`, one event frame (`AP:On`) | Ace2 is a 1.12 library |

## What the client gives, and what the collector has to observe

| Data | From the client? | How the collector gets it |
|---|---|---|
| XP needed per level | **Yes** | `UnitXPMax("player")` on start, `PLAYER_XP_UPDATE` and `PLAYER_LEVEL_UP` (+1 s, since `UnitXPMax` updates late) |
| XP a quest gives | **Yes**, at turn-in | `QUEST_TURNED_IN(questID, xpReward, moneyReward)`. Also `GetRewardXP()` on the frames (offered), and the XP bar's own movement as a check |
| Money a quest gives | **Yes** | `moneyReward`, and `GetRewardMoney()` |
| Reward items, choices, spells, currencies | **Yes**, on the quest frame | `GetQuestItemLink`/`GetQuestItemInfo("choice"\|"reward", i)`, `C_QuestInfoSystem` |
| The choice the player made | No | `hooksecurefunc("GetQuestReward")` |
| Reputation a quest gives | **No** (classic factions aren't on the frame) | **Observed** within 3 s of the turn-in: `FACTION_STANDING_CHANGED` (by faction id, against the last value read) and the `CHAT_MSG_COMBAT_FACTION_CHANGE` line (by name), counted once |
| Who gives a quest, where | **No** API for it | **Observed** on `QUEST_DETAIL`: `UnitGUID("npc")` (creature or object id), `UnitName("npc")`, the player's map and x/y. `questStartItemID` for item-started quests |
| Quests available on a map | **Partly** | `C_QuestLine.RequestQuestLinesForMap` / `GetAvailableQuestLines(uiMapID)`: the world map's "!" pins, with x/y, where the client provides them |
| Where objectives are done | **Partly** | The client's own POIs for quests in the log: `C_QuestLog.GetQuestsOnMap(uiMapID)` (objective area, or turn-in once ready). Plus **observed**: the player's position each time an objective's count goes up |
| Who takes a quest back, where | **No** API until it's in the log and ready (then a POI) | **Observed** on `QUEST_COMPLETE`: the NPC, map and x/y, plus the client POI once ready |
| Quest level, group size, tag | **Yes** | `C_QuestLog.GetInfo`, `GetQuestDifficultyLevel`, `GetQuestTagInfo` |
| Quest chains | **No** | **Observed:** a quest offered by the same NPC within 10 s of a turn-in follows it |
| Time per level | No (`RequestTimePlayed` prints to chat) | **Observed:** session time at the level, kept only when the whole level was seen |

## Still to confirm in a live Forever client

The port is written against the 1.60.1 interface code and tested against a
mock client (`Tools/smoke_test.py`). These need a real session:

1. Whether **Forever's quest POIs** (`C_QuestLog.GetQuestsOnMap`) and
   **available quest lines** (`C_QuestLine.GetAvailableQuestLines`) are filled
   in for classic zones. Retail fills them. The collector records them only
   when they are.
2. The payload of **`FACTION_STANDING_CHANGED`**: the collector doesn't
   trust `updatedStanding` and re-reads `C_Reputation.GetFactionDataByID`
   instead. Confirm that the reputation gain is caught once.
3. **`UnitGUID("npc")` for object quest givers** (wanted posters, chests):
   the collector reads the guid without asking `UnitExists("npc")`.
4. **TGA textures and TTF fonts** load from `media/` as in the Instance
   Journal (same format, RLE 32-bit).
5. The **Blizzard skin's art paths** (`DialogFrame\UI-DialogBox-*`,
   `Buttons\UI-CheckBox-*`, `Buttons\UI-SliderBar-*`,
   `Buttons\UI-ScrollBar-Knob`, `Minimap\MiniMap-TrackingBorder`) are all
   referenced by Forever's own interface code, but should be looked at in game.
6. **`C_ChatInfo.SendChatMessage(…, "EMOTE")`** for the level-up emote is
   allowed outside a hardware event.
7. Whether **secret values** turn up in the quest frame inside Forever's
   dungeons. Everything is guarded, so a secret value shows up as a missing
   field, not an error.
