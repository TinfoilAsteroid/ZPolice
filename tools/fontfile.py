"""The screens' fonts: read, write, check, and the designs they start from.

Two fonts, each a file the game loads at start-up (fonts_load,
layer2-320x256.asm), edited with tools/font_editor.py:
  ZPDATA/FONT8.ZPF   the 8x8 font (F8): every text screen, the ULA ones and
                     the HUD too (its glyphs are copied over the built-in
                     font8, text.asm), and the dense lists of the 320x256
                     ones (with its gradients there).  gentables.py builds
                     the built-in font8 (tables_font.inc) from this file, so
                     without it at run time the game has the one it was
                     built with.
  ZPDATA/FONT12.ZPF  the large font (F12): the 320x256 screens' titles, help
                     and messages; without it each large cell gets the 8x8
                     glyph.

Format (little-endian):
  +0   4    "ZPFN"
  +4   1    VERSION
  +5   1    cell width in pixels  (8 / 12)
  +6   1    cell height in pixels (8 / 10)
  +7   1    first character (32: space)
  +8   1    characters (64: space to _ / 59: space to Z)
  +9   1    bytes per row (1 / 2)
  +10  1    gradients (1..GRAD_MAX)
  +11  1    0
  +12       the glyphs: count * height rows of bytes-per-row bytes, pixel 0
            the top bit of the row's first byte (1: ink, 0: paper)
  then      each gradient: its base colour (the text colour asked for), then
            a colour for each row of the cell, top first (RRRGGGBB)
On the 320x256 screens text in a colour with no gradient is drawn in that
colour, flat; the ULA draws the 8x8 font flat in its attribute colour.  Lower
case is drawn as upper case; a character outside the font as a space.
"""
import os

MAGIC = b"ZPFN"
VERSION = 1
GRAD_MAX = 8
HEADER = 12
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Spec:
    """One font's shape: its cell, characters and file"""

    def __init__(self, name, w, h, first, count, file, art, art_y, label):
        self.name, self.W, self.H, self.FIRST, self.COUNT = name, w, h, first, count
        self.BPR = (w + 7) // 8
        self.PATH = os.path.join(ROOT, "ZPDATA", file)
        self.art, self.art_y, self.label = art, art_y, label
        self.SIZE_MAX = HEADER + count * h * self.BPR + GRAD_MAX * (1 + h)

    def header(self):
        return (VERSION, self.W, self.H, self.FIRST, self.COUNT, self.BPR)

    def chars(self):
        return [chr(self.FIRST + i) for i in range(self.COUNT)]


