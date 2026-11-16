"""Zombie decisions, one record a frame (zdec_i, zombie.asm), and the step
check between them: a step that would take a zombie within ZMARGIN of a
building (or the map's edge) isn't taken; it stops and turns 90 degrees,
left or right at random.  A base tile there: it goes for it.
"""
import zptest as zp
from zptest import sym

ZREC, NMON = sym["ZREC"], sym["NMON"]
CM, GRID = sym["city_map"], sym["GRID"]
MARGIN = sym["ZMARGIN"]
NORTH = 0                               # heading 0: +z (zdir_step)


def rec(i):
    return sym["zombies"] + i * ZREC


def code(cpu, x, z):
    return cpu.rd(CM + z * GRID + x) & sym["CELL_CODE"]


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, 1)
    zp.frames(cpu, 2)
    return sd, cpu


def only_zombie(cpu, x, z, heading, cx=128, cz=128):
    """Every record off but zombie 0, at (cx, cz) in cell (x, z), walking
    heading; its decision as far away as it can be"""
    for i in range(NMON):
        cpu.wr(rec(i) + 10, cpu.rd(rec(i) + 10) & ~1)
    r = rec(0)
    cpu.wr(r + 10, cpu.rd(r + 10) | 1)
    cpu.wr16(r, x * 256 + cx)
    cpu.wr16(r + 2, z * 256 + cz)
    cpu.wr(r + 4, heading)
    for o in (6, 7, 16):                # no fraction, not waiting or attacking
        cpu.wr(r + o, 0)
    cpu.wr(r + 15, 0)                   # (a plain zombie: ZT 0)
    cpu.wr(sym["zdec_i"], 0)            # (record 0 decided last frame:
    return r                            #  the next in NMON frames)


def find_cell(cpu, ahead):
    """A road cell whose neighbour to the north (+z) satisfies ahead(code),
    with road to its south (room to come from)"""
    for z in range(2, GRID - 3):
        for x in range(2, GRID - 2):
            if code(cpu, x, z) == 0 and code(cpu, x, z - 1) == 0 and ahead(code(cpu, x, z + 1)):
                return x, z
    raise AssertionError("no such cell")


def test_one_a_frame():
    """zdec_i moves on one record a frame, round after NMON - 1"""
    sd, cpu = game()
    try:
        cpu.wr(sym["zdec_i"], NMON - 3)
        seen = []
        for _ in range(4):
            zp.frames(cpu, 1)
            seen.append(cpu.rd(sym["zdec_i"]))
        zp.check(seen == [NMON - 2, NMON - 1, 0, 1], f"zdec_i went {seen}")
    finally:
        sd.close()


def test_stops_at_a_building():
    """Walking at a building between decisions: it never comes within
    ZMARGIN of it, and turns 90 degrees"""
    sd, cpu = game()
    try:
        bld = lambda c: 1 <= c < sym["PAD_CODE"]
        x, z = find_cell(cpu, bld)
        edge = (z + 1) * 256
        r = only_zombie(cpu, x, z, NORTH, cz=256 - MARGIN - 6)    # a few steps away
        turned = None
        for f in range(30):                                       # (before its decision)
            zp.frames(cpu, 1)
            zz = cpu.rd16(r + 2)
            zp.check(zz <= edge - MARGIN, f"frame {f}: z {zz}, within {edge - zz} of the wall")
            if cpu.rd(r + 4) != NORTH:
                turned = cpu.rd(r + 4)
                break
        zp.check(turned in (1, 3), f"heading {turned}: not turned 90 degrees")
        zp.check(cpu.rd(r + 7) == 0, "standing still (a dead end's wait), not a turn")
    finally:
        sd.close()


def test_turns_either_way():
    """The turn is left or right at random: both happen"""
    sd, cpu = game()
    try:
        x, z = find_cell(cpu, lambda c: 1 <= c < sym["PAD_CODE"])
        ways = set()
        for _ in range(12):
            r = only_zombie(cpu, x, z, NORTH, cz=256 - MARGIN - 1)
            for _ in range(10):
                zp.frames(cpu, 1)
                if cpu.rd(r + 4) != NORTH:
                    ways.add(cpu.rd(r + 4))
                    break
            if ways == {1, 3}:
                break
        zp.check(ways == {1, 3}, f"turned only {sorted(ways)}")
    finally:
        sd.close()


def test_base_ahead():
    """A base tile ahead between decisions: it goes for it"""
    sd, cpu = game()
    try:
        x, z = sym["PAD_X"], sym["PAD_Z"] - sym["TERRACE_R"] - 1  # south of the terrace
        zp.check(code(cpu, x, z) == 0, "no road south of the base")
        r = only_zombie(cpu, x, z, NORTH, cz=256 - MARGIN - 1)
        for _ in range(10):
            zp.frames(cpu, 1)
            if cpu.rd(r + 16):
                break
        zp.check(cpu.rd(r + 16) in (1, 2), "not going for the base")
        zp.check(cpu.rd(r + 4) == NORTH, "turned away from the base")
    finally:
        sd.close()


def test_walks_on_in_the_open():
    """Road ahead: it keeps walking, heading kept"""
    sd, cpu = game()
    try:
        x, z = find_cell(cpu, lambda c: c == 0)
        r = only_zombie(cpu, x, z, NORTH, cz=100)
        z0 = cpu.rd16(r + 2)
        zp.frames(cpu, 20)
        zp.check(cpu.rd(r + 4) == NORTH and cpu.rd16(r + 2) > z0, "didn't walk on")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
