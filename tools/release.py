"""Build a zip of FlashCD to share: dist/FlashCD-<version>.zip

The zip holds a FlashCD folder with only what the game loads (the files
listed in FlashCD.toc and the icon) plus the README, so it can be unpacked
straight into Interface/AddOns. Tests, tools and git files are left out.

    python tools/release.py
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    toc_path = os.path.join(ROOT, "FlashCD.toc")
    with open(toc_path, encoding="utf-8") as f:
        toc = f.read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    version = version.group(1) if version else "dev"

    files = ["FlashCD.toc", "README.md", "LICENSE", "Media/Icon.tga", "Media/icon.png"]
    files += [line.strip() for line in toc.splitlines()
              if line.strip() and not line.startswith("#") and line.strip().endswith(".lua")]
    missing = [f for f in files if not os.path.isfile(os.path.join(ROOT, f))]
    if missing:
        print("missing files:", ", ".join(missing))
        sys.exit(1)

    out_dir = os.path.join(ROOT, "dist")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "FlashCD-%s.zip" % version)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(os.path.join(ROOT, f), "FlashCD/" + f)
    print("wrote", os.path.relpath(out, ROOT), "(%d files)" % len(files))


if __name__ == "__main__":
    main()
