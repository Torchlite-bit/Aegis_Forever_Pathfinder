"""
Loads the addon the way the client would (files in TOC order, sharing one namespace)
against Tools/wow_mock.lua, then runs Tools/smoke_scenario.lua: it starts the data
collector, plays a quest through from offer to turn-in, levels up, exports, and clicks
through every window -- once in each skin.

    python Tools/smoke_test.py

Needs the lupa package (pip install lupa), which bundles Lua 5.1, WoW's Lua version.
It checks the addon's own logic and that the export is valid JSON. It does not show
what the windows look like; only the game does that.
"""

import json
import os
import sys
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


def run(skin):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("date = os.date; time = os.time; debugstack = function() return debug.traceback() end")
    lua.execute(read(os.path.join(TOOLS, "wow_mock.lua")))
    # The saved variables as the client hands them over: empty, or with the skin chosen.
    if skin == "blizzard":
        lua.execute('AegisPathfinderDB = { profile = { theme = "blizzard" } }')

    before = set(lua.eval("function() local t = {} for k in pairs(_G) do t[#t + 1] = k end return t end")().values())
    load = lua.eval("""function(source, name, addon, ns)
        local chunk, err = loadstring(source, "@" .. name)
        if not chunk then error(err) end
        local ok, runErr = xpcall(function() return chunk(addon, ns) end, debug.traceback)
        if not ok then error(runErr) end
    end""")
    ns = lua.table()
    files = list(toc_files())
    for relative in files:
        if relative.lower().endswith(".xml"):
            ElementTree.parse(os.path.join(ROOT, relative))
            continue
        load(read(os.path.join(ROOT, relative)), relative, ADDON, ns)
    ElementTree.parse(os.path.join(ROOT, "Bindings.xml"))

    scenario = lua.eval("""function(source, ns, skin)
        local chunk = assert(loadstring(source, "@smoke_scenario.lua"))
        return xpcall(function() return chunk(ns, skin) end, debug.traceback)
    end""")
    ok, result = scenario(read(os.path.join(TOOLS, "smoke_scenario.lua")), ns, skin)
    if not ok:
        print("FAILED (%s skin):\n%s" % (skin, result))
        return False
    # Globals the addon made: its own names only, nothing leaked from a missing `local`.
    after = set(lua.eval("function() local t = {} for k in pairs(_G) do t[#t + 1] = k end return t end")().values())
    stray = sorted(name for name in after - before
                   if not str(name).startswith(("AegisPathfinder", "SLASH_AEGISPATHFINDER", "BINDING_"))
                   and name not in ALLOWED_GLOBALS)
    if stray:
        print("FAILED (%s skin): globals leaked: %s" % (skin, ", ".join(map(str, stray))))
        return False
    # The export is checked here, where there is a JSON parser.
    export = lua.eval("WOWMOCK.export")
    header, _, body = export.partition("\n")
    assert header.startswith("AEGIS PATHFINDER FOREVER DATA;1;"), header
    data = json.loads(body)
    quest = data["quests"]["176"]
    assert quest["title"] == "Wanted: Hogger", quest["title"]
    assert quest["rewards"]["xp"]["5"]["last"] == 1450, quest["rewards"]["xp"]
    assert "log" not in data, "the window's log is left out of the export"
    print("%s skin: loaded %d files; %s; export %.1f KB, valid JSON" % (skin, len(files), result, len(export) / 1024))
    return True


def main():
    ok = all([run("pathfinder"), run("blizzard")])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
