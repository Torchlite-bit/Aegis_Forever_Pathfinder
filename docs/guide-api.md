# Writing guides for Pathfinder on Forever

The seam guides plug into (`Core/Guides.lua`). The first one,
`Guides/Northshire.lua` (a short test guide), was written from collected data.

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
an unknown action, an unknown class or race). A guide file should report a
refusal (`if not ok then geterrorhandler()(why) end`): a refused guide is
otherwise just missing. The smoke test checks every shipped guide registers.

## Steps

| Field | Meaning |
|---|---|
| `action` | One of the 1.12 addon's: `ACCEPT`, `COMPLETE`, `TURNIN`, `RUN`, `MAP`, `KILL`, `GRIND`, `USE`, `BUY`, `NOTE`, `HEARTH`, `SETHEARTH`, `FLY`, `GETFLIGHTPOINT`, `BOAT`, `TRAIN`, `DIE`, `PET` |
| `qid` | The quest id. `ACCEPT`, `COMPLETE` and `TURNIN` steps with one tick themselves |
| `title` | What the step row shows |
| `note` | The line under it, in full in focus mode (under the band, for a current ACCEPT or TURNIN); on hover in the list |
| `map`, `x`, `y` | A uiMapID and 0–1 coordinates: where Pathfinder's arrow points, and the game's own map pin and arrow, set once as the step comes up |
| `class` | Optional. Only these classes see the step: a list of `UnitClass`'s second return (`WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`, `WARLOCK`, `DRUID`) |
| `unverified` | Optional. `true` on a step not confirmed by the collected data yet (written from another source, like the other classes' letters from the Turtle guide). The smoke test only warns when the data disagrees with it |
| `race` | Optional. Only these races see the step: `UnitRace`'s second return (`Human`, `Dwarf`, `NightElf`, `Gnome`, `Orc`, `Scourge`, `Tauren`, `Troll`). With both, both must match |

A step for another class or race is left out for that character everywhere: the
current step, the list, the counts, the arrows and `/apg next`/`/apg prev`.
Progress stays keyed by the step's index in the guide, so inserting steps in a
later version shifts hand-ticked marks (quest steps tick again from the client).

How steps tick:

- `ACCEPT`: when the quest is in the log (`QUEST_ACCEPTED`, `C_QuestLog.IsOnQuest`)
- `COMPLETE`: when `C_QuestLog.ReadyForTurnIn` or `IsComplete`
- `TURNIN`: on `QUEST_TURNED_IN`, or `C_QuestLog.IsQuestFlaggedCompleted`
- anything else: by hand (the step's ring, the → on the nav row, `/apg next`).
  A current ACCEPT or TURNIN shows as a band without a ring: its fallback is the →.

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
export into these tables. Until then a guide is written by hand from the data, as
Northshire was. `Tools/smoke_test.py` checks every shipped quest step against
`data/merged.json`: the id and title are in the data, and an ACCEPT or TURNIN
stands within 0.03 of where the data saw that quest picked up or handed in. A
quest the data hasn't seen is allowed only on an `unverified` step, and the data
disagreeing with an `unverified` step is a warning, not a failure: new data
(merged on `main` by the intake's pull request) must never stop a release. A
disagreement on any other step fails the tests, and with them the release, until
the guide is fixed. The run prints how many steps the data confirms.
