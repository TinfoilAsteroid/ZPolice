"""Z-Police figure graphics (humans and monsters): the format shared by the
sprite editor (tools/sprite_editor.py) and gengraphics.py.

The colours: sprites/palette.json, 32 colours, r g b 0..7 each:

    {"format": "Z-Police figure palette", "version": 1,
     "colours": [[r, g, b], ...32]}

Colour 0 is transparent (never drawn), so 31 are usable.  They are Layer 2
palette entries SPR_PAL0 (192) .. SPR_PAL0+31, families 48-55, which no
building or fixed colour uses: gentables.py puts them in every city's palette
(and every level's own), so the figures look the same everywhere.

A figure: sprites/NAME.json, one per figure in FIGURES (zombie, ghoul,
ghost, banshee, human, lich):

    {"format": "Z-Police figure", "version": 1, "name": "zombie",
     "height": 26,
     "anims": {"walk_front": {"frames": [
                  {"lods": [{"min_z": 0, "rows": ["..12..", ...]},
                            {"min_z": null, "rows": [...]}, ...]},
                  ...]},
               "walk_side": ..., "walk_rear": ...}}

"height": the figure's height in world units (26: 2 m), what the game
projects it at.  "anims": one per purpose the game asks for (ANIMS: the
figure's names below, each a list of frames, played in turn).  A frame has
one or more levels of detail ("lods"), largest first; each its pixel "rows"
(one string a row, a character a pixel: PIXEL_CHARS, "." transparent, then
1-9, A-V for colours 1..31; all rows the same length) and "min_z": the
nearest camera distance (world units, Z) it is drawn from.  The first (the
largest) is drawn from 0; null for the others: from the distance its height
is the figure's projected height (auto_min_z).  The game draws the level
whose min_z is the largest not past the figure's distance, at its own size
(no scaling), its bottom centre on the figure's feet.  A side view faces
left: the game mirrors it for a figure facing right.

gengraphics.py packs them all into ZPDATA/SPRITES.ZPG (build, below), which
the game loads at start-up, and writes gfx_ids.inc (the ANIM_ numbers).
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITE_DIR = os.path.join(ROOT, "sprites")
PAL_FILE = os.path.join(SPRITE_DIR, "palette.json")
PAL_FORMAT = "Z-Police figure palette"
FORMAT = "Z-Police figure"
VERSION = 1
COLOURS = 32
SPR_PAL0 = 192                          # Layer 2 palette entry of colour 0
PIXEL_CHARS = ".123456789ABCDEFGHIJKLMNOPQRSTUV"
assert len(PIXEL_CHARS) == COLOURS
MAX_W, MAX_H = 64, 64                   # a level of detail at most this big
MAX_FRAMES, MAX_LODS = 16, 8
PROJ = 128                              # screen pixels per (world unit / Z)

# The figures, their heights (world units) and the purposes the game asks
# for: (name, description).  Their order is the game's ANIM_ numbers: change
# it only with the game (gfx_ids.inc is generated from it).
FIGURES = [
    ("zombie", 26, [("walk_front", "walking towards the camera"),
                    ("walk_side", "walking, side on, facing left (mirrored for right)"),
                    ("walk_rear", "walking away from the camera")]),
    ("ghoul", 13, [("walk_front", "walking towards the camera"),
                   ("walk_side", "walking, side on, facing left (mirrored for right)"),
                   ("walk_rear", "walking away from the camera")]),
    ("ghost", 26, [("float", "floating, facing the camera (never mirrored)")]),
    ("banshee", 26, [("float", "floating, facing the camera (never mirrored)")]),
    ("human", 26, [("wave", "waiting, the VTOL near: facing the camera, waving"),
                   ("run_front", "running (to the VTOL, or from a monster), towards the camera"),
                   ("run_side", "running, side on, facing left (mirrored for right)"),
                   ("run_rear", "running, away from the camera"),
                   ("stand", "waiting, the VTOL far off: facing the camera, standing")]),
    ("lich", 52, [("walk_front", "walking towards the camera"),
                  ("walk_side", "walking, side on, facing left (mirrored for right)"),
                  ("walk_rear", "walking away from the camera")]),
]
FIGURE_NAMES = [f for f, _, _ in FIGURES]
ANIMS = [(f, a) for f, _, anims in FIGURES for a, _ in anims]


def anim_label(fig, anim):
    """The assembler name of a purpose: ANIM_ZOMBIE_WALK_FRONT."""
    return f"ANIM_{fig.upper()}_{anim.upper()}"


def figure_height(fig):
    return {f: h for f, h, _ in FIGURES}[fig]


def figure_anims(fig):
    return {f: a for f, _, a in FIGURES}[fig]


def figure_path(fig):
    return os.path.join(SPRITE_DIR, f"{fig}.json")


def is_transparent(c):
    """(r, g, b) 0..7 is Layer 2's transparent colour ($E3): never shown."""
    r, g, b = c
    return r == 7 and g == 0 and b >> 1 == 3


