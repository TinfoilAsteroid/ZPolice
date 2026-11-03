"""Interrupts don't disturb the drawing: 30 frames of flight (climbing and
turning) drawn with no interrupts, with the 50 Hz interrupt, and under
stress (an interrupt every ~2,000 T-states, and forced in the window just
before the DI and the last PUSH of push_end, while SP points into Layer 2)
must give the same Layer 2, frame for frame.
"""
import zptest as zp
from zptest import sym

L2 = [sym["PAGE_L2_A"] + i for i in range(6)] + [sym["PAGE_L2_B"] + i for i in range(6)]
FRAMES = 30
PLAN = [(1, 4, ""), (5, FRAMES, "WQP")]     # (first frame, last, keys held:
                                            #  climbing off the pad, speeding
                                            #  up, turning)


def flight(mode):
    """mode: None (no interrupts), 'frame' (50 Hz) or 'stress'.  Returns each
    frame's Layer 2 and the interrupts taken."""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        st = {"f": 0, "pics": [], "n": 0, "win": 0, "next": cpu.t + zp.FRAME_T}

        def flip(bank):
            st["f"] += 1
            f = st["f"]
            cpu.keys = set(next((k for a, b, k in PLAN if a <= f <= b), ""))
            st["pics"].append(b"".join(bytes(cpu.page(p)) for p in L2))
            if f >= FRAMES:
                raise zp.nexsim.Halt("done")
        cpu.on_flip = flip
        push_end = sym["push_end"]
        try:
            while True:
                was_ei = cpu.rd(cpu.pc) == 0xFB      # (EI: none until after the next)
                cpu.step()
                if was_ei or not cpu.iff or mode is None:
                    continue
                if mode == "frame":
                    if cpu.t >= st["next"]:
                        st["next"] += zp.FRAME_T
                        st["n"] += bool(cpu.interrupt())
                elif (cpu.pc in (push_end - 2, push_end - 3) and (cpu.sp < 0x2003 or cpu.sp >= 0xFFFE)
                      and cpu.mmu[7] == sym["PAGE_CITY"]):
                    st["win"] += 1
                    if st["win"] % 2 == 0:
                        st["n"] += bool(cpu.interrupt())
                elif cpu.t >= st["next"]:
                    st["next"] = cpu.t + 1999
                    st["n"] += bool(cpu.interrupt())
        except zp.nexsim.Halt:
            pass
        return st["pics"], st["n"]


_ref = []


def compare(mode):
    if not _ref:
        _ref.append(flight(None)[0])
    ref = _ref[0]
    pics, n = flight(mode)
    zp.check(len(pics) == len(ref) == FRAMES, f"{len(pics)} frames drawn, {len(ref)} without interrupts")
    zp.check(n > 0, "no interrupts taken")
    bad = [i + 1 for i, (a, b) in enumerate(zip(ref, pics)) if a != b]
    zp.check(not bad, f"Layer 2 differs from the run without interrupts in frames {bad}")
    zp.note(f"{n:,} interrupts")


def test_50hz():
    compare("frame")


def test_stress():
    compare("stress")


if __name__ == "__main__":
    zp.main(globals())
