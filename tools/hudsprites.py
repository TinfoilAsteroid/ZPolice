"""The HUD's hardware sprites (Layer 3): their file, sprites/hud.json, its checks
and the pixel operations (shared by tools/hud_sprite_editor.py, gentables.py
and the tests).

Every pattern is 16 x 16 pixels, each a byte RRRGGGBB, the sprite palette being
the identity; $E3 is transparent.  They go into sprite bank 0 in the file's
order, so a pattern's number is its place in the file.

The file:

    {"version": 1,
     "sprites": [
       {"name": "HSPR_FIELD",
        "rows": ["E3 E3 FF ...", ... 16 rows of 16 hex bytes ...]},
       ...
     ]}

The names are the assembler's (gentables.py writes each as an equ, in
tables_hspr.inc), so the game's own, REQUIRED, have to be there, first and in
that order.  More can follow, and the game has them as soon as code uses their
names.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUD_FILE = os.path.join(ROOT, "sprites", "hud.json")
VERSION = 1
SIZE = 16
TRANSPARENT = 0xE3
MAX_SPRITES = 31                        # what an 8K sprite bank holds, with its loader

REQUIRED = [
    ("HSPR_FIELD", "Human status: waiting in the city, not yet rescued"),
    ("HSPR_ABOARD", "Human status: aboard the VTOL"),
    ("HSPR_SAVED", "Human status: rescued"),
    ("HSPR_DEAD", "Human status: dead"),
    ("CSPR_N", "Compass: north"),
    ("CSPR_E", "Compass: east"),
    ("CSPR_S", "Compass: south"),
    ("CSPR_W", "Compass: west"),
    ("CSPR_DOT", "Compass: the 45 degree marks (NE, SE, SW, NW)"),
    ("CSPR_TICK", "Compass: the 22.5 degree marks between"),
    ("CSPR_PTR", "Compass: the heading pointer, under the bar's middle"),
    ("FRM_CRN", "Viewport frame: the top corners (the right one mirrored). Outside "
                "the curve is black, the border's colour"),
    ("FRM_CRN_P", "Viewport frame: the bottom corners (mirrored to fit). Outside the "
                  "curve is the panel's colour, $6D in hud.asm: keep them the same"),
    ("FRM_CRN_S", "Viewport frame: rounds the panel's bottom corners (mirrored to fit)"),
    ("FRM_H", "Viewport frame: the top edge. Only the top rows are seen as lines: "
              "it's stretched 8 times across"),
    ("FRM_V", "Viewport frame: the side edges (the right one mirrored), stretched "
              "4 times down"),
]
REQUIRED_NAMES = [n for n, _ in REQUIRED]
DESCRIPTIONS = dict(REQUIRED)


def description(name):
    return DESCRIPTIONS.get(name, "Added: the game has it as soon as code uses its name")


def blank():
    return [[TRANSPARENT] * SIZE for _ in range(SIZE)]


def new_sprite(name):
    return {"name": name, "pixels": blank()}


# ------------------------------------------------------------------ the file
def load(path=HUD_FILE):
    """The file -> a list of {"name", "pixels": 16 rows of 16 bytes}.
    ValueError if it's malformed."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("version") != VERSION:
        raise ValueError(f"{path}: version {d.get('version')}, not {VERSION}")
    out = []
    for s in d["sprites"]:
        try:
            px = [[int(v, 16) for v in row.split()] for row in s["rows"]]
        except (KeyError, AttributeError, TypeError) as e:
            raise ValueError(f"{path}: {s.get('name', '?')}: {e}")
        out.append({"name": s["name"], "pixels": px})
    return out


