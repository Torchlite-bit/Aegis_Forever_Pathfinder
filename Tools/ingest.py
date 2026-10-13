"""
Takes in the data players send, checks it, and adds it to the repository.

Players send what the collector wrote (docs/data-schema.md) in one of these
forms (docs/data-submission.md says how they get each one):

  share code     "APF1:" and then the data, packed with zlib and written out as
                 Base64 text. The in-game Submit window gives one to copy.
  plain export   a header line "AEGIS PATHFINDER FOREVER DATA;<format>;..."
                 and then JSON. What Submit gives when the client can't pack.
  data file      the SavedVariables file, Aegis_Forever_Pathfinder.lua (maybe
                 renamed .txt, zipped or gzipped). Read as data by
                 Tools/savedvariables.py, never run.

Everything a player sends is untrusted. It is read with size limits, then
cleaned: only the fields docs/data-schema.md lists are kept, with the right
types and sensible sizes. Then:

  store()     saves one collection as data/submissions/<collection id>.json.
              Players send their growing collection again and again: the
              newest copy of a collection replaces the older one, so nothing
              is counted twice.
  rebuild()   makes these again from every saved submission:
                data/merged.json         everything merged, by the rules of
                                         Tools/merge_exports.py
                data/contributors.json   who sent what
                Contributors.lua         the names the addon shows in game
                CONTRIBUTORS.md          the names, between its markers

The command line is for maintainers, for files sent on Discord:

    python Tools/ingest.py FILE [FILE...] [--credit NAME] [--root .]
    python Tools/ingest.py                   # only make the files again

The GitHub Action behind the "Submit collected data" issue form runs
Tools/ingest_issue.py, which uses this file.
"""

import argparse
import base64
import binascii
import datetime
import glob
import hashlib
import io
import json
import math
import os
import re
import stat
import sys
import unicodedata
import zipfile
import zlib
from dataclasses import dataclass

TOOLS = os.path.dirname(os.path.abspath(__file__))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

import merge_exports  # noqa: E402  (found through the line above)
import savedvariables  # noqa: E402

ROOT = os.path.dirname(TOOLS)
ADDON = "Aegis_Forever_Pathfinder"
SHARE_PREFIX = "APF1:"
HEADER = merge_exports.HEADER  # "AEGIS PATHFINDER FOREVER DATA"

# Limits on what is read.
MAX_INPUT = 25 * 1024 * 1024        # a pasted text, a file or a download
MAX_UNPACKED = 50 * 1024 * 1024     # what a zip, gzip or share code unpacks to, in all
MAX_ZIP_MEMBERS = 20
# Limits on what is kept.
MAX_NAME = 40
MAX_TEXT = 2000
MAX_QUESTS = 20000
MAX_LEVELS = 100
MAX_CELLS = 40                      # the collector's own limit per list of map cells
COUNT_MAX = 10 ** 9
ID_MAX = 2 ** 31 - 1
MONEY_MAX = 10 ** 12                # copper
XP_MAX = 10 ** 9
LEVEL_MAX = 200
# GetServerTime() stamps: 2000-01-01 to 2100-01-01.
TIME_MIN, TIME_MAX = 946684800, 4102444800

# What store() can do with a collection, and which of those count as taken in.
ACCEPTED = ("new", "replaced", "unchanged", "older")
CHANGED = ("new", "replaced")

SUBMISSIONS = os.path.join("data", "submissions")
MARK_START = "<!-- data-contributors:start -->"
MARK_END = "<!-- data-contributors:end -->"


class IngestError(ValueError):
    """Something a player sent can't be used. The message says why, in plain words."""


@dataclass
class Submission:
    """One collection found in what a player sent."""
    envelope: dict          # {format, addon, addonVersion, build, interface, exportedAt, contributor, data}
    kind: str = "share code"  # "share code", "export" or "data file"
    origin: str = "text"    # the file it came from


@dataclass
class Stored:
    """What store() did with a collection."""
    id: str
    status: str             # new, replaced, unchanged, older or taken
    path: str
    quests: int = 0
    levels: int = 0
    contributor: str = None


##########################################################################################
# Finding the data in what a player sent
##########################################################################################

def decode(text_or_bytes, filename=None, problems=None, report_empty=True):
    """Every collection found in a pasted text or a file, as a list of Submissions.

    Bytes may be a zip or gzip file; text may hold any number of share codes and
    exports, or be a SavedVariables file. `filename` is only used to name it in
    messages. What can't be read is described in plain words in `problems`, when
    a list is passed; without one, an IngestError is raised if nothing was found.
    With `report_empty` off, text with no data in it at all is not a problem."""
    own = problems if problems is not None else []
    found = _decode(text_or_bytes, filename, own, 0, report_empty)
    if problems is None and not found:
        raise IngestError(" ".join(own) or "No Pathfinder data found.")
    return found


def _label(filename):
    return filename or "The text"


def _decode(content, filename, problems, depth, report_empty=True):
    label = _label(filename)
    if isinstance(content, str):
        if len(content) > MAX_INPUT:
            problems.append("%s is bigger than 25 MB." % label)
            return []
        return _decode_text(content, filename, problems, report_empty)
    if not isinstance(content, (bytes, bytearray)):
        raise TypeError("decode takes text or bytes")
    content = bytes(content)
    if len(content) > MAX_INPUT:
        problems.append("%s is bigger than 25 MB." % label)
        return []
    archive = content[:4] in (b"PK\x03\x04", b"PK\x05\x06") or content[:2] == b"\x1f\x8b"
    if archive and depth > 0:
        problems.append("%s is an archive inside an archive. Zip the data file itself." % label)
        return []
    if content[:4] in (b"PK\x03\x04", b"PK\x05\x06"):
        return _decode_zip(content, filename, problems, depth)
    if content[:2] == b"\x1f\x8b":
        return _decode_gzip(content, filename, problems, depth)
    if content[:4] == b"Rar!" or content[:6] == b"7z\xbc\xaf\x27\x1c":
        problems.append("%s is a RAR or 7z archive. Send a .zip, or the file itself renamed to .txt."
                        % label)
        return []
    return _decode_text(content.decode("utf-8", errors="replace"), filename, problems, report_empty)


