"""Sync the travel data and walking maps from Shortest Path Forever into ForeverNav.

    python3 -I tools/sync_spf.py                 # the latest release
    python3 -I tools/sync_spf.py --tag v1.37.1   # a given release
    python3 -I tools/sync_spf.py --zip PATH      # a release zip already downloaded (offline); --tag names it

Shortest Path Forever (https://github.com/cjber/shortest-path-forever, by Cillian Berragan, GPL-3.0-or-later)
bakes its walking maps from the Forever client's terrain (TrinityCore's tools, Recast) and generates its travel data
from the client's tables, CMaNGOS classic-db and InFlight. ForeverNav uses that data with its own router, so the data
is what has to stay in step: this script takes it from a release zip, as players get it.

What it does:
- Nav/: every walking map file and Nav.xml, with the global ShortestPathForeverPathData renamed ForeverNavPathData
  (the only change). Each map's metadata must declare the format the reader knows (NAV_FORMAT, steep), and every
  packed block its `counts` promise must be in the part files: a map that came through short is refused.
- Data/: the routing data files, in Shortest Path Forever's load order, unchanged (each writes onto the addon table it
  is loaded with). Each must set exactly the tables listed in DATA, so a file that grew or lost a table is noticed
  before the router reads it. Services.lua (nearby services) and Credits.lua (its players) are left out.
- Every synced file gets a header line naming where it came from; UPSTREAM.json records the release, its commit, the
  client build the data was made from, and each upstream file's sha256.

Refuses (and changes nothing) on any check that fails; --force syncs anyway, for a format we are about to support.
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
import zipfile
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT.parent / "addons" / "ForeverNav"   # ROOT is nav/ in the DeckKit repo
CACHE = ROOT / "cache" / "spf"
UPSTREAM = ROOT / "UPSTREAM.json"
REPO = "cjber/shortest-path-forever"

UPSTREAM_GLOBAL = "ShortestPathForeverPathData"
OUR_GLOBAL = "ForeverNavPathData"
NAV_FORMAT = 3                     # the walking-map format our reader knows (see each Nav*.lua header)

# The routing data, in Shortest Path Forever's .toc order, and the tables each sets on the addon table.
DATA = [
    ("Routes.lua", {"Docks", "Routes"}),
    ("Transports.lua", {"Docks", "Routes"}),      # adds lifts and the tram to Routes.lua's tables
    ("Taxi.lua", {"Landmasses", "TaxiNodes", "TaxiPaths"}),
    ("Portals.lua", {"Entrances", "Portals"}),
    ("Teleports.lua", {"Teleports"}),
    ("Zones.lua", {"Zones"}),
    ("TownAreas.lua", {"TownAreas"}),
    ("Walks.lua", {"WalkPlaces", "Walks"}),
    ("RoadCells.lua", {"RoadCells"}),
    ("RoadEdges.lua", {"RoadEdges"}),
    ("Heights.lua", {"SpawnHeights"}),
]
LEFT_OUT = {"Services.lua", "Credits.lua"}


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()


def latest_tag():
    return run("gh", "release", "view", "--repo", REPO, "--json", "tagName", "--jq", ".tagName")


def tag_commit(tag):
    """The commit a tag points at (through an annotated tag object if it is one)."""
    ref = json.loads(run("gh", "api", f"repos/{REPO}/git/ref/tags/{tag}"))
    obj = ref["object"]
    if obj["type"] == "tag":
        obj = json.loads(run("gh", "api", f"repos/{REPO}/git/tags/{obj['sha']}"))["object"]
    return obj["sha"]


def download(tag):
    dest = CACHE / tag
    zips = list(dest.glob("*forever.zip")) if dest.is_dir() else []
    if not zips:
        dest.mkdir(parents=True, exist_ok=True)
        run("gh", "release", "download", tag, "--repo", REPO, "--pattern", "*forever.zip", "--dir", str(dest))
        zips = list(dest.glob("*forever.zip"))
    if len(zips) != 1:
        sys.exit(f"expected one *forever.zip for {tag} in {dest}, found {len(zips)}")
    return zips[0]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def check_nav(files, problems):
    """Each map's metadata (NavN.lua) and its packed blocks across the part files (NavN_k.lua)."""
    maps = {}
    for name, text in files.items():
        for m in re.finditer(r"^%s\[(\d+)\] = \{(.*?)^\}" % UPSTREAM_GLOBAL, text, re.M | re.S):
            body = m.group(2)
            fmt = re.search(r"^\s*format = (\d+),", body, re.M)
            counts = re.search(r"counts = \{([^}]*)\}", body)
            maps[int(m.group(1))] = {
                "file": name,
                "format": int(fmt.group(1)) if fmt else None,
                "steep": re.search(r"^\s*steep = true,", body, re.M) is not None,
                "counts": {k: int(v) for k, v in re.findall(r"(\w+) = (\d+)", counts.group(1))} if counts else {},
            }
    if not maps:
        problems.append("Nav: no map metadata found")
    packed = {}
    for text in files.values():
        local = re.search(r"^local data = %s\[(\d+)\]" % UPSTREAM_GLOBAL, text, re.M)
        if not local:
            continue
        mid = int(local.group(1))
        for kind, idx in re.findall(r"^data\.packed\.(\w+)\[(\d+)\] = ", text, re.M):
            packed.setdefault(mid, {}).setdefault(kind, set()).add(int(idx))
    for mid, meta in sorted(maps.items()):
        if meta["format"] != NAV_FORMAT or not meta["steep"]:
            problems.append(f"Nav map {mid}: format {meta['format']} steep={meta['steep']}, the reader knows "
                            f"format {NAV_FORMAT} with steep")
        for kind, want in meta["counts"].items():
            got = len(packed.get(mid, {}).get(kind, ()))
            if got != want:
                problems.append(f"Nav map {mid}: {got} packed {kind} blocks, its counts say {want}")
    return maps


