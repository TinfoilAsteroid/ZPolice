"""The final boss, the devil (devil.asm): alone in the last wave of the last
level, rising at the entrance to hell (a circle of road), its graphics over
the other monsters' pages (PREPARE FOR COMBAT: devil_load) and the figures'
own back at the next level's start.  Scaled to its size as it's drawn.  It
chases the VTOL half a tile a step, shaking the view at each footfall,
knocking down buildings under level 5, terraces, barricades and even the pad
(no game over) on its way, and walking over rubble.  In range its eyes charge
black to blue over 10 s (interrupts; a rising whine for the last 3), then
lightning with a crackling zap: straight at the VTOL (10 damage, a spin of 7-44 degrees, its nose half way up or down, its speed
halved), unless a building is in the way: that comes down instead (cover), bringing down any building it passes below the roof of.  Killed, it
sinks into the ground.
"""
import os
import sys

import zptest as zp
from zptest import sym

ZREC, NZOMB, NMON = sym["ZREC"], sym["NZOMB"], sym["NMON"]
sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
import levelfile as lf  # noqa: E402
import spritefile as sf  # noqa: E402

FB0 = sym["bullets"] + (sym["NBULLETS"] - sym["NFIRE"]) * sym["BREC"]
HX, HZ = sym["HELL_X"], sym["HELL_Z"]
DX, DZ = HX * 256 + 128, HZ * 256 + 128          # its starting place (world units)


def rec(i):
    return sym["zombies"] + i * ZREC


def devils(cpu):
    return [rec(i) for i in range(NZOMB, NMON)
            if cpu.rd(rec(i) + 10) & 1 and cpu.rd(rec(i) + 15) == sym["ZT_DEVIL"]]


def hp(cpu, r):
    return cpu.rd(r + 18) + 256 * cpu.rd(r + sym["LICH_HP_HI"])


def devil_game():
    """Level 50, its last wave begun: the devil in, its graphics loaded"""
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, 50)
    zp.check(not devils(cpu), "the devil before the last wave")
    cpu.wr(sym["wave_number"], cpu.rd(sym["level_cur"] + sym["LV_WAVES"]) - 1)
    for i in range(NMON):
        cpu.wr(rec(i) + 10, 0)
    zp.frames(cpu, 2)
    return sd, cpu


def only_devil(cpu):
    """Everyone else gone, the VTOL away from it, facing away (quick frames)"""
    r = devils(cpu)[0]
    for i in range(NMON):
        if rec(i) != r:
            cpu.wr(rec(i) + 10, 0)
    return r


def look_at(cpu, dist, y=100, x=DX, z=DZ):
    """The VTOL dist units south of (x, z), looking north at it"""
    zp.set_camera(cpu, x << 8, (z - dist) << 8, y)


def shown(cpu):
    p = cpu.nextreg.get(0x12, 0) * 2
    buf = b"".join(bytes(cpu.page(p + i)) for i in range(4))
    return [buf[y * 256:(y + 1) * 256] for y in range(sym["VIEW_H"])]


def spec16(cpu, a):
    """A word of the specials page (devil.asm's data), whatever is in slot 6"""
    sp = cpu.page(sym["PAGE_SPECIAL"])
    return sp[a - 0xC000] + 256 * sp[a - 0xC000 + 1]


def cell_ptr(x, z):
    return sym["city_map"] + z * 64 + x


def test_the_last_wave():
    sd, cpu = devil_game()
    try:
        ds = devils(cpu)
        zp.check(len(ds) == 1, f"{len(ds)} devils in the last wave")
        r = ds[0]
        zp.check((cpu.rd(r + 1), cpu.rd(r + 3)) == (HX, HZ), "not at the entrance to hell")
        moved = abs(cpu.rd16(r) - DX) + abs(cpu.rd16(r + 2) - DZ)
        zp.check(moved <= 4 * sym["DV_STEP_U"], f"{moved} units from its cell's middle")
        zp.check(hp(cpu, r) == sym["DEVIL_HP"], f"{hp(cpu, r)} hit points")
        others = {cpu.rd(rec(i) + 15) for i in range(NZOMB, NMON) if cpu.rd(rec(i) + 10) & 1} - {sym["ZT_DEVIL"]}
        zp.check(not others, f"other special monsters with it: {others}")
        hell = [(x, z) for z in range(HZ - 3, HZ + 4) for x in range(HX - 3, HX + 4)
                if (x - HX) ** 2 + (z - HZ) ** 2 <= 10]
        zp.check(all(cpu.rd(cell_ptr(x, z)) & 31 == 0 for x, z in hell), "no circle of road")
        # its graphics, over the pages from the kept ones on
        zp.check(cpu.rd(sym["devil_gfx"]) == 1, "its graphics not loaded")
        figs = open(sd.path("SPRITES.ZPG"), "rb").read()
        keep = cpu.rd(sym["gfx_keep"])
        zp.check(keep == figs[7], f"kept pages {keep}, the file says {figs[7]}")
        data = open(sd.path("DEVIL.ZPB"), "rb").read()
        h = sym["GFX_HEADER"]
        for k in range(sym["DEVIL_FRAMES"]):
            page = bytes(cpu.page(sym["PAGE_GFX0"] + keep + k))
            zp.check(page == data[h + 8192 * k:h + 8192 * (k + 1)], f"frame {k} not in page {keep + k}")
        zp.note(f"kept pages: {keep}; the devil's: {keep}..{keep + sym['DEVIL_FRAMES'] - 1}")
    finally:
        sd.close()


