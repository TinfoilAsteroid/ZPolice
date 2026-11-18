"""The hardware tilemap (tiles.asm): its registers, the font's tiles and the
map in page 14 (PAGE_TILES), printing, tile definitions, the palette and
scrolling.  (nexsim doesn't draw the tilemap: what's checked is what the
code sets up for the hardware.)
"""
import zptest as zp
from zptest import sym

T = sym["PAGE_TILES"]
DEFS, MAP = sym["TM_DEFS"], sym["TM_MAP"]


# the LEDs the game changes (draw_boost_led, draw_alt_led, draw_leds): not
# necessarily as the layout has them
DRIVEN = {(29, sym["SPD_GCOL"] + 4), (29, sym["ALT_GCOL"] + 4), (29, sym["BST_GCOL"] + 4),
          (10, 37), (13, 37), (16, 37), (26, 25)} | \
    {(r, 30 + k) for r in (29, 30) for k in range(5)}     # (the weapon LEDs, labels)


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu, 1)
    zp.frames(cpu, 1)
    return sd, cpu


def call(cpu, name, page="PAGE_SPRITES", **regs):
    """name (in the sprites page, or page, slot 7) with registers set, to
    its return"""
    pc0, sp0 = cpu.pc, cpu.sp
    mmu7 = cpu.mmu[7]
    cpu.set_nextreg(0x57, sym[page])
    idx = {"b": 0, "c": 1, "d": 2, "e": 3, "h": 4, "l": 5, "a": 7}
    for k, v in regs.items():
        if k in ("hl", "de", "bc"):
            cpu.r[idx[k[0]]], cpu.r[idx[k[1]]] = v >> 8, v & 255
        else:
            cpu.r[idx[k]] = v
    cpu.push(pc0)
    cpu.pc = sym[name]
    zp.run_until(cpu, lambda: cpu.pc == pc0 and cpu.sp == sp0, f"{name} to return", limit=5_000_000)
    cpu.set_nextreg(0x57, mmu7)


def cell(cpu, row, col, cols=40):
    p = cpu.page(T)
    a = MAP + (row * cols + col) * 2
    return p[a], p[a + 1]


def test_init_40():
    sd, cpu = game()
    try:
        call(cpu, "tm_init", a=sym["TM_40"])
        nr = cpu.nextreg
        zp.check(nr.get(0x6B) == 0x81, f"$6B {nr.get(0x6B, 0):02X}: not on, 40 columns, over the ULA")
        zp.check(nr.get(0x6E) == 0x80 | MAP >> 8, f"$6E {nr.get(0x6E, 0):02X}: not the map in bank 7")
        zp.check(nr.get(0x6F) == 0x80 | DEFS >> 8, f"$6F {nr.get(0x6F, 0):02X}: not the tiles in bank 7")
        zp.check(nr.get(0x4C) == 0, "pixel index 0 isn't the transparent one")
        p = cpu.page(T)
        zp.check(not any(p[MAP:MAP + 40 * 32 * 2]), "the map isn't clear")
        # the font: 'A' (ASCII 65) as tile 33, each 1-bit pixel ink index 1
        f = sym["font8"] + (ord("A") - 32) * 8
        rows = [cpu.rd(f + i) for i in range(8)]
        t = p[DEFS + 33 * 32: DEFS + 34 * 32]
        want = []
        for r in rows:
            for k in range(4):
                hi, lo = r >> (7 - 2 * k) & 1, r >> (6 - 2 * k) & 1
                want.append(hi << 4 | lo)
        zp.check(list(t) == want, "tile 33 isn't the font's A")
        zp.check(any(t), "the font's A is blank")
        pal = cpu.palettes.get(3, {})          # the tilemap's first palette
        inks = list(cpu.page(sym["PAGE_SPRITES"])[sym["tm_inks"] - 0xE000:][:16])     # (in the sprites page)
        got = [pal.get(16 * k + 1, -1) >> 1 for k in range(16)]
        zp.check(got == inks, f"the inks {got[:4]}..., not {inks[:4]}...")
    finally:
        sd.close()


