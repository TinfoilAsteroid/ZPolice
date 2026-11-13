"""The debug keys: 0 kills the wave's enemies (the humans left as they are),
so it moves on a wave, or on the last wave completes the level;
9 picks a level (LEVEL SELECT over the view: Q up, A down, SPACE goes, 9
back); 8 completes the level from any wave, on to the final boss: level 50's
last wave.
"""
import zptest as zp
from zptest import sym

def _two_waves():
    """A level with two waves or more (levels/LEVELnn.TXL: they get edited)"""
    import glob
    import os
    import levelfile as lf
    for p in sorted(glob.glob(os.path.join(zp.ROOT, "levels", "LEVEL*.TXL"))):
        d = lf.read(p)
        if 2 <= d["lv"] <= 40 and d["values"][1] >= 2 and not any(
                lf.SPEC_NAMES[t] == "DEVIL" for sp in d["waves_specials"] for t, _ in sp):
            return d["lv"]
    raise AssertionError("no level with two waves")


LEVEL = _two_waves()                    # (10 when written)


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


def shown(cpu):
    """The level the selector shows (dls_level), and its box's text"""
    a = sym["txt_dls"]
    return cpu.rd(sym["dls_level"]), bytes(cpu.rd(a + i) for i in range(17)).split(bytes(1))[0].decode()


def scans(cpu, keys, n):
    """Hold keys for n of the selector's key scans"""
    cpu.keys = set(keys)
    k = [0]

    def count():
        if cpu.pc == sym["kbd_scan"]:
            k[0] += 1
        return k[0] > n
    zp.run_until(cpu, count, f"{n} key scans", limit=(n + 2) * 2_000_000)


def tap(cpu, key):
    scans(cpu, key, 1)
    scans(cpu, "", 1)


def in_select(cpu):
    """In the selector's loop (or the key scan it called)"""
    pc = cpu.rd16(cpu.sp) if cpu.pc == sym["kbd_scan"] else cpu.pc
    return sym["debug_level_select"] <= pc < sym["dls_show"]


def start_level(cpu):
    """SPACE on the selector: the load-out (0 starts), then the level"""
    cpu.keys = {" "}
    zp.run_until(cpu, lambda: cpu.mmu[6] == sym["PAGE_LOADOUT"], "the load-out screen")
    cpu.keys = {"0"}
    zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "the level")
    cpu.keys = set()


def test_key_0_leaves_the_humans():
    """0: every monster gone, no human counted rescued or taken off the map"""
    sd, cpu = game()
    try:
        H, HR = sym["humans"], sym["HREC"]
        before = [cpu.rd(H + k * HR + 6) for k in range(sym["HUMAN_MAX"])]
        saved = cpu.rd(sym["saved"])
        zp.check(sym["HS_WAIT"] in before, "no human waiting to test with")
        press(cpu, "0")
        live = [k for k in range(sym["NMON"]) if cpu.rd(sym["zombies"] + k * sym["ZREC"] + 10) & 1
                and cpu.rd(sym["wave_number"]) == 1]
        zp.check(not live, f"monsters {live} left on wave 1")
        after = [cpu.rd(H + k * HR + 6) for k in range(sym["HUMAN_MAX"])]
        zp.check(cpu.rd(sym["saved"]) == saved, f"0 counted {cpu.rd(sym['saved']) - saved} rescued")
        zp.check(after == before, "0 changed the humans")
    finally:
        sd.close()


def test_key_9():
    """9: LEVEL SELECT from the next level; Q, Q, A: two on, one back; SPACE:
    that level, from wave 1"""
    sd, cpu = game()
    try:
        press(cpu, "0")                 # (on wave 2: the new level starts at 1)
        zp.frames(cpu, 2)
        cpu.keys = {"9"}
        zp.run_until(cpu, lambda: in_select(cpu), "the level select")
        scans(cpu, "", 1)
        zp.check(in_select(cpu), "9 didn't open the level select")
        zp.check(shown(cpu) == (LEVEL + 1, f" LEVEL SELECT {LEVEL + 1:02d} "), f"9: {shown(cpu)}")
        for k in "QQA":
            tap(cpu, k)
        zp.check(shown(cpu)[0] == LEVEL + 2, f"Q Q A: level {shown(cpu)[0]}, not {LEVEL + 2}")
        start_level(cpu)
        zp.check(cpu.rd(sym["level"]) == LEVEL + 2, f"level {cpu.rd(sym['level'])}, not {LEVEL + 2}")
        zp.check(cpu.rd(sym["wave_number"]) == 1, f"wave {cpu.rd(sym['wave_number'])}, not 1")
        zp.frames(cpu, 2)
        zp.check(cpu.rd(sym["level_done"]) == 0 and cpu.rd(sym["game_over"]) == 0, "it isn't playing")
    finally:
        sd.close()