def test_vision_modes():
    """White and blue normally; thermal black, its outline grey, its eyes to red;
    night vision green bright greens, monochrome light greys, its eyes to
    white in both"""
    data = open(os.path.join(zp.ROOT, "ZPDATA", "LEVEL50.ZPV"), "rb").read()
    pal = [[(data[8 + 512 * m + 2 * i] >> 5, (data[8 + 512 * m + 2 * i] >> 2) & 7,
             ((data[8 + 512 * m + 2 * i] & 3) << 1) | (data[9 + 512 * m + 2 * i] & 1)) for i in range(256)]
           for m in range(4)]
    mine = [pal_i for pal_i in range(sym["DEVIL_COL0"], sym["DEVIL_COL3"] + 1)]
    zp.check(pal[0][sym["DEVIL_COL0"]] == (7, 7, 7) and pal[0][sym["DEVIL_COL2"]][2] == 7, "not white and blue")
    zp.check([pal[3][i] for i in mine] == [(0, 0, 0)] * 3 + [(3, 3, 3)],
             f"thermal: {[pal[3][i] for i in mine]}, not black with a grey outline")
    zp.check(all(pal[1][i][1] >= 3 and pal[1][i][1] > max(pal[1][i][0], pal[1][i][2]) for i in mine)
             and max(pal[1][i][1] for i in mine) == 7, f"night vision green: {[pal[1][i] for i in mine]}")
    zp.check(all(len(set(pal[2][i])) == 1 and pal[2][i][0] >= 3 for i in mine), f"monochrome: {[pal[2][i] for i in mine]}")
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        look_at(cpu, 1024, 100)
        for mode, want in ((3, 0x1C0), (1, 0x1FF), (2, 0x1FF), (0, 0x01F)):   # (normal: electric blue)
            cpu.wr(r + sym["DV_EYES"], 1)
            cpu.wr16(r + sym["DV_T0"], 0)
            cpu.wr16(sym["isr_ticks"], sym["DV_CHARGE_T"] - 1)
            cpu.wr(sym["vision_mode"], mode)
            zp.frames(cpu, 1)
            eye = cpu.palettes.get(1, {}).get(sym["DEVIL_EYE"], 0)
            zp.check(eye == want, f"vision mode {mode}: its eyes ${eye:03X} charged, not ${want:03X}")
    finally:
        sd.close()


