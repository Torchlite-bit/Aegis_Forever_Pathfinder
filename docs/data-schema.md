# Data schema: what the collector writes

The collector keeps one table, merged by quest and by level instead of as an
event stream, in the account-wide saved variable:

```
AegisPathfinderDB.collect      -- schemaVersion 1
```

It lives in `WTF/Account/<ACCOUNT>/SavedVariables/Aegis_Forever_Pathfinder.lua`
and reaches that file at logout or `/reload`. **Export** (the data collection
window, or `/apg export`) gives the same data as text:

```
AEGIS PATHFINDER FOREVER DATA;<format>;<addon version>;<client version.build>;<interface>;<UTC time>
{ ...the table below as JSON, keys sorted... }
```

JSON turns every table key into a string, so quest ids and levels appear as
`"176"`, `"5"`. `Tools/merge_exports.py` merges many exports into one file.

**Source key** (in the tables below)

- **client**: the client says it directly (an API return or an event payload).
- **observed**: the collector works it out from what happened (where the
  player stood, what changed just after).
- **frame**: read off a quest frame while it's open (also client data, but
  only when the player opens that frame).

## Top level

| Field | Type | Source | Meaning |
|---|---|---|---|
| `schemaVersion` | number | — | `1`. Future versions migrate older data in `Collector:Init` |
| `created` | number | client | `GetServerTime()` when the table was first made, or last cleared |
| `builds` | `{ [build] = true }` | client | Every client build that wrote to it, e.g. `"1.60.1.70338"` (`GetBuildInfo`) |
| `observers` | `{ ["Race:CLASS:Faction"] = count }` | client | Who collected, and how many sessions. **Never a character's name** |
| `levels` | `{ [level] = Level }` | | One entry per player level |
| `quests` | `{ [questID] = Quest }` | | One entry per quest id |
| `log` | list of strings | — | The window's recent activity. **Left out of the export** |

## Stamps (on every Level and Quest)

| Field | Type | Meaning |
|---|---|---|
| `builds` | `{ [build] = true }` | Client builds that saw it |
| `by` | `{ ["Race:CLASS:Faction"] = count }` | Who saw it, and how often |
| `first`, `last` | number | `GetServerTime()` of the first and latest sighting |

## Ranges

A number seen more than once keeps all of it as a **Range**:

| Field | Meaning |
|---|---|
| `min`, `max` | Lowest and highest seen |
| `count` | How many times |
| `last` | The latest |

## Level

| Field | Type | Source | Meaning |
|---|---|---|---|
| `xpMax` | Range | client | `UnitXPMax("player")` at this level: the XP it takes to reach the next. A range wider than one value means characters disagreed (worth a look) |
| `seconds` | Range | observed | Time played at the level, **only from characters whose collector saw the whole level** (from the level-up into it to the level-up out of it, while collecting) |

## Quest

| Field | Type | Source | Meaning |
|---|---|---|---|
| `title` | string | frame / client | `GetTitleText()`, else `C_QuestLog.GetTitleForQuestID` |
| `description` | string | frame | `GetQuestText()` on the offer |
| `objectiveText` | string | frame | `GetObjectiveText()` on the offer |
| `progressText` | string | frame | `GetProgressText()`: what the NPC says before you hand in |
| `completionText` | string | frame | `GetRewardText()` on the reward frame |
| `level` | number | client | `C_QuestLog.GetQuestDifficultyLevel` / `GetInfo().level` |
| `suggestedGroup` | number | client | Suggested group size, when there is one |
| `frequency` | number | client | 0 normal, 1 daily, 2 weekly (`Enum.QuestFrequency`) |
| `tag`, `tagID` | string, number | client | `C_QuestLog.GetQuestTagInfo` (Elite, Dungeon, …) |
| `requiredMoney` | number | client | Copper the quest takes to hand in |
| `questLine` | string | client | Quest-line name, from the map's available-quest pins |
| `seen` | `{ offered, accepted, turnedIn, abandoned = count }` | observed | How often each happened |
| `pickups` | `{ [key] = Place }` | observed | Who or what gave it, and where. See **Place** |
| `turnins` | `{ [key] = Place }` | observed | Who took it back, and where |
| `objectives` | list of `{ text, type, required }` | client | `C_QuestLog.GetQuestObjectives`: `text` without its count ("Hogger slain"), `type` (`monster`, `item`, `object`, `event`, …), `required` |
| `progress` | `{ [objectiveIndex] = Cells }` | observed | Where the player stood each time that objective's count went up |
| `poi` | `{ objective = Cells, turnin = Cells, available = Cells }` | client | The client's own map points: `C_QuestLog.GetQuestsOnMap` for quests in the log (`objective` while in progress, `turnin` once ready), and `C_QuestLine.GetAvailableQuestLines` (`available`: the "!" pickup pins) |
| `chain` | `{ prev = { [questID] = true }, next = { [questID] = true } }` | observed | Offered by the same NPC within 10 s of handing in another |
| `rewards` | Rewards | | What it gave |
| `builds`, `by`, `first`, `last` | | | Stamps |

