"""The release folder, release/, as a player gets it (build.bat release runs
this; not one of the test_*.py, which need the debug build's keys): the game
in it starts from its own files and has no debug features left.

    python tests/release_check.py
"""
import os

import zptest as zp
from zptest import sym

RELEASE = os.path.join(zp.ROOT, "release")
SYM = os.path.join(zp.ROOT, "release_tmp", "zpolice.sym")


def use_release():
    """zptest, on the release: its .nex, symbols and data files."""
    zp.NEX = os.path.join(RELEASE, "zpolice.nex")
    zp.ROOT = RELEASE
    sym.clear()
    sym.update(zp.load_sym(SYM))


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)
    zp.frames(cpu, 2)
    return sd, cpu


def test_files():
    names = os.listdir(os.path.join(RELEASE, "ZPDATA"))
    bad = [n for n in names if n.endswith((".TXL", ".TXC", ".ZPK", ".ZPS"))]
    zp.check(not bad, f"files a release shouldn't have: {bad[:5]}")
    for f in ("zpolice.nex", "MANUAL.txt"):
        zp.check(os.path.exists(os.path.join(RELEASE, f)), f"no {f}")


def test_no_debug_code():
    bad = [s for s in ("debug_killall", "debug_gun_cycle") if s in sym]
    zp.check(not bad, f"debug code in the release: {bad}")


def test_new_game():
    sd, cpu = game()
    try:
        zp.check(cpu.rd(sym["level"]) == 1, f"starts on level {cpu.rd(sym['level'])}")
        zp.check(cpu.rd(sym["salvage_points"]) == 0, "starts with salvage")
        for name in ("boost_fitted", "vthrust_fitted", "lthrust_fitted", "vision_owned"):
            zp.check(cpu.rd(sym[name]) == 0, f"{name} is set at the start")
        stock = [cpu.rd(sym["wpn_stock"] + k) for k in range(1, sym["WPN_LAST"] + 1)]
        zp.check(not any(stock), f"weapons in store at the start: {stock}")
    finally:
        sd.close()


def test_no_debug_keys():
    sd, cpu = game()
    try:
        wave = cpu.rd(sym["wave_number"])
        gun = cpu.rd(sym["wpn_slots"])
        for key in "098":
            cpu.keys = {key}
            zp.frames(cpu, 2)
            cpu.keys = set()
            zp.frames(cpu, 2)
            zp.check(cpu.rd(sym["level_done"]) == 0, f"key {key} ended the level")
            zp.check(cpu.rd(sym["wave_number"]) == wave, f"key {key} moved the wave on")
            zp.check(cpu.rd(sym["wpn_slots"]) == gun, f"key {key} changed the gun")
    finally:
        sd.close()


if __name__ == "__main__":
    use_release()
    zp.main(globals())