def test_print():
    sd, cpu = game()
    try:
        call(cpu, "tm_init", a=sym["TM_40"])
        s = b"Hi! ~" + bytes(1)                 # (the text: in page 14's last free tile)
        a = DEFS + 95 * 32
        for i, ch in enumerate(s):
            cpu.page(T)[a + i] = ch
        call(cpu, "tm_print", d=2, e=3, c=0x20, hl=a)
        got = [cell(cpu, 2, 3 + k) for k in range(5)]
        want = [(ord("H") - 32, 0x20), (ord("I") - 32, 0x20), (ord("!") - 32, 0x20),
                (0, 0x20), (0, 0x20)]           # (space; ~ isn't in the font)
        zp.check(got == want, f"printed {got}, not {want}")
        call(cpu, "tm_tile", d=31, e=39, a=70, c=0x10)
        zp.check(cell(cpu, 31, 39) == (70, 0x10), "tm_tile not in the last cell")
    finally:
        sd.close()


def test_layout_and_scroll():
    """Page 14 for 40 columns: the map 2.5K, then 176 tiles (TM_FREE.. 112
    free); the last tile's definition fits the page; scrolling, off, on"""
    sd, cpu = game()
    try:
        zp.check(sym["TM_DEFS"] == 40 * 32 * 2 and sym["TM_TILES"] == 176, "not the 40-column layout")
        zp.check(sym["TM_TILES"] - sym["TM_FREE"] == 112, "not 112 free tiles")
        call(cpu, "tm_init", a=sym["TM_40"])
        call(cpu, "tm_tile", d=31, e=39, a=175, c=0)
        zp.check(cell(cpu, 31, 39) == (175, 0), "the last cell, the last tile")
        src = sym["font8"]
        call(cpu, "tm_defs", hl=src, a=175, b=1)        # (the page's last 32 bytes)
        p = cpu.page(T)
        zp.check(list(p[0x2000 - 32:]) == [cpu.rd(src + i) for i in range(32)], "tile 175 not at the page's end")
        call(cpu, "tm_scroll", hl=300, a=17)
        nr = cpu.nextreg
        zp.check((nr.get(0x2F), nr.get(0x30), nr.get(0x31)) == (1, 300 & 255, 17), "the scroll registers")
        call(cpu, "tm_off")
        zp.check(cpu.nextreg.get(0x6B) == 0, "not hidden")
        call(cpu, "tm_on")
        zp.check(cpu.nextreg.get(0x6B) == 0x81, "not shown again")
    finally:
        sd.close()


def test_defs_and_colour():
    sd, cpu = game()
    try:
        call(cpu, "tm_init", a=sym["TM_40"])
        src = sym["font8"]                      # (any 64 bytes: two tiles' worth)
        p = cpu.page(T)
        a = DEFS + sym["TM_FREE"] * 32
        after = bytes(p[a + 64:a + 96])         # (the next tile, as it was)
        call(cpu, "tm_defs", hl=src, a=sym["TM_FREE"], b=2)
        zp.check(list(p[a:a + 64]) == [cpu.rd(src + i) for i in range(64)], "tm_defs didn't copy them")
        zp.check(bytes(p[a + 64:a + 96]) == after, "tm_defs copied too much")
        call(cpu, "tm_colour", a=5, e=0xE0)
        zp.check(cpu.palettes[3].get(5 * 16 + 1, 0) >> 1 == 0xE0, "tm_colour: offset 5's ink not red")
    finally:
        sd.close()


