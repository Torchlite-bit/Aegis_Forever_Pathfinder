# Sending collected data, and how it gets in

Pathfinder's guides are written from the data players collect in game
([data-schema.md](data-schema.md) has every field). This page is how a player
sends theirs, what happens to it, and what maintainers need to know.

## For players

### The share code (the easy way)

1. In game, click **Submit data** in the data collection window (or type
   `/apg submit`).
2. The window shows your **share code**: everything you collected, packed into
   one line that starts with `APF1:`. It is already selected: press **Ctrl+C**.
   Fill in **Credit me as** there if you'd like a name other than your
   character's in the contributors list.
3. Open the **Submit collected data** form on GitHub (the Submit window has the
   link, or *Issues → New issue → Submit collected data*), paste the code into
   **Share code or data file**, and submit.

A bot reads it within a few minutes, answers on the issue, and closes it.

Send again whenever you have collected more. The addon gives your collection
an id that stays until you clear your data, and a newer copy **replaces** the
one we have, so nothing is counted twice.

### The data file (for a big collection, or no GitHub account)

A GitHub issue takes about 65,000 characters, so a very big collection may not
fit as a code. Send the file instead. After `/reload` (or logging out), it is:

```
World of Warcraft/<client folder>/WTF/Account/<your account>/SavedVariables/Aegis_Forever_Pathfinder.lua
```

- **On GitHub**: GitHub doesn't take `.lua` files, so rename it to `.txt` (or
  zip it), then drag it into the form's **Share code or data file** box.
