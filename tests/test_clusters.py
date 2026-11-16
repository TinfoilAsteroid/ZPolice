"""A wave's CLUSTERS (as the level files give them: CLUSTERS n in a WAVE
line): the first n zombies, the parents, are placed at random, the rest in
turn within 2 tiles of each on x and z, on streets; in other waves they are
spread over the city.
"""
import os
import sys

import zptest as zp
from zptest import sym

ZREC, NZOMB = sym["ZREC"], sym["NZOMB"]
TILE = 256
sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
import levelfile as lf  # noqa: E402

CL = lf.SPEC_NAMES.index("CLUSTERS")


def level(lv):
    with open(os.path.join(zp.ROOT, "levels", f"LEVEL{lv:02d}.TXL"), encoding="latin-1") as f:
        return lf.level_parse(f.read())


def clusters(lv, wave):
    """The clusters level lv's wave has (0: none)"""
    sp = level(lv)["waves_specials"][wave - 1]
    return sum(n for t, n in sp if t == CL)


def zombies(cpu):
    """(x, z) of each zombie in the wave."""
    out = []
    for i in range(NZOMB):
        r = sym["zombies"] + i * ZREC
        if cpu.rd(r + 10) & 1:
            out.append((cpu.rd16(r), cpu.rd16(r + 2)))
    return out


def far(zs, n):
    """The furthest any zombie is from its parent (n clusters), on x or z."""
    return max(max(abs(x - zs[i % n][0]), abs(z - zs[i % n][1])) for i, (x, z) in enumerate(zs))


def check_clustered(cpu, what, n):
    zs = zombies(cpu)
    d = far(zs, n)
    zp.note(f"{what}: {n} clusters, the furthest from its parent: {d / TILE:.2f} tiles")
    zp.check(d <= 2 * TILE + 8, f"{what}: one {d / TILE:.2f} tiles from its parent")
    cm = sym["city_map"]
    bad = [(x, z) for x, z in zs if cpu.rd(cm + (z >> 8) * 64 + (x >> 8)) & sym["CELL_CODE"]]
    zp.check(not bad, f"{what}: zombies in buildings: {bad}")
    if n > 1:
        ps = zs[:n]
        apart = max(max(abs(a[0] - b[0]), abs(a[1] - b[1])) for a in ps for b in ps)
        zp.check(apart > 4 * TILE, f"{what}: the parents aren't spread out")


def test_clusters():
    """The levels whose first wave has clusters"""
    lvs = [lv for lv in range(1, 51) if clusters(lv, 1)][:3]
    zp.check(lvs, "no level starts with clusters")
    for lv in lvs:
        with zp.SD() as sd:
            cpu = zp.machine(sd)
            zp.start_game(cpu, lv)
            zs = zombies(cpu)
            want = min(level(lv)["values"][0], NZOMB)
            zp.check(len(zs) == want, f"level {lv}: {len(zs)} zombies, not {want}")
            check_clustered(cpu, f"level {lv}", clusters(lv, 1))


def test_no_clusters_elsewhere():
    """A wave without clusters: spread over the city"""
    lv = next(lv for lv in range(1, 51) if not clusters(lv, 1) and level(lv)["values"][0] >= 10)
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu, lv)
        zp.check(far(zombies(cpu), 1) > 8 * TILE, f"level {lv}'s zombies are clustered")


def test_a_later_wave():
    """Clusters in a later wave only: that wave's zombies clustered"""
    lv, w = next((lv, w) for lv in range(1, 51) for w in range(2, len(level(lv)["waves_specials"]) + 1)
                 if clusters(lv, w) and not clusters(lv, 1))
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu, lv)
        cpu.wr(sym["wave_number"], w - 1)
        for i in range(sym["NMON"]):
            cpu.wr(sym["zombies"] + i * ZREC + 10, 0)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(sym["wave_number"]) == w, f"level {lv}: not on wave {w}")
        check_clustered(cpu, f"level {lv} wave {w}", clusters(lv, w))


if __name__ == "__main__":
    zp.main(globals())
