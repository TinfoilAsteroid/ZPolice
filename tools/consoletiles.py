"""The VTOL console round the view: hardware tilemap tiles (tiles.asm) in
the screen's border, under the HUD's sprites (the compass, the humans
column, the view's frame) and the ULA panel.  gentables.py writes
tables_console.inc from here:

    console_pal    CON_BANKS banks of 16 colours, 9-bit (2 bytes each:
                   RRRGGGBB, then blue's low bit; NextReg $44), bank k at
                   tilemap palette offset CON_OFFSET0 + k (index 0 of each
                   is see-through)
    console_tbank  CON_N bytes: each tile's attribute, its bank's palette
                   offset << 4
    console_defs   CON_N tiles of 32 bytes (4 bits a pixel), loaded as
                   tiles TM_FREE.. (tiles.asm)
    console_map    40 x 32 cells of 2 bytes, row by row: the tile's place
                   in console_defs + 1 (0: none, see-through; tiles.asm
                   adds TM_FREE - 1), then its flags as attribute bits:
                   bit 3 mirror x, bit 2 mirror y, bit 1 rotate, bit 0
                   the ULA over it

The tiles, their colours and the layout are in sprites/console_tiles.json:
edit them with tools/tile_editor.py (load, save, problems here).

    {"format": "Z-Police console tiles", "version": 2,
     "banks": [[16 colours, 9-bit RRRGGGBBB (0-511); index 0 is
                see-through], ... 1 to 15 banks],
     "tiles": [{"name": "PLATE", "bank": 0, "rows": ["44444444", ... 8 rows
                of 8 hex digits: a pixel's colour index in its bank]},
               ... at most 112],
     "layout": [32 rows of 40 cells: "" none (the view's area), "NAME",
                or "NAME|" and any of x (mirror left to right), y (mirror
                top to bottom), r (rotate 90 degrees clockwise), u (the
                ULA drawn over this tile, where the ULA isn't see-through):
                "NAME|xr";
                an older "|m" is x]}

Without the file, it's made (gentables.py: ensure_file) from the tiles
drawn below (8 rows of 8 characters, CHARS the colour indices) and
layout().  A version 1 file (one 8-bit "palette") is read as one bank of
9-bit colours.  build.bat puts them in the game.

    python tools/consoletiles.py [out.png]    a preview of the layout
"""
import json
import os
import sys

FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sprites",
                    "console_tiles.json")
FORMAT = "Z-Police console tiles"
VERSION = 2
MAX_TILES = 112                         # tiles 64-175 (tiles.asm TM_FREE..)
CON_OFFSET0 = 1                         # bank 0's tilemap palette offset (0: the
MAX_BANKS = 16 - CON_OFFSET0            #   font's white), up to 15 banks
FIRST = 64                              # TM_FREE (tiles.asm)
COLS, ROWS = 40, 32

# colour index: (char, RRRGGGBB)
CHARS = {
    ".": (0, 0x00),     # see-through
    "k": (1, 0x00),     # black
    "d": (2, 0x24),     # very dark grey
    "m": (3, 0x49),     # dark grey: shadows
    "p": (4, 0x6D),     # the panel's grey (the HUD's, hud.asm $6D)
    "l": (5, 0x92),     # light grey
    "h": (6, 0xB6),     # highlight
    "w": (7, 0xDB),     # bright highlight
    "r": (8, 0x05),     # recess: dark blue-grey
    "b": (9, 0x01),     # recess, darker
    "g": (10, 0x1C),    # green lamp
    "G": (11, 0x0C),    # dim green
    "a": (12, 0xF4),    # amber lamp
    "R": (13, 0xE0),    # red lamp
    "x": (14, 0x2E),    # dim cyan: glass
    "y": (15, 0x60),    # dark red
}

T = {}


def tile(name, *rows):
    assert len(rows) == 8 and all(len(r) == 8 for r in rows), name
    T[name] = rows


tile("PLATE",   "pppppppp", "pppppppp", "pppppppp", "pppppppp",
                "pppppppp", "pppppppp", "pppppppp", "pppppppp")
