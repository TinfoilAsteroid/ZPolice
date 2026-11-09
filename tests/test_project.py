"""Building corners' projection (vproj and vproj_y, city.asm): the same
screen x and y as vtx_proj (project, zpatch, scale_comp) and the level-flight
shortcut it replaced (proj_y after the corner below), for corners whose
outcode is 0, over every shift of Z (left, none, right) and the frustum's
edges.
"""
import random
import zptest as zp
from zptest import sym

RET = 0x0000                            # a return address no routine uses
V = sym["vtx"]                          # a corner, and the one 64 above it


def s16(v):
    return v - 65536 if v > 32767 else v


def call(cpu, name, ix=None, hl=None, de=None):
    cpu.set_nextreg(0x57, sym["PAGE_CITY"])
    if ix is not None:
        cpu.ix = ix
    if hl is not None:
        cpu.r[4], cpu.r[5] = hl >> 8 & 255, hl & 255
    if de is not None:
        cpu.r[2], cpu.r[3] = de >> 8 & 255, de & 255
    cpu.sp = 0xBFF0
    cpu.push(RET)
    cpu.pc = sym[name]
    n = 0
    while cpu.pc != RET:
        cpu.step()
        n += 1
        if n > 5000:
            raise AssertionError(f"{name} didn't return")


def put(cpu, at, x, y, z):
    for k, v in enumerate((x, y, z)):
        cpu.wr16(at + 2 * k, v & 0xFFFF)


def outcode(cpu, at):
    call(cpu, "calc_oc", hl=at)
    return cpu.r[7]


def corners():
    rnd = random.Random(7)
    zs = [sym["NEAR"], sym["NEAR"] + 1, 100, 255, 256, 257, 300, 511, 512, 513,
          1000, 1023, 1024, 2047, 2048, 4095, 4096, 8000, 16000]
    for z in zs:
        for x in (-z, -z + 1, -1, 0, 1, z // 2, z - 1, z):
            for y in (-(z >> 1), -(z >> 1) + 1, -1, 0, 1, (z >> 1) - 1, z >> 1):
                yield x, y, z
    for _ in range(3000):
        z = int(sym["NEAR"] * 2 ** rnd.uniform(0, 10))
        yield rnd.randint(-z, z), rnd.randint(-(z >> 1), z >> 1), z


def test_same_as_vtx_proj():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        n = 0
        for x, y, z in corners():
            put(cpu, V, x, y, z)
            if outcode(cpu, V):
                continue
            call(cpu, "vtx_proj", ix=V)
            old = cpu.rd(V + 7), cpu.rd(V + 8)
            cpu.wr(V + 7, 0x5A)
            cpu.wr(V + 8, 0xA5)
            call(cpu, "vproj", ix=V)
            new = cpu.rd(V + 7), cpu.rd(V + 8)
            zp.check(new == old, f"corner {x},{y},{z}: vproj {new}, vtx_proj {old}")
            # the level shortcut: a corner above, the same X and Z
            yt = (y + 37 * z // 100) if y < 0 else (y - 23 * z // 100)
            put(cpu, V + 64, x, yt, z)
            if outcode(cpu, V + 64) == 0:
                call(cpu, "vtx_proj", ix=V)
                call(cpu, "proj_y", hl=yt & 0xFFFF)
                old = cpu.r[7], cpu.r[1]
                call(cpu, "vproj", ix=V)
                call(cpu, "vproj_y", ix=V + 64)
                new = cpu.rd(V + 64 + 7), cpu.rd(V + 64 + 8)
                zp.check(new == old, f"corner {x},{yt},{z} over {y}: vproj_y {new}, proj_y {old}")
            n += 1
        zp.note(f"{n} corners the same")


def test_pretest_same_as_scale_comp():
    """occ_pretest's oz_norm / oz_sc / oz_sx (city2.asm): the same as zpatch
    then scale_comp, and occ_sx's screen x from it, for any Z >= NEAR and
    components far outside the view too (the clamp).  (The old occ_sx called
    zpatch with A = X's high byte, so for X 0-255 and Z < 256 zpatch took Z
    as 1: a bound at the screen's edge.  oz_norm always uses Z.)"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        cpu.set_nextreg(0x54, sym["PAGE_CITY2"])
        rnd = random.Random(11)
        st = sym["oz_min"]
        pairs = [(z, v) for z in (sym["NEAR"], 100, 255, 256, 511, 512, 1023, 1024, 5000)
                 for v in (-4000, -z - 188, -z, -1, 0, 1, z, z + 188, 4000)]
        pairs += [(int(sym["NEAR"] * 2 ** rnd.uniform(0, 8)), rnd.randint(-4000, 4000))
                  for _ in range(1500)]
        for z, v in pairs:
            cpu.r[7] = 1                # (zpatch takes Z 0 if A | H is 0:
            call(cpu, "zpatch", hl=z)  # project calls it with A = L)
            call(cpu, "scale_comp", hl=v & 0xFFFF)
            old = cpu.r[7]
            sx_old = min(255, 128 + old) if v >= 0 else max(0, 128 - old)
            call(cpu, "oz_norm", hl=z, de=st)
            call(cpu, "oz_sc", hl=v & 0xFFFF, de=st)
            new = cpu.r[7]
            zp.check(new == old, f"Z {z}, component {v}: oz_sc {new}, scale_comp {old}")
            call(cpu, "oz_sx", hl=v & 0xFFFF, de=st)
            zp.check(cpu.r[7] == sx_old, f"Z {z}, X {v}: oz_sx {cpu.r[7]}, occ_sx {sx_old}")
        zp.note(f"{len(pairs)} the same")


if __name__ == "__main__":
    zp.main(globals())