def _decode_text(text, filename, problems, report_empty=True):
    before = len(problems)
    if text.startswith("\ufeff"):
        text = text[1:]
    text = text.replace("\r\n", "\n")

    # A whole SavedVariables file: read as one, and nothing else is looked for in it.
    sv_problem = None
    if _SV_START.search(text):
        found, sv_problem = _saved_variables(text, filename)
        if found:
            return [found]

    found = _share_codes(text, filename, problems) + _plain_exports(text, filename, problems)
    # A SavedVariables file pasted between ``` lines.
    if not found:
        for block in _fenced_blocks(text):
            if _SV_START.search(block):
                submission, problem = _saved_variables(block, filename)
                if submission:
                    found.append(submission)
                sv_problem = sv_problem or problem
    if not found and sv_problem:
        problems.append(sv_problem)
    if not found and len(problems) == before and report_empty:
        problems.append("%s: no share code, export or Pathfinder data file found in it." % _label(filename))
    return found


# Share codes ----------------------------------------------------------------------------

# The letters a share code is made of (Base64, and its URL-safe "-" and "_"),
# and the spaces and line breaks a paste may add.
_CODE_LETTERS = re.compile(r"[A-Za-z0-9+/=_\-\s]*")


def _share_codes(text, filename, problems):
    found = []
    starts = [match.end() for match in re.finditer(re.escape(SHARE_PREFIX), text)]
    for number, start in enumerate(starts, 1):
        end = text.find(SHARE_PREFIX, start)
        letters = _CODE_LETTERS.match(text, start, end if end >= 0 else len(text)).group(0)
        which = "share code" if len(starts) == 1 else "share code %d" % number
        try:
            envelope = _envelope_from_json(_json_object(unpack_share_code(letters)), None)
        except IngestError as error:
            problems.append("%s, %s: %s" % (_label(filename), which, error))
            continue
        found.append(Submission(envelope, "share code", filename or "text"))
    return found


def unpack_share_code(letters):
    """The JSON text inside a share code (without its "APF1:"). Spaces and line
    breaks are ignored, and so is anything after the packed data ends."""
    letters = re.sub(r"\s+", "", letters).replace("-", "+").replace("_", "/")
    pad = letters.find("=")
    if pad >= 0:
        # "=" only ever ends Base64: the code stops after its one or two.
        letters = letters[:pad] + re.match(r"=*", letters[pad:]).group(0)[:2]
    else:
        # A copy that lost its "=" gets them back; a stray last letter is dropped.
        remainder = len(letters) % 4
        if remainder == 1:
            letters = letters[:-1]
        elif remainder:
            letters += "=" * (4 - remainder)
    if not letters:
        raise IngestError("the code is empty. Copy it again, all of it.")
    try:
        packed = base64.b64decode(letters, validate=True)
    except (binascii.Error, ValueError):
        raise IngestError("the code has letters missing or changed. Copy it again, all of it.")
    # zlib, as the addon packs it (a gzip header is taken too); bare deflate if neither.
    for window in (32 + zlib.MAX_WBITS, -zlib.MAX_WBITS):
        unpacker = zlib.decompressobj(window)
        try:
            raw = unpacker.decompress(packed, MAX_UNPACKED + 1)
        except zlib.error:
            continue
        if len(raw) > MAX_UNPACKED:
            raise IngestError("the code unpacks to more than 50 MB.")
        if not unpacker.eof:
            raise IngestError("the code is cut short. Copy it again, all of it "
                              "(click in the box, Ctrl+A, then Ctrl+C).")
        return raw.decode("utf-8", errors="replace")
    raise IngestError("the code is damaged. Copy it again, all of it.")


def _json_object(text):
    try:
        value = json.loads(text)
    except (ValueError, RecursionError):
        raise IngestError("the data inside is not valid JSON.")
    if not isinstance(value, dict):
        raise IngestError("the data inside is not in the expected shape.")
    return value


# Plain exports --------------------------------------------------------------------------

_EXPORT_HEADER = re.compile(re.escape(HEADER) + r";([^\n]*)")


def _plain_exports(text, filename, problems):
    found = []
    decoder = json.JSONDecoder()
    headers = list(_EXPORT_HEADER.finditer(text))
    for number, match in enumerate(headers, 1):
        which = "export" if len(headers) == 1 else "export %d" % number
        # <format>;<addon version>;<build>;<interface>;<UTC time>[;<contributor>]
        fields = match.group(1).split(";", 5)
        brace = text.find("{", match.end())
        following = headers[number].start() if number < len(headers) else len(text)
        if brace < 0 or brace >= following:
            problems.append("%s, %s: only its first line is there. Copy all of it." % (_label(filename), which))
            continue
        try:
            body, _ = decoder.raw_decode(text, brace)
        except (ValueError, RecursionError):
            problems.append("%s, %s: its data is cut short or changed. Copy it again, all of it."
                            % (_label(filename), which))
            continue
        if not isinstance(body, dict):
            problems.append("%s, %s: its data is not in the expected shape." % (_label(filename), which))
            continue
        found.append(Submission(_envelope_from_json(body, fields), "export", filename or "text"))
    return found


