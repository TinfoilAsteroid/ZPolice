"""Aim assist (aim_assist, weapons.asm): a centre slot shot turns to a monster
just off its path, at most AIM_DEV steps of 1/256 rad, if the monster was drawn
last frame; one further off flies straight.  Each linked chain gun has its
own, from its own muzzle.  The crosshairs are where the rounds are 50 m
ahead.  And the
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


def linked_frames(cpu, n=12):
    """n frames of linked fire: the mean sin of the left gun's rounds and of
    the right's (told apart by their x either side of the camera's)"""
    recs = [sym["bullets"] + k * sym["BREC"] for k in range(sym["NBULLETS"])]
    cx = cpu.rd16(sym["cam_x"] + 1)
    left, right = [], []
    for _ in range(n):
        for b in recs:
            cpu.wr(b + sym["B_STATE"], 0)
        cpu.wr(sym["gun_wait"], 0)
        cpu.keys = {" "}
        zp.frames(cpu, 1)
        cpu.keys = set()
        for b in recs:
            if cpu.rd(b + sym["B_STATE"]):
                sn = s16(cpu.rd16(b + sym["B_SIN"]))
                px = s16((cpu.rd16(b + sym["B_PX"]) - cx) & 0xFFFF)
                (left if px < 0 else right).append(sn)
    return sum(left) / max(1, len(left)), sum(right) / max(1, len(right)), len(left), len(right)


def linked(cpu):
    L, R = sym["WPN_LINK_L"], sym["WPN_LINK_R"]
    for slot, t in ((L, "WPN_LCHAIN_L"), (R, "WPN_LCHAIN_R")):
        cpu.wr(sym["wpn_slots"] + 2 * slot, sym[t])
        cpu.wr(sym["wpn_slots"] + 2 * slot + 1, 200)
    cpu.wr(sym["wpn_sel"], L)


def test_linked_guns_aim_each():
    """Each linked chain gun has its own aim assist, from its own muzzle: a
    zombie just off the left gun's line turns the left gun's rounds (and its
    crosshair) towards it, and not the right's (too far off theirs); and the
    other way round"""
    k = sym["LINK_OFF"]
    for across, side in ((-k - 8, "left"), (k + 8, "right")):
        sd, cpu = game()
        with sd:
            stage(cpu, 2, across)
            linked(cpu)
            zp.frames(cpu, 1)
            lx, rx = cpu.rd(sym["sight_lx"]), cpu.rd(sym["sight_rx"])
            ml, mr, nl_, nr = linked_frames(cpu)
            zp.check(nl_ and nr, f"rounds: {nl_} left, {nr} right")
            zp.note(f"zombie {across} across: left gun's sin {ml:+.1f}, right's {mr:+.1f}; "
                    f"crosshairs at {lx}, {rx}")
            if side == "left":
                zp.check(ml < -2 and abs(mr) < 2, f"left {ml:.1f}, right {mr:.1f}: not the left gun alone")
                zp.check(lx < 128 - sym["LINK_SIGHT_DX"] and rx == 128 + sym["LINK_SIGHT_DX"],
                         f"crosshairs at {lx}, {rx}: not the left one moved left alone")
            else:
                zp.check(mr > 2 and abs(ml) < 2, f"left {ml:.1f}, right {mr:.1f}: not the right gun alone")
                zp.check(rx > 128 + sym["LINK_SIGHT_DX"] and lx == 128 - sym["LINK_SIGHT_DX"],
                         f"crosshairs at {lx}, {rx}: not the right one moved right alone")


def test_sights_at_50_m():
    """The crosshairs, with nothing to aim at, are where the rounds are
    SIGHT_RANGE (50 m) ahead: the linked guns' LINK_OFF to each side and the
    muzzles GUN_DY below the camera; the centre gun's by its tilt
    (sight_rows)"""
    import math
    R, F = sym["SIGHT_RANGE"], 128
    zp.check(R == 640, f"SIGHT_RANGE {R}, not 50 m (640 units)")
    dy = -s16(sym["GUN_DY"] & 0xFFFF)
    zp.check(sym["GUN_SIGHT_DY"] == round(F * dy / R), "GUN_SIGHT_DY")
    zp.check(sym["LINK_SIGHT_DX"] == round(F * sym["LINK_OFF"] / R), "LINK_SIGHT_DX")
    sd, cpu = game()
    with sd:
        page = cpu.page(sym["PAGE_WEAPONS"])
        dn, up = sym["GUN_TILT_DN"], sym["GUN_TILT_UP"]
        for i, kk in enumerate(range(-dn, up + 1)):
            a = kk * 2 * math.pi / 256
            want = round(sym["VIEW_CY"] - F * math.tan(a) + F * dy / (R * math.cos(a)))
            got = page[sym["sight_rows"] - 0xC000 + i]
            zp.check(got == want, f"sight_rows for tilt {kk}: {got}, not {want}")
        zp.check(cpu.rd(sym["sight_y"]) == sym["VIEW_CY"] + sym["GUN_SIGHT_DY"], "the level sight's row")
        for tilt in (5, -10, -dn):          # the row follows the tilt (in the view)
            cpu.wr(sym["gun_tilt"], tilt & 255)
            zp.frames(cpu, 1)
            want = min(max(page[sym["sight_rows"] - 0xC000 + tilt + dn], sym["SIGHT_MARGIN"]),
                       sym["VIEW_H"] - sym["SIGHT_MARGIN"] - 1)
            zp.check(cpu.rd(sym["sight_y"]) == want, f"tilt {tilt}: sight row {cpu.rd(sym['sight_y'])}, not {want}")
        cpu.wr(sym["gun_tilt"], 0)
        linked(cpu)
        zp.frames(cpu, 2)
        got = [cpu.rd(sym[v]) for v in ("sight_lx", "sight_ly", "sight_rx", "sight_ry")]
        y = sym["VIEW_CY"] + sym["GUN_SIGHT_DY"]
        want = [128 - sym["LINK_SIGHT_DX"], y, 128 + sym["LINK_SIGHT_DX"], y]
        zp.check(got == want, f"the linked crosshairs at {got}, not {want} (nothing near)")


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
