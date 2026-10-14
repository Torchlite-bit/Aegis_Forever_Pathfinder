# Where Pathfinder (Forever) stands

Handoff notes from the cloud session of 2026-10-13, for whoever works on this
next. Read this first, then the Launch Kit (`docs/launch-kit.html`, open it in a
browser; published copy at https://claude.ai/artifact/YLXpspLGznx9qMU5cFzMhq).

## What we're building

- **The addon:** a port of *Aegis: Pathfinder* (Turtle WoW, 1.12) to
  **WoW: Forever** (client 1.60.1, `## Interface 16001`, Lua 5.1, the modern
  Mainline engine). The same windows, settings and features. Forever is new,
  so the addon **collects quest and level data** that the guides are written
  from; the first, a short **test guide for Northshire Valley (1-6)**, ships
  in 0.4.0.
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
| #15 | **0.3.0**: a new install starts in Default (an earlier install keeps its saved theme) |
| #16 | Each new version's changelog posts itself to Discord through a webhook (`DISCORD_WEBHOOK_URL`), once |

**Released:** v0.3.0 on GitHub, and on CurseForge as file 9168527 (project
1742985, game version id 17053, found by itself; uploaded as a *Release*, since
`CURSEFORGE_RELEASE_TYPE` isn't set). Earlier files: v0.2.0 9166895, v0.2.1
9167387, v0.2.3 9167632, v0.2.4 9167948. The `CF_API_KEY` repository variable (a duplicate of
the secret) was deleted on 2026-10-13.

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
2. **CurseForge page:** approved on 2026-10-14, public at
   <https://www.curseforge.com/wow/addons/aegis-pathfinder>. The Discord releases post and
   #downloads link it (`release_post.py` and `directory` in `Aegis_Discord_Tools`); the README
   and the release notes (`Tools/package.py`) do from 0.3.4. Done earlier (the owner pasted the description from
   `docs/curseforge.md`). Optional: mark the uploaded files Beta, and set the
   repository variable `CURSEFORGE_RELEASE_TYPE` = `beta` for later uploads.
3. **Tester post** for Discord: in the Launch Kit.
4. **Discord:** changelogs post themselves into this addon's post in the **changelogs**
   forum (since 2026-10-14; releases keeps the download) once the `DISCORD_WEBHOOK_URL` secret (the forum's webhook) and the
   `DISCORD_THREAD_ID` variable (the post) are set (`Tools/discord_post.py`, #16, #17).
   The Instance Journal does the same in its own post. The thread variables are
   set (Pathfinder's changelog post: 1559782369643470999; the posts show the blue logo, `.github/discord-logo.png`); the webhook secret is the owner's.
   The server was **restructured on 2026-10-13** by the Aegis Tools bot (private
   repo `Aegis_Discord_Tools`, run from the owner's PC): see the Launch Kit's
   Discord section for the layout and what's left (deleting the carry-over's
   copies, Administrator off, empty categories, Community and Onboarding).
   Since 2026-10-14 the archive is hidden, #testing is in it, and anyone can test:
   bugs go to help-and-bugs and data to share-and-submit, tagged Pathfinder (Forever).
5. **Decided (0.3.0):** a new install starts on Default; an earlier install keeps
   the theme it saved.
6. **Still to confirm in game** (from the 0.2.0 list): quest auto accept and
   turn-in, vendor auto sell and repair (both off by default; switched on under
   *Settings → Automation*), and the level-up card.
7. **The Northshire test guide (0.4.0): to confirm in game.** It was written
   from one Human Warlock's run. Open questions, for a run with another class:
   - The other classes' letters (Simple 3100 Warrior, Consecrated 3101 Paladin,
     Encrypted 3102 Rogue, Hallowed 3103 Priest, Glyphic 3104 Mage) and their
     trainers' places come from the Turtle guide, not Forever's data. A wrong id
     leaves that class clicking the → twice. Hunters (Tordrin Sternblade is
     Forever's Hunter trainer here) get no letter in the guide.
   - Answered by the owner in game (2026-10-14): The Big Picture (91752, Elite)
     can be done alone at level 5; the Nibbled-On Book (91741) drops from a
     kobold; the kobold tracks (91772) are green tracks to click, starting just
     outside the abbey on the road to Goldshire. The guide's notes say so.
   - Rest and Relaxation (2158) was only seen offered at level 6.
   - The guide shows to every Alliance character (guides filter by faction only).
8. **Data saved before 0.4.1:** quest 21 (*Skirmish at Echo Ridge*) has
   `seen.abandoned = 1` and no `xpObserved` in `data/merged.json`, though it was
   handed in: it went in less than a second before 91752 (*The Big Picture*) at
   Marshal McBride, and only the last turn-in was kept. The same moment linked
   54 (*Report to Goldshire*, which follows 21) to 91752; 91752's other `next`
   links (91758, 96627) came from it too and may be wrong. `merged.json` is made by
   `Tools/ingest.py`: don't edit it by hand; read old `abandoned` counts and chains
   with this in mind.

## Learned the hard way (don't relearn these)

- **Quests go in back to back:** quest automation hands in every finished quest an
  NPC takes, well under a second apart, and only then picks up what it offers. Up
  to 0.4.0 the collector kept only the last turn-in: the first of two counted as
  abandoned, lost its XP check, and the NPC's next quest was linked to the last one.
  0.4.1 keeps the last few seconds' turn-ins by quest id, checks the first quest's
  XP as the second's reward frame opens, and links no chain when two or more went
  to that NPC. The offer in progress (`pendingDetail`) is still one slot.

- **Guides (0.4.0):** a step for one class or race (`class`/`race`) is left out
  for everyone else everywhere: current step, list, counts, arrows, `/apg next`
  and `prev` (`AP:GuideSteps`, `StepForward`, `StepBack`). A current ACCEPT or
  TURNIN is a band without a ring, so its note shows under the band in focus
  mode, and its by-hand fallback is the →. The waypoint is set once as a step
  comes up (setting it on every scan took the arrow from a quest the player
  tracked) and our own pin is cleared at a step with no place and at the end.
  Every shipped quest step is checked against `data/merged.json` by the smoke test;
  a step marked `unverified` only warns, so a data pull request never stops a
  release. A disagreement on a verified step does fail main's tests (the intake's
  PR runs no CI), so after merging data, look at main's run.
- **Who sees a guide:** `HasGuides` counts only the character's faction's guides
  (`GetGuides(nil)`), so a Horde character isn't told to pick the Alliance-only
  Northshire guide.

- **Secure buttons and key down:** an addon's `SecureActionButtonTemplate`
  button acts on the key-down half of a click while the ActionButtonUseKeyDown
  setting is on, unless its `useOnKeyDown` attribute is false
  (`SecureActionButton_OnClick` in the client's SecureTemplates.lua). Registered
  for `AnyUp` only, it then does nothing. The mock client now plays this rule.
- **A new frame is shown:** `Hide()` on a frame just made fires its OnHide.
  Hide it before setting an OnHide that forgets state (0.2.1's first Reload
  question came up blank that way).
- **Vendors open late:** Forever shows the merchant window through the player
  interaction manager (`PLAYER_INTERACTION_MANAGER_FRAME_SHOW`), so at `MERCHANT_SHOW`
  `MerchantFrame` may not be shown yet. 0.3.1 checked the window and never sold a
  grey; 0.3.2 tracks MERCHANT_SHOW/MERCHANT_CLOSED and sells a frame later.
- **Other addons replace Blizzard's windows:** DialogueUI unregisters `QuestFrame`'s
  events and shows its own window, so `QuestFrame` never opens. 0.3.2 checked
  `QuestFrame:IsShown()` before accepting and never accepted; 0.3.3 tracks
  QUEST_DETAIL/QUEST_FINISHED. Follow events, not Blizzard frames.
- **Chat with no click (0.3.2, `/apg chattest`):** EMOTE is blocked on Forever, though
  Zygor's code posts it from the event (Forever's global `SendChatMessage` only wraps
  `C_ChatInfo.SendChatMessage`). Party and Guild: not tested yet.
- **Discord posts the bot made are the bot's:** nobody else can edit them, so a
  change to a releases post, #downloads or #welcome goes through the bot
  (`Aegis_Discord_Tools`). The carry-over copied old posts with their old channel
  links; four pointed at archived or deleted channels (#recorder-data, a RallyPower
  bug forum) and were re-pointed by hand on 2026-10-13.
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
