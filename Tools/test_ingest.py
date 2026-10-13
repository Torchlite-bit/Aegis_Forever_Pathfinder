"""
Tests for Tools/ingest.py and Tools/ingest_issue.py: reading what players send
(share codes, exports, SavedVariables files, zip and gzip), turning away what
isn't safe, cleaning, storing without counting anything twice, making the
merged data and the credits again, and reading an issue.

    python Tools/test_ingest.py

Uses lupa (pip install lupa), when it is there, to load the generated
Contributors.lua in Lua; without it, its shape is checked instead.
"""

import base64
import contextlib
import copy
import gzip
import io
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import zipfile
import zlib
from unittest import mock

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)

import ingest  # noqa: E402
import ingest_issue  # noqa: E402
import merge_exports  # noqa: E402
import savedvariables  # noqa: E402

try:
    import lupa.lua51 as lupa  # WoW's Lua version, as Tools/smoke_test.py uses
except ImportError:
    try:
        import lupa
    except ImportError:
        lupa = None


##########################################################################################
# Test data: one collection, as the game saves it and as the addon exports it
##########################################################################################

COLLECTION_ID = "68e8a5c01a2b3c4d5e6f7a8b"

# The SavedVariables file, written the way WoW writes it: tabs, ["key"] = value,
# [number] keys, "-- [n]" after list items, escaped strings.
SAVED_VARIABLES = r'''
AegisPathfinderDB = {
	["profile"] = {
		["minimapangle"] = 215,
		["theme"] = "blizzard",
		["creditName"] = "Gary \"Goldshire\" O'Neil",
		["objframeopacity"] = 0.5,
		["showprogress"] = true,
	},
	["collect"] = {
		["schemaVersion"] = 1,
		["id"] = "68e8a5c01a2b3c4d5e6f7a8b",
		["created"] = 1760000000,
		["builds"] = {
			["1.60.1.70338"] = true,
		},
		["observers"] = {
			["Human:WARRIOR:Alliance"] = 3,
		},
		["levels"] = {
			{
				["xpMax"] = {
					["count"] = 1,
					["max"] = 400,
					["last"] = 400,
					["min"] = 400,
				},
				["builds"] = {
					["1.60.1.70338"] = true,
				},
				["by"] = {
					["Human:WARRIOR:Alliance"] = 1,
				},
				["first"] = 1760000010,
				["last"] = 1760000010,
			}, -- [1]
			{
				["xpMax"] = {
					["count"] = 2,
					["max"] = 900,
					["last"] = 900,
					["min"] = 900,
				},
				["seconds"] = {
					["count"] = 1,
					["max"] = 612,
					["last"] = 612,
					["min"] = 612,
				},
				["builds"] = {
					["1.60.1.70338"] = true,
				},
				["by"] = {
					["Human:WARRIOR:Alliance"] = 2,
				},
				["first"] = 1760000400,
				["last"] = 1760000500,
			}, -- [2]
		},
		["quests"] = {
			[176] = {
				["title"] = "Wanted: Hogger",
				["description"] = "A huge gnoll, \"Hogger\", roams the forest.\n\nBring me his claw. \\o/",
				["objectiveText"] = "Kill Hogger.",
				["level"] = 11,
				["frequency"] = 0,
				["objectives"] = {
					{
						["text"] = "Hogger slain",
						["type"] = "monster",
						["required"] = 1,
					}, -- [1]
				},
				["seen"] = {
					["offered"] = 1,
					["accepted"] = 1,
					["turnedIn"] = 1,
				},
				["pickups"] = {
					["npc:240@1429"] = {
						["kind"] = "npc",
						["id"] = 240,
						["name"] = "Marshal Dughan",
						["mapID"] = 1429,
						["zone"] = "Elwynn Forest",
						["subzone"] = "Goldshire",
						["x"] = 0.4215,
						["y"] = 0.659,
						["xMin"] = 0.4215,
						["xMax"] = 0.4215,
						["yMin"] = 0.659,
						["yMax"] = 0.659,
						["xyCount"] = 1,
						["count"] = 1,
						["playerLevel"] = {
							["count"] = 1,
							["max"] = 5,
							["last"] = 5,
							["min"] = 5,
						},
					},
				},
				["turnins"] = {
					["npc:240@1429"] = {
						["kind"] = "npc",
						["id"] = 240,
						["name"] = "Marshal Dughan",
						["mapID"] = 1429,
						["zone"] = "Elwynn Forest",
						["x"] = 0.4221,
						["y"] = 0.6588,
						["xMin"] = 0.4221,
						["xMax"] = 0.4221,
						["yMin"] = 0.6588,
						["yMax"] = 0.6588,
						["xyCount"] = 1,
						["count"] = 1,
					},
				},
				["progress"] = {
					{
						["1429:26:77"] = 1,
					}, -- [1]
				},
				["poi"] = {
					["turnin"] = {
						["1429:42:66"] = 1,
					},
				},
				["rewards"] = {
					["xp"] = {
						[5] = {
							["count"] = 1,
							["max"] = 1450,
							["last"] = 1450,
							["min"] = 1450,
						},
					},
					["xpOffered"] = {
						[5] = 1450,
					},
					["money"] = {
						["count"] = 1,
						["max"] = 500,
						["last"] = 500,
						["min"] = 500,
					},
					["choices"] = {
						[2224] = {
							["name"] = "Militia Dagger",
							["count"] = 1,
						},
					},
					["spells"] = {
						[8326] = true,
					},
					["reputation"] = {
						["Stormwind"] = {
							["factionID"] = 72,
							["count"] = 1,
							["max"] = 250,
							["last"] = 250,
							["min"] = 250,
						},
					},
					["chosen"] = {
						["WARRIOR"] = {
							[2224] = 1,
						},
					},
				},
				["builds"] = {
					["1.60.1.70338"] = true,
				},
				["by"] = {
					["Human:WARRIOR:Alliance"] = 3,
				},
				["first"] = 1760000100,
				["last"] = 1760000900,
			},
			[7] = {
				["title"] = "Kobold Camp Cleanup",
				["seen"] = {
					["offered"] = 1,
				},
				["pickups"] = {
				},
				["turnins"] = {
				},
				["rewards"] = {
				},
				["first"] = 1760000200,
				["last"] = 1760000200,
			},
		},
		["log"] = {
			"10:07  Offered \"Wanted: Hogger\"", -- [1]
			"10:09  Hogger slain", -- [2]
		},
	},
}
'''

