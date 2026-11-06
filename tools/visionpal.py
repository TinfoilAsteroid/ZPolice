"""Z-Police vision palettes: the Layer 2 palettes the game swaps in for the
VTOL's vision modes (salvage rewards: night vision green and monochrome,
thermal).  Shared by gentables.py (which makes them) and the map editor.

Each level gets ZPDATA/LEVELnn.ZPV, made by gentables.py:
  +0   4     "ZPVS"
  +4   1     format version (1)
  +5   1     level number
  +6   2     (reserved, 0)
  +8   2048  4 Layer 2 palettes, 256 RRRGGGBB / low-blue-bit pairs each (as
             NextReg $44), by vision mode (MODES' order): normal (the
             level's own palette, or its city's), night vision green,
             night vision monochrome, thermal
load_level (level_load.asm) reads it; the vision control (K_VISION) swaps
the mode's palette in (vis_apply).

Each vision palette is generated from the level's normal one (vision()):
  * the building colours, roads, wall (the sky), edges and street dots:
    each colour's brightness, as green (night vision green), white to grey
    (monochrome), or blue (thermal: cold buildings, their roofs warmer,
    towards magenta and red);
  * the fixed colours of the HUD, the city map, the gunsight and the
    reticule, tracers, the laser and particles: kept (KEEP), so they read
    the same in every mode;
  * the figures' entries (SPR_PAL0..): their vision set's role colours
    (FIGURE_COLOURS; the roles: tools/spritefile.py, vision_pixels).

Editable: levels/LEVELnn_NVG.json, _NVM.json, _THM.json (the format of
levels/LEVELnn_PAL.json: tools/levelpal.py), if there is one, is used in
place of the generated palette for that mode.  The map editor edits them
(in level mode: the four palettes side by side); gentables.py also writes
the generated ones to levels/generated/, for reference.
"""
import os

import levelpal
import spritefile as sf

MAGIC = b"ZPVS"
BIN_VERSION = 1
MODES = ["normal", "NVG", "NVM", "THM"]     # vision_mode 0..3 (zpolice.asm)
MODE_NAMES = {"NVG": "night vision, green", "NVM": "night vision, monochrome",
              "THM": "thermal"}
BIN_SIZE = 8 + 512 * len(MODES)

# Fixed colours kept in every mode (indices: gentables.py FIXED, zpolice.asm)
KEEP = {15, 19,                         # HUD_COL, HUD_WARN (gunsight)
        31, 35,                         # BULLET_COL, LASER_COL (tracers, beam,
                                        #   the missile reticule)
        39, 47, 51, 55,                 # the city map: MAP_BG, HUMAN_BLIP,
                                        #   MAP_ZOMBIE_MID, _DARK
        91, 95,                         # PANEL_L2, GAUGE_AMBER
        99, 103, 107, 111,              # ghost blips and fade steps
        115, 119, 123, 127,             # banshee blips and fade steps
        59, 63, 67, 71, 75, 79, 83, 87,     # zombie burst particles
        131, 135, 139, 143, 147, 151, 155, 159, 163, 167}   # fire particles
GROUND_IDX = 7                          # GROUND_COL: the roads

# The roads, and each figure's role colours (face, core, outline), by mode
ROAD = {"NVG": (0, 1, 0), "NVM": (2, 2, 2), "THM": (0, 0, 1)}
FIGURE_COLOURS = {
    "NVG": {"human": [(4, 7, 4), (2, 7, 2), (2, 7, 2)],     # bright green
            "zombie": [(0, 5, 0), (0, 4, 0), (0, 4, 0)],    # mid green
            "ghoul": [(0, 5, 0), (0, 4, 0), (0, 4, 0)],
            "ghost": [(0, 0, 0), (0, 0, 0), (0, 0, 0)],     # black
            "banshee": [(0, 0, 0), (0, 0, 0), (0, 0, 0)],
            "lich": [(4, 7, 4), (0, 5, 0), (0, 3, 0)]},     # a bright head
    "NVM": {"human": [(7, 7, 7), (7, 7, 7), (6, 6, 6)],     # white
            "zombie": [(5, 5, 5), (4, 4, 4), (4, 4, 4)],    # mid grey
            "ghoul": [(5, 5, 5), (4, 4, 4), (4, 4, 4)],
            "ghost": [(0, 0, 0), (0, 0, 0), (0, 0, 0)],     # black
            "banshee": [(0, 0, 0), (0, 0, 0), (0, 0, 0)],
            "lich": [(7, 7, 7), (5, 5, 5), (3, 3, 3)]},     # a white head
    "THM": {"human": [(7, 7, 7), (7, 7, 0), (7, 4, 0)],     # white face, yellow
                                                            #   core, orange outline
            "zombie": [(7, 4, 0), (6, 0, 0), (6, 0, 0)],    # orange face, red body
            "ghoul": [(7, 4, 0), (6, 0, 0), (6, 0, 0)],
            "ghost": [(6, 0, 0), (6, 0, 0), (7, 7, 7)],     # red body, white outline
            "banshee": [(6, 0, 0), (6, 0, 0), (7, 7, 7)],
            "lich": [(7, 7, 7), (6, 0, 6), (7, 0, 0)]},     # white head, hot magenta
}


def path_for(level_dir, lv, mode):
    """A level's hand-tuned vision palette: levels/LEVELnn_<mode>.json."""
    return os.path.join(level_dir, f"LEVEL{lv:02d}_{mode}.json")


def lum(c):
    """A colour's brightness, 0..1."""
    r, g, b = c
    return (0.299 * r + 0.587 * g + 0.114 * b) / 7


SHADE_ROOF = 2                          # a family's roof entry (family*4 + 2)


def shade(c, mode, roof=False):
    """Colour c in the mode: its brightness as green, grey, or (thermal)
    cold blue, a roof warmer (towards magenta and red: the sun's heat)."""
    L = lum(c)
    if mode == "NVG":
        return (0, 1 + round(6 * L), 0)
    if mode == "NVM":
        v = 2 + round(5 * L)
        return (v, v, v)
    if roof:
        return (2 + round(4 * L), round(1.5 * L), 2 + round(2 * L))   # THM: warm roofs
    return (0, round(2 * L), 1 + round(5 * L))      # THM: cold blues


def vision(normal, mode):
    """The mode's palette (256 (r, g, b)) from the level's normal one (or
    any palette: the map editor's Convert)."""
    out = []
    for i, c in enumerate(normal):
        if i in KEEP:
            out.append(tuple(c))
        elif i == GROUND_IDX:
            out.append(ROAD[mode])
        elif sf.SPR_PAL0 <= i < sf.SPR_PAL0 + sf.COLOURS:
            out.append((0, 0, 0))       # (the roles, below)
        else:
            out.append(shade(c, mode, roof=(i % 4 == SHADE_ROOF)))
    for fig, base in sf.VISION_BASE.items():
        for role, col in enumerate(FIGURE_COLOURS[mode][fig]):
            out[sf.SPR_PAL0 + base + role] = col
    assert not any(map(levelpal.is_transparent, out))
    return out


def pal_pair(c):
    r, g, b = c
    return bytes(((r << 5) | (g << 2) | (b >> 1), b & 1))


def binary(lv, palettes):
    """ZPDATA/LEVELnn.ZPV: the 4 palettes (MODES' order), 256 (r, g, b) each."""
    assert len(palettes) == len(MODES) and all(len(p) == 256 for p in palettes)
    data = MAGIC + bytes((BIN_VERSION, lv, 0, 0)) + b"".join(pal_pair(c) for p in palettes for c in p)
    assert len(data) == BIN_SIZE
    return data
