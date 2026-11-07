"""Z-Police figure graphics: sprites/*.json (made with tools/sprite_editor.py)
-> ZPDATA/SPRITES.ZPG (loaded by the game at start-up) and gfx_ids.inc (the
purposes' ANIM_ numbers and the constants the game draws them with).
The format is in tools/spritefile.py.  Run by build.bat (after gentables.py,
which puts the figure colours, sprites/palette.json, into every palette).

A missing file is made from the original stick figures (in colour), and
then edited from there on.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
import spritefile as sf

os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(sf.SPRITE_DIR, exist_ok=True)
DATA_DIR = "ZPDATA"

# ---------------------------------------------------------------------------
# The starting palette and figures
DEFAULT_PALETTE = [
    (0, 0, 0),              # 0: transparent (never drawn)
    (0, 0, 0),              # 1 black
    (7, 7, 7),              # 2 white
    (5, 5, 5),              # 3 light grey
    (3, 3, 3),              # 4 grey
    (1, 1, 1),              # 5 dark grey
    (7, 5, 3),              # 6 skin
    (5, 3, 2),              # 7 dark skin
    (4, 6, 2),              # 8 zombie skin (pale olive)
    (2, 4, 1),              # 9 dark zombie skin
    (4, 0, 0),              # 10 dark red (blood)
    (7, 1, 1),              # 11 red
    (2, 3, 7),              # 12 blue (shirt)
    (1, 1, 4),              # 13 dark blue (trousers)
    (4, 2, 1),              # 14 brown
    (2, 1, 0),              # 15 dark brown
    (7, 7, 0),              # 16 yellow
    (5, 5, 0),              # 17 dark yellow
    (1, 6, 1),              # 18 green
    (0, 3, 0),              # 19 dark green
    (7, 4, 0),              # 20 orange
    (5, 1, 6),              # 21 purple
    (2, 0, 3),              # 22 dark purple
    (2, 7, 7),              # 23 cyan
    (0, 4, 4),              # 24 dark cyan
    (6, 6, 5),              # 25 bone
    (3, 4, 3),              # 26 grey-green (ghoul skin)
    (1, 2, 1),              # 27 dark grey-green
    (7, 6, 6),              # 28 pale pink
    (6, 2, 2),              # 29 dull red
    (3, 2, 1),              # 30 mud
    (1, 1, 2),              # 31 navy
]

Z_TOP_F = ["..###...", "..###...", "..###...", "...#....", ".#####..",
           "#.###.#.", "#.###.#.", "..###...", "..###...", "..#.#..."]
Z_TOP_L = ["...##...", "..###...", "...##...", "...#....", "#####...",
           "...##...", "...##...", "...##...", "...##...", "...##..."]
Z_LEGS = {
    0: [["..#.#...", "..#.#...", "..#.#...", "..#.#...", "..#.#...", ".##.##.."],
        ["..#.#...", "..#.#...", "..#.#...", ".##.#...", "....#...", "....##.."],
        ["..#.#...", "..#.#...", "..#.#...", "..#.#...", "..#.#...", ".##.##.."],
        ["..#.#...", "..#.#...", "..#.#...", "..#.##..", "..#.....", ".##....."]],
    1: [["..#..#..", "..#..#..", ".#....#.", ".#....#.", "#.....#.", "##....##"],
        ["...#.#..", "...#.#..", "..#..#..", "..#.#...", ".#..#...", "##..##.."],
        ["...##...", "...##...", "...##...", "...##...", "...##...", "..###..."],
        ["...#.#..", "...#.#..", "...#..#.", "...#..#.", "...#..#.", "..##..##"]],
}
H_TOP_F = ["...###..", "...###..", "...###..", "....#...", "...###..",
           "..#.#.#.", "..#.#.#.", "..#.#.#.", "..#.#.#.", "....#..."]
GHOST_BODY = ["..####..", ".######.", ".######.", ".#.##.#.", ".######.",
              "########", "########", ".######.", ".######.", ".######.",
              ".######.", ".######.", ".######."]
GHOST_HEMS = [["##.##.##", "#..#..#.", "..#..#.."], ["#.##.##.", ".#..#..#", "..#..#.."]]
BANSHEE_BODY = ["...##...", "..####..", "..#..#..", "..####..", ".######.",
                ".#.##.#.", "...##...", "..####..", "..####..", "..####..",
                "..####..", "..####..", "..####.."]
BANSHEE_HEMS = [["..#..#..", ".#....#.", "...##..."], ["..#.#.#.", "..#..#..", "...##..."]]


def human_wave(hand_col):
    g = [list("........") for _ in range(16)]
    def put(r, c):
        if 0 <= r < 16 and 0 <= c < 8:
            g[r][c] = "#"
    for r in range(0, 3):
        for c in range(3, 6):
            put(r, c)
    put(3, 4)
    for c in range(3, 6):
        put(4, c)
    for r in range(5, 10):
        put(r, 4)
    for r in range(5, 9):
        put(r, 6)
    put(4, 6)
    r0, c0, r1, c1 = 4, 2, 0, hand_col
    n = max(abs(r1 - r0), abs(c1 - c0))
    for k in range(n + 1):
        put(round(r0 + (r1 - r0) * k / n), round(c0 + (c1 - c0) * k / n))
    for r in range(10, 15):
        put(r, 3); put(r, 5)
    put(15, 2); put(15, 3); put(15, 5); put(15, 6)
    return ["".join(row) for row in g]


def colour(art, head, body, legs, feet, head_rows=4, legs_from=10):
    """'#' art (16 rows) -> colour numbers: the head rows, the body, the legs,
    the last row (feet) each their colour."""
    out = []
    for y, row in enumerate(art):
        c = head if y < head_rows else body if y < legs_from else feet if y == len(art) - 1 else legs
        out.append([c if ch == "#" else 0 for ch in row])
    return out


def lods_of(px, height):
    """The levels of detail of an 8x16 frame: 16, 12, 8 and 4 rows high."""
    lods = []
    for k, (w, h) in enumerate([(8, 16), (6, 12), (4, 8), (2, 4)]):
        p = px if (w, h) == (8, 16) else sf.shrink(px, w, h)
        lods.append({"min_z": 0 if k == 0 else None, **sf.from_pixels(p)})
    return {"lods": lods}


def walker(skin, shirt, trousers, shoes, height):
    """walk_front / _side / _rear from the zombie stick men"""
    front = [colour(Z_TOP_F + Z_LEGS[0][f], skin, shirt, trousers, shoes) for f in range(4)]
    side = [colour(Z_TOP_L + Z_LEGS[1][f], skin, shirt, trousers, shoes) for f in range(4)]
    rear = [sf.mirror(p) for p in front]
    return {"walk_front": {"frames": [lods_of(p, height) for p in front]},
            "walk_side": {"frames": [lods_of(p, height) for p in side]},
            "walk_rear": {"frames": [lods_of(p, height) for p in rear]}}


# The lich: a skeleton in a crown, 16 x 32, its legs in 2 frames.  B bone,
# d dark grey (shadow), Y gold, y dark gold, R red (eyes, the crown's jewels)
LICH_TOP_F = ["....Y..YY..Y....", "....YY.YY.YY....", "....YYYYYYYY....", "....yRyyyyRy....",
              ".....BBBBBB.....", ".....BBBBBB.....", ".....BRBBRB.....", ".....BBBBBB.....",
              "......BddB......", "......BdBd......", ".......BB.......", "...BBBBBBBBBB...",
              "..BB.BBBBBB.BB..", "..B..B.BB.B..B..", "..B..BBBBBB..B..", "..B..B.BB.B..B..",
              "..B..BBBBBB..B..", "..B...B..B...B..", "..B...BBBB...B..", ".BB....BB....BB."]
LICH_TOP_S = [".....Y.YY.Y.....", ".....YYYYYY.....", ".....YYYYYY.....", ".....yRyyyy.....",
              "....BBBBBBB.....", "....BBBBBBB.....", "....BRBBBBB.....", "....BBBBBBB.....",
              ".....BdBBB......", ".....dBBB.......", ".......BB.......", "......BBBB......",
              ".....BBBBBB.....", "....BBBB.BB.....", "....BBBBBB......", "...BB.BB.BB.....",
              "...B.BBBBB......", "..BB..B.BB......", "..B...BBB.......", ".BB....BB......."]
LICH_LEGS_F = [["......BBBB......", ".....BBBBBB.....", ".....BB..BB.....", ".....B....B.....",
                ".....B....B.....", ".....B....B.....", "....BB....B.....", "....B.....B.....",
                "....B.....BB....", "....B......B....", "...BB......BB...", "...BBB.....BBB.."],
               ["......BBBB......", ".....BBBBBB.....", ".....BB..BB.....", ".....B....B.....",
                ".....B....B.....", ".....B....B.....", ".....B....BB....", ".....B.....B....",
                "....BB.....B....", "....B......B....", "...BB......BB...", "..BBB.....BBB..."]]
LICH_LEGS_S = [["......BBB.......", ".....BBBBB......", ".....BB.BB......", "....BB...B......",
                "....B....BB.....", "....B.....B.....", "...BB.....B.....", "...B......BB....",
                "...B.......B....", "..BB.......B....", "..B........BB...", ".BBB.......BBB.."],
               ["......BBB.......", ".....BBBBB......", "......BBB.......", "......BB........",
                "......BB........", ".......B........", ".......BB.......", "........B.......",
                "........B.......", "........BB......", ".........B......", ".......BBBB....."]]
LICH_COL = {".": 0, "B": 25, "d": 4, "Y": 16, "y": 17, "R": 11}


def lich_lods(art):
    """The levels of detail of a 16 x 32 lich frame."""
    px = [[LICH_COL[ch] for ch in row] for row in art]
    lods = []
    for k, (w, h) in enumerate([(16, 32), (12, 24), (8, 16), (6, 12), (3, 6)]):
        p = px if k == 0 else sf.shrink(px, w, h)
        lods.append({"min_z": 0 if k == 0 else None, **sf.from_pixels(p)})
    return {"lods": lods}


def lich_figure():
    front = [LICH_TOP_F + legs for legs in LICH_LEGS_F]
    side = [LICH_TOP_S + legs for legs in LICH_LEGS_S]
    rear = [[row.replace("R", "B").replace("d", "B")[::-1] for row in f] for f in front]
    return {"walk_front": {"frames": [lich_lods(f) for f in front]},
            "walk_side": {"frames": [lich_lods(f) for f in side]},
            "walk_rear": {"frames": [lich_lods(f) for f in rear]}}


def default_figure(fig):
    H = sf.figure_height(fig)
    if fig == "lich":
        anims = lich_figure()
    elif fig == "zombie":
        anims = walker(8, 14, 15, 5, H)
    elif fig == "fast_zombie":
        anims = walker(18, 14, 15, 5, H)    # a zombie with a bright green head
    elif fig == "ghoul":
        anims = walker(26, 22, 27, 5, H)
    elif fig in ("ghost", "banshee"):
        body, hems, col = ((GHOST_BODY, GHOST_HEMS, 2) if fig == "ghost"
                           else (BANSHEE_BODY, BANSHEE_HEMS, 16))
        frames = [lods_of([[col if ch == "#" else 0 for ch in r] for r in body + hem], H)
                  for hem in hems]
        anims = {"float": {"frames": frames}}
    else:                               # human: waving, and running
        wave = [colour(human_wave(hc), 6, 12, 13, 5, head_rows=4, legs_from=10)
                for hc in (0, 1, 2, 1)]
        front = [colour(H_TOP_F + Z_LEGS[0][f], 6, 12, 13, 5) for f in range(4)]
        side = [colour(Z_TOP_L + Z_LEGS[1][f], 6, 12, 13, 5) for f in range(4)]
        rear = [sf.mirror(p) for p in front]
        anims = {"wave": {"frames": [lods_of(p, H) for p in wave]},
                 "run_front": {"frames": [lods_of(p, H) for p in front]},
                 "run_side": {"frames": [lods_of(p, H) for p in side]},
                 "run_rear": {"frames": [lods_of(p, H) for p in rear]},
                 "stand": {"frames": [lods_of(colour(H_TOP_F + Z_LEGS[0][0], 6, 12, 13, 5), H)]}}
    return {"name": fig, "height": H, "anims": anims}


# ---------------------------------------------------------------------------
if not os.path.exists(sf.PAL_FILE):
    sf.save_palette(DEFAULT_PALETTE, sf.default_vision(DEFAULT_PALETTE))
    print(f"wrote {os.path.relpath(sf.PAL_FILE)} (the starting colours: edit them with tools/sprite_editor.py)")
pal = sf.load_palette()
try:
    errs = sf.palette_problems(pal, sf.load_vision())
except ValueError as e:
    errs = [str(e)]
if errs:
    raise SystemExit(f"{sf.PAL_FILE}: the colours can't be used:\n  " + "\n  ".join(errs))

figures = {}
for fig in sf.FIGURE_NAMES:
    p = sf.figure_path(fig)
    if not os.path.exists(p):
        sf.save(p, default_figure(fig))
        print(f"wrote {os.path.relpath(p)} (from the stick figures: edit it with tools/sprite_editor.py)")
    try:
        d = sf.load(p)
        new = [a for a, _ in sf.figure_anims(fig) if a not in d["anims"]]
        if new:                         # a purpose the game has added
            dflt = default_figure(fig)["anims"]
            d["anims"].update({a: dflt[a] for a in new})
            sf.save(p, d)
            print(f"added {', '.join(new)} to {os.path.relpath(p)} (from the stick figures: "
                  "edit with tools/sprite_editor.py)")
        errs = sf.problems(fig, d)
    except (OSError, ValueError) as e:
        errs = [str(e)]
    if errs:
        raise SystemExit(f"{p}: the figure can't be used:\n  " + "\n  ".join(errs))
    figures[fig] = d

data, npages, used = sf.build(figures)


def write_data(name, data):
    """Only if changed (the folder is synced by OneDrive: see gentables.py)."""
    path = os.path.join(DATA_DIR, name)
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    except OSError:
        pass
    with open(path, "wb") as f:
        f.write(data)
    return True


changed = write_data("SPRITES.ZPG", data)
print(f"{'wrote' if changed else 'unchanged'} {DATA_DIR}/SPRITES.ZPG: {len(sf.ANIMS)} purposes, "
      f"{npages} page(s), {used} of {npages * sf.PAGE} bytes used")

inc = ["; ---- generated by gengraphics.py - do not edit ----",
       "; The figures' graphics (tools/spritefile.py has the format): the purposes",
       "; the game asks for, in ZPDATA/SPRITES.ZPG's order",
       f"SPR_PAL0        equ {sf.SPR_PAL0}     ; Layer 2 entry of figure colour 0",
       f"GFX_ANIMS       equ {len(sf.ANIMS)}",
       f"GFX_ENTRIES     equ {len(sf.ANIMS)}     ; the directory: the purposes (the vision modes: by palette)",
       f"GFX_PAGES_MAX   equ {sf.GFX_PAGES_MAX}",
       f"GFX_MIN_H       equ {sf.GFX_MIN_H}      ; the sizes drawn, in rows",
       f"GFX_MAX_H       equ {sf.GFX_MAX_H}",
       f"GFX_DIR         equ ${sf.GFX_ADDR:04X}",
       f"GFX_VERSION     equ {sf.BIN_VERSION}",
       f"GFX_HEADER      equ {sf.HEADER}"]
for n, (fig, a) in enumerate(sf.ANIMS):
    inc.append(f"{sf.anim_label(fig, a):<32}equ {n}")
for fig, h, _ in sf.FIGURES:
    inc.append(f"{('FIG_' + fig.upper() + '_H'):<32}equ {h}      ; its height (world units)")
text = "\n".join(inc) + "\n"
if not os.path.exists("gfx_ids.inc") or open("gfx_ids.inc").read() != text:
    with open("gfx_ids.inc", "w") as f:
        f.write(text)
print("gfx_ids.inc:", ", ".join(sf.anim_label(f, a) for f, a in sf.ANIMS))