### Place (a pickup or a turn-in)

Keyed `"<kind>:<id or name>@<uiMapID>"`, e.g. `"npc:240@1429"`,
`"item:1972@1429"`, `"object:31@1426"`, `"auto:?@1429"`.

| Field | Type | Source | Meaning |
|---|---|---|---|
| `kind` | string | observed | `npc`, `object` (a game object: poster, chest), `item` (started from an item in your bags), `auto` (no frame: shared, auto-accepted, or auto-completed), `unknown` |
| `id` | number | client | Creature or object id from `UnitGUID("npc")`, or the item id from `QUEST_DETAIL`'s `questStartItemID` |
| `name` | string | client | `UnitName("npc")`, or the item's name |
| `mapID` | number | client | `C_Map.GetBestMapForUnit("player")`: a uiMapID |
| `zone`, `subzone` | string | client | `GetRealZoneText()`, `GetSubZoneText()` |
| `x`, `y` | number | observed | Running mean of the player's position (0–1, four places) |
| `xMin`, `xMax`, `yMin`, `yMax` | number | observed | The extremes of those positions |
| `xyCount` | number | observed | Positions averaged (none inside dungeons, where Forever gives no position) |
| `count` | number | observed | Sightings |
| `playerLevel` | Range | client | The player's level when it happened |

### Cells (map points)

`{ ["<uiMapID>:<x%>:<y%>"] = count }`: positions merged onto a 1% grid,
e.g. `"1429:26:77"` is 26% across and 77% down Elwynn Forest (uiMapID 1429).
At most 40 cells per list.

### Rewards

| Field | Type | Source | Meaning |
|---|---|---|---|
| `xp` | `{ [playerLevel] = Range }` | client | **The XP the turn-in gave**, from `QUEST_TURNED_IN`'s `xpReward`, by the player's level at the time (quest XP falls off as you outlevel a quest) |
| `xpOffered` | `{ [playerLevel] = number }` | frame | `GetRewardXP()` on the offer and reward frames |
| `xpObserved` | `{ [playerLevel] = Range }` | observed | How far the XP bar moved, across a level-up if there was one. A check on `xp` |
| `money` | Range | client | Copper from `QUEST_TURNED_IN`'s `moneyReward` |
| `moneyOffered` | number | frame | `GetRewardMoney()` |
| `choices` | `{ [itemID] = { name, count } }` | frame | Items to choose one of |
| `items` | `{ [itemID] = { name, count } }` | frame | Items always given |
| `chosen` | `{ [CLASS] = { [itemID] = count } }` | observed | Which choice each class took (`GetQuestReward` hook) |
| `spells` | `{ [spellID] = name }` | frame | `C_QuestInfoSystem.GetQuestRewardSpells` |
| `currencies` | `{ [currencyID] = { name, amount } }` | frame | `C_QuestInfoSystem.GetQuestRewardCurrencies` |
| `reputation` | `{ [faction name] = Range + factionID }` | observed | Gains within 3 s of the turn-in, from `FACTION_STANDING_CHANGED` (by id, against the last value read) and the "Reputation with X increased by N." chat line, counted once |
| `title`, `skillPoints`, `honor` | | frame | When a quest gives them |

## Example

One quest, offered and handed in once at level 5:

```json
{
  "176": {
    "title": "Wanted: Hogger", "level": 11,
    "objectiveText": "Kill Hogger.",
    "objectives": [ { "text": "Hogger slain", "type": "monster", "required": 1 } ],
    "pickups": { "npc:240@1429": { "kind": "npc", "id": 240, "name": "Marshal Dughan", "mapID": 1429,
      "x": 0.4215, "y": 0.659, "count": 1, "playerLevel": { "min": 5, "max": 5, "count": 1, "last": 5 } } },
    "turnins": { "npc:240@1429": { "kind": "npc", "id": 240, "name": "Marshal Dughan", "mapID": 1429,
      "x": 0.4221, "y": 0.6588, "count": 1 } },
    "progress": { "1": { "1429:26:77": 1 } },
    "poi": { "turnin": { "1429:42:66": 1 } },
    "rewards": {
      "xp": { "5": { "min": 1450, "max": 1450, "count": 1, "last": 1450 } },
      "money": { "min": 500, "max": 500, "count": 1, "last": 500 },
      "choices": { "2224": { "name": "Militia Dagger", "count": 1 } },
      "reputation": { "Stormwind": { "factionID": 72, "min": 250, "max": 250, "count": 1, "last": 250 } }
    },
    "seen": { "offered": 1, "accepted": 1, "turnedIn": 1 },
    "by": { "Human:WARRIOR:Alliance": 3 }
  }
}
```

## Privacy

Nothing leaves the game by itself: the data stays in the saved variables
until the player exports it and chooses to share it. Characters are recorded
as race, class and faction. The export doesn't contain the character's
name, the realm, or the window's activity log.
