"""Z-Police figure graphics (humans and monsters): the format shared by the
sprite editor (tools/sprite_editor.py) and gengraphics.py.

The colours: sprites/palette.json, 32 colours, r g b 0..7 each, and each
one's colour in each vision mode (VISION_MODES: night vision green and
monochrome, thermal):

    {"format": "Z-Police figure palette", "version": 1,
     "colours": [[r, g, b], ...32],
     "vision": {"NVG": [[r, g, b], ...32], "NVM": [...], "THM": [...]}}

Colour 0 is transparent (never drawn), so 31 are usable.  They are Layer 2
palette entries SPR_PAL0 (192) .. SPR_PAL0+31, families 48-55, which no
building or fixed colour uses: gentables.py puts them in every city's palette
(and every level's own), so the figures look the same everywhere; and the
"vision" colours in the vision modes' palettes (tools/visionpal.py).  So a
vision mode recolours the figures by palette alone: the game has one set of
figure graphics.  A colour's vision colours are its own, whichever figures
use it: two figures meant to look different in a vision mode need colours of
their own (shared_colours lists the ones shared).  An outline that shows in
a vision mode is drawn: a second colour, the same in normal view (the
ghost's two whites: in thermal one is its white outline, the other its red
body).

A figure: sprites/NAME.json, one per figure in FIGURES (zombie,
fast_zombie, ghoul, ghost, banshee, human, lich):

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
is the figure's projected height (auto_min_z).  The game draws a figure at
its true projected height, a row at a time, from GFX_MIN_H to GFX_MAX_H rows:
build makes each size (sized) from the level for that distance, which it
scales unless it's that size already, so a level drawn by hand is used as it
stands at its own size.  Its bottom centre is on the figure's feet.  A side
view faces left: the game mirrors it for a figure facing right.

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
MAX_FRAMES, MAX_LODS = 16, 40         # (every size the game draws, by hand)
PROJ = 128                              # screen pixels per (world unit / Z)

# The figures, their heights (world units) and the purposes the game asks
# for: (name, description).  Their order is the game's ANIM_ numbers: change
# it only with the game (gfx_ids.inc is generated from it).
FIGURES = [
    ("zombie", 26, [("walk_front", "walking towards the camera"),
                    ("walk_side", "walking, side on, facing left (mirrored for right)"),
                    ("walk_rear", "walking away from the camera")]),
    ("fast_zombie", 26, [("walk_front", "walking towards the camera"),
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
VISION_MODES = ("NVG", "NVM", "THM")    # (visionpal.MODES after "normal")


def default_vision(pal):
    """Each colour's vision colours, from its brightness: green (night vision
    green), grey (monochrome), red to yellow (thermal: figures are warm)."""
    out = {m: [] for m in VISION_MODES}
    for i, (r, g, b) in enumerate(pal):
        L = (0.299 * r + 0.587 * g + 0.114 * b) / 7
        v = round(2 + 5 * L)
        out["NVG"].append((0, v, 0))
        out["NVM"].append((v, v, v))
        out["THM"].append((7, round(6 * L), 0) if L > 0.4 else (round(4 + 3 * L), 0, 0))
        if i == 0:
            for m in VISION_MODES:
                out[m][-1] = (0, 0, 0)
    return out


def load_vision(path=PAL_FILE):
    """sprites/palette.json's vision colours -> {mode: 32 (r, g, b)}, or from
    the colours' brightness if it has none.  ValueError if malformed."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    v = d.get("vision")
    if v is None:
        return default_vision(load_palette(path))
    try:
        out = {m: [tuple(int(c) for c in col) for col in v[m]] for m in VISION_MODES}
    except (KeyError, TypeError, ValueError):
        raise ValueError(f"{path}: \"vision\" needs {', '.join(VISION_MODES)}, each [r, g, b] x {COLOURS}")
    if any(len(t) != COLOURS for t in out.values()):
        raise ValueError(f"{path}: each vision mode needs {COLOURS} colours")
    return out


def shared_colours(figures):
    """{colour: [figures]} for the colours more than one figure uses (a
    vision mode colours them alike: zombie and fast_zombie mean to)."""
    users = {}
    for f, d in figures.items():
        cs = {PIXEL_CHARS.index(ch) for an in d["anims"].values() for fr in an["frames"]
              for lod in fr["lods"] for r in lod["rows"] for ch in r if ch != "."}
        for c in cs:
            users.setdefault(c, []).append(f)
    return {c: fs for c, fs in sorted(users.items()) if len(fs) > 1}


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