def _envelope_from_json(body, fields):
    """The envelope, from an export's JSON and its header fields (None for a share code).
    Format 2 sends the envelope itself; format 1 sent the collected table alone."""
    fields = list(fields or []) + [None] * 6
    header = {
        "format": _int_text(fields[0]),
        "addonVersion": fields[1],
        "build": fields[2],
        "interface": _int_text(fields[3]),
        "exportedAt": _utc_seconds(fields[4]),
        "contributor": fields[5],
    }
    if "data" in body and isinstance(body.get("data"), dict):
        envelope = dict(body)
        for key, value in header.items():
            if envelope.get(key) in (None, "") and value not in (None, ""):
                envelope[key] = value
        return envelope
    # Format 1: the collected table, with what is known about it in the header.
    envelope = dict(header, addon=ADDON, data=body)
    envelope["format"] = header["format"] or 1
    return envelope


def _int_text(value):
    value = (value or "").strip()
    return int(value) if re.fullmatch(r"[0-9]{1,9}", value) else None


def _utc_seconds(value):
    """Unix seconds from the export header's "2026-10-13T08:07:38Z", or None."""
    try:
        moment = datetime.datetime.strptime((value or "").strip(), "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return int(moment.replace(tzinfo=datetime.timezone.utc).timestamp())


# SavedVariables files -------------------------------------------------------------------

_SV_START = re.compile(r"^[ \t]*AegisPathfinderDB[ \t]*=", re.M)
_FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})[^\n]*\n(.*?)^[ \t]*\1[ \t]*$", re.M | re.S)


def _fenced_blocks(text):
    return [match.group(2) for match in _FENCE.finditer(text)]


def _saved_variables(text, filename):
    """(Submission, None), or (None, why not)."""
    label = _label(filename)
    try:
        variables = savedvariables.load(text)
    except (savedvariables.ParseError, RecursionError, ValueError):
        return None, ("%s looks like a Pathfinder data file, but it has something in it that is not "
                      "plain saved data, or it is cut short. Send the file exactly as the game wrote it."
                      % label)
    db = variables.get("AegisPathfinderDB")
    collect = db.get("collect") if isinstance(db, dict) else None
    if not isinstance(collect, dict):
        return None, ("%s has no collected data in it yet. Start collecting in game, play a while, "
                      "then /reload (or log out) before sending the file." % label)
    profile = db.get("profile")
    collect = _json_shape(collect)
    envelope = {
        "format": None,
        "addon": ADDON,
        "addonVersion": None,
        "build": _newest_build(collect.get("builds")),
        "interface": None,
        "exportedAt": None,  # sanitize() takes the newest stamp in the data
        "contributor": profile.get("creditName") if isinstance(profile, dict) else None,
        "data": collect,
    }
    return Submission(envelope, "data file", filename or "text"), None


def _json_shape(value):
    """A value from the SavedVariables reader with every table key as text, as JSON
    has it: [176] -> "176". (Tables keyed 1..n are lists in both.)"""
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            key = _key_text(key)
            if key is not None:
                out[key] = _json_shape(item)
        return out
    if isinstance(value, list):
        return [_json_shape(item) for item in value]
    return value


def _key_text(key):
    if isinstance(key, bool):
        return "true" if key else "false"
    if isinstance(key, int):
        return str(key)
    if isinstance(key, float):
        return str(int(key)) if key.is_integer() else repr(key)
    return key if isinstance(key, str) else None


def _newest_build(builds):
    names = [name for name in (builds if isinstance(builds, dict) else {}) if _BUILD.fullmatch(name)]
    return max(names, key=lambda name: [int(part) for part in name.split(".")], default=None)


# Archives -------------------------------------------------------------------------------

class _Refused(Exception):
    pass


def _decode_zip(content, filename, problems, depth):
    label = filename or "The zip file"
    try:
        archive = zipfile.ZipFile(io.BytesIO(content))
    except (zipfile.BadZipFile, zipfile.LargeZipFile, ValueError, EOFError):
        problems.append("%s could not be opened as a zip file." % label)
        return []
    found = []
    try:
        with archive:
            members = archive.infolist()
            if len(members) > MAX_ZIP_MEMBERS:
                raise _Refused("it has more than %d files in it. Zip only the data file." % MAX_ZIP_MEMBERS)
            for info in members:
                _check_member(info)
            room = MAX_UNPACKED
            for info in members:
                base = os.path.basename(info.filename.rstrip("/"))
                if info.is_dir() or info.filename.startswith("__MACOSX/") or base.startswith("._") \
                        or base == ".DS_Store":
                    continue
                if info.flag_bits & 0x1:
                    raise _Refused("it is password-protected.")
                if info.file_size > room:
                    raise _Refused("it unpacks to more than 50 MB.")
                try:
                    with archive.open(info) as handle:
                        data = handle.read(room + 1)
                except (zipfile.BadZipFile, zlib.error, NotImplementedError, RuntimeError, EOFError, OSError):
                    problems.append("%s: %s in it could not be unpacked." % (label, base))
                    continue
                if len(data) > room:
                    raise _Refused("it unpacks to more than 50 MB.")
                room -= len(data)
                found += _decode(data, base, problems, depth + 1)
    except _Refused as refusal:
        problems.append("%s was not opened: %s" % (label, refusal))
        return []
    return found


def _check_member(info):
    """Refuses a zip whose files would land outside its folder (absolute paths,
    "..") or that holds links: nothing here is written to disk, but such a zip
    is never what the game writes, so it is turned away whole."""
    name = info.filename
    if "\x00" in name or name.startswith(("/", "\\")) or re.match(r"[A-Za-z]:", name):
        raise _Refused("it has a file with an absolute path in it.")
    if ".." in re.split(r"[\\/]", name):
        raise _Refused("it has a file pointing outside its folder (..) in it.")
    if stat.S_ISLNK(info.external_attr >> 16):
        raise _Refused("it has a link in it.")


