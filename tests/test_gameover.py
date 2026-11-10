"""GAME OVER stays up until SPACE is pressed, then the main menu.  A SPACE
already held when the screen comes up (firing) doesn't count.
"""
import zptest as zp
from zptest import sym

OLD_PAUSE = 500                         # the frames the screen used to last


def over(keys):
    """A game, ended, on the GAME OVER screen, keys held.  cpu.left: the main
    menu has been reached since."""
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)
    zp.frames(cpu, 2)
    cpu.keys = set(keys)
    zp.frames(cpu, 1)
    cpu.wr(sym["game_over"], 1)
    zp.run_until(cpu, lambda: cpu.pc == sym["game_over_screen"], "the GAME OVER screen")
    cpu.left = False
    step = cpu.stepi

    def watch():
        step()
        cpu.left = cpu.left or (cpu.pc == sym["main_menu"] and cpu.mmu[6] == sym["PAGE_MAINMENU"])
    cpu.stepi = watch
    return sd, cpu


def scans(cpu, n):
    """Run n of the screen's key scans; fail if it leaves for the main menu."""
    for _ in range(n):
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "a key scan")
        zp.check(not cpu.left, "GAME OVER left without a new SPACE")
        cpu.stepi()


def goes_to_menu(cpu):
    zp.run_until(cpu, lambda: cpu.left, "the main menu", limit=10 * zp.FRAME_T)


def test_waits_for_space():
    sd, cpu = over("")
    try:
        scans(cpu, OLD_PAUSE + 20)
        ula = bytes(cpu.page(10))
        row = sym["LD_PROMPT_ROW"]
        lines = [ula[0x1000 + (row - 16) * 32 + 256 * n + 4 + k] for n in range(8) for k in range(23)]
        zp.check(any(lines), "no prompt on the screen")
        cpu.keys = {" "}
        goes_to_menu(cpu)
    finally:
        sd.close()


def test_held_space():
    sd, cpu = over(" ")
    try:
        scans(cpu, 20)
        cpu.keys = set()
        scans(cpu, 2)
        cpu.keys = {" "}
        goes_to_menu(cpu)
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