def test_treads():
    """Its footfall kills the zombies and waiting humans under its feet, not
    those beyond them"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        zp.set_camera(cpu, 32 * 256 << 8, 30 * 256 << 8, 60, yaw=128)    # (far off)
        cpu.wr16(r, DX)
        cpu.wr16(r + 2, DZ)
        cpu.wr(r + 7, 1)                            # (holding still)
        z = [sym["zombies"] + i * sym["ZREC"] for i in (0, 1)]
        for a, dx in zip(z, (60, 300)):             # one underfoot, one beyond
            cpu.wr(a + 10, 1)
            cpu.wr(a + 15, 0)
            cpu.wr16(a, DX + dx)
            cpu.wr16(a + 2, DZ)
        hu = sym["humans"]
        h = [hu + k * sym["HREC"] for k in (0, 1)]
        for a, dz in zip(h, (-80, 400)):
            cpu.wr(a + 6, sym["HS_WAIT"])
            cpu.wr16(a, DX)
            cpu.wr16(a + 2, DZ + dz)
            cpu.wr16(a + 4, 0)
        for k in range(2, sym["HUMAN_MAX"]):
            cpu.wr(hu + k * sym["HREC"] + 6, 0)
        cpu.wr(r + 7, 0)                            # its footfall next frame
        cpu.wr(r + 4, 1)
        cpu.wr16(r, DX - sym["DV_STEP_U"])
        cpu.wr(r + 11, sym["DV_MOVE_FR"] - 1)
        zp.frames(cpu, 1)
        zp.check(not cpu.rd(z[0] + 10) & 1, "the zombie underfoot not killed")
        zp.check(cpu.rd(z[1] + 10) & 1, "a zombie beyond its feet killed")
        zp.check(cpu.rd(h[0] + 6) == sym["HS_DEAD"], "the human underfoot not killed")
        zp.check(cpu.rd(h[1] + 6) == sym["HS_WAIT"], "a human beyond its feet killed")
    finally:
        sd.close()


def test_level_files():
    """Only in a level's last wave, alone, one of it"""
    assert "DEVIL" in lf.SPEC_NAMES
    d = lf.level_parse(open(os.path.join(zp.ROOT, "levels", "LEVEL50.TXL")).read())
    dv = lf.SPEC_NAMES.index("DEVIL")
    zp.check(d["waves_specials"][-1] == [(dv, 1)], "level 50's last wave isn't the devil alone")
    zp.check(all(dv not in [t for t, _ in sp] for sp in d["waves_specials"][:-1]), "the devil early")
    cities = {d["cn"]: ([0] * 4096, [0] * 4096)}

    def errs(waves):
        e = dict(d, values=[d["values"][0], len(waves), d["values"][2], d["values"][3]],
                 waves_specials=waves, changes=[])
        return lf.level_check(50, e, cities)
    gh = lf.SPEC_NAMES.index("GHOST")
    zp.check(any("without" in e for e in errs([[(dv, 1), (gh, 1)]])), "a ghost allowed with it")
    zp.check(any("last wave" in e for e in errs([[(dv, 1)], []])), "allowed before the last wave")
    zp.check(any("one DEVIL" in e for e in errs([[(dv, 2)]])), "two allowed")


def test_drawn():
    """Scaled to its size, its eyes and body in the view"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        dist, y = 1024, 100
        look_at(cpu, dist, y)
        zp.frames(cpu, 2)
        rows = shown(cpu)
        eye = sym["DEVIL_EYE"]
        body = set(range(sym["DEVIL_COL0"], sym["DEVIL_COL3"] + 1))     # (its own colours)
        eyes = sum(row.count(eye) for row in rows)
        mine = [(x, yy) for yy, row in enumerate(rows) for x, c in enumerate(row)
                if c in body and 96 <= x < 160]
        zp.check(eyes > 0, "no eyes")
        zp.check(len(mine) > 200, f"{len(mine)} body pixels")
        ys = [yy for _, yy in mine]
        xs = [x for x, _ in mine]
        top = 64 - (sym["DEVIL_H"] - y) * 128 / dist      # its head and feet as projected
        bot = 64 + y * 128 / dist
        zp.note(f"rows {min(ys)}..{max(ys)} (projected {top:.0f}..{bot:.0f}), columns {min(xs)}..{max(xs)}")
        zp.check(abs(min(ys) - max(0, top)) <= 4 and abs(max(ys) - bot) <= 3, "not its projected height")
        zp.check(abs((min(xs) + max(xs)) / 2 - 128) <= 6, "not in the middle")
        zp.check(cpu.rd(r + 31) & 1, "not noted as seen (the missile lock)")
        # close to: taller than the view, still drawn
        look_at(cpu, 300, y)
        zp.frames(cpu, 1)
        rows = shown(cpu)
        n = sum(1 for row in rows for c in row if c in body)
        zp.check(n > 4000, f"close to: {n} body pixels")
    finally:
        sd.close()


def turn_from(cpu, r, cx, cz, heading, vtol):
    """The devil in cell (cx, cz)'s middle facing heading, the VTOL over cell
    vtol: its heading after the frame it chooses its way"""
    zp.set_camera(cpu, (vtol[0] * 256 + 128) << 8, (vtol[1] * 256 + 128) << 8, 60, yaw=128)
    cpu.wr16(r, cx * 256 + 128)
    cpu.wr16(r + 2, cz * 256 + 128)
    cpu.wr(r + 4, heading)
    cpu.wr(r + 7, 0)
    cpu.wr(r + 11, 0)
    zp.frames(cpu, 1)
    return cpu.rd(r + 4)


def test_chases_the_vtol():
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        hd = turn_from(cpu, r, HX, HZ, 2, (HX + 25, HZ))
        zp.check(hd == 1, f"the VTOL east: heading {hd}, not +x")
        moved = abs(cpu.rd16(r) - DX) + abs(cpu.rd16(r + 2) - DZ)
        zp.check(moved == sym["DV_STEP_U"], f"moved {moved} in a frame")
        hd = turn_from(cpu, r, HX, HZ, 1, (HX, HZ + 8))
        zp.check(hd == 0, f"the VTOL north: heading {hd}, not +z")
        hd = turn_from(cpu, r, HX, HZ, 1, (HX - 10, HZ))
        zp.check(hd == 3, f"the VTOL straight behind: heading {hd}, not turned round")
        # the footfall: a shake, the other leg
        cpu.wr(sym["shake_t"], 0)
        leg = cpu.rd(r + 5)
        cpu.wr(r + 11, sym["DV_MOVE_FR"] - 1)
        zp.frames(cpu, 1)
        zp.check(cpu.rd(sym["shake_t"]) > 0, "no shake at the footfall")
        zp.check(cpu.rd(r + 5) == leg ^ 1, "the same leg")
    finally:
        sd.close()


def test_walks_through_low_buildings():
    """Under level 5: knocked down as it walks on (as the lightning does);
    level 5 and up: it goes round"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        c0, n = sym["COLLAPSE_CODE"], sym["COLLAPSE_N"]
        p = cell_ptr(HX + 1, HZ)
        cpu.wr(p, sym["DV_TALL"] - 1)
        hd = turn_from(cpu, r, HX, HZ, 2, (HX + 25, HZ))
        zp.check(hd == 1, f"a level {sym['DV_TALL'] - 1} building east: heading {hd}, not through it")
        zp.check(c0 <= cpu.rd(p) & 31 < c0 + n, f"not coming down: code {cpu.rd(p) & 31}")
        cpu.wr(p, sym["DV_TALL"])
        hd = turn_from(cpu, r, HX, HZ, 2, (HX + 25, HZ))
        zp.check(hd != 1, f"walked into a level {sym['DV_TALL']} building")
        cpu.wr(p, sym["RUBBLE_CODE"])               # rubble: as road
        hd = turn_from(cpu, r, HX, HZ, 2, (HX + 25, HZ))
        zp.check(hd == 1 and cpu.rd(p) & 31 == sym["RUBBLE_CODE"], "rubble not walked over")
    finally:
        sd.close()


