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
| #9 | **0.2.1**: every Reload asks through one dialog whose Reload button is the secure /reload button. Tested in game on 2026-10-13: it reloads from all three places |
| #11 | **0.2.2**: the Reload dialog's first question is no longer blank; Clear data and Reload no longer hide each other; going back to the running skin withdraws its reload request. Tested in game |
| #12 | **0.2.3**: text drawn in our fonts is set again after login and as the ≡ menu opens (labels were blank after a skin switch); `/apg mouse` names what has the mouse; window stacking keeps each frame above its parent (the Default X took clicks on only a few pixels) |
| #13 | **0.2.4**: the player's name, which the game writes into some quest text, is saved as `<name>` (and cleaned from saved data at login and before sending); the intake strips the credit name and its first word; the stored data was cleaned |

**Released:** v0.2.1 on GitHub, and on CurseForge as file 9167387 (project
1742985, game version id 17053, found by itself; uploaded as a *Release*, since
`CURSEFORGE_RELEASE_TYPE` isn't set). v0.2.0 was file 9166895.

**Working locally:** from 2026-10-13, sessions run on the owner's PC, in the
clone, following `.claude/CLAUDE.md` (#10).

## Open

1. **If Reload ever stops working:** check the button gets the mouse (hovering
   it lights it up; that highlight comes from the secure button itself). Then
   try the secure /reload macro bare, if `/run` works on this client (it's a
   debug command, and the client can switch those off):
   `/run local b=CreateFrame("Button","APTest",UIParent,"SecureActionButtonTemplate,UIPanelButtonTemplate") b:SetSize(140,30) b:SetPoint("CENTER") b:SetText("Test /reload") b:SetAttribute("type","macro") b:SetAttribute("macrotext","/reload") b:SetAttribute("useOnKeyDown",false) b:RegisterForClicks("AnyUp")`
   and click it. Keep `useOnKeyDown` false: without it, the button follows the
   ActionButtonUseKeyDown setting and, registered for mouse-up only, does nothing.
2. **CurseForge page:** paste the description from `docs/curseforge.md`
   (switch the editor to Markdown). Mark the uploaded files Beta if wanted, and set
   the repository variable `CURSEFORGE_RELEASE_TYPE` = `beta` for later uploads.
3. **Tester post** for Discord: in the Launch Kit.
4. **Discord:** changelogs post themselves to #announcements once the
   `DISCORD_WEBHOOK_URL` secret is set (`Tools/discord_post.py`, from #16). The
   restructure (the plan is in the Launch Kit), a backup of the old posts and
   carrying the latest download and changelog posts over are done by a bot from the
   separate private repo `Aegis_Discord_Tools`, run from the owner's PC.
5. **Undecided:** "Default" is the Blizzard look, but a new install still starts
   on Pathfinder Green. Ask whether new installs should start on Default.
6. **Still to confirm in game** (from the 0.2.0 list): quest auto accept and
   turn-in, vendor auto sell and repair (both off by default; switched on under
   *Settings → Automation*), and the level-up card.

## Learned the hard way (don't relearn these)

- **Secure buttons and key down:** an addon's `SecureActionButtonTemplate`
  button acts on the key-down half of a click while the ActionButtonUseKeyDown
  setting is on, unless its `useOnKeyDown` attribute is false
  (`SecureActionButton_OnClick` in the client's SecureTemplates.lua). Registered
  for `AnyUp` only, it then does nothing. The mock client now plays this rule.
- **A new frame is shown:** `Hide()` on a frame just made fires its OnHide.
  Hide it before setting an OnHide that forgets state (0.2.1's first Reload
  question came up blank that way).
- **Names in quest text:** the game writes the player's name into some quest
  text. Saved as is, it went out even under another credit name (0.2.0 to
  0.2.3). `Collector.Unnamed` writes `<name>`; the intake does it too. The
  `data-submissions` branch's history still holds the first submission's raw
  text (it named the player only as their own credit name).
- **Class quests:** this client has no API that says a quest is for one class
  (`GetQuestTagInfo` gave none; `GetQuestClassification` has no class kind).
  Tell them apart from the data: the classes that saw them, the giver, the rewards.
- **Our fonts load late** the first time a game session uses them (after a
  switch from Default): some labels built then came up blank until the next
  reload. `Theme:SetFont` keeps our font strings, and `Theme:RefreshFontStrings`
  sets their text again (after login, and as the ≡ menu opens).
- **A click that lands on the wrong frame** can only be seen in game:
  `/apg mouse` names what has the mouse after 3 seconds. It found the Default
  X's problem: the header had it (level 516).
- **Window stacking:** a toplevel window raised by a click goes above its own
  children, so `Restack` measured every child as 1 above the window and set
  them all level with each other: the header covered its own X. `Restack` now
  keeps each frame at least 1 above its parent.
- **The client's UI source** is exported on the owner's PC:
  `World of Warcraft\_classic_beta_\BlizzardInterfaceCode\Interface\AddOns`
  (2026-10-06). Check Blizzard templates and APIs there.

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
- **The Forever UI source** isn't in the repository, but it is exported on the
  owner's PC (see the top of this list). A cloud session can't reach it: ask
  the owner.
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
