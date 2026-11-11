"""The 320x256 Layer 2 graphics (layer2-320x256.asm, PAGE_L320 in slot 2):
each routine run on its own and the screen compared with what it should
draw, pixel for pixel; the display switched to 320x256 and back."""
import os
import random
import sys
import zptest as zp
from zptest import sym

sys.path.insert(0, os.path.join(zp.ROOT, "tools"))
import fontfile as ff  # noqa: E402
import imagefile as imf  # noqa: E402
import vtol_schematic as vs  # noqa: E402

FONT = ff.Font.load(ff.F12.PATH, ff.F12)    # ZPDATA/FONT12.ZPF
FONT8 = ff.Font.load(ff.F8.PATH, ff.F8)     # ZPDATA/FONT8.ZPF
GRAD8 = [dict((b, cols) for b, cols in FONT8.grads)]    # (none: [{}])

RET = 0x0000                            # a return address no routine uses
W, H = 320, 256
REGS = "BCDEHLFA"


def machine():
    sd = zp.SD()
    cpu = zp.machine(sd)
    cpu.keys = set()
    zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
    call(cpu, "l2_game_mode")           # (the menu is at 320x256: the game's set-up)
    cpu.set_nextreg(sym["L320_MMU"], sym["PAGE_L320"])
    cpu.wr(sym["l320_font"], sym["L320_F8"])    # (the menu left the large one)
    return sd, cpu


def call(cpu, name, limit=20_000_000, **regs):
    for k, v in regs.items():
        if k in ("hl", "de", "bc"):
            cpu.r[REGS.index(k[0].upper())] = v >> 8 & 255
            cpu.r[REGS.index(k[1].upper())] = v & 255
        else:
            cpu.r[REGS.index(k.upper())] = v & 255
    cpu.sp = 0xBFF0
    cpu.push(RET)
    cpu.pc = sym[name]
    t0 = cpu.t
    while cpu.pc != RET:
        cpu.step()
        if cpu.t - t0 > limit:
            raise AssertionError(f"{name} didn't return")
    return cpu.t - t0


def screen(cpu):
    """The screen as rows of colours, [y][x]"""
    p0 = sym["L320_PAGE0"]
    pages = [bytes(cpu.page(p0 + i)) for i in range(10)]
    return [[pages[x >> 5][(x & 31) * 256 + y] for x in range(W)] for y in range(H)]


def blank(c=0):
    return [[c] * W for _ in range(H)]


def diff(got, want, what):
    bad = [(x, y) for y in range(H) for x in range(W) if got[y][x] != want[y][x]]
    zp.check(not bad, f"{what}: {len(bad)} pixels differ, first {bad[:4]}")


def font(cpu):
    f = sym["font8"]
    return [[cpu.rd(f + c * 8 + r) for r in range(8)] for c in range(64)]


def put_char(m, fnt, ch, x, y, ink, paper):
    """The 8x8 glyph, in ink's gradient in FONT8.ZPF (GRAD8[0]) or flat"""
    grad = GRAD8[0].get(ink, [ink] * 8)
    c = ord(ch)
    if ord("a") <= c <= ord("z"):
        c -= 32
    c -= 32
    if not 0 <= c < 64:
        c = 0
    for r in range(8):
        for i in range(8):
            if x + i >= W:
                continue
            if fnt[c][r] & (0x80 >> i):
                m[(y + r) & 255][x + i] = grad[r]
            elif paper != sym["L320_NOPAPER"]:
                m[(y + r) & 255][x + i] = paper


def bresenham(x0, y0, x1, y1):
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx, sy = (1 if x1 >= x0 else -1), (1 if y1 >= y0 else -1)
    err = dx - dy
    while True:
        yield x0, y0
        if (x0, y0) == (x1, y1):
            return
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


def test_cls():
    sd, cpu = machine()
    with sd:
        for c in (0x00, 0x5A, 0xFF):
            t = call(cpu, "l320_cls", a=c)
            p0 = sym["L320_PAGE0"]
            zp.check(all(bytes(cpu.page(p0 + i)) == bytes([c]) * 8192 for i in range(10)),
                     f"l320_cls {c:02X}: not every byte")
        zp.note(f"l320_cls: {t:,} T (by DMA)")


