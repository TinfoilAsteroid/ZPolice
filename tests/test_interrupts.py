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



def test_sound_page():
    """An interrupt plays the sounds from the audio page, mapped into slot 7
    for them, then puts back the page there and the main code's selected
    NextReg (it may be between its OUT $243B and its IN / OUT $253B)"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.frames(cpu, 2)
        zp.run_until(cpu, lambda: cpu.iff and cpu.mmu[7] != sym["PAGE_AUDIO"], "a moment to interrupt")
        mmu7, pc0, sp0 = cpu.mmu[7], cpu.pc, cpu.sp
        cpu.nr_sel = 0x1F                           # (the raster line, mid-read)
        cpu.wr(sym["sfx_req"], sym["SFX_MG"])
        cpu.ay.pop(2, None)
        cpu.interrupt()
        zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, "the interrupt's return",
                     limit=200_000)
        cpu.step()
        zp.check(cpu.mmu[7] == mmu7, f"slot 7: page {cpu.mmu[7]}, not {mmu7} as before")
        zp.check(cpu.nr_sel == 0x1F, f"the selected NextReg ${cpu.nr_sel:02X}, not $1F")
        zp.check(any(cpu.ay.get(2, [0] * 16)), "the machine gun's sound not played (AY 2)")
        zp.check(cpu.rd16(sym["sfx_ptr"]) != 0, "the sound not playing on")



def test_engines_mono():
    """The engines' AY (select %11: the hardware's AY 0) mono, in the centre
    (NextReg $09 bit 5); the effects' chips (AY 1, AY 2) stereo"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
        nr9 = cpu.nextreg.get(0x09, 0)
        zp.check(nr9 & 0xE0 == 0x20, f"NextReg $09 = ${nr9:02X}: not the engines' AY alone mono")


if __name__ == "__main__":
    zp.main(globals())
