"""The linked chain guns: L only in slot 4 (just left of the centre slot on
the HUD), R only in slot 5.  Either selected fires every one fitted, each
round leaving 2 m (LINK_OFF, 26 units) to its side of the centre line; the gunsight
is a crosshair for each fitted, 16 pixels either side of the centre.
"""
import zptest as zp
from zptest import sym

L, R = sym["WPN_LINK_L"], sym["WPN_LINK_R"]


def s16(v):
    return v - 65536 if v > 32767 else v


def game(left, right, sel):
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)
    W = sym["wpn_slots"]
    if left:
        cpu.wr(W + 2 * L, sym["WPN_LCHAIN_L"]); cpu.wr(W + 2 * L + 1, sym["LINK_SHOTS"])
    if right:
        cpu.wr(W + 2 * R, sym["WPN_LCHAIN_R"]); cpu.wr(W + 2 * R + 1, sym["LINK_SHOTS"])
    cpu.wr(sym["wpn_sel"], sel)
    cpu.keys = set("W")                 # off the pad: weapons fire in the air
    zp.frames(cpu, 10)
    cpu.keys = set()
    zp.frames(cpu, 25)                  # (rounds from before gone)
    return sd, cpu


def fire_one(cpu):
    """One frame of fire: the sideways offsets of its rounds' muzzles."""
    cx, cz = cpu.rd16(sym["cam_x"] + 1), cpu.rd16(sym["cam_z"] + 1)
    cpu.keys = {" "}
    zp.frames(cpu, 1)
    cpu.keys = set()
    sn, cs = s16(cpu.rd16(sym["sin_y"])) / 256, s16(cpu.rd16(sym["cos_y"])) / 256
    out = []
    for k in range(sym["NBULLETS"]):
        b = sym["bullets"] + k * sym["BREC"]
        if cpu.rd(b + sym["B_STATE"]) == 1:
            dx = s16(cpu.rd16(b + sym["B_PX"])) - cx
            dz = s16(cpu.rd16(b + sym["B_PZ"])) - cz
            out.append(round(dx * cs - dz * sn))    # + right of the heading
    return sorted(out)


def test_fits_only_its_slot():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        cfg = sym["wpn_cfg"] + sym["WCFG_SLOTS"]
        for t, slot in (("WPN_LCHAIN_L", L), ("WPN_LCHAIN_R", R)):
            mask = cpu.rd(cfg + sym["WCFG_SIZE"] * sym[t])
            zp.check(mask == 1 << slot, f"{t} fits slots {mask:05b}, not only {slot + 1}")


def test_both_fire_together():
    for sel in (L, R):
        sd, cpu = game(True, True, sel)
        try:
            off = fire_one(cpu)
            zp.check(len(off) == 2, f"slot {sel + 1} selected: {len(off)} rounds, not 2")
            k = sym["LINK_OFF"]
            zp.check(abs(off[0] + k) <= 1 and abs(off[1] - k) <= 1,
                     f"muzzles at {off} units, not -{k} and {k}")
            zp.check(cpu.rd(sym["sight_mask"]) == sym["SM_LINK_L"] | sym["SM_LINK_R"],
                     f"sight_mask {cpu.rd(sym['sight_mask'])}: not both crosshairs")
            zp.note(f"slot {sel + 1}: muzzles {off}")
        finally:
            sd.close()


def test_ammo():
    sd, cpu = game(True, True, L)
    try:
        W, n = sym["wpn_slots"], sym["LINK_SHOTS"]
        zp.check(n == 200, f"LINK_SHOTS {n}, not 200")
        zp.check(cpu.rd(sym["wpn_cfg"] + sym["WCFG_SIZE"] * sym["WPN_LCHAIN_L"]) == n,
                 "full load not LINK_SHOTS")
        fire_one(cpu)
        a = cpu.rd(W + 2 * L + 1), cpu.rd(W + 2 * R + 1)
        zp.check(a == (n - 1, n - 1), f"after a frame: ammo {a}, not {n - 1} each")
        cpu.wr(W + 2 * L + 1, 0)            # L out: R fires on alone
        zp.frames(cpu, 25)
        off = fire_one(cpu)
        zp.check(len(off) == 1 and off[0] > 0, f"L empty: muzzles {off}, not R's alone")
        zp.check(cpu.rd(W + 2 * L + 1) == 0, "an empty gun's ammo went below 0")
    finally:
        sd.close()


def test_one_fitted():
    sd, cpu = game(False, True, R)
    try:
        off = fire_one(cpu)
        zp.check(len(off) == 1 and off[0] > 10, f"R alone: muzzles {off}")
        zp.check(cpu.rd(sym["sight_mask"]) == sym["SM_LINK_R"], "R alone: not just the right crosshair")
    finally:
        sd.close()


def test_centre_gun_sight():
    sd, cpu = game(True, True, sym["WPN_CENTRE"])
    try:
        off = fire_one(cpu)
        zp.check(off == [0], f"the machine gun: muzzles {off}, not [0]")
        zp.check(cpu.rd(sym["sight_mask"]) == sym["SM_CENTRE"], "centre slot: not the centre crosshair")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