# The 8x8 design: 7 x 7 glyphs ('#' ink) in rows 1-7 of the cell (row 0
# and column 7 clear), in the large font's style: 2-pixel uprights, 1-pixel
# bars, cut corners.
ART8 = {
    " ": [""] * 7,
    "!": ["  ##"] * 4 + ["", "  ##", "  ##"],
    '"': [" ## ##", " ## ##", "", "", "", "", ""],
    "%": ["##   ##", "##  ##", "   ##", "  ##", " ##", "##  ##", "##   ##"],
    "'": ["  ##", "  ##", "", "", "", "", ""],
    "(": ["   ##", "  ##", "  ##", "  ##", "  ##", "  ##", "   ##"],
    ")": [" ##", "  ##", "  ##", "  ##", "  ##", "  ##", " ##"],
    "*": ["", "## # ##", " #####", "#######", " #####", "## # ##", ""],
    "+": ["", "  ##", "  ##", "######", "  ##", "  ##", ""],
    ",": ["", "", "", "", "  ##", "  ##", " ##"],
    "-": ["", "", "", " #####", "", "", ""],
    ".": ["", "", "", "", "", "  ##", "  ##"],
    "/": ["     ##", "    ##", "   ##", "  ##", " ##", "##", "#"],
    "0": [" #####", "##   ##", "##  ###", "## # ##", "###  ##", "##   ##", " #####"],
    "1": ["  ##", " ###", "  ##", "  ##", "  ##", "  ##", " ####"],
    "2": [" #####", "     ##", "     ##", " #####", "##", "##", "#######"],
    "3": ["######", "     ##", "     ##", "  ####", "     ##", "     ##", "######"],
    "4": ["##   ##", "##   ##", "##   ##", "#######", "     ##", "     ##", "     ##"],
    "5": ["#######", "##", "##", "######", "     ##", "     ##", "######"],
    "6": [" #####", "##", "##", "######", "##   ##", "##   ##", " #####"],
    "7": ["#######", "     ##", "    ##", "   ##", "  ##", "  ##", "  ##"],
    "8": [" #####", "##   ##", "##   ##", " #####", "##   ##", "##   ##", " #####"],
    "9": [" #####", "##   ##", "##   ##", " ######", "     ##", "     ##", " #####"],
    ":": ["", "  ##", "  ##", "", "  ##", "  ##", ""],
    ";": ["", "  ##", "  ##", "", "  ##", "  ##", " ##"],
    "<": ["    ##", "   ##", "  ##", " ##", "  ##", "   ##", "    ##"],
    "=": ["", "", "######", "", "######", "", ""],
    ">": [" ##", "  ##", "   ##", "    ##", "   ##", "  ##", " ##"],
    "?": [" #####", "##   ##", "     ##", "   ###", "  ##", "", "  ##"],
    "A": [" #####", "##   ##", "##   ##", "#######", "##   ##", "##   ##", "##   ##"],
    "B": ["######", "##   ##", "##   ##", "######", "##   ##", "##   ##", "######"],
    "C": [" ######", "##", "##", "##", "##", "##", " ######"],
    "D": ["######"] + ["##   ##"] * 5 + ["######"],
    "E": ["#######", "##", "##", "######", "##", "##", "#######"],
    "F": ["#######", "##", "##", "######", "##", "##", "##"],
    "G": [" ######", "##", "##", "##  ###", "##   ##", "##   ##", " #####"],
    "H": ["##   ##"] * 3 + ["#######"] + ["##   ##"] * 3,
    "I": [" ####", "  ##", "  ##", "  ##", "  ##", "  ##", " ####"],
    "J": ["  #####", "     ##", "     ##", "     ##", "##   ##", "##   ##", " #####"],
    "K": ["##   ##", "##  ##", "## ##", "#####", "##  ##", "##   ##", "##   ##"],
    "L": ["##"] * 6 + ["#######"],
    "M": ["##   ##", "### ###", "#######", "## # ##", "##   ##", "##   ##", "##   ##"],
    "N": ["##   ##", "###  ##", "#### ##", "## ####", "##  ###", "##   ##", "##   ##"],
    "O": [" #####"] + ["##   ##"] * 5 + [" #####"],
    "P": ["######", "##   ##", "##   ##", "######", "##", "##", "##"],
    "Q": [" #####", "##   ##", "##   ##", "##   ##", "## # ##", "##  ##", " ### ##"],
    "R": ["######", "##   ##", "##   ##", "######", "## ##", "##  ##", "##   ##"],
    "S": [" ######", "##", "##", " #####", "     ##", "     ##", "######"],
    "T": ["######"] + ["  ##"] * 6,
    "U": ["##   ##"] * 6 + [" #####"],
    "V": ["##   ##"] * 4 + [" ## ##", "  ###", "   #"],
    "W": ["##   ##"] * 3 + ["## # ##", "#######", "### ###", "##   ##"],
    "X": ["##   ##", "##   ##", " ## ##", "  ###", " ## ##", "##   ##", "##   ##"],
    "Y": ["##   ##", "##   ##", " ## ##", "  ###", "  ##", "  ##", "  ##"],
    "Z": ["#######", "    ##", "   ##", "  ##", " ##", "##", "#######"],
    "[": [" ####", " ##", " ##", " ##", " ##", " ##", " ####"],
    "]": [" ####", "   ##", "   ##", "   ##", "   ##", "   ##", " ####"],
    "_": ["", "", "", "", "", "", "#######"],
}