def _decode_gzip(content, filename, problems, depth):
    label = filename or "The gzip file"
    unpacker = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        raw = unpacker.decompress(content, MAX_UNPACKED + 1)
    except zlib.error:
        problems.append("%s could not be unpacked." % label)
        return []
    if len(raw) > MAX_UNPACKED:
        problems.append("%s was not opened: it unpacks to more than 50 MB." % label)
        return []
    if not unpacker.eof:
        problems.append("%s is cut short." % label)
        return []
    inner = filename[:-3] if filename and filename.lower().endswith(".gz") else filename
    return _decode(raw, inner, problems, depth + 1)


##########################################################################################
# Cleaning: only known fields, with the right types and sizes
##########################################################################################

_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f\ud800-\udfff]")
_BUILD = re.compile(r"[0-9]{1,4}(?:\.[0-9]{1,6}){1,4}")
_VERSION = re.compile(r"[\w.+-]{1,40}")
_WHO = re.compile(r"[\w' .?-]{1,40}:[\w' .?-]{1,40}:[\w' .?-]{1,40}")
_CLASS = re.compile(r"[\w?]{1,40}")
_CELL = re.compile(r"([0-9]{1,7}):([0-9]{1,3}):([0-9]{1,3})")
_HEX_ID = re.compile(r"[0-9a-fA-F]{1,64}")
_LOGIN = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}")

PLACE_KINDS = {"npc", "object", "item", "auto", "unknown"}
SEEN_KEYS = {"offered", "accepted", "turnedIn", "abandoned"}
POI_KEYS = {"objective", "turnin", "available"}
QUEST_TEXTS = ("title", "description", "objectiveText", "progressText", "completionText", "questLine")


