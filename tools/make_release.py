"""Make the release folder, release/, from a build with -DRELEASE (build.bat
release): the game (release_tmp/zpolice.nex), the data files it reads and
nothing else (not the .TXL / .TXC text forms, nor a player's KEYS.ZPK or
SAVEGAME.ZPS), and the player's manual, docs/MANUAL.txt.

    release/zpolice.nex
    release/ZPDATA/...
    release/MANUAL.txt

The folder is made afresh each time, so anything else left in it goes.
"""
import glob
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RELEASE = os.path.join(ROOT, "release")
TMP = os.path.join(ROOT, "release_tmp")
DATA = os.path.join(ROOT, "ZPDATA")
LEVELS = 50
CITIES = 10

MANUAL = os.path.join(ROOT, "docs", "MANUAL.txt")


def game_files():
    """The data files the game reads."""
    need = [f"LEVEL{n:02d}.ZPL" for n in range(1, LEVELS + 1)]
    need += [f"LEVEL{n:02d}.ZPV" for n in range(1, LEVELS + 1)]
    need += [f"CITY{n:02d}.ZPC" for n in range(1, CITIES + 1)]
    need += ["SPRITES.ZPG", "FONT8.ZPF", "FONT12.ZPF", "VTOL.ZPI", "MAINMENU.ZPI"]
    missing = [f for f in need if not os.path.exists(os.path.join(DATA, f))]
    if missing:
        raise SystemExit(f"ZPDATA: missing {', '.join(missing[:8])}")
    return need + sorted(os.path.basename(p) for p in glob.glob(os.path.join(DATA, "LEVEL*.ZPP")))


def clear_release():
    """Every file in the folder goes.  The folders are only removed if they
    can be: OneDrive or Explorer may have one open, and an empty one is fine."""
    for folder, dirs, names in os.walk(RELEASE, topdown=False):
        for n in names:
            os.remove(os.path.join(folder, n))
        for d in dirs:
            try:
                os.rmdir(os.path.join(folder, d))
            except OSError:
                pass


def main():
    nex = os.path.join(TMP, "zpolice.nex")
    if not os.path.exists(nex):
        raise SystemExit(f"no {nex}: assemble with -DRELEASE first (build.bat release)")
    files = game_files()
    clear_release()
    os.makedirs(os.path.join(RELEASE, "ZPDATA"), exist_ok=True)
    shutil.copy2(nex, RELEASE)
    for f in files:
        shutil.copy2(os.path.join(DATA, f), os.path.join(RELEASE, "ZPDATA", f))
    with open(MANUAL, encoding="ascii") as src, \
            open(os.path.join(RELEASE, "MANUAL.txt"), "w", encoding="ascii", newline="\r\n") as f:
        f.write(src.read())
    print(f"wrote {RELEASE}: zpolice.nex, MANUAL.txt, ZPDATA ({len(files)} files)")


if __name__ == "__main__":
    sys.exit(main())