def test_flattens_the_base():
    """Terrace and pad knocked down on its way, no game over"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        c0, n = sym["COLLAPSE_CODE"], sym["COLLAPSE_N"]
        bhp = sym["base_hp"]
        tx, tz = 30, 32                             # a terrace tile, then the pad
        zp.check(cpu.rd(cell_ptr(tx, tz)) & 31 == sym["TERRACE_CODE"], "no terrace there")
        hd = turn_from(cpu, r, tx - 1, tz, 1, (45, tz))
        zp.check(hd == 1, f"heading {hd}, not onto the terrace")
        zp.check(c0 <= cpu.rd(cell_ptr(tx, tz)) & 31 < c0 + n, "the terrace tile not knocked down")
        zp.check(cpu.rd(bhp + 2 * 5 + 0) == 0, "its hit points not gone")
        hd = turn_from(cpu, r, 31, tz, 1, (45, tz))
        zp.check(hd == 1, f"heading {hd}, not onto the pad")
        zp.check(c0 <= cpu.rd(cell_ptr(32, tz)) & 31 < c0 + n, "the pad not knocked down")
        zp.check(cpu.rd(bhp + 12) == 0, "the pad's hit points not gone")
        zp.frames(cpu, 4)
        zp.check(cpu.rd(sym["game_over"]) == 0, "game over: the devil crushed the pad")
    finally:
        sd.close()


def test_charges_and_fires():
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        dist = 1024
        look_at(cpu, dist, 100)
        bx, bz = HX, HZ - 2                         # a tall building in the way
        cpu.wr(cell_ptr(bx, bz), 15)
        cpu.wr(cell_ptr(bx, bz) - sym["city_map"] + sym["city_col"], 4)
        ticks = sym["isr_ticks"]
        cpu.wr(r + sym["DV_EYES"], 0)               # (resting since 0: long enough)
        cpu.wr16(r + sym["DV_T0"], 0)
        cpu.wr16(ticks, 1000)
        zp.frames(cpu, 1)
        zp.check(cpu.rd(r + sym["DV_EYES"]) == 1, "not charging, the VTOL in range")
        cpu.wr16(ticks, 1000 + sym["DV_CHARGE_T"] // 2)
        zp.frames(cpu, 1)
        blue = cpu.palettes.get(1, {}).get(sym["DEVIL_EYE"], 0) & 7
        zp.check(blue == 4, f"half charged: its eyes' blue {blue}, not 4")
        zp.check(cpu.rd(sym["sfx3_req"]) != sym["SFX_CHARGE"], "whining before its last 3 s")
        cpu.wr16(ticks, 1000 + sym["DV_CHARGE_T"] - sym["DV_HUM_T"])
        zp.frames(cpu, 1)
        zp.check(cpu.rd(sym["sfx3_req"]) == sym["SFX_CHARGE"] and cpu.rd(sym["dv_hum"]) == 1,
                 "no charging whine for its last 3 s")
        cpu.wr(sym["sfx3_req"], 0)
        cpu.wr16(ticks, 1000 + sym["DV_CHARGE_T"] - 10)
        zp.frames(cpu, 1)
        zp.check(cpu.rd(sym["sfx3_req"]) == 0, "the whine asked for again")
        hp0 = cpu.rd(sym["vtol_hp"])
        cpu.wr(sym["speed"], 10)
        cpu.wr16(ticks, 1000 + sym["DV_CHARGE_T"])
        zp.frames(cpu, 1)
        # the building in the way takes it: it comes down, the VTOL is safe
        zp.check(cpu.rd(sym["bolt_hit"]) == 1, "the bolt not stopped by the building")
        zp.check(cpu.rd(sym["vtol_hp"]) == hp0, f"the VTOL hit through a building: {hp0} -> {cpu.rd(sym['vtol_hp'])}")
        zp.check(cpu.rd(sym["bolt_brake"]) == 0 and cpu.rd(sym["spin_t"]) == 0, "the VTOL thrown about behind cover")
        zp.check(cpu.rd(r + sym["DV_EYES"]) == 0, "still charging after the shot")
        zp.check(cpu.rd(sym["bolt_t"]) > 0, "no bolt")
        zp.check(cpu.rd(sym["sfx2_req"]) == sym["SFX_BOLT"], "no crackling zap")
        zp.check(cpu.rd(sym["dv_hum"]) == 0, "the whine still holding the splats off")
        zp.check(any(sym["BOLT_COL"] in row for row in shown(cpu)), "the bolt not drawn (to the building)")
        code = cpu.rd(cell_ptr(bx, bz)) & 31
        c0 = sym["COLLAPSE_CODE"]
        zp.check(c0 <= code < c0 + sym["COLLAPSE_N"], f"the building in the way not coming down: code {code}")
        parts = [i for i in range(sym["NPART"]) if cpu.rd(sym["particles"] + i * sym["PREC"])]
        zp.check(len(parts) >= 40, f"{len(parts)} particles")
        vx = [(cpu.rd(sym["particles"] + i * sym["PREC"] + 7) + 128) % 256 - 128 for i in parts]
        zp.check(max(map(abs, vx)) > 8, f"the burst not wide: x speeds {min(vx)}..{max(vx)}")
        # it comes down a metre every 2 frames, to rubble
        slot = code - c0
        h = spec16(cpu, sym["cl_h"] + 2 * slot)
        zp.frames(cpu, 4)
        h2 = spec16(cpu, sym["cl_h"] + 2 * slot)
        zp.check(h - h2 == 2 * (sym["HEIGHT_UNITS"] // 10), f"fell {h - h2} in 4 frames")
        zp.check(cpu.rd16(sym["htab"] + 2 * code) == h2, "its height not the one drawn")
        sp = cpu.page(sym["PAGE_SPECIAL"])
        a = sym["cl_h"] + 2 * slot - 0xC000
        sp[a], sp[a + 1] = (sym["RUBBLE_H"] + 20) & 255, 0
        zp.frames(cpu, 4)
        zp.check(cpu.rd(cell_ptr(bx, bz)) & 31 == sym["RUBBLE_CODE"], "not rubble")
        # cover gone: the next shot hits the VTOL, its speed halved
        cpu.wr(sym["speed"], 10)
        cpu.wr(r + sym["DV_EYES"], 1)
        cpu.wr16(r + sym["DV_T0"], 0)
        cpu.wr16(ticks, 5000)
        zp.frames(cpu, 1)
        zp.check(cpu.rd(sym["bolt_hit"]) == 0, "stopped by the rubble")
        zp.check(cpu.rd(sym["vtol_hp"]) == hp0 - sym["BOLT_DMG"],
                 f"VTOL {hp0} -> {cpu.rd(sym['vtol_hp'])} hit points")
        k = sym["PITCH_KICK"]
        zp.check(cpu.rd(sym["pitch"]) in (k, 256 - k), f"the nose not pitched {k}: {cpu.rd(sym['pitch'])}")
        zp.check(cpu.rd(sym["bolt_brake"]) == 1 and cpu.rd(sym["bolt_spd"]) == 5, "not braking to half (5)")
        zp.frames(cpu, sym["SPIN_FR"] + 1)
        sp_ = cpu.rd(sym["speed"])
        zp.check(cpu.rd(sym["spin_t"]) == 0, "still spinning")
        zp.check(cpu.rd(sym["bolt_brake"]) == 0 and 3 <= sp_ <= 5, f"speed {sp_}: not braked to about half of 10")
    finally:
        sd.close()


def test_spin():
    """7 to 44 degrees, either way"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        ticks = sym["isr_ticks"]
        turns = []
        for k in range(4):
            look_at(cpu, 1024, 100)
            cpu.wr(r + sym["DV_EYES"], 1)
            cpu.wr16(r + sym["DV_T0"], 0)
            cpu.wr16(ticks, 2000 + k)
            zp.frames(cpu, 1)
            y0 = cpu.rd(sym["yaw"])
            zp.frames(cpu, sym["SPIN_FR"] + 1)
            d = (cpu.rd(sym["yaw"]) - y0 + 128) % 256 - 128
            turns.append(d)
            cpu.wr(sym["vtol_hp"], 50)
        zp.note(f"turns (256 a circle): {turns}")
        zp.check(all(4 <= abs(d) <= 32 for d in turns), f"turns {turns}")
    finally:
        sd.close()