# ------------------------------------------------------------- the palette
def load_palette(path=PAL_FILE):
    """sprites/palette.json -> 32 (r, g, b).  ValueError if malformed."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("format") != PAL_FORMAT:
        raise ValueError(f"{path}: not a {PAL_FORMAT} file")
    cols = d.get("colours")
    if not isinstance(cols, list) or len(cols) != COLOURS:
        raise ValueError(f"{path}: needs {COLOURS} colours")
    try:
        return [tuple(int(v) for v in c) for c in cols]
    except (TypeError, ValueError):
        raise ValueError(f"{path}: each colour is [r, g, b]")


def save_palette(pal, path=PAL_FILE):
    lines = [f"  {json.dumps(list(c))}" for c in pal]
    text = ('{\n "format": "%s", "version": %d,\n "colours": [\n' % (PAL_FORMAT, VERSION)
            + ",\n".join(lines) + "\n ]\n}\n")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def palette_problems(pal):
    errs = []
    for i, c in enumerate(pal):
        if len(c) != 3 or any(not 0 <= v <= 7 for v in c):
            errs.append(f"colour {i}: r, g, b are 0..7")
        elif i and is_transparent(c):
            errs.append(f"colour {i}: {tuple(c)} is Layer 2's transparent colour")
    return errs


def apply_palette(layer2_pal, pal):
    """The figure colours into a 256-entry Layer 2 palette, in place
    (entries SPR_PAL0..; colour 0, never drawn, as black)."""
    for i, c in enumerate(pal):
        layer2_pal[SPR_PAL0 + i] = (0, 0, 0) if i == 0 else tuple(c)
    return layer2_pal


# ------------------------------------------------------------- the figures
def new_lod(w, h, min_z=None):
    return {"min_z": min_z, "rows": ["." * w for _ in range(h)]}


def lod_size(lod):
    rows = lod["rows"]
    return (len(rows[0]) if rows else 0), len(rows)


def auto_min_z(height, h):
    """The distance from which a level of detail h pixels high is the
    figure's projected height (or less): 128 * height / h."""
    return math.ceil(PROJ * height / max(1, h))


def min_zs(fig_data):
    """Each frame's levels' min_z, worked out where null: {anim: [[z, ...]]}."""
    H = fig_data["height"]
    out = {}
    for a, an in fig_data["anims"].items():
        out[a] = []
        for fr in an["frames"]:
            zs = []
            for k, lod in enumerate(fr["lods"]):
                z = lod.get("min_z")
                if k == 0:
                    z = 0
                elif z is None:
                    z = auto_min_z(H, lod_size(lod)[1])
                zs.append(int(z))
            out[a].append(zs)
    return out


