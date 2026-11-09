"""The 320x256 Layer 2 graphics (layer2-320x256.asm, PAGE_L320 in slot 2):
each routine run on its own and the screen compared with what it should
draw, pixel for pixel; the display switched to 320x256 and back."""
import random
import zptest as zp
from zptest import sym

RET = 0x0000                            # a return address no routine uses
W, H = 320, 256
REGS = "BCDEHLFA"


def machine():
    sd = zp.SD()
    cpu = zp.machine(sd)
    cpu.keys = set()
    zp.run_until(cpu, lambda: zp.at_scan(cpu, sym["PAGE_MENU"]), "the main menu")
    cpu.set_nextreg(sym["L320_MMU"], sym["PAGE_L320"])
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
                m[(y + r) & 255][x + i] = ink
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


if __name__ == "__main__":
    zp.main(globals())
