# Aegis: Pathfinder — Forever (v0.1.0)

**The Pathfinder leveling guide, ported to WoW: Forever. No guides yet, so for
now it collects the data to write them.**

[![WoW: Forever](https://img.shields.io/badge/WoW%3A%20Forever-Interface%2016001-c79c2e?style=flat-square&labelColor=555)](#install)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/Hr66t25vE7)

> Built for **WoW: Forever** (client 1.60.1, interface **16001**), which runs
> the modern engine. This is a port of [Aegis: Pathfinder](https://github.com/Torchlite-bit/Aegis_Pathfinder)
> for Turtle WoW (1.12), not that addon. The two clients share almost no API.

> ⚠️ **In development.** No guides yet. What works now: the guide window, the
> guide browser, the settings, and the **data collector**.

---

## What it is right now

**The Pathfinder look, on Forever.** The guide window, the ≡ menu, the guide
browser, the options window and the minimap button are the Turtle WoW
addon's, panel for panel: same layout, same fonts, same colour themes (Day,
Night, Pathfinder green, OctoWoW, RavenCraft, Capybara Paradise, Aegis).

**A Blizzard skin.** One more theme, **Blizzard**, draws the same windows with
the client's own art: dialog frames and title plate, Blizzard's red buttons and
check boxes, Friz Quadrata, gold headings and the game's tooltip. Pick it under
*Settings → Appearance → Theme*. Switching to or from it reloads the
interface.

**No guides yet.** WoW: Forever is new, so the guide window says so and offers
to **start collecting data** instead. The engine that follows guides is there
and waiting ([docs/guide-api.md](docs/guide-api.md)).

### The data collector

Switch it on and play normally. Pathfinder writes down:

- **The XP each level needs**, and how long each level took.
- **Every quest** you're offered, pick up and hand in:
  - its text, level and objectives
  - **who gave it and where**: NPC, object or item, the map, x/y, and your level
  - **where its objectives moved on** (where you stood as the count went up)
  - the client's own map pins for it
  - **who took it back and where**
  - **what it gave**: XP at your level, money, the items to choose from and
    the ones given (and which one your class picked), spells, currencies and
    **reputation**
  - which quest led to it

Repeat sightings are merged: counts add up, and the lowest and highest XP,
money and coordinates are kept. Each record is stamped with the client build
and the race, class and faction that saw it, **never your character's name**.
Nothing is sent anywhere. It stays in your saved variables until you export it.

**The data collection window** (the ● chip on the guide, shift-click the
minimap button, or `/apg collect`):

- **Start / Stop collecting data**
- ☑ **Automatically run**: starts collecting at every login on this
  character. New characters take the last choice you made.
- What it has so far, and the last things it wrote down
- **Export**: everything as text to copy. Paste it in the Discord or a GitHub
  issue.
- **Clear data**

What every field means: [docs/data-schema.md](docs/data-schema.md).

### Also working without guides

- **Automation**: accept and hand in quests (all of them, since no guide says
  which are "its"; never a grey quest and never a reward choice), pick quests
  from an NPC's list, a *Sell greys* button, selling greys, repairing (your
  money, or the guild's first). Hold Shift to suspend.
- **Extras**: detailed reputation gains ("Stormwind +25: Honored 4,350 /
  12,000, 7,650 to Revered"), and level-up announcements to emote, party or
  guild.
- **Window settings**: lock, transparency, opacity, step text size, window
  scale, hiding in dungeons or combat.

What came over from the Turtle addon, and what didn't and why:
[docs/feature-inventory.md](docs/feature-inventory.md).

---

## Install

1. Download the repository's ZIP (or a release).
2. Put the folder in `World of Warcraft/_classic_beta_/Interface/AddOns/` (the
   Forever client's AddOns folder) and **rename it to exactly
   `Aegis_Forever_Pathfinder`**. GitHub's ZIP unpacks as
   `Aegis_Forever_Pathfinder-main`, and the addon won't load under that name.
3. **Restart the client fully** the first time (a `/reload` isn't enough for
   new files).

## Using it

| Command | |
|---|---|
| `/apg` (or `/pathfinder`) | Show or hide the guide window |
| `/apg collect` | The data collection window |
| `/apg start`, `/apg stop` | Start or stop collecting |
| `/apg status` | What has been collected so far |
| `/apg export` | The export window |
| `/apg config` | Settings |
| `/apg browser` | The guide browser |
| `/apg next`, `/apg prev` | Step forward or back (with a guide) |
| `/apg resetpanels` | Put every window back where it opens |
| `/apg minimapbutton` | Show or hide the minimap button |

There's deliberately no `/aegis`: that's the Aegis Instance Journal's.
Both windows have key bindings under *Key Bindings → AddOns*. The settings
also have an entry in the game's own *Options → AddOns*.

**Minimap button:** click for the guide, right-click for settings, shift-click
for data collection, drag to move it.

## For developers

```
Aegis_Forever_Pathfinder.toc   Interface 16001
Locale.lua                     the words on screen
Core/Init.lua                  namespace, saved variables, events (AP:On), start-up
Core/Compat.lua                guarded client calls: secret values, map position, guids
Core/Theme.lua                 the look: tokens, themes, every widget, both skins
Core/Guides.lua                guide registration and the engine that follows one
Core/Startup.lua               slash commands and key bindings
Collector/Collector.lua        the data collector
Collector/Export.lua           the export (header line + JSON)
UI/*.lua                       the guide window, data collection, guide browser, options, minimap
Features/*.lua                 automation and chat extras
media/                         the generated art and the Rajdhani and Inter fonts
Tools/smoke_test.py            loads the addon against a mock client and plays it through
Tools/merge_exports.py         merges players' exports into one file
docs/                          feature inventory, API migration, data schema, guide API
```

```sh
pip install lupa
python Tools/smoke_test.py          # 200+ checks, once per skin
python Tools/merge_exports.py a.txt b.txt -o merged.json
```

The API this is written against, and what still needs checking in a live
client: [docs/api-migration.md](docs/api-migration.md).

## Credits

A port of **Aegis: Pathfinder** (Torchlite and its contributors), which
descends from **TourGuide** (Tekkub), **VanillaGuide** (isalcedo) and
**VanillaGuide-Plus** (NostalgiaGeek, Brues). What the **Aegis: Forever
Instance Journal** learned about this client (its compat layer, its recorder,
its mock-client tests) is built in here. Fonts: **Rajdhani** (Indian Type
Foundry) and **Inter** (Rasmus Andersson), both SIL Open Font License 1.1.

## License

See [LICENSE](LICENSE).

---

*Aegis: Pathfinder is part of the Aegis addon series. Good hunting.* ⚔️