def test_console_in_the_game():
    """A level: the console as sprites/console_tiles.json lays it out (tiles
    TM_FREE.., each tile's bank's palette offset, mirrored cells; the banks'
    9-bit colours in the tilemap palette), the whole border
    covered; drawn (nexsim draws the tilemap), and see-through where the
    layout has nothing; hidden on the screens outside the game"""
    sd, cpu = game()
    try:
        zp.check(cpu.nextreg.get(0x6B) == 0x80, f"$6B {cpu.nextreg.get(0x6B, 0):02X}: the console isn't shown "
                 "(the tiles' bit 0 choosing the ULA over them)")
        import os
        import sys
        sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
        import consoletiles as ct
        d = ct.load()
        names = [t["name"] for t in d["tiles"]]
        bank = {t["name"]: t.get("bank", 0) for t in d["tiles"]}
        bad = []
        for r in range(32):                     # the map as the layout file has it:
            for c in range(40):                 # each tile with its bank's offset
                cl = d["layout"][r][c]
                v = ct.cell_tile(cl, names)
                want = (0, 0) if v is None else                     (v[0], ct.bank_offset(bank[cl.split("|")[0]]) << 4 | v[1])    # (+ its flags)
                if cell(cpu, r, c) != want and (r, c) not in DRIVEN:
                    bad.append((c, r, cell(cpu, r, c), want))
        zp.check(not bad, f"cells not as sprites/console_tiles.json has them: {bad[:4]}")
        zp.check(all(cell(cpu, r, c)[0] for r in range(32) for c in range(40)
                     if r < 4 or r >= 28 or c < 4 or c >= 36), "the border isn't all console")
        pal = cpu.palettes.get(3, {})           # each bank's 9-bit colours
        for k, b in enumerate(d["banks"]):
            got = [pal.get(ct.bank_offset(k) * 16 + i) for i in range(16)]
            zp.check(got == b, f"bank {k}'s colours {got[:4]}..., not {b[:4]}...")
        import nexsim
        px = nexsim.tilemap_pixels(cpu)
        zp.check((4, 200) in px and (300, 100) in px, "the console not drawn in the border")
        clear = [(r, c) for r in range(4, 28) for c in range(4, 36) if not d["layout"][r][c]]
        zp.check(not any((c * 8 + 4, r * 8 + 4) in px for r, c in clear),
                 "drawn over the view where the layout has nothing")
        cpu.wr(sym["game_over"], 1)             # GAME OVER over the view: the console
        zp.run_until(cpu, lambda: cpu.pc == sym["game_over_screen"], "GAME OVER")   # stays;
        cpu.keys = {" "}                        # SPACE, the main menu: hidden
        zp.run_until(cpu, lambda: cpu.nextreg.get(0x6B, 0x81) == 0, "the console hidden", limit=60 * zp.FRAME_T)
        cpu.keys = set()
    finally:
        sd.close()


def test_console_file():
    """sprites/console_tiles.json usable (consoletiles.problems), and
    tables_console.inc made from it (run build.bat after editing)"""
    import os
    import sys
    import tempfile
    sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
    import consoletiles as ct
    d = ct.load()
    zp.check(os.path.exists(ct.FILE), "no sprites/console_tiles.json")
    errs = ct.problems(d)
    zp.check(not errs, "; ".join(errs))
    with tempfile.TemporaryDirectory() as t:
        out = os.path.join(t, "c.inc")
        ct.write_inc(out, d)
        zp.check(open(out).read() == open(os.path.join(zp.ROOT, "tables_console.inc")).read(),
                 "tables_console.inc is out of date: run build.bat")


