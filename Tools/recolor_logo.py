"""
Recolours the red parts of the addon's logo textures (media/*.tga) to another colour, keeping their
light and shade: the rune ring, the AEGIS letters and the banner. Gold, silver and the dark
background stay. Standard library only.

    python Tools/recolor_logo.py media/logo.tga media/logo.tga 1E6FD9
    python Tools/recolor_logo.py media/logo.tga preview.png          a PNG to look at (no recolouring)

Reads and writes 32-bit TGAs, run-length encoded or not (what the client loads). The WoW: Forever
blue used for the Forever logos is 1E6FD9 (the same as the Discord releases posts).
"""

import colorsys
import struct
import sys
import zlib


def read_tga(path):
    with open(path, "rb") as handle:
        data = handle.read()
    id_length, colour_map, image_type = data[0], data[1], data[2]
    width, height = struct.unpack("<HH", data[12:16])
    bpp, descriptor = data[16], data[17]
    if colour_map or bpp != 32 or image_type not in (2, 10):
        sys.exit("{}: only 32-bit true-colour TGAs (type {}, {} bit).".format(path, image_type, bpp))
    pos, count = 18 + id_length, width * height
    pixels = bytearray()
    if image_type == 2:
        pixels = bytearray(data[pos:pos + count * 4])
    else:
        while len(pixels) < count * 4:
            head = data[pos]
            pos += 1
            run = (head & 0x7F) + 1
            if head & 0x80:
                pixels += data[pos:pos + 4] * run
                pos += 4
            else:
                pixels += data[pos:pos + run * 4]
                pos += run * 4
    rows = [bytearray(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height)]
    if not descriptor & 0x20:          # stored bottom row first
        rows.reverse()
    # BGRA to RGBA
    for row in rows:
        for i in range(0, len(row), 4):
            row[i], row[i + 2] = row[i + 2], row[i]
    return width, height, rows


def write_tga(path, width, height, rows):
    """Run-length encoded, bottom row first, as the originals are."""
    out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 10, 0, 0, 0, 0, 0, width, height, 32, 8))
    for row in reversed(rows):
        pixels = [bytes((row[i + 2], row[i + 1], row[i], row[i + 3])) for i in range(0, len(row), 4)]
        i = 0
        while i < len(pixels):
            run = 1
            while i + run < len(pixels) and run < 128 and pixels[i + run] == pixels[i]:
                run += 1
            if run > 1:
                out += bytes((0x80 | (run - 1),)) + pixels[i]
                i += run
                continue
            start = i
            while i < len(pixels) and i - start < 128 and (i + 1 >= len(pixels) or pixels[i + 1] != pixels[i]):
                i += 1
            if i == start:
                i += 1
            out += bytes((i - start - 1,)) + b"".join(pixels[start:i])
    out += b"\x00" * 8 + b"TRUEVISION-XFILE.\x00"
    with open(path, "wb") as handle:
        handle.write(out)


def write_png(path, width, height, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def is_red(h, s, v):
    """Reds and red-oranges, not gold (about 40 degrees) or greys. 27 degrees keeps the gold
    ring's orange edges gold."""
    degrees = h * 360
    return s >= 0.28 and v >= 0.08 and (degrees >= 335 or degrees <= 27)


def recolour(rows, target):
    th = colorsys.rgb_to_hsv(*(c / 255 for c in target))[0]
    changed = 0
    for row in rows:
        for i in range(0, len(row), 4):
            if row[i + 3] == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(row[i] / 255, row[i + 1] / 255, row[i + 2] / 255)
            if is_red(h, s, v):
                r, g, b = colorsys.hsv_to_rgb(th, s, v)
                row[i], row[i + 1], row[i + 2] = round(r * 255), round(g * 255), round(b * 255)
                changed += 1
    return changed


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    width, height, rows = read_tga(argv[0])
    if len(argv) > 2:
        colour = argv[2].lstrip("#")
        changed = recolour(rows, tuple(int(colour[i:i + 2], 16) for i in (0, 2, 4)))
        print("{}: {} of {} pixels recoloured".format(argv[0], changed, width * height))
    (write_png if argv[1].lower().endswith(".png") else write_tga)(argv[1], width, height, rows)
    print("Wrote", argv[1])


if __name__ == "__main__":
    main(sys.argv[1:])