# The same collection as the addon's JSON export writes it: keys as text,
# tables keyed 1..n as lists, empty tables as {}, the log left out.
COLLECT = {
    "schemaVersion": 1, "id": COLLECTION_ID, "created": 1760000000,
    "builds": {"1.60.1.70338": True},
    "observers": {"Human:WARRIOR:Alliance": 3},
    "levels": [
        {"xpMax": {"count": 1, "max": 400, "last": 400, "min": 400}, "builds": {"1.60.1.70338": True},
         "by": {"Human:WARRIOR:Alliance": 1}, "first": 1760000010, "last": 1760000010},
        {"xpMax": {"count": 2, "max": 900, "last": 900, "min": 900},
         "seconds": {"count": 1, "max": 612, "last": 612, "min": 612},
         "builds": {"1.60.1.70338": True}, "by": {"Human:WARRIOR:Alliance": 2},
         "first": 1760000400, "last": 1760000500},
    ],
    "quests": {
        "176": {
            "title": "Wanted: Hogger",
            "description": "A huge gnoll, \"Hogger\", roams the forest.\n\nBring me his claw. \\o/",
            "objectiveText": "Kill Hogger.", "level": 11, "frequency": 0,
            "objectives": [{"text": "Hogger slain", "type": "monster", "required": 1}],
            "seen": {"offered": 1, "accepted": 1, "turnedIn": 1},
            "pickups": {"npc:240@1429": {
                "kind": "npc", "id": 240, "name": "Marshal Dughan", "mapID": 1429, "zone": "Elwynn Forest",
                "subzone": "Goldshire", "x": 0.4215, "y": 0.659, "xMin": 0.4215, "xMax": 0.4215,
                "yMin": 0.659, "yMax": 0.659, "xyCount": 1, "count": 1,
                "playerLevel": {"count": 1, "max": 5, "last": 5, "min": 5}}},
            "turnins": {"npc:240@1429": {
                "kind": "npc", "id": 240, "name": "Marshal Dughan", "mapID": 1429, "zone": "Elwynn Forest",
                "x": 0.4221, "y": 0.6588, "xMin": 0.4221, "xMax": 0.4221, "yMin": 0.6588, "yMax": 0.6588,
                "xyCount": 1, "count": 1}},
            "progress": [{"1429:26:77": 1}],
            "poi": {"turnin": {"1429:42:66": 1}},
            "rewards": {
                "xp": {"5": {"count": 1, "max": 1450, "last": 1450, "min": 1450}},
                "xpOffered": {"5": 1450},
                "money": {"count": 1, "max": 500, "last": 500, "min": 500},
                "choices": {"2224": {"name": "Militia Dagger", "count": 1}},
                "spells": {"8326": True},
                "reputation": {"Stormwind": {"factionID": 72, "count": 1, "max": 250, "last": 250, "min": 250}},
                "chosen": {"WARRIOR": {"2224": 1}},
            },
            "builds": {"1.60.1.70338": True}, "by": {"Human:WARRIOR:Alliance": 3},
            "first": 1760000100, "last": 1760000900,
        },
        "7": {"title": "Kobold Camp Cleanup", "seen": {"offered": 1}, "pickups": {}, "turnins": {},
              "rewards": {}, "first": 1760000200, "last": 1760000200},
    },
}


def envelope(collect=None, contributor="Goldshire Gary", exported_at=1760001000, **extra):
    value = {
        "format": 2, "addon": "Aegis_Forever_Pathfinder", "addonVersion": "0.2.0",
        "build": "1.60.1.70338", "interface": 16001, "exportedAt": exported_at,
        "contributor": contributor, "data": copy.deepcopy(COLLECT if collect is None else collect),
    }
    value.update(extra)
    return value


def share_code(value):
    """A share code the way the addon makes one."""
    packed = zlib.compress(json.dumps(value).encode("utf-8"))
    return "APF1:" + base64.b64encode(packed).decode("ascii")


def plain_export(value, fmt=2):
    if fmt == 1:
        header = "AEGIS PATHFINDER FOREVER DATA;1;0.1.0;1.60.1.70338;16001;2025-10-09T08:56:40Z"
    else:
        header = "AEGIS PATHFINDER FOREVER DATA;2;0.2.0;1.60.1.70338;16001;2025-10-09T08:56:40Z;%s" % (
            value.get("contributor") or "")
    return header + "\n" + json.dumps(value, sort_keys=True, separators=(",", ":"))


