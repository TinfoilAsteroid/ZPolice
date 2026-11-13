"""The lich, a city's boss: in the last wave of each city's last level, harder
in each later city; it walks at 4 times a zombie's speed, and shoots fireballs
at where the VTOL will be, in range.  A fireball passes through monsters and
bursts at a building, the ground, the VTOL or at the end of its flight, for 10
within 5 m on each axis to the VTOL, humans and the base, not to monsters.
"""
import math

import zptest as zp
from zptest import sym

ZREC, NZOMB, NMON = sym["ZREC"], sym["NZOMB"], sym["NMON"]
FB0 = sym["bullets"] + (sym["NBULLETS"] - sym["NFIRE"]) * sym["BREC"]   # fireball records


def s16(v):
    return v - 65536 if v > 32767 else v


def rec(i):
    return sym["zombies"] + i * ZREC


def liches(cpu):
    return [rec(i) for i in range(NZOMB, NMON)
            if cpu.rd(rec(i) + 10) & 1 and cpu.rd(rec(i) + 15) == sym["ZT_LICH"]]


def hp(cpu, r):
    return cpu.rd(r + 18) + 256 * cpu.rd(r + sym["LICH_HP_HI"])


def game(level=5):
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, level)
    return sd, cpu


def only_lich(cpu):
    """Everything but the lich gone, and it holding still."""
    r = liches(cpu)[0]
    for i in range(NMON):
        if rec(i) != r:
            cpu.wr(rec(i) + 10, 0)
    cpu.wr(r + 7, 200)                  # standing still
    return r


def cam(cpu, x, z, y, **k):
    zp.set_camera(cpu, x * 256, z * 256, y, **k)     # (world units)


def place(cpu, r, x, z):
    cpu.wr16(r + 0, x)
    cpu.wr16(r + 2, z)


def fireballs(cpu):
    return [b for b in (FB0, FB0 + sym["BREC"]) if cpu.rd(b + sym["B_STATE"]) & 127 == 1]


def drop(cpu, kind, x, z, y=2):
    """A round of this kind just above the ground: it bursts next frame."""
    B = FB0
    for f, v in (("B_X", x), ("B_Y", y), ("B_Z", z), ("B_PX", x), ("B_PY", y), ("B_PZ", z),
                 ("B_SIN", 0), ("B_COS", 256), ("B_SLOPE", -256 & 65535), ("B_S", 20), ("B_TDX", 0)):
        cpu.wr16(B + sym[f], v)
    cpu.wr(B + sym["B_KIND"], kind)
    cpu.wr(B + sym["B_DMG"], 0)
    cpu.wr(B + sym["B_TGT"], 14)
    cpu.wr(B + sym["B_STATE"], 1)


def test_spawns_in_the_last_wave():
    sd, cpu = game(5)                   # city 1: one wave
    try:
        zp.check(len(liches(cpu)) == 1, "no lich on level 5")
        r = liches(cpu)[0]
        zp.check(hp(cpu, r) == 25, f"city 1: {hp(cpu, r)} hit points, not 25")
        zp.check(cpu.rd(r + sym["LICH_FRAMES"]) == 150, "city 1: not 150 frames a shot")
    finally:
        sd.close()
    sd, cpu = game(4)
    try:
        zp.check(not liches(cpu), "a lich before the city's last level")
    finally:
        sd.close()
    for lv, h, rate in ((10, 30, 145), (45, 65, 110)):     # (level 50's last: the devil)
        sd, cpu = game(lv)
        try:
            zp.check(not liches(cpu), f"level {lv}: a lich before the last wave")
            cpu.wr(sym["wave_number"], cpu.rd(sym["level_cur"] + sym["LV_WAVES"]) - 1)
            for i in range(NMON):
                cpu.wr(rec(i) + 10, 0)
            zp.frames(cpu, 2)
            zp.check(len(liches(cpu)) == 1, f"level {lv}: no lich in the last wave")
            r = liches(cpu)[0]
            zp.check(hp(cpu, r) == h, f"level {lv}: {hp(cpu, r)} hit points, not {h}")
            zp.check(cpu.rd(r + sym["LICH_FRAMES"]) == rate, f"level {lv}: not {rate} frames a shot")
        finally:
            sd.close()


def test_walks_at_four_times():
    sd, cpu = game(5)
    try:
        r = only_lich(cpu)
        cpu.wr(r + 7, 0)                # walking,
        cpu.wr(r + 11, 100)             # no decisions for a while
        cpu.wr(r + 16, 0)
        cpu.wr(r + 4, 1)                # along +x
        cpu.wr(r + sym["LICH_WAIT"], 200)
        x0, n = cpu.rd16(r), 16
        zp.frames(cpu, n)
        want = 4 * cpu.rd(sym["zspeed"]) / 16 * n
        got = cpu.rd16(r) - x0
        zp.check(abs(got - want) <= 2, f"{n} frames: {got} units, not {want:.0f}")
    finally:
        sd.close()


