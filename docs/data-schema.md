# Data schema: what the collector writes

The collector keeps one table, merged by quest and by level instead of as an
event stream, in the account-wide saved variable:

```
AegisPathfinderDB.collect      -- schemaVersion 1
```

It lives in `WTF/Account/<ACCOUNT>/SavedVariables/Aegis_Forever_Pathfinder.lua`
and reaches that file at logout or `/reload`.

**Submit data** (the data collection window, or `/apg submit`) sends it
wrapped in an **envelope**, format 2:

```json
{ "format": 2, "addon": "Aegis_Forever_Pathfinder", "addonVersion": "0.2.0",
  "build": "1.60.1.70338", "interface": 16001, "exportedAt": 1760000000,
  "contributor": "Brandy", "data": { ...the table below, without its log... } }
```

The Submit window shows it in one of two forms:

- **The share code**: `APF1:` and then the envelope's JSON, zlib-compressed by
  the client's `C_EncodingUtil` and written in Base64. It is one line, and
  several times smaller than the text.
- **The plain export** ("As text", and the fallback on a client without
  `C_EncodingUtil`): one header line, then the envelope as JSON.

```
AEGIS PATHFINDER FOREVER DATA;2;<addon version>;<client version.build>;<interface>;<UTC time>;<contributor>
{ ...the envelope as JSON, keys sorted... }
```

Format 1, from 0.1.0, had a shorter header (no contributor) followed by the
data table itself, with no envelope. `Tools/ingest.py` still reads it.

JSON turns every table key into a string, so quest ids and levels appear as
`"176"`, `"5"`. `Tools/ingest.py` reads every form (codes, text, the saved
variables file, zipped or not) and `Tools/merge_exports.py` merges them. See
[data-submission.md](data-submission.md).

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
| `id` | string | — | A random id for this collection, kept until it is cleared. Data sent again under the same id replaces the copy sent before, so nothing is counted twice |
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
| `description` | string | frame | `GetQuestText()` on the offer. In every quest text the player's name, which the game writes into some of them, is `<name>`: the collector replaces it (0.2.4 on; saved text is cleaned at login and before sending), and the intake replaces the credit name and its first word for older clients |
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
| `chain` | `{ prev = { [questID] = true }, next = { [questID] = true } }` | observed | Offered by the same NPC within 10 s of handing in another. Not linked when two or more were handed in to that NPC in that time (from 0.4.1) |
| `rewards` | Rewards | | What it gave |
| `builds`, `by`, `first`, `last` | | | Stamps |

### Place (a pickup or a turn-in)

Keyed `"<kind>:<id or name>@<uiMapID>"`, e.g. `"npc:240@1429"`,
`"item:1972@1429"`, `"object:31@1426"`, `"auto:?@1429"`, `"shared:?@1429"`.

| Field | Type | Source | Meaning |
|---|---|---|---|
| `kind` | string | observed | `npc`, `object` (a game object: poster, chest), `item` (started from an item in your bags), `shared` (a party member shared it: where you stood, and never who they were), `auto` (no frame: auto-accepted or auto-completed), `unknown` |
| `id` | number | client | Creature or object id from `UnitGUID("npc")`, or the item id from `QUEST_DETAIL`'s `questStartItemID` |
| `name` | string | client | `UnitName("npc")`, or the item's name; never kept for `shared` |
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
| `xpObserved` | `{ [playerLevel] = Range }` | observed | How far the XP bar moved, across a level-up if there was one, read 1 s after the turn-in or as the next reward frame opens, if sooner. A check on `xp` |
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

Nothing leaves the game by itself: the addon has no way to send anything, and
the data stays in the saved variables until the player submits it. Characters
are recorded as race, class and faction. What is sent leaves out the realm
and the window's activity log. **The one name in it is the contributor's**:
the "Credit me as" name the player chose in the Submit window, or, left
empty, the character's name, so that the contributors list can thank them.
It is printed in the game (Submit window, About page) and in `CONTRIBUTORS.md`.