def load(path):
    """sprites/NAME.json -> dict (name, height, anims).  ValueError if
    malformed (problems() finds what the game can't use)."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("format") != FORMAT:
        raise ValueError(f"{path}: not a {FORMAT} file")
    anims = {}
    for a, an in (d.get("anims") or {}).items():
        frames = []
        for fr in an.get("frames") or []:
            lods = []
            for lod in fr.get("lods") or []:
                rows = lod.get("rows")
                if not isinstance(rows, list) or not all(isinstance(r, str) for r in rows):
                    raise ValueError(f"{path}: {a}: rows are strings")
                z = lod.get("min_z")
                lods.append({"min_z": None if z is None else int(z), "rows": list(rows)})
            frames.append({"lods": lods})
        anims[a] = {"frames": frames}
    return {"name": d.get("name", ""), "height": int(d.get("height", 26)), "anims": anims}


def save(path, fig_data):
    """Write a figure, one pixel row a line (easy to read and diff)."""
    out = ['{', f' "format": "{FORMAT}", "version": {VERSION},',
           f' "name": {json.dumps(fig_data["name"])}, "height": {fig_data["height"]},',
           ' "anims": {']
    alist = list(fig_data["anims"].items())
    for ai, (a, an) in enumerate(alist):
        out.append(f'  {json.dumps(a)}: {{"frames": [')
        for fi, fr in enumerate(an["frames"]):
            out.append('   {"lods": [')
            for li, lod in enumerate(fr["lods"]):
                z = "null" if lod.get("min_z") is None else str(lod["min_z"])
                out.append(f'    {{"min_z": {z}, "rows": [')
                rows = lod["rows"]
                for ri, r in enumerate(rows):
                    out.append(f'     {json.dumps(r)}' + ("," if ri < len(rows) - 1 else ""))
                out.append('    ]}' + ("," if li < len(fr["lods"]) - 1 else ""))
            out.append('   ]}' + ("," if fi < len(an["frames"]) - 1 else ""))
        out.append('  ]}' + ("," if ai < len(alist) - 1 else ""))
    out += [' }', '}']
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def problems(fig, fig_data):
    """What the game can't use in figure fig's data, as messages."""
    errs = []
    if fig_data.get("height", 0) <= 0:
        errs.append("height: world units, more than 0")
    need = [a for a, _ in figure_anims(fig)]
    for a in need:
        if a not in fig_data["anims"]:
            errs.append(f"{a}: missing (the game uses it)")
    for a in fig_data["anims"]:
        if a not in need:
            errs.append(f"{a}: not one of {fig}'s purposes ({', '.join(need)}): the game won't use it")
    zs = min_zs(fig_data)
    for a, an in fig_data["anims"].items():
        frames = an["frames"]
        if not 1 <= len(frames) <= MAX_FRAMES:
            errs.append(f"{a}: 1 to {MAX_FRAMES} frames")
        for fi, fr in enumerate(frames):
            where = f"{a} frame {fi + 1}"
            lods = fr["lods"]
            if not 1 <= len(lods) <= MAX_LODS:
                errs.append(f"{where}: 1 to {MAX_LODS} levels of detail")
            for li, lod in enumerate(lods):
                w, h = lod_size(lod)
                rows = lod["rows"]
                if not (1 <= w <= MAX_W and 1 <= h <= MAX_H):
                    errs.append(f"{where} level {li + 1}: 1x1 to {MAX_W}x{MAX_H} pixels")
                if any(len(r) != w for r in rows):
                    errs.append(f"{where} level {li + 1}: every row {w} pixels")
                bad = {ch for r in rows for ch in r if ch not in PIXEL_CHARS}
                if bad:
                    errs.append(f"{where} level {li + 1}: unknown pixels {''.join(sorted(bad))!r}")
            z = zs[a][fi]
            if any(z[k] >= z[k + 1] for k in range(len(z) - 1)):
                errs.append(f"{where}: each level's min_z more than the one before ({z})")
            if any(v > 65535 for v in z):
                errs.append(f"{where}: min_z at most 65535")
    return errs


def pixels(lod):
    """A level's pixels: rows of colour numbers 0..31."""
    return [[PIXEL_CHARS.index(ch) for ch in r] for r in lod["rows"]]