def zip_bytes(members):
    """A zip of { name or ZipInfo: bytes }."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in members:
            archive.writestr(name, content)
    return buffer.getvalue()


def collection(collection_id, quests, created=1760000000):
    """A small collection of its own, for merging and dedupe tests."""
    return {
        "schemaVersion": 1, "id": collection_id, "created": created,
        "builds": {"1.60.1.70338": True}, "observers": {"Orc:SHAMAN:Horde": 1},
        "quests": {str(quest): {
            "title": "Quest %d" % quest, "seen": {"turnedIn": 1},
            "progress": {"1": {"1411:50:50": 2}},
            "rewards": {"xp": {"6": {"min": 100 + quest, "max": 100 + quest, "count": 1, "last": 100 + quest}}},
            "first": created + 10, "last": created + 20} for quest in quests},
    }


class TempRepo(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="ingest-test-")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def read(self, *parts):
        with open(os.path.join(self.root, *parts), encoding="utf-8") as handle:
            return handle.read()


##########################################################################################
# Reading what players send
##########################################################################################

class ShareCodes(unittest.TestCase):
    def test_round_trip(self):
        found = ingest.decode(share_code(envelope()))
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].kind, "share code")
        self.assertEqual(found[0].envelope["data"]["id"], COLLECTION_ID)
        self.assertEqual(found[0].envelope["contributor"], "Goldshire Gary")

    def test_spaces_line_breaks_and_a_code_fence(self):
        code = share_code(envelope())
        wrapped = "\n".join(code[index:index + 60] for index in range(0, len(code), 60))
        text = "Here you go!\n\n```\n  %s  \n```\n\nThanks for the addon" % wrapped
        found = ingest.decode(text)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].envelope["data"]["quests"]["176"]["title"], "Wanted: Hogger")

    def test_two_codes_in_one_text(self):
        first = share_code(envelope())
        second = share_code(envelope(collection("aaaa1111", [33]), contributor="Second"))
        found = ingest.decode("first:\n%s\n\nand my alt:\n%s\n" % (first, second))
        self.assertEqual([item.envelope["contributor"] for item in found], ["Goldshire Gary", "Second"])

    def test_text_straight_after_a_code(self):
        # Codes of a few lengths (ending in "=", "==" or neither), then words: the words are ignored.
        value = envelope()
        for padding in range(3):
            value["addonVersion"] = "0.2." + "0" * padding
            code = share_code(value)
            found = ingest.decode(code + " thanks for all the fish")
            self.assertEqual(len(found), 1, code[-4:])

    def test_cut_short_code_is_explained(self):
        code = share_code(envelope())
        problems = []
        self.assertEqual(ingest.decode(code[:len(code) // 2], problems=problems), [])
        self.assertTrue(any(re.search("cut short|damaged|letters missing", problem) for problem in problems),
                        problems)

    def test_changed_code_is_explained(self):
        code = share_code(envelope())
        broken = code[:200] + ("A" if code[200] != "A" else "B") + code[201:]
        problems = []
        self.assertEqual(ingest.decode(broken, problems=problems), [])
        self.assertTrue(problems)

    def test_nothing_found_raises_without_a_problems_list(self):
        with self.assertRaises(ingest.IngestError):
            ingest.decode("just some words")


class PlainExports(unittest.TestCase):
    def test_format_2(self):
        found = ingest.decode(plain_export(envelope()))
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].kind, "export")
        self.assertEqual(found[0].envelope["contributor"], "Goldshire Gary")
        self.assertEqual(found[0].envelope["exportedAt"], 1760001000)

    def test_format_2_takes_the_name_from_the_header_if_needed(self):
        value = envelope(contributor="")
        text = plain_export(value).replace(";2025-10-09T08:56:40Z;", ";2025-10-09T08:56:40Z;Header Name")
        found = ingest.decode(text)
        self.assertEqual(found[0].envelope["contributor"], "Header Name")

    def test_format_1(self):
        found = ingest.decode("```\n" + plain_export(COLLECT, fmt=1) + "\n```")
        self.assertEqual(len(found), 1)
        value = found[0].envelope
        self.assertEqual(value["format"], 1)
        self.assertEqual(value["addonVersion"], "0.1.0")
        self.assertEqual(value["interface"], 16001)
        self.assertEqual(value["exportedAt"], 1760000200)  # 2025-10-09T08:56:40Z
        self.assertIsNone(value["contributor"])
        self.assertEqual(value["data"]["quests"]["176"]["title"], "Wanted: Hogger")

    def test_header_without_data(self):
        problems = []
        self.assertEqual(ingest.decode("AEGIS PATHFINDER FOREVER DATA;2;0.2.0;1.60.1.70338;16001;x\n",
                                       problems=problems), [])
        self.assertIn("first line", problems[0])


class SavedVariablesFiles(unittest.TestCase):
    def test_file_becomes_the_same_envelope(self):
        found = ingest.decode(SAVED_VARIABLES.encode("utf-8"), "Aegis_Forever_Pathfinder.lua")
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].kind, "data file")
        from_file = ingest.sanitize(found[0].envelope)
        from_export = ingest.sanitize(envelope())
        # Same data either way: [176] -> "176", levels 1..2 -> "1", "2", the log left out.
        self.assertEqual(from_file["data"], from_export["data"])
        self.assertEqual(sorted(from_file["data"]["levels"]), ["1", "2"])
        self.assertEqual(sorted(from_file["data"]["quests"]), ["176", "7"])
        self.assertNotIn("log", from_file["data"])
        self.assertEqual(from_file["data"]["quests"]["176"]["description"],
                         "A huge gnoll, \"Hogger\", roams the forest.\n\nBring me his claw. \\o/")
        # The name set in game, cleaned; the newest stamp stands in for the export time.
        self.assertEqual(from_file["contributor"], "Gary Goldshire ONeil")
        self.assertEqual(from_file["exportedAt"], 1760000900)
        self.assertEqual(from_file["build"], "1.60.1.70338")

    def test_renamed_txt_with_windows_line_ends_and_bom(self):
        content = ("\ufeff" + SAVED_VARIABLES.replace("\n", "\r\n")).encode("utf-8")
        found = ingest.decode(content, "Aegis_Forever_Pathfinder.txt")
        self.assertEqual(len(found), 1)

    def test_pasted_in_a_code_fence(self):
        text = "My file:\n```lua\n%s\n```\nbye" % SAVED_VARIABLES
        found = ingest.decode(text)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].kind, "data file")

    def test_file_without_collected_data(self):
        problems = []
        self.assertEqual(ingest.decode('AegisPathfinderDB = { ["profile"] = { ["theme"] = "day" } }',
                                       "x.lua", problems), [])
        self.assertIn("no collected data", problems[0])

    def test_code_in_a_data_file_is_refused(self):
        attacks = [
            'AegisPathfinderDB = { ["collect"] = os.execute("echo pwned") }',
            'AegisPathfinderDB = loadstring("os.exit()")()',
            'AegisPathfinderDB = {}\nos.exit(1)',
            'local x = 1\nAegisPathfinderDB = { ["collect"] = {} }',
            'AegisPathfinderDB = { ["collect"] = function() os.exit() end }',
            'AegisPathfinderDB = { ["collect"] = { ["id"] = "a" .. "b" } }',
            'AegisPathfinderDB = setmetatable({}, { __index = os })',
        ]
        for attack in attacks:
            problems = []
            self.assertEqual(ingest.decode(attack, "evil.lua", problems), [], attack)
            self.assertTrue(any("not plain saved data" in problem for problem in problems), (attack, problems))


class Archives(unittest.TestCase):
    def test_zip(self):
        content = zip_bytes([("Aegis_Forever_Pathfinder.txt", SAVED_VARIABLES.encode("utf-8")),
                             ("__MACOSX/._Aegis_Forever_Pathfinder.txt", b"\x00\x05junk")])
        found = ingest.decode(content, "data.zip")
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].origin, "Aegis_Forever_Pathfinder.txt")

    def test_zip_with_a_share_code_and_an_export(self):
        content = zip_bytes([("code.txt", share_code(envelope()).encode()),
                             ("export.txt", plain_export(envelope(collection("bbbb2222", [12]))).encode())])
        self.assertEqual(len(ingest.decode(content, "two.zip")), 2)

    def test_gzip(self):
        found = ingest.decode(gzip.compress(SAVED_VARIABLES.encode("utf-8")), "Aegis_Forever_Pathfinder.lua.gz")
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].origin, "Aegis_Forever_Pathfinder.lua")

    def refused(self, content, words):
        problems = []
        self.assertEqual(ingest.decode(content, "bad.zip", problems), [])
        self.assertTrue(any(words in problem for problem in problems), problems)

    def test_zip_slip_is_refused_whole(self):
        good = ("good.txt", share_code(envelope()).encode())
        self.refused(zip_bytes([good, ("../evil.txt", b"x")]), "outside")
        self.refused(zip_bytes([good, ("data/../../evil.txt", b"x")]), "outside")
        self.refused(zip_bytes([good, (zipfile.ZipInfo("/etc/evil.txt"), b"x")]), "absolute")
        self.refused(zip_bytes([good, ("C:/evil.txt", b"x")]), "absolute")
        link = zipfile.ZipInfo("link.txt")
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.refused(zip_bytes([good, (link, b"/etc/passwd")]), "link")

    def test_too_many_files(self):
        self.refused(zip_bytes([("f%d.txt" % index, b"x") for index in range(21)]), "more than 20")

    def test_zip_bomb(self):
        self.refused(zip_bytes([("big.txt", b"\0" * (ingest.MAX_UNPACKED + 1))]), "more than 50 MB")

    def test_gzip_bomb(self):
        problems = []
        self.assertEqual(ingest.decode(gzip.compress(b"\0" * (ingest.MAX_UNPACKED + 1)), "big.gz", problems), [])
        self.assertIn("more than 50 MB", problems[0])

    def test_archive_in_an_archive(self):
        inner = zip_bytes([("code.txt", share_code(envelope()).encode())])
        self.refused(zip_bytes([("inner.zip", inner)]), "inside an archive")

    def test_input_over_25_mb(self):
        problems = []
        self.assertEqual(ingest.decode(b"x" * (ingest.MAX_INPUT + 1), "huge.txt", problems), [])
        self.assertIn("bigger than 25 MB", problems[0])


##########################################################################################
# Cleaning
##########################################################################################

class Sanitizer(unittest.TestCase):
    def test_unknown_fields_are_dropped(self):
        value = envelope(evil="x")
        value["data"]["evil"] = {"a": 1}
        value["data"]["log"] = ["secret"]
        quest = value["data"]["quests"]["176"]
        quest["script"] = "os.exit()"
        quest["pickups"]["npc:240@1429"]["onClick"] = "x"
        quest["rewards"]["hack"] = 1
        quest["objectives"][0]["html"] = "<b>"
        clean = ingest.sanitize(value)
        self.assertNotIn("evil", clean)
        self.assertNotIn("evil", clean["data"])
        self.assertNotIn("log", clean["data"])
        quest = clean["data"]["quests"]["176"]
        self.assertNotIn("script", quest)
        self.assertNotIn("onClick", quest["pickups"]["npc:240@1429"])
        self.assertNotIn("hack", quest["rewards"])
        self.assertEqual(quest["objectives"], [{"text": "Hogger slain", "type": "monster", "required": 1}])

    def test_bad_numbers_are_dropped(self):
        text = json.dumps(envelope())
        value = json.loads(text)
        quest = value["data"]["quests"]["176"]
        quest["level"] = float("nan")
        quest["seen"]["offered"] = -3
        quest["seen"]["accepted"] = True
        quest["seen"]["turnedIn"] = 2.5
        quest["rewards"]["money"] = {"min": float("inf"), "max": "500", "count": 1}
        quest["pickups"]["npc:240@1429"]["x"] = 1.5
        quest["requiredMoney"] = 10 ** 20
        value["data"]["levels"][0]["xpMax"]["count"] = -1
        value["exportedAt"] = 99
        value["interface"] = "16001"
        clean = ingest.sanitize(value)
        quest = clean["data"]["quests"]["176"]
        self.assertNotIn("level", quest)
        self.assertNotIn("seen", quest)
        self.assertNotIn("money", quest["rewards"])
        self.assertNotIn("requiredMoney", quest)
        place = quest["pickups"]["npc:240@1429"]
        for key in ("x", "y", "xMin", "xMax", "yMin", "yMax", "xyCount"):
            self.assertNotIn(key, place)  # a position is kept whole or not at all
        self.assertEqual(clean["data"]["levels"]["1"]["xpMax"]["count"], 1)
        self.assertEqual(clean["exportedAt"], 1760000900)  # out of range: the newest stamp instead
        self.assertIsNone(clean["interface"])

    def test_nan_from_json_text(self):
        text = json.dumps(envelope()).replace('"level": 11', '"level": NaN')
        clean = ingest.sanitize(ingest.decode(share_code(json.loads(text)))[0].envelope)
        self.assertNotIn("level", clean["data"]["quests"]["176"])

    def test_keys_must_be_numbers_where_the_game_uses_numbers(self):
        value = envelope()
        quests = value["data"]["quests"]
        for key in ("abc", "-5", "1e3", "176.5", " 12", "99999999999"):
            quests[key] = {"title": "x"}
        quests["0012"] = {"title": "padded"}
        value["data"]["levels"] = {"1": {"xpMax": {"min": 1, "max": 1, "count": 1, "last": 1}},
                                   "999": {"xpMax": {"min": 1, "max": 1, "count": 1, "last": 1}},
                                   "two": {}}
        clean = ingest.sanitize(value)
        self.assertEqual(sorted(clean["data"]["quests"]), ["12", "176", "7"])
        self.assertEqual(list(clean["data"]["levels"]), ["1"])

    def test_sizes_are_capped(self):
        value = envelope()
        value["data"]["quests"] = {str(index): {"title": "q"} for index in range(1, 20006)}
        value["data"]["levels"] = [{"xpMax": {"min": 1, "max": 1, "count": 1, "last": 1}}] * 150
        value["data"]["quests"]["1"]["description"] = "x" * 5000
        value["data"]["quests"]["2"]["progress"] = {"1": {"1429:%d:%d" % (index % 100, index // 100): index + 1
                                                          for index in range(60)}}
        clean = ingest.sanitize(value)
        self.assertEqual(len(clean["data"]["quests"]), ingest.MAX_QUESTS)
        self.assertNotIn("20005", clean["data"]["quests"])
        self.assertEqual(len(clean["data"]["levels"]), ingest.MAX_LEVELS)
        self.assertEqual(len(clean["data"]["quests"]["1"]["description"]), ingest.MAX_TEXT)
        cells = clean["data"]["quests"]["2"]["progress"]["1"]
        self.assertEqual(len(cells), 40)
        self.assertEqual(min(cells.values()), 21)  # the 40 seen most often

    def test_wrong_types_are_dropped_not_raised(self):
        # Found by fuzzing: a table where a word belongs raised TypeError, and the
        # whole issue was answered as our own error.
        for kind in ([], {}, ["npc"], {"npc": 1}, 3, None):
            value = envelope()
            value["data"]["quests"]["176"]["pickups"]["npc:240@1429"]["kind"] = kind
            place = ingest.sanitize(value)["data"]["quests"]["176"]["pickups"]["npc:240@1429"]
            self.assertEqual(place["kind"], "unknown")

    def test_other_addons_data_is_refused(self):
        with self.assertRaises(ingest.IngestError):
            ingest.sanitize(envelope(addon="SomethingElse"))

    def test_sanitize_is_stable(self):
        once = ingest.sanitize(envelope())
        self.assertEqual(ingest.sanitize(json.loads(json.dumps(once))), once)

    def test_names(self):
        self.assertEqual(ingest.clean_name("  Goldshire   Gary  "), "Goldshire Gary")
        self.assertIsNone(ingest.clean_name("   "))
        self.assertIsNone(ingest.clean_name(None))
        self.assertIsNone(ingest.clean_name(42))
        self.assertEqual(ingest.clean_name("@everyone"), "everyone")
        name = ingest.clean_name('<script>"x"</script> `rm` \\ \u202e\x00\nBob\u200b')
        self.assertFalse(re.search("[<>\"'`\\\\@\u202e\u200b\x00\n]", name), name)
        self.assertEqual(ingest.clean_name("Thrall"), "Thrall")
        self.assertEqual(ingest.clean_name("Ñandú Жук"), "Ñandú Жук")
        self.assertEqual(len(ingest.clean_name("x" * 100)), ingest.MAX_NAME)


##########################################################################################
# Storing without counting anything twice
##########################################################################################

class Store(TempRepo):
    def store(self, exported_at, received, contributor="Gary", login=None, collect=None):
        return ingest.store(envelope(collect, contributor=contributor, exported_at=exported_at), self.root,
                            {"kind": "file", "received": received, "github_login": login})

    def stored(self):
        return json.loads(self.read("data", "submissions", COLLECTION_ID + ".json"))

    def test_newest_copy_replaces_and_older_is_ignored(self):
        self.assertEqual(self.store(1760001000, "2025-10-10T00:00:00Z").status, "new")
        newer = envelope(exported_at=1760002000)
        newer["data"]["quests"]["176"]["seen"]["turnedIn"] = 2
        result = ingest.store(newer, self.root, {"received": "2025-10-11T00:00:00Z"})
        self.assertEqual(result.status, "replaced")
        self.assertEqual(self.store(1760001500, "2025-10-12T00:00:00Z").status, "older")
        kept = self.stored()
        self.assertEqual(kept["exportedAt"], 1760002000)
        self.assertEqual(kept["data"]["quests"]["176"]["seen"]["turnedIn"], 2)
        self.assertEqual(kept["source"]["first_received"], "2025-10-10T00:00:00Z")
        self.assertEqual(kept["source"]["received"], "2025-10-11T00:00:00Z")
        self.assertEqual(len(os.listdir(os.path.join(self.root, "data", "submissions"))), 1)

    def test_same_copy_again_changes_nothing(self):
        self.store(1760001000, "2025-10-10T00:00:00Z")
        before = self.read("data", "submissions", COLLECTION_ID + ".json")
        self.assertEqual(self.store(1760001000, "2025-10-11T00:00:00Z").status, "unchanged")
        self.assertEqual(self.store(1760001000, "2025-10-11T00:00:00Z", contributor=None).status, "unchanged")
        self.assertEqual(self.read("data", "submissions", COLLECTION_ID + ".json"), before)

    def test_tie_goes_to_the_one_received_later(self):
        self.store(1760001000, "2025-10-10T00:00:00Z")
        self.assertEqual(self.store(1760001000, "2025-10-11T00:00:00Z", contributor="New Name").status, "replaced")
        self.assertEqual(self.stored()["contributor"], "New Name")
        self.assertEqual(self.store(1760001000, "2025-10-09T00:00:00Z", contributor="Old Name").status, "older")

    def test_a_copy_without_a_name_keeps_the_name(self):
        self.store(1760001000, "2025-10-10T00:00:00Z", contributor="Gary")
        self.assertEqual(self.store(1760002000, "2025-10-11T00:00:00Z", contributor=None).status, "replaced")
        self.assertEqual(self.stored()["contributor"], "Gary")

    def test_another_github_account_cant_replace_it(self):
        self.store(1760001000, "2025-10-10T00:00:00Z", login="gary")
        self.assertEqual(self.store(1760009000, "2025-10-11T00:00:00Z", login="mallory").status, "taken")
        self.assertEqual(self.stored()["exportedAt"], 1760001000)
        self.assertEqual(self.store(1760009000, "2025-10-11T00:00:00Z", login="Gary").status, "replaced")

    def test_a_maintainers_copy_cant_be_taken_from_github(self):
        # Collection ids are public: one a maintainer added from a file isn't anyone's to claim.
        self.store(1760001000, "2025-10-10T00:00:00Z")
        self.assertEqual(self.store(1760009000, "2025-10-11T00:00:00Z", login="mallory").status, "taken")
        self.assertIsNone(self.stored()["source"]["github_login"])
        self.assertEqual(self.store(1760009000, "2025-10-11T00:00:00Z").status, "replaced")

    def test_a_maintainers_resend_keeps_the_owner(self):
        self.store(1760001000, "2025-10-10T00:00:00Z", login="gary")
        self.assertEqual(self.store(1760009000, "2025-10-11T00:00:00Z").status, "replaced")
        self.assertEqual(self.stored()["source"]["github_login"], "gary")
        self.assertEqual(self.store(1760019000, "2025-10-12T00:00:00Z", login="gary").status, "replaced")

    def test_the_account_number_decides_not_the_login(self):
        def send(exported_at, received, login, number):
            return ingest.store(envelope(exported_at=exported_at), self.root,
                                {"received": received, "github_login": login, "github_id": number}).status
        send(1760001000, "2025-10-10T00:00:00Z", "gary", 101)
        self.assertEqual(send(1760002000, "2025-10-11T00:00:00Z", "gary-renamed", 101), "replaced")
        # Someone who took the old login after the rename:
        self.assertEqual(send(1760003000, "2025-10-12T00:00:00Z", "gary", 202), "taken")

    def test_a_far_future_date_cant_lock_a_collection(self):
        self.store(4102444000, "2025-10-10T00:00:00Z", login="gary")
        self.assertEqual(self.stored()["exportedAt"], 1760054400 + 86400)  # a day past arriving, at most
        self.assertEqual(self.store(1760150000, "2025-10-12T00:00:00Z", login="gary").status, "replaced")

    def test_the_copy_that_holds_more_is_the_newer(self):
        # A data file has no export time (its newest stamp stands in), and much of what
        # the addon adds stamps nothing: a file holding more must still win.
        self.store(1760005000, "2025-10-10T00:00:00Z")
        more = envelope(exported_at=1760001000)
        more["data"]["quests"]["176"]["seen"]["offered"] += 3
        self.assertEqual(ingest.store(more, self.root, {"received": "2025-10-11T00:00:00Z"}).status, "replaced")
        self.assertEqual(self.store(1760009000, "2025-10-12T00:00:00Z").status, "older")

    def test_a_resend_without_a_name_keeps_the_chosen_one(self):
        source = {"received": "2025-10-10T00:00:00Z", "github_login": "gary-g"}
        ingest.store(envelope(contributor="Chosen Name"), self.root, source, fallback_name="gary-g")
        again = ingest.store(envelope(contributor=None, exported_at=1760002000), self.root,
                             dict(source, received="2025-10-11T00:00:00Z"), fallback_name="gary-g")
        self.assertEqual((again.status, self.stored()["contributor"]), ("replaced", "Chosen Name"))
        other = ingest.store(envelope(collection("eeee0001", [1]), contributor=None), self.root, source,
                             fallback_name="gary-g")
        self.assertEqual(other.contributor, "gary-g")

    def test_no_id_gets_one_from_its_content(self):
        collect = copy.deepcopy(COLLECT)
        del collect["id"]
        first = self.store(1760001000, "2025-10-10T00:00:00Z", collect=collect)
        self.assertRegex(first.id, "^[0-9a-f]{64}$")
        self.assertEqual(self.store(1760001000, "2025-10-11T00:00:00Z", collect=collect).id, first.id)

    def test_empty_collection_is_refused(self):
        with self.assertRaises(ingest.IngestError):
            ingest.store(envelope({"schemaVersion": 1, "id": "abc", "quests": {}, "levels": {}}), self.root)

    def test_hostile_id_cant_choose_the_file_name(self):
        collect = copy.deepcopy(COLLECT)
        collect["id"] = "../../Contributors"
        result = self.store(1760001000, "2025-10-10T00:00:00Z", collect=collect)
        self.assertRegex(result.id, "^[0-9a-f]{64}$")
        self.assertEqual(os.path.dirname(result.path), os.path.join(self.root, "data", "submissions"))


##########################################################################################
# Making the merged data and the credits again
##########################################################################################

HOSTILE_NAME = 'Evil"; os.exit(1) --[[ <script>alert(1)</script> ]] `x` \\ @everyone |cffff0000red|r\n\u202e'


def load_contributors_lua(text):
    """The names Contributors.lua gives the addon, run in Lua with nothing
    dangerous reachable (no os, no io)."""
    runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
    run = runtime.eval("""function(source)
        os, io, require, dofile, loadfile = nil, nil, nil, nil, nil
        local chunk, err = (loadstring or load)(source, "@Contributors.lua")
        if not chunk then return nil, err end
        local AP = {}
        local ok, runErr = pcall(chunk, "Aegis_Forever_Pathfinder", AP)
        if not ok then return nil, runErr end
        local names = {}
        for index, name in ipairs(AP.CONTRIBUTORS) do
            if type(name) ~= "string" then return nil, "not a string" end
            names[index] = name
        end
        local count = 0
        for _ in pairs(AP.CONTRIBUTORS) do count = count + 1 end
        if count ~= #names then return nil, "not a plain list" end
        return names, nil
    end""")
    names, error = run(text)
    if names is None:
        raise AssertionError("Contributors.lua does not load: %s" % error)
    return [names[index] for index in range(1, len(names) + 1)]


class Rebuild(TempRepo):
    def fill(self, order=(0, 1, 2, 3)):
        stores = [
            (envelope(collection("aaaa0001", [1, 2], created=1760000000), contributor="Alice",
                      exported_at=1760000100), {"received": "2025-10-01T00:00:00Z", "github_login": "alice"}),
            (envelope(collection("bbbb0002", [2, 3], created=1760500000), contributor=HOSTILE_NAME,
                      exported_at=1760500100), {"received": "2025-10-02T00:00:00Z", "github_login": "mallory"}),
            (envelope(collection("cccc0003", [4], created=1760600000), contributor=None,
                      exported_at=1760600100), {"received": "2025-10-03T00:00:00Z"}),
            (envelope(collection("dddd0004", [5], created=1760700000), contributor="alice",
                      exported_at=1760700100), {"received": "2025-10-04T00:00:00Z", "github_login": "alice"}),
        ]
        for index in order:
            value, source = stores[index]
            ingest.store(value, self.root, dict(source, kind="github-issue", issue=index + 1))

    def outputs(self):
        return [self.read(*parts) for parts in (("data", "merged.json"), ("data", "contributors.json"),
                                                ("Contributors.lua",), ("CONTRIBUTORS.md",))]

    def test_merged_data(self):
        self.fill()
        totals = ingest.rebuild(self.root)
        self.assertEqual(totals["submissions"], 4)
        merged = json.loads(self.read("data", "merged.json"))
        quest = merged["quests"]["2"]
        self.assertEqual(quest["seen"]["turnedIn"], 2)              # counts add up
        self.assertEqual(quest["progress"]["1"]["1411:50:50"], 4)   # map cells too
        self.assertEqual(quest["rewards"]["xp"]["6"]["count"], 2)
        self.assertEqual(merged["observers"]["Orc:SHAMAN:Horde"], 4)
        self.assertEqual(merged["created"], 1760000000)
        self.assertNotIn("id", merged)
        self.assertEqual([source["id"] for source in merged["sources"]],
                         ["aaaa0001", "bbbb0002", "cccc0003", "dddd0004"])

    def test_contributors(self):
        self.fill()
        ingest.rebuild(self.root)
        contributors = json.loads(self.read("data", "contributors.json"))
        self.assertEqual([entry["name"] for entry in contributors],
                         ["Alice", ingest.clean_name(HOSTILE_NAME), "Anonymous"])
        alice = contributors[0]
        self.assertEqual((alice["github"], alice["submissions"], alice["quests"]), ("alice", 2, 3))
        self.assertEqual((alice["first"], alice["last"]), ("2025-10-01T00:00:00Z", "2025-10-04T00:00:00Z"))
        markdown = self.read("CONTRIBUTORS.md")
        self.assertIn("[Alice](https://github.com/alice)", markdown)
        self.assertIn("1 collection sent without a name", markdown)
        self.assertNotIn("<script>", markdown)
        self.assertNotIn("@everyone", markdown)

    def test_reward_items_without_names_merge(self):
        # The game doesn't always know an item's name yet: such an item is {"count": n},
        # which once looked like a number range to the merge and stopped it.
        for index, collection_id in enumerate(("aaaa0001", "bbbb0002")):
            collect = collection(collection_id, [5])
            collect["quests"]["5"]["rewards"]["items"] = {"2224": {"count": index + 1}}
            ingest.store(envelope(collect), self.root, {"received": "2025-10-1%dT00:00:00Z" % index})
        ingest.rebuild(self.root)
        merged = json.loads(self.read("data", "merged.json"))
        self.assertEqual(merged["quests"]["5"]["rewards"]["items"]["2224"], {"count": 1})

    def test_merged_in_the_order_collections_arrived(self):
        # Not by "created", which the sender chooses: the first sent keeps its text.
        first, second = collection("aaaa0001", [5]), collection("bbbb0002", [5], created=1000000000)
        first["quests"]["5"]["title"], second["quests"]["5"]["title"] = "First sent", "Sent later"
        ingest.store(envelope(first), self.root, {"received": "2025-10-10T00:00:00Z"})
        ingest.store(envelope(second), self.root, {"received": "2025-10-11T00:00:00Z"})
        ingest.rebuild(self.root)
        self.assertEqual(json.loads(self.read("data", "merged.json"))["quests"]["5"]["title"], "First sent")

    def test_contributors_lua_is_safe(self):
        self.fill()
        ingest.rebuild(self.root)
        text = self.read("Contributors.lua")
        self.assertTrue(text.startswith("local _, AP = ...\n"))
        self.assertIn("Generated by Tools/ingest.py from data/contributors.json", text)
        ingest.check_contributors_lua(text)
        expected = ["Alice", ingest.lua_name(ingest.clean_name(HOSTILE_NAME))]
        self.assertTrue(expected[1])
        self.assertNotIn("|", expected[1])
        self.assertNotIn('"', expected[1])
        if lupa:
            self.assertEqual(load_contributors_lua(text), expected)
        for line in text.split("\n"):
            self.assertNotIn("os.exit", line.split('"')[0])  # never outside a string

    def test_lua_strings_never_break_out(self):
        if not lupa:
            self.skipTest("lupa is not installed")
        runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
        for text in ['plain', 'a"b', "a'b", "back\\slash", "new\nline", "\x00\x01\x7f", "]]--[[", "é ж 名",
                     "\u202eright to left", "trailing\\", "12\x003"]:
            literal = ingest.lua_string(text)
            self.assertNotIn("\n", literal)
            self.assertEqual(runtime.eval(literal), text, literal)

    def test_empty_list(self):
        ingest.rebuild(self.root)
        text = self.read("Contributors.lua")
        self.assertIn("AP.CONTRIBUTORS = {\n}\n", text)
        if lupa:
            self.assertEqual(load_contributors_lua(text), [])
        self.assertEqual(json.loads(self.read("data", "contributors.json")), [])
        self.assertIn("No one yet", self.read("CONTRIBUTORS.md"))

    def test_the_same_submissions_give_the_same_files(self):
        self.fill()
        ingest.rebuild(self.root)
        first = self.outputs()
        ingest.rebuild(self.root)
        self.assertEqual(self.outputs(), first)
        # A second repository, the same submissions stored in another order.
        saved, self.root = self.root, tempfile.mkdtemp(prefix="ingest-test-")
        try:
            self.fill(order=(3, 1, 0, 2))
            ingest.rebuild(self.root)
            self.assertEqual(self.outputs(), first)
        finally:
            shutil.rmtree(self.root, ignore_errors=True)
            self.root = saved

    def test_contributors_md_keeps_what_is_outside_the_markers(self):
        path = os.path.join(self.root, "CONTRIBUTORS.md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("# Thanks\n\nCode by people.\n\n%s\nold list\n%s\n\nFooter stays.\n"
                         % (ingest.MARK_START, ingest.MARK_END))
        self.fill()
        ingest.rebuild(self.root)
        text = self.read("CONTRIBUTORS.md")
        self.assertTrue(text.startswith("# Thanks\n\nCode by people.\n\n" + ingest.MARK_START))
        self.assertTrue(text.endswith(ingest.MARK_END + "\n\nFooter stays.\n"))
        self.assertNotIn("old list", text)
        self.assertEqual(text.count(ingest.MARK_START), 1)

    def test_command_line(self):
        path = os.path.join(self.root, "from-discord.lua")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(SAVED_VARIABLES)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(ingest.main([path, "--credit", "Discord Dan", "--root", self.root]), 0)
        self.assertIn("new", output.getvalue())
        contributors = json.loads(self.read("data", "contributors.json"))
        self.assertEqual(contributors[0]["name"], "Discord Dan")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ingest.main([path, "--root", self.root]), 0)  # again: still taken in
            empty = os.path.join(self.root, "empty.txt")
            open(empty, "w").close()
            self.assertEqual(ingest.main([empty, "--root", self.root]), 2)


##########################################################################################
# The issue form
##########################################################################################

REPOSITORY = "Torchlite-bit/Aegis_Pathfinder_Forever"


def issue_body(credit="Goldshire Gary", data="", notes="_No response_"):
    return "### Credit me as\n\n%s\n\n### Share code or data file\n\n%s\n\n### Anything to add\n\n%s\n" % (
        credit, data, notes)


class IssueForm(TempRepo):
    def run_issue(self, body, downloads=None, login="gary-g"):
        downloads = downloads or {}
        summary = os.path.join(self.root, "summary.md")
        outputs = os.path.join(self.root, "outputs.txt")
        # As the workflow passes it: the issue's text in a file.
        body_file = os.path.join(self.root, "body.md")
        with open(body_file, "w", encoding="utf-8", newline="") as handle:
            handle.write(body)
        environ = {"ISSUE_NUMBER": "42", "ISSUE_BODY_FILE": body_file, "ISSUE_USER": login, "REPO_ROOT": self.root,
                   "GITHUB_REPOSITORY": REPOSITORY, "SUMMARY_PATH": summary, "GITHUB_OUTPUT": outputs}
        fetched = []

        def fake_fetch(url):
            fetched.append(url)
            if url not in downloads:
                raise ingest.IngestError("it could not be downloaded (404).")
            return downloads[url]

        with mock.patch.object(ingest_issue, "fetch", fake_fetch), contextlib.redirect_stdout(io.StringIO()):
            status = ingest_issue.main(environ)
        with open(summary, encoding="utf-8") as handle:
            text = handle.read()
        with open(outputs, encoding="utf-8") as handle:
            values = dict(line.split("=", 1) for line in handle.read().splitlines())
        return status, text, values, fetched

    def test_parse_form(self):
        answers = ingest_issue.parse_form(issue_body(data="APF1:abc", notes="Played Elwynn.\n\n### Credit me as\n\nX"))
        self.assertEqual(answers["credit me as"], "Goldshire Gary")  # the form's own heading wins
        self.assertEqual(answers["share code or data file"], "APF1:abc")
        self.assertTrue(answers["anything to add"].startswith("Played Elwynn."))
        self.assertEqual(ingest_issue.parse_form(issue_body(credit="_No response_"))["credit me as"], "")
        self.assertIsNone(ingest_issue.credit_from_form(issue_body(credit="_No response_")))
        self.assertEqual(ingest_issue.credit_from_form(issue_body(credit='"<b>Gary</b>" @all')), "bGary/b all")

    def test_only_github_attachments_are_fetched(self):
        body = "\n".join([
            "[ok.txt](https://github.com/user-attachments/files/123/ok.txt)",
            "https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever/files/456/old.zip",
            "https://github.com/someone/else/files/789/x.zip",
            "https://github.com.evil.example/user-attachments/files/1/x.txt",
            "http://github.com/user-attachments/files/1/plain-http.txt",
            "https://evil.example/https://github.com/user-attachments/files/1/x.txt",
            "https://raw.githubusercontent.com/x/y/main/z.txt",
            "https://github.com/user-attachments/assets/0f1e2d3c-image",
            "https://github.com/user-attachments/files/123/ok.txt",
        ])
        self.assertEqual(ingest_issue.attachment_urls(body, REPOSITORY), [
            "https://github.com/user-attachments/files/123/ok.txt",
            "https://github.com/Torchlite-bit/Aegis_Pathfinder_Forever/files/456/old.zip",
        ])
        self.assertEqual(len(ingest_issue.attachment_urls(body, None)), 1)

    def test_downloads_stay_on_github(self):
        allowed = ingest_issue.allowed_host
        self.assertTrue(allowed("https://github.com/user-attachments/files/1/x.txt"))
        self.assertTrue(allowed("https://objects.githubusercontent.com/github-production/x"))
        for url in ("http://github.com/x", "https://evilgithub.com/x", "https://github.com.evil.example/x",
                    "https://githubusercontent.com.evil.example/x", "file:///etc/passwd", "ftp://github.com/x"):
            self.assertFalse(allowed(url), url)
        handler = ingest_issue._GitHubRedirectsOnly()
        request = urllib.request.Request("https://github.com/user-attachments/files/1/x.txt")
        with self.assertRaises(urllib.error.HTTPError):
            handler.redirect_request(request, None, 302, "Found", {}, "https://evil.example/x")
        with self.assertRaises(urllib.error.HTTPError):
            handler.redirect_request(request, None, 302, "Found", {}, "http://objects.githubusercontent.com/x")
        followed = handler.redirect_request(request, None, 302, "Found", {},
                                            "https://objects.githubusercontent.com/x")
        self.assertEqual(followed.full_url, "https://objects.githubusercontent.com/x")
        with self.assertRaises(ingest.IngestError):
            ingest_issue.fetch("https://evil.example/file.txt")

    def test_share_code_and_attachment(self):
        attachment = "https://github.com/user-attachments/files/123/Aegis_Forever_Pathfinder.zip"
        zipped = zip_bytes([("Aegis_Forever_Pathfinder.txt",
                             SAVED_VARIABLES.replace(COLLECTION_ID, "eeee0005").encode())])
        data = "%s\n\n[Aegis_Forever_Pathfinder.zip](%s)\n[evil](https://evil.example/x.zip)" % (
            share_code(envelope()), attachment)
        status, summary, outputs, fetched = self.run_issue(issue_body(data=data), {attachment: zipped})
        self.assertEqual(status, 0, summary)
        self.assertEqual(fetched, [attachment])
        self.assertEqual(outputs, {"stored": "2", "changed": "2", "attention": "0", "credit": "Goldshire Gary"})
        self.assertIn("Thanks for sending your data", summary)
        self.assertIn("credited as **Goldshire Gary**", summary)
        stored = json.loads(self.read("data", "submissions", COLLECTION_ID + ".json"))
        self.assertEqual(stored["source"]["issue"], 42)
        self.assertEqual(stored["source"]["github_login"], "gary-g")
        self.assertEqual(stored["source"]["kind"], "github-issue")
        self.assertIn('"Goldshire Gary"', self.read("Contributors.lua"))

        # The same issue read again (an edit, or the second event): nothing changes.
        status, summary, outputs, _ = self.run_issue(issue_body(data=data), {attachment: zipped})
        self.assertEqual((status, outputs["changed"]), (0, "0"))
        self.assertIn("already had", summary)

    def test_credit_order(self):
        # The form's name, else the name set in game, else the GitHub login.
        cases = [("Form Name", "Game Name", "Form Name"), ("_No response_", "Game Name", "Game Name"),
                 ("_No response_", "", "gary-g")]
        for index, (form, game, expected) in enumerate(cases):
            collect = collection("ffff000%d" % index, [index + 1])
            status, _, outputs, _ = self.run_issue(issue_body(credit=form,
                                                              data=share_code(envelope(collect, contributor=game))))
            self.assertEqual((status, outputs["credit"]), (0, expected), form)

    def test_another_accounts_collection_needs_a_person(self):
        data = share_code(envelope())
        status, _, outputs, _ = self.run_issue(issue_body(data=data), login="gary-g")
        self.assertEqual((status, outputs["attention"]), (0, "0"))
        status, summary, outputs, _ = self.run_issue(issue_body(data=data), login="mallory")
        self.assertEqual((status, outputs["stored"], outputs["attention"]), (2, "0", "1"))
        self.assertIn("another GitHub account", summary)

    def test_nothing_usable(self):
        status, summary, outputs, _ = self.run_issue(issue_body(data="I played a lot!"))
        self.assertEqual(status, 2)
        self.assertEqual(outputs["stored"], "0")
        self.assertIn("couldn't find any Pathfinder data", summary)
        self.assertIn("How to send your data", summary)
        self.assertFalse(os.path.exists(os.path.join(self.root, "data", "merged.json")))

    def test_broken_code_and_failed_download_are_explained(self):
        attachment = "https://github.com/user-attachments/files/9/missing.txt"
        code = share_code(envelope())
        status, summary, _, _ = self.run_issue(issue_body(data="%s\n\n[missing.txt](%s)" % (code[:300], attachment)))
        self.assertEqual(status, 2)
        self.assertRegex(summary, "cut short|damaged|letters missing")
        self.assertIn("missing", summary)
        self.assertIn("404", summary)

    def test_hostile_file_name_is_escaped_in_the_answer(self):
        attachment = "https://github.com/user-attachments/files/9/%3Cimg%20src=x%3E.txt"
        status, summary, _, _ = self.run_issue(issue_body(data=attachment), {attachment: b"nothing here"})
        self.assertEqual(status, 2)
        self.assertNotIn("<img", summary)

    def test_internal_error(self):
        with mock.patch.object(ingest, "store", side_effect=RuntimeError("disk on fire")), \
                contextlib.redirect_stderr(io.StringIO()):
            status, summary, outputs, _ = self.run_issue(issue_body(data=share_code(envelope())))
        self.assertEqual(status, 1)
        self.assertIn("went wrong on our side", summary)
        self.assertEqual(outputs["stored"], "0")


##########################################################################################
# The merge command, and text built to be slow
##########################################################################################

class MergeCommand(TempRepo):
    def test_reads_codes_and_both_export_formats(self):
        files = {"code.txt": share_code(envelope(collection("aaaa0001", [1]))),
                 "export2.txt": plain_export(envelope(collection("bbbb0002", [2]))),
                 "export1.txt": plain_export(collection("cccc0003", [3]), fmt=1)}
        paths = []
        for name, text in files.items():
            paths.append(os.path.join(self.root, name))
            with open(paths[-1], "w", encoding="utf-8") as handle:
                handle.write(text)
        out = os.path.join(self.root, "merged.json")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(merge_exports.main(paths + ["-o", out]), 0)
        with open(out, encoding="utf-8") as handle:
            merged = json.load(handle)
        self.assertEqual(sorted(merged["quests"]), ["1", "2", "3"])
        self.assertNotIn("data", merged)
        self.assertEqual(sorted(source["id"] for source in merged["sources"]), ["aaaa0001", "bbbb0002", "cccc0003"])


class SlowText(unittest.TestCase):
    """Text that once took exponential or quadratic time. Anyone can open an issue."""

    def quick(self, call):
        started = time.monotonic()
        try:
            call()
        except (savedvariables.ParseError, ingest.IngestError):
            pass
        self.assertLess(time.monotonic() - started, 2.0)

    def test_backslashes_and_line_breaks_in_a_string(self):
        self.quick(lambda: savedvariables.load('AegisPathfinderDB = "' + "\\\n" * 200000))

    def test_long_comments_and_strings_never_closed(self):
        self.quick(lambda: savedvariables.load("AegisPathfinderDB = {} " + "--[[ x\n" * 20000))
        self.quick(lambda: savedvariables.load("AegisPathfinderDB = " + "[[" * 50000))
        with self.assertRaises(savedvariables.ParseError):
            savedvariables.load("AegisPathfinderDB = { a = --[[ never closed\n 1 }")

    def test_long_strings_and_comments_still_read(self):
        self.assertEqual(savedvariables.load('AegisPathfinderDB = { a = [==[x]]y]==], --[[ c ]] b = "q\\\nr" }'),
                         {"AegisPathfinderDB": {"a": "x]]y", "b": "q\nr"}})

    def test_fences_that_never_close(self):
        self.quick(lambda: ingest.decode("```a\nAegisPathfinderDB = {}\n" * 50000, "f", []))
        self.assertEqual(ingest._fenced_blocks("```lua\nA\n```\n~~~~\nB\n~~~\nstill B\n~~~~\n```\nopen\n"),
                         ["A", "B\n~~~\nstill B"])

    def test_a_heading_line_full_of_spaces(self):
        self.quick(lambda: ingest_issue.parse_form("### a" + " " * 60000 + "b\n"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
