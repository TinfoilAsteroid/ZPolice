"""GAME OVER stays up until SPACE is pressed, then the main menu.  A SPACE
already held when the screen comes up (firing) doesn't count.  It is drawn
over the last frame of the view (the game's Layer 2): GAME OVER in fire
colours, VTOL DESTROYED or BASE DESTROYED, PRESS SPACE TO CONTINUE.  And the
crash before it: fire bursts, the heavy shake as the wreck hits the ground.
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


def shown(cpu):
    """The Layer 2 buffer shown: rows of 256"""
    p = cpu.nextreg.get(0x12, 0) * 2
    buf = b"".join(bytes(cpu.page(p + i)) for i in range(6))
    return [buf[y * 256:(y + 1) * 256] for y in range(192)]


def colours(rows, y0, h):
    return {c for y in range(y0, y0 + h) for c in rows[y]}


def overlay_ok(cpu, why):
    """GAME OVER (fire colours), why (yellow) and the prompt (white) over the
    view, each with its black shadow"""
    rows = shown(cpu)
    fire = {sym["FIRE_COL0"] + 4 * k for k in range(10)}
    zp.check(len(colours(rows, sym["GO_TITLE_Y"], 10) & fire) >= 5, "no GAME OVER in fire colours")
    zp.check(sym["BULLET_COL"] in colours(rows, sym["GO_WHY_Y"], 10), "no yellow line under GAME OVER")
    zp.check(sym["EDGE_COL"] in colours(rows, sym["GO_PROMPT_Y"], 8), "no PRESS SPACE TO CONTINUE")
    zp.check(sym["MAP_BG"] in colours(rows, sym["GO_TITLE_Y"], 11), "no shadow")
    # which line: the text's yellow pixels, against each message drawn in Python
    import os, sys
    sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
    import fontfile as ff
    f = ff.Font.load(ff.F12.PATH, ff.F12)
    for text, name in (("VTOL DESTROYED", "vtol"), ("BASE DESTROYED", "base")):
        x0 = (256 - 12 * len(text)) // 2
        ink = {(x0 + 12 * i + x, sym["GO_WHY_Y"] + y) for i, ch in enumerate(text)
               for y in range(10) for x in range(12) if f.glyphs[ch][y][x]}
        got = {(x, y) for y in range(sym["GO_WHY_Y"], sym["GO_WHY_Y"] + 10) for x in range(256)
               if rows[y][x] == sym["BULLET_COL"]}
        if name == why:
            zp.check(got == ink, f"not {text}: {len(got ^ ink)} pixels differ")


def test_waits_for_space():
    sd, cpu = over("")
    try:
        scans(cpu, OLD_PAUSE + 20)
        overlay_ok(cpu, "base")             # (game_over set: the pad's way)
        cpu.keys = {" "}
        goes_to_menu(cpu)
    finally:
        sd.close()


def test_crash():
    """The VTOL destroyed in the air: a fire burst at once, debris as it
    falls, the heavy shake and a bigger burst as it hits the ground, then
    GAME OVER over the view, VTOL DESTROYED"""
    sd = zp.SD()
    try:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.set_camera(cpu, (20 << 16) | 0x8000, (20 << 16) | 0x8000, 200)
        zp.frames(cpu, 2)
        parts = sym["particles"]
        live = lambda: sum(1 for k in range(sym["NPART"]) if cpu.rd(parts + k * sym["PREC"]))
        cpu.wr(sym["vtol_hp"], 0)
        cpu.wr(sym["vtol_dead"], 1)
        zp.frames(cpu, 1)
        n0 = live()
        zp.check(n0 >= sym["WRECK_BOOM"] // 2, f"no explosion: {n0} particles")
        seen, big = n0, False
        for _ in range(200):
            zp.frames(cpu, 1)
            seen = max(seen, live())
            if cpu.rd(sym["dead_down"]) and cpu.rd16(sym["shake_tab"]) == sym["shake_big_xy"]:
                big = True
                n1 = live()
                break
        zp.check(big, "no heavy shake as it hit the ground")
        zp.check(n1 >= sym["WRECK_IMPACT"] // 2, f"no impact burst: {n1} particles")
        zp.note(f"particles: {n0} at the explosion, {n1} at the impact")
        zp.run_until(cpu, lambda: cpu.pc == sym["game_over_screen"], "GAME OVER")
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "its key scan")
        overlay_ok(cpu, "vtol")
        zp.check(cpu.nextreg.get(0x16, 0) == 0 and cpu.nextreg.get(0x17, 0) == 0, "the view left shaken")
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
