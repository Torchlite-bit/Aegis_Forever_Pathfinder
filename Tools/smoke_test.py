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


def run(skin):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("date = os.date; time = os.time; debugstack = function() return debug.traceback() end")
    lua.execute(read(os.path.join(TOOLS, "wow_mock.lua")))
    # The saved variables as the client hands them over: empty, or with the skin chosen.
    # "plain": a client without the modern art or C_EncodingUtil, to prove the fallbacks.
    if skin != "blizzard-plain":
        lua.execute("WOWMOCK.InstallModernArt()")
        lua.execute("WOWMOCK.InstallEncoding()")
    if skin.startswith("blizzard"):
        lua.execute('AegisPathfinderDB = { profile = { theme = "blizzard" } }')
    else:
        # A character 0.1.0 saved, with quest automation written as off.
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
    print("%s skin: loaded %d files; %s; text %.1f KB%s, decoded%s" % (
        skin, len(files), result, len(export) / 1024,
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
