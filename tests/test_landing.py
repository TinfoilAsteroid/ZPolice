"""Landed (resting on the pad, a roof or the road): the speed keys only
bring the speed back to 0, and any speed is braked away as the air brake
does, with a shake.  In the air the speed keys work as before.
"""
import zptest as zp
from zptest import sym


def speed(cpu):
    v = cpu.rd(sym["speed"])
    return v - 256 if v > 127 else v


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)                  # on the landing pad, stopped
    return sd, cpu


def hold(cpu, keys, n):
    cpu.keys = set(keys)
    zp.frames(cpu, n)
    cpu.keys = set()


def test_no_take_off_speed():
    sd, cpu = game()
    try:
        hold(cpu, "Q", 5)
        zp.check(speed(cpu) == 0, f"Q while landed: speed {speed(cpu)}, not 0")
        hold(cpu, "A", 5)
        zp.check(speed(cpu) == 0, f"A while landed: speed {speed(cpu)}, not 0 (no reversing)")
    finally:
        sd.close()


def test_landed_speed_braked():
    sd, cpu = game()
    try:
        cpu.wr(sym["speed"], 20)
        zp.frames(cpu, 1)
        s1 = speed(cpu)
        zp.check(cpu.rd(sym["shake_t"]) > 0, "no shake")
        zp.check(s1 < 20, f"landed at speed 20: still {s1}")
        zp.frames(cpu, 15)
        zp.check(speed(cpu) == 0, f"not braked to 0: speed {speed(cpu)}")
        zp.note(f"speed 20 -> {s1} after a frame")
    finally:
        sd.close()


def test_reverse_back_to_zero():
    sd, cpu = game()
    try:
        cpu.wr(sym["speed"], (-1) & 255)
        hold(cpu, "Q", 6)               # (and the brake): towards 0, not past
        zp.check(speed(cpu) == 0, f"Q from reverse while landed: speed {speed(cpu)}, not 0")
    finally:
        sd.close()


def test_speed_keys_in_the_air():
    sd, cpu = game()
    try:
        hold(cpu, "W", 10)              # climb off the pad
        zp.check(cpu.rd16(sym["cam_y"]) > sym["MIN_Y"] + 50, "didn't climb")
        hold(cpu, "Q", 5)
        zp.check(speed(cpu) == 5, f"Q in the air: speed {speed(cpu)}, not 5")
    finally:
        sd.close()


def pos(cpu):
    return cpu.rd16(sym["cam_x"] + 1) * 256 + cpu.rd(sym["cam_x"]), \
        cpu.rd16(sym["cam_z"] + 1) * 256 + cpu.rd(sym["cam_z"])


def test_strafe():
    sd, cpu = game()
    try:
        p0 = pos(cpu)
        cpu.wr(sym["lthrust_fitted"], 1)
        hold(cpu, "L", 2)
        zp.check(pos(cpu) == p0, "strafed while landed")
        hold(cpu, "W", 10)              # off the pad
        p0 = pos(cpu)
        hold(cpu, "L", 1)               # a frame: 2.5 units
        p1 = pos(cpu)
        dx, dz = p1[0] - p0[0], p1[1] - p0[1]
        d = (dx * dx + dz * dz) ** 0.5 / 256
        zp.check(2.2 < d < 2.8, f"a frame moved {d:.2f} units, not 2.5")
        zp.note(f"a frame: ({dx / 256:.2f}, {dz / 256:.2f}) units")
        hold(cpu, "L", 3)               # held: on it goes
        p3 = pos(cpu)
        dx, dz = p3[0] - p0[0], p3[1] - p0[1]
        d = (dx * dx + dz * dz) ** 0.5 / 256
        zp.check(9.5 < d < 10.5, f"held 4 frames moved {d:.2f} units, not 10")
        hold(cpu, "K", 4)               # left: back again
        p2 = pos(cpu)
        zp.check(abs(p2[0] - p0[0]) < 40 and abs(p2[1] - p0[1]) < 40, "left didn't undo right")
    finally:
        sd.close()


def test_no_strafe_without_thrusters():
    sd, cpu = game()
    try:
        cpu.wr(sym["lthrust_fitted"], 0)    # (DEBUG_UNLOCK_ALL fits them)
        hold(cpu, "W", 10)
        p0 = pos(cpu)
        hold(cpu, "L", 2)
        zp.check(pos(cpu) == p0, "strafed without the lateral thrusters")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