tile("RIVET",   "pppppppp", "pppppppp", "pppllppp", "pplwhmpp",
                "pplhhmpp", "pppmmppp", "pppppppp", "pppppppp")
tile("BEV_T",   "hhhhhhhh", "llllllll", "pppppppp", "pppppppp",
                "pppppppp", "pppppppp", "pppppppp", "pppppppp")
tile("BEV_B",   "pppppppp", "pppppppp", "pppppppp", "pppppppp",
                "pppppppp", "pppppppp", "mmmmmmmm", "dddddddd")
tile("BEV_L",   "hlpppppp", "hlpppppp", "hlpppppp", "hlpppppp",
                "hlpppppp", "hlpppppp", "hlpppppp", "hlpppppp")
tile("BEV_R",   "ppppppmd", "ppppppmd", "ppppppmd", "ppppppmd",
                "ppppppmd", "ppppppmd", "ppppppmd", "ppppppmd")
tile("C_TL",    "whhhhhhh", "hlllllll", "hlpppppp", "hlpppppp",
                "hlpppppp", "hlpppppp", "hlpppppp", "hlpppppp")
tile("C_TR",    "hhhhhhhm", "llllllmd", "ppppppmd", "ppppppmd",
                "ppppppmd", "ppppppmd", "ppppppmd", "ppppppmd")
tile("C_BL",    "hlpppppp", "hlpppppp", "hlpppppp", "hlpppppp",
                "hlpppppp", "hlpppppp", "hmmmmmmm", "mddddddd")
tile("C_BR",    "ppppppmd", "ppppppmd", "ppppppmd", "ppppppmd",
                "ppppppmd", "ppppppmd", "mmmmmmmd", "dddddddd")
# the compass's window: a dark recess, its rims shadowed above and lit below
tile("WIN_T",   "kkkkkkkk", "dddddddd", "rrrrrrrr", "rrrrrrrr",
                "rrrrrrrr", "rrrrrrrr", "rrrrrrrr", "bbbbbbbb")
tile("WIN_B",   "bbbbbbbb", "rrrrrrrr", "rrrrrrrr", "rrrrrrrr",
                "rrrrrrrr", "rrrrrrrr", "mmmmmmmm", "llllllll")
tile("WIN_TL",  "pkkkkkkk", "kddddddd", "kdrrrrrr", "kdrrrrrr",
                "kdrrrrrr", "kdrrrrrr", "kdrrrrrr", "kdbbbbbb")
tile("WIN_BL",  "kdbbbbbb", "kdrrrrrr", "kdrrrrrr", "kdrrrrrr",
                "kdrrrrrr", "kdrrrrrr", "kmmmmmmm", "plllllll")
tile("WIN_TR",  "kkkkkkkp", "dddddddl", "rrrrrrml", "rrrrrrml",
                "rrrrrrml", "rrrrrrml", "rrrrrrml", "bbbbbbml")
tile("WIN_BR",  "bbbbbbml", "rrrrrrml", "rrrrrrml", "rrrrrrml",
                "rrrrrrml", "rrrrrrml", "mmmmmmll", "lllllllp")
# the heading pointer's housing, under the window's middle
tile("NOTCH",   "dddddddd", "mbrrrrrr", "mbrrrrrr", "mbrrrrrr",
                "mbrrrrrr", "mbrrrrrr", "mbrrrrrr", "llllllll")    # (its right: mirrored)
# lips against the view: shadow on the view's side
tile("LIP_B",   "pppppppp", "pppppppp", "pppppppp", "pppppppp",
                "pppppppp", "pppppppp", "mmmmmmmm", "kkkkkkkk")
tile("LIP_T",   "kkkkkkkk", "hhhhhhhh", "pppppppp", "pppppppp",
                "pppppppp", "pppppppp", "pppppppp", "pppppppp")
tile("LIP_R",   "ppppppmk", "ppppppmk", "ppppppmk", "ppppppmk",
                "ppppppmk", "ppppppmk", "ppppppmk", "ppppppmk")
tile("LIP_L",   "khpppppp", "khpppppp", "khpppppp", "khpppppp",
                "khpppppp", "khpppppp", "khpppppp", "khpppppp")
