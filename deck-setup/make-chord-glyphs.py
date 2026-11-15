#!/usr/bin/env python3
"""Generates DeckKit's grip chord glyph: addons/DeckKit/media/chords-24.tga.

Ben's pixel art, for the Deck's 1280 x 800 screen, where a UI unit is a screen pixel: shown at 24 they land
1:1. One 256 x 128 texture holding 8 x 4 cells of 24 x 24. Cell n (0-31, left to right, top to bottom):
n % 16 is the set of grips held (bit 1 L4, 2 R4, 4 L5, 8 R5, the same order as Chords.lua's GRIPS), n >= 16
the held ("hold") version. Chords.Glyph shows a cell inline with |T...|t texcoords.

Built from his two drawings in glyphs/: compact-press.png (the Deck's back grips: L4 top left, L5 below it,
R4 top right, R5 below it) and compact-hold.png (the same with the hold bar). Each grip's inside is
flood-filled from a point (SEEDS): lilac (DeckKit.COLORS.LILAC) when it's held, dark gray when it isn't; the
drawings' white outline becomes RING; then the visible rows are centered up and down in the cell (an odd
spare row goes below). To change the look, redraw those (or the colors here) and run this again; never
hand-edit the texture.
"""
import os, struct

GLYPH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "glyphs")
CC = 24                                       # cell size
SEEDS = [(6, 3), (16, 3), (6, 10), (16, 10)]  # a point inside each grip, by bit: L4, R4, L5, R5
HELD = (0xB8, 0x7A, 0xFF, 255)               # lilac
NOT_HELD = (0x33, 0x33, 0x33, 255)           # dark gray
RING = (155, 173, 183, 255)                  # the drawings' white outline, darkened and tinted cool gray-blue


def read_png(path):
    """An 8-bit RGBA or RGB PNG (non-interlaced) as rows of (r, g, b, a) tuples."""
    import zlib
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", path
    i, idat = 8, b""
    while i < len(d):
        n, = struct.unpack(">I", d[i:i + 4])
        kind, body = d[i + 4:i + 8], d[i + 8:i + 8 + n]
        i += 12 + n
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
    assert depth == 8 and interlace == 0 and ctype in (2, 6), "%s: 8-bit RGB(A), not interlaced" % path
    ch = 4 if ctype == 6 else 3
    raw, stride, rows, prev, p = zlib.decompress(idat), w * ch, [], bytearray(w * ch), 0
    for _ in range(h):
        f, line = raw[p], bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0
            b, c = prev[x], (prev[x - ch] if x >= ch else 0)
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * ch:x * ch + ch]) + ((255,) if ch == 3 else ()) for x in range(w)])
        prev = line
    return rows


def flood(img, x, y, color):
    """Fills the 4-connected area of (x, y)'s color with `color`."""
    old = img[y][x]
    if old == color:
        return
    todo = [(x, y)]
    while todo:
        x, y = todo.pop()
        if 0 <= y < len(img) and 0 <= x < len(img[0]) and img[y][x] == old:
            img[y][x] = color
            todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]


def main():
    bases = [read_png(os.path.join(GLYPH_DIR, f)) for f in ("compact-press.png", "compact-hold.png")]
    SW, SH = 256, 128
    pixels = bytearray(SW * SH * 4)
    for n in range(32):
        mask = n % 16
        img = [list(row) for row in bases[1 if n >= 16 else 0]]
        for bit, (sx, sy) in enumerate(SEEDS):
            flood(img, sx, sy, HELD if mask & (1 << bit) else NOT_HELD)
        img = [[RING if px == (255, 255, 255, 255) else px for px in row] for row in img]
        # Centered up and down: the drawing's visible rows, moved to the middle of the cell.
        seen = [y for y, row in enumerate(img) if any(px[3] for px in row)]
        top, height = seen[0], seen[-1] - seen[0] + 1
        dy = (CC - height) // 2 - top
        ox, oy = (n % 8) * CC, (n // 8) * CC
        for y in range(CC):
            for x in range(CC):
                sy = y - dy
                if not 0 <= sy < len(img):
                    continue
                r, g, b, a = img[sy][x]
                i = ((oy + y) * SW + ox + x) * 4
                pixels[i:i + 4] = bytes((b, g, r, a))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SW, SH, 32, 0x28)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "DeckKit", "media",
                        "chords-24.tga")
    with open(path, "wb") as f:
        f.write(header + pixels)
    print("wrote", os.path.normpath(path))




if __name__ == "__main__":
    main()
