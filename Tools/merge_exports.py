"""
Merges players' data into one file to write guides from, without storing it
(Tools/ingest.py stores it and merges with the same rules).

    python Tools/merge_exports.py code.txt export.txt Aegis_Forever_Pathfinder.lua ... -o merged.json

Each input is anything Tools/ingest.py reads: share codes, the Submit window's
text (format 1 or 2), or a SavedVariables file, zipped or not. Each is cleaned
as ingest stores it. The merge follows the collector's own rules
(docs/data-schema.md): counts add up, ranges keep the lowest and highest,
coordinates average by how many positions each side had, sets join, and text
keeps the first seen.
"""

import argparse
import json
import os
import sys

HEADER = "AEGIS PATHFINDER FOREVER DATA"
RANGE_KEYS = {"min", "max", "count", "last"}
# Tables whose values are counts that add up: "who saw it", "how often", map cells.
COUNT_TABLES = {"by", "seen", "observers", "objective", "turnin", "available", "counts"}
# Tables of such tables: progress keeps map cells per objective, and chosen keeps
# item counts per class. Their entries merge as "counts".
COUNT_PARENTS = {"progress", "chosen"}


def is_range(value):
    # min and max, not just count: a reward item without a name is {"count": n}.
    return isinstance(value, dict) and {"min", "max", "count"} <= set(value) <= RANGE_KEYS | {"factionID"}


def is_place(value):
    return isinstance(value, dict) and "kind" in value and "count" in value


def merge_range(a, b):
    out = dict(a)
    out["min"] = min(a.get("min", b.get("min")), b.get("min", a.get("min")))
    out["max"] = max(a.get("max", b.get("max")), b.get("max", a.get("max")))
    out["count"] = a.get("count", 0) + b.get("count", 0)
    out["last"] = b.get("last", a.get("last"))
    if "factionID" in b and "factionID" not in a:
        out["factionID"] = b["factionID"]
    return out


def merge_place(a, b):
    out = dict(a)
    na, nb = a.get("xyCount", 0), b.get("xyCount", 0)
    if nb:
        if na:
            out["x"] = round((a["x"] * na + b["x"] * nb) / (na + nb), 4)
            out["y"] = round((a["y"] * na + b["y"] * nb) / (na + nb), 4)
            for key, pick in (("xMin", min), ("yMin", min), ("xMax", max), ("yMax", max)):
                out[key] = pick(a[key], b[key])
        else:
            for key in ("x", "y", "xMin", "xMax", "yMin", "yMax"):
                out[key] = b[key]
        out["xyCount"] = na + nb
    out["count"] = a.get("count", 0) + b.get("count", 0)
    if "playerLevel" in b:
        out["playerLevel"] = merge_range(a["playerLevel"], b["playerLevel"]) if "playerLevel" in a else b["playerLevel"]
    for key in ("name", "subzone", "zone", "id"):
        if out.get(key) is None and b.get(key) is not None:
            out[key] = b[key]
    return out


def merge(a, b, key=None):
    if a is None:
        return b
    if b is None:
        return a
    if is_range(a) and is_range(b):
        return merge_range(a, b)
    if is_place(a) and is_place(b):
        return merge_place(a, b)
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            if k in out:
                if key in COUNT_TABLES and isinstance(out[k], (int, float)) and isinstance(v, (int, float)) \
                        and not isinstance(v, bool):
                    out[k] = out[k] + v
                else:
                    out[k] = merge(out[k], v, "counts" if key in COUNT_PARENTS else k)
            else:
                out[k] = v
        return out
    if key in ("first", "created"):
        return min(a, b)
    if key == "last" and isinstance(a, (int, float)):
        return max(a, b)
    # Text, lists and anything else: the first seen stands.
    return a


def read_inputs(path):
    """Every collection in a file, as cleaned envelopes (Tools/ingest.py reads it)."""
    import ingest  # here rather than at the top: ingest imports this file
    with open(path, "rb") as handle:
        content = handle.read()
    problems = []
    envelopes = []
    for submission in ingest.decode(content, os.path.basename(path), problems):
        try:
            envelopes.append(ingest.sanitize(submission.envelope))
        except ingest.IngestError as error:
            problems.append("%s: %s" % (os.path.basename(path), error))
    for problem in problems:
        print(problem, file=sys.stderr)
    return envelopes


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("exports", nargs="+")
    parser.add_argument("-o", "--output", default="-")
    args = parser.parse_args(argv)

    merged, sources = None, []
    for path in args.exports:
        for envelope in read_inputs(path):
            data = dict(envelope["data"])
            sources.append({"file": path, "id": data.pop("id", None), "format": envelope["format"],
                            "addonVersion": envelope["addonVersion"], "build": envelope["build"],
                            "contributor": envelope["contributor"]})
            merged = merge(merged, data)
    merged = merged or {}
    merged["sources"] = sources

    text = json.dumps(merged, indent=1, sort_keys=True)
    if args.output == "-":
        sys.stdout.write(text + "\n")
    else:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
    quests = len(merged.get("quests", {}))
    levels = len(merged.get("levels", {}))
    print("merged %d exports: %d quests, %d levels" % (len(args.exports), quests, levels), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
