"""Headless tests: loads ForeverNav's .toc in order into a Lua 5.1 runtime (lupa) with the few client functions it
calls stood in for, then runs Lua test files.

    pip install lupa                     # once (a venv is fine)
    python3 tests/harness.py             # every tests/test_*.lua that needs the addon loaded
    python3 tests/harness.py test_surfaces

Stand-ins: C_EncodingUtil.DecodeBase64 and DecompressString (Python's base64 and zlib, as the client's), the
compression enum, debugprofilestop. Tests get `ns` (the addon's table) and the globals the addon sets (ForeverNav).
"""
import base64
import pathlib
import re
import sys
import time
import zlib

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT.parent / "addons" / "ForeverNav"   # ROOT is nav/ in the DeckKit repo

STUBS = r"""
Enum = { CompressionMethod = { Zlib = 0, Deflate = 1, Brotli = 2 } }
function debugprofilestop() return _py_clock() end
function GetTime() return _py_clock() / 1000 end
function GetServerTime() return 1794700000 + math.floor(_py_clock() / 1000) end
function UnitFactionGroup() return FACTION or "Horde" end
function GetUnitSpeed() return 0, 7 end
function geterrorhandler() return function(e) error(e, 2) end end
-- A character with no bind point and no teleports; tests that need them set their own.
function canaccessvalue() return true end
function GetBindLocation() return nil end
C_Item = { GetItemCount = function() return 0 end, GetItemCooldown = function() return 0, 0 end }
C_SpellBook = { IsSpellKnown = function() return false end }
C_Spell = { GetSpellInfo = function() return nil end, GetSpellCooldown = function() return nil end }
-- A frame that takes event registrations and scripts and does nothing with them: tests drive the code directly.
function CreateFrame()
    local f = {}
    for _, m in ipairs({ "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "SetScript", "Hide", "Show" }) do
        f[m] = function() end
    end
    return f
end
C_EncodingUtil = {
    DecodeBase64 = function(s) return _py_b64(s) end,
    DecompressString = function(s, method) return _py_inflate(s) end,
}
"""

PRELUDE = r"""
function check(cond, msg)
    if not cond then error("CHECK FAILED: " .. tostring(msg), 2) end
end
"""


def toc_files():
    out = []
    for line in (ADDON / "ForeverNav.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = line.replace("\\", "/")
        if path.endswith(".xml"):
            folder = pathlib.PurePosixPath(path).parent
            xml = (ADDON / path).read_text(encoding="utf-8")
            out += [str(folder / f) for f in re.findall(r'<Script file="([^"]+)"/>', xml)]
        else:
            out.append(path)
    return out


def new_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    g = lua.globals()
    g._py_clock = lambda: time.perf_counter() * 1000

    def b64(s):
        try:
            return base64.b64decode(s)
        except Exception:
            return None

    def inflate(s):
        try:
            return zlib.decompress(s)
        except Exception:
            return None

    g._py_b64, g._py_inflate = b64, inflate
    lua.execute(STUBS)
    ns = lua.eval("{}")
    loadstring = lua.eval("loadstring")
    for name in toc_files():
        source = (ADDON / name).read_bytes()
        chunk = loadstring(source, b"@" + name.encode())
        if isinstance(chunk, tuple):
            raise SystemExit(f"syntax error in {name}: {chunk[1]}")
        chunk(b"ForeverNav", ns)
    g.ns = ns
    lua.execute(PRELUDE)
    return lua


def run_test(name):
    lua = new_runtime()
    path = ROOT / "tests" / f"{name}.lua"
    chunk = lua.eval("loadstring")(path.read_bytes(), b"@" + path.name.encode())
    if isinstance(chunk, tuple):
        raise SystemExit(f"syntax error in {path.name}: {chunk[1]}")
    started = time.perf_counter()
    outcome = lua.eval("pcall")(chunk)
    ok, result = outcome if isinstance(outcome, tuple) else (outcome, None)
    took = time.perf_counter() - started
    if isinstance(result, bytes):
        result = result.decode("utf-8", "replace")
    print(f"{'PASS' if ok else 'FAIL'} {name} ({took:.2f} s)" + ("" if ok else f": {result}"))
    return bool(ok)


def main():
    names = sys.argv[1:] or sorted(p.stem for p in (ROOT / "tests").glob("test_*.lua")
                                   if p.stem != "test_data_loads")      # that one runs on plain lua5.1
    results = [run_test(n) for n in names]
    raise SystemExit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
