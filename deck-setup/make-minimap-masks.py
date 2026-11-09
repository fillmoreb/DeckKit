#!/usr/bin/env python3
"""Generates DeckHUD's minimap masks: addons/DeckHUD/masks/crop_NN.tga, NN = 01..45.

Each mask is 8 x 256, opaque white with NN% of its height transparent, split between the top and
the bottom. The minimap stretches its mask over its (square) area, so crop_12 shows the middle 88%
of the map's height at full width. 8 wide is enough: the masks only vary from top to bottom.
"""
import os, struct

W, H = 8, 256
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "DeckHUD", "masks")
os.makedirs(out, exist_ok=True)
for pct in range(1, 46):
    cut = round(H * pct / 100 / 2)  # transparent rows at each end
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
    rows = bytearray()
    for y in range(H):
        a = 0 if (y < cut or y >= H - cut) else 255
        rows += bytes((255, 255, 255, a)) * W
    with open(os.path.join(out, "crop_%02d.tga" % pct), "wb") as f:
        f.write(header + rows)
print("wrote 45 masks to", os.path.normpath(out))
