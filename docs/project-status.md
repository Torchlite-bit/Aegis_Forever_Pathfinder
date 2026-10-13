# Where Pathfinder (Forever) stands

Handoff notes from the cloud session of 2026-10-13, for whoever works on this
next. Read this first, then the Launch Kit (`docs/launch-kit.html`, open it in a
browser; published copy at https://claude.ai/artifact/YLXpspLGznx9qMU5cFzMhq).

## What we're building

- **The addon:** a port of *Aegis: Pathfinder* (Turtle WoW, 1.12) to
  **WoW: Forever** (client 1.60.1, `## Interface 16001`, Lua 5.1, the modern
  Mainline engine). The same windows, settings and features, but **no guides
  yet**: Forever is new, so the addon **collects quest and level data** that
  the guides will be written from.
- **Two looks:** the Pathfinder themes (Pathfinder Day, Night, Green, Purple,
  Grey, Tan, Red), and **Default**, the same windows in Blizzard's modern art.
- **Getting data in:** players press *Submit data* (`/apg submit`) and paste a
  one-line share code (`APF1:` + Base64 of zlib JSON) into the GitHub issue
  form, or into Discord, or send their SavedVariables file. A GitHub Action
  reads it onto the `data-submissions` branch and opens a pull request;
  contributors are credited in game and in `CONTRIBUTORS.md`.
- **Shipping:** every merge to `main` publishes the GitHub release for the
  TOC's version; a new version is also uploaded to CurseForge, once. The same
  setup as the Aegis Forever Instance Journal.
- **Community:** testers through the Discord; a plan to cut the Discord from
  ~57 channels to 13 (in the Launch Kit).

## Shipped (on `main`)

| PR | What |
|---|---|
| #1 | The Forever port, with the data collector |
| #3 | **0.2.0**: Submit data and share codes, the GitHub intake (issue form + `ingest-data.yml`), contributors, the modern solid Default skin, quest automation on by default, Sell All Junk, the level-up card, the Escape taint fix, releases and the CurseForge pipeline |
| #4 | The first player data (issue #2: 34 quests, 6 levels, credited "Genesys Firstborn") |
| #5 | Repository renamed to **Aegis_Pathfinder_Forever**; the CurseForge description with badges; privacy fix: a shared quest no longer records who shared it |
| #6 | Themes renamed (Default, Pathfinder Day … Red); a second Reload attempt |
| #7 | A Reload check that reports what the client sees; the CurseForge project id from a variable or a secret |
| #8 | The CurseForge project id in the TOC (`## X-Curse-Project-ID: 1742985`) |

**Released:** v0.2.0 on GitHub, and on CurseForge as file 9166895 (project
1742985, game version id 17053, found by itself; uploaded as a *Release*, since
`CURSEFORGE_RELEASE_TYPE` isn't set).

## Open

1. **PR #9, 0.2.1: Reload.** Needs an in-game test, then a merge (which uploads
   0.2.1). Switch Default → a Pathfinder theme and press Reload; the guide's ≡
   menu → Reload; Submit → *Save it now*. Each should reload at once. If chat
   says "Reload was clicked, but the game didn't reload", the secure /reload
   macro itself doesn't work on this client: test it bare with
   `/run local b=CreateFrame("Button","APTest",UIParent,"SecureActionButtonTemplate,UIPanelButtonTemplate") b:SetSize(140,30) b:SetPoint("CENTER") b:SetText("Test /reload") b:SetAttribute("type","macro") b:SetAttribute("macrotext","/reload") b:RegisterForClicks("AnyUp")`
   and click it.
2. **CurseForge page:** paste the description from `docs/curseforge.md`
   (switch the editor to Markdown). Mark the 0.2.0 file Beta if wanted, and set
   the repository variable `CURSEFORGE_RELEASE_TYPE` = `beta` for later uploads.
3. **Tester post** for Discord: in the Launch Kit.
4. **Discord restructure:** the plan is in the Launch Kit; the owner applies it.
5. **Undecided:** "Default" is the Blizzard look, but a new install still starts
   on Pathfinder Green. Ask whether new installs should start on Default.
6. **Still to confirm in game** (from the 0.2.0 list): quest auto accept and
   turn-in, vendor auto sell and repair (both off by default; switched on under
   *Settings → Automation*), and the level-up card.

## Learned the hard way (don't relearn these)

- **Chat:** `C_ChatInfo.SendChatMessage` works only from a click (a hardware
  event), so level-up announcements are a card with a button per channel.
- **Reload:** `ReloadUI()` / `C_UI.Reload` is blocked for addons even from a
  click ("ADDON BLOCKED: Reload()"), though its documentation doesn't say so.
  Only a secure action button running the `/reload` macro works. **An invisible
  secure button laid over our own button does not work on this client**: in
  game it was shown, takes clicks, same strata, two levels higher, exactly the
  same rectangle, and `GetMouseFoci()` still named our button. The secure
  button has to *be* the button (0.2.1: one dialog, `Theme:AskReload`).
- **Protected frames:** a frame holding a secure button is protected. No
  Show/Hide/SetPoint/SetScale/SetAttribute in combat; hide it on
  `PLAYER_REGEN_DISABLED` (it fires before the lockdown). Never put a secure
  button inside a Pathfinder window (they must close in combat), and don't
  register such a frame with `Theme:RegisterWindow` (window scale calls
  `SetScale`).
- **Escape taint:** never assign to `StaticPopupDialogs`. Blizzard_Calendar
  reads it, then registers its Escape handler, and every Escape after that is
  "ADDON FORBIDDEN". Use `Theme:Confirm`.
- **Lua 5.1 `#t`** on a table with holes can be short or 0: the exporter's
  `IsArray` checks the keys are exactly 1..n.
- **Names:** the repository is `Aegis_Pathfinder_Forever`, but the **addon
  folder stays `Aegis_Forever_Pathfinder`** (SavedVariables are keyed by it).
  The release zip has the right folder; a release page's "Source code" zip
  doesn't. Theme **keys** never changed (`day`, `night`, `pathfinder`,
  `octowow`, `ravencraft`, `capybara`, `aegis`, `blizzard`); only labels did.
