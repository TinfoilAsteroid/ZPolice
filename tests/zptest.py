"""Shared helpers for the emulator tests (tests/test_*.py).

Each test file runs on its own (python tests/test_render.py) or from
tests/run_tests.py, which runs them all at once.  A test is a function
test_NAME() that raises AssertionError (check()) when it fails; main() runs
a file's tests and prints PASS or FAIL for each.

The game runs on tools/nexsim.py from the built zpolice.nex and its
zpolice.sym, on a copy of ZPDATA in a temporary folder (the SD card), so a
test never writes to the repository and never sees a KEYS.ZPK or a
SAVEGAME.ZPS left there by playing.
"""
import os
import re
import shutil
import sys
import tempfile
import time
import traceback

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")
REF = os.path.join(TESTS, "ref")
NEX = os.path.join(ROOT, "zpolice.nex")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import nexsim  # noqa: E402

FRAME_T = 28_000_000 // 50           # T-states per 50 Hz frame at 28 MHz


def load_sym(path=os.path.join(ROOT, "zpolice.sym")):
    sym = {}
    for line in open(path):
        m = re.match(r"([\w.]+):\s+EQU\s+0x([0-9A-F]+)", line)
        if m:
            sym[m.group(1)] = int(m.group(2), 16)
    return sym


sym = load_sym()


class SD:
    """A temporary SD card: ZPDATA copied without the player's files.
    drop: more ZPDATA files to leave out (to test their absence)."""

    def __init__(self, drop=()):
        self.root = tempfile.mkdtemp(prefix="zptest_")
        self.data = os.path.join(self.root, "ZPDATA")
        shutil.copytree(os.path.join(ROOT, "ZPDATA"), self.data)
        for name in ("KEYS.ZPK", "SAVEGAME.ZPS") + tuple(drop):
            p = os.path.join(self.data, name)
            if os.path.exists(p):
                os.remove(p)

    def path(self, name):
        return os.path.join(self.data, name)

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


def machine(sd, interrupts=False):
    """A Next with zpolice.nex loaded, the SD card sd.  cpu.stepi steps one
    instruction, raising the 50 Hz interrupt if interrupts (nexsim raises
    none of its own)."""
    cpu = nexsim.Cpu()
    cpu.esx_root = sd.root
    nexsim.load_nex(cpu, NEX)
    if "wp_wait" in sym:                # PREPARE FOR WAVE's 2 s (wave_prepare):
        ticks = sym["isr_ticks"]        # nexsim raises no interrupts of its own,
        wait = sym["WPREP_TICKS"]       # so skip it (test_wave_prepare checks it)
        cpu.trap_pc = sym["wp_wait"]
        cpu.trap = lambda: (cpu.wr(ticks, wait & 255), cpu.wr(ticks + 1, wait >> 8))
    if interrupts:
        nxt = [cpu.t + FRAME_T]

        def stepi():
            cpu.step()
            if cpu.t >= nxt[0]:
                nxt[0] += FRAME_T
                cpu.interrupt()
        cpu.stepi = stepi
    else:
        cpu.stepi = cpu.step
    return cpu


def run_until(cpu, cond, what, limit=400_000_000):
    """Step until cond(); fail if it takes over limit T-states."""
    t0 = cpu.t
    while not cond():
        cpu.stepi()
        if cpu.t - t0 > limit:
            raise AssertionError(f"stuck waiting for {what}: pc {cpu.pc:04X}, "
                                 f"slot 6 page {cpu.mmu[6]}, slot 7 page {cpu.mmu[7]}")


def at_scan(cpu, page):
    """At kbd_scan with page (PAGE_MAINMENU, PAGE_LOADOUT, ...) in slot 6."""
    return (cpu.pc == sym["kbd_scan"] and cpu.mmu[6] == page
            and cpu.mmu[7] == sym["PAGE_INPUT"])     # ($E000: every slot 7 page)


def start_game(cpu, level=None):
    """From the start: 1 (new game) on the main menu, then 0 (launch) on the
    loadout screen, until main_loop.  level: the level to play."""
    cpu.keys = {"1"}
    n = 0
    while cpu.pc != sym["main_loop"]:
        if cpu.keys == {"1"} and cpu.mmu[6] == sym["PAGE_LOADOUT"]:
            cpu.keys = set()                # (1 let go as the load-out opens)
        if at_scan(cpu, sym["PAGE_LOADOUT"]):
            n += 1
            if n == 1 and level is not None:
                cpu.wr(sym["level"], level)
            cpu.keys = {"0"} if n == 3 else set()
        cpu.stepi()
        if cpu.t > 2_000_000_000:
            raise AssertionError(f"the game didn't start: pc {cpu.pc:04X}, slot 6 page {cpu.mmu[6]}")
    cpu.keys = set()


def frames(cpu, n):
    """Run n more Layer 2 flips."""
    flips = []
    old = cpu.on_flip
    cpu.on_flip = lambda b: flips.append(b)
    try:
        run_until(cpu, lambda: len(flips) >= n, f"{n} frames", limit=n * 20 * FRAME_T)
    finally:
        cpu.on_flip = old


def set_camera(cpu, x, z, y, yaw=0, pitch=0, speed=0):
    """Put the VTOL at (x, z), height y.  x and z are 24 bits: world units
    (256 a cell) times 256, so the low byte is the fraction."""
    for i in range(3):
        cpu.wr(sym["cam_x"] + i, x >> (8 * i) & 255)
        cpu.wr(sym["cam_z"] + i, z >> (8 * i) & 255)
    cpu.wr16(sym["cam_y"], y)
    cpu.wr(sym["yaw_frac"], 0)
    cpu.wr(sym["yaw"], yaw & 255)
    cpu.wr(sym["pitch"], pitch & 255)
    cpu.wr(sym["pitch_frac"], 0)
    cpu.wr(sym["speed"], speed & 255)


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def note(msg):
    """A line of detail under the test's PASS or FAIL."""
    print("      " + msg, flush=True)


def main(module_globals):
    """Run the file's test_* functions (or those named on the command line).
    Exit code 1 if any fails."""
    tests = [(k, v) for k, v in module_globals.items() if k.startswith("test_") and callable(v)]
    want = [a for a in sys.argv[1:] if not a.startswith("-")]
    if want:
        tests = [(k, v) for k, v in tests if k in want or k[5:] in want]
    file = os.path.basename(module_globals.get("__file__", "?"))
    bad = 0
    for name, fn in tests:
        t0 = time.time()
        try:
            fn()
            print(f"PASS {file} {name} ({time.time() - t0:.1f}s)", flush=True)
        except AssertionError as e:
            bad += 1
            print(f"FAIL {file} {name}: {e}", flush=True)
        except Exception:
            bad += 1
            print(f"FAIL {file} {name}: error", flush=True)
            traceback.print_exc(file=sys.stdout)
    sys.exit(1 if bad else 0)