def from_pixels(px):
    return {"rows": ["".join(PIXEL_CHARS[v] for v in r) for r in px]}


def shrink(px, w, h):
    """Pixels (rows of colour numbers) scaled to w x h: each new pixel the
    most common colour of the ones it covers (transparent only if they all
    are, so thin limbs survive)."""
    sh, sw = len(px), len(px[0])
    out = []
    for y in range(h):
        y0, y1 = y * sh // h, max(y * sh // h + 1, (y + 1) * sh // h)
        row = []
        for x in range(w):
            x0, x1 = x * sw // w, max(x * sw // w + 1, (x + 1) * sw // w)
            counts = {}
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    v = px[yy][xx]
                    if v:
                        counts[v] = counts.get(v, 0) + 1
            row.append(max(counts, key=lambda v: (counts[v], -v)) if counts else 0)
        out.append(row)
    return out


def mirror(px):
    return [list(reversed(r)) for r in px]


# ------------------------------------------------- the vision modes' figures
# In a vision mode (night vision, thermal) the game draws a second set of the
# figures, made from the first: each pixel is one of its figure's 3 roles,
# and each role is one Layer 2 entry (SPR_PAL0 + VISION_BASE[fig] + role)
# that the vision palettes colour (tools/visionpal.py): a human bright green
# in night vision, white face, yellow core and orange outline in thermal.
#   outline: an edge pixel (one with a transparent pixel beside it, left,
#            right, above or below) next to the core (any of its 8);
#   face:    any other pixel in the top quarter of the rows (at least the
#            top row);
#   core:    the rest (a thin limb, with no core beside it, is core too).
VISION_ROLES = 3                        # face, core, outline: + 0, 1, 2
ROLE_FACE, ROLE_CORE, ROLE_OUTLINE = 0, 1, 2
VISION_BASE = {"human": 1, "zombie": 4, "ghoul": 7, "ghost": 10, "banshee": 13, "lich": 16}
assert max(VISION_BASE.values()) + VISION_ROLES <= COLOURS


