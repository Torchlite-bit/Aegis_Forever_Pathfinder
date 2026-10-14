# Aegis: Pathfinder (Forever): how we work

A leveling-guide addon for **WoW: Forever** (client 1.60.1, `## Interface 16001`, Lua 5.1,
the modern Mainline engine). It is the Turtle WoW addon *Aegis: Pathfinder* ported: the same
windows, settings and features, with one short test guide so far (`Guides/Northshire.lua`). It
collects quest and level data from players, credits every contributor, and the guides are
written from that data (`docs/guide-api.md`; the smoke test checks them against `data/merged.json`).

**At the start of a session, read `docs/project-status.md`**: what has shipped, what's open,
and what's next. The Launch Kit (`docs/launch-kit.html`) holds the CurseForge page text, the
Discord tester post and the Discord plan. When something ships or is learned the hard way,
update `docs/project-status.md` in the same pull request.

## Where things are

| What | Where |
|---|---|
| Source (a clone of the repo) | `C:\Users\antho\OneDrive\Desktop\Aegis_Forever_Pathfinder` |
| Repo | https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever (default branch `main`) |
| Installed copy | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Aegis_Forever_Pathfinder` |
| The client's own UI source (exported 2026-10-06) | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\BlizzardInterfaceCode\Interface\AddOns` |
| git, gh | `C:\Program Files\Git\cmd`, `C:\Program Files\GitHub CLI` (gh is logged in) |
| Python | `C:\Users\antho\AppData\Local\Python\bin\python.exe` |
| CurseForge | project 1742985 (`## X-Curse-Project-ID` in the TOC) |

- In PowerShell, put git and gh on the PATH first:
  `$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + $env:Path`
- The game folder is `World of Warcraft\_classic_beta_` (a backslash before `_classic_beta_`;
  Markdown likes to eat it).
- Check Blizzard templates and APIs in the exported UI source, read-only, not from memory of
  retail WoW: this client differs.
- git here has `core.autocrlf=true`: the clone has CRLF, the release zip (built on Linux) LF.
  Compare files with line endings normalized.

## Workflow for every change

1. **Branch.** Start a new branch from the latest `origin/main` (`git fetch origin`, then
   `git switch -c <name> origin/main`). Before adding to an existing pull request, check with
   `gh pr view <n> --json state` that it's still open; if it was merged, start a new branch
   from `main` instead. Don't push to a branch another session is using.
2. **Change, and extend the smoke tests to cover it** (`Tools/smoke_scenario.lua`,
   `Tools/wow_mock.lua`, `Tools/test_ingest.py`). The mock client can't model which frame gets
   the mouse: for anything about clicks, secure buttons or combat, tell the owner exactly what
   to test in game.
3. **Test**, and fix any failure before going on:
   `python Tools/smoke_test.py`, `python Tools/test_ingest.py` and `python Tools/test_release.py`
   (the first two need `lupa` 2.8, the version CI pins).
4. **Install**: mirror the clone into the installed copy, leaving out exactly what
   `Tools/package.py` leaves out of the release zip: its `LEFT_OUT` folders (`Tools`, `docs`,
   `data`, `dist`), dot files and folders (`.git`, `.github`, `.claude`, …), `__pycache__`, and
   `.pyc` and `.zip` files. Full paths in `/XD`, so a nested folder with the same name isn't
   skipped:

   ```powershell
   $src = "C:\Users\antho\OneDrive\Desktop\Aegis_Forever_Pathfinder"
   $dst = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Aegis_Forever_Pathfinder"
   robocopy $src $dst /MIR /XD "$src\Tools" "$src\docs" "$src\data" "$src\dist" "$src\.git" "$src\.github" "$src\.claude" ".*" "__pycache__" /XF ".*" "*.pyc" "*.zip" /NP /NDL /NJH
   if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
   ```

   Exit codes below 8 mean success. This copies the same files `package.py` puts in the zip
   (91 checked 2026-10-13 with `/L`; 92 from 0.4.0, with `Guides/Northshire.lua`; 93 from 0.5.0, with `UI/NavArrow.lua`). `/MIR` never deletes from the installed copy anything that
   matches an exclusion (a `Tools` or `docs` folder, a dot file): if such leftovers appear
   there, list them and ask before sending them to the Recycle Bin.
   **One installed copy, several sessions:** a `/MIR` from another branch deletes what that
   branch lacks (on 2026-10-14 a main-based mirror wiped the Northshire guide the owner was
   testing). Before mirroring, read the installed TOC's `## Version` and compare its file list
   with yours: if it holds a newer version or files your branch doesn't have, another
   session's build is being tested, so ask the owner before installing over it.
   **The CurseForge app** on the owner's PC also writes there: when a version is
   released, it replaces the folder with the release zip (LF line endings; a copy from
   this clone has CRLF). On 2026-10-14 it swapped a 0.5.0 test build for the 0.4.1
   release. Before asking the owner to test, check the installed `## Version` again.
   Before the first mirror of a session, check the installed copy isn't a folder link
   (`(Get-Item -LiteralPath $dst -Force).LinkType` is empty): mirroring into a link would write
   over this clone.
   Then tell the owner to `/reload`, or to **restart the game fully** when files were added or
   removed.
