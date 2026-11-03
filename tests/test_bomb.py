"""The bomb: released from a hover along a long road, it glides down from
BOMB_ANGLE (10 degrees: 7 angle steps, 9.8), a step steeper every
BOMB_STEEPEN frames, its speed kept, and bursts on the ground.  From 15 m
it lands outside the blast (2 tiles) and the VTOL is unhurt; from low down
the blast reaches the VTOL for BOMB_DMG.
"""
import math

import zptest as zp
from zptest import sym

GRID = 64


def code(cpu, x, z):
    return cpu.rd(sym["city_map"] + z * GRID + x) & sym["CELL_CODE"]


def long_road(cpu, n=12):
    """A road cell with road for n cells north of it (+z)."""
    for x in range(4, GRID - 4):
        for z in range(4, GRID - 4 - n):
            if all(code(cpu, x, z + k) == 0 for k in range(n)):
                return x, z
    raise AssertionError(f"no straight road {n} cells long on level 1")


def drop(height):
    """Hover at height over a long road facing north, drop a bomb: its path
    (x, y, z each frame until it bursts) and the VTOL's hit points before
    and after."""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        x, z = long_road(cpu)
        W = sym["wpn_slots"]
        cpu.wr(W + 2, sym["WPN_BOMB"]); cpu.wr(W + 3, 1)     # slot 2: a bomb
        cpu.wr(sym["wpn_sel"], 1)
        zp.set_camera(cpu, x << 16 | 0x8000, z << 16 | 0x8000, height)
        hp0 = cpu.rd(sym["vtol_hp"])
        cpu.keys = {" "}
        zp.frames(cpu, 1)
        cpu.keys = set()
        bombs = [sym["bullets"] + k * sym["BREC"] for k in range(sym["NBULLETS"])]
        rec = next((a for a in bombs if cpu.rd(a + sym["B_STATE"]) and cpu.rd(a + sym["B_KIND"]) == sym["BK_BOMB"]), None)
        zp.check(rec is not None, "SPACE dropped no bomb")
        path = []
        for _ in range(200):
            st = cpu.rd(rec + sym["B_STATE"])
            path.append((cpu.rd16(rec + sym["B_X"]), cpu.rd16(rec + sym["B_Y"]), cpu.rd16(rec + sym["B_Z"])))
            if st != 1 and st != 0x81:
                break
            zp.frames(cpu, 1)
        zp.check(cpu.rd(rec + sym["B_STATE"]) in (0, 2), "the bomb never landed")
        return path, (x << 8 | 0x80, height, z << 8 | 0x80), hp0, cpu.rd(sym["vtol_hp"])


def angle(a, b):
    """The descent angle from path point a to b, degrees."""
    return math.degrees(math.atan2(a[1] - b[1], math.hypot(b[0] - a[0], b[2] - a[2])))


def test_glide_from_15m():
    path, cam, hp0, hp1 = drop(sym["MAX_Y"])
    x1, y1, z1 = path[-1]
    n = sym["BOMB_STEEPEN"]
    first = angle(path[1], path[1 + n - 1])     # (before its first step)
    later = angle(path[-1 - n], path[-1])
    zp.note(f"{len(path)} frames, landed {z1 - cam[2]} units ahead at height {y1}; "
            f"glide {first:.1f} degrees at first, {later:.1f} at the end")
    want = sym["BOMB_ANGLE"] * 360 / 256
    zp.check(abs(first - want) < 1.5, f"glides at {first:.1f} degrees at first, not {want:.1f}")
    zp.check(later > first + 2, f"the glide didn't steepen ({first:.1f} -> {later:.1f} degrees)")
    zp.check(y1 < 20, f"burst {y1} units up, not on the ground")
    zp.check(z1 - cam[2] > sym["BOMB_R"], f"landed only {z1 - cam[2]} units ahead (inside the blast)")
    zp.check(hp1 == hp0, f"the VTOL took {hp0 - hp1} from a bomb 3 tiles off")


def test_low_drop_hurts_the_vtol():
    path, cam, hp0, hp1 = drop(40)
    zp.note(f"landed {path[-1][2] - cam[2]} units ahead; VTOL {hp0} -> {hp1}")
    zp.check(hp0 - hp1 == sym["BOMB_DMG"], f"the VTOL took {hp0 - hp1}, not {sym['BOMB_DMG']}")


if __name__ == "__main__":
    zp.main(globals())
