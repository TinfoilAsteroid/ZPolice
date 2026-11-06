"""A wave's CLUSTERS (levels 2 and 4: 4, with 40 zombies; the middle wave of
every 3rd level): the first zombies, the parents, are placed at random, the
rest in turn within 2 tiles of each on x and z, on streets; in other waves
they are spread over the city.
"""
import os
import sys

import zptest as zp
from zptest import sym

ZREC, NZOMB = sym["ZREC"], sym["NZOMB"]
TILE = 256
CLUSTERS = 4


def zombies(cpu):
    """(x, z) of each zombie in the wave."""
    out = []
    for i in range(NZOMB):
        r = sym["zombies"] + i * ZREC
        if cpu.rd(r + 10) & 1:
            out.append((cpu.rd16(r), cpu.rd16(r + 2)))
    return out


def far(zs):
    """The furthest any zombie is from its parent, on x or z."""
    return max(max(abs(x - zs[i % CLUSTERS][0]), abs(z - zs[i % CLUSTERS][1]))
               for i, (x, z) in enumerate(zs))


def test_clusters():
    for lv in (2, 4):
        with zp.SD() as sd:
            cpu = zp.machine(sd)
            zp.start_game(cpu, lv)
            zs = zombies(cpu)
            zp.check(len(zs) == 40, f"level {lv}: {len(zs)} zombies, not 40")
            d = far(zs)
            zp.note(f"level {lv}: the furthest from its parent: {d / TILE:.2f} tiles")
            zp.check(d <= 2 * TILE + 8, f"level {lv}: one {d / TILE:.2f} tiles from its parent")
            cm = sym["city_map"]
            bad = [(x, z) for x, z in zs if cpu.rd(cm + (z >> 8) * 64 + (x >> 8)) & sym["CELL_CODE"]]
            zp.check(not bad, f"level {lv}: zombies in buildings: {bad}")
            ps = zs[:CLUSTERS]
            apart = max(max(abs(a[0] - b[0]), abs(a[1] - b[1])) for a in ps for b in ps)
            zp.check(apart > 4 * TILE, f"level {lv}: the parents aren't spread out")


def test_no_clusters_elsewhere():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu, 1)
        zp.check(far(zombies(cpu)) > 8 * TILE, "level 1's zombies are clustered")


def test_every_third_level():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sys.path.insert(0, os.path.join(root, "tools"))
    import levelfile as lf
    cl = lf.SPEC_NAMES.index("CLUSTERS")
    for lv in range(1, 51):
        if lv in (2, 4):
            continue                    # (the trial)
        with open(os.path.join(root, "levels", f"LEVEL{lv:02d}.TXL"), encoding="latin-1") as f:
            d = lf.level_parse(f.read())
        ws = [w for w, sp in enumerate(d["waves_specials"], 1) if any(t == cl for t, _ in sp)]
        want = [(len(d["waves_specials"]) + 1) // 2] if lv % 3 == 0 else []
        zp.check(ws == want, f"level {lv}: clusters on waves {ws}, not {want}")


def test_only_the_middle_wave():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu, 12)          # 3 waves: the second
        zp.check(far(zombies(cpu)) > 8 * TILE, "wave 1 is clustered")
        for i in range(sym["NMON"]):
            cpu.wr(sym["zombies"] + i * ZREC + 10, 0)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(sym["wave_number"]) == 2, "not on wave 2")
        d = far(zombies(cpu))
        zp.check(d <= 2 * TILE + 8, f"wave 2: one {d / TILE:.2f} tiles from its parent")


if __name__ == "__main__":
    zp.main(globals())
