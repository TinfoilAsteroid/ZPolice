"""Preview a city as the game draws it, from a chosen point, using the
emulator (tools/nexsim.py) and the built game (zpolice.nex):

    python tools/preview.py maps/CITYnn.json X Z [--heading DEG]
                            [--height UNITS] [--level N] [--palette FILE.json]
                            [--out FILE.png]

X, Z: the map cell to stand the VTOL in (0..63; z up the map is north).
--heading: degrees, 0 north (up the map), 90 east (right); default 0.
--height: the camera's height in world units (8..192, 128 a height level);
default 120.  --level: the level to play (default the city's first level,
from ZPDATA); its own map changes aren't applied (the map given is drawn as
it is).  --palette: a level palette file (tools/levelpal.py) to play the
level in (as levels/LEVELnn_PAL.json; default: the level's own from ZPDATA,
if it has one, else the city's).  --out: the PNG to write (default
preview.png).

It builds a temporary SD card: the city's ZPDATA/CITYnn.ZPC with this map
(and its hand-set palette shades) in place of the built one, and the level's
file.  Then it starts the game, goes to the level, puts the VTOL there and
draws a frame.  It takes a little while (the emulator is slow): the map
editor runs it in the background (View > Preview from a point).
"""
import argparse
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import citymap as cm
import levelpal as lp
import nexsim
import spritefile as sf

ROOT = os.path.dirname(HERE)
DATA_DIR = os.path.join(ROOT, "ZPDATA")
NEX = os.path.join(ROOT, "zpolice.nex")
SYM = os.path.join(ROOT, "zpolice.sym")
GRID = cm.GRID


def pal_pair(c):
    r, g, b = c
    return bytes(((r << 5) | (g << 2) | (b >> 1), b & 1))


def city_file(m, built):
    """The city's ZPC bytes with map m (cm.load's) in place of the built
    one's map, colours and palette."""
    n = m["city"]
    pal = cm.read_generated(n, os.path.join(ROOT, "maps"))
    if pal is None:                     # (not built since generated palettes)
        pal = [((built[32 + 2 * i] >> 5), (built[32 + 2 * i] >> 2) & 7,
                ((built[32 + 2 * i] & 3) << 1) | (built[33 + 2 * i] & 1)) for i in range(256)]
    cm.apply_palette(pal, m["palette"])
    sf.apply_palette(pal, sf.load_palette())    # the figures' colours
    col = []
    for code, fam in zip(m["cells"], m["fams"]):
        f = cm.family_for(code, fam)
        col.append(cm.city_col(f) if isinstance(f, int) else cm.GROUND_IDX)
    return built[:32] + b"".join(pal_pair(c) for c in pal) + bytes(col) + bytes(m["cells"])


def level_for(n, level):
    """(level number, its ZPL bytes with no map changes) for city n."""
    for lv in ([level] if level else range(1, 100)):
        p = os.path.join(DATA_DIR, f"LEVEL{lv:02d}.ZPL")
        if not os.path.exists(p):
            continue
        d = open(p, "rb").read()
        if d[5] == n or level:
            return lv, d[:6 + 113] + b"\x00"       # (its map changes left out)
    raise SystemExit(f"no level file for city {n} in {DATA_DIR}: run build.bat")


def render(map_path, x, z, heading=0, height=120, level=None, out="preview.png", palette=None):
    sym = {}
    for line in open(SYM):
        k, _, v = line.partition(": EQU 0x")
        if v:
            sym[k] = int(v, 16)
    m = cm.load(map_path)
    n = m["city"]
    built = open(os.path.join(DATA_DIR, f"CITY{n:02d}.ZPC"), "rb").read()
    lv, lfile = level_for(n, level)
    sd = tempfile.mkdtemp(prefix="zpolice_preview_")
    try:
        os.makedirs(os.path.join(sd, "ZPDATA"))
        with open(os.path.join(sd, "ZPDATA", f"CITY{n:02d}.ZPC"), "wb") as f:
            f.write(city_file(m, built))
        with open(os.path.join(sd, "ZPDATA", f"LEVEL{lv:02d}.ZPL"), "wb") as f:
            f.write(lfile)
        gfx = os.path.join(DATA_DIR, "SPRITES.ZPG")    # the figures
        if os.path.exists(gfx):
            shutil.copy(gfx, os.path.join(sd, "ZPDATA", "SPRITES.ZPG"))
        zpp = os.path.join(DATA_DIR, f"LEVEL{lv:02d}.ZPP")
        if palette:                     # the level's colours: as given,
            pdata = lp.binary(lv, sf.apply_palette(lp.load(palette)["pal"], sf.load_palette()))
        elif os.path.exists(zpp):       #   or as built
            pdata = open(zpp, "rb").read()
        else:
            pdata = None
        if pdata:
            with open(os.path.join(sd, "ZPDATA", f"LEVEL{lv:02d}.ZPP"), "wb") as f:
                f.write(pdata)
        cpu = nexsim.Cpu()
        cpu.esx_root = sd
        nexsim.load_nex(cpu, NEX)
        cpu.keys = {"1"}                # new game, then the load-out screen
        scans = 0
        while cpu.pc != sym["main_loop"]:
            if cpu.pc == sym["kbd_scan"] and cpu.mmu[6] == sym["PAGE_LOADOUT"]:
                scans += 1
                if scans == 2:
                    cpu.wr(sym["level"], lv)
                cpu.keys = {"0"} if scans == 4 else set()
            cpu.step()
        cpu.keys = set()
        for i, v in enumerate((0, 0x80, x)):    # the VTOL: the cell's centre
            cpu.wr(sym["cam_x"] + i, v)
        for i, v in enumerate((0, 0x80, z)):
            cpu.wr(sym["cam_z"] + i, v)
        cpu.wr16(sym["cam_y"], height)
        cpu.wr(sym["yaw_frac"], 0)
        cpu.wr(sym["yaw"], round(heading * 256 / 360) & 255)
        cpu.wr16(sym["pitch_frac"], 0)
        cpu.wr(sym["speed"], 0)
        flips = []
        cpu.on_flip = lambda bank: flips.append(bank)
        while len(flips) < 2:
            cpu.step()
        nexsim.write_png(out, 9, cpu)
    finally:
        shutil.rmtree(sd, ignore_errors=True)
    return out


def main():
    ap = argparse.ArgumentParser(description="Preview a city map as the game draws it.")
    ap.add_argument("map")
    ap.add_argument("x", type=int)
    ap.add_argument("z", type=int)
    ap.add_argument("--heading", type=float, default=0)
    ap.add_argument("--height", type=int, default=120)
    ap.add_argument("--level", type=int, default=None)
    ap.add_argument("--palette", default=None)
    ap.add_argument("--out", default="preview.png")
    a = ap.parse_args()
    if not (0 <= a.x < GRID and 0 <= a.z < GRID):
        raise SystemExit(f"x and z are 0..{GRID - 1}")
    if not os.path.exists(NEX):
        raise SystemExit(f"{NEX}: build the game first (build.bat)")
    print(render(a.map, a.x, a.z, a.heading, max(8, min(192, a.height)), a.level, a.out, a.palette))


if __name__ == "__main__":
    main()
