"""Images for the 320x256 screens (ZPDATA/*.ZPI): read, write, check, and the
drawing operations the screen editor and the image generators share.

The game draws one with l320_image (layer2-320x256.asm), read from the SD
card a strip of columns at a time when the screen needs it (the load-out
screen: ZPDATA/VTOL.ZPI).  tools/screen_editor.py edits them;
tools/vtol_schematic.py makes the load-out's VTOL.

An image is a whole 320x256 screen to the editor; the file keeps only the
smallest box round the pixels drawn, and where it goes on the screen.
Format (little-endian):
  +0   4    "ZPIM"
  +4   1    VERSION
  +5   2    x of the box's left column (0-319)
  +7   1    y of its top row (0-255)
  +8   2    width  (1-320; x + width <= 320)
  +10  2    height (1-256; y + height <= 256)
  +12  4    0
  +16       the pixels, column by column (the screen's own order: 320x256
            Layer 2 is column-major), each column top to bottom; a colour
            is RRRGGGBB (the screens' palette), CLEAR ($E3, the transparency
            colour) leaves the screen as it is
"""
import os
from collections import deque

MAGIC = b"ZPIM"
VERSION = 1
HEADER = 16
SW, SH = 320, 256
CLEAR = 0xE3
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "ZPDATA")


def rgb(c):
    """RRRGGGBB -> (r, g, b), 0-7 each (blue as the Next widens it)"""
    b = c & 3
    return c >> 5, (c >> 2) & 7, (b << 1) | (1 if b else 0)


def hexc(c):
    r, g, b = rgb(c)
    return "#%02x%02x%02x" % (r * 255 // 7, g * 255 // 7, b * 255 // 7)


class Image:
    """A 320x256 screen of colours, CLEAR where nothing is drawn"""

    def __init__(self):
        self.px = bytearray([CLEAR]) * (SW * SH)

    def get(self, x, y):
        return self.px[y * SW + x] if 0 <= x < SW and 0 <= y < SH else CLEAR

    def set(self, x, y, c):
        if 0 <= x < SW and 0 <= y < SH:
            self.px[y * SW + x] = c

    def copy(self):
        im = Image()
        im.px[:] = self.px
        return im

    # --- drawing ------------------------------------------------------------
    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx, sy = (1 if x1 >= x0 else -1), (1 if y1 >= y0 else -1)
        err = dx - dy
        while True:
            self.set(x0, y0, c)
            if (x0, y0) == (x1, y1):
                return
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    def rect(self, x0, y0, x1, y1, c, filled=False):
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if filled or x in (x0, x1) or y in (y0, y1):
                    self.set(x, y, c)

    def ellipse(self, x0, y0, x1, y1, c, filled=False):
        """In the box (x0, y0)-(x1, y1)"""
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rx, ry = max((x1 - x0) / 2, 0.5), max((y1 - y0) / 2, 0.5)
        inside = set()
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if ((x - cx) / (rx + 0.5)) ** 2 + ((y - cy) / (ry + 0.5)) ** 2 <= 1:
                    inside.add((x, y))
        for x, y in inside:
            edge = any((x + dx, y + dy) not in inside for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if filled or edge:
                self.set(x, y, c)

    def polygon(self, pts, c, filled=False):
        """A closed polygon: its outline, or filled (scan lines, the outline
        included)"""
        if filled:
            ys = [y for _, y in pts]
            for y in range(min(ys), max(ys) + 1):
                xs = []
                for (ax, ay), (bx, by) in zip(pts, pts[1:] + pts[:1]):
                    if ay != by and min(ay, by) <= y < max(ay, by):
                        xs.append(ax + (y + 0.5 - ay) * (bx - ax) / (by - ay))
                xs.sort()
                for a, b in zip(xs[::2], xs[1::2]):
                    for x in range(round(a), round(b) + 1):
                        self.set(x, y, c)
        for (ax, ay), (bx, by) in zip(pts, pts[1:] + pts[:1]):
            self.line(ax, ay, bx, by, c)

    def fill(self, x, y, c):
        """Flood fill: the area of (x, y)'s colour, joined side to side"""
        old = self.get(x, y)
        if old == c or not (0 <= x < SW and 0 <= y < SH):
            return
        q = deque([(x, y)])
        while q:
            x, y = q.popleft()
            if 0 <= x < SW and 0 <= y < SH and self.px[y * SW + x] == old:
                self.px[y * SW + x] = c
                q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    # --- files --------------------------------------------------------------
    def box(self):
        """The smallest box round the pixels drawn: (x, y, w, h), or None"""
        x0 = y0 = None
        x1 = y1 = -1
        for y in range(SH):
            row = self.px[y * SW:(y + 1) * SW]
            if row.count(CLEAR) == SW:
                continue
            first = next(x for x in range(SW) if row[x] != CLEAR)
            last = next(x for x in range(SW - 1, -1, -1) if row[x] != CLEAR)
            y0 = y if y0 is None else y0
            y1 = y
            x0 = first if x0 is None else min(x0, first)
            x1 = max(x1, last)
        if y0 is None:
            return None
        return x0, y0, x1 - x0 + 1, y1 - y0 + 1

    def to_bytes(self):
        b = self.box()
        if b is None:
            raise ValueError("nothing drawn")
        x, y, w, h = b
        out = bytearray(MAGIC + bytes([VERSION]) + x.to_bytes(2, "little") + bytes([y])
                        + w.to_bytes(2, "little") + h.to_bytes(2, "little") + bytes(4))
        for cx in range(x, x + w):
            out += bytes(self.px[cy * SW + cx] for cy in range(y, y + h))
        return bytes(out)

    @classmethod
    def from_bytes(cls, data):
        x, y, w, h = check(data)
        im = cls()
        p = HEADER
        for cx in range(x, x + w):
            for cy in range(y, y + h):
                im.px[cy * SW + cx] = data[p]
                p += 1
        return im

    def save(self, path):
        with open(path, "wb") as fh:
            fh.write(self.to_bytes())

    @classmethod
    def load(cls, path):
        with open(path, "rb") as fh:
            return cls.from_bytes(fh.read())


def check(data):
    """(x, y, w, h) of an image the game takes; ValueError if it isn't one"""
    if data[:4] != MAGIC:
        raise ValueError("not an image file (magic)")
    if data[4] != VERSION:
        raise ValueError(f"version {data[4]}, not {VERSION}")
    x = int.from_bytes(data[5:7], "little")
    y = data[7]
    w = int.from_bytes(data[8:10], "little")
    h = int.from_bytes(data[10:12], "little")
    if not (1 <= w and 1 <= h and x + w <= SW and y + h <= SH):
        raise ValueError(f"box ({x}, {y}) {w} x {h} not on the screen")
    if len(data) != HEADER + w * h:
        raise ValueError(f"{len(data)} bytes, not {HEADER + w * h}")
    return x, y, w, h