- **Privacy:** the data carries race, class and faction, never character names
  or realm; the one name is the credit name. A quest shared by a party member
  is kind `shared`, with no name; the intake also strips names from `npc`
  places without a creature id (from 0.2.0 clients).
- **The intake** runs only the default branch's code, parses uploaded Lua as
  data without running it, and caps sizes. To re-read an issue: *Actions →
  Ingest submitted data → Run workflow*, with its number.
- **Releases** (`.github/workflows/release.yml`): tests on every push and pull
  request; on `main`, builds the zip (`Tools/package.py`, which leaves out
  `Tools/`, `docs/`, `data/`, `dist/`, dot files and folders, `__pycache__`,
  `.pyc` and `.zip`), publishes or refreshes release `v<TOC version>`, and
  uploads to CurseForge once per version (the release keeps a `curseforge.txt`
  marker). The same version again only refreshes the GitHub release. Needs the
  `CF_API_KEY` repository secret; the project id comes from the TOC.
- **Tests:** `python Tools/smoke_test.py` (three skins against a mock client,
  `Tools/wow_mock.lua`, which blocks what the client blocks: chat outside a
  click, `ReloadUI`, protected frames in combat, writing the game's globals) and
  `python Tools/test_ingest.py` (75 tests). They need `lupa`. **The mock can't
  model which frame gets the mouse**: anything about clicks reaching the right
  frame must be tested in game.
- **The Forever UI source** isn't in the repository. To check a Blizzard
  template or API, export the client's interface files, or ask the owner.
- **Writing style:** plain words, short sentences, no jargon in anything a
  player reads; a CHANGELOG entry per version.

## Where things are

- `Core/Theme.lua`: the look, both skins, every widget, `Theme:Confirm`,
  `Theme:AskReload`. `Core/Init.lua`: saved variables, events (`AP:On`),
  defaults. `Core/Startup.lua`: `/apg` commands.
- `Collector/Collector.lua`: what is recorded. `Collector/Export.lua`: the
  envelope, the share code, the credit name.
- `UI/`: the guide window, data collection and Submit windows, options,
  browser, minimap button. `Features/`: automation and the level-up card.
- `Tools/`: package, CurseForge upload, intake (`ingest.py`,
  `ingest_issue.py`, `savedvariables.py`, `merge_exports.py`), tests.
- `docs/`: `curseforge.md` (setup and the page's text), `data-submission.md`,
  `data-schema.md`, `api-migration.md`, `feature-inventory.md`, this file,
  and the Launch Kit.