def save_palette(pal, vision, path=PAL_FILE):
    def block(cols):
        return ",\n".join(f"  {json.dumps(list(c))}" for c in cols)
    text = ('{\n "format": "%s", "version": %d,\n "colours": [\n' % (PAL_FORMAT, VERSION)
            + block(pal) + "\n ],\n \"vision\": {\n"
            + ",\n".join(f'  "{m}": [\n' + block(vision[m]).replace("\n  ", "\n   ").replace("  [", "   [", 1)
                          + "\n  ]" for m in VISION_MODES)
            + "\n }\n}\n")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def palette_problems(pal, vision=None):
    errs = []
    sets = [("", pal)] + [(f"{m} ", vision[m]) for m in VISION_MODES] if vision else [("", pal)]
    for name, cols in sets:
        for i, c in enumerate(cols):
            if len(c) != 3 or any(not 0 <= v <= 7 for v in c):
                errs.append(f"{name}colour {i}: r, g, b are 0..7")
            elif i and is_transparent(c):
                errs.append(f"{name}colour {i}: {tuple(c)} is Layer 2's transparent colour")
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


# ---------------------------------------------------- the game's binary file
# ZPDATA/SPRITES.ZPG:
#   +0   4    "ZPGF"
#   +4   1    format version (5)
#   +5   1    pages (8K each, from PAGE_GFX0), 1..GFX_PAGES_MAX
#   +6   1    directory entries: the purposes (the game's GFX_ENTRIES)
#   +7   1    kept pages: the directory and the KEEP_FIGURES' levels and
#             pixels are all in the pages before this one (they're placed
#             first).  The final boss's graphics (DEVIL.ZPB, below) go over
#             the pages from here on in its wave: the other figures aren't
#             drawn then
#   +8   8    (reserved, 0)
#   +16  pages x 8192: the pages, each loaded to $C000 (slot 6)
# Page 0 starts with the directory (GFX_DIR, $C000):
#   the purposes, 4 bytes each in ANIMS order: frames, 0, address of its
#     frame list (2).  (No second set for the vision modes: their palettes
#     recolour these, VISION_MODES);
#   a frame list: 3 bytes per frame: the page (0..) and address (2) of its
#     levels.
# The other pages, and the rest of page 0 (a table doesn't cross a page; a
# table and its pixels may be apart):
#   levels: a count, then 4 bytes each, one to every height from GFX_MIN_H
#     rows up: width, page (0..), address of its pixels (2);
#   pixels: a row at a time, its first drawn pixel's column (from the left),
#     the number of pixels, then each a Layer 2 palette entry (SPR_PAL0 +
#     colour) or 0 (transparent, skipped).
# ZPDATA/SPRITEHW.ZPG, the real-hardware build's (REAL_HARDWARE: one DMA+
# transparent rectangle a figure): the same but "ZPGR", and each level's
# pixels its rectangle, width x height bytes row by row, 0 transparent.
MAGIC = b"ZPGF"
MAGIC_RECT = b"ZPGR"
BIN_VERSION = 5
KEEP_FIGURES = ("human", "zombie", "fast_zombie")   # (the final boss's wave has them)
HEADER = 16
PAGE = 8192
GFX_ADDR = 0xC000
GFX_PAGES_MAX = 58                      # (pages 38 to 95: 86-95 shared with PAGE_L320_BG,
                                        #  read back at a level's start)
GFX_MIN_H, GFX_MAX_H = 3, 32            # the sizes drawn, in rows.  The file
                                        # grows with the cube of GFX_MAX_H


