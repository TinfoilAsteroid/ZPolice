"""The source data and the files built from it: every city map, level and
level palette passes tools/check_maps.py; every figure passes the sprite
editor's checks; and ZPDATA/SPRITES.ZPG is what gengraphics.py would build
from sprites/ now (not left over from an older build).  The HUD's sprites,
sprites/hud.json, pass their checks and are what tables_hspr.inc holds, and
the HUD sprite editor's pixel operations do what they say.
"""
import os
import subprocess
import sys
import tempfile

import zptest as zp
import hudsprites as hs  # noqa: E402  (tools/, on the path from zptest)
import spritefile as sf  # noqa: E402


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
    hw = open(os.path.join(zp.ROOT, "ZPDATA", "SPRITEHW.ZPG"), "rb").read()
    zp.check(bytes(sf.build(figures(), rect=True)[0]) == hw, "ZPDATA/SPRITEHW.ZPG is out of date: run build.bat")


def test_devil_palette():
    """sprites/devil_palette.json passes its checks, and the built palettes
    hold its colours: normal (every city's) and each vision mode's (level 50's)"""
    dp = sf.load_devil_palette()
    errs = sf.devil_palette_problems(dp)
    zp.check(not errs, "; ".join(errs))
    data = open(os.path.join(zp.ROOT, "ZPDATA", "LEVEL50.ZPV"), "rb").read()
    for k, mode in enumerate(sf.DEVIL_PAL_MODES):
        for e in sf.DEVIL_ENTRIES:
            a, lo = data[8 + 512 * k + 2 * e], data[9 + 512 * k + 2 * e]
            got = (a >> 5, (a >> 2) & 7, ((a & 3) << 1) | (lo & 1))
            zp.check(got == tuple(dp[e][mode]), f"entry {e} {mode}: {got}, the file says {dp[e][mode]}")


def test_hud_sprites():
    sprites = hs.load()
    errs = hs.problems(sprites)
    zp.check(not errs, "; ".join(errs[:8]))
    inc = open(os.path.join(zp.ROOT, "tables_hspr.inc")).read()
    zp.check(hs.table_text(sprites) == inc, "tables_hspr.inc is out of date: run build.bat")
    bad = hs.problems(sprites[1:])
    zp.check(bad, "the game's own sprites can be missing")


def test_hud_sprite_file():
    sprites = hs.load()
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "hud.json")
        hs.save(sprites, p)
        zp.check(hs.load(p) == sprites, "a saved file doesn't load the same")


def test_hud_sprite_operations():
    a, b = 0x1C, 0xE0
    px = hs.blank()
    px[1][2] = a
    zp.check(hs.mirror(px)[1][13] == a, "mirror")
    zp.check(hs.flip(px)[14][2] == a, "flip")
    zp.check(hs.rotate(px)[2][14] == a, "rotate")
    zp.check(hs.shift(px, -3, -2)[15][15] == a, "shift doesn't wrap")
    zp.check(hs.replace(px, a, b)[1][2] == b, "replace")
    box = hs.blank()
    for x, y in hs.rect_cells((1, 1), (5, 5)):
        box[y][x] = a
    filled = hs.fill(box, (3, 3), b)
    zp.check(filled[3][3] == b and filled[1][1] == a and filled[0][0] == hs.TRANSPARENT, "fill")
    zp.check(box[3][3] == hs.TRANSPARENT, "fill changed what it was given")
    zp.check(hs.line_cells((0, 0), (3, 3)) == {(k, k) for k in range(4)}, "line")
    zp.check(hs.rgb(0xFF) == (255, 255, 255) and hs.rgb(0x03)[2] == 255 and hs.rgb(0x01)[2] == 109, "rgb")


if __name__ == "__main__":
    zp.main(globals())