def test_modes():
    sd, cpu = machine()
    with sd:
        nr = cpu.nextreg
        before = {r: nr.get(r, 0) for r in (0x15, 0x43, 0x70)}
        call(cpu, "l320_cls", a=0)
        call(cpu, "l320_mode320")
        zp.check(nr[0x70] == 0x10, f"$70 = {nr[0x70]:02X}, not 320x256")
        zp.check(nr[0x12] == sym["L2_BANK_A"], "not showing L2_BANK_A")
        zp.check((nr[0x15] >> 2) & 7 == 0, f"priority $15 = {nr[0x15]:02X}, not S L U")
        zp.check(nr[0x15] & 3 == before[0x15] & 3, "the sprite bits of $15 changed")
        zp.check(nr[0x43] & 4, "Layer 2's second palette not shown")
        zp.check(cpu.l2clip == [0, 159, 0, 255], f"clip window {cpu.l2clip}")
        pal = cpu.palettes.get(5, {})
        zp.check(all(pal.get(i) == (i << 1) | (1 if i & 3 else 0) for i in range(256)),
                 "the second palette isn't RRRGGGBB")
        call(cpu, "l320_mode320")       # again: the saved priority kept
        call(cpu, "l320_mode256")
        zp.check(nr[0x70] == 0, "not back to 256x192")
        zp.check(nr[0x15] == before[0x15], f"$15 {nr[0x15]:02X}, was {before[0x15]:02X}")
        zp.check(not nr[0x43] & 4, "still on the second palette")
        zp.check(cpu.l2clip == [0, 255, 0, 191], f"clip window {cpu.l2clip}")
        nr[0x70] = 0x55                 # once off, again does nothing
        call(cpu, "l320_mode256")
        zp.check(nr[0x70] == 0x55, "l320_mode256 changed things when already off")


def test_text():
    sd, cpu = machine()
    with sd:
        fnt = font(cpu)
        call(cpu, "l320_cls", a=0)
        m = blank()
        rnd = random.Random(3)
        chars = [chr(c) for c in range(32, 96)] + list("abcxyz{~\x7f")
        for k in range(150):
            ch = rnd.choice(chars)
            ink, paper = rnd.randint(1, 255), rnd.choice((0x12, sym["L320_NOPAPER"]))
            if ink == sym["L320_NOPAPER"]:
                ink = 1
            if k % 3:
                row, col = rnd.randint(0, 31), rnd.randint(0, 39)
                call(cpu, "l320_at", d=row, e=col)
                x, y = col * 8, row * 8
            else:
                x, y = rnd.randint(0, 319), rnd.randint(0, 248)
                call(cpu, "l320_pos", hl=x, c=y)
            cpu.wr(sym["l320_ink"], ink)
            cpu.wr(sym["l320_paper"], paper)
            t = call(cpu, "l320_char", a=ord(ch))
            put_char(m, fnt, ch, x, y, ink, paper)
            zp.check(cpu.rd16(sym["l320_cx"]) == x + 8, "l320_char didn't move on 8")
        diff(screen(cpu), m, "l320_char")
        zp.note(f"l320_char: about {t:,} T a character")

        # a string with its codes, and a table of strings
        at = sym["sg_buf"]                # (scratch: the save game's buffer)
        text = (b"AB" + bytes([1, 0x1C]) + b"cd" + bytes([2, 0xE0]) + b"E"
                + bytes([3, 5, 10]) + b"F\x07G" + b"\x00")
        for i, v in enumerate(text):
            cpu.wr(at + i, v)
        cpu.wr(sym["l320_ink"], 0xFF)
        cpu.wr(sym["l320_paper"], 0)
        call(cpu, "l320_at", d=2, e=3)
        call(cpu, "l320_print", hl=at)
        zp.check(cpu.r[4] << 8 | cpu.r[5] == at + len(text), "l320_print: HL not past the 0")
        for ch, x, y, ink, paper in (("A", 24, 16, 0xFF, 0), ("B", 32, 16, 0xFF, 0),
                                     ("C", 40, 16, 0x1C, 0), ("D", 48, 16, 0x1C, 0),
                                     ("E", 56, 16, 0x1C, 0xE0), ("F", 80, 40, 0x1C, 0xE0),
                                     ("G", 88, 40, 0x1C, 0xE0)):
            put_char(m, fnt, ch, x, y, ink, paper)
        table = bytes([10, 0, 0xFC]) + b"TOP\x00" + bytes([31, 37, 0x03]) + b"END\x00\xFF"
        for i, v in enumerate(table):
            cpu.wr(at + i, v)
        call(cpu, "l320_print_list", hl=at)
        zp.check(cpu.r[4] << 8 | cpu.r[5] == at + len(table), "l320_print_list: HL not past the $FF")
        for i, ch in enumerate("TOP"):
            put_char(m, fnt, ch, i * 8, 80, 0xFC, 0xE0)
        for i, ch in enumerate("END"):
            put_char(m, fnt, ch, 296 + i * 8, 248, 0x03, 0xE0)
        diff(screen(cpu), m, "l320_print / l320_print_list")


