"""The city renderer: ten fixed views of level 1, drawn pixel for pixel as
the reference (tests/ref/render.ref), and how long each takes.

After a change meant to alter the picture (the renderer, the figures, level
1's city or palette), check the new views, then save them as the reference:

    python tests/test_render.py --save

The frame times are reported against the reference's but don't fail the
test: the emulator's timing is exact, so any change shows.
"""
import gzip
import os
import pickle
import sys

import zptest as zp
from zptest import sym

REF = os.path.join(zp.REF, "render.ref")
VIEWS = [  # (x cell, z cell, height, yaw byte, pitch)
    (32, 33, 100, 0, 0), (32, 33, 100, 40, 0), (32, 33, 100, 90, 0), (32, 33, 100, 160, 0),
    (32, 33, 100, 40, 12), (32, 33, 60, 200, -10), (20, 44, 30, 64, 0), (20, 44, 180, 128, 0),
    (20, 44, 180, 10, -20), (50, 12, 140, 222, 6)]


def render():
    """Each view's Layer 2 rows 0-127 (the city view) and its frame's T-states."""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        flips = []
        cpu.on_flip = lambda b: flips.append(cpu.t)
        pics, times = [], []
        for x, z, h, yaw, pitch in VIEWS:
            zp.set_camera(cpu, x << 16 | 0x8000, z << 16 | 0x8000, h, yaw, pitch)
            f0 = len(flips)
            while len(flips) < f0 + 1:
                cpu.step()
            t0 = cpu.t
            while len(flips) < f0 + 2:
                cpu.step()
            times.append(cpu.t - t0)
            shown = cpu.nextreg.get(0x12, 0) * 2      # the 16K bank shown, as an 8K page
            pics.append(b"".join(bytes(cpu.page(shown + i)) for i in range(4)))
        return pics, times


def test_views():
    pics, times = render()
    if "--save" in sys.argv:
        os.makedirs(zp.REF, exist_ok=True)
        with gzip.open(REF, "wb") as f:
            pickle.dump((pics, times), f)
        zp.note(f"saved {len(pics)} views as the reference; total {sum(times):,} T")
        return
    zp.check(os.path.exists(REF), "no reference: run python tests/test_render.py --save")
    with gzip.open(REF, "rb") as f:
        ref_pics, ref_times = pickle.load(f)
    for i, (a, b) in enumerate(zip(ref_times, times)):
        if a != b:
            zp.note(f"view {i}: {a:,} -> {b:,} T ({100 * (b - a) / a:+.1f}%)")
    zp.note(f"frame time, all views: {sum(ref_times):,} -> {sum(times):,} T "
            f"({100 * (sum(times) - sum(ref_times)) / sum(ref_times):+.1f}%)")
    bad = [f"view {i} ({sum(x != y for x, y in zip(a, b))} bytes)"
           for i, (a, b) in enumerate(zip(ref_pics, pics)) if a != b]
    zp.check(not bad, "differ from the reference: " + ", ".join(bad))


if __name__ == "__main__":
    zp.main(globals())
