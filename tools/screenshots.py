"""Screenshots of the game's 320x256 Layer 2 screens, as the emulator
(tools/nexsim.py) draws them from zpolice.nex: the main menu, redefine
keys, the load-out, level complete, the congratulations after the last
level, and the load error.  Saved as PNGs in docs/ (320x256).

    python tools/screenshots.py          (build first: build.bat)

It plays its way to each screen with tests/zptest.py's helpers, on a
temporary copy of ZPDATA (no save game, no redefined keys).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
import zptest as zp  # noqa: E402  (puts tools/ on the path too)
import nexsim  # noqa: E402
from zptest import sym  # noqa: E402

OUT = os.path.join(ROOT, "docs")


def shot(cpu, name):
    path = os.path.join(OUT, f"screen_{name}.png")
    nexsim.write_png(path, cpu.nextreg.get(0x12, 0), cpu)
    print("wrote", os.path.relpath(path, ROOT))


def settle(cpu, page, n=3):
    """A few more of the screen's key scans: drawn in full"""
    cpu.keys = set()
    for _ in range(n):
        cpu.stepi()
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym[page]), page)


def main():
    with zp.SD() as sd:                 # the main menu and redefine keys
        cpu = zp.machine(sd)
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
        settle(cpu, "PAGE_MAINMENU")
        shot(cpu, "main_menu")
        cpu.keys = {"9"}
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_KEYDEF"]), "redefine keys")
        settle(cpu, "PAGE_KEYDEF")
        shot(cpu, "redefine_keys")
    with zp.SD() as sd:                 # the load-out, level complete
        cpu = zp.machine(sd)
        cpu.keys = {"1"}
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        settle(cpu, "PAGE_LOADOUT")
        shot(cpu, "loadout")
        zp.start_game(cpu)
        zp.frames(cpu, 2)
        cpu.sp, cpu.pc = sym["stack_top"], sym["level_complete_screen"]
        cpu.set_nextreg(0x56, sym["PAGE_LEVELEND"])
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LEVELEND"]), "level complete")
        settle(cpu, "PAGE_LEVELEND")
        shot(cpu, "level_complete")
    with zp.SD() as sd:                 # after the last level
        cpu = zp.machine(sd)
        zp.start_game(cpu, sym["LEVEL_LAST"])
        zp.frames(cpu, 2)
        cpu.sp, cpu.pc = sym["stack_top"], sym["game_done_go"]
        zp.run_until(cpu, lambda: cpu.pc == sym["space_wait"], "congratulations")
        zp.run_until(cpu, lambda: cpu.pc == sym["kbd_scan"], "its key scan")
        shot(cpu, "congratulations")
        cpu.sp, cpu.pc = sym["stack_top"], sym["load_error_screen"]
        cpu.set_nextreg(0x56, sym["PAGE_MENU"])
        zp.run_until(cpu, lambda: cpu.pc == sym["menu_frame"], "the load error")
        shot(cpu, "load_error")


if __name__ == "__main__":
    main()
