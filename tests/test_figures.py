"""The figures' graphics (ZPDATA/SPRITES.ZPG): loaded at start-up; a human
is drawn standing, waving, or running seen from the front, the side
(mirrored or not) or behind by the way it runs; without the file the game
still runs, drawing no figures.
"""
import zptest as zp
from zptest import sym

GFX_PAGES = [sym["PAGE_GFX0"] + i for i in range(sym["GFX_PAGES_MAX"])]


def find_human(cpu):
    hu = sym["humans"]
    for k in range(sym["HUMAN_MAX"]):
        a = hu + k * sym["HREC"]
        if cpu.rd(a + 6) == 1:
            return cpu.rd16(a), cpu.rd16(a + 2), cpu.rd16(a + 4)
    raise AssertionError("no human waiting on level 1")


def drawn_as(cpu, x, z, y, run):
    """Look north at the human from 150 units south, its way set to run
    (record +13: 0 standing, HUM_WAVING, 1 +z, 2 +x, 3 -z, 4 -x): its (fig_anim, zface)
    as drawn, or None if it wasn't."""
    zp.set_camera(cpu, x << 8, (z - 150) << 8, y + 24)
    seen = []
    flips = []
    cpu.on_flip = lambda b: flips.append(1)
    while len(flips) < 2:
        if cpu.pc == sym["human_draw"]:
            cpu.wr(cpu.ix + 13, run)
        elif cpu.pc == sym["spr_draw"] and cpu.mmu[4] == sym["PAGE_CITY2"]:
            seen.append((cpu.rd(sym["fig_anim"]), cpu.rd(sym["zface"])))
        cpu.step()
    cpu.on_flip = None
    humans = [s for s in seen if s[0] >= sym["ANIM_HUMAN_WAVE"]]
    return humans[-1] if humans else None


def test_loaded():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.check(cpu.rd(sym["gfx_ok"]) == 1, "gfx_ok is 0: SPRITES.ZPG not loaded")
        data = open(sd.path("SPRITES.ZPG"), "rb").read()
        h = sym["GFX_HEADER"]
        got = b"".join(bytes(cpu.page(p)) for p in GFX_PAGES)[:len(data) - h]
        zp.check(got == data[h:], "the graphics pages don't hold SPRITES.ZPG")


def test_human_facing():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        x, z, y = find_human(cpu)
        W, St = sym["ANIM_HUMAN_WAVE"], sym["ANIM_HUMAN_STAND"]
        F, S, R = sym["ANIM_HUMAN_RUN_FRONT"], sym["ANIM_HUMAN_RUN_SIDE"], sym["ANIM_HUMAN_RUN_REAR"]
        want = {0: (St, 0), sym["HUM_WAVING"]: (W, 0), 1: (R, 0), 2: (S, 2), 3: (F, 0), 4: (S, 0)}
        for run, w in want.items():
            got = drawn_as(cpu, x, z, y, run)
            zp.check(got == w, f"running way {run}: drawn as (anim, zface) {got}, not {w}")


def test_without_file():
    with zp.SD(drop=["SPRITES.ZPG"]) as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.check(cpu.rd(sym["gfx_ok"]) == 0, "gfx_ok is 1 without SPRITES.ZPG")
        x, z, y = find_human(cpu)
        zp.check(drawn_as(cpu, x, z, y, 0) is None, "a figure was drawn without SPRITES.ZPG")
        zp.frames(cpu, 3)


if __name__ == "__main__":
    zp.main(globals())
