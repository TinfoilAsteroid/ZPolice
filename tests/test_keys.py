"""The key definitions: saved to ZPDATA/KEYS.ZPK on leaving the redefine
screen, loaded at start-up, a bad file ignored; and X on the pause screen
quits to the main menu without saving the game.
"""
import os

import zptest as zp
from zptest import sym

N_DEFS = 20
KB_Q, KB_M = 0x0201, 0x0704                # SPEED UP's default, and M


def boot(sd):
    cpu = zp.machine(sd, interrupts=True)
    zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "the main menu")
    return cpu


def defs(cpu):
    """key_defs (in the input page) as 16-bit codes."""
    page = cpu.page(sym["PAGE_INPUT"])
    a = sym["key_defs"] - 0xE000
    return [page[a + 2 * i] | page[a + 2 * i + 1] << 8 for i in range(N_DEFS)]


def scans(cpu, keys, n):
    """Hold keys for n calls of kbd_scan."""
    cpu.keys = set(keys)
    k = [0]

    def count():
        if cpu.pc == sym["kbd_scan"]:
            k[0] += 1
        return k[0] > n
    zp.run_until(cpu, count, f"{n} key scans", limit=60_000_000)


def redefine_speed_up(cpu):
    """9 on the main menu, SPEED UP redefined as M, then 1 to leave."""
    kd = sym["PAGE_KEYDEF"]
    scans(cpu, "9", 2)
    zp.run_until(cpu, lambda: zp.at_scan(cpu, kd), "the redefine screen")
    scans(cpu, "", 3)
    scans(cpu, " ", 2)                 # SPACE: redefine all, from SPEED UP
    scans(cpu, "", 60)                 #   (its second's pause)
    scans(cpu, "M", 2)
    scans(cpu, "", 3)
    zp.check(defs(cpu)[0] == KB_M, f"SPEED UP is {defs(cpu)[0]:04X} after pressing M, not {KB_M:04X}")
    scans(cpu, "1", 2)
    zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "the main menu again")


def test_defaults_without_file():
    with zp.SD() as sd:
        d = defs(boot(sd))
        zp.check(d[0] == KB_Q, f"SPEED UP is {d[0]:04X}, not Q ({KB_Q:04X})")


def test_saved_and_loaded():
    with zp.SD() as sd:
        cpu = boot(sd)
        d0 = defs(cpu)
        redefine_speed_up(cpu)
        p = sd.path("KEYS.ZPK")
        zp.check(os.path.exists(p), "KEYS.ZPK not written")
        data = open(p, "rb").read()
        zp.check(len(data) == 86, f"KEYS.ZPK is {len(data)} bytes, not 86")
        zp.check(data[:6] == b"ZPKY\x01" + bytes([N_DEFS]), f"KEYS.ZPK header {data[:6]!r}")
        zp.check(data[6:8] == KB_M.to_bytes(2, "little"), f"KEYS.ZPK SPEED UP {data[6:8].hex()}")
        d = defs(boot(sd))
        zp.check(d[0] == KB_M, f"after a restart SPEED UP is {d[0]:04X}, not M")
        zp.check(d[1:] == d0[1:], "after a restart other keys changed")
        open(p, "wb").write(data[:4] + b"\x09" + data[5:])     # a version this game doesn't know
        zp.check(defs(boot(sd)) == d0, "a KEYS.ZPK of the wrong version was used")


def test_pause_quit():
    with zp.SD() as sd:
        cpu = boot(sd)
        zp.start_game(cpu)
        for _ in range(200_000):                # a few frames of play
            cpu.stepi()
        zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "main_loop")
        cpu._map(7, sym["PAGE_INPUT"])
        cpu.push(sym["main_loop"])
        cpu.pc = sym["game_pause"]
        scans(cpu, "", 3)
        scans(cpu, "X", 2)
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "the main menu after X",
                     limit=100_000_000)
        zp.check(not os.path.exists(sd.path("SAVEGAME.ZPS")), "X saved the game")


if __name__ == "__main__":
    zp.main(globals())
