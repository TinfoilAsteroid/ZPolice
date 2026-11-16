"""Game time (clock_step, zpolice.asm): dt, the 50 Hz ticks since the last
frame (at most DT_MAX, right across the counter's roll-over); fs, their
frames' worth at ASSUMED_FPS (8.8) and its inverse; fsteps, whole frames'
worth (the fraction carried); game_now; clock_reset.  And timing that holds
whatever the frames' length: the machine gun's rate.
"""
import zptest as zp
from zptest import sym

TICK_HZ, FPS, DT_MAX = sym["TICK_HZ"], sym["ASSUMED_FPS"], sym["DT_MAX"]


def call(cpu, name):
    pc0, sp0 = cpu.pc, cpu.sp
    cpu.push(pc0)
    cpu.pc = sym[name]
    zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, f"{name} to return", limit=2_000_000)


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, 1)
    zp.frames(cpu, 2)
    cpu.wr(sym["clk_test"], 0)          # the real clock (driven by hand)
    return sd, cpu


def step(cpu, ticks):
    """isr_ticks on by ticks, then clock_step"""
    cpu.wr16(sym["isr_ticks"], (cpu.rd16(sym["isr_ticks"]) + ticks) & 0xFFFF)
    call(cpu, "clock_step")
    return cpu.rd(sym["dt"]), cpu.rd16(sym["fs"]), cpu.rd(sym["fsteps"])


def test_dt_and_fs():
    sd, cpu = game()
    try:
        cpu.wr16(sym["isr_ticks"], 1000)
        call(cpu, "clock_reset")
        for t in range(DT_MAX + 1):
            dt, fs, _ = step(cpu, t)
            zp.check(dt == t, f"{t} ticks: dt {dt}")
            want = round(t * FPS * 256 / TICK_HZ)
            zp.check(abs(fs - want) <= 1, f"{t} ticks: fs {fs}, not {want}")
            inv = cpu.rd16(sym["fsinv"])
            if t:
                zp.check(abs(inv * fs / 65536 - 1) < 0.02, f"{t} ticks: fsinv {inv} isn't 1/fs")
        dt, _, _ = step(cpu, 500)
        zp.check(dt == DT_MAX, f"a 10 s stall: dt {dt}, not DT_MAX")
    finally:
        sd.close()


def test_roll_over():
    """isr_ticks rolling over 65535 -> 0 still gives the ticks between"""
    sd, cpu = game()
    try:
        cpu.wr16(sym["isr_ticks"], 65533)
        call(cpu, "clock_reset")
        dt, _, _ = step(cpu, 5)
        zp.check(cpu.rd16(sym["isr_ticks"]) == 2 and dt == 5, f"across the roll-over: dt {dt}, not 5")
    finally:
        sd.close()


def test_fsteps_and_game_now():
    """At 3 or 4 ticks a frame (about 14 fps) a whole frame's worth comes
    about every frame; at 1 tick a frame (50 fps) about every 3.6"""
    sd, cpu = game()
    try:
        call(cpu, "clock_reset")
        now0 = cpu.rd16(sym["game_now"])
        total = sum(step(cpu, 1)[2] for _ in range(50))
        zp.check(total == FPS or abs(total - FPS) <= 1, f"50 ticks one at a time: {total} frames' worth, not {FPS}")
        total = sum(step(cpu, 4)[2] for _ in range(25))
        zp.check(abs(total - 100 * FPS / TICK_HZ) <= 1, f"100 ticks four at a time: {total} frames' worth")
        zp.check(cpu.rd16(sym["game_now"]) - now0 == 150, "game_now isn't the ticks added up")
    finally:
        sd.close()


def test_paused_time_doesnt_count():
    """clock_reset (after a pause, a load): the next frame counts from then"""
    sd, cpu = game()
    try:
        call(cpu, "clock_reset")
        cpu.wr16(sym["isr_ticks"], cpu.rd16(sym["isr_ticks"]) + 300)    # 6 s paused
        call(cpu, "clock_reset")
        dt, _, _ = step(cpu, 2)
        zp.check(dt == 2, f"after the pause: dt {dt}, not 2")
    finally:
        sd.close()


def test_gun_rate_holds():
    """The machine gun fires every GUN_INTERVAL ticks on average, whether the
    frames are 2 ticks or 7"""
    for per in (2, 7):
        sd, cpu = game()
        try:
            cpu.wr16(sym["wpn_slots"], sym["WPN_GUN"] | 255 << 8)
            cpu.wr(sym["wpn_sel"], 0)
            cpu.wr(sym["clk_test"], 1)
            cpu.keys = {"W"}            # (off the pad: the guns fire in the air)
            zp.frames(cpu, 6)
            cpu.wr(sym["clk_test"], 0)  # then the clock by hand
            call(cpu, "clock_reset")
            cpu.keys = {" "}
            shots = [0]
            old = cpu.on_flip
            sfx = sym["sfx_req"]
            n = 0
            frames = 30 * 7 // per      # 210 ticks either way
            for _ in range(frames):
                cpu.wr16(sym["isr_ticks"], (cpu.rd16(sym["isr_ticks"]) + per) & 0xFFFF)
                cpu.wr(sfx, 0)
                zp.frames(cpu, 1)
                n += cpu.rd(sfx) == sym["SFX_MG"]
            want = frames * per / sym["GUN_INTERVAL"]
            zp.note(f"{per} ticks a frame: {n} rounds in {frames * per} ticks ({want:.1f} at the rate)")
            zp.check(abs(n - want) <= 1.5, f"{per} ticks a frame: {n} rounds, not about {want:.1f}")
        finally:
            sd.close()


if __name__ == "__main__":
    zp.main(globals())
