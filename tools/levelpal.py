"""Z-Police level palette files: the format shared by the map editor
(tools/map_editor.py), gentables.py and the preview (tools/preview.py).

A level can have its own colours: levels/LEVELnn_PAL.json, written by the
map editor when a colour family is edited in level mode (or by hand):

    {
      "format": "Z-Police level palette", "version": 1,
      "level": 7, "city": 2,
      "families": {"00": [[r, g, b], [r, g, b], [r, g, b], [r, g, b]],
                   ...,
                   "63": [...]}
    }

"families": the whole Layer 2 palette, all 64 colour families of 4 entries
(SHADE_DARK, SHADE_FACE, SHADE_ROOF and the fixed one: palette entries
family*4 .. family*4+3), each r, g, b 0..7.  None may be Layer 2's
transparent colour.  The map editor starts it from the city's palette
(generated, with the city's hand-set shades) and changes only the first 3 of
a family; family 00's 4th entry is the sky (SKY_COL), as in the city's.

gentables.py turns each into ZPDATA/LEVELnn.ZPP (binary):
  +0   4    "ZPPL"
  +4   1    format version (1)
  +5   1    level number
  +6   2    (reserved, 0)
  +8   512  Layer 2 palette: 256 RRRGGGBB / low-blue-bit pairs (as NextReg $44)
load_level (level_load.asm) loads it, if there is one, after the city's
palette, in its place.  A level without one plays in its city's palette.
"""
import json
import os

FORMAT = "Z-Police level palette"
VERSION = 1
FAMILIES = 64
MAGIC = b"ZPPL"
BIN_VERSION = 1
BIN_SIZE = 8 + 512


def path_for(level_dir, lv):
    """A level's palette file: levels/LEVELnn_PAL.json."""
    return os.path.join(level_dir, f"LEVEL{lv:02d}_PAL.json")


def is_transparent(c):
    """(r, g, b) 0..7 is Layer 2's transparent colour ($E3): never shown."""
    r, g, b = c
    return r == 7 and g == 0 and b >> 1 == 3


def load(path):
    """levels/LEVELnn_PAL.json -> dict: level, city, pal (256 (r, g, b)).
    ValueError if malformed."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if d.get("format") != FORMAT:
        raise ValueError(f"{path}: not a {FORMAT} file")
    fams = d.get("families") or {}
    pal = [None] * 256
    for k, cols in fams.items():
        try:
            fam = int(k)
            cols = [tuple(int(v) for v in c) for c in cols]
        except (TypeError, ValueError):
            raise ValueError(f"{path}: family {k!r}: 4 colours, [r, g, b] each")
        if not 0 <= fam < FAMILIES or len(cols) != 4 or any(len(c) != 3 for c in cols):
            raise ValueError(f"{path}: family {k!r}: families 00..63, 4 colours, [r, g, b] each")
        pal[fam * 4:fam * 4 + 4] = cols
    missing = sorted({i // 4 for i, c in enumerate(pal) if c is None})
    if missing:
        raise ValueError(f"{path}: every family 00..63 is needed: missing "
                         + ", ".join(f"{f:02d}" for f in missing[:8]) + ("..." if len(missing) > 8 else ""))
    return {"level": int(d.get("level", 0)), "city": int(d.get("city", 0)), "pal": pal}


def text(lv, city, pal):
    """A level's palette file's text (256 (r, g, b)), one family a line."""
    lines = [f'  "{f:02d}": ' + json.dumps([list(c) for c in pal[f * 4:f * 4 + 4]])
             for f in range(FAMILIES)]
    return ('{\n "format": "%s", "version": %d,\n "level": %d, "city": %d,\n "families": {\n'
            % (FORMAT, VERSION, lv, city) + ",\n".join(lines) + "\n }\n}\n")


def save(path, lv, city, pal):
    """Write a level's palette (256 (r, g, b)) as levels/LEVELnn_PAL.json
    (or a vision palette, levels/LEVELnn_NVG.json ...: tools/visionpal.py)."""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text(lv, city, pal))


def problems(lv, d, city=None):
    """The problems with a loaded level palette (load's dict) for level lv
    (of city `city`, if given), as messages."""
    errs = []
    if d["level"] != lv:
        errs.append(f"it says level {d['level']}, not {lv}")
    if city is not None and d["city"] != city:
        errs.append(f"it says city {d['city']}, but level {lv} is in city {city}")
    for i, c in enumerate(d["pal"]):
        if any(not 0 <= v <= 7 for v in c):
            errs.append(f"family {i // 4:02d} colour {i % 4}: r, g, b are 0..7")
        elif is_transparent(c):
            errs.append(f"family {i // 4:02d} colour {i % 4}: {c} is the transparent colour")
    return errs


def pal_pair(c):
    r, g, b = c
    return bytes(((r << 5) | (g << 2) | (b >> 1), b & 1))


def binary(lv, pal):
    """ZPDATA/LEVELnn.ZPP's bytes."""
    data = MAGIC + bytes((BIN_VERSION, lv, 0, 0)) + b"".join(pal_pair(c) for c in pal)
    assert len(data) == BIN_SIZE
    return data
