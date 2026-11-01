"""Z-Police level files: the format shared by gentables.py, the map editor
(tools/map_editor.py) and tools/check_maps.py.

A level's source is levels/LEVELnn.TXL, a text file (level_text writes it,
level_parse reads it, level_check checks it); gentables.py turns it into the
binary ZPDATA/LEVELnn.ZPL the game loads (level_record, level_file):

    LEVEL n / CITY n / NAME name
    ZOMBIES n / WAVES n / FAST n / VIEW n
    WAVE 1 GHOST 3 GHOUL 1    one line a wave: up to 5 type / count pairs
    CHANGES n                 then n lines: x z code family (map changes)
    END

ZPDATA/LEVELnn.ZPL: "ZPLV", version 2, the city number, the level record
(levels.asm, 113 bytes: level, name (8), zombies, waves, fast, view, then 10
waves of 5 special types (255 none) and 5 counts), the number of map
changes, then x, z, cell code, city_col each.
"""
import citymap

GRID = citymap.GRID
MAP_CHARS = citymap.MAP_CHARS
GROUND_IDX = citymap.GROUND_IDX
PAD_X, PAD_Z = citymap.PAD_X, citymap.PAD_Z
VIEW_R = 6                              # the most draw distance (zpolice.asm)
NZOMB = 30                              # zombies a wave at most (zombie.asm)
NSPEC = 8                               # specials at once at most
LVF_CHG_MAX = 64                        # map changes at most (level_load.asm)


def col_text(c):
    """A city_col byte as its two-character field (.. for none)."""
    if c == GROUND_IDX:
        return ".."
    assert c % 4 == 0, c
    return f"{c // 4:02d}"


def col_value(t):
    return GROUND_IDX if t == ".." else int(t) * 4


def text_lines(text):
    """The lines that matter: no comments, no blank lines."""
    return [ln.rstrip() for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith(";")]


def field(line, k):
    """A "KEY value" line's value; ValueError if its key isn't k."""
    w = line.split(None, 1)
    if w[0] != k:
        raise ValueError(f"expected {k}: {line!r}")
    return w[1] if len(w) > 1 else ""


LEVEL_KEYS = ["ZOMBIES", "WAVES", "FAST", "VIEW"]
LEVEL_VERSION = 2                      # the level files' format (level_load.asm)
LV_MAX_WAVES, LV_SPEC_SLOTS = 10, 5    # levels.asm
SPEC_NAMES = ["GHOST", "BANSHEE", "GHOUL"]     # the special types, by id (SPEC_*)
SPEC_NONE = 255

def level_record(lv, name, values, waves_specials):
    """The level record (levels.asm, 113 bytes): values as LEVEL_KEYS;
    waves_specials, a list per wave of (type id, count) pairs."""
    zomb, waves, fast, view = values
    assert 1 <= waves <= LV_MAX_WAVES and len(waves_specials) == waves
    rec = bytes((lv,)) + name.ljust(8).encode() + bytes((zomb, waves, fast, view))
    for w in range(LV_MAX_WAVES):
        sp = waves_specials[w] if w < waves else []
        assert len(sp) <= LV_SPEC_SLOTS, (lv, w + 1, sp)
        ids = [t for t, _ in sp] + [SPEC_NONE] * (LV_SPEC_SLOTS - len(sp))
        counts = [n for _, n in sp] + [0] * (LV_SPEC_SLOTS - len(sp))
        rec += bytes(ids) + bytes(counts)
    assert len(rec) == 113
    return rec

def level_file(lv, cn, rec, changes):
    return b"ZPLV" + bytes((LEVEL_VERSION, cn)) + rec + bytes((len(changes),)) + b"".join(bytes(c) for c in changes)