ART12 = {
    " ": [""] * 9,
    "!": ["    ##"] * 6 + [""] + ["    ##"] * 2,
    '"': ["  ##  ##"] * 3 + [""] * 6,
    "'": ["    ##"] * 3 + [""] * 6,
    "(": ["     ###", "    ##", "    ##", "    ##", "    ##", "    ##", "    ##", "    ##", "     ###"],
    ")": ["  ###", "    ##", "    ##", "    ##", "    ##", "    ##", "    ##", "    ##", "  ###"],
    "+": ["", "", "    ##", "    ##", "  ######", "    ##", "    ##", "", ""],
    ",": [""] * 6 + ["    ##", "    ##", "   ##"],
    "-": ["", "", "", "", "  ######", "", "", "", ""],
    ".": [""] * 7 + ["    ##", "    ##"],
    "/": [" " * (8 - k) + "##" for k in range(9)],
    "0": [" ########", "##      ##", "##      ##", "##      ##", "##  ##  ##",
          "##      ##", "##      ##", "##      ##", " ########"],
    "1": ["   ###", "  ####", "    ##", "    ##", "    ##", "    ##", "    ##", "    ##", "  ######"],
    "2": [" ########", "        ##", "        ##", "        ##", " ########",
          "##", "##", "##", "##########"],
    "3": ["#########", "        ##", "        ##", "        ##", "  #######",
          "        ##", "        ##", "        ##", "#########"],
    "4": ["##      ##"] * 4 + ["##########"] + ["        ##"] * 4,
    "5": ["##########", "##", "##", "##", "#########", "        ##", "        ##", "        ##", "#########"],
    "6": [" ########", "##", "##", "##", "#########", "##      ##", "##      ##", "##      ##", " ########"],
    "7": ["##########", "        ##", "       ##", "      ##", "     ##", "    ##", "    ##", "    ##", "    ##"],
    "8": [" ########", "##      ##", "##      ##", "##      ##", " ########",
          "##      ##", "##      ##", "##      ##", " ########"],
    "9": [" ########", "##      ##", "##      ##", "##      ##", " #########",
          "        ##", "        ##", "        ##", " ########"],
    ":": ["", "", "    ##", "    ##", "", "", "    ##", "    ##", ""],
    ";": ["", "", "    ##", "    ##", "", "", "    ##", "    ##", "   ##"],
    "=": ["", "", "", "  ######", "", "  ######", "", "", ""],
    "?": [" ########", "##      ##", "        ##", "     ####", "    ##", "    ##", "", "    ##", "    ##"],
    "A": [" ########"] + ["##      ##"] * 3 + ["##########"] + ["##      ##"] * 4,
    "B": ["#########"] + ["##      ##"] * 3 + ["#########"] + ["##      ##"] * 3 + ["#########"],
    "C": [" #########"] + ["##"] * 7 + [" #########"],
    "D": ["#########"] + ["##      ##"] * 7 + ["#########"],
    "E": ["##########"] + ["##"] * 3 + ["########"] + ["##"] * 3 + ["##########"],
    "F": ["##########"] + ["##"] * 3 + ["########"] + ["##"] * 4,
    "G": [" #########", "##", "##", "##", "##   #####", "##      ##", "##      ##", "##      ##", " ########"],
    "H": ["##      ##"] * 4 + ["##########"] + ["##      ##"] * 4,
    "I": ["  ######"] + ["    ##"] * 7 + ["  ######"],
    "J": ["    ######"] + ["        ##"] * 5 + ["##      ##"] * 2 + [" ########"],
    "K": ["##      ##", "##     ##", "##    ##", "##   ##", "#######", "##    ##", "##     ##",
          "##      ##", "##      ##"],
    "L": ["##"] * 8 + ["##########"],
    "M": ["###    ###", "####  ####", "## #### ##", "##  ##  ##"] + ["##      ##"] * 5,
    "N": ["###     ##", "####    ##", "## ##   ##", "##  ##  ##", "##   ## ##", "##    ####",
          "##     ###", "##      ##", "##      ##"],
    "O": [" ########"] + ["##      ##"] * 7 + [" ########"],
    "P": ["#########"] + ["##      ##"] * 3 + ["#########"] + ["##"] * 4,
    "Q": [" ########"] + ["##      ##"] * 4 + ["##   ## ##", "##    ### ", "##     ## ", " ##### ###"],
    "R": ["#########"] + ["##      ##"] * 3 + ["#########", "##    ##", "##     ##", "##      ##", "##      ##"],
    "S": [" #########", "##", "##", "##", " ########", "        ##", "        ##", "        ##", "#########"],
    "T": ["##########"] + ["    ##"] * 8,
    "U": ["##      ##"] * 8 + [" ########"],
    "V": ["##      ##"] * 5 + [" ##    ##", "  ##  ##", "   ####", "    ##"],
    "W": ["##      ##"] * 5 + ["##  ##  ##", "## #### ##", "####  ####", "###    ###"],
    "X": ["##      ##", " ##    ##", "  ##  ##", "   ####", "    ##", "   ####", "  ##  ##",
          " ##    ##", "##      ##"],
    "Y": ["##      ##", " ##    ##", "  ##  ##", "   ####"] + ["    ##"] * 5,
    "Z": ["##########", "       ##", "      ##", "     ##", "    ##", "   ##", "  ##", " ##", "##########"],
}

