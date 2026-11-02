"""The humans waiting to be rescued: standing while the VTOL is far off and
waving when it is near (WAVE_R); on the road, running from a monster that
comes within FLEE_R, along the road and away from it; on a roof, never.
"""
import zptest as zp
from zptest import sym

HREC = sym["HREC"]
GRID = 64


def humans(cpu):
    return [sym["humans"] + k * HREC for k in range(sym["HUMAN_MAX"])]


def waiting(cpu):
    return [a for a in humans(cpu) if cpu.rd(a + 6) == sym["HS_WAIT"]]


def code(cpu, x, z):
    return cpu.rd(sym["city_map"] + z * GRID + x) & sym["CELL_CODE"]


def crossroads(cpu):
    """A road cell with road all round it (3x3), away from the edge."""
    for z in range(4, GRID - 4):
        for x in range(4, GRID - 4):
            if all(code(cpu, x + i, z + j) == 0 for i in (-1, 0, 1) for j in (-1, 0, 1)):
                return x, z
    raise AssertionError("no open crossroads on level 1")


def game():
    """Level 1, with one monster: record 0 (kept, so the wave isn't over),
    moved by the tests that use it, else parked far off."""
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)
    for z in range(1, sym["NMON"]):
        cpu.wr(sym["zombies"] + z * sym["ZREC"] + 10, 0)
    zm = sym["zombies"]
    cpu.wr(zm + 10, 1)
    cpu.wr(zm + 7, 250)                         # standing still
    return sd, cpu


def place(cpu, a, x, z, y=0):
    cpu.wr16(a, x); cpu.wr16(a + 2, z); cpu.wr16(a + 4, y)
    cpu.wr(a + 14, 0)


def far_camera(cpu, x, z):
    """The VTOL hovering well beyond WAVE_R of (x, z) (world units)."""
    zp.set_camera(cpu, (x + 6 * 256) << 8, (z + 6 * 256) << 8, 100)


def test_stand_and_wave():
    sd, cpu = game()
    try:
        a = waiting(cpu)[0]
        x, z = cpu.rd16(a), cpu.rd16(a + 2)
        zm = sym["zombies"]                     # the monster far off
        cpu.wr16(zm, x + 8 * 256 & 0x3FFF); cpu.wr16(zm + 2, z + 8 * 256 & 0x3FFF)
        far_camera(cpu, x, z)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(a + 13) == 0, f"VTOL far off: drawn as {cpu.rd(a + 13)}, not standing (0)")
        zp.set_camera(cpu, (x + 2 * 256) << 8, (z - 256) << 8, 100)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(a + 13) == sym["HUM_WAVING"],
                 f"VTOL near: drawn as {cpu.rd(a + 13)}, not waving ({sym['HUM_WAVING']})")
    finally:
        sd.close()


def test_flee_on_road():
    sd, cpu = game()
    try:
        cx, cz = crossroads(cpu)
        a = humans(cpu)[0]
        cpu.wr(a + 6, sym["HS_WAIT"])
        hx, hz = cx * 256 + 128, cz * 256 + 128
        place(cpu, a, hx, hz)
        zm = sym["zombies"]                    # a zombie 80 units to its west, standing
        cpu.wr16(zm, hx - 80); cpu.wr16(zm + 2, hz); cpu.wr(zm + 10, 1); cpu.wr(zm + 7, 250)
        far_camera(cpu, hx, hz)
        ways = set()
        for _ in range(sym["FLEE_EVERY"] + sym["FLEE_TIME"] // 2):
            zp.frames(cpu, 1)
            ways.add(cpu.rd(a + 13))
        nx, nz = cpu.rd16(a), cpu.rd16(a + 2)
        zp.check((nx, nz) != (hx, hz), "didn't move")
        zp.check(cpu.rd(a + 15) in (1, 2), f"fled way {cpu.rd(a + 15)}: not +z or +x (away from the west)")
        zx, zz = cpu.rd16(zm), cpu.rd16(zm + 2)
        zp.check((nx - zx) ** 2 + (nz - zz) ** 2 > 80 ** 2, "not farther from the zombie")
        zp.check(code(cpu, nx >> 8, nz >> 8) == 0, f"ran off the road, to cell {nx >> 8},{nz >> 8}")
        zp.check(ways & {1, 2}, f"not drawn running (+13 seen: {sorted(ways)})")
        zp.note(f"fled way {cpu.rd(a + 15)}: ({hx},{hz}) -> ({nx},{nz})")
    finally:
        sd.close()


def test_blocked_way():
    """Against a building on one side: only the open way is taken."""
    sd, cpu = game()
    try:
        cx, cz = None, None
        for z in range(4, GRID - 4):
            for x in range(4, GRID - 4):
                if (code(cpu, x, z) == 0 and code(cpu, x + 1, z) == 0 and code(cpu, x - 1, z) == 0
                        and code(cpu, x, z + 1) != 0 and sym["PAD_CODE"] > code(cpu, x, z + 1)):
                    cx, cz = x, z
                    break
            if cx is not None:
                break
        zp.check(cx is not None, "no road cell with a building north of it")
        a = humans(cpu)[0]
        cpu.wr(a + 6, sym["HS_WAIT"])
        hx, hz = cx * 256 + 128, cz * 256 + 250        # by the building to the north
        place(cpu, a, hx, hz)
        zm = sym["zombies"]                             # south-west of it: away is +x or +z
        cpu.wr16(zm, hx - 60); cpu.wr16(zm + 2, hz - 60); cpu.wr(zm + 10, 1); cpu.wr(zm + 7, 250)
        far_camera(cpu, hx, hz)
        zp.frames(cpu, sym["FLEE_EVERY"] + 2)
        zp.check(cpu.rd(a + 15) == 2 and cpu.rd16(a) > hx, f"took way {cpu.rd(a + 15)}, not +x (north blocked)")
        zp.check(cpu.rd16(a + 2) >> 8 == cz, "ran into the building")
    finally:
        sd.close()


def test_no_flee_on_roof():
    sd, cpu = game()
    try:
        roof = next((a for a in waiting(cpu) if cpu.rd16(a + 4)), None)
        if roof is None:                        # put one on a roof
            roof = waiting(cpu)[0]
            x, z = next((x, z) for z in range(4, GRID - 4) for x in range(4, GRID - 4)
                        if 0 < code(cpu, x, z) < sym["PAD_CODE"])
            place(cpu, roof, x * 256 + 128, z * 256 + 128, 20)
        x, z = cpu.rd16(roof), cpu.rd16(roof + 2)
        zm = sym["zombies"]
        cpu.wr16(zm, x - 50); cpu.wr16(zm + 2, z); cpu.wr(zm + 10, 1); cpu.wr(zm + 7, 250)
        far_camera(cpu, x, z)
        zp.frames(cpu, sym["FLEE_EVERY"] + 4)
        zp.check((cpu.rd16(roof), cpu.rd16(roof + 2)) == (x, z) and cpu.rd(roof + 14) == 0,
                 "a human on a roof fled")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
