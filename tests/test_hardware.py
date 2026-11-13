"""The real-hardware build (-DREAL_HARDWARE: DMA+, the zxnDDMA blitter; see
docs/ZXNDDMA.md), assembled here as tests/hw.nex and run on nexsim's DMA+
model: the render test's ten views drawn byte for byte as the reference
(tests/ref/render.ref), so every DMA+ path draws exactly what the plain one
does; and its frame times against the plain build's (reported: nexsim's DMA
timing is an estimate, the hardware's is what counts).
"""
import gzip
import os
import pickle
import subprocess

import zptest as zp
import test_render as tr

SJASM = r"C:\CSpect\sjasmplus.exe"
NEX = os.path.join(zp.ROOT, "tests", "hw.nex")
SYM = os.path.join(zp.ROOT, "tests", "hw.sym")


def build():
    """tests/hw.nex and its symbols: the hardware build"""
    r = subprocess.run([SJASM, "--zxnext", "--nologo", "-DREAL_HARDWARE", "-DTEST_HW",
                        f"--sym={SYM}", "zpolice.asm"], cwd=zp.ROOT,
                       capture_output=True, text=True)
    zp.check(r.returncode == 0, "the hardware build failed:\n" + r.stdout[-2000:] + r.stderr[-2000:])


def with_build(nex, symfile, fn):
    """fn() run with zptest pointed at another build (the symbols too)"""
    old_nex, old_sym = zp.NEX, dict(zp.sym)
    zp.NEX = nex
    zp.sym.clear()
    zp.sym.update(zp.load_sym(symfile))
    try:
        return fn()
    finally:
        zp.NEX = old_nex
        zp.sym.clear()
        zp.sym.update(old_sym)


def test_views_as_the_reference():
    if not os.path.exists(SJASM):
        zp.note(f"no {SJASM}: skipped")
        return
    build()
    pics, times = with_build(NEX, SYM, tr.render)
    with gzip.open(tr.REF, "rb") as f:
        ref_pics, ref_times = pickle.load(f)
    plain = sum(ref_times)
    zp.note(f"frame time, all views: plain {plain:,} T, hardware {sum(times):,} T "
            f"({100 * (sum(times) - plain) / plain:+.1f}%, nexsim's DMA estimate)")
    for i, (a, b) in enumerate(zip(ref_times, times)):
        zp.note(f"  view {i}: {a:,} -> {b:,} T ({100 * (b - a) / a:+.1f}%)")
    bad = [f"view {i} ({sum(x != y for x, y in zip(a, b))} bytes)"
           for i, (a, b) in enumerate(zip(ref_pics, pics)) if a != b]
    zp.check(not bad, "the hardware build draws differently: " + ", ".join(bad))


FIG_VIEWS = [  # (distance, sideways, running way: 0 standing, 2 / 4 side on, mirrored or
    # not; and optionally spr_col (one colour: the fading ghost's), pitch, camera height)
    (45, 0, 0), (45, 0, 2), (45, 0, 4), (60, 0, 2), (100, 0, 0), (150, 0, 4), (400, 0, 0),
    (45, 38, 0), (45, -38, 2), (45, 41, 4), (45, -41, 0), (60, 52, 2), (60, -54, 4),
    (45, 44, 4), (45, -44, 2), (45, 45, 0), (45, -45, 4), (45, 43, 2), (45, -43, 0),
    (45, 0, 0, 0, -36, 24), (45, 0, 2, 0, -30, 24), (45, 0, 4, 0, -33, 24), (45, 0, 0, 0, 0, 2),
    (45, 0, 2, 200), (45, -44, 0, 200), (45, 44, 4, 200), (45, 0, 4, 200, -36, 24)]


def figures():
    """A human drawn from each of FIG_VIEWS: the shown view's bytes"""
    from test_figures import find_human
    sym = zp.sym
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        x, z, y = find_human(cpu)
        pics = []
        for dist, side, run, *more in FIG_VIEWS:
            col, pitch, dh = (more + [0, 0, 24][len(more):])[:3]
            zp.set_camera(cpu, (x + side) << 8, (z - dist) << 8, y + dh, 0, pitch)
            flips = []
            cpu.on_flip = lambda b: flips.append(1)
            while len(flips) < 2:
                if cpu.pc == sym["human_draw"]:
                    cpu.wr(cpu.ix + 13, run)
                elif col and cpu.pc == sym["spr_draw"] and cpu.mmu[4] == sym["PAGE_CITY2"]:
                    cpu.wr(sym["spr_col"], col)
                cpu.step()
            cpu.on_flip = None
            shown = cpu.nextreg.get(0x12, 0) * 2
            pics.append(b"".join(bytes(cpu.page(shown + i)) for i in range(4)))
        return pics