# The 12x10 design: 10 x 9 glyphs in rows 0-8 (a column and a row of gap
# after each).
F12 = Spec("12x10", 12, 10, 32, 59, "FONT12.ZPF", ART12, 0, "large font (12x10)")
F8 = Spec("8x8", 8, 8, 32, 64, "FONT8.ZPF", ART8, 1, "8x8 font")
SPECS = (F8, F12)

# (the large font's, as before: the 320x256 page's names)
W, H, FIRST, COUNT, BPR = F12.W, F12.H, F12.FIRST, F12.COUNT, F12.BPR
SIZE_MAX, PATH = F12.SIZE_MAX, F12.PATH


def art_rows(spec, art):
    """The design's strings -> spec.H rows of spec.W booleans"""
    rows = [[False] * spec.W for _ in range(spec.H)]
    for y, s in enumerate(art):
        for k in range(min(len(s), spec.W)):
            rows[y + spec.art_y][k] = s[k] == "#"
    return rows


def rgb(c):
    """RRRGGGBB -> (r, g, b), 0-7 each (blue as the Next widens it)"""
    b = c & 3
    return c >> 5, (c >> 2) & 7, (b << 1) | (1 if b else 0)


def pack(r, g, b):
    return (min(7, max(0, round(r))) << 5) | (min(7, max(0, round(g))) << 2) | min(3, max(0, round(b / 7 * 3)))


def ramp(base, h=10):
    """A top-to-bottom shade ramp of h rows for a colour: lighter at the top,
    the colour itself in the middle, darker (to 0.6 of it) at the bottom"""
    r, g, b = rgb(base)
    out = []
    for row in range(h):
        if row < 2:                     # towards white
            k = 0.45 if row == 0 else 0.22
            out.append(pack(r + (7 - r) * k, g + (7 - g) * k, b + (7 - b) * k))
        else:
            k = 1 - 0.4 * max(0, row - 3) / max(1, h - 5)
            out.append(pack(r * k, g * k, b * k))
    return out


