#!/usr/bin/env python3
# Sets up the four back grips of a Steam Deck controller layout for DeckKit's grip chords.
#
# Each grip sends two plain keys and nothing else: its own key while it's held (Full_Press), and a
# second key once it has been held for the long-press time (Long_Press). DeckKit's secure code in the
# game turns those into chords (any set of grips, fired on release) and holds (fired when the long
# keys arrive). Steam does no chord logic: no layers, no double presses.
#
#   L4 = F1 / F5    R4 = F2 / F6    L5 = F3 / F7    R5 = F4 / F8
#
# Everything else in the layout is left alone. Keep these keys in step with ns.GRIPS in
# addons/DeckKit/Core.lua (a test checks). All of the setup's key assignments: README.md, "Keys".
#
# Usage:
#   make-chord-layout.py IN.vdf OUT.vdf [--hold-ms 400] [--hold-ms-L4 500 ...]
#   make-chord-layout.py --install [--game NAME | --layout PATH] [--hold-ms ...]
#       on the Deck, while Steam is NOT running (Desktop Mode, Steam exited): finds your WoW: Forever
#       controller layout and rewrites it, keeping a backup next to it. With several candidates it
#       lists them; pick one with --game (the layout folder's name) or --layout (the file).
# The long-press time is in milliseconds (400 by default); shorter holds are snappier but turn more
# quick squeezes into holds.
import argparse, os, shutil, subprocess, sys, time

GRIPS = [  # (name, Steam input, key while held, key after the long press)
    ("L4", "button_back_left_upper", "F1", "F5"),
    ("R4", "button_back_right_upper", "F2", "F6"),
    ("L5", "button_back_left", "F3", "F7"),
    ("R5", "button_back_right", "F4", "F8"),
]
DEFAULT_HOLD_MS = 400
# Steam keeps one layout per game (or non-Steam shortcut) here: <account id>/config/<game>/controller_neptune.vdf
CONFIGS = os.path.expanduser("~/.local/share/Steam/steamapps/common/Steam Controller Configs")


def layout_folders():
    """Every game layout folder there is (its name is the game's or shortcut's), for when none matched."""
    names = set()
    for account in sorted(os.listdir(CONFIGS)) if os.path.isdir(CONFIGS) else []:
        base = os.path.join(CONFIGS, account, "config")
        for folder in sorted(os.listdir(base)) if os.path.isdir(base) else []:
            if os.path.isfile(os.path.join(base, folder, "controller_neptune.vdf")):
                names.add(folder)
    return sorted(names)


