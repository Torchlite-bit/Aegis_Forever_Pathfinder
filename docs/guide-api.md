# Writing guides for Pathfinder on Forever

No guides ship yet. This page describes the seam they plug into
(`Core/Guides.lua`), so the first guide written from collected data works
without engine changes.

## Registering a guide

A guide is a Lua file listed in the `.toc` after `Core\Guides.lua` (put guides
under `Guides\`). It calls `AegisPathfinder:RegisterGuide` once:

```lua
AegisPathfinder:RegisterGuide({
    name = "Elwynn Forest (1-10)",   -- unique; shown on the tab and in the browser
    category = "leveling",           -- leveling | dungeons | class | professions
    faction = "Alliance",            -- Alliance | Horde | Both
    minLevel = 1, maxLevel = 10,
    next = "Westfall (10-20)",       -- offered when this one ends
    steps = {
        { action = "ACCEPT", qid = 176, title = "Wanted: Hogger", map = 1429, x = 0.4215, y = 0.6590,
          note = "Marshal Dughan, Goldshire." },
        { action = "COMPLETE", qid = 176, title = "Wanted: Hogger", map = 1429, x = 0.2581, y = 0.7712,
          note = "Hogger roams the camp south-west." },
        { action = "TURNIN", qid = 176, title = "Wanted: Hogger", map = 1429, x = 0.4215, y = 0.6590 },
        { action = "RUN", title = "Westfall", map = 1436, x = 0.5, y = 0.5 },
    },
})
```

`RegisterGuide` returns `true`, or `false` and the reason (no name, no steps,
an unknown action).

## Steps

| Field | Meaning |
|---|---|
| `action` | One of the 1.12 addon's: `ACCEPT`, `COMPLETE`, `TURNIN`, `RUN`, `MAP`, `KILL`, `GRIND`, `USE`, `BUY`, `NOTE`, `HEARTH`, `SETHEARTH`, `FLY`, `GETFLIGHTPOINT`, `BOAT`, `TRAIN`, `DIE`, `PET` |
| `qid` | The quest id. `ACCEPT`, `COMPLETE` and `TURNIN` steps with one tick themselves |
| `title` | What the step row shows |
| `note` | The line under it, in full in focus mode |
| `map`, `x`, `y` | A uiMapID and 0–1 coordinates: the step's map pin and arrow |

How steps tick:

- `ACCEPT`: when the quest is in the log (`QUEST_ACCEPTED`, `C_QuestLog.IsOnQuest`)
- `COMPLETE`: when `C_QuestLog.ReadyForTurnIn` or `IsComplete`
- `TURNIN`: on `QUEST_TURNED_IN`, or `C_QuestLog.IsQuestFlaggedCompleted`
- anything else: by hand (the step's ring, the → on the nav row, `/apg next`)

Progress is per character (`AegisPathfinderCharDB.progress`).

## From collected data to a guide

Every field a step needs is in the collected data (see
[data-schema.md](data-schema.md)):

| Step field | From |
|---|---|
| ACCEPT `map`/`x`/`y`, `note` (who) | `quests[id].pickups[*]`: the one with the highest `count` |
| COMPLETE `map`/`x`/`y` | `quests[id].progress[i]` (the busiest cells), or `poi.objective` |
| TURNIN `map`/`x`/`y` | `quests[id].turnins[*]`, or `poi.turnin` |
| Ordering by level | `quests[id].level`, `pickups[*].playerLevel`, `rewards.xp` |
| Chains (what to pick up after a hand-in) | `quests[id].chain.next` |
| Route length check | `levels[n].xpMax` against the sum of `rewards.xp[n].last` |

A converter (`Tools/build_guide.py`, still to write) can turn a merged
export into these tables.
