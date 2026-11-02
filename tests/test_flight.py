"""Flying into a building stops the VTOL, costs hit points, shakes the
screen and plays the crunch.
"""
import os

import zptest as zp
from zptest import sym

import citymap as cm  # noqa: E402  (tools/, on the path from zptest)


def test_building_crash():
    m = cm.load(os.path.join(zp.ROOT, "maps", "CITY01.json"))
    c = m["cells"]
    x, z = next((x, z) for z in range(20, 30) for x in range(20, 44)
                if c[z * 64 + x] == 0 and c[(z + 1) * 64 + x] in range(5, 16) and c[(z - 1) * 64 + x] == 0)
    with zp.SD() as sd:
        cpu = zp.machine(sd, interrupts=True)
        zp.start_game(cpu)
        # on a road, flying north at a building taller than the VTOL
        zp.set_camera(cpu, x << 16 | 0x8000, z << 16, 40, speed=12)
        hp0 = cpu.rd(sym["vtol_hp"])
        seen = {"shake": False, "crunch": False}
        flips = []
        cpu.on_flip = lambda b: flips.append(1)
        while len(flips) < 26:
            cpu.stepi()
            seen["shake"] |= cpu.rd(sym["shake_t"]) > 0
            seen["crunch"] |= cpu.rd(sym["sfx2_req"]) == sym["SFX_CRASH"]
        shook, crunch = seen["shake"], seen["crunch"]
        zp.check(cpu.rd(sym["cam_z"] + 2) <= z, f"flew into the building at cell {x},{z + 1}")
        zp.check(cpu.rd(sym["vtol_hp"]) < hp0, "no damage")
        zp.check(shook, "no screen shake")
        zp.check(crunch, "no crunch sound")


if __name__ == "__main__":
    zp.main(globals())