def test_recolour():
    sd, cpu = machine()
    with sd:
        fnt = font(cpu)
        call(cpu, "l320_cls", a=0x00)
        cpu.wr(sym["l320_ink"], 0xFF)
        cpu.wr(sym["l320_paper"], 0x00)
        m = blank()                     # a row of text, part highlighted and back
        for i, ch in enumerate("SELECT THIS ROW"):
            call(cpu, "l320_at", d=7, e=25 + i)
            call(cpu, "l320_char", a=ord(ch))
            put_char(m, fnt, ch, (25 + i) * 8, 56, 0xFF, 0x00)
        call(cpu, "l320_recolour", d=7, e=27, b=13, h=0x00, c=0x00, a=0x1C)
        for y in range(56, 64):
            for x in range(27 * 8, 40 * 8):
                m[y][x] = 0x1C if m[y][x] == 0x00 else 0x00
        diff(screen(cpu), m, "l320_recolour")
        call(cpu, "l320_recolour", d=7, e=27, b=13, h=0x1C, c=0xFF, a=0x00)
        for y in range(56, 64):
            for x in range(27 * 8, 40 * 8):
                m[y][x] = 0x00 if m[y][x] == 0x1C else 0xFF
        diff(screen(cpu), m, "l320_recolour back")

        # l320_swap: one colour in a box, the rest left
        call(cpu, "l320_fill", hl=300, c=200, de=40, b=30, a=0x55)
        for y in range(200, 230):
            for x in range(300, 320):
                m[y][x] = 0x55
        cpu.wr(sym["l320_ink"], 0x99)
        call(cpu, "l320_swap", hl=290, c=190, de=100, b=50, a=0x55)
        for y in range(190, 240):
            for x in range(290, 320):
                if m[y][x] == 0x55:
                    m[y][x] = 0x99
        diff(screen(cpu), m, "l320_swap")


def test_shapes():
    sd, cpu = machine()
    with sd:
        call(cpu, "l320_cls", a=0)
        m = blank()
        rnd = random.Random(11)
        for k in range(60):
            c = rnd.randint(1, 255)
            x, y = rnd.randint(0, 330), rnd.randint(0, 255)
            what = k % 5
            if what == 0:
                call(cpu, "l320_plot", hl=x, e=y, a=c)
                if x < W:
                    m[y][x] = c
            elif what == 1:
                w = rnd.randint(1, 320)
                call(cpu, "l320_hline", hl=x, c=y, de=w, a=c)
                for i in range(w):
                    if x + i < W:
                        m[y][x + i] = c
            elif what == 2:
                h = rnd.randint(0, 255)
                call(cpu, "l320_vline", hl=x, c=y, b=h, a=c)
                for j in range(h or 256):
                    if x < W:
                        m[(y + j) & 255][x] = c
            elif what == 3:
                w, h = rnd.randint(1, 60), rnd.randint(1, 60)
                call(cpu, "l320_fill", hl=x, c=y, de=w, b=h, a=c)
                for j in range(h):
                    for i in range(w):
                        if x + i < W:
                            m[(y + j) & 255][x + i] = c
            else:
                x, y = rnd.randint(0, 300), rnd.randint(0, 230)
                w, h = rnd.randint(1, 319 - x), rnd.randint(1, 255 - y)
                call(cpu, "l320_box", hl=x, c=y, de=w, b=h, a=c)
                for i in range(w):
                    m[y][x + i] = m[y + h - 1][x + i] = c
                for j in range(h):
                    m[y + j][x] = m[y + j][x + w - 1] = c
        diff(screen(cpu), m, "l320_plot / hline / vline / fill / box")

        call(cpu, "l320_cls", a=0)
        m = blank()
        ends = [(0, 0, 319, 255), (319, 0, 0, 255), (5, 100, 5, 100), (10, 10, 300, 10),
                (40, 250, 40, 3), (0, 128, 319, 129), (319, 255, 0, 0), (100, 0, 101, 255)]
        while len(ends) < 120:
            ends.append((rnd.randint(0, 319), rnd.randint(0, 255), rnd.randint(0, 319), rnd.randint(0, 255)))
        for k, (x0, y0, x1, y1) in enumerate(ends):
            c = 1 + k % 254
            call(cpu, "l320_line", hl=x0, c=y0, de=x1, b=y1, a=c)
            for x, y in bresenham(x0, y0, x1, y1):
                m[y][x] = c
        diff(screen(cpu), m, "l320_line")


def test_page_kept():
    """Slot 2 (the occlusion page) is put back before the game: l2_game_mode"""
    sd, cpu = machine()
    with sd:
        call(cpu, "l320_cls", a=0)
        call(cpu, "l320_mode320")
        call(cpu, "l2_game_mode")
        zp.check(cpu.mmu[2] == sym["PAGE_OCC0"], f"slot 2 has page {cpu.mmu[2]}, not the occlusion page")
        zp.check(cpu.nextreg[0x70] == 0, "l2_game_mode didn't go back to 256x192")