def test_range():
    sd, cpu = game(5)
    try:
        r = only_lich(cpu)
        y = sym["MAX_Y"]
        cam(cpu, 32 * 256, 32 * 256, y)
        place(cpu, r, (32 - 11) * 256, 32 * 256)    # 220 m away
        cpu.wr(r + sym["LICH_WAIT"], 0)
        zp.frames(cpu, 2)
        zp.check(not fireballs(cpu) and cpu.rd(r + sym["LICH_WAIT"]) == 0, "fired out of range")
        place(cpu, r, (32 - 9) * 256, 32 * 256)     # 180 m
        zp.frames(cpu, 1)
        zp.check(cpu.rd(r + sym["LICH_WAIT"]) == cpu.rd(r + sym["LICH_FRAMES"]) - 1, "didn't fire in range (its reload)")
    finally:
        sd.close()


def test_aims_ahead():
    """Lateral motion at 20 units a frame, 1000 units away: aimed straight at
    the VTOL it would be 6 degrees behind."""
    sd, cpu = game(5)
    errs = []
    spd = 20
    try:
        r = only_lich(cpu)
        place(cpu, r, (32 - 4) * 256, 32 * 256)
        y = sym["MAX_Y"]
        for k in range(10):
            cam(cpu, 32 * 256, 32 * 256, y, yaw=0, speed=spd)     # flying +z
            cpu.wr(r + sym["LICH_WAIT"], 2)
            cpu.wr(FB0 + sym["B_STATE"], 0)
            cpu.wr(FB0 + sym["BREC"] + sym["B_STATE"], 0)
            zp.frames(cpu, 3)
            fb = [b for b in (FB0, FB0 + sym["BREC"]) if cpu.rd(b + sym["B_STATE"])]
            zp.check(fb, "no fireball")
            b = fb[0]
            sn, cs = s16(cpu.rd16(b + sym["B_SIN"])), s16(cpu.rd16(b + sym["B_COS"]))
            cx, cz = cpu.rd16(sym["cam_x"] + 1), cpu.rd16(sym["cam_z"] + 1)
            lx, lz = cpu.rd16(r), cpu.rd16(r + 2)
            t = math.hypot(cx - lx, cz - lz) / sym["FB_STEP"]
            for _ in range(3):
                t = math.hypot(cx - lx, cz + spd * t - lz) / sym["FB_STEP"]
            ideal = math.degrees(math.atan2(cx - lx, cz + spd * t - lz))
            errs.append(math.degrees(math.atan2(sn, cs)) - ideal)
        mean = sum(errs) / len(errs)
        zp.note(f"aim error: mean {mean:.1f}, from {min(errs):.1f} to {max(errs):.1f} degrees")
        zp.check(abs(mean) < 1.5, f"the aim is {mean:.1f} degrees off on average")
        zp.check(max(map(abs, errs)) < 3, f"an aim {max(map(abs, errs)):.1f} degrees off")
        zp.check(max(errs) - min(errs) > 0.5, "no variance in the aim")
    finally:
        sd.close()


def test_flight_ends_in_the_air():
    sd, cpu = game(5)
    try:
        r = only_lich(cpu)
        cpu.wr(r + sym["LICH_WAIT"], 200)
        B, x0 = FB0, 8 * 256
        drop(cpu, sym["BK_FIREBALL"], x0, 32 * 256, y=2000)
        cpu.wr16(B + sym["B_SIN"], 256)
        cpu.wr16(B + sym["B_COS"], 0)
        cpu.wr16(B + sym["B_SLOPE"], 0)
        cpu.wr16(B + sym["B_S"], sym["FB_STEP"])
        cpu.wr(B + sym["B_TGT"], sym["FB_FRAMES"])
        n = 0
        while cpu.rd(B + sym["B_STATE"]) == 1 and n < 30:
            zp.frames(cpu, 1)
            n += 1
        d = cpu.rd16(B + sym["B_X"]) - x0
        zp.check(n == sym["FB_FRAMES"], f"flew {n} frames, not {sym['FB_FRAMES']}")
        zp.check(abs(d - 2560) < 30, f"flew {d} units, not 2560 (200 m)")
        zp.check(cpu.rd(B + sym["B_STATE"]) == 2, "no burst at the end of its flight")
    finally:
        sd.close()


def test_hits_the_vtol():
    sd, cpu = game(5)
    try:
        r = only_lich(cpu)
        cpu.wr(r + 0, 128)                  # the middle of its street cell,
        cpu.wr(r + 2, 128)
        cam(cpu, cpu.rd16(r) + 50, cpu.rd16(r + 2), 70)     # the VTOL just along it
        hp0 = cpu.rd(sym["vtol_hp"])
        cpu.wr(r + sym["LICH_WAIT"], 0)
        zp.frames(cpu, 4)
        zp.check(cpu.rd(sym["vtol_hp"]) == hp0 - 10, f"VTOL {hp0} -> {cpu.rd(sym['vtol_hp'])}, not -10")
    finally:
        sd.close()