def _number(value, low, high):
    """A finite number from low to high, or None. Whole floats become ints."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if isinstance(value, float):
        if not math.isfinite(value):
            return None
        if value.is_integer():
            value = int(value)
    return value if low <= value <= high else None


def _integer(value, low, high):
    value = _number(value, low, high)
    return value if isinstance(value, int) else None


def _count(value):
    return _integer(value, 0, COUNT_MAX)


def _time(value):
    return _integer(value, TIME_MIN, TIME_MAX)


def _coordinate(value):
    return _number(value, 0, 1)


def _text(value, limit=MAX_TEXT):
    """Text without control characters, at most `limit` long, or None."""
    if not isinstance(value, str):
        return None
    value = _CONTROL.sub("", value)[:limit]
    return value or None


def _true(value):
    return True if value is True else None


def _put(out, key, value):
    """Sets out[key] unless the value is missing or empty."""
    if value is not None and value != {} and value != []:
        out[key] = value


def _pairs(value):
    """A table's (key, value) pairs, keys as text. A table keyed 1..n arrives as
    a list (in JSON and from the SavedVariables reader alike): it is read as the
    keys "1".."n" it had in the game."""
    if isinstance(value, dict):
        return [(key, item) for key, item in value.items() if isinstance(key, str)]
    if isinstance(value, list):
        return [(str(index), item) for index, item in enumerate(value, 1)]
    return []


def _order(key):
    """Number keys in number order, then text keys. (Only 0-9 count as digits:
    "²" is a digit to Python but not a number to int().)"""
    return (0, int(key), "") if re.fullmatch(r"[0-9]+", key) else (1, 0, key)


def _table(value, check_key, clean, limit):
    """A cleaned { key = value } table: keys `check_key` refuses and values `clean`
    refuses are dropped, and at most `limit` entries are kept (the first, in key order)."""
    keys = {}
    for key, item in _pairs(value):
        key = check_key(key)
        if key is not None:
            keys[key] = item
    out = {}
    for key in sorted(keys, key=_order):
        if len(out) >= limit:
            break
        item = clean(keys[key])
        if item is not None and item != {} and item != []:
            out[key] = item
    return out or None


def _id_key(low, high):
    """Keys that are whole numbers from low to high (quest ids, levels, item ids),
    written the way the game writes them."""
    def check(key):
        if not re.fullmatch(r"[0-9]{1,10}", key):
            return None
        number = int(key)
        return str(number) if low <= number <= high else None
    return check


def _match_key(pattern):
    def check(key):
        return key if pattern.fullmatch(key) else None
    return check


def _one_of(names):
    def check(key):
        return key if key in names else None
    return check


def _text_key(limit):
    def check(key):
        return _text(key, limit)
    return check


ID_KEY = _id_key(1, ID_MAX)
LEVEL_KEY = _id_key(1, LEVEL_MAX)
OBJECTIVE_KEY = _id_key(1, 50)


def _range(value, low, high):
    """A Range ({min, max, count, last}), complete, or None."""
    if not isinstance(value, dict):
        return None
    numbers = {key: _number(value.get(key), low, high) for key in ("min", "max", "last")}
    known = [number for number in numbers.values() if number is not None]
    if not known:
        return None
    least = min(known) if numbers["min"] is None else min(numbers["min"], *known)
    most = max(known) if numbers["max"] is None else max(numbers["max"], *known)
    last = numbers["last"] if numbers["last"] is not None else most
    return {"min": least, "max": most, "count": _integer(value.get("count"), 1, COUNT_MAX) or 1, "last": last}


def _cells(value):
    """Map cells, { "mapID:x:y" = count }: the MAX_CELLS seen most often."""
    cells = {}
    for key, count in _pairs(value):
        match = _CELL.fullmatch(key)
        count = _integer(count, 1, COUNT_MAX)
        if match and count and int(match.group(2)) <= 100 and int(match.group(3)) <= 100:
            cells["%d:%d:%d" % tuple(int(part) for part in match.groups())] = count
    kept = sorted(cells.items(), key=lambda item: (-item[1], _cell_order(item[0])))[:MAX_CELLS]
    return dict(sorted(kept, key=lambda item: _cell_order(item[0]))) or None


def _cell_order(key):
    return tuple(int(part) for part in key.split(":"))


def _stamps(value, out):
    _put(out, "builds", _table(value.get("builds"), _match_key(_BUILD), _true, 100))
    _put(out, "by", _table(value.get("by"), _match_key(_WHO), _count, 500))
    _put(out, "first", _time(value.get("first")))
    _put(out, "last", _time(value.get("last")))


def _place(value):
    """A pickup or turn-in. A position is kept only whole: its mean, its
    extremes and how many positions went into it."""
    if not isinstance(value, dict):
        return None
    out = {"kind": value.get("kind") if value.get("kind") in PLACE_KINDS else "unknown",
           "count": _integer(value.get("count"), 1, COUNT_MAX) or 1}
    _put(out, "id", _integer(value.get("id"), 0, ID_MAX))
    _put(out, "name", _text(value.get("name"), 200))
    _put(out, "mapID", _integer(value.get("mapID"), 0, ID_MAX))
    _put(out, "zone", _text(value.get("zone"), 200))
    _put(out, "subzone", _text(value.get("subzone"), 200))
    _put(out, "playerLevel", _range(value.get("playerLevel"), 1, LEVEL_MAX))
    positions = _integer(value.get("xyCount"), 1, COUNT_MAX)
    x, y = _coordinate(value.get("x")), _coordinate(value.get("y"))
    if positions and x is not None and y is not None:
        out.update(x=x, y=y, xyCount=positions)
        for key, centre, pick in (("xMin", x, min), ("xMax", x, max), ("yMin", y, min), ("yMax", y, max)):
            edge = _coordinate(value.get(key))
            out[key] = centre if edge is None else pick(edge, centre)
    return out


def _objectives(value):
    """The quest's objectives, a list. Objectives with a gap in their numbers
    arrive keyed "1", "3": they go back into a list, the gap left empty."""
    if isinstance(value, dict):
        indexed = {int(key): item for key, item in _pairs(value) if OBJECTIVE_KEY(key)}
        items = [indexed.get(index) for index in range(1, max(indexed, default=0) + 1)]
    elif isinstance(value, list):
        items = value[:50]
    else:
        return None
    out = []
    for item in items:
        objective = {}
        if isinstance(item, dict):
            _put(objective, "text", _text(item.get("text"), 500))
            _put(objective, "type", _text(item.get("type"), 40))
            _put(objective, "required", _integer(item.get("required"), 0, 10 ** 6))
        out.append(objective)
    return out if any(out) else None


def _item(value):
    if not isinstance(value, dict):
        return None
    out = {"count": _integer(value.get("count"), 1, 10 ** 6) or 1}
    _put(out, "name", _text(value.get("name"), 200))
    return out


def _currency(value):
    if not isinstance(value, dict):
        return None
    out = {}
    _put(out, "name", _text(value.get("name"), 200))
    _put(out, "amount", _integer(value.get("amount"), 0, COUNT_MAX))
    return out


def _spell(value):
    return True if value is True else _text(value, 200)


def _reputation(value):
    if not isinstance(value, dict):
        return None
    out = _range(value, -10 ** 7, 10 ** 7) or {}
    _put(out, "factionID", _integer(value.get("factionID"), 0, ID_MAX))
    return out


def _item_counts(value):
    return _table(value, ID_KEY, lambda count: _integer(count, 1, COUNT_MAX), 50)


def _rewards(value):
    if not isinstance(value, dict):
        return None
    out = {}
    _put(out, "xp", _table(value.get("xp"), LEVEL_KEY, lambda item: _range(item, 0, XP_MAX), MAX_LEVELS))
    _put(out, "xpOffered", _table(value.get("xpOffered"), LEVEL_KEY, lambda item: _integer(item, 0, XP_MAX),
                                  MAX_LEVELS))
    _put(out, "xpObserved", _table(value.get("xpObserved"), LEVEL_KEY, lambda item: _range(item, 0, XP_MAX),
                                   MAX_LEVELS))
    _put(out, "money", _range(value.get("money"), 0, MONEY_MAX))
    _put(out, "moneyOffered", _integer(value.get("moneyOffered"), 0, MONEY_MAX))
    _put(out, "choices", _table(value.get("choices"), ID_KEY, _item, 50))
    _put(out, "items", _table(value.get("items"), ID_KEY, _item, 50))
    _put(out, "chosen", _table(value.get("chosen"), _match_key(_CLASS), _item_counts, 30))
    _put(out, "spells", _table(value.get("spells"), ID_KEY, _spell, 50))
    _put(out, "currencies", _table(value.get("currencies"), ID_KEY, _currency, 50))
    _put(out, "reputation", _table(value.get("reputation"), _text_key(100), _reputation, 50))
    _put(out, "title", _text(value.get("title"), 200))
    _put(out, "skillPoints", _integer(value.get("skillPoints"), 0, 10 ** 6))
    _put(out, "honor", _integer(value.get("honor"), 0, COUNT_MAX))
    return out


def _chain(value):
    return _table(value, _one_of({"prev", "next"}), lambda ids: _table(ids, ID_KEY, _true, 100), 2)


def _quest(value):
    if not isinstance(value, dict):
        return None
    out = {}
    for key in QUEST_TEXTS:
        _put(out, key, _text(value.get(key)))
    _put(out, "tag", _text(value.get("tag"), 100))
    _put(out, "level", _integer(value.get("level"), -1, 1000))
    _put(out, "suggestedGroup", _integer(value.get("suggestedGroup"), 0, 100))
    _put(out, "frequency", _integer(value.get("frequency"), 0, 100))
    _put(out, "tagID", _integer(value.get("tagID"), 0, ID_MAX))
    _put(out, "requiredMoney", _integer(value.get("requiredMoney"), 0, MONEY_MAX))
    _put(out, "seen", _table(value.get("seen"), _one_of(SEEN_KEYS), _count, 4))
    _put(out, "pickups", _table(value.get("pickups"), _text_key(200), _place, 100))
    _put(out, "turnins", _table(value.get("turnins"), _text_key(200), _place, 100))
    _put(out, "objectives", _objectives(value.get("objectives")))
    _put(out, "progress", _table(value.get("progress"), OBJECTIVE_KEY, _cells, 50))
    _put(out, "poi", _table(value.get("poi"), _one_of(POI_KEYS), _cells, 3))
    _put(out, "chain", _chain(value.get("chain")))
    _put(out, "rewards", _rewards(value.get("rewards")))
    _stamps(value, out)
    return out


def _level(value):
    if not isinstance(value, dict):
        return None
    out = {}
    _put(out, "xpMax", _range(value.get("xpMax"), 0, XP_MAX))
    _put(out, "seconds", _range(value.get("seconds"), 0, 10 ** 8))
    _stamps(value, out)
    return out


def _collection(value):
    """The collected table (docs/data-schema.md), cleaned. The window's log is left out."""
    if not isinstance(value, dict):
        raise IngestError("the data is not a table of quests and levels.")
    out = {"schemaVersion": _integer(value.get("schemaVersion"), 1, 1000) or 1}
    collection_id = value.get("id")
    if isinstance(collection_id, str) and _HEX_ID.fullmatch(collection_id):
        out["id"] = collection_id.lower()
    _put(out, "created", _time(value.get("created")))
    _put(out, "builds", _table(value.get("builds"), _match_key(_BUILD), _true, 100))
    _put(out, "observers", _table(value.get("observers"), _match_key(_WHO), _count, 500))
    _put(out, "levels", _table(value.get("levels"), LEVEL_KEY, _level, MAX_LEVELS))
    _put(out, "quests", _table(value.get("quests"), ID_KEY, _quest, MAX_QUESTS))
    return out