def sized(lods, zs, height, h):
    """The level of detail for a figure drawn h rows high: the one whose
    min_z (zs) is the largest not past the distance of that projected height,
    scaled to h rows and in proportion, unless it is h rows already."""
    z = auto_min_z(height, h)
    lod = max(((m, k) for k, m in enumerate(zs) if m <= z), default=(0, 0))[1]
    lod = lods[lod]
    w0, h0 = lod_size(lod)
    if h0 == h:
        return lod
    w = max(1, (2 * w0 * h + h0) // (2 * h0))
    return from_pixels(shrink(pixels(lod), w, h))


def lod_bytes(lod):
    """A level's pixel data (the rows, as the game draws them)."""
    px = pixels(lod)
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


def lod_rect(lod):
    """A level's pixels as a rectangle (SPRITEHW.ZPG): every row whole."""
    return bytes(SPR_PAL0 + v if v else 0 for r in pixels(lod) for v in r)


def build(figures, rect=False):
    """figures: {name: data} for every figure -> (the file's bytes, pages
    used, bytes used): SPRITES.ZPG, or with rect SPRITEHW.ZPG (each level a
    rectangle).  ValueError if it won't fit.  (keep_pages(file) is its kept
    pages: the KEEP_FIGURES are placed first.)"""
    # the frames, each a list of (width, height, pixels) by height
    entries = []
    for fig, a in ANIMS:
        d = figures[fig]
        zs = min_zs(d)[a]
        frames = []
        for fi, fr in enumerate(d["anims"][a]["frames"]):
            levels = []
            for h in range(GFX_MIN_H, GFX_MAX_H + 1):
                lod = sized(fr["lods"], zs[fi], d["height"], h)
                levels.append((lod_size(lod)[0], lod_rect(lod) if rect else lod_bytes(lod)))
            frames.append(levels)
        entries.append(frames)
    assert len(entries) == len(ANIMS)
    dir_size = 4 * len(entries) + 3 * sum(len(f) for f in entries)
    if dir_size > PAGE:
        raise ValueError("the directory doesn't fit in a page")

    pages = [bytearray(PAGE)]
    page, off = 0, dir_size

    def place(size):
        """Room for size bytes: where -> (page, address)."""
        nonlocal page, off
        if size > PAGE:
            raise ValueError("a level of detail over 8K")
        if off + size > PAGE:
            page += 1
            off = 0
            if page >= GFX_PAGES_MAX:
                raise ValueError(f"the figures need more than {GFX_PAGES_MAX} pages "
                                 f"({GFX_PAGES_MAX * PAGE // 1024}K)")
            pages.append(bytearray(PAGE))
        got = page, GFX_ADDR + off
        off += size
        return got

    # the directory (its frame lists in ANIMS order), then per frame its
    # table of levels and their pixels: the KEEP_FIGURES' first
    d = pages[0]
    p = 4 * len(entries)                # after the purpose table
    lists = []
    for ai, frames in enumerate(entries):
        d[4 * ai] = len(frames)
        d[4 * ai + 2:4 * ai + 4] = (GFX_ADDR + p).to_bytes(2, "little")
        lists.append(p)
        p += 3 * len(frames)
    assert p == dir_size
    kept = [ai for ai, (fig, _) in enumerate(ANIMS) if fig in KEEP_FIGURES]
    keep = None
    for ai in kept + [ai for ai in range(len(entries)) if ai not in kept]:
        if keep is None and ai not in kept:
            keep = page + (1 if off else 0)     # (the kept ones all before it)
        p = lists[ai]
        for levels in entries[ai]:
            tp, ta = place(1 + 4 * len(levels))
            d[p] = tp
            d[p + 1:p + 3] = ta.to_bytes(2, "little")
            p += 3
            t = bytearray((len(levels),))
            for w, data in levels:
                pg, addr = place(len(data))
                pages[pg][addr - GFX_ADDR:addr - GFX_ADDR + len(data)] = data
                t += bytes((w, pg, addr & 255, addr >> 8))
            pages[tp][ta - GFX_ADDR:ta - GFX_ADDR + len(t)] = t
    if keep is None:
        keep = len(pages)
    used = page * PAGE + off
    head = ((MAGIC_RECT if rect else MAGIC) + bytes((BIN_VERSION, len(pages), len(entries), keep))
            + bytes(HEADER - 8))
    return head + b"".join(bytes(pg) for pg in pages), len(pages), used


def keep_pages(data):
    """A built figure file's kept pages (the KEEP_FIGURES' are before it)."""
    return data[7]


# ---------------------------------------------------- the final boss
# The devil (Quatermass's): sprites/devil.json, the figure format, but its
# own: never in SPRITES.ZPG.  DEVIL_ANIMS' frames, each one level of
# DEVIL_W x DEVIL_SRC_H pixels, which the game scales itself to any size
# (devil_draw, city2.asm).  Its eyes are colour DEVIL_EYE_COLOUR, which the
# game draws in its own palette entry, DEVIL_EYE_ENTRY, glowing from black
# to blue as it charges its lightning (red in thermal: devil.asm); and the
# colours in DEVIL_COLOURS are drawn in its own entries too (white, pale
# blue, blue, dark blue; black in thermal).
#
# ZPDATA/DEVIL.ZPB, loaded over the figures' pages from the kept pages on
# (above) when its wave starts:
#   +0   4    "ZPDV"
#   +4   1    format version (1)
#   +5   1    frames (DEVIL_FRAMES), in DEVIL_ANIMS order
#   +6   1    width (DEVIL_W)
#   +7   1    height (DEVIL_SRC_H)
#   +8   8    (reserved, 0)
#   +16  frames x 8192: each frame's pixels, row by row, a Layer 2 palette
#        entry each (SPR_PAL0 + colour; DEVIL_EYE_ENTRY its eyes), 0
#        transparent: one 8K page a frame, at $C000 to draw
DEVIL = "devil"
DEVIL_H = 597                           # world units: 10 building levels (46 m)
DEVIL_W, DEVIL_SRC_H = 64, 128
DEVIL_ANIMS = [("walk_front", "walking towards the camera (2 steps)"),
               ("walk_side", "walking, side on, facing left (mirrored for right)"),
               ("walk_rear", "walking away from the camera")]
DEVIL_FRAMES_EACH = 2
DEVIL_FRAMES = DEVIL_FRAMES_EACH * len(DEVIL_ANIMS)
DEVIL_EYE_COLOUR = 23                   # (cyan in the editor)
DEVIL_EYE_ENTRY = 171                   # (a fixed slot: zpolice.asm DEVIL_EYE)
# Its own colours: these figure colours are drawn in the devil's palette
# entries (gentables.py FIXED DEVIL_COL0..3: black in thermal), not the
# figures' (shared with the other figures, so they'd show in thermal)
DEVIL_COLOURS = {2: 188,                # white
                 21: 189,               # pale blue (white in the editor)
                 12: 190,               # blue
                 13: 191,               # dark blue: its outline
                 DEVIL_EYE_COLOUR: DEVIL_EYE_ENTRY}
# Its own entries' colours, one place for all of them: normal (gentables.py
# puts them in every palette) and in each vision mode (visionpal.py), in
# sprites/devil_palette.json (the sprite editor edits it; made from
# DEVIL_PAL_DEFAULT if missing):
#     {"format": "Z-Police devil palette", "version": 1,
#      "colours": {"188": {"normal": [r, g, b], "NVG": [...], "NVM": [...],
#                          "THM": [...]}, ... "191": ...}}
# Its eyes (DEVIL_EYE_ENTRY) are the game's: black in every palette, set as
# they charge, to DEVIL_EYE_SHOWN fully charged (the editor shows that).
DEVIL_PAL_FILE = os.path.join(SPRITE_DIR, "devil_palette.json")
DEVIL_PAL_FORMAT = "Z-Police devil palette"
DEVIL_PAL_MODES = ("normal",) + VISION_MODES
DEVIL_ENTRIES = (188, 189, 190, 191)    # (gentables.py FIXED DEVIL_COL0..3)
DEVIL_PAL_DEFAULT = {
    188: {"normal": (7, 7, 7), "NVG": (4, 7, 4), "NVM": (7, 7, 7), "THM": (0, 0, 0)},   # white
    189: {"normal": (5, 6, 7), "NVG": (2, 7, 2), "NVM": (6, 6, 6), "THM": (0, 0, 0)},   # pale blue
    190: {"normal": (3, 4, 7), "NVG": (0, 6, 0), "NVM": (5, 5, 5), "THM": (0, 0, 0)},   # blue
    191: {"normal": (1, 1, 3), "NVG": (0, 3, 0), "NVM": (3, 3, 3), "THM": (3, 3, 3)},   # outline
}
DEVIL_EYE_SHOWN = {"normal": (0, 3, 7), "NVG": (7, 7, 7), "NVM": (7, 7, 7), "THM": (7, 0, 0)}


def load_devil_palette(path=DEVIL_PAL_FILE):
    """sprites/devil_palette.json -> {entry: {mode: (r, g, b)}}; the
    defaults if there's no file.  ValueError if malformed."""
    if not os.path.exists(path):
        return {e: dict(m) for e, m in DEVIL_PAL_DEFAULT.items()}
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("format") != DEVIL_PAL_FORMAT:
        raise ValueError(f"{path}: not a {DEVIL_PAL_FORMAT} file")
    try:
        return {e: {m: tuple(int(v) for v in d["colours"][str(e)][m]) for m in DEVIL_PAL_MODES}
                for e in DEVIL_ENTRIES}
    except (KeyError, TypeError, ValueError):
        raise ValueError(f"{path}: needs entries {', '.join(map(str, DEVIL_ENTRIES))}, "
                         f"each [r, g, b] for {', '.join(DEVIL_PAL_MODES)}")


def save_devil_palette(dp, path=DEVIL_PAL_FILE):
    lines = []
    for e in DEVIL_ENTRIES:
        modes = ", ".join(f'"{m}": {json.dumps(list(dp[e][m]))}' for m in DEVIL_PAL_MODES)
        lines.append(f'  "{e}": {{{modes}}}')
    text = ('{\n "format": "%s", "version": %d,\n "colours": {\n' % (DEVIL_PAL_FORMAT, VERSION)
            + ",\n".join(lines) + "\n }\n}\n")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def devil_palette_problems(dp):
    errs = []
    for e in DEVIL_ENTRIES:
        for m in DEVIL_PAL_MODES:
            c = dp[e][m]
            if len(c) != 3 or any(not 0 <= v <= 7 for v in c):
                errs.append(f"entry {e} {m}: r, g, b are 0..7")
            elif is_transparent(c):
                errs.append(f"entry {e} {m}: {tuple(c)} is Layer 2's transparent colour")
    return errs


DEVIL_MAGIC = b"ZPDV"
DEVIL_VERSION = 1
assert DEVIL_W * DEVIL_SRC_H == PAGE


def devil_path():
    return os.path.join(SPRITE_DIR, f"{DEVIL}.json")


def devil_problems(fig_data):
    """What the game can't use in the devil's data, as messages."""
    errs = []
    need = [a for a, _ in DEVIL_ANIMS]
    for a in need:
        if a not in fig_data["anims"]:
            errs.append(f"{a}: missing (the game uses it)")
    for a, an in fig_data["anims"].items():
        if a not in need:
            errs.append(f"{a}: not one of the devil's ({', '.join(need)})")
            continue
        if len(an["frames"]) != DEVIL_FRAMES_EACH:
            errs.append(f"{a}: {DEVIL_FRAMES_EACH} frames")
        for fi, fr in enumerate(an["frames"]):
            if len(fr["lods"]) != 1:
                errs.append(f"{a} frame {fi + 1}: one level ({DEVIL_W}x{DEVIL_SRC_H}: the game scales it)")
                continue
            lod = fr["lods"][0]
            if lod_size(lod) != (DEVIL_W, DEVIL_SRC_H) or any(len(r) != DEVIL_W for r in lod["rows"]):
                errs.append(f"{a} frame {fi + 1}: {DEVIL_W}x{DEVIL_SRC_H} pixels")
            bad = {ch for r in lod["rows"] for ch in r if ch not in PIXEL_CHARS}
            if bad:
                errs.append(f"{a} frame {fi + 1}: unknown pixels {''.join(sorted(bad))!r}")
    return errs


def devil_file(fig_data):
    """sprites/devil.json's data -> ZPDATA/DEVIL.ZPB's bytes."""
    out = DEVIL_MAGIC + bytes((DEVIL_VERSION, DEVIL_FRAMES, DEVIL_W, DEVIL_SRC_H)) + bytes(HEADER - 8)
    for a, _ in DEVIL_ANIMS:
        for fr in fig_data["anims"][a]["frames"]:
            px = pixels(fr["lods"][0])
            out += bytes(DEVIL_COLOURS.get(v, SPR_PAL0 + v) if v else 0
                         for r in px for v in r)
    assert len(out) == HEADER + DEVIL_FRAMES * PAGE
    return out
