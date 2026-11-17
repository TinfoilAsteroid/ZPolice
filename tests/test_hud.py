"""The panel: a weapon slot in use shows its slot number above its bar, its ammo
down the bar, hundreds first (INF for infinite), and its weapon's letter; an
unused one has none of them.  The viewport's frame is hardware sprites, set
once and put back after the menus hide them.
"""
import zptest as zp
from zptest import sym

GLYPH = {str(d): d for d in range(10)} | {" ": sym["GLYPH_SPACE"], "I": sym["GLYPH_I"], "N": sym["GLYPH_N"],
                                          "F": sym["GLYPH_F"], "M": sym["GLYPH_M"], "R": sym["GLYPH_R"]}
ORDER = [1, 3, 0, 4, 2]                 # the slots, left to right (keys 2 4 1 5 3)


def cell(cpu, col, row):
    """The 8 bitmap lines of a ULA character cell (the bottom third)."""
    ula = bytes(cpu.page(10))
    base = 0x1000 + (row - 16) * 32 + col
    return bytes(ula[base + 256 * n] for n in range(8))


def glyph(cpu, ch):
    hud = bytes(cpu.page(sym["PAGE_HUD"]))
    a = sym["font"] - 0xE000 + 8 * GLYPH[ch]
    return hud[a:a + 8]


def column(slot):
    return sym["WPN_COL0"] + 2 * ORDER.index(slot)


def strip(b):
    """A cell without the selected slot's lines (in the number's and letter's)."""
    return b[1:7]


def shows(cpu, slot, text, letter, number):
    c = column(slot)
    rows = [(sym["WPN_NUM_ROW"], number)]
    rows += [(sym["WPN_ROW"] + k, t) for k, t in enumerate(text)]
    rows += [(sym["WPN_LTR_ROW"], letter)]
    for row, ch in rows:
        got, want = strip(cell(cpu, c, row)), strip(glyph(cpu, ch))
        zp.check(got == want, f"slot {slot + 1}, row {row}: not {ch!r}: {got.hex()} / {want.hex()}")


def game():
    sd = zp.SD()
    cpu = zp.machine(sd)
    zp.start_game(cpu)
    zp.frames(cpu, 2)
    return sd, cpu


def test_slots():
    sd, cpu = game()
    try:
        shows(cpu, 0, "INF", "M", "1")      # the machine gun
        shows(cpu, 1, "   ", " ", " ")      # unused: no number
        W = sym["wpn_slots"]
        cpu.wr(W + 2 * 3, sym["WPN_ROCKETS"])
        cpu.wr(W + 2 * 3 + 1, 12)
        zp.frames(cpu, 2)
        shows(cpu, 3, "012", "R", "4")
        cpu.wr(W + 2 * 3 + 1, 137)
        zp.frames(cpu, 2)
        shows(cpu, 3, "137", "R", "4")
        attr = bytes(cpu.page(10))[0x1800 + sym["WPN_ROW"] * 32 + column(3)]
        zp.check((attr >> 3) & 7 == sym["C_OK"], "a slot with ammo isn't green")
        cpu.wr(W + 2 * 3 + 1, 0)
        zp.frames(cpu, 2)
        shows(cpu, 3, "000", "R", "4")
        attr = bytes(cpu.page(10))[0x1800 + sym["WPN_ROW"] * 32 + column(3)]
        zp.check((attr >> 3) & 7 == sym["C_WARN"], "a slot out of ammo isn't red")
    finally:
        sd.close()


def test_selected():
    sd, cpu = game()
    try:
        c = column(0)
        num, ltr = sym["WPN_NUM_ROW"], sym["WPN_LTR_ROW"]
        zp.check(cell(cpu, c, num)[7] == 0xFF and cell(cpu, c, ltr)[0] == 0xFF, "the selected slot has no lines")
        attrs = bytes(cpu.page(10))[0x1800:]
        for row in (num, ltr):
            zp.check(attrs[row * 32 + c] & 7 == sym["C_YEL"], f"row {row} of the selected slot isn't yellow")
        for k in range(sym["WPN_BAR"]):
            row = sym["WPN_ROW"] + k
            zp.check(attrs[row * 32 + c] & 7 == 0, f"row {row} of the selected slot's bar isn't black ink")
            zp.check(attrs[row * 32 + column(1)] & 7 == 0, f"row {row} of an unselected bar isn't black ink")
        o = column(4)
        zp.check(cell(cpu, o, num)[7] == 0 and cell(cpu, o, ltr)[0] == 0, "an unselected slot has a line")
    finally:
        sd.close()


def test_frame():
    sd, cpu = game()
    try:
        first, n = sym["FRM_SPR0"], sym["FRM_COUNT"]
        vis = [cpu.spr_attr[first + k][3] & 0x80 for k in range(n)]
        corners = 4                             # (the first four: FRM_CORNERS;
        want = ([bool(sym["FRM_CORNERS"])] * corners      # the rest: FRM_EDGES)
                + [bool(sym["FRM_EDGES"])] * (n - corners))
        zp.check([bool(v) for v in vis] == want, f"the frame's sprites shown {vis}, not as "
                 f"FRM_CORNERS {sym['FRM_CORNERS']}, FRM_EDGES {sym['FRM_EDGES']} say")
        x = lambda a: a[0] | (a[2] & 1) << 8   # (9 bits: the MSB in attribute 2)
        tl, tr = cpu.spr_attr[first], cpu.spr_attr[first + 1]
        zp.check((x(tl), tl[1]) == (33, 33), f"the top left corner at {x(tl)},{tl[1]}, not 33,33")
        zp.check((x(tr), tr[1]) == (32 + 256 - 16 - 1, 33), f"the top right corner at {x(tr)},{tr[1]}")
        bl, br = cpu.spr_attr[first + 2], cpu.spr_attr[first + 3]
        zp.check(x(bl) == 33 and x(br) == 32 + 256 - 16 - 1, "the bottom corners not 1 pixel in")
        zp.check(bl[1] == br[1] == 32 + sym["VIEW_H"] - 16, "the bottom corners moved up or down")
        top = cpu.spr_attr[first + 4]
        zp.check((top[4] >> 3) & 3 == 3, "the top edge isn't stretched")
    finally:
        sd.close()


if __name__ == "__main__":
    zp.main(globals())
