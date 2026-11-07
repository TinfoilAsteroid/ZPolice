"""Aim assist (aim_assist, weapons.asm): a centre slot shot turns to a monster
just off its path, at most AIM_DEV steps of 1/256 rad, if the monster was drawn
last frame; one further off, or a linked gun's, flies straight.  And the
figures are drawn at their true height, a row at a time.
"""
import zptest as zp
from zptest import sym

Y = 20                                  # the camera's height: 1.5 m, so a
                                        # level shot is at a zombie's chest


def s16(v):
    return v - 65536 if v > 32767 else v


def road_ahead(cpu, depth):
    """A road cell with depth cells of road on towards +z."""
    cm = sym["city_map"]
    road = lambda x, z: 0 <= x < 64 and 0 <= z < 64 and cpu.rd(cm + z * 64 + x) & 31 == 0
    for z in range(2, 62):
        for x in range(2, 62):
            if all(road(x, z + d) for d in range(depth + 1)):
                return x, z
    raise AssertionError("no straight road")


def game(level=2):
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, level)
    return sd, cpu


def stage(cpu, tiles, across):
    """The camera on a road looking +z, one zombie `tiles` cells ahead and
    `across` units to the right; the others gone.  Its record."""
    x, z = road_ahead(cpu, tiles + 1)
    recs = [sym["zombies"] + k * sym["ZREC"] for k in range(sym["NMON"])]
    live = [r for r in recs if cpu.rd(r + 10) & 1]
    r = live[0]
    for o in live[1:]:
        cpu.wr(o + 10, cpu.rd(o + 10) & ~1)
    cx, cz = (x << 8) + 128, (z << 8) + 128
    zp.set_camera(cpu, cx << 8, cz << 8, Y)
    cpu.wr16(r, cx + across)
    cpu.wr16(r + 2, cz + tiles * 256)
    cpu.wr(r + 21, 0)
    cpu.wr(r + 22, 0)
    cpu.wr(r + 18, 100)                 # (enough hit points to see each hit)
    zp.frames(cpu, 2)
    return r


def fire(cpu, weapon=None, sel=0):
    """One frame of fire: its rounds (any that hit something have stopped,
    but kept these), as (sin, cos, slope)."""
    recs = [sym["bullets"] + k * sym["BREC"] for k in range(sym["NBULLETS"])]
    for b in recs:
        cpu.wr(b + sym["B_STATE"], 0)
    if weapon:
        cpu.wr(sym["wpn_slots"] + 2 * sel, sym[weapon])
        cpu.wr(sym["wpn_slots"] + 2 * sel + 1, 200)
    cpu.wr(sym["wpn_sel"], sel)
    cpu.wr(sym["gun_wait"], 0)
    cpu.keys = {" "}
    zp.frames(cpu, 1)
    cpu.keys = set()
    out = []
    for b in recs:
        if cpu.rd(b + sym["B_STATE"]):
            out.append((s16(cpu.rd16(b + sym["B_SIN"])), s16(cpu.rd16(b + sym["B_COS"])),
                        s16(cpu.rd16(b + sym["B_SLOPE"]))))
    return out


def test_turns_to_a_near_miss():
    sd, cpu = game()
    with sd:
        stage(cpu, 2, 8)                # 40 m ahead, 0.6 m off: outside its
        rounds = fire(cpu, "WPN_GUN")   # hit box, inside the cone
        zp.check(rounds, "no round fired")
        sn = rounds[0][0]
        zp.check(0 < sn <= sym["AIM_DEV"], f"sin {sn}: not turned right, or over AIM_DEV")
        zp.note(f"8 units off at 512: sin {sn}/256")


def test_the_shot_hits():
    """Straight, this round would pass 8 units from the zombie's middle: its
    box is 3 each way."""
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, 8)
        fire(cpu, "WPN_GUN")
        zp.frames(cpu, 3)
        hp = cpu.rd(r + 18)
        zp.check(hp < 100, "the zombie wasn't hit")


def test_left_too():
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, -8)
        rounds = fire(cpu, "WPN_GUN")
        zp.check(-sym["AIM_DEV"] <= rounds[0][0] < 0, f"sin {rounds[0][0]}: not turned left")
        zp.frames(cpu, 3)
        zp.check(cpu.rd(r + 18) < 100, "the zombie wasn't hit")


def test_outside_the_cone():
    sd, cpu = game()
    with sd:
        stage(cpu, 2, 38)               # 3 m off at 40 m: 4.2 degrees
        rounds = fire(cpu, "WPN_GUN")
        zp.check(rounds[0][0] == 0, f"sin {rounds[0][0]}: turned, and it's out of the cone")


def test_not_drawn():
    """A monster that wasn't drawn (behind a building, say): no assist."""
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, 8)
        cpu.wr(sym["wpn_slots"], sym["WPN_GUN"])
        cpu.wr(sym["wpn_sel"], 0)
        cpu.wr(sym["gun_wait"], 0)
        cpu.keys = {" "}
        zp.run_until(cpu, lambda: cpu.pc == sym["aim_assist"], "aim_assist")
        cpu.wr(r + 31, 0)
        zp.frames(cpu, 1)
        cpu.keys = set()
        zp.check(cpu.rd(r + 18) == 100, "hit: the round was turned to it")