def test_burst():
    """FB_DMG to the VTOL and the base, and a human, nothing to monsters."""
    sd, cpu = game(5)
    try:
        r = only_lich(cpu)
        cpu.wr(r + sym["LICH_WAIT"], 200)
        x, z = cpu.rd16(sym["cam_x"] + 1) + 256, cpu.rd16(sym["cam_z"] + 1)     # by the pad
        place(cpu, r, x + 10, z)
        cpu.wr16(rec(0) + 0, x - 10)        # a zombie beside it
        cpu.wr16(rec(0) + 2, z)
        cpu.wr(rec(0) + 10, 1)
        cpu.wr(rec(0) + 18, 5)
        cpu.wr(rec(0) + 7, 200)
        cpu.wr(rec(0) + 15, 0)
        h = sym["humans"]
        cpu.wr16(h + 0, x)
        cpu.wr16(h + 2, z + 20)
        cpu.wr16(h + 4, 0)
        cpu.wr(h + 6, sym["HS_WAIT"])
        cpu.wr(h + 10, 10)                 # (10 hit points: FB_DMG kills)
        cam(cpu, x - 20, z, 40)
        hp0, l0 = cpu.rd(sym["vtol_hp"]), hp(cpu, r)
        n = (2 * sym["TERRACE_R"] + 1) ** 2
        b0 = [cpu.rd(sym["base_hp"] + i) for i in range(n)]
        drop(cpu, sym["BK_FIREBALL"], x, z)
        zp.frames(cpu, 2)
        b1 = [cpu.rd(sym["base_hp"] + i) for i in range(n)]
        zp.check(cpu.rd(sym["vtol_hp"]) == hp0 - 10, f"VTOL {hp0} -> {cpu.rd(sym['vtol_hp'])}")
        zp.check(cpu.rd(rec(0) + 18) == 5 and cpu.rd(rec(0) + 10) & 1, "the zombie was hurt")
        zp.check(hp(cpu, r) == l0, "the lich was hurt")
        zp.check(cpu.rd(h + 6) == sym["HS_DEAD"], "the human lived")
        zp.check(sum(b1) < sum(b0), "the base wasn't damaged")
    finally:
        sd.close()


def test_big_hit_points_and_box():
    sd, cpu = game(5)
    try:
        r = only_lich(cpu)
        cpu.wr(r + sym["LICH_WAIT"], 200)
        cpu.wr(rec(0) + 10, 1)              # (a zombie left: the level goes on)
        cpu.wr(rec(0) + 7, 200)
        cpu.wr(r + 18, 19)                  # 275: over 8 bits
        cpu.wr(r + sym["LICH_HP_HI"], 1)
        x, z = cpu.rd16(r), cpu.rd16(r + 2)
        drop(cpu, sym["BK_ROCKET"], x, z)
        zp.frames(cpu, 2)
        zp.check(hp(cpu, r) == 255, f"275 - 20 = {hp(cpu, r)}")
        zp.check(cpu.rd(r + 10) & 1, "killed by a rocket")
        cpu.wr(r + 18, 5)                   # a round at 3 m: over a zombie's head
        cpu.wr(r + sym["LICH_HP_HI"], 0)
        B = sym["bullets"]
        cpu.wr(r + 0, 128)
        cpu.wr(r + 2, 128)
        x, z = cpu.rd16(r), cpu.rd16(r + 2)
        zp.frames(cpu, 1)
        for f, v in (("B_X", x - 20), ("B_Y", 40), ("B_Z", z), ("B_PX", x - 20), ("B_PY", 40), ("B_PZ", z),
                     ("B_SIN", 256), ("B_COS", 0), ("B_SLOPE", 0), ("B_S", 40), ("B_TDX", 0)):
            cpu.wr16(B + sym[f], v)
        cpu.wr(B + sym["B_KIND"], 0)
        cpu.wr(B + sym["B_DMG"], 4)
        cpu.wr(B + sym["B_STATE"], 1)
        zp.frames(cpu, 1)
        zp.check(hp(cpu, r) == 1, f"a round at its head: {hp(cpu, r)} hit points left, not 1")
        cpu.wr(B + sym["B_STATE"], 0)
        drop(cpu, sym["BK_ROCKET"], x, z)
        zp.frames(cpu, 2)
        zp.check(not cpu.rd(r + 10) & 1, "not killed at 0 hit points")
    finally:
        sd.close()


def test_forty_zombies_and_the_lich():
    """A full wave of zombies leaves the specials their own records."""
    sd, cpu = game(10)
    try:
        cpu.wr(sym["level_cur"] + sym["LV_ZOMBIES"], 40)
        for i in range(NMON):
            cpu.wr(rec(i) + 10, 0)
        zp.frames(cpu, 2)
        n = sum(cpu.rd(rec(i) + 10) & 1 for i in range(NZOMB))
        zp.check(n == 40, f"{n} zombies in the wave, not 40")
        zp.check(len(liches(cpu)) == 1, "no lich with a full wave")
        zp.frames(cpu, 4)
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