def test_key_9_limits():
    """A stops at 1, Q at LEVEL_LAST (held, they repeat); 9 again goes back to
    the level, as it was"""
    sd, cpu = game()
    try:
        cpu.keys = {"9"}
        zp.run_until(cpu, lambda: in_select(cpu), "the level select")
        scans(cpu, "", 1)
        scans(cpu, "A", 60)              # (held: repeating, down to 1)
        zp.check(shown(cpu)[0] == 1, f"A held: level {shown(cpu)[0]}, not 1")
        scans(cpu, "Q", 200)
        zp.check(shown(cpu)[0] == sym["LEVEL_LAST"], f"Q held: level {shown(cpu)[0]}")
        scans(cpu, "", 1)
        cpu.keys = {"9"}
        zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "the game again", limit=20_000_000)
        cpu.keys = set()
        zp.check(cpu.rd(sym["level"]) == LEVEL and cpu.rd(sym["wave_number"]) == 1,
                 f"9: level {cpu.rd(sym['level'])} wave {cpu.rd(sym['wave_number'])}")
        zp.frames(cpu, 2)
        zp.check(not in_select(cpu), "still in the level select")
    finally:
        sd.close()


def test_key_9_level_1():
    """Level 1 can be picked (A from the next)"""
    sd, cpu = game()
    try:
        cpu.keys = {"9"}
        zp.run_until(cpu, lambda: in_select(cpu), "the level select")
        scans(cpu, "", 1)
        scans(cpu, "A", 60)
        scans(cpu, "", 1)
        start_level(cpu)
        zp.check(cpu.rd(sym["level"]) == 1, f"level {cpu.rd(sym['level'])}, not 1")
    finally:
        sd.close()


def test_key_8():
    sd, cpu = game()
    try:
        press(cpu, "8")
        level_ends(cpu)
        cpu.keys = {" "}                # level complete: SPACE; the load-out: 0
        zp.run_until(cpu, lambda: cpu.mmu[6] == sym["PAGE_LOADOUT"], "the load-out screen")
        cpu.keys = {"0"}
        zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "the next level")
        cpu.keys = set()
        zp.check(cpu.rd(sym["level"]) == sym["LEVEL_LAST"], f"8: level {cpu.rd(sym['level'])}")
        waves = cpu.rd(sym["level_cur"] + sym["LV_WAVES"])
        zp.check(cpu.rd(sym["wave_number"]) == waves, f"wave {cpu.rd(sym['wave_number'])}, not {waves}")
        zp.frames(cpu, 2)
        devils = [i for i in range(sym["NZOMB"], sym["NMON"])
                  if cpu.rd(sym["zombies"] + i * sym["ZREC"] + 15) == sym["ZT_DEVIL"]
                  and cpu.rd(sym["zombies"] + i * sym["ZREC"] + 10) & 1]
        zp.check(len(devils) == 1 and cpu.rd(sym["devil_gfx"]) == 1, "no devil")
    finally:
        sd.close()


def test_level_complete_message():
    for lv in (5, 10):
        with zp.SD() as sd:
            cpu = zp.machine(sd)
            zp.start_game(cpu, lv)
            zp.frames(cpu, 2)
            for _ in range(10):         # 0: wave by wave to the level's end
                w = cpu.rd(sym["wave_number"])
                if w == cpu.rd(sym["level_cur"] + sym["LV_WAVES"]):
                    press(cpu, "0")     # (the last: the level ends)
                    break
                press(cpu, "0")
                zp.frames(cpu, 2)
            level_ends(cpu)
            zp.run_until(cpu, lambda: cpu.pc == sym["salvage_award"], "the level complete screen")
            a = sym["txt_level_done"]
            t = bytes(cpu.rd(a + i) for i in range(20)).split(bytes(1))[0].decode()
            zp.check(t == f"LEVEL {lv} COMPLETE", f"the message is {t!r}")


if __name__ == "__main__":
    zp.main(globals())
