"""The missile lock's next target (lk_next, weapons.asm): with a target,
K_TARGET (M by default) moves the lock to the next monster by index, round
the list, that was drawn last frame and is in range; it locks on afresh
(locking, LOCK_TIME again).  Back round to the current one, the lock stays.
"""
import zptest as zp
from zptest import sym

NMON = sym["NMON"]
ZREC = sym["ZREC"]


def rec(k):
    return sym["zombies"] + k * ZREC


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, 2)
    zp.frames(cpu, 2)
    cpu.set_nextreg(0x56, sym["PAGE_WEAPONS"])      # (weapons logic at $C000,
    cpu.set_nextreg(0x57, sym["PAGE_INPUT"])        #  the keys in slot 7)
    return sd, cpu


def call(cpu, name):
    pc0, sp0 = cpu.pc, cpu.sp
    cpu.push(pc0)
    cpu.pc = sym[name]
    zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, f"{name} to return", limit=5_000_000)


def stage(cpu, seen, target, state=2):
    """Only the monsters `seen` in play, each beside the VTOL and drawn last
    frame; the lock on `target`, in `state`."""
    zp.set_camera(cpu, 0x200080, 0x200080, 20)
    cx = cpu.rd16(sym["cam_x"] + 1)
    cz = cpu.rd16(sym["cam_z"] + 1)
    for k in range(NMON):
        r = rec(k)
        if k in seen:
            cpu.wr(r + 10, cpu.rd(r + 10) | 1)
            cpu.wr(r + 16, 0)
            cpu.wr16(r, cx + 40)
            cpu.wr16(r + 2, cz + 300)
            cpu.wr(r + 31, 1)
            cpu.wr(r + 32, 128)
            cpu.wr(r + 33, 60)
        else:
            cpu.wr(r + 10, cpu.rd(r + 10) & ~1)
            cpu.wr(r + 31, 0)
    cpu.wr(sym["lock_tgt"], target)
    cpu.wr(sym["lock_state"], state)
    cpu.wr(sym["lock_t"], sym["LOCK_TIME"] if state == 2 else 3)


def lock(cpu):
    return cpu.rd(sym["lock_tgt"]), cpu.rd(sym["lock_state"]), cpu.rd(sym["lock_t"])


def test_next():
    """Locked on 2 of 2, 5 and 9: the next is 5, locking afresh; then 9;
    then round to 2"""
    sd, cpu = game()
    try:
        stage(cpu, {2, 5, 9}, 2)
        call(cpu, "lk_next")
        zp.check(lock(cpu) == (5, 1, 0), f"after 2: {lock(cpu)}, not (5, locking, 0)")
        call(cpu, "lk_next")
        zp.check(lock(cpu)[0] == 9, f"after 5: {lock(cpu)[0]}, not 9")
        call(cpu, "lk_next")
        zp.check(lock(cpu)[0] == 2, f"after 9: {lock(cpu)[0]}, not 2 (round the list)")
    finally:
        sd.close()


def test_round_from_the_last():
    """Locked on the last record: the next is the first one seen"""
    sd, cpu = game()
    try:
        stage(cpu, {0, NMON - 1}, NMON - 1)
        call(cpu, "lk_next")
        zp.check(lock(cpu)[0] == 0, f"after {NMON - 1}: {lock(cpu)[0]}, not 0")
    finally:
        sd.close()


def test_skips_the_unseen():
    """Ones not drawn last frame, out of range, or fading out are passed over"""
    sd, cpu = game()
    try:
        stage(cpu, {1, 3, 4, 6, 7}, 1)
        cpu.wr(rec(3) + 31, 0)                          # not drawn
        cpu.wr16(rec(4), cpu.rd16(rec(4)) + sym["LOCK_RANGE"] + 100)   # too far
        cpu.wr(rec(6) + 16, sym["GM_DYING"])            # fading out
        call(cpu, "lk_next")
        zp.check(lock(cpu)[0] == 7, f"after 1: {lock(cpu)[0]}, not 7")
    finally:
        sd.close()


def test_only_one():
    """The only target: the lock is kept as it was"""
    sd, cpu = game()
    try:
        stage(cpu, {4}, 4)
        call(cpu, "lk_next")
        zp.check(lock(cpu) == (4, 2, sym["LOCK_TIME"]), f"{lock(cpu)}: the lock changed")
        zp.check(cpu.iy == rec(4), f"IY {cpu.iy:04X}, not the target's record {rec(4):04X}")
    finally:
        sd.close()


def test_key_m():
    """In lock_update, M (K_TARGET's default) pressed moves the lock on; held,
    it doesn't again"""
    sd, cpu = game()
    try:
        slot = sym["wpn_slots"] + 2 * cpu.rd(sym["wpn_sel"])
        cpu.wr(slot, sym["WPN_MISSILE"])
        cpu.keys = set()
        call(cpu, "kbd_scan")
        stage(cpu, {2, 5}, 2)
        cpu.keys = {"M"}
        call(cpu, "kbd_scan")
        call(cpu, "lock_update")
        zp.check(lock(cpu)[:2] == (5, 1), f"M: {lock(cpu)}, not (5, locking)")
        stage(cpu, {2, 5}, 5, state=1)
        call(cpu, "kbd_scan")                           # (still held)
        call(cpu, "lock_update")
        zp.check(lock(cpu)[0] == 5, f"M held: {lock(cpu)[0]}, not 5")
        stage(cpu, {2, 5}, 2)
        cpu.keys = set()
        call(cpu, "kbd_scan")
        call(cpu, "lock_update")
        zp.check(lock(cpu)[:2] == (2, 2), f"no key: {lock(cpu)}, not (2, locked)")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