def test_sky_bolt_drawn():
    """Out of range, seen from afar: the bolt goes up from its eyes"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        look_at(cpu, 2100, 300)                     # (beyond DV_RANGE, in the draw distance)
        cpu.wr(r + 7, 1)
        cpu.wr(r + sym["DV_EYES"], 1)
        cpu.wr16(r + sym["DV_T0"], 0)
        cpu.wr16(sym["isr_ticks"], sym["DV_CHARGE_T"] + 5)
        zp.frames(cpu, 1)
        zp.check(cpu.rd(sym["bolt_up"]) == 1, "not fired up")
        rows = [y for y, row in enumerate(shown(cpu)) if sym["BOLT_COL"] in row]
        ey = cpu.page(sym["PAGE_CITY2"])[sym["dv_ey"] - 0x8000]     # (its eyes' row)
        zp.check(rows and min(rows) == 0 and max(rows) <= ey + 1,
                 f"the bolt not from its eyes (row {ey}) up: rows {rows[0]}..{rows[-1]}")
    finally:
        sd.close()


def test_out_of_range():
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        zp.set_camera(cpu, 32 * 256 << 8, 32 * 256 << 8, 60)     # (the pad: 20 tiles off)
        ticks = sym["isr_ticks"]
        cpu.wr(r + sym["DV_EYES"], 0)
        cpu.wr16(r + sym["DV_T0"], 0)
        cpu.wr16(ticks, 5000)
        zp.frames(cpu, 1)
        zp.check(cpu.rd(r + sym["DV_EYES"]) & 1, "not charging out of range")
        hp0 = cpu.rd(sym["vtol_hp"])
        cpu.wr16(ticks, 5000 + sym["DV_CHARGE_T"])
        zp.frames(cpu, 1)
        zp.check(cpu.rd(sym["bolt_t"]) > 0 and cpu.rd(sym["bolt_up"]) == 1, "no bolt into the sky")
        zp.check(cpu.rd(sym["sfx2_req"]) == sym["SFX_BOLT"], "no crackling zap")
        zp.check(cpu.rd(sym["vtol_hp"]) == hp0 and cpu.rd(sym["spin_t"]) == 0, "the VTOL hit out of range")
        zp.check(cpu.rd(r + sym["DV_EYES"]) == 0, "not resting after it")
        cpu.wr16(ticks, 5000 + sym["DV_CHARGE_T"] + sym["DV_REST_T"])
        zp.frames(cpu, 1)
        zp.check(cpu.rd(r + sym["DV_EYES"]) & 1, "not charging again")
    finally:
        sd.close()


def drop(cpu, kind, x, z, y):
    """A round of this kind at (x, y, z), bursting next frame"""
    B = FB0
    for f, v in (("B_X", x), ("B_Y", y), ("B_Z", z), ("B_PX", x), ("B_PY", y + 2), ("B_PZ", z),
                 ("B_SIN", 0), ("B_COS", 256), ("B_SLOPE", -256 & 65535), ("B_S", 20), ("B_TDX", 0)):
        cpu.wr16(B + sym[f], v)
    cpu.wr(B + sym["B_KIND"], kind)
    cpu.wr(B + sym["B_DMG"], 0)
    cpu.wr(B + sym["B_TGT"], 14)
    cpu.wr(B + sym["B_STATE"], 1)


def test_killed():
    """A rocket at its chest: hurt; at 0 it sinks into the ground and goes"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        zp.set_camera(cpu, 32 * 256 << 8, 30 * 256 << 8, 60, yaw=128)
        cpu.wr16(r + 11, 0)
        cpu.wr(r + 7, 1)                            # (holding still)
        x, z = cpu.rd16(r), cpu.rd16(r + 2)
        drop(cpu, sym["BK_ROCKET"], x + 60, z, 300)  # (beside it: in its box)
        zp.frames(cpu, 2)
        zp.check(hp(cpu, r) == sym["DEVIL_HP"] - sym["BLAST_DMG"], f"{hp(cpu, r)} hit points after a rocket")
        cpu.wr(r + 18, 5)
        cpu.wr(r + sym["LICH_HP_HI"], 0)
        drop(cpu, sym["BK_ROCKET"], x - 60, z, 300)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(r + 16) == sym["GM_DYING"], "not dying")
        zp.check(cpu.rd16(r + 21) >= 32768, "not sinking")
        cpu.wr(r + 17, 2)
        zp.frames(cpu, 2)
        zp.check(not cpu.rd(r + 10) & 1, "still there")
    finally:
        sd.close()