def level_text(lv, cn, name, values, waves_specials, changes):
    out = [f"; Z-Police level {lv}: LEVEL{lv:02d}.TXL, the text form of LEVEL{lv:02d}.ZPL",
           f"; The source is levels/LEVEL{lv:02d}.TXL: edit that one, then build.bat",
           "; (gentables.py checks it and makes ZPDATA/ from it; its comments have",
           "; the format)",
           f"LEVEL {lv}", f"CITY {cn}", f"NAME {name}"]
    out += [f"{k} {v}" for k, v in zip(LEVEL_KEYS, values)]
    out += ["", f"; special monsters, one line a wave (1 is the level's start): WAVE n,",
            f"; then up to {LV_SPEC_SLOTS} type / count pairs; types: " + ", ".join(SPEC_NAMES)]
    out += [" ".join([f"WAVE {w + 1}"] + [f"{SPEC_NAMES[t]} {n}" for t, n in sp])
            for w, sp in enumerate(waves_specials)]
    out += ["", "; cells of the city's map changed for this level: x z code family",
            f"CHANGES {len(changes)}"]
    out += [f"{x} {z} {MAP_CHARS[code]} {col_text(c)}" for x, z, code, c in changes]
    out += ["END", ""]
    return "\n".join(out)

def level_parse(text):
    """LEVELnn.TXL -> its fields: lv, cn, name, values (as LEVEL_KEYS),
    waves_specials (per wave, (type id, count) pairs), changes ((x, z, cell
    code, city_col)).  ValueError, saying which line, if it can't be read."""
    ln = text_lines(text)
    i = 0
    def line():
        if i >= len(ln):
            raise ValueError("the file ends too soon (no END?)")
        return ln[i]
    def num(k):
        v = field(line(), k)
        try:
            return int(v)
        except ValueError:
            raise ValueError(f"{k} needs a number: {line()!r}")
    lv = num("LEVEL"); i += 1
    cn = num("CITY"); i += 1
    name = field(line(), "NAME"); i += 1
    values = []
    for k in LEVEL_KEYS:
        values.append(num(k)); i += 1
    waves_specials = []
    for w in range(max(0, min(values[1], LV_MAX_WAVES))):   # a WAVE line a wave
        f = line().split()
        if f[:2] != ["WAVE", str(w + 1)] or len(f) % 2:
            raise ValueError(f"expected WAVE {w + 1} then type / count pairs: {line()!r}")
        sp = []
        for j in range(2, len(f), 2):
            if f[j] not in SPEC_NAMES or not f[j + 1].isdigit():
                raise ValueError(f"wave {w + 1}: {f[j]} {f[j + 1]}: a type ({', '.join(SPEC_NAMES)}) "
                                 "and a count expected")
            sp.append((SPEC_NAMES.index(f[j]), int(f[j + 1])))
        waves_specials.append(sp)
        i += 1
    nch = num("CHANGES"); i += 1
    changes = []
    for j in range(nch):
        f = line().split()
        if len(f) != 4 or not f[0].isdigit() or not f[1].isdigit() or f[2] not in MAP_CHARS \
                or len(f[2]) != 1 or not (f[3] == ".." or f[3].isdigit()):
            raise ValueError(f"a map change is x z code family (e.g. 10 12 T 62): {line()!r}")
        changes.append((int(f[0]), int(f[1]), MAP_CHARS.index(f[2]), col_value(f[3])))
        i += 1
    if line() != "END":
        raise ValueError(f"expected END: {line()!r}")
    return dict(lv=lv, cn=cn, name=name, values=values, waves_specials=waves_specials, changes=changes)