def save(sprites, path=HUD_FILE):
    """A row a line, so a change shows up as such in a diff."""
    parts = []
    for s in sprites:
        rows = ",\n".join('    "' + " ".join(f"{v:02X}" for v in r) + '"' for r in s["pixels"])
        parts.append(f'  {{"name": "{s["name"]}",\n   "rows": [\n{rows}\n   ]}}')
    text = '{"version": %d,\n "sprites": [\n' % VERSION + ",\n".join(parts) + "\n]}\n"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def problems(sprites):
    """What stops the game using them, as a list of strings."""
    errs = []
    names = [s["name"] for s in sprites]
    if names[:len(REQUIRED_NAMES)] != REQUIRED_NAMES:
        errs.append("the game's own sprites must come first, in order: " + ", ".join(REQUIRED_NAMES))
    if len(sprites) > MAX_SPRITES:
        errs.append(f"{len(sprites)} sprites: a bank holds {MAX_SPRITES}")
    for s in sprites:
        n = s["name"]
        if not valid_name(n):
            errs.append(f"{n!r}: not a name for the assembler (capitals, digits, _)")
        if names.count(n) > 1:
            errs.append(f"{n}: the name is used twice")
        px = s["pixels"]
        if len(px) != SIZE or any(len(r) != SIZE for r in px):
            errs.append(f"{n}: not 16 x 16")
        elif any(not 0 <= v <= 255 for r in px for v in r):
            errs.append(f"{n}: a pixel isn't a byte")
    return errs


def valid_name(name):
    return re.fullmatch(r"[A-Z][A-Z0-9_]*", name) is not None


def table_text(sprites):
    """tables_hspr.inc: an equ for each pattern's number, then the patterns."""
    names = [s["name"] for s in sprites]
    humans = sum(n.startswith("HSPR_") for n in REQUIRED_NAMES)
    hl = ["; ---- generated by gentables.py - do not edit ----", "",
          "; sprite bank 0: 16x16 8-bit patterns (RRRGGGBB, $E3 transparent): the",
          "; human status sprites, the compass bar's, then the viewport frame's"]
    for n, name in enumerate(names):
        hl.append(f"{name:15s} equ {n}")
    hl.append(f"HSPR_COUNT      equ {humans}      ; the human status ones")
    hl.append(f"SPRB0_PATTERNS  equ {len(sprites)}     ; all of bank 0's")
    hl.append("hspr_patterns:")
    for s in sprites:
        hl.append(f"; {s['name']}")
        for row in s["pixels"]:
            hl.append("        db " + ",".join(f"${v:02X}" for v in row))
    return "\n".join(hl) + "\n"


# ------------------------------------------------------------------ colours
def rgb(v):
    """A byte RRRGGGBB -> (r, g, b), 0..255, as the Next shows it (the third
    blue bit is the other two ORed)."""
    b = v & 3
    return (round((v >> 5) * 255 / 7), round((v >> 2 & 7) * 255 / 7),
            round(((b << 1) | (1 if b else 0)) * 255 / 7))


def hex_rgb(v):
    return "#%02x%02x%02x" % rgb(v)


# ----------------------------------------------------------- pixel operations
def mirror(px):
    return [r[::-1] for r in px]


def flip(px):
    return [list(r) for r in px[::-1]]


def rotate(px):
    """A quarter turn clockwise."""
    return [list(r) for r in zip(*px[::-1])]


def shift(px, dx, dy):
    """Moved dx right and dy down; what goes off one edge comes back on the
    other, so nothing is lost."""
    return [[px[(y - dy) % SIZE][(x - dx) % SIZE] for x in range(SIZE)] for y in range(SIZE)]


def replace(px, old, new):
    return [[new if v == old else v for v in r] for r in px]


def fill(px, at, colour):
    """A new copy: the area of at's colour, joined side to side, in colour."""
    out = [list(r) for r in px]
    old = out[at[1]][at[0]]
    if old == colour:
        return out
    todo = [at]
    while todo:
        x, y = todo.pop()
        if 0 <= x < SIZE and 0 <= y < SIZE and out[y][x] == old:
            out[y][x] = colour
            todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return out


def line_cells(a, b):
    (x0, y0), (x1, y1) = a, b
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    return {(round(x0 + (x1 - x0) * k / n), round(y0 + (y1 - y0) * k / n)) for k in range(n + 1)}


def rect_cells(a, b):
    """The outline of the box with corners a and b."""
    x0, x1 = sorted((a[0], b[0]))
    y0, y1 = sorted((a[1], b[1]))
    return {(x, y) for x in range(x0, x1 + 1) for y in (y0, y1)} | \
           {(x, y) for y in range(y0, y1 + 1) for x in (x0, x1)}