def test_figures_as_the_plain_build():
    """The hardware build's spr_draw (spr_rect.asm: SPRITEHW.ZPG's rectangles,
    one DMA+ transparent copy a figure, mirrored by port B counting down; the
    CPU for one colour) draws the figures as the plain one: near, far,
    mirrored, cut by the view's edges, in one colour"""
    if not os.path.exists(SJASM):
        zp.note(f"no {SJASM}: skipped")
        return
    if not os.path.exists(NEX):
        build()
    used = []
    orig = zp.machine

    def counting(sd):
        cpu = orig(sd)
        arm = zp.sym.get("fq_cmds") and zp.sym.get("spr_draw")
        if arm is not None:
            step = cpu.step

            def st():
                if cpu.pc == arm:
                    used.append(1)
                step()
            cpu.step = st
        return cpu
    plain = figures()
    zp.machine = counting
    try:
        hw = with_build(NEX, SYM, figures)
    finally:
        zp.machine = orig
    zp.check(used, "the hardware build drew no figure")
    zp.note(f"figures drawn: {len(used)}")
    bad = [f"view {i} {FIG_VIEWS[i]} ({sum(x != y for x, y in zip(a, b))} bytes)"
           for i, (a, b) in enumerate(zip(plain, hw)) if a != b]
    zp.check(not bad, "the hardware build draws the figures differently: " + ", ".join(bad))



DEVIL_VIEWS = [  # (distance, camera height, its heading: 2 facing us, 0 away, 1 / 3 side on)
    (2048, 100, 2), (1024, 100, 2), (640, 120, 1), (400, 100, 3), (250, 120, 0),
    (150, 100, 2), (90, 60, 2), (700, 400, 1)]


def devil_views():
    """The devil drawn from each of DEVIL_VIEWS: the shown view's bytes, and
    the T-states its drawing took"""
    import test_devil as td
    sym = zp.sym
    sd, cpu = td.devil_game()
    try:
        r = td.only_devil(cpu)
        cpu.wr(r + 7, 1)                            # (holding still)
        pics, times = [], []
        for dist, y, hd in DEVIL_VIEWS:
            cpu.wr(r + 4, hd)
            cpu.wr16(r, td.DX)
            cpu.wr16(r + 2, td.DZ)
            td.look_at(cpu, dist, y)
            zp.frames(cpu, 1)
            flips, t, inside, sp0, ts = [], 0, False, 0, 0
            cpu.on_flip = lambda b: flips.append(1)
            while not flips:
                if not inside and cpu.pc == sym["devil_draw"] and cpu.mmu[4] == sym["PAGE_CITY2"]:
                    inside, sp0, ts = True, cpu.sp, cpu.t
                cpu.step()
                if inside and cpu.sp == sp0 + 2:
                    inside, t = False, t + cpu.t - ts
            cpu.on_flip = None
            pics.append(bytes(b"".join(td.shown(cpu))))
            times.append(t)
        return pics, times
    finally:
        sd.close()


def test_devil_as_the_plain_build():
    """The devil (DMA+: each frame row drawn once, copied to the rows that
    repeat it) drawn byte for byte as the plain build's CPU drawing"""
    if not os.path.exists(SJASM):
        zp.note(f"no {SJASM}: skipped")
        return
    plain, pt = devil_views()
    build()
    hw, ht = with_build(NEX, SYM, devil_views)
    for (dist, y, hd), a, b in zip(DEVIL_VIEWS, pt, ht):
        zp.note(f"  {dist:4} units, height {y}, heading {hd}: {a:,} -> {b:,} T "
                f"({100 * (b - a) / max(1, a):+.0f}%)")
    bad = [f"{v[0]} units ({sum(x != y for x, y in zip(a, b))} bytes)"
           for v, a, b in zip(DEVIL_VIEWS, plain, hw) if a != b]
    zp.check(not bad, "the hardware build draws the devil differently: " + ", ".join(bad))



def test_save_in_home():
    """The hardware build: /home/ZPSave made at start-up (and left alone if
    it's there), the save game written there and continued from it"""
    if not os.path.exists(SJASM):
        zp.note(f"no {SJASM}: skipped")
        return
    build()
    import test_save as ts

    def run():
        with zp.SD() as sd:
            cpu = zp.machine(sd)
            zp.run_until(cpu, lambda: zp.at_scan(cpu, zp.sym["PAGE_MAINMENU"]), "the main menu")
            zp.check(os.path.isdir(os.path.join(sd.root, "home", "ZPSave")), "/home/ZPSave not made")
            cpu = zp.machine(sd)                # (again: it's there already)
            zp.run_until(cpu, lambda: zp.at_scan(cpu, zp.sym["PAGE_MAINMENU"]), "the main menu again")
        ts.test_save_and_continue()
    with_build(NEX, SYM, run)


if __name__ == "__main__":
    zp.main(globals())