# the humans column's slot (columns 1-2)
tile("REC_TL",  "dddddddd", "dbbbbbbb", "dbrrrrrr", "dbrrrrrr",
                "dbrrrrrr", "dbrrrrrr", "dbrrrrrr", "dbrrrrrr")
tile("REC_TR",  "dddddddd", "bbbbbbbl", "rrrrrrbl", "rrrrrrbl",
                "rrrrrrbl", "rrrrrrbl", "rrrrrrbl", "rrrrrrbl")
tile("REC_L",   "dbrrrrrr", "dbrrrrrr", "dbrrrrrr", "dbrrrrrr",
                "dbrrrrrr", "dbrrrrrr", "dbrrrrrr", "dbrrrrrr")
tile("REC_R",   "rrrrrrbl", "rrrrrrbl", "rrrrrrbl", "rrrrrrbl",
                "rrrrrrbl", "rrrrrrbl", "rrrrrrbl", "rrrrrrbl")
tile("REC_BL",  "dbrrrrrr", "dbrrrrrr", "dbrrrrrr", "dbrrrrrr",
                "dbrrrrrr", "dbbbbbbb", "dlllllll", "llllllll")
tile("REC_BR",  "rrrrrrbl", "rrrrrrbl", "rrrrrrbl", "rrrrrrbl",
                "rrrrrrbl", "bbbbbbbl", "llllllll", "llllllll")
tile("VENT",    "pppppppp", "mkkkkkkm", "plllllll", "pppppppp",
                "mkkkkkkm", "plllllll", "pppppppp", "pppppppp")
tile("LED_G",   "pppppppp", "ppmmmmpp", "pmdgGdhp", "pmggggdp",
                "pmGgggdp", "pmdGGdhp", "pphhhhpp", "pppppppp")
tile("LED_A",   "pppppppp", "ppmmmmpp", "pmdaydhp", "pmaaaadp",
                "pmyaaadp", "pmdyydhp", "pphhhhpp", "pppppppp")
tile("LED_R",   "pppppppp", "ppmmmmpp", "pmdRydhp", "pmRRRRdp",
                "pmyRRRdp", "pmdyydhp", "pphhhhpp", "pppppppp")
tile("LABEL",   "pppppppp", "pkkkkkkp", "pkxxxkkp", "pkkkkkkp",
                "pkxkxxkp", "pkkkkkkp", "pppppppp", "pppppppp")

NAMES = list(T)
assert len(NAMES) <= MAX_TILES


MIRROR = "mirror"


def layout():
    """40 x 32 names (None: no tile, the view's area), or (name, MIRROR):
    mirrored left to right"""
    m = [[None] * COLS for _ in range(ROWS)]

    def put(r, c, n):
        m[r][c] = n
    for c in range(1, COLS - 1):                # the outer edge
        put(0, c, "BEV_T")
        put(ROWS - 1, c, "BEV_B")
    for r in range(1, ROWS - 1):
        put(r, 0, "BEV_L")
        put(r, COLS - 1, "BEV_R")
    put(0, 0, "C_TL"), put(0, COLS - 1, "C_TR")
    put(ROWS - 1, 0, "C_BL"), put(ROWS - 1, COLS - 1, "C_BR")
    # the compass: the window rows 1-2, columns 1-38, the notch under its
    # middle (the pointer, sprite x 152-167: columns 19-20)
    for c in range(2, COLS - 2):
        put(1, c, "WIN_T")
        put(2, c, "WIN_B")
    put(1, 1, "WIN_TL"), put(2, 1, "WIN_BL")
    put(1, COLS - 2, "WIN_TR"), put(2, COLS - 2, "WIN_BR")
    for c in range(1, COLS - 1):                # row 3: the lip above the view
        put(3, c, "LIP_B" if 4 <= c < COLS - 4 else "PLATE")
    put(3, 19, "NOTCH"), put(3, 20, ("NOTCH", MIRROR))
    put(3, 2, "RIVET"), put(3, COLS - 3, "RIVET")
    # the sides, rows 4-27
    for r in range(4, 28):
        put(r, 3, "LIP_R")
        put(r, COLS - 4, "LIP_L")
        put(r, 1, "REC_L")
        put(r, 2, "REC_R")
        put(r, COLS - 3, "VENT")
        put(r, COLS - 2, "VENT")
    put(4, 1, "REC_TL"), put(4, 2, "REC_TR")
    put(27, 1, "REC_BL"), put(27, 2, "REC_BR")
    for r in (4, 27):
        put(r, COLS - 3, "RIVET"), put(r, COLS - 2, "PLATE")
    for r, n in ((10, "LED_G"), (13, "LED_A"), (16, "LED_R")):
        put(r, COLS - 3, n)
    # below the panel, rows 28-30
    for r in range(28, 31):
        for c in range(1, COLS - 1):
            put(r, c, "PLATE")
    for c in range(4, COLS - 4):
        put(28, c, "LIP_T")
    for c in range(12, 28):
        put(29, c, "VENT"), put(30, c, "VENT")
    put(29, 2, "RIVET"), put(30, COLS - 3, "RIVET")
    for c, n in ((5, "LED_G"), (6, "LED_A"), (7, "LED_R")):
        put(29, c, n)
    for c in (5, 6, 7, 31, 32, 33, 34):
        put(30, c, "LABEL")
    put(29, 32, "LED_G"), put(29, 33, "LED_G")
    return m