def steam_running():
    return subprocess.call(["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL) == 0


def stop_steam(timeout=60):
    """Asks Steam to exit (it writes its layouts as it does) and waits for it. False if it's still up."""
    if not steam_running():
        return True
    print("stopping Steam...")
    subprocess.call(["steam", "-shutdown"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = time.time() + timeout
    while time.time() < end:
        if not steam_running():
            time.sleep(2)  # let it finish writing files
            return True
        time.sleep(1)
    return False


def find_layouts(game=None):
    """Deck layouts for games whose layout folder mentions "forever" (or is named `game`)."""
    found = []
    for account in sorted(os.listdir(CONFIGS)) if os.path.isdir(CONFIGS) else []:
        base = os.path.join(CONFIGS, account, "config")
        for folder in sorted(os.listdir(base)) if os.path.isdir(base) else []:
            path = os.path.join(base, folder, "controller_neptune.vdf")
            wanted = folder.lower() == game.lower() if game else "forever" in folder.lower()
            if wanted and os.path.isfile(path):
                found.append(path)
    return found


# --- A small reader/writer for Steam's text VDF -------------------------------------------------------
# A node is a list of [key, value] pairs, value a string or another node. Order and repeated keys
# ("group", "binding") are kept, and a line spaced other than with two tabs keeps its spacing as a
# third item, so an untouched layout writes back byte for byte.

def parse(text):
    tokens, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif c == "/" and text.startswith("//", i):
            i = text.find("\n", i)
            i = n if i < 0 else i
        elif c in "{}":
            tokens.append(c)
            i += 1
        elif c == '"':
            j, out = i + 1, []
            while text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    out.append(text[j:j + 2])
                    j += 2
                else:
                    out.append(text[j])
                    j += 1
            tokens.append(("s", "".join(out), i, j + 1))
            i = j + 1
        else:
            raise ValueError("unexpected %r at %d" % (c, i))

    pos = 0

    def node():
        nonlocal pos
        items = []
        while pos < len(tokens) and tokens[pos] != "}":
            key = tokens[pos]
            if not isinstance(key, tuple):
                raise ValueError("expected a key, got %r" % (key,))
            pos += 1
            if tokens[pos] == "{":
                pos += 1
                value = node()
                if tokens[pos] != "}":
                    raise ValueError("unclosed block %r" % key[1])
                pos += 1
            else:
                value = tokens[pos][1]
                gap = text[key[3]:tokens[pos][2]]
                pos += 1
                if gap != "\t\t":
                    items.append([key[1], value, gap])  # keep Steam's own spacing for this line
                    continue
            items.append([key[1], value])
        return items

    root = node()
    if pos != len(tokens):
        raise ValueError("stray closing brace")
    return root


def dump(items, depth=0):
    out, tab = [], "\t" * depth
    for pair in items:
        key, value = pair[0], pair[1]
        if isinstance(value, list):
            out.append('%s"%s"\n%s{\n%s%s}\n' % (tab, key, tab, dump(value, depth + 1), tab))
        else:
            out.append('%s"%s"%s"%s"\n' % (tab, key, pair[2] if len(pair) > 2 else "\t\t", value))
    return "".join(out)


def get(items, key):
    for pair in items:
        if pair[0] == key:
            return pair[1]


def get_all(items, key):
    return [pair[1] for pair in items if pair[0] == key]


def put(items, key, value):
    for pair in items:
        if pair[0] == key:
            pair[1:] = [value]
            return
    items.append([key, value])


# --- The grips -----------------------------------------------------------------------------------------

def activators(key, long_key, hold_ms):
    return [
        ["Full_Press", [
            ["bindings", [["binding", "key_press %s, , " % key]]],
            ["settings", [["interruptable", "0"]]],
        ]],
        ["Long_Press", [
            ["bindings", [["binding", "key_press %s, , " % long_key]]],
            ["settings", [["long_press_time", str(hold_ms)]]],
        ]],
    ]


def switch_groups(layout):
    """The "switches" groups the default preset uses (the back grips live in one of these)."""
    groups = {get(g, "id"): g for g in get_all(layout, "group") if get(g, "mode") == "switches"}
    active = []
    for preset in get_all(layout, "preset"):
        if get(preset, "id") != "0":
            continue
        for gid, how, *_ in get(preset, "group_source_bindings") or []:
            if gid in groups and how.startswith("switch") and "active" in how:
                active.append(groups[gid])
    if not active:
        raise ValueError("no active switches group in the default preset")
    return active


def apply(text, hold_ms):
    """hold_ms: {grip name: milliseconds}. Returns the new layout text."""
    root = parse(text)
    if len(root) != 1 or root[0][0] != "controller_mappings":
        raise ValueError("not a controller layout (no controller_mappings)")
    layout = root[0][1]
    groups = switch_groups(layout)
    for name, steam_input, key, long_key in GRIPS:
        # The grip's entry if a group has one, else add it to the first active switches group.
        target = None
        for g in groups:
            inputs = get(g, "inputs")
            if inputs is not None and get(inputs, steam_input) is not None:
                target = inputs
                break
        if target is None:
            target = get(groups[0], "inputs")
            if target is None:
                target = []
                put(groups[0], "inputs", target)
        entry = get(target, steam_input)
        if entry is None:
            entry = []
            target.append([steam_input, entry])
        put(entry, "activators", activators(key, long_key, hold_ms[name]))
        # Activators switched off in the editor would otherwise linger next to ours.
        put(entry, "disabled_activators", [])
    return dump(root)


def main():
    ap = argparse.ArgumentParser(description="Set up the back grips for DeckKit grip chords.")
    ap.add_argument("infile", nargs="?")
    ap.add_argument("outfile", nargs="?")
    ap.add_argument("--install", action="store_true",
                    help="rewrite your WoW: Forever layout on this Deck (Steam must not be running)")
    ap.add_argument("--stop-steam", action="store_true",
                    help="with --install: close Steam first and wait for it (lets you type the command with "
                         "Steam's on-screen keyboard before Steam goes away)")
    ap.add_argument("--game", help="with --install: the layout folder's name (the Steam shortcut's name), "
                                   "when it doesn't contain \"forever\" or more than one matches")
    ap.add_argument("--layout", help="with --install: the controller_neptune.vdf to rewrite")
    ap.add_argument("--hold-ms", type=int, default=DEFAULT_HOLD_MS, help="long-press time for every grip")
    for name, *_ in GRIPS:
        ap.add_argument("--hold-ms-" + name, type=int, help="long-press time for " + name)
    a = ap.parse_args()

    hold = {}
    for name, *_ in GRIPS:
        ms = getattr(a, "hold_ms_" + name) or a.hold_ms
        if not 100 <= ms <= 2000:
            ap.error("long-press time %d ms for %s is outside 100-2000" % (ms, name))
        hold[name] = ms

    if a.install:
        if a.infile or a.outfile:
            ap.error("--install takes no file names")
        if a.stop_steam and not stop_steam():
            sys.exit("Steam didn't close within a minute: exit it from its menu, then run this again")
        if steam_running():
            sys.exit("Steam is running: add --stop-steam, or exit Steam first (it rewrites the layout when it exits)")
        if a.layout:
            layouts = [a.layout] if os.path.isfile(a.layout) else []
        else:
            layouts = find_layouts(a.game)
        if len(layouts) != 1:
            if not layouts:
                print("No WoW: Forever controller layout found under", CONFIGS)
                print("Open the game's controller settings in Steam once (so it has a layout), or")
                print("name it: --game \"<layout folder>\" or --layout \"<path to controller_neptune.vdf>\"")
                folders = layout_folders()
                if folders:
                    print("Layout folders on this Deck (one is your WoW: Forever shortcut's):")
                    for name in folders: print('  --game "%s"' % name)
            else:
                print("More than one layout matches; pick one with --layout:")
                for path in layouts: print("  " + path)
            sys.exit(1)
        src = dst = layouts[0]
        backup = dst + ".bak-before-chords"
        if not os.path.exists(backup):
            shutil.copy2(dst, backup)
            print("backup:", backup)
    else:
        if not (a.infile and a.outfile):
            ap.error("give IN.vdf and OUT.vdf, or --install")
        src, dst = a.infile, a.outfile

    text = open(src, encoding="utf-8").read()
    out = apply(text, hold)
    open(dst, "w", encoding="utf-8").write(out)
    print("wrote", dst, "(" + ", ".join("%s %d ms" % (n, hold[n]) for n, *_ in GRIPS) + ")")


if __name__ == "__main__":
    main()