def test_boost_led():
    """The LED under the B gauge (draw_boost_led): left as the layout has it
    with no booster; green from half full, amber below half, red below a
    tenth, back to green as it refills; each level's start puts the layout's
    back and shows the level's fuel"""
    import os
    import sys
    sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
    import consoletiles as ct
    d = ct.load()
    names = [t["name"] for t in d["tiles"]]
    banks = {t["name"]: ct.bank_offset(t.get("bank", 0)) << 4 for t in d["tiles"]}
    r, c = sym["BST_LED_ROW"], sym["BST_LED_COL"]
    cl = d["layout"][r][c]
    zp.check(cl.split("|")[0] == "LED_G", f"the layout's cell {c},{r} is {cl!r}, not LED_G")
    flags = ct.cell_parts(cl)[1]
    sd, cpu = game()
    try:
        def shows(name):
            return cell(cpu, r, c) == (sym["TM_FREE"] + names.index(name), banks[name] | flags)
        zp.frames(cpu, 2)
        zp.check(shows("LED_G"), "no booster: not the layout's LED_G")
        cpu.wr(sym["boost_fitted"], 1)
        mx = sym["BOOST_FUEL_MAX"]
        # (on the pad it refuels a little a frame: well clear of the edges)
        for fuel, want in ((mx, "LED_G"), (mx * 3 // 4, "LED_G"), (mx * 3 // 10, "LED_A"), (mx * 3 // 20, "LED_A"),
                           (mx // 20, "LED_R"), (0, "LED_R"), (mx * 3 // 10, "LED_A"), (mx, "LED_G")):
            cpu.wr(sym["boost_fuel"], fuel)
            zp.frames(cpu, 2)
            zp.check(shows(want), f"fuel {fuel}: cell {cell(cpu, r, c)}, not {want}")
    finally:
        sd.close()


def test_alt_led():
    """The LED under the A gauge (draw_alt_led): from the altitude bar's
    gap above the ground's (g_alt - g_gnd pixels): green, amber within
    ALT_LED_AMBER, red below ALT_LED_RED; on the pad (landed) red, high up
    green"""
    import os
    import sys
    sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
    import consoletiles as ct
    d = ct.load()
    names = [t["name"] for t in d["tiles"]]
    banks = {t["name"]: ct.bank_offset(t.get("bank", 0)) << 4 for t in d["tiles"]}
    r, c = sym["ALT_LED_ROW"], sym["ALT_LED_COL"]
    cl = d["layout"][r][c]
    zp.check(cl.split("|")[0] == "LED_G", f"the layout's cell {c},{r} is {cl!r}, not LED_G")
    flags = ct.cell_parts(cl)[1]
    sd, cpu = game()
    try:
        def check(what):
            gap = max(cpu.rd(sym["g_alt"]) - cpu.rd(sym["g_gnd"]), 0)
            want = ("LED_R" if gap < sym["ALT_LED_RED"] else
                    "LED_A" if gap <= sym["ALT_LED_AMBER"] else "LED_G")
            got = cell(cpu, r, c)
            zp.check(got == (sym["TM_FREE"] + names.index(want), banks[want] | flags),
                     f"{what}: gap {gap} pixels, cell {got}, not {want}")
            return want
        zp.frames(cpu, 2)
        zp.check(check("on the pad") == "LED_R", "on the pad: not red")
        seen = set()
        for y in (64, 140, 250, 60):            # (cam_y: 4 or 8 units a pixel)
            cpu.wr(sym["cam_y"], y)
            cpu.wr(sym["cam_y"] + 1, 0)
            zp.frames(cpu, 1)
            seen.add(check(f"cam_y {y}"))
        zp.check("LED_G" in seen, f"never green: {seen}")
    finally:
        sd.close()


def led_test(body):
    """A level's start, the clock stopped (dt 0, so nothing flashes on its
    own); body(cpu, led, step) with led(row, col) the LED tile's name there
    and step() a call of draw_leds"""
    import os
    import sys
    sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
    import consoletiles as ct
    d = ct.load()
    names = [t["name"] for t in d["tiles"]]
    banks = {t["name"]: ct.bank_offset(t.get("bank", 0)) << 4 for t in d["tiles"]}
    sd, cpu = game()
    try:
        zp.frames(cpu, 2)

        def led(r, c):
            t, a = cell(cpu, r, c)
            n = names[t - sym["TM_FREE"]]
            zp.check(a & 0xF0 == banks[n], f"cell {c},{r}: {n} with bank attribute {a:02X}")
            return n

        def step(dt=0):
            cpu.wr(sym["dt"], dt)
            call(cpu, "draw_leds", page="PAGE_HUD")
        body(cpu, led, step)
    finally:
        sd.close()


def test_speed_led():
    """Under the S gauge: green; amber from SPEED_AMBER or reversing; red
    boosting"""
    def body(cpu, led, step):
        r, c = sym["LED_ROW"], sym["SPD_GCOL"] + 4
        for spd, boost, want in ((0, 0, "LED_G"), (sym["SPEED_AMBER"] - 1, 0, "LED_G"),
                                 (sym["SPEED_AMBER"], 0, "LED_A"), (0xFC, 0, "LED_A"),
                                 (sym["SPEED_MAX"], 1, "LED_R"), (0, 0, "LED_G")):
            cpu.wr(sym["speed"], spd)
            cpu.wr(sym["boost_on"], boost)
            step()
            zp.check(led(r, c) == want, f"speed {spd}, boost {boost}: {led(r, c)}, not {want}")
    led_test(body)


def test_integrity_led_and_beeps():
    """Right of the percentage: green, amber below 25% with a mid beep, red
    below 10% with the high beeps; once each, again after a repair"""
    def body(cpu, led, step):
        def at(hp, want, beep):
            cpu.wr(sym["sfx4_req"], 0)
            cpu.wr(sym["vtol_hp"], hp)
            step()
            got = cpu.rd(sym["sfx4_req"])
            zp.check(led(26, 25) == want, f"hp {hp}: {led(26, 25)}, not {want}")
            zp.check(got == beep, f"hp {hp}: sound {got}, not {beep}")
        mid, high = sym["SFX_WARN_MID"], sym["SFX_WARN_HIGH"]
        at(50, "LED_G", 0)
        at(13, "LED_G", 0)                      # 26%
        at(12, "LED_A", mid)                    # 24%: the beep,
        at(10, "LED_A", 0)                      # once
        at(4, "LED_R", high)                    # 8%
        at(2, "LED_R", 0)
        at(50, "LED_G", 0)                      # repaired: quiet,
        at(3, "LED_R", high)                    # and again
    led_test(body)


def test_human_led():
    """The top right LED: green; flashing bright (a second each) while a
    waiting human is within 2 cells on both axes"""
    def body(cpu, led, step):
        hum, hrec = sym["humans"], sym["HREC"]
        for k in range(sym["HUMAN_MAX"]):
            cpu.wr(hum + k * hrec + 6, 0)       # none
        cx, cz = cpu.rd(sym["cam_x"] + 2), cpu.rd(sym["cam_z"] + 2)

        def put(dx, dz, state):
            cpu.wr(hum + 1, cx + dx)
            cpu.wr(hum + 3, cz + dz)
            cpu.wr(hum + 6, state)
        cpu.wr(sym["flash_ph"], 1)
        for dx, dz, state, want in ((0, 0, 0, "LED_G"), (2, -2, sym["HS_WAIT"], "LED_G_BRIGHT"),
                                    (3, 0, sym["HS_WAIT"], "LED_G"), (-1, 3, sym["HS_WAIT"], "LED_G"),
                                    (1, 1, sym["HS_ABOARD"], "LED_G"), (-2, 1, sym["HS_WAIT"], "LED_G_BRIGHT")):
            put(dx, dz, state)
            step()
            zp.check(led(10, 37) == want, f"a human {dx},{dz} state {state}: {led(10, 37)}, not {want}")
        cpu.wr(sym["flash_t"], 50)              # a second on: back to green,
        step(25)
        zp.check(led(10, 37) == "LED_G_BRIGHT", "flashed too soon")
        step(25)
        zp.check(led(10, 37) == "LED_G", "not back to green after a second")
        step(50)                                # and bright again
        zp.check(led(10, 37) == "LED_G_BRIGHT", "not bright again after another second")
    led_test(body)


def test_wall_led():
    """The middle right LED: amber; flashing bright within 0.2 of a cell's
    edge with a building past it the VTOL isn't clear of, or the city's
    edge"""
    def body(cpu, led, step):
        grid, cmap, htab = sym["GRID"], sym["city_map"], sym["htab"]

        def height(x, z):
            k = (cpu.rd(cmap + z * grid + x) & 31) * 2
            return cpu.rd(htab + k) | cpu.rd(htab + k + 1) << 8
        # a road cell with a building to its west and roads on its other sides
        spot = next((x, z) for z in range(2, grid - 2) for x in range(2, grid - 2)
                    if height(x, z) == 0 and height(x - 1, z) > 0
                    and height(x + 1, z) == 0 and height(x, z - 1) == 0 and height(x, z + 1) == 0)
        x, z = spot
        roof = height(x - 1, z)
        cpu.wr(sym["flash_ph"], 1)

        def at(cx, fx, cz, fz, y, want):
            cpu.wr(sym["cam_x"] + 1, fx)
            cpu.wr(sym["cam_x"] + 2, cx)
            cpu.wr(sym["cam_z"] + 1, fz)
            cpu.wr(sym["cam_z"] + 2, cz)
            cpu.wr(sym["cam_y"], y & 255)
            cpu.wr(sym["cam_y"] + 1, y >> 8)
            step()
            zp.check(led(13, 37) == want, f"at {cx}+{fx}/256, {cz}+{fz}/256, y {y} (roof {roof} west "
                     f"of {spot}): {led(13, 37)}, not {want}")
        coll = sym["COLL_H"]
        at(x, 128, z, 128, 8, "LED_A")          # the middle of the road
        at(x, 50, z, 128, 8, "LED_A_BRIGHT")    # near the building
        at(x, 51, z, 128, 8, "LED_A")
        at(x, 20, z, 128, roof + coll - 1, "LED_A_BRIGHT")
        at(x, 20, z, 128, roof + coll, "LED_A")         # clear of its roof
        at(x, 220, z, 128, 8, "LED_A")          # the road side
        at(0, 10, z, 128, 8, "LED_A_BRIGHT")    # the city's edges
        at(grid - 1, 250, z, 128, 8, "LED_A_BRIGHT")
        at(x, 128, 0, 5, 8, "LED_A_BRIGHT")
        cpu.wr(sym["flash_ph"], 0)
        at(x, 50, z, 128, 8, "LED_A")           # (its dim second)
    led_test(body)


def test_enemy_led():
    """The bottom right LED: red; attacked (enemy_alert), bright a second,
    red a second, 3 times; another attack starts them again"""
    def body(cpu, led, step):
        step()
        zp.check(led(16, 37) == "LED_R", "not red to start")
        cpu.wr(sym["enemy_alert"], 1)
        seen = []
        step()
        seen.append(led(16, 37))
        zp.check(cpu.rd(sym["enemy_alert"]) == 0, "the alert not taken")
        for _ in range(6):
            step(50)
            seen.append(led(16, 37))
        want = ["LED_R_BRIGHT", "LED_R"] * 3 + ["LED_R"]
        zp.check(seen == want, f"{seen}, not {want}")
        cpu.wr(sym["enemy_alert"], 1)           # again, mid-way: from the start
        step()
        step(50)
        step(50)
        cpu.wr(sym["enemy_alert"], 1)
        step()
        n = cpu.rd(sym["en_cnt"])
        zp.check(n == 6, f"not started again: {n}")
        zp.check(led(16, 37) == "LED_R_BRIGHT", "not bright again")
    led_test(body)


def test_weapon_leds():
    """The weapon slots' LEDs (row 29, columns 30-34, in wpn_order: keys 2,
    4, 1, 5, 3) and labels (row 30): no weapon LED_OFF and
    LABEL_WPNS_EMPTY; else LABEL_WPNS and LED_G, LED_A selected, LED_R
    selected and firing, LED_R / LED_R_BRIGHT flashing out of ammo; a linked
    chain gun selected lights both its slots"""
    def body(cpu, led, step):
        order = [cpu.rd(sym["wpn_order"] + k) for k in range(5)]
        slots = sym["wpn_slots"]

        def load(*ws):                  # (type, ammo) for slots 0-4
            for k, (t, a) in enumerate(ws):
                cpu.wr(slots + 2 * k, t)
                cpu.wr(slots + 2 * k + 1, a)

        def show(sel, fire, ph):
            cpu.wr(sym["wpn_sel"], sel)
            cpu.wr(sym["fire_held"], fire)
            cpu.wr(sym["flash_ph"], ph)
            cpu.wr(sym["dt"], 0)
            call(cpu, "draw_wpn_leds", page="PAGE_HUD")
            by_slot = {}
            for k, sl in enumerate(order):
                by_slot[sl] = (led(29, 30 + k), led(30, 30 + k))
            return [by_slot[k] for k in range(5)]
        G, A, R, RB, OFF = "LED_G", "LED_A", "LED_R", "LED_R_BRIGHT", "LED_OFF"
        W, E = "LABEL_WPNS", "LABEL_WPNS_EMPTY"
        gun, rk, ms = sym["WPN_GUN"], sym["WPN_ROCKETS"], sym["WPN_MISSILE"]
        load((gun, 255), (rk, 12), (0, 0), (ms, 0), (0, 0))
        got = show(0, 0, 0)
        want = [(A, W), (G, W), (OFF, E), (R, W), (OFF, E)]
        zp.check(got == want, f"the gun selected: {got}, not {want}")
        got = show(0, 1, 1)
        want = [(R, W), (G, W), (OFF, E), (RB, W), (OFF, E)]
        zp.check(got == want, f"firing, the flash's bright second: {got}, not {want}")
        got = show(1, 0, 0)
        want = [(G, W), (A, W), (OFF, E), (R, W), (OFF, E)]
        zp.check(got == want, f"the rockets selected: {got}, not {want}")
        load((gun, 255), (rk, 12), (0, 0), (ms, 4), (0, 0))   # reloaded
        got = show(1, 0, 1)
        want = [(G, W), (A, W), (OFF, E), (G, W), (OFF, E)]
        zp.check(got == want, f"the missiles reloaded: {got}, not {want}")
        lL, lR = sym["WPN_LCHAIN_L"], sym["WPN_LCHAIN_R"]
        load((gun, 255), (0, 0), (0, 0), (lL, 90), (lR, 90))  # linked chain guns
        for sel in (3, 4):
            got = show(sel, 1, 0)
            want = [(G, W), (OFF, E), (OFF, E), (R, W), (R, W)]
            zp.check(got == want, f"a linked chain gun (slot {sel}) firing: {got}, not {want}")
        got = show(0, 0, 0)
        want = [(A, W), (OFF, E), (OFF, E), (G, W), (G, W)]
        zp.check(got == want, f"back to the gun: {got}, not {want}")
    led_test(body)


if __name__ == "__main__":
    zp.main(globals())

