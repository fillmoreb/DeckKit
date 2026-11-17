#!/usr/bin/env python3
"""Generates DeckHUD's compass pointer: addons/DeckHUD/media/compass-pointer.tga.

Cut from Ben's drawing, compass/pointer-source.png: a long metal bar with a winged ornament hanging from its
middle, a purple gem set into the bar above the ornament's point. The pointer is the ornament alone: it hangs
from the status bar's own metal edge, so the drawing's bar is dropped except for the stretch the ornament grows
out of, which fades out sideways into the game's edge.

Scaled so the drawing's bar (BAR_TOP..BAR_BOTTOM, 31 rows) comes out EDGE px thick: 6, a little heavier than the
status bar's 4 px metal edge, so it reads as a boss on the edge and the wings still show (at 4 the ornament is 64
px wide and its detail is lost). On the Deck a UI unit is a screen pixel: the art lands 1:1 at its size, 96 x 26.

The texture holds two layers, so the gem can be tinted on its own (plum, warming to lilac as the waypoint comes
ahead) while the metal keeps its own colours:
  rows 0..25   the metal, the gem cut out
  rows 32..57  the gem, in gray (white at its brightest), to be tinted with SetVertexColor
Compass.lua's POINTER_* constants describe this layout; change them together.

To change the look, change the drawing or the numbers here and run this again; never hand-edit the texture.
"""
import importlib.util, os, struct

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "compass", "pointer-source.png")
OUT = os.path.join(HERE, "..", "addons", "DeckHUD", "media", "compass-pointer.tga")

BAR_TOP, BAR_BOTTOM = 286, 316   # the drawing's bar, rows (inclusive)
TIP = 421                        # a row just past the ornament's point
CENTER = 998                     # the ornament's middle, column
EDGE = 6                         # the drawing's bar comes out this thick, px
OUT_W = 96                       # the pointer's width, px
FADE_IN, FADE_OUT = 90, 170      # the bar's stretch: kept within FADE_IN of the middle, gone by FADE_OUT
DUST = 40                        # alpha under this is the drawing's dust, not art
TEX_W, TEX_H, GEM_ROW = 128, 64, 32


def load_png(path):
    spec = importlib.util.spec_from_file_location("glyphs", os.path.join(HERE, "make-chord-glyphs.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.read_png(path)


def gem_weight(r, g, b):
    """How much a pixel is the gem: purple (red and blue over green), not the gray metal."""
    sat = min(r, b) - g
    return max(0.0, min(1.0, (sat - 6) / 18.0))


def weights(n_in, n_out):
    """Box-filter weights: for each output pixel, [(input index, share)], shares summing to 1."""
    k = n_in / n_out
    out = []
    for o in range(n_out):
        a, b, ws = o * k, (o + 1) * k, []
        i = int(a)
        while i < b and i < n_in:
            share = min(b, i + 1) - max(a, i)
            if share > 0:
                ws.append((i, share / k))
            i += 1
        out.append(ws)
    return out


def main():
    src = load_png(SOURCE)
    scale = EDGE / (BAR_BOTTOM - BAR_TOP + 1)
    src_w = OUT_W / scale
    x0 = CENTER - src_w / 2
    left, cols = int(round(x0)), int(round(src_w))
    rows = TIP - BAR_TOP
    out_h = int(round(rows * scale))

    # The two layers at the drawing's size, premultiplied: metal (r, g, b, a) and gem (v, a).
    metal = [[(0.0, 0.0, 0.0, 0.0)] * cols for _ in range(rows)]
    gem = [[(0.0, 0.0)] * cols for _ in range(rows)]
    gem_max = 0
    for y in range(rows):
        sy = BAR_TOP + y
        for x in range(cols):
            sx = left + x
            r, g, b, a = src[sy][sx]
            if a < DUST:
                continue
            a = a / 255.0
            if sy <= BAR_BOTTOM:  # the bar: only the stretch the ornament grows from, fading out sideways
                d = abs(sx - CENTER)
                a *= max(0.0, min(1.0, (FADE_OUT - d) / float(FADE_OUT - FADE_IN)))
            w = gem_weight(r, g, b)
            ma = a * (1 - w)
            metal[y][x] = (r / 255.0 * ma, g / 255.0 * ma, b / 255.0 * ma, ma)
            v = max(r, g, b)
            if w > 0.5:
                gem_max = max(gem_max, v)
            gem[y][x] = (v / 255.0 * a * w, a * w)

    # Down to size: box filter across, then down.
    wx, wy = weights(cols, OUT_W), weights(rows, out_h)

    def shrink(layer, n):
        across = [[tuple(sum(row[i][c] * s for i, s in wx[o]) for c in range(n)) for o in range(OUT_W)]
                  for row in layer]
        return [[tuple(sum(across[i][x][c] * s for i, s in wy[o]) for c in range(n)) for x in range(OUT_W)]
                for o in range(out_h)]

    small_metal, small_gem = shrink(metal, 4), shrink(gem, 2)

    tex = [[(0, 0, 0, 0)] * TEX_W for _ in range(TEX_H)]
    clamp = lambda v: max(0, min(255, int(round(v * 255))))
    for y in range(out_h):
        for x in range(OUT_W):
            r, g, b, a = small_metal[y][x]
            if a > 0:
                tex[y][x] = (clamp(r / a), clamp(g / a), clamp(b / a), clamp(a))
            v, a = small_gem[y][x]
            if a > 0:
                gray = clamp(min(1.0, v / a * 255.0 / gem_max))
                tex[GEM_ROW + y][x] = (gray, gray, gray, clamp(a))

    # 32-bit TGA, top-left origin (descriptor 0x28: 8 alpha bits, top to bottom), BGRA.
    with open(OUT, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, TEX_W, TEX_H, 32, 0x28))
        for row in tex:
            f.write(bytes(c for r, g, b, a in row for c in (b, g, r, a)))
    print("wrote %s: %d x %d art (scale %.4f), bar rows 0..%d" % (os.path.relpath(OUT), OUT_W, out_h, scale,
                                                                   EDGE - 1))


if __name__ == "__main__":
    main()
