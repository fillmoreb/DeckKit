#!/usr/bin/env python3
"""Generates DeckKit's paddle chord glyphs: addons/DeckKit/media/chords.tga.

One 512 x 256 texture of 64 x 64 cells, 8 across and 4 down. Cell n (0-31, left to right, top to
bottom): n % 16 is the set of grips held (bit 1 L4, 2 R4, 4 L5, 8 R5, the same order as Chords.lua's
GRIPS), and n >= 16 is the held ("hold") version. Each cell is the Deck's back as you hold it:
L4 top left, L5 below it, R4 top right, R5 below it; held grips lit, the others dim outlines. The
hold version adds a bar along the bottom. Chords.lua shows a cell inline with |T...|t texcoords.
"""
import os, struct

CELL, COLS, ROWS = 64, 8, 4
W, H = CELL * COLS, CELL * ROWS
SS = 4  # supersampling per axis, for smooth edges

LIT = (255, 196, 70)      # gold, like the menu's headings
DIM = (150, 140, 120)     # unlit outline
BAR = (255, 196, 70)

# Grip rectangles in a cell (x0, y0, x1, y1), by bit: L4, R4, L5, R5.
GW, GH = 22, 15
LX, RX = 7, 64 - 7 - GW
TY, BY = 9, 9 + GH + 5
GRIPS = [(LX, TY), (RX, TY), (LX, BY), (RX, BY)]
RADIUS = 5
OUTLINE = 2.0
BAR_RECT = (12, 50, 52, 55)


def rounded(px, py, x0, y0, x1, y1, r):
    """Signed distance from (px, py) to a rounded rectangle (negative inside)."""
    cx, cy = min(max(px, x0 + r), x1 - r), min(max(py, y0 + r), y1 - r)
    dx, dy = px - cx, py - cy
    d = (dx * dx + dy * dy) ** 0.5 - r
    if x0 + r <= px <= x1 - r and y0 + r <= py <= y1 - r:
        d = -min(px - x0, x1 - px, py - y0, y1 - py)
    return d


def cell_pixel(mask, hold, px, py):
    """Color and coverage (0..1) of one sample point in a cell."""
    for bit, (gx, gy) in enumerate(GRIPS):
        d = rounded(px, py, gx, gy, gx + GW, gy + GH, RADIUS)
        if mask & (1 << bit):
            if d <= 0:
                return LIT, 1.0
        elif -OUTLINE <= d <= 0:
            return DIM, 0.85
    if hold:
        x0, y0, x1, y1 = BAR_RECT
        if rounded(px, py, x0, y0, x1, y1, 2.5) <= 0:
            return BAR, 1.0
    return (0, 0, 0), 0.0


def main():
    pixels = bytearray(W * H * 4)
    for n in range(COLS * ROWS):
        mask, hold = n % 16, n >= 16
        ox, oy = (n % COLS) * CELL, (n // COLS) * CELL
        for y in range(CELL):
            for x in range(CELL):
                r = g = b = a = 0.0
                for sy in range(SS):
                    for sx in range(SS):
                        (cr, cg, cb), cov = cell_pixel(mask, hold, x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                        r += cr * cov; g += cg * cov; b += cb * cov; a += cov
                i = ((oy + y) * W + ox + x) * 4
                if a > 0:
                    pixels[i:i + 4] = bytes((round(b / a), round(g / a), round(r / a), round(255 * a / SS / SS)))
    # 32-bit uncompressed TGA, origin top left (descriptor 0x28: 8 alpha bits + top-left).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x28)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "DeckKit", "media")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "chords.tga")
    with open(path, "wb") as f:
        f.write(header + pixels)
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
