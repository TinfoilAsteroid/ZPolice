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
  * the figures' entries (SPR_PAL0..): each figure colour's own colour for
    the mode (sprites/palette.json's "vision", edited in the sprite editor).

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
# The devil's colours (gentables.py FIXED: DEVIL_COL0..3: white, pale blue,
# blue, its dark blue outline) by vision mode: thermal black and dark greys
# (a cold shape), night vision green bright greens, monochrome light greys.
# Its eyes (DEVIL_EYE) black: the game sets them as they charge (red in
# thermal, white in night vision: devil.asm dv_eye).
# (sprites/devil_palette.json: spritefile.load_devil_palette, which the
# sprite editor shows and edits)
_DP = sf.load_devil_palette()
DEVIL_VISION = {m: {**{e: _DP[e][m] for e in sf.DEVIL_ENTRIES}, sf.DEVIL_EYE_ENTRY: (0, 0, 0)}
                for m in ("NVG", "NVM", "THM")}

# The roads, by mode
ROAD = {"NVG": (0, 1, 0), "NVM": (2, 2, 2), "THM": (0, 0, 1)}
FIGURES = sf.load_vision()            # the figure colours' own, by mode


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
        elif i in DEVIL_VISION.get(mode, {}):
            out.append(DEVIL_VISION[mode][i])
        elif sf.SPR_PAL0 <= i < sf.SPR_PAL0 + sf.COLOURS:
            out.append(tuple(FIGURES[mode][i - sf.SPR_PAL0]) if i > sf.SPR_PAL0 else (0, 0, 0))
        else:
            out.append(shade(c, mode, roof=(i % 4 == SHADE_ROOF)))
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