def vision_pixels(px, fig):
    """A level's pixels as the vision set's: each opaque pixel its role's
    colour number (VISION_BASE[fig] + role), transparent stays 0."""
    h, w = len(px), len(px[0])

    def opaque(x, y):
        return 0 <= x < w and 0 <= y < h and px[y][x] != 0
    core = {(x, y) for y in range(h) for x in range(w)
            if opaque(x, y) and all(opaque(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    face_rows = max(1, h // 4)
    base = VISION_BASE[fig]
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            if not opaque(x, y):
                row.append(0)
                continue
            if (x, y) in core:
                role = ROLE_CORE
            elif any((x + dx, y + dy) in core for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                role = ROLE_OUTLINE
            else:
                role = ROLE_CORE            # a thin part: no core beside it
            if role != ROLE_OUTLINE and y < face_rows:
                role = ROLE_FACE
            row.append(base + role)
        out.append(row)
    return out


# ---------------------------------------------------- the game's binary file
# ZPDATA/SPRITES.ZPG:
#   +0   4    "ZPGF"
#   +4   1    format version (2)
#   +5   1    pages (8K each, from PAGE_GFX0), 1..GFX_PAGES_MAX
#   +6   1    directory entries: 2 x the purposes (the game's GFX_ENTRIES)
#   +7   9    (reserved, 0)
#   +16  pages x 8192: the pages, each loaded to $C000 (slot 6)
# Page 0 starts with the directory (GFX_DIR, $C000):
#   the purposes, 4 bytes each in ANIMS order, then again for the vision
#     set (vision_pixels: entry GFX_ANIMS + n is purpose n's): frames, 0,
#     address of its frame list (2);
#   a frame list: an address (2) per frame, of its levels of detail:
#   levels: a count, then 7 bytes each, the farthest first (min_z largest):
#     min_z (2), width, height, page (0..), address of its pixels (2);
#   pixels: a row at a time, its first drawn pixel's column (from the left),
#     the number of pixels, then each a Layer 2 palette entry (SPR_PAL0 +
#     colour) or 0 (transparent, skipped).
MAGIC = b"ZPGF"
BIN_VERSION = 2
HEADER = 16
PAGE = 8192
GFX_ADDR = 0xC000
GFX_PAGES_MAX = 4


def lod_bytes(lod, fig=None):
    """A level's pixel data (the rows, as the game draws them); with fig,
    the vision set's (vision_pixels)."""
    px = pixels(lod)
    if fig is not None:
        px = vision_pixels(px, fig)
    out = bytearray()
    for r in px:
        opaque = [i for i, v in enumerate(r) if v]
        if not opaque:
            out += bytes((0, 0))
            continue
        a, b = opaque[0], opaque[-1]
        out += bytes((a, b - a + 1))
        out += bytes(SPR_PAL0 + v if v else 0 for v in r[a:b + 1])
    return bytes(out)


def build(figures):
    """figures: {name: data} for every figure -> (the file's bytes, pages
    used, bytes used).  ValueError if it won't fit."""
    # the directory's size first: then the pixel blocks after it
    entries = []                        # per purpose: [frame: [(min_z, w, h, bytes)]]
    for vision in (False, True):        # the purposes, then their vision set
        for fig, a in ANIMS:
            d = figures[fig]
            zs = min_zs(d)[a]
            frames = []
            for fi, fr in enumerate(d["anims"][a]["frames"]):
                lods = []
                for li, lod in enumerate(fr["lods"]):
                    w, h = lod_size(lod)
                    lods.append((zs[fi][li], w, h, lod_bytes(lod, fig if vision else None)))
                frames.append(sorted(lods, key=lambda t: -t[0]))     # farthest first
            entries.append(frames)
    assert len(entries) == 2 * len(ANIMS)
    dir_size = 4 * len(entries)
    for frames in entries:
        dir_size += 2 * len(frames) + sum(1 + 7 * len(l) for l in frames)
    if dir_size > PAGE:
        raise ValueError("the directory doesn't fit in a page")
    # place the pixel blocks: page 0 after the directory, then the next pages
    pages = [bytearray(PAGE)]
    page, off = 0, dir_size
    placed = {}
    for ai, frames in enumerate(entries):
        for fi, lods in enumerate(frames):
            for li, (_, w, h, data) in enumerate(lods):
                if len(data) > PAGE:
                    raise ValueError("a level of detail over 8K")
                if off + len(data) > PAGE:
                    page += 1
                    off = 0
                    if page >= GFX_PAGES_MAX:
                        raise ValueError(f"the figures need more than {GFX_PAGES_MAX} pages (32K)")
                    pages.append(bytearray(PAGE))
                pages[page][off:off + len(data)] = data
                placed[ai, fi, li] = (page, GFX_ADDR + off)
                off += len(data)
    # the directory
    d = pages[0]
    p = 4 * len(entries)                # after the purpose table
    for ai, frames in enumerate(entries):
        d[4 * ai] = len(frames)
        d[4 * ai + 2:4 * ai + 4] = (GFX_ADDR + p).to_bytes(2, "little")
        flist = p
        p += 2 * len(frames)
        for fi, lods in enumerate(frames):
            d[flist + 2 * fi:flist + 2 * fi + 2] = (GFX_ADDR + p).to_bytes(2, "little")
            d[p] = len(lods)
            p += 1
            for li, (z, w, h, _) in enumerate(lods):
                pg, addr = placed[ai, fi, li]
                d[p:p + 7] = bytes((z & 255, z >> 8, w, h, pg, addr & 255, addr >> 8))
                p += 7
    assert p == dir_size
    used = page * PAGE + off
    head = MAGIC + bytes((BIN_VERSION, len(pages), len(entries))) + bytes(HEADER - 7)
    return head + b"".join(bytes(pg) for pg in pages), len(pages), used
