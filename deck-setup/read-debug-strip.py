#!/usr/bin/env python3
"""Reads DeckKit's debug strip (addons/DeckKit/Debug.lua) off the Steam Deck's screen and prints it.

Run on the Deck as the desktop user (deck), with the game in Gaming Mode:
    python3 read-debug-strip.py            # take a screenshot and decode it
    python3 read-debug-strip.py shot.png   # decode an existing screenshot
It asks gamescope for a full-composite screenshot (overlays included), decodes only the top rows
of the PNG (plain Python, no libraries), and prints the text. Exit status 1 if no strip is found.
"""
import os, struct, subprocess, sys, time, zlib

CELL, PER_ROW, ROWS = 4, 300, 3
SYNC = [(3, 0, 0), (0, 3, 0), (0, 0, 3), (3, 3, 3)]
LEVELS = 4
SHOT = "/tmp/gamescope.png"


def screenshot():
    before = os.path.getmtime(SHOT) if os.path.exists(SHOT) else 0
    env = dict(os.environ, DISPLAY=":0")
    # 2 = base plane only: the game's own picture, without overlays drawn on top of it.
    subprocess.run(["xprop", "-root", "-f", "GAMESCOPECTRL_REQUEST_SCREENSHOT", "32c",
                    "-set", "GAMESCOPECTRL_REQUEST_SCREENSHOT", "2"], env=env, check=True)
    for _ in range(60):  # up to ~6 s
        time.sleep(0.1)
        if os.path.exists(SHOT) and os.path.getmtime(SHOT) > before and os.path.getsize(SHOT) > 0:
            time.sleep(0.2)
            return SHOT
    sys.exit("no screenshot")


def top_rows(path, count):
    """The first `count` rows of an 8-bit RGB/RGBA PNG, as lists of (r, g, b) tuples."""
    data = open(path, "rb").read()
    pos, idat, width = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, _, depth, color = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and color in (2, 6), "unsupported PNG"
            bpp = 4 if color == 6 else 3
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    stride = width * bpp
    need = count * (stride + 1)
    raw, inflater = b"", zlib.decompressobj()
    for chunk in idat:
        raw += inflater.decompress(chunk, need - len(raw))
        if len(raw) >= need:
            break
    rows, prev = [], bytearray(stride)
    for y in range(count):
        kind, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], (prev[x - bpp] if x >= bpp else 0)
            if kind == 1: line[x] = (line[x] + a) & 255
            elif kind == 2: line[x] = (line[x] + b) & 255
            elif kind == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif kind == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([(line[i], line[i + 1], line[i + 2]) for i in range(0, stride, bpp)])
        prev = line
    return rows


def decode(path):
    rows = top_rows(path, ROWS * CELL)
    pixels = []
    for i in range(PER_ROW * ROWS):
        y, x = (i // PER_ROW) * CELL + CELL // 2, (i % PER_ROW) * CELL + CELL // 2
        pixels.append(rows[y][x])
    # Sync: only full-on / full-off, which survive gamma.
    sync = [tuple(1 if v > 127 else 0 for v in p) for p in pixels[:len(SYNC)]]
    if sync != [tuple(1 if v else 0 for v in c) for c in SYNC]:
        if os.environ.get("STRIP_DEBUG"):
            print("first pixels:", pixels[:6], file=sys.stderr)
        return None
    # The ramp: how each level actually came out, per channel.
    ramp = pixels[len(SYNC):len(SYNC) + LEVELS]
    def level(value, channel):
        return min(range(LEVELS), key=lambda n: abs(ramp[n][channel] - value))
    digits = [level(p[c], c) for p in pixels[len(SYNC) + LEVELS:] for c in range(3)]
    if False:
        if os.environ.get("STRIP_DEBUG"):
            print("first cells (nibbles):", cells[:8], file=sys.stderr)
            print("raw pixels row 2, x 0..20:", rows[2][:20], file=sys.stderr)
        return None
    def number(at, count):
        value = 0
        for d in digits[at:at + count]:
            value = value * 4 + d
        return value
    length, checksum = number(0, 8), number(8, 8)
    text = bytes(number(16 + 4 * k, 4) for k in range(length)) if 16 + 4 * length <= len(digits) else b""
    s1 = s2 = 0
    for b in text:
        s1 = (s1 + b) % 255
        s2 = (s2 + s1) % 255
    if len(text) != length or (s2 << 8 | s1) != checksum:
        if os.environ.get("STRIP_DEBUG"):
            print("length %d, checksum %d vs %d, start %r" % (length, checksum, s2 << 8 | s1, text[:60]), file=sys.stderr)
        return None
    return text.decode("utf-8", "replace")


if __name__ == "__main__":
    shot = sys.argv[1] if len(sys.argv) > 1 else screenshot()
    text = decode(shot)
    if shot == SHOT and len(sys.argv) == 1:
        os.remove(SHOT)
    if text is None:
        sys.exit("no debug strip found (is /deckkit debug on?)")
    print(text)