def default_palette():
    """The built-in colours, 8-bit (RRRGGGBB)"""
    pal = [0] * 16
    for i, c in CHARS.values():
        pal[i] = c
    return pal


def to9(c):
    """RRRGGGBB -> a 9-bit colour (RRRGGGBBB) as the Next shows it: the third
    blue bit the other two ORed"""
    return (c << 1) | (1 if c & 3 else 0)


def default():
    """The data from the tiles drawn above and layout(): one bank"""
    tiles = [{"name": n, "bank": 0, "rows": ["".join(f"{CHARS[ch][0]:x}" for ch in row) for row in T[n]]}
             for n in NAMES]
    lay = [["" if n is None else (n[0] + "|x" if isinstance(n, tuple) else n) for n in row]
           for row in layout()]
    return {"format": FORMAT, "version": VERSION, "banks": [[to9(c) for c in default_palette()]],
            "tiles": tiles, "layout": lay}


def upgrade(d):
    """Version 1 (one 8-bit palette, no banks) -> 2: one bank of 9-bit
    colours, every tile in it"""
    if "banks" not in d:
        d["banks"] = [[to9(int(c)) for c in d.pop("palette")]]
    for t in d.get("tiles", []):
        t.setdefault("bank", 0)
    d["layout"] = [[cell_text(*cell_parts(c)) for c in row] for row in d.get("layout", [])]  # (|m -> |x)
    d["version"] = VERSION
    return d


def load(path=FILE):
    """The console's data (the defaults if there's no file; version 1
    upgraded).  ValueError if it can't be read."""
    if not os.path.exists(path):
        return default()
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("format") != FORMAT:
        raise ValueError(f"{path}: not a {FORMAT} file")
    return upgrade(d)


def save(d, path=FILE):
    """Compact: a bank, a tile, a layout row on a line"""
    out = ["{", f' "format": "{FORMAT}", "version": {VERSION},', ' "banks": [']
    out.append(",\n".join("  " + json.dumps(b) for b in d["banks"]))
    out.append(" ],")
    out.append(' "tiles": [')
    out.append(",\n".join(f'  {{"name": {json.dumps(t["name"])}, "bank": {t.get("bank", 0)}, '
                          f'"rows": {json.dumps(t["rows"])}}}' for t in d["tiles"]))
    out.append(" ],")
    out.append(' "layout": [')
    out.append(",\n".join("  " + json.dumps(row) for row in d["layout"]))
    out.append(" ]")
    out.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def ensure_file():
    """Write the file from the defaults if it isn't there (gentables.py).
    True if it was written."""
    if os.path.exists(FILE):
        return False
    save(default())
    return True