def test_death_ends_the_game():
    """Killed: every other monster dies at once; when it has sunk, the level
    and the game are complete (the congratulations)"""
    sd, cpu = devil_game()
    try:
        ds = devils(cpu)
        r = ds[0]
        others = [rec(i) for i in range(NMON) if cpu.rd(rec(i) + 10) & 1 and rec(i) != r]
        zp.check(len(others) >= 10, f"only {len(others)} other monsters in its wave")
        zp.set_camera(cpu, 32 * 256 << 8, 30 * 256 << 8, 60, yaw=128)
        cpu.wr(r + 7, 1)
        cpu.wr(r + 18, 5)
        cpu.wr(r + sym["LICH_HP_HI"], 0)
        x, z = cpu.rd16(r), cpu.rd16(r + 2)
        drop(cpu, sym["BK_ROCKET"], x + 60, z, 300)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(r + 16) == sym["GM_DYING"], "not dying")
        alive = [a for a in others if cpu.rd(a + 10) & 1]
        zp.check(not alive, f"{len(alive)} monsters still alive with it dying")
        zp.check(cpu.rd(sym["level_done"]) == 0, "the level over before it has sunk")
        zp.run_until(cpu, lambda: cpu.pc == sym["game_complete_screen"] and cpu.mmu[6] == sym["PAGE_MENU"],
                     "the congratulations", limit=200 * zp.FRAME_T)
    finally:
        sd.close()


