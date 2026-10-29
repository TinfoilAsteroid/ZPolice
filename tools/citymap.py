"""Z-Police city map files: the format shared by the map editor
(tools/map_editor.py) and gentables.py.

A city map is maps/CITYnn.json:

    {
      "format": "Z-Police city map", "version": 1,
      "city": 1, "name": "LONDON",
      "map": [64 strings of 64 characters],
      "colours": [64 strings of 64 space-separated fields]
    }

"map": one character per cell, x left to right, z = 0 the first string:
    .        road
    1-9 A-F  a building, height level 1-15 (F = 15: the perimeter wall's)
    P        the landing pad (only at PAD_X, PAD_Z)
    T        terrace: round the pad, or anywhere as an improvised barricade
    X        out of bounds (outside the perimeter wall: never drawn)
"colours": each cell's colour family, "00".."63" (an entry of the city's
palette: 4 colours, the building's face is the second), or ".." for a road
or out of bounds.  A building takes one of the building families,
0..BLD_FAMILIES-1 (its base colour); the pad and terrace always take their
own families (62, 63).  A field that isn't any of these (a hand edit: "64",
"7x") is kept as its text, so the map still loads; on a building it is a
bad colour (bad_colours, validate).

The palette itself is made by gentables.py (from the city's seed and style)
and read back by the editor from ZPDATA/CITYnn.ZPC (read_palette).
"""
import json

GRID = 64
MAP_CHARS = ".123456789ABCDEFPTX"
ROAD, WALL_H, PAD, TERRACE, VOID = 0, 15, 16, 17, 18
PAD_X = PAD_Z = GRID // 2               # the base: the landing pad's cell
TERRACE_R = 2                           # terrace: cells 1..2 out from it
MAX_BARRICADES = 30                     # terrace away from the base (NBARR)
FAMILIES = 64
BLD_FAMILIES = 62                       # buildings' colour families: 0..61
WALL_FAMILY = 0                         # the perimeter wall's colour family
TERRACE_FAMILY = 62
PAD_FAMILY = 63
GROUND_IDX = 7                          # city_col of a road (GROUND_COL)
FORMAT = "Z-Police city map"
VERSION = 1


def is_building(code):
    return 1 <= code <= WALL_H


def base_cells():
    """The base's cells (x, z): the pad and its terrace."""
    return {(x, z) for z in range(PAD_Z - TERRACE_R, PAD_Z + TERRACE_R + 1)
            for x in range(PAD_X - TERRACE_R, PAD_X + TERRACE_R + 1)}


