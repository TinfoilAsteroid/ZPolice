"""Every level (ZPDATA/LEVELnn.ZPL) starts from the loadout screen and plays
a few frames of flight, with interrupts.  The levels run at the same time,
one process each.
"""
import glob
import os
import re
from concurrent.futures import ProcessPoolExecutor

import zptest as zp
from zptest import sym


def levels():
    return sorted(int(m.group(1)) for p in glob.glob(os.path.join(zp.ROOT, "ZPDATA", "LEVEL*.ZPL"))
                  if (m := re.search(r"LEVEL(\d+)\.ZPL$", p, re.I)))


def play(n):
    """Level n: None if it plays, else what went wrong."""
    try:
        with zp.SD() as sd:
            cpu = zp.machine(sd, interrupts=True)
            zp.start_game(cpu, n)
            zp.check(cpu.rd(sym["level"]) == n, f"level {cpu.rd(sym['level'])} started")
            cpu.wr(sym["speed"], 8)
            zp.frames(cpu, 4)
    except AssertionError as e:
        return f"level {n}: {e}"
    return None


def test_every_level():
    lv = levels()
    zp.check(lv, "no ZPDATA/LEVELnn.ZPL")
    with ProcessPoolExecutor(max_workers=max(1, (os.cpu_count() or 4) // 2)) as ex:
        bad = [r for r in ex.map(play, lv) if r]
    zp.note(f"{len(lv)} levels")
    zp.check(not bad, "; ".join(bad))


if __name__ == "__main__":
    zp.main(globals())