def test_congratulations_not_shaken():
    """The level over mid-shake (the devil's footfalls, a wreck): the
    congratulations screen is shown with Layer 2's scroll back at 0"""
    sd, cpu = devil_game()
    try:
        cpu.wr(sym["level_done"], 1)
        zp.run_until(cpu, lambda: cpu.pc == sym["level_complete_screen"]
                     and cpu.mmu[6] == sym["PAGE_LEVELEND"], "the level's end")
        cpu.set_nextreg(0x16, 255)                  # (shake_xy's, mid-shake)
        cpu.set_nextreg(0x17, 191)
        cpu.wr(sym["shake_t"], 3)
        zp.run_until(cpu, lambda: cpu.pc == sym["space_wait"] and cpu.mmu[6] == sym["PAGE_MENU"],
                     "the congratulations", limit=40 * zp.FRAME_T)
        sc = (cpu.nextreg.get(0x16), cpu.nextreg.get(0x17))
        zp.check(sc == (0, 0), f"Layer 2 scrolled {sc} on the congratulations")
        zp.check(cpu.rd(sym["shake_t"]) == 0, "still shaking")
    finally:
        sd.close()


def test_graphics_back():
    """The next game's level: the figures' own pages back from SPRITES.ZPG"""
    sd, cpu = devil_game()
    try:
        cpu.wr(sym["game_over"], 1)
        zp.run_until(cpu, lambda: cpu.pc == sym["game_over_screen"], "the GAME OVER screen")
        cpu.keys = {" "}
        zp.run_until(cpu, lambda: cpu.pc == sym["main_menu"] and cpu.mmu[6] == sym["PAGE_MAINMENU"],
                     "the main menu", limit=40 * zp.FRAME_T)
        cpu.keys = set()
        zp.start_game(cpu, 1)
        zp.frames(cpu, 2)                           # (PREPARE FOR COMBAT after the first)
        zp.check(cpu.rd(sym["devil_gfx"]) == 0, "the devil's graphics still in")
        data = open(sd.path("SPRITES.ZPG"), "rb").read()
        h, n = sym["GFX_HEADER"], data[5]
        bad = [p for p in range(n) if bytes(cpu.page(sym["PAGE_GFX0"] + p)) != data[h + 8192 * p:h + 8192 * (p + 1)]]
        zp.check(not bad, f"pages {bad} not the figures' again")
    finally:
        sd.close()


