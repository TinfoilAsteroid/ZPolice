"""A level's start: PREPARE FOR COMBAT over the view after the first frame,
for at least WPREP_TICKS interrupts (2 s: isr_ticks); and the figures' last
pages, shared with the load-out's background copy (PAGE_L320_BG), read back
from the graphics file then (gfx_reload), or the load error screen if they
can't be.  (Every other test skips the wait: zptest.machine.)
"""
import os

import zptest as zp
from zptest import sym

GFX = "SPRITEHW.ZPG" if "fq_cmds" in sym else "SPRITES.ZPG"


def attrs(cpu, row, col, n):
    """n ULA attribute bytes from character row, column"""
    ula = cpu.page(sym["PAGE_ULA0"])
    a = 0x1800 + row * 32 + col
    return bytes(ula[a:a + n])


def chars(cpu, row, col, n):
    """The pixel bytes of n characters (all 8 lines)"""
    ula = cpu.page(sym["PAGE_ULA0"])
    out = b""
    for k in range(8):
        a = ((row & 0x18) << 8) | (k << 8) | ((row & 7) << 5) | col
        out += bytes(ula[a:a + n])
    return out


def test_box_and_wait():
    """The box, held until isr_ticks reaches WPREP_TICKS, then gone"""
    row, col, wait = sym["WPREP_ROW"], sym["WPREP_COL"], sym["WPREP_TICKS"]
    n = sym["txt_wprep_off"] - sym["txt_wprep"] - 1
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        cpu.trap_pc = -1                       # (the real wait)
        zp.run_until(cpu, lambda: cpu.pc == sym["wp_wait"], "the wait")
        zp.check(attrs(cpu, row, col, n) == bytes([sym["PAUSE_ATTR"]]) * n,
                 f"no box: attributes {attrs(cpu, row, col, n).hex()}")
        zp.check(any(chars(cpu, row, col, n)), "the box has no text")
        txt = bytes(cpu.rd(sym["txt_wprep"] + i) for i in range(n)).decode()
        zp.check(txt.strip() == "PREPARE FOR COMBAT", f"the text: {txt!r}")
        lo, hi = sym["wp_wait"], sym["txt_wprep"]
        for ticks in (0, wait - 1):
            cpu.wr(sym["isr_ticks"], ticks & 255)
            cpu.wr(sym["isr_ticks"] + 1, ticks >> 8)
            for _ in range(20000):
                cpu.step()
                zp.check(lo <= cpu.pc < hi, f"left the wait at {ticks} ticks (pc {cpu.pc:04X})")
        cpu.wr(sym["isr_ticks"], wait & 255)
        cpu.wr(sym["isr_ticks"] + 1, wait >> 8)
        zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "the game after the wait")
        zp.check(attrs(cpu, row, col, n) == bytes([sym["VIEW_ATTR"]]) * n, "the box is still there")


def test_ticks():
    """The interrupt counts isr_ticks"""
    with zp.SD() as sd:
        cpu = zp.machine(sd, interrupts=True)
        zp.start_game(cpu)
        cpu.wr(sym["isr_ticks"], 0)
        cpu.wr(sym["isr_ticks"] + 1, 0)
        zp.frames(cpu, 3)
        zp.check(cpu.rd16(sym["isr_ticks"]) > 0, "isr_ticks didn't count")


def padded(sd):
    """The graphics file made GFX_PAGES_MAX pages, the added ones a pattern
    (so it reaches the shared pages): its pages"""
    path = sd.path(GFX)
    data = bytearray(open(path, "rb").read())
    h, n, full = sym["GFX_HEADER"], data[5], sym["GFX_PAGES_MAX"]
    pages = [bytes(data[h + i * 8192:h + (i + 1) * 8192]) for i in range(n)]
    pages += [bytes((i * 37 + j) & 255 for j in range(8192)) for i in range(n, full)]
    data[5] = full
    open(path, "wb").write(bytes(data[:h]) + b"".join(pages))
    return pages


def test_shared_pages_read_back():
    """The load-out's background over the figures' last pages: no figures in
    the first frame, then the pages read back from the file"""
    shared, bg = sym["GFX_SHARED"], sym["PAGE_L320_BG"]
    with zp.SD() as sd:
        pages = padded(sd)
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.check(cpu.rd(sym["shared_pg"]) == 1, "the load-out didn't mark the shared pages taken")
        zp.check(cpu.rd(sym["gfx_ok"]) == 0, "figures allowed while their pages are the background's")
        zp.check(bytes(cpu.page(bg)) != pages[shared], "the background copy isn't over the shared pages")
        zp.run_until(cpu, lambda: cpu.pc == sym["wp_wait"], "the wait")
        zp.check(cpu.rd(sym["shared_pg"]) == 0 and cpu.rd(sym["gfx_ok"]) == 1, "not read back")
        bad = [p for p in range(shared, len(pages)) if bytes(cpu.page(sym["PAGE_GFX0"] + p)) != pages[p]]
        zp.check(not bad, f"graphics pages {bad} not as the file")
        zp.frames(cpu, 2)


def test_unshared_file_not_read():
    """A graphics file short of the shared pages (as now): nothing read back,
    the figures on from the first frame"""
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        zp.check(cpu.rd(sym["gfx_ok"]) == 1, "figures off at the level's start")
        calls = len(cpu.esx_log)
        zp.frames(cpu, 2)
        zp.check(cpu.rd(sym["shared_pg"]) == 0, "shared_pg not cleared")
        zp.check(len(cpu.esx_log) == calls, "the SD card was read for nothing")


def test_read_back_fails():
    """The file gone (the SD card at fault): the load error screen"""
    with zp.SD() as sd:
        padded(sd)
        cpu = zp.machine(sd)
        zp.start_game(cpu)
        os.remove(sd.path(GFX))
        zp.run_until(cpu, lambda: cpu.pc == sym["load_error_screen"] and cpu.mmu[6] == sym["PAGE_MENU"],
                     "the load error screen")
        zp.run_until(cpu, lambda: cpu.pc == sym["menu_frame"], "its wait")
        zp.check((cpu.nextreg.get(0x70, 0) >> 4) & 3 == 1 and cpu.rd(sym["l320_font"]) == sym["L320_F12"],
                 "the load error not 320x256 in the large font")
        zp.run_until(cpu, lambda: cpu.pc == sym["main_menu"], "the main menu after it",
                     limit=400 * zp.FRAME_T)


if __name__ == "__main__":
    zp.main(globals())