- **On Discord** ([discord.gg/Hr66t25vE7](https://discord.gg/Hr66t25vE7)): post
  the file and a maintainer adds it.

The file holds only this addon's settings and collected data. It never names
your character's realm, and characters are recorded as race, class and
faction. The one name in what you send is your credit name.

### If something went wrong

The bot's answer says what it could not read, in plain words (a code cut
short, a file that isn't the right one), and labels the issue
`needs-attention`. **Edit the issue** to fix it, and it is read again.

## What happens to it

```
issue form ──► Ingest submitted data (Action) ──► data-submissions branch ──► pull request ──► merged
                 Tools/ingest_issue.py              one commit per issue        maintainer review
```

1. The issue form gives the issue the `data-submission` label, which starts
   `.github/workflows/ingest-data.yml`. (The form's own heading starts it too,
   so the first submission is read even before the label exists; the Action
   then adds the label.)
2. `Tools/ingest_issue.py` finds the share codes and exports pasted in the
   issue and downloads the files attached to it, then reads, cleans and stores
   each collection with `Tools/ingest.py`:
   - `data/submissions/<collection id>.json`: one file per collection. A newer
     copy (later `exportedAt`; on a tie, received later) replaces the file; an
     older or identical one changes nothing.
   - made again from every submission: `data/merged.json`,
     `data/contributors.json`, `Contributors.lua` (the names the addon
     shows) and the list in `CONTRIBUTORS.md`.
3. The Action runs `Tools/smoke_test.py` on the default branch's addon with
   the new contributors list in it, to prove it still loads, then commits to
   the `data-submissions` branch as `Data from #<issue> by <name>`, with the
   player as co-author.
4. It opens a pull request from `data-submissions` (*Collected data from
   players*), or adds to the open one.
5. It answers on the issue, labels it `ingested` and closes it. When nothing
   usable was found, it answers with help, labels it `needs-attention` and
   leaves it open.

The `data-submissions` branch is kept current: each run first merges the
default branch into it. Runs for different issues go side by side: if another
run pushed first, a run starts again from the branch as it is now (up to five
times), so no submission is dropped. Runs for the same issue wait their turn.

## For maintainers

### One-time setup

- **Settings → Actions → General → Workflow permissions**: tick *Allow GitHub
  Actions to create and approve pull requests*. Without it the data still
  reaches the `data-submissions` branch, but the Action can't open the pull
  request: its answer on the issue says so, with a link to open it by hand.
- **Labels** (optional): `data-submission`, `ingested` and `needs-attention`.
  The Action makes any that are missing the first time it runs.

### Reviewing the pull request

Anyone can open an issue, so read the pull request before merging. Each commit
names its issue. What to look at: new files in `data/submissions/` (a
collection with a handful of quests is normal; thousands of quests from a
brand-new collection may be worth a look) and new names in
`Contributors.lua` / `CONTRIBUTORS.md`.

Pushes made by the Action don't start the repository's other workflows (GitHub
doesn't start workflows from the Action's own token). The Action runs the smoke
test itself; to run the usual checks on the pull request too, close and reopen
it.

Merge as you like. After a merge, the next submission opens a new pull request.

### Files sent on Discord

```sh
python Tools/ingest.py Aegis_Forever_Pathfinder.lua --credit "Their Name"
python Tools/ingest.py data.zip code.txt            # several at once; codes and exports in text files too
python Tools/ingest.py                              # only make the generated files again
```

It reads share codes, exports (format 1 and 2), SavedVariables files (renamed,
zipped or gzipped), stores each collection the same way the Action does, and
makes the generated files again. `--credit` names the contributor (otherwise:
the name set in game, else "Anonymous", which is counted but not listed).
Then commit `data/`, `Contributors.lua` and `CONTRIBUTORS.md`.

### Fixing things by hand

- **Remove a submission**: delete its `data/submissions/<id>.json`, run
  `python Tools/ingest.py`, commit.
- **Read an issue again**: *Actions → Ingest submitted data → Run workflow*,
  with the issue's number. (Editing the issue, or removing and re-adding its
  `data-submission` label, does it too.)
- **"First sent from another GitHub account"**: a collection id can only be
  replaced from the account that first sent it, so no one can overwrite
  someone else's data. If it really is the same player, delete the old file
  and read the issue again.

## Safety

Everything a player sends is untrusted, and the Action that reads it can push.

- **Uploaded Lua is parsed, never run.** `Tools/savedvariables.py` reads
  tables, strings, numbers and booleans, and refuses anything else (a function
  call, an expression, `local`).
- **Sizes are capped**: 25 MB in (text, file or download), 50 MB unpacked, at
  most 20 files in a zip. A zip with an absolute path, `..` or a link in it is
  refused whole, and nothing from it is written to disk. Archives inside
  archives aren't opened.
- **Only GitHub's own attachment links are downloaded**
  (`github.com/user-attachments/files/...` and this repository's
  `/files/...`), over https, following redirects only to `github.com` and
  `githubusercontent.com`, with a 30-second timeout.
- **Only known fields are kept.** The cleaner keeps what
  [data-schema.md](data-schema.md) lists, with the right types: numbers finite
  and in range, coordinates 0 to 1, counts whole and not negative, ids as
  numbers, text without control characters and at most 2,000 characters, at
  most 20,000 quests and 100 levels.
- **Names are cleaned**: no control or invisible characters, `<`, `>`, `\`,
  backticks, quotes or `@` (no mentions), at most 40 characters. The in-game
  list keeps only letters, digits, spaces and `. , ! ? & + ( ) # -` (never `|`,
  the game's escape character), every string is escaped, and the file is
  checked line by line before it is written. Markdown output is escaped.
- **The issue's text is fetched into a file** through GitHub's API and reaches
  the scripts only through that file and environment variables, never pasted
  into a workflow script.
- **Only the default branch's code runs.** The Action checks the default
  branch out on its own and runs its `Tools/` from there; the
  `data-submissions` branch is only written to, never run from.
- **A person merges.** Nothing reaches the default branch without the pull
  request being merged.

## Credits

Each collection is credited to the form's **Credit me as**, else the name set
in game (which is the character's name if the player left it empty), else the
GitHub login. Names are listed in the order players first sent data:
in game (Submit window, About page), in `CONTRIBUTORS.md`, and in
`data/contributors.json` with counts. Collections sent without any name are
counted, not listed. To change or remove a name, send again with a new
**Credit me as**, or ask a maintainer.