def level_check(lv, d, cities):
    """The problems with level lv's fields d (level_parse); cities: each
    city's map (cells), by number."""
    errs = []
    zomb, waves, fast, view = d["values"]
    if d["lv"] != lv:
        errs.append(f"LEVEL {d['lv']}: this is level {lv}'s file")
    if d["cn"] not in cities:
        errs.append(f"CITY {d['cn']}: there are cities 1 to {len(cities)}")
    if len(d["name"]) > 8 or not d["name"].isascii():
        errs.append(f"NAME {d['name']!r}: at most 8 plain characters")
    if not 1 <= zomb <= 30:
        errs.append(f"ZOMBIES {zomb}: 1 to 30 a wave (NZOMB)")
    if not 1 <= waves <= LV_MAX_WAVES:
        errs.append(f"WAVES {waves}: 1 to {LV_MAX_WAVES}")
    if not 0 <= fast <= zomb:
        errs.append(f"FAST {fast}: 0 to ZOMBIES ({zomb})")
    if not 2 <= view <= VIEW_R:
        errs.append(f"VIEW {view}: a draw distance of 2 to {VIEW_R} tiles")
    for w, sp in enumerate(d["waves_specials"], 1):
        if len(sp) > LV_SPEC_SLOTS:
            errs.append(f"WAVE {w}: at most {LV_SPEC_SLOTS} types")
        if any(n > 255 for _, n in sp):
            errs.append(f"WAVE {w}: a count over 255")
        if sum(n for _, n in sp) > 8:
            errs.append(f"WAVE {w}: {sum(n for _, n in sp)} specials; at most 8 at once (NSPEC)")
    ch = d["changes"]
    if len(ch) > 64:
        errs.append(f"CHANGES {len(ch)}: at most 64 (LVF_CHG_MAX)")
    if d["cn"] in cities and not any(not 0 <= v < GRID for x, z, _, _ in ch for v in (x, z)):
        cells = list(cities[d["cn"]][0])
        fams = list(cities[d["cn"]][1])
        for x, z, code, col in ch:
            fam = None if col == GROUND_IDX else col // 4
            if code == citymap.PAD:
                errs.append(f"change {x} {z}: the landing pad can't be moved or added")
            elif code in (citymap.ROAD, citymap.VOID):
                if fam is not None:
                    errs.append(f"change {x} {z} {MAP_CHARS[code]}: a road or out of bounds takes .. (no colour)")
            elif code == citymap.TERRACE:
                if fam != citymap.TERRACE_FAMILY:
                    errs.append(f"change {x} {z} T: the terrace's colour is {citymap.TERRACE_FAMILY}")
            elif not citymap.is_bld_family(fam):
                errs.append(f"change {x} {z} {MAP_CHARS[code]}: a building takes a building colour "
                            f"(00..{citymap.BLD_FAMILIES - 1})")
            if (x, z) == (PAD_X, PAD_Z) and code != citymap.PAD:
                errs.append(f"change {x} {z}: that's the landing pad")
            cells[z * GRID + x], fams[z * GRID + x] = code, fam
        # the city as the level changes it: the map's own rules
        nb = len(citymap.barricades(cells))
        if nb > citymap.MAX_BARRICADES:
            errs.append(f"{nb} barricades with the changes: at most {citymap.MAX_BARRICADES}")
        bw = [(i % GRID, i // GRID) for i in citymap.bad_walls(cells, fams)]
        if bw:
            errs.append(f"the wall's colour off the perimeter wall with the changes, e.g. {bw[0]}")
    else:
        errs += [f"change {x} {z}: outside the {GRID} x {GRID} map" for x, z, _, _ in ch
                 if not (0 <= x < GRID and 0 <= z < GRID)]
    return errs

def level_from_text(text):
    """LEVELnn.TXL -> (level number, the LEVELnn.ZPL bytes)."""
    d = level_parse(text)
    rec = level_record(d["lv"], d["name"], d["values"], d["waves_specials"])
    return d["lv"], level_file(d["lv"], d["cn"], rec, d["changes"])


def read(path):
    """levels/LEVELnn.TXL -> its fields (level_parse).  OSError, ValueError."""
    with open(path, encoding="latin-1") as f:
        return level_parse(f.read())


def write(path, d):
    """Fields d (level_parse's) -> levels/LEVELnn.TXL."""
    text = level_text(d["lv"], d["cn"], d["name"], d["values"], d["waves_specials"], d["changes"])
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write(text)
