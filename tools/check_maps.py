"""Check every city map and level file, without opening the editor or
building:

    python tools/check_maps.py

The city maps (maps/CITYnn.json: citymap.validate, the hand-set palette
shades too) and the level files (levels/LEVELnn.TXL: levelfile.level_check,
the map changes checked against their city), and the level palettes
(levels/LEVELnn_PAL.json: levelpal.problems, the level's city too).  Prints
each file's problems,
or OK; the exit code is 1 if any file has problems, so a script can stop on
it.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import citymap as cm
import levelfile as lf
import levelpal as lp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    bad = 0
    cities = {}
    maps = sorted(glob.glob(os.path.join(ROOT, "maps", "CITY*.json")))
    for p in maps:
        name = os.path.relpath(p, ROOT)
        try:
            m = cm.load(p)
            errs = cm.validate(m["cells"], m["fams"], m["palette"])
            cities[m["city"]] = (m["cells"], m["fams"])
        except (OSError, ValueError, KeyError) as e:
            errs = [str(e)]
        bad += report(name, errs)
    levels = sorted(glob.glob(os.path.join(ROOT, "levels", "LEVEL*.TXL")))
    level_city = {}
    for p in levels:
        name = os.path.relpath(p, ROOT)
        try:
            lv = int(os.path.basename(p)[5:7])
            d = lf.read(p)
            level_city[lv] = d["cn"]
            errs = lf.level_check(lv, d, cities)
        except (OSError, ValueError, IndexError) as e:
            errs = [str(e)]
        bad += report(name, errs)
    pals = sorted(glob.glob(os.path.join(ROOT, "levels", "LEVEL*_PAL.json")))
    for p in pals:
        name = os.path.relpath(p, ROOT)
        try:
            lv = int(os.path.basename(p)[5:7])
            errs = lp.problems(lv, lp.load(p), level_city.get(lv))
            if lv not in level_city:
                errs.append(f"there is no levels/LEVEL{lv:02d}.TXL")
        except (OSError, ValueError, IndexError) as e:
            errs = [str(e)]
        bad += report(name, errs)
    print(f"{len(maps)} city maps, {len(levels)} levels, {len(pals)} level palettes: "
          + (f"{bad} with problems" if bad else "all OK"))
    return 1 if bad else 0


def report(name, errs):
    if errs:
        print(f"{name}:")
        for e in errs:
            print(f"  - {e}")
        return 1
    print(f"{name}: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
