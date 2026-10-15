"""
Loads the addon the way the client would (files in TOC order, sharing one namespace)
against Tools/wow_mock.lua, then runs Tools/smoke_scenario.lua: it starts the data
collector, plays a quest through from offer to turn-in, levels up, packs it to submit,
and clicks through every window -- once in each skin. The share code and plain export
are decoded here, and by Tools/ingest.py when it is there.

    python Tools/smoke_test.py

Needs the lupa package (pip install lupa), which bundles Lua 5.1, WoW's Lua version.
It checks the addon's own logic and that what it sends decodes. It does not show
what the windows look like; only the game does that.
"""

import base64
import json
import os
import sys
import zlib
from xml.etree import ElementTree

import lupa.lua51 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "Tools")
ADDON = "Aegis_Forever_Pathfinder"
# Globals the scenario itself sets, besides the addon's own names.
ALLOWED_GLOBALS = {"GetQuestReward"}


def toc_files():
    with open(os.path.join(ROOT, ADDON + ".toc"), encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                yield line.replace("\\", os.sep)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


sys.path.insert(0, TOOLS)
try:
    import ingest  # Tools/ingest.py, the GitHub side's reader
except ImportError:
    ingest = None


def check_envelope(envelope, credit):
    """The envelope Tools/ingest.py expects: docs/data-submission.md."""
    assert envelope["format"] == 2, envelope.get("format")
    assert envelope["addon"] == ADDON, envelope.get("addon")
    assert envelope["contributor"] == credit, envelope.get("contributor")
    assert isinstance(envelope["exportedAt"], int) and isinstance(envelope["interface"], int)
    data = envelope["data"]
    quest = data["quests"]["176"]
    assert quest["title"] == "Wanted: Hogger", quest["title"]
    assert quest["rewards"]["xp"]["5"]["last"] == 1450, quest["rewards"]["xp"]
    assert "log" not in data, "the window's log is left out of the export"
    assert "Tester" not in json.dumps(data), "the data never names the character"
    assert isinstance(data["id"], str) and data["id"], "the collection has an id"


DATA = os.path.join(ROOT, "data", "merged.json")
NEAR = 0.03   # how far a step's place may be from where the data saw the NPC (0-1 map units)


def check_guides(ns):
    """The shipped guides against the collected data: each quest step's id and title are
    in data/merged.json, and an ACCEPT or TURNIN stands where the data saw that quest
    picked up or handed in. A step marked `unverified = true` (written from another
    source, e.g. the other classes' letters from the Turtle guide) may name a quest the
    data hasn't seen, and when the data disagrees with it that is a warning, not a
    failure, so new data never stops a release. Returns (problems, warnings, matched,
    unseen): matched counts the steps the data confirms, unseen the unverified steps
    whose quest the data hasn't seen yet."""
    with open(DATA, encoding="utf-8") as handle:
        quests = json.load(handle)["quests"]
    problems, warnings, matched, unseen = [], [], 0, 0
    for name in ns.guidelist.values():
        for index, step in ns.guides[name].steps.items():
            qid = step.qid
            if qid is None:
                continue
            where = "%s, step %d (%s %s)" % (name, index, step.action, step.title)
            report = warnings if step.unverified else problems
            quest = quests.get(str(int(qid)))
            if quest is None:
                if step.unverified:
                    unseen += 1
                else:
                    problems.append(where + ": quest %d isn't in the collected data" % qid)
                continue
            found = len(report)
            if quest.get("title") and quest["title"] != step.title:
                report.append(where + ": the data calls quest %d %r" % (qid, quest["title"]))
            places = {"ACCEPT": quest.get("pickups"), "TURNIN": quest.get("turnins")}.get(step.action)
            if places and step.map is not None:
                near = [p for p in places.values() if p.get("mapID") == step.map and p.get("x") is not None
                        and abs(p["x"] - step.x) <= NEAR and abs(p["y"] - step.y) <= NEAR]
                if not near:
                    report.append(where + ": not where the data saw it (%s)" % ", ".join(
                        "%s %.3f,%.3f" % (p.get("name") or p.get("kind"), p.get("x") or 0, p.get("y") or 0)
                        for p in places.values()))
            if len(report) == found:
                matched += 1
    return problems, warnings, matched, unseen


BOOKS = os.path.join(TOOLS, "library_books.json")
FLIGHT_MASTERS = os.path.join(TOOLS, "flight_masters.json")
TRIPS = ("RUN", "FLY", "BOAT", "HEARTH", "MAP")


def check_shipped(ns):
    """Every shipped guide's steps, before the scenario adds its own: a title; map/x/y all or
    none, on a 0..1 map; a node on a flight point; no character name in a note. The book
    routes: each holds its continent's books once each (one Rumi), and every flight point and
    flight stands on a flight master of the guide's faction or a neutral one."""
    with open(FLIGHT_MASTERS, encoding="utf-8") as handle:
        masters = {n["id"]: n for n in json.load(handle)["nodes"]}
    with open(BOOKS, encoding="utf-8") as handle:
        data = json.load(handle)
    continents = {side: {b["book"] for b in data[side]} for side in ("eastern_kingdoms", "kalimdor")}
    problems = []
    for name in ns.guidelist.values():
        guide = ns.guides[name]
        faction = guide.faction
        books = []
        for index, step in guide.steps.items():
            where = "%s, step %d" % (name, index)
            if not step.title:
                problems.append(where + ": no title")
            placed = [step.map is not None, step.x is not None, step.y is not None]
            if any(placed) and not all(placed):
                problems.append(where + ": only part of a place")
            if all(placed) and not (0 < step.x < 1 and 0 < step.y < 1):
                problems.append(where + ": a place off the map (%s, %s)" % (step.x, step.y))
            if step.note and "<name>" in step.note:
                problems.append(where + ": names someone")
            if step.action == "GETFLIGHTPOINT":
                node = masters.get(step.node)
                if not node:
                    problems.append(where + ": a flight point with no known node (%s)" % step.node)
                elif node["faction"] not in (faction, "Neutral") or node["mapID"] != step.map \
                        or abs(node["x"] - step.x) > 0.002 or abs(node["y"] - step.y) > 0.002:
                    problems.append(where + ": not %s's flight master for the %s" % (node["name"], faction))
            if step.action == "FLY" and step.map is not None:
                if not any(n["mapID"] == step.map and abs(n["x"] - step.x) <= 0.002 and abs(n["y"] - step.y) <= 0.002
                           and n["faction"] in (faction, "Neutral") for n in masters.values()):
                    problems.append(where + ": a flight to no %s flight master" % faction)
            if step.action == "LOOT" and step.item:
                books.append(step.item)
        if guide.category == "collections" and name.startswith("Library Books"):
            side = "eastern_kingdoms" if "Eastern Kingdoms" in name else "kalimdor"
            want = continents[side]
            if len(books) != len(set(books)) or set(books) != want:
                problems.append("%s: the books aren't its continent's, once each (missing %s, extra %s)" % (
                    name, sorted(want - set(books)), sorted(set(books) - want)))
    return problems


def check_books(ns):
    """The library-book guides against the book list (Tools/library_books.json): each LOOT
    step names a known book and stands within 0.002 of one of its spots (Blackrock
    Mountain's two have no spot). Returns the problems and how many book steps were checked."""
    with open(BOOKS, encoding="utf-8") as handle:
        data = json.load(handle)
    spots = {}
    for side in ("eastern_kingdoms", "kalimdor"):
        for book in data[side]:
            spots.setdefault(book["book"], []).append(book)
    problems, checked = [], 0
    for name in ns.guidelist.values():
        for index, step in ns.guides[name].steps.items():
            if step.action != "LOOT" or step.item is None:
                continue
            checked += 1
            where = "%s, step %d (%s)" % (name, index, step.item)
            known = spots.get(step.item)
            if not known:
                problems.append(where + ": not a book in the list")
                continue
            if step.map is None:
                if not any(b["zone"] == "Blackrock Mountain" for b in known):
                    problems.append(where + ": no spot on the map")
                continue
            if any(b["zone"] == "Blackrock Mountain" for b in known):
                problems.append(where + ": Blackrock Mountain's map has no id: no spot can be right")
                continue
            if not any(b.get("mapID") == step.map and abs(b["zx"] - step.x) <= 0.002 and abs(b["zy"] - step.y) <= 0.002
                       for b in known):
                problems.append(where + ": not at the book's spot")
    return problems, checked


def run(skin):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("date = os.date; time = os.time; debugstack = function() return debug.traceback() end")
    lua.execute(read(os.path.join(TOOLS, "wow_mock.lua")))
    # The saved variables as the client hands them over: empty, or with the skin chosen.
    # "plain": a client without the modern art or C_EncodingUtil, to prove the fallbacks.
    if skin != "blizzard-plain":
        lua.execute("WOWMOCK.InstallModernArt()")
        lua.execute("WOWMOCK.InstallEncoding()")
    if skin == "blizzard":
        pass  # A new install: nothing saved, so it starts in Default.
    elif skin == "blizzard-plain":
        lua.execute('AegisPathfinderDB = { profile = { theme = "blizzard" } }')
    else:
        # An earlier install, which saved Pathfinder Green (every load writes the defaults),
        # and a character 0.1.0 saved, with quest automation written as off.
        lua.execute('AegisPathfinderDB = { profile = { theme = "pathfinder" } }')
        lua.execute('AegisPathfinderCharDB = { autoquest = false }')

    before = set(lua.eval("function() local t = {} for k in pairs(_G) do t[#t + 1] = k end return t end")().values())
    # Each file runs with every global write passing through `written`, so an assignment
    # to one of the game's own globals is caught even when it assigns the same value:
    # `StaticPopupDialogs = StaticPopupDialogs or {}` tainted Escape in 0.1.0.
    written = lua.table()
    load = lua.eval("""function(source, name, addon, ns, written)
        local chunk, err = loadstring(source, "@" .. name)
        if not chunk then error(err) end
        setfenv(chunk, setmetatable({}, { __index = _G, __newindex = function(_, key, value)
            written[key] = name
            _G[key] = value
        end }))
        local ok, runErr = xpcall(function() return chunk(addon, ns) end, debug.traceback)
        if not ok then error(runErr) end
    end""")
    ns = lua.table()
    files = list(toc_files())
    for relative in files:
        if relative.lower().endswith(".xml"):
            ElementTree.parse(os.path.join(ROOT, relative))
            continue
        load(read(os.path.join(ROOT, relative)), relative, ADDON, ns, written)
    ElementTree.parse(os.path.join(ROOT, "Bindings.xml"))
    # Before the scenario registers its own test guide: only the shipped ones.
    bookProblems, bookSteps = check_books(ns)
    bookProblems = bookProblems + check_shipped(ns)
    if bookProblems:
        print("FAILED (%s skin): the book guides disagree with the book list:\n  %s" % (skin, "\n  ".join(bookProblems)))
        return False
    problems, warnings, matched, unseen = check_guides(ns)
    for warning in warnings:
        print("WARNING (%s skin): an unverified guide step disagrees with the data: %s" % (skin, warning))
    if problems:
        print("FAILED (%s skin): the guides disagree with the collected data:\n  %s" % (skin, "\n  ".join(problems)))
        return False

    scenario = lua.eval("""function(source, ns, skin)
        local chunk = assert(loadstring(source, "@smoke_scenario.lua"))
        return xpcall(function() return chunk(ns, skin) end, debug.traceback)
    end""")
    ok, result = scenario(read(os.path.join(TOOLS, "smoke_scenario.lua")), ns, skin.split("-")[0])
    if not ok:
        print("FAILED (%s skin):\n%s" % (skin, result))
        return False
    # The game's globals are read, never assigned: assigning one taints it.
    reassigned = sorted("%s (%s)" % (key, where) for key, where in written.items()
                        if key in before and not str(key).startswith("AegisPathfinder"))
    if reassigned:
        print("FAILED (%s skin): the game's globals assigned: %s" % (skin, ", ".join(reassigned)))
        return False
    # Globals the addon made: its own names only, nothing leaked from a missing `local`.
    after = set(lua.eval("function() local t = {} for k in pairs(_G) do t[#t + 1] = k end return t end")().values())
    stray = sorted(name for name in after - before
                   if not str(name).startswith(("AegisPathfinder", "SLASH_AEGISPATHFINDER", "BINDING_"))
                   and name not in ALLOWED_GLOBALS)
    if stray:
        print("FAILED (%s skin): globals leaked: %s" % (skin, ", ".join(map(str, stray))))
        return False
    # What goes out is checked here, where there are JSON, Base64 and zlib.
    export = lua.eval("WOWMOCK.export")
    header, _, body = export.partition("\n")
    assert header.startswith("AEGIS PATHFINDER FOREVER DATA;2;"), header
    assert header.endswith(";Brandy"), "the header ends with the credit name: " + header
    envelope = json.loads(body)
    check_envelope(envelope, "Brandy")
    code = lua.eval("WOWMOCK.shareCode")
    if skin == "blizzard-plain":
        assert code is None, "no share code without C_EncodingUtil"
    else:
        assert code.startswith("APF1:"), code[:20]
        coded = json.loads(zlib.decompress(base64.b64decode(code[5:], validate=True)).decode("utf-8"))
        check_envelope(coded, "Brandy")
        assert coded["data"] == envelope["data"], "the code and the text carry the same data"
    # And the GitHub side reads both the way it would from an issue.
    if ingest:
        for text in [export] + ([code] if code else []):
            found = ingest.decode("```\n" + text + "\n```")
            assert len(found) == 1, "ingest finds one submission, not %d" % len(found)
    print("%s skin: loaded %d files; %d guide steps match the collected data (%d not seen in it yet), %d book "
          "steps the book list; %s; text %.1f KB%s, decoded%s" % (
        skin, len(files), matched, unseen, bookSteps, result, len(export) / 1024,
        "; share code %.1f KB (the mock doesn't compress)" % (len(code) / 1024) if code
        else "; no share code (no C_EncodingUtil)",
        " and read by Tools/ingest.py" if ingest else ""))
    return True


def main():
    # The Blizzard skin twice: with the client's modern art, and on a client without it.
    ok = all([run("pathfinder"), run("blizzard"), run("blizzard-plain")])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
