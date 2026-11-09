#!/usr/bin/env python3
# Adds a "WoW Forever" non-Steam shortcut (Lutris game 2) and gives it the same controller layout
# as "world of warcraft". Run as deck while Steam is NOT running. Usage: addshortcut.py [--dry]
import os, shutil, struct, sys, zlib

DRY = "--dry" in sys.argv
USER = "/home/deck/.local/share/Steam/userdata/70511644/config"
VDF = os.environ.get("VDF", USER + "/shortcuts.vdf")
NAME = "WoW Forever"
EXE = '"/usr/bin/flatpak"'
APPID = zlib.crc32((EXE + NAME).encode()) | 0x80000000


def s(k, v): return b"\x01" + k.encode() + b"\x00" + v.encode() + b"\x00"
def i(k, v): return b"\x02" + k.encode() + b"\x00" + struct.pack("<I", v)


data = open(VDF, "rb").read()
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
             + s("icon", USER + "/grid/%d_icon.png" % APPID)
             + s("ShortcutPath", "")
             + s("LaunchOptions", "LC_ALL=C.UTF-8 %command% run net.lutris.Lutris lutris:rungameid/2")
             + i("IsHidden", 0) + i("AllowDesktopConfig", 1) + i("AllowOverlay", 1)
             + i("OpenVR", 0) + i("Devkit", 0) + s("DevkitGameID", "") + i("DevkitOverrideAppID", 0)
             + i("LastPlayTime", 0) + s("FlatpakAppID", "") + s("sortas", "")
             + b"\x00tags\x00\x08"
             + b"\x08")
    new = data[:-2] + entry + b"\x08\x08"
    print("adding entry", idx, "appid", APPID)
    if not DRY:
        shutil.copy2(VDF, VDF + ".bak-wowforever")
        open(VDF, "wb").write(new)

# Controller layout: same as "world of warcraft" (back buttons -> F8-F11).
cfg = "/home/deck/.local/share/Steam/steamapps/common/Steam Controller Configs/70511644/config"
src, dst = cfg + "/world of warcraft", cfg + "/wow forever"
if os.path.isdir(src) and not os.path.isdir(dst):
    print("copying controller layout")
    if not DRY:
        shutil.copytree(src, dst)
        p = dst + "/controller_neptune.vdf"
        t = open(p).read().replace("default://world of warcraft", "default://wow forever")
        open(p, "w").write(t)
cs = cfg + "/configset_controller_neptune.vdf"
t = open(cs).read()
if '"wow forever"' not in t:
    print("registering layout")
    if not DRY:
        k = t.rindex("}")
        open(cs, "w").write(t[:k] + '\t"wow forever"\n\t{\n\t\t"autosave"\t\t"1"\n\t}\n' + t[k:])
print("done" + (" (dry run)" if DRY else ""))
