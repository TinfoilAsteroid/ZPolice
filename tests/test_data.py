"""The source data and the files built from it: every city map, level and
level palette passes tools/check_maps.py; every figure passes the sprite
editor's checks; and ZPDATA/SPRITES.ZPG is what gengraphics.py would build
from sprites/ now (not left over from an older build).
"""
import os
import subprocess
import sys

import zptest as zp
import spritefile as sf  # noqa: E402  (tools/, on the path from zptest)


def test_maps_and_levels():
    r = subprocess.run([sys.executable, os.path.join(zp.ROOT, "tools", "check_maps.py")],
                       capture_output=True, text=True, cwd=zp.ROOT)
    bad = [line for line in r.stdout.splitlines() if line.strip() and not line.rstrip().endswith("OK")]
    zp.check(r.returncode == 0, "check_maps.py: " + "; ".join(bad[:8] or [r.stderr.strip()]))


def figures():
    return {n: sf.load(sf.figure_path(n)) for n in sf.FIGURE_NAMES}


def test_figures():
    errs = [f"palette: {e}" for e in sf.palette_problems(sf.load_palette())]
    for name, fig in figures().items():
        errs += [f"{name}: {e}" for e in sf.problems(name, fig)]
    zp.check(not errs, "; ".join(errs[:8]))


def test_sprites_built():
    built = open(os.path.join(zp.ROOT, "ZPDATA", "SPRITES.ZPG"), "rb").read()
    zp.check(bytes(sf.build(figures())[0]) == built, "ZPDATA/SPRITES.ZPG is out of date: run build.bat")


if __name__ == "__main__":
    zp.main(globals())
