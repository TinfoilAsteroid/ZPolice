"""The base's warning beeps (base_beep, zombie.asm; voice 4, AY 2 channel C):
a terrace tile or a barricade hit, a low beep (SFX_WARN_LOW); the landing
pad hit, a mid one (SFX_WARN_MID), over a low one.  A low one waits for the
voice to be free, so that many hits are still heard as beeps.  The weapons'
sounds on AY 2 leave channel C alone.
"""
import zptest as zp
from zptest import sym

PAD_X, PAD_Z = sym["PAD_X"], sym["PAD_Z"]


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, 1)
    zp.frames(cpu, 2)
    return sd, cpu


def hit(cpu, x, z, dmg=1):
    """base_damage at cell (x, z), until it returns"""
    pc0, sp0 = cpu.pc, cpu.sp
    cpu.push(pc0)
    cpu.r[1], cpu.r[2], cpu.r[3] = dmg, z, x            # C, D, E
    cpu.pc = sym["base_damage"]
    zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, "base_damage to return", limit=500_000)


def quiet(cpu):
    cpu.wr(sym["sfx4_req"], 0)
    cpu.wr16(sym["sfx4_ptr"], 0)


def test_terrace_and_pad():
    sd, cpu = game()
    try:
        quiet(cpu)
        hit(cpu, PAD_X - 1, PAD_Z)                      # a terrace tile
        zp.check(cpu.rd(sym["sfx4_req"]) == sym["SFX_WARN_LOW"], "a terrace hit: no low beep")
        hit(cpu, PAD_X, PAD_Z)                          # the pad, over it
        zp.check(cpu.rd(sym["sfx4_req"]) == sym["SFX_WARN_MID"], "the pad hit: no mid beep")
        quiet(cpu)
        cpu.wr16(sym["sfx4_ptr"], sym["sfx_warn_mid"])  # (one playing)
        hit(cpu, PAD_X + 1, PAD_Z)
        zp.check(cpu.rd(sym["sfx4_req"]) == 0, "a low beep cut the one playing")
        hit(cpu, PAD_X, PAD_Z)
        zp.check(cpu.rd(sym["sfx4_req"]) == sym["SFX_WARN_MID"], "the pad's beep waited")
        zp.check(cpu.rd(sym["game_over"]) == 0, "(the pad destroyed)")
    finally:
        sd.close()


def test_barricade():
    sd, cpu = game()
    try:
        t = sym["barr_tab"]
        cpu.wr(t, 10)                                   # one at (10, 12), 5 hit points
        cpu.wr(t + 1, 12)
        cpu.wr(t + 2, 5)
        quiet(cpu)
        hit(cpu, 10, 12)
        zp.check(cpu.rd(sym["sfx4_req"]) == sym["SFX_WARN_LOW"], "a barricade hit: no low beep")
        zp.check(cpu.rd(t + 2) == 4, "the barricade not hurt")
        quiet(cpu)
        cpu.wr(t + 2, 0)                                # gone: no beep
        hit(cpu, 10, 12)
        zp.check(cpu.rd(sym["sfx4_req"]) == 0, "a destroyed barricade beeped")
    finally:
        sd.close()


def test_played_on_ay2_c():
    """The interrupt plays it on AY 2 channel C; a weapon's sound after it
    keeps tone C on in AY 2's mixer"""
    sd, cpu = game()
    try:
        zp.run_until(cpu, lambda: cpu.iff and cpu.mmu[7] != sym["PAGE_AUDIO"], "a moment to interrupt")
        cpu.wr(sym["sfx4_req"], sym["SFX_WARN_MID"])
        cpu.wr(sym["sfx_req"], sym["SFX_MG"])
        cpu.ay.pop(2, None)
        pc0, sp0 = cpu.pc, cpu.sp
        cpu.interrupt()
        zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, "the interrupt's return", limit=200_000)
        ay = cpu.ay.get(2, [0] * 16)
        zp.check(ay[4] | ay[5] << 8 == sym["WARN_MID_TONE"], f"AY 2 tone C {ay[4] | ay[5] << 8}")
        zp.check(ay[10] == 12, f"AY 2 volume C {ay[10]}, not 12")
        zp.check(not ay[7] & 4, "AY 2's mixer has tone C off (the machine gun's)")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
