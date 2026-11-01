"""Move every building onto the building colour families (citymap.BLD_FAMILIES,
01..15; 00 is the perimeter wall's), each to the nearest in colour:

    python tools/remap_families.py [--dry-run]

For each city map (maps/CITYnn.json), a building whose colour family is 16
or more takes the family among 01..BLD_FAMILIES-1 whose SHADE_DARK,
SHADE_FACE and SHADE_ROOF are nearest to its own (the sum of the squared
r, g, b differences over the 3 shades), in the city's palette as built
(ZPDATA/CITYnn.ZPC: the generated colours with the map's hand-set shades).
The levels' map changes (levels/LEVELnn.TXL) are remapped the same way, in
their city's palette.  Run build.bat first (for the palettes) and after
(to rebuild the ZPDATA files).
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import citymap as cm
import levelfile as lf

ROOT = os.path.dirname(HERE)
TARGETS = range(cm.WALL_FAMILY + 1, cm.BLD_FAMILIES)
SHADES = (cm.SHADE_DARK, cm.SHADE_FACE, cm.SHADE_ROOF)


def nearest(pal, f):
    """The building family nearest in colour to family f."""
    def dist(g):
        return sum((a - b) ** 2 for k in SHADES
                   for a, b in zip(pal[f * 4 + k], pal[g * 4 + k]))
    return min(TARGETS, key=lambda g: (dist(g), g))


def needs_remap(code, f):
    return cm.is_building(code) and isinstance(f, int) and f >= cm.BLD_FAMILIES \
        and f not in (cm.TERRACE_FAMILY, cm.PAD_FAMILY)


def main():
    dry = "--dry-run" in sys.argv
    pals = {}
    for p in sorted(glob.glob(os.path.join(ROOT, "maps", "CITY*.json"))):
        m = cm.load(p)
        n = m["city"]
        pal = cm.read_palette(os.path.join(ROOT, "ZPDATA", f"CITY{n:02d}.ZPC"))
        pals[n] = pal
        fams, moved, used = list(m["fams"]), 0, {}
        for i, (code, f) in enumerate(zip(m["cells"], fams)):
            if needs_remap(code, f):
                g = nearest(pal, f)
                fams[i] = g
                used[(f, g)] = used.get((f, g), 0) + 1
                moved += 1
        print(f"{os.path.relpath(p, ROOT)}: {moved} buildings moved onto families "
              f"01..{cm.BLD_FAMILIES - 1:02d} ({len({f for f, _ in used})} families folded)")
        if moved and not dry:
            cm.save(p, n, m["name"], m["cells"], fams, m["palette"])
    for p in sorted(glob.glob(os.path.join(ROOT, "levels", "LEVEL*.TXL"))):
        d = lf.read(p)
        pal = pals.get(d["cn"])
        ch, moved = [], 0
        for x, z, code, col in d["changes"]:
            if pal and needs_remap(code, col // 4):
                col = cm.city_col(nearest(pal, col // 4))
                moved += 1
            ch.append((x, z, code, col))
        if moved:
            print(f"{os.path.relpath(p, ROOT)}: {moved} map changes moved")
            if not dry:
                d["changes"] = ch
                lf.write(p, d)


if __name__ == "__main__":
    main()
