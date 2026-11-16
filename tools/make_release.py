"""Make the release folder, release/, from a build with -DRELEASE (build.bat
release): the game (release_tmp/zpolice.nex), the data files it reads and
nothing else (not the .TXL / .TXC text forms, nor a player's KEYS.ZPK or
SAVEGAME.ZPS), and the player's manual, docs/MANUAL.txt.

    release/zpolice.nex
    release/ZPDATA/...
    release/MANUAL.txt

    python tools/make_release.py          the release folder
    python tools/make_release.py debug    the debug folder, the same way from
                                          the normal (debug) build: zpolice.nex
                                          and its zpolice.map and zpolice.sym
                                          (for CSpect's debugger), ZPDATA,
                                          MANUAL.txt (build.bat does this after
                                          every build without release)

The folder is made afresh each time, so anything else left in it goes.
"""
import glob
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RELEASE = os.path.join(ROOT, "release")
DEBUG = os.path.join(ROOT, "debug")
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
    need += ["SPRITES.ZPG", "SPRITEHW.ZPG", "DEVIL.ZPB", "FONT8.ZPF", "FONT12.ZPF", "VTOL.ZPI", "MAINMENU.ZPI"]
    missing = [f for f in need if not os.path.exists(os.path.join(DATA, f))]
    if missing:
        raise SystemExit(f"ZPDATA: missing {', '.join(missing[:8])}")
    return need + sorted(os.path.basename(p) for p in glob.glob(os.path.join(DATA, "LEVEL*.ZPP")))


def clear_release(out=RELEASE):
    """Every file in the folder goes.  The folders are only removed if they
    can be: OneDrive or Explorer may have one open, and an empty one is fine."""
    for folder, dirs, names in os.walk(out, topdown=False):
        for n in names:
            os.remove(os.path.join(folder, n))
        for d in dirs:
            try:
                os.rmdir(os.path.join(folder, d))
            except OSError:
                pass


def main(argv=sys.argv[1:]):
    if "debug" in argv:
        out, src, extra = DEBUG, ROOT, ["zpolice.map", "zpolice.sym"]
        hint = "build first (build.bat)"
    else:
        out, src, extra = RELEASE, TMP, []
        hint = "assemble with -DRELEASE first (build.bat release)"
    nex = os.path.join(src, "zpolice.nex")
    if not os.path.exists(nex):
        raise SystemExit(f"no {nex}: {hint}")
    files = game_files()
    clear_release(out)
    os.makedirs(os.path.join(out, "ZPDATA"), exist_ok=True)
    shutil.copy2(nex, out)
    for e in extra:
        if os.path.exists(os.path.join(src, e)):
            shutil.copy2(os.path.join(src, e), out)
    for f in files:
        shutil.copy2(os.path.join(DATA, f), os.path.join(out, "ZPDATA", f))
    with open(MANUAL, encoding="ascii") as src_f, \
            open(os.path.join(out, "MANUAL.txt"), "w", encoding="ascii", newline="\r\n") as f:
        f.write(src_f.read())
    print(f"wrote {out}: zpolice.nex, {', '.join(extra + ['MANUAL.txt'])}, ZPDATA ({len(files)} files)")


if __name__ == "__main__":
    sys.exit(main())