def test_devil_file():
    """ZPDATA/DEVIL.ZPB is sprites/devil.json's"""
    built = open(os.path.join(zp.ROOT, "ZPDATA", "DEVIL.ZPB"), "rb").read()
    d = sf.load(sf.devil_path())
    zp.check(not sf.devil_problems(d), "; ".join(sf.devil_problems(d)))
    zp.check(sf.devil_file(d) == built, "ZPDATA/DEVIL.ZPB is out of date: run build.bat")



def call(cpu, addr, c=0, d=0, e=0):
    """Call a routine with C, D, E set, until it returns"""
    pc0, sp0 = cpu.pc, cpu.sp
    cpu.push(pc0)
    cpu.r[1], cpu.r[2], cpu.r[3] = c, d, e
    cpu.pc = addr
    zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, f"${addr:04X} to return", limit=2_000_000)


def test_base_on_the_last_level():
    """Level 50: the pad destroyed (zombies) is no game over; level 1 it is"""
    sd, cpu = devil_game()
    try:
        call(cpu, sym["base_damage"], c=255, d=sym["PAD_Z"], e=sym["PAD_X"])
        zp.check(cpu.rd(sym["game_over"]) == 0, "level 50: the pad destroyed ended the game")
    finally:
        sd.close()
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu, 1)
        call(cpu, sym["base_damage"], c=255, d=sym["PAD_Z"], e=sym["PAD_X"])
        zp.check(cpu.rd(sym["game_over"]) == 1, "level 1: the pad destroyed, no game over")


def test_chain_spark():
    """A chain gun round's hit: one spark, gone in SPARK_LIFE frames"""
    sd, cpu = devil_game()
    try:
        only_devil(cpu)
        zp.set_camera(cpu, 32 * 256 << 8, 30 * 256 << 8, 60, yaw=128)
        for i in range(sym["NPART"]):
            cpu.wr(sym["particles"] + i * sym["PREC"], 0)
        drop(cpu, 0, 40 * 256, 40 * 256, 3)
        cpu.wr(FB0 + sym["B_DMG"], sym["CHAIN_DMG"])
        zp.frames(cpu, 1)
        live = [i for i in range(sym["NPART"]) if cpu.rd(sym["particles"] + i * sym["PREC"])]
        zp.check(len(live) == 1, f"{len(live)} particles from a chain gun's hit, not 1")
        zp.check(cpu.rd(sym["particles"] + live[0] * sym["PREC"] + 11) == sym["SPARK_LIFE"], "not a quick spark")
    finally:
        sd.close()


def test_darkens():
    """Every DV_DARK_HP hit points off it: the normal palette a step darker
    (not its eyes); and its hit points on the HUD (debug)"""
    sd, cpu = devil_game()
    try:
        r = only_devil(cpu)
        look_at(cpu, 1024, 100)
        hp = sym["DEVIL_HP"] - 2 * sym["DV_DARK_HP"] - 50        # (two steps)
        cpu.wr(r + 18, hp & 255)
        cpu.wr(r + sym["LICH_HP_HI"], hp >> 8)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(sym["dv_dark"]) == 2, f"darkness {cpu.rd(sym['dv_dark'])}, not 2")
        data = open(sd.path("LEVEL50.ZPV"), "rb").read()
        def rgb(i):
            a, lo = data[8 + 2 * i], data[9 + 2 * i]
            return a >> 5, (a >> 2) & 7, ((a & 3) << 1) | (lo & 1)
        def pal(i):
            v = cpu.palettes.get(1, {}).get(i, 0)
            return v >> 6, (v >> 3) & 7, v & 7
        for i in (sym["DEVIL_COL0"], sym["SKY_COL"], 100):
            want = tuple(max(0, c - 2) for c in rgb(i))
            zp.check(pal(i) == want, f"entry {i}: {pal(i)}, not {want}")
        # the HUD: its hit points, in red after the integrity
        zp.check(cpu.rd16(sym["dhp_shown"]) == hp, f"the HUD shows {cpu.rd16(sym['dhp_shown'])}, not {hp}")
        ula = cpu.page(sym["PAGE_ULA0"])
        a = 0x1800 + (sym["INT_ROW"] + 1) * 32 + sym["DHP_COL"]
        zp.check(ula[a] & 7 == sym["C_WARN"], "its hit points not in red")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
