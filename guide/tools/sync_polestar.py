"""Sync the compiled guides from Polestar into ForeverGuide.

    python3 -I tools/sync_polestar.py                 # the latest release
    python3 -I tools/sync_polestar.py --tag v0.4.1    # a given release
    python3 -I tools/sync_polestar.py --src PATH      # a Polestar checkout already on disk; --tag names it

Polestar (https://github.com/fitzforge/polestar, by Fitz, GPL-3.0-only) writes leveling routes for WoW: Forever and
compiles them into Lua (`forge guide compile`). ForeverGuide plays those compiled guides with its own engine, so the
guides are what has to stay in step: this script takes them from a release, as players get them.

What it does:
- Copies, unchanged but for one header line, the compiled guide files:
    addon/Polestar_Guides/Guides.lua, MapFrames.lua  -> addons/ForeverGuide/Data/
    addon/Polestar_Guides_Horde/Guides.lua           -> addons/ForeverGuide_Horde/Guides.lua
    addon/Polestar_Guides_Alliance/Guides.lua        -> addons/ForeverGuide_Alliance/Guides.lua
  and Polestar's data notice (LICENSE-DATA.txt, where each fact comes from) beside each.
- The header line is `local Polestar = ForeverGuide.Data`: the files call Polestar.RegisterGuide and friends, and
  ForeverGuide's Core.lua answers those calls (no global named Polestar, so Polestar itself can be installed too).
- Each file may only call the Polestar functions listed in CALLS; a file that calls another is refused, since the
  engine wouldn't know what it means.
- UPSTREAM.json records the release, its commit and each upstream file's sha256.

The race parts (Polestar_Guides_<Race>/Legs.lua: baked walks into each step) are left out: ForeverNav walks.
Refuses (and changes nothing) on any check that fails.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent      # guide/ in the DeckKit repo
ADDONS = ROOT.parent / "addons"
UPSTREAM = ROOT / "UPSTREAM.json"
REPO = "fitzforge/polestar"

# upstream path -> our path, and the Polestar.* calls the file may make
FILES = [
    ("addon/Polestar_Guides/MapFrames.lua", "ForeverGuide/Data/MapFrames.lua", {"RegisterMapFrames"}),
    ("addon/Polestar_Guides/Guides.lua", "ForeverGuide/Data/Guides.lua",
     {"RegisterGuide", "RetireGuides", "RegisterExperimental"}),
    ("addon/Polestar_Guides_Horde/Guides.lua", "ForeverGuide_Horde/Guides.lua", {"RegisterGuide"}),
    ("addon/Polestar_Guides_Alliance/Guides.lua", "ForeverGuide_Alliance/Guides.lua", {"RegisterGuide"}),
]
NOTICE = "addon/Polestar_Guides/LICENSE-DATA.txt"
NOTICE_TO = ["ForeverGuide/Data/LICENSE-DATA.txt", "ForeverGuide_Horde/LICENSE-DATA.txt",
             "ForeverGuide_Alliance/LICENSE-DATA.txt"]
CALLS = {"RegisterMapFrames", "RegisterGuide", "RetireGuides", "RegisterExperimental"}


def run(*cmd, cwd=None):
    return subprocess.run(cmd, capture_output=True, text=True, check=True, cwd=cwd).stdout.strip()


def latest_tag():
    return run("gh", "release", "view", "--repo", REPO, "--json", "tagName", "--jq", ".tagName")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def header(tag, commit, upstream_path):
    return (f"-- Synced from Polestar {tag} ({commit[:12]}), {upstream_path}, by guide/tools/sync_polestar.py.\n"
            "-- Polestar (https://github.com/fitzforge/polestar) by Fitz, GPL-3.0-only: the guides are Polestar's,\n"
            "-- unchanged. Never edit this file; sync again. ForeverGuide/Core.lua answers the Polestar.* calls.\n"
            "local Polestar = ForeverGuide.Data\n")


def check(src):
    problems = []
    for up, _, allowed in FILES:
        p = src / up
        if not p.exists():
            problems.append(f"{up}: missing")
            continue
        text = p.read_text(encoding="utf-8")
        calls = set(re.findall(r"\bPolestar\.([A-Za-z_]+)", text))
        if calls - allowed:
            problems.append(f"{up}: calls Polestar.{', Polestar.'.join(sorted(calls - allowed))}")
        if "RegisterGuide" in allowed and "Polestar.RegisterGuide(" not in text:
            problems.append(f"{up}: no guides in it")
    if not (src / NOTICE).exists():
        problems.append(f"{NOTICE}: missing")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag")
    ap.add_argument("--src", type=pathlib.Path)
    args = ap.parse_args()
    tag = args.tag or latest_tag()

    with tempfile.TemporaryDirectory() as tmp:
        if args.src:
            src = args.src.resolve()
        else:
            src = pathlib.Path(tmp) / "polestar"
            run("git", "clone", "--depth", "1", "--branch", tag, f"https://github.com/{REPO}.git", str(src))
        commit = run("git", "rev-parse", "HEAD", cwd=src)

        problems = check(src)
        if problems:
            print("refused, nothing changed:\n  " + "\n  ".join(problems), file=sys.stderr)
            return 1

        files = {}
        for up, ours, _ in FILES:
            p = src / up
            dest = ADDONS / ours
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(header(tag, commit, up) + p.read_text(encoding="utf-8"), encoding="utf-8")
            files[up] = sha256(p)
            print(f"{ours}: {p.stat().st_size // 1024} KB")
        for ours in NOTICE_TO:
            shutil.copyfile(src / NOTICE, ADDONS / ours)
        files[NOTICE] = sha256(src / NOTICE)

    UPSTREAM.write_text(json.dumps({
        "source": f"https://github.com/{REPO}",
        "release": tag,
        "commit": commit,
        "synced": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "files": files,
    }, indent=2) + "\n")
    print(f"synced Polestar {tag} ({commit[:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