def colours_in_rows(cpu, row0, row1):
    """The colours in character rows row0..row1"""
    scr = screen(cpu)
    return {c for y in range(row0 * 8, row1 * 8 + 8) for c in scr[y]}


def big_has(cpu, row0, row1, base):
    """Text in colour base (its gradient's colours, or flat) in the large
    font's rows row0..row1"""
    grad = dict((b, cols) for b, cols in FONT.grads).get(base, [base])
    scr = screen(cpu)
    y0 = sym["F12_Y0"] + row0 * sym["F12_H"]
    seen = {c for y in range(y0, y0 + (row1 - row0 + 1) * sym["F12_H"]) for c in scr[y]}
    return bool(seen & set(grad))


def shown_320(cpu, what):
    zp.check(cpu.nextreg.get(0x70) == 0x10, f"{what}: not 320x256")
    zp.check(cpu.mmu[2] == sym["PAGE_L320"], f"{what}: the 320x256 page not in slot 2")


def test_screens():
    """The main menu and redefine keys are drawn at 320x256; the game, and
    the ULA end screens, are back at 256x192 with the occlusion page"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
        shown_320(cpu, "main menu")
        zp.check(cpu.page(sym["PAGE_L320"])[sym["f12_ok"] - 0x4000] == 1, "the large font not loaded")
        zp.check(big_has(cpu, 3, 3, sym["SCR_TITLE"]), "main menu: no title")
        zp.check(big_has(cpu, 9, 13, sym["SCR_TEXT"]), "main menu: no options")
        cpu.keys = {"9"}
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_KEYDEF"]), "redefine keys")
        cpu.keys = set()
        for _ in range(3):                  # (drawn, and a few scans on)
            cpu.stepi()
            zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_KEYDEF"]), "redefine keys")
        shown_320(cpu, "redefine keys")
        r0 = sym["KD_ROW0"]
        zp.check(sym["SCR_OK"] in colours_in_rows(cpu, r0, r0), "redefine keys: first control not highlighted")
        zp.check(sym["SCR_OK"] not in colours_in_rows(cpu, r0 + 1, r0 + sym["KD_VIS"] - 1),
                 "redefine keys: more than one highlighted")
        zp.check(sym["SCR_TEXT"] in colours_in_rows(cpu, r0 + sym["KD_VIS"] - 1, r0 + sym["KD_VIS"] - 1),
                 "redefine keys: the last control not shown")
        cpu.keys = {"1"}                    # back
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu again")
        shown_320(cpu, "main menu again")
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.check(cpu.nextreg.get(0x70) == 0, "the game isn't at 256x192")
        zp.check(cpu.mmu[2] == sym["PAGE_OCC0"], "the game hasn't the occlusion page in slot 2")
        zp.check(not cpu.nextreg.get(0x43, 0) & 4, "the game is on Layer 2's second palette")
        zp.check(cpu.l2clip == [0, 255, 0, 191], f"the game's clip window {cpu.l2clip}")
        cpu.pc = sym["level_complete_screen"]   # LEVEL COMPLETE, then the load-out
        cpu.set_nextreg(0x56, sym["PAGE_LEVELEND"])
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LEVELEND"]), "LEVEL COMPLETE")
        shown_320(cpu, "level complete")
        zp.check(big_has(cpu, sym["LE_TITLE_ROW"], sym["LE_TITLE_ROW"], sym["SCR_TITLE"]),
                 "level complete: no title")
        zp.check(big_has(cpu, sym["LE_SAVED_ROW"], sym["LE_REARM_ROW"], sym["SCR_TEXT"]),
                 "level complete: no salvage lines")
        zp.check(big_has(cpu, sym["LE_PROMPT_ROW"], sym["LE_PROMPT_ROW"], sym["SCR_HELP"]),
                 "level complete: no PRESS SPACE")
        cpu.keys = {" "}
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        cpu.keys = set()
        for _ in range(2):
            cpu.stepi()
            zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        shown_320(cpu, "load-out")
        r0 = sym["LO_ROW0"]
        zp.check(sym["SCR_TITLE"] in colours_in_rows(cpu, r0, r0 + 2 * 4), "load-out: no selected slot")
        zp.check(big_has(cpu, sym["LO_START_ROW"], sym["LO_START_ROW"], sym["SCR_TEXT"]),
                 "load-out: no START LEVEL")
        cpu.keys = {"0"}                    # and on into the game: 256x192 again
        zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "the next level")
        cpu.keys = set()
        zp.check(cpu.nextreg.get(0x70) == 0 and cpu.mmu[2] == sym["PAGE_OCC0"], "the next level isn't on the game's set-up")
        cpu.pc = sym["game_over_screen"]    # a ULA screen
        cpu.set_nextreg(0x56, sym["PAGE_MENU"])
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "GAME OVER")
        zp.check(cpu.nextreg.get(0x70) == 0 and cpu.mmu[2] == sym["PAGE_OCC0"], "GAME OVER not on the ULA set-up")


def put_char12(m, ch, x, y, ink, paper):
    c = ch.upper()
    if not FONT.glyphs.get(c):
        c = " "
    grad = dict((b, cols) for b, cols in FONT.grads).get(ink, [ink] * ff.H)
    for row in range(ff.H):
        for col in range(ff.W):
            if x + col >= W:
                continue
            if FONT.glyphs[c][row][col]:
                m[(y + row) & 255][x + col] = grad[row]
            elif paper != sym["L320_NOPAPER"]:
                m[(y + row) & 255][x + col] = paper


def test_font_file():
    """ZPDATA/FONT8.ZPF and FONT12.ZPF are ones the game takes, and fontfile
    reads and writes them unchanged; the game's idea of the format is
    fontfile's; the built-in font8 (tables_font.inc) is FONT8.ZPF's"""
    for sp in (ff.F8, ff.F12):
        data = open(sp.PATH, "rb").read()
        ff.check(data, sp)
        zp.check(ff.Font.from_bytes(data).to_bytes() == data, f"fontfile doesn't write back {sp.PATH}")
    for k, v in (("F8_H", ff.F8.H), ("F8_FIRST", ff.F8.FIRST), ("F8_COUNT", ff.F8.COUNT),
                 ("F8_BPR", ff.F8.BPR), ("F8_SIZE_MAX", ff.F8.SIZE_MAX)):
        zp.check(sym[k] == v, f"{k} {sym[k]} in the game, {v} in fontfile.py")
    with zp.SD() as sd:                 # (not loaded yet: the built-in one)
        cpu = zp.machine(sd)
        main = cpu.page(sym["PAGE_MAIN"])     # (slot 5 not mapped yet)
        built = bytes(main[sym["font8"] - 0xA000 + i] for i in range(64 * 8))
    zp.check(built == ff.font8_rows(), "the built-in font8 isn't FONT8.ZPF's: rebuild")
    for k, v in (("F12_W", ff.W), ("F12_H", ff.H), ("F12_FIRST", ff.FIRST), ("F12_COUNT", ff.COUNT),
                 ("F12_BPR", ff.BPR), ("F12_HEADER", ff.HEADER), ("F12_GRAD_MAX", ff.GRAD_MAX),
                 ("F12_SIZE_MAX", ff.SIZE_MAX)):
        zp.check(sym[k] == v, f"{k} {sym[k]} in the game, {v} in fontfile.py")


def test_large_font():
    """l320_char12: each character's cell in its colour's gradient (or flat),
    pixel for pixel; the position on 12; l320_at on the large grid"""
    sd, cpu = machine()
    with sd:
        zp.check(cpu.page(sym["PAGE_L320"])[sym["f12_ok"] - 0x4000] == 1, "the large font not loaded")
        call(cpu, "l320_cls", a=0)
        cpu.wr(sym["l320_font"], sym["L320_F12"])
        m = blank()
        rnd = random.Random(12)
        chars = [chr(c) for c in range(32, 91)] + list("az{~")
        inks = [b for b, _ in FONT.grads] + [0x49, 0x92]
        for k in range(120):
            ch = rnd.choice(chars)
            ink = rnd.choice(inks)
            paper = rnd.choice((0x12, sym["L320_NOPAPER"]))
            if k % 2:
                row, col = rnd.randint(0, 24), rnd.randint(0, 25)
                call(cpu, "l320_at", d=row, e=col)
                x, y = sym["F12_X0"] + col * 12, sym["F12_Y0"] + row * 10
            else:
                x, y = rnd.randint(0, 319), rnd.randint(0, 246)
                call(cpu, "l320_pos", hl=x, c=y)
            cpu.wr(sym["l320_ink"], ink)
            cpu.wr(sym["l320_paper"], paper)
            t = call(cpu, "l320_char", a=ord(ch))
            put_char12(m, ch, x, y, ink, paper)
            zp.check(cpu.rd16(sym["l320_cx"]) == x + 12, "l320_char (large) didn't move on 12")
        diff(screen(cpu), m, "l320_char (large font)")
        zp.note(f"l320_char (large font): about {t:,} T a character")


def test_no_font_file():
    """Without FONT12.ZPF (or with a bad one) the large grid keeps its
    places, each cell with the 8x8 glyph"""
    for drop, bad in ((("FONT12.ZPF",), None), ((), b"ZPFN" + bytes(20))):
        sd = zp.SD(drop=drop)
        if bad is not None:
            with open(sd.path("FONT12.ZPF"), "wb") as fh:
                fh.write(bad)
        with sd:
            cpu = zp.machine(sd)
            zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
            zp.check(cpu.page(sym["PAGE_L320"])[sym["f12_ok"] - 0x4000] == 0,
                     "a missing or bad font file taken")
            call(cpu, "l2_game_mode")
            cpu.set_nextreg(sym["L320_MMU"], sym["PAGE_L320"])
            fnt = font(cpu)
            call(cpu, "l320_cls", a=0)
            cpu.wr(sym["l320_font"], sym["L320_F12"])
            cpu.wr(sym["l320_ink"], 0xFF)
            cpu.wr(sym["l320_paper"], 0)
            m = blank()
            for i, ch in enumerate("Z-POLICE"):
                call(cpu, "l320_at", d=4, e=3 + i)
                call(cpu, "l320_char", a=ord(ch))
                put_char(m, fnt, ch, sym["F12_X0"] + (3 + i) * 12 + 2, sym["F12_Y0"] + 40 + 1, 0xFF, 0)
                zp.check(cpu.rd16(sym["l320_cx"]) == sym["F12_X0"] + (4 + i) * 12, "not on 12")
            diff(screen(cpu), m, "the 8x8 glyphs in the large cells")


def test_font8_file():
    """FONT8.ZPF's glyphs go over the built-in font8 at start-up (the ULA
    screens use them too), and its gradients colour the 8x8 text on the
    320x256 screens; without it (or with a bad one) the built-in font, flat"""
    edited = ff.Font.load(ff.F8.PATH, ff.F8)
    edited.glyphs["A"] = [[x == y for x in range(8)] for y in range(8)]   # (a mark)
    for case in ("edited", "none", "bad"):
        sd = zp.SD(drop=("FONT8.ZPF",) if case == "none" else ())
        if case == "edited":
            edited.save(sd.path("FONT8.ZPF"))
        if case == "bad":
            with open(sd.path("FONT8.ZPF"), "wb") as fh:
                fh.write(edited.to_bytes()[:-1])
        with sd:
            cpu = zp.machine(sd)
            zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
            ok = cpu.page(sym["PAGE_L320"])[sym["f8_ok"] - 0x4000]
            zp.check(ok == (case == "edited"), f"{case}: f8_ok {ok}")
            got = bytes(cpu.rd(sym["font8"] + i) for i in range(64 * 8))
            want = (edited.to_bytes()[12:12 + 512] if case == "edited" else ff.font8_rows())
            zp.check(got == want, f"{case}: font8 isn't the {'file' if case == 'edited' else 'built-in'} one")
            call(cpu, "l2_game_mode")
            cpu.set_nextreg(sym["L320_MMU"], sym["PAGE_L320"])
            cpu.wr(sym["l320_font"], sym["L320_F8"])
            call(cpu, "l320_cls", a=0)
            cpu.wr(sym["l320_paper"], 0)
            fnt = font(cpu)
            GRAD8[0] = dict((b, cols) for b, cols in edited.grads) if case == "edited" else {}
            try:
                m = blank()
                for i, (ch, ink) in enumerate(zip("AZ09:", (0xFF, 0xFC, 0x1C, 0x49, 0xE0))):
                    cpu.wr(sym["l320_ink"], ink)
                    call(cpu, "l320_at", d=3, e=2 + i)
                    call(cpu, "l320_char", a=ord(ch))
                    put_char(m, fnt, ch, (2 + i) * 8, 24, ink, 0)
                diff(screen(cpu), m, f"{case}: the 8x8 text in its gradients")
            finally:
                GRAD8[0] = dict((b, cols) for b, cols in FONT8.grads)


def image_bytes(x, y, w, h, rnd):
    """A random image (some pixels clear) in the box, as a file"""
    im = imf.Image()
    for cx in range(x, x + w):
        for cy in range(y, y + h):
            v = rnd.randint(0, 255)
            im.set(cx, cy, imf.CLEAR if v < 60 else v)
    im.set(x, y, 0x11)                      # (the corners drawn: the box is it)
    im.set(x + w - 1, y + h - 1, 0x22)
    return im, im.to_bytes()


def test_image():
    """l320_image: an image file from the SD card drawn at its place, pixel
    for pixel, its clear pixels leaving the screen; read in strips (many
    columns a read, or one when 256 high); carry set, and nothing drawn,
    without the file or with a bad one"""
    rnd = random.Random(21)
    cases = [(100, 20, 60, 40), (0, 0, 7, 256), (250, 200, 70, 56), (3, 9, 317, 23)]
    with zp.SD() as sd:
        for i, (x, y, w, h) in enumerate(cases):
            im, data = image_bytes(x, y, w, h, rnd)
            with open(sd.path(f"T{i}.ZPI"), "wb") as fh:
                fh.write(data)
        over = bytearray(image_bytes(300, 0, 20, 10, rnd)[1])
        over[5:7] = (310).to_bytes(2, "little")             # off the right edge
        with open(sd.path("OVER.ZPI"), "wb") as fh:
            fh.write(over)
        _, short = image_bytes(10, 10, 30, 30, rnd)
        with open(sd.path("SHORT.ZPI"), "wb") as fh:
            fh.write(short[:-5])
        with open(sd.path("BAD1.ZPI"), "wb") as fh:
            fh.write(b"ZPIX" + bytes(12))
        cpu = zp.machine(sd)
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
        call(cpu, "l2_game_mode")
        cpu.set_nextreg(sym["L320_MMU"], sym["PAGE_L320"])
        name = sym["sg_buf"]

        def draw(fname):
            for k, ch in enumerate(f"ZPDATA/{fname}".encode() + bytes(1)):
                cpu.wr(name + k, ch)
            t = call(cpu, "l320_image", hl=name, limit=200_000_000)
            zp.check(cpu.mmu[7] == sym["PAGE_INPUT"], "the input page not back in slot 7")
            return cpu.r[REGS.index("F")] & 1, t

        rnd2 = random.Random(5)
        for i, (x, y, w, h) in enumerate(cases):
            back = rnd2.randint(1, 255)
            call(cpu, "l320_cls", a=back)
            m = blank(back)
            im = imf.Image.load(sd.path(f"T{i}.ZPI"))
            for cy in range(256):
                for cx in range(W):
                    v = im.get(cx, cy)
                    if v != imf.CLEAR:
                        m[cy][cx] = v
            cf, t = draw(f"T{i}.ZPI")
            zp.check(not cf, f"T{i}.ZPI: carry set")
            diff(screen(cpu), m, f"image {i} ({x}, {y}) {w} x {h}")
            zp.note(f"l320_image {w} x {h}: {t:,} T (with the emulator's file calls)")
        for bad in ("NOPE.ZPI", "BAD1.ZPI", "OVER.ZPI"):
            call(cpu, "l320_cls", a=0x33)
            cf, _ = draw(bad)
            zp.check(cf, f"{bad}: carry clear")
            diff(screen(cpu), blank(0x33), f"{bad}: drew something")
        cf, _ = draw("SHORT.ZPI")
        zp.check(cf, "SHORT.ZPI (cut short): carry clear")


def test_vtol_image():
    """ZPDATA/VTOL.ZPI is an image the game takes, imagefile writes back what
    it reads, and the load-out's hardpoints (lo_hp) are tools/vtol_schematic's"""
    data = open(vs.PATH, "rb").read()
    imf.check(data)
    zp.check(imf.Image.from_bytes(data).to_bytes() == data, "imagefile doesn't write back VTOL.ZPI")
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        page = cpu.page(sym["PAGE_LOADOUT"])
        at = sym["lo_hp"] - 0xC000
        n = sym["LO_HP_SIZE"]
        for slot in range(1, 6):
            e = page[at + n * (slot - 1):at + n * slot]
            hp = (e[0] | e[1] << 8, e[2])
            lb = (e[3] | e[4] << 8, e[5])
            bx = (e[6], e[7])
            zp.check(hp == vs.HARDPOINTS[slot], f"slot {slot}: lo_hp {hp}, vtol_schematic {vs.HARDPOINTS[slot]}")
            zp.check(lb == vs.LABELS[slot], f"slot {slot}: label {lb}, vtol_schematic {vs.LABELS[slot]}")
            zp.check(bx == vs.BOXES[slot], f"slot {slot}: box {bx}, vtol_schematic {vs.BOXES[slot]}")


def bg_copy(cpu):
    """The background copy (PAGE_L320_BG on) as rows of colours, [y][x]"""
    p0 = sym["PAGE_L320_BG"]
    pages = [bytes(cpu.page(p0 + i)) for i in range(10)]
    return [[pages[x >> 5][(x & 31) * 256 + y] for x in range(W)] for y in range(H)]


def test_loadout_vtol():
    """The load-out draws VTOL.ZPI first, as the background, and keeps a copy
    of it; its text is printed over the picture (no paper); a box at each
    slot's hardpoint, the selected slot's yellow; a field that changes gets
    the background back under it"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        cpu.keys = {"1"}
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        for keys in (set(), {"3"}, set()):
            cpu.keys = keys
            cpu.stepi()
            zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        bg = bg_copy(cpu)
        m = blank(sym["SCR_BG"])            # the plain screen (l320_screen), the
        for k, col in ((0, sym["SCR_FRAME"]), (2, sym["SCR_FRAME2"])):     # picture over it
            for x in range(k, W - k):
                m[k][x] = m[H - 1 - k][x] = col
            for y in range(k, H - k):
                m[y][k] = m[y][W - 1 - k] = col
        im = imf.Image.load(vs.PATH)
        for y in range(H):
            for x in range(W):
                if im.get(x, y) != imf.CLEAR:
                    m[y][x] = im.get(x, y)
        diff(bg, m, "the background copy")
        scr = screen(cpu)
        for slot, (hx, hy) in vs.HARDPOINTS.items():
            w, h = vs.BOXES[slot]
            want = sym["SCR_TITLE"] if slot == 3 else sym["SCR_FRAME2"]
            x0, y0 = hx - w // 2, hy - h // 2
            for x, y in ((x0, y0), (x0 + w - 1, y0), (x0, y0 + h - 1), (x0 + w - 1, y0 + h - 1)):
                zp.check(scr[y][x] == want, f"slot {slot}'s box at ({x}, {y}): {scr[y][x]:02X}, not {want:02X}")
        title = set(dict((b_, cols) for b_, cols in FONT.grads)[sym["SCR_TITLE"]])
        y0 = sym["F12_Y0"] + sym["LO_TITLE_ROW"] * sym["F12_H"]
        cells = [(x, y) for y in range(y0, y0 + 10) for x in range(W)]
        ink = [(x, y) for x, y in cells if scr[y][x] != bg[y][x]]
        zp.check(ink and all(scr[y][x] in title for x, y in ink),
                 "the title isn't printed over the picture (some paper, or none of it)")
        cpu.keys = {"1"}                    # slot 1, then U: MACHINE GUN -> EMPTY
        cpu.stepi()
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        cpu.keys = {"U"}
        cpu.stepi()
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_LOADOUT"]), "the load-out")
        cpu.keys = set()
        zp.check(cpu.rd(sym["wpn_slots"]) == 0, "slot 1 not unloaded")
        scr = screen(cpu)
        x0 = (sym["LO_SLOT_COL"] + 2 + 5) * 8   # past "EMPTY": the old name's end
        y0 = sym["LO_SROW0"] * 8
        left = [(x, y) for y in range(y0, y0 + 8) for x in range(x0, x0 + 6 * 8) if scr[y][x] != bg[y][x]]
        zp.check(not left, f"the old name not cleared: {len(left)} pixels, first {left[:4]}")


