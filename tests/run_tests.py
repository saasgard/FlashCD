"""Run FlashCD's tests outside the game.

Needs Python with the `lupa` package (pip install lupa). Each tests/test_*.lua
file runs in a fresh Lua state after tests/wow_mock.lua (a small fake of the
WoW API) and the addon's files, loaded in TOC order.

    python tests/run_tests.py            # all tests
    python tests/run_tests.py window     # only files whose name contains "window"
"""
import glob
import os
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)


def run(path):
    L = lupa.LuaRuntime()
    g = L.globals()
    g.ADDON_DIR = ADDON.replace("\\", "/")
    g.TESTS_DIR = HERE.replace("\\", "/")
    with open(os.path.join(HERE, "wow_mock.lua"), encoding="utf-8") as f:
        L.execute(f.read())
    with open(path, encoding="utf-8") as f:
        src = f.read()
    try:
        L.execute(src)
    except lupa.LuaError as e:
        print("  ERROR", str(e).splitlines()[0], flush=True)
        return 1
    return int(g.Failures())


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else ""
    files = sorted(glob.glob(os.path.join(HERE, "test_*.lua")))
    files = [f for f in files if want in os.path.basename(f)]
    failed = 0
    for path in files:
        print(os.path.basename(path), flush=True)
        n = run(path)
        if n:
            failed += 1
    print()
    print("%d of %d test files passed" % (len(files) - failed, len(files)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