def check_data(name, text, want, problems):
    # Tables it writes: whole (ns.X = ...) or entries of one an earlier file made (ns.X[k] = ..., Transports.lua).
    tables = set(re.findall(r"^\s*ns\.(\w+)\s*(?:=|\[)", text, re.M))
    if tables != want:
        problems.append(f"Data/{name}: writes {sorted(tables)}, expected {sorted(want)}")
    if "ShortestPathForever" in text:
        problems.append(f"Data/{name}: names ShortestPathForever (it should write only onto the addon table)")


def header(tag, commit, upstream_path):
    return (f"-- Synced from Shortest Path Forever {tag} ({commit[:12]}), {upstream_path}, by Cillian Berragan (cjber),\n"
            f"-- https://github.com/{REPO}, GPL-3.0-or-later. Do not edit: tools/sync_spf.py writes it.\n")


def client_build(texts):
    builds = set()
    for t in texts:
        builds.update(re.findall(r"\b1\.60\.\d+\.\d+\b", t[:2000]))
    return sorted(builds)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tag", help="release tag (default: the latest)")
    ap.add_argument("--zip", help="a release zip already downloaded")
    ap.add_argument("--force", action="store_true", help="sync even when a check fails")
    args = ap.parse_args()

    tag = args.tag or latest_tag()
    zip_path = pathlib.Path(args.zip) if args.zip else download(tag)
    commit = tag_commit(tag)

    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        def read(path):
            return z.read(path).decode("utf-8")
        nav_names = sorted(n for n in names if re.match(r"ShortestPathForever/Nav/[^/]+\.(lua|xml)$", n))
        nav = {n: read(n) for n in nav_names}
        data = {}
        problems = []
        for name, want in DATA:
            path = f"ShortestPathForever/Data/{name}"
            if path not in names:
                problems.append(f"Data/{name}: missing from the release")
                continue
            data[name] = read(path)
            check_data(name, data[name], want, problems)
        known = {n for n, _ in DATA} | LEFT_OUT
        for n in names:
            m = re.match(r"ShortestPathForever/Data/([^/]+\.lua)$", n)
            if m and m.group(1) not in known:
                problems.append(f"Data/{m.group(1)}: new in this release, not synced (add it to DATA if routing needs it)")
        toc = read("ShortestPathForever/ShortestPathForever.toc")
        version = re.search(r"^## Version: (.+)$", toc, re.M).group(1).strip()

    maps = check_nav({n: t for n, t in nav.items() if n.endswith(".lua")}, problems)
    if problems:
        print("problems:\n  " + "\n  ".join(problems))
        if not args.force:
            sys.exit("not synced (--force to sync anyway)")

    # Write into a fresh folder, then swap it in, so a failure never leaves a half-synced addon.
    staging = pathlib.Path(tempfile.mkdtemp(prefix="spf-sync-", dir=ROOT))
    try:
        (staging / "Nav").mkdir()
        (staging / "Data").mkdir()
        files = {}
        for n, text in nav.items():
            base = n.split("/")[-1]
            out = text.replace(UPSTREAM_GLOBAL, OUR_GLOBAL)
            if base.endswith(".lua"):
                out = header(tag, commit, f"Nav/{base}") + out
            else:
                out = out.replace('<Ui xmlns="http://www.blizzard.com/wow/ui/">',
                                  '<Ui xmlns="http://www.blizzard.com/wow/ui/">\n\t<!-- Synced from Shortest Path Forever '
                                  f'{tag} by tools/sync_spf.py: do not edit. -->', 1)
            (staging / "Nav" / base).write_text(out, encoding="utf-8")
            files[f"Nav/{base}"] = sha256(text.encode("utf-8"))
        for name, _ in DATA:
            if name in data:
                (staging / "Data" / name).write_text(header(tag, commit, f"Data/{name}") + data[name], encoding="utf-8")
                files[f"Data/{name}"] = sha256(data[name].encode("utf-8"))
        scripts = "".join(f'\t<Script file="{name}"/>\n' for name, _ in DATA if name in data)
        (staging / "Data" / "Data.xml").write_text(
            '<Ui xmlns="http://www.blizzard.com/wow/ui/">\n'
            f'\t<!-- Shortest Path Forever {tag}\'s routing data, in its load order. tools/sync_spf.py writes it. -->\n'
            f'{scripts}</Ui>\n', encoding="utf-8")

        ADDON.mkdir(parents=True, exist_ok=True)
        previous = json.loads(UPSTREAM.read_text()) if UPSTREAM.is_file() else None
        for sub in ("Nav", "Data"):
            target = ADDON / sub
            if target.exists():
                shutil.rmtree(target)
            shutil.move(str(staging / sub), str(target))
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    record = {
        "source": f"https://github.com/{REPO}",
        "release": tag,
        "version": version,
        "commit": commit,
        "client_builds": client_build(list(nav.values()) + list(data.values())),
        "nav_format": NAV_FORMAT,
        "maps": {str(k): {"format": v["format"], "counts": v["counts"]} for k, v in sorted(maps.items())},
        "synced": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "files": dict(sorted(files.items())),
    }
    UPSTREAM.write_text(json.dumps(record, indent=2) + "\n")

    changed = [f for f, h in files.items() if not previous or previous.get("files", {}).get(f) != h]
    gone = sorted(set(previous.get("files", {})) - set(files)) if previous else []
    size = sum(p.stat().st_size for p in ADDON.rglob("*") if p.is_file() and p.parent.name in ("Nav", "Data"))
    print(f"synced Shortest Path Forever {tag} ({commit[:12]}): {len(files)} files, {size / 1e6:.1f} MB, "
          f"maps {', '.join(str(m) for m in sorted(maps))}, client {', '.join(record['client_builds']) or '?'}")
    if previous:
        print(f"since {previous['release']}: {len(changed)} changed, {len(gone)} gone" +
              ("".join(f"\n  changed {f}" for f in changed[:20])) + ("".join(f"\n  gone {f}" for f in gone)))


if __name__ == "__main__":
    main()