def problems(d):
    """What the game can't use"""
    errs = []
    banks = d.get("banks", [])
    if not 1 <= len(banks) <= MAX_BANKS:
        errs.append(f"{len(banks)} colour banks: 1 to {MAX_BANKS}")
    for k, b in enumerate(banks):
        if len(b) != 16 or any(not isinstance(c, int) or not 0 <= c <= 511 for c in b):
            errs.append(f"bank {k}: 16 colours, 0-511 (9 bits: RRRGGGBBB)")
    tiles = d.get("tiles", [])
    if not 1 <= len(tiles) <= MAX_TILES:
        errs.append(f"{len(tiles)} tiles: 1 to {MAX_TILES} (tiles {FIRST}-{FIRST + MAX_TILES - 1})")
    names = [t.get("name", "") for t in tiles]
    for n in names:
        if not n or not all(ch.isalnum() or ch == "_" for ch in n):
            errs.append(f"tile name {n!r}: letters, digits and _")
    dup = sorted({n for n in names if names.count(n) > 1})
    if dup:
        errs.append(f"tile names used twice: {', '.join(dup)}")
    for t in tiles:
        rows = t.get("rows", [])
        if len(rows) != 8 or any(len(r) != 8 or any(ch not in "0123456789abcdef" for ch in r.lower())
                                 for r in rows):
            errs.append(f"tile {t.get('name')}: 8 rows of 8 hex digits")
        if not isinstance(t.get("bank", 0), int) or not 0 <= t.get("bank", 0) < len(banks):
            errs.append(f"tile {t.get('name')}: bank {t.get('bank')} isn't there")
    lay = d.get("layout", [])
    if len(lay) != ROWS or any(len(r) != COLS for r in lay):
        errs.append(f"the layout: {ROWS} rows of {COLS} cells")
    else:
        bad = sorted({c.split("|")[0] for r in lay for c in r if c and c.split("|")[0] not in names})
        if bad:
            errs.append(f"the layout uses tiles that aren't there: {', '.join(bad)}")
        odd = sorted({c for r in lay for c in r if c.count("|") > 1
                      or any(ch not in "xymru" for ch in c.partition("|")[2])})
        if odd:
            errs.append(f"cells with flags other than x, y, r, u: {', '.join(odd[:4])}")
    return errs


def pixel(rows, u, v):
    """A tile's colour index at (u, v)"""
    return int(rows[v][u], 16)


def tile_bytes(rows):
    """32 bytes: 4 bits a pixel, the left one in the high nibble"""
    out = bytearray()
    for row in rows:
        for k in range(0, 8, 2):
            out.append(int(row[k], 16) << 4 | int(row[k + 1], 16))
    return bytes(out)


# a cell's flags: the tile attribute's bits (tiles.asm, the hardware's)
MIRROR_X, MIRROR_Y, ROTATE, ULA_OVER = 8, 4, 2, 1
FLAG_LETTERS = (("x", MIRROR_X), ("y", MIRROR_Y), ("r", ROTATE), ("u", ULA_OVER))


def cell_parts(cell):
    """A layout cell -> (its tile's name, its flags), ("", 0) for none"""
    if not cell:
        return "", 0
    n, _, f = cell.partition("|")
    flags = 0
    for ch in f:
        flags |= {"x": MIRROR_X, "m": MIRROR_X, "y": MIRROR_Y, "r": ROTATE, "u": ULA_OVER}.get(ch, 0)
    return n, flags


def cell_text(name, flags):
    """(name, flags) -> a layout cell ("NAME", "NAME|xyr")"""
    if not name:
        return ""
    f = "".join(ch for ch, bit in FLAG_LETTERS if flags & bit)
    return name + ("|" + f if f else "")


def source(u, v, flags):
    """The tile's pixel shown at (u, v) of a cell with these flags, as the
    hardware: rotated 90 degrees clockwise, then the result mirrored on the
    screen (so the mirrors flip the screen's (u, v) before the rotation
    looks the pixel up; nexsim)"""
    if flags & MIRROR_X:
        u = 7 - u
    if flags & MIRROR_Y:
        v = 7 - v
    if flags & ROTATE:
        u, v = v, 7 - u
    return u, v


