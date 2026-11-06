"""The debug keys: 0 moves on a wave, or on the last wave completes the level;
9 completes the level from any wave, so the next is the next level.
"""
import zptest as zp
from zptest import sym

LEVEL = 10                              # two waves


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, LEVEL)
    zp.frames(cpu, 2)                   # (0 left the load-out screen: let go)
    return sd, cpu


def press(cpu, key):
    cpu.keys = {key}
    zp.frames(cpu, 1)
    cpu.keys = set()


def level_ends(cpu):
    zp.run_until(cpu, lambda: cpu.rd(sym["level_done"]) == 1, "the level's end", limit=20_000_000)


def test_key_0():
    sd, cpu = game()
    try:
        zp.check(cpu.rd(sym["wave_number"]) == 1, "not on wave 1")
        press(cpu, "0")
        zp.frames(cpu, 2)
        zp.check(cpu.rd(sym["wave_number"]) == 2, f"0: wave {cpu.rd(sym['wave_number'])}, not 2")
        zp.check(cpu.rd(sym["level_done"]) == 0, "0 on wave 1 ended the level")
        press(cpu, "0")
        level_ends(cpu)
        zp.check(cpu.rd(sym["level"]) == LEVEL, "the level moved on too soon")
    finally:
        sd.close()


def test_key_9():
    sd, cpu = game()
    try:
        press(cpu, "9")
        level_ends(cpu)
        zp.check(cpu.rd(sym["level"]) == LEVEL, f"9: level {cpu.rd(sym['level'])}, before the "
                                                f"level complete screen moves it on one")
        cpu.keys = {" "}                # the level complete screen: SPACE
        zp.run_until(cpu, lambda: cpu.rd(sym["level"]) == LEVEL + 1, "the next level")
        cpu.keys = set()
    finally:
        sd.close()


def test_level_complete_message():
    for lv in (5, 10):
        with zp.SD() as sd:
            cpu = zp.machine(sd)
            zp.start_game(cpu, lv)
            zp.frames(cpu, 2)
            press(cpu, "9")
            level_ends(cpu)
            zp.run_until(cpu, lambda: cpu.pc == sym["salvage_award"], "the level complete screen")
            a = sym["txt_level_done"]
            t = bytes(cpu.rd(a + i) for i in range(20)).split(bytes(1))[0].decode()
            zp.check(t == f"LEVEL {lv} COMPLETE", f"the message is {t!r}")


if __name__ == "__main__":
    zp.main(globals())
