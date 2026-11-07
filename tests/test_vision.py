"""The vision modes: each level's palettes (ZPDATA/LEVELnn.ZPV) are loaded;
the vision control (K_VISION, N) steps through the modes the VTOL has,
swapping each one's palette in, then back to normal; with none it does
nothing; and in a vision mode the figures are drawn from the same graphics,
recoloured by the mode's palette: each figure colour's own vision colour
(sprites/palette.json's "vision").
"""
import os
import sys

import zptest as zp
from zptest import sym
from test_figures import find_human

sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
import spritefile as sf  # noqa: E402

L2_PAL = 1                                  # nexsim: Layer 2's first palette
VIS_ALL = sym["VIS_NV_GREEN"] | sym["VIS_NV_MONO"] | sym["VIS_THERMAL"]


def zpv(sd, mode, lv=1):
    """The level's palette for a vision mode, from its .ZPV, as 9-bit values."""
    data = open(sd.path(f"LEVEL{lv:02d}.ZPV"), "rb").read()
    p = 8 + 512 * mode
    return [data[p + 2 * i] << 1 | (data[p + 2 * i + 1] & 1) for i in range(256)]


def shown(cpu):
    return [cpu.palettes.get(L2_PAL, {}).get(i) for i in range(256)]


def press_n(cpu):
    """The vision control: N for a frame, then let go for one."""
    cpu.keys = {"N"}
    zp.frames(cpu, 1)
    cpu.keys = set()
    zp.frames(cpu, 1)


def game(owned):
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)
    cpu.wr(sym["vision_owned"], owned)
    return sd, cpu


def test_loaded():
    sd, cpu = game(0)
    try:
        zp.check(os.path.exists(sd.path("LEVEL01.ZPV")), "no ZPDATA/LEVEL01.ZPV")
        zp.check(cpu.rd(sym["vis_ok"]) == 1, "vis_ok is 0: LEVEL01.ZPV not loaded")
        zp.check(cpu.rd(sym["vision_mode"]) == 0, "not in normal vision at the start")
        zp.check(shown(cpu) == zpv(sd, 0), "the Layer 2 palette isn't the level's normal one")
        press_n(cpu)
        zp.check(cpu.rd(sym["vision_mode"]) == 0, "N changed the mode with no vision mode owned")
    finally:
        sd.close()


def test_cycle_all():
    sd, cpu = game(VIS_ALL)
    try:
        for want in (1, 2, 3, 0, 1):
            press_n(cpu)
            got = cpu.rd(sym["vision_mode"])
            zp.check(got == want, f"N: mode {got}, not {want}")
            zp.check(shown(cpu) == zpv(sd, want), f"mode {want}: the Layer 2 palette isn't its palette")
    finally:
        sd.close()


def test_cycle_thermal_only():
    sd, cpu = game(sym["VIS_THERMAL"])
    try:
        for want in (3, 0, 3):
            press_n(cpu)
            got = cpu.rd(sym["vision_mode"])
            zp.check(got == want, f"N with thermal only: mode {got}, not {want}")
    finally:
        sd.close()


def drawn_entries(cpu, x, z, y):
    """Look at the human: the Layer 2 entries of the first level drawn for
    it (the pixel data spr_draw gets: spr_pg, spr_ptr)."""
    zp.set_camera(cpu, x << 8, (z - 150) << 8, y + 24)
    got = []
    flips = []
    cpu.on_flip = lambda b: flips.append(1)
    while len(flips) < 2:
        if (not got and cpu.pc == sym["spr_draw"] and cpu.mmu[4] == sym["PAGE_CITY2"]
                and cpu.rd(sym["fig_anim"]) >= sym["ANIM_HUMAN_WAVE"]):
            page = cpu.page(cpu.rd(sym["spr_pg"]))     # (an absolute page)
            p = cpu.rd16(sym["spr_ptr"]) - 0xC000
            for _ in range(cpu.rd(sym["zh"])):      # its rows: skip, count, entries
                n = page[p + 1]
                got += [v for v in page[p + 2:p + 2 + n] if v]
                p += 2 + n
        cpu.step()
    cpu.on_flip = None
    return set(got)


def nine_bit(c):
    r, g, b = c
    return (r << 6) | (g << 3) | b


def test_figures_by_palette():
    """The same graphics in every mode; each figure colour's palette entry
    its own colour for the mode, in the palette the game swaps in."""
    sd, cpu = game(VIS_ALL)
    try:
        x, z, y = find_human(cpu)
        normal = drawn_entries(cpu, x, z, y)
        zp.check(normal, "no human drawn")
        vis = sf.load_vision()
        for mode, name in ((1, "NVG"), (2, "NVM"), (3, "THM")):
            press_n(cpu)
            zp.check(cpu.rd(sym["vision_mode"]) == mode, f"not in mode {mode}")
            drawn = drawn_entries(cpu, x, z, y)
            zp.check(drawn == normal, f"{name}: drawn with entries {sorted(drawn)}, not {sorted(normal)}")
            pal = shown(cpu)
            for e in drawn:
                want = nine_bit(vis[name][e - sym["SPR_PAL0"]])
                zp.check(pal[e] == want, f"{name}: entry {e} is {pal[e]:03o}, not its vision colour {want:03o}")
        zp.note(f"human entries {sorted(normal)} in every mode")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