def _newest_stamp(data):
    stamps = [data.get("created")]
    for group in ("levels", "quests"):
        stamps += [record.get("last") for record in (data.get(group) or {}).values()]
    return max((stamp for stamp in stamps if stamp), default=None)


def sanitize(envelope):
    """The envelope with only what docs/data-schema.md knows, cleaned. Raises
    IngestError when it isn't Pathfinder data at all."""
    if not isinstance(envelope, dict):
        raise IngestError("the data is not in the expected shape.")
    if envelope.get("addon") not in (None, ADDON):
        raise IngestError("this is data from another addon.")
    data = _collection(envelope.get("data"))
    version, build = envelope.get("addonVersion"), envelope.get("build")
    return {
        "format": _integer(envelope.get("format"), 1, 100),
        "addon": ADDON,
        "addonVersion": version if isinstance(version, str) and _VERSION.fullmatch(version) else None,
        "build": build if isinstance(build, str) and _BUILD.fullmatch(build) else None,
        "interface": _integer(envelope.get("interface"), 0, 10 ** 7),
        # A data file has no export time: the newest stamp in it stands in.
        "exportedAt": _time(envelope.get("exportedAt")) or _newest_stamp(data),
        "contributor": clean_name(envelope.get("contributor")),
        "data": data,
    }


validate = sanitize


def has_data(envelope):
    data = envelope.get("data") or {}
    return bool(data.get("quests") or data.get("levels"))


# Names ----------------------------------------------------------------------------------

_NAME_DROPS = re.compile("[<>\\\\`\"'@\u2018\u2019\u201a\u201b\u201c\u201d\u201e\u201f\u00ab\u00bb\u2039\u203a\u00b4]")
# What a name may keep in the in-game list: letters (any alphabet), digits,
# spaces and a little punctuation. Notably not "|", the game's own escape character.
_LUA_UNSAFE = re.compile(r"[^\w .,!?&+()#-]")
_MARKDOWN = re.compile(r"([\\`*_{}\[\]()#+\-.!|~:@\"'=])")