def barricades(cells):
    """The barricades: terrace cells (x, z) away from the base."""
    base = base_cells()
    return [(i % GRID, i // GRID) for i, c in enumerate(cells)
            if c == TERRACE and (i % GRID, i // GRID) not in base]


def pads(cells):
    """The landing pad cells (x, z)."""
    return [(i % GRID, i // GRID) for i, c in enumerate(cells) if c == PAD]


def is_bld_family(f):
    """A building's base colour: a family 0..BLD_FAMILIES-1 (not none, the
    pad's or terrace's, or a field load couldn't read)."""
    return isinstance(f, int) and 0 <= f < BLD_FAMILIES


def bad_colours(cells, fams):
    """The buildings (cell indices) without a valid base colour: none, the
    pad's or terrace's family, or an unreadable field."""
    return [i for i, c in enumerate(cells) if is_building(c) and not is_bld_family(fams[i])]


def family_text(f):
    """A colour field as the JSON holds it."""
    if f is None:
        return ".."
    return f if isinstance(f, str) else f"{f:02d}"


def family_for(code, family):
    """The colour family a cell keeps: its own for a building (whatever it
    is: see bad_colours), the fixed ones for the pad and terrace, None for a
    road or out of bounds."""
    if code == PAD:
        return PAD_FAMILY
    if code == TERRACE:
        return TERRACE_FAMILY
    if is_building(code):
        return family
    return None


def load(path):
    """maps/CITYnn.json -> dict: city, name, cells (GRID*GRID codes),
    fams (GRID*GRID families, None for none, the text of a field that isn't
    a family).  ValueError if malformed."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("format") != FORMAT:
        raise ValueError(f"{path}: not a {FORMAT} file")
    rows, crows = d["map"], d["colours"]
    if len(rows) != GRID or len(crows) != GRID:
        raise ValueError(f"{path}: needs {GRID} map and colour rows")
    cells, fams = [], []
    for z, (row, crow) in enumerate(zip(rows, crows)):
        if len(row) != GRID:
            raise ValueError(f"{path}: map row {z} is {len(row)} cells, not {GRID}")
        f = crow.split()
        if len(f) != GRID:
            raise ValueError(f"{path}: colour row {z} has {len(f)} fields, not {GRID}")
        for x, (ch, t) in enumerate(zip(row, f)):
            if ch not in MAP_CHARS:
                raise ValueError(f"{path}: map ({x}, {z}): unknown character {ch!r}")
            cells.append(MAP_CHARS.index(ch))
            if t == "..":
                fams.append(None)
            elif t.isdigit() and int(t) < FAMILIES:
                fams.append(int(t))
            else:
                fams.append(t)          # (not a family: kept, a bad colour)
    return {"city": d.get("city", 0), "name": d.get("name", ""), "cells": cells, "fams": fams}


def save(path, city, name, cells, fams):
    rows, crows = [], []
    for z in range(GRID):
        rows.append("".join(MAP_CHARS[c] for c in cells[z * GRID:(z + 1) * GRID]))
        crows.append(" ".join(family_text(f) for f in fams[z * GRID:(z + 1) * GRID]))
    d = {"format": FORMAT, "version": VERSION, "city": city, "name": name,
         "map": rows, "colours": crows}
    text = json.dumps(d, indent=1)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text + "\n")


def validate(cells, fams):
    """The problems with a map, as messages (none: the game can use it)."""
    errs = []
    at = lambda x, z: cells[z * GRID + x]
    # the map's edge: wall or out of bounds, so nothing can leave the map
    edge = [(x, z) for z in range(GRID) for x in range(GRID)
            if x in (0, GRID - 1) or z in (0, GRID - 1)]
    bad = [(x, z) for x, z in edge if at(x, z) not in (WALL_H, VOID)]
    if bad:
        errs.append(f"the map's edge must be wall (F) or out of bounds (X): {len(bad)} cells aren't, e.g. {bad[0]}")
    # the base: the pad at (PAD_X, PAD_Z), and nowhere else.  (Terrace can
    # go anywhere: away from the base it is an improvised barricade.)
    if at(PAD_X, PAD_Z) != PAD:
        errs.append(f"the landing pad must be at ({PAD_X}, {PAD_Z})")
    stray = [(x, z) for z in range(GRID) for x in range(GRID)
             if at(x, z) == PAD and (x, z) != (PAD_X, PAD_Z)]
    if stray:
        errs.append(f"landing pad outside the base: {len(stray)} cells, e.g. {stray[0]}")
    # at most MAX_BARRICADES barricades (each has its own hit points)
    nb = len(barricades(cells))
    if nb > MAX_BARRICADES:
        errs.append(f"{nb} barricades (terrace away from the base): at most {MAX_BARRICADES}")
    # buildings need a building colour family (a base colour, 0..BLD_FAMILIES-1)
    bad = [(i % GRID, i // GRID) for i in bad_colours(cells, fams)]
    if bad:
        errs.append(f"buildings without a valid base colour (family 00..{BLD_FAMILIES - 1:02d}): "
                    f"{len(bad)}, e.g. {bad[0]}")
    # out of bounds only behind the wall: every neighbour is out of bounds or wall
    leak = []
    for z in range(GRID):
        for x in range(GRID):
            if at(x, z) != VOID:
                continue
            for dz in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, nz = x + dx, z + dz
                    if 0 <= nx < GRID and 0 <= nz < GRID and at(nx, nz) not in (VOID, WALL_H):
                        leak.append((x, z))
                        break
                else:
                    continue
                break
    if leak:
        errs.append(f"out of bounds (X) must be closed off by wall (F): {len(leak)} cells touch something else, e.g. {leak[0]}")
    return errs


def read_palette(zpc_path):
    """A city's Layer 2 palette from its CITYnn.ZPC: 256 (r, g, b), 0..7."""
    with open(zpc_path, "rb") as f:
        d = f.read()
    if d[:4] != b"ZPCY":
        raise ValueError(f"{zpc_path}: not a city file")
    pal = []
    for i in range(256):
        a, b = d[32 + 2 * i], d[33 + 2 * i]
        pal.append((a >> 5, (a >> 2) & 7, ((a & 3) << 1) | (b & 1)))
    return pal
