"""
Reads a WoW SavedVariables file without running it.

The files players send in are untrusted: they are parsed here as data -- tables,
strings, numbers, booleans, nil -- and anything else (a function call, an
expression, a `local`) is refused. Never `dofile` or `lupa.execute` a submitted file.

    from savedvariables import load
    variables = load(open("Aegis_Forever_Pathfinder.lua", encoding="utf-8").read())
    collect = variables["AegisPathfinderDB"]["collect"]

Tables come back as dicts; a table whose keys are exactly 1..n comes back as a list.
"""

import re

MAX_DEPTH = 64
MAX_SIZE = 64 * 1024 * 1024

_TOKEN = re.compile(r"""
    (?P<space>\s+)
  | (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<string>"(?:[^"\\\n]|\\.|\\\n)*"|'(?:[^'\\\n]|\\.|\\\n)*')
  | (?P<long>\[(?P<leq>=*)\[.*?\](?P=leq)\])
  | (?P<number>0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;\-])
""", re.VERBOSE | re.DOTALL)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
            "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class ParseError(ValueError):
    pass


def _unescape(body):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= len(body):
            raise ParseError("string ends in a backslash")
        c = body[i]
        if c in _ESCAPES:
            out.append(_ESCAPES[c])
            i += 1
        elif c.isdigit():
            digits = re.match(r"\d{1,3}", body[i:]).group(0)
            out.append(chr(int(digits)))
            i += len(digits)
        elif c == "x":
            out.append(chr(int(body[i + 1:i + 3], 16)))
            i += 3
        else:
            raise ParseError("unknown escape \\%s" % c)
    # WoW writes UTF-8 bytes one escape at a time; put the bytes back together.
    raw = "".join(out)
    try:
        return raw.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return raw


def _tokens(text):
    pos = 0
    while pos < len(text):
        match = _TOKEN.match(text, pos)
        if not match:
            raise ParseError("unexpected %r at character %d" % (text[pos:pos + 20], pos))
        pos = match.end()
        kind = match.lastgroup
        if kind in ("space", "comment") or match.group("comment") is not None:
            continue
        value = match.group(0)
        if match.group("string") is not None:
            yield ("string", _unescape(value[1:-1]))
        elif match.group("long") is not None:
            level = len(match.group("leq"))
            body = value[level + 2:-(level + 2)]
            yield ("string", body[1:] if body.startswith("\n") else body)
        elif match.group("number") is not None:
            yield ("number", int(value, 16) if value[:2].lower() == "0x" else
                   (float(value) if any(ch in value for ch in ".eE") else int(value)))
        elif match.group("name") is not None:
            yield ("name", value)
        else:
            yield ("op", value)
    yield ("end", None)


class _Parser:
    def __init__(self, text):
        self.tokens = _tokens(text)
        self.kind, self.value = next(self.tokens)

    def advance(self):
        kind, value = self.kind, self.value
        self.kind, self.value = next(self.tokens)
        return kind, value

    def expect(self, kind, value=None):
        if self.kind != kind or (value is not None and self.value != value):
            raise ParseError("expected %s %s, got %s %r" % (kind, value or "", self.kind, self.value))
        return self.advance()[1]

    def value_(self, depth):
        if depth > MAX_DEPTH:
            raise ParseError("tables nested too deep")
        kind, value = self.kind, self.value
        if kind == "string" or kind == "number":
            self.advance()
            return value
        if kind == "op" and value == "-":
            self.advance()
            if self.kind != "number":
                raise ParseError("a minus sign must come before a number")
            return -self.advance()[1]
        if kind == "name" and value in ("true", "false", "nil"):
            self.advance()
            return {"true": True, "false": False, "nil": None}[value]
        if kind == "op" and value == "{":
            return self.table(depth + 1)
        raise ParseError("only data is allowed: got %s %r" % (kind, value))

    def table(self, depth):
        self.expect("op", "{")
        result, index = {}, 1
        while not (self.kind == "op" and self.value == "}"):
            if self.kind == "op" and self.value == "[":
                self.advance()
                key = self.value_(depth)
                self.expect("op", "]")
                self.expect("op", "=")
                result[key] = self.value_(depth)
            elif self.kind == "name" and self.value not in ("true", "false", "nil"):
                key = self.advance()[1]
                self.expect("op", "=")
                result[key] = self.value_(depth)
            else:
                result[index] = self.value_(depth)
                index += 1
            if self.kind == "op" and self.value in (",", ";"):
                self.advance()
            elif not (self.kind == "op" and self.value == "}"):
                raise ParseError("expected , or } in a table, got %r" % (self.value,))
        self.expect("op", "}")
        result = {k: v for k, v in result.items() if v is not None}
        if result and all(isinstance(k, int) for k in result) and sorted(result) == list(range(1, len(result) + 1)):
            return [result[i] for i in range(1, len(result) + 1)]
        return result

    def chunk(self):
        variables = {}
        while self.kind != "end":
            name = self.expect("name")
            if name in ("local", "function", "return", "true", "false", "nil"):
                raise ParseError("only `Name = value` assignments are allowed, got %r" % name)
            self.expect("op", "=")
            variables[name] = self.value_(0)
            if self.kind == "op" and self.value == ";":
                self.advance()
        return variables


def load(text):
    """The variables a SavedVariables file assigns, as Python values."""
    if len(text) > MAX_SIZE:
        raise ParseError("file too large")
    if text.startswith("﻿"):
        text = text[1:]
    return _Parser(text).chunk()