def test_too_high_or_low():
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, 8)
        cpu.wr(r + 21, 200)             # 15 m up (a monster over a roof)
        zp.frames(cpu, 2)
        rounds = fire(cpu, "WPN_GUN")
        zp.check(rounds[0][0] == 0, f"sin {rounds[0][0]}: turned, and it's far above the path")


def test_chain_and_laser():
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, 8)
        sins = []
        for _ in range(16):
            rounds = fire(cpu, "WPN_CHAIN")
            sins.append(rounds[-1][0])
            cpu.wr(r + 18, 100)
        mean = sum(sins) / len(sins)
        zp.note(f"chain gun sin: mean {mean:.1f}, {min(sins)} to {max(sins)}")
        zp.check(mean > 2, "the chain gun's rounds aren't turned towards it")
        zp.check(max(sins) > min(sins), "the chain gun has lost its spread")
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, 8)
        cpu.wr(sym["wpn_slots"], sym["WPN_LASER"])
        cpu.wr(sym["wpn_sel"], 0)
        cpu.keys = {" "}
        zp.frames(cpu, 3)
        cpu.keys = set()
        zp.check(cpu.rd(r + 18) < 100, "the laser didn't reach it")


def test_the_sight_shows_it():
    """The centre crosshair moves to where the rounds go, without firing:
    right for a zombie to the right, left for one to the left, back to the
    middle when nothing is near."""
    for across, side in ((8, 1), (-8, -1), (38, 0)):
        sd, cpu = game()
        with sd:
            cpu.wr(sym["wpn_slots"], sym["WPN_GUN"])
            cpu.wr(sym["wpn_sel"], 0)
            stage(cpu, 2, across)
            zp.frames(cpu, 1)
            x, y = cpu.rd(sym["sight_ax"]), cpu.rd(sym["sight_ay"])
            d = (cpu.page(sym["PAGE_WEAPONS"])[sym["aa_d"] - 0xC000] ^ 128) - 128   # (its page)
            zp.check(x == 128 + (d >> 1), f"sight at {x}, the turn {d}")
            zp.check((x > 128) - (x < 128) == side, f"{across} across: the sight at column {x}")
            zp.check(abs(y - cpu.rd(sym["sight_y"])) <= sym["AIM_DEV"] // 2 + 1, f"sight row {y}")
            rounds = fire(cpu, "WPN_GUN")
            zp.check(rounds[0][0] == d, f"the round turned {rounds[0][0]}, the sight showed {d}")


def test_linked_guns_stay_straight():
    sd, cpu = game()
    with sd:
        stage(cpu, 2, 8)
        L = sym["WPN_LINK_L"]
        cpu.wr(sym["wpn_slots"] + 2 * L, sym["WPN_LCHAIN_L"])
        cpu.wr(sym["wpn_slots"] + 2 * L + 1, 200)
        hits = []
        cpu.wr(sym["wpn_sel"], L)
        cpu.keys = {" "}
        for _ in range(4):
            cpu.wr(sym["gun_wait"], 0)
            zp.run_until(cpu, lambda: cpu.pc == sym["chain_round"], "chain_round")
            a = sym["aim_apply"]
            done = []
            while cpu.pc != sym["round_spread"]:
                if cpu.pc == a:
                    done.append(1)
                cpu.step()
            hits += done
            zp.frames(cpu, 1)
        cpu.keys = set()
        zp.check(not hits, "aim assist ran for a linked gun")


def test_true_size():
    """The zombie's height drawn at each distance: its true projected height,
    one row at a time, up to the largest."""
    sd, cpu = game()
    with sd:
        r = stage(cpu, 2, 0)
        top = sym["GFX_MAX_H"]
        cz = cpu.rd16(r + 2) - 512      # the camera's
        seen = {}
        for dz in list(range(60, 300, 8)) + list(range(300, 1000, 25)):
            cpu.wr16(r + 2, cz + dz)
            got = []
            flips = []
            cpu.on_flip = lambda b: flips.append(1)
            while len(flips) < 1:
                if cpu.pc == sym["spr_draw"] and cpu.mmu[4] == sym["PAGE_CITY2"]:
                    got.append((cpu.rd(sym["zh"]), cpu.rd(sym["zw"]), cpu.rd(sym["zhr"])))
                cpu.step()
            cpu.on_flip = None
            for h, w, hr in got:
                seen[dz] = (h, w, hr)
                zp.check(h == min(hr, top), f"Z about {dz}: {h} rows drawn, projected {hr}")
                zp.check(abs(w - h / 2) <= 2, f"{w} x {h}: out of proportion")
        zp.check(len(seen) > 20, f"only {len(seen)} distances drawn")
        hs = sorted({v[0] for v in seen.values()})
        zp.note(f"heights drawn: {hs}")
        zp.check(top in hs and 16 < max(hs), "never drawn large")


if __name__ == "__main__":
    zp.main(globals())
