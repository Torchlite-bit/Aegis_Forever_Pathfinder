# Writing guides for Pathfinder on Forever

The seam guides plug into (`Core/Guides.lua`). The first one,
`Guides/Northshire.lua` (a short test guide), was written from collected data.

## Registering a guide

A guide is a Lua file listed in the `.toc` after `Core\Guides.lua` (put guides
under `Guides\`). It calls `AegisPathfinder:RegisterGuide` once:

```lua
AegisPathfinder:RegisterGuide({
    name = "Elwynn Forest (1-10)",   -- unique; shown on the tab and in the browser
    category = "leveling",           -- leveling | dungeons | class | professions | collections
    faction = "Alliance",            -- Alliance | Horde | Both
    minLevel = 1, maxLevel = 10,
    next = "Westfall (10-20)",       -- offered when this one ends
    chain = true,                    -- optional: a quest chain (see below)
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

`chain = true` marks a quest chain, done in order (the Cozy Sleeping Bag). In a
chain, a quest step done (as you play, ticked by hand, or found done when the
guide opens) also ticks every step with no quest before it: a player partway
through opens the guide where they are, and a note or a hearth they skipped
doesn't hold the guide back. Quest steps keep the client's word. A trip you step
back to by hand isn't ticked again while you stand at its place; once you've
left, the next quest done (or a reload) ticks it again. Leave it off a leveling
guide: there a quest done out of order mustn't tick the steps before it.

## Steps

| Field | Meaning |
|---|---|
| `action` | One of the 1.12 addon's: `ACCEPT`, `COMPLETE`, `TURNIN`, `RUN`, `MAP`, `KILL`, `GRIND`, `USE`, `BUY`, `NOTE`, `HEARTH`, `SETHEARTH`, `FLY`, `GETFLIGHTPOINT`, `BOAT`, `TRAIN`, `DIE`, `PET`; and `LOOT` (pick something up: with `item`) |
| `qid` | The quest id. `ACCEPT`, `COMPLETE` and `TURNIN` steps with one tick themselves |
| `title` | What the step row shows |
| `note` | The line under it, in full in focus mode (under the band, for a current ACCEPT or TURNIN); on hover in the list |
| `map`, `x`, `y` | A uiMapID and 0–1 coordinates: where Pathfinder's arrow points, and the game's own map pin and arrow, set once as the step comes up |
| `class` | Optional. Only these classes see the step: a list of `UnitClass`'s second return (`WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`, `WARLOCK`, `DRUID`) |
| `unverified` | Optional. `true` on a step not confirmed by the collected data yet (written from another source, like the other classes' letters from the Turtle guide). The smoke test only warns when the data disagrees with it |
| `together` | Optional. `true`: done with the step before it, in the same area. A run of them is one block: in focus mode every step of it shows, each ticking itself (not on step 1) |
| `fromitem` | Optional, on an ACCEPT. `true`: the quest starts from a looted item. The step ticks once a bag item that starts this quest is held (`C_Container.GetContainerItemQuestInfo`), so the item's name or id needn't be known. Quest automation opens such an item by itself |
| `item` | Optional. The step ticks once an item of this exact name is in the bags (a LOOT step: a library book) |
| `node` | GETFLIGHTPOINT: the flight master's id (`/apg flights` saves them all). The step ticks once the client says you know it |
| `race` | Optional. Only these races see the step: `UnitRace`'s second return (`Human`, `Dwarf`, `NightElf`, `Gnome`, `Orc`, `Scourge`, `Tauren`, `Troll`). With both, both must match |

A step for another class or race is left out for that character everywhere: the
current step, the list, the counts, the arrows and `/apg next`/`/apg prev`.
Progress stays keyed by the step's index in the guide, so inserting steps in a
later version shifts hand-ticked marks (quest steps tick again from the client).

How steps tick:

- `ACCEPT`: when the quest is in the log (`QUEST_ACCEPTED`, `C_QuestLog.IsOnQuest`)
- `COMPLETE`: when `C_QuestLog.ReadyForTurnIn` or `IsComplete`
- `TURNIN`: on `QUEST_TURNED_IN`, or `C_QuestLog.IsQuestFlaggedCompleted`
- `LOOT` (with `item`): once an item of that name is in the bags
- `GETFLIGHTPOINT` (with `node`): once you know that flight point. Forever's client calls every node
  "discovered", so the flight points a flight master's map lists are saved per character as it opens
- `RUN`, `FLY`, `BOAT`, `HEARTH`, `MAP`: once you're within 40 yards of its place, or once the step of
  yours right after it is done as you play (not at load; a quest handed in counts, from 0.7.0; a flight
  point only when you learn it at its own flight master, since every flight master's map lists all the
  ones you know). Stepping back to a trip by hand doesn't tick it again until you've left its place
- anything else: by hand (the step's ring, the → on the nav row, `/apg next`).
  A current ACCEPT or TURNIN shows as a band without a ring: its fallback is the →.
  (In a block of steps done together there are no bands: every step has its ring.)

In focus mode, a COMPLETE step (the current one, or any in the current block) shows
its quest's live progress under it: a box with a line per counted objective, its
name, "3 / 10" and a bar, from `C_QuestLog.GetQuestObjectives`. In the list, its
line reads "Kobold Vermin slain - 3/10".

## Kill areas

A block with a COMPLETE, KILL or GRIND step is an area. Once you are within 60
yards of the step's place, the game's pin and Pathfinder's arrow stop marking it
(a pin the player set is left alone), and that is saved per character. A later
step of the block more than 100 yards from where you arrived is marked again,
until you reach it. Group steps with `together` only when they really are done
in one area: a single spot a little way off (a tent, a boss's shack) more than
100 yards away is marked on its own, nearer than that it isn't.

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
