"""Read files from WoW: Forever's CASC storage through CascLib (vendor/CascLib, built as a shared lib).

Online mode: CascLib fetches only the files we ask for from Blizzard's CDN and caches them in
cache/casc, so we never need the 48 GB client install.

    from casc import Storage
    with Storage() as s:
        data = s.read(775971)          # by FileDataID
"""
import ctypes
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB_CANDIDATES = [
    os.path.join(ROOT, "vendor/CascLib/build/casc.framework/casc"),
    os.path.join(ROOT, "vendor/CascLib/build/libcasc.so"),
    os.path.join(ROOT, "vendor/CascLib/build/libcasc.dylib"),
]
CACHE = os.path.join(ROOT, "cache", "casc")

CASC_OPEN_BY_FILEID = 3
CASC_OVERCOME_ENCRYPTED = 0x20
CASC_LOCALE_ALL = 0xFFFFFFFF


def _load():
    for path in LIB_CANDIDATES:
        if os.path.exists(path):
            lib = ctypes.CDLL(path)
            break
    else:
        sys.exit("CascLib not built: see README (vendor/CascLib)")
    v, b, d = ctypes.c_void_p, ctypes.c_bool, ctypes.c_uint32
    lib.CascOpenOnlineStorage.argtypes = [ctypes.c_char_p, d, ctypes.POINTER(v)]
    lib.CascOpenOnlineStorage.restype = b
    lib.CascOpenFile.argtypes = [v, v, d, d, ctypes.POINTER(v)]
    lib.CascOpenFile.restype = b
    lib.CascGetFileSize64.argtypes = [v, ctypes.POINTER(ctypes.c_uint64)]
    lib.CascGetFileSize64.restype = b
    lib.CascReadFile.argtypes = [v, v, d, ctypes.POINTER(d)]
    lib.CascReadFile.restype = b
    lib.CascCloseFile.argtypes = [v]
    lib.CascCloseStorage.argtypes = [v]
    lib.GetCascError.restype = d
    return lib


class Storage:
    def __init__(self, product="wowf", region="us"):
        self.lib = _load()
        os.makedirs(CACHE, exist_ok=True)
        self.handle = ctypes.c_void_p()
        params = f"{CACHE}*{product}*{region}".encode()
        if not self.lib.CascOpenOnlineStorage(params, CASC_LOCALE_ALL, ctypes.byref(self.handle)):
            raise OSError(f"CascOpenOnlineStorage({product}) failed: error {self.lib.GetCascError()}")

    def read(self, file_data_id):
        """The file's bytes, or None if the storage doesn't have it."""
        fh = ctypes.c_void_p()
        if not self.lib.CascOpenFile(self.handle, ctypes.c_void_p(file_data_id), CASC_LOCALE_ALL,
                                     CASC_OPEN_BY_FILEID, ctypes.byref(fh)):
            return None
        try:
            size = ctypes.c_uint64()
            self.lib.CascGetFileSize64(fh, ctypes.byref(size))
            buf = ctypes.create_string_buffer(size.value)
            got = ctypes.c_uint32()
            if not self.lib.CascReadFile(fh, buf, size.value, ctypes.byref(got)):
                raise OSError(f"CascReadFile({file_data_id}) failed: error {self.lib.GetCascError()}")
            return buf.raw[:got.value]
        finally:
            self.lib.CascCloseFile(fh)

    def close(self):
        if self.handle:
            self.lib.CascCloseStorage(self.handle)
            self.handle = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


if __name__ == "__main__":
    # Smoke test: python3 tools/casc.py [FileDataID ...]  (default: Azeroth's and Kalimdor's WDT)
    ids = [int(a) for a in sys.argv[1:]] or [775971, 782779]
    with Storage() as s:
        for fid in ids:
            data = s.read(fid)
            print(fid, "missing" if data is None else f"{len(data)} bytes, starts {data[:4]!r}")