def plain_screen():
    """l320_screen's: SCR_BG, the frame"""
    m = blank(sym["SCR_BG"])
    for k, col in ((0, sym["SCR_FRAME"]), (2, sym["SCR_FRAME2"])):
        for x in range(k, W - k):
            m[k][x] = m[H - 1 - k][x] = col
        for y in range(k, H - k):
            m[y][k] = m[y][W - 1 - k] = col
    return m


def test_mainmenu_image():
    """The main menu draws ZPDATA/MAINMENU.ZPI first, then its text over it
    (no paper): every pixel is the picture's (over the plain screen), but for
    the text's own, in the text's rows"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MAINMENU"]), "the main menu")
        m = plain_screen()
        im = imf.Image.load(os.path.join(imf.DATA, "MAINMENU.ZPI"))
        for y in range(H):
            for x in range(W):
                if im.get(x, y) != imf.CLEAR:
                    m[y][x] = im.get(x, y)
        scr = screen(cpu)
        grads = dict((b, cols) for b, cols in FONT.grads)
        text = set(grads[sym["SCR_TITLE"]]) | set(grads[sym["SCR_TEXT"]])
        rows = set()
        for r in (3, 9, 11, 13):            # mm_text's rows (large font)
            y0 = sym["F12_Y0"] + r * sym["F12_H"]
            rows |= set(range(y0, y0 + sym["F12_H"]))
        bad = [(x, y) for y in range(H) for x in range(W)
               if scr[y][x] != m[y][x] and not (y in rows and scr[y][x] in text)]
        zp.check(not bad, f"{len(bad)} pixels neither the picture's nor the text's, first {bad[:4]}")
        drawn = sum(1 for y in rows for x in range(W) if scr[y][x] != m[y][x])
        zp.check(drawn > 200, f"the text not drawn over the picture ({drawn} pixels)")


if __name__ == "__main__":
    zp.main(globals())
