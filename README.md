# Aegis: Pathfinder — Forever (v0.2.0)

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
Night, Pathfinder (the original green), OctoWoW, RavenCraft, Capybara Paradise, Aegis).

**A Blizzard skin.** One more theme, **Blizzard**, draws the same windows the
way today's game draws its own, like its Options window: the smooth metal
frame with a solid dark background (nothing shows through), the red close
button, Blizzard's red buttons, the slim check boxes, sliders, scroll bars and
drop-downs, gold Friz Quadrata labels, the Options list highlight and section
rules, and the game's tooltip. Pick it under *Settings → Appearance → Theme*.
Switching to or from it reloads the interface.

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
The addon sends nothing by itself: it stays in your saved variables until you
press **Submit data**.

**The data collection window** (the ● chip on the guide, shift-click the
minimap button, or `/apg collect`):

- **Start / Stop collecting data**
- ☑ **Automatically run**: starts collecting at every login on this
  character. New characters take the last choice you made.
- What it has so far, and the last things it wrote down
- **Submit data**: packs it to send to us (below)
- **Clear data**

The guide window has the **Automatically run** box too, while it has no
guide.

What every field means: [docs/data-schema.md](docs/data-schema.md).

### Sending us your data

Addons can't reach the internet or write files, so the game can't send it for
you, but it's two keystrokes. **Submit data** opens a window with:

- **A share code**: everything you collected, compressed into one line
  (`APF1:…`) and already selected. Press **Ctrl+C**.
- **Where to paste it**, as links to copy:
  - **[The GitHub form](https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever/issues/new?template=submit-data.yml)**:
    paste the code and submit. A GitHub Action reads it, adds it to the
    collected data and credits you, with no one copying anything by hand.
    It answers on the issue when it's done.
  - **[Our Discord](https://discord.gg/Hr66t25vE7)**: paste it there. A long
    paste turns into a text file by itself, and that's fine.
- **Credit me as**: the name for the contributors list (empty: your
  character's name in the code; the file carries only a name you typed).
- **Or the file**: everything is also in
  `WTF/Account/<account>/SavedVariables/Aegis_Forever_Pathfinder.lua` after a
  `/reload` (the window has a button). Drop it in Discord, or rename it to
  `.txt` (or zip it) and drag it into the GitHub form. That's the way for
  very large collections, which don't fit in an issue as a code.

Send again whenever you like, without clearing: each collection has an id,
and a newer copy replaces the older one instead of counting twice.
**As text** shows exactly what goes out. Everyone who sends data is listed in
the Submit window, on the *About* page and in
[CONTRIBUTORS.md](CONTRIBUTORS.md). How the intake works:
[docs/data-submission.md](docs/data-submission.md).

### Also working without guides

- **Automation**: accept and hand in quests, on by default as in the Turtle
  addon (all of them, since no guide says which are "its"; never a grey quest
  and never a reward choice), pick quests from an NPC's list, selling greys
  (with the game's own *Sell All Junk*, or a *Sell greys* button where the
  vendor has none), repairing (your money, or the guild's first). Hold Shift
  to suspend. These are per character: *Settings → Automation*.
- **Extras**: detailed reputation gains ("Stormwind +25: Honored 4,350 /
  12,000, 7,650 to Revered"), and level-up announcements to emote, party or
  guild: a card with a button for each, since the game lets addons post in
  chat only when you click.
- **Window settings**: lock, transparency, opacity, step text size, window
  scale, hiding in dungeons or combat.

What came over from the Turtle addon, and what didn't and why:
[docs/feature-inventory.md](docs/feature-inventory.md).

---

## Install

1. Download **`Aegis_Forever_Pathfinder-v<version>.zip`** from
   [the latest release](https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever/releases/latest),
   not *Source code*.
2. Put the folder in `World of Warcraft/_classic_beta_/Interface/AddOns/` (the
   Forever client's AddOns folder). It must be named exactly
   **`Aegis_Forever_Pathfinder`**: the addon's name, not the repository's. The
   release file's folder already is. *Source code* and the repository's own
   ZIP unpack as `Aegis_Pathfinder_Forever-<version>` or `-main`, and the addon
   won't load until you rename the folder.
3. **Restart the client fully** the first time (a `/reload` isn't enough for
   new files).

## Using it

| Command | |
|---|---|
| `/apg` (or `/pathfinder`) | Show or hide the guide window |
| `/apg collect` | The data collection window |
| `/apg start`, `/apg stop` | Start or stop collecting |
| `/apg status` | What has been collected so far |
| `/apg submit` (or `/apg export`) | The Submit data window |
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
Collector/Export.lua           what is sent: the envelope, the share code, the credit name
Contributors.lua               the contributors list (generated by Tools/ingest.py)
UI/*.lua                       the guide window, data collection, guide browser, options, minimap
Features/*.lua                 automation and chat extras
media/                         the generated art and the Rajdhani and Inter fonts
Tools/smoke_test.py            loads the addon against a mock client and plays it through
Tools/ingest.py                reads submissions (codes, text, files), merges them, credits contributors
Tools/ingest_issue.py          the GitHub Action's side of ingest.py
Tools/savedvariables.py        reads a SavedVariables file as data, never running it
Tools/merge_exports.py         merges codes, exports and data files into one file, storing nothing
.github/                       the Submit data issue form and the Action that ingests it
data/                          what players sent, and everything merged
docs/                          feature inventory, API migration, data schema, guide API, CurseForge
Tools/package.py               builds the release zip; Tools/curseforge_upload.py uploads it
```

```sh
pip install lupa
python Tools/smoke_test.py          # once per skin, and on a client without the modern art
python Tools/test_ingest.py         # the intake: decoding, cleaning, merging, credits
python Tools/ingest.py file.lua --credit Name   # add a file sent on Discord
python Tools/merge_exports.py code.txt Aegis_Forever_Pathfinder.lua -o merged.json
```

The API this is written against, and what still needs checking in a live
client: [docs/api-migration.md](docs/api-migration.md).

**Releases are automatic**, as for the Instance Journal. Every merge to `main`
publishes a GitHub release named after the `.toc` version, with the addon zip
and that version's changelog entry; a merge that keeps the version refreshes
that release's zip. Each new version also goes to CurseForge, once: bump the
version for CurseForge to get a new file. Setup and the project page's text:
[docs/curseforge.md](docs/curseforge.md).

## Credits

**The players who send their data** are listed in
[CONTRIBUTORS.md](CONTRIBUTORS.md) and in the game.

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