# The text colours of the screens (SCR_TEXT, SCR_TITLE, SCR_OK, SCR_BAD,
# SCR_HELP: layer2-320x256.asm) and amber
DEFAULT_BASES = [0xFF, 0xFC, 0x1C, 0xE0, 0x1F, 0xF4]


class Font:
    def __init__(self, spec=F12):
        self.spec = spec
        self.glyphs = {}                # character -> H rows of W booleans
        self.grads = []                 # [base, [H colours]]

    @classmethod
    def default(cls, spec=F12):
        f = cls(spec)
        for ch in spec.chars():
            f.glyphs[ch] = art_rows(spec, spec.art.get(ch, []))
        f.grads = [[b, ramp(b, spec.H)] for b in DEFAULT_BASES]
        return f

    def to_bytes(self):
        sp = self.spec
        if not 1 <= len(self.grads) <= GRAD_MAX:
            raise ValueError(f"1 to {GRAD_MAX} gradients, not {len(self.grads)}")
        out = bytearray(MAGIC + bytes(sp.header() + (len(self.grads), 0)))
        for ch in sp.chars():
            for row in self.glyphs[ch]:
                v = 0
                for k, on in enumerate(row):
                    if on:
                        v |= 1 << (8 * sp.BPR - 1 - k)
                out += v.to_bytes(sp.BPR, "big")
        for base, cols in self.grads:
            out += bytes([base] + list(cols))
        return bytes(out)

    @classmethod
    def from_bytes(cls, data, spec=None):
        spec = spec or spec_of(data)
        check(data, spec)
        f = cls(spec)
        p = HEADER
        top = 8 * spec.BPR - 1
        for ch in spec.chars():
            rows = []
            for _ in range(spec.H):
                v = int.from_bytes(data[p:p + spec.BPR], "big")
                p += spec.BPR
                rows.append([bool(v >> (top - k) & 1) for k in range(spec.W)])
            f.glyphs[ch] = rows
        for _ in range(data[10]):
            f.grads.append([data[p], list(data[p + 1:p + 1 + spec.H])])
            p += 1 + spec.H
        return f

    def save(self, path=None):
        with open(path or self.spec.PATH, "wb") as fh:
            fh.write(self.to_bytes())

    @classmethod
    def load(cls, path=PATH, spec=None):
        with open(path, "rb") as fh:
            return cls.from_bytes(fh.read(), spec)


def spec_of(data):
    """The font (F8 or F12) a file's header says it is"""
    for sp in SPECS:
        if tuple(data[4:10]) == sp.header():
            return sp
    raise ValueError(f"not one of this game's fonts: {tuple(data[4:10])}")


def check(data, spec=None):
    """Raise ValueError unless data is a font the game takes (as spec, if
    given)"""
    if data[:4] != MAGIC:
        raise ValueError("not a font file (magic)")
    spec = spec or spec_of(data)
    if tuple(data[4:10]) != spec.header():
        raise ValueError(f"not the {spec.label}: {tuple(data[4:10])}")
    n = data[10]
    if not 1 <= n <= GRAD_MAX:
        raise ValueError(f"{n} gradients")
    if len(data) != HEADER + spec.COUNT * spec.H * spec.BPR + n * (1 + spec.H):
        raise ValueError(f"{len(data)} bytes")


def font8_rows(path=F8.PATH):
    """The 8x8 font's bytes, 8 a character (gentables.py: tables_font.inc):
    the file's, or the default design's if there's no usable file"""
    try:
        f = Font.load(path, F8)
    except (OSError, ValueError):
        f = Font.default(F8)
    return Font.to_bytes(f)[HEADER:HEADER + F8.COUNT * F8.H]


if __name__ == "__main__":
    import sys
    for sp in SPECS:
        if "--default" in sys.argv or not os.path.exists(sp.PATH):
            Font.default(sp).save()
            print("wrote", sp.PATH)
        else:
            Font.load(sp.PATH, sp)
            print(sp.PATH, "is fine")