def cell_value(cell, names):
    """A layout cell -> its map bytes (tiles.asm console_on): its tile's
    place in the tiles + 1 (0: none), its flags"""
    n, flags = cell_parts(cell)
    if not n:
        return 0, 0
    return names.index(n) + 1, flags


def cell_tile(cell, names):
    """A layout cell -> (its tile number in the game, its flags), or None"""
    n, flags = cell_parts(cell)
    if not n:
        return None
    return FIRST + names.index(n), flags


def bank_offset(bank):
    """A bank -> its tilemap palette offset (attribute bits 7-4)"""
    return CON_OFFSET0 + bank


def write_inc(path, d=None):
    if d is None:
        d = load()
    errs = problems(d)
    if errs:
        raise SystemExit(f"{FILE}: the console's tiles can't be used:\n  " + "\n  ".join(errs))
    names = [t["name"] for t in d["tiles"]]
    lines = ["; Generated by tools/consoletiles.py (gentables.py): the VTOL console's",
             "; tiles (tiles.asm, console_on), from sprites/console_tiles.json (edit",
             "; them with tools/tile_editor.py, not this).",
             f"CON_OFFSET0     equ {CON_OFFSET0}", f"CON_BANKS       equ {len(d['banks'])}",
             f"CON_N           equ {len(names)}",
             "console_pal:                    ; each bank's 16 colours, 9-bit: RRRGGGBB, then B's low bit"]
    for k, b in enumerate(d["banks"]):
        lines.append("        db " + ", ".join(f"${c >> 1:02X}, {c & 1}" for c in b)
                     + f"    ; bank {k}: palette offset {bank_offset(k)}")
    lines.append("console_tbank:                  ; each tile's attribute: its bank's palette offset << 4")
    lines.append("        db " + ", ".join(f"${bank_offset(t.get('bank', 0)) << 4:02X}" for t in d["tiles"]))
    lines.append("; each tile: CT_name its place (the game's tile TM_FREE + it), CTA_name its")
    lines.append("; attribute's bank (palette offset << 4), for code that changes a cell")
    for k, t in enumerate(d["tiles"]):
        lines.append(f"CT_{t['name']:<20} equ {k}")
        lines.append(f"CTA_{t['name']:<19} equ ${bank_offset(t.get('bank', 0)) << 4:02X}")
    lines.append("console_defs:")
    for k, t in enumerate(d["tiles"]):
        b = tile_bytes(t["rows"])
        lines.append(f"        db {', '.join(f'${x:02X}' for x in b)}    ; {FIRST + k} {t['name']}")
    lines.append("console_map:                    ; a cell: its tile's place + 1 (0 none), its flags")
    for row in d["layout"]:
        lines.append("        db " + ", ".join("%d,%d" % cell_value(c, names) for c in row))
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def rgb9(c):
    """A 9-bit colour (RRRGGGBBB) -> (r, g, b) 0-255"""
    return (round((c >> 6) * 255 / 7), round((c >> 3 & 7) * 255 / 7), round((c & 7) * 255 / 7))


def rgb(c):
    """RRRGGGBB -> (r, g, b) 0-255, as the Next shows it (the third blue bit
    is the other two ORed; as hudsprites.rgb)"""
    return rgb9(to9(c))


def preview(path, scale=2, d=None):
    """The layout as a PNG (see-through: dark magenta)"""
    import struct
    import zlib
    if d is None:
        d = load()
    tiles = {t["name"]: t for t in d["tiles"]}
    W, H = COLS * 8, ROWS * 8
    raw = bytearray()
    for y in range(H * scale):
        raw.append(0)
        for x in range(W * scale):
            px, py = x // scale, y // scale
            cell = d["layout"][py // 8][px // 8]
            if not cell:
                raw += bytes((60, 0, 60))
                continue
            n, flags = cell_parts(cell)
            u, v = source(px % 8, py % 8, flags)
            t = tiles[n]
            i = pixel(t["rows"], u, v)
            raw += bytes(rgb9(d["banks"][t.get("bank", 0)][i])) if i else bytes((60, 0, 60))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W * scale, H * scale, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "docs", "console_tiles.png")
    preview(out)
    print("wrote", out)
