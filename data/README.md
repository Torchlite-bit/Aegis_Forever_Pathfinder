# data/

The quest and leveling data players collected in game and sent in, kept for
writing the guides. Everything here is made by `Tools/ingest.py`; don't edit it
by hand. How players send data, and how it gets here:
[docs/data-submission.md](../docs/data-submission.md).

```
submissions/<collection id>.json   one file per collection: what one player's
                                   addon collected (until they cleared it), cleaned,
                                   with where it came from ("source")
merged.json                        every submission merged into one, with
                                   "sources" listing them
contributors.json                  who sent what: name, GitHub login,
                                   collections, quests, levels, first and last time
```

- **One file per collection.** The addon gives each collection a random id and
  keeps it until the player clears their data. Players send the same growing
  collection again and again, so a newer copy (one that holds more) *replaces*
  the file and nothing is counted twice.
- **Cleaned.** Only the fields [docs/data-schema.md](../docs/data-schema.md)
  lists are kept, with the right types and sensible sizes. The data names no
  character: players are race, class and faction. The one name kept is the
  contributor's chosen credit name.
- **merged.json** follows `Tools/merge_exports.py`'s rules: counts add up,
  ranges keep the lowest and highest, positions average, text keeps the first
  sent (collections are merged in the order they first arrived).
- The same submissions always give the same `merged.json` and
  `contributors.json`, so a diff shows only what changed.

Made from the same submissions, outside this folder:
`Contributors.lua` (the names the addon shows in game) and the list in
`CONTRIBUTORS.md`.

Make everything again after editing or removing a submission by hand:

```sh
python Tools/ingest.py
```