5. **Version and pull request.** Bump `## Version` in the TOC (patch for fixes, minor for
   features) and the fallback version in `Core/Init.lua`, add a `CHANGELOG.md` entry (plain
   words; it becomes the release notes), commit, push, and open the pull request with
   `gh pr create --body-file <file>`. A change only to files the zip leaves out (`Tools`,
   `docs`, `data`, `.github`, `.claude`) can keep the version: merging it only refreshes the
   current GitHub release.
6. **Don't poll CI.** Give the owner the pull request link; the owner merges it.

### What a merge to main does (`.github/workflows/release.yml`)

Every push and pull request runs the tests. On `main` only, it then builds the zip
(`Tools/package.py`: the addon folder alone, plus the version's CHANGELOG entry as notes) and
publishes the GitHub release `v<TOC version>`, or refreshes it if that version exists. A new
version is also uploaded to CurseForge once (`Tools/curseforge_upload.py`); the release keeps a
`curseforge.txt` marker so the same version is never uploaded twice. Then the version's
changelog is posted to Discord once (`Tools/discord_post.py`, a `discord.txt` marker), when the
`DISCORD_WEBHOOK_URL` secret is set (the releases forum's webhook); the `DISCORD_THREAD_ID`
variable names this addon's post in that forum, and the optional `DISCORD_PING_ROLE_ID` mentions
a role. The Instance Journal posts the same way, into its own post. Needs the `CF_API_KEY`
repository **secret**; the project id comes from the TOC (a `CURSEFORGE_PROJECT_ID` variable or
secret overrides it). Optional variables: `CURSEFORGE_RELEASE_TYPE` (`release`, `beta`,
`alpha`), `CURSEFORGE_GAME_VERSION_IDS` (found by itself so far: 17053).

## Rules

- Never handle API keys or tokens: don't read, print or set their values. The owner adds
  secrets. Check Actions settings by name only.
- Commit as `Torchlite-bit <229679030+Torchlite-bit@users.noreply.github.com>` (set in this
  repo's git config). Never put the owner's personal email anywhere.
- Send files to the Recycle Bin instead of deleting them permanently:
  `Add-Type -AssemblyName Microsoft.VisualBasic` then
  `[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')`
  (`DeleteDirectory` for a folder).
- Ask before downloading or installing anything.
- No force-pushing, and no deleting branches.
- The addon folder and TOC stay named `Aegis_Forever_Pathfinder` (players' saved data is keyed
  by it), though the repo is `Aegis_Pathfinder_Forever`. Theme **keys** never change (`day`,
  `night`, `pathfinder`, `octowow`, `ravencraft`, `capybara`, `aegis`, `blizzard`); only their
  labels may.
- Only the game's own code can reload: never call `ReloadUI` or `C_UI.Reload`, and never lay a
  secure button over another button (that failed in game). Never assign to
  `StaticPopupDialogs` (it taints Escape). Never put a secure button inside a Pathfinder window.
- Player data never carries character names or realms; the credit name is the only name.
- Write anything players read in plain words and short sentences.

## Learned the hard way (from the cloud session; don't relearn these)

- **Chat:** `C_ChatInfo.SendChatMessage` works only from a click (a hardware event), so
  level-up announcements are a card with a button per channel.
- **Reload:** `ReloadUI()` / `C_UI.Reload` is blocked for addons even from a click ("ADDON
  BLOCKED: Reload()"), though its documentation doesn't say so. Only a secure action button
  running the `/reload` macro works. An invisible secure button laid over our own button does
  not work on this client: in game it was shown, took clicks, same strata, two levels higher,
  exactly the same rectangle, and `GetMouseFoci()` still named our button. The secure button
  has to *be* the button (0.2.1: one dialog, `Theme:AskReload`).
- **Protected frames:** a frame holding a secure button is protected. No
  Show/Hide/SetPoint/SetScale/SetAttribute in combat; hide it on `PLAYER_REGEN_DISABLED` (it
  fires before the lockdown). Never put a secure button inside a Pathfinder window (they must
  close in combat), and don't register such a frame with `Theme:RegisterWindow` (window scale
  calls `SetScale`).
- **Escape taint:** never assign to `StaticPopupDialogs`. Blizzard_Calendar reads it, then
  registers its Escape handler, and every Escape after that is "ADDON FORBIDDEN". Use
  `Theme:Confirm`.
- **Lua 5.1 `#t`** on a table with holes can be short or 0: the exporter's `IsArray` checks the
  keys are exactly 1..n.
- **Names:** the release zip has the right folder (`Aegis_Forever_Pathfinder`); a release
  page's "Source code" zip doesn't.
- **Privacy:** the data carries race, class and faction, never character names or realm; the
  one name is the credit name. A quest shared by a party member is kind `shared`, with no name;
  the intake also strips names from `npc` places without a creature id (from 0.2.0 clients).
- **The intake** (`.github/workflows/ingest-data.yml`) runs only the default branch's code,
  parses uploaded Lua as data without running it, and caps sizes. It files submissions on the
  `data-submissions` branch (the bot's; don't push to it) and opens a pull request. To re-read
  an issue: *Actions → Ingest submitted data → Run workflow*, with its number.
- **Tests:** `Tools/smoke_test.py` runs three skins against a mock client
  (`Tools/wow_mock.lua`) that blocks what the client blocks: chat outside a click, `ReloadUI`,
  protected frames in combat, writing the game's globals. `Tools/test_ingest.py` tests the
  intake. The mock can't model which frame gets the mouse: anything about clicks reaching the
  right frame must be tested in game.
- **Writing style:** plain words, short sentences, no jargon in anything a player reads; a
  CHANGELOG entry per version.