def clean_name(name):
    """A contributor's name as shown in the credits, or None: no control or
    invisible characters, angle brackets, backslashes, backticks, quotes or "@"
    (so it can't mention anyone), spaces trimmed, at most MAX_NAME long."""
    if not isinstance(name, str):
        return None
    name = unicodedata.normalize("NFKC", name)
    # Spaces stay (and are squeezed below); control, invisible and unassigned characters go.
    name = "".join(char for char in name if char.isspace() or not unicodedata.category(char).startswith("C"))
    name = _NAME_DROPS.sub("", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name[:MAX_NAME].strip() or None


def clean_login(login):
    """A GitHub login, or None if it doesn't look like one."""
    return login if isinstance(login, str) and _LOGIN.fullmatch(login) else None


def lua_name(name):
    """A name cut down to what is safe in the in-game list (see _LUA_UNSAFE)."""
    return clean_name(_LUA_UNSAFE.sub("", name or ""))


def lua_string(text):
    """`text` as a Lua string literal that can never end early: backslashes and
    quotes escaped, and anything unprintable written as decimal escapes."""
    out = []
    for char in text:
        if char in "\\\"'":
            out.append("\\" + char)
        elif char.isprintable():
            out.append(char)
        else:
            out.extend("\\%03d" % byte for byte in char.encode("utf-8", errors="replace"))
    return '"' + "".join(out) + '"'


def markdown_escape(text):
    """Text that shows as itself in Markdown: no links, emphasis, HTML or table breaks."""
    text = _MARKDOWN.sub(r"\\\1", re.sub(r"\s+", " ", str(text)))
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


##########################################################################################
# Storing a collection
##########################################################################################

def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _iso(value):
    """A time as "2026-10-13T08:07:38Z": from that text, or from unix seconds."""
    if isinstance(value, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value):
        return value
    seconds = _time(value)
    if seconds is None:
        return None
    return datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _source(source):
    source = source or {}
    received = _iso(source.get("received")) or _now()
    return {
        "kind": _text(source.get("kind"), 40) or "file",
        "via": _text(source.get("via"), 40),
        "issue": _integer(source.get("issue"), 1, COUNT_MAX),
        "github_login": clean_login(source.get("github_login")),
        "received": received,
        "first_received": _iso(source.get("first_received")) or received,
    }


def _read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _write(path, text):
    """Writes the file whole, or not at all."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    os.replace(temporary, path)


def _json_text(value):
    return json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def store(envelope, repo_root, source=None):
    """Saves one collection as data/submissions/<collection id>.json, cleaned,
    with where it came from (`source`: kind, issue, github_login, received).

    Players send the same growing collection again and again, so a collection
    already stored is replaced only by a newer copy (a later exportedAt; on a
    tie, the one received later). A copy first sent from one GitHub account is
    not replaced from another. Returns a Stored saying what happened."""
    clean = sanitize(envelope)
    if not has_data(clean):
        raise IngestError("the data is empty: no quests or levels yet. Play a while with collecting on, "
                          "then send it again.")
    data = clean["data"]
    if not data.get("id"):
        # Older exports have no collection id: their content stands in for one.
        data["id"] = hashlib.sha256(_canonical(data).encode("utf-8")).hexdigest()
    collection_id = data["id"]
    source = _source(source)
    path = os.path.join(repo_root, SUBMISSIONS, collection_id + ".json")
    result = Stored(collection_id, "new", path, len(data.get("quests") or {}), len(data.get("levels") or {}))

    if os.path.exists(path):
        old = _read_json(path)
        old_source = old.get("source") or {}
        old_login, new_login = old_source.get("github_login"), source["github_login"]
        if old_login and new_login and old_login.lower() != new_login.lower():
            result.status = "taken"
            return result
        same = old.get("data") == data and old.get("exportedAt") == clean["exportedAt"] \
            and clean["contributor"] in (None, old.get("contributor"))
        if same:
            result.status = "unchanged"
            result.contributor = old.get("contributor")
            return result
        newer = (clean["exportedAt"] or 0, source["received"]) > \
            (old.get("exportedAt") or 0, old_source.get("received") or "")
        if not newer:
            result.status = "older"
            result.contributor = old.get("contributor")
            return result
        result.status = "replaced"
        source["first_received"] = old_source.get("first_received") or old_source.get("received") \
            or source["first_received"]
        # A copy sent without a name keeps the name the last one had.
        clean["contributor"] = clean["contributor"] or clean_name(old.get("contributor"))
        source["github_login"] = new_login or clean_login(old_login)

    result.contributor = clean["contributor"]
    _write(path, _json_text(dict(clean, source=source)))
    return result


##########################################################################################
# Making the merged data and the credits again
##########################################################################################

def load_submissions(repo_root):
    """Every stored submission, cleaned again, in collection id order."""
    records = []
    for path in sorted(glob.glob(os.path.join(repo_root, SUBMISSIONS, "*.json"))):
        try:
            raw = _read_json(path)
            record = sanitize(raw)
        except (ValueError, OSError) as error:
            raise IngestError("%s can't be read: %s" % (os.path.relpath(path, repo_root), error))
        record["data"]["id"] = os.path.splitext(os.path.basename(path))[0]
        record["source"] = _source(raw.get("source"))
        records.append(record)
    return records


def rebuild(repo_root):
    """Makes data/merged.json, data/contributors.json, Contributors.lua and
    the contributors section of CONTRIBUTORS.md again, from every stored
    submission. The same submissions always give the same files."""
    records = load_submissions(repo_root)

    # Merged oldest collection first, so the text kept for a quest is the first seen.
    merged, sources = None, []
    for record in sorted(records, key=lambda record: (record["data"].get("created") or 0, record["data"]["id"])):
        data = dict(record["data"])
        collection_id = data.pop("id")
        merged = merge_exports.merge(merged, data)
        sources.append({
            "id": collection_id,
            "contributor": record["contributor"],
            "addonVersion": record["addonVersion"],
            "build": record["build"],
            "exportedAt": record["exportedAt"],
            "via": record["source"]["via"],
            "quests": len(data.get("quests") or {}),
            "levels": len(data.get("levels") or {}),
        })
    merged = dict(merged or {})
    merged["sources"] = sources
    _write(os.path.join(repo_root, "data", "merged.json"), _json_text(merged))

    contributors = _contributors(records)
    _write(os.path.join(repo_root, "data", "contributors.json"), _json_text(contributors))
    names = credited_names(contributors)
    lua = contributors_lua(names)
    check_contributors_lua(lua)
    _write(os.path.join(repo_root, "Contributors.lua"), lua)
    _write_contributors_markdown(os.path.join(repo_root, "CONTRIBUTORS.md"), contributors)
    return {
        "submissions": len(records),
        "quests": len(merged.get("quests") or {}),
        "levels": len(merged.get("levels") or {}),
        "contributors": len(names),
    }


def _contributors(records):
    """Who sent what: one entry per name, in the order they first sent data."""
    groups = {}
    ordered = sorted(records, key=lambda record: (record["source"]["first_received"], record["data"]["id"]))
    for record in ordered:
        source = record["source"]
        login = source["github_login"]
        name = record["contributor"] or login or "Anonymous"
        group = groups.setdefault(name.casefold(), {
            "name": name, "github": None, "submissions": 0, "quests": set(), "levels": set(),
            "first": source["first_received"], "last": source["received"],
        })
        group["github"] = group["github"] or login
        group["submissions"] += 1
        group["quests"].update((record["data"].get("quests") or {}).keys())
        group["levels"].update((record["data"].get("levels") or {}).keys())
        group["first"] = min(group["first"], source["first_received"])
        group["last"] = max(group["last"], source["received"])
    out = []
    for group in groups.values():
        out.append(dict(group, quests=len(group["quests"]), levels=len(group["levels"])))
    return sorted(out, key=lambda group: (group["first"], group["name"].casefold()))


def _anonymous(contributor):
    return contributor["name"].casefold() == "anonymous"


def credited_names(contributors):
    """The names for the in-game list: no anonymous ones, each name once."""
    names, seen = [], set()
    for contributor in contributors:
        name = lua_name(contributor["name"])
        if name and not _anonymous(contributor) and name.casefold() not in seen:
            seen.add(name.casefold())
            names.append(name)
    return names


def contributors_lua(names):
    lines = [
        "local _, AP = ...",
        "",
        "-- Generated by Tools/ingest.py from data/contributors.json: the players who sent",
        "-- collected data, in the order they first did. Don't edit it by hand; it is made",
        "-- again each time data comes in (docs/data-submission.md).",
        "AP.CONTRIBUTORS = {",
    ]
    lines += ["\t%s," % lua_string(name) for name in names]
    lines.append("}")
    return "\n".join(lines) + "\n"


# One entry per line between the braces: a double-quoted string in which every
# backslash starts an escape, and no bare quote or control character.
_LUA_ENTRY = re.compile(r'\t"(?:[^"\\\x00-\x1f\x7f]|\\[\\"\']|\\[0-9]{3})*",')


def check_contributors_lua(text):
    """Raises IngestError unless the in-game list is exactly the shape
    contributors_lua() writes: one plain string per line."""
    lines = text.split("\n")
    try:
        start = lines.index("AP.CONTRIBUTORS = {")
        end = lines.index("}", start)
    except ValueError:
        raise IngestError("Contributors.lua has no AP.CONTRIBUTORS = { ... } list")
    if lines[0] != "local _, AP = ..." or any(line.strip() for line in lines[end + 1:]) \
            or any(line and not line.startswith("--") for line in lines[1:start]):
        raise IngestError("Contributors.lua is not in its usual shape")
    for line in lines[start + 1:end]:
        if not _LUA_ENTRY.fullmatch(line) or not line[1:].isprintable():
            raise IngestError("Contributors.lua has a line that is not one plain string: %r" % line)


def _contributors_section(contributors):
    shown = [contributor for contributor in contributors if not _anonymous(contributor)]
    anonymous = sum(contributor["submissions"] for contributor in contributors if _anonymous(contributor))
    lines = [MARK_START, "<!-- Made by Tools/ingest.py from data/contributors.json: edits here are lost. -->", ""]
    if shown:
        lines += ["| Player | Quests | Levels |", "|---|---:|---:|"]
        for contributor in shown:
            name = markdown_escape(contributor["name"])
            login = clean_login(contributor["github"])
            if login:
                name = "[%s](https://github.com/%s)" % (name, login)
            lines.append("| %s | %d | %d |" % (name, contributor["quests"], contributor["levels"]))
    else:
        lines.append("_No one yet. Be the first: [how to send your data](docs/data-submission.md)._")
    if anonymous:
        lines += ["", "And %d collection%s sent without a name." % (anonymous, "" if anonymous == 1 else "s")]
    lines += ["", MARK_END]
    return "\n".join(lines)


CONTRIBUTORS_INTRO = """# Contributors

Pathfinder's guides for WoW: Forever are being written from the quest and
leveling data players collect in game. These are the players who sent theirs.
Thank you!

Send yours: [docs/data-submission.md](docs/data-submission.md).
"""


def _write_contributors_markdown(path, contributors):
    """Writes the contributors between the markers in CONTRIBUTORS.md, leaving
    the rest of the file as it is (and making the file if there is none)."""
    section = _contributors_section(contributors)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    else:
        text = CONTRIBUTORS_INTRO
    start, end = text.find(MARK_START), text.find(MARK_END)
    if start >= 0 and end > start:
        text = text[:start] + section + text[end + len(MARK_END):]
    else:
        text = text.rstrip("\n") + "\n\n" + section + "\n"
    _write(path, text)


##########################################################################################
# The command line
##########################################################################################

RESULT_WORDS = {
    "new": "new",
    "replaced": "a newer copy: replaced the one stored",
    "unchanged": "already stored, the same",
    "older": "older than the copy stored: kept that one",
    "taken": "first sent from another GitHub account: not replaced",
}


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Adds players' data files (share codes, exports, SavedVariables files, zipped or "
                    "not) to data/submissions/ and makes the merged data and the credits again.")
    parser.add_argument("files", nargs="*", metavar="FILE", help="files to add; none: only make the files again")
    parser.add_argument("--credit", metavar="NAME", help="the name to credit (instead of the one set in game)")
    parser.add_argument("--root", default=ROOT, help="the repository (default: the one this script is in)")
    args = parser.parse_args(argv)

    credit = clean_name(args.credit)
    taken = 0
    for path in args.files:
        name = os.path.basename(path)
        try:
            if os.path.getsize(path) > MAX_INPUT:
                print("%s: bigger than 25 MB, skipped" % name)
                continue
            with open(path, "rb") as handle:
                content = handle.read()
        except OSError as error:
            print("%s: can't be read (%s)" % (name, error.strerror or error))
            continue
        problems = []
        for submission in decode(content, name, problems):
            try:
                envelope = sanitize(submission.envelope)
                envelope["contributor"] = credit or envelope["contributor"]
                result = store(envelope, args.root, {"kind": "file", "via": submission.kind})
            except IngestError as error:
                print("%s (%s): %s" % (name, submission.kind, error))
                continue
            if result.status in ACCEPTED:
                taken += 1
            print("%s (%s): collection %s, %d quests, %d levels, credited to %s: %s" % (
                name, submission.kind, result.id[:12], result.quests, result.levels,
                result.contributor or "Anonymous", RESULT_WORDS[result.status]))
        for problem in problems:
            print("  " + problem)

    totals = rebuild(args.root)
    print("Stored: %d collections, %d quests and %d levels in all, %d credited players." % (
        totals["submissions"], totals["quests"], totals["levels"], totals["contributors"]))
    return 0 if taken or not args.files else 2


if __name__ == "__main__":
    sys.exit(main())
