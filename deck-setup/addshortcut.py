#!/usr/bin/env python3
# Adds a "WoW Forever" non-Steam shortcut that starts WoW: Forever through Lutris (game 2), gives it the
# Steam artwork in wowforever-art/, and the same controller layout as a "world of warcraft" shortcut if
# there is one. The author's own setup (INSTALL.md appendix); adjust LAUNCH for yours.
#
# Run on the Deck as deck while Steam is NOT running (Steam rewrites shortcuts.vdf when it exits):
#   python3 addshortcut.py [--dry] [--user <Steam account number>]
# --user is only needed when the Deck has more than one Steam account (folders in
# ~/.local/share/Steam/userdata).
import os, shutil, struct, sys, zlib

DRY = "--dry" in sys.argv
STEAM = os.path.expanduser("~/.local/share/Steam")
HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "wowforever-art")
NAME = "WoW Forever"
EXE = '"/usr/bin/flatpak"'
LAUNCH = "LC_ALL=C.UTF-8 %command% run net.lutris.Lutris lutris:rungameid/2"
# Steam's id for a non-Steam shortcut: from its Exe and name. Its art files are named after it.
APPID = zlib.crc32((EXE + NAME).encode()) | 0x80000000
# Our art file -> the name Steam looks for in the account's grid folder.
ART_NAMES = {"cover.png": "%dp.png", "capsule.png": "%d.png", "hero.png": "%d_hero.png",
             "logo.png": "%d_logo.png", "icon.png": "%d_icon.png"}


def account():
    """The Steam account number: --user, or the only one on this Deck."""
    if "--user" in sys.argv:
        return sys.argv[sys.argv.index("--user") + 1]
    base = os.path.join(STEAM, "userdata")
    ids = [d for d in os.listdir(base) if d.isdigit() and d != "0"] if os.path.isdir(base) else []
    if len(ids) != 1:
        sys.exit("Steam accounts here: %s. Pick one with --user <number>." % (", ".join(ids) or "none"))
    return ids[0]


def s(k, v): return b"\x01" + k.encode() + b"\x00" + v.encode() + b"\x00"
def i(k, v): return b"\x02" + k.encode() + b"\x00" + struct.pack("<I", v)


if os.system("pgrep -x steam >/dev/null") == 0:
    sys.exit("Steam is running: exit it first (it rewrites shortcuts.vdf when it exits)")
ACCOUNT = account()
USER = os.path.join(STEAM, "userdata", ACCOUNT, "config")
VDF = os.environ.get("VDF", USER + "/shortcuts.vdf")
GRID = USER + "/grid"

# The shortcut.
data = open(VDF, "rb").read() if os.path.exists(VDF) else b"\x00shortcuts\x00\x08\x08"
assert data.startswith(b"\x00shortcuts\x00") and data.endswith(b"\x08\x08"), "unexpected shortcuts.vdf format"
if b"\x01AppName\x00" + NAME.encode() + b"\x00" in data or b"\x01appname\x00" + NAME.encode() + b"\x00" in data:
    print("shortcut already present")
else:
    # Next index: count top-level entries.
    idx = 0
    while b"\x00" + str(idx).encode() + b"\x00\x02appid\x00" in data:
        idx += 1
    entry = (b"\x00" + str(idx).encode() + b"\x00"
             + i("appid", APPID)
             + s("AppName", NAME)
             + s("Exe", EXE)
             + s("StartDir", '"/home/deck"')
             + s("icon", GRID + "/%d_icon.png" % APPID)
             + s("ShortcutPath", "")
             + s("LaunchOptions", LAUNCH)
             + i("IsHidden", 0) + i("AllowDesktopConfig", 1) + i("AllowOverlay", 1)
             + i("OpenVR", 0) + i("Devkit", 0) + s("DevkitGameID", "") + i("DevkitOverrideAppID", 0)
             + i("LastPlayTime", 0) + s("FlatpakAppID", "") + s("sortas", "")
             + b"\x00tags\x00\x08"
             + b"\x08")
    new = data[:-2] + entry + b"\x08\x08"
    print("adding entry", idx, "appid", APPID)
    if not DRY:
        if os.path.exists(VDF):
            shutil.copy2(VDF, VDF + ".bak-wowforever")
        open(VDF, "wb").write(new)

# The artwork, under the names Steam looks for (the shortcut's id).
for ours, theirs in ART_NAMES.items():
    src, dst = os.path.join(ART, ours), os.path.join(GRID, theirs % APPID)
    if os.path.isfile(src):
        print("art:", ours, "->", os.path.basename(dst))
        if not DRY:
            os.makedirs(GRID, exist_ok=True)
            shutil.copy2(src, dst)

# Controller layout: a copy of "world of warcraft" (its back buttons; make-chord-layout.py sets the grip keys).
cfg = os.path.join(STEAM, "steamapps/common/Steam Controller Configs", ACCOUNT, "config")
src, dst = cfg + "/world of warcraft", cfg + "/wow forever"
if os.path.isdir(src) and not os.path.isdir(dst):
    print("copying controller layout")
    if not DRY:
        shutil.copytree(src, dst)
        p = dst + "/controller_neptune.vdf"
        t = open(p).read().replace("default://world of warcraft", "default://wow forever")
        open(p, "w").write(t)
cs = cfg + "/configset_controller_neptune.vdf"
if os.path.isdir(dst) and os.path.exists(cs):
    t = open(cs).read()
    if '"wow forever"' not in t:
        print("registering layout")
        if not DRY:
            k = t.rindex("}")
            open(cs, "w").write(t[:k] + '\t"wow forever"\n\t{\n\t\t"autosave"\t\t"1"\n\t}\n' + t[k:])
print("done" + (" (dry run)" if DRY else ""))
